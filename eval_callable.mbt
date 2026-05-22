///|
fn is_reflect_metadata_type_annotation(type_name : String) -> Bool {
  type_name == "reflect.Type" ||
  type_name == "reflect.Property" ||
  type_name == "reflect.Method"
}

///|
fn eval_value_accepts_type_annotation(
  type_name : String,
  value : Value,
) -> Bool {
  let type_name = pkl_strip_default_type_marker(type_name)
  match pkl_constrained_type_base_name(type_name) {
    Some(base_name) =>
      return eval_value_accepts_type_annotation(base_name, value)
    None => ()
  }
  // PKL-148at: top-level union — `Int|String` accepts a value when
  // ANY choice does. The split walker honours angle / paren / bracket
  // nesting so `Map<String, Int>` inside a union doesn't trip on
  // its inner `,`. Single-choice strings fall through to the regular
  // match below.
  let choices = split_top_level_union_choices(type_name)
  if choices.length() > 1 {
    for choice in choices {
      let trimmed = pkl_constraint_trim(choice)
      if eval_value_accepts_type_annotation(trimmed, value) {
        return true
      }
    }
    return false
  }
  if type_name.has_suffix("?") {
    if value is NullValue {
      return true
    }
    let inner_name = String::unsafe_substring(
      type_name,
      start=0,
      end=type_name.length() - 1,
    )
    return eval_value_accepts_type_annotation(inner_name, value)
  }
  // PKL-148at: `Listing<Int>` / `Map<String, Int>` / `Set<UInt32>` etc.
  // are shape-preserving cast targets — the outer head determines
  // runtime acceptance; the type parameters are validated lazily
  // when individual elements are read. Strip the `<...>` tail here
  // and recurse on the bare head so `Set(...) as Set<Listing<Int>>`
  // routes through the generic-free arm match.
  match type_name.find("<") {
    Some(idx) =>
      if type_name.has_suffix(">") {
        let head = String::unsafe_substring(type_name, start=0, end=idx)
        return eval_value_accepts_type_annotation(head, value)
      }
    None => ()
  }
  // PKL-148at: function-type literal (`(Int) -> Int`, `(A, B) -> C`).
  // Apple Pkl's `as` accepts any FunctionValue whose arity matches
  // the parameter count; the parameter / return types are validated
  // lazily at call time. Detect `(...) -> ...` shape and check arity
  // by counting top-level commas in the parameter group.
  if type_name.has_prefix("(") {
    let close_opt = type_name.find(")")
    if close_opt is Some(close) {
      let arrow_ok = close + 2 < type_name.length() &&
        String::unsafe_substring(type_name, start=close + 1, end=close + 3) ==
        "->"
      if arrow_ok {
        let params_text = String::unsafe_substring(
          type_name,
          start=1,
          end=close,
        )
        let trimmed = pkl_constraint_trim(params_text)
        let arity = if trimmed == "" {
          0
        } else {
          let mut commas = 0
          let mut depth = 0
          for i = 0; i < params_text.length(); i = i + 1 {
            let c = params_text[i].to_int().unsafe_to_char()
            if c == '(' || c == '<' || c == '[' {
              depth = depth + 1
            } else if c == ')' || c == '>' || c == ']' {
              depth = depth - 1
            } else if c == ',' && depth == 0 {
              commas = commas + 1
            }
          }
          commas + 1
        }
        return value is FunctionValue(parameters, _, _, _, _) &&
          parameters.length() == arity
      }
    }
  }
  // PKL-148ai: string-literal type annotation (`x: "Pigeon"`,
  // `List<Null|Boolean|"Pigeon">`). The Pkl surface lets a quoted
  // string stand in as a singleton type whose only inhabitant is the
  // literal value itself. Match a StringValue against the unquoted
  // payload; non-string runtimes never satisfy it.
  if type_name.length() >= 2 &&
    type_name.has_prefix("\"") &&
    type_name.has_suffix("\"") {
    let literal = String::unsafe_substring(
      type_name,
      start=1,
      end=type_name.length() - 1,
    )
    return value is StringValue(s) && s == literal
  }
  if type_name == "BaseValueRenderer" || type_name == "ValueRenderer" {
    return match value {
      ObjectValue(members) => renderer_format_from_members(members) is Some(_)
      _ => false
    }
  }
  if renderer_format_for_class_name(type_name) is Some(_) {
    return match value {
      ObjectValue(members) => object_class_tag_matches(members, type_name)
      _ => false
    }
  }
  if type_name == "RenderDirective" {
    return match value {
      ObjectValue(members) =>
        object_class_tag_matches(members, "RenderDirective")
      _ => false
    }
  }
  if is_reflect_metadata_type_annotation(type_name) {
    return value is ObjectValue(_)
  }
  match (type_name, value) {
    // PKL-148e: `Any` is Apple Pkl's top type — it accepts every
    // runtime value, matching `eval_value_accepts_type_annotation`'s
    // top-level surface.
    ("Any", _) => true
    ("Int", IntValue(_)) => true
    ("Float", FloatValue(_)) => true
    // PKL-092: `Number` is the type-system union of Int and Float; both
    // pass the annotation. Float-only contexts use the `Float` name.
    ("Number", IntValue(_)) | ("Number", FloatValue(_)) => true
    ("String", StringValue(_)) => true
    ("Boolean", BoolValue(_)) | ("Bool", BoolValue(_)) => true
    ("Null", NullValue) => true
    ("Object", ObjectValue(_)) => true
    // PKL-148bh: `module` is the type of the enclosing module — any
    // ObjectValue satisfies it structurally (types/currentModuleType*).
    ("module", ObjectValue(_)) => true
    // PKL-148bh: `unknown` is Apple Pkl's wildcard return type;
    // accept every runtime value (basic/newInAmendingModuleMethod).
    ("unknown", _) => true
    ("Listing", ListingValue(_))
    | ("Listing", DefaultedListingValue(_, _, _)) => true
    ("Mapping", MappingValue(_))
    | ("Mapping", DefaultedMappingValue(_, _, _)) => true
    // PKL-148h: `List<T>` accepts the dedicated `ListValue`; the older
    // path accepting `ListingValue` is kept as a transitional aid for
    // codepaths that still produce `ListingValue` for list-shaped input
    // (e.g. `pkl:json.Parser` arrays). Apple Pkl's `Collection` is the
    // join of List + Set, so all three list-shaped variants satisfy it.
    // `Map` accepts both `MapValue` and `MappingValue` for the same
    // reason; the split slice for Mapping is separate.
    ("List", ListValue(_))
    | ("List", ListingValue(_))
    | ("List", DefaultedListingValue(_, _, _)) => true
    ("Collection", ListValue(_))
    | ("Collection", ListingValue(_))
    | ("Collection", DefaultedListingValue(_, _, _))
    | ("Collection", SetValue(_)) => true
    ("Map", MapValue(_))
    | ("Map", MappingValue(_))
    | ("Map", DefaultedMappingValue(_, _, _)) => true
    ("Set", SetValue(_))
    | ("Set", ListingValue(_))
    | ("Set", DefaultedListingValue(_, _, _))
    | ("Set", ListValue(_)) => true
    ("Pair", PairValue(_, _)) => true
    ("IntSeq", IntSeqValue(_, _, _)) => true
    ("Mixin", ObjectValue(members)) =>
      object_class_tag_matches(members, "Mixin") ||
      object_members_are_mixin_body(members)
    ("Function", FunctionValue(_, _, _, _, _)) => true
    ("Duration", DurationValue(_, _)) => true
    ("DataSize", DataSizeValue(_, _)) => true
    ("Regex", RegexValue(_)) => true
    ("Bytes", BytesValue(_)) => true
    _ => false
  }
}

