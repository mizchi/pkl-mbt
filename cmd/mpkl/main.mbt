///|
fn usage() -> Unit {
  println(
    "usage: pkl <parse|check|eval|test|format|analyze|codegen|stdlib> [args]",
  )
  println(
    "       pkl eval [-f|--format pcf|json|yaml|properties|plist|textproto|xml] <file.pkl>",
  )
  println("       pkl test <file.pkl>")
  println("       pkl format <file.pkl>")
  println("       pkl analyze <file.pkl>")
  println("       pkl codegen [-t|--target moonbit] <file.pkl>")
  println("       pkl parse-many <file.pkl>...")
  println(
    "  sandbox flags: --allowed-modules <pipe-separated-prefixes> --module-path <dir> -p NAME=VALUE",
  )
}

///|
fn fail(message : String) -> Unit {
  println(message)
  @sys.exit(1)
}

///|

///|
/// Split `s` on `|`. Empty segments are dropped so a trailing or
/// leading pipe doesn't introduce an empty allow-list entry that
/// would match every URI.
fn split_pipe(s : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < s.length() {
    if s[i].to_int().unsafe_to_char() == '|' {
      if i > start {
        parts.push(String::unsafe_substring(s, start~, end=i))
      }
      start = i + 1
    }
    i = i + 1
  }
  if start < s.length() {
    parts.push(String::unsafe_substring(s, start~, end=s.length()))
  }
  parts
}

///|
/// PKL-129b1: structural parse of a `package://` URI. Apple Pkl's
/// registry URLs land in three logical parts: the authority (host),
/// the registry path (which ends with `@<version>` — pkl-mbt keeps
/// the path verbatim so the same string round-trips into the
/// metadata URL), and an optional `#<fragment>` selecting a file
/// inside the package zip. Returns `None` when the URI doesn't have
/// the `package://<host>/<path>` shape.
struct PackageUri {
  authority : String
  path : String
  fragment : String
}

///|
fn parse_package_uri(uri : String) -> PackageUri? {
  if !uri.has_prefix("package://") {
    return None
  }
  let after_scheme = String::unsafe_substring(uri, start=10, end=uri.length())
  let (without_fragment, fragment) = match after_scheme.find("#") {
    Some(idx) =>
      (
        String::unsafe_substring(after_scheme, start=0, end=idx),
        String::unsafe_substring(
          after_scheme,
          start=idx + 1,
          end=after_scheme.length(),
        ),
      )
    None => (after_scheme, "")
  }
  // The authority ends at the first `/` after the host. A package
  // URI without a path (`package://host`) isn't a valid registry
  // reference, so we reject it here rather than building a bogus
  // metadata URL downstream.
  match without_fragment.find("/") {
    None => None
    Some(0) => None
    Some(slash) => {
      let authority = String::unsafe_substring(
        without_fragment,
        start=0,
        end=slash,
      )
      let path = String::unsafe_substring(
        without_fragment,
        start=slash,
        end=without_fragment.length(),
      )
      Some(PackageUri::{ authority, path, fragment })
    }
  }
}

///|
/// PKL-129b1: build the HTTPS URL the registry serves the package
/// metadata JSON at. Apple Pkl's convention is a direct scheme
/// rewrite + drop the fragment: `package://<authority><path>#fragment`
/// becomes `https://<authority><path>`. The metadata response carries
/// `packageZipUrl` (extracted separately).
fn package_metadata_url(p : PackageUri) -> String {
  ignore(p.fragment)
  "https://\{p.authority}\{p.path}"
}

///|
/// PKL-129b1: pluck the `packageZipUrl` string from a metadata JSON
/// body without standing up a full JSON parser. The field is a
/// simple `"packageZipUrl": "<url>"` pair; URLs never contain JSON
/// string escapes, so a naive substring scan is sufficient. Returns
/// `None` when the field is absent or malformed.
fn extract_package_zip_url(body : String) -> String? {
  let needle = "\"packageZipUrl\""
  match body.find(needle) {
    None => None
    Some(idx) => {
      let mut i = idx + needle.length()
      // Skip whitespace then a single `:` then more whitespace.
      while i < body.length() {
        let c = body[i].to_int().unsafe_to_char()
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
          i = i + 1
        } else {
          break
        }
      }
      if i >= body.length() || body[i].to_int().unsafe_to_char() != ':' {
        return None
      }
      i = i + 1
      while i < body.length() {
        let c = body[i].to_int().unsafe_to_char()
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
          i = i + 1
        } else {
          break
        }
      }
      if i >= body.length() || body[i].to_int().unsafe_to_char() != '"' {
        return None
      }
      let value_start = i + 1
      let mut j = value_start
      while j < body.length() && body[j].to_int().unsafe_to_char() != '"' {
        j = j + 1
      }
      if j >= body.length() {
        return None
      }
      Some(String::unsafe_substring(body, start=value_start, end=j))
    }
  }
}

///|
/// PKL-148ad: resolve an `@<dep>/<rest>` project-dependency import URI
/// to an absolute file path by walking up `from`'s ancestor
/// directories for a `PklProject.deps.json`, JSON-parsing the
/// `resolvedDependencies` map, finding the entry whose key path-tail
/// matches `<dep>` (`package://host/<dep>@<v>` → `<dep>`), and — when
/// the entry is `type: "local"` — combining the PklProject directory
/// with the entry's `path` and the import's `<rest>`. Remote entries
/// (`type: "remote"`) return None; package download is its own slice
/// (PKL-129). Returns the absolute path on a match so the caller can
/// register it in the sandbox cache (mirroring the triple-dot path).
fn resolve_at_prefix_dep(from : String, uri : String) -> String? {
  if !uri.has_prefix("@") {
    return None
  }
  let after_at = String::unsafe_substring(uri, start=1, end=uri.length())
  let slash_idx = match after_at.find("/") {
    Some(idx) => idx
    None => return None
  }
  let dep_name = String::unsafe_substring(after_at, start=0, end=slash_idx)
  let rest = String::unsafe_substring(
    after_at,
    start=slash_idx + 1,
    end=after_at.length(),
  )
  let mut current = match from.rev_find("/") {
    Some(idx) => String::unsafe_substring(from, start=0, end=idx)
    None => ""
  }
  let mut keep_walking = true
  while keep_walking {
    // PKL-150 (#258): consult PklProject directly for the alias's URI
    // first — it carries the alias→URI mapping verbatim, and the
    // configured `--package-cache` can resolve the URI to a local
    // file without needing the deps.json lockfile. The deps.json path
    // below still wins for `type: "local"` (file-path) entries; the
    // PklProject scan only runs for the remote-URI variant the cache
    // can serve.
    let pklproject_path = if current == "" {
      "PklProject"
    } else {
      current + "/PklProject"
    }
    if @fs.path_exists(pklproject_path) {
      let project_text = @fs.read_file_to_string(pklproject_path) catch {
        _ => ""
      }
      if project_text != "" {
        match pklproject_alias_to_uri(project_text, dep_name) {
          Some(remote_uri) =>
            match resolve_package_uri_to_cache(remote_uri, rest) {
              Some(cached_path) => return Some(cached_path)
              None => return Some(package_uri_with_rest(remote_uri, rest))
            }
          None => ()
        }
      }
    }
    // PKL-150 (#258): when the importer is itself inside a package
    // cache directory, the alias map lives in the `<name>@<version>.json`
    // metadata sibling rather than a PklProject. The layout is
    // `<cache>/<name>@<version>/package/<file>` for sources and
    // `<cache>/<name>@<version>/<name>@<version>.json` for metadata —
    // step past the `package/` directory once and probe for any
    // `*@*.json` whose `dependencies[<dep>]` matches the alias.
    match package_metadata_alias_to_uri(current, dep_name) {
      Some(remote_uri) =>
        match resolve_package_uri_to_cache(remote_uri, rest) {
          Some(cached_path) => return Some(cached_path)
          None => return Some(package_uri_with_rest(remote_uri, rest))
        }
      None => ()
    }
    let deps_path = if current == "" {
      "PklProject.deps.json"
    } else {
      current + "/PklProject.deps.json"
    }
    if @fs.path_exists(deps_path) {
      let body = @fs.read_file_to_string(deps_path) catch { _ => "" }
      if body != "" {
        let parsed = Some(@json.parse(body[:])) catch { _ => None }
        match parsed {
          Some(Object(top)) =>
            match top.get("resolvedDependencies") {
              Some(Object(deps)) =>
                for key, value in deps {
                  let key_tail = match key.rev_find("/") {
                    Some(idx) =>
                      String::unsafe_substring(
                        key,
                        start=idx + 1,
                        end=key.length(),
                      )
                    None => key
                  }
                  let entry_name = match key_tail.find("@") {
                    Some(idx) =>
                      String::unsafe_substring(key_tail, start=0, end=idx)
                    None => key_tail
                  }
                  if entry_name == dep_name {
                    match value {
                      Object(entry) => {
                        let entry_type = match entry.get("type") {
                          Some(String(s)) => s
                          _ => ""
                        }
                        let path_str = match entry.get("path") {
                          Some(String(s)) => Some(s)
                          _ => None
                        }
                        let uri_str = match entry.get("uri") {
                          Some(String(s)) => Some(s)
                          _ => None
                        }
                        if entry_type == "local" {
                          match path_str {
                            Some(path) => {
                              let dep_dir = if path.has_suffix("/") {
                                path
                              } else {
                                path + "/"
                              }
                              let joined = if dep_dir.has_prefix("/") {
                                dep_dir + rest
                              } else if current == "" {
                                dep_dir + rest
                              } else {
                                current + "/" + dep_dir + rest
                              }
                              return Some(joined)
                            }
                            None => ()
                          }
                        } else if entry_type == "remote" {
                          // PKL-150 (#258): `type: "remote"` carries a
                          // `projectpackage://host/name@version` URI.
                          // Resolve through the package cache when
                          // possible; otherwise return the package URI
                          // shape so the async loader can download it.
                          match uri_str {
                            Some(remote_uri) =>
                              match
                                resolve_package_uri_to_cache(remote_uri, rest) {
                                Some(cached_path) => return Some(cached_path)
                                None =>
                                  return Some(
                                    package_uri_with_rest(remote_uri, rest),
                                  )
                              }
                            None => ()
                          }
                        }
                      }
                      _ => ()
                    }
                  }
                }
              _ => ()
            }
          _ => ()
        }
      }
    }
    if current == "" || current == "/" {
      keep_walking = false
    } else {
      match current.rev_find("/") {
        Some(idx) =>
          current = String::unsafe_substring(current, start=0, end=idx)
        None => current = ""
      }
    }
  }
  None
}

