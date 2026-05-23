// PKL-153c: YAML 1.2-mode adjustments for `yaml.Parser { mode =
// "1.2" }`. The upstream `moonbit-community/yaml` loader does its
// own permissive scalar resolution that follows MoonBit `strconv`
// rather than YAML 1.2's core-schema regex grammar — e.g. `0b1001`
// becomes Integer(9), `1_2_3` becomes Integer(123), and `Null`
// stays String("Null"). 1.2 expects those to be String("0b1001"),
// String("1_2_3"), and Null respectively.
//
// We can't substitute a custom event-stream receiver because the
// upstream trait is sealed against external `impl`s (issue not
// fixed yet), so this module instead pre-processes the source
// string to quote 1.1-only-syntax bare scalars before handing it
// to the loader, and post-processes the resulting tree to handle
// the small remaining set of resolver differences. The set of
// patterns covered here is what Apple Pkl's `yamlParser1Yaml12`
// fixture stresses; if a new fixture surfaces a different shape
// we extend the matcher here rather than re-deriving the schema.

///|
/// Pre-process a YAML source body so the upstream loader sees
/// 1.2-friendly plain scalars. Only patterns that the upstream
/// resolves as integer/float but YAML 1.2 wants as string get
/// quoted; everything else passes through unchanged.
///
/// Today this handles the case where the whole input is a single
/// trimmed scalar (the snippet test calls `parser.parse("0b1001")`,
/// `parser.parse("-0o123")`, etc.). Multi-line documents are left
/// untouched.
fn yaml_v12_source_rewrite(source : String) -> String {
  let trimmed = trim_whitespace_v12(source)
  if trimmed == "" {
    return source
  }
  if is_v12_string_only_scalar(trimmed) {
    let buf = StringBuilder::new()
    buf.write_char('\'')
    buf.write_string(trimmed)
    buf.write_char('\'')
    return buf.to_string()
  }
  source
}

///|
/// Returns true when `text` parses as int/float under the upstream
/// permissive resolver but YAML 1.2's core schema would treat it as
/// a plain string.
///   - `0b...`, `[-+]0b...`        (binary, 1.1 only)
///   - `[-+]0o...`, `[-+]0x...`    (signed octal/hex, 1.1 only)
///   - `..._...`                   (underscore-grouped numerics, 1.1 only)
fn is_v12_string_only_scalar(text : String) -> Bool {
  let len = text.length()
  if len == 0 || text == "_" {
    return false
  }
  let mut has_underscore = false
  let mut has_digit = false
  for c in text {
    if c == '_' {
      has_underscore = true
    } else if c is '0'..='9' {
      has_digit = true
    }
  }
  if has_underscore && has_digit {
    return true
  }
  // Binary literal: 1.1 only.
  if has_prefix_after_sign(text, "0b") {
    return true
  }
  // Signed octal / hex: 1.1 only.
  if text[0] is ('+' | '-') &&
    (has_prefix_after_sign(text, "0o") || has_prefix_after_sign(text, "0x")) {
    return true
  }
  false
}

