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
          value: ObjectValue([ValueMember::{ name: "a", value: IntValue(6) }]),
        },
        ValueMember::{
          name: "res2",
          value: StringValue(
            "type annotation X member a constraint isGreaterThan rejects 5",
          ),
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
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{ name: "age", value: IntValue(30) },
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
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{
      name: "friends",
      value: ListingValue([StringValue("barn owl"), StringValue("parrot")]),
    },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{ name: "street", value: StringValue("Norton St.") },
        ValueMember::{ name: "zip", value: IntValue(12345) },
      ]),
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
    ValueMember::{ name: "a3", value: ListingValue([]) },
    ValueMember::{ name: "b2", value: MappingValue([]) },
    ValueMember::{ name: "b3", value: ObjectValue([]) },
    ValueMember::{
      name: "nested",
      value: ObjectValue([
        ValueMember::{ name: "a3", value: ListingValue([]) },
        ValueMember::{ name: "b2", value: MappingValue([]) },
      ]),
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
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{ name: "age", value: IntValue(30) },
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
  inspect(render_value_as_yaml(ListingValue([])), content="[]\n")
  inspect(render_value_as_yaml(MappingValue([])), content="{}\n")
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
test "YAML Mapping keys coerce non-string values to strings" {
  inspect(
    render_value_as_yaml(
      MappingValue([
        ValueEntry::{ key: IntValue(1), value: StringValue("a") },
        ValueEntry::{ key: BoolValue(true), value: StringValue("b") },
        ValueEntry::{ key: NullValue, value: StringValue("c") },
      ]),
    ),
    content=(
      #|'1': a
      #|'true': b
      #|'null': c
      #|
    ),
  )
}

///|
test "render nested Pkl objects and arrays as YAML" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{
      name: "friends",
      value: ListingValue([StringValue("barn owl"), StringValue("parrot")]),
    },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{ name: "street", value: StringValue("Norton St.") },
        ValueMember::{ name: "zip", value: IntValue(12345) },
      ]),
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
    },
    ValueMember::{
      name: "nestedFriends2",
      value: ListingValue([
        ObjectValue([
          ValueMember::{ name: "name", value: StringValue("barn owl") },
        ]),
        ObjectValue([
          ValueMember::{ name: "name", value: StringValue("parrot") },
        ]),
      ]),
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
      ValueMember::{ name: "name", value: StringValue("alice") },
      ValueMember::{ name: "age", value: IntValue(30) },
    ]),
    ObjectValue([
      ValueMember::{ name: "name", value: StringValue("bob") },
      ValueMember::{ name: "age", value: IntValue(25) },
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
    ValueMember::{ name: "a3", value: ListingValue([]) },
    ValueMember::{ name: "b2", value: MappingValue([]) },
    ValueMember::{ name: "b3", value: ObjectValue([]) },
    ValueMember::{
      name: "nested",
      value: ObjectValue([
        ValueMember::{ name: "a3", value: ListingValue([]) },
        ValueMember::{ name: "b2", value: MappingValue([]) },
      ]),
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
        },
        ValueMember::{ name: "len", value: IntValue(3) },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nempty = xs.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "xs", value: ListingValue([]) },
        ValueMember::{ name: "empty", value: BoolValue(true) },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing { 1 }\nempty = xs.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "xs", value: ListingValue([IntValue(1)]) },
        ValueMember::{ name: "empty", value: BoolValue(false) },
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
        },
        ValueMember::{ name: "f", value: IntValue(10) },
        ValueMember::{ name: "l", value: IntValue(30) },
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
        },
        ValueMember::{
          name: "d",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
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
        },
        ValueMember::{ name: "has", value: BoolValue(true) },
        ValueMember::{ name: "missing", value: BoolValue(false) },
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
        },
        ValueMember::{
          name: "r",
          value: ListingValue([IntValue(3), IntValue(2), IntValue(1)]),
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
        },
        ValueMember::{
          name: "t",
          value: ListingValue([IntValue(1), IntValue(2)]),
        },
        ValueMember::{
          name: "d",
          value: ListingValue([IntValue(4), IntValue(5)]),
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
        },
        ValueMember::{
          name: "t",
          value: ListingValue([IntValue(1), IntValue(2)]),
        },
        ValueMember::{ name: "d", value: ListingValue([]) },
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
        },
        ValueMember::{ name: "j", value: StringValue("a, b, c") },
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
        },
        ValueMember::{ name: "j", value: StringValue("1-2-3") },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nj = xs.join(\"-\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "xs", value: ListingValue([]) },
        ValueMember::{ name: "j", value: StringValue("") },
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
        },
        ValueMember::{
          name: "ys",
          value: ListingValue([IntValue(10), IntValue(20), IntValue(30)]),
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
        },
        ValueMember::{
          name: "ys",
          value: ListingValue([IntValue(3), IntValue(4), IntValue(5)]),
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
        },
        ValueMember::{ name: "sum", value: IntValue(10) },
      ]),
    ),
  )
  assert_true(
    eval_source("xs = new Listing {}\nsum = xs.fold(42, (acc, x) -> acc + x)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "xs", value: ListingValue([]) },
        ValueMember::{ name: "sum", value: IntValue(42) },
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
        },
        ValueMember::{ name: "result", value: IntValue(54) },
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
        },
        ValueMember::{ name: "len", value: IntValue(2) },
        ValueMember::{ name: "empty", value: BoolValue(false) },
      ]),
    ),
  )
  assert_true(
    eval_source("m = new Mapping {}\nempty = m.isEmpty\nlen = m.length") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "m", value: MappingValue([]) },
        ValueMember::{ name: "empty", value: BoolValue(true) },
        ValueMember::{ name: "len", value: IntValue(0) },
      ]),
    ),
  )
}

///|
test "Mapping.keys and values project to Listings" {
  // Apple Pkl exposes `keys` as a `Set<K>`; we don't have a distinct Set
  // value yet, so the projection lands as a `Listing<K>` preserving the
  // declaration order. `values` returns a `Listing<V>` in declaration order
  // too.
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
        },
        ValueMember::{
          name: "ks",
          value: ListingValue([
            StringValue("a"),
            StringValue("b"),
            StringValue("c"),
          ]),
        },
        ValueMember::{
          name: "vs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
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
        },
        ValueMember::{ name: "has", value: BoolValue(true) },
        ValueMember::{ name: "missing", value: BoolValue(false) },
        ValueMember::{ name: "val", value: IntValue(2) },
        ValueMember::{ name: "none", value: NullValue },
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
        },
        ValueMember::{ name: "sum", value: IntValue(6) },
      ]),
    ),
  )
  assert_true(
    eval_source("m = new Mapping {}\nsum = m.fold(42, (acc, k, v) -> acc + v)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "m", value: MappingValue([]) },
        ValueMember::{ name: "sum", value: IntValue(42) },
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
        },
        ValueMember::{ name: "result", value: IntValue(5) },
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
        ValueMember::{ name: "s", value: StringValue("hello") },
        ValueMember::{ name: "len", value: IntValue(5) },
        ValueMember::{ name: "empty", value: BoolValue(false) },
      ]),
    ),
  )
  assert_true(
    eval_source("s = \"\"\nlen = s.length\nempty = s.isEmpty") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("") },
        ValueMember::{ name: "len", value: IntValue(0) },
        ValueMember::{ name: "empty", value: BoolValue(true) },
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
        ValueMember::{ name: "s", value: StringValue("Hello") },
        ValueMember::{ name: "up", value: StringValue("HELLO") },
        ValueMember::{ name: "down", value: StringValue("hello") },
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
        ValueMember::{ name: "s", value: StringValue("hello world") },
        ValueMember::{ name: "has", value: BoolValue(true) },
        ValueMember::{ name: "start", value: BoolValue(true) },
        ValueMember::{ name: "end", value: BoolValue(true) },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "s = \"hello\"\nmissing = s.contains(\"xyz\")\nbad_start = s.startsWith(\"world\")\nbad_end = s.endsWith(\"world\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("hello") },
        ValueMember::{ name: "missing", value: BoolValue(false) },
        ValueMember::{ name: "bad_start", value: BoolValue(false) },
        ValueMember::{ name: "bad_end", value: BoolValue(false) },
      ]),
    ),
  )
}

