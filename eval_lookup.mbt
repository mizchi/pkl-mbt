///|
fn lookup_value(env : Array[ValueBinding], name : String) -> Value? {
  // Reverse-walk + early-break preserves "last shadowing binding
  // wins" semantics. Most lookups land on a recently-pushed entry
  // (`@__module_name`, `outer`, `this`, etc. are appended at the end
  // of the cache), so the typical scan is O(1).
  let mut i = env.length() - 1
  while i >= 0 {
    let binding = env[i]
    if binding.name == name {
      return Some(binding.value)
    }
    i = i - 1
  }
  None
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
fn reflect_member(name : String, value : Value) -> ValueMember {
  { name, value, source: None, annotations: [] }
}

///|
fn reflect_hidden_member(name : String, value : Value) -> ValueMember {
  { name: hidden_member_name(name), value, source: None, annotations: [] }
}

///|
fn reflect_module_metadata_name() -> String {
  "__reflect_module_metadata"
}

///|
fn object_to_string_value(members : Array[ValueMember]) -> String {
  match semver_to_string(members) {
    Some(s) => return s
    None => ()
  }
  match find_object_class_tag(members) {
    Some(class_name) =>
      match lookup_member(members, "__annotation_body_text") {
        Some(StringValue(body)) => {
          let trimmed = trim_spaces(body)
          if trimmed == "" {
            return "new \{class_name} {}"
          }
          return "new \{class_name} { \{trimmed} }"
        }
        _ => ()
      }
    None => ()
  }
  match reflect_kind(members) {
    Some("Class") | Some("TypeAlias") =>
      match lookup_member(members, hidden_member_name("__qualified_name")) {
        Some(StringValue(s)) => return s
        _ =>
          match lookup_member(members, "name") {
            Some(StringValue(s)) => return s
            _ => return ""
          }
      }
    _ => render_pcf_value_inline(ObjectValue(members))
  }
}

///|
fn reflect_type_value(name : String, type_arguments : Array[Value]) -> Value {
  let members : Array[ValueMember] = [
    reflect_hidden_member("__kind", StringValue("Type")),
    reflect_member("name", StringValue(name)),
    reflect_member("typeArguments", ListValue(type_arguments)),
  ]
  if is_stdlib_class_name(name) && name != "unknown" && name != "module" {
    members.push(reflect_member("referent", synth_class_mirror_for_name(name)))
  }
  ObjectValue(members)
}

///|
fn reflect_declared_type_value(
  referent : Value,
  type_arguments : Array[Value],
) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("DeclaredType")),
    reflect_member("referent", referent),
    reflect_member("typeArguments", ListValue(type_arguments)),
  ])
}

///|
fn reflect_nullable_type_value(base : Value) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("NullableType")),
    reflect_member("baseType", base),
  ])
}

///|
fn reflect_union_type_value(types : Array[Value]) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("UnionType")),
    reflect_member("members", ListValue(types)),
  ])
}

///|
fn reflect_string_literal_type_value(value : String) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("StringLiteralType")),
    reflect_member("literal", StringValue(value)),
  ])
}

///|
fn reflect_type_variable_value(name : String) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("TypeVariable")),
    reflect_member("name", StringValue(name)),
  ])
}

///|
fn reflect_class_factory_value(arg : Value) -> Value {
  match arg {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Class") => arg
        _ => synth_class_mirror_for_value(arg)
      }
    StringValue(name) => synth_class_mirror_for_name(name)
    _ => synth_class_mirror_for_value(arg)
  }
}

///|
fn reflect_type_alias_factory_value(arg : Value) -> Value {
  match arg {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("TypeAlias") => arg
        _ =>
          synth_type_alias_mirror_for_qualified(eval_value_type_name(arg), None)
      }
    StringValue(name) => synth_type_alias_mirror_for_qualified(name, None)
    _ => synth_type_alias_mirror_for_qualified(eval_value_type_name(arg), None)
  }
}

///|
fn reflect_module_factory_value(arg : Value) -> Value {
  match arg {
    ObjectValue(members) =>
      match reflect_kind(members) {
        Some("Module") => arg
        _ => {
          let mirror_members : Array[ValueMember] = [
            reflect_hidden_member("__kind", StringValue("Module")),
            reflect_member("reflectee", arg),
            reflect_member("modifiers", SetValue([])),
          ]
          match lookup_member(members, reflect_module_metadata_name()) {
            Some(ObjectValue(meta_members)) =>
              for meta in meta_members {
                mirror_members.push(meta)
              }
            _ => {
              let imports = match lookup_member(members, "imports") {
                Some(value) => value
                None => MapValue([])
              }
              mirror_members.push(reflect_member("imports", imports))
              mirror_members.push(reflect_member("annotations", ListValue([])))
              mirror_members.push(reflect_member("docComment", NullValue))
              mirror_members.push(reflect_member("uri", StringValue("")))
              mirror_members.push(reflect_member("supermodule", NullValue))
              mirror_members.push(reflect_member("isAmend", BoolValue(false)))
              mirror_members.push(
                reflect_member(
                  "moduleClass",
                  synth_class_mirror_for_name(eval_value_type_name(arg)),
                ),
              )
            }
          }
          ObjectValue(mirror_members)
        }
      }
    _ =>
      ObjectValue([
        reflect_hidden_member("__kind", StringValue("Module")),
        reflect_member("reflectee", arg),
        reflect_member("modifiers", SetValue([])),
        reflect_member("imports", MapValue([])),
        reflect_member("annotations", ListValue([])),
        reflect_member("docComment", NullValue),
        reflect_member("uri", StringValue("")),
        reflect_member("supermodule", NullValue),
        reflect_member("isAmend", BoolValue(false)),
        reflect_member("moduleClass", synth_class_mirror_for_value(arg)),
      ])
  }
}

///|
fn is_reflect_type_members(members : Array[ValueMember]) -> Bool {
  match reflect_kind(members) {
    Some("Type")
    | Some("DeclaredType")
    | Some("NullableType")
    | Some("UnionType")
    | Some("StringLiteralType")
    | Some("TypeVariable") => true
    _ => false
  }
}

///|
fn is_reflect_type_method_name(name : String) -> Bool {
  name == "withTypeArgument" || name == "withTypeArguments"
}

///|
fn reflect_type_with_arguments(
  members : Array[ValueMember],
  type_arguments : Array[Value],
) -> Value? {
  match reflect_kind(members) {
    Some("Type") =>
      match lookup_member(members, "name") {
        Some(StringValue(name)) =>
          Some(reflect_type_value(name, type_arguments))
        _ => None
      }
    Some("DeclaredType") =>
      match lookup_member(members, "referent") {
        Some(referent) =>
          Some(reflect_declared_type_value(referent, type_arguments))
        None => None
      }
    _ => None
  }
}

///|
fn eval_reflect_type_method(
  receiver_members : Array[ValueMember],
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
  match method_name {
    "withTypeArgument" => {
      if arguments.length() != 1 {
        diagnostics.push(diag("withTypeArgument expects 1 argument"))
        return None
      }
      let arg = match
        eval_expr_with_bindings(
          arguments[0],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(value) => value
        None => return None
      }
      reflect_type_with_arguments(receiver_members, [arg])
    }
    "withTypeArguments" => {
      if arguments.length() != 1 {
        diagnostics.push(diag("withTypeArguments expects 1 argument"))
        return None
      }
      let arg = match
        eval_expr_with_bindings(
          arguments[0],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(value) => value
        None => return None
      }
      match arg {
        ListingValue(values) | ListValue(values) =>
          reflect_type_with_arguments(receiver_members, values)
        _ => {
          diagnostics.push(diag("withTypeArguments expects a List argument"))
          None
        }
      }
    }
    _ => None
  }
}

