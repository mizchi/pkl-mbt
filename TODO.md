# Release TODO

Current coverage: 271 / 391 PCF gold-match (69.3%).

Release focus:

- `basic`: 66 PASS / 20 DIFF
- `generators`: 14 PASS / 7 DIFF

Planned order:

1. Priority 4: Spread And Predicate Member Semantics
2. Priority 5: Generic `as` / `is` / Typed Collection Retention
3. Priority 1: Numeric And Bytes Parity
4. Priority 2: Resource And Glob Host Surface
5. Priority 3: Shape-Aware Object Body Evaluation

Priority 6 is deferred unless it becomes a direct blocker for one of the above slices.

## Priority 1: Numeric And Bytes Parity

Low-risk, local fixes that should improve `basic` without large evaluator surgery.

Target fixtures:

- `basic/bytes`
- `basic/dataSize`
- `basic/duration`
- `basic/float`
- `basic/int`
- `basic/map`

Required work:

- [x] Support `Bytes(1, 2, 3)` varargs in addition to `Bytes(new Listing { ... })`.
- Add Bytes equality, concatenation, subscript, iteration, and PCF rendering parity.
- Finish `Duration` / `DataSize` arithmetic: `/`, `~/`, `**`, division by same unit returning `Float` / `Int`, and Apple-style unsupported-operator diagnostics.
- Tighten unit normalization and display choice for mixed-unit `Duration` / `DataSize`.
- Finish Float exponent literal / underscore formatting edge cases and PCF exponent formatting.
- Finish Int exponent edge cases: negative exponent results for `0`, `1`, `-1`, overflow diagnostics, `math.maxInt*` constants.
- Add Map subscript parity and missing-key diagnostics.

Main dependencies:

- `pkl:math` constants surface.
- Scalar PCF formatting.
- Existing scalar stdlib paths in `eval_stdlib_scalar.mbt`.

## Priority 2: Resource And Glob Host Surface

Mostly CLI / host service work. Useful for release because it affects real-world file/resource use.

Target fixtures:

- `basic/read`
- `basic/readGlob`
- `basic/importGlob`

Required work:

- Match Apple Pkl `read()` resource shape: `uri`, `text`, `base64`.
- Support `env:` and `prop:` reads with Apple-compatible missing-resource diagnostics.
- Canonicalize file URIs and encode unsafe URI characters.
- Implement `read*()` globstar, character classes, empty glob behavior, and directory diagnostics.
- Implement `import*` glob ordering and inferred keys.
- Extend package-cache path to package glob cases if needed.

Main dependencies:

- CLI sandbox/resource policy.
- Glob implementation.
- Existing package cache / `package://` resolver.

## Priority 3: Shape-Aware Object Body Evaluation

This is the main blocker for `generators`. It is larger than fixture-by-fixture patching.

Target fixtures:

- `generators/elementGenerators`
- `generators/elementGeneratorsTyped`
- `generators/entryGenerators`
- `generators/entryGeneratorsTyped`
- `generators/forGeneratorLexicalScope`
- `basic/underscore`
- Some of `basic/amendsChains`

Problem:

Current `@for` evaluation eventually collapses generated content into `ObjectValue`. Apple Pkl effectively evaluates object bodies as a member stream that preserves whether each member is a property, element, or entry. Listing, Mapping, and Dynamic then project that stream differently.

Required work:

- Introduce or simulate a member-stream representation for object body evaluation.
- Preserve property / element / entry kind through nested `for`, `when`, and spread.
- Iterate `Listing`, `List`, `Set`, `IntSeq`, `Bytes`, `Mapping`, `Map`, and `Dynamic` with Apple-compatible one-var and two-var binding semantics.
- Fix Dynamic iteration order: properties, elements, entries as Apple expects.
- Preserve loop variables through nested lambdas and nested generators.

Main dependencies:

