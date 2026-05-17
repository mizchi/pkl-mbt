///|
pub(all) enum Value {
  IntValue(Int)
  // PKL-092: Float numeric value backed by MoonBit's `Double`. Arithmetic
  // between `IntValue` and `FloatValue` promotes to `FloatValue`; the
  // dedicated `Number` type sits above both in the typechecker hierarchy.
  FloatValue(Double)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  ObjectValue(Array[ValueMember])
  ListingValue(Array[Value])
  // PKL-148h: `List(...)` constructor result, kept distinct from
  // `ListingValue` (the `new Listing { ... }` block form). The two
  // share most method-dispatch surface but diverge on PCF rendering
  // (`List(a, b, c)` vs `new { a; b; c }`), runtime type name
  // (`List` vs `Listing`), and derived equality (List == Listing is
  // false even when element arrays match — Apple Pkl treats them as
  // distinct types).
  ListValue(Array[Value])
  MappingValue(Array[ValueEntry])
  // PKL-119a: Pair carries two ordered values with member access via
  // `.first` / `.second`. Previously collapsed into `ListingValue` of
  // size 2 (per the PKL-139 stop-gap), which lost the member-access
  // shape and the type-level distinction from `Listing<T>`. The
  // dedicated variant lets consumers using pkl-mbt as a library keep
  // the upstream type semantics for `Pair<A, B>`.
  PairValue(Value, Value)
  // PKL-119b: lazy integer sequence (start, end, step). `start` and
  // `end` are inclusive in Apple Pkl; `step` must be non-zero and
  // defaults to 1 (-1 when called as `IntSeq(start, end).step(-1)`
  // for descending iteration). Empty sequences (e.g. ascending
  // `IntSeq(5, 2)`) carry the original endpoints so the renderer can
  // round-trip the source form. The variant is intentionally lazy —
  // materialization happens at `.toList()` / `.toListing()` / `.map`
  // / `.fold` / non-PCF renderer projection time so a million-element
  // IntSeq doesn't allocate a million-slot Array up front.
  IntSeqValue(Int, Int, Int)
  // PKL-119c: ordered set of unique values, insertion-order preserved.
  // `Set(a, b, c)` constructs one (duplicates dropped at the
  // constructor); the dedicated variant means PCF renders the
  // upstream `Set(a, b, c)` form rather than `new Listing { a; b; c }`,
  // and the typechecker keeps `Set<T>` separate from `Listing<T>`.
  SetValue(Array[Value])
  // PKL-119d: immutable functional map (Apple Pkl's `Map<K, V>`),
  // distinct from `MappingValue` (the object-style `new Mapping
  // { ... }` form). `Map(k1, v1, k2, v2, ...)` builds one; later
  // keys with the same value overwrite earlier ones. The dedicated
  // variant lets PCF round-trip through `Map(k, v, ...)` rather
  // than the Mapping block form, and keeps `Map<K, V>` separate
  // from `Mapping<K, V>` at the typechecker.
  MapValue(Array[ValueEntry])
  // PKL-148g: identity stamp so `(() -> 1) == (() -> 1)` is false
  // (distinct LambdaExpr evaluations) while `local f = () -> 1; f == f`
  // is true (the same cached instance). MoonBit's derived `==` includes
  // the id, so structural-only payloads no longer falsely equate.
  FunctionValue(
    Array[FunctionParameter],
    Expr,
    String?,
    Array[ValueBinding],
    Int
  )
  // PKL-082: magnitude in the named unit. Mixed-unit arithmetic
  // normalizes to the smaller of the two units (the base unit of each
  // family — `ns` for Duration, `b` for DataSize — when no common
  // larger unit divides both). PKL-121 widened the magnitude from
  // `Int` to `Double` so Float-magnitude literals (`1.5.s`, `2.5.gib`)
  // round-trip without precision loss; Int-magnitude call sites
  // promote on the way in.
  DurationValue(Double, String)
  DataSizeValue(Double, String)
  // PKL-081: Regex value created via `Regex("<pattern>")`. Stores the
  // source pattern so methods can recompile via `moonbitlang/regexp`
  // and renderers can round-trip the value through `Regex("...")`.
  RegexValue(String)
  // PKL-083: Bytes value backed by MoonBit's `Bytes`. Constructed via
  // `Bytes(<Listing of Int>)` or `Bytes.fromBase64("...")`; PCF
  // round-trips through the Listing constructor and JSON / YAML /
  // Properties project the base64 string.
  BytesValue(Bytes)
} derive(Eq, Debug)

///|
pub(all) struct ValueMember {
  name : String
  value : Value
} derive(Eq, Debug)

///|
pub(all) struct ValueEntry {
  key : Value
  value : Value
} derive(Eq, Debug)

///|
pub(all) enum EvalResult {
  EvalOk(Value)
  EvalError(Array[Diagnostic])
} derive(Eq, Debug)

///|
pub(all) struct ValueBinding {
  name : String
  value : Value
} derive(Eq, Debug)

///|
priv struct ClassBinding {
  name : String
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
}

///|
priv struct EvalTypeAliasBinding {
  name : String
  target : String
}

///|
pub(all) struct ClassExport {
  name : String
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
} derive(Eq, Debug)

///|
fn lookup_value(env : Array[ValueBinding], name : String) -> Value? {
  let mut found : Value? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.value)
    }
  }
  found
}

///|
/// PKL-143: read the hidden `__kind` marker that `pkl:reflect.Class` /
/// `Module` / `TypeAlias` factories stamp on their returned mirror.
/// Returns `None` for an ordinary ObjectValue.
fn reflect_kind(members : Array[ValueMember]) -> String? {
  match lookup_member(members, "__kind") {
    Some(StringValue(kind)) => Some(kind)
    _ => None
  }
}

///|
/// PKL-143: read the `reflectee` member of a reflect mirror — the
/// string identifier the user passed to the factory.
fn reflect_reflectee_name(members : Array[ValueMember]) -> String? {
  match lookup_member(members, "reflectee") {
    Some(StringValue(name)) => Some(name)
    _ => None
  }
}

///|
/// PKL-143: project the property declarations of a class as a
/// `Listing<{name: String, typeName: String?}>`. Returns an empty
/// listing when the class isn't found in `declarations`.
fn reflect_class_properties(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          for prop in class_decl.properties {
            let type_value = match prop.type_name {
              Some(t) => StringValue(t)
              None => NullValue
            }
            result.push(
              ObjectValue([
                { name: "name", value: StringValue(prop.name) },
                { name: "typeName", value: type_value },
              ]),
            )
          }
        }
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: project the method declarations of a class as a
/// `Listing<{name: String, returnTypeName: String?, parameterTypeNames: Listing<String?>}>`.
fn reflect_class_methods(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          for fn_decl in class_decl.methods {
            let return_value = match fn_decl.return_type_name {
              Some(t) => StringValue(t)
              None => NullValue
            }
            let parameter_types : Array[Value] = []
            for parameter in fn_decl.parameters {
              parameter_types.push(
                match parameter.type_name {
                  Some(t) => StringValue(t)
                  None => NullValue
                },
              )
            }
            result.push(
              ObjectValue([
                { name: "name", value: StringValue(fn_decl.name) },
                { name: "returnTypeName", value: return_value },
                {
                  name: "parameterTypeNames",
                  value: ListingValue(parameter_types),
                },
              ]),
            )
          }
        }
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: look up a class's declared `parent_name` and wrap it in a
/// `Class` mirror with the hidden `__kind = "Class"` marker so chained
/// `.supertype.supertype` walks resolve recursively. Returns `NullValue`
/// when the class has no parent or isn't found.
fn reflect_class_supertype(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          match class_decl.parent_name {
            Some(parent) =>
              return ObjectValue([
                { name: "reflectee", value: StringValue(parent) },
                {
                  name: hidden_member_name("__kind"),
                  value: StringValue("Class"),
                },
              ])
            None => return NullValue
          }
        }
      _ => ()
    }
  }
  NullValue
}

///|
/// PKL-143: project the module's class declarations as a
/// `Listing<Class>` — each element is itself a Class mirror with the
/// `__kind = "Class"` marker so chained `.classes[i].properties`
/// walks resolve through the same hijack path.
fn reflect_module_classes(declarations : Array[Declaration]) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        result.push(
          ObjectValue([
            { name: "reflectee", value: StringValue(class_decl.name) },
            { name: hidden_member_name("__kind"), value: StringValue("Class") },
          ]),
        )
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: walk the parent chain of `child` to determine whether
/// `parent` is reachable. Same-class returns true (a class is its
/// own subclass for the purposes of `isSubclassOf`).
fn reflect_is_subclass_of(
  child : String,
  parent : String,
  declarations : Array[Declaration],
) -> Bool {
  if child == parent {
    return true
  }
  let mut current = child
  // Bound the walk at 256 hops to keep a malformed cyclic chain from
  // spinning forever; a healthy class hierarchy never reaches it.
  for _ in 0..<256 {
    let mut next : String? = None
    for decl in declarations {
      match decl {
        ClassDeclaration(class_decl) =>
          if class_decl.name == current {
            next = class_decl.parent_name
          }
        _ => ()
      }
    }
    match next {
      Some(name) => if name == parent { return true } else { current = name }
      None => return false
    }
  }
  false
}

///|
fn lookup_member(members : Array[ValueMember], name : String) -> Value? {
  // Hidden / local members carry the `hidden_member_prefix` /
  // `local_member_prefix` marker in their stored name so renderers can
  // skip them. A lookup for the bare name resolves any of the three
  // forms so internal callers (binding-cache resolvers, amend merges)
  // see the same data the writer wrote.
  let hidden_prefixed = hidden_member_name(name)
  let local_prefixed = local_member_name(name)
  let mut found : Value? = None
  for field in members {
    if field.name == name ||
      field.name == hidden_prefixed ||
      field.name == local_prefixed {
      found = Some(field.value)
    }
  }
  found
}

///|
/// PKL-148j: bare-name-only lookup for external member access on an
/// ObjectValue (`foo.x` where `foo` is bound to an ObjectValue).
/// Apple Pkl hides `local` members from outside-of-body access — `foo`
/// declaring `local x = 2` then `foo.x` from sibling code raises
/// "Cannot find property `x` in object of type `Dynamic`." rather than
/// returning `2`. `hidden` members stay reachable here (they only
/// disappear from the rendered envelope), matching Apple Pkl's
/// distinction between the two visibility modifiers.
fn lookup_visible_member(members : Array[ValueMember], name : String) -> Value? {
  let hidden_prefixed = hidden_member_name(name)
  let mut found : Value? = None
  for field in members {
    if (field.name == name || field.name == hidden_prefixed) &&
      !is_local_member_name(field.name) {
      found = Some(field.value)
    }
  }
  found
}

///|
fn lookup_class_binding(
  env : Array[ClassBinding],
  name : String,
) -> ClassBinding? {
  let mut found : ClassBinding? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding)
    }
  }
  found
}

///|
fn lookup_eval_type_alias(
  env : Array[EvalTypeAliasBinding],
  name : String,
) -> String? {
  let mut found : String? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.target)
    }
  }
  found
}

///|
fn lookup_function_decl(
  declarations : Array[FunctionDecl],
  name : String,
) -> FunctionDecl? {
  let mut found : FunctionDecl? = None
  for declaration in declarations {
    if declaration.name == name {
      found = Some(declaration)
    }
  }
  found
}

///|
fn lookup_class_method_with_stack(
  class_env : Array[ClassBinding],
  type_name : String,
  method_name : String,
  stack : Array[String],
) -> FunctionDecl? {
  if stack_contains_binding(stack, type_name) {
    return None
  }
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) =>
      match lookup_function_decl(class_binding.methods, method_name) {
        Some(function_decl) => Some(function_decl)
        None =>
          match class_binding.parent_name {
            Some(parent_name) =>
              lookup_class_method_with_stack(
                class_env,
                parent_name,
                method_name,
                push_binding_stack(stack, type_name),
              )
            None => None
          }
      }
    None => None
  }
}

///|
fn lookup_class_method(
  class_env : Array[ClassBinding],
  type_name : String,
  method_name : String,
) -> FunctionDecl? {
  lookup_class_method_with_stack(class_env, type_name, method_name, [])
}

///|
fn lookup_entry(entries : Array[ValueEntry], key : Value) -> Value? {
  let mut found : Value? = None
  for entry in entries {
    if entry.key == key {
      found = Some(entry.value)
    }
  }
  found
}

///|
fn merge_value_members(
  base : Array[ValueMember],
  overrides : Array[ValueMember],
) -> Array[ValueMember] {
  let merged : Array[ValueMember] = []
  for value_member in base {
    // PKL-148j: match base / override slots by exact storage name, not
    // by bare name. `local l` and a separately-declared visible `l`
    // occupy different namespaces in Apple Pkl — amending an object
    // that declares `local l = "original"` with `l = "override"` adds
    // a fresh visible `l` slot rather than overwriting the local.
    // `lookup_member` would conflate the two because it accepts either
    // form; `find_member_exact` matches only the stored name.
    match find_member_exact(overrides, value_member.name) {
      Some(value) =>
        merged.push({
          name: value_member.name,
          value: deep_merge_amend_value(value_member.value, value),
        })
      None => merged.push(value_member)
    }
  }
  for value_member in overrides {
    if find_member_exact(base, value_member.name) is None {
      merged.push(value_member)
    }
  }
  merged
}

///|
/// PKL-148j: strict storage-name lookup. Used by `merge_value_members`
/// so an amend body's bare `l` doesn't accidentally hit a base's
/// `@local$l` (different namespace) or the inverse. Matches only the
/// literal field name; callers that want bare-name resolution should
/// stay on `lookup_member`.
fn find_member_exact(members : Array[ValueMember], name : String) -> Value? {
  let mut found : Value? = None
  for field in members {
    if field.name == name {
      found = Some(field.value)
    }
  }
  found
}

///|
/// PKL-148d: deep-merge an amend body into a base value. When both
/// sides are ObjectValue, recursively merge their members so a nested
/// amend (`(x) { foo { bar = 11 } }`) preserves the base's
/// uninvolved members (`foo.num2`, `foo.baz.num3`). For other shapes
/// the override wins outright — Apple Pkl treats a typed Listing /
/// Mapping override as replacement, not append.
fn deep_merge_amend_value(base : Value, replacement : Value) -> Value {
  match (base, replacement) {
    (ObjectValue(base_members), ObjectValue(over_members)) =>
      ObjectValue(merge_value_members(base_members, over_members))
    _ => replacement
  }
}

///|

///|
/// Monotonic counter that hands out a fresh identity stamp every time
/// a LambdaExpr is evaluated or a function declaration is loaded.
/// Distinct lambda literals get distinct ids, so structural payloads
/// no longer collide under `==`.
let lambda_id_counter : Ref[Int] = { val: 0 }

///|
fn fresh_function_id() -> Int {
  lambda_id_counter.val = lambda_id_counter.val + 1
  lambda_id_counter.val
}

///|
fn find_binding(bindings : Array[Binding], name : String) -> Binding? {
  let mut found : Binding? = None
  let hidden = hidden_member_name(name)
  for binding in bindings {
    if binding.name == name || binding.name == hidden {
      found = Some(binding)
    }
  }
  found
}

///|
fn all_eval_bindings(program : Program) -> Array[Binding] {
  let bindings : Array[Binding] = []
  for declaration in program.declarations {
    match declaration {
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
              abstract_slot: false,
            })
          None => ()
        }
      ClassDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  for binding in program.bindings {
    bindings.push(binding)
  }
  bindings
}

///|
fn eval_type_alias_bindings(
  declarations : Array[Declaration],
) -> Array[EvalTypeAliasBinding] {
  let aliases : Array[EvalTypeAliasBinding] = []
  for declaration in declarations {
    match declaration {
      TypeAliasDeclaration(type_alias) =>
        aliases.push({ name: type_alias.name, target: type_alias.target })
      ClassDeclaration(_) | FunctionDeclaration(_) => ()
    }
  }
  aliases
}

///|
fn eval_constrained_type_source_name_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  if pkl_constrained_type_annotation_has_supported_constraint(name) {
    return Some(name)
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_constrained_type_source_name_with_depth(target, aliases, depth + 1)
    None => None
  }
}

///|
fn eval_resolved_type_alias_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String {
  if depth > 8 {
    return name
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_resolved_type_alias_with_depth(target, aliases, depth + 1)
    None => name
  }
}

