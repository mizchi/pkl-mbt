# pkl-mbt

Pure MoonBit parser, typechecker, and evaluator for Apple's [Pkl](https://pkl-lang.org/) language. Ships as both a CLI (`mpkl`) and a library (`mizchi/pkl`).

**Compatibility policy**: behaviour follows [Apple Pkl](https://pkl-lang.org/). The current release gate passes the upstream test surface outside the intentionally postponed Jsonnet renderer fixtures. Divergent output or a crash where Apple Pkl returns a value is a bug; please file an issue with the source snippet and Apple Pkl's output for comparison.

## Install

CLI (native + js only — the wasm / wasm-gc targets ship a stub `main` that points users at the library):

```bash
moon install mizchi/pkl/cmd/mpkl
```

Library — builds clean on all four MoonBit targets (`native`, `js`, `wasm`, `wasm-gc`); the `@pkl` surface is pure (no IO, no async), so an embedder running in a wasm sandbox can depend on it directly:

```bash
moon add mizchi/pkl
```

## CLI — `mpkl`

```bash
mpkl parse    <file.pkl>                       # parse-only sanity check
mpkl check    <file.pkl>                       # typecheck, print module type
mpkl eval     <file.pkl> [-f <format>]         # eval + render (default: pcf)
mpkl test     <file.pkl> [--overwrite]         # walk facts: / examples:
                       [--junit-reports <dir>] # write JUnit XML per module
mpkl format   <file.pkl>                       # canonical PCF re-emit
mpkl analyze  <file.pkl>                       # lint (unused locals / imports / ...)
mpkl codegen  <file.pkl> [-t moonbit]          # lower to a target-language skeleton  (pkl-mbt only)
```

Renderers via `-f` / `--format`: `pcf` (default), `json`, `yaml`, `properties`, `plist`, `textproto`, `xml`. `output { renderer = new <Renderer> { ... } }` also drives the format from the source.

Sandbox flags: `--allowed-modules <pipe|prefixes>`, `--module-path <dir>` (repeatable), `--package-cache <dir>` (repeatable; resolves and stores `package://host/path/name@version#/file.pkl` under `<dir>/path/name@version/package/file.pkl`; when omitted the CLI uses `$PKL_MBT_PACKAGE_CACHE`, `$XDG_CACHE_HOME/pkl-mbt/package-2`, or `$HOME/.cache/pkl-mbt/package-2`), `-p NAME=VALUE` (populates `read("prop:NAME")`).

`mpkl test`: same wire shape as Apple Pkl's `pkl test` for facts + examples + golden diff. `--junit-reports <dir>` writes `<dir>/<basename>.xml` per module (one `<testsuite>` per file, one `<testcase>` per fact + one for the examples block) so CI / pkspec-style runners can ingest structured results. Eval-time errors surface as a single failed `<testcase name="eval">` so a parse / type failure still leaves an envelope.

## pkl-mbt specific

These don't exist in Apple Pkl:

- **`mpkl codegen <file.pkl> [-t <target>]`** — lowers a Pkl module to a target-language skeleton. Today only `moonbit` is wired; the `@pkl.CodegenTarget` enum + `@pkl.codegen(program, target)` dispatcher keep the API shape stable when other targets (Java / Kotlin / Swift / Go / TypeScript) land.
- **`mpkl analyze`** — lint pass over the parsed module (unused locals / imports / class properties / module-level shadowing).
- **Library entrypoint** (`@pkl`) — pure-MoonBit, no IO / async, builds clean on all four MoonBit targets. Apple's `pkl` ships as a JVM-backed CLI.
- **In-process resource reader hook** — `@pkl.configure_sandbox_resource_reader(scheme, fn(uri) -> SandboxResource?)` lets an embedded host service `read("<scheme>:<path>")` calls in-process. Useful for plugging in HTTP / DB / shell-exec readers without spawning a separate process. Apple Pkl's equivalent is the `--external-resource-reader=<scheme>=<bin>` MessagePack-IPC binary; the in-process hook trades the protocol overhead for a callback that runs in the same address space.

## Status

The parser, evaluator, typechecker, package/project loading, and advertised renderers (PCF, JSON, YAML, properties, plist, textproto, XML, and Jsonnet) are passing the current release test gate. The remaining Jsonnet fixtures (`jsonnetRenderer7` — Mixin / Function rendering diagnostic, `jsonnetRenderer8` — `convertPropertyTransformers`) are tracked as follow-ups; see [TODO.md](TODO.md) for the full upstream fixture inventory and release notes.

### 0.2.2 highlights

- **`default` field on a user class is no longer hidden.** `class P { default: String? = null }; new P { default = "world" }` previously rendered as `default = null` — the parser unconditionally renamed any body `default = ...` slot to the hidden namespace (a workaround for `new Dynamic { default = (_) -> 42 }`'s per-element-default semantics). The rename is now narrowed to the lambda-valued case, so scalar / collection assignments to a `default`-named property flow through to the class's public slot. Unblocks pkfire's `Param.default`.

### 0.2.1 highlights

- **Self-referential `Listing<T>` / `Mapping<K, T>` defaults no longer hang.** A class declared as `class Task { deps: Listing<Task> = new {} }` used to spin mpkl indefinitely when its class-default was materialised — the element-default synthesis path entered a fresh seen-set and recursed forever on the element type. A `materializing` marker on the class-default memo entry now records the in-flight class name so element synthesis short-circuits to the empty shape (the materialised default is unobservable for an empty collection anyway). Real schemas that model graphs (pkfire's `Taskfile`, recursive AST types) build through.
- **`module.X` resolves past inner-scope field shadows.** Inside a derived module's `output.value` re-eval, `new R { defaults = module.defaults }` used to false-positive "cyclic property reference defaults" because `find_binding` picked up R's `defaults` field (last-wins) instead of the module-level `defaults` binding, and the inner field's name was on the resolve stack. The `module.X` lookup now reorders the bindings list so the module-level binding wins the reverse walk regardless of how many inner-scope fields share the name.
- **Dropped a `module.X` short-circuit that returned the outer snapshot.** A leftover branch returned the whole `outer` ObjectValue as the result of `module.X` when X wasn't in cache but lived in the bindings list. Inside a nested object-literal body (`new R { workflowTests = new Listing { for (wt in module.workflowTests) { ... } } }`) this returned R's in-flight body as `module.workflowTests`, which then iterated dynamically and produced shape-wrong inner values. `module.X` now always resolves through the standard binding / cache / parent-super chain.

### 0.2.0 highlights

- **`extends`-chain re-eval is now late-binding-aware.** Parent-module member bodies that reference inherited fields (`local testNames = tests.toList()...; output { value = new { dupCount = duplicateNames.length } }`) now propagate derived-module overrides instead of returning the parent-static cached value. The fix threads parent's raw `Binding[]` through the re-eval path and arranges `parent visibles → derived exported → parent locals` so derived's amends win for shared visible names while `localModuleMemberOverride2`-style derived locals do not shadow a coincident parent visible reference.
- **Cross-module recursive functions and module-locals.** A `function f(...)` imported from another module can now recurse and reference module-private helpers (`local mask32 = 0xffffffff`); the function-eval post-pass cross-links every top-level function's captured env so the body sees siblings + locals at apply time even when the caller is in a different module.
- **`Listing<T>` / `Mapping<K,V>` return types drive `new {}` interpretation.** A `function f(): Listing<Case> = let (r = ...) new { for (...) { ... } }` body now produces a ListingValue instead of an ObjectValue — the body rewrite walks through `LetExpr` wrappers to reach the inner `new {}`.
- **`mpkl test --junit-reports <dir>`.** Same wire shape as Apple Pkl's flag; pkspec / CI runners can ingest structured results.
- **In-process resource reader hook.** `configure_sandbox_resource_reader("cmd", fn)` services `read("cmd:...")` via an embedded callback; see pkl-mbt specific above.

## Benchmarks vs Apple Pkl

`scripts/bench-vs-pkl.sh` (hyperfine, `--shell=none`, warmup 5 / runs 25, parity-guarded by a pre-bench `diff` against `pkl eval`) on macOS arm64. Both binaries are native AOT — Apple Pkl 0.31.1 native, `mpkl` `moon build --release --target native`. Lower ratio = mpkl faster.

| fixture | mpkl mean | pkl mean | mpkl / pkl |
| --- | ---: | ---: | ---: |
| `cli.pkl` (micro) | 4.6 ms | 8.0 ms | **0.58×** |
| `cli_amends_base_merge.pkl` | 4.3 ms | 7.8 ms | **0.55×** |
| `cli_map_value.pkl` | 4.8 ms | 9.0 ms | **0.54×** |
| `cli_set_value.pkl` | 4.6 ms | 7.9 ms | **0.59×** |
| `cli_int_seq_value.pkl` | 4.6 ms | 7.6 ms | **0.60×** |
| upstream `basic/int.pkl` | 7.2 ms | 9.4 ms | **0.77×** |
| upstream `basic/float.pkl` | 6.7 ms | 8.1 ms | **0.83×** |
| upstream `basic/string.pkl` | 6.3 ms | 10.7 ms | **0.58×** |
| upstream `basic/as.pkl` | 7.2 ms | 9.1 ms | **0.80×** |
| upstream `basic/is.pkl` | 6.9 ms | 8.2 ms | **0.84×** |
| upstream `basic/new.pkl` | 6.5 ms | 9.8 ms | **0.66×** |
| upstream `basic/rawString.pkl` | 5.4 ms | 7.2 ms | **0.75×** |
| `pkspec/Test.pkl` (1643 lines, 49 classes) | 20.4 ms | 9.7 ms | 2.11× |

12 of 13 fixtures have `mpkl` faster than `pkl`. The outlier (`pkspec/Test.pkl`) is now allocator / GC-bound (`moonbit_drop_object` / `malloc` / `_platform_memmove` dominate the profile) — algorithmic wins from the leaf-string and class-default passes have largely landed; further gap-closing on this fixture needs either Array pooling on the class-default synthesis path or cheaper structural-equality fast paths.

On larger synthetic workloads the gap widens in mpkl's favour as the class-default memoisation amortises:

| fixture | mpkl | pkl | ratio |
| --- | ---: | ---: | ---: |
| 200 Group × 3 Item Listing | 23 ms | 211 ms | mpkl **9× faster** |
| 1000 Group × 3 Item Listing | 39 ms | 113 ms | mpkl **2.9× faster** |
| `apple-pkl/stdlib/base.pkl` (eval as user module, ~150 classes) | 62 ms | — | (no fair pkl comparison — stdlib) |

See [`benchmarks/refactor-2026-05-22.md`](benchmarks/refactor-2026-05-22.md) for the prior session retro (26 commits, baseline `pkspec/Test.pkl` 830 ms → 22 ms, 38× speedup) and [`benchmarks/refactor-2026-05-23.md`](benchmarks/refactor-2026-05-23.md) for the 0.2.0 round (lazy stdlib base.pkl load, class-default purity verdict memo, strip-source in place, Protobuf renderer extracted to its own file).

## Development

```bash
pkf run release-check                       # full local gate (14 tasks)
moon test --target native
moon check --deny-warn --target wasm-gc
pkspec exec -f specs/Test.pkl
```

Upstream submodule for gold-match:

```bash
git submodule update --init --recursive
./scripts/upstream-smoke.sh
./scripts/upstream-parse-suite.sh
```

CI (`.github/workflows/ci.yml`) runs the same gate on every push / PR. 181 implemented pkspec scenarios; see `SPEC.md` for the full rendered spec.
