# Apple Pkl vs mpkl benchmark

- tag: `final`
- date: 2026-05-22T13:37:26Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:35:36 2026) at `8a953b5-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=10, runs=40)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.6 ± 0.5 | 3.9 | 6.2 | 1.00 |
| `pkl:micro` | 9.4 ± 3.3 | 6.8 | 22.0 | 2.03 ± 0.75 |
| `mpkl:amend-base` | 5.5 ± 1.0 | 4.3 | 8.4 | 1.18 ± 0.24 |
| `pkl:amend-base` | 10.4 ± 2.0 | 8.0 | 17.6 | 2.25 ± 0.50 |
| `mpkl:map-value` | 5.9 ± 1.0 | 4.9 | 8.9 | 1.28 ± 0.26 |
| `pkl:map-value` | 8.6 ± 0.8 | 7.6 | 11.8 | 1.87 ± 0.27 |
| `mpkl:set-value` | 5.2 ± 0.9 | 4.4 | 8.0 | 1.13 ± 0.22 |
| `pkl:set-value` | 7.2 ± 0.4 | 6.8 | 8.5 | 1.56 ± 0.19 |
| `mpkl:int-seq` | 5.7 ± 2.2 | 4.3 | 12.6 | 1.23 ± 0.49 |
| `pkl:int-seq` | 9.2 ± 1.4 | 7.0 | 13.3 | 1.99 ± 0.37 |
| `mpkl:basic-int` | 10.8 ± 2.8 | 7.8 | 20.5 | 2.35 ± 0.65 |
| `pkl:basic-int` | 9.4 ± 1.4 | 7.6 | 14.9 | 2.04 ± 0.38 |
| `mpkl:basic-float` | 10.9 ± 2.5 | 7.6 | 16.2 | 2.36 ± 0.59 |
| `pkl:basic-float` | 9.5 ± 1.5 | 7.3 | 15.7 | 2.07 ± 0.40 |
| `mpkl:basic-string` | 15.0 ± 3.9 | 10.5 | 25.9 | 3.26 ± 0.92 |
| `pkl:basic-string` | 11.2 ± 1.7 | 8.8 | 16.4 | 2.44 ± 0.46 |
| `mpkl:basic-as` | 10.7 ± 1.2 | 9.6 | 17.0 | 2.31 ± 0.36 |
| `pkl:basic-as` | 9.2 ± 1.1 | 8.1 | 12.7 | 1.99 ± 0.32 |
| `mpkl:basic-is` | 11.9 ± 1.5 | 10.2 | 19.1 | 2.59 ± 0.43 |
| `pkl:basic-is` | 8.5 ± 1.1 | 7.2 | 12.7 | 1.85 ± 0.32 |
| `mpkl:basic-new` | 11.0 ± 1.3 | 9.5 | 13.9 | 2.38 ± 0.38 |
| `pkl:basic-new` | 11.0 ± 1.4 | 8.7 | 14.7 | 2.39 ± 0.40 |
| `mpkl:basic-rawstring` | 13.4 ± 4.0 | 9.9 | 26.4 | 2.91 ± 0.92 |
| `pkl:basic-rawstring` | 9.8 ± 1.4 | 8.6 | 17.2 | 2.12 ± 0.38 |
| `mpkl:pkspec-test-schema` | 32.9 ± 12.7 | 21.2 | 91.4 | 7.14 ± 2.86 |
| `pkl:pkspec-test-schema` | 9.8 ± 1.4 | 8.4 | 14.2 | 2.13 ± 0.39 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.61 ms | 9.38 ms | 0.49x |
| amend-base | 5.45 ms | 10.39 ms | 0.52x |
| map-value | 5.89 ms | 8.64 ms | 0.68x |
| set-value | 5.21 ms | 7.20 ms | 0.72x |
| int-seq | 5.68 ms | 9.16 ms | 0.62x |
| basic-int | 10.83 ms | 9.39 ms | 1.15x |
| basic-float | 10.87 ms | 9.52 ms | 1.14x |
| basic-string | 15.03 ms | 11.24 ms | 1.34x |
| basic-as | 10.67 ms | 9.20 ms | 1.16x |
| basic-is | 11.94 ms | 8.55 ms | 1.40x |
| basic-new | 10.98 ms | 11.00 ms | 1.00x |
| basic-rawstring | 13.42 ms | 9.78 ms | 1.37x |
| pkspec-test-schema | 32.93 ms | 9.82 ms | 3.35x |
