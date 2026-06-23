///|
test "Properties renderer escapes special characters in scalar values" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "tab",
      value: StringValue("a\tb"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "newline",
      value: StringValue("a\nb"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "cr",
      value: StringValue("a\rb"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "ff",
      value: StringValue("a\u{0C}b"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "backslash",
      value: StringValue("c:\\path"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "leadingspace",
      value: StringValue(" lead"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "bangs",
      value: StringValue("!hello#world"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "kvchars",
      value: StringValue("a:b=c"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|tab = a\tb
      #|newline = a\nb
      #|cr = a\rb
      #|ff = a\fb
      #|backslash = c\:\\path
      #|leadingspace = \ lead
      #|bangs = \!hello\#world
      #|kvchars = a\:b\=c
      #|
    ),
  )
}

///|
test "Properties renderer escapes special characters in keys" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "a b",
      value: IntValue(1),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "a=b",
      value: IntValue(2),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "a:b",
      value: IntValue(3),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "a!b",
      value: IntValue(4),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "a#b",
      value: IntValue(5),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "a\\b",
      value: IntValue(6),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|a\ b = 1
      #|a\=b = 2
      #|a\:b = 3
      #|a\!b = 4
      #|a\#b = 5
      #|a\\b = 6
      #|
    ),
  )
}

///|
test "Properties renderer drops empty composites without leaves" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "emptyObj",
      value: ObjectValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "emptyMap",
      value: MappingValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "emptyList",
      value: ListingValue([]),
      source: None,
      annotations: [],
    },
  ])
  // Empty Object/Mapping yield no key (no leaves to attach to); empty
  // Listing emits the inline `[]` form so the entry is preserved.
  inspect(
    render_value_as_properties(value),
    content=(
      #|name = pigeon
      #|emptyList = []
      #|
    ),
  )
}

///|
test "Properties rendered top-level Pkl matches the propertiesRenderer1 fixture shape" {
  // Apple Pkl's `pkl eval -f properties` on the upstream
  // `propertiesRenderer1.properties.pkl` produces the inner pigeon block;
  // our pipeline still renders the post-eval module directly, so the
  // `pigeon` prefix stays on the dotted keys.
  let source = "pigeon {\n  name = \"pigeon\"\n  age = 30\n}\n"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_properties(value),
    content=(
      #|pigeon.name = pigeon
      #|pigeon.age = 30
      #|
    ),
  )
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
        ValueMember::{
          name: "foo",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "bar",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
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
                ValueMember::{
                  name: "z",
                  value: IntValue(1),
                  source: None,
                  annotations: [],
                },
              ]),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
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
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
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
        ValueMember::{
          name: "libFoo",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "libBar",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
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
          source: None,
          annotations: [],
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
  let parsed = parse_source("value = (x, y)\nother = 1")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.unsupported_syntax.length(), content="1")
  let item = parsed.unsupported_syntax[0]
  inspect(item.start, content="8")
  inspect(item.end, content="14")
  inspect(item.text, content="(x, y)")
  inspect(item.kind, content="unsupported_expr")

  let supported = parse_source(
    "let xs = new Listing { 1; 2 }\nxs[0]\nmax(1, 2)",
  )
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
  inspect(function_decl.parameters[0].name, content="x")
  assert_true(function_decl.body == Some(Identifier("x")))
}