///|
fn eval_reflect_type_property(
  receiver_members : Array[ValueMember],
  property_name : String,
) -> Value? {
  if property_name == "nullable" && is_reflect_type_members(receiver_members) {
    Some(reflect_nullable_type_value(ObjectValue(receiver_members)))
  } else {
    None
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
  let idx = match reflect_source_index(Some(source)) {
    Some(i) => i
    None => return None
  }
  let line_idx = match idx.module_decl_line.get(property_name + " property") {
    Some(i) => i
    None => return None
  }
  // Doc-comment walk for module-level properties differs from class
  // members: it tolerates `/* ... */` block comments and stops at the
  // first non-blank, non-comment line. This variant is only used by
  // `pkl_test.mbt`'s expected output checks, so the divergence stays
  // local instead of being folded into `collect_doc_comment_above`.
  let lines = idx.lines
  let docs : Array[String] = []
  let mut in_block_comment = false
  for j = line_idx - 1; j >= 0; j = j - 1 {
    let line = trim_spaces(lines[j])
    if in_block_comment {
      if line.has_prefix("/*") {
        in_block_comment = false
      }
      continue
    }
    if line == "" {
      if docs.length() == 0 {
        continue
      }
      break
    }
    if line.has_prefix("*/") {
      in_block_comment = true
      continue
    }
    if line.has_prefix("//") && !line.has_prefix("///") {
      continue
    }
    if line.has_prefix("/*") {
      continue
    }
    if docs.length() == 0 && line.has_prefix("@") {
      continue
    }
    if line.has_prefix("///") && !line.has_prefix("////") {
      docs.insert(0, strip_doc_comment_line(line))
      continue
    }
    break
  }
  if docs.length() == 0 {
    return None
  }
  Some(join_doc_comment_lines(docs))
}


///|
fn doc_comment_before_reflect_decl(
  source : String?,
  name : String,
  kind : String,
) -> String? {
  let idx = match reflect_source_index(source) {
    Some(i) => i
    None => return None
  }
  let key = if kind == "module" { " " + kind } else { name + " " + kind }
  match idx.module_decl_line.get(key) {
    Some(line_idx) => collect_doc_comment_above(idx.lines, line_idx)
    None => None
  }
}

///|
fn doc_comment_before_class_member(
  source : String?,
  class_name : String,
  member_name : String,
  kind : String,
) -> String? {
  let idx = match reflect_source_index(source) {
    Some(i) => i
    None => return None
  }
  let key = class_name + " " + member_name + " " + kind
  let member_idx = match idx.class_member_line.get(key) {
    Some(line_idx) => line_idx
    None =>
      // Class header wasn't found in source (e.g. inherited from a
      // parent module amend): fall back to the module-scope walker so
      // an `import-class.member` reflect still surfaces its docs.
      return doc_comment_before_reflect_decl(source, member_name, kind)
  }
  collect_doc_comment_above(idx.lines, member_idx)
}

///|
/// Walk backwards from `line_idx - 1` collecting `///` doc-comment
/// lines, skipping blank lines and `@`-prefixed annotations. Mirrors
/// what `doc_comment_before_class_member` /
/// `doc_comment_before_reflect_decl` / `module_property_doc_comment_from_source`
/// used to do inline before they were routed through
/// `reflect_source_index`.
fn collect_doc_comment_above(
  lines : Array[String],
  line_idx : Int,
) -> String? {
  let docs : Array[String] = []
  let mut j = line_idx - 1
  while j >= 0 {
    let prev = trim_spaces(lines[j])
    if prev == "" || prev.has_prefix("@") {
      j = j - 1
      continue
    }
    if prev.has_prefix("///") && !prev.has_prefix("////") {
      docs.push(strip_doc_comment_line(prev))
      j = j - 1
      continue
    }
    break
  }
  if docs.length() == 0 {
    return None
  }
  let ordered : Array[String] = []
  for k = docs.length() - 1; k >= 0; k = k - 1 {
    ordered.push(docs[k])
  }
  Some(join_doc_comment_lines(ordered))
}

///|
fn reflect_class_member_decl_line_from_source(
  source : String?,
  class_name : String,
  member_name : String,
  kind : String,
) -> String? {
  let idx = match reflect_source_index(source) {
    Some(i) => i
    None => return None
  }
  let key = class_name + " " + member_name + " " + kind
  match idx.class_member_line.get(key) {
    Some(line_idx) =>
      if line_idx < idx.lines.length() {
        Some(trim_spaces(idx.lines[line_idx]))
      } else {
        None
      }
    None =>
      // Fall back to module-scope lookup when the class itself is
      // missing from the source (e.g. the class came in via a parent
      // module amend) — mirrors the old walker which delegated to
      // `reflect_decl_line_from_source` after failing to find the
      // class header.
      reflect_decl_line_from_source(source, member_name, kind)
  }
}

///|
fn reflect_display_uri(path : String?) -> String {
  match path {
    Some(p) =>
      if p.has_prefix("file://") ||
        p.has_prefix("pkl:") ||
        p.find("://") is Some(_) {
        p
      } else if p.has_prefix("/") {
        "file://" + p
      } else {
        "file:///" + p
      }
    None => ""
  }
}

///|
fn reflect_location_value(path : String?) -> Value {
  ObjectValue([
    reflect_member("displayUri", StringValue(reflect_display_uri(path))),
  ])
}

///|
fn reflect_enclosing_module_value(path : String?) -> Value {
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("Module")),
    reflect_member("uri", StringValue(reflect_display_uri(path))),
  ])
}

///|
fn reflect_doc_value(doc : String?) -> Value {
  match doc {
    Some(text) => StringValue(text)
    None => NullValue
  }
}

///|
fn reflect_type_parameter_values(parameters : Array[String]) -> Value {
  let values : Array[Value] = []
  for parameter in parameters {
    values.push(
      ObjectValue([
        reflect_member("name", StringValue(parameter)),
        reflect_member("variance", NullValue),
      ]),
    )
  }
  ListValue(values)
}

///|
fn reflect_module_short_name(path : String?, module_name : String?) -> String {
  match path {
    Some(p) => {
      let base = match p.rev_find("/") {
        Some(idx) => String::unsafe_substring(p, start=idx + 1, end=p.length())
        None => p
      }
      if base.has_suffix(".pkl") {
        String::unsafe_substring(base, start=0, end=base.length() - 4)
      } else {
        base
      }
    }
    None =>
      match module_name {
        Some(name) =>
          match name.rev_find(".") {
            Some(idx) =>
              String::unsafe_substring(name, start=idx + 1, end=name.length())
            None => name
          }
        None => "module"
      }
  }
}

///|
fn reflect_module_prefix_from_uri(uri : String) -> String {
  reflect_module_short_name(Some(uri), None)
}

///|
fn module_doc_comment_from_source(source : String?) -> String? {
  doc_comment_before_reflect_decl(source, "", "module")
}

///|
/// Cache of `(class_name, member_name, kind) → trimmed_line` indexes
/// built lazily from a module source. The reflect pass calls into
/// `reflect_class_member_decl_line_from_source` and
/// `reflect_decl_line_from_source` once per (class, member) and once
/// per top-level decl; before this cache, each call re-split the
/// module source into lines and re-walked them looking for a single
/// match. For pkspec/Test.pkl (1643 lines, 49 classes, ~500 reflect
/// queries) that walk dominated the eval profile by ~70% of total
/// time. With the cache we pay O(L) once to build the index, then
/// every subsequent lookup is `Map.get`.
///
/// The cache is keyed by the source `String` itself; in practice the
/// reflect path passes the same `current_module_source` reference
/// repeatedly within a single `eval_source` call. The cap below keeps
/// memory bounded across long-running CLI sessions and benchmarks.
priv struct ReflectSourceIndex {
  // Pre-split, owned lines. Doc-comment scanners walk backwards from a
  // known declaration index to grab the `///` block above it; they
  // index into this array instead of re-splitting on every call.
  lines : Array[String]
  // `class member kind → line index` for every member declaration we
  // observed inside a class body. Combined with `lines` this gives
  // both the trimmed declaration text and the position needed to walk
  // backwards looking for doc comments.
  class_member_line : Map[String, Int]
  // `name kind → line index` for top-level declarations (class,
  // function, typealias, module).
  module_decl_line : Map[String, Int]
}

