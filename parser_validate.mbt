///|
priv struct OpenDelimiter {
  kind : @cst.SyntaxKind
}

///|
fn parser_validation_diag(message : String, offset : Int) -> Diagnostic {
  { message, start: offset, end: offset }
}

///|
fn delimiter_name(kind : @cst.SyntaxKind) -> String {
  if kind == lparen() {
    ")"
  } else if kind == lbracket() {
    "]"
  } else {
    "}"
  }
}

///|
fn closes_delimiter(open : @cst.SyntaxKind, close : @cst.SyntaxKind) -> Bool {
  (open == lparen() && close == rparen()) ||
  (open == lbracket() && close == rbracket()) ||
  (open == lbrace() && close == rbrace())
}

///|
fn string_hash_count(text : String) -> Int {
  let mut count = 0
  while count < text.length() && text[count].to_int().unsafe_to_char() == '#' {
    count += 1
  }
  count
}

///|
fn string_has_raw_suffix(
  text : String,
  hash_count : Int,
  quote_count : Int,
) -> Bool {
  let suffix_len = hash_count + quote_count
  if text.length() < suffix_len {
    return false
  }
  let quote_start = text.length() - suffix_len
  for i = 0; i < quote_count; i = i + 1 {
    if text[quote_start + i].to_int().unsafe_to_char() != '"' {
      return false
    }
  }
  for i = 0; i < hash_count; i = i + 1 {
    if text[quote_start + quote_count + i].to_int().unsafe_to_char() != '#' {
      return false
    }
  }
  true
}

///|
fn validate_string_escape(
  text : String,
  start : Int,
  end : Int,
  base_offset : Int,
  allow_line_continuation : Bool,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let mut i = start
  while i < end {
    if text[i].to_int().unsafe_to_char() != '\\' {
      i += 1
      continue
    }
    if i + 1 >= end {
      diagnostics.push(
        parser_validation_diag(
          "Invalid line continuation escape sequence.",
          base_offset + i,
        ),
      )
      return
    }
    let next = text[i + 1].to_int().unsafe_to_char()
    if next == 'u' {
      if i + 2 >= end || text[i + 2].to_int().unsafe_to_char() != '{' {
        diagnostics.push(
          parser_validation_diag(
            "Invalid Unicode escape sequence.",
            base_offset + i,
          ),
        )
        return
      }
      let mut j = i + 3
      let mut digits = 0
      while j < end && text[j].to_int().unsafe_to_char() != '}' {
        let c = text[j].to_int().unsafe_to_char()
        if !is_hex_digit(c) {
          diagnostics.push(
            parser_validation_diag(
              "Invalid Unicode escape sequence.",
              base_offset + i,
            ),
          )
          return
        }
        digits += 1
        j += 1
      }
      if j >= end {
        diagnostics.push(
          parser_validation_diag(
            "Unterminated Unicode escape sequence.",
            base_offset + i,
          ),
        )
        return
      }
      if digits == 0 {
        diagnostics.push(
          parser_validation_diag(
            "Invalid Unicode escape sequence.",
            base_offset + i,
          ),
        )
        return
      }
      i = j + 1
      continue
    }
    if next == 'n' ||
      next == 'r' ||
      next == 't' ||
      next == '"' ||
      next == '\\' ||
      next == '(' ||
      (allow_line_continuation && next == '\n') {
      i += 2
      continue
    }
    diagnostics.push(
      parser_validation_diag(
        "Invalid character escape sequence `\\\{next}`.",
        base_offset + i,
      ),
    )
    return
  }
}

///|
fn validate_multiline_indent(
  text : String,
  content_start : Int,
  close_start : Int,
  base_offset : Int,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let mut closing_line_start = close_start
  while closing_line_start > content_start &&
        text[closing_line_start - 1].to_int().unsafe_to_char() != '\n' {
    closing_line_start -= 1
  }
  let indent_len = close_start - closing_line_start
  for i = closing_line_start; i < close_start; i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c != ' ' && c != '\t' {
      return
    }
  }
  let mut line_start = content_start
  if line_start < close_start &&
    text[line_start].to_int().unsafe_to_char() == '\n' {
    line_start += 1
  }
  while line_start < closing_line_start {
    let mut line_end = line_start
    while line_end < closing_line_start &&
          text[line_end].to_int().unsafe_to_char() != '\n' {
      line_end += 1
    }
    let mut non_blank = false
    for i = line_start; i < line_end; i = i + 1 {
      let c = text[i].to_int().unsafe_to_char()
      if c != ' ' && c != '\t' && c != '\r' {
        non_blank = true
        break
      }
    }
    if non_blank {
      if line_start + indent_len > line_end {
        diagnostics.push(
          parser_validation_diag(
            "Line must match or exceed indentation of the String's last line.",
            base_offset + line_start,
          ),
        )
        return
      }
      for i = 0; i < indent_len; i = i + 1 {
        if text[line_start + i] != text[closing_line_start + i] {
          diagnostics.push(
            parser_validation_diag(
              "Line must match or exceed indentation of the String's last line.",
              base_offset + line_start,
            ),
          )
          return
        }
      }
    }
    line_start = line_end + 1
  }
}

