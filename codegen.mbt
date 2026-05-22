///|
/// PKL-131b: target-driven codegen dispatcher. Only `MoonBit` is wired
/// today; the enum + dispatcher pair keeps the public surface stable
/// when future targets (Java / Kotlin / Swift / Go / TypeScript) land
/// — embedders never need to swap entry points or learn a new
/// per-target function name.
pub(all) enum CodegenTarget {
  MoonBit
} derive(Eq, Debug)

///|
/// PKL-131b: single entry point for codegen, parametric over the
/// target language. Returns the generated source as a String;
/// embedders write it to disk / a stream as they see fit. Each
/// target's lowering rules live in its own helper so the dispatcher
/// stays a one-line `match`.
pub fn codegen(program : Program, target : CodegenTarget) -> String {
  match target {
    MoonBit => codegen_moonbit(program)
  }
}

///|
/// PKL-131: lower a parsed Pkl module into a MoonBit source skeleton
/// so embedders can round-trip schemas through both type systems.
///
/// Today's scope:
///   - `class C { p: T = ... }` → `pub(all) struct C { p : T_mbt } derive(Eq, Show)`
///   - `typealias A = T` → `pub typealias A = T_mbt`
///   - `function` declarations are skipped (no data-shape MoonBit
///     equivalent; configure them at the embedder side).
///
/// Type mapping is intentionally narrow — when a Pkl type doesn't
/// have a faithful MoonBit counterpart, the emitter falls back to a
/// commented `// TODO: <pkl-type>` line above the field so the
/// human-in-the-loop can decide the right shape.
fn codegen_moonbit(program : Program) -> String {
  let buf = StringBuilder::new()
  let module_label = match program.module_name {
    Some(name) => name
    None => "<anonymous>"
  }
  buf.write_string("// Generated from `\{module_label}` by pkl-mbt codegen.\n")
  buf.write_string("// PKL-131 — Do not edit by hand.\n")
  let mut first = true
  for declaration in program.declarations {
    match declaration {
      ClassDeclaration(class_decl) => {
        if first {
          buf.write_char('\n')
          first = false
        } else {
          buf.write_char('\n')
        }
        emit_class_struct(class_decl, buf)
      }
      TypeAliasDeclaration(type_alias) => {
        if first {
          buf.write_char('\n')
          first = false
        } else {
          buf.write_char('\n')
        }
        emit_typealias(type_alias, buf)
      }
      // PKL-131: module-level functions don't have a MoonBit
      // struct / enum analogue — they encode behaviour, not shape.
      // The embedder typically rewrites them by hand against their
      // existing function library.
      FunctionDeclaration(_) => ()
    }
  }
  buf.to_string()
}

///|
fn emit_class_struct(class_decl : ClassDecl, buf : StringBuilder) -> Unit {
  buf.write_string("///|\n")
  buf.write_string("pub(all) struct \{class_decl.name} {\n")
  for prop in class_decl.properties {
    let mbt_type = match prop.type_name {
      Some(type_name) => pkl_type_to_moonbit(type_name)
      None => "Unit /* TODO: untyped property */"
    }
    buf.write_string("  \{prop.name} : \{mbt_type}\n")
  }
  buf.write_string("} derive(Eq, Show)\n")
}

///|
fn emit_typealias(type_alias : TypeAliasDecl, buf : StringBuilder) -> Unit {
  let target = pkl_type_to_moonbit(type_alias.target)
  buf.write_string("///|\n")
  buf.write_string("pub typealias \{target} as \{type_alias.name}\n")
}

