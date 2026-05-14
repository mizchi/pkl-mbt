///|
pub(all) enum Value {
  IntValue(Int)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  ObjectValue(Array[ValueMember])
  ListingValue(Array[Value])
  MappingValue(Array[ValueEntry])
  FunctionValue(Array[FunctionParameter], Expr, String?)
} derive(Eq, Debug)

///|
pub(all) struct ValueMember {
  name : String
  value : Value
} derive(Eq, Debug)

///|
pub(all) struct ValueEntry {
  key : Value
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
priv struct ClassBinding {
  name : String
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
}

///|
pub(all) struct ClassExport {
  name : String
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
} derive(Eq, Debug)

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
fn lookup_class_binding(
  env : Array[ClassBinding],
  name : String,
) -> ClassBinding? {
  let mut found : ClassBinding? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding)
    }
  }
  found
}

///|
fn lookup_function_decl(
  declarations : Array[FunctionDecl],
  name : String,
) -> FunctionDecl? {
  let mut found : FunctionDecl? = None
  for declaration in declarations {
    if declaration.name == name {
      found = Some(declaration)
    }
  }
  found
}

///|
fn lookup_class_method_with_stack(
  class_env : Array[ClassBinding],
  type_name : String,
  method_name : String,
  stack : Array[String],
) -> FunctionDecl? {
  if stack_contains_binding(stack, type_name) {
    return None
  }
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) =>
      match lookup_function_decl(class_binding.methods, method_name) {
        Some(function_decl) => Some(function_decl)
        None =>
          match class_binding.parent_name {
            Some(parent_name) =>
              lookup_class_method_with_stack(
                class_env,
                parent_name,
                method_name,
                push_binding_stack(stack, type_name),
              )
            None => None
          }
      }
    None => None
  }
}

///|
fn lookup_class_method(
  class_env : Array[ClassBinding],
  type_name : String,
  method_name : String,
) -> FunctionDecl? {
  lookup_class_method_with_stack(class_env, type_name, method_name, [])
}

///|
fn lookup_entry(entries : Array[ValueEntry], key : Value) -> Value? {
  let mut found : Value? = None
  for entry in entries {
    if entry.key == key {
      found = Some(entry.value)
    }
  }
  found
}

