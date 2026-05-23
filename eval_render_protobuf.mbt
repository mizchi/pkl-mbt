///|
/// Type-driven Protobuf textproto-fragment renderer. Distinct from the
/// generic textproto serializer in `eval_render_textproto.mbt`: this
/// path is class-aware and resolves Pkl union annotations to the
/// `it_<choice>` discriminant fields Apple Pkl's `protobuf.Renderer`
/// emits. Functions here previously lived in `eval_expr.mbt` and were
/// extracted to keep that file focused on the core eval pipeline.

///|
fn protobuf_renderer_value_error(
  value : Value,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  match value {
    MappingValue(_) | DefaultedMappingValue(_, _, _) | MapValue(_) =>
      Some(
        "The top-level value of a protobuf file must have type `Typed`, but got type `\{renderer_error_type_name(value, cache)}`.",
      )
    _ => protobuf_nested_value_error(value, cache, class_env, declarations)
  }
}

///|
fn protobuf_nested_value_error(
  value : Value,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  match value {
    DataSizeValue(_, _) =>
      Some(renderer_cannot_render_message("Protobuf", value, cache, false))
    ObjectValue(members) => {
      match find_object_class_tag(members) {
        Some("Dynamic") =>
          return Some(
            renderer_cannot_render_message("Protobuf", value, cache, false),
          )
        Some(class_name) =>
          match
            protobuf_typed_object_members_error(
              members, class_name, cache, class_env, declarations,
            ) {
            Some(message) => return Some(message)
            None => ()
          }
        None => ()
      }
      for field in visible_members(members) {
        match
          protobuf_nested_value_error(
            field.value,
            cache,
            class_env,
            declarations,
          ) {
          Some(message) => return Some(message)
          None => ()
        }
      }
      None
    }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => {
      for element in elements {
        match
          protobuf_nested_value_error(element, cache, class_env, declarations) {
          Some(message) => return Some(message)
          None => ()
        }
      }
      None
    }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      protobuf_mapping_entries_error(entries, cache, class_env, declarations)
    PairValue(first, second) =>
      match protobuf_nested_value_error(first, cache, class_env, declarations) {
        Some(message) => Some(message)
        None =>
          protobuf_nested_value_error(second, cache, class_env, declarations)
      }
    _ => None
  }
}

