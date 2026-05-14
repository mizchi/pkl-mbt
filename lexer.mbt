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
  mut pos : Int
}

///|
fn Lexer::new(input : String) -> Lexer {
  Lexer::{ input, pos: 0 }
}

///|
fn Lexer::peek(self : Lexer) -> Char? {
  if self.pos >= self.input.length() {
    None
  } else {
    Some(self.input[self.pos].to_int().unsafe_to_char())
  }
}

///|
fn Lexer::peek_next(self : Lexer) -> Char? {
  if self.pos + 1 >= self.input.length() {
    None
  } else {
    Some(self.input[self.pos + 1].to_int().unsafe_to_char())
  }
}

///|
fn Lexer::advance(self : Lexer) -> Char? {
  match self.peek() {
    Some(c) => {
      self.pos += 1
      Some(c)
    }
    None => None
  }
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
  let buf = StringBuilder::new()
  for i = start; i < self.pos; i = i + 1 {
    buf.write_char(self.input[i].to_int().unsafe_to_char())
  }
  buf.to_string()
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
    _ => identifier()
  }
}

///|
fn Lexer::next_token(self : Lexer) -> Token {
  match self.peek() {
    None => Token::new(eof(), "")
    Some(c) => {
      if is_horizontal_space(c) {
        let start = self.pos
        while (match self.peek() {
                Some(ch) => is_horizontal_space(ch)
                None => false
              }) {
          ignore(self.advance())
        }
        return Token::new(whitespace(), self.slice_from(start))
      }
      if c == '\n' {
        ignore(self.advance())
        return Token::new(newline(), "\n")
      }
      if c == '/' && self.peek_next() == Some('/') {
        let start = self.pos
        ignore(self.advance())
        ignore(self.advance())
        while (match self.peek() {
                Some(ch) => ch != '\n'
                None => false
              }) {
          ignore(self.advance())
        }
        return Token::new(comment(), self.slice_from(start))
      }
      if c == '/' && self.peek_next() == Some('*') {
        let start = self.pos
        ignore(self.advance())
        ignore(self.advance())
        while !self.is_eof() {
          if self.peek() == Some('*') && self.peek_next() == Some('/') {
            ignore(self.advance())
            ignore(self.advance())
            return Token::new(comment(), self.slice_from(start))
          }
          ignore(self.advance())
        }
        return Token::new(comment(), self.slice_from(start))
      }
      if is_alpha(c) {
        let start = self.pos
        while (match self.peek() {
                Some(ch) => is_alnum(ch)
                None => false
              }) {
          ignore(self.advance())
        }
        let text = self.slice_from(start)
        return Token::new(keyword_or_identifier(text), text)
      }
      if is_digit(c) {
        let start = self.pos
        while (match self.peek() {
                Some(ch) => is_digit(ch)
                None => false
              }) {
          ignore(self.advance())
        }
        return Token::new(int_token(), self.slice_from(start))
      }
      if c == '"' {
        let start = self.pos
        ignore(self.advance())
        while (match self.peek() {
                Some(ch) => ch != '"' && ch != '\n'
                None => false
              }) {
          match self.peek() {
            Some('\\') => {
              ignore(self.advance())
              if self.peek() is Some(_) {
                ignore(self.advance())
              }
            }
            _ => ignore(self.advance())
          }
        }
        if self.peek() == Some('"') {
          ignore(self.advance())
        }
        return Token::new(string_token(), self.slice_from(start))
      }
      if c == '`' {
        let start = self.pos
        ignore(self.advance())
        while (match self.peek() {
                Some(ch) => ch != '`' && ch != '\n'
                None => false
              }) {
          ignore(self.advance())
        }
        if self.peek() == Some('`') {
          ignore(self.advance())
        }
        return Token::new(identifier(), self.slice_from(start))
      }
      ignore(self.advance())
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
  }
}

///|
fn Lexer::is_eof(self : Lexer) -> Bool {
  self.pos >= self.input.length()
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
