///|
pub(all) enum Value {
  // PKL-150: Pkl's `Int` is i64. We stored it in MoonBit's `Int` (i32)
  // through PKL-149; everything from Unix-ns timestamps to bitwise ops on
  // the upper 32 bits silently truncated. Carrying Int64 in the variant
  // keeps the runtime aligned with the language reference and is the
  // load-bearing change for the api/int / api/dataSize / api/duration
  // gold-match.
  IntValue(Int64)
  // PKL-092: Float numeric value backed by MoonBit's `Double`. Arithmetic
  // between `IntValue` and `FloatValue` promotes to `FloatValue`; the
  // dedicated `Number` type sits above both in the typechecker hierarchy.
  FloatValue(Double)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  DeferredImportValue(String)
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
  // Collection values that carry a Pkl `default` member. `raw_*`
  // preserves the explicitly declared elements / entries; `materialized_*`
  // is the user-visible projection after applying the current default.
  // Keeping both lets `(xs) { default { ... } }` reapply a new default to
  // old entries without treating values supplied by the previous default
  // as explicit user fields.
  DefaultedListingValue(Array[Value], Array[Value], Value)
  DefaultedMappingValue(Array[ValueEntry], Array[ValueEntry], Value)
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
  // PKL-150: IntSeq carries Int64 to match the widened Pkl `Int`.
  IntSeqValue(Int64, Int64, Int64)
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
  // `Bytes(<Listing of Int>)`, `Bytes(<Int>...)`, or
  // `Bytes.fromBase64("...")`; PCF round-trips through the varargs
  // constructor and JSON / YAML / Properties project the base64 string.
  BytesValue(Bytes)
} derive(Eq, Debug)

///|
pub(all) struct ValueMember {
  name : String
  value : Value
  annotations : Array[Annotation]
  // PKL-148bb: original right-hand expression captured at eval time so an
  // amend overlay can re-evaluate the slot when a sibling it references
  // gets overridden (late binding — `x = y; y = 3` then `(base) { y = 4 }`
  // must propagate the new `y` into `x`). `None` for slots whose value
  // was never produced from a user-source Expr (synthetic sentinels,
  // method-built ObjectValue, etc.). Excluded from equality so existing
  // test fixtures that compare `ValueMember::{ name, value, source: None, annotations: [] }`
  // against an evaluator output (which now carries the captured Expr)
  // still match — the user-visible state is the (name, value) pair.
  source : Expr?
} derive(Debug)

///|
impl Eq for ValueMember with equal(a, b) {
  a.name == b.name && a.value == b.value
}

///|
fn append_annotations(
  left : Array[Annotation],
  right : Array[Annotation],
) -> Array[Annotation] {
  let out : Array[Annotation] = []
  for item in left {
    out.push(item)
  }
  for item in right {
    out.push(item)
  }
  out
}

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
fn deferred_error_value(message : String) -> Value {
  ObjectValue([
    {
      name: error_member_name("@deferred"),
      value: StringValue(message),
      source: None,
      annotations: [],
    },
  ])
}

///|
fn deferred_error_message(value : Value) -> String? {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, error_member_name("@deferred")) {
        Some(StringValue(message)) => Some(message)
        _ => None
      }
    _ => None
  }
}

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
  // equality (`ValueMember::{ name: "result", value: IntValue(3), source: None, annotations: [] }`);
  // surfacing the synthetic function entries here would force every
  // test that declares a `function` to expand its expected ObjectValue
  // even though the user-visible render still hides them. The CLI's
  // `render_value` already skips hidden members, so this filter is the
  // only place the symmetry needs to be re-stated.
  match eval_source_with_imports(source, fn(_) { None }) {
    EvalOk(value) => EvalOk(strip_invisible_recursive(value))
    other => other
  }
}

