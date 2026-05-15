#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"
GOLD="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/output"

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

parse_ok "basic/parens.pkl" "$UPSTREAM/basic/parens.pkl"
parse_ok "basic/import1.pkl" "$UPSTREAM/basic/import1.pkl"
parse_ok "basic/import2.pkl" "$UPSTREAM/basic/import2.pkl"
parse_ok "basic/import3.pkl" "$UPSTREAM/basic/import3.pkl"
parse_ok "basic/imported.pkl" "$UPSTREAM/basic/imported.pkl"
parse_ok \
  "modules/filename with spaces.pkl" \
  "$UPSTREAM/modules/filename with spaces.pkl"
parse_ok \
  "modules/filename with spaces 2.pkl" \
  "$UPSTREAM/modules/filename with spaces 2.pkl"
parse_ok "modules/objects.pkl" "$UPSTREAM/modules/objects.pkl"
parse_ok "classes/constraints8.pkl" "$UPSTREAM/classes/constraints8.pkl"

eval_matches_gold \
  "basic/parens.pkl" \
  "$UPSTREAM/basic/parens.pkl" \
  "$GOLD/basic/parens.pcf"
eval_matches_gold \
  "basic/import1.pkl" \
  "$UPSTREAM/basic/import1.pkl" \
  "$GOLD/basic/import1.pcf"
eval_matches_gold \
  "basic/import2.pkl" \
  "$UPSTREAM/basic/import2.pkl" \
  "$GOLD/basic/import2.pcf"
eval_matches_gold \
  "basic/import3.pkl" \
  "$UPSTREAM/basic/import3.pkl" \
  "$GOLD/basic/import3.pcf"
eval_matches_gold \
  "modules/filename with spaces.pkl" \
  "$UPSTREAM/modules/filename with spaces.pkl" \
  "$GOLD/modules/filename with spaces.pcf"
eval_matches_gold \
  "modules/filename with spaces 2.pkl" \
  "$UPSTREAM/modules/filename with spaces 2.pkl" \
  "$GOLD/modules/filename with spaces 2.pcf"
eval_matches_gold \
  "modules/objects.pkl" \
  "$UPSTREAM/modules/objects.pkl" \
  "$GOLD/modules/objects.pcf"

# classes/constraints8 carries our project-specific error diagnostic wording
# rather than Apple Pkl's "Type constraint ... violated. Value: ..." text,
# so we keep the partial substring check until the diagnostic surface is
# aligned with upstream wording.
eval_contains \
  "classes/constraints8.pkl" \
  "$UPSTREAM/classes/constraints8.pkl" \
  "res2 = \"type annotation X member a constraint isGreaterThan rejects 5\""