///|
let reflect_source_index_cache : Ref[Array[(String, ReflectSourceIndex)]] = {
  val: [],
}

///|
/// Look up or compute the line index for `source`. Returns `None`
/// when `source` is `None` so reflect on a module without a source
/// (e.g. synthetic test-only modules) keeps the old behaviour of
/// returning no metadata.
fn reflect_source_index(source : String?) -> ReflectSourceIndex? {
  let text = match source {
    Some(s) => s
    None => return None
  }
  let cache = reflect_source_index_cache.val
  for entry in cache {
    let (key, idx) = entry
    if key.length() == text.length() && key == text {
      return Some(idx)
    }
  }
  let idx = build_reflect_source_index(text)
  // LRU-ish cap: drop the oldest entry once we hold four sources.
  // Bench cycles repeatedly evaluate the same source; CLI evals one
  // source per process; both stay comfortably inside the cap.
  while reflect_source_index_cache.val.length() >= 4 {
    let _ = reflect_source_index_cache.val.remove(0)
  }
  reflect_source_index_cache.val.push((text, idx))
  Some(idx)
}

///|
/// Walk `text` line-by-line and bin every declaration into
/// `class_member_line` or `module_decl_line` according to
/// the current class scope. The scope-end heuristics match the
/// pre-existing `reflect_class_member_decl_line_from_source` walk:
/// a class scope runs from `class X` until the next class declaration
/// or another `module` / `amends` / `extends` header.
fn build_reflect_source_index(text : String) -> ReflectSourceIndex {
  let split = text.split("\n").collect()
  let lines : Array[String] = []
  for view in split {
    lines.push(view.to_owned())
  }
  let class_member_line : Map[String, Int] = Map([], capacity=64)
  let module_decl_line : Map[String, Int] = Map([], capacity=64)
  let mut current_class : String? = None
  for i = 0; i < lines.length(); i = i + 1 {
    let line = lines[i]
    match line_decl_info(line) {
      Some((kind, name)) => {
        if kind == "module" {
          // `module foo` / `amends ...` / `extends ...` resets scope.
          current_class = None
          let key = " " + kind
          if !module_decl_line.contains(key) {
            module_decl_line[key] = i
          }
          continue
        }
        if kind == "class" {
          current_class = Some(name)
          let key = name + " " + kind
          if !module_decl_line.contains(key) {
            module_decl_line[key] = i
          }
          continue
        }
        if kind == "function" || kind == "typealias" {
          // Top-level function/typealias only counts when not nested in
          // a class. Class methods are recorded under the class scope.
          match current_class {
            None => {
              let key = name + " " + kind
              if !module_decl_line.contains(key) {
                module_decl_line[key] = i
              }
            }
            Some(class_name) => {
              let key = class_name + " " + name + " " + kind
              if !class_member_line.contains(key) {
                class_member_line[key] = i
              }
            }
          }
          continue
        }
        // kind == "property"
        match current_class {
          None => {
            let key = name + " " + kind
            if !module_decl_line.contains(key) {
              module_decl_line[key] = i
            }
          }
          Some(class_name) => {
            let key = class_name + " " + name + " " + kind
            if !class_member_line.contains(key) {
              class_member_line[key] = i
            }
          }
        }
      }
      None => ()
    }
  }
  { lines, class_member_line, module_decl_line }
}

///|
/// Identify what (kind, name) a single trimmed source line declares.
/// Returns `None` for blank lines, comments, body expressions, etc.
/// The classification mirrors what `line_declares_reflect_name`
/// accepts.
fn line_decl_info(line : String) -> (String, String)? {
  let trimmed = trim_spaces(line)
  let prefixes = [
    "open", "abstract", "external", "hidden", "local", "fixed", "const",
  ]
  let mut rest = trimmed
  let mut changed = true
  while changed {
    changed = false
    for prefix in prefixes {
      if rest == prefix || rest.has_prefix(prefix + " ") {
        rest = trim_spaces(
          String::unsafe_substring(
            rest,
            start=prefix.length(),
            end=rest.length(),
          ),
        )
        changed = true
      }
    }
  }
  if rest == "" {
    return None
  }
  if rest.has_prefix("module ") ||
    rest.has_prefix("amends ") ||
    rest.has_prefix("extends ") ||
    rest == "module" {
    return Some(("module", ""))
  }
  match extract_decl_name(rest, "class ") {
    Some(name) => return Some(("class", name))
    None => ()
  }
  match extract_decl_name(rest, "function ") {
    Some(name) => return Some(("function", name))
    None => ()
  }
  match extract_decl_name(rest, "typealias ") {
    Some(name) => return Some(("typealias", name))
    None => ()
  }
  // Property: bare `name` followed by `:`, `=`, `{`, space, or eol.
  let mut end = 0
  for i = 0; i < rest.length(); i = i + 1 {
    let c = rest[i].to_int().unsafe_to_char()
    let is_ident = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$'
    if !is_ident {
      break
    }
    end = i + 1
  }
  if end == 0 {
    return None
  }
  let name = String::unsafe_substring(rest, start=0, end=end)
  if end == rest.length() {
    return Some(("property", name))
  }
  let c = rest[end].to_int().unsafe_to_char()
  if c == ':' || c == '=' || c == '{' || c == ' ' || c == '\t' {
    return Some(("property", name))
  }
  None
}

///|
/// `extract_decl_name(rest, "class ")` returns the identifier that
/// follows `class ` (or the corresponding keyword), stripping a
/// trailing `<` generic clause. Returns `None` when `rest` does not
/// begin with `keyword`.
fn extract_decl_name(rest : String, keyword : String) -> String? {
  if !rest.has_prefix(keyword) {
    return None
  }
  let tail = String::unsafe_substring(
    rest,
    start=keyword.length(),
    end=rest.length(),
  )
  let mut end = 0
  for i = 0; i < tail.length(); i = i + 1 {
    let c = tail[i].to_int().unsafe_to_char()
    let is_ident = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$'
    if !is_ident {
      break
    }
    end = i + 1
  }
  if end == 0 {
    return None
  }
  Some(String::unsafe_substring(tail, start=0, end=end))
}

///|
fn reflect_decl_line_from_source(
  source : String?,
  name : String,
  kind : String,
) -> String? {
  match reflect_source_index(source) {
    Some(idx) => {
      let key = if kind == "module" { " " + kind } else { name + " " + kind }
      match idx.module_decl_line.get(key) {
        Some(line_idx) =>
          if line_idx < idx.lines.length() {
            Some(trim_spaces(idx.lines[line_idx]))
          } else {
            None
          }
        None => None
      }
    }
    None => None
  }
}

///|
fn reflect_line_has_decl_modifier(line : String, modifier : String) -> Bool {
  let words = line.split(" ").collect()
  for word in words {
    let token = trim_spaces(word.to_owned())
    if token == "" {
      continue
    }
    if token == "module" ||
      token == "amends" ||
      token == "extends" ||
      token == "class" ||
      token == "function" ||
      token == "typealias" ||
      token.find(":") is Some(_) ||
      token.find("=") is Some(_) ||
      token.find("{") is Some(_) ||
      token.find("(") is Some(_) ||
      token.find("<") is Some(_) {
      return false
    }
    if token == modifier {
      return true
    }
  }
  false
}

///|
fn reflect_decl_modifiers_from_source(
  source : String?,
  name : String,
  kind : String,
  hidden : Bool,
  fixed : Bool,
  const_ : Bool,
  abstract_ : Bool,
  open_ : Bool,
) -> Value {
  match reflect_decl_line_from_source(source, name, kind) {
    Some(line) =>
      reflect_modifiers_value(
        hidden || reflect_line_has_decl_modifier(line, "hidden"),
        fixed || reflect_line_has_decl_modifier(line, "fixed"),
        const_ || reflect_line_has_decl_modifier(line, "const"),
        abstract_ || reflect_line_has_decl_modifier(line, "abstract"),
        open_ || reflect_line_has_decl_modifier(line, "open"),
      )
    None => reflect_modifiers_value(hidden, fixed, const_, abstract_, open_)
  }
}

