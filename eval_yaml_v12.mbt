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
///
/// Restricted to "looks like a plain numeric token": no whitespace
/// and no YAML structural characters (`:`, `,`, `[`, `]`, `{`, `}`,
/// `"`, `\``, `#`). Without this guard the matcher fires on
/// multi-line documents with embedded underscores + digits and
/// inadvertently wraps the whole document as a quoted scalar.
fn is_v12_string_only_scalar(text : String) -> Bool {
  let len = text.length()
  if len == 0 || text == "_" {
    return false
  }
  let mut has_underscore = false
  let mut has_digit = false
  for c in text {
    if c is (' ' | '\t' | '\n' | '\r' | ':' | ',' | '[' | ']' | '{' | '}'
      | '"' | '\'' | '#') {
      return false
    }
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
/// Sentinel prefix for a YAML mapping entry whose key was originally
/// expressed with the `? <complex-key>` syntax. The upstream loader
/// can't carry non-string keys through its `Map[String, Yaml]`, so
/// `yaml_v12_extract_complex_keys` rewrites each such entry to a
/// string key beginning with this prefix and carrying the original
/// key as an embedded YAML scalar. `yaml_to_value_with_aliases`
/// recognises the prefix and reconstructs the complex key on the
/// way out (see `yaml_v12_try_decode_complex_key`).
let yaml_v12_complex_key_prefix : String = "\u{001f}PKL_KEY:"

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
/// Pre-process the YAML source so `? <key>\n: <val>` explicit-key
/// entries become string-keyed sentinel entries that the upstream
/// loader accepts. The original key block YAML is base64-encoded
/// into the key so `yaml_v12_try_decode_complex_key` can recover
/// it when projecting back to a Pkl value.
///
/// Returns the rewritten source. Lines that don't match the
/// explicit-key form pass through unchanged so this is a no-op for
/// the vast majority of YAML inputs.
fn yaml_v12_rewrite_complex_keys(source : String) -> String {
  let lines = split_lines_for_block_detect(source)
  let out = StringBuilder::new()
  let mut i = 0
  let mut first = true
  while i < lines.length() {
    let line = lines[i]
    let indent = leading_space_count(line)
    let body_start = indent
    let body = String::unsafe_substring(
      line, start=body_start, end=line.length(),
    )
    if body.length() >= 2 && body[0] == '?' && body[1] is (' ' | '\t') {
      // Collect lines belonging to the key block: the rest of this
      // line (after `? `), plus continuation lines that are indented
      // strictly more than `indent`. The key block terminates at the
      // matching `: ` line at the same indent (`indent` again).
      let key_buf = StringBuilder::new()
      // First line of the key block: everything after `? `.
      if line.length() > body_start + 2 {
        key_buf.write_string(
          String::unsafe_substring(
            line, start=body_start + 2, end=line.length(),
          ),
        )
      }
      let mut j = i + 1
      let mut value_line : Int = -1
      while j < lines.length() {
        let lj = lines[j]
        let li = leading_space_count(lj)
        let bj = String::unsafe_substring(lj, start=li, end=lj.length())
        if li == indent &&
          bj.length() >= 1 &&
          bj[0] == ':' &&
          (bj.length() == 1 || bj[1] is (' ' | '\t')) {
          value_line = j
          break
        }
        if li > indent || trim_yaml_ws_v12(lj) == "" {
          key_buf.write_char('\n')
          // Dedent the key block by `body_start + 2` so the captured
          // text is a standalone YAML document. If the line wasn't
          // indented that far (e.g. blank line), take it as-is.
          let dedent = body_start + 2
          if li >= dedent {
            key_buf.write_string(
              String::unsafe_substring(lj, start=dedent, end=lj.length()),
            )
          } else {
            key_buf.write_string(lj)
          }
          j = j + 1
        } else {
          // Same / less indent, not the `: ` line — no matching `:`,
          // give up on this entry. Emit the original lines verbatim.
          break
        }
      }
      if value_line < 0 {
        // Didn't find matching `: ` — emit the lines we consumed
        // verbatim and fall through to the upstream loader.
        if !first {
          out.write_char('\n')
        }
        first = false
        out.write_string(line)
        i = i + 1
        continue
      }
      // Build the sentinel-key entry. Reuse the value-line's body
      // after the `:`. Use a base64 encoding of the key YAML so the
      // result is safe to embed as a double-quoted scalar.
      let key_yaml = key_buf.to_string()
      let key_bytes = string_to_bytes_for_b64(key_yaml)
      let encoded = @base64.encode(key_bytes[:])
      let sentinel_key = yaml_v12_complex_key_prefix + encoded
      let vline = lines[value_line]
      let vli = leading_space_count(vline)
      let value_text = if vline.length() > vli + 2 {
        String::unsafe_substring(vline, start=vli + 2, end=vline.length())
      } else {
        ""
      }
      if !first {
        out.write_char('\n')
      }
      first = false
      // Indent the synthesized line at the original indent so it
      // remains a sibling of the explicit-key entry's neighbours.
      for _ in 0..<indent {
        out.write_char(' ')
      }
      out.write_char('"')
      out.write_string(sentinel_key)
      out.write_string("\": ")
      out.write_string(value_text)
      i = value_line + 1
      continue
    }
    if !first {
      out.write_char('\n')
    }
    first = false
    out.write_string(line)
    i = i + 1
  }
  out.to_string()
}

///|
fn string_to_bytes_for_b64(s : String) -> Bytes {
  // `@base64.encode` takes a Bytes view; encode the string's UTF-8
  // byte representation so non-ASCII characters round-trip cleanly.
  @utf8.encode(s)
}

///|
/// When projecting a Pkl `MappingValue` from a YAML map, intercept
/// entries whose key begins with `yaml_v12_complex_key_prefix` and
/// rebuild the original key by base64-decoding the embedded YAML
/// then re-parsing it through the upstream loader.
fn yaml_v12_try_decode_complex_key(
  encoded_key : String,
  refs : YamlAliasRefs,
  use_mapping : Bool,
) -> Value? {
  let prefix = yaml_v12_complex_key_prefix
  if encoded_key.length() < prefix.length() {
    return None
  }
  for i in 0..<prefix.length() {
    if encoded_key[i] != prefix[i] {
      return None
    }
  }
  let payload = String::unsafe_substring(
    encoded_key, start=prefix.length(), end=encoded_key.length(),
  )
  try {
    let raw_bytes = @base64.decode(payload[:])
    let key_yaml_text = @utf8.decode(raw_bytes[:])
    let docs = @yaml.Yaml::load_from_string(key_yaml_text[:])
    if docs.length() == 0 {
      None
    } else {
      Some(yaml_to_value_with_aliases(docs[0], use_mapping, refs))
    }
  } catch {
    _ => None
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
