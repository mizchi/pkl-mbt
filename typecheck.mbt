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
  UnionType(Array[Type])
  NullableType(Type)
  DefaultedType(Type)
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
pub(all) struct TypeExport {
  name : String
  typ : Type
} derive(Eq, Debug)

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
fn member_contract_type(typ : Type) -> Type {
  match typ {
    DefaultedType(inner) => inner
    _ => typ
  }
}

///|
fn is_defaulted_member_type(typ : Type) -> Bool {
  match typ {
    DefaultedType(_) => true
    _ => false
  }
}

///|
fn nullable_type(typ : Type) -> Type {
  match typ {
    NullableType(_) => typ
    _ => NullableType(typ)
  }
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
    UnionType(types) => {
      let buf = StringBuilder::new()
      let mut first = true
      for typ in types {
        if first {
          first = false
        } else {
          buf.write_string("|")
        }
        buf.write_string(render_type(typ))
      }
      buf.to_string()
    }
    NullableType(inner) => "\{render_type(inner)}?"
    DefaultedType(inner) => render_type(inner)
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
fn split_top_level_generic_arguments(text : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for char in text {
    if char == ',' && parens == 0 && brackets == 0 && angles == 0 {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      if char == '(' {
        parens += 1
      } else if char == ')' && parens > 0 {
        parens -= 1
      } else if char == '[' {
        brackets += 1
      } else if char == ']' && brackets > 0 {
        brackets -= 1
      } else if char == '<' {
        angles += 1
      } else if char == '>' && angles > 0 {
        angles -= 1
      }
      buf.write_string(char.to_string())
    }
  }
  let last = buf.to_string()
  if last != "" || parts.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn split_top_level_union_choices(text : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for char in text {
    if char == '|' && parens == 0 && brackets == 0 && angles == 0 {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      if char == '(' {
        parens += 1
      } else if char == ')' && parens > 0 {
        parens -= 1
      } else if char == '[' {
        brackets += 1
      } else if char == ']' && brackets > 0 {
        brackets -= 1
      } else if char == '<' {
        angles += 1
      } else if char == '>' && angles > 0 {
        angles -= 1
      }
      buf.write_string(char.to_string())
    }
  }
  let last = buf.to_string()
  if last != "" || parts.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn push_unique_type(types : Array[Type], typ : Type) -> Unit {
  let mut found = false
  for existing in types {
    if existing == typ {
      found = true
    }
  }
  if !found {
    types.push(typ)
  }
}

///|
fn make_union_type(types : Array[Type]) -> Type {
  let flattened : Array[Type] = []
  for typ in types {
    match typ {
      UnionType(inner_types) =>
        for inner in inner_types {
          push_unique_type(flattened, inner)
        }
      _ => push_unique_type(flattened, typ)
    }
  }
  if flattened.length() == 0 {
    UnknownType
  } else if flattened.length() == 1 {
    flattened[0]
  } else {
    UnionType(flattened)
  }
}

///|
fn generic_argument_text(name : String, prefix : String) -> String? {
  let start = prefix.length() + 1
  if name.has_prefix(prefix + "<") &&
    name.has_suffix(">") &&
    name.length() > start {
    Some(String::unsafe_substring(name, start~, end=name.length() - 1))
  } else {
    None
  }
}

///|
fn type_from_annotation(name : String, type_env : Array[TypeBinding]) -> Type? {
  let union_choices = split_top_level_union_choices(name)
  if union_choices.length() > 1 {
    let types : Array[Type] = []
    for choice in union_choices {
      if choice == "" {
        return None
      }
      match type_from_annotation(choice, type_env) {
        Some(typ) => types.push(typ)
        None => return None
      }
    }
    return Some(make_union_type(types))
  }
  if name.has_suffix("?") {
    let inner_name = String::unsafe_substring(
      name,
      start=0,
      end=name.length() - 1,
    )
    match type_from_annotation(inner_name, type_env) {
      Some(inner) => return Some(NullableType(inner))
      None => return None
    }
  }
  match generic_argument_text(name, "Listing") {
    Some(inner_text) =>
      match type_from_annotation(inner_text, type_env) {
        Some(inner) => return Some(ListingType([inner]))
        None => return None
      }
    None => ()
  }
  match generic_argument_text(name, "Mapping") {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() != 2 {
        return None
      }
      match
        (
          type_from_annotation(parts[0], type_env),
          type_from_annotation(parts[1], type_env),
        ) {
        (Some(key), Some(value)) =>
          return Some(MappingType([TypeEntry::{ key, value }]))
        _ => return None
      }
    }
    None => ()
  }
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
    (UnionType(expected_options), UnionType(actual_options)) => {
      let mut ok = true
      for actual in actual_options {
        if !type_accepts(UnionType(expected_options), actual) {
          ok = false
        }
      }
      ok
    }
    (UnionType(expected_options), actual) => {
      let mut ok = false
      for expected_option in expected_options {
        if type_accepts(expected_option, actual) {
          ok = true
        }
      }
      ok
    }
    (expected, UnionType(actual_options)) => {
      let mut ok = true
      for actual in actual_options {
        if !type_accepts(expected, actual) {
          ok = false
        }
      }
      ok
    }
    (DefaultedType(expected_inner), actual) =>
      type_accepts(expected_inner, member_contract_type(actual))
    (expected, DefaultedType(actual_inner)) =>
      type_accepts(expected, actual_inner)
    (NullableType(_), NullType) => true
    (NullableType(expected_inner), NullableType(actual_inner)) =>
      type_accepts(expected_inner, actual_inner)
    (NullableType(expected_inner), actual) =>
      type_accepts(expected_inner, actual)
    (ClassType(_, expected_members), ObjectType(actual_members)) => {
      let mut ok = true
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            if !type_accepts(member_contract_type(expected_member.typ), actual) {
              ok = false
            }
          None =>
            if !is_defaulted_member_type(expected_member.typ) {
              ok = false
            }
        }
      }
      ok
    }
    (ListingType(expected_items), ListingType(actual_items)) => {
      if expected_items.length() == 0 {
        return true
      }
      let expected_item = common_type(expected_items)
      let mut ok = true
      for actual_item in actual_items {
        if !type_accepts(expected_item, actual_item) {
          ok = false
        }
      }
      ok
    }
    (MappingType(expected_entries), MappingType(actual_entries)) => {
      if expected_entries.length() == 0 {
        return true
      }
      let expected_key = common_type(
        expected_entries.map(fn(entry) { entry.key }),
      )
      let expected_value = common_type(
        expected_entries.map(fn(entry) { entry.value }),
      )
      let mut ok = true
      for actual_entry in actual_entries {
        if !type_accepts(expected_key, actual_entry.key) ||
          !type_accepts(expected_value, actual_entry.value) {
          ok = false
        }
      }
      ok
    }
    (
      FunctionType(expected_parameters, expected_return),
      FunctionType(actual_parameters, actual_return),
    ) => {
      if expected_parameters.length() != actual_parameters.length() {
        return false
      }
      let mut ok = type_accepts(expected_return, actual_return)
      for i = 0; i < expected_parameters.length(); i = i + 1 {
        if !type_accepts(expected_parameters[i], actual_parameters[i]) {
          ok = false
        }
      }
      ok
    }
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
              if !type_accepts(
                  member_contract_type(expected_member.typ),
                  actual,
                ) {
                message = Some(
                  "type annotation \{annotation_name} member \{expected_member.name} expects \{render_type(expected_member.typ)}, got \{render_type(actual)}",
                )
              }
            None =>
              if !is_defaulted_member_type(expected_member.typ) {
                message = Some(
                  "type annotation \{annotation_name} missing member \{expected_member.name}",
                )
              }
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
            match (expected, inferred) {
              (NullableType(ObjectType([])), ObjectType(_)) =>
                NullableType(inferred)
              _ => expected
            }
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
      return make_union_type(types)
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
fn function_parameter_types(
  parameters : Array[FunctionParameter],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[Type] {
  let types : Array[Type] = []
  for parameter in parameters {
    match parameter.type_name {
      Some(type_name) =>
        match type_from_annotation(type_name, type_env) {
          Some(typ) => types.push(typ)
          None => {
            diagnostics.push(Diagnostic::{
              message: "unknown type annotation \{type_name}",
            })
            types.push(UnknownType)
          }
        }
      None => types.push(UnknownType)
    }
  }
  types
}

///|
fn function_return_type(
  return_type_name : String?,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match return_type_name {
    Some(type_name) =>
      match type_from_annotation(type_name, type_env) {
        Some(typ) => typ
        None => {
          diagnostics.push(Diagnostic::{
            message: "unknown type annotation \{type_name}",
          })
          UnknownType
        }
      }
    None => UnknownType
  }
}

///|
fn function_signature_type(
  function_decl : FunctionDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  FunctionType(
    function_parameter_types(function_decl.parameters, type_env, diagnostics),
    function_return_type(function_decl.return_type_name, type_env, diagnostics),
  )
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
fn qualify_imported_type(
  import_name : String,
  type_export : TypeExport,
) -> Type {
  match type_export.typ {
    ClassType(_, members) =>
      ClassType("\{import_name}.\{type_export.name}", members)
    _ => type_export.typ
  }
}

///|
fn imported_type_bindings(
  imports : Array[ImportDecl],
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> Array[TypeBinding] {
  let bindings : Array[TypeBinding] = []
  for decl in imports {
    match resolve_import_types(decl.uri) {
      Some(exports) =>
        for type_export in exports {
          bindings.push({
            name: "\{decl.import_name}.\{type_export.name}",
            typ: qualify_imported_type(decl.import_name, type_export),
          })
        }
      None => ()
    }
  }
  bindings
}

///|
fn type_name_is_qualified(name : String) -> Bool {
  name.find(".") is Some(_)
}

///|
fn optional_type_name_is_qualified(name : String?) -> Bool {
  match name {
    Some(value) => type_name_is_qualified(value)
    None => false
  }
}

///|
fn expr_uses_qualified_type_name(expr : Expr) -> Bool {
  match expr {
    TypedObjectLiteral(type_name, members) =>
      type_name_is_qualified(type_name) ||
      object_members_use_qualified_type_name(members)
    ObjectLiteral(members) => object_members_use_qualified_type_name(members)
    ListingLiteral(elements) => {
      for element in elements {
        if expr_uses_qualified_type_name(element) {
          return true
        }
      }
      false
    }
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_uses_qualified_type_name(entry.key) ||
          expr_uses_qualified_type_name(entry.value) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      expr_uses_qualified_type_name(target)
    SubscriptAccess(target, key) =>
      expr_uses_qualified_type_name(target) ||
      expr_uses_qualified_type_name(key)
    AmendExpr(base, members) =>
      expr_uses_qualified_type_name(base) ||
      object_members_use_qualified_type_name(members)
    CallExpr(callee, arguments) => {
      if expr_uses_qualified_type_name(callee) {
        return true
      }
      for argument in arguments {
        if expr_uses_qualified_type_name(argument) {
          return true
        }
      }
      false
    }
    LambdaExpr(parameters, body, return_type_name) => {
      if optional_type_name_is_qualified(return_type_name) ||
        function_parameters_use_qualified_type_name(parameters) {
        return true
      }
      expr_uses_qualified_type_name(body)
    }
    NonNullExpr(inner) | UnaryExpr(_, inner) =>
      expr_uses_qualified_type_name(inner)
    BinaryExpr(_, left, right) =>
      expr_uses_qualified_type_name(left) ||
      expr_uses_qualified_type_name(right)
    ConditionalExpr(condition, then_expr, else_expr) =>
      expr_uses_qualified_type_name(condition) ||
      expr_uses_qualified_type_name(then_expr) ||
      expr_uses_qualified_type_name(else_expr)
    _ => false
  }
}

///|
fn object_members_use_qualified_type_name(
  members : Array[ObjectMember],
) -> Bool {
  for object_member in members {
    if optional_type_name_is_qualified(object_member.type_name) ||
      expr_uses_qualified_type_name(object_member.value) {
      return true
    }
  }
  false
}

///|
fn function_parameters_use_qualified_type_name(
  parameters : Array[FunctionParameter],
) -> Bool {
  for parameter in parameters {
    if optional_type_name_is_qualified(parameter.type_name) {
      return true
    }
  }
  false
}

///|
fn function_decl_uses_qualified_type_name(function_decl : FunctionDecl) -> Bool {
  if optional_type_name_is_qualified(function_decl.return_type_name) ||
    function_parameters_use_qualified_type_name(function_decl.parameters) {
    return true
  }
  match function_decl.body {
    Some(body) => expr_uses_qualified_type_name(body)
    None => false
  }
}

///|
fn class_properties_use_qualified_type_name(
  properties : Array[ClassProperty],
) -> Bool {
  for property in properties {
    if optional_type_name_is_qualified(property.type_name) {
      return true
    }
    match property.value {
      Some(value) => if expr_uses_qualified_type_name(value) { return true }
      None => ()
    }
  }
  false
}

///|
fn class_methods_use_qualified_type_name(methods : Array[FunctionDecl]) -> Bool {
  for class_method in methods {
    if function_decl_uses_qualified_type_name(class_method) {
      return true
    }
  }
  false
}

///|
fn declaration_uses_qualified_type_name(declaration : Declaration) -> Bool {
  match declaration {
    ClassDeclaration(class_decl) => {
      if optional_type_name_is_qualified(class_decl.parent_name) {
        return true
      }
      class_properties_use_qualified_type_name(class_decl.properties) ||
      class_methods_use_qualified_type_name(class_decl.methods)
    }
    FunctionDeclaration(function_decl) =>
      function_decl_uses_qualified_type_name(function_decl)
    TypeAliasDeclaration(type_alias) =>
      type_name_is_qualified(type_alias.target)
  }
}

///|
fn program_uses_qualified_type_name(program : Program) -> Bool {
  for declaration in program.declarations {
    if declaration_uses_qualified_type_name(declaration) {
      return true
    }
  }
  for binding in program.bindings {
    if optional_type_name_is_qualified(binding.type_name) ||
      expr_uses_qualified_type_name(binding.value) {
      return true
    }
  }
  match program.body {
    Some(body) => expr_uses_qualified_type_name(body)
    None => false
  }
}

///|
fn narrow_positive_is_guard_type(original : Type, guard_type : Type) -> Type? {
  match original {
    UnionType(options) => {
      let narrowed : Array[Type] = []
      for option in options {
        if type_accepts(guard_type, option) {
          push_unique_type(narrowed, option)
        }
      }
      if narrowed.length() == 0 {
        None
      } else {
        Some(make_union_type(narrowed))
      }
    }
    NullableType(inner) =>
      if type_accepts(guard_type, inner) {
        Some(inner)
      } else if guard_type == NullType {
        Some(NullType)
      } else {
        None
      }
    _ =>
      if type_accepts(guard_type, original) {
        Some(original)
      } else if type_accepts(original, guard_type) {
        Some(guard_type)
      } else {
        None
      }
  }
}

///|
fn narrow_negative_is_guard_type(original : Type, guard_type : Type) -> Type? {
  match original {
    UnionType(options) => {
      let narrowed : Array[Type] = []
      let mut changed = false
      for option in options {
        if type_accepts(guard_type, option) {
          changed = true
        } else {
          push_unique_type(narrowed, option)
        }
      }
      if changed && narrowed.length() > 0 {
        Some(make_union_type(narrowed))
      } else {
        None
      }
    }
    NullableType(inner) =>
      if type_accepts(guard_type, inner) {
        Some(NullType)
      } else if guard_type == NullType {
        Some(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
fn push_narrowed_type_binding(
  name : String,
  guard_type : Type,
  positive : Bool,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match
    resolve_binding_type(
      name, bindings, env, type_env, source_cache, stack, diagnostics, resolve_import,
    ) {
    Some(original_type) => {
      let narrowed = if positive {
        narrow_positive_is_guard_type(original_type, guard_type)
      } else {
        narrow_negative_is_guard_type(original_type, guard_type)
      }
      match narrowed {
        Some(typ) => target_cache.push({ name, typ })
        None => ()
      }
    }
    None => ()
  }
}

///|
fn apply_positive_is_guard_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match expr {
    BinaryExpr(Is, Identifier(name), Identifier(type_name)) =>
      match type_from_annotation(type_name, type_env) {
        Some(guard_type) =>
          push_narrowed_type_binding(
            name, guard_type, true, bindings, env, type_env, source_cache, target_cache,
            stack, diagnostics, resolve_import,
          )
        None => ()
      }
    BinaryExpr(Equal, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(Equal, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(And, left, right) => {
      apply_positive_is_guard_expr(
        left, bindings, env, type_env, source_cache, target_cache, stack, diagnostics,
        resolve_import,
      )
      apply_positive_is_guard_expr(
        right, bindings, env, type_env, target_cache, target_cache, stack, diagnostics,
        resolve_import,
      )
    }
    _ => ()
  }
}

///|
fn apply_negative_is_guard_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[TypeBinding],
  type_env : Array[TypeBinding],
  source_cache : Array[TypeBinding],
  target_cache : Array[TypeBinding],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> TypecheckResult?,
) -> Unit {
  match expr {
    BinaryExpr(Is, Identifier(name), Identifier(type_name)) =>
      match type_from_annotation(type_name, type_env) {
        Some(guard_type) =>
          push_narrowed_type_binding(
            name, guard_type, false, bindings, env, type_env, source_cache, target_cache,
            stack, diagnostics, resolve_import,
          )
        None => ()
      }
    BinaryExpr(Equal, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(Equal, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        false,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, Identifier(name), NullLiteral) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    BinaryExpr(NotEqual, NullLiteral, Identifier(name)) =>
      push_narrowed_type_binding(
        name,
        NullType,
        true,
        bindings,
        env,
        type_env,
        source_cache,
        target_cache,
        stack,
        diagnostics,
        resolve_import,
      )
    _ => ()
  }
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
              value: LambdaExpr(
                function_decl.parameters,
                body,
                function_decl.return_type_name,
              ),
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
      None =>
        match property.value {
          Some(value) =>
            infer_expr_with_bindings(
              value,
              [],
              [],
              type_env,
              [],
              [],
              diagnostics,
              fn(_) { None },
            )
          None => UnknownType
        }
    }
    let member_type = match property.value {
      Some(_) => DefaultedType(typ)
      None => typ
    }
    members.push({ name: property.name, typ: member_type })
  }
  members
}

///|
fn class_methods_to_members(
  methods : Array[FunctionDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  let members : Array[TypeMember] = []
  for class_method in methods {
    members.push({
      name: class_method.name,
      typ: DefaultedType(
        function_signature_type(class_method, type_env, diagnostics),
      ),
    })
  }
  members
}

///|
fn class_decl_to_members(
  class_decl : ClassDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  let own_members = merge_type_members(
    class_properties_to_members(class_decl.properties, type_env, diagnostics),
    class_methods_to_members(class_decl.methods, type_env, diagnostics),
  )
  match class_decl.parent_name {
    Some(parent_name) =>
      match lookup_type(type_env, parent_name) {
        Some(ClassType(_, base_members)) =>
          merge_type_members(base_members, own_members)
        Some(_) => {
          diagnostics.push(Diagnostic::{
            message: "class \{class_decl.name} extends non-class \{parent_name}",
          })
          own_members
        }
        None => {
          diagnostics.push(Diagnostic::{
            message: "unknown type annotation \{parent_name}",
          })
          own_members
        }
      }
    None => own_members
  }
}

///|
fn collect_declared_types(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Array[TypeBinding] {
  collect_declared_types_with_imports(declarations, diagnostics, [])
}

///|
fn collect_declared_types_with_imports(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  imported_types : Array[TypeBinding],
) -> Array[TypeBinding] {
  let type_env = copy_type_bindings(imported_types)
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
            class_decl_to_members(class_decl, type_env, diagnostics),
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
fn type_exports_from_parse_result(parsed : ParseResult) -> Array[TypeExport] {
  let diagnostics : Array[Diagnostic] = []
  let type_env = collect_declared_types(
    parsed.program.declarations,
    diagnostics,
  )
  let exports : Array[TypeExport] = []
  for declaration in parsed.program.declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        match lookup_type(type_env, class_decl.name) {
          Some(typ) => exports.push({ name: class_decl.name, typ })
          None => ()
        }
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  exports
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
  parameters : Array[FunctionParameter],
  return_type_name : String?,
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
    let parameter = parameters[i]
    let parameter_type = match parameter.type_name {
      Some(type_name) =>
        match type_from_annotation(type_name, type_env) {
          Some(expected) =>
            if type_accepts(expected, argument_types[i]) {
              expected
            } else {
              diagnostics.push(Diagnostic::{
                message: "\{label} argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
              })
              return UnknownType
            }
          None => {
            diagnostics.push(Diagnostic::{
              message: "unknown type annotation \{type_name}",
            })
            UnknownType
          }
        }
      None => argument_types[i]
    }
    call_cache.push({ name: parameter.name, typ: parameter_type })
  }
  let inferred_return = infer_expr_with_bindings(
    body, bindings, env, type_env, call_cache, stack, diagnostics, resolve_import,
  )
  match return_type_name {
    Some(type_name) =>
      match type_from_annotation(type_name, type_env) {
        Some(expected) =>
          if type_accepts(expected, inferred_return) {
            expected
          } else {
            diagnostics.push(Diagnostic::{
              message: "\{label} return annotation \{type_name} does not accept \{render_type(inferred_return)}",
            })
            UnknownType
          }
        None => {
          diagnostics.push(Diagnostic::{
            message: "unknown type annotation \{type_name}",
          })
          UnknownType
        }
      }
    None => inferred_return
  }
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
    LambdaExpr(parameters, body, return_type_name) =>
      return infer_lambda_application(
        "function", parameters, return_type_name, body, arguments, bindings, env,
        type_env, cache, stack, diagnostics, resolve_import,
      )
    Identifier(name) =>
      match find_type_binding(bindings, name) {
        Some(binding) =>
          match binding.value {
            LambdaExpr(parameters, body, return_type_name) =>
              return infer_lambda_application(
                "function \{name}",
                parameters,
                return_type_name,
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
    NullableType(FunctionType(parameter_types, return_type)) => {
      let inferred_return = infer_function_type_call(
        parameter_types, return_type, arguments, bindings, env, type_env, cache,
        stack, diagnostics, resolve_import,
      )
      if inferred_return == UnknownType {
        UnknownType
      } else {
        nullable_type(inferred_return)
      }
    }
    NullType =>
      match callee {
        SafeMemberAccess(_, _) => NullType
        _ => {
          diagnostics.push(Diagnostic::{ message: "call expects Function" })
          UnknownType
        }
      }
    UnknownType => UnknownType
    _ => {
      diagnostics.push(Diagnostic::{ message: "call expects Function" })
      UnknownType
    }
  }
}

///|
fn infer_boolean_condition_expr(
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
    BinaryExpr(And, left_expr, right_expr) => {
      let left = infer_boolean_condition_expr(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right_cache = copy_type_bindings(cache)
      apply_positive_is_guard_expr(
        left_expr, bindings, env, type_env, cache, right_cache, stack, diagnostics,
        resolve_import,
      )
      let right = infer_boolean_condition_expr(
        right_expr, bindings, env, type_env, right_cache, stack, diagnostics, resolve_import,
      )
      if left == BoolType && right == BoolType {
        BoolType
      } else {
        diagnostics.push(Diagnostic::{
          message: "operator && expects Boolean operands",
        })
        UnknownType
      }
    }
    BinaryExpr(Or, left_expr, right_expr) => {
      let left = infer_boolean_condition_expr(
        left_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      let right_cache = copy_type_bindings(cache)
      apply_negative_is_guard_expr(
        left_expr, bindings, env, type_env, cache, right_cache, stack, diagnostics,
        resolve_import,
      )
      let right = infer_boolean_condition_expr(
        right_expr, bindings, env, type_env, right_cache, stack, diagnostics, resolve_import,
      )
      if left == BoolType && right == BoolType {
        BoolType
      } else {
        diagnostics.push(Diagnostic::{
          message: "operator || expects Boolean operands",
        })
        UnknownType
      }
    }
    _ =>
      infer_expr_with_bindings(
        expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
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
    TypedObjectLiteral(type_name, members) => {
      let inferred = ObjectType(
        infer_object_members(
          members, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ),
      )
      apply_type_annotation(Some(type_name), inferred, type_env, diagnostics)
    }
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
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
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
    SafeMemberAccess(target_expr, member_name) =>
      match
        infer_expr_with_bindings(
          target_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        ObjectType(members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        NullableType(ObjectType(members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        NullableType(ClassType(_, members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown member \{member_name}",
              })
              UnknownType
            }
          }
        NullType => NullType
        UnknownType => UnknownType
        _ => {
          diagnostics.push(Diagnostic::{
            message: "safe member access expects Object",
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
    LambdaExpr(parameters, _, return_type_name) => {
      let return_type = match return_type_name {
        Some(type_name) =>
          match type_from_annotation(type_name, type_env) {
            Some(typ) => typ
            None => {
              diagnostics.push(Diagnostic::{
                message: "unknown type annotation \{type_name}",
              })
              UnknownType
            }
          }
        None => UnknownType
      }
      FunctionType(
        function_parameter_types(parameters, type_env, diagnostics),
        return_type,
      )
    }
    NonNullExpr(inner_expr) =>
      match
        infer_expr_with_bindings(
          inner_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
        ) {
        NullableType(inner) => inner
        NullType => {
          diagnostics.push(Diagnostic::{
            message: "non-null assertion rejects Null",
          })
          UnknownType
        }
        UnknownType => UnknownType
        typ => typ
      }
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
        match right_expr {
          Identifier(name) =>
            match type_from_annotation(name, type_env) {
              Some(_) => return BoolType
              None => {
                diagnostics.push(Diagnostic::{
                  message: "unknown type annotation \{name}",
                })
                return UnknownType
              }
            }
          _ => return BoolType
        }
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
      if op == And || op == Or {
        return infer_boolean_condition_expr(
          BinaryExpr(op, left_expr, right_expr),
          bindings,
          env,
          type_env,
          cache,
          stack,
          diagnostics,
          resolve_import,
        )
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
        And | Or => panic()
        NullCoalesce =>
          if left == NullType {
            right
          } else if left is NullableType(inner) {
            if right == NullType {
              left
            } else if type_accepts(inner, right) {
              inner
            } else if type_accepts(left, right) {
              left
            } else {
              UnknownType
            }
          } else if right == NullType || left == right {
            left
          } else {
            UnknownType
          }
        Is | As | Pipe => panic()
      }
    }
    ConditionalExpr(condition_expr, then_expr, else_expr) => {
      let condition = infer_boolean_condition_expr(
        condition_expr, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
      if condition != BoolType {
        diagnostics.push(Diagnostic::{ message: "if condition expects Boolean" })
      }
      let then_cache = copy_type_bindings(cache)
      let else_cache = copy_type_bindings(cache)
      apply_positive_is_guard_expr(
        condition_expr, bindings, env, type_env, cache, then_cache, stack, diagnostics,
        resolve_import,
      )
      apply_negative_is_guard_expr(
        condition_expr, bindings, env, type_env, cache, else_cache, stack, diagnostics,
        resolve_import,
      )
      let then_type = infer_expr_with_bindings(
        then_expr, bindings, env, type_env, then_cache, stack, diagnostics, resolve_import,
      )
      let else_type = infer_expr_with_bindings(
        else_expr, bindings, env, type_env, else_cache, stack, diagnostics, resolve_import,
      )
      common_type([then_type, else_type])
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
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> Type {
  let env : Array[TypeBinding] = []
  let imported_types = if program_uses_qualified_type_name(program) {
    imported_type_bindings(program.imports, resolve_import_types)
  } else {
    []
  }
  let type_env = collect_declared_types_with_imports(
    program.declarations,
    diagnostics,
    imported_types,
  )
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
  typecheck_parsed_with_import_details(parsed, resolve_import, fn(_) { None })
}

///|
fn typecheck_parsed_with_import_details(
  parsed : ParseResult,
  resolve_import : (String) -> TypecheckResult?,
  resolve_import_types : (String) -> Array[TypeExport]?,
) -> TypecheckResult {
  let diagnostics = parsed.diagnostics
  if diagnostics.length() > 0 {
    return TypeError(diagnostics)
  }
  let typ = infer_program(
    parsed.program,
    diagnostics,
    resolve_import,
    resolve_import_types,
  )
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
