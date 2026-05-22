# Apple Pkl vs mpkl benchmark

- tag: `post-class-env-map`
- date: 2026-05-22T13:24:47Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:24:39 2026) at `3707a67-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.3 ± 0.3 | 3.9 | 5.4 | 1.01 ± 0.08 |
| `pkl:micro` | 7.2 ± 1.3 | 6.3 | 13.3 | 1.68 ± 0.31 |
| `mpkl:amend-base` | 4.3 ± 0.1 | 4.1 | 4.6 | 1.00 |
| `pkl:amend-base` | 7.2 ± 0.4 | 6.6 | 8.0 | 1.69 ± 0.10 |
| `mpkl:map-value` | 5.0 ± 0.3 | 4.7 | 6.1 | 1.17 ± 0.08 |
| `pkl:map-value` | 7.4 ± 0.5 | 6.8 | 8.7 | 1.73 ± 0.12 |
| `mpkl:set-value` | 4.6 ± 0.1 | 4.4 | 5.0 | 1.07 ± 0.04 |
| `pkl:set-value` | 8.4 ± 1.6 | 7.0 | 12.8 | 1.97 ± 0.38 |
| `mpkl:int-seq` | 4.5 ± 0.3 | 4.1 | 5.4 | 1.06 ± 0.08 |
| `pkl:int-seq` | 7.4 ± 0.4 | 6.7 | 8.6 | 1.73 ± 0.12 |
| `mpkl:basic-int` | 8.1 ± 0.2 | 7.8 | 8.7 | 1.89 ± 0.07 |
| `pkl:basic-int` | 8.0 ± 0.4 | 7.5 | 9.0 | 1.86 ± 0.10 |
| `mpkl:basic-float` | 8.5 ± 1.1 | 7.8 | 13.5 | 1.98 ± 0.27 |
| `pkl:basic-float` | 7.8 ± 0.9 | 6.9 | 11.3 | 1.82 ± 0.23 |
| `mpkl:basic-string` | 10.7 ± 1.0 | 10.1 | 15.3 | 2.51 ± 0.25 |
| `pkl:basic-string` | 10.0 ± 2.5 | 8.3 | 19.4 | 2.34 ± 0.60 |
| `mpkl:basic-as` | 9.7 ± 0.7 | 9.2 | 12.6 | 2.28 ± 0.17 |
| `pkl:basic-as` | 9.2 ± 0.9 | 8.2 | 12.3 | 2.15 ± 0.22 |
| `mpkl:basic-is` | 10.2 ± 0.2 | 9.8 | 10.5 | 2.37 ± 0.09 |
| `pkl:basic-is` | 8.9 ± 1.3 | 7.4 | 12.0 | 2.09 ± 0.31 |
| `mpkl:basic-new` | 10.0 ± 0.4 | 9.5 | 11.3 | 2.33 ± 0.12 |
| `pkl:basic-new` | 9.4 ± 1.7 | 8.3 | 14.2 | 2.21 ± 0.40 |
| `mpkl:basic-rawstring` | 10.0 ± 0.3 | 9.6 | 10.8 | 2.34 ± 0.10 |
| `pkl:basic-rawstring` | 8.5 ± 6.1 | 6.5 | 37.5 | 2.00 ± 1.42 |
| `mpkl:pkspec-test-schema` | 22.0 ± 1.5 | 20.8 | 25.5 | 5.14 ± 0.39 |
| `pkl:pkspec-test-schema` | 9.0 ± 0.4 | 8.3 | 9.9 | 2.11 ± 0.12 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.33 ms | 7.21 ms | 0.60x |
| amend-base | 4.28 ms | 7.21 ms | 0.59x |
| map-value | 5.01 ms | 7.39 ms | 0.68x |
| set-value | 4.59 ms | 8.41 ms | 0.55x |
| int-seq | 4.54 ms | 7.42 ms | 0.61x |
| basic-int | 8.09 ms | 7.96 ms | 1.02x |
| basic-float | 8.46 ms | 7.78 ms | 1.09x |
| basic-string | 10.73 ms | 10.04 ms | 1.07x |
| basic-as | 9.74 ms | 9.18 ms | 1.06x |
| basic-is | 10.15 ms | 8.93 ms | 1.14x |
| basic-new | 9.96 ms | 9.44 ms | 1.05x |
| basic-rawstring | 10.01 ms | 8.54 ms | 1.17x |
| pkspec-test-schema | 22.02 ms | 9.04 ms | 2.44x |
