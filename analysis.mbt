///|
pub struct AnalysisSession {
  priv db : @ripple.Database
  priv sources : @ripple.Input[String, String]
  priv types : @ripple.Query[String, TypecheckResult]
  priv evals : @ripple.Query[String, EvalResult]
}

///|
pub fn AnalysisSession::new() -> AnalysisSession {
  let db = @ripple.Database::new()
  let sources : @ripple.Input[String, String] = db.input()
  let types : @ripple.Query[String, TypecheckResult] = db.query(fn(rt, path) {
    typecheck_module_path(sources, rt, path, [])
  })
  let evals : @ripple.Query[String, EvalResult] = db.query(fn(rt, path) {
    eval_module_path(sources, rt, path, [])
  })
  AnalysisSession::{ db, sources, types, evals }
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
  sources : @ripple.Input[String, String],
  rt : @ripple.Runtime,
  path : String,
  stack : Array[String],
) -> TypecheckResult {
  if stack_contains(stack, path) {
    return TypeError([Diagnostic::{ message: "cyclic import \{path}" }])
  }
  match get_module_source(sources, rt, path) {
    Some(source) =>
      typecheck_source_with_imports(source, fn(uri) {
        let resolved = resolve_import_path(path, uri)
        Some(
          typecheck_module_path(sources, rt, resolved, push_stack(stack, path)),
        )
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
