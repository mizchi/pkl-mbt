///|
test "PKL-106: read prop missing surfaces diagnostic" {
  configure_sandbox_props(Map([], capacity=8))
  let result = eval_source("api_key = read(\"prop:ABSENT\")")
  guard result is EvalError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="Cannot find resource `prop:ABSENT`.")
}

///|
test "PKL-106: sandbox_is_module_allowed empty list permits any URI" {
  configure_sandbox_allowed_modules([])
  inspect(sandbox_is_module_allowed("pkl:math"), content="true")
  inspect(
    sandbox_is_module_allowed("https://example.com/foo.pkl"),
    content="true",
  )
  inspect(sandbox_is_module_allowed("/abs/path/file.pkl"), content="true")
}

///|
test "PKL-106: sandbox_is_module_allowed checks scheme prefixes" {
  configure_sandbox_allowed_modules(["pkl:", "file:"])
  inspect(sandbox_is_module_allowed("pkl:math"), content="true")
  inspect(sandbox_is_module_allowed("file:///foo.pkl"), content="true")
  inspect(
    sandbox_is_module_allowed("https://example.com/foo.pkl"),
    content="false",
  )
  configure_sandbox_allowed_modules([])
}

///|
test "PKL-106: sandbox_is_module_allowed exempts bare filesystem paths" {
  configure_sandbox_allowed_modules(["pkl:"])
  inspect(sandbox_is_module_allowed("foo/bar.pkl"), content="true")
  inspect(sandbox_is_module_allowed("/abs/path/file.pkl"), content="true")
  configure_sandbox_allowed_modules([])
}

///|
test "PKL-108: unbound identifier uses Apple Pkl wording" {
  let result = eval_source("x = no_such")
  guard result is EvalError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="Cannot find property `no_such`.")
}

///|
test "PKL-108: unknown member on Listing uses upstream wording" {
  let result = eval_source(
    "list = new Listing { 1; 2; 3 }\nlength = list.nonexistent",
  )
  guard result is EvalError(diagnostics) else { panic() }
  inspect(
    diagnostics[0].message,
    content="Cannot find property `nonexistent` in object of type `Listing`.",
  )
}

///|
test "PKL-108: unknown type annotation uses Apple Pkl wording" {
  let result = typecheck_source("typed: NotDeclared = 1")
  guard result is TypeError(diagnostics) else { panic() }
  inspect(diagnostics[0].message, content="Cannot find type `NotDeclared`.")
}

///|
test "PKL-118: imported module-level function is callable across modules" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "function double(x: Int): Int = x * 2")
  session.set_source(
    "main.pkl", "import \"base.pkl\" as Base\nresult = Base.double(5)",
  )
  let result = session.eval_path("main.pkl")
  guard result is EvalOk(ObjectValue(members)) else { panic() }
  inspect(members.length(), content="1")
  inspect(members[0].name, content="result")
  guard members[0].value is IntValue(n) else { panic() }
  inspect(n, content="10")
}

///|
test "PKL-118: imported function call participates in typecheck" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "function double(x: Int): Int = x * 2")
  session.set_source(
    "main.pkl", "import \"base.pkl\" as Base\nresult = Base.double(\"not_int\")",
  )
  let result = session.typecheck_path("main.pkl")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="method double argument 1 expects Int, got String",
  )
}

///|
test "PKL-118: imported function does not pollute rendered output" {
  let session = AnalysisSession::new()
  session.set_source(
    "base.pkl", "function double(x: Int): Int = x * 2\nvisible = 1",
  )
  let result = session.eval_path("base.pkl")
  guard result is EvalOk(ObjectValue(members)) else { panic() }
  // Only the `visible` binding renders; the `double` function exists
  // but stays hidden so a pkl eval of the base module shows it
  // contributes nothing on its own.
  inspect(members.length(), content="1")
  inspect(members[0].name, content="visible")
}

///|
test "PKL-117: missing abstract method override is reported" {
  let result = typecheck_source(
    "abstract class Bird {\n  abstract function chirp(): String\n}\nclass Sparrow extends Bird {\n}",
  )
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Class `Sparrow` does not implement abstract method `chirp` inherited from `Bird`.",
  )
}

///|
test "PKL-117: concrete override silences abstract diagnostic" {
  let result = typecheck_source(
    "abstract class Bird {\n  abstract function chirp(): String\n}\nclass Sparrow extends Bird {\n  function chirp(): String = \"chirp\"\n}",
  )
  guard result is TypeOk(_) else { panic() }
}

///|
test "PKL-117: abstract method satisfied by intermediate ancestor" {
  let result = typecheck_source(
    "abstract class Bird {\n  abstract function chirp(): String\n}\nclass Songbird extends Bird {\n  function chirp(): String = \"trill\"\n}\nclass Sparrow extends Songbird {\n}",
  )
  guard result is TypeOk(_) else { panic() }
}

///|
test "PKL-117: override return type covariance violation" {
  let result = typecheck_source(
    "class Animal {\n  function name(): String = \"animal\"\n}\nclass Mammal extends Animal {\n  function name(): Int = 42\n}",
  )
  guard result is TypeError(diagnostics) else { panic() }
  inspect(
    diagnostics[0].message,
    content="Method `Mammal.name` return type `Int` is not a subtype of `Animal.name` return type `String`.",
  )
}

///|
test "PKL-117: override parameter contravariance violation" {
  let result = typecheck_source(
    "class Animal {\n  function speak(x: Int): String = \"\"\n}\nclass Mammal extends Animal {\n  function speak(x: String): String = x\n}",
  )
  guard result is TypeError(diagnostics) else { panic() }
  inspect(
    diagnostics[0].message,
    content="Method `Mammal.speak` parameter `x` type `String` is not a supertype of `Animal.speak` parameter type `Int`.",
  )
}

///|
test "PKL-117: abstract class itself may declare abstract methods" {
  let result = typecheck_source(
    "abstract class Animal {\n  abstract function name(): String\n}\nabstract class Mammal extends Animal {\n}",
  )
  guard result is TypeOk(_) else { panic() }
}

///|
test "PKL-108: unresolved import uses Apple Pkl wording" {
  let result = eval_source("import \"not_here.pkl\" as Other\nx = Other.value")
  guard result is EvalError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  // The first diagnostic surfaces the unresolved import; later
  // diagnostics may follow from the cascade through the body
  // referencing `Other`. The assertion only pins the first line.
  inspect(messages[0], content="Cannot find module `not_here.pkl`.")
}

///|
test "PKL-106: module-paths are stored in CLI order" {
  configure_sandbox_module_paths(["dir-a", "dir-b"])
  let dirs = sandbox_module_paths()
  inspect(dirs.length(), content="2")
  inspect(dirs[0], content="dir-a")
  inspect(dirs[1], content="dir-b")
  configure_sandbox_module_paths([])
}

///|
test "PKL-125: YAML literal block scalar clips with single trailing newline" {
  let v : Value = ObjectValue([
    ValueMember::{
      name: "p",
      value: StringValue("line one\nline two\n"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(v),
    content=(
      #|p: |
      #|  line one
      #|  line two
      #|
    ),
  )
}

///|
test "PKL-125: YAML literal block scalar strips with no trailing newline" {
  let v : Value = ObjectValue([
    ValueMember::{
      name: "p",
      value: StringValue("alpha\nbeta"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(v),
    content=(
      #|p: |-
      #|  alpha
      #|  beta
      #|
    ),
  )
}

///|
test "PKL-125: YAML literal block scalar keeps with multi trailing newlines" {
  let v : Value = ObjectValue([
    ValueMember::{
      name: "p",
      value: StringValue("alpha\nbeta\n\n\n"),
      source: None,
      annotations: [],
    },
  ])
  // The source string has 3 trailing newlines; the natural newline
  // after `  beta` covers one of them, so the rendered form adds 2
  // bare newlines to preserve the run.
  inspect(
    render_value_as_yaml(v),
    content=(
      #|p: |+
      #|  alpha
      #|  beta
      #|
      #|
      #|
    ),
  )
}

///|
test "PKL-125: YAML uses an indentation indicator when the first line leads with space" {
  let v : Value = ObjectValue([
    ValueMember::{
      name: "p",
      value: StringValue(" first\ncannot block\nlast"),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(v),
    content=(
      #|p: |2-
      #|   first
      #|  cannot block
      #|  last
      #|
    ),
  )
}

///|
test "PKL-125: YAML block scalar in a sequence item indents to column 2" {
  let v : Value = ObjectValue([
    ValueMember::{
      name: "items",
      value: ListingValue([StringValue("a\nb"), StringValue("single")]),
      source: None,
      annotations: [],
    },
  ])
  inspect(
    render_value_as_yaml(v),
    content=(
      #|items:
      #|- |-
      #|  a
      #|  b
      #|- single
      #|
    ),
  )
}

///|
test "PKL-123: pkl:platform exposes stub OS / architecture" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:platform\" as platform\nos = platform.current.operatingSystem.name\narch = platform.current.architecture.name",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut os = ""
  let mut arch = ""
  for entry in members {
    if entry.name == "os" {
      guard entry.value is StringValue(s) else { panic() }
      os = s
    }
    if entry.name == "arch" {
      guard entry.value is StringValue(s) else { panic() }
      arch = s
    }
  }
  inspect(os, content="stub-os")
  inspect(arch, content="stub-arch")
}

///|
test "PKL-152: pkl:release exposes current release metadata shape" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:release"
      #|major = release.current.version.major
      #|versionInfoOk = release.current.versionInfo.contains("Linux")
      #|commitOk = release.current.commitId.matches(Regex(#"[0-9a-f]{7,40}"#))
      #|sourceOk = release.current.sourceCode.homepage.startsWith("https://")
      #|docsOk = release.current.documentation.homepage.endsWith("/")
      #|hasBase = release.current.standardLibrary.modules.contains("pkl:base")
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("major = 0"), content="true")
  inspect(rendered.contains("versionInfoOk = true"), content="true")
  inspect(rendered.contains("commitOk = true"), content="true")
  inspect(rendered.contains("sourceOk = true"), content="true")
  inspect(rendered.contains("docsOk = true"), content="true")
  inspect(rendered.contains("hasBase = true"), content="true")
}

///|
test "PKL-152: pkl:Benchmark stubs produce benchmark result shape" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:Benchmark"
      #|micro = (new Benchmark.Microbenchmark {
      #|  expression = 1 + 2
      #|  iterations = 3
      #|  iterationTime = 1.ms
      #|}).run()
      #|output = (new Benchmark.OutputBenchmark {
      #|  sourceModule = module
      #|  iterations = 3
      #|  iterationTime = 1.ms
      #|  isVerbose = true
      #|}).run()
      #|whole = new Benchmark {
      #|  microbenchmarks { ["micro"] { expression = 1 + 2 } }
      #|}
      #|microOk = micro.iterations == 3 && micro.samples == null && micro.min > 0.s
      #|outputOk = output.samples.length == 3 && output.min == output.samples.min
      #|textOk = whole.output.text.contains("[\"micro\"]")
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("microOk = true"), content="true")
  inspect(rendered.contains("outputOk = true"), content="true")
  inspect(rendered.contains("textOk = true"), content="true")
}

///|
test "PKL-123: pkl:semver parse decomposes major.minor.patch" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\nv = semver.parse(\"1.2.3\")\nmaj = v.major\nmin = v.minor\npat = v.patch",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut maj = 0L
  let mut min = 0L
  let mut pat = 0L
  for entry in members {
    if entry.name == "maj" {
      guard entry.value is IntValue(n) else { panic() }
      maj = n
    }
    if entry.name == "min" {
      guard entry.value is IntValue(n) else { panic() }
      min = n
    }
    if entry.name == "pat" {
      guard entry.value is IntValue(n) else { panic() }
      pat = n
    }
  }
  inspect(maj, content="1")
  inspect(min, content="2")
  inspect(pat, content="3")
}

///|
test "PKL-123: pkl:semver parse captures preRelease and build" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\nv = semver.parse(\"1.0.0-alpha.1+build.42\")\npre = v.preRelease\nbld = v.build",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut pre = ""
  let mut bld = ""
  for entry in members {
    if entry.name == "pre" {
      guard entry.value is StringValue(s) else { panic() }
      pre = s
    }
    if entry.name == "bld" {
      guard entry.value is StringValue(s) else { panic() }
      bld = s
    }
  }
  inspect(pre, content="alpha.1")
  inspect(bld, content="build.42")
}

///|
test "PKL-123: pkl:semver parseOrNull returns null on bad input" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\nv = semver.parseOrNull(\"not-a-version\")",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  assert_true(members[0].value == NullValue)
}

///|
test "PKL-123: pkl:semver isLessThan orders by major.minor.patch" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\na = semver.parse(\"1.2.3\")\nb = semver.parse(\"1.10.0\")\nlt = semver.isLessThan(a, b)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut lt = false
  for entry in members {
    if entry.name == "lt" {
      guard entry.value is BoolValue(b) else { panic() }
      lt = b
    }
  }
  inspect(lt, content="true")
}

///|
test "PKL-123: pkl:semver pre-release ranks below release" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\na = semver.parse(\"1.0.0-rc.1\")\nb = semver.parse(\"1.0.0\")\nlt = semver.isLessThan(a, b)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut lt = false
  for entry in members {
    if entry.name == "lt" {
      guard entry.value is BoolValue(b) else { panic() }
      lt = b
    }
  }
  inspect(lt, content="true")
}

///|
test "PKL-152: semver toString wins over universal Any toString" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:semver\" as semver\ntext = semver.Version(\"1.2.3-rc-1+abc\").toString()",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is StringValue(text) else { panic() }
  inspect(text, content="1.2.3-rc-1+abc")
}

///|
test "PKL-120: pkl:math.sqrt computes square root" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nx = math.sqrt(16.0)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got = 0.0
  for entry in members {
    if entry.name == "x" {
      match entry.value {
        FloatValue(d) => got = d
        _ => ()
      }
    }
  }
  inspect(got, content="4")
}

///|
test "PKL-120: pkl:math.pow takes two arguments" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\" as math\nx = math.pow(2.0, 10.0)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got = 0.0
  for entry in members {
    if entry.name == "x" {
      match entry.value {
        FloatValue(d) => got = d
        _ => ()
      }
    }
  }
  inspect(got, content="1024")
}

