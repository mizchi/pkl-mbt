///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
  builder : @cst.GreenNodeBuilder
  diagnostics : Array[Diagnostic]
}

///|
fn Parser::new(tokens : Array[Token]) -> Parser {
  Parser::{
    tokens,
    pos: 0,
    builder: @cst.GreenNodeBuilder::new(),
    diagnostics: [],
  }
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos >= self.tokens.length() {
    Token::new(eof(), "")
  } else {
    self.tokens[self.pos]
  }
}

///|
fn Parser::peek_kind(self : Parser) -> @cst.SyntaxKind {
  self.peek().kind()
}

///|
fn Parser::at(self : Parser, kind : @cst.SyntaxKind) -> Bool {
  self.peek_kind() == kind
}

///|
fn Parser::at_text(self : Parser, text : String) -> Bool {
  self.peek().text() == text
}

///|
fn is_modifier_text(text : String) -> Bool {
  match text {
    "abstract" | "external" | "open" | "hidden" | "fixed" | "const" => true
    _ => false
  }
}

///|
fn is_decl_text(text : String) -> Bool {
  match text {
    "class" | "function" | "typealias" | "amends" | "extends" => true
    _ => false
  }
}

///|
fn Parser::peek_non_whitespace_kind(
  self : Parser,
  start : Int,
) -> @cst.SyntaxKind {
  let mut i = start
  while i < self.tokens.length() &&
        (
          self.tokens[i].kind() == whitespace() ||
          self.tokens[i].kind() == comment()
        ) {
    i += 1
  }
  if i >= self.tokens.length() {
    eof()
  } else {
    self.tokens[i].kind()
  }
}

///|
fn Parser::peek_non_trivia_text(self : Parser, start : Int) -> String {
  let mut i = start
  while i < self.tokens.length() && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.tokens.length() {
    ""
  } else {
    self.tokens[i].text()
  }
}

///|
fn Parser::peek_non_trivia_kind(self : Parser, start : Int) -> @cst.SyntaxKind {
  let mut i = start
  while i < self.tokens.length() && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.tokens.length() {
    eof()
  } else {
    self.tokens[i].kind()
  }
}

///|
fn Parser::at_property_decl(self : Parser) -> Bool {
  self.at(identifier()) &&
  (
    self.peek_non_whitespace_kind(self.pos + 1) == eq() ||
    self.peek_non_whitespace_kind(self.pos + 1) == colon() ||
    self.peek_non_whitespace_kind(self.pos + 1) == lbrace()
  )
}

///|
fn Parser::at_property_decl_from(self : Parser, start : Int) -> Bool {
  if start >= self.tokens.length() || self.tokens[start].kind() != identifier() {
    return false
  }
  let next = self.peek_non_whitespace_kind(start + 1)
  next == eq() || next == colon() || next == lbrace()
}

///|
fn Parser::at_module_member_boundary_from(self : Parser, start : Int) -> Bool {
  let mut i = start
  while i < self.tokens.length() && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.tokens.length() {
    return true
  }
  let kind = self.tokens[i].kind()
  let text = self.tokens[i].text()
  kind == eof() ||
  kind == rbrace() ||
  kind == import_kw() ||
  kind == module_kw() ||
  kind == let_kw() ||
  kind == local_kw() ||
  is_decl_text(text) ||
  is_modifier_text(text) ||
  self.at_property_decl_from(i)
}

///|
fn Parser::paren_expr_looks_unsupported(self : Parser) -> Bool {
  if !self.at(lparen()) {
    return false
  }
  let mut depth = 0
  let mut i = self.pos
  while i < self.tokens.length() {
    let kind = self.tokens[i].kind()
    if kind == lparen() {
      depth += 1
    } else if kind == rparen() {
      depth -= 1
      if depth == 0 {
        let next = self.peek_non_whitespace_kind(i + 1)
        return next == minus()
      }
    } else if depth == 1 && (kind == comma() || kind == colon()) {
      return true
    }
    i += 1
  }
  false
}

///|
fn Parser::add_error(self : Parser, message : String) -> Unit {
  self.diagnostics.push(Diagnostic::{ message, })
}

///|
fn Parser::bump(self : Parser) -> Token {
  let tok = self.peek()
  self.builder.token(tok.kind(), tok.text())
  self.pos += 1
  tok
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while self.at(whitespace()) || self.at(comment()) {
    ignore(self.bump())
  }
}

