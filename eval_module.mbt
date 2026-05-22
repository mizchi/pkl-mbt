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
  if parent_name.find(".") is Some(_) || is_stdlib_class_name(parent_name) {
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
    if !decl.is_glob {
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
  current_module_path : String?,
  env : Array[ValueBinding],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Unit {
  for decl in imports {
    if decl.is_glob {
      match
        eval_import_glob_value(
          decl.uri,
          current_module_path,
          diagnostics,
          resolve_import,
        ) {
        Some(value) => env.push({ name: decl.import_name, value })
        None => ()
      }
    } else {
      match resolve_import(decl.uri) {
        Some(EvalOk(value)) => env.push({ name: decl.import_name, value })
        Some(EvalError(errors)) =>
          for error in errors {
            diagnostics.push(error)
          }
        None => diagnostics.push(diag("Cannot find module `\{decl.uri}`."))
      }
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
      diagnostics.push(
        diag("module \{relation_kind_name(relation.kind)} expects Object"),
      )
      []
    }
    Some(EvalError(errors)) => {
      for error in errors {
        diagnostics.push(error)
      }
      []
    }
    None => {
      diagnostics.push(diag("Cannot find module `\{relation.uri}`."))
      []
    }
  }
}

///|
fn module_metadata_name() -> String {
  "__module_name"
}

///|
fn module_metadata_super_name() -> String {
  "__module_super"
}

///|
fn module_metadata_path_name() -> String {
  "__module_path"
}

///|
fn module_members_name(members : Array[ValueMember]) -> String? {
  match lookup_member(members, module_metadata_name()) {
    Some(StringValue(name)) => Some(name)
    _ => None
  }
}

///|
fn module_members_super(members : Array[ValueMember]) -> Array[ValueMember]? {
  match lookup_member(members, module_metadata_super_name()) {
    Some(ObjectValue(super_members)) => Some(super_members)
    _ => None
  }
}

///|
fn is_module_member_set(members : Array[ValueMember]) -> Bool {
  module_members_name(members) is Some(_) ||
  module_members_super(members) is Some(_)
}

///|
fn module_super_members_from_cache(
  cache : Array[ValueBinding],
) -> Array[ValueMember]? {
  match lookup_value(cache, "super") {
    Some(ObjectValue(members)) =>
      if is_module_member_set(members) {
        Some(members)
      } else {
        None
      }
    _ => None
  }
}

///|
fn is_module_runtime_metadata_name(name : String) -> Bool {
  let bare = strip_member_visibility_prefix(name)
  bare == module_metadata_name() ||
  bare == module_metadata_super_name() ||
  bare == reflect_module_metadata_name() ||
  bare == "__class" ||
  bare == "__kind" ||
  bare == "__qualified_name"
}

///|
fn should_overlay_module_receiver_binding(name : String) -> Bool {
  if name == "super" || name == "this" || is_error_member_name(name) {
    return false
  }
  if name.has_prefix("@") &&
    !is_hidden_member_name(name) &&
    !is_local_member_name(name) {
    return false
  }
  !is_module_runtime_metadata_name(name)
}

///|
fn module_receiver_binding_name(name : String) -> String {
  strip_member_visibility_prefix(name)
}

///|
fn module_binding_shadowed_by_receiver(
  name : String,
  receiver_bindings : Array[Binding],
) -> Bool {
  find_binding(receiver_bindings, module_receiver_binding_name(name)) is Some(_)
}

///|
fn bind_module_function_receiver(
  value : Value,
  receiver_cache : Array[ValueBinding],
  receiver_bindings : Array[Binding],
) -> Value {
  match value {
    FunctionValue(parameters, body, return_type_name, captured_env, id) => {
      let rebound : Array[ValueBinding] = []
      for captured in captured_env {
        if should_overlay_module_receiver_binding(captured.name) &&
          module_binding_shadowed_by_receiver(captured.name, receiver_bindings) {
          continue
        }
        rebound.push(captured)
      }
      for receiver in receiver_cache {
        if should_overlay_module_receiver_binding(receiver.name) {
          rebound.push({
            name: module_receiver_binding_name(receiver.name),
            value: receiver.value,
          })
        }
      }
      FunctionValue(parameters, body, return_type_name, rebound, id)
    }
    _ => value
  }
}

///|
fn module_parent_reeval_env(
  owner_members : Array[ValueMember],
  receiver_bindings : Array[Binding],
  env : Array[ValueBinding],
  receiver_cache : Array[ValueBinding],
) -> Array[ValueBinding] {
  let local_env : Array[ValueBinding] = []
  for value_member in owner_members {
    if is_error_member_name(value_member.name) ||
      is_module_runtime_metadata_name(value_member.name) {
      continue
    }
    let bare = strip_member_visibility_prefix(value_member.name)
    if find_binding(receiver_bindings, bare) is Some(_) {
      continue
    }
    local_env.push({
      name: bare,
      value: bind_module_function_receiver(
        value_member.value,
        receiver_cache,
        receiver_bindings,
      ),
    })
  }
  for binding in env {
    local_env.push(binding)
  }
  for binding in receiver_cache {
    if should_overlay_module_receiver_binding(binding.name) {
      local_env.push({
        name: module_receiver_binding_name(binding.name),
        value: binding.value,
      })
    }
  }
  local_env
}

///|
fn module_parent_reeval_cache(
  owner_members : Array[ValueMember],
  receiver_cache : Array[ValueBinding],
) -> Array[ValueBinding] {
  let local_cache : Array[ValueBinding] = []
  for binding in receiver_cache {
    if binding.name != "super" {
      local_cache.push(binding)
    }
  }
  match module_members_super(owner_members) {
    Some(super_members) =>
      local_cache.push({ name: "super", value: ObjectValue(super_members) })
    None => ()
  }
  local_cache
}

///|
fn resolve_module_parent_member_value(
  member_name : String,
  parent_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match lookup_value_member(parent_members, member_name) {
    Some(value_member) =>
      match value_member.value {
        FunctionValue(_, _, _, _, _) =>
          Some(
            bind_module_function_receiver(value_member.value, cache, bindings),
          )
        _ =>
          match value_member.source {
            Some(source) =>
              if expr_references_super(source) ||
                expr_references_late_binding(source, "module") {
                eval_expr_with_bindings(
                  source,
                  bindings,
                  module_parent_reeval_env(parent_members, bindings, env, cache),
                  class_env,
                  module_parent_reeval_cache(parent_members, cache),
                  stack,
                  declarations,
                  diagnostics,
                  resolve_import,
                )
              } else {
                Some(value_member.value)
              }
            None => Some(value_member.value)
          }
      }
    None => None
  }
}

///|
fn late_bind_module_parent_members(
  parent_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ValueMember] {
  if !is_module_member_set(parent_members) {
    return parent_members
  }
  let rebound : Array[ValueMember] = []
  for value_member in parent_members {
    if is_module_runtime_metadata_name(value_member.name) {
      rebound.push(value_member)
      continue
    }
    let value = match
      resolve_module_parent_member_value(
        strip_member_visibility_prefix(value_member.name),
        parent_members,
        bindings,
        env,
        class_env,
        cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(v) => v
      None => value_member.value
    }
    rebound.push({
      name: value_member.name,
      value,
      source: value_member.source,
      annotations: value_member.annotations,
    })
  }
  rebound
}

///|
fn sandbox_resource_value(resource : SandboxResource) -> Value {
  ObjectValue(
    tag_object_with_class(
      [
        {
          name: "uri",
          value: StringValue(resource.resource_uri),
          source: None,
          annotations: [],
        },
        {
          name: "text",
          value: StringValue(resource.text),
          source: None,
          annotations: [],
        },
        {
          name: "base64",
          value: StringValue(@base64.encode(@utf8.encode(resource.text))),
          source: None,
          annotations: [],
        },
      ],
      "Resource",
    ),
  )
}

///|
fn sort_value_entries_by_string_key(
  entries : Array[ValueEntry],
) -> Array[ValueEntry] {
  let out = entries[:].to_owned()
  for i = 1; i < out.length(); i = i + 1 {
    let cur = out[i]
    let cur_key = value_entry_string_key(cur)
    let mut j = i - 1
    while j >= 0 &&
          string_greater_codepoint(value_entry_string_key(out[j]), cur_key) {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = cur
  }
  out
}

///|
fn string_greater_codepoint(a : String, b : String) -> Bool {
  let mut i = 0
  while i < a.length() && i < b.length() {
    if a[i] > b[i] {
      return true
    }
    if a[i] < b[i] {
      return false
    }
    i = i + 1
  }
  a.length() > b.length()
}

///|
fn value_entry_string_key(entry : ValueEntry) -> String {
  match entry.key {
    StringValue(s) => s
    _ => value_to_string_for_join(entry.key)
  }
}

///|
fn env_read_glob_entries(rest_pattern : String) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for pair in sandbox_env_entries() {
    let (name, value) = pair
    let visible_name = sandbox_percent_encode_resource_key(name)
    if sandbox_glob_matches(rest_pattern, visible_name) {
      entries.push({
        key: StringValue("env:" + visible_name),
        value: StringValue(value),
      })
    }
  }
  sort_value_entries_by_string_key(entries)
}

///|
fn prop_read_glob_entries(rest_pattern : String) -> Array[ValueEntry] {
  let entries : Array[ValueEntry] = []
  for pair in sandbox_prop_entries() {
    let (name, value) = pair
    let visible_name = sandbox_percent_encode_resource_key(name)
    if sandbox_glob_matches(rest_pattern, visible_name) {
      entries.push({
        key: StringValue("prop:" + visible_name),
        value: StringValue(value),
      })
    }
  }
  sort_value_entries_by_string_key(entries)
}

///|
fn eval_cached_read_glob(
  pattern : String,
  current_module_path : String?,
) -> Value? {
  match current_module_path {
    Some(path) =>
      match sandbox_lookup_read_glob(path, pattern) {
        Some(resources) => {
          let entries : Array[ValueEntry] = []
          for resource in resources {
            entries.push({
              key: StringValue(resource.uri),
              value: sandbox_resource_value(resource),
            })
          }
          Some(MappingValue(entries))
        }
        None => None
      }
    None => None
  }
}

///|
fn eval_import_glob_value(
  pattern : String,
  current_module_path : String?,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match current_module_path {
    Some(path) =>
      match sandbox_lookup_import_glob(path, pattern) {
        Some(uris) => {
          let entries : Array[ValueEntry] = []
          for visible_uri in uris {
            let value = match
              sandbox_lookup_import_glob_error(path, pattern, visible_uri) {
              Some(message) => deferred_error_value(message)
              None =>
                match resolve_import(visible_uri) {
                  Some(EvalOk(value)) => value
                  _ => DeferredImportValue(visible_uri)
                }
            }
            entries.push({ key: StringValue(visible_uri), value })
          }
          Some(MappingValue(entries))
        }
        None => {
          diagnostics.push(diag("Cannot find module `\{pattern}`."))
          None
        }
      }
    None => {
      diagnostics.push(diag("Cannot find module `\{pattern}`."))
      None
    }
  }
}

///|
fn eval_read_glob(
  pattern : String,
  current_module_path : String?,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match pattern.find(":") {
    Some(idx) => {
      let scheme = String::unsafe_substring(pattern, start=0, end=idx)
      let rest = String::unsafe_substring(
        pattern,
        start=idx + 1,
        end=pattern.length(),
      )
      if scheme == "env" {
        Some(MappingValue(env_read_glob_entries(rest)))
      } else if scheme == "prop" {
        Some(MappingValue(prop_read_glob_entries(rest)))
      } else {
        match eval_cached_read_glob(pattern, current_module_path) {
          Some(value) => Some(value)
          None => {
            diagnostics.push(
              diag(
                "read: scheme \{scheme}: is not allowed by the sandbox policy",
              ),
            )
            None
          }
        }
      }
    }
    None =>
      match current_module_path {
        Some(path) =>
          match sandbox_lookup_read_glob(path, pattern) {
            Some(_) => eval_cached_read_glob(pattern, current_module_path)
            None => {
              diagnostics.push(diag("Cannot find module `\{pattern}`."))
              None
            }
          }
        None => {
          diagnostics.push(diag("Cannot find module `\{pattern}`."))
          None
        }
      }
  }
}

///|
fn eval_read_uri(
  uri : String,
  current_module_path : String?,
  diagnostics : Array[Diagnostic],
) -> Value? {
  // PKL-098 / PKL-106 sandbox policy: `env:` is always on the
  // allow-list; `prop:` is allow-listed when the CLI installed at
  // least one `-p NAME=VALUE` binding. The remaining Apple Pkl
  // schemes (`file:`, `https:`, `package:`) still need explicit
  // policy decisions before they ship; surfacing them as a
  // diagnostic keeps the failure mode honest until those follow-up
  // slices land.
  match uri.find(":") {
    None =>
      match current_module_path {
        Some(path) =>
          match sandbox_lookup_read_resource(path, uri) {
            Some(resource) => Some(sandbox_resource_value(resource))
            None => {
              diagnostics.push(diag(read_resource_not_found_message(uri)))
              None
            }
          }
        None => {
          diagnostics.push(diag(read_resource_not_found_message(uri)))
          None
        }
      }
    Some(idx) => {
      let scheme = String::unsafe_substring(uri, start=0, end=idx)
      let rest = String::unsafe_substring(uri, start=idx + 1, end=uri.length())
      if scheme == "env" {
        match sandbox_lookup_env(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag(read_resource_not_found_message(uri)))
            None
          }
        }
      } else if scheme == "prop" {
        match sandbox_lookup_prop(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag(read_resource_not_found_message(uri)))
            None
          }
        }
      } else {
        match current_module_path {
          Some(path) =>
            match sandbox_lookup_read_resource(path, uri) {
              Some(resource) => Some(sandbox_resource_value(resource))
              None => {
                diagnostics.push(diag(read_resource_refused_message(uri)))
                None
              }
            }
          None => {
            diagnostics.push(diag(read_resource_refused_message(uri)))
            None
          }
        }
      }
    }
  }
}

