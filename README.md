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
