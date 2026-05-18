///|
test "support multiple Pkl type constraint predicates" {
  assert_true(
    typecheck_source("value: Int(isPositive, isLessThan(10)) = 3") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source("value: Int(isPositive, isLessThan(10)) = 10")
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `isLessThan(10)` violated. Value: 10
    ),
  )
  guard eval_source("value: Int(isPositive, isBetween(1, 10)) = 0")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="Type constraint `isPositive` violated. Value: 0",
  )
}

///|
test "support negated Pkl type constraint predicates" {
  assert_true(
    typecheck_source("value: Int(!isPositive) = 0") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source("value: Int(!isPositive) = 1")
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content="Type constraint `!isPositive` violated. Value: 1",
  )
  guard eval_source("value: Int(!isLessThan(10)) = 9")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `!isLessThan(10)` violated. Value: 9
    ),
  )
}

///|
test "evaluate Pkl user-defined type constraint functions" {
  assert_true(
    typecheck_source(
      "function above(n) = (x) -> x > n\nvalue: Int(above(5)) = 6",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function above(n) = (x) -> x > n\ntypealias Above5 = Int(above(5))\nvalue: Above5 = 6",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "function above(n) = (x) -> x > n\nvalue: Int(above(5)) = 5",
    )
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
  guard typecheck_source(
      "function above(n) = (x) -> x > n\ntypealias Above5 = Int(above(5))\nvalue: Above5 = 5",
    )
    is TypeError(alias_type_diagnostics) else {
    panic()
  }
  inspect(
    alias_type_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
  guard eval_source(
      "function above(n) = (x) -> x > n\nvalue: Int(above(5)) = 5",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
  guard eval_source(
      "function above(n) = (x) -> x > n\ntypealias Above5 = Int(above(5))\nvalue: Above5 = 5",
    )
    is EvalError(alias_eval_diagnostics) else {
    panic()
  }
  inspect(
    alias_eval_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
}

///|
test "evaluate and typecheck Pkl constrained type annotation predicates" {
  assert_true(
    typecheck_source("value: Int(isBetween(0, 10)) = 3") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source("value: Int(isBetween(0, 10)) = 11")
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  assert_true(
    eval_source("value: Int(isBetween(0, 10)) = 3") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3), source: None }])),
  )
  guard eval_source("value: Int(this.isBetween(0, 10)) = 11")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source("value = new { n: Int(isBetween(0, 10)) = 11 }")
    is TypeError(member_type_diagnostics) else {
    panic()
  }
  inspect(
    member_type_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard eval_source("value = new { n: Int(isBetween(0, 10)) = 11 }")
    is EvalError(member_eval_diagnostics) else {
    panic()
  }
  inspect(
    member_eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck Pkl nullable annotations" {
  let parsed = parse_source("name: String? = null")
  assert_true(parsed.program.bindings[0].type_name == Some("String?"))

  assert_true(
    typecheck_source("name: String? = null\nother: String? = \"hawk\"") ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "name", typ: NullableType(StringType) },
        TypeMember::{ name: "other", typ: NullableType(StringType) },
      ]),
    ),
  )
  guard typecheck_source("name: String? = 1") is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation String? does not accept Int",
  )
  assert_true(
    typecheck_source(
      "function label(x: String?): String = x ?? \"none\"\nvalue = label(null)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: StringType }])),
  )
}

///|
test "typecheck Pkl generic collection annotations" {
  let parsed = parse_source(
    "numbers: Listing<Int> = new Listing { 1; 2 }\nhabitats: Mapping<String, String> = new Mapping { [\"hawk\"] = \"forest\" }",
  )
  assert_true(parsed.program.bindings[0].type_name == Some("Listing<Int>"))
  assert_true(
    parsed.program.bindings[1].type_name == Some("Mapping<String,String>"),
  )

  assert_true(
    typecheck_source(
      "numbers: Listing<Int> = new Listing { 1; 2 }\nhabitats: Mapping<String, String> = new Mapping { [\"hawk\"] = \"forest\" }",
    ) ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "numbers", typ: ListingType([IntType]) },
        TypeMember::{
          name: "habitats",
          typ: MappingType([TypeEntry::{ key: StringType, value: StringType }]),
        },
      ]),
    ),
  )

  guard typecheck_source("numbers: Listing<Int> = new Listing { 1; \"two\" }")
    is TypeError(listing_diagnostics) else {
    panic()
  }
  inspect(
    listing_diagnostics[0].message,
    content="type annotation Listing<Int> does not accept Listing",
  )

  guard typecheck_source(
      "habitats: Mapping<String, String> = new Mapping { [\"hawk\"] = 1 }",
    )
    is TypeError(mapping_diagnostics) else {
    panic()
  }
  inspect(
    mapping_diagnostics[0].message,
    content="type annotation Mapping<String,String> does not accept Mapping",
  )
}