///|
/// PKL-150 (#258): when a file inside a package cache (`<cache>/<name>@<version>/package/...`)
/// imports `@<dep>/<rest>`, the alias→URI map lives in the package's
/// `<name>@<version>.json` metadata sibling, not in a PklProject.
/// Probe ancestor directories for one whose parent contains a
/// `*.json` metadata file with `dependencies[<dep>].uri`. Returns the
/// `package://...` URI on a hit so the caller routes through the
/// existing cache resolver, or None to fall through to the legacy
/// path.
fn package_metadata_alias_to_uri(
  current : String,
  dep_name : String,
) -> String? {
  // Walk up: if the importing file is `.../<name>@<version>/package/sub/dir/X.pkl`,
  // we keep stepping up until we hit `<name>@<version>/package`. The
  // sibling `<name>@<version>.json` then carries the dep map.
  let mut dir = current
  while dir != "" && dir != "/" {
    // Look for a sibling JSON file named like `<basename>.json` in the
    // parent directory of `dir`. That covers the canonical cache
    // layout where `package/` lives under `<name>@<version>/`.
    let parent_idx = dir.rev_find("/")
    let (parent, basename) = match parent_idx {
      Some(idx) =>
        (
          String::unsafe_substring(dir, start=0, end=idx),
          String::unsafe_substring(dir, start=idx + 1, end=dir.length()),
        )
      None => ("", dir)
    }
    // The package layout puts the metadata next to `package/`; the
    // basename of `dir`'s parent should be `<name>@<version>`. Probe
    // for that specific JSON.
    if basename == "package" {
      let pkg_dir_idx = parent.rev_find("/")
      let pkg_basename = match pkg_dir_idx {
        Some(idx) =>
          String::unsafe_substring(parent, start=idx + 1, end=parent.length())
        None => parent
      }
      if pkg_basename.find("@") is Some(_) {
        let meta_path = parent + "/" + pkg_basename + ".json"
        if @fs.path_exists(meta_path) {
          let body = @fs.read_file_to_string(meta_path) catch { _ => "" }
          if body != "" {
            let parsed = Some(@json.parse(body[:])) catch { _ => None }
            match parsed {
              Some(Object(top)) =>
                match top.get("dependencies") {
                  Some(Object(deps)) =>
                    match deps.get(dep_name) {
                      Some(Object(entry)) =>
                        match entry.get("uri") {
                          Some(String(uri)) => return Some(uri)
                          _ => ()
                        }
                      _ => ()
                    }
                  _ => ()
                }
              _ => ()
            }
          }
        }
      }
    }
    match parent_idx {
      Some(idx) => dir = String::unsafe_substring(dir, start=0, end=idx)
      None => dir = ""
    }
  }
  None
}

///|
/// PKL-150 (#258): scan a PklProject text for the `["<alias>"]` block
/// and read out its `uri = "..."`. Apple Pkl evaluates the project
/// module to compute this — we lean on a text scan because the eval
/// path would loop (the loader resolves imports through PklProject,
/// which would re-trigger eval through the loader). The scan only
/// looks for the literal `["<alias>"] {` opener and a subsequent
/// `uri = "..."` until the matching `}`, so non-literal forms
/// (`["x" + y"]` etc.) fall through to None. That covers the snippet
/// fixtures and any project that writes dependency entries in the
/// standard form.
fn pklproject_alias_to_uri(text : String, dep_alias : String) -> String? {
  let opener = "[\"" + dep_alias + "\"]"
  let mut search_from = 0
  while search_from < text.length() {
    let tail = String::unsafe_substring(
      text,
      start=search_from,
      end=text.length(),
    )
    let open_idx = match tail.find(opener) {
      Some(idx) => idx
      None => return None
    }
    let absolute = search_from + open_idx
    let after_opener = absolute + opener.length()
    // Walk past whitespace then expect `{`. Skip on mismatch (some
    // other `["<alias>"]` reference outside a dependencies block).
    let mut p = after_opener
    while p < text.length() {
      let c = text[p].to_int().unsafe_to_char()
      if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
        p = p + 1
      } else {
        break
      }
    }
    if p >= text.length() || text[p].to_int().unsafe_to_char() != '{' {
      search_from = after_opener
      continue
    }
    let body_start = p + 1
    // Find the matching `}`. Counts nested braces so an inner object
    // (`checksums { ... }`) doesn't close early.
    let mut depth = 1
    let mut j = body_start
    while j < text.length() && depth > 0 {
      let c = text[j].to_int().unsafe_to_char()
      if c == '{' {
        depth = depth + 1
      } else if c == '}' {
        depth = depth - 1
        if depth == 0 {
          break
        }
      }
      j = j + 1
    }
    if j >= text.length() {
      return None
    }
    let body = String::unsafe_substring(text, start=body_start, end=j)
    // Find `uri = "..."` literally. Restricted to the in-body slice so
    // we don't accidentally grab a `uri` from a later block.
    let uri_marker = "uri"
    let uri_idx = match body.find(uri_marker) {
      Some(idx) => idx
      None => {
        search_from = j + 1
        continue
      }
    }
    let mut k = uri_idx + uri_marker.length()
    while k < body.length() {
      let c = body[k].to_int().unsafe_to_char()
      if c == ' ' || c == '\t' || c == '=' {
        k = k + 1
      } else {
        break
      }
    }
    if k >= body.length() || body[k].to_int().unsafe_to_char() != '"' {
      search_from = j + 1
      continue
    }
    let value_start = k + 1
    let mut value_end = value_start
    while value_end < body.length() &&
          body[value_end].to_int().unsafe_to_char() != '"' {
      value_end = value_end + 1
    }
    if value_end > body.length() {
      return None
    }
    return Some(
      String::unsafe_substring(body, start=value_start, end=value_end),
    )
  }
  None
}

