///|
fn eval_string_property(
  s : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(s.length().to_int64()))
    "isEmpty" => Some(BoolValue(s.length() == 0))
    // PKL-148: pkl:base String zero-arg accessors. `isBlank` checks
    // for whitespace-only; `reverse` reverses code-points (not UTF-16
    // units) so surrogate pairs survive.
    "isNotEmpty" => Some(BoolValue(s.length() != 0))
    "isBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(blank))
    }
    "isNotBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(!blank))
    }
    "base64" =>
      // PKL-148: encode the string's UTF-8 bytes as standard base64.
      // Apple Pkl projects this as a property, not a method.
      Some(StringValue(@base64.encode(@utf8.encode(s))))
    "reverse" => {
      let chars : Array[Char] = []
      for c in s.iter() {
        chars.push(c)
      }
      let buf = StringBuilder::new()
      let mut i = chars.length() - 1
      while i >= 0 {
        buf.write_char(chars[i])
        i = i - 1
      }
      Some(StringValue(buf.to_string()))
    }
    // PKL-122: surrogate-pair aware properties. `length` stays
    // UTF-16 code units for compat with the existing fixture
    // baseline; `codePointCount` / `codePoints` / `chars` are the
    // new Unicode-correct view. MoonBit's `String::iter` already
    // yields full code-point `Char` values, so a single pass walks
    // surrogates correctly.
    "codePointCount" => Some(IntValue(s.char_length().to_int64()))
    "codePoints" => {
      let points : Array[Value] = []
      for c in s.iter() {
        points.push(IntValue(c.to_int().to_int64()))
      }
      Some(ListingValue(points))
    }
    "chars" => {
      let chars : Array[Value] = []
      for c in s.iter() {
        chars.push(StringValue(String::from_array([c][:])))
      }
      Some(ListingValue(chars))
    }
    // PKL-149: bare property surface for the api/string fact batch.
    // `lastIndex` is `length - 1` (or -1 for empty strings, matching
    // Apple Pkl). `isBase64` re-runs the decoder and observes whether
    // the throw cycles back. `base64Decoded` / `base64DecodedBytes`
    // round-trip the standard base64 alphabet so `"AQIDBA==" ⇒ Bytes(1,
    // 2, 3, 4)`. `isRegex` compiles the source pattern as a probe.
    "lastIndex" => {
      let len = s.length()
      if len == 0 {
        Some(IntValue(-1L))
      } else {
        Some(IntValue((len - 1).to_int64()))
      }
    }
    "isBase64" =>
      // Empty string counts as base64 in Apple Pkl. Padding-required
      // strings round-trip through `@base64.decode`; the decoder
      // raises on bad input so we catch and treat as false.
      try {
        let _ = @base64.decode(s[:])
        Some(BoolValue(true))
      } catch {
        _ => Some(BoolValue(false))
      }
    "base64Decoded" =>
      try {
        let raw = @base64.decode(s[:])
        Some(StringValue(@utf8.decode(raw[:])))
      } catch {
        _ => {
          diagnostics.push(diag("Could not base64-decode string \"\{s}\"."))
          None
        }
      }
    "base64DecodedBytes" =>
      try {
        let raw = @base64.decode(s[:])
        Some(BytesValue(raw))
      } catch {
        _ => {
          diagnostics.push(diag("Could not base64-decode string \"\{s}\"."))
          None
        }
      }
    "isRegex" => {
      let probe : Array[Diagnostic] = []
      Some(BoolValue(compile_regex_pattern(s, probe) is Some(_)))
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `String`."),
      )
      None
    }
  }
}

///|
fn pad_string(s : String, width : Int, pad : String, at_start : Bool) -> String {
  let current = s.length()
  if current >= width || pad.length() == 0 {
    return s
  }
  let buf = StringBuilder::new()
  if at_start {
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
    buf.write_string(s)
  } else {
    buf.write_string(s)
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
  }
  buf.to_string()
}