///|
test "String.indexOf returns position or -1" {
  // Apple Pkl returns -1 when the substring is absent rather than null.
  assert_true(
    eval_source(
      "s = \"hello world\"\nat = s.indexOf(\"world\")\nmissing = s.indexOf(\"xyz\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("hello world") },
        ValueMember::{ name: "at", value: IntValue(6) },
        ValueMember::{ name: "missing", value: IntValue(-1) },
      ]),
    ),
  )
}

///|
test "String.replaceAll and replaceFirst" {
  assert_true(
    eval_source(
      "s = \"banana\"\nall = s.replaceAll(\"a\", \"o\")\nfirst = s.replaceFirst(\"a\", \"o\")",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("banana") },
        ValueMember::{ name: "all", value: StringValue("bonono") },
        ValueMember::{ name: "first", value: StringValue("bonana") },
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
        ValueMember::{ name: "s", value: StringValue("hello") },
        ValueMember::{ name: "t", value: StringValue("he") },
        ValueMember::{ name: "d", value: StringValue("llo") },
        ValueMember::{ name: "t0", value: StringValue("") },
        ValueMember::{ name: "d0", value: StringValue("hello") },
      ]),
    ),
  )
  // Out-of-range arguments saturate at the string bounds, mirroring Listing.take/drop.
  assert_true(
    eval_source("s = \"ab\"\nt = s.take(99)\nd = s.drop(99)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("ab") },
        ValueMember::{ name: "t", value: StringValue("ab") },
        ValueMember::{ name: "d", value: StringValue("") },
      ]),
    ),
  )
}

///|
test "String.split projects to a Listing" {
  assert_true(
    eval_source("s = \"a,b,c\"\nparts = s.split(\",\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("a,b,c") },
        ValueMember::{
          name: "parts",
          value: ListingValue([
            StringValue("a"),
            StringValue("b"),
            StringValue("c"),
          ]),
        },
      ]),
    ),
  )
  // Split on an absent separator yields a single-element listing.
  assert_true(
    eval_source("s = \"abc\"\nparts = s.split(\",\")") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "s", value: StringValue("abc") },
        ValueMember::{
          name: "parts",
          value: ListingValue([StringValue("abc")]),
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
        ValueMember::{ name: "s", value: StringValue("7") },
        ValueMember::{ name: "left", value: StringValue("007") },
        ValueMember::{ name: "right", value: StringValue("7xx") },
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
        ValueMember::{ name: "s", value: StringValue("abcd") },
        ValueMember::{ name: "left", value: StringValue("abcd") },
        ValueMember::{ name: "right", value: StringValue("abcd") },
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
        ValueMember::{ name: "s", value: StringValue("alpha,beta,gamma,delta") },
        ValueMember::{ name: "result", value: StringValue("ALPHA;GAMMA;DELTA") },
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
        ValueMember::{ name: "n", value: IntValue(-7) },
        ValueMember::{ name: "p", value: IntValue(4) },
        ValueMember::{ name: "abs_n", value: IntValue(7) },
        ValueMember::{ name: "abs_p", value: IntValue(4) },
        ValueMember::{ name: "odd", value: BoolValue(true) },
        ValueMember::{ name: "even", value: BoolValue(true) },
      ]),
    ),
  )
  assert_true(
    eval_source("zero = 0\nev = zero.isEven\nod = zero.isOdd") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "zero", value: IntValue(0) },
        ValueMember::{ name: "ev", value: BoolValue(true) },
        ValueMember::{ name: "od", value: BoolValue(false) },
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
        ValueMember::{ name: "n", value: IntValue(255) },
        ValueMember::{ name: "dec", value: StringValue("255") },
        ValueMember::{ name: "hex", value: StringValue("ff") },
        ValueMember::{ name: "bin", value: StringValue("11111111") },
        ValueMember::{ name: "oct", value: StringValue("377") },
      ]),
    ),
  )
  // Negative numbers get a leading `-`.
  assert_true(
    eval_source("n = -42\ndec = n.toString()\nhex = n.toString(16)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "n", value: IntValue(-42) },
        ValueMember::{ name: "dec", value: StringValue("-42") },
        ValueMember::{ name: "hex", value: StringValue("-2a") },
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
        ValueMember::{ name: "n", value: IntValue(0) },
        ValueMember::{ name: "dec", value: StringValue("0") },
        ValueMember::{ name: "hex", value: StringValue("0") },
        ValueMember::{ name: "bin", value: StringValue("0") },
      ]),
    ),
  )
}

///|
test "Int.toChar() projects a Unicode code point to a String" {
  assert_true(
    eval_source("a = 65\nA = a.toChar()\nz = 122\nlowercase_z = z.toChar()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: IntValue(65) },
        ValueMember::{ name: "A", value: StringValue("A") },
        ValueMember::{ name: "z", value: IntValue(122) },
        ValueMember::{ name: "lowercase_z", value: StringValue("z") },
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
        },
        ValueMember::{ name: "hex_csv", value: StringValue("a,ff,10") },
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
        ValueMember::{ name: "max32", value: IntValue(2147483647) },
        ValueMember::{ name: "min32", value: IntValue(-2147483648) },
        ValueMember::{ name: "max", value: IntValue(2147483647) },
        ValueMember::{ name: "min", value: IntValue(-2147483648) },
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
        ValueMember::{ name: "abs_neg", value: IntValue(7) },
        ValueMember::{ name: "abs_pos", value: IntValue(4) },
        ValueMember::{ name: "mn", value: IntValue(3) },
        ValueMember::{ name: "mx", value: IntValue(8) },
        ValueMember::{ name: "mn_eq", value: IntValue(5) },
        ValueMember::{ name: "mx_eq", value: IntValue(5) },
      ]),
    ),
  )
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
    Some(ObjectValue([ValueMember::{ name: "value", value: IntValue(5) }])),
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
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(3.14) }])),
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
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: BoolValue(true) }])),
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
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(3.14) }])),
  )
}

///|
test "Number annotation accepts Int and Float" {
  assert_true(
    eval_source("a: Number = 5\nb: Number = 2.5") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: IntValue(5) },
        ValueMember::{ name: "b", value: FloatValue(2.5) },
      ]),
    ),
  )
}

///|
test "Float constraint predicate accepts in-range Float" {
  assert_true(
    eval_source("res: Float(isPositive) = 1.5") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(1.5) }])),
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
    content="type annotation Float(isPositive) constraint isPositive rejects -0.5",
  )
}

///|
test "Float isBetween accepts inclusive endpoints" {
  assert_true(
    eval_source("res: Float(isBetween(0, 10)) = 5.5") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(5.5) }])),
  )
}

///|
test "PKL-112: Float isBetween accepts Float thresholds in range" {
  assert_true(
    eval_source("res: Float(isBetween(0.5, 1.5)) = 1.0") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(1.0) }])),
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
    content="type annotation Float(isBetween(0.5,1.5)) constraint isBetween rejects 2",
  )
}

///|
test "PKL-112: Float isGreaterThan accepts Float threshold" {
  assert_true(
    eval_source("res: Float(isGreaterThan(0.5)) = 0.75") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: FloatValue(0.75) }])),
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
    content="type annotation Float(isLessThan(1.5)) constraint isLessThan rejects 2",
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
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: BoolValue(true) }])),
  )
}

///|
test "PKL-114: is Float evaluates to true for Float value" {
  assert_true(
    eval_source("res = 1.5 is Float") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: BoolValue(true) }])),
  )
}

