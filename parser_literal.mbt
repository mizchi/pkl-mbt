///|
fn parse_int_text(text : String) -> Int64 {
  // PKL-147: Apple Pkl integer literals come in four shapes:
  //   1. decimal `123`, with optional `_` separators (`1_000_000`),
  //   2. hex `0xFF_FF` / `0X1A`,
  //   3. binary `0b1010` / `0B1010`,
  //   4. octal `0o17` / `0O17`.
  // PKL-150: accumulate in Int64 so 64-bit literals like
  // `0xFFFF_FFFF_FFFF_FFFF` / `9_223_372_036_854_775_807` round-trip
  // without truncation.
  let len = text.length()
  if len >= 2 && text[0].to_int().unsafe_to_char() == '0' {
    let prefix = text[1].to_int().unsafe_to_char()
    if prefix == 'x' || prefix == 'X' {
      let mut value : Int64 = 0L
      for i = 2; i < len; i = i + 1 {
        let c = text[i].to_int().unsafe_to_char()
        if c == '_' {
          continue
        }
        let d = if c >= '0' && c <= '9' {
          c.to_int() - '0'.to_int()
        } else if c >= 'a' && c <= 'f' {
          c.to_int() - 'a'.to_int() + 10
        } else if c >= 'A' && c <= 'F' {
          c.to_int() - 'A'.to_int() + 10
        } else {
          continue
        }
        value = value * 16L + d.to_int64()
      }
      return value
    }
    if prefix == 'b' || prefix == 'B' {
      let mut value : Int64 = 0L
      for i = 2; i < len; i = i + 1 {
        let c = text[i].to_int().unsafe_to_char()
        if c == '0' || c == '1' {
          value = value * 2L + (c.to_int() - '0'.to_int()).to_int64()
        }
      }
      return value
    }
    if prefix == 'o' || prefix == 'O' {
      let mut value : Int64 = 0L
      for i = 2; i < len; i = i + 1 {
        let c = text[i].to_int().unsafe_to_char()
        if c >= '0' && c <= '7' {
          value = value * 8L + (c.to_int() - '0'.to_int()).to_int64()
        }
      }
      return value
    }
  }
  let mut value : Int64 = 0L
  for i = 0; i < len; i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
  }
  value
}

///|
fn parse_float_text(text : String) -> Double {
  // PKL-092: parse `<int>.<frac>` into a Double by accumulating the
  // integer and fractional parts separately. PKL-128: also handle
  // scientific notation (`1e10`, `2.5e-3`, `4E+8`) — split at the
  // exponent marker, parse the mantissa, then multiply by 10^exp.
  // The lexer guarantees a digit+ exponent so the trailing parse can
  // assume a non-empty signed integer.
  let mut exp_idx = -1
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == 'e' || c == 'E' {
      exp_idx = i
      break
    }
  }
  let mantissa_text = if exp_idx >= 0 {
    String::unsafe_substring(text, start=0, end=exp_idx)
  } else {
    text
  }
  let mut int_part = 0.0
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  let mut in_fraction = false
  for i = 0; i < mantissa_text.length(); i = i + 1 {
    let c = mantissa_text[i].to_int().unsafe_to_char()
    if c == '.' {
      in_fraction = true
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_double()
      if in_fraction {
        frac_scale = frac_scale * 10.0
        frac_part = frac_part + digit / frac_scale
      } else {
        int_part = int_part * 10.0 + digit
      }
    }
  }
  let mantissa = int_part + frac_part
  if exp_idx < 0 {
    return mantissa
  }
  let mut exp_start = exp_idx + 1
  let mut exp_sign = 1.0
  if exp_start < text.length() {
    let sign_char = text[exp_start].to_int().unsafe_to_char()
    if sign_char == '+' {
      exp_start = exp_start + 1
    } else if sign_char == '-' {
      exp_sign = -1.0
      exp_start = exp_start + 1
    }
  }
  let mut exp_value = 0.0
  for i = exp_start; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      exp_value = exp_value * 10.0 + (c.to_int() - '0'.to_int()).to_double()
    }
  }
  let mut power = 1.0
  let mut steps = 0.0
  while steps < exp_value {
    power = power * 10.0
    steps = steps + 1.0
  }
  if exp_sign > 0.0 {
    mantissa * power
  } else {
    mantissa / power
  }
}

