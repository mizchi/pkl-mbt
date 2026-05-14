///|
test "parse source builds a CST-backed program" {
  let parsed = parse_source("1 + 2 * 3")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(kind_name(parsed.root.kind()), content="module")
  inspect(parsed.root.text_len().to_int(), content="9")
}

///|
test "evaluate integer arithmetic with precedence" {
  assert_true(eval_source("1 + 2 * 3") == EvalOk(IntValue(7)))
}

///|
test "evaluate let binding" {
  assert_true(eval_source("let x = 41\nx + 1") == EvalOk(IntValue(42)))
}

///|
test "typecheck rejects invalid integer operation" {
  guard typecheck_source("1 + true") is TypeError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
}

///|
test "analysis session caches source-backed typechecking through ripple" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "let x = 1\nx + 2")
  assert_true(session.typecheck_path("main.pkl") == TypeOk(IntType))
  session.set_source("main.pkl", "let x = true\nx + 2")
  guard session.typecheck_path("main.pkl") is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
}

///|
test "parse module header and top-level properties" {
  let parsed = parse_source("module demo\nname = \"hawk\"\nage = 2")
  inspect(parsed.diagnostics.length(), content="0")
  assert_true(parsed.program.module_name == Some("demo"))
  inspect(parsed.program.bindings.length(), content="2")
}

///|
test "evaluate object literal from top-level module properties" {
  assert_true(
    eval_source("module demo\nname = \"hawk\"\nage = 2") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "name", value: StringValue("hawk") },
        ValueMember::{ name: "age", value: IntValue(2) },
      ]),
    ),
  )
}

///|
test "evaluate object member lookup" {
  assert_true(
    eval_source("let bird = new { name = \"hawk\" }\nbird.name") ==
    EvalOk(StringValue("hawk")),
  )
}

///|
test "typecheck object member lookup" {
  assert_true(
    typecheck_source("let bird = new { age = 2 }\nbird.age") == TypeOk(IntType),
  )
}

///|
test "analysis session resolves import clauses for typechecking and evaluation" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "name = \"hawk\"\nage = 2")
  session.set_source("main.pkl", "import \"base.pkl\" as base\nbase.name")
  assert_true(session.typecheck_path("main.pkl") == TypeOk(StringType))
  assert_true(session.eval_path("main.pkl") == EvalOk(StringValue("hawk")))
}

///|
test "analysis session resolves selected pkl standard library modules" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "import \"pkl:math\" as math\nmath.maxInt32")
  assert_true(session.typecheck_path("main.pkl") == TypeOk(IntType))
  assert_true(session.eval_path("main.pkl") == EvalOk(IntValue(2147483647)))
}

///|
test "typecheck accepts matching Pkl property annotations" {
  guard typecheck_source("name: String = \"hawk\"")
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  assert_true(fields[0].typ == StringType)
}

///|
test "typecheck rejects mismatched Pkl property annotations" {
  guard typecheck_source("name: Int = \"hawk\"") is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation Int does not accept String",
  )
}

///|
test "evaluate common string escapes" {
  assert_true(
    eval_source("\"hawk\\nmoon\"") == EvalOk(StringValue("hawk\nmoon")),
  )
  assert_true(
    eval_source("\"say \\\"hi\\\"\"") == EvalOk(StringValue("say \"hi\"")),
  )
}

///|
test "render string escapes for CLI output" {
  inspect(render_value(StringValue("hawk\nmoon")), content="\"hawk\\nmoon\"")
}

///|
test "parser treats Pkl comments as trivia" {
  let parsed = parse_source(
    "// leading\nname = \"hawk\" // trailing\nage = 2 /* block */\n",
  )
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.program.bindings.length(), content="2")
}

///|
test "evaluate top-level properties with forward references" {
  assert_true(
    eval_source("foo = bar * 2\nbar = 3") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "foo", value: IntValue(6) },
        ValueMember::{ name: "bar", value: IntValue(3) },
      ]),
    ),
  )
}

///|
test "typecheck top-level properties with forward references" {
  guard typecheck_source("foo = bar * 2\nbar = 3") is TypeOk(ObjectType(fields)) else {
    panic()
  }
  assert_true(fields[0].typ == IntType)
  assert_true(fields[1].typ == IntType)
}

///|
test "parse and evaluate Pkl object body property shorthand" {
  assert_true(
    eval_source("x { y { z = 1 } }") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "x",
          value: ObjectValue([
            ValueMember::{
              name: "y",
              value: ObjectValue([
                ValueMember::{ name: "z", value: IntValue(1) },
              ]),
            },
          ]),
        },
      ]),
    ),
  )
}

