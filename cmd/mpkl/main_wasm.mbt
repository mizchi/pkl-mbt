// PKL-142: WASM build placeholder for the `mpkl` CLI. The async
// runtime that `main.mbt` depends on (`moonbitlang/async`'s
// `run_async_main`) is `#cfg(target="native"|"js")` only, so the
// full CLI surface isn't reachable from WebAssembly today.
//
// Why ship this stub at all: moon insists on a `main` function for
// every `is-main: true` package, and we want `moon build --target
// wasm-gc` (and `--target wasm`) to succeed at the workspace level
// so library consumers don't trip over CLI-only breakage. The stub
// prints a one-line redirect and exits.
//
// Library consumers should depend on `mizchi/pkl` directly — the
// `@pkl` package itself builds clean on all four targets (native /
// js / wasm / wasm-gc), no IO, no async.

///|
fn main {
  // Reference each package alias declared in `moon.pkg` so the
  // per-package `unused_package` warning doesn't trip `--deny-warn`
  // on wasm. `ignore` doesn't call these — they exist purely to
  // satisfy the import-usage check. The same packages are actually
  // exercised by main.mbt on native / js.
  ignore(@pkl.parse_source)
  ignore(@fs.path_exists)
  ignore(@sys.exit)
  let _http_ref : @http.Response? = None
  ignore(_http_ref)
  ignore(@async.now)
  println(
    "mpkl CLI is not available on wasm / wasm-gc targets — embed the `mizchi/pkl` library instead.",
  )
}
