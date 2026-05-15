# Test SPEC

104 tests across 2 module(s) — 97 pending, 7 active

## `specs/`

### `Spec.pkl`

- [ ] **Bytes literals and conversions** (minor) [draft] — verifies: PKL-083 — tags: stdlib, bytes
  > `Bytes` values created via `Bytes(...)` or string conversions, plus length, slice, and base64 encoding / decoding.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - body: _not yet implemented_

- [ ] **CLI --format flag for eval** (minor) [draft] — verifies: PKL-094 — tags: cli, renderer
  > `moon run cmd/main eval --format json|yaml|pcf|properties path.pkl` dispatches to the matching renderer; the default stays pcf.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-072, PKL-073, PKL-074
  - body: _not yet implemented_

- [ ] **CLI test runner integrates pkl:test** (minor) [draft] — verifies: PKL-095 — tags: cli, pkl-test
  > `moon run cmd/main test path.pkl` runs the `pkl:test` cases declared in the module, reports pass / fail counts, and exits non-zero on any failure.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-058
  - body: _not yet implemented_

- [ ] **Duration and DataSize literals and arithmetic** (minor) [draft] — verifies: PKL-082 — tags: stdlib, duration, datasize
  > Numeric literals with `.h` / `.min` / `.s` / `.ms` / `.us` / `.ns` produce `Duration`; `.kb` / `.mb` / `.gb` / `.kib` / `.mib` / `.gib` produce `DataSize`. Both support addition, subtraction, comparison, and conversion to a normalized base unit.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - body: _not yet implemented_

- [ ] **Float constraint predicates** (minor) [draft] — verifies: PKL-092 — tags: constraint, float
  > Numeric constraint predicates (`isPositive`, `isBetween`, etc.) accept Float values alongside Int, including mixed Int / Float comparisons inside user-defined factories.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-078
  - body: _not yet implemented_

- [ ] **Listing and Mapping element constraint propagation** [draft] — verifies: PKL-093 — tags: constraint, collection
  > Constraint annotations on Listing / Mapping element types (`Listing<Int(isPositive)>`, `Mapping<String, String(length > 0)>`) propagate to each element at typecheck and runtime.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-091, PKL-075
  - body: _not yet implemented_

- [ ] **Regex literal and Regex methods** [draft] — verifies: PKL-081 — tags: stdlib, regex, constraint
  > `Regex(#"..."#)` literal, plus `matches`, `find`, `findAll`, `replace`, and `replaceAll`. Regex-based String constraints (e.g. `String(matches(Regex(...)))`) become typecheckable and runtime-enforceable.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **String constraint predicates** [draft] — verifies: PKL-091 — tags: constraint, string
  > `String(length > 0)`, `String(length.isBetween(1, 64))`, and `String(matches(Regex(...)))` are recognized by both the typechecker and the runtime, mirroring the existing numeric constraint cascade.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077, PKL-081
  - body: _not yet implemented_

- [ ] **allow Pkl class property defaults to satisfy missing members** — verifies: PKL-035 — tags: typechecker
  > Assignments to declared class types accept object literals that omit class properties with defaults, while still requiring properties without annotations or defaults.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-034
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **diff evaluation output against apple/pkl gold files** [draft] — verifies: PKL-097 — tags: compatibility, upstream, renderer
  > For each upstream fixture that evaluates, byte-diff the PCF / JSON output against the `expected` gold files in `LanguageSnippetTests/output`. Mismatches fail the smoke script.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-071, PKL-072, PKL-096
  - body: _not yet implemented_

