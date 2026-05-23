# Release TODO

Current version: `0.2.0` (see `moon.mod.json`).
Current coverage: 376 / 391 PCF gold-match (96.2%).
Last verified with `pkf run coverage` / `scripts/coverage-by-category.sh` on 2026-05-22.

## 0.2.0 landing notes

Embedded-host blockers cleared during the 0.2.0 round:

- `extends "X.pkl"` chain now late-binds against the derived module's overrides via a parent-`Binding[]` resolver thread; parent-local references inside parent visibles (`local testNames = tests.toList()...; output { value = ... duplicateNames ... }`) propagate derived `tests {}` amends instead of returning the parent-static cached value. `localModuleMemberOverride2` remains gold-matched — derived `local p2 = "override"` does NOT shadow `parent.local p2`.
- Cross-module recursive functions and module-locals — `function f(...)` imported from another module can recurse into itself and call sibling functions / `local` helpers via a post-pass that cross-links each top-level function's captured env with `(siblings, module_locals)` once all functions exist.
- `Listing<T>` / `Mapping<K,V>` return types now drive the `new {}` rewrite even when the body is `let (...) new { ... }`. Apple Pkl's listing-vs-object disambiguation is satisfied for the common QuickCheck pattern.
- `mpkl test --junit-reports <dir>` emits a JUnit XML envelope (one `<testsuite>` per module, one `<testcase>` per fact + one for `examples`). Eval-time errors surface as a single failed `<testcase name="eval">`. The text-mode summary is unchanged.
- `configure_sandbox_resource_reader(scheme, reader)` lets an embedded caller service `read("scheme:path")` in-process — pkspec / pkfire's `cmd:` reader use case without a separate subprocess.

Post-0.2.0 fixes (2026-05-24 on `main`, queued for 0.2.1):

- **PKL-153** (`dc1c86c`): self-referential `Listing<T>` / `Mapping<K, T>` default expansion no longer infinite-loops. A class with `class Task { deps: Listing<Task> = new {} }` used to hang mpkl indefinitely; `apply_collection_default_for_type`'s call to `synthesize_default_for_type` reset the seen-set, recursing forever on the element type. A `materializing` marker on `ClassDefaultMemoEntry` records the in-flight class name so element-default synthesis on a self-referential type short-circuits to the empty shape (the materialised default is unobservable for an empty collection anyway).
- **PKL-153a** (`72465cf`): `MemberAccess(Identifier("module"), X)` no longer false-positives "cyclic property reference X" when an inner object-literal body declares a field whose name shadows a module-level binding (`new R { defaults = module.defaults }` inside a derived module's `output.value` re-eval). The fix reorders the bindings list so the module-level binding wins `find_binding`'s reverse walk instead of the inner shadow.
- **PKL-153b** (`f0a5a7f`): dropped a `module.X` short-circuit that returned the whole `outer` snapshot as the result of `module.X` when X wasn't in cache but lived in the bindings list. Inside a nested object-literal body (`new R { workflowTests = new Listing { for (wt in module.workflowTests) { ... } } }`), this returned R's in-flight body as `module.workflowTests`, which then iterated as four pseudo-members and produced "Cannot find property `name` in object of type `Listing`" on the inner field access.
- Combined effect: pkfire's `examples/basic/Taskfile.pkl` (`amends "package://pkg.pkl-lang.org/github.com/mizchi/pkfire/pkfire@0.10.0#/Taskfile.pkl"`) now evaluates byte-identically to Apple Pkl 0.31.1. The pkspec / pkfire wire-format consumer no longer needs the JVM `pkl` CLI for this schema.

Known follow-up (not blocking the release gate):

- `length on Int` in `QuickCheck.test.pkl`'s `checkAllInt` fact — Apple Pkl works because of lazy property evaluation (the failing slot `cases = cases.length` inside a `new Result { ... }` body is never demanded by the caller's `r.passed && r.failure == null` reads). mpkl evaluates eagerly and trips on the in-progress self-reference. A real fix needs lazy property evaluation across `new T { ... }` bodies — a major architectural change, deferred.

Release focus:

- `basic`: 86 PASS / 0 DIFF
- `generators`: 21 PASS / 0 DIFF
- `projects`: 19 PASS / 0 DIFF
- `packages`: 3 PASS / 0 DIFF