///|
fn eval_resolved_type_alias(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String {
  eval_resolved_type_alias_with_depth(name, aliases, 0)
}

///|
fn eval_constrained_type_source_name(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String? {
  eval_constrained_type_source_name_with_depth(name, aliases, 0)
}

///|
// PKL-138: coerce an empty `ObjectValue([])` to the empty Listing /
// Mapping value when the binding's type annotation requires it. Parsers
// can't tell whether `new {}` (no explicit type, empty body) is meant
// to be a Listing, Mapping, or Object — the binding's type annotation
// is the disambiguator, applied here at eval time.
//
// Non-empty `ObjectValue`s aren't coerced: if the body had real entries
// they would have been parsed as listing / mapping body via the
// `parse_inferred_new_body` peek (which dispatches on the first
// significant token), so a non-empty ObjectValue with a Listing /
// Mapping annotation is a real type mismatch.

///|
/// PKL-148: when a typed binding (`p: Person = new {}`) gets filled in
/// with an empty object, fall back to the class's declared default
/// property values. Without this the rendered output is `p {}` instead
/// of the inherited defaults. The expansion runs only for ObjectValue
/// with zero visible members where `type_name` names a user-defined
/// class; everything else passes through.
fn apply_class_defaults_for_type(
  value : Value,
  type_name : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match (value, type_name) {
    (ObjectValue(members), Some(name)) =>
      if visible_members(members).length() != 0 {
        value
      } else {
        let base = name
        match lookup_class_binding(class_env, base) {
          Some(_) => {
            let defaults = eval_class_default_members(
              base,
              bindings,
              env,
              class_env,
              cache,
              [],
              declarations,
              diagnostics,
              resolve_import,
            )
            if defaults.length() == 0 {
              value
            } else {
              ObjectValue(merge_value_members(defaults, members))
            }
          }
          None => value
        }
      }
    _ => value
  }
}

///|
/// Synthesize a runtime default value for a typed property that has no
/// `=` initializer. Mirrors Apple Pkl's auto-default rules so a module
/// like `class P; p: P` renders as `p {}`. Returns `None` when the
/// type doesn't have a representable default (e.g., an unresolved
/// generic) so the caller can fall back to the abstract-slot skip.
fn synthesize_default_for_type(
  type_name : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match type_name {
    None => None
    Some(raw) => {
      let name = trim_spaces(raw)
      // Nullable types (`T?`) default to null.
      if name.has_suffix("?") || name == "Null" || name == "Nothing" {
        return Some(NullValue)
      }
      // String literal type `"foo"` defaults to the literal text.
      if name.length() >= 2 && name[0] == '"' && name[name.length() - 1] == '"' {
        let inner = String::unsafe_substring(
          name,
          start=1,
          end=name.length() - 1,
        )
        return Some(StringValue(inner))
      }
      // `*A|B|...` union with a default branch picks the starred type.
      if name.has_prefix("*") {
        let rest = String::unsafe_substring(name, start=1, end=name.length())
        let pipe = rest.find("|")
        let head = match pipe {
          Some(idx) => String::unsafe_substring(rest, start=0, end=idx)
          None => rest
        }
        return synthesize_default_for_type(
          Some(trim_spaces(head)),
          bindings,
          env,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        )
      }
      // Structural collections fall back to their empty form. Set/Map
      // carry dedicated variants that round-trip through the PCF
      // constructor renderer; Listing/Mapping render as block bodies.
      // PKL-148j: `Collection<T>` and `List<T>` default to `ListValue`
      // (Apple Pkl renders `List()` for both, matching the
      // `basic/propertyDefaults` gold).
      if name == "Listing" || name.has_prefix("Listing<") {
        return Some(ListingValue([]))
      }
      if name == "Mapping" || name.has_prefix("Mapping<") {
        return Some(MappingValue([]))
      }
      if name == "Set" || name.has_prefix("Set<") {
        return Some(SetValue([]))
      }
      if name == "Map" || name.has_prefix("Map<") {
        return Some(MapValue([]))
      }
      if name == "List" ||
        name.has_prefix("List<") ||
        name == "Collection" ||
        name.has_prefix("Collection<") {
        return Some(ListValue([]))
      }
      // User-defined class → `new T {}` with class defaults applied.
      let base = match name.find("<") {
        Some(idx) => String::unsafe_substring(name, start=0, end=idx)
        None => name
      }
      match lookup_class_binding(class_env, base) {
        Some(_) =>
          Some(
            apply_class_defaults_for_type(
              ObjectValue([]),
              Some(base),
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
          )
        None => None
      }
    }
  }
}

///|
fn coerce_value_to_annotated_type(value : Value, type_name : String?) -> Value {
  match (value, type_name) {
    (ObjectValue(members), Some(name)) if members.length() == 0 =>
      if name == "Listing" ||
        name == "List" ||
        name.has_prefix("Listing<") ||
        name.has_prefix("List<") {
        ListingValue([])
      } else if name == "Mapping" || name.has_prefix("Mapping<") {
        MappingValue([])
      } else if name == "Set" || name.has_prefix("Set<") {
        // PKL-119 will introduce SetValue; until then collapse to
        // ListingValue (matches how Listing/List share a variant today).
        ListingValue([])
      } else {
        value
      }
    _ => value
  }
}

///|
fn eval_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match type_name {
    Some(display_name) =>
      match eval_constrained_type_source_name(display_name, aliases) {
        Some(source_name) =>
          match
            pkl_constrained_type_annotation_value_rejection_message_from_source(
              display_name, source_name, value,
            ) {
            Some(message) => {
              diagnostics.push(diag(message))
              false
            }
            None => true
          }
        None => true
      }
    None => true
  }
}

///|
fn eval_user_defined_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match
    pkl_user_defined_constrained_type_annotation_value_rejection_message(
      type_name, value, declarations,
    ) {
    Some(message) => {
      diagnostics.push(diag(message))
      false
    }
    None => true
  }
}

///|
fn eval_lookup_class_decl(
  declarations : Array[Declaration],
  name : String,
) -> ClassDecl? {
  let mut found : ClassDecl? = None
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        if class_decl.name == name {
          found = Some(class_decl)
        }
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  found
}

///|
fn eval_class_property_annotation_with_depth(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut found = false
      let mut annotation : String? = None
      for property in class_decl.properties {
        if property.name == property_name {
          found = true
          annotation = property.type_name
        }
      }
      // PKL-148i: a subclass property that omits the type annotation
      // (e.g. `name = "Pigeon"` while the parent declared
      // `name: String`) still inherits the parent's annotation —
      // amend overrides must satisfy it. Walk the parent chain when
      // either the property isn't declared locally OR is declared
      // without its own annotation.
      if found && annotation is Some(_) {
        annotation
      } else {
        match class_decl.parent_name {
          Some(parent_name) =>
            eval_class_property_annotation_with_depth(
              declarations,
              parent_name,
              property_name,
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
fn eval_class_property_annotation(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
) -> String? {
  eval_class_property_annotation_with_depth(
    declarations, class_name, property_name, 0,
  )
}

///|

///|
/// PKL-148c: pretty-print a constraint text by re-inserting whitespace
/// around binary comparison / logical operators. `parse_type_text`
/// strips trivia so the captured constraint reads `this>=min` rather
/// than Apple Pkl's `this >= min`; this helper restores the spaces
/// before the text reaches the diagnostic.
fn pretty_constraint_text(text : String) -> String {
  let trimmed = pkl_constraint_trim(text)
  let multi : Array[String] = [">=", "<=", "==", "!=", "&&", "||"]
  let single : Array[Char] = ['>', '<']
  let buf = StringBuilder::new()
  let n = trimmed.length()
  let mut i = 0
  let mut depth = 0
  while i < n {
    let c = trimmed[i].to_int().unsafe_to_char()
    if c == '"' {
      // copy a string literal verbatim
      buf.write_char(c)
      i = i + 1
      while i < n {
        let cc = trimmed[i].to_int().unsafe_to_char()
        buf.write_char(cc)
        i = i + 1
        if cc == '\\' && i < n {
          buf.write_char(trimmed[i].to_int().unsafe_to_char())
          i = i + 1
        } else if cc == '"' {
          break
        }
      }
      continue
    }
    if c == '(' || c == '[' {
      depth = depth + 1
    } else if c == ')' || c == ']' {
      depth = depth - 1
    }
    if depth >= 0 {
      // Check multi-char ops first.
      let mut matched = false
      for op in multi {
        let m = op.length()
        if i + m <= n {
          let mut equal = true
          for j = 0; j < m; j = j + 1 {
            if trimmed[i + j] != op[j] {
              equal = false
              break
            }
          }
          if equal {
            ensure_trailing_space(buf)
            buf.write_string(op)
            buf.write_char(' ')
            i = i + m
            matched = true
            break
          }
        }
      }
      if matched {
        continue
      }
      let mut single_matched = false
      for op in single {
        if c == op {
          // Don't space a `<` / `>` that's part of a generic type
          // argument list (rare in constraint texts, but defensive).
          ensure_trailing_space(buf)
          buf.write_char(op)
          buf.write_char(' ')
          i = i + 1
          single_matched = true
          break
        }
      }
      if single_matched {
        continue
      }
    }
    buf.write_char(c)
    i = i + 1
  }
  collapse_spaces(buf.to_string())
}

///|
fn ensure_trailing_space(buf : StringBuilder) -> Unit {
  let current = buf.to_string()
  if current.length() > 0 {
    let last = current[current.length() - 1].to_int().unsafe_to_char()
    if last != ' ' {
      buf.write_char(' ')
    }
  }
}

///|
fn collapse_spaces(text : String) -> String {
  let buf = StringBuilder::new()
  let mut prev_space = false
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == ' ' {
      if !prev_space {
        buf.write_char(' ')
      }
      prev_space = true
    } else {
      buf.write_char(c)
      prev_space = false
    }
  }
  pkl_constraint_trim(buf.to_string())
}

///|
/// PKL-148c: walk an `Expr` tree and replace each bare
/// `Identifier(name)` whose name doesn't appear in the constraint's
/// known scope with `MemberAccess(Identifier("this"), name)`. Apple
/// Pkl's constraint expression body uses implicit-receiver lookup —
/// `abs` inside `Int(abs < 100)` resolves as `this.abs`. We pre-rewrite
/// instead of overloading the Identifier eval arm so the standard
/// resolver stays unchanged for non-constraint expressions.
fn rewrite_implicit_this_in_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Expr {
  match expr {
    Identifier(name) => {
      if name == "this" ||
        name == "module" ||
        name == "true" ||
        name == "false" ||
        name == "null" {
        return expr
      }
      let in_bindings = find_binding(bindings, name) is Some(_)
      let in_env = lookup_value(env, name) is Some(_)
      let in_cache = lookup_value(cache, name) is Some(_)
      if in_bindings || in_env || in_cache {
        expr
      } else {
        MemberAccess(Identifier("this"), name)
      }
    }
    MemberAccess(target, name) =>
      MemberAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        name,
      )
    SafeMemberAccess(target, name) =>
      SafeMemberAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        name,
      )
    SubscriptAccess(target, key) =>
      SubscriptAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        rewrite_implicit_this_in_expr(key, bindings, env, cache),
      )
    CallExpr(callee, args) => {
      let new_callee = rewrite_implicit_this_in_expr(
        callee, bindings, env, cache,
      )
      let new_args : Array[Expr] = []
      for a in args {
        new_args.push(rewrite_implicit_this_in_expr(a, bindings, env, cache))
      }
      CallExpr(new_callee, new_args)
    }
    NullSafeCallExpr(callee, args) => {
      let new_callee = rewrite_implicit_this_in_expr(
        callee, bindings, env, cache,
      )
      let new_args : Array[Expr] = []
      for a in args {
        new_args.push(rewrite_implicit_this_in_expr(a, bindings, env, cache))
      }
      NullSafeCallExpr(new_callee, new_args)
    }
    UnaryExpr(op, inner) =>
      UnaryExpr(op, rewrite_implicit_this_in_expr(inner, bindings, env, cache))
    BinaryExpr(op, l, r) =>
      BinaryExpr(
        op,
        rewrite_implicit_this_in_expr(l, bindings, env, cache),
        rewrite_implicit_this_in_expr(r, bindings, env, cache),
      )
    NonNullExpr(inner) =>
      NonNullExpr(rewrite_implicit_this_in_expr(inner, bindings, env, cache))
    ConditionalExpr(c, t, e) =>
      ConditionalExpr(
        rewrite_implicit_this_in_expr(c, bindings, env, cache),
        rewrite_implicit_this_in_expr(t, bindings, env, cache),
        rewrite_implicit_this_in_expr(e, bindings, env, cache),
      )
    _ => expr
  }
}

///|
/// PKL-148c: parse a constraint expression text into an `Expr`. Uses
/// the regular parser by wrapping the source as `__probe = (text)` and
/// pulling the binding's value back out. Returns `None` when the parse
/// fails or the binding is missing — the caller falls through to the
/// existing static predicate path.
fn parse_constraint_expression(text : String) -> Expr? {
  let wrapped = "__probe = (" + text + ")"
  let parsed = parse_source(wrapped)
  for binding in parsed.program.bindings {
    if binding.name == "__probe" {
      return Some(binding.value)
    }
  }
  None
}

///|
/// PKL-148c: run an arbitrary constraint expression against a candidate
/// value with `this` bound. When the candidate is an `ObjectValue`, the
/// object's members are also hoisted into the env so the implicit
/// receiver form (`street.endsWith("St.")` rather than
/// `this.street.endsWith("St.")`) resolves. Returns the canonical
/// diagnostic text when the predicate evaluates to `false`.
fn eval_runtime_constraint_for_property(
  class_name : String,
  property_name : String,
  property_value : Value,
  enclosing_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  let source_name = match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(s) => s
    None => return None
  }
  let text = match pkl_constrained_type_constraint_text(source_name) {
    Some(t) => t
    None => return None
  }
  let parts = pkl_split_constraint_arguments(text)
  for part in parts {
    let expr = match parse_constraint_expression(part) {
      Some(e) => e
      None => continue
    }
    // Build a fresh env with `this` bound to the candidate. If the
    // candidate is an ObjectValue, push its members under their bare
    // names too so identifier lookup picks them up before falling
    // through to the surrounding scope (implicit receiver). The
    // enclosing class's other property values are also added so a
    // sibling reference (`Int(this >= min)`) resolves.
    let new_env : Array[ValueBinding] = []
    for binding in env {
      new_env.push(binding)
    }
    new_env.push({ name: "this", value: property_value })
    match property_value {
      ObjectValue(receiver_members) =>
        for value_member in receiver_members {
          if !is_invisible_member_name(value_member.name) {
            new_env.push({ name: value_member.name, value: value_member.value })
          }
        }
      _ => ()
    }
    for value_member in enclosing_members {
      if !is_invisible_member_name(value_member.name) &&
        value_member.name != property_name {
        new_env.push({ name: value_member.name, value: value_member.value })
      }
    }
    // PKL-148c: rewrite bare `Identifier(name)` nodes inside the
    // constraint expression to `MemberAccess(Identifier("this"), name)`
    // when `name` is neither a binding nor in env. Apple Pkl treats
    // `abs` inside `Int(abs < 100)` as `this.abs` because the
    // candidate value is the implicit receiver of the constraint
    // body. Pre-rewriting the tree keeps the existing
    // `eval_expr_with_bindings` flow untouched.
    let rewritten = rewrite_implicit_this_in_expr(
      expr, bindings, new_env, cache,
    )
    let probe_diags : Array[Diagnostic] = []
    match
      eval_expr_with_bindings(
        rewritten, bindings, new_env, class_env, cache, stack, declarations, probe_diags,
        resolve_import,
      ) {
      Some(BoolValue(true)) => ()
      Some(BoolValue(false)) => {
        // PKL-148d: the diagnostic's `Value:` segment renders
        // ObjectValue candidates with their declared class name
        // (`new Address { ... }` rather than `new { ... }`), matching
        // Apple Pkl's compact-line form.
        let hint = match pkl_constrained_type_base_name(source_name) {
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
          "Type constraint `\{pretty_constraint_text(part)}` violated. Value: \{render_pcf_value_inline_compact(property_value, hint)}",
        )
      }
      // A non-Bool result or a diagnostic from inside the expression
      // means the predicate is shape-incompatible with this slice's
      // runtime — fall through silently rather than masking the
      // original static-predicate path.
      _ => ()
    }
  }
  None
}

///|
fn eval_class_property_constraint_value_rejection_message(
  class_name : String,
  property_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      let display_name = "\{class_name} member \{property_name}"
      // PKL-148b: a class property typed `Listing<...>(...)` whose
      // amend body is empty (`l {}`) initially evaluates to an empty
      // ObjectValue. Coerce to ListingValue before the constraint
      // dispatch so the Listing-host predicate (e.g. `!isEmpty`) fires.
      let coerced = coerce_value_to_annotated_type(value, Some(source_name))
      match
        pkl_constrained_type_annotation_value_rejection_message_from_source(
          display_name, source_name, coerced,
        ) {
        Some(message) => Some(message)
        None =>
          pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
            display_name, source_name, coerced, declarations,
          )
      }
    }
    None => None
  }
}

///|
/// PKL-148i: reject an assignment whose value's runtime type doesn't
/// satisfy the property's declared type annotation. The existing
/// `eval_class_property_constraint_value_rejection_message` only
/// dispatches predicate-style constraints (`Int(x > 0)`), so a bare
/// type annotation like `name: String` never fires when the supplied
/// value is the wrong shape (`new Person { name = 42 }` evaluated to
/// `42` instead of producing the upstream rejection diagnostic).
/// Mirrors the surface of `eval_callable_return_rejection_message`:
/// resolve type alias, accept type parameters, and only emit when
/// neither the builtin acceptance set nor a user-class annotation
/// satisfies the value.
fn eval_class_property_type_rejection_message(
  class_name : String,
  property_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      if eval_type_name_is_type_parameter(source_name, declarations) {
        return None
      }
      let aliases = eval_type_alias_bindings(declarations)
      let resolved_type_name = eval_resolved_type_alias(source_name, aliases)
      let base = match pkl_constrained_type_base_name(resolved_type_name) {
        Some(b) => b
        None => resolved_type_name
      }
      let coerced = coerce_value_to_annotated_type(value, Some(source_name))
      // Normalize generic type heads (`Listing<X>` → `Listing`,
      // `Mapping<K,V>` → `Mapping`, `Pair<A,B>` → `Pair`, …) before
      // the acceptance check; `eval_value_accepts_type_annotation`
      // matches against the bare collection name.
      let stripped_q = if base.has_suffix("?") {
        String::unsafe_substring(base, start=0, end=base.length() - 1)
      } else {
        base
      }
      let head = {
        let mut cut = -1
        let n = stripped_q.length()
        for i = 0; i < n; i = i + 1 {
          if stripped_q[i].to_int().unsafe_to_char() == '<' {
            cut = i
            break
          }
        }
        if cut < 0 {
          stripped_q
        } else {
          String::unsafe_substring(stripped_q, start=0, end=cut)
        }
      }
      let head_with_optional = if base.has_suffix("?") {
        head + "?"
      } else {
        head
      }
      if eval_value_accepts_type_annotation(head_with_optional, coerced) {
        return None
      }
      if value_satisfies_user_class_annotation(head, coerced, declarations) {
        return None
      }
      // Only reject for stdlib type names or known user classes;
      // unknown annotations stay silent (matches the legacy behaviour
      // for not-yet-implemented surface).
      if !is_stdlib_class_name(head) &&
        !(eval_lookup_class_decl(declarations, head) is Some(_)) {
        return None
      }
      Some(
        "Expected value of type `\{base}`, but got type `\{eval_value_type_name(coerced)}`. Value: \{render_pcf_value_inline(coerced)}",
      )
    }
    None => None
  }
}

///|
fn eval_object_member_expr_is_provided(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  for field in members {
    if field.name == name {
      return true
    }
  }
  false
}

///|
fn eval_class_property_default_constraints_are_valid_with_depth(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  depth : Int,
) -> Bool {
  if depth > 8 {
    return true
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut ok = true
      match class_decl.parent_name {
        Some(parent_name) =>
          if !eval_class_property_default_constraints_are_valid_with_depth(
              parent_name,
              provided_members,
              values,
              declarations,
              diagnostics,
              depth + 1,
            ) {
            ok = false
          }
        None => ()
      }
      for property in class_decl.properties {
        if property.value is Some(_) &&
          !eval_object_member_expr_is_provided(provided_members, property.name) {
          match lookup_member(values, property.name) {
            Some(default_value) =>
              match
                eval_class_property_constraint_value_rejection_message(
                  class_name,
                  property.name,
                  default_value,
                  declarations,
                ) {
                Some(message) => {
                  diagnostics.push(diag(message))
                  ok = false
                }
                None => ()
              }
            None => ()
          }
        }
      }
      ok
    }
    None => true
  }
}

///|
fn eval_class_property_default_constraints_are_valid(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  eval_class_property_default_constraints_are_valid_with_depth(
    class_name, provided_members, values, declarations, diagnostics, 0,
  )
}

///|
fn eval_expr_class_property_constraints_are_valid(
  expr : Expr,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (TypedObjectLiteral(class_name, members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) => {
            match
              eval_class_property_constraint_value_rejection_message(
                class_name,
                field.name,
                member_value,
                declarations,
              ) {
              Some(message) => {
                diagnostics.push(diag(message))
                ok = false
              }
              None => ()
            }
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          }
          None => ()
        }
      }
      if !eval_class_property_default_constraints_are_valid(
          class_name, members, values, declarations, diagnostics,
        ) {
        ok = false
      }
      ok
    }
    (ObjectLiteral(members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) =>
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          None => ()
        }
      }
      ok
    }
    _ => true
  }
}

