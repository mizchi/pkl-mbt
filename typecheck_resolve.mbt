///|
fn resolve_binding_type(
  name : String,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type? {
  match lookup_type(cache, name) {
    Some(typ) => Some(typ)
    None =>
      match find_type_binding(bindings, name) {
        Some(binding) =>
          if stack_contains_type_binding(stack, name) {
            diagnostics.push(diag("cyclic property reference \{name}"))
            None
          } else {
            let inferred = infer_expr_with_bindings(
              binding.value,
              bindings,
              env,
              type_env,
              cache,
              push_type_stack(stack, name),
              diagnostics,
              resolve_import,
            )
            let typ = apply_type_annotation(
              binding.type_name,
              inferred,
              type_env,
              diagnostics,
            )
            push_constrained_type_annotation_expr_diagnostic(
              binding.type_name,
              binding.value,
              type_env,
              diagnostics,
            )
            cache.push({ name, typ, alias_decl: None, bound: None })
            Some(typ)
          }
        None => lookup_type(env, name)
      }
  }
}

///|
fn infer_argument_types(
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[Type] {
  let argument_types : Array[Type] = []
  for argument in arguments {
    argument_types.push(
      infer_expr_with_bindings(
        argument, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      ),
    )
  }
  argument_types
}

///|
fn function_parameter_index(
  parameters : Array[FunctionParameter],
  name : String,
) -> Int? {
  for i = 0; i < parameters.length(); i = i + 1 {
    if parameters[i].name == name {
      return Some(i)
    }
  }
  None
}

///|
fn callable_parameter_types_from_type(typ : Type) -> Array[Type]? {
  match typ {
    FunctionType(parameter_types, _) => Some(parameter_types)
    NullableType(FunctionType(parameter_types, _)) => Some(parameter_types)
    _ => None
  }
}

///|
fn validate_higher_order_constrained_call(
  label : String,
  parameters : Array[FunctionParameter],
  body : Expr,
  argument_types : Array[Type],
  arguments : Array[Expr],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match body {
    CallExpr(Identifier(callee_name), call_arguments) =>
      match function_parameter_index(parameters, callee_name) {
        Some(callee_index) =>
          match
            callable_parameter_types_from_type(argument_types[callee_index]) {
            Some(callable_parameter_types) => {
              let mut limit = call_arguments.length()
              if callable_parameter_types.length() < limit {
                limit = callable_parameter_types.length()
              }
              for i = 0; i < limit; i = i + 1 {
                match
                  constrained_type_annotation_name(callable_parameter_types[i]) {
                  Some(type_name) =>
                    match call_arguments[i] {
                      Identifier(argument_name) =>
                        match
                          function_parameter_index(parameters, argument_name) {
                          Some(argument_index) =>
                            match
                              constrained_type_annotation_expr_rejection_message(
                                Some(type_name),
                                arguments[argument_index],
                                type_env,
                              ) {
                              Some(message) => {
                                diagnostics.push(
                                  diag(
                                    "\{label} argument \{argument_index + 1} \{message}",
                                  ),
                                )
                                return false
                              }
                              None => ()
                            }
                          None => ()
                        }
                      _ => ()
                    }
                  None => ()
                }
              }
              true
            }
            None => true
          }
        None => true
      }
    _ => true
  }
}

///|
fn infer_lambda_application(
  label : String,
  parameters : Array[FunctionParameter],
  return_type_name : String?,
  body : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  if parameters.length() != arguments.length() {
    diagnostics.push(
      diag(
        "\{label} expects \{parameters.length()} arguments, got \{arguments.length()}",
      ),
    )
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  // PKL-110: collect TypeVariable substitutions from every parameter site
  // before evaluating the body so callee-scoped uses of T (parameter cache,
  // body-derived return, declared return annotation) all see the same
  // concrete binding.
  let substitutions : Array[TypeSubstitution] = []
  let call_cache = copy_type_bindings(cache)
  for i = 0; i < parameters.length(); i = i + 1 {
    let parameter = parameters[i]
    let parameter_type = match parameter.type_name {
      Some(type_name) =>
        match parameter_type_from_annotation(type_name, type_env) {
          Some(expected) =>
            if type_accepts(expected, argument_types[i]) {
              match
                constrained_type_annotation_expr_rejection_message(
                  parameter.type_name,
                  arguments[i],
                  type_env,
                ) {
                Some(message) => {
                  diagnostics.push(
                    diag("\{label} argument \{i + 1} \{message}"),
                  )
                  return UnknownType
                }
                None => ()
              }
              unify_for_substitution(
                expected,
                argument_types[i],
                substitutions,
                type_env,
                diagnostics,
              )
              substitute_type(expected, substitutions)
            } else {
              diagnostics.push(
                diag(
                  "\{label} argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
                ),
              )
              return UnknownType
            }
          None => {
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
            UnknownType
          }
        }
      None => argument_types[i]
    }
    call_cache.push({
      name: parameter.name,
      typ: parameter_type,
      alias_decl: None,
      bound: None,
    })
  }
  if !validate_higher_order_constrained_call(
      label, parameters, body, argument_types, arguments, type_env, diagnostics,
    ) {
    return UnknownType
  }
  let inferred_return = infer_expr_with_bindings(
    body, bindings, env, type_env, call_cache, stack, diagnostics, resolve_import,
  )
  let inferred_return = substitute_type(inferred_return, substitutions)
  match return_type_name {
    Some(type_name) =>
      match type_from_annotation(type_name, type_env) {
        Some(expected) => {
          let expected = substitute_type(expected, substitutions)
          if type_accepts(expected, inferred_return) {
            expected
          } else {
            diagnostics.push(
              diag(
                "\{label} return annotation \{type_name} does not accept \{render_type(inferred_return)}",
              ),
            )
            UnknownType
          }
        }
        None => {
          diagnostics.push(diag("Cannot find type `\{type_name}`."))
          UnknownType
        }
      }
    None => inferred_return
  }
}

///|
fn constrained_type_annotation_name(typ : Type) -> String? {
  match typ {
    ConstrainedType(type_name, _) => Some(type_name)
    DefaultedType(inner) => constrained_type_annotation_name(inner)
    NullableType(inner) => constrained_type_annotation_name(inner)
    _ => None
  }
}

///|
fn infer_function_type_call(
  label : String,
  parameter_types : Array[Type],
  return_type : Type,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  if parameter_types.length() != arguments.length() {
    diagnostics.push(
      diag(
        "\{label} expects \{parameter_types.length()} arguments, got \{arguments.length()}",
      ),
    )
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  let substitutions : Array[TypeSubstitution] = []
  for i = 0; i < parameter_types.length(); i = i + 1 {
    let expected = parameter_types[i]
    if expected != UnknownType && !type_accepts(expected, argument_types[i]) {
      diagnostics.push(
        diag(
          "\{label} argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
        ),
      )
      return UnknownType
    }
    unify_for_substitution(
      expected,
      argument_types[i],
      substitutions,
      type_env,
      diagnostics,
    )
    match constrained_type_annotation_name(expected) {
      Some(type_name) =>
        match
          constrained_type_annotation_expr_rejection_message(
            Some(type_name),
            arguments[i],
            type_env,
          ) {
          Some(message) => {
            diagnostics.push(diag("\{label} argument \{i + 1} \{message}"))
            return UnknownType
          }
          None => ()
        }
      None => ()
    }
  }
  substitute_type(return_type, substitutions)
}

///|
fn function_type_call_label(callee : Expr) -> String {
  match callee {
    MemberAccess(_, member_name) | SafeMemberAccess(_, member_name) =>
      "method \{member_name}"
    _ => "function"
  }
}

///|
fn infer_call_expr(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  match callee {
    LambdaExpr(parameters, body, return_type_name) =>
      return infer_lambda_application(
        "function", parameters, return_type_name, body, arguments, bindings, env,
        type_env, cache, stack, diagnostics, resolve_import,
      )
    Identifier(name) =>
      match find_type_binding(bindings, name) {
        Some(binding) =>
          match binding.value {
            LambdaExpr(parameters, body, return_type_name) =>
              return infer_lambda_application(
                "function \{name}",
                parameters,
                return_type_name,
                body,
                arguments,
                bindings,
                env,
                type_env,
                cache,
                stack,
                diagnostics,
                resolve_import,
              )
            _ => ()
          }
        None => ()
      }
    _ => ()
  }
  // PKL-119a: `Pair(first, second)` is a top-level constructor in
  // Apple Pkl's surface, not a user-defined binding. Infer it
  // directly into `PairType(first_type, second_type)` so call sites
  // see the dedicated type and `.first` / `.second` accesses resolve.
  if callee is Identifier("Pair") && find_type_binding(bindings, "Pair") is None {
    if arguments.length() != 2 {
      diagnostics.push(diag("Pair expects exactly two arguments"))
      return UnknownType
    }
    let first_type = infer_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    let second_type = infer_expr_with_bindings(
      arguments[1],
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    return PairType(first_type, second_type)
  }
  // PKL-119b: method-call form on an IntSeq receiver. `.step(n)`
  // returns a new IntSeq; `.toList()` / `.toListing()` return
  // `Listing<Int>`; `.map(f)` returns a `Listing` of the lambda's
  // return type; `.fold(initial, op)` returns the initial type.
  // Intercept here so the call site sees the correct return type
  // even though the bare `MemberAccess(intseq, method)` resolves to
  // UnknownType (or `Int` for the overloaded `.step` accessor).
  match callee {
    MemberAccess(target_expr, method_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        IntSeqType =>
          match method_name {
            "step" => return IntSeqType
            "toList" | "toListing" => return ListingType([IntType])
            "map" =>
              if arguments.length() == 1 {
                let lambda_type = infer_expr_with_bindings(
                  arguments[0],
                  bindings,
                  env,
                  type_env,
                  cache,
                  stack,
                  diagnostics,
                  resolve_import,
                )
                match lambda_type {
                  FunctionType(_, return_type) =>
                    return ListingType([return_type])
                  _ => return ListingType([UnknownType])
                }
              } else {
                return ListingType([UnknownType])
              }
            "fold" =>
              if arguments.length() == 2 {
                return infer_expr_with_bindings(
                  arguments[0],
                  bindings,
                  env,
                  type_env,
                  cache,
                  stack,
                  diagnostics,
                  resolve_import,
                )
              } else {
                return UnknownType
              }
            _ => ()
          }
        // PKL-119c: SetType method-call return-type inference.
        // `.contains` → Boolean; `.toList` / `.toListing` →
        // `Listing<element>`; `.toSet` → identity `Set<element>`;
        // `.map(f)` → Listing of the lambda's return type;
        // `.filter(p)` → `Set<element>`; `.fold(initial, op)` →
        // initial type; `.join(sep)` → String.
        SetType(element_types) =>
          match method_name {
            "contains" => return BoolType
            "toList" | "toListing" => return ListingType(element_types)
            "toSet" => return SetType(element_types)
            "map" =>
              if arguments.length() == 1 {
                let lambda_type = infer_expr_with_bindings(
                  arguments[0],
                  bindings,
                  env,
                  type_env,
                  cache,
                  stack,
                  diagnostics,
                  resolve_import,
                )
                match lambda_type {
                  FunctionType(_, return_type) =>
                    return ListingType([return_type])
                  _ => return ListingType([UnknownType])
                }
              } else {
                return ListingType([UnknownType])
              }
            "filter" => return SetType(element_types)
            "fold" =>
              if arguments.length() == 2 {
                return infer_expr_with_bindings(
                  arguments[0],
                  bindings,
                  env,
                  type_env,
                  cache,
                  stack,
                  diagnostics,
                  resolve_import,
                )
              } else {
                return UnknownType
              }
            "join" => return StringType
            _ => ()
          }
        // PKL-119d: MapType method-call return-type inference. Lookup
        // helpers (`.containsKey` → Boolean, `.getOrNull(k)` → value
        // type narrowed to `value?`, `.getOrThrow(k)` → value type).
        // Projection (`.toMap` → identity, `.toMapping` → MappingType,
        // `.toList` → Listing<Pair<K, V>>). Higher-order (`.map` →
        // open MapType<UnknownKey, UnknownValue> since the lambda's
        // return-type structure is opaque without a richer signature
        // model; `.filter` → MapType<K, V>; `.fold` → initial type).
        MapType(type_entries) =>
          match method_name {
            "containsKey" => return BoolType
            "getOrNull" =>
              if type_entries.length() == 0 {
                return UnknownType
              } else {
                return nullable_type(
                  common_type(type_entries.map(fn(e) { e.value })),
                )
              }
            "getOrThrow" =>
              if type_entries.length() == 0 {
                return UnknownType
              } else {
                return common_type(type_entries.map(fn(e) { e.value }))
              }
            "toMap" => return MapType(type_entries)
            "toMapping" => return MappingType(type_entries)
            "toList" =>
              if type_entries.length() == 0 {
                return ListingType([PairType(UnknownType, UnknownType)])
              } else {
                let key_type = common_type(type_entries.map(fn(e) { e.key }))
                let value_type = common_type(
                  type_entries.map(fn(e) { e.value }),
                )
                return ListingType([PairType(key_type, value_type)])
              }
            "map" => return MapType([])
            "filter" => return MapType(type_entries)
            "fold" =>
              if arguments.length() == 2 {
                return infer_expr_with_bindings(
                  arguments[0],
                  bindings,
                  env,
                  type_env,
                  cache,
                  stack,
                  diagnostics,
                  resolve_import,
                )
              } else {
                return UnknownType
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  // PKL-119c: `Set(a, b, c)` constructor — element types flow
  // through inference; the returned `SetType` carries those types
  // so downstream `.contains` etc. keep their narrowing.
  if callee is Identifier("Set") && find_type_binding(bindings, "Set") is None {
    let element_types : Array[Type] = []
    for argument in arguments {
      element_types.push(
        infer_expr_with_bindings(
          argument, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ),
      )
    }
    return SetType(element_types)
  }
  // PKL-119d: `Map(k1, v1, k2, v2, ...)` constructor — alternating
  // arguments flow through inference into the carrier type-entry
  // shape. Odd argument count surfaces the eval-side diagnostic so
  // both passes report the same wording.
  if callee is Identifier("Map") && find_type_binding(bindings, "Map") is None {
    if arguments.length() % 2 != 0 {
      diagnostics.push(
        diag("Map expects an even number of arguments (alternating key, value)"),
      )
      return UnknownType
    }
    let type_entries : Array[TypeEntry] = []
    let mut i = 0
    while i < arguments.length() {
      let key = infer_expr_with_bindings(
        arguments[i],
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
      let value = infer_expr_with_bindings(
        arguments[i + 1],
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
      type_entries.push({ key, value })
      i = i + 2
    }
    return MapType(type_entries)
  }
  // PKL-119b: `IntSeq(start, end)` mirrors the Pair handling. Both
  // arguments must accept `Int`; the returned type is the parameter-
  // free `IntSeqType`.
  if callee is Identifier("IntSeq") &&
    find_type_binding(bindings, "IntSeq") is None {
    if arguments.length() != 2 {
      diagnostics.push(diag("IntSeq expects exactly two arguments"))
      return UnknownType
    }
    let start_type = infer_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    let end_type = infer_expr_with_bindings(
      arguments[1],
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    if !type_accepts(IntType, start_type) {
      diagnostics.push(
        diag("IntSeq argument 1 expects Int, got \{render_type(start_type)}"),
      )
    }
    if !type_accepts(IntType, end_type) {
      diagnostics.push(
        diag("IntSeq argument 2 expects Int, got \{render_type(end_type)}"),
      )
    }
    return IntSeqType
  }
  match
    infer_expr_with_bindings(
      callee, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
    ) {
    FunctionType(parameter_types, return_type) =>
      infer_function_type_call(
        function_type_call_label(callee),
        parameter_types,
        return_type,
        arguments,
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
    NullableType(FunctionType(parameter_types, return_type)) => {
      let inferred_return = infer_function_type_call(
        function_type_call_label(callee),
        parameter_types,
        return_type,
        arguments,
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
      if inferred_return == UnknownType {
        UnknownType
      } else {
        nullable_type(inferred_return)
      }
    }
    NullType =>
      match callee {
        SafeMemberAccess(_, _) => NullType
        _ => {
          diagnostics.push(diag("call expects Function"))
          UnknownType
        }
      }
    UnknownType => UnknownType
    _ => {
      diagnostics.push(diag("call expects Function"))
      UnknownType
    }
  }
}