///|
test "PKL-114: is Int evaluates to false for String value" {
  assert_true(
    eval_source("res = \"x\" is Int") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: BoolValue(false) }])),
  )
}

///|
test "PKL-114: is Number evaluates to true for Int and Float values" {
  assert_true(
    eval_source("a = 5 is Number\nb = 1.5 is Number\nc = \"x\" is Number") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: BoolValue(true) },
        ValueMember::{ name: "b", value: BoolValue(true) },
        ValueMember::{ name: "c", value: BoolValue(false) },
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
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: IntValue(6) }])),
  )
  assert_true(
    eval_source(
      "function f(x: Number): Int = if (x is Int) x + 1 else 0\nres = f(2.5)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: IntValue(0) }])),
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
test "PKL-134: Listing.toList() returns same elements" {
  assert_true(
    eval_source("xs = new Listing { 1; 2; 3 }\nys = xs.toList()") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
        },
        ValueMember::{
          name: "ys",
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
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
  guard members[1].value is ListingValue(ys) else { panic() }
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
  guard members[1].value is ListingValue(items) else { panic() }
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
test "PKL-139: List(...) constructor produces Listing" {
  guard eval_source("xs = List(1, 2, 3)") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="3")
}

///|
test "PKL-139: List() with no args produces empty Listing" {
  guard eval_source("xs = List()") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="0")
}

///|
test "PKL-139: Set(...) deduplicates arguments" {
  guard eval_source("xs = Set(1, 2, 2, 3, 3, 3)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="3")
}

///|
test "PKL-139: Map(...) builds Mapping from alternating args" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MappingValue(entries) else { panic() }
  inspect(entries.length(), content="2")
}

///|
test "PKL-139: Pair(a, b) collapses to 2-element Listing" {
  guard eval_source("p = Pair(\"first\", \"second\")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="2")
}

///|
test "PKL-140: external modifier on property declaration" {
  guard typecheck_source("external minInt: Int") is TypeOk(_) else { panic() }
}

///|
test "PKL-140: abstract property slot skipped at evaluation" {
  guard eval_source("foo: Int?\nbar = 5") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  inspect(members.length(), content="1")
  inspect(members[0].name, content="bar")
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
  let mut count_value = -1
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
test "PKL-128c: comma-composed predicates accepted with whitespace" {
  guard typecheck_source("x: Int(isPositive,  isLessThan(10) ) = 5")
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-128c: composition rejects when upper bound violated" {
  guard eval_source("x: Int(isPositive, isLessThan(10)) = 15")
    is EvalError(diagnostics) else {
    panic()
  }
  let mut hit = false
  for diagnostic in diagnostics {
    if diagnostic.message.contains("isLessThan") {
      hit = true
    }
  }
  assert_true(hit)
}

///|
test "PKL-128c: composition rejects when lower bound violated" {
  guard eval_source("x: Int(isPositive, isLessThan(10)) = -1")
    is EvalError(diagnostics) else {
    panic()
  }
  let mut hit = false
  for diagnostic in diagnostics {
    if diagnostic.message.contains("isPositive") {
      hit = true
    }
  }
  assert_true(hit)
}

///|
test "PKL-128b: scientific notation Float literal parses" {
  guard eval_source("x = 1e10") is EvalOk(ObjectValue(members)) else { panic() }
  guard members[0].value is FloatValue(d) else { panic() }
  inspect(d, content="10000000000")
}

///|
test "PKL-128b: negative exponent scientific Float" {
  guard eval_source("x = 2.5e-3") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is FloatValue(d) else { panic() }
  inspect(d, content="0.0025")
}

///|
test "PKL-128b: triple-quoted heredoc strips dedent" {
  guard eval_source("greeting = \"\"\"\n  hello\n  world\n  \"\"\"")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is StringValue(s) else { panic() }
  assert_eq(s, "hello\nworld\n")
}

///|
test "PKL-128a: string interpolation evaluates each segment" {
  guard eval_source(
      "name = \"alpha\"\ncount = 3\nmsg = \"hello \\(name), count is \\(count + 1)\"",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut msg = ""
  for entry in members {
    if entry.name == "msg" {
      match entry.value {
        StringValue(s) => msg = s
        _ => ()
      }
    }
  }
  inspect(msg, content="hello alpha, count is 4")
}

///|
test "PKL-128a: string with no interpolation stays a plain StringLiteral" {
  guard eval_source("msg = \"plain text\"") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is StringValue(s) else { panic() }
  inspect(s, content="plain text")
}

///|
test "PKL-128a: interpolation passes through balanced parens and inner strings" {
  guard eval_source(
      "xs = new Listing { \"a\"; \"b\" }\nmsg = \"items: \\(xs.join(\", \"))\"",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut msg = ""
  for entry in members {
    if entry.name == "msg" {
      match entry.value {
        StringValue(s) => msg = s
        _ => ()
      }
    }
  }
  inspect(msg, content="items: a, b")
}

///|
test "PKL-107: parser diagnostic carries a non-negative start offset" {
  let parsed = @pkl.parse_source("bad = (1 +")
  assert_true(parsed.diagnostics.length() > 0)
  let diagnostic = parsed.diagnostics[0]
  assert_true(diagnostic.start >= 0)
}

///|
test "PKL-105: nested-path converter rewrites a nested value" {
  guard eval_source(
      "server { port = 8080 }\noutput { renderer = new JsonRenderer { converters { [\"server.port\"] = (p) -> p + 1 } } }",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut port = -1
  for entry in members {
    if entry.name == "server" {
      match entry.value {
        ObjectValue(server_members) =>
          for sub in server_members {
            if sub.name == "port" {
              match sub.value {
                IntValue(n) => port = n
                _ => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  inspect(port, content="8081")
}

///|
test "PKL-104: output block is stripped from the rendered envelope" {
  guard eval_source(
      "name = \"alpha\"\noutput { renderer = new JsonRenderer {} }",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  // The eval result still carries the `output` member; the CLI's
  // `extract_output_value` strips it before rendering. Verify both
  // halves: the raw eval still has 2 entries, with `output` present.
  inspect(members.length(), content="2")
  let mut has_output = false
  for entry in members {
    if entry.name == "output" {
      has_output = true
    }
  }
  assert_true(has_output)
}

///|
test "Number constraint predicate accepts both Int and Float" {
  assert_true(
    eval_source("a: Number(isPositive) = 3\nb: Number(isPositive) = 0.5") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: IntValue(3) },
        ValueMember::{ name: "b", value: FloatValue(0.5) },
      ]),
    ),
  )
}

///|
test "PCF renders Float with trailing .0 when integral" {
  inspect(render_value(FloatValue(42.0)), content="42.0")
  inspect(render_value(FloatValue(3.14)), content="3.14")
  inspect(render_value(FloatValue(0.0 - 1.5)), content="-1.5")
}

///|
test "read built-in resolves env: scheme to the host env variable" {
  // PKL-098 minimal slice: `read("env:NAME")` consults the host
  // environment via `moonbitlang/core/env`. Setting the variable first
  // pins the assertion regardless of the ambient shell.
  @env.set_env_var("PKL_MBT_TEST_VAR", "hello")
  assert_true(
    eval_source("res = read(\"env:PKL_MBT_TEST_VAR\")") ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "res", value: StringValue("hello") }]),
    ),
  )
  @env.unset_env_var("PKL_MBT_TEST_VAR")
}

///|
test "read built-in errors on missing env: variable" {
  @env.unset_env_var("PKL_MBT_TEST_MISSING")
  guard eval_source("res = read(\"env:PKL_MBT_TEST_MISSING\")")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="read: env variable PKL_MBT_TEST_MISSING is not set",
  )
}

///|
test "read built-in rejects unsupported schemes" {
  guard eval_source("res = read(\"file:/etc/hosts\")") is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="read: scheme file: is not allowed by the sandbox policy",
  )
}

///|
test "read built-in rejects URIs without a scheme" {
  guard eval_source("res = read(\"foo\")") is EvalError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="read: missing URI scheme in \"foo\"")
}

///|
test "read built-in rejects non-String arguments" {
  guard eval_source("res = read(7)") is EvalError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="read expects a String argument")
}

///|
test "read built-in rejects wrong arity" {
  guard eval_source("res = read()") is EvalError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="read expects exactly one argument")
}

///|
test "read is shadowable by a local binding" {
  @env.set_env_var("PKL_MBT_TEST_SHADOW", "ambient")
  guard eval_source(
      "read = (uri) -> uri\nres = read(\"env:PKL_MBT_TEST_SHADOW\")",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut res_value : Value? = None
  for entry in members {
    if entry.name == "res" {
      res_value = Some(entry.value)
    }
  }
  assert_true(res_value == Some(StringValue("env:PKL_MBT_TEST_SHADOW")))
  @env.unset_env_var("PKL_MBT_TEST_SHADOW")
}

///|
test "throw built-in aborts evaluation with the given message" {
  // PKL-084 split-1: `throw("...")` evaluates the message, pushes a
  // diagnostic carrying the message verbatim, and returns no value. The
  // diagnostic surface lines up with the existing constrained-rejection
  // path so `test.catch` could capture it as the surfacing message.
  guard eval_source("res = throw(\"boom\")") is EvalError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="boom")
}

///|
test "throw built-in rejects non-String arguments" {
  guard eval_source("res = throw(7)") is EvalError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="throw expects a String argument")
}

