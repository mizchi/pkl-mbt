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
      let next_text = self.peek_non_trivia_text(self.pos + 1)
      if next_text == "class" ||
        next_text == "function" ||
        next_text == "typealias" {
        ignore(self.bump())
        self.skip_whitespace()
        continue
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

///|
fn Parser::parse_module_decl(self : Parser) -> ParsedModuleDecl? {
  // PKL-128d: capture annotations preceding the `module` / `amends`
  // / `extends` keyword.
  let annotations = self.take_pending_annotations()
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
    Some({ module_name: parsed_name, module_relation, annotations })
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
  // Apple Pkl accepts modifier keywords after `local` (`local const x`,
  // `local hidden x`); swallow any combination so the identifier that
  // follows is read as the binding name rather than as the second
  // modifier.
  self.skip_whitespace()
  while self.at(identifier()) && is_modifier_text(self.peek().text()) {
    ignore(self.bump())
    self.skip_whitespace()
  }
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
  } else if ({
      self.skip_whitespace()
      self.at(lbrace())
    }) {
    // PKL-148e: `local a { body }` (no `=`, brace body) is the local
    // form of Apple Pkl's amend-shorthand. Dispatch through the same
    // body-inference path that `parse_property_decl` uses.
    self.parse_inferred_new_body()
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
  // PKL-128d: drain any pending annotations the surrounding
  // `skip_member_header` collected; they precede the `class` keyword.
  let annotations = self.take_pending_annotations()
  // PKL-117: drain the `abstract` modifier if present so the
  // typechecker can refuse instantiation and enforce that
  // descendant concrete classes override every abstract method.
  let is_abstract = self.take_pending_abstract()
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
      // PKL-148e: `local` modifier on a class property. Apple Pkl's
      // local class properties are usable from class methods but
      // hidden from PCF output / external access. Consume the keyword
      // and route through the regular property parser; the hidden
      // prefix gates rendering and `push_receiver_method_bindings`
      // strips it when seeding the method cache. PKL-148j: switch to
      // the dedicated `local_member_prefix` so external `.X` resolves
      // through `lookup_visible_member` and rejects with "Cannot find
      // property `X`".
      let local_modifier = if self.at(local_kw()) {
        ignore(self.bump())
        self.skip_whitespace()
        true
      } else {
        false
      }
      if self.at_text("function") {
        match self.parse_function_decl() {
          Some(class_method) => methods.push(class_method)
          None => ()
        }
      } else if self.at_property_decl() {
        match self.parse_class_property_decl() {
          Some(property) =>
            if local_modifier {
              properties.push({
                name: local_member_name(property.name),
                type_name: property.type_name,
                value: property.value,
              })
            } else {
              properties.push(property)
            }
          None => ()
        }
      } else {
        self.skip_unknown_member()
      }
      self.consume_separators()
    }
    ignore(self.expect(rbrace(), "}"))
  }
  // PKL-148e: bodyless `class Foo` is well-formed; the previous
  // `skip_unknown_member` fallback ate the following separator + next
  // declaration into the current `class_decl` node, hiding subsequent
  // `class Foo2` from the top-level dispatcher.
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
      annotations,
      is_abstract,
    })
  }
}

