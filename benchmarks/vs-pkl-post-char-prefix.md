# Apple Pkl vs mpkl benchmark

- tag: `post-char-prefix`
- date: 2026-05-22T13:35:44Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:35:36 2026) at `b1f2077-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 5.4 ± 0.8 | 4.3 | 7.7 | 1.22 ± 0.18 |
| `pkl:micro` | 8.4 ± 1.5 | 7.1 | 14.3 | 1.91 ± 0.35 |
| `mpkl:amend-base` | 4.4 ± 0.2 | 4.1 | 4.8 | 1.00 |
| `pkl:amend-base` | 7.0 ± 0.4 | 6.6 | 7.9 | 1.60 ± 0.11 |
| `mpkl:map-value` | 5.0 ± 0.1 | 4.8 | 5.2 | 1.12 ± 0.05 |
| `pkl:map-value` | 7.7 ± 0.8 | 6.8 | 10.1 | 1.74 ± 0.20 |
| `mpkl:set-value` | 4.6 ± 0.2 | 4.4 | 5.1 | 1.05 ± 0.06 |
| `pkl:set-value` | 8.2 ± 1.4 | 6.7 | 13.1 | 1.85 ± 0.34 |
| `mpkl:int-seq` | 4.8 ± 0.4 | 4.1 | 5.6 | 1.08 ± 0.11 |
| `pkl:int-seq` | 8.2 ± 0.9 | 7.1 | 10.7 | 1.87 ± 0.21 |
| `mpkl:basic-int` | 11.9 ± 7.1 | 8.3 | 41.1 | 2.69 ± 1.61 |
| `pkl:basic-int` | 8.8 ± 1.5 | 7.7 | 15.5 | 1.99 ± 0.36 |
| `mpkl:basic-float` | 8.8 ± 0.8 | 8.0 | 11.4 | 1.99 ± 0.20 |
| `pkl:basic-float` | 8.2 ± 1.4 | 7.0 | 13.3 | 1.87 ± 0.33 |
| `mpkl:basic-string` | 9.8 ± 0.4 | 9.4 | 11.6 | 2.22 ± 0.13 |
| `pkl:basic-string` | 10.1 ± 1.6 | 8.3 | 16.4 | 2.28 ± 0.37 |
| `mpkl:basic-as` | 9.6 ± 0.7 | 9.2 | 13.0 | 2.18 ± 0.19 |
| `pkl:basic-as` | 10.4 ± 3.2 | 8.1 | 21.6 | 2.37 ± 0.73 |
| `mpkl:basic-is` | 11.7 ± 1.9 | 10.0 | 18.3 | 2.66 ± 0.45 |
| `pkl:basic-is` | 7.6 ± 0.4 | 6.8 | 8.5 | 1.73 ± 0.12 |
| `mpkl:basic-new` | 11.2 ± 1.9 | 9.6 | 19.4 | 2.53 ± 0.44 |
| `pkl:basic-new` | 9.7 ± 1.2 | 8.5 | 12.7 | 2.20 ± 0.29 |
| `mpkl:basic-rawstring` | 12.1 ± 3.8 | 9.7 | 23.5 | 2.74 ± 0.86 |
| `pkl:basic-rawstring` | 8.8 ± 1.7 | 6.9 | 14.0 | 2.00 ± 0.40 |
| `mpkl:pkspec-test-schema` | 23.8 ± 7.0 | 20.8 | 56.4 | 5.40 ± 1.60 |
| `pkl:pkspec-test-schema` | 10.1 ± 1.4 | 8.4 | 13.6 | 2.28 ± 0.33 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 5.38 ms | 8.41 ms | 0.64x |
| amend-base | 4.41 ms | 7.04 ms | 0.63x |
| map-value | 4.95 ms | 7.69 ms | 0.64x |
| set-value | 4.61 ms | 8.17 ms | 0.56x |
| int-seq | 4.75 ms | 8.24 ms | 0.58x |
| basic-int | 11.87 ms | 8.78 ms | 1.35x |
| basic-float | 8.78 ms | 8.24 ms | 1.07x |
| basic-string | 9.78 ms | 10.06 ms | 0.97x |
| basic-as | 9.61 ms | 10.44 ms | 0.92x |
| basic-is | 11.73 ms | 7.64 ms | 1.54x |
| basic-new | 11.16 ms | 9.71 ms | 1.15x |
| basic-rawstring | 12.08 ms | 8.85 ms | 1.37x |
| pkspec-test-schema | 23.82 ms | 10.08 ms | 2.36x |
