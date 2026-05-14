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
    fn(_rt, path) {
      TypeError([Diagnostic::{ message: "cyclic import \{path}" }])
    },
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
    "pkl:math" => Some("maxInt32 = 2147483647")
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
      typecheck_parsed_with_imports(parsed, fn(uri) {
        let resolved = resolve_import_path(path, uri)
        Some(types_ref.val.unwrap().fetch(rt, resolved))
      })
    None => TypeError([Diagnostic::{ message: "unresolved import \{path}" }])
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
    return EvalError([Diagnostic::{ message: "cyclic import \{path}" }])
  }
  match get_module_source(sources, rt, path) {
    Some(source) =>
      eval_source_with_imports(source, fn(uri) {
        let resolved = resolve_import_path(path, uri)
        Some(eval_module_path(sources, rt, resolved, push_stack(stack, path)))
      })
    None => EvalError([Diagnostic::{ message: "unresolved import \{path}" }])
  }
}
