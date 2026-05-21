# Release TODO

Current coverage: 315 / 391 PCF gold-match (80.6%).
Last verified with `pkf run coverage` / `scripts/coverage-by-category.sh` on 2026-05-21.

Release focus:

- `basic`: 80 PASS / 6 DIFF
- `generators`: 21 PASS / 0 DIFF

Planned order:

1. Done: Priority 4: Spread And Predicate Member Semantics
2. Done: Priority 3: `for` / Shape-Aware Object Body Evaluation
3. Done: Priority 2: Resource And Glob Host Surface for with-gold `basic/read`, `basic/readGlob`, and `basic/importGlob`
4. Done: Priority 1: Numeric And Bytes Parity
5. Current: Renderer API surface: keep the advertised output formats honest
6. Priority 5: remaining Generic `as` / `is` / Typed Collection Retention

Priority 6 is deferred unless it becomes a direct blocker for one of the above slices.

## Release Blocker Triage

End-user blocker priority is based on "will a normal Pkl config author hit this?", not raw gold-match count.

1. Resource / read / glob: file/resource access, `read*()`, and `import*` glob behavior are release blockers for multi-file configs and CLI usage.
2. `for` / generators: completed for with-gold upstream fixtures. Keep this as a regression-sensitive area because real configs use list/map comprehensions and generated object bodies heavily.
3. Renderer API surface: `api` has many DIFFs, but not all are equal. Treat public output formats as blockers only if we advertise them for this release. Keep `pcf` / `json` stable; renderer converter coverage now includes direct `renderDocument` / `renderValue` calls across PCF / JSON / YAML / plist / XML, validation diagnostics for non-renderable values, XML class-keyed converters, path-keyed wildcard converters, direct CDATA/comment helpers, and `xml.Element` rename fixtures. Protobuf text currently covers the promoted `protobuf3.txtpb` path; decide whether the remaining XML / Protobuf diagnostics and inline formatting are release-supported or experimental.
4. Basic scalar / collection parity: `Bytes`, `DataSize`, `Duration`, `Int`, `Float`, `Map`, and nullable semantics are gold-matching for `basic`; remaining first-release scalar / collection gaps are long-tail `as` / `new` / const provenance cases.
5. Deep stdlib / reflect parity: important for long-term compatibility, but not a first release blocker unless a public API or real package depends on it.

For this release pass, Resource / Glob, Numeric / Bytes, nullable basics, and the advertised renderer validation surface are gold-matching for their targeted fixtures.

## Current DIFF Snapshot

Measured from the release binary against Apple Pkl LanguageSnippetTests gold files.

`basic` remaining DIFFs:

- `basic/amendsChains`
- `basic/as`
- `basic/constModifier`
- `basic/new`
- `basic/newType`
- `basic/underscore`

`generators` remaining DIFFs: none.

Adjacent typed-collection DIFFs: `listings/typeCheck` and `mappings/typeCheck` now gold-match.

## Priority 1: Numeric And Bytes Parity

Status: completed for the targeted `basic` fixtures. `basic/bytes`, `basic/dataSize`, `basic/duration`, `basic/float`, `basic/int`, and `basic/map` now gold-match.

Low-risk, local fixes that should improve `basic` without large evaluator surgery.

Target fixtures:

- `basic/float`
- `basic/int`
- `basic/map`

Required work:

- [x] Support `Bytes(1, 2, 3)` varargs in addition to `Bytes(new Listing { ... })`.
- [x] Add Bytes equality, concatenation, subscript, iteration, `List<Int>.toBytes()`, diagnostics, and PCF rendering parity; `basic/bytes` now gold-matches.
- [x] Finish `Duration` / `DataSize` arithmetic: `/`, `~/`, `**`, division by same unit returning `Float` / `Int`, and Apple-style unsupported-operator diagnostics; `basic/duration` and `basic/dataSize` now gold-match.
- [x] Tighten unit normalization and display choice for mixed-unit `Duration` / `DataSize`.
- [x] Finish Float exponent literal / underscore formatting edge cases, subnormal parsing, and PCF exponent formatting; `basic/float` now gold-matches.
- [x] Finish Int exponent edge cases: negative exponent results for `0`, `1`, `-1`, overflow diagnostics, and `math.maxInt*` constants; `basic/int` now gold-matches.
- [x] Add Map subscript parity and missing-key diagnostics; `basic/map` now gold-matches.