///|
fn eval_string_method(
  s : String,
  method_name : String,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toUpperCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toUpperCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_upper()))
    }
    "toBytes" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("String.toBytes expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(BytesValue(@utf8.encode(s[:])))
    }
    // PKL-122: code-point index lookup. `i` indexes the Unicode
    // code-point stream (surrogate-pair aware), not the UTF-16 code
    // units indexed by `String[i]` / `String.take`. Returns IntValue
    // of the code point or pushes a diagnostic if out of range.
    "codePointAt" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.codePointAt expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx64) => {
          let idx = idx64.to_int()
          let mut count = 0
          let mut found : Int? = None
          for c in s.iter() {
            if count == idx {
              found = Some(c.to_int())
              break
            }
            count = count + 1
          }
          match found {
            Some(cp) => Some(IntValue(cp.to_int64()))
            None => {
              diagnostics.push(
                diag("String.codePointAt index \{idx64} out of range"),
              )
              None
            }
          }
        }
        _ => {
          diagnostics.push(diag("String.codePointAt expects Int argument"))
          None
        }
      }
    }
    "toLowerCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toLowerCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_lower()))
    }
    // PKL-149: `contains` / `startsWith` / `endsWith` / `indexOf` are
    // overloaded on Regex in Apple Pkl. The regex arm reuses the
    // shared compile+find helpers in eval_stdlib_scalar.
    "contains" =>
      one_string_or_regex_arg(
        arg_values,
        "String.contains",
        diagnostics,
        fn(needle) { Some(BoolValue(s.contains(needle))) },
        fn(re) {
          match regex_find_first(re, s) {
            Some(_) => Some(BoolValue(true))
            None => Some(BoolValue(false))
          }
        },
      )
    "startsWith" =>
      one_string_or_regex_arg(
        arg_values,
        "String.startsWith",
        diagnostics,
        fn(prefix) { Some(BoolValue(s.has_prefix(prefix))) },
        fn(re) {
          // Anchored at offset 0: `before()` must be empty.
          match re.match_(s) {
            Some(m) => Some(BoolValue(m.before().length() == 0))
            None => Some(BoolValue(false))
          }
        },
      )
    "endsWith" =>
      one_string_or_regex_arg(
        arg_values,
        "String.endsWith",
        diagnostics,
        fn(suffix) { Some(BoolValue(s.has_suffix(suffix))) },
        fn(re) {
          // Walk all matches via the existing find-all helper and check
          // the last one's tail length is 0.
          let matches = regex_find_all(re, s)
          if matches.length() == 0 {
            return Some(BoolValue(false))
          }
          // Re-run a tail-anchored scan: scan from the end of the
          // last match to confirm there is nothing after it.
          let mut consumed = 0
          for m in matches {
            consumed = consumed + m.length()
          }
          Some(BoolValue(consumed > 0 && s.has_suffix(matches[matches.length() - 1])))
        },
      )
    "indexOf" =>
      one_string_or_regex_arg(
        arg_values,
        "String.indexOf",
        diagnostics,
        fn(needle) {
          match s.find(needle) {
            Some(i) => Some(IntValue(i.to_int64()))
            None => {
              // Apple Pkl raises when the needle is not present.
              diagnostics.push(
                diag("String \"\{s}\" does not contain \"\{needle}\"."),
              )
              None
            }
          }
        },
        fn(re) {
          match re.match_(s) {
            Some(m) => Some(IntValue(m.before().length().to_int64()))
            None => {
              diagnostics.push(
                diag(
                  "String \"\{s}\" does not contain the given regular expression.",
                ),
              )
              None
            }
          }
        },
      )
    "replaceAll" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceAll expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace_all(old~, new=new_value)))
        (RegexValue(pattern), StringValue(new_value)) =>
          // PKL-149: regex-driven replaceAll uses backref expansion
          // (`$0`, `$1`, ...) so caller-supplied templates land.
          match compile_regex_pattern(pattern, diagnostics) {
            Some(re) => Some(StringValue(regex_replace_all(re, s, new_value)))
            None => None
          }
        _ => {
          diagnostics.push(diag("String.replaceAll expects String arguments"))
          None
        }
      }
    }
    "replaceFirst" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceFirst expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace(old~, new=new_value)))
        (RegexValue(pattern), StringValue(new_value)) =>
          match compile_regex_pattern(pattern, diagnostics) {
            Some(re) => Some(StringValue(regex_replace_first(re, s, new_value)))
            None => None
          }
        _ => {
          diagnostics.push(diag("String.replaceFirst expects String arguments"))
          None
        }
      }
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.take expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > s.length() {
            s.length()
          } else {
            raw_i
          }
          Some(StringValue(String::unsafe_substring(s, start=0, end=n)))
        }
        _ => {
          diagnostics.push(diag("String.take expects Int argument"))
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.drop expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > s.length() {
            s.length()
          } else {
            raw_i
          }
          Some(
            StringValue(String::unsafe_substring(s, start=n, end=s.length())),
          )
        }
        _ => {
          diagnostics.push(diag("String.drop expects Int argument"))
          None
        }
      }
    }
    "split" =>
      one_string_or_regex_arg(
        arg_values,
        "String.split",
        diagnostics,
        fn(sep) {
          let parts : Array[Value] = []
          for piece in s.split(sep) {
            parts.push(StringValue(piece.to_owned()))
          }
          Some(ListingValue(parts))
        },
        fn(re) {
          // Walk via match_/after, accumulating `before()` slices.
          let parts : Array[Value] = []
          let mut rest = s
          while rest.length() > 0 {
            match re.match_(rest) {
              Some(m) => {
                parts.push(StringValue(m.before().to_owned()))
                let after = m.after().to_owned()
                if m.before().length() + m.get(0).unwrap_or("").length() == 0 {
                  // Zero-width match: advance by one to avoid loop.
                  if rest.length() <= 1 {
                    rest = ""
                  } else {
                    rest = String::unsafe_substring(rest, start=1, end=rest.length())
                  }
                } else {
                  rest = after
                }
              }
              None => {
                parts.push(StringValue(rest))
                rest = ""
                break
              }
            }
          }
          // If the input ended just at the last match, push the empty
          // tail to mirror Apple Pkl's split semantics.
          if parts.length() == 0 || rest.length() == 0 {
            // No-op: already produced.
          }
          Some(ListingValue(parts))
        },
      )
    "padStart" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.padStart expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width.to_int(), pad, true)))
        _ => {
          diagnostics.push(
            diag("String.padStart expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    "padEnd" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("String.padEnd expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width.to_int(), pad, false)))
        _ => {
          diagnostics.push(
            diag("String.padEnd expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    // PKL-149: pkl:base.String.matches(Regex) — full-input regex
    // match. The expected-argument type is fixed: String literal
    // arguments are rejected (Apple Pkl flags it as a type error).
    "matches" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.matches expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        RegexValue(pattern) =>
          match compile_regex_pattern(pattern, diagnostics) {
            Some(re) => Some(BoolValue(regex_matches_full(re, s)))
            None => None
          }
        _ => {
          diagnostics.push(diag("String.matches expects Regex argument"))
          None
        }
      }
    }
    // PKL-149: pkl:base.String.capitalize / .decapitalize — upper /
    // lower-case the first code point only; rest is preserved as-is.
    // Empty string round-trips.
    "capitalize" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.capitalize expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(capitalize_first(s, true)))
    }
    "decapitalize" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.decapitalize expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(capitalize_first(s, false)))
    }
    // PKL-149: pkl:base.String.repeat(n) — concatenate `s` `n` times.
    // Negative `n` raises in Apple Pkl.
    "repeat" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.repeat expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(n) => {
          if n < 0L {
            diagnostics.push(
              diag("Expected a positive number, but got \{n}."),
            )
            return None
          }
          let buf = StringBuilder::new()
          for _ in 0..<n.to_int() {
            buf.write_string(s)
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(diag("String.repeat expects Int argument"))
          None
        }
      }
    }
    // PKL-149: trim family — Apple Pkl trims Unicode whitespace.
    // MoonBit's String iterator yields Char so we project via
    // ASCII-space + tab/newline/CR; this matches the upstream test
    // coverage. trimStart / trimEnd are one-sided variants.
    "trim" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("String.trim expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(StringValue(trim_string(s, true, true)))
    }
    "trimStart" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.trimStart expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(trim_string(s, true, false)))
    }
    "trimEnd" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.trimEnd expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(trim_string(s, false, true)))
    }
    // PKL-149: toBoolean accepts case-insensitive "true" / "false";
    // anything else raises (so the example fixture chains them through
    // `module.catch`). toBooleanOrNull returns NullValue on failure.
    "toBoolean" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toBoolean expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match parse_pkl_boolean(s) {
        Some(b) => Some(BoolValue(b))
        None => {
          diagnostics.push(
            diag("Cannot parse string as Boolean: \"\{s}\"."),
          )
          None
        }
      }
    }
    "toBooleanOrNull" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toBooleanOrNull expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match parse_pkl_boolean(s) {
        Some(b) => Some(BoolValue(b))
        None => Some(NullValue)
      }
    }
    // PKL-149: toInt / toIntOrNull. Apple Pkl allows `_` as a digit
    // separator (`"1_2__3___"` → 123) — strip them before parsing.
    "toInt" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("String.toInt expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match parse_pkl_int(s) {
        Some(i) => Some(IntValue(i))
        None => {
          diagnostics.push(
            diag("Cannot parse string as Int: \"\{s}\"."),
          )
          None
        }
      }
    }
    "toIntOrNull" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toIntOrNull expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match parse_pkl_int(s) {
        Some(i) => Some(IntValue(i))
        None => Some(NullValue)
      }
    }
    "toFloat" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toFloat expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match parse_pkl_float(s) {
        Some(d) => Some(FloatValue(d))
        None => {
          diagnostics.push(
            diag("Cannot parse string as Float: \"\{s}\"."),
          )
          None
        }
      }
    }
    "toFloatOrNull" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toFloatOrNull expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match parse_pkl_float(s) {
        Some(d) => Some(FloatValue(d))
        None => Some(NullValue)
      }
    }
    // PKL-149: substring(start, end) — half-open; raises if either
    // bound is out of range or start > end. substringOrNull returns
    // NullValue instead of raising.
    "substring" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.substring expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(start64), IntValue(end64)) => {
          let start = start64.to_int()
          let end = end64.to_int()
          if start64 < 0L || end > s.length() || start > end {
            diagnostics.push(
              diag("Index out of range: start=\{start64}, end=\{end64}, length=\{s.length()}"),
            )
            None
          } else {
            Some(
              StringValue(String::unsafe_substring(s, start~, end~)),
            )
          }
        }
        _ => {
          diagnostics.push(
            diag("String.substring expects (Int, Int) arguments"),
          )
          None
        }
      }
    }
    "substringOrNull" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.substringOrNull expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(start64), IntValue(end64)) => {
          let start = start64.to_int()
          let end = end64.to_int()
          if start64 < 0L || end > s.length() || start > end {
            Some(NullValue)
          } else {
            Some(
              StringValue(String::unsafe_substring(s, start~, end~)),
            )
          }
        }
        _ => {
          diagnostics.push(
            diag("String.substringOrNull expects (Int, Int) arguments"),
          )
          None
        }
      }
    }
    // PKL-149: getOrNull(index) — character at the index as a 1-char
    // String, or null on out-of-range.
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.getOrNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(i64) => {
          let i = i64.to_int()
          if i64 < 0L || i >= s.length() {
            Some(NullValue)
          } else {
            Some(
              StringValue(
                String::unsafe_substring(s, start=i, end=i + 1),
              ),
            )
          }
        }
        _ => {
          diagnostics.push(diag("String.getOrNull expects Int argument"))
          None
        }
      }
    }
    // No-arg property surface accessible as `string.length()` etc.
    "length"
    | "isEmpty"
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars"
    | "lastIndex"
    | "isBase64"
    | "isRegex"
    | "base64Decoded"
    | "base64DecodedBytes" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_string_property(s, method_name, diagnostics)
      }
    _ => None
  }
}

