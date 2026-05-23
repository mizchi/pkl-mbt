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
fn xml_render_document_error(
  value : Value,
  root_element_name : String,
  xml_version : String,
) -> String? {
  match xml_name_error(root_element_name, xml_version, "element") {
    Some(message) => return Some(message)
    None => xml_render_value_error(value, xml_version)
  }
}

///|
fn xml_render_value_error(value : Value, xml_version : String) -> String? {
  xml_render_nested_value_error(value, xml_version, true)
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
        Some("CData") =>
          render_xml_regular_named_element(name, value, level, indent_text, buf)
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
    let starts_inline = xml_value_starts_with_inline_child(value)
    let ends_inline = xml_value_ends_with_inline_child(value)
    buf.write_char('<')
    write_xml_name(name, buf)
    buf.write_char('>')
    if !starts_inline {
      buf.write_char('\n')
    }
    render_xml_children(value, level + 1, indent_text, buf)
    if !ends_inline {
      buf.write_char('\n')
      write_xml_indent(buf, level, indent_text)
    }
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
  let block_format = xml_element_is_block_format(members)
  let attributes = xml_element_attributes(members)
  let body = xml_element_body_members(members)
  if block_format {
    write_xml_indent(buf, level, indent_text)
  }
  if body.length() == 0 {
    buf.write_char('<')
    write_xml_name(element_name, buf)
    write_xml_attributes(attributes, buf)
    buf.write_string("></")
    write_xml_name(element_name, buf)
    buf.write_char('>')
    return
  }
  let body_value = ObjectValue(body)
  if xml_value_is_block(body_value) {
    let starts_inline = xml_value_starts_with_inline_child(body_value)
    let ends_inline = xml_value_ends_with_inline_child(body_value)
    buf.write_char('<')
    write_xml_name(element_name, buf)
    write_xml_attributes(attributes, buf)
    buf.write_char('>')
    if !starts_inline {
      buf.write_char('\n')
    }
    render_xml_children(body_value, level + 1, indent_text, buf)
    if !ends_inline {
      buf.write_char('\n')
      if block_format {
        write_xml_indent(buf, level, indent_text)
      }
    }
    buf.write_string("</")
    write_xml_name(element_name, buf)
    buf.write_char('>')
  } else {
    buf.write_char('<')
    write_xml_name(element_name, buf)
    write_xml_attributes(attributes, buf)
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
  let mut previous_inline = false
  match value {
    ObjectValue(members) =>
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        let mut rendered = render_xml_member_to_string(
          field, level, indent_text,
        )
        let current_inline = xml_rendered_member_is_inline(
          rendered, level, indent_text,
        )
        if (first || previous_inline) && current_inline {
          rendered = xml_strip_leading_newline(rendered)
        }
        if !first {
          if !(previous_inline && current_inline) {
            buf.write_char('\n')
          }
        }
        buf.write_string(rendered)
        previous_inline = current_inline
        first = false
      }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
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
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      for element in elements {
        if element is NullValue {
          continue
        }
        let current_inline = xml_fragment_renders_inline(element)
        if !first {
          if !(previous_inline && current_inline) {
            buf.write_char('\n')
          }
        }
        render_xml_fragment_value(element, level, indent_text, buf)
        previous_inline = current_inline
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
  if field.name.has_prefix("@element$") {
    match xml_member_source_constructor(field.source) {
      Some("CData") =>
        match field.value {
          ObjectValue(members) =>
            match lookup_member(members, "text") {
              Some(StringValue(text)) => {
                write_xml_cdata(text, buf)
                return
              }
              _ => ()
            }
          _ => ()
        }
      Some("Comment") =>
        match field.value {
          ObjectValue(members) => {
            render_xml_comment_object(members, level, indent_text, buf)
            return
          }
          _ => ()
        }
      _ => ()
    }
    if xml_member_source_function_name(field.source) == Some("comment") {
      match field.value {
        ObjectValue(members) => {
          render_xml_comment_object(members, level, indent_text, buf)
          return
        }
        _ => ()
      }
    }
    match field.value {
      ObjectValue(members) => {
        let visible = visible_members(members)
        if visible.length() == 1 && visible[0].name == "text" {
          render_xml_comment_object(members, level, indent_text, buf)
          return
        }
      }
      _ => ()
    }
    render_xml_fragment_value(field.value, level, indent_text, buf)
    return
  }
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
fn render_xml_member_to_string(
  field : ValueMember,
  level : Int,
  indent_text : String,
) -> String {
  let buf = StringBuilder::new()
  render_xml_member(field, level, indent_text, buf)
  buf.to_string()
}

///|
fn xml_rendered_member_is_inline(
  rendered : String,
  level : Int,
  indent_text : String,
) -> Bool {
  if level == 0 {
    return xml_rendered_member_has_inline_prefix(rendered)
  }
  let prefix = xml_indent_string(level, indent_text)
  !rendered.has_prefix(prefix)
}

///|
fn xml_rendered_member_has_inline_prefix(rendered : String) -> Bool {
  !(rendered.has_prefix("<") || rendered.has_prefix(" "))
}

///|
fn xml_strip_leading_newline(rendered : String) -> String {
  if rendered.has_prefix("\n") {
    String::unsafe_substring(rendered, start=1, end=rendered.length())
  } else {
    rendered
  }
}

///|
fn xml_indent_string(level : Int, indent_text : String) -> String {
  let buf = StringBuilder::new()
  write_xml_indent(buf, level, indent_text)
  buf.to_string()
}

///|
fn xml_member_source_constructor(source : Expr?) -> String? {
  match source {
    Some(CallExpr(MemberAccess(Identifier(_), name), _)) =>
      match name {
        "CData" | "Comment" | "Inline" => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn xml_member_source_function_name(source : Expr?) -> String? {
  match source {
    Some(CallExpr(Identifier(name), _)) => Some(name)
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
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 1 && visible[0].name == "text" {
        render_xml_comment_object(members, level, indent_text, buf)
        return
      }
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
    }
    MappingValue(_) | DefaultedMappingValue(_, _, _) | MapValue(_) =>
      render_xml_children(value, level, indent_text, buf)
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      render_xml_fragment_elements(elements, level, indent_text, buf)
    _ => render_xml_inline_content(value, buf)
  }
}

///|
fn render_xml_fragment_elements(
  elements : Array[Value],
  level : Int,
  indent_text : String,
  buf : StringBuilder,
) -> Unit {
  let mut first = true
  let mut previous_inline = false
  for element in elements {
    if element is NullValue {
      continue
    }
    let current_inline = xml_fragment_renders_inline(element)
    if !first && !(previous_inline && current_inline) {
      buf.write_char('\n')
    }
    render_xml_fragment_value(element, level, indent_text, buf)
    previous_inline = current_inline
    first = false
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
    DeferredImportValue(_) => ()
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
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      for element in elements {
        render_xml_inline_content(element, buf)
      }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
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
  if render_directive_text(value) is Some(_) {
    return false
  }
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("CData") | Some("Inline") | Some("Comment") => false
        Some("Element") =>
          xml_element_is_block_format(members) &&
          xml_element_body_members(members).length() > 0
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
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => entries.length() > 0
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => {
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
fn xml_value_starts_with_inline_child(value : Value) -> Bool {
  match value {
    ObjectValue(members) =>
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        return xml_member_renders_inline(field)
      }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      for element in elements {
        if element is NullValue {
          continue
        }
        return xml_fragment_renders_inline(element)
      }
    _ => ()
  }
  false
}

///|
fn xml_value_ends_with_inline_child(value : Value) -> Bool {
  let mut found = false
  let mut inline = false
  match value {
    ObjectValue(members) =>
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        found = true
        inline = xml_member_renders_inline(field)
      }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) =>
      for element in elements {
        if element is NullValue {
          continue
        }
        found = true
        inline = xml_fragment_renders_inline(element)
      }
    _ => ()
  }
  found && inline
}

///|
fn xml_member_renders_inline(field : ValueMember) -> Bool {
  if xml_member_source_constructor(field.source) is Some("Inline") {
    return xml_fragment_renders_inline(field.value)
  }
  if field.name.has_prefix("@element$") {
    return xml_fragment_renders_inline(field.value)
  }
  match field.value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Inline") => xml_fragment_renders_inline(field.value)
        _ => false
      }
    _ => false
  }
}

///|
fn xml_fragment_renders_inline(value : Value) -> Bool {
  if render_directive_text(value) is Some(_) {
    return true
  }
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Inline") =>
          match lookup_member(members, "value") {
            Some(inner) => xml_fragment_renders_inline(inner)
            None => true
          }
        Some("Element") => !xml_element_is_block_format(members)
        Some("CData") => true
        Some("Comment") => false
        _ => !xml_value_is_block(value)
      }
    _ => !xml_value_is_block(value)
  }
}

///|
fn xml_element_is_block_format(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "isBlockFormat") {
    Some(BoolValue(false)) => false
    _ => true
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
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => entries.length() == 0
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
  match lookup_member(members, "__class") {
    Some(StringValue(class_name)) =>
      match xml_kind_from_class_name(class_name) {
        Some(kind) => return Some(kind)
        None => ()
      }
    _ => ()
  }
  match find_object_class_tag(members) {
    Some(class_name) =>
      match xml_kind_from_class_name(class_name) {
        Some(kind) => return Some(kind)
        None => ()
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
fn xml_kind_from_class_name(class_name : String) -> String? {
  if class_name.has_suffix("Element") {
    Some("Element")
  } else if class_name.has_suffix("Inline") {
    Some("Inline")
  } else if class_name.has_suffix("CData") {
    Some("CData")
  } else if class_name.has_suffix("Comment") {
    Some("Comment")
  } else {
    None
  }
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
  name == "name" || name == "isBlockFormat" || name == "attributes"
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
  // PKL-153f: a RenderDirective key uses its `text` verbatim — Apple
  // Pkl accepts an arbitrary string (even emoji) as the element name
  // when it came from a directive.
  match render_directive_text(value) {
    Some(text) => return text
    None => ()
  }
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
fn xml_element_attributes(members : Array[ValueMember]) -> Array[ValueEntry] {
  let attributes : Array[ValueEntry] = []
  match lookup_member(members, "attributes") {
    Some(value) => append_xml_attribute_entries(attributes, value)
    None => ()
  }
  attributes
}

///|
fn append_xml_attribute_entries(out : Array[ValueEntry], value : Value) -> Unit {
  match value {
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      for entry in entries {
        out.push(entry)
      }
    ObjectValue(members) =>
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        if field.name.has_prefix("@subscript$") {
          match field.value {
            ObjectValue(pair_members) =>
              match
                (
                  lookup_member(pair_members, "@key"),
                  lookup_member(pair_members, "@value"),
                ) {
                (Some(key), Some(attr_value)) =>
                  out.push({ key, value: attr_value })
                _ => ()
              }
            _ => ()
          }
        } else {
          out.push({ key: StringValue(field.name), value: field.value })
        }
      }
    _ => ()
  }
}

///|
fn write_xml_attributes(
  attributes : Array[ValueEntry],
  buf : StringBuilder,
) -> Unit {
  for entry in attributes {
    buf.write_char(' ')
    write_xml_name(xml_coerce_key(entry.key), buf)
    buf.write_string("=\"")
    write_xml_escaped_attr(xml_attribute_value_text(entry.value), buf)
    buf.write_char('"')
  }
}

///|
fn xml_attribute_value_text(value : Value) -> String {
  match render_directive_text(value) {
    Some(text) => return text
    None => ()
  }
  match value {
    StringValue(s) => s
    IntValue(n) => n.to_string()
    FloatValue(d) => render_float_text(d)
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    _ => render_pcf_value_inline(value)
  }
}

///|
fn xml_render_nested_value_error(
  value : Value,
  xml_version : String,
  top_level : Bool,
) -> String? {
  match xml_unsupported_value_error(value, top_level) {
    Some(message) => return Some(message)
    None => ()
  }
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Element") => xml_element_render_error(members, xml_version)
        Some("Inline") =>
          match lookup_member(members, "value") {
            Some(inner) =>
              match xml_nested_inline_special_kind(inner) {
                Some(kind) => Some(xml_unsupported_here_message(kind, inner))
                None => xml_render_nested_value_error(inner, xml_version, false)
              }
            None => None
          }
        Some("CData") | Some("Comment") => None
        _ => xml_object_render_error(members, xml_version)
      }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => xml_entries_render_error(entries, xml_version)
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => xml_elements_render_error(elements, xml_version)
    _ => None
  }
}

///|
fn xml_nested_inline_special_kind(value : Value) -> String? {
  match value {
    ObjectValue(members) =>
      match xml_object_kind(members) {
        Some("Element") => Some("Element")
        Some("Inline") => Some("Inline")
        _ => None
      }
    _ => None
  }
}

///|
fn xml_unsupported_here_message(kind : String, value : Value) -> String {
  "`xml.\{kind}` is not supported here. Value: \{xml_unsupported_here_value_text(kind, value)}"
}

///|
fn xml_unsupported_here_value_text(kind : String, value : Value) -> String {
  match (kind, value) {
    ("Element", ObjectValue(members)) => {
      let name = match lookup_member(members, "name") {
        Some(StringValue(s)) => s
        _ => "element"
      }
      "new Dynamic { _isXmlElement = true; name = \"\{name}\"; attributes {}; isBlockF..."
    }
    ("Inline", ObjectValue(members)) =>
      match lookup_member(members, "value") {
        Some(inner) =>
          "new Inline { value \{xml_placeholder_value_text(inner)} }"
        None => "new Inline {}"
      }
    _ => render_pcf_value_inline(value)
  }
}

///|
fn xml_placeholder_value_text(value : Value) -> String {
  match value {
    ObjectValue(members) => {
      let buf = StringBuilder::new()
      buf.write_string("{ ")
      let mut first = true
      for field in visible_members(members) {
        if field.value is NullValue {
          continue
        }
        if !first {
          buf.write_string("; ")
        }
        buf.write_string(field.name)
        buf.write_string(" = ?")
        first = false
      }
      buf.write_string(" }")
      buf.to_string()
    }
    _ => render_pcf_value_inline(value)
  }
}

///|
fn xml_unsupported_value_error(value : Value, top_level : Bool) -> String? {
  match value {
    NullValue =>
      if top_level {
        Some(xml_unsupported_value_message(value))
      } else {
        None
      }
    DurationValue(_, _)
    | DataSizeValue(_, _)
    | FunctionValue(_, _, _, _, _)
    | PairValue(_, _)
    | IntSeqValue(_, _, _) => Some(xml_unsupported_value_message(value))
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(xml_unsupported_value_message(value))
        _ => None
      }
    _ => None
  }
}

///|
fn xml_unsupported_value_message(value : Value) -> String {
  "Cannot render value of type `\{xml_unsupported_type_name(value)}` as XML. Value: \{xml_unsupported_value_text(value)}"
}

///|
fn xml_unsupported_type_name(value : Value) -> String {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some(kind) => kind
        None => eval_value_type_name(value)
      }
    FunctionValue(parameters, _, _, _, _) => "Function\{parameters.length()}"
    _ => eval_value_type_name(value)
  }
}