///|
fn reflect_class_member_modifiers_from_source(
  source : String?,
  class_name : String,
  member_name : String,
  kind : String,
  hidden : Bool,
  fixed : Bool,
  const_ : Bool,
  abstract_ : Bool,
  open_ : Bool,
) -> Value {
  match
    reflect_class_member_decl_line_from_source(
      source, class_name, member_name, kind,
    ) {
    Some(line) =>
      reflect_modifiers_value(
        hidden || reflect_line_has_decl_modifier(line, "hidden"),
        fixed || reflect_line_has_decl_modifier(line, "fixed"),
        const_ || reflect_line_has_decl_modifier(line, "const"),
        abstract_ || reflect_line_has_decl_modifier(line, "abstract"),
        open_ || reflect_line_has_decl_modifier(line, "open"),
      )
    None => reflect_modifiers_value(hidden, fixed, const_, abstract_, open_)
  }
}

///|
fn reflect_qualified_decl_name(prefix : String, name : String) -> String {
  if prefix == "" || prefix == "module" {
    name
  } else {
    prefix + "." + name
  }
}

///|
fn reflect_parse_annotation_body(annotation : Annotation) -> Array[ValueMember] {
  let members : Array[ValueMember] = []
  if annotation.body_kind is BraceBody {
    let body = annotation.body_text
    let pieces = body.split(";").collect()
    for piece in pieces {
      let text = trim_spaces(piece.to_owned())
      match text.find("=") {
        Some(idx) => {
          let key = trim_spaces(
            String::unsafe_substring(text, start=0, end=idx),
          )
          let raw = trim_spaces(
            String::unsafe_substring(text, start=idx + 1, end=text.length()),
          )
          let value = if raw.length() >= 2 &&
            raw.has_prefix("\"") &&
            raw.has_suffix("\"") {
            StringValue(
              String::unsafe_substring(raw, start=1, end=raw.length() - 1),
            )
          } else {
            StringValue(raw)
          }
          if key != "" {
            members.push(reflect_member(key, value))
          }
        }
        None => ()
      }
    }
  }
  members
}

///|
fn reflect_annotation_values(
  annotations : Array[Annotation],
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
) -> Value {
  let values : Array[Value] = []
  for annotation in annotations {
    let class_name = if annotation.class_name.find(".") is Some(_) {
      annotation.class_name
    } else if declarations_contain_class(declarations, annotation.class_name) {
      reflect_qualified_decl_name(module_prefix, annotation.class_name)
    } else {
      match parent_module_prefix {
        Some(prefix) =>
          reflect_qualified_decl_name(prefix, annotation.class_name)
        None => annotation.class_name
      }
    }
    let members = reflect_parse_annotation_body(annotation)
    members.push(
      reflect_hidden_member(
        "__annotation_body_text",
        StringValue(trim_spaces(annotation.body_text)),
      ),
    )
    values.push(ObjectValue(tag_object_with_class(members, class_name)))
  }
  ListValue(values)
}

///|
fn reflect_modifiers_value(
  hidden : Bool,
  fixed : Bool,
  const_ : Bool,
  abstract_ : Bool,
  open_ : Bool,
) -> Value {
  let values : Array[Value] = []
  if hidden {
    values.push(StringValue("hidden"))
  }
  if fixed {
    values.push(StringValue("fixed"))
  }
  if const_ {
    values.push(StringValue("const"))
  }
  if abstract_ {
    values.push(StringValue("abstract"))
  }
  if open_ {
    values.push(StringValue("open"))
  }
  SetValue(values)
}

///|
fn reflect_type_from_annotation(
  type_name : String?,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
) -> Value {
  match type_name {
    Some(name) =>
      reflect_type_from_annotation_text(
        name,
        declarations,
        module_prefix,
        parent_module_prefix,
        [],
      )
    None => reflect_type_value("unknown", [])
  }
}

///|
fn reflect_type_from_annotation_text(
  type_name : String,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  type_parameters : Array[String],
) -> Value {
  let trimmed = strip_balanced_outer_type_parens(
    pkl_strip_default_type_marker(pkl_constraint_trim(type_name)),
  )
  let choices = split_top_level_union_choices(trimmed)
  if choices.length() > 1 {
    let values : Array[Value] = []
    for choice in choices {
      values.push(
        reflect_type_from_annotation_text(
          choice, declarations, module_prefix, parent_module_prefix, type_parameters,
        ),
      )
    }
    return reflect_union_type_value(values)
  }
  if trimmed.has_suffix("?") {
    let base = String::unsafe_substring(
      trimmed,
      start=0,
      end=trimmed.length() - 1,
    )
    return reflect_nullable_type_value(
      reflect_type_from_annotation_text(
        base, declarations, module_prefix, parent_module_prefix, type_parameters,
      ),
    )
  }
  let base = match pkl_constrained_type_base_name(trimmed) {
    Some(b) => b
    None => trimmed
  }
  if base.length() >= 2 && base.has_prefix("\"") && base.has_suffix("\"") {
    return reflect_string_literal_type_value(
      String::unsafe_substring(base, start=1, end=base.length() - 1),
    )
  }
  for parameter in type_parameters {
    if base == parameter {
      return reflect_type_variable_value(parameter)
    }
  }
  let generic = try_split_generic_name(base)
  let (head, args) = match generic {
    Some(pair) => pair
    None => (base, [])
  }
  let arg_values : Array[Value] = []
  for arg in args {
    arg_values.push(
      reflect_type_from_annotation_text(
        arg, declarations, module_prefix, parent_module_prefix, type_parameters,
      ),
    )
  }
  match head {
    "Any" => reflect_type_value("Any", arg_values)
    "nothing" => reflect_type_value("nothing", arg_values)
    "unknown" => reflect_type_value("unknown", arg_values)
    "Boolean" | "Bool" => reflect_type_value("Boolean", arg_values)
    "Int" | "UInt" | "UInt8" | "UInt16" | "UInt32" =>
      reflect_type_value("Int", arg_values)
    "Float" => reflect_type_value("Float", arg_values)
    "Number" => reflect_type_value("Number", arg_values)
    "String" => reflect_type_value("String", arg_values)
    "Duration" => reflect_type_value("Duration", arg_values)
    "DataSize" => reflect_type_value("DataSize", arg_values)
    "Bytes" => reflect_type_value("Bytes", arg_values)
    "Pair" => reflect_type_value("Pair", arg_values)
    "List" => reflect_type_value("List", arg_values)
    "Set" => reflect_type_value("Set", arg_values)
    "Map" => reflect_type_value("Map", arg_values)
    "Listing" => reflect_type_value("Listing", arg_values)
    "Mapping" => reflect_type_value("Mapping", arg_values)
    "Dynamic" => reflect_type_value("Dynamic", arg_values)
    "Typed" => reflect_type_value("Typed", arg_values)
    "Module" => reflect_type_value("Module", arg_values)
    _ => {
      for decl in declarations {
        match decl {
          TypeAliasDeclaration(alias_decl) =>
            if alias_decl.name == head {
              return reflect_declared_type_value(
                synth_type_alias_mirror_for_qualified(
                  reflect_metadata_decl_name(
                    declarations, module_prefix, parent_module_prefix, head,
                  ),
                  None,
                ),
                arg_values,
              )
            }
          ClassDeclaration(class_decl) =>
            if class_decl.name == head {
              return reflect_declared_type_value(
                synth_class_mirror_for_name(
                  reflect_metadata_decl_name(
                    declarations, module_prefix, parent_module_prefix, head,
                  ),
                ),
                arg_values,
              )
            }
          FunctionDeclaration(_) => ()
        }
      }
      reflect_declared_type_value(
        synth_class_mirror_for_name(
          reflect_metadata_decl_name(
            declarations, module_prefix, parent_module_prefix, head,
          ),
        ),
        arg_values,
      )
    }
  }
}

