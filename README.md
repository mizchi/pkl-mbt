# pkl-mbt

Pure MoonBit parser, typechecker, and evaluator for Apple's [Pkl](https://pkl-lang.org/) language. Ships as both a CLI (`mpkl`) and a library (`mizchi/pkl`).

## Install

CLI (`native` + `js` only — the wasm / wasm-gc targets ship a stub `main` that points users at the library):

```bash
moon install mizchi/pkl/cmd/mpkl
```

Library — builds clean on all four MoonBit targets (`native`, `js`, `wasm`, `wasm-gc`); the @pkl surface is pure (no IO, no async), so an embedder running in a wasm sandbox can depend on it directly:

```bash
moon add mizchi/pkl
```

## CLI — `mpkl`

```bash
mpkl parse    <file.pkl>                  # parse-only sanity check
mpkl check    <file.pkl>                  # typecheck, print module type
mpkl eval     <file.pkl> [-f <format>]    # eval + render (default: pcf)
mpkl test     <file.pkl> [--overwrite]    # walk facts: / examples:
mpkl format   <file.pkl>                  # canonical PCF re-emit
mpkl analyze  <file.pkl>                  # lint (unused locals / imports / ...)
mpkl codegen  <file.pkl>                  # lower to MoonBit struct skeleton
mpkl stdlib                               # probe stdlib coverage (PASS/FAIL per module)
```

Renderers exposed via `-f` / `--format`: `pcf` (default), `json`, `yaml`, `properties`, `plist`. `output { renderer = new <Renderer> { ... } }` in the source also drives the format without an explicit flag.

Sandbox flags (apply to `read("...")` and `import "..."`):

```bash
--allowed-modules <pipe|separated|prefixes>   # default: unrestricted
--module-path     <dir>                        # repeatable
-p NAME=VALUE                                  # populates read("prop:NAME")
```

## Library — `@pkl`

23 public items. The full surface lives in `pkg.generated.mbti`; the high-level shape:

```moonbit
// Parse / typecheck / eval entry points
@pkl.parse_source(source : String) -> @pkl.ParseResult
@pkl.typecheck_source(source : String) -> @pkl.TypecheckResult
@pkl.eval_source(source : String) -> @pkl.EvalResult

// Incremental analysis (ripple-backed)
let session = @pkl.AnalysisSession::new()
session.set_source("main.pkl", source)
session.typecheck_path("main.pkl")
session.eval_path("main.pkl")

// Renderers
@pkl.render_value(value)                        // PCF
@pkl.render_value_as_json(value)
@pkl.render_value_as_yaml(value)
@pkl.render_value_as_properties(value)
@pkl.render_value_as_plist(value)
@pkl.render_type(typ)

// MoonBit codegen — emit `pub(all) struct` / typealias skeletons
@pkl.codegen_moonbit(program) -> String

// Lint
@pkl.lint_program(program) -> Array[@pkl.LintFinding]

// Sandbox config (mutable module state, read by the loader)
@pkl.configure_sandbox_props(map)
@pkl.configure_sandbox_module_paths(dirs)
@pkl.configure_sandbox_allowed_modules(patterns)
@pkl.sandbox_module_paths()
@pkl.sandbox_is_module_allowed(uri)
```

ADTs (`pub(all)`, suitable for pattern matching from consumer code): `Program` / `Declaration` / `ClassDecl` / `FunctionDecl` / `TypeAliasDecl` / `Expr` / `BinaryOp` / `UnaryOp` / `Binding` / `ImportDecl` / `Annotation` / `Type` / `TypeMember` / `Value` / `ValueMember` / `ValueEntry` / `Diagnostic` / `LintFinding` etc. — see the `.mbti` for the exhaustive list.

## Supported language surface

### Parser

