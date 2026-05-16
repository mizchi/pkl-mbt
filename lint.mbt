///|
/// PKL-102: lightweight static-analysis checks surfaced through
/// `pkl analyze <file>`. Each finding identifies a category (`rule`)
/// and carries a human-readable message. Source positions become
/// useful once PKL-107 propagates byte offsets into the AST; until
/// then the CLI prints `path: rule: message` and the byte offsets
/// stay at -1.
pub(all) struct LintFinding {
  rule : String
  message : String
} derive(Eq, Debug)

///|
/// Entry point: walk `program` once per rule and accumulate findings
/// in source order so the CLI output is stable across runs.
pub fn lint_program(program : Program) -> Array[LintFinding] {
  let findings : Array[LintFinding] = []
  check_unused_local_bindings(program, findings)
  check_unused_imports(program, findings)
  check_unused_class_properties(program, findings)
  check_shadowed_identifiers(program, findings)
  findings
}

///|
/// Module-level `local foo = ...` (parser sets `exported: false`)
/// whose name never appears on the right-hand side of any other
/// expression in the module. Exported bindings are part of the
/// module's surface, so they are not candidates here.
fn check_unused_local_bindings(
  program : Program,
  out : Array[LintFinding],
) -> Unit {
  for binding in program.bindings {
    if binding.exported {
      continue
    }
    if !identifier_referenced(
        program,
        binding.name,
        skip_binding=Some(binding.name),
      ) {
      out.push({
        rule: "unused-local-binding",
        message: "local binding `\{binding.name}` is never referenced",
      })
    }
  }
}

///|
/// `import "foo.pkl" as Bar` (or the implicit `import "foo.pkl"`
/// shorthand the parser fills in) where `Bar` never appears as an
/// identifier reference anywhere in the module body.
fn check_unused_imports(program : Program, out : Array[LintFinding]) -> Unit {
  for imp in program.imports {
    if !identifier_referenced(program, imp.import_name, skip_binding=None) {
      out.push({
        rule: "unused-import",
        message: "import `\{imp.import_name}` (from \"\{imp.uri}\") is never referenced",
      })
    }
  }
}