///|
fn validate_string_token(
  text : String,
  offset : Int,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let hashes = string_hash_count(text)
  let quote_start = hashes
  if quote_start >= text.length() ||
    text[quote_start].to_int().unsafe_to_char() != '"' {
    return
  }
  let multiline = quote_start + 2 < text.length() &&
    text[quote_start + 1].to_int().unsafe_to_char() == '"' &&
    text[quote_start + 2].to_int().unsafe_to_char() == '"'
  let quote_count = if multiline { 3 } else { 1 }
  if !string_has_raw_suffix(text, hashes, quote_count) ||
    text.length() < hashes * 2 + quote_count * 2 {
    let delimiter = if multiline { "\"\"\"" } else { "\"" }
    let raw_suffix = if hashes > 0 { "#" } else { "" }
    diagnostics.push(
      parser_validation_diag(
        "Missing `\{delimiter}\{raw_suffix}` delimiter.",
        offset + text.length(),
      ),
    )
    return
  }
  let content_start = quote_start + quote_count
  let close_start = text.length() - hashes - quote_count
  if hashes == 0 {
    validate_string_escape(
      text, content_start, close_start, offset, multiline, diagnostics,
    )
  }
  if multiline {
    validate_multiline_indent(
      text, content_start, close_start, offset, diagnostics,
    )
  }
}

///|
fn invalid_numeric_separator(text : String) -> Bool {
  if text.has_prefix("0x_") ||
    text.has_prefix("0X_") ||
    text.has_prefix("0b_") ||
    text.has_prefix("0B_") ||
    text.has_prefix("0o_") ||
    text.has_prefix("0O_") {
    return true
  }
  false
}

///|
fn next_significant_token(tokens : Array[Token], start : Int) -> Token? {
  for i = start; i < tokens.length(); i = i + 1 {
    if !is_trivia(tokens[i].kind()) {
      return Some(tokens[i])
    }
  }
  None
}

///|
fn current_scope_is_paren(delimiters : Array[OpenDelimiter]) -> Bool {
  delimiters.length() > 0 &&
  delimiters[delimiters.length() - 1].kind == lparen()
}

///|
fn value_end_kind(kind : @cst.SyntaxKind) -> Bool {
  kind == identifier() ||
  kind == int_token() ||
  kind == float_token() ||
  kind == string_token() ||
  kind == true_kw() ||
  kind == false_kw() ||
  kind == null_kw()
}

///|
fn value_start_kind(kind : @cst.SyntaxKind) -> Bool {
  kind == identifier() ||
  kind == int_token() ||
  kind == float_token() ||
  kind == string_token() ||
  kind == true_kw() ||
  kind == false_kw() ||
  kind == null_kw()
}

///|
fn type_default_marker_counts(
  tokens : Array[Token],
  marker_index : Int,
) -> (Int, Int) {
  let mut start = marker_index
  while start > 0 {
    start -= 1
    let kind = tokens[start].kind()
    if kind == colon() {
      break
    }
    if kind == eq() ||
      kind == arrow() ||
      kind == newline() ||
      kind == semicolon() {
      return (0, 0)
    }
  }
  if tokens[start].kind() != colon() {
    return (0, 0)
  }
  let mut defaults = 0
  let mut unions = 0
  let mut depth = 0
  let mut marker_depth = 0
  for i = start + 1; i < marker_index; i = i + 1 {
    if tokens[i].kind() == lparen() {
      marker_depth += 1
    } else if tokens[i].kind() == rparen() {
      marker_depth -= 1
    }
  }
  for i = start + 1; i < tokens.length(); i = i + 1 {
    let kind = tokens[i].kind()
    if kind == eq() ||
      kind == arrow() ||
      kind == newline() ||
      kind == semicolon() ||
      kind == eof() {
      break
    }
    if kind == lparen() {
      depth += 1
    } else if kind == rparen() {
      depth -= 1
    } else if kind == star() && depth == marker_depth {
      defaults += 1
    } else if kind == pipe() && depth == marker_depth {
      unions += 1
    }
  }
  (defaults, unions)
}

