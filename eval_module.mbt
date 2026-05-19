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
          methods: class_decl.methods
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
            methods: class_export.methods
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
          methods: class_decl.methods
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
              methods: class_export.methods
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
        Some(value) => members.push({ name: binding.name, value, source: None })
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
            members.push({ name: binding.name, value, source: None })
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
                  value, source: None
                })
              None => ()
            }
          }
          None => ()
        }
      _ => ()
    }
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
      if converters.length() == 0 {
        Some(value)
      } else {
        Some(
          apply_path_converters(
            value,
            converters,
            bindings,
            env,
            class_env,
            cache,
            program.declarations,
            diagnostics,
            resolve_import,
          ),
        )
      }
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
              ), source: None
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
