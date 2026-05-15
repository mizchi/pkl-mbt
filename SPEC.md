# Test SPEC

112 tests across 2 module(s) — 98 pending, 14 active

## `specs/`

### `Spec.pkl`

- [ ] **Bytes literal and Bytes methods** (minor) — verifies: PKL-083 — tags: evaluator, renderer, bytes, stdlib
  > `Bytes(<Listing of Int>)` is recognized as a constructor form ahead of the generic call path; each Listing element must be an Int in 0..=255 and the resulting `BytesValue` wraps a MoonBit `Bytes` instance. `Bytes.fromBase64("<base64>")` is the static-style decoder counterpart, surfacing malformed base64 input as a diagnostic rather than a raise. The `.length` and `.base64` properties expose the byte count and the base64 encoding of the underlying bytes; `.getOrNull(i)` returns the byte at index `i` (as `IntValue` 0..=255) or `null` when out of range; `.toList()` materializes the bytes back into a `Listing<Int>` so existing list helpers keep working. `String.toBytes()` joins the dispatch table on the String side, encoding the input as UTF-8 via `moonbitlang/core/encoding/utf8`. The PCF renderer round-trips a `BytesValue` back through the constructor (`Bytes(new Listing { 65; 66; 67 })`) so the parser can re-evaluate the literal verbatim; JSON / YAML / Properties project the bytes as their base64 encoding (a quoted string), matching the projection shape used by Apple Pkl for opaque stdlib values.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **CLI --format flag for eval** (minor) — verifies: PKL-094 — tags: cli, renderer
  > The `pkl eval` subcommand accepts both the short `-f` and the long `--format` flag and dispatches to the matching renderer. The format string is validated against the closed set `pcf` / `json` / `yaml` / `properties` before evaluation begins; an unrecognised format fails fast with `unsupported format: <text>`. Inside the dispatch, `pcf` has its own explicit arm rather than acting as the unmatched fallback, so adding a future renderer surfaces as a missing-arm warning at compile time. The default format remains `pcf` when neither flag is present, matching the existing CLI contract and the upstream `pkl eval` default. Both short and long forms are tested via the pkspec contracts: `cli eval --format long form` exercises `--format json`, `cli eval --format pcf` exercises the explicit `pcf` arm, and the existing `cli eval json` / `cli eval yaml` / `cli eval properties` tests stay on the short form to cover the original surface.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-072, PKL-073, PKL-074
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **CLI test runner integrates pkl:test facts** (minor) — verifies: PKL-095 — tags: cli, pkl-test
  > `pkl test <file.pkl>` evaluates the file the same way `eval` does, then walks a top-level `facts: Mapping<String, Listing<Boolean>>` member: each entry is one fact, each Listing element is one assertion, and the fact passes only when every assertion is `BoolValue(true)`. The runner prints one `PASS <name> (N assertions)` or `FAIL <name>: assertion #i of N did not evaluate to true` line per fact, then a trailing `<passed> passed, <failed> failed` summary, and exits non-zero on any failure. Modules without a `facts` member print only the summary (zero passed, zero failed) and exit zero — matching the `moon test` behaviour for empty test files. The minimal slice intentionally requires the explicit typed `facts` shape rather than the `amends "pkl:test"` shorthand because the shorthand needs the full `pkl:test` module to flow through the import system; that lift stays a follow-up.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-058
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Duration and DataSize literals with arithmetic comparison and unit conversion** (minor) — verifies: PKL-082 — tags: evaluator, renderer, duration, datasize
  > Member access on an Int literal whose name is a recognised Duration unit (`ns` / `us` / `ms` / `s` / `min` / `h` / `d`) produces a `DurationValue(Int, String)` carrying the original magnitude and unit; the matching DataSize units (`b` / `kb` / `kib` / `mb` / `mib` / `gb` / `gib` / `tb` / `tib` / `pb` / `pib`) produce a `DataSizeValue`. Same-unit `+` / `-` operate on the raw magnitudes and preserve the unit; mixed-unit `+` / `-` and comparison (`<` / `<=` / `>` / `>=` / `==` / `!=`) normalize to the smaller of the two units by stepping along the unit ladder one factor at a time so the running magnitude never overflows Int32. `.value` and `.unit` accessors expose the underlying Int and unit name; `.toUnit(name)` re-expresses the value in another aligned unit (e.g. `1.h.toUnit("min") == 60.min`). Unary negation flips the sign while keeping the unit. The PCF renderer emits the values back as the `<n>.<unit>` literal; JSON / YAML / Properties project them as the same lexical form coerced to a string.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Float numerics and constraint predicates** (minor) — verifies: PKL-092 — tags: evaluator, typechecker, renderer, constraint, float
  > Float numeric values flow through the entire stack. The lexer recognizes `<digits>.<digits>` as a Float token (Duration / DataSize `Int.<unit>` shorthand stays Int because `.identifier` is not promoted), the parser produces a new `FloatLiteral(Double)` Expr, and the evaluator carries the new `FloatValue(Double)` variant. Arithmetic widens automatically: `Int + Float` and `Float + Float` produce Float, comparisons (`<`, `<=`, `>`, `>=`, `==`, `!=`) admit any Int / Float mix, and `Int / Int` widens to Float to match Apple Pkl's `5 / 2 == 2.5` semantics. `IntDivide` / `Modulo` / `Power` keep their Int-only contract since their semantics are integer-domain. The typechecker gains a sibling `FloatType` and the `Number` annotation expands to `UnionType([IntType, FloatType])` so existing narrowing logic (union members, is-guards) keeps working. All four renderers (PCF / JSON / YAML / Properties) project Floats via a `render_float_text` helper that appends `.0` when the Double's shortest-round-trip form would otherwise look like an Int. The constraint cascade extends `pkl_constrained_int_predicates` to accept `Int(...)` / `Float(...)` / `Number(...)` as the host annotation, and a new `pkl_constraint_predicate_accepts_float` evaluator runs the existing Int-threshold predicates against Double values (widening thresholds to Double). `Float(isPositive)`, `Float(isBetween(0, 10))`, `Number(isPositive)`, and the negated / custom variants therefore fire on Float values; the rejection message format matches the Int side (`type annotation <name> constraint <p> rejects <v>`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-078
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Listing and Mapping element constraint propagation** — verifies: PKL-093 — tags: evaluator, typechecker, constraint, collection
  > `pkl_constrained_type_annotation_has_supported_constraint` recurses into the `Listing<T>` and `Mapping<K, V>` wrappers so element-level constraint annotations register as supported. The value-rejection cascade gains a collection branch after the Int / String branches: for a `Listing<T>` annotation on a `ListingValue`, every element re-enters the cascade with `T` as both display and source name; for a `Mapping<K, V>` annotation on a `MappingValue`, each entry's key is checked against `K` and each entry's value against `V`. The first rejecting element produces the diagnostic and short-circuits the cascade so error messages name a single failing predicate rather than a list. Nested wrappers (`Listing<Listing<Int(isPositive)>>`, `Mapping<String, Listing<Int(isBetween(0, 9))>>`) compose naturally because each recursion uses the same entry point; depth is capped at 8 to keep cycle-like aliases bounded.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-091, PKL-075
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **Regex literal and Regex methods** — verifies: PKL-081 — tags: evaluator, renderer, regex, stdlib
  > `Regex("<pattern>")` is recognized as a constructor form before the generic call path runs; the call's single String argument is captured verbatim as a `RegexValue(String)` carrying the pattern. The `.pattern` property exposes the original source pattern as a `String`. Five Regex methods dispatch through the same MemberAccess / SafeMemberAccess sites as the other stdlib value methods: `.matches(input)` returns true only when the regex covers the entire input (anchored on both ends), `.find(input)` returns the first match's text or `null`, `.findAll(input)` returns a `Listing<String>` of every non-overlapping match, `.replace(input, repl)` substitutes the first match, and `.replaceAll(input, repl)` substitutes every non-overlapping match. Compilation is deferred to the first method call so a Regex value can be constructed even if its pattern is later unused; an invalid pattern reports a diagnostic at method-call time. The PCF renderer round-trips a `RegexValue(p)` back as `Regex("<escaped-p>")`; JSON / YAML / Properties project the pattern as a plain string.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **String constraint predicates** — verifies: PKL-091 — tags: evaluator, typechecker, constraint, string
  > `String(...)` annotations recognise three predicate shapes — length comparisons (`length > 0`, `length >= 1`, etc., plus `<` / `<=` / `==` / `!=`), `length.NAME(...)` method calls that reuse the Int predicate grammar (`length.isBetween(1, 64)`, `length.isPositive`, `length.isGreaterThan(N)`, `length.isLessThan(N)`), and full-input regex matches (`matches(Regex("<pattern>"))`). Negation via the `!` prefix wraps any of these. Predicates run as part of the same constrained-type-annotation rejection cascade as the Int predicates: `pkl_constrained_type_annotation_has_supported_constraint` returns true when a String constraint is present, the runtime value-rejection path dispatches on String values, and the typecheck literal-expression path dispatches on String literals. Diagnostics keep the constraint name verbatim (`length > 0`, `length.isBetween`, `matches`, `!matches`, etc.) so the rejection message reads back to the original source shape.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077, PKL-081
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **allow Pkl class property defaults to satisfy missing members** — verifies: PKL-035 — tags: typechecker
  > Assignments to declared class types accept object literals that omit class properties with defaults, while still requiring properties without annotations or defaults.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-034
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **diff JSON evaluation output against apple/pkl gold files** — verifies: PKL-097 — tags: compatibility, upstream, renderer
  > `scripts/upstream-smoke.sh` gains a `JSON_GOLD_FIXTURES` list and an `eval_json_matches_gold` helper that runs the native CLI with `eval -f json`, byte-diffs the output against `LanguageSnippetTests/output/<dir>/<name>.json`, and prints `upstream json eval ok: <label> (gold match)` on success. The CLI's new `extract_output_value` helper unwraps a top-level `output { value = ... }` member before the renderer dispatches, mirroring the `output.value`-on-renderer invocation Apple Pkl uses for its renderer-test fixtures. Fixtures that route their data through `output.value` therefore render only the inner subtree, so `api/jsonRenderer1.json.pkl` matches the gold byte-for-byte. The remaining upstream JSON-renderer fixtures (`jsonRenderer2.json.pkl` / `3.json.pkl` / `6.json.pkl`) all need converters, Float numerics, or stdlib types (List / Set / Map / Pair / IntSeq / Dynamic) outside the implemented slice; those stay off the list and are picked up incrementally as the related slices land.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-071, PKL-072, PKL-096
  - decisions: 3 entry(ies)
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

- [ ] **evaluate broader upstream Pkl fixtures with gold byte-diff** — verifies: PKL-096 — tags: compatibility, upstream, renderer
  > `scripts/upstream-smoke.sh` carries an explicit list of `LanguageSnippetTests/input/<dir>/<name>.pkl` fixtures whose `pkl eval` output already matches the upstream gold `.pcf` file byte-for-byte. The script iterates the list, runs the fixture through the native CLI, diffs against `LanguageSnippetTests/output/<dir>/<name>.pcf`, and prints `upstream eval ok: <label> (gold match)` on success or a unified diff plus non-zero exit on any mismatch. The `parse_ok` and `eval_contains` paths from the original script remain so parser-only fixtures and the project-specific diagnostic-text fixture (`classes/constraints8.pkl`) keep their checks. The list lifts coverage from 7 hand-coded fixtures to 25 (`basic` 12, `classes` 3, `modules` 8, `objects` 1, `types` 1) and the trailing `upstream-smoke: <N> gold-match fixtures passed` summary lets the pkspec contract assert the total count instead of every individual line.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075, PKL-077, PKL-085
  - decisions: 3 entry(ies)
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

- [ ] **evaluate object body for-generators** — verifies: PKL-085 — tags: evaluator, object
  > `for (var in source) { ... }` and `for (var1, var2 in source) { ... }` inside an object body iterate the source (Listing or Mapping) and splice each iteration's members into the surrounding object. For Listings, the single-variable form binds the element; the two-variable form binds (index, element). For Mappings, the two-variable form binds (key, value). Per-iteration members are merged via `merge_value_members`, so later iterations overwrite earlier writes to the same name (matching Apple Pkl's `for`-as-property-generator semantics). The construct is encoded as a synthetic `@for` ObjectMember whose value is a new `ForGenerator(var1, var2, source, body)` `Expr` variant; `eval_object_members` recognises the reserved name and spreads the resulting `ObjectValue`'s members into the parent. Composes with `when`-conditionals inside the body — the @when spread per iteration contributes (or skips) members according to the condition.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075, PKL-086
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate object body when-conditionals** — verifies: PKL-086 — tags: evaluator, object
  > `when (cond) { ... } else { ... }` inside an object body picks the then-branch when the condition evaluates to `true` and the else-branch otherwise; the picked branch's members are spliced into the surrounding object body alongside any sibling properties. `else` is optional — a false condition without an `else` contributes no members. The condition expression sees the enclosing module's bindings (so `when (stage == "prod")` works), and each branch may declare multiple members. The construct is desugared at parse time into a synthetic `@when` object member whose value is a `ConditionalExpr` between the two branch `ObjectLiteral`s; `eval_object_members` recognises the reserved name and spreads the resulting `ObjectValue`'s members into the parent.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate simple Pkl callable closure captures** — verifies: PKL-061 — tags: evaluator, callable
  > Function and lambda values preserve simple scalar lexical bindings so returned lambdas and higher-order callables can evaluate variables from their defining scope.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-044, PKL-060
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **evaluate typealiased Pkl callable argument annotations** — verifies: PKL-069 — tags: evaluator, callable, typealias
  > Function, lambda, and class method calls resolve typealiased parameter annotations through the alias chain at runtime, so a parameter declared `x: Small` with `typealias Small = Int(isBetween(0, 10))` triggers the same predicate cascade as `x: Int(isBetween(0, 10))`. Built-in and user-defined constrained predicates fire alike, and the diagnostic preserves the original alias name (`Small`) while running the resolved constraint against the argument value.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-066, PKL-068
  - decisions: 2 entry(ies)
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

