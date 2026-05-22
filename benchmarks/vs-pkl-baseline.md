# Apple Pkl vs mpkl benchmark

- tag: `baseline`
- date: 2026-05-22T11:33:00Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 20:20:37 2026) at `55a1dfc-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 4.2 ± 0.2 | 3.9 | 4.8 | 1.00 |
| `pkl:micro` | 6.7 ± 0.3 | 6.3 | 7.4 | 1.59 ± 0.11 |
| `mpkl:amend-base` | 4.5 ± 0.4 | 4.2 | 6.0 | 1.07 ± 0.11 |
| `pkl:amend-base` | 7.2 ± 0.7 | 6.6 | 9.8 | 1.70 ± 0.19 |
| `mpkl:map-value` | 5.2 ± 0.2 | 4.9 | 5.8 | 1.23 ± 0.08 |
| `pkl:map-value` | 7.4 ± 0.7 | 6.7 | 9.9 | 1.76 ± 0.18 |
| `mpkl:set-value` | 4.8 ± 0.1 | 4.7 | 5.1 | 1.15 ± 0.07 |
| `pkl:set-value` | 7.4 ± 0.6 | 6.6 | 9.2 | 1.76 ± 0.17 |
| `mpkl:int-seq` | 4.5 ± 0.1 | 4.4 | 4.8 | 1.07 ± 0.07 |
| `pkl:int-seq` | 8.4 ± 0.9 | 7.2 | 11.7 | 2.00 ± 0.25 |
| `mpkl:basic-int` | 10.0 ± 0.7 | 8.5 | 11.3 | 2.37 ± 0.21 |
| `pkl:basic-int` | 8.8 ± 0.8 | 7.6 | 10.9 | 2.09 ± 0.21 |
| `mpkl:basic-float` | 8.7 ± 0.6 | 8.3 | 11.7 | 2.06 ± 0.19 |
| `pkl:basic-float` | 7.5 ± 0.3 | 6.9 | 8.3 | 1.77 ± 0.12 |
| `mpkl:basic-string` | 12.3 ± 2.7 | 10.0 | 20.3 | 2.92 ± 0.65 |
| `pkl:basic-string` | 8.5 ± 0.4 | 8.0 | 9.6 | 2.01 ± 0.14 |
| `mpkl:basic-as` | 10.7 ± 1.7 | 9.2 | 16.5 | 2.55 ± 0.42 |
| `pkl:basic-as` | 8.1 ± 0.3 | 7.7 | 9.1 | 1.92 ± 0.13 |
| `mpkl:basic-is` | 10.2 ± 0.3 | 9.7 | 10.7 | 2.42 ± 0.15 |
| `pkl:basic-is` | 7.4 ± 0.3 | 7.0 | 7.9 | 1.76 ± 0.12 |
| `mpkl:basic-new` | 14.2 ± 1.0 | 13.6 | 17.3 | 3.37 ± 0.30 |
| `pkl:basic-new` | 9.9 ± 0.9 | 8.5 | 13.2 | 2.35 ± 0.24 |
| `mpkl:basic-rawstring` | 14.8 ± 2.0 | 11.4 | 18.7 | 3.50 ± 0.50 |
| `pkl:basic-rawstring` | 7.9 ± 0.6 | 6.6 | 9.0 | 1.88 ± 0.18 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 4.22 ms | 6.73 ms | 0.63x |
| amend-base | 4.53 ms | 7.18 ms | 0.63x |
| map-value | 5.19 ms | 7.42 ms | 0.70x |
| set-value | 4.85 ms | 7.41 ms | 0.65x |
| int-seq | 4.53 ms | 8.42 ms | 0.54x |
| basic-int | 10.01 ms | 8.81 ms | 1.14x |
| basic-float | 8.68 ms | 7.46 ms | 1.16x |
| basic-string | 12.33 ms | 8.47 ms | 1.46x |
| basic-as | 10.74 ms | 8.12 ms | 1.32x |
| basic-is | 10.19 ms | 7.41 ms | 1.38x |
| basic-new | 14.19 ms | 9.89 ms | 1.43x |
| basic-rawstring | 14.77 ms | 7.94 ms | 1.86x |
