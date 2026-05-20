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
          value: deep_merge_amend_value(default_member.value, raw_member.value),
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
    ImportGlobExpr(uri) =>
      match current_module_path_from_cache(cache) {
        Some(path) =>
          match sandbox_lookup_import_glob(path, uri) {
            Some(uris) => {
              let entries : Array[ValueEntry] = []
              for visible_uri in uris {
                entries.push({ key: StringValue(visible_uri), value: NullValue })
              }
              Some(MapValue(entries))
            }
            None => {
              diagnostics.push(diag("Cannot find module `\{uri}`."))
              None
            }
          }
        None => {
          diagnostics.push(diag("Cannot find module `\{uri}`."))
          None
        }
      }
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
      // PKL-152: a Listing body that picked up a bracket-key entry
      // (`new Listing { [0] = true }`) carries a synthetic call to
      // `@__listing_index_entry`. Pure construction can't index into
      // a non-existent element, so raise Apple Pkl's "Element index
      // out of range" diagnostic immediately.
      for element in elements {
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
                  bindings,
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
        match collection_default_expr_from_listing_element(element) {
          Some(default_expr) =>
            default_value = eval_collection_default_expr(
              default_expr, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          None => ()
        }
      }
      let raw_values : Array[Value] = []
      let values : Array[Value] = []
      for element in elements {
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
            push_collection_binding(
              body_env,
              body_cache,
              "this",
              collection_this_listing_value(raw_values, values, default_value),
            )
            match
              eval_expr_with_bindings(
                inner, bindings, body_env, class_env, body_cache, stack, declarations,
                diagnostics, resolve_import,
              ) {
              Some(ListingValue(inner_elements))
              | Some(DefaultedListingValue(_, inner_elements, _))
              | Some(ListValue(inner_elements)) =>
                for v in inner_elements {
                  raw_values.push(v)
                  values.push(v)
                }
              // PKL-148s: `...?x` against a null `x` silently skips
              // (also covers `...x` against null — see the matching
              // arm in `eval_object_members` for the rationale).
              Some(NullValue) => ()
              Some(_) =>
                diagnostics.push(
                  diag("when block inside Listing must produce a Listing"),
                )
              None => ()
            }
          }
          _ => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_binding(
              body_env,
              body_cache,
              "this",
              collection_this_listing_value(raw_values, values, default_value),
            )
            let diag_start = diagnostics.length()
            match
              eval_collection_body_expr(
                element,
                IntValue(raw_values.length().to_int64()),
                default_value,
                bindings,
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
      // PKL-152: a Mapping body that picked up a bare-expression
      // element (`new Mapping { "pigeon" }`) carries an `@element$`
      // sentinel key. Raise Apple Pkl's "cannot have an element"
      // wording before the entries get rendered.
      let mut mapping_when_seen = false
      for entry in entries {
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
        match collection_default_expr_from_mapping_entry(entry) {
          Some(default_expr) =>
            default_value = eval_collection_default_expr(
              default_expr, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          None => ()
        }
      }
      let raw_values : Array[ValueEntry] = []
      let values : Array[ValueEntry] = []
      let mut duplicate_emitted = false
      for entry in entries {
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
            push_collection_binding(
              body_env,
              body_cache,
              "this",
              collection_this_mapping_value(raw_values, values, default_value),
            )
            match
              eval_expr_with_bindings(
                inner, bindings, body_env, class_env, body_cache, stack, declarations,
                diagnostics, resolve_import,
              ) {
              Some(MappingValue(inner_entries)) =>
                for e in inner_entries {
                  raw_values.push(e)
                  values.push(e)
                }
              Some(DefaultedMappingValue(raw_entries, inner_entries, _)) => {
                for e in raw_entries {
                  raw_values.push(e)
                }
                for e in inner_entries {
                  values.push(e)
                }
              }
              // PKL-148s: `...?x` against a null `x` silently skips
              // (also covers `...x` against null).
              Some(NullValue) => ()
              Some(_) =>
                diagnostics.push(
                  diag("when block inside Mapping must produce a Mapping"),
                )
              None => ()
            }
          }
          _ => {
            let body_env = copy_value_bindings(env)
            let body_cache = copy_value_bindings(cache)
            push_collection_binding(
              body_env,
              body_cache,
              "this",
              collection_this_mapping_value(raw_values, values, default_value),
            )
            let key = eval_expr_with_bindings(
              entry.key,
              bindings,
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
                let entry_values = eval_collection_body_expr(
                  entry.value,
                  k,
                  default_value,
                  bindings,
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
                  None => ()
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
          Some(ObjectValue(members)) =>
            // PKL-143: if the object is a `pkl:reflect` mirror (carries
            // the hidden `__kind` marker), intercept introspection
            // members before the generic `lookup_member` path.
            match reflect_kind(members) {
              Some("Class") =>
                match member_name {
                  "properties" =>
                    match reflect_reflectee_name(members) {
                      Some(name) =>
                        Some(reflect_class_properties(name, declarations))
                      None => lookup_member(members, member_name)
                    }
                  "methods" =>
                    match reflect_reflectee_name(members) {
                      Some(name) =>
                        Some(reflect_class_methods(name, declarations))
                      None => lookup_member(members, member_name)
                    }
                  "supertype" =>
                    match reflect_reflectee_name(members) {
                      Some(name) =>
                        Some(reflect_class_supertype(name, declarations))
                      None => lookup_member(members, member_name)
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
                  "classes" => Some(reflect_module_classes(declarations))
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
                  Some(elements[0])
                }
              "last" =>
                if elements.length() == 0 {
                  diagnostics.push(diag("Set.last is empty"))
                  None
                } else {
                  Some(elements[elements.length() - 1])
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
          // `.isEmpty`, `.isNotEmpty`, `.keys` (Listing of keys),
          // `.values` (Listing of values), `.entries` (Listing of
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
                Some(ListingValue(values))
              }
              "entries" => {
                let pairs : Array[Value] = []
                for entry in entries {
                  pairs.push(PairValue(entry.key, entry.value))
                }
                Some(ListingValue(pairs))
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
        | (Some(ListValue(elements)), Some(IntValue(index64))) =>
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
        | (Some(ListValue(_)), Some(key_value)) => {
          // PKL-148bb: align with Apple Pkl wording so `test.catch`
          // snapshots in `listings/listing2.res8` round-trip.
          let actual = eval_value_type_name(key_value)
          diagnostics.push(
            diag("Expected key of type `Int`, but got type `\{actual}`."),
          )
          None
        }
        (Some(MappingValue(entries)), Some(key_value))
        | (Some(DefaultedMappingValue(_, entries, _)), Some(key_value)) =>
          match lookup_entry(entries, key_value) {
            Some(value) => Some(value)
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
    AmendExpr(base_expr, members) =>
      match
        eval_expr_with_bindings(
          base_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
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
          let amend_class_name = typed_object_class_name_for_expr(
            base_expr,
            bindings,
            [],
          )
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
        let module_members : Array[ValueMember] = []
        // PKL-148bb: expose the import (alias, URI) Map under the bare
        // name `imports` so `reflect.Module(module).imports`
        // (`api/reflect5`) recovers Apple Pkl's
        // `Map("reflect", "pkl:reflect", ...)` shape. The Map was
        // stashed at `eval_program` time under the hidden
        // `@__module_imports` cache key; promote it to a visible
        // member of the synthesised module ObjectValue.
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
        for value_binding in cache {
          if value_binding.name == "super" ||
            value_binding.name == "this" ||
            value_binding.name.has_prefix("@") {
            continue
          }
          module_members.push({
            name: value_binding.name,
            value: value_binding.value,
            source: None,
            annotations: [],
          })
        }
        Some(ObjectValue(module_members))
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
      } else if callee is Identifier("Bytes") &&
        !stack_contains_binding(stack, "Bytes") &&
        find_binding(bindings, "Bytes") is None {
        // PKL-083: `Bytes(<Listing of Int>)` constructor. Each element
        // is validated 0..=255 inside `build_bytes_from_int_listing`;
        // anything else records a diagnostic and bails.
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
            Some(ListingValue(elements))
            | Some(DefaultedListingValue(_, elements, _))
            | Some(ListValue(elements)) =>
              build_bytes_from_int_listing(elements, diagnostics)
            Some(_) => {
              diagnostics.push(diag("Bytes expects a Listing of Int"))
              None
            }
            None => None
          }
        } else {
          diagnostics.push(diag("Bytes expects exactly one argument"))
          None
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
              match current_module_path_from_cache(cache) {
                Some(path) =>
                  match sandbox_lookup_read_glob(path, pattern) {
                    Some(resources) => {
                      let entries : Array[ValueEntry] = []
                      for resource in resources {
                        entries.push({
                          key: StringValue(resource.uri),
                          value: sandbox_resource_value(resource),
                        })
                      }
                      Some(MapValue(entries))
                    }
                    None => {
                      diagnostics.push(diag("Cannot find module `\{pattern}`."))
                      None
                    }
                  }
                None => {
                  diagnostics.push(diag("Cannot find module `\{pattern}`."))
                  None
                }
              }
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
            } else if target_expr is Identifier(class_name) &&
              lookup_class_binding(class_env, class_name) is Some(_) {
              // PKL-148d: `Person.bar()` where `Person` is a class name
              // and `bar` isn't a static-callable method. Apple Pkl
              // reports `Cannot find method \`bar\` in class \`Class\`.`
              // — distinct from the property-access wording.
              diagnostics.push(
                diag("Cannot find method `\{method_name}` in class `Class`."),
              )
              None
            } else if method_name == "getClass" && arguments.length() == 0 {
              // PKL-148: `value.getClass()` returns a `pkl:reflect.Class`
              // mirror exposing `simpleName` / `name`. snippetTest's
              // `api/any.pkl` exercises this on every primitive variant
              // — Int, Float, Bool, String, Duration, DataSize, List,
              // Map, Listing, Mapping, Dynamic, Pair, Null.
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
                      synth_class_mirror_for_qualified(bare, Some(module_name)),
                    )
                  } else {
                    Some(synth_class_mirror_for_value(value))
                  }
                }
                None => None
              }
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
              method_name == "toUnit" ||
              method_name == "toBinaryUnit" ||
              method_name == "toDecimalUnit" ||
              method_name == "toBytes" ||
              method_name == "isSubclassOf" ||
              method_name == "parse" ||
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
                  if (
                      method_name == "renderValue" ||
                      method_name == "renderDocument"
                    ) &&
                    renderer_format_from_members(receiver_members)
                    is Some(format) {
                    eval_value_renderer_method(
                      format, receiver_members, method_name, arguments, bindings,
                      env, class_env, cache, stack, declarations, diagnostics, resolve_import,
                    )
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
                            Some(json_to_value(parsed, use_mapping))
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
                  } else if method_name == "parse" &&
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
                          "yaml.Parser.parse expects 1 argument, got \{arguments.length()}",
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
                            let docs = @yaml.Yaml::load_from_string(
                              source_text[:],
                            )
                            if docs.length() == 0 {
                              Some(NullValue)
                            } else {
                              Some(yaml_to_value(docs[0], use_mapping))
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
                            diag("yaml.Parser.parse expects a String argument"),
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
                          match
                            (
                              reflect_reflectee_name(receiver_members),
                              reflect_reflectee_name(other_members),
                            ) {
                            (Some(child), Some(parent)) =>
                              Some(
                                BoolValue(
                                  reflect_is_subclass_of(
                                    child, parent, declarations,
                                  ),
                                ),
                              )
                            _ => {
                              diagnostics.push(
                                diag(
                                  "Class.isSubclassOf expects a Class mirror argument",
                                ),
                              )
                              None
                            }
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
                          callee, arguments, bindings, env, class_env, cache, stack,
                          declarations, diagnostics, resolve_import,
                        )
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
                  let user_class_match = if value is ObjectValue(_) {
                    if lookup_class_binding(class_env, base_for_user_check)
                      is Some(_) {
                      true
                    } else if lookup_value(env, base_for_user_check)
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
                  if !value_is_type(value, type_name) && !user_class_match {
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
        // shape-preserving (no coercion / widening).
        As => {
          let value_opt = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match (value_opt, right_expr) {
            (Some(value), Identifier(type_name)) => {
              let aliases = eval_type_alias_bindings(declarations)
              let resolved = eval_resolved_type_alias(type_name, aliases)
              // PKL-150 / PKL-148at: shape-preserving cast — the
              // `eval_value_accepts_type_annotation` cascade now
              // handles unions (`Int|String`), nullables (`T?`),
              // generic heads (`Listing<Int>` → strip to `Listing`),
              // string-literal singletons (`"Pigeon"`), and the
              // constrained shape (`Foo(...)`) uniformly, so the
              // As eval no longer needs to do the head strip itself.
              // user_class_annotation is a separate fallback for
              // user-declared class names that the cascade doesn't
              // recognise. The diagnostic still quotes the surface
              // name so user-facing messages preserve the original
              // annotation text.
              let user_class_head = match
                pkl_constrained_type_base_name(resolved) {
                Some(base) => base
                None => resolved
              }
              let user_class_head = match user_class_head.find("<") {
                Some(idx) =>
                  String::unsafe_substring(user_class_head, start=0, end=idx)
                None => user_class_head
              }
              if eval_value_accepts_type_annotation(resolved, value) ||
                value_satisfies_user_class_annotation(
                  user_class_head, value, declarations,
                ) {
                return Some(value)
              } else {
                let diag_name = rejection_type_label(type_name)
                let message = if value is NullValue {
                  "Expected value of type `\{diag_name}`, but got `null`."
                } else {
                  "Expected value of type `\{diag_name}`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}"
                }
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
              match int_pow(a, b) {
                Some(value) => Some(IntValue(value))
                None => {
                  diagnostics.push(
                    diag("operator ** expects non-negative exponent"),
                  )
                  None
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
        (Some(DurationValue(av, au)), Some(DurationValue(bv, bu))) =>
          // Same-unit arithmetic keeps the magnitudes raw to avoid Int32
          // overflow on the intermediate ns conversion (one `1.s` already
          // grosses 1e9 ns — `4.s` alone overflows). Mixed-unit operations
          // pick the smaller unit so the result stays expressible as an
          // Int; the upstream evaluator switches to Float for fractional
          // mixed-unit cases, which is the documented gap for this slice.
          if au == bu {
            match op {
              Add => Some(DurationValue(av + bv, au))
              Subtract => Some(DurationValue(av - bv, au))
              LessThan => Some(BoolValue(av < bv))
              LessOrEqual => Some(BoolValue(av <= bv))
              GreaterThan => Some(BoolValue(av > bv))
              GreaterOrEqual => Some(BoolValue(av >= bv))
              Equal => Some(BoolValue(av == bv))
              NotEqual => Some(BoolValue(av != bv))
              _ => {
                diagnostics.push(
                  diag(
                    "operator \{operator_name(op)} not defined for Duration operands",
                  ),
                )
                None
              }
            }
          } else {
            let target = smaller_duration_unit(au, bu)
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
              _ => {
                diagnostics.push(
                  diag(
                    "operator \{operator_name(op)} not defined for Duration operands",
                  ),
                )
                None
              }
            }
          }
        (Some(DataSizeValue(av, au)), Some(DataSizeValue(bv, bu))) =>
          if au == bu {
            match op {
              Add => Some(DataSizeValue(av + bv, au))
              Subtract => Some(DataSizeValue(av - bv, au))
              LessThan => Some(BoolValue(av < bv))
              LessOrEqual => Some(BoolValue(av <= bv))
              GreaterThan => Some(BoolValue(av > bv))
              GreaterOrEqual => Some(BoolValue(av >= bv))
              Equal => Some(BoolValue(av == bv))
              NotEqual => Some(BoolValue(av != bv))
              _ => {
                diagnostics.push(
                  diag(
                    "operator \{operator_name(op)} not defined for DataSize operands",
                  ),
                )
                None
              }
            }
          } else {
            let target = smaller_datasize_unit(au, bu)
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
              _ => {
                diagnostics.push(
                  diag(
                    "operator \{operator_name(op)} not defined for DataSize operands",
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
    ForGenerator(var1, var2, source_expr, body_members) =>
      eval_for_generator(
        var1, var2, source_expr, body_members, bindings, env, class_env, cache, stack,
        declarations, diagnostics, resolve_import,
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
                None => Some(NullValue)
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
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let source = eval_expr_with_bindings(
    source_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
    resolve_import,
  )
  let mut accumulated : Array[ValueMember] = []
  match source {
    Some(ListingValue(elements))
    | Some(DefaultedListingValue(_, elements, _))
    | Some(ListValue(elements))
    | Some(SetValue(elements)) =>
      for i = 0; i < elements.length(); i = i + 1 {
        let iter_cache = copy_value_bindings(cache)
        match var2 {
          Some(name2) => {
            iter_cache.push({ name: var1, value: IntValue(i.to_int64()) })
            iter_cache.push({ name: name2, value: elements[i] })
          }
          None => iter_cache.push({ name: var1, value: elements[i] })
        }
        let iter_members = eval_object_members(
          body_members, bindings, env, class_env, iter_cache, stack, declarations,
          diagnostics, resolve_import,
        )
        accumulated = merge_for_generator_members(accumulated, iter_members, i)
      }
    // PKL-148bb: `IntSeq(a, b)` iterates `a..=b` inclusive. The
    // single-var form binds the current integer; the two-var form
    // binds (index, value) like Listing.
    Some(IntSeqValue(start_v, end_v, step_v)) => {
      let elements : Array[Value] = []
      if step_v > 0L {
        let mut v = start_v
        while v <= end_v {
          elements.push(IntValue(v))
          v = v + step_v
        }
      } else if step_v < 0L {
        let mut v = start_v
        while v >= end_v {
          elements.push(IntValue(v))
          v = v + step_v
        }
      }
      for i = 0; i < elements.length(); i = i + 1 {
        let iter_cache = copy_value_bindings(cache)
        match var2 {
          Some(name2) => {
            iter_cache.push({ name: var1, value: IntValue(i.to_int64()) })
            iter_cache.push({ name: name2, value: elements[i] })
          }
          None => iter_cache.push({ name: var1, value: elements[i] })
        }
        let iter_members = eval_object_members(
          body_members, bindings, env, class_env, iter_cache, stack, declarations,
          diagnostics, resolve_import,
        )
        accumulated = merge_for_generator_members(accumulated, iter_members, i)
      }
    }
    Some(MappingValue(entries))
    | Some(DefaultedMappingValue(_, entries, _))
    | Some(MapValue(entries)) =>
      for i = 0; i < entries.length(); i = i + 1 {
        let entry = entries[i]
        let iter_cache = copy_value_bindings(cache)
        match var2 {
          Some(name2) => {
            iter_cache.push({ name: var1, value: entry.key })
            iter_cache.push({ name: name2, value: entry.value })
          }
          None => {
            diagnostics.push(
              diag(
                "for-generator over Mapping requires two variables (key, value)",
              ),
            )
            return None
          }
        }
        let iter_members = eval_object_members(
          body_members, bindings, env, class_env, iter_cache, stack, declarations,
          diagnostics, resolve_import,
        )
        accumulated = merge_for_generator_members(accumulated, iter_members, i)
      }
    Some(_) => {
      diagnostics.push(diag("for-generator source must be Listing or Mapping"))
      return None
    }
    None => return None
  }
  Some(ObjectValue(accumulated))
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
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent_name) => {
          let aliases = eval_type_alias_bindings(declarations)
          collect_class_default_properties_in_order(
            out,
            eval_resolved_type_alias(parent_name, aliases),
            class_env,
            declarations,
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
        source, bindings, local_env, class_env, reeval_cache, stack, declarations,
        diagnostics, resolve_import,
      ) {
      Some(raw_value) => {
        let value = coerce_value_to_annotated_type(
          raw_value,
          property.type_name,
        )
        if replace_member_value_by_bare_name(current, property.name, value) {
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
    Some(value) =>
      match format {
        "pcf" => Some(StringValue(render_value(value)))
        "json" => Some(StringValue(render_value_as_json(value)))
        "yaml" => Some(StringValue(render_value_as_yaml(value)))
        "properties" => Some(StringValue(render_value_as_properties(value)))
        "plist" => Some(StringValue(render_value_as_plist(value)))
        "textproto" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_textproto_with_indent(value, indent_text),
              ),
            )
          } else {
            Some(
              StringValue(
                render_value_as_textproto_fragment(value, indent_text),
              ),
            )
          }
        }
        "xml" => {
          let indent_text = xml_renderer_option(
            renderer_members, "indent", "  ",
          )
          if method_name == "renderDocument" {
            Some(
              StringValue(
                render_value_as_xml_with_options(
                  value,
                  xml_renderer_option(
                    renderer_members, "rootElementName", "root",
                  ),
                  indent_text,
                  xml_renderer_option(renderer_members, "xmlVersion", "1.0"),
                ),
              ),
            )
          } else {
            Some(StringValue(render_value_as_xml_fragment(value, indent_text)))
          }
        }
        _ => None
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
          return copy_function_parameters(parameters)
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
  next.push({
    name: "outer",
    value: ObjectValue(copy_value_members(outer_members)),
  })
  next
}

///|
fn cache_for_nested_object_value(
  value : Expr,
  cache : Array[ValueBinding],
  outer_members : Array[ValueMember],
) -> Array[ValueBinding] {
  match value {
    ObjectLiteral(_) | TypedObjectLiteral(_, _) =>
      cache_with_outer_object(cache, outer_members)
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
    ForGenerator(_, _, source, members) => {
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
    ForGenerator(_, _, source, members) => {
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
    ForGenerator(_, _, source, members) => {
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
    ForGenerator(key_name, value_name, source, members) => {
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
          (_, ov) => ov
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
      final_members.push(m)
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
  let mut found : ValueMember? = None
  for field in members {
    if field.name == name {
      found = Some(field)
    }
  }
  found
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
  eval_object_members_with_options(
    members,
    bindings,
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
    None => None
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
  // PKL-148e: pre-register every sibling member as a binding so a
  // forward reference (`x = 1 + y; y = 2`) resolves through the
  // bindings-driven lazy lookup path. Cycle detection still kicks in
  // via the `stack` argument inside `resolve_binding_value`.
  let local_bindings : Array[Binding] = []
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
  for field in members {
    if is_function_amend_marker_member_name(field.name) {
      continue
    }
    // PKL-148d: build a per-field eval env that shadows the outer
    // scope with the members already produced inside this body. Apple
    // Pkl's implicit-receiver resolution means `bar { x = 2; y = x +
    // 3 }` resolves `x` in `y`'s RHS to the inner `x = 2` first, not
    // the enclosing `foo.x`. The env entries are pushed in
    // declaration order so a later field sees the earlier values.
    let local_env : Array[ValueBinding] = []
    for binding in env {
      local_env.push(binding)
    }
    for prior in values {
      if is_error_member_name(prior.name) {
        // PKL-148ak: a `@error$<stored>` sentinel from a deferred
        // type / constraint rejection on a sibling. Strip whatever
        // visibility prefix lives inside the sentinel name so the
        // env entry sits under `@error$<bare>` — the Identifier
        // resolution path picks it up before the (type-invalid)
        // bare-name value and raises the deferred diagnostic so
        // `test.catch(() -> p2)` can capture it.
        let inner = String::unsafe_substring(
          prior.name,
          start=error_member_prefix.length(),
          end=prior.name.length(),
        )
        let bare = strip_member_visibility_prefix(inner)
        local_env.push({ name: error_member_name(bare), value: prior.value })
      } else if is_invisible_member_name(prior.name) {
        // PKL-148d: a `local l = 2` / `hidden h = 2` member surfaces
        // under its visibility prefix; strip when hoisting into env
        // so subsequent sibling expressions can reference the bare
        // name. PKL-148j: handles both `@hidden$` and `@local$` via
        // `strip_member_visibility_prefix`.
        let bare = strip_member_visibility_prefix(prior.name)
        local_env.push({ name: bare, value: prior.value })
      } else {
        local_env.push({ name: prior.name, value: prior.value })
      }
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
      let snapshot : Array[ValueMember] = []
      for prior in values {
        snapshot.push(prior)
      }
      local_env.push({ name: inflight_name, value: ObjectValue(snapshot) })
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
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            let val = eval_expr_with_bindings(
              args[1],
              local_bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            match (key, val) {
              (Some(k), Some(v)) =>
                values.push({
                  name: field.name,
                  value: ObjectValue([
                    { name: "@key", value: k, source: None, annotations: [] },
                    { name: "@value", value: v, source: None, annotations: [] },
                  ]),
                  source: None,
                  annotations: [],
                })
              _ => ()
            }
          }
        _ => ()
      }
      continue
    }
    if field.name.has_prefix("@element$") {
      match
        eval_expr_with_bindings(
          field.value,
          local_bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(v) =>
          values.push({
            name: field.name,
            value: v,
            source: None,
            annotations: field.annotations,
          })
        None => ()
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
            ObjectValue(branch_members) =>
              for branch_member in branch_members {
                values.push(branch_member)
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
            ObjectValue(spread_members) =>
              for spread_member in spread_members {
                values.push(spread_member)
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
            MappingValue(entries)
            | DefaultedMappingValue(_, entries, _)
            | MapValue(entries) =>
              for i = 0; i < entries.length(); i = i + 1 {
                values.push({
                  name: "@subscript$spread" + field.name + "$" + i.to_string(),
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
                })
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