///|
/// PKL-131: translate a Pkl type-annotation source string into the
/// closest MoonBit type. The mapping covers the common scalar and
/// container shapes; anything outside drops into a `Unknown` slot
/// with a TODO comment so the generated file still parses and the
/// embedder gets a flag they can grep for.
fn pkl_type_to_moonbit(text : String) -> String {
  let trimmed = trim_codegen_spaces(text)
  // Nullable suffix is treated structurally: `T?` → `T_mbt?`.
  if trimmed.has_suffix("?") {
    let inner = String::unsafe_substring(
      trimmed,
      start=0,
      end=trimmed.length() - 1,
    )
    return "\{pkl_type_to_moonbit(inner)}?"
  }
  // Constraint suffix `Int(isPositive)` → `Int`. The constraint stays
  // a Pkl-side validator; codegen strips it because MoonBit doesn't
  // model dependent / refinement types here.
  match strip_codegen_constraint(trimmed) {
    Some(base) => return pkl_type_to_moonbit(base)
    None => ()
  }
  // Generic shapes — recognise the head and recurse on the arguments.
  match split_codegen_generic(trimmed) {
    Some((head, args)) =>
      match head {
        "Listing" | "List" =>
          if args.length() == 1 {
            return "Array[\{pkl_type_to_moonbit(args[0])}]"
          }
        "Mapping" | "Map" =>
          if args.length() == 2 {
            let k = pkl_type_to_moonbit(args[0])
            let v = pkl_type_to_moonbit(args[1])
            return "Map[\{k}, \{v}]"
          }
        "Set" =>
          if args.length() == 1 {
            // No ordered-unique container in moonbitlang/core yet;
            // emit an Array with a TODO note for the embedder.
            return "Array[\{pkl_type_to_moonbit(args[0])}] /* Set */"
          }
        "Pair" =>
          if args.length() == 2 {
            let a = pkl_type_to_moonbit(args[0])
            let b = pkl_type_to_moonbit(args[1])
            return "(\{a}, \{b})"
          }
        _ => ()
      }
    None => ()
  }
  // Union types collapse to the first branch with a TODO comment
  // because MoonBit's enums need names; the embedder usually wants
  // to pick a discriminated form by hand.
  if has_top_level_pipe(trimmed) {
    return "Unit /* TODO: union \{trimmed} */"
  }
  // String-literal type (`"alpha"` etc.) — Pkl narrows at the type
  // level; MoonBit uses plain String.
  if trimmed.length() >= 2 &&
    trimmed.has_prefix("\"") &&
    trimmed.has_suffix("\"") {
    return "String"
  }
  match trimmed {
    "Int" => "Int"
    "Float" => "Double"
    "Number" => "Double /* Number */"
    "Boolean" | "Bool" => "Bool"
    "String" => "String"
    "Null" => "Unit"
    "Any" => "Unit /* TODO: Any */"
    "Unknown" => "Unit /* TODO: Unknown */"
    "IntSeq" => "Array[Int] /* IntSeq */"
    "Duration" => "Double /* Duration */"
    "DataSize" => "Double /* DataSize */"
    "Regex" => "String /* Regex pattern */"
    "Bytes" => "Bytes"
    other => other
  }
}

///|
fn trim_codegen_spaces(s : String) -> String {
  let mut start = 0
  while start < s.length() {
    let c = s[start].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      start = start + 1
    } else {
      break
    }
  }
  let mut endIdx = s.length()
  while endIdx > start {
    let c = s[endIdx - 1].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      endIdx = endIdx - 1
    } else {
      break
    }
  }
  if start == 0 && endIdx == s.length() {
    s
  } else {
    String::unsafe_substring(s, start~, end=endIdx)
  }
}

///|
fn strip_codegen_constraint(text : String) -> String? {
  // Recognise `Base(...)` where the parens balance to the end. Returns
  // the base name on a hit, `None` otherwise.
  let mut idx = -1
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == '(' {
      idx = i
      break
    }
  }
  if idx <= 0 || !text.has_suffix(")") {
    return None
  }
  let mut depth = 0
  for i = idx; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth == 0 && i != text.length() - 1 {
        return None
      }
    }
  }
  Some(String::unsafe_substring(text, start=0, end=idx))
}

///|
fn split_codegen_generic(text : String) -> (String, Array[String])? {
  let mut idx = -1
  let mut parens = 0
  let mut brackets = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == '(' {
      parens = parens + 1
    } else if c == ')' && parens > 0 {
      parens = parens - 1
    } else if c == '[' {
      brackets = brackets + 1
    } else if c == ']' && brackets > 0 {
      brackets = brackets - 1
    } else if c == '<' && parens == 0 && brackets == 0 {
      idx = i
      break
    }
  }
  if idx <= 0 || !text.has_suffix(">") {
    return None
  }
  let base = String::unsafe_substring(text, start=0, end=idx)
  let inner = String::unsafe_substring(
    text,
    start=idx + 1,
    end=text.length() - 1,
  )
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_angle = 0
  for c in inner {
    if c == ',' && depth_paren == 0 && depth_bracket == 0 && depth_angle == 0 {
      parts.push(trim_codegen_spaces(buf.to_string()))
      buf.reset()
    } else {
      if c == '(' {
        depth_paren = depth_paren + 1
      } else if c == ')' && depth_paren > 0 {
        depth_paren = depth_paren - 1
      } else if c == '[' {
        depth_bracket = depth_bracket + 1
      } else if c == ']' && depth_bracket > 0 {
        depth_bracket = depth_bracket - 1
      } else if c == '<' {
        depth_angle = depth_angle + 1
      } else if c == '>' && depth_angle > 0 {
        depth_angle = depth_angle - 1
      }
      buf.write_char(c)
    }
  }
  let last = trim_codegen_spaces(buf.to_string())
  if last != "" || parts.length() > 0 {
    parts.push(last)
  }
  Some((base, parts))
}

///|
fn has_top_level_pipe(text : String) -> Bool {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int().unsafe_to_char()
    if c == '(' {
      parens = parens + 1
    } else if c == ')' && parens > 0 {
      parens = parens - 1
    } else if c == '[' {
      brackets = brackets + 1
    } else if c == ']' && brackets > 0 {
      brackets = brackets - 1
    } else if c == '<' {
      angles = angles + 1
    } else if c == '>' && angles > 0 {
      angles = angles - 1
    } else if c == '|' && parens == 0 && brackets == 0 && angles == 0 {
      return true
    }
  }
  false
}