///|
fn eval_type_name_is_type_parameter(
  type_name : String,
  declarations : Array[Declaration],
) -> Bool {
  // PKL-089 / PKL-090: a function or class type parameter is an
  // arbitrary user-chosen identifier (T, U, K, V, MyParam) bound at the
  // declaration site. The evaluator treats it as 'accept any value' —
  // call-site inference is deferred, so neither runtime parameter
  // validation nor return-value validation should reject based on the
  // parameter name. Class type parameters check covers methods on a
  // generic class; function parameters cover top-level generic
  // functions.
  for declaration in declarations {
    match declaration {
      FunctionDeclaration(fd) =>
        for parameter in fd.type_parameters {
          if parameter == type_name {
            return true
          }
        }
      ClassDeclaration(cd) =>
        for parameter in cd.type_parameters {
          if parameter == type_name {
            return true
          }
        }
      TypeAliasDeclaration(_) => ()
    }
  }
  false
}

///|
/// PKL-148ag: true iff every choice in the union-resolved form of
/// `type_name` fails to resolve to a stdlib class, user class,
/// typealias, or in-scope type parameter. The check feeds the
/// callable parameter / return rejection paths so an unknown type
/// annotation surfaces `Cannot find type \`<name>\`.` (Apple Pkl's
/// upstream wording) instead of the mismatched-value message that
/// otherwise pretends the annotation is meaningful.
fn eval_type_name_is_unresolvable(
  type_name : String,
  declarations : Array[Declaration],
) -> Bool {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(type_name, aliases)
  for choice in split_top_level_union_choices(resolved) {
    let trimmed = pkl_constraint_trim(choice)
    let without_constraint = match pkl_constrained_type_base_name(trimmed) {
      Some(base) => base
      None => trimmed
    }
    let head = match without_constraint.find("<") {
      Some(idx) =>
        String::unsafe_substring(without_constraint, start=0, end=idx)
      None => without_constraint
    }
    let head_no_optional = if head.has_suffix("?") {
      String::unsafe_substring(head, start=0, end=head.length() - 1)
    } else {
      head
    }
    if head_no_optional == "" ||
      head_no_optional.has_prefix("\"") ||
      is_stdlib_class_name(head_no_optional) ||
      is_reflect_metadata_type_annotation(head_no_optional) ||
      eval_lookup_class_decl(declarations, head_no_optional) is Some(_) ||
      eval_type_name_is_type_parameter(head_no_optional, declarations) {
      return false
    }
  }
  true
}

///|
/// PKL-148l: a callable's parameter declared with a basic type
/// annotation (`a: Int`, `b: Number`, `s: String`, etc.) must reject
/// arguments whose runtime type does not satisfy the annotation
/// before the body runs. Apple Pkl emits the bare diagnostic
/// (`Expected value of type \`Int\`, but got type \`Float\`. Value: 1.1`)
/// with no `label argument N` prefix, so this helper mirrors the
/// return-side wording.
fn eval_callable_argument_type_rejection_message(
  type_name : String?,
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
) -> String? {
  match type_name {
    Some(source) => {
      if eval_type_name_is_type_parameter(source, declarations) {
        return None
      }
      let aliases = eval_type_alias_bindings(declarations)
      let resolved = eval_resolved_type_alias(source, aliases)
      // PKL-148t: alias resolution may produce a union shape
      // (`Union` → `Int|Boolean`) or a generic head
      // (`Parameterized` → `List<String>`). Walk every choice in the
      // top-level union split, stripping each choice's `(...)`
      // constraint and outermost `<...>` generic head — accept if
      // any choice matches via the builtin acceptance set or the
      // user-class annotation cascade.
      let union_accepted = {
        let mut matched = false
        for choice in split_top_level_union_choices(resolved) {
          let trimmed = pkl_constraint_trim(choice)
          let without_constraint = match
            pkl_constrained_type_base_name(trimmed) {
            Some(base) => base
            None => trimmed
          }
          let head_for_check = match without_constraint.find("<") {
            Some(idx) =>
              String::unsafe_substring(without_constraint, start=0, end=idx)
            None => without_constraint
          }
          if eval_value_accepts_type_annotation(head_for_check, value) ||
            value_satisfies_user_class_annotation(
              head_for_check, value, declarations,
            ) {
            matched = true
            break
          }
        }
        matched
      }
      if union_accepted {
        // PKL-148af: head-level acceptance still needs to walk a
        // `List<X>` / `Listing<X>` / `Set<X>` / `Map<K, V>` /
        // `Mapping<K, V>` value's elements against the inner type so
        // `f3(List("foo", 42))` against `x: List<String>` rejects the
        // `42` element with the same `"Expected value of type \`X\`,
        // but got type \`Y\`. Value: <v>"` wording. Strip the outer
        // constraint and recurse into the cascade per element / entry;
        // the first violation surfaces and the rest are silenced
        // (matches Apple Pkl's fail-fast diag ordering).
        let resolved_base = match pkl_constrained_type_base_name(resolved) {
          Some(b) => b
          None => resolved
        }
        let listing_or_list_or_set = match
          generic_argument_text(resolved_base, "Listing") {
          Some(t) => Some(t)
          None =>
            match generic_argument_text(resolved_base, "List") {
              Some(t) => Some(t)
              None => generic_argument_text(resolved_base, "Set")
            }
        }
        match listing_or_list_or_set {
          Some(element_type) =>
            match value {
              ListingValue(elements)
              | DefaultedListingValue(_, elements, _)
              | ListValue(elements)
              | SetValue(elements) =>
                for element in elements {
                  match
                    eval_callable_argument_type_rejection_message(
                      Some(element_type),
                      element,
                      class_env,
                      cache,
                      declarations,
                    ) {
                    Some(message) => return Some(message)
                    None => ()
                  }
                }
              _ => ()
            }
          None => ()
        }
        let mapping_or_map = match
          generic_argument_text(resolved_base, "Mapping") {
          Some(t) => Some(t)
          None => generic_argument_text(resolved_base, "Map")
        }
        match mapping_or_map {
          Some(inner_text) => {
            let parts = split_top_level_generic_arguments(inner_text)
            if parts.length() == 2 {
              let key_type = parts[0]
              let value_type = parts[1]
              match value {
                MappingValue(entries)
                | DefaultedMappingValue(_, entries, _)
                | MapValue(entries) =>
                  for entry in entries {
                    match
                      eval_callable_argument_type_rejection_message(
                        Some(key_type),
                        entry.key,
                        class_env,
                        cache,
                        declarations,
                      ) {
                      Some(message) => return Some(message)
                      None => ()
                    }
                    match
                      eval_callable_argument_type_rejection_message(
                        Some(value_type),
                        entry.value,
                        class_env,
                        cache,
                        declarations,
                      ) {
                      Some(message) => return Some(message)
                      None => ()
                    }
                  }
                _ => ()
              }
            }
          }
          None => ()
        }
        return None
      }
      // PKL-148ag: when the annotation itself doesn't name a known
      // type (no stdlib class, user class, typealias, or in-scope
      // type parameter resolves), Apple Pkl surfaces
      // `Cannot find type \`<name>\`.` — not the mismatched-value
      // wording. Run the resolvability gate before crafting the
      // value-mismatch message.
      if eval_type_name_is_unresolvable(source, declarations) {
        return Some("Cannot find type `\{source}`.")
      }
      // PKL-148u: Apple Pkl quotes the RESOLVED type name in the
      // rejection diagnostic (not the source alias name). Strip a
      // trailing `?` so `Nullable = Duration?` shows as `Duration`.
      let diag_name = qualified_rejection_type_label(resolved, class_env, cache)
      if value is NullValue {
        return Some("Expected value of type `\{diag_name}`, but got `null`.")
      }
      let actual = qualify_value_type_name(
        value,
        class_env,
        module_name_from_cache(cache),
      )
      Some(
        "Expected value of type `\{diag_name}`, but got type `\{actual}`. Value: \{render_pcf_value_inline(value)}",
      )
    }
    None => None
  }
}