///|
fn eval_object_member_alias_constraints_are_valid(
  members : Array[ObjectMember],
  values : Array[ValueMember],
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  let mut ok = true
  for object_member in members {
    match lookup_member(values, object_member.name) {
      Some(value) => {
        if !eval_constrained_type_annotation_value_is_valid(
            object_member.type_name,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
        if !eval_expr_alias_constraints_are_valid(
            object_member.value,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
      }
      None => ()
    }
  }
  ok
}

///|
fn eval_expr_alias_constraints_are_valid(
  expr : Expr,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (ObjectLiteral(members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    (TypedObjectLiteral(_, members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    _ => true
  }
}

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
            typed_object_class_name_for_expr(
              binding.value,
              bindings,
              push_binding_stack(stack, name),
            )
          None => None
        }
      }
    _ => None
  }
}

///|
fn copy_value_bindings(bindings : Array[ValueBinding]) -> Array[ValueBinding] {
  let copied : Array[ValueBinding] = []
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
  for binding in cache {
    captured.push(binding)
  }
  captured
}

///|
fn int_pow(base : Int, exponent : Int) -> Int? {
  if exponent < 0 {
    return None
  }
  let mut result = 1
  let mut i = 0
  while i < exponent {
    result = result * base
    i += 1
  }
  Some(result)
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
  match lookup_value(cache, name) {
    Some(value) => Some(value)
    None =>
      match find_binding(bindings, name) {
        Some(binding) =>
          if stack_contains_binding(stack, name) {
            diagnostics.push(diag("cyclic property reference \{name}"))
            None
          } else {
            match
              eval_expr_with_bindings(
                binding.value,
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
                if pkl_constrained_type_annotation_value_is_valid(
                    binding.type_name,
                    value,
                    diagnostics,
                  ) {
                  cache.push({ name, value })
                  Some(value)
                } else {
                  None
                }
              }
              None => None
            }
          }
        None => None
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
  while current is Some(name) {
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
fn eval_value_type_name(value : Value) -> String {
  match value {
    IntValue(_) => "Int"
    FloatValue(_) => "Float"
    BoolValue(_) => "Boolean"
    StringValue(_) => "String"
    NullValue => "Null"
    ObjectValue(_) => "Object"
    ListingValue(_) => "Listing"
    ListValue(_) => "List"
    MappingValue(_) => "Mapping"
    FunctionValue(_, _, _, _, _) => "Function"
    DurationValue(_, _) => "Duration"
    DataSizeValue(_, _) => "DataSize"
    RegexValue(_) => "Regex"
    BytesValue(_) => "Bytes"
    PairValue(_, _) => "Pair"
    IntSeqValue(_, _, _) => "IntSeq"
    SetValue(_) => "Set"
    MapValue(_) => "Map"
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
/// PKL-148d: build the same `pkl:reflect.Class` mirror from a bare
/// class name. Used when a class identifier (`Person`) is read as a
/// value rather than as a type annotation — Apple Pkl treats the
/// identifier as a Class instance whose member-access surface
/// produces `Cannot find property \`X\` in object of type \`Class\`.`
/// for anything other than `simpleName` / `name`.
fn synth_class_mirror_for_name(name : String) -> Value {
  ObjectValue([
    { name: hidden_member_name("__kind"), value: StringValue("Class") },
    { name: hidden_member_name("reflectee"), value: StringValue(name) },
    { name: "simpleName", value: StringValue(name) },
    { name: "name", value: StringValue(name) },
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
    | "Function5" => true
    _ => false
  }
}

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
      // Normalize the head for the acceptance check while keeping
      // the original surface name in the diagnostic: strip a trailing
      // constraint `(...)` and any generic `<...>` so e.g.
      // `List<Set<...>>(thisisList)` collapses to `List` — the
      // value-side acceptance only matches on the outermost head.
      let without_constraint = match pkl_constrained_type_base_name(resolved) {
        Some(base) => base
        None => resolved
      }
      let head_for_check = match without_constraint.find("<") {
        Some(idx) =>
          String::unsafe_substring(without_constraint, start=0, end=idx)
        None => without_constraint
      }
      if eval_value_accepts_type_annotation(head_for_check, value) {
        return None
      }
      if value_satisfies_user_class_annotation(
          head_for_check, value, declarations,
        ) {
        return None
      }
      Some(
        "Expected value of type `\{source}`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
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
      if !eval_value_accepts_type_annotation(resolved_type_name, value) &&
        !value_satisfies_user_class_annotation(
          resolved_type_name, value, declarations,
        ) {
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
        match
          pkl_constrained_type_annotation_value_rejection_message_from_source(
            type_name, resolved_type_name, value,
          ) {
          Some(message) => Some("\{label} return \{message}")
          None =>
            match
              pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
                type_name, resolved_type_name, value, declarations,
              ) {
              Some(message) => Some("\{label} return \{message}")
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
        diagnostics.push(diag("\{label} argument \{i + 1} \{message}"))
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
            diagnostics.push(diag("\{label} argument \{i + 1} \{message}"))
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
/// PKL-119b: method names dispatched off an `IntSeqValue` target.
/// `step` is overloaded — it's also a property name returning the
/// carrier slot — so the CallExpr dispatcher checks the call form
/// (zero args ⇒ method call returning a new IntSeq).
fn is_intseq_method_name(name : String) -> Bool {
  match name {
    "step" | "toList" | "toListing" | "map" | "fold" => true
    _ => false
  }
}

///|
/// PKL-119c: method names dispatched off a `SetValue` target. The
/// method-side surface mirrors Apple Pkl's `Set` class — the binary
/// `union` / `intersection` / `difference` operators come in a
/// follow-up; this slice covers `.contains` plus the read-only
/// projections and the higher-order helpers shared with `Listing`.
fn is_set_method_name(name : String) -> Bool {
  match name {
    "contains"
    // PKL-148: pkl:base Set surface — `add` / `every` / `any` /
    // `firstOrNull` / `getOrNull` / `count`.
    | "add"
    | "every"
    | "any"
    | "none"
    | "firstOrNull"
    | "lastOrNull"
    | "count"
    | "toList"
    | "toListing"
    | "toSet"
    | "map"
    | "filter"
    | "fold"
    | "join" => true
    _ => false
  }
}

///|
/// PKL-119d: method names dispatched off a `MapValue` target. Apple
/// Pkl's `Map<K, V>` class is read-mostly; this slice covers the
/// lookup methods (`getOrNull` / `containsKey` / `getOrThrow`),
/// projection helpers (`toMap` / `toMapping` / `toList`), and the
/// higher-order surface (`map` / `filter` / `fold`). The mutation
/// methods (`put` / `remove`) are intentionally elided — Apple Pkl's
/// signatures return new Maps rather than mutating, but their
/// implementations involve key-equality semantics we already cover
/// via the entry-walker so the slice can pick them up later without
/// further model changes.
fn is_map_method_name(name : String) -> Bool {
  match name {
    "containsKey"
    // PKL-148: pkl:base Map.containsValue(v) is the value-side parallel
    // of `containsKey` — Apple Pkl's fixture `api/map.pkl` exercises it.
    | "containsValue"
    | "getOrNull"
    | "getOrThrow"
    | "toMap"
    | "toMapping"
    | "toList"
    | "map"
    | "filter"
    | "fold" => true
    _ => false
  }
}

///|
/// PKL-144: convert a `@json.Json` value into the corresponding Pkl
/// `Value`. `use_mapping` controls how JSON objects project — `true`
/// → `MappingValue` (key as `StringValue`, matching Apple Pkl's
/// `Parser { useMapping = true }` mode); `false` → `ObjectValue`
/// (one property per JSON entry, the Dynamic shape Apple Pkl uses
/// by default). Numbers convert to Int when integral, Float
/// otherwise — matches the upstream rule that JSON `42` evaluates
/// to a Pkl `Int` and `42.5` to a `Float`.
fn json_to_value(j : Json, use_mapping : Bool) -> Value {
  match j {
    Null => NullValue
    True => BoolValue(true)
    False => BoolValue(false)
    Number(d, ..) => {
      let truncated = d.to_int().to_double()
      if truncated == d && d >= -2147483648.0 && d <= 2147483647.0 {
        IntValue(d.to_int())
      } else {
        FloatValue(d)
      }
    }
    String(s) => StringValue(s)
    Array(items) => {
      let elements : Array[Value] = []
      for item in items {
        elements.push(json_to_value(item, use_mapping))
      }
      ListingValue(elements)
    }
    Object(map) =>
      if use_mapping {
        let entries : Array[ValueEntry] = []
        for k, v in map {
          entries.push({ key: StringValue(k), value: json_to_value(v, true) })
        }
        MappingValue(entries)
      } else {
        let members : Array[ValueMember] = []
        for k, v in map {
          members.push({ name: k, value: json_to_value(v, false) })
        }
        ObjectValue(members)
      }
  }
}

///|
/// PKL-144 / PKL-145: read the `useMapping` slot from a pkl:json /
/// pkl:yaml Parser mirror. Each Parser is identified via the hidden
/// `__kind = "<JsonParser|YamlParser>"` marker stamped by the
/// synthetic class (`reflect_kind` walks the same `__kind` member);
/// this helper only reads the toggle once the marker has been
/// matched.
fn parser_use_mapping(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "useMapping") {
    Some(BoolValue(b)) => b
    _ => false
  }
}

///|
/// PKL-146: convert a `moonbit-community/yaml` `Yaml` value into the
/// corresponding Pkl `Value`. `use_mapping` controls how YAML maps
/// project — `true` → `MappingValue` (key as `StringValue`); `false`
/// → `ObjectValue` (Dynamic shape, the default). Numbers: YAML
/// `Real(d)` becomes Pkl `IntValue` when integral + Int32-bounded
/// else `FloatValue` (same rule as the JSON path); YAML `Integer`
/// clamps Int64 → Int32 and falls back to FloatValue when out of
/// range so no value silently truncates. `BadValue` projects as
/// `NullValue` — the upstream `yaml` package emits it for parse
/// inputs the loader couldn't classify.
fn yaml_to_value(y : @yaml.Yaml, use_mapping : Bool) -> Value {
  match y {
    Null => NullValue
    Boolean(b) => BoolValue(b)
    Integer(i) =>
      if i >= -2147483648L && i <= 2147483647L {
        IntValue(i.to_int())
      } else {
        FloatValue(i.to_double())
      }
    Real(d, ..) => {
      let truncated = d.to_int().to_double()
      if truncated == d && d >= -2147483648.0 && d <= 2147483647.0 {
        IntValue(d.to_int())
      } else {
        FloatValue(d)
      }
    }
    String(s) => StringValue(s)
    Array(items) => {
      let elements : Array[Value] = []
      for item in items {
        elements.push(yaml_to_value(item, use_mapping))
      }
      ListingValue(elements)
    }
    Map(map) =>
      if use_mapping {
        let entries : Array[ValueEntry] = []
        for k, v in map {
          entries.push({ key: StringValue(k), value: yaml_to_value(v, true) })
        }
        MappingValue(entries)
      } else {
        let members : Array[ValueMember] = []
        for k, v in map {
          members.push({ name: k, value: yaml_to_value(v, false) })
        }
        ObjectValue(members)
      }
    BadValue => NullValue
  }
}

///|
/// PKL-119b: materialize an IntSeq into an Array[Value] of Int
/// elements. Empty when `step > 0 && start > end` or
/// `step < 0 && start < end`; `step == 0` would be rejected by the
/// caller before reaching here (and is treated as empty here too as
/// a defensive guard).
fn intseq_materialize(start : Int, end_v : Int, step : Int) -> Array[Value] {
  let result : Array[Value] = []
  if step > 0 {
    let mut i = start
    while i <= end_v {
      result.push(IntValue(i))
      i = i + step
    }
  } else if step < 0 {
    let mut i = start
    while i >= end_v {
      result.push(IntValue(i))
      i = i + step
    }
  }
  result
}

///|
/// Number of elements an IntSeq with the given start/end/step would
/// produce. Computed in Int64 so that ranges that span the full Int32
/// width (`IntSeq(math.minInt, math.maxInt)`) don't overflow.
fn intseq_length(start : Int, end_v : Int, step : Int) -> Int64 {
  let s = start.to_int64()
  let e = end_v.to_int64()
  let st = step.to_int64()
  if st > 0L {
    if s > e {
      return 0L
    }
    return (e - s) / st + 1L
  }
  if st < 0L {
    if s < e {
      return 0L
    }
    return (s - e) / -st + 1L
  }
  0L
}

///|
/// Visible-member equality for ObjectValue operands. Compares only
/// rendered (non-hidden) properties and ignores order so
/// `{foo=1; bar=2} == {bar=2; foo=1}` agrees with Apple Pkl.
fn object_values_equal(
  xs : Array[ValueMember],
  ys : Array[ValueMember],
) -> Bool {
  let visible_xs = visible_members(xs)
  let visible_ys = visible_members(ys)
  if visible_xs.length() != visible_ys.length() {
    return false
  }
  for x in visible_xs {
    let mut matched = false
    for y in visible_ys {
      if y.name == x.name && y.value == x.value {
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// Map / Mapping content equality — key/value order is immaterial; two
/// entries with the same key/value pair regardless of position match.
fn map_entries_equal(xs : Array[ValueEntry], ys : Array[ValueEntry]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let consumed : Array[Bool] = Array::make(ys.length(), false)
  for x in xs {
    let mut matched = false
    for j = 0; j < ys.length(); j = j + 1 {
      if !consumed[j] && ys[j].key == x.key && ys[j].value == x.value {
        consumed[j] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// Multiset equality for SetValue operands — Apple Pkl treats two Sets
/// as equal when they hold the same elements regardless of insertion
/// order. Quadratic, but Sets in practice are small.
fn set_values_equal(xs : Array[Value], ys : Array[Value]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let consumed : Array[Bool] = Array::make(ys.length(), false)
  for x in xs {
    let mut matched = false
    for j = 0; j < ys.length(); j = j + 1 {
      if !consumed[j] && ys[j] == x {
        consumed[j] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// PKL-119be (IntSeq equality follow-up): two IntSeqs are equal when
/// they produce the same Int sequence. Compute lengths without
/// materializing — for arithmetic progressions equality reduces to
/// matching length, start, and step (step doesn't matter when len <= 1).
fn intseq_value_equal(
  start_a : Int,
  end_a : Int,
  step_a : Int,
  start_b : Int,
  end_b : Int,
  step_b : Int,
) -> Bool {
  let len_a = intseq_length(start_a, end_a, step_a)
  let len_b = intseq_length(start_b, end_b, step_b)
  if len_a != len_b {
    return false
  }
  if len_a == 0 {
    return true
  }
  if start_a != start_b {
    return false
  }
  if len_a == 1 {
    return true
  }
  step_a == step_b
}

///|
fn is_listing_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: PKL-base Listing properties — `isNotEmpty`, `isDistinct`,
    // `firstOrNull`, `lastOrNull`, `toList`, `toSet`. Apple Pkl projects
    // them as zero-arg property reads (no parens) since the underlying
    // method has no parameters.
    | "isNotEmpty"
    | "isDistinct"
    | "firstOrNull"
    | "lastOrNull"
    | "toList"
    | "toSet"
    | "toListing"
    | "first"
    | "last"
    | "distinct" => true
    _ => false
  }
}

///|
fn is_listing_method_name(name : String) -> Bool {
  match name {
    "contains"
    | "fold"
    | "map"
    | "filter"
    | "take"
    | "drop"
    | "join"
    | "reverse"
    // PKL-148: pkl:base Listing surface — `getOrNull(idx)`,
    // `startsWith(other)`, `endsWith(other)`, `min` / `max` / `sum`.
    | "getOrNull"
    | "startsWith"
    | "endsWith"
    // PKL-148b: Listing.isDistinctBy(keyFn) — checks whether elements
    // are unique under the key extractor.
    | "isDistinctBy"
    // PKL-134: read-only conversion methods used by pkf / pkspec's
    // shape inspection chains (`tests.toList().map(...)`).
    | "toList"
    | "toMap"
    // PKL-135: predicate / search / flatten methods used by pkspec's
    // `tagSteps`, `duplicateNames`, and rendered Mapping projections.
    | "flatMap"
    | "count"
    | "every"
    | "any"
    | "none"
    | "find"
    | "findOrNull"
    | "findLast"
    | "findLastOrNull"
    // Apple Pkl exposes the no-arg surface (`toSet`, `toListing`,
    // `first`, `last`, `firstOrNull`, `lastOrNull`, `distinct`,
    // `isEmpty`, `isNotEmpty`, `isDistinct`) as both property reads
    // and method calls; accept the `()` form too so fixtures like
    // `list.toSet()` route through the method dispatcher.
    | "toSet"
    | "toListing"
    | "first"
    | "last"
    | "firstOrNull"
    | "lastOrNull"
    | "distinct"
    | "isEmpty"
    | "isNotEmpty"
    | "isDistinct" => true
    _ => false
  }
}

///|
fn is_mapping_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: project the no-arg surface used by `.isNotEmpty` / `.entries`
    // / `.toMap` / `.toMapping` from pkl:base.
    | "isNotEmpty"
    | "entries"
    | "toMap"
    | "toMapping"
    | "keys"
    | "values" => true
    _ => false
  }
}

///|
fn is_mapping_method_name(name : String) -> Bool {
  match name {
    "containsKey"
    | "getOrNull"
    | "fold"
    // PKL-134: identity conversion methods used by pkf / pkspec.
    | "toMap"
    | "toList"
    // PKL-135: predicate methods. Upstream's Mapping.every/any/none take
    // `(Key, Value) -> Boolean`. count is upstream's `count((K, V) -> ...)`.
    | "every"
    | "any"
    | "none"
    | "count" => true
    _ => false
  }
}

///|
fn is_string_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: pkl:base.String surface — `isNotEmpty`, `isBlank`,
    // `isNotBlank`, `reverse`, `base64`, plus the surrogate-pair
    // accessors.
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars" => true
    _ => false
  }
}

///|
fn is_string_method_name(name : String) -> Bool {
  match name {
    "toUpperCase"
    | "toLowerCase"
    | "contains"
    | "startsWith"
    | "endsWith"
    | "indexOf"
    | "replaceAll"
    | "replaceFirst"
    | "take"
    | "drop"
    | "split"
    | "padStart"
    | "padEnd"
    | "toBytes"
    | "codePointAt"
    // Apple Pkl exposes the no-arg surface (`reverse`, `isEmpty`,
    // `length`, etc.) as both property reads and method calls.
    | "length"
    | "isEmpty"
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars" => true
    _ => false
  }
}

///|
fn is_int_property_name(name : String) -> Bool {
  match name {
    "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv" => true
    _ => false
  }
}

///|
fn is_int_method_name(name : String) -> Bool {
  match name {
    // PKL-148b: pkl:base Int method surface adds `isBetween(a, b)`,
    // `toFloat()`, `shl` / `shr` / `ushr` / `or` / `and` / `xor`.
    "toString"
    | "toChar"
    | "toFloat"
    | "isBetween"
    // No-arg property surface also accessible as `(N).method()`.
    | "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv" => true
    _ => false
  }
}

///|
/// PKL-148: pkl:base Boolean method names.
fn is_bool_method_name(name : String) -> Bool {
  match name {
    "xor" | "implies" | "and" | "or" | "toString" => true
    _ => false
  }
}

///|
/// PKL-148: pkl:base Float method names. Mirrors `is_int_method_name`
/// but routes through `eval_float_method`.
fn is_float_method_name(name : String) -> Bool {
  match name {
    "toString"
    | "abs"
    | "round"
    | "floor"
    | "ceil"
    // No-arg property surface — callable as `(x).isNaN()` etc.
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign" => true
    _ => false
  }
}

///|
fn is_duration_unit_name(name : String) -> Bool {
  match name {
    "ns" | "us" | "ms" | "s" | "min" | "h" | "d" => true
    _ => false
  }
}

///|
fn is_datasize_unit_name(name : String) -> Bool {
  match name {
    "b"
    | "kb"
    | "kib"
    | "mb"
    | "mib"
    | "gb"
    | "gib"
    | "tb"
    | "tib"
    | "pb"
    | "pib" => true
    _ => false
  }
}

///|
/// Position of a Duration unit on the ns..d ladder. Returned values are
/// only used for ordering and adjacent-step lookups — the absolute
/// factor between two units is reconstructed by walking the ladder a
/// step at a time so the intermediate magnitude never overflows Int32
/// (a flat `min`-to-ns factor would already need ≥ 6e10).
fn duration_unit_level(unit : String) -> Int {
  match unit {
    "ns" => 0
    "us" => 1
    "ms" => 2
    "s" => 3
    "min" => 4
    "h" => 5
    "d" => 6
    _ => -1
  }
}

///|
/// Integer factor that scales one unit at `level` to the next-finer unit
/// at `level - 1` (e.g. `min` → `s` is 60, `s` → `ms` is 1000).
fn duration_step_factor(level : Int) -> Int {
  match level {
    1 => 1000 // us -> ns
    2 => 1000 // ms -> us
    3 => 1000 // s  -> ms
    4 => 60 // min -> s
    5 => 60 // h   -> min
    6 => 24 // d   -> h
    _ => 1
  }
}

///|
/// Factor from a DataSize unit to bytes. Values up to `gib` (≈ 1.07e9)
/// fit in Int32; `tb` and beyond overflow and return -1 so callers can
/// detect the gap and skip mixed-unit arithmetic. This is the
/// documented PKL-082 ceiling — promoting larger units to lossless
/// arithmetic needs Int64 in the value model.
fn datasize_byte_factor(unit : String) -> Int {
  match unit {
    "b" => 1
    "kb" => 1000
    "kib" => 1024
    "mb" => 1_000_000
    "mib" => 1_048_576
    "gb" => 1_000_000_000
    "gib" => 1_073_741_824
    "tb" | "tib" | "pb" | "pib" => -1
    _ => -1
  }
}

///|
/// Pick the unit with the smaller magnitude-per-unit so the resulting
/// arithmetic always rounds toward the finer side and stays expressible
/// in Int. For Duration this collapses to the ladder ordering (ns < us <
/// ms < s < min < h < d). For DataSize the comparison is by direct
/// byte factor (with the `tb`+ overflow ceiling caveat).
fn smaller_duration_unit(a : String, b : String) -> String {
  if duration_unit_level(a) <= duration_unit_level(b) {
    a
  } else {
    b
  }
}

///|
fn smaller_datasize_unit(a : String, b : String) -> String {
  let fa = datasize_byte_factor(a)
  let fb = datasize_byte_factor(b)
  if fa < 0 || fb < 0 {
    // tb / tib / pb / pib do not participate in mixed-unit arithmetic in
    // this slice; pick `a` deterministically so callers see a stable
    // result without a panic. Mixed-unit ops involving these will hit
    // the overflow-guarded path below.
    a
  } else if fa <= fb {
    a
  } else {
    b
  }
}

///|
/// Convert `magnitude` from `from_unit` to `to_unit` by walking one step
/// along the unit ladder at a time. Coarser→finer multiplies by each
/// step factor; finer→coarser divides (truncating). Stepping avoids the
/// overflow that a flat `factor_to_ns / factor_to_target` would hit on
/// `min`, `h`, or `d`.
fn duration_in_unit(
  magnitude : Double,
  from_unit : String,
  to_unit : String,
) -> Double {
  let from = duration_unit_level(from_unit)
  let to = duration_unit_level(to_unit)
  let mut m = magnitude
  let mut level = from
  while level > to {
    m = m * duration_step_factor(level).to_double()
    level = level - 1
  }
  while level < to {
    m = m / duration_step_factor(level + 1).to_double()
    level = level + 1
  }
  m
}

///|
/// Convert `magnitude` from `from_unit` to `to_unit` for DataSize. Both
/// units must fit in the Int32 byte-factor range (`b`..`gib`); callers
/// that mix `tb`+ units guard against the -1 sentinel from
/// `datasize_byte_factor` first.
fn datasize_in_unit(
  magnitude : Double,
  from_unit : String,
  to_unit : String,
) -> Double {
  let from_f = datasize_byte_factor(from_unit)
  let to_f = datasize_byte_factor(to_unit)
  if from_f < 0 || to_f < 0 {
    return magnitude
  }
  if from_f == to_f {
    magnitude
  } else if from_f > to_f {
    magnitude * (from_f / to_f).to_double()
  } else {
    magnitude / (to_f / from_f).to_double()
  }
}

///|
fn is_regex_method_name(name : String) -> Bool {
  match name {
    "matches" | "find" | "findAll" | "replace" | "replaceAll" => true
    _ => false
  }
}

///|
fn is_bytes_method_name(name : String) -> Bool {
  match name {
    "getOrNull" | "toList" => true
    _ => false
  }
}

///|
/// Build a `BytesValue` from a Listing of Int byte values. Each entry
/// must be in the 0..=255 range; an out-of-range or non-Int element
/// records a diagnostic and bails. The resulting `Bytes` is owned by
/// the new `BytesValue` and shared by reference for the lifetime of
/// the value (MoonBit `Bytes` is immutable).
fn build_bytes_from_int_listing(
  elements : Array[Value],
  diagnostics : Array[Diagnostic],
) -> Value? {
  let buf : Array[Byte] = []
  for element in elements {
    match element {
      IntValue(n) =>
        if n < 0 || n > 255 {
          diagnostics.push(diag("Bytes element \{n} is out of range 0..255"))
          return None
        } else {
          buf.push(n.to_byte())
        }
      _ => {
        diagnostics.push(
          diag(
            "Bytes element must be Int, got \{eval_value_type_name(element)}",
          ),
        )
        return None
      }
    }
  }
  Some(BytesValue(Bytes::from_array(buf)))
}

///|
fn eval_bytes_property(
  bytes : Bytes,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(bytes.length()))
    "base64" => Some(StringValue(@base64.encode(bytes[:])))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Bytes`."),
      )
      None
    }
  }
}

///|
fn eval_bytes_method(
  bytes : Bytes,
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
    return None
  }
  match method_name {
    "getOrNull" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          IntValue(index) =>
            if index < 0 || index >= bytes.length() {
              Some(NullValue)
            } else {
              Some(IntValue(bytes[index].to_int()))
            }
          _ => {
            diagnostics.push(diag("Bytes.getOrNull expects an Int argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Bytes.getOrNull expects exactly one argument"))
        None
      }
    "toList" =>
      if arg_values.length() == 0 {
        let elements : Array[Value] = []
        for i = 0; i < bytes.length(); i = i + 1 {
          elements.push(IntValue(bytes[i].to_int()))
        }
        Some(ListValue(elements))
      } else {
        diagnostics.push(diag("Bytes.toList takes no arguments"))
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Bytes`."),
      )
      None
    }
  }
}

///|
/// Compile `pattern` via `moonbitlang/regexp`. Returns `None` and pushes
/// a diagnostic on syntax errors so callers can bail out without
/// propagating a raise. Each call recompiles — the value model only
/// caches the source string so equality stays decidable on the surface.
fn compile_regex_pattern(
  pattern : String,
  diagnostics : Array[Diagnostic],
) -> @regexp.Regexp? {
  Some(@regexp.compile(pattern)) catch {
    err => {
      diagnostics.push(diag("invalid Regex pattern: \{err}"))
      None
    }
  }
}

///|
fn regex_matches_full(re : @regexp.Regexp, input : String) -> Bool {
  let m = re.execute(input)
  if !m.matched() {
    return false
  }
  // Full-input match: the captured slice must cover the entire input
  // with nothing before or after. `before` / `after` come back as views
  // so an empty view means the match anchored at both ends.
  m.before().length() == 0 && m.after().length() == 0
}

///|
fn regex_find_first(re : @regexp.Regexp, input : String) -> String? {
  match re.match_(input) {
    Some(m) =>
      match m.get(0) {
        Some(view) => Some(view.to_owned())
        None => None
      }
    None => None
  }
}

///|
/// Repeatedly execute the regex on the remaining suffix, collecting each
/// match's text. Advances by at least one character on zero-width
/// matches so the walk always terminates.
fn regex_find_all(re : @regexp.Regexp, input : String) -> Array[String] {
  let out : Array[String] = []
  let mut rest = input
  while rest.length() > 0 {
    match re.match_(rest) {
      Some(m) =>
        match m.get(0) {
          Some(view) => {
            let matched_text = view.to_owned()
            out.push(matched_text)
            let after = m.after().to_owned()
            if matched_text.length() == 0 && after.length() == rest.length() {
              // Zero-width match at the head of `rest`: skip one char to
              // avoid an infinite loop.
              if rest.length() <= 1 {
                rest = ""
              } else {
                rest = String::unsafe_substring(
                  rest,
                  start=1,
                  end=rest.length(),
                )
              }
            } else {
              rest = after
            }
          }
          None => break
        }
      None => break
    }
  }
  out
}

///|
fn regex_replace_first(
  re : @regexp.Regexp,
  input : String,
  replacement : String,
) -> String {
  match re.match_(input) {
    Some(m) => {
      let buf = StringBuilder::new()
      buf.write_string(m.before().to_owned())
      buf.write_string(replacement)
      buf.write_string(m.after().to_owned())
      buf.to_string()
    }
    None => input
  }
}

///|
fn regex_replace_all(
  re : @regexp.Regexp,
  input : String,
  replacement : String,
) -> String {
  let buf = StringBuilder::new()
  let mut rest = input
  while rest.length() > 0 {
    match re.match_(rest) {
      Some(m) =>
        match m.get(0) {
          Some(view) => {
            let matched_text = view.to_owned()
            buf.write_string(m.before().to_owned())
            buf.write_string(replacement)
            let after = m.after().to_owned()
            if matched_text.length() == 0 && after.length() == rest.length() {
              // Zero-width match: emit the first char verbatim then
              // continue, so substitution never spins.
              if rest.length() >= 1 {
                buf.write_string(String::unsafe_substring(rest, start=0, end=1))
              }
              if rest.length() <= 1 {
                rest = ""
              } else {
                rest = String::unsafe_substring(
                  rest,
                  start=1,
                  end=rest.length(),
                )
              }
            } else {
              rest = after
            }
          }
          None => {
            buf.write_string(rest)
            rest = ""
          }
        }
      None => {
        buf.write_string(rest)
        rest = ""
      }
    }
  }
  buf.to_string()
}

///|
fn contains_entry_key(entries : Array[ValueEntry], key : Value) -> Bool {
  for entry in entries {
    if entry.key == key {
      return true
    }
  }
  false
}

///|
fn contains_value(xs : Array[Value], v : Value) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

///|
fn value_to_string_for_join(v : Value) -> String {
  match v {
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    StringValue(s) => s
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(v, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn eval_listing_property(
  elements : Array[Value],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(elements.length()))
    "isEmpty" => Some(BoolValue(elements.length() == 0))
    "isNotEmpty" => Some(BoolValue(elements.length() != 0))
    "isDistinct" => {
      let seen : Array[Value] = []
      let mut distinct = true
      for v in elements {
        if contains_value(seen, v) {
          distinct = false
          break
        }
        seen.push(v)
      }
      Some(BoolValue(distinct))
    }
    "firstOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(elements[0])
      }
    "lastOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(elements[elements.length() - 1])
      }
    // PKL-148h: `.toList()` tags as `ListValue` (round-trips through
    // the `List(...)` constructor form); `.toListing()` keeps the
    // Listing block tag. `.toSet` deduplicates and tags as Set.
    "toList" => Some(ListValue(elements))
    "toListing" => Some(ListingValue(elements))
    "toSet" => {
      let seen : Array[Value] = []
      for v in elements {
        if !contains_value(seen, v) {
          seen.push(v)
        }
      }
      Some(SetValue(seen))
    }
    "first" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Listing.first on empty Listing"))
        None
      } else {
        Some(elements[0])
      }
    "last" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Listing.last on empty Listing"))
        None
      } else {
        Some(elements[elements.length() - 1])
      }
    "distinct" => {
      let seen : Array[Value] = []
      for v in elements {
        if !contains_value(seen, v) {
          seen.push(v)
        }
      }
      Some(ListingValue(seen))
    }
    _ => None
  }
}

///|
fn eval_listing_method(
  elements : Array[Value],
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
    return None
  }
  match method_name {
    "contains" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.contains expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(BoolValue(contains_value(elements, arg_values[0])))
    }
    "isDistinctBy" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.isDistinctBy expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let keys : Array[Value] = []
      let mut distinct = true
      for element in elements {
        match
          apply_function_value(
            "Listing.isDistinctBy keyFn",
            arg_values[0],
            [element],
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
            if contains_value(keys, key) {
              distinct = false
              break
            } else {
              keys.push(key)
            }
          None => return None
        }
      }
      Some(BoolValue(distinct))
    }
    // PKL-148: pkl:base Listing.getOrNull(index) — returns the element
    // at `index` or null when out of bounds. Apple Pkl's signature is
    // `(Int) -> T?`.
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.getOrNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx) =>
          if idx >= 0 && idx < elements.length() {
            Some(elements[idx])
          } else {
            Some(NullValue)
          }
        _ => {
          diagnostics.push(diag("Listing.getOrNull expects an Int index"))
          None
        }
      }
    }
    // PKL-148: pkl:base Listing.startsWith(other) / endsWith(other) —
    // structural prefix / suffix match against another Listing.
    "startsWith" | "endsWith" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        ListingValue(other) | ListValue(other) | SetValue(other) =>
          if other.length() > elements.length() {
            Some(BoolValue(false))
          } else {
            let offset = if method_name == "startsWith" {
              0
            } else {
              elements.length() - other.length()
            }
            let mut equal = true
            for i = 0; i < other.length(); i = i + 1 {
              if elements[i + offset] != other[i] {
                equal = false
                break
              }
            }
            Some(BoolValue(equal))
          }
        _ => {
          diagnostics.push(
            diag("Listing.\{method_name} expects a Listing argument"),
          )
          None
        }
      }
    }
    "reverse" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.reverse expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let reversed : Array[Value] = []
      let mut i = elements.length() - 1
      while i >= 0 {
        reversed.push(elements[i])
        i = i - 1
      }
      Some(ListingValue(reversed))
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.take expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
          }
          let result : Array[Value] = []
          for i = 0; i < n; i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(diag("Listing.take expects Int argument"))
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.drop expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
          }
          let result : Array[Value] = []
          for i = n; i < elements.length(); i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(diag("Listing.drop expects Int argument"))
          None
        }
      }
    }
    "join" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.join expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(sep) => {
          let buf = StringBuilder::new()
          for i = 0; i < elements.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(sep)
            }
            buf.write_string(value_to_string_for_join(elements[i]))
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(diag("Listing.join expects String separator"))
          None
        }
      }
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.map callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => result.push(v)
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.filter predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(element)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(
              diag("Listing.filter predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Listing.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for element in elements {
        match
          apply_function_value(
            "Listing.fold combine",
            callback,
            [acc, element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    // PKL-148h: `.toList()` on a Listing returns a `ListValue` so the
    // renderer projects through the `List(...)` constructor form. The
    // arity guard is preserved from the PKL-134 implementation. `.toMap`
    // on a Listing without Pair entries is the empty map — matches
    // Apple Pkl's behaviour when the Listing is not a Listing-of-Pair.
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Listing.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(ListValue(elements))
    }
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Listing.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MappingValue([]))
    }
    // PKL-135: flatMap concatenates the listing results of each element's
    // transform call. Upstream allows Collection<Result> (List | Listing | Set);
    // pkl-mbt collapses those into ListingValue, so the shape stays consistent.
    "flatMap" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.flatMap expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.flatMap callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(ListingValue(inner)) | Some(ListValue(inner)) =>
            for v in inner {
              result.push(v)
            }
          Some(_) => {
            diagnostics.push(
              diag("Listing.flatMap callback must return Listing"),
            )
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for element in elements {
        match
          apply_function_value(
            "Listing.count predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => n = n + 1
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(
              diag("Listing.count predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n))
    }
    "every" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.every expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.every predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => ()
          Some(BoolValue(false)) => return Some(BoolValue(false))
          Some(_) => {
            diagnostics.push(
              diag("Listing.every predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "any" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.any expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.any predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(true))
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Listing.any predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(false))
    }
    "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.none expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.none predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(false))
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Listing.none predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "find" | "findOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.\{method_name} predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(element)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(
              diag("Listing.\{method_name} predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      // Apple Pkl: `find` throws when no match, `findOrNull` returns null.
      if method_name == "findOrNull" {
        Some(NullValue)
      } else {
        diagnostics.push(diag("Listing.find did not match any element"))
        None
      }
    }
    "findLast" | "findLastOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut i = elements.length() - 1
      while i >= 0 {
        let element = elements[i]
        match
          apply_function_value(
            "Listing.\{method_name} predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(element)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(
              diag("Listing.\{method_name} predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
        i = i - 1
      }
      if method_name == "findLastOrNull" {
        Some(NullValue)
      } else {
        diagnostics.push(diag("Listing.findLast did not match any element"))
        None
      }
    }
    // Apple Pkl allows zero-arg property reads (e.g. `list.toSet`) to be
    // written as method calls (`list.toSet()`). Delegate the no-arg
    // surface back to the property evaluator so both forms agree.
    "toSet"
    | "toListing"
    | "first"
    | "last"
    | "firstOrNull"
    | "lastOrNull"
    | "distinct"
    | "isEmpty"
    | "isNotEmpty"
    | "isDistinct" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_listing_property(elements, method_name, diagnostics)
      }
    _ => None
  }
}

///|
fn eval_mapping_property(
  entries : Array[ValueEntry],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(entries.length()))
    "isEmpty" => Some(BoolValue(entries.length() == 0))
    "isNotEmpty" => Some(BoolValue(entries.length() != 0))
    "keys" => {
      let keys : Array[Value] = []
      for entry in entries {
        keys.push(entry.key)
      }
      Some(ListingValue(keys))
    }
    "values" => {
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(ListingValue(values))
    }
    "entries" => {
      // PKL-148: `Mapping.entries` projects to a Listing of
      // Pair<Key, Value> mirroring `Map.entries`.
      let pairs : Array[Value] = []
      for entry in entries {
        pairs.push(PairValue(entry.key, entry.value))
      }
      Some(ListingValue(pairs))
    }
    "toMap" => {
      // PKL-148: lift the Mapping into a Map value preserving order.
      let kvs : Array[ValueEntry] = []
      for entry in entries {
        kvs.push({ key: entry.key, value: entry.value })
      }
      Some(MapValue(kvs))
    }
    "toMapping" => Some(MappingValue(entries))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Mapping`."),
      )
      None
    }
  }
}

///|
/// PKL-119b: dispatch methods on an IntSeqValue. `step(newValue)`
/// returns a new IntSeq with the carrier step replaced; `toList` /
/// `toListing` materialize to a `ListingValue` (the two are aliased
/// until PKL-119c/d split List / Mapping out); `map(f)` materializes
/// then applies the lambda to each element; `fold(initial, op)`
/// reduces left-to-right.
fn eval_intseq_method(
  start : Int,
  end_v : Int,
  step : Int,
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
    return None
  }
  match method_name {
    "step" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("IntSeq.step expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(new_step) =>
          if new_step == 0 {
            diagnostics.push(diag("IntSeq.step rejects 0"))
            None
          } else {
            Some(IntSeqValue(start, end_v, new_step))
          }
        _ => {
          diagnostics.push(diag("IntSeq.step expects Int"))
          None
        }
      }
    }
    "toList" | "toListing" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "IntSeq.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(ListingValue(intseq_materialize(start, end_v, step)))
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("IntSeq.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let elements = intseq_materialize(start, end_v, step)
      let mapped : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "IntSeq.map callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => mapped.push(v)
          None => return None
        }
      }
      Some(ListingValue(mapped))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("IntSeq.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let elements = intseq_materialize(start, end_v, step)
      for element in elements {
        match
          apply_function_value(
            "IntSeq.fold operator",
            arg_values[1],
            [acc, element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    _ => {
      diagnostics.push(
        diag(
          "Cannot find property `\{method_name}` in object of type `IntSeq`.",
        ),
      )
      None
    }
  }
}

///|
/// PKL-119c: dispatch methods on a `SetValue`. `.contains(x)` reuses
/// the same value-equality helper as Listing; `.toList()` /
/// `.toListing()` materialise into a `ListingValue` (the two are
/// aliased until PKL-119d splits List / Map out); `.toSet()` is
/// identity since the receiver is already a Set; `.map` / `.filter`
/// / `.fold` / `.join` mirror the Listing surface but return into a
/// `ListingValue` (mapped Sets keep insertion order but the upstream
/// signature for `Set.map` is `Listing<Out>`, not `Set<Out>`).
fn eval_set_method(
  elements : Array[Value],
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
    return None
  }
  match method_name {
    "contains" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.contains expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      Some(BoolValue(contains_value(elements, arg_values[0])))
    }
    // PKL-148: `Set.add(x)` returns a new Set with `x` appended (no-op
    // when the element already belongs). Apple Pkl's signature is
    // `add(Value) -> Set` — non-mutating.
    "add" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.add expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let next : Array[Value] = []
      for v in elements {
        next.push(v)
      }
      if !contains_value(next, arg_values[0]) {
        next.push(arg_values[0])
      }
      Some(SetValue(next))
    }
    "firstOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(elements[0])
      }
    "lastOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(elements[elements.length() - 1])
      }
    "every" | "any" | "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Set.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut hit = false
      for element in elements {
        match
          apply_function_value(
            "Set.\{method_name} predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => {
            hit = true
            if method_name == "any" || method_name == "none" {
              break
            }
          }
          Some(BoolValue(false)) =>
            if method_name == "every" {
              return Some(BoolValue(false))
            }
          Some(_) => {
            diagnostics.push(
              diag("Set.\{method_name} predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      match method_name {
        "every" => Some(BoolValue(true))
        "any" => Some(BoolValue(hit))
        "none" => Some(BoolValue(!hit))
        _ => None
      }
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for element in elements {
        match
          apply_function_value(
            "Set.count predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => n = n + 1
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Set.count predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n))
    }
    "toList" | "toListing" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Set.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      // PKL-148h: `Set.toList` → `ListValue`, `Set.toListing` →
      // `ListingValue`. Element order is preserved (Set walks in
      // insertion order, matching the Apple Pkl PCF projection).
      if method_name == "toList" {
        Some(ListValue(elements))
      } else {
        Some(ListingValue(elements))
      }
    }
    "toSet" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Set.toSet expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(SetValue(elements))
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Set.map callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => result.push(v)
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Set.filter predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(element)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Set.filter predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(SetValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Set.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      for element in elements {
        match
          apply_function_value(
            "Set.fold operator",
            arg_values[1],
            [acc, element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    "join" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.join expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(separator) => {
          let buf = StringBuilder::new()
          for i = 0; i < elements.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(separator)
            }
            match elements[i] {
              StringValue(s) => buf.write_string(s)
              other => render_pcf_inline(other, 0, buf)
            }
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(diag("Set.join expects String separator"))
          None
        }
      }
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{method_name}` in object of type `Set`."),
      )
      None
    }
  }
}