///|
/// PKL-128: build either a plain `StringLiteral` or an
/// `InterpolatedString` from a raw quoted string token. Splits the
/// inner text at `\(...)` boundaries (balanced parens, escape-aware)
/// and parses each `\(...)` content as a Pkl expression. Strings with
/// no interpolation segments collapse back to a plain `StringLiteral`.
fn parse_string_literal_text(text : String) -> Expr {
  // PKL-148an / PKL-148ao: raw string literal `<N #s>"..."<N #s>`
  // (single-line) or `<N #s>"""..."""<N #s>` (heredoc). The lexer
  // pairs a leading run of `#`s with the same count on the close.
  // Strip both runs + the opening / closing quotes, then assemble
  // the inner text through `assemble_string_parts` with the same
  // hash count — escape sequences (`\n`, `\t`, etc.) stay verbatim
  // in raw form, and only the `\<N #>(expr)` marker (with matching
  // hash count) opens an interpolation segment. Heredoc indent
  // stripping still applies — Apple Pkl drops the leading newline
  // and the closing delimiter's indentation in raw heredocs the
  // same way it does for the non-raw form.
  if text.length() >= 2 && text.has_prefix("#") {
    let mut hash_count = 0
    while hash_count < text.length() &&
          text[hash_count].to_int().unsafe_to_char() == '#' {
      hash_count = hash_count + 1
    }
    if hash_count >= 1 &&
      hash_count + 1 <= text.length() &&
      text[hash_count].to_int().unsafe_to_char() == '"' {
      let is_heredoc = text.length() >= hash_count * 2 + 6 &&
        hash_count + 2 < text.length() &&
        text[hash_count + 1].to_int().unsafe_to_char() == '"' &&
        text[hash_count + 2].to_int().unsafe_to_char() == '"'
      let inner = if is_heredoc {
        strip_heredoc_indent(
          String::unsafe_substring(
            text,
            start=hash_count + 3,
            end=text.length() - hash_count - 3,
          ),
        )
      } else {
        String::unsafe_substring(
          text,
          start=hash_count + 1,
          end=text.length() - hash_count - 1,
        )
      }
      return assemble_string_parts(inner, hash_count)
    }
  }
  // Strip the surrounding quotes (if present) but track the inner text
  // so escape sequences and interpolations can be split independently.
  // PKL-128: a triple-quoted heredoc (`"""..."""`) strips its leading
  // newline and the closing delimiter's indentation from each line
  // before the regular escape / interpolation processing kicks in.
  let inner = if text.length() >= 6 &&
    text.has_prefix("\"\"\"") &&
    text.has_suffix("\"\"\"") {
    strip_heredoc_indent(
      String::unsafe_substring(text, start=3, end=text.length() - 3),
    )
  } else if text.length() >= 2 &&
    text[0].to_int().unsafe_to_char() == '"' &&
    text[text.length() - 1].to_int().unsafe_to_char() == '"' {
    String::unsafe_substring(text, start=1, end=text.length() - 1)
  } else {
    text
  }
  assemble_string_parts(inner, 0)
}