- [ ] **enforce Pkl constrained function parameter annotations** — verifies: PKL-047 — tags: typechecker, evaluator
  > Function and lambda calls validate constrained parameter annotations such as `x: Int(isBetween(0, 10))`, rejecting invalid arguments at call boundaries in the typechecker and evaluator.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-046, PKL-023, PKL-044
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **enforce Pkl constrained method parameter annotations** — verifies: PKL-050 — tags: typechecker, evaluator
  > Class method calls validate constrained method parameter annotations in the typechecker and evaluator, so typed object method calls reject invalid constrained arguments.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-049, PKL-041, PKL-046
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl callable return annotations** — verifies: PKL-063 — tags: evaluator, callable
  > Function and lambda calls validate declared return annotations at runtime so callable values reject bodies that return incompatible values.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-062, PKL-044, PKL-023
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl class method invocations** — verifies: PKL-041 — tags: evaluator, typechecker
  > Typed object method calls dispatch to class method bodies with receiver and argument bindings, while method declarations remain separate from object value members.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040, PKL-022, PKL-037
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl class method return annotations** — verifies: PKL-064 — tags: evaluator, class
  > Class method calls validate declared return annotations at runtime so method bodies reject incompatible returned values.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-063, PKL-036, PKL-040
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl constrained class property annotations** — verifies: PKL-058 — tags: evaluator, typechecker
  > Typed object values enforce constrained class property annotations, including user-defined numeric constraint factories from top-level function declarations.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-057, PKL-056, PKL-035
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl constrained class property default values** — verifies: PKL-059 — tags: evaluator, typechecker
  > Class property default expressions enforce their constrained annotations during typechecking and evaluation, including user-defined numeric constraint factories.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-058, PKL-057, PKL-056
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl constrained type annotation predicates** — verifies: PKL-046 — tags: typechecker, evaluator
  > Constrained annotations evaluate supported predicate expressions against the annotated value so contracts such as `Int(isBetween(0, 10))` can reject out-of-range values.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-045, PKL-041, PKL-044
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl constrained typealias object member annotations** — verifies: PKL-052 — tags: evaluator, typechecker
  > Object member annotations that use constrained type aliases preserve alias metadata during evaluation, so nested object values reject invalid constrained members.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-051, PKL-046, PKL-017
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl function declarations lambdas and calls** — verifies: PKL-042 — tags: evaluator
  > The evaluator can call top-level function declarations and lambda values with argument bindings, aligning runtime behavior with the callable AST and typechecker support.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-022, PKL-023, PKL-041
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl typed object class defaults** — verifies: PKL-037 — tags: evaluator
  > Typed object expressions such as `new Bird { ... }` materialize class property defaults during evaluation while preserving explicitly supplied object members as overrides.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-036, PKL-035
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate Pkl user-defined type constraint functions** — verifies: PKL-056 — tags: typechecker, evaluator
  > Type constraints can call user-defined predicate factories such as `isGreaterThan(5)`, so supported function declarations can participate in annotation checking instead of being matched only by built-in names.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-055, PKL-044, PKL-046
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate arithmetic and let bindings** (critical) — verifies: PKL-002
  > The interpreter evaluates integer arithmetic with precedence and resolves top-level let bindings.
  - contributes to: GOAL-PKL-PURE
  - body: _not yet implemented_

- [ ] **evaluate broader upstream Pkl fixtures** [draft] — verifies: PKL-096 — tags: compatibility, upstream
  > Expand `scripts/upstream-smoke.sh` from the current ~10 fixtures to the bulk of `LanguageSnippetTests/input/basic`, accepting only those that exercise implemented language features and gating new failures via the script.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075, PKL-077, PKL-085
  - body: _not yet implemented_

- [ ] **evaluate constrained Pkl callable return annotations** — verifies: PKL-065 — tags: evaluator, callable, typechecker
  > Function, lambda, and class method calls enforce constrained return annotations, including user-defined numeric predicate factories.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-064, PKL-063, PKL-056
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate non-scalar Pkl callable closure captures** — verifies: PKL-062 — tags: evaluator, callable
  > Function and lambda values preserve captured object and callable bindings instead of only scalar literals.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-061, PKL-044
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate object body for-generators** [draft] — verifies: PKL-085 — tags: evaluator, object
  > `for (k, v in source) { ... }` inside an object body expands into repeated members, with iteration over Listing / Mapping / Set sources matching Apple Pkl semantics.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075
  - body: _not yet implemented_