Main dependencies:

- `pkl:math` constants surface.
- Scalar PCF formatting.
- Existing scalar stdlib paths in `eval_stdlib_scalar.mbt`.

## Priority 2: Resource And Glob Host Surface

Status: completed for the with-gold `basic/read`, `basic/readGlob`, and `basic/importGlob` fixtures. Keep the remaining sandbox-policy decisions as release-scope product choices, not gold blockers.

Target fixtures:

- `basic/read`
- `basic/readGlob`
- `basic/importGlob`

Required work:

- [x] Match file-backed `read()` resource shape for the current sandbox cache: `uri`, `text`, `base64`.
- [x] Support `env:` and `prop:` reads with Apple-compatible missing-resource diagnostics.
- [x] Add `read*()` Mapping results for file cache, `env:` glob, and `prop:` glob.
- [x] Add CLI file globstar suffix scanning, simple character classes, deterministic ordering, and unsafe URI character encoding for file resources.
- [x] Add package-cache-backed `read*()` resources and `import*()` ordered key discovery for package URI globs.
- [x] Implement top-level `import* ... as name` clause binding and inferred-name binding.
- [x] Add deferred directory diagnostics for `import*("").toMap()` and direct directory glob matches.
- [x] Resolve file-backed `import*` module values lazily on member access and mapping predicate amends.
- [x] Synthesize `output.text` for amended imported modules with renderer blocks.
- [x] Gold-match `read()` and `read*()` fixture env / prop / file behavior under the controlled upstream snippet-test host environment.
- [ ] Finish `read*()` empty glob behavior if a user-facing repro appears outside the current gold fixtures.
- [x] Finish lazy `import*` module-value parity for file glob amends and package URI globs.
- [x] Preserve Apple-compatible visible URI normalization for globstar parent segments such as `**/../`.
- [x] Preserve escaped wildcard literal chars in raw `import*` URI strings.
- [x] Resolve package-glob module bodies through dependency aliases instead of the current key-only fallback.
- [x] Reconcile `import*` directory diagnostic URI rendering where Apple gold uses `$snippetsDir` placeholders.
- [ ] Decide whether direct `file:` / `https:` / `package:` `read()` should be release-supported or stay sandbox-blocked.

Main dependencies:

- CLI sandbox/resource policy.
- Glob implementation.
- Existing package cache / `package://` resolver.
- Package metadata alias resolution for globbed package module bodies.

## Priority 3: Shape-Aware Object Body Evaluation

Status: completed for all with-gold `generators` fixtures. Keep the focused tests and smoke entries as regression coverage because this slice changed object-body member-kind and lexical-scope evaluation.

Target fixtures:

- `generators/forGeneratorInFunctionBody`
- `generators/forGeneratorInMixins`
- `generators/forGeneratorLexicalScope`
- `basic/underscore`
- Some of `basic/amendsChains`

Problem:

Current `@for` evaluation eventually collapses generated content into `ObjectValue`. Apple Pkl effectively evaluates object bodies as a member stream that preserves whether each member is a property, element, or entry. Listing, Mapping, and Dynamic then project that stream differently.

Completed in this slice:

- `generators/elementGenerators`
- `generators/entryGenerators`
- `generators/elementGeneratorsTyped`
- `generators/entryGeneratorsTyped`
- `generators/forGeneratorInFunctionBody`
- `generators/forGeneratorInMixins`
- `generators/forGeneratorLexicalScope`

