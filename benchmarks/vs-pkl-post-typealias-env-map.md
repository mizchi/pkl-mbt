# Apple Pkl vs mpkl benchmark

- tag: `post-typealias-env-map`
- date: 2026-05-22T13:27:32Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:27:25 2026) at `3707a67-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.2 ± 0.2 | 3.9 | 4.9 | 1.00 |
| `pkl:micro` | 7.3 ± 0.7 | 6.5 | 8.9 | 1.73 ± 0.20 |
| `mpkl:amend-base` | 4.2 ± 0.1 | 4.1 | 4.6 | 1.01 ± 0.07 |
| `pkl:amend-base` | 7.1 ± 1.2 | 6.6 | 12.8 | 1.69 ± 0.30 |
| `mpkl:map-value` | 7.5 ± 5.8 | 4.7 | 27.8 | 1.79 ± 1.39 |
| `pkl:map-value` | 7.9 ± 1.0 | 6.9 | 11.8 | 1.88 ± 0.26 |
| `mpkl:set-value` | 4.8 ± 0.2 | 4.5 | 5.2 | 1.14 ± 0.08 |
| `pkl:set-value` | 7.3 ± 0.4 | 6.8 | 8.2 | 1.74 ± 0.14 |
| `mpkl:int-seq` | 5.5 ± 3.1 | 4.2 | 15.7 | 1.31 ± 0.75 |
| `pkl:int-seq` | 7.7 ± 0.6 | 6.6 | 9.1 | 1.83 ± 0.18 |
| `mpkl:basic-int` | 8.4 ± 0.8 | 7.8 | 11.3 | 1.99 ± 0.23 |
| `pkl:basic-int` | 8.1 ± 0.7 | 7.4 | 9.9 | 1.92 ± 0.20 |
| `mpkl:basic-float` | 8.0 ± 0.5 | 7.7 | 9.6 | 1.91 ± 0.16 |
| `pkl:basic-float` | 7.3 ± 0.3 | 6.9 | 8.3 | 1.73 ± 0.12 |
| `mpkl:basic-string` | 10.1 ± 1.6 | 9.2 | 17.5 | 2.39 ± 0.41 |
| `pkl:basic-string` | 8.3 ± 0.3 | 7.9 | 9.1 | 1.98 ± 0.13 |
| `mpkl:basic-as` | 10.0 ± 1.5 | 9.1 | 15.9 | 2.37 ± 0.39 |
| `pkl:basic-as` | 8.4 ± 0.5 | 7.7 | 9.8 | 1.99 ± 0.16 |
| `mpkl:basic-is` | 10.5 ± 1.0 | 9.8 | 14.4 | 2.49 ± 0.28 |
| `pkl:basic-is` | 7.6 ± 0.3 | 7.1 | 8.6 | 1.82 ± 0.13 |
| `mpkl:basic-new` | 9.9 ± 1.0 | 9.4 | 14.4 | 2.36 ± 0.27 |
| `pkl:basic-new` | 8.7 ± 0.5 | 8.2 | 10.7 | 2.07 ± 0.18 |
| `mpkl:basic-rawstring` | 9.9 ± 1.0 | 9.5 | 14.9 | 2.36 ± 0.28 |
| `pkl:basic-rawstring` | 7.0 ± 0.4 | 6.4 | 7.8 | 1.65 ± 0.13 |
| `mpkl:pkspec-test-schema` | 21.0 ± 0.6 | 20.4 | 23.6 | 4.99 ± 0.33 |
| `pkl:pkspec-test-schema` | 9.0 ± 1.3 | 8.3 | 15.1 | 2.13 ± 0.34 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.20 ms | 7.27 ms | 0.58x |
| amend-base | 4.24 ms | 7.11 ms | 0.60x |
| map-value | 7.53 ms | 7.92 ms | 0.95x |
| set-value | 4.78 ms | 7.33 ms | 0.65x |
| int-seq | 5.52 ms | 7.68 ms | 0.72x |
| basic-int | 8.35 ms | 8.08 ms | 1.03x |
| basic-float | 8.02 ms | 7.28 ms | 1.10x |
| basic-string | 10.06 ms | 8.34 ms | 1.21x |
| basic-as | 9.95 ms | 8.38 ms | 1.19x |
| basic-is | 10.49 ms | 7.64 ms | 1.37x |
| basic-new | 9.92 ms | 8.72 ms | 1.14x |
| basic-rawstring | 9.91 ms | 6.95 ms | 1.43x |
| pkspec-test-schema | 20.96 ms | 8.97 ms | 2.34x |
