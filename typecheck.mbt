///|
pub(all) enum Type {
  IntType
  BoolType
  StringType
  NullType
  ObjectType(Array[TypeMember])
  ClassType(String, Array[TypeMember])
  ListingType(Array[Type])
  MappingType(Array[TypeEntry])
  FunctionType(Array[Type], Type)
  UnknownType
} derive(Eq, Debug)

///|
pub(all) struct TypeMember {
  name : String
  typ : Type
} derive(Eq, Debug)

///|
pub(all) struct TypeEntry {
  key : Type
  value : Type
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
fn merge_type_members(
  base : Array[TypeMember],
  overrides : Array[TypeMember],
) -> Array[TypeMember] {
  let merged : Array[TypeMember] = []
  for type_member in base {
    match lookup_member_type(overrides, type_member.name) {
      Some(typ) => merged.push({ name: type_member.name, typ })
      None => merged.push(type_member)
    }
  }
  for type_member in overrides {
    if lookup_member_type(base, type_member.name) is None {
      merged.push(type_member)
    }
  }
  merged
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
    ClassType(name, _) => name
    ListingType(_) => "Listing"
    MappingType(_) => "Mapping"
    FunctionType(_, _) => "Function"
    UnknownType => "Unknown"
  }
}

///|
fn builtin_type_from_annotation(name : String) -> Type? {
  match name {
    "Int" => Some(IntType)
    "String" => Some(StringType)
    "Boolean" => Some(BoolType)
    "Bool" => Some(BoolType)
    "Null" => Some(NullType)
    "Object" => Some(ObjectType([]))
    "Listing" => Some(ListingType([]))
    "Mapping" => Some(MappingType([]))
    _ => None
  }
}

///|
fn type_from_annotation(name : String, type_env : Array[TypeBinding]) -> Type? {
  match builtin_type_from_annotation(name) {
    Some(typ) => Some(typ)
    None => lookup_type(type_env, name)
  }
}

///|
fn type_accepts(expected : Type, inferred : Type) -> Bool {
  if expected == inferred {
    return true
  }
  match (expected, inferred) {
    (UnknownType, _) => true
    (ObjectType(_), ObjectType(_)) => true
    (ObjectType(_), ClassType(_, _)) => true
    (ClassType(_, expected_members), ObjectType(actual_members)) => {
      let mut ok = true
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            if !type_accepts(expected_member.typ, actual) {
              ok = false
            }
          None => ok = false
        }
      }
      ok
    }
    (ListingType(_), ListingType(_)) => true
    (MappingType(_), MappingType(_)) => true
    (FunctionType(_, _), FunctionType(_, _)) => true
    _ => false
  }
}

///|
fn class_type_mismatch_message(
  annotation_name : String,
  expected : Type,
  inferred : Type,
) -> String? {
  match (expected, inferred) {
    (ClassType(_, expected_members), ObjectType(actual_members)) => {
      let mut message : String? = None
      for expected_member in expected_members {
        if message is None {
          match lookup_member_type(actual_members, expected_member.name) {
            Some(actual) =>
              if !type_accepts(expected_member.typ, actual) {
                message = Some(
                  "type annotation \{annotation_name} member \{expected_member.name} expects \{render_type(expected_member.typ)}, got \{render_type(actual)}",
                )
              }
            None =>
              message = Some(
                "type annotation \{annotation_name} missing member \{expected_member.name}",
              )
          }
        }
      }
      message
    }
    _ => None
  }
}

