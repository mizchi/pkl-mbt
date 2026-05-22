# Apple Pkl vs mpkl benchmark

- tag: `post-cycle-fix`
- date: 2026-05-22T11:53:32Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 20:53:13 2026) at `55a1dfc-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 6.9 ± 4.7 | 4.2 | 26.5 | 1.12 ± 0.77 |
| `pkl:micro` | 14.3 ± 1.7 | 9.9 | 18.7 | 2.32 ± 0.36 |
| `mpkl:amend-base` | 11.7 ± 5.5 | 6.6 | 24.4 | 1.89 ± 0.90 |
| `pkl:amend-base` | 10.6 ± 1.1 | 8.7 | 13.0 | 1.71 ± 0.25 |
| `mpkl:map-value` | 6.2 ± 0.6 | 5.3 | 7.9 | 1.00 |
| `pkl:map-value` | 14.3 ± 8.6 | 9.5 | 44.8 | 2.31 ± 1.41 |
| `mpkl:set-value` | 10.1 ± 1.3 | 7.0 | 13.1 | 1.63 ± 0.27 |
| `pkl:set-value` | 16.0 ± 1.6 | 12.1 | 20.1 | 2.59 ± 0.36 |
| `mpkl:int-seq` | 8.4 ± 1.0 | 6.4 | 10.8 | 1.35 ± 0.21 |
| `pkl:int-seq` | 14.0 ± 6.2 | 9.8 | 43.0 | 2.26 ± 1.03 |
| `mpkl:basic-int` | 11.5 ± 1.3 | 9.9 | 14.8 | 1.86 ± 0.28 |
| `pkl:basic-int` | 11.2 ± 1.8 | 9.5 | 17.8 | 1.81 ± 0.34 |
| `mpkl:basic-float` | 10.5 ± 0.6 | 9.8 | 12.4 | 1.70 ± 0.19 |
| `pkl:basic-float` | 9.1 ± 0.7 | 8.2 | 11.6 | 1.48 ± 0.19 |
| `mpkl:basic-string` | 20.4 ± 7.1 | 13.3 | 40.9 | 3.30 ± 1.19 |
| `pkl:basic-string` | 17.5 ± 18.2 | 9.6 | 100.9 | 2.84 ± 2.96 |
| `mpkl:basic-as` | 18.3 ± 2.0 | 14.5 | 21.7 | 2.96 ± 0.44 |
| `pkl:basic-as` | 13.7 ± 3.1 | 10.9 | 24.6 | 2.21 ± 0.54 |
| `mpkl:basic-is` | 16.3 ± 5.8 | 11.7 | 40.2 | 2.63 ± 0.98 |
| `pkl:basic-is` | 18.3 ± 1.8 | 13.5 | 21.4 | 2.96 ± 0.42 |
| `mpkl:basic-new` | 23.1 ± 1.9 | 20.7 | 27.1 | 3.73 ± 0.48 |
| `pkl:basic-new` | 18.2 ± 7.2 | 12.1 | 43.4 | 2.94 ± 1.20 |
| `mpkl:basic-rawstring` | 16.8 ± 2.9 | 13.7 | 24.9 | 2.72 ± 0.54 |
| `pkl:basic-rawstring` | 11.5 ± 1.8 | 9.5 | 15.5 | 1.86 ± 0.35 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 6.94 ms | 14.32 ms | 0.48x |
| amend-base | 11.67 ms | 10.57 ms | 1.10x |
| map-value | 6.18 ms | 14.26 ms | 0.43x |
| set-value | 10.06 ms | 16.01 ms | 0.63x |
| int-seq | 8.37 ms | 13.98 ms | 0.60x |
| basic-int | 11.50 ms | 11.21 ms | 1.03x |
| basic-float | 10.53 ms | 9.13 ms | 1.15x |
| basic-string | 20.37 ms | 17.53 ms | 1.16x |
| basic-as | 18.27 ms | 13.69 ms | 1.33x |
| basic-is | 16.28 ms | 18.31 ms | 0.89x |
| basic-new | 23.09 ms | 18.20 ms | 1.27x |
| basic-rawstring | 16.80 ms | 11.47 ms | 1.46x |
