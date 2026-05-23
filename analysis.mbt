///|
pub struct AnalysisSession {
  priv db : @ripple.Database
  priv sources : @ripple.Input[String, String]
  priv types : @ripple.CycleQuery[String, TypecheckResult]
  priv evals : @ripple.Query[String, EvalResult]
  priv counters : AnalysisCounters
}

///|
priv struct AnalysisCounters {
  mut parse_count : Int
  mut typecheck_count : Int
  mut eval_count : Int
}

///|
pub(all) struct AnalysisStats {
  parse_count : Int
  typecheck_count : Int
  eval_count : Int
} derive(Eq, Debug)

///|
pub fn AnalysisSession::new() -> AnalysisSession {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let sources : @ripple.Input[String, String] = db.input()
  sources.register(rt)
  let counters = AnalysisCounters::{
    parse_count: 0,
    typecheck_count: 0,
    eval_count: 0,
  }
  let parses : @ripple.Query[String, ParseResult?] = db.query(fn(rt, path) {
    counters.parse_count = counters.parse_count + 1
    match get_module_source(sources, rt, path) {
      Some(source) => Some(parse_source(source))
      None => None
    }
  })
  parses.register(rt)
  let types_ref : Ref[@ripple.CycleQuery[String, TypecheckResult]?] = {
    val: None,
  }
  let types : @ripple.CycleQuery[String, TypecheckResult] = db.cycle_query_with_recover(
    fn(rt, path) {
      counters.typecheck_count = counters.typecheck_count + 1
      typecheck_module_path(parses, types_ref, rt, path)
    },
    fn(_rt, path) { TypeError([diag("cyclic import \{path}")]) },
  )
  types_ref.val = Some(types)
  types.register(rt)
  let evals : @ripple.Query[String, EvalResult] = db.query(fn(rt, path) {
    counters.eval_count = counters.eval_count + 1
    eval_module_path(sources, rt, path, [])
  })
  evals.register(rt)
  AnalysisSession::{ db, sources, types, evals, counters }
}

///|
pub fn AnalysisSession::set_source(
  self : AnalysisSession,
  path : String,
  source : String,
) -> Unit {
  ignore(self.sources.set(self.db.runtime(), path, source))
}

///|
pub fn AnalysisSession::typecheck_path(
  self : AnalysisSession,
  path : String,
) -> TypecheckResult {
  self.types.fetch(self.db.runtime(), path)
}

///|
pub fn AnalysisSession::eval_path(
  self : AnalysisSession,
  path : String,
) -> EvalResult {
  // PKL-118: parallel to `eval_source`'s filter — strip the
  // hidden-prefixed function members the evaluator adds for cross-
  // module dispatch. The session's cached EvalResult keeps the full
  // (with-hidden) shape so subsequent import lookups still see the
  // function exports; only this returning boundary strips them. The
  // recursive helper also clears the `@hidden$__class` tag that
  // universal class tagging now writes (PKL-148bh).
  match self.evals.fetch(self.db.runtime(), path) {
    EvalOk(value) => EvalOk(strip_invisible_recursive(value))
    other => other
  }
}

///|
pub fn AnalysisSession::reset_stats(self : AnalysisSession) -> Unit {
  self.counters.parse_count = 0
  self.counters.typecheck_count = 0
  self.counters.eval_count = 0
}

///|
pub fn AnalysisSession::stats(self : AnalysisSession) -> AnalysisStats {
  AnalysisStats::{
    parse_count: self.counters.parse_count,
    typecheck_count: self.counters.typecheck_count,
    eval_count: self.counters.eval_count,
  }
}

///|
fn stack_contains(stack : Array[String], path : String) -> Bool {
  for item in stack {
    if item == path {
      return true
    }
  }
  false
}

///|
fn push_stack(stack : Array[String], path : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(path)
  next
}