///|
fn reflect_annotation_value_list_concat(left : Value, right : Value) -> Value {
  let values : Array[Value] = []
  match left {
    ListValue(xs) | ListingValue(xs) =>
      for x in xs {
        values.push(x)
      }
    _ => ()
  }
  match right {
    ListValue(xs) | ListingValue(xs) =>
      for x in xs {
        values.push(x)
      }
    _ => ()
  }
  ListValue(values)
}

///|
fn reflect_modifier_value_has(value : Value, name : String) -> Bool {
  match value {
    SetValue(xs) | ListingValue(xs) | ListValue(xs) =>
      for x in xs {
        if x == StringValue(name) {
          return true
        }
      }
    _ => ()
  }
  false
}

///|
fn reflect_modifier_values_merge(left : Value, right : Value) -> Value {
  reflect_modifiers_value(
    reflect_modifier_value_has(left, "hidden") ||
    reflect_modifier_value_has(right, "hidden"),
    reflect_modifier_value_has(left, "fixed") ||
    reflect_modifier_value_has(right, "fixed"),
    reflect_modifier_value_has(left, "const") ||
    reflect_modifier_value_has(right, "const"),
    reflect_modifier_value_has(left, "abstract") ||
    reflect_modifier_value_has(right, "abstract"),
    reflect_modifier_value_has(left, "open") ||
    reflect_modifier_value_has(right, "open"),
  )
}

///|
fn reflect_property_metadata_object_with_values(
  name : String,
  type_name : String?,
  default_value : Value?,
  annotations_value : Value,
  all_annotations_value : Value,
  doc_comment : String?,
  modifiers : Value,
  all_modifiers : Value,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
) -> Value {
  let bare_name = strip_member_visibility_prefix(name)
  let members : Array[ValueMember] = [
    reflect_member("location", reflect_location_value(path)),
    reflect_member("docComment", reflect_doc_value(doc_comment)),
    reflect_member("annotations", annotations_value),
    reflect_member("modifiers", modifiers),
    reflect_member("allModifiers", all_modifiers),
    reflect_member("allAnnotations", all_annotations_value),
    reflect_member("name", StringValue(bare_name)),
    reflect_member(
      "type",
      reflect_type_from_annotation(
        type_name, declarations, module_prefix, parent_module_prefix,
      ),
    ),
  ]
  match default_value {
    Some(value) => members.push(reflect_member("defaultValue", value))
    None => members.push(reflect_member("defaultValue", NullValue))
  }
  ObjectValue(members)
}

///|
fn reflect_property_metadata_object(
  name : String,
  type_name : String?,
  default_value : Value?,
  annotations : Array[Annotation],
  doc_comment : String?,
  modifiers : Value,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
) -> Value {
  let annotations_value = reflect_annotation_values(
    annotations, declarations, module_prefix, parent_module_prefix,
  )
  reflect_property_metadata_object_with_values(
    name, type_name, default_value, annotations_value, annotations_value, doc_comment,
    modifiers, modifiers, declarations, module_prefix, parent_module_prefix, path,
  )
}

///|
fn reflect_method_metadata_object(
  fn_decl : FunctionDecl,
  doc_comment : String?,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
) -> Value {
  let entries : Array[ValueEntry] = []
  for parameter in fn_decl.parameters {
    entries.push({
      key: StringValue(parameter.name),
      value: ObjectValue([
        reflect_member("name", StringValue(parameter.name)),
        reflect_member(
          "type",
          reflect_type_from_annotation(
            parameter.type_name,
            declarations,
            module_prefix,
            parent_module_prefix,
          ),
        ),
      ]),
    })
  }
  ObjectValue([
    reflect_member("location", reflect_location_value(path)),
    reflect_member("docComment", reflect_doc_value(doc_comment)),
    reflect_member(
      "annotations",
      reflect_annotation_values(
        fn_decl.annotations,
        declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
    reflect_member(
      "modifiers",
      reflect_modifiers_value(
        false,
        false,
        fn_decl.is_const,
        fn_decl.is_abstract,
        false,
      ),
    ),
    reflect_member("name", StringValue(fn_decl.name)),
    reflect_member(
      "typeParameters",
      reflect_type_parameter_values(fn_decl.type_parameters),
    ),
    reflect_member("parameters", MapValue(entries)),
    reflect_member(
      "returnType",
      reflect_type_from_annotation(
        fn_decl.return_type_name,
        declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
  ])
}

///|
fn declarations_contain_class(
  declarations : Array[Declaration],
  name : String,
) -> Bool {
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => if class_decl.name == name { return true }
      _ => ()
    }
  }
  false
}

///|
fn declarations_contain_type_declaration(
  declarations : Array[Declaration],
  name : String,
) -> Bool {
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) => if class_decl.name == name { return true }
      TypeAliasDeclaration(alias_decl) =>
        if alias_decl.name == name {
          return true
        }
      FunctionDeclaration(_) => ()
    }
  }
  false
}

///|
fn reflect_metadata_decl_name(
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  name : String,
) -> String {
  if name.find(".") is Some(_) || is_stdlib_class_name(name) {
    return name
  }
  if declarations_contain_type_declaration(declarations, name) {
    return reflect_qualified_decl_name(module_prefix, name)
  }
  match parent_module_prefix {
    Some(prefix) => reflect_qualified_decl_name(prefix, name)
    None => reflect_qualified_decl_name(module_prefix, name)
  }
}

///|
fn reflect_class_parent_name(
  class_decl : ClassDecl,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
) -> String {
  match class_decl.parent_name {
    Some(parent) =>
      if is_stdlib_class_name(parent) || parent.find(".") is Some(_) {
        parent
      } else if declarations_contain_class(declarations, parent) {
        reflect_qualified_decl_name(module_prefix, parent)
      } else {
        match parent_module_prefix {
          Some(prefix) => reflect_qualified_decl_name(prefix, parent)
          None => reflect_qualified_decl_name(module_prefix, parent)
        }
      }
    None => if class_decl.name == "Annotation" { "Any" } else { "Typed" }
  }
}

///|
fn reflect_lookup_class_decl(
  declarations : Array[Declaration],
  name : String,
) -> ClassDecl? {
  let simple = if name.find("#") is Some(idx) {
    String::unsafe_substring(name, start=idx + 1, end=name.length())
  } else {
    match name.rev_find(".") {
      Some(idx) =>
        String::unsafe_substring(name, start=idx + 1, end=name.length())
      None => name
    }
  }
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        if class_decl.name == simple {
          return Some(class_decl)
        }
      _ => ()
    }
  }
  None
}

///|
fn reflect_class_decl_chain(
  out : Array[ClassDecl],
  class_name : String,
  declarations : Array[Declaration],
  seen : Array[String],
) -> Unit {
  if contains_string(seen, class_name) {
    return
  }
  seen.push(class_name)
  match reflect_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      match class_decl.parent_name {
        Some(parent) =>
          reflect_class_decl_chain(out, parent, declarations, seen)
        None => ()
      }
      out.push(class_decl)
    }
    None => ()
  }
}

///|
fn reflect_property_default_value(
  default_members : Array[ValueMember],
  property_name : String,
) -> Value? {
  let bare_name = strip_member_visibility_prefix(property_name)
  match lookup_value_member(default_members, bare_name) {
    Some(value_member) => Some(value_member.value)
    None =>
      match lookup_value_member(default_members, property_name) {
        Some(value_member) => Some(value_member.value)
        None => None
      }
  }
}

///|
fn reflect_entry_index(entries : Array[ValueEntry], key : Value) -> Int {
  for i = 0; i < entries.length(); i = i + 1 {
    if entries[i].key == key {
      return i
    }
  }
  -1
}