Planned order:

1. Done: Priority 4: Spread And Predicate Member Semantics
2. Done: Priority 3: `for` / Shape-Aware Object Body Evaluation
3. Done: Priority 2: Resource And Glob Host Surface for with-gold `basic/read`, `basic/readGlob`, and `basic/importGlob`
4. Done: Priority 1: Numeric And Bytes Parity
5. Done: Renderer API surface: keep the advertised output formats honest
6. Done: Priority 5: remaining Generic `as` / `is` / Typed Collection Retention
7. Done: Priority 6: `outer` And Const Provenance

Priority 6 now covers the with-gold `basic` fixture surface. Keep the remaining const-error-only fixtures out of the release gate unless they become user-facing regressions.

## Release Blocker Triage

End-user blocker priority is based on "will a normal Pkl config author hit this?", not raw gold-match count.

1. Resource / read / glob: file/resource access, `read*()`, and `import*` glob behavior are release blockers for multi-file configs and CLI usage.
2. `for` / generators: completed for with-gold upstream fixtures. Keep this as a regression-sensitive area because real configs use list/map comprehensions and generated object bodies heavily.
3. Renderer API surface: `api` has many DIFFs, but not all are equal. Treat public output formats as blockers only if we advertise them for this release. Keep `pcf` / `json` / `yaml` stable; renderer converter coverage now includes direct `renderDocument` / `renderValue` calls across PCF / JSON / YAML / plist / XML, PCF/JSON indent options, YAML stream mode, YAML `indentWidth`, YAML `Bytes`/mapping-key output, YAML key quoting / explicit-key / string-escape parity, custom string delimiter options, validation diagnostics for non-renderable values, XML class-keyed converters, path-keyed wildcard converters, direct CDATA/comment helpers, and `xml.Element` rename fixtures. JSON parser converters and YAML `parseAll` / class-converter parsing now gold-match their targeted fixtures. Protobuf text now covers every upstream Protobuf fixture (`api/protobuf`, `api/protobuf2`, and `api/protobuf3.txtpb`).
4. Basic scalar / collection parity: `Bytes`, `DataSize`, `Duration`, `Int`, `Float`, `Map`, nullable, `new`, `as`, `outer`, and const provenance are gold-matching for all with-gold `basic` fixtures.
5. Deep stdlib / reflect parity: important for long-term compatibility, but not a first release blocker unless a public API or real package depends on it.

Latest API-surface pass: `api/any`, `api/annotationConverters`, `api/benchmarkModule`, `api/bytes`, `api/dynamic`, `api/list`, `api/listing`, `api/mapping`, `api/map`, `api/regex`, `api/releaseModule`, `api/set`, `api/setNullable`, `api/string`, `api/stringUnicode`, `api/typeAliases`, `api/typed`, `api/Resource`, `api/dir1/dir2/relativePathTo`, `api/module`, `api/semverModule`, and `api/reflect1` / `api/reflect2` / `api/reflect3` / `api/reflect4` / `api/reflect5` now gold-match. `reflect.Module(...).imports` keeps existing `reflect5` parity and no longer fails on modules without an import map. Remaining reflect DIFF is the full recursive stdlib declaration shape in `api/reflectedDeclaration`, not basic Module/Class/Property construction. `api/mathModule` remains DIFF only on last-bit host floating-point output for `log2` / trig functions.

For this release pass, Resource / Glob, Numeric / Bytes, nullable basics, and the advertised renderer validation surface are gold-matching for their targeted fixtures.

## Current DIFF Snapshot

Measured from the release binary against Apple Pkl LanguageSnippetTests gold files.

`basic` remaining DIFFs: none.

`generators` remaining DIFFs: none.

`api` remaining DIFFs:

- Core collection / scalar API: none.
- Resource / path API: none.
- Renderer / parser API: `api/jsonnetRenderer7` (Mixin / Function1 rendering diagnostic), `api/jsonnetRenderer8` (`convertPropertyTransformers` + `LineComment` annotation surface), `api/renderDirective`, `api/renderDirective2`, `api/yamlParser1Compat`, `api/yamlParser1Yaml11`, `api/yamlParser1Yaml12`, `api/yamlParser6`, `api/yamlRendererStringsCompat`, `api/yamlRendererStringsYaml11`, `api/yamlRendererStringsYaml12`. `jsonnetRenderer1/2/3/4/5/6` now gold-match through the in-tree Jsonnet renderer.