Implemented work:

- Parse `for` inside explicit Listing / Mapping bodies as Listing / Mapping body streams, not as ordinary unsupported expressions.
- Normalize `for` sources into `(key, value)` iteration entries: Listing/List/Set/IntSeq/Bytes use numeric indexes, Mapping/Map use entry keys, and Dynamic/Object iterates properties, entries, then elements.
- Reject duplicate generated Dynamic entry keys with Apple-compatible `Duplicate definition of member ...` diagnostics.
- Preserve typed `for` binding annotations in the AST and validate generated key/value bindings with Apple-compatible type diagnostics.
- Split object-body lexical scope from implicit receiver scope so `for` source/key expressions keep function/lambda bindings while generated values can still read prior object properties.
- Apply `Mixin` objects through `|>` for Listing / Mapping targets, including generated entries from `Mixin<Mapping<...>>`.
- Clear deferred class-default diagnostics when constructor overrides make a re-evaluated default valid, covering nested generator access through `new App { n = _n }.list`.

Execution plan:

1. Done: pin direct upstream diffs for `generators/elementGenerators` and `generators/entryGenerators`, plus focused unit tests for generated element vs entry preservation.
2. Done: introduce the smallest member-stream representation needed for object-body `for`, without rewriting unrelated amend/eval paths.
3. Done: extend iteration binding semantics for one-var and two-var loops over `Listing`, `List`, `Set`, `IntSeq`, `Bytes`, `Mapping`, `Map`, and `Dynamic`.
4. Done: add typed generator support now that untyped element / entry generators are stable.
5. Done: handle `forGeneratorInFunctionBody` and `forGeneratorInMixins`.
6. Done: handle `forGeneratorLexicalScope`.

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

Status: completed by targeted member-kind preservation for predicate members and spread syntax.

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
- Fixed lazy typed generated Listing / Mapping values for `listings2/typeCheck` and `mappings2/typeCheck`.
- Fixed union-aware typed collection retention for `listings/typeCheck` and `mappings/typeCheck`, including lazy single-collection union branches, eager Set hash validation, `Pair<T, U>` nested collection annotations, and `new Mapping<K, V>` type-argument retention.

Target fixtures:

- `basic/as`
- `basic/new`
- `basic/newType`

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
- #6 XML / Protobuf renderer bodies: all upstream XML `.xml` renderer fixtures now promote (`xmlRenderer1`, `xmlRenderer2`, `xmlRenderer3`, `xmlRenderer6`, `xmlRenderer9`, `xmlRendererCData`, `xmlRendererElement`, `xmlRendererInline`, `xmlRendererInline2`, `xmlRendererInline3`, `xmlRendererHtml`); direct renderer-method / validation PCF fixtures now cover `pcfRenderer2b`, `pcfRenderer4`, `pcfRenderer5`, `jsonRenderer2b`, `jsonRenderer4`, `jsonRenderer5`, `yamlRenderer2b`, `yamlRenderer4`, `yamlRenderer5`, `plistRenderer2b`, `pListRenderer4`, `pListRenderer5`, `propertiesRenderer4`, `propertiesRenderer5`, `xmlRenderer2b`, `xmlRenderer4`, `xmlRenderer5`, `xmlRendererValidation10`, and `xmlRendererValidation11`; Protobuf text still promotes `protobuf3.txtpb`. Remaining Protobuf gaps are release blockers only if those advanced surfaces are release-supported output formats; otherwise document them as experimental follow-up.
- #8 Umbrella practical blockers: update after each release slice.
- #1 Stdlib module evaluation gaps: relevant for long-term stdlib parity, especially external declarations, variance, and `pkl:` module loading.

## Suggested Release Path

1. Decide and document the release-supported renderer set. Fix only those API renderer fixtures as blockers; leave the rest marked experimental.
2. Return to remaining Priority 5 and Priority 6 edge cases only when they block a supported fixture or real package.
