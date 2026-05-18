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
        (stop_at_expression_operator && self.at_type_expression_boundary()) {
        break
      }
      if is_separator(self.peek_kind()) {
        // PKL-148ap: a separator at top level normally ends the type
        // text, but Apple Pkl lets a union typealias body wrap onto
        // a continuation line whose first significant token is `|`:
        //   typealias A =
        //     "a"
        //     | "b"
        //     | "c"
        // Peek past the trivia run; if the next significant token is
        // `|`, swallow the separators and continue collecting the
        // type text. Otherwise the separator is a real boundary
        // (`typealias A = Int\n typealias B = Float` etc.) and we
        // stop here.
        let next_kind = self.peek_non_trivia_kind(self.pos + 1)
        if next_kind == pipe() {
          self.skip_trivia()
          continue
        }
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
  // PKL-148as: function return-type annotation must accept the
  // function-type form `(X) -> Y` (the only place where `->` is part
  // of the type rather than a lambda body marker). `parse_type_annotation`
  // stops at arrow (correct for lambda-parameter annotations where
  // `(a: Int) -> body` has `Int` as the param type and `->` as the
  // body marker), so the return-type slot is the one site that must
  // bypass that stop. Inline the colon-aware walk here with
  // `stop_at_arrow=false` so `function matches(...): (String) -> Boolean
  // = ...` parses the whole function type before looking for `=`.
  self.skip_whitespace()
  let return_type_name = if self.at(colon()) {
    ignore(self.bump())
    self.skip_whitespace()
    let t = self.parse_type_text(
      stop_at_arrow=false,
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
    let mut body = self.parse_inferred_new_body()
    // PKL-148ap: `name { body1 } { body2 }` chains additional amend
    // bodies onto the same property. Apple Pkl's `foo { bar { "Hello"
    // } } { bar { "World" } }` produces the merged value where the
    // second body amends the first. Each trailing `{` wraps the
    // running expression in an `AmendExpr`.
    while ({
            self.skip_trivia()
            self.at(lbrace())
          }) {
      let members = self.parse_object_body_members()
      body = AmendExpr(body, members)
    }
    body
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