- [ ] **expand pkl:math beyond maxInt32** (minor) — verifies: PKL-079 — tags: stdlib, pkl-math
  > `pkl:math` exposes Int range constants (`maxInt32`, `minInt32`, `maxInt`, `minInt`) and Int-side helpers (`abs(x)`, `min(a, b)`, `max(a, b)`). The helpers are declared as top-level lambda bindings inside the synthetic `pkl:math` source so they round-trip through the regular `exported: true` path and become members of the imported module's `ObjectValue` — `import "pkl:math" as math; math.max(a, b)` evaluates without further dispatch work. `maxInt` / `minInt` track the 32-bit `Int` representation; once a 64-bit slot exists they expand to match the Java-derived Apple Pkl bounds.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-007, PKL-078
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **expose pkl:base Int operations** (minor) — verifies: PKL-078 — tags: stdlib, pkl-base, numeric
  > Int properties (`abs`, `isEven`, `isOdd`) and methods (`toString()`, `toString(radix)`, `toChar()`) dispatch against `IntValue` receivers via the same `MemberAccess` / `CallExpr` interception as the Listing / Mapping / String builtins. `toString(radix)` accepts radices 2..36 and writes a leading `-` for negative inputs. `toChar()` projects a Unicode code point (0..0x10FFFF) to a single-character `StringValue`. Int builtins compose with String / Listing pipelines, so `xs.map((n) -> n.toString(16)).join(",")` returns a hex-CSV `StringValue`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 3 entry(ies)
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