///|
test "typecheck Pkl rich typealias annotations" {
  let parsed = parse_source(
    "typealias MaybeName = String?\ntypealias Names = Listing<String>\ntypealias HabitatMap = Mapping<String, String>",
  )
  guard parsed.program.declarations[0] is TypeAliasDeclaration(maybe_name) else {
    panic()
  }
  inspect(maybe_name.target, content="String?")
  guard parsed.program.declarations[1] is TypeAliasDeclaration(names) else {
    panic()
  }
  inspect(names.target, content="Listing<String>")
  guard parsed.program.declarations[2] is TypeAliasDeclaration(habitat_map) else {
    panic()
  }
  inspect(habitat_map.target, content="Mapping<String,String>")

  assert_true(
    typecheck_source(
      "typealias MaybeName = String?\ntypealias Names = Listing<String>\nname: MaybeName = null\nnames: Names = new Listing { \"hawk\" }",
    ) ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "name", typ: NullableType(StringType) },
        TypeMember::{ name: "names", typ: ListingType([StringType]) },
      ]),
    ),
  )

  guard typecheck_source(
      "typealias Names = Listing<String>\nnames: Names = new Listing { 1 }",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation Names does not accept Listing",
  )
}

///|
test "typecheck Pkl union type annotations" {
  let parsed = parse_source(
    "value: String | Int = \"hawk\"\nitems: Listing<String | Int> = new Listing { \"hawk\"; 1 }",
  )
  assert_true(parsed.program.bindings[0].type_name == Some("String|Int"))
  assert_true(
    parsed.program.bindings[1].type_name == Some("Listing<String|Int>"),
  )

  assert_true(
    typecheck_source("name: String | Int = \"hawk\"\nage: String | Int = 1") ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "name", typ: UnionType([StringType, IntType]) },
        TypeMember::{ name: "age", typ: UnionType([StringType, IntType]) },
      ]),
    ),
  )
  assert_true(
    typecheck_source(
      "items: Listing<String | Int> = new Listing { \"hawk\"; 1 }",
    ) ==
    TypeOk(
      ObjectType([
        TypeMember::{
          name: "items",
          typ: ListingType([UnionType([StringType, IntType])]),
        },
      ]),
    ),
  )
  assert_true(
    typecheck_source(
      "function identity(x: String | Int): String | Int = x\nvalue = identity(1)",
    ) ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "value", typ: UnionType([StringType, IntType]) },
      ]),
    ),
  )
  assert_true(
    typecheck_source("value = if (true) \"hawk\" else 1") ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "value", typ: UnionType([StringType, IntType]) },
      ]),
    ),
  )

  guard typecheck_source("value: String | Int = true") is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation String|Int does not accept Boolean",
  )
}

///|
test "typecheck Pkl rich is and as type operands" {
  let parsed = parse_source(
    "value = 1 as String | Int\nok = value is Listing<String | Int>",
  )
  guard parsed.program.bindings[0].value
    is BinaryExpr(As, _, Identifier(cast_type)) else {
    panic()
  }
  inspect(cast_type, content="String|Int")
  guard parsed.program.bindings[1].value
    is BinaryExpr(Is, _, Identifier(test_type)) else {
    panic()
  }
  inspect(test_type, content="Listing<String|Int>")

  assert_true(
    typecheck_source("value = 1 as String | Int") ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "value", typ: UnionType([StringType, IntType]) },
      ]),
    ),
  )
  assert_true(
    typecheck_source("ok = new Listing { 1 } is Listing<String | Int>") ==
    TypeOk(ObjectType([TypeMember::{ name: "ok", typ: BoolType }])),
  )

  guard typecheck_source("ok = 1 is Missing") is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="Cannot find type `Missing`.")
}

