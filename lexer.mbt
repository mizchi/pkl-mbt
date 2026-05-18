///|
priv struct Token {
  kind : @cst.SyntaxKind
  text : String
}

///|
fn Token::new(kind : @cst.SyntaxKind, text : String) -> Token {
  Token::{ kind, text }
}

///|
fn Token::kind(self : Token) -> @cst.SyntaxKind {
  self.kind
}

///|
fn Token::text(self : Token) -> String {
  self.text
}

///|
priv struct Lexer {
  input : String
  len : Int
  mut pos : Int
}

///|
fn Lexer::new(input : String) -> Lexer {
  Lexer::{ input, len: input.length(), pos: 0 }
}

///|
fn Lexer::char_at(self : Lexer, index : Int) -> Char {
  self.input[index].to_int().unsafe_to_char()
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex_digit(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn is_octal_digit(c : Char) -> Bool {
  c >= '0' && c <= '7'
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn is_horizontal_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
fn Lexer::slice_from(self : Lexer, start : Int) -> String {
  String::unsafe_substring(self.input, start~, end=self.pos)
}

///|
fn keyword_or_identifier(text : String) -> @cst.SyntaxKind {
  match text {
    "let" => let_kw()
    "true" => true_kw()
    "false" => false_kw()
    "null" => null_kw()
    "module" => module_kw()
    "new" => new_kw()
    "import" => import_kw()
    "as" => as_kw()
    "local" => local_kw()
    "if" => if_kw()
    "else" => else_kw()
    "is" => is_kw()
    "when" => when_kw()
    "for" => for_kw()
    "in" => in_kw()
    _ => identifier()
  }
}

///|
fn Lexer::next_token(self : Lexer) -> Token {
  if self.pos >= self.len {
    return Token::new(eof(), "")
  }
  let start = self.pos
  let c = self.char_at(start)
  // PKL-148p: a shebang preamble (`#!...`) at module start is consumed
  // as a comment trivia so the parser sees it the same way as `//...`.
  // Apple Pkl's `pkl eval` strips the shebang line silently — without
  // this branch the `#` would surface as `unsupported expression` and
  // `syntax/shebang.pkl` (`#!/usr/bin/env pkl eval` + body) would fail
  // before reaching `foo = 1`.
  if start == 0 &&
    c == '#' &&
    self.pos + 1 < self.len &&
    self.char_at(self.pos + 1) == '!' {
    self.pos += 2
    while self.pos < self.len && self.char_at(self.pos) != '\n' {
      self.pos += 1
    }
    return Token::new(comment(), self.slice_from(start))
  }
  if is_horizontal_space(c) {
    self.pos += 1
    while self.pos < self.len && is_horizontal_space(self.char_at(self.pos)) {
      self.pos += 1
    }
    return Token::new(whitespace(), self.slice_from(start))
  }
  if c == '\n' {
    self.pos += 1
    return Token::new(newline(), "\n")
  }
  if c == '/' && self.pos + 1 < self.len {
    let next = self.char_at(self.pos + 1)
    if next == '/' {
      self.pos += 2
      while self.pos < self.len && self.char_at(self.pos) != '\n' {
        self.pos += 1
      }
      return Token::new(comment(), self.slice_from(start))
    }
    if next == '*' {
      self.pos += 2
      while self.pos < self.len {
        if self.char_at(self.pos) == '*' &&
          self.pos + 1 < self.len &&
          self.char_at(self.pos + 1) == '/' {
          self.pos += 2
          return Token::new(comment(), self.slice_from(start))
        }
        self.pos += 1
      }
      return Token::new(comment(), self.slice_from(start))
    }
  }
  if is_alpha(c) {
    self.pos += 1
    while self.pos < self.len && is_alnum(self.char_at(self.pos)) {
      self.pos += 1
    }
    let text = self.slice_from(start)
    return Token::new(keyword_or_identifier(text), text)
  }
  // PKL-148e: a `.` immediately followed by a digit lexes as a
  // leading-dot Float (`.3` → `0.3`). Member access `foo.bar` requires
  // an identifier after the dot, so `.<digit>` is unambiguous here.
  if c == '.' && self.pos + 1 < self.len && is_digit(self.char_at(self.pos + 1)) {
    self.pos += 1
    while self.pos < self.len &&
          (is_digit(self.char_at(self.pos)) || self.char_at(self.pos) == '_') {
      self.pos += 1
    }
    if self.pos < self.len {
      let exp_char = self.char_at(self.pos)
      if exp_char == 'e' || exp_char == 'E' {
        let mut probe = self.pos + 1
        if probe < self.len &&
          (self.char_at(probe) == '+' || self.char_at(probe) == '-') {
          probe = probe + 1
        }
        if probe < self.len && is_digit(self.char_at(probe)) {
          self.pos = probe
          while self.pos < self.len && is_digit(self.char_at(self.pos)) {
            self.pos += 1
          }
        }
      }
    }
    return Token::new(float_token(), self.slice_from(start))
  }
  if is_digit(c) {
    self.pos += 1
    // PKL-147: Apple Pkl integer literals support `0x` / `0b` / `0o`
    // base prefixes plus `_` digit separators (`0xFF_FF`, `0b1010`,
    // `1_000_000`). Detect the prefix immediately after a leading `0`
    // and consume the base-specific digit run. Without this branch the
    // lexer splits `0xABC` into `0` + identifier `xABC`, which surfaces
    // as a spurious parse error inside snippetTest fixtures.
    if c == '0' && self.pos < self.len {
      let next = self.char_at(self.pos)
      if next == 'x' || next == 'X' {
        self.pos += 1
        while self.pos < self.len &&
              (
                is_hex_digit(self.char_at(self.pos)) ||
                self.char_at(self.pos) == '_'
              ) {
          self.pos += 1
        }
        return Token::new(int_token(), self.slice_from(start))
      }
      if next == 'b' || next == 'B' {
        self.pos += 1
        while self.pos < self.len &&
              (
                self.char_at(self.pos) == '0' ||
                self.char_at(self.pos) == '1' ||
                self.char_at(self.pos) == '_'
              ) {
          self.pos += 1
        }
        return Token::new(int_token(), self.slice_from(start))
      }
      if next == 'o' || next == 'O' {
        self.pos += 1
        while self.pos < self.len &&
              (
                is_octal_digit(self.char_at(self.pos)) ||
                self.char_at(self.pos) == '_'
              ) {
          self.pos += 1
        }
        return Token::new(int_token(), self.slice_from(start))
      }
    }
    while self.pos < self.len &&
          (is_digit(self.char_at(self.pos)) || self.char_at(self.pos) == '_') {
      self.pos += 1
    }
    // PKL-092: a `.digit` immediately after the integer run promotes the
    // token to a Float literal. The Duration / DataSize unit shorthand
    // (`1.h`, `5.min`) stays an Int because the character after `.` is
    // an identifier, not a digit, so the dispatch below keeps the
    // existing magnitude-+-unit path intact.
    let mut is_float = false
    if self.pos + 1 < self.len &&
      self.char_at(self.pos) == '.' &&
      is_digit(self.char_at(self.pos + 1)) {
      self.pos += 1
      while self.pos < self.len && is_digit(self.char_at(self.pos)) {
        self.pos += 1
      }
      is_float = true
    }
    // PKL-128: scientific-notation Float (`1e10`, `2.5e-3`, `4E+8`).
    // An `e` / `E` immediately following the digit (or fractional)
    // run with an optional `+` / `-` sign and at least one digit
    // promotes the literal to a Float. Without the trailing digit
    // the `e` is treated as a regular identifier byte (the
    // identifier dispatch below picks it up on the next call).
    if self.pos < self.len {
      let exp_char = self.char_at(self.pos)
      if exp_char == 'e' || exp_char == 'E' {
        let mut probe = self.pos + 1
        if probe < self.len &&
          (self.char_at(probe) == '+' || self.char_at(probe) == '-') {
          probe = probe + 1
        }
        if probe < self.len && is_digit(self.char_at(probe)) {
          self.pos = probe
          while self.pos < self.len && is_digit(self.char_at(self.pos)) {
            self.pos += 1
          }
          is_float = true
        }
      }
    }
    if is_float {
      return Token::new(float_token(), self.slice_from(start))
    }
    return Token::new(int_token(), self.slice_from(start))
  }
  // PKL-148an: raw string literal — `#"..."#` (single-line) or
  // `#"""..."""#` (heredoc). Apple Pkl allows an arbitrary number
  // of leading `#`s; the closing delimiter must carry the same
  // count. Inside a raw string `\` escape sequences and `\(...)`
  // interpolation are NOT interpreted (verbatim text). The
  // `\<N hashes>(expr)` form re-enables interpolation, but that's a
  // follow-up — the lexer simply scans until the matching close.
  if c == '#' {
    let mut hash_count = 0
    while self.pos + hash_count < self.len &&
          self.char_at(self.pos + hash_count) == '#' {
      hash_count = hash_count + 1
    }
    let quote_pos = self.pos + hash_count
    if hash_count >= 1 && quote_pos < self.len && self.char_at(quote_pos) == '"' {
      let is_heredoc = quote_pos + 2 < self.len &&
        self.char_at(quote_pos + 1) == '"' &&
        self.char_at(quote_pos + 2) == '"'
      if is_heredoc {
        let mut p = quote_pos + 3
        // Need to find `"""` + hash_count `#`s.
        let needed = 3 + hash_count
        while p + needed - 1 < self.len {
          if self.char_at(p) == '"' &&
            self.char_at(p + 1) == '"' &&
            self.char_at(p + 2) == '"' {
            let mut ok = true
            for i = 0; i < hash_count; i = i + 1 {
              if self.char_at(p + 3 + i) != '#' {
                ok = false
                break
              }
            }
            if ok {
              self.pos = p + 3 + hash_count
              return Token::new(string_token(), self.slice_from(start))
            }
          }
          p = p + 1
        }
        self.pos = self.len
        return Token::new(string_token(), self.slice_from(start))
      }
      // Single-line raw: scan until `"` + hash_count `#`s, OR newline
      // (which ends the literal token; Apple Pkl flags that as a
      // lex / parse error but our recovery just stops the token).
      let mut p = quote_pos + 1
      let needed = 1 + hash_count
      while p + needed - 1 < self.len {
        let ch = self.char_at(p)
        if ch == '"' {
          let mut ok = true
          for i = 0; i < hash_count; i = i + 1 {
            if self.char_at(p + 1 + i) != '#' {
              ok = false
              break
            }
          }
          if ok {
            self.pos = p + 1 + hash_count
            return Token::new(string_token(), self.slice_from(start))
          }
        }
        if ch == '\n' {
          break
        }
        p = p + 1
      }
      self.pos = p
      return Token::new(string_token(), self.slice_from(start))
    }
  }
  if c == '"' {
    // PKL-128: triple-quoted heredoc (`"""..."""`). Apple Pkl strips
    // the leading newline + the closing delimiter's indentation from
    // each content line. The lexer keeps the whole literal as one
    // `string_token`; the parser's escape decoder will strip the
    // indent and unwrap. Detection is shallow: three consecutive
    // `"` characters open a heredoc, and the matching three `"`
    // close it. Inner `"` runs of length 1 or 2 stay literal.
    if self.pos + 2 < self.len &&
      self.char_at(self.pos + 1) == '"' &&
      self.char_at(self.pos + 2) == '"' {
      self.pos += 3
      while self.pos + 2 < self.len {
        if self.char_at(self.pos) == '"' &&
          self.char_at(self.pos + 1) == '"' &&
          self.char_at(self.pos + 2) == '"' {
          self.pos += 3
          return Token::new(string_token(), self.slice_from(start))
        }
        self.pos += 1
      }
      // Unterminated heredoc — consume to EOF and return what we have.
      self.pos = self.len
      return Token::new(string_token(), self.slice_from(start))
    }
    self.pos += 1
    while self.pos < self.len {
      let ch = self.char_at(self.pos)
      if ch == '"' || ch == '\n' {
        break
      }
      if ch == '\\' {
        // PKL-128: `\(...)` is a string interpolation segment.  Walk
        // the balanced paren group so the inner `"..."` doesn't close
        // the outer string. Other escape sequences (`\n`, `\t`, etc.)
        // consume two chars as before.
        if self.pos + 1 < self.len && self.char_at(self.pos + 1) == '(' {
          self.pos += 2
          let mut depth = 1
          let mut inside_string = false
          while self.pos < self.len && depth > 0 {
            let cc = self.char_at(self.pos)
            if inside_string {
              if cc == '\\' && self.pos + 1 < self.len {
                self.pos += 2
                continue
              } else if cc == '"' {
                inside_string = false
              }
            } else if cc == '"' {
              inside_string = true
            } else if cc == '(' {
              depth = depth + 1
            } else if cc == ')' {
              depth = depth - 1
              if depth == 0 {
                self.pos += 1
                break
              }
            }
            self.pos += 1
          }
        } else {
          self.pos += 1
          if self.pos < self.len {
            self.pos += 1
          }
        }
      } else {
        self.pos += 1
      }
    }
    if self.pos < self.len && self.char_at(self.pos) == '"' {
      self.pos += 1
    }
    return Token::new(string_token(), self.slice_from(start))
  }
  if c == '`' {
    self.pos += 1
    while self.pos < self.len {
      let ch = self.char_at(self.pos)
      if ch == '`' || ch == '\n' {
        break
      }
      self.pos += 1
    }
    if self.pos < self.len && self.char_at(self.pos) == '`' {
      self.pos += 1
    }
    return Token::new(identifier(), self.slice_from(start))
  }
  if self.pos + 1 < self.len {
    let next = self.char_at(self.pos + 1)
    match c {
      '=' if next == '=' => {
        self.pos += 2
        return Token::new(equal_equal(), "==")
      }
      '!' if next == '=' => {
        self.pos += 2
        return Token::new(not_equal(), "!=")
      }
      '!' if next == '!' => {
        self.pos += 2
        return Token::new(non_null(), "!!")
      }
      '<' if next == '=' => {
        self.pos += 2
        return Token::new(lte(), "<=")
      }
      '>' if next == '=' => {
        self.pos += 2
        return Token::new(gte(), ">=")
      }
      '&' if next == '&' => {
        self.pos += 2
        return Token::new(and_and(), "&&")
      }
      '|' if next == '|' => {
        self.pos += 2
        return Token::new(or_or(), "||")
      }
      '|' if next == '>' => {
        self.pos += 2
        return Token::new(pipe_forward(), "|>")
      }
      '?' if next == '?' => {
        self.pos += 2
        return Token::new(coalesce(), "??")
      }
      '?' if next == '.' => {
        self.pos += 2
        return Token::new(qdot(), "?.")
      }
      '-' if next == '>' => {
        self.pos += 2
        return Token::new(arrow(), "->")
      }
      '*' if next == '*' => {
        self.pos += 2
        return Token::new(pow(), "**")
      }
      '~' if next == '/' => {
        self.pos += 2
        return Token::new(int_div(), "~/")
      }
      _ => ()
    }
  }
  self.pos += 1
  match c {
    '=' => Token::new(eq(), "=")
    '+' => Token::new(plus(), "+")
    '-' => Token::new(minus(), "-")
    '*' => Token::new(star(), "*")
    '/' => Token::new(slash(), "/")
    '(' => Token::new(lparen(), "(")
    ')' => Token::new(rparen(), ")")
    ';' => Token::new(semicolon(), ";")
    '{' => Token::new(lbrace(), "{")
    '}' => Token::new(rbrace(), "}")
    '.' => Token::new(dot(), ".")
    ':' => Token::new(colon(), ":")
    '[' => Token::new(lbracket(), "[")
    ']' => Token::new(rbracket(), "]")
    ',' => Token::new(comma(), ",")
    '@' => Token::new(at_sign(), "@")
    '?' => Token::new(question(), "?")
    '!' => Token::new(bang(), "!")
    '<' => Token::new(lt(), "<")
    '>' => Token::new(gt(), ">")
    '|' => Token::new(pipe(), "|")
    '%' => Token::new(percent(), "%")
    _ => Token::new(error_kind(), c.to_string())
  }
}

///|
fn Lexer::is_eof(self : Lexer) -> Bool {
  self.pos >= self.len
}

///|
fn tokenize(input : String) -> Array[Token] {
  let lexer = Lexer::new(input)
  let tokens : Array[Token] = []
  while !lexer.is_eof() {
    tokens.push(lexer.next_token())
  }
  tokens.push(Token::new(eof(), ""))
  tokens
}