///|
fn merge_value_members(
  base : Array[ValueMember],
  overrides : Array[ValueMember],
) -> Array[ValueMember] {
  let merged : Array[ValueMember] = []
  for value_member in base {
    match lookup_member(overrides, value_member.name) {
      Some(value) => merged.push({ name: value_member.name, value })
      None => merged.push(value_member)
    }
  }
  for value_member in overrides {
    if lookup_member(base, value_member.name) is None {
      merged.push(value_member)
    }
  }
  merged
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
fn all_eval_bindings(program : Program) -> Array[Binding] {
  let bindings : Array[Binding] = []
  for declaration in program.declarations {
    match declaration {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) =>
            bindings.push({
              name: function_decl.name,
              type_name: None,
              value: LambdaExpr(
                function_decl.parameters,
                body,
                function_decl.return_type_name,
              ),
              exported: false,
            })
          None => ()
        }
      ClassDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  for binding in program.bindings {
    bindings.push(binding)
  }
  bindings
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
fn typed_object_class_name_for_expr(
  expr : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> String? {
  match expr {
    TypedObjectLiteral(type_name, _) => Some(type_name)
    AmendExpr(base, _) | NonNullExpr(base) =>
      typed_object_class_name_for_expr(base, bindings, stack)
    Identifier(name) =>
      if stack_contains_binding(stack, name) {
        None
      } else {
        match find_binding(bindings, name) {
          Some(binding) =>
            typed_object_class_name_for_expr(
              binding.value,
              bindings,
              push_binding_stack(stack, name),
            )
          None => None
        }
      }
    _ => None
  }
}

///|
fn copy_value_bindings(bindings : Array[ValueBinding]) -> Array[ValueBinding] {
  let copied : Array[ValueBinding] = []
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn int_pow(base : Int, exponent : Int) -> Int? {
  if exponent < 0 {
    return None
  }
  let mut result = 1
  let mut i = 0
  while i < exponent {
    result = result * base
    i += 1
  }
  Some(result)
}

///|
fn resolve_binding_value(
  name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
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
                class_env,
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
fn push_receiver_method_bindings(
  method_cache : Array[ValueBinding],
  receiver_members : Array[ValueMember],
) -> Unit {
  for value_member in receiver_members {
    method_cache.push({ name: value_member.name, value: value_member.value })
  }
  method_cache.push({ name: "this", value: ObjectValue(receiver_members) })
}

///|
fn eval_lambda_application(
  label : String,
  parameters : Array[FunctionParameter],
  body : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  if parameters.length() != arguments.length() {
    diagnostics.push(Diagnostic::{
      message: "\{label} expects \{parameters.length()} arguments, got \{arguments.length()}",
    })
    return None
  }
  let argument_values : Array[Value] = []
  let mut arguments_ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
      ) {
      Some(value) => argument_values.push(value)
      None => arguments_ok = false
    }
  }
  if !arguments_ok {
    return None
  }
  let call_cache = copy_value_bindings(cache)
  for i = 0; i < parameters.length(); i = i + 1 {
    call_cache.push({ name: parameters[i].name, value: argument_values[i] })
  }
  eval_expr_with_bindings(
    body, bindings, env, class_env, call_cache, stack, diagnostics, resolve_import,
  )
}

///|
fn eval_class_method_call(
  target_expr : Expr,
  method_name : String,
  arguments : Array[Expr],
  null_safe : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_expr_with_bindings(
      target_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
    ) {
    Some(NullValue) =>
      if null_safe {
        Some(NullValue)
      } else {
        diagnostics.push(Diagnostic::{ message: "method call expects Object" })
        None
      }
    Some(ObjectValue(receiver_members)) =>
      match typed_object_class_name_for_expr(target_expr, bindings, []) {
        Some(type_name) =>
          match lookup_class_method(class_env, type_name, method_name) {
            Some(function_decl) => {
              if function_decl.parameters.length() != arguments.length() {
                diagnostics.push(Diagnostic::{
                  message: "method \{method_name} expects \{function_decl.parameters.length()} arguments, got \{arguments.length()}",
                })
                return None
              }
              let argument_values : Array[Value] = []
              let mut arguments_ok = true
              for argument in arguments {
                match
                  eval_expr_with_bindings(
                    argument, bindings, env, class_env, cache, stack, diagnostics,
                    resolve_import,
                  ) {
                  Some(value) => argument_values.push(value)
                  None => arguments_ok = false
                }
              }
              if !arguments_ok {
                return None
              }
              match function_decl.body {
                Some(body) => {
                  let method_cache = copy_value_bindings(cache)
                  push_receiver_method_bindings(method_cache, receiver_members)
                  for i = 0; i < function_decl.parameters.length(); i = i + 1 {
                    method_cache.push({
                      name: function_decl.parameters[i].name,
                      value: argument_values[i],
                    })
                  }
                  eval_expr_with_bindings(
                    body, bindings, env, class_env, method_cache, stack, diagnostics,
                    resolve_import,
                  )
                }
                None => {
                  diagnostics.push(Diagnostic::{
                    message: "method \{method_name} has no body",
                  })
                  None
                }
              }
            }
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{method_name}",
              })
              None
            }
          }
        None => {
          diagnostics.push(Diagnostic::{
            message: "call expressions are parser-only",
          })
          None
        }
      }
    Some(_) => {
      diagnostics.push(Diagnostic::{ message: "method call expects Object" })
      None
    }
    None => None
  }
}

///|
fn callee_label(callee : Expr) -> String {
  match callee {
    Identifier(name) => "function \{name}"
    _ => "function"
  }
}

///|
fn class_method_call_available(
  target_expr : Expr,
  method_name : String,
  bindings : Array[Binding],
  class_env : Array[ClassBinding],
) -> Bool {
  match typed_object_class_name_for_expr(target_expr, bindings, []) {
    Some(type_name) =>
      lookup_class_method(class_env, type_name, method_name) is Some(_)
    None => false
  }
}

