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
    name: "Duration mixed-unit addition (normalizes to smaller unit)",
    source: "v = (3.s + 500.ms).value",
    expect: "v = 3500",
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
  // pkl:reflect — minimal stub.
  {
    group: "pkl:reflect",
    name: "intType mirror constant",
    source: "import \"pkl:reflect\" as r\nv = r.intType",
    expect: "v = \"pkl.base#Int\"",
  },
  {
    group: "pkl:reflect",
    name: "Class factory reflectee",
    source: "import \"pkl:reflect\" as r\nv = r.Class(\"Foo\").reflectee",
    expect: "v = \"Foo\"",
  },
  // pkl:json — Parser shell only (no parsing logic yet).
  {
    group: "pkl:json",
    name: "Parser class instantiable",
    source: "import \"pkl:json\" as json\np = new json.Parser { useMapping = true }\nv = p.useMapping",
    expect: "v = true",
  },
  // pkl:yaml — Parser shell only.
  {
    group: "pkl:yaml",
    name: "Parser class instantiable",
    source: "import \"pkl:yaml\" as yaml\np = new yaml.Parser { useMapping = false }\nv = p.useMapping",
    expect: "v = false",
  },
  // pkl:xml — Renderer class shell only (no rendering yet).
  {
    group: "pkl:xml",
    name: "Renderer class instantiable",
    source: "import \"pkl:xml\" as xml\nr = new xml.Renderer { rootElementName = \"config\" }\nv = r.rootElementName",
    expect: "v = \"config\"",
  },
  // pkl:protobuf — Renderer class shell only.
  {
    group: "pkl:protobuf",
    name: "Renderer class instantiable",
    source: "import \"pkl:protobuf\" as proto\nr = new proto.Renderer {}",
    expect: "r {}",
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
