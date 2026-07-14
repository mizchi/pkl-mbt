///|
fn package_cache_roots() -> Array[String] {
  package_cache_roots_from(@pkl.sandbox_package_caches())
}

///|
fn strip_package_checksum_from_path(path : String) -> String {
  let at_idx = match path.rev_find("@") {
    Some(idx) => idx
    None => return path
  }
  let before_version = String::unsafe_substring(path, start=0, end=at_idx + 1)
  let after_at = String::unsafe_substring(
    path,
    start=at_idx + 1,
    end=path.length(),
  )
  let (version, extra) = match after_at.find("/") {
    Some(idx) =>
      (
        String::unsafe_substring(after_at, start=0, end=idx),
        String::unsafe_substring(after_at, start=idx, end=after_at.length()),
      )
    None => (after_at, "")
  }
  before_version + strip_package_checksum_from_version(version) + extra
}

///|
fn package_uri_with_rest(uri : String, rest : String) -> String {
  if rest == "" {
    uri
  } else if uri.find("#") is Some(_) {
    if uri.has_suffix("/") {
      uri + rest
    } else {
      uri + "/" + rest
    }
  } else {
    uri + "#/" + rest
  }
}

///|
/// Map a package URI onto a file in one of the configured package caches.
fn resolve_package_uri_to_cache(uri : String, rest : String) -> String? {
  resolve_package_uri_to_cache_in_roots(uri, rest, package_cache_roots())
}
