///|
fn reference_hidden_member_name(name : String) -> String {
  hidden_member_name("__ref_" + name)
}

///|
fn is_reference_value_members(members : Array[ValueMember]) -> Bool {
  object_class_tag_matches(members, "Reference") &&
  lookup_member(members, "__ref_domain") is Some(_)
}

///|
fn reference_hidden_value(
  members : Array[ValueMember],
  name : String,
) -> Value? {
  lookup_member(members, "__ref_" + name)
}

///|
fn reference_referent_type(members : Array[ValueMember]) -> String? {
  match reference_hidden_value(members, "type") {
    Some(StringValue(type_name)) => Some(type_name)
    _ => None
  }
}

///|
fn reference_path_values(members : Array[ValueMember]) -> Array[Value] {
  match reference_hidden_value(members, "path") {
    Some(ListValue(values)) => values
    Some(ListingValue(values)) => values
    _ => []
  }
}

///|
fn reference_value(
  domain : Value,
  referent_type : String,
  data : Value,
  path : Array[Value],
) -> Value {
  ObjectValue(
    tag_object_with_class(
      [
        {
          name: reference_hidden_member_name("domain"),
          value: domain,
          source: None,
          annotations: [],
        },
        {
          name: reference_hidden_member_name("type"),
          value: StringValue(referent_type),
          source: None,
          annotations: [],
        },
        {
          name: reference_hidden_member_name("data"),
          value: data,
          source: None,
          annotations: [],
        },
        {
          name: reference_hidden_member_name("path"),
          value: ListValue(path),
          source: None,
          annotations: [],
        },
      ],
      "ref.Reference",
    ),
  )
}

///|
fn reference_rebind_data(value : Value, data : Value) -> Value {
  match value {
    ObjectValue(members) if is_reference_value_members(members) => {
      let next : Array[ValueMember] = []
      let data_name = reference_hidden_member_name("data")
      for value_member in members {
        if value_member.name == data_name {
          next.push({
            name: value_member.name,
            value: data,
            source: value_member.source,
            annotations: value_member.annotations,
          })
        } else {
          next.push(value_member)
        }
      }
      ObjectValue(next)
    }
    _ => value
  }
}

///|
fn reference_access_value(property : String?, key : Value) -> Value {
  ObjectValue(
    tag_object_with_class(
      [
        {
          name: "isProperty",
          value: BoolValue(property is Some(_)),
          source: None,
          annotations: [],
        },
        {
          name: "isSubscript",
          value: BoolValue(property is None),
          source: None,
          annotations: [],
        },
        {
          name: "property",
          value: match property {
            Some(name) => StringValue(name)
            None => NullValue
          },
          source: None,
          annotations: [],
        },
        { name: "key", value: key, source: None, annotations: [] },
      ],
      "ref.Access",
    ),
  )
}

///|
fn reference_simple_type_name(type_name : String) -> String {
  let base = match pkl_constrained_type_base_name(type_name) {
    Some(name) => name
    None => type_name
  }
  let without_module = match base.find("#") {
    Some(index) =>
      String::unsafe_substring(base, start=index + 1, end=base.length())
    None => base
  }
  match without_module.rev_find(".") {
    Some(index) =>
      String::unsafe_substring(
        without_module,
        start=index + 1,
        end=without_module.length(),
      )
    None => without_module
  }
}

///|
fn reference_annotation_head(type_name : String) -> String {
  let trimmed = pkl_strip_default_type_marker(trim_spaces(type_name))
  let base = match pkl_constrained_type_base_name(trimmed) {
    Some(name) => name
    None => trimmed
  }
  match base.find("<") {
    Some(index) => String::unsafe_substring(base, start=0, end=index)
    None => base
  }
}

