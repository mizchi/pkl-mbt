///|
/// Filesystem layout shared by the native/JS package downloader and the
/// cache-only Wasm Marketplace loader.
struct PackageCacheParts {
  package_root_relative : String
  package_dir_relative : String
  file_relative : String
  metadata_relative : String
}

///|
fn is_package_uri_like(uri : String) -> Bool {
  uri.has_prefix("package://") || uri.has_prefix("projectpackage://")
}

///|
fn strip_package_scheme(uri : String) -> String? {
  if uri.has_prefix("projectpackage://") {
    Some(String::unsafe_substring(uri, start=17, end=uri.length()))
  } else if uri.has_prefix("package://") {
    Some(String::unsafe_substring(uri, start=10, end=uri.length()))
  } else {
    None
  }
}

///|
fn trim_leading_slashes(path : String) -> String {
  let mut start = 0
  while start < path.length() && path[start].to_int().unsafe_to_char() == '/' {
    start += 1
  }
  String::unsafe_substring(path, start~, end=path.length())
}

///|
fn join_relative_segments(a : String, b : String, c : String) -> String {
  let segments = [
    trim_leading_slashes(a),
    trim_leading_slashes(b),
    trim_leading_slashes(c),
  ]
  let buf = StringBuilder::new()
  let mut needs_sep = false
  for segment in segments {
    if segment == "" {
      continue
    }
    if needs_sep {
      buf.write_char('/')
    }
    buf.write_string(segment)
    needs_sep = !segment.has_suffix("/")
  }
  buf.to_string()
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) =>
      String::unsafe_substring(path, start=idx + 1, end=path.length())
    None => path
  }
}

///|
fn strip_package_checksum_from_version(version : String) -> String {
  match version.find("::") {
    Some(idx) => String::unsafe_substring(version, start=0, end=idx)
    None => version
  }
}

///|
fn strip_fixture_redirect_segments(path : String) -> String {
  let mut rest = trim_leading_slashes(path)
  let mut changed = true
  while changed {
    if rest.has_prefix("HTTP301/") {
      rest = String::unsafe_substring(rest, start=8, end=rest.length())
    } else if rest.has_prefix("HTTP307/") {
      rest = String::unsafe_substring(rest, start=8, end=rest.length())
    } else {
      changed = false
    }
  }
  rest
}

///|
fn join_path(base : String, relative : String) -> String {
  if relative == "" {
    base
  } else if base.has_suffix("/") {
    base + relative
  } else {
    base + "/" + relative
  }
}

///|
fn default_package_cache_root() -> String {
  match @sys.get_env_var("PKL_MBT_PACKAGE_CACHE") {
    Some(root) if root != "" => root
    _ =>
      match @sys.get_env_var("XDG_CACHE_HOME") {
        Some(root) if root != "" => root + "/pkl-mbt/package-2"
        _ =>
          match @sys.get_env_var("HOME") {
            Some(home) if home != "" => home + "/.cache/pkl-mbt/package-2"
            _ => ".pkl-mbt/package-2"
          }
      }
  }
}

///|
fn package_cache_roots_from(configured : Array[String]) -> Array[String] {
  if configured.length() > 0 {
    configured
  } else {
    [default_package_cache_root()]
  }
}

///|
fn cli_hex_value(c : UInt16) -> Int? {
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
fn percent_decode_uri_path(path : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < path.length() {
    if path[i] == '%' && i + 2 < path.length() {
      match (cli_hex_value(path[i + 1]), cli_hex_value(path[i + 2])) {
        (Some(hi), Some(lo)) => {
          buf.write_char((hi * 16 + lo).unsafe_to_char())
          i = i + 3
          continue
        }
        _ => ()
      }
    }
    buf.write_char(path[i].to_int().unsafe_to_char())
    i = i + 1
  }
  buf.to_string()
}

///|
fn package_cache_parts(uri : String, rest : String) -> PackageCacheParts? {
  let body = match strip_package_scheme(uri) {
    Some(body) => body
    None => return None
  }
  let (without_fragment, fragment) = match body.find("#") {
    Some(idx) =>
      (
        String::unsafe_substring(body, start=0, end=idx),
        String::unsafe_substring(body, start=idx + 1, end=body.length()),
      )
    None => (body, "")
  }
  let after_host = match without_fragment.find("/") {
    Some(idx) =>
      strip_fixture_redirect_segments(
        String::unsafe_substring(
          without_fragment,
          start=idx + 1,
          end=without_fragment.length(),
        ),
      )
    None => return None
  }
  let at_idx = match after_host.rev_find("@") {
    Some(idx) => idx
    None => return None
  }
  let name = String::unsafe_substring(after_host, start=0, end=at_idx)
  if name == "" {
    return None
  }
  let after_at = String::unsafe_substring(
    after_host,
    start=at_idx + 1,
    end=after_host.length(),
  )
  let (version, extra) = match after_at.find("/") {
    Some(idx) =>
      (
        String::unsafe_substring(after_at, start=0, end=idx),
        String::unsafe_substring(after_at, start=idx + 1, end=after_at.length()),
      )
    None => (after_at, "")
  }
  if version == "" {
    return None
  }
  let package_root_relative = "\{name}@\{strip_package_checksum_from_version(version)}"
  let package_dir_relative = package_root_relative + "/package"
  let suffix = join_relative_segments(
    extra,
    percent_decode_uri_path(fragment),
    rest,
  )
  let file_relative = if suffix == "" {
    package_dir_relative
  } else {
    package_dir_relative + "/" + suffix
  }
  let metadata_relative = package_root_relative +
    "/" +
    basename(package_root_relative) +
    ".json"
  Some({
    package_root_relative,
    package_dir_relative,
    file_relative,
    metadata_relative,
  })
}

///|
pub fn package_cache_relative(uri : String, rest : String) -> String {
  match package_cache_parts(uri, rest) {
    Some(parts) => {
      // The downloader reads these fields only on native/JS. Keep the shared
      // Wasm build warning-clean while exposing one target-neutral layout.
      ignore(parts.package_root_relative)
      ignore(parts.package_dir_relative)
      ignore(parts.metadata_relative)
      parts.file_relative
    }
    None => ""
  }
}

///|
fn resolve_package_uri_to_cache_in_roots(
  uri : String,
  rest : String,
  roots : Array[String],
) -> String? {
  let relative = match package_cache_parts(uri, rest) {
    Some(parts) => parts.file_relative
    None => return None
  }
  for cache_dir in roots {
    let candidate = join_path(cache_dir, relative)
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}
