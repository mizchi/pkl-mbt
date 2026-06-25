///|
test "parse source builds a CST-backed program" {
  let parsed = parse_source("1 + 2 * 3")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.root.text_len().to_int(), content="9")
}

///|
test "evaluate integer arithmetic with precedence" {
  assert_true(eval_source("1 + 2 * 3") == EvalOk(IntValue(7)))
}

///|
// PKL-pkspec-C: a newline (and surrounding trivia) immediately before
// a closing `)` must be skipped. `(expr)` and `(expr)\n.member` parse
// fine, but `( \n expr \n )` used to fail with `expected ), got
// newline`. Apple Pkl treats newlines as whitespace inside a
// parenthesized group. Triggered by pkspec's `pkl/Test.test.pkl`,
// whose parenthesized `new Schema.CmdTest { ... }` puts the `)` on its
// own line.
test "PKL-pkspec-C: newline before closing paren parses" {
  assert_true(eval_source("(\n  1 + 2\n)") == EvalOk(IntValue(3)))
  // Leading newline after `(` and a trailing comment before `)`.
  assert_true(
    eval_source("(\n  4 * 5 // product\n)") == EvalOk(IntValue(20)),
  )
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
test "parse and evaluate unicode identifiers" {
  let parsed = parse_source("日本語 = \"Japanese language\"")
  inspect(parsed.diagnostics.length(), content="0")
  inspect(parsed.unsupported_syntax.length(), content="0")
  inspect(parsed.program.bindings[0].name, content="日本語")
  assert_true(
    eval_source("日本語 = \"Japanese language\"") ==
    EvalOk(
      ObjectValue([
        {
          name: "日本語",
          value: StringValue("Japanese language"),
          source: Some(StringLiteral("Japanese language")),
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "evaluate object literal from top-level module properties" {
  assert_true(
    eval_source("module demo\nname = \"hawk\"\nage = 2") ==
    EvalOk(
      ObjectValue([
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
test "parse raw import glob string preserves escaped wildcard literal" {
  let parsed = parse_source("x = import*(#\"foo\\[bar].pkl\"#)")
  inspect(parsed.diagnostics.length(), content="0")
  guard parsed.program.bindings[0].value is ImportGlobExpr(uri) else { panic() }
  inspect(uri, content="foo\\[bar].pkl")
}

///|
test "analysis session self import sees current module partial bindings" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "a = \"hawk\"\nb = import(\"main.pkl\").a")
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_eq(members.length(), 2)
  assert_eq(members[1].name, "b")
  assert_true(members[1].value == StringValue("hawk"))
}

///|
test "analysis session reports cyclic imports during typechecking" {
  let session = AnalysisSession::new()
  session.set_source("a.pkl", "import \"b.pkl\" as b\nvalue = b.value")
  session.set_source("b.pkl", "import \"a.pkl\" as a\nvalue = a.value")
  guard session.typecheck_path("a.pkl") is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="cyclic import a.pkl")
}

///|
test "analysis session resolves selected pkl standard library modules" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "import \"pkl:math\" as math\nmath.maxInt32")
  assert_true(session.typecheck_path("main.pkl") == TypeOk(IntType))
  assert_true(session.eval_path("main.pkl") == EvalOk(IntValue(2147483647)))
}

///|
test "evaluate pkl test catch for upstream constraint fixtures" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nconst function isGreaterThan(n) = (x) -> x > n\nclass X { a: Int(isGreaterThan(5)) }\nres1 = new X { a = 6 }\nres2 = test.catch(() -> new X { a = 5 }.a)",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res1",
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
        ValueMember::{
          name: "res2",
          value: StringValue(
            "Type constraint `isGreaterThan(5)` violated. Value: 5",
          ),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
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
test "render Pkl values as PCF primitives" {
  inspect(render_value(IntValue(0)), content="0")
  inspect(render_value(IntValue(42)), content="42")
  inspect(render_value(IntValue(-7)), content="-7")
  inspect(render_value(BoolValue(true)), content="true")
  inspect(render_value(BoolValue(false)), content="false")
  inspect(render_value(NullValue), content="null")
  inspect(render_value(StringValue("")), content="\"\"")
  inspect(render_value(StringValue("hawk")), content="\"hawk\"")
  inspect(render_value(StringValue("a\nb")), content="\"a\\nb\"")
  inspect(render_value(StringValue("a\tb")), content="\"a\\tb\"")
  inspect(render_value(StringValue("a\rb")), content="\"a\\rb\"")
  inspect(render_value(StringValue("say \"hi\"")), content="\"say \\\"hi\\\"\"")
  inspect(render_value(StringValue("c:\\path")), content="\"c:\\\\path\"")
}

///|
test "render PCF module bindings as key equals value lines" {
  guard eval_source("n = 42\nb = true\ns = \"hawk\"\nz = null") is EvalOk(value) else {
    panic()
  }
  inspect(
    render_value(value),
    content=(
      #|n = 42
      #|b = true
      #|s = "hawk"
      #|z = null
    ),
  )
}

///|
test "PCF render output reparses to the original module" {
  let source = "n = 42\nb = true\ns = \"a\\tb\"\nz = null"
  guard eval_source(source) is EvalOk(first_pass) else { panic() }
  let rendered = render_value(first_pass)
  guard eval_source(rendered) is EvalOk(second_pass) else { panic() }
  assert_true(first_pass == second_pass)
}

///|
test "render Pkl listings and mappings as PCF blocks" {
  inspect(
    render_value(ListingValue([])),
    content=(
      #|new {}
    ),
  )
  inspect(
    render_value(ListingValue([IntValue(1), IntValue(2), IntValue(3)])),
    content=(
      #|new {
      #|  1
      #|  2
      #|  3
      #|}
    ),
  )
  inspect(
    render_value(MappingValue([])),
    content=(
      #|new {}
    ),
  )
  inspect(
    render_value(
      MappingValue([
        ValueEntry::{ key: StringValue("hawk"), value: StringValue("forest") },
        ValueEntry::{ key: StringValue("owl"), value: StringValue("night") },
      ]),
    ),
    content=(
      #|new {
      #|  ["hawk"] = "forest"
      #|  ["owl"] = "night"
      #|}
    ),
  )
}

///|
test "render Pkl module bindings with nested PCF blocks" {
  guard eval_source(
      "foo = new {\n  name = \"hawk\"\n  age = 2\n}\nempty = new {}",
    )
    is EvalOk(value) else {
    panic()
  }
  inspect(
    render_value(value),
    content=(
      #|foo {
      #|  name = "hawk"
      #|  age = 2
      #|}
      #|empty {}
    ),
  )
}

///|
test "render Pkl module bindings with nested listings and mappings" {
  guard eval_source(
      "nums = new Listing { 1; 2; 3 }\nempty_list = new Listing {}\nhabitats = new Mapping { [\"hawk\"] = \"forest\" }\nempty_map = new Mapping {}",
    )
    is EvalOk(value) else {
    panic()
  }
  inspect(
    render_value(value),
    content=(
      #|nums {
      #|  1
      #|  2
      #|  3
      #|}
      #|empty_list {}
      #|habitats {
      #|  ["hawk"] = "forest"
      #|}
      #|empty_map {}
    ),
  )
}

///|
test "render deeply nested Pkl values as PCF" {
  guard eval_source(
      "config = new {\n  servers = new Listing {\n    new Mapping { [\"host\"] = \"a\"; [\"port\"] = 1 }\n    new Mapping { [\"host\"] = \"b\"; [\"port\"] = 2 }\n  }\n}",
    )
    is EvalOk(value) else {
    panic()
  }
  inspect(
    render_value(value),
    content=(
      #|config {
      #|  servers {
      #|    new {
      #|      ["host"] = "a"
      #|      ["port"] = 1
      #|    }
      #|    new {
      #|      ["host"] = "b"
      #|      ["port"] = 2
      #|    }
      #|  }
      #|}
    ),
  )
}

///|
test "PCF rendered object members reparse to the original module" {
  // Object members use `name = scalar` / `name { ... }` lines that round
  // through the parser; listing / mapping rendering drops the type tag
  // and uses Pkl's element shorthand which our parser does not yet
  // accept, so this round-trip stays on the object-member subset.
  let source = "outer = new {\n  inner = new {\n    deep = new {\n      x = 1\n    }\n  }\n  flat = 42\n}"
  guard eval_source(source) is EvalOk(first_pass) else { panic() }
  let rendered = render_value(first_pass)
  guard eval_source(rendered) is EvalOk(second_pass) else { panic() }
  assert_true(first_pass == second_pass)
}

///|
test "render Pkl values as JSON primitives" {
  inspect(render_value_as_json(IntValue(0)), content="0")
  inspect(render_value_as_json(IntValue(42)), content="42")
  inspect(render_value_as_json(IntValue(-7)), content="-7")
  inspect(render_value_as_json(BoolValue(true)), content="true")
  inspect(render_value_as_json(BoolValue(false)), content="false")
  inspect(render_value_as_json(NullValue), content="null")
  inspect(render_value_as_json(StringValue("")), content="\"\"")
  inspect(render_value_as_json(StringValue("hawk")), content="\"hawk\"")
}

///|
test "render JSON strings with escapes and control characters" {
  inspect(render_value_as_json(StringValue("a\nb")), content="\"a\\nb\"")
  inspect(render_value_as_json(StringValue("a\tb")), content="\"a\\tb\"")
  inspect(render_value_as_json(StringValue("a\rb")), content="\"a\\rb\"")
  inspect(
    render_value_as_json(StringValue("say \"hi\"")),
    content="\"say \\\"hi\\\"\"",
  )
  inspect(
    render_value_as_json(StringValue("c:\\path")),
    content="\"c:\\\\path\"",
  )
  inspect(render_value_as_json(StringValue("\u{08}")), content="\"\\b\"")
  inspect(render_value_as_json(StringValue("\u{0C}")), content="\"\\f\"")
  inspect(render_value_as_json(StringValue("\u{01}")), content="\"\\u0001\"")
}

///|
test "render Pkl module bindings as JSON object" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "age",
      value: IntValue(30),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "name": "pigeon",
      #|  "age": 30
      #|}
    ),
  )
}

///|
test "render Pkl listings and mappings as JSON" {
  inspect(render_value_as_json(ListingValue([])), content="[]")
  inspect(render_value_as_json(MappingValue([])), content="{}")
  inspect(
    render_value_as_json(
      ListingValue([StringValue("string"), BoolValue(true), IntValue(42)]),
    ),
    content=(
      #|[
      #|  "string",
      #|  true,
      #|  42
      #|]
    ),
  )
  inspect(
    render_value_as_json(
      MappingValue([
        ValueEntry::{ key: StringValue("name"), value: StringValue("pigeon") },
        ValueEntry::{ key: StringValue("age"), value: IntValue(30) },
      ]),
    ),
    content=(
      #|{
      #|  "name": "pigeon",
      #|  "age": 30
      #|}
    ),
  )
}

///|
test "JSON Mapping keys coerce non-string values to strings" {
  inspect(
    render_value_as_json(
      MappingValue([
        ValueEntry::{ key: IntValue(1), value: StringValue("a") },
        ValueEntry::{ key: BoolValue(true), value: StringValue("b") },
        ValueEntry::{ key: NullValue, value: StringValue("c") },
      ]),
    ),
    content=(
      #|{
      #|  "1": "a",
      #|  "true": "b",
      #|  "null": "c"
      #|}
    ),
  )
}

///|
test "render nested Pkl objects and arrays as JSON" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "friends",
      value: ListingValue([StringValue("barn owl"), StringValue("parrot")]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{
          name: "street",
          value: StringValue("Norton St."),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "zip",
          value: IntValue(12345),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "name": "pigeon",
      #|  "friends": [
      #|    "barn owl",
      #|    "parrot"
      #|  ],
      #|  "address": {
      #|    "street": "Norton St.",
      #|    "zip": 12345
      #|  }
      #|}
    ),
  )
}

///|
test "render empty composites as JSON" {
  // Mirrors jsonRendererEmptyComposites: every empty composite serializes
  // identically regardless of whether it originated as Object, Listing, or
  // Mapping.
  let value : Value = ObjectValue([
    ValueMember::{
      name: "a3",
      value: ListingValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "b2",
      value: MappingValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "b3",
      value: ObjectValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "nested",
      value: ObjectValue([
        ValueMember::{
          name: "a3",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b2",
          value: MappingValue([]),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "a3": [],
      #|  "b2": {},
      #|  "b3": {},
      #|  "nested": {
      #|    "a3": [],
      #|    "b2": {}
      #|  }
      #|}
    ),
  )
}

///|
test "JSON rendered top-level Pkl matches the jsonRenderer1 fixture shape" {
  // Apple Pkl's `pkl eval -f json` on the upstream `jsonRenderer1.json.pkl`
  // produces this exact document, modulo the inability of our pipeline to
  // honor `output { renderer = ... }` blocks today: we still render the
  // post-eval module directly.
  let source = "pigeon {\n  name = \"pigeon\"\n  age = 30\n}\n"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "pigeon": {
      #|    "name": "pigeon",
      #|    "age": 30
      #|  }
      #|}
    ),
  )
}

///|
test "render Pkl values as YAML primitives" {
  inspect(render_value_as_yaml(IntValue(0)), content="0\n")
  inspect(render_value_as_yaml(IntValue(42)), content="42\n")
  inspect(render_value_as_yaml(IntValue(-7)), content="-7\n")
  inspect(render_value_as_yaml(BoolValue(true)), content="true\n")
  inspect(render_value_as_yaml(BoolValue(false)), content="false\n")
  inspect(render_value_as_yaml(NullValue), content="null\n")
  inspect(render_value_as_yaml(StringValue("")), content="''\n")
  inspect(render_value_as_yaml(StringValue("hawk")), content="hawk\n")
}

///|
test "render YAML strings with quoting and escapes" {
  // Strings that collide with reserved scalar shapes get single-quoted.
  inspect(render_value_as_yaml(StringValue("true")), content="'true'\n")
  inspect(render_value_as_yaml(StringValue("null")), content="'null'\n")
  inspect(render_value_as_yaml(StringValue("42")), content="'42'\n")
  inspect(render_value_as_yaml(StringValue("3.14")), content="'3.14'\n")
  // Indicator-prefixed plain scalars must be quoted.
  inspect(render_value_as_yaml(StringValue("- foo")), content="'- foo'\n")
  inspect(render_value_as_yaml(StringValue("? foo")), content="'? foo'\n")
  inspect(render_value_as_yaml(StringValue(": foo")), content="': foo'\n")
  // Internal ": " or " #" promote to single-quoted as well.
  inspect(render_value_as_yaml(StringValue("foo: bar")), content="'foo: bar'\n")
  inspect(
    render_value_as_yaml(StringValue("foo # bar")),
    content="'foo # bar'\n",
  )
  // Embedded apostrophes are legal inside plain scalars (YAML treats `'` as
  // an indicator only at the very start), so they pass through unquoted.
  // A leading apostrophe still trips single-quoting, with `''` escape.
  inspect(
    render_value_as_yaml(StringValue("she said 'hi'")),
    content="she said 'hi'\n",
  )
  inspect(
    render_value_as_yaml(StringValue("'leading")),
    content="'''leading'\n",
  )
  // Control characters and backslashes require double-quoting.
  inspect(render_value_as_yaml(StringValue("a\nb")), content="\"a\\nb\"\n")
  inspect(render_value_as_yaml(StringValue("a\tb")), content="\"a\\tb\"\n")
  inspect(render_value_as_yaml(StringValue("a\rb")), content="\"a\\rb\"\n")
  inspect(
    render_value_as_yaml(StringValue("c:\\path")),
    content="\"c:\\\\path\"\n",
  )
  inspect(render_value_as_yaml(StringValue("\u{01}")), content="\"\\u0001\"\n")
}

///|
test "render Pkl module bindings as YAML mapping" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "age",
      value: IntValue(30),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|name: pigeon
      #|age: 30
      #|
    ),
  )
}

///|
test "render Pkl listings and mappings as YAML" {
  inspect(render_value_as_yaml(ListingValue([])), content=" []\n")
  inspect(render_value_as_yaml(MappingValue([])), content=" {}\n")
  inspect(
    render_value_as_yaml(
      ListingValue([StringValue("string"), BoolValue(true), IntValue(42)]),
    ),
    content=(
      #|- string
      #|- true
      #|- 42
      #|
    ),
  )
  inspect(
    render_value_as_yaml(
      MappingValue([
        ValueEntry::{ key: StringValue("name"), value: StringValue("pigeon") },
        ValueEntry::{ key: StringValue("age"), value: IntValue(30) },
      ]),
    ),
    content=(
      #|name: pigeon
      #|age: 30
      #|
    ),
  )
}

///|
test "YAML Mapping keys preserve scalar key syntax" {
  inspect(
    render_value_as_yaml(
      MappingValue([
        ValueEntry::{ key: IntValue(1), value: StringValue("a") },
        ValueEntry::{ key: BoolValue(true), value: StringValue("b") },
        ValueEntry::{ key: NullValue, value: StringValue("c") },
      ]),
    ),
    content=(
      #|1: a
      #|true: b
      #|null: c
      #|
    ),
  )
}

///|
test "YAML renderer quotes Pkl and mapping keys like upstream" {
  inspect(
    render_value_as_yaml(
      ObjectValue([
        ValueMember::{
          name: "`one[two`",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
    content="'one[two': 42\n",
  )
  inspect(
    render_value_as_yaml(
      MappingValue([
        ValueEntry::{ key: StringValue("one[two"), value: IntValue(42) },
        ValueEntry::{ key: StringValue("one,two"), value: IntValue(42) },
      ]),
    ),
    content="'one[two': 42\n'one,two': 42\n",
  )
}

///|
test "YAML renderer emits explicit mapping keys when required" {
  let key_buf = StringBuilder::new()
  for _i = 0; _i < 1025; _i = _i + 1 {
    key_buf.write_char('a')
  }
  let long_key = key_buf.to_string()
  let value : Value = ObjectValue([
    ValueMember::{
      name: "entries",
      value: MappingValue([
        ValueEntry::{ key: StringValue("one\ntwo"), value: IntValue(42) },
        ValueEntry::{ key: StringValue(long_key), value: IntValue(42) },
      ]),
      source: None,
      annotations: [],
    },
  ])
  let out = render_value_as_yaml(value)
  inspect(out.contains("  ? |-\n    one\n    two\n  : 42"), content="true")
  inspect(out.contains("  ? aaaaaaaaaa"), content="true")
}

///|
test "YAML renderer matches upstream block scalar chomping" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "a1",
      value: StringValue("\n"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "d1",
      value: StringValue("one\n"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "d2",
      value: StringValue("one\n\n"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "j3",
      value: StringValue("one\n   two"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "l2",
      value: StringValue("   \n"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|a1: |+
      #|
      #|d1: |
      #|  one
      #|d2: |+
      #|  one
      #|
      #|j3: |-
      #|  one
      #|     two
      #|l2: |2
      #|     
      #|
    ),
  )
}

///|
test "YAML renderer uses YAML double-quoted escape names" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "`null`",
      value: StringValue("\t\u{00}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "bell",
      value: StringValue("\t\u{7}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "verticalTab",
      value: StringValue("\t\u{b}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "escape",
      value: StringValue("\t\u{1b}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "nextLine",
      value: StringValue("\t\u{85}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "nbsp",
      value: StringValue("\t\u{a0}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "lineSep",
      value: StringValue("\t\u{2028}"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "paragraphSep",
      value: StringValue("\t\u{2029}"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|'null': "\t\0"
      #|bell: "\t\a"
      #|verticalTab: "\t\v"
      #|escape: "\t\e"
      #|nextLine: "\t\N"
      #|nbsp: "\t\_"
      #|lineSep: "\t\L"
      #|paragraphSep: "\t\P"
      #|
    ),
  )
}

///|
test "render nested Pkl objects and arrays as YAML" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "friends",
      value: ListingValue([StringValue("barn owl"), StringValue("parrot")]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{
          name: "street",
          value: StringValue("Norton St."),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "zip",
          value: IntValue(12345),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|name: pigeon
      #|friends:
      #|- barn owl
      #|- parrot
      #|address:
      #|  street: Norton St.
      #|  zip: 12345
      #|
    ),
  )
}

///|
test "render YAML sequence of mappings and nested sequences" {
  // Mirrors the nestedFriends / nestedFriends2 shapes from
  // yamlRendererIndentationWidth2.yml: outer sequence whose elements are
  // sequences or single-member objects.
  let value : Value = ObjectValue([
    ValueMember::{
      name: "nestedFriends",
      value: ListingValue([
        ListingValue([StringValue("barn owl"), StringValue("parrot")]),
        ListingValue([StringValue("elf owl"), StringValue("albatross")]),
      ]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "nestedFriends2",
      value: ListingValue([
        ObjectValue([
          ValueMember::{
            name: "name",
            value: StringValue("barn owl"),
            source: None,
            annotations: [],
          },
        ]),
        ObjectValue([
          ValueMember::{
            name: "name",
            value: StringValue("parrot"),
            source: None,
            annotations: [],
          },
        ]),
      ]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|nestedFriends:
      #|- - barn owl
      #|  - parrot
      #|- - elf owl
      #|  - albatross
      #|nestedFriends2:
      #|- name: barn owl
      #|- name: parrot
      #|
    ),
  )
}

///|
test "render YAML sequence of multi-member mappings" {
  let value : Value = ListingValue([
    ObjectValue([
      ValueMember::{
        name: "name",
        value: StringValue("alice"),
        source: None,
        annotations: [],
      },
      ValueMember::{
        name: "age",
        value: IntValue(30),
        source: None,
        annotations: [],
      },
    ]),
    ObjectValue([
      ValueMember::{
        name: "name",
        value: StringValue("bob"),
        source: None,
        annotations: [],
      },
      ValueMember::{
        name: "age",
        value: IntValue(25),
        source: None,
        annotations: [],
      },
    ]),
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|- name: alice
      #|  age: 30
      #|- name: bob
      #|  age: 25
      #|
    ),
  )
}

///|
test "render empty composites as YAML" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "a3",
      value: ListingValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "b2",
      value: MappingValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "b3",
      value: ObjectValue([]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "nested",
      value: ObjectValue([
        ValueMember::{
          name: "a3",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b2",
          value: MappingValue([]),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(value),
    content=(
      #|a3: []
      #|b2: {}
      #|b3: {}
      #|nested:
      #|  a3: []
      #|  b2: {}
      #|
    ),
  )
}

///|
test "YAML rendered top-level Pkl matches the yamlRenderer1 fixture shape" {
  // Apple Pkl's `pkl eval -f yaml` on the upstream `yamlRenderer1.yml.pkl`
  // would emit this shape, modulo the indentWidth default (we keep 2 spaces
  // for now; the upstream fixture uses indentWidth=4 explicitly).
  let source = "pigeon {\n  name = \"pigeon\"\n  age = 30\n}\n"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_yaml(value),
    content=(
      #|pigeon:
      #|  name: pigeon
      #|  age: 30
      #|
    ),
  )
}

///|
test "Listing.length and isEmpty are properties" {
  // `xs.length` and `xs.isEmpty` are property-style on Apple Pkl Listings.
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nlen = xs.length") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "len",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nempty = xs.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing { 1 }\nempty = xs.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.first / last / distinct properties" {
  assert_true(
    eval_source("xs = new Listing { 10; 20; 30 }\nf = xs.first\nl = xs.last") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(10), IntValue(20), IntValue(30)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "f",
          value: IntValue(10),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "l",
          value: IntValue(30),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing { 1; 2; 2; 3; 1 }\nd = xs.distinct") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(1),
            IntValue(2),
            IntValue(2),
            IntValue(3),
            IntValue(1),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.contains and reverse methods" {
  assert_true(
    eval_source(
      "xs = new Listing { 1; 2; 3 }\nhas = xs.contains(2)\nmissing = xs.contains(99)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "has",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "missing",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nr = xs.reverse()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "r",
          value: ListingValue([IntValue(3), IntValue(2), IntValue(1)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.take and drop methods" {
  assert_true(
    eval_source(
      "xs = new Listing { 1; 2; 3; 4; 5 }\nt = xs.take(2)\nd = xs.drop(3)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(1),
            IntValue(2),
            IntValue(3),
            IntValue(4),
            IntValue(5),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "t",
          value: ListingValue([IntValue(1), IntValue(2)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d",
          value: ListingValue([IntValue(4), IntValue(5)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // take more than length / drop more than length saturate at length.
  assert_true(
    eval_source("xs = new Listing { 1; 2 }\nt = xs.take(10)\nd = xs.drop(10)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "t",
          value: ListingValue([IntValue(1), IntValue(2)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.join method" {
  assert_true(
    eval_source("xs = new Listing { \"a\"; \"b\"; \"c\" }\nj = xs.join(\", \")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            StringValue("a"),
            StringValue("b"),
            StringValue("c"),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "j",
          value: StringValue("a, b, c"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nj = xs.join(\"-\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "j",
          value: StringValue("1-2-3"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nj = xs.join(\"-\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "j",
          value: StringValue(""),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.map applies a callable to each element" {
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nys = xs.map((x) -> x * 10)") ==
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
          value: ListingValue([IntValue(10), IntValue(20), IntValue(30)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.filter keeps elements that pass the predicate" {
  assert_true(
    eval_source(
      "xs = new Listing { 1; 2; 3; 4; 5 }\nys = xs.filter((x) -> x > 2)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(1),
            IntValue(2),
            IntValue(3),
            IntValue(4),
            IntValue(5),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "ys",
          value: ListingValue([IntValue(3), IntValue(4), IntValue(5)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing.fold reduces to a single accumulated value" {
  assert_true(
    eval_source(
      "xs = new Listing { 1; 2; 3; 4 }\nsum = xs.fold(0, (acc, x) -> acc + x)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(1),
            IntValue(2),
            IntValue(3),
            IntValue(4),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "sum",
          value: IntValue(10),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nsum = xs.fold(42, (acc, x) -> acc + x)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "sum",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Listing builtins compose through higher-order callable chains" {
  // Stack a map / filter / fold pipeline to confirm the dispatcher handles
  // method results being passed back into other listing methods.
  assert_true(
    eval_source(
      "xs = new Listing { 1; 2; 3; 4; 5 }\nresult = xs.filter((x) -> x > 1).map((x) -> x * x).fold(0, (acc, x) -> acc + x)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(1),
            IntValue(2),
            IntValue(3),
            IntValue(4),
            IntValue(5),
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: IntValue(54),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Mapping.length and isEmpty are properties" {
  assert_true(
    eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }\nlen = m.length\nempty = m.isEmpty",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([
            ValueEntry::{ key: StringValue("a"), value: IntValue(1) },
            ValueEntry::{ key: StringValue("b"), value: IntValue(2) },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "len",
          value: IntValue(2),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("m = new Mapping {}\nempty = m.isEmpty\nlen = m.length") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "len",
          value: IntValue(0),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Mapping.keys projects to Set and values project to Listing" {
  // Apple Pkl exposes `keys` as a `Set<K>` and `values` as a listing-like
  // projection in declaration order.
  assert_true(
    eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2; [\"c\"] = 3 }\nks = m.keys\nvs = m.values",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([
            ValueEntry::{ key: StringValue("a"), value: IntValue(1) },
            ValueEntry::{ key: StringValue("b"), value: IntValue(2) },
            ValueEntry::{ key: StringValue("c"), value: IntValue(3) },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "ks",
          value: SetValue([StringValue("a"), StringValue("b"), StringValue("c")]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "vs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Mapping.containsKey and getOrNull methods" {
  assert_true(
    eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }\nhas = m.containsKey(\"a\")\nmissing = m.containsKey(\"x\")\nval = m.getOrNull(\"b\")\nnone = m.getOrNull(\"x\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([
            ValueEntry::{ key: StringValue("a"), value: IntValue(1) },
            ValueEntry::{ key: StringValue("b"), value: IntValue(2) },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "has",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "missing",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "val",
          value: IntValue(2),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "none",
          value: NullValue,
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Mapping.fold reduces with (acc, key, value) callback" {
  // Apple Pkl's Mapping.fold passes (accumulator, key, value) per entry.
  assert_true(
    eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2; [\"c\"] = 3 }\nsum = m.fold(0, (acc, k, v) -> acc + v)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([
            ValueEntry::{ key: StringValue("a"), value: IntValue(1) },
            ValueEntry::{ key: StringValue("b"), value: IntValue(2) },
            ValueEntry::{ key: StringValue("c"), value: IntValue(3) },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "sum",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("m = new Mapping {}\nsum = m.fold(42, (acc, k, v) -> acc + v)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "sum",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Mapping builtins chain through Listing pipelines" {
  assert_true(
    eval_source(
      "m = new Mapping { [\"a\"] = 1; [\"b\"] = 2; [\"c\"] = 3 }\nresult = m.values.filter((v) -> v > 1).fold(0, (acc, v) -> acc + v)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "m",
          value: MappingValue([
            ValueEntry::{ key: StringValue("a"), value: IntValue(1) },
            ValueEntry::{ key: StringValue("b"), value: IntValue(2) },
            ValueEntry::{ key: StringValue("c"), value: IntValue(3) },
          ]),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String.length and isEmpty are properties" {
  assert_true(
    eval_source("s = \"hello\"\nlen = s.length\nempty = s.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "len",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("s = \"\"\nlen = s.length\nempty = s.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue(""),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "len",
          value: IntValue(0),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "empty",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String case-conversion methods" {
  assert_true(
    eval_source("s = \"Hello\"\nup = s.toUpperCase()\ndown = s.toLowerCase()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("Hello"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "up",
          value: StringValue("HELLO"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "down",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String search predicates" {
  assert_true(
    eval_source(
      "s = \"hello world\"\nhas = s.contains(\"world\")\nstart = s.startsWith(\"hello\")\nend = s.endsWith(\"world\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("hello world"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "has",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "start",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "end",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "s = \"hello\"\nmissing = s.contains(\"xyz\")\nbad_start = s.startsWith(\"world\")\nbad_end = s.endsWith(\"world\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "missing",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "bad_start",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "bad_end",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
/// PKL-149: Apple Pkl's `String.indexOf` raises when the substring is
/// absent (fixture `api/string` wraps the missing case in
/// `module.catch`). For absence-tolerant callers, `indexOfOrNull` and
/// `lastIndexOfOrNull` return Null.
test "String.indexOf returns position or raises on miss" {
  assert_true(
    eval_source("s = \"hello world\"\nat = s.indexOf(\"world\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("hello world"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "at",
          value: IntValue(6),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // Missing substring raises.
  let outcome = eval_source("s = \"hello world\"\nmissing = s.indexOf(\"xyz\")")
  assert_true(outcome is EvalError(_))
}

///|
test "String.replaceAll and replaceFirst" {
  assert_true(
    eval_source(
      "s = \"banana\"\nall = s.replaceAll(\"a\", \"o\")\nfirst = s.replaceFirst(\"a\", \"o\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("banana"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "all",
          value: StringValue("bonono"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "first",
          value: StringValue("bonana"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String.take and drop substring methods" {
  assert_true(
    eval_source(
      "s = \"hello\"\nt = s.take(2)\nd = s.drop(2)\nt0 = s.take(0)\nd0 = s.drop(0)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "t",
          value: StringValue("he"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d",
          value: StringValue("llo"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "t0",
          value: StringValue(""),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d0",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // Out-of-range arguments saturate at the string bounds, mirroring Listing.take/drop.
  assert_true(
    eval_source("s = \"ab\"\nt = s.take(99)\nd = s.drop(99)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("ab"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "t",
          value: StringValue("ab"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "d",
          value: StringValue(""),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String.split projects to a List" {
  assert_true(
    eval_source("s = \"a,b,c\"\nparts = s.split(\",\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("a,b,c"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "parts",
          value: ListValue([
            StringValue("a"),
            StringValue("b"),
            StringValue("c"),
          ]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // Split on an absent separator yields a single-element List.
  assert_true(
    eval_source("s = \"abc\"\nparts = s.split(\",\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("abc"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "parts",
          value: ListValue([StringValue("abc")]),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String.padStart and padEnd reach a target width" {
  assert_true(
    eval_source(
      "s = \"7\"\nleft = s.padStart(3, \"0\")\nright = s.padEnd(3, \"x\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("7"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "left",
          value: StringValue("007"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "right",
          value: StringValue("7xx"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // When the string already meets the width, no padding is added.
  assert_true(
    eval_source(
      "s = \"abcd\"\nleft = s.padStart(2, \"-\")\nright = s.padEnd(2, \"-\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("abcd"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "left",
          value: StringValue("abcd"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "right",
          value: StringValue("abcd"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "String builtins compose through Listing pipelines" {
  // Split into a Listing then pipe through Listing builtins.
  assert_true(
    eval_source(
      "s = \"alpha,beta,gamma,delta\"\nresult = s.split(\",\").filter((p) -> p.length > 4).map((p) -> p.toUpperCase()).join(\";\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "s",
          value: StringValue("alpha,beta,gamma,delta"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: StringValue("ALPHA;GAMMA;DELTA"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Int.abs, isEven, and isOdd are properties" {
  assert_true(
    eval_source(
      "n = -7\np = 4\nabs_n = n.abs\nabs_p = p.abs\nodd = n.isOdd\neven = p.isEven",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "n",
          value: IntValue(-7),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "p",
          value: IntValue(4),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "abs_n",
          value: IntValue(7),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "abs_p",
          value: IntValue(4),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "odd",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "even",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  assert_true(
    eval_source("zero = 0\nev = zero.isEven\nod = zero.isOdd") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "zero",
          value: IntValue(0),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "ev",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "od",
          value: BoolValue(false),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "Int.toString() and toString(radix) methods" {
  assert_true(
    eval_source(
      "n = 255\ndec = n.toString()\nhex = n.toString(16)\nbin = n.toString(2)\noct = n.toString(8)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "n",
          value: IntValue(255),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "dec",
          value: StringValue("255"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "hex",
          value: StringValue("ff"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "bin",
          value: StringValue("11111111"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "oct",
          value: StringValue("377"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // Negative numbers get a leading `-`.
  assert_true(
    eval_source("n = -42\ndec = n.toString()\nhex = n.toString(16)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "n",
          value: IntValue(-42),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "dec",
          value: StringValue("-42"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "hex",
          value: StringValue("-2a"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
  // Zero stays "0" in every radix.
  assert_true(
    eval_source(
      "n = 0\ndec = n.toString()\nhex = n.toString(16)\nbin = n.toString(2)",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "n",
          value: IntValue(0),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "dec",
          value: StringValue("0"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "hex",
          value: StringValue("0"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "bin",
          value: StringValue("0"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