///|
test "typecheck Pkl is guards narrow union types" {
  assert_true(
    typecheck_source(
      "function plusOne(x: String | Int): Int = if (x is Int) x + 1 else 0\nvalue = plusOne(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function plusOne(x: String | Int): Int = if (x is String) 0 else x + 1\nvalue = plusOne(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "local input: String | Int = 1\nvalue: Int = if (input is Int) input + 1 else 0",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )

  guard typecheck_source(
      "function bad(x: String | Boolean): Int = if (x is String) 0 else x + 1\nvalue = bad(true)",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
}

///|
test "typecheck Pkl compound is guards narrow union types" {
  let parsed = parse_source("ok = x is Int && x > 0")
  guard parsed.program.bindings[0].value
    is BinaryExpr(
      And,
      BinaryExpr(Is, Identifier("x"), Identifier(type_name)),
      _
    ) else {
    panic()
  }
  inspect(type_name, content="Int")

  assert_true(
    typecheck_source(
      "function plusPositive(x: String | Int): Int = if (x is Int && x > 0) x + 1 else 0\nvalue = plusPositive(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function addInts(x: String | Int, y: String | Int): Int = if (x is Int && y is Int) x + y else 0\nvalue = addInts(1, 2)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "local input: String | Int = 1\nok = input is Int && input > 0",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "ok", typ: BoolType }])),
  )
}

///|
test "typecheck Pkl null guards narrow nullable types" {
  assert_true(
    typecheck_source(
      "function inc(x: Int?): Int = if (x != null) x + 1 else 0\nvalue = inc(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function inc(x: Int?): Int = if (x == null) 0 else x + 1\nvalue = inc(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function positive(x: Int?): Boolean = x != null && x > 0\nvalue = positive(1)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: BoolType }])),
  )
  assert_true(
    typecheck_source(
      "local input: Int? = 1\nvalue: Int = if (input != null) input + 1 else 0",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )

  guard typecheck_source(
      "function bad(x: String?): Int = if (x != null) x + 1 else 0\nvalue = bad(\"hawk\")",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
}

///|
test "typecheck Pkl nullable postfix operators" {
  let parsed = parse_source(
    "name: String? = \"hawk\"\nvalue = name!!\nbird: Bird? = new { name = \"hawk\" }\nlabel = bird?.name",
  )
  assert_true(
    parsed.program.bindings[1].value == NonNullExpr(Identifier("name")),
  )
  assert_true(
    parsed.program.bindings[3].value ==
    SafeMemberAccess(Identifier("bird"), "name"),
  )

  assert_true(
    typecheck_source("local name: String? = \"hawk\"\nvalue: String = name!!") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: StringType }])),
  )
  assert_true(
    typecheck_source(
      "class Bird { name: String }\nlocal bird: Bird? = new { name = \"hawk\" }\nlabel: String? = bird?.name",
    ) ==
    TypeOk(
      ObjectType([TypeMember::{ name: "label", typ: NullableType(StringType) }]),
    ),
  )
  assert_true(
    typecheck_source(
      "class Bird { name: String }\nlocal bird: Bird = new { name = \"hawk\" }\nlabel: String = bird?.name\nvalue: Int = 1!!",
    ) ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "label", typ: StringType },
        TypeMember::{ name: "value", typ: IntType },
      ]),
    ),
  )

  guard typecheck_source("value = null!!") is TypeError(non_null_diagnostics) else {
    panic()
  }
  inspect(
    non_null_diagnostics[0].message,
    content="non-null assertion rejects Null",
  )

  guard typecheck_source("value = 1?.name")
    is TypeError(safe_member_diagnostics) else {
    panic()
  }
  inspect(
    safe_member_diagnostics[0].message,
    content="safe member access expects Object",
  )
}