CST-backed via `mizchi/cst`. Accepts **802 / 802** fixtures of the upstream `LanguageSnippetTests` parser corpus (parse-only). Modifier-qualified forms (`const function`, `abstract class`), generic `class C<T>` / `function f<T>(...)`, doc-comments, structured `@Annotation(...)` / `@Annotation { ... }` capture, `when (cond) { ... } else { ... }`, `for (var in xs) { ... }`, `let (name = value) body`, multi-line typealiases, dot-chain across newlines, scientific Float (`1.5e10`), triple-quoted heredoc strings with `\(expr)` interpolation, `??` null-coalescing, `?.` safe member access, and the full operator grid (`** ~/ % | & .. ..< >.. >=..`).

### Typechecker

Primitive (`Int` / `Float` / `Number` / `Bool` / `String` / `Null` / `Any` / `Unknown`), nullable `T?`, parametric generics on classes and functions (`Box<T>` / `identity<T>(x: T)`), generic typealiases (`typealias Box<T> = Listing<T>`), type-parameter bounds (`<T : Number>`), union (`A | B`) with `is`-guard narrowing, structural classes with inheritance + abstract-method coverage + override-direction subtype rules (covariant return, contravariant params), constraint cascade through `Listing<T>` / `Mapping<K, V>` / `Pair<A, B>` / `Set<T>` / `Map<K, V>` / `IntSeq` annotations, cross-module function exports via hidden-prefixed members, equality type compatibility, callable & class-method literal-body return / argument validation including user-defined constraint factories.

### Evaluator

- All numeric / scalar primitives plus dedicated value variants for `Pair<A, B>`, `IntSeq` (lazy carrier), `Set<T>`, `Map<K, V>` (immutable functional map, distinct from object-style `Mapping<K, V>`).
- `Duration` / `DataSize` literals (`3.s`, `4.mb`, etc.) with mixed-unit arithmetic, comparisons, `.value` / `.unit` / `.toUnit(name)`. Float magnitudes (`1.5.s`, `2.5.gib`) round-trip without precision loss.
- `Regex("...")` with `.matches / .find / .findAll / .replace / .replaceAll` backed by `moonbitlang/regexp`. PCF round-trips through the constructor form.
- `Bytes(<Listing>)` / `Bytes.fromBase64("...")` with `.length` / `.base64` / `.getOrNull(i)` / `.toList()`, plus `String.toBytes()` UTF-8 encoder. JSON / YAML / Properties / plist project as the base64 string.
- Lambda closures (scalar + non-scalar capture), `super.method(args)` dispatch, `module.foo` self-reference, `import("...")` expression form, `when` / `for` object-body generators.
- Sandbox-bounded `read(uri)` (env: enabled by default; prop: opens via `-p NAME=VALUE`; file:/https:/package: gated by `--allowed-modules`), `throw(msg)`, `trace(value)`.

### Renderers

PCF, JSON, YAML, Properties, plist (Apple PLIST 1.0 DTD). Each carries the dedicated value-variant projections: `Pair(a, b)` / `Set(...)` / `Map(k, v, ...)` / `IntSeq(s, e).step(n)` round-trip through PCF for parser-readable output; JSON / YAML / Properties / plist materialize as arrays / objects with Apple Pkl's conventions (`omitNullProperties` defaults, Duration/DataSize space-separated form in plist, etc.). The CLI's AST-driven dispatcher reads `output { renderer = new <ClassName> { ... } }` and routes accordingly when `-f` is absent.

### Stdlib modules

Synthesized in-process (no upstream Pkl JAR required). Run `mpkl stdlib` to verify each module against the in-process probe table — it eval s one minimal fixture per documented capability and prints `[PASS]` / `[FAIL]` per row, exiting non-zero on regression.

