///|
/// PKL-153e: yaml.Renderer's `mode = "1.2"` toggle. The renderer
/// quoting decision walks string scalars and asks "could this round-
/// trip as a non-string?". In compat mode the answer is yes for the
/// full set of 1.1 + 1.2 patterns (`y`, `yes`, `0b1001`, `1_2_3`,
/// base-60, etc.); in 1.2 mode it's narrowed to just what 1.2's
/// core schema produces (`true/null/0o/0x/decimals/floats`). The
/// renderer entry points stash the mode in `yaml_render_mode_ref`
/// for `render_yaml_string` to consult — saves threading the
/// parameter through every helper in the chain.
let yaml_render_mode_ref : Ref[String] = { val: "compat" }

///|
fn yaml_render_mode_current() -> String {
  yaml_render_mode_ref.val
}

///|
pub fn render_value_as_yaml(value : Value) -> String {
  render_value_as_yaml_with_options(value, 2, false)
}

///|
/// Mode-aware entry point used by the runtime renderer dispatch.
/// External callers should prefer this when the YamlRenderer's
/// `mode` slot matters; `render_value_as_yaml_with_options` keeps
/// the historical default-"compat" behaviour intact.
pub fn render_value_as_yaml_with_mode(
  value : Value,
  indent_width : Int,
  is_stream : Bool,
  mode : String,
) -> String {
  let prev = yaml_render_mode_ref.val
  yaml_render_mode_ref.val = mode
  let result = render_value_as_yaml_with_options(value, indent_width, is_stream)
  yaml_render_mode_ref.val = prev
  result
}

///|
pub fn render_value_as_yaml_fragment_with_mode(
  value : Value,
  indent_width : Int,
  is_stream : Bool,
  mode : String,
) -> String {
  let prev = yaml_render_mode_ref.val
  yaml_render_mode_ref.val = mode
  let result = render_value_as_yaml_fragment_with_options(
    value, indent_width, is_stream,
  )
  yaml_render_mode_ref.val = prev
  result
}

///|
pub fn render_value_as_yaml_with_indent_width(
  value : Value,
  indent_width : Int,
) -> String {
  render_value_as_yaml_with_options(value, indent_width, false)
}

///|
pub fn render_value_as_yaml_stream(value : Value, indent_width : Int) -> String {
  render_value_as_yaml_with_options(value, indent_width, true)
}

///|
pub fn render_value_as_yaml_with_options(
  value : Value,
  indent_width : Int,
  is_stream : Bool,
) -> String {
  let buf = StringBuilder::new()
  let step = yaml_normalize_indent_width(indent_width)
  if is_stream {
    render_yaml_stream_root(value, step, buf)
  } else {
    render_yaml_root(value, step, buf)
  }
  buf.to_string()
}

///|
pub fn render_value_as_yaml_fragment(value : Value) -> String {
  render_value_as_yaml_fragment_with_options(value, 2, false)
}

///|
pub fn render_value_as_yaml_fragment_with_options(
  value : Value,
  indent_width : Int,
  is_stream : Bool,
) -> String {
  let text = render_value_as_yaml_with_options(value, indent_width, is_stream)
  if text.has_suffix("\n") {
    String::unsafe_substring(text, start=0, end=text.length() - 1)
  } else {
    text
  }
}

///|
fn yaml_normalize_indent_width(indent_width : Int) -> Int {
  if indent_width < 1 {
    1
  } else {
    indent_width
  }
}

///|
fn render_yaml_stream_root(
  value : Value,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          match elements[i] {
            ObjectValue(_)
            | MappingValue(_)
            | DefaultedMappingValue(_, _, _)
            | MapValue(_)
            | ListingValue(_)
            | DefaultedListingValue(_, _, _)
            | ListValue(_)
            | SetValue(_) => buf.write_string("---\n")
            _ => buf.write_string("--- ")
          }
        }
        if i > 0 {
          match elements[i] {
            ObjectValue(_)
            | MappingValue(_)
            | DefaultedMappingValue(_, _, _)
            | MapValue(_)
            | ListingValue(_)
            | DefaultedListingValue(_, _, _)
            | ListValue(_)
            | SetValue(_) => render_yaml_root(elements[i], indent_width, buf)
            _ => {
              render_yaml_scalar(elements[i], buf)
              buf.write_char('\n')
            }
          }
        } else {
          render_yaml_root(elements[i], indent_width, buf)
        }
      }
    _ => render_yaml_root(value, indent_width, buf)
  }
}

