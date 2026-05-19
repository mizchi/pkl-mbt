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
  // PKL-148bb: original right-hand expression captured at eval time so an
  // amend overlay can re-evaluate the slot when a sibling it references
  // gets overridden (late binding — `x = y; y = 3` then `(base) { y = 4 }`
  // must propagate the new `y` into `x`). `None` for slots whose value
  // was never produced from a user-source Expr (synthetic sentinels,
  // method-built ObjectValue, etc.). Excluded from equality so existing
  // test fixtures that compare `ValueMember::{ name, value, source: None }`
  // against an evaluator output (which now carries the captured Expr)
  // still match — the user-visible state is the (name, value) pair.
  source : Expr?
} derive(Debug)

///|
impl Eq for ValueMember with equal(a, b) {
  a.name == b.name && a.value == b.value
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
  // equality (`ValueMember::{ name: "result", value: IntValue(3), source: None }`);
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
    "Dynamic" =>
      match value {
        ObjectValue(_) => true
        _ => false
      }
    // PKL-148bh: `module` is the enclosing-module type — every
    // ObjectValue satisfies it structurally, matching how Apple Pkl
    // treats the annotation in types/currentModuleType*.
    "module" =>
      match value {
        ObjectValue(_) => true
        _ => false
      }
    // PKL-148bh: `unknown` is Apple Pkl's wildcard type — accepts
    // every runtime value (basic/newInAmendingModuleMethod's
    // `function parrot(): unknown`).
    "unknown" => true
    "Any" => true
    _ => false
  }
}

///|

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
  eval_source_with_import_details_named(
    source, None, resolve_import, resolve_import_classes,
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