///|
fn Parser::parse_class_property_decl(self : Parser) -> ClassProperty? {
  // PKL-145: drain the `hidden` modifier from the pending list that
  // `skip_member_header` populated, then prefix the stored name with
  // `hidden_member_prefix` so renderers skip the property (same
  // contract as the object-body `hidden` member path).
  let hidden = self.take_pending_hidden()
  self.builder.start_node(property_decl())
  if !self.at(identifier()) {
    self.skip_unknown_member()
    self.builder.finish_node()
    return None
  }
  let raw_name = match self.expect(identifier(), "class property name") {
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
  if raw_name == "" {
    None
  } else {
    let name = if hidden { hidden_member_name(raw_name) } else { raw_name }
    Some({ name, type_name, value })
  }
}

///|
fn Parser::parse_typealias_decl(self : Parser) -> TypeAliasDecl? {
  // PKL-128d: capture annotations preceding the `typealias` keyword.
  let annotations = self.take_pending_annotations()
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
    Some({ name, type_parameters, target, annotations })
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
  // PKL-128d: capture annotations preceding the `function` keyword.
  let annotations = self.take_pending_annotations()
  // PKL-117: drain the `abstract` modifier collected by
  // `skip_member_header`. Abstract functions intentionally have no
  // body — the modifier is the explicit marker the typechecker uses
  // when checking that concrete subclasses override every inherited
  // abstract method.
  let is_abstract = self.take_pending_abstract()
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
      annotations,
      is_abstract,
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
      // PKL-107: pull byte_offset along with self.pos so subsequent
      // position-tagged diagnostics still point at the right source
      // location. The trivia tokens are NOT pushed to the cst here
      // (existing behaviour for dot-chain continuation).
      for i = self.pos; i < trivia_end; i = i + 1 {
        self.byte_offset += self.tokens[i].text().length()
      }
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
      // PKL-103: `f?(...)` is Apple Pkl's null-safe call form. Today
      // only `read?(uri)` is wired through, but the parser recognises
      // the generic shape so future null-safe intrinsics share the
      // dispatch. `?` not followed by `(` keeps the existing
      // unsupported-syntax behaviour.
      let unsupported_start = self.current_offset()
      let after_question = self.peek_non_whitespace_kind(self.pos + 1)
      if after_question == lparen() {
        ignore(self.bump())
        self.skip_whitespace()
        self.builder.start_node_at(checkpoint, call_expr())
        ignore(self.expect(lparen(), "("))
        let arguments : Array[Expr] = []
        self.skip_whitespace()
        while !self.at(eof()) && !self.at(rparen()) {
          arguments.push(self.parse_expr())
          self.skip_whitespace()
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
        expr = NullSafeCallExpr(expr, arguments)
      } else {
        ignore(self.bump())
        self.record_unsupported_syntax(
          unsupported_start,
          self.current_offset(),
          kind_name(unsupported_expr()),
        )
        expr = UnsupportedExpr
      }
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
      parse_string_literal_text(tok.text())
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
  // PKL-150: `{ local NAME = EXPR; … }` can sit in either an object
  // body (subsequent members are property declarations) or a listing
  // body (subsequent members are bare element expressions). Disambiguate
  // by skipping past every leading `local …;` block and looking at the
  // first non-`local` token: a property-decl form → object, anything
  // else → listing.
  let after_locals_idx = self.skip_local_decls_from(first_idx)
  let after_locals_kind = if after_locals_idx >= self.len {
    eof()
  } else {
    self.tokens[after_locals_idx].kind()
  }
  let after_locals_text = if after_locals_idx >= self.len {
    ""
  } else {
    self.tokens[after_locals_idx].text()
  }
  let body_first = if first == local_kw() { after_locals_kind } else { first }
  let body_first_idx = if first == local_kw() {
    after_locals_idx
  } else {
    first_idx
  }
  let _ = if first == local_kw() { after_locals_text } else { first_text }
  // PKL-148x: a body whose first significant token is `...` (triple
  // dot, spread) routes through the object-body parser now that the
  // Dynamic-shape `@element$` / `@subscript$` sentinels exist; the
  // object-body `@spread` arm absorbs the payload regardless of
  // whether it evaluates to an ObjectValue (merge members),
  // ListingValue / ListValue / SetValue (push as `@element$`
  // entries), MappingValue (push as `@subscript$` entries), or
  // NullValue (silently skip).
  let body_first_is_triple_dot = body_first_idx + 2 < self.len &&
    self.tokens[body_first_idx].kind() == dot() &&
    self.tokens[body_first_idx + 1].kind() == dot() &&
    self.tokens[body_first_idx + 2].kind() == dot()
  // PKL-148aj: skip past any leading member-header tokens (modifier
  // idents like `const` / `fixed` / `abstract`, the `hidden` / `local`
  // visibility prefixes, and annotations) before deciding whether the
  // body parses as an object or a listing. Previously only `hidden`
  // and `fixed` were treated as property-decl signals here, so `const
  // qux = 99` (and any combination like `const local function`) routed
  // through `parse_listing_body` and the `qux = 99` member was lost.
  let prefix_skipped_idx = self.skip_member_prefix_from(body_first_idx)
  let prefix_skipped_kind = if prefix_skipped_idx >= self.len {
    eof()
  } else {
    self.tokens[prefix_skipped_idx].kind()
  }
  let prefix_skipped_text = if prefix_skipped_idx >= self.len {
    ""
  } else {
    self.tokens[prefix_skipped_idx].text()
  }
  if body_first == lbracket() {
    self.parse_mapping_body()
  } else if body_first == rbrace() ||
    body_first == when_kw() ||
    body_first == for_kw() ||
    body_first_is_triple_dot ||
    self.at_property_decl_from(body_first_idx) ||
    self.at_property_decl_from(prefix_skipped_idx) ||
    prefix_skipped_text == "function" ||
    prefix_skipped_kind == when_kw() ||
    prefix_skipped_kind == for_kw() {
    self.parse_object_body()
  } else {
    self.parse_listing_body()
  }
}

///|
/// PKL-148aj: walk past trivia + any sequence of annotation / visibility
/// (`local`, `hidden`) / modifier (`const`, `fixed`, `abstract`, ...)
/// tokens starting at `start`, returning the index of the first non-
/// prefix significant token. Mirrors the loop in `consume_member_header`
/// without committing to a parser advance, so callers can peek at what a
/// modifier run is actually decorating.
fn Parser::skip_member_prefix_from(self : Parser, start : Int) -> Int {
  let mut i = self.skip_trivia_from(start)
  while i < self.len {
    let kind = self.tokens[i].kind()
    let text = self.tokens[i].text()
    if kind == at_sign() {
      // Skip the annotation name (dotted identifier chain) and an
      // optional balanced `(...)` / `{...}` payload.
      let mut j = i + 1
      while j < self.len &&
            (
              self.tokens[j].kind() == identifier() ||
              self.tokens[j].kind() == dot()
            ) {
        j += 1
      }
      j = self.skip_trivia_from(j)
      if j < self.len &&
        (self.tokens[j].kind() == lparen() || self.tokens[j].kind() == lbrace()) {
        let open_kind = self.tokens[j].kind()
        let close_kind = if open_kind == lparen() { rparen() } else { rbrace() }
        let mut depth = 0
        while j < self.len {
          let k = self.tokens[j].kind()
          if k == open_kind {
            depth += 1
          } else if k == close_kind {
            depth -= 1
            if depth == 0 {
              j += 1
              break
            }
          }
          j += 1
        }
      }
      i = self.skip_trivia_from(j)
    } else if kind == local_kw() {
      i = self.skip_trivia_from(i + 1)
    } else if kind == identifier() &&
      (text == "hidden" || is_modifier_text(text)) {
      i = self.skip_trivia_from(i + 1)
    } else {
      break
    }
  }
  i
}

///|
/// Walk past every `local NAME [: TYPE] = EXPR` declaration starting
/// at `start`, returning the index of the first non-`local` significant
/// token. Used by `parse_inferred_new_body` to disambiguate object-vs-
/// listing bodies that lead with one or more `local` bindings — the
/// body kind is determined by what follows the leading locals, not by
/// the `local` keyword itself.
fn Parser::skip_local_decls_from(self : Parser, start : Int) -> Int {
  let mut i = start
  while i < self.len {
    let i_skipped = self.skip_trivia_from(i)
    if i_skipped >= self.len {
      return i_skipped
    }
    if self.tokens[i_skipped].kind() != local_kw() {
      return i_skipped
    }
    // Skip `local`, then walk to the end of the declaration (the next
    // separator at zero-balance brace/paren/bracket depth).
    let mut j = i_skipped + 1
    let mut parens = 0
    let mut braces = 0
    let mut brackets = 0
    while j < self.len {
      let kind = self.tokens[j].kind()
      if parens == 0 && braces == 0 && brackets == 0 {
        if kind == rbrace() || kind == rparen() || kind == rbracket() {
          break
        }
        if is_separator(kind) {
          break
        }
      }
      if kind == lparen() {
        parens += 1
      } else if kind == rparen() && parens > 0 {
        parens -= 1
      } else if kind == lbrace() {
        braces += 1
      } else if kind == rbrace() && braces > 0 {
        braces -= 1
      } else if kind == lbracket() {
        brackets += 1
      } else if kind == rbracket() && brackets > 0 {
        brackets -= 1
      }
      j += 1
    }
    i = j
  }
  i
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
  // PKL-150: Apple Pkl allows `local NAME = EXPR` declarations
  // interleaved with element expressions inside a Listing body —
  // the binding scopes to the rest of the body so subsequent
  // elements can reference it (e.g. `local s1 = Set(...) as
  // Set<Listing<Int>>; s1.first[0]`). Capture each item as either
  // an Element or a LocalBinding so the chain can be desugared
  // into nested `let` expressions after the body is fully read.
  let items : Array[ListingBodyItem] = []
  self.consume_separators()
  while !self.at(eof()) && !self.at(rbrace()) {
    self.skip_member_header()
    if self.at(when_kw()) {
      // PKL-136: `when (cond) { ... } [else { ... }]` inside a Listing body.
      // The branches re-parse as Listing bodies so the wrapped Expr stays
      // ListingLiteral on both sides; the spread happens at eval time.
      items.push({
        kind: ElementItem,
        name: "",
        value: self.parse_listing_when(),
      })
    } else if self.at(local_kw()) {
      match self.parse_local_decl() {
        Some(binding) =>
          items.push({
            kind: LocalBindingItem,
            name: binding.name,
            value: binding.value,
          })
        None => ()
      }
    } else if self.at_triple_dot() {
      // PKL-148s: `...x` / `...?x` spread in a Listing body. Wrap the
      // payload in `WhenSpread(...)` so the listing evaluator's
      // existing spread-flatten path picks it up.
      let payload = self.parse_spread_payload()
      items.push({ kind: ElementItem, name: "", value: WhenSpread(payload) })
    } else if self.at(lbracket()) ||
      self.at_property_decl() ||
      is_decl_text(self.peek().text()) {
      self.skip_unknown_member()
    } else {
      items.push({ kind: ElementItem, name: "", value: self.parse_expr() })
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  self.builder.finish_node()
  build_listing_body(items)
}

///|
priv enum ListingBodyItemKind {
  ElementItem
  LocalBindingItem
} derive(Eq)

///|
priv struct ListingBodyItem {
  kind : ListingBodyItemKind
  name : String
  value : Expr
}

///|
/// Desugar a Listing body that may contain `local NAME = EXPR`
/// declarations into a `ListingLiteral` whose elements include
/// `WhenSpread`-wrapped `let`-chains. The strategy is to walk the
/// items in order: every `local` opens a fresh scope (a CallExpr to
/// a LambdaExpr binding the name to the value) whose body is the
/// recursively-desugared remainder; the resulting ListingValue gets
/// spread back into the parent via WhenSpread so the binding stays
/// transparent at render time.
fn build_listing_body(items : Array[ListingBodyItem]) -> Expr {
  let any_local = {
    let mut found = false
    for item in items {
      if item.kind == LocalBindingItem {
        found = true
        break
      }
    }
    found
  }
  if !any_local {
    let elements : Array[Expr] = []
    for item in items {
      elements.push(item.value)
    }
    return ListingLiteral(elements)
  }
  build_listing_body_chain(items, 0)
}

///|
fn build_listing_body_chain(
  items : Array[ListingBodyItem],
  start : Int,
) -> Expr {
  let elements : Array[Expr] = []
  let mut i = start
  while i < items.length() {
    let item = items[i]
    if item.kind == LocalBindingItem {
      let body = build_listing_body_chain(items, i + 1)
      let bound = CallExpr(
        LambdaExpr([{ name: item.name, type_name: None }], body, None),
        [item.value],
      )
      elements.push(WhenSpread(bound))
      return ListingLiteral(elements)
    } else {
      elements.push(item.value)
      i = i + 1
    }
  }
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
    } else if self.at_triple_dot() {
      // PKL-148s: `...x` / `...?x` inside a Mapping body. Reuse the
      // same `WhenSpread(payload)`-keyed synthetic-entry encoding so
      // the mapping evaluator's existing spread-flatten path picks
      // it up.
      let payload = self.parse_spread_payload()
      entries.push({ key: WhenSpread(payload), value: NullLiteral })
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
    // PKL-147: `["k"] { body }` is the amend form for the entry's
    // existing value — dispatch by the first significant brace token
    // so a Mapping<String, Listing<T>> entry parses its body as a
    // Listing (bare elements) instead of an ObjectLiteral.
    self.parse_inferred_new_body()
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
    let visibility = self.consume_member_header()
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
    } else if self.at_triple_dot() {
      // PKL-148s: `...x` / `...?x` spread member. Stored under the
      // reserved name `@spread` so `eval_object_members` can intercept
      // it (alongside the existing `@when` / `@for` sentinels) and
      // splice the spread value's members into the parent. Nullable
      // and required spreads share the same encoding for now — the
      // evaluator silently skips on `NullValue` either way (good
      // enough for `spreadSyntaxTyped` / `spreadSyntaxNullable` gold
      // matches; tightening the required-spread null check is a
      // follow-up).
      let payload = self.parse_spread_payload()
      members.push({ name: "@spread", type_name: None, value: payload })
    } else if self.at(lbracket()) {
      // PKL-148w: `(x) { [3] = "barn owl" }` style subscript-amend
      // entry inside an object body. Apple Pkl interprets this as an
      // amend-time index/key override (`x` is a Listing → replace
      // element 3; `x` is a Mapping → upsert entry at key 3). The
      // parser doesn't know the base shape, so capture the entry as
      // `ObjectMember { name = "@subscript$<offset>", value =
      // CallExpr(Identifier("@__index_entry"), [key, value]) }` —
      // the `AmendExpr` evaluator decodes it and dispatches to
      // `replace_listing_element` / `mapping_amend` based on the
      // resolved base. Offset disambiguates multiple subscript
      // entries inside the same body.
      let offset = self.current_offset()
      ignore(self.bump())
      self.skip_whitespace()
      let key_expr = self.parse_expr()
      ignore(self.expect(rbracket(), "]"))
      self.skip_whitespace()
      if self.at(eq()) {
        ignore(self.bump())
        self.skip_whitespace()
        let value_expr = self.parse_expr()
        members.push({
          name: "@subscript$" + offset.to_string(),
          type_name: None,
          value: CallExpr(Identifier("@__index_entry"), [key_expr, value_expr]),
        })
      } else if self.at(lbrace()) {
        // `[key] { ... }` — amend the entry at `key` with the given
        // body. Encoded the same way; the second argument carries
        // the amend body.
        let body = self.parse_object_body()
        members.push({
          name: "@subscript$" + offset.to_string(),
          type_name: None,
          value: CallExpr(Identifier("@__index_entry"), [key_expr, body]),
        })
      } else {
        self.skip_unknown_member()
      }
    } else if self.at(identifier()) && self.peek().text() == "function" {
      // PKL-148ag: `local function f(...) = body` inside an object body.
      // Apple Pkl scopes the method to the body's lexical extent;
      // siblings inside the same body call `f(...)` and resolve through
      // the implicit-receiver chain. Reuse `parse_function_decl` and
      // lower to `@local$f = (params) -> body` — the lambda's
      // FunctionValue lands in the object's member list and
      // `eval_object_members` already strips the `@local$` prefix when
      // hoisting prior members into the per-field eval env, so a sibling
      // `f(arg)` resolves the bare name. Only the LocalMember visibility
      // makes sense for an in-body function (Apple Pkl rejects
      // body-level `function f(...)` without `local`); the other
      // visibilities fall through to the same encoding for resilience.
      match self.parse_function_decl() {
        Some(decl) => {
          let body_expr = match decl.body {
            Some(e) => e
            None => UnsupportedExpr
          }
          let lambda = LambdaExpr(
            decl.parameters,
            body_expr,
            decl.return_type_name,
          )
          let stored_name = match visibility {
            LocalMember | VisibleMember | HiddenMember =>
              local_member_name(decl.name)
          }
          members.push({ name: stored_name, type_name: None, value: lambda })
        }
        None => ()
      }
    } else if self.at_property_decl() {
      match self.parse_object_member() {
        Some(field) => {
          let stored_name = match visibility {
            VisibleMember => field.name
            HiddenMember => hidden_member_name(field.name)
            LocalMember => local_member_name(field.name)
          }
          members.push({
            name: stored_name,
            type_name: field.type_name,
            value: field.value,
          })
        }
        None => ()
      }
    } else {
      // PKL-148x: a bare expression at object-body position is a
      // Dynamic-shape unnamed element (Apple Pkl's `new {}` accepts
      // both `name = value` properties and bare elements
      // simultaneously). Stash under a `@element$<offset>` sentinel
      // so the renderer can project it listing-style (no `name =`
      // prefix). When the parser doesn't recognise the input as an
      // expression at all (UnsupportedExpr / zero advance), fall
      // through to `skip_unknown_member` to preserve the legacy
      // tolerance for malformed bodies. The amend-lambda shorthand
      // (`(f) { x -> body }`) also lands here; the trailing `->`
      // after a bare identifier signals an Apple-Pkl-specific
      // lambda-amend form that pkl-mbt doesn't yet support — defer
      // to `skip_unknown_member` so existing parse-suite fixtures
      // don't regress when the body is fed through `parse_expr`.
      // Conservative element detection: only emit `@element$` when
      // the next token looks like a value-producing expression start
      // (literal, `new`, prefix sign, `(...)`, identifier-followed-by
      // a call/access/operator). Identifier alone with a trailing
      // `:` / `->` / `,` resembles a typed-lambda-parameter list
      // (Apple-Pkl-specific amend-lambda shorthand) that pkl-mbt
      // doesn't yet support — defer to `skip_unknown_member` there
      // so the existing parse-suite fixtures don't regress.
      let kind = self.peek_kind()
      let next_non_trivia = self.peek_non_trivia_kind(self.pos + 1)
      let is_value_start = kind == int_token() ||
        kind == float_token() ||
        kind == string_token() ||
        kind == true_kw() ||
        kind == false_kw() ||
        kind == null_kw() ||
        kind == new_kw() ||
        kind == minus() ||
        kind == bang()
      let identifier_kind_safe = kind == identifier() &&
        next_non_trivia != arrow() &&
        next_non_trivia != comma() &&
        next_non_trivia != colon()
      if is_value_start || identifier_kind_safe {
        let start_pos = self.pos
        let expr = self.parse_expr()
        match expr {
          UnsupportedExpr => self.skip_unknown_member()
          _ =>
            if self.pos == start_pos {
              self.skip_unknown_member()
            } else {
              let offset = self.byte_offset
              members.push({
                name: "@element$" + offset.to_string(),
                type_name: None,
                value: expr,
              })
            }
        }
      } else {
        self.skip_unknown_member()
      }
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  members
}

///|
/// PKL-148j: classify the leading visibility modifier on the next
/// object-body member. `local` and `hidden` were collapsed into a single
/// boolean before; splitting them lets external `.X` access keep `hidden`
/// reachable while rejecting `local`.
priv enum MemberVisibility {
  VisibleMember
  HiddenMember
  LocalMember
} derive(Eq)

///|
/// Consume any leading `hidden` / `local` visibility modifiers on the next
/// object-body member. Returns which variant was seen so the caller can
/// pick the matching storage prefix (`@hidden$` vs `@local$`).
///
/// `hidden` is a modifier-text identifier (the lexer keeps it as a regular
/// identifier; `is_modifier_text` recognises it later). `local` is a
/// dedicated keyword (`local_kw`) introduced for top-level local
/// declarations. Both are stripped here before `skip_member_header` runs
/// its annotation / modifier loop so other modifiers (`const`, `fixed`,
/// `abstract`, etc.) can still pass through. When both modifiers are
/// present on the same member the more restrictive `LocalMember` wins —
/// `hidden local x` should not be reachable through external `.x`.
/// PKL-148aj: object-body members accept any interleaving of modifier
/// keywords (`const`, `fixed`, ...) and visibility keywords (`local`,
/// `hidden`) before the member's name, e.g. `const local function biz()`.
/// The previous shape — `consume_member_visibility_modifiers` then
/// `skip_member_header` — only saw the visibility keywords that
/// physically led the modifier run, so `const local` parsed as
/// VisibleMember + a leftover `local` token that no later branch
/// recognises (the body fell through to the bare-expression path and
/// failed with `Cannot find property`). Do both passes in one loop so
/// visibility latches independent of position.
fn Parser::consume_member_header(self : Parser) -> MemberVisibility {
  self.pending_annotations.clear()
  self.pending_modifiers.clear()
  let mut visibility : MemberVisibility = VisibleMember
  let mut keep_going = true
  while keep_going {
    self.skip_trivia()
    if self.at(at_sign()) {
      ignore(self.parse_annotation())
    } else if self.at(local_kw()) {
      visibility = LocalMember
      ignore(self.bump())
    } else if self.at(identifier()) && self.peek().text() == "hidden" {
      if visibility != LocalMember {
        visibility = HiddenMember
      }
      ignore(self.bump())
    } else if self.at(identifier()) && is_modifier_text(self.peek().text()) {
      self.pending_modifiers.push(self.peek().text())
      ignore(self.bump())
    } else {
      keep_going = false
    }
  }
  visibility
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
/// Reserved prefix used to mark `hidden` object members. The lexer rejects
/// `@` and `$` in identifiers, so the prefix can never collide with a
/// user-declared property name. Renderers skip members whose name starts
/// with this prefix; `lookup_member` resolves either the bare or prefixed
/// form so reads from the same value see the hidden member transparently.
/// PKL-148j: `hidden` and `local` were previously conflated under this
/// prefix; the `local_member_prefix` below separates the two so external
/// member access can hide `local` while keeping `hidden` accessible (Apple
/// Pkl's `hidden` keeps property values reachable via `.X`, only excluding
/// them from the rendered envelope).
let hidden_member_prefix : String = "@hidden$"

///|
/// PKL-148j: separate prefix for `local` object members. Same renderer-
/// invisibility contract as `hidden_member_prefix`, but `lookup_visible_member`
/// filters this one out so `(target).x` raises "Cannot find property `x`"
/// when `x` was declared `local`.
let local_member_prefix : String = "@local$"

///|
fn hidden_member_name(name : String) -> String {
  hidden_member_prefix + name
}

///|
fn local_member_name(name : String) -> String {
  local_member_prefix + name
}

///|
fn is_hidden_member_name(name : String) -> Bool {
  name.has_prefix(hidden_member_prefix)
}

///|
fn is_local_member_name(name : String) -> Bool {
  name.has_prefix(local_member_prefix)
}

///|
/// PKL-148ak: prefix marker for a deferred per-property type / constraint
/// rejection. `eval_object_members` stamps a `@error$<name>` member
/// alongside the rejected value; the access paths (member access via
/// `lookup_pending_error_message`, identifier resolution via the
/// `error_member_name` env entry hoisted next to the bare name) raise
/// the diagnostic lazily. The sentinel itself must never reach the
/// renderer — fold it into the invisible-member set.
let error_member_prefix : String = "@error$"

///|
fn error_member_name(name : String) -> String {
  error_member_prefix + name
}

///|
fn is_error_member_name(name : String) -> Bool {
  name.has_prefix(error_member_prefix)
}

///|
/// PKL-148j: combined predicate for any renderer-invisible member.
/// Renderers / filter sites that previously called `is_hidden_member_name`
/// to skip non-rendered members should switch to this so `local` members
/// stay hidden from the output too.
fn is_invisible_member_name(name : String) -> Bool {
  is_hidden_member_name(name) ||
  is_local_member_name(name) ||
  is_error_member_name(name)
}

///|
/// PKL-148j: strip whichever visibility prefix (`@hidden$` / `@local$`)
/// is present on a member name. Returns the bare name unchanged when the
/// member carries no prefix. Used by every site that needs to project a
/// hidden / local member back into a bare-name binding (method-cache
/// seeding, sibling-resolution env hoisting, etc.).
fn strip_member_visibility_prefix(name : String) -> String {
  if is_hidden_member_name(name) {
    String::unsafe_substring(
      name,
      start=hidden_member_prefix.length(),
      end=name.length(),
    )
  } else if is_local_member_name(name) {
    String::unsafe_substring(
      name,
      start=local_member_prefix.length(),
      end=name.length(),
    )
  } else {
    name
  }
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
    // PKL-105 / PKL-137: nested brace body uses the inferred-body
    // dispatcher so a `converters { ["k"] = v }` mapping inside a
    // renderer object isn't silently dropped (object-body parsing
    // would skip the bracket-keyed entries as unknown members).
    self.parse_inferred_new_body()
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
  // PKL-147: Apple Pkl integer literals come in four shapes:
  //   1. decimal `123`, with optional `_` separators (`1_000_000`),
  //   2. hex `0xFF_FF` / `0X1A`,
  //   3. binary `0b1010` / `0B1010`,
  //   4. octal `0o17` / `0O17`.
  // The lexer keeps the prefix in the token text, so dispatch on
  // `text[0..1]` and accumulate the digits in the matching base.
  // Underscores are skipped in every form.
  let len = text.length()
  if len >= 2 && text[0].to_int().unsafe_to_char() == '0' {
    let prefix = text[1].to_int().unsafe_to_char()
    if prefix == 'x' || prefix == 'X' {
      let mut value = 0
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
        value = value * 16 + d
      }
      return value
    }
    if prefix == 'b' || prefix == 'B' {
      let mut value = 0
      for i = 2; i < len; i = i + 1 {
        let c = text[i].to_int().unsafe_to_char()
        if c == '0' || c == '1' {
          value = value * 2 + c.to_int() - '0'.to_int()
        }
      }
      return value
    }
    if prefix == 'o' || prefix == 'O' {
      let mut value = 0
      for i = 2; i < len; i = i + 1 {
        let c = text[i].to_int().unsafe_to_char()
        if c >= '0' && c <= '7' {
          value = value * 8 + c.to_int() - '0'.to_int()
        }
      }
      return value
    }
  }
  let mut value = 0
  for i = 0; i < len; i = i + 1 {
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
  // Fast path: no interpolation marker → reuse the existing escape
  // decoder so the common case stays a single allocation.
  if inner.find("\\(") is None {
    return StringLiteral(decode_string_escapes(inner))
  }
  let parts : Array[Expr] = []
  let buf = StringBuilder::new()
  let mut buf_has_content = false
  let mut i = 0
  while i < inner.length() {
    let c = inner[i].to_int().unsafe_to_char()
    if c == '\\' && i + 1 < inner.length() {
      let next = inner[i + 1].to_int().unsafe_to_char()
      if next == '(' {
        // Flush any accumulated literal segment.
        if buf_has_content {
          parts.push(StringLiteral(decode_string_escapes(buf.to_string())))
          buf.reset()
          buf_has_content = false
        }
        // Walk a balanced `(...)` group to find the matching close.
        let mut depth = 1
        let mut j = i + 2
        while j < inner.length() && depth > 0 {
          let cc = inner[j].to_int().unsafe_to_char()
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
        let segment = String::unsafe_substring(inner, start=i + 2, end=j)
        // Parse the segment as a Pkl expression by routing it through
        // `parse_source` and pulling the body Expr (or the last
        // binding's value as fallback).
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
      } else {
        // Regular escape (handled by decode_string_escapes); accumulate
        // the two chars verbatim so the final flush hands the literal
        // back to the decoder.
        buf.write_char(c)
        buf_has_content = true
        if i + 1 < inner.length() {
          buf.write_char(next)
        }
        i = i + 2
      }
    } else {
      buf.write_char(c)
      buf_has_content = true
      i = i + 1
    }
  }
  if buf_has_content {
    parts.push(StringLiteral(decode_string_escapes(buf.to_string())))
  }
  // Apply escape decoding to every literal-segment part now that the
  // splits are done. Inner expressions are pre-parsed and need no
  // further escape work.
  let normalized : Array[Expr] = []
  for part in parts {
    match part {
      StringLiteral(text) => normalized.push(StringLiteral(text))
      other => normalized.push(other)
    }
  }
  if normalized.length() == 1 {
    match normalized[0] {
      StringLiteral(_) as plain => return plain
      _ => ()
    }
  }
  InterpolatedString(normalized)
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
