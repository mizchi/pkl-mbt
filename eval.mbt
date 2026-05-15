///|
pub(all) enum Value {
  IntValue(Int)
  BoolValue(Bool)
  StringValue(String)
  NullValue
  ObjectValue(Array[ValueMember])
  ListingValue(Array[Value])
  MappingValue(Array[ValueEntry])
  FunctionValue(Array[FunctionParameter], Expr, String?, Array[ValueBinding])
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
pub(all) struct ValueBinding {
  name : String
  value : Value
} derive(Eq, Debug)

///|
priv struct ClassBinding {
  name : String
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
}

///|
priv struct EvalTypeAliasBinding {
  name : String
  target : String
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
fn lookup_eval_type_alias(
  env : Array[EvalTypeAliasBinding],
  name : String,
) -> String? {
  let mut found : String? = None
  for binding in env {
    if binding.name == name {
      found = Some(binding.target)
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
fn eval_type_alias_bindings(
  declarations : Array[Declaration],
) -> Array[EvalTypeAliasBinding] {
  let aliases : Array[EvalTypeAliasBinding] = []
  for declaration in declarations {
    match declaration {
      TypeAliasDeclaration(type_alias) =>
        aliases.push({ name: type_alias.name, target: type_alias.target })
      ClassDeclaration(_) | FunctionDeclaration(_) => ()
    }
  }
  aliases
}

///|
fn eval_constrained_type_source_name_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  if pkl_constrained_type_annotation_has_supported_constraint(name) {
    return Some(name)
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_constrained_type_source_name_with_depth(target, aliases, depth + 1)
    None => None
  }
}

///|
fn eval_resolved_type_alias_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String {
  if depth > 8 {
    return name
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_resolved_type_alias_with_depth(target, aliases, depth + 1)
    None => name
  }
}

///|
fn eval_resolved_type_alias(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String {
  eval_resolved_type_alias_with_depth(name, aliases, 0)
}

///|
fn eval_constrained_type_source_name(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String? {
  eval_constrained_type_source_name_with_depth(name, aliases, 0)
}

///|
fn eval_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match type_name {
    Some(display_name) =>
      match eval_constrained_type_source_name(display_name, aliases) {
        Some(source_name) =>
          match
            pkl_constrained_type_annotation_value_rejection_message_from_source(
              display_name, source_name, value,
            ) {
            Some(message) => {
              diagnostics.push(Diagnostic::{ message, })
              false
            }
            None => true
          }
        None => true
      }
    None => true
  }
}

///|
fn eval_user_defined_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match
    pkl_user_defined_constrained_type_annotation_value_rejection_message(
      type_name, value, declarations,
    ) {
    Some(message) => {
      diagnostics.push(Diagnostic::{ message, })
      false
    }
    None => true
  }
}

///|
fn eval_lookup_class_decl(
  declarations : Array[Declaration],
  name : String,
) -> ClassDecl? {
  let mut found : ClassDecl? = None
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        if class_decl.name == name {
          found = Some(class_decl)
        }
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  found
}

///|
fn eval_class_property_annotation_with_depth(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut found = false
      let mut annotation : String? = None
      for property in class_decl.properties {
        if property.name == property_name {
          found = true
          annotation = property.type_name
        }
      }
      if found {
        annotation
      } else {
        match class_decl.parent_name {
          Some(parent_name) =>
            eval_class_property_annotation_with_depth(
              declarations,
              parent_name,
              property_name,
              depth + 1,
            )
          None => None
        }
      }
    }
    None => None
  }
}

///|
fn eval_class_property_annotation(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
) -> String? {
  eval_class_property_annotation_with_depth(
    declarations, class_name, property_name, 0,
  )
}

///|
fn eval_class_property_constraint_value_rejection_message(
  class_name : String,
  property_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      let display_name = "\{class_name} member \{property_name}"
      match
        pkl_constrained_type_annotation_value_rejection_message_from_source(
          display_name, source_name, value,
        ) {
        Some(message) => Some(message)
        None =>
          pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
            display_name, source_name, value, declarations,
          )
      }
    }
    None => None
  }
}

///|
fn eval_object_member_expr_is_provided(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  for field in members {
    if field.name == name {
      return true
    }
  }
  false
}

///|
fn eval_class_property_default_constraints_are_valid_with_depth(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  depth : Int,
) -> Bool {
  if depth > 8 {
    return true
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut ok = true
      match class_decl.parent_name {
        Some(parent_name) =>
          if !eval_class_property_default_constraints_are_valid_with_depth(
              parent_name,
              provided_members,
              values,
              declarations,
              diagnostics,
              depth + 1,
            ) {
            ok = false
          }
        None => ()
      }
      for property in class_decl.properties {
        if property.value is Some(_) &&
          !eval_object_member_expr_is_provided(provided_members, property.name) {
          match lookup_member(values, property.name) {
            Some(default_value) =>
              match
                eval_class_property_constraint_value_rejection_message(
                  class_name,
                  property.name,
                  default_value,
                  declarations,
                ) {
                Some(message) => {
                  diagnostics.push(Diagnostic::{ message, })
                  ok = false
                }
                None => ()
              }
            None => ()
          }
        }
      }
      ok
    }
    None => true
  }
}

///|
fn eval_class_property_default_constraints_are_valid(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  eval_class_property_default_constraints_are_valid_with_depth(
    class_name, provided_members, values, declarations, diagnostics, 0,
  )
}

///|
fn eval_expr_class_property_constraints_are_valid(
  expr : Expr,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (TypedObjectLiteral(class_name, members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) => {
            match
              eval_class_property_constraint_value_rejection_message(
                class_name,
                field.name,
                member_value,
                declarations,
              ) {
              Some(message) => {
                diagnostics.push(Diagnostic::{ message, })
                ok = false
              }
              None => ()
            }
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          }
          None => ()
        }
      }
      if !eval_class_property_default_constraints_are_valid(
          class_name, members, values, declarations, diagnostics,
        ) {
        ok = false
      }
      ok
    }
    (ObjectLiteral(members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) =>
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          None => ()
        }
      }
      ok
    }
    _ => true
  }
}