///|
/// PKL-148ao: detect a string-literal start at `start` and return the
/// index just past its closing delimiter. Returns `start` unchanged
/// when no string literal begins here. Handles four shapes:
///
/// - `"..."` (single-line non-raw): scans to the matching `"` skipping
///   `\<any>` escape pairs so a `\"` inside doesn't close the string
///   prematurely.
/// - `"""..."""` (heredoc non-raw): scans to the matching `"""`.
/// - `<N #>"..."<N #>` (single-line raw): scans to a `"` followed by
///   exactly `hash_count` `#`s.
/// - `<N #>"""..."""<N #>` (heredoc raw): scans to `"""` followed by
///   `hash_count` `#`s.
///
/// Used by the interpolation walker in `assemble_string_parts` so a
/// `\#(<expr that contains a "..." or #"..."# arg>)` segment is sliced
/// at the correct closing `)` instead of being cut short by a `)` that
/// happens to live inside a nested string literal.
fn skip_string_at(s : String, start : Int) -> Int {
  if start >= s.length() {
    return start
  }
  let c = s[start].to_int().unsafe_to_char()
  let mut hash_count = 0
  let mut quote_pos = start
  if c == '#' {
    while quote_pos < s.length() &&
          s[quote_pos].to_int().unsafe_to_char() == '#' {
      hash_count = hash_count + 1
      quote_pos = quote_pos + 1
    }
    if quote_pos >= s.length() || s[quote_pos].to_int().unsafe_to_char() != '"' {
      return start
    }
  } else if c != '"' {
    return start
  }
  let is_heredoc = quote_pos + 2 < s.length() &&
    s[quote_pos + 1].to_int().unsafe_to_char() == '"' &&
    s[quote_pos + 2].to_int().unsafe_to_char() == '"'
  if is_heredoc {
    let mut p = quote_pos + 3
    while p + 2 + hash_count < s.length() {
      if s[p].to_int().unsafe_to_char() == '"' &&
        s[p + 1].to_int().unsafe_to_char() == '"' &&
        s[p + 2].to_int().unsafe_to_char() == '"' {
        let mut ok = true
        for h = 0; h < hash_count; h = h + 1 {
          if s[p + 3 + h].to_int().unsafe_to_char() != '#' {
            ok = false
            break
          }
        }
        if ok {
          return p + 3 + hash_count
        }
      }
      p = p + 1
    }
    return s.length()
  }
  let mut p = quote_pos + 1
  while p < s.length() {
    let ch = s[p].to_int().unsafe_to_char()
    if hash_count == 0 && ch == '\\' && p + 1 < s.length() {
      // Non-raw escape — skip the two-char sequence so `\"` doesn't
      // close the string here.
      p = p + 2
      continue
    }
    if ch == '"' {
      if hash_count == 0 {
        return p + 1
      }
      let mut ok = true
      for h = 0; h < hash_count; h = h + 1 {
        if p + 1 + h >= s.length() ||
          s[p + 1 + h].to_int().unsafe_to_char() != '#' {
          ok = false
          break
        }
      }
      if ok {
        return p + 1 + hash_count
      }
    }
    if ch == '\n' {
      // Unterminated single-line string — bail at the newline so the
      // outer walker can resume.
      return p
    }
    p = p + 1
  }
  s.length()
}

