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
  "basic/baseModule"
  "basic/comments"
  "basic/constModifier3"
  "basic/fixedProperty1"
  "basic/fixedProperty3"
  "basic/import1"
  "basic/import2"
  "basic/import3"
  "basic/imported"
  "basic/indexExpressions"
  "basic/parens"
  "basic/semicolon"
  "classes/class1"
  "classes/constraintsLambdaThis"
  "classes/functions2"
  "modules/amendModule1"
  "modules/amendModule2"
  "modules/amendModule3"
  "modules/filename with spaces"
  "modules/filename with spaces 2"
  "modules/library"
  "modules/objects"
  "modules/supercalls1"
  "objects/implicitReceiver3"
  "types/nothingWithUnions"
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
  "classes/constraints8.pkl"
)

parse_ok() {
  local label="$1"
  local file="$2"
  local output
  output="$(moon run cmd/main --target native -- parse "$file")"
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
  local actual
  actual="$(moon run cmd/main --target native -- eval "$input")"
  if ! diff -u "$gold" <(printf '%s\n' "$actual") >/tmp/upstream-smoke-diff.$$; then
    printf 'upstream eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-diff.$$ >&2
    rm -f /tmp/upstream-smoke-diff.$$
    exit 1
  fi
  rm -f /tmp/upstream-smoke-diff.$$
  printf 'upstream eval ok: %s (gold match)\n' "$label"
}

eval_contains() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local output
  output="$(moon run cmd/main --target native -- eval "$file")"
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
  actual="$(moon run cmd/main --target native -- eval -f json "$input")"
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

# classes/constraints8 carries our project-specific error diagnostic wording
# rather than Apple Pkl's "Type constraint ... violated. Value: ..." text,
# so we keep the partial substring check until the diagnostic surface is
# aligned with upstream wording.
eval_contains \
  "classes/constraints8.pkl" \
  "$UPSTREAM/classes/constraints8.pkl" \
  "res2 = \"type annotation X member a constraint isGreaterThan rejects 5\""

printf 'upstream-smoke: %d gold-match fixtures passed\n' "$ok_count"
printf 'upstream-smoke: %d json gold-match fixtures passed\n' "$json_ok_count"