///|
fn module_name_from_cache(cache : Array[ValueBinding]) -> String? {
  match lookup_value(cache, "@__module_name") {
    Some(StringValue(module_name)) =>
      if module_name.length() == 0 {
        None
      } else {
        Some(module_name)
      }
    _ => None
  }
}

///|
fn push_module_metadata_from_cache(
  call_cache : Array[ValueBinding],
  caller_cache : Array[ValueBinding],
) -> Unit {
  for
    name in [
      "@__module_name", "@__module_path", "@__module_source", "@__module_imports",
    ] {
    if lookup_value(call_cache, name) is None {
      match lookup_value(caller_cache, name) {
        Some(v) => call_cache.push({ name, value: v })
        None => ()
      }
    }
  }
}

///|
fn push_class_default_scope_from_cache(
  call_cache : Array[ValueBinding],
  caller_cache : Array[ValueBinding],
) -> Unit {
  if lookup_value(call_cache, "@__class_default_call_scope") is Some(_) {
    return
  }
  let marker = match lookup_value(caller_cache, "@__class_default_scope") {
    Some(value) => Some(value)
    None => lookup_value(caller_cache, "@__class_default_call_scope")
  }
  match marker {
    Some(value) =>
      call_cache.push({ name: "@__class_default_call_scope", value })
    None => ()
  }
}

///|
fn push_class_default_call_name(
  call_cache : Array[ValueBinding],
  label : String,
) -> Unit {
  if lookup_value(call_cache, "@__class_default_call_scope") is None {
    return
  }
  if lookup_value(call_cache, "@__class_default_call_name") is Some(_) {
    return
  }
  if label.has_prefix("function ") {
    call_cache.push({
      name: "@__class_default_call_name",
      value: StringValue(
        String::unsafe_substring(
          label,
          start="function ".length(),
          end=label.length(),
        ),
      ),
    })
  }
}

///|
fn qualified_rejection_type_label(
  type_name : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> String {
  let label = rejection_type_label(type_name)
  match module_name_from_cache(cache) {
    Some(module_name) =>
      if is_stdlib_class_name(label) ||
        lookup_class_binding(class_env, label) is None {
        label
      } else {
        "\{module_name}#\{label}"
      }
    None => label
  }
}

///|
fn eval_callable_argument_rejection_message(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  // Mirror the return-side alias resolution: a parameter declared
  // `x: Small` with `typealias Small = Int(isBetween(0, 10))` must trigger
  // the same predicate cascade as `x: Int(isBetween(0, 10))`. The
  // `_from_source` predicate variants keep the original alias name in the
  // diagnostic while running the resolved constraint against the value.
  match type_name {
    Some(source) => {
      if eval_type_name_is_type_parameter(source, declarations) {
        return None
      }
      let aliases = eval_type_alias_bindings(declarations)
      let resolved = eval_resolved_type_alias(source, aliases)
      match
        pkl_constrained_type_annotation_value_rejection_message_from_source(
          source, resolved, value,
        ) {
        Some(message) => Some(message)
        None =>
          pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
            source, resolved, value, declarations,
          )
      }
    }
    None => None
  }
}

///|
priv enum CallableCollectionAnnotationCast {
  CallableCollectionCastSkipped
  CallableCollectionCastOk(Value)
  CallableCollectionCastErr(String)
}

