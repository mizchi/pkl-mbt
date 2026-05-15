///|
priv struct Parser {
  source : String
  tokens : Array[Token]
  len : Int
  mut pos : Int
  builder : @cst.GreenNodeBuilder
  diagnostics : Array[Diagnostic]
  unsupported_syntax : Array[UnsupportedSyntax]
}

///|
priv struct ParsedModuleDecl {
  module_name : String?
  module_relation : ModuleRelation?
}

///|
fn Parser::new(source : String) -> Parser {
  let tokens = tokenize(source)
  Parser::{
    source,
    tokens,
    len: tokens.length(),
    pos: 0,
    builder: @cst.GreenNodeBuilder::new(),
    diagnostics: [],
    unsupported_syntax: [],
  }
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos >= self.len {
    Token::new(eof(), "")
  } else {
    self.tokens[self.pos]
  }
}

///|
/// Cheap peek that avoids materialising a Token struct copy for the
/// common case (`self.pos` inside bounds). Called from hot dispatch
/// loops in the parser where the Token's text is not needed.
fn Parser::peek_kind(self : Parser) -> @cst.SyntaxKind {
  if self.pos >= self.len {
    eof()
  } else {
    self.tokens[self.pos].kind()
  }
}

///|
fn Parser::at(self : Parser, kind : @cst.SyntaxKind) -> Bool {
  self.peek_kind() == kind
}

///|
/// Compare the peeked token's text against a literal. Short-circuits on
/// text length so the common case of mismatched-length keywords (e.g.
/// `at_text("class")` when the peek is `function`) is rejected without
/// touching the underlying character data.
fn Parser::at_text(self : Parser, text : String) -> Bool {
  if self.pos >= self.len {
    return false
  }
  let tok_text = self.tokens[self.pos].text()
  if tok_text.length() != text.length() {
    return false
  }
  tok_text == text
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
  while i < self.len &&
        (
          self.tokens[i].kind() == whitespace() ||
          self.tokens[i].kind() == comment()
        ) {
    i += 1
  }
  if i >= self.len {
    eof()
  } else {
    self.tokens[i].kind()
  }
}

///|
fn Parser::peek_non_trivia_text(self : Parser, start : Int) -> String {
  let mut i = start
  while i < self.len && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.len {
    ""
  } else {
    self.tokens[i].text()
  }
}

///|
fn Parser::peek_non_trivia_kind(self : Parser, start : Int) -> @cst.SyntaxKind {
  let mut i = start
  while i < self.len && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.len {
    eof()
  } else {
    self.tokens[i].kind()
  }
}

///|
fn Parser::at_property_decl(self : Parser) -> Bool {
  if !self.at(identifier()) {
    return false
  }
  let next = self.peek_non_whitespace_kind(self.pos + 1)
  next == eq() || next == colon() || next == lbrace()
}

///|
fn Parser::at_property_decl_from(self : Parser, start : Int) -> Bool {
  if start >= self.len || self.tokens[start].kind() != identifier() {
    return false
  }
  let next = self.peek_non_whitespace_kind(start + 1)
  next == eq() || next == colon() || next == lbrace()
}