///|
/// PKL-150 (#258): map a `package://host/name@version[/rest]` (or the
/// `projectpackage://` variant the deps.json uses) URI onto a local
/// file under one of the configured `--package-cache` directories, or
/// the CLI default cache when no explicit root is configured.
fn resolve_package_uri_to_cache(uri : String, rest : String) -> String? {
  let relative = match package_cache_parts(uri, rest) {
    Some(parts) => parts.file_relative
    None => return None
  }
  for cache_dir in package_cache_roots() {
    let base = if cache_dir.has_suffix("/") {
      cache_dir
    } else {
      cache_dir + "/"
    }
    let candidate = base + relative
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn resolve_import_path(from : String, uri : String) -> String {
  // PKL-148ad: project-dependency import (`import "@<dep>/<rest>"`).
  // The PklProject.deps.json file in an ancestor directory carries
  // the resolved dependency map; local-type deps are FS-loadable.
  // Cache the resolution into the same sandbox registry the
  // triple-dot path uses so the IO-free analysis layer sees the
  // mapping too. Falls through to the legacy join when no @-prefix
  // resolution matches.
  match resolve_at_prefix_dep(from, uri) {
    Some(resolved) => {
      @pkl.register_triple_dot_resolution(from, uri, resolved)
      return resolved
    }
    None => ()
  }
  // PKL-148r: triple-dot import (`import ".../X/Y.pkl"`). Walk the
  // ancestor directories of `from` looking for the first one that
  // contains the remainder path as a file. Cache the resolution into
  // the sandbox registry so the IO-free analysis layer can map the
  // same `(from, uri)` pair back to the absolute path the CLI is
  // about to load. When no ancestor matches, return `uri` unchanged
  // so the caller's "Cannot find module" diagnostic surfaces with
  // the original triple-dot URI.
  if uri.has_prefix(".../") {
    let remainder = String::unsafe_substring(uri, start=4, end=uri.length())
    let mut current = match from.rev_find("/") {
      Some(idx) => String::unsafe_substring(from, start=0, end=idx)
      None => ""
    }
    let mut keep_walking = true
    while keep_walking {
      let candidate = if current == "" {
        remainder
      } else {
        current + "/" + remainder
      }
      if @fs.path_exists(candidate) {
        @pkl.register_triple_dot_resolution(from, uri, candidate)
        return candidate
      }
      if current == "" || current == "/" {
        keep_walking = false
      } else {
        match current.rev_find("/") {
          Some(idx) =>
            current = String::unsafe_substring(current, start=0, end=idx)
          None => current = ""
        }
      }
    }
    return uri
  }
  // PKL-148bb: `modulepath:/<path>` URIs come from Apple Pkl's
  // modulepath: configurable search list. For snippet tests, the
  // referenced module lives in the same directory as the importer
  // (`basic/import1b` references `modulepath:/org/pkl/core/snippets/imported.pkl`
  // and `basic/imported.pkl` sits next to the importer). Walk the
  // `from` directory plus a few snippetTest roots for a basename match
  // and rewrite to the absolute file path; fall through to the URI
  // unchanged so the loader's standard "Cannot find module" surfaces
  // when no candidate matches.
  if uri.has_prefix("modulepath:/") {
    let inner = String::unsafe_substring(uri, start=12, end=uri.length())
    let basename = match inner.rev_find("/") {
      Some(idx) =>
        String::unsafe_substring(inner, start=idx + 1, end=inner.length())
      None => inner
    }
    let from_dir = match from.rev_find("/") {
      Some(idx) => String::unsafe_substring(from, start=0, end=idx)
      None => "."
    }
    let candidate = from_dir + "/" + basename
    if @fs.path_exists(candidate) {
      @pkl.register_triple_dot_resolution(from, uri, candidate)
      return candidate
    }
    return uri
  }
  if uri.has_prefix("/") || uri.find(":") is Some(_) {
    return normalize_path_segments(uri)
  }
  let combined = match from.rev_find("/") {
    Some(idx) => String::unsafe_substring(from, start=0, end=idx + 1) + uri
    None => uri
  }
  // PKL-152: collapse `..` / `.` so cycle-detection paths match.
  normalize_path_segments(combined)
}

///|
/// PKL-152: collapse `..` / `.` segments. See analysis.mbt's twin —
/// the CLI has its own resolver for FS-aware loading, so we duplicate
/// the normalizer here rather than depending on the `mizchi/pkl`
/// surface that the analysis layer reaches into.
fn normalize_path_segments(path : String) -> String {
  let scheme_end = match path.find("://") {
    Some(idx) => idx + 3
    None => 0
  }
  let head = String::unsafe_substring(path, start=0, end=scheme_end)
  let body = String::unsafe_substring(path, start=scheme_end, end=path.length())
  let leading_slash = body.has_prefix("/")
  let raw_segments : Array[String] = []
  let mut start = if leading_slash { 1 } else { 0 }
  let mut i = start
  while i < body.length() {
    if body.unsafe_get(i) == '/' {
      raw_segments.push(String::unsafe_substring(body, start~, end=i))
      start = i + 1
    }
    i = i + 1
  }
  if start <= body.length() {
    raw_segments.push(String::unsafe_substring(body, start~, end=body.length()))
  }
  let resolved : Array[String] = []
  for seg in raw_segments {
    if seg == "" || seg == "." {
      continue
    }
    if seg == ".." {
      if resolved.length() > 0 && resolved[resolved.length() - 1] != ".." {
        let _ = resolved.pop()
      } else if !leading_slash {
        resolved.push("..")
      }
      continue
    }
    resolved.push(seg)
  }
  let buf = StringBuilder::new()
  buf.write_string(head)
  if leading_slash {
    buf.write_char('/')
  }
  for k = 0; k < resolved.length(); k = k + 1 {
    if k > 0 {
      buf.write_char('/')
    }
    buf.write_string(resolved[k])
  }
  buf.to_string()
}

///|
fn stack_contains(stack : Array[String], path : String) -> Bool {
  for item in stack {
    if item == path {
      return true
    }
  }
  false
}

///|
fn push_stack(stack : Array[String], path : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(path)
  next
}

///|
fn module_parent_dir(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => String::unsafe_substring(path, start=0, end=idx)
    None => "."
  }
}

///|
fn split_glob_pattern(pattern : String) -> (String, String) {
  match pattern.rev_find("/") {
    Some(idx) =>
      (
        String::unsafe_substring(pattern, start=0, end=idx + 1),
        String::unsafe_substring(pattern, start=idx + 1, end=pattern.length()),
      )
    None => ("", pattern)
  }
}

///|
fn glob_name_matches(pattern : String, name : String) -> Bool {
  match pattern.find("*") {
    None => name == pattern
    Some(idx) => {
      let prefix = String::unsafe_substring(pattern, start=0, end=idx)
      let suffix = String::unsafe_substring(
        pattern,
        start=idx + 1,
        end=pattern.length(),
      )
      name.has_prefix(prefix) && name.has_suffix(suffix)
    }
  }
}

///|
fn sort_strings(values : Array[String]) -> Array[String] {
  let out = values[:].to_owned()
  for i = 1; i < out.length(); i = i + 1 {
    let cur = out[i]
    let mut j = i - 1
    while j >= 0 && out[j] > cur {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = cur
  }
  out
}

///|
fn read_resource_from(from : String, uri : String) -> @pkl.SandboxResource? {
  let resolved = resolve_import_path(from, uri)
  let body = @fs.read_file_to_string(resolved) catch { _ => "" }
  if body != "" || @fs.path_exists(resolved) {
    Some({ uri, text: body })
  } else {
    None
  }
}

///|
fn glob_resources_from(
  from : String,
  pattern : String,
) -> Array[@pkl.SandboxResource] {
  let (dir_prefix, name_pattern) = split_glob_pattern(pattern)
  let base_dir = normalize_path_segments(
    module_parent_dir(from) + "/" + dir_prefix,
  )
  let names = @fs.read_dir(base_dir) catch { _ => [] }
  let resources : Array[@pkl.SandboxResource] = []
  for name in sort_strings(names) {
    if !glob_name_matches(name_pattern, name) {
      continue
    }
    let resolved = normalize_path_segments(base_dir + "/" + name)
    let is_dir = @fs.is_dir(resolved) catch { _ => false }
    if is_dir {
      continue
    }
    let body = @fs.read_file_to_string(resolved) catch { _ => "" }
    if body != "" || @fs.path_exists(resolved) {
      resources.push({ uri: dir_prefix + name, text: body })
    }
  }
  resources
}

///|
fn glob_visible_uris_from(from : String, pattern : String) -> Array[String] {
  let uris : Array[String] = []
  for resource in glob_resources_from(from, pattern) {
    uris.push(resource.uri)
  }
  uris
}

///|
fn register_expr_io(from : String, expr : @pkl.Expr) -> Unit {
  match expr {
    CallExpr(Identifier("read"), args) => {
      if args.length() == 1 && args[0] is StringLiteral(uri) {
        match read_resource_from(from, uri) {
          Some(resource) =>
            @pkl.register_read_resource(from, uri, resource.uri, resource.text)
          None => ()
        }
      }
      for arg in args {
        register_expr_io(from, arg)
      }
    }
    CallExpr(Identifier("read*"), args) => {
      if args.length() == 1 && args[0] is StringLiteral(pattern) {
        @pkl.register_read_glob(
          from,
          pattern,
          glob_resources_from(from, pattern),
        )
      }
      for arg in args {
        register_expr_io(from, arg)
      }
    }
    ImportGlobExpr(pattern) =>
      @pkl.register_import_glob(
        from,
        pattern,
        glob_visible_uris_from(from, pattern),
      )
    ObjectLiteral(members) | TypedObjectLiteral(_, members) =>
      for field in members {
        register_expr_io(from, field.value)
      }
    ListingLiteral(elements) =>
      for element in elements {
        register_expr_io(from, element)
      }
    MappingLiteral(entries) =>
      for entry in entries {
        register_expr_io(from, entry.key)
        register_expr_io(from, entry.value)
      }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      register_expr_io(from, target)
    SubscriptAccess(target, key) => {
      register_expr_io(from, target)
      register_expr_io(from, key)
    }
    AmendExpr(base, members) => {
      register_expr_io(from, base)
      for object_member in members {
        register_expr_io(from, object_member.value)
      }
    }
    CallExpr(callee, args) | NullSafeCallExpr(callee, args) => {
      register_expr_io(from, callee)
      for arg in args {
        register_expr_io(from, arg)
      }
    }
    LambdaExpr(_, body, _) => register_expr_io(from, body)
    LetExpr(_, _, value, body) => {
      register_expr_io(from, value)
      register_expr_io(from, body)
    }
    NonNullExpr(inner) | UnaryExpr(_, inner) | WhenSpread(inner) =>
      register_expr_io(from, inner)
    BinaryExpr(_, left, right) => {
      register_expr_io(from, left)
      register_expr_io(from, right)
    }
    ConditionalExpr(condition, then_expr, else_expr) => {
      register_expr_io(from, condition)
      register_expr_io(from, then_expr)
      register_expr_io(from, else_expr)
    }
    ForGenerator(_, _, source, members, _, _) => {
      register_expr_io(from, source)
      for object_member in members {
        register_expr_io(from, object_member.value)
      }
    }
    InterpolatedString(parts) =>
      for part in parts {
        register_expr_io(from, part)
      }
    IntLiteral(_)
    | FloatLiteral(_)
    | BoolLiteral(_)
    | StringLiteral(_)
    | NullLiteral
    | Identifier(_)
    | ImportExpr(_)
    | UnsupportedExpr
    | ErrorExpr(_) => ()
  }
}

///|
async fn load_expr_imports(
  session : @pkl.AnalysisSession,
  from : String,
  expr : @pkl.Expr,
  stack : Array[String],
  loaded : Map[String, Unit],
) -> Unit {
  match expr {
    ImportExpr(uri) =>
      load_path(
        session,
        resolve_import_path(from, uri),
        push_stack(stack, from),
        loaded,
      )
    ImportGlobExpr(_) => ()
    ObjectLiteral(members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack, loaded)
      }
    TypedObjectLiteral(_, members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack, loaded)
      }
    ListingLiteral(elements) =>
      for element in elements {
        load_expr_imports(session, from, element, stack, loaded)
      }
    MappingLiteral(entries) =>
      for entry in entries {
        load_expr_imports(session, from, entry.key, stack, loaded)
        load_expr_imports(session, from, entry.value, stack, loaded)
      }
    MemberAccess(target, _) =>
      load_expr_imports(session, from, target, stack, loaded)
    SafeMemberAccess(target, _) =>
      load_expr_imports(session, from, target, stack, loaded)
    SubscriptAccess(target, key) => {
      load_expr_imports(session, from, target, stack, loaded)
      load_expr_imports(session, from, key, stack, loaded)
    }
    AmendExpr(base, members) => {
      load_expr_imports(session, from, base, stack, loaded)
      for object_member in members {
        load_expr_imports(session, from, object_member.value, stack, loaded)
      }
    }
    BinaryExpr(_, left, right) => {
      load_expr_imports(session, from, left, stack, loaded)
      load_expr_imports(session, from, right, stack, loaded)
    }
    CallExpr(callee, arguments) => {
      load_expr_imports(session, from, callee, stack, loaded)
      for argument in arguments {
        load_expr_imports(session, from, argument, stack, loaded)
      }
    }
    LambdaExpr(_, body, _) =>
      load_expr_imports(session, from, body, stack, loaded)
    NonNullExpr(inner) => load_expr_imports(session, from, inner, stack, loaded)
    UnaryExpr(_, inner) =>
      load_expr_imports(session, from, inner, stack, loaded)
    ConditionalExpr(condition, then_expr, else_expr) => {
      load_expr_imports(session, from, condition, stack, loaded)
      load_expr_imports(session, from, then_expr, stack, loaded)
      load_expr_imports(session, from, else_expr, stack, loaded)
    }
    _ => ()
  }
}