- [ ] **evaluate object body when-conditionals** [draft] — verifies: PKL-086 — tags: evaluator, object
  > `when (cond) { ... } else { ... }` inside an object body conditionally adds members at evaluation time, matching Apple Pkl semantics for both inline and standalone forms.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - body: _not yet implemented_

- [ ] **evaluate simple Pkl callable closure captures** — verifies: PKL-061 — tags: evaluator, callable
  > Function and lambda values preserve simple scalar lexical bindings so returned lambdas and higher-order callables can evaluate variables from their defining scope.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-044, PKL-060
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate typealiased Pkl callable argument annotations** [draft] — verifies: PKL-069 — tags: evaluator, callable, typealias
  > Function, lambda, and class method calls resolve typealiased parameter annotations through the alias chain at runtime so built-in and user-defined constrained predicates fire when the constraint is declared via a typealias such as typealias Small = Int(isBetween(0, 10)).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-066, PKL-068
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate typealiased Pkl callable return annotations** — verifies: PKL-068 — tags: evaluator, callable, typealias
  > Function, lambda, and class method return annotations whose declared type name is a typealias resolve through the alias chain at runtime, accepting alias targets such as Int when the alias is declared as typealias Small = Int.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-065, PKL-039
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate upstream Pkl constraint fixture catch flow** — verifies: PKL-060 — tags: evaluator, stdlib, upstream
  > The evaluator supports enough of `pkl:test.catch` and lazy lambda invocation to run upstream constraint fixtures that capture failed constrained object construction.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-059, PKL-058, PKL-011
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate user-defined constrained Pkl callable arguments** — verifies: PKL-066 — tags: evaluator, callable
  > Function, lambda, and class method calls enforce user-defined numeric predicate factories on parameter annotations at runtime, matching the existing built-in numeric predicate behavior.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-065, PKL-056
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **expand pkl:math beyond maxInt32** (minor) [draft] — verifies: PKL-079 — tags: stdlib, pkl-math
  > `pkl:math` exposes min, max, abs, sqrt, pow, log, exp, ceil, floor, round, and the maxInt / minInt / maxFloat constants matching Apple Pkl.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-007
  - body: _not yet implemented_

- [ ] **expose pkl:base Int operations** (minor) [draft] — verifies: PKL-078 — tags: stdlib, pkl-base, numeric, next
  > Int instance methods abs, isEven, isOdd, toFloat, toString, toString(radix), and toChar evaluate, along with the matching Float-side projections.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - body: _not yet implemented_

