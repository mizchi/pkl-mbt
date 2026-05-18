///|
pub fn render_value_as_yaml(value : Value) -> String {
  let buf = StringBuilder::new()
  render_yaml_root(value, buf)
  buf.to_string()
}

///|
fn render_yaml_root(value : Value, buf : StringBuilder) -> Unit {
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_members(visible, 0, buf)
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_entries(entries, 0, buf)
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string("[]\n")
      } else {
        render_yaml_sequence(elements, 0, buf)
      }
    _ => {
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_mapping_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  for i = 0; i < visible.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(visible[i].name, buf)
    buf.write_char(':')
    render_yaml_block_value(visible[i].value, indent, buf)
  }
}

///|
fn render_yaml_mapping_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < entries.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(yaml_coerce_key(entries[i].key), buf)
    buf.write_char(':')
    render_yaml_block_value(entries[i].value, indent, buf)
  }
}

///|
fn render_yaml_block_value(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_members(visible, indent + 2, buf)
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(entries, indent + 2, buf)
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    // PKL-119a: Pair flows through the same block-sequence path as
    // a 2-element Listing so YAML emits it as the canonical
    // `- first\n- second` form rather than the PCF inline fallback.
    PairValue(first, second) => {
      buf.write_char('\n')
      render_yaml_sequence([first, second], indent, buf)
    }
    // PKL-119b: IntSeq materializes and reuses the sequence path so
    // the YAML output matches what a hand-written `new Listing { ... }`
    // of the same elements would render to.
    IntSeqValue(start, end_v, step) => {
      let elements = intseq_materialize(start, end_v, step)
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    }
    // PKL-119c: Set reuses the sequence path; uniqueness is upstream
    // semantics, not a YAML output concern.
    SetValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    // PKL-119d: Map reuses the mapping-entries path so the YAML
    // output shape matches a hand-written `new Mapping { ... }` of
    // the same entries.
    MapValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(entries, indent + 2, buf)
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(indicator, lines, trailing, indent + 2, buf)
        None => {
          buf.write_char(' ')
          render_yaml_scalar(value, buf)
          buf.write_char('\n')
        }
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_sequence(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < elements.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    buf.write_char('-')
    render_yaml_seq_item(elements[i], indent + 2, buf)
  }
}

///|
fn render_yaml_seq_item(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  // The first sub-member or sub-element shares the `- ` line; the rest are
  // continued at `indent` (two spaces past the `- `).
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(visible[0].name, buf)
        buf.write_char(':')
        render_yaml_block_value(visible[0].value, indent, buf)
        for i = 1; i < visible.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(visible[i].name, buf)
          buf.write_char(':')
          render_yaml_block_value(visible[i].value, indent, buf)
        }
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(yaml_coerce_key(entries[0].key), buf)
        buf.write_char(':')
        render_yaml_block_value(entries[0].value, indent, buf)
        for i = 1; i < entries.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(yaml_coerce_key(entries[i].key), buf)
          buf.write_char(':')
          render_yaml_block_value(entries[i].value, indent, buf)
        }
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char(' ')
        buf.write_char('-')
        render_yaml_seq_item(elements[0], indent + 2, buf)
        for i = 1; i < elements.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          buf.write_char('-')
          render_yaml_seq_item(elements[i], indent + 2, buf)
        }
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(indicator, lines, trailing, indent, buf)
        None => {
          buf.write_char(' ')
          render_yaml_scalar(value, buf)
          buf.write_char('\n')
        }
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
/// PKL-125: decide whether `s` qualifies for a YAML literal block
/// scalar (`|`, `|-`, `|+`). A string is eligible when:
///   - it has at least one internal newline (`\n` somewhere before
///     the trailing-newline run), so the block form actually
///     improves readability over a double-quoted single-line escape;
///   - it carries no control characters other than `\n` and `\t`,
///     which would otherwise need `\uXXXX` escapes that the block
///     form cannot express;
///   - no content line starts with whitespace, which would otherwise
///     require an explicit indentation indicator like `|2`.
///
/// The chomping indicator follows the trailing-newline count:
///   - exactly 1 trailing `\n`  → `|`  (clip — single final newline)
///   - 0 trailing `\n`          → `|-` (strip — no final newline)
///   - 2+ trailing `\n`         → `|+` (keep — preserve all)
///
/// Returns `Some((indicator, content_lines, trailing))` on
/// eligibility, where `content_lines` are the lines stripped of
/// every trailing newline and `trailing` is the original trailing
/// newline count (the `|+` path needs it to emit the extra blank
/// lines that preserve the run).
fn yaml_string_block_scalar_info(s : String) -> (String, Array[String], Int)? {
  if s.length() == 0 {
    return None
  }
  // Count trailing `\n` characters.
  let mut trailing = 0
  while trailing < s.length() && s[s.length() - 1 - trailing].to_int() == 0x0A {
    trailing = trailing + 1
  }
  let core_len = s.length() - trailing
  let core = String::unsafe_substring(s, start=0, end=core_len)
  // Need at least one internal newline to beat the inline double-quote form.
  let mut has_internal_newline = false
  for c in core {
    if c == '\n' {
      has_internal_newline = true
      break
    }
  }
  if !has_internal_newline {
    return None
  }
  // Reject anything with control chars other than `\n` / `\t`.
  for c in core {
    if c < ' ' && c != '\n' && c != '\t' {
      return None
    }
    if c == '\u{7F}' {
      return None
    }
  }
  // Split into lines and reject any line whose first char is whitespace.
  let lines : Array[String] = []
  for piece in core.split("\n") {
    lines.push(piece.to_owned())
  }
  for line in lines {
    if line.length() == 0 {
      continue
    }
    let first = line[0].to_int().unsafe_to_char()
    if first == ' ' || first == '\t' {
      return None
    }
  }
  let indicator = if trailing == 1 {
    "|"
  } else if trailing == 0 {
    "|-"
  } else {
    "|+"
  }
  Some((indicator, lines, trailing))
}