///|
fn render_yaml_root(
  value : Value,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      buf.write_char('\n')
      return
    }
    None => ()
  }
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        render_yaml_mapping_members(visible, 0, indent_width, buf)
      }
    }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        render_yaml_mapping_entries(entries, 0, indent_width, buf)
      }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        render_yaml_sequence(elements, 0, indent_width, buf)
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
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  for i = 0; i < visible.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_member_key(visible[i].name, visible[i].value, buf)
    buf.write_char(':')
    render_yaml_block_value(visible[i].value, indent, indent_width, buf)
  }
}

///|
fn render_yaml_mapping_entries(
  entries : Array[ValueEntry],
  indent : Int,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < entries.length(); i = i + 1 {
    render_yaml_mapping_entry(entries[i], indent, indent_width, buf)
  }
}

///|
fn render_yaml_mapping_entry(
  entry : ValueEntry,
  indent : Int,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  match entry.key {
    StringValue(s) if yaml_string_key_needs_explicit(s) => {
      write_yaml_indent(buf, indent)
      buf.write_char('?')
      match yaml_string_block_scalar_info(s, indent_width) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(
            indicator,
            lines,
            trailing,
            indent + indent_width,
            buf,
          )
        None => {
          buf.write_char(' ')
          render_yaml_key_string(s, false, buf)
          buf.write_char('\n')
        }
      }
      write_yaml_indent(buf, indent)
      buf.write_char(':')
      render_yaml_block_value(entry.value, indent, indent_width, buf)
    }
    _ => {
      write_yaml_indent(buf, indent)
      render_yaml_entry_key(entry.key, buf)
      buf.write_char(':')
      render_yaml_block_value(entry.value, indent, indent_width, buf)
    }
  }
}

///|
fn render_yaml_block_value(
  value : Value,
  indent : Int,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      buf.write_char('\n')
      return
    }
    None => ()
  }
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_members(
          visible,
          indent + indent_width,
          indent_width,
          buf,
        )
      }
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(
          entries,
          indent + indent_width,
          indent_width,
          buf,
        )
      }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, indent_width, buf)
      }
    // PKL-119a: Pair flows through the same block-sequence path as
    // a 2-element Listing so YAML emits it as the canonical
    // `- first\n- second` form rather than the PCF inline fallback.
    PairValue(first, second) => {
      buf.write_char('\n')
      render_yaml_sequence([first, second], indent, indent_width, buf)
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
        render_yaml_sequence(elements, indent, indent_width, buf)
      }
    }
    // PKL-119c: Set reuses the sequence path; uniqueness is upstream
    // semantics, not a YAML output concern.
    SetValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, indent_width, buf)
      }
    // PKL-119d: Map reuses the mapping-entries path so the YAML
    // output shape matches a hand-written `new Mapping { ... }` of
    // the same entries.
    MapValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(
          entries,
          indent + indent_width,
          indent_width,
          buf,
        )
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s, indent_width) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(
            indicator,
            lines,
            trailing,
            indent + indent_width,
            buf,
          )
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
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < elements.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    buf.write_char('-')
    render_yaml_seq_item(elements[i], indent + indent_width, indent_width, buf)
  }
}

