# Apple Pkl vs mpkl benchmark

- tag: `baseline-7cb8099`
- date: 2026-05-23T07:25:31Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 23 16:16:20 2026) at `7cb8099`
- hyperfine: `hyperfine 1.20.0` (warmup=3, runs=15)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 5.3 ± 0.3 | 4.8 | 5.7 | 1.08 ± 0.06 |
| `pkl:micro` | 11.9 ± 8.4 | 7.9 | 40.7 | 2.44 ± 1.71 |
| `mpkl:amend-base` | 5.5 ± 0.2 | 5.2 | 5.8 | 1.12 ± 0.05 |
| `pkl:amend-base` | 8.9 ± 0.5 | 8.4 | 10.4 | 1.83 ± 0.11 |
| `mpkl:map-value` | 5.7 ± 0.2 | 5.4 | 5.9 | 1.16 ± 0.04 |
| `pkl:map-value` | 8.3 ± 0.3 | 7.9 | 8.7 | 1.69 ± 0.07 |
| `mpkl:set-value` | 4.9 ± 0.1 | 4.8 | 5.2 | 1.00 |
| `pkl:set-value` | 8.8 ± 0.8 | 7.8 | 10.5 | 1.80 ± 0.18 |
| `mpkl:int-seq` | 4.9 ± 0.2 | 4.7 | 5.3 | 1.01 ± 0.04 |
| `pkl:int-seq` | 8.4 ± 0.5 | 7.9 | 9.7 | 1.72 ± 0.11 |
| `mpkl:basic-int` | 7.9 ± 0.3 | 7.3 | 8.4 | 1.61 ± 0.08 |
| `pkl:basic-int` | 10.0 ± 0.3 | 9.5 | 10.4 | 2.04 ± 0.08 |
| `mpkl:basic-float` | 7.7 ± 0.3 | 7.3 | 8.1 | 1.58 ± 0.07 |
| `pkl:basic-float` | 8.8 ± 0.4 | 8.2 | 9.6 | 1.80 ± 0.09 |
| `mpkl:basic-string` | 7.3 ± 0.2 | 6.9 | 7.6 | 1.49 ± 0.06 |
| `pkl:basic-string` | 9.8 ± 0.5 | 9.1 | 10.8 | 2.00 ± 0.12 |
| `mpkl:basic-as` | 8.6 ± 1.3 | 7.3 | 11.6 | 1.76 ± 0.27 |
| `pkl:basic-as` | 11.9 ± 1.6 | 9.8 | 16.8 | 2.44 ± 0.33 |
| `mpkl:basic-is` | 8.6 ± 0.3 | 8.2 | 9.0 | 1.76 ± 0.07 |
| `pkl:basic-is` | 10.3 ± 1.1 | 8.5 | 12.6 | 2.10 ± 0.22 |
| `mpkl:basic-new` | 7.4 ± 0.2 | 7.0 | 7.8 | 1.52 ± 0.06 |
| `pkl:basic-new` | 10.8 ± 0.5 | 10.2 | 11.8 | 2.20 ± 0.11 |
| `mpkl:basic-rawstring` | 6.2 ± 0.2 | 5.9 | 6.5 | 1.27 ± 0.05 |
| `pkl:basic-rawstring` | 8.3 ± 0.3 | 7.7 | 8.8 | 1.69 ± 0.08 |
| `mpkl:pkspec-test-schema` | 24.1 ± 2.3 | 22.2 | 31.4 | 4.92 ± 0.48 |
| `pkl:pkspec-test-schema` | 11.2 ± 0.7 | 10.4 | 12.5 | 2.29 ± 0.15 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 5.26 ms | 11.95 ms | 0.44x |
| amend-base | 5.48 ms | 8.95 ms | 0.61x |
| map-value | 5.65 ms | 8.27 ms | 0.68x |
| set-value | 4.89 ms | 8.78 ms | 0.56x |
| int-seq | 4.93 ms | 8.39 ms | 0.59x |
| basic-int | 7.88 ms | 9.97 ms | 0.79x |
| basic-float | 7.70 ms | 8.80 ms | 0.87x |
| basic-string | 7.29 ms | 9.77 ms | 0.75x |
| basic-as | 8.58 ms | 11.92 ms | 0.72x |
| basic-is | 8.60 ms | 10.28 ms | 0.84x |
| basic-new | 7.42 ms | 10.76 ms | 0.69x |
| basic-rawstring | 6.20 ms | 8.26 ms | 0.75x |
| pkspec-test-schema | 24.08 ms | 11.22 ms | 2.15x |
