# Apple Pkl vs mpkl benchmark

- tag: `final-stable`
- date: 2026-05-22T13:37:43Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:35:36 2026) at `8a953b5-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.2 ± 0.3 | 3.8 | 5.0 | 1.00 |
| `pkl:micro` | 8.0 ± 1.6 | 6.6 | 12.9 | 1.92 ± 0.40 |
| `mpkl:amend-base` | 5.3 ± 1.2 | 4.3 | 10.2 | 1.28 ± 0.30 |
| `pkl:amend-base` | 7.2 ± 0.6 | 6.5 | 8.7 | 1.73 ± 0.19 |
| `mpkl:map-value` | 6.1 ± 1.0 | 5.0 | 9.3 | 1.48 ± 0.25 |
| `pkl:map-value` | 12.2 ± 2.7 | 8.4 | 18.4 | 2.95 ± 0.67 |
| `mpkl:set-value` | 7.3 ± 1.7 | 5.2 | 11.5 | 1.76 ± 0.42 |
| `pkl:set-value` | 9.0 ± 2.8 | 6.7 | 20.0 | 2.17 ± 0.69 |
| `mpkl:int-seq` | 5.3 ± 0.7 | 4.3 | 7.2 | 1.27 ± 0.20 |
| `pkl:int-seq` | 10.5 ± 1.3 | 8.4 | 14.6 | 2.52 ± 0.36 |
| `mpkl:basic-int` | 9.3 ± 1.0 | 8.0 | 12.4 | 2.25 ± 0.29 |
| `pkl:basic-int` | 8.3 ± 0.7 | 7.4 | 10.1 | 1.99 ± 0.22 |
| `mpkl:basic-float` | 8.1 ± 0.8 | 7.6 | 12.0 | 1.94 ± 0.25 |
| `pkl:basic-float` | 11.0 ± 3.1 | 7.9 | 19.7 | 2.65 ± 0.77 |
| `mpkl:basic-string` | 12.6 ± 2.2 | 10.1 | 17.4 | 3.02 ± 0.58 |
| `pkl:basic-string` | 12.6 ± 6.2 | 9.3 | 38.7 | 3.04 ± 1.50 |
| `mpkl:basic-as` | 12.2 ± 2.2 | 10.0 | 19.0 | 2.93 ± 0.56 |
| `pkl:basic-as` | 12.7 ± 8.1 | 9.3 | 50.5 | 3.05 ± 1.96 |
| `mpkl:basic-is` | 10.8 ± 0.7 | 10.1 | 13.3 | 2.59 ± 0.25 |
| `pkl:basic-is` | 8.6 ± 0.5 | 7.7 | 9.7 | 2.06 ± 0.20 |
| `mpkl:basic-new` | 11.1 ± 0.8 | 10.2 | 13.4 | 2.67 ± 0.28 |
| `pkl:basic-new` | 10.1 ± 0.8 | 9.2 | 13.3 | 2.42 ± 0.25 |
| `mpkl:basic-rawstring` | 10.7 ± 0.5 | 10.1 | 12.3 | 2.58 ± 0.22 |
| `pkl:basic-rawstring` | 10.1 ± 2.6 | 7.5 | 18.6 | 2.44 ± 0.66 |
| `mpkl:pkspec-test-schema` | 23.2 ± 2.4 | 21.0 | 32.5 | 5.60 ± 0.70 |
| `pkl:pkspec-test-schema` | 10.8 ± 2.5 | 8.6 | 21.1 | 2.59 ± 0.62 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.15 ms | 7.97 ms | 0.52x |
| amend-base | 5.32 ms | 7.20 ms | 0.74x |
| map-value | 6.14 ms | 12.25 ms | 0.50x |
| set-value | 7.31 ms | 9.01 ms | 0.81x |
| int-seq | 5.30 ms | 10.47 ms | 0.51x |
| basic-int | 9.34 ms | 8.26 ms | 1.13x |
| basic-float | 8.08 ms | 10.99 ms | 0.74x |
| basic-string | 12.55 ms | 12.62 ms | 0.99x |
| basic-as | 12.19 ms | 12.68 ms | 0.96x |
| basic-is | 10.76 ms | 8.55 ms | 1.26x |
| basic-new | 11.10 ms | 10.06 ms | 1.10x |
| basic-rawstring | 10.73 ms | 10.14 ms | 1.06x |
| pkspec-test-schema | 23.25 ms | 10.76 ms | 2.16x |
