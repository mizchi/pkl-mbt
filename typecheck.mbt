///|
pub(all) enum Type {
  IntType
  // PKL-092: Float numeric type. Mixed Int / Float arithmetic widens to
  // Float; constraint predicates accept both via the implicit `Number`
  // hierarchy.
  FloatType
  BoolType
  StringType
  NullType
  ObjectType(Array[TypeMember])
  ClassType(String, Array[TypeMember])
  ListingType(Array[Type])
  MappingType(Array[TypeEntry])
  FunctionType(Array[Type], Type)
  ConstrainedType(String, Type)
  UnionType(Array[Type])
  NullableType(Type)
  DefaultedType(Type)
  // PKL-110: free type parameter in a generic class / function context.
  // Carries the parameter name (e.g. "T") so the substitution pass at the
  // call site / class literal can match `TypeVariable("T")` to a concrete
  // argument type and rewrite the surrounding signature in place.
  TypeVariable(String)
  // PKL-133: Pkl's top type. Every value flows through `Any`. Distinct
  // from `UnknownType` (parser / inference fallback) so render output
  // surfaces as `Any` exactly, and so the typechecker can later
  // distinguish "user wrote Any explicitly" from "we lost track of the
  // type". Accept-any on both sides of `type_accepts`.
  AnyType
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
  // PKL-115: when this binding came from a generic typealias declaration
  // (`typealias Box<T> = Listing<T>`), capture the original decl so that
  // `type_from_annotation` can substitute the parameter list at the
  // instantiation site (`Box<Int>` → `Listing<Int>`). `None` for
  // ordinary bindings.
  alias_decl : TypeAliasDecl?
  // PKL-116: when this binding represents a generic type parameter with
  // a declared bound (`function pick<T : Number>(...)` or
  // `class Box<T : Number>`), capture the resolved bound Type so
  // `unify_for_substitution` can check that the concrete argument flows
  // through `type_accepts(bound, actual)`. `None` for ordinary
  // bindings and unbounded type parameters.
  bound : Type?
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
    ConstrainedType(_, inner) => inner
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
    FloatType => "Float"
    BoolType => "Boolean"
    StringType => "String"
    NullType => "Null"
    ObjectType(_) => "Object"
    ClassType(name, _) => name
    ListingType(_) => "Listing"
    MappingType(_) => "Mapping"
    FunctionType(_, _) => "Function"
    ConstrainedType(_, inner) => render_type(inner)
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
    TypeVariable(name) => name
    AnyType => "Any"
    UnknownType => "Unknown"
  }
}