///|
fn eval_object_member_alias_constraints_are_valid(
  members : Array[ObjectMember],
  values : Array[ValueMember],
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  let mut ok = true
  for object_member in members {
    match lookup_member(values, object_member.name) {
      Some(value) => {
        if !eval_constrained_type_annotation_value_is_valid(
            object_member.type_name,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
        if !eval_expr_alias_constraints_are_valid(
            object_member.value,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
      }
      None => ()
    }
  }
  ok
}

///|
fn eval_expr_alias_constraints_are_valid(
  expr : Expr,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (ObjectLiteral(members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    (TypedObjectLiteral(_, members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    _ => true
  }
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
fn capture_value_bindings(
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Array[ValueBinding] {
  let captured = copy_value_bindings(env)
  for binding in cache {
    captured.push(binding)
  }
  captured
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
  declarations : Array[Declaration],
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
                declarations,
                diagnostics,
                resolve_import,
              ) {
              Some(value) =>
                if pkl_constrained_type_annotation_value_is_valid(
                    binding.type_name,
                    value,
                    diagnostics,
                  ) {
                  cache.push({ name, value })
                  Some(value)
                } else {
                  None
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
fn eval_value_type_name(value : Value) -> String {
  match value {
    IntValue(_) => "Int"
    BoolValue(_) => "Boolean"
    StringValue(_) => "String"
    NullValue => "Null"
    ObjectValue(_) => "Object"
    ListingValue(_) => "Listing"
    MappingValue(_) => "Mapping"
    FunctionValue(_, _, _, _) => "Function"
  }
}

///|
fn eval_value_accepts_type_annotation(
  type_name : String,
  value : Value,
) -> Bool {
  match pkl_constrained_type_base_name(type_name) {
    Some(base_name) =>
      return eval_value_accepts_type_annotation(base_name, value)
    None => ()
  }
  if type_name.has_suffix("?") {
    if value is NullValue {
      return true
    }
    let inner_name = String::unsafe_substring(
      type_name,
      start=0,
      end=type_name.length() - 1,
    )
    return eval_value_accepts_type_annotation(inner_name, value)
  }
  match (type_name, value) {
    ("Int", IntValue(_)) => true
    ("String", StringValue(_)) => true
    ("Boolean", BoolValue(_)) | ("Bool", BoolValue(_)) => true
    ("Null", NullValue) => true
    ("Object", ObjectValue(_)) => true
    ("Listing", ListingValue(_)) => true
    ("Mapping", MappingValue(_)) => true
    ("Function", FunctionValue(_, _, _, _)) => true
    _ => false
  }
}

///|
fn eval_callable_argument_rejection_message(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    pkl_constrained_type_annotation_value_rejection_message(type_name, value) {
    Some(message) => Some(message)
    None =>
      pkl_user_defined_constrained_type_annotation_value_rejection_message(
        type_name, value, declarations,
      )
  }
}

///|
fn eval_callable_return_rejection_message(
  label : String,
  return_type_name : String?,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match return_type_name {
    Some(type_name) => {
      let aliases = eval_type_alias_bindings(declarations)
      let resolved_type_name = eval_resolved_type_alias(type_name, aliases)
      if !eval_value_accepts_type_annotation(resolved_type_name, value) {
        Some(
          "\{label} return type annotation \{type_name} does not accept \{eval_value_type_name(value)}",
        )
      } else {
        match
          pkl_constrained_type_annotation_value_rejection_message_from_source(
            type_name, resolved_type_name, value,
          ) {
          Some(message) => Some("\{label} return \{message}")
          None =>
            match
              pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
                type_name, resolved_type_name, value, declarations,
              ) {
              Some(message) => Some("\{label} return \{message}")
              None => None
            }
        }
      }
    }
    None => None
  }
}

///|
fn eval_callable_return_value(
  label : String,
  return_type_name : String?,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Value? {
  match
    eval_callable_return_rejection_message(
      label, return_type_name, value, declarations,
    ) {
    Some(message) => {
      diagnostics.push(Diagnostic::{ message, })
      None
    }
    None => Some(value)
  }
}

///|
fn eval_lambda_application(
  label : String,
  parameters : Array[FunctionParameter],
  body : Expr,
  return_type_name : String?,
  captured_env : Array[ValueBinding],
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
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
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(value) => argument_values.push(value)
      None => arguments_ok = false
    }
  }
  if !arguments_ok {
    return None
  }
  let call_cache = copy_value_bindings(captured_env)
  for i = 0; i < parameters.length(); i = i + 1 {
    match
      eval_callable_argument_rejection_message(
        parameters[i].type_name,
        argument_values[i],
        declarations,
      ) {
      Some(message) => {
        diagnostics.push(Diagnostic::{
          message: "\{label} argument \{i + 1} \{message}",
        })
        return None
      }
      None => ()
    }
    call_cache.push({ name: parameters[i].name, value: argument_values[i] })
  }
  match body {
    LambdaExpr(lambda_parameters, lambda_body, lambda_return_type_name) =>
      eval_callable_return_value(
        label,
        return_type_name,
        FunctionValue(
          lambda_parameters,
          lambda_body,
          lambda_return_type_name,
          copy_value_bindings(call_cache),
        ),
        declarations,
        diagnostics,
      )
    _ =>
      match
        eval_expr_with_bindings(
          body, bindings, env, class_env, call_cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, declarations, diagnostics,
          )
        None => None
      }
  }
}

///|
/// Apply a `FunctionValue` to an array of already-evaluated `Value`
/// arguments. Mirrors `eval_lambda_application` but accepts values instead
/// of expressions so the stdlib builtins (Listing.map / .filter / .fold)
/// can invoke user callbacks per element.
fn apply_function_value(
  label : String,
  fn_value : Value,
  args : Array[Value],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  _cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match fn_value {
    FunctionValue(parameters, body, return_type_name, captured_env) => {
      if parameters.length() != args.length() {
        diagnostics.push(Diagnostic::{
          message: "\{label} expects \{parameters.length()} arguments, got \{args.length()}",
        })
        return None
      }
      let call_cache = copy_value_bindings(captured_env)
      for i = 0; i < parameters.length(); i = i + 1 {
        match
          eval_callable_argument_rejection_message(
            parameters[i].type_name,
            args[i],
            declarations,
          ) {
          Some(message) => {
            diagnostics.push(Diagnostic::{
              message: "\{label} argument \{i + 1} \{message}",
            })
            return None
          }
          None => ()
        }
        call_cache.push({ name: parameters[i].name, value: args[i] })
      }
      match
        eval_expr_with_bindings(
          body, bindings, env, class_env, call_cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          eval_callable_return_value(
            label, return_type_name, value, declarations, diagnostics,
          )
        None => None
      }
    }
    _ => {
      diagnostics.push(Diagnostic::{ message: "\{label} expects Function" })
      None
    }
  }
}

///|
fn is_listing_property_name(name : String) -> Bool {
  match name {
    "length" | "isEmpty" | "first" | "last" | "distinct" => true
    _ => false
  }
}

///|
fn is_listing_method_name(name : String) -> Bool {
  match name {
    "contains"
    | "fold"
    | "map"
    | "filter"
    | "take"
    | "drop"
    | "join"
    | "reverse" => true
    _ => false
  }
}

///|
fn is_mapping_property_name(name : String) -> Bool {
  match name {
    "length" | "isEmpty" | "keys" | "values" => true
    _ => false
  }
}

///|
fn is_mapping_method_name(name : String) -> Bool {
  match name {
    "containsKey" | "getOrNull" | "fold" => true
    _ => false
  }
}

///|
fn is_string_property_name(name : String) -> Bool {
  match name {
    "length" | "isEmpty" => true
    _ => false
  }
}

///|
fn is_string_method_name(name : String) -> Bool {
  match name {
    "toUpperCase"
    | "toLowerCase"
    | "contains"
    | "startsWith"
    | "endsWith"
    | "indexOf"
    | "replaceAll"
    | "replaceFirst"
    | "take"
    | "drop"
    | "split"
    | "padStart"
    | "padEnd" => true
    _ => false
  }
}

///|
fn is_int_property_name(name : String) -> Bool {
  match name {
    "abs" | "isEven" | "isOdd" => true
    _ => false
  }
}

///|
fn is_int_method_name(name : String) -> Bool {
  match name {
    "toString" | "toChar" => true
    _ => false
  }
}

///|
fn contains_entry_key(entries : Array[ValueEntry], key : Value) -> Bool {
  for entry in entries {
    if entry.key == key {
      return true
    }
  }
  false
}

///|
fn contains_value(xs : Array[Value], v : Value) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

///|
fn value_to_string_for_join(v : Value) -> String {
  match v {
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    StringValue(s) => s
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(v, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn eval_listing_property(
  elements : Array[Value],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(elements.length()))
    "isEmpty" => Some(BoolValue(elements.length() == 0))
    "first" =>
      if elements.length() == 0 {
        diagnostics.push(Diagnostic::{
          message: "Listing.first on empty Listing",
        })
        None
      } else {
        Some(elements[0])
      }
    "last" =>
      if elements.length() == 0 {
        diagnostics.push(Diagnostic::{
          message: "Listing.last on empty Listing",
        })
        None
      } else {
        Some(elements[elements.length() - 1])
      }
    "distinct" => {
      let seen : Array[Value] = []
      for v in elements {
        if !contains_value(seen, v) {
          seen.push(v)
        }
      }
      Some(ListingValue(seen))
    }
    _ => None
  }
}

///|
fn eval_listing_method(
  elements : Array[Value],
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "contains" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.contains expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      Some(BoolValue(contains_value(elements, arg_values[0])))
    }
    "reverse" => {
      if arg_values.length() != 0 {
        diagnostics.push(Diagnostic::{
          message: "Listing.reverse expects 0 arguments, got \{arg_values.length()}",
        })
        return None
      }
      let reversed : Array[Value] = []
      let mut i = elements.length() - 1
      while i >= 0 {
        reversed.push(elements[i])
        i = i - 1
      }
      Some(ListingValue(reversed))
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.take expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
          }
          let result : Array[Value] = []
          for i = 0; i < n; i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "Listing.take expects Int argument",
          })
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.drop expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
          }
          let result : Array[Value] = []
          for i = n; i < elements.length(); i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "Listing.drop expects Int argument",
          })
          None
        }
      }
    }
    "join" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.join expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match arg_values[0] {
        StringValue(sep) => {
          let buf = StringBuilder::new()
          for i = 0; i < elements.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(sep)
            }
            buf.write_string(value_to_string_for_join(elements[i]))
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "Listing.join expects String separator",
          })
          None
        }
      }
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.map expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.map callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => result.push(v)
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Listing.filter expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.filter predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(element)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(Diagnostic::{
              message: "Listing.filter predicate must return Boolean",
            })
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "Listing.fold expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for element in elements {
        match
          apply_function_value(
            "Listing.fold combine",
            callback,
            [acc, element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    _ => None
  }
}