///|
test "throw built-in rejects wrong arity" {
  guard eval_source("res = throw(\"a\", \"b\")") is EvalError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="throw expects exactly one argument")
}

///|
test "throw is shadowable by a local binding" {
  // PKL-084 split-1: the builtin form only kicks in when `throw` is not
  // shadowed by a user binding. Defining `throw` locally as an identity
  // lambda takes precedence, mirroring how `Bytes` / `Regex` honor
  // user-defined shadows. The lambda binding itself shows up in the
  // exported module too; the assertion narrows to the `res` member.
  guard eval_source("throw = (s) -> s\nres = throw(\"keep\")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut res_value : Value? = None
  for entry in members {
    if entry.name == "res" {
      res_value = Some(entry.value)
    }
  }
  assert_true(res_value == Some(StringValue("keep")))
}

///|
test "trace built-in passes the value through unchanged" {
  // PKL-084 split-1: `trace(x)` evaluates `x` and returns it verbatim;
  // a real trace would also stamp a diagnostic (Apple Pkl prints to
  // stderr), which this slice intentionally defers — the value-side
  // semantics ship first because the diagnostic surface needs CLI plumbing
  // to be observable.
  assert_true(
    eval_source("res = trace(42)") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: IntValue(42) }])),
  )
}

///|
test "trace built-in composes inside expressions" {
  assert_true(
    eval_source("res = trace(2) + trace(3)") ==
    EvalOk(ObjectValue([ValueMember::{ name: "res", value: IntValue(5) }])),
  )
}

///|
test "trace built-in rejects wrong arity" {
  guard eval_source("res = trace(1, 2)") is EvalError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="trace expects exactly one argument")
}

///|
test "pkl:reflect exposes builtin type mirror constants" {
  // PKL-080 minimal slice: `pkl:reflect` is implemented as a thin Pkl source
  // stub (mirror constants + factory lambdas), the same shape `pkl:math` uses.
  // Apple's full reflect.pkl has ~20 `external` declarations our evaluator
  // cannot satisfy; the minimal subset here lets fixtures that only inspect
  // type names round-trip through `import "pkl:reflect"`.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nintMirror = reflect.intType\nstringMirror = reflect.stringType\nbooleanMirror = reflect.booleanType",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "intMirror", value: StringValue("pkl.base#Int") },
        ValueMember::{
          name: "stringMirror",
          value: StringValue("pkl.base#String"),
        },
        ValueMember::{
          name: "booleanMirror",
          value: StringValue("pkl.base#Boolean"),
        },
      ]),
    ),
  )
}

///|
test "pkl:reflect Class factory returns a reflectee container" {
  // PKL-080 minimal slice: the `Class` / `Module` / `TypeAlias` / `Property`
  // factories take a string identifier (rather than a class value) because we
  // do not yet have a `ClassValue` variant to round-trip a class declaration.
  // The container returned exposes the `reflectee` field, which is enough for
  // assertions of the form `reflect.Class("Foo").reflectee == "Foo"`.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclassMirror = reflect.Class(\"Foo\")\nname = classMirror.reflectee\ndecl = reflect.DeclaredType(reflect.Class(\"Bar\"))\ndeclName = decl.referent.reflectee",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "classMirror",
          value: ObjectValue([
            ValueMember::{ name: "reflectee", value: StringValue("Foo") },
          ]),
        },
        ValueMember::{ name: "name", value: StringValue("Foo") },
        ValueMember::{
          name: "decl",
          value: ObjectValue([
            ValueMember::{
              name: "referent",
              value: ObjectValue([
                ValueMember::{ name: "reflectee", value: StringValue("Bar") },
              ]),
            },
          ]),
        },
        ValueMember::{ name: "declName", value: StringValue("Bar") },
      ]),
    ),
  )
}

///|
test "pkl:math composes with Listing builtins" {
  // Use math.max as the reducer in Listing.fold to find the maximum element.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nxs = new Listing { 3; 7; 1; 9; 4 }\nresult = xs.fold(math.minInt, (acc, x) -> math.max(acc, x))",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "xs",
          value: ListingValue([
            IntValue(3),
            IntValue(7),
            IntValue(1),
            IntValue(9),
            IntValue(4),
          ]),
        },
        ValueMember::{ name: "result", value: IntValue(9) },
      ]),
    ),
  )
}

///|
test "null-coalescing operator returns the left side when non-null" {
  assert_true(
    eval_source("a = 7\nb = a ?? 42") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: IntValue(7) },
        ValueMember::{ name: "b", value: IntValue(7) },
      ]),
    ),
  )
}

///|
test "null-coalescing operator falls through to the right side when null" {
  assert_true(
    eval_source("a = null\nb = a ?? 42") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: NullValue },
        ValueMember::{ name: "b", value: IntValue(42) },
      ]),
    ),
  )
}

///|
test "null-coalescing chains right-associatively" {
  assert_true(
    eval_source("a = null\nb = null\nc = a ?? b ?? 99") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "a", value: NullValue },
        ValueMember::{ name: "b", value: NullValue },
        ValueMember::{ name: "c", value: IntValue(99) },
      ]),
    ),
  )
}

///|
test "let-expression introduces a single scoped binding" {
  assert_true(
    eval_source("result = let (x = 5) x * 2") ==
    EvalOk(ObjectValue([ValueMember::{ name: "result", value: IntValue(10) }])),
  )
}

///|
test "let-expression body can reference outer bindings" {
  assert_true(
    eval_source("base = 3\nresult = let (square = base * base) square + 1") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "base", value: IntValue(3) },
        ValueMember::{ name: "result", value: IntValue(10) },
      ]),
    ),
  )
}

///|
test "let-expression nests with inner shadowing" {
  assert_true(
    eval_source("result = let (x = 1) let (x = x + 10) let (x = x * 2) x") ==
    EvalOk(ObjectValue([ValueMember::{ name: "result", value: IntValue(22) }])),
  )
}

///|
test "let-expression composes with null-coalescing" {
  assert_true(
    eval_source("raw = null\nresult = let (fallback = 99) raw ?? fallback") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "raw", value: NullValue },
        ValueMember::{ name: "result", value: IntValue(99) },
      ]),
    ),
  )
}