- [ ] **expose pkl:base Listing operations** — verifies: PKL-075 — tags: stdlib, pkl-base, listing
  > Listing properties (`length`, `isEmpty`, `first`, `last`, `distinct`) and methods (`contains(x)`, `reverse()`, `take(n)`, `drop(n)`, `join(sep)`, `map(fn)`, `filter(p)`, `fold(init, op)`) dispatch against `ListingValue` receivers in the evaluator. Property-style access (`xs.length`) is handled in the `MemberAccess` arm; method calls (`xs.contains(1)`) are handled in the `CallExpr(MemberAccess(...), args)` arm before falling through to the regular callable path. Higher-order methods (`map` / `filter` / `fold`) accept a `FunctionValue` callback and invoke it per element via a shared `apply_function_value` helper that mirrors `eval_lambda_application` for already-evaluated arguments. Chained calls (`xs.filter(p).map(f).fold(0, g)`) work because each step re-evaluates its receiver as a `ListingValue`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009, PKL-066
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **expose pkl:base Mapping operations** — verifies: PKL-076 — tags: stdlib, pkl-base, mapping
  > Mapping properties (`length`, `isEmpty`, `keys`, `values`) and methods (`containsKey(k)`, `getOrNull(k)`, `fold(init, op)`) dispatch against `MappingValue` receivers via the same `MemberAccess` / `CallExpr` interception as the Listing builtins. `keys` and `values` project to `ListingValue` in declaration order (Apple Pkl returns `Set<K>` for `keys`, but our value model has no separate Set yet — the deviation is documented in the decisions). `getOrNull(k)` returns `NullValue` when the key is missing. `fold` invokes a 3-argument callback `(acc, key, value)` per entry via the shared `apply_function_value` helper. Listing builtins continue to dispatch on Listing receivers, so `m.values.filter(...).fold(...)` pipelines through both surfaces correctly.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **expose pkl:base String operations** — verifies: PKL-077 — tags: stdlib, pkl-base, string
  > String properties (`length`, `isEmpty`) and methods (`toUpperCase()`, `toLowerCase()`, `contains(s)`, `startsWith(p)`, `endsWith(s)`, `indexOf(s)`, `replaceAll(old, new)`, `replaceFirst(old, new)`, `take(n)`, `drop(n)`, `split(sep)`, `padStart(width, padStr)`, `padEnd(width, padStr)`) dispatch against `StringValue` receivers via the same `MemberAccess` / `CallExpr` interception as the Listing / Mapping builtins. `indexOf` returns `-1` for missing substrings (matching Apple Pkl rather than returning null). `split` projects to `Listing<String>`, so `s.split(",").map(...).join(...)` pipelines through the Listing builtins. `take` and `drop` saturate at the string bounds. All operations are code-unit-based (matching Apple Pkl's Java-string-derived semantics).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-076
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **generic class declarations** [draft] — verifies: PKL-089 — tags: typechecker, generics, class
  > `class Box<T> { value: T }` declares a parameterized class; instances bind T at construction time and the typechecker propagates the binding through property and method accesses.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - body: _not yet implemented_

- [ ] **generic function type parameters** [draft] — verifies: PKL-090 — tags: typechecker, generics, callable
  > Function declarations such as `function identity<T>(x: T): T = x` accept a type parameter list; the typechecker infers the binding from the argument types at call sites.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-089
  - body: _not yet implemented_

- [ ] **hidden and local object members** [draft] — verifies: PKL-087 — tags: evaluator, renderer, object
  > Members declared `hidden ` or `local ` are visible inside expressions but absent from rendered output. The interpreter and every renderer respects this distinction.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-070
  - body: _not yet implemented_

- [ ] **infer Pkl class property default types** — verifies: PKL-034 — tags: typechecker
  > Class declarations use property default expressions as member type contracts when no explicit annotation is present, so assignments to declared class types still reject incompatible object members.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-019, PKL-022
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **inventory unsupported syntax in tolerant parser output** — verifies: PKL-016 — tags: parser
  > ParseResult exposes an unsupported_syntax coverage report with source ranges, text, and syntax kind for accepted code that still lowers to UnsupportedExpr.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-015
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **minimal pkl:reflect support** (minor) [draft] — verifies: PKL-080 — tags: stdlib, pkl-reflect
  > `pkl:reflect.Type` / `Class` / `Property` enough for the upstream `reflect.pkl` fixtures: get the runtime type of a value, list class properties, and check whether a type is a subtype of another.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **model Pkl callable runtime values** — verifies: PKL-044 — tags: evaluator
  > The evaluator represents function and lambda expressions as callable runtime values so callables can be stored, passed as arguments, and invoked beyond direct AST call sites.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-042, PKL-023
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **model Pkl class function and typealias declarations** — verifies: PKL-019 — tags: parser, typechecker
  > Program retains class, function, and typealias declarations, and the typechecker resolves declared class and typealias names in property annotations.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-016, PKL-008
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **model Pkl class method declarations** — verifies: PKL-040 — tags: parser, typechecker
  > Class bodies retain method declarations and typed object member access can resolve method signatures without treating methods as object properties.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-039, PKL-022
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **narrow nullable types through Pkl null guards** — verifies: PKL-031 — tags: typechecker
  > The typechecker narrows nullable identifiers through `x != null` and `x == null` guards so non-null branches can use the inner type without explicit coalescing.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-024, PKL-030
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **narrow union types through Pkl is guards** — verifies: PKL-029 — tags: typechecker
  > The typechecker narrows union-typed identifiers inside `if (x is T)` branches so callable bodies and property expressions can use the guarded branch type.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-027, PKL-028
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **narrow union types through compound Pkl boolean guards** — verifies: PKL-030 — tags: parser, typechecker
  > The typechecker carries `is` guard narrowing through compound Boolean conditions such as `x is Int && x > 0`, so guarded subexpressions and then branches see the narrowed type.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-029
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **null-coalescing operator and let expressions** (minor) [draft] — verifies: PKL-088 — tags: evaluator, expressions
  > The `??` operator picks the right-hand value when the left is null; `let (name = expr) body` introduces a scoped binding inside an expression.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - body: _not yet implemented_

- [ ] **parse Pkl call lambda and operator expressions** — verifies: PKL-018 — tags: parser
  > The parser lowers calls, lambdas, unary operators, comparisons, boolean operators, null-coalescing, and conditional expressions into explicit AST nodes with precedence matching Pkl.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-016
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **parse Pkl const function declarations** — verifies: PKL-057 — tags: parser, typechecker
  > Const-qualified function declarations such as `const function isGreaterThan(n) = (x) -> x > n` parse as function declarations, so upstream constraint-factory fixtures can use their original syntax.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-056, PKL-015
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **parse and evaluate Pkl collection expressions** — verifies: PKL-017 — tags: parser, evaluator, typechecker
  > The parser lowers explicit `new Listing` elements and `new Mapping` entries into AST nodes, and evaluator/typechecker support collection values plus subscript access without using UnsupportedExpr.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-013, PKL-014
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **parse arithmetic expressions** (critical) — verifies: PKL-001
  > The parser builds a CST-backed program for integer arithmetic expressions and preserves source length.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **parse upstream apple/pkl snippet corpus** (critical) — verifies: PKL-015
  > The native parser accepts every syntactically valid fixture selected by apple/pkl's ParserComparisonTest LanguageSnippetTests input corpus.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **preserve Pkl constrained callable signature metadata** — verifies: PKL-048 — tags: typechecker
  > Callable values retain constrained parameter annotations through aliases and stored callable values so the typechecker can reject invalid calls after functions are assigned to other names.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-047, PKL-044, PKL-028
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **preserve Pkl constrained typealias metadata** — verifies: PKL-051 — tags: typechecker, evaluator
  > Type aliases that target constrained annotations such as `typealias Small = Int(isBetween(0, 10))` preserve enough metadata for annotated values and callable parameters to keep enforcing the constraint.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-050, PKL-045, PKL-028
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **propagate Pkl constrained callable metadata through higher-order calls** — verifies: PKL-049 — tags: typechecker
  > The typechecker preserves constrained callable metadata when functions are passed as higher-order arguments, so downstream calls through parameters can still reject invalid constrained arguments when enough static information is available.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-048, PKL-047, PKL-044
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **provide a usable CLI** — verifies: PKL-009
  > The native command-line entrypoint can parse, typecheck, and evaluate Pkl source files.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **read trace and throw built-ins** [draft] — verifies: PKL-084 — tags: stdlib, io, diagnostics
  > Built-in `read(uri)`, `read?(uri)`, `trace(value)`, and `throw(message)`. read covers `env:` / `prop:` / `file:` URIs at minimum, trace stamps a diagnostic without affecting the value, and throw aborts with a localized error.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **reject invalid integer operations** (critical) — verifies: PKL-003
  > The typechecker rejects binary arithmetic when either operand is not an Int.
  - contributes to: GOAL-PKL-PURE
  - body: _not yet implemented_

- [ ] **render Pkl objects and listings as PCF** — verifies: PKL-071 — tags: renderer, pcf
  > PCF rendering emits nested objects, listings, and mappings with the brace / element conventions Apple Pkl uses, including 2-space indentation, type-tag-free `new { ... }` wrappers for non-scalar listing / mapping values, and the empty `{}` form. The basic, modules, and classes upstream fixtures match the gold `.pcf` output byte-for-byte.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-070
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **render Pkl values as JSON** — verifies: PKL-072 — tags: renderer, json, cli
  > The CLI `eval -f json` (or `--format json`) flag emits a JSON document matching Apple Pkl's `pkl eval -f json` shape: ObjectValue and MappingValue project to JSON objects (Mapping keys are coerced to strings), ListingValue projects to JSON arrays, IntValue / BoolValue / NullValue use the JSON scalar form, and StringValue applies the standard `"`, `\`, control-character (`\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`) escapes. Indentation is fixed at two spaces. The default `eval` output remains PCF.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-071
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **render Pkl values as Java Properties** — verifies: PKL-074 — tags: renderer, properties, cli
  > The CLI `eval -f properties` (or `--format properties`) flag emits a Java Properties document matching Apple Pkl's `pkl eval -f properties` shape: ObjectValue and MappingValue members flatten into dotted keys (`a.b.c`), Mapping keys are coerced to strings, scalar values emit as unquoted `key = value` lines with property-style escaping for `\`, `\n`, `\t`, `\r`, `\f`, leading space, `:`, `=`, `!`, and `#`. ListingValue renders as a compact JSON-style single-line value (`[1,2,3]`), with the JSON `:` separators property-escaped to `\:`. NullValue leaves are omitted (mirroring Apple Pkl's `omitNullProperties = true` default), empty Object / Mapping leaves are dropped entirely, and empty Listings emit `key = []`. Top-level non-mapping values produce an empty document.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-072, PKL-073
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **render Pkl values as PCF primitives** — verifies: PKL-070 — tags: renderer, pcf
  > Module rendering as the canonical Pkl Configuration Format (PCF) emits Int, Boolean, String, and Null values with the same lexical form Apple Pkl uses, so module bindings reparse to the same value graph and the basic LanguageSnippetTests fixtures match the upstream gold output byte-for-byte.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **render Pkl values as YAML** — verifies: PKL-073 — tags: renderer, yaml, cli
  > The CLI `eval -f yaml` (or `--format yaml`) flag emits a YAML document matching Apple Pkl's `pkl eval -f yaml` block-style shape: ObjectValue and MappingValue project to block mappings (Mapping keys are coerced to strings, indented two spaces per level), ListingValue projects to block sequences at the parent column with `- value` entries, and empty composites use the `[]` / `{}` flow form. String scalars stay bare when they parse as plain YAML, switch to single-quoted with `''` escapes for leading indicators / numeric-or-keyword shapes / inline `: ` / ` #` / trailing whitespace, and switch to double-quoted with `\n`, `\t`, `\r`, `\\`, `\"`, and `\uXXXX` escapes when the value contains control characters or a backslash. The default `eval` output stays PCF.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-072
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl class inheritance defaults** — verifies: PKL-038 — tags: parser, typechecker, evaluator
  > Class declarations with inheritance merge base class property contracts and defaults so typed object expressions can omit inherited default-backed members and override inherited properties.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-037, PKL-036, PKL-019
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl comments and module property forward references** — verifies: PKL-012
  > The lexer preserves line/block comments as trivia, and module property evaluation/typechecking resolves sibling properties regardless of declaration order.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl imports and module resolution** (critical) — verifies: PKL-006
  > Import clauses resolve modules from the AnalysisSession source graph and make imported modules available for evaluation and typechecking.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl local module bindings and import expressions** — verifies: PKL-014
  > Module-level `local` bindings are available to sibling properties without being exported, and `import("...")` expressions resolve through the same pure MoonBit module resolver as import clauses.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl object body property shorthand** — verifies: PKL-013
  > Module and object members can use `name { ... }` object bodies as shorthand for object-valued properties.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl qualified class inheritance types** — verifies: PKL-039 — tags: parser, typechecker, imports
  > Class inheritance and typed object expressions preserve qualified class names such as `library.Person` so imported class contracts can be resolved through the analysis session.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-038, PKL-006, PKL-036
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl standard library surface** — verifies: PKL-007
  > The AnalysisSession resolver recognizes selected pkl: standard library modules and exposes them as pure MoonBit module sources.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support Pkl string escape compatibility** — verifies: PKL-010
  > Common string escapes are decoded by the parser and rendered by the evaluator/CLI output path.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support additional Pkl numeric constraint predicates** — verifies: PKL-053 — tags: typechecker, evaluator
  > Constrained integer annotations support common numeric predicate calls beyond `isBetween`, such as greater-than and less-than checks, in both typechecking and evaluation paths.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-052, PKL-046, PKL-051
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support initial Pkl object and module syntax** (critical) — verifies: PKL-005
  > The parser accepts module declarations, top-level properties, object literals, and member access; evaluator and typechecker resolve object fields.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support module extends amends and object amendments** (critical) — verifies: PKL-020 — tags: parser, evaluator, typechecker
  > Module `extends`/`amends` clauses and object amendment syntax merge inherited members through AnalysisSession resolution for parsing, evaluation, and typechecking.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-006, PKL-013, PKL-019
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **support multiple Pkl type constraint predicates** — verifies: PKL-054 — tags: typechecker, evaluator
  > Type annotations with multiple constraints, such as `Int(isPositive, isBetween(0, 10))`, evaluate each supported predicate and reject values that violate any predicate.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-053, PKL-046, PKL-052
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support negated Pkl type constraint predicates** — verifies: PKL-055 — tags: typechecker, evaluator
  > Type annotations with negated constraints, such as `Int(!isPositive)`, invert supported predicate results in typechecking and evaluation paths.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-054, PKL-053, PKL-046
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **support richer Pkl type semantics** — verifies: PKL-008
  > The parser and typechecker accept primitive Pkl-style type annotations and reject mismatched property/member values.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl callable parameter and return annotations** (critical) — verifies: PKL-023 — tags: parser, typechecker
  > Function declarations and lambda expressions retain parameter and return type annotations, and the typechecker validates call arguments plus annotated return values.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-022, PKL-008
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl class method bodies with receiver bindings** — verifies: PKL-043 — tags: typechecker
  > Class method bodies are checked with parameter bindings plus the receiver's property contract, so annotated method signatures reject invalid implementations before runtime.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040, PKL-041, PKL-023
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl constrained type annotations** — verifies: PKL-045 — tags: parser, typechecker
  > Type annotations with constraint calls such as `Int(isBetween(0, 10))` retain their base type contract so stdlib-like signatures can be parsed and checked before full constraint evaluation exists.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-023, PKL-028, PKL-044
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl function declarations lambdas and calls** (critical) — verifies: PKL-022 — tags: typechecker
  > The typechecker resolves function declarations and lambda bindings at call sites, infers return types from argument-bound parameter types, and reports call arity and non-function call errors.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-018, PKL-019
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl generic collection annotations** — verifies: PKL-025 — tags: parser, typechecker
  > The parser preserves generic annotation text for Listing and Mapping types, and the typechecker validates listing element and mapping key/value types.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-017, PKL-024
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl null-safe invocation chains** — verifies: PKL-033 — tags: parser, typechecker, evaluator
  > The parser and typechecker distinguish null-safe member invocation chains such as `value?.method()` from ordinary calls, preserving nullable short-circuit behavior through calls and chained accesses.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-032, PKL-022
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl nullable and generic typealias annotations** — verifies: PKL-026 — tags: parser, typechecker
  > Typealias declarations preserve nullable and generic target annotation text, and the typechecker resolves aliases to nullable, Listing, and Mapping contracts.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-024, PKL-025
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl nullable annotations** (critical) — verifies: PKL-024 — tags: parser, typechecker
  > The parser preserves nullable type annotation suffixes such as `String?`, and the typechecker accepts null or the inner type while narrowing null-coalescing expressions.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-008, PKL-018, PKL-023
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl nullable postfix operators** — verifies: PKL-032 — tags: parser, typechecker
  > The parser and typechecker support nullable postfix operators such as non-null assertion `!!` and safe member access `?.`, producing inner or nullable member types with diagnostics for invalid targets.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-024, PKL-031
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl typed object expressions** — verifies: PKL-036 — tags: parser, typechecker
  > Object literals that spell an explicit class name, such as `new Bird { ... }`, preserve that type in the AST and are checked against the class contract even without a separate property annotation.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-017, PKL-019, PKL-035
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl union type annotations** — verifies: PKL-027 — tags: parser, typechecker
  > The parser preserves union annotation text such as `String | Int`, and the typechecker accepts values that match any union branch, including nested collection and callable annotations.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-023, PKL-025, PKL-026
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck constrained Pkl callable return bodies** — verifies: PKL-067 — tags: typechecker, callable
  > Function, lambda, and class method declarations whose body is a literal that violates the declared constrained return annotation are rejected by the typechecker, mirroring the existing constrained binding behavior for built-in and user-defined numeric predicates.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-065, PKL-066
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck incrementally through ripple dependency graph** (critical) — verifies: PKL-021 — tags: typechecker, incremental, ripple
  > AnalysisSession registers source, parse, and typecheck query nodes with ripple so unrelated source edits do not re-run typechecking, and unchanged dependency type results are backdated.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-004, PKL-006, PKL-020
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck rich Pkl is and as type operands** — verifies: PKL-028 — tags: parser, typechecker
  > `is` and `as` expressions preserve nullable, generic, and union type operand text, and the typechecker validates the referenced type before returning the Boolean or cast result type.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-018, PKL-027
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck source through ripple** — verifies: PKL-004
  > A source-backed analysis session uses ripple input and query nodes to recompute typechecking after source changes.
  - contributes to: GOAL-PKL-PURE
  - body: _not yet implemented_