///|
fn read_resource_not_found_message(uri : String) -> String {
  "Cannot find resource `\{uri}`."
}

///|
fn read_resource_refused_message(uri : String) -> String {
  "Refusing to read resource `\{uri}` because it does not match any entry in the resource allowlist (`--allowed-resources`)."
}

///|
fn is_read_resource_refusal(message : String) -> Bool {
  message.has_prefix("Refusing to read resource `")
}

///|
fn pkl_test_catch_lambda_body(expr : Expr) -> Expr? {
  // PKL-147: snippetTest fixtures call `module.catch(() -> ...)` where
  // `catch` is inherited via `extends "pkl:test"`. Recognise both the
  // bare `test.catch(...)` form (binding-time intercept on the top
  // binding) and the `module.catch(...)` form so a fixture that uses
  // the module-self reference still routes through this stub. PKL-148o
  // extends the same lambda extraction to `catchOrNull`.
  let arguments = match expr {
    CallExpr(MemberAccess(Identifier("test"), "catch"), args) => args
    CallExpr(MemberAccess(Identifier("module"), "catch"), args) => args
    CallExpr(MemberAccess(Identifier("test"), "catchOrNull"), args) => args
    CallExpr(MemberAccess(Identifier("module"), "catchOrNull"), args) => args
    _ => return None
  }
  if arguments.length() != 1 {
    return None
  }
  match arguments[0] {
    LambdaExpr(parameters, body, _) =>
      if parameters.length() == 0 {
        Some(body)
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
  // PKL-148o: when this entry recognises the bound expression as a
  // `catch` / `catchOrNull` call, dispatch through the form-specific
  // wrapper so the no-throw branch lines up with Apple Pkl's
  // semantics: `catch` throws `Expected an exception, but none was
  // thrown.`; `catchOrNull` returns `null`. The shared
  // `pkl_test_catch_lambda_body` already accepts both forms, so the
  // dispatch is keyed off the AST shape itself.
  match pkl_test_catch_form_kind(expr) {
    Some(CatchOrNullForm) =>
      eval_pkl_test_catch_or_null_binding_value(
        expr, bindings, env, class_env, cache, stack, declarations, resolve_import,
      )
    Some(CatchForm) =>
      match
        eval_pkl_test_catch_outcome(
          expr, bindings, env, class_env, cache, stack, declarations, resolve_import,
        ) {
        Some(ThrewOutcome(message)) => Some(StringValue(message))
        Some(NoThrowOutcome) =>
          Some(StringValue("Expected an exception, but none was thrown."))
        None => None
      }
    None => None
  }
}

///|
priv enum PklTestCatchFormKind {
  CatchForm
  CatchOrNullForm
}

///|
fn pkl_test_catch_form_kind(expr : Expr) -> PklTestCatchFormKind? {
  match expr {
    CallExpr(MemberAccess(Identifier("test"), "catch"), _)
    | CallExpr(MemberAccess(Identifier("module"), "catch"), _) =>
      Some(CatchForm)
    CallExpr(MemberAccess(Identifier("test"), "catchOrNull"), _)
    | CallExpr(MemberAccess(Identifier("module"), "catchOrNull"), _) =>
      Some(CatchOrNullForm)
    _ => None
  }
}

///|
/// PKL-148o: shared core for `catch` / `catchOrNull` — evaluates the
/// passed lambda body once, surfaces whether it threw (collected
/// diagnostic) or returned a value, and lets the wrappers branch on
/// the outcome. The probe runs `push_constrained_class_property_expr_diagnostics`
/// first because some constraint failures are emitted at the
/// expression-shape inspection phase rather than during evaluation.
priv enum PklTestCatchOutcome {
  ThrewOutcome(String)
  NoThrowOutcome
}

///|
fn eval_pkl_test_catch_outcome(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> PklTestCatchOutcome? {
  match pkl_test_catch_lambda_body(expr) {
    Some(body) => {
      let caught_diagnostics : Array[Diagnostic] = []
      push_constrained_class_property_expr_diagnostics(
        body, declarations, caught_diagnostics,
      )
      if caught_diagnostics.length() > 0 {
        return Some(ThrewOutcome(caught_diagnostics[0].message))
      }
      match
        eval_expr_with_bindings(
          body, bindings, env, class_env, cache, stack, declarations, caught_diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          match deferred_error_message(value) {
            Some(message) => Some(ThrewOutcome(message))
            None =>
              if caught_diagnostics.length() > 0 {
                Some(ThrewOutcome(caught_diagnostics[0].message))
              } else {
                Some(NoThrowOutcome)
              }
          }
        None =>
          if caught_diagnostics.length() > 0 {
            Some(ThrewOutcome(caught_diagnostics[0].message))
          } else {
            Some(ThrewOutcome("caught error"))
          }
      }
    }
    None => None
  }
}

///|
fn eval_pkl_test_catch_or_null_binding_value(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match
    eval_pkl_test_catch_outcome(
      expr, bindings, env, class_env, cache, stack, declarations, resolve_import,
    ) {
    Some(ThrewOutcome(message)) => Some(StringValue(message))
    Some(NoThrowOutcome) => Some(NullValue)
    None => None
  }
}

///|
fn module_class_properties_from_bindings(
  module_bindings : Array[Binding],
) -> Array[ClassProperty] {
  let properties : Array[ClassProperty] = []
  for binding in module_bindings {
    if !binding.exported || binding.name == "output" {
      continue
    }
    properties.push({
      name: binding.name,
      type_name: binding.type_name,
      value: if binding.abstract_slot {
        None
      } else {
        Some(binding.value)
      },
      annotations: binding.annotations,
    })
  }
  properties
}

///|
fn add_current_module_class_binding(
  class_env : Array[ClassBinding],
  module_bindings : Array[Binding],
) -> Unit {
  class_env.push({
    name: "module",
    parent_name: None,
    properties: module_class_properties_from_bindings(module_bindings),
    methods: [],
  })
}

///|
fn eval_program(
  program : Program,
  current_module_path : String?,
  current_module_source : String?,
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
  resolve_import_classes : (String) -> Array[ClassExport]?,
) -> Value? {
  let env : Array[ValueBinding] = []
  let class_env = collect_class_bindings(program.declarations)
  let type_aliases = eval_type_alias_bindings(program.declarations)
  let cache : Array[ValueBinding] = []
  let members : Array[ValueMember] = []
  let module_parent_members : Array[ValueMember] = []
  let bindings = all_eval_bindings(program)
  add_current_module_class_binding(class_env, program.bindings)
  eval_imports(
    program.imports,
    current_module_path,
    env,
    diagnostics,
    resolve_import,
  )
  add_imported_class_bindings(
    program.imports,
    class_env,
    resolve_import_classes,
  )
  // PKL-148bb: stash the module's import list as a hidden cache entry
  // so `reflect.Module(module).imports` can recover the (alias, URI)
  // pairs as a `Map`. The Identifier("module") handler picks this up
  // and surfaces it as a regular property on the module ObjectValue.
  if program.imports.length() > 0 {
    let entries : Array[ValueEntry] = []
    for decl in program.imports {
      entries.push({
        key: StringValue(decl.import_name),
        value: StringValue(decl.uri),
      })
    }
    cache.push({ name: "@__module_imports", value: MapValue(entries) })
  }
  match current_module_path {
    Some(path) =>
      cache.push({ name: "@__module_path", value: StringValue(path) })
    None => ()
  }
  match current_module_source {
    Some(source) =>
      cache.push({ name: "@__module_source", value: StringValue(source) })
    None => ()
  }
  // PKL-148bh: stash the declared module name (`module Foo` header)
  // so reflect mirrors can build the `<module>#<simple>` qualified
  // form Apple Pkl uses for Class.toString / TypeAlias.toString.
  // When no explicit header is present, leave the marker unset so
  // the bare simple-name is used.
  match program.module_name {
    Some(name) =>
      cache.push({ name: "@__module_name", value: StringValue(name) })
    None => ()
  }
  // PKL-140: `extends "parent.pkl"` exposes the parent module's class
  // declarations as bare-name lookups in the child (Apple Pkl treats
  // extends as inheritance, not a namespaced import). Pull the parent
  // ClassExports in directly so an inherited typed slot like
  // `pp1: Person1` can resolve `Person1` against the parent.
  //
  // PKL-148ac: also eagerly evaluate the parent module so `super.X` /
  // `super.X(...)` inside the child's own functions / hidden properties
  // can dispatch to the parent's binding / FunctionValue. The parent's
  // members are pushed as `super = ObjectValue(...)` into the cache so
  // every module-level FunctionValue created during this `eval_program`
  // captures `super` via `capture_value_bindings(env, cache)`. The
  // cache (not env) is the right home because class-default evaluation
  // (PKL-148aa) pushes its own class-level `super` later — and that
  // sits on top of the same cache, so a class body's `super.X` keeps
  // pointing at the parent class while a module-level body sees the
  // parent module. Pushing into env would force the module-level super
  // ahead of every class-default super, regressing PKL-148aa.
  match program.module_relation {
    Some(relation) =>
      match resolve_import_classes(relation.uri) {
        Some(exports) =>
          for class_export in exports {
            class_env.push({
              name: class_export.name,
              parent_name: class_export.parent_name,
              properties: class_export.properties,
              methods: class_export.methods,
            })
          }
        None => ()
      }
    None => ()
  }
  match program.module_relation {
    Some(relation) => {
      let parent_members = eval_module_relation(
        relation, diagnostics, resolve_import,
      )
      for parent_member in parent_members {
        module_parent_members.push(parent_member)
      }
      if parent_members.length() > 0 {
        cache.push({ name: "super", value: ObjectValue(parent_members) })
      }
    }
    None => ()
  }
  for binding in program.bindings {
    // Hidden top-level properties are not part of the rendered module
    // surface, but they are still reachable through `super.x` /
    // imported-module member access. Evaluate them against a local
    // diagnostics buffer: successful values are exported as hidden
    // members, while failing values stay lazy for same-module
    // `test.catch(() -> x)` and are represented as deferred errors for
    // cross-module access.
    if is_hidden_member_name(binding.name) {
      let hidden_diagnostics : Array[Diagnostic] = []
      let resolved_value = if binding.abstract_slot {
        synthesize_default_for_type(
          binding.type_name,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          hidden_diagnostics,
          resolve_import,
        )
      } else {
        match
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
              hidden_diagnostics,
              resolve_import,
            )
        }
      }
      match resolved_value {
        Some(raw_value) => {
          let coerced = coerce_value_to_annotated_type(
            raw_value,
            binding.type_name,
          )
          let value = apply_class_defaults_for_type(
            coerced,
            binding.type_name,
            bindings,
            env,
            class_env,
            cache,
            program.declarations,
            hidden_diagnostics,
            resolve_import,
          )
          if eval_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              type_aliases,
              hidden_diagnostics,
            ) &&
            eval_user_defined_constrained_type_annotation_value_is_valid(
              binding.type_name,
              value,
              program.declarations,
              hidden_diagnostics,
            ) &&
            eval_expr_class_property_constraints_are_valid(
              binding.value,
              value,
              program.declarations,
              hidden_diagnostics,
            ) &&
            eval_expr_alias_constraints_are_valid(
              binding.value,
              value,
              type_aliases,
              hidden_diagnostics,
            ) {
            members.push({
              name: binding.name,
              value,
              source: Some(binding.value),
              annotations: binding.annotations,
            })
          } else if hidden_diagnostics.length() > 0 {
            members.push({
              name: binding.name,
              value: deferred_error_value(hidden_diagnostics[0].message),
              source: Some(binding.value),
              annotations: binding.annotations,
            })
          }
        }
        None =>
          if hidden_diagnostics.length() > 0 {
            members.push({
              name: binding.name,
              value: deferred_error_value(hidden_diagnostics[0].message),
              source: Some(binding.value),
              annotations: binding.annotations,
            })
          }
      }
      continue
    }
    // PKL-140: abstract / external slot bindings (declared without a
    // `=` default) carry no value to render. Apple Pkl synthesises a
    // type-directed default for typed slots — a user class projects
    // to `new T {}` with class defaults applied, nullable types and
    // `Null` project to `null`, a string-literal type projects to the
    // literal itself, and structural collection types fall back to
    // their empty form. Slots that don't fit the synthesiser remain
    // skipped (the typechecker still recorded their type).
    if binding.abstract_slot {
      match
        synthesize_default_for_type(
          binding.type_name,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(value) =>
          members.push({
            name: binding.name,
            value,
            source: None,
            annotations: binding.annotations,
          })
        None => ()
      }
      continue
    }
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
        Some(raw_value) => {
          let coerced = coerce_value_to_annotated_type(
            raw_value,
            binding.type_name,
          )
          // PKL-148: when a typed binding is filled in with `new {}` (or
          // a sparse amend), expand the class-level defaults so the
          // declared properties materialise in the rendered output.
          // `apply_class_defaults_for_type` is a no-op when the value
          // already carries members, when no type is annotated, or when
          // the type name doesn't resolve to a user-defined class.
          let value = apply_class_defaults_for_type(
            coerced,
            binding.type_name,
            bindings,
            env,
            class_env,
            cache,
            program.declarations,
            diagnostics,
            resolve_import,
          )
          let no_deferred_error = match binding.type_name {
            Some(_) =>
              match first_deferred_error_message(value) {
                Some(message) => {
                  diagnostics.push(diag(message))
                  false
                }
                None => true
              }
            None => true
          }
          if no_deferred_error &&
            eval_constrained_type_annotation_value_is_valid(
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
            members.push({
              name: binding.name,
              value,
              source: Some(binding.value),
              annotations: binding.annotations,
            })
          }
        }
        None => ()
      }
    }
  }
  // PKL-118: surface module-level `function f(...) = ...` declarations
  // as hidden-prefixed exported members so a cross-module reference
  // (`import "x.pkl" as Base; out = Base.helper(5)`) can resolve them
  // through `lookup_member`. The hidden prefix keeps the function out
  // of the rendered output (`render_value` skips
  // `is_hidden_member_name(field.name)`); internal references inside
  // the declaring module continue to flow through the bare-named entry
  // in `bindings` produced by `all_eval_bindings`.
  for declaration in program.declarations {
    match declaration {
      FunctionDeclaration(function_decl) =>
        match function_decl.body {
          Some(body) => {
            let lambda_expr = LambdaExpr(
              function_decl.parameters,
              body,
              function_decl.return_type_name,
            )
            match
              eval_expr_with_bindings(
                lambda_expr,
                bindings,
                env,
                class_env,
                cache,
                [],
                program.declarations,
                diagnostics,
                resolve_import,
              ) {
              Some(value) =>
                members.push({
                  name: hidden_member_name(function_decl.name),
                  value,
                  source: None,
                  annotations: [],
                })
              None => ()
            }
          }
          None => ()
        }
      _ => ()
    }
  }
  match program.module_name {
    Some(name) =>
      members.push({
        name: hidden_member_name(module_metadata_name()),
        value: StringValue(name),
        source: None,
        annotations: [],
      })
    None => ()
  }
  match current_module_path {
    Some(path) =>
      members.push({
        name: hidden_member_name(module_metadata_path_name()),
        value: StringValue(path),
        source: None,
        annotations: [],
      })
    None => ()
  }
  match program.module_relation {
    Some(_) =>
      members.push({
        name: hidden_member_name(module_metadata_super_name()),
        value: ObjectValue(module_parent_members),
        source: None,
        annotations: [],
      })
    None => ()
  }
  members.push({
    name: hidden_member_name("__class"),
    value: StringValue("Module"),
    source: None,
    annotations: [],
  })
  members.push({
    name: hidden_member_name(reflect_module_metadata_name()),
    value: reflect_module_metadata_value(
      program, members, module_parent_members, bindings, env, class_env, cache, current_module_path,
      current_module_source, resolve_import,
    ),
    source: None,
    annotations: [],
  })
  let result = match program.body {
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
    None if program.module_relation is Some(_) =>
      Some(
        ObjectValue(
          merge_value_members(
            late_bind_module_parent_members(
              module_parent_members,
              bindings,
              env,
              class_env,
              cache,
              program.declarations,
              diagnostics,
              resolve_import,
            ),
            members,
          ),
        ),
      )
    None if members.length() > 0 => Some(ObjectValue(members))
    // PKL-140: declarations-only modules (stdlib `pkl:math`, `pkl:test`,
    // etc.) have no value bindings to render but still parse cleanly.
    // Apple Pkl treats these as empty modules; the loadable surface is
    // the class / typealias / function declarations alone. Returning
    // an empty ObjectValue keeps the eval pipeline happy.
    None => Some(ObjectValue([]))
  }
  // PKL-105: post-process the result by applying any path-keyed
  // `output.renderer.converters` lambdas. Each converter is a
  // `(value) -> newValue` callback the user attached to a dotted path
  // on the module's `output.value` (or directly on the module body).
  // Class-keyed converters (`["MyClass"] = ...`) are deferred until
  // ObjectValue carries its source class.
  match result {
    Some(value) => {
      let finalized_value = finalize_output_super_text(value)
      let converters = collect_path_converters(finalized_value)
      let class_converters = collect_class_converters(finalized_value)
      let property_transformers = collect_convert_property_transformers(
        finalized_value,
        bindings,
        env,
        class_env,
        cache,
        program.declarations,
        diagnostics,
        resolve_import,
      )
      let renderer_value = collect_output_renderer(finalized_value)
      let mut current = finalized_value
      if property_transformers.length() > 0 ||
        value_has_member_annotations(current) {
        current = apply_convert_property_transformers(
          current,
          renderer_value,
          property_transformers,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          diagnostics,
          resolve_import,
        )
      }
      if converters.length() > 0 {
        current = apply_path_converters(
          current,
          converters,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          diagnostics,
          resolve_import,
        )
      }
      // PKL-152: class-keyed converters (`[Dog]`, `[Any]`) walk the
      // whole rendered tree and rewrite any ObjectValue whose class tag
      // matches the converter's class reference. `Any` matches anything
      // that isn't a module mirror.
      if class_converters.length() > 0 {
        current = apply_class_converters(
          current,
          class_converters,
          bindings,
          env,
          class_env,
          cache,
          program.declarations,
          diagnostics,
          resolve_import,
        )
      }
      Some(current)
    }
    None => None
  }
}