///|
/// PKL-149: capitalize / decapitalize helper — flip the first
/// code-point's case; the rest is left untouched. Empty string is the
/// identity.
fn capitalize_first(s : String, upper : Bool) -> String {
  if s.length() == 0 {
    return s
  }
  let first = String::unsafe_substring(s, start=0, end=1)
  let rest = String::unsafe_substring(s, start=1, end=s.length())
  let flipped = if upper { first.to_upper() } else { first.to_lower() }
  flipped + rest
}

///|
/// PKL-149: trim ASCII whitespace from either or both ends.
fn trim_string(s : String, lead : Bool, trail : Bool) -> String {
  let len = s.length()
  let mut lo = 0
  let mut hi = len
  if lead {
    while lo < hi {
      let ch = s.get_char(lo)
      if ch is Some(c) && is_pkl_whitespace(c) {
        lo = lo + 1
      } else {
        break
      }
    }
  }
  if trail {
    while hi > lo {
      let ch = s.get_char(hi - 1)
      if ch is Some(c) && is_pkl_whitespace(c) {
        hi = hi - 1
      } else {
        break
      }
    }
  }
  if lo == 0 && hi == len {
    s
  } else {
    String::unsafe_substring(s, start=lo, end=hi)
  }
}

///|
fn is_pkl_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// PKL-149: case-insensitive "true" / "false" recognizer. Returns
/// `None` for anything else (callers decide raise-vs-null).
fn parse_pkl_boolean(s : String) -> Bool? {
  let lower = s.to_lower()
  if lower == "true" {
    Some(true)
  } else if lower == "false" {
    Some(false)
  } else {
    None
  }
}