///|
test "typecheck Pkl null-safe invocation chains" {
  let parsed = parse_source("value = box?.f(1)")
  assert_true(
    parsed.program.bindings[0].value ==
    CallExpr(SafeMemberAccess(Identifier("box"), "f"), [IntLiteral(1)]),
  )

  assert_true(
    typecheck_source(
      "local box: Object? = new { f = (x: Int): Int -> x + 1 }\nvalue: Int? = box?.f(1)",
    ) ==
    TypeOk(
      ObjectType([TypeMember::{ name: "value", typ: NullableType(IntType) }]),
    ),
  )
  assert_true(
    typecheck_source("value = null?.f()") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: NullType }])),
  )
  assert_true(
    eval_source("value = null?.f()") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: NullValue, source: None }])),
  )

  guard typecheck_source(
      "local box: Object? = new { f = (x: Int): Int -> x + 1 }\nvalue = box?.f(true)",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="method f argument 1 expects Int, got Boolean",
  )
}

///|
test "evaluate and typecheck Pkl object amendments" {
  let source = "base = new { name = \"hawk\"; age = 2 }\nbird = (base) { age = 3; wing = \"wide\" }"
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "base",
          value: ObjectValue([
            ValueMember::{ name: "name", value: StringValue("hawk"), source: None },
            ValueMember::{ name: "age", value: IntValue(2), source: None },
          ]), source: None
        },
        ValueMember::{
          name: "bird",
          value: ObjectValue([
            ValueMember::{ name: "name", value: StringValue("hawk"), source: None },
            ValueMember::{ name: "age", value: IntValue(3), source: None },
            ValueMember::{ name: "wing", value: StringValue("wide"), source: None },
          ]), source: None
        },
      ]),
    ),
  )
  guard typecheck_source(source) is TypeOk(ObjectType(fields)) else { panic() }
  guard fields[1].typ is ObjectType(bird_fields) else { panic() }
  inspect(bird_fields[0].name, content="name")
  assert_true(bird_fields[0].typ == StringType)
  inspect(bird_fields[1].name, content="age")
  assert_true(bird_fields[1].typ == IntType)
  inspect(bird_fields[2].name, content="wing")
  assert_true(bird_fields[2].typ == StringType)
}

///|
test "analysis session resolves module amends and extends" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "name = \"hawk\"\nage = 2")
  session.set_source("amended.pkl", "amends \"base.pkl\"\nage = 3")
  session.set_source("extended.pkl", "extends \"base.pkl\"\nwing = \"wide\"")

  assert_true(
    session.eval_path("amended.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "name", value: StringValue("hawk"), source: None },
        ValueMember::{ name: "age", value: IntValue(3), source: None },
      ]),
    ),
  )
  assert_true(
    session.eval_path("extended.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "name", value: StringValue("hawk"), source: None },
        ValueMember::{ name: "age", value: IntValue(2), source: None },
        ValueMember::{ name: "wing", value: StringValue("wide"), source: None },
      ]),
    ),
  )
  guard session.typecheck_path("extended.pkl") is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(fields.length(), content="3")
  assert_true(fields[0].typ == StringType)
  assert_true(fields[1].typ == IntType)
  assert_true(fields[2].typ == StringType)
}

///|
test "construct Pkl Duration literals from Int magnitudes" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 1.ns\nb = 2.us\nc = 3.ms\nd = 4.s\ne = 5.min\nf = 6.h\ng = 7.d",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DurationValue(1, "ns"), source: None },
        ValueMember::{ name: "b", value: DurationValue(2, "us"), source: None },
        ValueMember::{ name: "c", value: DurationValue(3, "ms"), source: None },
        ValueMember::{ name: "d", value: DurationValue(4, "s"), source: None },
        ValueMember::{ name: "e", value: DurationValue(5, "min"), source: None },
        ValueMember::{ name: "f", value: DurationValue(6, "h"), source: None },
        ValueMember::{ name: "g", value: DurationValue(7, "d"), source: None },
      ]),
    ),
  )
}

