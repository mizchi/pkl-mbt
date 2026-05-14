///|
pub(all) enum Type {
  IntType
  BoolType
  StringType
  NullType
  ObjectType(Array[TypeMember])
  UnknownType
} derive(Eq, Debug)

///|
pub(all) struct TypeMember {
  name : String
  typ : Type
} derive(Eq, Debug)

///|
pub(all) enum TypecheckResult {
  TypeOk(Type)
  TypeError(Array[Diagnostic])
} derive(Eq, Debug)

///|
priv struct TypeBinding {
  name : String
  typ : Type
}

///|
fn lookup_type(env : Array[TypeBinding], name : String) -> Type? {
  let mut found : Type? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.typ)
    }
  }
  found
}

///|
fn lookup_member_type(members : Array[TypeMember], name : String) -> Type? {
  let mut found : Type? = None
  for field in members {
    if field.name == name {
      found = Some(field.typ)
    }
  }
  found
}

///|
fn find_type_binding(bindings : Array[Binding], name : String) -> Binding? {
  let mut found : Binding? = None
  for binding in bindings {
    if binding.name == name {
      found = Some(binding)
    }
  }
  found
}

///|
fn stack_contains_type_binding(stack : Array[String], name : String) -> Bool {
  for item in stack {
    if item == name {
      return true
    }
  }
  false
}

///|
fn push_type_stack(stack : Array[String], name : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(name)
  next
}

///|
pub fn render_type(typ : Type) -> String {
  match typ {
    IntType => "Int"
    BoolType => "Boolean"
    StringType => "String"
    NullType => "Null"
    ObjectType(_) => "Object"
    UnknownType => "Unknown"
  }
}

///|
fn type_from_annotation(name : String) -> Type? {
  match name {
    "Int" => Some(IntType)
    "String" => Some(StringType)
    "Boolean" => Some(BoolType)
    "Bool" => Some(BoolType)
    "Null" => Some(NullType)
    "Object" => Some(ObjectType([]))
    _ => None
  }
}

///|
fn apply_type_annotation(
  type_name : String?,
  inferred : Type,
  diagnostics : Array[Diagnostic],
) -> Type {
  match type_name {
    None => inferred
    Some(name) =>
      match type_from_annotation(name) {
        Some(expected) =>
          if expected == inferred ||
            (expected is ObjectType(_) && inferred is ObjectType(_)) {
            expected
          } else {
            diagnostics.push(Diagnostic::{
              message: "type annotation \{name} does not accept \{render_type(inferred)}",
            })
            UnknownType
          }
        None => {
          diagnostics.push(Diagnostic::{
            message: "unknown type annotation \{name}",
          })
          UnknownType
        }
      }
  }
}

///|
fn resolve_binding_type(
  name : String,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type? {
  match lookup_type(cache, name) {
    Some(typ) => Some(typ)
    None =>
      match find_type_binding(bindings, name) {
        Some(binding) =>
          if stack_contains_type_binding(stack, name) {
            diagnostics.push(Diagnostic::{
              message: "cyclic property reference \{name}",
            })
            None
          } else {
            let inferred = infer_expr_with_bindings(
              binding.value,
              bindings,
              env,
              cache,
              push_type_stack(stack, name),
              diagnostics,
              resolve_import,
            )
            let typ = apply_type_annotation(
              binding.type_name,
              inferred,
              diagnostics,
            )
            cache.push({ name, typ })
            Some(typ)
          }
        None => lookup_type(env, name)
      }
  }
}

///|
fn infer_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  match expr {
    IntLiteral(_) => IntType
    BoolLiteral(_) => BoolType
    StringLiteral(_) => StringType
    NullLiteral => NullType
    ImportExpr(uri) =>
      match resolve_import(uri) {
        Some(TypeOk(typ)) => typ
        Some(TypeError(errors)) => {
          for error in errors {
            diagnostics.push(error)
          }
          UnknownType
        }
        None => {
          diagnostics.push(Diagnostic::{ message: "unresolved import \{uri}" })
          UnknownType
        }
      }
    ObjectLiteral(members) => {
      let fields : Array[TypeMember] = []
      for field in members {
        let inferred = infer_expr_with_bindings(
          field.value,
          bindings,
          env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        fields.push({
          name: field.name,
          typ: apply_type_annotation(field.type_name, inferred, diagnostics),
        })
      }
      ObjectType(fields)
    }
    MemberAccess(target_expr, member_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => typ
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(Diagnostic::{
            message: "member access expects Object",
          })
          UnknownType
        }
      }
    Identifier(name) =>
      match
        resolve_binding_type(
          name, bindings, env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(typ) => typ
        None => {
          diagnostics.push(Diagnostic::{ message: "unbound identifier \{name}" })
          UnknownType
        }
      }
    BinaryExpr(op, left_expr, right_expr) => {
      let left = infer_expr_with_bindings(
        left_expr, bindings, env, cache, stack, diagnostics, resolve_import,
      )
      let right = infer_expr_with_bindings(
        right_expr, bindings, env, cache, stack, diagnostics, resolve_import,
      )
      if left == IntType && right == IntType {
        IntType
      } else {
        diagnostics.push(Diagnostic::{
          message: "operator \{operator_name(op)} expects Int operands",
        })
        UnknownType
      }
    }
    ErrorExpr(message) => {
      diagnostics.push(Diagnostic::{ message, })
      UnknownType
    }
    UnsupportedExpr => {
      diagnostics.push(Diagnostic::{ message: "unsupported expression" })
      UnknownType
    }
  }
}

///|
fn infer_imports(
  imports : Array[ImportDecl],
  env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  for decl in imports {
    match resolve_import(decl.uri) {
      Some(TypeOk(typ)) => env.push({ name: decl.import_name, typ })
      Some(TypeError(errors)) =>
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
fn infer_program(
  program : Program,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  let env : Array[TypeBinding] = []
  let cache : Array[TypeBinding] = []
  let fields : Array[TypeMember] = []
  infer_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    match
      resolve_binding_type(
        binding.name,
        program.bindings,
        env,
        cache,
        [],
        diagnostics,
        resolve_import,
      ) {
      Some(typ) =>
        if binding.exported {
          fields.push({ name: binding.name, typ })
        }
      None => ()
    }
  }
  match program.body {
    Some(expr) =>
      infer_expr_with_bindings(
        expr,
        program.bindings,
        env,
        cache,
        [],
        diagnostics,
        resolve_import,
      )
    None if fields.length() > 0 => ObjectType(fields)
    None => {
      diagnostics.push(Diagnostic::{ message: "missing expression body" })
      UnknownType
    }
  }
}

///|
pub fn typecheck_source(source : String) -> TypecheckResult {
  typecheck_source_with_imports(source, fn(_) { None })
}

///|
fn typecheck_source_with_imports(
  source : String,
  resolve_import : (String) -> TypecheckResult?,
) -> TypecheckResult {
  let parsed = parse_source(source)
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return TypeError(diagnostics)
  }
  let typ = infer_program(parsed.program, diagnostics, resolve_import)
  if diagnostics.length() == 0 {
    TypeOk(typ)
  } else {
    TypeError(diagnostics)
  }
}
