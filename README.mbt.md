# mizchi/pkl

Pure-MoonBit parser, typechecker, evaluator, and renderer for Apple's [Pkl](https://pkl-lang.org/) language. Builds clean on all four MoonBit targets (`native`, `js`, `wasm`, `wasm-gc`); the `@pkl` surface is pure (no IO, no async) so an embedder running in a wasm sandbox can depend on it directly.

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

The release gate passes Apple Pkl's upstream LanguageSnippetTests across the advertised renderers (PCF, JSON, YAML, properties, plist, textproto, XML, Jsonnet). Coverage of the Apple Pkl test surface is ~96% by gold-match; see the repository's `TODO.md` for the remaining fixture inventory.

Known gaps for embedded callers:

- **Eager property evaluation.** mpkl evaluates every property of a `new T { ... }` object eagerly; Apple Pkl is lazy. Object bodies that contain a slot whose body errors on a code path the caller never reads (`new Result { cases = cases.length; ... }` where `cases.length` would fail but the caller only reads `result.passed`) still error in mpkl. Tracked as a follow-up.
- **External-reader subprocess protocol.** Apple Pkl's `--external-resource-reader=<scheme>=<bin>` ships a MessagePack-framed IPC; mpkl's in-process callback hook is the embedded substitute. A subprocess-side adapter would need MoonBit's `core` / `x` packages to ship a subprocess runtime first.

## Versioning

This is `0.2.0`. Pre-1.0 minor bumps may break the public surface — semver promises kick in at `1.0.0`.
