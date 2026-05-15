///|
fn usage() -> Unit {
  println("usage: pkl <parse|check|eval> <file.pkl>")
  println("       pkl eval [-f|--format pcf|json|yaml|properties] <file.pkl>")
  println("       pkl parse-many <file.pkl>...")
}

///|
fn fail(message : String) -> Unit {
  println(message)
  @sys.exit(1)
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
fn load_expr_imports(
  session : @pkl.AnalysisSession,
  from : String,
  expr : @pkl.Expr,
  stack : Array[String],
) -> Unit {
  match expr {
    ImportExpr(uri) =>
      load_path(
        session,
        resolve_import_path(from, uri),
        push_stack(stack, from),
      )
    ObjectLiteral(members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack)
      }
    TypedObjectLiteral(_, members) =>
      for field in members {
        load_expr_imports(session, from, field.value, stack)
      }
    ListingLiteral(elements) =>
      for element in elements {
        load_expr_imports(session, from, element, stack)
      }
    MappingLiteral(entries) =>
      for entry in entries {
        load_expr_imports(session, from, entry.key, stack)
        load_expr_imports(session, from, entry.value, stack)
      }
    MemberAccess(target, _) => load_expr_imports(session, from, target, stack)
    SafeMemberAccess(target, _) =>
      load_expr_imports(session, from, target, stack)
    SubscriptAccess(target, key) => {
      load_expr_imports(session, from, target, stack)
      load_expr_imports(session, from, key, stack)
    }
    AmendExpr(base, members) => {
      load_expr_imports(session, from, base, stack)
      for object_member in members {
        load_expr_imports(session, from, object_member.value, stack)
      }
    }
    BinaryExpr(_, left, right) => {
      load_expr_imports(session, from, left, stack)
      load_expr_imports(session, from, right, stack)
    }
    CallExpr(callee, arguments) => {
      load_expr_imports(session, from, callee, stack)
      for argument in arguments {
        load_expr_imports(session, from, argument, stack)
      }
    }
    LambdaExpr(_, body, _) => load_expr_imports(session, from, body, stack)
    NonNullExpr(inner) => load_expr_imports(session, from, inner, stack)
    UnaryExpr(_, inner) => load_expr_imports(session, from, inner, stack)
    ConditionalExpr(condition, then_expr, else_expr) => {
      load_expr_imports(session, from, condition, stack)
      load_expr_imports(session, from, then_expr, stack)
      load_expr_imports(session, from, else_expr, stack)
    }
    _ => ()
  }
}

///|
fn load_path(
  session : @pkl.AnalysisSession,
  path : String,
  stack : Array[String],
) -> Unit {
  if path.has_prefix("pkl:") {
    return
  }
  if stack_contains(stack, path) {
    fail("cyclic import \{path}")
  }
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      fail("failed to read \{path}")
      ""
    }
  }
  session.set_source(path, source)
  let parsed = @pkl.parse_source(source)
  for decl in parsed.program.imports {
    load_path(
      session,
      resolve_import_path(path, decl.uri),
      push_stack(stack, path),
    )
  }
  match parsed.program.module_relation {
    Some(relation) =>
      load_path(
        session,
        resolve_import_path(path, relation.uri),
        push_stack(stack, path),
      )
    None => ()
  }
  for binding in parsed.program.bindings {
    load_expr_imports(session, path, binding.value, stack)
  }
  match parsed.program.body {
    Some(expr) => load_expr_imports(session, path, expr, stack)
    None => ()
  }
}

///|
fn print_diagnostics(diagnostics : Array[@pkl.Diagnostic]) -> Unit {
  for diagnostic in diagnostics {
    println(diagnostic.message)
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
    println("\{path}:")
    print_diagnostics(parsed.diagnostics)
    false
  } else {
    true
  }
}

///|
fn main {
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
  // Pull out optional flags after the command. Only `eval` currently
  // understands `-f <format>` / `--format <format>`; everything else
  // continues to require exactly one positional argument.
  let mut format = "pcf"
  let positional : Array[String] = []
  let mut i = 2
  while i < args.length() {
    let token = args[i]
    if token == "-f" || token == "--format" {
      if i + 1 >= args.length() {
        usage()
        @sys.exit(1)
      }
      format = args[i + 1]
      i = i + 2
    } else {
      positional.push(token)
      i = i + 1
    }
  }
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
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      fail("failed to read \{path}")
      ""
    }
  }
  match command {
    "parse" => {
      let parsed = @pkl.parse_source(source)
      if parsed.diagnostics.length() > 0 {
        print_diagnostics(parsed.diagnostics)
        @sys.exit(1)
      }
      println("ok")
    }
    "check" => {
      let session = @pkl.AnalysisSession::new()
      load_path(session, path, [])
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
      load_path(session, path, [])
      match session.eval_path(path) {
        EvalOk(value) =>
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
