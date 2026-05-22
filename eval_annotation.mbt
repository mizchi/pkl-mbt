///|
fn eval_type_alias_bindings(
  declarations : Array[Declaration],
) -> Array[EvalTypeAliasBinding] {
  let aliases : Array[EvalTypeAliasBinding] = []
  // PKL-148bb: Apple Pkl's `pkl:base` ships fixed-width integer
  // typealiases (`UInt8` = `Int(isBetween(0, 255))`, etc.). Seed them
  // so user code can annotate `x: UInt8 = 255` without explicitly
  // importing — the constraint cascade then enforces the range.
  // `api/typeAliases` and `basic/int` both rely on these.
  aliases.push({ name: "UInt", target: "Int(isBetween(0, 4294967295))" })
  aliases.push({ name: "UInt8", target: "Int(isBetween(0, 255))" })
  aliases.push({ name: "UInt16", target: "Int(isBetween(0, 65535))" })
  aliases.push({ name: "UInt32", target: "Int(isBetween(0, 4294967295))" })
  aliases.push({ name: "Int8", target: "Int(isBetween(-128, 127))" })
  aliases.push({ name: "Int16", target: "Int(isBetween(-32768, 32767))" })
  aliases.push({
    name: "Int32",
    target: "Int(isBetween(-2147483648, 2147483647))",
  })
  for declaration in declarations {
    match declaration {
      TypeAliasDeclaration(type_alias) =>
        aliases.push({ name: type_alias.name, target: type_alias.target })
      ClassDeclaration(_) | FunctionDeclaration(_) => ()
    }
  }
  aliases
}

///|
fn eval_constrained_type_source_name_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  if pkl_constrained_type_annotation_has_supported_constraint(name) {
    return Some(name)
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_constrained_type_source_name_with_depth(target, aliases, depth + 1)
    None => None
  }
}

///|
fn eval_resolved_type_alias_with_depth(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
  depth : Int,
) -> String {
  if depth > 8 {
    return name
  }
  match lookup_eval_type_alias(aliases, name) {
    Some(target) =>
      eval_resolved_type_alias_with_depth(target, aliases, depth + 1)
    None => name
  }
}

