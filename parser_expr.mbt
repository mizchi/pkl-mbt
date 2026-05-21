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
    } else {
      None
    }
    match op {
      Some(actual_op) => {
        self.builder.start_node_at(checkpoint, binary_expr())
        ignore(self.bump())
        let right = match actual_op {
          Is => self.parse_type_operand_expr()
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
  // PKL-148at: `as` / `is` right-operand also accepts string-literal
  // singletons (`"Pigeon"` as a type) and parenthesized / function-type
  // shapes (`(Int) -> Int`). For string literals and `(` openings, the
  // type text walker handles the consumption just like the identifier
  // path — collect every type-position token until a real expression
  // operator boundary.
  if self.at(identifier()) || self.at(lparen()) || self.at(string_token()) {
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
  let mut keep_going = true
  while keep_going {
    // PKL-148au: `+` is unambiguously binary, so it can continue
    // across newlines / semicolons (`1\n + 2`, `1;; +; 2`). `-` is
    // ambiguous (`2\n - 1` is two elements, not one binary), so it
    // only continues across plain whitespace + comments.
    self.skip_whitespace()
    if self.at(plus()) {
      self.builder.start_node_at(checkpoint, binary_expr())
      ignore(self.bump())
      let right = self.parse_mul_expr()
      self.builder.finish_node()
      left = BinaryExpr(BinaryOp::Add, left, right)
      continue
    }
    if self.at(minus()) {
      self.builder.start_node_at(checkpoint, binary_expr())
      ignore(self.bump())
      let right = self.parse_mul_expr()
      self.builder.finish_node()
      left = BinaryExpr(BinaryOp::Subtract, left, right)
      continue
    }
    // PKL-148au: no operator on the current line — peek past
    // newlines / semicolons for a continuation `+`. `-` stays
    // out of this branch because of the unary-minus ambiguity.
    let after_sep = self.skip_trivia_and_semicolons_from(self.pos)
    if after_sep < self.len && self.tokens[after_sep].kind() == plus() {
      self.skip_trivia_and_semicolons()
      self.builder.start_node_at(checkpoint, binary_expr())
      ignore(self.bump())
      // Also swallow any trailing separators after the operator
      // (`1;; +; 2;` puts a `;` between `+` and `2`).
      self.skip_trivia_and_semicolons()
      let right = self.parse_mul_expr()
      self.builder.finish_node()
      left = BinaryExpr(BinaryOp::Add, left, right)
      continue
    }
    keep_going = false
  }
  left
}

///|
fn Parser::parse_mul_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = self.parse_power_expr()
  while ({
          // PKL-148au: `*` / `/` / `%` / `~/` are unambiguously
          // binary, so they continue across newlines / semicolons
          // (`1\n / 2`, `3 *\n 4`). Peek past separators when the
          // current line has no operator.
          self.skip_whitespace()
          if self.at(star()) ||
            self.at(slash()) ||
            self.at(percent()) ||
            self.at(int_div()) {
            true
          } else {
            let after_sep = self.skip_trivia_and_semicolons_from(self.pos)
            if after_sep < self.len {
              let k = self.tokens[after_sep].kind()
              if k == star() || k == slash() || k == percent() || k == int_div() {
                self.skip_trivia_and_semicolons()
                true
              } else {
                false
              }
            } else {
              false
            }
          }
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
    // PKL-148au: swallow separators after the operator so the
    // right operand can sit on a fresh line / past a `;` (`3 *\n
    // 4`, `1;; / 2;`).
    self.skip_trivia_and_semicolons()
    let right = self.parse_power_expr()
    self.builder.finish_node()
    left = BinaryExpr(op, left, right)
  }
  left
}

///|
fn Parser::parse_power_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let left = self.parse_cast_expr()
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
fn Parser::parse_cast_expr(self : Parser) -> Expr {
  let checkpoint = self.builder.checkpoint()
  let mut left = self.parse_unary_expr()
  while ({
          self.skip_whitespace()
          self.at(as_kw())
        }) {
    self.builder.start_node_at(checkpoint, binary_expr())
    ignore(self.bump())
    let right = self.parse_type_operand_expr()
    self.builder.finish_node()
    left = BinaryExpr(As, left, right)
  }
  left
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
    // PKL-148aq: `next_kind == dot()` is normally a member-access
    // continuation, but a run of three consecutive `.`s is the
    // spread operator (`...listing`). When the dot-chain heuristic
    // would consume `.` from a spread that follows a bare element
    // (`{ 0\n  ...listing }` or `{ 3...IntSeq(...) }`), the inner
    // member parser then bumps `.` looking for an identifier, finds
    // another `.`, and surfaces `unsupported expression`. Bail out
    // of the entire postfix loop when three dots are stacked so the
    // caller's `at_triple_dot` arm picks up the spread.
    let is_triple_dot = trivia_end + 2 < self.len &&
      self.tokens[trivia_end].kind() == dot() &&
      self.tokens[trivia_end + 1].kind() == dot() &&
      self.tokens[trivia_end + 2].kind() == dot()
    if is_triple_dot {
      break
    }
    if self.at(star()) &&
      expr is Identifier("read") &&
      self.peek_non_whitespace_kind(self.pos + 1) == lparen() {
      // Apple Pkl's `read*("glob")` is a glob intrinsic, not binary
      // multiplication. Keep it on the existing CallExpr path by using
      // a synthetic callee name that the evaluator recognises.
      self.builder.start_node_at(checkpoint, call_expr())
      ignore(self.bump())
      self.skip_whitespace()
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
      expr = CallExpr(Identifier("read*"), arguments)
      continue
    }
    let mut separated_call = false
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
      let before_whitespace = self.pos
      self.skip_whitespace()
      separated_call = self.pos > before_whitespace
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
      if separated_call && !expr_allows_whitespace_call(expr) {
        keep_going = false
        continue
      }
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
          self.skip_trivia()
          // PKL-148bh: trailing comma before `)` is accepted by Apple
          // Pkl (`parser/methodTrailingCommas` exercises every form
          // including multi-line bodies). Without this exit the next
          // iteration would call `parse_expr` on `)`, push an
          // UnsupportedExpr / placeholder argument, and the arity
          // check would reject the call.
          if self.at(rparen()) {
            break
          }
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
fn expr_allows_whitespace_call(expr : Expr) -> Bool {
  match expr {
    Identifier(_)
    | MemberAccess(_, _)
    | SafeMemberAccess(_, _)
    | CallExpr(_, _)
    | NullSafeCallExpr(_, _)
    | SubscriptAccess(_, _)
    | NonNullExpr(_) => true
    _ => false
  }
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
      if self.legacy_dynamic_constructor_at_current() {
        return self.parse_legacy_dynamic_constructor()
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
fn Parser::legacy_dynamic_constructor_at_current(self : Parser) -> Bool {
  if !self.at(lparen()) {
    return false
  }
  let name_idx = self.skip_trivia_from(self.pos + 1)
  if name_idx >= self.len ||
    self.tokens[name_idx].kind() != identifier() ||
    self.tokens[name_idx].text() != "Dynamic" {
    return false
  }
  let close_idx = self.skip_trivia_from(name_idx + 1)
  if close_idx >= self.len || self.tokens[close_idx].kind() != rparen() {
    return false
  }
  let body_idx = self.skip_trivia_from(close_idx + 1)
  body_idx < self.len && self.tokens[body_idx].kind() == lbrace()
}

///|
fn Parser::parse_legacy_dynamic_constructor(self : Parser) -> Expr {
  self.builder.start_node(object_expr())
  ignore(self.expect(lparen(), "("))
  self.skip_whitespace()
  ignore(self.expect(identifier(), "Dynamic"))
  self.skip_whitespace()
  ignore(self.expect(rparen(), ")"))
  let members = self.parse_object_body_members()
  self.builder.finish_node()
  TypedObjectLiteral("Dynamic", members)
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
  // PKL-148bb: lambda return type stops at the body-marker `->`.
  // `parse_type_annotation`'s default (`stop_at_arrow=false`) is the
  // right call for class-method parameter / return slots where a
  // function-typed annotation (`(String) -> Int`) should land whole,
  // but a lambda's own return slot is immediately followed by the
  // body's `->` and must stop before it.
  self.skip_whitespace()
  let return_type_name = if self.at(colon()) {
    ignore(self.bump())
    self.skip_whitespace()
    let t = self.parse_type_text(
      stop_at_arrow=true,
      stop_at_expression_operator=false,
    )
    if t == "" {
      None
    } else {
      Some(t)
    }
  } else {
    None
  }
  ignore(self.expect(arrow(), "->"))
  let body = self.parse_expr()
  self.builder.finish_node()
  LambdaExpr(parameters, body, return_type_name)
}

///|
/// Parse `let (name = value) body`.
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
  LetExpr(name, type_name, value, body)
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
  let is_glob = self.at(star())
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
  if is_glob {
    ImportGlobExpr(uri)
  } else {
    ImportExpr(uri)
  }
}

///|
fn Parser::parse_object_expr(self : Parser) -> Expr {
  self.parse_object_expr_with_expected_type(None)
}

///|
fn Parser::parse_expr_with_expected_type(
  self : Parser,
  type_name : String?,
) -> Expr {
  self.skip_whitespace()
  if type_name == Some("Dynamic") && self.at_bare_new_body() {
    self.parse_object_expr_with_expected_type(type_name)
  } else {
    self.parse_expr()
  }
}

///|
fn Parser::at_bare_new_body(self : Parser) -> Bool {
  if !self.at(new_kw()) {
    return false
  }
  let body_idx = self.skip_trivia_from(self.pos + 1)
  body_idx < self.len && self.tokens[body_idx].kind() == lbrace()
}

///|
fn Parser::parse_object_expr_with_expected_type(
  self : Parser,
  expected_type_name : String?,
) -> Expr {
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
  let value = if type_name == "Listing" {
    self.parse_listing_body()
  } else if type_name.has_prefix("Listing<") {
    CallExpr(Identifier("@__typed_listing"), [
      StringLiteral(type_name),
      self.parse_listing_body(),
    ])
  } else if type_name == "Mapping" {
    self.parse_mapping_body()
  } else if type_name.has_prefix("Mapping<") {
    CallExpr(Identifier("@__typed_listing"), [
      StringLiteral(type_name),
      self.parse_mapping_body(),
    ])
  } else if type_name == "" {
    match expected_type_name {
      Some("Dynamic") =>
        // PKL-148ax: `local x: Dynamic = new { 1; foo = "foo" }`
        // is a Dynamic body, not a Listing with an illegal property.
        // The declared type is the only place that disambiguates this
        // mixed element/property body before evaluation.
        TypedObjectLiteral("Dynamic", self.parse_object_body_members())
      _ =>
        // PKL-138: peek the first significant token inside `{` to
        // decide whether `new { ... }` is a listing, mapping, or object
        // body. Without an expected Dynamic annotation, infer from the
        // body's first item shape.
        self.parse_inferred_new_body()
    }
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
    self.function_amend_signature_at_from(body_first_idx) ||
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
