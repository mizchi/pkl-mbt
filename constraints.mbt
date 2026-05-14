///|
priv struct ConstraintIntRange {
  lower : Int
  upper : Int
}

///|
fn pkl_parse_constraint_int_text(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut index = 0
  let mut sign = 1
  if text[0].to_int().unsafe_to_char() == '-' {
    sign = -1
    index = 1
  }
  if index == text.length() {
    return None
  }
  let mut value = 0
  while index < text.length() {
    let char = text[index].to_int().unsafe_to_char()
    if char < '0' || char > '9' {
      return None
    }
    value = value * 10 + char.to_int() - '0'.to_int()
    index += 1
  }
  Some(value * sign)
}

///|
fn pkl_split_constraint_arguments(text : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for char in text {
    if char == ',' && parens == 0 && brackets == 0 && angles == 0 {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      if char == '(' {
        parens += 1
      } else if char == ')' && parens > 0 {
        parens -= 1
      } else if char == '[' {
        brackets += 1
      } else if char == ']' && brackets > 0 {
        brackets -= 1
      } else if char == '<' {
        angles += 1
      } else if char == '>' && angles > 0 {
        angles -= 1
      }
      buf.write_string(char.to_string())
    }
  }
  let last = buf.to_string()
  if last != "" || parts.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn pkl_constrained_type_paren_index(name : String) -> Int? {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for i = 0; i < name.length(); i = i + 1 {
    let char = name[i].to_int().unsafe_to_char()
    if char == '(' && parens == 0 && brackets == 0 && angles == 0 {
      if i == 0 {
        return None
      }
      return Some(i)
    }
    if char == '(' {
      parens += 1
    } else if char == ')' && parens > 0 {
      parens -= 1
    } else if char == '[' {
      brackets += 1
    } else if char == ']' && brackets > 0 {
      brackets -= 1
    } else if char == '<' && parens == 0 && brackets == 0 {
      angles += 1
    } else if char == '>' && parens == 0 && brackets == 0 && angles > 0 {
      angles -= 1
    }
  }
  None
}

///|
fn pkl_constrained_type_suffix_is_balanced(name : String, start : Int) -> Bool {
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for i = start; i < name.length(); i = i + 1 {
    let char = name[i].to_int().unsafe_to_char()
    if char == '(' {
      parens += 1
    } else if char == ')' {
      parens -= 1
      if parens < 0 {
        return false
      }
    } else if char == '[' {
      brackets += 1
    } else if char == ']' {
      brackets -= 1
      if brackets < 0 {
        return false
      }
    } else if char == '<' && parens == 0 && brackets == 0 {
      angles += 1
    } else if char == '>' && parens == 0 && brackets == 0 {
      angles -= 1
      if angles < 0 {
        return false
      }
    }
  }
  parens == 0 && brackets == 0 && angles == 0
}

///|
fn pkl_constrained_type_base_name(name : String) -> String? {
  match pkl_constrained_type_paren_index(name) {
    Some(index) =>
      if name.has_suffix(")") &&
        pkl_constrained_type_suffix_is_balanced(name, index) {
        Some(String::unsafe_substring(name, start=0, end=index))
      } else {
        None
      }
    None => None
  }
}

///|
fn pkl_constrained_type_constraint_text(name : String) -> String? {
  match pkl_constrained_type_paren_index(name) {
    Some(index) =>
      if name.has_suffix(")") &&
        pkl_constrained_type_suffix_is_balanced(name, index) {
        Some(
          String::unsafe_substring(name, start=index + 1, end=name.length() - 1),
        )
      } else {
        None
      }
    None => None
  }
}

///|
fn pkl_constraint_call_inner(text : String, prefix : String) -> String? {
  if text.has_prefix(prefix) &&
    text.has_suffix(")") &&
    text.length() >= prefix.length() + 1 {
    Some(
      String::unsafe_substring(
        text,
        start=prefix.length(),
        end=text.length() - 1,
      ),
    )
  } else {
    None
  }
}

///|
fn pkl_is_between_inner(text : String) -> String? {
  match pkl_constraint_call_inner(text, "isBetween(") {
    Some(inner) => Some(inner)
    None => pkl_constraint_call_inner(text, "this.isBetween(")
  }
}

///|
fn pkl_is_between_range(text : String) -> ConstraintIntRange? {
  match pkl_is_between_inner(text) {
    Some(inner) => {
      let parts = pkl_split_constraint_arguments(inner)
      if parts.length() != 2 {
        return None
      }
      match
        (
          pkl_parse_constraint_int_text(parts[0]),
          pkl_parse_constraint_int_text(parts[1]),
        ) {
        (Some(lower), Some(upper)) => Some({ lower, upper })
        _ => None
      }
    }
    None => None
  }
}

///|
fn pkl_constrained_int_range(type_name : String) -> ConstraintIntRange? {
  match pkl_constrained_type_base_name(type_name) {
    Some("Int") =>
      match pkl_constrained_type_constraint_text(type_name) {
        Some(text) => pkl_is_between_range(text)
        None => None
      }
    _ => None
  }
}

///|
fn pkl_constrained_int_rejection_message(
  type_name : String?,
  value : Int,
) -> String? {
  match type_name {
    Some(name) =>
      match pkl_constrained_int_range(name) {
        Some(range) =>
          if value < range.lower || value > range.upper {
            Some(
              "type annotation \{name} constraint isBetween rejects \{value}",
            )
          } else {
            None
          }
        None => None
      }
    None => None
  }
}

///|
fn pkl_int_literal_value(expr : Expr) -> Int? {
  match expr {
    IntLiteral(value) => Some(value)
    UnaryExpr(Negate, IntLiteral(value)) => Some(0 - value)
    _ => None
  }
}

///|
fn pkl_push_constrained_type_annotation_expr_diagnostic(
  type_name : String?,
  expr : Expr,
  diagnostics : Array[Diagnostic],
) -> Unit {
  match pkl_int_literal_value(expr) {
    Some(value) =>
      match pkl_constrained_int_rejection_message(type_name, value) {
        Some(message) => diagnostics.push(Diagnostic::{ message, })
        None => ()
      }
    None => ()
  }
}

///|
fn pkl_value_int(value : Value) -> Int? {
  match value {
    IntValue(inner) => Some(inner)
    _ => None
  }
}

///|
fn pkl_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match pkl_value_int(value) {
    Some(inner) =>
      match pkl_constrained_int_rejection_message(type_name, inner) {
        Some(message) => {
          diagnostics.push(Diagnostic::{ message, })
          false
        }
        None => true
      }
    None => true
  }
}