///|
fn Parser::skip_trivia(self : Parser) -> Unit {
  while is_trivia(self.peek_kind()) {
    ignore(self.bump())
  }
}

///|
fn Parser::consume_separators(self : Parser) -> Unit {
  while ({
          self.skip_whitespace()
          is_separator(self.peek_kind())
        }) {
    ignore(self.bump())
  }
}

///|
fn Parser::skip_annotation(self : Parser) -> Unit {
  if self.at(at_sign()) || self.at_text("@") {
    ignore(self.bump())
    while self.at(identifier()) || self.at(dot()) {
      ignore(self.bump())
    }
    self.skip_whitespace()
    if self.at(lparen()) {
      self.skip_balanced_group(lparen(), rparen())
    }
  }
}

///|
fn Parser::skip_member_header(self : Parser) -> Unit {
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(at_sign()) || self.at_text("@") {
      self.skip_annotation()
    } else if is_modifier_text(self.peek().text()) {
      ignore(self.bump())
    } else {
      keep_going = false
    }
  }
}

///|
fn Parser::skip_balanced_group(
  self : Parser,
  open : @cst.SyntaxKind,
  close : @cst.SyntaxKind,
) -> Unit {
  if !self.at(open) {
    return
  }
  let mut depth = 0
  while !self.at(eof()) {
    if self.at(open) {
      depth += 1
    } else if self.at(close) {
      depth -= 1
      ignore(self.bump())
      if depth == 0 {
        return
      }
      continue
    }
    ignore(self.bump())
  }
}

///|
fn Parser::skip_unknown_member(self : Parser) -> Unit {
  let mut parens = 0
  let mut braces = 0
  let mut brackets = 0
  let mut consumed = false
  while !self.at(eof()) {
    if !consumed &&
      (self.at(rbrace()) || self.at(rparen()) || self.at(rbracket())) {
      ignore(self.bump())
      return
    }
    if consumed && parens == 0 && braces == 0 && brackets == 0 {
      if self.at(rbrace()) || self.at(rparen()) || self.at(rbracket()) {
        return
      }
      if is_separator(self.peek_kind()) {
        return
      }
    }
    if self.at(lparen()) {
      parens += 1
    } else if self.at(rparen()) {
      if parens == 0 {
        return
      }
      parens -= 1
    } else if self.at(lbrace()) {
      braces += 1
    } else if self.at(rbrace()) {
      if braces == 0 {
        return
      }
      braces -= 1
    } else if self.at(lbracket()) {
      brackets += 1
    } else if self.at(rbracket()) {
      if brackets == 0 {
        return
      }
      brackets -= 1
    }
    consumed = true
    ignore(self.bump())
  }
}

///|
fn Parser::expect(
  self : Parser,
  kind : @cst.SyntaxKind,
  expected : String,
) -> Token? {
  self.skip_whitespace()
  if self.at(kind) {
    Some(self.bump())
  } else {
    self.add_error("expected \{expected}, got \{kind_name(self.peek_kind())}")
    self.builder.token(error_kind(), "")
    None
  }
}

///|
fn Parser::parse(self : Parser) -> ParseResult {
  self.builder.start_node(module_node())
  let mut module_name : String? = None
  let imports : Array[ImportDecl] = []
  let bindings : Array[Binding] = []
  self.consume_separators()
  let mut body : Expr? = None
  while !self.at(eof()) {
    self.skip_member_header()
    if self.at(eof()) {
      break
    }
    if self.at(import_kw()) {
      match self.parse_import_decl() {
        Some(decl) => imports.push(decl)
        None => ()
      }
    } else if self.at(module_kw()) ||
      self.at_text("amends") ||
      self.at_text("extends") {
      match self.parse_module_decl() {
        Some(name) => module_name = Some(name)
        None => ()
      }
    } else if self.at(let_kw()) {
      if self.peek_non_trivia_kind(self.pos + 1) == lparen() {
        if body is None {
          body = Some(self.parse_expr())
        } else {
          self.skip_unknown_member()
        }
      } else {
        match self.parse_let_decl() {
          Some(binding) => bindings.push(binding)
          None => ()
        }
      }
    } else if self.at(local_kw()) {
      if is_decl_text(self.peek_non_trivia_text(self.pos + 1)) {
        self.skip_unknown_member()
      } else {
        match self.parse_local_decl() {
          Some(binding) => bindings.push(binding)
          None => ()
        }
      }
    } else if self.at_property_decl() {
      match self.parse_property_decl() {
        Some(binding) => bindings.push(binding)
        None => ()
      }
    } else if is_decl_text(self.peek().text()) {
      self.skip_unknown_member()
    } else if body is None {
      body = Some(self.parse_expr())
    } else {
      self.skip_unknown_member()
    }
    self.consume_separators()
  }
  self.builder.finish_node()
  let green = self.builder.finish()
  {
    root: @cst.SyntaxNode::new_root(green),
    program: { module_name, imports, bindings, body },
    diagnostics: self.diagnostics,
  }
}