///|
fn xml_unsupported_value_text(value : Value) -> String {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          match lookup_member(members, "__qualified_name") {
            Some(StringValue(name)) => name
            _ =>
              match lookup_member(members, "name") {
                Some(StringValue(name)) => name
                _ => render_pcf_value_inline(value)
              }
          }
        _ => render_pcf_value_inline(value)
      }
    FunctionValue(parameters, _, _, _, _) =>
      "new Function\{parameters.length()} {}"
    _ => render_pcf_value_inline(value)
  }
}

///|
fn xml_element_render_error(
  members : Array[ValueMember],
  xml_version : String,
) -> String? {
  let element_name = match lookup_member(members, "name") {
    Some(StringValue(s)) => s
    _ => "element"
  }
  match xml_name_error(element_name, xml_version, "element") {
    Some(message) => return Some(message)
    None => ()
  }
  let attributes = xml_element_attributes(members)
  for entry in attributes {
    let name = xml_coerce_key(entry.key)
    match xml_name_error(name, xml_version, "attribute") {
      Some(message) => return Some(message)
      None => ()
    }
    match xml_render_nested_value_error(entry.value, xml_version, false) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  xml_object_render_error(xml_element_body_members(members), xml_version)
}

///|
fn xml_object_render_error(
  members : Array[ValueMember],
  xml_version : String,
) -> String? {
  for field in visible_members(members) {
    if field.value is NullValue {
      continue
    }
    if field.name.has_prefix("@element$") {
      match xml_render_nested_value_error(field.value, xml_version, false) {
        Some(message) => return Some(message)
        None => ()
      }
      continue
    }
    if field.name.has_prefix("@subscript$") {
      match field.value {
        ObjectValue(pair_members) =>
          match
            (
              lookup_member(pair_members, "@key"),
              lookup_member(pair_members, "@value"),
            ) {
            (Some(key), Some(entry_value)) => {
              match
                xml_name_error(xml_coerce_key(key), xml_version, "element") {
                Some(message) => return Some(message)
                None => ()
              }
              match
                xml_render_nested_value_error(entry_value, xml_version, false) {
                Some(message) => return Some(message)
                None => ()
              }
            }
            _ => ()
          }
        _ => ()
      }
      continue
    }
    let name = xml_member_element_name(field)
    match xml_name_error(name, xml_version, "element") {
      Some(message) => return Some(message)
      None => ()
    }
    match xml_render_nested_value_error(field.value, xml_version, false) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  None
}

///|
fn xml_entries_render_error(
  entries : Array[ValueEntry],
  xml_version : String,
) -> String? {
  for entry in entries {
    if entry.value is NullValue {
      continue
    }
    // PKL-153f: skip the name-validity check for keys that came from
    // a RenderDirective — Apple Pkl emits the directive's text raw
    // even when the resulting element name isn't a valid XML 1.0
    // identifier.
    if render_directive_text(entry.key) is None {
      match xml_name_error(xml_coerce_key(entry.key), xml_version, "element") {
        Some(message) => return Some(message)
        None => ()
      }
    }
    match xml_render_nested_value_error(entry.value, xml_version, false) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  None
}

///|
fn xml_elements_render_error(
  elements : Array[Value],
  xml_version : String,
) -> String? {
  for element in elements {
    if element is NullValue {
      continue
    }
    match xml_render_nested_value_error(element, xml_version, false) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  None
}

///|
fn xml_name_error(
  name : String,
  xml_version : String,
  kind : String,
) -> String? {
  if xml_name_is_valid(name, xml_version) {
    None
  } else {
    Some("Invalid XML \{xml_version} \{kind} name: `\{name}`")
  }
}

///|
fn xml_name_is_valid(name : String, xml_version : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for c in name {
    if xml_version == "1.0" {
      if !xml_name_char_is_ascii(c) {
        return false
      }
    } else if !xml_name_char_is_xml11(c) {
      return false
    }
  }
  true
}

///|
fn xml_name_char_is_ascii(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') ||
  (c >= 'a' && c <= 'z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-' ||
  c == '.' ||
  c == ':'
}

///|
fn xml_name_char_is_xml11(c : Char) -> Bool {
  if c <= ' ' {
    return false
  }
  c != '<' && c != '>' && c != '&' && c != '"'
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
      '"' => buf.write_string("&quot;")
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
