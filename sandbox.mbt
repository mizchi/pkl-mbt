///|
/// PKL-106: sandbox configuration consulted by the evaluator and the
/// CLI loader. Apple Pkl exposes three CLI knobs that shape what a
/// module can `import` or `read`:
///
///   - `--allowed-modules <pattern>`: a `|`-separated list of URI
///     prefixes that imports must match. When empty (the default)
///     imports are unrestricted.
///   - `--module-path <dir>`: extra directories searched when
///     resolving an unqualified import URI. Repeatable.
///   - `-p NAME=VALUE`: populate the `prop:` resolver so
///     `read("prop:NAME")` returns `VALUE`. Repeatable. Lifts `prop:`
///     into the `read` allow-list alongside `env:`.
///
/// The configuration is stored in module-level mutable state because
/// the CLI installs it once at startup and the evaluator threads it
/// through deep call paths that we don't want to rewrite to thread
/// an extra parameter. The shape mirrors how `env:` already reads
/// from process-global state (host environment variables); flipping
/// the storage to a `SandboxConfig` argument later is straightforward
/// once an embedded use case demands it.
priv struct SandboxConfig {
  mut props : Map[String, String]
  mut allowed_modules : Array[String]
  mut module_paths : Array[String]
  // PKL-150 (#258): package cache roots. The CLI can fill this cache
  // itself from registry metadata + zipballs; embedded callers may
  // still provide pre-extracted roots. A directory looks like
  // `<dir>/<path>/<name>@<version>/package/<files>`, with metadata in
  // the package root sibling (`<name>@<version>.json`).
  mut package_caches : Array[String]
  // PKL-148r: triple-dot import resolutions cached by the CLI's load
  // step (FS-based) so the IO-free analysis layer can map the same
  // `(from, ".../X")` pair back to the absolute path the CLI already
  // loaded into the session source store. Key shape is
  // `"<from>\n<uri>"`.
  triple_dot_resolutions : Map[String, String]
  read_resources : Map[String, SandboxResource]
  read_globs : Map[String, Array[SandboxResource]]
  import_globs : Map[String, Array[String]]
}

///|
pub(all) struct SandboxResource {
  uri : String
  resource_uri : String
  text : String
} derive(Eq, Debug)

///|
let sandbox_config : SandboxConfig = {
  props: Map([], capacity=8),
  allowed_modules: [],
  module_paths: [],
  package_caches: [],
  triple_dot_resolutions: Map([], capacity=8),
  read_resources: Map([], capacity=8),
  read_globs: Map([], capacity=8),
  import_globs: Map([], capacity=8),
}

///|
/// Replace the configured props map. Pass an empty map to clear.
pub fn configure_sandbox_props(props : Map[String, String]) -> Unit {
  sandbox_config.props = props
}

///|
/// Replace the configured allowed-modules pattern list. An empty
/// list disables the allow-list (everything is permitted).
pub fn configure_sandbox_allowed_modules(patterns : Array[String]) -> Unit {
  sandbox_config.allowed_modules = patterns
}

///|
/// Replace the configured module-path search list. Directories are
/// consulted in order when resolving an unqualified import.
pub fn configure_sandbox_module_paths(dirs : Array[String]) -> Unit {
  sandbox_config.module_paths = dirs
}

///|
/// Look up a `prop:` value installed via `-p NAME=VALUE`. Returns
/// `None` when the key is absent, which `eval_read_uri` translates
/// into a diagnostic mirroring the `env:` missing-variable path.
fn sandbox_lookup_prop(name : String) -> String? {
  sandbox_config.props.get(sandbox_percent_decode(name))
}

///|
fn sandbox_prop_entries() -> Array[(String, String)] {
  sandbox_config.props.to_array()
}

///|
fn sandbox_hex_value(c : UInt16) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn sandbox_percent_decode(s : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    if s[i] == '%' && i + 2 < s.length() {
      match (sandbox_hex_value(s[i + 1]), sandbox_hex_value(s[i + 2])) {
        (Some(hi), Some(lo)) => {
          buf.write_char((hi * 16 + lo).unsafe_to_char())
          i = i + 3
          continue
        }
        _ => ()
      }
    }
    buf.write_char(s[i].to_int().unsafe_to_char())
    i = i + 1
  }
  buf.to_string()
}

