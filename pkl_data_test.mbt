///|
test "PKL-119be: non-empty IntSeqs are equal when their element sequences match" {
  guard eval_source("v = IntSeq(-10, 10).step(2) == IntSeq(-10, 11).step(2)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is BoolValue(b) else { panic() }
  inspect(b, content="true")
}

///|
test "PKL-119be: IntSeqs with different step values are not equal" {
  guard eval_source("v = IntSeq(-10, 10) == IntSeq(-10, 10).step(2)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is BoolValue(b) else { panic() }
  inspect(b, content="false")
}

///|
test "PKL-119be: reversed-direction IntSeqs are not equal" {
  guard eval_source("v = IntSeq(-10, 10) == IntSeq(10, -10).step(-1)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is BoolValue(b) else { panic() }
  inspect(b, content="false")
}

///|
test "PKL-119be: IntSeq != mirrors the equality semantics" {
  guard eval_source("v = IntSeq(0, 3) != IntSeq(0, 3)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is BoolValue(b) else { panic() }
  inspect(b, content="false")
}

///|
test "PKL-119b: PCF renders IntSeq through the constructor form" {
  guard eval_source("s = IntSeq(2, 5)") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content="s = IntSeq(2, 5)")
}

///|
test "PKL-119b: PCF renders custom step as chained .step call" {
  guard eval_source("s = IntSeq(0, 10).step(2)") is EvalOk(value) else {
    panic()
  }
  inspect(@pkl.render_value(value), content="s = IntSeq(0, 10).step(2)")
}

///|
test "PKL-119b: JSON materializes IntSeq into an Int array" {
  guard eval_source("s = IntSeq(1, 3)") is EvalOk(value) else { panic() }
  let json = @pkl.render_value_as_json(value)
  let expected =
    #|{
    #|  "s": [
    #|    1,
    #|    2,
    #|    3
    #|  ]
    #|}
  inspect(json, content=expected)
}

///|
test "PKL-119b: IntSeq typechecks under the IntSeq annotation" {
  guard typecheck_source(
      "r: IntSeq = IntSeq(1, 5)\nstart: Int = r.start\nlst = r.toList()",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-119b: IntSeq rejects non-Int arguments at typecheck" {
  let result = typecheck_source("s = IntSeq(1, \"five\")")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(messages[0], content="IntSeq argument 2 expects Int, got String")
}

///|
test "PKL-119b: IntSeq member typo surfaces Pkl-shaped diagnostic" {
  let result = typecheck_source("s = IntSeq(1, 5)\nbad = s.starts")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Cannot find property `starts` in object of type `IntSeq`.",
  )
}

///|
test "PKL-119a: Pair.first / .second eval-side access" {
  guard eval_source("p = Pair(\"alpha\", 42)\nf = p.first\ns = p.second")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got_first = ""
  let mut got_second = 0L
  for entry in members {
    if entry.name == "f" {
      guard entry.value is StringValue(s) else { panic() }
      got_first = s
    }
    if entry.name == "s" {
      guard entry.value is IntValue(n) else { panic() }
      got_second = n
    }
  }
  inspect(got_first, content="alpha")
  inspect(got_second, content="42")
}

///|
test "PKL-119a: Pair<A, B> annotation participates in typecheck" {
  guard typecheck_source(
      "p: Pair<Int, String> = Pair(1, \"hello\")\nf: Int = p.first\ns: String = p.second",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-119a: Pair member typo surfaces Pair-named diagnostic" {
  let result = typecheck_source("p = Pair(1, 2)\nbad = p.thirdy")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Cannot find property `thirdy` in object of type `Pair`.",
  )
}

///|
test "PKL-119a: Pair arity mismatch reports diagnostic" {
  let result = typecheck_source("p = Pair(1, 2, 3)")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(messages[0], content="Pair expects exactly two arguments")
}

///|
test "PKL-119a: PCF renders Pair as Pair(a, b) constructor" {
  guard eval_source("p = Pair(1, \"two\")") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content="p = Pair(1, \"two\")")
}

///|
test "PKL-119a: JSON renders Pair as 2-element array" {
  guard eval_source("p = Pair(1, \"two\")") is EvalOk(value) else { panic() }
  let json = @pkl.render_value_as_json(value)
  let expected =
    #|{
    #|  "p": [
    #|    1,
    #|    "two"
    #|  ]
    #|}
  inspect(json, content=expected)
}

///|
test "PKL-119a: YAML renders Pair as a 2-element sequence" {
  guard eval_source("p = Pair(1, \"two\")") is EvalOk(value) else { panic() }
  let yaml = @pkl.render_value_as_yaml(value)
  let expected =
    #|p:
    #|- 1
    #|- two
    #|
  inspect(yaml, content=expected)
}

///|
test "PKL-119a: nested Pair survives the PCF round-trip" {
  guard eval_source("p = Pair(Pair(1, 2), Pair(3, 4))") is EvalOk(value) else {
    panic()
  }
  inspect(@pkl.render_value(value), content="p = Pair(Pair(1, 2), Pair(3, 4))")
}

///|
test "PKL-119a: user-defined class Pair shadows the builtin generic" {
  // Mirrors `generic class declaration with two type parameters` —
  // confirm the local `class Pair<A, B>` keeps winning over the
  // PKL-119a typing hooks since they only kick in for `Pair<...>`
  // annotations and bare `Pair(...)` constructor calls.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Pair<A, B> { first: A; second: B }\np = new Pair { first = 1; second = \"hi\" }",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
}

///|
test "PKL-119a: user-defined class Pair evaluates through local class binding" {
  guard eval_source(
      "class Pair<A, B> { first: A; second: B }\np = new Pair { first = 1; second = \"hi\" }",
    )
    is EvalOk(value) else {
    panic()
  }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("p {"), content="true")
  inspect(rendered.contains("first = 1"), content="true")
  inspect(rendered.contains("second = \"hi\""), content="true")
}

///|
test "PKL-126a: plist renderer emits XML 1.0 prolog and Apple DOCTYPE" {
  guard eval_source("name = \"pigeon\"\nage = 42") is EvalOk(value) else {
    panic()
  }
  let out = @pkl.render_value_as_plist(value)
  inspect(
    out.has_prefix(
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist",
    ),
    content="true",
  )
  inspect(out.has_suffix("</plist>\n"), content="true")
}

///|
test "PKL-126a: plist scalars map to integer / real / true / false / string nodes" {
  guard eval_source("i = 7\nd = 1.5\nt = true\nf = false\ns = \"hi\"")
    is EvalOk(value) else {
    panic()
  }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<integer>7</integer>"), content="true")
  inspect(out.contains("<real>1.5</real>"), content="true")
  inspect(out.contains("<true/>"), content="true")
  inspect(out.contains("<false/>"), content="true")
  inspect(out.contains("<string>hi</string>"), content="true")
}

///|
test "PKL-126a: plist escapes XML special characters in strings" {
  guard eval_source("s = \"<a & b>\"") is EvalOk(value) else { panic() }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<string>&lt;a &amp; b&gt;</string>"), content="true")
}

///|
test "PKL-126a: plist dict omits null entries (omitNullProperties default)" {
  guard eval_source("present = 1\nabsent = null") is EvalOk(value) else {
    panic()
  }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<key>present</key>"), content="true")
  inspect(out.contains("<key>absent</key>"), content="false")
}

///|
test "PKL-126a: plist Listing renders as <array> with nested values" {
  guard eval_source("xs = new Listing { 1; 2; 3 }") is EvalOk(value) else {
    panic()
  }
  let out = @pkl.render_value_as_plist(value)
  inspect(
    out.contains(
      "<array>\n    <integer>1</integer>\n    <integer>2</integer>\n    <integer>3</integer>\n  </array>",
    ),
    content="true",
  )
}

///|
test "PKL-126a: plist Mapping renders as <dict> with key + value pairs" {
  guard eval_source("m = new Mapping { [\"a\"] = 1; [\"b\"] = 2 }")
    is EvalOk(value) else {
    panic()
  }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<key>a</key>"), content="true")
  inspect(out.contains("<key>b</key>"), content="true")
  inspect(out.contains("<integer>1</integer>"), content="true")
  inspect(out.contains("<integer>2</integer>"), content="true")
}

///|
test "PKL-126a: plist Duration / DataSize project to space-separated strings" {
  guard eval_source("d = 3.s\nb = 4.mb") is EvalOk(value) else { panic() }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<string>3 s</string>"), content="true")
  inspect(out.contains("<string>4 mb</string>"), content="true")
}

///|
test "PKL-126a: plist empty object renders as self-closing <dict/>" {
  guard eval_source("only_null = null") is EvalOk(value) else { panic() }
  let out = @pkl.render_value_as_plist(value)
  inspect(out.contains("<dict/>"), content="true")
}

///|
test "PKL-124: pkl:base JsonRenderer typechecks without import" {
  let result = typecheck_source(
    "count = 5\noutput { renderer = new JsonRenderer { indent = \"    \" } }",
  )
  guard result is TypeOk(_) else { panic() }
}

///|
test "PKL-124: pkl:base YamlRenderer / PcfRenderer / PropertiesRenderer / PListRenderer typecheck" {
  let result = typecheck_source(
    "yaml = new YamlRenderer {}\npcf = new PcfRenderer {}\nprops = new PropertiesRenderer {}\nplist = new PListRenderer {}",
  )
  guard result is TypeOk(_) else { panic() }
}

///|
test "PKL-124: pkl:json Parser instantiable through qualified import" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser { useMapping = true }\nm = p.useMapping",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got_mapping = false
  for entry in members {
    if entry.name == "m" {
      guard entry.value is BoolValue(b) else { panic() }
      inspect(b, content="true")
      got_mapping = true
    }
  }
  inspect(got_mapping, content="true")
}