///|
fn Parser::parse_module_decl(self : Parser) -> String? {
  self.builder.start_node(module_decl())
  let buf = StringBuilder::new()
  if self.at(module_kw()) {
    ignore(self.bump())
    match self.expect(identifier(), "module name") {
      Some(tok) => buf.write_string(tok.text())
      None => ()
    }
    while ({
            self.skip_whitespace()
            self.at(dot())
          }) {
      ignore(self.bump())
      match self.expect(identifier(), "module name segment") {
        Some(tok) => {
          buf.write_string(".")
          buf.write_string(tok.text())
        }
        None => ()
      }
    }
  }
  self.skip_whitespace()
  if self.at_text("extends") || self.at_text("amends") {
    ignore(self.bump())
    if self.at(string_token()) {
      ignore(self.bump())
    } else if self.at(lparen()) {
      self.skip_balanced_group(lparen(), rparen())
    } else {
      self.skip_unknown_member()
    }
  }
  self.builder.finish_node()
  let text = buf.to_string()
  if text == "" {
    None
  } else {
    Some(text)
  }
}

///|
fn Parser::parse_let_decl(self : Parser) -> Binding? {
  self.builder.start_node(let_decl())
  ignore(self.expect(let_kw(), "let"))
  let name = match self.expect(identifier(), "identifier") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_type_annotation()
  let value = if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else {
    UnsupportedExpr
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: false })
  }
}

///|
fn Parser::parse_local_decl(self : Parser) -> Binding? {
  self.builder.start_node(let_decl())
  ignore(self.expect(local_kw(), "local"))
  let name = match self.expect(identifier(), "identifier") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_type_annotation()
  let value = if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else {
    UnsupportedExpr
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: false })
  }
}

///|
fn Parser::parse_type_annotation(self : Parser) -> String? {
  self.skip_whitespace()
  if !self.at(colon()) {
    return None
  }
  ignore(self.bump())
  self.skip_whitespace()
  let type_name = if self.at(identifier()) {
    Some(self.bump().text())
  } else {
    None
  }
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  while !self.at(eof()) {
    if parens == 0 && brackets == 0 && angles == 0 {
      if self.at(eq()) ||
        self.at(lbrace()) ||
        self.at(rbrace()) ||
        is_separator(self.peek_kind()) {
        break
      }
    }
    if self.at(lparen()) {
      parens += 1
    } else if self.at(rparen()) {
      if parens == 0 {
        break
      }
      parens -= 1
    } else if self.at(lbracket()) {
      brackets += 1
    } else if self.at(rbracket()) {
      if brackets == 0 {
        break
      }
      brackets -= 1
    } else if self.at(lt()) {
      angles += 1
    } else if self.at(gt()) {
      if angles == 0 {
        break
      }
      angles -= 1
    }
    ignore(self.bump())
  }
  type_name
}

///|
fn Parser::parse_import_decl(self : Parser) -> ImportDecl? {
  self.builder.start_node(import_decl())
  ignore(self.expect(import_kw(), "import"))
  self.skip_whitespace()
  if self.at(star()) {
    ignore(self.bump())
  }
  self.skip_whitespace()
  let uri = if self.at(string_token()) {
    unquote(self.bump().text())
  } else {
    self.skip_unknown_member()
    ""
  }
  let import_name = if ({
      self.skip_whitespace()
      self.at(as_kw())
    }) {
    ignore(self.bump())
    match self.expect(identifier(), "import alias") {
      Some(tok) => tok.text()
      None => ""
    }
  } else {
    import_alias_from_uri(uri)
  }
  self.builder.finish_node()
  if uri == "" || import_name == "" {
    None
  } else {
    Some({ uri, import_name })
  }
}