///|
fn cast_callable_collection_annotation(
  type_name : String?,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> CallableCollectionAnnotationCast {
  let annotation = match type_name {
    Some(name) => name
    None => return CallableCollectionCastSkipped
  }
  if type_annotation_collection_branch_count(annotation, declarations) == 0 {
    return CallableCollectionCastSkipped
  }
  match
    cast_value_to_type_annotation(
      annotation, value, bindings, env, class_env, cache, stack, declarations, resolve_import,
    ) {
    TypeCastOk(casted) =>
      match
        binding_collection_host_constraint_rejection_message(
          Some(annotation),
          casted,
          declarations,
        ) {
        Some(message) => CallableCollectionCastErr(message)
        None => CallableCollectionCastOk(casted)
      }
    TypeCastErr(message) => CallableCollectionCastErr(message)
  }
}

///|

///|
/// PKL-148bh: runtime predicate check for a callable parameter
/// annotation that carries a `(<expr>)` constraint
/// (e.g. `String(length > n)` where `n` lives in the captured env).
/// Mirrors the eval_runtime_constraint_for_property cascade but uses
/// the function's captured_env as the lexical scope and binds `this`
/// to the actual argument. Returns Apple Pkl's standard violation
/// wording when the predicate evaluates to `false`; returns `None`
/// when the predicate matches or the annotation has no constraint /
/// fails to parse.
fn eval_callable_runtime_constraint_message(
  type_name : String?,
  value : Value,
  bindings : Array[Binding],
  class_env : Array[ClassBinding],
  captured_env : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  let source = match type_name {
    Some(s) => s
    None => return None
  }
  let text = match pkl_constrained_type_constraint_text(source) {
    Some(t) => t
    None => return None
  }
  let parts = pkl_split_constraint_arguments(text)
  for part in parts {
    let expr = match parse_constraint_expression(part) {
      Some(e) => e
      None => continue
    }
    let pred_env : Array[ValueBinding] = []
    for b in captured_env {
      pred_env.push(b)
    }
    pred_env.push({ name: "this", value })
    // Implicit-receiver bareword resolution: when the value is an
    // ObjectValue, hoist its visible members so `length` / `name`
    // etc. resolve directly. Scalar values rely on
    // rewrite_implicit_this_in_expr to fold bare names that miss
    // both env and bindings into `this.<name>` member accesses.
    match value {
      ObjectValue(members) =>
        for m in members {
          if !is_invisible_member_name(m.name) {
            pred_env.push({ name: m.name, value: m.value })
          }
        }
      _ => ()
    }
    let rewritten = rewrite_implicit_this_in_expr(
      expr, bindings, pred_env, captured_env,
    )
    let probe_diags : Array[Diagnostic] = []
    let probe = eval_expr_with_bindings(
      rewritten, bindings, pred_env, class_env, captured_env, stack, declarations,
      probe_diags, resolve_import,
    )
    match probe {
      Some(BoolValue(true)) => continue
      Some(BoolValue(false)) => {
        let hint = match pkl_constrained_type_base_name(source) {
          Some(base) =>
            if base == "Int" ||
              base == "Float" ||
              base == "Number" ||
              base == "Boolean" ||
              base == "String" ||
              base == "Listing" ||
              base == "Mapping" ||
              base == "Set" ||
              base == "Map" ||
              base.has_prefix("Listing<") ||
              base.has_prefix("Mapping<") ||
              base.has_prefix("Set<") ||
              base.has_prefix("Map<") {
              None
            } else {
              Some(base)
            }
          None => None
        }
        return Some(
          "Type constraint `\{pretty_constraint_text(part)}` violated. Value: \{render_pcf_value_inline_compact(value, hint)}",
        )
      }
      _ => continue
    }
  }
  None
}

///|
/// PKL-148: render a value through the inline PCF form so diagnostic
/// messages can quote the rejected value. The wrapper keeps the call
/// sites concise — the `Value: <text>` segment is a recurring shape
/// in Apple Pkl's constraint / type-mismatch wording.
fn render_pcf_value_inline(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) =>
      // PKL-148bh: every typed ObjectValue now carries the
      // `@hidden$__class` tag (universal tagging in
      // `tag_object_with_class`), so the inline form prints
      // `new <Class> { ... }` for both Dynamic and user classes
      // (lambdas/pipeOperator's diagnostic for `Person`).
      match find_object_class_tag(members) {
        Some(class_name) => render_pcf_class_inline(class_name, members, buf)
        None => render_pcf_inline(value, 0, false, buf)
      }
    _ => render_pcf_inline(value, 0, false, buf)
  }
  buf.to_string()
}

///|
/// Render an ObjectValue with an attached class tag in the inline-quote
/// form Apple Pkl uses inside diagnostic strings — `new Dynamic {}` /
/// `new Dynamic { x = 1 }`. Visible members only; the class tag itself
/// stays hidden.
fn render_pcf_class_inline(
  class_name : String,
  members : Array[ValueMember],
  buf : StringBuilder,
) -> Unit {
  buf.write_string("new ")
  buf.write_string(class_name)
  let visible = visible_members(members)
  if visible.length() == 0 {
    buf.write_string(" {}")
    return
  }
  buf.write_string(" { ")
  for i = 0; i < visible.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string(visible[i].name)
    buf.write_string(" = ")
    render_pcf_scalar(visible[i].value, buf)
  }
  buf.write_string(" }")
}

///|
/// PKL-148d: compact single-line render used by constraint diagnostics
/// (`Type constraint \`X\` violated. Value: <text>`). Apple Pkl renders
/// the offending ObjectValue as `new ClassName { x = "..." }` on one
/// line, with the class name pulled from the host constraint target.
/// Listing / Mapping fall back to `new Listing {}` / `new Mapping {}`
/// for empty cases so the existing PKL-148b output stays stable; the
/// non-empty inline form mirrors `render_pcf_inline` but on a single
/// line.
fn render_pcf_value_inline_compact(
  value : Value,
  class_hint : String?,
) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => {
      buf.write_string("new ")
      match class_hint {
        Some(name) => {
          buf.write_string(name)
          buf.write_char(' ')
        }
        None => ()
      }
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string("{}")
      } else {
        buf.write_string("{ ")
        for i = 0; i < visible.length(); i = i + 1 {
          if i > 0 {
            buf.write_string("; ")
          }
          buf.write_string(visible[i].name)
          buf.write_string(" = ")
          render_pcf_scalar(visible[i].value, buf)
        }
        buf.write_string(" }")
      }
    }
    _ => render_pcf_inline(value, 0, false, buf)
  }
  buf.to_string()
}

///|
/// PKL-148e: looser check that accepts ObjectValue for any
/// user-declared class name (and the stdlib `Dynamic` / `Typed`
/// supertypes). Apple Pkl's runtime carries the dynamic class along
/// with the instance; pkl-mbt's ObjectValue erases it. Until we
/// recover the class on the value, accept any ObjectValue against a
/// declared class type — the alternative (rejecting every
/// `param: Person` call site) is strictly worse for upstream
/// compatibility.
fn value_satisfies_user_class_annotation(
  type_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> Bool {
  match value {
    ObjectValue(members) => {
      if reflect_kind(members) is Some(_) {
        return false
      }
      if type_name == "Dynamic" || type_name == "Typed" {
        return true
      }
      let base = match pkl_constrained_type_base_name(type_name) {
        Some(b) => b
        None => type_name
      }
      match find_object_class_tag(members) {
        Some(tag) =>
          if tag == base {
            return true
          } else {
            let mut current : ClassDecl? = eval_lookup_class_decl(
              declarations, tag,
            )
            while current is Some(decl) {
              match decl.parent_name {
                Some(parent) =>
                  if parent == base {
                    return true
                  } else {
                    current = eval_lookup_class_decl(declarations, parent)
                  }
                None => current = None
              }
            }
            return false
          }
        None => ()
      }
      eval_lookup_class_decl(declarations, base) is Some(_)
    }
    _ => false
  }
}

///|
fn eval_callable_return_rejection_message(
  label : String,
  return_type_name : String?,
  value : Value,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
) -> String? {
  match return_type_name {
    Some(type_name) => {
      if eval_type_name_is_type_parameter(type_name, declarations) {
        return None
      }
      let aliases = eval_type_alias_bindings(declarations)
      let resolved_type_name = eval_resolved_type_alias(type_name, aliases)
      // PKL-148t: alias resolution may produce a generic
      // (`Parameterized` → `List<String>`) or a union
      // (`Union` → `Int|Boolean`); the value-side acceptance only
      // matches on a bare head, so split the resolved name on
      // top-level `|`, strip each choice's `(...)` constraint and
      // outermost `<...>` generic head, and accept if any choice
      // matches. Mirrors PKL-148l's callable-parameter normalisation
      // (which the parameter side already runs via
      // `eval_callable_argument_type_rejection_message`).
      let union_accepted = {
        let mut matched = false
        for choice in split_top_level_union_choices(resolved_type_name) {
          let trimmed = pkl_constraint_trim(choice)
          let without_constraint = match
            pkl_constrained_type_base_name(trimmed) {
            Some(base) => base
            None => trimmed
          }
          let head_for_check = match without_constraint.find("<") {
            Some(idx) =>
              String::unsafe_substring(without_constraint, start=0, end=idx)
            None => without_constraint
          }
          if eval_value_accepts_type_annotation(head_for_check, value) ||
            value_satisfies_user_class_annotation(
              head_for_check, value, declarations,
            ) {
            matched = true
            break
          }
        }
        matched
      }
      if !union_accepted {
        // PKL-148ag: unresolvable annotation → `Cannot find type`
        // rather than the value-mismatch wording. Mirrors the
        // parameter-side gate.
        if eval_type_name_is_unresolvable(type_name, declarations) {
          return Some("Cannot find type `\{type_name}`.")
        }
        // PKL-148: align with Apple Pkl's diagnostic wording so
        // snippetTest fixtures that capture this exact string via
        // `test.catch(...)` match byte-for-byte. The trailing
        // `Value: <pcf>` segment mirrors upstream — it renders the
        // failing value with the standard PCF inline form so the
        // user sees what was rejected.
        let diag_name = qualified_rejection_type_label(
          type_name, class_env, cache,
        )
        if value is NullValue {
          return Some("Expected value of type `\{diag_name}`, but got `null`.")
        }
        let actual = qualify_value_type_name(
          value,
          class_env,
          module_name_from_cache(cache),
        )
        Some(
          "Expected value of type `\{diag_name}`, but got type `\{actual}`. Value: \{render_pcf_value_inline(value)}",
        )
      } else {
        // PKL-148ae: Apple Pkl's return-side constraint diagnostic
        // omits the call-site label (`method <name> return ...`) —
        // it matches the parameter side already dropped by PKL-148o.
        // `label` is preserved at the signature so callers can still
        // carry the call-site identity for non-constraint diagnostics
        // (`<label> expects <n> arguments, got <m>`).
        let _ = label
        match
          pkl_constrained_type_annotation_value_rejection_message_from_source(
            type_name, resolved_type_name, value,
          ) {
          Some(message) => Some(message)
          None =>
            match
              pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
                type_name, resolved_type_name, value, declarations,
              ) {
              Some(message) => Some(message)
              None => None
            }
        }
      }
    }
    None => None
  }
}

