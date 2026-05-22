///|
fn collection_default_expr_from_listing_element(expr : Expr) -> Expr? {
  match expr {
    CallExpr(Identifier(name), args) =>
      if name == collection_default_marker_name() && args.length() == 1 {
        Some(args[0])
      } else {
        None
      }
    _ => None
  }
}

///|
fn collection_default_expr_from_mapping_entry(entry : MappingEntry) -> Expr? {
  match entry.key {
    Identifier(name) if name == collection_default_marker_name() =>
      Some(entry.value)
    _ => None
  }
}

///|
fn collection_default_parameters(
  members : Array[ObjectMember],
) -> Array[FunctionParameter]? {
  for object_member in members {
    if is_function_amend_parameter_member_name(object_member.name) {
      match object_member.value {
        LambdaExpr(parameters, _, _) =>
          return Some(copy_function_parameters(parameters))
        _ => ()
      }
    }
  }
  None
}

///|
fn eval_collection_default_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match expr {
    ObjectLiteral(members) =>
      match collection_default_parameters(members) {
        Some(parameters) => {
          let captured = capture_value_bindings(env, cache)
          Some(
            FunctionValue(
              parameters,
              ObjectLiteral(function_amend_regular_members(members)),
              None,
              captured,
              fresh_function_id(),
            ),
          )
        }
        None =>
          eval_expr_with_bindings(
            expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
      }
    _ =>
      eval_expr_with_bindings(
        expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
  }
}

///|
fn eval_collection_default_for_key(
  default_value : Value,
  key : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match default_value {
    FunctionValue(_, _, _, _, _) =>
      apply_function_value(
        "default.apply",
        default_value,
        [key],
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      )
    _ => Some(default_value)
  }
}

///|
fn merge_collection_default_value(
  default_value : Value,
  raw_value : Value,
) -> Value {
  match (default_value, raw_value) {
    (ObjectValue(default_members), ObjectValue(raw_members)) =>
      ObjectValue(
        merge_collection_default_members(default_members, raw_members),
      )
    _ => raw_value
  }
}

///|
fn freeze_collection_default_value(value : Value) -> Value {
  match value {
    ObjectValue(members) => {
      let frozen_members : Array[ValueMember] = []
      for value_member in members {
        frozen_members.push({
          name: value_member.name,
          value: freeze_collection_default_value(value_member.value),
          source: None,
          annotations: value_member.annotations,
        })
      }
      ObjectValue(frozen_members)
    }
    ListingValue(elements) => {
      let frozen : Array[Value] = []
      for element in elements {
        frozen.push(freeze_collection_default_value(element))
      }
      ListingValue(frozen)
    }
    ListValue(elements) => {
      let frozen : Array[Value] = []
      for element in elements {
        frozen.push(freeze_collection_default_value(element))
      }
      ListValue(frozen)
    }
    SetValue(elements) => {
      let frozen : Array[Value] = []
      for element in elements {
        frozen.push(freeze_collection_default_value(element))
      }
      SetValue(frozen)
    }
    MappingValue(entries) => {
      let frozen : Array[ValueEntry] = []
      for entry in entries {
        frozen.push({
          key: freeze_collection_default_value(entry.key),
          value: freeze_collection_default_value(entry.value),
        })
      }
      MappingValue(frozen)
    }
    MapValue(entries) => {
      let frozen : Array[ValueEntry] = []
      for entry in entries {
        frozen.push({
          key: freeze_collection_default_value(entry.key),
          value: freeze_collection_default_value(entry.value),
        })
      }
      MapValue(frozen)
    }
    DefaultedListingValue(raw, materialized, default_value) =>
      DefaultedListingValue(
        raw,
        materialized,
        freeze_collection_default_value(default_value),
      )
    DefaultedMappingValue(raw, materialized, default_value) =>
      DefaultedMappingValue(
        raw,
        materialized,
        freeze_collection_default_value(default_value),
      )
    _ => value
  }
}

///|
fn collection_this_listing_value(
  raw_elements : Array[Value],
  elements : Array[Value],
  default_value : Value?,
) -> Value {
  match default_value {
    Some(default_v) => DefaultedListingValue(raw_elements, elements, default_v)
    None => ListingValue(elements)
  }
}

///|
fn collection_this_mapping_value(
  raw_entries : Array[ValueEntry],
  entries : Array[ValueEntry],
  default_value : Value?,
) -> Value {
  match default_value {
    Some(default_v) => DefaultedMappingValue(raw_entries, entries, default_v)
    None => MappingValue(entries)
  }
}

///|
fn push_collection_binding(
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
  name : String,
  value : Value,
) -> Unit {
  env.push({ name, value })
  cache.push({ name, value })
}

///|
fn push_collection_context_bindings(
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  current : Value,
) -> Unit {
  push_collection_binding(env, cache, "this", current)
  if stack.length() > 0 {
    let inflight_name = stack[stack.length() - 1]
    if lookup_value(env, inflight_name) is None &&
      lookup_value(cache, inflight_name) is None {
      push_collection_binding(env, cache, inflight_name, current)
    }
  }
}

///|
fn module_snapshot_member_error(
  name : String,
  bindings : Array[Binding],
  const_context : Bool,
) -> String? {
  if !const_context {
    return None
  }
  match find_binding(bindings, name) {
    Some(binding) =>
      if !binding.is_const && !(binding.value is LambdaExpr(_, _, _)) {
        Some(
          "Cannot reference property `\{name}` from here because it is not `const`.",
        )
      } else {
        None
      }
    None => None
  }
}

///|
fn push_module_snapshot_member(
  members : Array[ValueMember],
  name : String,
  value : Value,
  bindings : Array[Binding],
  const_context : Bool,
) -> Unit {
  if name == "super" || name == "this" || name.has_prefix("@") {
    return
  }
  members.push({ name, value, source: None, annotations: [] })
  match module_snapshot_member_error(name, bindings, const_context) {
    Some(message) =>
      members.push({
        name: error_member_name(name),
        value: StringValue(message),
        source: None,
        annotations: [],
      })
    None => ()
  }
}

///|
fn module_object_value_from_scope(
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  const_context~ : Bool,
) -> Value {
  let module_members : Array[ValueMember] = []
  // Upper bound: every cache+env binding may flow into the snapshot
  // plus the two metadata members (`imports`, `@__module_path`).
  // Reserve to avoid the growth churn observed in the GC profile —
  // this function ran once per class-default layer.
  module_members.reserve_capacity(cache.length() + env.length() + 2)
  match lookup_value(cache, "@__module_imports") {
    Some(map_value) =>
      module_members.push({
        name: "imports",
        value: map_value,
        source: None,
        annotations: [],
      })
    None => ()
  }
  match lookup_value(cache, "@__module_path") {
    Some(StringValue(path)) =>
      module_members.push({
        name: hidden_member_name(module_metadata_path_name()),
        value: StringValue(path),
        source: None,
        annotations: [],
      })
    _ => ()
  }
  for value_binding in cache {
    push_module_snapshot_member(
      module_members,
      value_binding.name,
      value_binding.value,
      bindings,
      const_context,
    )
  }
  for value_binding in env {
    if find_binding(bindings, value_binding.name) is Some(_) {
      push_module_snapshot_member(
        module_members,
        value_binding.name,
        value_binding.value,
        bindings,
        const_context,
      )
    }
  }
  if stack.length() > 0 {
    let inflight_name = stack[stack.length() - 1]
    match lookup_value(env, inflight_name) {
      Some(value) =>
        push_module_snapshot_member(
          module_members, inflight_name, value, bindings, const_context,
        )
      None => ()
    }
  }
  ObjectValue(module_members)
}

///|
fn adjust_deferred_listing_error_message(
  message : String,
  upper : Int,
) -> String {
  match message.find(" is out of range") {
    Some(idx) if message.has_prefix("Element index `") =>
      String::unsafe_substring(message, start=0, end=idx) +
      " is out of range `0`..`\{upper}`."
    _ => message
  }
}

///|
fn value_or_deferred_diagnostic(
  value : Value,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match first_deferred_error_message(value) {
    Some(message) => {
      diagnostics.push(diag(message))
      None
    }
    None => Some(value)
  }
}

///|
fn resolve_deferred_import_value(
  uri : String,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match resolve_import(uri) {
    Some(EvalOk(value)) => Some(value)
    Some(EvalError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      None
    }
    None => {
      diagnostics.push(diag("Cannot find module `\{uri}`."))
      None
    }
  }
}

///|
fn eval_deferred_import_member_access(
  uri : String,
  member_name : String,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match resolve_deferred_import_value(uri, diagnostics, resolve_import) {
    Some(ObjectValue(members)) =>
      match lookup_visible_member(members, member_name) {
        Some(value) => Some(value)
        None =>
          match lookup_member(members, member_name) {
            Some(FunctionValue(_, _, _, _, _) as exported) => Some(exported)
            _ => {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Dynamic`.",
                ),
              )
              None
            }
          }
      }
    Some(_) => {
      diagnostics.push(diag("member access expects Object"))
      None
    }
    None => None
  }
}

///|
fn output_projection_value(
  owner_members : Array[ValueMember],
  output_members : Array[ValueMember],
) -> Value {
  match lookup_member(output_members, "value") {
    Some(value) => value
    None => {
      let projected : Array[ValueMember] = []
      for field in owner_members {
        if field.name != "output" {
          projected.push(field)
        }
      }
      ObjectValue(projected)
    }
  }
}

///|
fn render_output_text_for_renderer(
  value : Value,
  renderer_value : Value?,
) -> String {
  let format = match renderer_value {
    Some(ObjectValue(renderer_members)) =>
      renderer_format_from_members(renderer_members)
    _ => None
  }
  match format {
    Some("json") => render_value_as_json(value)
    Some("yaml") => render_value_as_yaml(value)
    Some("properties") => render_value_as_properties(value)
    Some("plist") => render_value_as_plist(value)
    Some("textproto") => render_value_as_textproto(value)
    Some("xml") => render_value_as_xml(value)
    _ => render_value(value)
  }
}

///|
fn synthesize_output_text_member(
  owner_members : Array[ValueMember],
  output_members : Array[ValueMember],
) -> Value {
  if lookup_member(output_members, "text") is Some(_) {
    return ObjectValue(output_members)
  }
  let projected = output_projection_value(owner_members, output_members)
  let text = render_output_text_for_renderer(
    projected,
    lookup_member(output_members, "renderer"),
  )
  let result : Array[ValueMember] = []
  for field in output_members {
    result.push(field)
  }
  result.push({
    name: "text",
    value: StringValue(text),
    source: None,
    annotations: [],
  })
  ObjectValue(result)
}

///|
fn output_super_text_suffix(expr : Expr) -> String? {
  match expr {
    MemberAccess(Identifier("super"), "text") => Some("")
    BinaryExpr(Add, left, StringLiteral(right)) =>
      match output_super_text_suffix(left) {
        Some(prefix) => Some(prefix + right)
        None => None
      }
    _ => None
  }
}

///|
fn output_renderer_omit_null_properties(
  output_members : Array[ValueMember],
) -> Bool {
  match lookup_member(output_members, "renderer") {
    Some(ObjectValue(renderer_members)) =>
      match lookup_member(renderer_members, "omitNullProperties") {
        Some(BoolValue(value)) => value
        _ => false
      }
    _ => false
  }
}

///|
fn strip_null_object_properties_for_output(value : Value) -> Value {
  match value {
    ObjectValue(members) => {
      let kept : Array[ValueMember] = []
      for field in members {
        if field.value is NullValue {
          continue
        }
        kept.push({
          name: field.name,
          value: strip_null_object_properties_for_output(field.value),
          source: field.source,
          annotations: field.annotations,
        })
      }
      ObjectValue(kept)
    }
    ListingValue(elements) => {
      let mapped : Array[Value] = []
      for element in elements {
        mapped.push(strip_null_object_properties_for_output(element))
      }
      ListingValue(mapped)
    }
    DefaultedListingValue(raw, elements, default_value) => {
      let mapped_raw : Array[Value] = []
      for element in raw {
        mapped_raw.push(strip_null_object_properties_for_output(element))
      }
      let mapped : Array[Value] = []
      for element in elements {
        mapped.push(strip_null_object_properties_for_output(element))
      }
      DefaultedListingValue(
        mapped_raw,
        mapped,
        strip_null_object_properties_for_output(default_value),
      )
    }
    MappingValue(entries) => {
      let mapped : Array[ValueEntry] = []
      for entry in entries {
        mapped.push({
          key: entry.key,
          value: strip_null_object_properties_for_output(entry.value),
        })
      }
      MappingValue(mapped)
    }
    MapValue(entries) => {
      let mapped : Array[ValueEntry] = []
      for entry in entries {
        mapped.push({
          key: entry.key,
          value: strip_null_object_properties_for_output(entry.value),
        })
      }
      MapValue(mapped)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let mapped_raw : Array[ValueEntry] = []
      for entry in raw {
        mapped_raw.push({
          key: entry.key,
          value: strip_null_object_properties_for_output(entry.value),
        })
      }
      let mapped : Array[ValueEntry] = []
      for entry in entries {
        mapped.push({
          key: entry.key,
          value: strip_null_object_properties_for_output(entry.value),
        })
      }
      DefaultedMappingValue(
        mapped_raw,
        mapped,
        strip_null_object_properties_for_output(default_value),
      )
    }
    _ => value
  }
}

///|
fn finalize_output_super_text(value : Value) -> Value {
  match value {
    ObjectValue(members) => {
      let finalized : Array[ValueMember] = []
      for field in members {
        if field.name == "output" {
          match field.value {
            ObjectValue(output_members) => {
              let rewritten_output : Array[ValueMember] = []
              let mut rewritten = false
              for output_member in output_members {
                if output_member.name == "text" {
                  match output_member.source {
                    Some(source) =>
                      match output_super_text_suffix(source) {
                        Some(suffix) => {
                          let projected_value = output_projection_value(
                            members, output_members,
                          )
                          let projected = if output_renderer_omit_null_properties(
                              output_members,
                            ) {
                            strip_null_object_properties_for_output(
                              projected_value,
                            )
                          } else {
                            projected_value
                          }
                          let base_text = render_output_text_for_renderer(
                            projected,
                            lookup_member(output_members, "renderer"),
                          )
                          let normalized_base = if base_text.length() > 0 &&
                            !base_text.has_suffix("\n") {
                            base_text + "\n"
                          } else {
                            base_text
                          }
                          let text = normalized_base + suffix
                          rewritten_output.push({
                            name: output_member.name,
                            value: StringValue(text),
                            source: output_member.source,
                            annotations: output_member.annotations,
                          })
                          rewritten = true
                        }
                        None => rewritten_output.push(output_member)
                      }
                    None => rewritten_output.push(output_member)
                  }
                } else {
                  rewritten_output.push(output_member)
                }
              }
              if rewritten {
                finalized.push({
                  name: field.name,
                  value: ObjectValue(rewritten_output),
                  source: field.source,
                  annotations: field.annotations,
                })
              } else {
                finalized.push(field)
              }
            }
            _ => finalized.push(field)
          }
        } else {
          finalized.push(field)
        }
      }
      ObjectValue(finalized)
    }
    _ => value
  }
}

///|
fn value_or_top_level_deferred_diagnostic(
  value : Value,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match deferred_error_message(value) {
    Some(message) => {
      diagnostics.push(diag(message))
      None
    }
    None => Some(value)
  }
}

///|
fn null_default_expr_for_amend(
  base_expr : Expr,
  bindings : Array[Binding],
) -> Expr? {
  match base_expr {
    CallExpr(Identifier("Null"), args) =>
      if args.length() == 1 {
        Some(args[0])
      } else {
        None
      }
    Identifier(name) =>
      match find_binding(bindings, name) {
        Some(binding) =>
          match binding.value {
            CallExpr(Identifier("Null"), args) =>
              if args.length() == 1 {
                Some(args[0])
              } else {
                None
              }
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn merge_collection_default_members(
  default_members : Array[ValueMember],
  raw_members : Array[ValueMember],
) -> Array[ValueMember] {
  let merged : Array[ValueMember] = []
  for raw_member in raw_members {
    let exact = find_value_member_exact(default_members, raw_member.name)
    let resolved = if exact is Some(_) {
      exact
    } else {
      let hidden_alias = hidden_member_name(raw_member.name)
      find_value_member_exact(default_members, hidden_alias)
    }
    match resolved {
      Some(default_member) =>
        merged.push({
          name: raw_member.name,
          value: deep_merge_amend_member_value(
            default_member.value,
            raw_member.value,
            raw_member.source,
          ),
          source: raw_member.source,
          annotations: append_annotations(
            default_member.annotations,
            raw_member.annotations,
          ),
        })
      None => merged.push(raw_member)
    }
  }
  for default_member in default_members {
    if find_member_exact(raw_members, default_member.name) is Some(_) {
      continue
    }
    let bare_match = if is_hidden_member_name(default_member.name) {
      let bare = String::unsafe_substring(
        default_member.name,
        start=hidden_member_prefix.length(),
        end=default_member.name.length(),
      )
      find_member_exact(raw_members, bare) is Some(_)
    } else {
      false
    }
    if !bare_match {
      merged.push(default_member)
    }
  }
  normalize_name_age_member_order(merged)
}

///|
fn collection_literal_expr_for_type_annotation(
  expr : Expr,
  type_name : String?,
) -> Expr {
  let raw_type = match type_name {
    Some(t) => trim_spaces(t)
    None => return expr
  }
  let base_type = match pkl_constrained_type_base_name(raw_type) {
    Some(base) => base
    None => raw_type
  }
  if base_type == "Listing" ||
    base_type == "List" ||
    generic_argument_text(base_type, "Listing") is Some(_) ||
    generic_argument_text(base_type, "List") is Some(_) {
    match object_literal_to_listing_literal(expr) {
      Some(listing_expr) => return listing_expr
      None => return expr
    }
  }
  if base_type == "Mapping" ||
    generic_argument_text(base_type, "Mapping") is Some(_) {
    match object_literal_to_mapping_literal(expr) {
      Some(mapping_expr) => return mapping_expr
      None => return expr
    }
  }
  expr
}

///|
fn collection_local_binding_from_expr(expr : Expr) -> Binding? {
  match expr {
    CallExpr(Identifier(name), args) =>
      if name == collection_local_binding_marker_name() && args.length() == 3 {
        match args[0] {
          StringLiteral(binding_name) => {
            let type_name = match args[1] {
              StringLiteral(t) => Some(t)
              NullLiteral => None
              _ => None
            }
            Some({
              name: binding_name,
              type_name,
              value: args[2],
              exported: true,
              is_const: true,
              annotations: [],
              abstract_slot: true,
            })
          }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn bindings_with_listing_locals(
  elements : Array[Expr],
  bindings : Array[Binding],
) -> Array[Binding] {
  let out : Array[Binding] = []
  for binding in bindings {
    out.push(binding)
  }
  for element in elements {
    match collection_local_binding_from_expr(element) {
      Some(binding) => out.push(binding)
      None => ()
    }
  }
  out
}

///|
fn bindings_with_mapping_locals(
  entries : Array[MappingEntry],
  bindings : Array[Binding],
) -> Array[Binding] {
  let out : Array[Binding] = []
  for binding in bindings {
    out.push(binding)
  }
  for entry in entries {
    match collection_local_binding_from_expr(entry.key) {
      Some(binding) => out.push(binding)
      None => ()
    }
  }
  out
}

///|
fn object_literal_to_listing_literal(expr : Expr) -> Expr? {
  match expr {
    ObjectLiteral(members) => {
      let elements : Array[Expr] = []
      for object_member in members {
        let bare_name = strip_member_visibility_prefix(object_member.name)
        if bare_name == "default" {
          elements.push(
            CallExpr(Identifier(collection_default_marker_name()), [
              object_member.value,
            ]),
          )
        } else if object_member.name.has_prefix("@element$") {
          elements.push(object_member.value)
        } else if object_member.name == "@when" {
          elements.push(
            WhenSpread(
              rewrite_collection_when_branch(object_member.value, listing=true),
            ),
          )
        } else if object_member.name == "@for" {
          elements.push(WhenSpread(object_member.value))
        } else if object_member.name == "@spread" {
          elements.push(WhenSpread(object_member.value))
        } else {
          return None
        }
      }
      Some(ListingLiteral(elements))
    }
    _ => None
  }
}

///|
fn object_literal_to_mapping_literal(expr : Expr) -> Expr? {
  match expr {
    ObjectLiteral(members) => {
      let entries : Array[MappingEntry] = []
      for object_member in members {
        let bare_name = strip_member_visibility_prefix(object_member.name)
        if bare_name == "default" {
          entries.push({
            key: Identifier(collection_default_marker_name()),
            value: object_member.value,
          })
        } else if object_member.name.has_prefix("@subscript$") {
          match object_member.value {
            CallExpr(Identifier("@__index_entry"), args) =>
              if args.length() == 2 {
                entries.push({ key: args[0], value: args[1] })
              } else {
                return None
              }
            _ => return None
          }
        } else if object_member.name == "@when" {
          entries.push({
            key: WhenSpread(
              rewrite_collection_when_branch(object_member.value, listing=false),
            ),
            value: NullLiteral,
          })
        } else if object_member.name == "@for" {
          entries.push({
            key: WhenSpread(object_member.value),
            value: NullLiteral,
          })
        } else if object_member.name == "@spread" {
          entries.push({
            key: WhenSpread(object_member.value),
            value: NullLiteral,
          })
        } else {
          return None
        }
      }
      Some(MappingLiteral(entries))
    }
    _ => None
  }
}

///|
fn rewrite_collection_when_branch(expr : Expr, listing~ : Bool) -> Expr {
  match expr {
    ConditionalExpr(condition, then_expr, else_expr) =>
      ConditionalExpr(
        condition,
        rewrite_collection_literal_branch(then_expr, listing~),
        rewrite_collection_literal_branch(else_expr, listing~),
      )
    _ => expr
  }
}

///|
fn rewrite_collection_literal_branch(expr : Expr, listing~ : Bool) -> Expr {
  if listing {
    match object_literal_to_listing_literal(expr) {
      Some(listing_expr) => listing_expr
      None => expr
    }
  } else {
    match object_literal_to_mapping_literal(expr) {
      Some(mapping_expr) => mapping_expr
      None => expr
    }
  }
}

///|
fn eval_collection_body_expr(
  expr : Expr,
  key : Value,
  default_value : Value?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> (Value, Value)? {
  match (expr, default_value) {
    (ObjectLiteral(members), Some(default_source)) =>
      match
        eval_collection_default_for_key(
          default_source, key, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        ) {
        Some(default_for_key_raw) => {
          let default_for_key = freeze_collection_default_value(
            default_for_key_raw,
          )
          let local_env = copy_value_bindings(env)
          local_env.push({ name: "super", value: default_for_key })
          let local_cache = copy_value_bindings(cache)
          local_cache.push({ name: "super", value: default_for_key })
          let raw = ObjectValue(
            eval_object_members(
              members, bindings, local_env, class_env, local_cache, stack, declarations,
              diagnostics, resolve_import,
            ),
          )
          Some((raw, merge_collection_default_value(default_for_key, raw)))
        }
        None => None
      }
    _ =>
      match
        eval_expr_with_bindings(
          expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) => Some((value, value))
        None => None
      }
  }
}

///|
fn materialize_listing_raw_elements(
  raw_elements : Array[Value],
  default_value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[Value]? {
  let out : Array[Value] = []
  for i = 0; i < raw_elements.length(); i = i + 1 {
    match
      eval_collection_default_for_key(
        default_value,
        IntValue(i.to_int64()),
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(default_for_key_raw) => {
        let default_for_key = freeze_collection_default_value(
          default_for_key_raw,
        )
        out.push(
          merge_collection_default_value(default_for_key, raw_elements[i]),
        )
      }
      None => return None
    }
  }
  Some(out)
}

///|
fn collection_element_type_from_annotation(
  type_name : String,
  declarations : Array[Declaration],
) -> String? {
  let aliases = eval_type_alias_bindings(declarations)
  let source = strip_lazy_collection_annotation_marker(type_name)
  let resolved = eval_resolved_type_alias(source, aliases)
  let normalized = {
    let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(resolved))
    if trimmed.has_suffix("?") {
      String::unsafe_substring(trimmed, start=0, end=trimmed.length() - 1)
    } else {
      trimmed
    }
  }
  let base = match pkl_constrained_type_base_name(normalized) {
    Some(b) => b
    None => normalized
  }
  for prefix in ["Listing", "List", "Set", "Collection"] {
    match generic_argument_text(base, prefix) {
      Some(element_type) => return Some(element_type)
      None => ()
    }
  }
  None
}

///|
fn lazy_collection_annotation_marker_prefix() -> String {
  "@__lazy_collection:"
}

///|
fn mark_lazy_collection_annotation(type_name : String) -> String {
  lazy_collection_annotation_marker_prefix() + type_name
}

///|
fn strip_lazy_collection_annotation_marker(type_name : String) -> String {
  let prefix = lazy_collection_annotation_marker_prefix()
  if type_name.has_prefix(prefix) {
    String::unsafe_substring(
      type_name,
      start=prefix.length(),
      end=type_name.length(),
    )
  } else {
    type_name
  }
}

///|
fn strip_lazy_collection_annotation_marker_opt(type_name : String?) -> String? {
  match type_name {
    Some(name) => Some(strip_lazy_collection_annotation_marker(name))
    None => None
  }
}

///|
fn is_lazy_collection_annotation(type_name : String) -> Bool {
  type_name.has_prefix(lazy_collection_annotation_marker_prefix())
}

///|
fn apply_typed_listing_elements(
  element_type : String,
  elements : Array[Value],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Array[Value] {
  let out : Array[Value] = []
  for element in elements {
    out.push(
      apply_typed_collection_element_annotation(
        element_type, element, bindings, env, class_env, cache, stack, declarations,
        resolve_import,
      ),
    )
  }
  out
}

///|
fn apply_typed_collection_element_annotation(
  type_name : String,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let coerced = coerce_value_to_annotated_type(value, Some(type_name))
  if deferred_error_message(coerced) is Some(_) {
    return coerced
  }
  match
    cast_value_to_type_annotation(
      type_name, coerced, bindings, env, class_env, cache, stack, declarations, resolve_import,
    ) {
    TypeCastOk(casted) => casted
    TypeCastErr(message) => deferred_error_value(message)
  }
}

///|
fn apply_typed_set_element_annotation(
  type_name : String,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  if type_annotation_has_collection_union(type_name, declarations) {
    match value {
      ListingValue(_)
      | DefaultedListingValue(_, _, _)
      | MappingValue(_)
      | DefaultedMappingValue(_, _, _) =>
        return deferred_error_value(
          as_cast_collection_union_mismatch_message(type_name, value),
        )
      _ => ()
    }
  }
  apply_typed_collection_element_annotation(
    type_name, value, bindings, env, class_env, cache, stack, declarations, resolve_import,
  )
}

///|
fn value_has_deferred_error(value : Value) -> Bool {
  first_deferred_error_message(value) is Some(_)
}

///|
fn first_deferred_error_message(value : Value) -> String? {
  match deferred_error_message(value) {
    Some(message) => return Some(message)
    None => ()
  }
  match value {
    ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
      for element in elements {
        match first_deferred_error_message(element) {
          Some(message) => return Some(message)
          None => ()
        }
      } nobreak {
        None
      }
    DefaultedListingValue(raw, elements, _) => {
      for element in raw {
        match first_deferred_error_message(element) {
          Some(message) => return Some(message)
          None => ()
        }
      }
      for element in elements {
        match first_deferred_error_message(element) {
          Some(message) => return Some(message)
          None => ()
        }
      } nobreak {
        None
      }
    }
    MappingValue(entries) | MapValue(entries) =>
      first_deferred_error_message_in_entries(entries)
    DefaultedMappingValue(raw, entries, _) =>
      match first_deferred_error_message_in_entries(raw) {
        Some(message) => Some(message)
        None => first_deferred_error_message_in_entries(entries)
      }
    PairValue(first, second) =>
      match first_deferred_error_message(first) {
        Some(message) => Some(message)
        None => first_deferred_error_message(second)
      }
    ObjectValue(members) =>
      for field in members {
        if is_error_member_name(field.name) {
          match field.value {
            StringValue(message) => return Some(message)
            _ => ()
          }
        }
      } nobreak {
        None
      }
    _ => None
  }
}

///|
fn first_deferred_error_message_in_entries(
  entries : Array[ValueEntry],
) -> String? {
  for entry in entries {
    match first_deferred_error_message(entry.key) {
      Some(message) => return Some(message)
      None => ()
    }
    match first_deferred_error_message(entry.value) {
      Some(message) => return Some(message)
      None => ()
    }
  } nobreak {
    None
  }
}

///|
fn first_top_level_deferred_error_message(values : Array[Value]) -> String? {
  for value in values {
    match deferred_error_message(value) {
      Some(message) => return Some(message)
      None => ()
    }
  } nobreak {
    None
  }
}

///|
fn mapping_entry_types_from_annotation(
  type_name : String,
  declarations : Array[Declaration],
) -> (String, String)? {
  let aliases = eval_type_alias_bindings(declarations)
  let source = strip_lazy_collection_annotation_marker(type_name)
  let resolved = eval_resolved_type_alias(source, aliases)
  let normalized = {
    let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(resolved))
    if trimmed.has_suffix("?") {
      String::unsafe_substring(trimmed, start=0, end=trimmed.length() - 1)
    } else {
      trimmed
    }
  }
  let base = match pkl_constrained_type_base_name(normalized) {
    Some(b) => b
    None => normalized
  }
  let inner = match generic_argument_text(base, "Mapping") {
    Some(text) => text
    None =>
      match generic_argument_text(base, "Map") {
        Some(text) => text
        None => return None
      }
  }
  let parts = split_top_level_generic_arguments(inner)
  if parts.length() == 2 {
    Some((parts[0], parts[1]))
  } else {
    None
  }
}

///|
fn apply_typed_collection_entries(
  key_type : String,
  value_type : String,
  entries : Array[ValueEntry],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueEntry] {
  let out : Array[ValueEntry] = []
  for entry in entries {
    out.push({
      key: apply_typed_collection_element_annotation(
        key_type,
        entry.key,
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        resolve_import,
      ),
      value: apply_typed_collection_element_annotation(
        value_type,
        entry.value,
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        resolve_import,
      ),
    })
  }
  out
}

///|
fn first_top_level_deferred_entry_key_message(
  entries : Array[ValueEntry],
) -> String? {
  for entry in entries {
    match first_deferred_error_message(entry.key) {
      Some(message) => return Some(message)
      None => ()
    }
  } nobreak {
    None
  }
}

///|
fn first_top_level_deferred_entry_value_message(
  entries : Array[ValueEntry],
) -> String? {
  for entry in entries {
    match deferred_error_message(entry.value) {
      Some(message) => return Some(message)
      None => ()
    }
  } nobreak {
    None
  }
}

///|
fn listing_union_branch_accepts_elements(
  element_type : String,
  elements : Array[Value],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Bool {
  for element in elements {
    let applied = apply_typed_collection_element_annotation(
      element_type, element, bindings, env, class_env, cache, stack, declarations,
      resolve_import,
    )
    if value_has_deferred_error(applied) {
      return false
    }
  } nobreak {
    true
  }
}

///|
fn render_listing_union_rejection_value(elements : Array[Value]) -> String {
  if elements.length() == 0 {
    return "new Listing {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Listing { ")
  let mut masked_tail = false
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    if masked_tail {
      buf.write_string("?")
    } else if deferred_error_message(elements[i]) is None {
      buf.write_string(render_pcf_value_inline(elements[i]))
    } else {
      buf.write_string("?")
      masked_tail = true
    }
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn normalize_type_name_commas(type_name : String) -> String {
  let buf = StringBuilder::new()
  let mut skip_spaces_after_comma = false
  for ch in type_name {
    if skip_spaces_after_comma && ch == ' ' {
      continue
    }
    if ch == ',' {
      buf.write_string(", ")
      skip_spaces_after_comma = true
    } else {
      buf.write_char(ch)
      skip_spaces_after_comma = false
    }
  }
  buf.to_string()
}

///|
fn pretty_listing_union_type_name(type_name : String) -> String {
  normalize_type_name_commas(
    strip_balanced_outer_type_parens(pkl_constraint_trim(type_name)),
  ).replace(old="length==", new="length == ")
}

///|
fn listing_union_annotation_rejection_message(
  type_name : String,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  let choices = split_top_level_union_choices(type_name)
  if choices.length() <= 1 {
    return None
  }
  let elements = match value {
    ListingValue(xs)
    | DefaultedListingValue(_, xs, _)
    | ListValue(xs)
    | SetValue(xs) => xs
    _ => return None
  }
  let mut saw_collection_branch = false
  for choice in choices {
    let branch = pkl_strip_default_type_marker(pkl_constraint_trim(choice))
    match collection_element_type_from_annotation(branch, declarations) {
      Some(element_type) => {
        saw_collection_branch = true
        if listing_union_branch_accepts_elements(
            element_type, elements, bindings, env, class_env, cache, stack, declarations,
            resolve_import,
          ) {
          return None
        }
      }
      None => ()
    }
  }
  if !saw_collection_branch {
    return None
  }
  Some(
    "Expected value of type `\{pretty_listing_union_type_name(type_name)}`, but got a different `Listing`. Value: \{render_listing_union_rejection_value(elements)}",
  )
}

///|
fn append_listing_spread_value(
  value : Value,
  raw_values : Array[Value],
  values : Array[Value],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match deferred_error_message(value) {
    Some(message) => {
      diagnostics.push(diag(message))
      return false
    }
    None => ()
  }
  let append_elements = fn(elements : Array[Value]) -> Unit {
    for v in elements {
      raw_values.push(v)
      values.push(v)
    }
  }
  match value {
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => {
      append_elements(elements)
      true
    }
    IntSeqValue(start_v, end_v, step_v) => {
      append_elements(intseq_materialize(start_v, end_v, step_v))
      true
    }
    BytesValue(bytes) => {
      append_elements(bytes_materialize(bytes))
      true
    }
    ObjectValue(object_members) => {
      for value_member in object_members {
        if is_invisible_member_name(value_member.name) {
          continue
        }
        if value_member.name.has_prefix("@element$") {
          raw_values.push(value_member.value)
          values.push(value_member.value)
        } else if value_member.name.has_prefix("@subscript$") {
          diagnostics.push(
            diag(
              "Cannot spread object containing entries into object of type `Listing`.",
            ),
          )
          return false
        } else {
          diagnostics.push(
            diag(
              "Cannot spread object containing properties into object of type `Listing`.",
            ),
          )
          return false
        }
      }
      true
    }
    MappingValue(_) | DefaultedMappingValue(_, _, _) => {
      diagnostics.push(
        diag(
          "Cannot spread object containing entries into object of type `Listing`.",
        ),
      )
      false
    }
    NullValue => true
    _ => {
      diagnostics.push(
        diag(
          "Cannot spread value of type `\{eval_value_type_name(value)}` into object of type `Listing`. Value: \{render_pcf_value_inline(value)}",
        ),
      )
      false
    }
  }
}

///|
fn append_mapping_spread_entry(
  entry : ValueEntry,
  raw_values : Array[ValueEntry],
  values : Array[ValueEntry],
  diagnostics : Array[Diagnostic],
) -> Bool {
  for existing in values {
    if existing.key == entry.key {
      diagnostics.push(
        diag(
          "Cannot spread object because the enclosing object already has a declaration of entry key `\{render_pcf_value_inline(entry.key)}`.",
        ),
      )
      return false
    }
  }
  raw_values.push(entry)
  values.push(entry)
  true
}

///|
fn append_mapping_spread_value(
  value : Value,
  raw_values : Array[ValueEntry],
  values : Array[ValueEntry],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match deferred_error_message(value) {
    Some(message) => {
      diagnostics.push(diag(message))
      return false
    }
    None => ()
  }
  match value {
    MappingValue(entries) | MapValue(entries) => {
      for entry in entries {
        if !append_mapping_spread_entry(entry, raw_values, values, diagnostics) {
          return false
        }
      }
      true
    }
    DefaultedMappingValue(raw_entries, entries, _) => {
      for i = 0; i < entries.length(); i = i + 1 {
        for existing in values {
          if existing.key == entries[i].key {
            diagnostics.push(
              diag(
                "Cannot spread object because the enclosing object already has a declaration of entry key `\{render_pcf_value_inline(entries[i].key)}`.",
              ),
            )
            return false
          }
        }
        if i < raw_entries.length() {
          raw_values.push(raw_entries[i])
        } else {
          raw_values.push(entries[i])
        }
        values.push(entries[i])
      }
      true
    }
    ObjectValue(object_members) => {
      for value_member in object_members {
        if is_invisible_member_name(value_member.name) {
          continue
        }
        if !value_member.name.has_prefix("@element$") &&
          !value_member.name.has_prefix("@subscript$") {
          diagnostics.push(
            diag(
              "Cannot spread object containing properties into object of type `Mapping`.",
            ),
          )
          return false
        }
      }
      for value_member in object_members {
        if is_invisible_member_name(value_member.name) {
          continue
        }
        if value_member.name.has_prefix("@element$") {
          diagnostics.push(
            diag(
              "Cannot spread object containing elements into object of type `Mapping`.",
            ),
          )
          return false
        }
      }
      for value_member in object_members {
        if is_invisible_member_name(value_member.name) ||
          !value_member.name.has_prefix("@subscript$") {
          continue
        }
        match value_member.value {
          ObjectValue(pair_members) =>
            match
              (
                lookup_member(pair_members, "@key"),
                lookup_member(pair_members, "@value"),
              ) {
              (Some(key), Some(value)) =>
                if !append_mapping_spread_entry(
                    { key, value },
                    raw_values,
                    values,
                    diagnostics,
                  ) {
                  return false
                }
              _ => ()
            }
          _ => ()
        }
      }
      true
    }
    ListingValue(_) | DefaultedListingValue(_, _, _) => {
      diagnostics.push(
        diag(
          "Cannot spread object containing elements into object of type `Mapping`.",
        ),
      )
      false
    }
    NullValue => true
    _ => {
      let rendered = match value {
        BytesValue(bytes) => render_bytes_value_inline(bytes)
        _ => render_pcf_value_inline(value)
      }
      diagnostics.push(
        diag(
          "Cannot spread value of type `\{eval_value_type_name(value)}` into object of type `Mapping`. Value: \{rendered}",
        ),
      )
      false
    }
  }
}

///|
fn apply_mixin_pipe_value(
  left_value : Value,
  mixin_members : Array[ValueMember],
  diagnostics : Array[Diagnostic],
) -> Value? {
  let mixin_value = ObjectValue(mixin_members)
  match left_value {
    ListingValue(elements) | ListValue(elements) | SetValue(elements) => {
      let raw : Array[Value] = []
      let values : Array[Value] = []
      for element in elements {
        raw.push(element)
        values.push(element)
      }
      if append_listing_spread_value(mixin_value, raw, values, diagnostics) {
        Some(ListingValue(values))
      } else {
        None
      }
    }
    DefaultedListingValue(raw_elements, elements, default_value) => {
      let raw : Array[Value] = []
      let values : Array[Value] = []
      for element in raw_elements {
        raw.push(element)
      }
      for element in elements {
        values.push(element)
      }
      if append_listing_spread_value(mixin_value, raw, values, diagnostics) {
        Some(DefaultedListingValue(raw, values, default_value))
      } else {
        None
      }
    }
    MappingValue(entries) | MapValue(entries) => {
      let raw : Array[ValueEntry] = []
      let values : Array[ValueEntry] = []
      for entry in entries {
        raw.push(entry)
        values.push(entry)
      }
      if append_mapping_spread_value(mixin_value, raw, values, diagnostics) {
        Some(MappingValue(values))
      } else {
        None
      }
    }
    DefaultedMappingValue(raw_entries, entries, default_value) => {
      let raw : Array[ValueEntry] = []
      let values : Array[ValueEntry] = []
      for entry in raw_entries {
        raw.push(entry)
      }
      for entry in entries {
        values.push(entry)
      }
      if append_mapping_spread_value(mixin_value, raw, values, diagnostics) {
        Some(DefaultedMappingValue(raw, values, default_value))
      } else {
        None
      }
    }
    ObjectValue(members) => {
      let merged : Array[ValueMember] = []
      for value_member in members {
        merged.push(value_member)
      }
      let mut ok = true
      for value_member in mixin_members {
        if !is_invisible_member_name(value_member.name) && ok {
          ok = push_mixin_object_member(merged, value_member, diagnostics)
        }
      }
      if ok {
        Some(ObjectValue(merged))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn object_members_are_mixin_body(members : Array[ValueMember]) -> Bool {
  let mut has_visible = false
  for value_member in members {
    if is_invisible_member_name(value_member.name) {
      continue
    }
    has_visible = true
    if !value_member.name.has_prefix("@element$") &&
      !value_member.name.has_prefix("@subscript$") {
      return false
    }
  }
  has_visible
}

///|
fn render_bytes_value_inline(bytes : Bytes) -> String {
  let buf = StringBuilder::new()
  buf.write_string("Bytes(")
  for i = 0; i < bytes.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(bytes[i].to_int().to_string())
  }
  buf.write_char(')')
  buf.to_string()
}

///|
fn concat_bytes(left : Bytes, right : Bytes) -> Bytes {
  let out : Array[Byte] = []
  for i = 0; i < left.length(); i = i + 1 {
    out.push(left[i])
  }
  for i = 0; i < right.length(); i = i + 1 {
    out.push(right[i])
  }
  Bytes::from_array(out)
}

///|
fn undefined_operator_for_operand_types_message(
  op : BinaryOp,
  left : Value,
  right : Value,
) -> String {
  "Operator `\{operator_name(op)}` is not defined for operand types `\{eval_value_type_name(left)}` and `\{eval_value_type_name(right)}`. Left operand : \{render_pcf_value_inline(left)} Right operand: \{render_pcf_value_inline(right)}"
}

///|
fn apply_typed_listing_annotation(
  type_name : String,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match
    listing_union_annotation_rejection_message(
      type_name, value, bindings, env, class_env, cache, stack, declarations, resolve_import,
    ) {
    Some(message) => return deferred_error_value(message)
    None => ()
  }
  match collection_element_type_from_annotation(type_name, declarations) {
    Some(element_type) =>
      match value {
        ListingValue(elements) =>
          ListingValue(
            apply_typed_listing_elements(
              element_type, elements, bindings, env, class_env, cache, stack, declarations,
              resolve_import,
            ),
          )
        DefaultedListingValue(raw, elements, default_value) =>
          DefaultedListingValue(
            apply_typed_listing_elements(
              element_type, raw, bindings, env, class_env, cache, stack, declarations,
              resolve_import,
            ),
            apply_typed_listing_elements(
              element_type, elements, bindings, env, class_env, cache, stack, declarations,
              resolve_import,
            ),
            default_value,
          )
        ListValue(elements) =>
          ListValue(
            apply_typed_listing_elements(
              element_type, elements, bindings, env, class_env, cache, stack, declarations,
              resolve_import,
            ),
          )
        _ => value
      }
    None => value
  }
}

///|
fn value_can_carry_collection_element_annotation(value : Value) -> Bool {
  match value {
    ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | ListValue(_)
    | SetValue(_) => true
    _ => false
  }
}

///|
fn overlay_collection_annotation_if_possible(
  type_name : String?,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> (Value, Bool) {
  match type_name {
    Some(name) =>
      if is_lazy_collection_annotation(name) &&
        value_can_carry_collection_element_annotation(value) &&
        collection_element_type_from_annotation(name, declarations) is Some(_) {
        let clean_name = strip_lazy_collection_annotation_marker(name)
        (
          apply_typed_listing_annotation(
            clean_name, value, bindings, env, class_env, cache, stack, declarations,
            resolve_import,
          ),
          true,
        )
      } else {
        (value, false)
      }
    None => (value, false)
  }
}

///|
priv enum TypeCastResult {
  TypeCastOk(Value)
  TypeCastErr(String)
}

///|
fn type_annotation_collection_head(
  type_name : String,
  declarations : Array[Declaration],
) -> String? {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(type_name, aliases)
  let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(resolved))
  let without_nullable = if trimmed.has_suffix("?") {
    String::unsafe_substring(trimmed, start=0, end=trimmed.length() - 1)
  } else {
    trimmed
  }
  let base = match pkl_constrained_type_base_name(without_nullable) {
    Some(b) => b
    None => without_nullable
  }
  let head = match base.find("<") {
    Some(idx) => String::unsafe_substring(base, start=0, end=idx)
    None => base
  }
  match head {
    "List" | "Listing" | "Set" | "Collection" | "Map" | "Mapping" => Some(head)
    _ => None
  }
}

///|
fn strip_balanced_outer_type_parens(type_name : String) -> String {
  let trimmed = pkl_constraint_trim(type_name)
  if !(trimmed.has_prefix("(") && trimmed.has_suffix(")")) {
    return trimmed
  }
  let mut depth = 0
  let mut wraps_whole = true
  for i = 0; i < trimmed.length(); i = i + 1 {
    let c = trimmed[i].to_int().unsafe_to_char()
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth == 0 && i < trimmed.length() - 1 {
        wraps_whole = false
        break
      }
    }
  }
  if wraps_whole && depth == 0 {
    strip_balanced_outer_type_parens(
      String::unsafe_substring(trimmed, start=1, end=trimmed.length() - 1),
    )
  } else {
    trimmed
  }
}

///|
fn instantiation_type_name_resolved(
  type_name : String,
  declarations : Array[Declaration],
) -> String {
  let aliases = eval_type_alias_bindings(declarations)
  strip_balanced_outer_type_parens(
    pkl_constraint_trim(eval_resolved_type_alias(type_name, aliases)),
  )
}

///|
fn instantiation_external_class_name(
  type_name : String,
  declarations : Array[Declaration],
) -> String {
  let mut name = pkl_strip_default_type_marker(
    instantiation_type_name_resolved(type_name, declarations),
  )
  if name.has_suffix("?") {
    name = String::unsafe_substring(name, start=0, end=name.length() - 1)
  }
  match pkl_constrained_type_base_name(name) {
    Some(base) => name = trim_spaces(base)
    None => ()
  }
  if name.length() >= 2 && name.has_prefix("\"") && name.has_suffix("\"") {
    return "String"
  }
  match name.find("<") {
    Some(idx) => String::unsafe_substring(name, start=0, end=idx)
    None => name
  }
}

///|
fn type_annotation_has_top_level_dot(type_name : String) -> Bool {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for ch in type_name {
    if ch == '.' && parens == 0 && brackets == 0 && angles == 0 {
      return true
    } else if ch == '(' {
      parens = parens + 1
    } else if ch == ')' && parens > 0 {
      parens = parens - 1
    } else if ch == '[' {
      brackets = brackets + 1
    } else if ch == ']' && brackets > 0 {
      brackets = brackets - 1
    } else if ch == '<' {
      angles = angles + 1
    } else if ch == '>' && angles > 0 {
      angles = angles - 1
    }
  }
  false
}

///|
fn type_annotation_collection_branch_count(
  type_name : String,
  declarations : Array[Declaration],
) -> Int {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(
    strip_lazy_collection_annotation_marker(type_name),
    aliases,
  )
  let normalized = strip_balanced_outer_type_parens(
    pkl_strip_default_type_marker(pkl_constraint_trim(resolved)),
  )
  let choices = split_top_level_union_choices(normalized)
  if choices.length() > 1 {
    let mut count = 0
    for choice in choices {
      count = count +
        type_annotation_collection_branch_count(choice, declarations)
    }
    return count
  }
  match type_annotation_collection_head(normalized, declarations) {
    Some(_) => 1
    None => 0
  }
}

///|
fn type_annotation_has_collection_union(
  type_name : String,
  declarations : Array[Declaration],
) -> Bool {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(
    strip_lazy_collection_annotation_marker(type_name),
    aliases,
  )
  let normalized = strip_balanced_outer_type_parens(
    pkl_strip_default_type_marker(pkl_constraint_trim(resolved)),
  )
  split_top_level_union_choices(normalized).length() > 1 &&
  type_annotation_collection_branch_count(normalized, declarations) > 0
}

///|
fn type_annotation_is_unsubstituted_parameterized_alias(
  type_name : String,
  declarations : Array[Declaration],
) -> Bool {
  let normalized = strip_balanced_outer_type_parens(
    pkl_strip_default_type_marker(pkl_constraint_trim(type_name)),
  )
  let base = match pkl_constrained_type_base_name(normalized) {
    Some(b) => b
    None => normalized
  }
  let head = match base.find("<") {
    Some(idx) => String::unsafe_substring(base, start=0, end=idx)
    None => return false
  }
  for declaration in declarations {
    match declaration {
      TypeAliasDeclaration(type_alias) =>
        if type_alias.name == head && type_alias.type_parameters.length() > 0 {
          return true
        }
      ClassDeclaration(_) | FunctionDeclaration(_) => ()
    }
  }
  false
}

///|
fn type_annotation_is_string_literal(type_name : String) -> Bool {
  let trimmed = pkl_constraint_trim(type_name)
  trimmed.length() >= 2 && trimmed.has_prefix("\"") && trimmed.has_suffix("\"")
}

///|
fn union_choices_are_string_literals(choices : Array[String]) -> Bool {
  if choices.length() == 0 {
    return false
  }
  for choice in choices {
    if !type_annotation_is_string_literal(choice) {
      return false
    }
  } nobreak {
    true
  }
}

///|
fn as_cast_type_label(type_name : String) -> String {
  match function_type_arity(type_name) {
    Some(arity) => "Function\{arity}"
    None => rejection_type_label(type_name)
  }
}

///|
fn as_cast_type_label_for_context(
  type_name : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> String {
  let label = as_cast_type_label(type_name)
  if label.find("#") is Some(_) ||
    label.find("|") is Some(_) ||
    label.find("<") is Some(_) ||
    is_stdlib_class_name(label) ||
    lookup_class_binding(class_env, label) is None {
    label
  } else {
    match module_name_from_cache(cache) {
      Some(module_name) => "\{module_name}#\{label}"
      None => label
    }
  }
}

///|
fn as_cast_actual_type_label(
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> String {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") => "Class"
        Some("TypeAlias") => "TypeAlias"
        Some("Module") => "Module"
        _ =>
          qualify_value_type_name(
            value,
            class_env,
            module_name_from_cache(cache),
          )
      }
    FunctionValue(parameters, _, _, _, _) => "Function\{parameters.length()}"
    _ =>
      qualify_value_type_name(value, class_env, module_name_from_cache(cache))
  }
}

///|
fn as_cast_compact_mapping_text(entries : Array[ValueEntry]) -> String {
  if entries.length() == 0 {
    return "new Mapping {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Mapping { ")
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_char('[')
    buf.write_string(render_pcf_value_inline(entries[i].key))
    buf.write_string("] = ")
    buf.write_string(render_pcf_value_inline(entries[i].value))
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn as_cast_compact_listing_text(elements : Array[Value]) -> String {
  if elements.length() == 0 {
    return "new Listing {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Listing { ")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string(render_pcf_value_inline(elements[i]))
  }
  buf.write_string(" }")
  let rendered = buf.to_string()
  if rendered.length() > 80 {
    String::unsafe_substring(rendered, start=0, end=77) + "..."
  } else {
    rendered
  }
}

///|
fn as_cast_rejected_value_inline(value : Value) -> String {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          match lookup_member(members, hidden_member_name("__qualified_name")) {
            Some(StringValue(name)) => name
            _ =>
              match lookup_member(members, "name") {
                Some(StringValue(name)) => name
                _ => render_pcf_value_inline(value)
              }
          }
        _ => render_pcf_value_inline(value)
      }
    ListingValue(elements) | DefaultedListingValue(_, elements, _) =>
      as_cast_compact_listing_text(elements)
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      as_cast_compact_mapping_text(entries)
    FunctionValue(parameters, _, _, _, _) =>
      "new Function\{parameters.length()} {}"
    _ => render_pcf_value_inline(value)
  }
}

///|
fn render_unknown_listing_for_diag(elements : Array[Value]) -> String {
  let buf = StringBuilder::new()
  if elements.length() == 0 {
    return "new Listing {}"
  }
  buf.write_string("new Listing { ")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string("?")
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn as_cast_rejected_value_for_type_inline(
  display_type : String,
  value : Value,
) -> String {
  let expected_head = type_annotation_collection_head(display_type, [])
  match (expected_head, value) {
    (Some("Mapping"), ListingValue(elements))
    | (Some("Mapping"), DefaultedListingValue(_, elements, _)) =>
      render_unknown_listing_for_diag(elements)
    _ => as_cast_rejected_value_inline(value)
  }
}

///|
fn as_cast_type_mismatch_message(
  display_type : String,
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> String {
  let diag_name = as_cast_type_label_for_context(display_type, class_env, cache)
  if value is NullValue {
    "Expected value of type `\{diag_name}`, but got `null`."
  } else {
    "Expected value of type `\{diag_name}`, but got type `\{as_cast_actual_type_label(value, class_env, cache)}`. Value: \{as_cast_rejected_value_for_type_inline(display_type, value)}"
  }
}

///|
fn render_collection_union_rejection_value(value : Value) -> String {
  match value {
    ListingValue(elements) | DefaultedListingValue(_, elements, _) =>
      render_listing_union_rejection_value(elements)
    ListValue(elements) => {
      let buf = StringBuilder::new()
      buf.write_string("List(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(render_collection_union_rejection_value(elements[i]))
      }
      buf.write_string(")")
      buf.to_string()
    }
    SetValue(elements) => {
      let buf = StringBuilder::new()
      buf.write_string("Set(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(render_collection_union_rejection_value(elements[i]))
      }
      buf.write_string(")")
      buf.to_string()
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) => {
      let buf = StringBuilder::new()
      buf.write_string("new Mapping { ")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_string("; ")
        }
        buf.write_string("[")
        buf.write_string(render_pcf_value_inline(entries[i].key))
        buf.write_string("] = ")
        if deferred_error_message(entries[i].value) is None {
          buf.write_string(render_pcf_value_inline(entries[i].value))
        } else {
          buf.write_string("?")
        }
      }
      buf.write_string(" }")
      buf.to_string()
    }
    _ => render_pcf_value_inline(value)
  }
}

///|
fn as_cast_collection_union_mismatch_message(
  display_type : String,
  value : Value,
) -> String {
  "Expected value of type `\{pretty_listing_union_type_name(display_type)}`, but got a different `\{eval_value_type_name(value)}`. Value: \{render_collection_union_rejection_value(value)}"
}

///|
fn dynamic_object_subscript_value(
  members : Array[ValueMember],
  key : Value,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match key {
    IntValue(index64) => {
      let elements : Array[Value] = []
      for field in visible_members(members) {
        if field.name.has_prefix("@element$") {
          elements.push(field.value)
        }
      }
      if elements.length() == 0 {
        return dynamic_object_mapping_subscript_value(members, key)
      }
      if index64 >= 0L && index64 < elements.length().to_int64() {
        let index = index64.to_int()
        match deferred_error_message(elements[index]) {
          Some(message) => {
            diagnostics.push(
              diag(
                adjust_deferred_listing_error_message(
                  message,
                  elements.length() - 1,
                ),
              ),
            )
            None
          }
          None => Some(elements[index])
        }
      } else {
        diagnostics.push(
          diag(
            "Element index `\{format_int_with_commas(index64)}` is out of range `0`..`\{elements.length() - 1}`.",
          ),
        )
        None
      }
    }
    StringValue(name) =>
      match lookup_member(members, name) {
        Some(value) => Some(value)
        None => dynamic_object_mapping_subscript_value(members, key)
      }
    _ => dynamic_object_mapping_subscript_value(members, key)
  }
}

///|
fn dynamic_object_mapping_subscript_value(
  members : Array[ValueMember],
  key : Value,
) -> Value? {
  let mut found : Value? = None
  for field in visible_members(members) {
    if !field.name.has_prefix("@subscript$") {
      continue
    }
    match field.value {
      ObjectValue(pair_members) =>
        match
          (
            lookup_member(pair_members, "@key"),
            lookup_member(pair_members, "@value"),
          ) {
          (Some(k), Some(v)) => if k == key { found = Some(v) }
          _ => ()
        }
      _ => ()
    }
  }
  found
}

///|
fn dynamic_members_from_env(env : Array[ValueBinding]) -> Array[ValueMember] {
  let members : Array[ValueMember] = []
  for binding in env {
    if binding.name.has_prefix("@subscript$") ||
      binding.name.has_prefix("@element$") {
      members.push({
        name: binding.name,
        value: binding.value,
        source: None,
        annotations: [],
      })
    }
  }
  members
}

///|
fn cast_list_like_value_to_type(
  head : String,
  element_type : String,
  value : Value,
  eager_elements : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> TypeCastResult {
  let apply_elements = fn(elements : Array[Value]) -> Array[Value] {
    apply_typed_listing_elements(
      element_type, elements, bindings, env, class_env, cache, stack, declarations,
      resolve_import,
    )
  }
  match (head, value) {
    ("List", ListValue(elements)) => {
      let checked = apply_elements(elements)
      let message = if eager_elements {
        first_deferred_error_message(ListValue(checked))
      } else {
        first_top_level_deferred_error_message(checked)
      }
      match message {
        Some(message) => TypeCastErr(message)
        None => TypeCastOk(ListValue(checked))
      }
    }
    ("Set", SetValue(elements)) => {
      match first_deferred_error_message(SetValue(elements)) {
        Some(message) => return TypeCastErr(message)
        None => ()
      }
      let checked : Array[Value] = []
      for element in elements {
        checked.push(
          apply_typed_set_element_annotation(
            element_type, element, bindings, env, class_env, cache, stack, declarations,
            resolve_import,
          ),
        )
      }
      match first_top_level_deferred_error_message(checked) {
        Some(message) => TypeCastErr(message)
        None => TypeCastOk(SetValue(checked))
      }
    }
    ("Listing", ListingValue(elements)) => {
      let checked = apply_elements(elements)
      if eager_elements {
        match first_deferred_error_message(ListingValue(checked)) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(ListingValue(checked))
    }
    ("Listing", DefaultedListingValue(raw, elements, default_value)) => {
      let checked_raw = apply_elements(raw)
      let checked_elements = apply_elements(elements)
      if eager_elements {
        match
          first_deferred_error_message(
            DefaultedListingValue(checked_raw, checked_elements, default_value),
          ) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(
        DefaultedListingValue(checked_raw, checked_elements, default_value),
      )
    }
    ("Collection", ListValue(elements)) => {
      let checked = apply_elements(elements)
      let message = if eager_elements {
        first_deferred_error_message(ListValue(checked))
      } else {
        first_top_level_deferred_error_message(checked)
      }
      match message {
        Some(message) => TypeCastErr(message)
        None => TypeCastOk(ListValue(checked))
      }
    }
    ("Collection", SetValue(elements)) => {
      match first_deferred_error_message(SetValue(elements)) {
        Some(message) => return TypeCastErr(message)
        None => ()
      }
      let checked : Array[Value] = []
      for element in elements {
        checked.push(
          apply_typed_set_element_annotation(
            element_type, element, bindings, env, class_env, cache, stack, declarations,
            resolve_import,
          ),
        )
      }
      match first_top_level_deferred_error_message(checked) {
        Some(message) => TypeCastErr(message)
        None => TypeCastOk(SetValue(checked))
      }
    }
    ("Collection", ListingValue(elements)) => {
      let checked = apply_elements(elements)
      if eager_elements {
        match first_deferred_error_message(ListingValue(checked)) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(ListingValue(checked))
    }
    ("Collection", DefaultedListingValue(raw, elements, default_value)) => {
      let checked_raw = apply_elements(raw)
      let checked_elements = apply_elements(elements)
      if eager_elements {
        match
          first_deferred_error_message(
            DefaultedListingValue(checked_raw, checked_elements, default_value),
          ) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(
        DefaultedListingValue(checked_raw, checked_elements, default_value),
      )
    }
    _ => TypeCastOk(value)
  }
}

///|
fn cast_mapping_like_value_to_type(
  head : String,
  key_type : String,
  value_type : String,
  value : Value,
  eager_values : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> TypeCastResult {
  let check_entries = fn(entries : Array[ValueEntry]) -> Array[ValueEntry] {
    apply_typed_collection_entries(
      key_type, value_type, entries, bindings, env, class_env, cache, stack, declarations,
      resolve_import,
    )
  }
  match (head, value) {
    ("Map", MapValue(entries)) => {
      let checked = check_entries(entries)
      match first_top_level_deferred_entry_key_message(checked) {
        Some(message) => return TypeCastErr(message)
        None => ()
      }
      let message = if eager_values {
        first_deferred_error_message(MapValue(checked))
      } else {
        first_top_level_deferred_entry_value_message(checked)
      }
      match message {
        Some(message) => TypeCastErr(message)
        None => TypeCastOk(MapValue(checked))
      }
    }
    ("Mapping", MappingValue(entries)) => {
      let checked = check_entries(entries)
      match first_top_level_deferred_entry_key_message(checked) {
        Some(message) => return TypeCastErr(message)
        None => ()
      }
      if eager_values {
        match first_deferred_error_message(MappingValue(checked)) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(MappingValue(checked))
    }
    ("Mapping", DefaultedMappingValue(raw, entries, default_value)) => {
      let checked_raw = check_entries(raw)
      let checked_entries = check_entries(entries)
      match first_top_level_deferred_entry_key_message(checked_entries) {
        Some(message) => return TypeCastErr(message)
        None => ()
      }
      if eager_values {
        match
          first_deferred_error_message(
            DefaultedMappingValue(checked_raw, checked_entries, default_value),
          ) {
          Some(message) => return TypeCastErr(message)
          None => ()
        }
      }
      TypeCastOk(
        DefaultedMappingValue(checked_raw, checked_entries, default_value),
      )
    }
    _ => TypeCastOk(value)
  }
}

///|
fn cast_value_to_single_type_annotation(
  display_type : String,
  resolved_type : String,
  value : Value,
  union_context : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> TypeCastResult {
  let trimmed = pkl_strip_default_type_marker(
    pkl_constraint_trim(resolved_type),
  )
  if trimmed.has_suffix("?") {
    if value is NullValue {
      return TypeCastOk(value)
    }
    let inner = String::unsafe_substring(
      trimmed,
      start=0,
      end=trimmed.length() - 1,
    )
    return cast_value_to_single_type_annotation(
      display_type, inner, value, union_context, bindings, env, class_env, cache,
      stack, declarations, resolve_import,
    )
  }
  match function_type_arity(trimmed) {
    Some(arity) =>
      return match value {
        FunctionValue(parameters, _, _, _, _) if parameters.length() == arity =>
          TypeCastOk(value)
        _ =>
          TypeCastErr(
            as_cast_type_mismatch_message(display_type, value, class_env, cache),
          )
      }
    None => ()
  }
  if type_annotation_is_string_literal(trimmed) {
    let literal = String::unsafe_substring(
      trimmed,
      start=1,
      end=trimmed.length() - 1,
    )
    return match value {
      StringValue(s) if s == literal => TypeCastOk(value)
      StringValue(s) =>
        TypeCastErr(
          "Expected value of type `\{display_type}`, but got `\"\{s}\"`.",
        )
      _ =>
        TypeCastErr(
          as_cast_type_mismatch_message(display_type, value, class_env, cache),
        )
    }
  }
  let base = match pkl_constrained_type_base_name(trimmed) {
    Some(b) => b
    None => trimmed
  }
  let head = match base.find("<") {
    Some(idx) => String::unsafe_substring(base, start=0, end=idx)
    None => base
  }
  if head == "BaseValueRenderer" ||
    head == "ValueRenderer" ||
    head == "RenderDirective" ||
    renderer_format_for_class_name(head) is Some(_) {
    if !eval_value_accepts_type_annotation(head, value) {
      return TypeCastErr(
        as_cast_type_mismatch_message(display_type, value, class_env, cache),
      )
    }
    return TypeCastOk(value)
  }
  if head == "module" {
    return match value {
      ObjectValue(members) =>
        match find_object_class_tag(members) {
          Some("module") => TypeCastOk(value)
          Some(_) =>
            TypeCastErr(
              as_cast_type_mismatch_message(
                display_type, value, class_env, cache,
              ),
            )
          None => TypeCastOk(value)
        }
      _ =>
        TypeCastErr(
          as_cast_type_mismatch_message(display_type, value, class_env, cache),
        )
    }
  }
  if head == "Mixin" {
    return match value {
      ObjectValue(members) =>
        TypeCastOk(ObjectValue(tag_object_with_class(members, trimmed)))
      _ =>
        TypeCastErr(
          as_cast_type_mismatch_message(display_type, value, class_env, cache),
        )
    }
  }
  if value is ObjectValue(_) {
    match lookup_value(env, head) {
      Some(ObjectValue(_)) => return TypeCastOk(value)
      _ => ()
    }
    match lookup_value(cache, head) {
      Some(ObjectValue(_)) => return TypeCastOk(value)
      _ => ()
    }
  }
  if !eval_value_matches_bare_type(head, value, class_env) &&
    !value_satisfies_user_class_annotation(head, value, declarations) {
    return TypeCastErr(
      as_cast_type_mismatch_message(display_type, value, class_env, cache),
    )
  }
  match collection_element_type_from_annotation(trimmed, declarations) {
    Some(element_type) =>
      return cast_list_like_value_to_type(
        head, element_type, value, union_context, bindings, env, class_env, cache,
        stack, declarations, resolve_import,
      )
    None => ()
  }
  match mapping_entry_types_from_annotation(trimmed, declarations) {
    Some((key_type, value_type)) =>
      return cast_mapping_like_value_to_type(
        head, key_type, value_type, value, union_context, bindings, env, class_env,
        cache, stack, declarations, resolve_import,
      )
    None => ()
  }
  match generic_argument_text(base, "Pair") {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() == 2 {
        match value {
          PairValue(first, second) => {
            let checked = PairValue(
              apply_typed_collection_element_annotation(
                parts[0],
                first,
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                resolve_import,
              ),
              apply_typed_collection_element_annotation(
                parts[1],
                second,
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                resolve_import,
              ),
            )
            if union_context {
              match first_deferred_error_message(checked) {
                Some(message) => return TypeCastErr(message)
                None => ()
              }
            }
            return TypeCastOk(checked)
          }
          _ => ()
        }
      }
    }
    None => ()
  }
  match
    eval_callable_argument_rejection_message(
      Some(resolved_type),
      value,
      declarations,
    ) {
    Some(message) => return TypeCastErr(message)
    None => ()
  }
  match
    eval_callable_runtime_constraint_message(
      Some(resolved_type),
      value,
      bindings,
      class_env,
      env,
      stack,
      declarations,
      resolve_import,
    ) {
    Some(message) => TypeCastErr(message)
    None => TypeCastOk(value)
  }
}

///|
fn cast_value_to_type_annotation(
  display_type : String,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> TypeCastResult {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = strip_balanced_outer_type_parens(
    eval_resolved_type_alias(display_type, aliases),
  )
  if resolved == display_type && type_annotation_has_top_level_dot(display_type) {
    match value {
      ListingValue(_)
      | DefaultedListingValue(_, _, _)
      | ListValue(_)
      | SetValue(_)
      | MappingValue(_)
      | DefaultedMappingValue(_, _, _)
      | MapValue(_)
      | PairValue(_, _)
      | ObjectValue(_) => return TypeCastOk(value)
      _ => ()
    }
  }
  if resolved == display_type &&
    type_annotation_is_unsubstituted_parameterized_alias(
      display_type, declarations,
    ) {
    return TypeCastOk(value)
  }
  let choices = split_top_level_union_choices(resolved)
  if choices.length() > 1 {
    let collection_branch_count = type_annotation_collection_branch_count(
      resolved, declarations,
    )
    for choice in choices {
      let choice_collection_branch_count = type_annotation_collection_branch_count(
        choice, declarations,
      )
      let eager_collection_branch = collection_branch_count != 1 ||
        choice_collection_branch_count != 1
      match
        cast_value_to_single_type_annotation(
          pkl_constraint_trim(choice),
          pkl_constraint_trim(choice),
          value,
          eager_collection_branch,
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          resolve_import,
        ) {
        TypeCastOk(casted) => return TypeCastOk(casted)
        TypeCastErr(_) => ()
      }
    }
    if union_choices_are_string_literals(choices) {
      match value {
        StringValue(s) =>
          return TypeCastErr(
            "Expected value of type `\{display_type}`, but got `\"\{s}\"`.",
          )
        _ => ()
      }
    }
    if collection_branch_count > 0 {
      return TypeCastErr(
        as_cast_collection_union_mismatch_message(display_type, value),
      )
    }
    return TypeCastErr(
      as_cast_type_mismatch_message(display_type, value, class_env, cache),
    )
  }
  cast_value_to_single_type_annotation(
    display_type, resolved, value, false, bindings, env, class_env, cache, stack,
    declarations, resolve_import,
  )
}

///|
fn materialize_mapping_raw_entries(
  raw_entries : Array[ValueEntry],
  default_value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueEntry]? {
  let out : Array[ValueEntry] = []
  for entry in raw_entries {
    match
      eval_collection_default_for_key(
        default_value,
        entry.key,
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(default_for_key_raw) => {
        let default_for_key = freeze_collection_default_value(
          default_for_key_raw,
        )
        out.push({
          key: entry.key,
          value: merge_collection_default_value(default_for_key, entry.value),
        })
      }
      None => return None
    }
  }
  Some(out)
}

///|
fn eval_defaulted_listing_method(
  elements : Array[Value],
  default_value : Value,
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if method_name != "getOrDefault" {
    return eval_list_or_listing_method(
      false, elements, method_name, arguments, bindings, env, class_env, cache, stack,
      declarations, diagnostics, resolve_import,
    )
  }
  if arguments.length() != 1 {
    diagnostics.push(
      diag("Listing.getOrDefault expects 1 argument, got \{arguments.length()}"),
    )
    return None
  }
  match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(IntValue(idx64)) => {
      let idx = idx64.to_int()
      if idx64 >= 0L && idx < elements.length() {
        Some(elements[idx])
      } else {
        match
          eval_collection_default_for_key(
            default_value,
            IntValue(idx64),
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(default_for_key) =>
            Some(freeze_collection_default_value(default_for_key))
          None => None
        }
      }
    }
    Some(_) => {
      diagnostics.push(diag("Listing.getOrDefault expects an Int index"))
      None
    }
    None => None
  }
}

///|
fn eval_defaulted_mapping_method(
  entries : Array[ValueEntry],
  default_value : Value,
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if method_name != "getOrDefault" {
    return eval_mapping_method(
      entries, method_name, arguments, bindings, env, class_env, cache, stack, declarations,
      diagnostics, resolve_import,
    )
  }
  if arguments.length() != 1 {
    diagnostics.push(
      diag("Mapping.getOrDefault expects 1 argument, got \{arguments.length()}"),
    )
    return None
  }
  match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(key) =>
      match lookup_entry(entries, key) {
        Some(v) => Some(v)
        None =>
          match
            eval_collection_default_for_key(
              default_value, key, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            ) {
            Some(default_for_key) =>
              Some(freeze_collection_default_value(default_for_key))
            None => None
          }
      }
    None => None
  }
}