///|
fn value_has_member_annotations(value : Value) -> Bool {
  match value {
    ObjectValue(members) => {
      for field in members {
        if field.annotations.length() > 0 ||
          value_has_member_annotations(field.value) {
          return true
        }
      }
      false
    }
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => {
      for element in elements {
        if value_has_member_annotations(element) {
          return true
        }
      }
      false
    }
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) => {
      for entry in entries {
        if value_has_member_annotations(entry.key) ||
          value_has_member_annotations(entry.value) {
          return true
        }
      }
      false
    }
    PairValue(first, second) =>
      value_has_member_annotations(first) ||
      value_has_member_annotations(second)
    _ => false
  }
}

///|
/// PKL-105: extract path-keyed converter callbacks from
/// `result.output.renderer.converters`. Returns an `(path, callback)`
/// list; class-keyed entries (those without a `.` and not starting
/// with `[` style) are recognised but skipped — the runtime doesn't
/// carry an object's source class yet.
fn collect_path_converters(value : Value) -> Array[(String, Value)] {
  let converters : Array[(String, Value)] = []
  match value {
    ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  match output_member.value {
                    ObjectValue(renderer_members) =>
                      append_path_converters_from_renderer_members(
                        converters, renderer_members,
                      )
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  converters
}

///|
fn append_path_converters_from_renderer_members(
  out : Array[(String, Value)],
  renderer_members : Array[ValueMember],
) -> Unit {
  for renderer_member in renderer_members {
    if renderer_member.name == "converters" {
      append_path_converters_from_value(out, renderer_member.value)
    }
  }
}

///|
fn append_path_converters_from_value(
  out : Array[(String, Value)],
  value : Value,
) -> Unit {
  match value {
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      for entry in entries {
        match entry.key {
          StringValue(path) => out.push((path, entry.value))
          _ => ()
        }
      }
    ObjectValue(members) =>
      for field in visible_members(members) {
        match converter_entry_from_subscript_member(field) {
          Some((StringValue(path), callback)) => out.push((path, callback))
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn collect_path_converters_from_renderer_members(
  renderer_members : Array[ValueMember],
) -> Array[(String, Value)] {
  let converters : Array[(String, Value)] = []
  append_path_converters_from_renderer_members(converters, renderer_members)
  converters
}

///|
fn apply_path_converters(
  value : Value,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let mut current = value
  for entry in converters {
    let (path, callback) = entry
    if !path_has_wildcard(path) {
      continue
    }
    current = rewrite_at_path(
      current, path, callback, bindings, env, class_env, cache, declarations, diagnostics,
      resolve_import,
    )
  }
  for entry in converters {
    let (path, callback) = entry
    if path_has_wildcard(path) {
      continue
    }
    current = rewrite_at_path(
      current, path, callback, bindings, env, class_env, cache, declarations, diagnostics,
      resolve_import,
    )
  }
  current
}

///|
/// PKL-152: extract class-keyed converters from
/// `result.output.renderer.converters`. Each entry's key is an
/// ObjectValue carrying the class mirror Apple Pkl materializes for
/// `Dog` / `Any` / etc. The returned list pairs the class's qualified
/// name (`"anyConverter#Dog"` / `"Any"`) with the callback.
fn collect_class_converters(value : Value) -> Array[(String, Value)] {
  let converters : Array[(String, Value)] = []
  match value {
    ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  match output_member.value {
                    ObjectValue(renderer_members) =>
                      append_class_converters_from_renderer_members(
                        converters, renderer_members,
                      )
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  converters
}

///|
fn append_class_converters_from_renderer_members(
  out : Array[(String, Value)],
  renderer_members : Array[ValueMember],
) -> Unit {
  for renderer_member in renderer_members {
    if renderer_member.name == "converters" {
      append_class_converters_from_value(out, renderer_member.value)
    }
  }
}

///|
fn append_class_converters_from_value(
  out : Array[(String, Value)],
  value : Value,
) -> Unit {
  match value {
    MappingValue(entries)
    | DefaultedMappingValue(_, entries, _)
    | MapValue(entries) =>
      for entry in entries {
        match class_name_from_mirror_value(entry.key) {
          Some(name) => out.push((name, entry.value))
          None => ()
        }
      }
    ObjectValue(members) =>
      for field in visible_members(members) {
        match converter_entry_from_subscript_member(field) {
          Some((key, callback)) =>
            match class_name_from_mirror_value(key) {
              Some(name) => out.push((name, callback))
              None => ()
            }
          None => ()
        }
      }
    _ => ()
  }
}

///|
fn converter_entry_from_subscript_member(
  field : ValueMember,
) -> (Value, Value)? {
  if !field.name.has_prefix("@subscript$") {
    return None
  }
  match field.value {
    ObjectValue(pair_members) =>
      match
        (
          lookup_member(pair_members, "@key"),
          lookup_member(pair_members, "@value"),
        ) {
        (Some(key), Some(value)) => Some((key, value))
        _ => None
      }
    _ => None
  }
}

///|
fn collect_class_converters_from_renderer_members(
  renderer_members : Array[ValueMember],
) -> Array[(String, Value)] {
  let converters : Array[(String, Value)] = []
  append_class_converters_from_renderer_members(converters, renderer_members)
  converters
}

///|
priv struct ConvertPropertyTransformer {
  class_name : String
  value : Value
}

///|
fn collect_output_renderer(value : Value) -> Value? {
  match value {
    ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  return Some(output_member.value)
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  None
}

///|
fn collect_convert_property_transformers(
  value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[ConvertPropertyTransformer] {
  let transformers : Array[ConvertPropertyTransformer] = []
  match value {
    ObjectValue(members) =>
      for entry in members {
        if entry.name == "output" {
          match entry.value {
            ObjectValue(output_members) =>
              for output_member in output_members {
                if output_member.name == "renderer" {
                  match output_member.value {
                    ObjectValue(renderer_members) =>
                      for renderer_member in renderer_members {
                        if renderer_member.name == "convertPropertyTransformers" {
                          match renderer_member.value {
                            MappingValue(entries) =>
                              for entry in entries {
                                match class_name_from_mirror_value(entry.key) {
                                  Some(class_name) =>
                                    transformers.push({
                                      class_name,
                                      value: instantiate_convert_property_value(
                                        class_name,
                                        entry.value,
                                        bindings,
                                        env,
                                        class_env,
                                        cache,
                                        declarations,
                                        diagnostics,
                                        resolve_import,
                                      ),
                                    })
                                  None => ()
                                }
                              }
                            _ => ()
                          }
                        }
                      }
                    _ => ()
                  }
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  transformers
}

///|
fn class_name_from_mirror_value(value : Value) -> String? {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, "name") {
        Some(StringValue(name)) => Some(class_binding_name_from_mirror(name))
        _ =>
          match lookup_member(members, "reflectee") {
            Some(StringValue(name)) =>
              Some(class_binding_name_from_mirror(name))
            _ => None
          }
      }
    _ => None
  }
}

///|
fn class_binding_name_from_mirror(name : String) -> String {
  let hash = name.find("#")
  match hash {
    Some(idx) =>
      String::unsafe_substring(name, start=idx + 1, end=name.length())
    None => name
  }
}

///|
fn instantiate_convert_property_value(
  class_name : String,
  mixin_value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match mixin_value {
    ObjectValue(members) => {
      let defaults = eval_class_default_members(
        class_name,
        bindings,
        env,
        class_env,
        cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      )
      ObjectValue(
        tag_object_with_class(
          merge_value_members(defaults, members),
          class_name,
        ),
      )
    }
    _ => mixin_value
  }
}

///|
fn apply_convert_property_transformers(
  value : Value,
  renderer_value : Value?,
  transformers : Array[ConvertPropertyTransformer],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  transform_convert_property_value(
    value,
    renderer_value_or_default(renderer_value),
    transformers,
    bindings,
    env,
    class_env,
    cache,
    declarations,
    diagnostics,
    resolve_import,
  )
}

///|
fn renderer_value_or_default(renderer_value : Value?) -> Value {
  match renderer_value {
    Some(value) => value
    None => ObjectValue(tag_object_with_class([], "PcfRenderer"))
  }
}

///|
fn transform_convert_property_value(
  value : Value,
  renderer_value : Value,
  transformers : Array[ConvertPropertyTransformer],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        let child = transform_convert_property_value(
          field.value,
          renderer_value,
          transformers,
          bindings,
          env,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        )
        next.push(
          apply_convert_property_annotations_to_member(
            field, child, renderer_value, transformers, bindings, env, class_env,
            cache, declarations, diagnostics, resolve_import,
          ),
        )
      }
      match find_object_class_tag(members) {
        Some(class_name) =>
          if find_object_class_tag(next) is None {
            ObjectValue(tag_object_with_class(next, class_name))
          } else {
            ObjectValue(next)
          }
        None => ObjectValue(next)
      }
    }
    ListingValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          transform_convert_property_value(
            element, renderer_value, transformers, bindings, env, class_env, cache,
            declarations, diagnostics, resolve_import,
          ),
        )
      }
      ListingValue(next)
    }
    DefaultedListingValue(raw, elements, default_value) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          transform_convert_property_value(
            element, renderer_value, transformers, bindings, env, class_env, cache,
            declarations, diagnostics, resolve_import,
          ),
        )
      }
      DefaultedListingValue(raw, next, default_value)
    }
    ListValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          transform_convert_property_value(
            element, renderer_value, transformers, bindings, env, class_env, cache,
            declarations, diagnostics, resolve_import,
          ),
        )
      }
      ListValue(next)
    }
    SetValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          transform_convert_property_value(
            element, renderer_value, transformers, bindings, env, class_env, cache,
            declarations, diagnostics, resolve_import,
          ),
        )
      }
      SetValue(next)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: transform_convert_property_value(
            entry.value,
            renderer_value,
            transformers,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MapValue(next)
    }
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: transform_convert_property_value(
            entry.value,
            renderer_value,
            transformers,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: transform_convert_property_value(
            entry.value,
            renderer_value,
            transformers,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    PairValue(first, second) =>
      PairValue(
        transform_convert_property_value(
          first, renderer_value, transformers, bindings, env, class_env, cache, declarations,
          diagnostics, resolve_import,
        ),
        transform_convert_property_value(
          second, renderer_value, transformers, bindings, env, class_env, cache,
          declarations, diagnostics, resolve_import,
        ),
      )
    _ => value
  }
}

///|
fn apply_convert_property_annotations_to_member(
  field : ValueMember,
  value : Value,
  renderer_value : Value,
  transformers : Array[ConvertPropertyTransformer],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> ValueMember {
  let mut name = field.name
  let mut current = tag_xml_constructor_value_from_source(field.source, value)
  for annotation in field.annotations {
    match
      apply_single_convert_property_annotation(
        annotation, name, current, renderer_value, transformers, bindings, env, class_env,
        cache, declarations, diagnostics, resolve_import,
      ) {
      Some((next_name, next_value)) => {
        name = next_name
        current = next_value
      }
      None => ()
    }
  }
  { name, value: current, source: field.source, annotations: [] }
}

///|
fn tag_xml_constructor_value_from_source(
  source : Expr?,
  value : Value,
) -> Value {
  let class_name = match source {
    Some(expr) => xml_constructor_class_name_from_expr(expr)
    None => None
  }
  match (class_name, value) {
    (Some(name), ObjectValue(members)) =>
      if find_object_class_tag(members) is Some(_) {
        value
      } else {
        ObjectValue(tag_object_with_class(members, name))
      }
    _ => value
  }
}

///|
fn xml_constructor_class_name_from_expr(expr : Expr) -> String? {
  let ctor = match expr {
    CallExpr(MemberAccess(Identifier(_), name), _) => xml_constructor_name(name)
    CallExpr(Identifier(name), _) => xml_constructor_name(name)
    AmendExpr(base, _) => return xml_constructor_class_name_from_expr(base)
    _ => None
  }
  match ctor {
    Some("Element") => Some("xml.Element")
    Some("Inline") => Some("xml.Inline")
    Some("CData") => Some("xml.CData")
    Some("Comment") => Some("xml.Comment")
    _ => None
  }
}

///|
fn apply_single_convert_property_annotation(
  annotation : Annotation,
  property_name : String,
  property_value : Value,
  renderer_value : Value,
  transformers : Array[ConvertPropertyTransformer],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> (String, Value)? {
  if annotation.class_name == "Property" ||
    annotation.class_name.has_suffix(".Property") {
    match protobuf_annotation_string_field(annotation.body_text, "name") {
      Some(next_name) => return Some((next_name, property_value))
      None => ()
    }
  }
  let class_name = class_binding_name_from_mirror(annotation.class_name)
  let matching_transformer = pick_convert_property_transformer(
    class_name, transformers, class_env,
  )
  let annotation_value = match
    eval_annotation_instance(
      annotation, bindings, env, class_env, cache, declarations, diagnostics, resolve_import,
    ) {
    Some(value) => value
    None => return None
  }
  let transformer_value = match matching_transformer {
    Some(transformer) =>
      merge_convert_property_values(annotation_value, transformer)
    None => annotation_value
  }
  let render_fn = match transformer_value {
    ObjectValue(members) => lookup_member(members, "render")
    _ => None
  }
  match render_fn {
    Some(fn_value) =>
      match
        apply_convert_property_render_function(
          fn_value,
          PairValue(StringValue(property_name), property_value),
          renderer_value,
          transformer_value,
          bindings,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(PairValue(StringValue(next_name), next_value)) =>
          Some((next_name, next_value))
        _ => None
      }
    None => None
  }
}

///|
fn merge_convert_property_values(base : Value, mixin_value : Value) -> Value {
  match (base, mixin_value) {
    (ObjectValue(base_members), ObjectValue(mixin_members)) =>
      ObjectValue(merge_value_members(base_members, mixin_members))
    _ => mixin_value
  }
}

///|
fn eval_annotation_instance(
  annotation : Annotation,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let source = match annotation.body_kind {
    BraceBody =>
      "__annotation = new " +
      annotation.class_name +
      " {" +
      annotation.body_text +
      "}"
    NoBody => "__annotation = new " + annotation.class_name + " {}"
    ParenBody => return None
  }
  let parsed = parse_source(source)
  for binding in parsed.program.bindings {
    if binding.name == "__annotation" {
      return eval_expr_with_bindings(
        binding.value,
        bindings,
        env,
        class_env,
        cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      )
    }
  }
  None
}

///|
fn pick_convert_property_transformer(
  class_name : String,
  transformers : Array[ConvertPropertyTransformer],
  class_env : Array[ClassBinding],
) -> Value? {
  let chain = class_chain_for_tag(class_name, class_env)
  for ancestor in chain {
    for transformer in transformers {
      if name_matches_class_tag(transformer.class_name, ancestor) {
        return Some(transformer.value)
      }
    }
  }
  None
}

///|
fn apply_convert_property_render_function(
  fn_value : Value,
  property : Value,
  renderer_value : Value,
  outer_value : Value,
  bindings : Array[Binding],
  class_env : Array[ClassBinding],
  caller_cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match fn_value {
    FunctionValue(parameters, body, _return_type_name, captured_env, _) => {
      if parameters.length() != 2 {
        diagnostics.push(diag("ConvertProperty.render expects 2 arguments"))
        return None
      }
      let call_cache = copy_value_bindings(captured_env)
      push_object_members_as_bindings(call_cache, outer_value)
      call_cache.push({ name: "outer", value: outer_value })
      push_module_metadata_from_cache(call_cache, caller_cache)
      call_cache.push({ name: parameters[0].name, value: property })
      call_cache.push({ name: parameters[1].name, value: renderer_value })
      eval_expr_with_bindings(
        body,
        bindings,
        [],
        class_env,
        call_cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      )
    }
    _ => None
  }
}

///|
fn push_object_members_as_bindings(
  bindings : Array[ValueBinding],
  value : Value,
) -> Unit {
  match value {
    ObjectValue(members) =>
      for value_member in members {
        if is_invisible_member_name(value_member.name) {
          continue
        }
        bindings.push({ name: value_member.name, value: value_member.value })
      }
    _ => ()
  }
}

///|
/// PKL-152: walk the rendered tree and rewrite any ObjectValue whose
/// class matches a converter key. `Any` matches every ObjectValue
/// (except the module mirror itself); explicit class entries match
/// only when the class tag agrees verbatim. Lookup falls through to
/// the next match so a more specific class wins over `Any`.
fn apply_class_converters(
  value : Value,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  // Skip the top-level module value; converters apply to children only
  // (so `[Any]` doesn't recursively swallow the output module itself).
  match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        if field.name == "output" {
          next.push(
            walk_output_member_class_converters(
              field, converters, bindings, env, class_env, cache, declarations, diagnostics,
              resolve_import,
            ),
          )
        } else {
          next.push({
            name: field.name,
            value: walk_class_converter(
              field.value,
              converters,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: field.source,
            annotations: field.annotations,
          })
        }
      }
      ObjectValue(next)
    }
    _ => value
  }
}

///|
fn apply_value_renderer_converters(
  value : Value,
  renderer_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let path_converters = collect_path_converters_from_renderer_members(
    renderer_members,
  )
  let class_converters = collect_class_converters_from_renderer_members(
    renderer_members,
  )
  let mut current = value
  if path_converters.length() > 0 {
    current = apply_path_converters(
      current, path_converters, bindings, env, class_env, cache, declarations, diagnostics,
      resolve_import,
    )
  }
  if class_converters.length() > 0 {
    current = walk_class_converter(
      current, class_converters, bindings, env, class_env, cache, declarations, diagnostics,
      resolve_import,
    )
  }
  current
}

///|
fn apply_parser_converters(
  value : Value,
  parser_members : Array[ValueMember],
  convert_keys : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let path_converters = collect_path_converters_from_renderer_members(
    parser_members,
  )
  let class_converters = collect_class_converters_from_renderer_members(
    parser_members,
  )
  let mut current = value
  if path_converters.length() > 0 {
    current = apply_parser_path_converters(
      current, path_converters, convert_keys, bindings, env, class_env, cache, declarations,
      diagnostics, resolve_import,
    )
  }
  if class_converters.length() > 0 {
    current = walk_parser_class_converter(
      current, class_converters, convert_keys, bindings, env, class_env, cache, declarations,
      diagnostics, resolve_import,
    )
  }
  current
}

///|
fn apply_parser_path_converters(
  value : Value,
  converters : Array[(String, Value)],
  propagate_aliases : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let mut current = value
  for entry in converters {
    let (path, callback) = entry
    let before = current
    let converted = if path.has_prefix("^") {
      rewrite_at_path(
        current, path, callback, bindings, env, class_env, cache, declarations, diagnostics,
        resolve_import,
      )
    } else {
      rewrite_at_path_anywhere(
        current, path, callback, bindings, env, class_env, cache, declarations, diagnostics,
        resolve_import,
      )
    }
    current = if propagate_aliases {
      propagate_parser_alias_rewrites(before, converted)
    } else {
      converted
    }
  }
  current
}

///|
fn propagate_parser_alias_rewrites(before : Value, after : Value) -> Value {
  match (before, after) {
    (ObjectValue(before_members), ObjectValue(after_members)) =>
      if before_members.length() == after_members.length() {
        let replacements : Array[(Int64, Value)] = []
        for i = 0; i < before_members.length(); i = i + 1 {
          if before_members[i].value != after_members[i].value {
            match parser_alias_id(before_members[i].value) {
              Some(id) => replacements.push((id, after_members[i].value))
              None => ()
            }
          }
        }
        let next : Array[ValueMember] = []
        for i = 0; i < after_members.length(); i = i + 1 {
          let value = if before_members[i].value == after_members[i].value {
            match
              parser_alias_replacement_for(
                before_members[i].value,
                replacements,
              ) {
              Some(replacement) => replacement
              None => after_members[i].value
            }
          } else {
            propagate_parser_alias_rewrites(
              before_members[i].value,
              after_members[i].value,
            )
          }
          next.push({
            name: after_members[i].name,
            value,
            source: after_members[i].source,
            annotations: after_members[i].annotations,
          })
        }
        ObjectValue(next)
      } else {
        after
      }
    (ListingValue(before_values), ListingValue(after_values)) =>
      if before_values.length() == after_values.length() {
        ListingValue(
          propagate_parser_alias_rewrites_in_values(before_values, after_values),
        )
      } else {
        after
      }
    (ListValue(before_values), ListValue(after_values)) =>
      if before_values.length() == after_values.length() {
        ListValue(
          propagate_parser_alias_rewrites_in_values(before_values, after_values),
        )
      } else {
        after
      }
    (SetValue(before_values), SetValue(after_values)) =>
      if before_values.length() == after_values.length() {
        SetValue(
          propagate_parser_alias_rewrites_in_values(before_values, after_values),
        )
      } else {
        after
      }
    (
      DefaultedListingValue(raw, before_values, default_value),
      DefaultedListingValue(_, after_values, _),
    ) =>
      if before_values.length() == after_values.length() {
        DefaultedListingValue(
          raw,
          propagate_parser_alias_rewrites_in_values(before_values, after_values),
          default_value,
        )
      } else {
        after
      }
    _ => after
  }
}

///|
fn propagate_parser_alias_rewrites_in_values(
  before_values : Array[Value],
  after_values : Array[Value],
) -> Array[Value] {
  let replacements : Array[(Int64, Value)] = []
  for i = 0; i < before_values.length(); i = i + 1 {
    if before_values[i] != after_values[i] {
      match parser_alias_id(before_values[i]) {
        Some(id) => replacements.push((id, after_values[i]))
        None => ()
      }
    }
  }
  let next : Array[Value] = []
  for i = 0; i < after_values.length(); i = i + 1 {
    if before_values[i] == after_values[i] {
      match parser_alias_replacement_for(before_values[i], replacements) {
        Some(replacement) => next.push(replacement)
        None => next.push(after_values[i])
      }
    } else {
      next.push(
        propagate_parser_alias_rewrites(before_values[i], after_values[i]),
      )
    }
  }
  next
}

///|
fn parser_alias_replacement_for(
  value : Value,
  replacements : Array[(Int64, Value)],
) -> Value? {
  match parser_alias_id(value) {
    Some(id) =>
      for entry in replacements {
        if id == entry.0 {
          return Some(entry.1)
        }
      }
    None => ()
  }
  None
}

///|
fn parser_alias_id(value : Value) -> Int64? {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, "__yamlAnchorId") {
        Some(IntValue(id)) => Some(id)
        _ => None
      }
    _ => None
  }
}

