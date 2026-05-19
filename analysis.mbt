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
  // function exports; only this returning boundary strips them.
  match self.evals.fetch(self.db.runtime(), path) {
    EvalOk(ObjectValue(members)) => {
      let visible : Array[ValueMember] = []
      for field in members {
        if !is_invisible_member_name(field.name) {
          visible.push(field)
        }
      }
      EvalOk(ObjectValue(visible))
    }
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
    return uri
  }
  match from.rev_find("/") {
    Some(idx) => String::unsafe_substring(from, start=0, end=idx + 1) + uri
    None => uri
  }
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
      // `maxInt` / `minInt` track our 32-bit `Int` representation; once
      // a 64-bit slot exists, they expand to match the Java-derived
      // Apple Pkl bounds.
      //
      // The helpers are declared as top-level lambda bindings rather
      // than `function` declarations because the parser marks
      // `function ... = ...` forms as `exported: false`, which keeps
      // them out of the imported module's `ObjectValue`. Lambda-valued
      // bindings round-trip through the regular `exported: true` path.
      let source =
        #|maxInt32 = 2147483647
        #|minInt32 = 0 - 2147483647 - 1
        #|maxInt = 2147483647
        #|minInt = 0 - 2147483647 - 1
        #|pi = 3.141592653589793
        #|e = 2.718281828459045
        #|abs = (x) -> if (x < 0) 0 - x else x
        #|min = (a, b) -> if (a < b) a else b
        #|max = (a, b) -> if (a > b) a else b
        #|sqrt = (x) -> _pkl_math_sqrt(x)
        #|pow = (x, y) -> _pkl_math_pow(x, y)
        #|log = (x) -> _pkl_math_log(x)
        #|exp = (x) -> _pkl_math_exp(x)
        #|floor = (x) -> _pkl_math_floor(x)
        #|ceil = (x) -> _pkl_math_ceil(x)
        #|round = (x) -> _pkl_math_round(x)
        #|sin = (x) -> _pkl_math_sin(x)
        #|cos = (x) -> _pkl_math_cos(x)
        #|tan = (x) -> _pkl_math_tan(x)
        #|atan = (x) -> _pkl_math_atan(x)
        #|atan2 = (y, x) -> _pkl_math_atan2(y, x)
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
    "pkl:semver" => {
      // PKL-123: `Version` constructor builds the canonical record
      // (major / minor / patch / preRelease / build). `parse` and
      // `parseOrNull` forward to the `_pkl_semver_parse(_or_null)`
      // intrinsics so the lexer logic stays in MoonBit; `parse` raises
      // a diagnostic on bad input while `parseOrNull` returns null.
      // Comparison helpers wrap `_pkl_semver_compare` (`<0` / `0` /
      // `>0` style) so pre-release ordering follows the SemVer spec
      // without re-implementing it in pkl.
      let source =
        #|Version = (major, minor, patch) -> new {
        #|  major = major
        #|  minor = minor
        #|  patch = patch
        #|  preRelease = null
        #|  build = null
        #|}
        #|parse = (s) -> _pkl_semver_parse(s)
        #|parseOrNull = (s) -> _pkl_semver_parse_or_null(s)
        #|compare = (a, b) -> _pkl_semver_compare(a, b)
        #|isLessThan = (a, b) -> _pkl_semver_compare(a, b) < 0
        #|isGreaterThan = (a, b) -> _pkl_semver_compare(a, b) > 0
        #|isEqualTo = (a, b) -> _pkl_semver_compare(a, b) == 0
      Some(source)
    }
    "pkl:test" => Some("catch = null")
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
        #|  hidden __kind: String = "JsonParser"
        #|}
        #|class Property {
        #|  name: String
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
        #|  useMapping: Boolean = false
        #|  hidden __kind: String = "YamlParser"
        #|}
        #|class Property {
        #|  name: String
        #|}
      Some(source)
    }
    "pkl:xml" => {
      // PKL-124: the `pkl:xml` module exposes the renderer under its
      // own qualified name `xml.Renderer`. The underlying renderer
      // implementation lands with PKL-126; right now the class shape
      // exists only so `import "pkl:xml" as xml; new xml.Renderer
      // { ... }` parses and typechecks.
      let source =
        #|class Renderer {
        #|  indent: String = "  "
        #|  xmlVersion: String = "1.0"
        #|  rootElementName: String = "root"
        #|}
        #|class Element {
        #|  name: String
        #|}
        #|class Inline {
        #|  name: String
        #|}
      Some(source)
    }
    "pkl:protobuf" => {
      // PKL-124: protobuf renderer surface lives in the `pkl:protobuf`
      // module under the qualified `protobuf.Renderer` name. Same
      // shape as `pkl:xml` — class declaration only; the wire-format
      // emitter is deferred to PKL-126.
      let source =
        #|class Renderer {
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
        #|anyType = "pkl.base#Any"
        #|booleanType = "pkl.base#Boolean"
        #|intType = "pkl.base#Int"
        #|floatType = "pkl.base#Float"
        #|numberType = "pkl.base#Number"
        #|stringType = "pkl.base#String"
        #|durationType = "pkl.base#Duration"
        #|dataSizeType = "pkl.base#DataSize"
        #|bytesType = "pkl.base#Bytes"
        #|pairType = "pkl.base#Pair"
        #|listType = "pkl.base#List"
        #|setType = "pkl.base#Set"
        #|mapType = "pkl.base#Map"
        #|listingType = "pkl.base#Listing"
        #|mappingType = "pkl.base#Mapping"
        #|objectType = "pkl.base#Object"
        #|dynamicType = "pkl.base#Dynamic"
        #|typedType = "pkl.base#Typed"
        #|moduleType = "pkl.base#Module"
        #|unknownType = "pkl.base#unknown"
        #|nothingType = "pkl.base#nothing"
        // PKL-143: Class / Module mirrors carry a hidden `__kind`
        // marker that the evaluator uses to hijack `.properties` /
        // `.methods` / `.supertype` / `.classes` / `.isSubclassOf`
        // member access. The marker doesn't render (hidden modifier)
        // and the user-facing surface still exposes `reflectee`.
        #|Class = (name) -> new {
        #|  reflectee = name
        #|  hidden __kind = "Class"
        #|  modifiers = Set()
        #|}
        #|Module = (name) -> new {
        #|  reflectee = name
        #|  hidden __kind = "Module"
        #|  modifiers = Set()
        #|  imports = if (name is Object) name.imports else Map()
        #|}
        #|TypeAlias = (name) -> new {
        #|  reflectee = name
        #|  hidden __kind = "TypeAlias"
        #|  modifiers = Set()
        #|}
        #|Property = (name) -> new { name = name }
        #|DeclaredType = (referent) -> new { referent = referent }
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
    Some(idx) => String::unsafe_substring(path, start=idx + 1, end=path.length())
    None => path
  }
  if basename.has_suffix(".pkl") {
    Some(
      String::unsafe_substring(basename, start=0, end=basename.length() - 4),
    )
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
      eval_source_with_import_details_named(
        source,
        derive_module_name_from_path(path),
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
      )
    None => EvalError([diag("Cannot find module `\{path}`.")])
  }
}