///|
fn apply_type_annotation(
  type_name : String?,
  inferred : Type,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match type_name {
    None => inferred
    Some(name) =>
      match type_from_annotation(name, type_env) {
        Some(expected) =>
          if type_accepts(expected, inferred) {
            expected
          } else {
            let message = match
              class_type_mismatch_message(name, expected, inferred) {
              Some(detail) => detail
              None =>
                "type annotation \{name} does not accept \{render_type(inferred)}"
            }
            diagnostics.push(Diagnostic::{ message, })
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
fn common_type(types : Array[Type]) -> Type {
  if types.length() == 0 {
    return UnknownType
  }
  let first = types[0]
  for typ in types {
    if typ != first {
      return UnknownType
    }
  }
  first
}

///|
fn lookup_mapping_value_type(entries : Array[TypeEntry], key : Type) -> Type? {
  let mut found : Type? = None
  for entry in entries {
    if entry.key == key {
      found = Some(entry.value)
    }
  }
  found
}

///|
fn function_parameter_types(count : Int) -> Array[Type] {
  let parameters : Array[Type] = []
  for _i = 0; _i < count; _i = _i + 1 {
    parameters.push(UnknownType)
  }
  parameters
}

///|
fn copy_type_bindings(bindings : Array[TypeBinding]) -> Array[TypeBinding] {
  let copied : Array[TypeBinding] = []
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn all_program_bindings(program : Program) -> Array[Binding] {
  let bindings : Array[Binding] = []
  for decl in program.declarations {
    match decl {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) =>
            bindings.push({
              name: function_decl.name,
              type_name: None,
              value: LambdaExpr(function_decl.parameters, body),
              exported: false,
            })
          None => ()
        }
      _ => ()
    }
  }
  for binding in program.bindings {
    bindings.push(binding)
  }
  bindings
}

///|
fn class_properties_to_members(
  properties : Array[ClassProperty],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  let members : Array[TypeMember] = []
  for property in properties {
    let typ = match property.type_name {
      Some(type_name) =>
        match type_from_annotation(type_name, type_env) {
          Some(resolved) => resolved
          None => {
            diagnostics.push(Diagnostic::{
              message: "unknown type annotation \{type_name}",
            })
            UnknownType
          }
        }
      None => UnknownType
    }
    members.push({ name: property.name, typ })
  }
  members
}

///|
fn collect_declared_types(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Array[TypeBinding] {
  let type_env : Array[TypeBinding] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        type_env.push({
          name: class_decl.name,
          typ: ClassType(class_decl.name, []),
        })
      TypeAliasDeclaration(type_alias) =>
        match builtin_type_from_annotation(type_alias.target) {
          Some(typ) => type_env.push({ name: type_alias.name, typ })
          None => ()
        }
      FunctionDeclaration(_) => ()
    }
  }
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        type_env.push({
          name: class_decl.name,
          typ: ClassType(
            class_decl.name,
            class_properties_to_members(
              class_decl.properties,
              type_env,
              diagnostics,
            ),
          ),
        })
      TypeAliasDeclaration(type_alias) =>
        match type_from_annotation(type_alias.target, type_env) {
          Some(typ) => type_env.push({ name: type_alias.name, typ })
          None =>
            diagnostics.push(Diagnostic::{
              message: "unknown type annotation \{type_alias.target}",
            })
        }
      FunctionDeclaration(_) => ()
    }
  }
  type_env
}