///|
test "construct Pkl DataSize literals from Int magnitudes" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 1.b\nb = 2.kb\nc = 3.kib\nd = 4.mb\ne = 5.mib\nf = 6.gb\ng = 7.gib\nh = 8.tb\ni = 9.tib\nj = 10.pb\nk = 11.pib",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DataSizeValue(1, "b"), source: None },
        ValueMember::{ name: "b", value: DataSizeValue(2, "kb"), source: None },
        ValueMember::{ name: "c", value: DataSizeValue(3, "kib"), source: None },
        ValueMember::{ name: "d", value: DataSizeValue(4, "mb"), source: None },
        ValueMember::{ name: "e", value: DataSizeValue(5, "mib"), source: None },
        ValueMember::{ name: "f", value: DataSizeValue(6, "gb"), source: None },
        ValueMember::{ name: "g", value: DataSizeValue(7, "gib"), source: None },
        ValueMember::{ name: "h", value: DataSizeValue(8, "tb"), source: None },
        ValueMember::{ name: "i", value: DataSizeValue(9, "tib"), source: None },
        ValueMember::{ name: "j", value: DataSizeValue(10, "pb"), source: None },
        ValueMember::{ name: "k", value: DataSizeValue(11, "pib"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Duration addition keeps the larger unit when units match" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "a = 2.s + 4.s")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "a", value: DurationValue(6, "s"), source: None }]),
    ),
  )
}

///|
test "Pkl Duration mixed-unit addition normalizes to the smaller unit" {
  let session = AnalysisSession::new()
  // `2.s + 3.min` chooses the smaller unit (`s`) so we can stay in Int.
  // The upstream evaluator would emit `3.033333.min` via Float; this slice
  // intentionally restricts to Int magnitudes (see Spec.pkl decisions).
  session.set_source("main.pkl", "a = 2.s + 3.min")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "a", value: DurationValue(182, "s"), source: None }]),
    ),
  )
}

///|
test "Pkl Duration subtraction works for same and mixed units" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "a = 5.s - 2.s\nb = 3.min - 30.s")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DurationValue(3, "s"), source: None },
        ValueMember::{ name: "b", value: DurationValue(150, "s"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Duration comparison normalizes to the base unit" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "lt = 1.min < 2.min\nle = 60.s <= 1.min\ngt = 1.h > 59.min\nge = 1.h >= 60.min\neq = 1000.ms == 1.s\nne = 1.s != 2.s",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "lt", value: BoolValue(true), source: None },
        ValueMember::{ name: "le", value: BoolValue(true), source: None },
        ValueMember::{ name: "gt", value: BoolValue(true), source: None },
        ValueMember::{ name: "ge", value: BoolValue(true), source: None },
        ValueMember::{ name: "eq", value: BoolValue(true), source: None },
        ValueMember::{ name: "ne", value: BoolValue(true), source: None },
      ]),
    ),
  )
}

///|
test "Pkl DataSize arithmetic and comparison normalize to the smaller unit" {
  // Mixed-unit DataSize ops pick the smaller of the two as the result
  // unit (e.g. `1.mb - 100.kb` settles in `kb`). Comparison routes through
  // the same normalization so the wider unit gets expanded into the
  // narrower. `kb` / `kib` are intentionally not mixed here because the
  // 1000 vs 1024 factor pair loses precision under integer arithmetic;
  // that gap is documented in the slice scope.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 2.kb + 3.kb\nb = 1.mb - 100.kb\nc = 1.mb > 100.kb\nd = 1024.b == 1.kib",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DataSizeValue(5, "kb"), source: None },
        ValueMember::{ name: "b", value: DataSizeValue(900, "kb"), source: None },
        ValueMember::{ name: "c", value: BoolValue(true), source: None },
        ValueMember::{ name: "d", value: BoolValue(true), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Duration unary negation flips the magnitude" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "a = -4.s\nb = -(2.min)")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DurationValue(-4, "s"), source: None },
        ValueMember::{ name: "b", value: DurationValue(-2, "min"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Duration value and unit accessors" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "v = 3.min.value\nu = 3.min.unit\nm = 2.kb.value\nun = 2.kb.unit",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "v", value: IntValue(3), source: None },
        ValueMember::{ name: "u", value: StringValue("min"), source: None },
        ValueMember::{ name: "m", value: IntValue(2), source: None },
        ValueMember::{ name: "un", value: StringValue("kb"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Duration toUnit normalizes to the requested unit" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 1.min.toUnit(\"s\")\nb = 1.h.toUnit(\"min\")\nc = 1.kib.toUnit(\"b\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: DurationValue(60, "s"), source: None },
        ValueMember::{ name: "b", value: DurationValue(60, "min"), source: None },
        ValueMember::{ name: "c", value: DataSizeValue(1024, "b"), source: None },
      ]),
    ),
  )
}

///|
test "render Pkl Duration and DataSize values as PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "wait", value: DurationValue(5, "min"), source: None },
    ValueMember::{ name: "size", value: DataSizeValue(3, "kib"), source: None },
    ValueMember::{ name: "neg", value: DurationValue(-2, "s"), source: None },
  ])
  inspect(
    render_value(value),
    content=(
      #|wait = 5.min
      #|size = 3.kib
      #|neg = -2.s
    ),
  )
}