///|
test "object body when-conditional picks the then-branch on true" {
  assert_true(
    eval_source(
      "result {\n  always = 1\n  when (true) {\n    flag = \"yes\"\n  } else {\n    flag = \"no\"\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "always", value: IntValue(1) },
            ValueMember::{ name: "flag", value: StringValue("yes") },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body when-conditional picks the else-branch on false" {
  assert_true(
    eval_source(
      "result {\n  always = 1\n  when (false) {\n    flag = \"yes\"\n  } else {\n    flag = \"no\"\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "always", value: IntValue(1) },
            ValueMember::{ name: "flag", value: StringValue("no") },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body when-conditional without else drops members on false" {
  // No else-branch means a false condition contributes nothing.
  assert_true(
    eval_source(
      "result {\n  always = 1\n  when (false) {\n    flag = \"yes\"\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "always", value: IntValue(1) },
          ]),
        },
      ]),
    ),
  )
  assert_true(
    eval_source(
      "result {\n  always = 1\n  when (true) {\n    flag = \"yes\"\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "always", value: IntValue(1) },
            ValueMember::{ name: "flag", value: StringValue("yes") },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body when-conditional reads outer bindings" {
  // The when-condition can refer to bindings declared earlier in the module.
  assert_true(
    eval_source(
      "stage = \"prod\"\nresult {\n  when (stage == \"prod\") {\n    replicas = 3\n  } else {\n    replicas = 1\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "stage", value: StringValue("prod") },
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "replicas", value: IntValue(3) },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body when-conditional emits multiple members per branch" {
  assert_true(
    eval_source(
      "result {\n  when (true) {\n    a = 1\n    b = 2\n  } else {\n    c = 3\n  }\n  d = 4\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "a", value: IntValue(1) },
            ValueMember::{ name: "b", value: IntValue(2) },
            ValueMember::{ name: "d", value: IntValue(4) },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator iterates a Listing with one variable" {
  // Three iterations each rebind `last` — the latest write wins via the
  // existing member-merge semantics.
  assert_true(
    eval_source(
      "result {\n  for (x in new Listing { 1; 2; 3 }) {\n    last = x\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([ValueMember::{ name: "last", value: IntValue(3) }]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator binds index and element with two variables" {
  assert_true(
    eval_source(
      "result {\n  for (i, x in new Listing { 10; 20; 30 }) {\n    idx = i\n    val = x\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "idx", value: IntValue(2) },
            ValueMember::{ name: "val", value: IntValue(30) },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator binds key and value over a Mapping" {
  assert_true(
    eval_source(
      "result {\n  for (k, v in new Mapping { [\"a\"] = 1; [\"b\"] = 2 }) {\n    lastKey = k\n    lastVal = v\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "lastKey", value: StringValue("b") },
            ValueMember::{ name: "lastVal", value: IntValue(2) },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator contributes no members on an empty source" {
  assert_true(
    eval_source(
      "result {\n  base = 1\n  for (x in new Listing {}) {\n    extra = x\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([ValueMember::{ name: "base", value: IntValue(1) }]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator sees outer-scope bindings" {
  assert_true(
    eval_source(
      "scale = 10\nresult {\n  for (x in new Listing { 1; 2; 3 }) {\n    last = x * scale\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "scale", value: IntValue(10) },
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{ name: "last", value: IntValue(30) },
          ]),
        },
      ]),
    ),
  )
}

///|
test "object body for-generator composes with when-conditionals" {
  // Skip iterations where the element fails a predicate.
  assert_true(
    eval_source(
      "result {\n  for (x in new Listing { 1; 2; 3; 4 }) {\n    when (x > 2) {\n      last = x\n    }\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([ValueMember::{ name: "last", value: IntValue(4) }]),
        },
      ]),
    ),
  )
}

///|
test "hidden object members are kept out of the PCF render" {
  // `hidden` modifier on an object member retains the member in the
  // evaluated object (so other code can still read it) but the PCF
  // renderer skips it.
  let source = "result {\n  visible = 1\n  hidden invisible = 2\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|result {
      #|  visible = 1
      #|}
    ),
  )
}

///|
test "local object members are kept out of the PCF render" {
  // `local` modifier on an object member receives the same render-side
  // treatment as `hidden` here — both omit the member from rendered output.
  let source = "result {\n  visible = 1\n  local helper = 99\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|result {
      #|  visible = 1
      #|}
    ),
  )
}

///|
test "JSON renderer skips hidden and local members" {
  let source = "result {\n  visible = 1\n  hidden invisible = 2\n  local helper = 3\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "result": {
      #|    "visible": 1
      #|  }
      #|}
    ),
  )
}

///|
test "YAML renderer skips hidden and local members" {
  let source = "result {\n  visible = 1\n  hidden invisible = 2\n  local helper = 3\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_yaml(value),
    content=(
      #|result:
      #|  visible: 1
      #|
    ),
  )
}

///|
test "Properties renderer skips hidden and local members" {
  let source = "result {\n  visible = 1\n  hidden invisible = 2\n  local helper = 3\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_properties(value),
    content=(
      #|result.visible = 1
      #|
    ),
  )
}

///|
test "module-level visible properties survive the hidden filter" {
  let source = "name = \"hawk\"\nhidden internal = \"secret\"\nlocal helper = 99\nage = 2"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|name = "hawk"
      #|age = 2
    ),
  )
}

///|
test "typealiased function argument annotation enforces the alias constraint" {
  // `typealias Small = Int(isBetween(0, 10))` should fire on the
  // argument side just like the inline `Int(isBetween(0, 10))` form does.
  // An argument outside the range must reject with the constraint
  // message, not silently pass.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "typealias Small = Int(isBetween(0, 10))\nincrement = (x: Small) -> x + 1\nbad = increment(11)",
  )
  guard session.eval_path("main.pkl") is EvalError(diagnostics) else { panic() }
  assert_true(
    diagnostics.length() > 0 &&
    diagnostics[0].message.contains("isBetween rejects 11"),
  )
}

///|
test "typealiased function argument annotation accepts in-range value" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "typealias Small = Int(isBetween(0, 10))\nincrement = (x: Small) -> x + 1\ngood = increment(5)",
  )
  assert_true(
    session.eval_path("main.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "increment",
          value: FunctionValue(
            [{ name: "x", type_name: Some("Small") }],
            BinaryExpr(Add, Identifier("x"), IntLiteral(1)),
            None,
            [],
          ),
        },
        ValueMember::{ name: "good", value: IntValue(6) },
      ]),
    ),
  )
}

///|
test "typealiased class method argument annotation enforces the alias constraint" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "typealias Small = Int(isBetween(0, 10))\nclass Box { function bump(x: Small) = x + 1 }\nb = new Box {}\nbad = b.bump(20)",
  )
  guard session.eval_path("main.pkl") is EvalError(diagnostics) else { panic() }
  assert_true(
    diagnostics.length() > 0 &&
    diagnostics[0].message.contains("isBetween rejects 20"),
  )
}

///|
test "render Pkl module bindings as Java Properties" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{ name: "age", value: IntValue(30) },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|name = pigeon
      #|age = 30
      #|
    ),
  )
}

///|
test "Properties renderer flattens nested Pkl objects with dotted keys" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{ name: "street", value: StringValue("Norton St.") },
        ValueMember::{ name: "zip", value: IntValue(12345) },
      ]),
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|name = pigeon
      #|address.street = Norton St.
      #|address.zip = 12345
      #|
    ),
  )
}

///|
test "Properties renderer flattens Mapping with coerced keys" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "map",
      value: MappingValue([
        ValueEntry::{ key: StringValue("one"), value: IntValue(1) },
        ValueEntry::{ key: IntValue(2), value: BoolValue(true) },
        ValueEntry::{ key: NullValue, value: StringValue("nullish") },
      ]),
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|map.one = 1
      #|map.2 = true
      #|map.null = nullish
      #|
    ),
  )
}