///|
/// PKL-148ao: walk a string literal's inner body and split it into
/// `StringLiteral` / interpolation `Expr` segments. `hash_count`
/// controls both the interpolation marker shape and the literal-
/// segment decoding:
///
/// - `hash_count == 0` (non-raw): `\(expr)` opens an interpolation
///   segment; literal segments run through `decode_string_escapes`
///   so the standard `\n` / `\t` / `\u{...}` escapes resolve.
/// - `hash_count >= 1` (raw): the marker is `\<hash_count #>(expr)` —
///   the `\` followed by exactly `hash_count` `#`s and an opening
///   `(`. Inside a raw string the regular `\n` / `\t` escapes stay
///   verbatim (no decoding), but interpolation still works through
///   the hashed marker.
///
/// The function returns a single `StringLiteral` when no interpolation
/// fires, or `InterpolatedString(parts)` when at least one segment
/// was lifted into an expression.
fn assemble_string_parts(inner : String, hash_count : Int) -> Expr {
  let is_raw = hash_count > 0
  let decode = fn(s : String) -> String {
    if is_raw {
      s
    } else {
      decode_string_escapes(s)
    }
  }
  let parts : Array[Expr] = []
  let buf = StringBuilder::new()
  let mut buf_has_content = false
  let mut i = 0
  while i < inner.length() {
    let c = inner[i].to_int().unsafe_to_char()
    // PKL-148ao: in raw mode (`hash_count > 0`), the `\<N #>X` form
    // re-enables escape decoding for X (`\#t` → tab, `\#n` → newline,
    // `\##u{61}` → `a`, etc.). The hash count must match exactly; a
    // `\#t` inside a `##"..."##` literal is still verbatim. The
    // marker is detected by reading the hash run after `\`; if `X` is
    // `(`, the marker arm below handles it as interpolation. For
    // every other recognised escape char we decode and emit, then
    // skip past the escape sequence.
    if is_raw && c == '\\' && i + 1 + hash_count < inner.length() {
      let mut hashes_ok = true
      for h = 0; h < hash_count; h = h + 1 {
        if inner[i + 1 + h].to_int().unsafe_to_char() != '#' {
          hashes_ok = false
          break
        }
      }
      if hashes_ok {
        let escape_char = inner[i + 1 + hash_count].to_int().unsafe_to_char()
        if escape_char != '(' {
          // Decode the escape inline and emit the resolved char(s).
          // Reuse `decode_string_escapes` by feeding it the equivalent
          // non-raw escape (`\#t` → `\t`); the helper already knows
          // every Apple-Pkl escape including `\u{...}`.
          let consumed = if escape_char == 'u' &&
            i + 2 + hash_count < inner.length() &&
            inner[i + 2 + hash_count].to_int().unsafe_to_char() == '{' {
            let mut k = i + 3 + hash_count
            while k < inner.length() &&
                  inner[k].to_int().unsafe_to_char() != '}' {
              k = k + 1
            }
            if k < inner.length() {
              k + 1 - i
            } else {
              inner.length() - i
            }
          } else {
            2 + hash_count
          }
          let escape_payload = String::unsafe_substring(
            inner,
            start=i + 1 + hash_count,
            end=i + consumed,
          )
          let resolved = decode_string_escapes("\\" + escape_payload)
          buf.write_string(resolved)
          buf_has_content = true
          i = i + consumed
          continue
        }
      }
    }
    // Detect interpolation marker: `\` + `hash_count` `#`s + `(`.
    let mut marker = false
    if c == '\\' && i + 1 + hash_count < inner.length() {
      let mut hashes_ok = true
      for h = 0; h < hash_count; h = h + 1 {
        if inner[i + 1 + h].to_int().unsafe_to_char() != '#' {
          hashes_ok = false
          break
        }
      }
      if hashes_ok && inner[i + 1 + hash_count].to_int().unsafe_to_char() == '(' {
        marker = true
      }
    }
    if marker {
      if buf_has_content {
        parts.push(StringLiteral(decode(buf.to_string())))
        buf.reset()
        buf_has_content = false
      }
      let open_paren = i + 1 + hash_count
      let mut depth = 1
      let mut j = open_paren + 1
      while j < inner.length() && depth > 0 {
        let cc = inner[j].to_int().unsafe_to_char()
        // PKL-148ao: skip the entire content of any string literal we
        // encounter so embedded `(` / `)` inside a nested string don't
        // disturb the balanced-paren count. Handles single-line raw
        // (`<N #>"..."<N #>`), heredoc raw (`<N #>"""..."""<N #>`),
        // non-raw (`"..."`), and non-raw heredoc (`"""..."""`). The
        // outer hash count is independent — a `#"..."#` argument inside
        // a `\#(...)` segment is still recognised verbatim because the
        // skip walker only consumes balanced delimiters.
        let skipped = skip_string_at(inner, j)
        if skipped > j {
          j = skipped
          continue
        }
        if cc == '(' {
          depth = depth + 1
        } else if cc == ')' {
          depth = depth - 1
          if depth == 0 {
            break
          }
        }
        j = j + 1
      }
      let segment = String::unsafe_substring(inner, start=open_paren + 1, end=j)
      let parsed = parse_source(segment)
      let expr = match parsed.program.body {
        Some(body_expr) => body_expr
        None =>
          if parsed.program.bindings.length() > 0 {
            parsed.program.bindings[parsed.program.bindings.length() - 1].value
          } else {
            ErrorExpr("empty interpolation")
          }
      }
      parts.push(expr)
      i = j + 1
    } else if c == '\\' && !is_raw && i + 1 < inner.length() {
      // Regular escape in a non-raw string — accumulate the two-char
      // sequence so the eventual `decode_string_escapes` call resolves
      // it. In raw strings we fall through to the generic char branch
      // because escapes are verbatim.
      buf.write_char(c)
      buf.write_char(inner[i + 1].to_int().unsafe_to_char())
      buf_has_content = true
      i = i + 2
    } else {
      buf.write_char(c)
      buf_has_content = true
      i = i + 1
    }
  }
  if buf_has_content {
    parts.push(StringLiteral(decode(buf.to_string())))
  }
  if parts.length() == 0 {
    return StringLiteral("")
  }
  if parts.length() == 1 {
    match parts[0] {
      StringLiteral(_) as plain => return plain
      _ => ()
    }
  }
  InterpolatedString(parts)
}

