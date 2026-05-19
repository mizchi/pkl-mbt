///|
pub fn render_value_as_textproto(value : Value) -> String {
  render_value_as_textproto_with_indent(value, "  ")
}

///|
pub fn render_value_as_textproto_with_indent(
  value : Value,
  indent_text : String,
) -> String {
  let buf = StringBuilder::new()
  render_textproto_value(value, 0, indent_text, buf)
  if !buf.to_string().has_suffix("\n") {
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
pub fn render_value_as_textproto_fragment(
  value : Value,
  indent_text : String,
) -> String {
  let buf = StringBuilder::new()
  render_textproto_value(value, 0, indent_text, buf)
  textproto_trim_trailing_newline(buf.to_string())
}

///|
fn render_textproto_value(
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  match value {
    ObjectValue(members) =>
      render_textproto_members(members, level, indent_text, buf)
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      render_textproto_elements_as_fields(
        "it", elements, level, indent_text, buf,
      )
    MappingValue(entries) | MapValue(entries) =>
      render_textproto_entries_as_fields("it", entries, level, indent_text, buf)
    DurationValue(_, _) =>
      render_textproto_duration_body(value, level, indent_text, buf)
    _ => render_textproto_scalar(value, buf)
  }
}

///|
fn render_textproto_members(
  members : Array[ValueMember],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  for field in visible_members(members) {
    render_textproto_field(
      protobuf_member_field_name(field),
      field.value,
      level,
      indent_text,
      buf,
    )
  }
}

///|
fn render_textproto_field(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match value {
    NullValue => ()
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      render_textproto_elements_as_fields(
        name, elements, level, indent_text, buf,
      )
    MappingValue(entries) | MapValue(entries) =>
      render_textproto_entries_as_fields(name, entries, level, indent_text, buf)
    _ => render_textproto_single_field(name, value, level, indent_text, buf)
  }
}

///|
fn render_textproto_single_field(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      write_textproto_indent(buf, level, indent_text)
      buf.write_string(name)
      buf.write_string(": ")
      buf.write_string(text)
      buf.write_char('\n')
      return
    }
    None => ()
  }
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      write_textproto_indent(buf, level, indent_text)
      buf.write_string(name)
      if visible.length() == 0 {
        buf.write_string(": {}\n")
      } else {
        buf.write_string(": {\n")
        render_textproto_members(members, level + 1, indent_text, buf)
        write_textproto_indent(buf, level, indent_text)
        buf.write_string("}\n")
      }
    }
    DurationValue(_, _) => {
      write_textproto_indent(buf, level, indent_text)
      buf.write_string(name)
      buf.write_string(": {\n")
      render_textproto_duration_body(value, level + 1, indent_text, buf)
      write_textproto_indent(buf, level, indent_text)
      buf.write_string("}\n")
    }
    _ => {
      write_textproto_indent(buf, level, indent_text)
      buf.write_string(name)
      buf.write_string(": ")
      render_textproto_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_textproto_elements_as_fields(
  name : String,
  elements : Array[Value],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  for element in elements {
    if textproto_needs_collection_wrapper(element) {
      render_textproto_wrapped_collection_field(
        name, element, level, indent_text, buf,
      )
    } else {
      render_textproto_single_field(name, element, level, indent_text, buf)
    }
  }
}

///|
fn render_textproto_entries_as_fields(
  name : String,
  entries : Array[ValueEntry],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  for entry in entries {
    write_textproto_indent(buf, level, indent_text)
    buf.write_string(name)
    buf.write_string(": {\n")
    write_textproto_indent(buf, level + 1, indent_text)
    buf.write_string("key: ")
    render_textproto_map_key(entry.key, buf)
    buf.write_char('\n')
    if textproto_needs_collection_wrapper(entry.value) {
      render_textproto_wrapped_collection_field(
        "value",
        entry.value,
        level + 1,
        indent_text,
        buf,
      )
    } else {
      render_textproto_single_field(
        "value",
        entry.value,
        level + 1,
        indent_text,
        buf,
      )
    }
    write_textproto_indent(buf, level, indent_text)
    buf.write_string("}\n")
  }
}

///|
fn render_textproto_wrapped_collection_field(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  write_textproto_indent(buf, level, indent_text)
  buf.write_string(name)
  if textproto_collection_is_empty(value) {
    buf.write_string(": {}\n")
    return
  }
  buf.write_string(": {\n")
  match value {
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      render_textproto_elements_as_fields(
        "it",
        elements,
        level + 1,
        indent_text,
        buf,
      )
    MappingValue(entries) | MapValue(entries) =>
      render_textproto_entries_as_fields(
        "it",
        entries,
        level + 1,
        indent_text,
        buf,
      )
    _ => render_textproto_single_field("it", value, level + 1, indent_text, buf)
  }
  write_textproto_indent(buf, level, indent_text)
  buf.write_string("}\n")
}

///|
fn textproto_needs_collection_wrapper(value : Value) -> Bool {
  match value {
    ListingValue(_)
    | ListValue(_)
    | SetValue(_)
    | MappingValue(_)
    | MapValue(_) => true
    _ => false
  }
}

///|
fn textproto_collection_is_empty(value : Value) -> Bool {
  match value {
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      elements.length() == 0
    MappingValue(entries) | MapValue(entries) => entries.length() == 0
    _ => false
  }
}

///|
fn render_textproto_duration_body(
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match value {
    DurationValue(n, unit) => {
      let total_ns = duration_in_unit(n, unit, "ns").to_int64()
      let seconds = total_ns / 1_000_000_000L
      let nanos = total_ns % 1_000_000_000L
      write_textproto_indent(buf, level, indent_text)
      buf.write_string("seconds: ")
      buf.write_string(seconds.to_string())
      buf.write_char('\n')
      write_textproto_indent(buf, level, indent_text)
      buf.write_string("nanos: ")
      buf.write_string(nanos.to_string())
      buf.write_char('\n')
    }
    _ => ()
  }
}

///|
fn render_textproto_scalar(value : Value, buf : StringBuilder) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  match value {
    IntValue(n) => buf.write_string(n.to_string())
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) => write_textproto_string(s, buf)
    NullValue => buf.write_string("null")
    RegexValue(pattern) => write_textproto_string(pattern, buf)
    BytesValue(bytes) => write_textproto_string(@base64.encode(bytes[:]), buf)
    DataSizeValue(n, unit) => write_textproto_string("\{n}.\{unit}", buf)
    DurationValue(_, _) => buf.write_string("{}")
    PairValue(first, second) => {
      buf.write_string("first: ")
      render_textproto_scalar(first, buf)
      buf.write_string(" second: ")
      render_textproto_scalar(second, buf)
    }
    IntSeqValue(start, end_v, step) => {
      let elements = intseq_materialize(start, end_v, step)
      buf.write_string("[")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_textproto_scalar(elements[i], buf)
      }
      buf.write_string("]")
    }
    ObjectValue(_)
    | ListingValue(_)
    | ListValue(_)
    | MappingValue(_)
    | SetValue(_)
    | MapValue(_) => buf.write_string("{}")
    FunctionValue(_, _, _, _, _) => buf.write_string("null")
  }
}