///|
fn Parser::parse_property_decl(self : Parser) -> Binding? {
  self.builder.start_node(property_decl())
  if !self.at(identifier()) {
    self.skip_unknown_member()
    self.builder.finish_node()
    return None
  }
  let name = match self.expect(identifier(), "property name") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_type_annotation()
  let value = if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    self.parse_object_body()
  } else if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else {
    UnsupportedExpr
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: true })
  }
}

///|
fn Parser::parse_expr(self : Parser) -> Expr {
  self.parse_add_expr()
}

///|
fn Parser::parse_add_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = self.parse_mul_expr()
  while ({
          self.skip_whitespace()
          self.at(plus()) || self.at(minus())
        }) {
    self.builder.start_node_at(checkpoint, binary_expr())
    let op = if self.at(plus()) { BinaryOp::Add } else { BinaryOp::Subtract }
    ignore(self.bump())
    let right = self.parse_mul_expr()
    self.builder.finish_node()
    left = BinaryExpr(op, left, right)
  }
  left
}

///|
fn Parser::parse_mul_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = self.parse_postfix_expr()
  while ({
          self.skip_whitespace()
          self.at(star()) || self.at(slash())
        }) {
    self.builder.start_node_at(checkpoint, binary_expr())
    let op = if self.at(star()) { BinaryOp::Multiply } else { BinaryOp::Divide }
    ignore(self.bump())
    let right = self.parse_postfix_expr()
    self.builder.finish_node()
    left = BinaryExpr(op, left, right)
  }
  left
}

///|
fn Parser::parse_postfix_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut expr = self.parse_primary_expr()
  let mut keep_going = true
  while keep_going {
    self.skip_whitespace()
    if self.at(dot()) {
      self.builder.start_node_at(checkpoint, member_access())
      ignore(self.bump())
      let field_name = if self.at(identifier()) {
        self.bump().text()
      } else {
        if !self.at(eof()) {
          ignore(self.bump())
        }
        ""
      }
      self.builder.finish_node()
      expr = if field_name == "" {
        UnsupportedExpr
      } else {
        MemberAccess(expr, field_name)
      }
    } else if self.at(lparen()) {
      self.skip_balanced_group(lparen(), rparen())
      expr = UnsupportedExpr
    } else if self.at(lbracket()) {
      self.skip_balanced_group(lbracket(), rbracket())
      expr = UnsupportedExpr
    } else if self.at(question()) || self.at(bang()) {
      ignore(self.bump())
      expr = UnsupportedExpr
    } else {
      keep_going = false
    }
  }
  expr
}

///|
fn Parser::parse_primary_expr(self : Parser) -> Expr {
  self.skip_trivia()
  match self.peek_kind() {
    kind if kind == int_token() => {
      self.builder.start_node(literal_expr())
      let tok = self.bump()
      self.builder.finish_node()
      IntLiteral(parse_int_text(tok.text()))
    }
    kind if kind == true_kw() => {
      self.builder.start_node(literal_expr())
      ignore(self.bump())
      self.builder.finish_node()
      BoolLiteral(true)
    }
    kind if kind == false_kw() => {
      self.builder.start_node(literal_expr())
      ignore(self.bump())
      self.builder.finish_node()
      BoolLiteral(false)
    }
    kind if kind == null_kw() => {
      self.builder.start_node(literal_expr())
      ignore(self.bump())
      self.builder.finish_node()
      NullLiteral
    }
    kind if kind == string_token() => {
      self.builder.start_node(literal_expr())
      let tok = self.bump()
      self.builder.finish_node()
      StringLiteral(unquote(tok.text()))
    }
    kind if kind == identifier() => {
      if self.peek_non_whitespace_kind(self.pos + 1) == lparen() {
        return self.parse_unsupported_expr()
      }
      self.builder.start_node(name_ref())
      let tok = self.bump()
      self.builder.finish_node()
      Identifier(tok.text())
    }
    kind if kind == import_kw() => self.parse_import_expr()
    kind if kind == new_kw() => self.parse_object_expr()
    kind if kind == lparen() => {
      if self.paren_expr_looks_unsupported() {
        return self.parse_unsupported_expr()
      }
      self.builder.start_node(paren_expr())
      ignore(self.bump())
      let expr = self.parse_expr()
      ignore(self.expect(rparen(), ")"))
      self.builder.finish_node()
      expr
    }
    _ => self.parse_unsupported_expr()
  }
}