///|
test "construct Pkl Regex values from a pattern string" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "a = Regex(\"a+\")\nb = Regex(\"^foo$\")")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: RegexValue("a+"), source: None },
        ValueMember::{ name: "b", value: RegexValue("^foo$"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Regex pattern property returns the source pattern" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "p = Regex(\"[0-9]+\").pattern")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "p", value: StringValue("[0-9]+"), source: None }]),
    ),
  )
}

///|
test "Pkl Regex matches checks the entire input" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = Regex(\"[0-9]+\").matches(\"123\")\nb = Regex(\"[0-9]+\").matches(\"abc123\")\nc = Regex(\"a.c\").matches(\"abc\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: BoolValue(true), source: None },
        ValueMember::{ name: "b", value: BoolValue(false), source: None },
        ValueMember::{ name: "c", value: BoolValue(true), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Regex find returns the first match or null" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = Regex(\"[0-9]+\").find(\"abc123def456\")\nb = Regex(\"x+\").find(\"abc\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: StringValue("123"), source: None },
        ValueMember::{ name: "b", value: NullValue, source: None },
      ]),
    ),
  )
}

///|
test "Pkl Regex findAll returns all non-overlapping matches" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = Regex(\"[0-9]+\").findAll(\"abc12de3f456\")\nb = Regex(\"x+\").findAll(\"abc\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "a",
          value: ListingValue([
            StringValue("12"),
            StringValue("3"),
            StringValue("456"),
          ]), source: None
        },
        ValueMember::{ name: "b", value: ListingValue([]), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Regex replace substitutes the first match" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = Regex(\"[0-9]+\").replace(\"abc12de3\", \"X\")\nb = Regex(\"x+\").replace(\"abc\", \"Y\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: StringValue("abcXde3"), source: None },
        ValueMember::{ name: "b", value: StringValue("abc"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Regex replaceAll substitutes every non-overlapping match" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = Regex(\"[0-9]+\").replaceAll(\"abc12de3f456\", \"X\")\nb = Regex(\"x+\").replaceAll(\"abc\", \"Y\")",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: StringValue("abcXdeXfX"), source: None },
        ValueMember::{ name: "b", value: StringValue("abc"), source: None },
      ]),
    ),
  )
}

///|
test "render Pkl Regex values as Regex(\"...\") PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "digits", value: RegexValue("[0-9]+"), source: None },
    ValueMember::{ name: "anchored", value: RegexValue("^foo$"), source: None },
  ])
  inspect(
    render_value(value),
    content=(
      #|digits = Regex("[0-9]+")
      #|anchored = Regex("^foo$")
    ),
  )
}

///|
test "Pkl String constraint length comparison accepts in-range values" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "name: String(length > 0) = \"hawk\"")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "name", value: StringValue("hawk"), source: None }]),
    ),
  )
}

