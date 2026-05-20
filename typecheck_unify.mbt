///|
/// that PKL-118 still tracks separately.
fn push_inheritance_hardening_diagnostics(
  declarations : Array[Declaration],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let by_name : Map[String, ClassDecl] = Map([], capacity=8)
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => by_name[class_decl.name] = class_decl
      _ => ()
    }
  }
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => {
        if !class_decl.is_abstract {
          enforce_abstract_method_coverage(class_decl, by_name, diagnostics)
        }
        enforce_method_override_directions(
          class_decl, by_name, type_env, diagnostics,
        )
      }
      _ => ()
    }
  }
}

///|
/// Walk the parent chain collecting abstract methods that the
/// concrete `class_decl` (or some ancestor below the declaring
/// class) must override. Methods present in any descendant between
/// the abstract declaration and `class_decl` count as overrides.
fn enforce_abstract_method_coverage(
  class_decl : ClassDecl,
  by_name : Map[String, ClassDecl],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let descendant_methods : Array[String] = []
  for class_method in class_decl.methods {
    descendant_methods.push(class_method.name)
  }
  let mut current : ClassDecl? = match class_decl.parent_name {
    Some(name) => by_name.get(name)
    None => None
  }
  while current is Some(parent_decl) {
    for parent_method in parent_decl.methods {
      if parent_method.is_abstract &&
        !array_contains_string(descendant_methods, parent_method.name) {
        diagnostics.push(
          diag(
            "Class `\{class_decl.name}` does not implement abstract method `\{parent_method.name}` inherited from `\{parent_decl.name}`.",
          ),
        )
      }
    }
    for parent_method in parent_decl.methods {
      if !array_contains_string(descendant_methods, parent_method.name) {
        descendant_methods.push(parent_method.name)
      }
    }
    current = match parent_decl.parent_name {
      Some(name) => by_name.get(name)
      None => None
    }
  }
}

