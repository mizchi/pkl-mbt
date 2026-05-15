# pkl-mbt

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
- constrained `Int(isBetween(...))` annotations for top-level and object member values
- constrained function/lambda parameter annotations at direct call and runtime callable boundaries
- constrained callable signature metadata through simple aliases
- constrained callable metadata through simple higher-order calls
- constrained class method parameter annotations
- constrained typealias metadata for top-level values and callable parameter typechecking
- constrained typealias object member annotations during evaluation
- additional numeric constraints: `isPositive`, `isGreaterThan`, and `isLessThan`
- multiple numeric constraints in a single annotation
- negated numeric constraints such as `!isPositive`
- user-defined numeric constraint factories for plain `function` declarations such as `function above(n) = (x) -> x > n`
- modifier-qualified function declarations such as `const function above(n) = (x) -> x > n`
- constrained class property annotations for typed object override values
- constrained class property default values
- native CLI commands: `parse`, `check`, and `eval`
- common string escape decoding/rendering for `\n`, `\t`, `\r`, `\"`, and `\\`
- ripple-backed `AnalysisSession` for source-driven typechecking
- pkspec contracts for the implemented behavior
- selected compatibility smoke checks against the `apple/pkl` submodule
- parse-only compatibility with the upstream `LanguageSnippetTests` parser corpus
- pkfire task graph for local CI

## Current Completion Estimate

As of the `PKL-059` spec slice, this project has 59 implemented pkspec scenarios. The next tracked slice is `PKL-060`, which targets the upstream constraint fixture flow using `pkl:test.catch`.

These are engineering estimates, not formal coverage numbers:

| Area | Estimate | Notes |
| --- | ---: | --- |
| Parser | 60-70% | The upstream parser snippet corpus is accepted in parse-only mode, and modifier-qualified function declarations such as `const function` are preserved as function declarations. Some constructs are still tolerant parse output or reduced to unsupported expression placeholders instead of full semantic AST coverage. |
| Interpreter | 35-45% | Arithmetic, objects, imports, module amends/extends, collections, class defaults/inheritance, method calls, direct function/lambda calls, callable runtime values, simple constrained value annotations, constrained callable arguments, constrained method arguments, constrained typealias values/members, selected numeric constraints, multiple constraint lists, negated constraints, plain-function user-defined numeric constraint factories, constrained class property override values, and constrained class property defaults work. Broad stdlib behavior, generators, renderers, the full constraint system, and many external functions are still incomplete. |
| Typechecker | 40-50% | Primitive, nullable, generic collection, union, narrowing, call, typed object, class inheritance, imported class, constrained annotation base types, selected numeric predicate checks, multiple constraint lists, negated constraints, direct constrained function/lambda arguments, constrained callable aliases, simple higher-order constrained callable flow, constrained method arguments, constrained typealias metadata, plain-function user-defined numeric constraint factories, constrained class property values/defaults, and class method body checks exist. Type parameters, stdlib types, `pkl:test` helpers, and deeper module/class semantics are still incomplete. |

Overall, this is roughly 40%+ complete as a pure MoonBit Pkl core, or closer to the 30% range if measured as a replacement for Apple Pkl compatibility.

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

This is not a full Pkl implementation yet. The next compatibility work is `PKL-060` upstream constraint fixture catch flow, followed by broader Pkl type/stdlib coverage and class/object semantics.