///|
test "Pkl String constraint length comparison rejects out-of-range values" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "name: String(length > 0) = \"\"")
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("length") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl String constraint length.isBetween accepts and rejects" {
  let accepting = AnalysisSession::new()
  accepting.set_source(
    "main.pkl", "name: String(length.isBetween(1, 4)) = \"hi\"",
  )
  assert_true(
    accepting.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "name", value: StringValue("hi"), source: None }]),
    ),
  )
  let rejecting = AnalysisSession::new()
  rejecting.set_source(
    "main.pkl", "name: String(length.isBetween(1, 4)) = \"toolong\"",
  )
  match rejecting.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("isBetween") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl String constraint matches(Regex(...)) accepts and rejects" {
  let accepting = AnalysisSession::new()
  accepting.set_source(
    "main.pkl", "id: String(matches(Regex(\"[a-z]+\"))) = \"hawk\"",
  )
  assert_true(
    accepting.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "id", value: StringValue("hawk"), source: None }]),
    ),
  )
  let rejecting = AnalysisSession::new()
  rejecting.set_source(
    "main.pkl", "id: String(matches(Regex(\"[a-z]+\"))) = \"HAWK\"",
  )
  match rejecting.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("matches") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl String constraint length.isPositive rejects empty strings" {
  let rejecting = AnalysisSession::new()
  rejecting.set_source("main.pkl", "name: String(length.isPositive) = \"\"")
  match rejecting.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("isPositive") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl String constraint negated matches rejects matching values" {
  let rejecting = AnalysisSession::new()
  rejecting.set_source(
    "main.pkl", "id: String(!matches(Regex(\"[0-9]+\"))) = \"123\"",
  )
  match rejecting.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("!matches") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl Listing element constraint accepts a Listing of valid Ints" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "xs: Listing<Int(isPositive)> = new Listing { 1; 2; 3 }",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]), source: None
        },
      ]),
    ),
  )
}

///|
test "Pkl Listing element constraint rejects an element that fails the predicate" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "xs: Listing<Int(isPositive)> = new Listing { 1; -2; 3 }",
  )
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("isPositive") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl Listing element constraint propagates String predicates" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "names: Listing<String(length > 0)> = new Listing { \"hawk\"; \"\" }",
  )
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("length") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl Mapping element constraint validates entry values" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "scores: Mapping<String, Int(isBetween(0, 9))> = new Mapping { [\"a\"] = 3; [\"b\"] = 12 }",
  )
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("isBetween") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl Mapping element constraint validates entry keys" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "scores: Mapping<String(length > 0), Int> = new Mapping { [\"ok\"] = 3; [\"\"] = 4 }",
  )
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let mut found = false
      for d in diagnostics {
        if d.message.contains("length") && d.message.contains("violated") {
          found = true
        }
      }
      assert_true(found)
    }
    EvalOk(_) => assert_true(false)
  }
}

///|
test "Pkl Bytes constructor wraps a Listing of byte values" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "data = Bytes(new Listing { 65; 66; 67 })")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Bytes length and base64 properties" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "n = Bytes(new Listing { 65; 66; 67 }).length\nb = Bytes(new Listing { 65; 66; 67 }).base64",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "n", value: IntValue(3), source: None },
        ValueMember::{ name: "b", value: StringValue("QUJD"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl Bytes getOrNull returns the byte at an index or null" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "in_bound = Bytes(new Listing { 65; 66; 67 }).getOrNull(1)\nout_bound = Bytes(new Listing { 65; 66; 67 }).getOrNull(7)",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "in_bound", value: IntValue(66), source: None },
        ValueMember::{ name: "out_bound", value: NullValue, source: None },
      ]),
    ),
  )
}

///|
test "Pkl Bytes toList returns the underlying ints" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "xs = Bytes(new Listing { 1; 2; 3 }).toList()")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListValue([IntValue(1), IntValue(2), IntValue(3)]), source: None
        },
      ]),
    ),
  )
}

///|
test "Pkl Bytes.fromBase64 decodes a base64 string" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "data = Bytes.fromBase64(\"QUJD\")")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43"), source: None },
      ]),
    ),
  )
}

///|
test "Pkl String.toBytes encodes the string as UTF-8 bytes" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "data = \"ABC\".toBytes()")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43"), source: None },
      ]),
    ),
  )
}

///|
test "render Pkl Bytes values as Bytes(new Listing { ... }) PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43"), source: None },
  ])
  inspect(
    render_value(value),
    content=(
      #|data = Bytes(new Listing { 65; 66; 67 })
    ),
  )
}

///|
test "Pkl shebang preamble at module start is consumed as trivia (PKL-148p)" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "#!/usr/bin/env pkl eval\nfoo = 1\n")
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(ObjectValue([ValueMember::{ name: "foo", value: IntValue(1), source: None }])),
  )
}
