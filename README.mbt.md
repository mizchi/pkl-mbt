# mizchi/pkl

Pure-MoonBit parser, typechecker, evaluator, and renderer for Apple's [Pkl](https://pkl-lang.org/) language. Builds clean on all four MoonBit targets (`native`, `js`, `wasm`, `wasm-gc`); the `@pkl` surface is pure (no IO, no async) so an embedder running in a wasm sandbox can depend on it directly. The `cmd/mpkl` package includes a Marketplace `SKILL.md` and a `moon runwasm` entry for parse, check, eval, and format workflows over inline source or local files with relative imports and cache-backed `package://` modules.

The CLI lives in [`cmd/mpkl`](https://github.com/mizchi/pkl-mbt/tree/main/cmd/mpkl) (`mpkl parse|check|eval|test|format|analyze|codegen`). See the [repository README](https://github.com/mizchi/pkl-mbt) for install / usage / benchmarks against Apple Pkl.

## What the library exposes

Entry points:

- `parse_source(source) -> ParseResult` — top-level CST-backed parse.
- `eval_source(source) -> EvalResult` — parse + evaluate a single source.
- `typecheck_source(source) -> TypecheckResult` — parse + typecheck.
- `lint_program(program) -> Array[LintFinding]` — static-analysis pass.
- `codegen(program, target) -> String` — code generator dispatch (`CodegenTarget::MoonBit` today).
- `AnalysisSession` — incremental, ripple-backed analysis for editor / multi-file flows.

Renderers (one entry per format): `render_value` (PCF, default), plus `render_value_as_json` / `_yaml` / `_xml` / `_textproto` / `_properties` / `_plist` / `_jsonnet` and their `_document` / `_fragment` / `_with_indent` / `_with_options` variants. Apple Pkl's `output { renderer = new <Renderer> { ... } }` is honoured.

Sandbox configuration (`configure_sandbox_*` / `register_*`): module allowlist, module paths, package caches, `prop:` / `env:` populating, static read-resource registration, import-glob registration, `extends`-chain parent binding resolver, and the lazy stdlib `base.pkl` loader. The dynamic resource-reader hook `configure_sandbox_resource_reader(scheme, fn(uri) -> SandboxResource?)` lets an embedded caller service `read("scheme:path")` calls in-process (HTTP / DB / shell-exec etc.).

## Status

The release gate byte-matches all Apple Pkl 0.32.1 LanguageSnippetTests that ship reference output (416/416). The remaining 544 fixtures have no gold file; all 960 are still covered by the exclusion-free parser/diagnostic differential. The embedded standard-library type facade resolves all 324 public top-level declarations from the 23 public `pkl:` modules.

Known gaps for embedded callers:

- **CLI surface is partial.** `eval`, `test`, `format`, and `analyze` exist, but multiple-module/stdin/output-path/expression flows and the upstream `repl`, `server`, `project`, `download-package`, `run`, and `shell-completion` commands are not implemented. Most upstream common CLI options are also absent.
- **Standard-library behavior is not complete.** The 324/324 check proves import/type-name resolution, not method-level semantic parity. Several modules use deterministic stubs or partial implementations where Apple Pkl delegates to VM internals.
- **Property computation is memoized and demand-driven.** `Value` carries self-contained property-thunk cells backed by a `Pending` / `Evaluating` / `Resolved` / `Rejected` state machine. Successful and failed right-hand sides in local/exported object bindings—including typed constructors—are evaluated at first access, with type/constraint checks and recursive-force detection memoized in the same cell. Settled cells release their computation closures, and separate analysis sessions do not share cell state. Lookup, output/rendering, converter, and amend consumers force the values they select; class defaults retain their separate declaration-scoped memo/materialization guard. `eval_source` remains an eager compatibility projection, while runtime-metadata consumers can call `force_value` explicitly.
- **External-reader subprocess protocol.** Apple Pkl's `--external-resource-reader=<scheme>=<bin>` ships a MessagePack-framed IPC; mpkl's in-process callback hook is the embedded substitute. A subprocess-side adapter would need MoonBit's `core` / `x` packages to ship a subprocess runtime first.

## Versioning

This is `0.5.0`. Pre-1.0 minor bumps may break the public surface — semver promises kick in at `1.0.0`.