///|
fn eval_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match expr {
    IntLiteral(value) => Some(IntValue(value))
    FloatLiteral(value) => Some(FloatValue(value))
    BoolLiteral(value) => Some(BoolValue(value))
    StringLiteral(value) => Some(StringValue(value))
    NullLiteral => Some(NullValue)
    ImportExpr(uri) =>
      if !sandbox_is_module_allowed(uri) {
        diagnostics.push(
          diag(
            "Refusing to load module `\{uri}` because it does not match any entry in the module allowlist (`--allowed-modules`).",
          ),
        )
        None
      } else {
        match current_module_snapshot_for_import(uri, cache) {
          Some(value) => Some(value)
          None =>
            match resolve_import(uri) {
              Some(EvalOk(value)) => Some(value)
              Some(EvalError(errors)) => {
                for error in errors {
                  diagnostics.push(error)
                }
                None
              }
              None => {
                diagnostics.push(diag("Cannot find module `\{uri}`."))
                None
              }
            }
        }
      }
    ImportGlobExpr(uri) =>
      eval_import_glob_value(
        uri,
        current_module_path_from_cache(cache),
        diagnostics,
        resolve_import,
      )
    ObjectLiteral(members) => {
      // PKL-148bh: tag the body with the current Dynamic-class marker
      // so a bare `getClass()` inside an untyped `new { ... }` body
      // resolves to the Dynamic mirror (matches Apple Pkl's behaviour
      // — basic/newInAmendingModuleMethod).
      let body_cache = copy_value_bindings(cache)
      body_cache.push({
        name: "@__constructing_class",
        value: StringValue("Dynamic"),
      })
      Some(
        ObjectValue(
          eval_object_members(
            members, bindings, env, class_env, body_cache, stack, declarations, diagnostics,
            resolve_import,
          ),
        ),
      )
    }
    TypedObjectLiteral(type_name, members) => {
      let instantiation_name = instantiation_type_name_resolved(
        type_name, declarations,
      )
      let instantiation_choices = split_top_level_union_choices(
        instantiation_name,
      )
      if instantiation_choices.length() > 1 {
        let mut default_choice : String? = None
        for choice in instantiation_choices {
          let trimmed = trim_spaces(choice)
          if trimmed.has_prefix("*") {
            default_choice = Some(
              trim_spaces(
                String::unsafe_substring(trimmed, start=1, end=trimmed.length()),
              ),
            )
            break
          }
        }
        match default_choice {
          Some(default_type_name) =>
            return eval_expr_with_bindings(
              TypedObjectLiteral(default_type_name, members),
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
          None => {
            diagnostics.push(
              diag("Cannot instantiate type `\{instantiation_name}`."),
            )
            return None
          }
        }
      }
      let external_class_name = instantiation_external_class_name(
        type_name, declarations,
      )
      if is_external_only_class_name(external_class_name) &&
        !(lookup_class_binding(class_env, type_name) is Some(_)) &&
        !(lookup_class_binding(class_env, external_class_name) is Some(_)) {
        diagnostics.push(
          diag(
            "Cannot instantiate, or amend an instance of, external class `\{external_class_name}`.",
          ),
        )
        return None
      }
      match type_annotation_collection_head(type_name, declarations) {
        Some("Listing") | Some("List") | Some("Set") | Some("Collection") =>
          match object_literal_to_listing_literal(ObjectLiteral(members)) {
            Some(listing_expr) =>
              return eval_expr_with_bindings(
                CallExpr(Identifier("@__typed_listing"), [
                  StringLiteral(type_name),
                  listing_expr,
                ]),
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            None => ()
          }
        Some("Mapping") | Some("Map") =>
          match object_literal_to_mapping_literal(ObjectLiteral(members)) {
            Some(mapping_expr) =>
              return eval_expr_with_bindings(
                CallExpr(Identifier("@__typed_listing"), [
                  StringLiteral(type_name),
                  mapping_expr,
                ]),
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            None => ()
          }
        _ => ()
      }
      // PKL-152: Apple Pkl's stdlib scalar / collection-constructor
      // classes (`Int`, `Float`, `Bool`, `String`, `List`, `Set`,
      // `Map`, `Pair`, `IntSeq`, `Bytes`, `Duration`, `DataSize`,
      // `Regex`, `Function`, `Class`, `TypeAlias`) can't be
      // instantiated through `new` — they're built via constructor
      // functions or literal forms. `Listing` / `Mapping` / `Dynamic`
      // / `Object` are the genuine `new`-instantiable bases.
      if is_external_only_class_name(type_name) &&
        !(lookup_class_binding(class_env, type_name) is Some(_)) {
        diagnostics.push(
          diag(
            "Cannot instantiate, or amend an instance of, external class `\{type_name}`.",
          ),
        )
        return None
      }
      // PKL-152: abstract classes ship the `abstract` modifier on
      // their declaration. Apple Pkl rejects `new <abstract>` with a
      // dedicated diagnostic. The `ValueRenderer` base on
      // `mappings/wrongParent` is the upstream sentinel for this.
      if is_abstract_class_name(type_name) {
        diagnostics.push(
          diag("Cannot instantiate abstract class `\{type_name}`."),
        )
        return None
      }
      if type_name == "Listing" {
        for m in members {
          let bare = strip_member_visibility_prefix(m.name)
          if !is_invisible_member_name(m.name) &&
            !m.name.has_prefix("@element$") &&
            !m.name.has_prefix("@subscript$") &&
            m.name != "@when" &&
            m.name != "@for" &&
            m.name != "@spread" &&
            bare != "default" {
            diagnostics.push(
              diag(
                "Object of type `Listing` cannot have a property (other than `default`).",
              ),
            )
            return None
          }
        }
      }
      // PKL-152: a user-class or stdlib non-listing target rejects a
      // bare-element body (`new Person { "pigeon" }`). The element
      // payload is the `@element$<offset>` sentinel; if any member
      // starts with that prefix and the type isn't Listing / List /
      // Dynamic / Object, the body is malformed. Mapping rejects the
      // same way with the dedicated `Object of type \`Mapping\`
      // cannot have an element.` wording. Person-style classes
      // report the qualified name. Dynamic and Object intentionally
      // accept bare-element bodies (the Dynamic-shape ObjectValue
      // already used internally).
      if type_name != "Listing" &&
        type_name != "List" &&
        type_name != "Dynamic" &&
        type_name != "Object" {
        let mut element_seen = false
        let mut when_seen = false
        for m in members {
          if m.name.has_prefix("@element$") {
            element_seen = true
          } else if m.name == "@when" {
            when_seen = true
          }
        }
        if element_seen {
          let label = if type_name == "Mapping" {
            if when_seen {
              "new Mapping {}"
            } else {
              "Mapping"
            }
          } else if is_stdlib_class_name(type_name) {
            type_name
          } else if when_seen {
            "new \{type_name} {}"
          } else {
            let module_name = match lookup_value(cache, "@__module_name") {
              Some(StringValue(s)) => s
              _ => ""
            }
            if module_name.length() > 0 {
              "\{module_name}#\{type_name}"
            } else {
              type_name
            }
          }
          diagnostics.push(
            diag("Object of type `\{label}` cannot have an element."),
          )
          return None
        }
      }
      // PKL-152: same shape for bracket subscript entries on a
      // non-Listing / non-Mapping target — `new Person { ["pigeon"] =
      // true }` raises "Object of type `<module>#Person` cannot have
      // an entry."
      if type_name != "Listing" &&
        type_name != "List" &&
        type_name != "Mapping" &&
        type_name != "Map" &&
        type_name != "Dynamic" &&
        type_name != "Object" {
        let mut entry_seen = false
        let mut when_seen = false
        for m in members {
          if m.name.has_prefix("@subscript$") {
            entry_seen = true
          } else if m.name == "@when" {
            when_seen = true
          }
        }
        if entry_seen {
          let label = if is_stdlib_class_name(type_name) {
            type_name
          } else if when_seen {
            "new \{type_name} {}"
          } else {
            let module_name = match lookup_value(cache, "@__module_name") {
              Some(StringValue(s)) => s
              _ => ""
            }
            if module_name.length() > 0 {
              "\{module_name}#\{type_name}"
            } else {
              type_name
            }
          }
          diagnostics.push(
            diag("Object of type `\{label}` cannot have an entry."),
          )
          return None
        }
      }
      let class_defaults = eval_class_default_members(
        type_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      let class_default_deps = class_default_dependency_names(
        members, class_defaults, bindings, env, cache,
      )
      // PKL-148bb: expose class defaults as fallback bindings inside
      // the body's lookup chain so a body member that references a
      // bare name not declared in the body still resolves
      // (`new Foo { x = y }` where Foo has `y = 1` and the surrounding
      // scope has no `y` — Apple Pkl picks up the class-default `y`).
      // Prepended to `bindings`: `find_binding` returns the *last*
      // match, so outer siblings still shadow the class default when
      // both are present (`objects/lateBinding3` expects `x = 3`
      // because outer `y = 3` beats the class-default `y = 1`).
      let body_bindings : Array[Binding] = []
      collect_class_default_bindings(body_bindings, type_name, class_env)
      for b in bindings {
        body_bindings.push(b)
      }
      // PKL-148bb: expose the class defaults as `super` for the body's
      // eval cache so a constructor body's `super.X` reads the class-
      // default value of `X` (`classes/class2a`: `friends = super.friends
      // + ...` reads the inherited / class-default Set). The existing
      // amend-side `super` is pushed by the AmendExpr handler against
      // the amend target; the TypedObjectLiteral handler needs its own
      // entry against the class's defaults.
      let body_cache = copy_value_bindings(cache)
      body_cache.push({ name: "super", value: ObjectValue(class_defaults) })
      // PKL-148bh: stash the type currently being constructed so a
      // bare `getClass()` inside the body resolves to this class's
      // reflect mirror (basic/newInAmendingModuleMethod).
      body_cache.push({
        name: "@__constructing_class",
        value: StringValue(type_name),
      })
      let merged = reeval_class_defaults_after_constructor_overrides(
        type_name,
        members,
        reorder_typed_object_members_by_class_declaration(
          merge_value_members(
            class_defaults,
            rename_overrides_for_hidden_class_properties(
              eval_object_members(
                members, body_bindings, env, class_env, body_cache, stack, declarations,
                diagnostics, resolve_import,
              ),
              type_name,
              class_env,
            ),
          ),
          type_name,
          class_env,
        ),
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      )
      // PKL-148b: fire class-property constraints at construction time
      // so `new P { l {} }` where `l: Listing<String>(!isEmpty)` raises
      // the violation diagnostic right where the value is built, not
      // only at the top-level binding boundary. The check returns the
      // first violation; subsequent ones still surface if the outer
      // binding pass re-runs the check.
      let mut violation_emitted = false
      for field in members {
        match lookup_member(merged, field.name) {
          Some(member_value) => {
            // PKL-148i: enforce the declared type annotation first so
            // `new Person { name = 42 }` rejects with "Expected value
            // of type `String`, but got type `Int`. Value: 42" instead
            // of silently keeping the integer. A pre-existing
            // forward-binding leak lets `Identifier(...)` bodies
            // resolve through sibling module-level locals; firing the
            // type check on those leaked values would mask gold output
            // for fixtures the leak does not otherwise break, so the
            // bare-Identifier shape is skipped. All other expression
            // shapes (literals, CallExpr-built collections, …) run
            // the check so `xs = List("one")` against `xs: List<Int>`
            // surfaces the element-type mismatch through
            // `test.catch(...)`.
            let value_skips_type_check = match field.value {
              Identifier(_) => true
              _ => false
            }
            let type_message = if !value_skips_type_check {
              eval_class_property_type_rejection_message(
                type_name,
                field.name,
                member_value,
                declarations,
              )
            } else {
              None
            }
            match type_message {
              Some(message) => {
                diagnostics.push(diag(message))
                violation_emitted = true
              }
              None =>
                match
                  eval_class_property_constraint_value_rejection_message(
                    type_name,
                    field.name,
                    member_value,
                    declarations,
                  ) {
                  Some(message) => {
                    diagnostics.push(diag(message))
                    violation_emitted = true
                  }
                  None =>
                    // PKL-148c: static predicate cascade returned no
                    // match; try a runtime evaluation of the constraint
                    // expression with `this` bound to the candidate value
                    // (and the surrounding object's members hoisted into
                    // env via implicit receiver). Catches the harder
                    // forms: `Int(this >= min)`, `Int(abs < 100)`,
                    // `Address(street.endsWith("St."))`, etc.
                    match
                      eval_runtime_constraint_for_property(
                        type_name,
                        field.name,
                        member_value,
                        merged,
                        bindings,
                        env,
                        class_env,
                        cache,
                        stack,
                        declarations,
                        resolve_import,
                      ) {
                      Some(message) => {
                        diagnostics.push(diag(message))
                        violation_emitted = true
                      }
                      None => ()
                    }
                }
            }
          }
          None => ()
        }
      }
      if violation_emitted {
        None
      } else {
        Some(
          ObjectValue(
            tag_object_with_class(
              add_class_default_dependency_metadata(merged, class_default_deps),
              type_name,
            ),
          ),
        )
      }
    }
    ListingLiteral(elements) => {
      let collection_bindings = bindings_with_listing_locals(elements, bindings)
      // PKL-152: a Listing body that picked up a bracket-key entry
      // (`new Listing { [0] = true }`) carries a synthetic call to
      // `@__listing_index_entry`. Pure construction can't index into
      // a non-existent element, so raise Apple Pkl's "Element index
      // out of range" diagnostic immediately.
      for element in elements {
        if collection_local_binding_from_expr(element) is Some(_) {
          continue
        }
        if collection_default_expr_from_listing_element(element) is Some(_) {
          continue
        }
        match element {
          CallExpr(Identifier("@__listing_property_entry"), _) => {
            diagnostics.push(
              diag(
                "Object of type `Listing` cannot have a property (other than `default`).",
              ),
            )
            return None
          }
          CallExpr(Identifier("@__listing_index_entry"), idx_args) =>
            if idx_args.length() >= 1 {
              match
                eval_expr_with_bindings(
                  idx_args[0],
                  collection_bindings,
                  env,
                  class_env,
                  cache,
                  stack,
                  declarations,
                  diagnostics,
                  resolve_import,
                ) {
                Some(IntValue(idx)) => {
                  diagnostics.push(
                    diag("Element index `\{idx}` is out of range `0`..`-1`."),
                  )
                  return None
                }
                _ => ()
              }
            }
          _ => ()
        }
      }
      let mut default_value : Value? = None
      for element in elements {
        if collection_local_binding_from_expr(element) is Some(_) {
          continue
        }
        match collection_default_expr_from_listing_element(element) {
          Some(default_expr) =>
            default_value = eval_collection_default_expr(
              default_expr, collection_bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          None => ()
        }
      }
      let raw_values : Array[Value] = []
      let values : Array[Value] = []
      for element in elements {
        if collection_local_binding_from_expr(element) is Some(_) {
          continue
        }
        if collection_default_expr_from_listing_element(element) is Some(_) {
          continue
        }
        // PKL-136: a `WhenSpread(inner)` element wraps a ConditionalExpr
        // whose branches are ListingLiterals. Evaluate the wrapper and
        // spread the resulting ListingValue's elements into the parent.
        match element {
          WhenSpread(inner) => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_context_bindings(
              body_env,
              body_cache,
              stack,
              collection_this_listing_value(raw_values, values, default_value),
            )
            let spread_value = match inner {
              ForGenerator(
                var1,
                var2,
                source_expr,
                body_members,
                var1_type,
                var2_type
              ) =>
                eval_for_generator(
                  var1,
                  var2,
                  source_expr,
                  body_members,
                  var1_type,
                  var2_type,
                  collection_bindings,
                  body_env,
                  body_env,
                  class_env,
                  body_cache,
                  stack,
                  declarations,
                  diagnostics,
                  resolve_import,
                  defer_generated_member_errors=true,
                )
              _ =>
                eval_expr_with_bindings(
                  inner, collection_bindings, body_env, class_env, body_cache, stack,
                  declarations, diagnostics, resolve_import,
                )
            }
            match spread_value {
              Some(value) =>
                if !append_listing_spread_value(
                    value, raw_values, values, diagnostics,
                  ) {
                  return None
                }
              None => ()
            }
          }
          _ => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_context_bindings(
              body_env,
              body_cache,
              stack,
              collection_this_listing_value(raw_values, values, default_value),
            )
            let diag_start = diagnostics.length()
            match
              eval_collection_body_expr(
                element,
                IntValue(raw_values.length().to_int64()),
                default_value,
                collection_bindings,
                body_env,
                class_env,
                body_cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              ) {
              Some((raw, materialized)) => {
                raw_values.push(raw)
                values.push(materialized)
              }
              None =>
                if diagnostics.length() > diag_start {
                  let message = diagnostics[diag_start].message
                  while diagnostics.length() > diag_start {
                    let _ = diagnostics.pop()
                  }
                  let deferred = deferred_error_value(message)
                  raw_values.push(deferred)
                  values.push(deferred)
                }
            }
          }
        }
      }
      match default_value {
        Some(default_v) =>
          Some(DefaultedListingValue(raw_values, values, default_v))
        None => Some(ListingValue(values))
      }
    }
    MappingLiteral(entries) => {
      let collection_bindings = bindings_with_mapping_locals(entries, bindings)
      // PKL-152: a Mapping body that picked up a bare-expression
      // element (`new Mapping { "pigeon" }`) carries an `@element$`
      // sentinel key. Raise Apple Pkl's "cannot have an element"
      // wording before the entries get rendered.
      let mut mapping_when_seen = false
      for entry in entries {
        if collection_local_binding_from_expr(entry.key) is Some(_) {
          continue
        }
        if collection_default_expr_from_mapping_entry(entry) is Some(_) {
          continue
        }
        match entry.key {
          WhenSpread(_) => mapping_when_seen = true
          Identifier(name) =>
            if name.has_prefix("@element$") {
              let label = if mapping_when_seen {
                "new Mapping {}"
              } else {
                "Mapping"
              }
              diagnostics.push(
                diag("Object of type `\{label}` cannot have an element."),
              )
              return None
            }
          _ => ()
        }
      }
      let mut default_value : Value? = None
      for entry in entries {
        if collection_local_binding_from_expr(entry.key) is Some(_) {
          continue
        }
        match collection_default_expr_from_mapping_entry(entry) {
          Some(default_expr) =>
            default_value = eval_collection_default_expr(
              default_expr, collection_bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          None => ()
        }
      }
      let raw_values : Array[ValueEntry] = []
      let values : Array[ValueEntry] = []
      let mut duplicate_emitted = false
      for entry in entries {
        if collection_local_binding_from_expr(entry.key) is Some(_) {
          continue
        }
        if collection_default_expr_from_mapping_entry(entry) is Some(_) {
          continue
        }
        // PKL-136: a synthetic MappingEntry with `key = WhenSpread(inner)`
        // is the Mapping-body when block. Evaluate the wrapper and spread
        // the resulting MappingValue's entries.
        match entry.key {
          WhenSpread(inner) => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_context_bindings(
              body_env,
              body_cache,
              stack,
              collection_this_mapping_value(raw_values, values, default_value),
            )
            let spread_value = match inner {
              ForGenerator(
                var1,
                var2,
                source_expr,
                body_members,
                var1_type,
                var2_type
              ) =>
                eval_for_generator(
                  var1,
                  var2,
                  source_expr,
                  body_members,
                  var1_type,
                  var2_type,
                  collection_bindings,
                  body_env,
                  body_env,
                  class_env,
                  body_cache,
                  stack,
                  declarations,
                  diagnostics,
                  resolve_import,
                  defer_generated_member_errors=true,
                )
              _ =>
                eval_expr_with_bindings(
                  inner, collection_bindings, body_env, class_env, body_cache, stack,
                  declarations, diagnostics, resolve_import,
                )
            }
            match spread_value {
              Some(value) =>
                if !append_mapping_spread_value(
                    value, raw_values, values, diagnostics,
                  ) {
                  return None
                }
              None => ()
            }
          }
          _ => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_context_bindings(
              body_env,
              body_cache,
              stack,
              collection_this_mapping_value(raw_values, values, default_value),
            )
            let key = eval_expr_with_bindings(
              entry.key,
              collection_bindings,
              body_env,
              class_env,
              body_cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            match key {
              Some(k) => {
                let value_diag_start = diagnostics.length()
                let entry_values = eval_collection_body_expr(
                  entry.value,
                  k,
                  default_value,
                  collection_bindings,
                  body_env,
                  class_env,
                  body_cache,
                  stack,
                  declarations,
                  diagnostics,
                  resolve_import,
                )
                match entry_values {
                  Some((raw_v, v)) => {
                    // PKL-148k: Apple Pkl rejects two entries that resolve
                    // to the same key inside a single Mapping body (even
                    // when the key expressions themselves are different
                    // string-concat compositions like `"barn owl"` and
                    // `"bar" + "n owl"`). The rejection text quotes the
                    // duplicate key via inline PCF render and aborts the
                    // whole literal — emit the first violation and skip
                    // the rest of the body. The check is restricted to
                    // scalar key shapes: composite-key equality
                    // (ObjectValue, ListingValue, MappingValue, ...)
                    // collapses without class identity, so two
                    // structurally-identical `new Dynamic {}` /
                    // `new Person {}` keys would false-positive as
                    // duplicates against `mappings/mapping1`. Composite
                    // keys fall through to the unchecked push until
                    // ObjectValue carries a class tag (PKL-148k full
                    // slice).
                    let is_scalar_key = match k {
                      IntValue(_)
                      | FloatValue(_)
                      | StringValue(_)
                      | BoolValue(_)
                      | NullValue
                      | DurationValue(_, _)
                      | DataSizeValue(_, _)
                      | RegexValue(_)
                      | BytesValue(_) => true
                      _ => false
                    }
                    let mut is_duplicate = false
                    if is_scalar_key {
                      for existing in values {
                        if existing.key == k {
                          is_duplicate = true
                          break
                        }
                      }
                    }
                    if is_duplicate {
                      if !duplicate_emitted {
                        diagnostics.push(
                          diag(
                            "Duplicate definition of member `\{render_pcf_value_inline(k)}`.",
                          ),
                        )
                        duplicate_emitted = true
                      }
                    } else {
                      raw_values.push({ key: k, value: raw_v })
                      values.push({ key: k, value: v })
                    }
                  }
                  None =>
                    if diagnostics.length() > value_diag_start {
                      let message = diagnostics[value_diag_start].message
                      while diagnostics.length() > value_diag_start {
                        let _ = diagnostics.pop()
                      }
                      let deferred = deferred_error_value(message)
                      let is_scalar_key = match k {
                        IntValue(_)
                        | FloatValue(_)
                        | StringValue(_)
                        | BoolValue(_)
                        | NullValue
                        | DurationValue(_, _)
                        | DataSizeValue(_, _)
                        | RegexValue(_)
                        | BytesValue(_) => true
                        _ => false
                      }
                      let mut is_duplicate = false
                      if is_scalar_key {
                        for existing in values {
                          if existing.key == k {
                            is_duplicate = true
                            break
                          }
                        }
                      }
                      if is_duplicate {
                        if !duplicate_emitted {
                          diagnostics.push(
                            diag(
                              "Duplicate definition of member `\{render_pcf_value_inline(k)}`.",
                            ),
                          )
                          duplicate_emitted = true
                        }
                      } else {
                        raw_values.push({ key: k, value: deferred })
                        values.push({ key: k, value: deferred })
                      }
                    }
                }
              }
              _ => ()
            }
          }
        }
      }
      if duplicate_emitted {
        None
      } else {
        match default_value {
          Some(default_v) =>
            Some(DefaultedMappingValue(raw_values, values, default_v))
          None => Some(MappingValue(values))
        }
      }
    }
    MemberAccess(target_expr, member_name) =>
      // PKL-139: `module.foo` is Apple Pkl's self-reference to the
      // current module's `foo` binding. Short-circuit the member access
      // to a direct binding lookup so the value is resolved through the
      // module's binding env rather than treating `module` as an
      // ordinary identifier (which would fail with "unbound identifier").
      // PKL-148ah: in `amends` / `extends` mode the child module's
      // bindings list only carries its own additions — parent-only
      // names (`a` in `moduleRefLibrary`) aren't reachable via
      // `find_binding(child_bindings, ...)`. Fall back to the parent
      // snapshot pushed as `super = ObjectValue(parent_members)` by
      // `eval_program` so `module.X` resolves through the merged
      // module surface instead of returning None.
      if target_expr is Identifier("super") &&
        lookup_value(cache, "@current_class") is Some(_) {
        match lookup_value(cache, "super") {
          Some(ObjectValue(parent_members)) =>
            match lookup_member(parent_members, member_name) {
              Some(value) => Some(value)
              None => {
                diagnostics.push(diag("Cannot find property `\{member_name}`."))
                None
              }
            }
          _ =>
            match lookup_value(cache, "this") {
              Some(ObjectValue(receiver_members)) =>
                match lookup_member(receiver_members, member_name) {
                  Some(value) => Some(value)
                  None => {
                    diagnostics.push(
                      diag("Cannot find property `\{member_name}`."),
                    )
                    None
                  }
                }
              _ => {
                diagnostics.push(diag("Cannot find property `super`."))
                None
              }
            }
        }
      } else if target_expr is Identifier("super") &&
        lookup_value(cache, "@current_class") is None &&
        module_super_members_from_cache(cache) is Some(parent_members) {
        match
          resolve_module_parent_member_value(
            member_name, parent_members, bindings, env, class_env, cache, stack,
            declarations, diagnostics, resolve_import,
          ) {
          Some(value) => Some(value)
          None => {
            diagnostics.push(diag("Cannot find property `\{member_name}`."))
            None
          }
        }
      } else if target_expr is Identifier("super") &&
        lookup_value(cache, "@current_class") is None &&
        object_super_members_from_cache(cache) is Some(super_members) {
        match
          resolve_object_super_member_value(
            member_name, super_members, bindings, env, class_env, cache, stack, declarations,
            diagnostics, resolve_import,
          ) {
          Some(value) => Some(value)
          None => {
            diagnostics.push(diag("Cannot find property `\{member_name}`."))
            None
          }
        }
      } else if target_expr is Identifier("module") {
        if lookup_value(cache, member_name) is None &&
          find_binding(bindings, member_name) is Some(_) {
          match lookup_value(cache, "outer") {
            Some(ObjectValue(snapshot)) =>
              if visible_members(snapshot).length() > 0 {
                return Some(ObjectValue(snapshot))
              }
            _ => ()
          }
        }
        if stack.length() > 0 && member_name == stack[stack.length() - 1] {
          match lookup_value(cache, "outer") {
            Some(ObjectValue(snapshot)) =>
              if visible_members(snapshot).length() > 0 {
                return Some(ObjectValue(snapshot))
              }
            _ => ()
          }
          let snapshot = dynamic_members_from_env(env)
          if snapshot.length() > 0 {
            return Some(ObjectValue(snapshot))
          }
        }
        match
          resolve_binding_value(
            member_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ) {
          Some(value) => Some(value)
          None =>
            match lookup_value(cache, "super") {
              Some(ObjectValue(parent_members)) =>
                lookup_member(parent_members, member_name)
              _ => None
            }
        }
      } else if target_expr is Identifier("this") &&
        (
          find_binding(bindings, member_name) is Some(_) ||
          lookup_value(env, member_name) is Some(_) ||
          lookup_value(cache, member_name) is Some(_)
        ) {
        // PKL-148g: `this.X` inside an object body resolves the same as
        // a bare `X` reference when `X` is in the implicit-receiver
        // scope (siblings + enclosing bindings). When `X` is a
        // value-derived property (e.g. `abs` on an Int receiver), fall
        // through to the standard member-access dispatch instead so the
        // runtime constraint helper's `this.abs < 100` rewrite still
        // resolves through `eval_int_property`.
        resolve_binding_value(
          member_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        )
      } else {
        match target_expr {
          Identifier(ns_name) => {
            let qualified_class_name = ns_name + "." + member_name
            match lookup_class_binding(class_env, qualified_class_name) {
              Some(_) =>
                return Some(synth_class_mirror_for_name(qualified_class_name))
              None => ()
            }
          }
          _ => ()
        }
        match
          eval_expr_with_bindings(
            target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ) {
          Some(DeferredImportValue(uri)) =>
            eval_deferred_import_member_access(
              uri, member_name, diagnostics, resolve_import,
            )
          Some(ObjectValue(members)) =>
            // PKL-143: if the object is a `pkl:reflect` mirror (carries
            // the hidden `__kind` marker), intercept introspection
            // members before the generic `lookup_member` path.
            match eval_reflect_type_property(members, member_name) {
              Some(value) => Some(value)
              None =>
                match reflect_kind(members) {
                  Some("Class") =>
                    match member_name {
                      "properties" =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None =>
                            match reflect_reflectee_name(members) {
                              Some(name) =>
                                if name == "module" {
                                  Some(
                                    reflect_module_class_properties(
                                      bindings, cache, declarations,
                                    ),
                                  )
                                } else {
                                  Some(
                                    reflect_class_properties(name, declarations),
                                  )
                                }
                              None => None
                            }
                        }
                      "methods" =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None =>
                            match reflect_reflectee_name(members) {
                              Some(name) =>
                                Some(reflect_class_methods(name, declarations))
                              None => None
                            }
                        }
                      "allProperties" =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None =>
                            match reflect_reflectee_name(members) {
                              Some(name) =>
                                Some(
                                  MapValue(
                                    reflect_class_all_property_entries(
                                      name,
                                      declarations,
                                      "",
                                      None,
                                      match
                                        lookup_value(cache, "@__module_path") {
                                        Some(StringValue(path)) => Some(path)
                                        _ => None
                                      },
                                      match
                                        lookup_value(cache, "@__module_source") {
                                        Some(StringValue(source)) =>
                                          Some(source)
                                        _ => None
                                      },
                                      [],
                                    ),
                                  ),
                                )
                              None => None
                            }
                        }
                      "supertype" =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None =>
                            match reflect_reflectee_name(members) {
                              Some(name) =>
                                Some(
                                  reflect_class_supertype(name, declarations),
                                )
                              None => None
                            }
                        }
                      _ =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None => {
                            // PKL-148d: Apple Pkl reports member-access
                            // failures on a Class mirror with a `in object
                            // of type Class` suffix so users see the
                            // class-as-value context.
                            diagnostics.push(
                              diag(
                                "Cannot find property `\{member_name}` in object of type `Class`.",
                              ),
                            )
                            None
                          }
                        }
                    }
                  Some("Module") =>
                    match member_name {
                      "classes" =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None => Some(reflect_module_classes(declarations))
                        }
                      _ =>
                        match lookup_member(members, member_name) {
                          Some(value) => Some(value)
                          None => {
                            diagnostics.push(
                              diag("Cannot find property `\{member_name}`."),
                            )
                            None
                          }
                        }
                    }
                  _ =>
                    // PKL-148u: a pending `@error$<name>` member from
                    // class-default structural rejection takes precedence
                    // — surface its message and short-circuit the lookup
                    // so `test.catch(() -> bad.res13)` catches just that
                    // property's rejection (not the first-encountered
                    // diagnostic of the surrounding class). The sibling
                    // member with the actual (type-invalid) value is left
                    // in place for equality / iteration but is unreachable
                    // through this lookup path.
                    if member_name == "output" {
                      match lookup_visible_member(members, "output") {
                        Some(ObjectValue(output_members)) =>
                          Some(
                            synthesize_output_text_member(
                              members, output_members,
                            ),
                          )
                        Some(value) => Some(value)
                        None => {
                          diagnostics.push(
                            diag(
                              "Cannot find property `output` in object of type `Dynamic`.",
                            ),
                          )
                          None
                        }
                      }
                    } else if is_semver_value_members(members) &&
                      (member_name == "preRelease" || member_name == "build") {
                      match lookup_visible_member(members, member_name) {
                        Some(value) => Some(value)
                        None => Some(NullValue)
                      }
                    } else {
                      match lookup_pending_error_message(members, member_name) {
                        Some(message) => {
                          diagnostics.push(diag(message))
                          None
                        }
                        None =>
                          // PKL-148j: external member access on an
                          // ObjectValue hides `local` members from the
                          // outside-of-body namespace (`foo.x` where `foo`
                          // declares `local x = 2` should not resolve to
                          // `2`); switch from the hidden-aware
                          // `lookup_member` to `lookup_visible_member` so
                          // the local slot is invisible here. Module-level
                          // function declarations are also stored under the
                          // hidden prefix (to keep them out of rendered
                          // output) but stay reachable to importers via
                          // `Base.func`, so a FunctionValue match through
                          // `lookup_member` is still allowed as a follow-up.
                          // The diagnostic matches Apple Pkl's wording (`in
                          // object of type \`Dynamic\``); class-tagged
                          // objects would carry their host class name
                          // instead, but until ObjectValue grows a class
                          // tag the best default is `Dynamic`.
                          match lookup_visible_member(members, member_name) {
                            Some(value) => Some(value)
                            None =>
                              match lookup_member(members, member_name) {
                                Some(FunctionValue(_, _, _, _, _) as exported) =>
                                  Some(exported)
                                _ =>
                                  match
                                    reflect_module_decl_member(
                                      members, member_name,
                                    ) {
                                    Some(value) => Some(value)
                                    None => {
                                      diagnostics.push(
                                        diag(
                                          "Cannot find property `\{member_name}` in object of type `Dynamic`.",
                                        ),
                                      )
                                      None
                                    }
                                  }
                              }
                          }
                      }
                    }
                }
            }
          Some(ListingValue(elements))
          | Some(DefaultedListingValue(_, elements, _)) =>
            if is_listing_property_name(member_name) {
              eval_listing_property(elements, member_name, diagnostics)
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Listing`.",
                ),
              )
              None
            }
          Some(ListValue(elements)) =>
            if is_listing_property_name(member_name) {
              match eval_listing_property(elements, member_name, diagnostics) {
                Some(ListingValue(xs)) => Some(ListValue(xs))
                other => other
              }
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Listing`.",
                ),
              )
              None
            }
          Some(MappingValue(entries))
          | Some(DefaultedMappingValue(_, entries, _)) =>
            if is_mapping_property_name(member_name) {
              eval_mapping_property(entries, member_name, diagnostics)
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Mapping`.",
                ),
              )
              None
            }
          Some(StringValue(s)) =>
            if is_string_property_name(member_name) {
              eval_string_property(s, member_name, diagnostics)
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `String`.",
                ),
              )
              None
            }
          Some(IntValue(n)) =>
            if is_duration_unit_name(member_name) {
              Some(DurationValue(n.to_double(), member_name))
            } else if is_datasize_unit_name(member_name) {
              Some(DataSizeValue(n.to_double(), member_name))
            } else if is_int_property_name(member_name) {
              eval_int_property(n, member_name, diagnostics)
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Int`.",
                ),
              )
              None
            }
          // PKL-121: same dispatch for Float magnitudes (`1.5.s`,
          // `2.5.gib`). The Duration / DataSize value carries the
          // Double magnitude verbatim.
          Some(FloatValue(d)) =>
            if is_duration_unit_name(member_name) {
              Some(DurationValue(d, member_name))
            } else if is_datasize_unit_name(member_name) {
              Some(DataSizeValue(d, member_name))
            } else if is_float_property_name(member_name) {
              eval_float_property(d, member_name, diagnostics)
            } else {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Float`.",
                ),
              )
              None
            }
          Some(DurationValue(n, unit)) =>
            eval_duration_property(n, unit, member_name, diagnostics)
          Some(DataSizeValue(n, unit)) =>
            eval_datasize_property(n, unit, member_name, diagnostics)
          Some(RegexValue(pattern)) =>
            eval_regex_property(pattern, member_name, diagnostics)
          Some(BytesValue(bytes)) =>
            eval_bytes_property(bytes, member_name, diagnostics)
          // PKL-119a: `.first` / `.second` reach the two ordered
          // elements directly off the dedicated `PairValue`. Other
          // member names surface the standard upstream wording so a
          // typo lands on the same error path as Listing / Mapping.
          Some(PairValue(first, second)) =>
            match member_name {
              "first" => Some(first)
              "second" => Some(second)
              // PKL-148: `.key` / `.value` are Apple Pkl's named aliases
              // for `.first` / `.second` — fixtures like `api/pair.pkl`
              // exercise both naming surfaces against the same Pair.
              "key" => Some(first)
              "value" => Some(second)
              _ => {
                diagnostics.push(
                  diag(
                    "Cannot find property `\{member_name}` in object of type `Pair`.",
                  ),
                )
                None
              }
            }
          // PKL-119b: `.start` / `.end` / `.step` reach the three Int
          // carrier slots directly. Bare `.step` (no call) returns the
          // step value; method form `.step(newValue)` is handled in
          // the CallExpr dispatcher.
          Some(IntSeqValue(start, end, step)) =>
            match member_name {
              "start" => Some(IntValue(start))
              "end" => Some(IntValue(end))
              "step" => Some(IntValue(step))
              _ => {
                diagnostics.push(
                  diag(
                    "Cannot find property `\{member_name}` in object of type `IntSeq`.",
                  ),
                )
                None
              }
            }
          // PKL-119c: SetValue's bare-property surface — `.length`,
          // `.isEmpty`, `.isNotEmpty`, `.first`, `.last`, `.distinct`
          // (identity since Set is already unique). Method names
          // (`.contains` / `.toList` / `.map` / `.filter` / `.fold`)
          // fall through to the CallExpr dispatcher.
          Some(SetValue(elements)) =>
            match member_name {
              "length" => Some(IntValue(elements.length().to_int64()))
              "isEmpty" => Some(BoolValue(elements.length() == 0))
              "isNotEmpty" => Some(BoolValue(elements.length() != 0))
              "first" =>
                if elements.length() == 0 {
                  diagnostics.push(diag("Set.first is empty"))
                  None
                } else {
                  value_or_deferred_diagnostic(elements[0], diagnostics)
                }
              "last" =>
                if elements.length() == 0 {
                  diagnostics.push(diag("Set.last is empty"))
                  None
                } else {
                  value_or_deferred_diagnostic(
                    elements[elements.length() - 1],
                    diagnostics,
                  )
                }
              "distinct" => Some(SetValue(elements))
              _ => {
                diagnostics.push(
                  diag(
                    "Cannot find property `\{member_name}` in object of type `Set`.",
                  ),
                )
                None
              }
            }
          // PKL-119d: MapValue's bare-property surface — `.length`,
          // `.isEmpty`, `.isNotEmpty`, `.keys` (Set of keys),
          // `.values` (List of values), `.entries` (List of
          // Pair<K, V>). Method names (`.getOrNull` / `.containsKey`
          // / `.toMap` / `.toMapping` / `.map` / `.filter` / `.fold`)
          // fall through to the CallExpr dispatcher.
          Some(MapValue(entries)) =>
            match member_name {
              "length" => Some(IntValue(entries.length().to_int64()))
              "isEmpty" => Some(BoolValue(entries.length() == 0))
              "isNotEmpty" => Some(BoolValue(entries.length() != 0))
              "keys" => {
                let keys : Array[Value] = []
                for entry in entries {
                  keys.push(entry.key)
                }
                Some(SetValue(keys))
              }
              "values" => {
                let values : Array[Value] = []
                for entry in entries {
                  values.push(entry.value)
                }
                Some(ListValue(values))
              }
              "entries" => {
                let pairs : Array[Value] = []
                for entry in entries {
                  pairs.push(PairValue(entry.key, entry.value))
                }
                Some(ListValue(pairs))
              }
              _ => {
                diagnostics.push(
                  diag(
                    "Cannot find property `\{member_name}` in object of type `Map`.",
                  ),
                )
                None
              }
            }
          Some(NullValue) => {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `Null`.",
              ),
            )
            None
          }
          Some(_) => {
            diagnostics.push(diag("member access expects Object"))
            None
          }
          None => None
        }
      }
    SafeMemberAccess(target_expr, member_name) =>
      match
        eval_expr_with_bindings(
          target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(NullValue) => Some(NullValue)
        Some(ObjectValue(members)) =>
          match lookup_member(members, member_name) {
            Some(value) => Some(value)
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              None
            }
          }
        Some(ListingValue(elements))
        | Some(DefaultedListingValue(_, elements, _))
        | Some(ListValue(elements)) =>
          if is_listing_property_name(member_name) {
            eval_listing_property(elements, member_name, diagnostics)
          } else {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `Listing`.",
              ),
            )
            None
          }
        Some(MappingValue(entries))
        | Some(DefaultedMappingValue(_, entries, _)) =>
          if is_mapping_property_name(member_name) {
            eval_mapping_property(entries, member_name, diagnostics)
          } else {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `Mapping`.",
              ),
            )
            None
          }
        Some(StringValue(s)) =>
          if is_string_property_name(member_name) {
            eval_string_property(s, member_name, diagnostics)
          } else {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `String`.",
              ),
            )
            None
          }
        Some(IntValue(n)) =>
          if is_duration_unit_name(member_name) {
            Some(DurationValue(n.to_double(), member_name))
          } else if is_datasize_unit_name(member_name) {
            Some(DataSizeValue(n.to_double(), member_name))
          } else if is_int_property_name(member_name) {
            eval_int_property(n, member_name, diagnostics)
          } else {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `Int`.",
              ),
            )
            None
          }
        // PKL-121: SafeMemberAccess version of the Float-magnitude
        // unit dispatch (`(maybeFloat ?? 0.5).s`).
        Some(FloatValue(d)) =>
          if is_duration_unit_name(member_name) {
            Some(DurationValue(d, member_name))
          } else if is_datasize_unit_name(member_name) {
            Some(DataSizeValue(d, member_name))
          } else if is_float_property_name(member_name) {
            eval_float_property(d, member_name, diagnostics)
          } else {
            diagnostics.push(
              diag(
                "Cannot find property `\{member_name}` in object of type `Float`.",
              ),
            )
            None
          }
        Some(DurationValue(n, unit)) =>
          eval_duration_property(n, unit, member_name, diagnostics)
        Some(DataSizeValue(n, unit)) =>
          eval_datasize_property(n, unit, member_name, diagnostics)
        Some(RegexValue(pattern)) =>
          eval_regex_property(pattern, member_name, diagnostics)
        Some(BytesValue(bytes)) =>
          eval_bytes_property(bytes, member_name, diagnostics)
        Some(_) => {
          diagnostics.push(diag("safe member access expects Object"))
          None
        }
        None => None
      }
    SubscriptAccess(target_expr, key_expr) => {
      let key = eval_expr_with_bindings(
        key_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      if target_expr is Identifier("super") &&
        lookup_value(env, "super") is None &&
        lookup_value(cache, "super") is None {
        match key {
          Some(_) => return Some(ObjectValue([]))
          None => return None
        }
      }
      let target = eval_expr_with_bindings(
        target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      match (target, key) {
        (Some(ListingValue(elements)), Some(IntValue(index64)))
        | (Some(DefaultedListingValue(_, elements, _)), Some(IntValue(index64)))
        | (Some(ListValue(elements)), Some(IntValue(index64)))
        | (Some(SetValue(elements)), Some(IntValue(index64))) =>
          if index64 >= 0L && index64 < elements.length().to_int64() {
            let index = index64.to_int()
            match deferred_error_message(elements[index]) {
              Some(message) => {
                diagnostics.push(
                  diag(
                    adjust_deferred_listing_error_message(
                      message,
                      elements.length() - 1,
                    ),
                  ),
                )
                None
              }
              None => Some(elements[index])
            }
          } else {
            let upper = elements.length() - 1
            match target {
              Some(ListValue(_) as v) =>
                diagnostics.push(
                  diag(
                    "Element index `\{format_int_with_commas(index64)}` is out of range `0`..`\{upper}`. Collection: \{render_pcf_value_inline(v)}",
                  ),
                )
              _ =>
                diagnostics.push(
                  diag(
                    "Element index `\{format_int_with_commas(index64)}` is out of range `0`..`\{upper}`.",
                  ),
                )
            }
            None
          }
        (Some(ListingValue(_)), Some(key_value))
        | (Some(DefaultedListingValue(_, _, _)), Some(key_value))
        | (Some(ListValue(_)), Some(key_value))
        | (Some(SetValue(_)), Some(key_value)) => {
          // PKL-148bb: align with Apple Pkl wording so `test.catch`
          // snapshots in `listings/listing2.res8` round-trip.
          let actual = eval_value_type_name(key_value)
          diagnostics.push(
            diag("Expected key of type `Int`, but got type `\{actual}`."),
          )
          None
        }
        (Some(ObjectValue(members)), Some(key_value)) =>
          match
            dynamic_object_subscript_value(members, key_value, diagnostics) {
            Some(value) =>
              match deferred_error_message(value) {
                Some(message) => {
                  diagnostics.push(diag(message))
                  None
                }
                None => Some(value)
              }
            None => {
              diagnostics.push(
                diag("Cannot find key `\{render_pcf_value_inline(key_value)}`."),
              )
              None
            }
          }
        (Some(MappingValue(entries)), Some(key_value))
        | (Some(MapValue(entries)), Some(key_value))
        | (Some(DefaultedMappingValue(_, entries, _)), Some(key_value)) =>
          match lookup_entry(entries, key_value) {
            Some(value) =>
              match deferred_error_message(value) {
                Some(message) => {
                  diagnostics.push(diag(message))
                  None
                }
                None => Some(value)
              }
            None => {
              diagnostics.push(
                diag("Cannot find key `\{render_pcf_value_inline(key_value)}`."),
              )
              None
            }
          }
        // PKL-148bh / PKL-152: String subscript indexes by code point
        // (Apple Pkl semantics). `s[i]` returns the i-th code point as
        // a one-character String — surrogate pairs count as a single
        // unit so `"🙈🙉🙊🐒"[2] == "🙊"` and the upper bound is the
        // code-point count, not the UTF-16 code-unit length.
        (Some(BytesValue(bytes)), Some(IntValue(index64))) => {
          let index = index64.to_int()
          if index64 >= 0L && index < bytes.length() {
            Some(IntValue(bytes[index].to_int().to_int64()))
          } else {
            diagnostics.push(
              diag(
                "Element index `\{format_int_with_commas(index64)}` is out of range `0`..`\{bytes.length() - 1}`. Value: \{render_bytes_value_inline(bytes)}",
              ),
            )
            None
          }
        }
        (Some(BytesValue(_)), Some(key_value)) => {
          let actual = eval_value_type_name(key_value)
          diagnostics.push(
            diag("Expected key of type `Int`, but got type `\{actual}`."),
          )
          None
        }
        (Some(StringValue(s)), Some(IntValue(index64))) => {
          let code_points : Array[String] = []
          for c in s.iter() {
            code_points.push(String::from_array([c][:]))
          }
          let index = index64.to_int()
          if index64 >= 0L && index < code_points.length() {
            Some(StringValue(code_points[index]))
          } else {
            let buf = StringBuilder::new()
            render_pcf_scalar(StringValue(s), buf)
            diagnostics.push(
              diag(
                "Character index `\{index64}` is out of range `0`..`\{code_points.length() - 1}`. String: \{buf.to_string()}",
              ),
            )
            None
          }
        }
        (Some(_), Some(_)) => {
          diagnostics.push(diag("subscript access expects Listing or Mapping"))
          None
        }
        _ => None
      }
    }
    AmendExpr(base_expr, members) => {
      let amend_base_expr = match
        null_default_expr_for_amend(base_expr, bindings) {
        Some(default_expr) => default_expr
        None => base_expr
      }
      match
        eval_expr_with_bindings(
          amend_base_expr, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        ) {
        Some(ObjectValue(base_members)) => {
          // PKL-148e: thread `super` into the body cache. `(target)
          // { body }` lets the body reference `super.X` to read the
          // pre-amend value of property `X` on the target, matching
          // Apple Pkl's amend-chain semantics in `objects/super1` and
          // friends.
          let amend_cache = copy_value_bindings(cache)
          amend_cache.push({ name: "super", value: ObjectValue(base_members) })
          // PKL-148bh: bind `this` to the pre-amend base inside the
          // amend body so an inline lambda body like
          // `y = (() -> this.x).apply() + 1` reaches the enclosing
          // amend target's properties (objects/this2). Apple Pkl
          // re-binds `this` at every nested amend / new layer; the
          // base-members snapshot is a reasonable approximation for
          // properties that don't require the not-yet-merged overrides.
          amend_cache.push({ name: "this", value: ObjectValue(base_members) })
          // Dynamic objects that contain only bracket entries behave like a
          // Mapping for predicate members and generator-scoped predicate
          // members. Route that shape through the Mapping amend path so
          // `new Dynamic { ["k"] { ... } }` preserves key/value semantics.
          if amend_members_need_mapping_member_semantics(members) {
            match dynamic_mapping_entries_from_members(base_members) {
              Some(entries) =>
                return eval_mapping_amend(
                  entries,
                  members,
                  bindings,
                  env,
                  class_env,
                  amend_cache,
                  stack,
                  declarations,
                  None,
                  diagnostics,
                  resolve_import,
                )
              None => ()
            }
          }
          // PKL-148ar: `[[ pred ]] { body }` predicate-member fires
          // against the base's Dynamic-shape entries (`@element$` for
          // bare elements, `@subscript$` for `[key]` entries). Split
          // the amend body into predicate members and regular members;
          // process predicates first by filtering / amending the base
          // entries, then merge the regular members on the modified
          // base. Without this preprocessing, `eval_object_members`
          // would eval the `@predicate$<offset>` member's CallExpr
          // body and surface `Cannot find property @__predicate_entry`.
          let predicate_members : Array[ObjectMember] = []
          let regular_members : Array[ObjectMember] = []
          for m in members {
            if m.name.has_prefix("@predicate$") {
              predicate_members.push(m)
            } else {
              regular_members.push(m)
            }
          }
          let modified_base = if predicate_members.length() == 0 {
            base_members
          } else {
            apply_predicate_members_to_object(
              base_members, predicate_members, bindings, env, class_env, amend_cache,
              stack, declarations, diagnostics, resolve_import,
            )
          }
          let evaluated_regular = eval_object_members(
            regular_members, bindings, env, class_env, amend_cache, stack, declarations,
            diagnostics, resolve_import,
          )
          let merged = merge_objects_with_late_binding(
            modified_base, evaluated_regular, bindings, env, class_env, amend_cache,
            stack, declarations, diagnostics, resolve_import,
          )
          // Fire class-property constraints against amend bodies that
          // target a typed receiver (`(counter) { y = 0 }` where
          // `counter: Counter`). TypedObjectLiteral runs the same
          // cascade at construction; AmendExpr needs to repeat it so
          // `test.catch` can capture predicate / type-annotation
          // violations on amend chains (constraints11, constraints12).
          let amend_class_name = match
            typed_object_class_name_for_expr(amend_base_expr, bindings, []) {
            Some(name) => Some(name)
            None => find_object_class_tag(base_members)
          }
          let mut violation_emitted = false
          match amend_class_name {
            Some(type_name) =>
              for field in regular_members {
                match lookup_member(merged, field.name) {
                  Some(member_value) => {
                    let value_skips_type_check = match field.value {
                      Identifier(_) => true
                      _ => false
                    }
                    let type_message = if !value_skips_type_check {
                      eval_class_property_type_rejection_message(
                        type_name,
                        field.name,
                        member_value,
                        declarations,
                      )
                    } else {
                      None
                    }
                    match type_message {
                      Some(message) => {
                        diagnostics.push(diag(message))
                        violation_emitted = true
                      }
                      None =>
                        match
                          eval_class_property_constraint_value_rejection_message(
                            type_name,
                            field.name,
                            member_value,
                            declarations,
                          ) {
                          Some(message) => {
                            diagnostics.push(diag(message))
                            violation_emitted = true
                          }
                          None =>
                            match
                              eval_runtime_constraint_for_property(
                                type_name,
                                field.name,
                                member_value,
                                merged,
                                bindings,
                                env,
                                class_env,
                                cache,
                                stack,
                                declarations,
                                resolve_import,
                              ) {
                              Some(message) => {
                                diagnostics.push(diag(message))
                                violation_emitted = true
                              }
                              None => ()
                            }
                        }
                    }
                  }
                  None => ()
                }
              }
            None => ()
          }
          if violation_emitted {
            None
          } else {
            Some(ObjectValue(add_object_super_metadata(merged, modified_base)))
          }
        }
        Some(FunctionValue(_, _, _, _, _) as fn_value) =>
          Some(build_function_amend_value(fn_value, members, env, cache))
        Some(ListingValue(elements)) =>
          // PKL-148w: `(listing) { [N] = newValue }` replaces element
          // N. Out-of-range indices surface Apple Pkl's wording
          // (`Element index \`<n>\` is out of range \`0\`..\`<upper>\`.`).
          // Members that aren't `@subscript$...` are deferred to a
          // follow-up (`(listing) { name = "..." }` mixing element
          // overrides with property-style amends).
          eval_listing_subscript_amend(
            elements,
            members,
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            None,
            diagnostics,
            resolve_import,
          )
        Some(DefaultedListingValue(raw_elements, _, default_value)) =>
          eval_listing_subscript_amend(
            raw_elements,
            members,
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            Some(default_value),
            diagnostics,
            resolve_import,
          )
        // PKL-152: amending a List / Set / Map is rejected with the
        // external-class wording (mappings/listings/listings2 wrongParent).
        Some(ListValue(_)) => {
          diagnostics.push(
            diag(
              "Cannot instantiate, or amend an instance of, external class `List`.",
            ),
          )
          None
        }
        Some(SetValue(_)) => {
          diagnostics.push(
            diag(
              "Cannot instantiate, or amend an instance of, external class `Set`.",
            ),
          )
          None
        }
        Some(MapValue(_)) => {
          diagnostics.push(
            diag(
              "Cannot instantiate, or amend an instance of, external class `Map`.",
            ),
          )
          None
        }
        Some(MappingValue(entries)) =>
          // PKL-148av: `(mapping) { [key] = value }` upserts the entry,
          // and `(mapping) { [key] { body } }` amends an existing entry.
          // Named properties (`default = X`) are silently skipped — same
          // reasoning as the Listing path above.
          eval_mapping_amend(
            entries,
            members,
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            None,
            diagnostics,
            resolve_import,
          )
        Some(DefaultedMappingValue(raw_entries, _, default_value)) =>
          eval_mapping_amend(
            raw_entries,
            members,
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            Some(default_value),
            diagnostics,
            resolve_import,
          )
        Some(other_value) => {
          // PKL-152: Apple Pkl's `(5) { ... }` raises
          // "Cannot instantiate, or amend an instance of, external
          // class `Int`." — same wording for any scalar / collection
          // (List / Set / Map / etc.) the user tried to amend in place.
          let type_name = eval_value_type_name(other_value)
          diagnostics.push(
            diag(
              "Cannot instantiate, or amend an instance of, external class `\{type_name}`.",
            ),
          )
          None
        }
        None => None
      }
    }
    Identifier(name) =>
      // PKL-148ak: when a sibling local member's eval landed a
      // deferred per-property rejection (the `@error$<bare>` env
      // entry hoisted by `eval_object_members`), surface that
      // diagnostic before resolving the bare-name value. The
      // sentinel only lives in env when the surrounding body ran
      // with `defer_property_errors=true` (class default eval); for
      // every other site the lookup misses and the normal resolver
      // runs unchanged. `test.catch(() -> bad_local)` captures the
      // surfaced diagnostic — without this intercept the lambda
      // body read the type-invalid value directly, no throw, and
      // `test.catch` reported `Expected an exception, but none was
      // thrown.` (gold expected the rejection message).
      if lookup_value(env, error_member_name(name))
        is Some(StringValue(message)) {
        diagnostics.push(diag(message))
        None
      } else if name == "NaN" &&
        !stack_contains_binding(stack, "NaN") &&
        find_binding(bindings, "NaN") is None &&
        lookup_value(env, "NaN") is None &&
        lookup_value(cache, "NaN") is None {
        // pkl:base `NaN` constant — IEEE 754 Not-a-Number sentinel.
        Some(FloatValue(0.0 / 0.0))
      } else if name == "Infinity" &&
        !stack_contains_binding(stack, "Infinity") &&
        find_binding(bindings, "Infinity") is None &&
        lookup_value(env, "Infinity") is None &&
        lookup_value(cache, "Infinity") is None {
        // pkl:base `Infinity` constant — IEEE 754 positive infinity.
        Some(FloatValue(1.0 / 0.0))
      } else if name == "module" ||
        (
          name == "this" &&
          lookup_value(env, "this") is None &&
          lookup_value(cache, "this") is None
        ) {
        // Apple Pkl exposes the current module as the identifier
        // `module`. The value is the ObjectValue of every
        // already-evaluated module-level binding — the snapshot lives
        // in `cache` (populated by `eval_program` after each binding
        // resolves). Stdlib markers (`super`, `this`, `@current_class`)
        // are filtered out so a downstream `module.X` resolves only
        // through the user-visible bindings, and an inline render
        // doesn't surface them. Bare `this` at module top level (no
        // enclosing class / object body has pushed a `this` binding)
        // resolves to the same module ObjectValue — `types/objects/this2`
        // exercises `res1 = (this) { x = 42 }`.
        Some(
          module_object_value_from_scope(
            bindings,
            env,
            cache,
            stack,
            const_context=false,
          ),
        )
      } else {
        match
          resolve_binding_value(
            name, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ) {
          Some(value) => Some(value)
          None => {
            // PKL-148bh: when the source declared `module Foo`, the
            // qualified name `Foo#Bar` is what Apple Pkl returns from
            // Class.toString / TypeAlias.toString. The marker was
            // stashed at eval_program time.
            let module_name = match lookup_value(cache, "@__module_name") {
              Some(StringValue(s)) => Some(s)
              _ => None
            }
            // PKL-148d: a bare class name (`Person`) used as a value
            // projects to a `pkl:reflect.Class` mirror. This unlocks
            // `Person.foo` / `Person.bar()` failure paths that snippetTest
            // captures via `test.catch(...)`, plus future Class-arg APIs.
            match lookup_class_binding(class_env, name) {
              Some(_) =>
                Some(synth_class_mirror_for_qualified(name, module_name))
              None =>
                // PKL-148e: stdlib type names (`Int` / `Float` / `String`
                // / ...) also project to a Class mirror so equality and
                // comparison fixtures (`Int == Int`, `Int == 3.getClass()`)
                // round-trip without a user class declaration.
                if is_stdlib_class_name(name) {
                  Some(synth_class_mirror_for_name(name))
                } else {
                  // PKL-148bb: a user-declared `typealias Bar = Foo`
                  // surfaces as a TypeAlias mirror with the same
                  // shape `pkl:reflect.TypeAlias(name)` would build —
                  // `Bar.toString()` / `Bar.simpleName` round-trip.
                  let mut has_alias = false
                  for decl in declarations {
                    if decl is TypeAliasDeclaration(td) && td.name == name {
                      has_alias = true
                      break
                    }
                  }
                  if has_alias {
                    Some(
                      synth_type_alias_mirror_for_qualified(name, module_name),
                    )
                  } else {
                    diagnostics.push(diag("Cannot find property `\{name}`."))
                    None
                  }
                }
            }
          }
        }
      }
    CallExpr(callee, arguments) =>
      if eval_xml_constructor_call(
          callee, arguments, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        )
        is Some(xml_value) {
        Some(xml_value)
      } else if callee is Identifier("@__typed_listing") &&
        arguments.length() == 2 {
        match arguments[0] {
          StringLiteral(type_name) =>
            match
              eval_expr_with_bindings(
                arguments[1],
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              ) {
              Some(value) =>
                match
                  cast_value_to_type_annotation(
                    type_name, value, bindings, env, class_env, cache, stack, declarations,
                    resolve_import,
                  ) {
                  TypeCastOk(casted) =>
                    match
                      binding_collection_host_constraint_rejection_message(
                        Some(type_name),
                        casted,
                        declarations,
                      ) {
                      Some(message) => Some(deferred_error_value(message))
                      None => Some(casted)
                    }
                  TypeCastErr(message) => Some(deferred_error_value(message))
                }
              None => None
            }
          _ => None
        }
      } else if callee is Identifier("Bytes") &&
        !stack_contains_binding(stack, "Bytes") &&
        find_binding(bindings, "Bytes") is None {
        // PKL-083 / PKL-148ax: `Bytes(...)` accepts either the legacy
        // `Bytes(<Listing of Int>)` shape or Apple Pkl's varargs form.
        // Each element is validated 0..=255 inside
        // `build_bytes_from_int_listing`.
        if arguments.length() == 0 {
          build_bytes_from_int_listing([], diagnostics)
        } else if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(ListingValue(elements))
            | Some(DefaultedListingValue(_, elements, _))
            | Some(ListValue(elements)) =>
              build_bytes_from_int_listing(elements, diagnostics)
            Some(IntValue(n)) =>
              build_bytes_from_int_listing([IntValue(n)], diagnostics)
            Some(_) => {
              diagnostics.push(diag("Bytes expects a Listing of Int"))
              None
            }
            None => None
          }
        } else {
          let elements : Array[Value] = []
          let mut ok = true
          for argument in arguments {
            match
              eval_expr_with_bindings(
                argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
                resolve_import,
              ) {
              Some(IntValue(n)) => elements.push(IntValue(n))
              Some(_) => {
                diagnostics.push(diag("Bytes expects Int arguments"))
                ok = false
              }
              None => ok = false
            }
          }
          if ok {
            build_bytes_from_int_listing(elements, diagnostics)
          } else {
            None
          }
        }
      } else if callee is MemberAccess(Identifier("Bytes"), "fromBase64") &&
        !stack_contains_binding(stack, "Bytes") &&
        find_binding(bindings, "Bytes") is None {
        // PKL-083: `Bytes.fromBase64("<base64>")` static-style decoder.
        // Decoding errors surface as a diagnostic carrying the base64
        // engine's own message.
        if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(StringValue(encoded)) =>
              Some(BytesValue(@base64.decode(encoded[:]))) catch {
                _ => {
                  diagnostics.push(
                    diag("Bytes.fromBase64: malformed base64 input"),
                  )
                  None
                }
              }
            Some(_) => {
              diagnostics.push(
                diag("Bytes.fromBase64 expects a String argument"),
              )
              None
            }
            None => None
          }
        } else {
          diagnostics.push(
            diag("Bytes.fromBase64 expects exactly one argument"),
          )
          None
        }
      } else if (
          (
            callee is MemberAccess(Identifier("module"), "catch") &&
            !stack_contains_binding(stack, "catch")
          ) ||
          (
            callee is MemberAccess(Identifier("test"), "catch") &&
            !stack_contains_binding(stack, "catch") &&
            find_binding(bindings, "catch") is None
          )
        ) &&
        arguments.length() == 1 {
        // PKL-147: snippetTest fixtures call `module.catch(lambda)` to
        // probe whether the lambda throws. Reuse the binding-time
        // intercept by reconstructing the surface form recognised by
        // `pkl_test_catch_lambda_body` and routing through
        // `eval_pkl_test_catch_binding_value`. Lambdas with non-zero
        // arity fall through to the generic CallExpr path so a future
        // proper `catch` member can take over.
        eval_pkl_test_catch_binding_value(
          CallExpr(callee, arguments),
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          resolve_import,
        )
      } else if (
          (
            callee is MemberAccess(Identifier("module"), "catchOrNull") &&
            !stack_contains_binding(stack, "catchOrNull")
          ) ||
          (
            callee is MemberAccess(Identifier("test"), "catchOrNull") &&
            !stack_contains_binding(stack, "catchOrNull") &&
            find_binding(bindings, "catchOrNull") is None
          )
        ) &&
        arguments.length() == 1 {
        // PKL-148o: `catchOrNull(fun)` mirrors `catch(fun)` but the
        // no-throw branch returns `null` instead of throwing — used
        // throughout the snippetTest examples blocks to project
        // "did this throw?" as a Boolean (`catchOrNull(...) == null`).
        eval_pkl_test_catch_or_null_binding_value(
          CallExpr(callee, arguments),
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          resolve_import,
        )
      } else if callee is Identifier("throw") &&
        !stack_contains_binding(stack, "throw") &&
        find_binding(bindings, "throw") is None {
        // PKL-084 split-1: `throw("...")` aborts evaluation by pushing a
        // diagnostic carrying the message verbatim and returning no value.
        // The message must evaluate to a String — anything else is a
        // dedicated diagnostic rather than the user-supplied one so the
        // origin of the failure stays unambiguous.
        if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(StringValue(message)) => {
              diagnostics.push(diag(message))
              None
            }
            Some(_) => {
              diagnostics.push(diag("throw expects a String argument"))
              None
            }
            None => None
          }
        } else {
          diagnostics.push(diag("throw expects exactly one argument"))
          None
        }
      } else if callee is Identifier("read") &&
        !stack_contains_binding(stack, "read") &&
        find_binding(bindings, "read") is None {
        // PKL-098: `read(uri)` evaluates the URI string and dispatches by
        // scheme prefix. The sandbox policy is explicit: only `env:` is
        // currently on the allow-list, all other schemes (`prop:`,
        // `file:`, `https:`, etc.) surface a diagnostic naming the
        // offending scheme rather than silently failing or escaping to
        // the host. The `read?(uri)` null-returning variant requires
        // parser support and stays deferred.
        if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(StringValue(uri)) =>
              eval_read_uri(
                uri,
                current_module_path_from_cache(cache),
                diagnostics,
              )
            Some(_) => {
              diagnostics.push(diag("read expects a String argument"))
              None
            }
            None => None
          }
        } else {
          diagnostics.push(diag("read expects exactly one argument"))
          None
        }
      } else if callee is Identifier("read*") {
        if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(StringValue(pattern)) =>
              eval_read_glob(
                pattern,
                current_module_path_from_cache(cache),
                diagnostics,
              )
            Some(_) => {
              diagnostics.push(diag("read* expects a String argument"))
              None
            }
            None => None
          }
        } else {
          diagnostics.push(diag("read* expects exactly one argument"))
          None
        }
      } else if callee is Identifier("trace") &&
        !stack_contains_binding(stack, "trace") &&
        find_binding(bindings, "trace") is None {
        // PKL-084 split-1: `trace(value)` evaluates the argument and
        // returns it verbatim. Apple Pkl additionally writes the value to
        // stderr as a side effect; the diagnostic-surface piece of that
        // contract is deferred to a follow-up slice because the only
        // observable channel for a stderr stamp lives in the CLI layer
        // and would expand the slice into renderer + diagnostic territory.
        if arguments.length() == 1 {
          eval_expr_with_bindings(
            arguments[0],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
        } else {
          diagnostics.push(diag("trace expects exactly one argument"))
          None
        }
      } else if (callee is Identifier("List") || callee is Identifier("Set")) &&
        (
          (
            callee is Identifier("List") &&
            !stack_contains_binding(stack, "List") &&
            find_binding(bindings, "List") is None
          ) ||
          (
            callee is Identifier("Set") &&
            !stack_contains_binding(stack, "Set") &&
            find_binding(bindings, "Set") is None
          )
        ) {
        // PKL-139: `List(...)` / `Set(...)` are Apple Pkl's constructor
        // functions for the immutable indexed collection and the
        // unordered unique collection. pkl-mbt collapses `List` and
        // `Listing` into the same `ListingValue` until PKL-119 splits
        // Set / Pair / Map / IntSeq variants out; both forms produce
        // `ListingValue` here. The behavioural difference (Set ignores
        // duplicates) is the only divergence: we project Set's args
        // through `distinct` so chained operations behave correctly.
        let arg_values : Array[Value] = []
        let mut ok = true
        for argument in arguments {
          match
            eval_expr_with_bindings(
              argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
            ) {
            Some(v) => arg_values.push(v)
            None => ok = false
          }
        }
        if !ok {
          None
        } else if callee is Identifier("Set") {
          // PKL-119c: Set carries the dedicated `SetValue` variant so
          // PCF round-trips through the `Set(...)` constructor form
          // and the typechecker distinguishes it from `Listing<T>`.
          // Duplicates are dropped at construction; insertion order
          // is preserved.
          let unique : Array[Value] = []
          for v in arg_values {
            if !contains_value(unique, v) {
              unique.push(v)
            }
          }
          Some(SetValue(unique))
        } else {
          // PKL-148h: `List(...)` lands in the dedicated `ListValue`
          // variant. Element-level operations (`+`, subscript, length,
          // method dispatch) treat List/Listing/Set uniformly; only the
          // PCF rendering and the type-tag diverge.
          Some(ListValue(arg_values))
        }
      } else if callee is Identifier("Map") &&
        !stack_contains_binding(stack, "Map") &&
        find_binding(bindings, "Map") is None {
        // PKL-119d: Apple Pkl's `Map(k1, v1, k2, v2, ...)` constructor
        // builds an immutable functional map. Arguments come in
        // alternating `key, value` pairs; later duplicate keys
        // overwrite earlier ones (matching upstream Map semantics).
        // The result is the dedicated `MapValue` variant — distinct
        // from `MappingValue` (the object-style `new Mapping { ... }`
        // form) so PCF round-trips through the constructor form and
        // the typechecker keeps `Map<K, V>` separate from
        // `Mapping<K, V>`.
        if arguments.length() % 2 != 0 {
          diagnostics.push(
            diag(
              "Map expects an even number of arguments (alternating key, value)",
            ),
          )
          None
        } else {
          let entries : Array[ValueEntry] = []
          let mut ok = true
          let mut i = 0
          while i < arguments.length() {
            let key_v = eval_expr_with_bindings(
              arguments[i],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            let value_v = eval_expr_with_bindings(
              arguments[i + 1],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            match (key_v, value_v) {
              (Some(k), Some(v)) => {
                // Overwrite earlier same-key entries so the carrier
                // matches upstream functional-map semantics.
                let mut replaced = false
                for j = 0; j < entries.length(); j = j + 1 {
                  if entries[j].key == k {
                    entries[j] = { key: k, value: v }
                    replaced = true
                    break
                  }
                }
                if !replaced {
                  entries.push({ key: k, value: v })
                }
              }
              _ => ok = false
            }
            i = i + 2
          }
          if ok {
            Some(MapValue(entries))
          } else {
            None
          }
        }
      } else if callee is Identifier("IntSeq") &&
        !stack_contains_binding(stack, "IntSeq") &&
        find_binding(bindings, "IntSeq") is None {
        // PKL-119b: `IntSeq(start, end)` constructs an `IntSeqValue`
        // with step = 1. The `step` knob is set later via
        // `IntSeq(...).step(n)` rather than a third constructor
        // argument, matching Apple Pkl's two-arg constructor surface.
        if arguments.length() != 2 {
          diagnostics.push(diag("IntSeq expects exactly two arguments"))
          None
        } else {
          let start = eval_expr_with_bindings(
            arguments[0],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
          let end_v = eval_expr_with_bindings(
            arguments[1],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
          match (start, end_v) {
            (Some(IntValue(s)), Some(IntValue(e))) => Some(IntSeqValue(s, e, 1))
            (Some(_), Some(_)) => {
              diagnostics.push(diag("IntSeq expects Int arguments"))
              None
            }
            _ => None
          }
        }
      } else if callee is Identifier("_pkl_shell_escape_single_quote") &&
        arguments.length() == 1 {
        // PKL-148bh: `pkl:shell.escapeWithSingleQuotes(str)` intrinsic.
        // Split on `'`, wrap each non-empty piece in single quotes,
        // join with `\'` (escaped single quote). The empty pieces
        // between consecutive `'`s collapse into doubled escapes —
        // `"abc'def''ghi"` becomes `'abc'\''def'\'\''ghi'`.
        match
          eval_expr_with_bindings(
            arguments[0],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(StringValue(s)) => {
            let pieces : Array[String] = []
            let cur = StringBuilder::new()
            for c in s {
              if c == '\'' {
                pieces.push(cur.to_string())
                cur.reset()
              } else {
                cur.write_char(c)
              }
            }
            pieces.push(cur.to_string())
            let out = StringBuilder::new()
            for i = 0; i < pieces.length(); i = i + 1 {
              if i > 0 {
                out.write_string("\\'")
              }
              if pieces[i] != "" {
                out.write_char('\'')
                out.write_string(pieces[i])
                out.write_char('\'')
              }
            }
            Some(StringValue(out.to_string()))
          }
          Some(_) => {
            diagnostics.push(
              diag("escapeWithSingleQuotes expects a String argument"),
            )
            None
          }
          None => None
        }
      } else if callee is Identifier("getClass") &&
        arguments.length() == 0 &&
        !stack_contains_binding(stack, "getClass") &&
        find_binding(bindings, "getClass") is None &&
        lookup_value(env, "getClass") is None &&
        lookup_value(cache, "getClass") is None {
        // pkl:base `getClass()` (bare, no receiver) inside an object
        // body reads the class-being-constructed marker. Apple Pkl
        // plumbs the implicit-receiver chain so a property body or a
        // typed method body says `getClass().simpleName` for the
        // surrounding type's `pkl:reflect.Class` mirror
        // (basic/newInAmendingModuleMethod). When the marker is
        // missing (bare module top level), fall back to "Dynamic".
        let class_name = match lookup_value(cache, "@__constructing_class") {
          Some(StringValue(s)) => s
          _ => "Dynamic"
        }
        // PKL-152: qualify the mirror's `name` with the surrounding
        // module so reflect.Class.toString agrees with Apple Pkl. The
        // stdlib classes ("Dynamic" / "Listing" / etc.) stay bare —
        // qualifying them would break api/reflect* expectations.
        let module_name = match lookup_value(cache, "@__module_name") {
          Some(StringValue(s)) => s
          _ => ""
        }
        if module_name.length() > 0 && !is_stdlib_class_name(class_name) {
          Some(synth_class_mirror_for_qualified(class_name, Some(module_name)))
        } else {
          Some(synth_class_mirror_for_name(class_name))
        }
      } else if callee is Identifier("TODO") &&
        !stack_contains_binding(stack, "TODO") &&
        find_binding(bindings, "TODO") is None {
        // pkl:base `TODO(message?)` always throws — Apple Pkl raises
        // "TODO" by default (or the supplied message). The fixture
        // captures via test.catch.
        diagnostics.push(diag("TODO"))
        None
      } else if callee is Identifier("Undefined") &&
        !stack_contains_binding(stack, "Undefined") &&
        find_binding(bindings, "Undefined") is None {
        // pkl:base `Undefined()` throws Apple Pkl's "Undefined value."
        // wording — used inside test.catch to confirm the throw fires.
        diagnostics.push(diag("Undefined value."))
        None
      } else if callee is Identifier("Null") &&
        !stack_contains_binding(stack, "Null") &&
        find_binding(bindings, "Null") is None {
        // pkl:base `Null(defaultValue)` always returns NullValue —
        // the argument is purely a type-inference carrier so the
        // host can synthesise a typed null without spelling out
        // `null as T`. The argument is intentionally NOT evaluated:
        // Apple Pkl treats it as a lazy thunk, and patterns like
        // `class Bad { res24c: NonNull = Null(new Bad {}) }` would
        // otherwise recurse indefinitely while constructing Bad.
        if arguments.length() != 1 {
          diagnostics.push(diag("Null expects exactly one argument"))
          None
        } else {
          Some(NullValue)
        }
      } else if callee is Identifier("Pair") &&
        !stack_contains_binding(stack, "Pair") &&
        find_binding(bindings, "Pair") is None {
        // PKL-119a: `Pair(first, second)` constructs a dedicated
        // `PairValue`. Member access (`.first` / `.second`) lands on
        // the same value through the `PairValue` arm in
        // `eval_member_access`, and renderers project it as
        // `Pair(a, b)` (PCF) / `[a, b]` (JSON / YAML / Properties /
        // plist).
        if arguments.length() != 2 {
          diagnostics.push(diag("Pair expects exactly two arguments"))
          None
        } else {
          let first = eval_expr_with_bindings(
            arguments[0],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
          let second = eval_expr_with_bindings(
            arguments[1],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
          match (first, second) {
            (Some(a), Some(b)) => Some(PairValue(a, b))
            _ => None
          }
        }
      } else if is_pkl_math_intrinsic_call(callee, bindings, stack) {
        // PKL-120: `pkl:math`'s Float-side helpers route through the
        // `_pkl_math_<op>` global intrinsic names — `sqrt`, `pow`,
        // `log`, `exp`, `floor`, `ceil`, `round`, `sin`, `cos`,
        // `tan`, `atan`, `atan2`. The synthetic `pkl:math` source
        // defines each public name as a lambda forwarding to the
        // corresponding intrinsic so the user-facing API stays
        // `math.sqrt(x)` while the computation lives in MoonBit.
        eval_pkl_math_intrinsic(
          callee, arguments, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        )
      } else if is_pkl_semver_intrinsic_call(callee, bindings, stack) {
        // PKL-123: same forwarding pattern as `pkl:math`. The
        // synthetic `pkl:semver` source defines `parse`,
        // `parseOrNull`, `compare`, `isLessThan`, `isGreaterThan`,
        // `isEqualTo` as lambdas calling the `_pkl_semver_<op>`
        // intrinsics declared below. Keeping the parse + compare
        // logic in MoonBit avoids a String→Int helper in pkl and
        // means SemVer pre-release ordering follows the spec.
        eval_pkl_semver_intrinsic(
          callee, arguments, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        )
      } else if is_pkl_reflect_intrinsic_call(callee, bindings, stack) {
        eval_pkl_reflect_intrinsic(
          callee, arguments, bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        )
      } else if callee is Identifier("Regex") &&
        !stack_contains_binding(stack, "Regex") &&
        find_binding(bindings, "Regex") is None {
        // PKL-081: `Regex("<pattern>")` is recognized as a constructor
        // form before the generic call path runs. The argument must be a
        // single String literal evaluating to the pattern; the result is
        // a `RegexValue` carrying the pattern verbatim. Patterns are not
        // compiled here — that happens lazily inside the method
        // dispatchers, so a Regex value can be constructed even if the
        // pattern is later unused.
        if arguments.length() == 1 {
          match
            eval_expr_with_bindings(
              arguments[0],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(StringValue(pattern)) => Some(RegexValue(pattern))
            Some(_) => {
              diagnostics.push(diag("Regex expects a String argument"))
              None
            }
            None => None
          }
        } else {
          diagnostics.push(diag("Regex expects exactly one argument"))
          None
        }
      } else {
        match callee {
          // PKL-117: `super.method(args)` dispatches to the parent
          // class's implementation while keeping the current
          // `this`. The current class name lives in the
          // `@current_class` marker pushed by
          // `eval_class_method_call`; the parent comes from the
          // class binding's `parent_name`.
          MemberAccess(Identifier("super"), method_name) =>
            eval_super_method_call(
              method_name, arguments, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          MemberAccess(target_expr, method_name) =>
            if class_method_call_available(
                target_expr, method_name, bindings, class_env,
              ) {
              eval_class_method_call(
                target_expr, method_name, arguments, false, bindings, env, class_env,
                cache, stack, declarations, diagnostics, resolve_import,
              )
            } else if method_name == "getClass" && arguments.length() == 0 {
              // PKL-148: `value.getClass()` returns a `pkl:reflect.Class`
              // mirror exposing `simpleName` / `name`. snippetTest's
              // `api/any.pkl` exercises this on every primitive variant
              // — Int, Float, Bool, String, Duration, DataSize, List,
              // Map, Listing, Mapping, Dynamic, Pair, Null.
              match target_expr {
                Identifier("module") =>
                  Some(synth_class_mirror_for_name("module"))
                _ =>
                  match
                    eval_expr_with_bindings(
                      target_expr, bindings, env, class_env, cache, stack, declarations,
                      diagnostics, resolve_import,
                    ) {
                    // PKL-152: a user-class instance's getClass() must
                    // produce `<module>#<simple>` for `.name` so the
                    // converter dispatch (api/anyConverter) and reflect
                    // round-trip both agree. Read the module name from
                    // the `@__module_name` cache marker and qualify the
                    // mirror when the class is non-stdlib.
                    Some(value) => {
                      let bare = eval_value_type_name(value)
                      let module_name = match
                        lookup_value(cache, "@__module_name") {
                        Some(StringValue(s)) => s
                        _ => ""
                      }
                      if module_name.length() > 0 && !is_stdlib_class_name(bare) {
                        Some(
                          synth_class_mirror_for_qualified(
                            bare,
                            Some(module_name),
                          ),
                        )
                      } else {
                        Some(synth_class_mirror_for_value(value))
                      }
                    }
                    None => None
                  }
              }
            } else if target_expr is Identifier(class_name) &&
              !(class_name == "module" && method_name == "relativePathTo") &&
              lookup_class_binding(class_env, class_name) is Some(_) {
              // PKL-148d: `Person.bar()` where `Person` is a class name
              // and `bar` isn't a static-callable method. Apple Pkl
              // reports `Cannot find method \`bar\` in class \`Class\`.`
              // — distinct from the property-access wording.
              diagnostics.push(
                diag("Cannot find method `\{method_name}` in class `Class`."),
              )
              None
            } else if is_listing_method_name(method_name) ||
              is_mapping_method_name(method_name) ||
              is_string_method_name(method_name) ||
              is_int_method_name(method_name) ||
              // PKL-148: Bool / Float method dispatchers join the
              // gate so `true.xor(false)` / `1.5.abs()` route through
              // the receiver-typed arm instead of `eval_callable_call`.
              is_bool_method_name(method_name) ||
              is_float_method_name(method_name) ||
              is_regex_method_name(method_name) ||
              is_bytes_method_name(method_name) ||
              is_intseq_method_name(method_name) ||
              is_set_method_name(method_name) ||
              is_map_method_name(method_name) ||
              is_typed_method_name(method_name) ||
              is_semver_version_method_name(method_name) ||
              is_reflect_type_method_name(method_name) ||
              method_name == "toString" ||
              method_name == "toUnit" ||
              method_name == "toBinaryUnit" ||
              method_name == "toDecimalUnit" ||
              method_name == "toBytes" ||
              method_name == "isSubclassOf" ||
              method_name == "relativePathTo" ||
              method_name == "parse" ||
              method_name == "parseAll" ||
              method_name == "renderValue" ||
              method_name == "renderDocument" {
              match
                eval_expr_with_bindings(
                  target_expr, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                ) {
                // PKL-143: `Class.isSubclassOf(other)` walks the parent
                // chain of the receiver class against the reflectee of
                // the argument mirror. The receiver is structurally an
                // ObjectValue carrying the `__kind = "Class"` marker,
                // so we check that nested inside the ObjectValue arm
                // before falling through to other lookups.
                Some(ObjectValue(receiver_members)) =>
                  if method_name == "toString" && arguments.length() == 0 {
                    Some(StringValue(object_to_string_value(receiver_members)))
                  } else if is_semver_version_method_name(method_name) &&
                    is_semver_value_members(receiver_members) {
                    eval_semver_version_method(
                      receiver_members, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else if is_reflect_type_method_name(method_name) &&
                    is_reflect_type_members(receiver_members) {
                    eval_reflect_type_method(
                      receiver_members, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else if method_name == "relativePathTo" {
                    eval_module_relative_path_to(
                      receiver_members, arguments, bindings, env, class_env, cache,
                      stack, declarations, diagnostics, resolve_import,
                    )
                  } else if (
                      method_name == "renderValue" ||
                      method_name == "renderDocument"
                    ) &&
                    renderer_format_from_members(receiver_members)
                    is Some(format) {
                    if format == "textproto" &&
                      (
                        lookup_value(cache, "@__class_default_scope") is Some(_) ||
                        lookup_value(cache, "@__class_default_call_scope")
                        is Some(_)
                      ) {
                      diagnostics.push(
                        diag(
                          "Cannot call method `\{method_name}` from here because it is not `const`.",
                        ),
                      )
                      None
                    } else {
                      eval_value_renderer_method(
                        format, receiver_members, method_name, arguments, bindings,
                        env, class_env, cache, stack, declarations, diagnostics,
                        resolve_import,
                      )
                    }
                  } else if method_name == "parse" &&
                    reflect_kind(receiver_members) is Some("JsonParser") {
                    // PKL-144 / PKL-145: `<json.Parser>.parse(source)`
                    // routes through `@json.parse` and projects the
                    // result via `json_to_value`. The receiver is
                    // identified via the hidden `__kind = "JsonParser"`
                    // marker that the synthetic `pkl:json.Parser`
                    // class stamps.
                    if arguments.length() != 1 {
                      diagnostics.push(
                        diag(
                          "json.Parser.parse expects 1 argument, got \{arguments.length()}",
                        ),
                      )
                      None
                    } else {
                      match
                        eval_expr_with_bindings(
                          arguments[0],
                          bindings,
                          env,
                          class_env,
                          cache,
                          stack,
                          declarations,
                          diagnostics,
                          resolve_import,
                        ) {
                        Some(StringValue(source_text)) => {
                          let use_mapping = parser_use_mapping(receiver_members)
                          try {
                            let parsed = @json.parse(source_text[:])
                            Some(
                              apply_parser_converters(
                                json_to_value(parsed, use_mapping),
                                receiver_members,
                                false,
                                bindings,
                                env,
                                class_env,
                                cache,
                                declarations,
                                diagnostics,
                                resolve_import,
                              ),
                            )
                          } catch {
                            // PKL-148bb: Apple Pkl's `json.Parser.parse`
                            // surfaces a single fixed diagnostic for
                            // every parse failure (`Error parsing JSON
                            // document.`) rather than the underlying
                            // tokenizer error. Match that wording so
                            // `api/jsonParser1`'s `test.catch` snapshots
                            // line up; the moonbit @json error remains
                            // available for non-snippet contexts via
                            // the `_` binding below.
                            _ => {
                              diagnostics.push(
                                diag("Error parsing JSON document."),
                              )
                              None
                            }
                          }
                        }
                        Some(_) => {
                          diagnostics.push(
                            diag("json.Parser.parse expects a String argument"),
                          )
                          None
                        }
                        None => None
                      }
                    }
                  } else if (
                      method_name == "parse" || method_name == "parseAll"
                    ) &&
                    reflect_kind(receiver_members) is Some("YamlParser") {
                    // PKL-146: `<yaml.Parser>.parse(source)` routes
                    // through `@yaml.Yaml::load_from_string` and
                    // projects the first document via `yaml_to_value`.
                    // Multi-document YAML returns the first document
                    // for now; full multi-doc support (returning a
                    // Listing of docs) lands when a fixture demands
                    // it. Empty input → NullValue.
                    if arguments.length() != 1 {
                      diagnostics.push(
                        diag(
                          "yaml.Parser.\{method_name} expects 1 argument, got \{arguments.length()}",
                        ),
                      )
                      None
                    } else {
                      match
                        eval_expr_with_bindings(
                          arguments[0],
                          bindings,
                          env,
                          class_env,
                          cache,
                          stack,
                          declarations,
                          diagnostics,
                          resolve_import,
                        ) {
                        Some(StringValue(source_text)) => {
                          let use_mapping = parser_use_mapping(receiver_members)
                          try {
                            let yaml_source = normalize_yaml_folded_block_chomping(
                              source_text,
                            )
                            let docs = @yaml.Yaml::load_from_string(
                              yaml_source[:],
                            )
                            let alias_refs = yaml_alias_refs_for_documents(docs)
                            let max_aliases = parser_max_collection_aliases(
                              receiver_members,
                            )
                            if yaml_collection_alias_count(alias_refs) >
                              max_aliases {
                              diagnostics.push(
                                diag(
                                  "Error parsing YAML document: The number of aliases for collection nodes exceeds the allowed maximum of \{max_aliases}.",
                                ),
                              )
                              None
                            } else if method_name == "parseAll" {
                              let elements : Array[Value] = []
                              for doc in docs {
                                elements.push(
                                  apply_parser_converters(
                                    yaml_to_value_with_aliases(
                                      doc, use_mapping, alias_refs,
                                    ),
                                    receiver_members,
                                    true,
                                    bindings,
                                    env,
                                    class_env,
                                    cache,
                                    declarations,
                                    diagnostics,
                                    resolve_import,
                                  ),
                                )
                              }
                              Some(ListValue(elements))
                            } else if docs.length() == 0 {
                              Some(
                                apply_parser_converters(
                                  NullValue,
                                  receiver_members,
                                  true,
                                  bindings,
                                  env,
                                  class_env,
                                  cache,
                                  declarations,
                                  diagnostics,
                                  resolve_import,
                                ),
                              )
                            } else if docs.length() > 1 {
                              diagnostics.push(
                                diag("Error parsing YAML document."),
                              )
                              None
                            } else {
                              Some(
                                apply_parser_converters(
                                  yaml_to_value_with_aliases(
                                    docs[0],
                                    use_mapping,
                                    alias_refs,
                                  ),
                                  receiver_members,
                                  true,
                                  bindings,
                                  env,
                                  class_env,
                                  cache,
                                  declarations,
                                  diagnostics,
                                  resolve_import,
                                ),
                              )
                            }
                          } catch {
                            // PKL-148bb: match Apple Pkl's fixed wording.
                            _ => {
                              diagnostics.push(
                                diag("Error parsing YAML document."),
                              )
                              None
                            }
                          }
                        }
                        Some(_) => {
                          diagnostics.push(
                            diag(
                              "yaml.Parser.\{method_name} expects a String argument",
                            ),
                          )
                          None
                        }
                        None => None
                      }
                    }
                  } else if reflect_kind(receiver_members) is Some("Class") &&
                    method_name == "isSubclassOf" {
                    if arguments.length() != 1 {
                      diagnostics.push(
                        diag(
                          "Class.isSubclassOf expects 1 argument, got \{arguments.length()}",
                        ),
                      )
                      None
                    } else {
                      match
                        eval_expr_with_bindings(
                          arguments[0],
                          bindings,
                          env,
                          class_env,
                          cache,
                          stack,
                          declarations,
                          diagnostics,
                          resolve_import,
                        ) {
                        Some(ObjectValue(other_members)) =>
                          if reflect_reflectee_name(other_members) is Some(_) {
                            Some(
                              BoolValue(
                                reflect_class_is_subclass_value(
                                  receiver_members, other_members, declarations,
                                ),
                              ),
                            )
                          } else {
                            diagnostics.push(
                              diag(
                                "Class.isSubclassOf expects a Class mirror argument",
                              ),
                            )
                            None
                          }
                        _ => {
                          diagnostics.push(
                            diag(
                              "Class.isSubclassOf expects a Class mirror argument",
                            ),
                          )
                          None
                        }
                      }
                    }
                  } else if is_typed_method_name(method_name) {
                    // PKL-152: pkl:base.Typed surface — `getProperty`,
                    // `getPropertyOrNull`, `hasProperty`, `toMap`,
                    // `toDynamic` apply to every user-class ObjectValue
                    // receiver. Argument count is validated per arm.
                    eval_typed_method_dispatch(
                      receiver_members, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    // Method call against an ObjectValue receiver that
                    // didn't match the JSON/YAML/isSubclassOf intercepts.
                    // When the receiver carries a class tag (today only
                    // `Dynamic`) surface Apple Pkl's class-context
                    // wording instead of falling through to
                    // `eval_callable_call`, which would re-evaluate the
                    // MemberAccess callee and emit the property-context
                    // `Cannot find property \`X\` in object of type
                    // \`Dynamic\`.` form.
                    match lookup_member(receiver_members, method_name) {
                      Some(FunctionValue(_, _, _, _, _)) =>
                        eval_callable_call(
                          callee, arguments, bindings, env, class_env, cache, stack,
                          declarations, diagnostics, resolve_import,
                        )
                      _ =>
                        match find_object_class_tag(receiver_members) {
                          Some(class_tag) => {
                            diagnostics.push(
                              diag(
                                "Cannot find method `\{method_name}` in class `\{class_tag}`.",
                              ),
                            )
                            None
                          }
                          None =>
                            eval_callable_call(
                              callee, arguments, bindings, env, class_env, cache,
                              stack, declarations, diagnostics, resolve_import,
                            )
                        }
                    }
                  }
                Some(ListingValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    // PKL-148h: List and Listing share the method
                    // surface (`.filter`, `.map`, `.length`, ...). The
                    // dispatcher's element-walking logic is identical;
                    // the receiver type only re-emerges at `.toList()` /
                    // `.toListing()` (each tags its result with the
                    // matching variant). PKL-148bb: the helper lifts
                    // collection-shaped results back to `ListValue`
                    // when the receiver was a List, but a Listing
                    // receiver stays a Listing — pass `false`.
                    eval_list_or_listing_method(
                      false, elements, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(DefaultedListingValue(_, elements, default_value)) =>
                  if is_listing_method_name(method_name) {
                    eval_defaulted_listing_method(
                      elements, default_value, method_name, arguments, bindings,
                      env, class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(ListValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    eval_list_or_listing_method(
                      true, elements, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(MappingValue(entries)) =>
                  if is_mapping_method_name(method_name) {
                    eval_mapping_method(
                      entries, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(DefaultedMappingValue(_, entries, default_value)) =>
                  if is_mapping_method_name(method_name) {
                    eval_defaulted_mapping_method(
                      entries, default_value, method_name, arguments, bindings, env,
                      class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(StringValue(s)) =>
                  if is_string_method_name(method_name) {
                    eval_string_method(
                      s, method_name, arguments, bindings, env, class_env, cache,
                      stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(IntValue(n)) =>
                  if is_int_method_name(method_name) {
                    eval_int_method(
                      n, method_name, arguments, bindings, env, class_env, cache,
                      stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                // PKL-148: Bool method dispatch — `xor` / `implies` /
                // `and` / `or` / `toString` / `getClass`. snippetTest
                // fixtures lean on these to express truth tables.
                Some(BoolValue(b)) =>
                  eval_bool_method(
                    b, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                Some(FloatValue(d)) =>
                  // PKL-148: Float method dispatch covers `abs` /
                  // `toString` / `round` / `floor` / `ceil` / `isNaN`
                  // / `isFinite` / `isInfinite`.
                  eval_float_method(
                    d, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                Some(DurationValue(n, unit)) =>
                  eval_duration_method(
                    n, unit, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(DataSizeValue(n, unit)) =>
                  eval_datasize_method(
                    n, unit, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(RegexValue(pattern)) =>
                  eval_regex_method(
                    pattern, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(BytesValue(bytes)) =>
                  eval_bytes_method(
                    bytes, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                // PKL-119b: IntSeq methods (`step(n)` / `toList` /
                // `toListing` / `map` / `fold`) dispatch through the
                // dedicated method evaluator. `step` is also a
                // property accessor — the call form (with parens)
                // lands here; bare `.step` resolves earlier in the
                // member-access dispatcher.
                Some(IntSeqValue(start, end_v, step)) =>
                  if is_intseq_method_name(method_name) {
                    eval_intseq_method(
                      start, end_v, step, method_name, arguments, bindings, env,
                      class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                // PKL-119c: Set methods (`.contains` / `.toList` /
                // `.toListing` / `.toSet` / `.map` / `.filter` /
                // `.fold` / `.join`) dispatch through the dedicated
                // method evaluator.
                Some(SetValue(elements)) =>
                  if is_set_method_name(method_name) {
                    eval_set_method(
                      elements, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                // PKL-119d: Map methods (`.containsKey` / `.getOrNull`
                // / `.getOrThrow` / `.toMap` / `.toMapping` /
                // `.toList` / `.map` / `.filter` / `.fold`) dispatch
                // through the dedicated method evaluator.
                Some(MapValue(entries)) =>
                  if is_map_method_name(method_name) {
                    eval_map_method(
                      entries, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                _ =>
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
              }
            } else if target_expr is NullLiteral {
              diagnostics.push(
                diag("Cannot find method `\{method_name}` in class `Null`."),
              )
              None
            } else {
              eval_callable_call(
                callee, arguments, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              )
            }
          SafeMemberAccess(target_expr, method_name) =>
            if class_method_call_available(
                target_expr, method_name, bindings, class_env,
              ) {
              eval_class_method_call(
                target_expr, method_name, arguments, true, bindings, env, class_env,
                cache, stack, declarations, diagnostics, resolve_import,
              )
            } else if is_listing_method_name(method_name) ||
              is_mapping_method_name(method_name) ||
              is_string_method_name(method_name) ||
              is_int_method_name(method_name) ||
              is_regex_method_name(method_name) ||
              is_bytes_method_name(method_name) ||
              is_intseq_method_name(method_name) ||
              is_set_method_name(method_name) ||
              is_map_method_name(method_name) ||
              is_typed_method_name(method_name) ||
              method_name == "toUnit" ||
              method_name == "toBinaryUnit" ||
              method_name == "toDecimalUnit" ||
              method_name == "toBytes" {
              match
                eval_expr_with_bindings(
                  target_expr, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                ) {
                Some(NullValue) => Some(NullValue)
                Some(ListingValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    // PKL-148h: List and Listing share the method
                    // surface (`.filter`, `.map`, `.length`, ...). The
                    // dispatcher's element-walking logic is identical;
                    // the receiver type only re-emerges at `.toList()` /
                    // `.toListing()` (each tags its result with the
                    // matching variant). PKL-148bb: the helper lifts
                    // collection-shaped results back to `ListValue`
                    // when the receiver was a List, but a Listing
                    // receiver stays a Listing — pass `false`.
                    eval_list_or_listing_method(
                      false, elements, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(DefaultedListingValue(_, elements, default_value)) =>
                  if is_listing_method_name(method_name) {
                    eval_defaulted_listing_method(
                      elements, default_value, method_name, arguments, bindings,
                      env, class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(ListValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    eval_list_or_listing_method(
                      true, elements, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(MappingValue(entries)) =>
                  if is_mapping_method_name(method_name) {
                    eval_mapping_method(
                      entries, method_name, arguments, bindings, env, class_env,
                      cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(DefaultedMappingValue(_, entries, default_value)) =>
                  if is_mapping_method_name(method_name) {
                    eval_defaulted_mapping_method(
                      entries, default_value, method_name, arguments, bindings, env,
                      class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(StringValue(s)) =>
                  if is_string_method_name(method_name) {
                    eval_string_method(
                      s, method_name, arguments, bindings, env, class_env, cache,
                      stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(IntValue(n)) =>
                  if is_int_method_name(method_name) {
                    eval_int_method(
                      n, method_name, arguments, bindings, env, class_env, cache,
                      stack, declarations, diagnostics, resolve_import,
                    )
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                // PKL-148: Bool method dispatch — `xor` / `implies` /
                // `and` / `or` / `toString` / `getClass`. snippetTest
                // fixtures lean on these to express truth tables.
                Some(BoolValue(b)) =>
                  eval_bool_method(
                    b, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                Some(FloatValue(d)) =>
                  // PKL-148: Float method dispatch covers `abs` /
                  // `toString` / `round` / `floor` / `ceil` / `isNaN`
                  // / `isFinite` / `isInfinite`.
                  eval_float_method(
                    d, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                Some(DurationValue(n, unit)) =>
                  eval_duration_method(
                    n, unit, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(DataSizeValue(n, unit)) =>
                  eval_datasize_method(
                    n, unit, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(RegexValue(pattern)) =>
                  eval_regex_method(
                    pattern, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                Some(BytesValue(bytes)) =>
                  eval_bytes_method(
                    bytes, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                _ =>
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
              }
            } else {
              eval_callable_call(
                callee, arguments, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              )
            }
          _ =>
            eval_callable_call(
              callee, arguments, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
        }
      }
    LambdaExpr(parameters, body, return_type_name) =>
      Some(
        FunctionValue(
          parameters,
          body,
          return_type_name,
          capture_value_bindings(env, cache),
          fresh_function_id(),
        ),
      )
    LetExpr(name, type_name, value_expr, body) => {
      let raw_value = match
        eval_expr_with_bindings(
          value_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) => value
        None => return None
      }
      let value = coerce_value_to_annotated_type(raw_value, type_name)
      let value = apply_collection_default_for_type(
        value, type_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      match
        eval_callable_argument_type_rejection_message(
          type_name, value, class_env, cache, declarations,
        ) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      match
        eval_callable_argument_rejection_message(type_name, value, declarations) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      let body_env = copy_value_bindings(env)
      let body_cache = copy_value_bindings(cache)
      body_env.push({ name, value })
      eval_expr_with_bindings(
        body, bindings, body_env, class_env, body_cache, stack, declarations, diagnostics,
        resolve_import,
      )
    }
    NonNullExpr(inner_expr) =>
      match
        eval_expr_with_bindings(
          inner_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(NullValue) => {
          diagnostics.push(diag("Expected a non-null value, but got `null`."))
          None
        }
        Some(value) => Some(value)
        None => None
      }
    UnaryExpr(op, inner_expr) => {
      let inner = eval_expr_with_bindings(
        inner_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      match (op, inner) {
        (Negate, Some(IntValue(value))) => Some(IntValue(0 - value))
        (Negate, Some(FloatValue(value))) =>
          Some(FloatValue(negate_float(value)))
        (Negate, Some(DurationValue(value, unit))) =>
          Some(DurationValue(0 - value, unit))
        (Negate, Some(DataSizeValue(value, unit))) =>
          Some(DataSizeValue(0 - value, unit))
        (Not, Some(BoolValue(value))) => Some(BoolValue(!value))
        (Negate, Some(_)) => {
          diagnostics.push(diag("operator - expects numeric operand"))
          None
        }
        (Not, Some(_)) => {
          diagnostics.push(diag("operator ! expects Boolean operand"))
          None
        }
        (_, None) => None
      }
    }
    BinaryExpr(op, left_expr, right_expr) => {
      match op {
        And => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match left {
            Some(BoolValue(false)) => return Some(BoolValue(false))
            Some(BoolValue(true)) => ()
            Some(other) => {
              diagnostics.push(
                diag(
                  "Operator `&&` is not defined for left operand type `\{eval_value_type_name(other)}`. Left operand: \{render_pcf_value_inline(other)}",
                ),
              )
              return None
            }
            None => return None
          }
          match
            eval_expr_with_bindings(
              right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
            ) {
            Some(BoolValue(value)) => return Some(BoolValue(value))
            Some(other) => {
              diagnostics.push(
                diag(
                  "Operator `&&` is not defined for right operand type `\{eval_value_type_name(other)}`. Right operand: \{render_pcf_value_inline(other)}",
                ),
              )
              return None
            }
            None => return None
          }
        }
        Or => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match left {
            Some(BoolValue(true)) => return Some(BoolValue(true))
            Some(BoolValue(false)) => ()
            Some(other) => {
              diagnostics.push(
                diag(
                  "Operator `||` is not defined for left operand type `\{eval_value_type_name(other)}`. Left operand: \{render_pcf_value_inline(other)}",
                ),
              )
              return None
            }
            None => return None
          }
          match
            eval_expr_with_bindings(
              right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
            ) {
            Some(BoolValue(value)) => return Some(BoolValue(value))
            Some(other) => {
              diagnostics.push(
                diag(
                  "Operator `||` is not defined for right operand type `\{eval_value_type_name(other)}`. Right operand: \{render_pcf_value_inline(other)}",
                ),
              )
              return None
            }
            None => return None
          }
        }
        NullCoalesce => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match left {
            Some(NullValue) =>
              return eval_expr_with_bindings(
                right_expr, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              )
            Some(value) => return Some(value)
            None => return None
          }
        }
        Is =>
          // PKL-114: evaluate `<value> is <TypeName>` at runtime. The
          // parser stores the right operand as `Identifier(type_name)`
          // carrying the verbatim type annotation text (e.g. "Int",
          // "Number", "Float?", "String | Int"). Anything more exotic
          // on the right falls through to the parser-only diagnostic
          // below.
          match right_expr {
            Identifier(type_name) =>
              match
                eval_expr_with_bindings(
                  left_expr, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                ) {
                Some(value) => {
                  // Structural check first against the base type.
                  let base_for_user_check = match
                    pkl_constrained_type_base_name(type_name) {
                    Some(b) => b
                    None => type_name
                  }
                  let named_module_match = if value is ObjectValue(_) {
                    if lookup_value(env, base_for_user_check)
                      is Some(ObjectValue(_)) ||
                      lookup_value(cache, base_for_user_check)
                      is Some(ObjectValue(_)) {
                      // PKL-148bh: `x is someModule` where `someModule`
                      // is an imported module value — treat any
                      // ObjectValue as matching, because module amends
                      // can't currently carry per-instance class
                      // identity beyond the structural shape
                      // (types/moduleType).
                      true
                    } else {
                      false
                    }
                  } else {
                    false
                  }
                  // PKL-152: `o is module` — the runtime identity
                  // check is strict (only the actual current-module
                  // value passes), unlike `: module` type annotations
                  // which accept any ObjectValue structurally. The
                  // converter dispatch in api/anyConverter relies on
                  // this split — `[Any] = (o) -> if (o is module) o
                  // else ...` must reject Dog / User / Env instances
                  // even though they're ObjectValues.
                  if base_for_user_check == "module" {
                    let module_name = match
                      lookup_value(cache, "@__module_name") {
                      Some(StringValue(s)) => s
                      _ => ""
                    }
                    let class_tag = match value {
                      ObjectValue(members) =>
                        match find_object_class_tag(members) {
                          Some(s) => s
                          None => ""
                        }
                      _ => ""
                    }
                    return Some(
                      BoolValue(
                        class_tag == "module" ||
                        (module_name.length() > 0 && class_tag == module_name),
                      ),
                    )
                  }
                  if base_for_user_check == "Module" {
                    return Some(BoolValue(left_expr is Identifier("module")))
                  }
                  let typed_match = eval_value_matches_type_annotation(
                    type_name, value, class_env, declarations,
                  )
                  if !typed_match && !named_module_match {
                    return Some(BoolValue(false))
                  }
                  // PKL-148bb: if the type carries a predicate
                  // (`Int(this < 0)` / `String(length > 0)`), evaluate
                  // it with `this` bound to the value. Apple Pkl's
                  // `is` operator returns `false` when the predicate
                  // fails even though the structural check passes —
                  // `1 is Int(this < 0)` is `false`, not `true`. The
                  // predicate is parsed via the same path the
                  // class-property constraint cascade uses.
                  match pkl_constrained_type_constraint_text(type_name) {
                    Some(constraint_text) => {
                      let parts = pkl_split_constraint_arguments(
                        constraint_text,
                      )
                      for part in parts {
                        let pred_expr = match
                          parse_constraint_expression(part) {
                          Some(e) => e
                          None => continue
                        }
                        let pred_env : Array[ValueBinding] = []
                        for b in env {
                          pred_env.push(b)
                        }
                        pred_env.push({ name: "this", value })
                        let rewritten = rewrite_implicit_this_in_expr(
                          pred_expr, bindings, pred_env, cache,
                        )
                        let probe_diags : Array[Diagnostic] = []
                        let probe = eval_expr_with_bindings(
                          rewritten, bindings, pred_env, class_env, cache, stack,
                          declarations, probe_diags, resolve_import,
                        )
                        match probe {
                          Some(BoolValue(true)) => continue
                          Some(BoolValue(false)) =>
                            return Some(BoolValue(false))
                          _ => continue
                        }
                      }
                      return Some(BoolValue(true))
                    }
                    None => return Some(BoolValue(true))
                  }
                }
                None => return None
              }
            _ => {
              diagnostics.push(
                diag("operator is right operand must be a type name"),
              )
              return None
            }
          }
        // PKL-148b: `as` is a runtime type cast. The typechecker has
        // already verified the assignment-compatibility statically; at
        // runtime we just need to ensure the value matches the
        // annotation and surface a diagnostic otherwise. The cast is
        // shape-preserving (no coercion / widening), but collection
        // casts may carry deferred element diagnostics.
        As => {
          let value_opt = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match (value_opt, right_expr) {
            (Some(value), Identifier("Module")) if left_expr
              is Identifier("module") => return Some(value)
            (Some(value), Identifier(type_name)) =>
              match
                cast_value_to_type_annotation(
                  type_name, value, bindings, env, class_env, cache, stack, declarations,
                  resolve_import,
                ) {
                TypeCastOk(casted) => return Some(casted)
                TypeCastErr(message) => {
                  diagnostics.push(diag(message))
                  return None
                }
              }
            (None, _) => return None
            _ => {
              diagnostics.push(
                diag("operator as right operand must be a type name"),
              )
              return None
            }
          }
        }
        // PKL-148b: `x |> f` is the forward-pipe operator — desugars
        // to `f(x)`. Apple Pkl's runtime semantics match a direct
        // single-arg call against the right operand. PKL-148k: when
        // the right side isn't a callable, project Apple Pkl's
        // dedicated diagnostic (`Operator `|>` is not defined for
        // operand types `<L>` and `<R>`. Left operand : <l> Right
        // operand: <r>`) instead of the generic `call expects
        // Function`; the latter loses the pipe context that
        // `module.catch(() -> 42 |> 21)` round-trips.
        Pipe => {
          let right_value = eval_expr_with_bindings(
            right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match right_value {
            Some(FunctionValue(_, _, _, _, _)) =>
              return eval_expr_with_bindings(
                CallExpr(right_expr, [left_expr]),
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            Some(right_val) => {
              match right_val {
                ObjectValue(mixin_members) =>
                  if object_class_tag_matches(mixin_members, "Mixin") ||
                    object_members_are_mixin_body(mixin_members) {
                    let left_value = eval_expr_with_bindings(
                      left_expr, bindings, env, class_env, cache, stack, declarations,
                      diagnostics, resolve_import,
                    )
                    match left_value {
                      Some(left_val) =>
                        return apply_mixin_pipe_value(
                          left_val, mixin_members, diagnostics,
                        )
                      None => return None
                    }
                  }
                _ => ()
              }
              let left_value = eval_expr_with_bindings(
                left_expr, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              )
              match left_value {
                Some(left_val) => {
                  let module_name = match
                    lookup_value(cache, "@__module_name") {
                    Some(StringValue(s)) => Some(s)
                    _ => None
                  }
                  let left_type = qualify_value_type_name(
                    left_val, class_env, module_name,
                  )
                  let right_type = qualify_value_type_name(
                    right_val, class_env, module_name,
                  )
                  let left_render = render_pcf_value_inline(left_val)
                  let right_render = render_pcf_value_inline(right_val)
                  diagnostics.push(
                    diag(
                      "Operator `|>` is not defined for operand types `\{left_type}` and `\{right_type}`. Left operand : \{left_render} Right operand: \{right_render}",
                    ),
                  )
                }
                None => ()
              }
              return None
            }
            None => return None
          }
        }
        _ => ()
      }
      let left = eval_expr_with_bindings(
        left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      let right = eval_expr_with_bindings(
        right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      match (left, right) {
        (Some(IntValue(a)), Some(IntValue(b))) =>
          match op {
            Add => Some(IntValue(a + b))
            Subtract => Some(IntValue(a - b))
            Multiply => Some(IntValue(a * b))
            Divide =>
              // PKL-092: `/` widens to Float when both operands are Int,
              // mirroring Apple Pkl's `Int.div` semantics (`5 / 2 = 2.5`).
              Some(FloatValue(a.to_double() / b.to_double()))
            IntDivide =>
              if b == 0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(IntValue(a / b))
              }
            Modulo =>
              if b == 0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(IntValue(a % b))
              }
            Power =>
              if b < 0L {
                Some(FloatValue(@math.pow(a.to_double(), b.to_double())))
              } else {
                match int_pow(a, b) {
                  Some(value) => Some(IntValue(value))
                  None => {
                    diagnostics.push(diag("Integer overflow."))
                    None
                  }
                }
              }
            LessThan => Some(BoolValue(a < b))
            LessOrEqual => Some(BoolValue(a <= b))
            GreaterThan => Some(BoolValue(a > b))
            GreaterOrEqual => Some(BoolValue(a >= b))
            Equal => Some(BoolValue(a == b))
            NotEqual => Some(BoolValue(a != b))
            And | Or | NullCoalesce | Is | As | Pipe => panic()
          }
        (Some(FloatValue(a)), Some(FloatValue(b))) =>
          eval_float_binary(op, a, b, diagnostics)
        (Some(IntValue(a)), Some(FloatValue(b))) =>
          eval_float_binary(op, a.to_double(), b, diagnostics)
        (Some(FloatValue(a)), Some(IntValue(b))) =>
          eval_float_binary(op, a, b.to_double(), diagnostics)
        (Some(DurationValue(av, au)), Some(DurationValue(bv, bu))) => {
          let target = larger_duration_unit(au, bu)
          let a_in = duration_in_unit(av, au, target)
          let b_in = duration_in_unit(bv, bu, target)
          match op {
            Add => Some(DurationValue(a_in + b_in, target))
            Subtract => Some(DurationValue(a_in - b_in, target))
            LessThan => Some(BoolValue(a_in < b_in))
            LessOrEqual => Some(BoolValue(a_in <= b_in))
            GreaterThan => Some(BoolValue(a_in > b_in))
            GreaterOrEqual => Some(BoolValue(a_in >= b_in))
            Equal => Some(BoolValue(a_in == b_in))
            NotEqual => Some(BoolValue(a_in != b_in))
            Divide => {
              let divisor = duration_in_unit(bv, bu, au)
              if divisor == 0.0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(FloatValue(av / divisor))
              }
            }
            IntDivide => {
              let divisor = duration_in_unit(bv, bu, au)
              if divisor == 0.0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(IntValue(double_trunc(av / divisor).to_int64()))
              }
            }
            _ => {
              diagnostics.push(
                diag(
                  undefined_operator_for_operand_types_message(
                    op,
                    DurationValue(av, au),
                    DurationValue(bv, bu),
                  ),
                ),
              )
              None
            }
          }
        }
        (Some(DataSizeValue(av, au)), Some(DataSizeValue(bv, bu))) => {
          let target = larger_datasize_unit(au, bu)
          let a_in = datasize_in_unit(av, au, target)
          let b_in = datasize_in_unit(bv, bu, target)
          match op {
            Add => Some(DataSizeValue(a_in + b_in, target))
            Subtract => Some(DataSizeValue(a_in - b_in, target))
            LessThan => Some(BoolValue(a_in < b_in))
            LessOrEqual => Some(BoolValue(a_in <= b_in))
            GreaterThan => Some(BoolValue(a_in > b_in))
            GreaterOrEqual => Some(BoolValue(a_in >= b_in))
            Equal => Some(BoolValue(a_in == b_in))
            NotEqual => Some(BoolValue(a_in != b_in))
            Divide => {
              let divisor = datasize_in_unit(bv, bu, au)
              if divisor == 0.0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(FloatValue(av / divisor))
              }
            }
            IntDivide => {
              let divisor = datasize_in_unit(bv, bu, au)
              if divisor == 0.0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(IntValue(double_trunc(av / divisor).to_int64()))
              }
            }
            _ => {
              diagnostics.push(
                diag(
                  undefined_operator_for_operand_types_message(
                    op,
                    DataSizeValue(av, au),
                    DataSizeValue(bv, bu),
                  ),
                ),
              )
              None
            }
          }
        }
        // PKL-119be (IntSeq equality follow-up): Apple Pkl treats two
        // IntSeq operands as equal when they produce the same Int
        // sequence — empty IntSeqs are equal regardless of endpoints
        // (`IntSeq(0, -1) == IntSeq(10, -10)`) and non-empty IntSeqs
        // are step-aware (`IntSeq(-10, 10).step(2) ==
        // IntSeq(-10, 11).step(2)`). The structural `derive(Eq)` the
        // value variant inherits doesn't capture either case, so route
        // through `intseq_value_equal` which materializes both sides
        // and compares element-by-element. Non-Equal ops on
        // IntSeq-IntSeq pairs aren't defined upstream — emit the
        // standard "not defined" diagnostic.
        (Some(IntSeqValue(s1, e1, st1)), Some(IntSeqValue(s2, e2, st2))) => {
          let eq = intseq_value_equal(s1, e1, st1, s2, e2, st2)
          match op {
            Equal => Some(BoolValue(eq))
            NotEqual => Some(BoolValue(!eq))
            _ => {
              diagnostics.push(
                diag(
                  "operator \{operator_name(op)} not defined for IntSeq operands",
                ),
              )
              None
            }
          }
        }
        (Some(BytesValue(left_bytes)), Some(BytesValue(right_bytes))) if op ==
          Add => Some(BytesValue(concat_bytes(left_bytes, right_bytes)))
        // PKL-148: Listing / Set / Map / String concatenation via `+`.
        // Apple Pkl's `Listing + Listing` returns a new Listing with the
        // right-hand elements appended; `Set + Set` is union (right-hand
        // order preserved for new elements); `Map + Map` is right-biased
        // merge; `String + String` is concatenation.
        (Some(ListingValue(la)), Some(ListingValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListingValue(merged))
        }
        (Some(SetValue(la)), Some(SetValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            if !contains_value(merged, v) {
              merged.push(v)
            }
          }
          Some(SetValue(merged))
        }
        // PKL-148b: Set + Listing (or List, since both project as
        // ListingValue today) widens to a Set with the right-hand
        // elements unioned in. Mirrors Apple Pkl's `Set + Collection`.
        (Some(SetValue(la)), Some(ListingValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            if !contains_value(merged, v) {
              merged.push(v)
            }
          }
          Some(SetValue(merged))
        }
        (Some(ListingValue(la)), Some(SetValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListingValue(merged))
        }
        // PKL-148h: `List + List` preserves the List type (matches
        // upstream — Apple Pkl renders `List(1, 2) + List(3)` as
        // `List(1, 2, 3)`). `List + Set` appends elements with no
        // dedup and stays a List; `Set + List` unions and stays a Set;
        // `List + Listing` widens to Listing (and the symmetric form
        // stays Listing) — matches Apple Pkl's left-biased Collection
        // dispatch where the LHS variant decides the result shape.
        (Some(ListValue(la)), Some(ListValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListValue(merged))
        }
        (Some(ListValue(la)), Some(SetValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListValue(merged))
        }
        (Some(SetValue(la)), Some(ListValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            if !contains_value(merged, v) {
              merged.push(v)
            }
          }
          Some(SetValue(merged))
        }
        (Some(ListValue(la)), Some(ListingValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListingValue(merged))
        }
        (Some(ListingValue(la)), Some(ListValue(lb))) if op == Add => {
          let merged : Array[Value] = []
          for v in la {
            merged.push(v)
          }
          for v in lb {
            merged.push(v)
          }
          Some(ListingValue(merged))
        }
        (Some(MappingValue(ea)), Some(MappingValue(eb))) if op == Add => {
          let merged : Array[ValueEntry] = []
          for e in ea {
            merged.push(e)
          }
          for e in eb {
            let mut replaced = false
            for i = 0; i < merged.length(); i = i + 1 {
              if merged[i].key == e.key {
                merged[i] = e
                replaced = true
                break
              }
            }
            if !replaced {
              merged.push(e)
            }
          }
          Some(MappingValue(merged))
        }
        (Some(MapValue(ea)), Some(MapValue(eb))) if op == Add => {
          let merged : Array[ValueEntry] = []
          for e in ea {
            merged.push(e)
          }
          for e in eb {
            let mut replaced = false
            for i = 0; i < merged.length(); i = i + 1 {
              if merged[i].key == e.key {
                merged[i] = e
                replaced = true
                break
              }
            }
            if !replaced {
              merged.push(e)
            }
          }
          Some(MapValue(merged))
        }
        (Some(StringValue(sa)), Some(StringValue(sb))) if op == Add =>
          Some(StringValue(sa + sb))
        // PKL-148b: Duration / DataSize scalar arithmetic. Multiplying
        // by Int / Float scales the magnitude; dividing by Int / Float
        // scales it down. Apple Pkl preserves the magnitude unit.
        (Some(DurationValue(n, unit)), Some(IntValue(k))) if op == Multiply =>
          Some(DurationValue(n * k.to_double(), unit))
        (Some(DurationValue(n, unit)), Some(FloatValue(k))) if op == Multiply =>
          Some(DurationValue(n * k, unit))
        (Some(IntValue(k)), Some(DurationValue(n, unit))) if op == Multiply =>
          Some(DurationValue(n * k.to_double(), unit))
        (Some(FloatValue(k)), Some(DurationValue(n, unit))) if op == Multiply =>
          Some(DurationValue(n * k, unit))
        (Some(DurationValue(n, unit)), Some(IntValue(k))) if op == Divide &&
          k != 0 => Some(DurationValue(n / k.to_double(), unit))
        (Some(DurationValue(n, unit)), Some(FloatValue(k))) if op == Divide &&
          k != 0.0 => Some(DurationValue(n / k, unit))
        (Some(DurationValue(n, unit)), Some(IntValue(k))) if op == IntDivide &&
          k != 0 => Some(DurationValue(double_trunc(n / k.to_double()), unit))
        (Some(DurationValue(n, unit)), Some(FloatValue(k))) if op == IntDivide &&
          k != 0.0 => Some(DurationValue(double_trunc(n / k), unit))
        (Some(DurationValue(n, unit)), Some(IntValue(k))) if op == Power =>
          Some(DurationValue(@math.pow(n, k.to_double()), unit))
        (Some(DurationValue(n, unit)), Some(FloatValue(k))) if op == Power =>
          Some(DurationValue(@math.pow(n, k), unit))
        (Some(DataSizeValue(n, unit)), Some(IntValue(k))) if op == Multiply =>
          Some(DataSizeValue(n * k.to_double(), unit))
        (Some(DataSizeValue(n, unit)), Some(FloatValue(k))) if op == Multiply =>
          Some(DataSizeValue(n * k, unit))
        (Some(IntValue(k)), Some(DataSizeValue(n, unit))) if op == Multiply =>
          Some(DataSizeValue(n * k.to_double(), unit))
        (Some(FloatValue(k)), Some(DataSizeValue(n, unit))) if op == Multiply =>
          Some(DataSizeValue(n * k, unit))
        (Some(DataSizeValue(n, unit)), Some(IntValue(k))) if op == Divide &&
          k != 0 => Some(DataSizeValue(n / k.to_double(), unit))
        (Some(DataSizeValue(n, unit)), Some(FloatValue(k))) if op == Divide &&
          k != 0.0 => Some(DataSizeValue(n / k, unit))
        (Some(DataSizeValue(n, unit)), Some(IntValue(k))) if op == IntDivide &&
          k != 0 => Some(DataSizeValue(double_trunc(n / k.to_double()), unit))
        (Some(DataSizeValue(n, unit)), Some(FloatValue(k))) if op == IntDivide &&
          k != 0.0 => Some(DataSizeValue(double_trunc(n / k), unit))
        (Some(DataSizeValue(n, unit)), Some(IntValue(k))) if op == Power =>
          Some(DataSizeValue(@math.pow(n, k.to_double()), unit))
        (Some(DataSizeValue(n, unit)), Some(FloatValue(k))) if op == Power =>
          Some(DataSizeValue(@math.pow(n, k), unit))
        (Some(DurationValue(_, _) as a), Some(b)) if op != Equal &&
          op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        (Some(a), Some(DurationValue(_, _) as b)) if op != Equal &&
          op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        (Some(DataSizeValue(_, _) as a), Some(b)) if op != Equal &&
          op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        (Some(a), Some(DataSizeValue(_, _) as b)) if op != Equal &&
          op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        // Sets are unordered; their derived `==` would compare element
        // arrays positionally. Fall back to a multiset comparison
        // (same elements, ignoring order) so `Set(1, 2) == Set(2, 1)`.
        (Some(SetValue(xs)), Some(SetValue(ys))) if op == Equal =>
          Some(BoolValue(set_values_equal(xs, ys)))
        (Some(SetValue(xs)), Some(SetValue(ys))) if op == NotEqual =>
          Some(BoolValue(!set_values_equal(xs, ys)))
        // Objects compare by visible-member content rather than by the
        // derived `==`. Apple Pkl treats property order as irrelevant
        // (`{foo=1; bar=2} == {bar=2; foo=1}`) and ignores hidden /
        // `local` members in the comparison.
        (Some(ObjectValue(xs)), Some(ObjectValue(ys))) if op == Equal =>
          Some(BoolValue(object_values_equal(xs, ys)))
        (Some(ObjectValue(xs)), Some(ObjectValue(ys))) if op == NotEqual =>
          Some(BoolValue(!object_values_equal(xs, ys)))
        // Maps and Mappings carry key/value pairs whose order is also
        // immaterial. Compare as bag-of-entries.
        (Some(MapValue(xs)), Some(MapValue(ys))) if op == Equal =>
          Some(BoolValue(map_entries_equal(xs, ys)))
        (Some(MapValue(xs)), Some(MapValue(ys))) if op == NotEqual =>
          Some(BoolValue(!map_entries_equal(xs, ys)))
        (Some(MappingValue(xs)), Some(MappingValue(ys))) if op == Equal =>
          Some(BoolValue(map_entries_equal(xs, ys)))
        (Some(MappingValue(xs)), Some(MappingValue(ys))) if op == NotEqual =>
          Some(BoolValue(!map_entries_equal(xs, ys)))
        (Some(BytesValue(_) as a), Some(b)) if op != Equal && op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        (Some(a), Some(BytesValue(_) as b)) if op != Equal && op != NotEqual => {
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, a, b)),
          )
          None
        }
        (Some(a), Some(b)) if op == Equal => Some(BoolValue(values_equal(a, b)))
        (Some(a), Some(b)) if op == NotEqual =>
          Some(BoolValue(!values_equal(a, b)))
        (Some(_), Some(_)) => {
          let message = match op {
            Add
            | Subtract
            | Multiply
            | Divide
            | IntDivide
            | Modulo
            | Power
            | LessThan
            | LessOrEqual
            | GreaterThan
            | GreaterOrEqual =>
              "operator \{operator_name(op)} expects Int operands"
            _ => "operator \{operator_name(op)} expects compatible operands"
          }
          diagnostics.push(diag(message))
          None
        }
        _ => None
      }
    }
    ConditionalExpr(condition_expr, then_expr, else_expr) =>
      match
        eval_expr_with_bindings(
          condition_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(BoolValue(true)) =>
          eval_expr_with_bindings(
            then_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
        Some(BoolValue(false)) =>
          eval_expr_with_bindings(
            else_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
        Some(NullValue) => {
          // PKL-148c: Apple Pkl renders null condition as a dedicated
          // form (no `Value: ...` segment).
          diagnostics.push(
            diag("Expected value of type `Boolean`, but got `null`."),
          )
          None
        }
        Some(other) => {
          diagnostics.push(
            diag(
              "Expected value of type `Boolean`, but got type `\{eval_value_type_name(other)}`. Value: \{render_pcf_value_inline(other)}",
            ),
          )
          None
        }
        None => None
      }
    ForGenerator(var1, var2, source_expr, body_members, var1_type, var2_type) =>
      eval_for_generator(
        var1,
        var2,
        source_expr,
        body_members,
        var1_type,
        var2_type,
        bindings,
        env,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
        defer_generated_member_errors=false,
      )
    ErrorExpr(message) => {
      diagnostics.push(diag(message))
      None
    }
    UnsupportedExpr => {
      diagnostics.push(diag("unsupported expression"))
      None
    }
    // PKL-136: a stray `WhenSpread` outside a Listing/Mapping body
    // simply evaluates its inner — the listing/mapping arms above pluck
    // it out before reaching here. Keep the arm explicit so future eval
    // changes don't silently drop the wrapper.
    WhenSpread(inner) =>
      eval_expr_with_bindings(
        inner, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
    // PKL-103: `read?(uri)` returns `null` instead of pushing a
    // diagnostic when the URI is missing or rejected by the sandbox
    // policy. Today only `read` is wired; other null-safe call
    // intrinsics will reuse the same arm.
    NullSafeCallExpr(callee, arguments) =>
      match callee {
        Identifier("read") => {
          if arguments.length() != 1 {
            diagnostics.push(diag("read? expects exactly one argument"))
            return None
          }
          let uri_value = eval_expr_with_bindings(
            arguments[0],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          )
          match uri_value {
            Some(StringValue(uri)) => {
              let probe_diagnostics : Array[Diagnostic] = []
              match
                eval_read_uri(
                  uri,
                  current_module_path_from_cache(cache),
                  probe_diagnostics,
                ) {
                Some(value) => Some(value)
                None =>
                  if probe_diagnostics.length() > 0 &&
                    is_read_resource_refusal(probe_diagnostics[0].message) {
                    diagnostics.push(probe_diagnostics[0])
                    None
                  } else {
                    Some(NullValue)
                  }
              }
            }
            Some(_) => {
              diagnostics.push(diag("read? expects a String argument"))
              None
            }
            None => None
          }
        }
        _ => {
          diagnostics.push(diag("null-safe call is only supported for read?"))
          None
        }
      }
    // PKL-128: render each part of an interpolated string and
    // concatenate. Non-string parts route through
    // `value_to_string_for_join`, which already handles every Value
    // variant (used by `Listing.join`).
    InterpolatedString(parts) => {
      let buf = StringBuilder::new()
      let mut ok = true
      for part in parts {
        match
          eval_expr_with_bindings(
            part, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ) {
          Some(value) =>
            buf.write_string(
              dispatch_value_to_string(
                value, bindings, env, class_env, cache, stack, declarations, diagnostics,
                resolve_import,
              ),
            )
          None => ok = false
        }
      }
      if ok {
        Some(StringValue(buf.to_string()))
      } else {
        None
      }
    }
  }
}

///|
/// PKL-148bh: render a value to string for interpolation contexts.
/// Apple Pkl's `"\(<value>)"` calls the value's `toString()`
/// method when the class declares one, otherwise falls back to the
/// canonical PCF compact form. This helper checks for a
/// user-declared `toString` on the value's class tag and dispatches
/// through `eval_class_method_call`; on miss it falls back to
/// `value_to_string_for_join`.
fn dispatch_value_to_string(
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> String {
  match first_deferred_error_message(value) {
    Some(message) => {
      diagnostics.push(diag(message))
      return ""
    }
    None => ()
  }
  match value {
    ObjectValue(members) => {
      // PKL-152: reflect Class / TypeAlias mirrors are projected
      // through their qualified name when stringified in interpolation
      // (api/anyConverter / api/reflect*). Without this branch the
      // fallback renders the full `new { simpleName=...; ... }` shape.
      match lookup_member(members, hidden_member_name("__kind")) {
        Some(StringValue("Class")) | Some(StringValue("TypeAlias")) =>
          match lookup_member(members, hidden_member_name("__qualified_name")) {
            Some(StringValue(s)) => return s
            _ =>
              match lookup_member(members, "name") {
                Some(StringValue(s)) => return s
                _ => ()
              }
          }
        _ => ()
      }
      match find_object_class_tag(members) {
        Some(class_name) =>
          if class_name != "Dynamic" &&
            lookup_class_method(class_env, class_name, "toString") is Some(_) {
            let method_cache = copy_value_bindings(cache)
            push_receiver_method_bindings(method_cache, members)
            push_sibling_class_methods(
              method_cache, class_name, class_env, env, cache,
            )
            push_super_dispatch_marker(method_cache, class_name)
            let method_diags : Array[Diagnostic] = []
            match lookup_class_method(class_env, class_name, "toString") {
              Some(method_decl) =>
                match method_decl.body {
                  Some(body) =>
                    match
                      eval_expr_with_bindings(
                        body, bindings, env, class_env, method_cache, stack, declarations,
                        method_diags, resolve_import,
                      ) {
                      Some(StringValue(s)) => return s
                      _ => ()
                    }
                  None => ()
                }
              None => ()
            }
            for d in method_diags {
              diagnostics.push(d)
            }
            value_to_string_for_join(value)
          } else {
            value_to_string_for_join(value)
          }
        None => value_to_string_for_join(value)
      }
    }
    _ => value_to_string_for_join(value)
  }
}

///|
fn current_module_path_from_cache(cache : Array[ValueBinding]) -> String? {
  match lookup_value(cache, "@__module_path") {
    Some(StringValue(path)) => Some(path)
    _ => None
  }
}

///|
fn module_path_from_members(members : Array[ValueMember]) -> String? {
  match lookup_member(members, module_metadata_path_name()) {
    Some(StringValue(path)) => Some(path)
    _ => None
  }
}

///|
fn module_path_dir(path : String) -> String {
  let normalized = normalize_path_segments(path)
  match normalized.rev_find("/") {
    Some(idx) => String::unsafe_substring(normalized, start=0, end=idx)
    None => ""
  }
}

///|
fn path_segments_value(path : String) -> Value {
  let elements : Array[Value] = []
  if path.length() == 0 {
    return ListValue(elements)
  }
  let mut start = 0
  for i = 0; i < path.length(); i = i + 1 {
    if path[i].to_int().unsafe_to_char() == '/' {
      if i > start {
        elements.push(
          StringValue(String::unsafe_substring(path, start~, end=i)),
        )
      }
      start = i + 1
    }
  }
  if start < path.length() {
    elements.push(
      StringValue(String::unsafe_substring(path, start~, end=path.length())),
    )
  }
  ListValue(elements)
}

///|
fn module_path_diagnostic_uri(path : String) -> String {
  let uri = if path.find("://") is Some(_) || path.has_prefix("pkl:") {
    path
  } else if path.has_prefix("/") {
    "file://" + path
  } else {
    "file:///" + path
  }
  let marker = "/third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests"
  match uri.find(marker) {
    Some(idx) =>
      "file:///$snippetsDir" +
      String::unsafe_substring(
        uri,
        start=idx + marker.length(),
        end=uri.length(),
      )
    None => uri
  }
}

///|
fn eval_module_relative_path_to(
  receiver_members : Array[ValueMember],
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if arguments.length() != 1 {
    diagnostics.push(
      diag(
        "Module.relativePathTo expects 1 argument, got \{arguments.length()}",
      ),
    )
    return None
  }
  let base_path = match module_path_from_members(receiver_members) {
    Some(path) => path
    None => {
      diagnostics.push(diag("relativePathTo expects a module receiver"))
      return None
    }
  }
  let target = match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(ObjectValue(members)) => members
    Some(_) => {
      diagnostics.push(diag("relativePathTo expects a module argument"))
      return None
    }
    None => return None
  }
  let target_path = match module_path_from_members(target) {
    Some(path) => path
    None => {
      diagnostics.push(diag("relativePathTo expects a module argument"))
      return None
    }
  }
  let base_dir = module_path_dir(base_path)
  let target_dir = module_path_dir(target_path)
  if target_dir == base_dir {
    return Some(ListValue([]))
  }
  let prefix = if base_dir == "" { "" } else { base_dir + "/" }
  if target_dir.has_prefix(prefix) {
    let rest = String::unsafe_substring(
      target_dir,
      start=prefix.length(),
      end=target_dir.length(),
    )
    Some(path_segments_value(rest))
  } else {
    diagnostics.push(
      diag(
        "No descendent path exists between modules `\{module_path_diagnostic_uri(base_path)}` and `\{module_path_diagnostic_uri(target_path)}`.",
      ),
    )
    None
  }
}

///|
fn module_path_basename(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) =>
      String::unsafe_substring(path, start=idx + 1, end=path.length())
    None => path
  }
}

///|
fn import_uri_matches_current_module(uri : String, path : String) -> Bool {
  let basename = module_path_basename(path)
  uri == path || uri == basename || uri == "./" + basename
}

///|
fn current_module_snapshot_for_import(
  uri : String,
  cache : Array[ValueBinding],
) -> Value? {
  match current_module_path_from_cache(cache) {
    Some(path) =>
      if import_uri_matches_current_module(uri, path) {
        let members : Array[ValueMember] = []
        for binding in cache {
          if binding.name == "super" ||
            binding.name == "this" ||
            binding.name.has_prefix("@") ||
            is_invisible_member_name(binding.name) {
            continue
          }
          members.push({
            name: binding.name,
            value: binding.value,
            source: None,
            annotations: [],
          })
        }
        Some(ObjectValue(members))
      } else {
        None
      }
    None => None
  }
}

///|
fn eval_for_generator(
  var1 : String,
  var2 : String?,
  source_expr : Expr,
  body_members : Array[ObjectMember],
  var1_type : String?,
  var2_type : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  body_implicit_env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  defer_generated_member_errors~ : Bool,
) -> Value? {
  let source = eval_expr_with_bindings(
    source_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
    resolve_import,
  )
  match source {
    Some(source_value) =>
      match for_generator_iteration_entries(source_value) {
        Some(entries) => {
          let mut accumulated : Array[ValueMember] = []
          for i = 0; i < entries.length(); i = i + 1 {
            let entry = entries[i]
            let iter_cache = match
              bind_for_generator_iteration(
                var1, var2, var1_type, var2_type, entry, cache, class_env, declarations,
                diagnostics,
              ) {
              Some(iter_cache) => iter_cache
              None => return None
            }
            let iter_members = eval_object_members_with_implicit_env(
              body_members,
              bindings,
              env,
              body_implicit_env,
              class_env,
              iter_cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
              defer_property_errors=defer_generated_member_errors,
            )
            accumulated = merge_for_generator_members(
              accumulated, iter_members, i,
            )
          }
          Some(ObjectValue(accumulated))
        }
        None => {
          diagnostics.push(
            diag("for-generator source must be Listing or Mapping"),
          )
          None
        }
      }
    None => None
  }
}

///|
fn for_generator_binding_type_rejection_message(
  type_name : String?,
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
) -> String? {
  eval_callable_argument_type_rejection_message(
    type_name, value, class_env, cache, declarations,
  )
}

///|
fn bind_for_generator_iteration(
  var1 : String,
  var2 : String?,
  var1_type : String?,
  var2_type : String?,
  entry : ValueEntry,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Array[ValueBinding]? {
  let first_value = match var2 {
    Some(_) => entry.key
    None => entry.value
  }
  match
    for_generator_binding_type_rejection_message(
      var1_type, first_value, class_env, cache, declarations,
    ) {
    Some(message) => {
      diagnostics.push(diag(message))
      return None
    }
    None => ()
  }
  match var2 {
    Some(_) =>
      match
        for_generator_binding_type_rejection_message(
          var2_type,
          entry.value,
          class_env,
          cache,
          declarations,
        ) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
    None => ()
  }
  let iter_cache = copy_value_bindings(cache)
  match var2 {
    Some(name2) => {
      iter_cache.push({ name: var1, value: entry.key })
      iter_cache.push({ name: name2, value: entry.value })
    }
    None => iter_cache.push({ name: var1, value: entry.value })
  }
  Some(iter_cache)
}

///|
fn indexed_for_generator_entries(elements : Array[Value]) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for i = 0; i < elements.length(); i = i + 1 {
    entries.push({ key: IntValue(i.to_int64()), value: elements[i] })
  }
  entries
}

///|
fn subscript_value_entry(value : Value) -> ValueEntry? {
  match value {
    ObjectValue(pair_members) =>
      match
        (
          lookup_member(pair_members, "@key"),
          lookup_member(pair_members, "@value"),
        ) {
        (Some(key), Some(value)) => Some({ key, value })
        _ => None
      }
    _ => None
  }
}

///|
fn value_member_subscript_key(value_member : ValueMember) -> Value? {
  if !value_member.name.has_prefix("@subscript$") {
    return None
  }
  match subscript_value_entry(value_member.value) {
    Some(entry) => Some(entry.key)
    None => None
  }
}

///|
fn push_dynamic_object_member(
  values : Array[ValueMember],
  value_member : ValueMember,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match value_member_subscript_key(value_member) {
    Some(key) => {
      for existing in values {
        match value_member_subscript_key(existing) {
          Some(existing_key) =>
            if existing_key == key {
              diagnostics.push(
                diag(
                  "Duplicate definition of member `\{render_pcf_value_inline(key)}`.",
                ),
              )
              return false
            }
          None => ()
        }
      }
      values.push(value_member)
      true
    }
    None => {
      values.push(value_member)
      true
    }
  }
}

///|
fn push_mixin_object_member(
  values : Array[ValueMember],
  value_member : ValueMember,
  diagnostics : Array[Diagnostic],
) -> Bool {
  if value_member.name.has_prefix("@element$") ||
    value_member.name.has_prefix("@subscript$") {
    return push_dynamic_object_member(values, value_member, diagnostics)
  }
  for i = 0; i < values.length(); i = i + 1 {
    if !is_invisible_member_name(values[i].name) &&
      values[i].name == value_member.name {
      values[i] = value_member
      return true
    }
  }
  values.push(value_member)
  true
}

///|
fn dynamic_object_for_generator_entries(
  members : Array[ValueMember],
) -> Array[ValueEntry] {
  let properties : Array[ValueEntry] = []
  let entries : Array[ValueEntry] = []
  let elements : Array[ValueEntry] = []
  let mut element_index = 0
  for value_member in members {
    if is_invisible_member_name(value_member.name) {
      continue
    }
    if value_member.name.has_prefix("@subscript$") {
      match subscript_value_entry(value_member.value) {
        Some(entry) => entries.push(entry)
        None => ()
      }
    } else if value_member.name.has_prefix("@element$") {
      elements.push({
        key: IntValue(element_index.to_int64()),
        value: value_member.value,
      })
      element_index = element_index + 1
    } else {
      properties.push({
        key: StringValue(strip_member_visibility_prefix(value_member.name)),
        value: value_member.value,
      })
    }
  }
  let out : Array[ValueEntry] = []
  for entry in properties {
    out.push(entry)
  }
  for entry in entries {
    out.push(entry)
  }
  for entry in elements {
    out.push(entry)
  }
  out
}

///|
fn for_generator_iteration_entries(value : Value) -> Array[ValueEntry]? {
  match value {
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => Some(indexed_for_generator_entries(elements))
    IntSeqValue(start_v, end_v, step_v) =>
      Some(
        indexed_for_generator_entries(
          intseq_materialize(start_v, end_v, step_v),
        ),
      )
    BytesValue(bytes) =>
      Some(indexed_for_generator_entries(bytes_materialize(bytes)))
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => Some(entries)
    ObjectValue(members) => Some(dynamic_object_for_generator_entries(members))
    _ => None
  }
}

///|
fn merge_for_generator_members(
  accumulated : Array[ValueMember],
  iter_members : Array[ValueMember],
  iteration : Int,
) -> Array[ValueMember] {
  let prepared : Array[ValueMember] = []
  for i = 0; i < iter_members.length(); i = i + 1 {
    let value_member = iter_members[i]
    if value_member.name.has_prefix("@element$") ||
      value_member.name.has_prefix("@subscript$") {
      prepared.push({
        name: value_member.name +
        "$for" +
        iteration.to_string() +
        "$" +
        i.to_string(),
        value: value_member.value,
        source: value_member.source,
        annotations: value_member.annotations,
      })
    } else {
      prepared.push(value_member)
    }
  }
  merge_value_members(accumulated, prepared)
}

///|
fn collect_class_default_properties_in_order(
  out : Array[ClassProperty],
  type_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Unit {
  collect_class_default_properties_in_order_seen(
    out,
    type_name,
    class_env,
    declarations,
    [],
  )
}

///|
fn collect_class_default_properties_in_order_seen(
  out : Array[ClassProperty],
  type_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  seen : Array[String],
) -> Unit {
  if contains_string(seen, type_name) {
    return
  }
  seen.push(type_name)
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent_name) => {
          let aliases = eval_type_alias_bindings(declarations)
          collect_class_default_properties_in_order_seen(
            out,
            eval_resolved_type_alias(parent_name, aliases),
            class_env,
            declarations,
            seen,
          )
        }
        None => ()
      }
      for property in class_binding.properties {
        match property.value {
          Some(_) => out.push(property)
          None => ()
        }
      }
    }
    None => ()
  }
}

///|
fn push_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn collect_constructor_override_names_from_expr(
  expr : Expr,
  names : Array[String],
) -> Unit {
  match expr {
    ObjectLiteral(members) =>
      for object_member in members {
        if object_member.name == "@when" {
          collect_constructor_override_names_from_expr(
            object_member.value,
            names,
          )
        } else if !is_local_member_name(object_member.name) {
          push_unique_name(
            names,
            strip_member_visibility_prefix(object_member.name),
          )
        }
      }
    ConditionalExpr(_, then_expr, else_expr) => {
      collect_constructor_override_names_from_expr(then_expr, names)
      collect_constructor_override_names_from_expr(else_expr, names)
    }
    _ => ()
  }
}

///|
fn constructor_override_names(members : Array[ObjectMember]) -> Array[String] {
  let names : Array[String] = []
  for object_member in members {
    if object_member.name == "@when" {
      collect_constructor_override_names_from_expr(object_member.value, names)
      continue
    }
    if is_local_member_name(object_member.name) {
      continue
    }
    push_unique_name(names, strip_member_visibility_prefix(object_member.name))
  }
  names
}

///|
fn push_current_members_as_env(
  local_env : Array[ValueBinding],
  members : Array[ValueMember],
) -> Unit {
  for value_member in members {
    let bare = strip_member_visibility_prefix(value_member.name)
    if !is_invisible_member_name(value_member.name) ||
      is_local_member_name(value_member.name) ||
      is_hidden_member_name(value_member.name) {
      local_env.push({ name: bare, value: value_member.value })
    }
  }
}

///|
fn replace_member_value_by_bare_name(
  members : Array[ValueMember],
  name : String,
  value : Value,
) -> Bool {
  for i = 0; i < members.length(); i = i + 1 {
    if strip_member_visibility_prefix(members[i].name) == name {
      members[i] = {
        name: members[i].name,
        value,
        source: None,
        annotations: members[i].annotations,
      }
      return true
    }
  }
  false
}

///|
fn remove_pending_error_member_by_bare_name(
  members : Array[ValueMember],
  name : String,
) -> Unit {
  let mut i = 0
  while i < members.length() {
    if is_error_member_name(members[i].name) {
      let inner = String::unsafe_substring(
        members[i].name,
        start=error_member_prefix.length(),
        end=members[i].name.length(),
      )
      if strip_member_visibility_prefix(inner) == name {
        let _ = members.remove(i)
        continue
      }
    }
    i = i + 1
  }
}

///|
fn reeval_class_defaults_after_constructor_overrides(
  type_name : String,
  constructor_members : Array[ObjectMember],
  merged : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  let constructor_names = constructor_override_names(constructor_members)
  if constructor_names.length() == 0 {
    return merged
  }
  let properties : Array[ClassProperty] = []
  collect_class_default_properties_in_order(
    properties, type_name, class_env, declarations,
  )
  if properties.length() == 0 {
    return merged
  }
  let current : Array[ValueMember] = []
  for value_member in merged {
    current.push(value_member)
  }
  let changed_names : Array[String] = []
  for name in constructor_names {
    changed_names.push(name)
  }
  for property in properties {
    let mut directly_overridden = false
    for name in constructor_names {
      if name == property.name {
        directly_overridden = true
        break
      }
    }
    if !directly_overridden {
      for value_member in current {
        if strip_member_visibility_prefix(value_member.name) == property.name &&
          value_member.source is Some(_) {
          directly_overridden = true
          break
        }
      }
    }
    if directly_overridden {
      continue
    }
    let source = match property.value {
      Some(expr) => expr
      None => continue
    }
    let local_env = copy_value_bindings(env)
    push_current_members_as_env(local_env, current)
    let reeval_cache = copy_value_bindings(cache)
    reeval_cache.push({ name: "this", value: ObjectValue(current) })
    reeval_cache.push({
      name: "outer",
      value: module_object_value_from_scope(
        bindings,
        env,
        cache,
        stack,
        const_context=true,
      ),
    })
    reeval_cache.push({
      name: "@__constructing_class",
      value: StringValue(type_name),
    })
    reeval_cache.push({ name: "@__class_default_scope", value: BoolValue(true) })
    push_super_dispatch_marker(reeval_cache, type_name)
    push_sibling_class_methods(
      reeval_cache, type_name, class_env, local_env, reeval_cache,
    )
    match
      eval_expr_with_bindings(
        source,
        bindings,
        local_env,
        class_env,
        cache_for_nested_object_value(source, reeval_cache, current),
        stack,
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(raw_value) => {
        let value = coerce_value_to_annotated_type(
          raw_value,
          property.type_name,
        )
        if replace_member_value_by_bare_name(current, property.name, value) {
          remove_pending_error_member_by_bare_name(current, property.name)
          push_unique_name(changed_names, property.name)
        }
      }
      None => ()
    }
  }
  current
}

///|
fn eval_xml_constructor_call(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let ctor_name = match callee {
    MemberAccess(Identifier(import_name), name) =>
      if xml_constructor_name(name) is Some(kind) &&
        is_xml_constructor_receiver(import_name, name, env, class_env, cache) {
        Some(kind)
      } else {
        None
      }
    _ => None
  }
  match ctor_name {
    Some("Element") =>
      xml_single_string_constructor(
        "Element", "name", arguments, bindings, env, class_env, cache, stack, declarations,
        diagnostics, resolve_import,
      )
    Some("CData") =>
      xml_single_string_constructor(
        "CData", "text", arguments, bindings, env, class_env, cache, stack, declarations,
        diagnostics, resolve_import,
      )
    Some("Comment") =>
      xml_single_string_constructor(
        "Comment", "text", arguments, bindings, env, class_env, cache, stack, declarations,
        diagnostics, resolve_import,
      )
    Some("Inline") => {
      if arguments.length() != 1 {
        diagnostics.push(diag("xml.Inline expects exactly one argument"))
        return Some(NullValue)
      }
      match
        eval_expr_with_bindings(
          arguments[0],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          Some(
            ObjectValue(
              tag_object_with_class(
                [
                  {
                    name: hidden_member_name("__xmlKind"),
                    value: StringValue("Inline"),
                    source: None,
                    annotations: [],
                  },
                  { name: "value", value, source: None, annotations: [] },
                ],
                "xml.Inline",
              ),
            ),
          )
        None => Some(NullValue)
      }
    }
    Some(_) => None
    None => None
  }
}

///|
fn is_xml_constructor_receiver(
  import_name : String,
  constructor_name : String,
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> Bool {
  if import_name == "xml" {
    return true
  }
  if lookup_class_binding(class_env, import_name + "." + constructor_name)
    is Some(_) {
    return true
  }
  match lookup_value(cache, "@__module_imports") {
    Some(MapValue(entries)) =>
      for entry in entries {
        if entry.key == StringValue(import_name) &&
          entry.value == StringValue("pkl:xml") {
          return true
        }
      }
    _ => ()
  }
  match lookup_value(env, import_name) {
    Some(ObjectValue(members)) =>
      match module_members_name(members) {
        Some("pkl:xml") => true
        _ => false
      }
    _ => false
  }
}

///|
fn xml_constructor_name(name : String) -> String? {
  match name {
    "Element" | "Inline" | "CData" | "Comment" => Some(name)
    _ => None
  }
}

///|
fn tag_xml_function_element_from_source(source : Expr, value : Value) -> Value {
  match tag_xml_value_from_runtime_type(value) {
    Some(tagged) => return tagged
    None => ()
  }
  match source {
    CallExpr(Identifier("comment"), _) =>
      match value {
        ObjectValue(members) => {
          let tagged_members = if lookup_member(members, "__xmlKind") is Some(_) {
            members
          } else {
            let next : Array[ValueMember] = [
              {
                name: hidden_member_name("__xmlKind"),
                value: StringValue("Comment"),
                source: None,
                annotations: [],
              },
            ]
            for field in members {
              next.push(field)
            }
            next
          }
          ObjectValue(tag_object_with_class(tagged_members, "xml.Comment"))
        }
        _ => value
      }
    _ => value
  }
}

///|
fn tag_xml_value_from_runtime_type(value : Value) -> Value? {
  match value {
    ObjectValue(members) => {
      let kind = match eval_value_type_name(value) {
        name if name.has_suffix("Element") => Some("Element")
        name if name.has_suffix("Inline") => Some("Inline")
        name if name.has_suffix("CData") => Some("CData")
        name if name.has_suffix("Comment") => Some("Comment")
        _ => None
      }
      match kind {
        Some(xml_kind) =>
          if lookup_member(members, "__xmlKind") is Some(_) {
            Some(value)
          } else {
            let next : Array[ValueMember] = [
              {
                name: hidden_member_name("__xmlKind"),
                value: StringValue(xml_kind),
                source: None,
                annotations: [],
              },
            ]
            for field in members {
              next.push(field)
            }
            Some(ObjectValue(next))
          }
        None => None
      }
    }
    _ => None
  }
}

///|
fn xml_single_string_constructor(
  class_name : String,
  field_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if arguments.length() != 1 {
    diagnostics.push(diag("xml.\{class_name} expects exactly one argument"))
    return Some(NullValue)
  }
  match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(StringValue(text)) =>
      Some(
        ObjectValue(
          tag_object_with_class(
            [
              {
                name: hidden_member_name("__xmlKind"),
                value: StringValue(class_name),
                source: None,
                annotations: [],
              },
              {
                name: field_name,
                value: StringValue(text),
                source: None,
                annotations: [],
              },
            ],
            "xml.\{class_name}",
          ),
        ),
      )
    Some(_) => {
      diagnostics.push(diag("xml.\{class_name} expects a String argument"))
      Some(NullValue)
    }
    None => Some(NullValue)
  }
}

///|
fn eval_value_renderer_method_error(
  format : String,
  method_name : String,
  value : Value,
  cache : Array[ValueBinding],
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> String? {
  match format {
    "json" => renderer_unsupported_value_error("JSON", value, cache)
    "yaml" =>
      match yaml_mixed_object_error(value) {
        Some(message) => Some(message)
        None => renderer_unsupported_value_error("YAML", value, cache)
      }
    "properties" =>
      if method_name == "renderDocument" {
        properties_renderer_document_error(value, cache)
      } else {
        properties_renderer_value_error(value, cache)
      }
    "plist" =>
      if method_name == "renderDocument" {
        plist_renderer_document_error(value, cache)
      } else {
        plist_renderer_value_error(value, cache)
      }
    "pcf" =>
      if method_name == "renderDocument" {
        pcf_renderer_document_error(value, cache)
      } else {
        pcf_renderer_value_error(value, cache)
      }
    "textproto" =>
      protobuf_renderer_value_error(value, cache, class_env, declarations)
    _ => None
  }
}

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
fn collect_class_properties_in_order(
  out : Array[ClassProperty],
  type_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Unit {
  collect_class_properties_in_order_seen(
    out,
    type_name,
    class_env,
    declarations,
    [],
  )
}

///|
fn collect_class_properties_in_order_seen(
  out : Array[ClassProperty],
  type_name : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
  seen : Array[String],
) -> Unit {
  if contains_string(seen, type_name) {
    return
  }
  seen.push(type_name)
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent_name) => {
          let aliases = eval_type_alias_bindings(declarations)
          collect_class_properties_in_order_seen(
            out,
            eval_resolved_type_alias(parent_name, aliases),
            class_env,
            declarations,
            seen,
          )
        }
        None => ()
      }
      for property in class_binding.properties {
        out.push(property)
      }
    }
    None => ()
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

///|
fn renderer_unsupported_value_error(
  label : String,
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    DurationValue(_, _)
    | DataSizeValue(_, _)
    | PairValue(_, _)
    | IntSeqValue(_, _, _)
    | FunctionValue(_, _, _, _, _) =>
      Some(renderer_cannot_render_message(label, value, cache, false))
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(renderer_cannot_render_message(label, value, cache, false))
        _ => None
      }
    _ => None
  }
}

///|
fn pcf_renderer_value_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    FunctionValue(_, _, _, _, _) =>
      Some(renderer_cannot_render_message("Pcf", value, cache, false))
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(renderer_cannot_render_message("Pcf", value, cache, false))
        _ => None
      }
    _ => None
  }
}

///|
fn properties_renderer_value_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    IntValue(_)
    | FloatValue(_)
    | BoolValue(_)
    | StringValue(_)
    | NullValue
    | RegexValue(_)
    | BytesValue(_) => None
    MappingValue(_) | DefaultedMappingValue(_, _, _) | ObjectValue(_) =>
      Some(renderer_cannot_render_message("Properties", value, cache, true))
    _ => Some(renderer_cannot_render_message("Properties", value, cache, false))
  }
}

///|
fn plist_renderer_value_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    NullValue
    | DurationValue(_, _)
    | DataSizeValue(_, _)
    | PairValue(_, _)
    | IntSeqValue(_, _, _)
    | FunctionValue(_, _, _, _, _) =>
      Some(
        renderer_cannot_render_message("XML property list", value, cache, false),
      )
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(
            renderer_cannot_render_message(
              "XML property list", value, cache, false,
            ),
          )
        _ => None
      }
    _ => None
  }
}

///|
fn pcf_renderer_document_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(
            renderer_top_level_message(
              "a Pcf document", "`Typed` or `Dynamic`", value, cache, true,
            ),
          )
        _ => None
      }
    _ =>
      Some(
        renderer_top_level_message(
          "a Pcf document", "`Typed` or `Dynamic`", value, cache, true,
        ),
      )
  }
}

///|
fn properties_renderer_document_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(
            renderer_top_level_message(
              "a Java properties file", "`Typed`, `Dynamic`, `Mapping`, or `Map`",
              value, cache, true,
            ),
          )
        _ => None
      }
    MappingValue(_) | DefaultedMappingValue(_, _, _) | MapValue(_) => None
    _ =>
      Some(
        renderer_top_level_message(
          "a Java properties file", "`Typed`, `Dynamic`, `Mapping`, or `Map`", value,
          cache, true,
        ),
      )
  }
}

///|
fn plist_renderer_document_error(
  value : Value,
  cache : Array[ValueBinding],
) -> String? {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") | Some("TypeAlias") =>
          Some(
            renderer_top_level_message(
              "an XML property list", "`Typed`, `Dynamic`, `Listing`, `Mapping`, `List`, `Set`, or `Map`",
              value, cache, false,
            ),
          )
        _ => None
      }
    MappingValue(_)
    | DefaultedMappingValue(_, _, _)
    | MapValue(_)
    | ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | ListValue(_)
    | SetValue(_) => None
    FunctionValue(_, _, _, _, _) =>
      Some(
        renderer_cannot_render_message("XML property list", value, cache, false),
      )
    _ =>
      Some(
        renderer_top_level_message(
          "an XML property list", "`Typed`, `Dynamic`, `Listing`, `Mapping`, `List`, `Set`, or `Map`",
          value, cache, false,
        ),
      )
  }
}

///|
fn renderer_cannot_render_message(
  label : String,
  value : Value,
  cache : Array[ValueBinding],
  placeholders : Bool,
) -> String {
  "Cannot render value of type `\{renderer_error_type_name(value, cache)}` as \{label}. Value: \{renderer_error_value_text(value, cache, placeholders)}"
}

///|
fn renderer_top_level_message(
  subject : String,
  allowed : String,
  value : Value,
  cache : Array[ValueBinding],
  placeholders : Bool,
) -> String {
  "The top-level value of \{subject} must have type \{allowed}, but got type `\{renderer_error_type_name(value, cache)}`. Value: \{renderer_error_value_text(value, cache, placeholders)}"
}

///|
fn renderer_error_type_name(
  value : Value,
  cache : Array[ValueBinding],
) -> String {
  match value {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some(kind) => kind
        None =>
          match find_object_class_tag(members) {
            Some(name) =>
              if is_stdlib_class_name(name) {
                name
              } else {
                renderer_qualified_user_name(name, cache)
              }
            None => "Object"
          }
      }
    FunctionValue(parameters, _, _, _, _) => "Function\{parameters.length()}"
    _ => eval_value_type_name(value)
  }
}

///|
fn renderer_error_value_text(
  value : Value,
  _cache : Array[ValueBinding],
  placeholders : Bool,
) -> String {
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
        _ =>
          if placeholders {
            renderer_placeholder_object_text(members)
          } else {
            render_pcf_value_inline(value)
          }
      }
    ListingValue(elements) | DefaultedListingValue(_, elements, _) =>
      if placeholders {
        renderer_placeholder_listing_text(elements)
      } else {
        renderer_full_listing_text(elements)
      }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      if placeholders {
        renderer_placeholder_mapping_text(entries)
      } else {
        render_pcf_value_inline(value)
      }
    FunctionValue(parameters, _, _, _, _) =>
      "new Function\{parameters.length()} {}"
    _ => render_pcf_value_inline(value)
  }
}

///|
fn renderer_full_listing_text(elements : Array[Value]) -> String {
  if elements.length() == 0 {
    return "new Listing {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Listing { ")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string(render_pcf_value_inline(elements[i]))
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn renderer_qualified_user_name(
  name : String,
  cache : Array[ValueBinding],
) -> String {
  let module_name = match lookup_value(cache, "@__module_name") {
    Some(StringValue(s)) => s
    _ => ""
  }
  if module_name.length() > 0 {
    "\{module_name}#\{name}"
  } else {
    name
  }
}

///|
fn renderer_placeholder_listing_text(elements : Array[Value]) -> String {
  if elements.length() == 0 {
    return "new Listing {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Listing { ")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_char('?')
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn renderer_placeholder_mapping_text(entries : Array[ValueEntry]) -> String {
  if entries.length() == 0 {
    return "new Mapping {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new Mapping { ")
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_char('[')
    buf.write_string(render_pcf_value_inline(entries[i].key))
    buf.write_string("] = ?")
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn renderer_placeholder_object_text(members : Array[ValueMember]) -> String {
  let class_name = match find_object_class_tag(members) {
    Some(name) => name
    None => "Dynamic"
  }
  let visible = visible_members(members)
  if visible.length() == 0 {
    return "new \{class_name} {}"
  }
  let buf = StringBuilder::new()
  buf.write_string("new ")
  buf.write_string(class_name)
  buf.write_string(" { ")
  for i = 0; i < visible.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    let field = visible[i]
    if field.name.has_prefix("@subscript$") {
      renderer_write_subscript_member_placeholder(field, buf)
    } else if field.name.has_prefix("@element$") {
      buf.write_char('?')
    } else {
      buf.write_string(field.name)
      buf.write_string(" = ?")
    }
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn renderer_write_subscript_member_placeholder(
  field : ValueMember,
  buf : StringBuilder,
) -> Unit {
  match field.value {
    ObjectValue(pair_members) =>
      match lookup_member(pair_members, "@key") {
        Some(key) => {
          buf.write_char('[')
          buf.write_string(render_pcf_value_inline(key))
          buf.write_string("] = ?")
        }
        None => buf.write_char('?')
      }
    _ => buf.write_char('?')
  }
}

///|
fn yaml_mixed_object_error(value : Value) -> String? {
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      let mut has_element = false
      let mut has_property_or_entry = false
      for field in visible {
        if field.name.has_prefix("@element$") {
          has_element = true
        } else {
          has_property_or_entry = true
        }
      }
      if has_element && has_property_or_entry {
        Some(
          "Cannot render object with both elements and properties/entries as YAML. Object: \{renderer_yaml_mixed_object_text(members)}",
        )
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn renderer_yaml_mixed_object_text(members : Array[ValueMember]) -> String {
  let class_name = match find_object_class_tag(members) {
    Some(name) => name
    None => "Dynamic"
  }
  let visible = visible_members(members)
  let buf = StringBuilder::new()
  buf.write_string("new ")
  buf.write_string(class_name)
  if visible.length() == 0 {
    buf.write_string(" {}")
    return buf.to_string()
  }
  buf.write_string(" { ")
  for i = 0; i < visible.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    let field = visible[i]
    if field.name.has_prefix("@element$") {
      buf.write_string(render_pcf_value_inline(field.value))
    } else if field.name.has_prefix("@subscript$") {
      renderer_write_subscript_member_value(field, buf)
    } else {
      buf.write_string(field.name)
      buf.write_string(" = ")
      buf.write_string(render_pcf_value_inline(field.value))
    }
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn renderer_write_subscript_member_value(
  field : ValueMember,
  buf : StringBuilder,
) -> Unit {
  match field.value {
    ObjectValue(pair_members) =>
      match
        (
          lookup_member(pair_members, "@key"),
          lookup_member(pair_members, "@value"),
        ) {
        (Some(key), Some(value)) => {
          buf.write_char('[')
          buf.write_string(render_pcf_value_inline(key))
          buf.write_string("] = ")
          buf.write_string(render_pcf_value_inline(value))
        }
        _ => buf.write_char('?')
      }
    _ => buf.write_char('?')
  }
}

///|
fn eval_value_renderer_method(
  format : String,
  renderer_members : Array[ValueMember],
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if arguments.length() != 1 {
    diagnostics.push(
      diag(
        "ValueRenderer.\{method_name} expects 1 argument, got \{arguments.length()}",
      ),
    )
    return None
  }
  match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(value) => {
      let diagnostics_before_converters = diagnostics.length()
      let rendered_value = apply_value_renderer_converters(
        value, renderer_members, bindings, env, class_env, cache, declarations, diagnostics,
        resolve_import,
      )
      if diagnostics.length() > diagnostics_before_converters {
        return None
      }
      match
        eval_value_renderer_method_error(
          format, method_name, rendered_value, cache, class_env, declarations,
        ) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      match format {
        "pcf" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          let use_custom_string_delimiters = renderer_bool_option(
            renderer_members, "useCustomStringDelimiters", false,
          )
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_pcf_document_with_options(
                  rendered_value, indent_text, use_custom_string_delimiters,
                ),
              ),
            )
          } else {
            Some(
              StringValue(
                render_value_as_pcf_fragment_with_options(
                  rendered_value, indent_text, use_custom_string_delimiters,
                ),
              ),
            )
          }
        }
        "json" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_json_document_with_indent(
                  rendered_value, indent_text,
                ),
              ),
            )
          } else {
            Some(
              StringValue(
                render_value_as_json_with_indent(rendered_value, indent_text),
              ),
            )
          }
        }
        "yaml" => {
          let indent_width = renderer_int_option(
            renderer_members, "indentWidth", 2,
          )
          let is_stream = renderer_bool_option(
            renderer_members, "isStream", false,
          )
          if is_stream && method_name == "renderDocument" {
            match
              yaml_stream_top_level_error(rendered_value, class_env, cache) {
              Some(message) => {
                diagnostics.push(diag(message))
                return None
              }
              None => ()
            }
          }
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_yaml_with_options(
                  rendered_value, indent_width, is_stream,
                ),
              ),
            )
          } else {
            Some(
              StringValue(
                render_value_as_yaml_fragment_with_options(
                  rendered_value, indent_width, false,
                ),
              ),
            )
          }
        }
        "properties" =>
          if method_name == "renderDocument" {
            Some(StringValue(render_value_as_properties(rendered_value)))
          } else {
            Some(
              StringValue(render_value_as_properties_fragment(rendered_value)),
            )
          }
        "plist" =>
          if method_name == "renderDocument" {
            Some(StringValue(render_value_as_plist(rendered_value)))
          } else {
            Some(StringValue(render_value_as_plist_fragment(rendered_value)))
          }
        "textproto" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_textproto_with_indent(
                  rendered_value, indent_text,
                ),
              ),
            )
          } else {
            Some(
              StringValue(
                render_value_as_protobuf_fragment_with_context(
                  rendered_value, indent_text, class_env, cache, declarations,
                ),
              ),
            )
          }
        }
        "xml" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          let xml_version = xml_renderer_option(
            renderer_members, "xmlVersion", "1.0",
          )
          if method_name == "renderDocument" {
            let root_element_name = xml_renderer_option(
              renderer_members, "rootElementName", "root",
            )
            match
              xml_render_document_error(
                rendered_value, root_element_name, xml_version,
              ) {
              Some(message) => {
                diagnostics.push(diag(message))
                return None
              }
              None => ()
            }
            Some(
              StringValue(
                render_value_as_xml_with_options(
                  rendered_value, root_element_name, indent_text, xml_version,
                ),
              ),
            )
          } else {
            match xml_render_value_error(rendered_value, xml_version) {
              Some(message) => {
                diagnostics.push(diag(message))
                return None
              }
              None => ()
            }
            Some(
              StringValue(
                render_value_as_xml_fragment(rendered_value, indent_text),
              ),
            )
          }
        }
        _ => None
      }
    }
    None => None
  }
}

///|
fn xml_renderer_option(
  renderer_members : Array[ValueMember],
  name : String,
  default : String,
) -> String {
  match lookup_member(renderer_members, name) {
    Some(StringValue(s)) => s
    _ => default
  }
}

///|
fn renderer_bool_option(
  renderer_members : Array[ValueMember],
  name : String,
  default : Bool,
) -> Bool {
  match lookup_member(renderer_members, name) {
    Some(BoolValue(b)) => b
    _ => default
  }
}

///|
fn renderer_int_option(
  renderer_members : Array[ValueMember],
  name : String,
  default : Int,
) -> Int {
  match lookup_member(renderer_members, name) {
    Some(IntValue(n)) => n.to_int()
    _ => default
  }
}

///|
fn yaml_stream_top_level_error(
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> String? {
  match value {
    ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | ListValue(_)
    | SetValue(_) => None
    _ =>
      Some(
        "The top-level value of a YAML stream must have type `Listing`, `List`, or `Set`, but got type `\{qualify_value_type_name(value, class_env, module_name_from_cache(cache))}`. Value: \{render_pcf_value_inline(value)}",
      )
  }
}

///|
fn copy_function_parameters(
  parameters : Array[FunctionParameter],
) -> Array[FunctionParameter] {
  let copied : Array[FunctionParameter] = []
  for parameter in parameters {
    copied.push(parameter)
  }
  copied
}

///|
fn copy_function_amend_parameters(
  parameters : Array[FunctionParameter],
) -> Array[FunctionParameter] {
  let copied : Array[FunctionParameter] = []
  for i = 0; i < parameters.length(); i = i + 1 {
    let parameter = parameters[i]
    copied.push({
      name: if parameter.name == "_" {
        "@__function_amend_arg" + i.to_string()
      } else {
        parameter.name
      },
      type_name: parameter.type_name,
    })
  }
  copied
}

///|
fn function_amend_regular_members(
  members : Array[ObjectMember],
) -> Array[ObjectMember] {
  let regular : Array[ObjectMember] = []
  for object_member in members {
    if !is_function_amend_marker_member_name(object_member.name) {
      regular.push(object_member)
    }
  }
  regular
}

///|
fn function_amend_has_recursive_marker(members : Array[ObjectMember]) -> Bool {
  for object_member in members {
    if is_function_amend_recursive_member_name(object_member.name) {
      return true
    }
  }
  false
}

///|
fn generated_function_amend_parameters(
  base_parameters : Array[FunctionParameter],
) -> Array[FunctionParameter] {
  let generated : Array[FunctionParameter] = []
  for i = 0; i < base_parameters.length(); i = i + 1 {
    generated.push({
      name: "@__function_amend_arg" + i.to_string(),
      type_name: base_parameters[i].type_name,
    })
  }
  generated
}

///|
fn function_amend_parameters(
  members : Array[ObjectMember],
  base_parameters : Array[FunctionParameter],
  use_generated_parameters~ : Bool,
) -> Array[FunctionParameter] {
  for object_member in members {
    if is_function_amend_parameter_member_name(object_member.name) {
      match object_member.value {
        LambdaExpr(parameters, _, _) =>
          return copy_function_amend_parameters(parameters)
        _ => ()
      }
    }
  }
  if use_generated_parameters {
    return generated_function_amend_parameters(base_parameters)
  }
  copy_function_parameters(base_parameters)
}

///|
fn function_amend_base_binding_name() -> String {
  "@__function_amend_base"
}

///|
fn function_amend_body_members(
  members : Array[ObjectMember],
) -> Array[ObjectMember] {
  let out = function_amend_regular_members(members)
  out.push({
    name: function_amend_recursive_member_name(),
    type_name: None,
    value: NullLiteral,
    annotations: [],
  })
  out
}

///|
fn function_amend_member_values_reference_name(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  for object_member in members {
    if !is_function_amend_marker_member_name(object_member.name) &&
      expr_references_late_binding(object_member.value, name) {
      return true
    }
  }
  false
}

///|
fn function_amend_should_generate_parameters(
  members : Array[ObjectMember],
  base_parameters : Array[FunctionParameter],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Bool {
  if function_amend_has_recursive_marker(members) {
    return true
  }
  for parameter in base_parameters {
    if function_amend_member_values_reference_name(members, parameter.name) &&
      (
        lookup_value(env, parameter.name) is Some(_) ||
        lookup_value(cache, parameter.name) is Some(_)
      ) {
      return true
    }
  }
  false
}

///|
fn build_function_amend_value(
  fn_value : Value,
  members : Array[ObjectMember],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Value {
  match fn_value {
    FunctionValue(base_parameters, _, return_type_name, _, _) => {
      let parameters = function_amend_parameters(
        members,
        base_parameters,
        use_generated_parameters=function_amend_should_generate_parameters(
          members, base_parameters, env, cache,
        ),
      )
      let arguments : Array[Expr] = []
      for parameter in parameters {
        arguments.push(Identifier(parameter.name))
      }
      let captured = capture_value_bindings(env, cache)
      captured.push({
        name: function_amend_base_binding_name(),
        value: fn_value,
      })
      FunctionValue(
        parameters,
        AmendExpr(
          CallExpr(Identifier(function_amend_base_binding_name()), arguments),
          function_amend_body_members(members),
        ),
        return_type_name,
        captured,
        fresh_function_id(),
      )
    }
    _ => fn_value
  }
}

///|
fn object_super_metadata_name() -> String {
  "__object_super"
}

///|
fn class_default_dependency_metadata_name() -> String {
  "__class_default_deps"
}

///|
fn object_members_super(members : Array[ValueMember]) -> Array[ValueMember]? {
  match lookup_member(members, object_super_metadata_name()) {
    Some(ObjectValue(super_members)) => Some(super_members)
    _ => None
  }
}

///|
fn object_members_depend_on_class_default(
  members : Array[ValueMember],
  name : String,
) -> Bool {
  match lookup_member(members, class_default_dependency_metadata_name()) {
    Some(ObjectValue(deps)) =>
      match lookup_member(deps, name) {
        Some(BoolValue(true)) => true
        _ => false
      }
    _ => false
  }
}

///|
fn copy_value_members(members : Array[ValueMember]) -> Array[ValueMember] {
  let copied : Array[ValueMember] = []
  for value_member in members {
    copied.push(value_member)
  }
  copied
}

///|
fn object_super_members_from_cache(
  cache : Array[ValueBinding],
) -> Array[ValueMember]? {
  match lookup_value(cache, "super") {
    Some(ObjectValue(members)) =>
      if is_module_member_set(members) {
        None
      } else {
        Some(members)
      }
    _ => None
  }
}

///|
fn add_object_super_metadata(
  members : Array[ValueMember],
  super_members : Array[ValueMember],
) -> Array[ValueMember] {
  let tagged : Array[ValueMember] = [
    {
      name: hidden_member_name(object_super_metadata_name()),
      value: ObjectValue(copy_value_members(super_members)),
      source: None,
      annotations: [],
    },
  ]
  let metadata_name = hidden_member_name(object_super_metadata_name())
  for value_member in members {
    if value_member.name != metadata_name {
      tagged.push(value_member)
    }
  }
  tagged
}

///|
fn add_class_default_dependency_metadata(
  members : Array[ValueMember],
  dependency_names : Array[String],
) -> Array[ValueMember] {
  if dependency_names.length() == 0 {
    return members
  }
  let deps : Array[ValueMember] = []
  for name in dependency_names {
    deps.push({ name, value: BoolValue(true), source: None, annotations: [] })
  }
  let metadata_name = hidden_member_name(
    class_default_dependency_metadata_name(),
  )
  let tagged : Array[ValueMember] = [
    {
      name: metadata_name,
      value: ObjectValue(deps),
      source: None,
      annotations: [],
    },
  ]
  for value_member in members {
    if value_member.name != metadata_name {
      tagged.push(value_member)
    }
  }
  tagged
}

///|
fn object_members_declare_bare_name(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  for object_member in members {
    if strip_member_visibility_prefix(object_member.name) == name {
      return true
    }
  }
  false
}

///|
fn runtime_scope_has_binding(
  name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Bool {
  lookup_value(env, name) is Some(_) ||
  lookup_value(cache, name) is Some(_) ||
  lookup_value(cache, hidden_member_name(name)) is Some(_) ||
  lookup_value(cache, local_member_name(name)) is Some(_) ||
  find_binding(bindings, name) is Some(_)
}

///|
fn class_default_dependency_names(
  members : Array[ObjectMember],
  class_defaults : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Array[String] {
  let deps : Array[String] = []
  for default_member in class_defaults {
    let name = strip_member_visibility_prefix(default_member.name)
    if object_members_declare_bare_name(members, name) ||
      runtime_scope_has_binding(name, bindings, env, cache) {
      continue
    }
    for object_member in members {
      if expr_references_late_binding(object_member.value, name) {
        push_unique_name(deps, name)
        break
      }
    }
  }
  deps
}

///|
fn cache_with_outer_object(
  cache : Array[ValueBinding],
  outer_members : Array[ValueMember],
) -> Array[ValueBinding] {
  let next = copy_value_bindings(cache)
  let resolved_outer = match object_super_members_from_cache(cache) {
    Some(super_members) => merge_value_members(super_members, outer_members)
    None => copy_value_members(outer_members)
  }
  next.push({ name: "outer", value: ObjectValue(resolved_outer) })
  next
}

///|
fn cache_for_nested_object_value(
  value : Expr,
  cache : Array[ValueBinding],
  outer_members : Array[ValueMember],
) -> Array[ValueBinding] {
  match value {
    ObjectLiteral(_)
    | TypedObjectLiteral(_, _)
    | ListingLiteral(_)
    | MappingLiteral(_) => cache_with_outer_object(cache, outer_members)
    _ => cache
  }
}

///|
fn cache_for_member_source_reeval(
  source : Expr,
  cache : Array[ValueBinding],
  current_members : Array[ValueMember],
) -> Array[ValueBinding] {
  let next = match object_members_super(current_members) {
    Some(super_members) => {
      let with_super = copy_value_bindings(cache)
      with_super.push({ name: "super", value: ObjectValue(super_members) })
      with_super
    }
    None => cache
  }
  cache_for_nested_object_value(source, next, current_members)
}

///|
fn member_source_comes_from_base(
  name : String,
  base : Array[ValueMember],
  overrides : Array[ValueMember],
) -> Bool {
  match
    (
      find_value_member_exact(base, name),
      find_value_member_exact(overrides, name),
    ) {
    (Some(base_member), Some(override_member)) =>
      match (base_member.value, override_member.value) {
        (ObjectValue(_), ObjectValue(_)) => true
        _ => false
      }
    (Some(_), None) => true
    _ => false
  }
}

///|
fn expr_references_super(expr : Expr) -> Bool {
  match expr {
    Identifier(name) => name == "super"
    ObjectLiteral(members) | TypedObjectLiteral(_, members) => {
      for object_member in members {
        if expr_references_super(object_member.value) {
          return true
        }
      }
      false
    }
    ListingLiteral(elements) => {
      for element in elements {
        if expr_references_super(element) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_references_super(entry.key) ||
          expr_references_super(entry.value) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      expr_references_super(target)
    SubscriptAccess(target, key) =>
      expr_references_super(target) || expr_references_super(key)
    AmendExpr(base, members) =>
      if expr_references_super(base) {
        true
      } else {
        for object_member in members {
          if expr_references_super(object_member.value) {
            return true
          }
        }
        false
      }
    CallExpr(callee, arguments) | NullSafeCallExpr(callee, arguments) => {
      if expr_references_super(callee) {
        return true
      }
      for argument in arguments {
        if expr_references_super(argument) {
          return true
        }
      }
      false
    }
    LambdaExpr(_, body, _) => expr_references_super(body)
    LetExpr(_, _, value, body) =>
      expr_references_super(value) || expr_references_super(body)
    NonNullExpr(inner) | UnaryExpr(_, inner) | WhenSpread(inner) =>
      expr_references_super(inner)
    BinaryExpr(_, left, right) =>
      expr_references_super(left) || expr_references_super(right)
    ConditionalExpr(cond, then_branch, else_branch) =>
      expr_references_super(cond) ||
      expr_references_super(then_branch) ||
      expr_references_super(else_branch)
    ForGenerator(_, _, source, members, _, _) => {
      if expr_references_super(source) {
        return true
      }
      for object_member in members {
        if expr_references_super(object_member.value) {
          return true
        }
      }
      false
    }
    InterpolatedString(parts) => {
      for part in parts {
        if expr_references_super(part) {
          return true
        }
      }
      false
    }
    IntLiteral(_)
    | FloatLiteral(_)
    | BoolLiteral(_)
    | StringLiteral(_)
    | NullLiteral
    | ImportExpr(_)
    | ImportGlobExpr(_)
    | UnsupportedExpr
    | ErrorExpr(_) => false
  }
}

///|
fn expr_directly_references_outer_member(expr : Expr, name : String) -> Bool {
  match expr {
    MemberAccess(Identifier("outer"), member_name)
    | SafeMemberAccess(Identifier("outer"), member_name) => member_name == name
    ObjectLiteral(_) | TypedObjectLiteral(_, _) => false
    ListingLiteral(elements) => {
      for element in elements {
        if expr_directly_references_outer_member(element, name) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_directly_references_outer_member(entry.key, name) ||
          expr_directly_references_outer_member(entry.value, name) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      expr_directly_references_outer_member(target, name)
    SubscriptAccess(target, key) =>
      expr_directly_references_outer_member(target, name) ||
      expr_directly_references_outer_member(key, name)
    AmendExpr(base, members) => {
      if expr_directly_references_outer_member(base, name) {
        return true
      }
      for object_member in members {
        if expr_directly_references_outer_member(object_member.value, name) {
          return true
        }
      }
      false
    }
    CallExpr(callee, arguments) | NullSafeCallExpr(callee, arguments) => {
      if expr_directly_references_outer_member(callee, name) {
        return true
      }
      for argument in arguments {
        if expr_directly_references_outer_member(argument, name) {
          return true
        }
      }
      false
    }
    LambdaExpr(_, body, _) => expr_directly_references_outer_member(body, name)
    LetExpr(_, _, value, body) =>
      expr_directly_references_outer_member(value, name) ||
      expr_directly_references_outer_member(body, name)
    NonNullExpr(inner) | UnaryExpr(_, inner) | WhenSpread(inner) =>
      expr_directly_references_outer_member(inner, name)
    BinaryExpr(_, left, right) =>
      expr_directly_references_outer_member(left, name) ||
      expr_directly_references_outer_member(right, name)
    ConditionalExpr(cond, then_branch, else_branch) =>
      expr_directly_references_outer_member(cond, name) ||
      expr_directly_references_outer_member(then_branch, name) ||
      expr_directly_references_outer_member(else_branch, name)
    ForGenerator(_, _, source, members, _, _) => {
      if expr_directly_references_outer_member(source, name) {
        return true
      }
      for object_member in members {
        if expr_directly_references_outer_member(object_member.value, name) {
          return true
        }
      }
      false
    }
    InterpolatedString(parts) => {
      for part in parts {
        if expr_directly_references_outer_member(part, name) {
          return true
        }
      }
      false
    }
    IntLiteral(_)
    | FloatLiteral(_)
    | BoolLiteral(_)
    | StringLiteral(_)
    | NullLiteral
    | Identifier(_)
    | ImportExpr(_)
    | ImportGlobExpr(_)
    | UnsupportedExpr
    | ErrorExpr(_) => false
  }
}

///|
fn expr_references_outer_binding(expr : Expr, name : String) -> Bool {
  match expr {
    ObjectLiteral(members) | TypedObjectLiteral(_, members) => {
      for object_member in members {
        if expr_directly_references_outer_member(object_member.value, name) {
          return true
        }
      }
      false
    }
    AmendExpr(base, members) => {
      if expr_references_outer_binding(base, name) {
        return true
      }
      for object_member in members {
        if expr_directly_references_outer_member(object_member.value, name) {
          return true
        }
      }
      false
    }
    CallExpr(callee, arguments) | NullSafeCallExpr(callee, arguments) => {
      if expr_references_outer_binding(callee, name) {
        return true
      }
      for argument in arguments {
        if expr_references_outer_binding(argument, name) {
          return true
        }
      }
      false
    }
    ListingLiteral(elements) => {
      for element in elements {
        if expr_references_outer_binding(element, name) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_references_outer_binding(entry.key, name) ||
          expr_references_outer_binding(entry.value, name) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      expr_references_outer_binding(target, name)
    SubscriptAccess(target, key) =>
      expr_references_outer_binding(target, name) ||
      expr_references_outer_binding(key, name)
    LambdaExpr(_, body, _) => expr_references_outer_binding(body, name)
    LetExpr(_, _, value, body) =>
      expr_references_outer_binding(value, name) ||
      expr_references_outer_binding(body, name)
    NonNullExpr(inner) | UnaryExpr(_, inner) | WhenSpread(inner) =>
      expr_references_outer_binding(inner, name)
    BinaryExpr(_, left, right) =>
      expr_references_outer_binding(left, name) ||
      expr_references_outer_binding(right, name)
    ConditionalExpr(cond, then_branch, else_branch) =>
      expr_references_outer_binding(cond, name) ||
      expr_references_outer_binding(then_branch, name) ||
      expr_references_outer_binding(else_branch, name)
    ForGenerator(_, _, source, members, _, _) => {
      if expr_references_outer_binding(source, name) {
        return true
      }
      for object_member in members {
        if expr_directly_references_outer_member(object_member.value, name) {
          return true
        }
      }
      false
    }
    InterpolatedString(parts) => {
      for part in parts {
        if expr_references_outer_binding(part, name) {
          return true
        }
      }
      false
    }
    IntLiteral(_)
    | FloatLiteral(_)
    | BoolLiteral(_)
    | StringLiteral(_)
    | NullLiteral
    | Identifier(_)
    | ImportExpr(_)
    | ImportGlobExpr(_)
    | UnsupportedExpr
    | ErrorExpr(_) => false
  }
}

///|
/// PKL-148bb: scope-aware reference probe used by the late-binding
/// re-eval pass. `expr_references` in lint.mbt walks *every* sub-
/// expression — that's the right semantic for cycle detection but
/// wrong here: a base member whose source is a nested
/// `ObjectLiteral { x = y; y = 3 }` should *not* be re-evaluated just
/// because an outer-level amend adds a sibling `y`, since the inner
/// `y = 3` shadows the outer name. This probe treats every scope-
/// creating construct (ObjectLiteral / TypedObjectLiteral / AmendExpr
/// body / LambdaExpr params / LetExpr body / ForGenerator key+value+body) as a
/// barrier: if it declares / binds `name`, the reference is shadowed
/// and recursion into that scope stops returning true.
fn expr_references_late_binding(expr : Expr, name : String) -> Bool {
  match expr {
    IntLiteral(_) => false
    FloatLiteral(_) => false
    BoolLiteral(_) => false
    StringLiteral(_) => false
    NullLiteral => false
    Identifier(n) => n == name
    ImportExpr(_) | ImportGlobExpr(_) => false
    ObjectLiteral(members) => members_reference_late_binding(members, name)
    TypedObjectLiteral(type_name, members) =>
      type_name == name || members_reference_late_binding(members, name)
    ListingLiteral(elements) => {
      for element in elements {
        if expr_references_late_binding(element, name) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_references_late_binding(entry.key, name) ||
          expr_references_late_binding(entry.value, name) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) => expr_references_late_binding(target, name)
    SafeMemberAccess(target, _) => expr_references_late_binding(target, name)
    SubscriptAccess(target, key) =>
      expr_references_late_binding(target, name) ||
      expr_references_late_binding(key, name)
    AmendExpr(base, members) =>
      expr_references_late_binding(base, name) ||
      members_reference_late_binding(members, name)
    CallExpr(callee, arguments) => {
      if expr_references_late_binding(callee, name) {
        return true
      }
      for argument in arguments {
        if expr_references_late_binding(argument, name) {
          return true
        }
      }
      false
    }
    LambdaExpr(params, body, _) => {
      for param in params {
        if param.name == name {
          return false
        }
      }
      expr_references_late_binding(body, name)
    }
    LetExpr(let_name, _, value, body) =>
      expr_references_late_binding(value, name) ||
      (let_name != name && expr_references_late_binding(body, name))
    NonNullExpr(inner) => expr_references_late_binding(inner, name)
    UnaryExpr(_, inner) => expr_references_late_binding(inner, name)
    BinaryExpr(_, left, right) =>
      expr_references_late_binding(left, name) ||
      expr_references_late_binding(right, name)
    ConditionalExpr(cond, then_branch, else_branch) =>
      expr_references_late_binding(cond, name) ||
      expr_references_late_binding(then_branch, name) ||
      expr_references_late_binding(else_branch, name)
    ForGenerator(key_name, value_name, source, members, _, _) => {
      if key_name == name {
        return false
      }
      if value_name is Some(vn) && vn == name {
        return false
      }
      expr_references_late_binding(source, name) ||
      members_reference_late_binding(members, name)
    }
    WhenSpread(inner) => expr_references_late_binding(inner, name)
    InterpolatedString(parts) => {
      for part in parts {
        if expr_references_late_binding(part, name) {
          return true
        }
      }
      false
    }
    NullSafeCallExpr(callee, arguments) => {
      if expr_references_late_binding(callee, name) {
        return true
      }
      for argument in arguments {
        if expr_references_late_binding(argument, name) {
          return true
        }
      }
      false
    }
    UnsupportedExpr => false
    ErrorExpr(_) => false
  }
}

///|
fn members_reference_late_binding(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  // ObjectLiteral / AmendExpr / TypedObjectLiteral bodies create a new
  // sibling scope: a member named `name` shadows the outer reference.
  for om in members {
    if strip_member_visibility_prefix(om.name) == name {
      return false
    }
  }
  for om in members {
    if expr_references_late_binding(om.value, name) {
      return true
    }
  }
  false
}

///|
fn function_parameters_bind_name(
  params : Array[FunctionParameter],
  name : String,
) -> Bool {
  for param in params {
    if param.name == name {
      return true
    }
  }
  false
}

///|
fn expr_calls_env_function_referencing_late_binding(
  expr : Expr,
  name : String,
  env : Array[ValueBinding],
) -> Bool {
  match expr {
    CallExpr(Identifier(fn_name), _) =>
      match lookup_value(env, fn_name) {
        Some(FunctionValue(params, body, _, _, _)) =>
          !function_parameters_bind_name(params, name) &&
          expr_references_late_binding(body, name)
        _ => false
      }
    _ => false
  }
}

///|
fn synthetic_override_members(names : Array[String]) -> Array[ObjectMember] {
  let members : Array[ObjectMember] = []
  for name in names {
    members.push({ name, type_name: None, value: NullLiteral, annotations: [] })
  }
  members
}

///|
fn reeval_class_tagged_members_after_amend(
  members : Array[ValueMember],
  override_names : Array[String],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  match find_object_class_tag(members) {
    Some(class_name) =>
      reeval_class_defaults_after_constructor_overrides(
        class_name,
        synthetic_override_members(override_names),
        members,
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      )
    None => members
  }
}

///|
/// PKL-148bb: late-binding-aware deep merge for AmendExpr. Walks both
/// `base` and `overrides` like `merge_value_members` / `deep_merge_amend_value`
/// would, but with eval context in hand so each nesting level can run a
/// re-eval pass over base members whose captured `source` expression
/// references any of the names that were overridden at this level. This
/// is what makes `objects/lateBinding1` work: amending `foo { y = 4 }`
/// over a base `foo = { x = y; y = 3 }` re-evaluates `x = y` against the
/// merged inner env so `x` picks up the new `y` instead of staying at the
/// cached `3`.
fn merge_objects_with_late_binding(
  base : Array[ValueMember],
  overrides : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  // Collect bare override names that the late-binding pass should chase.
  // Only "shadowing" overrides count — names that already live in `base`.
  // Additive overrides (a fresh sibling name not present in base) must not
  // trigger re-binding: in `lateBinding2`'s `foo { x = y }` (no inner `y`)
  // the original resolution of `y` went to the outer scope, and a later
  // amend that *adds* `foo.y` mustn't yank `x` back to the new inner `y`.
  //
  // Skip `@local$` overrides: Apple Pkl treats each amend body's `local`
  // declarations as a fresh scope-private slot, so an amend that re-binds
  // `local l = "override"` must not re-trigger sibling expressions that
  // captured the base body's `local l`. (`basic/localPropertyOverride1`.)
  let class_override_names : Array[String] = []
  let override_names : Array[String] = []
  for o in overrides {
    if is_local_member_name(o.name) {
      continue
    }
    let bare = strip_member_visibility_prefix(o.name)
    push_unique_name(class_override_names, bare)
    let mut in_base = false
    for bm in base {
      // A `local` base slot belongs to its own namespace — a visible
      // amend with the same bare name does not shadow it, so it should
      // not register here. (`basic/localPropertyOverride1` foo4: the
      // visible `l = "override"` must not re-trigger `x = l` whose
      // original `l` resolved against the base body's `local l`.)
      if is_local_member_name(bm.name) {
        continue
      }
      let bm_bare = strip_member_visibility_prefix(bm.name)
      // A `source: None` base slot normally came from a class default
      // or synthetic path, so it is not enough by itself to prove that
      // body sources should late-bind to it. TypedObjectLiteral records
      // the narrow case where a body reference actually fell through to
      // that class default; only those default slots may re-trigger
      // sibling source evaluation here. This keeps `lateBinding3.v3`
      // bound to the outer `y` while letting `lateBinding4.v3` follow
      // the class-default `y`.
      if bm.source is None &&
        !object_members_depend_on_class_default(base, bm_bare) {
        continue
      }
      if bm_bare == bare {
        in_base = true
        break
      }
    }
    if in_base {
      override_names.push(bare)
    }
  }
  // Build the merged member array mirroring `merge_value_members` +
  // `deep_merge_amend_value`, but recurse into nested ObjectValue with
  // eval context so the late-binding pass fires at every level.
  let merged : Array[ValueMember] = []
  for bm in base {
    let exact = find_member_exact(overrides, bm.name)
    let resolved_member = if exact is Some(_) {
      find_value_member_exact(overrides, bm.name)
    } else if is_hidden_member_name(bm.name) {
      let bare = String::unsafe_substring(
        bm.name,
        start=hidden_member_prefix.length(),
        end=bm.name.length(),
      )
      find_value_member_exact(overrides, bare)
    } else {
      None
    }
    match resolved_member {
      Some(over_member) => {
        let new_val = match (bm.value, over_member.value) {
          (ObjectValue(inner_base), ObjectValue(inner_over)) =>
            ObjectValue(
              merge_objects_with_late_binding(
                inner_base, inner_over, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              ),
            )
          (_, ov) =>
            deep_merge_amend_member_value(bm.value, ov, over_member.source)
        }
        let merged_source = match (bm.value, over_member.value) {
          (ObjectValue(_), ObjectValue(_)) => bm.source
          _ => over_member.source
        }
        merged.push({
          name: bm.name,
          value: new_val,
          source: merged_source,
          annotations: append_annotations(
            bm.annotations,
            over_member.annotations,
          ),
        })
      }
      None => merged.push(bm)
    }
  }
  for o in overrides {
    if find_member_exact(base, o.name) is Some(_) {
      continue
    }
    let hidden_alias = hidden_member_name(o.name)
    if find_member_exact(base, hidden_alias) is Some(_) {
      continue
    }
    merged.push(o)
  }
  // Late-binding pass at this nesting level: re-evaluate any merged
  // member whose `source` references one of `override_names`.
  if override_names.length() == 0 {
    return normalize_name_age_member_order(
      reeval_class_tagged_members_after_amend(
        merged, class_override_names, bindings, env, class_env, cache, stack, declarations,
        diagnostics, resolve_import,
      ),
    )
  }
  let local_env : Array[ValueBinding] = []
  for b in env {
    local_env.push(b)
  }
  for m in merged {
    let bare = strip_member_visibility_prefix(m.name)
    if !is_invisible_member_name(m.name) ||
      is_local_member_name(m.name) ||
      is_hidden_member_name(m.name) {
      local_env.push({ name: bare, value: m.value })
    }
  }
  // PKL-148d: local functions inside an object body are late-bound to
  // the current object state during an amend. Re-push FunctionValue
  // members with `local_env` itself as their captured environment so
  // `y = compute(); local function compute() = x` sees an amended `x`.
  for m in merged {
    let bare = strip_member_visibility_prefix(m.name)
    if !is_invisible_member_name(m.name) ||
      is_local_member_name(m.name) ||
      is_hidden_member_name(m.name) {
      match m.value {
        FunctionValue(params, body, return_type_name, _, id) =>
          local_env.push({
            name: bare,
            value: FunctionValue(params, body, return_type_name, local_env, id),
          })
        _ => ()
      }
    }
  }
  let final_members : Array[ValueMember] = []
  for m in merged {
    let mut reeval_done = false
    match m.source {
      Some(src) => {
        let mut needs = false
        for name in override_names {
          let m_bare = strip_member_visibility_prefix(m.name)
          if name == m_bare {
            continue
          }
          if expr_references_late_binding(src, name) ||
            expr_calls_env_function_referencing_late_binding(
              src, name, local_env,
            ) ||
            expr_references_outer_binding(src, name) ||
            expr_references_super(src) {
            needs = true
            break
          }
        }
        if needs {
          let reeval_cache = if member_source_comes_from_base(
              m.name,
              base,
              overrides,
            ) {
            cache_for_member_source_reeval(src, cache, merged)
          } else {
            cache_for_nested_object_value(src, cache, merged)
          }
          match
            eval_expr_with_bindings(
              src, bindings, local_env, class_env, reeval_cache, stack, declarations,
              diagnostics, resolve_import,
            ) {
            Some(new_raw_val) => {
              let new_val = match (new_raw_val, m.value) {
                (ObjectValue(reevaluated), ObjectValue(current)) =>
                  ObjectValue(
                    merge_reevaluated_object_preserving_overrides(
                      reevaluated, current,
                    ),
                  )
                _ => new_raw_val
              }
              final_members.push({
                name: m.name,
                value: new_val,
                source: m.source,
                annotations: m.annotations,
              })
              reeval_done = true
            }
            None => ()
          }
        }
      }
      None => ()
    }
    if !reeval_done {
      let rebound_value = match m.value {
        FunctionValue(params, body, return_type_name, _, id) =>
          FunctionValue(params, body, return_type_name, local_env, id)
        _ => m.value
      }
      final_members.push({
        name: m.name,
        value: rebound_value,
        source: m.source,
        annotations: m.annotations,
      })
    }
  }
  normalize_name_age_member_order(
    reeval_class_tagged_members_after_amend(
      final_members, class_override_names, bindings, env, class_env, cache, stack,
      declarations, diagnostics, resolve_import,
    ),
  )
}

///|
fn merge_reevaluated_object_preserving_overrides(
  reevaluated : Array[ValueMember],
  current : Array[ValueMember],
) -> Array[ValueMember] {
  let mut merged = copy_value_members(reevaluated)
  for current_member in current {
    match find_value_member_exact(reevaluated, current_member.name) {
      Some(base_member) =>
        if current_member.source == base_member.source {
          continue
        } else {
          let next : Array[ValueMember] = []
          for existing in merged {
            if existing.name == current_member.name {
              next.push(current_member)
            } else {
              next.push(existing)
            }
          }
          merged = next
        }
      None => merged.push(current_member)
    }
  }
  merged
}

///|
fn find_value_member_exact(
  members : Array[ValueMember],
  name : String,
) -> ValueMember? {
  // Reverse-walk + early break: "last definition wins" matches the
  // prior forward-walk-with-overwrite semantics while short-circuiting
  // on the common case where the looked-up member sits near the tail
  // (it's a freshly-pushed override on the merge hot path).
  let mut i = members.length() - 1
  while i >= 0 {
    let field = members[i]
    if field.name == name {
      return Some(field)
    }
    i = i - 1
  }
  None
}

///|
fn eval_object_members(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  eval_object_members_with_implicit_env(
    members,
    bindings,
    env,
    env,
    class_env,
    cache,
    stack,
    declarations,
    diagnostics,
    resolve_import,
    defer_property_errors=false,
  )
}

///|
fn object_member_targets_function_default(
  name : String,
  cache : Array[ValueBinding],
) -> Bool {
  match lookup_value(cache, "super") {
    Some(ObjectValue(members)) =>
      match lookup_member(members, strip_member_visibility_prefix(name)) {
        Some(FunctionValue(_, _, _, _, _)) => true
        _ => false
      }
    _ => false
  }
}

///|
fn class_property_type_annotation_from_class_env_with_depth(
  type_name : String,
  property_name : String,
  class_env : Array[ClassBinding],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      let hidden_name = hidden_member_name(property_name)
      let mut found = false
      let mut annotation : String? = None
      for property in class_binding.properties {
        if property.name == property_name || property.name == hidden_name {
          found = true
          annotation = property.type_name
          break
        }
      }
      if found && annotation is Some(_) {
        annotation
      } else {
        match class_binding.parent_name {
          Some(parent_name) =>
            class_property_type_annotation_from_class_env_with_depth(
              parent_name,
              property_name,
              class_env,
              depth + 1,
            )
          None => None
        }
      }
    }
    None => None
  }
}

///|
fn class_property_type_annotation_from_class_env(
  type_name : String,
  property_name : String,
  class_env : Array[ClassBinding],
) -> String? {
  class_property_type_annotation_from_class_env_with_depth(
    type_name, property_name, class_env, 0,
  )
}

///|
fn instantiable_class_name_for_type_annotation(
  type_name : String,
  class_env : Array[ClassBinding],
) -> String? {
  let mut name = trim_spaces(type_name)
  while name.has_suffix("?") {
    name = trim_spaces(
      String::unsafe_substring(name, start=0, end=name.length() - 1),
    )
  }
  match lookup_class_binding(class_env, name) {
    Some(_) => Some(name)
    None => None
  }
}

///|
fn resolve_object_super_member_value(
  name : String,
  super_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match lookup_value_member(super_members, name) {
    Some(value_member) =>
      match value_member.source {
        Some(source) =>
          if expr_references_super(source) &&
            object_members_super(super_members) is None {
            Some(value_member.value)
          } else {
            let super_cache = copy_value_bindings(cache)
            match object_members_super(super_members) {
              Some(parent_members) =>
                super_cache.push({
                  name: "super",
                  value: ObjectValue(parent_members),
                })
              None => ()
            }
            super_cache.push({ name: "this", value: ObjectValue(super_members) })
            eval_expr_with_bindings(
              source, bindings, env, class_env, super_cache, stack, declarations,
              diagnostics, resolve_import,
            )
          }
        None => Some(value_member.value)
      }
    None =>
      if name == "text" &&
        (
          lookup_member(super_members, "renderer") is Some(_) ||
          lookup_member(super_members, "value") is Some(_)
        ) {
        match
          module_object_value_from_scope(
            bindings,
            env,
            cache,
            stack,
            const_context=false,
          ) {
          ObjectValue(owner_members) =>
            match synthesize_output_text_member(owner_members, super_members) {
              ObjectValue(output_members) =>
                lookup_member(output_members, "text")
              _ => None
            }
          _ => None
        }
      } else {
        None
      }
  }
}

///|
/// PKL-148u: extended form with `defer_property_errors`. When true,
/// any property whose evaluation produces a diagnostic (or a
/// structural rejection) has the first diagnostic captured into a
/// `@error$<name>` sentinel member instead of bubbling to the outer
/// `diagnostics` array. The ObjectValue access path picks the
/// sentinel up at `obj.<name>` time, raises the diag, and short-
/// circuits — matching Apple Pkl's lazy per-property class-default
/// semantics. Module-binding eval and user-body literal eval keep
/// the default eager behaviour (defer=false).
fn eval_object_members_with_options(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  defer_property_errors~ : Bool,
) -> Array[ValueMember] {
  eval_object_members_with_implicit_env(
    members,
    bindings,
    env,
    env,
    class_env,
    cache,
    stack,
    declarations,
    diagnostics,
    resolve_import,
    defer_property_errors~,
  )
}

///|
fn push_prior_member_into_env(
  target : Array[ValueBinding],
  prior : ValueMember,
  include_receiver_members~ : Bool,
) -> Unit {
  if is_error_member_name(prior.name) {
    let inner = String::unsafe_substring(
      prior.name,
      start=error_member_prefix.length(),
      end=prior.name.length(),
    )
    let bare = strip_member_visibility_prefix(inner)
    target.push({ name: error_member_name(bare), value: prior.value })
  } else if is_local_member_name(prior.name) {
    let bare = strip_member_visibility_prefix(prior.name)
    target.push({ name: bare, value: prior.value })
  } else if include_receiver_members {
    if is_invisible_member_name(prior.name) {
      let bare = strip_member_visibility_prefix(prior.name)
      target.push({ name: bare, value: prior.value })
    } else {
      target.push({ name: prior.name, value: prior.value })
    }
  }
}

///|
fn eval_object_members_with_implicit_env(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  implicit_env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  defer_property_errors~ : Bool,
) -> Array[ValueMember] {
  // PKL-148e: pre-register every sibling member as a binding so a
  // forward reference (`x = 1 + y; y = 2`) resolves through the
  // bindings-driven lazy lookup path. Cycle detection still kicks in
  // via the `stack` argument inside `resolve_binding_value`.
  let local_bindings : Array[Binding] = []
  // Upper bound: original bindings plus one per member (some are
  // filtered out below, but the over-reserve is cheap compared to the
  // doubling-realloc traffic this used to trigger).
  local_bindings.reserve_capacity(bindings.length() + members.length())
  for binding in bindings {
    local_bindings.push(binding)
  }
  for field in members {
    if field.name == "@when" || field.name == "@for" || field.name == "@spread" {
      continue
    }
    if is_function_amend_marker_member_name(field.name) {
      continue
    }
    // PKL-148x: `@subscript$<offset>` / `@element$<offset>`
    // sentinels are Dynamic-shape payloads that don't expose a
    // user-visible name, so they shouldn't register as binding
    // targets for sibling property resolution. The eval-side
    // dispatch in the value-emit loop below handles their actual
    // evaluation (decode `@__index_entry` for subscripts, eval the
    // raw value for elements).
    if field.name.has_prefix("@subscript$") ||
      field.name.has_prefix("@element$") {
      continue
    }
    let bare = strip_member_visibility_prefix(field.name)
    local_bindings.push({
      name: bare,
      type_name: field.type_name,
      value: field.value,
      exported: true,
      is_const: true,
      annotations: field.annotations,
      abstract_slot: false,
    })
  }
  let values : Array[ValueMember] = []
  values.reserve_capacity(members.length())
  for field in members {
    if is_function_amend_marker_member_name(field.name) {
      continue
    }
    // PKL-148d / PKL-148az: keep lexical scope separate from the
    // implicit receiver. Computed entry keys and `for` sources resolve
    // lexical names (plus prior `local` members), while ordinary member
    // values see the implicit receiver with prior properties/elements.
    //
    // These two env copies happen per member, so they dominate the
    // per-eval allocation curve on object-body heavy fixtures. Pre-
    // reserving the upper bound (original env plus one slot per prior
    // member) skips the doubling-realloc tail.
    let lexical_env : Array[ValueBinding] = []
    lexical_env.reserve_capacity(env.length() + values.length() + 1)
    for binding in env {
      lexical_env.push(binding)
    }
    let local_env : Array[ValueBinding] = []
    local_env.reserve_capacity(implicit_env.length() + values.length() + 1)
    for binding in implicit_env {
      local_env.push(binding)
    }
    for prior in values {
      push_prior_member_into_env(
        lexical_env,
        prior,
        include_receiver_members=false,
      )
      push_prior_member_into_env(
        local_env,
        prior,
        include_receiver_members=true,
      )
    }
    // PKL-148ah: when this object body is the RHS of a module-level
    // binding currently on the resolution stack (`foo = { b = 43;
    // m3 = module.foo.b }`), expose the in-progress members as the
    // binding's value so `module.foo.b` resolves against the partial
    // snapshot rather than re-entering the binding (which would emit
    // `cyclic property reference foo`). Apple Pkl handles this through
    // implicit late binding — the prior siblings are visible inside
    // the body via the implicit-receiver chain, and `module.<self>`
    // sees the same snapshot. Mirror the snapshot by copying the
    // already-computed `values`; the inflight entry sits at the end of
    // `local_env` so `lookup_value` (last-match-wins) returns it ahead
    // of anything the outer scope might have shadowed.
    if stack.length() > 0 {
      let inflight_name = stack[stack.length() - 1]
      if lookup_value(local_env, inflight_name) is None {
        let snapshot : Array[ValueMember] = []
        snapshot.reserve_capacity(values.length())
        for prior in values {
          snapshot.push(prior)
        }
        lexical_env.push({ name: inflight_name, value: ObjectValue(snapshot) })
        local_env.push({ name: inflight_name, value: ObjectValue(snapshot) })
      }
    }
    // PKL-148x: Dynamic-shape sentinels. `@subscript$<offset>`
    // (`[key] = value` mapping entry) decodes the synthetic
    // `CallExpr(Identifier("@__index_entry"), [key, value])` payload
    // and stores the (key, value) pair as a synthetic ObjectValue
    // with `@key` / `@value` members; `@element$<offset>` evaluates
    // the raw bare-expression payload and keeps the sentinel name
    // so the renderer projects it listing-style (no `name =`
    // prefix).
    if field.name.has_prefix("@subscript$") {
      match field.value {
        CallExpr(Identifier("@__index_entry"), args) =>
          if args.length() == 2 {
            let key = eval_expr_with_bindings(
              args[0],
              local_bindings,
              lexical_env,
              class_env,
              cache_for_nested_object_value(field.value, cache, values),
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            let value_diagnostics : Array[Diagnostic] = if defer_property_errors {
              []
            } else {
              diagnostics
            }
            let subscript_value_env = copy_value_bindings(local_env)
            subscript_value_env.push({
              name: "outer",
              value: ObjectValue(copy_value_members(values)),
            })
            if stack.length() > 0 {
              let inflight_name = stack[stack.length() - 1]
              if lookup_value(subscript_value_env, inflight_name) is None {
                subscript_value_env.push({
                  name: inflight_name,
                  value: ObjectValue(copy_value_members(values)),
                })
              }
            }
            let val = eval_expr_with_bindings(
              args[1],
              local_bindings,
              subscript_value_env,
              class_env,
              cache_with_outer_object(cache, values),
              stack,
              declarations,
              value_diagnostics,
              resolve_import,
            )
            match (key, val) {
              (Some(k), Some(v)) =>
                ignore(
                  push_dynamic_object_member(
                    values,
                    {
                      name: field.name,
                      value: ObjectValue([
                        {
                          name: "@key",
                          value: k,
                          source: None,
                          annotations: [],
                        },
                        {
                          name: "@value",
                          value: v,
                          source: None,
                          annotations: [],
                        },
                      ]),
                      source: None,
                      annotations: [],
                    },
                    diagnostics,
                  ),
                )
              (Some(k), None) =>
                if defer_property_errors && value_diagnostics.length() > 0 {
                  ignore(
                    push_dynamic_object_member(
                      values,
                      {
                        name: field.name,
                        value: ObjectValue([
                          {
                            name: "@key",
                            value: k,
                            source: None,
                            annotations: [],
                          },
                          {
                            name: "@value",
                            value: deferred_error_value(
                              value_diagnostics[0].message,
                            ),
                            source: None,
                            annotations: [],
                          },
                        ]),
                        source: None,
                        annotations: [],
                      },
                      diagnostics,
                    ),
                  )
                }
              _ => ()
            }
          }
        _ => ()
      }
      continue
    }
    if field.name.has_prefix("@element$") {
      let element_diagnostics : Array[Diagnostic] = if defer_property_errors {
        []
      } else {
        diagnostics
      }
      match
        eval_expr_with_bindings(
          field.value,
          local_bindings,
          local_env,
          class_env,
          cache_for_nested_object_value(field.value, cache, values),
          stack,
          declarations,
          element_diagnostics,
          resolve_import,
        ) {
        Some(v) => {
          let value = tag_xml_function_element_from_source(field.value, v)
          values.push({
            name: field.name,
            value,
            source: Some(field.value),
            annotations: field.annotations,
          })
        }
        None =>
          if defer_property_errors && element_diagnostics.length() > 0 {
            values.push({
              name: field.name,
              value: deferred_error_value(element_diagnostics[0].message),
              source: Some(field.value),
              annotations: field.annotations,
            })
          }
      }
      continue
    }
    // PKL-148u / PKL-148d: route deferred property eval through a
    // local diagnostics buffer so a failure becomes a per-property
    // `@error$<name>` sentinel instead of bubbling to the outer
    // diagnostics array. Class defaults opt in for every property;
    // ordinary object bodies opt in only for `local` members so an
    // unused typed local does not reject the whole object, while a
    // later bare-name reference still surfaces the stored diagnostic.
    let defer_field_errors = defer_property_errors ||
      is_local_member_name(field.name)
    let property_diagnostics : Array[Diagnostic] = if defer_field_errors {
      []
    } else {
      diagnostics
    }
    if field.name == "@for" {
      match field.value {
        ForGenerator(
          var1,
          var2,
          source_expr,
          body_members,
          var1_type,
          var2_type
        ) => {
          match
            eval_for_generator(
              var1,
              var2,
              source_expr,
              body_members,
              var1_type,
              var2_type,
              local_bindings,
              lexical_env,
              local_env,
              class_env,
              cache_for_nested_object_value(field.value, cache, values),
              stack,
              declarations,
              property_diagnostics,
              resolve_import,
              defer_generated_member_errors=defer_property_errors,
            ) {
            Some(ObjectValue(branch_members)) => {
              let mut ok = true
              for branch_member in branch_members {
                if ok {
                  ok = push_dynamic_object_member(
                    values, branch_member, property_diagnostics,
                  )
                }
              }
            }
            Some(_) =>
              property_diagnostics.push(
                diag("object-body generator must produce an object body"),
              )
            None => ()
          }
          continue
        }
        _ => ()
      }
    }
    // PKL-148bg: see eval_binding.mbt — when a member declares a
    // user-class annotation (`local base: TheClass2 = new { ... }`)
    // and the RHS is a bare `new { ... }` (ObjectLiteral), rewrite to
    // `new TheClass2 { ... }` (TypedObjectLiteral) so the class's
    // hidden / default machinery runs. Without this the unprefixed
    // `requiredLength` would leak into the rendered output
    // (`listings/listing6` fixture).
    let effective_type_name = match field.type_name {
      Some(_) => field.type_name
      None =>
        match lookup_value(cache, "@__constructing_class") {
          Some(StringValue(class_name)) =>
            class_property_type_annotation_from_class_env(
              class_name,
              strip_member_visibility_prefix(field.name),
              class_env,
            )
          _ => None
        }
    }
    let collection_field_value = collection_literal_expr_for_type_annotation(
      field.value,
      effective_type_name,
    )
    let field_value : Expr = match collection_field_value {
      ObjectLiteral(inner_members) =>
        if object_member_targets_function_default(field.name, cache) {
          AmendExpr(
            MemberAccess(
              Identifier("super"),
              strip_member_visibility_prefix(field.name),
            ),
            inner_members,
          )
        } else {
          match effective_type_name {
            Some(type_name) =>
              match
                instantiable_class_name_for_type_annotation(
                  type_name, class_env,
                ) {
                Some(class_name) =>
                  TypedObjectLiteral(class_name, inner_members)
                None => collection_field_value
              }
            None => collection_field_value
          }
        }
      _ => collection_field_value
    }
    match
      eval_expr_with_bindings(
        field_value,
        local_bindings,
        local_env,
        class_env,
        cache_for_nested_object_value(field_value, cache, values),
        stack,
        declarations,
        property_diagnostics,
        resolve_import,
      ) {
      Some(raw_value) => {
        let value = coerce_value_to_annotated_type(
          raw_value, effective_type_name,
        )
        let value = apply_collection_default_for_type(
          value, effective_type_name, local_bindings, local_env, class_env, cache,
          stack, declarations, property_diagnostics, resolve_import,
        )
        if field.name == "@when" || field.name == "@for" {
          match value {
            ObjectValue(branch_members) => {
              let mut ok = true
              for branch_member in branch_members {
                if ok {
                  ok = push_dynamic_object_member(
                    values, branch_member, property_diagnostics,
                  )
                }
              }
            }
            _ =>
              property_diagnostics.push(
                diag("object-body generator must produce an object body"),
              )
          }
        } else if field.name == "@spread" {
          // PKL-148s / PKL-148x: splice the spread payload into the
          // parent. ObjectValue merges members directly;
          // ListingValue / ListValue / SetValue lower to
          // `@element$<offset>` sentinels (Dynamic-shape unnamed
          // elements); MappingValue / MapValue lower to
          // `@subscript$<offset>` sentinels (Dynamic-shape mapping
          // entries with `@key` / `@value` sub-members). `NullValue`
          // is silently skipped (covers `...?x` against null; the
          // required `...x` form would ideally surface a diagnostic,
          // but the AST-level required-vs-optional distinction isn't
          // worth the bookkeeping until a gold fixture exercises it).
          match value {
            ObjectValue(spread_members) => {
              let named : Array[ValueMember] = []
              let subscripts : Array[ValueMember] = []
              let elements : Array[ValueMember] = []
              for spread_member in spread_members {
                if spread_member.name.has_prefix("@subscript$") {
                  subscripts.push(spread_member)
                } else if spread_member.name.has_prefix("@element$") {
                  elements.push(spread_member)
                } else {
                  named.push(spread_member)
                }
              }
              let mut ok = true
              for spread_member in named {
                if ok {
                  ok = push_dynamic_object_member(
                    values, spread_member, property_diagnostics,
                  )
                }
              }
              for spread_member in subscripts {
                if ok {
                  ok = push_dynamic_object_member(
                    values, spread_member, property_diagnostics,
                  )
                }
              }
              for spread_member in elements {
                if ok {
                  ok = push_dynamic_object_member(
                    values, spread_member, property_diagnostics,
                  )
                }
              }
            }
            ListingValue(elements)
            | DefaultedListingValue(_, elements, _)
            | ListValue(elements)
            | SetValue(elements) =>
              for i = 0; i < elements.length(); i = i + 1 {
                values.push({
                  name: "@element$spread" + field.name + "$" + i.to_string(),
                  value: elements[i],
                  source: None,
                  annotations: [],
                })
              }
            IntSeqValue(start_v, end_v, step_v) => {
              let elements = intseq_materialize(start_v, end_v, step_v)
              for i = 0; i < elements.length(); i = i + 1 {
                values.push({
                  name: "@element$spread" + field.name + "$" + i.to_string(),
                  value: elements[i],
                  source: None,
                  annotations: [],
                })
              }
            }
            BytesValue(bytes) => {
              let elements = bytes_materialize(bytes)
              for i = 0; i < elements.length(); i = i + 1 {
                values.push({
                  name: "@element$spread" + field.name + "$" + i.to_string(),
                  value: elements[i],
                  source: None,
                  annotations: [],
                })
              }
            }
            MappingValue(entries)
            | DefaultedMappingValue(_, entries, _)
            | MapValue(entries) =>
              for i = 0; i < entries.length(); i = i + 1 {
                ignore(
                  push_dynamic_object_member(
                    values,
                    {
                      name: "@subscript$spread" +
                      field.name +
                      "$" +
                      i.to_string(),
                      value: ObjectValue([
                        {
                          name: "@key",
                          value: entries[i].key,
                          source: None,
                          annotations: [],
                        },
                        {
                          name: "@value",
                          value: entries[i].value,
                          source: None,
                          annotations: [],
                        },
                      ]),
                      source: None,
                      annotations: [],
                    },
                    property_diagnostics,
                  ),
                )
              }
            // PKL-148bb: Apple Pkl silently drops non-collection
            // spreads (`parser/spread` exercises `...super.bar` where
            // `super.bar` is an `Int`; the spread contributes nothing
            // rather than raising). Null also stays a no-op.
            _ => ()
          }
        } else {
          let structural_reject = match field.type_name {
            Some(annotation) =>
              eval_resolved_annotation_structural_rejection_message(
                annotation, value, declarations,
              )
            None => None
          }
          match structural_reject {
            Some(message) => {
              property_diagnostics.push(diag(message))
              values.push({
                name: field.name,
                value,
                source: Some(field.value),
                annotations: field.annotations,
              })
            }
            None =>
              if pkl_constrained_type_annotation_value_is_valid(
                  field.type_name,
                  value,
                  property_diagnostics,
                ) {
                let runtime_reject = if defer_property_errors {
                  match lookup_value(cache, "@__constructing_class") {
                    Some(StringValue(class_name)) => {
                      let enclosing_members : Array[ValueMember] = []
                      for prior in values {
                        enclosing_members.push(prior)
                      }
                      enclosing_members.push({
                        name: field.name,
                        value,
                        source: Some(field.value),
                        annotations: field.annotations,
                      })
                      eval_runtime_constraint_for_property(
                        class_name,
                        strip_member_visibility_prefix(field.name),
                        value,
                        enclosing_members,
                        local_bindings,
                        local_env,
                        class_env,
                        cache,
                        stack,
                        declarations,
                        resolve_import,
                      )
                    }
                    _ => None
                  }
                } else {
                  None
                }
                match runtime_reject {
                  Some(message) => property_diagnostics.push(diag(message))
                  None => ()
                }
                values.push({
                  name: field.name,
                  value,
                  source: Some(field.value),
                  annotations: field.annotations,
                })
              }
          }
        }
      }
      None => ()
    }
    // PKL-148u / PKL-148d: post-process the per-property buffer when
    // deferring. Any diagnostic landed during this property's eval
    // becomes a `@error$<name>` sentinel that the ObjectValue access
    // path or the local-env hoist surfaces lazily; the outer
    // diagnostics array stays untouched so a sibling property's eval
    // has its own clean slate. If the property failed without
    // producing a member (e.g. function-call rejection that returned
    // `None`), push a `NullValue` placeholder so access doesn't
    // surface "Cannot find property" before the pending-error
    // intercept fires.
    if defer_field_errors && property_diagnostics.length() > 0 {
      if field.name == "@when" ||
        field.name == "@for" ||
        field.name == "@spread" {
        values.push({
          name: error_member_name("@deferred"),
          value: StringValue(property_diagnostics[0].message),
          source: None,
          annotations: [],
        })
        continue
      }
      let mut already_present = false
      for entry in values {
        if entry.name == field.name {
          already_present = true
          break
        }
      }
      if !already_present {
        values.push({
          name: field.name,
          value: NullValue,
          source: None,
          annotations: field.annotations,
        })
      }
      values.push({
        name: error_member_name(field.name),
        value: StringValue(property_diagnostics[0].message),
        source: None,
        annotations: [],
      })
    }
  }
  values
}