///|
/// PKL-128: dedent a triple-quoted heredoc body.
///
/// Apple Pkl's `"""<newline>...<indent>"""` removes the leading newline
/// and trims the indentation of the closing delimiter from every line.
/// The body passed here is the raw content between the opening and
/// closing `"""` markers; the result is the content with the leading
/// newline stripped and each line's `closing_indent` prefix removed.
fn strip_heredoc_indent(body : String) -> String {
  let mut start = 0
  // Strip a single leading newline (`"""<lf>`).
  if start < body.length() {
    let c = body[start].to_int().unsafe_to_char()
    if c == '\n' {
      start = start + 1
    } else if c == '\r' &&
      start + 1 < body.length() &&
      body[start + 1].to_int().unsafe_to_char() == '\n' {
      start = start + 2
    }
  }
  // Find the indentation immediately before the trailing close. The
  // close marker has already been stripped, so the indent we want is
  // the run of horizontal whitespace at the very end of `body`.
  let mut indent_start = body.length()
  while indent_start > start {
    let c = body[indent_start - 1].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      indent_start = indent_start - 1
    } else {
      break
    }
  }
  let indent_len = body.length() - indent_start
  let indent = String::unsafe_substring(
    body,
    start=indent_start,
    end=body.length(),
  )
  // PKL-148e: Apple Pkl treats the newline immediately preceding the
  // closing delimiter's own line as the line terminator for that line
  // and strips it from the content. Without this, `"""<nl>x<nl>"""`
  // (and indented variants) carry a stray trailing `\n` that breaks
  // gold-match for fixtures like `basic/identifier`.
  let mut body_end = indent_start
  if body_end > start {
    let c = body[body_end - 1].to_int().unsafe_to_char()
    if c == '\n' {
      body_end = body_end - 1
      if body_end > start &&
        body[body_end - 1].to_int().unsafe_to_char() == '\r' {
        body_end = body_end - 1
      }
    }
  }
  // Walk each line, strip the indent prefix when present.
  let buf = StringBuilder::new()
  let mut i = start
  let mut at_line_start = true
  while i < body_end {
    if at_line_start && indent_len > 0 && i + indent_len <= body_end {
      let candidate = String::unsafe_substring(
        body,
        start=i,
        end=i + indent_len,
      )
      if candidate == indent {
        i = i + indent_len
        at_line_start = false
        continue
      }
    }
    let c = body[i].to_int().unsafe_to_char()
    buf.write_char(c)
    at_line_start = c == '\n'
    i = i + 1
  }
  buf.to_string()
}

