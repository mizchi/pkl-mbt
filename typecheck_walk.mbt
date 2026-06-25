///|
fn type_name_is_qualified(name : String) -> Bool {
  name.find(".") is Some(_)
}

///|
fn optional_type_name_is_qualified(name : String?) -> Bool {
  match name {
    Some(value) => type_name_is_qualified(value)
    None => false
  }
}

///|
fn expr_uses_qualified_type_name(expr : Expr) -> Bool {
  match expr {
    TypedObjectLiteral(type_name, members) =>
      type_name_is_qualified(type_name) ||
      object_members_use_qualified_type_name(members)
    ObjectLiteral(members) => object_members_use_qualified_type_name(members)
    ListingLiteral(elements) => {
      for element in elements {
        if expr_uses_qualified_type_name(element) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_uses_qualified_type_name(entry.key) ||
          expr_uses_qualified_type_name(entry.value) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      expr_uses_qualified_type_name(target)
    SubscriptAccess(target, key) =>
      expr_uses_qualified_type_name(target) ||
      expr_uses_qualified_type_name(key)
    AmendExpr(base, members) =>
      expr_uses_qualified_type_name(base) ||
      object_members_use_qualified_type_name(members)
    CallExpr(callee, arguments) => {
      if expr_uses_qualified_type_name(callee) {
        return true
      }
      for argument in arguments {
        if expr_uses_qualified_type_name(argument) {
          return true
        }
      }
      false
    }
    LambdaExpr(parameters, body, return_type_name) => {
      if optional_type_name_is_qualified(return_type_name) ||
        function_parameters_use_qualified_type_name(parameters) {
        return true
      }
      expr_uses_qualified_type_name(body)
    }
    NonNullExpr(inner) | UnaryExpr(_, inner) =>
      expr_uses_qualified_type_name(inner)
    BinaryExpr(_, left, right) =>
      expr_uses_qualified_type_name(left) ||
      expr_uses_qualified_type_name(right)
    ConditionalExpr(condition, then_expr, else_expr) =>
      expr_uses_qualified_type_name(condition) ||
      expr_uses_qualified_type_name(then_expr) ||
      expr_uses_qualified_type_name(else_expr)
    _ => false
  }
}

///|
fn object_members_use_qualified_type_name(
  members : Array[ObjectMember],
) -> Bool {
  for object_member in members {
    if optional_type_name_is_qualified(object_member.type_name) ||
      expr_uses_qualified_type_name(object_member.value) {
      return true
    }
  }
  false
}

///|
fn function_parameters_use_qualified_type_name(
  parameters : Array[FunctionParameter],
) -> Bool {
  for parameter in parameters {
    if optional_type_name_is_qualified(parameter.type_name) {
      return true
    }
  }
  false
}

///|
fn function_decl_uses_qualified_type_name(function_decl : FunctionDecl) -> Bool {
  if optional_type_name_is_qualified(function_decl.return_type_name) ||
    function_parameters_use_qualified_type_name(function_decl.parameters) {
    return true
  }
  match function_decl.body {
    Some(body) => expr_uses_qualified_type_name(body)
    None => false
  }
}

///|
fn class_properties_use_qualified_type_name(
  properties : Array[ClassProperty],
) -> Bool {
  for property in properties {
    if optional_type_name_is_qualified(property.type_name) {
      return true
    }
    match property.value {
      Some(value) => if expr_uses_qualified_type_name(value) { return true }
      None => ()
    }
  }
  false
}

///|
fn class_methods_use_qualified_type_name(methods : Array[FunctionDecl]) -> Bool {
  for class_method in methods {
    if function_decl_uses_qualified_type_name(class_method) {
      return true
    }
  }
  false
}

///|
fn declaration_uses_qualified_type_name(declaration : Declaration) -> Bool {
  match declaration {
    ClassDeclaration(class_decl) => {
      if optional_type_name_is_qualified(class_decl.parent_name) {
        return true
      }
      class_properties_use_qualified_type_name(class_decl.properties) ||
      class_methods_use_qualified_type_name(class_decl.methods)
    }
    FunctionDeclaration(function_decl) =>
      function_decl_uses_qualified_type_name(function_decl)
    TypeAliasDeclaration(type_alias) =>
      type_name_is_qualified(type_alias.target)
  }
}

///|
fn program_uses_qualified_type_name(program : Program) -> Bool {
  for declaration in program.declarations {
    if declaration_uses_qualified_type_name(declaration) {
      return true
    }
  }
  for binding in program.bindings {
    if optional_type_name_is_qualified(binding.type_name) ||
      expr_uses_qualified_type_name(binding.value) {
      return true
    }
  }
  match program.body {
    Some(body) => expr_uses_qualified_type_name(body)
    None => false
  }
}

///|
fn narrow_positive_is_guard_type(original : Type, guard_type : Type) -> Type? {
  match original {
    UnionType(options) => {
      let narrowed : Array[Type] = []
      for option in options {
        if type_accepts(guard_type, option) {
          push_unique_type(narrowed, option)
        }
      }
      if narrowed.length() == 0 {
        None
      } else {
        Some(make_union_type(narrowed))
      }
    }
    NullableType(inner) =>
      if type_accepts(guard_type, inner) {
        Some(inner)
      } else if guard_type == NullType {
        Some(NullType)
      } else {
        None
      }
    _ =>
      if type_accepts(guard_type, original) {
        Some(original)
      } else if type_accepts(original, guard_type) {
        Some(guard_type)
      } else {
        None
      }
  }
}

///|
fn narrow_negative_is_guard_type(original : Type, guard_type : Type) -> Type? {
  match original {
    UnionType(options) => {
      let narrowed : Array[Type] = []
      let mut changed = false
      for option in options {
        if type_accepts(guard_type, option) {
          changed = true
        } else {
          push_unique_type(narrowed, option)
        }
      }
      if changed && narrowed.length() > 0 {
        Some(make_union_type(narrowed))
      } else {
        None
      }
    }
    NullableType(inner) =>
      if type_accepts(guard_type, inner) {
        Some(NullType)
      } else if guard_type == NullType {
        Some(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
fn push_narrowed_type_binding(
  name : String,
  guard_type : Type,
  positive : Bool,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match
    resolve_binding_type(
      name, bindings, env, type_env, source_cache, stack, diagnostics, resolve_import,
    ) {
    Some(original_type) => {
      let narrowed = if positive {
        narrow_positive_is_guard_type(original_type, guard_type)
      } else {
        narrow_negative_is_guard_type(original_type, guard_type)
      }
      match narrowed {
        Some(typ) =>
          target_cache.push({ name, typ, alias_decl: None, bound: None })
        None => ()
      }
    }
    None => ()
  }
}

///|
fn apply_positive_is_guard_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match expr {
    BinaryExpr(Is, Identifier(name), Identifier(type_name)) =>
      match type_from_annotation(type_name, type_env) {
        Some(guard_type) =>
          push_narrowed_type_binding(
            name, guard_type, true, bindings, env, type_env, source_cache, target_cache,
            stack, diagnostics, resolve_import,
          )
        None => ()
      }
    BinaryExpr(Equal, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(Equal, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(And, left, right) => {
      apply_positive_is_guard_expr(
        left, bindings, env, type_env, source_cache, target_cache, stack, diagnostics,
        resolve_import,
      )
      apply_positive_is_guard_expr(
        right, bindings, env, type_env, target_cache, target_cache, stack, diagnostics,
        resolve_import,
      )
    }
    _ => ()
  }
}

///|
fn apply_negative_is_guard_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match expr {
    BinaryExpr(Is, Identifier(name), Identifier(type_name)) =>
      match type_from_annotation(type_name, type_env) {
        Some(guard_type) =>
          push_narrowed_type_binding(
            name, guard_type, false, bindings, env, type_env, source_cache, target_cache,
            stack, diagnostics, resolve_import,
          )
        None => ()
      }
    BinaryExpr(Equal, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(Equal, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    _ => ()
  }
}

///|
fn all_program_bindings(program : Program) -> Array[Binding] {
  let bindings : Array[Binding] = []
  for decl in program.declarations {
    match decl {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) =>
            bindings.push({
              name: function_decl.name,
              type_name: None,
              value: LambdaExpr(
                function_decl.parameters,
                body,
                function_decl.return_type_name,
              ),
              exported: false,
              is_const: true,
              annotations: function_decl.annotations,
              abstract_slot: false,
              sibling_slot: false,
            })
          None => ()
        }
      _ => ()
    }
  }
  for binding in program.bindings {
    bindings.push(binding)
  }
  bindings
}

///|
fn class_properties_to_members(
  properties : Array[ClassProperty],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  let members : Array[TypeMember] = []
  for property in properties {
    let typ = match property.type_name {
      Some(type_name) =>
        match type_from_annotation(type_name, type_env) {
          Some(resolved) => resolved
          None => {
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
            UnknownType
          }
        }
      None =>
        match property.value {
          Some(value) =>
            infer_expr_with_bindings(
              value,
              [],
              [],
              type_env,
              [],
              [],
              diagnostics,
              fn(_) { None },
            )
          None => UnknownType
        }
    }
    let member_type = match property.value {
      Some(_) => DefaultedType(typ)
      None => typ
    }
    members.push({ name: property.name, typ: member_type })
  }
  members
}

///|
fn class_methods_to_members(
  methods : Array[FunctionDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  let members : Array[TypeMember] = []
  for class_method in methods {
    members.push({
      name: class_method.name,
      typ: DefaultedType(
        function_signature_type(class_method, type_env, diagnostics),
      ),
    })
  }
  members
}

///|
fn push_class_method_receiver_bindings(
  cache : Array[TypeBinding],
  class_name : String,
  members : Array[TypeMember],
) -> Unit {
  for type_member in members {
    cache.push({
      name: type_member.name,
      typ: member_contract_type(type_member.typ),
      alias_decl: None,
      bound: None,
    })
  }
  cache.push({
    name: "this",
    typ: ClassType(class_name, members),
    alias_decl: None,
    bound: None,
  })
}

///|
fn validate_class_method_body(
  class_name : String,
  members : Array[TypeMember],
  function_decl : FunctionDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match function_decl.body {
    Some(body) => {
      let method_cache : Array[TypeBinding] = []
      push_class_method_receiver_bindings(method_cache, class_name, members)
      let parameter_types = function_parameter_types(
        function_decl.parameters,
        type_env,
        diagnostics,
      )
      for i = 0; i < function_decl.parameters.length(); i = i + 1 {
        method_cache.push({
          name: function_decl.parameters[i].name,
          typ: parameter_types[i],
          alias_decl: None,
          bound: None,
        })
      }
      let inferred_return = infer_expr_with_bindings(
        body,
        [],
        [],
        type_env,
        method_cache,
        [],
        diagnostics,
        fn(_) { None },
      )
      match function_decl.return_type_name {
        Some(type_name) =>
          match type_from_annotation(type_name, type_env) {
            Some(expected) =>
              if !type_accepts(expected, inferred_return) {
                diagnostics.push(
                  diag(
                    "method \{class_name}.\{function_decl.name} return annotation \{type_name} does not accept \{render_type(inferred_return)}",
                  ),
                )
              }
            None => diagnostics.push(diag("Cannot find type `\{type_name}`."))
          }
        None => ()
      }
    }
    None => ()
  }
}

///|
fn validate_class_method_bodies(
  class_name : String,
  members : Array[TypeMember],
  methods : Array[FunctionDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for class_method in methods {
    validate_class_method_body(
      class_name, members, class_method, type_env, diagnostics,
    )
  }
}

///|
fn class_decl_to_members(
  class_decl : ClassDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  // PKL-089 introduced the scoped type environment so `class Box<T>`
  // body uses of T resolve. PKL-110 sharpens the binding from
  // UnknownType to TypeVariable(name) so the call-site substitution
  // pass can later rewrite each T against the concrete argument type.
  let scoped_env = if class_decl.type_parameters.length() == 0 {
    type_env
  } else {
    let next : Array[TypeBinding] = []
    // PKL-116: thread declared bounds through the class-scoped type_env
    // so methods and properties resolved against `T` participate in the
    // same bound check as standalone functions. Bounds resolve against
    // the outer `type_env` (the class binding itself is not yet in
    // scope, matching PKL-110's TypeVariable injection order).
    for i = 0; i < class_decl.type_parameters.length(); i = i + 1 {
      let parameter = class_decl.type_parameters[i]
      let bound_text = if i < class_decl.type_parameter_bounds.length() {
        class_decl.type_parameter_bounds[i]
      } else {
        None
      }
      let bound = match bound_text {
        Some(text) => type_from_annotation(text, type_env)
        None => None
      }
      next.push({
        name: parameter,
        typ: TypeVariable(parameter),
        alias_decl: None,
        bound,
      })
    }
    for binding in type_env {
      next.push(binding)
    }
    next
  }
  let own_members = merge_type_members(
    class_properties_to_members(class_decl.properties, scoped_env, diagnostics),
    class_methods_to_members(class_decl.methods, scoped_env, diagnostics),
  )
  let members = match class_decl.parent_name {
    Some(parent_name) =>
      match lookup_type(scoped_env, parent_name) {
        Some(ClassType(_, base_members)) =>
          merge_type_members(base_members, own_members)
        Some(_) => {
          diagnostics.push(
            diag("class \{class_decl.name} extends non-class \{parent_name}"),
          )
          own_members
        }
        None => {
          diagnostics.push(diag("Cannot find type `\{parent_name}`."))
          own_members
        }
      }
    None => own_members
  }
  validate_class_method_bodies(
    class_decl.name,
    members,
    class_decl.methods,
    scoped_env,
    diagnostics,
  )
  members
}

///|
fn collect_declared_types(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Array[TypeBinding] {
  collect_declared_types_with_imports(declarations, diagnostics, [])
}

///|
fn collect_declared_types_with_imports(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  imported_types : Array[TypeBinding],
) -> Array[TypeBinding] {
  let type_env = copy_type_bindings(imported_types)
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        type_env.push({
          name: class_decl.name,
          typ: ClassType(class_decl.name, []),
          alias_decl: None,
          bound: None,
        })
      TypeAliasDeclaration(type_alias) =>
        // PKL-137: fall back to `type_from_annotation` so union /
        // constrained / nullable / generic alias targets resolve too.
        // `builtin_type_from_annotation` alone misses
        // `("draft" | "review" | "approved")` and similar; the richer
        // resolver participates in the partially built `type_env`
        // (later aliases can reference earlier ones).
        match
          (
            builtin_type_from_annotation(type_alias.target),
            type_from_annotation(type_alias.target, type_env),
          ) {
          (Some(typ), _) | (None, Some(typ)) =>
            type_env.push({
              name: type_alias.name,
              typ,
              alias_decl: if type_alias.type_parameters.length() > 0 {
                Some(type_alias)
              } else {
                None
              },
              bound: None,
            })
          (None, None) => ()
        }
      // PKL-090 flattened function-level type parameters into the
      // module-level type_env so annotations like `(x: T): T` resolve.
      // PKL-110 binds each parameter to TypeVariable(name) instead of
      // UnknownType: now signatures carry a marker that the call-site
      // substitution pass can match on (`identity(7)` binds T = Int and
      // rewrites the return type before it propagates outward).
      FunctionDeclaration(function_decl) =>
        // PKL-116: resolve each parameter's optional bound text in the
        // current type_env so the binding carries a fully resolved
        // bound Type. `unify_for_substitution` consults `bound` to
        // reject call sites whose argument does not flow through the
        // bound. Unbounded parameters keep `bound = None`.
        for i = 0; i < function_decl.type_parameters.length(); i = i + 1 {
          let parameter = function_decl.type_parameters[i]
          let bound_text = if i < function_decl.type_parameter_bounds.length() {
            function_decl.type_parameter_bounds[i]
          } else {
            None
          }
          let bound = match bound_text {
            Some(text) => type_from_annotation(text, type_env)
            None => None
          }
          type_env.push({
            name: parameter,
            typ: TypeVariable(parameter),
            alias_decl: None,
            bound,
          })
        }
    }
  }
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        type_env.push({
          name: class_decl.name,
          typ: ClassType(
            class_decl.name,
            class_decl_to_members(class_decl, type_env, diagnostics),
          ),
          alias_decl: None,
          bound: None,
        })
      TypeAliasDeclaration(type_alias) => {
        // PKL-115: capture the original decl on the binding when the
        // typealias is generic so use-site substitution can rewrite
        // the target text. For non-generic aliases the previous shape
        // is preserved by leaving `alias_decl` as `None`. Inject the
        // declared type parameters as scoped TypeVariables so the
        // target text can resolve at definition time even before any
        // instantiation site is seen.
        let scoped_type_env = copy_type_bindings(type_env)
        for parameter in type_alias.type_parameters {
          scoped_type_env.push({
            name: parameter,
            typ: TypeVariable(parameter),
            alias_decl: None,
            bound: None,
          })
        }
        match
          type_from_alias_target_annotation(type_alias.target, scoped_type_env) {
          Some(typ) =>
            type_env.push({
              name: type_alias.name,
              typ,
              alias_decl: if type_alias.type_parameters.length() > 0 {
                Some(type_alias)
              } else {
                None
              },
              bound: None,
            })
          None =>
            diagnostics.push(diag("Cannot find type `\{type_alias.target}`."))
        }
      }
      FunctionDeclaration(_) => ()
    }
  }
  type_env
}

///|
fn type_exports_from_parse_result(parsed : ParseResult) -> Array[TypeExport] {
  let diagnostics : Array[Diagnostic] = []
  let type_env = collect_declared_types(
    parsed.program.declarations,
    diagnostics,
  )
  let exports : Array[TypeExport] = []
  for declaration in parsed.program.declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        match lookup_type(type_env, class_decl.name) {
          Some(typ) => exports.push({ name: class_decl.name, typ })
          None => ()
        }
      // PKL-137: typealiases participate in the importing / amending
      // module's type scope the same way classes do. pkspec's
      // `Spec.pkl amends Test.pkl` references `Id`, `ReviewStatus`,
      // `Severity`, `IsoDate`, etc. — all typealiases declared in
      // Test.pkl. Export their resolved types so the relation /
      // import lookup populates the child's type env with them.
      TypeAliasDeclaration(type_alias) =>
        match lookup_type(type_env, type_alias.name) {
          Some(typ) => exports.push({ name: type_alias.name, typ })
          None => ()
        }
      FunctionDeclaration(_) => ()
    }
  }
  exports
}