///|

///|
/// PKL-106: read a file, falling back to the `--module-path`
/// directories when the direct read misses. The first hit wins and
/// the absolute path is reported via `fail` if every candidate
/// misses so the diagnostic names the original URI, not an unhelpful
/// fallback path. Module-path directories are only consulted when
/// `path` has no scheme prefix and isn't an absolute filesystem
/// path — otherwise the user's intent was already explicit.
fn read_with_module_paths(path : String) -> String {
  let direct = @fs.read_file_to_string(path) catch { _ => "" }
  if direct != "" {
    return direct
  }
  let direct_exists = @fs.path_exists(path)
  if direct_exists {
    return direct
  }
  if path.has_prefix("/") || path.find(":") is Some(_) {
    fail("Cannot find module `\{path}`.")
    return ""
  }
  for dir in @pkl.sandbox_module_paths() {
    let candidate = if dir.has_suffix("/") {
      dir + path
    } else {
      dir + "/" + path
    }
    let body = @fs.read_file_to_string(candidate) catch { _ => "" }
    if body != "" || @fs.path_exists(candidate) {
      return body
    }
  }
  fail("Cannot find module `\{path}`.")
  ""
}

///|
async fn load_path(
  session : @pkl.AnalysisSession,
  path : String,
  stack : Array[String],
  loaded : Map[String, Unit],
) -> Unit {
  if path.has_prefix("pkl:") {
    return
  }
  // PKL-106: enforce `--allowed-modules` at the loader boundary.
  // The check applies to every URI we'd actually fetch / read, so a
  // disallowed transitive import surfaces at load time rather than
  // as a missing-symbol diagnostic from the evaluator.
  if !@pkl.sandbox_is_module_allowed(path) {
    fail("module \{path} is not allowed by --allowed-modules")
  }
  if stack_contains(stack, path) {
    // PKL-148bb: ignore the back-edge of a type-only import cycle so
    // the loader still walks parsed-out class declarations for the
    // earlier modules; the runtime EvalResult of the back-edge module
    // is materialised as an empty `ObjectValue` (see analysis.mbt) so
    // the value-side binding doesn't fail. Real cycles through value
    // references resurface as a downstream lookup error.
    return
  }
  // Skip files that have already been loaded in this run. Without this
  // guard a module that both `extends` and `import`s the same base
  // (e.g. pkspec's `Spec.pkl amends Test.pkl` + `import "Test.pkl" as
  // base`) parses the base twice — the recursion processes each
  // top-level reference independently. The session's `set_source`
  // already dedupes, but the redundant parse + recursive walk is what
  // actually costs time.
  if loaded.contains(path) {
    return
  }
  loaded[path] = ()
  // PKL-129: route URI-shaped paths through the HTTP fetch helper.
  // - `https://` / `http://`: fetched through `mizchi/x/http.get`
  //   under a `moonbitlang/async` event loop. Native target ships
  //   the working fetcher; JS / WASM print a diagnostic and exit
  //   pending WASI support.
  // - `package://`: resolve through registry metadata, download the
  //   zipball via `mizchi/x/http`, verify SHA-256, then unpack ZIP
  //   method 0/8 entries into the CLI package cache.
  let source = if path.has_prefix("https://") || path.has_prefix("http://") {
    match fetch_uri(path) {
      Some(body) => body
      None => {
        fail("failed to fetch \{path}")
        ""
      }
    }
  } else if is_package_uri_like(path) {
    match resolve_or_download_package_uri_to_cache(path, "") {
      Some(cached_path) =>
        @fs.read_file_to_string(cached_path) catch {
          _ => {
            fail("Cannot find module `\{path}`.")
            ""
          }
        }
      None => {
        fail("failed to resolve package URI `\{path}`")
        ""
      }
    }
  } else {
    read_with_module_paths(path)
  }
  session.set_source(path, source)
  let parsed = @pkl.parse_source(source)
  for binding in parsed.program.bindings {
    register_expr_io(path, binding.value)
  }
  match parsed.program.body {
    Some(expr) => register_expr_io(path, expr)
    None => ()
  }
  for decl in parsed.program.imports {
    load_path(
      session,
      resolve_import_path(path, decl.uri),
      push_stack(stack, path),
      loaded,
    )
  }
  match parsed.program.module_relation {
    Some(relation) =>
      load_path(
        session,
        resolve_import_path(path, relation.uri),
        push_stack(stack, path),
        loaded,
      )
    None => ()
  }
  for binding in parsed.program.bindings {
    load_expr_imports(session, path, binding.value, stack, loaded)
  }
  match parsed.program.body {
    Some(expr) => load_expr_imports(session, path, expr, stack, loaded)
    None => ()
  }
}