///|
/// PKL-119d: dispatch methods on a `MapValue`. The lookup methods
/// (`getOrNull` / `containsKey` / `getOrThrow`) use the same value-
/// equality helper as `contains_value` so any key type that derives
/// Eq works (Pkl supports arbitrary key types). Projection helpers
/// materialize into the matching variant — `.toMap` is identity,
/// `.toMapping` re-projects into the object-style `MappingValue`,
/// `.toList` walks the entries as `Listing<Pair<K, V>>`. `.map(f)`
/// expects a `(key, value) -> Pair<NewKey, NewValue>` lambda; for
/// the MVP we accept the upstream convention. `.filter` and `.fold`
/// mirror the same pattern as Listing / Set.
fn eval_map_method(
  entries : Array[ValueEntry],
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
    return None
  }
  match method_name {
    "containsKey" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.containsKey expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(BoolValue(true))
        }
      }
      Some(BoolValue(false))
    }
    "containsValue" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Map.containsValue expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let v = arg_values[0]
      for entry in entries {
        if entry.value == v {
          return Some(BoolValue(true))
        }
      }
      Some(BoolValue(false))
    }
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.getOrNull expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(entry.value)
        }
      }
      Some(NullValue)
    }
    "getOrThrow" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.getOrThrow expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(entry.value)
        }
      }
      diagnostics.push(diag("Map.getOrThrow: key not found"))
      None
    }
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MapValue(entries))
    }
    "toMapping" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toMapping expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MappingValue(entries))
    }
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let pairs : Array[Value] = []
      for entry in entries {
        pairs.push(PairValue(entry.key, entry.value))
      }
      Some(ListingValue(pairs))
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.map callback",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(PairValue(new_key, new_value)) =>
            result.push({ key: new_key, value: new_value })
          Some(_) => {
            diagnostics.push(
              diag("Map.map callback must return Pair<NewKey, NewValue>"),
            )
            return None
          }
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.filter predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(entry)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Map.filter predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Map.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      for entry in entries {
        match
          apply_function_value(
            "Map.fold operator",
            arg_values[1],
            [acc, entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{method_name}` in object of type `Map`."),
      )
      None
    }
  }
}

///|
fn eval_mapping_method(
  entries : Array[ValueEntry],
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
    return None
  }
  match method_name {
    "containsKey" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.containsKey expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(BoolValue(contains_entry_key(entries, arg_values[0])))
    }
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.getOrNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match lookup_entry(entries, arg_values[0]) {
        Some(v) => Some(v)
        None => Some(NullValue)
      }
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Mapping.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for entry in entries {
        match
          apply_function_value(
            "Mapping.fold combine",
            callback,
            [acc, entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    // PKL-134: identity conversion. toMap on a Mapping is self;
    // toList projects the entries' values (matching Apple Pkl's
    // `Map.values.toList()` shape closely enough for shape-only chains).
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Mapping.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MappingValue(entries))
    }
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Mapping.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(ListingValue(values))
    }
    // PKL-135: predicate methods. Upstream's signature is
    // `(Key, Value) -> Boolean` for every / any; pkl-mbt mirrors that.
    "every" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.every expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.every predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => ()
          Some(BoolValue(false)) => return Some(BoolValue(false))
          Some(_) => {
            diagnostics.push(
              diag("Mapping.every predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "any" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.any expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.any predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(true))
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Mapping.any predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(false))
    }
    "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.none expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.none predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(false))
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Mapping.none predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for entry in entries {
        match
          apply_function_value(
            "Mapping.count predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => n = n + 1
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(
              diag("Mapping.count predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n))
    }
    _ => None
  }
}

///|
fn eval_int_property(
  n : Int,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "abs" => if n < 0 { Some(IntValue(0 - n)) } else { Some(IntValue(n)) }
    "isEven" => Some(BoolValue(n % 2 == 0))
    "isOdd" => Some(BoolValue(n % 2 != 0))
    // PKL-148: pkl:base Int zero-arg accessors.
    "isPositive" => Some(BoolValue(n >= 0))
    "isNonZero" => Some(BoolValue(n != 0))
    "isFinite" => Some(BoolValue(true))
    "isNaN" => Some(BoolValue(false))
    "isInfinite" => Some(BoolValue(false))
    "sign" =>
      if n > 0 {
        Some(IntValue(1))
      } else if n < 0 {
        Some(IntValue(-1))
      } else {
        Some(IntValue(0))
      }
    "inv" => Some(IntValue(n.lnot()))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Int`."),
      )
      None
    }
  }
}

///|
/// Float counterpart of `eval_int_property`. Apple Pkl exposes the
/// same no-arg surface (`abs`, `isPositive`, `isNaN`, …) on Float.
fn eval_float_property(
  d : Double,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "abs" => Some(FloatValue(if d < 0.0 { -d } else { d }))
    "isPositive" => Some(BoolValue(d >= 0.0))
    "isNonZero" => Some(BoolValue(d != 0.0))
    "isFinite" => Some(BoolValue(!d.is_nan() && !d.is_inf()))
    "isNaN" => Some(BoolValue(d.is_nan()))
    "isInfinite" => Some(BoolValue(d.is_inf()))
    "sign" =>
      if d > 0.0 {
        Some(FloatValue(1.0))
      } else if d < 0.0 {
        Some(FloatValue(-1.0))
      } else {
        Some(FloatValue(0.0))
      }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Float`."),
      )
      None
    }
  }
}

///|
fn is_float_property_name(name : String) -> Bool {
  match name {
    "abs"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign" => true
    _ => false
  }
}

///|
fn eval_duration_property(
  magnitude : Double,
  unit : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "value" => Some(magnitude_as_value(magnitude))
    "unit" => Some(StringValue(unit))
    "isPositive" => Some(BoolValue(magnitude >= 0.0))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Duration`."),
      )
      None
    }
  }
}

///|
fn eval_datasize_property(
  magnitude : Double,
  unit : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "value" => Some(magnitude_as_value(magnitude))
    "unit" => Some(StringValue(unit))
    "isPositive" => Some(BoolValue(magnitude >= 0.0))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `DataSize`."),
      )
      None
    }
  }
}

///|
/// PKL-121: project a magnitude back to an `IntValue` when it has no
/// fractional component and fits in `Int`, otherwise expose it as
/// `FloatValue`. Keeps the common Int-magnitude path observationally
/// identical to the pre-PKL-121 behaviour (`.value` on `5.min` is
/// still `5`, not `5.0`).
fn magnitude_as_value(magnitude : Double) -> Value {
  let rounded = magnitude.to_int()
  if rounded.to_double() == magnitude {
    IntValue(rounded)
  } else {
    FloatValue(magnitude)
  }
}

///|
fn int_to_string_radix(n : Int, radix : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let negative = n < 0
  let mut value = if negative { 0 - n } else { n }
  let chars : Array[Char] = []
  while value > 0 {
    let d = value % radix
    chars.push(digits.unsafe_get(d).to_int().unsafe_to_char())
    value = value / radix
  }
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  let mut i = chars.length() - 1
  while i >= 0 {
    buf.write_char(chars[i])
    i = i - 1
  }
  buf.to_string()
}

///|
fn eval_int_method(
  n : Int,
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
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        Some(StringValue("\{n}"))
      } else if arg_values.length() == 1 {
        match arg_values[0] {
          IntValue(radix) =>
            if radix < 2 || radix > 36 {
              diagnostics.push(
                diag(
                  "Int.toString radix must be between 2 and 36, got \{radix}",
                ),
              )
              None
            } else {
              Some(StringValue(int_to_string_radix(n, radix)))
            }
          _ => {
            diagnostics.push(diag("Int.toString radix must be Int"))
            None
          }
        }
      } else {
        diagnostics.push(
          diag(
            "Int.toString expects 0 or 1 arguments, got \{arg_values.length()}",
          ),
        )
        None
      }
    "toChar" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Int.toChar expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      if n < 0 || n > 0x10FFFF {
        diagnostics.push(diag("Int.toChar code point out of range: \{n}"))
        return None
      }
      let buf = StringBuilder::new()
      buf.write_char(n.unsafe_to_char())
      Some(StringValue(buf.to_string()))
    }
    // PKL-148b: Int.isBetween(lower, upper) — inclusive range check.
    "isBetween" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Int.isBetween expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let lower = match arg_values[0] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Int.isBetween expects Number arguments"))
          return None
        }
      }
      let upper = match arg_values[1] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Int.isBetween expects Number arguments"))
          return None
        }
      }
      let v = n.to_double()
      Some(BoolValue(v >= lower && v <= upper))
    }
    // PKL-148b: Int.toFloat() — widens to Float (no precision loss).
    "toFloat" =>
      if arg_values.length() == 0 {
        Some(FloatValue(n.to_double()))
      } else {
        diagnostics.push(diag("Int.toFloat takes no arguments"))
        None
      }
    // No-arg property surface accessible as `(N).abs()` / `.isEven()`
    // / `.sign()` / etc.
    "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Int.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_int_property(n, method_name, diagnostics)
      }
    _ => None
  }
}

///|
/// PKL-148: pkl:base Bool method surface. Apple Pkl projects logical
/// operators (`xor` / `implies`) and the keyword-named pair (`and` /
/// `or`) as instance methods; `toString` is universal. The methods
/// take a single Boolean argument except `toString` (arity 0) and the
/// unary `not` (arity 0).
fn eval_bool_method(
  b : Bool,
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
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        if b {
          Some(StringValue("true"))
        } else {
          Some(StringValue("false"))
        }
      } else {
        diagnostics.push(diag("Bool.toString takes no arguments"))
        None
      }
    "xor" | "implies" | "and" | "or" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          BoolValue(other) =>
            match method_name {
              "xor" => Some(BoolValue(b != other))
              "implies" => Some(BoolValue(!b || other))
              "and" => Some(BoolValue(b && other))
              "or" => Some(BoolValue(b || other))
              _ => None
            }
          _ => {
            diagnostics.push(
              diag("Bool.\{method_name} expects a Boolean argument"),
            )
            None
          }
        }
      } else {
        diagnostics.push(
          diag("Bool.\{method_name} expects exactly one argument"),
        )
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Boolean`."),
      )
      None
    }
  }
}

///|
/// PKL-148: pkl:base Float method surface. Most Float operations
/// share the Int name surface; the runtime intercepts a small set
/// of float-specific names (`isNaN`, `isFinite`, `isInfinite`).
fn eval_float_method(
  d : Double,
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
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        Some(StringValue(render_float_text(d)))
      } else {
        diagnostics.push(diag("Float.toString takes no arguments"))
        None
      }
    "abs" =>
      if arg_values.length() == 0 {
        Some(FloatValue(if d < 0.0 { -d } else { d }))
      } else {
        diagnostics.push(diag("Float.abs takes no arguments"))
        None
      }
    "round" =>
      if arg_values.length() == 0 {
        // Round half to even (Apple Pkl's default per IEEE 754 round-to-nearest).
        let r = d.round()
        Some(IntValue(r.to_int()))
      } else {
        diagnostics.push(diag("Float.round takes no arguments"))
        None
      }
    "floor" =>
      if arg_values.length() == 0 {
        Some(FloatValue(d.floor()))
      } else {
        diagnostics.push(diag("Float.floor takes no arguments"))
        None
      }
    "ceil" =>
      if arg_values.length() == 0 {
        Some(FloatValue(d.ceil()))
      } else {
        diagnostics.push(diag("Float.ceil takes no arguments"))
        None
      }
    "isPositive" | "isNonZero" | "isFinite" | "isNaN" | "isInfinite" | "sign" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Float.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_float_property(d, method_name, diagnostics)
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Float`."),
      )
      None
    }
  }
}