- [ ] **generic class declarations** [draft] — verifies: PKL-089 — tags: typechecker, generics, class, next
  > `class Box<T> { value: T }` declares a parameterized class; instances bind T at construction time and the typechecker propagates the binding through property and method accesses.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - body: _not yet implemented_

- [ ] **generic function type parameters** [draft] — verifies: PKL-090 — tags: typechecker, generics, callable
  > Function declarations such as `function identity<T>(x: T): T = x` accept a type parameter list; the typechecker infers the binding from the argument types at call sites.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-089
  - body: _not yet implemented_

- [ ] **hidden and local object members** — verifies: PKL-087 — tags: evaluator, renderer, object
  > Object-body members declared with the `hidden` modifier or the `local` keyword are kept inside the evaluated `ObjectValue` (so `lookup_member` still resolves bare-name reads against them) but are skipped by every renderer (PCF / JSON / YAML / Properties). Module-level `hidden` bindings get the same render-side filter; module-level `local` already routed through `parse_local_decl`, which marks the binding `exported: false` so the renderer never sees it in the first place. The render filter is a single `visible_members` projection applied at the entry of each renderer's member loop, keyed off a reserved `@hidden$` name prefix that the lexer rejects as an identifier character so it cannot collide with user-declared properties.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-070, PKL-071, PKL-072, PKL-073, PKL-074
  - decisions: 4 entry(ies)
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