///|
fn resolve_binding_type(
  name : String,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
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
              type_env,
              cache,
              push_type_stack(stack, name),
              diagnostics,
              resolve_import,
            )
            let typ = apply_type_annotation(
              binding.type_name,
              inferred,
              type_env,
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
fn infer_argument_types(
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[Type] {
  let argument_types : Array[Type] = []
  for argument in arguments {
    argument_types.push(
      infer_expr_with_bindings(
        argument, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      ),
    )
  }
  argument_types
}

///|
fn infer_lambda_application(
  label : String,
  parameters : Array[String],
  body : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  if parameters.length() != arguments.length() {
    diagnostics.push(Diagnostic::{
      message: "\{label} expects \{parameters.length()} arguments, got \{arguments.length()}",
    })
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  let call_cache = copy_type_bindings(cache)
  for i = 0; i < parameters.length(); i = i + 1 {
    call_cache.push({ name: parameters[i], typ: argument_types[i] })
  }
  infer_expr_with_bindings(
    body, bindings, env, type_env, call_cache, stack, diagnostics, resolve_import,
  )
}

///|
fn infer_function_type_call(
  parameter_types : Array[Type],
  return_type : Type,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  if parameter_types.length() != arguments.length() {
    diagnostics.push(Diagnostic::{
      message: "function expects \{parameter_types.length()} arguments, got \{arguments.length()}",
    })
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  for i = 0; i < parameter_types.length(); i = i + 1 {
    let expected = parameter_types[i]
    if expected != UnknownType && !type_accepts(expected, argument_types[i]) {
      diagnostics.push(Diagnostic::{
        message: "function argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
      })
      return UnknownType
    }
  }
  return_type
}

///|
fn infer_call_expr(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Type {
  match callee {
    LambdaExpr(parameters, body) =>
      return infer_lambda_application(
        "function", parameters, body, arguments, bindings, env, type_env, cache,
        stack, diagnostics, resolve_import,
      )
    Identifier(name) =>
      match find_type_binding(bindings, name) {
        Some(binding) =>
          match binding.value {
            LambdaExpr(parameters, body) =>
              return infer_lambda_application(
                "function \{name}",
                parameters,
                body,
                arguments,
                bindings,
                env,
                type_env,
                cache,
                stack,
                diagnostics,
                resolve_import,
              )
            _ => ()
          }
        None => ()
      }
    _ => ()
  }
  match
    infer_expr_with_bindings(
      callee, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
    ) {
    FunctionType(parameter_types, return_type) =>
      infer_function_type_call(
        parameter_types, return_type, arguments, bindings, env, type_env, cache,
        stack, diagnostics, resolve_import,
      )
    UnknownType => UnknownType
    _ => {
      diagnostics.push(Diagnostic::{ message: "call expects Function" })
      UnknownType
    }
  }
}

///|
fn infer_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
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
    ObjectLiteral(members) =>
      ObjectType(
        infer_object_members(
          members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ),
      )
    ListingLiteral(elements) => {
      let item_types : Array[Type] = []
      for element in elements {
        item_types.push(
          infer_expr_with_bindings(
            element, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
      }
      ListingType(item_types)
    }
    MappingLiteral(entries) => {
      let entry_types : Array[TypeEntry] = []
      for entry in entries {
        let key = infer_expr_with_bindings(
          entry.key,
          bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        let value = infer_expr_with_bindings(
          entry.value,
          bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        entry_types.push({ key, value })
      }
      MappingType(entry_types)
    }
    MemberAccess(target_expr, member_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
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
        ClassType(_, members) =>
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
    SubscriptAccess(target_expr, key_expr) => {
      let target = infer_expr_with_bindings(
        target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let key = infer_expr_with_bindings(
        key_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match target {
        ListingType(items) =>
          if key == IntType {
            match key_expr {
              IntLiteral(index) =>
                if index >= 0 && index < items.length() {
                  items[index]
                } else {
                  diagnostics.push(Diagnostic::{
                    message: "listing index out of bounds \{index}",
                  })
                  UnknownType
                }
              _ => common_type(items)
            }
          } else {
            diagnostics.push(Diagnostic::{
              message: "listing index expects Int",
            })
            UnknownType
          }
        MappingType(entries) =>
          match lookup_mapping_value_type(entries, key) {
            Some(value) => value
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown mapping key type",
              })
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(Diagnostic::{
            message: "subscript access expects Listing or Mapping",
          })
          UnknownType
        }
      }
    }
    AmendExpr(base_expr, members) =>
      match
        infer_expr_with_bindings(
          base_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(base_members) =>
          ObjectType(
            merge_type_members(
              base_members,
              infer_object_members(
                members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
              ),
            ),
          )
        ClassType(_, base_members) =>
          ObjectType(
            merge_type_members(
              base_members,
              infer_object_members(
                members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
              ),
            ),
          )
        UnknownType => UnknownType
        _ => {
          diagnostics.push(Diagnostic::{
            message: "object amendment expects Object",
          })
          UnknownType
        }
      }
    Identifier(name) =>
      match
        resolve_binding_type(
          name, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(typ) => typ
        None => {
          diagnostics.push(Diagnostic::{ message: "unbound identifier \{name}" })
          UnknownType
        }
      }
    CallExpr(callee, arguments) =>
      infer_call_expr(
        callee, arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
    LambdaExpr(parameters, _) =>
      FunctionType(function_parameter_types(parameters.length()), UnknownType)
    UnaryExpr(op, inner_expr) => {
      let inner = infer_expr_with_bindings(
        inner_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match op {
        Negate =>
          if inner == IntType {
            IntType
          } else {
            diagnostics.push(Diagnostic::{
              message: "operator - expects Int operand",
            })
            UnknownType
          }
        Not =>
          if inner == BoolType {
            BoolType
          } else {
            diagnostics.push(Diagnostic::{
              message: "operator ! expects Boolean operand",
            })
            UnknownType
          }
      }
    }
    BinaryExpr(op, left_expr, right_expr) => {
      if op == Is {
        ignore(
          infer_expr_with_bindings(
            left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
        return BoolType
      }
      if op == As {
        ignore(
          infer_expr_with_bindings(
            left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
        match right_expr {
          Identifier(name) =>
            match type_from_annotation(name, type_env) {
              Some(typ) => return typ
              None => {
                diagnostics.push(Diagnostic::{
                  message: "unknown type annotation \{name}",
                })
                return UnknownType
              }
            }
          _ => return UnknownType
        }
      }
      if op == Pipe {
        diagnostics.push(Diagnostic::{ message: "operator |> is parser-only" })
        return UnknownType
      }
      let left = infer_expr_with_bindings(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right = infer_expr_with_bindings(
        right_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      match op {
        Add | Subtract | Multiply | Divide | IntDivide | Modulo | Power =>
          if left == IntType && right == IntType {
            IntType
          } else {
            diagnostics.push(Diagnostic::{
              message: "operator \{operator_name(op)} expects Int operands",
            })
            UnknownType
          }
        LessThan | LessOrEqual | GreaterThan | GreaterOrEqual =>
          if left == IntType && right == IntType {
            BoolType
          } else {
            diagnostics.push(Diagnostic::{
              message: "operator \{operator_name(op)} expects Int operands",
            })
            UnknownType
          }
        Equal | NotEqual => BoolType
        And | Or =>
          if left == BoolType && right == BoolType {
            BoolType
          } else {
            diagnostics.push(Diagnostic::{
              message: "operator \{operator_name(op)} expects Boolean operands",
            })
            UnknownType
          }
        NullCoalesce =>
          if left == NullType {
            right
          } else if right == NullType || left == right {
            left
          } else {
            UnknownType
          }
        Is | As | Pipe => panic()
      }
    }
    ConditionalExpr(condition_expr, then_expr, else_expr) => {
      let condition = infer_expr_with_bindings(
        condition_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      if condition != BoolType {
        diagnostics.push(Diagnostic::{ message: "if condition expects Boolean" })
      }
      let then_type = infer_expr_with_bindings(
        then_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let else_type = infer_expr_with_bindings(
        else_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      if then_type == else_type {
        then_type
      } else if then_type == NullType {
        else_type
      } else if else_type == NullType {
        then_type
      } else {
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
fn infer_object_members(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[TypeMember] {
  let fields : Array[TypeMember] = []
  for field in members {
    let inferred = infer_expr_with_bindings(
      field.value,
      bindings,
      env,
      type_env,
      cache,
      stack,
      diagnostics,
      resolve_import,
    )
    fields.push({
      name: field.name,
      typ: apply_type_annotation(
        field.type_name,
        inferred,
        type_env,
        diagnostics,
      ),
    })
  }
  fields
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
fn relation_kind_name_for_typecheck(kind : ModuleRelationKind) -> String {
  match kind {
    ModuleAmends => "amends"
    ModuleExtends => "extends"
  }
}

///|
fn infer_module_relation(
  relation : ModuleRelation,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Array[TypeMember] {
  match resolve_import(relation.uri) {
    Some(TypeOk(ObjectType(members))) => members
    Some(TypeOk(ClassType(_, members))) => members
    Some(TypeOk(_)) => {
      diagnostics.push(Diagnostic::{
        message: "module \{relation_kind_name_for_typecheck(relation.kind)} expects Object",
      })
      []
    }
    Some(TypeError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      []
    }
    None => {
      diagnostics.push(Diagnostic::{
        message: "unresolved import \{relation.uri}",
      })
      []
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
  let type_env = collect_declared_types(program.declarations, diagnostics)
  let cache : Array[TypeBinding] = []
  let fields : Array[TypeMember] = []
  let bindings = all_program_bindings(program)
  infer_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    match
      resolve_binding_type(
        binding.name,
        bindings,
        env,
        type_env,
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
        bindings,
        env,
        type_env,
        cache,
        [],
        diagnostics,
        resolve_import,
      )
    None if program.module_relation is Some(relation) =>
      ObjectType(
        merge_type_members(
          infer_module_relation(relation, diagnostics, resolve_import),
          fields,
        ),
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
fn typecheck_parsed_with_imports(
  parsed : ParseResult,
  resolve_import : (String) -> TypecheckResult?,
) -> TypecheckResult {
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

///|
fn typecheck_source_with_imports(
  source : String,
  resolve_import : (String) -> TypecheckResult?,
) -> TypecheckResult {
  typecheck_parsed_with_imports(parse_source(source), resolve_import)
}
