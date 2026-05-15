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
  if is_digit(c) {
    self.pos += 1
    while self.pos < self.len && is_digit(self.char_at(self.pos)) {
      self.pos += 1
    }
    // PKL-092: a `.digit` immediately after the integer run promotes the
    // token to a Float literal. The Duration / DataSize unit shorthand
    // (`1.h`, `5.min`) stays an Int because the character after `.` is
    // an identifier, not a digit, so the dispatch below keeps the
    // existing magnitude-+-unit path intact.
    if self.pos + 1 < self.len &&
      self.char_at(self.pos) == '.' &&
      is_digit(self.char_at(self.pos + 1)) {
      self.pos += 1
      while self.pos < self.len && is_digit(self.char_at(self.pos)) {
        self.pos += 1
      }
      return Token::new(float_token(), self.slice_from(start))
    }
    return Token::new(int_token(), self.slice_from(start))
  }
  if c == '"' {
    self.pos += 1
    while self.pos < self.len {
      let ch = self.char_at(self.pos)
      if ch == '"' || ch == '\n' {
        break
      }
      if ch == '\\' {
        self.pos += 1
        if self.pos < self.len {
          self.pos += 1
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
