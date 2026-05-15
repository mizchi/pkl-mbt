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
