# Apple Pkl vs mpkl benchmark

- tag: `post-strip-inplace`
- date: 2026-05-23T07:47:07Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 23 16:43:39 2026) at `2f38bce-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.6 ± 0.3 | 4.0 | 5.3 | 1.02 ± 0.08 |
| `pkl:micro` | 8.0 ± 0.3 | 7.5 | 8.7 | 1.80 ± 0.09 |
| `mpkl:amend-base` | 5.8 ± 4.3 | 4.2 | 25.6 | 1.30 ± 0.97 |
| `pkl:amend-base` | 10.5 ± 4.1 | 7.1 | 26.4 | 2.35 ± 0.92 |
| `mpkl:map-value` | 5.2 ± 0.3 | 4.7 | 6.0 | 1.17 ± 0.08 |
| `pkl:map-value` | 8.9 ± 0.6 | 8.2 | 10.8 | 1.99 ± 0.14 |
| `mpkl:set-value` | 4.9 ± 0.3 | 4.5 | 5.8 | 1.09 ± 0.08 |
| `pkl:set-value` | 9.0 ± 0.9 | 7.7 | 10.4 | 2.03 ± 0.20 |
| `mpkl:int-seq` | 4.5 ± 0.1 | 4.2 | 4.7 | 1.00 |
| `pkl:int-seq` | 9.0 ± 1.0 | 8.0 | 11.4 | 2.03 ± 0.24 |
| `mpkl:basic-int` | 6.8 ± 0.3 | 6.2 | 7.4 | 1.53 ± 0.08 |
| `pkl:basic-int` | 8.9 ± 0.5 | 8.1 | 9.7 | 2.00 ± 0.12 |
| `mpkl:basic-float` | 6.6 ± 0.2 | 6.3 | 7.0 | 1.48 ± 0.06 |
| `pkl:basic-float` | 8.6 ± 0.6 | 7.6 | 9.8 | 1.94 ± 0.15 |
| `mpkl:basic-string` | 7.0 ± 0.7 | 6.5 | 9.6 | 1.58 ± 0.17 |
| `pkl:basic-string` | 13.5 ± 2.7 | 9.4 | 18.6 | 3.02 ± 0.61 |
| `mpkl:basic-as` | 9.4 ± 1.6 | 7.8 | 13.3 | 2.10 ± 0.37 |
| `pkl:basic-as` | 26.1 ± 24.1 | 10.9 | 129.0 | 5.85 ± 5.42 |
| `mpkl:basic-is` | 8.0 ± 0.5 | 7.4 | 9.0 | 1.80 ± 0.12 |
| `pkl:basic-is` | 9.9 ± 0.8 | 8.5 | 11.7 | 2.22 ± 0.19 |
| `mpkl:basic-new` | 13.3 ± 13.0 | 7.1 | 72.9 | 2.99 ± 2.92 |
| `pkl:basic-new` | 11.0 ± 0.6 | 10.0 | 12.7 | 2.48 ± 0.15 |
| `mpkl:basic-rawstring` | 7.6 ± 5.4 | 5.3 | 27.8 | 1.71 ± 1.20 |
| `pkl:basic-rawstring` | 10.2 ± 1.6 | 8.4 | 15.0 | 2.30 ± 0.36 |
| `mpkl:pkspec-test-schema` | 35.0 ± 9.6 | 25.4 | 58.1 | 7.85 ± 2.17 |
| `pkl:pkspec-test-schema` | 13.4 ± 4.5 | 9.0 | 28.8 | 3.00 ± 1.00 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.57 ms | 8.01 ms | 0.57x |
| amend-base | 5.78 ms | 10.46 ms | 0.55x |
| map-value | 5.24 ms | 8.87 ms | 0.59x |
| set-value | 4.86 ms | 9.03 ms | 0.54x |
| int-seq | 4.46 ms | 9.04 ms | 0.49x |
| basic-int | 6.80 ms | 8.92 ms | 0.76x |
| basic-float | 6.62 ms | 8.64 ms | 0.77x |
| basic-string | 7.05 ms | 13.45 ms | 0.52x |
| basic-as | 9.37 ms | 26.06 ms | 0.36x |
| basic-is | 8.01 ms | 9.91 ms | 0.81x |
| basic-new | 13.31 ms | 11.05 ms | 1.20x |
| basic-rawstring | 7.63 ms | 10.24 ms | 0.74x |
| pkspec-test-schema | 35.01 ms | 13.37 ms | 2.62x |