///|
fn protobuf_mapping_entries_error(
  entries : Array[ValueEntry],
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  for entry in entries {
    if !protobuf_map_key_is_supported(entry.key) {
      return Some(
        "Cannot render map with a non-scalar, floating point or byte array key type.",
      )
    }
    match
      protobuf_nested_value_error(entry.value, cache, class_env, declarations) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  None
}

///|
fn protobuf_map_key_is_supported(value : Value) -> Bool {
  // PKL-153f: a RenderDirective key flattens to its `text` at
  // render time, so the protobuf "scalar key only" rule needs to
  // see through the directive wrapper rather than reject it.
  if render_directive_text(value) is Some(_) {
    return true
  }
  match value {
    StringValue(_) | IntValue(_) | BoolValue(_) => true
    _ => false
  }
}

///|
fn render_value_as_protobuf_fragment_with_context(
  value : Value,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
) -> String {
  // PKL-153f: directive short-circuit — `renderValue(new
  // RenderDirective {...})` returns the text raw before the
  // protobuf-object pipeline kicks in.
  match render_directive_text(value) {
    Some(text) => return text
    None => ()
  }
  match value {
    DurationValue(_, _) => render_value_as_protobuf_fragment(value, indent_text)
    ObjectValue(members) => {
      let buf = StringBuilder::new()
      render_protobuf_object_members(
        members, 0, indent_text, class_env, cache, declarations, buf,
      )
      textproto_trim_trailing_newline(buf.to_string())
    }
    _ => render_value_as_textproto_fragment(value, indent_text)
  }
}

///|
fn render_protobuf_object_members(
  members : Array[ValueMember],
  level : Int,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  buf : StringBuilder,
) -> Unit {
  let class_name = find_object_class_tag(members)
  for field in visible_members(members) {
    let annotation = match class_name {
      Some(name) =>
        protobuf_class_property_type(name, field.name, class_env, declarations)
      None => None
    }
    render_protobuf_field(
      protobuf_member_field_name(field),
      field.value,
      annotation,
      level,
      indent_text,
      class_env,
      cache,
      declarations,
      buf,
    )
  }
}

///|
fn protobuf_class_property_type(
  class_name : String,
  property_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  let properties : Array[ClassProperty] = []
  collect_class_properties_in_order(
    properties, class_name, class_env, declarations,
  )
  for property in properties {
    if property.name == property_name {
      return property.type_name
    }
  }
  None
}

///|
fn render_protobuf_field(
  name : String,
  value : Value,
  type_name : String?,
  level : Int,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  buf : StringBuilder,
) -> Unit {
  if value is NullValue {
    return
  }
  match type_name {
    Some(annotation) =>
      match protobuf_union_choices_for_annotation(annotation, declarations) {
        Some(choices) => {
          render_protobuf_union_field(
            name, value, choices, level, indent_text, class_env, cache, declarations,
            buf,
          )
          return
        }
        None => ()
      }
    None => ()
  }
  match value {
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => {
      let element_type = match type_name {
        Some(annotation) =>
          collection_element_type_from_annotation(annotation, declarations)
        None => None
      }
      for element in elements {
        render_protobuf_collection_element_field(
          name, element, element_type, level, indent_text, class_env, cache, declarations,
          buf,
        )
      }
    }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      render_textproto_entries_as_fields(name, entries, level, indent_text, buf)
    _ =>
      render_protobuf_single_field(
        name, value, level, indent_text, class_env, cache, declarations, buf,
      )
  }
}

///|
fn render_protobuf_collection_element_field(
  name : String,
  value : Value,
  element_type : String?,
  level : Int,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  buf : StringBuilder,
) -> Unit {
  match element_type {
    Some(annotation) =>
      match protobuf_union_choices_for_annotation(annotation, declarations) {
        Some(choices) => {
          render_protobuf_union_field(
            name, value, choices, level, indent_text, class_env, cache, declarations,
            buf,
          )
          return
        }
        None => ()
      }
    None => ()
  }
  render_protobuf_single_field(
    name, value, level, indent_text, class_env, cache, declarations, buf,
  )
}

///|
fn render_protobuf_single_field(
  name : String,
  value : Value,
  level : Int,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
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
        render_protobuf_object_members(
          members,
          level + 1,
          indent_text,
          class_env,
          cache,
          declarations,
          buf,
        )
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
fn render_protobuf_union_field(
  name : String,
  value : Value,
  choices : Array[String],
  level : Int,
  indent_text : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  buf : StringBuilder,
) -> Unit {
  write_textproto_indent(buf, level, indent_text)
  buf.write_string(name)
  buf.write_string(": {\n")
  let label = protobuf_union_label_for_value(
    choices, value, class_env, declarations,
  )
  render_protobuf_single_field(
    "it_" + label,
    value,
    level + 1,
    indent_text,
    class_env,
    cache,
    declarations,
    buf,
  )
  write_textproto_indent(buf, level, indent_text)
  buf.write_string("}\n")
}

///|
fn protobuf_union_label_for_value(
  choices : Array[String],
  value : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String {
  match value {
    StringValue(_) => "String"
    IntValue(_) => "Int"
    FloatValue(_) => "Float"
    BoolValue(_) => "Boolean"
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(runtime_name) =>
          protobuf_union_label_for_object(
            runtime_name, choices, value, class_env, declarations,
          )
        None => "Dynamic"
      }
    _ => eval_value_type_name(value)
  }
}

///|
fn protobuf_union_label_for_object(
  runtime_name : String,
  choices : Array[String],
  value : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String {
  for choice in choices {
    let head = protobuf_type_annotation_head(choice)
    if head == runtime_name {
      return head
    }
  }
  for choice in choices {
    let head = protobuf_type_annotation_head(choice)
    if lookup_class_binding(class_env, head) is Some(_) &&
      value_satisfies_user_class_annotation(head, value, declarations) {
      return head
    }
  }
  runtime_name
}

///|
fn protobuf_union_choices_for_annotation(
  type_name : String,
  declarations : Array[Declaration],
) -> Array[String]? {
  let normalized = protobuf_normalize_type_annotation(type_name, declarations)
  let choices = split_top_level_union_choices(normalized)
  if choices.length() <= 1 {
    return None
  }
  for choice in choices {
    if !protobuf_union_choice_is_stringy(choice, declarations) {
      return Some(choices)
    }
  }
  None
}

///|
fn protobuf_union_choice_is_stringy(
  choice : String,
  declarations : Array[Declaration],
) -> Bool {
  let normalized = protobuf_normalize_type_annotation(choice, declarations)
  let choices = split_top_level_union_choices(normalized)
  if choices.length() > 1 {
    for nested in choices {
      if !protobuf_union_choice_is_stringy(nested, declarations) {
        return false
      }
    }
    return true
  }
  if normalized.length() >= 2 &&
    normalized[0] == '"' &&
    normalized[normalized.length() - 1] == '"' {
    return true
  }
  protobuf_type_annotation_head(normalized) == "String"
}

///|
fn protobuf_normalize_type_annotation(
  type_name : String,
  declarations : Array[Declaration],
) -> String {
  let aliases = eval_type_alias_bindings(declarations)
  let mut normalized = strip_balanced_outer_type_parens(
    eval_resolved_type_alias(
      pkl_strip_default_type_marker(pkl_constraint_trim(type_name)),
      aliases,
    ),
  )
  if normalized.has_prefix("*") {
    normalized = trim_spaces(
      String::unsafe_substring(normalized, start=1, end=normalized.length()),
    )
  }
  if normalized.has_suffix("?") {
    normalized = trim_spaces(
      String::unsafe_substring(normalized, start=0, end=normalized.length() - 1),
    )
    normalized = strip_balanced_outer_type_parens(normalized)
  }
  normalized
}

///|
fn protobuf_typed_object_members_error(
  members : Array[ValueMember],
  class_name : String,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  let properties : Array[ClassProperty] = []
  collect_class_properties_in_order(
    properties, class_name, class_env, declarations,
  )
  for property in properties {
    match lookup_visible_member(members, property.name) {
      Some(value) =>
        match
          protobuf_property_annotation_value_error(
            property.type_name,
            value,
            cache,
            class_env,
            declarations,
          ) {
          Some(message) => return Some(message)
          None => ()
        }
      None =>
        match
          protobuf_type_annotation_default_error(property.type_name, cache) {
          Some(message) => return Some(message)
          None => ()
        }
    }
  }
  None
}

///|
fn protobuf_property_annotation_value_error(
  type_name : String?,
  value : Value,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  let annotation = match type_name {
    Some(t) => t
    None => return None
  }
  match
    protobuf_property_subtype_error(
      annotation, value, cache, class_env, declarations,
    ) {
    Some(message) => return Some(message)
    None => ()
  }
  match mapping_entry_types_from_annotation(annotation, declarations) {
    Some((key_type, _)) =>
      if protobuf_mapping_value_has_entries(value) &&
        !protobuf_mapping_key_type_is_supported(key_type, declarations) {
        Some(
          "Cannot render map with a non-scalar, floating point or byte array key type.",
        )
      } else {
        None
      }
    None => None
  }
}

///|
fn protobuf_property_subtype_error(
  type_name : String,
  value : Value,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  if value is NullValue ||
    protobuf_union_choices_for_annotation(type_name, declarations) is Some(_) {
    return None
  }
  let specified = protobuf_type_annotation_head(type_name)
  if lookup_class_binding(class_env, specified) is None {
    return None
  }
  match value {
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(actual) =>
          if actual != specified &&
            lookup_class_binding(class_env, actual) is Some(_) &&
            value_satisfies_user_class_annotation(
              specified, value, declarations,
            ) {
            Some(
              "Cannot render subtype \{protobuf_qualified_user_type_name(specified, cache, class_env)} of specified type \{protobuf_qualified_user_type_name(actual, cache, class_env)} in protobuf.",
            )
          } else {
            None
          }
        None => None
      }
    _ => None
  }
}

///|
fn protobuf_qualified_user_type_name(
  name : String,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
) -> String {
  if is_stdlib_class_name(name) || lookup_class_binding(class_env, name) is None {
    name
  } else {
    match module_name_from_cache(cache) {
      Some(module_name) => "\{module_name}#\{name}"
      None => name
    }
  }
}

///|
fn protobuf_mapping_value_has_entries(value : Value) -> Bool {
  match value {
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => entries.length() > 0
    _ => false
  }
}

///|
fn protobuf_mapping_key_type_is_supported(
  type_name : String,
  declarations : Array[Declaration],
) -> Bool {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(type_name, aliases)
  let choices = split_top_level_union_choices(resolved)
  if choices.length() > 1 {
    for choice in choices {
      if !protobuf_mapping_key_type_is_supported(choice, declarations) {
        return false
      }
    }
    return true
  }
  let normalized = pkl_strip_default_type_marker(pkl_constraint_trim(resolved))
  if normalized.length() >= 2 &&
    normalized[0] == '"' &&
    normalized[normalized.length() - 1] == '"' {
    return true
  }
  let base = match pkl_constrained_type_base_name(normalized) {
    Some(b) => b
    None => normalized
  }
  let head = match base.find("<") {
    Some(idx) => String::unsafe_substring(base, start=0, end=idx)
    None => base
  }
  match trim_spaces(head) {
    "String"
    | "Int"
    | "Int8"
    | "Int16"
    | "Int32"
    | "UInt"
    | "UInt8"
    | "UInt16"
    | "UInt32"
    | "Boolean" => true
    _ => false
  }
}

///|
fn protobuf_type_annotation_default_error(
  type_name : String?,
  cache : Array[ValueBinding],
) -> String? {
  match type_name {
    Some(raw) => {
      if trim_spaces(raw).has_suffix("?") {
        return None
      }
      let base = protobuf_type_annotation_head(raw)
      if base == "Dynamic" {
        Some(
          renderer_cannot_render_message(
            "Protobuf",
            ObjectValue(tag_object_with_class([], "Dynamic")),
            cache,
            false,
          ),
        )
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn protobuf_type_annotation_head(type_name : String) -> String {
  let trimmed = pkl_constraint_trim(type_name)
  let without_constraint = match pkl_constrained_type_base_name(trimmed) {
    Some(base) => base
    None => trimmed
  }
  let without_nullable = if without_constraint.has_suffix("?") {
    String::unsafe_substring(
      without_constraint,
      start=0,
      end=without_constraint.length() - 1,
    )
  } else {
    without_constraint
  }
  let head = match without_nullable.find("<") {
    Some(idx) => String::unsafe_substring(without_nullable, start=0, end=idx)
    None => without_nullable
  }
  trim_spaces(head)
}