///|
fn eval_mapping_property(
  entries : Array[ValueEntry],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(entries.length()))
    "isEmpty" => Some(BoolValue(entries.length() == 0))
    "keys" => {
      let keys : Array[Value] = []
      for entry in entries {
        keys.push(entry.key)
      }
      Some(ListingValue(keys))
    }
    "values" => {
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(ListingValue(values))
    }
    _ => {
      diagnostics.push(Diagnostic::{
        message: "unknown Mapping property \{name}",
      })
      None
    }
  }
}

///|
fn eval_mapping_method(
  entries : Array[ValueEntry],
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "containsKey" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Mapping.containsKey expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      Some(BoolValue(contains_entry_key(entries, arg_values[0])))
    }
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "Mapping.getOrNull expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match lookup_entry(entries, arg_values[0]) {
        Some(v) => Some(v)
        None => Some(NullValue)
      }
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "Mapping.fold expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for entry in entries {
        match
          apply_function_value(
            "Mapping.fold combine",
            callback,
            [acc, entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    _ => None
  }
}

///|
fn eval_int_property(
  n : Int,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "abs" => if n < 0 { Some(IntValue(0 - n)) } else { Some(IntValue(n)) }
    "isEven" => Some(BoolValue(n % 2 == 0))
    "isOdd" => Some(BoolValue(n % 2 != 0))
    _ => {
      diagnostics.push(Diagnostic::{ message: "unknown Int property \{name}" })
      None
    }
  }
}

///|
fn int_to_string_radix(n : Int, radix : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let negative = n < 0
  let mut value = if negative { 0 - n } else { n }
  let chars : Array[Char] = []
  while value > 0 {
    let d = value % radix
    chars.push(digits.unsafe_get(d).to_int().unsafe_to_char())
    value = value / radix
  }
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  let mut i = chars.length() - 1
  while i >= 0 {
    buf.write_char(chars[i])
    i = i - 1
  }
  buf.to_string()
}

