# Apple Pkl vs mpkl benchmark

- tag: `post-memoize-purity`
- date: 2026-05-23T07:40:44Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 23 16:37:41 2026) at `2f38bce-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=3, runs=15)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.7 ± 0.4 | 4.1 | 5.5 | 1.03 ± 0.10 |
| `pkl:micro` | 8.3 ± 0.5 | 7.6 | 9.3 | 1.83 ± 0.14 |
| `mpkl:amend-base` | 4.8 ± 0.4 | 4.4 | 5.8 | 1.05 ± 0.10 |
| `pkl:amend-base` | 8.4 ± 0.6 | 7.4 | 9.6 | 1.85 ± 0.16 |
| `mpkl:map-value` | 4.5 ± 0.2 | 4.2 | 4.9 | 1.00 |
| `pkl:map-value` | 8.1 ± 0.4 | 7.6 | 8.9 | 1.79 ± 0.12 |
| `mpkl:set-value` | 4.9 ± 0.3 | 4.5 | 5.8 | 1.07 ± 0.08 |
| `pkl:set-value` | 8.1 ± 0.5 | 7.5 | 9.1 | 1.79 ± 0.14 |
| `mpkl:int-seq` | 5.1 ± 0.4 | 4.5 | 6.0 | 1.13 ± 0.11 |
| `pkl:int-seq` | 8.9 ± 0.9 | 8.2 | 11.8 | 1.95 ± 0.23 |
| `mpkl:basic-int` | 7.1 ± 0.2 | 6.9 | 7.5 | 1.57 ± 0.09 |
| `pkl:basic-int` | 8.9 ± 0.6 | 8.2 | 10.4 | 1.97 ± 0.17 |
| `mpkl:basic-float` | 6.6 ± 0.2 | 6.2 | 7.0 | 1.45 ± 0.08 |
| `pkl:basic-float` | 9.2 ± 1.0 | 7.9 | 11.4 | 2.02 ± 0.24 |
| `mpkl:basic-string` | 6.4 ± 0.4 | 6.0 | 7.6 | 1.41 ± 0.12 |
| `pkl:basic-string` | 10.1 ± 0.8 | 8.7 | 11.1 | 2.23 ± 0.21 |
| `mpkl:basic-as` | 8.9 ± 1.9 | 7.0 | 13.5 | 1.95 ± 0.43 |
| `pkl:basic-as` | 10.7 ± 1.4 | 8.8 | 14.2 | 2.37 ± 0.34 |
| `mpkl:basic-is` | 7.4 ± 0.6 | 6.7 | 8.4 | 1.64 ± 0.15 |
| `pkl:basic-is` | 7.8 ± 0.5 | 7.2 | 8.9 | 1.73 ± 0.13 |
| `mpkl:basic-new` | 6.3 ± 0.1 | 6.1 | 6.6 | 1.39 ± 0.07 |
| `pkl:basic-new` | 8.8 ± 0.4 | 8.2 | 9.7 | 1.95 ± 0.14 |
| `mpkl:basic-rawstring` | 5.2 ± 0.1 | 5.0 | 5.5 | 1.14 ± 0.06 |
| `pkl:basic-rawstring` | 7.1 ± 0.3 | 6.5 | 7.7 | 1.56 ± 0.11 |
| `mpkl:pkspec-test-schema` | 21.9 ± 1.1 | 20.5 | 23.6 | 4.83 ± 0.34 |
| `pkl:pkspec-test-schema` | 8.8 ± 0.6 | 8.2 | 10.1 | 1.95 ± 0.16 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.67 ms | 8.31 ms | 0.56x |
| amend-base | 4.78 ms | 8.38 ms | 0.57x |
| map-value | 4.54 ms | 8.12 ms | 0.56x |
| set-value | 4.86 ms | 8.14 ms | 0.60x |
| int-seq | 5.12 ms | 8.86 ms | 0.58x |
| basic-int | 7.11 ms | 8.94 ms | 0.80x |
| basic-float | 6.56 ms | 9.16 ms | 0.72x |
| basic-string | 6.40 ms | 10.10 ms | 0.63x |
| basic-as | 8.86 ms | 10.74 ms | 0.82x |
| basic-is | 7.42 ms | 7.83 ms | 0.95x |
| basic-new | 6.30 ms | 8.85 ms | 0.71x |
| basic-rawstring | 5.19 ms | 7.06 ms | 0.74x |
| pkspec-test-schema | 21.89 ms | 8.84 ms | 2.48x |