///|
fn sandbox_percent_encode_resource_key(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s.iter() {
    match c {
      ' ' => buf.write_string("%20")
      '[' => buf.write_string("%5B")
      ']' => buf.write_string("%5D")
      '\\' => buf.write_string("%5C")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn sandbox_glob_matches(pattern : String, text : String) -> Bool {
  sandbox_glob_matches_at(pattern, 0, text, 0)
}

///|
fn sandbox_glob_matches_at(
  pattern : String,
  pi : Int,
  text : String,
  ti : Int,
) -> Bool {
  if pi >= pattern.length() {
    return ti >= text.length()
  }
  if pattern[pi] == '*' {
    if pi + 1 < pattern.length() && pattern[pi + 1] == '*' {
      let mut j = ti
      while j <= text.length() {
        if sandbox_glob_matches_at(pattern, pi + 2, text, j) {
          return true
        }
        j = j + 1
      }
      return false
    }
    let mut j = ti
    while j <= text.length() {
      if sandbox_glob_matches_at(pattern, pi + 1, text, j) {
        return true
      }
      if j >= text.length() || text[j] == '/' {
        return false
      }
      j = j + 1
    }
    false
  } else if pattern[pi] == '[' {
    match sandbox_match_char_class(pattern, pi, text, ti) {
      Some(next_pi) => sandbox_glob_matches_at(pattern, next_pi, text, ti + 1)
      None => false
    }
  } else if ti < text.length() && pattern[pi] == text[ti] {
    sandbox_glob_matches_at(pattern, pi + 1, text, ti + 1)
  } else {
    false
  }
}

///|
fn sandbox_match_char_class(
  pattern : String,
  pi : Int,
  text : String,
  ti : Int,
) -> Int? {
  if ti >= text.length() {
    return None
  }
  let mut i = pi + 1
  let c = text[ti]
  let mut matched = false
  while i < pattern.length() && pattern[i] != ']' {
    if i + 2 < pattern.length() &&
      pattern[i + 1] == '-' &&
      pattern[i + 2] != ']' {
      if c >= pattern[i] && c <= pattern[i + 2] {
        matched = true
      }
      i = i + 3
    } else {
      if c == pattern[i] {
        matched = true
      }
      i = i + 1
    }
  }
  if i < pattern.length() && pattern[i] == ']' && matched {
    Some(i + 1)
  } else {
    None
  }
}

///|
/// True when `uri` is permitted by the current allow-list. An empty
/// allow-list means "no restriction" so the default CLI behaviour is
/// unchanged from before the slice. Each pattern is treated as a
/// literal URI prefix — the format matches Apple Pkl's
/// `|`-separated prefix lookup (e.g. `pkl:|file:|https:`).
///
/// Bare filesystem paths (no `scheme:` prefix) bypass the allow-list
/// because the check is intended for sandbox-relevant URIs that
/// cross trust boundaries (`https:`, `package:`, the stdlib `pkl:`,
/// etc.). The entrypoint and locally-rooted imports are already
/// gated by filesystem permissions and the user typing the path on
/// the command line, so re-checking them against the same allow-list
/// would force users to spell out every directory.
pub fn sandbox_is_module_allowed(uri : String) -> Bool {
  if sandbox_config.allowed_modules.length() == 0 {
    return true
  }
  match uri.find(":") {
    None => true
    Some(_) =>
      for pattern in sandbox_config.allowed_modules {
        if uri.has_prefix(pattern) {
          break true
        }
      } nobreak {
        false
      }
  }
}

///|
/// Iterate the configured `--module-path` directories in CLI order.
/// The loader prepends each directory to an unqualified import URI
/// and tries the resulting path; the first hit wins. Returning the
/// array directly keeps the loader free of an iterator wrapper.
pub fn sandbox_module_paths() -> Array[String] {
  sandbox_config.module_paths
}

///|
/// Replace the configured package-cache search list. See
/// `SandboxConfig.package_caches` for the layout each directory must
/// follow.
pub fn configure_sandbox_package_caches(dirs : Array[String]) -> Unit {
  sandbox_config.package_caches = dirs
}

///|
/// Iterate the configured `--package-cache` directories in CLI order.
pub fn sandbox_package_caches() -> Array[String] {
  sandbox_config.package_caches
}

///|
/// PKL-148r: register a triple-dot import resolution. Called by the
/// CLI loader after `@fs.path_exists` finds the matching ancestor
/// candidate, so the analysis-layer resolver can map the same
/// `(from, uri)` pair back to the same absolute path without
/// re-doing FS access.
pub fn register_triple_dot_resolution(
  from : String,
  uri : String,
  resolved : String,
) -> Unit {
  sandbox_config.triple_dot_resolutions[from + "\n" + uri] = resolved
}

///|
/// PKL-148r: look up a previously-registered triple-dot resolution.
/// Returns the absolute path the CLI loaded the module under, or
/// `None` if the CLI never saw this `(from, uri)` pair.
pub fn lookup_triple_dot_resolution(from : String, uri : String) -> String? {
  sandbox_config.triple_dot_resolutions.get(from + "\n" + uri)
}

///|
fn sandbox_io_key(from : String, uri : String) -> String {
  from + "\n" + uri
}

///|
pub fn reset_sandbox_io_cache() -> Unit {
  sandbox_config.read_resources.clear()
  sandbox_config.read_globs.clear()
  sandbox_config.import_globs.clear()
}

///|
pub fn register_read_resource(
  from : String,
  uri : String,
  visible_uri : String,
  resource_uri : String,
  text : String,
) -> Unit {
  sandbox_config.read_resources[sandbox_io_key(from, uri)] = {
    uri: visible_uri,
    resource_uri,
    text,
  }
}

///|
fn sandbox_lookup_read_resource(
  from : String,
  uri : String,
) -> SandboxResource? {
  sandbox_config.read_resources.get(sandbox_io_key(from, uri))
}

///|
pub fn register_read_glob(
  from : String,
  pattern : String,
  resources : Array[SandboxResource],
) -> Unit {
  sandbox_config.read_globs[sandbox_io_key(from, pattern)] = resources
}

///|
fn sandbox_lookup_read_glob(
  from : String,
  pattern : String,
) -> Array[SandboxResource]? {
  sandbox_config.read_globs.get(sandbox_io_key(from, pattern))
}

///|
pub fn register_import_glob(
  from : String,
  pattern : String,
  uris : Array[String],
) -> Unit {
  sandbox_config.import_globs[sandbox_io_key(from, pattern)] = uris
}

///|
fn sandbox_lookup_import_glob(
  from : String,
  pattern : String,
) -> Array[String]? {
  sandbox_config.import_globs.get(sandbox_io_key(from, pattern))
}
