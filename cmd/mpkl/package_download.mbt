///|
suberror PackageDownloadError {
  PackageDownloadError(String)
} derive(Eq)

///|
impl Show for PackageDownloadError with output(self, logger) {
  match self {
    PackageDownloadError(message) =>
      logger.write_string("PackageDownloadError(\{message})")
  }
}

///|
struct PackageCacheParts {
  package_root_relative : String
  package_dir_relative : String
  file_relative : String
  metadata_relative : String
}

///|
struct ZipEntry {
  path : String
  content : Bytes
  is_dir : Bool
}

///|
fn package_download_error(message : String) -> Unit raise PackageDownloadError {
  raise PackageDownloadError::PackageDownloadError(message)
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
fn package_cache_roots() -> Array[String] {
  let configured = @pkl.sandbox_package_caches()
  if configured.length() > 0 {
    configured
  } else {
    [default_package_cache_root()]
  }
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
    Some(parts) => parts.file_relative
    None => ""
  }
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
fn package_metadata_url_from_uri(uri : String) -> String? {
  if uri.has_prefix("package://") {
    match parse_package_uri(uri) {
      Some(parsed) =>
        Some(
          package_metadata_url({
            authority: parsed.authority,
            path: strip_package_checksum_from_path(parsed.path),
            fragment: parsed.fragment,
          }),
        )
      None => None
    }
  } else if uri.has_prefix("projectpackage://") {
    let body = String::unsafe_substring(uri, start=17, end=uri.length())
    let without_fragment = match body.find("#") {
      Some(idx) => String::unsafe_substring(body, start=0, end=idx)
      None => body
    }
    Some("https://\{strip_package_checksum_from_path(without_fragment)}")
  } else {
    None
  }
}

///|
fn extract_package_zip_sha256(body : String) -> String? {
  let parsed = Some(@json.parse(body[:])) catch { _ => None }
  match parsed {
    Some(Object(top)) =>
      match top.get("packageZipChecksums") {
        Some(Object(checksums)) =>
          match checksums.get("sha256") {
            Some(String(value)) => Some(value)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn ensure_dir(path : String) -> Unit raise {
  if path == "" || path == "/" {
    return
  }
  if @fs.path_exists(path) {
    let dir_ok = @fs.is_dir(path) catch { _ => false }
    if dir_ok {
      return
    }
    package_download_error("path exists but is not a directory: \{path}")
  }
  let mut i = if path.has_prefix("/") { 1 } else { 0 }
  while i <= path.length() {
    if i == path.length() || path[i].to_int().unsafe_to_char() == '/' {
      let part = String::unsafe_substring(path, start=0, end=i)
      if part != "" && part != "/" && !@fs.path_exists(part) {
        @fs.create_dir(part)
      }
    }
    i += 1
  }
}

///|
fn parent_dir(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => String::unsafe_substring(path, start=0, end=idx)
    None => ""
  }
}

///|
fn bytes_slice(data : Bytes, start : Int, end : Int) -> Bytes raise {
  if start < 0 || end < start || end > data.length() {
    package_download_error("byte slice out of range")
  }
  Bytes::from_array(FixedArray::makei(end - start, fn(i) { data[start + i] }))
}

///|
fn empty_bytes() -> Bytes {
  Bytes::from_array([])
}

///|
fn read_u16_le(data : Bytes, offset : Int) -> Int raise {
  if offset < 0 || offset + 2 > data.length() {
    package_download_error("unexpected end of zip data")
  }
  data[offset].to_int() | (data[offset + 1].to_int() << 8)
}

///|
fn read_u32_le(data : Bytes, offset : Int) -> Int raise {
  if offset < 0 || offset + 4 > data.length() {
    package_download_error("unexpected end of zip data")
  }
  data[offset].to_int() |
  (data[offset + 1].to_int() << 8) |
  (data[offset + 2].to_int() << 16) |
  (data[offset + 3].to_int() << 24)
}

///|
fn find_zip_eocd(data : Bytes) -> Int raise {
  if data.length() < 22 {
    package_download_error("zip data is too short")
  }
  let min = if data.length() > 66000 { data.length() - 66000 } else { 0 }
  let mut i = data.length() - 22
  while i >= min {
    if read_u32_le(data, i) == 0x06054b50 {
      return i
    }
    i -= 1
  }
  package_download_error("zip end-of-central-directory not found")
  0
}

///|
fn read_zip_entries(data : Bytes) -> Array[ZipEntry] raise {
  let eocd = find_zip_eocd(data)
  let total_entries = read_u16_le(data, eocd + 10)
  let central_offset = read_u32_le(data, eocd + 16)
  let entries : Array[ZipEntry] = []
  let mut offset = central_offset
  for _ in 0..<total_entries {
    if read_u32_le(data, offset) != 0x02014b50 {
      package_download_error("invalid zip central directory header")
    }
    let flags = read_u16_le(data, offset + 8)
    let compression_method = read_u16_le(data, offset + 10)
    let compressed_size = read_u32_le(data, offset + 20)
    let uncompressed_size = read_u32_le(data, offset + 24)
    let name_len = read_u16_le(data, offset + 28)
    let extra_len = read_u16_le(data, offset + 30)
    let comment_len = read_u16_le(data, offset + 32)
    let local_offset = read_u32_le(data, offset + 42)
    if compressed_size == 0xffffffff || uncompressed_size == 0xffffffff {
      package_download_error("zip64 package archives are not supported yet")
    }
    let name_start = offset + 46
    let name_end = name_start + name_len
    let name = @utf8.decode(bytes_slice(data, name_start, name_end)[:])
    let is_dir = name.has_suffix("/")
    if read_u32_le(data, local_offset) != 0x04034b50 {
      package_download_error("invalid zip local file header")
    }
    let local_name_len = read_u16_le(data, local_offset + 26)
    let local_extra_len = read_u16_le(data, local_offset + 28)
    let body_start = local_offset + 30 + local_name_len + local_extra_len
    let body_end = body_start + compressed_size
    let compressed = bytes_slice(data, body_start, body_end)
    let content = if is_dir {
      empty_bytes()
    } else {
      match compression_method {
        0 => compressed
        8 => @zlib.deflate_decompress(compressed, max_size=uncompressed_size)
        _ => {
          package_download_error(
            "unsupported zip compression method: \{compression_method}",
          )
          empty_bytes()
        }
      }
    }
    if !is_dir && content.length() != uncompressed_size {
      package_download_error("zip entry size mismatch: \{name}")
    }
    ignore(flags)
    entries.push({ path: name, content, is_dir })
    offset = name_end + extra_len + comment_len
  }
  entries
}

///|
fn zip_entry_path_is_safe(path : String) -> Bool {
  if path == "" || path.has_prefix("/") || path.find("\\") is Some(_) {
    return false
  }
  let mut start = 0
  let mut i = 0
  while i <= path.length() {
    if i == path.length() || path[i].to_int().unsafe_to_char() == '/' {
      let segment = String::unsafe_substring(path, start~, end=i)
      if segment == ".." {
        return false
      }
      start = i + 1
    }
    i += 1
  }
  true
}

///|
fn extract_zip_to_dir(data : Bytes, package_dir : String) -> Unit raise {
  ensure_dir(package_dir)
  for entry in read_zip_entries(data) {
    if !zip_entry_path_is_safe(entry.path) {
      package_download_error("unsafe zip entry path: \{entry.path}")
    }
    let target = join_path(package_dir, entry.path)
    if entry.is_dir {
      ensure_dir(target)
    } else {
      ensure_dir(parent_dir(target))
      @fs.write_bytes_to_file(target, entry.content)
    }
  }
}

///|
async fn download_package_uri_to_cache(uri : String) -> Bool {
  try {
    let parts = match package_cache_parts(uri, "") {
      Some(parts) => parts
      None => {
        package_download_error("malformed package URI: \{uri}")
        return false
      }
    }
    let metadata_url = match package_metadata_url_from_uri(uri) {
      Some(url) => url
      None => {
        package_download_error("malformed package URI: \{uri}")
        return false
      }
    }
    let metadata = match fetch_uri(metadata_url) {
      Some(body) => body
      None => {
        package_download_error("metadata fetch failed: \{metadata_url}")
        return false
      }
    }
    let zip_url = match extract_package_zip_url(metadata) {
      Some(url) => url
      None => {
        package_download_error("metadata is missing packageZipUrl")
        return false
      }
    }
    let expected_sha256 = match extract_package_zip_sha256(metadata) {
      Some(value) => value
      None => {
        package_download_error("metadata is missing packageZipChecksums.sha256")
        return false
      }
    }
    let zip_bytes = match fetch_uri_bytes(zip_url) {
      Some(bytes) => bytes
      None => {
        package_download_error("zip fetch failed: \{zip_url}")
        return false
      }
    }
    let actual_sha256 = @crypto.bytes_to_hex_string(@crypto.sha256(zip_bytes))
    if actual_sha256 != expected_sha256 {
      package_download_error(
        "package zip sha256 mismatch: expected \{expected_sha256}, got \{actual_sha256}",
      )
    }
    let roots = package_cache_roots()
    let cache_root = roots[0]
    let package_root = join_path(cache_root, parts.package_root_relative)
    let package_dir = join_path(cache_root, parts.package_dir_relative)
    ensure_dir(package_root)
    extract_zip_to_dir(zip_bytes, package_dir)
    @fs.write_string_to_file(
      join_path(cache_root, parts.metadata_relative),
      metadata,
    )
    true
  } catch {
    error => {
      println("package download failed for \{uri}: \{error}")
      false
    }
  }
}

///|
async fn resolve_or_download_package_uri_to_cache(
  uri : String,
  rest : String,
) -> String? {
  match resolve_package_uri_to_cache(uri, rest) {
    Some(path) => Some(path)
    None =>
      if download_package_uri_to_cache(uri) {
        resolve_package_uri_to_cache(uri, rest)
      } else {
        None
      }
  }
}