///|
test "Properties renderer omits null leaves" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{ name: "friend", value: NullValue },
    ValueMember::{
      name: "address",
      value: ObjectValue([
        ValueMember::{ name: "street", value: StringValue("Norton St.") },
        ValueMember::{ name: "fax", value: NullValue },
      ]),
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|name = pigeon
      #|address.street = Norton St.
      #|
    ),
  )
}

///|
test "Properties renderer emits Listings as compact JSON values" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "list",
      value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
    },
    ValueMember::{
      name: "mixed",
      value: ListingValue([StringValue("string"), BoolValue(true), IntValue(42)]),
    },
    ValueMember::{ name: "empty", value: ListingValue([]) },
  ])
  // `:` inside the nested object key/value separator is escaped per
  // Java properties rules. Brackets, braces, commas, and quotes pass
  // through verbatim.
  inspect(
    render_value_as_properties(value),
    content=(
      #|list = [1,2,3]
      #|mixed = ["string",true,42]
      #|empty = []
      #|
    ),
  )
}

///|
test "Properties renderer emits Listing of nested objects" {
  let value : Value = ObjectValue([
    ValueMember::{
      name: "items",
      value: ListingValue([
        ObjectValue([ValueMember::{ name: "one", value: IntValue(1) }]),
        ObjectValue([
          ValueMember::{ name: "name", value: StringValue("Pigeon") },
        ]),
      ]),
    },
  ])
  inspect(
    render_value_as_properties(value),
    content=(
      #|items = [{"one"\:1},{"name"\:"Pigeon"}]
      #|
    ),
  )
}

///|
test "Properties renderer escapes special characters in scalar values" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "tab", value: StringValue("a\tb") },
    ValueMember::{ name: "newline", value: StringValue("a\nb") },
    ValueMember::{ name: "cr", value: StringValue("a\rb") },
    ValueMember::{ name: "ff", value: StringValue("a\u{0C}b") },
    ValueMember::{ name: "backslash", value: StringValue("c:\\path") },
    ValueMember::{ name: "leadingspace", value: StringValue(" lead") },
    ValueMember::{ name: "bangs", value: StringValue("!hello#world") },
    ValueMember::{ name: "kvchars", value: StringValue("a:b=c") },
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
    ValueMember::{ name: "a b", value: IntValue(1) },
    ValueMember::{ name: "a=b", value: IntValue(2) },
    ValueMember::{ name: "a:b", value: IntValue(3) },
    ValueMember::{ name: "a!b", value: IntValue(4) },
    ValueMember::{ name: "a#b", value: IntValue(5) },
    ValueMember::{ name: "a\\b", value: IntValue(6) },
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
    ValueMember::{ name: "name", value: StringValue("pigeon") },
    ValueMember::{ name: "emptyObj", value: ObjectValue([]) },
    ValueMember::{ name: "emptyMap", value: MappingValue([]) },
    ValueMember::{ name: "emptyList", value: ListingValue([]) },
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
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(6) }])),
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
    EvalOk(ObjectValue([ValueMember::{ name: "bird", value: ObjectValue([]) }])),
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
            ValueMember::{ name: "base", value: IntValue(40) },
          ]),
        },
        ValueMember::{ name: "value", value: IntValue(42) },
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
        ValueMember::{ name: "counter", value: ObjectValue([]) },
        ValueMember::{ name: "value", value: IntValue(3) },
      ]),
    ),
  )

  let invalid = "class Counter { function add(n: Int(isBetween(0, 10))): Int = n }\ncounter = new Counter {}\nvalue = counter.add(11)"
  guard typecheck_source(invalid) is TypeError(type_diagnostics) else {
    panic()
  }
  inspect(
    type_diagnostics[0].message,
    content="method add argument 1 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content="method add argument 1 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
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
            ValueMember::{ name: "name", value: StringValue("hawk") },
            ValueMember::{ name: "age", value: IntValue(2) },
          ]),
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
            ValueMember::{ name: "name", value: StringValue("owl") },
            ValueMember::{ name: "age", value: IntValue(1) },
          ]),
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
          value: ObjectValue([ValueMember::{ name: "a", value: IntValue(6) }]),
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
    content="type annotation X member a constraint above rejects 5",
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation X member a constraint above rejects 5",
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
          value: ObjectValue([ValueMember::{ name: "a", value: IntValue(6) }]),
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
    content="type annotation X member a constraint above rejects 5",
  )
  guard eval_source(invalid) is EvalError(eval_diagnostics) else { panic() }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation X member a constraint above rejects 5",
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
            ValueMember::{ name: "name", value: StringValue("bird") },
            ValueMember::{ name: "age", value: IntValue(1) },
            ValueMember::{ name: "wing", value: StringValue("wide") },
          ]),
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
            ValueMember::{ name: "name", value: StringValue("anon") },
            ValueMember::{ name: "subject", value: StringValue("math") },
            ValueMember::{ name: "age", value: IntValue(3) },
          ]),
        },
        ValueMember::{ name: "name", value: StringValue("anon") },
        ValueMember::{ name: "subject", value: StringValue("math") },
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
        ValueMember::{ name: "sum", value: IntValue(3) },
        ValueMember::{ name: "next", value: IntValue(4) },
      ]),
    ),
  )
}

///|
test "evaluate Pkl callable runtime values" {
  assert_true(
    eval_source("local inc = (n) -> n + 1\nlocal f = inc\nvalue = f(41)") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(42) }])),
  )
  assert_true(
    eval_source(
      "function apply(f, n) = f(n)\nlocal inc = (n) -> n + 1\nvalue = apply(inc, 2)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
  assert_true(
    eval_source("local box = new { f = (x) -> x + 1 }\nvalue = box.f(2)") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
}

///|
test "evaluate Pkl callable closure captures" {
  assert_true(
    eval_source(
      "function makeAdder(n) = (x) -> x + n\nlocal add2 = makeAdder(2)\nvalue = add2(3)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(5) }])),
  )
}

///|
test "evaluate non-scalar Pkl callable closure captures" {
  assert_true(
    eval_source(
      "function makeReader(box) = () -> box.name\nlocal reader = makeReader(new { name = \"hawk\" })\nvalue = reader()",
    ) ==
    EvalOk(
      ObjectValue([ValueMember::{ name: "value", value: StringValue("hawk") }]),
    ),
  )
  assert_true(
    eval_source(
      "function makeApply(f) = (n) -> f(n)\nlocal inc = (x) -> x + 1\nlocal applyInc = makeApply(inc)\nvalue = applyInc(2)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
}

///|
test "evaluate Pkl callable return annotations" {
  assert_true(
    eval_source("function good(): Int = 1\nvalue = good()") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(1) }])),
  )
  guard eval_source("function bad(): Int = \"hawk\"\nvalue = bad()")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="function bad return type annotation Int does not accept String",
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
        ValueMember::{ name: "counter", value: ObjectValue([]) },
        ValueMember::{ name: "value", value: IntValue(1) },
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
    content="method bad return type annotation Int does not accept String",
  )
}

///|
test "evaluate constrained Pkl callable return annotations" {
  assert_true(
    eval_source("function good(): Int(isBetween(0, 10)) = 1\nvalue = good()") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(1) }])),
  )
  guard eval_source("function bad(): Int(isBetween(0, 10)) = 11\nvalue = bad()")
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="function bad return type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
}

///|
test "evaluate user-defined constrained Pkl callable return annotations" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nfunction good(): Int(above(5)) = 6\nvalue = good()",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(6) }])),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nfunction bad(): Int(above(5)) = 1\nvalue = bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="function bad return type annotation Int(above(5)) constraint above rejects 1",
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
        ValueMember::{ name: "counter", value: ObjectValue([]) },
        ValueMember::{ name: "value", value: IntValue(6) },
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
    content="method bad return type annotation Int(above(5)) constraint above rejects 1",
  )
}

