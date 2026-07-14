///|
test "wasm skill parses inline Pkl source" {
  let result = run_wasm_command([
    "parse", "--source", "name = \"Pkl\"\nanswer = 6 * 7",
  ])
  assert_eq(result.exit_code, 0)
  assert_eq(result.output, "ok")
}

///|
test "wasm skill typechecks inline Pkl source" {
  let result = run_wasm_command([
    "check", "--source", "name: String = \"Pkl\"\nanswer = 6 * 7",
  ])
  assert_eq(result.exit_code, 0)
  assert_eq(result.output, "Object")
}

///|
test "wasm skill evaluates inline Pkl source as JSON" {
  let result = run_wasm_command([
    "eval", "--format", "json", "--source", "name = \"Pkl\"\nanswer = 6 * 7",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.output.contains("\"name\": \"Pkl\""))
  assert_true(result.output.contains("\"answer\": 42"))
}

///|
test "wasm skill formats inline Pkl source as PCF" {
  let result = run_wasm_command([
    "format", "--source", "name=\"Pkl\"\nanswer=6*7",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.output.contains("name = \"Pkl\""))
  assert_true(result.output.contains("answer = 42"))
}

///|
test "wasm skill rejects unsupported output formats" {
  let result = run_wasm_command([
    "eval", "--format", "toml", "--source", "answer = 42",
  ])
  assert_eq(result.exit_code, 2)
  assert_eq(result.output, "unsupported format: toml")
}

///|
test "wasm skill only accepts output formats for eval" {
  let result = run_wasm_command([
    "check", "--format", "json", "--source", "answer = 42",
  ])
  assert_eq(result.exit_code, 2)
  assert_eq(result.output, "--format is only supported by eval")
}

///|
test "wasm skill requires an explicit inline source" {
  let result = run_wasm_command(["eval"])
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("file.pkl"))
}

///|
test "wasm skill evaluates a file with a relative import" {
  let result = run_wasm_command([
    "eval", "--format", "json", "cmd/mpkl/testdata/wasm/main.pkl",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.output.contains("\"name\": \"Pkl\""))
  assert_true(result.output.contains("\"answer\": 42"))
}

///|
test "wasm skill loads an amends parent from the filesystem" {
  let result = run_wasm_command([
    "eval", "--format", "json", "cmd/mpkl/testdata/wasm/amended.pkl",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.output.contains("\"name\": \"Pkl\""))
  assert_true(result.output.contains("\"answer\": 42"))
}

///|
test "wasm skill resolves an amends parent from a package cache" {
  let result = run_wasm_command([
    "eval", "--format", "json", "--package-cache", "cmd/mpkl/testdata/wasm/package-cache",
    "cmd/mpkl/testdata/wasm/package-amended.pkl",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.output.contains("\"name\": \"package child\""))
  assert_true(result.output.contains("\"answer\": 42"))
}

///|
test "wasm skill preserves package URI identity for relative imports" {
  assert_eq(
    resolve_wasm_import_path(
      "package://pkg.pkl-lang.org/example/demo@1.0.0#/dir/main.pkl", "../base.pkl",
    ),
    Some("package://pkg.pkl-lang.org/example/demo@1.0.0#/base.pkl"),
  )
}

///|
test "wasm skill reports an uncached package with recovery guidance" {
  let result = run_wasm_command([
    "eval", "--package-cache", "cmd/mpkl/testdata/wasm/empty-package-cache", "cmd/mpkl/testdata/wasm/package-amended.pkl",
  ])
  assert_eq(result.exit_code, 1)
  assert_true(result.output.contains("Cannot find package module"))
  assert_true(result.output.contains("--package-cache <dir>"))
}

///|
test "wasm skill rejects source and file together" {
  let result = run_wasm_command([
    "eval", "--source", "answer = 42", "cmd/mpkl/testdata/wasm/main.pkl",
  ])
  assert_eq(result.exit_code, 2)
  assert_eq(result.output, "pass either --source or a file path, not both")
}

///|
test "wasm skill reports a missing file" {
  let result = run_wasm_command(["eval", "cmd/mpkl/testdata/wasm/missing.pkl"])
  assert_eq(result.exit_code, 1)
  assert_true(result.output.contains("Cannot find module"))
}

///|
test "wasm skill normalizes Windows file paths" {
  assert_eq(
    normalize_wasm_path("C:\\work\\config\\..\\main.pkl"),
    "C:/work/main.pkl",
  )
}
