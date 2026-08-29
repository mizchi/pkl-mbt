///|
// Pkl's binary value encoding is MessagePack with small tagged arrays for
// values that MessagePack cannot represent directly. The tag values mirror
// Apple Pkl's PklBinaryCode enum.
let pklbinary_object_code : Int = 0x01

///|
let pklbinary_map_code : Int = 0x02

///|
let pklbinary_mapping_code : Int = 0x03

///|
let pklbinary_list_code : Int = 0x04

///|
let pklbinary_listing_code : Int = 0x05

///|
let pklbinary_set_code : Int = 0x06

///|
let pklbinary_duration_code : Int = 0x07

///|
let pklbinary_datasize_code : Int = 0x08

///|
let pklbinary_pair_code : Int = 0x09

///|
let pklbinary_intseq_code : Int = 0x0a

///|
let pklbinary_regex_code : Int = 0x0b

///|
let pklbinary_class_code : Int = 0x0c

///|
let pklbinary_typealias_code : Int = 0x0d

///|
let pklbinary_function_code : Int = 0x0e

///|
let pklbinary_bytes_code : Int = 0x0f

///|
let pklbinary_property_code : Int = 0x10

///|
let pklbinary_entry_code : Int = 0x11

///|
let pklbinary_element_code : Int = 0x12

///|
fn pklbinary_write_u8(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte(value.to_byte())
}

///|
fn pklbinary_write_array_header(buf : @buffer.Buffer, length : Int) -> Unit {
  if length <= 15 {
    pklbinary_write_u8(buf, 0x90 | length)
  } else if length <= 0xffff {
    pklbinary_write_u8(buf, 0xdc)
    buf.write_uint16_be(length.to_uint16())
  } else {
    pklbinary_write_u8(buf, 0xdd)
    buf.write_uint_be(length.reinterpret_as_uint())
  }
}

///|
fn pklbinary_write_map_header(buf : @buffer.Buffer, length : Int) -> Unit {
  if length <= 15 {
    pklbinary_write_u8(buf, 0x80 | length)
  } else if length <= 0xffff {
    pklbinary_write_u8(buf, 0xde)
    buf.write_uint16_be(length.to_uint16())
  } else {
    pklbinary_write_u8(buf, 0xdf)
    buf.write_uint_be(length.reinterpret_as_uint())
  }
}

///|
fn pklbinary_write_int(buf : @buffer.Buffer, value : Int64) -> Unit {
  if value >= 0L {
    if value <= 0x7fL {
      pklbinary_write_u8(buf, value.to_int())
    } else if value <= 0xffL {
      pklbinary_write_u8(buf, 0xcc)
      pklbinary_write_u8(buf, value.to_int())
    } else if value <= 0xffffL {
      pklbinary_write_u8(buf, 0xcd)
      buf.write_uint16_be(value.to_uint16())
    } else if value <= 0xffffffffL {
      pklbinary_write_u8(buf, 0xce)
      buf.write_uint_be(value.to_int().reinterpret_as_uint())
    } else {
      pklbinary_write_u8(buf, 0xcf)
      buf.write_uint64_be(value.reinterpret_as_uint64())
    }
  } else if value >= -32L {
    pklbinary_write_u8(buf, (value & 0xffL).to_int())
  } else if value >= -128L {
    pklbinary_write_u8(buf, 0xd0)
    pklbinary_write_u8(buf, (value & 0xffL).to_int())
  } else if value >= -32768L {
    pklbinary_write_u8(buf, 0xd1)
    buf.write_int16_be(Int16::from_int64(value))
  } else if value >= -2147483648L {
    pklbinary_write_u8(buf, 0xd2)
    buf.write_int_be(value.to_int())
  } else {
    pklbinary_write_u8(buf, 0xd3)
    buf.write_int64_be(value)
  }
}

