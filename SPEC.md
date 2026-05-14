# Test SPEC

36 tests across 2 module(s) — 32 pending, 4 active

## `specs/`

### `Spec.pkl`

- [ ] **evaluate arithmetic and let bindings** (critical) — verifies: PKL-002
  > The interpreter evaluates integer arithmetic with precedence and resolves top-level let bindings.
  - contributes to: GOAL-PKL-PURE
  - body: _not yet implemented_

- [ ] **inventory unsupported syntax in tolerant parser output** — verifies: PKL-016 — tags: parser
  > ParseResult exposes an unsupported_syntax coverage report with source ranges, text, and syntax kind for accepted code that still lowers to UnsupportedExpr.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-015
  - decisions: 2 entry(ies)
  - body: _not yet implemented_

- [ ] **model Pkl class function and typealias declarations** — verifies: PKL-019 — tags: parser, typechecker
  > Program retains class, function, and typealias declarations, and the typechecker resolves declared class and typealias names in property annotations.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-016, PKL-008
  - decisions: 2 entry(ies)
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

- [ ] **parse Pkl call lambda and operator expressions** — verifies: PKL-018 — tags: parser
  > The parser lowers calls, lambdas, unary operators, comparisons, boolean operators, null-coalescing, and conditional expressions into explicit AST nodes with precedence matching Pkl.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-016
  - decisions: 2 entry(ies)
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

- [ ] **provide a usable CLI** — verifies: PKL-009
  > The native command-line entrypoint can parse, typecheck, and evaluate Pkl source files.
  - contributes to: GOAL-PKL-PURE
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **reject invalid integer operations** (critical) — verifies: PKL-003
  > The typechecker rejects binary arithmetic when either operand is not an Int.
  - contributes to: GOAL-PKL-PURE
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

- [ ] **typecheck Pkl nullable postfix operators** [draft] — verifies: PKL-032 — tags: parser, typechecker, next
  > The parser and typechecker support nullable postfix operators such as non-null assertion `!!` and safe member access `?.`, producing inner or nullable member types with diagnostics for invalid targets.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-024, PKL-031
  - decisions: 1 entry(ies)
  - body: _not yet implemented_

- [ ] **typecheck Pkl union type annotations** — verifies: PKL-027 — tags: parser, typechecker
  > The parser preserves union annotation text such as `String | Int`, and the typechecker accepts values that match any union branch, including nested collection and callable annotations.
  - contributes to: GOAL-PKL-PURE
  - depends on: PKL-023, PKL-025, PKL-026
  - decisions: 1 entry(ies)
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

- [x] **moon unit tests** — verifies: PKL-001, PKL-002, PKL-003, PKL-004, PKL-005, PKL-006, PKL-007, PKL-008, PKL-009, PKL-010, PKL-012, PKL-013, PKL-014, PKL-016, PKL-017, PKL-018, PKL-019, PKL-020, PKL-021, PKL-022, PKL-023, PKL-024, PKL-025, PKL-026, PKL-027, PKL-028, PKL-029, PKL-030, PKL-031 — tags: moonbit, unit, contract
  > MoonBit unit tests verify the initial parser, interpreter, typechecker, and ripple-backed analysis session.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl fixture smoke** — verifies: PKL-011, PKL-012, PKL-013, PKL-014 — tags: moonbit, upstream, compatibility, contract
  > Selected fixtures from the apple/pkl submodule parse and evaluate through the native CLI.
  - body: `cmd` (exit 0 expected)

- [x] **upstream apple pkl parser suite** — verifies: PKL-015 — tags: moonbit, upstream, parser, compatibility, contract
  > All apple/pkl LanguageSnippetTests parser fixtures, excluding the same invalid cases as ParserComparisonTest, parse through the native CLI.
  - body: `cmd` (exit 0 expected)