///|
fn eval_duration_method(
  magnitude : Double,
  unit : String,
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
    return None
  }
  match method_name {
    "toUnit" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(target) =>
            if is_duration_unit_name(target) {
              Some(
                DurationValue(duration_in_unit(magnitude, unit, target), target),
              )
            } else {
              diagnostics.push(
                diag(
                  "Duration.toUnit expects one of ns/us/ms/s/min/h/d, got \{target}",
                ),
              )
              None
            }
          _ => {
            diagnostics.push(diag("Duration.toUnit expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Duration.toUnit expects exactly one argument"))
        None
      }
    _ => {
      diagnostics.push(
        diag(
          "Cannot find method `\{method_name}` in object of type `Duration`.",
        ),
      )
      None
    }
  }
}

///|
fn eval_datasize_method(
  magnitude : Double,
  unit : String,
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
    return None
  }
  match method_name {
    "toUnit" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(target) =>
            if is_datasize_unit_name(target) {
              Some(
                DataSizeValue(datasize_in_unit(magnitude, unit, target), target),
              )
            } else {
              diagnostics.push(
                diag(
                  "DataSize.toUnit expects one of b/kb/kib/mb/mib/gb/gib/tb/tib/pb/pib, got \{target}",
                ),
              )
              None
            }
          _ => {
            diagnostics.push(diag("DataSize.toUnit expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("DataSize.toUnit expects exactly one argument"))
        None
      }
    _ => {
      diagnostics.push(
        diag(
          "Cannot find method `\{method_name}` in object of type `DataSize`.",
        ),
      )
      None
    }
  }
}

///|
fn eval_regex_property(
  pattern : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "pattern" => Some(StringValue(pattern))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Regex`."),
      )
      None
    }
  }
}

///|
fn eval_regex_method(
  pattern : String,
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
    return None
  }
  let re = match compile_regex_pattern(pattern, diagnostics) {
    Some(r) => r
    None => return None
  }
  match method_name {
    "matches" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) => Some(BoolValue(regex_matches_full(re, input)))
          _ => {
            diagnostics.push(diag("Regex.matches expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.matches expects exactly one argument"))
        None
      }
    "find" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) =>
            match regex_find_first(re, input) {
              Some(found) => Some(StringValue(found))
              None => Some(NullValue)
            }
          _ => {
            diagnostics.push(diag("Regex.find expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.find expects exactly one argument"))
        None
      }
    "findAll" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) => {
            let matches = regex_find_all(re, input)
            let elements : Array[Value] = []
            for s in matches {
              elements.push(StringValue(s))
            }
            Some(ListingValue(elements))
          }
          _ => {
            diagnostics.push(diag("Regex.findAll expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.findAll expects exactly one argument"))
        None
      }
    "replace" =>
      if arg_values.length() == 2 {
        match (arg_values[0], arg_values[1]) {
          (StringValue(input), StringValue(repl)) =>
            Some(StringValue(regex_replace_first(re, input, repl)))
          _ => {
            diagnostics.push(
              diag("Regex.replace expects (String, String) arguments"),
            )
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.replace expects exactly two arguments"))
        None
      }
    "replaceAll" =>
      if arg_values.length() == 2 {
        match (arg_values[0], arg_values[1]) {
          (StringValue(input), StringValue(repl)) =>
            Some(StringValue(regex_replace_all(re, input, repl)))
          _ => {
            diagnostics.push(
              diag("Regex.replaceAll expects (String, String) arguments"),
            )
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.replaceAll expects exactly two arguments"))
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Regex`."),
      )
      None
    }
  }
}

///|
fn eval_string_property(
  s : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(s.length()))
    "isEmpty" => Some(BoolValue(s.length() == 0))
    // PKL-148: pkl:base String zero-arg accessors. `isBlank` checks
    // for whitespace-only; `reverse` reverses code-points (not UTF-16
    // units) so surrogate pairs survive.
    "isNotEmpty" => Some(BoolValue(s.length() != 0))
    "isBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(blank))
    }
    "isNotBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(!blank))
    }
    "base64" =>
      // PKL-148: encode the string's UTF-8 bytes as standard base64.
      // Apple Pkl projects this as a property, not a method.
      Some(StringValue(@base64.encode(@utf8.encode(s))))
    "reverse" => {
      let chars : Array[Char] = []
      for c in s.iter() {
        chars.push(c)
      }
      let buf = StringBuilder::new()
      let mut i = chars.length() - 1
      while i >= 0 {
        buf.write_char(chars[i])
        i = i - 1
      }
      Some(StringValue(buf.to_string()))
    }
    // PKL-122: surrogate-pair aware properties. `length` stays
    // UTF-16 code units for compat with the existing fixture
    // baseline; `codePointCount` / `codePoints` / `chars` are the
    // new Unicode-correct view. MoonBit's `String::iter` already
    // yields full code-point `Char` values, so a single pass walks
    // surrogates correctly.
    "codePointCount" => Some(IntValue(s.char_length()))
    "codePoints" => {
      let points : Array[Value] = []
      for c in s.iter() {
        points.push(IntValue(c.to_int()))
      }
      Some(ListingValue(points))
    }
    "chars" => {
      let chars : Array[Value] = []
      for c in s.iter() {
        chars.push(StringValue(String::from_array([c][:])))
      }
      Some(ListingValue(chars))
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `String`."),
      )
      None
    }
  }
}

///|
fn pad_string(s : String, width : Int, pad : String, at_start : Bool) -> String {
  let current = s.length()
  if current >= width || pad.length() == 0 {
    return s
  }
  let buf = StringBuilder::new()
  if at_start {
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
    buf.write_string(s)
  } else {
    buf.write_string(s)
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
  }
  buf.to_string()
}

///|
fn eval_string_method(
  s : String,
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
    return None
  }
  match method_name {
    "toUpperCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toUpperCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_upper()))
    }
    "toBytes" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("String.toBytes expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(BytesValue(@utf8.encode(s[:])))
    }
    // PKL-122: code-point index lookup. `i` indexes the Unicode
    // code-point stream (surrogate-pair aware), not the UTF-16 code
    // units indexed by `String[i]` / `String.take`. Returns IntValue
    // of the code point or pushes a diagnostic if out of range.
    "codePointAt" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.codePointAt expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx) => {
          let mut count = 0
          let mut found : Int? = None
          for c in s.iter() {
            if count == idx {
              found = Some(c.to_int())
              break
            }
            count = count + 1
          }
          match found {
            Some(cp) => Some(IntValue(cp))
            None => {
              diagnostics.push(
                diag("String.codePointAt index \{idx} out of range"),
              )
              None
            }
          }
        }
        _ => {
          diagnostics.push(diag("String.codePointAt expects Int argument"))
          None
        }
      }
    }
    "toLowerCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toLowerCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_lower()))
    }
    "contains" =>
      one_string_arg(arg_values, "String.contains", diagnostics, fn(needle) {
        Some(BoolValue(s.contains(needle)))
      })
    "startsWith" =>
      one_string_arg(arg_values, "String.startsWith", diagnostics, fn(prefix) {
        Some(BoolValue(s.has_prefix(prefix)))
      })
    "endsWith" =>
      one_string_arg(arg_values, "String.endsWith", diagnostics, fn(suffix) {
        Some(BoolValue(s.has_suffix(suffix)))
      })
    "indexOf" =>
      one_string_arg(arg_values, "String.indexOf", diagnostics, fn(needle) {
        match s.find(needle) {
          Some(i) => Some(IntValue(i))
          None => Some(IntValue(-1))
        }
      })
    "replaceAll" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceAll expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace_all(old~, new=new_value)))
        _ => {
          diagnostics.push(diag("String.replaceAll expects String arguments"))
          None
        }
      }
    }
    "replaceFirst" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceFirst expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace(old~, new=new_value)))
        _ => {
          diagnostics.push(diag("String.replaceFirst expects String arguments"))
          None
        }
      }
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.take expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(StringValue(String::unsafe_substring(s, start=0, end=n)))
        }
        _ => {
          diagnostics.push(diag("String.take expects Int argument"))
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.drop expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(
            StringValue(String::unsafe_substring(s, start=n, end=s.length())),
          )
        }
        _ => {
          diagnostics.push(diag("String.drop expects Int argument"))
          None
        }
      }
    }
    "split" =>
      one_string_arg(arg_values, "String.split", diagnostics, fn(sep) {
        let parts : Array[Value] = []
        for piece in s.split(sep) {
          parts.push(StringValue(piece.to_owned()))
        }
        Some(ListingValue(parts))
      })
    "padStart" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.padStart expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, true)))
        _ => {
          diagnostics.push(
            diag("String.padStart expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    "padEnd" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("String.padEnd expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, false)))
        _ => {
          diagnostics.push(
            diag("String.padEnd expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    // No-arg property surface accessible as `string.length()` etc.
    "length"
    | "isEmpty"
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_string_property(s, method_name, diagnostics)
      }
    _ => None
  }
}

