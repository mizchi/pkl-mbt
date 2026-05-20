# Release TODO

Current coverage: 275 / 391 PCF gold-match (70.3%).
Last verified with `pkf run coverage` / `scripts/coverage-by-category.sh` on 2026-05-21.

Release focus:

- `basic`: 70 PASS / 16 DIFF
- `generators`: 14 PASS / 7 DIFF

Planned order:

1. Done: Priority 4: Spread And Predicate Member Semantics
2. Current: Priority 3: `for` / Shape-Aware Object Body Evaluation
3. Priority 2: Resource And Glob Host Surface
4. Renderer API surface: keep the advertised output formats honest
5. Priority 1: Numeric And Bytes Parity
6. Priority 5: remaining Generic `as` / `is` / Typed Collection Retention

Priority 6 is deferred unless it becomes a direct blocker for one of the above slices.

## Release Blocker Triage

End-user blocker priority is based on "will a normal Pkl config author hit this?", not raw gold-match count.

1. `for` / generators: real configs use list/map comprehensions and generated object bodies. The remaining generator DIFFs share one root problem: generated members must preserve whether they are properties, elements, or entries until the target object projects them.
2. Resource / read / glob: file/resource access, `read*()`, and `import*` glob behavior are release blockers for multi-file configs and CLI usage.
3. Renderer API surface: `api` has many DIFFs, but not all are equal. Treat public output formats as blockers only if we advertise them for this release. Keep `pcf` / `json` stable, then decide whether `yaml`, `properties`, XML, Protobuf, plist, and JSONNet are release-supported or experimental.
4. Basic scalar / collection parity: `Int`, `Float`, `Bytes`, `DataSize`, `Duration`, and `Map` differences are real but narrower than generators/resource access.
5. Deep stdlib / reflect parity: important for long-term compatibility, but not a first release blocker unless a public API or real package depends on it.

For this release pass, start with `for` support before Resource / Glob. The first target is untyped element / entry generators; typed generators and lexical-scope cases follow after member-kind preservation is stable.

## Current DIFF Snapshot

Measured from the release binary against Apple Pkl LanguageSnippetTests gold files.

`basic` remaining DIFFs:

- `basic/amendsChains`
- `basic/as`
- `basic/bytes`
- `basic/constModifier`
- `basic/dataSize`
- `basic/duration`
- `basic/float`
- `basic/importGlob`
- `basic/int`
- `basic/map`
- `basic/new`
- `basic/newType`
- `basic/nullable`
- `basic/read`
- `basic/readGlob`
- `basic/underscore`

`generators` remaining DIFFs:

- `generators/elementGenerators`
- `generators/elementGeneratorsTyped`
- `generators/entryGenerators`
- `generators/entryGeneratorsTyped`
- `generators/forGeneratorInFunctionBody`
- `generators/forGeneratorInMixins`
- `generators/forGeneratorLexicalScope`

Adjacent typed-collection DIFFs worth pulling into Priority 5:

- `listings/typeCheck`
- `listings2/typeCheck`
- `mappings/typeCheck`
- `mappings2/typeCheck`

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

This is the current active slice. It is the main blocker for `generators` and larger than fixture-by-fixture patching.

Target fixtures:

- `generators/elementGenerators`
- `generators/elementGeneratorsTyped`
- `generators/entryGenerators`
- `generators/entryGeneratorsTyped`
- `generators/forGeneratorInFunctionBody`
- `generators/forGeneratorInMixins`
- `generators/forGeneratorLexicalScope`
- `basic/underscore`
- Some of `basic/amendsChains`

Problem:

Current `@for` evaluation eventually collapses generated content into `ObjectValue`. Apple Pkl effectively evaluates object bodies as a member stream that preserves whether each member is a property, element, or entry. Listing, Mapping, and Dynamic then project that stream differently.

Execution plan:

1. Red: pin direct upstream diffs for `generators/elementGenerators` and `generators/entryGenerators`, plus focused unit tests for generated element vs entry preservation.
2. Green: introduce the smallest member-stream representation needed for object-body `for`, without rewriting unrelated amend/eval paths.
3. Extend iteration binding semantics for one-var and two-var loops over `Listing`, `List`, `Set`, `IntSeq`, `Mapping`, `Map`, and `Dynamic`.
4. Add typed generator support once untyped element / entry generators are stable.
5. Then handle `forGeneratorInFunctionBody`, `forGeneratorInMixins`, and `forGeneratorLexicalScope`; defer broader `outer` / const provenance unless these fixtures require it directly.

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