- [ ] **minimal pkl:reflect support** (minor) — verifies: PKL-080 — tags: stdlib, pkl-reflect
  > `builtin_stdlib_source` resolves `pkl:reflect` to a thin Pkl-source stub that exposes the most-cited type mirror constants as string-tagged placeholders (`anyType`, `booleanType`, `intType`, `floatType`, `numberType`, `stringType`, `durationType`, `dataSizeType`, `bytesType`, `pairType`, `listType`, `setType`, `mapType`, `listingType`, `mappingType`, `objectType`, `dynamicType`, `typedType`, `moduleType`, `unknownType`, `nothingType`), all tagged with the `pkl.base#<name>` prefix that is internal to this stub. The factory bindings `Class`, `Module`, `TypeAlias`, `Property`, and `DeclaredType` are lambdas: each accepts a string identifier (rather than a class value, which the value model cannot yet round-trip) and returns an Object container exposing `reflectee` (for the first four) or `referent` (for `DeclaredType`). Fixtures that only read mirror constants or assert `reflect.Class(name).reflectee == name` now parse, typecheck, and evaluate; upstream `reflect.pkl` fixtures that need a real `ClassValue`, runtime member introspection, or `isSubclassOf` remain out of scope and are picked up by follow-up slices once the value model grows.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - decisions: 3 entry(ies)
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