///|
fn pklbinary_write_string(buf : @buffer.Buffer, value : String) -> Unit {
  let encoded = @utf8.encode(value[:])
  let length = encoded.length()
  if length <= 31 {
    pklbinary_write_u8(buf, 0xa0 | length)
  } else if length <= 0xff {
    pklbinary_write_u8(buf, 0xd9)
    pklbinary_write_u8(buf, length)
  } else if length <= 0xffff {
    pklbinary_write_u8(buf, 0xda)
    buf.write_uint16_be(length.to_uint16())
  } else {
    pklbinary_write_u8(buf, 0xdb)
    buf.write_uint_be(length.reinterpret_as_uint())
  }
  buf.write_bytes(encoded[:])
}

///|
fn pklbinary_write_binary(buf : @buffer.Buffer, bytes : Bytes) -> Unit {
  let length = bytes.length()
  if length <= 0xff {
    pklbinary_write_u8(buf, 0xc4)
    pklbinary_write_u8(buf, length)
  } else if length <= 0xffff {
    pklbinary_write_u8(buf, 0xc5)
    buf.write_uint16_be(length.to_uint16())
  } else {
    pklbinary_write_u8(buf, 0xc6)
    buf.write_uint_be(length.reinterpret_as_uint())
  }
  buf.write_bytes(bytes[:])
}

///|
fn pklbinary_write_tagged_list_header(
  buf : @buffer.Buffer,
  code : Int,
  payload_length : Int,
) -> Unit {
  pklbinary_write_array_header(buf, payload_length + 1)
  pklbinary_write_int(buf, code.to_int64())
}

///|
fn pklbinary_class_display_name(
  class_name : String,
  cache : Array[ValueBinding],
) -> String {
  if class_name == "module" || class_name == "Module" {
    match lookup_value(cache, "@__module_name") {
      Some(StringValue(name)) if name.length() > 0 => name
      _ => "module"
    }
  } else if class_name == "Dynamic" || is_stdlib_class_name(class_name) {
    class_name
  } else {
    renderer_qualified_user_name(class_name, cache)
  }
}

///|
fn pklbinary_class_module_uri(
  class_name : String,
  cache : Array[ValueBinding],
) -> String {
  if class_name == "module" || class_name == "Module" {
    match lookup_value(cache, "@__module_path") {
      Some(StringValue(path)) => normalize_pklbinary_module_uri(path)
      _ => ""
    }
  } else if class_name == "Dynamic" || is_stdlib_class_name(class_name) {
    "pkl:base"
  } else {
    match lookup_value(cache, "@__module_path") {
      Some(StringValue(path)) => normalize_pklbinary_module_uri(path)
      _ => ""
    }
  }
}

///|
fn pklbinary_write_reflect_value(
  buf : @buffer.Buffer,
  members : Array[ValueMember],
  cache : Array[ValueBinding],
) -> Bool {
  let code = match reflect_kind(members) {
    Some("Class") => pklbinary_class_code
    Some("TypeAlias") => pklbinary_typealias_code
    _ => return false
  }
  let name = match lookup_member(members, "__qualified_name") {
    Some(StringValue(value)) => value
    _ =>
      match lookup_member(members, "name") {
        Some(StringValue(value)) => value
        _ => ""
      }
  }
  let uri = match lookup_member(members, "moduleUri") {
    Some(StringValue(value)) => normalize_pklbinary_module_uri(value)
    _ =>
      match lookup_member(members, "uri") {
        Some(StringValue(value)) => normalize_pklbinary_module_uri(value)
        _ => {
          let simple_name = match lookup_member(members, "simpleName") {
            Some(StringValue(value)) => value
            _ => name
          }
          if (code == pklbinary_class_code && is_stdlib_class_name(simple_name)) ||
            (
              code == pklbinary_typealias_code &&
              is_stdlib_type_alias_name(simple_name)
            ) {
            "pkl:base"
          } else {
            match lookup_value(cache, "@__module_path") {
              Some(StringValue(value)) => normalize_pklbinary_module_uri(value)
              _ => ""
            }
          }
        }
      }
  }
  pklbinary_write_tagged_list_header(buf, code, 2)
  pklbinary_write_string(buf, name)
  pklbinary_write_string(buf, uri)
  true
}