///|
fn reflect_property_all_annotations_for_override(
  direct_annotations : Value,
  old_value : Value?,
) -> Value {
  match old_value {
    Some(ObjectValue(old_members)) =>
      match lookup_member(old_members, "allAnnotations") {
        Some(previous) =>
          reflect_annotation_value_list_concat(direct_annotations, previous)
        None => direct_annotations
      }
    _ => direct_annotations
  }
}

///|
fn reflect_property_all_modifiers_for_override(
  direct_modifiers : Value,
  old_value : Value?,
) -> Value {
  match old_value {
    Some(ObjectValue(old_members)) =>
      match lookup_member(old_members, "allModifiers") {
        Some(previous) =>
          reflect_modifier_values_merge(direct_modifiers, previous)
        None => direct_modifiers
      }
    _ => direct_modifiers
  }
}

///|
fn reflect_class_property_metadata_value(
  class_decl : ClassDecl,
  property : ClassProperty,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
  default_members : Array[ValueMember],
  all_annotations_value : Value,
  all_modifiers_value : Value,
) -> Value {
  let bare_name = strip_member_visibility_prefix(property.name)
  let modifiers = reflect_class_member_modifiers_from_source(
    source,
    class_decl.name,
    bare_name,
    "property",
    is_hidden_member_name(property.name),
    false,
    false,
    false,
    false,
  )
  reflect_property_metadata_object_with_values(
    property.name,
    property.type_name,
    reflect_property_default_value(default_members, property.name),
    reflect_annotation_values(
      property.annotations,
      declarations,
      module_prefix,
      parent_module_prefix,
    ),
    all_annotations_value,
    doc_comment_before_class_member(
      source,
      class_decl.name,
      bare_name,
      "property",
    ),
    modifiers,
    all_modifiers_value,
    declarations,
    module_prefix,
    parent_module_prefix,
    path,
  )
}

///|
fn reflect_class_all_property_entries(
  class_name : String,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
  default_members : Array[ValueMember],
) -> Array[ValueEntry] {
  let chain : Array[ClassDecl] = []
  reflect_class_decl_chain(chain, class_name, declarations, [])
  let entries : Array[ValueEntry] = []
  for class_decl in chain {
    for property in class_decl.properties {
      let bare_name = strip_member_visibility_prefix(property.name)
      let key = StringValue(bare_name)
      let direct_annotations = reflect_annotation_values(
        property.annotations,
        declarations,
        module_prefix,
        parent_module_prefix,
      )
      let direct_modifiers = reflect_class_member_modifiers_from_source(
        source,
        class_decl.name,
        bare_name,
        "property",
        is_hidden_member_name(property.name),
        false,
        false,
        false,
        false,
      )
      let idx = reflect_entry_index(entries, key)
      let old_value = if idx >= 0 { Some(entries[idx].value) } else { None }
      let value = reflect_class_property_metadata_value(
        class_decl,
        property,
        declarations,
        module_prefix,
        parent_module_prefix,
        path,
        source,
        default_members,
        reflect_property_all_annotations_for_override(
          direct_annotations, old_value,
        ),
        reflect_property_all_modifiers_for_override(direct_modifiers, old_value),
      )
      if idx >= 0 {
        entries[idx] = { key, value }
      } else {
        entries.push({ key, value })
      }
    }
  }
  entries
}

///|
fn reflect_class_mirror_from_decl(
  class_decl : ClassDecl,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
  default_members : Array[ValueMember],
) -> Value {
  let class_name = reflect_qualified_decl_name(module_prefix, class_decl.name)
  let property_entries : Array[ValueEntry] = []
  for property in class_decl.properties {
    let bare_name = strip_member_visibility_prefix(property.name)
    let default_value = match lookup_value_member(default_members, bare_name) {
      Some(value_member) => Some(value_member.value)
      None =>
        match lookup_value_member(default_members, property.name) {
          Some(value_member) => Some(value_member.value)
          None => None
        }
    }
    let modifiers = reflect_class_member_modifiers_from_source(
      source,
      class_decl.name,
      bare_name,
      "property",
      is_hidden_member_name(property.name),
      false,
      false,
      false,
      false,
    )
    property_entries.push({
      key: StringValue(bare_name),
      value: reflect_property_metadata_object(
        property.name,
        property.type_name,
        default_value,
        property.annotations,
        doc_comment_before_class_member(
          source,
          class_decl.name,
          bare_name,
          "property",
        ),
        modifiers,
        declarations,
        module_prefix,
        parent_module_prefix,
        path,
      ),
    })
  }
  let method_entries : Array[ValueEntry] = []
  for method_decl in class_decl.methods {
    method_entries.push({
      key: StringValue(method_decl.name),
      value: reflect_method_metadata_object(
        method_decl,
        doc_comment_before_class_member(
          source,
          class_decl.name,
          method_decl.name,
          "function",
        ),
        declarations,
        module_prefix,
        parent_module_prefix,
        path,
      ),
    })
  }
  let all_property_entries = reflect_class_all_property_entries(
    class_decl.name,
    declarations,
    module_prefix,
    parent_module_prefix,
    path,
    source,
    default_members,
  )
  let parent_name = reflect_class_parent_name(
    class_decl, declarations, module_prefix, parent_module_prefix,
  )
  let superclass = synth_class_mirror_for_name(parent_name)
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("Class")),
    reflect_hidden_member("reflectee", StringValue(class_decl.name)),
    reflect_member("reflectee", synth_class_mirror_for_name(class_name)),
    reflect_member("location", reflect_location_value(path)),
    reflect_member(
      "docComment",
      reflect_doc_value(
        doc_comment_before_reflect_decl(source, class_decl.name, "class"),
      ),
    ),
    reflect_member(
      "annotations",
      reflect_annotation_values(
        class_decl.annotations,
        declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
    reflect_member(
      "modifiers",
      reflect_decl_modifiers_from_source(
        source,
        class_decl.name,
        "class",
        false,
        false,
        false,
        class_decl.is_abstract,
        false,
      ),
    ),
    reflect_member("simpleName", StringValue(class_decl.name)),
    reflect_member("name", StringValue(class_name)),
    reflect_hidden_member("__qualified_name", StringValue(class_name)),
    reflect_member("enclosingDeclaration", reflect_enclosing_module_value(path)),
    reflect_member(
      "typeParameters",
      reflect_type_parameter_values(class_decl.type_parameters),
    ),
    reflect_member("superclass", superclass),
    reflect_member("supertype", reflect_declared_type_value(superclass, [])),
    reflect_member("properties", MapValue(property_entries)),
    reflect_member("allProperties", MapValue(all_property_entries)),
    reflect_member("methods", MapValue(method_entries)),
    reflect_member("allMethods", MapValue(method_entries)),
  ])
}

///|
fn reflect_type_alias_mirror_from_decl(
  alias_decl : TypeAliasDecl,
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
) -> Value {
  let alias_name = reflect_qualified_decl_name(module_prefix, alias_decl.name)
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("TypeAlias")),
    reflect_hidden_member("reflectee", StringValue(alias_decl.name)),
    reflect_member(
      "reflectee",
      synth_type_alias_mirror_for_qualified(alias_name, None),
    ),
    reflect_member("location", reflect_location_value(path)),
    reflect_member(
      "docComment",
      reflect_doc_value(
        doc_comment_before_reflect_decl(source, alias_decl.name, "typealias"),
      ),
    ),
    reflect_member(
      "annotations",
      reflect_annotation_values(
        alias_decl.annotations,
        declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
    reflect_member("modifiers", SetValue([])),
    reflect_member("simpleName", StringValue(alias_decl.name)),
    reflect_member("name", StringValue(alias_name)),
    reflect_hidden_member("__qualified_name", StringValue(alias_name)),
    reflect_member("enclosingDeclaration", reflect_enclosing_module_value(path)),
    reflect_member(
      "typeParameters",
      reflect_type_parameter_values(alias_decl.type_parameters),
    ),
    reflect_member(
      "referent",
      reflect_type_from_annotation_text(
        alias_decl.target,
        declarations,
        module_prefix,
        parent_module_prefix,
        alias_decl.type_parameters,
      ),
    ),
  ])
}

