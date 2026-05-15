// PKL-129: HTTP fetch wrapper for URI imports on the native target.
// `main` is `async fn main`, so we can await `@http.get` directly.

///|
/// Fetch the body of `url` over HTTP / HTTPS. Returns the decoded body
/// on success, `None` on failure (with the message printed to stdout
/// so the caller's `fail` path surfaces an unambiguous diagnostic).
pub async fn fetch_uri(url : String) -> String? {
  try {
    let (resp, body) = @http.get(url)
    if resp.code < 200 || resp.code >= 300 {
      println("http \{resp.code} \{resp.reason} fetching \{url}")
      None
    } else {
      Some(body.text())
    }
  } catch {
    e => {
      println("http fetch failed: \{e}")
      None
    }
  }
}