- [ ] **null-coalescing operator and let expressions** (minor) — verifies: PKL-088 — tags: evaluator, expressions
  > The `??` operator picks the right-hand value when the left evaluates to `NullValue`, and is right-associative so `a ?? b ?? fallback` short-circuits left-to-right. `let (name = value) body` introduces a single scoped binding, with the body able to reference outer bindings and inner let-expressions able to shadow the outer name. The two compose: `let (fallback = ...) raw ?? fallback`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 2 entry(ies)
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

- [ ] **read built-in with sandbox-bounded env: scheme** — verifies: PKL-098 — tags: stdlib, io, sandbox
  > `read(uri)` is recognized at the CallExpr layer ahead of the generic call path. The argument must evaluate to a String; the scheme prefix (text before the first `:`) selects the dispatch. Today the sandbox policy is explicit and conservative: only `env:` is on the allow-list. `read("env:NAME")` consults the host environment via `moonbitlang/core/env.get_env_var`, returning the value as a `StringValue` on success and surfacing `read: env variable <NAME> is not set` as a diagnostic when the variable is missing. The remaining Apple Pkl schemes (`prop:`, `file:`, `https:`, `package:`) all surface `read: scheme <s>: is not allowed by the sandbox policy` rather than silently failing — the diagnostic names the offending scheme so the failure mode points at the policy boundary, not at the call site. URIs without a scheme prefix surface `read: missing URI scheme in "<uri>"`. The `read?(uri)` null-returning variant requires parser support for the `?`-suffixed call form and stays deferred to a follow-up slice. Built-in honors user shadowing (`read = (uri) -> uri` takes precedence), mirroring how `Bytes` / `Regex` / `throw` / `trace` honor shadows.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-084
  - decisions: 3 entry(ies)
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

- [ ] **trace and throw built-ins** (minor) — verifies: PKL-084 — tags: stdlib, diagnostics
  > `throw(message)` recognized as a builtin call ahead of the generic call path. The argument must evaluate to a String; on success it pushes a diagnostic carrying the message verbatim and aborts evaluation (no value returned), letting the existing diagnostic surface reuse the `test.catch` capture path. Anything other than a String surfaces `throw expects a String argument`, and wrong arity surfaces `throw expects exactly one argument`. `trace(value)` recognized as a sibling builtin that evaluates the argument and returns it verbatim; the stderr-stamp side of Apple Pkl's `trace` is deferred to a follow-up slice because the only observable channel for it lives in the CLI layer and would balloon this slice into renderer / diagnostic territory. Both builtins honor user shadowing (`throw = (s) -> s` takes precedence) so the same identifier remains free for user-defined helpers, mirroring how `Bytes` / `Regex` honor shadows.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 3 entry(ies)
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

- [x] **cli eval --format long form** — verifies: PKL-094 — tags: moonbit, cli, renderer, json, contract
  > The native CLI accepts the `--format` long-form flag and dispatches to the JSON renderer.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval --format pcf** — verifies: PKL-094 — tags: moonbit, cli, renderer, pcf, contract
  > The native CLI accepts `--format pcf` explicitly and emits the same PCF output as the default.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval json** — verifies: PKL-072, PKL-094 — tags: moonbit, cli, renderer, json, contract
  > The native CLI emits a JSON document when invoked with `-f json`.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval properties** — verifies: PKL-074, PKL-094 — tags: moonbit, cli, renderer, properties, contract
  > The native CLI emits a Java Properties document when invoked with `-f properties`.
  - body: `cmd` (exit 0 expected)