Status: completed by targeted member-kind preservation for predicate members and spread syntax. The broader member-stream redesign remains Priority 3.

Completed in this slice:

- `generators/predicateMembersDynamicListing`
- `generators/predicateMembersDynamicMapping`
- `generators/predicateMembersListing`
- `generators/predicateMembersMapping`
- `generators/spreadSyntaxDynamic`
- `generators/spreadSyntaxListing`
- `generators/spreadSyntaxMapping`

Completed work:

- Made `...x` target-aware:
  - Listing accepts elements only.
  - Mapping accepts entries only.
  - Dynamic accepts properties, elements, and entries while preserving kind and order.
- Emitted Apple-compatible diagnostics for spreading wrong member kinds.
- Made `[[ pred ]] { ... }` filter Listing / Mapping / Dynamic members with correct `this`, key, and value binding for the upstream generator fixtures.
- Preserved enough member source through generated predicate / spread bodies to gold-match the seven targeted fixtures.

Main dependencies:

- Full duplicate detection that understands property names and entry keys separately is still a follow-up if it appears in a non-gold fixture or user report.
- Existing predicate-member machinery in `eval_amend.mbt`.

## Priority 5: Generic `as` / `is` / Typed Collection Retention

Important for both `basic` and typed generator fixtures. Medium-to-large design surface.

Completed in this slice:

- `basic/is`
- `basic/is2`
- `basic/as2`
- `basic/as3`

Implemented work:

- Added a deep runtime matcher for `is` that checks strict collection classes, generic collection elements, string-literal branches, nullable / union branches, function arity, Class mirrors, and user-class tags / inherited class tags.
- Fixed parenthesized `is Map<K, V>` parsing so commas inside generic angle brackets do not turn `!(...)` into `UnsupportedExpr`.
- Added generic `as` cast overlays for `List`, `Set`, `Map`, `Listing`, and `Mapping`; immutable collections validate eagerly while `Listing` / `Mapping` preserve deferred element / value errors until access.
- Preserved lazy collection-local bindings in Listing / Mapping bodies so earlier dynamic elements are not invalidated by later unused locals, and collection-local `local x` shadows module cache during eval and type resolution.
- Kept renderer-class casts compatible with `ValueRenderer` so `api/pcfRenderer9` remains gold-match.

Target fixtures:

- `basic/as`
- `basic/new`
- `basic/newType`
- typed generator fixtures

Required work:

- Close the remaining `basic/as` edge cases that are not covered by `basic/as2` / `basic/as3`.
- Improve `is` for generic collection types and constrained types.
- Stabilize object class identity for user classes, reflect `Class`, and diagnostics.
- Represent function type arity in diagnostics (`Function1`, `Function2`) where Apple Pkl expects it.
- Finish `Mixin` / `Mixin<T>` apply and pipe support for `newType`.

Main dependencies:

- Collection type-overlay design.
- Class tag / reflect class consistency.
- Callable type metadata.
- Some Priority 3 work for typed generated bodies.

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

## Issue Sync

- #4 Lazy local evaluation: implemented through the local-scope fixture slice and closed as completed.
- #6 XML / Protobuf renderer bodies: release blocker only if XML / Protobuf are release-supported output formats; otherwise document them as experimental follow-up.
- #8 Umbrella practical blockers: update after each release slice.
- #1 Stdlib module evaluation gaps: relevant for long-term stdlib parity, especially external declarations, variance, and `pkl:` module loading.

## Suggested Release Path

1. Start with Priority 3 `for` support: untyped element / entry generators first, then typed generators, then function/mixin/lexical-scope cases.
2. Follow with Priority 2 Resource / Glob so multi-file configs and CLI host reads behave predictably.
3. Decide and document the release-supported renderer set. Fix only those API renderer fixtures as blockers; leave the rest marked experimental.
4. Take Priority 1 for scalar / Bytes / Map parity.
5. Return to remaining Priority 5 and Priority 6 edge cases only when they block a supported fixture or real package.