///|
fn Parser::parse_unsupported_expr(self : Parser) -> Expr {
  self.builder.start_node(unsupported_expr())
  let mut parens = 0
  let mut braces = 0
  let mut brackets = 0
  let mut consumed = false
  self.skip_trivia()
  while !self.at(eof()) {
    if consumed && parens == 0 && braces == 0 && brackets == 0 {
      if self.at(rbrace()) ||
        self.at(rparen()) ||
        self.at(rbracket()) ||
        self.at(comma()) {
        break
      }
      if is_separator(self.peek_kind()) &&
        self.at_module_member_boundary_from(self.pos + 1) {
        break
      }
    }
    if self.at(lparen()) {
      parens += 1
    } else if self.at(rparen()) {
      if parens == 0 {
        break
      }
      parens -= 1
    } else if self.at(lbrace()) {
      braces += 1
    } else if self.at(rbrace()) {
      if braces == 0 {
        break
      }
      braces -= 1
    } else if self.at(lbracket()) {
      brackets += 1
    } else if self.at(rbracket()) {
      if brackets == 0 {
        break
      }
      brackets -= 1
    }
    consumed = true
    ignore(self.bump())
  }
  if !consumed && !self.at(eof()) {
    ignore(self.bump())
  }
  self.builder.finish_node()
  UnsupportedExpr
}

///|
fn Parser::parse_import_expr(self : Parser) -> Expr {
  self.builder.start_node(import_expr())
  ignore(self.expect(import_kw(), "import"))
  self.skip_whitespace()
  if self.at(star()) {
    ignore(self.bump())
  }
  if self.at(lparen()) {
    ignore(self.bump())
  }
  self.skip_whitespace()
  let uri = if self.at(string_token()) {
    unquote(self.bump().text())
  } else {
    while !self.at(eof()) && !self.at(rparen()) {
      ignore(self.bump())
    }
    ""
  }
  if self.at(rparen()) {
    ignore(self.bump())
  }
  self.builder.finish_node()
  ImportExpr(uri)
}

///|
fn Parser::parse_object_expr(self : Parser) -> Expr {
  self.builder.start_node(object_expr())
  ignore(self.expect(new_kw(), "new"))
  self.skip_whitespace()
  while !self.at(eof()) && !self.at(lbrace()) {
    if is_separator(self.peek_kind()) || self.at(rbrace()) {
      break
    }
    ignore(self.bump())
    self.skip_whitespace()
  }
  let value = self.parse_object_body()
  self.builder.finish_node()
  value
}

///|
fn Parser::parse_object_body(self : Parser) -> Expr {
  ignore(self.expect(lbrace(), "{"))
  let members : Array[ObjectMember] = []
  self.consume_separators()
  while !self.at(eof()) && !self.at(rbrace()) {
    self.skip_member_header()
    if self.at_property_decl() {
      match self.parse_object_member() {
        Some(field) => members.push(field)
        None => ()
      }
    } else {
      self.skip_unknown_member()
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  ObjectLiteral(members)
}

///|
fn Parser::parse_object_member(self : Parser) -> ObjectMember? {
  self.builder.start_node(object_member())
  if !self.at(identifier()) {
    self.skip_unknown_member()
    self.builder.finish_node()
    return None
  }
  let name = match self.expect(identifier(), "object member name") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_type_annotation()
  let value = if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    self.parse_object_body()
  } else if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else {
    UnsupportedExpr
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value })
  }
}

///|
fn parse_int_text(text : String) -> Int {
  let mut value = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - '0'.to_int()
    }
  }
  value
}

///|
fn unquote(text : String) -> String {
  if text.length() >= 2 && text[0].to_int().unsafe_to_char() == '"' {
    let end = text.length() - 1
    if text[end].to_int().unsafe_to_char() == '"' {
      return decode_string_escapes(
        String::unsafe_substring(text, start=1, end~),
      )
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
  Parser::new(tokenize(source)).parse()
}
