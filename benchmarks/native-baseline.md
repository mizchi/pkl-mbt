# Moon Bench Native Baseline

- date: 2026-05-14
- command: `pkf run bench` (`moon bench --target native --deny-warn`)
- moon: `moon 0.1.20260512 (81d40e3 2026-05-12)`
- source: worktree based on `9b40475` with lexer/parser hot-path optimizations
- platform: `Darwin KotaronoMacBook-Pro.local 25.4.0 Darwin Kernel Version 25.4.0: Thu Mar 19 19:33:43 PDT 2026; root:xnu-12377.101.15~1/RELEASE_ARM64_T8142 arm64`

No MoonBit compiler diagnostics were emitted.

| Benchmark | Mean | Stddev | Min | Max | Samples |
| --- | ---: | ---: | ---: | ---: | ---: |
| parse/small-module | 5.89 us | 149.21 ns | 5.73 us | 6.24 us | 10 x 16703 |
| parse/object-body | 15.68 us | 198.02 ns | 15.47 us | 16.05 us | 10 x 6441 |
| parse/imports | 9.46 us | 49.61 ns | 9.40 us | 9.55 us | 10 x 10589 |
| eval/object-body | 15.92 us | 202.41 ns | 15.70 us | 16.30 us | 10 x 6311 |
| typecheck/object-body | 15.79 us | 150.93 ns | 15.62 us | 16.05 us | 10 x 6296 |
| analysis/import-eval-cache-hit | 26.63 ns | 0.69 ns | 25.61 ns | 27.49 ns | 10 x 100000 |
