///|
pub(all) enum Value {
  IntValue(Int)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  ObjectValue(Array[ValueMember])
  ListingValue(Array[Value])
  MappingValue(Array[ValueEntry])
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
  properties : Array[ClassProperty]
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
fn lookup_class_properties(
  env : Array[ClassBinding],
  name : String,
) -> Array[ClassProperty]? {
  let mut found : Array[ClassProperty]? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.properties)
    }
  }
  found
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
    CallExpr(callee, _) =>
      match callee {
        SafeMemberAccess(target_expr, _) =>
          match
            eval_expr_with_bindings(
              target_expr, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
            ) {
            Some(NullValue) => Some(NullValue)
            Some(_) => {
              diagnostics.push(Diagnostic::{
                message: "call expressions are parser-only",
              })
              None
            }
            None => None
          }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "call expressions are parser-only",
          })
          None
        }
      }
    LambdaExpr(_, _, _) => {
      diagnostics.push(Diagnostic::{
        message: "lambda expressions are parser-only",
      })
      None
    }
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
  match lookup_class_properties(class_env, type_name) {
    Some(properties) =>
      for property in properties {
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
    None => ()
  }
  eval_object_members(
    defaults, bindings, env, class_env, cache, stack, diagnostics, resolve_import,
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
          properties: class_decl.properties,
        })
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  classes
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
) -> Value? {
  let env : Array[ValueBinding] = []
  let class_env = collect_class_bindings(program.declarations)
  let cache : Array[ValueBinding] = []
  let members : Array[ValueMember] = []
  eval_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    match
      resolve_binding_value(
        binding.name,
        program.bindings,
        env,
        class_env,
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