///|
fn eval_resolved_type_alias(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String {
  eval_resolved_type_alias_with_depth(name, aliases, 0)
}

///|
fn eval_constrained_type_source_name(
  name : String,
  aliases : Array[EvalTypeAliasBinding],
) -> String? {
  eval_constrained_type_source_name_with_depth(name, aliases, 0)
}

///|
// PKL-138: coerce an empty `ObjectValue([])` to the empty Listing /
// Mapping value when the binding's type annotation requires it. Parsers
// can't tell whether `new {}` (no explicit type, empty body) is meant
// to be a Listing, Mapping, or Object — the binding's type annotation
// is the disambiguator, applied here at eval time.
//
// Non-empty `ObjectValue`s aren't coerced: if the body had real entries
// they would have been parsed as listing / mapping body via the
// `parse_inferred_new_body` peek (which dispatches on the first
// significant token), so a non-empty ObjectValue with a Listing /
// Mapping annotation is a real type mismatch.

///|
/// PKL-148: when a typed binding (`p: Person = new {}`) gets filled in
/// with an empty object, fall back to the class's declared default
/// property values. Without this the rendered output is `p {}` instead
/// of the inherited defaults. The expansion runs only for ObjectValue
/// with zero visible members where `type_name` names a user-defined
/// class; everything else passes through.
fn apply_class_defaults_for_type(
  value : Value,
  type_name : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  match (value, type_name) {
    (ObjectValue(members), Some(name)) =>
      if visible_members(members).length() != 0 {
        value
      } else {
        let base = name
        match lookup_class_binding(class_env, base) {
          Some(_) => {
            let defaults = eval_class_default_members(
              base,
              bindings,
              env,
              class_env,
              cache,
              [],
              declarations,
              diagnostics,
              resolve_import,
            )
            if defaults.length() == 0 {
              value
            } else {
              ObjectValue(merge_value_members(defaults, members))
            }
          }
          None => value
        }
      }
    _ => value
  }
}

///|
/// Synthesize a runtime default value for a typed property that has no
/// `=` initializer. Mirrors Apple Pkl's auto-default rules so a module
/// like `class P; p: P` renders as `p {}`. Returns `None` when the
/// type doesn't have a representable default (e.g., an unresolved
/// generic) so the caller can fall back to the abstract-slot skip.
fn synthesize_default_for_type(
  type_name : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  match type_name {
    None => None
    Some(raw) => {
      let mut name = trim_spaces(raw)
      // Strip a wrapping `( ... )` introduced by nested union grouping
      // (`*("a"|*"b")|"c"`). Without unwrap the inner union split sees
      // the whole `("a"|*"b")` as one choice and treats it as an
      // unknown class name.
      while name.has_prefix("(") && name.has_suffix(")") {
        let mut depth = 0
        let mut wraps_whole = true
        for i = 0; i < name.length(); i = i + 1 {
          let c = name[i].to_int().unsafe_to_char()
          if c == '(' {
            depth = depth + 1
          } else if c == ')' {
            depth = depth - 1
            if depth == 0 && i < name.length() - 1 {
              wraps_whole = false
              break
            }
          }
        }
        if wraps_whole && depth == 0 {
          name = trim_spaces(
            String::unsafe_substring(name, start=1, end=name.length() - 1),
          )
        } else {
          break
        }
      }
      match pkl_constrained_type_base_name(name) {
        Some(base) => name = trim_spaces(base)
        None => ()
      }
      // Nullable types (`T?`) default to null.
      if name.has_suffix("?") || name == "Null" || name == "Nothing" {
        return Some(NullValue)
      }
      // `A|B|*C|D` — any union choice carrying a leading `*` is the
      // default branch. Walk every top-level union choice (a single
      // string with no `|` falls through as a one-element array). Must
      // run BEFORE the string-literal arm so `"foo"|*"bar"` isn't
      // mistaken for one giant quoted literal.
      let choices = split_top_level_union_choices(name)
      if choices.length() > 1 {
        for choice in choices {
          let trimmed = trim_spaces(choice)
          if trimmed.has_prefix("*") {
            let starred = trim_spaces(
              String::unsafe_substring(trimmed, start=1, end=trimmed.length()),
            )
            return synthesize_default_for_type(
              Some(starred),
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            )
          }
        }
      }
      // String literal type `"foo"` defaults to the literal text.
      if name.length() >= 2 && name[0] == '"' && name[name.length() - 1] == '"' {
        let inner = String::unsafe_substring(
          name,
          start=1,
          end=name.length() - 1,
        )
        return Some(StringValue(inner))
      }
      if name.has_prefix("*") {
        let rest = String::unsafe_substring(name, start=1, end=name.length())
        return synthesize_default_for_type(
          Some(trim_spaces(rest)),
          bindings,
          env,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        )
      }
      // Typealias dereference — `bar: Bar` where
      // `typealias Bar = "foo"|*"bar"` should pick up the starred
      // default through the resolved alias body, not the alias name.
      let aliases = eval_type_alias_bindings(declarations)
      let resolved = eval_resolved_type_alias(name, aliases)
      if resolved != name {
        return synthesize_default_for_type(
          Some(resolved),
          bindings,
          env,
          class_env,
          cache,
          declarations,
          diagnostics,
          resolve_import,
        )
      }
      // Structural collections fall back to their empty form. Set/Map
      // carry dedicated variants that round-trip through the PCF
      // constructor renderer; Listing/Mapping render as block bodies.
      // PKL-148j: `Collection<T>` and `List<T>` default to `ListValue`
      // (Apple Pkl renders `List()` for both, matching the
      // `basic/propertyDefaults` gold).
      if name == "Listing" || name.has_prefix("Listing<") {
        return Some(ListingValue([]))
      }
      if name == "Mapping" || name.has_prefix("Mapping<") {
        return Some(MappingValue([]))
      }
      if name == "Set" || name.has_prefix("Set<") {
        return Some(SetValue([]))
      }
      if name == "Map" || name.has_prefix("Map<") {
        return Some(MapValue([]))
      }
      if name == "List" ||
        name.has_prefix("List<") ||
        name == "Collection" ||
        name.has_prefix("Collection<") {
        return Some(ListValue([]))
      }
      // User-defined class → `new T {}` with class defaults applied.
      let base = match name.find("<") {
        Some(idx) => String::unsafe_substring(name, start=0, end=idx)
        None => name
      }
      match lookup_class_binding(class_env, base) {
        Some(_) =>
          Some(
            apply_class_defaults_for_type(
              ObjectValue([]),
              Some(base),
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ),
          )
        None => None
      }
    }
  }
}

///|
fn coerce_value_to_annotated_type(value : Value, type_name : String?) -> Value {
  match (value, type_name) {
    (ObjectValue(members), Some(name)) if members.length() == 0 => {
      let stripped = strip_lazy_collection_annotation_marker(name)
      let trimmed = pkl_strip_default_type_marker(pkl_constraint_trim(stripped))
      let base = match pkl_constrained_type_base_name(trimmed) {
        Some(base) => base
        None => trimmed
      }
      let head = match base.find("<") {
        Some(idx) => String::unsafe_substring(base, start=0, end=idx)
        None => base
      }
      if head == "Listing" || head == "List" {
        ListingValue([])
      } else if head == "Mapping" {
        MappingValue([])
      } else if head == "Set" {
        // PKL-119 will introduce SetValue; until then collapse to
        // ListingValue (matches how Listing/List share a variant today).
        ListingValue([])
      } else {
        value
      }
    }
    _ => value
  }
}

///|
fn apply_collection_default_for_type(
  value : Value,
  type_name : String?,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value {
  let annotation = match type_name {
    Some(t) => t
    None => return value
  }
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(annotation, aliases)
  let base = match pkl_constrained_type_base_name(resolved) {
    Some(b) => b
    None => resolved
  }
  match generic_argument_text(base, "Listing") {
    Some(element_type) =>
      match value {
        ListingValue(raw_elements) =>
          match
            synthesize_default_for_type(
              Some(element_type),
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(default_value) => {
              if collection_default_value_is_empty(default_value) {
                return value
              }
              match
                materialize_listing_raw_elements(
                  raw_elements, default_value, bindings, env, class_env, cache, stack,
                  declarations, diagnostics, resolve_import,
                ) {
                Some(materialized) =>
                  return DefaultedListingValue(
                    raw_elements, materialized, default_value,
                  )
                None => return value
              }
            }
            None => return value
          }
        _ => return value
      }
    None => ()
  }
  match generic_argument_text(base, "Mapping") {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() != 2 {
        return value
      }
      let value_type = parts[1]
      match value {
        MappingValue(raw_entries) =>
          match
            synthesize_default_for_type(
              Some(value_type),
              bindings,
              env,
              class_env,
              cache,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(default_value) => {
              if collection_default_value_is_empty(default_value) {
                return value
              }
              match
                materialize_mapping_raw_entries(
                  raw_entries, default_value, bindings, env, class_env, cache, stack,
                  declarations, diagnostics, resolve_import,
                ) {
                Some(materialized) =>
                  return DefaultedMappingValue(
                    raw_entries, materialized, default_value,
                  )
                None => return value
              }
            }
            None => return value
          }
        _ => return value
      }
    }
    None => ()
  }
  value
}

///|
fn collection_default_value_is_empty(value : Value) -> Bool {
  match value {
    ObjectValue(members) => visible_members(members).length() == 0
    _ => false
  }
}

///|
fn eval_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match type_name {
    Some(display_name) =>
      match eval_constrained_type_source_name(display_name, aliases) {
        Some(source_name) =>
          match
            pkl_constrained_type_annotation_value_rejection_message_from_source(
              display_name, source_name, value,
            ) {
            Some(message) => {
              diagnostics.push(diag(message))
              false
            }
            None => true
          }
        None => true
      }
    None => true
  }
}

///|
fn eval_user_defined_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match
    pkl_user_defined_constrained_type_annotation_value_rejection_message(
      type_name, value, declarations,
    ) {
    Some(message) => {
      diagnostics.push(diag(message))
      false
    }
    None => true
  }
}

///|
fn eval_lookup_class_decl(
  declarations : Array[Declaration],
  name : String,
) -> ClassDecl? {
  let mut found : ClassDecl? = None
  for declaration in declarations {
    match declaration {
      ClassDeclaration(class_decl) =>
        if class_decl.name == name {
          found = Some(class_decl)
        }
      FunctionDeclaration(_) | TypeAliasDeclaration(_) => ()
    }
  }
  found
}