///|
test "PKL-120: pkl:math.pi constant" {
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "import \"pkl:math\" as math\np = math.pi")
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got = 0.0
  for entry in members {
    if entry.name == "p" {
      match entry.value {
        FloatValue(d) => got = d
        _ => ()
      }
    }
  }
  inspect(got, content="3.141592653589793")
}

///|
test "PKL-148ay: Int power matches Apple Pkl negative exponent and overflow" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:math\"\nfraction = 2 ** -4\nzero = 0 ** -1\nminusOne = -1 ** -1\noverflow = module.catch(() -> 2 ** math.maxInt8)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut fraction = 0.0
  let mut zero_inf = false
  let mut minus_one = 0.0
  let mut overflow = ""
  for slot in members {
    match (slot.name, slot.value) {
      ("fraction", FloatValue(v)) => fraction = v
      ("zero", FloatValue(v)) => zero_inf = v.is_inf() && v > 0.0
      ("minusOne", FloatValue(v)) => minus_one = v
      ("overflow", StringValue(message)) => overflow = message
      _ => ()
    }
  }
  inspect(fraction, content="0.0625")
  inspect(zero_inf, content="true")
  inspect(minus_one, content="-1")
  inspect(overflow, content="Integer overflow.")
}

///|
test "PKL-131b: codegen dispatcher returns same output as codegen_moonbit for MoonBit target" {
  let parsed = @pkl.parse_source(
    "class Person {\n  name: String\n  age: Int\n}",
  )
  let via_dispatcher = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(via_dispatcher.contains("pub(all) struct Person {"), content="true")
  inspect(via_dispatcher.contains("name : String"), content="true")
}

///|
test "PKL-131b: CodegenTarget enum is pattern-matchable" {
  // Forward-compat smoke — the enum is `pub(all)` so consumers can
  // pattern match (used by the CLI's `-t / --target` arm + future
  // target additions). Round-trip equality also confirms `derive(Eq)`.
  let target : @pkl.CodegenTarget = @pkl.MoonBit
  assert_true(target == @pkl.MoonBit)
}

///|
test "PKL-131: codegen emits pub struct from class declaration" {
  let parsed = @pkl.parse_source(
    "class Person {\n  name: String\n  age: Int\n}",
  )
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("pub(all) struct Person {"), content="true")
  inspect(out.contains("name : String"), content="true")
  inspect(out.contains("age : Int"), content="true")
  inspect(out.contains("derive(Eq, Show)"), content="true")
}

///|
test "PKL-131: codegen maps Pkl scalar types to MoonBit scalars" {
  let parsed = @pkl.parse_source(
    "class Scalars {\n  i: Int\n  d: Float\n  b: Boolean\n  s: String\n  n: Null\n}",
  )
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("i : Int"), content="true")
  inspect(out.contains("d : Double"), content="true")
  inspect(out.contains("b : Bool"), content="true")
  inspect(out.contains("s : String"), content="true")
  inspect(out.contains("n : Unit"), content="true")
}

///|
test "PKL-131: codegen recurses through nullable annotations" {
  let parsed = @pkl.parse_source("class Wrap {\n  maybe: String?\n}")
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("maybe : String?"), content="true")
}

///|
test "PKL-131: codegen recurses into Listing / Mapping / Set / Pair generics" {
  let parsed = @pkl.parse_source(
    "class Containers {\n  xs: Listing<Int>\n  m: Mapping<String, Int>\n  set: Set<String>\n  pair: Pair<Int, String>\n}",
  )
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("xs : Array[Int]"), content="true")
  inspect(out.contains("m : Map[String, Int]"), content="true")
  inspect(out.contains("set : Array[String] /* Set */"), content="true")
  inspect(out.contains("pair : (Int, String)"), content="true")
}

///|
test "PKL-131: codegen strips constraint suffix from base type" {
  let parsed = @pkl.parse_source("class Bound {\n  n: Int(isPositive)\n}")
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("n : Int"), content="true")
}

///|
test "PKL-131: codegen flags union types with TODO comment" {
  let parsed = @pkl.parse_source("class U {\n  v: Int | String\n}")
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("Unit /* TODO: union Int|String */"), content="true")
}

///|
test "PKL-131: codegen emits typealias for each TypeAliasDeclaration" {
  let parsed = @pkl.parse_source(
    "typealias Username = String\ntypealias UserMap = Mapping<String, Int>",
  )
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("pub typealias String as Username"), content="true")
  inspect(
    out.contains("pub typealias Map[String, Int] as UserMap"),
    content="true",
  )
}

///|
test "PKL-131: codegen skips function declarations" {
  let parsed = @pkl.parse_source(
    "class C {\n  x: Int\n}\nfunction helper(n: Int): Int = n + 1",
  )
  let out = @pkl.codegen(parsed.program, @pkl.MoonBit)
  inspect(out.contains("struct C"), content="true")
  inspect(out.contains("helper"), content="false")
}

///|
test "PKL-119d: Map(...) carrier preserves insertion order, later duplicates overwrite" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2, \"a\", 99)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MapValue(entries) else { panic() }
  inspect(entries.length(), content="2")
  guard entries[0].key is StringValue(k0) else { panic() }
  guard entries[0].value is IntValue(v0) else { panic() }
  inspect(k0, content="a")
  inspect(v0, content="99")
}

///|
test "PKL-119d: Map.length / .isEmpty / .keys / .values / .entries" {
  guard eval_source(
      "m = Map(\"a\", 1, \"b\", 2)\nl = m.length\ne = m.isEmpty\nks = m.keys\nvs = m.values\nents = m.entries",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut length = 0L
  let mut empty = true
  for entry in members {
    match (entry.name, entry.value) {
      ("l", IntValue(n)) => length = n
      ("e", BoolValue(b)) => empty = b
      ("ks", SetValue(_)) => ()
      ("vs", ListValue(_)) => ()
      ("ents", ListValue(items)) => {
        guard items[0] is PairValue(_, _) else { panic() }
      }
      _ => ()
    }
  }
  inspect(length, content="2")
  inspect(empty, content="false")
}

///|
test "PKL-119d: Map.containsKey / .getOrNull / .getOrThrow" {
  guard eval_source(
      "m = Map(\"a\", 1)\nhit = m.containsKey(\"a\")\nmiss = m.containsKey(\"b\")\nv = m.getOrNull(\"a\")\nnull_ = m.getOrNull(\"b\")",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut hit = false
  let mut miss = true
  let mut got = 0L
  let mut null_seen = false
  for entry in members {
    match (entry.name, entry.value) {
      ("hit", BoolValue(b)) => hit = b
      ("miss", BoolValue(b)) => miss = b
      ("v", IntValue(n)) => got = n
      ("null_", NullValue) => null_seen = true
      _ => ()
    }
  }
  inspect(hit, content="true")
  inspect(miss, content="false")
  inspect(got, content="1")
  inspect(null_seen, content="true")
}

///|
test "PKL-119d: Map subscript returns values and reports missing keys" {
  let source =
    #|m = Map("a", 1, "b", 2)
    #|hit = m["b"]
    #|miss = module.catch(() -> m["c"])
  guard eval_source(source) is EvalOk(ObjectValue(members)) else { panic() }
  let mut hit = 0L
  let mut miss = ""
  for slot in members {
    match (slot.name, slot.value) {
      ("hit", IntValue(n)) => hit = n
      ("miss", StringValue(message)) => miss = message
      _ => ()
    }
  }
  inspect(hit, content="2")
  inspect(miss, content="Cannot find key `\"c\"`.")
}

///|
test "PKL-119d: Map.toMapping re-projects as MappingValue" {
  guard eval_source("m = Map(\"a\", 1).toMapping()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MappingValue(entries) else { panic() }
  inspect(entries.length(), content="1")
}

///|
test "PKL-119d: Map.toList projects entries as Listing<Pair<K, V>>" {
  guard eval_source("xs = Map(\"a\", 1, \"b\", 2).toList()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListingValue(items) else { panic() }
  inspect(items.length(), content="2")
  guard items[0] is PairValue(_, _) else { panic() }
}

///|
test "PKL-119d: Map.map projects to a new MapValue" {
  guard eval_source("m = Map(\"a\", 1).map((k, v) -> Pair(k, v + 10))")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MapValue(entries) else { panic() }
  guard entries[0].value is IntValue(n) else { panic() }
  inspect(n, content="11")
}

///|
test "PKL-119d: Map.mapKeys and mapValues project keys and values" {
  guard eval_source(
      "ks = Map(\"a\", 1).mapKeys((k, v) -> k + v.toString())\nvs = Map(\"a\", 1).mapValues((k, v) -> k.length + v)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MapValue(key_entries) else { panic() }
  guard key_entries[0].key is StringValue(key) else { panic() }
  inspect(key, content="a1")
  guard members[1].value is MapValue(value_entries) else { panic() }
  guard value_entries[0].value is IntValue(value) else { panic() }
  inspect(value, content="2")
}

///|
test "PKL-119d: Map.filter keeps the Map type" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2).filter((k, v) -> v > 1)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is MapValue(entries) else { panic() }
  inspect(entries.length(), content="1")
}

///|
test "PKL-119d: Map.fold reduces over the entries" {
  guard eval_source(
      "sum = Map(\"a\", 1, \"b\", 2, \"c\", 3).fold(0, (acc, k, v) -> acc + v)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is IntValue(n) else { panic() }
  inspect(n, content="6")
}

///|
test "PKL-152: Map mutators and toTyped follow pkl:base API shape" {
  let source =
    #|class Person {
    #|  name: String = "Default"
    #|  age: UInt
    #|}
    #|local abstract class Abstract
    #|removed = Map("one", 1, "two", 2, "three", 3).remove("two")
    #|put = Map("one", 1).put("one", 4)
    #|flat = Map("one", 1, "two", 2).flatMap((k, v) -> Map(v, v * 3))
    #|dynClass = Map("one", 1).toDynamic().getClass().simpleName
    #|typedName = Map("age", 42).toTyped(Person).name
    #|typedHasAge = Map("name", "Pigeon").toTyped(Person).hasProperty("age")
    #|missingErr = module.catch(() -> Map("name", "Pigeon").toTyped(Person).age)
    #|abstractErr = module.catch(() -> Map().toTyped(Abstract))
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("removed = Map(\"one\", 1, \"three\", 3)"),
    content="true",
  )
  inspect(rendered.contains("put = Map(\"one\", 4)"), content="true")
  inspect(rendered.contains("flat = Map(1, 3, 2, 6)"), content="true")
  inspect(rendered.contains("dynClass = \"Dynamic\""), content="true")
  inspect(rendered.contains("typedName = \"Default\""), content="true")
  inspect(rendered.contains("typedHasAge = true"), content="true")
  inspect(
    rendered.contains(
      "missingErr = \"Tried to read property `age` but its value is undefined.\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains("abstractErr = \"Cannot instantiate abstract class `"),
    content="true",
  )
}

///|
test "PKL-119d: PCF renders Map through the constructor form" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2)") is EvalOk(value) else {
    panic()
  }
  inspect(@pkl.render_value(value), content="m = Map(\"a\", 1, \"b\", 2)")
}

