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
mpkl parse    <file.pkl>                  # parse-only sanity check
mpkl check    <file.pkl>                  # typecheck, print module type
mpkl eval     <file.pkl> [-f <format>]    # eval + render (default: pcf)
mpkl test     <file.pkl> [--overwrite]    # walk facts: / examples:
mpkl format   <file.pkl>                  # canonical PCF re-emit
mpkl analyze  <file.pkl>                  # lint (unused locals / imports / ...)
mpkl codegen  <file.pkl> [-t moonbit]     # lower to a target-language skeleton  (pkl-mbt only)
```

Renderers via `-f` / `--format`: `pcf` (default), `json`, `yaml`, `properties`, `plist`, `textproto`, `xml`. `output { renderer = new <Renderer> { ... } }` also drives the format from the source.

Sandbox flags: `--allowed-modules <pipe|prefixes>`, `--module-path <dir>` (repeatable), `--package-cache <dir>` (repeatable; resolves and stores `package://host/path/name@version#/file.pkl` under `<dir>/path/name@version/package/file.pkl`; when omitted the CLI uses `$PKL_MBT_PACKAGE_CACHE`, `$XDG_CACHE_HOME/pkl-mbt/package-2`, or `$HOME/.cache/pkl-mbt/package-2`), `-p NAME=VALUE` (populates `read("prop:NAME")`).

## pkl-mbt specific

These don't exist in Apple Pkl:

- **`mpkl codegen <file.pkl> [-t <target>]`** — lowers a Pkl module to a target-language skeleton. Today only `moonbit` is wired; the `@pkl.CodegenTarget` enum + `@pkl.codegen(program, target)` dispatcher keep the API shape stable when other targets (Java / Kotlin / Swift / Go / TypeScript) land.
- **`mpkl analyze`** — lint pass over the parsed module (unused locals / imports / class properties / module-level shadowing).
- **Library entrypoint** (`@pkl`) — pure-MoonBit, no IO / async, builds clean on all four MoonBit targets. Apple's `pkl` ships as a JVM-backed CLI.

## Status

The parser, evaluator, typechecker, package/project loading, and advertised renderers are passing the current release test gate. Jsonnet renderer parity is intentionally left for the next pass; see [TODO.md](TODO.md) for the remaining upstream fixture inventory and release notes.

## Benchmarks vs Apple Pkl

`scripts/bench-vs-pkl.sh` (hyperfine, `--shell=none`, warmup 5 / runs 25, parity-guarded by a pre-bench `diff` against `pkl eval`) on macOS arm64. Both binaries are native AOT — Apple Pkl 0.31.1 native, `mpkl` `moon build --release --target native`. Lower ratio = mpkl faster.

| fixture | mpkl mean | pkl mean | mpkl / pkl |
| --- | ---: | ---: | ---: |
| `cli.pkl` (micro) | 4.5 ms | 9.0 ms | **0.50×** |
| `cli_amends_base_merge.pkl` | 5.1 ms | 9.5 ms | **0.54×** |
| `cli_map_value.pkl` | 4.6 ms | 8.4 ms | **0.55×** |
| `cli_set_value.pkl` | 5.0 ms | 9.4 ms | **0.54×** |
| `cli_int_seq_value.pkl` | 4.9 ms | 8.2 ms | **0.59×** |
| upstream `basic/int.pkl` | 6.7 ms | 9.7 ms | **0.69×** |
| upstream `basic/float.pkl` | 7.5 ms | 8.7 ms | **0.86×** |
| upstream `basic/string.pkl` | 6.4 ms | 10.1 ms | **0.63×** |
| upstream `basic/as.pkl` | 7.5 ms | 10.3 ms | **0.73×** |
| upstream `basic/is.pkl` | 7.1 ms | 9.7 ms | **0.74×** |
| upstream `basic/new.pkl` | 8.0 ms | 11.4 ms | **0.70×** |
| upstream `basic/rawString.pkl` | 5.4 ms | 8.7 ms | **0.62×** |
| `pkspec/Test.pkl` (1643 lines, 49 classes) | 22.2 ms | 10.3 ms | 2.17× |

12 of 13 fixtures have `mpkl` faster than `pkl`. The outlier (`pkspec/Test.pkl`) hits the per-merge `find_member_exact` String-equality tail that the eval interpreter pays once per class-default property; Apple Pkl's native AOT covers it more cheaply.

On larger synthetic workloads the gap widens in mpkl's favour as the class-default memoisation amortises:

| fixture | mpkl | pkl | ratio |
| --- | ---: | ---: | ---: |
| 200 Group × 3 Item Listing | 23 ms | 211 ms | mpkl **9× faster** |
| 1000 Group × 3 Item Listing | 39 ms | 113 ms | mpkl **2.9× faster** |
| `apple-pkl/stdlib/base.pkl` (eval as user module, ~150 classes) | 62 ms | — | (no fair pkl comparison — stdlib) |

See [`benchmarks/refactor-2026-05-22.md`](benchmarks/refactor-2026-05-22.md) for the full session retro: 26 commits, baseline `pkspec/Test.pkl` was 830 ms vs the current 22 ms (38×), and `apple-pkl/stdlib/base.pkl` went from a JS-engine stack overflow to 62 ms native.

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
