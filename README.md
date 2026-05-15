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
- `pkl:test.catch` support for the upstream `classes/constraints8.pkl` fixture flow
- simple scalar closure captures for returned lambdas and callable values
- non-scalar closure captures for object and callable values
- runtime return annotation validation for function and lambda calls
- runtime return annotation validation for class method calls
- runtime constrained return annotation validation, including user-defined numeric predicate factories
- runtime user-defined numeric predicate factory enforcement for callable and class method parameter annotations
- typecheck literal-body callable return validation for built-in and user-defined constrained return annotations
- runtime typealias resolution for callable and class method return annotations
- PCF renderer for Int, Boolean, String, and Null primitives (round-trips through the parser, matches upstream `parens.pkl` / `import1.pkl` byte-for-byte)
- PCF renderer for nested objects, listings, and mappings (2-space indent, type-tag-free `new { ... }` wrappers, matches the `basic` / `modules` / `classes` upstream gold output)
- JSON renderer behind `eval -f json` (`--format json` accepted as well), matching `pkl eval -f json` projection rules (Mapping keys coerced to strings, control-character escapes, two-space indent)
- YAML renderer behind `eval -f yaml`, emitting Apple Pkl's block-style projection (block sequences at the parent column, block mappings indented two spaces, empties as `[]` / `{}`, plain / single-quoted / double-quoted string selection)
- Java Properties renderer behind `eval -f properties`, matching `pkl eval -f properties` (nested objects flatten to dotted keys, listings emit as compact JSON-style values, null leaves omitted, property-style escaping for `=` / `:` / ` ` / `!` / `#` / `\\` in both keys and values)
- native CLI commands: `parse`, `check`, and `eval`
- common string escape decoding/rendering for `\n`, `\t`, `\r`, `\"`, and `\\`
- ripple-backed `AnalysisSession` for source-driven typechecking
- pkspec contracts for the implemented behavior
- selected compatibility smoke checks against the `apple/pkl` submodule
- parse-only compatibility with the upstream `LanguageSnippetTests` parser corpus
- pkfire task graph for local CI

## Current Completion Estimate

As of the `PKL-074` spec slice, this project has 73 implemented pkspec scenarios and a 24-entry roadmap of draft slices in `specs/Roadmap.pkl`. The next tracked slice is `PKL-075`, which exposes `pkl:base` Listing operations (length, map, filter, fold, etc.) against the implemented Pkl core. The constraint round-off task `PKL-069` is kept in the roadmap as a draft.

These are engineering estimates, not formal coverage numbers:

| Area | Estimate | Notes |
| --- | ---: | --- |
| Parser | 60-70% | The upstream parser snippet corpus is accepted in parse-only mode, and modifier-qualified function declarations such as `const function` are preserved as function declarations. Some constructs are still tolerant parse output or reduced to unsupported expression placeholders instead of full semantic AST coverage. |
| Interpreter | 40-50% | Arithmetic, objects, imports, module amends/extends, collections, class defaults/inheritance, method calls, direct function/lambda calls, callable runtime values, function/lambda/method return validation including built-in and user-defined constrained return predicates, callable and method argument validation including built-in and user-defined constrained predicates, typealias resolution for callable return annotations, lexical closure captures for scalar/object/callable values, simple constrained value annotations, constrained callable arguments, constrained method arguments, constrained typealias values/members, selected numeric constraints, multiple constraint lists, negated constraints, plain-function user-defined numeric constraint factories, constrained class property values/defaults, and the upstream `classes/constraints8.pkl` catch flow work. Broad stdlib behavior, generators, renderers, non-numeric constraints (String / Float / Boolean / collection element), and many external functions are still incomplete. |
| Typechecker | 42-52% | Primitive, nullable, generic collection, union, narrowing, call, typed object, class inheritance, imported class, constrained annotation base types, selected numeric predicate checks, multiple constraint lists, negated constraints, direct constrained function/lambda arguments, constrained callable aliases, simple higher-order constrained callable flow, constrained method arguments, constrained typealias metadata, plain-function user-defined numeric constraint factories, constrained class property values/defaults, callable and class method literal-body return predicate checks (built-in and user-defined), and class method body checks exist. Type parameters, broader stdlib types, non-numeric constraint predicates, and deeper module/class semantics are still incomplete. |
| Stdlib & rendering | 15-20% | Only `pkl:math.maxInt32` and the `pkl:test.catch` flow are wired on the stdlib side. The PCF renderer is byte-for-byte against upstream gold for the implemented language slice, `eval -f json` emits Apple Pkl's `pkl eval -f json` shape, `eval -f yaml` emits Apple Pkl's `pkl eval -f yaml` block-style shape (modulo block scalars for multiline strings, which still emit as double-quoted), and `eval -f properties` emits the Java Properties shape (dotted flatten, JSON-encoded listings, null leaves omitted). Plist renderer, generators, `pkl:base` extensions, `pkl:reflect`, regex / duration / bytes, and the rest of the Apple Pkl stdlib surface are unimplemented. This is still the largest remaining gap. |

Overall, this is roughly 40%+ complete as a pure MoonBit Pkl core (parser + typechecker + interpreter for the implemented language slice), or closer to the 25-30% range if measured as a replacement for Apple Pkl compatibility — the constraint system is now thick on the language-semantics side, but the stdlib / renderer / generator surface is largely untouched.

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
├── specs/             # project pkspec scenarios (Spec.pkl) + roadmap (Roadmap.pkl)
├── pkspec/            # vendored pkspec authoring schemas
├── third_party/        # upstream apple/pkl submodule
├── scripts/            # local test adapters
├── Taskfile.pkl       # pkfire task graph
└── SPEC.md            # rendered spec document
```

## Scope

This is not a full Pkl implementation yet. With the four-renderer surface (PCF / JSON / YAML / Properties) in place, the next compatibility work pivots to `PKL-075` `pkl:base` Listing operations (length, map, filter, fold, etc.); the full draft roadmap lives in `specs/Roadmap.pkl`.
