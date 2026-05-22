# Apple Pkl vs mpkl benchmark

- tag: `post-fastpaths`
- date: 2026-05-22T13:06:50Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:06:15 2026) at `71dbbaf-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=10, runs=50)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 11.7 ± 3.3 | 6.7 | 20.2 | 1.54 ± 0.46 |
| `pkl:micro` | 26.2 ± 6.2 | 18.2 | 43.4 | 3.45 ± 0.86 |
| `mpkl:amend-base` | 13.0 ± 2.9 | 7.9 | 21.0 | 1.71 ± 0.41 |
| `pkl:amend-base` | 26.8 ± 6.5 | 17.8 | 45.9 | 3.53 ± 0.91 |
| `mpkl:map-value` | 14.5 ± 3.5 | 8.8 | 26.8 | 1.90 ± 0.49 |
| `pkl:map-value` | 26.6 ± 23.1 | 12.2 | 177.6 | 3.50 ± 3.05 |
| `mpkl:set-value` | 18.0 ± 9.7 | 7.1 | 63.1 | 2.37 ± 1.29 |
| `pkl:set-value` | 25.8 ± 5.5 | 16.2 | 36.3 | 3.40 ± 0.77 |
| `mpkl:int-seq` | 13.2 ± 3.4 | 8.2 | 25.8 | 1.74 ± 0.47 |
| `pkl:int-seq` | 19.5 ± 6.4 | 12.8 | 55.5 | 2.56 ± 0.87 |
| `mpkl:basic-int` | 19.0 ± 3.7 | 10.5 | 31.0 | 2.50 ± 0.54 |
| `pkl:basic-int` | 29.2 ± 11.1 | 16.5 | 66.7 | 3.85 ± 1.49 |
| `mpkl:basic-float` | 21.7 ± 5.1 | 13.8 | 37.7 | 2.86 ± 0.71 |
| `pkl:basic-float` | 24.6 ± 6.4 | 15.7 | 42.0 | 3.24 ± 0.89 |
| `mpkl:basic-string` | 24.3 ± 4.7 | 16.1 | 36.0 | 3.20 ± 0.68 |
| `pkl:basic-string` | 47.3 ± 63.3 | 16.5 | 379.0 | 6.23 ± 8.35 |
| `mpkl:basic-as` | 25.2 ± 5.8 | 13.3 | 36.3 | 3.32 ± 0.81 |
| `pkl:basic-as` | 32.6 ± 14.9 | 17.2 | 111.8 | 4.30 ± 1.99 |
| `mpkl:basic-is` | 25.5 ± 6.6 | 15.6 | 44.7 | 3.36 ± 0.91 |
| `pkl:basic-is` | 26.2 ± 6.0 | 19.2 | 41.7 | 3.46 ± 0.84 |
| `mpkl:basic-new` | 23.0 ± 5.5 | 14.5 | 42.1 | 3.03 ± 0.77 |
| `pkl:basic-new` | 15.6 ± 4.1 | 10.5 | 28.2 | 2.06 ± 0.56 |
| `mpkl:basic-rawstring` | 12.0 ± 1.5 | 10.3 | 17.3 | 1.58 ± 0.24 |
| `pkl:basic-rawstring` | 7.6 ± 0.6 | 6.8 | 10.3 | 1.00 |
| `mpkl:pkspec-test-schema` | 22.5 ± 2.0 | 20.9 | 31.1 | 2.97 ± 0.36 |
| `pkl:pkspec-test-schema` | 10.6 ± 4.9 | 8.4 | 40.5 | 1.40 ± 0.65 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 11.68 ms | 26.21 ms | 0.45x |
| amend-base | 12.97 ms | 26.76 ms | 0.48x |
| map-value | 14.45 ms | 26.56 ms | 0.54x |
| set-value | 18.00 ms | 25.79 ms | 0.70x |
| int-seq | 13.24 ms | 19.47 ms | 0.68x |
| basic-int | 19.00 ms | 29.24 ms | 0.65x |
| basic-float | 21.68 ms | 24.62 ms | 0.88x |
| basic-string | 24.29 ms | 47.32 ms | 0.51x |
| basic-as | 25.21 ms | 32.63 ms | 0.77x |
| basic-is | 25.47 ms | 26.24 ms | 0.97x |
| basic-new | 23.01 ms | 15.61 ms | 1.47x |
| basic-rawstring | 11.99 ms | 7.59 ms | 1.58x |
| pkspec-test-schema | 22.53 ms | 10.61 ms | 2.12x |