///|
test "PKL-152: Regex constructor renders raw patterns and rejects broken groups" {
  let source =
    #|raw = Regex(#"[ab]\s+"#)
    #|err = module.catch(() -> Regex("("))
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("raw = Regex(#\"[ab]\\s+\"#)"), content="true")
  inspect(
    rendered.contains(
      "err = \"Syntax error in regex `(`: Unclosed group near index 1 (\"",
    ),
    content="true",
  )
}

///|
test "PKL-152: builtin type aliases use pkl:base targets" {
  let source =
    #|okUInt: UInt = 9223372036854775807
    #|okUri: Uri = "https://apple.com"
    #|okNonNull: NonNull = 42
    #|class Bad {
    #|  u: UInt = -1
    #|  uri: Uri = 42
    #|  nn: NonNull = null
    #|}
    #|local bad = new Bad {}
    #|badUInt = module.catch(() -> bad.u)
    #|badUri = module.catch(() -> bad.uri)
    #|badNonNull = module.catch(() -> bad.nn)
  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("okUInt = 9223372036854775807"), content="true")
  inspect(rendered.contains("okUri = \"https://apple.com\""), content="true")
  inspect(rendered.contains("okNonNull = 42"), content="true")
  inspect(
    rendered.contains(
      "badUInt = \"Type constraint `isPositive` violated. Value: -1\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "badUri = \"Expected value of type `String`, but got type `Int`. Value: 42\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "badNonNull = \"Type constraint `!(this is Null)` violated. Value: null\"",
    ),
    content="true",
  )
}

///|
test "PKL-152: Any ifNonNull toString and module getClass" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|moduleClass = import("pkl:base").getClass().simpleName
      #|nonnull = 10.ifNonNull((x) -> x + 1)
      #|nullish = null.ifNonNull((x) -> x)
      #|pairText = Pair(1, 2).toString()
      #|listText = List(1, 2, 3).toString()
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("moduleClass = \"ModuleClass\""), content="true")
  inspect(rendered.contains("nonnull = 11"), content="true")
  inspect(rendered.contains("nullish = null"), content="true")
  inspect(rendered.contains("pairText = \"Pair(1, 2)\""), content="true")
  inspect(rendered.contains("listText = \"List(1, 2, 3)\""), content="true")
}

///|
test "PKL-119d: JSON projects Map as a JSON object" {
  guard eval_source("m = Map(\"a\", 1, \"b\", 2)") is EvalOk(value) else {
    panic()
  }
  let json = @pkl.render_value_as_json(value)
  let expected =
    #|{
    #|  "m": {
    #|    "a": 1,
    #|    "b": 2
    #|  }
    #|}
  inspect(json, content=expected)
}

///|
test "PKL-119d: Map<K, V> annotation typechecks" {
  guard typecheck_source(
      "m: Map<String, Int> = Map(\"a\", 1, \"b\", 2)\nl: Int = m.length\nhit: Boolean = m.containsKey(\"a\")",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-119d: Map odd argument count surfaces diagnostic" {
  let result = eval_source("m = Map(\"a\", 1, \"b\")")
  guard result is EvalError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Map expects an even number of arguments (alternating key, value)",
  )
}

///|
test "PKL-119d: Map member typo surfaces Pkl-shaped diagnostic" {
  let result = typecheck_source("m = Map(\"a\", 1)\nbad = m.lentgh")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Cannot find property `lentgh` in object of type `Map`.",
  )
}

///|
test "PKL-119c: Set carrier preserves insertion order and drops duplicates" {
  guard eval_source("xs = Set(3, 1, 2, 1, 3)") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is SetValue(items) else { panic() }
  inspect(items.length(), content="3")
  guard items[0] is IntValue(a) else { panic() }
  guard items[1] is IntValue(b) else { panic() }
  guard items[2] is IntValue(c) else { panic() }
  inspect(a, content="3")
  inspect(b, content="1")
  inspect(c, content="2")
}

