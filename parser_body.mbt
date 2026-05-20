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
        type_name: None,
        value: self.parse_listing_when(),
      })
    } else if self.at(for_kw()) {
      match self.parse_for_header() {
        Some((var1, var2, source)) => {
          let body = self.parse_listing_body()
          items.push({
            kind: ElementItem,
            name: "",
            type_name: None,
            value: WhenSpread(
              ForGenerator(var1, var2, source, [
                {
                  name: "@spread",
                  type_name: None,
                  value: body,
                  annotations: [],
                },
              ]),
            ),
          })
        }
        None => ()
      }
    } else if self.at_local_function_decl() {
      match self.parse_local_function_binding_expr() {
        Some((name, value)) =>
          items.push({ kind: LocalBindingItem, name, type_name: None, value })
        None => ()
      }
    } else if self.at(local_kw()) {
      match self.parse_local_decl() {
        Some(binding) => {
          let (value, type_name) = collection_local_binding_value_and_type(
            binding.value,
            binding.type_name,
          )
          items.push({
            kind: LocalBindingItem,
            name: binding.name,
            type_name,
            value,
          })
        }
        None => ()
      }
    } else if self.at_triple_dot() {
      // PKL-148s: `...x` / `...?x` spread in a Listing body. Wrap the
      // payload in `WhenSpread(...)` so the listing evaluator's
      // existing spread-flatten path picks it up.
      let payload = self.parse_spread_payload()
      items.push({
        kind: ElementItem,
        name: "",
        type_name: None,
        value: WhenSpread(payload),
      })
    } else if self.at(lbracket()) {
      // PKL-152: a bracket-key entry inside `new Listing { ... }` only
      // makes sense as an amendment (`(listing) { [0] = value }`).
      // Pure construction can't index into a non-existent element, so
      // capture the bracket entry as a poison element that the
      // ListingLiteral evaluator turns into the
      // `Element index ... out of range ...` diagnostic.
      ignore(self.bump())
      self.skip_whitespace()
      let key_expr = self.parse_expr()
      self.skip_whitespace()
      ignore(self.expect(rbracket(), "]"))
      self.skip_whitespace()
      if self.at(eq()) {
        ignore(self.bump())
        self.skip_whitespace()
        let _ = self.parse_expr()
      } else if self.at(lbrace()) {
        let _ = self.parse_object_body()
      }
      items.push({
        kind: ElementItem,
        name: "",
        type_name: None,
        value: CallExpr(Identifier("@__listing_index_entry"), [key_expr]),
      })
    } else if self.at(identifier()) && self.peek().text() == "default" {
      match self.parse_collection_default_expr() {
        Some(default_expr) =>
          items.push({
            kind: ElementItem,
            name: "",
            type_name: None,
            value: CallExpr(Identifier(collection_default_marker_name()), [
              default_expr,
            ]),
          })
        None => ()
      }
    } else if self.at_property_decl() || is_decl_text(self.peek().text()) {
      items.push({
        kind: ElementItem,
        name: "",
        type_name: None,
        value: CallExpr(Identifier("@__listing_property_entry"), []),
      })
      self.skip_unknown_member()
    } else {
      items.push({
        kind: ElementItem,
        name: "",
        type_name: None,
        value: self.parse_expr(),
      })
    }
    self.consume_separators()
  }
  ignore(self.expect(rbrace(), "}"))
  self.builder.finish_node()
  build_listing_body(items)
}

///|
fn collection_default_marker_name() -> String {
  "@collectionDefault"
}

///|
fn Parser::parse_collection_default_expr(self : Parser) -> Expr? {
  if !self.at(identifier()) || self.peek().text() != "default" {
    return None
  }
  ignore(self.bump())
  self.skip_whitespace()
  if self.at(eq()) {
    ignore(self.bump())
    self.skip_whitespace()
    Some(self.parse_expr())
  } else if self.at(lbrace()) {
    Some(self.parse_object_body())
  } else {
    Some(UnsupportedExpr)
  }
}

///|
fn collection_annotation_uses_listing_marker(name : String) -> Bool {
  let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(name))
  let unwrapped = if trimmed.has_suffix("?") {
    String::unsafe_substring(trimmed, start=0, end=trimmed.length() - 1)
  } else {
    trimmed
  }
  unwrapped.contains("Listing<") ||
  unwrapped.contains("List<") ||
  unwrapped.contains("Set<") ||
  unwrapped.contains("Collection<")
}

///|
fn mark_lazy_collection_lambda_expr(value : Expr) -> Expr {
  match value {
    LambdaExpr(parameters, body, return_type_name) => {
      let marked_parameters : Array[FunctionParameter] = []
      for parameter in parameters {
        marked_parameters.push({
          name: parameter.name,
          type_name: mark_lazy_collection_annotation_opt(parameter.type_name),
        })
      }
      LambdaExpr(
        marked_parameters,
        body,
        mark_lazy_collection_annotation_opt(return_type_name),
      )
    }
    _ => value
  }
}

