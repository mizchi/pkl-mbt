# pickle-mbt

Pure MoonBit experiments for Apple's [Pkl](https://pkl-lang.org/) language.

The current slice is intentionally small and executable:

- CST-backed expression parser using `mizchi/cst`
- interpreter for integer arithmetic and top-level `let` bindings
- initial typechecker for primitive expressions
- initial Pkl module/object syntax with object member lookup
- source-backed import clause resolution through `AnalysisSession`
- `local` module bindings and `import("...")` expressions
- explicit `new Listing { ... }` / `new Mapping { [key] = value }` collection values with subscript access
- selected standard library module resolution, currently `pkl:math.maxInt32`
- object body property shorthand such as `x { y { z = 1 } }`
- primitive Pkl-style type annotations such as `name: String = "hawk"`
- native CLI commands: `parse`, `check`, and `eval`
- common string escape decoding/rendering for `\n`, `\t`, `\r`, `\"`, and `\\`
- ripple-backed `AnalysisSession` for source-driven typechecking
- pkspec contracts for the implemented behavior
- selected compatibility smoke checks against the `apple/pkl` submodule
- parse-only compatibility with the upstream `LanguageSnippetTests` parser corpus
- pkfire task graph for local CI

## Commands

```bash
pkf run ci
pkf run release-check
pkf run spec
moon run cmd/main --target native -- eval fixtures/cli.pkl
```

Useful direct commands:

```bash
moon test --target js
moon check --deny-warn --target js
pkspec exec -f specs/Test.pkl
pkspec spec --check specs/Spec.pkl specs/Test.pkl
```

The upstream Pkl repository is tracked as a git submodule:

```bash
git submodule update --init --recursive
./scripts/upstream-smoke.sh
./scripts/upstream-parse-suite.sh
```

## Layout

```text
.
├── *.mbt              # parser, AST, evaluator, typechecker, ripple analysis
├── specs/             # project pkspec scenarios and executable checks
├── pkspec/            # vendored pkspec authoring schemas
├── third_party/        # upstream apple/pkl submodule
├── scripts/            # local test adapters
├── Taskfile.pkl       # pkfire task graph
└── SPEC.md            # rendered spec document
```

## Scope

This is not a full Pkl implementation yet. The next compatibility work is broader Pkl type/stdlib coverage and class/object semantics.