///|
fn unquote(text : String) -> String {
  let mut hash_count = 0
  while hash_count < text.length() &&
        text[hash_count].to_int().unsafe_to_char() == '#' {
    hash_count = hash_count + 1
  }
  if hash_count > 0 &&
    hash_count + 1 <= text.length() &&
    text[hash_count].to_int().unsafe_to_char() == '"' {
    let suffix_len = hash_count + 1
    if text.length() >= hash_count + suffix_len {
      let quote_end = text.length() - hash_count - 1
      if quote_end >= hash_count &&
        text[quote_end].to_int().unsafe_to_char() == '"' {
        return String::unsafe_substring(
          text,
          start=hash_count + 1,
          end=quote_end,
        )
      }
    }
  }
  if text.length() >= 2 && text[0].to_int().unsafe_to_char() == '"' {
    let end = text.length() - 1
    if text[end].to_int().unsafe_to_char() == '"' {
      let inner = String::unsafe_substring(text, start=1, end~)
      if inner.find("\\") is None {
        return inner
      }
      return decode_string_escapes(inner)
    }
  }
  text
}

///|
fn decode_string_escapes(text : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    let c = text[i].to_int().unsafe_to_char()
    if c == '\\' && i + 1 < text.length() {
      let next = text[i + 1].to_int().unsafe_to_char()
      // PKL-148ao: `\u{HHHH}` unicode escape — read hex digits up to
      // the matching `}` and emit the resulting code point. Used by
      // both non-raw strings (`"\u{1F920}"`) and raw strings through
      // the `\<N #>u{...}` form (decoded inline before reaching here).
      if next == 'u' &&
        i + 2 < text.length() &&
        text[i + 2].to_int().unsafe_to_char() == '{' {
        let mut j = i + 3
        let mut code = 0
        while j < text.length() {
          let ch = text[j].to_int().unsafe_to_char()
          if ch == '}' {
            break
          }
          let digit = if ch >= '0' && ch <= '9' {
            ch.to_int() - '0'.to_int()
          } else if ch >= 'a' && ch <= 'f' {
            ch.to_int() - 'a'.to_int() + 10
          } else if ch >= 'A' && ch <= 'F' {
            ch.to_int() - 'A'.to_int() + 10
          } else {
            -1
          }
          if digit < 0 {
            break
          }
          code = code * 16 + digit
          j = j + 1
        }
        if j < text.length() && text[j].to_int().unsafe_to_char() == '}' {
          buf.write_char(code.unsafe_to_char())
          i = j + 1
          continue
        }
      }
      // PKL-148bb: `\<newline>` is a heredoc line continuation — Apple
      // Pkl drops both the backslash and the following newline so the
      // surrounding lines join (`basic/stringMultilineContinuation`).
      // Skip the `\r\n` variant too.
      if next == '\n' {
        i += 2
        continue
      }
      if next == '\r' &&
        i + 2 < text.length() &&
        text[i + 2].to_int().unsafe_to_char() == '\n' {
        i += 3
        continue
      }
      match next {
        'n' => buf.write_char('\n')
        't' => buf.write_char('\t')
        'r' => buf.write_char('\r')
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        _ => buf.write_char(next)
      }
      i += 2
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  buf.to_string()
}

///|
fn import_alias_from_uri(uri : String) -> String {
  let without_scheme = match uri.find(":") {
    Some(idx) => String::unsafe_substring(uri, start=idx + 1, end=uri.length())
    None => uri
  }
  let base = match without_scheme.rev_find("/") {
    Some(idx) =>
      String::unsafe_substring(
        without_scheme,
        start=idx + 1,
        end=without_scheme.length(),
      )
    None => without_scheme
  }
  if base.has_suffix(".pkl") {
    String::unsafe_substring(base, start=0, end=base.length() - 4)
  } else {
    base
  }
}

///|
pub fn parse_source(source : String) -> ParseResult {
  Parser::new(source).parse()
}
