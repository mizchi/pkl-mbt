# Apple Pkl vs mpkl benchmark

- tag: `post-char-find`
- date: 2026-05-22T13:31:48Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:31:41 2026) at `1699587-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.5 ± 1.2 | 3.9 | 10.0 | 1.04 ± 0.28 |
| `pkl:micro` | 7.0 ± 0.4 | 6.4 | 8.2 | 1.63 ± 0.10 |
| `mpkl:amend-base` | 4.3 ± 0.1 | 4.1 | 4.5 | 1.00 |
| `pkl:amend-base` | 7.6 ± 1.2 | 6.7 | 12.6 | 1.76 ± 0.28 |
| `mpkl:map-value` | 4.9 ± 0.1 | 4.7 | 5.1 | 1.14 ± 0.04 |
| `pkl:map-value` | 7.5 ± 1.0 | 6.7 | 11.0 | 1.74 ± 0.24 |
| `mpkl:set-value` | 4.6 ± 0.2 | 4.3 | 5.2 | 1.06 ± 0.06 |
| `pkl:set-value` | 7.3 ± 0.4 | 6.6 | 8.3 | 1.70 ± 0.10 |
| `mpkl:int-seq` | 4.3 ± 0.1 | 4.1 | 4.8 | 1.00 ± 0.04 |
| `pkl:int-seq` | 7.3 ± 1.1 | 6.8 | 12.3 | 1.69 ± 0.26 |
| `mpkl:basic-int` | 8.1 ± 0.3 | 7.8 | 8.9 | 1.87 ± 0.08 |
| `pkl:basic-int` | 8.1 ± 1.1 | 7.5 | 12.9 | 1.88 ± 0.26 |
| `mpkl:basic-float` | 8.0 ± 0.2 | 7.7 | 8.5 | 1.86 ± 0.07 |
| `pkl:basic-float` | 7.7 ± 1.0 | 7.0 | 12.1 | 1.80 ± 0.23 |
| `mpkl:basic-string` | 9.6 ± 0.2 | 9.2 | 10.2 | 2.23 ± 0.07 |
| `pkl:basic-string` | 8.7 ± 1.2 | 7.8 | 13.8 | 2.02 ± 0.28 |
| `mpkl:basic-as` | 9.5 ± 0.4 | 9.2 | 10.9 | 2.21 ± 0.11 |
| `pkl:basic-as` | 8.5 ± 1.3 | 7.8 | 14.6 | 1.99 ± 0.31 |
| `mpkl:basic-is` | 10.0 ± 0.2 | 9.8 | 10.4 | 2.33 ± 0.07 |
| `pkl:basic-is` | 7.6 ± 0.9 | 7.1 | 11.9 | 1.77 ± 0.22 |
| `mpkl:basic-new` | 9.9 ± 0.3 | 9.5 | 10.8 | 2.30 ± 0.10 |
| `pkl:basic-new` | 8.9 ± 0.6 | 8.3 | 10.5 | 2.07 ± 0.15 |
| `mpkl:basic-rawstring` | 10.0 ± 0.5 | 9.5 | 12.0 | 2.31 ± 0.13 |
| `pkl:basic-rawstring` | 7.2 ± 0.4 | 6.6 | 8.6 | 1.68 ± 0.11 |
| `mpkl:pkspec-test-schema` | 21.2 ± 0.9 | 20.5 | 24.5 | 4.93 ± 0.24 |
| `pkl:pkspec-test-schema` | 8.9 ± 0.4 | 8.4 | 9.8 | 2.07 ± 0.10 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.48 ms | 7.00 ms | 0.64x |
| amend-base | 4.30 ms | 7.55 ms | 0.57x |
| map-value | 4.91 ms | 7.48 ms | 0.66x |
| set-value | 4.55 ms | 7.33 ms | 0.62x |
| int-seq | 4.32 ms | 7.25 ms | 0.60x |
| basic-int | 8.05 ms | 8.08 ms | 1.00x |
| basic-float | 7.99 ms | 7.73 ms | 1.03x |
| basic-string | 9.58 ms | 8.68 ms | 1.10x |
| basic-as | 9.53 ms | 8.54 ms | 1.11x |
| basic-is | 10.02 ms | 7.60 ms | 1.32x |
| basic-new | 9.90 ms | 8.92 ms | 1.11x |
| basic-rawstring | 9.95 ms | 7.25 ms | 1.37x |
| pkspec-test-schema | 21.22 ms | 8.91 ms | 2.38x |
