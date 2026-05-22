# Apple Pkl vs mpkl benchmark

- tag: `post-reflect-index`
- date: 2026-05-22T12:13:07Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 21:12:40 2026) at `55a1dfc-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.8 ± 0.4 | 4.2 | 5.8 | 1.00 |
| `pkl:micro` | 9.3 ± 1.5 | 7.8 | 13.6 | 1.92 ± 0.35 |
| `mpkl:amend-base` | 5.0 ± 0.4 | 4.6 | 6.3 | 1.03 ± 0.11 |
| `pkl:amend-base` | 7.6 ± 0.2 | 7.1 | 8.3 | 1.57 ± 0.13 |
| `mpkl:map-value` | 6.3 ± 1.1 | 5.4 | 9.8 | 1.30 ± 0.24 |
| `pkl:map-value` | 8.0 ± 0.8 | 7.4 | 11.2 | 1.65 ± 0.21 |
| `mpkl:set-value` | 5.2 ± 0.2 | 4.8 | 5.5 | 1.07 ± 0.09 |
| `pkl:set-value` | 9.2 ± 1.3 | 7.6 | 11.7 | 1.90 ± 0.31 |
| `mpkl:int-seq` | 5.4 ± 0.4 | 4.9 | 6.4 | 1.11 ± 0.11 |
| `pkl:int-seq` | 9.0 ± 0.9 | 7.4 | 10.7 | 1.87 ± 0.24 |
| `mpkl:basic-int` | 10.8 ± 1.7 | 9.5 | 17.2 | 2.23 ± 0.40 |
| `pkl:basic-int` | 11.0 ± 1.3 | 9.6 | 15.0 | 2.27 ± 0.31 |
| `mpkl:basic-float` | 11.4 ± 2.1 | 9.1 | 18.4 | 2.36 ± 0.48 |
| `pkl:basic-float` | 10.6 ± 1.8 | 8.0 | 16.4 | 2.20 ± 0.41 |
| `mpkl:basic-string` | 16.8 ± 2.7 | 11.5 | 22.1 | 3.46 ± 0.63 |
| `pkl:basic-string` | 10.1 ± 0.9 | 8.7 | 12.2 | 2.08 ± 0.24 |
| `mpkl:basic-as` | 12.4 ± 2.8 | 10.4 | 21.2 | 2.55 ± 0.60 |
| `pkl:basic-as` | 9.8 ± 1.2 | 8.7 | 13.3 | 2.03 ± 0.29 |
| `mpkl:basic-is` | 11.8 ± 1.2 | 10.9 | 16.9 | 2.44 ± 0.31 |
| `pkl:basic-is` | 8.7 ± 1.0 | 7.7 | 13.4 | 1.80 ± 0.26 |
| `mpkl:basic-new` | 13.7 ± 0.4 | 12.9 | 14.5 | 2.82 ± 0.23 |
| `pkl:basic-new` | 9.5 ± 0.3 | 9.1 | 10.4 | 1.97 ± 0.17 |
| `mpkl:basic-rawstring` | 12.3 ± 1.2 | 11.4 | 16.9 | 2.54 ± 0.31 |
| `pkl:basic-rawstring` | 8.5 ± 0.6 | 7.8 | 10.5 | 1.77 ± 0.18 |
| `mpkl:pkspec-test-schema` | 368.8 ± 21.2 | 341.4 | 429.7 | 76.20 ± 7.35 |
| `pkl:pkspec-test-schema` | 11.2 ± 0.6 | 10.1 | 12.6 | 2.31 ± 0.22 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.84 ms | 9.31 ms | 0.52x |
| amend-base | 4.96 ms | 7.60 ms | 0.65x |
| map-value | 6.28 ms | 7.97 ms | 0.79x |
| set-value | 5.17 ms | 9.17 ms | 0.56x |
| int-seq | 5.39 ms | 9.05 ms | 0.60x |
| basic-int | 10.81 ms | 10.96 ms | 0.99x |
| basic-float | 11.44 ms | 10.64 ms | 1.07x |
| basic-string | 16.76 ms | 10.06 ms | 1.67x |
| basic-as | 12.36 ms | 9.83 ms | 1.26x |
| basic-is | 11.82 ms | 8.73 ms | 1.35x |
| basic-new | 13.66 ms | 9.54 ms | 1.43x |
| basic-rawstring | 12.28 ms | 8.55 ms | 1.44x |
| pkspec-test-schema | 368.76 ms | 11.18 ms | 32.99x |
