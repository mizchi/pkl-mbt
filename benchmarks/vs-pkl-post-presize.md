# Apple Pkl vs mpkl benchmark

- tag: `post-presize`
- date: 2026-05-22T13:54:18Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:53:06 2026) at `22fd394-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.4 ± 0.6 | 3.9 | 6.8 | 1.03 ± 0.14 |
| `pkl:micro` | 7.1 ± 0.3 | 6.7 | 8.2 | 1.67 ± 0.09 |
| `mpkl:amend-base` | 4.2 ± 0.1 | 4.1 | 4.6 | 1.00 |
| `pkl:amend-base` | 8.3 ± 1.7 | 6.9 | 14.8 | 1.96 ± 0.40 |
| `mpkl:map-value` | 5.1 ± 0.2 | 4.8 | 5.6 | 1.20 ± 0.06 |
| `pkl:map-value` | 7.5 ± 0.6 | 6.9 | 10.1 | 1.76 ± 0.16 |
| `mpkl:set-value` | 4.6 ± 0.1 | 4.4 | 4.9 | 1.09 ± 0.04 |
| `pkl:set-value` | 7.2 ± 0.3 | 6.6 | 7.9 | 1.69 ± 0.09 |
| `mpkl:int-seq` | 4.4 ± 0.1 | 4.2 | 4.5 | 1.03 ± 0.03 |
| `pkl:int-seq` | 10.1 ± 3.4 | 7.0 | 20.9 | 2.38 ± 0.81 |
| `mpkl:basic-int` | 10.2 ± 1.2 | 8.4 | 13.3 | 2.40 ± 0.29 |
| `pkl:basic-int` | 9.8 ± 1.3 | 8.1 | 12.7 | 2.30 ± 0.31 |
| `mpkl:basic-float` | 8.1 ± 0.5 | 7.7 | 10.5 | 1.91 ± 0.14 |
| `pkl:basic-float` | 8.8 ± 1.4 | 7.3 | 13.0 | 2.08 ± 0.33 |
| `mpkl:basic-string` | 10.1 ± 0.6 | 9.5 | 12.1 | 2.38 ± 0.16 |
| `pkl:basic-string` | 9.3 ± 0.4 | 8.6 | 10.3 | 2.19 ± 0.11 |
| `mpkl:basic-as` | 12.4 ± 1.9 | 9.9 | 17.1 | 2.92 ± 0.45 |
| `pkl:basic-as` | 9.3 ± 1.3 | 8.2 | 15.0 | 2.18 ± 0.32 |
| `mpkl:basic-is` | 11.0 ± 1.4 | 9.9 | 14.0 | 2.58 ± 0.33 |
| `pkl:basic-is` | 8.2 ± 0.9 | 7.1 | 11.7 | 1.92 ± 0.22 |
| `mpkl:basic-new` | 12.4 ± 3.0 | 10.0 | 21.6 | 2.91 ± 0.71 |
| `pkl:basic-new` | 11.0 ± 2.2 | 8.6 | 18.1 | 2.58 ± 0.53 |
| `mpkl:basic-rawstring` | 13.3 ± 1.6 | 10.1 | 15.5 | 3.15 ± 0.38 |
| `pkl:basic-rawstring` | 9.2 ± 1.7 | 7.0 | 14.0 | 2.17 ± 0.41 |
| `mpkl:pkspec-test-schema` | 22.7 ± 2.1 | 20.9 | 30.9 | 5.35 ± 0.52 |
| `pkl:pkspec-test-schema` | 11.2 ± 2.8 | 8.5 | 20.2 | 2.63 ± 0.66 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.36 ms | 7.06 ms | 0.62x |
| amend-base | 4.24 ms | 8.30 ms | 0.51x |
| map-value | 5.07 ms | 7.46 ms | 0.68x |
| set-value | 4.61 ms | 7.18 ms | 0.64x |
| int-seq | 4.36 ms | 10.12 ms | 0.43x |
| basic-int | 10.16 ms | 9.75 ms | 1.04x |
| basic-float | 8.11 ms | 8.83 ms | 0.92x |
| basic-string | 10.09 ms | 9.29 ms | 1.09x |
| basic-as | 12.40 ms | 9.26 ms | 1.34x |
| basic-is | 10.96 ms | 8.16 ms | 1.34x |
| basic-new | 12.36 ms | 10.95 ms | 1.13x |
| basic-rawstring | 13.35 ms | 9.22 ms | 1.45x |
| pkspec-test-schema | 22.70 ms | 11.18 ms | 2.03x |
