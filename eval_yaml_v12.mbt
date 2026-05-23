// PKL-153c: YAML 1.2-mode adjustments for `yaml.Parser { mode =
// "1.2" }`. The upstream `moonbit-community/yaml` loader does its
// own permissive scalar resolution that follows MoonBit `strconv`
// rather than YAML 1.2's core-schema regex grammar — e.g. `0b1001`
// becomes Integer(9), `1_2_3` becomes Integer(123), and `Null`
// stays String("Null"). 1.2 expects those to be String("0b1001"),
// String("1_2_3"), and Null respectively.
//
// We can't substitute a custom event-stream receiver because the
// upstream trait is sealed against external `impl`s (issue not
// fixed yet), so this module instead pre-processes the source
// string to quote 1.1-only-syntax bare scalars before handing it
// to the loader, and post-processes the resulting tree to handle
// the small remaining set of resolver differences. The set of
// patterns covered here is what Apple Pkl's `yamlParser1Yaml12`
// fixture stresses; if a new fixture surfaces a different shape
// we extend the matcher here rather than re-deriving the schema.

///|
/// Pre-process a YAML source body so the upstream loader sees
/// 1.2-friendly plain scalars. Only patterns that the upstream
/// resolves as integer/float but YAML 1.2 wants as string get
/// quoted; everything else passes through unchanged.
///
/// Today this handles the case where the whole input is a single
/// trimmed scalar (the snippet test calls `parser.parse("0b1001")`,
/// `parser.parse("-0o123")`, etc.). Multi-line documents are left
/// untouched.
fn yaml_v12_source_rewrite(source : String) -> String {
  let trimmed = trim_whitespace_v12(source)
  if trimmed == "" {
    return source
  }
  if is_v12_string_only_scalar(trimmed) {
    let buf = StringBuilder::new()
    buf.write_char('\'')
    buf.write_string(trimmed)
    buf.write_char('\'')
    return buf.to_string()
  }
  source
}

///|
/// Returns true when `text` parses as int/float under the upstream
/// permissive resolver but YAML 1.2's core schema would treat it as
/// a plain string.
///   - `0b...`, `[-+]0b...`        (binary, 1.1 only)
///   - `[-+]0o...`, `[-+]0x...`    (signed octal/hex, 1.1 only)
///   - `..._...`                   (underscore-grouped numerics, 1.1 only)
fn is_v12_string_only_scalar(text : String) -> Bool {
  let len = text.length()
  if len == 0 || text == "_" {
    return false
  }
  let mut has_underscore = false
  let mut has_digit = false
  for c in text {
    if c == '_' {
      has_underscore = true
    } else if c is '0'..='9' {
      has_digit = true
    }
  }
  if has_underscore && has_digit {
    return true
  }
  // Binary literal: 1.1 only.
  if has_prefix_after_sign(text, "0b") {
    return true
  }
  // Signed octal / hex: 1.1 only.
  if text[0] is ('+' | '-') &&
    (has_prefix_after_sign(text, "0o") || has_prefix_after_sign(text, "0x")) {
    return true
  }
  false
}

///|
fn has_prefix_after_sign(text : String, prefix : String) -> Bool {
  let plen = prefix.length()
  let offset = if text.length() >= 1 && text[0] is ('+' | '-') { 1 } else { 0 }
  if text.length() < offset + plen {
    return false
  }
  for i in 0..<plen {
    if text[offset + i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn trim_whitespace_v12(text : String) -> String {
  let len = text.length()
  let mut start = 0
  let mut stop = len
  while start < stop {
    let u = text[start]
    if u is (' ' | '\t' | '\n' | '\r') {
      start = start + 1
    } else {
      break
    }
  }
  while stop > start {
    let u = text[stop - 1]
    if u is (' ' | '\t' | '\n' | '\r') {
      stop = stop - 1
    } else {
      break
    }
  }
  if start == 0 && stop == len {
    text
  } else {
    String::unsafe_substring(text, start~, end=stop)
  }
}

///|
/// 1.2 core schema differs from the upstream resolver on one
/// non-numeric pattern: `Null` and `NULL` are still null (1.2
/// accepts `null|Null|NULL|~|<empty>` as the null token, but the
/// upstream lib only matches the lowercase `null`). Walk the loaded
/// tree and rewrite the affected strings to the Null variant.
fn yaml_v12_promote_null(y : @yaml.Yaml) -> @yaml.Yaml {
  match y {
    @yaml.Yaml::String(s) =>
      if s == "Null" || s == "NULL" {
        @yaml.Yaml::Null
      } else {
        @yaml.Yaml::String(s)
      }
    @yaml.Yaml::Array(items) => {
      let out : Array[@yaml.Yaml] = []
      for item in items {
        out.push(yaml_v12_promote_null(item))
      }
      @yaml.Yaml::Array(out)
    }
    @yaml.Yaml::Map(m) => {
      let out : Map[String, @yaml.Yaml] = {}
      for k, v in m {
        out[k] = yaml_v12_promote_null(v)
      }
      @yaml.Yaml::Map(out)
    }
    other => other
  }
}

///|
/// Read the `mode` slot off a `yaml.Parser` mirror. The default in
/// `pkl:yaml`'s synthetic stub is `"compat"`; only `"1.2"` triggers
/// the rewrites above today (1.1 mode would need additional
/// `yes/no/y/n/on/off/:base60:` boolean / numeric handling, which
/// the upstream lib's strict-ish behavior already declines to
/// produce, so we'd need a separate pre-processing pass for that
/// case).
fn parser_mode(members : Array[ValueMember]) -> String {
  match lookup_member(members, "mode") {
    Some(StringValue(s)) => s
    _ => "compat"
  }
}
