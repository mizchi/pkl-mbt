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
}

///|
let sandbox_config : SandboxConfig = {
  props: Map([], capacity=8),
  allowed_modules: [],
  module_paths: [],
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