///|
fn doc_comment_error(
  tokens : Array[Token],
  token_index : Int,
  offset : Int,
  previous_significant : Token?,
  saw_line_separator : Bool,
) -> Diagnostic? {
  if !tokens[token_index].text().has_prefix("///") {
    return None
  }
  if previous_significant is Some(_) && !saw_line_separator {
    return Some(
      parser_validation_diag("Dangling documentation comment.", offset),
    )
  }
  match next_significant_token(tokens, token_index + 1) {
    Some(next_token) if next_token.kind() == import_kw() =>
      return Some(
        parser_validation_diag(
          "Imports cannot have doc comments, annotations or modifiers.", offset,
        ),
      )
    None =>
      return Some(
        parser_validation_diag("Dangling documentation comment.", offset),
      )
    Some(next_token) if next_token.kind() == eof() =>
      return Some(
        parser_validation_diag("Dangling documentation comment.", offset),
      )
    _ => ()
  }
  let mut newlines = 0
  for i = token_index + 1; i < tokens.length(); i = i + 1 {
    let token = tokens[i]
    if token.kind() == newline() {
      newlines += 1
    } else if token.kind() == whitespace() {
      ()
    } else if token.kind() == comment() && token.text().has_prefix("///") {
      if newlines > 1 {
        return Some(
          parser_validation_diag("Dangling documentation comment.", offset),
        )
      }
      break
    } else {
      break
    }
  }
  None
}

///|
fn allows_top_level_identifier_sequence(first : String) -> Bool {
  first == "@" ||
  first == "class" ||
  first == "typealias" ||
  first == "function" ||
  first == "abstract" ||
  first == "open" ||
  first == "external" ||
  first == "extends" ||
  first == "amends" ||
  first == "hidden" ||
  first == "fixed" ||
  first == "const" ||
  first == "local"
}

///|
fn brace_follows_new_type(tokens : Array[Token], brace_index : Int) -> Bool {
  let mut i = brace_index
  while i > 0 {
    i -= 1
    let kind = tokens[i].kind()
    if is_trivia(kind) {
      continue
    }
    if kind == new_kw() {
      return true
    }
    if kind != identifier() &&
      kind != dot() &&
      kind != pipe() &&
      kind != string_token() &&
      kind != star() {
      return false
    }
  }
  false
}

