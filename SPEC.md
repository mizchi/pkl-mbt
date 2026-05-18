# Test SPEC

260 tests across 2 module(s) — 195 pending, 65 active

## `specs/`

### `Spec.pkl`

- [ ] **Any top type** — verifies: PKL-133 — tags: typechecker, pkf-pkspec
  > `Any` is Pkl's top type — every value flows through it. The Type enum gains a dedicated `AnyType` variant (distinct from `UnknownType`, which signals parser / inference fallback). `builtin_type_from_annotation("Any")` returns `AnyType`. `type_accepts` short-circuits to `true` whenever either side is `AnyType`, mirroring the relation `Any` plays in Pkl's type lattice: a concrete value flows into `Any`, and a value of `Any` flows back into any concrete annotation that expects it. `equality_compatible` accepts the same pattern so `x: Any = 5; res = x == 5` typechecks without a matching-types diagnostic. `render_type` emits `Any` so error messages preserve the user-facing name; collapsing into `UnknownType` would hide the difference from `Unknown`. The change is parser-transparent — no new tokens, no new AST nodes — and lights up `Any?`, `Mapping<String, Any>`, and `bodyJson: Any?` annotations across pkspec's schema without touching the evaluator at all.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-004
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Apple Pkl stdlib declaration modifiers** — verifies: PKL-140 — tags: parser, evaluator, typechecker, stdlib
  > Parser and evaluator accept four Apple Pkl stdlib idioms that previously tripped `unsupported expression` / `missing expression body` / `expected type parameter, got in`. (1) `external` modifier on properties / classes / functions: already recognised by `is_modifier_text` and consumed by `skip_member_header`; the gap was the resulting property with no `=` body, which the parser now flags as an abstract slot. (2) Abstract property slots (`foo: Int?`): the parser sets a new `Binding.abstract_slot = true` field, stores a `NullLiteral` placeholder value, and both evaluator + typechecker skip the binding (eval: not pushed onto ObjectValue; typecheck: type recorded as the declared slot type, no validation against the placeholder). (3) Variance modifiers `<in T>` / `<out T>` on class / function / typealias type parameters: parser consumes the modifier before the identifier; pkl-mbt treats type parameters invariantly so the marker is purely a parse-side acknowledgement. (4) Function type annotations on properties (`comparator: (V, V) -> Boolean = ...`): new `parse_property_type_annotation` helper uses `stop_at_arrow=false` because property declarations end at `=` / `{`, making the arrow unambiguous. The same helper is wired into class-property declarations. (5) Declarations-only modules (`module pkl.math` with only `external` properties) now evaluate to the empty ObjectValue rather than `missing expression body`, mirroring Apple Pkl's stdlib loading model.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-002, PKL-116
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

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

