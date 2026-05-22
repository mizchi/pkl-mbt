# Apple Pkl vs mpkl benchmark

- tag: `post-alias-memo`
- date: 2026-05-22T14:21:06Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 23:19:21 2026) at `0a45f40-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.2 ± 0.3 | 3.8 | 4.8 | 1.00 |
| `pkl:micro` | 7.4 ± 0.7 | 6.5 | 9.7 | 1.76 ± 0.21 |
| `mpkl:amend-base` | 4.5 ± 0.2 | 4.2 | 5.0 | 1.08 ± 0.09 |
| `pkl:amend-base` | 7.1 ± 0.3 | 6.7 | 7.9 | 1.71 ± 0.14 |
| `mpkl:map-value` | 5.0 ± 0.2 | 4.7 | 5.4 | 1.19 ± 0.09 |
| `pkl:map-value` | 7.2 ± 0.3 | 6.9 | 8.2 | 1.73 ± 0.14 |
| `mpkl:set-value` | 4.7 ± 0.9 | 4.4 | 9.1 | 1.13 ± 0.23 |
| `pkl:set-value` | 7.4 ± 0.4 | 6.9 | 8.4 | 1.78 ± 0.15 |
| `mpkl:int-seq` | 4.6 ± 0.9 | 4.1 | 8.8 | 1.09 ± 0.23 |
| `pkl:int-seq` | 7.7 ± 0.6 | 6.7 | 9.2 | 1.83 ± 0.19 |
| `mpkl:basic-int` | 8.4 ± 0.9 | 7.7 | 12.4 | 2.01 ± 0.25 |
| `pkl:basic-int` | 8.7 ± 0.7 | 7.9 | 10.8 | 2.08 ± 0.22 |
| `mpkl:basic-float` | 8.2 ± 0.3 | 7.8 | 8.8 | 1.96 ± 0.14 |
| `pkl:basic-float` | 8.5 ± 1.0 | 7.4 | 11.1 | 2.02 ± 0.27 |
| `mpkl:basic-string` | 9.8 ± 0.5 | 9.3 | 11.7 | 2.35 ± 0.20 |
| `pkl:basic-string` | 11.3 ± 1.5 | 9.2 | 14.4 | 2.71 ± 0.41 |
| `mpkl:basic-as` | 10.5 ± 0.7 | 9.7 | 12.0 | 2.50 ± 0.23 |
| `pkl:basic-as` | 9.3 ± 0.7 | 8.4 | 10.8 | 2.23 ± 0.21 |
| `mpkl:basic-is` | 10.8 ± 1.3 | 10.0 | 16.2 | 2.57 ± 0.35 |
| `pkl:basic-is` | 8.0 ± 0.5 | 7.2 | 9.3 | 1.90 ± 0.17 |
| `mpkl:basic-new` | 9.7 ± 1.1 | 9.1 | 14.4 | 2.32 ± 0.29 |
| `pkl:basic-new` | 9.1 ± 0.4 | 8.5 | 9.9 | 2.17 ± 0.17 |
| `mpkl:basic-rawstring` | 10.1 ± 0.3 | 9.6 | 10.7 | 2.41 ± 0.17 |
| `pkl:basic-rawstring` | 7.3 ± 0.4 | 6.8 | 8.0 | 1.75 ± 0.14 |
| `mpkl:pkspec-test-schema` | 22.0 ± 1.9 | 20.4 | 27.1 | 5.25 ± 0.57 |
| `pkl:pkspec-test-schema` | 12.9 ± 11.0 | 8.8 | 61.3 | 3.08 ± 2.63 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.19 ms | 7.36 ms | 0.57x |
| amend-base | 4.53 ms | 7.14 ms | 0.63x |
| map-value | 4.97 ms | 7.25 ms | 0.69x |
| set-value | 4.74 ms | 7.44 ms | 0.64x |
| int-seq | 4.57 ms | 7.66 ms | 0.60x |
| basic-int | 8.43 ms | 8.69 ms | 0.97x |
| basic-float | 8.19 ms | 8.47 ms | 0.97x |
| basic-string | 9.84 ms | 11.33 ms | 0.87x |
| basic-as | 10.45 ms | 9.33 ms | 1.12x |
| basic-is | 10.75 ms | 7.97 ms | 1.35x |
| basic-new | 9.72 ms | 9.10 ms | 1.07x |
| basic-rawstring | 10.09 ms | 7.33 ms | 1.38x |
| pkspec-test-schema | 21.98 ms | 12.90 ms | 1.70x |