///|
fn eval_callable_return_value(
  label : String,
  return_type_name : String?,
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let clean_return_type_name = strip_lazy_collection_annotation_marker_opt(
    return_type_name,
  )
  let mut return_value = value
  let mut overlaid = false
  match
    cast_callable_collection_annotation(
      clean_return_type_name, return_value, bindings, env, class_env, cache, stack,
      declarations, resolve_import,
    ) {
    CallableCollectionCastOk(casted) => {
      return_value = casted
      overlaid = true
    }
    CallableCollectionCastErr(message) => {
      diagnostics.push(diag(message))
      return None
    }
    CallableCollectionCastSkipped => {
      let (overlay_value, overlay_ok) = overlay_collection_annotation_if_possible(
        return_type_name, return_value, bindings, env, class_env, cache, stack, declarations,
        resolve_import,
      )
      return_value = overlay_value
      overlaid = overlay_ok
    }
  }
  if overlaid {
    return Some(return_value)
  }
  match
    eval_callable_return_rejection_message(
      label, clean_return_type_name, return_value, class_env, cache, declarations,
    ) {
    Some(message) => {
      diagnostics.push(diag(message))
      None
    }
    None => Some(return_value)
  }
}

///|
fn eval_lambda_application(
  label : String,
  parameters : Array[FunctionParameter],
  body : Expr,
  return_type_name : String?,
  captured_env : Array[ValueBinding],
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
  if parameters.length() != arguments.length() {
    diagnostics.push(
      diag(
        "\{label} expects \{parameters.length()} arguments, got \{arguments.length()}",
      ),
    )
    return None
  }
  let argument_values : Array[Value] = []
  let mut arguments_ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(value) => argument_values.push(value)
      None => arguments_ok = false
    }
  }
  if !arguments_ok {
    return None
  }
  let call_cache = copy_value_bindings(captured_env)
  push_module_metadata_from_cache(call_cache, cache)
  push_class_default_scope_from_cache(call_cache, cache)
  push_class_default_call_name(call_cache, label)
  for i = 0; i < parameters.length(); i = i + 1 {
    let parameter_type_name = strip_lazy_collection_annotation_marker_opt(
      parameters[i].type_name,
    )
    let mut argument_value = argument_values[i]
    let mut overlaid = false
    match
      cast_callable_collection_annotation(
        parameter_type_name, argument_value, bindings, call_cache, class_env, call_cache,
        stack, declarations, resolve_import,
      ) {
      CallableCollectionCastOk(casted) => {
        argument_value = casted
        overlaid = true
      }
      CallableCollectionCastErr(message) => {
        diagnostics.push(diag(message))
        return None
      }
      CallableCollectionCastSkipped => {
        let (overlay_value, overlay_ok) = overlay_collection_annotation_if_possible(
          parameters[i].type_name,
          argument_value,
          bindings,
          call_cache,
          class_env,
          call_cache,
          stack,
          declarations,
          resolve_import,
        )
        argument_value = overlay_value
        overlaid = overlay_ok
      }
    }
    if !overlaid {
      match
        eval_callable_argument_type_rejection_message(
          parameter_type_name, argument_value, class_env, call_cache, declarations,
        ) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      match
        eval_callable_argument_rejection_message(
          parameter_type_name, argument_value, declarations,
        ) {
        Some(message) => {
          // PKL-148o: Apple Pkl emits the bare constraint message
          // (`Type constraint `isPositive` violated. Value: -1`) for
          // callable-parameter constraint failures — no `<label>
          // argument N` prefix. Drop the wrapper across all three
          // call sites (this lambda application, `apply_function_value`,
          // and the class-method dispatch in `eval_member_access_call`)
          // so `test.catch(() -> f(-1))` round-trips the upstream
          // wording byte-for-byte. `label` is preserved here in case a
          // future diagnostic needs the caller's identity, but isn't
          // included in the user-facing message.
          let _ = label
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      // PKL-148bh: runtime predicate check using the captured env —
      // see `apply_function_value` for the rationale. Hooks the same
      // diagnostic format Apple Pkl prints for `String(length > n)`-
      // style parameter constraints (lambdas/typedLambdas).
      match
        eval_callable_runtime_constraint_message(
          parameter_type_name, argument_value, bindings, class_env, captured_env,
          stack, declarations, resolve_import,
        ) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
    }
    call_cache.push({ name: parameters[i].name, value: argument_value })
  }
  match body {
    LambdaExpr(lambda_parameters, lambda_body, lambda_return_type_name) =>
      eval_callable_return_value(
        label,
        return_type_name,
        FunctionValue(
          lambda_parameters,
          lambda_body,
          lambda_return_type_name,
          copy_value_bindings(call_cache),
          fresh_function_id(),
        ),
        bindings,
        call_cache,
        class_env,
        call_cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      )
    _ => {
      // PKL-148d: same lexical-isolation as `apply_function_value`.
      // The lambda body must not see the caller's env (which may
      // shadow a parameter, e.g. `import "pkl:semver" as s` colliding
      // with the lambda parameter `s`). captured_env + parameters
      // already live in `call_cache`.
      let body_env : Array[ValueBinding] = []
      // PKL-148bh: see `apply_function_value` — when a user-class
      // return type wraps a bare `new { ... }` body, treat as
      // `new T { ... }` so `getClass()` and class defaults flow.
      let body_to_eval : Expr = match (body, return_type_name) {
        (ObjectLiteral(members), Some(class_name)) =>
          if class_name.contains("<") ||
            class_name.contains("|") ||
            class_name.contains("(") ||
            class_name.contains("?") ||
            class_name.contains(".") {
            body
          } else {
            match lookup_class_binding(class_env, class_name) {
              Some(_) => TypedObjectLiteral(class_name, members)
              None => body
            }
          }
        _ => body
      }
      match
        eval_expr_with_bindings(
          body_to_eval, bindings, body_env, class_env, call_cache, stack, declarations,
          diagnostics, resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, bindings, call_cache, class_env, call_cache,
            stack, declarations, diagnostics, resolve_import,
          )
        None => None
      }
    }
  }
}

