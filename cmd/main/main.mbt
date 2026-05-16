///|
fn usage() -> Unit {
  println("usage: pkl <parse|check|eval|test|format|analyze> <file.pkl>")
  println("       pkl eval [-f|--format pcf|json|yaml|properties] <file.pkl>")
  println("       pkl test <file.pkl>")
  println("       pkl format <file.pkl>")
  println("       pkl analyze <file.pkl>")
  println("       pkl parse-many <file.pkl>...")
  println(
    "  sandbox flags: --allowed-modules <pipe-separated-prefixes> --module-path <dir> -p NAME=VALUE",
  )
}

///|
fn fail(message : String) -> Unit {
  println(message)
  @sys.exit(1)
}

///|

///|
/// Split `s` on `|`. Empty segments are dropped so a trailing or
/// leading pipe doesn't introduce an empty allow-list entry that
/// would match every URI.
fn split_pipe(s : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < s.length() {
    if s[i].to_int().unsafe_to_char() == '|' {
      if i > start {
        parts.push(String::unsafe_substring(s, start~, end=i))
      }
      start = i + 1
    }
    i = i + 1
  }
  if start < s.length() {
    parts.push(String::unsafe_substring(s, start~, end=s.length()))
  }
  parts
}

///|
fn resolve_import_path(from : String, uri : String) -> String {
  if uri.has_prefix("/") || uri.find(":") is Some(_) {
    return uri
  }
  match from.rev_find("/") {
    Some(idx) => String::unsafe_substring(from, start=0, end=idx + 1) + uri
    None => uri
  }
}

///|
fn stack_contains(stack : Array[String], path : String) -> Bool {
  for item in stack {
    if item == path {
      return true
    }
  }
  false
}

///|
fn push_stack(stack : Array[String], path : String) -> Array[String] {
  let next : Array[String] = []
  for item in stack {
    next.push(item)
  }
  next.push(path)
  next
}

///|
async fn load_expr_imports(
  session : @pkl.AnalysisSession,
  from : String,
  expr : @pkl.Expr,
  stack : Array[String],
  loaded : Map[String, Unit],
) -> Unit {
  match expr {
    ImportExpr(uri) =>
      load_path(
        session,
        resolve_import_path(from, uri),
        push_stack(stack, from),
        loaded,
      )
    ObjectLiteral(members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack, loaded)
      }
    TypedObjectLiteral(_, members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack, loaded)
      }
    ListingLiteral(elements) =>
      for element in elements {
        load_expr_imports(session, from, element, stack, loaded)
      }
    MappingLiteral(entries) =>
      for entry in entries {
        load_expr_imports(session, from, entry.key, stack, loaded)
        load_expr_imports(session, from, entry.value, stack, loaded)
      }
    MemberAccess(target, _) =>
      load_expr_imports(session, from, target, stack, loaded)
    SafeMemberAccess(target, _) =>
      load_expr_imports(session, from, target, stack, loaded)
    SubscriptAccess(target, key) => {
      load_expr_imports(session, from, target, stack, loaded)
      load_expr_imports(session, from, key, stack, loaded)
    }
    AmendExpr(base, members) => {
      load_expr_imports(session, from, base, stack, loaded)
      for object_member in members {
        load_expr_imports(session, from, object_member.value, stack, loaded)
      }
    }
    BinaryExpr(_, left, right) => {
      load_expr_imports(session, from, left, stack, loaded)
      load_expr_imports(session, from, right, stack, loaded)
    }
    CallExpr(callee, arguments) => {
      load_expr_imports(session, from, callee, stack, loaded)
      for argument in arguments {
        load_expr_imports(session, from, argument, stack, loaded)
      }
    }
    LambdaExpr(_, body, _) =>
      load_expr_imports(session, from, body, stack, loaded)
    NonNullExpr(inner) => load_expr_imports(session, from, inner, stack, loaded)
    UnaryExpr(_, inner) =>
      load_expr_imports(session, from, inner, stack, loaded)
    ConditionalExpr(condition, then_expr, else_expr) => {
      load_expr_imports(session, from, condition, stack, loaded)
      load_expr_imports(session, from, then_expr, stack, loaded)
      load_expr_imports(session, from, else_expr, stack, loaded)
    }
    _ => ()
  }
}