///|
fn Parser::at_module_member_boundary_from(self : Parser, start : Int) -> Bool {
  let mut i = start
  while i < self.len && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.len {
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
  while i < self.len {
    let kind = self.tokens[i].kind()
    if kind == lparen() {
      depth += 1
    } else if kind == rparen() {
      depth -= 1
      if depth == 0 {
        return false
      }
    } else if depth == 1 && (kind == comma() || kind == colon()) {
      return true
    }
    i += 1
  }
  false
}

///|
fn Parser::function_literal_at_current(self : Parser) -> Bool {
  if !self.at(lparen()) {
    return false
  }
  let first = self.peek_non_trivia_kind(self.pos + 1)
  if first != rparen() && first != identifier() {
    return false
  }
  let mut depth = 0
  let mut i = self.pos
  while i < self.len {
    let kind = self.tokens[i].kind()
    if kind == lparen() {
      depth += 1
    } else if kind == rparen() {
      depth -= 1
      if depth == 0 {
        return self.lambda_arrow_after_parameter_list(i + 1)
      }
    }
    i += 1
  }
  false
}

///|
fn Parser::lambda_arrow_after_parameter_list(
  self : Parser,
  start : Int,
) -> Bool {
  let mut i = start
  while i < self.len && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  if i >= self.len {
    return false
  }
  if self.tokens[i].kind() == arrow() {
    return true
  }
  if self.tokens[i].kind() != colon() {
    return false
  }
  i += 1
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  while i < self.len {
    let kind = self.tokens[i].kind()
    if parens == 0 && brackets == 0 && angles == 0 {
      if kind == arrow() {
        return true
      }
      if kind == eq() ||
        kind == lbrace() ||
        kind == rbrace() ||
        is_separator(kind) {
        return false
      }
    }
    if kind == lparen() {
      parens += 1
    } else if kind == rparen() {
      if parens == 0 {
        return false
      }
      parens -= 1
    } else if kind == lbracket() {
      brackets += 1
    } else if kind == rbracket() {
      if brackets == 0 {
        return false
      }
      brackets -= 1
    } else if parens == 0 && brackets == 0 && kind == lt() {
      angles += 1
    } else if parens == 0 && brackets == 0 && kind == gt() {
      if angles == 0 {
        return false
      }
      angles -= 1
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
fn Parser::current_offset(self : Parser) -> Int {
  let mut offset = 0
  let limit = if self.pos < self.len { self.pos } else { self.len }
  for i = 0; i < limit; i = i + 1 {
    offset += self.tokens[i].text().length()
  }
  offset
}

///|
fn Parser::source_slice(self : Parser, start : Int, end : Int) -> String {
  if end <= start || start < 0 || end > self.source.length() {
    ""
  } else {
    String::unsafe_substring(self.source, start~, end~)
  }
}

///|
fn Parser::record_unsupported_syntax(
  self : Parser,
  start : Int,
  end : Int,
  kind : String,
) -> Unit {
  self.unsupported_syntax.push(UnsupportedSyntax::{
    start,
    end,
    text: self.source_slice(start, end),
    kind,
  })
}

///|
fn Parser::parse_empty_unsupported_expr(self : Parser) -> Expr {
  let offset = self.current_offset()
  self.builder.start_node(unsupported_expr())
  self.builder.finish_node()
  self.record_unsupported_syntax(offset, offset, kind_name(unsupported_expr()))
  UnsupportedExpr
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
  while self.pos < self.len {
    match self.tokens[self.pos].kind().raw() {
      2 | 4 => ignore(self.bump())
      _ => return
    }
  }
}

///|
fn Parser::skip_trivia(self : Parser) -> Unit {
  while self.pos < self.len {
    match self.tokens[self.pos].kind().raw() {
      2 | 3 | 4 => ignore(self.bump())
      _ => return
    }
  }
}

///|
fn Parser::consume_separators(self : Parser) -> Unit {
  while true {
    self.skip_whitespace()
    if self.pos < self.len && is_separator(self.tokens[self.pos].kind()) {
      ignore(self.bump())
    } else {
      return
    }
  }
}

///|
fn Parser::skip_annotation(self : Parser) -> Unit {
  if self.at(at_sign()) {
    ignore(self.bump())
    while self.at(identifier()) || self.at(dot()) {
      ignore(self.bump())
    }
    self.skip_whitespace()
    // Apple Pkl annotations carry their argument either in parens
    // (`@Deprecated("...")`) or as a body literal (`@ModuleInfo { minPklVersion = ... }`).
    // Both forms are skipped today — we don't carry the metadata into
    // the AST yet.
    if self.at(lparen()) {
      self.skip_balanced_group(lparen(), rparen())
    } else if self.at(lbrace()) {
      self.skip_balanced_group(lbrace(), rbrace())
    }
  }
}

///|
fn Parser::skip_member_header(self : Parser) -> Unit {
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(at_sign()) {
      self.skip_annotation()
    } else if self.at(identifier()) && is_modifier_text(self.peek().text()) {
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
fn Parser::skip_call_argument_tail(self : Parser) -> Unit {
  let start = self.current_offset()
  let mut parens = 0
  let mut braces = 0
  let mut brackets = 0
  let mut consumed = false
  while !self.at(eof()) {
    if parens == 0 && braces == 0 && brackets == 0 {
      if self.at(comma()) || self.at(rparen()) {
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
  if consumed {
    self.record_unsupported_syntax(
      start,
      self.current_offset(),
      kind_name(unsupported_expr()),
    )
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
fn Parser::expect_text(self : Parser, text : String, expected : String) -> Unit {
  self.skip_whitespace()
  if self.at_text(text) {
    ignore(self.bump())
  } else {
    self.add_error("expected \{expected}, got \{self.peek().text()}")
    self.builder.token(error_kind(), "")
  }
}

///|
fn Parser::parse(self : Parser) -> ParseResult {
  self.builder.start_node(module_node())
  let mut module_name : String? = None
  let mut module_relation : ModuleRelation? = None
  let imports : Array[ImportDecl] = []
  let declarations : Array[Declaration] = []
  let bindings : Array[Binding] = []
  self.consume_separators()
  let mut body : Expr? = None
  while !self.at(eof()) {
    let hidden_at_module_level = self.consume_module_visibility_modifiers()
    self.skip_member_header()
    if self.at(eof()) {
      break
    }
    // Single peek + kind/text dispatch for the module member.
    // Previously this was a chain of `at_text` calls (each doing a String
    // compare) plus separate `at(kind)` checks; consolidating into one
    // switch removes the redundant peeks and lets the kind check fire
    // first so non-identifier tokens don't pay any string compares.
    let kind = self.peek_kind()
    let text = if kind == identifier() { self.peek().text() } else { "" }
    if kind == import_kw() {
      match self.parse_import_decl() {
        Some(decl) => imports.push(decl)
        None => ()
      }
    } else if kind == module_kw() || text == "amends" || text == "extends" {
      match self.parse_module_decl() {
        Some(decl) => {
          match decl.module_name {
            Some(name) => module_name = Some(name)
            None => ()
          }
          match decl.module_relation {
            Some(relation) => module_relation = Some(relation)
            None => ()
          }
        }
        None => ()
      }
    } else if kind == let_kw() {
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
    } else if kind == local_kw() {
      if is_decl_text(self.peek_non_trivia_text(self.pos + 1)) {
        self.skip_unknown_member()
      } else {
        match self.parse_local_decl() {
          Some(binding) => bindings.push(binding)
          None => ()
        }
      }
    } else if text == "class" {
      match self.parse_class_decl() {
        Some(decl) => declarations.push(ClassDeclaration(decl))
        None => ()
      }
    } else if text == "typealias" {
      match self.parse_typealias_decl() {
        Some(decl) => declarations.push(TypeAliasDeclaration(decl))
        None => ()
      }
    } else if text == "function" {
      match self.parse_function_decl() {
        Some(decl) => declarations.push(FunctionDeclaration(decl))
        None => ()
      }
    } else if self.at_property_decl() {
      match self.parse_property_decl() {
        Some(binding) =>
          if hidden_at_module_level {
            bindings.push({
              name: hidden_member_name(binding.name),
              type_name: binding.type_name,
              value: binding.value,
              exported: binding.exported,
              abstract_slot: binding.abstract_slot,
            })
          } else {
            bindings.push(binding)
          }
        None => ()
      }
    } else if is_decl_text(text) {
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
    program: {
      module_name,
      module_relation,
      imports,
      declarations,
      bindings,
      body,
    },
    diagnostics: self.diagnostics,
    unsupported_syntax: self.unsupported_syntax,
  }
}

///|
fn Parser::parse_module_decl(self : Parser) -> ParsedModuleDecl? {
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
  let mut module_relation : ModuleRelation? = None
  self.skip_whitespace()
  if self.at_text("extends") || self.at_text("amends") {
    let kind = if self.at_text("amends") { ModuleAmends } else { ModuleExtends }
    ignore(self.bump())
    self.skip_whitespace()
    let uri = if self.at(string_token()) {
      unquote(self.bump().text())
    } else if self.at(lparen()) {
      self.skip_balanced_group(lparen(), rparen())
      ""
    } else {
      self.skip_unknown_member()
      ""
    }
    if uri != "" {
      module_relation = Some({ kind, uri })
    }
  }
  self.builder.finish_node()
  let text = buf.to_string()
  let parsed_name = if text == "" { None } else { Some(text) }
  if parsed_name is None && module_relation is None {
    None
  } else {
    Some({ module_name: parsed_name, module_relation })
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
    self.parse_empty_unsupported_expr()
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: false, abstract_slot: false })
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
    self.parse_empty_unsupported_expr()
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: false, abstract_slot: false })
  }
}

///|
/// PKL-140: property-level type annotation that accepts function types
/// (`(A, B) -> R`). The standard `parse_type_annotation` stops at `->`
/// so call sites that follow with a lambda body (`fn parameter type`)
/// don't accidentally swallow the arrow. Property declarations end
/// with `=` / `{`, so function types are unambiguous here.
fn Parser::parse_property_type_annotation(self : Parser) -> String? {
  self.skip_whitespace()
  if !self.at(colon()) {
    return None
  }
  ignore(self.bump())
  self.skip_whitespace()
  let type_name = self.parse_type_text(
    stop_at_arrow=false,
    stop_at_expression_operator=false,
  )
  if type_name == "" {
    None
  } else {
    Some(type_name)
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
  let type_name = self.parse_type_text(
    stop_at_arrow=true,
    stop_at_expression_operator=false,
  )
  if type_name == "" {
    None
  } else {
    Some(type_name)
  }
}

///|
fn Parser::at_type_expression_boundary(self : Parser) -> Bool {
  self.at(or_or()) ||
  self.at(and_and()) ||
  self.at(coalesce()) ||
  self.at(pipe_forward()) ||
  self.at(equal_equal()) ||
  self.at(not_equal()) ||
  self.at(lte()) ||
  self.at(gte()) ||
  self.at(plus()) ||
  self.at(minus()) ||
  self.at(star()) ||
  self.at(slash()) ||
  self.at(percent()) ||
  self.at(int_div()) ||
  self.at(pow())
}

///|
fn Parser::parse_type_text(
  self : Parser,
  stop_at_arrow~ : Bool,
  stop_at_expression_operator~ : Bool,
) -> String {
  let buf = StringBuilder::new()
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  while !self.at(eof()) {
    if parens == 0 && brackets == 0 && angles == 0 {
      if self.at(eq()) ||
        self.at(lbrace()) ||
        self.at(rbrace()) ||
        self.at(comma()) ||
        (stop_at_arrow && self.at(arrow())) ||
        (stop_at_expression_operator && self.at_type_expression_boundary()) ||
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
    } else if parens == 0 && brackets == 0 && self.at(lt()) {
      angles += 1
    } else if parens == 0 && brackets == 0 && self.at(gt()) {
      if angles == 0 {
        break
      }
      angles -= 1
    }
    let tok = self.bump()
    if !is_trivia(tok.kind()) {
      buf.write_string(tok.text())
    }
  }
  buf.to_string()
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
fn Parser::parse_class_decl(self : Parser) -> ClassDecl? {
  self.builder.start_node(class_decl())
  self.expect_text("class", "class")
  let name = match self.expect(identifier(), "class name") {
    Some(tok) => tok.text()
    None => ""
  }
  // PKL-089: optional type parameter list immediately after the class
  // name (`class Box<T, U>`). The parser collects the parameter names so
  // the AST records them, but downstream stages treat the names as
  // `UnknownType` for now — binding-at-instantiation lands with PKL-090.
  // PKL-116: each parameter may carry a `: <bound>` suffix
  // (`class Box<T : Number>`); the bound expression is recorded as a raw
  // type text and the typechecker enforces it at call sites.
  let type_parameters : Array[String] = []
  let type_parameter_bounds : Array[String?] = []
  self.skip_whitespace()
  if self.at_text("<") {
    ignore(self.bump())
    let mut more = true
    while more {
      self.skip_whitespace()
      // PKL-140: Apple Pkl supports variance modifiers `<in T>` / `<out T>`
      // on type parameters. `in` is a keyword token (`in_kw`) and would
      // trip `expect(identifier())`; skip it here so the parameter name
      // parses. pkl-mbt is fully invariant under the hood — the modifier
      // is recorded as parsed but doesn't influence the typechecker.
      if self.at(in_kw()) || self.at_text("out") {
        ignore(self.bump())
        self.skip_whitespace()
      }
      match self.expect(identifier(), "type parameter") {
        Some(tok) => type_parameters.push(tok.text())
        None => type_parameters.push("")
      }
      self.skip_whitespace()
      if self.at(colon()) {
        ignore(self.bump())
        self.skip_whitespace()
        let bound = self.parse_type_text(
          stop_at_arrow=true,
          stop_at_expression_operator=true,
        )
        if bound == "" {
          type_parameter_bounds.push(None)
        } else {
          type_parameter_bounds.push(Some(bound))
        }
      } else {
        type_parameter_bounds.push(None)
      }
      self.skip_whitespace()
      if self.at_text(",") {
        ignore(self.bump())
      } else {
        more = false
      }
    }
    self.skip_whitespace()
    if self.at_text(">") {
      ignore(self.bump())
    }
  }
  let mut parent_name : String? = None
  while !self.at(eof()) && !self.at(lbrace()) {
    if is_separator(self.peek_kind()) || self.at(rbrace()) {
      break
    }
    if self.at_text("extends") {
      ignore(self.bump())
      self.skip_whitespace()
      let parsed_parent = self.parse_type_text(
        stop_at_arrow=false,
        stop_at_expression_operator=false,
      )
      if parsed_parent != "" {
        parent_name = Some(parsed_parent)
      }
    } else {
      ignore(self.bump())
    }
  }
  let properties : Array[ClassProperty] = []
  let methods : Array[FunctionDecl] = []
  if self.at(lbrace()) {
    ignore(self.bump())
    self.consume_separators()
    while !self.at(eof()) && !self.at(rbrace()) {
      self.skip_member_header()
      if self.at_text("function") {
        match self.parse_function_decl() {
          Some(class_method) => methods.push(class_method)
          None => ()
        }
      } else if self.at_property_decl() {
        match self.parse_class_property_decl() {
          Some(property) => properties.push(property)
          None => ()
        }
      } else {
        self.skip_unknown_member()
      }
      self.consume_separators()
    }
    ignore(self.expect(rbrace(), "}"))
  } else {
    self.skip_unknown_member()
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({
      name,
      type_parameters,
      type_parameter_bounds,
      parent_name,
      properties,
      methods,
    })
  }
}

///|
fn Parser::parse_class_property_decl(self : Parser) -> ClassProperty? {
  self.builder.start_node(property_decl())
  if !self.at(identifier()) {
    self.skip_unknown_member()
    self.builder.finish_node()
    return None
  }
  let name = match self.expect(identifier(), "class property name") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_property_type_annotation()
  let value = if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    Some(self.parse_object_body())
  } else if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    Some(self.parse_expr())
  } else {
    None
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value })
  }
}

///|
fn Parser::parse_typealias_decl(self : Parser) -> TypeAliasDecl? {
  self.builder.start_node(typealias_decl())
  self.expect_text("typealias", "typealias")
  let name = match self.expect(identifier(), "typealias name") {
    Some(tok) => tok.text()
    None => ""
  }
  // PKL-115: optional type parameter list `<T1, T2, ...>` immediately
  // after the alias name. Same shape as the class / function parameter
  // scope from PKL-089 / PKL-090. Names are recorded on the AST and the
  // typechecker substitutes them into `target` when an instantiation
  // site (`Box<Int>`) is resolved.
  let type_parameters : Array[String] = []
  self.skip_whitespace()
  if self.at_text("<") {
    ignore(self.bump())
    let mut more = true
    while more {
      self.skip_whitespace()
      // PKL-140: variance modifiers `<in T>` / `<out T>` on typealias type
      // parameters. Apple Pkl's `typealias NonNull = Any(...)` etc.
      if self.at(in_kw()) || self.at_text("out") {
        ignore(self.bump())
        self.skip_whitespace()
      }
      match self.expect(identifier(), "type parameter") {
        Some(tok) => type_parameters.push(tok.text())
        None => ()
      }
      self.skip_whitespace()
      if self.at_text(",") {
        ignore(self.bump())
      } else {
        more = false
      }
    }
    self.skip_whitespace()
    self.expect_text(">", "closing >")
  }
  let target = if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    // Apple Pkl allows the typealias RHS to start on the next line
    // (`typealias Foo =\n  String(...)`). Skip trivia (including
    // newlines) so the type-text parser starts at the first significant
    // token regardless of formatting.
    self.skip_trivia()
    self.parse_type_text(stop_at_arrow=false, stop_at_expression_operator=false)
  } else {
    ""
  }
  self.builder.finish_node()
  if name == "" || target == "" {
    None
  } else {
    Some({ name, type_parameters, target })
  }
}

///|
fn Parser::parse_function_parameter(self : Parser) -> FunctionParameter? {
  if !self.at(identifier()) {
    return None
  }
  let name = self.bump().text()
  let type_name = self.parse_type_annotation()
  Some({ name, type_name })
}

///|
fn Parser::parse_function_decl(self : Parser) -> FunctionDecl? {
  self.builder.start_node(function_decl())
  self.expect_text("function", "function")
  let name = match self.expect(identifier(), "function name") {
    Some(tok) => tok.text()
    None => ""
  }
  // PKL-090: optional type parameter list `<T1, T2, ...>` immediately
  // after the function name. Same shape and intent as the class
  // parameter scope: names are recorded on the AST and the typechecker
  // binds them to UnknownType inside the body.
  // PKL-116: each parameter may carry a `: <bound>` suffix
  // (`function pick<T : Number>(x: T) = ...`) recorded in
  // `type_parameter_bounds`; the typechecker enforces the bound at
  // call sites.
  let type_parameters : Array[String] = []
  let type_parameter_bounds : Array[String?] = []
  self.skip_whitespace()
  if self.at_text("<") {
    ignore(self.bump())
    let mut more = true
    while more {
      self.skip_whitespace()
      // PKL-140: variance modifiers `<in T>` / `<out T>` — skip before the
      // identifier parse (matches the class-decl path).
      if self.at(in_kw()) || self.at_text("out") {
        ignore(self.bump())
        self.skip_whitespace()
      }
      match self.expect(identifier(), "type parameter") {
        Some(tok) => type_parameters.push(tok.text())
        None => type_parameters.push("")
      }
      self.skip_whitespace()
      if self.at(colon()) {
        ignore(self.bump())
        self.skip_whitespace()
        let bound = self.parse_type_text(
          stop_at_arrow=true,
          stop_at_expression_operator=true,
        )
        if bound == "" {
          type_parameter_bounds.push(None)
        } else {
          type_parameter_bounds.push(Some(bound))
        }
      } else {
        type_parameter_bounds.push(None)
      }
      self.skip_whitespace()
      if self.at_text(",") {
        ignore(self.bump())
      } else {
        more = false
      }
    }
    self.skip_whitespace()
    if self.at_text(">") {
      ignore(self.bump())
    }
  }
  let parameters : Array[FunctionParameter] = []
  self.skip_whitespace()
  if self.at(lparen()) {
    ignore(self.bump())
    self.skip_whitespace()
    while !self.at(eof()) && !self.at(rparen()) {
      match self.parse_function_parameter() {
        Some(parameter) => parameters.push(parameter)
        None =>
          if self.at(comma()) {
            ignore(self.bump())
          } else {
            ignore(self.bump())
          }
      }
      self.skip_whitespace()
      if self.at(comma()) {
        ignore(self.bump())
        self.skip_whitespace()
      }
    }
    ignore(self.expect(rparen(), ")"))
  }
  let return_type_name = self.parse_type_annotation()
  let body = if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    Some(self.parse_expr())
  } else {
    None
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({
      name,
      type_parameters,
      type_parameter_bounds,
      parameters,
      return_type_name,
      body,
    })
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
  let type_name = self.parse_property_type_annotation()
  // PKL-140: a property declared without a `{` body and without `=`
  // is an abstract / external slot (`foo: Int?` / `external minInt: Int`).
  // Apple Pkl uses this in stdlib modules for host-bound or
  // subclass-filled properties. Mark the binding as abstract and skip
  // it at the evaluator (no value to render); only the type record
  // survives for typecheck purposes.
  let mut abstract_slot = false
  let value = if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    // PKL-137: `name { body }` (no `=`, brace body) is Apple Pkl's
    // *amend* form — the body's shape depends on the existing value
    // of `name` (Listing → bare elements, Mapping → `[k] = v` entries,
    // object → property decls). The parser doesn't know the existing
    // type at this point, so dispatch by peeking the first significant
    // token inside the brace, the same way PKL-138 does for
    // `new { ... }`.
    self.parse_inferred_new_body()
  } else if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else {
    abstract_slot = true
    NullLiteral
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, exported: true, abstract_slot })
  }
}

///|
fn Parser::parse_expr(self : Parser) -> Expr {
  self.parse_null_coalesce_expr()
}

///|
fn Parser::parse_binary_loop(
  self : Parser,
  parse_operand : () -> Expr,
  operators : () -> BinaryOp?,
) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = parse_operand()
  let mut maybe_op = operators()
  while maybe_op is Some(op) {
    self.builder.start_node_at(checkpoint, binary_expr())
    ignore(self.bump())
    let right = parse_operand()
    self.builder.finish_node()
    left = BinaryExpr(op, left, right)
    maybe_op = operators()
  }
  left
}

///|
fn Parser::parse_null_coalesce_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let left = self.parse_pipe_expr()
  self.skip_whitespace()
  if self.at(coalesce()) {
    self.builder.start_node_at(checkpoint, binary_expr())
    ignore(self.bump())
    let right = self.parse_null_coalesce_expr()
    self.builder.finish_node()
    BinaryExpr(NullCoalesce, left, right)
  } else {
    left
  }
}

