///|
priv struct Parser {
  source : String
  tokens : Array[Token]
  len : Int
  mut pos : Int
  // PKL-107: running byte offset into `source`. Maintained incrementally
  // by `bump` / direct `pos` writes so `current_offset` is O(1) instead
  // of summing all preceding token texts on every call (which previously
  // made parser diagnostics-with-positions an O(N) extra cost per emit).
  mut byte_offset : Int
  builder : @cst.GreenNodeBuilder
  diagnostics : Array[Diagnostic]
  unsupported_syntax : Array[UnsupportedSyntax]
  // PKL-128d: annotations consumed by `skip_member_header` accumulate
  // here until the following declaration parser drains them. Bindings
  // / properties that don't capture annotations simply leave the list
  // in place; the next `skip_member_header` resets it before parsing
  // the next member's annotation prefix.
  pending_annotations : Array[Annotation]
  // PKL-117: modifier keywords (`abstract`, `open`, `external`, etc.)
  // captured by `skip_member_header` for the next declaration. Drained
  // by the decl parsers that care (`parse_class_decl` /
  // `parse_function_decl` consult the `abstract` flag); cleared
  // unconditionally by the next `skip_member_header` so a modifier on
  // a binding doesn't leak into the following class declaration.
  pending_modifiers : Array[String]
}

///|
priv struct ParsedModuleDecl {
  module_name : String?
  module_relation : ModuleRelation?
  // PKL-128d: annotations preceding the `module` / `amends` /
  // `extends` keyword. Drained from `pending_annotations` at the
  // start of `parse_module_decl`.
  annotations : Array[Annotation]
}

