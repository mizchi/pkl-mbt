// PKL-129: HTTP fetch wrapper for URI imports on the native target.
// `main` is `async fn main`, so we can await `@http.get` directly.

///|
/// Fetch the body of `url` over HTTP / HTTPS. Returns the decoded body
/// on success, `None` on failure (with the message printed to stdout
/// so the caller's `fail` path surfaces an unambiguous diagnostic).
///
/// PKL-129b1: follow up to 5 redirects (301 / 302 / 303 / 307 / 308).
/// `pkg.pkl-lang.org` returns 301 redirects to a CDN host before
/// serving the metadata JSON, so without redirect-following the
/// registry probe always fails. The 5-hop cap matches `curl`'s
/// default and prevents loops.
pub async fn fetch_uri(url : String) -> String? {
  let mut current = url
  let mut remaining = 5
  while remaining > 0 {
    try {
      let (resp, body) = @http.get(current)
      if resp.code >= 300 && resp.code < 400 {
        match resp.headers.get("location") {
          Some(next) => {
            current = next
            remaining = remaining - 1
            continue
          }
          None =>
            match resp.headers.get("Location") {
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
      if resp.code >= 300 && resp.code < 400 {
        match resp.headers.get("location") {
          Some(next) => {
            current = next
            remaining = remaining - 1
            continue
          }
          None =>
            match resp.headers.get("Location") {
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
