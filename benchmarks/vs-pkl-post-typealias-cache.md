# Apple Pkl vs mpkl benchmark

- tag: `post-typealias-cache`
- date: 2026-05-22T12:54:18Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 21:54:10 2026) at `d48f5e3-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.8 ± 0.4 | 4.3 | 5.9 | 1.00 |
| `pkl:micro` | 7.6 ± 0.6 | 7.0 | 9.5 | 1.60 ± 0.17 |
| `mpkl:amend-base` | 4.9 ± 0.9 | 4.3 | 8.9 | 1.04 ± 0.20 |
| `pkl:amend-base` | 9.5 ± 6.1 | 7.2 | 30.1 | 2.00 ± 1.29 |
| `mpkl:map-value` | 5.4 ± 0.2 | 4.9 | 6.2 | 1.13 ± 0.11 |
| `pkl:map-value` | 8.2 ± 0.6 | 7.5 | 9.7 | 1.73 ± 0.19 |
| `mpkl:set-value` | 5.0 ± 0.2 | 4.8 | 5.4 | 1.05 ± 0.09 |
| `pkl:set-value` | 9.0 ± 1.5 | 7.3 | 14.6 | 1.90 ± 0.34 |
| `mpkl:int-seq` | 5.1 ± 0.3 | 4.5 | 5.9 | 1.07 ± 0.11 |
| `pkl:int-seq` | 7.7 ± 0.3 | 7.2 | 8.3 | 1.62 ± 0.14 |
| `mpkl:basic-int` | 9.5 ± 0.8 | 8.8 | 11.9 | 2.00 ± 0.23 |
| `pkl:basic-int` | 10.2 ± 1.4 | 8.3 | 13.9 | 2.15 ± 0.34 |
| `mpkl:basic-float` | 9.5 ± 1.0 | 8.5 | 12.1 | 2.01 ± 0.26 |
| `pkl:basic-float` | 10.1 ± 2.4 | 8.5 | 21.3 | 2.14 ± 0.54 |
| `mpkl:basic-string` | 10.8 ± 0.4 | 10.2 | 11.6 | 2.28 ± 0.20 |
| `pkl:basic-string` | 9.4 ± 0.4 | 8.6 | 10.3 | 1.99 ± 0.19 |
| `mpkl:basic-as` | 10.6 ± 0.8 | 10.1 | 14.2 | 2.23 ± 0.25 |
| `pkl:basic-as` | 9.3 ± 1.4 | 8.5 | 15.7 | 1.96 ± 0.33 |
| `mpkl:basic-is` | 12.5 ± 1.7 | 10.6 | 15.5 | 2.64 ± 0.42 |
| `pkl:basic-is` | 8.3 ± 0.4 | 7.6 | 9.5 | 1.74 ± 0.17 |
| `mpkl:basic-new` | 10.9 ± 0.3 | 10.3 | 11.7 | 2.31 ± 0.20 |
| `pkl:basic-new` | 10.3 ± 1.5 | 9.1 | 15.5 | 2.17 ± 0.36 |
| `mpkl:basic-rawstring` | 11.1 ± 0.6 | 10.5 | 13.3 | 2.35 ± 0.23 |
| `pkl:basic-rawstring` | 8.0 ± 0.5 | 7.3 | 9.4 | 1.69 ± 0.18 |
| `mpkl:pkspec-test-schema` | 24.5 ± 0.7 | 23.3 | 26.0 | 5.17 ± 0.44 |
| `pkl:pkspec-test-schema` | 10.5 ± 1.5 | 9.1 | 15.5 | 2.21 ± 0.37 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.75 ms | 7.59 ms | 0.63x |
| amend-base | 4.93 ms | 9.49 ms | 0.52x |
| map-value | 5.38 ms | 8.23 ms | 0.65x |
| set-value | 5.01 ms | 9.00 ms | 0.56x |
| int-seq | 5.07 ms | 7.69 ms | 0.66x |
| basic-int | 9.50 ms | 10.24 ms | 0.93x |
| basic-float | 9.54 ms | 10.15 ms | 0.94x |
| basic-string | 10.84 ms | 9.43 ms | 1.15x |
| basic-as | 10.62 ms | 9.33 ms | 1.14x |
| basic-is | 12.53 ms | 8.26 ms | 1.52x |
| basic-new | 10.95 ms | 10.30 ms | 1.06x |
| basic-rawstring | 11.14 ms | 8.05 ms | 1.38x |
| pkspec-test-schema | 24.54 ms | 10.48 ms | 2.34x |