///|
fn Parser::parse_pipe_expr(self : Parser) -> Expr {
  self.parse_binary_loop(fn() { self.parse_or_expr() }, fn() {
    self.skip_whitespace()
    if self.at(pipe_forward()) {
      Some(Pipe)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_or_expr(self : Parser) -> Expr {
  self.parse_binary_loop(fn() { self.parse_and_expr() }, fn() {
    self.skip_whitespace()
    if self.at(or_or()) {
      Some(Or)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_and_expr(self : Parser) -> Expr {
  self.parse_binary_loop(fn() { self.parse_equality_expr() }, fn() {
    self.skip_whitespace()
    if self.at(and_and()) {
      Some(And)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_equality_expr(self : Parser) -> Expr {
  self.parse_binary_loop(fn() { self.parse_comparison_expr() }, fn() {
    self.skip_whitespace()
    if self.at(equal_equal()) {
      Some(Equal)
    } else if self.at(not_equal()) {
      Some(NotEqual)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_comparison_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = self.parse_add_expr()
  let mut keep_going = true
  while keep_going {
    self.skip_whitespace()
    let op : BinaryOp? = if self.at(lt()) {
      Some(LessThan)
    } else if self.at(lte()) {
      Some(LessOrEqual)
    } else if self.at(gt()) {
      Some(GreaterThan)
    } else if self.at(gte()) {
      Some(GreaterOrEqual)
    } else if self.at(is_kw()) {
      Some(Is)
    } else if self.at(as_kw()) {
      Some(As)
    } else {
      None
    }
    match op {
      Some(actual_op) => {
        self.builder.start_node_at(checkpoint, binary_expr())
        ignore(self.bump())
        let right = match actual_op {
          Is | As => self.parse_type_operand_expr()
          _ => self.parse_add_expr()
        }
        self.builder.finish_node()
        left = BinaryExpr(actual_op, left, right)
      }
      None => keep_going = false
    }
  }
  left
}

///|
fn Parser::parse_type_operand_expr(self : Parser) -> Expr {
  self.skip_trivia()
  if self.at(identifier()) {
    self.builder.start_node(name_ref())
    let type_name = self.parse_type_text(
      stop_at_arrow=false,
      stop_at_expression_operator=true,
    )
    self.builder.finish_node()
    Identifier(type_name)
  } else {
    self.parse_add_expr()
  }
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
  let mut left = self.parse_power_expr()
  while ({
          self.skip_whitespace()
          self.at(star()) ||
          self.at(slash()) ||
          self.at(percent()) ||
          self.at(int_div())
        }) {
    self.builder.start_node_at(checkpoint, binary_expr())
    let op = if self.at(star()) {
      BinaryOp::Multiply
    } else if self.at(slash()) {
      BinaryOp::Divide
    } else if self.at(percent()) {
      BinaryOp::Modulo
    } else {
      BinaryOp::IntDivide
    }
    ignore(self.bump())
    let right = self.parse_power_expr()
    self.builder.finish_node()
    left = BinaryExpr(op, left, right)
  }
  left
}

///|
fn Parser::parse_power_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let left = self.parse_unary_expr()
  self.skip_whitespace()
  if self.at(pow()) {
    self.builder.start_node_at(checkpoint, binary_expr())
    ignore(self.bump())
    let right = self.parse_power_expr()
    self.builder.finish_node()
    BinaryExpr(Power, left, right)
  } else {
    left
  }
}

///|
fn Parser::parse_unary_expr(self : Parser) -> Expr {
  self.skip_trivia()
  if self.at(minus()) || self.at(bang()) {
    self.builder.start_node(unary_expr())
    let op = if self.at(minus()) { Negate } else { Not }
    ignore(self.bump())
    let expr = self.parse_unary_expr()
    self.builder.finish_node()
    UnaryExpr(op, expr)
  } else {
    self.parse_postfix_expr()
  }
}

///|
fn Parser::parse_postfix_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut expr = self.parse_primary_expr()
  let mut keep_going = true
  while keep_going {
    // Apple Pkl accepts dot-chains broken across lines:
    //   xs
    //     .toList()
    //     .map((x) -> x + 1)
    // Peek past trivia (whitespace + newline + comment) — if the next
    // significant token is `.` / `?.`, advance the cursor past the trivia
    // and continue the chain. Otherwise stay put so the newline keeps its
    // role as a statement separator.
    let trivia_end = self.skip_trivia_from(self.pos)
    let next_kind = if trivia_end >= self.len {
      eof()
    } else {
      self.tokens[trivia_end].kind()
    }
    if next_kind == dot() || next_kind == qdot() {
      self.pos = trivia_end
    } else {
      self.skip_whitespace()
    }
    if self.at(dot()) || self.at(qdot()) {
      let unsupported_start = self.current_offset()
      let safe = self.at(qdot())
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
        self.record_unsupported_syntax(
          unsupported_start,
          self.current_offset(),
          kind_name(unsupported_expr()),
        )
        UnsupportedExpr
      } else if safe {
        SafeMemberAccess(expr, field_name)
      } else {
        MemberAccess(expr, field_name)
      }
    } else if self.at(lparen()) {
      self.builder.start_node_at(checkpoint, call_expr())
      ignore(self.bump())
      let arguments : Array[Expr] = []
      self.skip_whitespace()
      while !self.at(eof()) && !self.at(rparen()) {
        arguments.push(self.parse_expr())
        self.skip_whitespace()
        if !self.at(comma()) && !self.at(rparen()) {
          self.skip_call_argument_tail()
          self.skip_whitespace()
        }
        if self.at(comma()) {
          ignore(self.bump())
          self.skip_whitespace()
        } else {
          break
        }
      }
      self.skip_whitespace()
      if self.at(rparen()) {
        ignore(self.bump())
      } else {
        self.builder.token(error_kind(), "")
      }
      self.builder.finish_node()
      expr = CallExpr(expr, arguments)
    } else if self.at(lbracket()) {
      self.builder.start_node_at(checkpoint, subscript_access())
      ignore(self.bump())
      let key = self.parse_expr()
      ignore(self.expect(rbracket(), "]"))
      self.builder.finish_node()
      expr = SubscriptAccess(expr, key)
    } else if self.at(lbrace()) {
      self.builder.start_node_at(checkpoint, amend_expr())
      let members = self.parse_object_body_members()
      self.builder.finish_node()
      expr = AmendExpr(expr, members)
    } else if self.at(non_null()) {
      self.builder.start_node_at(checkpoint, unary_expr())
      ignore(self.bump())
      self.builder.finish_node()
      expr = NonNullExpr(expr)
    } else if self.at(question()) {
      let unsupported_start = self.current_offset()
      ignore(self.bump())
      self.record_unsupported_syntax(
        unsupported_start,
        self.current_offset(),
        kind_name(unsupported_expr()),
      )
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
    kind if kind == float_token() => {
      // PKL-092: Float literal. The decimal form is `<digits>.<digits>`;
      // exponent forms (`1e10`, `2.5e-3`) are deferred — adding them only
      // touches the lexer / parser, the evaluator already handles
      // `Double` arithmetic uniformly.
      self.builder.start_node(literal_expr())
      let tok = self.bump()
      self.builder.finish_node()
      FloatLiteral(parse_float_text(tok.text()))
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
      self.builder.start_node(name_ref())
      let tok = self.bump()
      self.builder.finish_node()
      Identifier(tok.text())
    }
    // Apple Pkl: `module.foo` is a self-reference to the current module's
    // `foo` binding. Parse as `Identifier("module")` so the postfix `.foo`
    // chain attaches; the evaluator special-cases lookups on the
    // `module` identifier to resolve from the module-level binding set.
    kind if kind == module_kw() => {
      self.builder.start_node(name_ref())
      ignore(self.bump())
      self.builder.finish_node()
      Identifier("module")
    }
    kind if kind == import_kw() => self.parse_import_expr()
    kind if kind == new_kw() => self.parse_object_expr()
    kind if kind == if_kw() => self.parse_if_expr()
    kind if kind == let_kw() => self.parse_let_expr()
    kind if kind == lparen() => {
      if self.function_literal_at_current() {
        return self.parse_lambda_expr()
      }
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
fn Parser::parse_lambda_expr(self : Parser) -> Expr {
  self.builder.start_node(lambda_expr())
  ignore(self.expect(lparen(), "("))
  let parameters : Array[FunctionParameter] = []
  self.skip_whitespace()
  while !self.at(eof()) && !self.at(rparen()) {
    match self.parse_function_parameter() {
      Some(parameter) => parameters.push(parameter)
      None => ignore(self.bump())
    }
    self.skip_whitespace()
    if self.at(comma()) {
      ignore(self.bump())
      self.skip_whitespace()
    }
  }
  ignore(self.expect(rparen(), ")"))
  let return_type_name = self.parse_type_annotation()
  ignore(self.expect(arrow(), "->"))
  let body = self.parse_expr()
  self.builder.finish_node()
  LambdaExpr(parameters, body, return_type_name)
}

///|
/// Parse `let (name = value) body` and desugar it into `((name) -> body)(value)`.
/// Keeping the desugar at the parser level means the rest of the evaluator
/// continues to operate on the same `LambdaExpr` + `CallExpr` shape that
/// already implements scoping and closure capture.
fn Parser::parse_let_expr(self : Parser) -> Expr {
  self.builder.start_node(let_decl())
  ignore(self.expect(let_kw(), "let"))
  self.skip_whitespace()
  ignore(self.expect(lparen(), "("))
  self.skip_whitespace()
  let name = match self.expect(identifier(), "identifier") {
    Some(tok) => tok.text()
    None => ""
  }
  let type_name = self.parse_type_annotation()
  self.skip_whitespace()
  ignore(self.expect(eq(), "="))
  let value = self.parse_expr()
  self.skip_whitespace()
  ignore(self.expect(rparen(), ")"))
  let body = self.parse_expr()
  self.builder.finish_node()
  if name == "" {
    return UnsupportedExpr
  }
  CallExpr(LambdaExpr([{ name, type_name }], body, None), [value])
}

///|
fn Parser::parse_if_expr(self : Parser) -> Expr {
  self.builder.start_node(conditional_expr())
  ignore(self.expect(if_kw(), "if"))
  ignore(self.expect(lparen(), "("))
  let condition = self.parse_expr()
  ignore(self.expect(rparen(), ")"))
  let then_expr = self.parse_expr()
  self.skip_trivia()
  ignore(self.expect(else_kw(), "else"))
  let else_expr = self.parse_expr()
  self.builder.finish_node()
  ConditionalExpr(condition, then_expr, else_expr)
}

///|
fn Parser::parse_unsupported_expr(self : Parser) -> Expr {
  self.builder.start_node(unsupported_expr())
  let mut parens = 0
  let mut braces = 0
  let mut brackets = 0
  let mut consumed = false
  self.skip_trivia()
  let unsupported_start = self.current_offset()
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
  self.record_unsupported_syntax(
    unsupported_start,
    self.current_offset(),
    kind_name(unsupported_expr()),
  )
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
  let type_name = self.parse_type_text(
    stop_at_arrow=false,
    stop_at_expression_operator=false,
  )
  // PKL-136 drive-by: `new Listing<T> { ... }` previously fell into the
  // TypedObjectLiteral arm because `parse_type_text` returns the full
  // generic form (`Listing<String>`). Normalise the prefix so the body
  // parses as a listing / mapping body either way.
  let value = if type_name == "Listing" ||
    type_name.has_prefix("Listing<") ||
    type_name == "List" ||
    type_name.has_prefix("List<") {
    self.parse_listing_body()
  } else if type_name == "Mapping" || type_name.has_prefix("Mapping<") {
    self.parse_mapping_body()
  } else if type_name == "" {
    // PKL-138: peek the first significant token inside `{` to decide
    // whether `new { ... }` is a listing, mapping, or object body. The
    // binding's type annotation isn't visible at parse time, so we
    // infer from the body's first item shape.
    self.parse_inferred_new_body()
  } else {
    TypedObjectLiteral(type_name, self.parse_object_body_members())
  }
  self.builder.finish_node()
  value
}

///|
/// PKL-138: dispatch `new { ... }` (no explicit type) by peeking the
/// first significant token inside the body brace.
///
/// - First token `[` → Mapping body (`new { ["a"] = 1 }`)
/// - First token starts a property decl (`ident =` / `ident :` / `ident {`)
///   or a visibility / control keyword (`local`, `hidden`, `fixed`, `when`,
///   `for`) → Object body
/// - First token `}` (empty body) → Object body (the eval coerces to the
///   empty Listing / Mapping if the binding's annotation requires it)
/// - Otherwise (bare expression: literal, `(`, `new`, unary operator,
///   identifier-without-property-suffix) → Listing body
fn Parser::parse_inferred_new_body(self : Parser) -> Expr {
  self.skip_whitespace()
  if !self.at(lbrace()) {
    return self.parse_object_body()
  }
  let first_idx = self.skip_trivia_from(self.pos + 1)
  let first = if first_idx >= self.len {
    eof()
  } else {
    self.tokens[first_idx].kind()
  }
  let first_text = if first_idx >= self.len {
    ""
  } else {
    self.tokens[first_idx].text()
  }
  if first == lbracket() {
    self.parse_mapping_body()
  } else if first == rbrace() ||
    first == when_kw() ||
    first == for_kw() ||
    first == local_kw() ||
    self.at_property_decl_from(first_idx) ||
    // `hidden` / `fixed` are identifiers token-wise but mark a
    // property declaration when they precede an identifier.
    (
      (first_text == "hidden" || first_text == "fixed") &&
      self.at_property_decl_from(self.skip_trivia_from(first_idx + 1))
    ) {
    self.parse_object_body()
  } else {
    self.parse_listing_body()
  }
}

///|
/// Helper: skip trivia tokens starting at `start` and return the next
/// significant token index.
fn Parser::skip_trivia_from(self : Parser, start : Int) -> Int {
  let mut i = start
  while i < self.len && is_trivia(self.tokens[i].kind()) {
    i += 1
  }
  i
}

///|
fn Parser::parse_listing_body(self : Parser) -> Expr {
  self.builder.start_node(listing_expr())
  ignore(self.expect(lbrace(), "{"))
  let elements : Array[Expr] = []
  self.consume_separators()
  while !self.at(eof()) && !self.at(rbrace()) {
    self.skip_member_header()
    if self.at(when_kw()) {
      // PKL-136: `when (cond) { ... } [else { ... }]` inside a Listing body.
      // The branches re-parse as Listing bodies so the wrapped Expr stays
      // ListingLiteral on both sides; the spread happens at eval time.
      elements.push(self.parse_listing_when())
    } else if self.at(local_kw()) ||
      self.at(lbracket()) ||
      self.at_property_decl() ||
      is_decl_text(self.peek().text()) {
      self.skip_unknown_member()
    } else {
      elements.push(self.parse_expr())
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  self.builder.finish_node()
  ListingLiteral(elements)
}

///|
/// PKL-136: parse a `when (cond) { ... } [else { ... }]` block whose
/// branches are listing bodies. Returns `WhenSpread(ConditionalExpr(cond,
/// then_listing, else_listing))` so the listing evaluator can spread the
/// selected branch's elements into the parent listing.
fn Parser::parse_listing_when(self : Parser) -> Expr {
  ignore(self.expect(when_kw(), "when"))
  self.skip_whitespace()
  ignore(self.expect(lparen(), "("))
  let condition = self.parse_expr()
  self.skip_whitespace()
  ignore(self.expect(rparen(), ")"))
  self.skip_whitespace()
  let then_branch = self.parse_listing_body()
  self.consume_separators()
  let else_branch : Expr = if self.at(else_kw()) {
    ignore(self.bump())
    self.skip_whitespace()
    self.parse_listing_body()
  } else {
    ListingLiteral([])
  }
  WhenSpread(ConditionalExpr(condition, then_branch, else_branch))
}

///|
fn Parser::parse_mapping_body(self : Parser) -> Expr {
  self.builder.start_node(mapping_expr())
  ignore(self.expect(lbrace(), "{"))
  let entries : Array[MappingEntry] = []
  self.consume_separators()
  while !self.at(eof()) && !self.at(rbrace()) {
    self.skip_member_header()
    if self.at(when_kw()) {
      // PKL-136: `when (cond) { ["k"] = v; ... } [else { ... }]` inside a
      // Mapping body. The wrapper is a synthetic MappingEntry whose key is
      // `WhenSpread(ConditionalExpr(cond, then_mapping, else_mapping))`;
      // `value` is `NullLiteral` (never consulted — the evaluator spreads
      // the selected branch's entries before reading any value).
      entries.push({ key: self.parse_mapping_when(), value: NullLiteral })
    } else if self.at(lbracket()) {
      match self.parse_mapping_entry() {
        Some(entry) => entries.push(entry)
        None => ()
      }
    } else {
      self.skip_unknown_member()
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  self.builder.finish_node()
  MappingLiteral(entries)
}

///|
/// PKL-136: parse a `when (cond) { ... } [else { ... }]` block whose
/// branches are Mapping bodies. Returns `WhenSpread(ConditionalExpr(cond,
/// then_mapping, else_mapping))`.
fn Parser::parse_mapping_when(self : Parser) -> Expr {
  ignore(self.expect(when_kw(), "when"))
  self.skip_whitespace()
  ignore(self.expect(lparen(), "("))
  let condition = self.parse_expr()
  self.skip_whitespace()
  ignore(self.expect(rparen(), ")"))
  self.skip_whitespace()
  let then_branch = self.parse_mapping_body()
  self.consume_separators()
  let else_branch : Expr = if self.at(else_kw()) {
    ignore(self.bump())
    self.skip_whitespace()
    self.parse_mapping_body()
  } else {
    MappingLiteral([])
  }
  WhenSpread(ConditionalExpr(condition, then_branch, else_branch))
}

///|
fn Parser::parse_mapping_entry(self : Parser) -> MappingEntry? {
  self.builder.start_node(mapping_entry())
  ignore(self.expect(lbracket(), "["))
  let key = self.parse_expr()
  ignore(self.expect(rbracket(), "]"))
  let value = if ({
      self.skip_whitespace()
      self.at(eq())
    }) {
    ignore(self.bump())
    self.parse_expr()
  } else if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    self.parse_object_body()
  } else {
    self.parse_empty_unsupported_expr()
  }
  self.builder.finish_node()
  Some({ key, value })
}

///|
fn Parser::parse_object_body(self : Parser) -> Expr {
  ObjectLiteral(self.parse_object_body_members())
}

///|
fn Parser::parse_object_body_members(self : Parser) -> Array[ObjectMember] {
  ignore(self.expect(lbrace(), "{"))
  let members : Array[ObjectMember] = []
  self.consume_separators()
  while !self.at(eof()) && !self.at(rbrace()) {
    let hidden = self.consume_member_visibility_modifiers()
    self.skip_member_header()
    if self.at(when_kw()) {
      match self.parse_when_member() {
        Some(field) => members.push(field)
        None => ()
      }
    } else if self.at(for_kw()) {
      match self.parse_for_member() {
        Some(field) => members.push(field)
        None => ()
      }
    } else if self.at_property_decl() {
      match self.parse_object_member() {
        Some(field) =>
          if hidden {
            members.push({
              name: hidden_member_name(field.name),
              type_name: field.type_name,
              value: field.value,
            })
          } else {
            members.push(field)
          }
        None => ()
      }
    } else {
      self.skip_unknown_member()
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  members
}

///|
/// Consume any leading `hidden` / `local` visibility modifiers on the next
/// object-body member. Returns `true` when at least one was seen so the
/// caller knows to mark the produced `ObjectMember` with the hidden-name
/// prefix.
///
/// `hidden` is a modifier-text identifier (the lexer keeps it as a regular
/// identifier; `is_modifier_text` recognises it later). `local` is a
/// dedicated keyword (`local_kw`) introduced for top-level local
/// declarations. Both are stripped here before `skip_member_header` runs
/// its annotation / modifier loop so other modifiers (`const`, `fixed`,
/// `abstract`, etc.) can still pass through.
fn Parser::consume_member_visibility_modifiers(self : Parser) -> Bool {
  let mut hidden = false
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(local_kw()) {
      hidden = true
      ignore(self.bump())
    } else if self.at(identifier()) && self.peek().text() == "hidden" {
      hidden = true
      ignore(self.bump())
    } else {
      keep_going = false
    }
  }
  hidden
}

///|
/// Module-level variant: only consumes the `hidden` identifier modifier.
/// `local` at module level keeps its existing role as a binding-declaration
/// keyword (it routes through `parse_local_decl`, which already marks the
/// binding `exported: false`); consuming it here would strand the parser
/// in an inconsistent state. `hidden` at module level still needs the
/// prefix marker because the binding stays `exported: true`.
fn Parser::consume_module_visibility_modifiers(self : Parser) -> Bool {
  let mut hidden = false
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(identifier()) && self.peek().text() == "hidden" {
      hidden = true
      ignore(self.bump())
    } else {
      keep_going = false
    }
  }
  hidden
}

///|
/// Reserved prefix used to mark hidden / local object members. The lexer
/// rejects `@` and `$` in identifiers, so the prefix can never collide with
/// a user-declared property name. Renderers skip members whose name starts
/// with this prefix; `lookup_member` resolves either the bare or prefixed
/// form so reads from the same value see the hidden member transparently.
pub let hidden_member_prefix : String = "@hidden$"

///|
pub fn hidden_member_name(name : String) -> String {
  hidden_member_prefix + name
}

///|
pub fn is_hidden_member_name(name : String) -> Bool {
  name.has_prefix(hidden_member_prefix)
}

///|
/// Parse `when (cond) { ... } [else { ... }]` inside an object body.
///
/// The branches are rendered as `ObjectLiteral`s so they share the rest of
/// the evaluator's object-body machinery (property defaults, nested
/// when-conditionals, amend expressions, etc.). The whole construct is
/// encoded as a synthetic `ObjectMember` with the reserved name `@when` and
/// a `ConditionalExpr` value; `eval_object_members` recognises the reserved
/// name and spreads the resulting `ObjectValue`'s members into the parent
/// instead of attaching them under the reserved key.
fn Parser::parse_when_member(self : Parser) -> ObjectMember? {
  self.builder.start_node(object_member())
  ignore(self.expect(when_kw(), "when"))
  self.skip_whitespace()
  ignore(self.expect(lparen(), "("))
  let condition = self.parse_expr()
  self.skip_whitespace()
  ignore(self.expect(rparen(), ")"))
  self.skip_whitespace()
  let then_members = self.parse_object_body_members()
  self.consume_separators()
  let else_members : Array[ObjectMember] = if self.at(else_kw()) {
    ignore(self.bump())
    self.skip_whitespace()
    self.parse_object_body_members()
  } else {
    []
  }
  self.builder.finish_node()
  Some({
    name: "@when",
    type_name: None,
    value: ConditionalExpr(
      condition,
      ObjectLiteral(then_members),
      ObjectLiteral(else_members),
    ),
  })
}

///|
/// Parse `for (var [, var2] in source) { ... }` inside an object body.
///
/// The body's members are kept as `Array[ObjectMember]` so the iteration
/// step can re-evaluate each member against the per-iteration cache (with
/// the loop variables bound). The construct is encoded as a synthetic
/// `@for` object member whose value is a `ForGenerator` expression;
/// `eval_object_members` recognises the reserved name, iterates the source
/// via `eval_expr_with_bindings`, and spreads the per-iteration members
/// into the parent.
fn Parser::skip_for_binding_type_annotation(self : Parser) -> Unit {
  self.skip_whitespace()
  if !self.at(colon()) {
    return
  }
  ignore(self.bump())
  // Consume tokens up to (but not including) the next `,` / `in` /
  // `)`, balancing parens / brackets / angles so generic types like
  // `Listing<Pair<Int, Int>>` don't trip over the inner `,`.
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  while !self.at(eof()) {
    if parens == 0 && brackets == 0 && angles == 0 {
      if self.at(comma()) || self.at(in_kw()) || self.at(rparen()) {
        break
      }
    }
    if self.at(lparen()) {
      parens += 1
    } else if self.at(rparen()) {
      parens -= 1
    } else if self.at(lbracket()) {
      brackets += 1
    } else if self.at(rbracket()) {
      brackets -= 1
    } else if self.at(lt()) {
      angles += 1
    } else if self.at(gt()) {
      angles -= 1
    }
    ignore(self.bump())
  }
}

///|
fn Parser::parse_for_member(self : Parser) -> ObjectMember? {
  self.builder.start_node(object_member())
  ignore(self.expect(for_kw(), "for"))
  self.skip_trivia()
  ignore(self.expect(lparen(), "("))
  self.skip_trivia()
  let var1 = match self.expect(identifier(), "for-binding name") {
    Some(tok) => tok.text()
    None => ""
  }
  // Pkl allows a type annotation after each for-binding (`for (n: Int in ...)`)
  // — accept and discard it. We can't use `parse_type_annotation` here
  // because its `parse_type_text` greedily consumes tokens until it sees
  // `=` / `{` / `}` / `,`, which means it would swallow the `in` keyword
  // and the source expression. The custom loop below stops at `,` or `in`.
  self.skip_for_binding_type_annotation()
  self.skip_trivia()
  let var2 : String? = if self.at(comma()) {
    ignore(self.bump())
    self.skip_trivia()
    let name = match self.expect(identifier(), "for-binding name") {
      Some(tok) => tok.text()
      None => ""
    }
    self.skip_for_binding_type_annotation()
    if name == "" {
      None
    } else {
      Some(name)
    }
  } else {
    None
  }
  self.skip_trivia()
  ignore(self.expect(in_kw(), "in"))
  self.skip_trivia()
  let source = self.parse_expr()
  self.skip_trivia()
  ignore(self.expect(rparen(), ")"))
  self.skip_trivia()
  let body_members = self.parse_object_body_members()
  self.builder.finish_node()
  if var1 == "" {
    return None
  }
  Some({
    name: "@for",
    type_name: None,
    value: ForGenerator(var1, var2, source, body_members),
  })
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
    self.parse_empty_unsupported_expr()
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
fn parse_float_text(text : String) -> Double {
  // PKL-092: parse `<int>.<frac>` into a Double by accumulating the
  // integer and fractional parts separately. Sticking to a hand-rolled
  // walk keeps the parser self-contained (no extra core dep) and the
  // lexer guarantees the exact `digit+ . digit+` shape, so there is no
  // need to defend against malformed input here.
  let mut int_part = 0.0
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  let mut in_fraction = false
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
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
  int_part + frac_part
}

///|
fn unquote(text : String) -> String {
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