///|

///|
/// PKL-106: read a file, falling back to the `--module-path`
/// directories when the direct read misses. The first hit wins and
/// the absolute path is reported via `fail` if every candidate
/// misses so the diagnostic names the original URI, not an unhelpful
/// fallback path. Module-path directories are only consulted when
/// `path` has no scheme prefix and isn't an absolute filesystem
/// path — otherwise the user's intent was already explicit.
fn read_with_module_paths(path : String) -> String {
  let direct = @fs.read_file_to_string(path) catch { _ => "" }
  if direct != "" {
    return direct
  }
  let direct_exists = @fs.path_exists(path)
  if direct_exists {
    return direct
  }
  if path.has_prefix("/") || path.find(":") is Some(_) {
    fail("failed to read \{path}")
    return ""
  }
  for dir in @pkl.sandbox_module_paths() {
    let candidate = if dir.has_suffix("/") {
      dir + path
    } else {
      dir + "/" + path
    }
    let body = @fs.read_file_to_string(candidate) catch { _ => "" }
    if body != "" || @fs.path_exists(candidate) {
      return body
    }
  }
  fail("failed to read \{path}")
  ""
}

///|
async fn load_path(
  session : @pkl.AnalysisSession,
  path : String,
  stack : Array[String],
  loaded : Map[String, Unit],
) -> Unit {
  if path.has_prefix("pkl:") {
    return
  }
  // PKL-106: enforce `--allowed-modules` at the loader boundary.
  // The check applies to every URI we'd actually fetch / read, so a
  // disallowed transitive import surfaces at load time rather than
  // as a missing-symbol diagnostic from the evaluator.
  if !@pkl.sandbox_is_module_allowed(path) {
    fail("module \{path} is not allowed by --allowed-modules")
  }
  if stack_contains(stack, path) {
    fail("cyclic import \{path}")
  }
  // Skip files that have already been loaded in this run. Without this
  // guard a module that both `extends` and `import`s the same base
  // (e.g. pkspec's `Spec.pkl amends Test.pkl` + `import "Test.pkl" as
  // base`) parses the base twice — the recursion processes each
  // top-level reference independently. The session's `set_source`
  // already dedupes, but the redundant parse + recursive walk is what
  // actually costs time.
  if loaded.contains(path) {
    return
  }
  loaded[path] = ()
  // PKL-129: route URI-shaped paths through the HTTP fetch helper.
  // - `https://` / `http://`: fetched through `mizchi/x/http.get`
  //   under a `moonbitlang/async` event loop. Native target ships
  //   the working fetcher; JS / WASM print a diagnostic and exit
  //   pending WASI support.
  // - `package://`: not yet implemented. Apple Pkl's package
  //   registry protocol (zipball metadata + per-file path
  //   fragments) is a separate slice. Surface the gap clearly so
  //   the user knows the URI form was recognised.
  let source = if path.has_prefix("https://") || path.has_prefix("http://") {
    match fetch_uri(path) {
      Some(body) => body
      None => {
        fail("failed to fetch \{path}")
        ""
      }
    }
  } else if path.has_prefix("package://") {
    fail(
      "package:// imports not yet implemented — use the raw https:// URL of the .pkl file instead: \{path}",
    )
    ""
  } else {
    read_with_module_paths(path)
  }
  session.set_source(path, source)
  let parsed = @pkl.parse_source(source)
  for decl in parsed.program.imports {
    load_path(
      session,
      resolve_import_path(path, decl.uri),
      push_stack(stack, path),
      loaded,
    )
  }
  match parsed.program.module_relation {
    Some(relation) =>
      load_path(
        session,
        resolve_import_path(path, relation.uri),
        push_stack(stack, path),
        loaded,
      )
    None => ()
  }
  for binding in parsed.program.bindings {
    load_expr_imports(session, path, binding.value, stack, loaded)
  }
  match parsed.program.body {
    Some(expr) => load_expr_imports(session, path, expr, stack, loaded)
    None => ()
  }
}

