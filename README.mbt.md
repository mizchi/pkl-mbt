# mizchi/pickle

Pure MoonBit core for Apple's Pkl language.

The package currently exposes:

- `parse_source` for CST-backed parsing
- `eval_source` for the first interpreter slice
- `typecheck_source` for primitive typechecking
- `AnalysisSession` for ripple-backed source analysis

The supported language subset is integer arithmetic, booleans, strings, `null`, identifiers, parentheses, and top-level `let` bindings.
It also supports initial Pkl-style `module` declarations, top-level properties, `new { ... }` object literals, and object member lookup.
`AnalysisSession` resolves import clauses from its source graph for typechecking and evaluation.
Module-level `local` bindings and `import("...")` expressions resolve through the same source graph.
Object body property shorthand such as `x { y { z = 1 } }` is supported.
Explicit `new Listing { ... }` and `new Mapping { [key] = value }` collection values support subscript access.
Selected `pkl:` standard library modules are available through the same resolver; currently this includes `pkl:math.maxInt32`.
Primitive type annotations such as `name: String = "hawk"` are checked by the typechecker.
The native CLI supports `parse`, `check`, and `eval` subcommands for files.
Common string escapes are decoded and rendered for `\n`, `\t`, `\r`, `\"`, and `\\`.
The repository also tracks `apple/pkl` as a git submodule and runs selected upstream fixtures through `./scripts/upstream-smoke.sh`.
For parser coverage, `./scripts/upstream-parse-suite.sh` parses the upstream `LanguageSnippetTests` corpus selected by apple/pkl's `ParserComparisonTest`.