///|
fn render_yaml_seq_item(
  value : Value,
  indent : Int,
  indent_width : Int,
  buf : StringBuilder,
) -> Unit {
  // The first sub-member or sub-element shares the `- ` line; the rest are
  // continued at `indent` (two spaces past the `- `).
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      buf.write_char('\n')
      return
    }
    None => ()
  }
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        write_yaml_inline_padding(buf, indent_width)
        render_yaml_member_key(visible[0].name, visible[0].value, buf)
        buf.write_char(':')
        render_yaml_block_value(visible[0].value, indent, indent_width, buf)
        for i = 1; i < visible.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_member_key(visible[i].name, visible[i].value, buf)
          buf.write_char(':')
          render_yaml_block_value(visible[i].value, indent, indent_width, buf)
        }
      }
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        write_yaml_inline_padding(buf, indent_width)
        render_yaml_entry_key(entries[0].key, buf)
        buf.write_char(':')
        render_yaml_block_value(entries[0].value, indent, indent_width, buf)
        for i = 1; i < entries.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_entry_key(entries[i].key, buf)
          buf.write_char(':')
          render_yaml_block_value(entries[i].value, indent, indent_width, buf)
        }
      }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        write_yaml_inline_padding(buf, indent_width)
        buf.write_char('-')
        render_yaml_seq_item(
          elements[0],
          indent + indent_width,
          indent_width,
          buf,
        )
        for i = 1; i < elements.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          buf.write_char('-')
          render_yaml_seq_item(
            elements[i],
            indent + indent_width,
            indent_width,
            buf,
          )
        }
      }
    SetValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        write_yaml_inline_padding(buf, indent_width)
        buf.write_char('-')
        render_yaml_seq_item(
          elements[0],
          indent + indent_width,
          indent_width,
          buf,
        )
        for i = 1; i < elements.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          buf.write_char('-')
          render_yaml_seq_item(
            elements[i],
            indent + indent_width,
            indent_width,
            buf,
          )
        }
      }
    MapValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        write_yaml_inline_padding(buf, indent_width)
        render_yaml_entry_key(entries[0].key, buf)
        buf.write_char(':')
        render_yaml_block_value(entries[0].value, indent, indent_width, buf)
        for i = 1; i < entries.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_entry_key(entries[i].key, buf)
          buf.write_char(':')
          render_yaml_block_value(entries[i].value, indent, indent_width, buf)
        }
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s, indent_width) {
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
///   - it has either an internal newline or trailing newlines, so the
///     block form preserves line structure without double-quoted
///     escapes;
///   - it carries no control characters other than `\n`,
///     which would otherwise need `\uXXXX` escapes that the block
///     form cannot express;
///   - the first content line gets an explicit indentation indicator
///     (`|2`, `|4`, ...) when it starts with whitespace.
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
fn yaml_string_block_scalar_info(
  s : String,
  indent_width : Int,
) -> (String, Array[String], Int)? {
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
  // Need at least one line break to beat the inline double-quote form.
  let mut has_internal_newline = false
  for c in core {
    if c == '\n' {
      has_internal_newline = true
      break
    }
  }
  if !has_internal_newline && trailing == 0 {
    return None
  }
  // Reject anything with control chars other than `\n`.
  for c in core {
    if c < ' ' && c != '\n' {
      return None
    }
    if c == '\u{7F}' {
      return None
    }
  }
  // Split into lines. When the first content line starts with whitespace,
  // YAML needs an explicit indentation indicator (`|2-`, `|4-`, ...),
  // otherwise the leading spaces would be confused with the scalar's own
  // indentation. Later lines can carry extra indentation without the
  // indicator.
  let lines : Array[String] = []
  for piece in core.split("\n") {
    lines.push(piece.to_owned())
  }
  let mut needs_indent_indicator = false
  if lines.length() > 0 && lines[0].length() > 0 {
    let first = lines[0][0].to_int().unsafe_to_char()
    if first == ' ' || first == '\t' {
      needs_indent_indicator = true
    }
  }
  let indent_indicator = if needs_indent_indicator {
    "\{indent_width}"
  } else {
    ""
  }
  let keep_all_newlines = core_len == 0 && trailing > 0
  let indicator = if keep_all_newlines {
    "|\{indent_indicator}+"
  } else if trailing == 1 {
    "|\{indent_indicator}"
  } else if trailing == 0 {
    "|\{indent_indicator}-"
  } else {
    "|\{indent_indicator}+"
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
  if indicator.has_suffix("+") {
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
    BytesValue(bytes) => {
      buf.write_string("!!binary ")
      let encoded = @base64.encode(bytes[:])
      if encoded.length() == 0 {
        render_yaml_string(encoded, buf)
      } else {
        buf.write_string(encoded)
      }
    }
    _ =>
      // Composite values reach this path only via the same renderer fallback
      // that PCF / JSON use, so produce a deterministic flow form rather than
      // panic. Anything richer is handled by the block-mode entry points.
      render_pcf_inline(value, 0, false, buf)
  }
}

///|
fn render_yaml_member_key(
  name : String,
  value : Value,
  buf : StringBuilder,
) -> Unit {
  render_yaml_key_string(
    yaml_unquote_pkl_identifier_name(name),
    yaml_value_starts_with_percent(value),
    buf,
  )
}

///|
fn render_yaml_key_string(
  s : String,
  force_single_quote : Bool,
  buf : StringBuilder,
) -> Unit {
  if s == "" {
    buf.write_string("''")
    return
  }
  if yaml_string_needs_double_quote(s) {
    render_yaml_double_quoted(s, buf)
    return
  }
  if force_single_quote ||
    yaml_string_needs_single_quote(s) ||
    yaml_key_needs_single_quote(s) {
    render_yaml_single_quoted(s, buf)
    return
  }
  buf.write_string(s)
}

///|
fn render_yaml_entry_key(value : Value, buf : StringBuilder) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  match value {
    StringValue(s) => render_yaml_key_string(s, false, buf)
    IntValue(_) | FloatValue(_) | BoolValue(_) | NullValue =>
      render_yaml_scalar(value, buf)
    _ => render_yaml_key_string(yaml_coerce_key(value), false, buf)
  }
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
fn yaml_unquote_pkl_identifier_name(name : String) -> String {
  if name.length() >= 2 && name.has_prefix("`") && name.has_suffix("`") {
    String::unsafe_substring(name, start=1, end=name.length() - 1)
  } else {
    name
  }
}

///|
fn yaml_value_starts_with_percent(value : Value) -> Bool {
  match value {
    StringValue(s) => {
      for c in s {
        return c == '%'
      }
      false
    }
    _ => false
  }
}

///|
fn yaml_key_needs_single_quote(s : String) -> Bool {
  for c in s {
    match c {
      '[' | ']' | '{' | '}' | ',' => return true
      _ => ()
    }
  }
  false
}

///|
fn yaml_string_key_needs_explicit(s : String) -> Bool {
  if s.length() > 1024 {
    return true
  }
  for c in s {
    if c == '\n' {
      return true
    }
  }
  false
}

///|
fn yaml_string_needs_double_quote(s : String) -> Bool {
  for c in s {
    if c < ' ' ||
      c == '\u{7F}' ||
      c == '\u{85}' ||
      c == '\u{A0}' ||
      c == '\u{2028}' ||
      c == '\u{2029}' ||
      c == '\\' {
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
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return false
  }
  let first = chars[0]
  if first == ' ' || first == '\t' {
    return true
  }
  if first == '-' || first == '?' || first == ':' {
    if chars.length() == 1 || chars[1] == ' ' || chars[1] == '\t' {
      return true
    }
  }
  // Leading indicator characters that would otherwise alter parsing.
  match first {
    ','
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
  if last == ' ' || last == '\t' || last == ':' {
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
  // 1.2 core schema: only `true|false|null` (and `~` for null) are
  // reserved scalars. 1.1 / compat additionally treat the y/yes/on
  // boolean aliases as reserved.
  let mode = yaml_render_mode_current()
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
    | "~" => true
    _ =>
      if mode == "1.2" {
        false
      } else {
        match s {
          "yes"
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
          | "OFF"
          | "y"
          | "Y"
          | "n"
          | "N" => true
          _ => false
        }
      }
  }
}

///|
fn yaml_looks_like_number(s : String) -> Bool {
  let mode = yaml_render_mode_current()
  if yaml_looks_like_number_v12(s) {
    return true
  }
  if mode == "1.2" {
    return yaml_looks_like_special_float_v12(s)
  }
  // compat / 1.1 mode: also catch 1.1-only numeric forms so the
  // renderer quotes them and a downstream parser doesn't
  // re-interpret the string as a number.
  if yaml_looks_like_special_float_v12(s) {
    return true
  }
  yaml_looks_like_v11_only_number(s)
}

///|
/// Matches the YAML 1.2 core-schema integer / float regex grammar.
///   - decimal int: `[-+]?[0-9]+`
///   - octal: `0o[0-7]+` (unsigned only)
///   - hex: `0x[0-9a-fA-F]+` (unsigned only)
///   - float: `[-+]? ( \.[0-9]+ | [0-9]+ (\.[0-9]*)? ) ( [eE] [-+]? [0-9]+ )?`
fn yaml_looks_like_number_v12(s : String) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  if len >= 2 && s[0] == '0' && (s[1] == 'o' || s[1] == 'O') {
    if len == 2 {
      return false
    }
    for i in 2..<len {
      if !(s[i] is '0'..='7') {
        return false
      }
    }
    return true
  }
  if len >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
    if len == 2 {
      return false
    }
    for i in 2..<len {
      let c = s[i]
      if !(c is '0'..='9' || c is 'a'..='f' || c is 'A'..='F') {
        return false
      }
    }
    return true
  }
  let mut idx = 0
  if s[idx] == '+' || s[idx] == '-' {
    idx = idx + 1
  }
  let int_start = idx
  while idx < len && s[idx] is '0'..='9' {
    idx = idx + 1
  }
  let int_len = idx - int_start
  let mut saw_dot = false
  if idx < len && s[idx] == '.' {
    saw_dot = true
    idx = idx + 1
    let frac_start = idx
    while idx < len && s[idx] is '0'..='9' {
      idx = idx + 1
    }
    if int_len == 0 && idx == frac_start {
      return false
    }
  } else if int_len == 0 {
    return false
  }
  let _ = saw_dot
  if idx < len && (s[idx] == 'e' || s[idx] == 'E') {
    idx = idx + 1
    if idx < len && (s[idx] == '+' || s[idx] == '-') {
      idx = idx + 1
    }
    let exp_start = idx
    while idx < len && s[idx] is '0'..='9' {
      idx = idx + 1
    }
    if idx == exp_start {
      return false
    }
  }
  idx == len
}

///|
fn yaml_looks_like_special_float_v12(s : String) -> Bool {
  match s {
    ".inf"
    | ".Inf"
    | ".INF"
    | "+.inf"
    | "+.Inf"
    | "+.INF"
    | "-.inf"
    | "-.Inf"
    | "-.INF"
    | ".nan"
    | ".NaN"
    | ".NAN" => true
    _ => false
  }
}

///|
/// 1.1-only number-looking patterns that compat / 1.1 modes should
/// still quote when they appear as YAML output strings:
///   - binary `[-+]?0b[01]+`
///   - signed octal / hex `[-+](0o[0-7]+|0x[0-9a-fA-F]+)`
///   - base-60 `[-+]?[0-9]+(:[0-5]?[0-9])+(\.[0-9]*)?`
///   - underscore-separated `[0-9]+(_[0-9]+)*` (with optional `.frac`)
///   - bare leading `0` octal `0[0-7]+`
fn yaml_looks_like_v11_only_number(s : String) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  // Underscored numerics.
  let mut has_underscore = false
  let mut has_digit = false
  let mut nonnumeric = false
  for c in s {
    if c == '_' {
      has_underscore = true
    } else if c is '0'..='9' || c == '+' || c == '-' || c == '.' {
      if c is '0'..='9' {
        has_digit = true
      }
    } else {
      nonnumeric = true
    }
  }
  if has_underscore && has_digit && !nonnumeric {
    return true
  }
  // Binary (0b...).
  let mut idx = 0
  if s[0] == '+' || s[0] == '-' {
    idx = 1
  }
  if idx + 1 < len && s[idx] == '0' && (s[idx + 1] == 'b' || s[idx + 1] == 'B') {
    let mut k = idx + 2
    let mut bin_ok = k < len
    while k < len {
      if !(s[k] == '0' || s[k] == '1') {
        bin_ok = false
        break
      }
      k = k + 1
    }
    if bin_ok && k == len {
      return true
    }
  }
  // Signed `0o` / `0x` (1.1 only).
  if (s[0] == '+' || s[0] == '-') &&
    idx + 1 < len &&
    s[idx] == '0' &&
    (s[idx + 1] == 'o' || s[idx + 1] == 'x') {
    return true
  }
  // Base-60 (`d+(:d+)+`).
  if yaml_looks_like_base60(s) {
    return true
  }
  // Bare leading-zero octal `0\d+` is treated as int by 1.1.
  if s[0] == '0' &&
    len >= 2 &&
    s[1] is '0'..='9' &&
    yaml_string_all_digits(s) {
    return true
  }
  false
}

///|
fn yaml_string_all_digits(s : String) -> Bool {
  for c in s {
    if !(c is '0'..='9') {
      return false
    }
  }
  true
}

///|
fn yaml_looks_like_base60(s : String) -> Bool {
  // Pattern: optional sign, digits, then one or more `:digits`
  // groups, optionally followed by `.digits`. Used by YAML 1.1.
  let len = s.length()
  if len == 0 {
    return false
  }
  let mut idx = 0
  if s[idx] == '+' || s[idx] == '-' {
    idx = idx + 1
  }
  let head_start = idx
  while idx < len && s[idx] is '0'..='9' {
    idx = idx + 1
  }
  if idx == head_start {
    return false
  }
  if idx >= len || s[idx] != ':' {
    return false
  }
  while idx < len && s[idx] == ':' {
    idx = idx + 1
    let group_start = idx
    while idx < len && s[idx] is '0'..='9' {
      idx = idx + 1
    }
    if idx == group_start {
      return false
    }
  }
  if idx < len && s[idx] == '.' {
    idx = idx + 1
    while idx < len && s[idx] is '0'..='9' {
      idx = idx + 1
    }
  }
  idx == len
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
      '\u{00}' => buf.write_string("\\0")
      '\u{07}' => buf.write_string("\\a")
      '\u{08}' => buf.write_string("\\b")
      '\u{0B}' => buf.write_string("\\v")
      '\u{0C}' => buf.write_string("\\f")
      '\u{1B}' => buf.write_string("\\e")
      '\u{85}' => buf.write_string("\\N")
      '\u{A0}' => buf.write_string("\\_")
      '\u{2028}' => buf.write_string("\\L")
      '\u{2029}' => buf.write_string("\\P")
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
      render_pcf_inline(value, 0, false, buf)
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
fn write_yaml_inline_padding(buf : StringBuilder, indent_width : Int) -> Unit {
  for i = 1; i < indent_width; i = i + 1 {
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
