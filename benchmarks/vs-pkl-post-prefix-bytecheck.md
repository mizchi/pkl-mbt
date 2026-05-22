# Apple Pkl vs mpkl benchmark

- tag: `post-prefix-bytecheck`
- date: 2026-05-22T14:42:37Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 23:41:29 2026) at `17f162c-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.5 ± 0.3 | 4.1 | 5.4 | 1.00 |
| `pkl:micro` | 9.0 ± 0.8 | 7.7 | 11.4 | 1.99 ± 0.23 |
| `mpkl:amend-base` | 5.1 ± 1.1 | 4.4 | 8.7 | 1.13 ± 0.25 |
| `pkl:amend-base` | 9.5 ± 0.8 | 8.5 | 11.4 | 2.09 ± 0.24 |
| `mpkl:map-value` | 4.6 ± 0.2 | 4.3 | 5.0 | 1.02 ± 0.09 |
| `pkl:map-value` | 8.4 ± 0.3 | 7.9 | 9.0 | 1.84 ± 0.14 |
| `mpkl:set-value` | 5.0 ± 0.5 | 4.4 | 6.3 | 1.10 ± 0.14 |
| `pkl:set-value` | 9.4 ± 1.5 | 8.2 | 14.2 | 2.06 ± 0.37 |
| `mpkl:int-seq` | 4.9 ± 0.2 | 4.5 | 5.2 | 1.07 ± 0.09 |
| `pkl:int-seq` | 8.2 ± 0.3 | 7.8 | 9.1 | 1.81 ± 0.14 |
| `mpkl:basic-int` | 6.7 ± 0.2 | 6.4 | 7.3 | 1.48 ± 0.12 |
| `pkl:basic-int` | 9.7 ± 1.3 | 8.9 | 15.3 | 2.14 ± 0.32 |
| `mpkl:basic-float` | 7.5 ± 0.9 | 6.3 | 11.0 | 1.65 ± 0.23 |
| `pkl:basic-float` | 8.7 ± 0.4 | 8.2 | 9.7 | 1.91 ± 0.16 |
| `mpkl:basic-string` | 6.4 ± 0.2 | 6.1 | 6.7 | 1.41 ± 0.11 |
| `pkl:basic-string` | 10.1 ± 0.5 | 9.3 | 11.3 | 2.22 ± 0.19 |
| `mpkl:basic-as` | 7.5 ± 0.6 | 6.8 | 8.9 | 1.66 ± 0.18 |
| `pkl:basic-as` | 10.3 ± 0.4 | 9.6 | 11.1 | 2.26 ± 0.18 |
| `mpkl:basic-is` | 7.1 ± 0.3 | 6.6 | 7.9 | 1.57 ± 0.13 |
| `pkl:basic-is` | 9.7 ± 0.9 | 8.3 | 11.7 | 2.12 ± 0.24 |
| `mpkl:basic-new` | 8.0 ± 1.6 | 6.6 | 13.0 | 1.75 ± 0.38 |
| `pkl:basic-new` | 11.4 ± 1.8 | 9.7 | 16.7 | 2.50 ± 0.43 |
| `mpkl:basic-rawstring` | 5.4 ± 0.2 | 5.1 | 5.9 | 1.19 ± 0.10 |
| `pkl:basic-rawstring` | 8.7 ± 0.6 | 7.8 | 10.2 | 1.90 ± 0.19 |
| `mpkl:pkspec-test-schema` | 22.2 ± 1.8 | 20.4 | 27.5 | 4.89 ± 0.53 |
| `pkl:pkspec-test-schema` | 10.2 ± 0.6 | 9.6 | 12.7 | 2.25 ± 0.21 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.55 ms | 9.03 ms | 0.50x |
| amend-base | 5.15 ms | 9.51 ms | 0.54x |
| map-value | 4.64 ms | 8.36 ms | 0.55x |
| set-value | 5.01 ms | 9.36 ms | 0.54x |
| int-seq | 4.86 ms | 8.24 ms | 0.59x |
| basic-int | 6.72 ms | 9.71 ms | 0.69x |
| basic-float | 7.48 ms | 8.68 ms | 0.86x |
| basic-string | 6.40 ms | 10.09 ms | 0.63x |
| basic-as | 7.53 ms | 10.25 ms | 0.73x |
| basic-is | 7.11 ms | 9.65 ms | 0.74x |
| basic-new | 7.95 ms | 11.38 ms | 0.70x |
| basic-rawstring | 5.39 ms | 8.66 ms | 0.62x |
| pkspec-test-schema | 22.21 ms | 10.25 ms | 2.17x |