///|
fn eval_class_property_annotation_with_depth(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut found = false
      let mut annotation : String? = None
      // PKL-148bb: a class's `hidden` properties are stored under
      // `@hidden$<name>` (parser-side prefixing). The caller passes the
      // bare member name (`f`, not `@hidden$f`), so accept either form
      // when matching.
      let hidden_prefixed = hidden_member_name(property_name)
      for property in class_decl.properties {
        if property.name == property_name || property.name == hidden_prefixed {
          found = true
          annotation = property.type_name
        }
      }
      // PKL-148i: a subclass property that omits the type annotation
      // (e.g. `name = "Pigeon"` while the parent declared
      // `name: String`) still inherits the parent's annotation —
      // amend overrides must satisfy it. Walk the parent chain when
      // either the property isn't declared locally OR is declared
      // without its own annotation.
      if found && annotation is Some(_) {
        annotation
      } else {
        match class_decl.parent_name {
          Some(parent_name) =>
            eval_class_property_annotation_with_depth(
              declarations,
              parent_name,
              property_name,
              depth + 1,
            )
          None => None
        }
      }
    }
    None => None
  }
}

///|
fn eval_class_property_annotation(
  declarations : Array[Declaration],
  class_name : String,
  property_name : String,
) -> String? {
  eval_class_property_annotation_with_depth(
    declarations, class_name, property_name, 0,
  )
}

///|

///|
/// PKL-148c: pretty-print a constraint text by re-inserting whitespace
/// around binary comparison / logical operators. `parse_type_text`
/// strips trivia so the captured constraint reads `this>=min` rather
/// than Apple Pkl's `this >= min`; this helper restores the spaces
/// before the text reaches the diagnostic.
fn pretty_constraint_text(text : String) -> String {
  let trimmed = pkl_constraint_trim(text)
  let multi : Array[String] = [">=", "<=", "==", "!=", "&&", "||"]
  let single : Array[Char] = ['>', '<']
  let buf = StringBuilder::new()
  let n = trimmed.length()
  let mut i = 0
  let mut depth = 0
  while i < n {
    let c = trimmed[i].to_int().unsafe_to_char()
    if c == '"' {
      // copy a string literal verbatim
      buf.write_char(c)
      i = i + 1
      while i < n {
        let cc = trimmed[i].to_int().unsafe_to_char()
        buf.write_char(cc)
        i = i + 1
        if cc == '\\' && i < n {
          buf.write_char(trimmed[i].to_int().unsafe_to_char())
          i = i + 1
        } else if cc == '"' {
          break
        }
      }
      continue
    }
    if c == '(' || c == '[' {
      depth = depth + 1
    } else if c == ')' || c == ']' {
      depth = depth - 1
    }
    if depth >= 0 {
      // PKL-148bb: arrow `->` needs symmetric spacing (`(it) -> body`),
      // not just trailing. Handle it ahead of the single-char `>` rule
      // so the `>` branch can't see the `-` first and leave the leading
      // gap unfilled.
      if c == '-' &&
        i + 1 < n &&
        trimmed[i + 1].to_int().unsafe_to_char() == '>' {
        ensure_trailing_space(buf)
        buf.write_string("->")
        buf.write_char(' ')
        i = i + 2
        continue
      }
      // PKL-148bb: commas in argument lists need a trailing space —
      // `parse_type_text` strips trivia between tokens, so the captured
      // text reads `(key,value)` instead of Apple Pkl's `(key, value)`.
      if c == ',' {
        buf.write_char(',')
        if i + 1 < n && trimmed[i + 1].to_int().unsafe_to_char() != ' ' {
          buf.write_char(' ')
        }
        i = i + 1
        continue
      }
      // Check multi-char ops first.
      let mut matched = false
      for op in multi {
        let m = op.length()
        if i + m <= n {
          let mut equal = true
          for j = 0; j < m; j = j + 1 {
            if trimmed[i + j] != op[j] {
              equal = false
              break
            }
          }
          if equal {
            ensure_trailing_space(buf)
            buf.write_string(op)
            buf.write_char(' ')
            i = i + m
            matched = true
            break
          }
        }
      }
      if matched {
        continue
      }
      let mut single_matched = false
      for op in single {
        if c == op {
          // Don't space a `>` that closes a `->` arrow (lambda
          // parameter list — `(it) -> body`), which would split the
          // arrow into `- >`.
          let current = buf.to_string()
          if op == '>' && current.length() > 0 {
            let last = current[current.length() - 1].to_int().unsafe_to_char()
            if last == '-' {
              buf.write_char(op)
              buf.write_char(' ')
              i = i + 1
              single_matched = true
              break
            }
          }
          // Don't space a `<` / `>` that's part of a generic type
          // argument list (rare in constraint texts, but defensive).
          ensure_trailing_space(buf)
          buf.write_char(op)
          buf.write_char(' ')
          i = i + 1
          single_matched = true
          break
        }
      }
      if single_matched {
        continue
      }
    }
    buf.write_char(c)
    i = i + 1
  }
  collapse_spaces(buf.to_string())
}

///|
fn ensure_trailing_space(buf : StringBuilder) -> Unit {
  let current = buf.to_string()
  if current.length() > 0 {
    let last = current[current.length() - 1].to_int().unsafe_to_char()
    if last != ' ' {
      buf.write_char(' ')
    }
  }
}

///|
fn collapse_spaces(text : String) -> String {
  let buf = StringBuilder::new()
  let mut prev_space = false
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == ' ' {
      if !prev_space {
        buf.write_char(' ')
      }
      prev_space = true
    } else {
      buf.write_char(c)
      prev_space = false
    }
  }
  pkl_constraint_trim(buf.to_string())
}