///|
/// For each method in `class_decl`, look up a parent method with the
/// same name and verify return-type covariance and parameter-type
/// contravariance. Unresolved type annotations (`Cannot find type`)
/// don't push a duplicate diagnostic — they were already surfaced by
/// the class-member typecheck and skipping here keeps the noise
/// floor low.
fn enforce_method_override_directions(
  class_decl : ClassDecl,
  by_name : Map[String, ClassDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for class_method in class_decl.methods {
    let parent_method = find_inherited_method(
      class_decl,
      class_method.name,
      by_name,
    )
    match parent_method {
      Some((parent_decl, ancestor_method)) => {
        // Return type: covariant. Child must be a subtype of parent.
        match
          (ancestor_method.return_type_name, class_method.return_type_name) {
          (Some(parent_ret), Some(child_ret)) =>
            match
              (
                type_from_annotation(parent_ret, type_env),
                type_from_annotation(child_ret, type_env),
              ) {
              (Some(parent_type), Some(child_type)) =>
                if !type_accepts(parent_type, child_type) {
                  diagnostics.push(
                    diag(
                      "Method `\{class_decl.name}.\{class_method.name}` return type `\{child_ret}` is not a subtype of `\{parent_decl.name}.\{ancestor_method.name}` return type `\{parent_ret}`.",
                    ),
                  )
                }
              _ => ()
            }
          _ => ()
        }
        let parent_params = ancestor_method.parameters
        let child_params = class_method.parameters
        if parent_params.length() == child_params.length() {
          for i = 0; i < parent_params.length(); i = i + 1 {
            match (parent_params[i].type_name, child_params[i].type_name) {
              (Some(parent_param), Some(child_param)) =>
                match
                  (
                    type_from_annotation(parent_param, type_env),
                    type_from_annotation(child_param, type_env),
                  ) {
                  (Some(parent_type), Some(child_type)) =>
                    if !type_accepts(child_type, parent_type) {
                      diagnostics.push(
                        diag(
                          "Method `\{class_decl.name}.\{class_method.name}` parameter `\{child_params[i].name}` type `\{child_param}` is not a supertype of `\{parent_decl.name}.\{ancestor_method.name}` parameter type `\{parent_param}`.",
                        ),
                      )
                    }
                  _ => ()
                }
              _ => ()
            }
          }
        }
      }
      None => ()
    }
  }
}

///|
/// Look up the nearest ancestor that declares a method named
/// `method_name`. Returns the declaring class along with the method
/// itself so the diagnostic can name both. `None` when no ancestor
/// declares the method (this method is a new addition, not an
/// override).
fn find_inherited_method(
  class_decl : ClassDecl,
  method_name : String,
  by_name : Map[String, ClassDecl],
) -> (ClassDecl, FunctionDecl)? {
  let mut current : ClassDecl? = match class_decl.parent_name {
    Some(name) => by_name.get(name)
    None => None
  }
  while current is Some(parent_decl) {
    for parent_method in parent_decl.methods {
      if parent_method.name == method_name {
        return Some((parent_decl, parent_method))
      }
    }
    current = match parent_decl.parent_name {
      Some(name) => by_name.get(name)
      None => None
    }
  }
  None
}

///|
fn array_contains_string(items : Array[String], needle : String) -> Bool {
  for item in items {
    if item == needle {
      return true
    }
  }
  false
}

///|
fn type_from_alias_target_annotation(
  name : String,
  type_env : Array[TypeBinding],
) -> Type? {
  match type_from_annotation(name, type_env) {
    Some(typ) =>
      if pkl_constrained_type_annotation_has_supported_constraint(name) {
        Some(ConstrainedType(name, typ))
      } else {
        Some(typ)
      }
    None => None
  }
}

///|
fn parameter_type_from_annotation(
  name : String,
  type_env : Array[TypeBinding],
) -> Type? {
  match type_from_annotation(name, type_env) {
    Some(typ) =>
      if pkl_constrained_type_annotation_has_supported_constraint(name) ||
        typ is ConstrainedType(_, _) {
        Some(ConstrainedType(name, member_contract_type(typ)))
      } else {
        Some(typ)
      }
    None => None
  }
}

///|
fn type_accepts(expected : Type, inferred : Type) -> Bool {
  if expected == inferred {
    return true
  }
  match (expected, inferred) {
    (UnknownType, _) => true
    // PKL-110: a free type parameter accepts any incoming type at
    // unification time. The substitution pass at the call site fills in
    // the concrete type before the return value flows on; if no call site
    // exists (e.g. the body refers to T directly) it stays free.
    (TypeVariable(_), _) => true
    (_, TypeVariable(_)) => true
    // PKL-133: `Any` is Pkl's top type — every value flows through it.
    // The relation is symmetric so the same value can flow into and out
    // of `Any` (e.g. `x: Any = 5` and `n: Int = x as Int` once `as` lands).
    (AnyType, _) => true
    (_, AnyType) => true
    (ConstrainedType(_, expected_inner), actual) =>
      type_accepts(expected_inner, actual)
    (expected, ConstrainedType(_, actual_inner)) =>
      type_accepts(expected, actual_inner)
    (ObjectType(_), ObjectType(_)) => true
    (ObjectType(_), ClassType(_, _)) => true
    (UnionType(expected_options), UnionType(actual_options)) => {
      let mut ok = true
      for actual in actual_options {
        if !type_accepts(UnionType(expected_options), actual) {
          ok = false
        }
      }
      ok
    }
    (UnionType(expected_options), actual) => {
      let mut ok = false
      for expected_option in expected_options {
        if type_accepts(expected_option, actual) {
          ok = true
        }
      }
      ok
    }
    (expected, UnionType(actual_options)) => {
      let mut ok = true
      for actual in actual_options {
        if !type_accepts(expected, actual) {
          ok = false
        }
      }
      ok
    }
    (DefaultedType(expected_inner), actual) =>
      type_accepts(expected_inner, member_contract_type(actual))
    (expected, DefaultedType(actual_inner)) =>
      type_accepts(expected, actual_inner)
    (NullableType(_), NullType) => true
    (NullableType(expected_inner), NullableType(actual_inner)) =>
      type_accepts(expected_inner, actual_inner)
    (NullableType(expected_inner), actual) =>
      type_accepts(expected_inner, actual)
    (ClassType(_, expected_members), ObjectType(actual_members)) => {
      let mut ok = true
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            if !type_accepts(member_contract_type(expected_member.typ), actual) {
              ok = false
            }
          None =>
            if !is_defaulted_member_type(expected_member.typ) {
              ok = false
            }
        }
      }
      ok
    }
    (ListingType(expected_items), ListingType(actual_items)) => {
      if expected_items.length() == 0 {
        return true
      }
      let expected_item = common_type(expected_items)
      let mut ok = true
      for actual_item in actual_items {
        if !type_accepts(expected_item, actual_item) {
          ok = false
        }
      }
      ok
    }
    // PKL-119c: Set is invariant on element shape but accepts the
    // same element-wise widening as Listing — an empty expected
    // parameter list means "any element type".
    (SetType(expected_items), SetType(actual_items)) => {
      if expected_items.length() == 0 {
        return true
      }
      let expected_item = common_type(expected_items)
      let mut ok = true
      for actual_item in actual_items {
        if !type_accepts(expected_item, actual_item) {
          ok = false
        }
      }
      ok
    }
    // PKL-119d: Map follows the same widening rule as MappingType —
    // empty expected entries accept any key/value. Otherwise the
    // expected key / value common-types must accept each actual
    // entry's slots.
    (MapType(expected_entries), MapType(actual_entries)) => {
      if expected_entries.length() == 0 {
        return true
      }
      let expected_key = common_type(
        expected_entries.map(fn(entry) { entry.key }),
      )
      let expected_value = common_type(
        expected_entries.map(fn(entry) { entry.value }),
      )
      let mut ok = true
      for actual_entry in actual_entries {
        if !type_accepts(expected_key, actual_entry.key) ||
          !type_accepts(expected_value, actual_entry.value) {
          ok = false
        }
      }
      ok
    }
    // PKL-137: an empty `new {}` literal infers to `ObjectType([])` at
    // parse time. PKL-138's eval-side coercion projects the runtime
    // value to `ListingValue([])` / `MappingValue([])` based on the
    // binding annotation; mirror the same coercion here so the
    // typechecker accepts `tests: Listing<Test> = new {}` and
    // `m: Mapping<K, V> = new {}` cleanly.
    (ListingType(_), ObjectType(members)) => members.length() == 0
    (MappingType(_), ObjectType(members)) => members.length() == 0
    (MappingType(expected_entries), MappingType(actual_entries)) => {
      if expected_entries.length() == 0 {
        return true
      }
      let expected_key = common_type(
        expected_entries.map(fn(entry) { entry.key }),
      )
      let expected_value = common_type(
        expected_entries.map(fn(entry) { entry.value }),
      )
      let mut ok = true
      for actual_entry in actual_entries {
        if !type_accepts(expected_key, actual_entry.key) ||
          !type_accepts(expected_value, actual_entry.value) {
          ok = false
        }
      }
      ok
    }
    (
      FunctionType(expected_parameters, expected_return),
      FunctionType(actual_parameters, actual_return),
    ) => {
      if expected_parameters.length() != actual_parameters.length() {
        return false
      }
      let mut ok = type_accepts(expected_return, actual_return)
      for i = 0; i < expected_parameters.length(); i = i + 1 {
        if !type_accepts(expected_parameters[i], actual_parameters[i]) {
          ok = false
        }
      }
      ok
    }
    _ => false
  }
}