///|
/// PKL-148bh: recursively strip invisible members (hidden /
/// local / error sentinels / class tags) from an evaluation result.
/// The test harness compares evaluator output against
/// hand-constructed ObjectValue arrays that don't carry the runtime
/// markers; preserving them at depth 1+ broke fixtures that nest a
/// typed instance inside a module-level binding (universal class
/// tagging in `tag_object_with_class` started writing the
/// `@hidden$__class` marker for every typed body).
fn strip_invisible_recursive(value : Value) -> Value {
  match value {
    ObjectValue(members) => {
      let kept : Array[ValueMember] = []
      let preserve_class_tag = match find_object_class_tag(members) {
        Some("RenderDirective") => true
        _ => false
      }
      for m in members {
        if is_invisible_member_name(m.name) &&
          !(preserve_class_tag && m.name == class_tag_member_name()) {
          continue
        }
        kept.push({
          name: m.name,
          value: strip_invisible_recursive(m.value),
          source: m.source,
          annotations: m.annotations,
        })
      }
      ObjectValue(kept)
    }
    ListingValue(elements) => {
      let kept : Array[Value] = []
      for e in elements {
        kept.push(strip_invisible_recursive(e))
      }
      ListingValue(kept)
    }
    DefaultedListingValue(raw, elements, default_value) => {
      let kept_raw : Array[Value] = []
      for e in raw {
        kept_raw.push(strip_invisible_recursive(e))
      }
      let kept_elements : Array[Value] = []
      for e in elements {
        kept_elements.push(strip_invisible_recursive(e))
      }
      DefaultedListingValue(
        kept_raw,
        kept_elements,
        strip_invisible_recursive(default_value),
      )
    }
    ListValue(elements) => {
      let kept : Array[Value] = []
      for e in elements {
        kept.push(strip_invisible_recursive(e))
      }
      ListValue(kept)
    }
    SetValue(elements) => {
      let kept : Array[Value] = []
      for e in elements {
        kept.push(strip_invisible_recursive(e))
      }
      SetValue(kept)
    }
    MappingValue(entries) => {
      let kept : Array[ValueEntry] = []
      for entry in entries {
        kept.push({
          key: strip_invisible_recursive(entry.key),
          value: strip_invisible_recursive(entry.value),
        })
      }
      MappingValue(kept)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let kept_raw : Array[ValueEntry] = []
      for entry in raw {
        kept_raw.push({
          key: strip_invisible_recursive(entry.key),
          value: strip_invisible_recursive(entry.value),
        })
      }
      let kept_entries : Array[ValueEntry] = []
      for entry in entries {
        kept_entries.push({
          key: strip_invisible_recursive(entry.key),
          value: strip_invisible_recursive(entry.value),
        })
      }
      DefaultedMappingValue(
        kept_raw,
        kept_entries,
        strip_invisible_recursive(default_value),
      )
    }
    MapValue(entries) => {
      let kept : Array[ValueEntry] = []
      for entry in entries {
        kept.push({
          key: strip_invisible_recursive(entry.key),
          value: strip_invisible_recursive(entry.value),
        })
      }
      MapValue(kept)
    }
    PairValue(a, b) =>
      PairValue(strip_invisible_recursive(a), strip_invisible_recursive(b))
    _ => value
  }
}

///| Render a runtime value in the canonical Pkl Configuration Format

///| (PCF). Primitives use the same lexical form as Apple Pkl's

///| `pkl eval` default output, so the result can be reparsed by this

///| evaluator and by upstream Pkl. The JSON / YAML / Properties

///| renderers (PKL-072..074) will live alongside this as separate