///|
fn eval_callable_call(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_expr_with_bindings(
      callee, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
    ) {
    Some(FunctionValue(parameters, body, _)) =>
      eval_lambda_application(
        callee_label(callee),
        parameters,
        body,
        arguments,
        bindings,
        env,
        class_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
    Some(NullValue) =>
      match callee {
        SafeMemberAccess(_, _) => Some(NullValue)
        _ => {
          diagnostics.push(Diagnostic::{ message: "call expects Function" })
          None
        }
      }
    Some(_) => {
      diagnostics.push(Diagnostic::{ message: "call expects Function" })
      None
    }
    None => None
  }
}

///|
fn eval_expr_with_bindings(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
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
    ObjectLiteral(members) =>
      Some(
        ObjectValue(
          eval_object_members(
            members, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          ),
        ),
      )
    TypedObjectLiteral(type_name, members) =>
      Some(
        ObjectValue(
          merge_value_members(
            eval_class_default_members(
              type_name, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ),
            eval_object_members(
              members, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ),
          ),
        ),
      )
    ListingLiteral(elements) => {
      let values : Array[Value] = []
      for element in elements {
        match
          eval_expr_with_bindings(
            element, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          ) {
          Some(value) => values.push(value)
          None => ()
        }
      }
      Some(ListingValue(values))
    }
    MappingLiteral(entries) => {
      let values : Array[ValueEntry] = []
      for entry in entries {
        let key = eval_expr_with_bindings(
          entry.key,
          bindings,
          env,
          class_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        let value = eval_expr_with_bindings(
          entry.value,
          bindings,
          env,
          class_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
        match (key, value) {
          (Some(k), Some(v)) => values.push({ key: k, value: v })
          _ => ()
        }
      }
      Some(MappingValue(values))
    }
    MemberAccess(target_expr, member_name) =>
      match
        eval_expr_with_bindings(
          target_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
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
    SafeMemberAccess(target_expr, member_name) =>
      match
        eval_expr_with_bindings(
          target_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(NullValue) => Some(NullValue)
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
            message: "safe member access expects Object",
          })
          None
        }
        None => None
      }
    SubscriptAccess(target_expr, key_expr) => {
      let target = eval_expr_with_bindings(
        target_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
      )
      let key = eval_expr_with_bindings(
        key_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
      )
      match (target, key) {
        (Some(ListingValue(elements)), Some(IntValue(index))) =>
          if index >= 0 && index < elements.length() {
            Some(elements[index])
          } else {
            diagnostics.push(Diagnostic::{
              message: "listing index out of bounds \{index}",
            })
            None
          }
        (Some(ListingValue(_)), Some(_)) => {
          diagnostics.push(Diagnostic::{ message: "listing index expects Int" })
          None
        }
        (Some(MappingValue(entries)), Some(key_value)) =>
          match lookup_entry(entries, key_value) {
            Some(value) => Some(value)
            None => {
              diagnostics.push(Diagnostic::{ message: "unknown mapping key" })
              None
            }
          }
        (Some(_), Some(_)) => {
          diagnostics.push(Diagnostic::{
            message: "subscript access expects Listing or Mapping",
          })
          None
        }
        _ => None
      }
    }
    AmendExpr(base_expr, members) =>
      match
        eval_expr_with_bindings(
          base_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(ObjectValue(base_members)) =>
          Some(
            ObjectValue(
              merge_value_members(
                base_members,
                eval_object_members(
                  members, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
                ),
              ),
            ),
          )
        Some(_) => {
          diagnostics.push(Diagnostic::{
            message: "object amendment expects Object",
          })
          None
        }
        None => None
      }
    Identifier(name) =>
      match
        resolve_binding_value(
          name, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(value) => Some(value)
        None => {
          diagnostics.push(Diagnostic::{ message: "unbound identifier \{name}" })
          None
        }
      }
    CallExpr(callee, arguments) =>
      match callee {
        MemberAccess(target_expr, method_name) =>
          if class_method_call_available(
              target_expr, method_name, bindings, class_env,
            ) {
            eval_class_method_call(
              target_expr, method_name, arguments, false, bindings, env, class_env,
              cache, stack, diagnostics, resolve_import,
            )
          } else {
            eval_callable_call(
              callee, arguments, bindings, env, class_env, cache, stack, diagnostics,
              resolve_import,
            )
          }
        SafeMemberAccess(target_expr, method_name) =>
          if class_method_call_available(
              target_expr, method_name, bindings, class_env,
            ) {
            eval_class_method_call(
              target_expr, method_name, arguments, true, bindings, env, class_env,
              cache, stack, diagnostics, resolve_import,
            )
          } else {
            eval_callable_call(
              callee, arguments, bindings, env, class_env, cache, stack, diagnostics,
              resolve_import,
            )
          }
        _ =>
          eval_callable_call(
            callee, arguments, bindings, env, class_env, cache, stack, diagnostics,
            resolve_import,
          )
      }
    LambdaExpr(parameters, body, return_type_name) =>
      Some(FunctionValue(parameters, body, return_type_name))
    NonNullExpr(inner_expr) =>
      match
        eval_expr_with_bindings(
          inner_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(NullValue) => {
          diagnostics.push(Diagnostic::{ message: "non-null assertion failed" })
          None
        }
        Some(value) => Some(value)
        None => None
      }
    UnaryExpr(op, inner_expr) => {
      let inner = eval_expr_with_bindings(
        inner_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
      )
      match (op, inner) {
        (Negate, Some(IntValue(value))) => Some(IntValue(0 - value))
        (Not, Some(BoolValue(value))) => Some(BoolValue(!value))
        (Negate, Some(_)) => {
          diagnostics.push(Diagnostic::{
            message: "operator - expects Int operand",
          })
          None
        }
        (Not, Some(_)) => {
          diagnostics.push(Diagnostic::{
            message: "operator ! expects Boolean operand",
          })
          None
        }
        (_, None) => None
      }
    }
    BinaryExpr(op, left_expr, right_expr) => {
      match op {
        And => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          )
          match left {
            Some(BoolValue(false)) => return Some(BoolValue(false))
            Some(BoolValue(true)) => ()
            Some(_) => {
              diagnostics.push(Diagnostic::{
                message: "operator && expects Boolean operands",
              })
              return None
            }
            None => return None
          }
          match
            eval_expr_with_bindings(
              right_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ) {
            Some(BoolValue(value)) => return Some(BoolValue(value))
            Some(_) => {
              diagnostics.push(Diagnostic::{
                message: "operator && expects Boolean operands",
              })
              return None
            }
            None => return None
          }
        }
        Or => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          )
          match left {
            Some(BoolValue(true)) => return Some(BoolValue(true))
            Some(BoolValue(false)) => ()
            Some(_) => {
              diagnostics.push(Diagnostic::{
                message: "operator || expects Boolean operands",
              })
              return None
            }
            None => return None
          }
          match
            eval_expr_with_bindings(
              right_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ) {
            Some(BoolValue(value)) => return Some(BoolValue(value))
            Some(_) => {
              diagnostics.push(Diagnostic::{
                message: "operator || expects Boolean operands",
              })
              return None
            }
            None => return None
          }
        }
        NullCoalesce => {
          let left = eval_expr_with_bindings(
            left_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          )
          match left {
            Some(NullValue) =>
              return eval_expr_with_bindings(
                right_expr, bindings, env, class_env, cache, stack, diagnostics,
                resolve_import,
              )
            Some(value) => return Some(value)
            None => return None
          }
        }
        Is | As | Pipe => {
          diagnostics.push(Diagnostic::{
            message: "operator \{operator_name(op)} is parser-only",
          })
          return None
        }
        _ => ()
      }
      let left = eval_expr_with_bindings(
        left_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
      )
      let right = eval_expr_with_bindings(
        right_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
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
            IntDivide =>
              if b == 0 {
                diagnostics.push(Diagnostic::{ message: "division by zero" })
                None
              } else {
                Some(IntValue(a / b))
              }
            Modulo =>
              if b == 0 {
                diagnostics.push(Diagnostic::{ message: "division by zero" })
                None
              } else {
                Some(IntValue(a % b))
              }
            Power =>
              match int_pow(a, b) {
                Some(value) => Some(IntValue(value))
                None => {
                  diagnostics.push(Diagnostic::{
                    message: "operator ** expects non-negative exponent",
                  })
                  None
                }
              }
            LessThan => Some(BoolValue(a < b))
            LessOrEqual => Some(BoolValue(a <= b))
            GreaterThan => Some(BoolValue(a > b))
            GreaterOrEqual => Some(BoolValue(a >= b))
            Equal => Some(BoolValue(a == b))
            NotEqual => Some(BoolValue(a != b))
            And | Or | NullCoalesce | Is | As | Pipe => panic()
          }
        (Some(a), Some(b)) if op == Equal => Some(BoolValue(a == b))
        (Some(a), Some(b)) if op == NotEqual => Some(BoolValue(a != b))
        (Some(_), Some(_)) => {
          let message = match op {
            Add
            | Subtract
            | Multiply
            | Divide
            | IntDivide
            | Modulo
            | Power
            | LessThan
            | LessOrEqual
            | GreaterThan
            | GreaterOrEqual =>
              "operator \{operator_name(op)} expects Int operands"
            _ => "operator \{operator_name(op)} expects compatible operands"
          }
          diagnostics.push(Diagnostic::{ message, })
          None
        }
        _ => None
      }
    }
    ConditionalExpr(condition_expr, then_expr, else_expr) =>
      match
        eval_expr_with_bindings(
          condition_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
        ) {
        Some(BoolValue(true)) =>
          eval_expr_with_bindings(
            then_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          )
        Some(BoolValue(false)) =>
          eval_expr_with_bindings(
            else_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
          )
        Some(_) => {
          diagnostics.push(Diagnostic::{
            message: "if condition expects Boolean",
          })
          None
        }
        None => None
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
fn eval_object_members(
  members : Array[ObjectMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  let values : Array[ValueMember] = []
  for field in members {
    match
      eval_expr_with_bindings(
        field.value,
        bindings,
        env,
        class_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      ) {
      Some(value) => values.push({ name: field.name, value })
      None => ()
    }
  }
  values
}

///|
fn eval_class_default_members(
  type_name : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  let defaults : Array[ObjectMember] = []
  let base_values : Array[ValueMember] = []
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent_name) =>
          for
            value_member in eval_class_default_members(
              parent_name, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ) {
            base_values.push(value_member)
          }
        None => ()
      }
      for property in class_binding.properties {
        match property.value {
          Some(value) =>
            defaults.push({
              name: property.name,
              type_name: property.type_name,
              value,
            })
          None => ()
        }
      }
    }
    None => ()
  }
  merge_value_members(
    base_values,
    eval_object_members(
      defaults, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
    ),
  )
}