///|
/// PKL-125: emit a literal block scalar. The leading space and
/// indicator share the same line as the preceding `key:` / `-`;
/// each content line follows at `content_indent` spaces. Blank
/// content lines emit as a bare `\n` (YAML literal block scalars
/// allow empty lines to be undented). For the keep chomping (`|+`)
/// the source had ≥2 trailing newlines; the natural line break
/// after the last content line covers one of them, so `(trailing -
/// 1)` extra bare newlines preserve the rest.
fn render_yaml_block_scalar(
  indicator : String,
  lines : Array[String],
  trailing : Int,
  content_indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_char(' ')
  buf.write_string(indicator)
  buf.write_char('\n')
  for line in lines {
    if line.length() == 0 {
      buf.write_char('\n')
    } else {
      write_yaml_indent(buf, content_indent)
      buf.write_string(line)
      buf.write_char('\n')
    }
  }
  if indicator == "|+" {
    let mut extras = trailing - 1
    while extras > 0 {
      buf.write_char('\n')
      extras = extras - 1
    }
  }
}

///|
fn render_yaml_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_yaml_string(s, buf)
    DurationValue(n, unit) => render_yaml_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_yaml_string("\{n}.\{unit}", buf)
    RegexValue(pattern) => render_yaml_string(pattern, buf)
    BytesValue(bytes) => render_yaml_string(@base64.encode(bytes[:]), buf)
    _ =>
      // Composite values reach this path only via the same renderer fallback
      // that PCF / JSON use, so produce a deterministic flow form rather than
      // panic. Anything richer is handled by the block-mode entry points.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_yaml_key(name : String, buf : StringBuilder) -> Unit {
  // Keys reuse the scalar-string quoting policy.
  render_yaml_string(name, buf)
}

///|
fn render_yaml_string(s : String, buf : StringBuilder) -> Unit {
  if s == "" {
    buf.write_string("''")
    return
  }
  if yaml_string_needs_double_quote(s) {
    render_yaml_double_quoted(s, buf)
    return
  }
  if yaml_string_needs_single_quote(s) {
    render_yaml_single_quoted(s, buf)
    return
  }
  buf.write_string(s)
}

///|
fn yaml_string_needs_double_quote(s : String) -> Bool {
  for c in s {
    if c < ' ' || c == '\u{7F}' || c == '\\' {
      return true
    }
  }
  false
}

