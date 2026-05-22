# Apple Pkl vs mpkl benchmark

- tag: `post-docindex`
- date: 2026-05-22T12:18:18Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 21:18:10 2026) at `55a1dfc-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.8 ± 0.6 | 4.1 | 5.8 | 1.00 |
| `pkl:micro` | 8.6 ± 0.7 | 7.9 | 10.9 | 1.82 ± 0.27 |
| `mpkl:amend-base` | 5.2 ± 0.8 | 4.3 | 7.5 | 1.09 ± 0.22 |
| `pkl:amend-base` | 12.7 ± 5.6 | 7.9 | 33.5 | 2.66 ± 1.23 |
| `mpkl:map-value` | 5.6 ± 0.5 | 5.0 | 7.2 | 1.17 ± 0.18 |
| `pkl:map-value` | 8.5 ± 0.7 | 7.6 | 10.6 | 1.79 ± 0.26 |
| `mpkl:set-value` | 5.1 ± 1.2 | 4.5 | 10.9 | 1.08 ± 0.29 |
| `pkl:set-value` | 8.1 ± 0.4 | 7.5 | 8.7 | 1.70 ± 0.23 |
| `mpkl:int-seq` | 5.4 ± 0.9 | 4.5 | 7.1 | 1.13 ± 0.23 |
| `pkl:int-seq` | 9.1 ± 1.4 | 7.7 | 14.1 | 1.91 ± 0.37 |
| `mpkl:basic-int` | 10.0 ± 1.3 | 8.3 | 13.4 | 2.10 ± 0.38 |
| `pkl:basic-int` | 11.4 ± 1.7 | 9.6 | 14.9 | 2.40 ± 0.46 |
| `mpkl:basic-float` | 9.6 ± 1.5 | 8.6 | 15.4 | 2.03 ± 0.40 |
| `pkl:basic-float` | 9.4 ± 0.8 | 7.8 | 11.4 | 1.99 ± 0.29 |
| `mpkl:basic-string` | 10.7 ± 0.5 | 9.9 | 12.2 | 2.25 ± 0.30 |
| `pkl:basic-string` | 11.7 ± 3.4 | 9.3 | 24.1 | 2.45 ± 0.77 |
| `mpkl:basic-as` | 12.9 ± 2.2 | 10.1 | 17.7 | 2.72 ± 0.56 |
| `pkl:basic-as` | 10.4 ± 1.9 | 8.8 | 17.3 | 2.18 ± 0.48 |
| `mpkl:basic-is` | 11.6 ± 0.9 | 10.7 | 14.4 | 2.44 ± 0.36 |
| `pkl:basic-is` | 9.2 ± 0.7 | 8.1 | 10.9 | 1.93 ± 0.28 |
| `mpkl:basic-new` | 11.0 ± 1.6 | 10.1 | 18.3 | 2.31 ± 0.43 |
| `pkl:basic-new` | 10.3 ± 0.8 | 8.9 | 12.9 | 2.17 ± 0.32 |
| `mpkl:basic-rawstring` | 11.0 ± 0.7 | 10.3 | 13.2 | 2.30 ± 0.32 |
| `pkl:basic-rawstring` | 8.7 ± 1.3 | 7.6 | 14.5 | 1.82 ± 0.35 |
| `mpkl:pkspec-test-schema` | 27.2 ± 5.5 | 22.8 | 46.7 | 5.71 ± 1.36 |
| `pkl:pkspec-test-schema` | 10.2 ± 1.0 | 9.2 | 14.5 | 2.14 ± 0.34 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.75 ms | 8.63 ms | 0.55x |
| amend-base | 5.16 ms | 12.66 ms | 0.41x |
| map-value | 5.58 ms | 8.49 ms | 0.66x |
| set-value | 5.12 ms | 8.10 ms | 0.63x |
| int-seq | 5.37 ms | 9.07 ms | 0.59x |
| basic-int | 10.00 ms | 11.43 ms | 0.87x |
| basic-float | 9.64 ms | 9.44 ms | 1.02x |
| basic-string | 10.70 ms | 11.65 ms | 0.92x |
| basic-as | 12.94 ms | 10.35 ms | 1.25x |
| basic-is | 11.62 ms | 9.20 ms | 1.26x |
| basic-new | 10.99 ms | 10.34 ms | 1.06x |
| basic-rawstring | 10.96 ms | 8.66 ms | 1.26x |
| pkspec-test-schema | 27.17 ms | 10.18 ms | 2.67x |