///|
fn reference_value_satisfies_annotation(
  type_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> Bool {
  guard value is ObjectValue(members) && is_reference_value_members(members) else {
    return false
  }
  for choice in split_top_level_union_choices(type_name) {
    let head = reference_annotation_head(choice)
    if head == "Reference" ||
      head == "ref.Reference" ||
      head == "Ref" ||
      head.has_suffix("Reference") {
      return true
    }
    for declaration in declarations {
      match declaration {
        TypeAliasDeclaration(alias_decl) if alias_decl.name == head => {
          let target_head = reference_annotation_head(alias_decl.target)
          if target_head == "Reference" || target_head == "ref.Reference" {
            return true
          }
        }
        _ => ()
      }
    }
  }
  false
}

///|
fn reference_normalize_type(
  raw : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  cache : Array[ValueBinding],
) -> String {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(trim_spaces(raw), aliases)
  let unconstrained = match pkl_constrained_type_base_name(resolved) {
    Some(base) => base
    None => resolved
  }
  if unconstrained.has_suffix("?") {
    let inner = String::unsafe_substring(
      unconstrained,
      start=0,
      end=unconstrained.length() - 1,
    )
    let normalized_inner = reference_normalize_type(
      inner, class_env, declarations, cache,
    )
    return if normalized_inner == "String" {
      "Null | String"
    } else {
      normalized_inner + " | Null"
    }
  }
  let choices = split_top_level_union_choices(unconstrained)
  if choices.length() > 1 {
    let normalized : Array[String] = []
    for choice in choices {
      normalized.push(
        reference_normalize_type(choice, class_env, declarations, cache),
      )
    }
    return evaluator_path_join(normalized, " | ")
  }
  match unconstrained.find("<") {
    Some(index) if unconstrained.has_suffix(">") => {
      let head = String::unsafe_substring(unconstrained, start=0, end=index)
      let inner = String::unsafe_substring(
        unconstrained,
        start=index + 1,
        end=unconstrained.length() - 1,
      )
      let args = split_top_level_generic_arguments(inner)
      let normalized : Array[String] = []
      for arg in args {
        normalized.push(
          reference_normalize_type(arg, class_env, declarations, cache),
        )
      }
      return head + "<" + evaluator_path_join(normalized, ", ") + ">"
    }
    _ => ()
  }
  let simple = reference_simple_type_name(unconstrained)
  if is_stdlib_class_name(simple) || is_stdlib_type_alias_name(simple) {
    simple
  } else {
    match lookup_class_binding(class_env, simple) {
      Some(_) =>
        match lookup_value(cache, "@__module_name") {
          Some(StringValue(module_name)) if module_name != "" =>
            module_name + "#" + simple
          _ => simple
        }
      None => unconstrained
    }
  }
}

///|
fn reference_property_referent_type(
  members : Array[ValueMember],
  property_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  cache : Array[ValueBinding],
) -> String {
  let current = match reference_referent_type(members) {
    Some(type_name) => type_name
    None => "Any"
  }
  let simple = reference_simple_type_name(current)
  match
    class_property_type_annotation_from_class_env(
      simple, property_name, class_env,
    ) {
    Some(type_name) =>
      reference_normalize_type(type_name, class_env, declarations, cache)
    None => reference_normalize_type(current, class_env, declarations, cache)
  }
}

///|
fn reference_subscript_referent_type(
  members : Array[ValueMember],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  cache : Array[ValueBinding],
) -> String {
  let current = match reference_referent_type(members) {
    Some(type_name) => type_name
    None => return "Any"
  }
  let normalized = reference_normalize_type(
    current, class_env, declarations, cache,
  )
  for head in ["Mapping", "Map"] {
    match generic_argument_text(normalized, head) {
      Some(inner) => {
        let args = split_top_level_generic_arguments(inner)
        if args.length() == 2 {
          return reference_normalize_type(
            args[1],
            class_env,
            declarations,
            cache,
          )
        }
      }
      None => ()
    }
  }
  for head in ["Listing", "List", "Set", "Collection"] {
    match generic_argument_text(normalized, head) {
      Some(inner) =>
        return reference_normalize_type(inner, class_env, declarations, cache)
      None => ()
    }
  }
  normalized
}

///|
fn reference_append_access(
  members : Array[ValueMember],
  referent_type : String,
  access : Value,
) -> Value? {
  let domain = match reference_hidden_value(members, "domain") {
    Some(value) => value
    None => return None
  }
  let data = match reference_hidden_value(members, "data") {
    Some(value) => value
    None => return None
  }
  let path = reference_path_values(members)
  let next_path : Array[Value] = []
  for item in path {
    next_path.push(item)
  }
  next_path.push(access)
  Some(reference_value(domain, referent_type, data, next_path))
}

///|
fn eval_reference_property_access(
  members : Array[ValueMember],
  property_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  cache : Array[ValueBinding],
) -> Value? {
  if !is_reference_value_members(members) {
    return None
  }
  reference_append_access(
    members,
    reference_property_referent_type(
      members, property_name, class_env, declarations, cache,
    ),
    reference_access_value(Some(property_name), NullValue),
  )
}

///|
fn eval_reference_subscript_access(
  members : Array[ValueMember],
  key : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  cache : Array[ValueBinding],
) -> Value? {
  if !is_reference_value_members(members) {
    return None
  }
  reference_append_access(
    members,
    reference_subscript_referent_type(members, class_env, declarations, cache),
    reference_access_value(None, key),
  )
}

///|
fn reference_values_equal(
  left : Array[ValueMember],
  right : Array[ValueMember],
) -> Bool {
  match
    (
      reference_hidden_value(left, "domain"),
      reference_hidden_value(right, "domain"),
      reference_hidden_value(left, "type"),
      reference_hidden_value(right, "type"),
      reference_hidden_value(left, "data"),
      reference_hidden_value(right, "data"),
      reference_hidden_value(left, "path"),
      reference_hidden_value(right, "path"),
    ) {
    (
      Some(left_domain),
      Some(right_domain),
      Some(left_type),
      Some(right_type),
      Some(left_data),
      Some(right_data),
      Some(left_path),
      Some(right_path),
    ) =>
      values_equal(left_domain, right_domain) &&
      values_equal(left_type, right_type) &&
      values_equal(left_data, right_data) &&
      values_equal(left_path, right_path)
    _ => false
  }
}

///|
fn eval_reference_to_string(
  reference : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let domain_members = match reference_hidden_value(reference, "domain") {
    Some(ObjectValue(members)) => members
    _ => {
      diagnostics.push(diag("Reference domain must be an object"))
      return None
    }
  }
  let domain_class = match find_object_class_tag(domain_members) {
    Some(name) => name
    None => {
      diagnostics.push(diag("Reference domain must extend ref.Domain"))
      return None
    }
  }
  let render_method = match
    lookup_class_method(class_env, domain_class, "renderReference") {
    Some(function_decl) => function_decl
    None => {
      diagnostics.push(diag("Reference domain must implement renderReference"))
      return None
    }
  }
  let body = match render_method.body {
    Some(body) => body
    None => {
      diagnostics.push(diag("Reference domain renderReference has no body"))
      return None
    }
  }
  if render_method.parameters.length() != 1 {
    diagnostics.push(
      diag("Reference domain renderReference expects one parameter"),
    )
    return None
  }
  let method_cache = copy_value_bindings(cache)
  push_receiver_method_bindings(method_cache, domain_members)
  push_super_dispatch_marker(method_cache, domain_class)
  push_sibling_class_methods(method_cache, domain_class, class_env, env, cache)
  method_cache.push({
    name: render_method.parameters[0].name,
    value: ObjectValue(reference),
  })
  eval_expr_with_bindings(
    body, bindings, env, class_env, method_cache, stack, declarations, diagnostics,
    resolve_import,
  )
}

///|
fn render_reference_embedded_value(value : Value, buf : StringBuilder) -> Unit {
  match value {
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(class_name) => render_pcf_class_inline(class_name, members, buf)
        None => render_pcf_inline(value, 0, false, buf)
      }
    _ => render_pcf_inline(value, 0, false, buf)
  }
}

///|
fn render_reference_constructor(
  members : Array[ValueMember],
  buf : StringBuilder,
) -> Bool {
  if !is_reference_value_members(members) {
    return false
  }
  let domain = match reference_hidden_value(members, "domain") {
    Some(value) => value
    None => return false
  }
  let referent_type = match reference_referent_type(members) {
    Some(value) => value
    None => return false
  }
  let data = match reference_hidden_value(members, "data") {
    Some(value) => value
    None => return false
  }
  buf.write_string("Reference(")
  render_reference_embedded_value(domain, buf)
  buf.write_string(", ")
  buf.write_string(referent_type)
  buf.write_string(", ")
  render_reference_embedded_value(data, buf)
  buf.write_char(')')
  for access in reference_path_values(members) {
    match access {
      ObjectValue(access_members) =>
        match lookup_member(access_members, "property") {
          Some(StringValue(name)) => {
            buf.write_char('.')
            buf.write_string(name)
          }
          _ => {
            buf.write_char('[')
            match lookup_member(access_members, "key") {
              Some(key) => render_reference_embedded_value(key, buf)
              None => buf.write_string("null")
            }
            buf.write_char(']')
          }
        }
      _ => ()
    }
  }
  true
}