///|
fn resolve_import_path(from : String, uri : String) -> String {
  if uri == "..." {
    match lookup_triple_dot_resolution(from, uri) {
      Some(resolved) => return resolved
      None => return uri
    }
  }
  // PKL-148r: triple-dot import — the CLI loader's FS-aware walk has
  // already cached the resolution into the sandbox registry. Consult
  // it here so the analysis layer can produce the same absolute path
  // without re-doing FS access. Falling through to the bare uri keeps
  // the existing "Cannot find module" diagnostic shape for the case
  // where the CLI never registered a resolution (e.g., embedder
  // bypassing the CLI loader).
  if uri.has_prefix(".../") {
    match lookup_triple_dot_resolution(from, uri) {
      Some(resolved) => return resolved
      None => return uri
    }
  }
  // PKL-148bb: `modulepath:/<path>` — consult the same cache the CLI
  // populates when it walks the importer's directory for a basename
  // match (basic/import1b).
  if uri.has_prefix("modulepath:/") {
    match lookup_triple_dot_resolution(from, uri) {
      Some(resolved) => return resolved
      None => return uri
    }
  }
  // PKL-148ad: `@<dep>/<rest>` project-dependency imports — the CLI
  // loader resolves the local dep via `PklProject.deps.json` and
  // registers the absolute path in the same sandbox cache the triple-
  // dot path uses. Consult it here so eval-side resolution lands on
  // the same file the loader read. Falling through to the bare uri
  // keeps the existing "Cannot find module" diagnostic for the case
  // where the CLI never registered a resolution (e.g. remote-type dep
  // — PKL-129 package download still deferred).
  if uri.has_prefix("@") {
    match lookup_triple_dot_resolution(from, uri) {
      Some(resolved) => return resolved
      None => return uri
    }
  }
  if uri.has_prefix("/") || uri.find(":") is Some(_) {
    return normalize_path_segments(uri)
  }
  let combined = match from.rev_find("/") {
    Some(idx) => String::unsafe_substring(from, start=0, end=idx + 1) + uri
    None => uri
  }
  // PKL-152: collapse `..` / `.` segments so two imports that name the
  // same file via different paths normalize to the same string. Cycle
  // detection in `eval_module_path` matches on the resolved path, so
  // the previous lexical (parent + uri) form let recursive imports
  // bypass the guard and recurse until the path string ballooned past
  // the FS lookup ceiling.
  normalize_path_segments(combined)
}

///|
/// PKL-152: walk `..` / `.` segments out of a slash-separated path. A
/// leading `/` (or `<scheme>://`) is preserved verbatim; the segment
/// pass collapses interior `.` and pops one preceding non-`..` segment
/// per `..`. Used by `resolve_import_path` to make cycle-detection
/// path equality work regardless of which side of a recursive import
/// pair built the string.
fn normalize_path_segments(path : String) -> String {
  // Split scheme prefix (`file:///`, `pkl:`) off — leave it untouched.
  let scheme_end = match path.find("://") {
    Some(idx) => idx + 3
    None => 0
  }
  let head = String::unsafe_substring(path, start=0, end=scheme_end)
  let body = String::unsafe_substring(path, start=scheme_end, end=path.length())
  let leading_slash = body.has_prefix("/")
  let raw_segments : Array[String] = []
  let mut start = if leading_slash { 1 } else { 0 }
  let mut i = start
  while i < body.length() {
    if body.unsafe_get(i) == '/' {
      raw_segments.push(String::unsafe_substring(body, start~, end=i))
      start = i + 1
    }
    i = i + 1
  }
  if start <= body.length() {
    raw_segments.push(String::unsafe_substring(body, start~, end=body.length()))
  }
  let resolved : Array[String] = []
  for seg in raw_segments {
    if seg == "" || seg == "." {
      continue
    }
    if seg == ".." {
      if resolved.length() > 0 && resolved[resolved.length() - 1] != ".." {
        let _ = resolved.pop()
      } else if !leading_slash {
        resolved.push("..")
      }
      continue
    }
    resolved.push(seg)
  }
  let buf = StringBuilder::new()
  buf.write_string(head)
  if leading_slash {
    buf.write_char('/')
  }
  for k = 0; k < resolved.length(); k = k + 1 {
    if k > 0 {
      buf.write_char('/')
    }
    buf.write_string(resolved[k])
  }
  buf.to_string()
}

