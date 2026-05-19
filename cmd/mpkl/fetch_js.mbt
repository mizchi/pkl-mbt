// PKL-129: HTTP fetch wrapper for the JS target. `mizchi/x/http`
// supplies a Node.js / browser `fetch`-backed `get` implementation,
// so the JS target resolves `https://` imports too.
//
// `main` runs as `async fn main` so the call site can await
// `@http.get` directly; the wrapper just captures the body / errors
// into an `Option` return.

///|
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

///|
pub async fn fetch_uri_bytes(url : String) -> Bytes? {
  try {
    let (resp, body) = @http.get(url)
    if resp.code < 200 || resp.code >= 300 {
      println("http \{resp.code} \{resp.reason} fetching \{url}")
      None
    } else {
      Some(body.binary())
    }
  } catch {
    e => {
      println("http fetch failed: \{e}")
      None
    }
  }
}
