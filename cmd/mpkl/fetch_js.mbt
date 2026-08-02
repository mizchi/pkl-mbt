// PKL-129: HTTP fetch wrapper for the JS target. `mizchi/x/http`
// supplies a Node.js / browser `fetch`-backed `get` implementation,
// so the JS target resolves `https://` imports too.
//
// `main` runs as `async fn main` so the call site can await
// `@http.get` directly; the wrapper just captures the body / errors
// into an `Option` return.

///|
pub async fn fetch_uri(url : String) -> String? {
  let mut current = url
  let mut remaining = 5
  while remaining > 0 {
    try {
      let (resp, body) = @http.get(current)
      if is_http_redirect(resp.code) {
        match resp.headers.get("location") {
          Some(next) => {
            current = next
            remaining = remaining - 1
            continue
          }
          None => {
            println(
              "http \{resp.code} \{resp.reason} fetching \{current} (no Location header)",
            )
            return None
          }
        }
      }
      if resp.code < 200 || resp.code >= 300 {
        println("http \{resp.code} \{resp.reason} fetching \{current}")
        return None
      }
      return Some(body.text())
    } catch {
      e => {
        println("http fetch failed: \{e}")
        return None
      }
    }
  }
  println("http fetch failed: too many redirects (last url: \{current})")
  None
}

///|
pub async fn fetch_uri_bytes(url : String) -> Bytes? {
  let mut current = url
  let mut remaining = 5
  while remaining > 0 {
    try {
      let (resp, body) = @http.get(current)
      if is_http_redirect(resp.code) {
        match resp.headers.get("location") {
          Some(next) => {
            current = next
            remaining = remaining - 1
            continue
          }
          None => {
            println(
              "http \{resp.code} \{resp.reason} fetching \{current} (no Location header)",
            )
            return None
          }
        }
      }
      if resp.code < 200 || resp.code >= 300 {
        println("http \{resp.code} \{resp.reason} fetching \{current}")
        return None
      }
      return Some(body.binary())
    } catch {
      e => {
        println("http fetch failed: \{e}")
        return None
      }
    }
  }
  println("http fetch failed: too many redirects (last url: \{current})")
  None
}