///|
fn collection_local_binding_value_and_type(
  value : Expr,
  type_name : String?,
) -> (Expr, String?) {
  match type_name {
    Some(name) if collection_annotation_uses_listing_marker(name) =>
      (
        CallExpr(Identifier("@__typed_listing"), [StringLiteral(name), value]),
        None,
      )
    _ => (mark_lazy_collection_lambda_expr(value), type_name)
  }
}

///|
fn Parser::at_local_function_decl(self : Parser) -> Bool {
  if !self.at(local_kw()) {
    return false
  }
  let next = self.skip_trivia_from(self.pos + 1)
  next < self.len &&
  self.tokens[next].kind() == identifier() &&
  self.tokens[next].text() == "function"
}

///|
fn Parser::parse_local_function_binding_expr(self : Parser) -> (String, Expr)? {
  ignore(self.expect(local_kw(), "local"))
  self.skip_whitespace()
  match self.parse_function_decl() {
    Some(decl) => {
      let body = match decl.body {
        Some(expr) => expr
        None => UnsupportedExpr
      }
      let parameters : Array[FunctionParameter] = []
      for parameter in decl.parameters {
        parameters.push({
          name: parameter.name,
          type_name: mark_lazy_collection_annotation_opt(parameter.type_name),
        })
      }
      Some(
        (
          decl.name,
          LambdaExpr(
            parameters,
            body,
            mark_lazy_collection_annotation_opt(decl.return_type_name),
          ),
        ),
      )
    }
    None => None
  }
}

///|
fn mark_lazy_collection_annotation_opt(type_name : String?) -> String? {
  match type_name {
    Some(name) =>
      if collection_annotation_uses_listing_marker(name) {
        Some(mark_lazy_collection_annotation(name))
      } else {
        type_name
      }
    None => None
  }
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
  type_name : String?
  value : Expr
}

///|
fn collection_local_binding_marker_name() -> String {
  "@__collection_local"
}

///|
fn collection_local_binding_marker_expr(
  name : String,
  type_name : String?,
  value : Expr,
) -> Expr {
  let type_expr = match type_name {
    Some(t) => StringLiteral(t)
    None => NullLiteral
  }
  CallExpr(Identifier(collection_local_binding_marker_name()), [
    StringLiteral(name),
    type_expr,
    value,
  ])
}

