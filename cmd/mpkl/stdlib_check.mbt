// PKL-132x: stdlib coverage probe. The table below pins one minimal
// fixture per documented stdlib surface area so the support claims in
// README.md ("Full" / "Partial" / "Stub") are mechanically verified.
// `mpkl stdlib` evaluates each probe through the same `eval_source`
// path that user code takes, renders the result through the PCF
// renderer, and matches against an expected substring. Failures
// surface as `[FAIL]` lines plus a non-zero exit code so CI / a
// release-check pass catches the moment a documented capability
// regresses.

///|
priv struct StdlibProbe {
  group : String
  name : String
  source : String
  expect : String
}

///|
let stdlib_probes : Array[StdlibProbe] = [
  // pkl:base — value-variant + builtin operations.
  {
    group: "pkl:base",
    name: "Listing.fold",
    source: "v = new Listing { 1; 2; 3 }.fold(0, (acc, x) -> acc + x)",
    expect: "v = 6",
  },
  {
    group: "pkl:base",
    name: "Mapping.keys",
    source: "v = (new Mapping { [\"a\"] = 1; [\"b\"] = 2 }).keys",
    expect: "\"a\"",
  },
  {
    group: "pkl:base",
    name: "String.toUpperCase",
    source: "v = \"hi\".toUpperCase()",
    expect: "v = \"HI\"",
  },
  {
    group: "pkl:base",
    name: "Int.toString(radix)",
    source: "v = 255.toString(16)",
    expect: "v = \"ff\"",
  },
  {
    group: "pkl:base",
    name: "Pair value variant",
    source: "v = Pair(\"a\", 42).second",
    expect: "v = 42",
  },
  {
    group: "pkl:base",
    name: "IntSeq value variant",
    source: "v = IntSeq(1, 3).fold(0, (acc, x) -> acc + x)",
    expect: "v = 6",
  },
  {
    group: "pkl:base",
    name: "IntSeq sequence equality (empty)",
    source: "v = IntSeq(0, -1) == IntSeq(10, -10)",
    expect: "v = true",
  },
  {
    group: "pkl:base",
    name: "IntSeq sequence equality (step-aware)",
    source: "v = IntSeq(-10, 10).step(2) == IntSeq(-10, 11).step(2)",
    expect: "v = true",
  },
  {
    group: "pkl:base",
    name: "Set value variant",
    source: "v = Set(1, 2, 3, 2, 1).length",
    expect: "v = 3",
  },
  {
    group: "pkl:base",
    name: "Map value variant",
    source: "v = Map(\"a\", 1, \"b\", 2).getOrNull(\"a\")",
    expect: "v = 1",
  },
  {
    group: "pkl:base",
    name: "JsonRenderer class",
    source: "r = new JsonRenderer { indent = \"    \" }\nv = r.indent",
    expect: "v = \"    \"",
  },
  {
    group: "pkl:base",
    name: "YamlRenderer class",
    source: "r = new YamlRenderer { indentWidth = 4 }\nv = r.indentWidth",
    expect: "v = 4",
  },
  {
    group: "pkl:base",
    name: "Duration mixed-unit addition (normalizes to coarser unit)",
    source: "v = (3.s + 500.ms).value",
    expect: "v = 3.5",
  },
  {
    group: "pkl:base",
    name: "DataSize literal",
    source: "v = 4.mb.unit",
    expect: "v = \"mb\"",
  },
  {
    group: "pkl:base",
    name: "Regex.matches",
    source: "v = Regex(\"^a+$\").matches(\"aaa\")",
    expect: "v = true",
  },
  {
    group: "pkl:base",
    name: "Bytes base64 round-trip",
    source: "v = Bytes.fromBase64(\"aGVsbG8=\").base64",
    expect: "v = \"aGVsbG8=\"",
  },
  // pkl:math — Int + Float helpers.
  {
    group: "pkl:math",
    name: "constants (maxInt32)",
    source: "import \"pkl:math\" as math\nv = math.maxInt32",
    expect: "v = 2147483647",
  },
  {
    group: "pkl:math",
    name: "Int helpers (max)",
    source: "import \"pkl:math\" as math\nv = math.max(3, 8)",
    expect: "v = 8",
  },
  {
    group: "pkl:math",
    name: "Float helper (sqrt)",
    source: "import \"pkl:math\" as math\nv = math.sqrt(16.0)",
    expect: "v = 4.0",
  },
  {
    group: "pkl:math",
    name: "Float helper (pow)",
    source: "import \"pkl:math\" as math\nv = math.pow(2.0, 10.0)",
    expect: "v = 1024.0",
  },
  {
    group: "pkl:math",
    name: "pi constant",
    source: "import \"pkl:math\" as math\nv = math.pi",
    expect: "v = 3.141592653589793",
  },
  // pkl:semver — Version parsing + comparison.
  {
    group: "pkl:semver",
    name: "parse decomposition",
    source: "import \"pkl:semver\" as s\nv = s.parse(\"1.2.3\").minor",
    expect: "v = 2",
  },
  {
    group: "pkl:semver",
    name: "isLessThan with pre-release",
    source: "import \"pkl:semver\" as s\nv = s.isLessThan(s.parse(\"1.0.0-rc\"), s.parse(\"1.0.0\"))",
    expect: "v = true",
  },
  {
    group: "pkl:semver",
    name: "parseOrNull on bad input",
    source: "import \"pkl:semver\" as s\nv = s.parseOrNull(\"oops\")",
    expect: "v = null",
  },
  // pkl:platform — stub values.
  {
    group: "pkl:platform",
    name: "current.operatingSystem.name (stub)",
    source: "import \"pkl:platform\" as p\nv = p.current.operatingSystem.name",
    expect: "v = \"stub-os\"",
  },
  // pkl:test — catch flow.
  // Apple Pkl's `test.catch` returns null on no-throw and the
  // thrown-message string otherwise. pkl-mbt only implements the
  // throw-side branch (which is what `classes/constraints8.pkl`
  // exercises); the no-throw branch falls back to evaluating the
  // lambda as if catch wasn't there, so the probe is intentionally
  // scoped to the throw path.
  {
    group: "pkl:test",
    name: "catch captures thrown message",
    source: "import \"pkl:test\"\nv = test.catch(() -> throw(\"boom\"))",
    expect: "v = \"boom\"",
  },
  // pkl:reflect — mirror constants + introspection. `reflect.intType`
  // returns a Class mirror (`name = "Int"` + typeArguments / referent
  // slots), not a flat `"pkl.base#Int"` string — the latter was the
  // shape of the very-early stub, before the full reflect surface
  // landed.
  {
    group: "pkl:reflect",
    name: "intType mirror constant",
    source: "import \"pkl:reflect\" as r\nv = r.intType.name",
    expect: "v = \"Int\"",
  },
  {
    group: "pkl:reflect",
    name: "Class factory reflectee",
    source: "import \"pkl:reflect\" as r\nv = r.Class(\"Foo\").reflectee",
    expect: "v = \"Foo\"",
  },
  {
    group: "pkl:reflect",
    name: "Class.properties walks class declaration",
    source: "import \"pkl:reflect\" as r\nclass Person { name: String; age: Int }\nv = r.Class(\"Person\").properties[1].typeName",
    expect: "v = \"Int\"",
  },
  {
    group: "pkl:reflect",
    name: "Class.methods walks class declaration",
    source: "import \"pkl:reflect\" as r\nclass G { function greet(n: String): String = n }\nv = r.Class(\"G\").methods[0].returnTypeName",
    expect: "v = \"String\"",
  },
  {
    group: "pkl:reflect",
    name: "Class.supertype follows parent_name",
    source: "import \"pkl:reflect\" as r\nclass Animal {}\nclass Dog extends Animal {}\nv = r.Class(\"Dog\").supertype.reflectee",
    expect: "v = \"Animal\"",
  },
  {
    group: "pkl:reflect",
    name: "Class.isSubclassOf walks the parent chain",
    source: "import \"pkl:reflect\" as r\nclass A {}\nclass B extends A {}\nv = r.Class(\"B\").isSubclassOf(r.Class(\"A\"))",
    expect: "v = true",
  },
  {
    group: "pkl:reflect",
    name: "Module.classes lists declared classes",
    source: "import \"pkl:reflect\" as r\nclass A {}\nclass B {}\nv = r.Module(\"self\").classes[1].reflectee",
    expect: "v = \"B\"",
  },
  // pkl:json — Parser shell + parse() implementation.
  {
    group: "pkl:json",
    name: "Parser class instantiable",
    source: "import \"pkl:json\" as json\np = new json.Parser { useMapping = true }\nv = p.useMapping",
    expect: "v = true",
  },
  {
    group: "pkl:json",
    name: "Parser.parse decodes primitives (Dynamic mode)",
    source: "import \"pkl:json\" as json\nv = (new json.Parser {}).parse(\"{\\\"n\\\": 42}\").n",
    expect: "v = 42",
  },
  {
    group: "pkl:json",
    name: "Parser.parse honors useMapping",
    source: "import \"pkl:json\" as json\nv = (new json.Parser { useMapping = true }).parse(\"{\\\"k\\\": \\\"v\\\"}\")",
    expect: "[\"k\"] = \"v\"",
  },
  {
    group: "pkl:json",
    name: "Parser.parse handles nested arrays + objects",
    source: "import \"pkl:json\" as json\nv = (new json.Parser {}).parse(\"[1, {\\\"x\\\": [2, 3]}]\")[1].x[0]",
    expect: "v = 2",
  },
  // pkl:yaml — Parser shell + parse() implementation (via
  // moonbit-community/yaml).
  {
    group: "pkl:yaml",
    name: "Parser class instantiable",
    source: "import \"pkl:yaml\" as yaml\np = new yaml.Parser { useMapping = false }\nv = p.useMapping",
    expect: "v = false",
  },
  {
    group: "pkl:yaml",
    name: "Parser.parse decodes primitives (Dynamic mode)",
    source: "import \"pkl:yaml\" as yaml\nv = (new yaml.Parser {}).parse(\"n: 42\\n\").n",
    expect: "v = 42",
  },
  {
    group: "pkl:yaml",
    name: "Parser.parse honors useMapping",
    source: "import \"pkl:yaml\" as yaml\nv = (new yaml.Parser { useMapping = true }).parse(\"k: v\\n\")",
    expect: "[\"k\"] = \"v\"",
  },
  {
    group: "pkl:yaml",
    name: "Parser.parse handles nested arrays + maps",
    source: "import \"pkl:yaml\" as yaml\nv = (new yaml.Parser {}).parse(\"items:\\n  - 1\\n  - 2\\nnested:\\n  inner: hello\\n\").nested.inner",
    expect: "v = \"hello\"",
  },
  // pkl:xml — Renderer class surface.
  {
    group: "pkl:xml",
    name: "Renderer class instantiable",
    source: "import \"pkl:xml\" as xml\nr = new xml.Renderer { rootElementName = \"config\" }\nv = r.rootElementName",
    expect: "v = \"config\"",
  },
  // pkl:protobuf — Renderer class surface.
  {
    group: "pkl:protobuf",
    name: "Renderer class instantiable",
    source: "import \"pkl:protobuf\" as proto\nr = new proto.Renderer {}\nv = r.indent",
    expect: "v = \"  \"",
  },
  // Remaining public Pkl 0.32 modules — at least one executable contract
  // per URI so adding a synthetic source without a usable surface cannot
  // accidentally count as stdlib coverage.
  {
    group: "pkl:release",
    name: "current version metadata",
    source: "import \"pkl:release\" as release\nv = release.current.version.major",
    expect: "v = 0",
  },
  {
    group: "pkl:Benchmark",
    name: "Microbenchmark result shape",
    source: "import \"pkl:Benchmark\" as Benchmark\nv = (new Benchmark.Microbenchmark { expression = 1 }).run().mean",
    expect: "v = 1.ms",
  },
  {
    group: "pkl:analyze",
    name: "Import record class",
    source: "import \"pkl:analyze\" as analyze\nv = new analyze.Import { uri = \"main.pkl\" }.uri",
    expect: "v = \"main.pkl\"",
  },
  {
    group: "pkl:jsonnet",
    name: "Renderer class surface",
    source: "import \"pkl:jsonnet\" as jsonnet\nv = new jsonnet.Renderer {}.indent",
    expect: "v = \"  \"",
  },
  {
    group: "pkl:shell",
    name: "single quote escaping",
    source: "import \"pkl:shell\" as shell\nv = shell.escapeWithSingleQuotes(\"it's\")",
    expect: "v = \"'it'\\\\''s'\"",
  },
  {
    group: "pkl:EvaluatorSettings",
    name: "Proxy configuration class",
    source: "import \"pkl:EvaluatorSettings\" as s\nv = new s.Proxy { address = \"http://localhost:8080\" }.address",
    expect: "v = \"http://localhost:8080\"",
  },
  {
    group: "pkl:Project",
    name: "Project module amendment",
    source: "import \"pkl:Project\" as Project\nlocal p = (Project) { tests { \"test.pkl\" } }\nv = p.tests.length",
    expect: "v = 1",
  },
  {
    group: "pkl:pklbinary",
    name: "MessagePack byte renderer",
    source: "import \"pkl:pklbinary\" as binary\nv = new binary.Renderer {}.renderValue(Pair(1, \"x\")).base64",
    expect: "v = \"kwkBoXg=\"",
  },
  {
    group: "pkl:Command",
    name: "Flag annotation class",
    source: "import \"pkl:Command\" as Command\nv = new Command.Flag { shortName = \"v\" }.shortName",
    expect: "v = \"v\"",
  },
  {
    group: "pkl:DocPackageInfo",
    name: "PackageDependency class",
    source: "import \"pkl:DocPackageInfo\" as Doc\nv = new Doc.PackageDependency { name = \"birds\"; version = \"1.0.0\"; sourceCode = \"https://example.com/\" }.name",
    expect: "v = \"birds\"",
  },
  {
    group: "pkl:DocsiteInfo",
    name: "descriptor module is amendable",
    source: "import \"pkl:DocsiteInfo\" as Doc\nlocal site = (Doc) { title = \"Example\" }\nv = site.title",
    expect: "v = \"Example\"",
  },
  {
    group: "pkl:settings",
    name: "Editor configuration class",
    source: "import \"pkl:settings\" as settings\nv = new settings.Editor { urlScheme = \"editor://%{path}\" }.urlScheme",
    expect: "v = \"editor://%{path}\"",
  },
]