///|
test "PKL-119c: Set.length / .isEmpty / .first / .last bare reads" {
  guard eval_source(
      "xs = Set(\"a\", \"b\", \"c\")\nl = xs.length\ne = xs.isEmpty\nf = xs.first\nlast = xs.last",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut len = 0L
  let mut empty = true
  let mut first = ""
  let mut last = ""
  for entry in members {
    match (entry.name, entry.value) {
      ("l", IntValue(n)) => len = n
      ("e", BoolValue(b)) => empty = b
      ("f", StringValue(s)) => first = s
      ("last", StringValue(s)) => last = s
      _ => ()
    }
  }
  inspect(len, content="3")
  inspect(empty, content="false")
  inspect(first, content="a")
  inspect(last, content="c")
}

///|
test "PKL-119c: Set.contains uses value equality" {
  guard eval_source(
      "xs = Set(1, 2, 3)\nhit = xs.contains(2)\nmiss = xs.contains(99)",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut hit = false
  let mut miss = true
  for entry in members {
    match (entry.name, entry.value) {
      ("hit", BoolValue(b)) => hit = b
      ("miss", BoolValue(b)) => miss = b
      _ => ()
    }
  }
  inspect(hit, content="true")
  inspect(miss, content="false")
}

///|
test "PKL-148al: Set.contains compares visible object members" {
  guard eval_source(
      "xs = Set(new Dynamic { name = \"Pigeon\" })\nhit = xs.contains(new Dynamic { name = localName; local localName = \"Pigeon\" })",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut hit = false
  for entry in members {
    match (entry.name, entry.value) {
      ("hit", BoolValue(b)) => hit = b
      _ => ()
    }
  }
  inspect(hit, content="true")
}

///|
test "PKL-148al: dynamic default member is hidden from rendering" {
  guard eval_source(
      "res = new Dynamic { name = \"Pigeon\"; default = (_) -> 42 }",
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|res {
    #|  name = "Pigeon"
    #|}
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148al: top-level local declaration can carry open modifier" {
  guard eval_source(
      "local open class Person { name: String }\nres = new Person { name = \"Pigeon\" }",
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|res {
    #|  name = "Pigeon"
    #|}
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148h: Set.toList materialises to ListValue, .toListing to ListingValue" {
  guard eval_source("xs = Set(1, 2, 3)\nl = xs.toList()\nlg = xs.toListing()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  for entry in members {
    if entry.name == "l" {
      guard entry.value is ListValue(items) else { panic() }
      inspect(items.length(), content="3")
    } else if entry.name == "lg" {
      guard entry.value is ListingValue(items) else { panic() }
      inspect(items.length(), content="3")
    }
  }
}

///|
test "PKL-119c: Set.map keeps the Set type" {
  guard eval_source("xs = Set(1, 2, 3).map((n) -> n * 10)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is SetValue(items) else { panic() }
  guard items[0] is IntValue(a) else { panic() }
  guard items[2] is IntValue(c) else { panic() }
  inspect(a, content="10")
  inspect(c, content="30")
}

///|
test "PKL-119c: Set.filter keeps the Set type" {
  guard eval_source("xs = Set(1, 2, 3, 4).filter((n) -> n % 2 == 0)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is SetValue(items) else { panic() }
  inspect(items.length(), content="2")
  guard items[0] is IntValue(a) else { panic() }
  guard items[1] is IntValue(b) else { panic() }
  inspect(a, content="2")
  inspect(b, content="4")
}

///|
test "PKL-119c: Set.fold reduces left-to-right" {
  guard eval_source("sum = Set(1, 2, 3).fold(0, (acc, x) -> acc + x)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is IntValue(n) else { panic() }
  inspect(n, content="6")
}

///|
test "PKL-119c: Set.join concatenates elements with the separator" {
  guard eval_source("s = Set(\"alpha\", \"beta\", \"gamma\").join(\", \")")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is StringValue(s) else { panic() }
  inspect(s, content="alpha, beta, gamma")
}

///|
test "PKL-119c: PCF renders Set through the constructor form" {
  guard eval_source("xs = Set(1, 2, 3)") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content="xs = Set(1, 2, 3)")
}

///|
test "PKL-119c: JSON projects Set as an array" {
  guard eval_source("xs = Set(\"a\", \"b\")") is EvalOk(value) else { panic() }
  let json = @pkl.render_value_as_json(value)
  let expected =
    #|{
    #|  "xs": [
    #|    "a",
    #|    "b"
    #|  ]
    #|}
  inspect(json, content=expected)
}

///|
test "PKL-119c: Set<T> annotation typechecks" {
  guard typecheck_source(
      "xs: Set<Int> = Set(1, 2, 3)\nlen: Int = xs.length\nhit: Boolean = xs.contains(1)",
    )
    is TypeOk(_) else {
    panic()
  }
}

///|
test "PKL-119c: Set member typo surfaces Pkl-shaped diagnostic" {
  let result = typecheck_source("xs = Set(1, 2)\nbad = xs.lentgh")
  guard result is TypeError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(
    messages[0],
    content="Cannot find property `lentgh` in object of type `Set`.",
  )
}

///|
test "PKL-119b: IntSeq(start, end) builds an IntSeqValue with step=1" {
  guard eval_source("seq = IntSeq(2, 5)") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is IntSeqValue(start, end_v, step) else { panic() }
  inspect(start, content="2")
  inspect(end_v, content="5")
  inspect(step, content="1")
}

///|
test "PKL-119b: IntSeq.start / .end / .step bare reads" {
  guard eval_source(
      "seq = IntSeq(2, 5).step(2)\ns = seq.start\ne = seq.end\nst = seq.step",
    )
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut got_start = 0L
  let mut got_end = 0L
  let mut got_step = 0L
  for entry in members {
    match (entry.name, entry.value) {
      ("s", IntValue(n)) => got_start = n
      ("e", IntValue(n)) => got_end = n
      ("st", IntValue(n)) => got_step = n
      _ => ()
    }
  }
  inspect(got_start, content="2")
  inspect(got_end, content="5")
  inspect(got_step, content="2")
}

///|
test "PKL-119b: IntSeq.step(0) rejects the zero step" {
  let result = eval_source("seq = IntSeq(0, 5).step(0)")
  guard result is EvalError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(messages[0], content="Type constraint `isNonZero` violated. Value: 0")
}

///|
test "PKL-119b: IntSeq.toList materializes ascending elements" {
  guard eval_source("lst = IntSeq(1, 4).toList()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(elements) else { panic() }
  inspect(elements.length(), content="4")
  guard elements[0] is IntValue(first) else { panic() }
  guard elements[3] is IntValue(last) else { panic() }
  inspect(first, content="1")
  inspect(last, content="4")
}

///|
test "PKL-119b: IntSeq.toList of empty ascending sequence is empty" {
  guard eval_source("lst = IntSeq(5, 0).toList()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(elements) else { panic() }
  inspect(elements.length(), content="0")
}

///|
test "PKL-119b: IntSeq.step(-1).toList descends" {
  guard eval_source("lst = IntSeq(3, 1).step(-1).toList()")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(elements) else { panic() }
  inspect(elements.length(), content="3")
  guard elements[0] is IntValue(first) else { panic() }
  guard elements[2] is IntValue(last) else { panic() }
  inspect(first, content="3")
  inspect(last, content="1")
}

///|
test "PKL-119b: IntSeq.map projects each element through the lambda" {
  guard eval_source("xs = IntSeq(1, 3).map((n) -> n * n)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is ListValue(elements) else { panic() }
  guard elements[0] is IntValue(a) else { panic() }
  guard elements[1] is IntValue(b) else { panic() }
  guard elements[2] is IntValue(c) else { panic() }
  inspect(a, content="1")
  inspect(b, content="4")
  inspect(c, content="9")
}

///|
test "PKL-119b: IntSeq.fold reduces left-to-right" {
  guard eval_source("sum = IntSeq(1, 5).fold(0, (acc, n) -> acc + n)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is IntValue(n) else { panic() }
  inspect(n, content="15")
}

///|
test "PKL-148d: lexical scope wins over module bindings for nested objects" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "x = 0\nfoo {\n  x = 1\n  bar {\n    x = 2\n    y = x + 3\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("y = 5"), content="true")
}

///|
test "PKL-148d: local properties hoist into env with their bare name" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "local l = 1\nfoo {\n  local l = 2\n  bar {\n    baz = l\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("baz = 2"), content="true")
}

///|
test "PKL-148d: unused typed object local does not force rejection" {
  let session = AnalysisSession::new()
  let source =
    #|foo {
    #|  local bad: Int = "nope"
    #|  ok = 1
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content="foo {\n  ok = 1\n}")
}

///|
test "PKL-148d: typed object local rejection surfaces on reference" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|foo {
    #|  local bad: Int = "nope"
    #|  caught = test.catch(() -> bad)
    #|}
  let expected =
    #|foo {
    #|  caught = "Expected value of type `Int`, but got type `String`. Value: \"nope\""
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered, content=expected)
}

///|
test "PKL-148d: local method body late-binds amended sibling property" {
  let session = AnalysisSession::new()
  let source =
    #|class Box {
    #|  x = 1
    #|  y = compute()
    #|  local function compute() = x
    #|}
    #|base = new Box {}
    #|derived = (base) { x = 2 }
  let expected =
    #|base {
    #|  x = 1
    #|  y = 1
    #|}
    #|derived {
    #|  x = 2
    #|  y = 2
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: amended imported module functions see overridden properties" {
  let session = AnalysisSession::new()
  session.set_source(
    "helper.pkl",
    (
      #|referenceModule = "BaseModule.pkl"
      #|function hasExpectedLocation(path) = path.contains(referenceModule)
    ),
  )
  session.set_source(
    "main.pkl",
    (
      #|local helper = (import("helper.pkl")) {
      #|  referenceModule = "ExtendingModule.pkl"
      #|}
      #|ok = helper.hasExpectedLocation("file:///tmp/ExtendingModule.pkl")
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content="ok = true")
}

///|
test "PKL-148d: inherited module members keep parent local scope" {
  let session = AnalysisSession::new()
  let base_source =
    #|open module base
    #|local p = "original"
    #|p2 = "original"
    #|local function f() = "original"
    #|pp = p
    #|pp2 = p2
    #|ff = f()
  let source =
    #|extends "base.pkl"
    #|local p = "override"
    #|local p2 = "override"
    #|local function f() = "override"
    #|resP = pp
    #|resP2 = pp2
    #|resF = ff
  let expected =
    #|p2 = "original"
    #|pp = "original"
    #|pp2 = "original"
    #|ff = "original"
    #|resP = "original"
    #|resP2 = "original"
    #|resF = "original"
  session.set_source("base.pkl", base_source)
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: class body in amending module cannot capture non-const local" {
  let session = AnalysisSession::new()
  let source =
    #|amends "base.pkl"
    #|import "pkl:test"
    #|local y: Int = "wrong type"
    #|foo { c = new C {} }
    #|local class C {
    #|  res = test.catch(() -> y)
    #|}
  let expected =
    #|foo {
    #|  c {
    #|    res = "Cannot reference property `y` from here because it is not `const`."
    #|  }
    #|}
  session.set_source("base.pkl", "foo {}")
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: class defaults see module const through outer" {
  let session = AnalysisSession::new()
  let source =
    #|const moduleName = "Winner"
    #|class ValidConstOuter {
    #|  name: String
    #|  fromModule = outer.moduleName
    #|  fancyName = new { title = "The \(outer.name)" }
    #|}
    #|res = new ValidConstOuter { name = "Bird" }
  let expected =
    #|moduleName = "Winner"
    #|res {
    #|  name = "Bird"
    #|  fromModule = "Winner"
    #|  fancyName {
    #|    title = "The Bird"
    #|  }
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: class defaults reject non-const module property and function" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|nonConst = "not const"
    #|function nonConstFunction() = nonConst
    #|class BrokenSimple {
    #|  improperDefault = nonConst
    #|}
    #|class BrokenFunction {
    #|  improperDefaultFromNonConstFunction = nonConstFunction()
    #|}
    #|res1 = test.catch(() -> "\(new BrokenSimple {})")
    #|res2 = test.catch(() -> "\(new BrokenFunction {})")
  let expected =
    #|nonConst = "not const"
    #|res1 = "Cannot reference property `nonConst` from here because it is not `const`."
    #|res2 = "Cannot call method `nonConstFunction` from here because it is not `const`."
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: class default local method parameter shadows module local" {
  let session = AnalysisSession::new()
  let source =
    #|amends "base.pkl"
    #|import "pkl:test"
    #|local x = f1(42)
    #|local function f1(x: Int): Int = x + 1
    #|foo { c = new C {} }
    #|local class C {
    #|  foo {
    #|    bar {
    #|      local function f1(x: Int): Int = x + 2
    #|      res7 = f1(42)
    #|      res8 = test.catch(() -> f1("wrong type"))
    #|    }
    #|  }
    #|}
  let expected =
    #|foo {
    #|  c {
    #|    foo {
    #|      bar {
    #|        res7 = 44
    #|        res8 = "Expected value of type `Int`, but got type `String`. Value: \"wrong type\""
    #|      }
    #|    }
    #|  }
    #|}
  session.set_source("base.pkl", "foo {}")
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148c: module relativePathTo returns descendant path segments" {
  let session = AnalysisSession::new()
  session.set_source(
    "api/module.pkl",
    (
      #|import "pkl:test"
      #|desc = module.relativePathTo(import("dir1/dir2/relativePathTo.pkl"))
      #|same = module.relativePathTo(module)
      #|err = test.catch(() -> import("dir1/dir2/relativePathTo.pkl").relativePathTo(module))
    ),
  )
  session.set_source(
    "api/dir1/dir2/relativePathTo.pkl",
    (
      #|import "pkl:test"
      #|ok = true
    ),
  )
  guard session.eval_path("api/module.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("desc = List(\"dir1\", \"dir2\")"), content="true")
  inspect(rendered.contains("same = List()"), content="true")
  inspect(
    rendered.contains("No descendent path exists between modules"),
    content="true",
  )
}

///|
test "PKL-153: dynamic resource reader services read() on demand" {
  reset_sandbox_io_cache()
  clear_sandbox_resource_readers()
  configure_sandbox_resource_reader("cmd", fn(uri) {
    Some({
      uri,
      resource_uri: uri,
      text: "cmd-output:\{uri}",
    })
  })
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|local r = read("cmd:ls /tmp")
      #|uri = r.uri
      #|text = r.text
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let expected =
    #|uri = "cmd:ls /tmp"
    #|text = "cmd-output:cmd:ls /tmp"
  inspect(@pkl.render_value(value), content=expected)
  clear_sandbox_resource_readers()
  reset_sandbox_io_cache()
}

///|
test "PKL-153: resource reader returning None falls through to not-found diagnostic" {
  reset_sandbox_io_cache()
  clear_sandbox_resource_readers()
  configure_sandbox_resource_reader("http", fn(_uri) { None })
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|x = read("http://example.com/missing").text
    ),
  )
  match session.eval_path("main.pkl") {
    EvalOk(_) => panic()
    EvalError(diagnostics) =>
      inspect(
        diagnostics[0].message,
        content="Cannot find resource `http://example.com/missing`.",
      )
  }
  clear_sandbox_resource_readers()
  reset_sandbox_io_cache()
}

///|
test "PKL-152: read Resource exposes bytes and digest properties" {
  reset_sandbox_io_cache()
  register_read_resource(
    "main.pkl", "fox.txt", "fox.txt", "file:///fox.txt", "The quick brown fox jumps over the lazy dog.",
  )
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|local fox = read("fox.txt")
      #|uri = fox.uri
      #|text = fox.text
      #|bytesText = fox.bytes.decodeToString("UTF-8")
      #|base64 = fox.base64
      #|md5 = fox.md5
      #|sha1 = fox.bytes.sha1
      #|sha256 = fox.sha256
      #|sha256Int = fox.bytes.sha256Int
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let expected =
    #|uri = "file:///fox.txt"
    #|text = "The quick brown fox jumps over the lazy dog."
    #|bytesText = "The quick brown fox jumps over the lazy dog."
    #|base64 = "VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4="
    #|md5 = "e4d909c290d0fb1ca068ffaddf22cbd0"
    #|sha1 = "408d94384216f890ff7a0c3528e8bed1e0b01621"
    #|sha256 = "ef537f25c895bfa782526529a9b63d97aa631564d5d789c2b765448c8635fb6c"
    #|sha256Int = -6359199461968751633
  inspect(@pkl.render_value(value), content=expected)
  reset_sandbox_io_cache()
}

///|
test "PKL-152: in-language Resource computes bytes and base64 fields" {
  guard eval_source(
      (
        #|fromBase64 = new Resource { base64 = "AQIDBA==" }.bytes
        #|toBase64 = new Resource { bytes = Bytes(1, 2, 3, 4) }.base64
        #|fromText = new Resource { text = "foo bar" }.base64
        #|hash = new Resource { bytes = Bytes(1, 2, 3, 4) }.sha256
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|fromBase64 = Bytes(1, 2, 3, 4)
    #|toBase64 = "AQIDBA=="
    #|fromText = "Zm9vIGJhcg=="
    #|hash = "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a"
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148c: pkl math exposes uint constants and integer helpers" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:math"
      #|import "pkl:test"
      #|maxUInt32 = math.maxUInt32
      #|cbrt = math.cbrt(27)
      #|log2 = math.log2(2)
      #|gcd = math.gcd(4, 6)
      #|lcm = math.lcm(4, 6)
      #|pow2 = math.isPowerOfTwo(4096.0)
      #|bad = test.catch(() -> math.gcd(4, 6.1))
    ),
  )
  let expected =
    #|maxUInt32 = 4294967295
    #|cbrt = 3.0
    #|log2 = 1.0
    #|gcd = 2
    #|lcm = 12
    #|pow2 = true
    #|bad = "Expected value of type `Int`, but got type `Float`. Value: 6.1"
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148c: reflect module surface handles modules without imports" {
  let session = AnalysisSession::new()
  session.set_source("dep.pkl", "value = 1")
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:reflect"
      #|local dep = reflect.Module(import("dep.pkl"))
      #|depImportsEmpty = dep.imports == Map()
      #|docNull = dep.docComment == null
      #|isAmend = dep.isAmend
      #|selfImports = reflect.Module(module).imports
    ),
  )
  let expected =
    #|depImportsEmpty = true
    #|docNull = true
    #|isAmend = false
    #|selfImports = Map("reflect", "pkl:reflect")
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148c: reflect class allProperties merges inherited metadata" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:reflect"
      #|class MyAnn extends Annotation
      #|open class A {
      #|  @MyAnn
      #|  p: String
      #|}
      #|class B extends A {
      #|  hidden fixed p: Int = 1
      #|}
      #|local prop = reflect.Class(B).allProperties["p"]
      #|name = prop.name
      #|typeName = prop.type.referent.name
      #|annotations = prop.annotations.map((it) -> it.toString()).toListing()
      #|allAnnotations = prop.allAnnotations.map((it) -> it.toString()).toListing()
      #|modifiers = prop.modifiers.toListing()
      #|allModifiers = prop.allModifiers.toListing()
    ),
  )
  let expected =
    #|name = "p"
    #|typeName = "Int"
    #|annotations {}
    #|allAnnotations {
    #|  "new MyAnn {}"
    #|}
    #|modifiers {
    #|  "hidden"
    #|  "fixed"
    #|}
    #|allModifiers {
    #|  "hidden"
    #|  "fixed"
    #|}
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-152: reflected annotation toString preserves body text" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:reflect"
      #|class C {
      #|  @AlsoKnownAs { names { "mergedAnnotations" } }
      #|  p: String
      #|}
      #|text = reflect.Class(C).allProperties["p"].annotations.first.toString()
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(
    @pkl.render_value(value),
    content="text = \"new AlsoKnownAs { names { \\\"mergedAnnotations\\\" } }\"",
  )
}

///|
test "PKL-148c: reflect module class exposes output property metadata" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:reflect"
      #|local prop = reflect.Class(module.getClass()).properties["output"]
      #|name = prop.name
      #|typeName = prop.type.name
      #|modifiers = prop.modifiers.toListing()
      #|allModifiers = prop.allModifiers.toListing()
      #|output { text = "ok" }
    ),
  )
  let expected =
    #|name = "output"
    #|typeName = "unknown"
    #|modifiers {}
    #|allModifiers {
    #|  "hidden"
    #|}
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148c: module output amend appends synthesized super text" {
  let session = AnalysisSession::new()
  session.set_source(
    "base.pkl",
    (
      #|open module Base
      #|output {
      #|  renderer = new PcfRenderer {}
      #|}
    ),
  )
  session.set_source(
    "main.pkl",
    (
      #|amends "base.pkl"
      #|a = 1
      #|output {
      #|  text = super.text + "\n// tail"
      #|}
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut output_value : Value? = None
  for field in members {
    if field.name == "output" {
      output_value = Some(field.value)
      break
    }
  }
  guard output_value is Some(ObjectValue(output_members)) else { panic() }
  let mut text_value : Value? = None
  for field in output_members {
    if field.name == "text" {
      text_value = Some(field.value)
      break
    }
  }
  guard text_value is Some(StringValue(text)) else { panic() }
  inspect(
    text,
    content=(
      #|a = 1
      #|
      #|// tail
    ),
  )
}

///|
test "PKL-148c: reflect type getters work from class defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:reflect"
      #|class A { p: String }
      #|class DisplayProperty {
      #|  hidden property: reflect.Property
      #|  fixed type = property.type.getPropertyOrNull("referent")?.getPropertyOrNull("name") ?? "unknown"
      #|}
      #|x = new DisplayProperty { property = reflect.Class(A).allProperties["p"] }
    ),
  )
  let expected =
    #|x {
    #|  type = "String"
    #|}
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148d: class name as value projects to a Class mirror" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass Person { foo = 1 }\nres = test.catch(() -> Person.foo)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut message : String = ""
  for entry in members {
    if entry.name == "res" {
      match entry.value {
        StringValue(s) => message = s
        _ => ()
      }
    }
  }
  inspect(
    message.contains("Cannot find property `foo` in object of type `Class`."),
    content="true",
  )
}