///|
/// Apple Pkl serializes inherited renderer properties after evaluation.
/// Synthetic stdlib classes do not run the VM's external class initializer,
/// so materialize the canonical `PcfRenderer` defaults at this boundary.
fn pklbinary_visible_object_members(
  class_name : String,
  members : Array[ValueMember],
) -> Array[ValueMember] {
  let visible = visible_members(members)
  if class_name != "PcfRenderer" || visible.length() > 0 {
    return visible
  }
  [
    {
      name: "converters",
      value: MappingValue([]),
      source: None,
      annotations: [],
    },
    {
      name: "convertPropertyTransformers",
      value: MappingValue([]),
      source: None,
      annotations: [],
    },
    {
      name: "extension",
      value: StringValue("pcf"),
      source: None,
      annotations: [],
    },
    { name: "indent", value: StringValue("  "), source: None, annotations: [] },
    {
      name: "omitNullProperties",
      value: BoolValue(false),
      source: None,
      annotations: [],
    },
    {
      name: "useCustomStringDelimiters",
      value: BoolValue(false),
      source: None,
      annotations: [],
    },
  ]
}

///|
fn pklbinary_write_object_member(
  buf : @buffer.Buffer,
  field : ValueMember,
  element_index : Int64,
  cache : Array[ValueBinding],
) -> Unit {
  if field.name.has_prefix("@subscript$") {
    match field.value {
      ObjectValue(pair_members) =>
        match
          (
            lookup_member(pair_members, "@key"),
            lookup_member(pair_members, "@value"),
          ) {
          (Some(key), Some(value)) => {
            pklbinary_write_tagged_list_header(buf, pklbinary_entry_code, 2)
            pklbinary_write_value(buf, key, cache)
            pklbinary_write_value(buf, value, cache)
          }
          _ => ()
        }
      _ => ()
    }
  } else if field.name.has_prefix("@element$") {
    pklbinary_write_tagged_list_header(buf, pklbinary_element_code, 2)
    pklbinary_write_int(buf, element_index)
    pklbinary_write_value(buf, field.value, cache)
  } else {
    pklbinary_write_tagged_list_header(buf, pklbinary_property_code, 2)
    pklbinary_write_string(buf, strip_member_visibility_prefix(field.name))
    pklbinary_write_value(buf, field.value, cache)
  }
}

