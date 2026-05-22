# Apple Pkl vs mpkl benchmark

- tag: `post-classdefault-memo`
- date: 2026-05-22T14:04:11Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 23:04:02 2026) at `8f29dcb-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.8 ± 0.9 | 4.2 | 9.0 | 1.10 ± 0.22 |
| `pkl:micro` | 7.9 ± 0.8 | 6.6 | 9.7 | 1.80 ± 0.20 |
| `mpkl:amend-base` | 4.4 ± 0.1 | 4.2 | 4.7 | 1.00 |
| `pkl:amend-base` | 7.9 ± 1.1 | 7.0 | 12.5 | 1.80 ± 0.25 |
| `mpkl:map-value` | 5.2 ± 0.3 | 4.7 | 6.1 | 1.19 ± 0.08 |
| `pkl:map-value` | 8.5 ± 1.2 | 7.2 | 12.4 | 1.94 ± 0.28 |
| `mpkl:set-value` | 4.7 ± 0.2 | 4.3 | 5.1 | 1.08 ± 0.06 |
| `pkl:set-value` | 7.7 ± 0.4 | 7.0 | 9.0 | 1.75 ± 0.12 |
| `mpkl:int-seq` | 4.6 ± 1.0 | 4.2 | 9.3 | 1.04 ± 0.23 |
| `pkl:int-seq` | 8.0 ± 0.9 | 6.8 | 10.4 | 1.83 ± 0.21 |
| `mpkl:basic-int` | 9.1 ± 1.5 | 8.1 | 15.4 | 2.08 ± 0.35 |
| `pkl:basic-int` | 8.7 ± 0.6 | 7.7 | 9.8 | 1.98 ± 0.16 |
| `mpkl:basic-float` | 8.9 ± 0.9 | 7.9 | 11.9 | 2.03 ± 0.22 |
| `pkl:basic-float` | 9.6 ± 1.0 | 8.5 | 12.3 | 2.20 ± 0.23 |
| `mpkl:basic-string` | 11.6 ± 2.3 | 9.7 | 22.0 | 2.64 ± 0.54 |
| `pkl:basic-string` | 10.8 ± 1.3 | 8.5 | 14.2 | 2.46 ± 0.31 |
| `mpkl:basic-as` | 11.1 ± 1.2 | 9.9 | 14.0 | 2.52 ± 0.29 |
| `pkl:basic-as` | 11.4 ± 2.2 | 9.1 | 18.3 | 2.59 ± 0.50 |
| `mpkl:basic-is` | 20.0 ± 6.9 | 12.2 | 35.4 | 4.55 ± 1.59 |
| `pkl:basic-is` | 15.6 ± 7.5 | 7.5 | 32.4 | 3.55 ± 1.70 |
| `mpkl:basic-new` | 9.9 ± 0.3 | 9.4 | 10.7 | 2.26 ± 0.10 |
| `pkl:basic-new` | 15.5 ± 4.5 | 10.6 | 27.6 | 3.53 ± 1.02 |
| `mpkl:basic-rawstring` | 15.0 ± 2.1 | 11.3 | 21.4 | 3.41 ± 0.50 |
| `pkl:basic-rawstring` | 8.4 ± 1.1 | 7.2 | 12.2 | 1.92 ± 0.25 |
| `mpkl:pkspec-test-schema` | 23.1 ± 1.6 | 21.3 | 28.5 | 5.26 ± 0.39 |
| `pkl:pkspec-test-schema` | 10.0 ± 1.0 | 8.9 | 13.8 | 2.27 ± 0.24 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.85 ms | 7.89 ms | 0.61x |
| amend-base | 4.39 ms | 7.92 ms | 0.55x |
| map-value | 5.24 ms | 8.51 ms | 0.62x |
| set-value | 4.75 ms | 7.68 ms | 0.62x |
| int-seq | 4.57 ms | 8.02 ms | 0.57x |
| basic-int | 9.14 ms | 8.71 ms | 1.05x |
| basic-float | 8.92 ms | 9.65 ms | 0.92x |
| basic-string | 11.58 ms | 10.79 ms | 1.07x |
| basic-as | 11.08 ms | 11.40 ms | 0.97x |
| basic-is | 19.97 ms | 15.59 ms | 1.28x |
| basic-new | 9.92 ms | 15.51 ms | 0.64x |
| basic-rawstring | 14.99 ms | 8.43 ms | 1.78x |
| pkspec-test-schema | 23.10 ms | 9.98 ms | 2.32x |
