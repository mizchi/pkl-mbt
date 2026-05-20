///|
pub fn render_value_as_xml(value : Value) -> String {
  render_value_as_xml_with_options(value, "root", "  ", "1.0")
}

///|
pub fn render_value_as_xml_with_options(
  value : Value,
  root_element_name : String,
  indent_text : String,
  xml_version : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"")
  write_xml_escaped_attr(xml_version, buf)
  buf.write_string("\" encoding=\"UTF-8\"?>\n")
  render_xml_named_element(root_element_name, value, 0, indent_text, buf)
  buf.write_char('\n')
  buf.to_string()
}

///|
pub fn render_value_as_xml_fragment(
  value : Value,
  indent_text : String,
) -> String {
  let buf = StringBuilder::new()
  render_xml_fragment_value(value, 0, indent_text, buf)
  buf.to_string()
}

///|
fn render_xml_named_element(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  if value is NullValue {
    return
  }
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Inline") =>
          match lookup_member(members, "value") {
            Some(inner) =>
              render_xml_inline_or_children(inner, level, indent_text, buf)
            None => ()
          }
        Some("Element") =>
          render_xml_element_object(members, level, indent_text, buf)
        Some("Comment") =>
          render_xml_comment_object(members, level, indent_text, buf)
        _ =>
          render_xml_regular_named_element(name, value, level, indent_text, buf)
      }
    _ => render_xml_regular_named_element(name, value, level, indent_text, buf)
  }
}

///|
fn render_xml_regular_named_element(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  write_xml_indent(buf, level, indent_text)
  if xml_value_is_block(value) {
    if xml_value_is_empty_block(value) {
      buf.write_char('<')
      write_xml_name(name, buf)
      buf.write_string("/>")
      return
    }
    buf.write_char('<')
    write_xml_name(name, buf)
    buf.write_char('>')
    buf.write_char('\n')
    render_xml_children(value, level + 1, indent_text, buf)
    buf.write_char('\n')
    write_xml_indent(buf, level, indent_text)
    buf.write_string("</")
    write_xml_name(name, buf)
    buf.write_char('>')
  } else {
    buf.write_char('<')
    write_xml_name(name, buf)
    buf.write_char('>')
    render_xml_inline_content(value, buf)
    buf.write_string("</")
    write_xml_name(name, buf)
    buf.write_char('>')
  }
}

///|
fn render_xml_element_object(
  members : Array[ValueMember],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  let element_name = match lookup_member(members, "name") {
    Some(StringValue(s)) => s
    _ => "element"
  }
  let body = xml_element_body_members(members)
  write_xml_indent(buf, level, indent_text)
  if body.length() == 0 {
    buf.write_char('<')
    write_xml_name(element_name, buf)
    buf.write_string("/>")
    return
  }
  let body_value = ObjectValue(body)
  if xml_value_is_block(body_value) {
    buf.write_char('<')
    write_xml_name(element_name, buf)
    buf.write_char('>')
    buf.write_char('\n')
    render_xml_children(body_value, level + 1, indent_text, buf)
    buf.write_char('\n')
    write_xml_indent(buf, level, indent_text)
    buf.write_string("</")
    write_xml_name(element_name, buf)
    buf.write_char('>')
  } else {
    buf.write_char('<')
    write_xml_name(element_name, buf)
    buf.write_char('>')
    render_xml_inline_content(body_value, buf)
    buf.write_string("</")
    write_xml_name(element_name, buf)
    buf.write_char('>')
  }
}

///|
fn render_xml_comment_object(
  members : Array[ValueMember],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  let text = match lookup_member(members, "text") {
    Some(StringValue(s)) => s
    _ => ""
  }
  write_xml_indent(buf, level, indent_text)
  buf.write_string("<!--")
  buf.write_string(text)
  buf.write_string("-->")
}

///|
fn render_xml_children(
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  let mut first = true
  match value {
    ObjectValue(members) =>
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        if !first {
          buf.write_char('\n')
        }
        render_xml_member(field, level, indent_text, buf)
        first = false
      }
    MappingValue(entries) | MapValue(entries) =>
      for entry in entries {
        if entry.value is NullValue {
          continue
        }
        if !first {
          buf.write_char('\n')
        }
        render_xml_named_element(
          xml_coerce_key(entry.key),
          entry.value,
          level,
          indent_text,
          buf,
        )
        first = false
      }
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      for element in elements {
        if element is NullValue {
          continue
        }
        if !first {
          if xml_value_is_block(element) || xml_value_is_xml_special(element) {
            buf.write_char('\n')
          }
        }
        render_xml_fragment_value(element, level, indent_text, buf)
        first = false
      }
    _ => render_xml_fragment_value(value, level, indent_text, buf)
  }
}