///|
fn eval_int_method(
  n : Int,
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        Some(StringValue("\{n}"))
      } else if arg_values.length() == 1 {
        match arg_values[0] {
          IntValue(radix) =>
            if radix < 2 || radix > 36 {
              diagnostics.push(Diagnostic::{
                message: "Int.toString radix must be between 2 and 36, got \{radix}",
              })
              None
            } else {
              Some(StringValue(int_to_string_radix(n, radix)))
            }
          _ => {
            diagnostics.push(Diagnostic::{
              message: "Int.toString radix must be Int",
            })
            None
          }
        }
      } else {
        diagnostics.push(Diagnostic::{
          message: "Int.toString expects 0 or 1 arguments, got \{arg_values.length()}",
        })
        None
      }
    "toChar" => {
      if arg_values.length() != 0 {
        diagnostics.push(Diagnostic::{
          message: "Int.toChar expects 0 arguments, got \{arg_values.length()}",
        })
        return None
      }
      if n < 0 || n > 0x10FFFF {
        diagnostics.push(Diagnostic::{
          message: "Int.toChar code point out of range: \{n}",
        })
        return None
      }
      let buf = StringBuilder::new()
      buf.write_char(n.unsafe_to_char())
      Some(StringValue(buf.to_string()))
    }
    _ => None
  }
}

///|
fn eval_string_property(
  s : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(s.length()))
    "isEmpty" => Some(BoolValue(s.length() == 0))
    _ => {
      diagnostics.push(Diagnostic::{
        message: "unknown String property \{name}",
      })
      None
    }
  }
}

///|
fn pad_string(s : String, width : Int, pad : String, at_start : Bool) -> String {
  let current = s.length()
  if current >= width || pad.length() == 0 {
    return s
  }
  let buf = StringBuilder::new()
  if at_start {
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
    buf.write_string(s)
  } else {
    buf.write_string(s)
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
  }
  buf.to_string()
}

///|
fn eval_string_method(
  s : String,
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toUpperCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(Diagnostic::{
          message: "String.toUpperCase expects 0 arguments, got \{arg_values.length()}",
        })
        return None
      }
      Some(StringValue(s.to_upper()))
    }
    "toLowerCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(Diagnostic::{
          message: "String.toLowerCase expects 0 arguments, got \{arg_values.length()}",
        })
        return None
      }
      Some(StringValue(s.to_lower()))
    }
    "contains" =>
      one_string_arg(arg_values, "String.contains", diagnostics, fn(needle) {
        Some(BoolValue(s.contains(needle)))
      })
    "startsWith" =>
      one_string_arg(arg_values, "String.startsWith", diagnostics, fn(prefix) {
        Some(BoolValue(s.has_prefix(prefix)))
      })
    "endsWith" =>
      one_string_arg(arg_values, "String.endsWith", diagnostics, fn(suffix) {
        Some(BoolValue(s.has_suffix(suffix)))
      })
    "indexOf" =>
      one_string_arg(arg_values, "String.indexOf", diagnostics, fn(needle) {
        match s.find(needle) {
          Some(i) => Some(IntValue(i))
          None => Some(IntValue(-1))
        }
      })
    "replaceAll" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "String.replaceAll expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace_all(old~, new=new_value)))
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.replaceAll expects String arguments",
          })
          None
        }
      }
    }
    "replaceFirst" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "String.replaceFirst expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace(old~, new=new_value)))
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.replaceFirst expects String arguments",
          })
          None
        }
      }
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "String.take expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(StringValue(String::unsafe_substring(s, start=0, end=n)))
        }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.take expects Int argument",
          })
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(Diagnostic::{
          message: "String.drop expects 1 argument, got \{arg_values.length()}",
        })
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(
            StringValue(String::unsafe_substring(s, start=n, end=s.length())),
          )
        }
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.drop expects Int argument",
          })
          None
        }
      }
    }
    "split" =>
      one_string_arg(arg_values, "String.split", diagnostics, fn(sep) {
        let parts : Array[Value] = []
        for piece in s.split(sep) {
          parts.push(StringValue(piece.to_owned()))
        }
        Some(ListingValue(parts))
      })
    "padStart" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "String.padStart expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, true)))
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.padStart expects (Int, String) arguments",
          })
          None
        }
      }
    }
    "padEnd" => {
      if arg_values.length() != 2 {
        diagnostics.push(Diagnostic::{
          message: "String.padEnd expects 2 arguments, got \{arg_values.length()}",
        })
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, false)))
        _ => {
          diagnostics.push(Diagnostic::{
            message: "String.padEnd expects (Int, String) arguments",
          })
          None
        }
      }
    }
    _ => None
  }
}