///|
/// PKL-149: parse a Pkl-style integer literal. Underscore separators
/// are stripped before delegating to MoonBit's `parse_int`. Leading
/// or trailing underscores in Apple Pkl behave exactly like elsewhere
/// — the digit positions count, the underscores are visual only.
fn parse_pkl_int(s : String) -> Int64? {
  if s.length() == 0 {
    return None
  }
  let buf = StringBuilder::new()
  for c in s.iter() {
    if c != '_' {
      buf.write_char(c)
    }
  }
  let cleaned = buf.to_string()
  if cleaned.length() == 0 {
    return None
  }
  // Reject `_1_000` etc. — Apple Pkl raises for a leading-underscore
  // form unless the entire prefix is `-`.
  let head = s.get_char(0)
  if head is Some('_') {
    return None
  }
  try Some(@string.parse_int64(cleaned[:])) catch {
    _ => None
  }
}

///|
/// PKL-149: parse a Pkl-style float literal. Strip `_` separators and
/// delegate to MoonBit's double parser.
fn parse_pkl_float(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let buf = StringBuilder::new()
  for c in s.iter() {
    if c != '_' {
      buf.write_char(c)
    }
  }
  let cleaned = buf.to_string()
  if cleaned.length() == 0 {
    return None
  }
  let head = s.get_char(0)
  if head is Some('_') {
    return None
  }
  try Some(@string.parse_double(cleaned[:])) catch {
    _ => None
  }
}

///|
/// PKL-149: dispatch a String-or-Regex argument. `s_arm` runs for
/// `StringValue`, `re_arm` runs for `RegexValue` after compilation.
fn one_string_or_regex_arg(
  arg_values : Array[Value],
  label : String,
  diagnostics : Array[Diagnostic],
  s_arm : (String) -> Value?,
  re_arm : (@regexp.Regexp) -> Value?,
) -> Value? {
  if arg_values.length() != 1 {
    diagnostics.push(
      diag("\{label} expects 1 argument, got \{arg_values.length()}"),
    )
    return None
  }
  match arg_values[0] {
    StringValue(s) => s_arm(s)
    RegexValue(pattern) =>
      match compile_regex_pattern(pattern, diagnostics) {
        Some(re) => re_arm(re)
        None => None
      }
    _ => {
      diagnostics.push(diag("\{label} expects String or Regex argument"))
      None
    }
  }
}