///|
/// Run every entry in `stdlib_probes`, print a `[PASS] group :: name`
/// or `[FAIL] group :: name` line per probe (with the actual output on
/// failure), and exit non-zero when any probe fails. Designed to be
/// called as `mpkl stdlib`.
fn run_stdlib_check() -> Unit {
  let mut failed = 0
  let mut last_group = ""
  for probe in stdlib_probes {
    if probe.group != last_group {
      if last_group != "" {
        println("")
      }
      println("# \{probe.group}")
      last_group = probe.group
    }
    // Route through `AnalysisSession` (not the import-less `eval_source`)
    // so probes that `import "pkl:math"` etc. resolve through the
    // synthetic stdlib loader.
    let session = @pkl.AnalysisSession::new()
    session.set_source("__probe__.pkl", probe.source)
    match session.eval_path("__probe__.pkl") {
      EvalOk(value) => {
        let rendered = @pkl.render_value(value)
        if rendered.contains(probe.expect) {
          println("[PASS] \{probe.name}")
        } else {
          failed = failed + 1
          println("[FAIL] \{probe.name}")
          println("       expected substring: \{probe.expect}")
          println("       actual rendered:    \{rendered}")
        }
      }
      EvalError(diagnostics) => {
        failed = failed + 1
        println("[FAIL] \{probe.name}")
        for diagnostic in diagnostics {
          println("       diagnostic: \{diagnostic.message}")
        }
      }
    }
  }
  println("")
  let total = stdlib_probes.length()
  let passed = total - failed
  println("stdlib: \{passed} / \{total} passed")
  if failed > 0 {
    @sys.exit(1)
  }
}
