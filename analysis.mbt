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
  self.evals.fetch(self.db.runtime(), path)
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
      // The math module exposes the Int range constants and a few pure
      // Int-side helpers. Float-only operations (sqrt / pow / log / exp /
      // ceil / floor / round) stay deferred until a real `FloatValue` lands
      // in the value model (PKL-092). `maxInt` and `minInt` track our 32-bit
      // `Int` representation; once a 64-bit slot exists, they expand to
      // match the Java-derived Apple Pkl bounds.
      //
      // The helpers are declared as top-level lambda bindings rather than
      // `function` declarations because the parser marks `function ... = ...`
      // forms as `exported: false`, which keeps them out of the imported
      // module's `ObjectValue`. Lambda-valued bindings round-trip through
      // the regular `exported: true` path.
      let source =
        #|maxInt32 = 2147483647
        #|minInt32 = 0 - 2147483647 - 1
        #|maxInt = 2147483647
        #|minInt = 0 - 2147483647 - 1
        #|abs = (x) -> if (x < 0) 0 - x else x
        #|min = (a, b) -> if (a < b) a else b
        #|max = (a, b) -> if (a > b) a else b
      Some(source)
    }
    "pkl:test" => Some("catch = null")
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
        #|Class = (name) -> new { reflectee = name }
        #|Module = (name) -> new { reflectee = name }
        #|TypeAlias = (name) -> new { reflectee = name }
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
    None => TypeError([diag("unresolved import \{path}")])
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
    return EvalError([diag("cyclic import \{path}")])
  }
  match get_module_source(sources, rt, path) {
    Some(source) =>
      eval_source_with_import_details(
        source,
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          Some(eval_module_path(sources, rt, resolved, push_stack(stack, path)))
        },
        fn(uri) {
          let resolved = resolve_import_path(path, uri)
          match get_module_source(sources, rt, resolved) {
            Some(imported_source) =>
              Some(
                class_exports_from_parse_result(parse_source(imported_source)),
              )
            None => None
          }
        },
      )
    None => EvalError([diag("unresolved import \{path}")])
  }
}