///|
fn print_diagnostics(diagnostics : Array[@pkl.Diagnostic]) -> Unit {
  print_diagnostics_with_source(diagnostics, "", "")
}

///|
/// PKL-107: when a diagnostic carries a byte offset (`start >= 0`),
/// project it onto a `line:column` pair by walking `source` once.
/// The output format is `path:line:column: message` so editors / IDEs
/// can jump to the location. Diagnostics without positions render
/// as just `message`, matching the pre-PKL-107 behaviour.
fn print_diagnostics_with_source(
  diagnostics : Array[@pkl.Diagnostic],
  path : String,
  source : String,
) -> Unit {
  for diagnostic in diagnostics {
    if diagnostic.start >= 0 && source != "" {
      let (line, column) = offset_to_line_column(source, diagnostic.start)
      let prefix = if path == "" {
        "\{line}:\{column}"
      } else {
        "\{path}:\{line}:\{column}"
      }
      println("\{prefix}: \{diagnostic.message}")
    } else {
      println(diagnostic.message)
    }
  }
}

///|
fn offset_to_line_column(source : String, offset : Int) -> (Int, Int) {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  let cap = if offset < source.length() { offset } else { source.length() }
  while i < cap {
    let c = source[i].to_int().unsafe_to_char()
    if c == '\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    i = i + 1
  }
  (line, column)
}

///|
/// PKL-128d: emit a short structured summary of every annotation
/// captured by the parser. Output shape:
///
/// ```
/// annotation Deprecated on module: ParenBody=("removed in v3")
/// annotation ModuleInfo on module: BraceBody=(minPklVersion = "0.31.0")
/// annotation Since on class Box: NoBody=()
/// ```
///
/// Only emits when at least one annotation was captured so the
/// existing `parse → ok` smoke for annotation-free sources is
/// preserved byte-for-byte.
fn print_annotation_summary(program : @pkl.Program) -> Unit {
  let any = program.module_annotations.length() > 0 ||
    program.declarations
    .iter()
    .any(fn(d) {
      match d {
        ClassDeclaration(cd) => cd.annotations.length() > 0
        FunctionDeclaration(fd) => fd.annotations.length() > 0
        TypeAliasDeclaration(td) => td.annotations.length() > 0
      }
    })
  if !any {
    return
  }
  for a in program.module_annotations {
    println(
      "annotation \{a.class_name} on module: \{render_annotation_body(a)}",
    )
  }
  for decl in program.declarations {
    match decl {
      ClassDeclaration(cd) =>
        for a in cd.annotations {
          println(
            "annotation \{a.class_name} on class \{cd.name}: \{render_annotation_body(a)}",
          )
        }
      FunctionDeclaration(fd) =>
        for a in fd.annotations {
          println(
            "annotation \{a.class_name} on function \{fd.name}: \{render_annotation_body(a)}",
          )
        }
      TypeAliasDeclaration(td) =>
        for a in td.annotations {
          println(
            "annotation \{a.class_name} on typealias \{td.name}: \{render_annotation_body(a)}",
          )
        }
    }
  }
}

///|
fn render_annotation_body(a : @pkl.Annotation) -> String {
  match a.body_kind {
    NoBody => "NoBody=()"
    ParenBody => "ParenBody=(\{a.body_text})"
    BraceBody => "BraceBody=(\{a.body_text})"
  }
}