- [ ] **Callable parameter basic-type rejection fires before body evaluation** (minor) — verifies: PKL-148l — tags: evaluator, typecheck, upstream, compat
  > Apple Pkl rejects a function/method call whose argument doesn't satisfy the parameter's basic type annotation before the body runs, with the bare diagnostic `Expected value of type `<T>`, but got type `<U>`. Value: <pcf>` — the same wording the return-side annotation already uses. pkl-mbt only ran a constraint-shaped check (`Int(isBetween(0, 10))`) on parameters, so a basic-type mismatch like `x.sum(1.1, 2)` against `sum(a: Int, b: Int): Int = a + b` slipped past the parameter gate and only failed inside the body (sometimes returning a Float, sometimes bubbling `operator + expects Int operands`). A new `eval_callable_argument_type_rejection_message` mirrors the return-side acceptance pipeline (resolve type alias → strip the trailing `(...)` constraint → strip any `<...>` generic suffix → fall through `eval_value_accepts_type_annotation` + `value_satisfies_user_class_annotation`) and emits the bare message (no `<label> argument N` prefix, matching Apple Pkl's exact wording). The check runs at all three callable entry points — `eval_lambda_application`, `apply_function_value`, and the class-method dispatch in `eval_member_access_call` — before the existing constraint check, so the constraint cascade still wraps with `<label> argument N <message>` while the basic-type rejection projects the wording byte-for-byte. Generic-head stripping is necessary so `List<Set<String(this=="one")>(thisisSet)>(thisisList)`-shaped annotations from `types/ThisInTypeConstraint` collapse to `List` and accept the `ListValue` argument without false-positive. Lifts gold-match from 102 to 103 PCF (`methods/methodParameterTypes1`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148k
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **Duration and DataSize literals with arithmetic comparison and unit conversion** (minor) — verifies: PKL-082 — tags: evaluator, renderer, duration, datasize
  > Member access on an Int literal whose name is a recognised Duration unit (`ns` / `us` / `ms` / `s` / `min` / `h` / `d`) produces a `DurationValue(Int, String)` carrying the original magnitude and unit; the matching DataSize units (`b` / `kb` / `kib` / `mb` / `mib` / `gb` / `gib` / `tb` / `tib` / `pb` / `pib`) produce a `DataSizeValue`. Same-unit `+` / `-` operate on the raw magnitudes and preserve the unit; mixed-unit `+` / `-` and comparison (`<` / `<=` / `>` / `>=` / `==` / `!=`) normalize to the smaller of the two units by stepping along the unit ladder one factor at a time so the running magnitude never overflows Int32. `.value` and `.unit` accessors expose the underlying Int and unit name; `.toUnit(name)` re-expresses the value in another aligned unit (e.g. `1.h.toUnit("min") == 60.min`). Unary negation flips the sign while keeping the unit. The PCF renderer emits the values back as the `<n>.<unit>` literal; JSON / YAML / Properties project them as the same lexical form coerced to a string.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Dynamic value shape via element and subscript sentinel members** — verifies: PKL-148x — tags: parser, evaluator, renderer, upstream, compat
  > Apple Pkl's `new {}` accepts mixed-shape bodies: named properties (`name = value`), unnamed listing-style elements (bare `value`), and mapping-style entries (`[key] = value`) coexist on the same ObjectValue (Dynamic shape). pkl-mbt's ObjectValue carries only `Array[ValueMember]` (name → value), so unnamed elements were dropped at parse time (`skip_unknown_member`) and `[key] = value` couldn't be represented even after PKL-148w wired the parse side for AmendExpr. The Dynamic shape lands via sentinel member names that ride inside the existing `Array[ValueMember]` storage — no Value enum change. Parser captures bare expressions in an object body as `ObjectMember { name = "@element$<offset>" }` (offset disambiguates multiple unnamed entries) and `[key] = value` as `ObjectMember { name = "@subscript$<offset>", value = CallExpr(Identifier("@__index_entry"), [key, value]) }` (the same encoding PKL-148w introduced for AmendExpr). Eval-side `eval_object_members` evaluates each sentinel and stores the result as a ValueMember keeping the sentinel name; `@subscript$` payloads decode the CallExpr and produce a synthetic `ObjectValue([@key, @value])` so the (key, value) pair survives as a Value. Renderer's `render_pcf_object_member` projects `@element$` listing-style (`render_pcf_inline` so nested Dynamic objects pick up the `new ` prefix) and `@subscript$` as `[key] = value` (or `[key] { body }` for block values). The `@spread` arm in `eval_object_members` was extended to lower ListingValue / ListValue / SetValue payloads into `@element$spread<i>` entries and MappingValue / MapValue payloads into `@subscript$spread<i>` entries, so `new { ...listing }` and `new { ...mapping }` now flatten into the parent Dynamic. `parse_inferred_new_body` routes a body whose first significant token is `...` through the object-body parser (the Dynamic shape now absorbs every payload shape, so the listing-only route is no longer needed). +2 fixtures (`generators/spreadSyntaxTyped`, `generators/forGeneratorNestedReference2`), 120 → 122; generators category 9.5% → 19.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148w
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **Float Power IntDivide and Modulo semantics** (minor) — verifies: PKL-111 — tags: evaluator, typechecker, float, operator
  > Apple Pkl's `**` / `~/` / `%` operators accept Float operands and produce results that match the JVM evaluator's golden output. `**` (Power) widens to Float on any Float operand: `2.0 ** 3 = 8.0`, `2.3 ** 4.0 ≈ 27.984099999999998` (Apple's exact bit pattern). `~/` (IntDivide) always returns an Int even when both operands are Float, using truncation toward zero: `5.0 ~/ 3.0 = 1`, `5 ~/ 3.0 = 1`, `5.1 ~/ 3.1 = 1`. `%` (Modulo) widens to Float on any Float operand and computes the truncated remainder `a - b * trunc(a / b)`: `5.5 % 6.5 = 5.5`, `5 % 6.5 = 5.0`. The evaluator routes these through `eval_float_binary`'s extended branches, using `@math.pow` from `moonbitlang/core/math` for exponentiation and a local `double_trunc` helper that round-trips through Int64 for truncation. Division-by-zero on `~/` and `%` against a zero divisor surfaces the same `division by zero` diagnostic as the Int-side path. The typechecker mirrors the runtime rule: when both operands are numeric and at least one is Float, the result is Float for `**` / `%` and Int for `~/`; Int × Int keeps the existing Int-only result type.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-092
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Float magnitude Duration and DataSize literals** (minor) — verifies: PKL-121 — tags: parser, evaluator, duration, datasize, float
  > `1.5.s`, `2.5.gib`, `0.5.h` and other Float-magnitude unit literals parse and evaluate to Duration / DataSize values whose magnitude is `Double`. The `DurationValue` / `DataSizeValue` variants were widened from `Int` to `Double` so both Int and Float magnitudes round-trip through the same Value, and the conversion helpers (`duration_in_unit`, `datasize_in_unit`) now compute in Double. Int-magnitude call sites promote on the way in. The `.value` property projects back to `IntValue` when the magnitude is integral and `FloatValue` otherwise so existing Int-magnitude observations stay byte-identical.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-082, PKL-092
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **Float numerics and constraint predicates** (minor) — verifies: PKL-092 — tags: evaluator, typechecker, renderer, constraint, float
  > Float numeric values flow through the entire stack. The lexer recognizes `<digits>.<digits>` as a Float token (Duration / DataSize `Int.<unit>` shorthand stays Int because `.identifier` is not promoted), the parser produces a new `FloatLiteral(Double)` Expr, and the evaluator carries the new `FloatValue(Double)` variant. Arithmetic widens automatically: `Int + Float` and `Float + Float` produce Float, comparisons (`<`, `<=`, `>`, `>=`, `==`, `!=`) admit any Int / Float mix, and `Int / Int` widens to Float to match Apple Pkl's `5 / 2 == 2.5` semantics. `IntDivide` / `Modulo` / `Power` keep their Int-only contract since their semantics are integer-domain. The typechecker gains a sibling `FloatType` and the `Number` annotation expands to `UnionType([IntType, FloatType])` so existing narrowing logic (union members, is-guards) keeps working. All four renderers (PCF / JSON / YAML / Properties) project Floats via a `render_float_text` helper that appends `.0` when the Double's shortest-round-trip form would otherwise look like an Int. The constraint cascade extends `pkl_constrained_int_predicates` to accept `Int(...)` / `Float(...)` / `Number(...)` as the host annotation, and a new `pkl_constraint_predicate_accepts_float` evaluator runs the existing Int-threshold predicates against Double values (widening thresholds to Double). `Float(isPositive)`, `Float(isBetween(0, 10))`, `Number(isPositive)`, and the negated / custom variants therefore fire on Float values; the rejection message format matches the Int side (`type annotation <name> constraint <p> rejects <v>`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-078
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Float-threshold constraint predicates** (minor) — verifies: PKL-112 — tags: typechecker, constraint, float
  > Numeric constraint predicates (`isBetween`, `isGreaterThan`, `isLessThan`, plus the user-defined comparison factories) accept Float literals as thresholds. `Float(isBetween(0.5, 1.5))` now parses and runs without losing precision — previously the threshold parser only accepted Int text, so `0.5` failed to parse and the predicate was silently dropped. The `ConstraintIntPredicate` enum keeps its name (still scoped to the numeric host `Int` / `Float` / `Number`) but its arguments are encoded as `Double` instead of `Int`. The text parser `pkl_parse_constraint_double_text` accepts an optional leading `-`, a digit-run integer part, and an optional `.<digits>` fractional part; the existing `pkl_parse_constraint_int_text` stays in place for `String(length OP N)` paths where `length` is always Int. Int-side value comparison flows through `pkl_constraint_predicate_accepts_float(predicate, value.to_double())` so `Int(isBetween(0, 10))` keeps working uniformly with `Float(isBetween(0.5, 1.5))`. The `length.is*` reuse of the numeric grammar truncates the Double threshold back to Int with `Double::to_int` — `length.isBetween(2.5, 3.5)` therefore behaves like `length.isBetween(2, 3)`, matching Apple Pkl's truncation toward zero. Rejection messages format the Double via the existing `\{value}` interpolation, so `Float(isLessThan(1.5))` rejecting `2.0` surfaces as `rejects 2` (the MoonBit `Double::to_string` strips the trailing `.0` for integral Doubles, which the existing PKL-092 fixtures already documented for `rejects -0.5`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-092
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **IntSeq Value variant** — verifies: PKL-119b — tags: evaluator, typechecker, stdlib
  > IntSeq joins the dedicated stdlib value variants. `Value` gains `IntSeqValue(Int, Int, Int)` carrying start / end / step; `IntSeq(start, end)` constructs one with step = 1 and `.step(newValue)` returns a new IntSeq with the step replaced (zero is rejected). Bare property reads `.start` / `.end` / `.step` return the carrier slots as Int values; method calls `.toList()` / `.toListing()` materialize into a `ListingValue` of Ints (the two share the materialization path until PKL-119c/d split List / Map out), `.map(f)` projects each materialized element through the lambda, and `.fold(initial, op)` reduces left-to-right. PCF round-trips through `IntSeq(s, e)` (or `IntSeq(s, e).step(n)` when step != 1) so the rendered output is parser-readable; JSON / YAML / Properties / plist materialize to a sequence of Int elements. The typechecker gains `IntSeqType` (parameter-free since elements are always Int); `IntSeq` annotations resolve directly, `IntSeq(start, end)` call sites infer to `IntSeqType` with both arguments expected to accept `Int`, and `infer_call_expr` intercepts method-form calls so `.toList()`/`.toListing()` return `Listing<Int>`, `.map(f)` returns a Listing of the lambda's return type, `.fold(initial, op)` returns the initial type, and `.step(n)` returns IntSeqType. Empty IntSeq (e.g. ascending `IntSeq(5, 0)` or descending without `step(-1)`) materializes to an empty Listing; full upstream equality semantics (empty sequences are equal regardless of endpoints, step-aware element-set equality) remains a follow-up — the structural `derive(Eq)` lined up well enough for the contracts we have today.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-119a
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **IntSeq sequence equality** — verifies: PKL-119be — tags: evaluator, stdlib
  > Apple Pkl's `IntSeq` equality compares the *element sequence* the two operands produce, not their carrier shape. Empty IntSeqs are equal regardless of endpoints (`IntSeq(0, -1) == IntSeq(10, -10)`); non-empty IntSeqs are step-aware (`IntSeq(-10, 10).step(2) == IntSeq(-10, 11).step(2)` because both produce -10, -8, ..., 10). The PKL-119b stop-gap relied on the structural `derive(Eq)` the value variant inherits, which mis-answered both cases. `eval_binary` now intercepts `(IntSeqValue, IntSeqValue)` pairs before the generic equality fall-through and routes through `intseq_value_equal`, which materializes both operands and compares them element-by-element. Both-empty short-circuits via the length-mismatch check (zero == zero) plus the zero-iteration loop. Non-Equal binary ops on IntSeq operands aren't defined upstream and emit the standard `operator <op> not defined for IntSeq operands` diagnostic.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-119b
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **ListValue split from ListingValue for List constructor PCF round-trip** — verifies: PKL-148h — tags: evaluator, renderer, stdlib, upstream, compat
  > Apple Pkl distinguishes `List<T>` (immutable indexed collection, constructor `List(...)`, PCF `List(elem, ...)`) from `Listing<T>` (CST-typed builder, `new Listing { ... }`, PCF `new { elem; ... }` block). pkl-mbt previously collapsed both into `ListingValue`, which meant `List(1, 2, 3)` rendered as `new { 1; 2; 3 }` — silent rendering divergence on every fixture that uses `List`. This slice splits the variant: `List(...)` and `.toList()` now produce a dedicated `ListValue(Array[Value])` that renders through `render_pcf_scalar` as `List(elem, ...)`; `.toListing()` and the existing `new Listing { ... }` literal path stay on `ListingValue`. Listing-method dispatch (`.filter`, `.map`, `.length`, `.startsWith`, `.flatMap`, `.toSet`, subscript, `+`) accepts both variants via pattern alternation — the dispatcher's element-walking logic is identical. The Apple-Pkl `module.catch(() -> list[i])` diagnostic text is also brought into shape (`Element index `i` is out of range `0`..`N`. Collection: List(...)`) so out-of-bounds string projections round-trip. Lifts gold-match from 72 to 82 PCF (`api/pair`, `basic/list`, `classes/inheritance1`, `classes/inheritance2`, `listings/listing1`, `mappings/mapping1`, `methods/methodParameterTypes2`, `modules/lists`, `modules/typedModuleProperties1`, `types/ThisInTypeConstraint`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148g
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Listing and Mapping element constraint propagation** — verifies: PKL-093 — tags: evaluator, typechecker, constraint, collection
  > `pkl_constrained_type_annotation_has_supported_constraint` recurses into the `Listing<T>` and `Mapping<K, V>` wrappers so element-level constraint annotations register as supported. The value-rejection cascade gains a collection branch after the Int / String branches: for a `Listing<T>` annotation on a `ListingValue`, every element re-enters the cascade with `T` as both display and source name; for a `Mapping<K, V>` annotation on a `MappingValue`, each entry's key is checked against `K` and each entry's value against `V`. The first rejecting element produces the diagnostic and short-circuits the cascade so error messages name a single failing predicate rather than a list. Nested wrappers (`Listing<Listing<Int(isPositive)>>`, `Mapping<String, Listing<Int(isBetween(0, 9))>>`) compose naturally because each recursion uses the same entry point; depth is capped at 8 to keep cycle-like aliases bounded.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-091, PKL-075
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **Listing and Mapping functional methods** — verifies: PKL-135 — tags: stdlib, evaluator, typechecker, pkf-pkspec
  > Higher-order predicate / search / flatten methods on `Listing` and `Mapping` resolve and run end-to-end. `Listing` gains `flatMap`, `count`, `every`, `any`, `none`, `find`, `findOrNull`, `findLast`, `findLastOrNull`; `Mapping` gains `every`, `any`, `none`, `count` whose predicates take `(Key, Value) -> Boolean` (matching upstream's signature). Each method is wired through `is_listing_method_name` / `is_mapping_method_name` plus `eval_listing_method` / `eval_mapping_method`, reusing `apply_function_value` to invoke the user lambda per element. `find` raises a diagnostic when no element matches (mirroring Apple Pkl's behaviour), `findOrNull` and `findLastOrNull` return `NullValue` instead. `flatMap` accepts callbacks returning Listing only — the `Collection<Result>` union (List / Listing / Set) is collapsed onto `ListingValue` today, so the constraint is the runtime shape of the result rather than the declared type.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-134
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **Listing and Mapping stdlib core methods** — verifies: PKL-134 — tags: stdlib, evaluator, typechecker, pkf-pkspec
  > The read-only conversion / shape methods on `Listing` and `Mapping` resolve as expected. `Listing.toList()` returns the same elements (pkl-mbt collapses Listing / List into one Value variant); `Listing.toMap()` returns the empty Mapping (Pair-based projections are deferred to PKL-119). `Mapping.toMap()` is the identity, `Mapping.toList()` projects the values. `length`, `isEmpty`, `keys`, `values` were already wired by earlier slices and stay green. Type annotation `List<T>` resolves to `ListingType([T])` via a new alias in `builtin_type_from_annotation` and `generic_argument_text(..., "List")` — the typechecker treats Listing / List as the same shape until PKL-119 introduces dedicated value variants. The method dispatch routes through `is_listing_method_name` / `is_mapping_method_name` + the existing `eval_listing_method` / `eval_mapping_method`, so the call-site grammar (`xs.toList()`) follows the same path as `xs.contains(v)`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Map Value variant for the immutable functional map** — verifies: PKL-119d — tags: evaluator, typechecker, stdlib
  > Apple Pkl's `Map<K, V>` is the immutable functional map (built with `Map(k1, v1, k2, v2, ...)`), distinct from `Mapping<K, V>` (the object-style `new Mapping { ... }` form with constraints / defaults / amends). `Value` gains `MapValue(Array[ValueEntry])`; the `Map(...)` constructor returns it and later duplicate keys overwrite earlier entries (matching upstream functional-map semantics). Bare property reads — `.length` → Int; `.isEmpty` / `.isNotEmpty` → Boolean; `.keys` → SetValue of the keys; `.values` → ListingValue of values; `.entries` → ListingValue of PairValue carriers — flow through the member-access dispatcher. Methods (`.containsKey` / `.getOrNull(k)` / `.getOrThrow(k)` / `.toMap` / `.toMapping` / `.toList` / `.map((k, v) -> Pair<NewKey, NewValue>)` / `.filter((k, v) -> Boolean)` / `.fold(initial, (acc, k, v) -> NewAcc)`) dispatch through `eval_map_method`. Renderer projection: PCF round-trips through `Map(k, v, k, v, ...)` so eval output is parser-readable; JSON / YAML / Properties / plist project as the same object shape MappingValue uses (object / `<dict>` / `key.subkey = value`). Typechecker gains `MapType(Array[TypeEntry])` parallel to `MappingType`. `Map<K, V>` annotations land via `generic_argument_text`; bare `Map` resolves to `MapType([])`. `Map(...)` call sites infer to `MapType` carrying the entry-type pairs; `infer_call_expr` intercepts each method-call form so `.containsKey` → Boolean, `.getOrNull` → `value?`, `.getOrThrow` → value, `.toMap` → identity, `.toMapping` → MappingType, `.toList` → `Listing<Pair<K, V>>`, `.map` → `MapType([])` (richer return-type inference would need a Pair-shape narrowing hook), `.filter` → `Map<K, V>`, `.fold` → initial type. A new `(MapType, MapType)` arm in `type_accepts` mirrors `(MappingType, MappingType)`'s widening so `Map<String, Int>` annotations accept the constructor-inferred carrier shape.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-119a, PKL-119b, PKL-119c
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **Mapping literal duplicate scalar key detection and pipe operator diagnostic** (minor) — verifies: PKL-148k — tags: evaluator, diagnostics, upstream, compat
  > Two tiny Apple-Pkl-shaped diagnostics that travel through `test.catch(...)` and project the failure as a String. `new Mapping { ["barn owl"] = 1; ["bar" + "n owl"] = 3 }` must reject with `Duplicate definition of member `"barn owl"`.` even though the two key expressions are different string-concat compositions: the check fires at MappingLiteral eval time, after each key is resolved, and quotes the first colliding key through `render_pcf_value_inline`. The check is restricted to scalar key shapes (String / Int / Float / Bool / Null / Duration / DataSize / Regex / Bytes) — composite-key equality (ObjectValue / ListingValue / MappingValue) collapses without class identity, so the same gate would false-positive on `mappings/mapping1`'s `[new Dynamic {...}]` / `[new Person {...}]` keys that share identical visible members. The composite-key case lands alongside the class-aware ObjectValue refactor (PKL-148l). Pipe-operator (`|>`) projects the dedicated Apple Pkl diagnostic when the RHS isn't callable (`module.catch(() -> 42 |> 21)` → `Operator `|>` is not defined for operand types `Int` and `Int`. Left operand : 42 Right operand: 21`) instead of bubbling the desugared `CallExpr`'s generic `call expects Function`; the right operand is evaluated first so the diagnostic captures the actual runtime type / inline-PCF render. Lifts gold-match from 100 to 102 PCF (`mappings/duplicateComputedKey`, `mappings2/duplicateComputedKey`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148j
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **PCF triple-quoted heredoc form plus Dynamic property-before-element projection** (minor) — verifies: PKL-148al — tags: renderer, pcf, upstream, compat
  > Apple Pkl's PCF renderer has two output conventions that pkl-mbt was missing. (1) A StringValue containing at least one `\n` at a block position (property value, mapping entry value, listing element) renders as a triple-quoted heredoc — `lastName = """<newline><indent>line1<newline><indent>line2<newline><indent>"""` — with content lines and the closing `"""` sitting at one consistent indent that depends on whether the heredoc is a property value (indent + 2 from the name) or a bare element (same as the element's own indent). Inline contexts (`List("a\nb")`, `Pair("x\ny", 2)`) keep the single-line `\n`-escaped form. Empty content lines preserve the indent verbatim (Apple Pkl emits `<indent>\n`, not a bare `\n`). (2) A Dynamic-shape body's PCF projection groups every named property before every bare element / mapping subscript entry, regardless of source order — `barnOwl { name = "barn owl"; "surfing"; age = 42; "fire making" }` projects as `barnOwl { name = ...; age = ...; "surfing"; "fire making" }`, not source-order. The fix lives entirely in eval.mbt's PCF renderer: a new `render_pcf_string_heredoc(s, indent, buf)` helper plus a `string_split_newline` walker, gated by an `indent > 0 && value is StringValue(s) && s.contains("\n")` check inside `render_pcf_inline`; matching `field.value is StringValue(s) && s.contains("\n")` arms in `render_pcf_object_member` and `render_pcf_mapping_entry` so property / mapping values pick up the same heredoc form with `indent + 2`; and a partition step at the head of `render_pcf_block_body`'s ObjectValue arm that splits `visible_members` into a named bucket and an `@element$` / `@subscript$` bucket, emitting named first. +1 fixture (`api/pcfRenderer1`), 144 → 145; api category 7.4% → 8.4%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ak
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **Pair Value variant** — verifies: PKL-119a — tags: evaluator, typechecker, stdlib
  > Pair gets a dedicated value model. `Value` gains a `PairValue(Value, Value)` variant; the `Pair(first, second)` constructor returns it directly instead of the PKL-139 stop-gap `ListingValue` of size 2. Member access on the dedicated variant resolves `.first` and `.second` to the carried values; any other property name surfaces `Cannot find property \`<name>\` in object of type \`Pair\`.`, matching Apple Pkl's wording for typed containers. Renderer projection: PCF round-trips through `Pair(a, b)` (so the eval output is parser-readable), JSON / YAML / Properties / plist project as a 2-element sequence (`[a, b]` / sequence items / `<array>` of two elements). The typechecker gains `PairType(Type, Type)` alongside `ListingType` / `MappingType` so `Pair<A, B>` annotations stay distinct from `Listing<A | B>` — the same separation pkl-mbt's library consumers need to preserve embedder types. `Pair<A, B>` annotation lands through the `generic_argument_text` intercept; bare `Pair` (no generic arguments) is intentionally NOT a builtin so user-defined `class Pair` declarations still shadow per the existing generic-class-with-two-type-parameters test.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075, PKL-139
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **Regex literal and Regex methods** — verifies: PKL-081 — tags: evaluator, renderer, regex, stdlib
  > `Regex("<pattern>")` is recognized as a constructor form before the generic call path runs; the call's single String argument is captured verbatim as a `RegexValue(String)` carrying the pattern. The `.pattern` property exposes the original source pattern as a `String`. Five Regex methods dispatch through the same MemberAccess / SafeMemberAccess sites as the other stdlib value methods: `.matches(input)` returns true only when the regex covers the entire input (anchored on both ends), `.find(input)` returns the first match's text or `null`, `.findAll(input)` returns a `Listing<String>` of every non-overlapping match, `.replace(input, repl)` substitutes the first match, and `.replaceAll(input, repl)` substitutes every non-overlapping match. Compilation is deferred to the first method call so a Regex value can be constructed even if its pattern is later unused; an invalid pattern reports a diagnostic at method-call time. The PCF renderer round-trips a `RegexValue(p)` back as `Regex("<escaped-p>")`; JSON / YAML / Properties project the pattern as a plain string.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **Resource type for read return values** [draft] — verifies: PKL-149 — tags: evaluator, stdlib, upstream, compat
  > Apple Pkl's `read("file:...")` returns a `Resource` value carrying `.uri` / `.text` / `.base64` / `.md5` / `.sha256` accessors; pkl-mbt currently returns the file contents as a bare `String`. Introduce a `ResourceValue` variant, route `read("file:...")` through it, and wire the property accessors. Also stop rejecting bare paths (the upstream `api/Resource` fixture passes `read("empty.txt")` without a scheme — Apple Pkl treats it as `file:` relative to the module). Required for the `api/Resource*` / `api/read*` upstream fixture cluster.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-098
  - body: _not yet implemented_

- [ ] **Set Value variant** — verifies: PKL-119c — tags: evaluator, typechecker, stdlib
  > Set joins the dedicated stdlib value variants. `Value` gains `SetValue(Array[Value])` and the `Set(a, b, c)` constructor returns it (duplicates dropped at construction via `contains_value`; insertion order preserved). Bare property reads (`.length` → Int; `.isEmpty` / `.isNotEmpty` → Boolean; `.first` / `.last` → element type with empty-set diagnostic; `.distinct` → identity SetValue) resolve through the member-access dispatcher; method calls (`.contains` → Boolean; `.toList` / `.toListing` → `Listing<element>`; `.toSet` → identity; `.map(f)` → `Listing<lambda return>`; `.filter(p)` → `Set<element>`; `.fold(initial, op)` → initial type; `.join(sep)` → String) dispatch through the dedicated `eval_set_method` evaluator. Renderer projection: PCF round-trips through `Set(a, b, c)` so the eval output is parser-readable; JSON / YAML / Properties / plist materialize as an array of the elements. Typechecker gains `SetType(Array[Type])` parallel to `ListingType`. `Set<T>` annotations land via `generic_argument_text`; bare `Set` resolves to `SetType([])` (accept-any element). `Set(a, b, c)` call sites infer to `SetType` carrying the element types, and `infer_call_expr` intercepts the method-form calls so each method returns the right shape. `type_accepts` adds a `(SetType, SetType)` arm with the same widening rules as `(ListingType, ListingType)` so `Set<Int>` annotations accept the inferred `SetType([IntType, IntType, IntType])` shape from the constructor.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-119a, PKL-119b
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **Silent-mismatch survey** (minor) [draft] — verifies: PKL-153 — tags: renderer, upstream, compat
  > The 148 upstream fixtures that evaluate without diagnostic but don't byte-match the gold output are the long tail — typically rendering subtleties (whitespace, member ordering, string-escape choices, Listing element separator), output-block extraction edge cases, or trivial Float-format / number-stringification differences. Each one usually reads as a one-or-two-line PCF-renderer fix. The slice's deliverable is a tabulated categorization (by diff signature, captured into a checked-in CSV under `scripts/`) plus the highest-uplift bucket fixed end-to-end. Subsequent buckets land as their own micro-slices.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-096
  - body: _not yet implemented_

- [ ] **String constraint predicates** — verifies: PKL-091 — tags: evaluator, typechecker, constraint, string
  > `String(...)` annotations recognise three predicate shapes — length comparisons (`length > 0`, `length >= 1`, etc., plus `<` / `<=` / `==` / `!=`), `length.NAME(...)` method calls that reuse the Int predicate grammar (`length.isBetween(1, 64)`, `length.isPositive`, `length.isGreaterThan(N)`, `length.isLessThan(N)`), and full-input regex matches (`matches(Regex("<pattern>"))`). Negation via the `!` prefix wraps any of these. Predicates run as part of the same constrained-type-annotation rejection cascade as the Int predicates: `pkl_constrained_type_annotation_has_supported_constraint` returns true when a String constraint is present, the runtime value-rejection path dispatches on String values, and the typecheck literal-expression path dispatches on String literals. Diagnostics keep the constraint name verbatim (`length > 0`, `length.isBetween`, `matches`, `!matches`, etc.) so the rejection message reads back to the original source shape.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077, PKL-081
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **String unicode and codepoint methods** (minor) — verifies: PKL-122 — tags: stdlib, string, unicode
  > Surrogate-pair aware String access. `String.length` keeps the existing UTF-16 code-unit semantics (so the fixture baseline stays byte-identical), but three new properties surface the Unicode code-point view: `String.codePointCount: Int` (count of full code points), `String.codePoints: Listing<Int>` (code-point integers), `String.chars: Listing<String>` (single-character Strings split on code-point boundaries). `String.codePointAt(i: Int): Int` indexes the code-point stream; out-of-range pushes a diagnostic. All three iterate via MoonBit's `String::iter` which already yields full code-point `Char` values, so supplementary-plane characters (`🍣`, U+1F363) collapse to a single element instead of leaking the surrogate pair.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-077
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **URI imports via https with mizchi/x/http** — verifies: PKL-129 — tags: parser, imports, sandbox, pkf-pkspec
  > `import "https://..."` and the entry-point path resolve through `mizchi/x/http.get` running under a `moonbitlang/async` event loop. The CLI's `main` is now `async fn main`, so `load_path` can await the fetch directly — no `run_async_main` wrapper / Ref-capture dance. Both native and JS targets ship a working fetcher (mizchi/x supplies a socket-backed implementation on native and a `fetch`-backed one on JS, both behind the same `@http.get` surface). The WASM target prints a clear diagnostic — WASI support is the follow-up. `package://` URIs (Apple Pkl's registry protocol — zipball metadata + per-file path fragments) are recognised by the dispatcher but always raise; pointing the import at the raw GitHub URL is the workaround until that slice lands.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-006
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **YAML literal block scalars** (minor) — verifies: PKL-125 — tags: renderer, yaml, block-scalar
  > Multiline String values render as YAML literal block scalars (`|`, `|-`, `|+`) in block contexts (mapping value position after `key:` and sequence item position after `- `). The chomping indicator follows the trailing-newline count: exactly one trailing `\n` clips with `|`, zero strips with `|-`, two or more keep with `|+` (the natural newline after the last content line covers one of the kept newlines and `(trailing - 1)` bare newlines preserve the rest). Eligibility requires at least one internal newline (single-line strings stay inline), no control characters other than `\n` / `\t`, and no content line starting with whitespace (which would otherwise force an explicit `|N` indentation indicator). Ineligible strings fall back to the existing double-quoted form. Top-level scalar strings (no parent key / sequence) keep the double-quoted form for byte-identity with the pre-PKL-125 fixture baseline.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-073
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **allow Pkl class property defaults to satisfy missing members** — verifies: PKL-035 — tags: typechecker
  > Assignments to declared class types accept object literals that omit class properties with defaults, while still requiring properties without annotations or defaults.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-034
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **amend chain plus multi-line union typealias plus listing element append** (minor) — verifies: PKL-148ap — tags: parser, evaluator, upstream, compat
  > Three small parser / eval fixes that share the goal of shrinking the `unsupported expression` class without yet picking up a flippable fixture. (1) Multi-line typealias union: Apple Pkl allows the body of a `typealias A = ...` to wrap onto a continuation line whose first significant token is `|` (`typealias A =\n  "a"\n  | "b"\n  | "c"`). `parse_type_text` previously broke at any top-level separator, so the newline after `"a"` ended the type and the leading `|` on the next line became a syntactic dangling token. The fix peeks past the separator run: if the next significant token is `|`, the type-text walker swallows the separators and keeps collecting. (2) Amend chain at module-level property AND object-member positions: `foo { body1 } { body2 }` chains additional brace bodies onto the same property as successive `AmendExpr` layers. Apple Pkl's `foo { bar { "Hello" } } { bar { "World" } }` is parsed identically to `foo = AmendExpr(AmendExpr(<body1>, <body2>))`. The `parse_inferred_new_body` call inside `parse_property_decl` / `parse_object_member` is followed by a `while at(lbrace())` loop that wraps the running value in another `AmendExpr` per trailing brace. (3) Bare scalar element in a listing-amend body: `(listing) { "x"; "y" }` now appends one element per scalar. `eval_listing_subscript_amend` previously expected the `@element$` payload to evaluate to a Listing / List / Set (for spread-style splice) and the `Some(_) => ()` catch-all silently dropped scalars; the new arm checks the name prefix and pushes the scalar verbatim. No PCF count change — basic/amendsChains still stalls on predicate-member `[[ pred ]] { ... }` and on the implicit-amend-on-same-name semantic where `bar { ... }` (no `=`) inside an object body should amend the prior `bar` rather than override; that piece is a separate slice because it requires either an `AmendExpr(Identifier(name), body)` wrap at parse time (with a graceful fallback when no prior binding exists) or a metadata flag on ObjectMember that `merge_value_members` can read. `unsupported expression` class shrinks 24 → 23 (classes/unionTypesErrorAlias drops out).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ao
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **amends base module property and type merge** — verifies: PKL-137 — tags: evaluator, typechecker, amends, pkf-pkspec
  > `amends "base.pkl"` / `extends "base.pkl"` flows the base module's typealiases and class declarations into the child's unqualified type scope, in addition to the property values that PKL-006 already merged at eval time. (1) `infer_program` resolves `program.module_relation`, calls `resolve_import_types(relation.uri)`, and seeds the child's `type_env` with the base's `TypeExport`s so a bare `Test` annotation in the child resolves to the base's `class Test`. (2) `type_exports_from_parse_result` now exports `TypeAliasDeclaration`s alongside `ClassDeclaration`s. (3) `collect_declared_types_with_imports` falls back to `type_from_annotation` (not just `builtin_type_from_annotation`) so union / constrained / nullable alias targets resolve. (4) `type_from_annotation` strips a balanced outer paren wrapper before dispatch so target text like `("draft" | "review" | "approved")` splits correctly. (5) `builtin_type_from_annotation` recognises a quoted string literal in type position as `StringType` so string-literal union types (`"critical" | "major" | "minor"`) resolve. (6) `type_accepts` admits an empty `ObjectType([])` against `ListingType(_)` / `MappingType(_)`. (7) `parse_property_decl` routes a brace-bodied amend (`tests { entry }`) through `parse_inferred_new_body` so the body shape follows the first significant token.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-006, PKL-118, PKL-138
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **annotation class capture** (minor) — verifies: PKL-128d — tags: parser, annotation, pkldoc, codegen
  > Annotations preceding a `module` / `class` / `function` / `typealias` declaration are captured into the AST as `Annotation { class_name, body_kind, body_text }` records. Three body forms are recognised: bare (`@Deprecated`), parenthesised (`@Deprecated("...")`), and braced (`@ModuleInfo { minPklVersion = "..." }`); the verbatim body text between the delimiters is preserved so a downstream tool (pkldoc / codegen) can re-parse the arguments without scanning back to the open token. The parser keeps a `pending_annotations` buffer on `Parser` that `skip_member_header` fills and each decl parser drains via `take_pending_annotations`; bindings / properties that don't capture annotations simply leave the buffer to be cleared by the next header pass. Evaluation is unaffected — annotations are pure metadata. The CLI's `parse` subcommand prints a one-line summary per captured annotation so pkldoc / codegen pipelines can consume the metadata without linking against the AST directly.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-128a, PKL-128b, PKL-128c
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **as and pipe operator runtime semantics** [draft] — verifies: PKL-150 — tags: evaluator, operator, upstream, compat
  > PKL-148n landed the foundational pieces (`as` strips the trailing constraint and generic head so `Set(...) as Set<Listing<Int>>` accepts the outer SetValue; `|>` already projects Apple Pkl's diagnostic for non-callable RHS via PKL-148k; `local NAME = EXPR` inside Listing bodies now desugars into a `WhenSpread(let(...) body)` chain so the `basic/as*` fixtures' inline locals parse through). The remaining work needed before `basic/as`, `basic/as2`, `basic/as3`, and `lambdas/pipeOperator` byte-match the gold: (1) `pkl:test.catch` / `catchOrNull` currently runs the no-throw branch but returns the wrapped value uncasted — Apple Pkl returns the value as-is and the surrounding `== null` / pcf-render comparison drives the example output (needs the lambda body to evaluate THROUGH the lambda before catch decides whether to surface the result or the diagnostic); (2) per-element constraint deferral — `Set(new Listing { 'one' }) as Set<Listing<Int>>` accepts the outer SetValue at cast time, but reading `s2.first[0]` must fire the inner `Listing<Int>` constraint against the actual `String` element, requiring constraint storage on the cast value or a wrapper that knows its declared inner type; (3) the class-aware ObjectValue refactor (PKL-148m parent dep — `pipeOperator` res11 needs `new Person {}` to render with its class identity so the diagnostic projects `pipeOperator#Person` instead of bare `Object`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148n
  - body: _not yet implemented_

- [ ] **as cast accepts generic-wrapped heads and local bindings inside listing bodies** (minor) — verifies: PKL-148n — tags: evaluator, parser, operator, upstream, compat
  > Two infrastructure changes for the asAndPipeRuntime (PKL-150) work cluster, both gating the upstream `basic/as*` fixtures. (1) The `as` operator (Apple Pkl's runtime type cast) ran its acceptance check on the raw type-name string, so `Set(...) as Set<Listing<Int>>` rejected upfront with `Expected value of type `Set<Listing<Int>>`, but got type `Set`.` even though the outer Set shape was correct — Apple Pkl's runtime treats `as` as shape-preserving at the outermost head, with per-element constraint mismatches surfacing only when the inner values are read. Mirrors PKL-148l's generic-head strip (`pkl_constrained_type_base_name` then `name.find("<")`) so the cast check matches Apple Pkl semantics, and also threads `value_satisfies_user_class_annotation` so `value as MyClass<T>` round-trips. (2) `local NAME = EXPR` declarations interleaved with element expressions inside a Listing body (e.g., `examples { ["set of listing"] { local s1 = Set(...) as Set<Listing<Int>>; s1.first[0]; module.catchOrNull(() -> s1.first) == null } }` from `basic/as3`) were silently dropped by `parse_listing_body` (the catch-all `skip_unknown_member` ate the entire declaration), so any element after a local rendered as nothing. The parser now captures each body item as either an Element or a LocalBinding and desugars the chain into nested `let` expressions wrapped by `WhenSpread` (each `local` opens a fresh CallExpr(LambdaExpr, …) whose body is the recursively-desugared remainder; the resulting ListingValue spreads back into the parent so the binding stays transparent at render time). `parse_inferred_new_body` also gained a look-ahead helper (`skip_local_decls_from`) so an inferred body that leads with `local …` is dispatched to the listing parser when subsequent items are bare expressions, instead of always picking the object-body branch. Coverage counter doesn't move on this slice alone — the affected fixtures (`basic/as`, `basic/as2`, `basic/as3`) need follow-up work on `pkl:test.catch` / `catchOrNull` (currently the non-throw branch returns the value uncasted) and on per-element constraint deferral. The PKL-152 (`anyTypeCoercion`) roadmap entry is also retired here — `Any` already accepts every runtime value via `eval_value_accepts_type_annotation`'s `("Any", _) => true` arm (PKL-148e), so no separate slice is needed.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148m
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **at-prefix local dep import resolution** (minor) — verifies: PKL-148ad — tags: loader, sandbox, upstream, compat
  > Apple Pkl's `import "@<dep>/<rest>"` resolves the `<dep>` short-name through the nearest ancestor `PklProject.deps.json` file. For local-type deps (`type: "local"`, `path: "../packageWithSpaces/"`) the importer combines the PklProject directory with the entry's `path` and the import's remainder to land on a regular file. pkl-mbt's `resolve_import_path` had no `@`-prefix arm, so the loader joined `<from_dir>/@<dep>/<rest>` as if it were a relative path and the read failed with `Cannot find module`. The fix adds `resolve_at_prefix_dep` in the CLI loader: walk `from` upward looking for `PklProject.deps.json`, JSON-parse it via `@json.parse`, scan `resolvedDependencies` for an entry whose key path-tail (`package://host/<dep>@<v>` → `<dep>`) matches the import's `<dep>`, and when the entry is `local`-type combine the PklProject directory with `dep.path + rest` to produce the absolute path. The resolution is then registered in the sandbox cache (reusing the triple-dot registry from PKL-148r), and `analysis.mbt`'s resolve_import_path consults the same cache for `@`-prefix URIs so the IO-free eval-side lookup lands on the same file. Remote-type deps (`type: "remote"`) return None — package download (`pkl download-package` equivalent) is parked in PKL-129 and the fixture-side coverage stays None. +1 fixture (`projects/project7/spacesInImport`), 130 → 131; projects category 36.8% → 42.1%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148r
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **call-site generic inference** — verifies: PKL-110 — tags: typechecker, generics, inference
  > The typechecker propagates concrete types through generic function calls and class literals. Each `ClassDecl.type_parameters` / `FunctionDecl.type_parameters` entry binds to a new `TypeVariable(name)` variant in the typecheck `Type` enum (previously `UnknownType`). At every call site (`infer_lambda_application` and `infer_function_type_call`) the typechecker walks parameter / argument pairs through `unify_for_substitution`, building a `TypeSubstitution` table that records `TypeVariable("T") := <concrete>` bindings. `substitute_type` then rewrites the inferred return type, the parameter cache entries, and the declared return annotation so the call's result has the concrete type — `identity(7)` typechecks as `Int`, so `identity(7) + 1` succeeds while `identity("hi") + 1` rejects with `operator + expects Int operands`. The class literal path in `apply_type_annotation` does the symmetric move: when the expected `ClassType` still carries TypeVariable members and the inferred `ObjectType` carries concrete member types, `substitute_class_type_variables` unifies and rewrites the class type before returning, so downstream field accesses (`intBox.value`) resolve to the substituted member type. `type_accepts` treats `TypeVariable(_)` on either side as accept-any during the structural pass so unification can run without false rejection; the substitution table is the diagnostic surface. Generic class declarations whose body uses are exhausted at scope exit (e.g. a function body that references T but is never called) still typecheck — the variable simply stays free and renders as its parameter name.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-089, PKL-090
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **callable arg type rejection walks collection elements** (minor) — verifies: PKL-148af — tags: evaluator, constraints, upstream, compat
  > Apple Pkl's callable parameter type check walks the element type for `List<X>` / `Listing<X>` / `Set<X>` / `Map<K, V>` / `Mapping<K, V>` arguments even when the head accepts: `f3(List("foo", 42))` against `x: List<String>` rejects element `42` with `"Expected value of type \\`String\\`, but got type \\`Int\\`. Value: 42"`. pkl-mbt's `eval_callable_argument_type_rejection_message` accepted the head (`List` matched `eval_value_accepts_type_annotation` for ListValue) and returned None — so the element-type mismatch never surfaced; only constraint-side element walks (PKL-148ae) actually fired the per-element cascade. The fix folds the element / entry walk into the type-rejection arm right after `union_accepted`: strip the resolved type's outer constraint via `pkl_constrained_type_base_name`, then try `Listing` / `List` / `Set` and `Mapping` / `Map` prefixes via `generic_argument_text`. For matching collection values, recurse into `eval_callable_argument_type_rejection_message` per element / per (key, value) entry; the first violation surfaces and the rest are silenced (Apple Pkl's fail-fast diag order). +1 fixture (`basic/localTypedModuleMember`), 132 → 133; basic category 43.0% → 44.2%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ae
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **callable return / argument type checks resolve aliases generics and unions** (minor) — verifies: PKL-148t — tags: evaluator, typecheck, upstream, compat
  > Apple Pkl's function-parameter and function-return type checks resolve type aliases (`typealias Parameterized = List<String>`), strip the outermost generic head before the value-side acceptance check, and split top-level unions (`typealias Union = Int|Boolean`) into alternative choices. pkl-mbt's `eval_callable_return_rejection_message` was running the resolved alias through `eval_value_accepts_type_annotation` directly — `List<String>` didn't match any arm (which key on bare names like `List`), so functions declared with aliased generic return types (`function l(l: List<String(!isEmpty)>): List<String(!isEmpty)> = l`) wrongly rejected every valid return value. The argument-side check had the generic-head strip but lacked union splitting. Both sites now share the same shape: split on top-level `|` via `split_top_level_union_choices`, strip each choice's `(...)` constraint, strip its outermost `<...>` generic head, then accept if any choice matches either the builtin acceptance set or the user-class annotation cascade. PKL-148t also addresses a separate `qux = qux(...)` shadow case: when a property binding's RHS self-references the same name but a sibling module-level `function` shares it, `resolve_binding_value` now falls through to the function-shaped binding before surfacing the cycle diagnostic (the property `qux` and function `qux` live in different namespaces in Apple Pkl's lexical model). +1 fixture (`methods/methodParameterConstraints1`), 115 → 116; methods category 40% → 60%. The remaining typeAlias* fixtures stay gated on per-property lazy class instantiation (each `test.catch(() -> bad.res13)` should isolate that one property's check rather than re-evaluating all 12 properties on `new Bad {}`) — separate slice.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148s
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **catchOrNull wiring catch no-throw wording bare callable constraint diagnostic** (minor) — verifies: PKL-148o — tags: evaluator, diagnostics, upstream, compat
  > Three Apple-Pkl alignment fixes that share a code path (`pkl:test.catch` / `catchOrNull` plus the callable-parameter constraint diagnostic). (1) `module.catchOrNull(() -> ...)` / `test.catchOrNull(() -> ...)` wasn't wired into the CallExpr intercept — the snippetTest examples blocks lean on `catchOrNull(...) == null` to project Boolean throw-vs-no-throw, but pkl-mbt's eval surfaced `Cannot find property catchOrNull`. (2) `catch(fun)` on a non-throwing lambda returned the rendered value as a string instead of throwing — Apple Pkl's `TestNodes.catchMethod.eval` raises `expectedAnException` (`Expected an exception, but none was thrown.`) when the lambda exits normally. (3) The callable-parameter constraint check (`function add(n: Int(isPositive)) = n`, `class X { function int(int: Int(isPositive)) = int }`, etc.) wrapped its bare upstream message (`Type constraint isPositive violated. Value: -1`) with a `<label> argument N` prefix at all three eval entry points (`eval_lambda_application`, `apply_function_value`, class-method dispatch in `eval_member_access_call`), producing `function f argument 1 Type constraint isPositive violated. Value: -1` — Apple Pkl emits the bare form per its `errorMessages.properties#typeConstraintViolated` entry. New shared `pkl_test_catch_form_kind` predicate plus a `PklTestCatchOutcome` enum split keeps the binding-time intercept's catch / catchOrNull dispatch clean, the prefix wrapper is dropped at every eval call site (the typecheck-side wording in `typecheck.mbt` is unaffected), and four affected unit tests get their expected messages updated to the upstream-aligned bare form. No gold-match flip from this slice alone — the `basic/as*` and `methods/methodParameterConstraints2` fixtures that exercise these paths still need the broader per-element constraint deferral (`Set(...) as Set<Listing<Int>>` element access) and runtime constraint expression eval for lambdas with closures (`length > n` against a captured `n`), both deferred to PKL-148m (the super-late-bind cluster).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148n
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **class methods bare-name resolution in class default body** (minor) — verifies: PKL-148ab — tags: evaluator, upstream, compat
  > Apple Pkl's `class Foo { local function f() = "original"; x = f() }` calls `f()` bare from a property default — resolution walks the class's own lexical method set (no `this` dispatch needed, `local` modifier doesn't alter the bare-name reachability inside the declaring class). pkl-mbt parsed class methods into `ClassDecl.methods` but never injected them as Identifier-resolvable bindings, so `f()` fell through `Cannot find property \`f\`.`. `eval_class_default_members` now collects the class's own methods alongside the parent's recursive `base_values`, then pushes each method as a `FunctionValue` into the same `defaults_cache` it threads into `eval_object_members_with_options`. Each `FunctionValue.captured_env` references the live `defaults_cache` (no copy), so when one method calls another mutual-recursively, the lookup at call time sees every sibling pushed before the call. Lexical (not virtual) scoping: the recursive `eval_class_default_members("Foo1", ...)` pushes Foo1's methods during Foo1's defaults evaluation, then back at Foo2's layer pushes Foo2's methods — so `Foo1.x = f()` always resolves to Foo1's `f` (Apple Pkl's expected behaviour), and a Foo2-defined property would resolve to Foo2's `f`. +3 fixtures (`basic/localMethodOverride1` / `localMethodOverride2` / `localMethodTyped4`), 124 → 127; basic category 39.5% → 43.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148aa
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **class parent typealias resolved through alias chain** (minor) — verifies: PKL-148v — tags: evaluator, typecheck, upstream, compat
  > Apple Pkl walks the type-alias chain when looking up the parent class for default inheritance — `class Baz extends Bar` where `typealias Bar = Foo` resolves to `Foo`'s declarations for the default-property surface, so `new Baz {}.value` reads through to the `value: Int = 42` declared on `Foo`. pkl-mbt's `eval_class_default_members` recursed on `class_binding.parent_name` directly through `lookup_class_binding`; since `Bar` is a typealias not a class binding, the lookup returned None and `Baz` lost every inherited property. The fix is a one-spot alias resolve: when the parent_name is set, run it through `eval_resolved_type_alias` before the recursive class-default lookup. +1 fixture (`types/typeAlias2`), 118 → 119; types category 29.4% → 35.3%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148u
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **class-as-value reflect mirror plus lexical scope walk** — verifies: PKL-148d — tags: evaluator, scope, amend, upstream, compat
  > Adds class-as-value semantics — a bare class identifier (`Person`) projects to a `pkl:reflect.Class` mirror; member access on the mirror reports `Cannot find property \\\\\\\`X\\\\\\\` in object of type \\\\\\\`Class\\\\\\\`.` and call-form access reports `Cannot find method \\\\\\\`X\\\\\\\` in class \\\\\\\`Class\\\\\\\`.`. Lexical scope now wins over module-level bindings: `resolve_binding_value` checks `env` before the module's `bindings` / `cache`, and `eval_object_members` hoists each prior member (including `local` properties whose `@hidden$` prefix gets stripped during the hoist) into a per-field env so a nested `bar { x = 2; y = x + 3 }` resolves `x` to the inner `2` rather than the enclosing `foo.x = 1` or module-level `x = 0`. Amend operations now deep-merge ObjectValue members rather than wholesale-replacing them — `(x) { foo { bar { num1 = 11 } } }` keeps `foo.bar.num2` and `foo.baz` from the base. Constraint diagnostics that quote a class-typed value render with the host class name (`new Address { street = "Garlic Blvd." }` rather than the multi-line PCF block form). Lifts gold-match from 43 to 50 PCF (`basic/localProperty1`, `basic/localPropertyOverride3`, `classes/class4`, `classes/constraints3`, `objects/configureObjectAssign`, `objects/implicitReceiver1`, `objects/implicitReceiver2`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148c
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **cli format subcommand** — verifies: PKL-099 — tags: cli, renderer, format
  > `moon run cmd/mpkl -- format <file>` parses and evaluates the source through the existing `AnalysisSession`, then re-emits the resolved module via the PCF renderer. Whitespace and indentation collapse to the renderer's canonical form (`name = "hawk"`, two-space indent inside blocks, separator after `=`). Parse failures and evaluation failures short-circuit with the diagnostic surface used by the other CLI subcommands. The first cut deliberately operates on the evaluated module value rather than the CST, so default values from class declarations and amend chains land in the output; a trivia-preserving idempotent formatter (`render_cst_with_comments`) is a follow-up that reuses the existing CST infrastructure.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-070
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **cli sandbox flags** — verifies: PKL-106 — tags: cli, sandbox
  > Three CLI flags configure the sandbox surface that `read` / `import` consult: `-p NAME=VALUE` (repeatable) populates the `prop:` resolver and lifts `read("prop:NAME")` into the allow-list alongside `env:`; `--module-path <dir>` (repeatable) appends directories the loader searches when an unqualified import URI misses the working directory; `--allowed-modules <pipe-separated-prefixes>` overwrites a per-scheme allow-list that the loader enforces against import URIs. The allow-list applies only to URIs carrying a `scheme:` prefix (`pkl:`, `https:`, `package:`, etc.) — bare filesystem paths bypass the check so the entrypoint and locally-rooted imports don't have to be re-spelled into the pattern. Configuration is captured in module-level mutable state via `configure_sandbox_props` / `configure_sandbox_allowed_modules` / `configure_sandbox_module_paths`; the CLI installs the values once at startup before any evaluation runs, and the evaluator reads them through `sandbox_lookup_prop` / `sandbox_is_module_allowed` / `sandbox_module_paths`. Missing `prop:` reads surface `read: prop <NAME> is not set` (parallel to the existing `read: env variable <NAME> is not set`); disallowed module URIs surface `module <uri> is not allowed by --allowed-modules` at the loader boundary.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-098
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **constraint cascade extends to List Map Optional element walks** (minor) — verifies: PKL-148ae — tags: evaluator, constraints, upstream, compat
  > Apple Pkl's class-method parameter / return constraint cascade walks element-level predicates for `List<X(...)>`, `Map<K(...), V(...)>`, and the inner type of `T(...)?` nullable wrappers — and the return-side diagnostic shape mirrors the parameter side without the `<call-site label> return` prefix. pkl-mbt missed four pieces that together blocked `methods/methodParameterConstraints2` (7 lines of DIFF). (1) `eval_callable_return_rejection_message` was prepending `\\{label} return ` to the constraint message; Apple Pkl emits the bare message (matches the parameter-side already aligned by PKL-148o). (2) `pkl_collection_element_rejection_message_from_source` only matched `Listing<X>` / `Mapping<K, V>` source names — `List<X>` and `Map<K, V>` arguments / returns fell through with no element check. The helper now strips the top-level `(<...>)` constraint via `pkl_constrained_type_base_name` and then tries `Listing`, `List`, `Mapping`, and `Map` prefixes in turn; the List branch also walks `SetValue` so the same cascade catches `Set<X(...)>`. (3) Nullable-wrapped constrained types (`String(!isEmpty)?` / `Int(isPositive)?`) had their constraint cascade silently bypassed because `pkl_constrained_type_base_name` returns None when the source ends with `?`. The cascade now strips a trailing `?` recursively (NullValue passes; non-null values dispatch through the inner type). (4) `isEmpty` / `!isEmpty` on `String` weren't in the predicate set — only `length.isEmpty` / `length.isPositive` forms were recognised. Two new variants `StringIsEmpty` / `NotStringIsEmpty` join the set with bare `isEmpty` / `!isEmpty` (also matches `this.isEmpty`) so the constraint name renders verbatim. +1 fixture (`methods/methodParameterConstraints2`), 131 → 132; methods category 60.0% → 80.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ad
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **constraint predicate composition** (minor) — verifies: PKL-128c — tags: parser, constraints
  > Multi-argument constraint annotations like `Int(isPositive, isLessThan(10))` already split into per-predicate parts; this slice adds whitespace trimming so each part is dispatched with the surrounding spaces stripped (`pkl_int_constraint_predicate` no longer needs to defend against leading / trailing tabs). The lone-`&` predicate-composition form that some Pkl-adjacent dialects use isn't part of upstream Apple Pkl syntax — its formatter rejects `&` here — so this slice intentionally stops at the comma-separated form Apple Pkl supports.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-076
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **cross-module typecheck round-trip completeness** — verifies: PKL-118 — tags: typechecker, imports, pkf-pkspec
  > Module-level `function name(params) = body` declarations now participate in cross-module lookup. An importing module reaches them as `<Import>.<name>` at both the eval layer (the call dispatches the lambda body against the supplied arguments) and the typecheck layer (the function's signature flows through the same `infer_expr_with_bindings` path as a local lambda, so argument type errors surface with the precision a local call would have). The implementation pushes each module-level function as a hidden-prefixed member on the module's `ObjectValue` (eval) and `ObjectType` (typecheck); `render_value`'s existing skip for `is_hidden_member_name` keeps the rendered output unchanged. `AnalysisSession::eval_path`, `eval_source`, and `typecheck_source` strip the hidden entries at their return boundary so the existing test corpus (which asserts on visible-binding equality) keeps passing — only the internal cross-module dispatch sees the full shape. Today's slice covers module-level functions only; imported class definitions, type aliases, and constraint annotations already flow through PKL-006 / PKL-137's earlier work and `qualify_imported_type` (`<Import>.<TypeName>`); a future tightening can layer in cross-module abstract-method coverage once an embedded use case exercises it.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-006
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **deferred property error sentinel hides from output and fires on bare identifier reads** (minor) — verifies: PKL-148ak — tags: evaluator, diagnostics, upstream, compat
  > Apple Pkl evaluates class-default property bodies lazily: a typed local whose RHS violates the annotation (`local p2: Int = "foo"`) doesn't fail the surrounding class — the rejection is deferred and only raised when the property is actually read, so `test.catch(() -> p2)` captures the diagnostic message verbatim while siblings that never touch `p2` evaluate cleanly. pkl-mbt's `defer_property_errors` mode (PKL-148u) already stamps a `@error$<stored>` sentinel next to each rejected member, but the wiring was one-sided. The sentinel had no invisibility marker, so the PCF renderer projected entries like `@error$@local$p2 = "Expected value of type \`Int\`, but got type \`String\`. Value: \"foo\""` next to the legitimate `res*` members. And `local` member hoisting only pushed the bare name + (type-invalid) value into the per-field `local_env`; an Identifier reference to `p2` from a sibling — including the lambda body of `test.catch(() -> p2)` — read the value silently with no diagnostic, so `test.catch` reported `Expected an exception, but none was thrown.` instead of the gold message. Three coordinated changes. (1) Moved the `@error$` prefix out of `eval.mbt` into `parser.mbt` (`error_member_prefix` / `error_member_name` / `is_error_member_name`) and extended `is_invisible_member_name` to include it, so every existing renderer / equality / iteration site picks up the filter without per-site touch-ups. (2) `eval_object_members`'s hoisting loop now recognises `@error$<stored>` entries and re-emits them as `@error$<bare>` env bindings (with whatever inner visibility prefix stripped), so the sentinel sits in env alongside the bare-name value. (3) `eval_expr_with_bindings`'s Identifier arm checks `lookup_value(env, error_member_name(name))` first; when present it pushes the message and returns None, mirroring the `lookup_pending_error_message` short-circuit that the member-access arm already runs. Lambdas closed over the env (including the `test.catch(() -> p2)` body) see the same intercept. +1 fixture (`basic/localTypedClassMember`), 143 → 144; basic category 55.8% → 57.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148aj
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **diagnostic message text upstream alignment** — verifies: PKL-108 — tags: diagnostics, compatibility
  > First-line phrasing for the most common diagnostic families now matches Apple Pkl's wording verbatim: `Cannot find property \`<name>\`.`, `Cannot find property \`<name>\` in object of type \`<Type>\`.`, `Cannot find method \`<name>\` in object of type \`<Type>\`.`, `Cannot find type \`<name>\`.`, `Cannot find module \`<uri>\`.`. The alignment covers `unbound identifier`, `unknown member`, `unknown <Type> property / method` (Listing / Mapping / String / Int / Float / Duration / DataSize / Regex / Bytes), `unknown type annotation`, and `unresolved import` — both inside the evaluator and at the loader boundary that bails on missing imports before evaluation runs. Source-position arrows and value-trace blocks (the multi-line decoration around the first-line message in Apple Pkl's `.err` fixtures) stay deferred; pinning the first line is enough for an upstream-error-fixture sweep to diff against without false positives from prose differences.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-107
  - decisions: 3 entry(ies)
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

- [ ] **equality typecheck operand match** (minor) — verifies: PKL-113 — tags: typechecker, equality
  > The typechecker rejects `==` and `!=` when the operand types are statically distinct. Today's typechecker returned BoolType unconditionally, so `5 == "hi"` and `true != 3` typechecked clean and only failed at runtime (or rather, silently returned `false`). The new pass routes through a dedicated `equality_compatible(left, right)` helper that admits the wider compatibility relation Apple Pkl exhibits for equality: numeric mix (Int vs Float, e.g. `1 == 1.0` is `true` in upstream), nullable / non-null match (`name: String? = null; name == null`), same-name `ClassType` pairs, structural `ObjectType` / `ListingType` / `MappingType` matches, and any pair where either side is `UnknownType` or a free `TypeVariable(_)`. `ConstrainedType` / `DefaultedType` wrappers are stripped via `equality_unwrap_type` before the case match so `Int(isPositive) == 5` still compares as `Int == Int`. `UnionType` flows through the existing fan-out: a union accepts the other side if any of its options does. The helper is symmetric — both `5 == "hi"` and `"hi" == 5` raise `operator == expects operands of matching types`, and the same wording is reused for `!=`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-004
  - decisions: 4 entry(ies)
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

- [ ] **generic class declarations** — verifies: PKL-089 — tags: typechecker, generics, class
  > `class Box<T> { value: T }` and `class Pair<A, B> { first: A; second: B }` parse, typecheck, and evaluate. The parser recognizes the optional `<T1, T2, ...>` list immediately after the class name and stores the parameter names on `ClassDecl.type_parameters`. The typechecker injects each parameter into a class-scoped `type_env` as a binding to `UnknownType`, so body uses of `T` route through the existing unknown-but-tolerated annotation path rather than failing as 'unknown type annotation'. Parent-name lookup (`extends`) and method-body validation also receive the scoped env so a parameter visible in a property type stays visible on a method signature. The evaluator is unchanged: type parameters are a typechecker-only construct in this slice, so instantiating `new Box { value = 5 }` produces an `ObjectValue` whose `value` member carries the actual runtime value. Instantiation-time T-binding (where the typechecker would propagate `Int` through `b.value` after `new Box { value = 5 }`) stays deferred — that lands together with PKL-090's call-site inference.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **generic function type parameters** — verifies: PKL-090 — tags: typechecker, evaluator, generics, callable
  > `function identity<T>(x: T): T = x` and `function pair_first<A, B>(a: A, b: B): A = a` parse, typecheck, and evaluate. The parser captures the optional `<T1, T2, ...>` list immediately after the function name on `FunctionDecl.type_parameters`. The module-level `collect_declared_types_with_imports` flattens each function's parameters into the shared `type_env` as `UnknownType` bindings so body uses of `T` resolve without the 'unknown type annotation' diagnostic. The evaluator gains a `eval_type_name_is_type_parameter` short-circuit on both the callable-argument and callable-return validators: when the declared `type_name` matches any class or function type parameter, runtime annotation rejection is skipped wholesale (the parameter accepts any value). Call-site inference of T from the argument type stays deferred — `identity(42)` evaluates to `IntValue(42)` because the body is a literal pass-through, not because the typechecker propagated `Int` through `T`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-089
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **generic typealias instantiation** — verifies: PKL-115 — tags: parser, typechecker, typealias, generics
  > `typealias Box<T> = Listing<T>` parses and binds T in the target text. At an instantiation site like `Box<Int>`, the typechecker looks up the alias binding for `Box`, matches its declared type parameters against the provided arguments, substitutes the parameter names in the recorded target text, and re-evaluates the resulting type. `b: Box<Int> = new Listing { 1; 2; 3 }` typechecks (the target rewrites to `Listing<Int>`), `b: Box<Int> = new Listing { "a"; "b" }` rejects (Int-element listing expected, String elements found). Multi-parameter aliases (`typealias Pair<K, V> = Mapping<K, V>`) work the same way — parameters substitute positionally. The substitution pass is textual (`is_typealias_identifier_start` / `_continue` walks the target string and replaces full identifier tokens that match a parameter name); generic alias bindings carry the original `TypeAliasDecl` on a new `alias_decl: TypeAliasDecl?` field on `TypeBinding` so the use-site rewriter does not need to re-walk the declarations array. Non-generic aliases keep `alias_decl = None` and the previous resolution path unchanged.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-110
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **hidden and local object members** — verifies: PKL-087 — tags: evaluator, renderer, object
  > Object-body members declared with the `hidden` modifier or the `local` keyword are kept inside the evaluated `ObjectValue` (so `lookup_member` still resolves bare-name reads against them) but are skipped by every renderer (PCF / JSON / YAML / Properties). Module-level `hidden` bindings get the same render-side filter; module-level `local` already routed through `parse_local_decl`, which marks the binding `exported: false` so the renderer never sees it in the first place. The render filter is a single `visible_members` projection applied at the entry of each renderer's member loop, keyed off a reserved `@hidden$` name prefix that the lexer rejects as an identifier character so it cannot collide with user-declared properties.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-070, PKL-071, PKL-072, PKL-073, PKL-074
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **hidden class property modifier** — verifies: PKL-145 — tags: parser, evaluator, stdlib
  > The `hidden` member modifier now applies to class-property declarations, not just object-body members. `parse_class_property_decl` calls a new `take_pending_hidden` drainer that pulls the `hidden` token out of the `pending_modifiers` list `skip_member_header` populated, then wraps the stored property name with `hidden_member_name` (the same `@hidden$` prefix the object-body path uses). Lookups (`b.marker`) resolve through the bidirectional bare/prefixed `lookup_member` path; renderers skip the prefixed entry via `visible_members`. PKL-144's `pkl:json.Parser` synthetic source flips its `__kind = "JsonParser"` marker to a `hidden __kind` class property so the detection routes through the same `reflect_kind` helper that pkl:reflect mirrors use — replacing the shape-based fallback (`useMapping` slot present) with a structural marker check.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-098, PKL-144
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **infer Pkl class property default types** — verifies: PKL-034 — tags: typechecker
  > Class declarations use property default expressions as member type contracts when no explicit annotation is present, so assignments to declared class types still reject incompatible object members.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-019, PKL-022
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **inheritance dispatch hardening remaining** — verifies: PKL-117 — tags: typechecker, inheritance
  > The typechecker now enforces two structural inheritance rules on every locally-declared class. (1) Abstract method coverage: a concrete (non-`abstract`) class extending an ancestor chain that contains at least one `abstract function` must provide an override for every such method — through its own `methods` array or through some intermediate concrete ancestor between the abstract declaration and itself. Missing coverage surfaces as `Class \`<name>\` does not implement abstract method \`<name>\` inherited from \`<parent>\`.`. Abstract classes are exempt — they're explicitly allowed to leave abstract members for downstream concretisation. (2) Override-direction subtype rules: when a child class declares a method with the same name as one declared anywhere in its parent chain, the return type must be covariant (`child_return <: parent_return`) and each parameter type must be contravariant (`parent_param <: child_param`). Violations surface as `Method \`<class>.<name>\` return type \`<child>\` is not a subtype of \`<parent>.<name>\` return type \`<parent_return>\`.` and a parallel parameter form. Both checks walk only locally-declared parents; the imported-parent case still flows through PKL-118's cross-module typecheck round-trip work. The parser captures the `abstract` modifier on both class and function declarations via the same `pending_modifiers` buffer pattern PKL-128d uses for annotations, draining the flag at decl construction so the modifier never leaks between adjacent decls.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040, PKL-117a
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **inventory unsupported syntax in tolerant parser output** — verifies: PKL-016 — tags: parser
  > ParseResult exposes an unsupported_syntax coverage report with source ranges, text, and syntax kind for accepted code that still lowers to UnsupportedExpr.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-015
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **is operator runtime evaluation** (minor) — verifies: PKL-114 — tags: evaluator, is-operator, narrowing
  > The `is` operator evaluates at runtime: `5 is Int` returns `true`, `1.5 is Float` returns `true`, `5 is Number` and `1.5 is Number` both return `true`, `"x" is Int` returns `false`, and `if (x is Int) ...` actually branches on the runtime type of `x` instead of failing with `operator is is parser-only`. The new `value_is_type(value, type_name)` helper in `eval.mbt` mirrors the surface that the typechecker's `type_from_annotation` accepts: union (`String | Int`), nullable (`Float?`), constrained (`Int(isPositive)` strips the predicate and falls back on the base type), and generic (`Listing<Int>` / `Mapping<String, Int>` route to `ListingValue` / `MappingValue` without inspecting elements). User-defined class names fall through to `false` for now — class-instance dispatch needs class tags on `ObjectValue`, which is out of scope for this slice. The typechecker's is-guard narrowing was already generic enough for `Float / Number / TypeVariable` paths via the existing `UnionType` / `NullableType` recursion (PKL-092 widened `Number` to `UnionType([IntType, FloatType])` and PKL-110 made `TypeVariable(_)` accept-any in `type_accepts`), so the scope reduces to the evaluator side.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-092, PKL-110
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **lambda identity equality virtual method dispatch and this.X access** — verifies: PKL-148g — tags: evaluator, equality, dispatch, scope, upstream, compat
  > Closes the next batch of upstream silent-mismatch fixtures. FunctionValue carries an identity stamp (fresh `Int` id generated when a `LambdaExpr` is evaluated or a function declaration is loaded) so structural-only payloads no longer collide under MoonBit's derived `==` — Apple Pkl's identity-based lambda equality (`(() -> 1) == (() -> 1)` is false; `local f = ...; f == f` is true) now round-trips. Sibling class methods are seeded parent-first so the derived class's same-named override wins under `lookup_value`'s last-match rule, fixing virtual dispatch when a method body references another method that's overridden in the subclass. Module-level `local const x = ...` (and any `local <modifier>* x` combination) is parsed as a hidden binding; the modifier keywords were previously stealing the slot for the binding name and the actual identifier was being parsed as a separate property. `this.X` inside an object body short-circuits to `resolve_binding_value` when `X` is in the implicit-receiver scope (siblings / enclosing bindings), letting `bar = this.baz + 1` and `super.X`-free fixtures resolve their cross-references; value-derived properties (`this.abs` on an Int receiver, used by `Int(abs < 100)` after the constraint runtime's implicit-this rewrite) still flow through the standard MemberAccess path. Lifts gold-match from 67 to 72 PCF (`classes/functions1`, `classes/functions4`, `lambdas/equality`, `lambdas/inequality`, `objects/this1`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148f
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **listing amend body tolerates when for spread generator members** (minor) — verifies: PKL-148y — tags: evaluator, upstream, compat
  > Apple Pkl accepts `(listing) { when (cond) {...}; for (...) {...}; ...x; [N] = value }` — generator members (when / for / spread) inside a listing-amend body splice their payload into the running listing before subsequent `[N]` subscripts apply. pkl-mbt's `eval_listing_subscript_amend` only handled `@subscript$<offset>` sentinels and bailed with `object amendment expects Object` on anything else; `listings2/wrongIndex` exercises this exact shape (`when (false) {0}` followed by `[3] = "barn owl"`). The fix extends the per-member loop: when the member is `@when` / `@for` / `@spread` / `@element$<offset>`, evaluate the value and splice the resulting ListingValue / ListValue / SetValue elements onto the end of `result`; NullValue and other empty shapes contribute nothing. Subsequent `@subscript$<offset>` entries see the grown listing, so out-of-range diagnostics still surface against the post-generator length. +1 fixture (`listings2/wrongIndex`), 122 → 123; listings2 category 10.0% → 20.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148x
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **literal-valued class property assignments enforce declared type** — verifies: PKL-148i — tags: evaluator, typechecker, upstream, compat
  > Apple Pkl rejects `new Person { name = 42 }` with `Expected value of type `String`, but got type `Int`. Value: 42` when `Person.name: String`. pkl-mbt's TypedObjectLiteral loop only ran predicate-style constraint checks (`Int(x > 0)` and friends) — bare type annotations silently kept the wrong-shape value. This slice adds `eval_class_property_type_rejection_message` which resolves the declared annotation through type aliases, normalises generic heads (`Listing<X>` → `Listing`, `Mapping<K,V>` → `Mapping`, etc.), and emits Apple Pkl's exact diagnostic text when neither `eval_value_accepts_type_annotation` nor `value_satisfies_user_class_annotation` matches. The check fires only for literal-valued AST nodes (`IntLiteral`, `FloatLiteral`, `StringLiteral`, `BoolLiteral`, `NullLiteral`); free-form expression bodies are deferred until the upstream forward-binding leak (locals from a sibling object literal can resolve into a later body's identifier lookups, e.g. `a8`'s `local x = 1` reaching `c7`'s `age = x`) is fixed separately. `eval_class_property_annotation_with_depth` now walks the parent chain when a subclass declares the property without its own annotation (Person3 → Person.name), so `class Person3 extends Person { name = "Pigeon" }` still inherits the parent's `String` annotation for the rejection. Lifts gold-match from 82 to 96 PCF: 1 fixture (`classes/wrongType5`) is unblocked by the new check; 13 (`errors/baseModule`, `listings2/listing1`, `mappings2/mapping1`, `parser/constraintsTrailingComma`, `parser/trailingCommas`, the `projects/` cluster — `badLocalProject/dog`, `notAProject/@child/theChild`, `notAProject/goodImport`, `packageWithSpaces/module with spaces`, `project6/children/{a,b,c}` — and `types/helpers/someModule`) ride along as free promotions surfaced by the same exhaustive probe pass.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148h
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **local and hidden member visibility split with Collection default** — verifies: PKL-148j — tags: evaluator, parser, renderer, upstream, compat
  > External member access on an ObjectValue must hide `local` declarations (Apple Pkl's `foo.x` where `foo` declares `local x = 2` raises `Cannot find property `x` in object of type `Dynamic`.`) while still resolving `hidden`-modifier properties (`new Box { value = 42 }.marker` returns the hidden default). pkl-mbt previously collapsed both modifiers onto the single `@hidden$` storage prefix, so the visibility distinction was lost — `lookup_member` resolved both forms, and any `lookup_visible_member` filter would either expose locals or hide hidden properties. This slice splits the prefix: `local` declarations are stored under a dedicated `@local$` marker, `hidden` keeps `@hidden$`; `lookup_visible_member` filters only `@local$`, so external `.X` access correctly rejects locals while passing hidden through. A combined `is_invisible_member_name` predicate (either prefix) drives every renderer / analysis / typecheck filter so locals still stay out of PCF output. `strip_member_visibility_prefix` projects either prefix back to the bare name for binding-cache seeding and sibling-env hoisting (handles both 8-char `@hidden$` and 7-char `@local$` lengths). Module-level function declarations are still stored under `@hidden$` and remain reachable via `Base.func` — the external access falls back to a `FunctionValue`-only `lookup_member` after `lookup_visible_member` misses, matching Apple Pkl's cross-module function-export semantics. The Apple Pkl diagnostic wording (`in object of type `Dynamic`.`) replaces the bare `Cannot find property `X`.` form for ObjectValue member-access failures. Also fills the auto-default for `Collection<T>` / `List<T>` typed properties (Apple Pkl renders both as `List()`; the helper had Listing / Mapping / Set / Map but missed those two). Lifts gold-match from 96 to 98 PCF (`basic/localProperty2`, `basic/propertyDefaults`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148i
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **local modifier on class / function / typealias declarations** — verifies: PKL-148m — tags: parser, evaluator, upstream, compat
  > A `local` modifier in front of a `class`, `function`, or `typealias` declaration was silently dropped at parse time — the whole member routed through `skip_unknown_member`, so `local class C { ... }` / `local function f(...): ... = ...` / `local typealias T = Int(this > N)` never reached the declaration list. The downstream symptom was either `Cannot find property ...` on a later reference (`local function` / `local typealias` resolved to nothing) or a stamped-empty ObjectValue (`local class C` was unknown so `new C {}` couldn't pick up the defaults), AND silently bypassing a typealias's runtime constraint (`x: T = 5` against `local typealias T = Int(this > 100)` rendered `x = 5` instead of raising). Apple Pkl treats `local` here as a scope modifier — the declaration exists inside the module but is not exported when another module imports it; for pkl-mbt's primary single-module driver path the export-suppression aspect is a separate concern, so this slice records the declaration unchanged (parses the `local` token, then dispatches to the appropriate `parse_class_decl` / `parse_function_decl` / `parse_typealias_decl` exactly as the bare form would). Unblocks `types/typeAliasConstraint1` (`local typealias OneCharacterString = String(length == 1)` paired with a `local class ClassWithLengthProperty` whose default `characters: List<OneCharacterString> = List("a", "b")` couldn't be reached), plus a fan of fixtures that lean on `local function` declarations or `local class` defaults. Lifts gold-match from 103 to 109 PCF (`basic/localMethodTyped3`, `basic/localModuleMemberOverride1`, `modules/amendModule5`, `types/typeAliasConstraint1`, `implementation/equality`, `implementation/inequality`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148l
  - decisions: 1 entry(ies)
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

- [ ] **module self-ref partial visibility plus amend parent member fallback** (minor) — verifies: PKL-148ah — tags: evaluator, modules, upstream, compat
  > Apple Pkl's `module.<self>.<sibling>` reference, where `<self>` is the binding currently being evaluated, reads the in-progress partial object (siblings already computed in source order) instead of cycling — and `module.X` inside an `amends` / `extends` child resolves to the parent module's member when the child doesn't shadow it. pkl-mbt's `resolve_binding_value` short-circuit treated both as `cyclic property reference foo` / `Cannot find property a` respectively: the cyclic detector fired because the inflight binding was on the stack with no live snapshot in env, and `module.X` only consulted `find_binding(child_bindings, ...)` which doesn't carry parent-only names in amends mode. The fix has two parts. (1) `eval_object_members` pushes `{ name: <top_of_stack>, value: ObjectValue(values_snapshot) }` into per-field `local_env` so the in-flight object is exposed under the binding name being resolved; lookup_value's last-match-wins ordering means `module.foo.b` resolves through the snapshot ahead of the cycle path. (2) The `module.X` short-circuit (in MemberAccess) falls back to `lookup_value(cache, "super")` and reads X from the parent ObjectValue when the primary `resolve_binding_value` returns None — the `super = ObjectValue(parent_members)` pushed by `eval_program` (PKL-148ac) for amends / extends modules carries the parent surface. +2 fixtures (`basic/moduleRef1`, `basic/moduleRef2`), 139 → 141; basic category 51.2% → 53.5%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ag
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **module-level super dispatch for extends** (minor) — verifies: PKL-148ac — tags: evaluator, upstream, compat
  > Apple Pkl's `module B extends A` rebinds `super` to the parent module's evaluated members at the module-level — so `super.X` (property access) and `super.X(...)` (method call) inside the child's bindings / hidden properties / functions dispatch through the parent's binding cache, not just through a class-scoped `@current_class` marker. pkl-mbt's `eval_super_method_call` checked `@current_class` first and bailed with `super.<m> used outside a class body` when called from module top-level; the bare `super.X` property read hit `Cannot find property \`super\`.` because `Identifier("super")` had no env / cache entry. The fix is two-step: (1) at the start of `eval_program`, when `program.module_relation` is set, eagerly run `eval_module_relation` to materialise the parent's members and push `super = ObjectValue(parent_members)` into the cache (not env) so module-level `LambdaExpr → FunctionValue` evaluations capture it via `capture_value_bindings(env, cache)`, and so class-default evaluation (PKL-148aa) which pushes its own class-scoped `super` later still wins via the last-pushed-wins lookup. (2) `eval_super_method_call` falls back when `@current_class` is missing: look up `method_name` in the super-bound `ObjectValue` (trying both the bare and `hidden_member_name(...)` keys — module functions are stored under the hidden prefix), and when it resolves to a `FunctionValue`, hand it to `apply_function_value` with the evaluated arguments. The parent module's FunctionValues already captured the parent's env / cache when they were constructed, so `super.say(msg)` evaluates `prefix + msg` against the parent's `prefix`. +3 fixtures (`modules/supercalls2`, `modules/amendModule4`, `modules/extendModule1`); 127 → 130; modules category 61.9% → 76.2%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ab
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **mpkl stdlib coverage probe** — verifies: PKL-141 — tags: cli, stdlib, verification
  > `mpkl stdlib` runs an in-process probe table — one minimal fixture per documented stdlib surface area — through `AnalysisSession` (so `import "pkl:math"` etc. resolve through the synthetic stdlib loader, not the import-less `eval_source` path), renders the result via the PCF renderer, and matches against an expected substring. Pass / fail lines surface as `[PASS] group :: name` or `[FAIL]` with the diagnostic message; the trailing `stdlib: N / N passed` summary terminates the run, and the exit code is non-zero when any probe fails. The probe table covers `pkl:base` (Listing / Mapping / String / Int builtins + dedicated `Pair` / `IntSeq` / `Set` / `Map` value variants + Renderer classes + `Duration` / `DataSize` / `Regex` / `Bytes` literals), `pkl:math` (Int constants + helpers + Float-side `sqrt` / `pow` / `pi`), `pkl:semver` (parse + compare + parseOrNull), `pkl:platform` (deterministic stub values), `pkl:test` (`catch` on the throw branch), `pkl:reflect` (mirror constants + factory containers), `pkl:json` / `pkl:yaml` (Parser shells), and `pkl:xml` / `pkl:protobuf` (Renderer shells). The contract gates the surface README.md advertises as `Full` / `Partial` / `Stub` — any regression that breaks a documented capability fails the smoke check before the README claim can drift.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-119d, PKL-124, PKL-123
  - decisions: 3 entry(ies)
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

- [ ] **new body inference from first token and binding annotation** — verifies: PKL-138 — tags: parser, evaluator, pkf-pkspec
  > Apple Pkl writes `tests: Listing<Test> = new { ... }` and `m: Mapping<K, V> = new { ... }` without an explicit `Listing` / `Mapping` qualifier on `new`. The parser previously dispatched `new { ... }` (empty type prefix) unconditionally to `parse_object_body`, so bare-expression bodies parsed as zero members (the property-decl loop skipped them) and empty bodies came back as `ObjectValue([])` that failed every Listing / Mapping method. The new `parse_inferred_new_body` helper peeks the first significant token inside the brace: `[` → mapping body, `}` / `local` / `when` / `for` / property-decl / `hidden ident` / `fixed ident` → object body, anything else (literal / `(` / unary / `new` / identifier without property suffix) → listing body. For the empty-body case the parser still produces `ObjectLiteral([])`; the evaluator's `coerce_value_to_annotated_type` helper then projects it to `ListingValue([])` / `MappingValue([])` when the binding's type annotation requires it. Coercion runs at every binding eval site (`resolve_binding_value`, module-level binding loop, `eval_object_members`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-005
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **null-coalescing operator and let expressions** (minor) — verifies: PKL-088 — tags: evaluator, expressions
  > The `??` operator picks the right-hand value when the left evaluates to `NullValue`, and is right-associative so `a ?? b ?? fallback` short-circuits left-to-right. `let (name = value) body` introduces a single scoped binding, with the body able to reference outer bindings and inner let-expressions able to shadow the outer name. The two compose: `let (fallback = ...) raw ?? fallback`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **nullable read form** (minor) — verifies: PKL-103 — tags: parser, evaluator, read, nullable
  > Apple Pkl's `read?(uri)` mirrors `read(uri)` but returns `null` instead of pushing a diagnostic when the URI scheme is rejected by the sandbox or the resource is missing. The parser recognises `?` followed by `(` after a primary expression and emits a new `NullSafeCallExpr(callee, args)` AST node; the evaluator handles the `read?` case by routing through `eval_read_uri` with a throwaway diagnostic sink — anything that would have surfaced an error becomes `NullValue` instead. The typechecker reports the result as `NullableType(StringType)` so downstream nullable chains see the right shape. A `?` not followed by `(` stays the existing unsupported-syntax fall-through.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-098
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **object body forward refs amend super and Function apply surface** — verifies: PKL-148e — tags: evaluator, parser, scope, amend, stdlib, upstream, compat
  > Closes the next batch of upstream silent-mismatch fixtures. Object bodies now register every sibling member as a binding before evaluating any RHS, so `parent { x = 1 + y; y = 2 }` resolves `y` through the lazy `resolve_binding_value` path — cycle detection still uses the existing `stack` guard. Amend bodies expose `super` as the pre-amend ObjectValue, unlocking `(parent) { x = super.x + 100 }` for the simple-parent case (full Apple-Pkl super recursion against re-evaluated parents lands later). The `Function` value surface gains `.apply(args...)`, `.applyToList(list)`, `.toString()` / `.getClass()` plus the `(lambda).apply()` form, by intercepting MemberAccess(target, methodName) in `eval_callable_call` before the catch-all object-only lookup. Stdlib type identifiers (`Int`, `Float`, `String`, `Listing`, `Set`, `Map`, `Pair`, `IntSeq`, `Function`, etc.) project to a Class mirror just like user-declared classes, so `Int == Int`, `Int == 3.getClass()`, `Int != Float` round-trip. Bodyless `class Foo` is no longer eaten by the `skip_unknown_member` fallback that previously merged the following declaration into the current class node. `local` modifier on a class property now hoists via the hidden prefix and `push_receiver_method_bindings` strips it when seeding the method cache; sibling class methods are pushed as FunctionValues so `function compute() = b(c)` resolves `b` and `c` from the enclosing class. `let (x: Int = 42) body`'s typed binder threads through `parse_let_expr` already (no change required); the parser fix lands at `local name { body }` (was unsupported) and `.` immediately followed by a digit (leading-dot Float, used by `{1.2;.3;.4;.5}`). Heredoc dedent strips the newline immediately preceding the closing delimiter's indent line so `"""\\n hello\\n"""` reads as `"hello"` rather than `"hello\\n"`. The runtime type-acceptance widens: `Any` accepts every value (was rejecting), `List` / `Collection` accept ListingValue, `Set` accepts SetValue or ListingValue (until PKL-151's split), `Pair` / `IntSeq` route to their dedicated variants, and a user-declared class type accepts any ObjectValue (Apple Pkl checks the dynamic class on the instance; pkl-mbt's ObjectValue erases it). Lifts gold-match from 50 to 60 PCF (`api/moduleOutput`, `basic/identifier`, `basic/objectMember`, `classes/equality`, `classes/functions3`, `lambdas/lambda1`, `lambdas/lambda2`, `lambdas/lambda5`, `objects/super1`, `objects/super5`) and promotes `classes/constraints8` from substring to full gold-match.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148d
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **object body member header dispatch absorbs const and other modifier prefixes** (minor) — verifies: PKL-148aj — tags: parser, upstream, compat
  > Apple Pkl's object-body grammar lets any modifier keyword (`const`, `fixed`, `abstract`, ...) interleave with the `local` / `hidden` visibility prefix before the member's name — `const local function biz() = baz` and the simpler `const qux = 99` are both legal. pkl-mbt had two missing pieces in the parser. (1) `consume_member_visibility_modifiers` only consumed `local` / `hidden`; when the leading token was `const` the loop exited with VisibleMember, `skip_member_header` consumed `const`, and the parser then sat on `local function biz()` with no further visibility pass — the body-member dispatcher fell through to the bare-expression branch and lost the function. (2) `parse_inferred_new_body` disambiguates between an object body and a listing body by looking at the first significant token after `{`; only `hidden` and `fixed` (plus `local NAME = EXPR` blocks via `skip_local_decls_from`) routed to `parse_object_body`. A leading `const` (or `abstract`, etc.) failed every check and routed the entire body through `parse_listing_body`, dropping every named member silently — the rendered output of `const baz = 15; foo { const local bar = baz; … }` was `baz = 15; foo {}`. The fix collapses the two parser passes into a single `consume_member_header` that handles annotations + visibility + modifier-text idents in one loop, and adds a `skip_member_prefix_from` helper that walks past trivia + annotations + visibility + modifier idents so `parse_inferred_new_body` can ask `at_property_decl_from` on the token *after* the prefix run. +1 fixture (`basic/constModifier4`), 142 → 143; basic category 54.7% → 55.8%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ai
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **object-body local function and unknown-type diagnostic** (minor) — verifies: PKL-148ag — tags: parser, evaluator, diagnostics, upstream, compat
  > Apple Pkl lets an object body declare `local function f(...) = body` whose lexical scope covers every sibling member: `foo { local function f1(x: Int): Int = x + 1; res1 = f1(42) }` resolves `f1` to the in-body lambda. pkl-mbt's `parse_object_body_members` consumed the `local` visibility modifier but then dispatched on `at_property_decl()` / bare-expression — the leading `function` keyword (lexed as the bare identifier `function`) fell through to `parse_expr` and surfaced as `Cannot find property \\`function\\`.` at eval time. The fix adds a dedicated arm before the property-decl check: when the next significant token's text is `function`, reuse `parse_function_decl` to consume the full method shape (parameters, optional return type, body) and lower it to `ObjectMember { name = local_member_name(decl.name), value = LambdaExpr(params, body, return_type) }`. `eval_object_members` already strips the `@local$` prefix when hoisting prior members into the per-field eval env, so a sibling `f(arg)` resolves the bare name and `eval_callable_call`'s fallback path applies the FunctionValue. The same slice closes a related diagnostic gap: when a parameter / return annotation names a type that doesn't resolve to a stdlib class, user class, typealias, or in-scope type parameter, Apple Pkl emits `Cannot find type \\`<name>\\`.` — not the mismatched-value wording. A new `eval_type_name_is_unresolvable` helper runs the same `resolve → split-union → strip-constraint → strip-generic-head → strip-optional` cascade as the accept path, and the rejection-message functions short-circuit through it before crafting the value-mismatch message. +6 fixtures (`basic/localMethodInAmendingModule`, `basic/localMethodTyped`, `basic/localMethodTyped2`, `basic/localMethodTyped5`, `basic/localMethodTyped6`, `basic/localMethodUntyped`), 133 → 139; basic category 44.2% → 51.2%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148af
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **output renderer driver** — verifies: PKL-104 — tags: renderer, output, driver, pkf-pkspec
  > The CLI's `eval` command picks its rendered format from the module's `output { renderer = new JsonRenderer { ... } }` block when the user did not pass `-f` / `--format`. The renderer's class name is read directly from the parsed AST — `parse_source(source).program.bindings` is walked for an `output` binding whose `ObjectLiteral` body has a `renderer` member; the renderer's `TypedObjectLiteral(class_name, _)` (or an `AmendExpr` peeling back to one) maps onto the existing format string (`JsonRenderer` → `"json"`, `YamlRenderer` → `"yaml"`, `PropertiesRenderer` → `"properties"`, `PcfRenderer` → `"pcf"`). The eval result's `ObjectValue` does not carry the source class, so this path stays AST-driven rather than tagging values. The `output` block itself is then stripped from the rendered envelope by `extract_output_value` (when there's no explicit `output.value` subtree) so the renderer doesn't echo its own configuration. An explicit `-f` flag still wins over the renderer-class detection so existing fixtures behave unchanged.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-097
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **output.text emitted verbatim and upstream smoke diff goes bytewise** (minor) — verifies: PKL-148q — tags: cli, smoke, upstream, compat
  > Apple Pkl writes `output.text` to stdout verbatim — the string itself decides whether a trailing newline is present, so `output { text = "some string" }` produces exactly `some string` with no `\n`. pkl-mbt's CLI was calling `println(text)` in the `output.text` short-circuit, which always appended `\n` and skewed the byte count for `api/moduleOutput` (whose gold ends without `\n`). The fix routes the text bypass through `@fs.write_string_to_file("/dev/stdout", text)` — `/dev/stdout` is a kernel-provided alias for fd 1 on both macOS and Linux, so the existing `moonbitlang/x/fs` API gives us a no-newline write without adding a new dep just for one CLI slot; the `try / catch` falls back to `println` if the open ever fails on an unusual host. The smoke script's PCF diff path was simultaneously hardened: `eval_matches_gold` previously captured CLI stdout into a shell variable via `$(...)` (which strips trailing newlines) and re-emitted it through `printf '%s\n'` (which forces exactly one trailing `\n`), so any disagreement on the final byte was silently masked. Replacing that with `mpkl eval ... > tmpfile; diff -u gold tmpfile` makes the comparison byte-exact, which is the only shape that catches `api/moduleOutput`-style mismatches and matches the contract documented in the README ("byte-for-byte against upstream"). +1 gold-match fixture (`api/moduleOutput`), 110 → 111.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148p
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **package registry probe and structured diagnostic** — verifies: PKL-129b1 — tags: cli, parser, imports, sandbox, pkf-pkspec
  > The CLI accepts `package://<authority>/<path>@<version>[#<fragment>]` URIs and reports a structured diagnostic naming the package URI, the metadata URL (derived by direct scheme rewrite + drop the fragment), the optional fragment, and the `packageZipUrl` pulled out of the metadata JSON. The fetch path follows up to five 301 / 302 / 303 / 307 / 308 redirects so the `pkg.pkl-lang.org → CDN` hop the registry serves doesn't break the probe. `parse_package_uri` validates the shape (rejects authority-only URIs); `package_metadata_url` performs the rewrite; `extract_package_zip_url` substring-scans the metadata body for the `packageZipUrl` string (no full JSON parser stood up — the field is a simple unescaped URL string). On metadata fetch failure or missing field the diagnostic still surfaces the parsed pieces plus the workaround: download the zip manually (or with `pkl download-package`) and pass `--module-path <dir>`. The CLI exits with status 1 in either case. Full zipball download + DEFLATE unpack + cache + checksum verification land with PKL-129b2.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-129
  - decisions: 3 entry(ies)
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

- [ ] **parser and evaluator polish for pkspec** — verifies: PKL-139 — tags: parser, evaluator, stdlib, pkf-pkspec
  > Running pkspec's `pkl/Test.pkl` through pkl-mbt surfaced five drive-by parser / evaluator gaps that have nothing to do with one big subsystem but together blocked the file from evaluating. They are bundled here so a single slice unblocks the empirical pkspec round-trip: (1) `@ModuleInfo { ... }` brace-bodied annotations skip the `{ ... }` payload the same way `@Deprecated("...")` skips parens — Apple Pkl's module / class metadata uses the brace form. (2) `typealias Foo =\n  String(...)` allows the RHS to start on the next line; `parse_typealias_decl` now uses `skip_trivia` after the `=` so newlines are consumed. (3) Postfix dot-chains break across newlines (`xs\n  .toList()\n  .map(...)`); `parse_postfix_expr` peeks past trivia and, when the first significant follow-up token is `.` / `?.`, advances the cursor before continuing. (4) `module.foo` is Apple Pkl's self-reference to the current module's `foo` binding; the parser emits `Identifier("module")` and the evaluator short-circuits `MemberAccess(Identifier("module"), name)` to `resolve_binding_value(name, ...)`. (5) The stdlib constructor functions `List(...)`, `Set(...)`, `Map(k1, v1, k2, v2, ...)`, and `Pair(a, b)` are recognised before the generic call-path runs: `List` and `Set` produce `ListingValue` (Set dedupes), `Map` builds a `MappingValue`, `Pair` collapses to a 2-element `ListingValue` until PKL-119 introduces a dedicated `PairValue`.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-002, PKL-138
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl analyze lint subcommand** (minor) — verifies: PKL-102 — tags: cli, lint, analyze
  > `moon run cmd/mpkl -- analyze <file>` parses the module and runs a lint pass over the resulting `Program`. Four rules ship: `unused-local-binding` (a module-level `local` whose name never appears on any expression), `unused-import` (an import name never referenced), `unused-class-property` (a property of a class whose own name is never referenced — public schema classes are exempt to avoid noise), and `shadowed-identifier` (a binding whose name collides with an import / function / class / typealias at module scope). Findings render as `path: rule: message` one per line and the command exits non-zero when any finding surfaces, so editor integrations and CI can fail on lint regressions. Source positions become useful once PKL-107 propagates byte offsets into the AST; today's output is rule-driven.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-009
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl codegen bridge to MoonBit** — verifies: PKL-131 — tags: cli, codegen, typechecker
  > `moon run cmd/mpkl -- codegen <file.pkl>` lowers a parsed Pkl module into a MoonBit source skeleton so embedders can round-trip their schemas through both type systems. The `codegen_moonbit(program: Program): String` entry point walks `program.declarations`: each `ClassDeclaration` emits a `pub(all) struct ... derive(Eq, Show)` carrying one field per property; each `TypeAliasDeclaration` emits a `pub typealias <target> as <name>`; `FunctionDeclaration`s are intentionally skipped (no MoonBit data-shape analogue). Pkl type annotations flow through `pkl_type_to_moonbit`: scalars (`Int` → `Int`, `Float` → `Double`, `Boolean`/`Bool` → `Bool`, `String` → `String`, `Null` → `Unit`, `Bytes` → `Bytes`); generics recurse — `Listing<T>` / `List<T>` → `Array[T]`, `Mapping<K, V>` / `Map<K, V>` → `Map[K, V]`, `Set<T>` → `Array[T]` with a `/* Set */` comment (no ordered-unique container in moonbitlang/core yet), `Pair<A, B>` → tuple `(A, B)`, `IntSeq` → `Array[Int]` with `/* IntSeq */`, `Duration` / `DataSize` → `Double` with a unit comment; nullable `T?` carries through structurally; constraint suffixes (`Int(isPositive)`) strip to the base type because MoonBit doesn't model refinement types here; unrepresentable shapes (unions, `Any`, `Unknown`) fall back to `Unit /* TODO: ... */` so the generated file still parses and the embedder gets a `// TODO:` flag to grep for. The CLI subcommand reuses the same `print_diagnostics_with_source` path as `check` / `analyze` for parse errors, exits 1 on a non-clean parse, and otherwise prints the generated source verbatim (single trailing newline).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-080, PKL-110
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl test examples and golden diff** — verifies: PKL-100 — tags: cli, pkl-test, examples
  > The native CLI `test` subcommand walks the module-level `examples` member alongside the existing `facts` walker. Each example is rendered through the PCF envelope (`examples { ["label"] { ... } }`) and the entire envelope is byte-diffed against a sibling `<file>-expected.pcf` golden file. A passing diff prints `PASS examples (N examples)`; a mismatch prints `FAIL examples diff against <path>` and contributes to the non-zero exit. The `--overwrite` CLI flag regenerates the golden file from the current rendering (printing `OVERWRITE <path>`), matching Apple Pkl's golden-file workflow. Modules without an `examples` member skip the diff entirely so facts-only fixtures keep working unchanged.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-095
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:base method surface expansion first wave** — verifies: PKL-148 — tags: evaluator, stdlib, upstream, compat
  > Fills in the pkl:base surface gaps that snippetTest fixtures lean on. Added: Bool methods (`xor` / `implies` / `and` / `or` / `toString`); Float methods (`toString` / `abs` / `round` / `floor` / `ceil`); Int property surface (`isPositive` / `isNonZero` / `isFinite` / `isNaN` / `isInfinite` / `sign` / `inv`); String property surface (`isNotEmpty` / `isBlank` / `isNotBlank` / `reverse` / `base64`); Listing property surface (`isNotEmpty` / `isDistinct` / `firstOrNull` / `lastOrNull` / `toList` / `toSet` / `toListing`); Listing methods (`getOrNull(idx)` / `startsWith(other)` / `endsWith(other)`); Mapping property surface (`isNotEmpty` / `entries` / `toMap` / `toMapping`); Set methods (`add(x)` / `every(p)` / `any(p)` / `none(p)` / `count(p)` / `firstOrNull` / `lastOrNull`); Map method (`containsValue(v)`); Pair member aliases (`.key` / `.value` mirror `.first` / `.second`). Binary `+` now concatenates ListingValue / SetValue / MappingValue / MapValue / StringValue pairs. `value.getClass()` synthesises a `pkl:reflect.Class` mirror exposing `simpleName` / `name`. Class-typed bindings (`p: Person = new {}`) now expand their declared default properties via `apply_class_defaults_for_type`. Constraint diagnostic wording was rewritten to Apple Pkl's canonical form (`Type constraint \\\\\\\`isBetween(10, 20)\\\\\\\` violated. Value: 11` and `Expected value of type \\\\\\\`Int\\\\\\\`, but got type \\\\\\\`String\\\\\\\`. Value: \\\"foo\\\"`) so snippetTest fixtures that capture the message via `test.catch(...)` match byte-for-byte. NonNull assertion wording aligned (`Expected a non-null value, but got \\\\\\\`null\\\\\\\`.`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-075, PKL-147
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:base method surface second wave** — verifies: PKL-148b — tags: evaluator, stdlib, upstream, compat
  > Follows the PKL-148 first wave with runtime support for `this <op> N` bare-comparison constraints (`Int(this > 0)` etc. via the new `ThisCompare` predicate variant), the `as` and `|>` operators (parser-only stops being parser-only — `as` does a runtime type assertion and `|>` desugars to a single-arg call), Duration / DataSize scalar arithmetic (`5.s * 3`, `2.gb / 4`, the symmetric Int/Float on either side), Set + Listing (and Listing + Set) concat that mirrors Apple Pkl's collection-union semantics, Int methods (`isBetween(a, b)`, `toFloat()`), Listing.isDistinctBy(keyFn), Listing-host constraints (`Listing<T>(!isEmpty)`), and construction-time enforcement of class-property constraints so `new P { l {} }.l` raises the violation at construction rather than only at the outer binding boundary. Lifts gold-match from 38 to 40 PCF (`classes/constraints1`, `classes/constraints2`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:json / pkl:yaml / pkl:xml / pkl:protobuf stdlib modules** — verifies: PKL-124 — tags: stdlib, renderer
  > The renderer-driver classes the `output { renderer = ... }` path looks up are now part of the typechecker's stdlib surface. `JsonRenderer`, `YamlRenderer`, `PcfRenderer`, `PropertiesRenderer`, and `PListRenderer` are seeded as unqualified `ClassType` entries in `builtin_type_from_annotation` because Apple Pkl re-exports them through the implicitly-imported `pkl:base`; references like `new JsonRenderer { indent = "    " }` typecheck without an explicit import. Four synthetic stdlib modules — `pkl:json`, `pkl:yaml`, `pkl:xml`, `pkl:protobuf` — are added to `builtin_stdlib_source` so `import "pkl:json" as json` succeeds and `new json.Parser { ... }` / `new xml.Renderer { ... }` / `new protobuf.Renderer { ... }` reach the qualified-type lookup. Each renderer class is declared with an empty (or default-only) member surface; field-level typing for `converters`, `extension`, etc. is deferred to PKL-127 where the converter machinery actually consumes those properties. Unknown renderer names still trip `Cannot find type` — the surface is opt-in, not a silent open-world fallback. The CLI's existing `renderer_format_from_class` mapping is unchanged; the format dispatch was already AST-driven and the typecheck visibility was the missing link.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-104
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:json.Parser.parse implementation** — verifies: PKL-144 — tags: evaluator, stdlib, json
  > `pkl:json.Parser.parse(source)` decodes a JSON document into a Pkl `Value`. The evaluator's CallExpr dispatcher intercepts `<receiver>.parse(s)` whenever the receiver is an ObjectValue carrying a `useMapping : Boolean` slot — the distinguishing shape of the pkl:json Parser mirror (no class-level hidden marker because `hidden` on a class property is not yet a recognised modifier; the `useMapping` slot is a sufficient discriminator across the synthetic stdlib). The source string flows through MoonBit core's `@json.parse`, then `json_to_value` projects the resulting `Json` enum onto Pkl Values: `Null` → `NullValue`; `True` / `False` → `BoolValue`; `Number` → `IntValue` when the magnitude fits an Int32 and is integral, else `FloatValue` (matches Apple Pkl's `42` → `Int`, `42.5` → `Float` rule); `String` → `StringValue`; `Array` → `ListingValue` (recursive); `Object` → `ObjectValue` when `useMapping = false` (Apple Pkl's Dynamic-mode default) or `MappingValue` when `useMapping = true`. Parser errors from `@json.parse` surface as `json.Parser.parse: <err>` diagnostics; non-String arguments / wrong arity get their own targeted wording.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-124
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:math Float operations** (minor) — verifies: PKL-120 — tags: stdlib, pkl-math, float
  > `pkl:math` exposes the Float-side helpers `sqrt`, `pow`, `log`, `exp`, `floor`, `ceil`, `round`, `sin`, `cos`, `tan`, `atan`, `atan2`, plus the constants `pi` and `e`. The synthetic `pkl:math` source forwards each public name to a `_pkl_math_<op>` intrinsic identifier; the CallExpr dispatcher in `eval.mbt` intercepts those names, evaluates the numeric arguments (Int promotes to Double), and computes the result via MoonBit's `math` module (or the `Double` intrinsics for `sqrt` / `floor` / `ceil` / `round`). Existing Int helpers (`maxInt32`, `minInt32`, `abs`, `min`, `max`) stay unchanged.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-092
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:platform and pkl:semver stdlib modules** (minor) — verifies: PKL-123 — tags: stdlib, platform, semver
  > `pkl:platform` is a synthetic stdlib module that exposes a read-only stub view of the host VM (`current.operatingSystem.name`, `current.operatingSystem.version`, `current.architecture.name`, `current.language.version`). The stub hard-codes `stub-os` / `stub-arch` so fixtures are deterministic across CI hosts; a future slice can swap in host-detected values via intrinsics without breaking the API shape. `pkl:semver` exposes the canonical `Version(major, minor, patch)` constructor plus `parse(s)` / `parseOrNull(s)` / `compare(a, b)` / `isLessThan` / `isGreaterThan` / `isEqualTo`. Both `parse` paths forward to `_pkl_semver_parse(_or_null)` intrinsics that decompose the SemVer 2.0 grammar (`MAJOR.MINOR.PATCH[-PRE][+BUILD]`) into a `{ major, minor, patch, preRelease, build }` ObjectValue. The comparison helpers forward through `_pkl_semver_compare`, which compares numeric core fields and then applies SemVer pre-release ordering (numeric identifiers numerically; alphanumeric lexicographically; numeric < alphanumeric; fewer identifiers < more; pre-release < release).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-080
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:reflect class / module introspection** — verifies: PKL-143 — tags: evaluator, stdlib, reflect
  > `pkl:reflect` grows from a mirror-constant + factory stub into a usable introspection surface. The synthetic stdlib source stamps a hidden `__kind` marker (`"Class"` / `"Module"` / `"TypeAlias"`) on every factory-returned ObjectValue; the evaluator's `MemberAccess` arm checks for the marker before falling through to generic member lookup and dispatches to dedicated helpers (`reflect_class_properties` / `reflect_class_methods` / `reflect_class_supertype` / `reflect_module_classes`) that walk the surrounding module's `Array[Declaration]`. The same path handles the `isSubclassOf(other)` method call by tracing each receiver's `parent_name` chain against the argument's `reflectee` (with a 256-hop cap as a defensive cycle guard). The `__kind` marker is hidden via the existing `hidden_member_prefix` machinery, so it never reaches the renderer; the user-facing mirror still shows just `reflectee`. The slice deliberately keeps the factories taking a string identifier rather than a real `ClassValue` — that round-trip is the remaining gap once the value model grows a class-value variant. The `mpkl stdlib` probe table grows by five rows (properties / methods / supertype / isSubclassOf / classes) so the introspection surface is mechanically pinned alongside the existing mirror-constant probes.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-080
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **pkl:yaml.Parser.parse implementation** — verifies: PKL-146 — tags: evaluator, stdlib, yaml
  > `pkl:yaml.Parser.parse(source)` decodes a YAML document into a Pkl `Value`. The evaluator's CallExpr dispatcher mirrors the PKL-144 / PKL-145 pkl:json path: the Parser stamps `hidden __kind = "YamlParser"` on its synthetic class, the dispatch checks `reflect_kind(receiver) is Some("YamlParser")`, and the source string flows through `moonbit-community/yaml`'s `Yaml::load_from_string`. `yaml_to_value` projects each Yaml variant onto a Pkl Value: `Null` → `NullValue`; `Boolean` → `BoolValue`; `Integer(i)` → `IntValue` when `i` fits Int32 else `FloatValue` (no silent truncation); `Real(d)` → `IntValue` when integral + Int32-bounded else `FloatValue` (same disambiguation rule as the JSON path); `String` → `StringValue`; `Array` → `ListingValue` (recursive); `Map` → `ObjectValue` (default Dynamic mode) or `MappingValue` (`useMapping = true`); `BadValue` → `NullValue`. Multi-document YAML returns only the first document for now; the loader-side `Array[Yaml]` shape is preserved so multi-doc surface lands when a fixture demands it. Parser errors surface as `yaml.Parser.parse: <err>` diagnostics.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-145, PKL-144
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **plist renderer** — verifies: PKL-126a — tags: renderer, plist
  > The plist renderer emits Apple plist XML (PLIST 1.0 DTD) documents. The output starts with the standard XML 1.0 prolog and `<!DOCTYPE plist PUBLIC ...>` declaration, then wraps the rendered value in `<plist version="1.0">`. Value projection mirrors upstream Apple Pkl: Int → `<integer>N</integer>`, Float → `<real>D</real>`, Bool → `<true/>` / `<false/>`, String → `<string>...</string>` with XML entity escaping (`&` `<` `>`), Object / Mapping → `<dict>` with `<key>` + value pairs, Listing → `<array>`, Duration / DataSize → `<string>N unit</string>` (space-separated form rather than the `.` form used by JSON / YAML for these values), Regex → `<string>pattern</string>`, Bytes → `<string>base64</string>`. Null entries are elided inside dicts (matching Apple's `omitNullProperties` default) and inside arrays (the upstream error-on-null-in-array surface lands with PKL-127's converter machinery, alongside the rest of the renderer-side error pipeline). `-f plist` selects the renderer at the CLI; `output { renderer = new PListRenderer {} }` selects it via the AST-driven detection that already powers `JsonRenderer` / `YamlRenderer`. `pListRenderer1.plist` from the upstream snippet tests now byte-matches the gold file and joins `scripts/upstream-smoke.sh`'s new `PLIST_GOLD_FIXTURES` list.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-124
  - decisions: 2 entry(ies)
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

- [ ] **raw string interpolation plus raw escape decoding plus unicode escape plus heredoc backslash** (minor) — verifies: PKL-148ao — tags: parser, lexer, strings, renderer, upstream, compat
  > Apple Pkl's raw string literal supports an `\<N #>(expr)` interpolation marker — the same `\(...)` shape as a non-raw string but prefixed with `N` `#`s, where `N` matches the leading hash count of the raw delimiter. Inside a raw string the same N-hash escape re-enables every standard escape: `\#t` → tab, `\##n` → newline, `\#u{1F920}` → 🤠. PKL-148an landed the delimiter strip + verbatim text path; this slice closes the interpolation + escape loop. Four coupled changes. (1) Lexer learns to skip an entire `\<N #>(...)` argument when scanning for the close delimiter — without it a `"##` inside a nested raw string (e.g. `#"a\#(##"b"##)c"#`) mis-terminates the outer literal. `is_raw_interp_marker` + `skip_raw_interp_arg` + `skip_nested_string_at` walk balanced `(...)` while recognising every nested string shape (single-line / heredoc, raw / non-raw, arbitrary hash count). (2) Parser's `assemble_string_parts` is parameterised on `hash_count`: 0 routes to the non-raw walker (looks for `\(`, runs `decode_string_escapes` on literal segments), > 0 routes to the raw walker (looks for `\<N #>(`, keeps literal segments verbatim, but decodes `\<N #>X` inline by feeding the equivalent non-raw escape through `decode_string_escapes`). (3) `decode_string_escapes` gains a `\u{HHHH}` arm — hex digits up to the matching `}`, emitted as a single code point. This was missing entirely (`\u` fell through to the catch-all that wrote `u` literally), so non-raw `"\u{1F920}"` and raw `"\#u{1F920}"` both gain support in one place. (4) PCF heredoc render now escapes each content line via `escape_string_heredoc` (`\` → `\\`, `\t` → literal `\t`, `\r` → literal `\r`); previously a heredoc string containing a literal `\` round-tripped as a single backslash and broke gold-match for any multi-line value with escape-significant chars. +2 fixtures (basic/rawString, basic/stringMultiline — the latter benefits from the unicode escape arm), 145 → 147; basic category 57.0% → 59.3%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148an
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **raw string literal with arbitrary hash count for single-line and heredoc forms** (minor) — verifies: PKL-148an — tags: parser, lexer, strings, upstream, compat
  > Apple Pkl's raw string literal — `#"..."#` (single-line) or `#"""..."""#` (heredoc), with an arbitrary number of leading `#`s that the closing delimiter must match — passes the inner text through verbatim. `\` escape sequences (`\n`, `\t`, `\\`) are NOT interpreted, `\(...)` is NOT an interpolation marker, and only the matching `\<N #>(...)` form (which this slice does not yet implement) re-enables interpolation. pkl-mbt's lexer previously fell off the `#` character into the regular token path; the parser then surfaced every raw literal as `unsupported expression`. The fix has two halves. (1) The lexer counts the leading `#` run, requires a `"` (or `"""`) immediately after, and scans for a matching `"<N #>` (or `"""<N #>`) close. Newlines terminate single-line raw strings the same way the non-raw form would. (2) `parse_string_literal_text` detects a `#` prefix on the captured token, computes the hash count, strips the prefix / suffix, and emits the inner text as a verbatim `StringLiteral` — no escape decoding, no interpolation walk. Heredoc indent stripping still applies via `strip_heredoc_indent`, matching Apple Pkl's non-raw heredoc behaviour. No PCF count change — `basic/rawString` stalls on res28 which uses `\#(...)` interpolation inside a `#"..."#` raw, and the api/* fixtures that use raw strings (api/baseModule, api/jsonParser1/2, api/regex, api/string, api/stringUnicode, api/set, api/mapping, api/listing, api/stringMultiline*, etc.) each have additional snippetTest framework / stdlib surface needs before they flip. But the parse-error class shrinks substantially: 17 fixtures drop out of the `unsupported expression` set (43 → 26), unblocking diagnosis of the next layer of failures.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148al
  - decisions: 3 entry(ies)
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

- [ ] **renderer converters** — verifies: PKL-105 — tags: renderer, converter
  > `output { renderer = new JsonRenderer { converters { ["path.to.field"] = (value) -> ... } } }` rewrites the value at the named dotted path before the renderer serialises the module. Each converter is a `(value) -> newValue` lambda; `eval_program` collects the path-keyed converters from the post-eval result's `output.renderer.converters` MappingValue, then walks the value tree applying `apply_function_value(callback, [matched_node])` at each matching path. Both `ObjectValue` members and `MappingValue` entries with `StringValue` keys participate; unmatched paths are silently skipped (matching Apple Pkl's lenient behaviour). Class-keyed converters (`["MyClass"] = ...`) are recognised but deferred — pkl-mbt's `ObjectValue` doesn't yet carry its source class. The `parse_object_member` brace-body parser now delegates to `parse_inferred_new_body` (mirroring the property-decl fix in PKL-137) so `converters { ["k"] = v }` parses as a mapping rather than an object body that silently drops bracket-keyed entries.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-104
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **runtime evaluation of arbitrary constraint expressions** — verifies: PKL-148c — tags: evaluator, constraints, upstream, compat
  > Falls back to a generic runtime evaluator after the static predicate cascade (`isBetween`, `isPositive`, `length.isBetween`, `ThisCompare`, `!isEmpty`) returns no match for a class-property constraint. The fallback parses the constraint text by wrapping it as `__probe = (text)` through the regular parser, binds the candidate value as `this` plus the enclosing class's other property values into a fresh env, and rewrites bare `Identifier(name)` references inside the expression to `MemberAccess(Identifier("this"), name)` when `name` is otherwise unresolved — Apple Pkl's constraint body uses implicit-receiver lookup, so `abs` in `Int(abs < 100)` resolves as `this.abs`, `street` in `Address(street.endsWith("St."))` resolves as `this.street`, and `min` in `Int(this >= min)` falls through to the sibling-property push. Diagnostic text is re-spaced through `pretty_constraint_text` because the existing `parse_type_text` strips trivia (so the captured form reads `this>=min` rather than Apple Pkl's `this >= min`). Also aligns the `if` condition diagnostic wording to `Expected value of type \\\\\\\`Boolean\\\\\\\`, but got type \\\\\\\`X\\\\\\\`. Value: V` (with a dedicated null branch). Lifts gold-match from 40 to 43 PCF (`basic/if`, `classes/constraints4`, `classes/constraints6`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148b
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **scientific Float and triple-quoted heredoc** (minor) — verifies: PKL-128b — tags: parser, lexer, string, float
  > Two parser-surface extensions that landed together because they share the lexer's literal-token path. (1) Scientific-notation Float literals — `1e10`, `2.5e-3`, `4E+8`. The lexer extends the existing Int / Float scan with an optional `e` / `E` + sign + digit suffix; `parse_float_text` splits at the exponent, parses the mantissa, then multiplies by 10^exp. (2) Triple-quoted heredoc strings — `"""<newline>...<indent>"""`. The lexer captures the whole literal as one `string_token` (three opening `"`, body, three closing `"`); `strip_heredoc_indent` then drops the leading newline and dedents each body line by the closing delimiter's indentation. The existing escape decoder still runs on the dedented body so `\n`, `\t`, etc. continue to work. String interpolation (PKL-128a) operates on the same dedented body.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-128a
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **shebang preamble at module start consumed as trivia** (minor) — verifies: PKL-148p — tags: lexer, parser, upstream, compat
  > Apple Pkl tolerates a `#!...` shebang as the first line of a `.pkl` source — `pkl eval` strips it silently and parses the rest of the module, so `#!/usr/bin/env pkl eval` + `foo = 1` evaluates to the same `foo = 1` PCF as the body alone. pkl-mbt's lexer had no `#` branch, so the leading `#!` surfaced as `unsupported expression` and `syntax/shebang.pkl` failed before the body parsed. The fix is a tiny lexer-level branch in `Lexer::next_token`: when `pos == 0` and the first two bytes are `#!`, consume the line up to (not including) the next `\n` and emit it as a `comment()` trivia token — the existing trivia handling in the parser then skips it the same way it skips a `//` line comment. The `pos == 0` guard keeps a stray `#!` later in the source from being silently swallowed (Apple Pkl only treats the preamble shebang specially). +1 gold-match fixture (`syntax/shebang`), 109 → 110.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148o
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **snippetTest harness foundation** — verifies: PKL-147 — tags: parser, lexer, evaluator, cli
  > Four small fixes that let upstream `LanguageSnippetTests/input/<dir>/<name>.pkl` fixtures whose body amends `snippetTest.pkl` produce shape-correct output. (1) `parse_mapping_entry` now dispatches the `["k"] { body }` amend form through `parse_inferred_new_body` so a `Mapping<String, Listing<T>>` entry's body parses as a Listing (bare elements) instead of an ObjectLiteral that silently drops every non-property line — this alone unblocks every fixture whose body is a Listing of expressions. (2) The CallExpr dispatcher recognises `module.catch(() -> ...)` alongside `test.catch(() -> ...)` and reuses `eval_pkl_test_catch_binding_value` to materialise the no-throw / throw branches. (3) The lexer accepts `0x` / `0b` / `0o` integer prefixes plus `_` digit separators (`0xFF_FF`, `0b1010`, `1_000_000`) — without this the upstream `(0x110000).toChar()` test in `api/int.pkl` errored out at parse time. (4) The CLI's eval handler honours `output { text = "…" }` (verbatim string projection) and `output.renderer.omitNullProperties = true` (recursive null-property strip on the value tree). Method-coverage and diagnostic-message-wording gaps inside the snippetTest body bodies still keep most fixtures off the byte-match list; this slice is the harness foundation that PKL-148 / PKL-153 can build on.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-095, PKL-104, PKL-126, PKL-137
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **source position in diagnostics** — verifies: PKL-107 — tags: diagnostics, position
  > Every `Diagnostic` carries `start` / `end` byte offsets into the originating source. The parser sets the offset on every `add_error` site so syntax errors point at the failing token. The CLI's `print_diagnostics_with_source` projects the offset onto a `path:line:column: message` format that editors and IDEs can jump to. Sites that don't have a position yet (most typechecker / evaluator emissions) keep `start = -1`; those still render as just `message` — the migration is incremental. `Parser::current_offset` is now O(1) (cached on the parser struct, incremented by `bump`) instead of summing all preceding token texts on every emit. The helper `diag(message)` covers the common case of an unknown position; explicit `Diagnostic::{ message, start, end }` construction is the path for positioned diagnostics.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-004
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **spread members in object listing and mapping bodies** (minor) — verifies: PKL-148s — tags: parser, evaluator, upstream, compat
  > Apple Pkl's `...x` / `...?x` spread member splices the payload into the surrounding body — into listing elements when the parent is a Listing, mapping entries when the parent is a Mapping, properties when the parent is an Object. pkl-mbt's body parsers were dropping the construct entirely (the `else` arm of `parse_object_body_members` / `parse_listing_body` routed the dots through `skip_unknown_member`), so any fixture using spread reported `unsupported expression`. Implemented in two halves: the parser gains `at_triple_dot` / `parse_spread_payload` helpers and a spread arm in each of the three body parsers (object body pushes `ObjectMember { name = "@spread" }`; listing body and mapping body wrap the payload in the existing `WhenSpread(...)` construct so the eval-side spread-flatten path already covers them). The evaluator's `eval_object_members` gains an `@spread` arm alongside the existing `@when` / `@for` sentinels (splices ObjectValue members; silently skips `NullValue`; diagnoses other shapes), and the ListingLiteral / MappingLiteral arms gain a `Some(NullValue) => ()` clause so the nullable spread `...?x` against null is a no-op (the required form `...x` against null would ideally surface a diagnostic, but treating both alike unblocks `spreadSyntaxNullable` without demanding an AST-level required-vs-optional distinction that none of the current gold fixtures exercise). +1 fixture (`generators/spreadSyntaxNullable`), 114 → 115. The deeper Dynamic-shape work (a single value variant that holds both named members and unnamed elements simultaneously, needed to flip `spreadSyntaxDynamic` / `spreadSyntaxListing` / `spreadSyntaxTyped`) stays deferred under the super-late-bind cluster.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148r
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **string interpolation** — verifies: PKL-128a — tags: parser, evaluator, string
  > Apple Pkl's `"... \(expr) ..."` string interpolation parses and evaluates. The lexer walks balanced parens (escape- and inner-string-aware) so the outer string's closing `"` isn't confused with a `"` inside a `\(...)` segment. The parser's `parse_string_literal_text` helper splits the inner text at `\(` boundaries, parses each segment via `parse_source`, and builds an `InterpolatedString(Array[Expr])` AST node — strings with no interpolation collapse back to a plain `StringLiteral` so the hot path stays untouched. The evaluator concatenates each part's `value_to_string_for_join` projection (the helper already used by `Listing.join`). The typechecker reports the result as `StringType` regardless of inner expression types but still walks each part so nested diagnostics surface.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-002
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **string literal type union plus startsWith endsWith contains string constraints** (minor) — verifies: PKL-148ai — tags: evaluator, constraints, upstream, compat
  > Apple Pkl's `"<text>"` is a singleton type whose only inhabitant is the literal string itself; it can appear inside a union (`Null|Boolean|"Pigeon"`) to narrow the acceptable set of string values. The same surface also exposes `String.startsWith("X")` / `endsWith("X")` / `contains("X")` as constraint predicates (with `!`-prefixed negations). pkl-mbt's `eval_value_accepts_type_annotation` had no string-literal arm — the union choice `"Pigeon"` failed the head check, the cascade fell through to the value-mismatch path, and the `List<Null|Boolean|"Pigeon">` element `"Pigeon"` was rejected. The constraint side missed three predicates: `endsWith`, `startsWith`, `contains` (plus negations) — `String(endsWith("A"))` parsed but no `pkl_string_constraint_predicate` arm produced a recogniser, so the let-typed binding `str: String(endsWith("A")) = "Pigeon".reverse()` accepted `"noegiP"` and `test.catch` saw `Expected an exception, but none was thrown.` instead of the gold `Type constraint \\`endsWith(\\"A\\")\\` violated. Value: \\"noegiP\\"`. The fix has two parts. (1) `eval_value_accepts_type_annotation` checks for a leading-and-trailing `"` on the type name; if both present, the inner text is the literal payload — a StringValue equal to the payload satisfies the singleton, anything else rejects. The PKL-148ag unresolvable gate already special-cases the `"`-prefix head so the rejection cascade quotes the original union surface instead of `Cannot find type \\`"Pigeon"\\`.` (2) `ConstraintStringPredicate` gains `StringStartsWith` / `StringEndsWith` / `StringContains` plus their `Not`-prefixed twins; `pkl_string_constraint_predicate` recognises the bare and `this.`-prefixed forms with quoted-string arguments; `pkl_string_constraint_name` renders the verbatim source (`endsWith("A")`) so the diagnostic lines up byte-for-byte; `pkl_string_predicate_accepts` dispatches through `value.has_prefix` / `value.has_suffix` / `value.find` for the three positive forms. +1 fixture (`basic/letTyped`), 141 → 142; basic category 53.5% → 54.7%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ah
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **structural type rejection with lazy per-property class-default semantics** — verifies: PKL-148u — tags: evaluator, typecheck, upstream, compat
  > Apple Pkl rejects a value whose runtime type doesn't satisfy the declared annotation independently of any constraint predicate — `res: String = 42` (or the aliased `res: Simple = 42` where `typealias Simple = String`) emits `Expected value of type \`String\`, but got type \`Int\`. Value: 42`. pkl-mbt's binding-level and class-default checks were only running the CONSTRAINT cascade (`pkl_constrained_type_annotation_value_is_valid`) which silently accepts when the source type has no predicate, so the entire `typeAlias1`-shape gold cluster fell through with `Expected an exception, but none was thrown`. The fix has two parts: (1) a new `eval_resolved_annotation_structural_rejection_message` helper that resolves type aliases, splits top-level unions (`Int|Boolean`), strips each choice's `(...)` constraint and outermost `<...>` generic head, recurses element-wise for `List<T>` / `Listing<T>` / `Set<T>` / `Map<K,V>` / `Mapping<K,V>`, and produces the rejection diagnostic using the RESOLVED type name (not the source alias). The helper only fires for stdlib type names or known user classes so partially-implemented surfaces stay silent. (2) An `eval_object_members_with_options(... defer_property_errors~)` variant that captures each class-default property's diagnostics into a per-property buffer; failures are stored as a sentinel `@error$<name>` member on the resulting ObjectValue instead of bubbling to the outer diagnostics array. The ObjectValue access path (`MemberAccess` arm in `eval_expr_with_bindings`) consults `lookup_pending_error_message` first; when a sentinel matches, it raises THAT property's diagnostic and short-circuits. The net effect: `test.catch(() -> bad.res13)` catches `res13`'s rejection; `test.catch(() -> bad.res14)` independently catches `res14`'s — even though `bad = new Bad {}` is cached after first construction. The callable-argument and binding-level diagnostics also align with Apple Pkl's wording (use resolved name, strip trailing `?` so `Nullable = Duration?` shows as `Duration`). +2 fixtures (`types/typeAlias1`, `modules/typedModuleMethods1`), 116 → 118; types category 23.5% → 29.4%, modules 57.1% → 61.9%, TOTAL 29.7% → 30.2%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148t
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

- [ ] **subscript amend on Listing with out-of-range diagnostic** (minor) — verifies: PKL-148w — tags: parser, evaluator, upstream, compat
  > Apple Pkl accepts `(listing) { [N] = newValue }` as a subscript-amend syntax: when N is in `[0, length)` the element is replaced, when out of range the runtime emits `Element index \`<n>\` is out of range \`0\`..\`<upper>\`.`. pkl-mbt's parser routed every `(target) {...}` body through `parse_object_body_members` which had no `[` arm, so the bracketed entry was silently dropped (`skip_unknown_member`) and the AmendExpr arm bailed with the generic `object amendment expects Object`. The parser now captures each `[key] = value` (and `[key] { body }`) inside an object body as `ObjectMember { name = "@subscript$<offset>", value = CallExpr(Identifier("@__index_entry"), [key, value]) }` — a synthetic encoding that round-trips through the existing AST shapes (no new variant needed). The AmendExpr evaluator gains a `ListingValue` / `ListValue` arm that dispatches the `@subscript$*` members through `eval_listing_subscript_amend`: evaluate each key, range-check, replace the element, and surface Apple Pkl's wording on out-of-range. Members without the subscript prefix fall back to the generic diagnostic for now; mixing `[N] = ...` with `name = ...` on a Listing base is deferred until a gold fixture surfaces the need. +1 fixture (`listings/wrongIndex`), 119 → 120; listings category 18.8% → 25.0%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148v
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **super late binding amend lambda form class-aware object equality** [draft] — verifies: PKL-148aq — tags: evaluator, stdlib, upstream, compat, next
  > PKL-148ak folded the `@error$` deferred-rejection prefix into the invisible-member set, hoisted the sentinel into per-field env, and added an Identifier intercept so `test.catch(() -> bad_local)` captures the deferred diagnostic against typed locals (+1 fixture, 143 → 144; basic 55.8% → 57.0%); PKL-148al added the PCF triple-quoted heredoc form for multi-line strings at block positions and reordered Dynamic-shape projection so named properties land before bare elements / subscript entries (+1 fixture, 144 → 145; api 7.4% → 8.4%). The harder remaining pieces — all of which require non-local evaluator work — are: full Apple-Pkl `super.X` late binding (re-evaluate the parent's RHS against the amended this, needed for `objects/super2` / `super3` / `super4`, `classes/supercallsInLet`, and `basic/moduleRef3`'s `const a = 44` override of the parent's `aa = module.a`); the `(lambda) { body }` amend form for lambdas that return lambdas (used by `lambdas/amendLambda*` fixtures); runtime constraint expression eval that resolves user-defined `function` calls (`multiply(subtract(add(5,4),3),2) == z` from `classes/constraints7`); constraints firing on amend chains where the host class isn't statically known (constraints11 / 12 / 13); class-aware ObjectValue tagging so `new Person {} != new Person2 {}` (needed for `objects/equality`'s c-block + composite Mapping keys in `mappings/mapping1` that PKL-148k currently sidesteps via a scalar-only duplicate-check gate — a prototype hidden `__class` marker landed in PKL-148i but was reverted after it broke 14 structural-equality unit tests; the right shape is a dedicated `ObjectValue(class_name: String?, members)` enum-shape refactor); the `pipeOperator` res11 diagnostic also needs the class-aware tag to project `pipeOperator#Person` / `new Person {}`; object-body amend chain (`(obj) { ... } { ... }` — needed for `objects/equality` a11); free-form (non-literal) amend-override rejections (`(res3) { y = expr }` against `Int(this > x)` constraints — gated today on the upstream forward-binding leak where a sibling object's `local x = 1` resolves into a later object body's identifier lookup); listing/mapping body re-eval on amend so listing `(x) {}` / `default = N` work (needed for `listings/equality`, `listings/inequality`, `mappings/equality`, `mappings/inequality`). Listing/List-method receiver-tag preservation (`list.map(...)` returns a List, `listing.map(...)` returns a Listing) is a sub-task too; today the dispatcher always re-wraps as ListingValue. Remaining stdlib gaps (DataSize.isBinaryUnit, Duration.isBetween, jsonnet renderer module) ride along; PcfRenderer / JsonRenderer instance-method bodies (renderDocument / renderValue) plus converter dispatch (`converters { [Any] = ...; [Dog] = ... }` + regex path matching) are the next api/-shaped slice once the leverage analysis surfaces a 1-flip-per-feature angle.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148ap
  - body: _not yet implemented_

- [ ] **super method call** — verifies: PKL-117a — tags: evaluator, inheritance
  > `super.method(args)` inside a subclass method body dispatches to the parent class's implementation while keeping the current `this`. `eval_class_method_call` pushes a synthetic `@current_class` marker onto the method cache when it enters a class body; `eval_super_method_call` reads that marker, looks up the class binding's `parent_name`, finds the named method on the parent, and invokes it with the same receiver members plus the freshly bound parameters. Errors surface cleanly when `super` is used outside a class body, when the current class has no parent, or when the parent class doesn't define the method. The abstract-method enforcement and override-direction type compatibility halves of PKL-117 remain on the original ticket — the dispatch slice unblocks the most common usage in pkspec adapters.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-040
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **super property access in class default body** (minor) — verifies: PKL-148aa — tags: evaluator, upstream, compat
  > Apple Pkl's `class D extends C { result = let (x = "d") super.value + x }` resolves `super.value` against the parent class C's already-evaluated property defaults. pkl-mbt only pushed a `super` binding into the cache inside `AmendExpr` evaluation (the `(target) { ... }` form) and inside `eval_class_method_call` via the `@current_class` marker for `eval_super_method_call`. Class default bodies that referenced `super.X` as a property access — not a method call — fell through to `resolve_binding_value("super", ...)` which has no entry and surfaced `Cannot find property \`super\`.`. `eval_class_default_members` now copies the cache before evaluating the class's own defaults and pushes `{ name: "super", value: ObjectValue(base_values) }` when the parent contributed any members. `base_values` is the parent's recursively-evaluated default set (including the grand-parent chain), so a property read like `super.value` lands on the parent's value without disturbing the method-call path (`super.foo()` still goes through `CallExpr(MemberAccess(Identifier("super"), _), _) → eval_super_method_call` and uses `@current_class`). Lambda-captured cases work too: the `let (x = "d") body` desugar to `CallExpr(LambdaExpr([x], body), ["d"])` captures the cache (which now includes `super`) via `capture_value_bindings`, so the body sees `super` even after the lambda hop. +1 fixture (`classes/supercallsInLet`), 123 → 124; classes category 52.9% → 55.9%.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148y
  - decisions: 2 entry(ies)
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

- [ ] **triple-dot import resolves through ancestor directories** (minor) — verifies: PKL-148r — tags: cli, imports, upstream, compat
  > Apple Pkl's `import ".../X/Y.pkl"` form searches the parent directories of the importing module to find the first ancestor that contains the remainder path. The upstream test corpus uses this prefix 51 times (e.g. `import ".../input-helper/api/annotationConverter.pkl"` from `input/api/pcfRenderer9.pkl`), and pkl-mbt was bailing on all of them with `Cannot find module` because `resolve_import_path` only handled bare-relative paths. Implemented in two halves: the CLI loader (`cmd/mpkl/main.mbt:resolve_import_path`) walks ancestor dirs via `@fs.path_exists` and registers the resolution into a sandbox-level `(from, uri) -> resolved` map; the IO-free analysis-layer resolver (`analysis.mbt:resolve_import_path`) consults the registry to map the same `(from, uri)` pair back to the absolute path the CLI loaded under, so the cache key agrees end-to-end. Three fixtures flip: `classes/constraints14` (custom constraint pulling in a helper file), `errors/const/constLocalAmendModule` (amend chain across the `input-helper` tree), `modules/amendModule6` (`amends ".../input-helper/modules/Birds.pkl"`). The other 22+ with-gold triple-dot fixtures still need orthogonal work — `pkl:shell`, `pkl:yaml` parser flags, jsonnet renderer, `pkl:reflect.Module.imports`, `ConvertProperty` annotation framework, package registry resolution — so the resolver itself is the foundation and the rest land as their own slices. +3 gold-match fixtures, 111 → 114.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148q
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **type parameter bounds** (minor) — verifies: PKL-116 — tags: parser, typechecker, generics, bounds
  > `class Box<T : Number>` and `function pick<T : Number>(x: T): T` constrain T to a supertype. The parser collects the `: <bound>` suffix per type parameter and stores it as a parallel `type_parameter_bounds: Array[String?]` on `ClassDecl` and `FunctionDecl`. `collect_declared_types` resolves each bound text against the surrounding `type_env` and stores the resulting Type on the new `bound: Type?` field of `TypeBinding`. At call sites, `unify_for_substitution` consults `binding.bound` when it records `T := <actual>`; if the bound is set and `type_accepts(bound, actual)` returns false, a diagnostic surfaces as `type parameter T bound <bound> rejects <actual>` (with Number rendered as `Int|Float` since the union form is canonical). Unbounded parameters keep `bound = None` and the existing accept-any behaviour. Class type literal sites flow through the same path via `substitute_class_type_variables`, which now threads `type_env` and `diagnostics` so bound failures inside `new Container { value = "x" }` (where `Container<T : Number>`) reach the user.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-089, PKL-110
  - decisions: 5 entry(ies)
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

- [ ] **unordered equality plus typed-property default synthesis** — verifies: PKL-148f — tags: evaluator, equality, scope, defaults, upstream, compat
  > Tightens upstream equality and unblocks the typed-default fixture cluster. SetValue equality now compares as a multiset (was order-sensitive via derived `==`), ObjectValue equality compares by visible-member content ignoring property order and hidden members, and MapValue / MappingValue follow the same bag-of-entries pattern — `Set(1, "two", 3) == Set("two", 3, 1)` and `{foo=1; bar=2} == {bar=2; foo=1}` now round-trip. IntSeq equality no longer materialises the entire range (`IntSeq(math.minInt, math.maxInt)` was OOM-ing on the materialise path); length is computed in Int64 to survive the full 32-bit span. The no-arg property surface on String / Int / Float / Listing also accepts the method-call form (`str.reverse()`, `n.abs()`, `x.isNaN()`, `list.toSet()`) since Apple Pkl exposes both shapes; Float gains its own `eval_float_property` for `abs` / `isPositive` / `isNonZero` / `isFinite` / `isNaN` / `isInfinite` / `sign`. Module-level `hidden h = ...` is now resolvable by bare name through `find_binding`'s hidden-prefix-aware lookup. Typed properties declared without `=` synthesise a type-directed default — user classes project to `new T {}` with class defaults applied, nullable types and `Null` project to `null`, string-literal types project to the literal, `Listing` / `Mapping` / `Set` / `Map` default to their empty form, and `*A|B` picks the starred branch. `extends "parent.pkl"` now exposes the parent module's class declarations to the child by bare name, and the analysis-side import resolver follows the extends chain so a downstream importer sees inherited classes too. Lifts gold-match from 60 to 67 PCF (`basic/intseq`, `basic/set`, `basic/typeResolution1`, `basic/typeResolution2`, `basic/typeResolution3`, `basic/typeResolution4`, `objects/closure`).
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-148e
  - decisions: 4 entry(ies)
  - body: _not yet implemented_

- [ ] **upstream fixture sweep expansion** — verifies: PKL-109 — tags: compatibility, upstream
  > `scripts/upstream-smoke.sh` gains seven additional fixtures whose `pkl eval` output now matches the upstream `LanguageSnippetTests/output/<dir>/<name>.pcf` gold byte-for-byte: `annotation/annotation1`, `api/jsonRendererEmptyComposites`, `api/moduleOutput2`, `basic/minPklVersion`, `basic/moduleRefLibrary`, `generators/propertyGenerators`, `listings/cacheStealingTypeCheck`. Total gold-match coverage rises from 25 to 32 fixtures across 7 upstream subtrees (`annotation`, `api`, `basic`, `classes`, `generators`, `listings`, `modules`, `objects`, `types`). The promoted fixtures were discovered by walking the candidate subtrees (`api/`, `annotation/`, `generators/`, `lambdas/`, `listings/`, `mappings/`, `methods/`, `objects/`, `types/`) and gating on `diff -q gold actual` byte-equality; new failures still fall outside the curated list and surface as a non-zero exit when the script runs.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-096
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **use upstream apple/pkl fixtures as compatibility checks** — verifies: PKL-011
  > The contract suite references Apple's Pkl repository as a git submodule and runs selected upstream LanguageSnippetTests fixtures through the pure MoonBit CLI.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **when conditional property in Listing / Mapping bodies** — verifies: PKL-136 — tags: parser, evaluator, pkf-pkspec
  > Apple Pkl's `when (cond) { ... } [else { ... }]` form is recognised inside Listing and Mapping bodies as well as object bodies. The parser wraps each block in a new `WhenSpread(ConditionalExpr(cond, then_body, else_body))` Expr variant whose branches reuse `ListingLiteral` / `MappingLiteral` (matching the surrounding context). The evaluator's `ListingLiteral` and `MappingLiteral` arms recognise `WhenSpread` during element / entry iteration and spread the selected branch's contents into the parent collection instead of attaching it as a nested value. Object body `when` was already wired in an earlier slice via the synthetic `@when` ObjectMember; the new variant is additive. A drive-by parser fix in `parse_object_expr` recognises `new Listing<T> { ... }` / `new List<T> { ... }` / `new Mapping<K, V> { ... }` as listing / mapping bodies — previously the generic-tagged forms fell into the `TypedObjectLiteral` arm and silently parsed the body as object members, dropping everything inside.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-001, PKL-002
  - decisions: 3 entry(ies)
  - body: _not yet implemented_

### `Test.pkl`

- [x] **cli amends base merge** — verifies: PKL-137 — tags: moonbit, cli, evaluator, amends, pkf-pkspec, contract
  > The native CLI evaluates a child fixture that `amends` a sibling base module. The base provides a `Test` class, a `Severity` string-literal union typealias, and an empty `tests: Listing<Test>` slot; the child adds one entry referencing the base's class by its bare name. The child's typecheck succeeds (no `unknown type annotation Test`) and the rendered output shows the merged listing.
  - body: `cmd` (exit 0 expected)

- [x] **cli annotation capture** — verifies: PKL-128d — tags: moonbit, cli, parser, annotation, contract
  > The native CLI's `parse` subcommand prints one summary line per captured annotation when at least one was found, identifying the declaration it attaches to (module / class / function / typealias) and the body shape (NoBody / ParenBody / BraceBody) plus the verbatim body text. Annotation-free sources keep the existing one-line `ok` output for byte-identity with prior fixtures.
  - body: `cmd` (exit 0 expected)

- [x] **cli any top type** — verifies: PKL-133 — tags: moonbit, cli, typechecker, any, pkf-pkspec, contract
  > The native CLI evaluates a fixture that exercises `Any`-typed bindings (Int / String / Bool), a nullable `Any?` defaulted to null, and a `Mapping<String, Any>` carrying heterogeneous value types. Every binding typechecks (via the new `AnyType` short-circuit in `type_accepts`) and the evaluator emits the same PCF as the concrete annotations would.
  - body: `cmd` (exit 0 expected)

- [x] **cli codegen moonbit** — verifies: PKL-131 — tags: moonbit, cli, codegen, typechecker, contract
  > The native CLI's `codegen` subcommand lowers a Pkl fixture to MoonBit source. The fixture covers the common shape — scalar + nullable properties, references between classes, Listing / Mapping / Set / IntSeq / Pair generics, and typealias declarations. The expected output exercises the scalar mapping, the recursive generic translation (including the `Array[T] /* Set */` and `Array[Int] /* IntSeq */` fallbacks), nullable round-trip, and the `pub typealias <target> as <name>` form.
  - body: `cmd` (exit 0 expected)

- [x] **cli constraint composition** — verifies: PKL-128c — tags: moonbit, cli, parser, constraints, contract
  > The native CLI evaluates a fixture that composes numeric constraint predicates with `&` (e.g. `Int(isPositive & isLessThan(10))`). Valid values render normally; the dispatcher enforces both halves of the composition independently.
  - body: `cmd` (exit 0 expected)

- [x] **cli cross module function** — verifies: PKL-118 — tags: moonbit, cli, imports, typechecker, contract
  > The native CLI evaluates a module that calls two module-level functions declared in an imported sibling module (`Base.double`, `Base.format`). The eval layer dispatches the lambda bodies against the supplied arguments and the rendered output is the importing module's visible bindings only — the base module's functions are emitted with the hidden-member prefix so a `pkl eval` of the base alone renders nothing extra. Confirms cross-module precision for module-level function exports.
  - body: `cmd` (exit 0 expected)

- [x] **cli diagnostic position** — verifies: PKL-107 — tags: moonbit, cli, diagnostics, position, contract
  > The native CLI parses a fixture with a deliberate syntax error and the output carries a `path:line:column: message` prefix. The diagnostic's byte offset is projected onto a line:column pair so editors can jump to the failing token. The broken fixture lives under `fixtures/error_cases/` so the project formatter doesn't try to round-trip it.
  - body: `cmd` (exit 0 expected)

- [x] **cli diagnostic upstream alignment** — verifies: PKL-108 — tags: moonbit, cli, diagnostics, upstream, contract
  > The native CLI prints first-line diagnostic messages that match Apple Pkl's wording verbatim. The fixture is a module with intentional property and method misses; `pkl eval` surfaces them as `Cannot find property \`<name>\`.` and `Cannot find property \`<name>\` in object of type \`Listing\`.`. Source-position arrows and value-trace blocks stay deferred — pinning the first line is enough for a future upstream-`errors`-fixture sweep to diff against without false positives from prose differences.
  - body: `cmd` (exit 0 expected)

- [x] **cli equality type match** — verifies: PKL-113 — tags: moonbit, cli, typechecker, equality, contract
  > The native CLI evaluates a fixture that exercises `==` and `!=` against compatible operand types — Int vs Int, Int vs Float (Apple Pkl admits this), Float vs Float, Bool vs Bool, and a nullable binding against `null`. The evaluation produces the expected booleans without raising a typecheck diagnostic, demonstrating that PKL-113 leaves valid programs untouched.
  - body: `cmd` (exit 0 expected)

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

- [x] **cli float magnitude units** — verifies: PKL-121 — tags: moonbit, cli, parser, duration, datasize, float, contract
  > The native CLI evaluates a fixture using Float-magnitude Duration and DataSize literals (`0.5.s`, `2.5.gib`, `1.h`, `5.gib`). The rendered output preserves the magnitude and unit, and accessing `.value` projects back to Int when integral or Float when fractional.
  - body: `cmd` (exit 0 expected)

- [x] **cli float numerics and constraints** — verifies: PKL-092 — tags: moonbit, cli, float, constraint, contract
  > The native CLI evaluates a Float-heavy fixture, exercising Float literals, mixed Int / Float arithmetic, `Int / Int` widening to Float, and `Float(isPositive)` / `Float(isBetween(...))` / `Number(isPositive)` constraint predicates.
  - body: `cmd` (exit 0 expected)

- [x] **cli float power intdiv modulo** — verifies: PKL-111 — tags: moonbit, cli, float, operator, contract
  > The native CLI evaluates a fixture that exercises `**`, `~/`, and `%` with Float operands, matching Apple Pkl's golden output: `2.0 ** 3 = 8.0`, `5.0 ~/ 3.0 = 1`, `5.5 % 6.5 = 5.5`, `5 % 6.5 = 5.0`.
  - body: `cmd` (exit 0 expected)

- [x] **cli float threshold constraint predicates** — verifies: PKL-112 — tags: moonbit, cli, constraint, float, contract
  > The native CLI evaluates a fixture that exercises Float thresholds in numeric constraint predicates (`isBetween(0.5, 1.5)`, `isGreaterThan(0.5)`, `isLessThan(1.5)`, `isGreaterThan(-1.5)`) and prints the bindings without raising a constraint diagnostic.
  - body: `cmd` (exit 0 expected)

- [x] **cli format subcommand** — verifies: PKL-099 — tags: moonbit, cli, format, contract
  > The native CLI `format` subcommand re-emits the source through the PCF renderer, normalizing whitespace and indentation. Today the formatter operates on the evaluated module value; trivia-preserving idempotent reformatting is a follow-up.
  - body: `cmd` (exit 0 expected)

- [x] **cli generic call-site inference** — verifies: PKL-110 — tags: moonbit, cli, generics, inference, contract
  > The native CLI evaluates a fixture that depends on substituted generic types: `identity(7) + 1` typechecks and evaluates to `8` because T binds Int at the call site, and `intBox.value + 100` typechecks and evaluates to `105` because Box<T>'s value member instantiates as Int from the literal.
  - body: `cmd` (exit 0 expected)

- [x] **cli generic class and function declarations** — verifies: PKL-089, PKL-090 — tags: moonbit, cli, generics, contract
  > The native CLI evaluates a fixture that declares `class Box<T>`, `class Pair<A, B>`, `function identity<T>(x: T): T`, and `function pair_first<A, B>(a: A, b: B): A`, then instantiates and calls each. Type parameters are tolerated as UnknownType in the typechecker and accept-any in the evaluator's runtime annotation validators.
  - body: `cmd` (exit 0 expected)

- [x] **cli generic typealias** — verifies: PKL-115 — tags: moonbit, cli, typealias, generics, contract
  > The native CLI evaluates a fixture that declares `typealias Box<T> = Listing<T>` and `typealias Pair<K, V> = Mapping<K, V>`, then instantiates `Box<Int>`, `Box<String>`, and `Pair<String, Int>`. Each declaration resolves through `try_generic_alias_substitution`, the listing / mapping elements typecheck against the substituted element types, and the evaluator emits the same PCF as the equivalent non-aliased annotation.
  - body: `cmd` (exit 0 expected)

- [x] **cli heredoc string** — verifies: PKL-128b — tags: moonbit, cli, parser, lexer, string, contract
  > The native CLI evaluates a fixture with triple-quoted heredoc strings. The leading newline is dropped and every line is dedented by the closing delimiter's indentation; the rendered output joins each line back with `\n` separators.
  - body: `cmd` (exit 0 expected)

- [x] **cli https URI import** — verifies: PKL-129 — tags: moonbit, cli, imports, pkf-pkspec, contract
  > The native CLI evaluates a fixture whose `import` declaration points at a raw GitHub URL of another fixture in this repo. The HTTP fetch goes through `mizchi/x/http.get` under a `moonbitlang/async` event loop, and the imported module's bindings become available in the importing module's typecheck / evaluation pipeline.
  - body: `cmd` (exit 0 expected)

- [x] **cli inheritance hardening** — verifies: PKL-117 — tags: moonbit, cli, typechecker, inheritance, contract
  > The native CLI's `check` subcommand surfaces the typechecker's PKL-117 diagnostics for a fixture that trips both rules: `Sparrow extends Bird` without overriding `Bird`'s `abstract function chirp`, and `Mammal.name` overrides `Animal.name` with a return type (`Int`) that is not a subtype of the parent's return type (`String`). The fixture intentionally contains both faults so a single scenario exercises the abstract-method coverage and the return-type covariance checks together.
  - body: `cmd` (exit 0 expected)

- [x] **cli int seq value** — verifies: PKL-119b — tags: moonbit, cli, evaluator, typechecker, stdlib, contract
  > The native CLI evaluates a fixture exercising the dedicated `IntSeqValue` variant: `IntSeq(1, 5)` construction, bare `.start` / `.end` / `.step` property reads, `.toList()` materialization, `.map((x) -> x * 2)` projection, `.fold(0, (acc, x) -> acc + x)` reduction, `.step(2)` to change the step, `.step(-1)` for descending iteration, empty IntSeq materialization, and `IntSeq` annotation participating in typecheck. PCF renders `IntSeq(s, e)` (default step 1) or `IntSeq(s, e).step(n)` (custom step) so the eval output is parser-readable.
  - body: `cmd` (exit 0 expected)

- [x] **cli is operator runtime** — verifies: PKL-114 — tags: moonbit, cli, evaluator, is-operator, contract
  > The native CLI evaluates a fixture that exercises the `is` operator at runtime: `5 is Int`, `1.5 is Float`, `Number` checks against both Int and Float values, a negative check (`"x" is Int = false`), and an `if (x is Int) ...` branch inside a function. No `parser-only` diagnostic is raised — the evaluator routes through `value_is_type` and produces concrete Bool values.
  - body: `cmd` (exit 0 expected)

- [x] **cli lint findings** — verifies: PKL-102 — tags: moonbit, cli, lint, analyze, contract
  > The native CLI's `analyze` subcommand runs lint checks over the parsed module and prints one `path: rule: message` line per finding. The fixture intentionally exercises all four rules: an unused `local` binding, an unused import, an unused property on an unreferenced class, and a binding name that shadows an import. (Exit-code propagation through `moon run` is lossy, so the contract pins on stdout output rather than on the exit code; running the binary directly produces a non-zero exit when any finding surfaces.)
  - body: `cmd` (exit 0 expected)

- [x] **cli listing mapping functional** — verifies: PKL-135 — tags: moonbit, cli, stdlib, pkf-pkspec, contract
  > The native CLI evaluates a fixture that exercises `Listing.flatMap` / `count` / `every` / `any` / `none` / `find` / `findLast` / `findOrNull`, plus `Mapping.every` / `any` / `none` / `count`. Each method routes through `apply_function_value` per element and returns the value Apple Pkl produces for the equivalent call.
  - body: `cmd` (exit 0 expected)

- [x] **cli listing mapping stdlib** — verifies: PKL-134 — tags: moonbit, cli, stdlib, pkf-pkspec, contract
  > The native CLI evaluates a fixture that exercises Listing.toList / length / isEmpty, Mapping.toMap / length / keys / values, and the `List<T>` type annotation. Each method returns the expected value and the rendered PCF matches the equivalent literal.
  - body: `cmd` (exit 0 expected)

- [x] **cli map value** — verifies: PKL-119d — tags: moonbit, cli, evaluator, typechecker, stdlib, contract
  > The native CLI evaluates a fixture exercising the dedicated `MapValue` variant (Apple Pkl's `Map<K, V>`, distinct from `Mapping<K, V>`). `Map("a", 1, ...)` construction, bare property reads (`.length` / `.keys` / `.values` / `.entries`), lookup methods (`.containsKey` / `.getOrNull`), `.map((k, v) -> Pair(...))` projection, `.filter((k, v) -> Boolean)` (keeps Map type), `.fold(0, (acc, k, v) -> ...)` reduction, and `Map<K, V>` annotated bindings whose constructor inference flows through `type_accepts`. PCF renders `Map(k, v, ...)` so the eval output is parser-readable; `.entries` lands as `Listing<Pair<K, V>>` because PKL-119a's PairValue is now part of the value model.
  - body: `cmd` (exit 0 expected)

- [x] **cli math float ops** — verifies: PKL-120 — tags: moonbit, cli, stdlib, pkl-math, float, contract
  > The native CLI evaluates a fixture that imports `pkl:math` and calls `sqrt`, `pow`, `log`, `exp`, `floor`, `ceil`, `round`, plus reads `pi`. Each call returns the expected Float value computed via MoonBit's math intrinsics.
  - body: `cmd` (exit 0 expected)

- [x] **cli new body inference** — verifies: PKL-138 — tags: moonbit, cli, parser, evaluator, pkf-pkspec, contract
  > The native CLI evaluates a fixture that exercises bare `new { ... }` literals dispatched into listing / mapping / object bodies by the first significant token, plus empty `new {}` literals coerced to ListingValue / MappingValue via the binding's type annotation. Chained methods (`emptyListing.toList().map(...)`, `emptyMapping.keys`) succeed because the coercion runs before the method dispatch.
  - body: `cmd` (exit 0 expected)

- [x] **cli output renderer driver** — verifies: PKL-104 — tags: moonbit, cli, renderer, output, contract
  > The native CLI evaluates a fixture that declares `output { renderer = new JsonRenderer {} }` without passing `-f`. The CLI reads the renderer class from the parsed AST, switches the format to `json`, strips the `output` block from the rendered envelope, and prints the JSON projection of the module's other properties.
  - body: `cmd` (exit 0 expected)

- [x] **cli package registry probe** — verifies: PKL-129b1 — tags: moonbit, cli, imports, pkf-pkspec, contract
  > The native CLI follows redirects to `pkg.pkl-lang.org`'s CDN, fetches the metadata JSON, and extracts the `packageZipUrl` field. Hits the real Apple Pkl registry (same approach as `cli https URI import`); the assertion only pins the zip-url line, so registry path changes that keep the same package alive still pass.
  - body: `cmd` (exit 0 expected)

- [x] **cli package uri offline diagnostic** — verifies: PKL-129b1 — tags: moonbit, cli, imports, sandbox, contract
  > The native CLI parses a `package://` URI structurally even when the network is unreachable. The fixture uses an unresolvable authority `invalid.example.test` so the metadata fetch fails predictably; the diagnostic still surfaces the parsed `package URI`, `metadata URL`, `fragment`, plus the manual-workaround block. Pins the structural parse + diagnostic format independently of any live registry.
  - body: `cmd` (exit 0 expected)

- [x] **cli pair value** — verifies: PKL-119a — tags: moonbit, cli, evaluator, typechecker, stdlib, contract
  > The native CLI evaluates a fixture exercising the dedicated `PairValue` variant: top-level `Pair("alpha", 42)`, `.first` / `.second` member access (Pkl scalars), nested `Pair(Pair(...), Pair(...))` (deep member access via `.first.second`), and `Pair<String, Int>` annotated bindings whose typed `.first: String` / `.second: Int` lookups participate in typecheck. PCF renders each Pair through Apple Pkl's `Pair(a, b)` constructor form rather than the previous PKL-139 `new Listing { a; b }` stop-gap.
  - body: `cmd` (exit 0 expected)

- [x] **cli pkspec polish** — verifies: PKL-139 — tags: moonbit, cli, parser, evaluator, stdlib, pkf-pkspec, contract
  > The native CLI evaluates a fixture that exercises the five drive-by gaps that blocked pkspec Test.pkl: brace-bodied `@ModuleInfo` annotation, multi-line typealias RHS, dot-chain across newlines, `module.foo` self-reference, and `List` / `Set` / `Map` / `Pair` constructor functions. The rendered output shows each form producing the expected value.
  - body: `cmd` (exit 0 expected)

- [x] **cli platform semver** — verifies: PKL-123 — tags: moonbit, cli, stdlib, platform, semver, contract
  > The native CLI evaluates a fixture that imports `pkl:platform` and `pkl:semver`. The platform stub yields deterministic `stub-os` / `stub-arch` values; semver `parse("1.2.3-rc.1+build.42")` populates major / minor / patch / preRelease / build, `isLessThan` orders `1.0.0-alpha < 1.0.0` (pre-release ranks below release), and `parseOrNull("not-a-version")` returns null.
  - body: `cmd` (exit 0 expected)

- [x] **cli read nullable** — verifies: PKL-103 — tags: moonbit, cli, evaluator, read, nullable, contract
  > The native CLI evaluates a fixture that uses `read?(uri)` for both a missing env var and a non-`env:` scheme. Both calls return `null` instead of pushing a diagnostic, matching Apple Pkl's null-safe semantics.
  - body: `cmd` (exit 0 expected)

- [x] **cli reflect introspection** — verifies: PKL-143 — tags: moonbit, cli, stdlib, reflect, contract
  > The native CLI evaluates a fixture exercising the `pkl:reflect` introspection surface: `reflect.Class(name).properties` returns each property's `name` / `typeName`, `.methods` exposes return types + parameter types, `.supertype.reflectee` follows `parent_name` one hop, `.isSubclassOf(other)` walks the parent chain (`Puppy → Dog → Animal`), and `reflect.Module("self").classes` lists every class declaration. The hidden `__kind` marker that powers the dispatch never reaches the rendered output.
  - body: `cmd` (exit 0 expected)

- [x] **cli reflect minimal stub** — verifies: PKL-080 — tags: moonbit, cli, pkl-reflect, stdlib, contract
  > The native CLI evaluates a fixture that imports `pkl:reflect` and reads mirror constants plus the `Class` factory `reflectee` field, exercising the minimal stub registered in `builtin_stdlib_source`.
  - body: `cmd` (exit 0 expected)

- [x] **cli renderer converters** — verifies: PKL-105 — tags: moonbit, cli, renderer, converter, contract
  > The native CLI evaluates a fixture whose `output { renderer = new JsonRenderer { converters { ... } } }` declares two path-keyed converters: `["count"] = (v) -> v * 10` and `["server.port"] = (p) -> p + 1`. The post-eval pass rewrites both values before the JSON renderer fires, so `count = 5` shows as 50 and `server.port = 8080` shows as 8081 in the rendered output.
  - body: `cmd` (exit 0 expected)

- [x] **cli renderer plist** — verifies: PKL-126a — tags: moonbit, cli, renderer, plist, contract
  > The native CLI evaluates a fixture whose `output { renderer = new PListRenderer {} }` block routes the rendered envelope through the plist renderer. The output starts with the XML 1.0 prolog, the Apple PLIST 1.0 DOCTYPE, and a `<plist version="1.0">` wrapper; scalars map to `<integer>` / `<real>` / `<true/>` / `<false/>` / `<string>` nodes; XML entities (`<`, `>`, `&`) escape inside `<string>` contents; null entries elide inside `<dict>`; Listings render as `<array>`; Duration / DataSize project as space-separated `<string>3 s</string>` / `<string>4 mb</string>` rather than the `.` form JSON / YAML use. The renderer is selected from the AST without `-f plist`, mirroring the JsonRenderer driver path.
  - body: `cmd` (exit 0 expected)

- [x] **cli renderer stdlib modules** — verifies: PKL-124 — tags: moonbit, cli, stdlib, renderer, contract
  > The native CLI evaluates a fixture that instantiates every renderer-driver class the `output { renderer = ... }` path looks up. `JsonRenderer`, `YamlRenderer`, `PcfRenderer`, `PropertiesRenderer`, and `PListRenderer` are reached unqualified (pkl:base re-exports seeded into `builtin_type_from_annotation`); `xml.Renderer` and `protobuf.Renderer` come through the synthetic `pkl:xml` / `pkl:protobuf` stdlib modules; `json.Parser` rides on the synthetic `pkl:json` module. The rendered output shows each renderer's default-only field surface plus the user-supplied overrides, confirming both typecheck visibility and the import-binding round-trip.
  - body: `cmd` (exit 0 expected)

- [x] **cli sandbox flags** — verifies: PKL-106 — tags: moonbit, cli, sandbox, prop, contract
  > The native CLI accepts `-p NAME=VALUE` (repeatable) to populate the `prop:` resolver. The fixture reads two props via `read("prop:NAME")` and the rendered output binds the values back onto module keys so the contract can pattern-match on them. The flag lifts `prop:` into the `read` allow-list alongside `env:`; without the flag the same `read` call surfaces `read: prop <name> is not set`.
  - body: `cmd` (exit 0 expected)

- [x] **cli scientific float** — verifies: PKL-128b — tags: moonbit, cli, parser, lexer, float, contract
  > The native CLI evaluates a fixture with scientific-notation Float literals (`1e10`, `2.5e-3`, `4E+8`, `1.5e2`). Each literal renders as a Float value with the expected magnitude.
  - body: `cmd` (exit 0 expected)

- [x] **cli set value** — verifies: PKL-119c — tags: moonbit, cli, evaluator, typechecker, stdlib, contract
  > The native CLI evaluates a fixture exercising the dedicated `SetValue` variant: `Set(3, 1, 2, 1, 3)` dedupes to `Set(3, 1, 2)` (insertion order preserved), bare property reads (`.length` / `.isEmpty` / `.first` / `.last`), `.contains` lookup, `.toList()` materialization, `.map((n) -> n * 2)` projection (returns Listing per Apple Pkl's signature), `.filter((n) -> n % 2 == 0)` (keeps Set type), `.fold(0, (acc, n) -> acc + n)` reduction, `.join(", ")` concatenation, and `Set<Int>` annotated bindings whose constructor inference flows through `type_accepts`. PCF renders `Set(...)` so the eval output is parser-readable.
  - body: `cmd` (exit 0 expected)

- [x] **cli stdlib coverage probe** — verifies: PKL-141 — tags: moonbit, cli, stdlib, contract
  > The native CLI's `stdlib` subcommand evaluates one minimal probe per documented stdlib surface area (pkl:base value-variant ops + Renderer classes, pkl:math constants / Int + Float helpers, pkl:semver parse + compare, pkl:platform stub, pkl:test catch, pkl:reflect mirror constants + factories, pkl:json / pkl:yaml Parser shells, pkl:xml / pkl:protobuf Renderer shells) and prints `[PASS]` / `[FAIL]` per probe. The contract pins the trailing `stdlib: N / N passed` summary so a regression to any probe breaks CI.
  - body: `cmd` (exit 0 expected)

- [x] **cli stdlib modifiers** — verifies: PKL-140 — tags: moonbit, cli, parser, stdlib, contract
  > The native CLI evaluates a fixture using stdlib-style declarations: `external` modifier, abstract property slots (no `=` default), `<in T>` / `<out T>` variance modifiers, function type annotations, and a declarations-only module footprint. The rendered output skips abstract slots and keeps the regular bindings; declarations-only fragments evaluate to the empty ObjectValue.
  - body: `cmd` (exit 0 expected)

- [x] **cli string interpolation** — verifies: PKL-128a — tags: moonbit, cli, parser, evaluator, string, contract
  > The native CLI evaluates a fixture that uses `"... \(expr) ..."` interpolation with arithmetic, method calls, and an inner `", "` separator string. The rendered output shows each interpolation site replaced with its evaluated value.
  - body: `cmd` (exit 0 expected)

- [x] **cli string unicode** — verifies: PKL-122 — tags: moonbit, cli, stdlib, string, unicode, contract
  > The native CLI evaluates a fixture that observes a String whose last glyph is a supplementary-plane code point (`🍣`, U+1F363). `length` keeps the existing UTF-16 code-unit count (5) for byte-identity with prior fixtures, while `codePointCount` reports the Unicode code-point count (4), `codePoints` and `chars` walk the code-point stream, and `codePointAt(3)` returns the supplementary code point as an Int.
  - body: `cmd` (exit 0 expected)

- [x] **cli super method call** — verifies: PKL-117a — tags: moonbit, cli, evaluator, inheritance, contract
  > The native CLI evaluates a fixture where a subclass method body calls `super.method()` to chain into the parent class. The rendered output joins the subclass-side prefix with the parent-side return value.
  - body: `cmd` (exit 0 expected)

- [x] **cli test examples diff fail** — verifies: PKL-100 — tags: moonbit, cli, pkl-test, examples, contract
  > When the rendered `examples` envelope diverges from the `<file>-expected.pcf` golden the runner emits `FAIL examples diff against <path>` and contributes to the non-zero exit.
  - body: `cmd` (exit 0 expected)

- [x] **cli test examples gold match** — verifies: PKL-100 — tags: moonbit, cli, pkl-test, examples, contract
  > The native CLI `test` subcommand walks the `examples` member alongside `facts` and reports `PASS examples (N examples)` when the rendered envelope matches the `<file>-expected.pcf` golden byte-for-byte.
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

- [x] **cli type parameter bounds** — verifies: PKL-116 — tags: moonbit, cli, generics, bounds, contract
  > The native CLI evaluates a fixture that exercises `<T : Number>` on a generic function and a generic class: `clamp(5)` returns `5`, `clamp(2.5)` returns `2.5`, and `new Container { value = 42 }` / `{ value = 3.14 }` produce the expected ObjectValue. The fixture intentionally only uses arguments that satisfy the bound; bound rejection is covered by the unit tests.
  - body: `cmd` (exit 0 expected)

- [x] **cli when conditional property** — verifies: PKL-136 — tags: moonbit, cli, parser, evaluator, pkf-pkspec, contract
  > The native CLI evaluates a fixture that uses `when (cond) { ... } [else { ... }]` inside Listing, Mapping, and object bodies, plus `new Listing<T> { ... }` literals. Each conditional emits its inner body when the condition is true, skips it when false, falls back to the else branch when present, and produces the empty collection when no condition fires.
  - body: `cmd` (exit 0 expected)

- [x] **cli yaml block scalars** — verifies: PKL-125 — tags: moonbit, cli, renderer, yaml, block-scalar, contract
  > The native CLI evaluates a fixture that declares `output { renderer = new YamlRenderer {} }` and several multiline String values. The YAML output renders them as literal block scalars: `|` (one trailing newline, clip), `|-` (no trailing newline, strip), `|+` (multiple trailing newlines, keep), with two-space content indentation. Strings whose lines start with whitespace fall back to double-quoted form, and listing items in block context also pick up the block-scalar projection.
  - body: `cmd` (exit 0 expected)

- [x] **moon unit tests** — verifies: PKL-001, PKL-002, PKL-003, PKL-004, PKL-005, PKL-006, PKL-007, PKL-008, PKL-009, PKL-010, PKL-012, PKL-013, PKL-014, PKL-016, PKL-017, PKL-018, PKL-019, PKL-020, PKL-021, PKL-022, PKL-023, PKL-024, PKL-025, PKL-026, PKL-027, PKL-028, PKL-029, PKL-030, PKL-031, PKL-032, PKL-033, PKL-034, PKL-035, PKL-036, PKL-037, PKL-038, PKL-039, PKL-040, PKL-041, PKL-042, PKL-043, PKL-044, PKL-045, PKL-046, PKL-047, PKL-048, PKL-049, PKL-050, PKL-051, PKL-052, PKL-053, PKL-054, PKL-055, PKL-056, PKL-057, PKL-058, PKL-059, PKL-060, PKL-061, PKL-062, PKL-063, PKL-064, PKL-065, PKL-066, PKL-067, PKL-068, PKL-069, PKL-070, PKL-071, PKL-072, PKL-073, PKL-074, PKL-075, PKL-076, PKL-077, PKL-078, PKL-079, PKL-080, PKL-081, PKL-082, PKL-083, PKL-084, PKL-085, PKL-086, PKL-087, PKL-088, PKL-089, PKL-090, PKL-091, PKL-092, PKL-093, PKL-098, PKL-119be, PKL-144, PKL-145, PKL-146, PKL-147, PKL-148, PKL-148b, PKL-148c, PKL-148d — tags: moonbit, unit, contract
  > MoonBit unit tests verify the initial parser, interpreter, typechecker, and ripple-backed analysis session.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl fixture smoke** — verifies: PKL-011, PKL-012, PKL-013, PKL-014, PKL-060, PKL-096, PKL-097, PKL-109, PKL-126a, PKL-144, PKL-147, PKL-148, PKL-148b, PKL-148c, PKL-148d, PKL-148e, PKL-148f, PKL-148g, PKL-148h, PKL-148i, PKL-148j, PKL-148k, PKL-148l, PKL-148m, PKL-148n, PKL-148o, PKL-148p, PKL-148q, PKL-148r, PKL-148s, PKL-148t, PKL-148u, PKL-148v, PKL-148w, PKL-148x, PKL-148y, PKL-148aa, PKL-148ab, PKL-148ac, PKL-148ad, PKL-148ae, PKL-148af, PKL-148ag, PKL-148ah, PKL-148ai, PKL-148aj, PKL-148ak, PKL-148al, PKL-148an, PKL-148ao, PKL-148ap — tags: moonbit, upstream, compatibility, contract
  > Curated `pkl eval` fixtures from the apple/pkl submodule run through the native CLI and diff byte-for-byte against the upstream gold output (PCF and JSON).
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl parser suite** — verifies: PKL-015 — tags: moonbit, upstream, parser, compatibility, contract
  > All apple/pkl LanguageSnippetTests parser fixtures, excluding the same invalid cases as ParserComparisonTest, parse through the native CLI.
  - body: `cmd` (exit 0 expected)

## Spec implementation index

- **PKL-001** — parse arithmetic expressions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-002** — evaluate arithmetic and let bindings
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-003** — reject invalid integer operations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-004** — typecheck source through ripple
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-005** — support initial Pkl object and module syntax
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-006** — support Pkl imports and module resolution
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-007** — support Pkl standard library surface
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-008** — support richer Pkl type semantics
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-009** — provide a usable CLI
  - test: `specs/Test.pkl` — cli eval
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-010** — support Pkl string escape compatibility
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-011** — use upstream apple/pkl fixtures as compatibility checks
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-012** — support Pkl comments and module property forward references
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-013** — support Pkl object body property shorthand
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-014** — support Pkl local module bindings and import expressions
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-015** — parse upstream apple/pkl snippet corpus
  - test: `specs/Test.pkl` — upstream apple pkl parser suite
- **PKL-016** — inventory unsupported syntax in tolerant parser output
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-017** — parse and evaluate Pkl collection expressions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-018** — parse Pkl call lambda and operator expressions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-019** — model Pkl class function and typealias declarations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-020** — support module extends amends and object amendments
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-021** — typecheck incrementally through ripple dependency graph
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-022** — typecheck Pkl function declarations lambdas and calls
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-023** — typecheck Pkl callable parameter and return annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-024** — typecheck Pkl nullable annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-025** — typecheck Pkl generic collection annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-026** — typecheck Pkl nullable and generic typealias annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-027** — typecheck Pkl union type annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-028** — typecheck rich Pkl is and as type operands
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-029** — narrow union types through Pkl is guards
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-030** — narrow union types through compound Pkl boolean guards
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-031** — narrow nullable types through Pkl null guards
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-032** — typecheck Pkl nullable postfix operators
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-033** — typecheck Pkl null-safe invocation chains
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-034** — infer Pkl class property default types
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-035** — allow Pkl class property defaults to satisfy missing members
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-036** — typecheck Pkl typed object expressions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-037** — evaluate Pkl typed object class defaults
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-038** — support Pkl class inheritance defaults
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-039** — support Pkl qualified class inheritance types
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-040** — model Pkl class method declarations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-041** — evaluate Pkl class method invocations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-042** — evaluate Pkl function declarations lambdas and calls
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-043** — typecheck Pkl class method bodies with receiver bindings
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-044** — model Pkl callable runtime values
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-045** — typecheck Pkl constrained type annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-046** — evaluate Pkl constrained type annotation predicates
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-047** — enforce Pkl constrained function parameter annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-048** — preserve Pkl constrained callable signature metadata
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-049** — propagate Pkl constrained callable metadata through higher-order calls
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-050** — enforce Pkl constrained method parameter annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-051** — preserve Pkl constrained typealias metadata
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-052** — evaluate Pkl constrained typealias object member annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-053** — support additional Pkl numeric constraint predicates
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-054** — support multiple Pkl type constraint predicates
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-055** — support negated Pkl type constraint predicates
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-056** — evaluate Pkl user-defined type constraint functions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-057** — parse Pkl const function declarations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-058** — evaluate Pkl constrained class property annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-059** — evaluate Pkl constrained class property default values
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-060** — evaluate upstream Pkl constraint fixture catch flow
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-061** — evaluate simple Pkl callable closure captures
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-062** — evaluate non-scalar Pkl callable closure captures
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-063** — evaluate Pkl callable return annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-064** — evaluate Pkl class method return annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-065** — evaluate constrained Pkl callable return annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-066** — evaluate user-defined constrained Pkl callable arguments
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-067** — typecheck constrained Pkl callable return bodies
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-068** — evaluate typealiased Pkl callable return annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-069** — evaluate typealiased Pkl callable argument annotations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-070** — render Pkl values as PCF primitives
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-071** — render Pkl objects and listings as PCF
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-072** — render Pkl values as JSON
  - test: `specs/Test.pkl` — cli eval json
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-073** — render Pkl values as YAML
  - test: `specs/Test.pkl` — cli eval yaml
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-074** — render Pkl values as Java Properties
  - test: `specs/Test.pkl` — cli eval properties
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-075** — expose pkl:base Listing operations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-076** — expose pkl:base Mapping operations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-077** — expose pkl:base String operations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-078** — expose pkl:base Int operations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-079** — expand pkl:math beyond maxInt32
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-080** — minimal pkl:reflect support
  - test: `specs/Test.pkl` — cli reflect minimal stub
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-081** — Regex literal and Regex methods
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-082** — Duration and DataSize literals with arithmetic comparison and unit conversion
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-083** — Bytes literal and Bytes methods
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-084** — trace and throw built-ins
  - test: `specs/Test.pkl` — cli trace pass-through
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-085** — evaluate object body for-generators
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-086** — evaluate object body when-conditionals
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-087** — hidden and local object members
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-088** — null-coalescing operator and let expressions
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-089** — generic class declarations
  - test: `specs/Test.pkl` — cli generic class and function declarations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-090** — generic function type parameters
  - test: `specs/Test.pkl` — cli generic class and function declarations
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-091** — String constraint predicates
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-092** — Float numerics and constraint predicates
  - test: `specs/Test.pkl` — cli float numerics and constraints
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-093** — Listing and Mapping element constraint propagation
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-094** — CLI --format flag for eval
  - test: `specs/Test.pkl` — cli eval --format long form
  - test: `specs/Test.pkl` — cli eval --format pcf
  - test: `specs/Test.pkl` — cli eval json
  - test: `specs/Test.pkl` — cli eval properties
  - test: `specs/Test.pkl` — cli eval yaml
- **PKL-095** — CLI test runner integrates pkl:test facts
  - test: `specs/Test.pkl` — cli test failing facts
  - test: `specs/Test.pkl` — cli test passing facts
- **PKL-096** — evaluate broader upstream Pkl fixtures with gold byte-diff
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-097** — diff JSON evaluation output against apple/pkl gold files
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-098** — read built-in with sandbox-bounded env: scheme
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-099** — cli format subcommand
  - test: `specs/Test.pkl` — cli format subcommand
- **PKL-100** — pkl test examples and golden diff
  - test: `specs/Test.pkl` — cli test examples diff fail
  - test: `specs/Test.pkl` — cli test examples gold match
- **PKL-102** — pkl analyze lint subcommand
  - test: `specs/Test.pkl` — cli lint findings
- **PKL-103** — nullable read form
  - test: `specs/Test.pkl` — cli read nullable
- **PKL-104** — output renderer driver
  - test: `specs/Test.pkl` — cli output renderer driver
- **PKL-105** — renderer converters
  - test: `specs/Test.pkl` — cli renderer converters
- **PKL-106** — cli sandbox flags
  - test: `specs/Test.pkl` — cli sandbox flags
- **PKL-107** — source position in diagnostics
  - test: `specs/Test.pkl` — cli diagnostic position
- **PKL-108** — diagnostic message text upstream alignment
  - test: `specs/Test.pkl` — cli diagnostic upstream alignment
- **PKL-109** — upstream fixture sweep expansion
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-110** — call-site generic inference
  - test: `specs/Test.pkl` — cli generic call-site inference
- **PKL-111** — Float Power IntDivide and Modulo semantics
  - test: `specs/Test.pkl` — cli float power intdiv modulo
- **PKL-112** — Float-threshold constraint predicates
  - test: `specs/Test.pkl` — cli float threshold constraint predicates
- **PKL-113** — equality typecheck operand match
  - test: `specs/Test.pkl` — cli equality type match
- **PKL-114** — is operator runtime evaluation
  - test: `specs/Test.pkl` — cli is operator runtime
- **PKL-115** — generic typealias instantiation
  - test: `specs/Test.pkl` — cli generic typealias
- **PKL-116** — type parameter bounds
  - test: `specs/Test.pkl` — cli type parameter bounds
- **PKL-117** — inheritance dispatch hardening remaining
  - test: `specs/Test.pkl` — cli inheritance hardening
- **PKL-117a** — super method call
  - test: `specs/Test.pkl` — cli super method call
- **PKL-118** — cross-module typecheck round-trip completeness
  - test: `specs/Test.pkl` — cli cross module function
- **PKL-119a** — Pair Value variant
  - test: `specs/Test.pkl` — cli pair value
- **PKL-119b** — IntSeq Value variant
  - test: `specs/Test.pkl` — cli int seq value
- **PKL-119be** — IntSeq sequence equality
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-119c** — Set Value variant
  - test: `specs/Test.pkl` — cli set value
- **PKL-119d** — Map Value variant for the immutable functional map
  - test: `specs/Test.pkl` — cli map value
- **PKL-120** — pkl:math Float operations
  - test: `specs/Test.pkl` — cli math float ops
- **PKL-121** — Float magnitude Duration and DataSize literals
  - test: `specs/Test.pkl` — cli float magnitude units
- **PKL-122** — String unicode and codepoint methods
  - test: `specs/Test.pkl` — cli string unicode
- **PKL-123** — pkl:platform and pkl:semver stdlib modules
  - test: `specs/Test.pkl` — cli platform semver
- **PKL-124** — pkl:json / pkl:yaml / pkl:xml / pkl:protobuf stdlib modules
  - test: `specs/Test.pkl` — cli renderer stdlib modules
- **PKL-125** — YAML literal block scalars
  - test: `specs/Test.pkl` — cli yaml block scalars
- **PKL-126a** — plist renderer
  - test: `specs/Test.pkl` — cli renderer plist
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-128a** — string interpolation
  - test: `specs/Test.pkl` — cli string interpolation
- **PKL-128b** — scientific Float and triple-quoted heredoc
  - test: `specs/Test.pkl` — cli heredoc string
  - test: `specs/Test.pkl` — cli scientific float
- **PKL-128c** — constraint predicate composition
  - test: `specs/Test.pkl` — cli constraint composition
- **PKL-128d** — annotation class capture
  - test: `specs/Test.pkl` — cli annotation capture
- **PKL-129** — URI imports via https with mizchi/x/http
  - test: `specs/Test.pkl` — cli https URI import
- **PKL-129b1** — package registry probe and structured diagnostic
  - test: `specs/Test.pkl` — cli package registry probe
  - test: `specs/Test.pkl` — cli package uri offline diagnostic
- **PKL-131** — pkl codegen bridge to MoonBit
  - test: `specs/Test.pkl` — cli codegen moonbit
- **PKL-133** — Any top type
  - test: `specs/Test.pkl` — cli any top type
- **PKL-134** — Listing and Mapping stdlib core methods
  - test: `specs/Test.pkl` — cli listing mapping stdlib
- **PKL-135** — Listing and Mapping functional methods
  - test: `specs/Test.pkl` — cli listing mapping functional
- **PKL-136** — when conditional property in Listing / Mapping bodies
  - test: `specs/Test.pkl` — cli when conditional property
- **PKL-137** — amends base module property and type merge
  - test: `specs/Test.pkl` — cli amends base merge
- **PKL-138** — new body inference from first token and binding annotation
  - test: `specs/Test.pkl` — cli new body inference
- **PKL-139** — parser and evaluator polish for pkspec
  - test: `specs/Test.pkl` — cli pkspec polish
- **PKL-140** — Apple Pkl stdlib declaration modifiers
  - test: `specs/Test.pkl` — cli stdlib modifiers
- **PKL-141** — mpkl stdlib coverage probe
  - test: `specs/Test.pkl` — cli stdlib coverage probe
- **PKL-143** — pkl:reflect class / module introspection
  - test: `specs/Test.pkl` — cli reflect introspection
- **PKL-144** — pkl:json.Parser.parse implementation
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-145** — hidden class property modifier
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-146** — pkl:yaml.Parser.parse implementation
  - test: `specs/Test.pkl` — moon unit tests
- **PKL-147** — snippetTest harness foundation
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148** — pkl:base method surface expansion first wave
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148aa** — super property access in class default body
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ab** — class methods bare-name resolution in class default body
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ac** — module-level super dispatch for extends
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ad** — at-prefix local dep import resolution
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ae** — constraint cascade extends to List Map Optional element walks
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148af** — callable arg type rejection walks collection elements
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ag** — object-body local function and unknown-type diagnostic
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ah** — module self-ref partial visibility plus amend parent member fallback
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ai** — string literal type union plus startsWith endsWith contains string constraints
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148aj** — object body member header dispatch absorbs const and other modifier prefixes
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ak** — deferred property error sentinel hides from output and fires on bare identifier reads
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148al** — PCF triple-quoted heredoc form plus Dynamic property-before-element projection
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148an** — raw string literal with arbitrary hash count for single-line and heredoc forms
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ao** — raw string interpolation plus raw escape decoding plus unicode escape plus heredoc backslash
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148ap** — amend chain plus multi-line union typealias plus listing element append
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148aq** — super late binding amend lambda form class-aware object equality
  - _No active implementation._
- **PKL-148b** — pkl:base method surface second wave
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148c** — runtime evaluation of arbitrary constraint expressions
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148d** — class-as-value reflect mirror plus lexical scope walk
  - test: `specs/Test.pkl` — moon unit tests
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148e** — object body forward refs amend super and Function apply surface
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148f** — unordered equality plus typed-property default synthesis
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148g** — lambda identity equality virtual method dispatch and this.X access
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148h** — ListValue split from ListingValue for List constructor PCF round-trip
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148i** — literal-valued class property assignments enforce declared type
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148j** — local and hidden member visibility split with Collection default
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148k** — Mapping literal duplicate scalar key detection and pipe operator diagnostic
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148l** — Callable parameter basic-type rejection fires before body evaluation
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148m** — local modifier on class / function / typealias declarations
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148n** — as cast accepts generic-wrapped heads and local bindings inside listing bodies
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148o** — catchOrNull wiring catch no-throw wording bare callable constraint diagnostic
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148p** — shebang preamble at module start consumed as trivia
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148q** — output.text emitted verbatim and upstream smoke diff goes bytewise
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148r** — triple-dot import resolves through ancestor directories
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148s** — spread members in object listing and mapping bodies
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148t** — callable return / argument type checks resolve aliases generics and unions
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148u** — structural type rejection with lazy per-property class-default semantics
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148v** — class parent typealias resolved through alias chain
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148w** — subscript amend on Listing with out-of-range diagnostic
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148x** — Dynamic value shape via element and subscript sentinel members
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-148y** — listing amend body tolerates when for spread generator members
  - test: `specs/Test.pkl` — upstream apple pkl fixture smoke
- **PKL-149** — Resource type for read return values
  - _No active implementation._
- **PKL-150** — as and pipe operator runtime semantics
  - _No active implementation._
- **PKL-153** — Silent-mismatch survey
  - _No active implementation._
