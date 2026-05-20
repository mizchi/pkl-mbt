///|
test "Int.toChar() projects a Unicode code point to a String" {
  assert_true(
    eval_source("a = 65\nA = a.toChar()\nz = 122\nlowercase_z = z.toChar()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "a",
          value: IntValue(65),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "A",
          value: StringValue("A"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "z",
          value: IntValue(122),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "lowercase_z",
          value: StringValue("z"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Int builtins compose with String / Listing pipelines" {
  assert_true(
    eval_source(
      "xs = new Listing { 10; 255; 16 }\nhex_csv = xs.map((n) -> n.toString(16)).join(\",\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(10), IntValue(255), IntValue(16)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "hex_csv",
          value: StringValue("a,ff,10"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "pkl:math exposes Int range constants" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nmax32 = math.maxInt32\nmin32 = math.minInt32\nmax = math.maxInt\nmin = math.minInt",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "max32",
          value: IntValue(2147483647),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "min32",
          value: IntValue(-2147483648),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "max",
          value: IntValue(9223372036854775807),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "min",
          value: IntValue(-9223372036854775807 - 1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "pkl:math exposes Int abs, min, max functions" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nabs_neg = math.abs(-7)\nabs_pos = math.abs(4)\nmn = math.min(3, 8)\nmx = math.max(3, 8)\nmn_eq = math.min(5, 5)\nmx_eq = math.max(5, 5)",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "abs_neg",
          value: IntValue(7),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "abs_pos",
          value: IntValue(4),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "mn",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "mx",
          value: IntValue(8),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "mn_eq",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "mx_eq",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "pkl:math exposes finite Float range constants" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nmax = math.maxFiniteFloat\nmin = math.minFiniteFloat",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut max_seen = false
  let mut min_seen = false
  for entry in members {
    match (entry.name, entry.value) {
      ("max", FloatValue(value)) =>
        if !value.is_inf() && value > 1.0e300 {
          max_seen = true
        }
      ("min", FloatValue(value)) =>
        if !value.is_inf() && value < -1.0e300 {
          min_seen = true
        }
      _ => ()
    }
  }
  assert_true(max_seen && min_seen)
}

///|
test "generic function declaration parses and evaluates" {
  // PKL-090: `function identity<T>(x: T): T = x` parses with the type
  // parameter list, typechecks (T binds to UnknownType inside the body),
  // and evaluates as a normal function. Call-site inference of T from
  // the argument type stays deferred.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "function identity<T>(x: T): T = x\nres = identity(42)",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut res_value : Value? = None
  for entry in members {
    if entry.name == "res" {
      res_value = Some(entry.value)
    }
  }
  assert_true(res_value == Some(IntValue(42)))
}

///|
test "generic function with two type parameters" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "function pair_first<A, B>(a: A, b: B): A = a\nres = pair_first(7, \"x\")",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut res_value : Value? = None
  for entry in members {
    if entry.name == "res" {
      res_value = Some(entry.value)
    }
  }
  assert_true(res_value == Some(IntValue(7)))
}

///|
test "generic class declaration parses without error" {
  // PKL-089: `class Box<T>` parses, captures `T` as a type parameter on
  // the ClassDecl, and typechecks (T binds to UnknownType inside the
  // class body). Instantiation-time T-binding lands with PKL-090.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Box<T> { value: T }\nb = new Box { value = 5 }",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut box_value : Value? = None
  for entry in members {
    if entry.name == "b" {
      box_value = Some(entry.value)
    }
  }
  assert_true(
    box_value ==
    Some(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "generic class declaration with two type parameters" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Pair<A, B> { first: A; second: B }\np = new Pair { first = 1; second = \"hi\" }",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  assert_true(true)
}

///|
test "PKL-110: generic function return type substitutes argument type" {
  // identity<T>(7): T binds Int at the call site, so identity(7) + 1
  // typechecks as Int + Int → Int.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "function identity<T>(x: T): T = x\nres = identity(7) + 1",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  assert_true(true)
}

///|
test "PKL-110: generic function rejects mismatched downstream usage" {
  // T binds String at the call site, so identity("hi") + 1 is a typecheck
  // error (String + Int rejects). Without PKL-110 substitution the return
  // type was UnknownType and the downstream + was silently accepted.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "function identity<T>(x: T): T = x\nres = identity(\"hi\") + 1",
  )
  guard session.typecheck_path("main.pkl") is TypeError(_) else { panic() }
  assert_true(true)
}

///|
test "PKL-110: generic class member type instantiates from literal" {
  // class Box<T> { value: T }: when we write `new Box { value = 5 }`,
  // T binds Int and b.value resolves to Int, so b.value + 1 typechecks.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Box<T> { value: T }\nb = new Box { value = 5 }\nres = b.value + 1",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
  assert_true(true)
}

///|
test "PKL-110: generic class member type rejects after instantiation" {
  // After T binds String, b.value is String, so b.value + 1 fails.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Box<T> { value: T }\nb = new Box { value = \"hi\" }\nres = b.value + 1",
  )
  guard session.typecheck_path("main.pkl") is TypeError(_) else { panic() }
  assert_true(true)
}

///|
test "Float literal evaluates as FloatValue" {
  // PKL-092: `3.14` lexes into a Float token, parses into `FloatLiteral`,
  // and evaluates into `FloatValue`. Sanity check before the
  // mixed-arithmetic and constraint cascade tests stack on top.
  assert_true(
    eval_source("res = 3.14") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(3.14),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Float arithmetic widens Int operands" {
  guard eval_source("res = 1 + 2.5") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  assert_true(value == Some(FloatValue(3.5)))
}

///|
test "Float comparison accepts Int / Float mix" {
  assert_true(
    eval_source("res = 1.5 < 2") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Int division widens to Float" {
  guard eval_source("res = 5 / 2") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  assert_true(value == Some(FloatValue(2.5)))
}

///|
test "PKL-111: Float Power widens" {
  // 2.0 ** 3 = 8.0 (matches Apple Pkl: any Float operand on `**` widens
  // the result to Float).
  guard eval_source("res = 2.0 ** 3") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  assert_true(value == Some(FloatValue(8.0)))
}

///|
test "PKL-111: Float Power Float exponent" {
  // 2.3 ** 4.0 ≈ 27.984... matches Apple's golden expansion.
  guard eval_source("res = 2.3 ** 4.0") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  match value {
    Some(FloatValue(d)) => assert_true((d - 27.984099999999998).abs() < 1.0e-9)
    _ => panic()
  }
}

///|
test "PKL-111: IntDivide on Float operands returns Int" {
  // Apple Pkl: 5.0 ~/ 3 = 1 (Int), 5.0 ~/ 3.0 = 1, 5.1 ~/ 3.1 = 1.
  guard eval_source("res = 5.0 ~/ 3.0") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  assert_true(value == Some(IntValue(1)))
}

///|
test "PKL-111: Modulo widens on Float operands" {
  // Apple Pkl: 5.5 % 6.5 = 5.5, 5 % 6.5 = 5.0.
  guard eval_source("res = 5.5 % 6.5") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut value : Value? = None
  for entry in members {
    if entry.name == "res" {
      value = Some(entry.value)
    }
  }
  assert_true(value == Some(FloatValue(5.5)))
}

///|
test "Float annotation accepts Float value" {
  assert_true(
    eval_source("res: Float = 3.14") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(3.14),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Number annotation accepts Int and Float" {
  assert_true(
    eval_source("a: Number = 5\nb: Number = 2.5") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "a",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: FloatValue(2.5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Float constraint predicate accepts in-range Float" {
  assert_true(
    eval_source("res: Float(isPositive) = 1.5") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(1.5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Float constraint predicate rejects out-of-range Float" {
  guard eval_source("res: Float(isPositive) = 0.0 - 0.5")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="Type constraint `isPositive` violated. Value: -0.5",
  )
}

///|
test "Float isBetween accepts inclusive endpoints" {
  assert_true(
    eval_source("res: Float(isBetween(0, 10)) = 5.5") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(5.5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-112: Float isBetween accepts Float thresholds in range" {
  assert_true(
    eval_source("res: Float(isBetween(0.5, 1.5)) = 1.0") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(1.0),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-112: Float isBetween with Float thresholds rejects out-of-range" {
  guard eval_source("res: Float(isBetween(0.5, 1.5)) = 2.0")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0.5, 1.5)` violated. Value: 2
    ),
  )
}

///|
test "PKL-150: Float stdlib property and conversion surface" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|nan = NaN.isNaN
      #|finite = 42.123.isFinite
      #|infinite = Infinity.isInfinite
      #|between = 3.3.isBetween(2.2, 4.4)
      #|nonzero = (-3.3).isNonZero
      #|duration = 3.21.toDuration("min")
      #|dataSize = (-99.999).toDataSize("gib")
      #|sign = (-2.34).sign
      #|abs = (-2.34).abs
      #|ceil = (-2.34).ceil
      #|floor = (-2.34).floor
      #|round = (-2.9).round()
      #|truncate = (-2.9).truncate()
      #|int = (-2.9).toInt()
      #|float = (-2.9).toFloat()
      #|fixedText = 1.23456789.toFixed(4)
      #|badFixed = test.catch(() -> 1.23.toFixed(21))
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(rendered.contains("nan = true"), content="true")
  inspect(rendered.contains("finite = true"), content="true")
  inspect(rendered.contains("infinite = true"), content="true")
  inspect(rendered.contains("between = true"), content="true")
  inspect(rendered.contains("nonzero = true"), content="true")
  inspect(rendered.contains("duration = 3.21.min"), content="true")
  inspect(rendered.contains("dataSize = -99.999.gib"), content="true")
  inspect(rendered.contains("sign = -1.0"), content="true")
  inspect(rendered.contains("abs = 2.34"), content="true")
  inspect(rendered.contains("ceil = -2.0"), content="true")
  inspect(rendered.contains("floor = -3.0"), content="true")
  inspect(rendered.contains("round = -3.0"), content="true")
  inspect(rendered.contains("truncate = -2.0"), content="true")
  inspect(rendered.contains("int = -2"), content="true")
  inspect(rendered.contains("float = -2.9"), content="true")
  inspect(rendered.contains("fixedText = \"1.2346\""), content="true")
  inspect(
    rendered.contains(
      "badFixed = \"Type constraint `this.isBetween(0, 20)` violated. Value: 21\"",
    ),
    content="true",
  )
}

///|
test "PKL-112: Float isGreaterThan accepts Float threshold" {
  assert_true(
    eval_source("res: Float(isGreaterThan(0.5)) = 0.75") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: FloatValue(0.75),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-112: Float isLessThan with Float threshold rejects" {
  guard eval_source("res: Float(isLessThan(1.5)) = 2.0")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `isLessThan(1.5)` violated. Value: 2
    ),
  )
}

///|
test "PKL-113: == rejects Int and String operands" {
  guard typecheck_source("res = 5 == \"hi\"") is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="operator == expects operands of matching types",
  )
}

///|
test "PKL-113: != rejects Bool and Int operands" {
  guard typecheck_source("res = true != 3") is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="operator != expects operands of matching types",
  )
}

///|
test "PKL-113: == accepts same-type Int operands" {
  guard typecheck_source("res = 5 == 5") is TypeOk(_) else { panic() }
}

///|
test "PKL-113: == accepts Int and Float operands" {
  guard typecheck_source("res = 5 == 5.5") is TypeOk(_) else { panic() }
}

///|
test "PKL-113: == accepts null against nullable binding" {
  guard typecheck_source("name: String? = null\nres = name == null")
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-114: is Int evaluates to true for Int value" {
  assert_true(
    eval_source("res = 5 is Int") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-114: is Float evaluates to true for Float value" {
  assert_true(
    eval_source("res = 1.5 is Float") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-114: is Int evaluates to false for String value" {
  assert_true(
    eval_source("res = \"x\" is Int") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-114: is Number evaluates to true for Int and Float values" {
  assert_true(
    eval_source("a = 5 is Number\nb = 1.5 is Number\nc = \"x\" is Number") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "a",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "c",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-114: is guard branches on runtime type" {
  assert_true(
    eval_source(
      "function f(x: Number): Int = if (x is Int) x + 1 else 0\nres = f(5)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "function f(x: Number): Int = if (x is Int) x + 1 else 0\nres = f(2.5)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: IntValue(0),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-114: Float? narrows on is Float guard (typecheck)" {
  assert_true(
    typecheck_source(
      "function bump(x: Float?): Float = if (x is Float) x + 0.5 else 0.0\nvalue = bump(1.5)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: FloatType }])),
  )
}

///|
test "PKL-114: Number narrows on is Int positive guard (typecheck)" {
  assert_true(
    typecheck_source(
      "function plusOne(x: Number): Int = if (x is Int) x + 1 else 0\nvalue = plusOne(3)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
}

///|
test "PKL-114: Number narrows on is Float positive guard (typecheck)" {
  assert_true(
    typecheck_source(
      "function plusHalf(x: Number): Float = if (x is Float) x + 0.5 else 0.0\nvalue = plusHalf(3.0)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: FloatType }])),
  )
}

///|
test "PKL-115: parses typealias with single type parameter" {
  let parsed = parse_source("typealias Box<T> = Listing<T>")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.program.declarations.length(), content="1")
  guard parsed.program.declarations[0] is TypeAliasDeclaration(decl) else {
    panic()
  }
  inspect(decl.name, content="Box")
  inspect(decl.type_parameters.length(), content="1")
  inspect(decl.type_parameters[0], content="T")
  inspect(decl.target, content="Listing<T>")
}

///|
test "PKL-115: generic typealias accepts matching argument" {
  guard typecheck_source(
      "typealias Box<T> = Listing<T>\nb: Box<Int> = new Listing { 1; 2; 3 }",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-115: generic typealias rejects mismatched argument" {
  guard typecheck_source(
      "typealias Box<T> = Listing<T>\nb: Box<Int> = new Listing { \"a\"; \"b\" }",
    )
    is TypeError(_) else {
    panic()
  }
}

///|
test "PKL-115: generic typealias with two parameters" {
  let parsed = parse_source("typealias Pair<K, V> = Mapping<K, V>")
  guard parsed.program.declarations[0] is TypeAliasDeclaration(decl) else {
    panic()
  }
  inspect(decl.type_parameters.length(), content="2")
  inspect(decl.type_parameters[0], content="K")
  inspect(decl.type_parameters[1], content="V")
  inspect(decl.target, content="Mapping<K,V>")
}

///|
test "PKL-116: function type parameter bound parses" {
  let parsed = parse_source("function pick<T : Number>(x: T): T = x")
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is FunctionDeclaration(decl) else {
    panic()
  }
  inspect(decl.type_parameters.length(), content="1")
  inspect(decl.type_parameters[0], content="T")
  inspect(decl.type_parameter_bounds.length(), content="1")
  guard decl.type_parameter_bounds[0] is Some(bound_text) else { panic() }
  inspect(bound_text, content="Number")
}

///|
test "PKL-116: class type parameter bound parses" {
  let parsed = parse_source("class Container<T : Number> { value: T }")
  guard parsed.program.declarations[0] is ClassDeclaration(decl) else {
    panic()
  }
  inspect(decl.type_parameters.length(), content="1")
  inspect(decl.type_parameters[0], content="T")
  inspect(decl.type_parameter_bounds.length(), content="1")
  guard decl.type_parameter_bounds[0] is Some(bound_text) else { panic() }
  inspect(bound_text, content="Number")
}

///|
test "PKL-116: function call accepts argument that satisfies bound" {
  guard typecheck_source(
      "function pick<T : Number>(x: T): T = x\nvalue = pick(5)",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-116: function call rejects argument that violates bound" {
  guard typecheck_source(
      "function pick<T : Number>(x: T): T = x\nvalue = pick(\"hi\")",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type parameter T bound Int|Float rejects String",
  )
}

///|
test "PKL-116: function without bound still accepts any type" {
  guard typecheck_source("function pick<T>(x: T): T = x\nvalue = pick(\"hi\")")
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-133: Any annotation accepts any value" {
  guard typecheck_source("x: Any = 5\ny: Any = \"hello\"\nz: Any = true")
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-133: Any annotation renders as Any" {
  guard typecheck_source("x: Any = 5") is TypeOk(ObjectType(members)) else {
    panic()
  }
  inspect(render_type(members[0].typ), content="Any")
}

///|
test "PKL-133: nullable Any accepts null and concrete values" {
  guard typecheck_source("a: Any? = null\nb: Any? = 42") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-133: Mapping with Any value type accepts heterogeneous map" {
  guard typecheck_source(
      "m: Mapping<String, Any> = new Mapping { [\"n\"] = 1; [\"s\"] = \"x\" }",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-133: == accepts Any against any operand" {
  guard typecheck_source("x: Any = 5\nres = x == 5") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-148h: Listing.toList() projects to a ListValue" {
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nys = xs.toList()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "ys",
          value: ListValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-134: Mapping.toMap() returns same entries" {
  guard eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }\nm2 = m.toMap()",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  inspect(members.length(), content="2")
}

///|
test "PKL-134: List<T> type annotation resolves" {
  guard typecheck_source("xs: List<Int> = new Listing { 1; 2; 3 }") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-134: Listing.length and isEmpty stay green" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3 }\nn = xs.length\ne = xs.isEmpty",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members.length() == 3)
}

///|
test "PKL-134: Mapping.keys and values stay green" {
  guard eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }\nks = m.keys\nvs = m.values",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members.length() == 3)
}

///|
test "PKL-135: Listing.count counts matching elements" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3; 4 }\nn = xs.count((x) -> x.isEven)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is IntValue(n) else { panic() }
  inspect(n, content="2")
}

///|
test "PKL-135: Listing.every short-circuits on false" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3 }\nallPos = xs.every((x) -> x > 0)\nallEven = xs.every((x) -> x.isEven)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is BoolValue(all_pos) else { panic() }
  guard members[2].value is BoolValue(all_even) else { panic() }
  assert_true(all_pos)
  assert_true(!all_even)
}

///|
test "PKL-135: Listing.any returns true on first match" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3 }\nhasEven = xs.any((x) -> x.isEven)\nhasNeg = xs.any((x) -> x < 0)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is BoolValue(has_even) else { panic() }
  guard members[2].value is BoolValue(has_neg) else { panic() }
  assert_true(has_even)
  assert_true(!has_neg)
}

///|
test "PKL-135: Listing.none mirrors every with inverted predicate" {
  guard eval_source(
      "xs = new Listing { 1; 3; 5 }\nallOdd = xs.none((x) -> x.isEven)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is BoolValue(b) else { panic() }
  assert_true(b)
}

///|
test "PKL-135: Listing.find returns first match" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3; 4 }\nfirst = xs.find((x) -> x.isEven)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is IntValue(n) else { panic() }
  inspect(n, content="2")
}

///|
test "PKL-135: Listing.findLast walks back to front" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3; 4 }\nlast = xs.findLast((x) -> x.isEven)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is IntValue(n) else { panic() }
  inspect(n, content="4")
}

///|
test "PKL-135: Listing.findOrNull returns null on no match" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3 }\nmaybe = xs.findOrNull((x) -> x > 99)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members[1].value == NullValue)
}

///|
test "PKL-135: Listing.flatMap concatenates inner Listings" {
  guard eval_source(
      "xs = new Listing { 1; 2 }\nys = xs.flatMap((x) -> new Listing { x; x + 10 })",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="4")
}

///|
test "PKL-135: Mapping.every consumes (Key, Value) pairs" {
  guard eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }\nb = m.every((k, v) -> v > 0)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is BoolValue(b) else { panic() }
  assert_true(b)
}

///|
test "PKL-135: Mapping.count counts matching entries" {
  guard eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2; [\"c\"] = 3 }\nn = m.count((k, v) -> v.isOdd)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is IntValue(n) else { panic() }
  inspect(n, content="2")
}

///|
test "PKL-136: when inside Listing emits body when condition is true" {
  guard eval_source("xs = new Listing { 1; when (true) { 2; 3 }; 4 }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  inspect(xs.length(), content="4")
}

///|
test "PKL-136: when inside Listing skips body when condition is false" {
  guard eval_source("xs = new Listing { 1; when (false) { 2; 3 }; 4 }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  inspect(xs.length(), content="2")
}

///|
test "PKL-136: when else branch fires on false condition" {
  guard eval_source("xs = new Listing { when (false) { 1 } else { 2; 3 } }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  inspect(xs.length(), content="2")
}

///|
test "PKL-136: when inside Mapping spreads entries" {
  guard eval_source(
      "m = new Mapping { [\"a\"] = 1; when (true) { [\"b\"] = 2 } }",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MappingValue(entries) else { panic() }
  inspect(entries.length(), content="2")
}

///|
test "PKL-136: new Listing<T> parses body as listing" {
  guard eval_source("xs = new Listing<Int> { 1; 2; 3 }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  inspect(xs.length(), content="3")
}

///|
test "PKL-138: bare new { 1; 2; 3 } infers as listing body" {
  guard eval_source("xs: Listing<Int> = new { 1; 2; 3 }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  inspect(xs.length(), content="3")
}

///|
test "PKL-138: bare new { [\"a\"] = 1 } infers as mapping body" {
  guard eval_source(
      "m: Mapping<String, Int> = new { [\"a\"] = 1; [\"b\"] = 2 }",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MappingValue(entries) else { panic() }
  inspect(entries.length(), content="2")
}

///|
test "PKL-138: empty new {} coerces to ListingValue under Listing<T>" {
  guard eval_source("xs: Listing<Int> = new {}\nys = xs.toList()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(xs) else { panic() }
  // PKL-148h: `.toList()` projects through the dedicated ListValue
  // variant (PCF renders `List(...)`); the receiver Listing keeps the
  // Listing tag, so the two members carry different variants.
  guard members[1].value is ListValue(ys) else { panic() }
  inspect(xs.length(), content="0")
  inspect(ys.length(), content="0")
}

///|
test "PKL-138: empty new {} coerces to MappingValue under Mapping" {
  guard eval_source("m: Mapping<String, Int> = new {}\nks = m.keys")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MappingValue(_) else { panic() }
  guard members[1].value is ListingValue(ks) else { panic() }
  inspect(ks.length(), content="0")
}

///|
test "PKL-148: Listing default reapplies to existing and new elements" {
  let source =
    #|class Person {
    #|  name: String
    #|  age: Int = 42
    #|}
    #|res1: Listing<Person> = new {
    #|  new { name = "Pigeon" }
    #|}
    #|res2 = (res1) {
    #|  default { age = 21 }
    #|  new { name = "Parrot" }
    #|}
    #|res3 = (res2) {
    #|  default { n -> age = n }
    #|}
    #|res4 = (res3) {
    #|  (default.apply(5)) {
    #|    name = "Barn Owl"
    #|  }
    #|}
    #|res5 = (res4.getOrDefault(99)) {
    #|  name = "Bald Eagle"
    #|}
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(rendered.contains("name = \"Pigeon\"\n    age = 21"), content="true")
  inspect(rendered.contains("name = \"Parrot\"\n    age = 21"), content="true")
  inspect(rendered.contains("name = \"Barn Owl\"\n    age = 5"), content="true")
  inspect(
    rendered.contains("name = \"Bald Eagle\"\n  age = 99"),
    content="true",
  )
}

///|
test "PKL-148: Mapping default supports keyed functions and getOrDefault" {
  let source =
    #|class Person {
    #|  name: String
    #|  age: Int
    #|}
    #|res1: Mapping<String, Person> = new {
    #|  default { age = 42 }
    #|  ["pigeon"] { name = "Pigeon" }
    #|  ["parrot"] { name = "Parrot"; age = 50 }
    #|}
    #|res2 = (res1) {
    #|  default { age = 45 }
    #|}
    #|res3: Mapping<String, Person> = new {
    #|  default { key -> name = key }
    #|  ["pigeon"] { age = 40 }
    #|  ["susan"] { name = super.name + "!!!"; age = 60 }
    #|}
    #|res4 = (res3.getOrDefault("Bald Eagle")) {
    #|  age = 99
    #|}
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(
    rendered.contains("[\"pigeon\"] {\n    name = \"Pigeon\"\n    age = 45"),
    content="true",
  )
  inspect(
    rendered.contains("[\"parrot\"] {\n    name = \"Parrot\"\n    age = 50"),
    content="true",
  )
  inspect(
    rendered.contains("[\"susan\"] {\n    name = \"susan!!!\"\n    age = 60"),
    content="true",
  )
  inspect(
    rendered.contains("res4 {\n  name = \"Bald Eagle\"\n  age = 99"),
    content="true",
  )
}

///|
test "PKL-148: Listing and Mapping bodies bind this dynamically" {
  let source =
    #|list = new Listing {
    #|  "one"
    #|  this[0] + "!"
    #|}
    #|list2 = (list) {
    #|  "three"
    #|  this[2] + "!"
    #|  super[0] + "?"
    #|}
    #|map = new Mapping {
    #|  ["one"] = 1
    #|  ["two"] = this["one"] + 1
    #|}
    #|map2 = (map) {
    #|  ["one"] = super["one"] + 10
    #|  ["three"] = this["one"] + 10
    #|}
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(rendered.contains("\"one!\""), content="true")
  inspect(rendered.contains("\"three!\""), content="true")
  inspect(rendered.contains("\"one?\""), content="true")
  inspect(rendered.contains("[\"two\"] = 2"), content="true")
  inspect(rendered.contains("[\"one\"] = 11"), content="true")
  inspect(rendered.contains("[\"three\"] = 21"), content="true")
}

///|
test "PKL-138: bare new { ident = ... } still parses as object body" {
  guard eval_source("obj = new { name = \"foo\"; count = 5 }")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ObjectValue(inner) else { panic() }
  inspect(inner.length(), content="2")
}

///|
test "PKL-139: brace-bodied annotation skipped" {
  guard typecheck_source("@ModuleInfo { minPklVersion = \"0.31.0\" }\nx = 5")
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-139: multi-line typealias RHS" {
  guard typecheck_source(
      "typealias DisplayName =\n  String(length > 0)\nx: DisplayName = \"hi\"",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-139: dot-chain across newlines" {
  guard eval_source(
      "xs = new Listing { 1; 2; 3 }\nresult = xs\n  .toList()\n  .map((x) -> x + 1)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  // PKL-148bb: `.toList()` lifts the chain to `ListValue`, and the
  // shared listing-method dispatcher now preserves the receiver shape
  // through `.map` (`eval_list_or_listing_method`), so `.map(...)` on
  // a `ListValue` keeps the `ListValue` wrapper. Apple Pkl renders the
  // chained result through `List(2, 3, 4)`.
  guard members[1].value is ListValue(items) else { panic() }
  inspect(items.length(), content="3")
}

///|
test "PKL-139: module.foo self-reference resolves" {
  guard eval_source(
      "defaults: Mapping<String, String> = new { [\"a\"] = \"1\" }\nresult = module.defaults",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is MappingValue(entries) else { panic() }
  inspect(entries.length(), content="1")
}

///|
test "PKL-148h: List(...) constructor produces a ListValue" {
  guard eval_source("xs = List(1, 2, 3)") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(items) else { panic() }
  inspect(items.length(), content="3")
}

///|
test "PKL-148h: List() with no args produces an empty ListValue" {
  guard eval_source("xs = List()") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(items) else { panic() }
  inspect(items.length(), content="0")
}

///|
test "PKL-119c: Set(...) produces a dedicated SetValue with deduped elements" {
  guard eval_source("xs = Set(1, 2, 2, 3, 3, 3)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is SetValue(items) else { panic() }
  inspect(items.length(), content="3")
}

///|
test "PKL-119d: Map(...) builds a dedicated MapValue from alternating args" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MapValue(entries) else { panic() }
  inspect(entries.length(), content="2")
}

///|
test "PKL-119a: Pair(a, b) produces a dedicated PairValue" {
  guard eval_source("p = Pair(\"first\", \"second\")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is PairValue(first, second) else { panic() }
  guard first is StringValue(s_first) else { panic() }
  guard second is StringValue(s_second) else { panic() }
  inspect(s_first, content="first")
  inspect(s_second, content="second")
}

///|
test "PKL-140: external modifier on property declaration" {
  guard typecheck_source("external minInt: Int") is TypeOk(_) else { panic() }
}

///|
test "PKL-140: abstract slot of a nullable type defaults to null" {
  guard eval_source("foo: Int?\nbar = 5") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  inspect(members.length(), content="2")
  inspect(members[0].name, content="foo")
  inspect(members[0].value is NullValue, content="true")
  inspect(members[1].name, content="bar")
}

///|
test "PKL-140: variance modifier in T accepted on class" {
  guard typecheck_source("class Container<in T> { x: T }") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-140: variance modifier out T accepted on class" {
  guard typecheck_source("class Container<out T> { x: T }") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-140: function type annotation on property" {
  guard eval_source(
      "class V { x: Int }\nf: (V, V) -> Boolean = (a, b) -> a.x < b.x",
    )
    is EvalOk(ObjectValue(_)) else {
    panic()
  }
}

///|
test "PKL-140: declarations-only module evaluates to empty object" {
  guard eval_source("class Foo { x: Int }\ntypealias Bar = Int")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  inspect(members.length(), content="0")
}

///|
test "PKL-137: string-literal union typealias resolves" {
  guard typecheck_source(
      "typealias Severity = (\"critical\" | \"major\")\nx: Severity = \"major\"",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-137: empty new {} accepts Listing<T> annotation in typecheck" {
  guard typecheck_source("xs: Listing<Int> = new {}") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-137: empty new {} accepts Mapping annotation in typecheck" {
  guard typecheck_source("m: Mapping<String, Int> = new {}") is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-137: property amend body parses as listing for bare elements" {
  guard eval_source(
      "class T { name: String }\nbase: Listing<T> = new {}\nresult = base",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(_) else { panic() }
  guard members[1].value is ListingValue(_) else { panic() }
}

///|
test "PKL-105: path-keyed renderer converter rewrites a top-level value" {
  guard eval_source(
      "count = 5\noutput { renderer = new JsonRenderer { converters { [\"count\"] = (v) -> v * 10 } } }",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut count_value = -1L
  for entry in members {
    if entry.name == "count" {
      match entry.value {
        IntValue(n) => count_value = n
        _ => ()
      }
    }
  }
  inspect(count_value, content="50")
}

///|
test "PKL-121: Float magnitude Duration literal parses" {
  guard eval_source("x = 1.5.s") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is DurationValue(d, unit) else { panic() }
  inspect(d, content="1.5")
  inspect(unit, content="s")
}

///|
test "PKL-121: Float magnitude DataSize literal parses" {
  guard eval_source("x = 2.5.gib") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is DataSizeValue(d, unit) else { panic() }
  inspect(d, content="2.5")
  inspect(unit, content="gib")
}

///|
test "PKL-121: Int magnitude unchanged after Double widening" {
  guard eval_source("a = 5.min\nb = 3.gib") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is DurationValue(d1, _) else { panic() }
  guard members[1].value is DataSizeValue(d2, _) else { panic() }
  inspect(d1, content="5")
  inspect(d2, content="3")
}

///|
test "PKL-103: read?(uri) returns null when env var is missing" {
  guard eval_source("x = read?(\"env:NONEXISTENT_PKL_TEST_VAR_QZQ\")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members[0].value == NullValue)
}

///|
test "PKL-103: read?(uri) returns null when scheme is rejected" {
  guard eval_source("x = read?(\"https://example.com/missing\")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members[0].value == NullValue)
}

///|
test "PKL-122: String.codePointCount counts code points not UTF-16 units" {
  guard eval_source("s = \"abc🍣\"\nu = s.length\nc = s.codePointCount")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut u = 0L
  let mut c = 0L
  for entry in members {
    if entry.name == "u" {
      guard entry.value is IntValue(n) else { panic() }
      u = n
    }
    if entry.name == "c" {
      guard entry.value is IntValue(n) else { panic() }
      c = n
    }
  }
  inspect(u, content="5")
  inspect(c, content="4")
}

///|
test "PKL-122: String.codePoints surfaces full code points" {
  guard eval_source("s = \"a🍣\"\nx = s.codePoints")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is ListingValue(points) else { panic() }
  inspect(points.length(), content="2")
  guard points[0] is IntValue(p0) else { panic() }
  guard points[1] is IntValue(p1) else { panic() }
  inspect(p0, content="97")
  inspect(p1, content="127843")
}

///|
test "PKL-122: String.chars yields surrogate-pair-aware single-char Strings" {
  guard eval_source("s = \"a🍣b\"\nx = s.chars")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is ListingValue(chars) else { panic() }
  inspect(chars.length(), content="3")
  guard chars[1] is StringValue(sushi) else { panic() }
  inspect(sushi, content="🍣")
}

///|
test "PKL-122: String.codePointAt indexes the code-point stream" {
  guard eval_source("s = \"abc🍣d\"\nx = s.codePointAt(3)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[1].value is IntValue(cp) else { panic() }
  inspect(cp, content="127843")
}

///|
test "PKL-122: String.codePointAt out of range pushes diagnostic" {
  guard eval_source("s = \"a\"\nx = s.codePointAt(5)") is EvalError(diags) else {
    panic()
  }
  let mut found = false
  for d in diags {
    if d.message.contains("out of range") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "PKL-128d: paren-body annotation captures verbatim body text" {
  let parsed = parse_source(
    "@Deprecated(\"removed in v3\")\nclass Box { value: Int }",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(decl) else {
    panic()
  }
  inspect(decl.annotations.length(), content="1")
  inspect(decl.annotations[0].class_name, content="Deprecated")
  guard decl.annotations[0].body_kind is ParenBody else { panic() }
  inspect(decl.annotations[0].body_text, content="\"removed in v3\"")
}

///|
test "PKL-128d: brace-body annotation captures verbatim body text" {
  let parsed = parse_source(
    "@ModuleInfo { minPklVersion = \"0.31.0\" }\nmodule foo.bar",
  )
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.program.module_annotations.length(), content="1")
  let a = parsed.program.module_annotations[0]
  inspect(a.class_name, content="ModuleInfo")
  guard a.body_kind is BraceBody else { panic() }
  inspect(a.body_text, content=" minPklVersion = \"0.31.0\" ")
}

///|
test "PKL-128d: bare annotation has no body" {
  let parsed = parse_source("@Internal\nfunction helper(x: Int): Int = x * 2")
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is FunctionDeclaration(decl) else {
    panic()
  }
  inspect(decl.annotations.length(), content="1")
  inspect(decl.annotations[0].class_name, content="Internal")
  guard decl.annotations[0].body_kind is NoBody else { panic() }
  inspect(decl.annotations[0].body_text, content="")
}

///|
test "PKL-128d: multiple annotations stack on a single declaration" {
  let parsed = parse_source(
    "@Deprecated(\"old\")\n@Since(\"0.5.0\")\nclass Box { value: Int }",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(decl) else {
    panic()
  }
  inspect(decl.annotations.length(), content="2")
  inspect(decl.annotations[0].class_name, content="Deprecated")
  inspect(decl.annotations[1].class_name, content="Since")
}

///|
test "PKL-153: class property annotations are captured in source order" {
  let parsed = parse_source(
    "class Box {\n  @First\n  @Second { value = 1 }\n  item: Int = 1\n}",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(decl) else {
    panic()
  }
  inspect(decl.properties[0].annotations.length(), content="2")
  inspect(decl.properties[0].annotations[0].class_name, content="First")
  inspect(decl.properties[0].annotations[1].class_name, content="Second")
}

///|
test "PKL-153: ConvertProperty annotations transform rendered class properties" {
  let source =
    #|class Twice extends ConvertProperty {
    #|  render = (prop, _) -> Pair(prop.key, prop.value as Number * 2)
    #|}
    #|class Box {
    #|  @Twice
    #|  count: Int = 4
    #|}
    #|output {
    #|  value = new Box {}
    #|  renderer = new PcfRenderer {}
    #|}
  guard eval_source(source) is EvalOk(ObjectValue(members)) else { panic() }
  let mut output_value : Value? = None
  for m in members {
    if m.name == "output" {
      output_value = Some(m.value)
    }
  }
  guard output_value is Some(ObjectValue(output_members)) else { panic() }
  let mut projected_value : Value? = None
  for m in output_members {
    if m.name == "value" {
      projected_value = Some(m.value)
    }
  }
  guard projected_value is Some(ObjectValue(value_members)) else { panic() }
  inspect(render_value(ObjectValue(value_members)), content="count = 8")
}

///|
test "PKL-153: ConvertProperty render method is callable on annotation instance" {
  let source =
    #|class MultiplyValue extends ConvertProperty {
    #|  factor: Number
    #|  render = (prop, _) -> Pair(prop.key, prop.value as Number * factor)
    #|}
    #|m = new MultiplyValue { factor = 2 }
    #|x = m.render(Pair("k", 4), new PcfRenderer {}).second
  guard eval_source(source) is EvalOk(ObjectValue(members)) else { panic() }
  let mut x : Value? = None
  for entry in members {
    if entry.name == "x" {
      x = Some(entry.value)
    }
  }
  guard x is Some(IntValue(result)) else { panic() }
  inspect(result, content="8")
}

///|
test "PKL-153: PcfRenderer renders RenderDirective text raw" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "bar = new RenderDirective { text = \"= \\\"b\\\" // bar\" }",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let mut class_tag = ""
  guard value is ObjectValue(members) else { panic() }
  for entry in members {
    if entry.name == "bar" {
      guard entry.value is ObjectValue(bar_members) else { panic() }
      for bar_entry in bar_members {
        if bar_entry.name == "@hidden$__class" {
          guard bar_entry.value is StringValue(tag) else { panic() }
          class_tag = tag
        }
      }
    }
  }
  inspect(class_tag, content="RenderDirective")
  inspect(render_value(value), content="bar = \"b\" // bar")
}

///|
test "PKL-128d: annotations don't bleed across consecutive declarations" {
  let parsed = parse_source("@First\nclass A { v: Int }\nclass B { v: Int }")
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(first) else {
    panic()
  }
  guard parsed.program.declarations[1] is ClassDeclaration(second) else {
    panic()
  }
  inspect(first.annotations.length(), content="1")
  inspect(first.annotations[0].class_name, content="First")
  inspect(second.annotations.length(), content="0")
}

///|
test "PKL-128d: typealias annotation captures" {
  let parsed = parse_source("@Internal\ntypealias Alias = Int")
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is TypeAliasDeclaration(decl) else {
    panic()
  }
  inspect(decl.annotations.length(), content="1")
  inspect(decl.annotations[0].class_name, content="Internal")
}

///|
test "PKL-102: unused local binding surfaces lint finding" {
  let parsed = parse_source("local foo: Int = 1\nbar: Int = 2")
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="1")
  inspect(findings[0].rule, content="unused-local-binding")
  inspect(
    findings[0].message,
    content="local binding `foo` is never referenced",
  )
}

///|
test "PKL-102: referenced local binding is not flagged" {
  let parsed = parse_source("local foo: Int = 1\nbar: Int = foo + 2")
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="0")
}

///|
test "PKL-102: unused import surfaces lint finding" {
  let parsed = parse_source("import \"other.pkl\" as Other\nbar: Int = 1")
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="1")
  inspect(findings[0].rule, content="unused-import")
}

///|
test "PKL-102: referenced import is not flagged" {
  let parsed = parse_source(
    "import \"other.pkl\" as Other\nbar: Int = Other.value",
  )
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="0")
}

///|
test "PKL-102: shadowed binding name surfaces lint finding" {
  let parsed = parse_source(
    "import \"other.pkl\" as Other\nlocal Other: Int = 1\nbar: Int = Other",
  )
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="1")
  inspect(findings[0].rule, content="shadowed-identifier")
  inspect(
    findings[0].message,
    content="binding `Other` shadows existing import of the same name",
  )
}

///|
test "PKL-102: unused property of unreferenced class flagged" {
  let parsed = parse_source(
    "class Helper { temp: Int = 1; used: Int = 2; computed: Int = used + 1 }",
  )
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="2")
  let rules = findings.iter().map(fn(f) { f.rule }).collect()
  inspect(rules[0], content="unused-class-property")
  inspect(rules[1], content="unused-class-property")
}

///|
test "PKL-102: properties of referenced class skipped" {
  let parsed = parse_source(
    "class Helper { value: Int = 1 }\nout: Helper = new Helper { value = 5 }",
  )
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="0")
}

///|
test "PKL-102: import referenced via generic type annotation counts" {
  let parsed = parse_source(
    "import \"other.pkl\" as Other\nlist: Listing<Other> = new {}",
  )
  let findings = lint_program(parsed.program)
  inspect(findings.length(), content="0")
}

///|
test "PKL-106: read prop returns configured value" {
  configure_sandbox_props({ "API_KEY": "secret123" })
  let result = eval_source("api_key = read(\"prop:API_KEY\")")
  guard result is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|api_key = "secret123"
    ),
  )
  configure_sandbox_props(Map([], capacity=8))
}

///|
