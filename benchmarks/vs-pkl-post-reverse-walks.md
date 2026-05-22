# Apple Pkl vs mpkl benchmark

- tag: `post-reverse-walks`
- date: 2026-05-22T13:00:17Z
- host: `Darwin 25.4.0 arm64`
- pkl: `Pkl 0.31.1 (macOS 26.2, native)`
- mpkl: `mpkl.exe` (built May 22 22:00:08 2026) at `d48f5e3-dirty`
- hyperfine: `hyperfine 1.20.0` (warmup=5, runs=25)

## Pairwise results

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `mpkl:micro` | 8.3 ± 1.8 | 5.8 | 12.1 | 1.55 ± 0.38 |
| `pkl:micro` | 11.5 ± 2.5 | 7.3 | 17.0 | 2.13 ± 0.53 |
| `mpkl:amend-base` | 5.4 ± 0.6 | 4.5 | 6.8 | 1.00 |
| `pkl:amend-base` | 11.0 ± 2.5 | 7.4 | 15.2 | 2.04 ± 0.53 |
| `mpkl:map-value` | 7.4 ± 1.3 | 5.4 | 9.9 | 1.37 ± 0.29 |
| `pkl:map-value` | 10.9 ± 2.3 | 7.7 | 15.7 | 2.03 ± 0.50 |
| `mpkl:set-value` | 5.8 ± 0.9 | 4.9 | 8.5 | 1.07 ± 0.21 |
| `pkl:set-value` | 10.3 ± 2.0 | 7.6 | 14.7 | 1.92 ± 0.44 |
| `mpkl:int-seq` | 5.4 ± 0.9 | 4.7 | 8.2 | 1.01 ± 0.21 |
| `pkl:int-seq` | 9.9 ± 1.5 | 7.6 | 13.6 | 1.85 ± 0.36 |
| `mpkl:basic-int` | 10.5 ± 2.1 | 8.3 | 17.8 | 1.96 ± 0.46 |
| `pkl:basic-int` | 11.4 ± 2.0 | 8.9 | 16.1 | 2.11 ± 0.45 |
| `mpkl:basic-float` | 10.8 ± 2.1 | 8.4 | 15.8 | 2.02 ± 0.46 |
| `pkl:basic-float` | 9.9 ± 2.1 | 8.1 | 18.3 | 1.84 ± 0.45 |
| `mpkl:basic-string` | 13.7 ± 3.4 | 10.2 | 24.8 | 2.55 ± 0.69 |
| `pkl:basic-string` | 11.3 ± 1.3 | 9.4 | 14.1 | 2.11 ± 0.35 |
| `mpkl:basic-as` | 17.4 ± 4.9 | 9.9 | 29.3 | 3.24 ± 0.99 |
| `pkl:basic-as` | 11.2 ± 1.6 | 9.1 | 14.4 | 2.09 ± 0.38 |
| `mpkl:basic-is` | 14.4 ± 3.0 | 10.8 | 20.6 | 2.67 ± 0.65 |
| `pkl:basic-is` | 11.3 ± 3.6 | 8.3 | 25.8 | 2.11 ± 0.71 |
| `mpkl:basic-new` | 13.0 ± 2.2 | 10.6 | 19.4 | 2.42 ± 0.50 |
| `pkl:basic-new` | 11.4 ± 0.8 | 10.4 | 13.8 | 2.12 ± 0.30 |
| `mpkl:basic-rawstring` | 15.5 ± 3.0 | 10.5 | 21.6 | 2.88 ± 0.66 |
| `pkl:basic-rawstring` | 9.3 ± 2.1 | 7.1 | 17.2 | 1.74 ± 0.44 |
| `mpkl:pkspec-test-schema` | 26.7 ± 2.6 | 23.7 | 32.2 | 4.96 ± 0.77 |
| `pkl:pkspec-test-schema` | 11.0 ± 0.9 | 9.0 | 13.2 | 2.05 ± 0.30 |

## Ratio (mpkl / pkl) — lower is better for mpkl

| fixture | mpkl mean | pkl mean | mpkl/pkl |
| --- | ---: | ---: | ---: |
| micro | 8.34 ms | 11.48 ms | 0.73x |
| amend-base | 5.38 ms | 10.99 ms | 0.49x |
| map-value | 7.37 ms | 10.90 ms | 0.68x |
| set-value | 5.78 ms | 10.31 ms | 0.56x |
| int-seq | 5.40 ms | 9.94 ms | 0.54x |
| basic-int | 10.54 ms | 11.36 ms | 0.93x |
| basic-float | 10.84 ms | 9.89 ms | 1.10x |
| basic-string | 13.73 ms | 11.34 ms | 1.21x |
| basic-as | 17.43 ms | 11.24 ms | 1.55x |
| basic-is | 14.35 ms | 11.33 ms | 1.27x |
| basic-new | 12.99 ms | 11.39 ms | 1.14x |
| basic-rawstring | 15.51 ms | 9.34 ms | 1.66x |
| pkspec-test-schema | 26.69 ms | 11.01 ms | 2.42x |