///|
test "evaluate user-defined constrained Pkl callable arguments" {
  assert_true(
    eval_source(
      "const function above(n) = (x) -> x > n\nfunction check(n: Int(above(5))) = n\nvalue = check(6)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(6) }])),
  )
  guard eval_source(
      "const function above(n) = (x) -> x > n\nfunction check(n: Int(above(5))) = n\nvalue = check(1)",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="function check argument 1 type annotation Int(above(5)) constraint above rejects 1",
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
        ValueMember::{ name: "counter", value: ObjectValue([]) },
        ValueMember::{ name: "value", value: IntValue(6) },
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
    content="method check argument 1 type annotation Int(above(5)) constraint above rejects 1",
  )
}

///|
test "evaluate typealiased Pkl callable return annotations" {
  assert_true(
    eval_source(
      "typealias Small = Int\nfunction good(): Small = 1\nvalue = good()",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(1) }])),
  )
  guard eval_source(
      "typealias Small = Int\nfunction bad(): Small = \"hawk\"\nvalue = bad()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  inspect(
    diagnostics[0].message,
    content="function bad return type annotation Small does not accept String",
  )
  assert_true(
    eval_source(
      "typealias Small = Int(isBetween(0, 10))\nfunction good(): Small = 6\nvalue = good()",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(6) }])),
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nfunction bad(): Small = 11\nvalue = bad()",
    )
    is EvalError(constraint_diagnostics) else {
    panic()
  }
  inspect(
    constraint_diagnostics[0].message,
    content="function bad return type annotation Small constraint isBetween rejects 11",
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
        ValueMember::{ name: "counter", value: ObjectValue([]) },
        ValueMember::{ name: "value", value: IntValue(1) },
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
    content="method bad return type annotation Small does not accept String",
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
    content="function bad return type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard typecheck_source(
      "class Counter { function bad(): Int(isBetween(0, 10)) = 11 }\ncounter = new Counter {}",
    )
    is TypeError(method_diagnostics) else {
    panic()
  }
  inspect(
    method_diagnostics[0].message,
    content="method Counter.bad return type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
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
    content="function bad return type annotation Int(above(5)) constraint above rejects 1",
  )
  guard typecheck_source(
      "const function above(n) = (x) -> x > n\nclass Counter { function bad(): Int(above(5)) = 1 }\ncounter = new Counter {}",
    )
    is TypeError(method_diagnostics) else {
    panic()
  }
  inspect(
    method_diagnostics[0].message,
    content="method Counter.bad return type annotation Int(above(5)) constraint above rejects 1",
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
    content="function accept argument 1 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard typecheck_source(
      "local accept = (n: Int(this.isBetween(0, 10))): Int -> n\nvalue = accept(11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content="function accept argument 1 type annotation Int(this.isBetween(0,10)) constraint isBetween rejects 11",
  )
  assert_true(
    eval_source(
      "function accept(n: Int(isBetween(0, 10))) = n\nlocal f = accept\nvalue = f(3)",
    ) ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
  guard eval_source(
      "function accept(n: Int(isBetween(0, 10))) = n\nlocal f = accept\nvalue = f(11)",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="function f argument 1 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
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
    content="function argument 1 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard typecheck_source(
      "local accept = (n: Int(this.isBetween(0, 10))): Int -> n\nlocal f = accept\nvalue = f(11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content="function argument 1 type annotation Int(this.isBetween(0,10)) constraint isBetween rejects 11",
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
    content="function apply argument 2 type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard typecheck_source(
      "local apply = (f, n): Int -> f(n)\nlocal accept = (n: Int(this.isBetween(0, 10))): Int -> n\nvalue = apply(accept, 11)",
    )
    is TypeError(lambda_diagnostics) else {
    panic()
  }
  inspect(
    lambda_diagnostics[0].message,
    content="function apply argument 2 type annotation Int(this.isBetween(0,10)) constraint isBetween rejects 11",
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
    content="type annotation Small constraint isBetween rejects 11",
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue: Small = 11",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Small constraint isBetween rejects 11",
  )
  guard typecheck_source(
      "typealias Small = Int(this.isBetween(0, 10))\nfunction accept(n: Small): Int = n\nvalue = accept(11)",
    )
    is TypeError(parameter_diagnostics) else {
    panic()
  }
  inspect(
    parameter_diagnostics[0].message,
    content="function accept argument 1 type annotation Small constraint isBetween rejects 11",
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
    content="type annotation Small constraint isBetween rejects 11",
  )
  guard eval_source(
      "typealias Small = Int(isBetween(0, 10))\nvalue = new { n: Small = 11 }",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Small constraint isBetween rejects 11",
  )
}