| Module | Status | Coverage |
| --- | --- | --- |
| `pkl:base` (Listing / Mapping / String / Int builtins + value-variant ops + 9 Renderer classes + Duration / DataSize / Regex / Bytes) | Full | Method surface used by upstream `LanguageSnippetTests` fixtures + the dedicated `Pair` / `IntSeq` / `Set` / `Map` value variants. |
| `pkl:math` | Full | Int constants + helpers + Float-side `sqrt` / `pow` / `log` / `exp` / trig / `pi` / `e`. |
| `pkl:semver` | Full | `parse` / `parseOrNull` / `compare` / ordering — full SemVer pre-release semantics. |
| `pkl:platform` | Partial (deterministic stub) | Returns fixed `stub-os` / `stub-arch` values; the host-detection intrinsics aren't wired. |
| `pkl:test` | Partial | `test.catch(() -> throw(...))` returns the thrown message. The no-throw branch evaluates the lambda as if catch wasn't there (the constraints8.pkl flow is the upstream use we pin). |
| `pkl:reflect` | Stub | Mirror constants (`intType` etc.) + `Class` / `Module` / `TypeAlias` / `Property` / `DeclaredType` factories returning `reflectee` containers. No `isSubclassOf`, no runtime member introspection. |
| `pkl:json` / `pkl:yaml` | Type surface only | `Parser` + `Property` class shells instantiable; actual JSON / YAML parsing not implemented. |
| `pkl:xml` / `pkl:protobuf` | Type surface only | `Renderer` class shells instantiable; rendering itself stays in the deferred slices. |

### Imports

`file:` / `https:` (with 5-hop redirect following) / `package:` (URI parse + metadata fetch + zipball URL extraction; full DEFLATE+SHA-256+cache deferred — the diagnostic points users at `pkl download-package` + `--module-path` as a workaround).

### Upstream compatibility

- **Parser corpus**: 802 / 802 LanguageSnippetTests fixtures
- **Eval gold-match**: 32 PCF + 1 JSON + 1 plist fixtures byte-for-byte against the upstream `.pcf` / `.json` / `.plist` files
- **Diagnostic wording**: aligned with Apple Pkl's first-line phrasing (`Cannot find type \`X\`.` / `Cannot find property \`x\`.` / `Cannot find module \`...\`.` etc.)

## Not yet supported

Intentionally deferred — `specs/Roadmap.pkl`'s `deferredEntries`
listing carries the full rationale. One-line summaries:

| Slice | Status | Workaround |
| --- | --- | --- |
| LSP server | Out of scope (library focus). | Use Apple Pkl's `pkl-lsp`. |
| `mpkl repl` (interactive REPL) | Deferred. | Wrap `eval` in a shell loop. |
| `mpkl doc` / pkldoc generation | Deferred. | Use upstream `pkldoc`. |
| XML renderer (`-f xml` / `xml.Renderer`) | Deferred — type surface only. | `pkl eval -f xml` upstream. |
| Protobuf renderer | Deferred — type surface only. | `pkl eval -f protobuf` upstream. |
| Renderer `converters { ... }` machinery | Deferred. | `pkl eval` upstream. |
| `package://` zipball download + unpack | Deferred — URI parse + metadata probe land. | `pkl download-package` + `--module-path`. |

Partially landed:

- `read?(uri)` null-returning variant — only `read(uri)` (sandbox-bounded) is wired.
- `IntSeq` equality — structural `derive(Eq)`; Apple Pkl's empty-sequence-equality and step-aware element-set equality stay a follow-up.
- `pkl:reflect` — minimal mirror-constant + factory stub; `isSubclassOf`, real `ClassValue` round-trip, and runtime member introspection are absent.

## Development

```bash
# Local CI gate
pkf run release-check

# Targeted runs
moon test --target native
moon check --deny-warn --target native
pkspec exec -f specs/Test.pkl
pkspec spec --check specs/Spec.pkl specs/Test.pkl
```

Upstream submodule for gold-match:

```bash
git submodule update --init --recursive
./scripts/upstream-smoke.sh
./scripts/upstream-parse-suite.sh
```

## Status

144 implemented pkspec scenarios; active roadmap is empty (parser / typechecker / evaluator / codegen core has landed). See `SPEC.md` for the full rendered spec. Deferred slices live in `specs/Roadmap.pkl`'s `deferredEntries` listing and can revive on demand.
