///|
fn infer_boolean_condition_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  match expr {
    BinaryExpr(And, left_expr, right_expr) => {
      let left = infer_boolean_condition_expr(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right_cache = copy_type_bindings(cache)
      apply_positive_is_guard_expr(
        left_expr, bindings, env, type_env, cache, right_cache, stack, diagnostics,
        resolve_import,
      )
      let right = infer_boolean_condition_expr(
        right_expr, bindings, env, type_env, right_cache, stack, diagnostics, resolve_import,
      )
      if left == BoolType && right == BoolType {
        BoolType
      } else {
        diagnostics.push(diag("operator && expects Boolean operands"))
        UnknownType
      }
    }
    BinaryExpr(Or, left_expr, right_expr) => {
      let left = infer_boolean_condition_expr(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right_cache = copy_type_bindings(cache)
      apply_negative_is_guard_expr(
        left_expr, bindings, env, type_env, cache, right_cache, stack, diagnostics,
        resolve_import,
      )
      let right = infer_boolean_condition_expr(
        right_expr, bindings, env, type_env, right_cache, stack, diagnostics, resolve_import,
      )
      if left == BoolType && right == BoolType {
        BoolType
      } else {
        diagnostics.push(diag("operator || expects Boolean operands"))
        UnknownType
      }
    }
    _ =>
      infer_expr_with_bindings(
        expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
  }
}

///|
fn infer_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  match expr {
    IntLiteral(_) => IntType
    FloatLiteral(_) => FloatType
    BoolLiteral(_) => BoolType
    StringLiteral(_) => StringType
    NullLiteral => NullType
    ImportExpr(uri) =>
      match resolve_import(uri) {
        Some(TypeOk(typ)) => typ
        Some(TypeError(errors)) => {
          for error in errors {
            diagnostics.push(error)
          }
          UnknownType
        }
        None => {
          diagnostics.push(diag("unresolved import \{uri}"))
          UnknownType
        }
      }
    ImportGlobExpr(_) => MapType([])
    ObjectLiteral(members) =>
      ObjectType(
        infer_object_members(
          members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ),
      )
    TypedObjectLiteral(type_name, members) => {
      let inferred = ObjectType(
        infer_object_members(
          members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ),
      )
      apply_type_annotation(Some(type_name), inferred, type_env, diagnostics)
    }
    ListingLiteral(elements) => {
      let collection_bindings = bindings_with_listing_locals(elements, bindings)
      let item_types : Array[Type] = []
      for element in elements {
        if collection_local_binding_from_expr(element) is Some(_) {
          continue
        }
        item_types.push(
          infer_expr_with_bindings(
            element, collection_bindings, env, type_env, cache, stack, diagnostics,
            resolve_import,
          ),
        )
      }
      ListingType(item_types)
    }
    MappingLiteral(entries) => {
      let collection_bindings = bindings_with_mapping_locals(entries, bindings)
      let entry_types : Array[TypeEntry] = []
      for entry in entries {
        if collection_local_binding_from_expr(entry.key) is Some(_) {
          continue
        }
        let key = infer_expr_with_bindings(
          entry.key,
          collection_bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        let value = infer_expr_with_bindings(
          entry.value,
          collection_bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        entry_types.push({ key, value })
      }
      MappingType(entry_types)
    }
    MemberAccess(target_expr, member_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        // PKL-119a: `.first` / `.second` on a PairType resolve to the
        // two type parameters; anything else surfaces the standard
        // Pkl wording naming the target type.
        PairType(first, second) =>
          match member_name {
            "first" => first
            "second" => second
            _ => {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Pair`.",
                ),
              )
              UnknownType
            }
          }
        // PKL-119b: `.start` / `.end` / `.step` resolve to `Int`.
        // Method names (`.toList` / `.toListing` / `.map` / `.fold` /
        // overloaded `.step(n)`) fall through silently to UnknownType
        // because the method-call form is dispatched at runtime
        // through `eval_intseq_method`; the typechecker does not yet
        // model collection-method signatures (Listing has the same
        // gap). Unknown bare-property reads still surface the
        // canonical Pkl wording.
        IntSeqType =>
          match member_name {
            "start" | "end" | "step" => IntType
            "toList" | "toListing" | "map" | "fold" => UnknownType
            _ => {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `IntSeq`.",
                ),
              )
              UnknownType
            }
          }
        // PKL-119c: SetType bare property reads — `.length` /
        // `.isEmpty` / `.isNotEmpty` are Int / Boolean. `.first` /
        // `.last` return the element type when known. `.distinct` is
        // identity. Method names fall through silently because the
        // call form is handled earlier in `infer_call_expr`; unknown
        // bare-property reads still surface the canonical wording.
        SetType(element_types) =>
          match member_name {
            "length" => IntType
            "isEmpty" | "isNotEmpty" => BoolType
            "first" | "last" =>
              if element_types.length() == 0 {
                UnknownType
              } else {
                common_type(element_types)
              }
            "distinct" => SetType(element_types)
            "contains"
            | "toList"
            | "toListing"
            | "toSet"
            | "map"
            | "filter"
            | "fold"
            | "join" => UnknownType
            _ => {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Set`.",
                ),
              )
              UnknownType
            }
          }
        // PKL-119d: MapType bare property reads — `.length` / `.isEmpty`
        // / `.isNotEmpty` are Int / Boolean; `.keys` → `Set<K>`;
        // `.values` → `Listing<V>`; `.entries` → `Listing<Pair<K, V>>`.
        // Method names fall through silently (the call form is
        // intercepted in `infer_call_expr`); unknown bare reads
        // surface the canonical wording.
        MapType(type_entries) =>
          match member_name {
            "length" => IntType
            "isEmpty" | "isNotEmpty" => BoolType
            "keys" =>
              if type_entries.length() == 0 {
                SetType([])
              } else {
                SetType([common_type(type_entries.map(fn(e) { e.key }))])
              }
            "values" =>
              if type_entries.length() == 0 {
                ListingType([])
              } else {
                ListingType([common_type(type_entries.map(fn(e) { e.value }))])
              }
            "entries" =>
              if type_entries.length() == 0 {
                ListingType([PairType(UnknownType, UnknownType)])
              } else {
                ListingType([
                  PairType(
                    common_type(type_entries.map(fn(e) { e.key })),
                    common_type(type_entries.map(fn(e) { e.value })),
                  ),
                ])
              }
            "containsKey"
            | "getOrNull"
            | "getOrThrow"
            | "toMap"
            | "toMapping"
            | "toList"
            | "map"
            | "filter"
            | "fold" => UnknownType
            _ => {
              diagnostics.push(
                diag(
                  "Cannot find property `\{member_name}` in object of type `Map`.",
                ),
              )
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("member access expects Object"))
          UnknownType
        }
      }
    SafeMemberAccess(target_expr, member_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        NullableType(ObjectType(members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        NullableType(ClassType(_, members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(diag("Cannot find property `\{member_name}`."))
              UnknownType
            }
          }
        NullType => NullType
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("safe member access expects Object"))
          UnknownType
        }
      }
    SubscriptAccess(target_expr, key_expr) => {
      let target = infer_expr_with_bindings(
        target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let key = infer_expr_with_bindings(
        key_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match target {
        ListingType(items) =>
          if key == IntType {
            match key_expr {
              IntLiteral(index64) => {
                let index = index64.to_int()
                if index64 >= 0L && index < items.length() {
                  items[index]
                } else {
                  diagnostics.push(
                    diag("listing index out of bounds \{index64}"),
                  )
                  UnknownType
                }
              }
              _ => common_type(items)
            }
          } else {
            diagnostics.push(diag("listing index expects Int"))
            UnknownType
          }
        MappingType(entries) =>
          match lookup_mapping_value_type(entries, key) {
            Some(value) => value
            None => {
              diagnostics.push(diag("unknown mapping key type"))
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("subscript access expects Listing or Mapping"))
          UnknownType
        }
      }
    }
    AmendExpr(base_expr, members) =>
      match
        infer_expr_with_bindings(
          base_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(base_members) =>
          ObjectType(
            merge_type_members(
              base_members,
              infer_object_members(
                members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
              ),
            ),
          )
        ClassType(_, base_members) =>
          ObjectType(
            merge_type_members(
              base_members,
              infer_object_members(
                members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
              ),
            ),
          )
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("object amendment expects Object"))
          UnknownType
        }
      }
    Identifier(name) =>
      match
        resolve_binding_type(
          name, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(typ) => typ
        None => {
          diagnostics.push(diag("Cannot find property `\{name}`."))
          UnknownType
        }
      }
    CallExpr(callee, arguments) =>
      infer_call_expr(
        callee, arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
    LambdaExpr(parameters, _, return_type_name) => {
      let return_type = match return_type_name {
        Some(type_name) =>
          match type_from_annotation(type_name, type_env) {
            Some(typ) => typ
            None => {
              diagnostics.push(diag("Cannot find type `\{type_name}`."))
              UnknownType
            }
          }
        None => UnknownType
      }
      FunctionType(
        function_parameter_types(parameters, type_env, diagnostics),
        return_type,
      )
    }
    LetExpr(name, type_name, value_expr, body) => {
      let raw_type = infer_expr_with_bindings(
        value_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let typ = apply_type_annotation(
        type_name, raw_type, type_env, diagnostics,
      )
      let body_env = copy_type_bindings(env)
      let body_cache = copy_type_bindings(cache)
      body_env.push({ name, typ, alias_decl: None, bound: None })
      infer_expr_with_bindings(
        body, bindings, body_env, type_env, body_cache, stack, diagnostics, resolve_import,
      )
    }
    NonNullExpr(inner_expr) =>
      match
        infer_expr_with_bindings(
          inner_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        NullableType(inner) => inner
        NullType => {
          diagnostics.push(diag("non-null assertion rejects Null"))
          UnknownType
        }
        UnknownType => UnknownType
        typ => typ
      }
    UnaryExpr(op, inner_expr) => {
      let inner = infer_expr_with_bindings(
        inner_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match op {
        Negate =>
          if inner == IntType {
            IntType
          } else {
            diagnostics.push(diag("operator - expects Int operand"))
            UnknownType
          }
        Not =>
          if inner == BoolType {
            BoolType
          } else {
            diagnostics.push(diag("operator ! expects Boolean operand"))
            UnknownType
          }
      }
    }
    BinaryExpr(op, left_expr, right_expr) => {
      if op == Is {
        ignore(
          infer_expr_with_bindings(
            left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
        match right_expr {
          Identifier(name) =>
            match type_from_annotation(name, type_env) {
              Some(_) => return BoolType
              None => {
                diagnostics.push(diag("Cannot find type `\{name}`."))
                return UnknownType
              }
            }
          _ => return BoolType
        }
      }
      if op == As {
        ignore(
          infer_expr_with_bindings(
            left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
        match right_expr {
          Identifier(name) =>
            match type_from_annotation(name, type_env) {
              Some(typ) => return typ
              None => {
                diagnostics.push(diag("Cannot find type `\{name}`."))
                return UnknownType
              }
            }
          _ => return UnknownType
        }
      }
      if op == Pipe {
        diagnostics.push(diag("operator |> is parser-only"))
        return UnknownType
      }
      if op == And || op == Or {
        return infer_boolean_condition_expr(
          BinaryExpr(op, left_expr, right_expr),
          bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
      }
      let left = infer_expr_with_bindings(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right = infer_expr_with_bindings(
        right_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match op {
        Add | Subtract | Multiply | IntDivide | Modulo | Power =>
          // PKL-092: Int×Int stays Int. Add/Sub/Mul widen to Float when
          // any operand is Float.
          // PKL-111: Power widens to Float on any Float operand
          // (`2.0 ** 3 = 8.0`). IntDivide always returns Int but accepts
          // Float operands (Apple Pkl: `5.0 ~/ 3.0 == 1`). Modulo widens
          // to Float on any Float operand (Apple Pkl: `5.5 % 6.5 = 5.5`).
          if left == IntType && right == IntType {
            IntType
          } else if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            if op == IntDivide {
              IntType
            } else {
              FloatType
            }
          } else {
            diagnostics.push(
              diag("operator \{operator_name(op)} expects Int operands"),
            )
            UnknownType
          }
        Divide =>
          // PKL-092: `/` widens to Float unconditionally when both sides
          // are numeric, matching Apple Pkl's `5 / 2 == 2.5` semantics.
          if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            FloatType
          } else {
            diagnostics.push(diag("operator / expects numeric operands"))
            UnknownType
          }
        LessThan | LessOrEqual | GreaterThan | GreaterOrEqual =>
          // PKL-092: comparisons admit any Int / Float mix.
          if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            BoolType
          } else {
            diagnostics.push(
              diag("operator \{operator_name(op)} expects numeric operands"),
            )
            UnknownType
          }
        Equal | NotEqual =>
          // PKL-113: reject `a == b` / `a != b` when the operand types
          // are statically distinct. Today's typechecker passed every
          // pair through as BoolType, hiding `5 == "hi"` until runtime.
          if equality_compatible(left, right) {
            BoolType
          } else {
            diagnostics.push(
              diag(
                "operator \{operator_name(op)} expects operands of matching types",
              ),
            )
            UnknownType
          }
        And | Or => panic()
        NullCoalesce =>
          if left == NullType {
            right
          } else if left is NullableType(inner) {
            if right == NullType {
              left
            } else if type_accepts(inner, right) {
              inner
            } else if type_accepts(left, right) {
              left
            } else {
              UnknownType
            }
          } else if right == NullType || left == right {
            left
          } else {
            UnknownType
          }
        Is | As | Pipe => panic()
      }
    }
    ConditionalExpr(condition_expr, then_expr, else_expr) => {
      let condition = infer_boolean_condition_expr(
        condition_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      if condition != BoolType {
        diagnostics.push(diag("if condition expects Boolean"))
      }
      let then_cache = copy_type_bindings(cache)
      let else_cache = copy_type_bindings(cache)
      apply_positive_is_guard_expr(
        condition_expr, bindings, env, type_env, cache, then_cache, stack, diagnostics,
        resolve_import,
      )
      apply_negative_is_guard_expr(
        condition_expr, bindings, env, type_env, cache, else_cache, stack, diagnostics,
        resolve_import,
      )
      let then_type = infer_expr_with_bindings(
        then_expr, bindings, env, type_env, then_cache, stack, diagnostics, resolve_import,
      )
      let else_type = infer_expr_with_bindings(
        else_expr, bindings, env, type_env, else_cache, stack, diagnostics, resolve_import,
      )
      common_type([then_type, else_type])
    }
    ForGenerator(_, _, _, _, _, _) =>
      // for-generators only appear as synthetic `@for` object members and
      // are handled at object evaluation time. They never surface in
      // typechecking contexts; treat them as opaque object bodies.
      UnknownType
    ErrorExpr(message) => {
      diagnostics.push(diag(message))
      UnknownType
    }
    UnsupportedExpr => {
      diagnostics.push(diag("unsupported expression"))
      UnknownType
    }
    // PKL-136: a `WhenSpread` outside a Listing/Mapping body simply
    // forwards to the inner Expr's type. The Listing/Mapping literal
    // arms handle the spread itself (they collect inner element / entry
    // types from the wrapped ConditionalExpr).
    WhenSpread(inner) =>
      infer_expr_with_bindings(
        inner, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
    // PKL-103: `read?(uri)` returns `String?` — null when missing /
    // rejected, the read value otherwise. The typechecker collapses
    // to `NullableType(StringType)` so chained access sees a
    // nullable; further refinement (per-scheme types) is out of
    // scope for this slice.
    NullSafeCallExpr(_, args) => {
      for arg in args {
        ignore(
          infer_expr_with_bindings(
            arg, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
      }
      NullableType(StringType)
    }
    // PKL-128: an interpolated string always evaluates to a `String`,
    // regardless of the inner expression types. Walk the inner parts
    // so diagnostics from their typechecking still surface.
    InterpolatedString(parts) => {
      for part in parts {
        ignore(
          infer_expr_with_bindings(
            part, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
      }
      StringType
    }
  }
}

///|
fn infer_object_members(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[TypeMember] {
  let fields : Array[TypeMember] = []
  for field in members {
    let inferred = infer_expr_with_bindings(
      field.value,
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    fields.push({
      name: field.name,
      typ: apply_type_annotation(
        field.type_name,
        inferred,
        type_env,
        diagnostics,
      ),
    })
    push_constrained_type_annotation_expr_diagnostic(
      field.type_name,
      field.value,
      type_env,
      diagnostics,
    )
  }
  fields
}

///|
fn infer_imports(
  imports : Array[ImportDecl],
  env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  for decl in imports {
    match resolve_import(decl.uri) {
      Some(TypeOk(typ)) =>
        env.push({ name: decl.import_name, typ, alias_decl: None, bound: None })
      Some(TypeError(errors)) =>
        for error in errors {
          diagnostics.push(error)
        }
      None => diagnostics.push(diag("unresolved import \{decl.uri}"))
    }
  }
}

///|
fn relation_kind_name_for_typecheck(kind : ModuleRelationKind) -> String {
  match kind {
    ModuleAmends => "amends"
    ModuleExtends => "extends"
  }
}

///|
fn infer_module_relation(
  relation : ModuleRelation,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[TypeMember] {
  match resolve_import(relation.uri) {
    Some(TypeOk(ObjectType(members))) => members
    Some(TypeOk(ClassType(_, members))) => members
    Some(TypeOk(_)) => {
      diagnostics.push(
        diag(
          "module \{relation_kind_name_for_typecheck(relation.kind)} expects Object",
        ),
      )
      []
    }
    Some(TypeError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      []
    }
    None => {
      diagnostics.push(diag("unresolved import \{relation.uri}"))
      []
    }
  }
}

///|
fn infer_program(
  program : Program,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> Type {
  let env : Array[TypeBinding] = []
  let imported_types = if program_uses_qualified_type_name(program) {
    imported_type_bindings(program.imports, resolve_import_types)
  } else {
    []
  }
  // PKL-137: `amends "base.pkl"` / `extends "base.pkl"` brings the
  // base module's class / typealias declarations into the child's
  // unqualified type scope. Without this, the child sees the base's
  // property types (via `infer_module_relation`) but writing a
  // `class Test` from the base as a bare `Test` annotation in the
  // child errors with `Cannot find type `Test``.
  let relation_types : Array[TypeBinding] = []
  match program.module_relation {
    Some(relation) =>
      match resolve_import_types(relation.uri) {
        Some(exports) =>
          for type_export in exports {
            relation_types.push({
              name: type_export.name,
              typ: type_export.typ,
              alias_decl: None,
              bound: None,
            })
          }
        None => ()
      }
    None => ()
  }
  let combined_imports : Array[TypeBinding] = []
  for binding in imported_types {
    combined_imports.push(binding)
  }
  for binding in relation_types {
    combined_imports.push(binding)
  }
  let type_env = collect_declared_types_with_imports(
    program.declarations,
    diagnostics,
    combined_imports,
  )
  push_constrained_class_property_default_diagnostics(
    program.declarations,
    diagnostics,
  )
  push_constrained_callable_return_body_diagnostics(
    program.declarations,
    type_env,
    diagnostics,
  )
  // PKL-117: enforce abstract-method coverage on concrete classes and
  // override-direction subtype rules on every overriding method. The
  // pass walks only locally-declared parents — abstract methods that
  // arrive through an imported parent stay deferred; cross-module
  // visibility is a separate slice (PKL-118 currently tracks it).
  push_inheritance_hardening_diagnostics(
    program.declarations,
    type_env,
    diagnostics,
  )
  let cache : Array[TypeBinding] = []
  let fields : Array[TypeMember] = []
  let bindings = all_program_bindings(program)
  infer_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    // PKL-140: abstract / external slots carry a synthetic `NullLiteral`
    // value the typechecker would otherwise reject against the declared
    // type. Skip validation but keep the slot's type in the recorded
    // module shape so cross-module references still see it.
    if binding.abstract_slot {
      let slot_type = match binding.type_name {
        Some(text) =>
          match type_from_annotation(text, type_env) {
            Some(t) => t
            None => UnknownType
          }
        None => UnknownType
      }
      fields.push({ name: binding.name, typ: slot_type })
      continue
    }
    match
      resolve_binding_type(
        binding.name,
        bindings,
        env,
        type_env,
        cache,
        [],
        diagnostics,
        resolve_import,
      ) {
      Some(typ) => {
        push_user_defined_constrained_type_annotation_expr_diagnostic(
          binding.type_name,
          binding.value,
          program.declarations,
          diagnostics,
        )
        push_constrained_class_property_expr_diagnostics(
          binding.value,
          program.declarations,
          diagnostics,
        )
        if binding.exported {
          fields.push({ name: binding.name, typ })
        }
      }
      None => ()
    }
  }
  // PKL-118: mirror the eval-side hidden-prefixed function export so
  // a cross-module reference like `Base.helper(x)` resolves at the
  // typecheck layer. The function's lambda type flows through the
  // normal inference path so call-site argument checks line up with
  // the local-call behaviour. Hidden-prefixed entries don't render
  // in the module's downstream surface, so PCF / JSON output stays
  // unchanged.
  for declaration in program.declarations {
    match declaration {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) => {
            let lambda_expr = LambdaExpr(
              function_decl.parameters,
              body,
              function_decl.return_type_name,
            )
            let inferred = infer_expr_with_bindings(
              lambda_expr,
              bindings,
              env,
              type_env,
              cache,
              [],
              diagnostics,
              resolve_import,
            )
            fields.push({
              name: hidden_member_name(function_decl.name),
              typ: inferred,
            })
          }
          None => ()
        }
      _ => ()
    }
  }
  match program.body {
    Some(expr) =>
      infer_expr_with_bindings(
        expr,
        bindings,
        env,
        type_env,
        cache,
        [],
        diagnostics,
        resolve_import,
      )
    None if program.module_relation is Some(relation) =>
      ObjectType(
        merge_type_members(
          infer_module_relation(relation, diagnostics, resolve_import),
          fields,
        ),
      )
    None if fields.length() > 0 => ObjectType(fields)
    // PKL-140: declarations-only modules (Apple Pkl stdlib pattern)
    // typecheck to the empty ObjectType. The class / typealias /
    // function declarations are still tracked in program.declarations
    // and remain available to importers.
    None => ObjectType([])
  }
}