///|
/// Desugar a Listing body that may contain `local NAME = EXPR`
/// declarations into a `ListingLiteral` with synthetic local-binding
/// markers. The evaluator scans those markers into lazy bindings before
/// evaluating visible elements, so an unused bad local does not poison
/// earlier elements while forward references can still resolve.
fn build_listing_body(items : Array[ListingBodyItem]) -> Expr {
  let elements : Array[Expr] = []
  for item in items {
    if item.kind == LocalBindingItem {
      elements.push(
        collection_local_binding_marker_expr(
          item.name,
          item.type_name,
          item.value,
        ),
      )
    } else {
      elements.push(item.value)
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
    } else if self.at(for_kw()) {
      match self.parse_for_header() {
        Some((var1, var2, source)) => {
          let body = self.parse_mapping_body()
          entries.push({
            key: WhenSpread(
              ForGenerator(var1, var2, source, [
                {
                  name: "@spread",
                  type_name: None,
                  value: body,
                  annotations: [],
                },
              ]),
            ),
            value: NullLiteral,
          })
        }
        None => ()
      }
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
    } else if self.at_local_function_decl() {
      match self.parse_local_function_binding_expr() {
        Some((name, value)) =>
          entries.push({
            key: collection_local_binding_marker_expr(name, None, value),
            value: NullLiteral,
          })
        None => ()
      }
    } else if self.at(local_kw()) {
      // PKL-148av: Apple Pkl allows `local NAME = EXPR` declarations
      // inside a Mapping body; the binding hoists to the body's
      // lexical extent and the entry expressions can reference it.
      // Store it as a synthetic entry that the evaluator scans into
      // lazy bindings before evaluating visible entries.
      match self.parse_local_decl() {
        Some(binding) => {
          let (value, type_name) = collection_local_binding_value_and_type(
            binding.value,
            binding.type_name,
          )
          entries.push({
            key: collection_local_binding_marker_expr(
              binding.name,
              type_name,
              value,
            ),
            value: NullLiteral,
          })
        }
        None => ()
      }
    } else if self.at(identifier()) && self.peek().text() == "default" {
      match self.parse_collection_default_expr() {
        Some(default_expr) =>
          entries.push({
            key: Identifier(collection_default_marker_name()),
            value: default_expr,
          })
        None => ()
      }
    } else if self.at_property_decl() {
      self.skip_unknown_member()
    } else {
      // PKL-152: a bare expression at Mapping-body position is illegal
      // (`new Mapping { "pigeon" }`). Capture it as an `@element$`
      // sentinel — the MappingLiteral evaluator raises Apple Pkl's
      // "Object of type `Mapping` cannot have an element." diagnostic
      // when one is present. Falls back to `skip_unknown_member` for
      // tokens that don't look like an expression start so existing
      // tolerant fixtures keep parsing.
      let kind = self.peek_kind()
      let is_value_start = kind == int_token() ||
        kind == float_token() ||
        kind == string_token() ||
        kind == true_kw() ||
        kind == false_kw() ||
        kind == null_kw() ||
        kind == lparen() ||
        kind == new_kw()
      if is_value_start {
        let offset = self.current_offset()
        let bare_expr = self.parse_expr()
        entries.push({
          key: Identifier("@element$" + offset.to_string()),
          value: bare_expr,
        })
      } else {
        self.skip_unknown_member()
      }
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
  match self.parse_function_amend_signature_member() {
    Some(signature) => {
      members.push(signature)
      self.consume_separators()
    }
    None => ()
  }
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
      members.push({
        name: "@spread",
        type_name: None,
        value: payload,
        annotations: [],
      })
    } else if self.at(lbracket()) {
      // PKL-148ar: detect the predicate-member shape `[[ pred ]] { body }`
      // or `[[ pred ]] = value` first. Two consecutive `[` open a
      // predicate filter that selects elements / entries of the
      // amend target (Listing / Dynamic-listing / Mapping) whose
      // predicate (with `this` = the element under test) evaluates
      // true; the body amends every matched entry. Encoded as
      // `@predicate$<offset>` with value
      // `CallExpr(Identifier("@__predicate_entry"), [pred, body])`
      // so the AmendExpr evaluator can dispatch on it.
      let next_kind = self.peek_non_trivia_kind(self.pos + 1)
      if next_kind == lbracket() {
        let offset = self.current_offset()
        ignore(self.bump())
        self.skip_whitespace()
        ignore(self.expect(lbracket(), "[["))
        self.skip_whitespace()
        let pred_expr = self.parse_expr()
        self.skip_whitespace()
        ignore(self.expect(rbracket(), "]"))
        ignore(self.expect(rbracket(), "]]"))
        self.skip_whitespace()
        let body_expr = if self.at(eq()) {
          ignore(self.bump())
          self.skip_whitespace()
          self.parse_expr()
        } else if self.at(lbrace()) {
          self.parse_object_body()
        } else {
          UnsupportedExpr
        }
        members.push({
          name: "@predicate$" + offset.to_string(),
          type_name: None,
          value: CallExpr(Identifier("@__predicate_entry"), [
            pred_expr, body_expr,
          ]),
          annotations: [],
        })
      } else {
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
            annotations: [],
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
            annotations: [],
          })
        } else {
          self.skip_unknown_member()
        }
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
          members.push({
            name: stored_name,
            type_name: None,
            value: lambda,
            annotations: [],
          })
        }
        None => ()
      }
    } else if self.at_property_decl() {
      match self.parse_object_member() {
        Some(field) => {
          let stored_name = match visibility {
            VisibleMember =>
              if field.name == "default" {
                hidden_member_name(field.name)
              } else {
                field.name
              }
            HiddenMember => hidden_member_name(field.name)
            LocalMember => local_member_name(field.name)
          }
          members.push({
            name: stored_name,
            type_name: field.type_name,
            value: field.value,
            annotations: field.annotations,
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
        kind == bang() ||
        // PKL-148bb: `if (cond) ... else ...` / `let (x = ...) ...` /
        // `(value) { amend }` at object-body position are value-
        // producing elements (Apple Pkl accepts conditional / let /
        // parenthesised amend expressions as bare entries inside
        // `dynamic { ... }`-style bodies — `basic/newInsideIf`,
        // `basic/newInsideLet`, `parser/spread` rely on this).
        kind == if_kw() ||
        kind == let_kw() ||
        kind == module_kw() ||
        kind == lparen()
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
                annotations: [],
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
fn function_amend_parameter_member_name() -> String {
  "@functionAmend$params"
}

///|
fn is_function_amend_parameter_member_name(name : String) -> Bool {
  name == function_amend_parameter_member_name()
}

///|
fn function_amend_recursive_member_name() -> String {
  "@functionAmend$recursive"
}

///|
fn is_function_amend_recursive_member_name(name : String) -> Bool {
  name == function_amend_recursive_member_name()
}

///|
fn is_function_amend_marker_member_name(name : String) -> Bool {
  is_function_amend_parameter_member_name(name) ||
  is_function_amend_recursive_member_name(name)
}

///|
fn Parser::function_amend_signature_at_current(self : Parser) -> Bool {
  let mut i = self.skip_trivia_from(self.pos)
  if i >= self.len || self.tokens[i].kind() != identifier() {
    return false
  }
  while i < self.len {
    if self.tokens[i].kind() != identifier() {
      return false
    }
    i = self.skip_trivia_from(i + 1)
    if i < self.len && self.tokens[i].kind() == colon() {
      i = self.skip_function_amend_type_from(i + 1)
    }
    i = self.skip_trivia_from(i)
    if i < self.len && self.tokens[i].kind() == arrow() {
      return true
    }
    if i < self.len && self.tokens[i].kind() == comma() {
      i = self.skip_trivia_from(i + 1)
      continue
    }
    return false
  }
  false
}

///|
fn Parser::skip_function_amend_type_from(self : Parser, start : Int) -> Int {
  let mut i = self.skip_trivia_from(start)
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  while i < self.len {
    let kind = self.tokens[i].kind()
    if parens == 0 && brackets == 0 && angles == 0 {
      if kind == arrow() || kind == comma() || kind == rbrace() {
        return i
      }
      if is_separator(kind) {
        return i
      }
    }
    if kind == lparen() {
      parens += 1
    } else if kind == rparen() {
      if parens == 0 {
        return i
      }
      parens -= 1
    } else if kind == lbracket() {
      brackets += 1
    } else if kind == rbracket() {
      if brackets == 0 {
        return i
      }
      brackets -= 1
    } else if parens == 0 && brackets == 0 && kind == lt() {
      angles += 1
    } else if parens == 0 && brackets == 0 && kind == gt() {
      if angles == 0 {
        return i
      }
      angles -= 1
    }
    i += 1
  }
  i
}

///|
fn Parser::parse_function_amend_parameter(self : Parser) -> FunctionParameter? {
  if !self.at(identifier()) {
    return None
  }
  let name = self.bump().text()
  self.skip_whitespace()
  let type_name = if self.at(colon()) {
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
  Some({ name, type_name })
}

///|
fn Parser::parse_function_amend_signature_member(
  self : Parser,
) -> ObjectMember? {
  if !self.function_amend_signature_at_current() {
    return None
  }
  let parameters : Array[FunctionParameter] = []
  while !self.at(eof()) && !self.at(arrow()) && !self.at(rbrace()) {
    match self.parse_function_amend_parameter() {
      Some(parameter) => parameters.push(parameter)
      None => ignore(self.bump())
    }
    self.skip_whitespace()
    if self.at(comma()) {
      ignore(self.bump())
      self.skip_whitespace()
    } else {
      break
    }
  }
  self.skip_whitespace()
  ignore(self.expect(arrow(), "->"))
  Some({
    name: function_amend_parameter_member_name(),
    type_name: None,
    value: LambdaExpr(parameters, NullLiteral, None),
    annotations: [],
  })
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
  is_error_member_name(name) ||
  is_function_amend_marker_member_name(name)
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
    annotations: [],
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
fn Parser::parse_for_header(self : Parser) -> (String, String?, Expr)? {
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
  if var1 == "" {
    return None
  }
  Some((var1, var2, source))
}

///|
fn Parser::parse_for_member(self : Parser) -> ObjectMember? {
  self.builder.start_node(object_member())
  let header = self.parse_for_header()
  let body_members = self.parse_object_body_members()
  self.builder.finish_node()
  let (var1, var2, source) = match header {
    Some(parts) => parts
    None => return None
  }
  Some({
    name: "@for",
    type_name: None,
    value: ForGenerator(var1, var2, source, body_members),
    annotations: [],
  })
}

///|
fn Parser::parse_object_member(self : Parser) -> ObjectMember? {
  let annotations = self.take_pending_annotations()
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
    // `default { n -> ... }` is collection-default syntax, not a
    // Listing body. Route it through object-body parsing so the function
    // amend signature marker is preserved for the evaluator.
    let mut body = if name == "default" {
      self.parse_object_body()
    } else {
      self.parse_inferred_new_body()
    }
    // PKL-148ap: chain trailing `{ ... }` bodies as additional amend
    // layers, mirroring the module-level property amend chain.
    // `baz { "first" } { "second" "third" } { "forth" }` inside an
    // object body wraps the running value in successive AmendExprs.
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
    self.parse_empty_unsupported_expr()
  }
  self.builder.finish_node()
  if name == "" {
    None
  } else {
    Some({ name, type_name, value, annotations })
  }
}