///|
fn one_string_arg(
  arg_values : Array[Value],
  label : String,
  diagnostics : Array[Diagnostic],
  body : (String) -> Value?,
) -> Value? {
  if arg_values.length() != 1 {
    diagnostics.push(
      diag("\{label} expects 1 argument, got \{arg_values.length()}"),
    )
    return None
  }
  match arg_values[0] {
    StringValue(s) => body(s)
    _ => {
      diagnostics.push(diag("\{label} expects String argument"))
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
                        diagnostics.push(
                          diag(
                            "method \{method_name} argument \{i + 1} \{message}",
                          ),
                        )
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
    _ => {
      diagnostics.push(diag("super.\{method_name} used outside a class body"))
      return None
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
fn is_pkl_math_intrinsic_call(
  callee : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> Bool {
  match callee {
    Identifier(name) =>
      pkl_math_intrinsic_arity(name) is Some(_) &&
      !stack_contains_binding(stack, name) &&
      find_binding(bindings, name) is None
    _ => false
  }
}

///|
fn pkl_math_intrinsic_arity(name : String) -> Int? {
  match name {
    "_pkl_math_sqrt"
    | "_pkl_math_log"
    | "_pkl_math_exp"
    | "_pkl_math_floor"
    | "_pkl_math_ceil"
    | "_pkl_math_round"
    | "_pkl_math_sin"
    | "_pkl_math_cos"
    | "_pkl_math_tan"
    | "_pkl_math_atan" => Some(1)
    "_pkl_math_pow" | "_pkl_math_atan2" => Some(2)
    _ => None
  }
}

///|
fn eval_pkl_math_intrinsic(
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
  let name = match callee {
    Identifier(n) => n
    _ => return None
  }
  let arity = match pkl_math_intrinsic_arity(name) {
    Some(n) => n
    None => return None
  }
  if arguments.length() != arity {
    diagnostics.push(
      diag("\{name} expects \{arity} arguments, got \{arguments.length()}"),
    )
    return None
  }
  let arg_values : Array[Double] = []
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(FloatValue(d)) => arg_values.push(d)
      Some(IntValue(n)) => arg_values.push(n.to_double())
      Some(_) => {
        diagnostics.push(diag("\{name} expects numeric arguments"))
        return None
      }
      None => return None
    }
  }
  match name {
    "_pkl_math_sqrt" => Some(FloatValue(arg_values[0].sqrt()))
    "_pkl_math_pow" => Some(FloatValue(@math.pow(arg_values[0], arg_values[1])))
    "_pkl_math_log" => Some(FloatValue(@math.ln(arg_values[0])))
    "_pkl_math_exp" => Some(FloatValue(@math.exp(arg_values[0])))
    "_pkl_math_floor" => Some(FloatValue(arg_values[0].floor()))
    "_pkl_math_ceil" => Some(FloatValue(arg_values[0].ceil()))
    "_pkl_math_round" => Some(FloatValue(arg_values[0].round()))
    "_pkl_math_sin" => Some(FloatValue(@math.sin(arg_values[0])))
    "_pkl_math_cos" => Some(FloatValue(@math.cos(arg_values[0])))
    "_pkl_math_tan" => Some(FloatValue(@math.tan(arg_values[0])))
    "_pkl_math_atan" => Some(FloatValue(@math.atan(arg_values[0])))
    "_pkl_math_atan2" =>
      Some(FloatValue(@math.atan2(arg_values[0], arg_values[1])))
    _ => None
  }
}

///|
/// PKL-123: detect `_pkl_semver_<op>` intrinsic calls and report
/// their declared arity. Same routing pattern as `pkl:math`.
fn is_pkl_semver_intrinsic_call(
  callee : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> Bool {
  match callee {
    Identifier(name) =>
      pkl_semver_intrinsic_arity(name) is Some(_) &&
      !stack_contains_binding(stack, name) &&
      find_binding(bindings, name) is None
    _ => false
  }
}

///|
fn pkl_semver_intrinsic_arity(name : String) -> Int? {
  match name {
    "_pkl_semver_parse" | "_pkl_semver_parse_or_null" => Some(1)
    "_pkl_semver_compare" => Some(2)
    _ => None
  }
}

///|
/// Parse a SemVer 2.0 string `MAJOR.MINOR.PATCH[-PRE][+BUILD]` into
/// its five components. Numeric core fields must be ASCII digits and
/// non-negative; pre-release / build segments may contain ASCII
/// alphanumerics, dots, and hyphens. Returns None on bad input.
fn pkl_semver_decompose(s : String) -> (Int, Int, Int, String?, String?)? {
  let (head, build) = match s.find("+") {
    None => (s, None)
    Some(idx) =>
      (
        String::unsafe_substring(s, start=0, end=idx),
        Some(String::unsafe_substring(s, start=idx + 1, end=s.length())),
      )
  }
  let (core, pre) = match head.find("-") {
    None => (head, None)
    Some(idx) =>
      (
        String::unsafe_substring(head, start=0, end=idx),
        Some(String::unsafe_substring(head, start=idx + 1, end=head.length())),
      )
  }
  let parts = core.split(".").collect()
  if parts.length() != 3 {
    return None
  }
  let major = parse_semver_int(parts[0].to_owned()) catch { _ => return None }
  let minor = parse_semver_int(parts[1].to_owned()) catch { _ => return None }
  let patch = parse_semver_int(parts[2].to_owned()) catch { _ => return None }
  match pre {
    Some(p) => if !is_valid_semver_identifier_list(p) { return None }
    None => ()
  }
  match build {
    Some(b) => if !is_valid_semver_identifier_list(b) { return None }
    None => ()
  }
  Some((major, minor, patch, pre, build))
}

///|
fn parse_semver_int(s : String) -> Int raise {
  if s.length() == 0 {
    fail("empty numeric segment")
  }
  let mut acc = 0
  for i in 0..<s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c < '0' || c > '9' {
      fail("non-digit in numeric segment")
    }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
  }
  acc
}

///|
fn is_valid_semver_identifier_list(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for part in s.split(".") {
    if part.length() == 0 {
      return false
    }
    for c in part.iter() {
      let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      let digit = c >= '0' && c <= '9'
      if !alpha && !digit && c != '-' {
        return false
      }
    }
  }
  true
}

///|
fn semver_value(
  major : Int,
  minor : Int,
  patch : Int,
  pre : String?,
  build : String?,
) -> Value {
  let pre_value = match pre {
    Some(p) => StringValue(p)
    None => NullValue
  }
  let build_value = match build {
    Some(b) => StringValue(b)
    None => NullValue
  }
  ObjectValue([
    { name: "major", value: IntValue(major) },
    { name: "minor", value: IntValue(minor) },
    { name: "patch", value: IntValue(patch) },
    { name: "preRelease", value: pre_value },
    { name: "build", value: build_value },
  ])
}

///|
/// SemVer pre-release ordering: dot-separated identifiers compared
/// pairwise. Numeric identifiers compare numerically; alphanumeric
/// identifiers compare lexicographically; numeric < alphanumeric;
/// fewer identifiers < more identifiers (left-aligned).
fn compare_semver_prerelease(a : String?, b : String?) -> Int {
  match (a, b) {
    (None, None) => 0
    // Version with pre-release ranks below version without pre-release.
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (Some(left), Some(right)) => {
      let left_parts = left.split(".").collect()
      let right_parts = right.split(".").collect()
      let len = if left_parts.length() < right_parts.length() {
        left_parts.length()
      } else {
        right_parts.length()
      }
      for i in 0..<len {
        let lp = left_parts[i].to_owned()
        let rp = right_parts[i].to_owned()
        let cmp = compare_semver_identifier(lp, rp)
        if cmp != 0 {
          return cmp
        }
      }
      if left_parts.length() < right_parts.length() {
        -1
      } else if left_parts.length() > right_parts.length() {
        1
      } else {
        0
      }
    }
  }
}

///|
fn is_numeric_identifier(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for c in s.iter() {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn compare_semver_identifier(a : String, b : String) -> Int {
  let a_num = is_numeric_identifier(a)
  let b_num = is_numeric_identifier(b)
  if a_num && b_num {
    let ai = parse_semver_int(a) catch { _ => return 0 }
    let bi = parse_semver_int(b) catch { _ => return 0 }
    if ai < bi {
      -1
    } else if ai > bi {
      1
    } else {
      0
    }
  } else if a_num && !b_num {
    -1
  } else if !a_num && b_num {
    1
  } else if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn compare_semver_values(a : Value, b : Value) -> Int? {
  let (a_major, a_minor, a_patch, a_pre) = match extract_semver_core(a) {
    Some(t) => t
    None => return None
  }
  let (b_major, b_minor, b_patch, b_pre) = match extract_semver_core(b) {
    Some(t) => t
    None => return None
  }
  if a_major != b_major {
    return Some(if a_major < b_major { -1 } else { 1 })
  }
  if a_minor != b_minor {
    return Some(if a_minor < b_minor { -1 } else { 1 })
  }
  if a_patch != b_patch {
    return Some(if a_patch < b_patch { -1 } else { 1 })
  }
  Some(compare_semver_prerelease(a_pre, b_pre))
}

///|
fn extract_semver_core(v : Value) -> (Int, Int, Int, String?)? {
  match v {
    ObjectValue(members) => {
      let major = match find_int_member(members, "major") {
        Some(n) => n
        None => return None
      }
      let minor = match find_int_member(members, "minor") {
        Some(n) => n
        None => return None
      }
      let patch = match find_int_member(members, "patch") {
        Some(n) => n
        None => return None
      }
      let pre = match find_member(members, "preRelease") {
        Some(StringValue(s)) => Some(s)
        Some(NullValue) | None => None
        Some(_) => return None
      }
      Some((major, minor, patch, pre))
    }
    _ => None
  }
}

///|
fn find_member(members : Array[ValueMember], name : String) -> Value? {
  for m in members {
    if m.name == name {
      return Some(m.value)
    }
  }
  None
}

///|
fn find_int_member(members : Array[ValueMember], name : String) -> Int? {
  match find_member(members, name) {
    Some(IntValue(n)) => Some(n)
    _ => None
  }
}

///|
fn eval_pkl_semver_intrinsic(
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
  let name = match callee {
    Identifier(n) => n
    _ => return None
  }
  let arity = match pkl_semver_intrinsic_arity(name) {
    Some(n) => n
    None => return None
  }
  if arguments.length() != arity {
    diagnostics.push(
      diag("\{name} expects \{arity} arguments, got \{arguments.length()}"),
    )
    return None
  }
  let arg_values : Array[Value] = []
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => return None
    }
  }
  match name {
    "_pkl_semver_parse" => {
      let s = match arg_values[0] {
        StringValue(s) => s
        _ => {
          diagnostics.push(diag("semver.parse expects a String argument"))
          return None
        }
      }
      match pkl_semver_decompose(s) {
        Some((major, minor, patch, pre, build)) =>
          Some(semver_value(major, minor, patch, pre, build))
        None => {
          diagnostics.push(
            diag("semver.parse: invalid version string \"\{s}\""),
          )
          None
        }
      }
    }
    "_pkl_semver_parse_or_null" => {
      let s = match arg_values[0] {
        StringValue(s) => s
        _ => {
          diagnostics.push(diag("semver.parseOrNull expects a String argument"))
          return None
        }
      }
      match pkl_semver_decompose(s) {
        Some((major, minor, patch, pre, build)) =>
          Some(semver_value(major, minor, patch, pre, build))
        None => Some(NullValue)
      }
    }
    "_pkl_semver_compare" =>
      match compare_semver_values(arg_values[0], arg_values[1]) {
        Some(n) => Some(IntValue(n))
        None => {
          diagnostics.push(
            diag("semver.compare expects two parsed Version objects"),
          )
          None
        }
      }
    _ => None
  }
}

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
    ObjectLiteral(members) =>
      Some(
        ObjectValue(
          eval_object_members(
            members, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ),
        ),
      )
    TypedObjectLiteral(type_name, members) => {
      let merged = merge_value_members(
        eval_class_default_members(
          type_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ),
        eval_object_members(
          members, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ),
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
            // of silently keeping the integer. Restricted to literal
            // value expressions: free-form expression bodies are
            // still subject to a pre-existing forward-binding leak
            // (locals from other module-level objects can resolve
            // into a sibling body's identifier lookups), and firing
            // the type check on the leaked value would mask the gold
            // output of fixtures the leak does not otherwise break.
            // Fixing the leak itself is tracked separately.
            let value_is_literal = match field.value {
              IntLiteral(_)
              | FloatLiteral(_)
              | StringLiteral(_)
              | BoolLiteral(_)
              | NullLiteral => true
              _ => false
            }
            let type_message = if value_is_literal {
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
        Some(ObjectValue(merged))
      }
    }
    ListingLiteral(elements) => {
      let values : Array[Value] = []
      for element in elements {
        // PKL-136: a `WhenSpread(inner)` element wraps a ConditionalExpr
        // whose branches are ListingLiterals. Evaluate the wrapper and
        // spread the resulting ListingValue's elements into the parent.
        match element {
          WhenSpread(inner) =>
            match
              eval_expr_with_bindings(
                inner, bindings, env, class_env, cache, stack, declarations, diagnostics,
                resolve_import,
              ) {
              Some(ListingValue(inner_elements))
              | Some(ListValue(inner_elements)) =>
                for v in inner_elements {
                  values.push(v)
                }
              Some(_) =>
                diagnostics.push(
                  diag("when block inside Listing must produce a Listing"),
                )
              None => ()
            }
          _ =>
            match
              eval_expr_with_bindings(
                element, bindings, env, class_env, cache, stack, declarations, diagnostics,
                resolve_import,
              ) {
              Some(value) => values.push(value)
              None => ()
            }
        }
      }
      Some(ListingValue(values))
    }
    MappingLiteral(entries) => {
      let values : Array[ValueEntry] = []
      let mut duplicate_emitted = false
      for entry in entries {
        // PKL-136: a synthetic MappingEntry with `key = WhenSpread(inner)`
        // is the Mapping-body when block. Evaluate the wrapper and spread
        // the resulting MappingValue's entries.
        match entry.key {
          WhenSpread(inner) =>
            match
              eval_expr_with_bindings(
                inner, bindings, env, class_env, cache, stack, declarations, diagnostics,
                resolve_import,
              ) {
              Some(MappingValue(inner_entries)) =>
                for e in inner_entries {
                  values.push(e)
                }
              Some(_) =>
                diagnostics.push(
                  diag("when block inside Mapping must produce a Mapping"),
                )
              None => ()
            }
          _ => {
            let key = eval_expr_with_bindings(
              entry.key,
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            let value = eval_expr_with_bindings(
              entry.value,
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            )
            match (key, value) {
              (Some(k), Some(v)) => {
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
                  values.push({ key: k, value: v })
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
        Some(MappingValue(values))
      }
    }
    MemberAccess(target_expr, member_name) =>
      // PKL-139: `module.foo` is Apple Pkl's self-reference to the
      // current module's `foo` binding. Short-circuit the member access
      // to a direct binding lookup so the value is resolved through the
      // module's binding env rather than treating `module` as an
      // ordinary identifier (which would fail with "unbound identifier").
      if target_expr is Identifier("module") {
        resolve_binding_value(
          member_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        )
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
                // PKL-148j: external member access on an ObjectValue
                // hides `local` members from the outside-of-body
                // namespace (`foo.x` where `foo` declares `local x = 2`
                // should not resolve to `2`); switch from the
                // hidden-aware `lookup_member` to `lookup_visible_member`
                // so the local slot is invisible here. Module-level
                // function declarations are also stored under the
                // hidden prefix (to keep them out of rendered output)
                // but stay reachable to importers via `Base.func`, so
                // a FunctionValue match through `lookup_member` is
                // still allowed as a follow-up. The diagnostic matches
                // Apple Pkl's wording (`in object of type \`Dynamic\``);
                // class-tagged objects would carry their host class
                // name instead, but until ObjectValue grows a class
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
          Some(ListingValue(elements)) | Some(ListValue(elements)) =>
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
          Some(MappingValue(entries)) =>
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
              "length" => Some(IntValue(elements.length()))
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
              "length" => Some(IntValue(entries.length()))
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
        Some(ListingValue(elements)) | Some(ListValue(elements)) =>
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
        Some(MappingValue(entries)) =>
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
      let target = eval_expr_with_bindings(
        target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      let key = eval_expr_with_bindings(
        key_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      match (target, key) {
        (Some(ListingValue(elements)), Some(IntValue(index)))
        | (Some(ListValue(elements)), Some(IntValue(index))) =>
          if index >= 0 && index < elements.length() {
            Some(elements[index])
          } else {
            // PKL-148h: match Apple Pkl's wording so `module.catch(...)`
            // strings round-trip against gold. The container tag picks
            // `List(...)` for `ListValue` and falls back to
            // `Listing(...)` for the Listing block form.
            let coll_text = match target {
              Some(v) => render_pcf_value_inline(v)
              None => ""
            }
            let upper = elements.length() - 1
            diagnostics.push(
              diag(
                "Element index `\{index}` is out of range `0`..`\{upper}`. Collection: \{coll_text}",
              ),
            )
            None
          }
        (Some(ListingValue(_)), Some(_)) | (Some(ListValue(_)), Some(_)) => {
          diagnostics.push(diag("listing index expects Int"))
          None
        }
        (Some(MappingValue(entries)), Some(key_value)) =>
          match lookup_entry(entries, key_value) {
            Some(value) => Some(value)
            None => {
              diagnostics.push(diag("unknown mapping key"))
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
          Some(
            ObjectValue(
              merge_value_members(
                base_members,
                eval_object_members(
                  members, bindings, env, class_env, amend_cache, stack, declarations,
                  diagnostics, resolve_import,
                ),
              ),
            ),
          )
        }
        Some(_) => {
          diagnostics.push(diag("object amendment expects Object"))
          None
        }
        None => None
      }
    Identifier(name) =>
      match
        resolve_binding_value(
          name, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) => Some(value)
        None =>
          // PKL-148d: a bare class name (`Person`) used as a value
          // projects to a `pkl:reflect.Class` mirror. This unlocks
          // `Person.foo` / `Person.bar()` failure paths that snippetTest
          // captures via `test.catch(...)`, plus future Class-arg APIs.
          match lookup_class_binding(class_env, name) {
            Some(_) => Some(synth_class_mirror_for_name(name))
            None =>
              // PKL-148e: stdlib type names (`Int` / `Float` / `String`
              // / ...) also project to a Class mirror so equality and
              // comparison fixtures (`Int == Int`, `Int == 3.getClass()`)
              // round-trip without a user class declaration.
              if is_stdlib_class_name(name) {
                Some(synth_class_mirror_for_name(name))
              } else {
                diagnostics.push(diag("Cannot find property `\{name}`."))
                None
              }
          }
      }
    CallExpr(callee, arguments) =>
      if callee is Identifier("Bytes") &&
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
            Some(ListingValue(elements)) | Some(ListValue(elements)) =>
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
          callee is MemberAccess(Identifier("module"), "catch") ||
          callee is MemberAccess(Identifier("test"), "catch")
        ) &&
        !stack_contains_binding(stack, "catch") &&
        find_binding(bindings, "catch") is None &&
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
            Some(StringValue(uri)) => eval_read_uri(uri, diagnostics)
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
                Some(value) => Some(synth_class_mirror_for_value(value))
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
              method_name == "toUnit" ||
              method_name == "toBytes" ||
              method_name == "isSubclassOf" ||
              method_name == "parse" {
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
                  if method_name == "parse" &&
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
                            err => {
                              diagnostics.push(
                                diag("json.Parser.parse: \{err}"),
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
                            err => {
                              diagnostics.push(
                                diag("yaml.Parser.parse: \{err}"),
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
                  } else {
                    eval_callable_call(
                      callee, arguments, bindings, env, class_env, cache, stack,
                      declarations, diagnostics, resolve_import,
                    )
                  }
                Some(ListingValue(elements)) | Some(ListValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    // PKL-148h: List and Listing share the method
                    // surface (`.filter`, `.map`, `.length`, ...). The
                    // dispatcher's element-walking logic is identical;
                    // the receiver type only re-emerges at `.toList()` /
                    // `.toListing()` (each tags its result with the
                    // matching variant).
                    eval_listing_method(
                      elements, method_name, arguments, bindings, env, class_env,
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
              method_name == "toUnit" ||
              method_name == "toBytes" {
              match
                eval_expr_with_bindings(
                  target_expr, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                ) {
                Some(NullValue) => Some(NullValue)
                Some(ListingValue(elements)) | Some(ListValue(elements)) =>
                  if is_listing_method_name(method_name) {
                    // PKL-148h: List and Listing share the method
                    // surface (`.filter`, `.map`, `.length`, ...). The
                    // dispatcher's element-walking logic is identical;
                    // the receiver type only re-emerges at `.toList()` /
                    // `.toListing()` (each tags its result with the
                    // matching variant).
                    eval_listing_method(
                      elements, method_name, arguments, bindings, env, class_env,
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
        (Negate, Some(FloatValue(value))) => Some(FloatValue(0.0 - value))
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
            Some(_) => {
              diagnostics.push(diag("operator && expects Boolean operands"))
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
            Some(_) => {
              diagnostics.push(diag("operator && expects Boolean operands"))
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
            Some(_) => {
              diagnostics.push(diag("operator || expects Boolean operands"))
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
            Some(_) => {
              diagnostics.push(diag("operator || expects Boolean operands"))
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
                Some(value) =>
                  return Some(BoolValue(value_is_type(value, type_name)))
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
              // PKL-150: Apple Pkl's `as` is a shape-preserving cast at
              // the outermost head — `Set(...) as Set<Listing<Int>>`
              // accepts the SetValue without iterating the elements;
              // per-element constraint mismatches surface only when
              // the inner values are actually read. Mirror PKL-148l's
              // generic-head strip so the cast acceptance lines up
              // with that runtime semantics. The diagnostic still
              // quotes the surface name so user-facing messages
              // preserve the full annotation.
              let without_constraint = match
                pkl_constrained_type_base_name(resolved) {
                Some(base) => base
                None => resolved
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
                return Some(value)
              } else {
                diagnostics.push(
                  diag(
                    "Expected value of type `\{type_name}`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
                  ),
                )
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
                  let left_type = eval_value_type_name(left_val)
                  let right_type = eval_value_type_name(right_val)
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
              if b == 0 {
                diagnostics.push(diag("division by zero"))
                None
              } else {
                Some(FloatValue(a.to_double() / b.to_double()))
              }
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
        (Some(a), Some(b)) if op == Equal => Some(BoolValue(a == b))
        (Some(a), Some(b)) if op == NotEqual => Some(BoolValue(a != b))
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
              match eval_read_uri(uri, probe_diagnostics) {
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
          Some(value) => buf.write_string(value_to_string_for_join(value))
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
    Some(ListingValue(elements)) | Some(ListValue(elements)) =>
      for i = 0; i < elements.length(); i = i + 1 {
        let iter_cache = copy_value_bindings(cache)
        match var2 {
          Some(name2) => {
            iter_cache.push({ name: var1, value: IntValue(i) })
            iter_cache.push({ name: name2, value: elements[i] })
          }
          None => iter_cache.push({ name: var1, value: elements[i] })
        }
        let iter_members = eval_object_members(
          body_members, bindings, env, class_env, iter_cache, stack, declarations,
          diagnostics, resolve_import,
        )
        accumulated = merge_value_members(accumulated, iter_members)
      }
    Some(MappingValue(entries)) =>
      for entry in entries {
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
        accumulated = merge_value_members(accumulated, iter_members)
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
  // PKL-148e: pre-register every sibling member as a binding so a
  // forward reference (`x = 1 + y; y = 2`) resolves through the
  // bindings-driven lazy lookup path. Cycle detection still kicks in
  // via the `stack` argument inside `resolve_binding_value`.
  let local_bindings : Array[Binding] = []
  for binding in bindings {
    local_bindings.push(binding)
  }
  for field in members {
    if field.name == "@when" || field.name == "@for" {
      continue
    }
    let bare = strip_member_visibility_prefix(field.name)
    local_bindings.push({
      name: bare,
      type_name: field.type_name,
      value: field.value,
      exported: true,
      abstract_slot: false,
    })
  }
  let values : Array[ValueMember] = []
  for field in members {
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
      if is_invisible_member_name(prior.name) {
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
    match
      eval_expr_with_bindings(
        field.value,
        local_bindings,
        local_env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(raw_value) => {
        let value = coerce_value_to_annotated_type(raw_value, field.type_name)
        if field.name == "@when" || field.name == "@for" {
          match value {
            ObjectValue(branch_members) =>
              for branch_member in branch_members {
                values.push(branch_member)
              }
            _ =>
              diagnostics.push(
                diag("object-body generator must produce an object body"),
              )
          }
        } else if pkl_constrained_type_annotation_value_is_valid(
            field.type_name,
            value,
            diagnostics,
          ) {
          values.push({ name: field.name, value })
        }
      }
      None => ()
    }
  }
  values
}

///|
fn eval_class_default_members(
  type_name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  let defaults : Array[ObjectMember] = []
  let base_values : Array[ValueMember] = []
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent_name) =>
          for
            value_member in eval_class_default_members(
              parent_name, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            ) {
            base_values.push(value_member)
          }
        None => ()
      }
      for property in class_binding.properties {
        match property.value {
          Some(value) =>
            defaults.push({
              name: property.name,
              type_name: property.type_name,
              value,
            })
          None => ()
        }
      }
    }
    None => ()
  }
  merge_value_members(
    base_values,
    eval_object_members(
      defaults, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
    ),
  )
}

///|
fn collect_class_bindings(
  declarations : Array[Declaration],
) -> Array[ClassBinding] {
  let classes : Array[ClassBinding] = []
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        classes.push({
          name: class_decl.name,
          parent_name: class_decl.parent_name,
          properties: class_decl.properties,
          methods: class_decl.methods,
        })
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  classes
}

///|
fn imported_class_parent_name(
  import_name : String,
  parent_name : String,
) -> String {
  if parent_name.find(".") is Some(_) {
    parent_name
  } else {
    "\{import_name}.\{parent_name}"
  }
}

///|
fn add_imported_class_bindings(
  imports : Array[ImportDecl],
  class_env : Array[ClassBinding],
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> Unit {
  for decl in imports {
    match resolve_import_classes(decl.uri) {
      Some(exports) =>
        for class_export in exports {
          let parent_name = match class_export.parent_name {
            Some(parent) =>
              Some(imported_class_parent_name(decl.import_name, parent))
            None => None
          }
          class_env.push({
            name: "\{decl.import_name}.\{class_export.name}",
            parent_name,
            properties: class_export.properties,
            methods: class_export.methods,
          })
        }
      None => ()
    }
  }
}

///|
fn class_exports_from_parse_result(parsed : ParseResult) -> Array[ClassExport] {
  let exports : Array[ClassExport] = []
  for declaration in parsed.program.declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        exports.push({
          name: class_decl.name,
          parent_name: class_decl.parent_name,
          properties: class_decl.properties,
          methods: class_decl.methods,
        })
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  exports
}

///|
fn eval_imports(
  imports : Array[ImportDecl],
  env : Array[ValueBinding],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Unit {
  for decl in imports {
    match resolve_import(decl.uri) {
      Some(EvalOk(value)) => env.push({ name: decl.import_name, value })
      Some(EvalError(errors)) =>
        for error in errors {
          diagnostics.push(error)
        }
      None => diagnostics.push(diag("Cannot find module `\{decl.uri}`."))
    }
  }
}

///|
fn eval_module_relation(
  relation : ModuleRelation,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  match resolve_import(relation.uri) {
    Some(EvalOk(ObjectValue(members))) => members
    Some(EvalOk(_)) => {
      diagnostics.push(
        diag("module \{relation_kind_name(relation.kind)} expects Object"),
      )
      []
    }
    Some(EvalError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      []
    }
    None => {
      diagnostics.push(diag("Cannot find module `\{relation.uri}`."))
      []
    }
  }
}

///|
fn eval_read_uri(uri : String, diagnostics : Array[Diagnostic]) -> Value? {
  // PKL-098 / PKL-106 sandbox policy: `env:` is always on the
  // allow-list; `prop:` is allow-listed when the CLI installed at
  // least one `-p NAME=VALUE` binding. The remaining Apple Pkl
  // schemes (`file:`, `https:`, `package:`) still need explicit
  // policy decisions before they ship; surfacing them as a
  // diagnostic keeps the failure mode honest until those follow-up
  // slices land.
  match uri.find(":") {
    None => {
      diagnostics.push(diag("read: missing URI scheme in \"\{uri}\""))
      None
    }
    Some(idx) => {
      let scheme = String::unsafe_substring(uri, start=0, end=idx)
      let rest = String::unsafe_substring(uri, start=idx + 1, end=uri.length())
      if scheme == "env" {
        match @env.get_env_var(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag("read: env variable \{rest} is not set"))
            None
          }
        }
      } else if scheme == "prop" {
        match sandbox_lookup_prop(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag("read: prop \{rest} is not set"))
            None
          }
        }
      } else {
        diagnostics.push(
          diag("read: scheme \{scheme}: is not allowed by the sandbox policy"),
        )
        None
      }
    }
  }
}

///|
fn pkl_test_catch_lambda_body(expr : Expr) -> Expr? {
  // PKL-147: snippetTest fixtures call `module.catch(() -> ...)` where
  // `catch` is inherited via `extends "pkl:test"`. Recognise both the
  // bare `test.catch(...)` form (binding-time intercept on the top
  // binding) and the `module.catch(...)` form so a fixture that uses
  // the module-self reference still routes through this stub.
  let arguments = match expr {
    CallExpr(MemberAccess(Identifier("test"), "catch"), args) => args
    CallExpr(MemberAccess(Identifier("module"), "catch"), args) => args
    _ => return None
  }
  if arguments.length() != 1 {
    return None
  }
  match arguments[0] {
    LambdaExpr(parameters, body, _) =>
      if parameters.length() == 0 {
        Some(body)
      } else {
        None
      }
    _ => None
  }
}

///|
fn eval_pkl_test_catch_binding_value(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match pkl_test_catch_lambda_body(expr) {
    Some(body) => {
      let caught_diagnostics : Array[Diagnostic] = []
      push_constrained_class_property_expr_diagnostics(
        body, declarations, caught_diagnostics,
      )
      if caught_diagnostics.length() > 0 {
        return Some(StringValue(caught_diagnostics[0].message))
      }
      match
        eval_expr_with_bindings(
          body, bindings, env, class_env, cache, stack, declarations, caught_diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          if caught_diagnostics.length() > 0 {
            Some(StringValue(caught_diagnostics[0].message))
          } else {
            Some(StringValue(render_value(value)))
          }
        None =>
          if caught_diagnostics.length() > 0 {
            Some(StringValue(caught_diagnostics[0].message))
          } else {
            Some(StringValue("caught error"))
          }
      }
    }
    None => None
  }
}

///|
fn eval_program(
  program : Program,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> Value? {
  let env : Array[ValueBinding] = []
  let class_env = collect_class_bindings(program.declarations)
  let type_aliases = eval_type_alias_bindings(program.declarations)
  let cache : Array[ValueBinding] = []
  let members : Array[ValueMember] = []
  let bindings = all_eval_bindings(program)
  eval_imports(program.imports, env, diagnostics, resolve_import)
  add_imported_class_bindings(
    program.imports,
    class_env,
    resolve_import_classes,
  )
  // PKL-140: `extends "parent.pkl"` exposes the parent module's class
  // declarations as bare-name lookups in the child (Apple Pkl treats
  // extends as inheritance, not a namespaced import). Pull the parent
  // ClassExports in directly so an inherited typed slot like
  // `pp1: Person1` can resolve `Person1` against the parent.
  match program.module_relation {
    Some(relation) =>
      match resolve_import_classes(relation.uri) {
        Some(exports) =>
          for class_export in exports {
            class_env.push({
              name: class_export.name,
              parent_name: class_export.parent_name,
              properties: class_export.properties,
              methods: class_export.methods,
            })
          }
        None => ()
      }
    None => ()
  }
  for binding in program.bindings {
    // PKL-140: abstract / external slot bindings (declared without a
    // `=` default) carry no value to render. Apple Pkl synthesises a
    // type-directed default for typed slots — a user class projects
    // to `new T {}` with class defaults applied, nullable types and
    // `Null` project to `null`, a string-literal type projects to the
    // literal itself, and structural collection types fall back to
    // their empty form. Slots that don't fit the synthesiser remain
    // skipped (the typechecker still recorded their type).
    if binding.abstract_slot {
      match
        synthesize_default_for_type(
          binding.type_name,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(value) => members.push({ name: binding.name, value })
        None => ()
      }
      continue
    }
    if binding.exported {
      let resolved_value = match
        eval_pkl_test_catch_binding_value(
          binding.value,
          bindings,
          env,
          class_env,
          cache,
          [],
          program.declarations,
          resolve_import,
        ) {
        Some(value) => {
          cache.push({ name: binding.name, value })
          Some(value)
        }
        None =>
          resolve_binding_value(
            binding.name,
            bindings,
            env,
            class_env,
            cache,
            [],
            program.declarations,
            diagnostics,
            resolve_import,
          )
      }
      match resolved_value {
        Some(raw_value) => {
          let coerced = coerce_value_to_annotated_type(
            raw_value,
            binding.type_name,
          )
          // PKL-148: when a typed binding is filled in with `new {}` (or
          // a sparse amend), expand the class-level defaults so the
          // declared properties materialise in the rendered output.
          // `apply_class_defaults_for_type` is a no-op when the value
          // already carries members, when no type is annotated, or when
          // the type name doesn't resolve to a user-defined class.
          let value = apply_class_defaults_for_type(
            coerced,
            binding.type_name,
            bindings,
            env,
            class_env,
            cache,
            program.declarations,
            diagnostics,
            resolve_import,
          )
          if eval_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              type_aliases,
              diagnostics,
            ) &&
            eval_user_defined_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              program.declarations,
              diagnostics,
            ) &&
            eval_expr_class_property_constraints_are_valid(
              binding.value,
              value,
              program.declarations,
              diagnostics,
            ) &&
            eval_expr_alias_constraints_are_valid(
              binding.value,
              value,
              type_aliases,
              diagnostics,
            ) {
            members.push({ name: binding.name, value })
          }
        }
        None => ()
      }
    }
  }
  // PKL-118: surface module-level `function f(...) = ...` declarations
  // as hidden-prefixed exported members so a cross-module reference
  // (`import "x.pkl" as Base; out = Base.helper(5)`) can resolve them
  // through `lookup_member`. The hidden prefix keeps the function out
  // of the rendered output (`render_value` skips
  // `is_hidden_member_name(field.name)`); internal references inside
  // the declaring module continue to flow through the bare-named entry
  // in `bindings` produced by `all_eval_bindings`.
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
            match
              eval_expr_with_bindings(
                lambda_expr,
                bindings,
                env,
                class_env,
                cache,
                [],
                program.declarations,
                diagnostics,
                resolve_import,
              ) {
              Some(value) =>
                members.push({
                  name: hidden_member_name(function_decl.name),
                  value,
                })
              None => ()
            }
          }
          None => ()
        }
      _ => ()
    }
  }
  let result = match program.body {
    Some(expr) =>
      eval_expr_with_bindings(
        expr,
        bindings,
        env,
        class_env,
        cache,
        [],
        program.declarations,
        diagnostics,
        resolve_import,
      )
    None if program.module_relation is Some(relation) =>
      Some(
        ObjectValue(
          merge_value_members(
            eval_module_relation(relation, diagnostics, resolve_import),
            members,
          ),
        ),
      )
    None if members.length() > 0 => Some(ObjectValue(members))
    // PKL-140: declarations-only modules (stdlib `pkl:math`, `pkl:test`,
    // etc.) have no value bindings to render but still parse cleanly.
    // Apple Pkl treats these as empty modules; the loadable surface is
    // the class / typealias / function declarations alone. Returning
    // an empty ObjectValue keeps the eval pipeline happy.
    None => Some(ObjectValue([]))
  }
  // PKL-105: post-process the result by applying any path-keyed
  // `output.renderer.converters` lambdas. Each converter is a
  // `(value) -> newValue` callback the user attached to a dotted path
  // on the module's `output.value` (or directly on the module body).
  // Class-keyed converters (`["MyClass"] = ...`) are deferred until
  // ObjectValue carries its source class.
  match result {
    Some(value) => {
      let converters = collect_path_converters(value)
      if converters.length() == 0 {
        Some(value)
      } else {
        Some(
          apply_path_converters(
            value,
            converters,
            bindings,
            env,
            class_env,
            cache,
            program.declarations,
            diagnostics,
            resolve_import,
          ),
        )
      }
    }
    None => None
  }
}

///|
/// PKL-105: extract path-keyed converter callbacks from
/// `result.output.renderer.converters`. Returns an `(path, callback)`
/// list; class-keyed entries (those without a `.` and not starting
/// with `[` style) are recognised but skipped — the runtime doesn't
/// carry an object's source class yet.
fn collect_path_converters(value : Value) -> Array[(String, Value)] {
  let converters : Array[(String, Value)] = []
  match value {
    ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  match output_member.value {
                    ObjectValue(renderer_members) =>
                      for renderer_member in renderer_members {
                        if renderer_member.name == "converters" {
                          match renderer_member.value {
                            MappingValue(entries) =>
                              for entry in entries {
                                match entry.key {
                                  StringValue(path) =>
                                    converters.push((path, entry.value))
                                  _ => ()
                                }
                              }
                            _ => ()
                          }
                        }
                      }
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  converters
}

///|
fn apply_path_converters(
  value : Value,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let mut current = value
  for entry in converters {
    let (path, callback) = entry
    current = rewrite_at_path(
      current, path, callback, bindings, env, class_env, cache, declarations, diagnostics,
      resolve_import,
    )
  }
  current
}

///|
/// Walk `value`, find the node at the dotted path, and replace it
/// with `callback(node)`. Paths that don't exist are silently
/// skipped — Apple Pkl matches this lenient behaviour.
fn rewrite_at_path(
  value : Value,
  path : String,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let segments = split_path(path)
  if segments.length() == 0 {
    return value
  }
  rewrite_walk(
    value, segments, 0, callback, bindings, env, class_env, cache, declarations,
    diagnostics, resolve_import,
  )
}

///|
fn rewrite_walk(
  value : Value,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  if idx >= segments.length() {
    match
      apply_function_value(
        "renderer converter",
        callback,
        [value],
        bindings,
        env,
        class_env,
        cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(converted) => converted
      None => value
    }
  } else {
    let segment = segments[idx]
    match value {
      ObjectValue(members) => {
        let next : Array[ValueMember] = []
        for field in members {
          if field.name == segment {
            next.push({
              name: field.name,
              value: rewrite_walk(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else {
            next.push(field)
          }
        }
        ObjectValue(next)
      }
      MappingValue(entries) => {
        let next : Array[ValueEntry] = []
        for entry in entries {
          let key_matches = match entry.key {
            StringValue(k) => k == segment
            _ => false
          }
          if key_matches {
            next.push({
              key: entry.key,
              value: rewrite_walk(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else {
            next.push(entry)
          }
        }
        MappingValue(next)
      }
      _ => value
    }
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i].to_int().unsafe_to_char()
    if c == '.' {
      segments.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let last = buf.to_string()
  if last != "" || segments.length() > 0 {
    segments.push(last)
  }
  segments
}

///|
fn operator_name(op : BinaryOp) -> String {
  match op {
    Add => "+"
    Subtract => "-"
    Multiply => "*"
    Divide => "/"
    IntDivide => "~/"
    Modulo => "%"
    Power => "**"
    Equal => "=="
    NotEqual => "!="
    LessThan => "<"
    LessOrEqual => "<="
    GreaterThan => ">"
    GreaterOrEqual => ">="
    And => "&&"
    Or => "||"
    NullCoalesce => "??"
    Is => "is"
    As => "as"
    Pipe => "|>"
  }
}

///|
fn relation_kind_name(kind : ModuleRelationKind) -> String {
  match kind {
    ModuleAmends => "amends"
    ModuleExtends => "extends"
  }
}

///|
pub fn eval_source(source : String) -> EvalResult {
  // PKL-118: strip the hidden-prefixed function members the evaluator
  // adds for cross-module dispatch. `eval_source` is the test-facing
  // entry point and the existing tests assert on visible-binding
  // equality (`ValueMember::{ name: "result", value: IntValue(3) }`);
  // surfacing the synthetic function entries here would force every
  // test that declares a `function` to expand its expected ObjectValue
  // even though the user-visible render still hides them. The CLI's
  // `render_value` already skips hidden members, so this filter is the
  // only place the symmetry needs to be re-stated.
  match eval_source_with_imports(source, fn(_) { None }) {
    EvalOk(ObjectValue(members)) => {
      let visible : Array[ValueMember] = []
      for field in members {
        if !is_invisible_member_name(field.name) {
          visible.push(field)
        }
      }
      EvalOk(ObjectValue(visible))
    }
    other => other
  }
}

///| Render a runtime value in the canonical Pkl Configuration Format

///| (PCF). Primitives use the same lexical form as Apple Pkl's

///| `pkl eval` default output, so the result can be reparsed by this

///| evaluator and by upstream Pkl. The JSON / YAML / Properties

///| renderers (PKL-072..074) will live alongside this as separate

///|
/// entry points.
pub fn render_value(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_pcf_module(members, buf)
    _ => render_pcf_inline(value, 0, buf)
  }
  buf.to_string()
}

///|
fn escape_string(value : String) -> String {
  let buf = StringBuilder::new()
  for c in value {
    match c {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn pcf_is_block_value(value : Value) -> Bool {
  match value {
    ObjectValue(_) | ListingValue(_) | MappingValue(_) => true
    // PKL-148h: `ListValue` renders through the `List(...)` constructor
    // form (handled in `render_pcf_scalar`), not as a `new { ... }`
    // block — so callers must NOT prefix it with `new`.
    _ => false
  }
}

///|
fn write_pcf_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn eval_float_binary(
  op : BinaryOp,
  a : Double,
  b : Double,
  diagnostics : Array[Diagnostic],
) -> Value? {
  // PKL-092: Float-side arithmetic and comparison. Division-by-zero
  // surfaces a diagnostic to match the Int-side path; Apple Pkl returns
  // `Infinity` / `NaN` for floating point zero division, which is
  // implementable later but a separate slice — staying strict here keeps
  // the failure mode consistent across numeric types until then.
  match op {
    Add => Some(FloatValue(a + b))
    Subtract => Some(FloatValue(a - b))
    Multiply => Some(FloatValue(a * b))
    Divide =>
      if b == 0.0 {
        diagnostics.push(diag("division by zero"))
        None
      } else {
        Some(FloatValue(a / b))
      }
    LessThan => Some(BoolValue(a < b))
    LessOrEqual => Some(BoolValue(a <= b))
    GreaterThan => Some(BoolValue(a > b))
    GreaterOrEqual => Some(BoolValue(a >= b))
    Equal => Some(BoolValue(a == b))
    NotEqual => Some(BoolValue(a != b))
    // PKL-111: Apple Pkl widens these Int-domain operators to Float
    // operands. `**` (Power) returns a Float exponent; `~/` (IntDivide)
    // truncates toward zero and returns an Int even on Float operands
    // (matching Apple's `5.1 ~/ 3.1 == 1`); `%` (Modulo) returns the
    // truncated remainder as a Float so it composes with Float division.
    Power => Some(FloatValue(@math.pow(a, b)))
    IntDivide =>
      if b == 0.0 {
        diagnostics.push(diag("division by zero"))
        None
      } else {
        Some(IntValue(double_trunc(a / b).to_int()))
      }
    Modulo =>
      if b == 0.0 {
        diagnostics.push(diag("division by zero"))
        None
      } else {
        Some(FloatValue(a - b * double_trunc(a / b)))
      }
    And | Or | NullCoalesce | Is | As | Pipe => panic()
  }
}

///|
fn double_trunc(x : Double) -> Double {
  // PKL-111: truncation toward zero. MoonBit's core does not expose
  // `Double::trunc` directly across both JS and native targets, so do it
  // by converting through Int round-trip on finite values; Infinity / NaN
  // pass through (used only for divisions where `b == 0` short-circuits
  // before reaching here).
  if x >= 0.0 {
    x.to_int64().to_double()
  } else {
    -(-x).to_int64().to_double()
  }
}

///|
// PKL-114: classify a Value against a type annotation text. Used by
// the `is` operator at runtime. Supports the same surface the
// typechecker's `type_from_annotation` accepts: union (`String | Int`),
// nullable (`Float?`), constrained (`Int(isPositive)`), and generic
// (`Listing<Int>` / `Mapping<String, Int>`). User-defined class names
// fall through to `false` for now — that gap matches PKL-114's
// "extension" scope and leaves class-instance dispatch for a later
// slice once the evaluator carries class tags on ObjectValue.
fn value_is_type(value : Value, type_name : String) -> Bool {
  let trimmed = pkl_constraint_trim(type_name)
  if trimmed == "" {
    return false
  }
  let union_choices = split_top_level_union_choices(trimmed)
  if union_choices.length() > 1 {
    for choice in union_choices {
      if value_is_type(value, choice) {
        return true
      }
    }
    return false
  }
  if trimmed.has_suffix("?") {
    if value is NullValue {
      return true
    }
    let inner = String::unsafe_substring(
      trimmed,
      start=0,
      end=trimmed.length() - 1,
    )
    return value_is_type(value, inner)
  }
  match pkl_constrained_type_base_name(trimmed) {
    Some(base) => return value_is_type(value, base)
    None => ()
  }
  match generic_argument_text(trimmed, "Listing") {
    Some(_) =>
      return match value {
        ListingValue(_) => true
        _ => false
      }
    None => ()
  }
  match generic_argument_text(trimmed, "Mapping") {
    Some(_) =>
      return match value {
        MappingValue(_) => true
        _ => false
      }
    None => ()
  }
  match trimmed {
    "Int" =>
      match value {
        IntValue(_) => true
        _ => false
      }
    "Float" =>
      match value {
        FloatValue(_) => true
        _ => false
      }
    "Number" =>
      match value {
        IntValue(_) | FloatValue(_) => true
        _ => false
      }
    "String" =>
      match value {
        StringValue(_) => true
        _ => false
      }
    "Boolean" | "Bool" =>
      match value {
        BoolValue(_) => true
        _ => false
      }
    "Null" =>
      match value {
        NullValue => true
        _ => false
      }
    "Listing" =>
      match value {
        ListingValue(_) => true
        _ => false
      }
    "Mapping" =>
      match value {
        MappingValue(_) => true
        _ => false
      }
    "Object" =>
      match value {
        ObjectValue(_) => true
        _ => false
      }
    "Any" => true
    _ => false
  }
}

///|
fn render_float_text(d : Double) -> String {
  // PKL-092: render a Float deterministically. Apple Pkl emits Doubles in
  // the shortest round-trip form (`1.5`, `12.3`, `1.0` — never `1`), so
  // we anchor on `Double::to_string()` and append `.0` when the result
  // has no fractional or exponent component (otherwise `42.0` would
  // round-trip as `42` and pun as an Int).
  let s = d.to_string()
  if s.find(".") is None &&
    s.find("e") is None &&
    s.find("E") is None &&
    s != "Infinity" &&
    s != "-Infinity" &&
    s != "NaN" {
    s + ".0"
  } else {
    s
  }
}

///|
fn render_pcf_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) => {
      buf.write_char('"')
      buf.write_string(escape_string(s))
      buf.write_char('"')
    }
    NullValue => buf.write_string("null")
    FunctionValue(_, _, _, _, _) => buf.write_string("<function>")
    DurationValue(n, unit) => buf.write_string("\{n}.\{unit}")
    DataSizeValue(n, unit) => buf.write_string("\{n}.\{unit}")
    RegexValue(pattern) => {
      buf.write_string("Regex(\"")
      buf.write_string(escape_string(pattern))
      buf.write_string("\")")
    }
    BytesValue(bytes) => {
      // PKL-083: PCF round-trips Bytes through the Listing constructor
      // so the parser can re-evaluate the literal verbatim. Each byte
      // is emitted as its 0..=255 decimal int.
      buf.write_string("Bytes(new Listing { ")
      for i = 0; i < bytes.length(); i = i + 1 {
        if i > 0 {
          buf.write_string("; ")
        }
        let n = bytes[i].to_int()
        buf.write_string("\{n}")
      }
      buf.write_string(" })")
    }
    // PKL-119a: PCF round-trips `Pair(a, b)` through Apple Pkl's
    // constructor form. Element values flow through `render_pcf_inline`
    // so nested composites stay valid PCF (`Pair(new { x = 1 }, 2)`).
    PairValue(first, second) => {
      buf.write_string("Pair(")
      render_pcf_inline(first, 0, buf)
      buf.write_string(", ")
      render_pcf_inline(second, 0, buf)
      buf.write_char(')')
    }
    // PKL-119b: PCF round-trips IntSeq through Apple Pkl's constructor
    // form. Default `step = 1` stays implicit; any other step renders
    // as a chained `.step(n)` call so re-parsing the output yields the
    // same IntSeq.
    IntSeqValue(start, end_v, step) => {
      buf.write_string("IntSeq(\{start}, \{end_v})")
      if step != 1 {
        buf.write_string(".step(\{step})")
      }
    }
    // PKL-119c: PCF round-trips through Apple Pkl's `Set(...)`
    // constructor form. Element values flow through
    // `render_pcf_inline` so nested composites stay valid PCF.
    SetValue(elements) => {
      buf.write_string("Set(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(elements[i], 0, buf)
      }
      buf.write_char(')')
    }
    // PKL-148h: `ListValue` round-trips through `List(...)` to match
    // upstream PCF (`new { 1; 2 }` would parse back as a Listing, not a
    // List). Element values flow through `render_pcf_inline` so nested
    // composites — including `new Listing { ... }` blocks inside a
    // `List(...)` — stay valid PCF.
    ListValue(elements) => {
      buf.write_string("List(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(elements[i], 0, buf)
      }
      buf.write_char(')')
    }
    // PKL-119d: PCF round-trips through Apple Pkl's `Map(...)`
    // constructor form (alternating key, value, key, value, ...).
    // Reparsing the output yields the same MapValue.
    MapValue(entries) => {
      buf.write_string("Map(")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(entries[i].key, 0, buf)
        buf.write_string(", ")
        render_pcf_inline(entries[i].value, 0, buf)
      }
      buf.write_char(')')
    }
    ObjectValue(_) | ListingValue(_) | MappingValue(_) =>
      // Defensive: callers should route block values through
      // render_pcf_inline / render_pcf_block_body. Falling back keeps
      // diagnostics non-empty if we ever miss a case.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_pcf_inline(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  if pcf_is_block_value(value) {
    buf.write_string("new ")
    render_pcf_block_body(value, indent, buf)
  } else {
    render_pcf_scalar(value, buf)
  }
}

///|
fn render_pcf_block_body(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue([]) | ListingValue([]) | MappingValue([]) =>
      buf.write_string("{}")
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string("{}")
        return
      }
      buf.write_string("{\n")
      for i = 0; i < visible.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_object_member(visible[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    ListingValue(elements) => {
      buf.write_string("{\n")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_inline(elements[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    MappingValue(entries) => {
      buf.write_string("{\n")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_mapping_entry(entries[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    _ => render_pcf_scalar(value, buf)
  }
}

///|
fn render_pcf_object_member(
  field : ValueMember,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_string(field.name)
  if pcf_is_block_value(field.value) {
    buf.write_char(' ')
    render_pcf_block_body(field.value, indent, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(field.value, buf)
  }
}

///|
fn render_pcf_mapping_entry(
  entry : ValueEntry,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_char('[')
  render_pcf_inline(entry.key, indent, buf)
  buf.write_char(']')
  if pcf_is_block_value(entry.value) {
    buf.write_char(' ')
    render_pcf_block_body(entry.value, indent, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(entry.value, buf)
  }
}

///|
fn visible_members(members : Array[ValueMember]) -> Array[ValueMember] {
  // Hidden / local members carry the `hidden_member_prefix` marker; every
  // renderer projects through this filter so the prefix never reaches the
  // output. `lookup_member` still resolves bare-name reads against the
  // prefixed entry, so omitting members here doesn't break runtime access.
  let result : Array[ValueMember] = []
  for field in members {
    if !is_invisible_member_name(field.name) {
      result.push(field)
    }
  }
  result
}

///|
/// PKL-147: when the module declares
/// `output { renderer = new PcfRenderer { omitNullProperties = true } }`,
/// the PCF render drops every module-level property whose value is `null`.
/// snippetTest fixtures rely on this so the inherited stub `catch = null`
/// doesn't leak into the rendered output; without the omit pass each
/// snippetTest fixture's output would begin with `catch = null` and never
/// match upstream byte-for-byte.
fn pcf_omit_null_properties(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "output") {
    Some(ObjectValue(output_members)) =>
      match lookup_member(output_members, "renderer") {
        Some(ObjectValue(renderer_members)) =>
          match lookup_member(renderer_members, "omitNullProperties") {
            Some(BoolValue(value)) => value
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn render_pcf_module(members : Array[ValueMember], buf : StringBuilder) -> Unit {
  let omit_null = pcf_omit_null_properties(members)
  let visible = visible_members(members)
  let mut emitted = 0
  for i = 0; i < visible.length(); i = i + 1 {
    if omit_null && visible[i].value is NullValue {
      continue
    }
    // The `output` member is the renderer/value configuration block,
    // not data — Apple Pkl's PCF render strips it from the top-level
    // output. Without this filter `pkl eval` on a snippetTest fixture
    // would include the inherited `output { renderer = ... }` block.
    if visible[i].name == "output" {
      continue
    }
    if emitted > 0 {
      buf.write_char('\n')
    }
    render_pcf_object_member(visible[i], 0, buf)
    emitted = emitted + 1
  }
}

///|
/// Render a Pkl value as JSON matching `pkl eval -f json`.
///
/// - ObjectValue / MappingValue → JSON object (Mapping keys are coerced to strings).
/// - ListingValue → JSON array.
/// - IntValue / BoolValue / NullValue → JSON scalar.
/// - StringValue → JSON string with the standard `"`, `\\`, control-character
///   escapes.
/// - FunctionValue does not have a JSON projection and renders as `null` so
///   diagnostics still produce a parseable document; the typechecker rejects
///   functions earlier on the rendering path.
///
/// Indentation is fixed at two spaces, matching the upstream default for
/// `pkl eval -f json`.
pub fn render_value_as_json(value : Value) -> String {
  let buf = StringBuilder::new()
  render_json_value(value, 0, buf)
  buf.to_string()
}

///|
fn render_json_value(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) =>
      render_json_object_from_members(members, indent, buf)
    MappingValue(entries) =>
      render_json_object_from_entries(entries, indent, buf)
    ListingValue(elements) | ListValue(elements) =>
      render_json_array(elements, indent, buf)
    FunctionValue(_, _, _, _, _) => buf.write_string("null")
    // Upstream Pkl projects Duration / DataSize to a literal-style string
    // (e.g. `"5.min"`) in JSON / YAML / Properties. Match that shape until
    // the dedicated projection table from `pkl:base` lands.
    DurationValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    // PKL-081: Regex projects as the pattern string in JSON / YAML /
    // Properties, mirroring upstream Apple Pkl behavior for opaque
    // stdlib values.
    RegexValue(pattern) => render_json_string(pattern, buf)
    // PKL-083: Bytes projects as its base64 encoding in non-PCF
    // formats, since none of these formats have a native bytes type
    // and base64 is the upstream-compatible representation.
    BytesValue(bytes) => render_json_string(@base64.encode(bytes[:]), buf)
    // PKL-119a: Pair renders as a 2-element JSON array. Matches
    // Apple Pkl's `Pair`-to-JSON projection.
    PairValue(first, second) => render_json_array([first, second], indent, buf)
    // PKL-119b: IntSeq materializes to an Int array first, then flows
    // through the standard JSON array projection.
    IntSeqValue(start, end_v, step) =>
      render_json_array(intseq_materialize(start, end_v, step), indent, buf)
    // PKL-119c: Set renders as a JSON array. Uniqueness is already
    // enforced at construction, so the array element order matches
    // the upstream insertion-order semantics.
    SetValue(elements) => render_json_array(elements, indent, buf)
    // PKL-119d: Map projects as a JSON object, matching the
    // existing MappingValue projection. The entry-walker coerces
    // non-string keys the same way `json_coerce_key` already does.
    MapValue(entries) => render_json_object_from_entries(entries, indent, buf)
  }
}

///|
fn render_json_string(value : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in value {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' {
          let code = c.to_int()
          let hex = json_hex4(code)
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn json_hex4(code : Int) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  let mut i = 12
  while i >= 0 {
    let nibble = (code >> i) & 0xF
    buf.write_char(digits.unsafe_get(nibble).to_int().unsafe_to_char())
    i = i - 4
  }
  buf.to_string()
}

///|
fn json_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn write_json_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn render_json_object_from_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  if visible.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < visible.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(visible[i].name, buf)
    buf.write_string(": ")
    render_json_value(visible[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_object_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if entries.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(json_coerce_key(entries[i].key), buf)
    buf.write_string(": ")
    render_json_value(entries[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_array(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if elements.length() == 0 {
    buf.write_string("[]")
    return
  }
  buf.write_string("[\n")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_value(elements[i], indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char(']')
}

///|
/// Render a Value as YAML, mirroring the basic shape of `pkl eval -f yaml`.
///
/// Block style is used throughout: mappings emit `key: value` per line,
/// listings emit `- value` per line at the same column as the parent key, and
/// empty composites use flow form (`[]` / `{}`). String scalars are bare when
/// they parse as plain YAML, single-quoted when they collide with reserved
/// shapes (numeric / keyword / leading indicator / inline `: ` / ` #`), and
/// double-quoted with `\`-escapes when they contain control characters or a
/// backslash. Block scalars (`|`, `|-`, `|+`) for multiline strings remain
/// follow-up work.
///
/// Indentation is fixed at two spaces; Apple Pkl's `indentWidth` knob lives
/// inside the `YamlRenderer` stdlib class (PKL-079 expansion), which our
/// pipeline does not consume yet.
pub fn render_value_as_yaml(value : Value) -> String {
  let buf = StringBuilder::new()
  render_yaml_root(value, buf)
  buf.to_string()
}

///|
fn render_yaml_root(value : Value, buf : StringBuilder) -> Unit {
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_members(visible, 0, buf)
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_entries(entries, 0, buf)
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string("[]\n")
      } else {
        render_yaml_sequence(elements, 0, buf)
      }
    _ => {
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_mapping_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  for i = 0; i < visible.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(visible[i].name, buf)
    buf.write_char(':')
    render_yaml_block_value(visible[i].value, indent, buf)
  }
}

///|
fn render_yaml_mapping_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < entries.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(yaml_coerce_key(entries[i].key), buf)
    buf.write_char(':')
    render_yaml_block_value(entries[i].value, indent, buf)
  }
}

///|
fn render_yaml_block_value(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_members(visible, indent + 2, buf)
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(entries, indent + 2, buf)
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    // PKL-119a: Pair flows through the same block-sequence path as
    // a 2-element Listing so YAML emits it as the canonical
    // `- first\n- second` form rather than the PCF inline fallback.
    PairValue(first, second) => {
      buf.write_char('\n')
      render_yaml_sequence([first, second], indent, buf)
    }
    // PKL-119b: IntSeq materializes and reuses the sequence path so
    // the YAML output matches what a hand-written `new Listing { ... }`
    // of the same elements would render to.
    IntSeqValue(start, end_v, step) => {
      let elements = intseq_materialize(start, end_v, step)
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    }
    // PKL-119c: Set reuses the sequence path; uniqueness is upstream
    // semantics, not a YAML output concern.
    SetValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    // PKL-119d: Map reuses the mapping-entries path so the YAML
    // output shape matches a hand-written `new Mapping { ... }` of
    // the same entries.
    MapValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(entries, indent + 2, buf)
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(indicator, lines, trailing, indent + 2, buf)
        None => {
          buf.write_char(' ')
          render_yaml_scalar(value, buf)
          buf.write_char('\n')
        }
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_sequence(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < elements.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    buf.write_char('-')
    render_yaml_seq_item(elements[i], indent + 2, buf)
  }
}

///|
fn render_yaml_seq_item(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  // The first sub-member or sub-element shares the `- ` line; the rest are
  // continued at `indent` (two spaces past the `- `).
  match value {
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(visible[0].name, buf)
        buf.write_char(':')
        render_yaml_block_value(visible[0].value, indent, buf)
        for i = 1; i < visible.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(visible[i].name, buf)
          buf.write_char(':')
          render_yaml_block_value(visible[i].value, indent, buf)
        }
      }
    }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(yaml_coerce_key(entries[0].key), buf)
        buf.write_char(':')
        render_yaml_block_value(entries[0].value, indent, buf)
        for i = 1; i < entries.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(yaml_coerce_key(entries[i].key), buf)
          buf.write_char(':')
          render_yaml_block_value(entries[i].value, indent, buf)
        }
      }
    ListingValue(elements) | ListValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char(' ')
        buf.write_char('-')
        render_yaml_seq_item(elements[0], indent + 2, buf)
        for i = 1; i < elements.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          buf.write_char('-')
          render_yaml_seq_item(elements[i], indent + 2, buf)
        }
      }
    StringValue(s) =>
      match yaml_string_block_scalar_info(s) {
        Some((indicator, lines, trailing)) =>
          render_yaml_block_scalar(indicator, lines, trailing, indent, buf)
        None => {
          buf.write_char(' ')
          render_yaml_scalar(value, buf)
          buf.write_char('\n')
        }
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
/// PKL-125: decide whether `s` qualifies for a YAML literal block
/// scalar (`|`, `|-`, `|+`). A string is eligible when:
///   - it has at least one internal newline (`\n` somewhere before
///     the trailing-newline run), so the block form actually
///     improves readability over a double-quoted single-line escape;
///   - it carries no control characters other than `\n` and `\t`,
///     which would otherwise need `\uXXXX` escapes that the block
///     form cannot express;
///   - no content line starts with whitespace, which would otherwise
///     require an explicit indentation indicator like `|2`.
///
/// The chomping indicator follows the trailing-newline count:
///   - exactly 1 trailing `\n`  → `|`  (clip — single final newline)
///   - 0 trailing `\n`          → `|-` (strip — no final newline)
///   - 2+ trailing `\n`         → `|+` (keep — preserve all)
///
/// Returns `Some((indicator, content_lines, trailing))` on
/// eligibility, where `content_lines` are the lines stripped of
/// every trailing newline and `trailing` is the original trailing
/// newline count (the `|+` path needs it to emit the extra blank
/// lines that preserve the run).
fn yaml_string_block_scalar_info(s : String) -> (String, Array[String], Int)? {
  if s.length() == 0 {
    return None
  }
  // Count trailing `\n` characters.
  let mut trailing = 0
  while trailing < s.length() && s[s.length() - 1 - trailing].to_int() == 0x0A {
    trailing = trailing + 1
  }
  let core_len = s.length() - trailing
  let core = String::unsafe_substring(s, start=0, end=core_len)
  // Need at least one internal newline to beat the inline double-quote form.
  let mut has_internal_newline = false
  for c in core {
    if c == '\n' {
      has_internal_newline = true
      break
    }
  }
  if !has_internal_newline {
    return None
  }
  // Reject anything with control chars other than `\n` / `\t`.
  for c in core {
    if c < ' ' && c != '\n' && c != '\t' {
      return None
    }
    if c == '\u{7F}' {
      return None
    }
  }
  // Split into lines and reject any line whose first char is whitespace.
  let lines : Array[String] = []
  for piece in core.split("\n") {
    lines.push(piece.to_owned())
  }
  for line in lines {
    if line.length() == 0 {
      continue
    }
    let first = line[0].to_int().unsafe_to_char()
    if first == ' ' || first == '\t' {
      return None
    }
  }
  let indicator = if trailing == 1 {
    "|"
  } else if trailing == 0 {
    "|-"
  } else {
    "|+"
  }
  Some((indicator, lines, trailing))
}

///|
/// PKL-125: emit a literal block scalar. The leading space and
/// indicator share the same line as the preceding `key:` / `-`;
/// each content line follows at `content_indent` spaces. Blank
/// content lines emit as a bare `\n` (YAML literal block scalars
/// allow empty lines to be undented). For the keep chomping (`|+`)
/// the source had ≥2 trailing newlines; the natural line break
/// after the last content line covers one of them, so `(trailing -
/// 1)` extra bare newlines preserve the rest.
fn render_yaml_block_scalar(
  indicator : String,
  lines : Array[String],
  trailing : Int,
  content_indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_char(' ')
  buf.write_string(indicator)
  buf.write_char('\n')
  for line in lines {
    if line.length() == 0 {
      buf.write_char('\n')
    } else {
      write_yaml_indent(buf, content_indent)
      buf.write_string(line)
      buf.write_char('\n')
    }
  }
  if indicator == "|+" {
    let mut extras = trailing - 1
    while extras > 0 {
      buf.write_char('\n')
      extras = extras - 1
    }
  }
}

///|
fn render_yaml_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_yaml_string(s, buf)
    DurationValue(n, unit) => render_yaml_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_yaml_string("\{n}.\{unit}", buf)
    RegexValue(pattern) => render_yaml_string(pattern, buf)
    BytesValue(bytes) => render_yaml_string(@base64.encode(bytes[:]), buf)
    _ =>
      // Composite values reach this path only via the same renderer fallback
      // that PCF / JSON use, so produce a deterministic flow form rather than
      // panic. Anything richer is handled by the block-mode entry points.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_yaml_key(name : String, buf : StringBuilder) -> Unit {
  // Keys reuse the scalar-string quoting policy.
  render_yaml_string(name, buf)
}

///|
fn render_yaml_string(s : String, buf : StringBuilder) -> Unit {
  if s == "" {
    buf.write_string("''")
    return
  }
  if yaml_string_needs_double_quote(s) {
    render_yaml_double_quoted(s, buf)
    return
  }
  if yaml_string_needs_single_quote(s) {
    render_yaml_single_quoted(s, buf)
    return
  }
  buf.write_string(s)
}

///|
fn yaml_string_needs_double_quote(s : String) -> Bool {
  for c in s {
    if c < ' ' || c == '\u{7F}' || c == '\\' {
      return true
    }
  }
  false
}

///|
fn yaml_string_needs_single_quote(s : String) -> Bool {
  // Reserved YAML 1.1 plain-scalar keywords.
  if yaml_is_reserved_keyword(s) {
    return true
  }
  if yaml_looks_like_number(s) {
    return true
  }
  let mut first : Char = ' '
  let mut has_char = false
  for c in s {
    first = c
    has_char = true
    break
  }
  if !has_char {
    return false
  }
  if first == ' ' || first == '\t' {
    return true
  }
  // Leading indicator characters that would otherwise alter parsing.
  match first {
    '-'
    | '?'
    | ':'
    | ','
    | '['
    | ']'
    | '{'
    | '}'
    | '#'
    | '&'
    | '*'
    | '!'
    | '|'
    | '>'
    | '\''
    | '"'
    | '%'
    | '@'
    | '`' => return true
    _ => ()
  }
  // Trailing whitespace.
  let mut last : Char = first
  for c in s {
    last = c
  }
  if last == ' ' || last == '\t' {
    return true
  }
  // Embedded `: ` or ` #` flips a plain scalar into something the YAML parser
  // would re-interpret, so reach for single quotes.
  if yaml_contains_pair(s, ':', ' ') || yaml_contains_pair(s, ' ', '#') {
    return true
  }
  false
}

///|
fn yaml_is_reserved_keyword(s : String) -> Bool {
  match s {
    "true"
    | "True"
    | "TRUE"
    | "false"
    | "False"
    | "FALSE"
    | "null"
    | "Null"
    | "NULL"
    | "~"
    | "yes"
    | "Yes"
    | "YES"
    | "no"
    | "No"
    | "NO"
    | "on"
    | "On"
    | "ON"
    | "off"
    | "Off"
    | "OFF" => true
    _ => false
  }
}

///|
fn yaml_looks_like_number(s : String) -> Bool {
  // Recognize the common `[+-]?digits(.digits)?(e[+-]?digits)?` shape that
  // YAML would otherwise parse as a number.
  let mut idx = 0
  let mut saw_digit = false
  let mut saw_dot = false
  let mut saw_exp = false
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return false
  }
  if chars[idx] == '+' || chars[idx] == '-' {
    idx = idx + 1
  }
  while idx < chars.length() {
    let c = chars[idx]
    if c >= '0' && c <= '9' {
      saw_digit = true
      idx = idx + 1
    } else if c == '.' && !saw_dot && !saw_exp {
      saw_dot = true
      idx = idx + 1
    } else if (c == 'e' || c == 'E') && !saw_exp && saw_digit {
      saw_exp = true
      idx = idx + 1
      if idx < chars.length() && (chars[idx] == '+' || chars[idx] == '-') {
        idx = idx + 1
      }
    } else {
      return false
    }
  }
  saw_digit
}

///|
fn yaml_contains_pair(s : String, a : Char, b : Char) -> Bool {
  let mut prev : Char = '\u{0}'
  let mut have_prev = false
  for c in s {
    if have_prev && prev == a && c == b {
      return true
    }
    prev = c
    have_prev = true
  }
  false
}

///|
fn render_yaml_single_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('\'')
  for c in s {
    if c == '\'' {
      buf.write_string("''")
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char('\'')
}

///|
fn render_yaml_double_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' || c == '\u{7F}' {
          let code = c.to_int()
          let hex = json_hex4(code)
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn yaml_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn write_yaml_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
/// PKL-126a: Render a Value as an Apple plist XML document, matching
/// the upstream `PListRenderer` output. The output starts with the
/// XML 1.0 prolog and the Apple PLIST 1.0 DOCTYPE, then wraps the
/// rendered value in a `<plist version="1.0">` element.
///
/// Value mapping:
///   - Int    → `<integer>N</integer>`
///   - Float  → `<real>D</real>`
///   - Bool   → `<true/>` / `<false/>`
///   - String → `<string>...</string>` (XML-escaped)
///   - Null   → skipped inside `<dict>` (Apple `omitNullProperties`
///              behaviour); inside `<array>` it would error upstream,
///              but PKL-126a's slice elides it silently — the
///              error-on-null-in-array surface lands with PKL-127 so
///              the diagnostic flows through the same converter path
///              as the rest of the renderer-side errors.
///   - Object / Mapping → `<dict>` with `<key>` + value pairs.
///   - Listing → `<array>` of values.
///   - Duration / DataSize → `<string>N unit</string>` (space-separated
///              numeric + unit, matching Apple PListRenderer rather
///              than the `.` form JSON / YAML use for these values).
///   - Regex  → `<string>pattern</string>`.
///   - Bytes  → `<string>base64</string>`.
///
/// Indentation defaults to two spaces; the eventual converter-aware
/// path (PKL-127) will honor the `indent` property when it threads
/// renderer config through to this entry point.
pub fn render_value_as_plist(value : Value) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  buf.write_string(
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n",
  )
  buf.write_string("<plist version=\"1.0\">\n")
  render_plist_value(value, 0, buf)
  buf.write_char('\n')
  buf.write_string("</plist>\n")
  buf.to_string()
}

///|
fn render_plist_value(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => {
      write_plist_indent(buf, indent)
      buf.write_string("<integer>\{n}</integer>")
    }
    FloatValue(d) => {
      write_plist_indent(buf, indent)
      buf.write_string("<real>\{render_float_text(d)}</real>")
    }
    BoolValue(true) => {
      write_plist_indent(buf, indent)
      buf.write_string("<true/>")
    }
    BoolValue(false) => {
      write_plist_indent(buf, indent)
      buf.write_string("<false/>")
    }
    NullValue => {
      // Top-level Null lands here too — emit an empty `<string/>`
      // shape so the output stays valid plist XML. Object / array
      // contexts intercept Null earlier and elide / error per the
      // upstream rule.
      write_plist_indent(buf, indent)
      buf.write_string("<string></string>")
    }
    StringValue(s) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>")
      write_plist_escaped(s, buf)
      buf.write_string("</string>")
    }
    ObjectValue(members) => render_plist_dict_from_members(members, indent, buf)
    MappingValue(entries) =>
      render_plist_dict_from_entries(entries, indent, buf)
    ListingValue(elements) | ListValue(elements) =>
      render_plist_array(elements, indent, buf)
    FunctionValue(_, _, _, _, _) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string></string>")
    }
    DurationValue(n, unit) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{n} \{unit}</string>")
    }
    DataSizeValue(n, unit) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{n} \{unit}</string>")
    }
    RegexValue(pattern) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>")
      write_plist_escaped(pattern, buf)
      buf.write_string("</string>")
    }
    BytesValue(bytes) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{@base64.encode(bytes[:])}</string>")
    }
    // PKL-119a: Pair renders as a 2-element `<array>`; reuse the
    // listing path so element indent / null handling stay consistent
    // with sibling collections.
    PairValue(first, second) => render_plist_array([first, second], indent, buf)
    // PKL-119b: IntSeq materializes and reuses the plist `<array>`
    // path so the rendered shape matches a hand-written Listing of
    // the same elements.
    IntSeqValue(start, end_v, step) =>
      render_plist_array(intseq_materialize(start, end_v, step), indent, buf)
    // PKL-119c: Set reuses the same `<array>` path.
    SetValue(elements) => render_plist_array(elements, indent, buf)
    // PKL-119d: Map reuses the mapping-entries `<dict>` path.
    MapValue(entries) => render_plist_dict_from_entries(entries, indent, buf)
  }
}

///|
fn render_plist_dict_from_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  // Apple's `omitNullProperties` default is `true`; skip Null entries
  // before the dict envelope so an all-Null object renders as an
  // empty `<dict/>`.
  let kept : Array[ValueMember] = []
  for field in visible {
    if !(field.value is NullValue) {
      kept.push(field)
    }
  }
  write_plist_indent(buf, indent)
  if kept.length() == 0 {
    buf.write_string("<dict/>")
    return
  }
  buf.write_string("<dict>")
  for field in kept {
    buf.write_char('\n')
    write_plist_indent(buf, indent + 2)
    buf.write_string("<key>")
    write_plist_escaped(field.name, buf)
    buf.write_string("</key>")
    buf.write_char('\n')
    render_plist_value(field.value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</dict>")
}

///|
fn render_plist_dict_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let kept : Array[ValueEntry] = []
  for entry in entries {
    if !(entry.value is NullValue) {
      kept.push(entry)
    }
  }
  write_plist_indent(buf, indent)
  if kept.length() == 0 {
    buf.write_string("<dict/>")
    return
  }
  buf.write_string("<dict>")
  for entry in kept {
    buf.write_char('\n')
    write_plist_indent(buf, indent + 2)
    buf.write_string("<key>")
    write_plist_escaped(plist_coerce_key(entry.key), buf)
    buf.write_string("</key>")
    buf.write_char('\n')
    render_plist_value(entry.value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</dict>")
}

///|
fn render_plist_array(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  write_plist_indent(buf, indent)
  if elements.length() == 0 {
    buf.write_string("<array/>")
    return
  }
  buf.write_string("<array>")
  for element in elements {
    if element is NullValue {
      continue
    }
    buf.write_char('\n')
    render_plist_value(element, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</array>")
}

///|
fn write_plist_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn write_plist_escaped(value : String, buf : StringBuilder) -> Unit {
  for c in value {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(c)
    }
  }
}

///|
fn plist_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
/// Render a Value as a Java Properties document, mirroring the shape of
/// `pkl eval -f properties`.
///
/// Top-level Object / Mapping members flatten into dotted keys. Scalars emit
/// as `key = value` lines (unquoted, with property-style escaping for `\`,
/// `\n`, `\t`, `\r`, `\f`, leading space, `:`, `=`, `!`, `#`). Null leaves
/// are omitted (Apple Pkl's `omitNullProperties` default is `true`). Listings
/// render as a compact JSON-style single-line value (`[1,2,3]`), and the
/// JSON form's own `:` separators are then property-escaped to `\:`. Empty
/// Object / Mapping leaves are dropped entirely; empty Listings still emit
/// `key = []`. Top-level non-mapping values produce an empty document.
///
/// Apple Pkl's `restrictCharset = true` mode (emit `\uXXXX` for non-ASCII)
/// remains a follow-up — the default is `false` here, so unicode passes
/// through verbatim.
pub fn render_value_as_properties(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_properties_members(members, "", buf)
    MappingValue(entries) => render_properties_entries(entries, "", buf)
    _ => ()
  }
  buf.to_string()
}

///|
fn render_properties_members(
  members : Array[ValueMember],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for field in visible_members(members) {
    render_properties_leaf(prefix, field.name, field.value, buf)
  }
}

///|
fn render_properties_entries(
  entries : Array[ValueEntry],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for entry in entries {
    let key = properties_coerce_key(entry.key)
    render_properties_leaf(prefix, key, entry.value, buf)
  }
}

///|
fn render_properties_leaf(
  prefix : String,
  name : String,
  value : Value,
  buf : StringBuilder,
) -> Unit {
  let full_key = if prefix == "" { name } else { prefix + "." + name }
  match value {
    NullValue => ()
    ObjectValue(members) =>
      if members.length() == 0 {
        // Empty Object has no leaves, so drop the key entirely.
      } else {
        render_properties_members(members, full_key, buf)
      }
    MappingValue(entries) =>
      if entries.length() == 0 {
        // Empty Mapping likewise has no leaves.
      } else {
        render_properties_entries(entries, full_key, buf)
      }
    ListingValue(_) | FunctionValue(_, _, _, _, _) => {
      let compact = render_properties_compact_json(value)
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_value(compact, buf)
      buf.write_char('\n')
    }
    _ => {
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_properties_compact_json(value : Value) -> String {
  let buf = StringBuilder::new()
  write_compact_json_value(value, buf)
  buf.to_string()
}

///|
fn write_compact_json_value(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) => {
      let visible = visible_members(members)
      buf.write_char('{')
      for i = 0; i < visible.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(visible[i].name, buf)
        buf.write_char(':')
        write_compact_json_value(visible[i].value, buf)
      }
      buf.write_char('}')
    }
    MappingValue(entries) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(json_coerce_key(entries[i].key), buf)
        buf.write_char(':')
        write_compact_json_value(entries[i].value, buf)
      }
      buf.write_char('}')
    }
    ListingValue(elements) | ListValue(elements) => {
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    FunctionValue(_, _, _, _, _) => buf.write_string("null")
    DurationValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => render_json_string("\{n}.\{unit}", buf)
    RegexValue(pattern) => render_json_string(pattern, buf)
    BytesValue(bytes) => render_json_string(@base64.encode(bytes[:]), buf)
    // PKL-119a: properties uses the compact-JSON path for composite
    // values; project Pair the same way so a `Pair(1, "a")` shows up
    // as `[1,"a"]` inside the property line.
    PairValue(first, second) => {
      buf.write_char('[')
      write_compact_json_value(first, buf)
      buf.write_char(',')
      write_compact_json_value(second, buf)
      buf.write_char(']')
    }
    // PKL-119b: IntSeq materializes and reuses the listing path so
    // properties lines see `[1,2,3]` for `IntSeq(1, 3)`.
    IntSeqValue(start, end_v, step) => {
      let elements = intseq_materialize(start, end_v, step)
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    // PKL-119c: Set reuses the same compact array form.
    SetValue(elements) => {
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    // PKL-119d: Map projects as a compact JSON object, mirroring the
    // MappingValue projection so properties output sees `{"a":1,"b":2}`
    // for `Map("a", 1, "b", 2)`.
    MapValue(entries) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(json_coerce_key(entries[i].key), buf)
        buf.write_char(':')
        write_compact_json_value(entries[i].value, buf)
      }
      buf.write_char('}')
    }
  }
}

///|
fn write_properties_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("")
    StringValue(s) => write_properties_value(s, buf)
    DurationValue(n, unit) => write_properties_value("\{n}.\{unit}", buf)
    DataSizeValue(n, unit) => write_properties_value("\{n}.\{unit}", buf)
    RegexValue(pattern) => write_properties_value(pattern, buf)
    BytesValue(bytes) => write_properties_value(@base64.encode(bytes[:]), buf)
    _ =>
      // Unreachable in practice: render_properties_leaf already dispatches
      // composites through the compact-JSON path.
      write_properties_value(render_properties_compact_json(value), buf)
  }
}

///|
fn write_properties_key(key : String, buf : StringBuilder) -> Unit {
  for c in key {
    match c {
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0C}' => buf.write_string("\\f")
      ' ' => buf.write_string("\\ ")
      ':' => buf.write_string("\\:")
      '=' => buf.write_string("\\=")
      '!' => buf.write_string("\\!")
      '#' => buf.write_string("\\#")
      _ => buf.write_char(c)
    }
  }
}

///|
fn write_properties_value(s : String, buf : StringBuilder) -> Unit {
  let mut first = true
  for c in s {
    if first && c == ' ' {
      buf.write_string("\\ ")
    } else {
      match c {
        '\\' => buf.write_string("\\\\")
        '\n' => buf.write_string("\\n")
        '\r' => buf.write_string("\\r")
        '\t' => buf.write_string("\\t")
        '\u{0C}' => buf.write_string("\\f")
        ':' => buf.write_string("\\:")
        '=' => buf.write_string("\\=")
        '!' => buf.write_string("\\!")
        '#' => buf.write_string("\\#")
        _ => buf.write_char(c)
      }
    }
    first = false
  }
}

///|
fn properties_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn eval_source_with_imports(
  source : String,
  resolve_import : (String) -> EvalResult?,
) -> EvalResult {
  eval_source_with_import_details(source, resolve_import, fn(_) { None })
}

///|
fn eval_source_with_import_details(
  source : String,
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> EvalResult {
  let parsed = parse_source(source)
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return EvalError(diagnostics)
  }
  match
    eval_program(
      parsed.program,
      diagnostics,
      resolve_import,
      resolve_import_classes,
    ) {
    Some(value) =>
      if diagnostics.length() == 0 {
        EvalOk(value)
      } else {
        EvalError(diagnostics)
      }
    None => EvalError(diagnostics)
  }
}