///|
/// PKL-148c: walk an `Expr` tree and replace each bare
/// `Identifier(name)` whose name doesn't appear in the constraint's
/// known scope with `MemberAccess(Identifier("this"), name)`. Apple
/// Pkl's constraint expression body uses implicit-receiver lookup —
/// `abs` inside `Int(abs < 100)` resolves as `this.abs`. We pre-rewrite
/// instead of overloading the Identifier eval arm so the standard
/// resolver stays unchanged for non-constraint expressions.
fn rewrite_implicit_this_in_expr(
  expr : Expr,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  cache : Array[ValueBinding],
) -> Expr {
  match expr {
    Identifier(name) => {
      if name == "this" ||
        name == "module" ||
        name == "true" ||
        name == "false" ||
        name == "null" {
        return expr
      }
      let in_bindings = find_binding(bindings, name) is Some(_)
      let in_env = lookup_value(env, name) is Some(_)
      let in_cache = lookup_value(cache, name) is Some(_)
      if in_bindings || in_env || in_cache {
        expr
      } else {
        MemberAccess(Identifier("this"), name)
      }
    }
    MemberAccess(target, name) =>
      MemberAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        name,
      )
    SafeMemberAccess(target, name) =>
      SafeMemberAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        name,
      )
    SubscriptAccess(target, key) =>
      SubscriptAccess(
        rewrite_implicit_this_in_expr(target, bindings, env, cache),
        rewrite_implicit_this_in_expr(key, bindings, env, cache),
      )
    CallExpr(callee, args) => {
      let new_callee = rewrite_implicit_this_in_expr(
        callee, bindings, env, cache,
      )
      let new_args : Array[Expr] = []
      for a in args {
        new_args.push(rewrite_implicit_this_in_expr(a, bindings, env, cache))
      }
      CallExpr(new_callee, new_args)
    }
    NullSafeCallExpr(callee, args) => {
      let new_callee = rewrite_implicit_this_in_expr(
        callee, bindings, env, cache,
      )
      let new_args : Array[Expr] = []
      for a in args {
        new_args.push(rewrite_implicit_this_in_expr(a, bindings, env, cache))
      }
      NullSafeCallExpr(new_callee, new_args)
    }
    UnaryExpr(op, inner) =>
      UnaryExpr(op, rewrite_implicit_this_in_expr(inner, bindings, env, cache))
    BinaryExpr(op, l, r) =>
      BinaryExpr(
        op,
        rewrite_implicit_this_in_expr(l, bindings, env, cache),
        rewrite_implicit_this_in_expr(r, bindings, env, cache),
      )
    NonNullExpr(inner) =>
      NonNullExpr(rewrite_implicit_this_in_expr(inner, bindings, env, cache))
    ConditionalExpr(c, t, e) =>
      ConditionalExpr(
        rewrite_implicit_this_in_expr(c, bindings, env, cache),
        rewrite_implicit_this_in_expr(t, bindings, env, cache),
        rewrite_implicit_this_in_expr(e, bindings, env, cache),
      )
    _ => expr
  }
}

///|
fn push_constraint_enclosing_member_bindings(
  target_env : Array[ValueBinding],
  members : Array[ValueMember],
  excluded_name : String,
) -> Unit {
  for value_member in members {
    if value_member.name == excluded_name {
      continue
    }
    if !is_invisible_member_name(value_member.name) {
      target_env.push({ name: value_member.name, value: value_member.value })
    } else if value_member.name.has_prefix(local_member_prefix) ||
      value_member.name.has_prefix(hidden_member_prefix) {
      let prefix_len = if value_member.name.has_prefix(local_member_prefix) {
        local_member_prefix.length()
      } else {
        hidden_member_prefix.length()
      }
      let bare = String::unsafe_substring(
        value_member.name,
        start=prefix_len,
        end=value_member.name.length(),
      )
      if bare != excluded_name {
        target_env.push({ name: bare, value: value_member.value })
      }
    }
  }
}

///|
/// PKL-148bb: element-wise constraint cascade for collection-typed
/// class properties. When the type is `Listing<Inner(pred)>` /
/// `List<Inner(pred)>` / `Set<Inner(pred)>` / `Mapping<K,
/// V(pred)>` / `Map<K, V(pred)>` and the inner element type carries
/// a predicate, evaluate the predicate with `this` bound to each
/// element / value. Returns Apple Pkl's `Type constraint
/// \`<pred>\` violated. Value: <element>` on the first miss; None
/// when every element satisfies (or the type has no inner predicate).
fn eval_collection_element_constraint_rejection_message(
  class_name : String,
  property_name : String,
  type_name : String,
  value : Value,
  enclosing_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  let element_type = match generic_argument_text(type_name, "Listing") {
    Some(t) => Some(t)
    None =>
      match generic_argument_text(type_name, "List") {
        Some(t) => Some(t)
        None =>
          match generic_argument_text(type_name, "Set") {
            Some(t) => Some(t)
            None => generic_argument_text(type_name, "Collection")
          }
      }
  }
  match element_type {
    Some(inner) => {
      let inner_constraint = pkl_constrained_type_constraint_text(inner)
      match inner_constraint {
        Some(constraint_text) =>
          match value {
            ListingValue(elements)
            | DefaultedListingValue(_, elements, _)
            | ListValue(elements)
            | SetValue(elements) =>
              for element in elements {
                let parts = pkl_split_constraint_arguments(constraint_text)
                for part in parts {
                  let pred_expr = match parse_constraint_expression(part) {
                    Some(e) => e
                    None => continue
                  }
                  let pred_env = copy_value_bindings(env)
                  pred_env.push({ name: "this", value: element })
                  let super_diags : Array[Diagnostic] = []
                  match lookup_class_binding(class_env, class_name) {
                    Some(class_binding) =>
                      match class_binding.parent_name {
                        Some(parent_name) => {
                          let aliases = eval_type_alias_bindings(declarations)
                          let resolved_parent = eval_resolved_type_alias(
                            parent_name, aliases,
                          )
                          let super_members = eval_class_default_members(
                            resolved_parent, bindings, env, class_env, cache, stack,
                            declarations, super_diags, resolve_import,
                          )
                          pred_env.push({
                            name: "super",
                            value: ObjectValue(super_members),
                          })
                        }
                        None => ()
                      }
                    None => ()
                  }
                  match element {
                    ObjectValue(receiver_members) =>
                      for value_member in receiver_members {
                        if !is_invisible_member_name(value_member.name) {
                          pred_env.push({
                            name: value_member.name,
                            value: value_member.value,
                          })
                        }
                      }
                    _ => ()
                  }
                  push_constraint_enclosing_member_bindings(
                    pred_env, enclosing_members, property_name,
                  )
                  let rewritten = rewrite_implicit_this_in_expr(
                    pred_expr, bindings, pred_env, cache,
                  )
                  let probe_diags : Array[Diagnostic] = []
                  let mut probe = eval_expr_with_bindings(
                    rewritten, bindings, pred_env, class_env, cache, stack, declarations,
                    probe_diags, resolve_import,
                  )
                  if probe is Some(FunctionValue(_, _, _, _, _)) {
                    let apply_diags : Array[Diagnostic] = []
                    let apply_result = eval_expr_with_bindings(
                      CallExpr(MemberAccess(rewritten, "apply"), [
                        Identifier("this"),
                      ]),
                      bindings,
                      pred_env,
                      class_env,
                      cache,
                      stack,
                      declarations,
                      apply_diags,
                      resolve_import,
                    )
                    if apply_diags.length() == 0 {
                      probe = apply_result
                    } else if apply_diags[0].message.has_prefix(
                        "Expected value of type",
                      ) {
                      return Some(apply_diags[0].message)
                    }
                  }
                  match probe {
                    Some(BoolValue(true)) => continue
                    Some(BoolValue(false)) =>
                      return Some(
                        "Type constraint `\{pretty_constraint_text(part)}` violated. Value: \{render_pcf_value_inline(element)}",
                      )
                    _ => continue
                  }
                }
              }
            _ => ()
          }
        None => ()
      }
      return None
    }
    None => ()
  }
  None
}