## RenderDirective parity (deferred)

`api/renderDirective` and `api/renderDirective2` cover every advertised renderer (pcf, json, jsonnet, plist, properties, textproto, xml, yaml) in one go: each fixture invokes `renderValue` / `renderDocument` on `new RenderDirective { text = ... }` against all eight renderers, including RenderDirective values inside Mapping keys, Listing elements, Dynamic objects, and the leaf positions of nested NestedDirectives. PCF / JSON / textproto already pass through `render_directive_text`; properties / plist / yaml / xml / jsonnet reject RenderDirective at the renderer error gate.

A real fix needs to (a) bypass `*_renderer_value_error` / `*_renderer_document_error` when `render_directive_text(value) is Some(_)`, (b) emit `directive.text` verbatim from each renderer's main dispatch (including the mapping-key path, the listing-element path, and the dynamic-foo path), and (c) accept RenderDirective as a Mapping key without coercing to a scalar. The change is structurally similar across the five renderers but each one writes its own `write_leaf` / `write_entry` / `write_array` helpers, so the patch is ~5 × ~30 lines. Not blocking the current release gate — these two fixtures are the only places RenderDirective parity is asserted.
- Stdlib module / metadata API: `api/analyze1`, `api/mathModule`, `api/reflectedDeclaration`.

`internal` remaining DIFFs: `internal/polymorphicCallSite`.

Adjacent typed-collection / grammar DIFFs: `basic/new`, `basic/newType`, `listings/typeCheck`, `mappings/typeCheck`, `listings/listing5`, `parser/lineCommentBetween`, `classes/constraints7`, and `classes/constraints13` now gold-match.

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

Status: completed for all with-gold `generators` fixtures and the targeted `basic/underscore` / `basic/amendsChains` grammar-amend gaps. Keep the focused tests and smoke entries as regression coverage because this slice changed object-body member-kind, predicate-member, and lexical-scope evaluation.

Target fixtures:

- `generators/forGeneratorInFunctionBody`
- `generators/forGeneratorInMixins`
- `generators/forGeneratorLexicalScope`
- `basic/underscore`
- `basic/amendsChains`

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
- Parse constructor-function amend signatures inside inferred `new` bodies so underscore placeholders do not collapse positional defaults.
- Apply predicate body amend chains to selected Listing / Mapping / Dynamic entries, including collection implicit receiver calls such as `length` and `toList()`.

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
- `basic/as`
- `basic/as2`
- `basic/as3`
- `basic/new`
- `basic/newType`

Implemented work:

- Added a deep runtime matcher for `is` that checks strict collection classes, generic collection elements, string-literal branches, nullable / union branches, function arity, Class mirrors, and user-class tags / inherited class tags.
- Fixed parenthesized `is Map<K, V>` parsing so commas inside generic angle brackets do not turn `!(...)` into `UnsupportedExpr`.
- Added generic `as` cast overlays for `List`, `Set`, `Map`, `Listing`, and `Mapping`; immutable collections validate eagerly while `Listing` / `Mapping` preserve deferred element / value errors until access.
- Preserved lazy collection-local bindings in Listing / Mapping bodies so earlier dynamic elements are not invalidated by later unused locals, and collection-local `local x` shadows module cache during eval and type resolution.
- Kept renderer-class casts compatible with `ValueRenderer` so `api/pcfRenderer9` remains gold-match.
- Fixed lazy typed generated Listing / Mapping values for `listings2/typeCheck` and `mappings2/typeCheck`.
- Fixed union-aware typed collection retention for `listings/typeCheck` and `mappings/typeCheck`, including lazy single-collection union branches, eager Set hash validation, `Pair<T, U>` nested collection annotations, and `new Mapping<K, V>` type-argument retention.
- Finished `Mixin` / `Mixin<T>` pipe and `.apply()` dispatch, Mixin property override merge semantics, typealias `Mapping<K, V>` constructors, and `new` rejection diagnostics for external / unstarred union / string-literal types.
- Aligned `basic/as` runtime cast diagnostics and module self-reference from in-progress Mapping bodies, including `(module as Module).examples["String"][0]`.

Remaining follow-ups:

