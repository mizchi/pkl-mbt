// Sandboxed Marketplace entry point for `mpkl`.
//
// The native / JS CLI resolves files, imports, packages, and network resources
// asynchronously. `moon runwasm` exposes a synchronous local-file subset: it
// accepts either one self-contained module via `--source` or a filesystem entry
// point whose relative imports and module relations are loaded recursively.

///|
priv struct WasmCommandResult {
  exit_code : Int
  output : String
}

///|
fn wasm_usage() -> String {
  "usage: mpkl <parse|check|eval|format> (--source <pkl-source> | <file.pkl>) [--format <pcf|json|yaml|properties|plist|textproto|xml|jsonnet>] [--package-cache <dir>]"
}

///|
fn wasm_result(exit_code : Int, output : String) -> WasmCommandResult {
  { exit_code, output }
}

///|
fn render_wasm_diagnostics(diagnostics : Array[@pkl.Diagnostic]) -> String {
  let output = StringBuilder()
  let mut first = true
  for diagnostic in diagnostics {
    if first {
      first = false
    } else {
      output.write_char('\n')
    }
    output.write_string(
      "error[\{diagnostic.start}..\{diagnostic.end}]: \{diagnostic.message}",
    )
  }
  output.to_string()
}

///|
fn trim_final_newline(text : String) -> String {
  if text.has_suffix("\n") {
    String::unsafe_substring(text, start=0, end=text.length() - 1)
  } else {
    text
  }
}

///|
fn is_wasm_format_supported(format : String) -> Bool {
  format == "pcf" ||
  format == "json" ||
  format == "yaml" ||
  format == "properties" ||
  format == "plist" ||
  format == "textproto" ||
  format == "xml" ||
  format == "jsonnet"
}

///|
fn render_wasm_value(value : @pkl.Value, format : String) -> String {
  let rendered = match format {
    "json" => @pkl.render_value_as_json(value)
    "yaml" => @pkl.render_value_as_yaml(value)
    "properties" => @pkl.render_value_as_properties(value)
    "plist" => @pkl.render_value_as_plist(value)
    "textproto" => @pkl.render_value_as_textproto(value)
    "xml" => @pkl.render_value_as_xml(value)
    "jsonnet" => @pkl.render_value_as_jsonnet_document(value)
    _ => @pkl.render_value(value)
  }
  trim_final_newline(rendered)
}

///|
fn wasm_stack_contains(stack : Array[String], path : String) -> Bool {
  for item in stack {
    if item == path {
      return true
    }
  }
  false
}

///|
fn push_wasm_stack(stack : Array[String], path : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(path)
  next
}

///|
fn normalize_wasm_path(path : String) -> String {
  let path = path.replace_all(old="\\", new="/")
  let scheme_end = match path.find("://") {
    Some(index) => index + 3
    None => 0
  }
  let head = String::unsafe_substring(path, start=0, end=scheme_end)
  let body = String::unsafe_substring(path, start=scheme_end, end=path.length())
  let leading_slash = body.has_prefix("/")
  let raw_segments : Array[String] = []
  let mut start = if leading_slash { 1 } else { 0 }
  let mut i = start
  while i < body.length() {
    if body.unsafe_get(i) == '/' {
      raw_segments.push(String::unsafe_substring(body, start~, end=i))
      start = i + 1
    }
    i = i + 1
  }
  if start <= body.length() {
    raw_segments.push(String::unsafe_substring(body, start~, end=body.length()))
  }
  let resolved : Array[String] = []
  for segment in raw_segments {
    if segment == "" || segment == "." {
      continue
    }
    if segment == ".." {
      if resolved.length() > 0 && resolved[resolved.length() - 1] != ".." {
        let _ = resolved.pop()
      } else if !leading_slash {
        resolved.push("..")
      }
      continue
    }
    resolved.push(segment)
  }
  let output = StringBuilder()
  output.write_string(head)
  if leading_slash {
    output.write_char('/')
  }
  for i, segment in resolved {
    if i > 0 {
      output.write_char('/')
    }
    output.write_string(segment)
  }
  output.to_string()
}

///|
fn is_wasm_absolute_path(path : String) -> Bool {
  path.has_prefix("/") ||
  (path.length() >= 3 && path[1] == ':' && path[2] == '/')
}