- `eval_for_generator` redesign.
- `when` body flattening.
- Dynamic member-kind representation.
- Bytes iteration from Priority 1.

## Priority 4: Spread And Predicate Member Semantics

Depends on shape-aware body evaluation.

Completed in this slice:

- `generators/predicateMembersDynamicListing`
- `generators/predicateMembersDynamicMapping`
- `generators/predicateMembersListing`
- `generators/predicateMembersMapping`
- `generators/spreadSyntaxDynamic`
- `generators/spreadSyntaxListing`
- `generators/spreadSyntaxMapping`

Target fixtures:

- Some of `basic/amendsChains`

Required work:

- Make `...x` target-aware:
  - Listing accepts elements only.
  - Mapping accepts entries only.
  - Dynamic accepts properties, elements, and entries while preserving kind and order.
- Emit Apple-compatible diagnostics for spreading wrong member kinds.
- Detect duplicate entries / properties during spread and amend.
- Make `[[ pred ]] { ... }` filter Listing / Mapping / Dynamic members with correct `this`, key, and value binding.
- Preserve member source through chained amends.

Main dependencies:

- Priority 3 member-stream model.
- Duplicate detection that understands property names and entry keys separately.
- Existing predicate-member machinery in `eval_amend.mbt`.

## Priority 5: Generic `as` / `is` / Typed Collection Retention

Important for both `basic` and typed generator fixtures. Medium-to-large design surface.

Target fixtures:

- `basic/as`
- `basic/as2`
- `basic/as3`
- `basic/is`
- `basic/is2`
- `basic/new`
- `basic/newType`
- typed generator fixtures

Required work:

- Preserve type overlays from casts such as `x as Listing<String>` until element access.
- Apply collection element / key / value constraints lazily on access.
- Extend overlay support consistently across `List`, `Set`, `Map`, `Listing`, and `Mapping`.
- Improve `is` for generic collection types and constrained types.
- Stabilize object class identity for user classes, reflect `Class`, and diagnostics.
- Represent function type arity in diagnostics (`Function1`, `Function2`) where Apple Pkl expects it.
- Finish `Mixin` / `Mixin<T>` apply and pipe support for `newType`.

Main dependencies:

- Collection type-overlay design.
- Class tag / reflect class consistency.
- Callable type metadata.
- Some Priority 3/4 work for typed generated bodies.

## Priority 6: `outer` And Const Provenance

Needed for correctness, but less likely to unlock many fixtures quickly unless implemented cleanly.

Target fixtures:

- `basic/constModifier`
- Some `basic/nullable`
- Generator lexical-scope edge cases

Required work:

- Add lexical parent receiver stack for `outer`.
- Ensure nested object literal evaluation can resolve `outer.<name>` independently of `this`.
- Track const provenance for properties, local consts, and functions.
- Reject non-const references in const contexts with Apple-compatible diagnostics.

Main dependencies:

- Object evaluation environment stack.
- Binding/function metadata carrying `const`.
- Import/module snapshot support for const access across modules.

## Existing Open Issues To Reconcile

- #4 Lazy local evaluation: still important, but current `basic` / `generators` DIFF list is not primarily blocked by it.
- #6 XML / Protobuf renderer bodies: release blocker for API renderer parity, separate from `basic` / `generators`.
- #8 Umbrella practical blockers: update after each release slice.
- #1 Stdlib module evaluation gaps: relevant for long-term stdlib parity, especially external declarations, variance, and `pkl:` module loading.

## Suggested Release Path

1. Start with Priority 4. Extract only the minimal member-stream support needed for spread and predicate members instead of doing the full Priority 3 redesign first.
2. Move to Priority 5 while typed generated bodies and collection overlays are fresh.
3. Then take Priority 1 for lower-risk `basic` scalar wins.
4. Follow with Priority 2 for host/resource parity.
5. Finish with the broader Priority 3 evaluator redesign once the smaller generator semantics have forced the required shape.