///|
fn yaml_string_needs_single_quote(s : String) -> Bool {
  // Reserved YAML 1.1 plain-scalar keywords.
  if yaml_is_reserved_keyword(s) {
    return true
  }
  if yaml_looks_like_number(s) {
    return true
  }
  let mut first : Char = ' '
  let mut has_char = false
  for c in s {
    first = c
    has_char = true
    break
  }
  if !has_char {
    return false
  }
  if first == ' ' || first == '\t' {
    return true
  }
  // Leading indicator characters that would otherwise alter parsing.
  match first {
    '-'
    | '?'
    | ':'
    | ','
    | '['
    | ']'
    | '{'
    | '}'
    | '#'
    | '&'
    | '*'
    | '!'
    | '|'
    | '>'
    | '\''
    | '"'
    | '%'
    | '@'
    | '`' => return true
    _ => ()
  }
  // Trailing whitespace.
  let mut last : Char = first
  for c in s {
    last = c
  }
  if last == ' ' || last == '\t' {
    return true
  }
  // Embedded `: ` or ` #` flips a plain scalar into something the YAML parser
  // would re-interpret, so reach for single quotes.
  if yaml_contains_pair(s, ':', ' ') || yaml_contains_pair(s, ' ', '#') {
    return true
  }
  false
}

///|
fn yaml_is_reserved_keyword(s : String) -> Bool {
  match s {
    "true"
    | "True"
    | "TRUE"
    | "false"
    | "False"
    | "FALSE"
    | "null"
    | "Null"
    | "NULL"
    | "~"
    | "yes"
    | "Yes"
    | "YES"
    | "no"
    | "No"
    | "NO"
    | "on"
    | "On"
    | "ON"
    | "off"
    | "Off"
    | "OFF" => true
    _ => false
  }
}

///|
fn yaml_looks_like_number(s : String) -> Bool {
  // Recognize the common `[+-]?digits(.digits)?(e[+-]?digits)?` shape that
  // YAML would otherwise parse as a number.
  let mut idx = 0
  let mut saw_digit = false
  let mut saw_dot = false
  let mut saw_exp = false
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return false
  }
  if chars[idx] == '+' || chars[idx] == '-' {
    idx = idx + 1
  }
  while idx < chars.length() {
    let c = chars[idx]
    if c >= '0' && c <= '9' {
      saw_digit = true
      idx = idx + 1
    } else if c == '.' && !saw_dot && !saw_exp {
      saw_dot = true
      idx = idx + 1
    } else if (c == 'e' || c == 'E') && !saw_exp && saw_digit {
      saw_exp = true
      idx = idx + 1
      if idx < chars.length() && (chars[idx] == '+' || chars[idx] == '-') {
        idx = idx + 1
      }
    } else {
      return false
    }
  }
  saw_digit
}

///|
fn yaml_contains_pair(s : String, a : Char, b : Char) -> Bool {
  let mut prev : Char = '\u{0}'
  let mut have_prev = false
  for c in s {
    if have_prev && prev == a && c == b {
      return true
    }
    prev = c
    have_prev = true
  }
  false
}

///|
fn render_yaml_single_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('\'')
  for c in s {
    if c == '\'' {
      buf.write_string("''")
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char('\'')
}

///|
fn render_yaml_double_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' || c == '\u{7F}' {
          let code = c.to_int()
          let hex = json_hex4(code)
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn yaml_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn write_yaml_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
/// PKL-126a: Render a Value as an Apple plist XML document, matching
/// the upstream `PListRenderer` output. The output starts with the
/// XML 1.0 prolog and the Apple PLIST 1.0 DOCTYPE, then wraps the
/// rendered value in a `<plist version="1.0">` element.
///
/// Value mapping:
///   - Int    → `<integer>N</integer>`
///   - Float  → `<real>D</real>`
///   - Bool   → `<true/>` / `<false/>`
///   - String → `<string>...</string>` (XML-escaped)
///   - Null   → skipped inside `<dict>` (Apple `omitNullProperties`
///              behaviour); inside `<array>` it would error upstream,
///              but PKL-126a's slice elides it silently — the
///              error-on-null-in-array surface lands with PKL-127 so
///              the diagnostic flows through the same converter path
///              as the rest of the renderer-side errors.
///   - Object / Mapping → `<dict>` with `<key>` + value pairs.
///   - Listing → `<array>` of values.
///   - Duration / DataSize → `<string>N unit</string>` (space-separated
///              numeric + unit, matching Apple PListRenderer rather
///              than the `.` form JSON / YAML use for these values).
///   - Regex  → `<string>pattern</string>`.
///   - Bytes  → `<string>base64</string>`.
///
/// Indentation defaults to two spaces; the eventual converter-aware
/// path (PKL-127) will honor the `indent` property when it threads
/// renderer config through to this entry point.