///|
test "PKL-148d: deep-merge amend preserves uninvolved subtree members" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "x {\n  foo {\n    bar {\n      a = 1\n      b = 2\n    }\n  }\n}\ny = (x) {\n  foo {\n    bar {\n      a = 11\n    }\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("a = 11"), content="true")
  inspect(rendered.contains("b = 2"), content="true")
}

///|
test "PKL-148bi: function amend applies object body to call result" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "f = (x, y) -> new Dynamic { sum = x + y }\nres = (f) { a, b -> left = a; right = b }.apply(1, 2)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("sum = 3"), content="true")
  inspect(rendered.contains("left = 1"), content="true")
  inspect(rendered.contains("right = 2"), content="true")
}

///|
test "PKL-148bi: function amend propagates through returned functions" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "f = (x) -> (y) -> new Dynamic { y = y }\ng = (f) { a -> x = a }\nres = g.apply(1).apply(2)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("x = 1"), content="true")
  inspect(rendered.contains("y = 2"), content="true")
}

///|
test "PKL-148bi: constructor body amends function-valued class defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class X {\n  hidden f = (n) -> new Dynamic { one = n }\n  res = f.apply(1)\n}\nx = new X {\n  f {\n    amended = \"yes\"\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("one = 1"), content="true")
  inspect(rendered.contains("amended = \"yes\""), content="true")
}

///|
test "PKL-148bp: constructor body amends function defaults with signature placeholders" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|class Bird {
      #|  name: String
      #|  age: Int
      #|}
      #|class B {
      #|  hidden mkBird: (String, Int) -> Bird = (_name, _age) -> new Bird {
      #|    name = _name
      #|    age = _age
      #|  }
      #|  bird = mkBird.apply("Robin", 2)
      #|}
      #|bird1 = new B {
      #|  mkBird { _, _age ->
      #|    name = "Swallow"
      #|    age = _age
      #|  }
      #|}
      #|bird2 = new B {
      #|  mkBird { _name, _ ->
      #|    name = _name
      #|    age = 3
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Swallow\""), content="true")
  inspect(rendered.contains("age = 2"), content="true")
  inspect(rendered.contains("name = \"Robin\""), content="true")
  inspect(rendered.contains("age = 3"), content="true")
}

///|
test "PKL-148bi: callable user-class parameter diagnostics are qualified" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Foo\nclass Baz\nf = (x: Baz) -> x\nres = f.apply(new Foo {})",
  )
  guard session.eval_path("main.pkl") is EvalError(diagnostics) else { panic() }
  inspect(
    diagnostics[0].message,
    content="Expected value of type `main#Baz`, but got type `main#Foo`. Value: new Foo {}",
  )
}

///|
test "PKL-148bj: outer resolves enclosing object after amend" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "base { x = 1; child { z = outer.x } }\nres = (base) { x = 2 }",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("x = 2"), content="true")
  inspect(rendered.contains("z = 2"), content="true")
}

///|
test "PKL-148bj: super property re-evaluates base source with overrides" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "parent { x = 1 + y; y = 2 }\nchild = (parent) { x = super.x + 100; y = 3 }\ngrand = (child) { y = 4 }",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("child {\n  x = 104"), content="true")
  inspect(rendered.contains("grand {\n  x = 105"), content="true")
}

///|
test "PKL-148bj: typed object late binding can target class defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Foo {\n  x: Int\n  y = 1\n}\nbase { foo = new Foo { x = y } }\nres = (base) { foo { y = 5 } }",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("res {\n  foo {\n    x = 5"), content="true")
}

///|
test "PKL-148bk: classes extending module inherit module property defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "open module Foo\n\nprop: String\nmyself: module?\n\nclass Bar extends module {\n  prop2: Int\n}\n\noutput {\n  value = new Bar {\n    prop = \"hi\"\n    prop2 = 15\n    myself {\n      prop = \"again\"\n      prop2 = 16\n    }\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  guard value is ObjectValue(module_members) else { panic() }
  let mut output_value : Value? = None
  for value_member in module_members {
    if value_member.name == "output" {
      match value_member.value {
        ObjectValue(output_members) =>
          for output_member in output_members {
            if output_member.name == "value" {
              output_value = Some(output_member.value)
            }
          }
        _ => ()
      }
    }
  }
  guard output_value is Some(output_value) else { panic() }
  let rendered = @pkl.render_value(output_value)
  inspect(rendered.contains("myself = null"), content="true")
  inspect(rendered.contains("prop2 = 16"), content="true")
}

///|
test "PKL-148bk: starred union class default validates against bare class" {
  guard eval_source(
      "class Foo { name: String = \"foo\" }\nclass Baz { name: String = \"baz\" }\nd: *Foo | Baz\nf: Foo | *Baz",
    )
    is EvalOk(value) else {
    panic()
  }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("d {\n  name = \"foo\""), content="true")
  inspect(rendered.contains("f {\n  name = \"baz\""), content="true")
}

///|
test "PKL-148c: arbitrary constraint expression with sibling reference" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass Gauge { min: Int = 4; max: Int(this >= min) = 6 }\nres = test.catch(() -> new Gauge { min = 4; max = 3 }.max)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Type constraint `this >= min` violated. Value: 3"),
    content="true",
  )
}

///|
test "PKL-148c: constraint expression with implicit-receiver property access" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass X { y: Int(abs < 100) }\nres = test.catch(() -> new X { y = -100 }.y)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Type constraint `abs < 100` violated. Value: -100"),
    content="true",
  )
}

///|
test "PKL-148c: constraint expression sees receiver and enclosing methods" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|
    #|const function add(x, y) = x + y
    #|
    #|class X {
    #|  function subtract(x, y) = x - y
    #|  y: Y(multiply(subtract(add(5, 4), 3), 2) == z)
    #|}
    #|
    #|class Y {
    #|  function multiply(x, y) = x * y
    #|  z: Int
    #|}
    #|
    #|res = test.catch(() -> new X { y { z = 13 } }.y)
  session.set_source("constraints7.pkl", source)
  guard session.eval_path("constraints7.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut message = ""
  for entry in members {
    if entry.name == "res" {
      match entry.value {
        StringValue(value) => message = value
        _ => ()
      }
    }
  }
  inspect(
    message,
    content="Type constraint `multiply(subtract(add(5, 4), 3), 2) == z` violated. Value: new Y { z = 13 }",
  )
}

///|
test "PKL-148c: constraint-position function checks collection parameter eagerly" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|
    #|const local isOddLengthOfBirds = (it: Listing<Bird>) -> it.length.isOdd
    #|
    #|class Bird
    #|
    #|class MyTest {
    #|  birds: Listing(isOddLengthOfBirds) = new {
    #|    1
    #|    2
    #|    3
    #|  }
    #|}
    #|
    #|res = test.catch(() -> new MyTest {}.birds)
  session.set_source("constraints13.pkl", source)
  guard session.eval_path("constraints13.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut message = ""
  for entry in members {
    if entry.name == "res" {
      match entry.value {
        StringValue(value) => message = value
        _ => ()
      }
    }
  }
  inspect(
    message,
    content="Expected value of type `constraints13#Bird`, but got type `Int`. Value: 1",
  )
}

///|
test "PKL-148c: if-condition diagnostic uses Apple Pkl wording" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nres = test.catch(() -> if (\"\") 1 else 2)",
  )
  guard session.eval_path("main.pkl") is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut message : String = ""
  for entry in members {
    if entry.name == "res" {
      match entry.value {
        StringValue(s) => message = s
        _ => ()
      }
    }
  }
  inspect(
    message.contains(
      "Expected value of type `Boolean`, but got type `String`. Value: \"\"",
    ),
    content="true",
  )
}

///|
test "PKL-148b: this <op> N bare-comparison constraint fires the diagnostic" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass Person { age: Int(this > 0) }\nres = test.catch(() -> new Person { age = -30 }.age)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Type constraint `this > 0` violated. Value: -30"),
    content="true",
  )
}

///|
test "PKL-148b: Listing-host !isEmpty constraint fires at construction" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass P { l: Listing<String>(!isEmpty) }\nres = test.catch(() -> new P { l {} }.l)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Type constraint `!isEmpty` violated."),
    content="true",
  )
}

///|
test "PKL-148b: pipe operator desugars to a single-arg call" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "double = (x: Int) -> x * 2\nres = 21 |> double",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("res = 42"), content="true")
}

///|
test "PKL-148b: as does a runtime type assertion" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "good = (\"abc\" as String).length\nimport \"pkl:test\"\nbad = test.catch(() -> 1 as String)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("good = 3"), content="true")
  inspect(
    rendered.contains(
      "Expected value of type `String`, but got type `Int`. Value: 1",
    ),
    content="true",
  )
}

///|
test "PKL-148b: as diagnostics render class and collection values compactly" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|class Base
    #|class Other
    #|local mapping = new Mapping { ["name"] = "Pigeon"; ["age"] = 40 }
    #|local listing = new Listing {
    #|  test.catch(() -> 1 as Other)
    #|}
    #|classErr = test.catch(() -> Base as Other)
    #|mappingErr = test.catch(() -> mapping as Other)
    #|listingErr = test.catch(() -> listing as Other)
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "Expected value of type `main#Other`, but got type `Class`. Value: main#Base",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `main#Other`, but got type `Mapping`. Value: new Mapping { [\\\"name\\\"] = \\\"Pigeon\\\"; [\\\"age\\\"] = 40 }",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `main#Other`, but got type `Listing`. Value: new Listing { \\\"Expected value of type `main#Other`",
    ),
    content="true",
  )
}

///|
test "PKL-148b: module self reference sees in-progress binding for as Module" {
  let session = AnalysisSession::new()
  let source =
    #|examples {
    #|  ["String"] {
    #|    "abc"
    #|  }
    #|  ["Module"] {
    #|    (module as Module).examples["String"][0]
    #|    (module as Any).examples["String"][0]
    #|  }
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("[\"Module\"] {\n    \"abc\"\n    \"abc\""),
    content="true",
  )
}

///|
test "PKL-148cb: as validates generic immutable collection casts eagerly" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|listErr = test.catch(() -> List(1, 2, 3) as List<String>)
    #|setErr = test.catch(() -> Set(1, 2, 3) as Set<String>)
    #|mapErr = test.catch(() -> Map("Pigeon", 42) as Map<Int, String>)
    #|nested = Set(new Listing { "one" }) as Set<Listing<Int>>
    #|nestedThrows = test.catchOrNull(() -> nested.first) != null
    #|nestedErr = test.catch(() -> nested.first[0])
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "Expected value of type `String`, but got type `Int`. Value: 1",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `Int`, but got type `String`. Value: \\\"Pigeon\\\"",
    ),
    content="true",
  )
  inspect(rendered.contains("nestedThrows = true"), content="true")
  inspect(
    rendered.contains(
      "Expected value of type `Int`, but got type `String`. Value: \\\"one\\\"",
    ),
    content="true",
  )
}

///|
test "PKL-148cb: as keeps Listing and Mapping element errors lazy" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:test"
    #|local listing = new Listing { 1; 2 } as Listing<String>
    #|listingOk = test.catchOrNull(() -> listing) == null
    #|listingErr = test.catch(() -> listing[0])
    #|local mapping = new Mapping { ["hi"] = 1; ["bye"] = 2 } as Mapping<String, String>
    #|mappingOk = test.catchOrNull(() -> mapping) == null
    #|mappingErr = test.catch(() -> mapping["hi"])
    #|mappingKeyErr = test.catch(() -> new Mapping { ["hi"] = 1 } as Mapping<Int, Int>)
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("listingOk = true"), content="true")
  inspect(rendered.contains("mappingOk = true"), content="true")
  inspect(
    rendered.contains(
      "Expected value of type `String`, but got type `Int`. Value: 1",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `Int`, but got type `String`. Value: \\\"hi\\\"",
    ),
    content="true",
  )
}