///|
/// Class properties that are never read from inside the same module.
/// To avoid flagging public schema (Pkl class properties are commonly
/// part of the module's exported surface), only classes whose own
/// name is never referenced in the module are inspected. That covers
/// the "I added a temp helper class and forgot to remove it" failure
/// mode without yelling about every config-schema class.
fn check_unused_class_properties(
  program : Program,
  out : Array[LintFinding],
) -> Unit {
  for decl in program.declarations {
    match decl {
      ClassDeclaration(cd) => {
        if identifier_referenced(program, cd.name, skip_binding=None) {
          continue
        }
        for prop in cd.properties {
          if prop.value is None {
            continue
          }
          if !class_property_referenced(cd, prop.name) {
            out.push({
              rule: "unused-class-property",
              message: "property `\{prop.name}` of unused class `\{cd.name}` is never referenced",
            })
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// Module-level shadowing: a local binding whose name collides with
/// another module-level name (import, function, class, typealias, or
/// another binding declared earlier in source order). Catches the
/// typical "I named a helper the same as an import" mistake without
/// the cost of full scope analysis.
fn check_shadowed_identifiers(
  program : Program,
  out : Array[LintFinding],
) -> Unit {
  let seen : Map[String, String] = Map([], capacity=16)
  for imp in program.imports {
    seen[imp.import_name] = "import"
  }
  for decl in program.declarations {
    match decl {
      ClassDeclaration(cd) =>
        if !seen.contains(cd.name) {
          seen[cd.name] = "class"
        }
      FunctionDeclaration(fd) =>
        if !seen.contains(fd.name) {
          seen[fd.name] = "function"
        }
      TypeAliasDeclaration(td) =>
        if !seen.contains(td.name) {
          seen[td.name] = "typealias"
        }
    }
  }
  for binding in program.bindings {
    match seen.get(binding.name) {
      Some(kind) =>
        out.push({
          rule: "shadowed-identifier",
          message: "binding `\{binding.name}` shadows existing \{kind} of the same name",
        })
      None => seen[binding.name] = "binding"
    }
  }
}

///|
/// True when `name` appears as an `Identifier(name)` (or as a
/// receiver of a member-access chain that bottoms out in
/// `Identifier(name)`) anywhere in the module body. The
/// `skip_binding` parameter excludes a single binding's own RHS so a
/// recursive-looking definition doesn't count as a self-reference.
fn identifier_referenced(
  program : Program,
  name : String,
  skip_binding~ : String?,
) -> Bool {
  for binding in program.bindings {
    if skip_binding is Some(skip) && binding.name == skip {
      continue
    }
    if binding.type_name is Some(tn) && type_name_references(tn, name) {
      return true
    }
    if expr_references(binding.value, name) {
      return true
    }
  }
  for decl in program.declarations {
    match decl {
      ClassDeclaration(cd) => {
        if cd.parent_name is Some(pname) && pname == name {
          return true
        }
        for prop in cd.properties {
          if prop.type_name is Some(tn) && type_name_references(tn, name) {
            return true
          }
          if prop.value is Some(value) && expr_references(value, name) {
            return true
          }
        }
        for fn_decl in cd.methods {
          if function_references(fn_decl, name) {
            return true
          }
        }
      }
      FunctionDeclaration(fd) =>
        if function_references(fd, name) {
          return true
        }
      TypeAliasDeclaration(td) =>
        if type_name_references(td.target, name) {
          return true
        }
    }
  }
  if program.body is Some(body) && expr_references(body, name) {
    return true
  }
  false
}

///|
fn function_references(fd : FunctionDecl, name : String) -> Bool {
  for param in fd.parameters {
    if param.type_name is Some(tn) && type_name_references(tn, name) {
      return true
    }
  }
  if fd.return_type_name is Some(tn) && type_name_references(tn, name) {
    return true
  }
  if fd.body is Some(body) && expr_references(body, name) {
    return true
  }
  false
}

///|
/// True when `name` appears inside the same class body (other
/// properties' RHS, methods' bodies, or parent_name). Used by the
/// unused-class-property check so a property referenced by its
/// siblings stays alive.
fn class_property_referenced(cd : ClassDecl, name : String) -> Bool {
  for prop in cd.properties {
    if prop.name == name {
      continue
    }
    if prop.value is Some(value) && expr_references(value, name) {
      return true
    }
  }
  for fn_decl in cd.methods {
    if function_references(fn_decl, name) {
      return true
    }
  }
  false
}

///|
/// Conservative recursive walker: returns true if `Identifier(name)`
/// appears anywhere in `expr`. Member access (`Foo.bar`) bottoms out
/// on the receiver, so `Foo` counts as a reference to an import
/// named `Foo`.
fn expr_references(expr : Expr, name : String) -> Bool {
  match expr {
    IntLiteral(_) => false
    FloatLiteral(_) => false
    BoolLiteral(_) => false
    StringLiteral(_) => false
    NullLiteral => false
    Identifier(n) => n == name
    ImportExpr(_) => false
    ObjectLiteral(members) => members_reference(members, name)
    TypedObjectLiteral(type_name, members) =>
      type_name == name || members_reference(members, name)
    ListingLiteral(elements) => elements_reference(elements, name)
    MappingLiteral(entries) => {
      for entry in entries {
        if expr_references(entry.key, name) ||
          expr_references(entry.value, name) {
          return true
        }
      }
      false
    }
    MemberAccess(target, _) => expr_references(target, name)
    SafeMemberAccess(target, _) => expr_references(target, name)
    SubscriptAccess(target, key) =>
      expr_references(target, name) || expr_references(key, name)
    AmendExpr(base, members) =>
      expr_references(base, name) || members_reference(members, name)
    CallExpr(callee, arguments) =>
      expr_references(callee, name) || elements_reference(arguments, name)
    LambdaExpr(params, body, _) => {
      for param in params {
        if param.name == name {
          return false
        }
      }
      expr_references(body, name)
    }
    NonNullExpr(inner) => expr_references(inner, name)
    UnaryExpr(_, inner) => expr_references(inner, name)
    BinaryExpr(_, left, right) =>
      expr_references(left, name) || expr_references(right, name)
    ConditionalExpr(cond, then_branch, else_branch) =>
      expr_references(cond, name) ||
      expr_references(then_branch, name) ||
      expr_references(else_branch, name)
    ForGenerator(key_name, value_name, source, members) => {
      if key_name == name {
        return false
      }
      if value_name is Some(vn) && vn == name {
        return false
      }
      expr_references(source, name) || members_reference(members, name)
    }
    WhenSpread(inner) => expr_references(inner, name)
    InterpolatedString(parts) => elements_reference(parts, name)
    NullSafeCallExpr(callee, arguments) =>
      expr_references(callee, name) || elements_reference(arguments, name)
    UnsupportedExpr => false
    ErrorExpr(_) => false
  }
}

///|
fn members_reference(members : Array[ObjectMember], name : String) -> Bool {
  for om in members {
    if expr_references(om.value, name) {
      return true
    }
  }
  false
}

///|
fn elements_reference(elements : Array[Expr], name : String) -> Bool {
  for element in elements {
    if expr_references(element, name) {
      return true
    }
  }
  false
}

///|
/// Surface-level scan for type-annotation strings. The parser keeps
/// type annotations as their raw textual form (e.g. `"Listing<Box>"`,
/// `"Box?"`), so a substring search bounded by identifier-character
/// boundaries is enough to spot a referenced type name without
/// pulling in the full type parser.
fn type_name_references(type_name : String, name : String) -> Bool {
  if name == "" {
    return false
  }
  let nlen = name.length()
  let tlen = type_name.length()
  if tlen < nlen {
    return false
  }
  let mut i = 0
  while i + nlen <= tlen {
    let mut matched = true
    let mut j = 0
    while j < nlen {
      if type_name[i + j] != name[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      let prev_ok = if i == 0 {
        true
      } else {
        !is_identifier_byte(type_name[i - 1].to_int())
      }
      let next_ok = if i + nlen == tlen {
        true
      } else {
        !is_identifier_byte(type_name[i + nlen].to_int())
      }
      if prev_ok && next_ok {
        return true
      }
    }
    i = i + 1
  }
  false
}

///|
fn is_identifier_byte(b : Int) -> Bool {
  let c = b.unsafe_to_char()
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}