///|
/// PKL-148c: parse a constraint expression text into an `Expr`. Uses
/// the regular parser by wrapping the source as `__probe = (text)` and
/// pulling the binding's value back out. Returns `None` when the parse
/// fails or the binding is missing — the caller falls through to the
/// existing static predicate path.
fn parse_constraint_expression(text : String) -> Expr? {
  let wrapped = "__probe = (" + text + ")"
  let parsed = parse_source(wrapped)
  for binding in parsed.program.bindings {
    if binding.name == "__probe" {
      return Some(binding.value)
    }
  }
  None
}

///|
fn constraint_function_collection_parameter_error(
  fn_value : Value,
  argument_value : Value,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  match fn_value {
    FunctionValue(parameters, _, _, captured_env, _) => {
      if parameters.length() != 1 {
        return None
      }
      let parameter_type_name = match
        strip_lazy_collection_annotation_marker_opt(parameters[0].type_name) {
        Some(name) => name
        None => return None
      }
      if type_annotation_collection_branch_count(
          parameter_type_name, declarations,
        ) ==
        0 {
        return None
      }
      let call_cache = copy_value_bindings(captured_env)
      push_module_metadata_from_cache(call_cache, cache)
      match
        cast_value_to_type_annotation(
          parameter_type_name, argument_value, bindings, env, class_env, call_cache,
          stack, declarations, resolve_import,
        ) {
        TypeCastOk(casted) =>
          match
            binding_collection_host_constraint_rejection_message(
              Some(parameter_type_name),
              casted,
              declarations,
            ) {
            Some(message) => Some(message)
            None =>
              match first_deferred_error_message(casted) {
                Some(message) =>
                  Some(
                    qualify_collection_parameter_error_message(
                      message, parameter_type_name, class_env, call_cache, declarations,
                    ),
                  )
                None => None
              }
          }
        TypeCastErr(message) => Some(message)
      }
    }
    _ => None
  }
}

///|
fn collection_parameter_value_type_name(
  annotation : String,
  declarations : Array[Declaration],
) -> String? {
  let aliases = eval_type_alias_bindings(declarations)
  let resolved = eval_resolved_type_alias(
    strip_lazy_collection_annotation_marker(annotation),
    aliases,
  )
  let normalized = strip_balanced_outer_type_parens(
    pkl_strip_default_type_marker(pkl_constraint_trim(resolved)),
  )
  let base = match pkl_constrained_type_base_name(normalized) {
    Some(name) => name
    None => normalized
  }
  let inner = match generic_argument_text(base, "Listing") {
    Some(text) => Some(text)
    None =>
      match generic_argument_text(base, "List") {
        Some(text) => Some(text)
        None =>
          match generic_argument_text(base, "Set") {
            Some(text) => Some(text)
            None =>
              match generic_argument_text(base, "Collection") {
                Some(text) => Some(text)
                None =>
                  match generic_argument_text(base, "Mapping") {
                    Some(text) => {
                      let parts = split_top_level_generic_arguments(text)
                      if parts.length() == 2 {
                        Some(parts[1])
                      } else {
                        None
                      }
                    }
                    None =>
                      match generic_argument_text(base, "Map") {
                        Some(text) => {
                          let parts = split_top_level_generic_arguments(text)
                          if parts.length() == 2 {
                            Some(parts[1])
                          } else {
                            None
                          }
                        }
                        None => None
                      }
                  }
              }
          }
      }
  }
  match inner {
    Some(text) => {
      let cleaned = strip_balanced_outer_type_parens(
        pkl_strip_default_type_marker(pkl_constraint_trim(text)),
      )
      Some(
        match pkl_constrained_type_base_name(cleaned) {
          Some(name) => name
          None => cleaned
        },
      )
    }
    None => None
  }
}

///|
fn qualify_collection_parameter_error_message(
  message : String,
  annotation : String,
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  declarations : Array[Declaration],
) -> String {
  let expected = match
    collection_parameter_value_type_name(annotation, declarations) {
    Some(name) => name
    None => return message
  }
  let module_name = match module_name_from_cache(cache) {
    Some(name) => name
    None => return message
  }
  if lookup_class_binding(class_env, expected) is None {
    return message
  }
  let prefix = "Expected value of type `\{expected}`"
  if !message.has_prefix(prefix) {
    return message
  }
  "Expected value of type `\{module_name}#\{expected}`" +
  String::unsafe_substring(message, start=prefix.length(), end=message.length())
}

///|
fn push_constraint_method_scope(
  constraint_cache : Array[ValueBinding],
  class_name : String,
  source_name : String,
  property_value : Value,
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
) -> Unit {
  push_sibling_class_methods(
    constraint_cache, class_name, class_env, env, cache,
  )
  match property_value {
    ObjectValue(receiver_members) => {
      push_receiver_method_bindings(constraint_cache, receiver_members)
      match find_object_class_tag(receiver_members) {
        Some(receiver_class_name) =>
          push_sibling_class_methods(
            constraint_cache, receiver_class_name, class_env, env, constraint_cache,
          )
        None => ()
      }
    }
    _ => ()
  }
  match pkl_constrained_type_base_name(source_name) {
    Some(base_name) =>
      push_sibling_class_methods(
        constraint_cache, base_name, class_env, env, constraint_cache,
      )
    None => ()
  }
}

