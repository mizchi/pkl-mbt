# Apple Pkl vs mpkl benchmark

- tag: `post-firstchar-dispatch`
- date: 2026-05-22T13:18:13Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:18:05 2026) at `0272ead-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 8.3 ± 4.4 | 4.3 | 20.0 | 1.90 ± 1.01 |
| `pkl:micro` | 7.6 ± 1.3 | 6.4 | 12.9 | 1.73 ± 0.29 |
| `mpkl:amend-base` | 4.4 ± 0.1 | 4.2 | 4.7 | 1.00 |
| `pkl:amend-base` | 7.9 ± 1.1 | 7.3 | 13.0 | 1.81 ± 0.25 |
| `mpkl:map-value` | 5.0 ± 0.3 | 4.7 | 5.6 | 1.15 ± 0.07 |
| `pkl:map-value` | 7.2 ± 0.3 | 6.6 | 7.9 | 1.65 ± 0.09 |
| `mpkl:set-value` | 4.9 ± 0.8 | 4.4 | 8.8 | 1.13 ± 0.19 |
| `pkl:set-value` | 7.3 ± 0.4 | 6.8 | 8.3 | 1.68 ± 0.11 |
| `mpkl:int-seq` | 4.5 ± 0.3 | 4.2 | 5.8 | 1.02 ± 0.08 |
| `pkl:int-seq` | 8.2 ± 1.7 | 6.8 | 15.4 | 1.86 ± 0.38 |
| `mpkl:basic-int` | 9.6 ± 0.9 | 8.2 | 11.9 | 2.20 ± 0.22 |
| `pkl:basic-int` | 11.8 ± 3.8 | 8.2 | 23.7 | 2.69 ± 0.87 |
| `mpkl:basic-float` | 7.8 ± 0.1 | 7.6 | 8.2 | 1.79 ± 0.06 |
| `pkl:basic-float` | 9.4 ± 1.7 | 8.0 | 14.3 | 2.16 ± 0.39 |
| `mpkl:basic-string` | 13.0 ± 2.2 | 9.5 | 21.0 | 2.97 ± 0.52 |
| `pkl:basic-string` | 9.4 ± 0.7 | 7.9 | 11.3 | 2.14 ± 0.18 |
| `mpkl:basic-as` | 11.5 ± 1.2 | 9.5 | 14.9 | 2.63 ± 0.29 |
| `pkl:basic-as` | 9.1 ± 0.5 | 8.3 | 10.0 | 2.08 ± 0.13 |
| `mpkl:basic-is` | 13.0 ± 1.3 | 10.5 | 17.3 | 2.98 ± 0.31 |
| `pkl:basic-is` | 8.8 ± 2.7 | 7.1 | 19.3 | 2.01 ± 0.63 |
| `mpkl:basic-new` | 10.4 ± 1.6 | 9.4 | 14.4 | 2.39 ± 0.37 |
| `pkl:basic-new` | 8.6 ± 0.3 | 8.2 | 9.2 | 1.96 ± 0.09 |
| `mpkl:basic-rawstring` | 11.3 ± 1.8 | 9.7 | 16.1 | 2.58 ± 0.43 |
| `pkl:basic-rawstring` | 6.9 ± 0.2 | 6.5 | 7.5 | 1.58 ± 0.07 |
| `mpkl:pkspec-test-schema` | 21.5 ± 1.2 | 20.7 | 26.7 | 4.90 ± 0.32 |
| `pkl:pkspec-test-schema` | 8.8 ± 0.4 | 8.4 | 9.9 | 2.02 ± 0.11 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 8.32 ms | 7.56 ms | 1.10x |
| amend-base | 4.38 ms | 7.91 ms | 0.55x |
| map-value | 5.04 ms | 7.21 ms | 0.70x |
| set-value | 4.93 ms | 7.34 ms | 0.67x |
| int-seq | 4.48 ms | 8.15 ms | 0.55x |
| basic-int | 9.61 ms | 11.78 ms | 0.82x |
| basic-float | 7.84 ms | 9.45 ms | 0.83x |
| basic-string | 13.00 ms | 9.39 ms | 1.38x |
| basic-as | 11.51 ms | 9.10 ms | 1.27x |
| basic-is | 13.05 ms | 8.79 ms | 1.48x |
| basic-new | 10.44 ms | 8.57 ms | 1.22x |
| basic-rawstring | 11.27 ms | 6.90 ms | 1.63x |
| pkspec-test-schema | 21.47 ms | 8.85 ms | 2.43x |