///|
fn resolve_wasm_import_path(from : String, uri : String) -> String? {
  if uri.has_prefix("pkl:") {
    return Some(uri)
  }
  if is_package_uri_like(uri) {
    return Some(normalize_wasm_path(uri))
  }
  if is_wasm_absolute_path(uri) {
    return Some(normalize_wasm_path(uri))
  }
  if uri.find(":") is Some(_) {
    return None
  }
  let combined = match from.rev_find("/") {
    Some(index) => String::unsafe_substring(from, start=0, end=index + 1) + uri
    None => uri
  }
  Some(normalize_wasm_path(combined))
}

///|
fn read_wasm_source(
  path : String,
  package_cache_roots : Array[String],
) -> Result[String, String] {
  let filesystem_path = if is_package_uri_like(path) {
    match resolve_package_uri_to_cache_in_roots(path, "", package_cache_roots) {
      Some(cached_path) => cached_path
      None =>
        return Err(
          "Cannot find package module `\{path}` in the configured package cache. Pre-fetch it with native mpkl or pass --package-cache <dir>.",
        )
    }
  } else {
    path
  }
  Ok(@fs.read_file_to_string(filesystem_path)) catch {
    _ => Err("Cannot find module `\{path}`.")
  }
}

///|
fn load_wasm_expr_imports(
  session : @pkl.AnalysisSession,
  from : String,
  expr : @pkl.Expr,
  package_cache_roots : Array[String],
  stack : Array[String],
  loaded : Map[String, Unit],
) -> String? {
  match expr {
    ImportExpr(uri) =>
      match resolve_wasm_import_path(from, uri) {
        Some(resolved) =>
          load_wasm_path(session, resolved, package_cache_roots, stack, loaded)
        None => Some("unsupported module URI in Wasm file mode: \{uri}")
      }
    ImportGlobExpr(pattern) =>
      Some("import glob is not supported in Wasm file mode: \{pattern}")
    ObjectLiteral(members) | TypedObjectLiteral(_, members) => {
      for object_member in members {
        match
          load_wasm_expr_imports(
            session,
            from,
            object_member.value,
            package_cache_roots,
            stack,
            loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    ListingLiteral(elements) | InterpolatedString(elements) => {
      for element in elements {
        match
          load_wasm_expr_imports(
            session, from, element, package_cache_roots, stack, loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    MappingLiteral(entries) => {
      for entry in entries {
        match
          load_wasm_expr_imports(
            session,
            from,
            entry.key,
            package_cache_roots,
            stack,
            loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
        match
          load_wasm_expr_imports(
            session,
            from,
            entry.value,
            package_cache_roots,
            stack,
            loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    MemberAccess(target, _)
    | SafeMemberAccess(target, _)
    | NonNullExpr(target)
    | UnaryExpr(_, target)
    | WhenSpread(target) =>
      load_wasm_expr_imports(
        session, from, target, package_cache_roots, stack, loaded,
      )
    SubscriptAccess(target, key) | BinaryExpr(_, target, key) =>
      match
        load_wasm_expr_imports(
          session, from, target, package_cache_roots, stack, loaded,
        ) {
        Some(error) => Some(error)
        None =>
          load_wasm_expr_imports(
            session, from, key, package_cache_roots, stack, loaded,
          )
      }
    AmendExpr(base, members) => {
      match
        load_wasm_expr_imports(
          session, from, base, package_cache_roots, stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
      for object_member in members {
        match
          load_wasm_expr_imports(
            session,
            from,
            object_member.value,
            package_cache_roots,
            stack,
            loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    CallExpr(callee, arguments) | NullSafeCallExpr(callee, arguments) => {
      match
        load_wasm_expr_imports(
          session, from, callee, package_cache_roots, stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
      for argument in arguments {
        match
          load_wasm_expr_imports(
            session, from, argument, package_cache_roots, stack, loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    LambdaExpr(_, body, _) =>
      load_wasm_expr_imports(
        session, from, body, package_cache_roots, stack, loaded,
      )
    LetExpr(_, _, value, body) =>
      match
        load_wasm_expr_imports(
          session, from, value, package_cache_roots, stack, loaded,
        ) {
        Some(error) => Some(error)
        None =>
          load_wasm_expr_imports(
            session, from, body, package_cache_roots, stack, loaded,
          )
      }
    ConditionalExpr(condition, then_expr, else_expr) => {
      match
        load_wasm_expr_imports(
          session, from, condition, package_cache_roots, stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
      match
        load_wasm_expr_imports(
          session, from, then_expr, package_cache_roots, stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
      load_wasm_expr_imports(
        session, from, else_expr, package_cache_roots, stack, loaded,
      )
    }
    ForGenerator(_, _, source, members, _, _) => {
      match
        load_wasm_expr_imports(
          session, from, source, package_cache_roots, stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
      for object_member in members {
        match
          load_wasm_expr_imports(
            session,
            from,
            object_member.value,
            package_cache_roots,
            stack,
            loaded,
          ) {
          Some(error) => return Some(error)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
fn load_wasm_path(
  session : @pkl.AnalysisSession,
  path : String,
  package_cache_roots : Array[String],
  stack : Array[String],
  loaded : Map[String, Unit],
) -> String? {
  if path.has_prefix("pkl:") || loaded.contains(path) {
    return None
  }
  if wasm_stack_contains(stack, path) {
    return None
  }
  let source = match read_wasm_source(path, package_cache_roots) {
    Ok(source) => source
    Err(error) => return Some(error)
  }
  loaded[path] = ()
  session.set_source(path, source)
  let parsed = @pkl.parse_source(source)
  let next_stack = push_wasm_stack(stack, path)
  for import_decl in parsed.program.imports {
    if import_decl.is_glob {
      return Some(
        "import glob is not supported in Wasm file mode: \{import_decl.uri}",
      )
    }
    let resolved = match resolve_wasm_import_path(path, import_decl.uri) {
      Some(resolved) => resolved
      None =>
        return Some(
          "unsupported module URI in Wasm file mode: \{import_decl.uri}",
        )
    }
    match
      load_wasm_path(session, resolved, package_cache_roots, next_stack, loaded) {
      Some(error) => return Some(error)
      None => ()
    }
  }
  match parsed.program.module_relation {
    Some(relation) => {
      let resolved = match resolve_wasm_import_path(path, relation.uri) {
        Some(resolved) => resolved
        None =>
          return Some(
            "unsupported module URI in Wasm file mode: \{relation.uri}",
          )
      }
      match
        load_wasm_path(
          session, resolved, package_cache_roots, next_stack, loaded,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
    }
    None => ()
  }
  for binding in parsed.program.bindings {
    match
      load_wasm_expr_imports(
        session,
        path,
        binding.value,
        package_cache_roots,
        next_stack,
        loaded,
      ) {
      Some(error) => return Some(error)
      None => ()
    }
  }
  match parsed.program.body {
    Some(expr) =>
      load_wasm_expr_imports(
        session, path, expr, package_cache_roots, next_stack, loaded,
      )
    None => None
  }
}

///|
fn run_wasm_source_command(
  command : String,
  source : String,
  format : String,
) -> WasmCommandResult {
  match command {
    "parse" => {
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        wasm_result(1, render_wasm_diagnostics(parsed.diagnostics))
      } else {
        wasm_result(0, "ok")
      }
    }
    "check" =>
      match @pkl.typecheck_source(source) {
        TypeOk(typ) => wasm_result(0, @pkl.render_type(typ))
        TypeError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    "eval" =>
      match @pkl.eval_source(source) {
        EvalOk(value) =>
          wasm_result(
            0,
            render_wasm_value(@pkl.extract_output_value(value), format),
          )
        EvalError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    "format" =>
      match @pkl.eval_source(source) {
        EvalOk(value) => wasm_result(0, render_wasm_value(value, "pcf"))
        EvalError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    _ => wasm_result(2, wasm_usage())
  }
}

///|
fn run_wasm_file_command(
  command : String,
  path : String,
  format : String,
  configured_package_caches : Array[String],
) -> WasmCommandResult {
  let path = normalize_wasm_path(path)
  let package_cache_roots = package_cache_roots_from(configured_package_caches)
  if command == "parse" {
    return match read_wasm_source(path, package_cache_roots) {
      Ok(source) => run_wasm_source_command(command, source, format)
      Err(error) => wasm_result(1, error)
    }
  }
  let session = @pkl.AnalysisSession::new()
  match load_wasm_path(session, path, package_cache_roots, [], Map([])) {
    Some(error) => return wasm_result(1, error)
    None => ()
  }
  match command {
    "check" =>
      match session.typecheck_path(path) {
        TypeOk(typ) => wasm_result(0, @pkl.render_type(typ))
        TypeError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    "eval" =>
      match session.eval_path(path) {
        EvalOk(value) =>
          wasm_result(
            0,
            render_wasm_value(@pkl.extract_output_value(value), format),
          )
        EvalError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    "format" =>
      match session.eval_path(path) {
        EvalOk(value) => wasm_result(0, render_wasm_value(value, "pcf"))
        EvalError(diagnostics) =>
          wasm_result(1, render_wasm_diagnostics(diagnostics))
      }
    _ => wasm_result(2, wasm_usage())
  }
}

///|
fn run_wasm_command(args : Array[String]) -> WasmCommandResult {
  if args.length() == 0 {
    return wasm_result(2, wasm_usage())
  }
  let command = args[0]
  if command == "help" || command == "--help" || command == "-h" {
    return wasm_result(0, wasm_usage())
  }
  if command != "parse" &&
    command != "check" &&
    command != "eval" &&
    command != "format" {
    return wasm_result(2, "unsupported command: \{command}\n\{wasm_usage()}")
  }
  let mut file : String? = None
  let mut source : String? = None
  let package_caches : Array[String] = []
  let mut format = "pcf"
  let mut format_explicit = false
  let mut i = 1
  while i < args.length() {
    let token = args[i]
    if token == "--source" {
      if i + 1 >= args.length() {
        return wasm_result(2, "--source requires a value")
      }
      if source is Some(_) {
        return wasm_result(2, "--source may only be specified once")
      }
      source = Some(args[i + 1])
      i = i + 2
    } else if token == "--format" || token == "-f" {
      if i + 1 >= args.length() {
        return wasm_result(2, "\{token} requires a value")
      }
      format = args[i + 1]
      format_explicit = true
      i = i + 2
    } else if token == "--package-cache" {
      if i + 1 >= args.length() {
        return wasm_result(2, "--package-cache requires a value")
      }
      package_caches.push(args[i + 1])
      i = i + 2
    } else if token.has_prefix("-") {
      return wasm_result(2, "unsupported argument: \{token}\n\{wasm_usage()}")
    } else {
      if file is Some(_) {
        return wasm_result(2, "only one input file may be specified")
      }
      file = Some(token)
      i = i + 1
    }
  }
  if !is_wasm_format_supported(format) {
    return wasm_result(2, "unsupported format: \{format}")
  }
  if format_explicit && command != "eval" {
    return wasm_result(2, "--format is only supported by eval")
  }
  match (source, file) {
    (Some(_), Some(_)) =>
      wasm_result(2, "pass either --source or a file path, not both")
    (Some(source), None) => run_wasm_source_command(command, source, format)
    (None, Some(path)) =>
      run_wasm_file_command(command, path, format, package_caches)
    (None, None) => wasm_result(2, "missing input: pass --source or <file.pkl>")
  }
}

///|
fn keep_wasm_imports_linked() -> Unit {
  // Imports are shared with the native / JS CLI at package scope. Keep the
  // target-specific aliases referenced so `--deny-warn` remains useful on
  // wasm without granting these capabilities to the Marketplace command.
  ignore(@fs.path_exists)
  let _http_ref : @http.Response? = None
  ignore(_http_ref)
  ignore(@zlib.crc32(b""))
  ignore(@async.is_being_cancelled)
  ignore(@utf8.decode(b""[:]) catch { _ => "" })
  ignore(@env.current_dir)
  let _json_path_ref : @json.JsonPath? = None
  ignore(_json_path_ref)
  ignore(@crypto.sha256(b""))
}

///|
fn main {
  keep_wasm_imports_linked()
  let cli_args = @env.args()
  let args : Array[String] = []
  for i = 1; i < cli_args.length(); i = i + 1 {
    args.push(cli_args[i])
  }
  let result = run_wasm_command(args)
  if result.output != "" {
    println(result.output)
  }
  if result.exit_code != 0 {
    @sys.exit(result.exit_code)
  }
}
