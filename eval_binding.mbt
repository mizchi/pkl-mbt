///|
fn stack_contains_binding(stack : Array[String], name : String) -> Bool {
  for item in stack {
    if item == name {
      return true
    }
  }
  false
}

///|
fn push_binding_stack(stack : Array[String], name : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(name)
  next
}

///|
fn typed_object_class_name_for_expr(
  expr : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> String? {
  match expr {
    TypedObjectLiteral(type_name, _) => Some(type_name)
    AmendExpr(base, _) | NonNullExpr(base) =>
      typed_object_class_name_for_expr(base, bindings, stack)
    Identifier(name) =>
      if stack_contains_binding(stack, name) {
        None
      } else {
        match find_binding(bindings, name) {
          Some(binding) =>
            // PKL-148bh: `local a: A = new {}` keeps the binding's
            // value as an ObjectLiteral (the binding-eval rewrite
            // only fires at value time, not at AST construction).
            // Honour the binding annotation directly when its value
            // is a bare ObjectLiteral so a downstream `a.method()`
            // dispatches against class A's method table.
            match (binding.value, binding.type_name) {
              (ObjectLiteral(_), Some(class_name)) =>
                if class_name.contains("<") ||
                  class_name.contains("|") ||
                  class_name.contains("(") ||
                  class_name.contains("?") ||
                  class_name.contains(".") {
                  typed_object_class_name_for_expr(
                    binding.value,
                    bindings,
                    push_binding_stack(stack, name),
                  )
                } else {
                  Some(class_name)
                }
              _ =>
                typed_object_class_name_for_expr(
                  binding.value,
                  bindings,
                  push_binding_stack(stack, name),
                )
            }
          None => None
        }
      }
    _ => None
  }
}

///|
fn copy_value_bindings(bindings : Array[ValueBinding]) -> Array[ValueBinding] {
  // Pre-size to skip the doubling-realloc dance on the hot
  // class-default path. `copy_value_bindings(cache)` runs once per
  // class-layer materialisation; on `apple-pkl/stdlib/base.pkl` that
  // landed in the top sample bucket as `moonbit_unsafe_ref_array_blit`
  // / `moonbit_make_ref_array` traffic.
  let copied : Array[ValueBinding] = []
  copied.reserve_capacity(bindings.length())
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn capture_value_bindings(
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Array[ValueBinding] {
  let captured = copy_value_bindings(env)
  // Upper bound: every cache entry might be retained (excluding the
  // handful of `@__module_*` / `@__class_default_*` markers filtered
  // below).
  captured.reserve_capacity(env.length() + cache.length())
  for binding in cache {
    // PKL-148bh / PKL-148bl: module metadata markers are plumbing for
    // reflect/read dispatch and get reintroduced from the caller cache
    // at application time. Keeping them out of captured_env prevents
    // ordinary function values from growing hidden bindings.
    if binding.name == "@__module_name" ||
      binding.name == "@__module_path" ||
      binding.name == "@__module_source" ||
      binding.name == "@__class_default_scope" ||
      binding.name == "@__class_default_call_scope" {
      continue
    }
    captured.push(binding)
  }
  captured
}

///|
fn lookup_value_after_marker(
  cache : Array[ValueBinding],
  marker : String,
  name : String,
) -> Value? {
  let mut active = false
  let mut found : Value? = None
  for binding in cache {
    if binding.name == marker {
      active = true
      continue
    }
    if active && binding.name == name {
      found = Some(binding.value)
    }
  }
  found
}

///|
fn lookup_class_default_call_local(
  cache : Array[ValueBinding],
  name : String,
) -> Value? {
  // Parameters are appended after the class-default call marker. They
  // must shadow module bindings with the same name before const
  // provenance rejects the module binding.
  match lookup_value_after_marker(cache, "@__class_default_call_scope", name) {
    Some(value) => Some(value)
    None =>
      match
        lookup_value_after_marker(
          cache,
          "@__class_default_call_scope",
          hidden_member_name(name),
        ) {
        Some(value) => Some(value)
        None =>
          lookup_value_after_marker(
            cache,
            "@__class_default_call_scope",
            local_member_name(name),
          )
      }
  }
}

///|
fn int_pow(base : Int64, exponent : Int64) -> Int64? {
  if exponent == 0L {
    return Some(1L)
  }
  let mut result = 1L
  let mut factor = base
  let mut remaining = exponent
  while remaining > 0L {
    if remaining % 2L == 1L {
      match checked_int64_mul(result, factor) {
        Some(next) => result = next
        None => return None
      }
    }
    remaining = remaining / 2L
    if remaining > 0L {
      match checked_int64_mul(factor, factor) {
        Some(next) => factor = next
        None => return None
      }
    }
  }
  Some(result)
}

///|
fn checked_int64_mul(a : Int64, b : Int64) -> Int64? {
  if a == 0L || b == 0L {
    return Some(0L)
  }
  let max = 9223372036854775807L
  let min = 0L - 9223372036854775807L - 1L
  let ok = if a > 0L {
    if b > 0L {
      a <= max / b
    } else {
      b >= min / a
    }
  } else if b > 0L {
    a >= min / b
  } else {
    a >= max / b
  }
  if ok {
    Some(a * b)
  } else {
    None
  }
}

///|
fn binding_collection_host_constraint_rejection_message(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match type_name {
    Some(annotation) => {
      let aliases = eval_type_alias_bindings(declarations)
      let resolved = eval_resolved_type_alias(annotation, aliases)
      let source = strip_lazy_collection_annotation_marker(resolved)
      match value {
        ListingValue(elements)
        | DefaultedListingValue(_, elements, _)
        | ListValue(elements) =>
          pkl_constrained_listing_rejection_message_from_source(
            source, elements,
          )
        _ => None
      }
    }
    None => None
  }
}

///|
fn inherited_module_object_amend_expr(
  binding_name : String,
  expr : Expr,
  type_name : String?,
  cache : Array[ValueBinding],
) -> Expr {
  if binding_name != "output" {
    return expr
  }
  match (expr, type_name) {
    (ObjectLiteral(members), None) =>
      match module_super_members_from_cache(cache) {
        Some(parent_members) =>
          match lookup_value_member(parent_members, binding_name) {
            Some(_) =>
              AmendExpr(
                MemberAccess(Identifier("super"), binding_name),
                members,
              )
            None => expr
          }
        None => expr
      }
    _ => expr
  }
}

///|
fn resolve_binding_value(
  name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  // PKL-148d: lexical scope wins over module-level bindings. Apple
  // Pkl's implicit-receiver chain walks the innermost object body
  // first (`bar { x = 2; y = x + 3 }` resolves the RHS `x` to the
  // inner `x = 2`, not the module-level `x = 0`). The env slot now
  // carries the inner-scope members so a lookup must check it before
  // the module's binding cache.
  match lookup_value(env, name) {
    Some(value) => return Some(value)
    None => ()
  }
  let shadow_binding = find_binding(bindings, name)
  if lookup_value(cache, "@__class_default_call_scope") is Some(_) {
    match lookup_class_default_call_local(cache, name) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  if lookup_value(cache, "@__class_default_scope") is Some(_) ||
    lookup_value(cache, "@__class_default_call_scope") is Some(_) {
    match shadow_binding {
      Some(binding) =>
        if !binding.is_const && !(binding.value is LambdaExpr(_, _, _)) {
          let message = match
            lookup_value(cache, "@__class_default_call_name") {
            Some(StringValue(method_name)) =>
              "Cannot call method `\{method_name}` from here because it is not `const`."
            _ =>
              "Cannot reference property `\{name}` from here because it is not `const`."
          }
          diagnostics.push(diag(message))
          return None
        }
      None => ()
    }
  }
  let binding_shadows_cache = match shadow_binding {
    Some(binding) => binding.abstract_slot
    None => false
  }
  if !binding_shadows_cache {
    match lookup_value(cache, name) {
      Some(value) => return Some(value)
      None => ()
    }
    match lookup_value(cache, hidden_member_name(name)) {
      Some(value) => return Some(value)
      None => ()
    }
    match lookup_value(cache, local_member_name(name)) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  match shadow_binding {
    Some(binding) =>
      if binding.abstract_slot && binding.value is NullLiteral {
        match
          synthesize_default_for_type(
            binding.type_name,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(value) => {
            let structural_reject = match binding.type_name {
              Some(annotation) =>
                eval_resolved_annotation_structural_rejection_message(
                  annotation, value, declarations,
                )
              None => None
            }
            match structural_reject {
              Some(message) => {
                diagnostics.push(diag(message))
                None
              }
              None =>
                if pkl_constrained_type_annotation_value_is_valid(
                    binding.type_name,
                    value,
                    diagnostics,
                  ) {
                  cache.push({ name: binding.name, value })
                  Some(value)
                } else {
                  None
                }
            }
          }
          None => None
        }
      } else if lookup_value(cache, "@__class_default_scope") is Some(_) &&
        !binding.is_const &&
        !(binding.value is LambdaExpr(_, _, _)) {
        diagnostics.push(
          diag(
            "Cannot reference property `\{name}` from here because it is not `const`.",
          ),
        )
        None
      } else if stack_contains_binding(stack, name) {
        // PKL-148t: when a property's RHS self-references the
        // same name but a sibling module-level function shares
        // it (`function qux(...) = ...` beside `qux = qux(...)`),
        // Apple Pkl resolves the RHS occurrence through the
        // function namespace first. Try the function-shaped
        // binding before surfacing the cycle diagnostic — only
        // when the currently-resolving binding is itself NOT a
        // function (otherwise the fallback would short-circuit
        // back to the same binding).
        let cyclic_is_function = match binding.value {
          LambdaExpr(_, _, _) => true
          _ => false
        }
        if !cyclic_is_function {
          match find_function_binding(bindings, name) {
            Some(fn_binding) =>
              return eval_expr_with_bindings(
                fn_binding.value,
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
        }
        diagnostics.push(diag("cyclic property reference \{name}"))
        None
      } else {
        // PKL-148bg: when the binding annotation names a user class
        // (`local base: TheClass2 = new { requiredLength = 5 }`),
        // rewrite a bare `new { ... }` (ObjectLiteral) to
        // `new TheClass2 { ... }` (TypedObjectLiteral) so the
        // class's `hidden` / default machinery runs. Without this
        // the unprefixed `requiredLength` would leak into the
        // rendered output (`listings/listing6` fixture). When the
        // annotation names an in-scope module-shaped value
        // (`res1: someModule = new { foo = "..." }`), promote the
        // RHS to `AmendExpr(Identifier(someModule), members)` so
        // the module's own defaults flow through.
        let collection_rewritten_value = inherited_module_object_amend_expr(
          binding.name,
          collection_literal_expr_for_type_annotation(
            binding.value,
            binding.type_name,
          ),
          binding.type_name,
          cache,
        )
        let rewritten_value : Expr = match
          (collection_rewritten_value, binding.type_name) {
          (ObjectLiteral(members), Some(class_name)) =>
            match lookup_class_binding(class_env, class_name) {
              Some(_) => TypedObjectLiteral(class_name, members)
              None =>
                if class_name.contains(".") ||
                  class_name.contains("<") ||
                  class_name.contains("(") ||
                  class_name.contains("?") {
                  collection_rewritten_value
                } else if class_name.contains("|") {
                  // PKL-148bh: union annotation (`*Foo | Baz`)
                  // — pick the starred branch and route through
                  // its class. Falls back to ObjectLiteral when
                  // no starred branch resolves to a user class.
                  let mut starred_class : String? = None
                  for choice in split_top_level_union_choices(class_name) {
                    let t = trim_spaces(choice)
                    if t.has_prefix("*") {
                      let head = trim_spaces(
                        String::unsafe_substring(t, start=1, end=t.length()),
                      )
                      if lookup_class_binding(class_env, head) is Some(_) {
                        starred_class = Some(head)
                        break
                      }
                    }
                  }
                  match starred_class {
                    Some(name) => TypedObjectLiteral(name, members)
                    None => collection_rewritten_value
                  }
                } else if lookup_value(env, class_name) is Some(ObjectValue(_)) ||
                  lookup_value(cache, class_name) is Some(ObjectValue(_)) ||
                  find_binding(bindings, class_name) is Some(_) {
                  AmendExpr(Identifier(class_name), members)
                } else {
                  collection_rewritten_value
                }
            }
          _ => collection_rewritten_value
        }
        match
          eval_expr_with_bindings(
            rewritten_value,
            bindings,
            env,
            class_env,
            cache,
            push_binding_stack(stack, name),
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(raw_value) => {
            let value = coerce_value_to_annotated_type(
              raw_value,
              binding.type_name,
            )
            let value = apply_collection_default_for_type(
              value,
              binding.type_name,
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            let typed_value = match binding.type_name {
              Some(annotation) =>
                match
                  cast_value_to_type_annotation(
                    annotation, value, bindings, env, class_env, cache, stack, declarations,
                    resolve_import,
                  ) {
                  TypeCastOk(casted) => casted
                  TypeCastErr(message) => {
                    diagnostics.push(diag(message))
                    return None
                  }
                }
              None => value
            }
            match
              binding_collection_host_constraint_rejection_message(
                binding.type_name,
                typed_value,
                declarations,
              ) {
              Some(message) => {
                diagnostics.push(diag(message))
                None
              }
              None => {
                cache.push({ name: binding.name, value: typed_value })
                Some(typed_value)
              }
            }
          }
          None => None
        }
      }
    None =>
      match lookup_value(cache, "super") {
        Some(ObjectValue(parent_members)) =>
          if is_module_member_set(parent_members) {
            resolve_module_parent_member_value(
              name, parent_members, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          } else {
            None
          }
        _ => None
      }
  }
}

///|
fn push_receiver_method_bindings(
  method_cache : Array[ValueBinding],
  receiver_members : Array[ValueMember],
) -> Unit {
  for value_member in receiver_members {
    method_cache.push({ name: value_member.name, value: value_member.value })
    // PKL-148e: hidden / local class properties are stored under their
    // visibility prefix. The method body references them by the bare
    // name (`c`, not `@hidden$c` / `@local$c`); push the stripped form
    // alongside the prefixed one so cache lookup resolves both.
    if is_invisible_member_name(value_member.name) {
      method_cache.push({
        name: strip_member_visibility_prefix(value_member.name),
        value: value_member.value,
      })
    }
  }
  method_cache.push({ name: "this", value: ObjectValue(receiver_members) })
}

///|
/// PKL-117: marker pushed onto `method_cache` so `super.method(...)`
/// can find the enclosing class. The marker key uses an `@` prefix
/// — the lexer treats `@` as its own token so the name can't
/// collide with a user-written Pkl identifier.
fn push_super_dispatch_marker(
  method_cache : Array[ValueBinding],
  current_class : String,
) -> Unit {
  method_cache.push({
    name: "@current_class",
    value: StringValue(current_class),
  })
}

///|
/// PKL-148e: expose sibling class methods to a method body. Apple Pkl
/// scopes class methods like locals — `function compute() = b(c)` can
/// call `function b(x) = ...` declared in the same class without
/// `this.b(c)`. Walk the parent chain so an override (or new method)
/// in a subclass shadows the parent definition, matching the
/// inheritance order. Already-bound names (parameters, properties) win
/// because they were pushed onto the cache earlier.
fn push_sibling_class_methods(
  method_cache : Array[ValueBinding],
  class_name : String,
  class_env : Array[ClassBinding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Unit {
  let captured_env = capture_value_bindings(env, cache)
  // Collect the inheritance chain bottom-up, then push parent → derived
  // so a derived class's method ends up *after* its parent's same-named
  // method in the cache. `lookup_value` returns the last match, so the
  // most-derived override wins (virtual dispatch).
  let chain : Array[ClassBinding] = []
  let mut current : String? = Some(class_name)
  let seen : Array[String] = []
  while current is Some(name) {
    if contains_string(seen, name) {
      break
    }
    seen.push(name)
    match lookup_class_binding(class_env, name) {
      Some(class_binding) => {
        chain.push(class_binding)
        current = class_binding.parent_name
      }
      None => current = None
    }
  }
  for i = chain.length() - 1; i >= 0; i = i - 1 {
    for class_method in chain[i].methods {
      match class_method.body {
        Some(body) =>
          method_cache.push({
            name: class_method.name,
            value: FunctionValue(
              class_method.parameters,
              body,
              class_method.return_type_name,
              captured_env,
              fresh_function_id(),
            ),
          })
        None => ()
      }
    }
  }
}

///|
/// Stable hidden-member key used to attach a class name to an
/// ObjectValue. Today this is only set for `new Dynamic { ... }`
/// expressions so diagnostic output can render `new Dynamic {}` and
/// `got type \`Dynamic\`` instead of the generic `Object` / `new {}`
/// form. The user-class tagging is deferred — broader adoption would
/// shift many downstream diagnostic surfaces in one go.
fn class_tag_member_name() -> String {
  hidden_member_name("__class")
}

///|
fn tag_object_with_class(
  members : Array[ValueMember],
  class_name : String,
) -> Array[ValueMember] {
  // PKL-148bh: tag every typed ObjectValue with the constructing
  // class name. The marker uses the hidden prefix so the renderer
  // and visible_members filter it out automatically; downstream
  // dispatch paths (`eval_value_type_name`, `render_pcf_value_inline`,
  // `is X` checks) read it via `find_object_class_tag`.
  let tag_name = class_tag_member_name()
  for m in members {
    if m.name == tag_name {
      return members
    }
  }
  let tagged : Array[ValueMember] = [
    {
      name: tag_name,
      value: StringValue(class_name),
      source: None,
      annotations: [],
    },
  ]
  for m in members {
    tagged.push(m)
  }
  tagged
}

///|
fn find_object_class_tag(members : Array[ValueMember]) -> String? {
  let tag_name = class_tag_member_name()
  for m in members {
    if m.name == tag_name {
      return match m.value {
        StringValue(s) => Some(s)
        _ => None
      }
    }
  }
  None
}

///|
fn renderer_format_for_class_name(class_name : String) -> String? {
  if class_name.has_suffix("PcfRenderer") {
    Some("pcf")
  } else if class_name.has_suffix("JsonRenderer") {
    Some("json")
  } else if class_name.has_suffix("YamlRenderer") {
    Some("yaml")
  } else if class_name.has_suffix("PropertiesRenderer") {
    Some("properties")
  } else if class_name.has_suffix("PListRenderer") {
    Some("plist")
  } else if class_name == "xml.Renderer" || class_name.has_suffix("XmlRenderer") {
    Some("xml")
  } else if class_name == "protobuf.Renderer" ||
    class_name.has_suffix("ProtobufRenderer") {
    Some("textproto")
  } else {
    None
  }
}

///|
fn renderer_format_from_members(members : Array[ValueMember]) -> String? {
  match find_object_class_tag(members) {
    Some(class_name) => renderer_format_for_class_name(class_name)
    None => None
  }
}

///|
fn object_class_tag_matches(
  members : Array[ValueMember],
  expected : String,
) -> Bool {
  match find_object_class_tag(members) {
    Some(class_name) => {
      let class_head = match class_name.find("<") {
        Some(idx) => String::unsafe_substring(class_name, start=0, end=idx)
        None => class_name
      }
      class_head == expected || class_head.has_suffix(".\{expected}")
    }
    None => false
  }
}

///|
fn render_directive_text(value : Value) -> String? {
  match value {
    ObjectValue(members) =>
      if object_class_tag_matches(members, "RenderDirective") {
        match lookup_member(members, "text") {
          Some(StringValue(text)) => Some(text)
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// PKL-148bh: like `eval_value_type_name`, but when the value's
/// class tag matches a user-declared class in scope, prefix the
/// surrounding module name (`<module>#<simple>`). Stdlib types
/// (`Int`, `String`, `Listing`, …) and the `Dynamic` tag keep their
/// bare form because Apple Pkl never qualifies them.
fn qualify_value_type_name(
  value : Value,
  class_env : Array[ClassBinding],
  module_name : String?,
) -> String {
  let bare = eval_value_type_name(value)
  match module_name {
    Some(m) =>
      if bare == "Dynamic" || bare == "Object" || is_stdlib_class_name(bare) {
        bare
      } else if lookup_class_binding(class_env, bare) is Some(_) {
        "\{m}#\{bare}"
      } else {
        bare
      }
    None => bare
  }
}

///|
fn eval_value_type_name(value : Value) -> String {
  match value {
    IntValue(_) => "Int"
    FloatValue(_) => "Float"
    BoolValue(_) => "Boolean"
    StringValue(_) => "String"
    NullValue => "Null"
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") => "Class"
        Some("TypeAlias") => "TypeAlias"
        Some("Module") => "ModuleClass"
        _ =>
          // PKL-148bh: universal tagging emits the class name verbatim
          // (`Dynamic` stays `Dynamic`; user classes surface as
          // `Person` etc.). The module-qualified form
          // `<module>#<simple>` lives on the cached
          // `@__module_name` marker — the diagnostic path that wants
          // the qualified shape stitches it in via
          // `eval_value_type_name_qualified` below.
          match find_object_class_tag(members) {
            Some("Module") => "ModuleClass"
            Some(class_name) => class_name
            None => "Object"
          }
      }
    ListingValue(_) | DefaultedListingValue(_, _, _) => "Listing"
    ListValue(_) => "List"
    MappingValue(_) | DefaultedMappingValue(_, _, _) => "Mapping"
    FunctionValue(_, _, _, _, _) => "Function"
    DurationValue(_, _) => "Duration"
    DataSizeValue(_, _) => "DataSize"
    RegexValue(_) => "Regex"
    BytesValue(_) => "Bytes"
    PairValue(_, _) => "Pair"
    IntSeqValue(_, _, _) => "IntSeq"
    SetValue(_) => "Set"
    MapValue(_) => "Map"
    DeferredImportValue(_) => "ModuleClass"
  }
}

///|
/// PKL-148: synthesize a `pkl:reflect.Class` mirror for any runtime
/// `Value`. snippetTest fixtures lean on `x.getClass().simpleName` to
/// pin a value's type at runtime — the mirror only needs `simpleName`
/// and `name` to satisfy the common usage. The `__kind` marker keeps
/// the value compatible with the existing reflect-introspection path.
fn synth_class_mirror_for_value(value : Value) -> Value {
  synth_class_mirror_for_name(eval_value_type_name(value))
}

///|
/// PKL-148bh: TypeAlias mirror with a module-qualified `name` /
/// toString. When `module_name` is Some, the mirror's `name` and the
/// toString-style projection use `<module>#<simple>` (matching
/// Apple Pkl's reflect output). When None, falls back to the bare
/// simple name.
fn synth_type_alias_mirror_for_qualified(
  name : String,
  module_name : String?,
) -> Value {
  let qualified = match module_name {
    Some(m) => "\{m}#\{name}"
    None => name
  }
  ObjectValue([
    {
      name: hidden_member_name("__kind"),
      value: StringValue("TypeAlias"),
      source: None,
      annotations: [],
    },
    {
      name: hidden_member_name("reflectee"),
      value: StringValue(name),
      source: None,
      annotations: [],
    },
    {
      name: "simpleName",
      value: StringValue(name),
      source: None,
      annotations: [],
    },
    {
      name: "name",
      value: StringValue(qualified),
      source: None,
      annotations: [],
    },
    {
      name: hidden_member_name("__qualified_name"),
      value: StringValue(qualified),
      source: None,
      annotations: [],
    },
    { name: "modifiers", value: SetValue([]), source: None, annotations: [] },
  ])
}

///|
fn synth_class_mirror_for_name(name : String) -> Value {
  synth_class_mirror_for_qualified(name, None)
}

///|
/// PKL-148bh: Class mirror with optional module qualifier. When
/// `module_name` is Some, the mirror's `name` field carries the
/// `<module>#<simple>` form Apple Pkl uses for reflect.Class.toString
/// on a user-declared class; stdlib class mirrors keep the bare
/// simpleName for now.
fn synth_class_mirror_for_qualified(
  name : String,
  module_name : String?,
) -> Value {
  let qualified = match module_name {
    Some(m) => "\{m}#\{name}"
    None => name
  }
  ObjectValue([
    {
      name: hidden_member_name("__kind"),
      value: StringValue("Class"),
      source: None,
      annotations: [],
    },
    {
      name: hidden_member_name("reflectee"),
      value: StringValue(name),
      source: None,
      annotations: [],
    },
    {
      name: "simpleName",
      value: StringValue(name),
      source: None,
      annotations: [],
    },
    {
      name: "name",
      value: StringValue(qualified),
      source: None,
      annotations: [],
    },
    {
      name: hidden_member_name("__qualified_name"),
      value: StringValue(qualified),
      source: None,
      annotations: [],
    },
    // PKL-148bb: reflect.Class / reflect.TypeAlias both expose a
    // `modifiers : Set<String>` slot (annotation / visibility keywords
    // declared on the type). pkl-mbt doesn't surface modifier text
    // through the AST yet, so default to an empty Set — `types/modifiersForTypes`
    // and other `.modifiers` consumers see the expected empty Set form.
    { name: "modifiers", value: SetValue([]), source: None, annotations: [] },
  ])
}

///|
/// PKL-148e: a stdlib type name (`Int` / `Float` / `String` / etc.)
/// is usable as a class-as-value just like a user-declared `class Foo`.
/// Apple Pkl exposes them through `pkl:base` so `Int == Int`,
/// `Int == 3.getClass()`, `Int != Float` round-trip via the Class
/// mirror's `name` / `simpleName` / `reflectee` fields.
fn is_stdlib_class_name(name : String) -> Bool {
  match name {
    "Int"
    | "Int8"
    | "Int16"
    | "Int32"
    | "UInt"
    | "UInt8"
    | "UInt16"
    | "UInt32"
    | "Float"
    | "Number"
    | "String"
    | "Boolean"
    | "Bool"
    | "Null"
    | "Bytes"
    | "Duration"
    | "DataSize"
    | "Regex"
    | "Listing"
    | "Mapping"
    | "Set"
    | "Map"
    | "List"
    | "Pair"
    | "IntSeq"
    | "Mixin"
    | "Dynamic"
    | "Typed"
    | "Object"
    | "Any"
    | "Class"
    | "Module"
    | "TypeAlias"
    | "Annotation"
    | "Resource"
    | "Function"
    | "Function0"
    | "Function1"
    | "Function2"
    | "Function3"
    | "Function4"
    | "Function5"
    | "BaseValueRenderer"
    | "ValueRenderer"
    | "PcfRenderer"
    | "JsonRenderer"
    | "YamlRenderer"
    | "PropertiesRenderer"
    | "PListRenderer"
    | "ConvertProperty"
    | "RenderDirective"
    // PKL-148bh: `module` is Apple Pkl's annotation for "the type of
    // the enclosing module" — treat as a stdlib-accepting class name
    // so the eval-side rejection path doesn't blanket-reject every
    // signature that mentions it (types/currentModuleType*).
    | "module"
    // PKL-148bh: `unknown` is Apple Pkl's "I don't care" type — same
    // posture as `Any` for runtime rejection. Used in
    // basic/newInAmendingModuleMethod's `function parrot(): unknown`.
    | "unknown" => true
    _ => false
  }
}

///|
/// PKL-152: stdlib classes that Apple Pkl forbids `new`-instantiating
/// or in-place amending. List / Set / Map / Pair / IntSeq are built
/// via constructor functions; the scalar / primitive classes (Int /
/// Float / Bool / String / Bytes / Duration / DataSize / Regex /
/// Function / Class / TypeAlias / Module / Annotation)
/// have literal or reflection-only construction surfaces. The
/// `new`-instantiable bases (Listing / Mapping / Dynamic / Object /
/// Typed) and the typing aliases (Number / Any / Null / module /
/// unknown plus the UInt* / Int* widths) are intentionally absent.
fn is_external_only_class_name(name : String) -> Bool {
  match name {
    "Int"
    | "Float"
    | "Number"
    | "String"
    | "Boolean"
    | "Bool"
    | "Null"
    | "Bytes"
    | "Duration"
    | "DataSize"
    | "Regex"
    | "Set"
    | "Map"
    | "List"
    | "Pair"
    | "IntSeq"
    | "Class"
    | "TypeAlias"
    | "Module"
    | "Annotation"
    | "Function"
    | "Function0"
    | "Function1"
    | "Function2"
    | "Function3"
    | "Function4"
    | "Function5" => true
    _ => false
  }
}

///|
/// PKL-152: Apple Pkl marks `ValueRenderer` (and a handful of other
/// base classes) as `abstract`; instantiating them via `new` raises
/// "Cannot instantiate abstract class `X`.". The stdlib doesn't get
/// parsed through our regular ClassDeclaration path, so the abstract
/// set is hard-coded here. User-declared abstract classes route
/// through `is_abstract_user_class_name` once class-modifier
/// extraction lands.
fn is_abstract_class_name(name : String) -> Bool {
  match name {
    "ValueRenderer" | "FileRenderer" | "Renderer" => true
    _ => false
  }
}
