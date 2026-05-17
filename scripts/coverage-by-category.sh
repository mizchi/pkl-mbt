#!/usr/bin/env bash
# Per-category gold-match coverage of upstream Apple Pkl LanguageSnippetTests.
#
# Each fixture under the upstream `input/` tree is evaluated with the
# native CLI; the produced PCF is byte-compared against the gold under
# `output/`. The script groups results by top-level directory (the
# fixture category), then prints PASS / DIFF / NOGOLD counts plus the
# gold-match percentage of fixtures that actually have a gold file.
#
# NOGOLD fixtures are skipped from the percentage: most are
# `errors/*` and a few `packages/*` / `pklbinary/*` cases that don't
# emit a PCF gold (Apple Pkl tests them through a different
# diagnostic-comparison path).
#
# Uses the release `mpkl` binary directly (parallel xargs) rather than
# `moon run`, since 896+ fixtures × `moon run` startup cost is several
# minutes; the binary path keeps a full sweep around ~12s wall.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"
GOLD="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/output"
MPKL="_build/native/release/build/cmd/mpkl/mpkl.exe"

if [ ! -x "$MPKL" ]; then
  echo "building $MPKL ..." >&2
  moon build --target native --release >/dev/null 2>&1
fi

PROBE="$(mktemp)"
STATUS="$(mktemp)"
trap 'rm -f "$PROBE" "$STATUS"' EXIT

cat > "$PROBE" <<EOF
#!/usr/bin/env bash
MPKL="$ROOT/$MPKL"
UPSTREAM="$ROOT/$UPSTREAM"
GOLD="$ROOT/$GOLD"
EOF
cat >> "$PROBE" <<'EOF'
f="$1"
goldpcf="$GOLD/$f.pcf"
if [ ! -f "$goldpcf" ]; then
  printf '%s|NOGOLD\n' "$f"
  exit 0
fi
# PKL-148q: bytewise diff via temp file so fixtures whose gold ends
# without a trailing newline (e.g. `api/moduleOutput`) align with the
# upstream-smoke gate. The previous `$(...)` capture + `printf '%s\n'`
# wrapping always normalised the final byte and undercounted PASS.
tmp="$(mktemp)"
"$MPKL" eval "$UPSTREAM/$f.pkl" > "$tmp" 2>/dev/null || true
if diff -q "$goldpcf" "$tmp" >/dev/null 2>&1; then
  printf '%s|PASS\n' "$f"
else
  printf '%s|DIFF\n' "$f"
fi
rm -f "$tmp"
EOF
chmod +x "$PROBE"

cd "$UPSTREAM"
find . -name "*.pkl" -type f | sed 's|^\./||; s|\.pkl$||' > "$STATUS.fixtures"
cd "$ROOT"

xargs -I {} -P 8 "$PROBE" {} < "$STATUS.fixtures" > "$STATUS"
rm -f "$STATUS.fixtures"

awk -F'|' '
{
  cat = $1
  sub("/.*", "", cat)
  status = $2
  total[cat]++
  count[cat","status]++
  total_all++
  count_all[status]++
  if (!seen[cat]) { seen[cat] = 1; cats[++ncats] = cat }
}
END {
  for (i = 1; i <= ncats; i++) {
    for (j = i + 1; j <= ncats; j++) {
      p_i = count[cats[i] ",PASS"] + 0
      d_i = count[cats[i] ",DIFF"] + 0
      wg_i = p_i + d_i
      pct_i = wg_i > 0 ? (p_i / wg_i) : -1
      p_j = count[cats[j] ",PASS"] + 0
      d_j = count[cats[j] ",DIFF"] + 0
      wg_j = p_j + d_j
      pct_j = wg_j > 0 ? (p_j / wg_j) : -1
      if (pct_j > pct_i) {
        t = cats[i]; cats[i] = cats[j]; cats[j] = t
      }
    }
  }
  printf "%-20s %5s %5s %5s %5s   %s\n", "category", "PASS", "DIFF", "NOGD", "TOT", "%PASS (of with-gold)"
  printf "%-20s %5s %5s %5s %5s   %s\n", "--------------------", "----", "----", "----", "----", "--------------------"
  for (i = 1; i <= ncats; i++) {
    cat = cats[i]
    p = count[cat ",PASS"] + 0
    d = count[cat ",DIFF"] + 0
    ng = count[cat ",NOGOLD"] + 0
    wg = p + d
    if (wg > 0) {
      printf "%-20s %5d %5d %5d %5d   %5.1f%% (of %d)\n", cat, p, d, ng, total[cat], 100.0 * p / wg, wg
    } else {
      printf "%-20s %5d %5d %5d %5d     n/a (no gold)\n", cat, p, d, ng, total[cat]
    }
  }
  printf "%-20s %5s %5s %5s %5s   %s\n", "--------------------", "----", "----", "----", "----", "--------------------"
  P = count_all["PASS"] + 0
  D = count_all["DIFF"] + 0
  N = count_all["NOGOLD"] + 0
  WG = P + D
  if (WG > 0) {
    printf "%-20s %5d %5d %5d %5d   %5.1f%% (of %d)\n", "TOTAL", P, D, N, total_all, 100.0 * P / WG, WG
  } else {
    printf "%-20s %5d %5d %5d %5d     n/a\n", "TOTAL", P, D, N, total_all
  }
}
' "$STATUS"