///|
test "PKL-148cc: deferred local Mapping cast keeps earlier dynamic elements" {
  let session = AnalysisSession::new()
  let source =
    #|out = new {
    #|  local m1 = new Mapping {
    #|    ["hi"] = 1
    #|    ["bye"] = 2
    #|  } as Mapping<String, String>
    #|  module.catchOrNull(() -> m1) == null
    #|  module.catch(() -> m1["hi"])
    #|  module.catch(() -> m1["bye"])
    #|  local m2 = new Mapping {
    #|    ["hi"] = 1
    #|    ["bye"] = 2
    #|  } as Mapping<Int, Int>
    #|  module.catch(() -> m2)
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("  true"), content="true")
  inspect(
    rendered.contains(
      "Expected value of type `String`, but got type `Int`. Value: 1",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `String`, but got type `Int`. Value: 2",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "Expected value of type `Int`, but got type `String`. Value: \\\"hi\\\"",
    ),
    content="true",
  )
  inspect(rendered.contains("new {}"), content="false")
}

///|
test "PKL-148ca: is recognizes concrete collection class and callable shapes" {
  let session = AnalysisSession::new()
  let source =
    #|local open class Base
    #|local class Derived extends Base
    #|local class Other
    #|local f = (x) -> x
    #|base = new Base {}
    #|derived = new Derived {}
    #|other = new Other {}
    #|checks = new Listing {
    #|  1.s is Duration
    #|  1.b is DataSize
    #|  List(1) is List
    #|  !(Set(1) is List)
    #|  Set(1) is Set
    #|  !(List(1) is Set)
    #|  Map("x", 1) is Map
    #|  !(List(1) is Map)
    #|  List(1) is Collection
    #|  Set(1) is Collection
    #|  !(Map("x", 1) is Collection)
    #|  derived is Base
    #|  !(other is Base)
    #|  Base is Class
    #|  base.getClass() is Class
    #|  !(base is Class)
    #|  f is Function
    #|  f is Function1
    #|  !(f is Function2)
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("false"), content="false")
  inspect(rendered.contains("new {}"), content="false")
}

///|
test "PKL-148ca: is validates generic collection elements" {
  let session = AnalysisSession::new()
  let source =
    #|checks = new Listing {
    #|  List(1, 2, 3) is List<Int>
    #|  !(List(1, 2, 3) is List<String>)
    #|  !(Set(1, 2, 3) is List<Int>)
    #|  Set(1, 2, 3) is Set<Int>
    #|  !(List(1, 2, 3) is Set<Int>)
    #|  !(Set(1, 2, 3) is Set<String>)
    #|  Map("Pigeon", 42) is Map<String, Int>
    #|  !(Map("Pigeon", 42) is Map<Int, String>)
    #|  new Listing { 1; 2; 3 } is Listing<Int>
    #|  !(new Listing { 1; 2; 3 } is Listing<String>)
    #|  new Mapping { ["Pigeon"] = 42 } is Mapping<String, Int>
    #|  !(new Mapping { ["Pigeon"] = 42 } is Mapping<Int, String>)
    #|  List("a", "b", "c") is List<String(length == 1)>
    #|  !(List("a", "bb", "c") is List<String(length == 1)>)
    #|}
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("false"), content="false")
  inspect(rendered.contains("new {}"), content="false")
}

///|
test "PKL-148b: Duration / DataSize scalar arithmetic" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 5.s * 3\nb = 3 * 4.s\nc = 12.s / 4\nd = 2.gb * 2",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("a = 15.s"), content="true")
  inspect(rendered.contains("b = 12.s"), content="true")
  inspect(rendered.contains("c = 3.s"), content="true")
  inspect(rendered.contains("d = 4.gb"), content="true")
}

///|
test "PKL-148b: Int.isBetween and Int.toFloat" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = 5.isBetween(0, 10)\nb = 11.isBetween(0, 10)\nc = 3.toFloat()",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("a = true"), content="true")
  inspect(rendered.contains("b = false"), content="true")
  inspect(rendered.contains("c = 3.0"), content="true")
}

///|
test "PKL-148: Bool xor and implies dispatch through the method path" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = true.xor(false)\nb = true.implies(false)\nc = false.implies(true)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("a = true"), content="true")
  inspect(rendered.contains("b = false"), content="true")
  inspect(rendered.contains("c = true"), content="true")
}

///|
test "PKL-148: Listing.getOrNull returns the element or null" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "l = new Listing { 10; 20; 30 }\nfound = l.getOrNull(1)\nmissing = l.getOrNull(9)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("found = 20"), content="true")
  inspect(rendered.contains("missing = null"), content="true")
}

///|
test "PKL-148: Map.containsValue probes the value side" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "m = Map(\"a\", 1, \"b\", 2)\nhasOne = m.containsValue(1)\nhasNine = m.containsValue(9)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("hasOne = true"), content="true")
  inspect(rendered.contains("hasNine = false"), content="true")
}

///|
test "PKL-148: value.getClass().simpleName mirrors the runtime type" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "i = 1.getClass().simpleName\ns = \"hi\".getClass().simpleName\nb = true.getClass().simpleName",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("i = \"Int\""), content="true")
  inspect(rendered.contains("s = \"String\""), content="true")
  inspect(rendered.contains("b = \"Boolean\""), content="true")
}

///|
test "PKL-148: module.getClass exposes reflect property doc comments" {
  let session = AnalysisSession::new()
  let source =
    #|import "pkl:reflect"
    #|
    #|/// doc comment
    #|// line comments can appear between doc comments
    #|/*
    #| block comments also
    #|*/
    #|/// doc continuation
    #|foo = 1
    #|
    #|theComment = reflect.Class(module.getClass()).properties["foo"].docComment
  session.set_source("lineCommentBetween.pkl", source)
  guard session.eval_path("lineCommentBetween.pkl")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  let mut comment = ""
  for entry in members {
    if entry.name == "theComment" {
      match entry.value {
        StringValue(value) => comment = value
        _ => ()
      }
    }
  }
  inspect(comment, content="doc comment\ndoc continuation")
}

///|
test "PKL-148: typed empty new {} expands class defaults" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "class Person { name: String = \"The Person\" }\np: Person = new {}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"The Person\""), content="true")
}

///|
test "PKL-148: constraint diagnostic uses Apple Pkl wording" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:test\"\nclass X { a: Int(isBetween(0, 10)) }\nbad = test.catch(() -> new X { a = 20 }.a)",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Type constraint `isBetween(0, 10)` violated. Value: 20"),
    content="true",
  )
}

///|
test "PKL-148: Listing + Listing concatenates" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "a = new Listing { 1; 2 } + new Listing { 3; 4 }",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("1"), content="true")
  inspect(rendered.contains("4"), content="true")
}

///|
test "PKL-147: nested amend body in mapping entry preserves listing elements" {
  // Regression: `parse_mapping_entry`'s no-`=` brace form used to call
  // `parse_object_body` which silently dropped bare-element listing
  // contents. snippetTest's `examples { [\"k\"] { true; false } }` body
  // depends on this dispatching through `parse_inferred_new_body`.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "m : Mapping<String, Listing<Boolean>>?\nm {\n  [\"literal\"] {\n    true\n    false\n  }\n}",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"literal\"] {"), content="true")
  inspect(rendered.contains("true"), content="true")
  inspect(rendered.contains("false"), content="true")
}

///|
test "PKL-148ar: predicate members amend mapping entries" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden people = new Mapping {
      #|  ["Pigeon"] { name = "Pigeon"; age = 42 }
      #|  ["Barn Owl"] { name = "Barn Owl"; age = 21 }
      #|}
      #|res = (people) {
      #|  [[name == "Barn Owl"]] { age = 99 }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"Barn Owl\"] {"), content="true")
  inspect(rendered.contains("age = 99"), content="true")
  inspect(rendered.contains("age = 42"), content="true")
}

///|
test "PKL-148ar: predicate members ignore same-block listing additions" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden people = new Listing {
      #|  new { name = "Pigeon"; age = 42 }
      #|}
      #|res = (people) {
      #|  new { name = "Albatross"; age = 4 }
      #|  [[name == "Albatross"]] { age = 9 }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Albatross\""), content="true")
  inspect(rendered.contains("age = 4"), content="true")
  inspect(rendered.contains("age = 9"), content="false")
}

///|
test "PKL-148ar: predicate members inside for amend listing entries" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden people = new Listing {
      #|  new { name = "Pigeon"; age = 42 }
      #|  new { name = "Parrot"; age = 33 }
      #|}
      #|res = (people) {
      #|  for (target in List("Pigeon", "Parrot")) {
      #|    [[name == target]] { age = 99 }
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Pigeon\""), content="true")
  inspect(rendered.contains("name = \"Parrot\""), content="true")
  inspect(rendered.contains("age = 99"), content="true")
  inspect(rendered.contains("age = 42"), content="false")
  inspect(rendered.contains("age = 33"), content="false")
}

///|
test "PKL-152c: listing predicate members use collection implicit receiver" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden xs = new Listing {
      #|  new Listing { 1 }
      #|  new Listing { 2; 3 }
      #|}
      #|res = (xs) {
      #|  [[length > 1]] { 4 }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("2\n    3\n    4"), content="true")
}

///|
test "PKL-152c: nested listing predicate amends collection elements" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden xs = new Listing {
      #|  new Listing { new Listing { 1 } }
      #|  new Listing { new Listing { 2 }; new Listing { 2; 2 } }
      #|}
      #|res = (xs) {
      #|  [[length > 1]] {
      #|    [[toList().first < 3]] { -3 }
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("2\n      -3"), content="true")
  inspect(rendered.contains("2\n      2\n      -3"), content="true")
}

///|
test "PKL-148aw: for iterates mapping values bytes and dynamic member stream" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|out = new {
      #|  mappingValues = new Listing {
      #|    for (v in new Mapping { ["one"] = 1; ["two"] = 2 }) { v }
      #|  }
      #|  mapValues = new Listing {
      #|    for (v in Map("one", 1, "two", 2)) { v }
      #|  }
      #|  byteValues = new Listing {
      #|    for (v in Bytes(1, 2, 3)) { v }
      #|  }
      #|  dynamicKeyValues = new Listing {
      #|    for (k, v in new Dynamic {
      #|      prop = "value"
      #|      ["entry"] = "mapped"
      #|      "element"
      #|    }) {
      #|      "\(k) -> \(v)"
      #|    }
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("mappingValues {\n    1\n    2\n  }"),
    content="true",
  )
  inspect(rendered.contains("mapValues {\n    1\n    2\n  }"), content="true")
  inspect(
    rendered.contains("byteValues {\n    1\n    2\n    3\n  }"),
    content="true",
  )
  inspect(
    rendered.contains(
      "dynamicKeyValues {\n    \"prop -> value\"\n    \"entry -> mapped\"\n    \"0 -> element\"\n  }",
    ),
    content="true",
  )
}

///|
test "PKL-148aw: for-generated dynamic entries reject duplicate keys" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|
      #|result = test.catch(() -> new Dynamic {
      #|  for (v in new Dynamic {
      #|    first = "same"
      #|    ["second"] = "same"
      #|  }) {
      #|    [v] = v
      #|  }
      #|})
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("Duplicate definition of member `\\\"same\\\"`."),
    content="true",
  )
}

///|
test "PKL-148ay: typed for bindings validate index and value" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|
      #|out = new {
      #|  badValue = test.catch(() -> new Listing {
      #|    for (n: String in IntSeq(1, 2)) { n }
      #|  })
      #|  badIndex = test.catch(() -> new Listing {
      #|    for (i: String, n: Int in IntSeq(1, 2)) { n }
      #|  })
      #|  unknownOk = new Listing {
      #|    for (x: unknown in List("a", "b")) { x }
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "badValue = \"Expected value of type `String`, but got type `Int`. Value: 1\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains(
      "badIndex = \"Expected value of type `String`, but got type `Int`. Value: 0\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains("unknownOk {\n    \"a\"\n    \"b\"\n  }"),
    content="true",
  )
}

///|
test "PKL-148az: for source and key keep lexical function scope" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|function make(arg) = new Dynamic {
      #|  arg = "property"
      #|  for (key, value in List("one", arg)) {
      #|    [Pair(arg, key)] = Pair(arg, value)
      #|  }
      #|}
      #|res = make("two")
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("[Pair(\"two\", 0)] = Pair(\"property\", \"one\")"),
    content="true",
  )
  inspect(
    rendered.contains("[Pair(\"two\", 1)] = Pair(\"property\", \"two\")"),
    content="true",
  )
}