///|
/// Apply a `FunctionValue` to an array of already-evaluated `Value`
/// arguments. Mirrors `eval_lambda_application` but accepts values instead
/// of expressions so the stdlib builtins (Listing.map / .filter / .fold)
/// can invoke user callbacks per element.
fn apply_function_value(
  label : String,
  fn_value : Value,
  args : Array[Value],
  bindings : Array[Binding],
  _env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  caller_cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match fn_value {
    FunctionValue(parameters, body, return_type_name, captured_env, _id) => {
      if parameters.length() != args.length() {
        diagnostics.push(
          diag(
            "\{label} expects \{parameters.length()} arguments, got \{args.length()}",
          ),
        )
        return None
      }
      let call_cache = copy_value_bindings(captured_env)
      // Re-introduce module metadata at application time. The capture
      // pass filters these plumbing markers out of ordinary function
      // values, but read/reflect paths inside the body still need them.
      push_module_metadata_from_cache(call_cache, caller_cache)
      push_class_default_scope_from_cache(call_cache, caller_cache)
      push_class_default_call_name(call_cache, label)
      for i = 0; i < parameters.length(); i = i + 1 {
        let parameter_type_name = strip_lazy_collection_annotation_marker_opt(
          parameters[i].type_name,
        )
        let mut argument_value = args[i]
        let mut overlaid = false
        match
          cast_callable_collection_annotation(
            parameter_type_name, argument_value, bindings, call_cache, class_env,
            call_cache, stack, declarations, resolve_import,
          ) {
          CallableCollectionCastOk(casted) => {
            argument_value = casted
            overlaid = true
          }
          CallableCollectionCastErr(message) => {
            diagnostics.push(diag(message))
            return None
          }
          CallableCollectionCastSkipped => {
            let (overlay_value, overlay_ok) = overlay_collection_annotation_if_possible(
              parameters[i].type_name,
              argument_value,
              bindings,
              call_cache,
              class_env,
              call_cache,
              stack,
              declarations,
              resolve_import,
            )
            argument_value = overlay_value
            overlaid = overlay_ok
          }
        }
        if !overlaid {
          match
            eval_callable_argument_type_rejection_message(
              parameter_type_name, argument_value, class_env, call_cache, declarations,
            ) {
            Some(message) => {
              diagnostics.push(diag(message))
              return None
            }
            None => ()
          }
          match
            eval_callable_argument_rejection_message(
              parameter_type_name, argument_value, declarations,
            ) {
            Some(message) => {
              // PKL-148o: bare upstream wording — see
              // `eval_lambda_application` for the rationale.
              let _ = label
              diagnostics.push(diag(message))
              return None
            }
            None => ()
          }
          // PKL-148bh: runtime predicate check for parameter
          // constraints (`(str: String(length > n)) -> str` where
          // `n` comes from the captured env — lambdas/typedLambdas).
          // The static cascade only handles closed-form integer
          // predicates; once the predicate references the captured
          // env we have to evaluate the constraint expression with
          // `this` bound to the argument.
          match
            eval_callable_runtime_constraint_message(
              parameter_type_name, argument_value, bindings, class_env, captured_env,
              stack, declarations, resolve_import,
            ) {
            Some(message) => {
              diagnostics.push(diag(message))
              return None
            }
            None => ()
          }
        }
        call_cache.push({ name: parameters[i].name, value: argument_value })
      }
      // PKL-148d: a lambda's body sees its captured_env + parameters
      // (both in `call_cache`) plus the module-level bindings; the
      // caller's lexical env (e.g. an import alias that happens to
      // shadow a lambda parameter, like `import "pkl:semver" as s`
      // colliding with `parse = (s) -> ...`) must NOT bleed in. Pass
      // an empty env so the env-first lookup order doesn't pick up
      // the caller's bindings.
      let body_env : Array[ValueBinding] = []
      // PKL-148bh: when the function declares a user-class return
      // type and the body is a bare `new { ... }` ObjectLiteral,
      // rewrite to `new T { ... }` so the body inherits the class
      // identity. This drives `getClass().simpleName` inside the
      // body — basic/newInAmendingModuleMethod's typed function
      // bodies expect the declared class name, not "Dynamic".
      let body_to_eval : Expr = match (body, return_type_name) {
        (ObjectLiteral(members), Some(class_name)) =>
          if class_name.contains("<") ||
            class_name.contains("|") ||
            class_name.contains("(") ||
            class_name.contains("?") ||
            class_name.contains(".") {
            body
          } else {
            match lookup_class_binding(class_env, class_name) {
              Some(_) => TypedObjectLiteral(class_name, members)
              None => body
            }
          }
        _ => body
      }
      match
        eval_expr_with_bindings(
          body_to_eval, bindings, body_env, class_env, call_cache, stack, declarations,
          diagnostics, resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, bindings, call_cache, class_env, call_cache,
            stack, declarations, diagnostics, resolve_import,
          )
        None => None
      }
    }
    _ => {
      diagnostics.push(diag("\{label} expects Function"))
      None
    }
  }
}

