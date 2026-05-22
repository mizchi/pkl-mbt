# Apple Pkl vs mpkl benchmark

- tag: `post-env-presize`
- date: 2026-05-22T13:57:25Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:57:16 2026) at `22fd394-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.9 ± 0.4 | 4.1 | 5.7 | 1.00 |
| `pkl:micro` | 9.6 ± 2.6 | 7.2 | 20.2 | 1.96 ± 0.56 |
| `mpkl:amend-base` | 4.9 ± 0.7 | 4.2 | 7.1 | 1.00 ± 0.16 |
| `pkl:amend-base` | 8.9 ± 1.6 | 6.9 | 15.2 | 1.82 ± 0.36 |
| `mpkl:map-value` | 7.8 ± 2.1 | 5.5 | 13.0 | 1.59 ± 0.44 |
| `pkl:map-value` | 12.2 ± 1.9 | 9.9 | 18.7 | 2.49 ± 0.44 |
| `mpkl:set-value` | 7.5 ± 1.0 | 6.3 | 10.6 | 1.53 ± 0.23 |
| `pkl:set-value` | 9.3 ± 1.2 | 7.8 | 11.8 | 1.90 ± 0.29 |
| `mpkl:int-seq` | 4.9 ± 0.4 | 4.5 | 6.7 | 1.01 ± 0.12 |
| `pkl:int-seq` | 8.0 ± 1.2 | 6.9 | 12.3 | 1.64 ± 0.27 |
| `mpkl:basic-int` | 8.9 ± 0.7 | 8.2 | 10.6 | 1.81 ± 0.21 |
| `pkl:basic-int` | 9.6 ± 1.4 | 8.4 | 14.6 | 1.95 ± 0.32 |
| `mpkl:basic-float` | 9.2 ± 1.3 | 7.9 | 12.3 | 1.87 ± 0.31 |
| `pkl:basic-float` | 8.7 ± 1.3 | 7.9 | 14.7 | 1.78 ± 0.31 |
| `mpkl:basic-string` | 10.6 ± 1.4 | 9.8 | 16.9 | 2.16 ± 0.34 |
| `pkl:basic-string` | 10.1 ± 1.3 | 8.7 | 14.8 | 2.07 ± 0.32 |
| `mpkl:basic-as` | 10.4 ± 0.7 | 9.6 | 12.1 | 2.12 ± 0.22 |
| `pkl:basic-as` | 10.0 ± 1.0 | 9.0 | 14.5 | 2.04 ± 0.27 |
| `mpkl:basic-is` | 11.3 ± 1.4 | 10.1 | 16.7 | 2.30 ± 0.34 |
| `pkl:basic-is` | 9.0 ± 0.7 | 8.2 | 11.3 | 1.84 ± 0.20 |
| `mpkl:basic-new` | 10.6 ± 0.9 | 9.9 | 14.7 | 2.16 ± 0.26 |
| `pkl:basic-new` | 10.1 ± 0.7 | 8.6 | 11.4 | 2.05 ± 0.22 |
| `mpkl:basic-rawstring` | 15.3 ± 4.4 | 10.2 | 26.9 | 3.12 ± 0.93 |
| `pkl:basic-rawstring` | 13.0 ± 21.0 | 7.4 | 113.4 | 2.66 ± 4.29 |
| `mpkl:pkspec-test-schema` | 28.4 ± 7.4 | 22.3 | 49.0 | 5.80 ± 1.57 |
| `pkl:pkspec-test-schema` | 9.5 ± 1.0 | 8.4 | 13.7 | 1.93 ± 0.26 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.90 ms | 9.58 ms | 0.51x |
| amend-base | 4.91 ms | 8.90 ms | 0.55x |
| map-value | 7.81 ms | 12.19 ms | 0.64x |
| set-value | 7.49 ms | 9.31 ms | 0.80x |
| int-seq | 4.95 ms | 8.04 ms | 0.62x |
| basic-int | 8.87 ms | 9.57 ms | 0.93x |
| basic-float | 9.17 ms | 8.72 ms | 1.05x |
| basic-string | 10.57 ms | 10.14 ms | 1.04x |
| basic-as | 10.40 ms | 10.01 ms | 1.04x |
| basic-is | 11.29 ms | 9.03 ms | 1.25x |
| basic-new | 10.59 ms | 10.06 ms | 1.05x |
| basic-rawstring | 15.27 ms | 13.03 ms | 1.17x |
| pkspec-test-schema | 28.40 ms | 9.47 ms | 3.00x |
