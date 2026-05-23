# Apple Pkl vs mpkl benchmark

- tag: `post-refactor-final`
- date: 2026-05-23T08:02:41Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 23 16:59:39 2026) at `d3da178`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.6 ± 0.4 | 4.0 | 5.5 | 1.08 ± 0.11 |
| `pkl:micro` | 8.0 ± 0.2 | 7.6 | 8.3 | 1.87 ± 0.07 |
| `mpkl:amend-base` | 4.3 ± 0.1 | 4.1 | 4.6 | 1.00 |
| `pkl:amend-base` | 7.7 ± 0.3 | 7.3 | 8.3 | 1.82 ± 0.09 |
| `mpkl:map-value` | 4.8 ± 0.3 | 4.3 | 5.5 | 1.14 ± 0.08 |
| `pkl:map-value` | 9.0 ± 0.3 | 8.5 | 9.9 | 2.11 ± 0.09 |
| `mpkl:set-value` | 4.6 ± 0.2 | 4.3 | 5.1 | 1.09 ± 0.06 |
| `pkl:set-value` | 7.9 ± 0.3 | 7.1 | 8.5 | 1.85 ± 0.09 |
| `mpkl:int-seq` | 4.6 ± 0.3 | 4.2 | 5.0 | 1.07 ± 0.07 |
| `pkl:int-seq` | 7.6 ± 0.4 | 6.7 | 8.3 | 1.79 ± 0.11 |
| `mpkl:basic-int` | 7.2 ± 0.5 | 6.4 | 8.5 | 1.69 ± 0.13 |
| `pkl:basic-int` | 9.4 ± 0.4 | 8.5 | 9.9 | 2.20 ± 0.11 |
| `mpkl:basic-float` | 6.7 ± 0.2 | 6.4 | 7.1 | 1.57 ± 0.07 |
| `pkl:basic-float` | 8.1 ± 0.3 | 7.6 | 8.8 | 1.89 ± 0.09 |
| `mpkl:basic-string` | 6.3 ± 0.1 | 6.0 | 6.7 | 1.47 ± 0.06 |
| `pkl:basic-string` | 10.7 ± 0.9 | 9.2 | 12.5 | 2.52 ± 0.23 |
| `mpkl:basic-as` | 7.2 ± 0.3 | 6.7 | 8.0 | 1.70 ± 0.08 |
| `pkl:basic-as` | 9.1 ± 0.3 | 8.5 | 9.5 | 2.13 ± 0.09 |
| `mpkl:basic-is` | 6.9 ± 0.2 | 6.6 | 7.3 | 1.61 ± 0.06 |
| `pkl:basic-is` | 8.2 ± 0.2 | 7.8 | 8.7 | 1.93 ± 0.08 |
| `mpkl:basic-new` | 6.5 ± 0.1 | 6.2 | 6.8 | 1.52 ± 0.06 |
| `pkl:basic-new` | 9.8 ± 0.3 | 9.4 | 10.5 | 2.31 ± 0.10 |
| `mpkl:basic-rawstring` | 5.4 ± 0.2 | 5.1 | 5.7 | 1.27 ± 0.06 |
| `pkl:basic-rawstring` | 7.2 ± 0.4 | 6.6 | 8.0 | 1.68 ± 0.11 |
| `mpkl:pkspec-test-schema` | 20.4 ± 0.3 | 19.8 | 21.2 | 4.79 ± 0.17 |
| `pkl:pkspec-test-schema` | 9.6 ± 0.4 | 9.2 | 10.7 | 2.26 ± 0.11 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.59 ms | 7.97 ms | 0.58x |
| amend-base | 4.26 ms | 7.75 ms | 0.55x |
| map-value | 4.84 ms | 8.98 ms | 0.54x |
| set-value | 4.63 ms | 7.88 ms | 0.59x |
| int-seq | 4.56 ms | 7.64 ms | 0.60x |
| basic-int | 7.20 ms | 9.36 ms | 0.77x |
| basic-float | 6.68 ms | 8.05 ms | 0.83x |
| basic-string | 6.26 ms | 10.74 ms | 0.58x |
| basic-as | 7.24 ms | 9.09 ms | 0.80x |
| basic-is | 6.86 ms | 8.21 ms | 0.84x |
| basic-new | 6.48 ms | 9.84 ms | 0.66x |
| basic-rawstring | 5.39 ms | 7.16 ms | 0.75x |
| pkspec-test-schema | 20.40 ms | 9.65 ms | 2.11x |