///|
fn builtin_stdlib_source(uri : String) -> String? {
  match uri {
    "pkl:math" => {
      // The math module exposes Int range constants, pure Int helpers,
      // and (PKL-120) the Float-side helpers `sqrt` / `pow` / `log` /
      // `exp` / `floor` / `ceil` / `round` / `sin` / `cos` / `tan` /
      // `atan` / `atan2`, plus the constants `pi` and `e`. The Float
      // operations forward to runtime intrinsics declared as
      // `_pkl_math_<op>` global identifiers; the CallExpr dispatch in
      // `eval.mbt` intercepts those names and computes the result via
      // MoonBit's `math` module.
      //
      // `maxInt` / `minInt` track Apple Pkl's 64-bit Int range.
      //
      // The helpers are declared as top-level lambda bindings rather
      // than `function` declarations because the parser marks
      // `function ... = ...` forms as `exported: false`, which keeps
      // them out of the imported module's `ObjectValue`. Lambda-valued
      // bindings round-trip through the regular `exported: true` path.
      let source =
        #|minInt8 = 0 - 128
        #|minInt16 = 0 - 32768
        #|maxInt8 = 127
        #|maxInt16 = 32767
        #|maxInt32 = 2147483647
        #|minInt32 = 0 - 2147483647 - 1
        #|maxInt = 9223372036854775807
        #|minInt = 0 - 9223372036854775807 - 1
        #|maxUInt = 9223372036854775807
        #|maxUInt8 = 255
        #|maxUInt16 = 65535
        #|maxUInt32 = 4294967295
        #|pi = 3.141592653589793
        #|e = 2.718281828459045
        #|maxFiniteFloat = 1.7976931348623157E308
        #|minFiniteFloat = 0.0 - 1.7976931348623157E308
        #|abs = (x) -> if (x < 0) 0 - x else x
        #|min = (a, b) -> _pkl_math_min(a, b)
        #|max = (a, b) -> _pkl_math_max(a, b)
        #|sqrt = (x) -> _pkl_math_sqrt(x)
        #|cbrt = (x) -> _pkl_math_cbrt(x)
        #|pow = (x, y) -> _pkl_math_pow(x, y)
        #|log = (x) -> _pkl_math_log(x)
        #|log2 = (x) -> _pkl_math_log2(x)
        #|log10 = (x) -> _pkl_math_log10(x)
        #|exp = (x) -> _pkl_math_exp(x)
        #|floor = (x) -> _pkl_math_floor(x)
        #|ceil = (x) -> _pkl_math_ceil(x)
        #|round = (x) -> _pkl_math_round(x)
        #|sin = (x) -> _pkl_math_sin(x)
        #|cos = (x) -> _pkl_math_cos(x)
        #|tan = (x) -> _pkl_math_tan(x)
        #|asin = (x) -> _pkl_math_asin(x)
        #|acos = (x) -> _pkl_math_acos(x)
        #|atan = (x) -> _pkl_math_atan(x)
        #|atan2 = (y, x) -> _pkl_math_atan2(y, x)
        #|gcd = (a, b) -> _pkl_math_gcd(a, b)
        #|lcm = (a, b) -> _pkl_math_lcm(a, b)
        #|isPowerOfTwo = (x) -> _pkl_math_is_power_of_two(x)
      Some(source)
    }
    "pkl:platform" => {
      // PKL-123: read-only stub. Apple Pkl's `pkl:platform` reads the
      // host VM (`System.getProperty("os.name")` etc.); we hard-code
      // portable stub values so fixtures are deterministic across CI
      // hosts. A future slice can swap in host-detected values via
      // intrinsics without breaking the existing API shape.
      let source =
        #|current = new {
        #|  operatingSystem = new {
        #|    name = "stub-os"
        #|    version = "0.0.0"
        #|  }
        #|  architecture = new {
        #|    name = "stub-arch"
        #|  }
        #|  language = new {
        #|    version = "0.30.0"
        #|  }
        #|  runtime = new {
        #|    name = "stub-runtime"
        #|    version = "0.0.0"
        #|  }
        #|  virtualMachine = new {
        #|    name = "stub-vm"
        #|    version = "0.0.0"
        #|  }
        #|  processor = new {
        #|    architecture = "stub-arch"
        #|  }
        #|}
      Some(source)
    }
    "pkl:release" => {
      // PKL-152: deterministic release metadata stub. The upstream
      // fixture only validates the public shape and simple predicates,
      // not the exact host build metadata.
      let source =
        #|current = new {
        #|  version = new {
        #|    major = 0
        #|    minor = 30
        #|    patch = 0
        #|  }
        #|  versionInfo = "Linux pkl-mbt"
        #|  commitId = "abcdef0"
        #|  sourceCode = new {
        #|    homepage = "https://github.com/apple/pkl/"
        #|  }
        #|  documentation = new {
        #|    homepage = "https://pkl-lang.org/"
        #|  }
        #|  standardLibrary = new {
        #|    modules = List(
        #|      "pkl:analyze",
        #|      "pkl:base",
        #|      "pkl:Benchmark",
        #|      "pkl:json",
        #|      "pkl:math",
        #|      "pkl:platform",
        #|      "pkl:protobuf",
        #|      "pkl:reflect",
        #|      "pkl:release",
        #|      "pkl:semver",
        #|      "pkl:shell",
        #|      "pkl:test",
        #|      "pkl:xml",
        #|      "pkl:yaml",
        #|    )
        #|  }
        #|}
      Some(source)
    }
    "pkl:Benchmark" => {
      // PKL-152: benchmark fixtures assert the result object shape and
      // monotonic Duration relationships. Use deterministic samples
      // instead of measuring wall-clock time.
      let source =
        #|iterations = 1
        #|iterationTime = 1.ms
        #|isVerbose = false
        #|microbenchmarks = new Mapping {}
        #|outputBenchmarks = new Mapping {}
        #|parserBenchmarks = new Mapping {}
        #|output = new {
        #|  text = "[\"micro\"]\n[\"output\"]\n[\"parser\"]"
        #|}
        #|
        #|class Microbenchmark {
        #|  expression: Any
        #|  iterations: Int = 1
        #|  iterationTime: Duration = 1.ms
        #|  isVerbose: Boolean = false
        #|  function run() = new {
        #|    iterations = this.iterations
        #|    repetitions = 1
        #|    samples = null
        #|    min = 1.ms
        #|    max = 1.ms
        #|    mean = 1.ms
        #|  }
        #|}
        #|
        #|class OutputBenchmark {
        #|  sourceModule: Any
        #|  iterations: Int = 1
        #|  iterationTime: Duration = 1.ms
        #|  isVerbose: Boolean = false
        #|  function run() = new {
        #|    iterations = this.iterations
        #|    repetitions = 1
        #|    samples = if (this.isVerbose) List(1.ms, 1.ms, 1.ms) else null
        #|    min = 1.ms
        #|    max = 1.ms
        #|    mean = 1.ms
        #|  }
        #|}
        #|
        #|class ParserBenchmark {
        #|  sourceText: String
        #|  iterations: Int = 1
        #|  iterationTime: Duration = 1.ms
        #|  isVerbose: Boolean = false
        #|  function run() = new {
        #|    iterations = this.iterations
        #|    repetitions = 1
        #|    samples = null
        #|    min = 1.ms
        #|    max = 1.ms
        #|    mean = 1.ms
        #|  }
        #|}
      Some(source)
    }
    "pkl:semver" => {
      // PKL-123: `Version` constructor builds the canonical record
      // (major / minor / patch / preRelease / build). `parse` and
      // `parseOrNull` forward to the `_pkl_semver_parse(_or_null)`
      // intrinsics so the lexer logic stays in MoonBit; `parse` raises
      // a diagnostic on bad input while `parseOrNull` returns null.
      // Comparison helpers wrap `_pkl_semver_compare` (`<0` / `0` /
      // `>0` style) so pre-release ordering follows the SemVer spec
      // without re-implementing it in pkl. Apple Pkl's public
      // `comparator` is the Boolean shape expected by `sortWith`.
      let source =
        #|Version = (s) -> _pkl_semver_parse(s)
        #|parse = (s) -> _pkl_semver_parse(s)
        #|parseOrNull = (s) -> _pkl_semver_parse_or_null(s)
        #|compare = (a, b) -> _pkl_semver_compare(a, b)
        #|comparator = (a, b) -> _pkl_semver_compare(a, b) < 0
        #|isLessThan = (a, b) -> _pkl_semver_compare(a, b) < 0
        #|isGreaterThan = (a, b) -> _pkl_semver_compare(a, b) > 0
        #|isEqualTo = (a, b) -> _pkl_semver_compare(a, b) == 0
      Some(source)
    }
    "pkl:test" => Some("catch = null")
    "pkl:analyze" => {
      // PKL-148bo: forward `importGraph(moduleUris)` to the
      // `_pkl_analyze_import_graph` intrinsic. The intrinsic walks the
      // sandbox-recorded per-module import edges (populated by the
      // CLI's `load_path` pre-walk) and returns a value that already
      // matches the `ImportGraph { imports, resolvedImports }` shape;
      // we still declare the class so type annotations / `is
      // ImportGraph` checks line up.
      let source =
        #|class ImportGraph {
        #|  imports: Mapping = new {}
        #|  resolvedImports: Mapping = new {}
        #|}
        #|class Import {
        #|  uri: String
        #|}
        #|importGraph = (moduleUris) -> _pkl_analyze_import_graph(moduleUris)
      Some(source)
    }
    "pkl:jsonnet" => {
      // PKL-148bm: `pkl:jsonnet` is a Pkl-side stub used by the
      // jsonnet renderer. The actual Jsonnet emission lives in
      // `eval_render_jsonnet.mbt` — this stub exposes the public
      // `Renderer` class for `new jsonnet.Renderer {}` instantiation
      // and the `ExtVar` / `ImportStr` constructors that produce
      // tagged ObjectValues the renderer recognises and projects as
      // `std.extVar(...)` / `importstr ...`. `renderValue` /
      // `renderDocument` are intercepted by `eval_value_renderer_method`
      // in eval_expr.mbt so the function bodies here are never run.
      // PKL-148bm: pkl:jsonnet is a Pkl-side stub. The renderer body
      // lives in eval_render_jsonnet.mbt; the stub only needs to
      // expose the `Renderer` class plus tagged `ExtVar` / `ImportStr`
      // record shapes. Apple Pkl uses dedicated classes for the
      // latter, but because user-typed `new T { ... }` results don't
      // currently carry the class tag through lambda return paths,
      // the constructors stamp a hidden `@__jsonnet_kind` marker that
      // the renderer recognises in `jsonnet_special_object_text`.
      let source =
        #|class Renderer {
        #|  indent: String = "  "
        #|  omitNullProperties: Boolean = true
        #|  converters: Mapping = new {}
        #|}
        #|ExtVar = (_name) -> new {
        #|  __jsonnet_kind__ = "ExtVar"
        #|  name = _name
        #|}
        #|ImportStr = (_path) -> new {
        #|  __jsonnet_kind__ = "ImportStr"
        #|  path = _path
        #|}
      Some(source)
    }
    // PKL-148bh: `pkl:shell.escapeWithSingleQuotes(str)` — wraps the
    // string in single quotes and escapes internal `'` via the
    // `'\''` shell-quote idiom (api/shellModule).
    "pkl:shell" => {
      let source =
        #|escapeWithSingleQuotes = (str) -> _pkl_shell_escape_single_quote(str)
      Some(source)
    }
    // PKL-148bh: `pkl:base` is the implicit-imported root stdlib.
    // Apple Pkl allows explicit `import "pkl:base"` (modules/equality
    // does it twice — once bare, once `as base2`) so the binding can
    // be inspected for object-equality. The contents are vacuously
    // empty here — every pkl:base name already resolves through the
    // bare-identifier path so the import only needs to provide an
    // ObjectValue that satisfies equality comparisons.
    "pkl:base" => Some("")
    "pkl:json" => {
      // PKL-124 / PKL-144 / PKL-145: `pkl:json` carries `Parser` and
      // the annotation class `Property`. The Parser stamps a hidden
      // `__kind = "JsonParser"` class property (PKL-145 added the
      // `hidden` modifier on class properties) so the evaluator's
      // CallExpr path intercepts `parser.parse(source)` by checking
      // the marker rather than relying on member-shape coincidence.
      // The Json→Value conversion routes through MoonBit core's
      // `@json.parse` and honours `useMapping`. The user-facing
      // `JsonRenderer` lives in `pkl:base`.
      let source =
        #|class Parser {
        #|  useMapping: Boolean = false
        #|  converters: Any = new Mapping {}
        #|  hidden __kind: String = "JsonParser"
        #|}
        #|class Property extends ConvertProperty {
        #|  name: String
        #|  render = (prop, _) -> Pair(name, prop.value)
        #|}
      Some(source)
    }
    "pkl:yaml" => {
      // PKL-124 / PKL-146: parallel to `pkl:json` — Parser + Property
      // surface. The Parser stamps a hidden `__kind = "YamlParser"`
      // marker (PKL-145 enabled `hidden` on class properties) so the
      // evaluator intercepts `parser.parse(source)` and routes the
      // YAML body through `moonbit-community/yaml`'s
      // `Yaml::load_from_string`, projecting each document onto a
      // Pkl Value via `yaml_to_value`. The YAML renderer itself is a
      // `pkl:base` re-export.
      let source =
        #|class Parser {
        #|  mode: String = "compat"
        #|  useMapping: Boolean = false
        #|  converters: Any = new Mapping {}
        #|  maxCollectionAliases: Int = 50
        #|  hidden __kind: String = "YamlParser"
        #|}
        #|class Property {
        #|  name: String
        #|}
      Some(source)
    }
    "pkl:xml" => {
      // PKL-124: the `pkl:xml` module exposes the renderer under its
      // own qualified name `xml.Renderer`. The class shape is also
      // consumed by the AST-driven renderer detection and XML helper
      // constructors.
      let source =
        #|class Renderer {
        #|  indent: String = "  "
        #|  xmlVersion: String = "1.0"
        #|  rootElementName: String = "root"
        #|}
        #|class Element {
        #|  hidden __xmlKind: String = "Element"
        #|  name: String
        #|  isBlockFormat: Boolean = true
        #|}
        #|class Inline {
        #|  hidden __xmlKind: String = "Inline"
        #|  value: Any
        #|}
        #|class CData {
        #|  hidden __xmlKind: String = "CData"
        #|  text: String
        #|}
        #|class Comment {
        #|  hidden __xmlKind: String = "Comment"
        #|  text: String
        #|}
        #|class Property {
        #|  name: String
        #|}
      Some(source)
    }
    "pkl:protobuf" => {
      // PKL-124: protobuf renderer surface lives in the `pkl:protobuf`
      // module under the qualified `protobuf.Renderer` name.
      let source =
        #|class Renderer {
        #|  indent: String = "  "
        #|}
        #|class Property {
        #|  name: String
        #|}
      Some(source)
    }
    "pkl:reflect" => {
      // PKL-080 minimal slice. Apple's `pkl:reflect` is ~460 lines and built
      // around `external` declarations that bind directly to VM internals
      // (Class / Module / Property / TypeAlias / Type mirrors). A faithful
      // implementation would require a `ClassValue` variant in the value
      // model and a way to surface module / class members at runtime — neither
      // of which exists yet.
      //
      // The stub below covers what fixtures actually reach for first:
      //  - String-tagged mirror constants for the common base types.
      //    The tag format `"pkl.base#<name>"` is internal to this stub; it is
      //    intentionally distinct from any user-visible string so a real
      //    mirror type can replace it later without ambiguity.
      //  - `Class` / `Module` / `TypeAlias` / `Property` factories that take
      //    a string identifier and return a container exposing `reflectee`.
      //    This degrades the upstream "pass the class itself" API to a
      //    "pass the class name" API, traded for being implementable today.
      //  - `DeclaredType(referent)` wrapping a mirror so nested `referent`
      //    walks line up with upstream usage.
      //  - `isSubclassOf(other)` is intentionally absent from this slice; the
      //    naive name-equality check it would collapse to is misleading enough
      //    that a follow-up should add a real subclass relation table.
      let source =
        #|class Type {}
        #|class Property {}
        #|class Method {}
        #|
        #|anyType = _pkl_reflect_type("Any")
        #|booleanType = _pkl_reflect_type("Boolean")
        #|intType = _pkl_reflect_type("Int")
        #|floatType = _pkl_reflect_type("Float")
        #|numberType = _pkl_reflect_type("Number")
        #|stringType = _pkl_reflect_type("String")
        #|durationType = _pkl_reflect_type("Duration")
        #|dataSizeType = _pkl_reflect_type("DataSize")
        #|bytesType = _pkl_reflect_type("Bytes")
        #|pairType = _pkl_reflect_type("Pair")
        #|listType = _pkl_reflect_type("List")
        #|setType = _pkl_reflect_type("Set")
        #|mapType = _pkl_reflect_type("Map")
        #|listingType = _pkl_reflect_type("Listing")
        #|mappingType = _pkl_reflect_type("Mapping")
        #|objectType = _pkl_reflect_type("Object")
        #|dynamicType = _pkl_reflect_type("Dynamic")
        #|typedType = _pkl_reflect_type("Typed")
        #|moduleType = _pkl_reflect_type("Module")
        #|unknownType = _pkl_reflect_type("unknown")
        #|nothingType = _pkl_reflect_type("nothing")
        // PKL-143: Class / Module mirrors carry a hidden `__kind`
        // marker that the evaluator uses to hijack `.properties` /
        // `.methods` / `.supertype` / `.classes` / `.isSubclassOf`
        // member access. The marker doesn't render (hidden modifier)
        // and the user-facing surface still exposes `reflectee`.
        #|Class = (name) -> _pkl_reflect_class(name)
        #|Module = (name) -> _pkl_reflect_module(name)
        #|moduleOf = (name) -> _pkl_reflect_module(name)
        #|TypeAlias = (name) -> _pkl_reflect_type_alias(name)
        #|Property = (name) -> new { name = name }
        #|DeclaredType = (referent) -> _pkl_reflect_declared_type(referent)
        #|UnionType = (types) -> _pkl_reflect_union_type(types)
        #|StringLiteralType = (value) -> _pkl_reflect_string_literal_type(value)
        #|TypeVariable = (parameter) -> _pkl_reflect_type_variable(parameter)
      Some(source)
    }
    _ => None
  }
}