///|
fn render_xml_member(
  field : ValueMember,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match xml_member_source_constructor(field.source) {
    Some("CData") => {
      let name = xml_member_element_name(field)
      write_xml_indent(buf, level, indent_text)
      buf.write_char('<')
      write_xml_name(name, buf)
      buf.write_char('>')
      match field.value {
        ObjectValue(members) =>
          match lookup_member(members, "text") {
            Some(StringValue(text)) => write_xml_cdata(text, buf)
            _ => ()
          }
        _ => render_xml_inline_content(field.value, buf)
      }
      buf.write_string("</")
      write_xml_name(name, buf)
      buf.write_char('>')
      return
    }
    Some("Comment") => {
      match field.value {
        ObjectValue(members) =>
          render_xml_comment_object(members, level, indent_text, buf)
        _ => render_xml_inline_content(field.value, buf)
      }
      return
    }
    _ => ()
  }
  if field.name.has_prefix("@element$") {
    render_xml_fragment_value(field.value, level, indent_text, buf)
    return
  }
  if field.name.has_prefix("@subscript$") {
    match field.value {
      ObjectValue(pair_members) =>
        match
          (
            lookup_member(pair_members, "@key"),
            lookup_member(pair_members, "@value"),
          ) {
          (Some(key), Some(value)) =>
            render_xml_named_element(
              xml_coerce_key(key),
              value,
              level,
              indent_text,
              buf,
            )
          _ => ()
        }
      _ => ()
    }
    return
  }
  let name = xml_member_element_name(field)
  render_xml_named_element(name, field.value, level, indent_text, buf)
}

///|
fn xml_member_source_constructor(source : Expr?) -> String? {
  match source {
    Some(CallExpr(MemberAccess(Identifier(_), name), _)) =>
      match name {
        "CData" | "Comment" => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn render_xml_fragment_value(
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Inline") =>
          match lookup_member(members, "value") {
            Some(inner) =>
              render_xml_inline_or_children(inner, level, indent_text, buf)
            None => ()
          }
        Some("Element") =>
          render_xml_element_object(members, level, indent_text, buf)
        Some("Comment") =>
          render_xml_comment_object(members, level, indent_text, buf)
        _ =>
          if xml_value_is_block(value) {
            render_xml_children(value, level, indent_text, buf)
          } else {
            render_xml_inline_content(value, buf)
          }
      }
    MappingValue(_) | MapValue(_) =>
      render_xml_children(value, level, indent_text, buf)
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      for element in elements {
        render_xml_fragment_value(element, level, indent_text, buf)
      }
    _ => render_xml_inline_content(value, buf)
  }
}

///|
fn render_xml_inline_or_children(
  value : Value,
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  if xml_value_is_block(value) || xml_value_is_xml_special(value) {
    render_xml_fragment_value(value, level, indent_text, buf)
  } else {
    render_xml_inline_content(value, buf)
  }
}

///|
fn render_xml_inline_content(value : Value, buf : StringBuilder) -> Unit {
  match render_directive_text(value) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) => write_xml_escaped_text(s, buf)
    NullValue => ()
    DurationValue(n, unit) => {
      buf.write_string("\{n} ")
      buf.write_string(unit)
    }
    DataSizeValue(n, unit) => {
      buf.write_string("\{n} ")
      buf.write_string(unit)
    }
    RegexValue(pattern) => write_xml_escaped_text(pattern, buf)
    BytesValue(bytes) => buf.write_string(@base64.encode(bytes[:]))
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("CData") =>
          match lookup_member(members, "text") {
            Some(StringValue(text)) => write_xml_cdata(text, buf)
            _ => ()
          }
        Some("Inline") =>
          match lookup_member(members, "value") {
            Some(inner) => render_xml_inline_content(inner, buf)
            None => ()
          }
        _ =>
          for field in visible_members(members) {
            if field.value is NullValue {
              continue
            }
            render_xml_inline_content(field.value, buf)
          }
      }
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      for element in elements {
        render_xml_inline_content(element, buf)
      }
    MappingValue(entries) | MapValue(entries) =>
      for entry in entries {
        render_xml_inline_content(entry.value, buf)
      }
    FunctionValue(_, _, _, _, _) => ()
    PairValue(first, second) => {
      render_xml_inline_content(first, buf)
      render_xml_inline_content(second, buf)
    }
    IntSeqValue(start, end_v, step) =>
      for element in intseq_materialize(start, end_v, step) {
        render_xml_inline_content(element, buf)
      }
  }
}

