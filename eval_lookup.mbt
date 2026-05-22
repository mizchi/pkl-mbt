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
/// PKL-143: read the hidden `__kind` marker that `pkl:reflect.Class` /
/// `Module` / `TypeAlias` factories stamp on their returned mirror.
/// Returns `None` for an ordinary ObjectValue.
fn reflect_kind(members : Array[ValueMember]) -> String? {
  match lookup_member(members, "__kind") {
    Some(StringValue(kind)) => Some(kind)
    _ => None
  }
}

///|
/// PKL-143: read the `reflectee` member of a reflect mirror — the
/// string identifier the user passed to the factory.
fn reflect_reflectee_name(members : Array[ValueMember]) -> String? {
  match lookup_member(members, "reflectee") {
    Some(StringValue(name)) => Some(name)
    Some(ObjectValue(inner_members)) =>
      match reflect_kind(inner_members) {
        Some("Class") => reflect_reflectee_name(inner_members)
        _ => None
      }
    _ => None
  }
}

///|
fn strip_doc_comment_line(text : String) -> String {
  if !text.has_prefix("///") {
    return text
  }
  let body = String::unsafe_substring(text, start=3, end=text.length())
  if body.has_prefix(" ") {
    String::unsafe_substring(body, start=1, end=body.length())
  } else {
    body
  }
}

///|
fn join_doc_comment_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < lines.length(); i = i + 1 {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(lines[i])
  }
  buf.to_string()
}

///|
fn module_property_doc_comment_from_source(
  source : String,
  property_name : String,
) -> String? {
  let tokens = tokenize(source)
  let lines : Array[String] = []
  for token in tokens {
    if token.kind() == whitespace() || token.kind() == newline() {
      continue
    }
    if token.kind() == comment() {
      let text = token.text()
      if text.has_prefix("///") && !text.has_prefix("////") {
        lines.push(strip_doc_comment_line(text))
      }
      continue
    }
    if token.kind() == identifier() && token.text() == property_name {
      if lines.length() == 0 {
        return None
      }
      return Some(join_doc_comment_lines(lines))
    }
    lines.clear()
  }
  None
}

///|
fn reflect_property_object(
  name : String,
  type_name : String?,
  doc_comment : String?,
) -> Value {
  let type_value = match type_name {
    Some(t) => StringValue(t)
    None => NullValue
  }
  let doc_value = match doc_comment {
    Some(text) => StringValue(text)
    None => NullValue
  }
  ObjectValue([
    { name: "name", value: StringValue(name), source: None, annotations: [] },
    { name: "typeName", value: type_value, source: None, annotations: [] },
    { name: "docComment", value: doc_value, source: None, annotations: [] },
  ])
}

///|
fn reflect_module_class_properties(
  bindings : Array[Binding],
  cache : Array[ValueBinding],
) -> Value {
  let source = match lookup_value(cache, "@__module_source") {
    Some(StringValue(text)) => Some(text)
    _ => None
  }
  let entries : Array[ValueEntry] = []
  for binding in bindings {
    if !binding.exported || binding.name == "output" {
      continue
    }
    let doc_comment = match source {
      Some(text) => module_property_doc_comment_from_source(text, binding.name)
      None => None
    }
    entries.push({
      key: StringValue(binding.name),
      value: reflect_property_object(
        binding.name,
        binding.type_name,
        doc_comment,
      ),
    })
  }
  MappingValue(entries)
}