///|
/// PKL-148c: run an arbitrary constraint expression against a candidate
/// value with `this` bound. When the candidate is an `ObjectValue`, the
/// object's members are also hoisted into the env so the implicit
/// receiver form (`street.endsWith("St.")` rather than
/// `this.street.endsWith("St.")`) resolves. Returns the canonical
/// diagnostic text when the predicate evaluates to `false`.
fn eval_runtime_constraint_for_property(
  class_name : String,
  property_name : String,
  property_value : Value,
  enclosing_members : Array[ValueMember],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  resolve_import : (String) -> EvalResult?,
) -> String? {
  let source_name = match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(s) => s
    None => return None
  }
  // PKL-148bb: when the property type is a `Collection<Inner(...)>`
  // (or List/Set/Listing/Mapping/Map) and the inner type carries its
  // own constraint, fire the inner predicate against each element /
  // entry. The structural element walker only checks the bare type
  // head; the inner constraint stays untouched until this pass.
  // `classes/setConstraints1` exercises `ys: Set<Int(this < 0)>`.
  match
    eval_collection_element_constraint_rejection_message(
      class_name, property_name, source_name, property_value, enclosing_members,
      bindings, env, class_env, cache, stack, declarations, resolve_import,
    ) {
    Some(message) => return Some(message)
    None => ()
  }
  let text = match pkl_constrained_type_constraint_text(source_name) {
    Some(t) => t
    None => return None
  }
  let parts = pkl_split_constraint_arguments(text)
  for part in parts {
    let expr = match parse_constraint_expression(part) {
      Some(e) => e
      None => continue
    }
    // Build a fresh env with `this` bound to the candidate. If the
    // candidate is an ObjectValue, push its members under their bare
    // names too so identifier lookup picks them up before falling
    // through to the surrounding scope (implicit receiver). The
    // enclosing class's other property values are also added so a
    // sibling reference (`Int(this >= min)`) resolves.
    let new_env : Array[ValueBinding] = []
    for binding in env {
      new_env.push(binding)
    }
    new_env.push({ name: "this", value: property_value })
    // PKL-148b: bind `super` to the parent class's resolved defaults so
    // a constraint like `Int(this > super.x)` can read inherited values
    // from inside an amend chain. The parent chain is resolved through
    // `eval_class_default_members`, mirroring the same `super` shape
    // that `eval_class_default_members` plumbs into the defaults cache.
    let super_diags : Array[Diagnostic] = []
    match lookup_class_binding(class_env, class_name) {
      Some(class_binding) =>
        match class_binding.parent_name {
          Some(parent_name) => {
            let aliases = eval_type_alias_bindings(declarations)
            let resolved_parent = eval_resolved_type_alias(parent_name, aliases)
            let super_members = eval_class_default_members(
              resolved_parent, bindings, env, class_env, cache, stack, declarations,
              super_diags, resolve_import,
            )
            new_env.push({ name: "super", value: ObjectValue(super_members) })
          }
          None => ()
        }
      None => ()
    }
    match property_value {
      ObjectValue(receiver_members) =>
        for value_member in receiver_members {
          if !is_invisible_member_name(value_member.name) {
            new_env.push({ name: value_member.name, value: value_member.value })
          }
        }
      _ => ()
    }
    // PKL-148b: a class body's `local` / `hidden` declarations are
    // visible inside that class's constraint expressions, e.g.
    // `local isValid = (n) -> n > x; y: Int(isValid)`. The members
    // sit in `enclosing_members` under their storage-prefixed name
    // (`@local$isValid` / `@hidden$isValid`); strip the prefix so
    // bare-name resolution inside the constraint succeeds.
    push_constraint_enclosing_member_bindings(
      new_env, enclosing_members, property_name,
    )
    let constraint_cache = copy_value_bindings(cache)
    push_constraint_method_scope(
      constraint_cache, class_name, source_name, property_value, new_env, class_env,
      cache,
    )
    // PKL-148c: rewrite bare `Identifier(name)` nodes inside the
    // constraint expression to `MemberAccess(Identifier("this"), name)`
    // when `name` is neither a binding nor in env. Apple Pkl treats
    // `abs` inside `Int(abs < 100)` as `this.abs` because the
    // candidate value is the implicit receiver of the constraint
    // body. Pre-rewriting the tree keeps the existing
    // `eval_expr_with_bindings` flow untouched.
    let rewritten = rewrite_implicit_this_in_expr(
      expr, bindings, new_env, constraint_cache,
    )
    let probe_diags : Array[Diagnostic] = []
    let mut probe_result = eval_expr_with_bindings(
      rewritten, bindings, new_env, class_env, constraint_cache, stack, declarations,
      probe_diags, resolve_import,
    )
    // Apple Pkl treats a constraint-position function reference as a
    // unary call applied to the candidate (`Int(isValid)` ≡
    // `Int(it -> isValid(it))`). When the rewritten predicate
    // evaluates to a FunctionValue rather than a Boolean, replay the
    // probe as `function.apply(this)` so the predicate's result drives
    // the rejection.
    let mut had_function_apply = false
    if probe_result is Some(FunctionValue(_, _, _, _, _) as fn_value) {
      match
        constraint_function_collection_parameter_error(
          fn_value, property_value, bindings, new_env, class_env, constraint_cache,
          stack, declarations, resolve_import,
        ) {
        Some(message) => return Some(message)
        None => ()
      }
      had_function_apply = true
      let apply_diags : Array[Diagnostic] = []
      let apply_result = eval_expr_with_bindings(
        CallExpr(MemberAccess(rewritten, "apply"), [Identifier("this")]),
        bindings,
        new_env,
        class_env,
        constraint_cache,
        stack,
        declarations,
        apply_diags,
        resolve_import,
      )
      if apply_diags.length() == 0 {
        probe_result = apply_result
      } else if apply_diags[0].message.has_prefix("Expected value of type") {
        // PKL-148bh: the apply failed because the predicate's own
        // parameter type rejected the candidate. Apple Pkl surfaces
        // that inner diagnostic verbatim (classes/constraints13:
        // `Listing<Bird>` parameter rejects `Int` element via the
        // standard "Expected value of type ..." wording). Only
        // surface this specific shape so unrelated failures inside
        // the predicate body (e.g. an unimplemented stdlib method)
        // stay silent like they did before.
        return Some(apply_diags[0].message)
      }
    }
    match probe_result {
      Some(BoolValue(true)) => ()
      Some(BoolValue(false)) => {
        // PKL-148d: the diagnostic's `Value:` segment renders
        // ObjectValue candidates with their declared class name
        // (`new Address { ... }` rather than `new { ... }`), matching
        // Apple Pkl's compact-line form.
        let hint = match pkl_constrained_type_base_name(source_name) {
          Some(base) =>
            if base == "Int" ||
              base == "Float" ||
              base == "Number" ||
              base == "Boolean" ||
              base == "String" ||
              base == "Listing" ||
              base == "Mapping" ||
              base == "Set" ||
              base == "Map" ||
              base.has_prefix("Listing<") ||
              base.has_prefix("Mapping<") ||
              base.has_prefix("Set<") ||
              base.has_prefix("Map<") {
              None
            } else {
              Some(base)
            }
          None => None
        }
        return Some(
          "Type constraint `\{pretty_constraint_text(part)}` violated. Value: \{render_pcf_value_inline_compact(property_value, hint)}",
        )
      }
      // PKL-148bb: Apple Pkl rejects a constraint predicate that
      // evaluates to anything other than Boolean / Function with
      // `Expected value of type \`Boolean\` or \`Function\`, but got
      // type \`<T>\`. Value: <v>`. After the `function.apply(this)`
      // replay above, the wording narrows to just `\`Boolean\``
      // because the function reference was already resolved
      // (`classes/constraints9`: `Int("not a boolean")` vs
      // `Int((x) -> "not a boolean")`).
      //
      // A trailing `FunctionValue` here means the apply replay landed
      // diagnostics and we kept the raw probe; fall through silently
      // so the static-cascade fallback for predicates whose function
      // reference does resolve at runtime stays intact
      // (`classes/constraints10`).
      Some(FunctionValue(_, _, _, _, _)) => ()
      Some(non_bool_value) => {
        let actual = eval_value_type_name(non_bool_value)
        let expected = if had_function_apply {
          "`Boolean`"
        } else {
          "`Boolean` or `Function`"
        }
        return Some(
          "Expected value of type \{expected}, but got type `\{actual}`. Value: \{render_pcf_value_inline(non_bool_value)}",
        )
      }
      None => ()
    }
  }
  None
}

