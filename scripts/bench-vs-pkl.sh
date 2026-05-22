#!/usr/bin/env bash
# Compare `mpkl eval` against Apple Pkl's `pkl eval` on a fixed set of
# representative fixtures using `hyperfine`. Both binaries are native
# AOT so the comparison is fair (no JVM cold-start handicap).
#
# Outputs:
#   benchmarks/vs-pkl-<tag>.md   — human-readable summary
#   benchmarks/vs-pkl-<tag>.json — raw hyperfine results
#
# Usage:
#   scripts/bench-vs-pkl.sh                 # default tag = git short SHA + dirty?
#   scripts/bench-vs-pkl.sh <tag>           # explicit tag, e.g. "baseline" / "post-refactor"
#   WARMUP=5 RUNS=20 scripts/bench-vs-pkl.sh post-refactor

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v hyperfine >/dev/null || { echo "hyperfine not in PATH" >&2; exit 1; }
command -v pkl >/dev/null       || { echo "Apple pkl not in PATH" >&2; exit 1; }

MPKL="$ROOT/_build/native/release/build/cmd/mpkl/mpkl.exe"
if [ ! -x "$MPKL" ]; then
  echo "Building mpkl native release..." >&2
  moon build --release --target native >&2
fi

PKL_VERSION="$(pkl --version | head -1)"
MPKL_BUILD_INFO="$(stat -f '%Sm' "$MPKL" 2>/dev/null || stat -c '%y' "$MPKL")"
GIT_REV="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  GIT_DIRTY="-dirty"
fi

TAG="${1:-${GIT_REV}${GIT_DIRTY}}"
WARMUP="${WARMUP:-5}"
RUNS="${RUNS:-25}"

OUT_DIR="$ROOT/benchmarks"
mkdir -p "$OUT_DIR"
MD="$OUT_DIR/vs-pkl-${TAG}.md"
JSON="$OUT_DIR/vs-pkl-${TAG}.json"

# Fixture set: (label, path-relative-to-ROOT). Both binaries must
# already eval identically — verified via `diff` in CI gates.
FIXTURES=(
  "micro:fixtures/cli.pkl"
  "amend-base:fixtures/cli_amends_base_merge.pkl"
  "map-value:fixtures/cli_map_value.pkl"
  "set-value:fixtures/cli_set_value.pkl"
  "int-seq:fixtures/cli_int_seq_value.pkl"
  "basic-int:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/int.pkl"
  "basic-float:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/float.pkl"
  "basic-string:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/string.pkl"
  "basic-as:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/as.pkl"
  "basic-is:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/is.pkl"
  "basic-new:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/new.pkl"
  "basic-rawstring:third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/rawString.pkl"
  "pkspec-test-schema:../pkspec/pkl/Test.pkl"
)

ALL_HF_ARGS=()
declare -a NAMES
for spec in "${FIXTURES[@]}"; do
  label="${spec%%:*}"
  path="${spec#*:}"
  if [ ! -f "$path" ]; then
    echo "missing fixture: $path" >&2
    exit 1
  fi
  # Sanity-check parity before timing — refuse to publish numbers for
  # fixtures the two binaries don't agree on, because runtime varies
  # wildly between "real eval" and "early error path".
  if ! diff <("$MPKL" eval "$path" 2>/dev/null) <(pkl eval "$path" 2>/dev/null) >/dev/null; then
    echo "OUTPUT DIVERGES for $label ($path) — fix or drop from bench" >&2
    exit 1
  fi
  NAMES+=("$label")
  ALL_HF_ARGS+=(
    -n "mpkl:$label" "$MPKL eval $path"
    -n "pkl:$label"  "pkl eval $path"
  )
done

echo "Running hyperfine on ${#FIXTURES[@]} fixtures (warmup=$WARMUP runs=$RUNS)..." >&2
hyperfine \
  --shell=none \
  --warmup "$WARMUP" \
  --runs "$RUNS" \
  --export-json "$JSON" \
  --export-markdown "$MD.tmp" \
  --style basic \
  "${ALL_HF_ARGS[@]}"

{
  echo "# Apple Pkl vs mpkl benchmark"
  echo
  echo "- tag: \`$TAG\`"
  echo "- date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- host: \`$(uname -srm)\`"
  echo "- pkl: \`$PKL_VERSION\`"
  echo "- mpkl: \`$(basename "$MPKL")\` (built $MPKL_BUILD_INFO) at \`$GIT_REV$GIT_DIRTY\`"
  echo "- hyperfine: \`$(hyperfine --version)\` (warmup=$WARMUP, runs=$RUNS)"
  echo
  echo "## Pairwise results"
  echo
  cat "$MD.tmp"
  echo
  echo "## Ratio (mpkl / pkl) — lower is better for mpkl"
  echo
  echo "| fixture | mpkl mean | pkl mean | mpkl/pkl |"
  echo "| --- | ---: | ---: | ---: |"
  python3 - "$JSON" "${NAMES[@]}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
names = sys.argv[2:]
results = {r["command"]: r for r in data["results"]}
def fmt(t):
    if t < 1e-3: return f"{t*1e6:.1f} us"
    if t < 1:    return f"{t*1e3:.2f} ms"
    return f"{t:.3f} s"
for name in names:
    mp = results.get(f"mpkl:{name}")
    pk = results.get(f"pkl:{name}")
    if not mp or not pk: continue
    ratio = mp["mean"] / pk["mean"]
    print(f"| {name} | {fmt(mp['mean'])} | {fmt(pk['mean'])} | {ratio:.2f}x |")
PY
} > "$MD"

rm -f "$MD.tmp"
echo "wrote $MD and $JSON" >&2