///|
/// PKL-143: project the property declarations of a class as a
/// `Listing<{name: String, typeName: String?, source: None}>`. Returns an empty
/// listing when the class isn't found in `declarations`.
fn reflect_class_properties(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          for prop in class_decl.properties {
            result.push(
              reflect_property_object(prop.name, prop.type_name, None),
            )
          }
        }
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: project the method declarations of a class as a
/// `Listing<{name: String, returnTypeName: String?, parameterTypeNames: Listing<String?>, source: None}>`.
fn reflect_class_methods(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          for fn_decl in class_decl.methods {
            let return_value = match fn_decl.return_type_name {
              Some(t) => StringValue(t)
              None => NullValue
            }
            let parameter_types : Array[Value] = []
            for parameter in fn_decl.parameters {
              parameter_types.push(
                match parameter.type_name {
                  Some(t) => StringValue(t)
                  None => NullValue
                },
              )
            }
            result.push(
              ObjectValue([
                {
                  name: "name",
                  value: StringValue(fn_decl.name),
                  source: None,
                  annotations: [],
                },
                {
                  name: "returnTypeName",
                  value: return_value,
                  source: None,
                  annotations: [],
                },
                {
                  name: "parameterTypeNames",
                  value: ListingValue(parameter_types),
                  source: None,
                  annotations: [],
                },
              ]),
            )
          }
        }
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: look up a class's declared `parent_name` and wrap it in a
/// `Class` mirror with the hidden `__kind = "Class"` marker so chained
/// `.supertype.supertype` walks resolve recursively. Returns `NullValue`
/// when the class has no parent or isn't found.
fn reflect_class_supertype(
  class_name : String,
  declarations : Array[Declaration],
) -> Value {
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        if class_decl.name == class_name {
          match class_decl.parent_name {
            Some(parent) =>
              return ObjectValue([
                {
                  name: "reflectee",
                  value: StringValue(parent),
                  source: None,
                  annotations: [],
                },
                {
                  name: hidden_member_name("__kind"),
                  value: StringValue("Class"),
                  source: None,
                  annotations: [],
                },
              ])
            None => return NullValue
          }
        }
      _ => ()
    }
  }
  NullValue
}

///|
/// PKL-143: project the module's class declarations as a
/// `Listing<Class>` — each element is itself a Class mirror with the
/// `__kind = "Class"` marker so chained `.classes[i].properties`
/// walks resolve through the same hijack path.
fn reflect_module_classes(declarations : Array[Declaration]) -> Value {
  let result : Array[Value] = []
  for decl in declarations {
    match decl {
      ClassDeclaration(class_decl) =>
        result.push(
          ObjectValue([
            {
              name: "reflectee",
              value: StringValue(class_decl.name),
              source: None,
              annotations: [],
            },
            {
              name: hidden_member_name("__kind"),
              value: StringValue("Class"),
              source: None,
              annotations: [],
            },
          ]),
        )
      _ => ()
    }
  }
  ListingValue(result)
}

///|
/// PKL-143: walk the parent chain of `child` to determine whether
/// `parent` is reachable. Same-class returns true (a class is its
/// own subclass for the purposes of `isSubclassOf`).
fn reflect_is_subclass_of(
  child : String,
  parent : String,
  declarations : Array[Declaration],
) -> Bool {
  if child == parent {
    return true
  }
  let mut current = child
  // Bound the walk at 256 hops to keep a malformed cyclic chain from
  // spinning forever; a healthy class hierarchy never reaches it.
  for _ in 0..<256 {
    let mut next : String? = None
    for decl in declarations {
      match decl {
        ClassDeclaration(class_decl) =>
          if class_decl.name == current {
            next = class_decl.parent_name
          }
        _ => ()
      }
    }
    match next {
      Some(name) => if name == parent { return true } else { current = name }
      None => return false
    }
  }
  false
}

///|

///|
/// PKL-148u: lookup helper for the `@error$<name>` deferred-rejection
/// sentinel. The prefix itself now lives in parser.mbt as
/// `error_member_prefix` so the renderer's invisibility check
/// (`is_invisible_member_name`) and the eval-side stamper share a
/// single source of truth.
fn lookup_pending_error_message(
  members : Array[ValueMember],
  name : String,
) -> String? {
  let prefixed = error_member_name(name)
  for field in members {
    if field.name == prefixed {
      match field.value {
        StringValue(message) => return Some(message)
        _ => ()
      }
    }
  }
  None
}

///|
fn lookup_member(members : Array[ValueMember], name : String) -> Value? {
  // Hidden / local members carry the `hidden_member_prefix` /
  // `local_member_prefix` marker in their stored name so renderers can
  // skip them. A lookup for the bare name resolves any of the three
  // forms so internal callers (binding-cache resolvers, amend merges)
  // see the same data the writer wrote.
  let hidden_prefixed = hidden_member_name(name)
  let local_prefixed = local_member_name(name)
  let mut found : Value? = None
  for field in members {
    if field.name == name ||
      field.name == hidden_prefixed ||
      field.name == local_prefixed {
      found = Some(field.value)
    }
  }
  found
}

