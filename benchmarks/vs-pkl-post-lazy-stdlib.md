# Apple Pkl vs mpkl benchmark

- tag: `post-lazy-stdlib`
- date: 2026-05-23T07:33:00Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 23 16:30:03 2026) at `7cb8099-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=3, runs=15)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.9 ± 0.4 | 4.4 | 6.0 | 1.07 ± 0.10 |
| `pkl:micro` | 8.4 ± 0.4 | 8.0 | 9.5 | 1.83 ± 0.10 |
| `mpkl:amend-base` | 4.6 ± 0.2 | 4.3 | 4.8 | 1.00 |
| `pkl:amend-base` | 7.8 ± 0.3 | 7.3 | 8.3 | 1.70 ± 0.09 |
| `mpkl:map-value` | 4.7 ± 0.2 | 4.5 | 5.2 | 1.03 ± 0.06 |
| `pkl:map-value` | 10.8 ± 1.3 | 8.9 | 13.3 | 2.36 ± 0.28 |
| `mpkl:set-value` | 6.0 ± 0.5 | 5.3 | 7.2 | 1.31 ± 0.13 |
| `pkl:set-value` | 10.6 ± 1.6 | 9.3 | 15.2 | 2.33 ± 0.36 |
| `mpkl:int-seq` | 6.6 ± 0.7 | 5.7 | 8.2 | 1.45 ± 0.16 |
| `pkl:int-seq` | 9.9 ± 0.5 | 9.4 | 11.2 | 2.17 ± 0.12 |
| `mpkl:basic-int` | 7.4 ± 0.2 | 6.9 | 7.9 | 1.62 ± 0.08 |
| `pkl:basic-int` | 9.4 ± 0.5 | 8.6 | 10.4 | 2.05 ± 0.13 |
| `mpkl:basic-float` | 6.7 ± 0.2 | 6.3 | 7.0 | 1.47 ± 0.06 |
| `pkl:basic-float` | 9.1 ± 0.9 | 8.1 | 10.7 | 1.98 ± 0.21 |
| `mpkl:basic-string` | 7.3 ± 0.7 | 6.7 | 9.1 | 1.59 ± 0.16 |
| `pkl:basic-string` | 10.7 ± 0.6 | 9.6 | 11.8 | 2.33 ± 0.16 |
| `mpkl:basic-as` | 8.1 ± 0.3 | 7.6 | 8.5 | 1.78 ± 0.09 |
| `pkl:basic-as` | 11.7 ± 0.6 | 10.4 | 12.7 | 2.55 ± 0.16 |
| `mpkl:basic-is` | 8.0 ± 0.5 | 7.3 | 8.9 | 1.76 ± 0.12 |
| `pkl:basic-is` | 9.0 ± 0.5 | 8.1 | 9.8 | 1.96 ± 0.13 |
| `mpkl:basic-new` | 6.8 ± 0.4 | 6.4 | 8.2 | 1.48 ± 0.10 |
| `pkl:basic-new` | 12.6 ± 1.2 | 11.2 | 15.6 | 2.75 ± 0.28 |
| `mpkl:basic-rawstring` | 7.7 ± 0.8 | 6.7 | 9.0 | 1.68 ± 0.18 |
| `pkl:basic-rawstring` | 10.8 ± 1.0 | 9.8 | 13.6 | 2.36 ± 0.23 |
| `mpkl:pkspec-test-schema` | 22.9 ± 1.2 | 20.7 | 24.2 | 5.00 ± 0.31 |
| `pkl:pkspec-test-schema` | 11.1 ± 0.9 | 10.0 | 13.4 | 2.44 ± 0.20 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.88 ms | 8.37 ms | 0.58x |
| amend-base | 4.58 ms | 7.80 ms | 0.59x |
| map-value | 4.71 ms | 10.79 ms | 0.44x |
| set-value | 5.99 ms | 10.64 ms | 0.56x |
| int-seq | 6.64 ms | 9.93 ms | 0.67x |
| basic-int | 7.42 ms | 9.39 ms | 0.79x |
| basic-float | 6.73 ms | 9.07 ms | 0.74x |
| basic-string | 7.27 ms | 10.66 ms | 0.68x |
| basic-as | 8.15 ms | 11.69 ms | 0.70x |
| basic-is | 8.04 ms | 8.95 ms | 0.90x |
| basic-new | 6.79 ms | 12.57 ms | 0.54x |
| basic-rawstring | 7.71 ms | 10.82 ms | 0.71x |
| pkspec-test-schema | 22.90 ms | 11.15 ms | 2.05x |