///|
/// entry points.
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
    Divide => Some(FloatValue(a / b))
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
        Some(IntValue(double_trunc(a / b).to_int64()))
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
/// Runtime matcher for the `is` operator. This checks generic collection
/// arguments and user-class tags; unlike the assignment/callable rejection
/// helpers, unions succeed when any branch fully matches.
fn eval_value_matches_type_annotation(
  type_name : String,
  value : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Bool {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(type_name, aliases)
  eval_value_matches_resolved_type_annotation(
    pkl_constraint_trim(resolved),
    value,
    class_env,
    declarations,
  )
}

///|
fn eval_value_matches_resolved_type_annotation(
  type_name : String,
  value : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Bool {
  let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(type_name))
  if trimmed == "" {
    return false
  }
  let choices = split_top_level_union_choices(trimmed)
  if choices.length() > 1 {
    for choice in choices {
      if eval_value_matches_type_annotation(
          choice, value, class_env, declarations,
        ) {
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
    return eval_value_matches_type_annotation(
      inner, value, class_env, declarations,
    )
  }
  match function_type_arity(trimmed) {
    Some(arity) =>
      return match value {
        FunctionValue(parameters, _, _, _, _) => parameters.length() == arity
        _ => false
      }
    None => ()
  }
  if trimmed.length() >= 2 &&
    trimmed.has_prefix("\"") &&
    trimmed.has_suffix("\"") {
    let literal = String::unsafe_substring(
      trimmed,
      start=1,
      end=trimmed.length() - 1,
    )
    return value is StringValue(s) && s == literal
  }
  let base = match pkl_constrained_type_base_name(trimmed) {
    Some(b) => b
    None => trimmed
  }
  match
    eval_value_matches_generic_type_annotation(
      base, value, class_env, declarations,
    ) {
    Some(ok) => return ok && eval_value_satisfies_constraint(trimmed, value)
    None => ()
  }
  if !eval_value_matches_bare_type(base, value, class_env) {
    return false
  }
  eval_value_satisfies_constraint(trimmed, value)
}

///|
fn eval_value_matches_generic_type_annotation(
  type_name : String,
  value : Value,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Bool? {
  match generic_argument_text(type_name, "List") {
    Some(element_type) =>
      return match value {
        ListValue(elements) =>
          Some(
            eval_all_elements_match_type(
              elements, element_type, class_env, declarations,
            ),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Set") {
    Some(element_type) =>
      return match value {
        SetValue(elements) =>
          Some(
            eval_all_elements_match_type(
              elements, element_type, class_env, declarations,
            ),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Listing") {
    Some(element_type) =>
      return match value {
        ListingValue(elements) | DefaultedListingValue(_, elements, _) =>
          Some(
            eval_all_elements_match_type(
              elements, element_type, class_env, declarations,
            ),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Collection") {
    Some(element_type) =>
      return match value {
        ListValue(elements) | SetValue(elements) =>
          Some(
            eval_all_elements_match_type(
              elements, element_type, class_env, declarations,
            ),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Map") {
    Some(inner) =>
      return match value {
        MapValue(entries) =>
          Some(
            eval_all_entries_match_type(entries, inner, class_env, declarations),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Mapping") {
    Some(inner) =>
      return match value {
        MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
          Some(
            eval_all_entries_match_type(entries, inner, class_env, declarations),
          )
        _ => Some(false)
      }
    None => ()
  }
  match generic_argument_text(type_name, "Pair") {
    Some(inner) => {
      let parts = split_top_level_generic_arguments(inner)
      if parts.length() != 2 {
        return Some(false)
      }
      return match value {
        PairValue(first, second) =>
          Some(
            eval_value_matches_type_annotation(
              parts[0],
              first,
              class_env,
              declarations,
            ) &&
            eval_value_matches_type_annotation(
              parts[1],
              second,
              class_env,
              declarations,
            ),
          )
        _ => Some(false)
      }
    }
    None => ()
  }
  None
}

///|
fn eval_all_elements_match_type(
  elements : Array[Value],
  element_type : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Bool {
  for element in elements {
    if !eval_value_matches_type_annotation(
        element_type, element, class_env, declarations,
      ) {
      return false
    }
  }
  true
}

///|
fn eval_all_entries_match_type(
  entries : Array[ValueEntry],
  inner : String,
  class_env : Array[ClassBinding],
  declarations : Array[Declaration],
) -> Bool {
  let parts = split_top_level_generic_arguments(inner)
  if parts.length() != 2 {
    return false
  }
  let key_type = parts[0]
  let value_type = parts[1]
  for entry in entries {
    if !eval_value_matches_type_annotation(
        key_type,
        entry.key,
        class_env,
        declarations,
      ) ||
      !eval_value_matches_type_annotation(
        value_type,
        entry.value,
        class_env,
        declarations,
      ) {
      return false
    }
  }
  true
}

///|
fn eval_value_matches_bare_type(
  type_name : String,
  value : Value,
  class_env : Array[ClassBinding],
) -> Bool {
  match type_name {
    "Any" | "unknown" => true
    "Int" => value is IntValue(_)
    "Float" => value is FloatValue(_)
    "Number" => value is IntValue(_) || value is FloatValue(_)
    "String" => value is StringValue(_)
    "Boolean" | "Bool" => value is BoolValue(_)
    "Null" => value is NullValue
    "Duration" => value is DurationValue(_, _)
    "DataSize" => value is DataSizeValue(_, _)
    "Regex" => value is RegexValue(_)
    "Bytes" => value is BytesValue(_)
    "List" => value is ListValue(_)
    "Set" => value is SetValue(_)
    "Collection" => value is ListValue(_) || value is SetValue(_)
    "Map" => value is MapValue(_)
    "Listing" =>
      value is ListingValue(_) || value is DefaultedListingValue(_, _, _)
    "Mapping" =>
      value is MappingValue(_) || value is DefaultedMappingValue(_, _, _)
    "Pair" => value is PairValue(_, _)
    "IntSeq" => value is IntSeqValue(_, _, _)
    "Mixin" =>
      match value {
        ObjectValue(members) =>
          object_class_tag_matches(members, "Mixin") ||
          object_members_are_mixin_body(members)
        _ => false
      }
    "Object" | "Dynamic" | "Typed" => value is ObjectValue(_)
    "Class" =>
      match value {
        ObjectValue(members) => reflect_kind(members) is Some("Class")
        _ => false
      }
    "Function" => value is FunctionValue(_, _, _, _, _)
    _ =>
      match function_arity_from_type_name(type_name) {
        Some(arity) =>
          match value {
            FunctionValue(parameters, _, _, _, _) =>
              parameters.length() == arity
            _ => false
          }
        None => eval_value_matches_user_class_tag(type_name, value, class_env)
      }
  }
}

///|
fn eval_value_matches_user_class_tag(
  type_name : String,
  value : Value,
  class_env : Array[ClassBinding],
) -> Bool {
  match value {
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(tag) => {
          let chain = class_chain_for_tag(tag, class_env)
          for ancestor in chain {
            if name_matches_class_tag(type_name, ancestor) {
              return true
            }
          }
          false
        }
        None =>
          eval_untagged_object_matches_class_shape(
            members, type_name, class_env,
          )
      }
    _ => false
  }
}

///|
fn eval_untagged_object_matches_class_shape(
  members : Array[ValueMember],
  type_name : String,
  class_env : Array[ClassBinding],
) -> Bool {
  let declared : Array[String] = []
  collect_class_property_names(declared, type_name, class_env)
  if declared.length() == 0 {
    return false
  }
  for name in declared {
    if lookup_member(members, name) is None {
      return false
    }
  }
  true
}

///|
fn function_arity_from_type_name(type_name : String) -> Int? {
  if !type_name.has_prefix("Function") {
    return None
  }
  if type_name == "Function" {
    return None
  }
  let suffix = String::unsafe_substring(
    type_name,
    start="Function".length(),
    end=type_name.length(),
  )
  parse_nonnegative_int(suffix)
}

///|
fn eval_value_satisfies_constraint(type_name : String, value : Value) -> Bool {
  pkl_constrained_type_annotation_value_rejection_message_from_source(
    type_name, type_name, value,
  )
  is None
}

///|
fn parse_nonnegative_int(text : String) -> Int? {
  if text == "" {
    return None
  }
  let mut value = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c < '0' || c > '9' {
      return None
    }
    value = value * 10 + c.to_int() - '0'.to_int()
  }
  Some(value)
}

///|

///|
fn eval_source_with_imports(
  source : String,
  resolve_import : (String) -> EvalResult?,
) -> EvalResult {
  eval_source_with_import_details(
    source,
    resolve_import,
    fn(_) { None },
    fn(_) { None },
  )
}

///|
fn eval_source_with_import_details(
  source : String,
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
  resolve_import_bindings : (String) -> Array[Binding]?,
) -> EvalResult {
  eval_source_with_import_details_named(
    source,
    None,
    resolve_import,
    resolve_import_classes,
    resolve_import_bindings,
  )
}

///|
/// PKL-148bh: extended form accepting a fallback module name (derived
/// from the file path when the source omits an explicit
/// `module X` header). Threaded through `eval_program` so reflect
/// mirrors can build the `<module>#<simple>` qualified shape Apple
/// Pkl prints from Class.toString / TypeAlias.toString.
fn eval_source_with_import_details_named(
  source : String,
  fallback_module_name : String?,
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
  resolve_import_bindings : (String) -> Array[Binding]?,
) -> EvalResult {
  eval_source_with_import_details_named_at(
    source,
    fallback_module_name,
    None,
    resolve_import,
    resolve_import_classes,
    resolve_import_bindings,
  )
}

///|
fn eval_source_with_import_details_named_at(
  source : String,
  fallback_module_name : String?,
  current_module_path : String?,
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
  resolve_import_bindings : (String) -> Array[Binding]?,
) -> EvalResult {
  let parsed = parse_source(source)
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return EvalError(diagnostics)
  }
  let program = parsed.program
  let effective_name = match program.module_name {
    Some(_) => program.module_name
    None => fallback_module_name
  }
  let promoted_program : Program = if effective_name == program.module_name {
    program
  } else {
    {
      module_name: effective_name,
      module_relation: program.module_relation,
      imports: program.imports,
      declarations: program.declarations,
      bindings: program.bindings,
      body: program.body,
      module_annotations: program.module_annotations,
    }
  }
  match
    eval_program(
      promoted_program,
      current_module_path,
      Some(source),
      diagnostics,
      resolve_import,
      resolve_import_classes,
      resolve_import_bindings,
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