///|
// PKL-113: Equality (`==` / `!=`) admits a wider compatibility relation
// than `type_accepts`. Two operands typecheck under equality when they
// share a base shape: same primitive, numeric mix (Int / Float),
// nullable / non-null with matching base, or any structural pair where
// runtime equality is meaningful (object / class, listing / listing).
// The relation stays symmetric — `a == b` and `b == a` must agree —
// so the helper normalizes wrappers (`ConstrainedType`, `DefaultedType`)
// before pattern-matching.
fn equality_compatible(left : Type, right : Type) -> Bool {
  let l = equality_unwrap_type(left)
  let r = equality_unwrap_type(right)
  if l == r {
    return true
  }
  match (l, r) {
    (UnknownType, _) | (_, UnknownType) => true
    (TypeVariable(_), _) | (_, TypeVariable(_)) => true
    // PKL-133: `Any` participates in equality on either side.
    (AnyType, _) | (_, AnyType) => true
    (NullType, NullableType(_)) | (NullableType(_), NullType) => true
    (NullableType(inner), other) | (other, NullableType(inner)) =>
      equality_compatible(inner, other)
    (IntType, FloatType) | (FloatType, IntType) => true
    (ClassType(name_l, _), ClassType(name_r, _)) => name_l == name_r
    (ClassType(_, _), ObjectType(_)) | (ObjectType(_), ClassType(_, _)) => true
    (ObjectType(_), ObjectType(_)) => true
    (ListingType(_), ListingType(_)) => true
    (MappingType(_), MappingType(_)) => true
    (UnionType(options), other) | (other, UnionType(options)) => {
      let mut ok = false
      for option in options {
        if equality_compatible(option, other) {
          ok = true
        }
      }
      ok
    }
    _ => false
  }
}