///|
fn pklbinary_write_value(
  buf : @buffer.Buffer,
  value : Value,
  cache : Array[ValueBinding],
) -> Unit {
  match value {
    ThunkValue(_) => pklbinary_write_value(buf, force_eval_thunk(value), cache)
    IntValue(number) => pklbinary_write_int(buf, number)
    FloatValue(number) => {
      pklbinary_write_u8(buf, 0xcb)
      buf.write_double_be(number)
    }
    BoolValue(flag) => pklbinary_write_u8(buf, if flag { 0xc3 } else { 0xc2 })
    StringValue(text) => pklbinary_write_string(buf, text)
    NullValue => pklbinary_write_u8(buf, 0xc0)
    DurationValue(number, unit) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_duration_code, 2)
      pklbinary_write_u8(buf, 0xcb)
      buf.write_double_be(number)
      pklbinary_write_string(buf, unit)
    }
    DataSizeValue(number, unit) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_datasize_code, 2)
      pklbinary_write_u8(buf, 0xcb)
      buf.write_double_be(number)
      pklbinary_write_string(buf, unit)
    }
    BytesValue(bytes) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_bytes_code, 1)
      pklbinary_write_binary(buf, bytes)
    }
    RegexValue(pattern) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_regex_code, 1)
      pklbinary_write_string(buf, pattern)
    }
    PairValue(first, second) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_pair_code, 2)
      pklbinary_write_value(buf, first, cache)
      pklbinary_write_value(buf, second, cache)
    }
    IntSeqValue(start, end_, step) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_intseq_code, 3)
      pklbinary_write_int(buf, start)
      pklbinary_write_int(buf, end_)
      pklbinary_write_int(buf, step)
    }
    FunctionValue(_, _, _, _, _) =>
      pklbinary_write_tagged_list_header(buf, pklbinary_function_code, 0)
    ListValue(elements) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_list_code, 1)
      pklbinary_write_array_header(buf, elements.length())
      for element in elements {
        pklbinary_write_value(buf, element, cache)
      }
    }
    ListingValue(elements) | DefaultedListingValue(_, elements, _) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_listing_code, 1)
      pklbinary_write_array_header(buf, elements.length())
      for element in elements {
        pklbinary_write_value(buf, element, cache)
      }
    }
    SetValue(elements) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_set_code, 1)
      pklbinary_write_array_header(buf, elements.length())
      for element in elements {
        pklbinary_write_value(buf, element, cache)
      }
    }
    MapValue(entries) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_map_code, 1)
      pklbinary_write_map_header(buf, entries.length())
      for entry in entries {
        pklbinary_write_value(buf, entry.key, cache)
        pklbinary_write_value(buf, entry.value, cache)
      }
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) => {
      pklbinary_write_tagged_list_header(buf, pklbinary_mapping_code, 1)
      pklbinary_write_map_header(buf, entries.length())
      for entry in entries {
        pklbinary_write_value(buf, entry.key, cache)
        pklbinary_write_value(buf, entry.value, cache)
      }
    }
    ObjectValue(members) =>
      if !pklbinary_write_reflect_value(buf, members, cache) {
        let class_name = match find_object_class_tag(members) {
          Some(name) => name
          None => "Dynamic"
        }
        let visible = pklbinary_visible_object_members(class_name, members)
        pklbinary_write_tagged_list_header(buf, pklbinary_object_code, 3)
        pklbinary_write_string(
          buf,
          pklbinary_class_display_name(class_name, cache),
        )
        pklbinary_write_string(
          buf,
          pklbinary_class_module_uri(class_name, cache),
        )
        pklbinary_write_array_header(buf, visible.length())
        let mut element_index = 0L
        for field in visible {
          pklbinary_write_object_member(buf, field, element_index, cache)
          if field.name.has_prefix("@element$") {
            element_index = element_index + 1L
          }
        }
      }
    DeferredImportValue(uri) => pklbinary_write_string(buf, uri)
  }
}

///|
fn render_value_as_pklbinary_with_cache(
  value : Value,
  cache : Array[ValueBinding],
) -> Bytes {
  let buf = @buffer.Buffer()
  pklbinary_write_value(buf, value, cache)
  buf.to_bytes()
}

///|
/// Render a value using Pkl's MessagePack-based binary format while keeping
/// user class and module metadata anchored to the containing module.
pub fn render_value_as_pklbinary_with_module(
  value : Value,
  module_name : String,
  module_uri : String,
) -> Bytes {
  let cache : Array[ValueBinding] = [
    { name: "@__module_name", value: StringValue(module_name) },
    { name: "@__module_path", value: StringValue(module_uri) },
  ]
  render_value_as_pklbinary_with_cache(value, cache)
}

///|
/// Render a module projection. Values reconstructed from
/// `output.value = module` do not retain their hidden class marker, so
/// restore it before writing the Pkl binary object envelope.
pub fn render_module_as_pklbinary(
  value : Value,
  module_name : String,
  module_uri : String,
) -> Bytes {
  let module_value = match value {
    ObjectValue(members) =>
      ObjectValue(tag_object_with_class(members, "module"))
    other => other
  }
  render_value_as_pklbinary_with_module(module_value, module_name, module_uri)
}