///|
fn builtin_type_from_annotation(name : String) -> Type? {
  match name {
    "Int" => Some(IntType)
    "Float" => Some(FloatType)
    // PKL-092: `Number` is the union of `Int` and `Float`. The typechecker
    // expresses it as a union so existing narrowing logic (UnionType
    // members, is-guards) keeps working.
    "Number" => Some(UnionType([IntType, FloatType]))
    "String" => Some(StringType)
    "Boolean" => Some(BoolType)
    "Bool" => Some(BoolType)
    "Null" => Some(NullType)
    "Object" => Some(ObjectType([]))
    "Listing" => Some(ListingType([]))
    "Mapping" => Some(MappingType([]))
    // PKL-134: `List<T>` is Pkl's immutable indexed collection; pkl-mbt
    // collapses Listing / List into the same runtime value so the
    // typechecker treats them as the same shape. Once the value
    // variants split (PKL-119) this alias becomes a distinct variant.
    "List" => Some(ListingType([]))
    // PKL-133: top type. Maps to its own `AnyType` variant so render
    // output stays as `Any` instead of collapsing to `Unknown`.
    "Any" => Some(AnyType)
    // PKL-137: a quoted string literal in type position
    // (`typealias Severity = "critical" | "major"`) is Apple Pkl's
    // string-literal type. pkl-mbt approximates each literal as the
    // base `StringType` for now — the union machinery still flags
    // mismatched non-string operands, and the `==` / `is` paths fall
    // through to runtime equality on the literal value. A future
    // slice can introduce a refined `StringLiteralType("...")` variant
    // if call sites need the narrowed shape.
    _ =>
      if name.length() >= 2 && name.has_prefix("\"") && name.has_suffix("\"") {
        Some(StringType)
      } else {
        None
      }
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
fn constrained_type_base_text(name : String) -> String? {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for i = 0; i < name.length(); i = i + 1 {
    let char = name[i].to_int().unsafe_to_char()
    if char == '(' && parens == 0 && brackets == 0 && angles == 0 {
      if i == 0 {
        return None
      }
      return if constrained_type_suffix_is_balanced(name, i) {
        Some(String::unsafe_substring(name, start=0, end=i))
      } else {
        None
      }
    }
    if char == '(' {
      parens += 1
    } else if char == ')' && parens > 0 {
      parens -= 1
    } else if char == '[' {
      brackets += 1
    } else if char == ']' && brackets > 0 {
      brackets -= 1
    } else if char == '<' && parens == 0 && brackets == 0 {
      angles += 1
    } else if char == '>' && parens == 0 && brackets == 0 && angles > 0 {
      angles -= 1
    }
  }
  None
}

///|
fn constrained_type_suffix_is_balanced(name : String, start : Int) -> Bool {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for i = start; i < name.length(); i = i + 1 {
    let char = name[i].to_int().unsafe_to_char()
    if char == '(' {
      parens += 1
    } else if char == ')' {
      parens -= 1
      if parens < 0 {
        return false
      }
    } else if char == '[' {
      brackets += 1
    } else if char == ']' {
      brackets -= 1
      if brackets < 0 {
        return false
      }
    } else if char == '<' && parens == 0 && brackets == 0 {
      angles += 1
    } else if char == '>' && parens == 0 && brackets == 0 {
      angles -= 1
      if angles < 0 {
        return false
      }
    }
  }
  parens == 0 && brackets == 0 && angles == 0
}

///|
fn type_from_annotation(name : String, type_env : Array[TypeBinding]) -> Type? {
  // PKL-137: strip a balanced outer paren wrapper before the dispatch
  // table runs. Parser-emitted type text retains the parens (`("a" |
  // "b")` survives intact through `parse_type_text`), so an alias like
  // `typealias Severity = ("critical" | "major")` arrives here with the
  // outer parens — `split_top_level_union_choices` then keeps the `|`
  // inside parens and refuses to split, which makes the whole thing
  // look like a single unknown name.
  if name.has_prefix("(") && name.has_suffix(")") {
    let mut depth = 0
    let mut wraps_whole = true
    for i = 0; i < name.length(); i = i + 1 {
      let c = name[i].to_int().unsafe_to_char()
      if c == '(' {
        depth = depth + 1
      } else if c == ')' {
        depth = depth - 1
        if depth == 0 && i < name.length() - 1 {
          wraps_whole = false
          break
        }
      }
    }
    if wraps_whole && depth == 0 {
      let inner = String::unsafe_substring(name, start=1, end=name.length() - 1)
      return type_from_annotation(inner, type_env)
    }
  }
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
  match constrained_type_base_text(name) {
    Some(base_name) =>
      match type_from_annotation(base_name, type_env) {
        Some(typ) => return Some(typ)
        None => return None
      }
    None => ()
  }
  match generic_argument_text(name, "Listing") {
    Some(inner_text) =>
      match type_from_annotation(inner_text, type_env) {
        Some(inner) => return Some(ListingType([inner]))
        None => return None
      }
    None => ()
  }
  // PKL-134: `List<T>` aliases `Listing<T>` until the value variants split.
  match generic_argument_text(name, "List") {
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
  // PKL-115: generic typealias instantiation. `Box<Int>` looks up the
  // alias binding for `Box`, matches its declared type parameters
  // against the provided arguments, substitutes the parameter names in
  // the recorded target text, and re-evaluates the resulting type.
  match try_generic_alias_substitution(name, type_env) {
    Some(typ) => return Some(typ)
    None => ()
  }
  match builtin_type_from_annotation(name) {
    Some(typ) => Some(typ)
    None => lookup_type(type_env, name)
  }
}

///|
fn try_generic_alias_substitution(
  name : String,
  type_env : Array[TypeBinding],
) -> Type? {
  match try_split_generic_name(name) {
    Some((base, args)) =>
      for binding in type_env {
        if binding.name == base {
          match binding.alias_decl {
            Some(decl) =>
              if decl.type_parameters.length() == args.length() {
                let substituted = substitute_typealias_target_text(
                  decl.target,
                  decl.type_parameters,
                  args,
                )
                return type_from_annotation(substituted, type_env)
              }
            None => ()
          }
        }
      } nobreak {
        None
      }
    None => None
  }
}

///|
fn try_split_generic_name(name : String) -> (String, Array[String])? {
  let mut idx = -1
  let mut parens = 0
  let mut brackets = 0
  for i = 0; i < name.length(); i = i + 1 {
    let c = name[i].to_int().unsafe_to_char()
    if c == '(' {
      parens += 1
    } else if c == ')' && parens > 0 {
      parens -= 1
    } else if c == '[' {
      brackets += 1
    } else if c == ']' && brackets > 0 {
      brackets -= 1
    } else if c == '<' && parens == 0 && brackets == 0 {
      idx = i
      break
    }
  }
  if idx <= 0 || !name.has_suffix(">") {
    return None
  }
  let base = String::unsafe_substring(name, start=0, end=idx)
  let inner = String::unsafe_substring(
    name,
    start=idx + 1,
    end=name.length() - 1,
  )
  let args = split_top_level_generic_arguments(inner)
  Some((base, args))
}

///|
fn is_typealias_identifier_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_typealias_identifier_continue(c : Char) -> Bool {
  is_typealias_identifier_start(c) || (c >= '0' && c <= '9')
}

///|
fn substitute_typealias_target_text(
  target : String,
  parameters : Array[String],
  arguments : Array[String],
) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < target.length() {
    let c = target[i].to_int().unsafe_to_char()
    if is_typealias_identifier_start(c) {
      let mut end = i + 1
      while end < target.length() &&
            is_typealias_identifier_continue(
              target[end].to_int().unsafe_to_char(),
            ) {
        end += 1
      }
      let token = String::unsafe_substring(target, start=i, end~)
      let mut replaced = false
      for j = 0; j < parameters.length(); j = j + 1 {
        if !replaced && token == parameters[j] {
          buf.write_string(arguments[j])
          replaced = true
        }
      }
      if !replaced {
        buf.write_string(token)
      }
      i = end
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  buf.to_string()
}

///|
fn constrained_type_source_name_with_depth(
  name : String,
  type_env : Array[TypeBinding],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  if pkl_constrained_type_annotation_has_supported_constraint(name) {
    return Some(name)
  }
  match lookup_type(type_env, name) {
    Some(ConstrainedType(source_name, _)) =>
      constrained_type_source_name_with_depth(source_name, type_env, depth + 1)
    _ => None
  }
}

///|
fn constrained_type_source_name(
  name : String,
  type_env : Array[TypeBinding],
) -> String? {
  constrained_type_source_name_with_depth(name, type_env, 0)
}

///|
fn constrained_type_annotation_expr_rejection_message(
  type_name : String?,
  expr : Expr,
  type_env : Array[TypeBinding],
) -> String? {
  match type_name {
    Some(display_name) =>
      match constrained_type_source_name(display_name, type_env) {
        Some(source_name) =>
          pkl_constrained_type_annotation_expr_rejection_message_from_source(
            display_name, source_name, expr,
          )
        None => None
      }
    None => None
  }
}

///|
fn push_constrained_type_annotation_expr_diagnostic(
  type_name : String?,
  expr : Expr,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match
    constrained_type_annotation_expr_rejection_message(
      type_name, expr, type_env,
    ) {
    Some(message) => diagnostics.push(diag(message))
    None => ()
  }
}

///|
fn push_user_defined_constrained_type_annotation_expr_diagnostic(
  type_name : String?,
  expr : Expr,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match
    pkl_user_defined_constrained_type_annotation_expr_rejection_message(
      type_name, expr, declarations,
    ) {
    Some(message) => diagnostics.push(diag(message))
    None => ()
  }
}

///|
fn typecheck_lookup_class_decl(
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
fn typecheck_class_property_annotation_with_depth(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  match typecheck_lookup_class_decl(declarations, class_name) {
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
            typecheck_class_property_annotation_with_depth(
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
fn typecheck_class_property_annotation(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
) -> String? {
  typecheck_class_property_annotation_with_depth(
    declarations, class_name, property_name, 0,
  )
}

///|
fn typecheck_class_property_constraint_expr_rejection_message(
  class_name : String,
  property_name : String,
  expr : Expr,
  declarations : Array[Declaration],
) -> String? {
  match
    typecheck_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      let display_name = "\{class_name} member \{property_name}"
      match
        pkl_constrained_type_annotation_expr_rejection_message_from_source(
          display_name, source_name, expr,
        ) {
        Some(message) => Some(message)
        None =>
          pkl_user_defined_constrained_type_annotation_expr_rejection_message_from_source(
            display_name, source_name, expr, declarations,
          )
      }
    }
    None => None
  }
}

///|
fn push_constrained_callable_return_body_diagnostic(
  label : String,
  return_type_name : String?,
  body : Expr,
  type_env : Array[TypeBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match
    constrained_type_annotation_expr_rejection_message(
      return_type_name, body, type_env,
    ) {
    Some(message) => diagnostics.push(diag("\{label} return \{message}"))
    None =>
      match
        pkl_user_defined_constrained_type_annotation_expr_rejection_message(
          return_type_name, body, declarations,
        ) {
        Some(message) => diagnostics.push(diag("\{label} return \{message}"))
        None => ()
      }
  }
}

///|
fn push_constrained_callable_return_body_diagnostics(
  declarations : Array[Declaration],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for declaration in declarations {
    match declaration {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) =>
            push_constrained_callable_return_body_diagnostic(
              "function \{function_decl.name}",
              function_decl.return_type_name,
              body,
              type_env,
              declarations,
              diagnostics,
            )
          None => ()
        }
      ClassDeclaration(class_decl) =>
        for class_method in class_decl.methods {
          match class_method.body {
            Some(body) =>
              push_constrained_callable_return_body_diagnostic(
                "method \{class_decl.name}.\{class_method.name}",
                class_method.return_type_name,
                body,
                type_env,
                declarations,
                diagnostics,
              )
            None => ()
          }
        }
      TypeAliasDeclaration(_) => ()
    }
  }
}

///|
fn push_constrained_class_property_expr_diagnostics(
  expr : Expr,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match expr {
    TypedObjectLiteral(class_name, members) =>
      for field in members {
        match
          typecheck_class_property_constraint_expr_rejection_message(
            class_name,
            field.name,
            field.value,
            declarations,
          ) {
          Some(message) => diagnostics.push(diag(message))
          None => ()
        }
        push_constrained_class_property_expr_diagnostics(
          field.value,
          declarations,
          diagnostics,
        )
      }
    ObjectLiteral(members) =>
      for field in members {
        push_constrained_class_property_expr_diagnostics(
          field.value,
          declarations,
          diagnostics,
        )
      }
    AmendExpr(base, members) => {
      push_constrained_class_property_expr_diagnostics(
        base, declarations, diagnostics,
      )
      for field in members {
        push_constrained_class_property_expr_diagnostics(
          field.value,
          declarations,
          diagnostics,
        )
      }
    }
    ListingLiteral(elements) =>
      for element in elements {
        push_constrained_class_property_expr_diagnostics(
          element, declarations, diagnostics,
        )
      }
    MappingLiteral(entries) =>
      for entry in entries {
        push_constrained_class_property_expr_diagnostics(
          entry.key,
          declarations,
          diagnostics,
        )
        push_constrained_class_property_expr_diagnostics(
          entry.value,
          declarations,
          diagnostics,
        )
      }
    CallExpr(callee, arguments) => {
      push_constrained_class_property_expr_diagnostics(
        callee, declarations, diagnostics,
      )
      for argument in arguments {
        push_constrained_class_property_expr_diagnostics(
          argument, declarations, diagnostics,
        )
      }
    }
    MemberAccess(target, _) | SafeMemberAccess(target, _) =>
      push_constrained_class_property_expr_diagnostics(
        target, declarations, diagnostics,
      )
    SubscriptAccess(target, key) => {
      push_constrained_class_property_expr_diagnostics(
        target, declarations, diagnostics,
      )
      push_constrained_class_property_expr_diagnostics(
        key, declarations, diagnostics,
      )
    }
    NonNullExpr(inner) | UnaryExpr(_, inner) =>
      push_constrained_class_property_expr_diagnostics(
        inner, declarations, diagnostics,
      )
    BinaryExpr(_, left, right) => {
      push_constrained_class_property_expr_diagnostics(
        left, declarations, diagnostics,
      )
      push_constrained_class_property_expr_diagnostics(
        right, declarations, diagnostics,
      )
    }
    ConditionalExpr(condition, truthy, falsy) => {
      push_constrained_class_property_expr_diagnostics(
        condition, declarations, diagnostics,
      )
      push_constrained_class_property_expr_diagnostics(
        truthy, declarations, diagnostics,
      )
      push_constrained_class_property_expr_diagnostics(
        falsy, declarations, diagnostics,
      )
    }
    LambdaExpr(_, body, _) =>
      push_constrained_class_property_expr_diagnostics(
        body, declarations, diagnostics,
      )
    _ => ()
  }
}

///|
fn push_constrained_class_property_default_diagnostics(
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        for property in class_decl.properties {
          match property.value {
            Some(default_expr) =>
              match
                typecheck_class_property_constraint_expr_rejection_message(
                  class_decl.name,
                  property.name,
                  default_expr,
                  declarations,
                ) {
                Some(message) => diagnostics.push(diag(message))
                None => ()
              }
            None => ()
          }
        }
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
}

///|
/// PKL-117: enforce two structural inheritance rules on every class
/// declared locally in `declarations`:
///
///   1. Abstract-method coverage. When a concrete (non-abstract)
///      class extends an ancestor chain containing at least one
///      abstract method, the concrete class — or some intermediate
///      ancestor between the abstract method's declaring class and
///      the concrete class — must provide a method with the same
///      name. Otherwise the concrete class is unsound: instantiation
///      would resolve a method call on an absent body.
///
///   2. Override-direction subtype rules. When a child class
///      overrides a parent method (matching by name), the return
///      type must be covariant (`child_return <: parent_return`)
///      and each parameter type must be contravariant
///      (`parent_param <: child_param`). The check uses the
///      existing `type_accepts` subtype relation so the rules track
///      the standard Liskov substitution principle.
///
/// Both checks walk only locally-declared parents because the
/// imported-parent case requires cross-module member visibility
/// that PKL-118 still tracks separately.
fn push_inheritance_hardening_diagnostics(
  declarations : Array[Declaration],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let by_name : Map[String, ClassDecl] = Map([], capacity=8)
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => by_name[class_decl.name] = class_decl
      _ => ()
    }
  }
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => {
        if !class_decl.is_abstract {
          enforce_abstract_method_coverage(class_decl, by_name, diagnostics)
        }
        enforce_method_override_directions(
          class_decl, by_name, type_env, diagnostics,
        )
      }
      _ => ()
    }
  }
}

///|
/// Walk the parent chain collecting abstract methods that the
/// concrete `class_decl` (or some ancestor below the declaring
/// class) must override. Methods present in any descendant between
/// the abstract declaration and `class_decl` count as overrides.
fn enforce_abstract_method_coverage(
  class_decl : ClassDecl,
  by_name : Map[String, ClassDecl],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let descendant_methods : Array[String] = []
  for class_method in class_decl.methods {
    descendant_methods.push(class_method.name)
  }
  let mut current : ClassDecl? = match class_decl.parent_name {
    Some(name) => by_name.get(name)
    None => None
  }
  while current is Some(parent_decl) {
    for parent_method in parent_decl.methods {
      if parent_method.is_abstract &&
        !array_contains_string(descendant_methods, parent_method.name) {
        diagnostics.push(
          diag(
            "Class `\{class_decl.name}` does not implement abstract method `\{parent_method.name}` inherited from `\{parent_decl.name}`.",
          ),
        )
      }
    }
    for parent_method in parent_decl.methods {
      if !array_contains_string(descendant_methods, parent_method.name) {
        descendant_methods.push(parent_method.name)
      }
    }
    current = match parent_decl.parent_name {
      Some(name) => by_name.get(name)
      None => None
    }
  }
}

///|
/// For each method in `class_decl`, look up a parent method with the
/// same name and verify return-type covariance and parameter-type
/// contravariance. Unresolved type annotations (`Cannot find type`)
/// don't push a duplicate diagnostic — they were already surfaced by
/// the class-member typecheck and skipping here keeps the noise
/// floor low.
fn enforce_method_override_directions(
  class_decl : ClassDecl,
  by_name : Map[String, ClassDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for class_method in class_decl.methods {
    let parent_method = find_inherited_method(
      class_decl,
      class_method.name,
      by_name,
    )
    match parent_method {
      Some((parent_decl, ancestor_method)) => {
        // Return type: covariant. Child must be a subtype of parent.
        match
          (ancestor_method.return_type_name, class_method.return_type_name) {
          (Some(parent_ret), Some(child_ret)) =>
            match
              (
                type_from_annotation(parent_ret, type_env),
                type_from_annotation(child_ret, type_env),
              ) {
              (Some(parent_type), Some(child_type)) =>
                if !type_accepts(parent_type, child_type) {
                  diagnostics.push(
                    diag(
                      "Method `\{class_decl.name}.\{class_method.name}` return type `\{child_ret}` is not a subtype of `\{parent_decl.name}.\{ancestor_method.name}` return type `\{parent_ret}`.",
                    ),
                  )
                }
              _ => ()
            }
          _ => ()
        }
        let parent_params = ancestor_method.parameters
        let child_params = class_method.parameters
        if parent_params.length() == child_params.length() {
          for i = 0; i < parent_params.length(); i = i + 1 {
            match (parent_params[i].type_name, child_params[i].type_name) {
              (Some(parent_param), Some(child_param)) =>
                match
                  (
                    type_from_annotation(parent_param, type_env),
                    type_from_annotation(child_param, type_env),
                  ) {
                  (Some(parent_type), Some(child_type)) =>
                    if !type_accepts(child_type, parent_type) {
                      diagnostics.push(
                        diag(
                          "Method `\{class_decl.name}.\{class_method.name}` parameter `\{child_params[i].name}` type `\{child_param}` is not a supertype of `\{parent_decl.name}.\{ancestor_method.name}` parameter type `\{parent_param}`.",
                        ),
                      )
                    }
                  _ => ()
                }
              _ => ()
            }
          }
        }
      }
      None => ()
    }
  }
}

///|
/// Look up the nearest ancestor that declares a method named
/// `method_name`. Returns the declaring class along with the method
/// itself so the diagnostic can name both. `None` when no ancestor
/// declares the method (this method is a new addition, not an
/// override).
fn find_inherited_method(
  class_decl : ClassDecl,
  method_name : String,
  by_name : Map[String, ClassDecl],
) -> (ClassDecl, FunctionDecl)? {
  let mut current : ClassDecl? = match class_decl.parent_name {
    Some(name) => by_name.get(name)
    None => None
  }
  while current is Some(parent_decl) {
    for parent_method in parent_decl.methods {
      if parent_method.name == method_name {
        return Some((parent_decl, parent_method))
      }
    }
    current = match parent_decl.parent_name {
      Some(name) => by_name.get(name)
      None => None
    }
  }
  None
}

///|
fn array_contains_string(items : Array[String], needle : String) -> Bool {
  for item in items {
    if item == needle {
      return true
    }
  }
  false
}

///|
fn type_from_alias_target_annotation(
  name : String,
  type_env : Array[TypeBinding],
) -> Type? {
  match type_from_annotation(name, type_env) {
    Some(typ) =>
      if pkl_constrained_type_annotation_has_supported_constraint(name) {
        Some(ConstrainedType(name, typ))
      } else {
        Some(typ)
      }
    None => None
  }
}

///|
fn parameter_type_from_annotation(
  name : String,
  type_env : Array[TypeBinding],
) -> Type? {
  match type_from_annotation(name, type_env) {
    Some(typ) =>
      if pkl_constrained_type_annotation_has_supported_constraint(name) ||
        typ is ConstrainedType(_, _) {
        Some(ConstrainedType(name, member_contract_type(typ)))
      } else {
        Some(typ)
      }
    None => None
  }
}

///|
fn type_accepts(expected : Type, inferred : Type) -> Bool {
  if expected == inferred {
    return true
  }
  match (expected, inferred) {
    (UnknownType, _) => true
    // PKL-110: a free type parameter accepts any incoming type at
    // unification time. The substitution pass at the call site fills in
    // the concrete type before the return value flows on; if no call site
    // exists (e.g. the body refers to T directly) it stays free.
    (TypeVariable(_), _) => true
    (_, TypeVariable(_)) => true
    // PKL-133: `Any` is Pkl's top type — every value flows through it.
    // The relation is symmetric so the same value can flow into and out
    // of `Any` (e.g. `x: Any = 5` and `n: Int = x as Int` once `as` lands).
    (AnyType, _) => true
    (_, AnyType) => true
    (ConstrainedType(_, expected_inner), actual) =>
      type_accepts(expected_inner, actual)
    (expected, ConstrainedType(_, actual_inner)) =>
      type_accepts(expected, actual_inner)
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
    // PKL-137: an empty `new {}` literal infers to `ObjectType([])` at
    // parse time. PKL-138's eval-side coercion projects the runtime
    // value to `ListingValue([])` / `MappingValue([])` based on the
    // binding annotation; mirror the same coercion here so the
    // typechecker accepts `tests: Listing<Test> = new {}` and
    // `m: Mapping<K, V> = new {}` cleanly.
    (ListingType(_), ObjectType(members)) => members.length() == 0
    (MappingType(_), ObjectType(members)) => members.length() == 0
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
// PKL-113: Equality (`==` / `!=`) admits a wider compatibility relation
// than `type_accepts`. Two operands typecheck under equality when they
// share a base shape: same primitive, numeric mix (Int / Float),
// nullable / non-null with matching base, or any structural pair where
// runtime equality is meaningful (object / class, listing / listing).
// The relation stays symmetric — `a == b` and `b == a` must agree —
// so the helper normalizes wrappers (`ConstrainedType`, `DefaultedType`)
// before pattern-matching.
fn equality_compatible(left : Type, right : Type) -> Bool {
  let l = equality_unwrap_type(left)
  let r = equality_unwrap_type(right)
  if l == r {
    return true
  }
  match (l, r) {
    (UnknownType, _) | (_, UnknownType) => true
    (TypeVariable(_), _) | (_, TypeVariable(_)) => true
    // PKL-133: `Any` participates in equality on either side.
    (AnyType, _) | (_, AnyType) => true
    (NullType, NullableType(_)) | (NullableType(_), NullType) => true
    (NullableType(inner), other) | (other, NullableType(inner)) =>
      equality_compatible(inner, other)
    (IntType, FloatType) | (FloatType, IntType) => true
    (ClassType(name_l, _), ClassType(name_r, _)) => name_l == name_r
    (ClassType(_, _), ObjectType(_)) | (ObjectType(_), ClassType(_, _)) => true
    (ObjectType(_), ObjectType(_)) => true
    (ListingType(_), ListingType(_)) => true
    (MappingType(_), MappingType(_)) => true
    (UnionType(options), other) | (other, UnionType(options)) => {
      let mut ok = false
      for option in options {
        if equality_compatible(option, other) {
          ok = true
        }
      }
      ok
    }
    _ => false
  }
}

///|
fn equality_unwrap_type(typ : Type) -> Type {
  match typ {
    ConstrainedType(_, inner) => equality_unwrap_type(inner)
    DefaultedType(inner) => equality_unwrap_type(inner)
    _ => typ
  }
}

///|
// PKL-110: Substitution table for generic type parameters. A pair
// `(name, typ)` means "every TypeVariable(name) site rewrites to typ".
// Built incrementally by `unify_for_substitution` and consumed by
// `substitute_type`.
priv struct TypeSubstitution {
  name : String
  typ : Type
}

///|
fn substitution_lookup(subs : Array[TypeSubstitution], name : String) -> Type? {
  let mut found : Type? = None
  for entry in subs {
    if entry.name == name {
      found = Some(entry.typ)
    }
  }
  found
}

///|
fn substitute_type_member(
  field : TypeMember,
  subs : Array[TypeSubstitution],
) -> TypeMember {
  { name: field.name, typ: substitute_type(field.typ, subs) }
}

///|
fn substitute_type_entry(
  entry : TypeEntry,
  subs : Array[TypeSubstitution],
) -> TypeEntry {
  {
    key: substitute_type(entry.key, subs),
    value: substitute_type(entry.value, subs),
  }
}

///|
fn substitute_type(typ : Type, subs : Array[TypeSubstitution]) -> Type {
  if subs.length() == 0 {
    return typ
  }
  match typ {
    TypeVariable(name) =>
      match substitution_lookup(subs, name) {
        Some(resolved) => resolved
        None => typ
      }
    ObjectType(members) =>
      ObjectType(members.map(fn(m) { substitute_type_member(m, subs) }))
    ClassType(name, members) =>
      ClassType(name, members.map(fn(m) { substitute_type_member(m, subs) }))
    ListingType(items) =>
      ListingType(items.map(fn(t) { substitute_type(t, subs) }))
    MappingType(entries) =>
      MappingType(entries.map(fn(e) { substitute_type_entry(e, subs) }))
    FunctionType(parameters, ret) =>
      FunctionType(
        parameters.map(fn(t) { substitute_type(t, subs) }),
        substitute_type(ret, subs),
      )
    ConstrainedType(name, inner) =>
      ConstrainedType(name, substitute_type(inner, subs))
    UnionType(options) =>
      UnionType(options.map(fn(t) { substitute_type(t, subs) }))
    NullableType(inner) => NullableType(substitute_type(inner, subs))
    DefaultedType(inner) => DefaultedType(substitute_type(inner, subs))
    _ => typ
  }
}

///|
fn record_substitution(
  subs : Array[TypeSubstitution],
  name : String,
  typ : Type,
) -> Unit {
  // First binding wins. Later mismatches stay silent here — the surrounding
  // type_accepts check is the diagnostic surface, this pass only collects.
  match substitution_lookup(subs, name) {
    Some(_) => ()
    None => subs.push({ name, typ })
  }
}

///|
fn unify_for_substitution(
  expected : Type,
  actual : Type,
  subs : Array[TypeSubstitution],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match (expected, actual) {
    (TypeVariable(name), _) => {
      // PKL-116: when the parameter carries a declared bound, check
      // that the concrete argument flows through `type_accepts(bound,
      // actual)`. First-binding-wins still applies to the substitution
      // table itself; bound rejection is independent of binding
      // recording so the diagnostic surface stays clear.
      for binding in type_env {
        if binding.name == name {
          match binding.bound {
            Some(bound_type) =>
              if !type_accepts(bound_type, actual) {
                diagnostics.push(
                  diag(
                    "type parameter \{name} bound \{render_type(bound_type)} rejects \{render_type(actual)}",
                  ),
                )
              }
            None => ()
          }
        }
      }
      record_substitution(subs, name, actual)
    }
    (ConstrainedType(_, expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (_, ConstrainedType(_, actual_inner)) =>
      unify_for_substitution(
        expected, actual_inner, subs, type_env, diagnostics,
      )
    (DefaultedType(expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (_, DefaultedType(actual_inner)) =>
      unify_for_substitution(
        expected, actual_inner, subs, type_env, diagnostics,
      )
    (NullableType(expected_inner), NullableType(actual_inner)) =>
      unify_for_substitution(
        expected_inner, actual_inner, subs, type_env, diagnostics,
      )
    (NullableType(expected_inner), _) =>
      unify_for_substitution(
        expected_inner, actual, subs, type_env, diagnostics,
      )
    (ListingType(expected_items), ListingType(actual_items)) =>
      if expected_items.length() > 0 && actual_items.length() > 0 {
        let expected_item = expected_items[0]
        for item in actual_items {
          unify_for_substitution(
            expected_item, item, subs, type_env, diagnostics,
          )
        }
      }
    (MappingType(expected_entries), MappingType(actual_entries)) =>
      if expected_entries.length() > 0 && actual_entries.length() > 0 {
        let expected_entry = expected_entries[0]
        for entry in actual_entries {
          unify_for_substitution(
            expected_entry.key,
            entry.key,
            subs,
            type_env,
            diagnostics,
          )
          unify_for_substitution(
            expected_entry.value,
            entry.value,
            subs,
            type_env,
            diagnostics,
          )
        }
      }
    (
      FunctionType(expected_parameters, expected_return),
      FunctionType(actual_parameters, actual_return),
    ) => {
      let limit = if expected_parameters.length() < actual_parameters.length() {
        expected_parameters.length()
      } else {
        actual_parameters.length()
      }
      for i = 0; i < limit; i = i + 1 {
        unify_for_substitution(
          expected_parameters[i],
          actual_parameters[i],
          subs,
          type_env,
          diagnostics,
        )
      }
      unify_for_substitution(
        expected_return, actual_return, subs, type_env, diagnostics,
      )
    }
    (ClassType(_, expected_members), ObjectType(actual_members))
    | (ClassType(_, expected_members), ClassType(_, actual_members)) =>
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            unify_for_substitution(
              member_contract_type(expected_member.typ),
              actual,
              subs,
              type_env,
              diagnostics,
            )
          None => ()
        }
      }
    (ObjectType(expected_members), ObjectType(actual_members))
    | (ObjectType(expected_members), ClassType(_, actual_members)) =>
      for expected_member in expected_members {
        match lookup_member_type(actual_members, expected_member.name) {
          Some(actual) =>
            unify_for_substitution(
              member_contract_type(expected_member.typ),
              actual,
              subs,
              type_env,
              diagnostics,
            )
          None => ()
        }
      }
    _ => ()
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
            // PKL-110: for class literals like `new Box { value = 5 }`,
            // the expected ClassType still carries TypeVariable("T") in
            // its members. Unify against the inferred ObjectType members
            // and rewrite the returned ClassType so downstream field
            // access (`b.value`) resolves to the concrete argument type.
            let expected = substitute_class_type_variables(
              expected, inferred, type_env, diagnostics,
            )
            match (expected, inferred) {
              (NullableType(ObjectType([])), ObjectType(_)) =>
                NullableType(inferred)
              (ConstrainedType(_, inner), _) => inner
              _ => expected
            }
          } else {
            let message = match
              class_type_mismatch_message(name, expected, inferred) {
              Some(detail) => detail
              None =>
                "type annotation \{name} does not accept \{render_type(inferred)}"
            }
            diagnostics.push(diag(message))
            UnknownType
          }
        None => {
          diagnostics.push(diag("Cannot find type `\{name}`."))
          UnknownType
        }
      }
  }
}

///|
fn substitute_class_type_variables(
  expected : Type,
  inferred : Type,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Type {
  match expected {
    ClassType(_, _) => {
      let subs : Array[TypeSubstitution] = []
      unify_for_substitution(expected, inferred, subs, type_env, diagnostics)
      if subs.length() == 0 {
        expected
      } else {
        substitute_type(expected, subs)
      }
    }
    _ => expected
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
        match parameter_type_from_annotation(type_name, type_env) {
          Some(typ) => types.push(typ)
          None => {
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
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
          diagnostics.push(diag("Cannot find type `\{type_name}`."))
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
            alias_decl: None,
            bound: None,
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
        Some(typ) =>
          target_cache.push({ name, typ, alias_decl: None, bound: None })
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
              abstract_slot: false,
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
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
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
fn push_class_method_receiver_bindings(
  cache : Array[TypeBinding],
  class_name : String,
  members : Array[TypeMember],
) -> Unit {
  for type_member in members {
    cache.push({
      name: type_member.name,
      typ: member_contract_type(type_member.typ),
      alias_decl: None,
      bound: None,
    })
  }
  cache.push({
    name: "this",
    typ: ClassType(class_name, members),
    alias_decl: None,
    bound: None,
  })
}

///|
fn validate_class_method_body(
  class_name : String,
  members : Array[TypeMember],
  function_decl : FunctionDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match function_decl.body {
    Some(body) => {
      let method_cache : Array[TypeBinding] = []
      push_class_method_receiver_bindings(method_cache, class_name, members)
      let parameter_types = function_parameter_types(
        function_decl.parameters,
        type_env,
        diagnostics,
      )
      for i = 0; i < function_decl.parameters.length(); i = i + 1 {
        method_cache.push({
          name: function_decl.parameters[i].name,
          typ: parameter_types[i],
          alias_decl: None,
          bound: None,
        })
      }
      let inferred_return = infer_expr_with_bindings(
        body,
        [],
        [],
        type_env,
        method_cache,
        [],
        diagnostics,
        fn(_) { None },
      )
      match function_decl.return_type_name {
        Some(type_name) =>
          match type_from_annotation(type_name, type_env) {
            Some(expected) =>
              if !type_accepts(expected, inferred_return) {
                diagnostics.push(
                  diag(
                    "method \{class_name}.\{function_decl.name} return annotation \{type_name} does not accept \{render_type(inferred_return)}",
                  ),
                )
              }
            None => diagnostics.push(diag("Cannot find type `\{type_name}`."))
          }
        None => ()
      }
    }
    None => ()
  }
}

///|
fn validate_class_method_bodies(
  class_name : String,
  members : Array[TypeMember],
  methods : Array[FunctionDecl],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for class_method in methods {
    validate_class_method_body(
      class_name, members, class_method, type_env, diagnostics,
    )
  }
}

///|
fn class_decl_to_members(
  class_decl : ClassDecl,
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Array[TypeMember] {
  // PKL-089 introduced the scoped type environment so `class Box<T>`
  // body uses of T resolve. PKL-110 sharpens the binding from
  // UnknownType to TypeVariable(name) so the call-site substitution
  // pass can later rewrite each T against the concrete argument type.
  let scoped_env = if class_decl.type_parameters.length() == 0 {
    type_env
  } else {
    let next : Array[TypeBinding] = []
    // PKL-116: thread declared bounds through the class-scoped type_env
    // so methods and properties resolved against `T` participate in the
    // same bound check as standalone functions. Bounds resolve against
    // the outer `type_env` (the class binding itself is not yet in
    // scope, matching PKL-110's TypeVariable injection order).
    for i = 0; i < class_decl.type_parameters.length(); i = i + 1 {
      let parameter = class_decl.type_parameters[i]
      let bound_text = if i < class_decl.type_parameter_bounds.length() {
        class_decl.type_parameter_bounds[i]
      } else {
        None
      }
      let bound = match bound_text {
        Some(text) => type_from_annotation(text, type_env)
        None => None
      }
      next.push({
        name: parameter,
        typ: TypeVariable(parameter),
        alias_decl: None,
        bound,
      })
    }
    for binding in type_env {
      next.push(binding)
    }
    next
  }
  let own_members = merge_type_members(
    class_properties_to_members(class_decl.properties, scoped_env, diagnostics),
    class_methods_to_members(class_decl.methods, scoped_env, diagnostics),
  )
  let members = match class_decl.parent_name {
    Some(parent_name) =>
      match lookup_type(scoped_env, parent_name) {
        Some(ClassType(_, base_members)) =>
          merge_type_members(base_members, own_members)
        Some(_) => {
          diagnostics.push(
            diag("class \{class_decl.name} extends non-class \{parent_name}"),
          )
          own_members
        }
        None => {
          diagnostics.push(diag("Cannot find type `\{parent_name}`."))
          own_members
        }
      }
    None => own_members
  }
  validate_class_method_bodies(
    class_decl.name,
    members,
    class_decl.methods,
    scoped_env,
    diagnostics,
  )
  members
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
          alias_decl: None,
          bound: None,
        })
      TypeAliasDeclaration(type_alias) =>
        // PKL-137: fall back to `type_from_annotation` so union /
        // constrained / nullable / generic alias targets resolve too.
        // `builtin_type_from_annotation` alone misses
        // `("draft" | "review" | "approved")` and similar; the richer
        // resolver participates in the partially built `type_env`
        // (later aliases can reference earlier ones).
        match
          (
            builtin_type_from_annotation(type_alias.target),
            type_from_annotation(type_alias.target, type_env),
          ) {
          (Some(typ), _) | (None, Some(typ)) =>
            type_env.push({
              name: type_alias.name,
              typ,
              alias_decl: if type_alias.type_parameters.length() > 0 {
                Some(type_alias)
              } else {
                None
              },
              bound: None,
            })
          (None, None) => ()
        }
      // PKL-090 flattened function-level type parameters into the
      // module-level type_env so annotations like `(x: T): T` resolve.
      // PKL-110 binds each parameter to TypeVariable(name) instead of
      // UnknownType: now signatures carry a marker that the call-site
      // substitution pass can match on (`identity(7)` binds T = Int and
      // rewrites the return type before it propagates outward).
      FunctionDeclaration(function_decl) =>
        // PKL-116: resolve each parameter's optional bound text in the
        // current type_env so the binding carries a fully resolved
        // bound Type. `unify_for_substitution` consults `bound` to
        // reject call sites whose argument does not flow through the
        // bound. Unbounded parameters keep `bound = None`.
        for i = 0; i < function_decl.type_parameters.length(); i = i + 1 {
          let parameter = function_decl.type_parameters[i]
          let bound_text = if i < function_decl.type_parameter_bounds.length() {
            function_decl.type_parameter_bounds[i]
          } else {
            None
          }
          let bound = match bound_text {
            Some(text) => type_from_annotation(text, type_env)
            None => None
          }
          type_env.push({
            name: parameter,
            typ: TypeVariable(parameter),
            alias_decl: None,
            bound,
          })
        }
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
          alias_decl: None,
          bound: None,
        })
      TypeAliasDeclaration(type_alias) => {
        // PKL-115: capture the original decl on the binding when the
        // typealias is generic so use-site substitution can rewrite
        // the target text. For non-generic aliases the previous shape
        // is preserved by leaving `alias_decl` as `None`. Inject the
        // declared type parameters as scoped TypeVariables so the
        // target text can resolve at definition time even before any
        // instantiation site is seen.
        let scoped_type_env = copy_type_bindings(type_env)
        for parameter in type_alias.type_parameters {
          scoped_type_env.push({
            name: parameter,
            typ: TypeVariable(parameter),
            alias_decl: None,
            bound: None,
          })
        }
        match
          type_from_alias_target_annotation(type_alias.target, scoped_type_env) {
          Some(typ) =>
            type_env.push({
              name: type_alias.name,
              typ,
              alias_decl: if type_alias.type_parameters.length() > 0 {
                Some(type_alias)
              } else {
                None
              },
              bound: None,
            })
          None =>
            diagnostics.push(diag("Cannot find type `\{type_alias.target}`."))
        }
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
      // PKL-137: typealiases participate in the importing / amending
      // module's type scope the same way classes do. pkspec's
      // `Spec.pkl amends Test.pkl` references `Id`, `ReviewStatus`,
      // `Severity`, `IsoDate`, etc. — all typealiases declared in
      // Test.pkl. Export their resolved types so the relation /
      // import lookup populates the child's type env with them.
      TypeAliasDeclaration(type_alias) =>
        match lookup_type(type_env, type_alias.name) {
          Some(typ) => exports.push({ name: type_alias.name, typ })
          None => ()
        }
      FunctionDeclaration(_) => ()
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
            diagnostics.push(diag("cyclic property reference \{name}"))
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
            push_constrained_type_annotation_expr_diagnostic(
              binding.type_name,
              binding.value,
              type_env,
              diagnostics,
            )
            cache.push({ name, typ, alias_decl: None, bound: None })
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
fn function_parameter_index(
  parameters : Array[FunctionParameter],
  name : String,
) -> Int? {
  for i = 0; i < parameters.length(); i = i + 1 {
    if parameters[i].name == name {
      return Some(i)
    }
  }
  None
}

///|
fn callable_parameter_types_from_type(typ : Type) -> Array[Type]? {
  match typ {
    FunctionType(parameter_types, _) => Some(parameter_types)
    NullableType(FunctionType(parameter_types, _)) => Some(parameter_types)
    _ => None
  }
}

///|
fn validate_higher_order_constrained_call(
  label : String,
  parameters : Array[FunctionParameter],
  body : Expr,
  argument_types : Array[Type],
  arguments : Array[Expr],
  type_env : Array[TypeBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match body {
    CallExpr(Identifier(callee_name), call_arguments) =>
      match function_parameter_index(parameters, callee_name) {
        Some(callee_index) =>
          match
            callable_parameter_types_from_type(argument_types[callee_index]) {
            Some(callable_parameter_types) => {
              let mut limit = call_arguments.length()
              if callable_parameter_types.length() < limit {
                limit = callable_parameter_types.length()
              }
              for i = 0; i < limit; i = i + 1 {
                match
                  constrained_type_annotation_name(callable_parameter_types[i]) {
                  Some(type_name) =>
                    match call_arguments[i] {
                      Identifier(argument_name) =>
                        match
                          function_parameter_index(parameters, argument_name) {
                          Some(argument_index) =>
                            match
                              constrained_type_annotation_expr_rejection_message(
                                Some(type_name),
                                arguments[argument_index],
                                type_env,
                              ) {
                              Some(message) => {
                                diagnostics.push(
                                  diag(
                                    "\{label} argument \{argument_index + 1} \{message}",
                                  ),
                                )
                                return false
                              }
                              None => ()
                            }
                          None => ()
                        }
                      _ => ()
                    }
                  None => ()
                }
              }
              true
            }
            None => true
          }
        None => true
      }
    _ => true
  }
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
    diagnostics.push(
      diag(
        "\{label} expects \{parameters.length()} arguments, got \{arguments.length()}",
      ),
    )
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  // PKL-110: collect TypeVariable substitutions from every parameter site
  // before evaluating the body so callee-scoped uses of T (parameter cache,
  // body-derived return, declared return annotation) all see the same
  // concrete binding.
  let substitutions : Array[TypeSubstitution] = []
  let call_cache = copy_type_bindings(cache)
  for i = 0; i < parameters.length(); i = i + 1 {
    let parameter = parameters[i]
    let parameter_type = match parameter.type_name {
      Some(type_name) =>
        match parameter_type_from_annotation(type_name, type_env) {
          Some(expected) =>
            if type_accepts(expected, argument_types[i]) {
              match
                constrained_type_annotation_expr_rejection_message(
                  parameter.type_name,
                  arguments[i],
                  type_env,
                ) {
                Some(message) => {
                  diagnostics.push(
                    diag("\{label} argument \{i + 1} \{message}"),
                  )
                  return UnknownType
                }
                None => ()
              }
              unify_for_substitution(
                expected,
                argument_types[i],
                substitutions,
                type_env,
                diagnostics,
              )
              substitute_type(expected, substitutions)
            } else {
              diagnostics.push(
                diag(
                  "\{label} argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
                ),
              )
              return UnknownType
            }
          None => {
            diagnostics.push(diag("Cannot find type `\{type_name}`."))
            UnknownType
          }
        }
      None => argument_types[i]
    }
    call_cache.push({
      name: parameter.name,
      typ: parameter_type,
      alias_decl: None,
      bound: None,
    })
  }
  if !validate_higher_order_constrained_call(
      label, parameters, body, argument_types, arguments, type_env, diagnostics,
    ) {
    return UnknownType
  }
  let inferred_return = infer_expr_with_bindings(
    body, bindings, env, type_env, call_cache, stack, diagnostics, resolve_import,
  )
  let inferred_return = substitute_type(inferred_return, substitutions)
  match return_type_name {
    Some(type_name) =>
      match type_from_annotation(type_name, type_env) {
        Some(expected) => {
          let expected = substitute_type(expected, substitutions)
          if type_accepts(expected, inferred_return) {
            expected
          } else {
            diagnostics.push(
              diag(
                "\{label} return annotation \{type_name} does not accept \{render_type(inferred_return)}",
              ),
            )
            UnknownType
          }
        }
        None => {
          diagnostics.push(diag("Cannot find type `\{type_name}`."))
          UnknownType
        }
      }
    None => inferred_return
  }
}

///|
fn constrained_type_annotation_name(typ : Type) -> String? {
  match typ {
    ConstrainedType(type_name, _) => Some(type_name)
    DefaultedType(inner) => constrained_type_annotation_name(inner)
    NullableType(inner) => constrained_type_annotation_name(inner)
    _ => None
  }
}

///|
fn infer_function_type_call(
  label : String,
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
    diagnostics.push(
      diag(
        "\{label} expects \{parameter_types.length()} arguments, got \{arguments.length()}",
      ),
    )
    return UnknownType
  }
  let argument_types = infer_argument_types(
    arguments, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
  )
  let substitutions : Array[TypeSubstitution] = []
  for i = 0; i < parameter_types.length(); i = i + 1 {
    let expected = parameter_types[i]
    if expected != UnknownType && !type_accepts(expected, argument_types[i]) {
      diagnostics.push(
        diag(
          "\{label} argument \{i + 1} expects \{render_type(expected)}, got \{render_type(argument_types[i])}",
        ),
      )
      return UnknownType
    }
    unify_for_substitution(
      expected,
      argument_types[i],
      substitutions,
      type_env,
      diagnostics,
    )
    match constrained_type_annotation_name(expected) {
      Some(type_name) =>
        match
          constrained_type_annotation_expr_rejection_message(
            Some(type_name),
            arguments[i],
            type_env,
          ) {
          Some(message) => {
            diagnostics.push(diag("\{label} argument \{i + 1} \{message}"))
            return UnknownType
          }
          None => ()
        }
      None => ()
    }
  }
  substitute_type(return_type, substitutions)
}

///|
fn function_type_call_label(callee : Expr) -> String {
  match callee {
    MemberAccess(_, member_name) | SafeMemberAccess(_, member_name) =>
      "method \{member_name}"
    _ => "function"
  }
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
        function_type_call_label(callee),
        parameter_types,
        return_type,
        arguments,
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
      )
    NullableType(FunctionType(parameter_types, return_type)) => {
      let inferred_return = infer_function_type_call(
        function_type_call_label(callee),
        parameter_types,
        return_type,
        arguments,
        bindings,
        env,
        type_env,
        cache,
        stack,
        diagnostics,
        resolve_import,
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
          diagnostics.push(diag("call expects Function"))
          UnknownType
        }
      }
    UnknownType => UnknownType
    _ => {
      diagnostics.push(diag("call expects Function"))
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
        diagnostics.push(diag("operator && expects Boolean operands"))
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
        diagnostics.push(diag("operator || expects Boolean operands"))
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
    FloatLiteral(_) => FloatType
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
          diagnostics.push(diag("unresolved import \{uri}"))
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
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("member access expects Object"))
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
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        ClassType(_, members) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => member_contract_type(typ)
            None => {
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        NullableType(ObjectType(members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        NullableType(ClassType(_, members)) =>
          match lookup_member_type(members, member_name) {
            Some(typ) => nullable_type(member_contract_type(typ))
            None => {
              diagnostics.push(diag("unknown member \{member_name}"))
              UnknownType
            }
          }
        NullType => NullType
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("safe member access expects Object"))
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
                  diagnostics.push(diag("listing index out of bounds \{index}"))
                  UnknownType
                }
              _ => common_type(items)
            }
          } else {
            diagnostics.push(diag("listing index expects Int"))
            UnknownType
          }
        MappingType(entries) =>
          match lookup_mapping_value_type(entries, key) {
            Some(value) => value
            None => {
              diagnostics.push(diag("unknown mapping key type"))
              UnknownType
            }
          }
        UnknownType => UnknownType
        _ => {
          diagnostics.push(diag("subscript access expects Listing or Mapping"))
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
          diagnostics.push(diag("object amendment expects Object"))
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
          diagnostics.push(diag("Cannot find property `\{name}`."))
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
              diagnostics.push(diag("Cannot find type `\{type_name}`."))
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
          diagnostics.push(diag("non-null assertion rejects Null"))
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
            diagnostics.push(diag("operator - expects Int operand"))
            UnknownType
          }
        Not =>
          if inner == BoolType {
            BoolType
          } else {
            diagnostics.push(diag("operator ! expects Boolean operand"))
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
                diagnostics.push(diag("Cannot find type `\{name}`."))
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
                diagnostics.push(diag("Cannot find type `\{name}`."))
                return UnknownType
              }
            }
          _ => return UnknownType
        }
      }
      if op == Pipe {
        diagnostics.push(diag("operator |> is parser-only"))
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
        Add | Subtract | Multiply | IntDivide | Modulo | Power =>
          // PKL-092: Int×Int stays Int. Add/Sub/Mul widen to Float when
          // any operand is Float.
          // PKL-111: Power widens to Float on any Float operand
          // (`2.0 ** 3 = 8.0`). IntDivide always returns Int but accepts
          // Float operands (Apple Pkl: `5.0 ~/ 3.0 == 1`). Modulo widens
          // to Float on any Float operand (Apple Pkl: `5.5 % 6.5 = 5.5`).
          if left == IntType && right == IntType {
            IntType
          } else if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            if op == IntDivide {
              IntType
            } else {
              FloatType
            }
          } else {
            diagnostics.push(
              diag("operator \{operator_name(op)} expects Int operands"),
            )
            UnknownType
          }
        Divide =>
          // PKL-092: `/` widens to Float unconditionally when both sides
          // are numeric, matching Apple Pkl's `5 / 2 == 2.5` semantics.
          if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            FloatType
          } else {
            diagnostics.push(diag("operator / expects numeric operands"))
            UnknownType
          }
        LessThan | LessOrEqual | GreaterThan | GreaterOrEqual =>
          // PKL-092: comparisons admit any Int / Float mix.
          if (left == IntType || left == FloatType) &&
            (right == IntType || right == FloatType) {
            BoolType
          } else {
            diagnostics.push(
              diag("operator \{operator_name(op)} expects numeric operands"),
            )
            UnknownType
          }
        Equal | NotEqual =>
          // PKL-113: reject `a == b` / `a != b` when the operand types
          // are statically distinct. Today's typechecker passed every
          // pair through as BoolType, hiding `5 == "hi"` until runtime.
          if equality_compatible(left, right) {
            BoolType
          } else {
            diagnostics.push(
              diag(
                "operator \{operator_name(op)} expects operands of matching types",
              ),
            )
            UnknownType
          }
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
        diagnostics.push(diag("if condition expects Boolean"))
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
    ForGenerator(_, _, _, _) =>
      // for-generators only appear as synthetic `@for` object members and
      // are handled at object evaluation time. They never surface in
      // typechecking contexts; treat them as opaque object bodies.
      UnknownType
    ErrorExpr(message) => {
      diagnostics.push(diag(message))
      UnknownType
    }
    UnsupportedExpr => {
      diagnostics.push(diag("unsupported expression"))
      UnknownType
    }
    // PKL-136: a `WhenSpread` outside a Listing/Mapping body simply
    // forwards to the inner Expr's type. The Listing/Mapping literal
    // arms handle the spread itself (they collect inner element / entry
    // types from the wrapped ConditionalExpr).
    WhenSpread(inner) =>
      infer_expr_with_bindings(
        inner, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
      )
    // PKL-103: `read?(uri)` returns `String?` — null when missing /
    // rejected, the read value otherwise. The typechecker collapses
    // to `NullableType(StringType)` so chained access sees a
    // nullable; further refinement (per-scheme types) is out of
    // scope for this slice.
    NullSafeCallExpr(_, args) => {
      for arg in args {
        ignore(
          infer_expr_with_bindings(
            arg, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
      }
      NullableType(StringType)
    }
    // PKL-128: an interpolated string always evaluates to a `String`,
    // regardless of the inner expression types. Walk the inner parts
    // so diagnostics from their typechecking still surface.
    InterpolatedString(parts) => {
      for part in parts {
        ignore(
          infer_expr_with_bindings(
            part, bindings, env, type_env, cache, stack, diagnostics, resolve_import,
          ),
        )
      }
      StringType
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
    push_constrained_type_annotation_expr_diagnostic(
      field.type_name,
      field.value,
      type_env,
      diagnostics,
    )
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
      Some(TypeOk(typ)) =>
        env.push({ name: decl.import_name, typ, alias_decl: None, bound: None })
      Some(TypeError(errors)) =>
        for error in errors {
          diagnostics.push(error)
        }
      None => diagnostics.push(diag("unresolved import \{decl.uri}"))
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
      diagnostics.push(
        diag(
          "module \{relation_kind_name_for_typecheck(relation.kind)} expects Object",
        ),
      )
      []
    }
    Some(TypeError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      []
    }
    None => {
      diagnostics.push(diag("unresolved import \{relation.uri}"))
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
  // PKL-137: `amends "base.pkl"` / `extends "base.pkl"` brings the
  // base module's class / typealias declarations into the child's
  // unqualified type scope. Without this, the child sees the base's
  // property types (via `infer_module_relation`) but writing a
  // `class Test` from the base as a bare `Test` annotation in the
  // child errors with `Cannot find type `Test``.
  let relation_types : Array[TypeBinding] = []
  match program.module_relation {
    Some(relation) =>
      match resolve_import_types(relation.uri) {
        Some(exports) =>
          for type_export in exports {
            relation_types.push({
              name: type_export.name,
              typ: type_export.typ,
              alias_decl: None,
              bound: None,
            })
          }
        None => ()
      }
    None => ()
  }
  let combined_imports : Array[TypeBinding] = []
  for binding in imported_types {
    combined_imports.push(binding)
  }
  for binding in relation_types {
    combined_imports.push(binding)
  }
  let type_env = collect_declared_types_with_imports(
    program.declarations,
    diagnostics,
    combined_imports,
  )
  push_constrained_class_property_default_diagnostics(
    program.declarations,
    diagnostics,
  )
  push_constrained_callable_return_body_diagnostics(
    program.declarations,
    type_env,
    diagnostics,
  )
  // PKL-117: enforce abstract-method coverage on concrete classes and
  // override-direction subtype rules on every overriding method. The
  // pass walks only locally-declared parents — abstract methods that
  // arrive through an imported parent stay deferred; cross-module
  // visibility is a separate slice (PKL-118 currently tracks it).
  push_inheritance_hardening_diagnostics(
    program.declarations,
    type_env,
    diagnostics,
  )
  let cache : Array[TypeBinding] = []
  let fields : Array[TypeMember] = []
  let bindings = all_program_bindings(program)
  infer_imports(program.imports, env, diagnostics, resolve_import)
  for binding in program.bindings {
    // PKL-140: abstract / external slots carry a synthetic `NullLiteral`
    // value the typechecker would otherwise reject against the declared
    // type. Skip validation but keep the slot's type in the recorded
    // module shape so cross-module references still see it.
    if binding.abstract_slot {
      let slot_type = match binding.type_name {
        Some(text) =>
          match type_from_annotation(text, type_env) {
            Some(t) => t
            None => UnknownType
          }
        None => UnknownType
      }
      fields.push({ name: binding.name, typ: slot_type })
      continue
    }
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
      Some(typ) => {
        push_user_defined_constrained_type_annotation_expr_diagnostic(
          binding.type_name,
          binding.value,
          program.declarations,
          diagnostics,
        )
        push_constrained_class_property_expr_diagnostics(
          binding.value,
          program.declarations,
          diagnostics,
        )
        if binding.exported {
          fields.push({ name: binding.name, typ })
        }
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
    // PKL-140: declarations-only modules (Apple Pkl stdlib pattern)
    // typecheck to the empty ObjectType. The class / typealias /
    // function declarations are still tracked in program.declarations
    // and remain available to importers.
    None => ObjectType([])
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