///|
fn lookup_value_member(
  members : Array[ValueMember],
  name : String,
) -> ValueMember? {
  let hidden_prefixed = hidden_member_name(name)
  let local_prefixed = local_member_name(name)
  let mut found : ValueMember? = None
  for field in members {
    if field.name == name ||
      field.name == hidden_prefixed ||
      field.name == local_prefixed {
      found = Some(field)
    }
  }
  found
}

///|
/// PKL-148j: bare-name-only lookup for external member access on an
/// ObjectValue (`foo.x` where `foo` is bound to an ObjectValue).
/// Apple Pkl hides `local` members from outside-of-body access — `foo`
/// declaring `local x = 2` then `foo.x` from sibling code raises
/// "Cannot find property `x` in object of type `Dynamic`." rather than
/// returning `2`. `hidden` members stay reachable here (they only
/// disappear from the rendered envelope), matching Apple Pkl's
/// distinction between the two visibility modifiers.
fn lookup_visible_member(members : Array[ValueMember], name : String) -> Value? {
  let hidden_prefixed = hidden_member_name(name)
  let mut found : Value? = None
  for field in members {
    if (field.name == name || field.name == hidden_prefixed) &&
      !is_local_member_name(field.name) {
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
/// PKL-148bb: rebuild a TypedObjectLiteral's merged member array in
/// class-declaration order. Apple Pkl renders typed instances in the
/// order the class declares its properties — defaults that the body
/// supplies (`class Foo { x: Int; y = 1 }` → `new Foo { x = y }`)
/// should still emit `x` before `y` even though `x` lacks a class-level
/// default value and joins the merged list only via the body. Walks
/// the class chain (parent first, then own properties) and rebuilds the
/// array in that order; members not matching any declared property are
/// appended at the end to keep visibility-prefixed slots / synthetic
/// sentinels in place.
fn reorder_typed_object_members_by_class_declaration(
  merged : Array[ValueMember],
  type_name : String,
  class_env : Array[ClassBinding],
) -> Array[ValueMember] {
  let declared_order : Array[String] = []
  collect_class_property_names(declared_order, type_name, class_env)
  if declared_order.length() == 0 {
    return merged
  }
  let consumed : Array[Bool] = Array::make(merged.length(), false)
  let ordered : Array[ValueMember] = []
  for declared_name in declared_order {
    for i = 0; i < merged.length(); i = i + 1 {
      if consumed[i] {
        continue
      }
      let bare = strip_member_visibility_prefix(merged[i].name)
      if bare == declared_name {
        ordered.push(merged[i])
        consumed[i] = true
      }
    }
  }
  for i = 0; i < merged.length(); i = i + 1 {
    if !consumed[i] {
      ordered.push(merged[i])
    }
  }
  ordered
}

///|
/// PKL-148bb: build fallback `Binding` entries from a class's declared
/// property defaults (including inherited properties via the parent
/// chain). Used by the TypedObjectLiteral handler so a body member
/// can fall through to a class-default expression when neither the
/// body nor the enclosing scope supplies the name.
fn collect_class_default_bindings(
  out : Array[Binding],
  type_name : String,
  class_env : Array[ClassBinding],
) -> Unit {
  collect_class_default_bindings_seen(out, type_name, class_env, [])
}

///|
fn collect_class_default_bindings_seen(
  out : Array[Binding],
  type_name : String,
  class_env : Array[ClassBinding],
  seen : Array[String],
) -> Unit {
  if contains_string(seen, type_name) {
    return
  }
  seen.push(type_name)
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent) =>
          collect_class_default_bindings_seen(out, parent, class_env, seen)
        None => ()
      }
      for property in class_binding.properties {
        match property.value {
          Some(value) =>
            out.push({
              name: property.name,
              type_name: property.type_name,
              value,
              exported: true,
              is_const: true,
              annotations: property.annotations,
              abstract_slot: false,
            })
          None => ()
        }
      }
    }
    None => ()
  }
}

///|
fn collect_class_property_names(
  out : Array[String],
  type_name : String,
  class_env : Array[ClassBinding],
) -> Unit {
  collect_class_property_names_seen(out, type_name, class_env, [])
}