///|
fn print_diagnostics(diagnostics : Array[@pkl.Diagnostic]) -> Unit {
  print_diagnostics_with_source(diagnostics, "", "")
}

///|
/// PKL-107: when a diagnostic carries a byte offset (`start >= 0`),
/// project it onto a `line:column` pair by walking `source` once.
/// The output format is `path:line:column: message` so editors / IDEs
/// can jump to the location. Diagnostics without positions render
/// as just `message`, matching the pre-PKL-107 behaviour.
fn print_diagnostics_with_source(
  diagnostics : Array[@pkl.Diagnostic],
  path : String,
  source : String,
) -> Unit {
  for diagnostic in diagnostics {
    if diagnostic.start >= 0 && source != "" {
      let (line, column) = offset_to_line_column(source, diagnostic.start)
      let prefix = if path == "" {
        "\{line}:\{column}"
      } else {
        "\{path}:\{line}:\{column}"
      }
      println("\{prefix}: \{diagnostic.message}")
    } else {
      println(diagnostic.message)
    }
  }
}

///|
fn offset_to_line_column(source : String, offset : Int) -> (Int, Int) {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  let cap = if offset < source.length() { offset } else { source.length() }
  while i < cap {
    let c = source[i].to_int().unsafe_to_char()
    if c == '\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    i = i + 1
  }
  (line, column)
}

///|
/// PKL-128d: emit a short structured summary of every annotation
/// captured by the parser. Output shape:
///
/// ```
/// annotation Deprecated on module: ParenBody=("removed in v3")
/// annotation ModuleInfo on module: BraceBody=(minPklVersion = "0.31.0")
/// annotation Since on class Box: NoBody=()
/// ```
///
/// Only emits when at least one annotation was captured so the
/// existing `parse → ok` smoke for annotation-free sources is
/// preserved byte-for-byte.
fn print_annotation_summary(program : @pkl.Program) -> Unit {
  let any = program.module_annotations.length() > 0 ||
    program.declarations
    .iter()
    .any(fn(d) {
      match d {
        ClassDeclaration(cd) => cd.annotations.length() > 0
        FunctionDeclaration(fd) => fd.annotations.length() > 0
        TypeAliasDeclaration(td) => td.annotations.length() > 0
      }
    })
  if !any {
    return
  }
  for a in program.module_annotations {
    println(
      "annotation \{a.class_name} on module: \{render_annotation_body(a)}",
    )
  }
  for decl in program.declarations {
    match decl {
      ClassDeclaration(cd) =>
        for a in cd.annotations {
          println(
            "annotation \{a.class_name} on class \{cd.name}: \{render_annotation_body(a)}",
          )
        }
      FunctionDeclaration(fd) =>
        for a in fd.annotations {
          println(
            "annotation \{a.class_name} on function \{fd.name}: \{render_annotation_body(a)}",
          )
        }
      TypeAliasDeclaration(td) =>
        for a in td.annotations {
          println(
            "annotation \{a.class_name} on typealias \{td.name}: \{render_annotation_body(a)}",
          )
        }
    }
  }
}

///|
fn render_annotation_body(a : @pkl.Annotation) -> String {
  match a.body_kind {
    NoBody => "NoBody=()"
    ParenBody => "ParenBody=(\{a.body_text})"
    BraceBody => "BraceBody=(\{a.body_text})"
  }
}

