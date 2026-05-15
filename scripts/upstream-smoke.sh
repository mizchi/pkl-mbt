#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"

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

eval_contains \
  "basic/parens.pkl" \
  "$UPSTREAM/basic/parens.pkl" \
  "res2 = 20"
eval_contains \
  "basic/import1.pkl res1" \
  "$UPSTREAM/basic/import1.pkl" \
  "res1 = 6"
eval_contains \
  "basic/import1.pkl res4" \
  "$UPSTREAM/basic/import1.pkl" \
  "res4 = 3"
eval_contains \
  "basic/import2.pkl libFoo" \
  "$UPSTREAM/basic/import2.pkl" \
  "libFoo = 6"
eval_contains \
  "basic/import2.pkl libBar" \
  "$UPSTREAM/basic/import2.pkl" \
  "libBar = 3"
eval_contains \
  "basic/import3.pkl" \
  "$UPSTREAM/basic/import3.pkl" \
  "bak = 6"
eval_contains \
  "modules/filename with spaces.pkl" \
  "$UPSTREAM/modules/filename with spaces.pkl" \
  "foo = \"bar\""
eval_contains \
  "modules/filename with spaces 2.pkl" \
  "$UPSTREAM/modules/filename with spaces 2.pkl" \
  "otherFile = foo = \"bar\""
eval_contains \
  "modules/objects.pkl" \
  "$UPSTREAM/modules/objects.pkl" \
  "x = y = z = 1"
eval_contains \
  "classes/constraints8.pkl" \
  "$UPSTREAM/classes/constraints8.pkl" \
  "res2 = \"type annotation X member a constraint isGreaterThan rejects 5\""
