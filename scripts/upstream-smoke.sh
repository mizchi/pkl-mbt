#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"
GOLD="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/output"

# PKL-096: list of upstream fixtures whose `pkl eval` output already
# matches the gold `.pcf` byte-for-byte. Promote here only after a
# manual diff run; new failures must be either fixed or explicitly
# tracked outside this list (the script gates regressions).
GOLD_FIXTURES=(
  "annotation/annotation1"
  "api/jsonParser4"
  "api/jsonRendererEmptyComposites"
  "api/jsonRenderer7"
  "api/moduleOutput2"
  "api/pair"
  "api/pcfRenderer6"
  "basic/baseModule"
  "basic/comments"
  "basic/constModifier3"
  "basic/fixedProperty1"
  "basic/fixedProperty2"
  "basic/fixedProperty3"
  "basic/identifier"
  "basic/localMethodTyped3"
  "basic/localModuleMemberOverride1"
  "basic/import1"
  "basic/import2"
  "basic/if"
  "basic/import3"
  "basic/imported"
  "basic/indexExpressions"
  "basic/intseq"
  "basic/list"
  "basic/localProperty1"
  "basic/localProperty2"
  "basic/localPropertyOverride1"
  "basic/localPropertyOverride2"
  "basic/localPropertyOverride3"
  "basic/propertyDefaults"
  "basic/minPklVersion"
  "basic/moduleRefLibrary"
  "basic/nonNull"
  "basic/objectMember"
  "basic/parens"
  "basic/semicolon"
  "basic/set"
  "basic/typeResolution1"
  "basic/typeResolution2"
  "basic/typeResolution3"
  "basic/typeResolution4"
  "classes/class1"
  "classes/class4"
  "classes/constraints1"
  "classes/constraints2"
  "classes/constraints3"
  "classes/constraints4"
  "classes/constraints6"
  "classes/constraints8"
  "classes/constraintsLambdaThis"
  "classes/equality"
  "classes/wrongType5"
  "errors/baseModule"
  "classes/functions1"
  "classes/functions2"
  "classes/functions3"
  "classes/functions4"
  "classes/inheritance1"
  "classes/inheritance2"
  "generators/propertyGenerators"
  "lambdas/equality"
  "lambdas/inequality"
  "lambdas/lambda1"
  "lambdas/lambda2"
  "lambdas/lambda5"
  "listings/cacheStealing"
  "listings/cacheStealingTypeCheck"
  "listings/listing1"
  "listings2/listing1"
  "mappings/duplicateComputedKey"
  "mappings/mapping1"
  "mappings2/duplicateComputedKey"
  "mappings2/mapping1"
  "methods/methodParameterTypes1"
  "methods/methodParameterTypes2"
  "modules/amendModule1"
  "modules/amendModule2"
  "modules/amendModule3"
  "modules/amendModule5"
  "modules/filename with spaces"
  "modules/filename with spaces 2"
  "modules/library"
  "modules/lists"
  "modules/objects"
  "modules/supercalls1"
  "modules/typedModuleProperties1"
  "objects/closure"
  "objects/configureObjectAssign"
  "objects/implicitReceiver1"
  "objects/implicitReceiver2"
  "objects/implicitReceiver3"
  "objects/super1"
  "objects/super5"
  "objects/this1"
  "parser/constraintsTrailingComma"
  "parser/trailingCommas"
  "projects/badLocalProject/dog"
  "projects/notAProject/@child/theChild"
  "projects/notAProject/goodImport"
  "projects/packageWithSpaces/module with spaces"
  "projects/project6/children/a"
  "projects/project6/children/b"
  "projects/project6/children/c"
  "types/ThisInTypeConstraint"
  "types/helpers/someModule"
  "types/nothingWithUnions"
  "types/typeAliasConstraint1"
  "implementation/equality"
  "implementation/inequality"
  "syntax/shebang"
  "api/moduleOutput"
  "classes/constraints14"
  "errors/const/constLocalAmendModule"
  "modules/amendModule6"
  "generators/spreadSyntaxNullable"
  "methods/methodParameterConstraints1"
  "types/typeAlias1"
  "modules/typedModuleMethods1"
  "types/typeAlias2"
  "listings/wrongIndex"
  "generators/spreadSyntaxTyped"
  "generators/forGeneratorNestedReference2"
  "listings2/wrongIndex"
  "classes/supercallsInLet"
  "basic/localMethodOverride1"
  "basic/localMethodOverride2"
  "basic/localMethodTyped4"
  "modules/supercalls2"
  "modules/amendModule4"
  "modules/extendModule1"
  "projects/project7/spacesInImport"
  "methods/methodParameterConstraints2"
)

# PKL-097: list of upstream fixtures whose `eval -f json` output
# matches the upstream `<dir>/<name>.json` gold byte-for-byte after
# `extract_output_value` unwraps the `output { value }` envelope.
# Most upstream JSON-renderer fixtures additionally need converters,
# Float numerics, or stdlib types (List / Set / Map / Pair / IntSeq)
# we have not yet implemented; only fixtures that gold-match through
# the existing JSON renderer go on the list.
JSON_GOLD_FIXTURES=(
  "api/jsonRenderer1.json"
)

