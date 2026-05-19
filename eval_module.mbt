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
      None => diagnostics.push(diag("Cannot find module `\{decl.uri}`."))
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
fn eval_read_uri(uri : String, diagnostics : Array[Diagnostic]) -> Value? {
  // PKL-098 / PKL-106 sandbox policy: `env:` is always on the
  // allow-list; `prop:` is allow-listed when the CLI installed at
  // least one `-p NAME=VALUE` binding. The remaining Apple Pkl
  // schemes (`file:`, `https:`, `package:`) still need explicit
  // policy decisions before they ship; surfacing them as a
  // diagnostic keeps the failure mode honest until those follow-up
  // slices land.
  match uri.find(":") {
    None => {
      diagnostics.push(diag("read: missing URI scheme in \"\{uri}\""))
      None
    }
    Some(idx) => {
      let scheme = String::unsafe_substring(uri, start=0, end=idx)
      let rest = String::unsafe_substring(uri, start=idx + 1, end=uri.length())
      if scheme == "env" {
        match @env.get_env_var(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag("read: env variable \{rest} is not set"))
            None
          }
        }
      } else if scheme == "prop" {
        match sandbox_lookup_prop(rest) {
          Some(value) => Some(StringValue(value))
          None => {
            diagnostics.push(diag("read: prop \{rest} is not set"))
            None
          }
        }
      } else {
        diagnostics.push(
          diag("read: scheme \{scheme}: is not allowed by the sandbox policy"),
        )
        None
      }
    }
  }
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
        Some(_value) =>
          if caught_diagnostics.length() > 0 {
            Some(ThrewOutcome(caught_diagnostics[0].message))
          } else {
            Some(NoThrowOutcome)
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
  let module_parent_members : Array[ValueMember] = []
  let bindings = all_eval_bindings(program)
  eval_imports(program.imports, env, diagnostics, resolve_import)
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
      let converters = collect_path_converters(value)
      let class_converters = collect_class_converters(value)
      let property_transformers = collect_convert_property_transformers(
        value,
        bindings,
        env,
        class_env,
        cache,
        program.declarations,
        diagnostics,
        resolve_import,
      )
      let renderer_value = collect_output_renderer(value)
      let mut current = value
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
                      for renderer_member in renderer_members {
                        if renderer_member.name == "converters" {
                          match renderer_member.value {
                            MappingValue(entries) =>
                              for entry in entries {
                                match entry.key {
                                  StringValue(path) =>
                                    converters.push((path, entry.value))
                                  _ => ()
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
                      for renderer_member in renderer_members {
                        if renderer_member.name == "converters" {
                          match renderer_member.value {
                            MappingValue(entries) =>
                              for entry in entries {
                                match entry.key {
                                  ObjectValue(class_mirror_members) =>
                                    match
                                      lookup_member(
                                        class_mirror_members, "name",
                                      ) {
                                      Some(StringValue(name)) =>
                                        converters.push((name, entry.value))
                                      _ => ()
                                    }
                                  _ => ()
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
      ObjectValue(next)
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
  let mut current = value
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
  if annotation.class_name == "protobuf.Property" {
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
      match lookup_value(call_cache, "@__module_name") {
        Some(_) => ()
        None =>
          match lookup_value(caller_cache, "@__module_name") {
            Some(v) => call_cache.push({ name: "@__module_name", value: v })
            None => ()
          }
      }
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
      ObjectValue(next)
    }
    _ => value
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
  let descended = match value {
    ObjectValue(members) => {
      let next : Array[ValueMember] = []
      for field in members {
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
          key: e.key,
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
    _ => value
  }
  // Look up a matching converter for this node's class. Class-specific
  // wins over `Any`; if neither matches, the descended value flows
  // through unchanged.
  let chosen = pick_class_converter(descended, converters, class_env)
  match chosen {
    Some(callback) =>
      match
        apply_function_value(
          "renderer converter",
          callback,
          [descended],
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
        None => descended
      }
    None => descended
  }
}

///|
fn pick_class_converter(
  value : Value,
  converters : Array[(String, Value)],
  class_env : Array[ClassBinding],
) -> Value? {
  // PKL-152: collection wrappers (Listing / Mapping / Map / Pair) are
  // never re-rendered through `[Any]`; their elements are walked
  // first, then the wrapper passes through. Scalar values also skip
  // `[Any]` — Apple Pkl's class identity for "Any" matches user class
  // instances (ObjectValue with a class tag), not the universal
  // scalar/collection projection.
  let tag = match value {
    ObjectValue(members) =>
      match find_object_class_tag(members) {
        Some(s) => s
        None => "Dynamic"
      }
    _ => return None
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
  // Fall back to `Any` if present — only fires for ObjectValues.
  for entry in converters {
    if entry.0 == "Any" {
      return Some(entry.1)
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
          if field.name == segment {
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
          let key_matches = match entry.key {
            StringValue(k) => k == segment
            _ => false
          }
          if key_matches {
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
      _ => value
    }
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i].to_int().unsafe_to_char()
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