///|
fn rewrite_at_path_anywhere(
  value : Value,
  path : String,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let segments = split_path(path)
  if segments.length() == 0 {
    return value
  }
  rewrite_walk_anywhere(
    value, segments, callback, bindings, env, class_env, cache, declarations, diagnostics,
    resolve_import,
  )
}

///|
fn rewrite_walk_anywhere(
  value : Value,
  segments : Array[String],
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let current = rewrite_walk(
    value, segments, 0, callback, bindings, env, class_env, cache, declarations,
    diagnostics, resolve_import,
  )
  rewrite_walk_anywhere_children(
    current, segments, callback, bindings, env, class_env, cache, declarations, diagnostics,
    resolve_import,
  )
}

///|
fn rewrite_walk_anywhere_children(
  value : Value,
  segments : Array[String],
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        if is_invisible_member_name(field.name) {
          next.push(field)
        } else {
          next.push({
            name: field.name,
            value: rewrite_walk_anywhere(
              field.value,
              segments,
              callback,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: field.source,
            annotations: field.annotations,
          })
        }
      }
      ObjectValue(next)
    }
    ListingValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk_anywhere(
            element, segments, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListingValue(next)
    }
    DefaultedListingValue(raw, elements, default_value) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk_anywhere(
            element, segments, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      DefaultedListingValue(raw, next, default_value)
    }
    ListValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk_anywhere(
            element, segments, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListValue(next)
    }
    SetValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk_anywhere(
            element, segments, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      SetValue(next)
    }
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk_anywhere(
            entry.value,
            segments,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk_anywhere(
            entry.value,
            segments,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk_anywhere(
            entry.value,
            segments,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MapValue(next)
    }
    PairValue(first, second) =>
      PairValue(
        rewrite_walk_anywhere(
          first, segments, callback, bindings, env, class_env, cache, declarations,
          diagnostics, resolve_import,
        ),
        rewrite_walk_anywhere(
          second, segments, callback, bindings, env, class_env, cache, declarations,
          diagnostics, resolve_import,
        ),
      )
    _ => value
  }
}