///|
fn parse_file(path : String) -> Bool {
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      println("failed to read \{path}")
      return false
    }
  }
  let parsed = @pkl.parse_source(source)
  if parsed.diagnostics.length() > 0 {
    print_diagnostics_with_source(parsed.diagnostics, path, source)
    false
  } else {
    true
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  // PKL-132x: `mpkl stdlib` takes no positional file argument — it
  // runs the in-process stdlib probe table and exits with the result.
  // Dispatch it before the standard `<cmd> <file>` argc check so a
  // bare `mpkl stdlib` invocation isn't rejected as malformed.
  if args.length() >= 2 && args[1] == "stdlib" {
    run_stdlib_check()
    return
  }
  if args.length() < 3 {
    usage()
    @sys.exit(1)
  }
  let command = args[1]
  if command == "parse-many" {
    let mut passed = 0
    let mut failed = 0
    for i = 2; i < args.length(); i = i + 1 {
      if parse_file(args[i]) {
        passed += 1
      } else {
        failed += 1
      }
    }
    if failed > 0 {
      println("failed \{failed} of \{passed + failed}")
      @sys.exit(1)
    }
    println("ok \{passed}")
    return
  }
  // Pull out optional flags after the command. `eval` understands
  // `-f <format>` / `--format <format>`; `test` understands
  // `--overwrite` to regenerate the examples golden file. Unknown
  // tokens are treated as positional arguments, which keeps the legacy
  // single-file form working.
  let mut format = "pcf"
  let mut format_explicit = false
  let mut overwrite = false
  // PKL-131b: codegen target, parsed from `-t` / `--target`. Only
  // `moonbit` is wired today; the dispatcher rejects everything else
  // with the list of supported names so a typo is loud rather than
  // silently misrouting.
  let mut codegen_target = "moonbit"
  let positional : Array[String] = []
  // PKL-106: sandbox knobs. Each is collected as a list so multiple
  // occurrences accumulate (`-p A=1 -p B=2`, `--module-path foo
  // --module-path bar`). `--allowed-modules` takes a single `|`-
  // separated pattern argument and overwrites the previous one,
  // matching Apple Pkl's flag.
  let prop_pairs : Map[String, String] = Map([], capacity=8)
  let module_paths : Array[String] = []
  let package_caches : Array[String] = []
  let mut allowed_modules : Array[String] = []
  let mut i = 2
  while i < args.length() {
    let token = args[i]
    if token == "-f" || token == "--format" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      format = args[i + 1]
      format_explicit = true
      i = i + 2
    } else if token == "-t" || token == "--target" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      codegen_target = args[i + 1]
      i = i + 2
    } else if token == "--overwrite" {
      overwrite = true
      i = i + 1
    } else if token == "-p" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      let pair = args[i + 1]
      match pair.find("=") {
        Some(eq) => {
          let name = String::unsafe_substring(pair, start=0, end=eq)
          let value = String::unsafe_substring(
            pair,
            start=eq + 1,
            end=pair.length(),
          )
          prop_pairs[name] = value
        }
        None => fail("-p expects NAME=VALUE, got: \{pair}")
      }
      i = i + 2
    } else if token == "--module-path" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      module_paths.push(args[i + 1])
      i = i + 2
    } else if token == "--package-cache" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      package_caches.push(args[i + 1])
      i = i + 2
    } else if token == "--allowed-modules" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      allowed_modules = split_pipe(args[i + 1])
      i = i + 2
    } else {
      positional.push(token)
      i = i + 1
    }
  }
  @pkl.configure_sandbox_props(prop_pairs)
  @pkl.configure_sandbox_module_paths(module_paths)
  @pkl.configure_sandbox_package_caches(package_caches)
  @pkl.configure_sandbox_allowed_modules(allowed_modules)
  @pkl.reset_sandbox_io_cache()
  if format != "pcf" &&
    format != "json" &&
    format != "yaml" &&
    format != "properties" &&
    format != "plist" &&
    format != "textproto" &&
    format != "xml" {
    fail("unsupported format: \{format}")
  }
  if positional.length() != 1 {
    usage()
    @sys.exit(1)
  }
  let path = positional[0]
  // PKL-129: entry-point paths may themselves be URIs. Route them
  // through the same dispatcher `load_path` uses so the top-level
  // module can live on a remote URL.
  let source = if path.has_prefix("https://") || path.has_prefix("http://") {
    match fetch_uri(path) {
      Some(body) => body
      None => {
        fail("failed to fetch \{path}")
        ""
      }
    }
  } else if is_package_uri_like(path) {
    match resolve_or_download_package_uri_to_cache(path, "") {
      Some(cached_path) =>
        @fs.read_file_to_string(cached_path) catch {
          _ => {
            fail("Cannot find module `\{path}`.")
            ""
          }
        }
      None => {
        fail("failed to resolve package URI `\{path}`")
        ""
      }
    }
  } else {
    @fs.read_file_to_string(path) catch {
      _ => {
        fail("Cannot find module `\{path}`.")
        ""
      }
    }
  }
  match command {
    "parse" => {
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics_with_source(parsed.diagnostics, path, source)
        @sys.exit(1)
      }
      // PKL-128d: surface captured annotations so pkldoc / codegen
      // tooling can read them via the CLI. Printed only when at least
      // one annotation was captured, so the existing one-line `ok`
      // smoke output stays unchanged for annotation-free sources.
      print_annotation_summary(parsed.program)
      println("ok")
    }
    "check" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.typecheck_path(path) {
        TypeOk(typ) => println(@pkl.render_type(typ))
        TypeError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "eval" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(raw) => {
          // PKL-147: `output { text = "..." }` short-circuits the
          // renderer entirely — Apple Pkl writes the string verbatim.
          // Detect the slot before extract_output_value so the bypass
          // beats both the format dispatch and the renderer-class
          // auto-detection.
          match extract_output_text(raw) {
            Some(text) => {
              // PKL-148q: Apple Pkl writes `output.text` verbatim — the
              // string itself decides whether a trailing newline is
              // present. `println` would always append one and skew the
              // byte count for `api/moduleOutput`-shaped fixtures whose
              // gold ends without `\n`. `@fs.write_string_to_file` to
              // `/dev/stdout` is the smallest path to a no-newline write
              // that's available cross-target (native + js) without
              // pulling in an FFI dep just for one CLI slot.
              @fs.write_string_to_file("/dev/stdout", text) catch {
                _ => println(text)
              }
              return
            }
            None => ()
          }
          // PKL-097: Apple Pkl uses a module-level `output { value =
          // ...; renderer = ... }` block to drive what `pkl eval`
          // returns. Extract `output.value` so fixtures that route
          // their data through it render only that subtree instead
          // of the whole module envelope.
          let xml_options = extract_xml_renderer_options(raw)
          let value = extract_output_value(raw)
          // PKL-104: when the user didn't pass `-f / --format`, honor
          // the renderer class declared in `output { renderer = new
          // JsonRenderer { ... } }`. The class name is read directly
          // from the parsed AST (the eval result is a generic
          // ObjectValue that doesn't carry its source class). Explicit
          // `-f` always wins so existing test fixtures keep behaving.
          if !format_explicit {
            match detect_output_renderer_format(source) {
              Some(detected) => format = detected
              None => ()
            }
          }
          // The format string is validated up-front, so this match is
          // exhaustive at runtime. The explicit `pcf` arm doubles as
          // documentation: a future renderer added here surfaces as a
          // missing-arm warning rather than a silent fallback.
          match format {
            "json" => println(@pkl.render_value_as_json(value))
            "yaml" => {
              // render_value_as_yaml already terminates each line with
              // `\n`, including the final entry. Drop the trailing
              // newline so `println` does not double-up at end-of-stream.
              let yaml = @pkl.render_value_as_yaml(value)
              let trimmed = if yaml.has_suffix("\n") {
                String::unsafe_substring(yaml, start=0, end=yaml.length() - 1)
              } else {
                yaml
              }
              println(trimmed)
            }
            "properties" => {
              // Properties output is also line-terminated per entry;
              // strip the trailing newline so `println` keeps a single
              // final newline.
              let props = @pkl.render_value_as_properties(value)
              let trimmed = if props.has_suffix("\n") {
                String::unsafe_substring(props, start=0, end=props.length() - 1)
              } else {
                props
              }
              println(trimmed)
            }
            "pcf" => println(@pkl.render_value(value))
            "plist" => {
              // PKL-126a: `render_value_as_plist` already terminates
              // the document with `</plist>\n`. Drop the trailing
              // newline so `println` keeps a single final newline.
              let plist = @pkl.render_value_as_plist(value)
              let trimmed = if plist.has_suffix("\n") {
                String::unsafe_substring(plist, start=0, end=plist.length() - 1)
              } else {
                plist
              }
              println(trimmed)
            }
            "textproto" => {
              let textproto = @pkl.render_value_as_textproto(value)
              let trimmed = if textproto.has_suffix("\n") {
                String::unsafe_substring(
                  textproto,
                  start=0,
                  end=textproto.length() - 1,
                )
              } else {
                textproto
              }
              println(trimmed)
            }
            "xml" => {
              let (root_name, indent_text, xml_version) = xml_options
              let xml = @pkl.render_value_as_xml_with_options(
                value, root_name, indent_text, xml_version,
              )
              let trimmed = if xml.has_suffix("\n") {
                String::unsafe_substring(xml, start=0, end=xml.length() - 1)
              } else {
                xml
              }
              println(trimmed)
            }
            _ => fail("unsupported format: \{format}")
          }
        }
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "test" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(value) => {
          let facts_summary = run_pkl_test(value)
          for line in facts_summary.lines {
            println(line)
          }
          // PKL-100: `examples` are tracked alongside `facts`. The
          // facts walker keeps its own summary (rendered above); the
          // examples diff runs as a second pass and contributes its own
          // pass / fail lines plus an additional non-zero exit on
          // mismatch / missing golden.
          let examples_summary = run_pkl_examples_test(value, path, overwrite)
          for line in examples_summary.lines {
            println(line)
          }
          if facts_summary.failed > 0 || examples_summary.failed > 0 {
            @sys.exit(1)
          }
        }
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "analyze" => {
      // PKL-102: lightweight lint pass over the parsed module.
      // Reports unused locals / imports / private-class properties
      // and module-level shadowing. Exits non-zero when any finding
      // surfaces so editors / CI can fail on lint regressions.
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics_with_source(parsed.diagnostics, path, source)
        @sys.exit(1)
      }
      let findings = @pkl.lint_program(parsed.program)
      for finding in findings {
        println("\{path}: \{finding.rule}: \{finding.message}")
      }
      if findings.length() > 0 {
        @sys.exit(1)
      }
      println("ok")
    }
    "codegen" => {
      // PKL-131 / PKL-131b: lower a typechecked Pkl module to the
      // target language. Only `moonbit` is wired today; future
      // targets (Java / Kotlin / Swift / Go / TypeScript) extend the
      // `CodegenTarget` enum and the `@pkl.codegen` dispatcher and
      // are surfaced here via the same `-t` / `--target` flag.
      if codegen_target != "moonbit" && codegen_target != "mbt" {
        fail(
          "unsupported codegen target: \{codegen_target} (supported: moonbit)",
        )
      }
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics_with_source(parsed.diagnostics, path, source)
        @sys.exit(1)
      }
      let generated = @pkl.codegen(parsed.program, @pkl.MoonBit)
      let trimmed = if generated.has_suffix("\n") {
        String::unsafe_substring(generated, start=0, end=generated.length() - 1)
      } else {
        generated
      }
      println(trimmed)
    }
    "format" => {
      // PKL-099: parse the source, evaluate it through the existing
      // `AnalysisSession`, and re-emit the resolved module via the PCF
      // renderer. This is the first-cut formatter: input that fails to
      // evaluate (constraint reject, type error, etc.) fails the
      // command; structural and whitespace differences in the input
      // collapse to the renderer's canonical form. A trivia-preserving
      // formatter that round-trips comments and original layout is a
      // follow-up — the CST already carries the data, so the upgrade
      // path is purely on the emit side.
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics(parsed.diagnostics)
        @sys.exit(1)
      }
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(value) => println(@pkl.render_value(value))
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    _ => {
      usage()
      @sys.exit(1)
    }
  }
}