///|
fn validate_parser_syntax(
  source : String,
  tokens : Array[Token],
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let delimiters : Array[OpenDelimiter] = []
  let mut offset = 0
  let mut previous_significant : Token? = None
  let mut previous_previous_significant : Token? = None
  let mut previous_significant_end = -1
  let mut saw_line_separator = true
  let mut line_first_significant = ""
  let mut newlines_since_significant = 0
  for token_index = 0
      token_index < tokens.length()
      token_index = token_index + 1 {
    let token = tokens[token_index]
    let kind = token.kind()
    let text = token.text()
    if kind == eof() {
      break
    }
    if kind == newline() || kind == semicolon() {
      saw_line_separator = true
      if kind == newline() {
        newlines_since_significant += 1
      }
    }
    if kind == comment() {
      match
        doc_comment_error(
          tokens, token_index, offset, previous_significant, saw_line_separator,
        ) {
        Some(error) => diagnostics.push(error)
        None => ()
      }
    } else if kind == error_kind() {
      diagnostics.push(
        parser_validation_diag("Invalid token `\{text}`.", offset),
      )
    } else if kind == string_token() {
      validate_string_token(text, offset, diagnostics)
      match previous_significant {
        Some(previous) if previous.kind() == string_token() &&
          previous_significant_end == offset =>
          diagnostics.push(
            parser_validation_diag("Unexpected string literal.", offset),
          )
        _ => ()
      }
      match previous_significant {
        Some(previous) if previous.kind() == import_kw() &&
          text.find("\\(") is Some(_) =>
          diagnostics.push(
            parser_validation_diag(
              "String constant cannot have interpolated values.", offset,
            ),
          )
        _ => ()
      }
    } else if kind == identifier() {
      let next = next_significant_token(tokens, token_index + 1)
      let next_kind = match next {
        Some(next_token) => next_token.kind()
        None => eof()
      }
      let at_module_level = delimiters.length() == 0
      let follows_dot = match previous_significant {
        Some(previous) => previous.kind() == dot()
        None => false
      }
      let is_forbidden_keyword = if text == "outer" {
        follows_dot ||
        (at_module_level && (next_kind == eq() || next_kind == lparen()))
      } else if text == "record" {
        at_module_level && next_kind == eq()
      } else if text == "_" {
        at_module_level && next_kind == eq()
      } else {
        false
      }
      let previous_is_identifier = match previous_significant {
        Some(previous) => previous.kind() == identifier()
        None => false
      }
      if at_module_level &&
        !saw_line_separator &&
        previous_is_identifier &&
        !allows_top_level_identifier_sequence(line_first_significant) {
        diagnostics.push(
          parser_validation_diag("Invalid token at module level.", offset),
        )
      }
      if is_forbidden_keyword {
        diagnostics.push(
          parser_validation_diag(
            "Keyword `\{text}` is not allowed here.",
            offset,
          ),
        )
      } else if text.has_prefix("`") &&
        (text.length() < 2 || !text.has_suffix("`")) {
        diagnostics.push(
          parser_validation_diag(
            "Missing ``` delimiter.",
            offset + text.length(),
          ),
        )
      }
      match previous_significant {
        Some(previous) if (
            previous.kind() == int_token() || previous.kind() == float_token()
          ) &&
          (text.has_prefix("e_") || text.has_prefix("E_")) =>
          diagnostics.push(
            parser_validation_diag(
              "Unexpected separator character.",
              offset + 1,
            ),
          )
        _ => ()
      }
      let separator_after_dot = match
        (previous_previous_significant, previous_significant) {
        (Some(number), Some(dot_token)) =>
          (number.kind() == int_token() || number.kind() == float_token()) &&
          dot_token.kind() == dot() &&
          text.has_prefix("_")
        _ => false
      }
      if separator_after_dot {
        diagnostics.push(
          parser_validation_diag("Unexpected separator character.", offset),
        )
      }
      let previous_is_value = match previous_significant {
        Some(previous) => value_end_kind(previous.kind())
        None => false
      }
      let adjacent_without_comma = !saw_line_separator &&
        current_scope_is_paren(delimiters) &&
        previous_is_value
      let function_amend_without_comma = !saw_line_separator &&
        next_kind == arrow() &&
        previous_is_identifier
      if adjacent_without_comma || function_amend_without_comma {
        diagnostics.push(parser_validation_diag("Expected `,` or `)`.", offset))
      }
    } else if value_start_kind(kind) {
      if (kind == int_token() || kind == float_token()) &&
        invalid_numeric_separator(text) {
        diagnostics.push(
          parser_validation_diag("Unexpected separator character.", offset),
        )
      }
      let previous_is_value = match previous_significant {
        Some(previous) => value_end_kind(previous.kind())
        None => false
      }
      let adjacent_without_comma = !saw_line_separator &&
        current_scope_is_paren(delimiters) &&
        previous_is_value
      if adjacent_without_comma {
        diagnostics.push(parser_validation_diag("Expected `,` or `)`.", offset))
      }
    }
    if kind == at_sign() {
      let next_kind = match next_significant_token(tokens, token_index + 1) {
        Some(next_token) => next_token.kind()
        None => eof()
      }
      if next_kind != identifier() {
        diagnostics.push(
          parser_validation_diag("Expected an annotation class.", offset),
        )
      }
    }
    if kind == pipe() {
      let annotation_union = match
        (previous_previous_significant, previous_significant) {
        (Some(at_token), Some(name_token)) =>
          at_token.kind() == at_sign() && name_token.kind() == identifier()
        _ => false
      }
      if annotation_union {
        diagnostics.push(
          parser_validation_diag("Expected an annotation class.", offset),
        )
      }
    }
    if kind == star() {
      let (defaults, unions) = type_default_marker_counts(tokens, token_index)
      if defaults > 1 {
        diagnostics.push(
          parser_validation_diag(
            "A type union cannot have more than one default type.", offset,
          ),
        )
      } else if defaults == 1 && unions == 0 {
        diagnostics.push(
          parser_validation_diag(
            "Only type unions can have a default marker (*).", offset,
          ),
        )
      }
    }
    if kind == rparen() {
      let next_kind = match next_significant_token(tokens, token_index + 1) {
        Some(next_token) => next_token.kind()
        None => eof()
      }
      let empty_type = match
        (previous_previous_significant, previous_significant) {
        (Some(before_open), Some(open)) =>
          open.kind() == lparen() &&
          (before_open.kind() == pipe() || before_open.kind() == colon()) &&
          next_kind != arrow()
        _ => false
      }
      if empty_type {
        diagnostics.push(parser_validation_diag("Expected a type.", offset))
      }
    }
    if kind == rbracket() {
      let spaced_predicate_close = match previous_significant {
        Some(previous) =>
          previous.kind() == rbracket() && previous_significant_end != offset
        None => false
      }
      if spaced_predicate_close {
        diagnostics.push(
          parser_validation_diag("Expected adjacent `]]` delimiter.", offset),
        )
      }
    }
    if kind == lbrace() {
      let inside_parens = delimiters.length() > 0 &&
        delimiters[delimiters.length() - 1].kind == lparen()
      let follows_name = match previous_significant {
        Some(previous) => previous.kind() == identifier()
        None => false
      }
      if inside_parens &&
        follows_name &&
        !brace_follows_new_type(tokens, token_index) {
        diagnostics.push(
          parser_validation_diag(
            "Amend expressions used inside parentheses require a parenthesized base.",
            offset,
          ),
        )
      }
      let mut scan = token_index
      let mut saw_colon = false
      let mut saw_eq = false
      let mut reverse_paren_depth = 0
      while scan > 0 {
        scan -= 1
        let scan_kind = tokens[scan].kind()
        if reverse_paren_depth == 0 &&
          (
            scan_kind == newline() ||
            scan_kind == semicolon() ||
            scan_kind == lbrace() ||
            scan_kind == rbrace()
          ) {
          break
        }
        if scan_kind == rparen() {
          reverse_paren_depth += 1
        } else if scan_kind == lparen() {
          if reverse_paren_depth > 0 {
            reverse_paren_depth -= 1
          }
        } else if scan_kind == colon() && reverse_paren_depth == 0 {
          saw_colon = true
        } else if scan_kind == eq() && reverse_paren_depth == 0 {
          saw_eq = true
        }
      }
      if saw_colon && !saw_eq && !brace_follows_new_type(tokens, token_index) {
        diagnostics.push(
          parser_validation_diag(
            "Properties with type annotations cannot have object bodies.", offset,
          ),
        )
      }
    }
    if kind == minus() &&
      delimiters.length() == 0 &&
      newlines_since_significant > 1 {
      let previous_is_value = match previous_significant {
        Some(previous) => value_end_kind(previous.kind())
        None => false
      }
      if previous_is_value {
        diagnostics.push(
          parser_validation_diag(
            "Binary operators cannot continue after a blank line.", offset,
          ),
        )
      }
    }
    if kind == lparen() || kind == lbracket() || kind == lbrace() {
      delimiters.push({ kind, })
    } else if kind == rparen() || kind == rbracket() || kind == rbrace() {
      if delimiters.length() == 0 {
        diagnostics.push(
          parser_validation_diag(
            "Unexpected closing delimiter `\{text}`.",
            offset,
          ),
        )
      } else {
        let last = delimiters[delimiters.length() - 1]
        if closes_delimiter(last.kind, kind) {
          ignore(delimiters.pop())
        } else {
          diagnostics.push(
            parser_validation_diag(
              "Unexpected closing delimiter `\{text}`.",
              offset,
            ),
          )
          ignore(delimiters.pop())
        }
      }
    }
    if !is_trivia(kind) {
      if saw_line_separator || line_first_significant == "" {
        line_first_significant = text
      }
      previous_previous_significant = previous_significant
      previous_significant = Some(token)
      previous_significant_end = offset + text.length()
      saw_line_separator = false
      newlines_since_significant = 0
    }
    offset += text.length()
  }
  for delimiter in delimiters {
    diagnostics.push(
      parser_validation_diag(
        "Missing `\{delimiter_name(delimiter.kind)}` delimiter.",
        source.length(),
      ),
    )
  }
  diagnostics
}