# PKL-126a: list of upstream fixtures whose `eval` output (the input
# already routes through `output { renderer = new PListRenderer {} }`,
# so no `-f plist` is needed) matches the upstream `<dir>/<name>.plist`
# gold byte-for-byte. Most other pListRenderer fixtures upstream lean
# on converter machinery (PKL-127) or on Set / Map / Pair / IntSeq
# value variants (PKL-119); they get promoted as those slices land.
PLIST_GOLD_FIXTURES=(
  "api/pListRenderer1.plist"
)

# Files whose `pkl parse` should succeed even when we cannot evaluate
# them (e.g. they exercise stdlib gaps or runtime semantics outside
# the implemented slice). Keeping a parse-only check pins the parser
# surface.
PARSE_ONLY=(
  "basic/parens.pkl"
  "basic/import1.pkl"
  "basic/import2.pkl"
  "basic/import3.pkl"
  "basic/imported.pkl"
  "modules/filename with spaces.pkl"
  "modules/filename with spaces 2.pkl"
  "modules/objects.pkl"
)

parse_ok() {
  local label="$1"
  local file="$2"
  local output
  output="$(moon run cmd/mpkl --target native -- parse "$file")"
  if ! grep -Fxq "ok" <<<"$output"; then
    printf 'upstream parse failed: %s\n%s\n' "$label" "$output" >&2
    exit 1
  fi
  printf 'upstream parse ok: %s\n' "$label"
}

eval_matches_gold() {
  local label="$1"
  local input="$2"
  local gold="$3"
  # PKL-148q: capture mpkl stdout to a temp file and bytewise-diff,
  # instead of the previous `$(...)` capture + `printf '%s\n'` wrapping
  # which always appended a trailing newline. The wrapper masked any
  # disagreement on the final byte: `api/moduleOutput`'s gold ends
  # without `\n` (Apple Pkl writes `output.text` verbatim), so the
  # previous shape forced a 1-byte mismatch even after the CLI bypass
  # emitted the correct payload.
  local tmp
  tmp="$(mktemp)"
  moon run cmd/mpkl --target native -- eval "$input" > "$tmp"
  if ! diff -u "$gold" "$tmp" >/tmp/upstream-smoke-diff.$$; then
    printf 'upstream eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-diff.$$ >&2
    rm -f /tmp/upstream-smoke-diff.$$ "$tmp"
    exit 1
  fi
  rm -f /tmp/upstream-smoke-diff.$$ "$tmp"
  printf 'upstream eval ok: %s (gold match)\n' "$label"
}

eval_contains() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local output
  output="$(moon run cmd/mpkl --target native -- eval "$file")"
  if ! grep -Fq "$expected" <<<"$output"; then
    printf 'upstream eval failed: %s\nexpected: %s\n%s\n' "$label" "$expected" "$output" >&2
    exit 1
  fi
  printf 'upstream eval ok: %s\n' "$label"
}

# PKL-097: byte-diff `eval -f json` output against the upstream JSON
# gold file. Same gating shape as `eval_matches_gold` but runs the
# JSON renderer; the CLI's `extract_output_value` strips the
# `output {}` envelope so `output.value` matches Apple Pkl's
# JsonRenderer-on-output.value behavior.
eval_json_matches_gold() {
  local label="$1"
  local input="$2"
  local gold="$3"
  local actual
  actual="$(moon run cmd/mpkl --target native -- eval -f json "$input")"
  if ! diff -u "$gold" <(printf '%s\n' "$actual") >/tmp/upstream-smoke-json-diff.$$; then
    printf 'upstream json eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-json-diff.$$ >&2
    rm -f /tmp/upstream-smoke-json-diff.$$
    exit 1
  fi
  rm -f /tmp/upstream-smoke-json-diff.$$
  printf 'upstream json eval ok: %s (gold match)\n' "$label"
}

# Parse-only sanity for files that exercise the parser even when
# evaluation depends on unimplemented features.
for entry in "${PARSE_ONLY[@]}"; do
  parse_ok "$entry" "$UPSTREAM/$entry"
done

# Gold-match each fixture in the curated list.
ok_count=0
for label in "${GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label.pcf"
  ok_count=$((ok_count + 1))
done

# JSON gold-match for fixtures that route their output through
# `output.value`. The CLI's `extract_output_value` strips the
# `output { value }` envelope before the JSON renderer sees the
# value, so the diff lines up with Apple Pkl's upstream JSON output.
# Each label already carries its `.json` suffix because upstream
# names the input as `<name>.json.pkl` and the gold as `<name>.json`.
json_ok_count=0
for label in "${JSON_GOLD_FIXTURES[@]}"; do
  eval_json_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  json_ok_count=$((json_ok_count + 1))
done

# PKL-126a: gold-match each fixture whose `output { renderer = new
# PListRenderer {} }` block routes through the plist renderer. The
# rendered envelope is exactly the upstream `.plist` gold file, so
# `eval_matches_gold` (no `-f` override needed because the driver
# path detects the renderer from the AST) lines up byte-for-byte.
plist_ok_count=0
for label in "${PLIST_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  plist_ok_count=$((plist_ok_count + 1))
done

printf 'upstream-smoke: %d gold-match fixtures passed\n' "$ok_count"
printf 'upstream-smoke: %d json gold-match fixtures passed\n' "$json_ok_count"
printf 'upstream-smoke: %d plist gold-match fixtures passed\n' "$plist_ok_count"