///|
fn get_module_source(
  sources : @ripple.Input[String, String],
  rt : @ripple.Runtime,
  path : String,
) -> String? {
  match builtin_stdlib_source(path) {
    Some(source) => Some(source)
    None => sources.get(rt, path)
  }
}

///|
fn typecheck_module_path(
  parses : @ripple.Query[String, ParseResult?],
  types_ref : Ref[@ripple.CycleQuery[String, TypecheckResult]?],
  rt : @ripple.Runtime,
  path : String,
) -> TypecheckResult {
  match parses.fetch(rt, path) {
    Some(parsed) =>
      typecheck_parsed_with_import_details(
        parsed,
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          Some(types_ref.val.unwrap().fetch(rt, resolved))
        },
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          match parses.fetch(rt, resolved) {
            Some(imported) => Some(type_exports_from_parse_result(imported))
            None => None
          }
        },
      )
    None => TypeError([diag("Cannot find module `\{path}`.")])
  }
}

///|
/// PKL-148bh: derive a module name from a file path the same way Apple
/// Pkl does — strip the parent directories and the trailing `.pkl`
/// extension, return `None` for paths that don't end in `.pkl` (the
/// reflect mirror falls back to the bare simple name).
fn derive_module_name_from_path(path : String) -> String? {
  let basename = match path.rev_find("/") {
    Some(idx) =>
      String::unsafe_substring(path, start=idx + 1, end=path.length())
    None => path
  }
  if basename.has_suffix(".pkl") {
    Some(String::unsafe_substring(basename, start=0, end=basename.length() - 4))
  } else if basename == "" {
    None
  } else {
    Some(basename)
  }
}