///|
test "typecheck Pkl object body property shorthand" {
  guard typecheck_source("x { y { z = 1 } }") is TypeOk(ObjectType(fields)) else {
    panic()
  }
  guard fields[0].typ is ObjectType(nested) else { panic() }
  guard nested[0].typ is ObjectType(inner) else { panic() }
  assert_true(inner[0].typ == IntType)
}

///|
test "evaluate Pkl local module bindings without exporting them" {
  assert_true(
    eval_source("local base = 2\nvalue = base + 1") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
}

///|
test "analysis session resolves import expressions" {
  let session = AnalysisSession::new()
  session.set_source("imported.pkl", "foo = bar * 2\nbar = 3")
  session.set_source(
    "main.pkl", "local i = import(\"imported.pkl\")\nlibFoo = i.foo\nlibBar = i.bar",
  )
  assert_true(
    session.typecheck_path("main.pkl") ==
    TypeOk(
      ObjectType([
        TypeMember::{ name: "libFoo", typ: IntType },
        TypeMember::{ name: "libBar", typ: IntType },
      ]),
    ),
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "libFoo", value: IntValue(6) },
        ValueMember::{ name: "libBar", value: IntValue(3) },
      ]),
    ),
  )
}

///|
test "evaluate Pkl Listing literal and index access" {
  assert_true(
    eval_source("let xs = new Listing { 1; 2; 3 }\nxs[1]") ==
    EvalOk(IntValue(2)),
  )
  assert_true(
    eval_source("numbers = new Listing { 1; 2 }") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "numbers",
          value: ListingValue([IntValue(1), IntValue(2)]),
        },
      ]),
    ),
  )
}

///|
test "evaluate Pkl Mapping entries and key access" {
  assert_true(
    eval_source(
      "let habitats = new Mapping { [\"hawk\"] = \"forest\"; [\"owl\"] = \"night\" }\nhabitats[\"owl\"]",
    ) ==
    EvalOk(StringValue("night")),
  )
}

///|
test "typecheck Pkl collection subscript access" {
  assert_true(
    typecheck_source("let xs = new Listing { 1; 2; 3 }\nxs[0]") ==
    TypeOk(IntType),
  )
  assert_true(
    typecheck_source(
      "let habitats = new Mapping { [\"hawk\"] = \"forest\" }\nhabitats[\"hawk\"]",
    ) ==
    TypeOk(StringType),
  )
}

///|
test "parser reports unsupported syntax inventory" {
  let parsed = parse_source("value = max(1, 2)\nother = 1")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.unsupported_syntax.length(), content="1")
  let item = parsed.unsupported_syntax[0]
  inspect(item.start, content="8")
  inspect(item.end, content="17")
  inspect(item.text, content="max(1, 2)")
  inspect(item.kind, content="unsupported_expr")

  let supported = parse_source("let xs = new Listing { 1; 2 }\nxs[0]")
  inspect(supported.unsupported_syntax.length(), content="0")
}

///|
test "parse Pkl class function and typealias declarations" {
  let parsed = parse_source(
    "class Bird { name: String }\ntypealias Label = String\nfunction identity(x) = x\nbird: Bird = new { name = \"hawk\" }\nlabel: Label = \"raptor\"",
  )
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.program.declarations.length(), content="3")
  guard parsed.program.declarations[0] is ClassDeclaration(class_decl) else {
    panic()
  }
  inspect(class_decl.name, content="Bird")
  inspect(class_decl.properties[0].name, content="name")
  assert_true(class_decl.properties[0].type_name == Some("String"))
  guard parsed.program.declarations[1] is TypeAliasDeclaration(type_alias) else {
    panic()
  }
  inspect(type_alias.name, content="Label")
  inspect(type_alias.target, content="String")
  guard parsed.program.declarations[2] is FunctionDeclaration(function_decl) else {
    panic()
  }
  inspect(function_decl.name, content="identity")
  inspect(function_decl.parameters.length(), content="1")
  assert_true(function_decl.body == Some(Identifier("x")))
}

///|
test "typecheck resolves declared class and typealias annotations" {
  guard typecheck_source(
      "class Bird { name: String }\ntypealias Label = String\nbird: Bird = new { name = \"hawk\" }\nlabel: Label = \"raptor\"",
    )
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Bird")
  assert_true(fields[1].typ == StringType)

  guard typecheck_source(
      "class Bird { name: String }\nbird: Bird = new { age = 2 }",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation Bird missing member name",
  )
}