///|
fn equality_unwrap_type(typ : Type) -> Type {
  match typ {
    ConstrainedType(_, inner) => equality_unwrap_type(inner)
    DefaultedType(inner) => equality_unwrap_type(inner)
    _ => typ
  }
}

///|
// PKL-110: Substitution table for generic type parameters. A pair
// `(name, typ)` means "every TypeVariable(name) site rewrites to typ".
// Built incrementally by `unify_for_substitution` and consumed by
// `substitute_type`.
priv struct TypeSubstitution {
  name : String
  typ : Type
}

///|
fn substitution_lookup(subs : Array[TypeSubstitution], name : String) -> Type? {
  let mut found : Type? = None
  for entry in subs {
    if entry.name == name {
      found = Some(entry.typ)
    }
  }
  found
}

///|
fn substitute_type_member(
  field : TypeMember,
  subs : Array[TypeSubstitution],
) -> TypeMember {
  { name: field.name, typ: substitute_type(field.typ, subs) }
}

///|
fn substitute_type_entry(
  entry : TypeEntry,
  subs : Array[TypeSubstitution],
) -> TypeEntry {
  {
    key: substitute_type(entry.key, subs),
    value: substitute_type(entry.value, subs),
  }
}

///|
fn substitute_type(typ : Type, subs : Array[TypeSubstitution]) -> Type {
  if subs.length() == 0 {
    return typ
  }
  match typ {
    TypeVariable(name) =>
      match substitution_lookup(subs, name) {
        Some(resolved) => resolved
        None => typ
      }
    ObjectType(members) =>
      ObjectType(members.map(fn(m) { substitute_type_member(m, subs) }))
    ClassType(name, members) =>
      ClassType(name, members.map(fn(m) { substitute_type_member(m, subs) }))
    ListingType(items) =>
      ListingType(items.map(fn(t) { substitute_type(t, subs) }))
    MappingType(entries) =>
      MappingType(entries.map(fn(e) { substitute_type_entry(e, subs) }))
    FunctionType(parameters, ret) =>
      FunctionType(
        parameters.map(fn(t) { substitute_type(t, subs) }),
        substitute_type(ret, subs),
      )
    ConstrainedType(name, inner) =>
      ConstrainedType(name, substitute_type(inner, subs))
    UnionType(options) =>
      UnionType(options.map(fn(t) { substitute_type(t, subs) }))
    NullableType(inner) => NullableType(substitute_type(inner, subs))
    DefaultedType(inner) => DefaultedType(substitute_type(inner, subs))
    _ => typ
  }
}

///|
fn record_substitution(
  subs : Array[TypeSubstitution],
  name : String,
  typ : Type,
) -> Unit {
  // First binding wins. Later mismatches stay silent here — the surrounding
  // type_accepts check is the diagnostic surface, this pass only collects.
  match substitution_lookup(subs, name) {
    Some(_) => ()
    None => subs.push({ name, typ })
  }
}