- Improve `is` for generic collection types and constrained types.
- Stabilize object class identity for user classes, reflect `Class`, and diagnostics.
- Represent function type arity in diagnostics (`Function1`, `Function2`) where Apple Pkl expects it.

Main dependencies:

- Collection type-overlay design.
- Class tag / reflect class consistency.
- Callable type metadata.
- Some Priority 3 work for typed generated bodies.

## Priority 6: `outer` And Const Provenance

Status: completed for the with-gold `basic` surface. `basic/constModifier`, `basic/localMethodInAmendingModule`, and the previous `outer` regressions now gold-match.

Target fixtures:

- `basic/constModifier`
- Generator lexical-scope edge cases

Required work:

- [x] Add lexical parent receiver stack for `outer`.
- [x] Ensure nested object literal evaluation can resolve `outer.<name>` independently of `this`.
- [x] Track const provenance for properties, local consts, and functions.
- [x] Reject non-const references in const contexts with Apple-compatible diagnostics.
- [x] Preserve function-parameter shadowing over module locals inside class-default call scopes.

Main dependencies:

- Object evaluation environment stack.
- Binding/function metadata carrying `const`.
- Import/module snapshot support for const access across modules.

## Issue Sync

- #4 Lazy local evaluation: implemented through the local-scope fixture slice and closed as completed.
- #6 XML / Protobuf renderer bodies: all upstream XML `.xml` renderer fixtures now promote (`xmlRenderer1`, `xmlRenderer2`, `xmlRenderer3`, `xmlRenderer6`, `xmlRenderer9`, `xmlRendererCData`, `xmlRendererElement`, `xmlRendererInline`, `xmlRendererInline2`, `xmlRendererInline3`, `xmlRendererHtml`); JSON output now promotes `jsonRenderer1`, `jsonRenderer2`, `jsonRenderer3`, `jsonRenderer6`, and `jsonRenderer9`; YAML output now promotes `yamlRenderer1`, `yamlRenderer2`, `yamlRenderer3`, `yamlRenderer6`, `yamlRenderer8`, `yamlRenderer9`, `yamlRenderer10`, `yamlRendererBug66849708`, `yamlRendererEmpty`, `yamlRendererIndentationWidth2/4/5`, `yamlRendererKeys`, and `yamlRendererStrings`; direct renderer-method / validation PCF fixtures now cover `pcfRenderer2`, `pcfRenderer2b`, `pcfRenderer4`, `pcfRenderer5`, `jsonRenderer2b`, `jsonRenderer4`, `jsonRenderer5`, `yamlRenderer2b`, `yamlRenderer4`, `yamlRenderer5`, `yamlRendererStream1`, `yamlRendererStream2`, `plistRenderer2b`, `pListRenderer4`, `pListRenderer5`, `propertiesRenderer2b`, `propertiesRenderer4`, `propertiesRenderer5`, `xmlRenderer2b`, `xmlRenderer4`, `xmlRenderer5`, `xmlRendererValidation10`, `xmlRendererValidation11`, `protobuf`, and `protobuf2`; Protobuf text also promotes `protobuf3.txtpb`. Remaining Protobuf work is outside the current upstream LanguageSnippetTests surface, so #6 should be closed or rescoped before release.
- #8 Umbrella practical blockers: coverage and active focus were updated after the 367 / 391 slice. The open release path is now API surface parity first; Resource / Path API is gold-matching for the upstream with-gold fixtures.
- #17 YAML Parser complex mapping keys: still open for `api/yamlParser6`; this is not a release blocker unless full YAML complex-key parity is advertised.
- #1 Stdlib module evaluation gaps: relevant for long-term stdlib parity, especially external declarations, variance, and `pkl:` module loading.

## Suggested Release Path

1. Keep GitHub issues and release docs aligned with the current `367 / 391` baseline; stale issue bodies should not be used as the source of truth over this file.
2. Work down the remaining `api` fixtures, prioritizing broad user-facing stdlib API surface before deep reflect parity.
3. Done: treat `api/list` / `api/listing` / `api/mapping` / `api/set` / `api/string` as the next low-risk user-facing API cluster.
4. Leave `api/reflectedDeclaration`, `api/mathModule`, and `internal/polymorphicCallSite` out of the immediate release gate unless a real package depends on them.