///|
fn xml_value_is_block(value : Value) -> Bool {
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("CData") | Some("Inline") | Some("Comment") => false
        Some("Element") => xml_element_body_members(members).length() > 0
        _ => {
          for field in visible_members(members) {
            if field.value is NullValue {
              continue
            }
            if field.name.has_prefix("@element$") {
              if xml_value_is_block(field.value) ||
                xml_value_is_xml_special(field.value) {
                return true
              }
              continue
            }
            return true
          }
          false
        }
      }
    MappingValue(entries) | MapValue(entries) => entries.length() > 0
    ListingValue(elements) | ListValue(elements) | SetValue(elements) => {
      for element in elements {
        if xml_value_is_block(element) || xml_value_is_xml_special(element) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn xml_value_is_empty_block(value : Value) -> Bool {
  match value {
    ObjectValue(members) => {
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        return false
      }
      true
    }
    MappingValue(entries) | MapValue(entries) => entries.length() == 0
    _ => false
  }
}

///|
fn xml_value_is_xml_special(value : Value) -> Bool {
  match value {
    ObjectValue(members) => xml_object_kind(members) is Some(_)
    _ => false
  }
}

///|
fn xml_object_kind(members : Array[ValueMember]) -> String? {
  match lookup_member(members, "__xmlKind") {
    Some(StringValue(kind)) => return Some(kind)
    _ => ()
  }
  match find_object_class_tag(members) {
    Some(class_name) =>
      if class_name.has_suffix("Element") {
        return Some("Element")
      } else if class_name.has_suffix("Inline") {
        return Some("Inline")
      } else if class_name.has_suffix("CData") {
        return Some("CData")
      } else if class_name.has_suffix("Comment") {
        return Some("Comment")
      } else {
        ()
      }
    None => ()
  }
  let visible = visible_members(members)
  if visible.length() == 1 && visible[0].name == "value" {
    return Some("Inline")
  }
  let mut has_name = false
  let mut element_shaped = true
  for field in visible {
    if field.name == "name" {
      has_name = true
    } else if field.name == "isBlockFormat" ||
      field.name.has_prefix("@element$") ||
      field.name.has_prefix("@subscript$") {
      ()
    } else {
      element_shaped = false
    }
  }
  if has_name && element_shaped {
    return Some("Element")
  }
  None
}

///|
fn xml_element_body_members(members : Array[ValueMember]) -> Array[ValueMember] {
  let body : Array[ValueMember] = []
  for field in visible_members(members) {
    if xml_member_is_element_metadata(field.name) {
      continue
    }
    body.push(field)
  }
  body
}

///|
fn xml_member_is_element_metadata(name : String) -> Bool {
  name == "name" || name == "isBlockFormat"
}

///|
fn xml_member_element_name(field : ValueMember) -> String {
  for annotation in field.annotations {
    if annotation.class_name.has_suffix(".Property") ||
      annotation.class_name == "Property" {
      match xml_annotation_string_field(annotation.body_text, "name") {
        Some(name) => return name
        None => ()
      }
    }
  }
  field.name
}

///|
fn xml_annotation_string_field(body : String, field_name : String) -> String? {
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
fn xml_coerce_key(value : Value) -> String {
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
fn write_xml_indent(
  buf : StringBuilder,
  level : Int,
  indent_text : String,
) -> Unit {
  for _i = 0; _i < level; _i = _i + 1 {
    buf.write_string(indent_text)
  }
}

///|
fn write_xml_name(name : String, buf : StringBuilder) -> Unit {
  buf.write_string(name)
}

///|
fn write_xml_escaped_text(value : String, buf : StringBuilder) -> Unit {
  for c in value {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(c)
    }
  }
}

///|
fn write_xml_escaped_attr(value : String, buf : StringBuilder) -> Unit {
  for c in value {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      _ => buf.write_char(c)
    }
  }
}

///|
fn write_xml_cdata(value : String, buf : StringBuilder) -> Unit {
  buf.write_string("<![CDATA[")
  let mut start = 0
  while start < value.length() {
    let rest = String::unsafe_substring(value, start~, end=value.length())
    match rest.find("]]>") {
      Some(idx) => {
        let end = start + idx + 2
        buf.write_string(String::unsafe_substring(value, start~, end~))
        buf.write_string("]]><![CDATA[")
        start = end
      }
      None => {
        buf.write_string(rest)
        start = value.length()
      }
    }
  }
  buf.write_string("]]>")
}