///|
fn render_textproto_map_key(value : Value, buf : StringBuilder) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  match value {
    StringValue(s) => write_textproto_string(s, buf)
    IntValue(n) => buf.write_string(n.to_string())
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    _ => render_textproto_scalar(value, buf)
  }
}

///|
fn protobuf_member_field_name(field : ValueMember) -> String {
  for annotation in field.annotations {
    if annotation.class_name == "Property" ||
      annotation.class_name.has_suffix(".Property") {
      match protobuf_annotation_string_field(annotation.body_text, "name") {
        Some(name) => return name
        None => ()
      }
    }
  }
  field.name
}

///|
fn protobuf_annotation_string_field(
  body : String,
  field_name : String,
) -> String? {
  let needle = field_name + " = \""
  match body.find(needle) {
    Some(start) => {
      let value_start = start + needle.length()
      let rest = String::unsafe_substring(
        body,
        start=value_start,
        end=body.length(),
      )
      match rest.find("\"") {
        Some(end_rel) =>
          Some(String::unsafe_substring(rest, start=0, end=end_rel))
        None => None
      }
    }
    None => None
  }
}

///|
fn write_textproto_indent(
  buf : StringBuilder,
  level : Int,
  indent_text : String,
) -> Unit {
  for i = 0; i < level; i = i + 1 {
    buf.write_string(indent_text)
  }
}

///|
fn write_textproto_string(value : String, buf : StringBuilder) -> Unit {
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
          buf.write_string("\\u")
          buf.write_string(json_hex4(code))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn textproto_trim_trailing_newline(value : String) -> String {
  if value.has_suffix("\n") {
    String::unsafe_substring(value, start=0, end=value.length() - 1)
  } else {
    value
  }
}