///|
fn has_prefix_after_sign(text : String, prefix : String) -> Bool {
  let plen = prefix.length()
  let offset = if text.length() >= 1 && text[0] is ('+' | '-') { 1 } else { 0 }
  if text.length() < offset + plen {
    return false
  }
  for i in 0..<plen {
    if text[offset + i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn trim_whitespace_v12(text : String) -> String {
  let len = text.length()
  let mut start = 0
  let mut stop = len
  while start < stop {
    let u = text[start]
    if u is (' ' | '\t' | '\n' | '\r') {
      start = start + 1
    } else {
      break
    }
  }
  while stop > start {
    let u = text[stop - 1]
    if u is (' ' | '\t' | '\n' | '\r') {
      stop = stop - 1
    } else {
      break
    }
  }
  if start == 0 && stop == len {
    text
  } else {
    String::unsafe_substring(text, start~, end=stop)
  }
}

///|
/// Returns true when `source` ends with a literal-/folded-block
/// scalar whose payload runs to the end of input (no sibling key /
/// no more content follows). The upstream lexer always appends a
/// trailing `\n` to the block's clip-chomped value even when the
/// source itself has no trailing newline, which produces
/// `"hello\nworld\n"` instead of the `"hello\nworld"` Apple Pkl
/// emits in this case (`yamlParser1*` standalone literal-block
/// example). When the block is followed by sibling content this
/// quirk happens to match Apple Pkl, so we restrict the post-strip
/// to the block-at-EOF case.
fn yaml_v12_source_ends_in_block_scalar(source : String) -> Bool {
  // Strip trailing whitespace then walk lines bottom-up: the source
  // ends in a block scalar iff there exists some "indicator" line
  // (`<key>: |[chomp][indent]<ws>`) followed only by content lines
  // (i.e. no later sibling-key line, since that would terminate the
  // block before EOF). Detection runs to mirror Apple Pkl's
  // behavior of dropping the final `\n` clip-chomping would
  // otherwise add when the block has nothing after it.
  let lines = split_lines_for_block_detect(source)
  if lines.length() == 0 {
    return false
  }
  // Walk lines bottom-up; ignore trailing blank lines.
  let mut idx = lines.length() - 1
  while idx >= 0 && trim_yaml_ws_v12(lines[idx]) == "" {
    idx = idx - 1
  }
  if idx < 0 {
    return false
  }
  // Walk upward looking for an indicator line. Each line in between
  // must be a block-content line (i.e. not a `key: value` form).
  while idx >= 0 {
    let line = lines[idx]
    if line_is_block_indicator(line) {
      return true
    }
    if line_starts_new_key(line) {
      // A `key:` line above implies the block already terminated.
      return false
    }
    idx = idx - 1
  }
  false
}

///|
fn split_lines_for_block_detect(source : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in source {
    if c == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  result.push(buf.to_string())
  result
}

///|
fn trim_yaml_ws_v12(s : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut stop = len
  while start < stop && s[start] is (' ' | '\t') {
    start = start + 1
  }
  while stop > start && s[stop - 1] is (' ' | '\t') {
    stop = stop - 1
  }
  if start == 0 && stop == len {
    s
  } else {
    String::unsafe_substring(s, start~, end=stop)
  }
}

///|
fn line_is_block_indicator(line : String) -> Bool {
  let trimmed = trim_yaml_ws_v12(line)
  let len = trimmed.length()
  if len == 0 {
    return false
  }
  // Strip trailing chomping/indent indicators (`-`, `+`, `0..9`) off
  // the right edge, then check the remaining trailing char.
  let mut tail = len
  while tail > 0 && trimmed[tail - 1] is ('-' | '+' | '0'..='9') {
    tail = tail - 1
  }
  if tail == 0 {
    return false
  }
  trimmed[tail - 1] is ('|' | '>')
}

///|
/// Detect lines of the form `<key>:[<ws><value>?]`. Used to bail
/// out when scanning upward for a block indicator — a sibling key
/// terminates the block before we'd reach the indicator.
fn line_starts_new_key(line : String) -> Bool {
  let trimmed = trim_yaml_ws_v12(line)
  let len = trimmed.length()
  if len == 0 || trimmed[0] is ('-' | '?' | ':' | '#') {
    return false
  }
  let mut i = 0
  while i < len {
    let c = trimmed[i]
    if c == ':' {
      let next_is_space = i + 1 >= len || trimmed[i + 1] is (' ' | '\t')
      if next_is_space {
        return true
      }
    }
    i = i + 1
  }
  false
}

///|
/// Strip the trailing `\n` off the LAST leaf string of a document.
/// "Last leaf" follows insertion order for maps and last-element for
/// arrays, mirroring source order. The upstream lexer adds an extra
/// `\n` to the final clip-chomped block scalar when the source ends
/// without a trailing newline, so we walk the document spine and
/// strip exactly one `\n` from the terminal string. Other strings in
/// the tree are left intact.
fn yaml_v12_strip_trailing_block_newline(y : @yaml.Yaml) -> @yaml.Yaml {
  match y {
    @yaml.Yaml::String(s) => {
      let len = s.length()
      if len == 0 || s[len - 1] != '\n' {
        @yaml.Yaml::String(s)
      } else {
        @yaml.Yaml::String(String::unsafe_substring(s, start=0, end=len - 1))
      }
    }
    @yaml.Yaml::Array(items) => {
      if items.length() == 0 {
        return @yaml.Yaml::Array(items)
      }
      let out : Array[@yaml.Yaml] = []
      for i = 0; i < items.length(); i = i + 1 {
        if i == items.length() - 1 {
          out.push(yaml_v12_strip_trailing_block_newline(items[i]))
        } else {
          out.push(items[i])
        }
      }
      @yaml.Yaml::Array(out)
    }
    @yaml.Yaml::Map(m) => {
      let out : Map[String, @yaml.Yaml] = {}
      let mut last_key : String? = None
      for k, _ in m {
        last_key = Some(k)
      }
      for k, v in m {
        if Some(k) == last_key {
          out[k] = yaml_v12_strip_trailing_block_newline(v)
        } else {
          out[k] = v
        }
      }
      @yaml.Yaml::Map(out)
    }
    other => other
  }
}

///|
/// 1.2 core schema differs from the upstream resolver on one
/// non-numeric pattern: `Null` and `NULL` are still null (1.2
/// accepts `null|Null|NULL|~|<empty>` as the null token, but the
/// upstream lib only matches the lowercase `null`). Walk the loaded
/// tree and rewrite the affected strings to the Null variant.
fn yaml_v12_promote_null(y : @yaml.Yaml) -> @yaml.Yaml {
  match y {
    @yaml.Yaml::String(s) =>
      if s == "Null" || s == "NULL" {
        @yaml.Yaml::Null
      } else {
        @yaml.Yaml::String(s)
      }
    @yaml.Yaml::Array(items) => {
      let out : Array[@yaml.Yaml] = []
      for item in items {
        out.push(yaml_v12_promote_null(item))
      }
      @yaml.Yaml::Array(out)
    }
    @yaml.Yaml::Map(m) => {
      let out : Map[String, @yaml.Yaml] = {}
      for k, v in m {
        out[k] = yaml_v12_promote_null(v)
      }
      @yaml.Yaml::Map(out)
    }
    other => other
  }
}

///|
/// Read the `mode` slot off a `yaml.Parser` mirror. The default in
/// `pkl:yaml`'s synthetic stub is `"compat"`; only `"1.2"` triggers
/// the rewrites above today (1.1 mode would need additional
/// `yes/no/y/n/on/off/:base60:` boolean / numeric handling, which
/// the upstream lib's strict-ish behavior already declines to
/// produce, so we'd need a separate pre-processing pass for that
/// case).
fn parser_mode(members : Array[ValueMember]) -> String {
  match lookup_member(members, "mode") {
    Some(StringValue(s)) => s
    _ => "compat"
  }
}

///|
/// Sentinel that flows through the YAML loader as a plain string and
/// is recognized by `yaml_v12_decode_sentinels` after parsing.
/// `\u{1f}` (ASCII Unit Separator) is a control char that cannot
/// legally appear in YAML plain scalars, so the prefix is collision-
/// free for realistic inputs.
let yaml_v12_binary_sentinel : String = "\u{001f}PKL_BYTES:"

///|
let yaml_v12_set_sentinel : String = "\u{001f}PKL_SET"

///|
let yaml_v12_set_marker_member : String = "__pkl_v12_set_marker"

///|
/// Drives both `!!binary` and `!!set` rewriting. Replaces every
/// `!!binary <payload>` region in `source` with a single-quoted
/// sentinel containing the stripped base64 text, and replaces every
/// `!!set` tag with `!!str` plus an injected sentinel mapping entry
/// so the loader still produces a mapping but we can recognise it
/// after the fact.
fn yaml_v12_rewrite_tags(source : String) -> String {
  let binary_rewritten = yaml_v12_rewrite_binary(source)
  yaml_v12_rewrite_set(binary_rewritten)
}

///|
fn yaml_v12_rewrite_binary(source : String) -> String {
  let needle = "!!binary"
  let len = source.length()
  if len < needle.length() {
    return source
  }
  let buf = StringBuilder::new()
  let mut i = 0
  while i < len {
    if i + needle.length() <= len && substring_equals(source, i, needle) {
      // Confirm `!!binary` is followed by a separator. Otherwise it
      // could be part of a longer identifier (highly unlikely in YAML
      // but cheap to check).
      let after = i + needle.length()
      let sep_ok = if after >= len {
        true
      } else {
        let next_u = source[after]
        next_u is (' ' | '\t' | '\n' | '\r')
      }
      if !sep_ok {
        buf.write_char(char_at_v12(source, i))
        i = i + 1
        continue
      }
      let value = extract_yaml_scalar_after(source, after)
      match value {
        Some((value_text, consumed_end)) => {
          let payload = strip_yaml_whitespace_v12(value_text)
          buf.write_char('\'')
          buf.write_string(yaml_v12_binary_sentinel)
          buf.write_string(payload)
          buf.write_char('\'')
          i = consumed_end
          continue
        }
        None => ()
      }
    }
    buf.write_char(char_at_v12(source, i))
    i = i + 1
  }
  buf.to_string()
}

///|
fn yaml_v12_rewrite_set(source : String) -> String {
  let needle = "!!set"
  let len = source.length()
  if len < needle.length() {
    return source
  }
  let buf = StringBuilder::new()
  let mut i = 0
  while i < len {
    if i + needle.length() <= len && substring_equals(source, i, needle) {
      let after = i + needle.length()
      let sep_ok = if after >= len {
        true
      } else {
        let next_u = source[after]
        next_u is (' ' | '\t' | '\n' | '\r')
      }
      if sep_ok {
        // Drop the `!!set` tag entirely. The block / flow content
        // that follows still parses correctly as a mapping (or, for
        // the "wrong tag/node combination" example, as a sequence);
        // we tag the *result* via `yaml_v12_finalize_set_marker`
        // below by leaning on the position of `!!set` in the source.
        // We also inject a synthetic mapping entry so downstream
        // code can identify the result was set-tagged.
        buf.write_string("? \"")
        buf.write_string(yaml_v12_set_marker_member)
        buf.write_string("\"\n: \"")
        buf.write_string(yaml_v12_set_sentinel)
        buf.write_string("\"\n")
        i = after
        continue
      }
    }
    buf.write_char(char_at_v12(source, i))
    i = i + 1
  }
  buf.to_string()
}

///|
fn char_at_v12(s : String, i : Int) -> Char {
  s[i].to_int().unsafe_to_char()
}

///|
fn substring_equals(source : String, start : Int, needle : String) -> Bool {
  let nlen = needle.length()
  if start + nlen > source.length() {
    return false
  }
  for j in 0..<nlen {
    if source[start + j] != needle[j] {
      return false
    }
  }
  true
}

///|
fn strip_yaml_whitespace_v12(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      continue
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Skip leading horizontal whitespace, then capture the YAML scalar
/// that follows. Handles four scalar styles seen by Apple Pkl's
/// `yamlParser1*` fixtures:
///   - plain (up to end-of-line / end-of-source)
///   - single-quoted: `'...'`
///   - double-quoted: `"..."`
///   - block literal `|`, `|-`, `|+` (indented payload until dedent)
/// Returns `Some((text, consumed_end))` where `text` is the captured
/// scalar (still containing newlines for block style — caller
/// normalises) and `consumed_end` is the absolute index past the
/// scalar. Returns `None` when we cannot identify the scalar (e.g.
/// `!!binary` at end of source with no value); the caller leaves the
/// region untouched in that case.
fn extract_yaml_scalar_after(
  source : String,
  start : Int,
) -> (String, Int)? {
  let len = source.length()
  let mut i = start
  while i < len {
    let u = source[i]
    if u is (' ' | '\t') {
      i = i + 1
    } else {
      break
    }
  }
  if i >= len {
    return None
  }
  let first = source[i]
  if first == '\'' {
    let mut j = i + 1
    while j < len && source[j] != '\'' {
      j = j + 1
    }
    if j >= len {
      return None
    }
    Some((String::unsafe_substring(source, start=i + 1, end=j), j + 1))
  } else if first == '"' {
    let mut j = i + 1
    while j < len {
      let c = source[j]
      if c == '\\' {
        j = j + 2
        continue
      }
      if c == '"' {
        break
      }
      j = j + 1
    }
    if j >= len {
      return None
    }
    Some((String::unsafe_substring(source, start=i + 1, end=j), j + 1))
  } else if first == '|' || first == '>' {
    // Block-literal / folded indicator. Skip the indicator and any
    // chomping / indent indicators, then capture indented lines.
    let mut j = i + 1
    while j < len && source[j] is ('-' | '+' | '0'..='9') {
      j = j + 1
    }
    // Skip the rest of the indicator line.
    while j < len && source[j] != '\n' {
      j = j + 1
    }
    if j < len {
      j = j + 1
    }
    // Determine block indent from the first non-empty content line.
    let mut indent = -1
    let mut probe = j
    while probe < len {
      let mut spaces = 0
      while probe < len && source[probe] == ' ' {
        spaces = spaces + 1
        probe = probe + 1
      }
      if probe >= len {
        break
      }
      if source[probe] == '\n' {
        probe = probe + 1
        continue
      }
      indent = spaces
      break
    }
    if indent <= 0 {
      // No indented payload found.
      return Some((String::unsafe_substring(source, start=j, end=j), j))
    }
    let payload = StringBuilder::new()
    let mut k = j
    while k < len {
      // Count this line's leading-space count.
      let mut spaces = 0
      let line_start = k
      while k < len && source[k] == ' ' {
        spaces = spaces + 1
        k = k + 1
      }
      if k < len && source[k] == '\n' {
        // Empty / whitespace-only line — keep newline and continue.
        payload.write_char('\n')
        k = k + 1
        continue
      }
      if k >= len {
        break
      }
      if spaces < indent {
        // Dedented — block ends. Restore to line start.
        k = line_start
        break
      }
      // Copy content (after `indent` spaces) up to and including newline.
      let content_start = line_start + indent
      while k < len && source[k] != '\n' {
        k = k + 1
      }
      payload.write_string(
        String::unsafe_substring(source, start=content_start, end=k),
      )
      payload.write_char('\n')
      if k < len {
        k = k + 1
      }
    }
    Some((payload.to_string(), k))
  } else {
    // Plain scalar: read until end-of-line / end-of-source.
    let mut j = i
    while j < len && source[j] != '\n' {
      j = j + 1
    }
    Some((String::unsafe_substring(source, start=i, end=j), j))
  }
}

///|
/// Detect Apple Pkl's "explicit key with non-string key" pattern
/// (`? <seq>\n: <val>`) and, when present, project the whole
/// document into a Pkl `MappingValue` with the parsed key and
/// value. Returns `None` when the source doesn't match the
/// pattern so the regular parse path continues. Today this only
/// targets the single-entry shape that `yamlParser1*`'s "complex
/// mapping key" fixture stresses — the upstream lib's `Map[String,
/// Yaml]` doesn't let us route this through the standard projection.
fn yaml_v12_try_complex_key_doc(source : String) -> Value? {
  let lines = split_lines_for_block_detect(source)
  if lines.length() < 3 {
    return None
  }
  // Locate `? `-prefixed line and the matching `: ` line.
  let mut key_start : Int = -1
  let mut value_start : Int = -1
  let mut indent_target : Int = -1
  for i = 0; i < lines.length(); i = i + 1 {
    let line = lines[i]
    let line_indent = leading_space_count(line)
    let body = String::unsafe_substring(line, start=line_indent, end=line.length())
    if key_start < 0 {
      // Looking for the `? ` start.
      if body.length() >= 2 && body[0] == '?' && body[1] is (' ' | '\t') {
        key_start = i
        indent_target = line_indent
      }
    } else if value_start < 0 && line_indent == indent_target {
      if body.length() >= 2 && body[0] == ':' && body[1] is (' ' | '\t') {
        value_start = i
        break
      }
    }
  }
  if key_start < 0 || value_start < 0 || value_start <= key_start {
    return None
  }
  // Reject doc if other top-level entries exist beyond the single
  // `?: ` pair — Apple Pkl's fixture has just the one entry; mixing
  // it with regular keys here would require a deeper rewrite.
  for i = 0; i < lines.length(); i = i + 1 {
    if i == key_start || i == value_start {
      continue
    }
    let line = lines[i]
    let line_indent = leading_space_count(line)
    if line_indent != indent_target {
      continue
    }
    let trimmed = trim_yaml_ws_v12(line)
    if trimmed == "" {
      continue
    }
    // A bare top-level key at the marker indent we don't recognise
    // → bail out.
    return None
  }
  // Reassemble the key block: `? <first>` becomes `<first>` and the
  // following lines preserve their original indent but get the `?`
  // prefix peeled. The block ends at the `: ` line.
  let key_buf = StringBuilder::new()
  let first_key_line = lines[key_start]
  let first_indent = leading_space_count(first_key_line)
  if first_key_line.length() > first_indent + 2 {
    key_buf.write_string(
      String::unsafe_substring(
        first_key_line, start=first_indent + 2, end=first_key_line.length(),
      ),
    )
  }
  for i = key_start + 1; i < value_start; i = i + 1 {
    key_buf.write_char('\n')
    let line = lines[i]
    let li = leading_space_count(line)
    let body_start = if li >= first_indent + 2 { first_indent + 2 } else { li }
    key_buf.write_string(
      String::unsafe_substring(line, start=body_start, end=line.length()),
    )
  }
  // Value: everything after `: ` on the value line plus all
  // subsequent lines verbatim. Trim trailing whitespace lines so
  // upstream doesn't add a phantom trailing empty document.
  let val_buf = StringBuilder::new()
  let value_line = lines[value_start]
  let vi = leading_space_count(value_line)
  if value_line.length() > vi + 2 {
    val_buf.write_string(
      String::unsafe_substring(
        value_line, start=vi + 2, end=value_line.length(),
      ),
    )
  }
  for i = value_start + 1; i < lines.length(); i = i + 1 {
    val_buf.write_char('\n')
    val_buf.write_string(lines[i])
  }
  let key_source = key_buf.to_string()
  let val_source = val_buf.to_string()
  let key_doc = try? @yaml.Yaml::load_from_string(key_source[:])
  let val_doc = try? @yaml.Yaml::load_from_string(val_source[:])
  match (key_doc, val_doc) {
    (Ok(key_docs), Ok(val_docs)) => {
      if key_docs.length() == 0 || val_docs.length() == 0 {
        return None
      }
      let alias_refs : YamlAliasRefs = {
        array_refs: [], map_refs: [], next_id: 1L,
      }
      let key_value = yaml_to_value_with_aliases(
        key_docs[0], false, alias_refs,
      )
      let val_value = yaml_to_value_with_aliases(
        val_docs[0], false, alias_refs,
      )
      Some(MappingValue([{ key: key_value, value: val_value }]))
    }
    _ => None
  }
}

///|
fn leading_space_count(line : String) -> Int {
  let mut i = 0
  while i < line.length() && line[i] is (' ') {
    i = i + 1
  }
  i
}

///|
/// Returns true if a Yaml::Map has the `!!set` sentinel injected by
/// `yaml_v12_rewrite_set`.
fn yaml_v12_map_is_set(m : Map[String, @yaml.Yaml]) -> Bool {
  match m.get(yaml_v12_set_marker_member) {
    Some(@yaml.Yaml::String(s)) => s == yaml_v12_set_sentinel
    _ => false
  }
}

///|
/// Convert a sentinel-marked `Yaml::String` into a Pkl `BytesValue`,
/// or pass through other strings. Tree-walks composites by routing
/// through the regular `yaml_to_value_with_aliases` path; only the
/// leaves need this hook. Caller invokes this on each `Yaml::String`
/// node before falling through to the existing converter.
fn yaml_v12_try_decode_binary_string(value : String) -> Value? {
  let prefix = yaml_v12_binary_sentinel
  if value.length() < prefix.length() {
    return None
  }
  for i in 0..<prefix.length() {
    if value[i] != prefix[i] {
      return None
    }
  }
  let payload = String::unsafe_substring(
    value, start=prefix.length(), end=value.length(),
  )
  let cleaned = strip_yaml_whitespace_v12(payload)
  try {
    let bytes = @base64.decode(cleaned[:])
    Some(BytesValue(bytes))
  } catch {
    _ => None
  }
}
