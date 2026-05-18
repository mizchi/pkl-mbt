///|
fn eval_value_accepts_type_annotation(
  type_name : String,
  value : Value,
) -> Bool {
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
    ("Listing", ListingValue(_)) => true
    ("Mapping", MappingValue(_)) => true
    // PKL-148h: `List<T>` accepts the dedicated `ListValue`; the older
    // path accepting `ListingValue` is kept as a transitional aid for
    // codepaths that still produce `ListingValue` for list-shaped input
    // (e.g. `pkl:json.Parser` arrays). Apple Pkl's `Collection` is the
    // join of List + Set, so all three list-shaped variants satisfy it.
    // `Map` accepts both `MapValue` and `MappingValue` for the same
    // reason; the split slice for Mapping is separate.
    ("List", ListValue(_)) | ("List", ListingValue(_)) => true
    ("Collection", ListValue(_))
    | ("Collection", ListingValue(_))
    | ("Collection", SetValue(_)) => true
    ("Map", MapValue(_)) | ("Map", MappingValue(_)) => true
    ("Set", SetValue(_)) | ("Set", ListingValue(_)) | ("Set", ListValue(_)) =>
      true
    ("Pair", PairValue(_, _)) => true
    ("IntSeq", IntSeqValue(_, _, _)) => true
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
              | ListValue(elements)
              | SetValue(elements) =>
                for element in elements {
                  match
                    eval_callable_argument_type_rejection_message(
                      Some(element_type),
                      element,
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
                MappingValue(entries) | MapValue(entries) =>
                  for entry in entries {
                    match
                      eval_callable_argument_type_rejection_message(
                        Some(key_type),
                        entry.key,
                        declarations,
                      ) {
                      Some(message) => return Some(message)
                      None => ()
                    }
                    match
                      eval_callable_argument_type_rejection_message(
                        Some(value_type),
                        entry.value,
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
      let diag_name = {
        let trimmed = pkl_constraint_trim(resolved)
        let without_constraint = match pkl_constrained_type_base_name(trimmed) {
          Some(base) => base
          None => trimmed
        }
        if without_constraint.has_suffix("?") {
          String::unsafe_substring(
            without_constraint,
            start=0,
            end=without_constraint.length() - 1,
          )
        } else {
          without_constraint
        }
      }
      Some(
        "Expected value of type `\{diag_name}`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
      )
    }
    None => None
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

///|
/// PKL-148: render a value through the inline PCF form so diagnostic
/// messages can quote the rejected value. The wrapper keeps the call
/// sites concise — the `Value: <text>` segment is a recurring shape
/// in Apple Pkl's constraint / type-mismatch wording.
fn render_pcf_value_inline(value : Value) -> String {
  let buf = StringBuilder::new()
  render_pcf_inline(value, 0, buf)
  buf.to_string()
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
    _ => render_pcf_inline(value, 0, buf)
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
    ObjectValue(_) => {
      if type_name == "Dynamic" || type_name == "Typed" {
        return true
      }
      let base = match pkl_constrained_type_base_name(type_name) {
        Some(b) => b
        None => type_name
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
        Some(
          "Expected value of type `\{type_name}`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
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
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Value? {
  match
    eval_callable_return_rejection_message(
      label, return_type_name, value, declarations,
    ) {
    Some(message) => {
      diagnostics.push(diag(message))
      None
    }
    None => Some(value)
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
  for i = 0; i < parameters.length(); i = i + 1 {
    match
      eval_callable_argument_type_rejection_message(
        parameters[i].type_name,
        argument_values[i],
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
        parameters[i].type_name,
        argument_values[i],
        declarations,
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
    call_cache.push({ name: parameters[i].name, value: argument_values[i] })
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
        declarations,
        diagnostics,
      )
    _ => {
      // PKL-148d: same lexical-isolation as `apply_function_value`.
      // The lambda body must not see the caller's env (which may
      // shadow a parameter, e.g. `import "pkl:semver" as s` colliding
      // with the lambda parameter `s`). captured_env + parameters
      // already live in `call_cache`.
      let body_env : Array[ValueBinding] = []
      match
        eval_expr_with_bindings(
          body, bindings, body_env, class_env, call_cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, declarations, diagnostics,
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
  _cache : Array[ValueBinding],
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
      for i = 0; i < parameters.length(); i = i + 1 {
        match
          eval_callable_argument_type_rejection_message(
            parameters[i].type_name,
            args[i],
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
            parameters[i].type_name,
            args[i],
            declarations,
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
        call_cache.push({ name: parameters[i].name, value: args[i] })
      }
      // PKL-148d: a lambda's body sees its captured_env + parameters
      // (both in `call_cache`) plus the module-level bindings; the
      // caller's lexical env (e.g. an import alias that happens to
      // shadow a lambda parameter, like `import "pkl:semver" as s`
      // colliding with `parse = (s) -> ...`) must NOT bleed in. Pass
      // an empty env so the env-first lookup order doesn't pick up
      // the caller's bindings.
      let body_env : Array[ValueBinding] = []
      match
        eval_expr_with_bindings(
          body, bindings, body_env, class_env, call_cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, declarations, diagnostics,
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
                    match
                      eval_callable_argument_type_rejection_message(
                        function_decl.parameters[i].type_name,
                        argument_values[i],
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
                        function_decl.parameters[i].type_name,
                        argument_values[i],
                        declarations,
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
                    method_cache.push({
                      name: function_decl.parameters[i].name,
                      value: argument_values[i],
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
                        declarations,
                        diagnostics,
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
          let target = match lookup_member(parent_members, method_name) {
            Some(value) => Some(value)
            None =>
              lookup_member(parent_members, hidden_member_name(method_name))
          }
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
                fn_value,
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
              diagnostics.push(
                diag("Cannot find method `\{method_name}` in parent module."),
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
        method_name == "getClass" {
        Some((target_expr, method_name))
      } else {
        None
      }
    SafeMemberAccess(target_expr, method_name) =>
      if method_name == "apply" ||
        method_name == "applyToList" ||
        method_name == "toString" ||
        method_name == "getClass" {
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
