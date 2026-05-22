# Apple Pkl vs mpkl benchmark

- tag: `post-glob-skip`
- date: 2026-05-22T14:30:08Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 23:27:06 2026) at `605c5f8-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.5 ± 0.8 | 3.9 | 7.1 | 1.08 ± 0.19 |
| `pkl:micro` | 7.5 ± 1.5 | 6.3 | 12.4 | 1.82 ± 0.36 |
| `mpkl:amend-base` | 4.1 ± 0.1 | 4.0 | 4.3 | 1.00 |
| `pkl:amend-base` | 7.4 ± 0.5 | 6.7 | 8.3 | 1.79 ± 0.12 |
| `mpkl:map-value` | 4.4 ± 0.1 | 4.2 | 4.8 | 1.07 ± 0.04 |
| `pkl:map-value` | 9.3 ± 3.7 | 6.9 | 24.0 | 2.27 ± 0.91 |
| `mpkl:set-value` | 4.8 ± 0.9 | 4.3 | 9.1 | 1.16 ± 0.23 |
| `pkl:set-value` | 7.3 ± 0.4 | 6.8 | 8.2 | 1.76 ± 0.10 |
| `mpkl:int-seq` | 10.4 ± 20.5 | 4.3 | 105.5 | 2.52 ± 4.97 |
| `pkl:int-seq` | 7.6 ± 0.4 | 6.8 | 8.4 | 1.83 ± 0.12 |
| `mpkl:basic-int` | 6.9 ± 0.6 | 6.3 | 8.5 | 1.67 ± 0.14 |
| `pkl:basic-int` | 8.1 ± 0.4 | 7.5 | 8.8 | 1.96 ± 0.10 |
| `mpkl:basic-float` | 6.6 ± 0.2 | 6.3 | 7.1 | 1.60 ± 0.06 |
| `pkl:basic-float` | 7.8 ± 0.6 | 6.9 | 9.2 | 1.89 ± 0.15 |
| `mpkl:basic-string` | 6.2 ± 0.2 | 6.0 | 6.6 | 1.50 ± 0.05 |
| `pkl:basic-string` | 9.0 ± 0.6 | 8.2 | 10.6 | 2.18 ± 0.15 |
| `mpkl:basic-as` | 6.9 ± 0.2 | 6.7 | 7.6 | 1.68 ± 0.07 |
| `pkl:basic-as` | 8.7 ± 0.6 | 7.8 | 9.7 | 2.11 ± 0.16 |
| `mpkl:basic-is` | 6.9 ± 0.3 | 6.6 | 7.6 | 1.66 ± 0.08 |
| `pkl:basic-is` | 7.6 ± 0.4 | 7.1 | 8.6 | 1.85 ± 0.10 |
| `mpkl:basic-new` | 6.4 ± 0.4 | 6.0 | 7.8 | 1.56 ± 0.09 |
| `pkl:basic-new` | 10.9 ± 6.8 | 8.4 | 43.4 | 2.63 ± 1.66 |
| `mpkl:basic-rawstring` | 5.2 ± 0.1 | 5.0 | 5.5 | 1.26 ± 0.04 |
| `pkl:basic-rawstring` | 8.2 ± 1.7 | 6.6 | 13.5 | 1.99 ± 0.41 |
| `mpkl:pkspec-test-schema` | 21.0 ± 0.8 | 20.1 | 23.1 | 5.08 ± 0.22 |
| `pkl:pkspec-test-schema` | 9.0 ± 0.8 | 8.1 | 12.3 | 2.19 ± 0.21 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.46 ms | 7.50 ms | 0.59x |
| amend-base | 4.13 ms | 7.37 ms | 0.56x |
| map-value | 4.43 ms | 9.35 ms | 0.47x |
| set-value | 4.77 ms | 7.26 ms | 0.66x |
| int-seq | 10.40 ms | 7.56 ms | 1.37x |
| basic-int | 6.89 ms | 8.10 ms | 0.85x |
| basic-float | 6.59 ms | 7.80 ms | 0.84x |
| basic-string | 6.20 ms | 8.99 ms | 0.69x |
| basic-as | 6.94 ms | 8.70 ms | 0.80x |
| basic-is | 6.85 ms | 7.65 ms | 0.90x |
| basic-new | 6.43 ms | 10.86 ms | 0.59x |
| basic-rawstring | 5.19 ms | 8.21 ms | 0.63x |
| pkspec-test-schema | 20.97 ms | 9.05 ms | 2.32x |