///|
fn eval_class_property_constraint_value_rejection_message(
  class_name : String,
  property_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      let display_name = "\{class_name} member \{property_name}"
      // PKL-148b: a class property typed `Listing<...>(...)` whose
      // amend body is empty (`l {}`) initially evaluates to an empty
      // ObjectValue. Coerce to ListingValue before the constraint
      // dispatch so the Listing-host predicate (e.g. `!isEmpty`) fires.
      let coerced = coerce_value_to_annotated_type(value, Some(source_name))
      match
        pkl_constrained_type_annotation_value_rejection_message_from_source(
          display_name, source_name, coerced,
        ) {
        Some(message) => Some(message)
        None =>
          pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
            display_name, source_name, coerced, declarations,
          )
      }
    }
    None => None
  }
}

///|
/// PKL-148i: reject an assignment whose value's runtime type doesn't
/// satisfy the property's declared type annotation. The existing
/// `eval_class_property_constraint_value_rejection_message` only
/// dispatches predicate-style constraints (`Int(x > 0)`), so a bare
/// type annotation like `name: String` never fires when the supplied
/// value is the wrong shape (`new Person { name = 42 }` evaluated to
/// `42` instead of producing the upstream rejection diagnostic).
/// Mirrors the surface of `eval_callable_return_rejection_message`:
/// resolve type alias, accept type parameters, and only emit when
/// neither the builtin acceptance set nor a user-class annotation
/// satisfies the value.
fn eval_class_property_type_rejection_message(
  class_name : String,
  property_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    eval_class_property_annotation(declarations, class_name, property_name) {
    Some(source_name) => {
      if eval_type_name_is_type_parameter(source_name, declarations) {
        return None
      }
      // PKL-148bb: arity mismatch on a function-typed property (`f:
      // () -> Int` amended with `(str) -> str.length`) projects to
      // `Expected value of type \`FunctionN\`, but got type
      // \`FunctionM\`. Value: new FunctionM {}` (`classes/lambdaConstraints1`).
      match (function_type_arity(source_name), value) {
        (Some(expected), FunctionValue(params, _, _, _, _)) => {
          let actual = params.length()
          if expected != actual {
            return Some(
              "Expected value of type `Function\{expected}`, but got type `Function\{actual}`. Value: new Function\{actual} {}",
            )
          }
        }
        _ => ()
      }
      let aliases = eval_type_alias_bindings(declarations)
      let resolved_type_name = eval_resolved_type_alias(source_name, aliases)
      let base = match pkl_constrained_type_base_name(resolved_type_name) {
        Some(b) => b
        None => resolved_type_name
      }
      let coerced = coerce_value_to_annotated_type(value, Some(source_name))
      let choices = split_top_level_union_choices(base)
      if choices.length() > 1 {
        let mut any_known_head = false
        for choice in choices {
          let trimmed = pkl_strip_default_type_marker(
            pkl_constraint_trim(choice),
          )
          let without_constraint = match
            pkl_constrained_type_base_name(trimmed) {
            Some(b) => b
            None => trimmed
          }
          let stripped_q = if without_constraint.has_suffix("?") {
            String::unsafe_substring(
              without_constraint,
              start=0,
              end=without_constraint.length() - 1,
            )
          } else {
            without_constraint
          }
          let head = {
            let mut cut = -1
            let n = stripped_q.length()
            for i = 0; i < n; i = i + 1 {
              if stripped_q[i].to_int().unsafe_to_char() == '<' {
                cut = i
                break
              }
            }
            if cut < 0 {
              stripped_q
            } else {
              String::unsafe_substring(stripped_q, start=0, end=cut)
            }
          }
          let head_with_optional = if without_constraint.has_suffix("?") {
            head + "?"
          } else {
            head
          }
          if eval_value_accepts_type_annotation(head_with_optional, coerced) {
            return eval_resolved_collection_element_structural_rejection_message(
              stripped_q, coerced, declarations,
            )
          }
          if value_satisfies_user_class_annotation(head, coerced, declarations) {
            return None
          }
          if is_stdlib_class_name(head) ||
            eval_lookup_class_decl(declarations, head) is Some(_) {
            any_known_head = true
          }
        }
        if !any_known_head {
          return None
        }
        let diag_name = rejection_type_label(base)
        if coerced is NullValue {
          return Some("Expected value of type `\{diag_name}`, but got `null`.")
        }
        return Some(
          "Expected value of type `\{diag_name}`, but got type `\{eval_value_type_name(coerced)}`. Value: \{render_pcf_value_inline(coerced)}",
        )
      }
      // Normalize generic type heads (`Listing<X>` → `Listing`,
      // `Mapping<K,V>` → `Mapping`, `Pair<A,B>` → `Pair`, …) before
      // the acceptance check; `eval_value_accepts_type_annotation`
      // matches against the bare collection name.
      let stripped_q = if base.has_suffix("?") {
        String::unsafe_substring(base, start=0, end=base.length() - 1)
      } else {
        base
      }
      let head = {
        let mut cut = -1
        let n = stripped_q.length()
        for i = 0; i < n; i = i + 1 {
          if stripped_q[i].to_int().unsafe_to_char() == '<' {
            cut = i
            break
          }
        }
        if cut < 0 {
          stripped_q
        } else {
          String::unsafe_substring(stripped_q, start=0, end=cut)
        }
      }
      let head_with_optional = if base.has_suffix("?") {
        head + "?"
      } else {
        head
      }
      if eval_value_accepts_type_annotation(head_with_optional, coerced) {
        // Structural element check for generic collections — Apple Pkl
        // surfaces `Expected value of type \`Int\`...` for
        // `xs: List<Int>` amended with `List("one")`.
        return eval_resolved_collection_element_structural_rejection_message(
          stripped_q, coerced, declarations,
        )
      }
      if value_satisfies_user_class_annotation(head, coerced, declarations) {
        return None
      }
      // Only reject for stdlib type names or known user classes;
      // unknown annotations stay silent (matches the legacy behaviour
      // for not-yet-implemented surface).
      if !is_stdlib_class_name(head) &&
        !(eval_lookup_class_decl(declarations, head) is Some(_)) {
        return None
      }
      let diag_name = rejection_type_label(base)
      if coerced is NullValue {
        return Some("Expected value of type `\{diag_name}`, but got `null`.")
      }
      Some(
        "Expected value of type `\{diag_name}`, but got type `\{eval_value_type_name(coerced)}`. Value: \{render_pcf_value_inline(coerced)}",
      )
    }
    None => None
  }
}