///|
test "parse Pkl const function declarations" {
  let source = "const function above(n) = (x) -> x > n\nvalue: Int(above(5)) = 6"
  let parsed = parse_source(source)
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.unsupported_syntax.length(), content="0")
  inspect(parsed.program.declarations.length(), content="1")
  guard parsed.program.declarations[0] is FunctionDeclaration(function_decl) else {
    panic()
  }
  inspect(function_decl.name, content="above")
  inspect(function_decl.parameters.length(), content="1")
  inspect(function_decl.parameters[0].name, content="n")
  assert_true(
    typecheck_source(source) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "parse and typecheck Pkl class method declarations" {
  let source = "class Bird { function label(prefix: String): String = prefix }\nbird = new Bird {}\nvalue = bird.label"
  let parsed = parse_source(source)
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(class_decl) else {
    panic()
  }
  inspect(class_decl.methods.length(), content="1")
  inspect(class_decl.methods[0].name, content="label")
  inspect(class_decl.methods[0].parameters.length(), content="1")
  inspect(class_decl.methods[0].parameters[0].name, content="prefix")
  assert_true(class_decl.methods[0].parameters[0].type_name == Some("String"))
  assert_true(class_decl.methods[0].return_type_name == Some("String"))

  guard typecheck_source(source) is TypeOk(ObjectType(fields)) else { panic() }
  assert_true(fields[1].typ == FunctionType([StringType], StringType))
  assert_true(
    eval_source(
      "class Bird { function label(): String = \"hawk\" }\nbird = new Bird {}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "bird",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "evaluate Pkl class method invocations" {
  let source = "class BaseCounter { base = 40\nfunction add(n: Int): Int = base + n }\nclass Counter extends BaseCounter {}\ncounter = new Counter {}\nvalue = counter.add(2)"
  guard typecheck_source(source) is TypeOk(ObjectType(fields)) else { panic() }
  assert_true(fields[1].typ == IntType)
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([
            ValueMember::{
              name: "base",
              value: IntValue(40),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "enforce Pkl constrained method parameter annotations" {
  let source = "class Counter { function add(n: Int(isBetween(0, 10))): Int = n }\ncounter = new Counter {}\nvalue = counter.add(3)"
  assert_true(typecheck_source(source) is TypeOk(_))
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )

  let invalid = "class Counter { function add(n: Int(isBetween(0, 10))): Int = n }\ncounter = new Counter {}\nvalue = counter.add(11)"
  guard typecheck_source(invalid) is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|method add argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck Pkl class method bodies with receiver bindings" {
  assert_true(
    typecheck_source(
      "class Counter { base = 40\nfunction add(n: Int): Int = base + n }\ncounter = new Counter {}\nvalue = counter.add(2)",
    )
    is TypeOk(_),
  )
  guard typecheck_source(
      "class BadCounter { base = \"hawk\"\nfunction add(n: Int): Int = base + n }\nbad = new BadCounter {}\nvalue = bad.add(2)",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
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

///|
test "typecheck infers Pkl class property default types" {
  guard typecheck_source(
      "class Bird { name = \"hawk\"; age = 2 }\nbird: Bird = new { name = \"owl\"; age = 3 }",
    )
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Bird")

  guard typecheck_source(
      "class Bird { name = \"hawk\"; age = 2 }\nbird: Bird = new { name = 1; age = 3 }",
    )
    is TypeError(name_diagnostics) else {
    panic()
  }
  inspect(
    name_diagnostics[0].message,
    content="type annotation Bird member name expects String, got Int",
  )

  guard typecheck_source(
      "class Box { f = (x: Int): Int -> x + 1 }\nbox: Box = new { f = (x: String): String -> x }",
    )
    is TypeError(function_diagnostics) else {
    panic()
  }
  inspect(
    function_diagnostics[0].message,
    content="type annotation Box member f expects Function, got Function",
  )
}

///|
test "typecheck allows Pkl class defaults to satisfy missing members" {
  guard typecheck_source(
      "class Bird { name = \"hawk\"; age: Int }\nbird: Bird = new { age = 2 }",
    )
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Bird")

  guard typecheck_source(
      "class Bird { name: String = \"hawk\"; age: Int = 1 }\nbird: Bird = new {}",
    )
    is TypeOk(ObjectType(default_fields)) else {
    panic()
  }
  inspect(render_type(default_fields[0].typ), content="Bird")

  guard typecheck_source(
      "class Bird { name = \"hawk\"; age: Int }\nbird: Bird = new { name = 1; age = 2 }",
    )
    is TypeError(name_diagnostics) else {
    panic()
  }
  inspect(
    name_diagnostics[0].message,
    content="type annotation Bird member name expects String, got Int",
  )

  guard typecheck_source(
      "class Bird { name = \"hawk\"; age: Int }\nbird: Bird = new {}",
    )
    is TypeError(age_diagnostics) else {
    panic()
  }
  inspect(
    age_diagnostics[0].message,
    content="type annotation Bird missing member age",
  )
}

///|
test "parse and typecheck Pkl typed object expressions" {
  let parsed = parse_source(
    "class Bird { name: String }\nbird = new Bird { name = \"hawk\" }",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.bindings[0].value
    is TypedObjectLiteral(type_name, members) else {
    panic()
  }
  inspect(type_name, content="Bird")
  inspect(members[0].name, content="name")

  guard typecheck_source(
      "class Bird { name: String }\nbird = new Bird { name = \"hawk\" }\nlabel = bird.name",
    )
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Bird")
  assert_true(fields[1].typ == StringType)

  guard typecheck_source("class Bird { name = \"hawk\" }\nbird = new Bird {}")
    is TypeOk(ObjectType(default_fields)) else {
    panic()
  }
  inspect(render_type(default_fields[0].typ), content="Bird")

  guard typecheck_source("class Bird { name: String }\nbird = new Bird {}")
    is TypeError(missing_diagnostics) else {
    panic()
  }
  inspect(
    missing_diagnostics[0].message,
    content="type annotation Bird missing member name",
  )

  guard typecheck_source(
      "class Bird { name: String }\nbird = new Bird { name = 1 }",
    )
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content="type annotation Bird member name expects String, got Int",
  )
}

///|
test "evaluate Pkl typed object class defaults" {
  assert_true(
    eval_source(
      "class Bird { name = \"hawk\"; age: Int }\nbird = new Bird { age = 2 }",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "bird",
          value: ObjectValue([
            ValueMember::{
              name: "name",
              value: StringValue("hawk"),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "age",
              value: IntValue(2),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "class Bird { name = \"hawk\"; age = 1 }\nbird = new Bird { name = \"owl\" }",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "bird",
          value: ObjectValue([
            ValueMember::{
              name: "name",
              value: StringValue("owl"),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "age",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "class Bird { name = \"hawk\" }\nlet bird = new Bird {}\nbird.name",
    ) ==
    EvalOk(StringValue("hawk")),
  )
}

///|
test "evaluate Pkl constrained class property annotations" {
  let valid = "const function above(n) = (x) -> x > n\nclass X { a: Int(above(5)) }\nx = new X { a = 6 }"
  guard typecheck_source(valid) is TypeOk(ObjectType(fields)) else { panic() }
  inspect(render_type(fields[0].typ), content="X")
  assert_true(
    eval_source(valid) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "x",
          value: ObjectValue([
            ValueMember::{
              name: "a",
              value: IntValue(6),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )

  let invalid = "const function above(n) = (x) -> x > n\nclass X { a: Int(above(5)) }\nx = new X { a = 5 }"
  guard typecheck_source(invalid) is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
}

///|
test "evaluate Pkl constrained class property default values" {
  let valid = "const function above(n) = (x) -> x > n\nclass X { a: Int(above(5)) = 6 }\nx = new X {}"
  guard typecheck_source(valid) is TypeOk(ObjectType(fields)) else { panic() }
  inspect(render_type(fields[0].typ), content="X")
  assert_true(
    eval_source(valid) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "x",
          value: ObjectValue([
            ValueMember::{
              name: "a",
              value: IntValue(6),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )

  let invalid = "const function above(n) = (x) -> x > n\nclass X { a: Int(above(5)) = 5 }\nx = new X {}"
  guard typecheck_source(invalid) is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 5
    ),
  )
}

///|
test "support Pkl class inheritance defaults" {
  let parsed = parse_source(
    "class Animal { name = \"animal\" }\nclass Bird extends Animal { wing = \"wide\" }",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[1] is ClassDeclaration(class_decl) else {
    panic()
  }
  inspect(class_decl.name, content="Bird")
  assert_true(class_decl.parent_name == Some("Animal"))

  guard typecheck_source(
      "class Animal { name = \"animal\"; age: Int }\nclass Bird extends Animal { wing = \"wide\" }\nbird = new Bird { age = 2 }\nname = bird.name\nwing = bird.wing",
    )
    is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Bird")
  assert_true(fields[1].typ == StringType)
  assert_true(fields[2].typ == StringType)

  guard typecheck_source(
      "class Animal { age: Int }\nclass Bird extends Animal {}\nbird = new Bird {}",
    )
    is TypeError(missing_diagnostics) else {
    panic()
  }
  inspect(
    missing_diagnostics[0].message,
    content="type annotation Bird missing member age",
  )

  assert_true(
    eval_source(
      "class Animal { name = \"animal\"; age = 1 }\nclass Bird extends Animal { name = \"bird\"; wing = \"wide\" }\nbird = new Bird {}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "bird",
          value: ObjectValue([
            ValueMember::{
              name: "name",
              value: StringValue("bird"),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "age",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "wing",
              value: StringValue("wide"),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "support Pkl qualified class inheritance types" {
  let parsed = parse_source(
    "import \"library.pkl\" as library\nclass Teacher extends library.Person { subject = \"math\" }\nteacher = new library.Person { age = 2 }",
  )
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.declarations[0] is ClassDeclaration(class_decl) else {
    panic()
  }
  assert_true(class_decl.parent_name == Some("library.Person"))
  guard parsed.program.bindings[0].value is TypedObjectLiteral(type_name, _) else {
    panic()
  }
  inspect(type_name, content="library.Person")

  let session = AnalysisSession::new()
  session.set_source(
    "library.pkl", "class Person { name = \"anon\"; age: Int }\nmarker = 1",
  )
  session.set_source(
    "main.pkl", "import \"library.pkl\" as library\nclass Teacher extends library.Person { subject = \"math\" }\nteacher = new Teacher { age = 3 }\nname = teacher.name\nsubject = teacher.subject",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(ObjectType(fields)) else {
    panic()
  }
  inspect(render_type(fields[0].typ), content="Teacher")
  assert_true(fields[1].typ == StringType)
  assert_true(fields[2].typ == StringType)

  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "teacher",
          value: ObjectValue([
            ValueMember::{
              name: "name",
              value: StringValue("anon"),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "age",
              value: IntValue(3),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "subject",
              value: StringValue("math"),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "name",
          value: StringValue("anon"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "subject",
          value: StringValue("math"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "parse Pkl calls lambdas operators and conditionals" {
  let parsed = parse_source(
    "local f = (x, y) -> x + y\nvalue = f(1, 2)\nlogic = true || false && !false\nchoice = null ?? if (1 + 2 > 2) \"yes\" else \"no\"",
  )
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.unsupported_syntax.length(), content="0")

  guard parsed.program.bindings[0].value
    is LambdaExpr(parameters, lambda_body, None) else {
    panic()
  }
  inspect(parameters.length(), content="2")
  inspect(parameters[0].name, content="x")
  inspect(parameters[1].name, content="y")
  assert_true(lambda_body == BinaryExpr(Add, Identifier("x"), Identifier("y")))

  assert_true(
    parsed.program.bindings[1].value ==
    CallExpr(Identifier("f"), [IntLiteral(1), IntLiteral(2)]),
  )

  assert_true(
    parsed.program.bindings[2].value ==
    BinaryExpr(
      Or,
      BoolLiteral(true),
      BinaryExpr(And, BoolLiteral(false), UnaryExpr(Not, BoolLiteral(false))),
    ),
  )

  assert_true(
    parsed.program.bindings[3].value ==
    BinaryExpr(
      NullCoalesce,
      NullLiteral,
      ConditionalExpr(
        BinaryExpr(
          GreaterThan,
          BinaryExpr(Add, IntLiteral(1), IntLiteral(2)),
          IntLiteral(2),
        ),
        StringLiteral("yes"),
        StringLiteral("no"),
      ),
    ),
  )
}

///|
test "evaluate Pkl boolean comparison coalescing and conditional expressions" {
  assert_true(
    eval_source("if (1 + 2 > 2 && !false) \"yes\" else \"no\"") ==
    EvalOk(StringValue("yes")),
  )
  assert_true(eval_source("null ?? 4") == EvalOk(IntValue(4)))
  assert_true(eval_source("false || true && false") == EvalOk(BoolValue(false)))
}

///|
test "typecheck Pkl boolean comparison coalescing and conditional expressions" {
  assert_true(
    typecheck_source("if (1 + 2 > 2 && !false) \"yes\" else \"no\"") ==
    TypeOk(StringType),
  )
  assert_true(typecheck_source("null ?? 4") == TypeOk(IntType))
  guard typecheck_source("if (1) \"yes\" else \"no\"") is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="if condition expects Boolean")
}

///|
test "typecheck Pkl function declarations and lambdas at call sites" {
  let source = "function add(x, y) = x + y\nlocal inc = (n) -> n + 1\nsum = add(1, 2)\nnext = inc(sum)"
  guard typecheck_source(source) is TypeOk(ObjectType(fields)) else { panic() }
  inspect(fields[0].name, content="sum")
  assert_true(fields[0].typ == IntType)
  inspect(fields[1].name, content="next")
  assert_true(fields[1].typ == IntType)
}

///|
test "evaluate Pkl function declarations lambdas and calls" {
  let source = "function add(x: Int, y: Int): Int = x + y\nlocal inc = (n) -> n + 1\nsum = add(1, 2)\nnext = inc(sum)"
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "sum",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "next",
          value: IntValue(4),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "evaluate Pkl callable runtime values" {
  assert_true(
    eval_source("local inc = (n) -> n + 1\nlocal f = inc\nvalue = f(41)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "function apply(f, n) = f(n)\nlocal inc = (n) -> n + 1\nvalue = apply(inc, 2)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("local box = new { f = (x) -> x + 1 }\nvalue = box.f(2)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "evaluate Pkl callable closure captures" {
  assert_true(
    eval_source(
      "function makeAdder(n) = (x) -> x + n\nlocal add2 = makeAdder(2)\nvalue = add2(3)",
    ) ==
    EvalOk(
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
test "evaluate non-scalar Pkl callable closure captures" {
  assert_true(
    eval_source(
      "function makeReader(box) = () -> box.name\nlocal reader = makeReader(new { name = \"hawk\" })\nvalue = reader()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: StringValue("hawk"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "function makeApply(f) = (n) -> f(n)\nlocal inc = (x) -> x + 1\nlocal applyInc = makeApply(inc)\nvalue = applyInc(2)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "evaluate Pkl callable return annotations" {
  assert_true(
    eval_source("function good(): Int = 1\nvalue = good()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source("function bad(): Int = \"hawk\"\nvalue = bad()")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Expected value of type `Int`, but got type `String`. Value: "hawk"
    ),
  )
}

///|
test "evaluate Pkl class method return annotations" {
  assert_true(
    eval_source(
      "class Counter { function good(): Int = 1 }\ncounter = new Counter {}\nvalue = counter.good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "class Counter { function bad(): Int = \"hawk\" }\ncounter = new Counter {}\nvalue = counter.bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Expected value of type `Int`, but got type `String`. Value: "hawk"
    ),
  )
}

///|
test "evaluate constrained Pkl callable return annotations" {
  assert_true(
    eval_source("function good(): Int(isBetween(0, 10)) = 1\nvalue = good()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source("function bad(): Int(isBetween(0, 10)) = 11\nvalue = bad()")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "evaluate user-defined constrained Pkl callable return annotations" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nfunction good(): Int(above(5)) = 6\nvalue = good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nfunction bad(): Int(above(5)) = 1\nvalue = bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 1
    ),
  )
}

///|
test "evaluate user-defined constrained Pkl class method return annotations" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function good(): Int(above(5)) = 6 }\ncounter = new Counter {}\nvalue = counter.good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function bad(): Int(above(5)) = 1 }\ncounter = new Counter {}\nvalue = counter.bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 1
    ),
  )
}

///|
test "evaluate user-defined constrained Pkl callable arguments" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nfunction check(n: Int(above(5))) = n\nvalue = check(6)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nfunction check(n: Int(above(5))) = n\nvalue = check(1)",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 1
    ),
  )
}

///|
test "evaluate user-defined constrained Pkl class method arguments" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function check(n: Int(above(5))) = n }\ncounter = new Counter {}\nvalue = counter.check(6)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function check(n: Int(above(5))) = n }\ncounter = new Counter {}\nvalue = counter.check(1)",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Type constraint `above(5)` violated. Value: 1
    ),
  )
}

///|
test "evaluate typealiased Pkl callable return annotations" {
  assert_true(
    eval_source(
      "typealias Small = Int\nfunction good(): Small = 1\nvalue = good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "typealias Small = Int\nfunction bad(): Small = \"hawk\"\nvalue = bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Expected value of type `Small`, but got type `String`. Value: "hawk"
    ),
  )
  assert_true(
    eval_source(
      "typealias Small = Int(isBetween(0, 10))\nfunction good(): Small = 6\nvalue = good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nfunction bad(): Small = 11\nvalue = bad()",
    )
    is EvalError(constraint_diagnostics) else {
    panic()
  }
  inspect(
    constraint_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "evaluate typealiased Pkl class method return annotations" {
  assert_true(
    eval_source(
      "typealias Small = Int\nclass Counter { function good(): Small = 1 }\ncounter = new Counter {}\nvalue = counter.good()",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "counter",
          value: ObjectValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "value",
          value: IntValue(1),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "typealias Small = Int\nclass Counter { function bad(): Small = \"hawk\" }\ncounter = new Counter {}\nvalue = counter.bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|Expected value of type `Small`, but got type `String`. Value: "hawk"
    ),
  )
}

///|
test "typecheck rejects invalid Pkl calls" {
  guard typecheck_source("function add(x, y) = x + y\nvalue = add(1)")
    is TypeError(arity_diagnostics) else {
    panic()
  }
  inspect(
    arity_diagnostics[0].message,
    content="function add expects 2 arguments, got 1",
  )

  guard typecheck_source("value = 1(2)") is TypeError(call_diagnostics) else {
    panic()
  }
  inspect(call_diagnostics[0].message, content="call expects Function")
}

///|
test "typecheck Pkl callable parameter and return annotations" {
  assert_true(
    typecheck_source(
      "function add(x: Int, y: Int): Int = x + y\nvalue = add(1, 2)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "local stringify = (x: String): String -> x\nvalue = stringify(\"hawk\")",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: StringType }])),
  )

  guard typecheck_source(
      "function add(x: Int, y: Int): Int = x + y\nvalue = add(1, true)",
    )
    is TypeError(argument_diagnostics) else {
    panic()
  }
  inspect(
    argument_diagnostics[0].message,
    content="function add argument 2 expects Int, got Boolean",
  )

  guard typecheck_source("function bad(x: Int): String = x\nvalue = bad(1)")
    is TypeError(return_diagnostics) else {
    panic()
  }
  inspect(
    return_diagnostics[0].message,
    content="function bad return annotation String does not accept Int",
  )
}

///|
test "typecheck rejects constrained Pkl callable return bodies" {
  assert_true(
    typecheck_source(
      "function good(): Int(isBetween(0, 10)) = 1\nvalue = good()",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "function bad(): Int(isBetween(0, 10)) = 11\nvalue = bad()",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|function bad return Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source(
      "class Counter { function bad(): Int(isBetween(0, 10)) = 11 }\ncounter = new Counter {}",
    )
    is TypeError(method_diagnostics) else {
    panic()
  }
  inspect(
    method_diagnostics[0].message,
    content=(
      #|method Counter.bad return Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck rejects user-defined constrained Pkl callable return bodies" {
  assert_true(
    typecheck_source(
      "const function above(n) = (x) -> x > n\nfunction good(): Int(above(5)) = 6\nvalue = good()",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "const function above(n) = (x) -> x > n\nfunction bad(): Int(above(5)) = 1\nvalue = bad()",
    )
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content=(
      #|function bad return Type constraint `above(5)` violated. Value: 1
    ),
  )
  guard typecheck_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function bad(): Int(above(5)) = 1 }\ncounter = new Counter {}",
    )
    is TypeError(method_diagnostics) else {
    panic()
  }
  inspect(
    method_diagnostics[0].message,
    content=(
      #|method Counter.bad return Type constraint `above(5)` violated. Value: 1
    ),
  )
}

///|
test "enforce Pkl constrained function parameter annotations" {
  assert_true(
    typecheck_source(
      "function accept(n: Int(isBetween(0, 10))): Int = n\nvalue = accept(3)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "function accept(n: Int(isBetween(0, 10))): Int = n\nvalue = accept(11)",
    )
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|function accept argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source(
      "local accept = (n: Int(this.isBetween(0, 10))): Int -> n\nvalue = accept(11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content=(
      #|function accept argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  assert_true(
    eval_source(
      "function accept(n: Int(isBetween(0, 10))) = n\nlocal f = accept\nvalue = f(3)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "value",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  guard eval_source(
      "function accept(n: Int(isBetween(0, 10))) = n\nlocal f = accept\nvalue = f(11)",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck Pkl constrained callable signature metadata" {
  assert_true(
    typecheck_source(
      "function accept(n: Int(isBetween(0, 10))): Int = n\nlocal f = accept\nvalue = f(3)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "function accept(n: Int(isBetween(0, 10))): Int = n\nlocal f = accept\nvalue = f(11)",
    )
    is TypeError(function_diagnostics) else {
    panic()
  }
  inspect(
    function_diagnostics[0].message,
    content=(
      #|function argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source(
      "local accept = (n: Int(this.isBetween(0, 10))): Int -> n\nlocal f = accept\nvalue = f(11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content=(
      #|function argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck Pkl constrained higher-order callable metadata" {
  assert_true(
    typecheck_source(
      "function apply(f, n): Int = f(n)\nfunction accept(n: Int(isBetween(0, 10))): Int = n\nvalue = apply(accept, 3)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "function apply(f, n): Int = f(n)\nfunction accept(n: Int(isBetween(0, 10))): Int = n\nvalue = apply(accept, 11)",
    )
    is TypeError(function_diagnostics) else {
    panic()
  }
  inspect(
    function_diagnostics[0].message,
    content=(
      #|function apply argument 2 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source(
      "local apply = (f, n): Int -> f(n)\nlocal accept = (n: Int(this.isBetween(0, 10))): Int -> n\nvalue = apply(accept, 11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content=(
      #|function apply argument 2 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "typecheck Pkl constrained type annotations" {
  let parsed = parse_source("value: Int(isBetween(0, 10)) = 3")
  assert_true(
    parsed.program.bindings[0].type_name == Some("Int(isBetween(0,10))"),
  )
  assert_true(
    typecheck_source("value: Int(isBetween(0, 10)) = 3") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source(
      "function id(n: Int(this.isBetween(0, 10))): Int(this.isBetween(0, 10)) = n\nvalue = id(3)",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source("value: Int(isBetween(0, 10)) = \"hawk\"")
    is TypeError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="type annotation Int(isBetween(0,10)) does not accept String",
  )
}

///|
test "preserve Pkl constrained typealias metadata" {
  assert_true(
    typecheck_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue: Small = 3",
    ) ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue: Small = 11",
    )
    is TypeError(value_diagnostics) else {
    panic()
  }
  inspect(
    value_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue: Small = 11",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard typecheck_source(
      "typealias Small = Int(this.isBetween(0, 10))\nfunction accept(n: Small): Int = n\nvalue = accept(11)",
    )
    is TypeError(parameter_diagnostics) else {
    panic()
  }
  inspect(
    parameter_diagnostics[0].message,
    content=(
      #|function accept argument 1 Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "evaluate Pkl constrained typealias object member annotations" {
  assert_true(
    typecheck_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue = new { n: Small = 3 }",
    )
    is TypeOk(_),
  )
  guard typecheck_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue = new { n: Small = 11 }",
    )
    is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue = new { n: Small = 11 }",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content=(
      #|Type constraint `isBetween(0, 10)` violated. Value: 11
    ),
  )
}

///|
test "support additional Pkl numeric constraint predicates" {
  assert_true(
    typecheck_source("value: Int(isPositive) = 3") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  assert_true(
    typecheck_source("value: Int(isPositive) = 0") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard eval_source("value: Int(this.isGreaterThan(5)) = 5")
    is EvalError(greater_diagnostics) else {
    panic()
  }
  inspect(
    greater_diagnostics[0].message,
    content=(
      #|Type constraint `isGreaterThan(5)` violated. Value: 5
    ),
  )
  guard typecheck_source(
      "typealias Small = Int(isLessThan(10))\nvalue = new { n: Small = 10 }",
    )
    is TypeError(alias_diagnostics) else {
    panic()
  }
  inspect(
    alias_diagnostics[0].message,
    content=(
      #|Type constraint `isLessThan(10)` violated. Value: 10
    ),
  )
}

///|
// PKL-158: cross-module amend of a typed `Listing<Class>` property whose
// type is declared only on the parent. The child writes
// `workflowTests { new { workflow = "build" } }` with NO annotation, so its
// binding carries `type_name = None`. The parent's element type
// `WorkflowTest` must still be threaded into the listing-literal evaluation
// so each element gains `WorkflowTest`'s property defaults
// (`direct: []`, `shell = "bash"`) while keeping the explicit `workflow`.
test "PKL-158: cross-module amend inherits parent listing element type defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "base.pkl",
    (
      #|module base
      #|class WorkflowTest {
      #|  workflow: String
      #|  shell: String = "bash"
      #|  direct: Listing<String> = new {}
      #|}
      #|workflowTests: Listing<WorkflowTest> = new {}
    ),
  )
  session.set_source(
    "main.pkl",
    (
      #|amends "base.pkl"
      #|workflowTests {
      #|  new { workflow = "build" }
      #|  new { workflow = "test"; shell = "zsh"; direct { "a"; "b" } }
      #|}
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  // Element 1 keeps `workflow` and gains the `shell` (String) and
  // `direct` (Listing) defaults; element 2 keeps all of its explicit
  // overrides. Matches `pkl eval` exactly.
  inspect(
    render_value(value),
    content=(
      #|workflowTests {
      #|  new {
      #|    workflow = "build"
      #|    shell = "bash"
      #|    direct {}
      #|  }
      #|  new {
      #|    workflow = "test"
      #|    shell = "zsh"
      #|    direct {
      #|      "a"
      #|      "b"
      #|    }
      #|  }
      #|}
    ),
  )
}

///|
// PKL-158b: regression for the cross-module class-identity check that the
// PKL-158 type backfill enabled. The child amends `schema.pkl` and fills the
// inherited `tasks: Listing<Task>` with an element constructed through a
// DIFFERENT import alias (`new s.Task { ... }`). The element's class tag is
// the alias-qualified `s.Task`, but it denotes the SAME underlying class as
// the parent's `Task` element type. The element type-check must accept it
// (Apple Pkl does); the pre-fix backfill wrongly rejected it with
// `Expected value of type \`schema#Task\`, but got type \`s.Task\``.
test "PKL-158b: cross-module amend accepts alias-qualified element of same class" {
  let session = AnalysisSession::new()
  session.set_source(
    "schema.pkl",
    (
      #|module schema
      #|class Task { name: String; cmd: String = "" }
      #|tasks: Listing<Task> = new {}
      #|names = tasks.toList().map((t) -> t.name)
    ),
  )
  session.set_source(
    "frag.pkl",
    (
      #|amends "schema.pkl"
      #|import "schema.pkl" as s
      #|tasks {
      #|  (new s.Task { name = "alpha"; cmd = "echo alpha" })
      #|}
    ),
  )
  guard session.eval_path("frag.pkl") is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|tasks {
      #|  new {
      #|    name = "alpha"
      #|    cmd = "echo alpha"
      #|  }
      #|}
      #|names = List("alpha")
    ),
  )
}

///|
