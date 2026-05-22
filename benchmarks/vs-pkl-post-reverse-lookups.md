# Apple Pkl vs mpkl benchmark

- tag: `post-reverse-lookups`
- date: 2026-05-22T13:12:56Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:12:49 2026) at `c633a7e-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.3 ± 0.4 | 4.0 | 5.2 | 1.00 |
| `pkl:micro` | 8.5 ± 1.8 | 6.8 | 13.1 | 1.95 ± 0.44 |
| `mpkl:amend-base` | 4.6 ± 0.3 | 4.2 | 5.2 | 1.05 ± 0.11 |
| `pkl:amend-base` | 8.3 ± 0.9 | 7.3 | 10.8 | 1.92 ± 0.26 |
| `mpkl:map-value` | 5.0 ± 0.2 | 4.8 | 5.5 | 1.16 ± 0.10 |
| `pkl:map-value` | 7.8 ± 0.6 | 7.0 | 9.4 | 1.79 ± 0.20 |
| `mpkl:set-value` | 5.3 ± 0.9 | 4.4 | 8.8 | 1.23 ± 0.24 |
| `pkl:set-value` | 7.8 ± 0.3 | 7.2 | 8.8 | 1.79 ± 0.17 |
| `mpkl:int-seq` | 4.5 ± 0.1 | 4.3 | 4.8 | 1.03 ± 0.09 |
| `pkl:int-seq` | 8.2 ± 1.4 | 7.0 | 14.4 | 1.90 ± 0.36 |
| `mpkl:basic-int` | 8.2 ± 0.2 | 7.8 | 8.6 | 1.89 ± 0.16 |
| `pkl:basic-int` | 9.0 ± 1.3 | 8.0 | 14.6 | 2.07 ± 0.34 |
| `mpkl:basic-float` | 8.2 ± 0.3 | 7.8 | 8.9 | 1.89 ± 0.17 |
| `pkl:basic-float` | 8.5 ± 1.4 | 7.6 | 14.6 | 1.95 ± 0.36 |
| `mpkl:basic-string` | 10.5 ± 2.4 | 9.4 | 21.7 | 2.42 ± 0.59 |
| `pkl:basic-string` | 9.4 ± 0.6 | 8.1 | 10.7 | 2.17 ± 0.23 |
| `mpkl:basic-as` | 10.4 ± 1.1 | 9.6 | 14.9 | 2.40 ± 0.33 |
| `pkl:basic-as` | 9.7 ± 1.9 | 8.2 | 18.0 | 2.24 ± 0.48 |
| `mpkl:basic-is` | 11.2 ± 1.3 | 10.0 | 13.8 | 2.57 ± 0.36 |
| `pkl:basic-is` | 8.7 ± 1.5 | 7.5 | 15.2 | 2.01 ± 0.38 |
| `mpkl:basic-new` | 10.1 ± 0.2 | 9.6 | 10.6 | 2.32 ± 0.20 |
| `pkl:basic-new` | 10.7 ± 1.5 | 8.8 | 14.4 | 2.45 ± 0.40 |
| `mpkl:basic-rawstring` | 10.2 ± 0.3 | 9.7 | 10.9 | 2.34 ± 0.20 |
| `pkl:basic-rawstring` | 7.9 ± 1.1 | 7.0 | 13.0 | 1.82 ± 0.30 |
| `mpkl:pkspec-test-schema` | 22.8 ± 2.1 | 21.2 | 28.7 | 5.25 ± 0.64 |
| `pkl:pkspec-test-schema` | 12.3 ± 7.0 | 9.1 | 44.8 | 2.84 ± 1.63 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.35 ms | 8.46 ms | 0.51x |
| amend-base | 4.56 ms | 8.33 ms | 0.55x |
| map-value | 5.04 ms | 7.80 ms | 0.65x |
| set-value | 5.33 ms | 7.77 ms | 0.69x |
| int-seq | 4.47 ms | 8.24 ms | 0.54x |
| basic-int | 8.20 ms | 9.01 ms | 0.91x |
| basic-float | 8.20 ms | 8.49 ms | 0.97x |
| basic-string | 10.53 ms | 9.42 ms | 1.12x |
| basic-as | 10.45 ms | 9.73 ms | 1.07x |
| basic-is | 11.16 ms | 8.73 ms | 1.28x |
| basic-new | 10.08 ms | 10.66 ms | 0.95x |
| basic-rawstring | 10.18 ms | 7.89 ms | 1.29x |
| pkspec-test-schema | 22.80 ms | 12.32 ms | 1.85x |