///|
fn walk_parser_class_converter(
  value : Value,
  converters : Array[(String, Value)],
  convert_keys : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let children_converted = walk_parser_class_converter_children(
    value, converters, convert_keys, bindings, env, class_env, cache, declarations,
    diagnostics, resolve_import,
  )
  match pick_class_converter(children_converted, converters, class_env) {
    Some(callback) =>
      match
        apply_function_value(
          "parser converter",
          callback,
          [children_converted],
          bindings,
          env,
          class_env,
          cache,
          [],
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(converted) => converted
        None => children_converted
      }
    None => children_converted
  }
}

///|
fn walk_parser_member_name_converter(
  name : String,
  converters : Array[(String, Value)],
  convert_keys : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> String {
  match
    walk_parser_class_converter(
      StringValue(name),
      converters,
      convert_keys,
      bindings,
      env,
      class_env,
      cache,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    StringValue(converted) => converted
    _ => name
  }
}

///|
fn walk_parser_class_converter_children(
  value : Value,
  converters : Array[(String, Value)],
  convert_keys : Bool,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        if is_invisible_member_name(field.name) {
          next.push(field)
        } else {
          let name = if convert_keys {
            walk_parser_member_name_converter(
              field.name,
              converters,
              convert_keys,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            )
          } else {
            field.name
          }
          next.push({
            name,
            value: walk_parser_class_converter(
              field.value,
              converters,
              convert_keys,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: field.source,
            annotations: field.annotations,
          })
        }
      }
      ObjectValue(next)
    }
    ListingValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_parser_class_converter(
            x, converters, convert_keys, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListingValue(next)
    }
    DefaultedListingValue(raw, xs, default_value) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_parser_class_converter(
            x, converters, convert_keys, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      DefaultedListingValue(raw, next, default_value)
    }
    ListValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_parser_class_converter(
            x, converters, convert_keys, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListValue(next)
    }
    SetValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_parser_class_converter(
            x, converters, convert_keys, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      SetValue(next)
    }
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: if convert_keys {
            walk_parser_class_converter(
              e.key,
              converters,
              convert_keys,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            )
          } else {
            e.key
          },
          value: walk_parser_class_converter(
            e.value,
            converters,
            convert_keys,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: if convert_keys {
            walk_parser_class_converter(
              e.key,
              converters,
              convert_keys,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            )
          } else {
            e.key
          },
          value: walk_parser_class_converter(
            e.value,
            converters,
            convert_keys,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: if convert_keys {
            walk_parser_class_converter(
              e.key,
              converters,
              convert_keys,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            )
          } else {
            e.key
          },
          value: walk_parser_class_converter(
            e.value,
            converters,
            convert_keys,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MapValue(next)
    }
    PairValue(first, second) =>
      PairValue(
        walk_parser_class_converter(
          first, converters, convert_keys, bindings, env, class_env, cache, declarations,
          diagnostics, resolve_import,
        ),
        walk_parser_class_converter(
          second, converters, convert_keys, bindings, env, class_env, cache, declarations,
          diagnostics, resolve_import,
        ),
      )
    _ => value
  }
}

///|
fn walk_output_member_class_converters(
  field : ValueMember,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> ValueMember {
  match field.value {
    ObjectValue(output_members) => {
      let next : Array[ValueMember] = []
      for output_member in output_members {
        if output_member.name == "value" {
          next.push({
            name: output_member.name,
            value: walk_class_converter(
              output_member.value,
              converters,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: output_member.source,
            annotations: output_member.annotations,
          })
        } else {
          next.push(output_member)
        }
      }
      {
        name: field.name,
        value: ObjectValue(next),
        source: field.source,
        annotations: field.annotations,
      }
    }
    _ => field
  }
}

///|
fn walk_class_converter(
  value : Value,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let converted = match pick_class_converter(value, converters, class_env) {
    Some(callback) =>
      match
        apply_function_value(
          "renderer converter",
          callback,
          [value],
          bindings,
          env,
          class_env,
          cache,
          [],
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(next) => next
        None => value
      }
    None => value
  }
  walk_class_converter_children(
    converted, converters, bindings, env, class_env, cache, declarations, diagnostics,
    resolve_import,
  )
}

///|
fn walk_class_converter_children(
  value : Value,
  converters : Array[(String, Value)],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) if object_class_tag_matches(members, "RenderDirective") =>
      value
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        if is_invisible_member_name(field.name) {
          next.push(field)
        } else {
          next.push({
            name: field.name,
            value: walk_class_converter(
              field.value,
              converters,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: field.source,
            annotations: field.annotations,
          })
        }
      }
      ObjectValue(next)
    }
    ListingValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_class_converter(
            x, converters, bindings, env, class_env, cache, declarations, diagnostics,
            resolve_import,
          ),
        )
      }
      ListingValue(next)
    }
    DefaultedListingValue(raw, xs, default_value) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_class_converter(
            x, converters, bindings, env, class_env, cache, declarations, diagnostics,
            resolve_import,
          ),
        )
      }
      DefaultedListingValue(raw, next, default_value)
    }
    ListValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_class_converter(
            x, converters, bindings, env, class_env, cache, declarations, diagnostics,
            resolve_import,
          ),
        )
      }
      ListValue(next)
    }
    SetValue(xs) => {
      let next : Array[Value] = []
      for x in xs {
        next.push(
          walk_class_converter(
            x, converters, bindings, env, class_env, cache, declarations, diagnostics,
            resolve_import,
          ),
        )
      }
      SetValue(next)
    }
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: walk_class_converter(
            e.key,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
          value: walk_class_converter(
            e.value,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: walk_class_converter(
            e.key,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
          value: walk_class_converter(
            e.value,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for e in entries {
        next.push({
          key: walk_class_converter(
            e.key,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
          value: walk_class_converter(
            e.value,
            converters,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MapValue(next)
    }
    // Pair renders as a scalar constructor in Apple Pkl's value renderers.
    // A `[Pair]` converter result is terminal for child class converters.
    PairValue(_, _) => value
    _ => value
  }
}

///|
fn pick_class_converter(
  value : Value,
  converters : Array[(String, Value)],
  class_env : Array[ClassBinding],
) -> Value? {
  // `[Any]` matches user class instances, not scalar / collection
  // wrappers. Specific converter keys such as `[String]`, `[List]`,
  // and `[Null]` still apply to their corresponding runtime values.
  let allow_any = value is ObjectValue(_)
  let tag = match value {
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(s) => s
        None => "Dynamic"
      }
    _ => eval_value_type_name(value)
  }
  // PKL-152: walk the receiver's superclass chain via `class_env`,
  // most-specific first, so a `[Cat]` converter wins over `[Animal]`
  // when both apply. Falls back to `[Any]` once the chain is
  // exhausted.
  let chain = class_chain_for_tag(tag, class_env)
  for ancestor in chain {
    for entry in converters {
      let (name, cb) = entry
      if name == "Any" {
        continue
      }
      if name == ancestor || name_matches_class_tag(name, ancestor) {
        return Some(cb)
      }
    }
  }
  if allow_any {
    for entry in converters {
      if entry.0 == "Any" {
        return Some(entry.1)
      }
    }
  }
  None
}

///|
/// PKL-152: walk the class hierarchy starting from `tag`. Strips the
/// `<module>#` prefix to look up bindings (which are stored under the
/// simple name). Walks via `parent_name`; stops when the parent is
/// missing or already seen (guards against cycles even though the
/// language disallows them).
fn class_chain_for_tag(
  tag : String,
  class_env : Array[ClassBinding],
) -> Array[String] {
  let chain : Array[String] = [tag]
  let mut current_simple = simple_class_name(tag)
  let seen : Array[String] = [current_simple]
  let mut limit = 32
  while limit > 0 {
    let parent = match lookup_class_binding_by_name(class_env, current_simple) {
      Some(binding) => binding.parent_name
      None => None
    }
    match parent {
      Some(p) => {
        if contains_string(seen, p) {
          break
        }
        seen.push(p)
        chain.push(p)
        current_simple = simple_class_name(p)
      }
      None => break
    }
    limit = limit - 1
  }
  chain
}

///|
fn simple_class_name(name : String) -> String {
  let hash = name.find("#")
  match hash {
    Some(idx) =>
      String::unsafe_substring(name, start=idx + 1, end=name.length())
    None => name
  }
}

///|
fn lookup_class_binding_by_name(
  class_env : Array[ClassBinding],
  name : String,
) -> ClassBinding? {
  for binding in class_env {
    if binding.name == name {
      return Some(binding)
    }
  }
  None
}

///|
fn contains_string(xs : Array[String], target : String) -> Bool {
  for s in xs {
    if s == target {
      return true
    }
  }
  false
}

///|
/// PKL-152: a converter key like `anyConverter#User` should match a
/// value tagged `"User"` (or vice versa). Stdlib-typed values carry the
/// bare class name; user classes carry the module-qualified form. We
/// accept the suffix-match either direction so the lookup is robust to
/// both projections.
fn name_matches_class_tag(name : String, tag : String) -> Bool {
  if name == tag {
    return true
  }
  // strip "<module>#" prefix
  let hash = name.find("#")
  let name_simple = match hash {
    Some(idx) =>
      String::unsafe_substring(name, start=idx + 1, end=name.length())
    None => name
  }
  let hash2 = tag.find("#")
  let tag_simple = match hash2 {
    Some(idx) => String::unsafe_substring(tag, start=idx + 1, end=tag.length())
    None => tag
  }
  name_simple == tag_simple
}

///|
/// Walk `value`, find the node at the dotted path, and replace it
/// with `callback(node)`. Paths that don't exist are silently
/// skipped — Apple Pkl matches this lenient behaviour.
fn rewrite_at_path(
  value : Value,
  path : String,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let segments = split_path(path)
  if segments.length() == 0 {
    return value
  }
  rewrite_walk(
    value, segments, 0, callback, bindings, env, class_env, cache, declarations,
    diagnostics, resolve_import,
  )
}

///|
fn rewrite_walk(
  value : Value,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  if idx >= segments.length() {
    match
      apply_function_value(
        "renderer converter",
        callback,
        [value],
        bindings,
        env,
        class_env,
        cache,
        [],
        declarations,
        diagnostics,
        resolve_import,
      ) {
      Some(converted) => converted
      None => value
    }
  } else {
    let segment = segments[idx]
    match value {
      ObjectValue(members) => {
        let next : Array[ValueMember] = []
        for field in members {
          if segment == "[*]" && field.name.has_prefix("@element$") {
            next.push({
              name: field.name,
              value: rewrite_walk(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if segment == "[*]" && field.name.has_prefix("@subscript$") {
            next.push({
              name: field.name,
              value: rewrite_dynamic_subscript_any_value(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if path_segment_subscript_key(segment) is Some(key) &&
            field.name.has_prefix("@subscript$") {
            next.push({
              name: field.name,
              value: rewrite_dynamic_subscript_value(
                field.value,
                key,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if segment == "*" {
            next.push({
              name: field.name,
              value: rewrite_walk(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if path_segment_subscript_base_key(segment)
            is Some((base, key)) &&
            field.name == base {
            next.push({
              name: field.name,
              value: rewrite_collection_key(
                field.value,
                key,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if path_segment_wildcard_base(segment) is Some(base) &&
            field.name == base {
            next.push({
              name: field.name,
              value: rewrite_collection_items(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else if field.name == path_segment_exact_name(segment) {
            next.push({
              name: field.name,
              value: rewrite_walk(
                field.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
              source: None,
              annotations: field.annotations,
            })
          } else {
            next.push(field)
          }
        }
        ObjectValue(next)
      }
      MappingValue(entries) => {
        let next : Array[ValueEntry] = []
        for entry in entries {
          let exact_segment = path_segment_exact_name(segment)
          let wildcard_base = path_segment_wildcard_base(segment)
          let key_matches = match entry.key {
            StringValue(k) => segment == "*" || k == exact_segment
            _ => false
          }
          let key_matches_wildcard_base = match (entry.key, wildcard_base) {
            (StringValue(k), Some(base)) => k == base
            _ => false
          }
          if key_matches_wildcard_base {
            next.push({
              key: entry.key,
              value: rewrite_collection_items(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else if key_matches {
            next.push({
              key: entry.key,
              value: rewrite_walk(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else {
            next.push(entry)
          }
        }
        MappingValue(next)
      }
      DefaultedMappingValue(raw, entries, default_value) => {
        let next : Array[ValueEntry] = []
        for entry in entries {
          let exact_segment = path_segment_exact_name(segment)
          let wildcard_base = path_segment_wildcard_base(segment)
          let key_matches = match entry.key {
            StringValue(k) => segment == "*" || k == exact_segment
            _ => false
          }
          let key_matches_wildcard_base = match (entry.key, wildcard_base) {
            (StringValue(k), Some(base)) => k == base
            _ => false
          }
          if key_matches_wildcard_base {
            next.push({
              key: entry.key,
              value: rewrite_collection_items(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else if key_matches {
            next.push({
              key: entry.key,
              value: rewrite_walk(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else {
            next.push(entry)
          }
        }
        DefaultedMappingValue(raw, next, default_value)
      }
      MapValue(entries) => {
        let next : Array[ValueEntry] = []
        for entry in entries {
          let exact_segment = path_segment_exact_name(segment)
          let wildcard_base = path_segment_wildcard_base(segment)
          let key_matches = match entry.key {
            StringValue(k) => segment == "*" || k == exact_segment
            _ => false
          }
          let key_matches_wildcard_base = match (entry.key, wildcard_base) {
            (StringValue(k), Some(base)) => k == base
            _ => false
          }
          if key_matches_wildcard_base {
            next.push({
              key: entry.key,
              value: rewrite_collection_items(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else if key_matches {
            next.push({
              key: entry.key,
              value: rewrite_walk(
                entry.value,
                segments,
                idx + 1,
                callback,
                bindings,
                env,
                class_env,
                cache,
                declarations,
                diagnostics,
                resolve_import,
              ),
            })
          } else {
            next.push(entry)
          }
        }
        MapValue(next)
      }
      ListingValue(_)
      | DefaultedListingValue(_, _, _)
      | ListValue(_)
      | SetValue(_) if path_segment_is_collection_wildcard(segment) =>
        rewrite_collection_items(
          value,
          segments,
          idx + 1,
          callback,
          bindings,
          env,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        )
      _ => value
    }
  }
}

///|
fn rewrite_collection_items(
  value : Value,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ListingValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk(
            element, segments, idx, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListingValue(next)
    }
    DefaultedListingValue(raw, elements, default_value) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk(
            element, segments, idx, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      DefaultedListingValue(raw, next, default_value)
    }
    ListValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk(
            element, segments, idx, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      ListValue(next)
    }
    SetValue(elements) => {
      let next : Array[Value] = []
      for element in elements {
        next.push(
          rewrite_walk(
            element, segments, idx, callback, bindings, env, class_env, cache, declarations,
            diagnostics, resolve_import,
          ),
        )
      }
      SetValue(next)
    }
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        next.push({
          key: entry.key,
          value: rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          ),
        })
      }
      MapValue(next)
    }
    _ => value
  }
}

///|
fn rewrite_collection_key(
  value : Value,
  key : String,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    MappingValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        let value = if entry.key == StringValue(key) {
          rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          )
        } else {
          entry.value
        }
        next.push({ key: entry.key, value })
      }
      MappingValue(next)
    }
    DefaultedMappingValue(raw, entries, default_value) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        let value = if entry.key == StringValue(key) {
          rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          )
        } else {
          entry.value
        }
        next.push({ key: entry.key, value })
      }
      DefaultedMappingValue(raw, next, default_value)
    }
    MapValue(entries) => {
      let next : Array[ValueEntry] = []
      for entry in entries {
        let value = if entry.key == StringValue(key) {
          rewrite_walk(
            entry.value,
            segments,
            idx,
            callback,
            bindings,
            env,
            class_env,
            cache,
            declarations,
            diagnostics,
            resolve_import,
          )
        } else {
          entry.value
        }
        next.push({ key: entry.key, value })
      }
      MapValue(next)
    }
    _ => value
  }
}

///|
fn rewrite_dynamic_subscript_any_value(
  value : Value,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
        if field.name == "@value" {
          next.push({
            name: field.name,
            value: rewrite_walk(
              field.value,
              segments,
              idx,
              callback,
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
            source: field.source,
            annotations: field.annotations,
          })
        } else {
          next.push(field)
        }
      }
      ObjectValue(next)
    }
    _ => value
  }
}

///|
fn rewrite_dynamic_subscript_value(
  value : Value,
  key : String,
  segments : Array[String],
  idx : Int,
  callback : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, "@key") {
        Some(StringValue(k)) if k == key => {
          let next : Array[ValueMember] = []
          for field in members {
            if field.name == "@value" {
              next.push({
                name: field.name,
                value: rewrite_walk(
                  field.value,
                  segments,
                  idx,
                  callback,
                  bindings,
                  env,
                  class_env,
                  cache,
                  declarations,
                  diagnostics,
                  resolve_import,
                ),
                source: field.source,
                annotations: field.annotations,
              })
            } else {
              next.push(field)
            }
          }
          ObjectValue(next)
        }
        _ => value
      }
    _ => value
  }
}

///|
fn path_has_wildcard(path : String) -> Bool {
  path.find("*") is Some(_)
}

///|
fn path_segment_is_collection_wildcard(segment : String) -> Bool {
  segment == "*" || segment == "[*]"
}

///|
fn path_segment_wildcard_base(segment : String) -> String? {
  if segment.length() > 3 && segment.has_suffix("[*]") {
    Some(String::unsafe_substring(segment, start=0, end=segment.length() - 3))
  } else {
    None
  }
}

///|
fn path_segment_subscript_base_key(segment : String) -> (String, String)? {
  match segment.find("[") {
    Some(idx) =>
      if idx > 0 && segment.has_suffix("]") && !segment.has_suffix("[*]") {
        Some(
          (
            String::unsafe_substring(segment, start=0, end=idx),
            String::unsafe_substring(
              segment,
              start=idx + 1,
              end=segment.length() - 1,
            ),
          ),
        )
      } else {
        None
      }
    None => None
  }
}

///|
fn path_segment_subscript_key(segment : String) -> String? {
  if segment.length() > 2 &&
    segment.has_prefix("[") &&
    segment.has_suffix("]") &&
    segment != "[*]" {
    Some(String::unsafe_substring(segment, start=1, end=segment.length() - 1))
  } else {
    None
  }
}

///|
fn path_segment_exact_name(segment : String) -> String {
  match path_segment_subscript_key(segment) {
    Some(name) => name
    None => segment
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let buf = StringBuilder::new()
  let normalized = if path.has_prefix("^") {
    String::unsafe_substring(path, start=1, end=path.length())
  } else {
    path
  }
  for i = 0; i < normalized.length(); i = i + 1 {
    let c = normalized[i].to_int().unsafe_to_char()
    if c == '.' {
      segments.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let last = buf.to_string()
  if last != "" || segments.length() > 0 {
    segments.push(last)
  }
  segments
}
