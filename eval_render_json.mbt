///|
pub fn render_value_as_json(value : Value) -> String {
  let buf = StringBuilder::new()
  render_json_value(value, 0, buf)
  buf.to_string()
}

///|
fn render_json_value(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) =>
      render_json_object_from_members(members, indent, buf)
    MappingValue(entries) =>
      render_json_object_from_entries(entries, indent, buf)
    ListingValue(elements) | ListValue(elements) =>
      render_json_array(elements, indent, buf)
    FunctionValue(_, _, _, _, _) => buf.write_string("null")
    // Upstream Pkl projects Duration / DataSize to a literal-style string
    // (e.g. `"5.min"`) in JSON / YAML / Properties. Match that shape until
    // the dedicated projection table from `pkl:base` lands.
    DurationValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    // PKL-081: Regex projects as the pattern string in JSON / YAML /
    // Properties, mirroring upstream Apple Pkl behavior for opaque
    // stdlib values.
    RegexValue(pattern) => render_json_string(pattern, buf)
    // PKL-083: Bytes projects as its base64 encoding in non-PCF
    // formats, since none of these formats have a native bytes type
    // and base64 is the upstream-compatible representation.
    BytesValue(bytes) => render_json_string(@base64.encode(bytes[:]), buf)
    // PKL-119a: Pair renders as a 2-element JSON array. Matches
    // Apple Pkl's `Pair`-to-JSON projection.
    PairValue(first, second) => render_json_array([first, second], indent, buf)
    // PKL-119b: IntSeq materializes to an Int array first, then flows
    // through the standard JSON array projection.
    IntSeqValue(start, end_v, step) =>
      render_json_array(intseq_materialize(start, end_v, step), indent, buf)
    // PKL-119c: Set renders as a JSON array. Uniqueness is already
    // enforced at construction, so the array element order matches
    // the upstream insertion-order semantics.
    SetValue(elements) => render_json_array(elements, indent, buf)
    // PKL-119d: Map projects as a JSON object, matching the
    // existing MappingValue projection. The entry-walker coerces
    // non-string keys the same way `json_coerce_key` already does.
    MapValue(entries) => render_json_object_from_entries(entries, indent, buf)
  }
}

///|
fn render_json_string(value : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in value {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' {
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
fn json_hex4(code : Int) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  let mut i = 12
  while i >= 0 {
    let nibble = (code >> i) & 0xF
    buf.write_char(digits.unsafe_get(nibble).to_int().unsafe_to_char())
    i = i - 4
  }
  buf.to_string()
}

///|
fn json_coerce_key(value : Value) -> String {
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
fn write_json_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn render_json_object_from_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  if visible.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < visible.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(visible[i].name, buf)
    buf.write_string(": ")
    render_json_value(visible[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_object_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if entries.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(json_coerce_key(entries[i].key), buf)
    buf.write_string(": ")
    render_json_value(entries[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_array(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if elements.length() == 0 {
    buf.write_string("[]")
    return
  }
  buf.write_string("[\n")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_value(elements[i], indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char(']')
}

///|
/// Render a Value as YAML, mirroring the basic shape of `pkl eval -f yaml`.
///
/// Block style is used throughout: mappings emit `key: value` per line,
/// listings emit `- value` per line at the same column as the parent key, and
/// empty composites use flow form (`[]` / `{}`). String scalars are bare when
/// they parse as plain YAML, single-quoted when they collide with reserved
/// shapes (numeric / keyword / leading indicator / inline `: ` / ` #`), and
/// double-quoted with `\`-escapes when they contain control characters or a
/// backslash. Block scalars (`|`, `|-`, `|+`) for multiline strings remain
/// follow-up work.
///
/// Indentation is fixed at two spaces; Apple Pkl's `indentWidth` knob lives
/// inside the `YamlRenderer` stdlib class (PKL-079 expansion), which our
/// pipeline does not consume yet.