///|
fn parse_file(path : String) -> Bool {
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      println("failed to read \{path}")
      return false
    }
  }
  let parsed = @pkl.parse_source(source)
  if parsed.diagnostics.length() > 0 {
    print_diagnostics_with_source(parsed.diagnostics, path, source)
    false
  } else {
    true
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    usage()
    @sys.exit(1)
  }
  let command = args[1]
  if command == "parse-many" {
    let mut passed = 0
    let mut failed = 0
    for i = 2; i < args.length(); i = i + 1 {
      if parse_file(args[i]) {
        passed += 1
      } else {
        failed += 1
      }
    }
    if failed > 0 {
      println("failed \{failed} of \{passed + failed}")
      @sys.exit(1)
    }
    println("ok \{passed}")
    return
  }
  // Pull out optional flags after the command. `eval` understands
  // `-f <format>` / `--format <format>`; `test` understands
  // `--overwrite` to regenerate the examples golden file. Unknown
  // tokens are treated as positional arguments, which keeps the legacy
  // single-file form working.
  let mut format = "pcf"
  let mut format_explicit = false
  let mut overwrite = false
  let positional : Array[String] = []
  // PKL-106: sandbox knobs. Each is collected as a list so multiple
  // occurrences accumulate (`-p A=1 -p B=2`, `--module-path foo
  // --module-path bar`). `--allowed-modules` takes a single `|`-
  // separated pattern argument and overwrites the previous one,
  // matching Apple Pkl's flag.
  let prop_pairs : Map[String, String] = Map([], capacity=8)
  let module_paths : Array[String] = []
  let mut allowed_modules : Array[String] = []
  let mut i = 2
  while i < args.length() {
    let token = args[i]
    if token == "-f" || token == "--format" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      format = args[i + 1]
      format_explicit = true
      i = i + 2
    } else if token == "--overwrite" {
      overwrite = true
      i = i + 1
    } else if token == "-p" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      let pair = args[i + 1]
      match pair.find("=") {
        Some(eq) => {
          let name = String::unsafe_substring(pair, start=0, end=eq)
          let value = String::unsafe_substring(
            pair,
            start=eq + 1,
            end=pair.length(),
          )
          prop_pairs[name] = value
        }
        None => fail("-p expects NAME=VALUE, got: \{pair}")
      }
      i = i + 2
    } else if token == "--module-path" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      module_paths.push(args[i + 1])
      i = i + 2
    } else if token == "--allowed-modules" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      allowed_modules = split_pipe(args[i + 1])
      i = i + 2
    } else {
      positional.push(token)
      i = i + 1
    }
  }
  @pkl.configure_sandbox_props(prop_pairs)
  @pkl.configure_sandbox_module_paths(module_paths)
  @pkl.configure_sandbox_allowed_modules(allowed_modules)
  if format != "pcf" &&
    format != "json" &&
    format != "yaml" &&
    format != "properties" {
    fail("unsupported format: \{format}")
  }
  if positional.length() != 1 {
    usage()
    @sys.exit(1)
  }
  let path = positional[0]
  // PKL-129: entry-point paths may themselves be URIs. Route them
  // through the same dispatcher `load_path` uses so the top-level
  // module can live on a remote URL.
  let source = if path.has_prefix("https://") || path.has_prefix("http://") {
    match fetch_uri(path) {
      Some(body) => body
      None => {
        fail("failed to fetch \{path}")
        ""
      }
    }
  } else if path.has_prefix("package://") {
    fail(
      "package:// imports not yet implemented — use the raw https:// URL of the .pkl file instead: \{path}",
    )
    ""
  } else {
    @fs.read_file_to_string(path) catch {
      _ => {
        fail("failed to read \{path}")
        ""
      }
    }
  }
  match command {
    "parse" => {
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics_with_source(parsed.diagnostics, path, source)
        @sys.exit(1)
      }
      // PKL-128d: surface captured annotations so pkldoc / codegen
      // tooling can read them via the CLI. Printed only when at least
      // one annotation was captured, so the existing one-line `ok`
      // smoke output stays unchanged for annotation-free sources.
      print_annotation_summary(parsed.program)
      println("ok")
    }
    "check" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.typecheck_path(path) {
        TypeOk(typ) => println(@pkl.render_type(typ))
        TypeError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "eval" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(raw) => {
          // PKL-097: Apple Pkl uses a module-level `output { value =
          // ...; renderer = ... }` block to drive what `pkl eval`
          // returns. Extract `output.value` so fixtures that route
          // their data through it render only that subtree instead
          // of the whole module envelope.
          let value = extract_output_value(raw)
          // PKL-104: when the user didn't pass `-f / --format`, honor
          // the renderer class declared in `output { renderer = new
          // JsonRenderer { ... } }`. The class name is read directly
          // from the parsed AST (the eval result is a generic
          // ObjectValue that doesn't carry its source class). Explicit
          // `-f` always wins so existing test fixtures keep behaving.
          if !format_explicit {
            match detect_output_renderer_format(source) {
              Some(detected) => format = detected
              None => ()
            }
          }
          // The format string is validated up-front, so this match is
          // exhaustive at runtime. The explicit `pcf` arm doubles as
          // documentation: a future renderer added here surfaces as a
          // missing-arm warning rather than a silent fallback.
          match format {
            "json" => println(@pkl.render_value_as_json(value))
            "yaml" => {
              // render_value_as_yaml already terminates each line with
              // `\n`, including the final entry. Drop the trailing
              // newline so `println` does not double-up at end-of-stream.
              let yaml = @pkl.render_value_as_yaml(value)
              let trimmed = if yaml.has_suffix("\n") {
                String::unsafe_substring(yaml, start=0, end=yaml.length() - 1)
              } else {
                yaml
              }
              println(trimmed)
            }
            "properties" => {
              // Properties output is also line-terminated per entry;
              // strip the trailing newline so `println` keeps a single
              // final newline.
              let props = @pkl.render_value_as_properties(value)
              let trimmed = if props.has_suffix("\n") {
                String::unsafe_substring(props, start=0, end=props.length() - 1)
              } else {
                props
              }
              println(trimmed)
            }
            "pcf" => println(@pkl.render_value(value))
            _ => fail("unsupported format: \{format}")
          }
        }
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "test" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(value) => {
          let facts_summary = run_pkl_test(value)
          for line in facts_summary.lines {
            println(line)
          }
          // PKL-100: `examples` are tracked alongside `facts`. The
          // facts walker keeps its own summary (rendered above); the
          // examples diff runs as a second pass and contributes its own
          // pass / fail lines plus an additional non-zero exit on
          // mismatch / missing golden.
          let examples_summary = run_pkl_examples_test(value, path, overwrite)
          for line in examples_summary.lines {
            println(line)
          }
          if facts_summary.failed > 0 || examples_summary.failed > 0 {
            @sys.exit(1)
          }
        }
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    "analyze" => {
      // PKL-102: lightweight lint pass over the parsed module.
      // Reports unused locals / imports / private-class properties
      // and module-level shadowing. Exits non-zero when any finding
      // surfaces so editors / CI can fail on lint regressions.
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics_with_source(parsed.diagnostics, path, source)
        @sys.exit(1)
      }
      let findings = @pkl.lint_program(parsed.program)
      for finding in findings {
        println("\{path}: \{finding.rule}: \{finding.message}")
      }
      if findings.length() > 0 {
        @sys.exit(1)
      }
      println("ok")
    }
    "format" => {
      // PKL-099: parse the source, evaluate it through the existing
      // `AnalysisSession`, and re-emit the resolved module via the PCF
      // renderer. This is the first-cut formatter: input that fails to
      // evaluate (constraint reject, type error, etc.) fails the
      // command; structural and whitespace differences in the input
      // collapse to the renderer's canonical form. A trivia-preserving
      // formatter that round-trips comments and original layout is a
      // follow-up — the CST already carries the data, so the upgrade
      // path is purely on the emit side.
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics(parsed.diagnostics)
        @sys.exit(1)
      }
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [], Map([], capacity=32))
      match session.eval_path(path) {
        EvalOk(value) => println(@pkl.render_value(value))
        EvalError(diagnostics) => {
          print_diagnostics(diagnostics)
          @sys.exit(1)
        }
      }
    }
    _ => {
      usage()
      @sys.exit(1)
    }
  }
}

