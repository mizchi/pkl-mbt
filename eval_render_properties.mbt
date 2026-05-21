///|
pub fn render_value_as_properties(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_properties_members(members, "", buf)
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      render_properties_entries(entries, "", buf)
    MapValue(entries) => render_properties_entries(entries, "", buf)
    _ => ()
  }
  buf.to_string()
}

///|
pub fn render_value_as_properties_fragment(value : Value) -> String {
  let buf = StringBuilder::new()
  write_properties_scalar(value, buf)
  buf.to_string()
}

///|
fn render_properties_members(
  members : Array[ValueMember],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for field in visible_members(members) {
    render_properties_leaf(prefix, field.name, field.value, buf)
  }
}

///|
fn render_properties_entries(
  entries : Array[ValueEntry],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for entry in entries {
    let key = properties_coerce_key(entry.key)
    render_properties_leaf(prefix, key, entry.value, buf)
  }
}

///|
fn render_properties_leaf(
  prefix : String,
  name : String,
  value : Value,
  buf : StringBuilder,
) -> Unit {
  let full_key = if prefix == "" { name } else { prefix + "." + name }
  match value {
    NullValue => ()
    ObjectValue(members) =>
      if members.length() == 0 {
        // Empty Object has no leaves, so drop the key entirely.
      } else {
        render_properties_members(members, full_key, buf)
      }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      if entries.length() == 0 {
        // Empty Mapping likewise has no leaves.
      } else {
        render_properties_entries(entries, full_key, buf)
      }
    ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | FunctionValue(_, _, _, _, _) => {
      let compact = render_properties_compact_json(value)
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_value(compact, buf)
      buf.write_char('\n')
    }
    _ => {
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_properties_compact_json(value : Value) -> String {
  let buf = StringBuilder::new()
  write_compact_json_value(value, buf)
  buf.to_string()
}

///|
fn write_compact_json_value(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    DeferredImportValue(_) => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) => {
      let visible = visible_members(members)
      buf.write_char('{')
      for i = 0; i < visible.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(visible[i].name, buf)
        buf.write_char(':')
        write_compact_json_value(visible[i].value, buf)
      }
      buf.write_char('}')
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(json_coerce_key(entries[i].key), buf)
        buf.write_char(':')
        write_compact_json_value(entries[i].value, buf)
      }
      buf.write_char('}')
    }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements) => {
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    FunctionValue(_, _, _, _, _) => buf.write_string("null")
    DurationValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    RegexValue(pattern) => render_json_string(pattern, buf)
    BytesValue(bytes) => render_json_string(@base64.encode(bytes[:]), buf)
    // PKL-119a: properties uses the compact-JSON path for composite
    // values; project Pair the same way so a `Pair(1, "a")` shows up
    // as `[1,"a"]` inside the property line.
    PairValue(first, second) => {
      buf.write_char('[')
      write_compact_json_value(first, buf)
      buf.write_char(',')
      write_compact_json_value(second, buf)
      buf.write_char(']')
    }
    // PKL-119b: IntSeq materializes and reuses the listing path so
    // properties lines see `[1,2,3]` for `IntSeq(1, 3)`.
    IntSeqValue(start, end_v, step) => {
      let elements = intseq_materialize(start, end_v, step)
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    // PKL-119c: Set reuses the same compact array form.
    SetValue(elements) => {
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    // PKL-119d: Map projects as a compact JSON object, mirroring the
    // MappingValue projection so properties output sees `{"a":1,"b":2}`
    // for `Map("a", 1, "b", 2)`.
    MapValue(entries) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(json_coerce_key(entries[i].key), buf)
        buf.write_char(':')
        write_compact_json_value(entries[i].value, buf)
      }
      buf.write_char('}')
    }
  }
}

///|
fn write_properties_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("")
    StringValue(s) => write_properties_value(s, buf)
    DurationValue(n, unit) => write_properties_value("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => write_properties_value("\{n}.\{unit}", buf)
    RegexValue(pattern) => write_properties_value(pattern, buf)
    BytesValue(bytes) => write_properties_value(@base64.encode(bytes[:]), buf)
    _ =>
      // Unreachable in practice: render_properties_leaf already dispatches
      // composites through the compact-JSON path.
      write_properties_value(render_properties_compact_json(value), buf)
  }
}

///|
fn write_properties_key(key : String, buf : StringBuilder) -> Unit {
  for c in key {
    match c {
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0C}' => buf.write_string("\\f")
      ' ' => buf.write_string("\\ ")
      ':' => buf.write_string("\\:")
      '=' => buf.write_string("\\=")
      '!' => buf.write_string("\\!")
      '#' => buf.write_string("\\#")
      _ => buf.write_char(c)
    }
  }
}

///|
fn write_properties_value(s : String, buf : StringBuilder) -> Unit {
  let mut first = true
  for c in s {
    if first && c == ' ' {
      buf.write_string("\\ ")
    } else {
      match c {
        '\\' => buf.write_string("\\\\")
        '\n' => buf.write_string("\\n")
        '\r' => buf.write_string("\\r")
        '\t' => buf.write_string("\\t")
        '\u{0C}' => buf.write_string("\\f")
        ':' => buf.write_string("\\:")
        '=' => buf.write_string("\\=")
        '!' => buf.write_string("\\!")
        '#' => buf.write_string("\\#")
        _ => buf.write_char(c)
      }
    }
    first = false
  }
}

///|
fn properties_coerce_key(value : Value) -> String {
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