///|
fn unify_for_substitution(
  expected : Type,
  actual : Type,
  subs : Array[TypeSubstitution],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match (expected, actual) {
    (TypeVariable(name), _) => {
      // PKL-116: when the parameter carries a declared bound, check
      // that the concrete argument flows through `type_accepts(bound,
      // actual)`. First-binding-wins still applies to the substitution
      // table itself; bound rejection is independent of binding
      // recording so the diagnostic surface stays clear.
      for binding in type_env {
        if binding.name == name {
          match binding.bound {
            Some(bound_type) =>
              if !type_accepts(bound_type, actual) {
                diagnostics.push(
                  diag(
                    "type parameter \{name} bound \{render_type(bound_type)} rejects \{render_type(actual)}",
                  ),
                )
              }
            None => ()
          }
        }
      }
      record_substitution(subs, name, actual)
    }
    (ConstrainedType(_, expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (_, ConstrainedType(_, actual_inner)) =>
      unify_for_substitution(
        expected, actual_inner, subs, type_env, diagnostics,
      )
    (DefaultedType(expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (_, DefaultedType(actual_inner)) =>
      unify_for_substitution(
        expected, actual_inner, subs, type_env, diagnostics,
      )
    (NullableType(expected_inner), NullableType(actual_inner)) =>
      unify_for_substitution(
        expected_inner, actual_inner, subs, type_env, diagnostics,
      )
    (NullableType(expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (ListingType(expected_items), ListingType(actual_items)) =>
      if expected_items.length() > 0 && actual_items.length() > 0 {
        let expected_item = expected_items[0]
        for item in actual_items {
          unify_for_substitution(
            expected_item, item, subs, type_env, diagnostics,
          )
        }
      }
    (MappingType(expected_entries), MappingType(actual_entries)) =>
      if expected_entries.length() > 0 && actual_entries.length() > 0 {
        let expected_entry = expected_entries[0]
        for entry in actual_entries {
          unify_for_substitution(
            expected_entry.key,
            entry.key,
            subs,
            type_env,
            diagnostics,
          )
          unify_for_substitution(
            expected_entry.value,
            entry.value,
            subs,
            type_env,
            diagnostics,
          )
        }
      }
    (
      FunctionType(expected_parameters, expected_return),
      FunctionType(actual_parameters, actual_return),
    ) => {
      let limit = if expected_parameters.length() < actual_parameters.length() {
        expected_parameters.length()
      } else {
        actual_parameters.length()
      }
      for i = 0; i < limit; i = i + 1 {
        unify_for_substitution(
          expected_parameters[i],
          actual_parameters[i],
          subs,
          type_env,
          diagnostics,
        )
      }
      unify_for_substitution(
        expected_return, actual_return, subs, type_env, diagnostics,
      )
    }
    (ClassType(_, expected_members), ObjectType(actual_members))
    | (ClassType(_, expected_members), ClassType(_, actual_members)) =>
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            unify_for_substitution(
              member_contract_type(expected_member.typ),
              actual,
              subs,
              type_env,
              diagnostics,
            )
          None => ()
        }
      }
    (ObjectType(expected_members), ObjectType(actual_members))
    | (ObjectType(expected_members), ClassType(_, actual_members)) =>
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            unify_for_substitution(
              member_contract_type(expected_member.typ),
              actual,
              subs,
              type_env,
              diagnostics,
            )
          None => ()
        }
      }
    _ => ()
  }
}

///|
fn class_type_mismatch_message(
  annotation_name : String,
  expected : Type,
  inferred : Type,
) -> String? {
  match (expected, inferred) {
    (ClassType(_, expected_members), ObjectType(actual_members)) => {
      let mut message : String? = None
      for expected_member in expected_members {
        if message is None {
          match lookup_member_type(actual_members, expected_member.name) {
            Some(actual) =>
              if !type_accepts(
                  member_contract_type(expected_member.typ),
                  actual,
                ) {
                message = Some(
                  "type annotation \{annotation_name} member \{expected_member.name} expects \{render_type(expected_member.typ)}, got \{render_type(actual)}",
                )
              }
            None =>
              if !is_defaulted_member_type(expected_member.typ) {
                message = Some(
                  "type annotation \{annotation_name} missing member \{expected_member.name}",
                )
              }
          }
        }
      }
      message
    }
    _ => None
  }
}

///|
fn apply_type_annotation(
  type_name : String?,
  inferred : Type,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match type_name {
    None => inferred
    Some(name) =>
      match type_from_annotation(name, type_env) {
        Some(expected) =>
          if type_accepts(expected, inferred) {
            // PKL-110: for class literals like `new Box { value = 5 }`,
            // the expected ClassType still carries TypeVariable("T") in
            // its members. Unify against the inferred ObjectType members
            // and rewrite the returned ClassType so downstream field
            // access (`b.value`) resolves to the concrete argument type.
            let expected = substitute_class_type_variables(
              expected, inferred, type_env, diagnostics,
            )
            match (expected, inferred) {
              (NullableType(ObjectType([])), ObjectType(_)) =>
                NullableType(inferred)
              (ConstrainedType(_, inner), _) => inner
              _ => expected
            }
          } else {
            let message = match
              class_type_mismatch_message(name, expected, inferred) {
              Some(detail) => detail
              None =>
                "type annotation \{name} does not accept \{render_type(inferred)}"
            }
            diagnostics.push(diag(message))
            UnknownType
          }
        None => {
          diagnostics.push(diag("Cannot find type `\{name}`."))
          UnknownType
        }
      }
  }
}

///|
fn substitute_class_type_variables(
  expected : Type,
  inferred : Type,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match expected {
    ClassType(_, _) => {
      let subs : Array[TypeSubstitution] = []
      unify_for_substitution(expected, inferred, subs, type_env, diagnostics)
      if subs.length() == 0 {
        expected
      } else {
        substitute_type(expected, subs)
      }
    }
    _ => expected
  }
}

///|
fn common_type(types : Array[Type]) -> Type {
  if types.length() == 0 {
    return UnknownType
  }
  let first = types[0]
  for typ in types {
    if typ != first {
      return make_union_type(types)
    }
  }
  first
}

///|
fn lookup_mapping_value_type(entries : Array[TypeEntry], key : Type) -> Type? {
  let mut found : Type? = None
  for entry in entries {
    if entry.key == key {
      found = Some(entry.value)
    }
  }
  found
}

///|
fn function_parameter_types(
  parameters : Array[FunctionParameter],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[Type] {
  let types : Array[Type] = []
  for parameter in parameters {
    match parameter.type_name {
      Some(type_name) =>
        match parameter_type_from_annotation(type_name, type_env) {
          Some(typ) => types.push(typ)
          None => {
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
            types.push(UnknownType)
          }
        }
      None => types.push(UnknownType)
    }
  }
  types
}

///|
fn function_return_type(
  return_type_name : String?,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match return_type_name {
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
}

///|
fn function_signature_type(
  function_decl : FunctionDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  FunctionType(
    function_parameter_types(function_decl.parameters, type_env, diagnostics),
    function_return_type(function_decl.return_type_name, type_env, diagnostics),
  )
}

///|
fn copy_type_bindings(bindings : Array[TypeBinding]) -> Array[TypeBinding] {
  let copied : Array[TypeBinding] = []
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn qualify_imported_type(
  import_name : String,
  type_export : TypeExport,
) -> Type {
  match type_export.typ {
    ClassType(_, members) =>
      ClassType("\{import_name}.\{type_export.name}", members)
    _ => type_export.typ
  }
}

///|
fn imported_type_bindings(
  imports : Array[ImportDecl],
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> Array[TypeBinding] {
  let bindings : Array[TypeBinding] = []
  for decl in imports {
    if !decl.is_glob {
      match resolve_import_types(decl.uri) {
        Some(exports) =>
          for type_export in exports {
            bindings.push({
              name: "\{decl.import_name}.\{type_export.name}",
              typ: qualify_imported_type(decl.import_name, type_export),
              alias_decl: None,
              bound: None,
            })
          }
        None => ()
      }
    }
  }
  bindings
}
