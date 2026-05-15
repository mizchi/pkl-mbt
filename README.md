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
- `pkl:base` Listing operations: properties `length`, `isEmpty`, `first`, `last`, `distinct` and methods `contains(x)`, `reverse()`, `take(n)`, `drop(n)`, `join(sep)`, `map(fn)`, `filter(p)`, `fold(init, op)`, including chained higher-order calls (`xs.filter(p).map(f).fold(0, g)`)
- `pkl:base` Mapping operations: properties `length`, `isEmpty`, `keys`, `values` (projected as `Listing<K>` / `Listing<V>` until a real `Set` value lands) and methods `containsKey(k)`, `getOrNull(k)`, `fold(init, (acc, key, value) -> ...)`
- `pkl:base` String operations: properties `length`, `isEmpty` and methods `toUpperCase()`, `toLowerCase()`, `contains(s)`, `startsWith(p)`, `endsWith(s)`, `indexOf(s)` (returns `-1` for missing), `replaceAll(old, new)`, `replaceFirst(old, new)`, `take(n)`, `drop(n)`, `split(sep)` → Listing, `padStart(width, padStr)`, `padEnd(width, padStr)`
- `pkl:base` Int operations: properties `abs`, `isEven`, `isOdd` and methods `toString()`, `toString(radix)` (radix 2..36), `toChar()` (Unicode code point → single-char String)
- `pkl:math` module: Int range constants `maxInt32`, `minInt32`, `maxInt`, `minInt` plus Int-side helpers `abs(x)`, `min(a, b)`, `max(a, b)` — reachable via `import "pkl:math" as math`
- `pkl:reflect` minimal stub: builtin type mirror constants (`anyType`, `booleanType`, `intType`, `floatType`, `numberType`, `stringType`, `durationType`, `dataSizeType`, `bytesType`, `pairType`, `listType`, `setType`, `mapType`, `listingType`, `mappingType`, `objectType`, `dynamicType`, `typedType`, `moduleType`, `unknownType`, `nothingType`) as `pkl.base#<name>` placeholders plus the `Class` / `Module` / `TypeAlias` / `Property` / `DeclaredType` factory lambdas that build `reflectee` / `referent` containers from a string identifier — enough for fixtures that only read mirror constants or assert `reflect.Class(name).reflectee == name`
- `throw(message)` / `trace(value)` top-level built-ins. `throw` evaluates the message, pushes a diagnostic carrying the text verbatim, and aborts; `trace` evaluates the argument and passes it through unchanged (the stderr-stamp side of Apple Pkl's `trace` stays deferred to a follow-up slice). Both honor user shadowing (`throw = (s) -> s`) so the identifiers remain free for user-defined helpers
- `read(uri)` top-level built-in with a default-deny sandbox policy. Only the `env:` scheme is on the allow-list: `read("env:NAME")` consults the host environment via `moonbitlang/core/env.get_env_var` and returns the value as a String. All other schemes (`prop:` / `file:` / `https:` / `package:`) surface `read: scheme <s>: is not allowed by the sandbox policy`, missing env variables surface `read: env variable <NAME> is not set`, and URIs without a scheme surface `read: missing URI scheme in "<uri>"`. The `read?(uri)` null-returning variant is deferred to a parser-extension slice. `read` honors user shadowing
- Generic class declarations such as `class Box<T> { value: T }` and `class Pair<A, B> { first: A; second: B }`. The parser captures the `<T1, T2, ...>` list on `ClassDecl.type_parameters`, and the typechecker injects each parameter into a class-scoped `type_env` as a binding to `UnknownType` so body uses of `T` route through the existing tolerated-annotation path instead of failing. Instantiation-time T-binding (propagating `Int` through `b.value` after `new Box { value = 5 }`) stays deferred to a follow-up
- Float numerics across lexer / parser / evaluator / typechecker / four renderers. `<digits>.<digits>` lexes as a Float token (Duration / DataSize `Int.<unit>` shorthand stays Int), `FloatLiteral(Double)` AST node, `FloatValue(Double)` value variant, sibling `FloatType` in the type system, `Number` annotation expands to `UnionType([IntType, FloatType])`. Arithmetic widens automatically: `Int + Float` → Float, mixed comparisons admit any Int / Float pair, and `Int / Int` widens to Float to match Apple Pkl's `5 / 2 == 2.5`. `IntDivide` / `Modulo` / `Power` stay Int-only. All renderers emit Float via `render_float_text` which appends `.0` for integral Doubles so the wire form round-trips as Float, not Int. Constraint cascade extends to `Float(...)` / `Number(...)` annotations: `Float(isPositive)`, `Float(isBetween(0, 10))`, `Number(isPositive)`, and the negated / custom variants fire on Float values via a `pkl_constraint_predicate_accepts_float` evaluator that widens Int thresholds to Double for the comparison
- null-coalescing operator `a ?? b` (right-associative, short-circuit) and `let (name = value) body` expression form (single scoped binding desugared at parse time into a single-parameter lambda application)
- object-body `when (cond) { ... } else { ... }` conditionals that splice the picked branch's members into the surrounding object (the `else` branch is optional)
- object-body `for (var in source) { ... }` and `for (var1, var2 in source) { ... }` generators that iterate Listings and Mappings; per-iteration members merge with last-write-wins semantics, and `for` composes with `when` inside the body
- `hidden` and `local` object-member modifiers (and module-level `hidden`) that keep the member resolvable via `lookup_member` but skip it in every renderer (PCF / JSON / YAML / Properties)
- typealiased callable-argument annotations (e.g. `(x: Small) -> ...` with `typealias Small = Int(isBetween(0, 10))`) resolve through the alias chain at runtime so the same predicate cascade as the inline form fires
- `Duration` / `DataSize` literals from `Int.<unit>` (`ns` / `us` / `ms` / `s` / `min` / `h` / `d` for Duration; `b` / `kb` / `kib` / `mb` / `mib` / `gb` / `gib` / `tb` / `tib` / `pb` / `pib` for DataSize) with same-unit and mixed-unit `+` / `-`, all six comparison operators, `.value` / `.unit` accessors, `.toUnit(name)` conversion, and unary negation — magnitudes are Int-only (the Float gap is documented as a follow-up slice) and the PCF renderer emits `<n>.<unit>` literals that round-trip through the parser
- `Regex` values from `Regex("<pattern>")` with `.pattern` accessor and `.matches(input)` / `.find(input)` / `.findAll(input)` / `.replace(input, repl)` / `.replaceAll(input, repl)` methods backed by `moonbitlang/regexp`; the PCF renderer round-trips `RegexValue` as `Regex("<escaped-pattern>")` while JSON / YAML / Properties project the pattern as a plain string
- `Bytes` values from `Bytes(<Listing of Int>)` (each element 0..=255) and `Bytes.fromBase64("...")`, with `.length` / `.base64` properties, `.getOrNull(i)` / `.toList()` methods, and a `String.toBytes()` UTF-8 encoder; PCF round-trips through the Listing constructor and JSON / YAML / Properties project the base64 string
- `String(...)` constraint predicates with three documented shapes: length comparisons (`length > 0`, `>=` / `<` / `<=` / `==` / `!=`), `length.NAME(...)` method calls reusing the Int predicate grammar (`length.isBetween(1, 64)`, `length.isPositive`, `length.isGreaterThan(N)`, `length.isLessThan(N)`), and full-input regex matches (`matches(Regex("<pattern>"))`); `!`-prefix negation wraps any predicate, and the same cascade fires at both typecheck (String literals) and runtime (any String value)
- Collection element constraint propagation: `Listing<T>` and `Mapping<K, V>` annotations recurse through the constrained-type cascade so per-element predicates fire (`Listing<Int(isPositive)>`, `Mapping<String(length > 0), Int(isBetween(0, 9))>`); nested wrappers compose and the first rejecting element short-circuits with a diagnostic naming the failing predicate
- native CLI commands: `parse`, `check`, `eval` (the latter with `-f` / `--format pcf|json|yaml|properties` dispatch, default `pcf`), and `test` (walks `facts: Mapping<String, Listing<Boolean>>` and reports per-fact pass / fail with a trailing summary)
- common string escape decoding/rendering for `\n`, `\t`, `\r`, `\"`, and `\\`
- ripple-backed `AnalysisSession` for source-driven typechecking
- pkspec contracts for the implemented behavior
- byte-for-byte gold-match against the upstream `apple/pkl` smoke suite for 25 hand-curated `.pcf` fixtures across `basic` / `classes` / `modules` / `objects` / `types`, plus 1 `.json` gold-match (`api/jsonRenderer1.json`), gated by `scripts/upstream-smoke.sh`. The CLI extracts a top-level `output { value = ... }` envelope before rendering so JSON gold fixtures match Apple Pkl's `output.value`-on-renderer behavior
- parse-only compatibility with the upstream `LanguageSnippetTests` parser corpus
- pkfire task graph for local CI

## Current Completion Estimate

As of the `PKL-089` spec slice, this project has 97 implemented pkspec scenarios and a 1-entry roadmap of draft slices in `specs/Roadmap.pkl`. The next tracked slice is `PKL-090` (generic function type parameters), which extends the type-parameter scope from class declarations to function declarations.

These are engineering estimates, not formal coverage numbers:

| Area | Estimate | Notes |
| --- | ---: | --- |
| Parser | 60-70% | The upstream parser snippet corpus is accepted in parse-only mode, and modifier-qualified function declarations such as `const function` are preserved as function declarations. Some constructs are still tolerant parse output or reduced to unsupported expression placeholders instead of full semantic AST coverage. |
| Interpreter | 51-61% | Arithmetic, objects, imports, module amends/extends, collections, class defaults/inheritance, method calls, direct function/lambda calls, callable runtime values, function/lambda/method return validation including built-in and user-defined constrained return predicates, callable and method argument validation including built-in and user-defined constrained predicates, typealias resolution for callable return annotations, lexical closure captures for scalar/object/callable values, simple constrained value annotations, constrained callable arguments, constrained method arguments, constrained typealias values/members, selected numeric constraints, multiple constraint lists, negated constraints, plain-function user-defined numeric constraint factories, constrained class property values/defaults, the upstream `classes/constraints8.pkl` catch flow, the `pkl:base` Listing / Mapping / String / Int builtins, String constraint predicates (`length` comparisons, `length.isBetween` / `.isPositive` / `.isGreaterThan` / `.isLessThan`, `matches(Regex(...))`), and collection element constraint propagation through `Listing<T>` / `Mapping<K, V>` all work. Generators, Float constraint predicates, Float numerics, and many external functions are still incomplete. |
| Typechecker | 46-56% | Primitive, nullable, generic collection, union, narrowing, call, typed object, class inheritance, imported class, constrained annotation base types, selected numeric predicate checks, multiple constraint lists, negated constraints, direct constrained function/lambda arguments, constrained callable aliases, simple higher-order constrained callable flow, constrained method arguments, constrained typealias metadata, plain-function user-defined numeric constraint factories, constrained class property values/defaults, callable and class method literal-body return predicate checks (built-in and user-defined), class method body checks, String literal rejection against `String(length ...)` / `String(matches(Regex(...)))` constraints, and `has_supported_constraint` recursion into `Listing<T>` / `Mapping<K, V>` wrappers all work. Type parameters, broader stdlib types, Float constraint predicates, and deeper module/class semantics are still incomplete. |
| Stdlib & rendering | 33-38% | `pkl:math` (Int constants `maxInt32`/`minInt32`/`maxInt`/`minInt` and helpers `abs`/`min`/`max`), the `pkl:test.catch` flow plus the new `pkl test` CLI subcommand for `facts`, the minimal `pkl:reflect` stub (mirror constants + `Class` / `Module` / `TypeAlias` / `Property` / `DeclaredType` factories returning `reflectee` containers), the core `pkl:base` Listing / Mapping / String / Int builtins, the `Duration` / `DataSize` value types (construction from `Int.<unit>`, `+` / `-` / comparison, `.value` / `.unit` / `.toUnit(name)`), `Regex` (construction via `Regex("...")`, `.pattern` / `.matches` / `.find` / `.findAll` / `.replace` / `.replaceAll`), and `Bytes` (`Bytes(<Listing>)` / `Bytes.fromBase64(...)`, `.length` / `.base64` / `.getOrNull(i)` / `.toList()`, plus `String.toBytes()` for UTF-8 encoding) are wired on the stdlib side. The PCF renderer is byte-for-byte against upstream gold for the implemented language slice, `eval -f json` / `eval -f yaml` / `eval -f properties` all match Apple Pkl's projection rules (modulo YAML block scalars for multiline strings). Plist renderer, generators, Float numerics, Float-bearing `pkl:math` (sqrt/pow/log/etc.), the rest of `pkl:reflect` (`isSubclassOf`, real `ClassValue` round-trip, runtime member introspection), Set, Float magnitudes on Duration / DataSize, and the rest of the Apple Pkl stdlib surface are unimplemented. This is still the largest remaining gap. |

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

This is not a full Pkl implementation yet. With the four-renderer surface (PCF / JSON / YAML / Properties), the core `pkl:base` Listing / Mapping / String / Int builtins, the Int-side `pkl:math` constants and helpers, the minimal `pkl:reflect` mirror-constant + factory stub, the value-side `throw` / `trace` / `read` (sandbox-bounded) built-ins, Float numerics + the `Float(...)` / `Number(...)` constraint cascade, the `??` / `let (...)` expression forms, the object-body `when` / `for` generators, `hidden` / `local` member filtering, typealiased argument resolution, the Int-magnitude `Duration` / `DataSize` literals, the `Regex` literal + method surface, the String constraint predicate cascade, collection element constraint propagation, the CLI `--format` long-form dispatch, the CLI `test` subcommand for `facts`, the `Bytes` literal + base64 / UTF-8 surface, the broader upstream fixture sweep (25 PCF byte-for-byte gold matches), and the JSON gold-diff infrastructure (with `output.value` extraction in the CLI) closed out, the remaining compatibility work pivots to the generics pair `PKL-089` / `PKL-090`; the full draft roadmap lives in `specs/Roadmap.pkl`.