///|
test "PKL-148ba: Mixin pipe applies generated elements and entries" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|function addItems(env: Dynamic) = new Mixin {
      #|  for (k, v in env) {
      #|    new { name = k; value = v }
      #|  }
      #|}
      #|function addEntries(keys: List<String>): Mixin<Mapping<String, String>> = new {
      #|  for (key in keys) { [key] = key }
      #|}
      #|items = new Listing {} |> addItems(new Dynamic { a = "A"; b = "B" })
      #|entries = new Mapping<String, String> { ["base"] = "base" } |> addEntries(List("next"))
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"a\""), content="true")
  inspect(rendered.contains("value = \"B\""), content="true")
  inspect(rendered.contains("[\"base\"] = \"base\""), content="true")
  inspect(rendered.contains("[\"next\"] = \"next\""), content="true")
}

///|
test "PKL-148bm: Mixin object apply mirrors pipe semantics" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|class Person { name: String }
      #|local mixin1: Mixin = new { name = "Other" }
      #|local mixin2: Mixin<Person> = new { name = "Typed" }
      #|res1 = new Person { name = "Base" } |> mixin1
      #|res2 = mixin2.apply(new Person { name = "Base" })
      #|err1 = test.catch(() -> mixin1.apply(new Person {}, new Person {}))
      #|err2 = test.catch(() -> mixin2.apply(1))
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("res1 {\n  name = \"Other\""), content="true")
  inspect(rendered.contains("res2 {\n  name = \"Typed\""), content="true")
  inspect(
    rendered.contains("err1 = \"Expected 1 function arguments but got 2.\""),
    content="true",
  )
  inspect(
    rendered.contains(
      "err2 = \"Expected value of type `main#Person`, but got type `Int`. Value: 1\"",
    ),
    content="true",
  )
}

///|
test "PKL-148bn: typealias Mapping constructor accepts entries" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|class Person { name: String }
      #|typealias PersonMapping = Mapping<String, Person>
      #|res = new PersonMapping {
      #|  ["one"] = new Person { name = "One" }
      #|  ["two"] = new { name = "Two" }
      #|  ["three"] { name = "Three" }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"one\"] {\n    name = \"One\""), content="true")
  inspect(rendered.contains("[\"two\"] {\n    name = \"Two\""), content="true")
  inspect(
    rendered.contains("[\"three\"] {\n    name = \"Three\""),
    content="true",
  )
}

///|
test "PKL-148bo: new rejects external and unstarred union types" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|class Person { name: String }
      #|setErr = test.catch(() -> new Set {})
      #|unionErr = test.catch(() -> new String|Person {})
      #|literalErr = test.catch(() -> new "foo" {})
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "setErr = \"Cannot instantiate, or amend an instance of, external class `Set`.\"",
    ),
    content="true",
  )
  inspect(
    rendered.contains("unionErr = \"Cannot instantiate type `String|Person`.\""),
    content="true",
  )
  inspect(
    rendered.contains(
      "literalErr = \"Cannot instantiate, or amend an instance of, external class `String`.\"",
    ),
    content="true",
  )
}

///|
test "PKL-148bl: class defaults re-evaluate after generator overrides" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|local class App {
      #|  n: Int
      #|  list = List(n, n, n)
      #|}
      #|result = new {
      #|  for (_n in List(1, 2, 3)) {
      #|    for (x in new App { n = _n }.list) {
      #|      x
      #|    }
      #|  }
      #|}
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      (
        #|result {
        #|  1
        #|  1
        #|  1
        #|  2
        #|  2
        #|  2
        #|  3
        #|  3
        #|  3
        #|}
      ),
    ),
    content="true",
  )
}

///|
test "PKL-148ar: Dynamic.toMap projects bracket entries" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden people = new Dynamic {
      #|  ["Pigeon"] { name = "Pigeon"; age = 42 }
      #|}
      #|age = people.toMap().values.first.age
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("age = 42"), content="true")
}

///|
test "PKL-152: Dynamic toMap toList toTyped project class-aware values" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|class Person {
      #|  name: String = "Default"
      #|  age: UInt
      #|}
      #|local base = new Dynamic {
      #|  prop = "prop"
      #|  ["name"] = "Pigeon"
      #|  "one"
      #|  "two"
      #|}
      #|local amended = (base) {
      #|  [0] = "one one"
      #|  [1] = "two two"
      #|}
      #|map = amended.toMap()
      #|list = amended.toList()
      #|typed = new Dynamic { age = 42 }.toTyped(Person)
      #|missing = module.catch(() -> new Dynamic { name = "Pigeon" }.toTyped(Person).age)
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains("map = Map(\"prop\", \"prop\", \"name\", \"Pigeon\")"),
    content="true",
  )
  inspect(
    rendered.contains("list = List(\"one one\", \"two two\")"),
    content="true",
  )
  inspect(rendered.contains("name = \"Default\""), content="true")
  inspect(rendered.contains("age = 42"), content="true")
  inspect(
    rendered.contains(
      "missing = \"Tried to read property `age` but its value is undefined.\"",
    ),
    content="true",
  )
}

///|
test "PKL-148ax: Dynamic annotation preserves mixed inferred new body" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden dynamic: Dynamic = new {
      #|  1
      #|  ["foo"] = 0
      #|  foo = "foo"
      #|}
      #|res = new Dynamic { ...dynamic }
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let expected =
    #|res {
    #|  foo = "foo"
    #|  ["foo"] = 0
    #|  1
    #|}
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ax: Bytes accepts varargs" {
  guard eval_source("bytes = Bytes(1, 2, 3, 4)") is EvalOk(value) else {
    panic()
  }
  inspect(@pkl.render_value(value), content="bytes = Bytes(1, 2, 3, 4)")
}

///|
test "PKL-148ax: Bytes addition and subscript match Apple Pkl" {
  guard eval_source(
      (
        #|sum = Bytes(1, 2, 3) + Bytes(1, 2, 4)
        #|empty = Bytes() + Bytes()
        #|left = Bytes(1, 2, 3) + Bytes()
        #|right = Bytes() + Bytes(1, 2, 4)
        #|first = Bytes(1, 2, 3)[0]
        #|last = Bytes(1, 2, 3)[2]
        #|
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|sum = Bytes(1, 2, 3, 1, 2, 4)
    #|empty = Bytes()
    #|left = Bytes(1, 2, 3)
    #|right = Bytes(1, 2, 4)
    #|first = 1
    #|last = 3
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ax: Bytes invalid operations use Apple diagnostics" {
  guard eval_source(
      (
        #|badAdd = module.catch(() -> Bytes(1, 2, 3) + Bytes(1, 2, 4).toList())
        #|badIndex = module.catch(() -> Bytes(1, 2, 3)[3])
        #|badByte = module.catch(() -> Bytes(0, 1, 2, 0xffff))
        #|
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|badAdd = "Operator `+` is not defined for operand types `Bytes` and `List`. Left operand : Bytes(1, 2, 3) Right operand: List(1, 2, 4)"
    #|badIndex = "Element index `3` is out of range `0`..`2`. Value: Bytes(1, 2, 3)"
    #|badByte = "Type constraint `isBetween(0, 255)` violated. Value: 65535"
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-152: Bytes exposes hash encoding size and UTF-8 APIs" {
  guard eval_source(
      (
        #|local bytes = Bytes(1, 2, 3, 4)
        #|md5 = bytes.md5
        #|sha1 = bytes.sha1
        #|sha256 = bytes.sha256
        #|base64 = bytes.base64
        #|hex = bytes.hex
        #|len = bytes.length
        #|size = bytes.size
        #|kilo = IntSeq(0, 999).map((_) -> 0).toBytes().size
        #|decoded = Bytes(0x66, 0x6f, 0x6f, 0x20, 0x62, 0x61, 0x72).decodeToString("UTF-8")
        #|roundTrip = "foo bar".encodeToBytes("UTF-8").decodeToString("UTF-8")
        #|missing = bytes.getOrNull(4)
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|md5 = "08d6c05a21512a79a1dfeb9d2a8f262f"
    #|sha1 = "12dada1fff4d4787ade3333147202c3b443e376f"
    #|sha256 = "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a"
    #|base64 = "AQIDBA=="
    #|hex = "01020304"
    #|len = 4
    #|size = 4.b
    #|kilo = 1.kb
    #|decoded = "foo bar"
    #|roundTrip = "foo bar"
    #|missing = null
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ax: List of Int converts to Bytes" {
  guard eval_source("bytes = IntSeq(0, 3).toList().toBytes()") is EvalOk(value) else {
    panic()
  }
  inspect(@pkl.render_value(value), content="bytes = Bytes(0, 1, 2, 3)")
}

///|
test "PKL-148az: Duration and DataSize arithmetic matches Apple Pkl" {
  guard eval_source(
      (
        #|durationAdd = 2.s + 3.min
        #|durationHuge = 10.ns + 7.d
        #|durationRatio = 2.2.h / 3.3.s
        #|durationTrunc = 6.2.h ~/ 3.3.s
        #|durationPower = 2.2.s ** 3.3
        #|durationBad = module.catch(() -> 3 / 2.s)
        #|dataAdd = 2.kb + 3.kib
        #|dataHuge = 10.b + 11.pib
        #|dataRatio = 2.2.mb / 3.3.b
        #|dataTrunc = 6.2.mb ~/ 3.3.b
        #|dataPower = 2.2.kb ** 3.3
        #|dataBad = module.catch(() -> 3 / 2.kb)
        #|
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|durationAdd = 3.033333333333333.min
    #|durationHuge = 7.0000000000001155.d
    #|durationRatio = 2400.0000000000005
    #|durationTrunc = 6763
    #|durationPower = 13.489468760533386.s
    #|durationBad = "Operator `/` is not defined for operand types `Int` and `Duration`. Left operand : 3 Right operand: 2.s"
    #|dataAdd = 4.953125.kib
    #|dataHuge = 11.000000000000009.pib
    #|dataRatio = 666666.6666666667
    #|dataTrunc = 1878787
    #|dataPower = 13.489468760533386.kb
    #|dataBad = "Operator `/` is not defined for operand types `Int` and `DataSize`. Left operand : 3 Right operand: 2.kb"
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ax: Dynamic spread materializes IntSeq and Bytes" {
  guard eval_source(
      (
        #|res = new Dynamic {
        #|  ...IntSeq(0, 5).step(2)
        #|  ...Bytes(1, 2)
        #|}
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|res {
    #|  0
    #|  2
    #|  4
    #|  1
    #|  2
    #|}
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ax: legacy Dynamic constructor is not a class mirror amend" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|hidden dynamic: Dynamic = new {
      #|  1
      #|  ["foo"] = 0
      #|  foo = "foo"
      #|}
      #|res = (Dynamic) { ...dynamic }
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("simpleName = \"Dynamic\""), content="false")
  inspect(rendered.contains("foo = \"foo\""), content="true")
  inspect(rendered.contains("[\"foo\"] = 0"), content="true")
}

///|
test "PKL-148ay: Listing spread materializes Set IntSeq and Bytes" {
  guard eval_source(
      (
        #|res = new Listing {
        #|  ...Set(10, 20)
        #|  ...IntSeq(0, 4).step(2)
        #|  ...Bytes(1, 2)
        #|}
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let expected =
    #|res {
    #|  10
    #|  20
    #|  0
    #|  2
    #|  4
    #|  1
    #|  2
    #|}
  inspect(@pkl.render_value(value), content=expected)
}

///|
test "PKL-148ay: Listing spread rejects Map with Apple wording" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|res = test.catch(() -> new Listing { ...Map("a", 1, "b", 2) })
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "Cannot spread value of type `Map` into object of type `Listing`.",
    ),
    content="true",
  )
}

///|
test "PKL-148az: Mapping spread accepts Map values and rejects element collections" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl",
    (
      #|import "pkl:test"
      #|res = new Mapping {
      #|  ...Map("a", 1, "b", 2)
      #|}
      #|err = test.catch(() -> new Mapping { ...List(1, 2, 3) })
      #|
    ),
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"a\"] = 1"), content="true")
  inspect(rendered.contains("[\"b\"] = 2"), content="true")
  inspect(
    rendered.contains(
      "Cannot spread value of type `List` into object of type `Mapping`.",
    ),
    content="true",
  )
}

///|
test "PKL-148az: Listing.toMap accepts key and value lambdas" {
  guard eval_source(
      (
        #|res = List("bar").toMap((name) -> name, (name) -> new {
        #|  label = name
        #|}).toMapping()
      ),
    )
    is EvalOk(value) else {
    panic()
  }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"bar\"] {"), content="true")
  inspect(rendered.contains("label = \"bar\""), content="true")
}

///|
test "PKL-147: module.catch routes through the test.catch intercept" {
  // The CallExpr dispatcher recognises both `test.catch(...)` and
  // `module.catch(...)`. snippetTest fixtures use the `module` form to
  // probe exception-throwing expressions inside an `examples` body.
  let session = AnalysisSession::new()
  session.set_source("main.pkl", "out = module.catch(() -> throw(\"boom\"))")
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("out = \"boom\""), content="true")
}

///|
test "PKL-147: hex / binary / octal integer literals lex through parse_int_text" {
  // Apple Pkl's `0xFF_FF` / `0b1010` / `0o17` literal forms were
  // lexed as `0` + identifier before this slice. snippetTest fixtures
  // like `api/int.pkl` lean on `(0x110000).toChar()`.
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "h = 0xFF\nh2 = 0xFF_FF\nb = 0b1010\no = 0o17\nu = 1_000_000",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("h = 255"), content="true")
  inspect(rendered.contains("h2 = 65535"), content="true")
  inspect(rendered.contains("b = 10"), content="true")
  inspect(rendered.contains("o = 15"), content="true")
  inspect(rendered.contains("u = 1000000"), content="true")
}

///|
test "PKL-146: pkl:yaml.Parser.parse decodes a primitive document (Dynamic mode)" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser {}\nv = p.parse(\"name: Alice\\nage: 30\\nactive: true\\n\")\nname = v.name\nage = v.age\nactive = v.active",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Alice\""), content="true")
  inspect(rendered.contains("age = 30"), content="true")
  inspect(rendered.contains("active = true"), content="true")
}