///|
fn Parser::new(source : String) -> Parser {
  let tokens = tokenize(source)
  Parser::{
    source,
    tokens,
    len: tokens.length(),
    pos: 0,
    byte_offset: 0,
    builder: @cst.GreenNodeBuilder::new(),
    diagnostics: [],
    unsupported_syntax: [],
    pending_annotations: [],
    pending_modifiers: [],
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
/// PKL-148s: `...x` / `...?x` spread member detection. Apple Pkl's
/// `...` is three consecutive `.` tokens (no trivia between them); a
/// trailing `?` lifts it to the nullable form. The dispatch in each
/// of `parse_object_body_members`, `parse_listing_body`, and
/// `parse_mapping_body` consults these helpers before falling through
/// to `skip_unknown_member` so the spread isn't silently dropped.
fn Parser::at_triple_dot(self : Parser) -> Bool {
  self.pos + 2 < self.len &&
  self.tokens[self.pos].kind() == dot() &&
  self.tokens[self.pos + 1].kind() == dot() &&
  self.tokens[self.pos + 2].kind() == dot()
}

///|
/// Consume the leading `...` (and optional `?`) of a spread member.
/// Returns the parsed payload expression. The caller decides which
/// container shape to push the spread into.
fn Parser::parse_spread_payload(self : Parser) -> Expr {
  ignore(self.bump())
  ignore(self.bump())
  ignore(self.bump())
  if self.at(question()) {
    ignore(self.bump())
  }
  self.skip_whitespace()
  self.parse_expr()
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
  let mut brackets = 0
  let mut angles = 0
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
    } else if kind == lbracket() {
      brackets += 1
    } else if kind == rbracket() {
      if brackets > 0 {
        brackets -= 1
      }
    } else if brackets == 0 && kind == lt() {
      angles += 1
    } else if brackets == 0 && kind == gt() {
      if angles > 0 {
        angles -= 1
      }
    } else if depth == 1 &&
      brackets == 0 &&
      angles == 0 &&
      (kind == comma() || kind == colon()) {
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
  // PKL-107: anchor parse errors at the parser's current byte offset
  // so the CLI can project them onto a line:column pair. `end` falls
  // back to `start` because the failing token text isn't always
  // bumped by the time `add_error` fires; that's good enough for
  // pointing at the right line, and refinement can come later.
  let start = self.byte_offset
  self.diagnostics.push({ message, start, end: start })
}

///|
fn Parser::current_offset(self : Parser) -> Int {
  self.byte_offset
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
  self.byte_offset += tok.text().length()
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
/// PKL-148au: skip trivia (whitespace + newline + comment) plus
/// semicolons. Used by the binary-expression continuation peek so
/// `1\n + 2\n / 3` and `1;; + 2; / 3` keep parsing as a single
/// chain (Apple Pkl treats semicolons / newlines as whitespace
/// inside an expression).
fn Parser::skip_trivia_and_semicolons(self : Parser) -> Unit {
  while self.pos < self.len {
    match self.tokens[self.pos].kind().raw() {
      2 | 3 | 4 | 42 => ignore(self.bump())
      _ => return
    }
  }
}

///|
/// PKL-148au: peek past whitespace + newline + comment + semicolon
/// from `start`, returning the next significant token index. Sibling
/// to `skip_trivia_from`. The binary-expression continuation logic
/// uses this to decide whether the upcoming operator should re-enter
/// the chain after a soft separator.
fn Parser::skip_trivia_and_semicolons_from(self : Parser, start : Int) -> Int {
  let mut i = start
  while i < self.len {
    match self.tokens[i].kind().raw() {
      2 | 3 | 4 | 42 => i += 1
      _ => return i
    }
  }
  i
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
/// PKL-128d: capture one `@Name(...)` / `@Name { ... }` / `@Name`
/// annotation into the parser's pending list. The name segment may
/// contain dots (`@my.pkg.Custom`); the body delimiters and verbatim
/// body text are recorded so a downstream tool can re-parse the
/// arguments without scanning back to the open token. Returns true
/// if an annotation was consumed.
fn Parser::parse_annotation(self : Parser) -> Bool {
  if !self.at(at_sign()) {
    return false
  }
  ignore(self.bump())
  let name_buf = StringBuilder::new()
  while self.at(identifier()) || self.at(dot()) {
    name_buf.write_string(self.peek().text())
    ignore(self.bump())
  }
  self.skip_whitespace()
  let class_name = name_buf.to_string()
  let (body_kind, body_text) = if self.at(lparen()) {
    let start = self.current_offset()
    self.skip_balanced_group(lparen(), rparen())
    let end = self.current_offset()
    // `skip_balanced_group` advances past the closing delimiter, so
    // the body lives in (start + 1, end - 1).
    (AnnotationBodyKind::ParenBody, self.source_slice(start + 1, end - 1))
  } else if self.at(lbrace()) {
    let start = self.current_offset()
    self.skip_balanced_group(lbrace(), rbrace())
    let end = self.current_offset()
    (AnnotationBodyKind::BraceBody, self.source_slice(start + 1, end - 1))
  } else {
    (AnnotationBodyKind::NoBody, "")
  }
  self.pending_annotations.push({ class_name, body_kind, body_text })
  true
}

///|
fn Parser::skip_member_header(self : Parser) -> Unit {
  // PKL-128d: clear out any annotations a previous header captured
  // but the following decl parser declined to take, so they don't
  // bleed into the next member.
  self.pending_annotations.clear()
  // PKL-117: same lifecycle for modifier keywords — clear before each
  // header pass so a `abstract` consumed for one member doesn't bleed
  // into the next.
  self.pending_modifiers.clear()
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(at_sign()) {
      ignore(self.parse_annotation())
    } else if self.at(identifier()) && is_modifier_text(self.peek().text()) {
      self.pending_modifiers.push(self.peek().text())
      ignore(self.bump())
    } else {
      keep_going = false
    }
  }
}

///|
/// PKL-128d: drain the pending annotation list and return its
/// contents. Called by decl parsers that want to attach the captured
/// annotations to their AST node; bindings and other consumers that
/// don't need the metadata can ignore it — the next
/// `skip_member_header` will reset the list before parsing the next
/// member.
fn Parser::take_pending_annotations(self : Parser) -> Array[Annotation] {
  let out : Array[Annotation] = []
  for a in self.pending_annotations {
    out.push(a)
  }
  self.pending_annotations.clear()
  out
}

///|
/// PKL-117: drain the pending modifier list and return true when the
/// `abstract` keyword was among them. The bool-returning shape keeps
/// the call site narrow — today the typechecker only cares about
/// `abstract` for inheritance enforcement; richer modifier inspection
/// (`open`, `external`, etc.) can layer in by returning a richer
/// payload later.
fn Parser::take_pending_abstract(self : Parser) -> Bool {
  let mut found = false
  for modifier in self.pending_modifiers {
    if modifier == "abstract" {
      found = true
    }
  }
  self.pending_modifiers.clear()
  found
}

///|
/// PKL-145: drain the pending modifier list and return true when the
/// `hidden` keyword was among them. Parallels `take_pending_abstract`
/// — `parse_class_property_decl` calls this to thread the modifier
/// into the property name via `hidden_member_name`, matching the
/// object-body member path's existing behaviour.
fn Parser::take_pending_hidden(self : Parser) -> Bool {
  let mut found = false
  // Walk in reverse so removals don't shift the iteration window.
  for i = self.pending_modifiers.length() - 1; i >= 0; i = i - 1 {
    if self.pending_modifiers[i] == "hidden" {
      found = true
      let _ = self.pending_modifiers.remove(i)
    }
  }
  found
}

///|
fn Parser::take_pending_const(self : Parser) -> Bool {
  let mut found = false
  for i = self.pending_modifiers.length() - 1; i >= 0; i = i - 1 {
    if self.pending_modifiers[i] == "const" {
      found = true
      let _ = self.pending_modifiers.remove(i)
    }
  }
  found
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
  let mut module_annotations : Array[Annotation] = []
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
          // PKL-128d: the first explicit `module` header in the file
          // owns the captured annotations. Re-parsing of subsequent
          // `module` keywords (which Apple Pkl rejects anyway) would
          // overwrite, but a single header is the well-formed case.
          module_annotations = decl.annotations
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
      // PKL-148m: a `local` modifier in front of a class / function /
      // typealias declaration was silently dropped (the whole member
      // routed through `skip_unknown_member`), so `local class C`,
      // `local function f`, and `local typealias T` never reached the
      // declaration list — references to them later in the module
      // raised `Cannot find property` / silently bypassed the
      // typealias's constraint. Apple Pkl treats `local` here as a
      // scope modifier (the declaration exists inside the module but
      // is not exported); pkl-mbt records the declaration unchanged
      // (the export-suppression side is a separate concern that only
      // matters when another module re-imports this one). Bump past
      // `local` and let the next loop iteration dispatch on the decl
      // keyword.
      let mut decl_i = self.skip_trivia_from(self.pos + 1)
      while decl_i < self.len &&
            self.tokens[decl_i].kind() == identifier() &&
            is_modifier_text(self.tokens[decl_i].text()) {
        decl_i = self.skip_trivia_from(decl_i + 1)
      }
      let next_text = if decl_i < self.len {
        self.tokens[decl_i].text()
      } else {
        ""
      }
      if next_text == "class" ||
        next_text == "function" ||
        next_text == "typealias" {
        ignore(self.bump())
        self.skip_whitespace()
        while self.at(identifier()) && is_modifier_text(self.peek().text()) {
          self.pending_modifiers.push(self.peek().text())
          ignore(self.bump())
          self.skip_whitespace()
        }
        if self.at_text("class") {
          match self.parse_class_decl() {
            Some(decl) => declarations.push(ClassDeclaration(decl))
            None => ()
          }
        } else if self.at_text("function") {
          match self.parse_function_decl() {
            Some(decl) => declarations.push(FunctionDeclaration(decl))
            None => ()
          }
        } else if self.at_text("typealias") {
          match self.parse_typealias_decl() {
            Some(decl) => declarations.push(TypeAliasDeclaration(decl))
            None => ()
          }
        } else {
          self.skip_unknown_member()
        }
      } else if is_decl_text(next_text) {
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
              is_const: binding.is_const,
              annotations: binding.annotations,
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
      module_annotations,
    },
    diagnostics: self.diagnostics,
    unsupported_syntax: self.unsupported_syntax,
  }
}