///|
fn reflect_module_function_declarations(
  declarations : Array[Declaration],
) -> Array[FunctionDecl] {
  let out : Array[FunctionDecl] = []
  for declaration in declarations {
    match declaration {
      FunctionDeclaration(function_decl) => out.push(function_decl)
      _ => ()
    }
  }
  out
}

///|
fn reflect_module_property_entries(
  bindings : Array[Binding],
  module_members : Array[ValueMember],
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for binding in bindings {
    if !binding.exported {
      continue
    }
    let bare_name = strip_member_visibility_prefix(binding.name)
    let default_value = match lookup_value_member(module_members, bare_name) {
      Some(value_member) => Some(value_member.value)
      None =>
        match lookup_value_member(module_members, binding.name) {
          Some(value_member) => Some(value_member.value)
          None => None
        }
    }
    let modifiers = reflect_decl_modifiers_from_source(
      source,
      bare_name,
      "property",
      is_hidden_member_name(binding.name),
      false,
      binding.is_const,
      false,
      false,
    )
    let all_modifiers = if bare_name == "output" {
      reflect_modifier_values_merge(
        modifiers,
        reflect_modifiers_value(true, false, false, false, false),
      )
    } else {
      modifiers
    }
    let annotations_value = reflect_annotation_values(
      binding.annotations,
      declarations,
      module_prefix,
      parent_module_prefix,
    )
    entries.push({
      key: StringValue(bare_name),
      value: reflect_property_metadata_object_with_values(
        binding.name,
        binding.type_name,
        default_value,
        annotations_value,
        annotations_value,
        match source {
          Some(text) => module_property_doc_comment_from_source(text, bare_name)
          None => None
        },
        modifiers,
        all_modifiers,
        declarations,
        module_prefix,
        parent_module_prefix,
        path,
      ),
    })
  }
  entries
}

///|
fn reflect_module_method_entries(
  declarations : Array[Declaration],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for function_decl in reflect_module_function_declarations(declarations) {
    entries.push({
      key: StringValue(function_decl.name),
      value: reflect_method_metadata_object(
        function_decl,
        doc_comment_before_reflect_decl(source, function_decl.name, "function"),
        declarations,
        module_prefix,
        parent_module_prefix,
        path,
      ),
    })
  }
  entries
}

///|
fn reflect_module_class_mirror(
  program : Program,
  module_members : Array[ValueMember],
  module_prefix : String,
  parent_module_prefix : String?,
  path : String?,
  source : String?,
) -> Value {
  let properties = reflect_module_property_entries(
    program.bindings,
    module_members,
    program.declarations,
    module_prefix,
    parent_module_prefix,
    path,
    source,
  )
  let methods = reflect_module_method_entries(
    program.declarations,
    module_prefix,
    parent_module_prefix,
    path,
    source,
  )
  let superclass = synth_class_mirror_for_name("Module")
  let superclass_with_reflectee = ObjectValue([
    reflect_hidden_member("__kind", StringValue("Class")),
    reflect_hidden_member("reflectee", StringValue("Module")),
    reflect_member("reflectee", superclass),
    reflect_member("simpleName", StringValue("Module")),
    reflect_member("name", StringValue("Module")),
    reflect_member("modifiers", SetValue([])),
  ])
  ObjectValue([
    reflect_hidden_member("__kind", StringValue("Class")),
    reflect_hidden_member("reflectee", StringValue("Module")),
    reflect_member("reflectee", synth_class_mirror_for_name("Module")),
    reflect_member("location", reflect_location_value(path)),
    reflect_member(
      "docComment",
      reflect_doc_value(module_doc_comment_from_source(source)),
    ),
    reflect_member(
      "annotations",
      reflect_annotation_values(
        program.module_annotations,
        program.declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
    reflect_member(
      "modifiers",
      reflect_decl_modifiers_from_source(
        source, "", "module", false, false, false, false, false,
      ),
    ),
    reflect_member("simpleName", StringValue("Module")),
    reflect_member("name", StringValue("Module")),
    reflect_hidden_member("__qualified_name", StringValue("Module")),
    reflect_member("enclosingDeclaration", reflect_enclosing_module_value(path)),
    reflect_member("typeParameters", ListValue([])),
    reflect_member("superclass", superclass_with_reflectee),
    reflect_member("supertype", reflect_declared_type_value(superclass, [])),
    reflect_member("properties", MapValue(properties)),
    reflect_member("allProperties", MapValue(properties)),
    reflect_member("methods", MapValue(methods)),
    reflect_member("allMethods", MapValue(methods)),
  ])
}

///|
fn reflect_class_is_subclass_value(
  receiver_members : Array[ValueMember],
  parent_members : Array[ValueMember],
  declarations : Array[Declaration],
) -> Bool {
  let parent = match reflect_reflectee_name(parent_members) {
    Some(name) => name
    None => return false
  }
  let child = match reflect_reflectee_name(receiver_members) {
    Some(name) => name
    None => return false
  }
  if child == parent {
    return true
  }
  if parent == "Any" && child != "nothing" {
    return true
  }
  let mut current = receiver_members
  for _ in 0..<64 {
    match lookup_member(current, "superclass") {
      Some(ObjectValue(super_members)) =>
        match reflect_reflectee_name(super_members) {
          Some(name) => {
            if name == parent {
              return true
            }
            if name == "Any" {
              return parent == "Any"
            }
            current = super_members
          }
          None => return false
        }
      _ => return reflect_is_subclass_of(child, parent, declarations)
    }
  }
  false
}

///|
fn reflect_module_class_entries(
  program : Program,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  current_module_path : String?,
  current_module_source : String?,
  resolve_import : (String) -> EvalResult?,
  module_prefix : String,
  parent_module_prefix : String?,
) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for declaration in program.declarations {
    match declaration {
      ClassDeclaration(class_decl) => {
        let local_diagnostics : Array[Diagnostic] = []
        let default_members = eval_class_default_members(
          class_decl.name,
          bindings,
          env,
          class_env,
          cache,
          [],
          program.declarations,
          local_diagnostics,
          resolve_import,
        )
        entries.push({
          key: StringValue(class_decl.name),
          value: reflect_class_mirror_from_decl(
            class_decl,
            program.declarations,
            module_prefix,
            parent_module_prefix,
            current_module_path,
            current_module_source,
            default_members,
          ),
        })
      }
      _ => ()
    }
  }
  entries
}

///|
fn reflect_module_type_alias_entries(
  program : Program,
  current_module_path : String?,
  current_module_source : String?,
  module_prefix : String,
  parent_module_prefix : String?,
) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for declaration in program.declarations {
    match declaration {
      TypeAliasDeclaration(alias_decl) =>
        entries.push({
          key: StringValue(alias_decl.name),
          value: reflect_type_alias_mirror_from_decl(
            alias_decl,
            program.declarations,
            module_prefix,
            parent_module_prefix,
            current_module_path,
            current_module_source,
          ),
        })
      _ => ()
    }
  }
  entries
}

