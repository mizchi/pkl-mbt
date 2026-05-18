///|
pub(all) enum Type {
  IntType
  // PKL-092: Float numeric type. Mixed Int / Float arithmetic widens to
  // Float; constraint predicates accept both via the implicit `Number`
  // hierarchy.
  FloatType
  BoolType
  StringType
  NullType
  ObjectType(Array[TypeMember])
  ClassType(String, Array[TypeMember])
  ListingType(Array[Type])
  MappingType(Array[TypeEntry])
  // PKL-119a: `Pair<A, B>` lives at the type level alongside Listing /
  // Mapping. Distinct from `ListingType([a, b])` so that
  // `Pair<Int, String>` and `Listing<Int | String>` stay separate,
  // and so `.first` / `.second` resolve only on the Pair side.
  PairType(Type, Type)
  // PKL-119b: `IntSeq` carries no type parameters (elements are
  // always Int). The dedicated type keeps `IntSeq` annotations and
  // `Listing<Int>` distinct at the typecheck layer the same way
  // `PairType` keeps `Pair<A, B>` separate from `Listing`.
  IntSeqType
  // PKL-119c: `Set<T>` parallels `ListingType` but keeps the type
  // distinct at the typecheck layer so consumers tracking
  // `Set<Person>` vs `Listing<Person>` see a real difference.
  SetType(Array[Type])
  // PKL-119d: `Map<K, V>` parallels `MappingType` but keeps the
  // immutable functional map separate from the object-style
  // `Mapping<K, V>` at the typechecker. Carrier shape mirrors
  // MappingType.
  MapType(Array[TypeEntry])
  FunctionType(Array[Type], Type)
  ConstrainedType(String, Type)
  UnionType(Array[Type])
  NullableType(Type)
  DefaultedType(Type)
  // PKL-110: free type parameter in a generic class / function context.
  // Carries the parameter name (e.g. "T") so the substitution pass at the
  // call site / class literal can match `TypeVariable("T")` to a concrete
  // argument type and rewrite the surrounding signature in place.
  TypeVariable(String)
  // PKL-133: Pkl's top type. Every value flows through `Any`. Distinct
  // from `UnknownType` (parser / inference fallback) so render output
  // surfaces as `Any` exactly, and so the typechecker can later
  // distinguish "user wrote Any explicitly" from "we lost track of the
  // type". Accept-any on both sides of `type_accepts`.
  AnyType
  UnknownType
} derive(Eq, Debug)

///|
pub(all) struct TypeMember {
  name : String
  typ : Type
} derive(Eq, Debug)

///|
pub(all) struct TypeEntry {
  key : Type
  value : Type
} derive(Eq, Debug)

///|
pub(all) enum TypecheckResult {
  TypeOk(Type)
  TypeError(Array[Diagnostic])
} derive(Eq, Debug)

///|
priv struct TypeBinding {
  name : String
  typ : Type
  // PKL-115: when this binding came from a generic typealias declaration
  // (`typealias Box<T> = Listing<T>`), capture the original decl so that
  // `type_from_annotation` can substitute the parameter list at the
  // instantiation site (`Box<Int>` → `Listing<Int>`). `None` for
  // ordinary bindings.
  alias_decl : TypeAliasDecl?
  // PKL-116: when this binding represents a generic type parameter with
  // a declared bound (`function pick<T : Number>(...)` or
  // `class Box<T : Number>`), capture the resolved bound Type so
  // `unify_for_substitution` can check that the concrete argument flows
  // through `type_accepts(bound, actual)`. `None` for ordinary
  // bindings and unbounded type parameters.
  bound : Type?
}

///|
pub(all) struct TypeExport {
  name : String
  typ : Type
} derive(Eq, Debug)

///|
fn lookup_type(env : Array[TypeBinding], name : String) -> Type? {
  let mut found : Type? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.typ)
    }
  }
  found
}

///|
fn lookup_member_type(members : Array[TypeMember], name : String) -> Type? {
  // PKL-118: mirror the eval-side `lookup_member` behaviour — a
  // hidden-prefixed entry (the form used to export module-level
  // functions across modules) resolves under its bare name too. This
  // is what lets `Base.helper(x)` find a `function helper(...)`
  // declared at the imported module's top level.
  let prefixed = hidden_member_name(name)
  let mut found : Type? = None
  for field in members {
    if field.name == name || field.name == prefixed {
      found = Some(field.typ)
    }
  }
  found
}

///|
fn member_contract_type(typ : Type) -> Type {
  match typ {
    DefaultedType(inner) => inner
    ConstrainedType(_, inner) => inner
    _ => typ
  }
}

///|
fn is_defaulted_member_type(typ : Type) -> Bool {
  match typ {
    DefaultedType(_) => true
    _ => false
  }
}

///|
fn nullable_type(typ : Type) -> Type {
  match typ {
    NullableType(_) => typ
    _ => NullableType(typ)
  }
}

///|
fn merge_type_members(
  base : Array[TypeMember],
  overrides : Array[TypeMember],
) -> Array[TypeMember] {
  let merged : Array[TypeMember] = []
  for type_member in base {
    match lookup_member_type(overrides, type_member.name) {
      Some(typ) => merged.push({ name: type_member.name, typ })
      None => merged.push(type_member)
    }
  }
  for type_member in overrides {
    if lookup_member_type(base, type_member.name) is None {
      merged.push(type_member)
    }
  }
  merged
}

///|
fn find_type_binding(bindings : Array[Binding], name : String) -> Binding? {
  let mut found : Binding? = None
  for binding in bindings {
    if binding.name == name {
      found = Some(binding)
    }
  }
  found
}

///|
fn stack_contains_type_binding(stack : Array[String], name : String) -> Bool {
  for item in stack {
    if item == name {
      return true
    }
  }
  false
}

///|
fn push_type_stack(stack : Array[String], name : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(name)
  next
}

///|
pub fn typecheck_source(source : String) -> TypecheckResult {
  // PKL-118: parallel to `eval_source`'s filter — strip the
  // hidden-prefixed function entries that the typechecker adds for
  // cross-module dispatch. The existing test corpus asserts on
  // visible-binding `ObjectType` membership; surfacing the synthetic
  // entries would force every test that declares a `function` to
  // expand its expected shape even though the user-visible module
  // surface still hides them.
  match typecheck_source_with_imports(source, fn(_) { None }) {
    TypeOk(ObjectType(members)) => {
      let visible : Array[TypeMember] = []
      for field in members {
        if !is_invisible_member_name(field.name) {
          visible.push(field)
        }
      }
      TypeOk(ObjectType(visible))
    }
    other => other
  }
}

///|
fn typecheck_parsed_with_imports(
  parsed : ParseResult,
  resolve_import : (String) -> TypecheckResult?,
) -> TypecheckResult {
  typecheck_parsed_with_import_details(parsed, resolve_import, fn(_) { None })
}

///|
fn typecheck_parsed_with_import_details(
  parsed : ParseResult,
  resolve_import : (String) -> TypecheckResult?,
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> TypecheckResult {
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return TypeError(diagnostics)
  }
  let typ = infer_program(
    parsed.program,
    diagnostics,
    resolve_import,
    resolve_import_types,
  )
  if diagnostics.length() == 0 {
    TypeOk(typ)
  } else {
    TypeError(diagnostics)
  }
}

///|
fn typecheck_source_with_imports(
  source : String,
  resolve_import : (String) -> TypecheckResult?,
) -> TypecheckResult {
  typecheck_parsed_with_imports(parse_source(source), resolve_import)
}