///|
test "support additional Pkl numeric constraint predicates" {
  assert_true(
    typecheck_source("value: Int(isPositive) = 3") ==
    TypeOk(ObjectType([TypeMember::{ name: "value", typ: IntType }])),
  )
  guard typecheck_source("value: Int(isPositive) = 0")
    is TypeError(positive_diagnostics) else {
    panic()
  }
  inspect(
    positive_diagnostics[0].message,
    content="type annotation Int(isPositive) constraint isPositive rejects 0",
  )
  guard eval_source("value: Int(this.isGreaterThan(5)) = 5")
    is EvalError(greater_diagnostics) else {
    panic()
  }
  inspect(
    greater_diagnostics[0].message,
    content="type annotation Int(this.isGreaterThan(5)) constraint isGreaterThan rejects 5",
  )
  guard typecheck_source(
      "typealias Small = Int(isLessThan(10))\nvalue = new { n: Small = 10 }",
    )
    is TypeError(alias_diagnostics) else {
    panic()
  }
  inspect(
    alias_diagnostics[0].message,
    content="type annotation Small constraint isLessThan rejects 10",
  )
}

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
    content="type annotation Int(isPositive,isLessThan(10)) constraint isLessThan rejects 10",
  )
  guard eval_source("value: Int(isPositive, isBetween(1, 10)) = 0")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Int(isPositive,isBetween(1,10)) constraint isPositive rejects 0",
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
    content="type annotation Int(!isPositive) constraint !isPositive rejects 1",
  )
  guard eval_source("value: Int(!isLessThan(10)) = 9")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Int(!isLessThan(10)) constraint !isLessThan rejects 9",
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
    content="type annotation Int(above(5)) constraint above rejects 5",
  )
  guard typecheck_source(
      "function above(n) = (x) -> x > n\ntypealias Above5 = Int(above(5))\nvalue: Above5 = 5",
    )
    is TypeError(alias_type_diagnostics) else {
    panic()
  }
  inspect(
    alias_type_diagnostics[0].message,
    content="type annotation Above5 constraint above rejects 5",
  )
  guard eval_source(
      "function above(n) = (x) -> x > n\nvalue: Int(above(5)) = 5",
    )
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Int(above(5)) constraint above rejects 5",
  )
  guard eval_source(
      "function above(n) = (x) -> x > n\ntypealias Above5 = Int(above(5))\nvalue: Above5 = 5",
    )
    is EvalError(alias_eval_diagnostics) else {
    panic()
  }
  inspect(
    alias_eval_diagnostics[0].message,
    content="type annotation Above5 constraint above rejects 5",
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
    content="type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  assert_true(
    eval_source("value: Int(isBetween(0, 10)) = 3") ==
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: IntValue(3) }])),
  )
  guard eval_source("value: Int(this.isBetween(0, 10)) = 11")
    is EvalError(eval_diagnostics) else {
    panic()
  }
  inspect(
    eval_diagnostics[0].message,
    content="type annotation Int(this.isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard typecheck_source("value = new { n: Int(isBetween(0, 10)) = 11 }")
    is TypeError(member_type_diagnostics) else {
    panic()
  }
  inspect(
    member_type_diagnostics[0].message,
    content="type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
  )
  guard eval_source("value = new { n: Int(isBetween(0, 10)) = 11 }")
    is EvalError(member_eval_diagnostics) else {
    panic()
  }
  inspect(
    member_eval_diagnostics[0].message,
    content="type annotation Int(isBetween(0,10)) constraint isBetween rejects 11",
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
  inspect(diagnostics[0].message, content="unknown type annotation Missing")
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
    EvalOk(ObjectValue([ValueMember::{ name: "value", value: NullValue }])),
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
            ValueMember::{ name: "name", value: StringValue("hawk") },
            ValueMember::{ name: "age", value: IntValue(2) },
          ]),
        },
        ValueMember::{
          name: "bird",
          value: ObjectValue([
            ValueMember::{ name: "name", value: StringValue("hawk") },
            ValueMember::{ name: "age", value: IntValue(3) },
            ValueMember::{ name: "wing", value: StringValue("wide") },
          ]),
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
        ValueMember::{ name: "name", value: StringValue("hawk") },
        ValueMember::{ name: "age", value: IntValue(3) },
      ]),
    ),
  )
  assert_true(
    session.eval_path("extended.pkl") ==
    EvalOk(
      ObjectValue([
        ValueMember::{ name: "name", value: StringValue("hawk") },
        ValueMember::{ name: "age", value: IntValue(2) },
        ValueMember::{ name: "wing", value: StringValue("wide") },
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
        ValueMember::{ name: "a", value: DurationValue(1, "ns") },
        ValueMember::{ name: "b", value: DurationValue(2, "us") },
        ValueMember::{ name: "c", value: DurationValue(3, "ms") },
        ValueMember::{ name: "d", value: DurationValue(4, "s") },
        ValueMember::{ name: "e", value: DurationValue(5, "min") },
        ValueMember::{ name: "f", value: DurationValue(6, "h") },
        ValueMember::{ name: "g", value: DurationValue(7, "d") },
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
        ValueMember::{ name: "a", value: DataSizeValue(1, "b") },
        ValueMember::{ name: "b", value: DataSizeValue(2, "kb") },
        ValueMember::{ name: "c", value: DataSizeValue(3, "kib") },
        ValueMember::{ name: "d", value: DataSizeValue(4, "mb") },
        ValueMember::{ name: "e", value: DataSizeValue(5, "mib") },
        ValueMember::{ name: "f", value: DataSizeValue(6, "gb") },
        ValueMember::{ name: "g", value: DataSizeValue(7, "gib") },
        ValueMember::{ name: "h", value: DataSizeValue(8, "tb") },
        ValueMember::{ name: "i", value: DataSizeValue(9, "tib") },
        ValueMember::{ name: "j", value: DataSizeValue(10, "pb") },
        ValueMember::{ name: "k", value: DataSizeValue(11, "pib") },
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
      ObjectValue([ValueMember::{ name: "a", value: DurationValue(6, "s") }]),
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
      ObjectValue([ValueMember::{ name: "a", value: DurationValue(182, "s") }]),
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
        ValueMember::{ name: "a", value: DurationValue(3, "s") },
        ValueMember::{ name: "b", value: DurationValue(150, "s") },
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
        ValueMember::{ name: "lt", value: BoolValue(true) },
        ValueMember::{ name: "le", value: BoolValue(true) },
        ValueMember::{ name: "gt", value: BoolValue(true) },
        ValueMember::{ name: "ge", value: BoolValue(true) },
        ValueMember::{ name: "eq", value: BoolValue(true) },
        ValueMember::{ name: "ne", value: BoolValue(true) },
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
        ValueMember::{ name: "a", value: DataSizeValue(5, "kb") },
        ValueMember::{ name: "b", value: DataSizeValue(900, "kb") },
        ValueMember::{ name: "c", value: BoolValue(true) },
        ValueMember::{ name: "d", value: BoolValue(true) },
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
        ValueMember::{ name: "a", value: DurationValue(-4, "s") },
        ValueMember::{ name: "b", value: DurationValue(-2, "min") },
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
        ValueMember::{ name: "v", value: IntValue(3) },
        ValueMember::{ name: "u", value: StringValue("min") },
        ValueMember::{ name: "m", value: IntValue(2) },
        ValueMember::{ name: "un", value: StringValue("kb") },
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
        ValueMember::{ name: "a", value: DurationValue(60, "s") },
        ValueMember::{ name: "b", value: DurationValue(60, "min") },
        ValueMember::{ name: "c", value: DataSizeValue(1024, "b") },
      ]),
    ),
  )
}

///|
test "render Pkl Duration and DataSize values as PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "wait", value: DurationValue(5, "min") },
    ValueMember::{ name: "size", value: DataSizeValue(3, "kib") },
    ValueMember::{ name: "neg", value: DurationValue(-2, "s") },
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
        ValueMember::{ name: "a", value: RegexValue("a+") },
        ValueMember::{ name: "b", value: RegexValue("^foo$") },
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
      ObjectValue([ValueMember::{ name: "p", value: StringValue("[0-9]+") }]),
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
        ValueMember::{ name: "a", value: BoolValue(true) },
        ValueMember::{ name: "b", value: BoolValue(false) },
        ValueMember::{ name: "c", value: BoolValue(true) },
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
        ValueMember::{ name: "a", value: StringValue("123") },
        ValueMember::{ name: "b", value: NullValue },
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
          ]),
        },
        ValueMember::{ name: "b", value: ListingValue([]) },
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
        ValueMember::{ name: "a", value: StringValue("abcXde3") },
        ValueMember::{ name: "b", value: StringValue("abc") },
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
        ValueMember::{ name: "a", value: StringValue("abcXdeXfX") },
        ValueMember::{ name: "b", value: StringValue("abc") },
      ]),
    ),
  )
}

///|
test "render Pkl Regex values as Regex(\"...\") PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "digits", value: RegexValue("[0-9]+") },
    ValueMember::{ name: "anchored", value: RegexValue("^foo$") },
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
      ObjectValue([ValueMember::{ name: "name", value: StringValue("hawk") }]),
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
        if d.message.contains("length") && d.message.contains("rejects") {
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
      ObjectValue([ValueMember::{ name: "name", value: StringValue("hi") }]),
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
        if d.message.contains("isBetween") && d.message.contains("rejects") {
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
      ObjectValue([ValueMember::{ name: "id", value: StringValue("hawk") }]),
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
        if d.message.contains("matches") && d.message.contains("rejects") {
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
        if d.message.contains("isPositive") && d.message.contains("rejects") {
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
        if d.message.contains("!matches") && d.message.contains("rejects") {
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
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
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
        if d.message.contains("isPositive") && d.message.contains("rejects") {
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
        if d.message.contains("length") && d.message.contains("rejects") {
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
        if d.message.contains("isBetween") && d.message.contains("rejects") {
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
        if d.message.contains("length") && d.message.contains("rejects") {
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
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43") },
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
        ValueMember::{ name: "n", value: IntValue(3) },
        ValueMember::{ name: "b", value: StringValue("QUJD") },
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
        ValueMember::{ name: "in_bound", value: IntValue(66) },
        ValueMember::{ name: "out_bound", value: NullValue },
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
          value: ListingValue([IntValue(1), IntValue(2), IntValue(3)]),
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
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43") },
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
        ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43") },
      ]),
    ),
  )
}

///|
test "render Pkl Bytes values as Bytes(new Listing { ... }) PCF literals" {
  let value : Value = ObjectValue([
    ValueMember::{ name: "data", value: BytesValue(b"\x41\x42\x43") },
  ])
  inspect(
    render_value(value),
    content=(
      #|data = Bytes(new Listing { 65; 66; 67 })
    ),
  )
}
