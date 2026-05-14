///|
let parser_small_source = "module demo\nname = \"hawk\"\nage = 2\nactive = true\n"

///|
let parser_object_source = "module bench\nlocal base = 2\nserver {\n  host = \"localhost\"\n  port = base * 4000 + 80\n  tls {\n    enabled = true\n    cert = \"dev.pem\"\n  }\n}\n"

///|
let parser_import_source = "import \"base.pkl\" as base\nlocal imported = import(\"base.pkl\")\nname = base.name\nsize = imported.size + 1\n"

///|
test "bench parse/small-module" (b : @bench.T) {
  b.bench(name="parse/small-module", fn() {
    let parsed = parse_source(parser_small_source)
    b.keep(parsed.diagnostics.length())
  })
}

///|
test "bench parse/object-body" (b : @bench.T) {
  b.bench(name="parse/object-body", fn() {
    let parsed = parse_source(parser_object_source)
    b.keep(parsed.program.bindings.length())
  })
}

///|
test "bench parse/imports" (b : @bench.T) {
  b.bench(name="parse/imports", fn() {
    let parsed = parse_source(parser_import_source)
    b.keep(parsed.program.imports.length() + parsed.program.bindings.length())
  })
}

///|
test "bench eval/object-body" (b : @bench.T) {
  b.bench(name="eval/object-body", fn() {
    b.keep(eval_source(parser_object_source))
  })
}

///|
test "bench typecheck/object-body" (b : @bench.T) {
  b.bench(name="typecheck/object-body", fn() {
    b.keep(typecheck_source(parser_object_source))
  })
}

///|
test "bench analysis/import-eval-cache-hit" (b : @bench.T) {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "name = \"hawk\"\nsize = 41\n")
  session.set_source("main.pkl", parser_import_source)
  ignore(session.eval_path("main.pkl"))
  b.bench(name="analysis/import-eval-cache-hit", fn() {
    b.keep(session.eval_path("main.pkl"))
  })
}