///|
priv struct PklTestSummary {
  lines : Array[String]
  failed : Int
}

///|
/// Walk a `facts: Mapping<String, Listing<Boolean>>` member at the
/// module level and report per-fact pass / fail. A fact passes when
/// every Boolean in its Listing is `true`; the first non-true value
/// (or any non-Boolean element) flips the fact to failed. Modules
/// without a `facts` member are treated as zero tests, which matches
/// `moon test`'s behaviour for empty test files.
fn run_pkl_test(value : @pkl.Value) -> PklTestSummary {
  let lines : Array[String] = []
  let mut passed = 0
  let mut failed = 0
  let facts : @pkl.Value? = lookup_module_member(value, "facts")
  match facts {
    Some(@pkl.MappingValue(entries))
    | Some(@pkl.DefaultedMappingValue(_, entries, _)) =>
      for entry in entries {
        let name = match entry.key {
          @pkl.StringValue(s) => s
          _ => "<non-string key>"
        }
        let elements = match entry.value {
          @pkl.ListingValue(xs) | @pkl.DefaultedListingValue(_, xs, _) => xs
          _ => []
        }
        let mut fact_failed = false
        let mut total = 0
        let mut bad_index = -1
        for i = 0; i < elements.length(); i = i + 1 {
          total += 1
          match elements[i] {
            @pkl.BoolValue(true) => ()
            _ =>
              if !fact_failed {
                fact_failed = true
                bad_index = i
              }
          }
        }
        if fact_failed {
          failed += 1
          lines.push(
            "FAIL \{name}: assertion #\{bad_index + 1} of \{total} did not evaluate to true",
          )
        } else {
          passed += 1
          lines.push("PASS \{name} (\{total} assertions)")
        }
      }
    Some(_) =>
      lines.push(
        "test runner expected `facts` to be a Mapping<String, Listing<Boolean>>",
      )
    None => ()
  }
  lines.push("\{passed} passed, \{failed} failed")
  { lines, failed }
}