///|
test "PKL-124: pkl:xml Renderer carries indent / xmlVersion / rootElementName defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:xml\" as xml\nr = new xml.Renderer { rootElementName = \"config\" }\ni = r.indent\nv = r.xmlVersion\nrn = r.rootElementName",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut indent = ""
  let mut version = ""
  let mut name = ""
  for entry in members {
    match (entry.name, entry.value) {
      ("i", StringValue(s)) => indent = s
      ("v", StringValue(s)) => version = s
      ("rn", StringValue(s)) => name = s
      _ => ()
    }
  }
  inspect(indent, content="  ")
  inspect(version, content="1.0")
  inspect(name, content="config")
}

///|
test "PKL-124: pkl:protobuf Renderer instantiable through qualified import" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:protobuf\" as protobuf\nr = new protobuf.Renderer {}",
  )
  guard session.typecheck_path("main.pkl") is TypeOk(_) else { panic() }
}

///|
test "PKL-124: unknown renderer class still surfaces Cannot find type" {
  let result = typecheck_source("r = new MysteryRenderer {}")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(messages[0], content="Cannot find type `MysteryRenderer`.")
}

///|
test "PKL-117: super method call dispatches to parent class" {
  guard eval_source(
      "class Animal { function describe(): String = \"an animal\" }\nclass Cat extends Animal { function describe(): String = \"fluffy \\(super.describe())\" }\nc = new Cat {}\nmsg = c.describe()",
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
  inspect(msg, content="fluffy an animal")
}

///|
test "PKL-117: super on class without parent reports clear error" {
  guard eval_source(
      "class Animal { function describe(): String = super.describe() }\nc = new Animal {}\nmsg = c.describe()",
    )
    is EvalError(diagnostics) else {
    panic()
  }
  let mut hit = false
  for diagnostic in diagnostics {
    if diagnostic.message.contains("no parent") {
      hit = true
    }
  }
  assert_true(hit)
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
  // PKL-148e: Apple Pkl strips the newline immediately preceding the
  // closing delimiter's own indent line.
  assert_eq(s, "hello\nworld")
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
  let mut port = -1L
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
        ValueMember::{
          name: "a",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: FloatValue(0.5),
          source: None,
          annotations: [],
        },
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
      ObjectValue([
        ValueMember::{
          name: "res",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
      ]),
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
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "trace built-in composes inside expressions" {
  assert_true(
    eval_source("res = trace(2) + trace(3)") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "res",
          value: IntValue(5),
          source: None,
          annotations: [],
        },
      ]),
    ),
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
        ValueMember::{
          name: "intMirror",
          value: StringValue("pkl.base#Int"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "stringMirror",
          value: StringValue("pkl.base#String"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "booleanMirror",
          value: StringValue("pkl.base#Boolean"),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "PKL-143: reflect.Class(name).properties walks the class declaration" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclass Person { name: String; age: Int }\nps = reflect.Class(\"Person\").properties\nfirstName = ps[0].name\nfirstTypeName = ps[0].typeName",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("firstName = \"name\""), content="true")
  inspect(rendered.contains("firstTypeName = \"String\""), content="true")
}

///|
test "PKL-143: reflect.Class(name).methods includes return + parameter types" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclass Greeter {\n  function greet(n: String): String = n\n}\nms = reflect.Class(\"Greeter\").methods\nmname = ms[0].name\nret = ms[0].returnTypeName",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("mname = \"greet\""), content="true")
  inspect(rendered.contains("ret = \"String\""), content="true")
}

///|
test "PKL-143: reflect.Class(name).supertype walks parent_name" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclass Animal { name: String }\nclass Dog extends Animal { breed: String }\nsup = reflect.Class(\"Dog\").supertype.reflectee",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  for entry in members {
    if entry.name == "sup" {
      guard entry.value is StringValue(name) else { panic() }
      inspect(name, content="Animal")
    }
  }
}

///|
test "PKL-143: reflect.Module(name).classes lists every class declaration" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclass A {}\nclass B {}\nclasses = reflect.Module(\"self\").classes",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  for entry in members {
    if entry.name == "classes" {
      guard entry.value is ListingValue(items) else { panic() }
      inspect(items.length(), content="2")
    }
  }
}

///|
test "PKL-143: reflect.Class.isSubclassOf walks the parent chain" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclass Animal {}\nclass Dog extends Animal {}\nclass Puppy extends Dog {}\ndogIsAnimal = reflect.Class(\"Dog\").isSubclassOf(reflect.Class(\"Animal\"))\npuppyIsAnimal = reflect.Class(\"Puppy\").isSubclassOf(reflect.Class(\"Animal\"))\nanimalIsDog = reflect.Class(\"Animal\").isSubclassOf(reflect.Class(\"Dog\"))",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  for entry in members {
    match (entry.name, entry.value) {
      ("dogIsAnimal", BoolValue(b)) => inspect(b, content="true")
      ("puppyIsAnimal", BoolValue(b)) => inspect(b, content="true")
      ("animalIsDog", BoolValue(b)) => inspect(b, content="false")
      _ => ()
    }
  }
}

///|
test "pkl:reflect Class factory returns a reflectee container" {
  // PKL-080 / PKL-143: the `Class` / `Module` / `TypeAlias` / `Property`
  // factories take a string identifier (rather than a class value) because we
  // do not yet have a `ClassValue` variant to round-trip a class declaration.
  // PKL-143 added a hidden `__kind` marker on each mirror so member-access
  // hijack can dispatch `.properties` / `.methods` / `.supertype` etc.;
  // assert only on the rendered output here so the hidden marker stays an
  // implementation detail rather than a contract.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:reflect\" as reflect\nclassMirror = reflect.Class(\"Foo\")\nname = classMirror.reflectee\ndecl = reflect.DeclaredType(reflect.Class(\"Bar\"))\ndeclName = decl.referent.reflectee",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Foo\""), content="true")
  inspect(rendered.contains("declName = \"Bar\""), content="true")
  inspect(rendered.contains("reflectee = \"Foo\""), content="true")
  inspect(rendered.contains("reflectee = \"Bar\""), content="true")
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
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: IntValue(9),
          source: None,
          annotations: [],
        },
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
        ValueMember::{
          name: "a",
          value: IntValue(7),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: IntValue(7),
          source: None,
          annotations: [],
        },
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
        ValueMember::{
          name: "a",
          value: NullValue,
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: IntValue(42),
          source: None,
          annotations: [],
        },
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
        ValueMember::{
          name: "a",
          value: NullValue,
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "b",
          value: NullValue,
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "c",
          value: IntValue(99),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "let-expression introduces a single scoped binding" {
  assert_true(
    eval_source("result = let (x = 5) x * 2") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: IntValue(10),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "let-expression body can reference outer bindings" {
  assert_true(
    eval_source("base = 3\nresult = let (square = base * base) square + 1") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "base",
          value: IntValue(3),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: IntValue(10),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "let-expression preserves the current this binding" {
  assert_true(
    eval_source(
      "result = let (x = this) let (y = this) x == y && y == this && this == module",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: BoolValue(true),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "class defaults with let see constructor overrides" {
  let source =
    #|class Lets {
    #|  x = 2
    #|  y = let (z = 2) z + x
    #|  function f(x) = let (z = 2) z + x
    #|  z = f(x)
    #|}
    #|result = new Lets { x = 4 }
  assert_true(
    eval_source(source) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{
              name: "x",
              value: IntValue(4),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "y",
              value: IntValue(6),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "z",
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
}

///|
test "let-expression nests with inner shadowing" {
  assert_true(
    eval_source("result = let (x = 1) let (x = x + 10) let (x = x * 2) x") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: IntValue(22),
          source: None,
          annotations: [],
        },
      ]),
    ),
  )
}

///|
test "let-expression composes with null-coalescing" {
  assert_true(
    eval_source("raw = null\nresult = let (fallback = 99) raw ?? fallback") ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "raw",
          value: NullValue,
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: IntValue(99),
          source: None,
          annotations: [],
        },
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
            ValueMember::{
              name: "always",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "flag",
              value: StringValue("yes"),
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
            ValueMember::{
              name: "always",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "flag",
              value: StringValue("no"),
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
            ValueMember::{
              name: "always",
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
      "result {\n  always = 1\n  when (true) {\n    flag = \"yes\"\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{
              name: "always",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "flag",
              value: StringValue("yes"),
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
test "object body when-conditional reads outer bindings" {
  // The when-condition can refer to bindings declared earlier in the module.
  assert_true(
    eval_source(
      "stage = \"prod\"\nresult {\n  when (stage == \"prod\") {\n    replicas = 3\n  } else {\n    replicas = 1\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "stage",
          value: StringValue("prod"),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{
              name: "replicas",
              value: IntValue(3),
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
            ValueMember::{
              name: "a",
              value: IntValue(1),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "b",
              value: IntValue(2),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "d",
              value: IntValue(4),
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
          value: ObjectValue([
            ValueMember::{
              name: "last",
              value: IntValue(3),
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
test "object body for-generator appends unnamed elements from each iteration" {
  let source = "result {\n  for (x in new Listing { 1; 2; 3 }) {\n    x\n  }\n}"
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|result {
      #|  1
      #|  2
      #|  3
      #|}
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
            ValueMember::{
              name: "idx",
              value: IntValue(2),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "val",
              value: IntValue(30),
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
            ValueMember::{
              name: "lastKey",
              value: StringValue("b"),
              source: None,
              annotations: [],
            },
            ValueMember::{
              name: "lastVal",
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
          value: ObjectValue([
            ValueMember::{
              name: "base",
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
}

///|
test "object body for-generator sees outer-scope bindings" {
  assert_true(
    eval_source(
      "scale = 10\nresult {\n  for (x in new Listing { 1; 2; 3 }) {\n    last = x * scale\n  }\n}",
    ) ==
    EvalOk(
      ObjectValue([
        ValueMember::{
          name: "scale",
          value: IntValue(10),
          source: None,
          annotations: [],
        },
        ValueMember::{
          name: "result",
          value: ObjectValue([
            ValueMember::{
              name: "last",
              value: IntValue(30),
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
          value: ObjectValue([
            ValueMember::{
              name: "last",
              value: IntValue(4),
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
    diagnostics[0].message.contains(
      "Type constraint `isBetween(0, 10)` violated. Value: 11",
    ),
  )
}

///|
test "typealiased function argument annotation accepts in-range value" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "typealias Small = Int(isBetween(0, 10))\nincrement = (x: Small) -> x + 1\ngood = increment(5)",
  )
  // PKL-148g: FunctionValue carries an identity stamp now, so the
  // structural `==` would diverge from the constructed pattern.
  // Destructure the shape and assert each visible component.
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_eq(members.length(), 2)
  assert_eq(members[0].name, "increment")
  guard members[0].value
    is FunctionValue(parameters, body, return_type_name, captured_env, _) else {
    panic()
  }
  assert_eq(parameters.length(), 1)
  assert_eq(parameters[0].name, "x")
  assert_true(parameters[0].type_name == Some("Small"))
  assert_true(body == BinaryExpr(Add, Identifier("x"), IntLiteral(1)))
  assert_true(return_type_name is None)
  assert_eq(captured_env.length(), 0)
  assert_eq(members[1].name, "good")
  assert_true(members[1].value == IntValue(6))
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
    diagnostics[0].message.contains(
      "Type constraint `isBetween(0, 10)` violated. Value: 20",
    ),
  )
}

///|
test "render Pkl module bindings as Java Properties" {
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
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
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
      source: None,
      annotations: [],
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
    ValueMember::{
      name: "name",
      value: StringValue("pigeon"),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "friend",
      value: NullValue,
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
          name: "fax",
          value: NullValue,
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
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
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "mixed",
      value: ListingValue([StringValue("string"), BoolValue(true), IntValue(42)]),
      source: None,
      annotations: [],
    },
    ValueMember::{
      name: "empty",
      value: ListingValue([]),
      source: None,
      annotations: [],
    },
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
        ObjectValue([
          ValueMember::{
            name: "one",
            value: IntValue(1),
            source: None,
            annotations: [],
          },
        ]),
        ObjectValue([
          ValueMember::{
            name: "name",
            value: StringValue("Pigeon"),
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
    render_value_as_properties(value),
    content=(
      #|items = [{"one"\:1},{"name"\:"Pigeon"}]
      #|
    ),
  )
}

///|