///|
fn eval_object_member_expr_is_provided(
  members : Array[ObjectMember],
  name : String,
) -> Bool {
  for field in members {
    if field.name == name {
      return true
    }
  }
  false
}

///|
fn eval_class_property_default_constraints_are_valid_with_depth(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  depth : Int,
) -> Bool {
  if depth > 8 {
    return true
  }
  match eval_lookup_class_decl(declarations, class_name) {
    Some(class_decl) => {
      let mut ok = true
      match class_decl.parent_name {
        Some(parent_name) =>
          if !eval_class_property_default_constraints_are_valid_with_depth(
              parent_name,
              provided_members,
              values,
              declarations,
              diagnostics,
              depth + 1,
            ) {
            ok = false
          }
        None => ()
      }
      for property in class_decl.properties {
        if property.value is Some(_) &&
          !eval_object_member_expr_is_provided(provided_members, property.name) {
          match lookup_member(values, property.name) {
            Some(default_value) =>
              match
                eval_class_property_constraint_value_rejection_message(
                  class_name,
                  property.name,
                  default_value,
                  declarations,
                ) {
                Some(message) => {
                  diagnostics.push(diag(message))
                  ok = false
                }
                None => ()
              }
            None => ()
          }
        }
      }
      ok
    }
    None => true
  }
}

///|
fn eval_class_property_default_constraints_are_valid(
  class_name : String,
  provided_members : Array[ObjectMember],
  values : Array[ValueMember],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  eval_class_property_default_constraints_are_valid_with_depth(
    class_name, provided_members, values, declarations, diagnostics, 0,
  )
}

///|
fn eval_expr_class_property_constraints_are_valid(
  expr : Expr,
  value : Value,
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (TypedObjectLiteral(class_name, members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) => {
            match
              eval_class_property_constraint_value_rejection_message(
                class_name,
                field.name,
                member_value,
                declarations,
              ) {
              Some(message) => {
                diagnostics.push(diag(message))
                ok = false
              }
              None => ()
            }
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          }
          None => ()
        }
      }
      if !eval_class_property_default_constraints_are_valid(
          class_name, members, values, declarations, diagnostics,
        ) {
        ok = false
      }
      ok
    }
    (ObjectLiteral(members), ObjectValue(values)) => {
      let mut ok = true
      for field in members {
        match lookup_member(values, field.name) {
          Some(member_value) =>
            if !eval_expr_class_property_constraints_are_valid(
                field.value,
                member_value,
                declarations,
                diagnostics,
              ) {
              ok = false
            }
          None => ()
        }
      }
      ok
    }
    _ => true
  }
}

///|
fn eval_object_member_alias_constraints_are_valid(
  members : Array[ObjectMember],
  values : Array[ValueMember],
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  let mut ok = true
  for object_member in members {
    match lookup_member(values, object_member.name) {
      Some(value) => {
        if !eval_constrained_type_annotation_value_is_valid(
            object_member.type_name,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
        if !eval_expr_alias_constraints_are_valid(
            object_member.value,
            value,
            aliases,
            diagnostics,
          ) {
          ok = false
        }
      }
      None => ()
    }
  }
  ok
}

///|
fn eval_expr_alias_constraints_are_valid(
  expr : Expr,
  value : Value,
  aliases : Array[EvalTypeAliasBinding],
  diagnostics : Array[Diagnostic],
) -> Bool {
  match (expr, value) {
    (ObjectLiteral(members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    (TypedObjectLiteral(_, members), ObjectValue(values)) =>
      eval_object_member_alias_constraints_are_valid(
        members, values, aliases, diagnostics,
      )
    _ => true
  }
}