///|
/// PKL-100 / PKL-095 shared helper: pick a top-level module member by
/// name. Returns the member value when the module is an `ObjectValue`
/// carrying that name; everything else (non-object module, missing
/// member) collapses to `None` so callers can branch on absence.
fn lookup_module_member(value : @pkl.Value, name : String) -> @pkl.Value? {
  match value {
    @pkl.ObjectValue(members) => {
      let mut found : @pkl.Value? = None
      for entry in members {
        if entry.name == name {
          found = Some(entry.value)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// PKL-100: walk the `examples` member and diff each example's rendered
/// PCF text against the corresponding section of the
/// `<path>-expected.pcf` golden file. On `--overwrite` the golden is
/// regenerated wholesale; otherwise mismatches surface as `FAIL` lines
/// and force a non-zero exit. The minimal envelope format is the
/// rendered `examples { ... }` block verbatim; richer per-example diffs
/// (with byte-level reporting) layer on top of this once a structured
/// golden format is introduced.
fn run_pkl_examples_test(
  value : @pkl.Value,
  path : String,
  overwrite : Bool,
) -> PklTestSummary {
  let lines : Array[String] = []
  let mut failed = 0
  match lookup_module_member(value, "examples") {
    Some(examples_value) => {
      let envelope = @pkl.ObjectValue([
        {
          name: "examples",
          value: examples_value,
          source: None,
          annotations: [],
        },
      ])
      let rendered = @pkl.render_value(envelope) + "\n"
      let golden_path = path + "-expected.pcf"
      if overwrite {
        @fs.write_string_to_file(golden_path, rendered) catch {
          _ => {
            failed = failed + 1
            lines.push(
              "FAIL examples could not write golden file \{golden_path}",
            )
          }
        }
        lines.push("OVERWRITE \{golden_path}")
      } else {
        let expected = @fs.read_file_to_string(golden_path) catch { _ => "" }
        if expected == "" {
          failed = failed + 1
          lines.push("FAIL examples missing golden file \{golden_path}")
        } else if expected == rendered {
          let count = match examples_value {
            @pkl.MappingValue(entries)
            | @pkl.DefaultedMappingValue(_, entries, _) => entries.length()
            _ => 0
          }
          lines.push("PASS examples (\{count} examples)")
        } else {
          failed = failed + 1
          lines.push("FAIL examples diff against \{golden_path}")
        }
      }
    }
    None => ()
  }
  { lines, failed }
}

///|
/// PKL-097: If the module exposes an `output { value = ... }` member,
/// return that subtree so the renderer dispatches on it instead of
/// the whole module envelope. Modules without an `output.value` chain
/// fall through unchanged so existing single-binding fixtures keep
/// rendering the entire module the same way they did before.
/// PKL-104: walk the parsed module's `output { renderer = new
/// JsonRenderer { ... } }` block and map the renderer's class name
/// onto the existing CLI format string. Returns `None` when the
/// module has no `output.renderer` clause, or when the renderer's
/// class doesn't match a renderer pkl-mbt knows about (pkl-binary is
/// still outside the text renderer set). The format is read from
/// the parsed AST rather than the eval result because the eval
/// collapses the renderer class to a plain ObjectValue without
/// retaining the source class.
fn detect_output_renderer_format(source : String) -> String? {
  let parsed = @pkl.parse_source(source)
  for binding in parsed.program.bindings {
    if binding.name == "output" {
      match binding.value {
        ObjectLiteral(members) =>
          for field in members {
            if field.name == "renderer" {
              match renderer_format_from_expr(field.value) {
                Some(f) => return Some(f)
                None => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  None
}

///|
fn renderer_format_from_expr(expr : @pkl.Expr) -> String? {
  match expr {
    TypedObjectLiteral(class_name, _) => renderer_format_from_class(class_name)
    AmendExpr(base, _) => renderer_format_from_expr(base)
    _ => None
  }
}

///|
fn renderer_format_from_class(class_name : String) -> String? {
  // The class name often arrives qualified (`pkl.JsonRenderer` /
  // `base.PcfRenderer`). Strip a trailing `Renderer` suffix and any
  // qualifier prefix before matching so both forms work.
  let raw = class_name
  let stripped = match raw.rev_find(".") {
    Some(idx) => String::unsafe_substring(raw, start=idx + 1, end=raw.length())
    None => raw
  }
  match stripped {
    "JsonRenderer" => Some("json")
    "YamlRenderer" => Some("yaml")
    "PropertiesRenderer" => Some("properties")
    "PcfRenderer" => Some("pcf")
    "PListRenderer" => Some("plist")
    "XmlRenderer" => Some("xml")
    "Renderer" =>
      if raw == "xml.Renderer" {
        Some("xml")
      } else if raw == "protobuf.Renderer" {
        Some("textproto")
      } else {
        None
      }
    _ => None
  }
}

///|
fn extract_xml_renderer_options(value : @pkl.Value) -> (String, String, String) {
  let mut root_name = "root"
  let mut indent_text = "  "
  let mut xml_version = "1.0"
  match value {
    @pkl.ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            @pkl.ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  match output_member.value {
                    @pkl.ObjectValue(renderer_members) =>
                      for renderer_member in renderer_members {
                        match (renderer_member.name, renderer_member.value) {
                          ("rootElementName", @pkl.StringValue(s)) =>
                            root_name = s
                          ("indent", @pkl.StringValue(s)) => indent_text = s
                          ("xmlVersion", @pkl.StringValue(s)) => xml_version = s
                          _ => ()
                        }
                      }
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  (root_name, indent_text, xml_version)
}

///|
fn extract_output_value(value : @pkl.Value) -> @pkl.Value {
  match value {
    @pkl.ObjectValue(members) => {
      let mut output_value : @pkl.Value? = None
      let mut has_output = false
      let mut omit_null = false
      for entry in members {
        if entry.name == "output" {
          has_output = true
          match entry.value {
            @pkl.ObjectValue(sub_members) =>
              for sub in sub_members {
                if sub.name == "value" {
                  output_value = Some(sub.value)
                }
                // PKL-147: read `output.renderer.omitNullProperties`
                // so the env strip below can drop null members at the
                // module-body level — snippetTest's inherited renderer
                // sets this to true.
                if sub.name == "renderer" {
                  match sub.value {
                    @pkl.ObjectValue(renderer_members) =>
                      for r in renderer_members {
                        if r.name == "omitNullProperties" {
                          match r.value {
                            @pkl.BoolValue(b) => omit_null = b
                            _ => ()
                          }
                        }
                      }
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
      let projected = match output_value {
        Some(v) => v
        None =>
          // PKL-104: `output { renderer = ... }` without an explicit
          // `output.value` projects the module's *other* properties,
          // not the `output` block itself. Strip `output` from the
          // rendered envelope so the renderer doesn't echo its own
          // configuration into the output (matches Apple Pkl's
          // module-body rendering rules).
          if has_output {
            let visible : Array[@pkl.ValueMember] = []
            for entry in members {
              if entry.name == "output" {
                continue
              }
              visible.push(entry)
            }
            @pkl.ObjectValue(visible)
          } else {
            value
          }
      }
      // PKL-147: when the inherited renderer requested
      // `omitNullProperties = true`, scrub null members at every
      // nesting depth before handing the value off to the renderer.
      // Apple Pkl's PcfRenderer pulls this directly from the renderer
      // settings rather than the surrounding value; we approximate by
      // pre-processing the value tree at the CLI boundary.
      if omit_null {
        strip_null_object_properties(projected)
      } else {
        projected
      }
    }
    _ => value
  }
}

///|
/// PKL-147: recursively drop members whose value is `null` from every
/// nested ObjectValue inside the given value. ListingValue / MappingValue
/// elements are not touched — Apple Pkl's `omitNullProperties` only
/// affects object properties.
fn strip_null_object_properties(value : @pkl.Value) -> @pkl.Value {
  match value {
    @pkl.ObjectValue(members) => {
      let kept : Array[@pkl.ValueMember] = []
      for entry in members {
        if entry.value is @pkl.NullValue {
          continue
        }
        kept.push({
          name: entry.name,
          value: strip_null_object_properties(entry.value),
          source: None,
          annotations: entry.annotations,
        })
      }
      @pkl.ObjectValue(kept)
    }
    @pkl.ListingValue(elements) => {
      let mapped : Array[@pkl.Value] = []
      for element in elements {
        mapped.push(strip_null_object_properties(element))
      }
      @pkl.ListingValue(mapped)
    }
    @pkl.DefaultedListingValue(raw, elements, default_value) => {
      let mapped_raw : Array[@pkl.Value] = []
      for element in raw {
        mapped_raw.push(strip_null_object_properties(element))
      }
      let mapped : Array[@pkl.Value] = []
      for element in elements {
        mapped.push(strip_null_object_properties(element))
      }
      @pkl.DefaultedListingValue(
        mapped_raw,
        mapped,
        strip_null_object_properties(default_value),
      )
    }
    @pkl.MappingValue(entries) => {
      let mapped : Array[@pkl.ValueEntry] = []
      for entry in entries {
        mapped.push({
          key: entry.key,
          value: strip_null_object_properties(entry.value),
        })
      }
      @pkl.MappingValue(mapped)
    }
    @pkl.DefaultedMappingValue(raw, entries, default_value) => {
      let mapped_raw : Array[@pkl.ValueEntry] = []
      for entry in raw {
        mapped_raw.push({
          key: entry.key,
          value: strip_null_object_properties(entry.value),
        })
      }
      let mapped : Array[@pkl.ValueEntry] = []
      for entry in entries {
        mapped.push({
          key: entry.key,
          value: strip_null_object_properties(entry.value),
        })
      }
      @pkl.DefaultedMappingValue(
        mapped_raw,
        mapped,
        strip_null_object_properties(default_value),
      )
    }
    other => other
  }
}

///|
/// PKL-147: extract `output.text` if set. The CLI emits this string
/// verbatim (bypassing the renderer), matching Apple Pkl's text-output
/// projection. snippetTest fixtures lean on this slot.
fn extract_output_text(value : @pkl.Value) -> String? {
  match value {
    @pkl.ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            @pkl.ObjectValue(sub_members) =>
              for sub in sub_members {
                if sub.name == "text" {
                  match sub.value {
                    @pkl.StringValue(text) => return Some(text)
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  None
}