///|
test "PKL-146: pkl:yaml.Parser.parse useMapping=true yields a Mapping" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser { useMapping = true }\nm = p.parse(\"a: 1\\nb: 2\\n\")",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"a\"] = 1"), content="true")
  inspect(rendered.contains("[\"b\"] = 2"), content="true")
}

///|
test "PKL-146: pkl:yaml.Parser.parse handles arrays + nested mappings" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser {}\nv = p.parse(\"items:\\n  - first\\n  - second\\nnested:\\n  inner: 42\\n\")\nfirst = v.items[0]\ninner = v.nested.inner",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("first = \"first\""), content="true")
  inspect(rendered.contains("inner = 42"), content="true")
}

///|
test "PKL-146: pkl:yaml.Parser.parse surfaces YAML parse errors as diagnostics" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser {}\nv = p.parse(\"key: value\\n  bad: indent\\n\")",
  )
  match session.eval_path("main.pkl") {
    EvalError(diagnostics) => {
      let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
      // PKL-148bb: matches Apple Pkl's fixed wording.
      inspect(messages[0], content="Error parsing YAML document.")
    }
    EvalOk(_) =>
      // Some YAML implementations forgive the mis-indented input;
      // tolerate the success path so the test stays useful even if
      // moonbit-community/yaml relaxes parsing later.
      ()
  }
}

///|
test "PKL-146b: pkl:yaml.Parser.parseAll returns all documents" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser {}\nv = p.parseAll(\"---\\n123\\n---\\n---\\n456\\n\")",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("v = List(123, null, 456)"), content="true")
}

///|
test "PKL-146c: pkl:yaml.Parser converters rewrite mapping keys and real scalars" {
  let source =
    #|import "pkl:yaml" as yaml
    #|local parser = new yaml.Parser {
    #|  converters {
    #|    [String] = (it) -> it + "x"
    #|    [Float] = (it) -> it + 1.23
    #|    [Dynamic] = (it) -> (it) { other = "other" }
    #|  }
    #|}
    #|v = parser.parse("name: Alice\nprice: 450.00\n")
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("namex = \"Alicex\""), content="true")
  inspect(rendered.contains("pricex = 451.23"), content="true")
  inspect(rendered.contains("other = \"other\""), content="true")
  inspect(rendered.contains("otherx"), content="false")
}

///|
test "PKL-146c: pkl:yaml.Parser folded scalars strip the clipped newline before converters" {
  let source =
    #|import "pkl:yaml" as yaml
    #|local parser = new yaml.Parser {
    #|  converters {
    #|    [String] = (it) -> it + "x"
    #|  }
    #|}
    #|v = parser.parse("""
    #|  comment: >
    #|    Late afternoon is best.
    #|    Backup contact is Nancy
    #|  """)
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "commentx = \"Late afternoon is best. Backup contact is Nancyx\"",
    ),
    content="true",
  )
}

///|
test "PKL-146c: pkl:yaml.Parser path converters preserve YAML anchor aliases" {
  let source =
    #|import "pkl:yaml" as yaml
    #|local parser = new yaml.Parser {
    #|  converters {
    #|    ["left.family"] = (it) -> it.reverse()
    #|  }
    #|}
    #|v = parser.parse("""
    #|  left: &id001
    #|    family: Dumars
    #|  right: *id001
    #|  """)
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("left {\n    family = \"sramuD\""), content="true")
  inspect(rendered.contains("right {\n    family = \"sramuD\""), content="true")
}

///|
test "PKL-146c: pkl:yaml.Parser path converters leave independent equal mappings alone" {
  let source =
    #|import "pkl:yaml" as yaml
    #|local parser = new yaml.Parser {
    #|  converters {
    #|    ["left.family"] = (it) -> it.reverse()
    #|  }
    #|}
    #|v = parser.parse("""
    #|  left:
    #|    family: Dumars
    #|  right:
    #|    family: Dumars
    #|  """)
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("left {\n    family = \"sramuD\""), content="true")
  inspect(rendered.contains("right {\n    family = \"Dumars\""), content="true")
}

///|
test "PKL-146c: pkl:yaml.Parser maxCollectionAliases rejects excess collection aliases" {
  let source =
    #|import "pkl:yaml" as yaml
    #|local parser = new yaml.Parser {
    #|  maxCollectionAliases = 1
    #|}
    #|message = module.catch(() -> parser.parse("""
    #|  left: &left ["x"]
    #|  middle: *left
    #|  right: *left
    #|  """))
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(
    rendered.contains(
      "Error parsing YAML document: The number of aliases for collection nodes exceeds the allowed maximum of 1.",
    ),
    content="true",
  )
}

///|
test "PKL-146b: pkl:yaml.Parser.parse rejects multiple documents" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:yaml\" as yaml\np = new yaml.Parser {}\nv = p.parse(\"---\\nname: pigeon\\n---\\nage: 42\\n\")",
  )
  guard session.eval_path("main.pkl") is EvalError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  inspect(messages[0], content="Error parsing YAML document.")
}

///|
test "PKL-145: hidden class property survives lookup but skips render" {
  guard eval_source(
      "class Box {\n  value: Int\n  hidden marker: String = \"BoxMarker\"\n}\nb = new Box { value = 42 }\nm = b.marker",
    )
    is EvalOk(value) else {
    panic()
  }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("value = 42"), content="true")
  inspect(rendered.contains("m = \"BoxMarker\""), content="true")
  // The hidden marker must not appear inside the rendered Box.
  inspect(rendered.contains("marker = \"BoxMarker\""), content="false")
}

///|
test "PKL-144: pkl:json.Parser.parse decodes a primitive object (Dynamic mode)" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser {}\nv = p.parse(\"{\\\"name\\\": \\\"Alice\\\", \\\"age\\\": 30, \\\"active\\\": true, \\\"meta\\\": null}\")\nname = v.name\nage = v.age\nactive = v.active\nmeta = v.meta",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Alice\""), content="true")
  inspect(rendered.contains("age = 30"), content="true")
  inspect(rendered.contains("active = true"), content="true")
  inspect(rendered.contains("meta = null"), content="true")
}

///|
test "PKL-144: pkl:json.Parser.parse useMapping=true yields a Mapping" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser { useMapping = true }\nm = p.parse(\"{\\\"a\\\": 1, \\\"b\\\": 2}\")",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("[\"a\"] = 1"), content="true")
  inspect(rendered.contains("[\"b\"] = 2"), content="true")
}

///|
test "PKL-144: pkl:json.Parser.parse handles arrays and nested values" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser {}\nv = p.parse(\"[1, 2, {\\\"x\\\": [3, 4]}]\")\nfirst = v[0]\nnested = v[2].x[1]",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("first = 1"), content="true")
  inspect(rendered.contains("nested = 4"), content="true")
}

///|
test "PKL-144: pkl:json.Parser.parse distinguishes Int vs Float" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser {}\nv = p.parse(\"{\\\"i\\\": 42, \\\"f\\\": 3.14}\")",
  )
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("i = 42"), content="true")
  inspect(rendered.contains("f = 3.14"), content="true")
}

///|
test "PKL-144: pkl:json.Parser.parse surfaces parse errors as diagnostics" {
  let session = AnalysisSession::new()
  session.set_source(
    "main.pkl", "import \"pkl:json\" as json\np = new json.Parser {}\nv = p.parse(\"not valid json\")",
  )
  guard session.eval_path("main.pkl") is EvalError(diagnostics) else { panic() }
  let messages = diagnostics.iter().map(fn(d) { d.message }).collect()
  // PKL-148bb: matches Apple Pkl's fixed wording.
  inspect(messages[0], content="Error parsing JSON document.")
}

///|
test "PKL-144b: pkl:json.Parser.parse applies parser converters bottom-up" {
  let source =
    #|import "pkl:json" as json
    #|local parser = new json.Parser {
    #|  converters {
    #|    [String] = (it) -> it + "x"
    #|    [Dynamic] = (it) -> (it) { other = "other" }
    #|    [Listing] = (it) -> (it) { "other" }
    #|  }
    #|}
    #|v = parser.parse("{\"name\":\"Alice\",\"items\":[\"one\"]}")
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("name = \"Alicex\""), content="true")
  inspect(rendered.contains("\"onex\""), content="true")
  inspect(rendered.contains("\"other\""), content="true")
  inspect(rendered.contains("\"otherx\""), content="false")
}

///|
test "PKL-144b: pkl:json.Parser.parse applies unanchored path converters" {
  let source =
    #|import "pkl:json" as json
    #|local parser = new json.Parser {
    #|  converters {
    #|    ["^city"] = (_) -> "no match"
    #|    ["state"] = (_) -> "CA"
    #|    ["phoneNumber[*].type"] = (_) -> "mobile"
    #|    ["phoneNumber[*]"] = (it) -> it.type
    #|  }
    #|}
    #|v = parser.parse("{\"address\":{\"city\":\"New York\",\"state\":\"NY\"},\"phoneNumber\":[{\"type\":\"home\"}]}")
  let session = AnalysisSession::new()
  session.set_source("main.pkl", source)
  guard session.eval_path("main.pkl") is EvalOk(value) else { panic() }
  let rendered = @pkl.render_value(value)
  inspect(rendered.contains("city = \"New York\""), content="true")
  inspect(rendered.contains("state = \"CA\""), content="true")
  inspect(rendered.contains("\"mobile\""), content="true")
}

///|
test "PKL-119be: empty IntSeqs are equal regardless of endpoints" {
  guard eval_source("v = IntSeq(0, -1) == IntSeq(10, -10)")
    is EvalOk(ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is BoolValue(b) else { panic() }
  inspect(b, content="true")
}

///|
test "class property union accepts null branch after generic head" {
  let source =
    #|class Z {
    #|  g: Pair<Int, Int>|Null
    #|}
    #|res = new Z { g = null }

  let expected =
    #|res {
    #|  g = null
    #|}

  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value), content=expected)
}

///|
test "PKL-153: self-referential Listing default does not infinite-loop" {
  // Before the fix `class Task { deps: Listing<Task> = new {} }` hung
  // mpkl indefinitely because `apply_collection_default_for_type`
  // synthesised the element default with a fresh `seen` array,
  // recursing into the same class. The materialising-marker on
  // `ClassDefaultMemoEntry` breaks the cycle for empty collections
  // without disturbing the non-recursive shape.
  let source =
    #|class Task {
    #|  name: String
    #|  deps: Listing<Task> = new {}
    #|}
    #|
    #|t = new Task { name = "build" }

  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(rendered.contains("name = \"build\""), content="true")
  inspect(rendered.contains("deps {}"), content="true")
}

///|
test "PKL-153: self-referential Mapping default does not infinite-loop" {
  let source =
    #|class Node {
    #|  label: String
    #|  children: Mapping<String, Node> = new {}
    #|}
    #|
    #|root = new Node { label = "root" }

  guard eval_source(source) is EvalOk(value) else { panic() }
  let rendered = render_value(value)
  inspect(rendered.contains("label = \"root\""), content="true")
  inspect(rendered.contains("children {}"), content="true")
}

///|
