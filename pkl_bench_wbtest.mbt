// Internal-stage benches. Black-box benches in `pkl_bench_test.mbt`
// only see `parse_source` / `eval_source` / `typecheck_source`, which
// makes it hard to tell whether a regression sits in the lexer or in
// the parser state machine. The whitebox versions here call the
// underlying private helpers directly so each stage shows up on its
// own line in `moon bench`.

///|
fn read_wbtest_source(path : String) -> String {
  try {
    @fs.read_file_to_string(path)
  } catch {
    _ => ""
  }
}

///|
let bench_wb_apple_pkl_stdlib_base : String = read_wbtest_source(
  "third_party/apple-pkl/stdlib/base.pkl",
)

///|
let bench_wb_pkspec_test_schema : String = read_wbtest_source(
  "../pkspec/pkl/Test.pkl",
)

///|
test "bench tokenize/apple-pkl-stdlib-base" (b : @bench.T) {
  if bench_wb_apple_pkl_stdlib_base == "" {
    return
  }
  b.bench(name="tokenize/apple-pkl-stdlib-base", fn() {
    b.keep(tokenize(bench_wb_apple_pkl_stdlib_base).length())
  })
}

///|
test "bench tokenize/pkspec-test-schema" (b : @bench.T) {
  if bench_wb_pkspec_test_schema == "" {
    return
  }
  b.bench(name="tokenize/pkspec-test-schema", fn() {
    b.keep(tokenize(bench_wb_pkspec_test_schema).length())
  })
}

///|
test "bench parser_new/apple-pkl-stdlib-base" (b : @bench.T) {
  if bench_wb_apple_pkl_stdlib_base == "" {
    return
  }
  b.bench(name="parser_new/apple-pkl-stdlib-base", fn() {
    b.keep(Parser::new(bench_wb_apple_pkl_stdlib_base).len)
  })
}