///|
fn eval_class_method_call(
  target_expr : Expr,
  method_name : String,
  arguments : Array[Expr],
  null_safe : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_expr_with_bindings(
      target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
    ) {
    Some(NullValue) =>
      if null_safe {
        Some(NullValue)
      } else {
        diagnostics.push(diag("method call expects Object"))
        None
      }
    Some(ObjectValue(receiver_members)) =>
      match typed_object_class_name_for_expr(target_expr, bindings, []) {
        Some(type_name) =>
          match lookup_class_method(class_env, type_name, method_name) {
            Some(function_decl) => {
              if function_decl.parameters.length() != arguments.length() {
                diagnostics.push(
                  diag(
                    "method \{method_name} expects \{function_decl.parameters.length()} arguments, got \{arguments.length()}",
                  ),
                )
                return None
              }
              let argument_values : Array[Value] = []
              let mut arguments_ok = true
              for argument in arguments {
                match
                  eval_expr_with_bindings(
                    argument, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  ) {
                  Some(value) => argument_values.push(value)
                  None => arguments_ok = false
                }
              }
              if !arguments_ok {
                return None
              }
              match function_decl.body {
                Some(body) => {
                  let method_cache = copy_value_bindings(cache)
                  push_receiver_method_bindings(method_cache, receiver_members)
                  // PKL-117: record the class whose body is about to
                  // evaluate so `super.method(...)` inside the body
                  // can locate the parent class.
                  push_super_dispatch_marker(method_cache, type_name)
                  // PKL-148e: sibling class methods are addressable
                  // by bare name from within a method body — Apple Pkl
                  // treats them like locally-scoped functions. Seed
                  // the method cache with every sibling as a
                  // FunctionValue so `Identifier(b)` inside `compute`
                  // resolves to `function b(x) = ...`.
                  push_sibling_class_methods(
                    method_cache, type_name, class_env, env, cache,
                  )
                  for i = 0; i < function_decl.parameters.length(); i = i + 1 {
                    let parameter_type_name = strip_lazy_collection_annotation_marker_opt(
                      function_decl.parameters[i].type_name,
                    )
                    let mut argument_value = argument_values[i]
                    let mut overlaid = false
                    match
                      cast_callable_collection_annotation(
                        parameter_type_name, argument_value, bindings, method_cache,
                        class_env, method_cache, stack, declarations, resolve_import,
                      ) {
                      CallableCollectionCastOk(casted) => {
                        argument_value = casted
                        overlaid = true
                      }
                      CallableCollectionCastErr(message) => {
                        diagnostics.push(diag(message))
                        return None
                      }
                      CallableCollectionCastSkipped => ()
                    }
                    if !overlaid {
                      match
                        eval_callable_argument_type_rejection_message(
                          parameter_type_name, argument_value, class_env, method_cache,
                          declarations,
                        ) {
                        Some(message) => {
                          diagnostics.push(diag(message))
                          return None
                        }
                        None => ()
                      }
                      match
                        eval_callable_argument_rejection_message(
                          parameter_type_name, argument_value, declarations,
                        ) {
                        Some(message) => {
                          // PKL-148o: bare upstream wording — see
                          // `eval_lambda_application` for the rationale.
                          let _ = method_name
                          diagnostics.push(diag(message))
                          return None
                        }
                        None => ()
                      }
                    }
                    method_cache.push({
                      name: function_decl.parameters[i].name,
                      value: argument_value,
                    })
                  }
                  match
                    eval_expr_with_bindings(
                      body, bindings, env, class_env, method_cache, stack, declarations,
                      diagnostics, resolve_import,
                    ) {
                    Some(value) =>
                      eval_callable_return_value(
                        "method \{method_name}",
                        function_decl.return_type_name,
                        value,
                        bindings,
                        method_cache,
                        class_env,
                        method_cache,
                        stack,
                        declarations,
                        diagnostics,
                        resolve_import,
                      )
                    None => None
                  }
                }
                None => {
                  diagnostics.push(diag("method \{method_name} has no body"))
                  None
                }
              }
            }
            None => {
              diagnostics.push(diag("Cannot find method `\{method_name}`."))
              None
            }
          }
        None => {
          diagnostics.push(diag("call expressions are parser-only"))
          None
        }
      }
    Some(_) => {
      diagnostics.push(diag("method call expects Object"))
      None
    }
    None => None
  }
}

///|
fn callee_label(callee : Expr) -> String {
  match callee {
    Identifier(name) => "function \{name}"
    _ => "function"
  }
}

