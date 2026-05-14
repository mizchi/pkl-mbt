///|
pub(all) enum Value {
  IntValue(Int)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  ObjectValue(Array[ValueMember])
} derive(Eq, Debug)

///|
pub(all) struct ValueMember {
  name : String
  value : Value
} derive(Eq, Debug)

///|
pub(all) enum EvalResult {
  EvalOk(Value)
  EvalError(Array[Diagnostic])
} derive(Eq, Debug)

///|
priv struct ValueBinding {
  name : String
  value : Value
}

///|
fn lookup_value(env : Array[ValueBinding], name : String) -> Value? {
  let mut found : Value? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.value)
    }
  }
  found
}

///|
fn lookup_member(members : Array[ValueMember], name : String) -> Value? {
  let mut found : Value? = None
  for field in members {
    if field.name == name {
      found = Some(field.value)
    }
  }
  found
}

///|
fn find_binding(bindings : Array[Binding], name : String) -> Binding? {
  let mut found : Binding? = None
  for binding in bindings {
    if binding.name == name {
      found = Some(binding)
    }
  }
  found
}

///|
fn stack_contains_binding(stack : Array[String], name : String) -> Bool {
  for item in stack {
    if item == name {
      return true
    }
  }
  false
}

///|
fn push_binding_stack(stack : Array[String], name : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(name)
  next
}

///|
fn resolve_binding_value(
  name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match lookup_value(cache, name) {
    Some(value) => Some(value)
    None =>
      match find_binding(bindings, name) {
        Some(binding) =>
          if stack_contains_binding(stack, name) {
            diagnostics.push(Diagnostic::{
              message: "cyclic property reference \{name}",
            })
            None
          } else {
            match
              eval_expr_with_bindings(
                binding.value,
                bindings,
                env,
                cache,
                push_binding_stack(stack, name),
                diagnostics,
                resolve_import,
              ) {
              Some(value) => {
                cache.push({ name, value })
                Some(value)
              }
              None => None
            }
          }
        None => lookup_value(env, name)
      }
  }
}

///|
fn eval_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match expr {
    IntLiteral(value) => Some(IntValue(value))
    BoolLiteral(value) => Some(BoolValue(value))
    StringLiteral(value) => Some(StringValue(value))
    NullLiteral => Some(NullValue)
    ImportExpr(uri) =>
      match resolve_import(uri) {
        Some(EvalOk(value)) => Some(value)
        Some(EvalError(errors)) => {
          for error in errors {
            diagnostics.push(error)
          }
          None
        }
        None => {
          diagnostics.push(Diagnostic::{ message: "unresolved import \{uri}" })
          None
        }
      }
    ObjectLiteral(members) => {
      let values : Array[ValueMember] = []
      for field in members {
        match
          eval_expr_with_bindings(
            field.value,
            bindings,
            env,
            cache,
            stack,
            diagnostics,
            resolve_import,
          ) {
          Some(value) => values.push({ name: field.name, value })
          None => ()
        }
      }
      Some(ObjectValue(values))
    }
    MemberAccess(target_expr, member_name) =>
      match
        eval_expr_with_bindings(
          target_expr, bindings, env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(ObjectValue(members)) =>
          match lookup_member(members, member_name) {
            Some(value) => Some(value)
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              None
            }
          }
        Some(_) => {
          diagnostics.push(Diagnostic::{
            message: "member access expects Object",
          })
          None
        }
        None => None
      }
    Identifier(name) =>
      match
        resolve_binding_value(
          name, bindings, env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(value) => Some(value)
        None => {
          diagnostics.push(Diagnostic::{ message: "unbound identifier \{name}" })
          None
        }
      }
    BinaryExpr(op, left_expr, right_expr) => {
      let left = eval_expr_with_bindings(
        left_expr, bindings, env, cache, stack, diagnostics, resolve_import,
      )
      let right = eval_expr_with_bindings(
        right_expr, bindings, env, cache, stack, diagnostics, resolve_import,
      )
      match (left, right) {
        (Some(IntValue(a)), Some(IntValue(b))) =>
          match op {
            Add => Some(IntValue(a + b))
            Subtract => Some(IntValue(a - b))
            Multiply => Some(IntValue(a * b))
            Divide =>
              if b == 0 {
                diagnostics.push(Diagnostic::{ message: "division by zero" })
                None
              } else {
                Some(IntValue(a / b))
              }
          }
        (Some(_), Some(_)) => {
          diagnostics.push(Diagnostic::{
            message: "operator \{operator_name(op)} expects Int operands",
          })
          None
        }
        _ => None
      }
    }
    ErrorExpr(message) => {
      diagnostics.push(Diagnostic::{ message, })
      None
    }
    UnsupportedExpr => {
      diagnostics.push(Diagnostic::{ message: "unsupported expression" })
      None
    }
  }
}

///|
fn eval_imports(
  imports : Array[ImportDecl],
  env : Array[ValueBinding],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Unit {
  for decl in imports {
    match resolve_import(decl.uri) {
      Some(EvalOk(value)) => env.push({ name: decl.import_name, value })
      Some(EvalError(errors)) =>
        for error in errors {
          diagnostics.push(error)
        }
      None =>
        diagnostics.push(Diagnostic::{
          message: "unresolved import \{decl.uri}",
        })
    }
  }
}

///|
fn eval_program(
  program : Program,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let env : Array[ValueBinding] = []
  let cache : Array[ValueBinding] = []
  let members : Array[ValueMember] = []
  eval_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    match
      resolve_binding_value(
        binding.name,
        program.bindings,
        env,
        cache,
        [],
        diagnostics,
        resolve_import,
      ) {
      Some(value) =>
        if binding.exported {
          members.push({ name: binding.name, value })
        }
      None => ()
    }
  }
  match program.body {
    Some(expr) =>
      eval_expr_with_bindings(
        expr,
        program.bindings,
        env,
        cache,
        [],
        diagnostics,
        resolve_import,
      )
    None if members.length() > 0 => Some(ObjectValue(members))
    None => {
      diagnostics.push(Diagnostic::{ message: "missing expression body" })
      None
    }
  }
}

///|
fn operator_name(op : BinaryOp) -> String {
  match op {
    Add => "+"
    Subtract => "-"
    Multiply => "*"
    Divide => "/"
  }
}

///|
pub fn eval_source(source : String) -> EvalResult {
  eval_source_with_imports(source, fn(_) { None })
}

///|
pub fn render_value(value : Value) -> String {
  match value {
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    StringValue(s) => "\"\{escape_string(s)}\""
    NullValue => "null"
    ObjectValue(members) => render_object_members(members)
  }
}

///|
fn escape_string(value : String) -> String {
  let buf = StringBuilder::new()
  for c in value {
    match c {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn render_object_members(members : Array[ValueMember]) -> String {
  let buf = StringBuilder::new()
  for i, field in members {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(field.name)
    buf.write_string(" = ")
    buf.write_string(render_value(field.value))
  }
  buf.to_string()
}

///|
fn eval_source_with_imports(
  source : String,
  resolve_import : (String) -> EvalResult?,
) -> EvalResult {
  let parsed = parse_source(source)
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return EvalError(diagnostics)
  }
  match eval_program(parsed.program, diagnostics, resolve_import) {
    Some(value) =>
      if diagnostics.length() == 0 {
        EvalOk(value)
      } else {
        EvalError(diagnostics)
      }
    None => EvalError(diagnostics)
  }
}
