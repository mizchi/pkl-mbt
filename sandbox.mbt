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
  // PKL-150 (#258): pre-extracted package cache roots. A directory
  // looks like `<dir>/<name>@<version>/package/<files>` — this is the
  // layout `pkl download-package` produces and the one Apple ships
  // alongside their snippet fixtures (`pkl-commons-test/src/main/files/packages`).
  // Real network download + DEFLATE + SHA-256 is deferred; this lets
  // any caller that has already-extracted packages (CI fixtures, an
  // air-gapped registry mirror) resolve `package://` URIs.
  mut package_caches : Array[String]
  // PKL-148r: triple-dot import resolutions cached by the CLI's load
  // step (FS-based) so the IO-free analysis layer can map the same
  // `(from, ".../X")` pair back to the absolute path the CLI already
  // loaded into the session source store. Key shape is
  // `"<from>\n<uri>"`.
  triple_dot_resolutions : Map[String, String]
}

///|
let sandbox_config : SandboxConfig = {
  props: Map([], capacity=8),
  allowed_modules: [],
  module_paths: [],
  package_caches: [],
  triple_dot_resolutions: Map([], capacity=8),
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
  sandbox_config.props.get(name)
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