///|
fn collect_class_bindings(
  declarations : Array[Declaration],
) -> Array[ClassBinding] {
  let classes : Array[ClassBinding] = []
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        classes.push({
          name: class_decl.name,
          parent_name: class_decl.parent_name,
          properties: class_decl.properties,
          methods: class_decl.methods,
        })
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  classes
}

///|
fn imported_class_parent_name(
  import_name : String,
  parent_name : String,
) -> String {
  if parent_name.find(".") is Some(_) {
    parent_name
  } else {
    "\{import_name}.\{parent_name}"
  }
}

///|
fn add_imported_class_bindings(
  imports : Array[ImportDecl],
  class_env : Array[ClassBinding],
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> Unit {
  for decl in imports {
    match resolve_import_classes(decl.uri) {
      Some(exports) =>
        for class_export in exports {
          let parent_name = match class_export.parent_name {
            Some(parent) =>
              Some(imported_class_parent_name(decl.import_name, parent))
            None => None
          }
          class_env.push({
            name: "\{decl.import_name}.\{class_export.name}",
            parent_name,
            properties: class_export.properties,
            methods: class_export.methods,
          })
        }
      None => ()
    }
  }
}

///|
fn class_exports_from_parse_result(parsed : ParseResult) -> Array[ClassExport] {
  let exports : Array[ClassExport] = []
  for declaration in parsed.program.declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        exports.push({
          name: class_decl.name,
          parent_name: class_decl.parent_name,
          properties: class_decl.properties,
          methods: class_decl.methods,
        })
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  exports
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
fn eval_module_relation(
  relation : ModuleRelation,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  match resolve_import(relation.uri) {
    Some(EvalOk(ObjectValue(members))) => members
    Some(EvalOk(_)) => {
      diagnostics.push(Diagnostic::{
        message: "module \{relation_kind_name(relation.kind)} expects Object",
      })
      []
    }
    Some(EvalError(errors)) => {
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
fn eval_program(
  program : Program,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> Value? {
  let env : Array[ValueBinding] = []
  let class_env = collect_class_bindings(program.declarations)
  let cache : Array[ValueBinding] = []
  let members : Array[ValueMember] = []
  let bindings = all_eval_bindings(program)
  eval_imports(program.imports, env, diagnostics, resolve_import)
  add_imported_class_bindings(
    program.imports,
    class_env,
    resolve_import_classes,
  )
  for binding in program.bindings {
    if binding.exported {
      match
        resolve_binding_value(
          binding.name,
          bindings,
          env,
          class_env,
          cache,
          [],
          diagnostics,
          resolve_import,
        ) {
        Some(value) => members.push({ name: binding.name, value })
        None => ()
      }
    }
  }
  match program.body {
    Some(expr) =>
      eval_expr_with_bindings(
        expr,
        bindings,
        env,
        class_env,
        cache,
        [],
        diagnostics,
        resolve_import,
      )
    None if program.module_relation is Some(relation) =>
      Some(
        ObjectValue(
          merge_value_members(
            eval_module_relation(relation, diagnostics, resolve_import),
            members,
          ),
        ),
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
    IntDivide => "~/"
    Modulo => "%"
    Power => "**"
    Equal => "=="
    NotEqual => "!="
    LessThan => "<"
    LessOrEqual => "<="
    GreaterThan => ">"
    GreaterOrEqual => ">="
    And => "&&"
    Or => "||"
    NullCoalesce => "??"
    Is => "is"
    As => "as"
    Pipe => "|>"
  }
}

///|
fn relation_kind_name(kind : ModuleRelationKind) -> String {
  match kind {
    ModuleAmends => "amends"
    ModuleExtends => "extends"
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
    ListingValue(elements) => render_listing_elements(elements)
    MappingValue(entries) => render_mapping_entries(entries)
    FunctionValue(_, _, _) => "<function>"
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
fn render_listing_elements(elements : Array[Value]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("new Listing {")
  for element in elements {
    buf.write_string("\n  ")
    buf.write_string(render_value(element))
  }
  if elements.length() > 0 {
    buf.write_string("\n")
  }
  buf.write_string("}")
  buf.to_string()
}

///|
fn render_mapping_entries(entries : Array[ValueEntry]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("new Mapping {")
  for entry in entries {
    buf.write_string("\n  [")
    buf.write_string(render_value(entry.key))
    buf.write_string("] = ")
    buf.write_string(render_value(entry.value))
  }
  if entries.length() > 0 {
    buf.write_string("\n")
  }
  buf.write_string("}")
  buf.to_string()
}

///|
fn eval_source_with_imports(
  source : String,
  resolve_import : (String) -> EvalResult?,
) -> EvalResult {
  eval_source_with_import_details(source, resolve_import, fn(_) { None })
}

///|
fn eval_source_with_import_details(
  source : String,
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> EvalResult {
  let parsed = parse_source(source)
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return EvalError(diagnostics)
  }
  match
    eval_program(
      parsed.program,
      diagnostics,
      resolve_import,
      resolve_import_classes,
    ) {
    Some(value) =>
      if diagnostics.length() == 0 {
        EvalOk(value)
      } else {
        EvalError(diagnostics)
      }
    None => EvalError(diagnostics)
  }
}