///|
/// PKL-117: dispatch `super.method(args)`. Looks up the
/// `@current_class` marker (pushed by `eval_class_method_call`),
/// finds its parent class, and invokes the named method on the
/// parent using the current `this` value.
fn eval_super_method_call(
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
  let current_class = match lookup_value(cache, "@current_class") {
    Some(StringValue(name)) => name
    _ =>
      // PKL-148ac: module-level fallback. `extends "parent.pkl"`
      // pushes `super = ObjectValue(parent_members)` into the cache at
      // module init time; a child-module function / hidden property
      // calling `super.X(...)` lives outside any class body, so
      // `@current_class` is absent. Look up `method_name` in the
      // super-bound ObjectValue's members — when it's a FunctionValue,
      // apply it to the evaluated arguments through the same lambda
      // path. The lookup goes through `lookup_member` (not the visible
      // variant) because module-level functions are stored under the
      // hidden member prefix.
      match lookup_value(cache, "super") {
        Some(ObjectValue(parent_members)) => {
          let target = lookup_member(parent_members, method_name)
          match target {
            Some(FunctionValue(_, _, _, _, _) as fn_value) => {
              let argument_values : Array[Value] = []
              let mut args_ok = true
              for argument in arguments {
                match
                  eval_expr_with_bindings(
                    argument, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  ) {
                  Some(value) => argument_values.push(value)
                  None => args_ok = false
                }
              }
              if !args_ok {
                return None
              }
              return apply_function_value(
                "super.\{method_name}",
                bind_module_function_receiver(fn_value, cache, bindings),
                argument_values,
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            }
            Some(_) => {
              diagnostics.push(diag("super.\{method_name} is not a callable"))
              return None
            }
            None => {
              let target_name = match module_members_name(parent_members) {
                Some(name) => "module `\{name}`"
                None => "parent module"
              }
              diagnostics.push(
                diag("Cannot find method `\{method_name}` in \{target_name}."),
              )
              return None
            }
          }
        }
        _ => {
          diagnostics.push(
            diag("super.\{method_name} used outside a class body"),
          )
          return None
        }
      }
  }
  let parent_name = match lookup_class_binding(class_env, current_class) {
    Some(binding) =>
      match binding.parent_name {
        Some(name) => name
        None => {
          diagnostics.push(
            diag(
              "class \{current_class} has no parent for super.\{method_name}",
            ),
          )
          return None
        }
      }
    None => {
      diagnostics.push(diag("class \{current_class} not found"))
      return None
    }
  }
  let function_decl = match
    lookup_class_method(class_env, parent_name, method_name) {
    Some(decl) => decl
    None => {
      diagnostics.push(
        diag("super class \{parent_name} has no method \{method_name}"),
      )
      return None
    }
  }
  let receiver_members = match lookup_value(cache, "this") {
    Some(ObjectValue(members)) => members
    _ => []
  }
  if function_decl.parameters.length() != arguments.length() {
    diagnostics.push(
      diag(
        "super method \{method_name} expects \{function_decl.parameters.length()} arguments, got \{arguments.length()}",
      ),
    )
    return None
  }
  let argument_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(value) => argument_values.push(value)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match function_decl.body {
    Some(body) => {
      let method_cache = copy_value_bindings(cache)
      push_receiver_method_bindings(method_cache, receiver_members)
      push_super_dispatch_marker(method_cache, parent_name)
      for i = 0; i < function_decl.parameters.length(); i = i + 1 {
        method_cache.push({
          name: function_decl.parameters[i].name,
          value: argument_values[i],
        })
      }
      eval_expr_with_bindings(
        body, bindings, env, class_env, method_cache, stack, declarations, diagnostics,
        resolve_import,
      )
    }
    None => {
      diagnostics.push(
        diag("super class \{parent_name} method \{method_name} has no body"),
      )
      None
    }
  }
}

///|
/// PKL-120: detect a call whose callee is one of the synthetic
/// `_pkl_math_<op>` intrinsic identifiers and the binding hasn't
/// been shadowed by a user import.

///|
fn class_method_call_available(
  target_expr : Expr,
  method_name : String,
  bindings : Array[Binding],
  class_env : Array[ClassBinding],
) -> Bool {
  match typed_object_class_name_for_expr(target_expr, bindings, []) {
    Some(type_name) =>
      lookup_class_method(class_env, type_name, method_name) is Some(_)
    None => false
  }
}

///|
fn mixin_apply_target_type_name(members : Array[ValueMember]) -> String? {
  match find_object_class_tag(members) {
    Some(tag) => generic_argument_text(tag, "Mixin")
    None => None
  }
}

///|
fn eval_callable_call(
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
  // PKL-148e: `g.apply(args...)` / `g?.apply(args...)` route to
  // direct lambda application when `g` evaluates to a FunctionValue.
  // Without this intercept the MemberAccess on a FunctionValue hits
  // the catch-all "member access expects Object" arm — Apple Pkl
  // exposes `.apply` on every `Function<...>` value. `.toString()` /
  // `.getClass()` ride along the same intercept since they share the
  // same dispatch shape.
  let function_method : (Expr, String)? = match callee {
    MemberAccess(target_expr, method_name) =>
      if method_name == "apply" ||
        method_name == "applyToList" ||
        method_name == "toString" ||
        method_name == "getClass" ||
        is_typed_method_name(method_name) {
        Some((target_expr, method_name))
      } else {
        None
      }
    SafeMemberAccess(target_expr, method_name) =>
      if method_name == "apply" ||
        method_name == "applyToList" ||
        method_name == "toString" ||
        method_name == "getClass" ||
        is_typed_method_name(method_name) {
        Some((target_expr, method_name))
      } else {
        None
      }
    _ => None
  }
  match function_method {
    Some((target_expr, method_name)) =>
      match
        eval_expr_with_bindings(
          target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(
          FunctionValue(parameters, body, return_type_name, captured_env, id)
        ) =>
          match method_name {
            "apply" =>
              return eval_lambda_application(
                callee_label(callee),
                parameters,
                body,
                return_type_name,
                captured_env,
                arguments,
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            "applyToList" => {
              // PKL-148e: `lambda.applyToList(list)` unpacks `list`
              // into positional arguments before applying. Mirrors
              // Apple Pkl's `Function.applyToList` which delegates to
              // `apply(elements[0], elements[1], ...)`.
              if arguments.length() != 1 {
                diagnostics.push(
                  diag(
                    "Function.applyToList expects 1 argument, got \{arguments.length()}",
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
                Some(ListingValue(elements))
                | Some(DefaultedListingValue(_, elements, _))
                | Some(ListValue(elements))
                | Some(SetValue(elements)) =>
                  // Apply with pre-evaluated values by wrapping each
                  // element back as a literal value expression. The
                  // call cache machinery only needs the values
                  // themselves at lambda-body entry; the simplest
                  // bridge is `apply_function_value`.
                  return apply_function_value(
                    callee_label(callee),
                    FunctionValue(
                      parameters, body, return_type_name, captured_env, id,
                    ),
                    elements,
                    bindings,
                    env,
                    class_env,
                    cache,
                    stack,
                    declarations,
                    diagnostics,
                    resolve_import,
                  )
                Some(_) => {
                  diagnostics.push(
                    diag("Function.applyToList expects a List argument"),
                  )
                  return None
                }
                None => return None
              }
            }
            "toString" =>
              if arguments.length() != 0 {
                diagnostics.push(diag("Function.toString takes no arguments"))
                return None
              } else {
                return Some(
                  StringValue("new Function\{parameters.length()} {}"),
                )
              }
            "getClass" =>
              if arguments.length() != 0 {
                diagnostics.push(diag("Function.getClass takes no arguments"))
                return None
              } else {
                return Some(
                  synth_class_mirror_for_value(
                    FunctionValue(
                      parameters, body, return_type_name, captured_env, id,
                    ),
                  ),
                )
              }
            _ => ()
          }
        Some(NullValue) =>
          if callee is SafeMemberAccess(_, _) {
            return Some(NullValue)
          }
        Some(ObjectValue(members)) =>
          if method_name == "toString" && arguments.length() == 0 {
            return Some(StringValue(object_to_string_value(members)))
          } else if is_typed_method_name(method_name) {
            return eval_typed_method_dispatch(
              members, method_name, arguments, bindings, env, class_env, cache, stack,
              declarations, diagnostics, resolve_import,
            )
          } else if method_name == "apply" &&
            (
              object_class_tag_matches(members, "Mixin") ||
              object_members_are_mixin_body(members)
            ) {
            if arguments.length() != 1 {
              diagnostics.push(
                diag(
                  "Expected 1 function arguments but got \{arguments.length()}.",
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
              Some(target) => {
                match
                  eval_callable_argument_type_rejection_message(
                    mixin_apply_target_type_name(members),
                    target,
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
                return apply_mixin_pipe_value(target, members, diagnostics)
              }
              None => return None
            }
          }
        _ => ()
      }
    None => ()
  }
  match
    eval_expr_with_bindings(
      callee, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
    ) {
    Some(FunctionValue(parameters, body, return_type_name, captured_env, _id)) =>
      tag_xml_comment_call_result(
        callee,
        eval_lambda_application(
          callee_label(callee),
          parameters,
          body,
          return_type_name,
          captured_env,
          arguments,
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ),
      )
    Some(NullValue) =>
      match callee {
        SafeMemberAccess(_, _) => Some(NullValue)
        _ => {
          diagnostics.push(diag("call expects Function"))
          None
        }
      }
    Some(_) => {
      diagnostics.push(diag("call expects Function"))
      None
    }
    None => None
  }
}

///|
fn tag_xml_comment_call_result(callee : Expr, value : Value?) -> Value? {
  match (callee, value) {
    (_, Some(ObjectValue(members))) => {
      let visible = visible_members(members)
      if !(callee is Identifier("comment")) &&
        !(visible.length() == 1 && visible[0].name == "text") {
        return value
      }
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
      Some(ObjectValue(tag_object_with_class(tagged_members, "xml.Comment")))
    }
    _ => value
  }
}

///|