///|
fn one_string_arg(
  arg_values : Array[Value],
  label : String,
  diagnostics : Array[Diagnostic],
  body : (String) -> Value?,
) -> Value? {
  if arg_values.length() != 1 {
    diagnostics.push(Diagnostic::{
      message: "\{label} expects 1 argument, got \{arg_values.length()}",
    })
    return None
  }
  match arg_values[0] {
    StringValue(s) => body(s)
    _ => {
      diagnostics.push(Diagnostic::{
        message: "\{label} expects String argument",
      })
      None
    }
  }
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
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_expr_with_bindings(
      target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
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
                    argument, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
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
                    match
                      eval_callable_argument_rejection_message(
                        function_decl.parameters[i].type_name,
                        argument_values[i],
                        declarations,
                      ) {
                      Some(message) => {
                        diagnostics.push(Diagnostic::{
                          message: "method \{method_name} argument \{i + 1} \{message}",
                        })
                        return None
                      }
                      None => ()
                    }
                    method_cache.push({
                      name: function_decl.parameters[i].name,
                      value: argument_values[i],
                    })
                  }
                  match
                    eval_expr_with_bindings(
                      body, bindings, env, class_env, method_cache, stack, declarations,
                      diagnostics, resolve_import,
                    ) {
                    Some(value) =>
                      eval_callable_return_value(
                        "method \{method_name}",
                        function_decl.return_type_name,
                        value,
                        declarations,
                        diagnostics,
                      )
                    None => None
                  }
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
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_expr_with_bindings(
      callee, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
    ) {
    Some(FunctionValue(parameters, body, return_type_name, captured_env)) =>
      eval_lambda_application(
        callee_label(callee),
        parameters,
        body,
        return_type_name,
        captured_env,
        arguments,
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
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
  declarations : Array[Declaration],
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
            members, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          ),
        ),
      )
    TypedObjectLiteral(type_name, members) =>
      Some(
        ObjectValue(
          merge_value_members(
            eval_class_default_members(
              type_name, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
            ),
            eval_object_members(
              members, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
            ),
          ),
        ),
      )
    ListingLiteral(elements) => {
      let values : Array[Value] = []
      for element in elements {
        match
          eval_expr_with_bindings(
            element, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
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
          declarations,
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
          declarations,
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
          target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
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
        Some(ListingValue(elements)) =>
          if is_listing_property_name(member_name) {
            eval_listing_property(elements, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Listing property \{member_name}",
            })
            None
          }
        Some(MappingValue(entries)) =>
          if is_mapping_property_name(member_name) {
            eval_mapping_property(entries, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Mapping property \{member_name}",
            })
            None
          }
        Some(StringValue(s)) =>
          if is_string_property_name(member_name) {
            eval_string_property(s, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown String property \{member_name}",
            })
            None
          }
        Some(IntValue(n)) =>
          if is_int_property_name(member_name) {
            eval_int_property(n, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Int property \{member_name}",
            })
            None
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
          target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
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
        Some(ListingValue(elements)) =>
          if is_listing_property_name(member_name) {
            eval_listing_property(elements, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Listing property \{member_name}",
            })
            None
          }
        Some(MappingValue(entries)) =>
          if is_mapping_property_name(member_name) {
            eval_mapping_property(entries, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Mapping property \{member_name}",
            })
            None
          }
        Some(StringValue(s)) =>
          if is_string_property_name(member_name) {
            eval_string_property(s, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown String property \{member_name}",
            })
            None
          }
        Some(IntValue(n)) =>
          if is_int_property_name(member_name) {
            eval_int_property(n, member_name, diagnostics)
          } else {
            diagnostics.push(Diagnostic::{
              message: "unknown Int property \{member_name}",
            })
            None
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
        target_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      let key = eval_expr_with_bindings(
        key_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
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
          base_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(ObjectValue(base_members)) =>
          Some(
            ObjectValue(
              merge_value_members(
                base_members,
                eval_object_members(
                  members, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
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
          name, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
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
              cache, stack, declarations, diagnostics, resolve_import,
            )
          } else if is_listing_method_name(method_name) ||
            is_mapping_method_name(method_name) ||
            is_string_method_name(method_name) ||
            is_int_method_name(method_name) {
            match
              eval_expr_with_bindings(
                target_expr, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              ) {
              Some(ListingValue(elements)) =>
                if is_listing_method_name(method_name) {
                  eval_listing_method(
                    elements, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(MappingValue(entries)) =>
                if is_mapping_method_name(method_name) {
                  eval_mapping_method(
                    entries, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(StringValue(s)) =>
                if is_string_method_name(method_name) {
                  eval_string_method(
                    s, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(IntValue(n)) =>
                if is_int_method_name(method_name) {
                  eval_int_method(
                    n, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              _ =>
                eval_callable_call(
                  callee, arguments, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                )
            }
          } else {
            eval_callable_call(
              callee, arguments, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          }
        SafeMemberAccess(target_expr, method_name) =>
          if class_method_call_available(
              target_expr, method_name, bindings, class_env,
            ) {
            eval_class_method_call(
              target_expr, method_name, arguments, true, bindings, env, class_env,
              cache, stack, declarations, diagnostics, resolve_import,
            )
          } else if is_listing_method_name(method_name) ||
            is_mapping_method_name(method_name) ||
            is_string_method_name(method_name) ||
            is_int_method_name(method_name) {
            match
              eval_expr_with_bindings(
                target_expr, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
              ) {
              Some(NullValue) => Some(NullValue)
              Some(ListingValue(elements)) =>
                if is_listing_method_name(method_name) {
                  eval_listing_method(
                    elements, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(MappingValue(entries)) =>
                if is_mapping_method_name(method_name) {
                  eval_mapping_method(
                    entries, method_name, arguments, bindings, env, class_env, cache,
                    stack, declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(StringValue(s)) =>
                if is_string_method_name(method_name) {
                  eval_string_method(
                    s, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              Some(IntValue(n)) =>
                if is_int_method_name(method_name) {
                  eval_int_method(
                    n, method_name, arguments, bindings, env, class_env, cache, stack,
                    declarations, diagnostics, resolve_import,
                  )
                } else {
                  eval_callable_call(
                    callee, arguments, bindings, env, class_env, cache, stack, declarations,
                    diagnostics, resolve_import,
                  )
                }
              _ =>
                eval_callable_call(
                  callee, arguments, bindings, env, class_env, cache, stack, declarations,
                  diagnostics, resolve_import,
                )
            }
          } else {
            eval_callable_call(
              callee, arguments, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
            )
          }
        _ =>
          eval_callable_call(
            callee, arguments, bindings, env, class_env, cache, stack, declarations,
            diagnostics, resolve_import,
          )
      }
    LambdaExpr(parameters, body, return_type_name) =>
      Some(
        FunctionValue(
          parameters,
          body,
          return_type_name,
          capture_value_bindings(env, cache),
        ),
      )
    NonNullExpr(inner_expr) =>
      match
        eval_expr_with_bindings(
          inner_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
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
        inner_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
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
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
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
              right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
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
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
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
              right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
              resolve_import,
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
            left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
          match left {
            Some(NullValue) =>
              return eval_expr_with_bindings(
                right_expr, bindings, env, class_env, cache, stack, declarations,
                diagnostics, resolve_import,
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
        left_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      )
      let right = eval_expr_with_bindings(
        right_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
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
          condition_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
          resolve_import,
        ) {
        Some(BoolValue(true)) =>
          eval_expr_with_bindings(
            then_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
          )
        Some(BoolValue(false)) =>
          eval_expr_with_bindings(
            else_expr, bindings, env, class_env, cache, stack, declarations, diagnostics,
            resolve_import,
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
  declarations : Array[Declaration],
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
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(value) =>
        if pkl_constrained_type_annotation_value_is_valid(
            field.type_name,
            value,
            diagnostics,
          ) {
          values.push({ name: field.name, value })
        }
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
  declarations : Array[Declaration],
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
              parent_name, bindings, env, class_env, cache, stack, declarations,
              diagnostics, resolve_import,
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
      defaults, bindings, env, class_env, cache, stack, declarations, diagnostics,
      resolve_import,
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
fn pkl_test_catch_lambda_body(expr : Expr) -> Expr? {
  match expr {
    CallExpr(MemberAccess(Identifier("test"), "catch"), arguments) =>
      if arguments.length() == 1 {
        match arguments[0] {
          LambdaExpr(parameters, body, _) =>
            if parameters.length() == 0 {
              Some(body)
            } else {
              None
            }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn eval_pkl_test_catch_binding_value(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match pkl_test_catch_lambda_body(expr) {
    Some(body) => {
      let caught_diagnostics : Array[Diagnostic] = []
      push_constrained_class_property_expr_diagnostics(
        body, declarations, caught_diagnostics,
      )
      if caught_diagnostics.length() > 0 {
        return Some(StringValue(caught_diagnostics[0].message))
      }
      match
        eval_expr_with_bindings(
          body, bindings, env, class_env, cache, stack, declarations, caught_diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          if caught_diagnostics.length() > 0 {
            Some(StringValue(caught_diagnostics[0].message))
          } else {
            Some(StringValue(render_value(value)))
          }
        None =>
          if caught_diagnostics.length() > 0 {
            Some(StringValue(caught_diagnostics[0].message))
          } else {
            Some(StringValue("caught error"))
          }
      }
    }
    None => None
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
  let type_aliases = eval_type_alias_bindings(program.declarations)
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
      let resolved_value = match
        eval_pkl_test_catch_binding_value(
          binding.value,
          bindings,
          env,
          class_env,
          cache,
          [],
          program.declarations,
          resolve_import,
        ) {
        Some(value) => {
          cache.push({ name: binding.name, value })
          Some(value)
        }
        None =>
          resolve_binding_value(
            binding.name,
            bindings,
            env,
            class_env,
            cache,
            [],
            program.declarations,
            diagnostics,
            resolve_import,
          )
      }
      match resolved_value {
        Some(value) =>
          if eval_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              type_aliases,
              diagnostics,
            ) &&
            eval_user_defined_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              program.declarations,
              diagnostics,
            ) &&
            eval_expr_class_property_constraints_are_valid(
              binding.value,
              value,
              program.declarations,
              diagnostics,
            ) &&
            eval_expr_alias_constraints_are_valid(
              binding.value,
              value,
              type_aliases,
              diagnostics,
            ) {
            members.push({ name: binding.name, value })
          }
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
        program.declarations,
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

///| Render a runtime value in the canonical Pkl Configuration Format

///| (PCF). Primitives use the same lexical form as Apple Pkl's

///| `pkl eval` default output, so the result can be reparsed by this

///| evaluator and by upstream Pkl. The JSON / YAML / Properties

///| renderers (PKL-072..074) will live alongside this as separate

///|
/// entry points.
pub fn render_value(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_pcf_module(members, buf)
    _ => render_pcf_inline(value, 0, buf)
  }
  buf.to_string()
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
fn pcf_is_block_value(value : Value) -> Bool {
  match value {
    ObjectValue(_) | ListingValue(_) | MappingValue(_) => true
    _ => false
  }
}

///|
fn write_pcf_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn render_pcf_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) => {
      buf.write_char('"')
      buf.write_string(escape_string(s))
      buf.write_char('"')
    }
    NullValue => buf.write_string("null")
    FunctionValue(_, _, _, _) => buf.write_string("<function>")
    ObjectValue(_) | ListingValue(_) | MappingValue(_) =>
      // Defensive: callers should route block values through
      // render_pcf_inline / render_pcf_block_body. Falling back keeps
      // diagnostics non-empty if we ever miss a case.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_pcf_inline(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  if pcf_is_block_value(value) {
    buf.write_string("new ")
    render_pcf_block_body(value, indent, buf)
  } else {
    render_pcf_scalar(value, buf)
  }
}

///|
fn render_pcf_block_body(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue([]) | ListingValue([]) | MappingValue([]) =>
      buf.write_string("{}")
    ObjectValue(members) => {
      buf.write_string("{\n")
      for i = 0; i < members.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_object_member(members[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    ListingValue(elements) => {
      buf.write_string("{\n")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_inline(elements[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    MappingValue(entries) => {
      buf.write_string("{\n")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_mapping_entry(entries[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    _ => render_pcf_scalar(value, buf)
  }
}

///|
fn render_pcf_object_member(
  field : ValueMember,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_string(field.name)
  if pcf_is_block_value(field.value) {
    buf.write_char(' ')
    render_pcf_block_body(field.value, indent, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(field.value, buf)
  }
}

///|
fn render_pcf_mapping_entry(
  entry : ValueEntry,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_char('[')
  render_pcf_inline(entry.key, indent, buf)
  buf.write_char(']')
  if pcf_is_block_value(entry.value) {
    buf.write_char(' ')
    render_pcf_block_body(entry.value, indent, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(entry.value, buf)
  }
}

///|
fn render_pcf_module(members : Array[ValueMember], buf : StringBuilder) -> Unit {
  for i = 0; i < members.length(); i = i + 1 {
    if i > 0 {
      buf.write_char('\n')
    }
    render_pcf_object_member(members[i], 0, buf)
  }
}

///|
/// Render a Pkl value as JSON matching `pkl eval -f json`.
///
/// - ObjectValue / MappingValue → JSON object (Mapping keys are coerced to strings).
/// - ListingValue → JSON array.
/// - IntValue / BoolValue / NullValue → JSON scalar.
/// - StringValue → JSON string with the standard `"`, `\\`, control-character
///   escapes.
/// - FunctionValue does not have a JSON projection and renders as `null` so
///   diagnostics still produce a parseable document; the typechecker rejects
///   functions earlier on the rendering path.
///
/// Indentation is fixed at two spaces, matching the upstream default for
/// `pkl eval -f json`.
pub fn render_value_as_json(value : Value) -> String {
  let buf = StringBuilder::new()
  render_json_value(value, 0, buf)
  buf.to_string()
}

///|
fn render_json_value(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) =>
      render_json_object_from_members(members, indent, buf)
    MappingValue(entries) =>
      render_json_object_from_entries(entries, indent, buf)
    ListingValue(elements) => render_json_array(elements, indent, buf)
    FunctionValue(_, _, _, _) => buf.write_string("null")
  }
}

///|
fn render_json_string(value : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in value {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' {
          let code = c.to_int()
          let hex = json_hex4(code)
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn json_hex4(code : Int) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  let mut i = 12
  while i >= 0 {
    let nibble = (code >> i) & 0xF
    buf.write_char(digits.unsafe_get(nibble).to_int().unsafe_to_char())
    i = i - 4
  }
  buf.to_string()
}

///|
fn json_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn write_json_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn render_json_object_from_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if members.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < members.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(members[i].name, buf)
    buf.write_string(": ")
    render_json_value(members[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_object_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if entries.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for i = 0; i < entries.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_string(json_coerce_key(entries[i].key), buf)
    buf.write_string(": ")
    render_json_value(entries[i].value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char('}')
}

///|
fn render_json_array(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  if elements.length() == 0 {
    buf.write_string("[]")
    return
  }
  buf.write_string("[\n")
  for i = 0; i < elements.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    write_json_indent(buf, indent + 2)
    render_json_value(elements[i], indent + 2, buf)
  }
  buf.write_char('\n')
  write_json_indent(buf, indent)
  buf.write_char(']')
}

///|
/// Render a Value as YAML, mirroring the basic shape of `pkl eval -f yaml`.
///
/// Block style is used throughout: mappings emit `key: value` per line,
/// listings emit `- value` per line at the same column as the parent key, and
/// empty composites use flow form (`[]` / `{}`). String scalars are bare when
/// they parse as plain YAML, single-quoted when they collide with reserved
/// shapes (numeric / keyword / leading indicator / inline `: ` / ` #`), and
/// double-quoted with `\`-escapes when they contain control characters or a
/// backslash. Block scalars (`|`, `|-`, `|+`) for multiline strings remain
/// follow-up work.
///
/// Indentation is fixed at two spaces; Apple Pkl's `indentWidth` knob lives
/// inside the `YamlRenderer` stdlib class (PKL-079 expansion), which our
/// pipeline does not consume yet.
pub fn render_value_as_yaml(value : Value) -> String {
  let buf = StringBuilder::new()
  render_yaml_root(value, buf)
  buf.to_string()
}

///|
fn render_yaml_root(value : Value, buf : StringBuilder) -> Unit {
  match value {
    ObjectValue(members) =>
      if members.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_members(members, 0, buf)
      }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string("{}\n")
      } else {
        render_yaml_mapping_entries(entries, 0, buf)
      }
    ListingValue(elements) =>
      if elements.length() == 0 {
        buf.write_string("[]\n")
      } else {
        render_yaml_sequence(elements, 0, buf)
      }
    _ => {
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_mapping_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < members.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(members[i].name, buf)
    buf.write_char(':')
    render_yaml_block_value(members[i].value, indent, buf)
  }
}

///|
fn render_yaml_mapping_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < entries.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    render_yaml_key(yaml_coerce_key(entries[i].key), buf)
    buf.write_char(':')
    render_yaml_block_value(entries[i].value, indent, buf)
  }
}

///|
fn render_yaml_block_value(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue(members) =>
      if members.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_members(members, indent + 2, buf)
      }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char('\n')
        render_yaml_mapping_entries(entries, indent + 2, buf)
      }
    ListingValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char('\n')
        render_yaml_sequence(elements, indent, buf)
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_sequence(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  for i = 0; i < elements.length(); i = i + 1 {
    write_yaml_indent(buf, indent)
    buf.write_char('-')
    render_yaml_seq_item(elements[i], indent + 2, buf)
  }
}

///|
fn render_yaml_seq_item(
  value : Value,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  // The first sub-member or sub-element shares the `- ` line; the rest are
  // continued at `indent` (two spaces past the `- `).
  match value {
    ObjectValue(members) =>
      if members.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(members[0].name, buf)
        buf.write_char(':')
        render_yaml_block_value(members[0].value, indent, buf)
        for i = 1; i < members.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(members[i].name, buf)
          buf.write_char(':')
          render_yaml_block_value(members[i].value, indent, buf)
        }
      }
    MappingValue(entries) =>
      if entries.length() == 0 {
        buf.write_string(" {}\n")
      } else {
        buf.write_char(' ')
        render_yaml_key(yaml_coerce_key(entries[0].key), buf)
        buf.write_char(':')
        render_yaml_block_value(entries[0].value, indent, buf)
        for i = 1; i < entries.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          render_yaml_key(yaml_coerce_key(entries[i].key), buf)
          buf.write_char(':')
          render_yaml_block_value(entries[i].value, indent, buf)
        }
      }
    ListingValue(elements) =>
      if elements.length() == 0 {
        buf.write_string(" []\n")
      } else {
        buf.write_char(' ')
        buf.write_char('-')
        render_yaml_seq_item(elements[0], indent + 2, buf)
        for i = 1; i < elements.length(); i = i + 1 {
          write_yaml_indent(buf, indent)
          buf.write_char('-')
          render_yaml_seq_item(elements[i], indent + 2, buf)
        }
      }
    _ => {
      buf.write_char(' ')
      render_yaml_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_yaml_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_yaml_string(s, buf)
    _ =>
      // Composite values reach this path only via the same renderer fallback
      // that PCF / JSON use, so produce a deterministic flow form rather than
      // panic. Anything richer is handled by the block-mode entry points.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_yaml_key(name : String, buf : StringBuilder) -> Unit {
  // Keys reuse the scalar-string quoting policy.
  render_yaml_string(name, buf)
}

///|
fn render_yaml_string(s : String, buf : StringBuilder) -> Unit {
  if s == "" {
    buf.write_string("''")
    return
  }
  if yaml_string_needs_double_quote(s) {
    render_yaml_double_quoted(s, buf)
    return
  }
  if yaml_string_needs_single_quote(s) {
    render_yaml_single_quoted(s, buf)
    return
  }
  buf.write_string(s)
}

///|
fn yaml_string_needs_double_quote(s : String) -> Bool {
  for c in s {
    if c < ' ' || c == '\u{7F}' || c == '\\' {
      return true
    }
  }
  false
}

///|
fn yaml_string_needs_single_quote(s : String) -> Bool {
  // Reserved YAML 1.1 plain-scalar keywords.
  if yaml_is_reserved_keyword(s) {
    return true
  }
  if yaml_looks_like_number(s) {
    return true
  }
  let mut first : Char = ' '
  let mut has_char = false
  for c in s {
    first = c
    has_char = true
    break
  }
  if !has_char {
    return false
  }
  if first == ' ' || first == '\t' {
    return true
  }
  // Leading indicator characters that would otherwise alter parsing.
  match first {
    '-'
    | '?'
    | ':'
    | ','
    | '['
    | ']'
    | '{'
    | '}'
    | '#'
    | '&'
    | '*'
    | '!'
    | '|'
    | '>'
    | '\''
    | '"'
    | '%'
    | '@'
    | '`' => return true
    _ => ()
  }
  // Trailing whitespace.
  let mut last : Char = first
  for c in s {
    last = c
  }
  if last == ' ' || last == '\t' {
    return true
  }
  // Embedded `: ` or ` #` flips a plain scalar into something the YAML parser
  // would re-interpret, so reach for single quotes.
  if yaml_contains_pair(s, ':', ' ') || yaml_contains_pair(s, ' ', '#') {
    return true
  }
  false
}

///|
fn yaml_is_reserved_keyword(s : String) -> Bool {
  match s {
    "true"
    | "True"
    | "TRUE"
    | "false"
    | "False"
    | "FALSE"
    | "null"
    | "Null"
    | "NULL"
    | "~"
    | "yes"
    | "Yes"
    | "YES"
    | "no"
    | "No"
    | "NO"
    | "on"
    | "On"
    | "ON"
    | "off"
    | "Off"
    | "OFF" => true
    _ => false
  }
}

///|
fn yaml_looks_like_number(s : String) -> Bool {
  // Recognize the common `[+-]?digits(.digits)?(e[+-]?digits)?` shape that
  // YAML would otherwise parse as a number.
  let mut idx = 0
  let mut saw_digit = false
  let mut saw_dot = false
  let mut saw_exp = false
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return false
  }
  if chars[idx] == '+' || chars[idx] == '-' {
    idx = idx + 1
  }
  while idx < chars.length() {
    let c = chars[idx]
    if c >= '0' && c <= '9' {
      saw_digit = true
      idx = idx + 1
    } else if c == '.' && !saw_dot && !saw_exp {
      saw_dot = true
      idx = idx + 1
    } else if (c == 'e' || c == 'E') && !saw_exp && saw_digit {
      saw_exp = true
      idx = idx + 1
      if idx < chars.length() && (chars[idx] == '+' || chars[idx] == '-') {
        idx = idx + 1
      }
    } else {
      return false
    }
  }
  saw_digit
}

///|
fn yaml_contains_pair(s : String, a : Char, b : Char) -> Bool {
  let mut prev : Char = '\u{0}'
  let mut have_prev = false
  for c in s {
    if have_prev && prev == a && c == b {
      return true
    }
    prev = c
    have_prev = true
  }
  false
}

///|
fn render_yaml_single_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('\'')
  for c in s {
    if c == '\'' {
      buf.write_string("''")
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char('\'')
}

///|
fn render_yaml_double_quoted(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c < ' ' || c == '\u{7F}' {
          let code = c.to_int()
          let hex = json_hex4(code)
          buf.write_string("\\u")
          buf.write_string(hex)
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
fn yaml_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
fn write_yaml_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
/// Render a Value as a Java Properties document, mirroring the shape of
/// `pkl eval -f properties`.
///
/// Top-level Object / Mapping members flatten into dotted keys. Scalars emit
/// as `key = value` lines (unquoted, with property-style escaping for `\`,
/// `\n`, `\t`, `\r`, `\f`, leading space, `:`, `=`, `!`, `#`). Null leaves
/// are omitted (Apple Pkl's `omitNullProperties` default is `true`). Listings
/// render as a compact JSON-style single-line value (`[1,2,3]`), and the
/// JSON form's own `:` separators are then property-escaped to `\:`. Empty
/// Object / Mapping leaves are dropped entirely; empty Listings still emit
/// `key = []`. Top-level non-mapping values produce an empty document.
///
/// Apple Pkl's `restrictCharset = true` mode (emit `\uXXXX` for non-ASCII)
/// remains a follow-up — the default is `false` here, so unicode passes
/// through verbatim.
pub fn render_value_as_properties(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_properties_members(members, "", buf)
    MappingValue(entries) => render_properties_entries(entries, "", buf)
    _ => ()
  }
  buf.to_string()
}

///|
fn render_properties_members(
  members : Array[ValueMember],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for field in members {
    render_properties_leaf(prefix, field.name, field.value, buf)
  }
}

///|
fn render_properties_entries(
  entries : Array[ValueEntry],
  prefix : String,
  buf : StringBuilder,
) -> Unit {
  for entry in entries {
    let key = properties_coerce_key(entry.key)
    render_properties_leaf(prefix, key, entry.value, buf)
  }
}

///|
fn render_properties_leaf(
  prefix : String,
  name : String,
  value : Value,
  buf : StringBuilder,
) -> Unit {
  let full_key = if prefix == "" { name } else { prefix + "." + name }
  match value {
    NullValue => ()
    ObjectValue(members) =>
      if members.length() == 0 {
        // Empty Object has no leaves, so drop the key entirely.
      } else {
        render_properties_members(members, full_key, buf)
      }
    MappingValue(entries) =>
      if entries.length() == 0 {
        // Empty Mapping likewise has no leaves.
      } else {
        render_properties_entries(entries, full_key, buf)
      }
    ListingValue(_) | FunctionValue(_, _, _, _) => {
      let compact = render_properties_compact_json(value)
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_value(compact, buf)
      buf.write_char('\n')
    }
    _ => {
      write_properties_key(full_key, buf)
      buf.write_string(" = ")
      write_properties_scalar(value, buf)
      buf.write_char('\n')
    }
  }
}

///|
fn render_properties_compact_json(value : Value) -> String {
  let buf = StringBuilder::new()
  write_compact_json_value(value, buf)
  buf.to_string()
}

///|
fn write_compact_json_value(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("null")
    StringValue(s) => render_json_string(s, buf)
    ObjectValue(members) => {
      buf.write_char('{')
      for i = 0; i < members.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(members[i].name, buf)
        buf.write_char(':')
        write_compact_json_value(members[i].value, buf)
      }
      buf.write_char('}')
    }
    MappingValue(entries) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        render_json_string(json_coerce_key(entries[i].key), buf)
        buf.write_char(':')
        write_compact_json_value(entries[i].value, buf)
      }
      buf.write_char('}')
    }
    ListingValue(elements) => {
      buf.write_char('[')
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact_json_value(elements[i], buf)
      }
      buf.write_char(']')
    }
    FunctionValue(_, _, _, _) => buf.write_string("null")
  }
}

///|
fn write_properties_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    NullValue => buf.write_string("")
    StringValue(s) => write_properties_value(s, buf)
    _ =>
      // Unreachable in practice: render_properties_leaf already dispatches
      // composites through the compact-JSON path.
      write_properties_value(render_properties_compact_json(value), buf)
  }
}

///|
fn write_properties_key(key : String, buf : StringBuilder) -> Unit {
  for c in key {
    match c {
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0C}' => buf.write_string("\\f")
      ' ' => buf.write_string("\\ ")
      ':' => buf.write_string("\\:")
      '=' => buf.write_string("\\=")
      '!' => buf.write_string("\\!")
      '#' => buf.write_string("\\#")
      _ => buf.write_char(c)
    }
  }
}

///|
fn write_properties_value(s : String, buf : StringBuilder) -> Unit {
  let mut first = true
  for c in s {
    if first && c == ' ' {
      buf.write_string("\\ ")
    } else {
      match c {
        '\\' => buf.write_string("\\\\")
        '\n' => buf.write_string("\\n")
        '\r' => buf.write_string("\\r")
        '\t' => buf.write_string("\\t")
        '\u{0C}' => buf.write_string("\\f")
        ':' => buf.write_string("\\:")
        '=' => buf.write_string("\\=")
        '!' => buf.write_string("\\!")
        '#' => buf.write_string("\\#")
        _ => buf.write_char(c)
      }
    }
    first = false
  }
}

///|
fn properties_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
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