- [x] **cli eval yaml** — verifies: PKL-073, PKL-094 — tags: moonbit, cli, renderer, yaml, contract
  > The native CLI emits a YAML document when invoked with `-f yaml`.
  - body: `cmd` (exit 0 expected)

- [x] **cli float numerics and constraints** — verifies: PKL-092 — tags: moonbit, cli, float, constraint, contract
  > The native CLI evaluates a Float-heavy fixture, exercising Float literals, mixed Int / Float arithmetic, `Int / Int` widening to Float, and `Float(isPositive)` / `Float(isBetween(...))` / `Number(isPositive)` constraint predicates.
  - body: `cmd` (exit 0 expected)

- [x] **cli reflect minimal stub** — verifies: PKL-080 — tags: moonbit, cli, pkl-reflect, stdlib, contract
  > The native CLI evaluates a fixture that imports `pkl:reflect` and reads mirror constants plus the `Class` factory `reflectee` field, exercising the minimal stub registered in `builtin_stdlib_source`.
  - body: `cmd` (exit 0 expected)

- [x] **cli test failing facts** — verifies: PKL-095 — tags: moonbit, cli, pkl-test, contract
  > The native CLI `test` subcommand reports a FAIL line for any fact whose Listing contains a non-true value, naming the offending assertion index, and prints the pass / fail summary.
  - body: `cmd` (exit 0 expected)

- [x] **cli test passing facts** — verifies: PKL-095 — tags: moonbit, cli, pkl-test, contract
  > The native CLI `test` subcommand walks a `facts: Mapping<String, Listing<Boolean>>` member, reports a PASS line per fact, and ends with the pass / fail summary.
  - body: `cmd` (exit 0 expected)

- [x] **cli trace pass-through** — verifies: PKL-084 — tags: moonbit, cli, trace, contract
  > The native CLI evaluates a fixture where `trace(value)` wraps its argument; the rendered output shows the inner values unchanged, confirming the builtin pass-through semantics ship as part of PKL-084.
  - body: `cmd` (exit 0 expected)

- [x] **moon unit tests** — verifies: PKL-001, PKL-002, PKL-003, PKL-004, PKL-005, PKL-006, PKL-007, PKL-008, PKL-009, PKL-010, PKL-012, PKL-013, PKL-014, PKL-016, PKL-017, PKL-018, PKL-019, PKL-020, PKL-021, PKL-022, PKL-023, PKL-024, PKL-025, PKL-026, PKL-027, PKL-028, PKL-029, PKL-030, PKL-031, PKL-032, PKL-033, PKL-034, PKL-035, PKL-036, PKL-037, PKL-038, PKL-039, PKL-040, PKL-041, PKL-042, PKL-043, PKL-044, PKL-045, PKL-046, PKL-047, PKL-048, PKL-049, PKL-050, PKL-051, PKL-052, PKL-053, PKL-054, PKL-055, PKL-056, PKL-057, PKL-058, PKL-059, PKL-060, PKL-061, PKL-062, PKL-063, PKL-064, PKL-065, PKL-066, PKL-067, PKL-068, PKL-069, PKL-070, PKL-071, PKL-072, PKL-073, PKL-074, PKL-075, PKL-076, PKL-077, PKL-078, PKL-079, PKL-080, PKL-081, PKL-082, PKL-083, PKL-084, PKL-085, PKL-086, PKL-087, PKL-088, PKL-091, PKL-092, PKL-093, PKL-098 — tags: moonbit, unit, contract
  > MoonBit unit tests verify the initial parser, interpreter, typechecker, and ripple-backed analysis session.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl fixture smoke** — verifies: PKL-011, PKL-012, PKL-013, PKL-014, PKL-060, PKL-096, PKL-097 — tags: moonbit, upstream, compatibility, contract
  > Curated `pkl eval` fixtures from the apple/pkl submodule run through the native CLI and diff byte-for-byte against the upstream gold output (PCF and JSON).
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl parser suite** — verifies: PKL-015 — tags: moonbit, upstream, parser, compatibility, contract
  > All apple/pkl LanguageSnippetTests parser fixtures, excluding the same invalid cases as ParserComparisonTest, parse through the native CLI.
  - body: `cmd` (exit 0 expected)