///|
priv struct PklTestSummary {
  lines : Array[String]
  failed : Int
}

///|
/// Walk a `facts: Mapping<String, Listing<Boolean>>` member at the
/// module level and report per-fact pass / fail. A fact passes when
/// every Boolean in its Listing is `true`; the first non-true value
/// (or any non-Boolean element) flips the fact to failed. Modules
/// without a `facts` member are treated as zero tests, which matches
/// `moon test`'s behaviour for empty test files.
fn run_pkl_test(value : @pkl.Value) -> PklTestSummary {
  let lines : Array[String] = []
  let mut passed = 0
  let mut failed = 0
  let facts : @pkl.Value? = lookup_module_member(value, "facts")
  match facts {
    Some(@pkl.MappingValue(entries)) =>
      for entry in entries {
        let name = match entry.key {
          @pkl.StringValue(s) => s
          _ => "<non-string key>"
        }
        let elements = match entry.value {
          @pkl.ListingValue(xs) => xs
          _ => []
        }
        let mut fact_failed = false
        let mut total = 0
        let mut bad_index = -1
        for i = 0; i < elements.length(); i = i + 1 {
          total += 1
          match elements[i] {
            @pkl.BoolValue(true) => ()
            _ =>
              if !fact_failed {
                fact_failed = true
                bad_index = i
              }
          }
        }
        if fact_failed {
          failed += 1
          lines.push(
            "FAIL \{name}: assertion #\{bad_index + 1} of \{total} did not evaluate to true",
          )
        } else {
          passed += 1
          lines.push("PASS \{name} (\{total} assertions)")
        }
      }
    Some(_) =>
      lines.push(
        "test runner expected `facts` to be a Mapping<String, Listing<Boolean>>",
      )
    None => ()
  }
  lines.push("\{passed} passed, \{failed} failed")
  { lines, failed }
}