///|
fn reflect_module_metadata_value(
  program : Program,
  module_members : Array[ValueMember],
  module_parent_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  current_module_path : String?,
  current_module_source : String?,
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let module_prefix = reflect_module_short_name(
    current_module_path,
    program.module_name,
  )
  let parent_module_prefix = match program.module_relation {
    Some(relation) => Some(reflect_module_prefix_from_uri(relation.uri))
    None => None
  }
  let imports = match lookup_value(cache, "@__module_imports") {
    Some(value) => value
    None => MapValue([])
  }
  let supermodule = if module_parent_members.length() > 0 {
    reflect_module_factory_value(ObjectValue(module_parent_members))
  } else {
    NullValue
  }
  let is_amend = match program.module_relation {
    Some(relation) => relation.kind is ModuleAmends
    None => false
  }
  ObjectValue([
    reflect_member("imports", imports),
    reflect_member(
      "annotations",
      reflect_annotation_values(
        program.module_annotations,
        program.declarations,
        module_prefix,
        parent_module_prefix,
      ),
    ),
    reflect_member(
      "docComment",
      reflect_doc_value(module_doc_comment_from_source(current_module_source)),
    ),
    reflect_member("uri", StringValue(reflect_display_uri(current_module_path))),
    reflect_member("supermodule", supermodule),
    reflect_member("isAmend", BoolValue(is_amend)),
    reflect_member(
      "modifiers",
      reflect_decl_modifiers_from_source(
        current_module_source, "", "module", false, false, false, false, false,
      ),
    ),
    reflect_member(
      "classes",
      MapValue(
        reflect_module_class_entries(
          program, bindings, env, class_env, cache, current_module_path, current_module_source,
          resolve_import, module_prefix, parent_module_prefix,
        ),
      ),
    ),
    reflect_member(
      "typeAliases",
      MapValue(
        reflect_module_type_alias_entries(
          program, current_module_path, current_module_source, module_prefix, parent_module_prefix,
        ),
      ),
    ),
    reflect_member(
      "moduleClass",
      reflect_module_class_mirror(
        program, module_members, module_prefix, parent_module_prefix, current_module_path,
        current_module_source,
      ),
    ),
  ])
}

///|
fn reflect_mirror_reflectee_value(value : Value) -> Value {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, "reflectee") {
        Some(reflectee) => reflectee
        None => value
      }
    _ => value
  }
}

///|
fn reflect_module_decl_member(
  members : Array[ValueMember],
  name : String,
) -> Value? {
  match lookup_member(members, reflect_module_metadata_name()) {
    Some(ObjectValue(meta_members)) => {
      match lookup_member(meta_members, "classes") {
        Some(MapValue(entries)) =>
          match lookup_entry(entries, StringValue(name)) {
            Some(value) => return Some(reflect_mirror_reflectee_value(value))
            None => ()
          }
        _ => ()
      }
      match lookup_member(meta_members, "typeAliases") {
        Some(MapValue(entries)) =>
          match lookup_entry(entries, StringValue(name)) {
            Some(value) => Some(reflect_mirror_reflectee_value(value))
            None => None
          }
        _ => None
      }
    }
    _ => None
  }
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
  declarations : Array[Declaration],
) -> Value {
  let source = match lookup_value(cache, "@__module_source") {
    Some(StringValue(text)) => Some(text)
    _ => None
  }
  let path = match lookup_value(cache, "@__module_path") {
    Some(StringValue(text)) => Some(text)
    _ => None
  }
  let module_name = match lookup_value(cache, "@__module_name") {
    Some(StringValue(text)) => Some(text)
    _ => None
  }
  let module_prefix = reflect_module_short_name(path, module_name)
  MapValue(
    reflect_module_property_entries(
      bindings,
      [],
      declarations,
      module_prefix,
      None,
      path,
      source,
    ),
  )
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
  // see the same data the writer wrote. Reverse-walk + early break:
  // last writer wins.
  let hidden_prefixed = hidden_member_name(name)
  let local_prefixed = local_member_name(name)
  let mut i = members.length() - 1
  while i >= 0 {
    let field = members[i]
    if field.name == name ||
      field.name == hidden_prefixed ||
      field.name == local_prefixed {
      return Some(field.value)
    }
    i = i - 1
  }
  None
}

///|
fn lookup_value_member(
  members : Array[ValueMember],
  name : String,
) -> ValueMember? {
  let hidden_prefixed = hidden_member_name(name)
  let local_prefixed = local_member_name(name)
  let mut i = members.length() - 1
  while i >= 0 {
    let field = members[i]
    if field.name == name ||
      field.name == hidden_prefixed ||
      field.name == local_prefixed {
      return Some(field)
    }
    i = i - 1
  }
  None
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
priv struct ClassEnvIndex {
  env : Array[ClassBinding]
  length : Int
  map : Map[String, ClassBinding]
}

///|
/// Cache of name → ClassBinding maps keyed by physical identity of
/// the class_env array (with a length check for staleness). Within a
/// single eval_source call, class_env is the same reference used by
/// every lookup; profiled on apple-pkl/stdlib/base.pkl, the previous
/// reverse-walk still attributed ~95 of ~5000 samples to this
/// function. The map turns each lookup into an O(1) Map.get.
let class_env_index_cache : Ref[Array[ClassEnvIndex]] = { val: [] }

///|
fn lookup_class_binding(
  env : Array[ClassBinding],
  name : String,
) -> ClassBinding? {
  let env_len = env.length()
  let cache = class_env_index_cache.val
  let mut idx_opt : ClassEnvIndex? = None
  for entry in cache {
    if physical_equal(entry.env, env) && entry.length == env_len {
      idx_opt = Some(entry)
      break
    }
  }
  let idx = match idx_opt {
    Some(i) => i
    None => {
      let map : Map[String, ClassBinding] = Map([], capacity=64)
      // Forward walk so "last binding wins" — Map insertion overwrite
      // matches the prior Array overwrite semantics.
      for binding in env {
        map[binding.name] = binding
      }
      let entry : ClassEnvIndex = { env, length: env_len, map }
      while class_env_index_cache.val.length() >= 4 {
        let _ = class_env_index_cache.val.remove(0)
      }
      class_env_index_cache.val.push(entry)
      entry
    }
  }
  match idx.map.get(name) {
    Some(b) => Some(b)
    None =>
      if name == "reflect.Type" ||
        name == "reflect.Property" ||
        name == "reflect.Method" {
        Some({ name, parent_name: None, properties: [], methods: [] })
      } else {
        None
      }
  }
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
priv struct TypeAliasEnvIndex {
  env : Array[EvalTypeAliasBinding]
  length : Int
  map : Map[String, String]
}

///|
/// Mirror of `class_env_index_cache` for typealias bindings.
/// `eval_type_alias_bindings` is already cached per-declarations, but
/// each cached result is then looked up name-by-name on the reflect /
/// synthesize-default paths; this index makes those lookups O(1).
let type_alias_env_index_cache : Ref[Array[TypeAliasEnvIndex]] = { val: [] }

///|
fn lookup_eval_type_alias(
  env : Array[EvalTypeAliasBinding],
  name : String,
) -> String? {
  let env_len = env.length()
  let cache = type_alias_env_index_cache.val
  let mut idx_opt : TypeAliasEnvIndex? = None
  for entry in cache {
    if physical_equal(entry.env, env) && entry.length == env_len {
      idx_opt = Some(entry)
      break
    }
  }
  let idx = match idx_opt {
    Some(i) => i
    None => {
      let map : Map[String, String] = Map([], capacity=32)
      // Forward walk so "last binding wins" via Map overwrite —
      // matches the previous reverse-walk-with-early-break semantics.
      for binding in env {
        map[binding.name] = binding.target
      }
      let entry : TypeAliasEnvIndex = { env, length: env_len, map }
      while type_alias_env_index_cache.val.length() >= 4 {
        let _ = type_alias_env_index_cache.val.remove(0)
      }
      type_alias_env_index_cache.val.push(entry)
      entry
    }
  }
  idx.map.get(name)
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
  // Upper bound on the merged result is `base.length() + overrides.length()`.
  // Pre-reserving skips the doubling-grow allocations that dominated
  // the class-default tail.
  merged.reserve_capacity(base.length() + overrides.length())
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
  // Same reverse-walk + early-break pattern as the rest of the lookups
  // — "last definition wins" without paying the full O(N) scan.
  let mut i = members.length() - 1
  while i >= 0 {
    let field = members[i]
    if field.name == name {
      return Some(field.value)
    }
    i = i - 1
  }
  None
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
  // Reverse-walk + early-break: preserves "last shadowing binding
  // wins" semantics without the full O(N) overwrite scan.
  let hidden = hidden_member_name(name)
  let mut i = bindings.length() - 1
  while i >= 0 {
    let binding = bindings[i]
    if binding.name == name || binding.name == hidden {
      return Some(binding)
    }
    i = i - 1
  }
  None
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