- [ ] **use upstream apple/pkl fixtures as compatibility checks** — verifies: PKL-011
  > The contract suite references Apple's Pkl repository as a git submodule and runs selected upstream LanguageSnippetTests fixtures through the pure MoonBit CLI.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

### `Test.pkl`

- [x] **cli eval** — verifies: PKL-009 — tags: moonbit, cli, contract
  > The native CLI evaluates a Pkl file and prints module object properties.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval json** — verifies: PKL-072 — tags: moonbit, cli, renderer, json, contract
  > The native CLI emits a JSON document when invoked with `-f json`.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval properties** — verifies: PKL-074 — tags: moonbit, cli, renderer, properties, contract
  > The native CLI emits a Java Properties document when invoked with `-f properties`.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval yaml** — verifies: PKL-073 — tags: moonbit, cli, renderer, yaml, contract
  > The native CLI emits a YAML document when invoked with `-f yaml`.
  - body: `cmd` (exit 0 expected)

- [x] **moon unit tests** — verifies: PKL-001, PKL-002, PKL-003, PKL-004, PKL-005, PKL-006, PKL-007, PKL-008, PKL-009, PKL-010, PKL-012, PKL-013, PKL-014, PKL-016, PKL-017, PKL-018, PKL-019, PKL-020, PKL-021, PKL-022, PKL-023, PKL-024, PKL-025, PKL-026, PKL-027, PKL-028, PKL-029, PKL-030, PKL-031, PKL-032, PKL-033, PKL-034, PKL-035, PKL-036, PKL-037, PKL-038, PKL-039, PKL-040, PKL-041, PKL-042, PKL-043, PKL-044, PKL-045, PKL-046, PKL-047, PKL-048, PKL-049, PKL-050, PKL-051, PKL-052, PKL-053, PKL-054, PKL-055, PKL-056, PKL-057, PKL-058, PKL-059, PKL-060, PKL-061, PKL-062, PKL-063, PKL-064, PKL-065, PKL-066, PKL-067, PKL-068, PKL-070, PKL-071, PKL-072, PKL-073, PKL-074, PKL-075, PKL-076, PKL-077 — tags: moonbit, unit, contract
  > MoonBit unit tests verify the initial parser, interpreter, typechecker, and ripple-backed analysis session.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl fixture smoke** — verifies: PKL-011, PKL-012, PKL-013, PKL-014, PKL-060 — tags: moonbit, upstream, compatibility, contract
  > Selected fixtures from the apple/pkl submodule parse and evaluate through the native CLI.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl parser suite** — verifies: PKL-015 — tags: moonbit, upstream, parser, compatibility, contract
  > All apple/pkl LanguageSnippetTests parser fixtures, excluding the same invalid cases as ParserComparisonTest, parse through the native CLI.
  - body: `cmd` (exit 0 expected)