///|
/// PKL-100 / PKL-095 shared helper: pick a top-level module member by
/// name. Returns the member value when the module is an `ObjectValue`
/// carrying that name; everything else (non-object module, missing
/// member) collapses to `None` so callers can branch on absence.
fn lookup_module_member(value : @pkl.Value, name : String) -> @pkl.Value? {
  match value {
    @pkl.ObjectValue(members) => {
      let mut found : @pkl.Value? = None
      for entry in members {
        if entry.name == name {
          found = Some(entry.value)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// PKL-100: walk the `examples` member and diff each example's rendered
/// PCF text against the corresponding section of the
/// `<path>-expected.pcf` golden file. On `--overwrite` the golden is
/// regenerated wholesale; otherwise mismatches surface as `FAIL` lines
/// and force a non-zero exit. The minimal envelope format is the
/// rendered `examples { ... }` block verbatim; richer per-example diffs
/// (with byte-level reporting) layer on top of this once a structured
/// golden format is introduced.
fn run_pkl_examples_test(
  value : @pkl.Value,
  path : String,
  overwrite : Bool,
) -> PklTestSummary {
  let lines : Array[String] = []
  let mut failed = 0
  match lookup_module_member(value, "examples") {
    Some(examples_value) => {
      let envelope = @pkl.ObjectValue([
        { name: "examples", value: examples_value },
      ])
      let rendered = @pkl.render_value(envelope) + "\n"
      let golden_path = path + "-expected.pcf"
      if overwrite {
        @fs.write_string_to_file(golden_path, rendered) catch {
          _ => {
            failed = failed + 1
            lines.push(
              "FAIL examples could not write golden file \{golden_path}",
            )
          }
        }
        lines.push("OVERWRITE \{golden_path}")
      } else {
        let expected = @fs.read_file_to_string(golden_path) catch { _ => "" }
        if expected == "" {
          failed = failed + 1
          lines.push("FAIL examples missing golden file \{golden_path}")
        } else if expected == rendered {
          let count = match examples_value {
            @pkl.MappingValue(entries) => entries.length()
            _ => 0
          }
          lines.push("PASS examples (\{count} examples)")
        } else {
          failed = failed + 1
          lines.push("FAIL examples diff against \{golden_path}")
        }
      }
    }
    None => ()
  }
  { lines, failed }
}

///|
/// PKL-097: If the module exposes an `output { value = ... }` member,
/// return that subtree so the renderer dispatches on it instead of
/// the whole module envelope. Modules without an `output.value` chain
/// fall through unchanged so existing single-binding fixtures keep
/// rendering the entire module the same way they did before.
/// PKL-104: walk the parsed module's `output { renderer = new
/// JsonRenderer { ... } }` block and map the renderer's class name
/// onto the existing CLI format string. Returns `None` when the
/// module has no `output.renderer` clause, or when the renderer's
/// class doesn't match a renderer pkl-mbt knows about (plist / xml /
/// protobuf / pkl-binary land with PKL-126). The format is read from
/// the parsed AST rather than the eval result because the eval
/// collapses the renderer class to a plain ObjectValue without
/// retaining the source class.
fn detect_output_renderer_format(source : String) -> String? {
  let parsed = @pkl.parse_source(source)
  for binding in parsed.program.bindings {
    if binding.name == "output" {
      match binding.value {
        ObjectLiteral(members) =>
          for field in members {
            if field.name == "renderer" {
              match renderer_format_from_expr(field.value) {
                Some(f) => return Some(f)
                None => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  None
}

///|
fn renderer_format_from_expr(expr : @pkl.Expr) -> String? {
  match expr {
    TypedObjectLiteral(class_name, _) => renderer_format_from_class(class_name)
    AmendExpr(base, _) => renderer_format_from_expr(base)
    _ => None
  }
}

///|
fn renderer_format_from_class(class_name : String) -> String? {
  // The class name often arrives qualified (`pkl.JsonRenderer` /
  // `base.PcfRenderer`). Strip a trailing `Renderer` suffix and any
  // qualifier prefix before matching so both forms work.
  let raw = class_name
  let stripped = match raw.rev_find(".") {
    Some(idx) => String::unsafe_substring(raw, start=idx + 1, end=raw.length())
    None => raw
  }
  match stripped {
    "JsonRenderer" => Some("json")
    "YamlRenderer" => Some("yaml")
    "PropertiesRenderer" => Some("properties")
    "PcfRenderer" => Some("pcf")
    _ => None
  }
}

///|
fn extract_output_value(value : @pkl.Value) -> @pkl.Value {
  match value {
    @pkl.ObjectValue(members) => {
      let mut output_value : @pkl.Value? = None
      let mut has_output = false
      for entry in members {
        if entry.name == "output" {
          has_output = true
          match entry.value {
            @pkl.ObjectValue(sub_members) =>
              for sub in sub_members {
                if sub.name == "value" {
                  output_value = Some(sub.value)
                }
              }
            _ => ()
          }
        }
      }
      match output_value {
        Some(v) => v
        None =>
          // PKL-104: `output { renderer = ... }` without an explicit
          // `output.value` projects the module's *other* properties,
          // not the `output` block itself. Strip `output` from the
          // rendered envelope so the renderer doesn't echo its own
          // configuration into the output (matches Apple Pkl's
          // module-body rendering rules).
          if has_output {
            let visible : Array[@pkl.ValueMember] = []
            for entry in members {
              if entry.name != "output" {
                visible.push(entry)
              }
            }
            @pkl.ObjectValue(visible)
          } else {
            value
          }
      }
    }
    _ => value
  }
}
