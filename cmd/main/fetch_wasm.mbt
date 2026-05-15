// PKL-129: HTTP fetch stub for the WASM target. WASI support is the
// follow-up — until then, fetching a URI from WASM prints an error
// rather than calling into an HTTP client that doesn't exist on this
// target.

///|
pub async fn fetch_uri(url : String) -> String? {
  // Reference @http so the per-target import set stays consistent
  // even though the WASM stub never actually calls into it.
  if false {
    let _ = @http.get(url)
  }
  println(
    "https / package imports require --target native or js (got WASM): \{url}",
  )
  None
}
