# pkl-mbt

Pure MoonBit parser, typechecker, and evaluator for Apple's [Pkl](https://pkl-lang.org/) language. Ships as both a CLI (`mpkl`) and a library (`mizchi/pkl`).

**Compatibility policy**: behaviour follows [Apple Pkl](https://pkl-lang.org/) unless listed under [Not supported](#not-supported) / [Partially supported](#partially-supported) below. Anything else that diverges from upstream is a bug — please file an issue with the source snippet and Apple Pkl's output for comparison.

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
mpkl codegen  <file.pkl>                  # lower to MoonBit struct skeleton  (pkl-mbt only)
mpkl stdlib                               # probe stdlib coverage (pkl-mbt only)
```

Renderers via `-f` / `--format`: `pcf` (default), `json`, `yaml`, `properties`, `plist`. `output { renderer = new <Renderer> { ... } }` also drives the format from the source.

Sandbox flags: `--allowed-modules <pipe|prefixes>`, `--module-path <dir>` (repeatable), `-p NAME=VALUE` (populates `read("prop:NAME")`).

## Not supported

These slices are intentionally parked — `specs/Roadmap.pkl`'s `deferredEntries` listing carries the rationale.

| Slice | Workaround |
| --- | --- |
| LSP server | Apple's `pkl-lsp`. |
| `mpkl repl` (interactive REPL) | Wrap `eval` in a shell loop. |
| `mpkl doc` / pkldoc generation | Upstream `pkldoc`. |
| XML renderer (`-f xml` / `xml.Renderer`) | `pkl eval -f xml` upstream. Type surface is wired (typecheck OK). |
| Protobuf renderer | `pkl eval -f protobuf` upstream. Type surface is wired. |
| Renderer `converters { ... }` machinery | `pkl eval` upstream. |
| `package://` zipball download + unpack | `pkl download-package` + `--module-path`. URI parse + metadata probe + zipball-URL extraction land in-process (PKL-129b1); the actual DEFLATE+SHA-256+cache loop is the deferred part. |

## Partially supported

- **`IntSeq` equality** — structural `derive(Eq)` only; Apple Pkl's empty-sequence-equality and step-aware element-set equality stay a follow-up.
- **`pkl:reflect`** — class / module introspection (`.properties` / `.methods` / `.supertype` / `.classes` / `.isSubclassOf`) is wired (PKL-143), but factories still take a string identifier rather than a real `ClassValue` round-trip.
- **`pkl:platform`** — deterministic stub values (`stub-os` / `stub-arch`) instead of host-detected.
- **`pkl:test.catch`** — only the throw branch (returns the message); the no-throw branch evaluates the lambda as if `catch` wasn't there.
- **`pkl:json` / `pkl:yaml` / `pkl:xml` / `pkl:protobuf`** — type surface only (Parser / Renderer class shells instantiable); actual parsing / rendering bodies aren't wired.

Run `mpkl stdlib` to verify the current state — the probe table evaluates one minimal fixture per documented capability and prints `[PASS]` / `[FAIL]` per row, exiting non-zero on regression.

## pkl-mbt specific

These don't exist in Apple Pkl:

- **`mpkl codegen <file.pkl>`** — lowers a Pkl module to a MoonBit `pub(all) struct` / `pub typealias` skeleton so embedders can round-trip schemas through both type systems.
- **`mpkl stdlib`** — runs the in-process probe table that verifies each documented stdlib surface area against a minimal fixture.
- **`mpkl analyze`** — lint pass over the parsed module (unused locals / imports / class properties / module-level shadowing).
- **Library entrypoint** (`@pkl`) — pure-MoonBit, no IO / async, builds clean on all four MoonBit targets. Apple's `pkl` ships as a JVM-backed CLI.

## Upstream compatibility

- **Parser corpus**: 802 / 802 LanguageSnippetTests fixtures (parse-only)
- **Eval gold-match**: 32 PCF + 1 JSON + 1 plist fixtures byte-for-byte against upstream
- **Diagnostic wording**: first-line messages aligned with Apple Pkl (`Cannot find type \`X\`.`, `Cannot find property \`x\`.`, `Cannot find module \`...\`.`)

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

CI (`.github/workflows/ci.yml`) runs the same gate on every push / PR. 146 implemented pkspec scenarios; see `SPEC.md` for the full rendered spec.