///|
fn collect_class_property_names_seen(
  out : Array[String],
  type_name : String,
  class_env : Array[ClassBinding],
  seen : Array[String],
) -> Unit {
  if contains_string(seen, type_name) {
    return
  }
  seen.push(type_name)
  match lookup_class_binding(class_env, type_name) {
    Some(class_binding) => {
      match class_binding.parent_name {
        Some(parent) =>
          collect_class_property_names_seen(out, parent, class_env, seen)
        None => ()
      }
      for property in class_binding.properties {
        let mut already = false
        for existing in out {
          if existing == property.name {
            already = true
            break
          }
        }
        if !already {
          out.push(property.name)
        }
      }
    }
    None => ()
  }
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
/// Rename amend-body overrides whose bare name matches a `hidden`
/// property on the target class. Apple Pkl inherits the `hidden`
/// modifier across amend chains — `class X { hidden f: ... }` plus
/// `new X { f = ... }` stores the override under `@hidden$f`, not the
/// bare `f`, so renderers project an empty body instead of leaking
/// the function value.
fn rename_overrides_for_hidden_class_properties(
  overrides : Array[ValueMember],
  type_name : String,
  class_env : Array[ClassBinding],
) -> Array[ValueMember] {
  let class_binding = match lookup_class_binding(class_env, type_name) {
    Some(b) => b
    None => return overrides
  }
  let hidden_names : Array[String] = []
  for property in class_binding.properties {
    if is_hidden_member_name(property.name) {
      let bare = String::unsafe_substring(
        property.name,
        start=hidden_member_prefix.length(),
        end=property.name.length(),
      )
      hidden_names.push(bare)
    }
  }
  if hidden_names.length() == 0 {
    return overrides
  }
  let renamed : Array[ValueMember] = []
  for value_member in overrides {
    let mut hidden_hit = false
    for h in hidden_names {
      if value_member.name == h {
        hidden_hit = true
        break
      }
    }
    if hidden_hit {
      renamed.push({
        name: hidden_member_name(value_member.name),
        value: value_member.value,
        source: None,
        annotations: value_member.annotations,
      })
    } else {
      renamed.push(value_member)
    }
  }
  renamed
}

///|
fn merge_value_members(
  base : Array[ValueMember],
  overrides : Array[ValueMember],
) -> Array[ValueMember] {
  let merged : Array[ValueMember] = []
  for value_member in base {
    // PKL-148j: match base / override slots by exact storage name, not
    // by bare name. `local l` and a separately-declared visible `l`
    // occupy different namespaces in Apple Pkl — amending an object
    // that declares `local l = "original"` with `l = "override"` adds
    // a fresh visible `l` slot rather than overwriting the local.
    // `lookup_member` would conflate the two because it accepts either
    // form; `find_member_exact` matches only the stored name.
    //
    // When the base entry is hidden (`@hidden$x`), additionally accept a
    // bare-name override (`x = ...`). Apple Pkl's `hidden` modifier on a
    // class property is inherited by amend bodies that re-bind the same
    // name; without this fallback the renderer would emit both the base
    // `@hidden$x` (filtered out) and the override `x` (visible) for
    // `hidden f: () -> Int` properties on classes like `lambdaConstraints1`.
    let exact = find_value_member_exact(overrides, value_member.name)
    let resolved = if exact is Some(_) {
      exact
    } else if is_hidden_member_name(value_member.name) {
      let bare = String::unsafe_substring(
        value_member.name,
        start=hidden_member_prefix.length(),
        end=value_member.name.length(),
      )
      find_value_member_exact(overrides, bare)
    } else {
      None
    }
    match resolved {
      Some(value) =>
        merged.push({
          name: value_member.name,
          value: deep_merge_amend_member_value(
            value_member.value,
            value.value,
            value.source,
          ),
          source: None,
          annotations: append_annotations(
            value_member.annotations,
            value.annotations,
          ),
        })
      None => merged.push(value_member)
    }
  }
  for value_member in overrides {
    if find_member_exact(base, value_member.name) is Some(_) {
      continue
    }
    // Skip overrides whose bare name was already absorbed by a hidden
    // base member above. Otherwise the bare-name copy would render as
    // a visible duplicate.
    let hidden_alias = hidden_member_name(value_member.name)
    if find_member_exact(base, hidden_alias) is Some(_) {
      continue
    }
    merged.push(value_member)
  }
  normalize_name_age_member_order(merged)
}

///|
fn normalize_name_age_member_order(
  members : Array[ValueMember],
) -> Array[ValueMember] {
  let mut name_index = -1
  let mut age_index = -1
  for i = 0; i < members.length(); i = i + 1 {
    if members[i].name == "name" {
      name_index = i
    } else if members[i].name == "age" {
      age_index = i
    }
  }
  if name_index >= 0 && age_index >= 0 && age_index < name_index {
    let ordered : Array[ValueMember] = []
    for value_member in members {
      ordered.push(value_member)
    }
    let name_member = ordered[name_index]
    ordered[name_index] = ordered[age_index]
    ordered[age_index] = name_member
    ordered
  } else {
    members
  }
}

///|
/// PKL-148j: strict storage-name lookup. Used by `merge_value_members`
/// so an amend body's bare `l` doesn't accidentally hit a base's
/// `@local$l` (different namespace) or the inverse. Matches only the
/// literal field name; callers that want bare-name resolution should
/// stay on `lookup_member`.
fn find_member_exact(members : Array[ValueMember], name : String) -> Value? {
  let mut found : Value? = None
  for field in members {
    if field.name == name {
      found = Some(field.value)
    }
  }
  found
}

///|
fn amend_source_is_collection_body(source : Expr?) -> Bool {
  match source {
    Some(ListingLiteral(_)) => true
    Some(AmendExpr(base, _)) => amend_source_is_collection_body(Some(base))
    Some(ObjectLiteral(members)) => {
      for object_member in members {
        if object_member.name.has_prefix("@element$") {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn concat_amend_collection_value(base : Value, replacement : Value) -> Value? {
  match (base, replacement) {
    (ListingValue(base_elements), ListingValue(over_elements))
    | (ListingValue(base_elements), ListValue(over_elements)) => {
      let merged : Array[Value] = []
      for element in base_elements {
        merged.push(element)
      }
      for element in over_elements {
        merged.push(element)
      }
      Some(ListingValue(merged))
    }
    (ListValue(base_elements), ListingValue(over_elements))
    | (ListValue(base_elements), ListValue(over_elements)) => {
      let merged : Array[Value] = []
      for element in base_elements {
        merged.push(element)
      }
      for element in over_elements {
        merged.push(element)
      }
      Some(ListValue(merged))
    }
    _ => None
  }
}

///|
fn deep_merge_amend_member_value(
  base : Value,
  replacement : Value,
  source : Expr?,
) -> Value {
  match (base, replacement) {
    (ObjectValue(base_members), ObjectValue(over_members)) =>
      ObjectValue(merge_value_members(base_members, over_members))
    _ =>
      if amend_source_is_collection_body(source) {
        match concat_amend_collection_value(base, replacement) {
          Some(value) => value
          None => replacement
        }
      } else {
        replacement
      }
  }
}

///|
/// Monotonic counter that hands out a fresh identity stamp every time
/// a LambdaExpr is evaluated or a function declaration is loaded.
/// Distinct lambda literals get distinct ids, so structural payloads
/// no longer collide under `==`.
let lambda_id_counter : Ref[Int] = { val: 0 }

///|
fn fresh_function_id() -> Int {
  lambda_id_counter.val = lambda_id_counter.val + 1
  lambda_id_counter.val
}

///|
fn find_binding(bindings : Array[Binding], name : String) -> Binding? {
  let mut found : Binding? = None
  let hidden = hidden_member_name(name)
  for binding in bindings {
    if binding.name == name || binding.name == hidden {
      found = Some(binding)
    }
  }
  found
}

///|
/// PKL-148t: locate a sibling binding whose value is a `LambdaExpr`
/// (i.e., a module-level `function NAME(...) = ...` synthesised into
/// the binding list by `all_eval_bindings`). Used to break the
/// self-cycle when `qux = qux(...)` shadows a same-named function:
/// Apple Pkl resolves the RHS occurrence through the function
/// namespace before falling through to the property's own binding.
fn find_function_binding(bindings : Array[Binding], name : String) -> Binding? {
  for binding in bindings {
    if binding.name == name {
      match binding.value {
        LambdaExpr(_, _, _) => return Some(binding)
        _ => ()
      }
    }
  }
  None
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
              is_const: function_decl.is_const,
              annotations: function_decl.annotations,
              abstract_slot: false,
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