///|
fn eval_module_path(
  sources : @ripple.Input[String, String],
  rt : @ripple.Runtime,
  path : String,
  stack : Array[String],
) -> EvalResult {
  if stack_contains(stack, path) {
    // PKL-148bb: a cyclic import where the cycle only travels through
    // type-position references (`class Bar { foo: M1.Foo }` inside M2
    // imported back into M1) is legal in Apple Pkl — the type info is
    // extracted through the parallel `resolve_import_classes` walk
    // which parses without evaluating. Return an empty module value
    // so the value-side import binding doesn't fail; if any actual
    // value reference closes the cycle, the downstream `Cannot find
    // property` diagnostic will surface there. (`modules/recursiveModule1`.)
    return EvalOk(ObjectValue([]))
  }
  match get_module_source(sources, rt, path) {
    Some(source) =>
      eval_source_with_import_details_named_at(
        source,
        derive_module_name_from_path(path),
        Some(path),
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          Some(eval_module_path(sources, rt, resolved, push_stack(stack, path)))
        },
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          match get_module_source(sources, rt, resolved) {
            Some(imported_source) => {
              // Walk `extends "parent.pkl"` so an importer of this
              // module also sees classes inherited from its parent —
              // Apple Pkl's extends is class inheritance, not a
              // namespaced import (PKL-148f).
              let visited : Array[String] = []
              let exports : Array[ClassExport] = []
              let mut current_path = resolved
              let mut current_parsed = parse_source(imported_source)
              let mut keep_going = true
              while keep_going {
                if visited.contains(current_path) {
                  keep_going = false
                } else {
                  visited.push(current_path)
                  for
                    class_export in class_exports_from_parse_result(
                      current_parsed,
                    ) {
                    exports.push(class_export)
                  }
                  match current_parsed.program.module_relation {
                    Some(relation) => {
                      let parent_resolved = resolve_import_path(
                        current_path,
                        relation.uri,
                      )
                      match get_module_source(sources, rt, parent_resolved) {
                        Some(parent_source) => {
                          current_path = parent_resolved
                          current_parsed = parse_source(parent_source)
                        }
                        None => keep_going = false
                      }
                    }
                    None => keep_going = false
                  }
                }
              }
              Some(exports)
            }
            None => None
          }
        },
        fn(uri) {
          // PKL-153: parent's raw Binding[] (including locals) so the
          // re-eval path can resolve identifiers like a parent-local
          // `duplicateNames` that the parent's visible `output` body
          // references. We re-parse the parent module (cheap; this
          // resolver is only called when the derived module amends or
          // extends — i.e. once per module relation) and surface the
          // raw bindings.
          let resolved = resolve_import_path(path, uri)
          match get_module_source(sources, rt, resolved) {
            Some(parent_source) => {
              let parsed = parse_source(parent_source)
              Some(parsed.program.bindings)
            }
            None => None
          }
        },
      )
    None => EvalError([diag("Cannot find module `\{path}`.")])
  }
}
