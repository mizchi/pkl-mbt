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
    PairType(first, second) =>
      "Pair<\{render_type(first)}, \{render_type(second)}>"
    IntSeqType => "IntSeq"
    SetType(_) => "Set"
    MapType(_) => "Map"
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
    // PKL-119b: `IntSeq` annotation resolves to the dedicated
    // `IntSeqType` so signatures like `r: IntSeq = IntSeq(1, 5)`
    // typecheck.
    "IntSeq" => Some(IntSeqType)
    // PKL-119c: bare `Set` (no type arguments) accepts any element
    // type; parameterised `Set<T>` is intercepted earlier in
    // `type_from_annotation` via `generic_argument_text`.
    "Set" => Some(SetType([]))
    // PKL-119d: bare `Map` (no generic arguments) accepts any
    // key/value type; `Map<K, V>` is intercepted earlier.
    "Map" => Some(MapType([]))
    // PKL-134: `List<T>` is Pkl's immutable indexed collection; pkl-mbt
    // collapses Listing / List into the same runtime value so the
    // typechecker treats them as the same shape. Once the value
    // variants split (PKL-119) this alias becomes a distinct variant.
    "List" => Some(ListingType([]))
    // PKL-133: top type. Maps to its own `AnyType` variant so render
    // output stays as `Any` instead of collapsing to `Unknown`.
    "Any" => Some(AnyType)
    // PKL-148bh: `module` is Apple Pkl's "type of the enclosing
    // module" annotation (`types/currentModuleType*`). Without a
    // dedicated variant the typechecker rejects every signature that
    // uses it; map to `ObjectType` so the structural shape lines up
    // with the module's own ObjectValue projection.
    "module" => Some(ObjectType([]))
    // PKL-148bh: `unknown` is Apple Pkl's "I don't care" type — wire
    // as `AnyType` so signatures using it
    // (basic/newInAmendingModuleMethod: `function parrot(): unknown`)
    // typecheck without flagging the value.
    "unknown" => Some(AnyType)
    // PKL-124: pkl:base renderer classes are globally accessible
    // (Apple Pkl implicitly imports `pkl:base`). Empty member list
    // means `new JsonRenderer { ... }` accepts any subset of property
    // assignments; field-level type checks land alongside PKL-127
    // (converter machinery) when each renderer's surface is fleshed
    // out. `PListRenderer` / `XmlRenderer` / `ProtobufRenderer` /
    // `JsonnetRenderer` / `PklBinaryRenderer` are pinned here too so
    // unqualified references in fixtures don't trip on `Cannot find
    // type`; the qualified `xml.Renderer` / `protobuf.Renderer` /
    // `jsonnet.Renderer` / `pklbinary.Renderer` aliases route through
    // the synthetic stdlib modules and the normal import-typing path.
    "PcfRenderer"
    | "JsonRenderer"
    | "YamlRenderer"
    | "PropertiesRenderer"
    | "PListRenderer"
    | "XmlRenderer"
    | "ProtobufRenderer"
    | "JsonnetRenderer"
    | "PklBinaryRenderer"
    | "Mixin" => Some(ClassType(name, []))
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
  let name = pkl_strip_default_type_marker(name)
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
  // PKL-119c: `Set<T>` annotation lands as `SetType([T])`. Bare
  // `Set` (no generic argument) is handled by
  // `builtin_type_from_annotation` and resolves to `SetType([])`.
  match generic_argument_text(name, "Set") {
    Some(inner_text) =>
      match type_from_annotation(inner_text, type_env) {
        Some(inner) => return Some(SetType([inner]))
        None => return None
      }
    None => ()
  }
  // PKL-119d: `Map<K, V>` annotation lands as `MapType([{key, value}])`.
  // Bare `Map` reaches `builtin_type_from_annotation` and resolves to
  // `MapType([])`.
  match generic_argument_text(name, "Map") {
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
          return Some(MapType([TypeEntry::{ key, value }]))
        _ => return None
      }
    }
    None => ()
  }
  // PKL-119a: `Pair<A, B>` annotation lands as the dedicated
  // `PairType(A, B)`. Bare `Pair` (no arguments) reaches
  // `builtin_type_from_annotation` below and resolves to
  // `PairType(UnknownType, UnknownType)` so unparameterised reads
  // still typecheck.
  match generic_argument_text(name, "Pair") {
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
        (Some(first), Some(second)) => return Some(PairType(first, second))
        _ => return None
      }
    }
    None => ()
  }
  match generic_argument_text(name, "Mixin") {
    Some(_) => return Some(ClassType("Mixin", []))
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
