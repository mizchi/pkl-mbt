///|
priv struct ConstraintIntRange {
  lower : Double
  upper : Double
}

///|
priv struct ConstraintIntCall {
  name : String
  argument : Double
}

///|
// PKL-112: threshold encoding lifted from Int to Double so that
// `Float(isBetween(0.5, 1.5))` parses and runs without losing precision.
// Int-side comparisons widen the value to Double before applying the
// operator (see pkl_constraint_predicate_accepts), so existing Int-only
// constraint annotations keep working unchanged.
priv enum ConstraintIntPredicate {
  IsBetween(Double, Double)
  IsPositive
  IsGreaterThan(Double)
  IsLessThan(Double)
  NotIsBetween(Double, Double)
  NotIsPositive
  NotIsGreaterThan(Double)
  NotIsLessThan(Double)
  CustomGreaterThan(String, Double)
  CustomLessThan(String, Double)
  CustomGreaterOrEqual(String, Double)
  CustomLessOrEqual(String, Double)
  NotCustomGreaterThan(String, Double)
  NotCustomLessThan(String, Double)
  NotCustomGreaterOrEqual(String, Double)
  NotCustomLessOrEqual(String, Double)
  // PKL-148b: `Int(this > 0)` / `Int(0 < this)`-style bare comparison
  // constraints. The constraint name renders as the literal source
  // ("this > 0") to match Apple Pkl's diagnostic wording, and the
  // accepts side runs the comparison with the candidate substituted
  // for `this`.
  ThisCompare(ConstraintCompareOp, Double, Bool)
  NotThisCompare(ConstraintCompareOp, Double, Bool)
}

///|
priv enum ConstraintCompareOp {
  CmpGreaterThan
  CmpGreaterOrEqual
  CmpLessThan
  CmpLessOrEqual
  CmpEqual
  CmpNotEqual
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
// PKL-112: parser for Int or Float threshold literals appearing inside
// constraint predicates (`isBetween(0.5, 1.5)`, `isGreaterThan(-3)`).
// Accepts an optional leading `-`, a digit-run integer part, and an
// optional `.<digits>` fractional part. Exponents are not handled — the
// parser surface (PKL-128) covers `1e10` separately and constraint text
// never contains scientific literals today.
fn pkl_parse_constraint_double_text(text : String) -> Double? {
  let trimmed = pkl_constraint_trim(text)
  if trimmed.length() == 0 {
    return None
  }
  let mut index = 0
  let mut sign = 1.0
  if trimmed[0].to_int().unsafe_to_char() == '-' {
    sign = -1.0
    index = 1
  }
  if index == trimmed.length() {
    return None
  }
  let mut int_part = 0.0
  let mut saw_digit = false
  while index < trimmed.length() {
    let char = trimmed[index].to_int().unsafe_to_char()
    if char >= '0' && char <= '9' {
      int_part = int_part * 10.0 + (char.to_int() - '0'.to_int()).to_double()
      saw_digit = true
      index += 1
    } else {
      break
    }
  }
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  let mut saw_dot = false
  if index < trimmed.length() && trimmed[index].to_int().unsafe_to_char() == '.' {
    saw_dot = true
    index += 1
    while index < trimmed.length() {
      let char = trimmed[index].to_int().unsafe_to_char()
      if char >= '0' && char <= '9' {
        frac_scale = frac_scale * 10.0
        frac_part = frac_part +
          (char.to_int() - '0'.to_int()).to_double() / frac_scale
        saw_digit = true
        index += 1
      } else {
        break
      }
    }
  }
  if index != trimmed.length() || !saw_digit {
    return None
  }
  let _ = saw_dot
  Some(sign * (int_part + frac_part))
}

///|
fn pkl_split_constraint_arguments(text : String) -> Array[String] {
  // Split a comma-separated constraint argument list at the top
  // level (parens / brackets / angles balanced). Each segment is
  // trimmed so the predicate dispatcher doesn't have to defend
  // against leading / trailing whitespace introduced by the
  // operator spacing in `Int(isPositive, isLessThan(10))`.
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut parens = 0
  let mut brackets = 0
  let mut angles = 0
  for char in text {
    if char == ',' && parens == 0 && brackets == 0 && angles == 0 {
      parts.push(trim_spaces(buf.to_string()))
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
  let last = trim_spaces(buf.to_string())
  if last != "" || parts.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn trim_spaces(text : String) -> String {
  let mut start = 0
  while start < text.length() {
    let c = text[start].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      start = start + 1
    } else {
      break
    }
  }
  let mut end = text.length()
  while end > start {
    let c = text[end - 1].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      end = end - 1
    } else {
      break
    }
  }
  String::unsafe_substring(text, start~, end~)
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
          pkl_parse_constraint_double_text(parts[0]),
          pkl_parse_constraint_double_text(parts[1]),
        ) {
        (Some(lower), Some(upper)) => Some({ lower, upper })
        _ => None
      }
    }
    None => None
  }
}

///|
fn pkl_constraint_property_matches(text : String, name : String) -> Bool {
  text == name || text == "this." + name
}

///|
fn pkl_single_int_constraint_argument(text : String, name : String) -> Double? {
  match pkl_constraint_call_inner(text, name + "(") {
    Some(inner) => pkl_parse_constraint_double_text(inner)
    None =>
      match pkl_constraint_call_inner(text, "this." + name + "(") {
        Some(inner) => pkl_parse_constraint_double_text(inner)
        None => None
      }
  }
}

///|
fn pkl_single_int_constraint_call(text : String) -> ConstraintIntCall? {
  let call_text = if text.has_prefix("this.") && text.length() > 5 {
    String::unsafe_substring(text, start=5, end=text.length())
  } else {
    text
  }
  match call_text.find("(") {
    Some(index) =>
      if index == 0 || !call_text.has_suffix(")") {
        None
      } else {
        let name = String::unsafe_substring(call_text, start=0, end=index)
        let inner = String::unsafe_substring(
          call_text,
          start=index + 1,
          end=call_text.length() - 1,
        )
        match pkl_parse_constraint_double_text(inner) {
          Some(argument) => Some({ name, argument })
          None => None
        }
      }
    None => None
  }
}

///|
fn pkl_int_constraint_predicate(text : String) -> ConstraintIntPredicate? {
  if text.has_prefix("!") && text.length() > 1 {
    let inner = String::unsafe_substring(text, start=1, end=text.length())
    match pkl_int_constraint_predicate(inner) {
      Some(IsBetween(lower, upper)) => return Some(NotIsBetween(lower, upper))
      Some(IsPositive) => return Some(NotIsPositive)
      Some(IsGreaterThan(threshold)) => return Some(NotIsGreaterThan(threshold))
      Some(IsLessThan(threshold)) => return Some(NotIsLessThan(threshold))
      Some(ThisCompare(op, t, leftish)) =>
        return Some(NotThisCompare(op, t, leftish))
      _ => return None
    }
  }
  match pkl_is_between_range(text) {
    Some(range) => return Some(IsBetween(range.lower, range.upper))
    None => ()
  }
  if pkl_constraint_property_matches(text, "isPositive") {
    return Some(IsPositive)
  }
  match pkl_single_int_constraint_argument(text, "isGreaterThan") {
    Some(threshold) => return Some(IsGreaterThan(threshold))
    None => ()
  }
  match pkl_single_int_constraint_argument(text, "isLessThan") {
    Some(threshold) => return Some(IsLessThan(threshold))
    None => ()
  }
  // PKL-148b: `this <op> N` bare comparison falls through last so it
  // doesn't shadow the named-predicate forms above.
  match pkl_parse_this_comparison(text) {
    Some(predicate) => return Some(predicate)
    None => ()
  }
  None
}

///|
fn pkl_user_defined_int_constraint_from_order(
  function_name : String,
  threshold : Double,
  value_on_left : Bool,
  op : BinaryOp,
) -> ConstraintIntPredicate? {
  match op {
    GreaterThan =>
      if value_on_left {
        Some(CustomGreaterThan(function_name, threshold))
      } else {
        Some(CustomLessThan(function_name, threshold))
      }
    LessThan =>
      if value_on_left {
        Some(CustomLessThan(function_name, threshold))
      } else {
        Some(CustomGreaterThan(function_name, threshold))
      }
    GreaterOrEqual =>
      if value_on_left {
        Some(CustomGreaterOrEqual(function_name, threshold))
      } else {
        Some(CustomLessOrEqual(function_name, threshold))
      }
    LessOrEqual =>
      if value_on_left {
        Some(CustomLessOrEqual(function_name, threshold))
      } else {
        Some(CustomGreaterOrEqual(function_name, threshold))
      }
    _ => None
  }
}

///|
fn pkl_user_defined_int_constraint_from_comparison(
  function_name : String,
  factory_parameter : String,
  threshold : Double,
  lambda_parameter : String,
  op : BinaryOp,
  left : Expr,
  right : Expr,
) -> ConstraintIntPredicate? {
  match (left, right) {
    (Identifier(left_name), Identifier(right_name)) =>
      if left_name == lambda_parameter && right_name == factory_parameter {
        pkl_user_defined_int_constraint_from_order(
          function_name, threshold, true, op,
        )
      } else if left_name == factory_parameter && right_name == lambda_parameter {
        pkl_user_defined_int_constraint_from_order(
          function_name, threshold, false, op,
        )
      } else {
        None
      }
    _ => None
  }
}

///|
fn pkl_user_defined_int_constraint_from_function_decl(
  function_decl : FunctionDecl,
  threshold : Double,
) -> ConstraintIntPredicate? {
  if function_decl.parameters.length() != 1 {
    return None
  }
  let factory_parameter = function_decl.parameters[0].name
  match function_decl.body {
    Some(LambdaExpr(lambda_parameters, BinaryExpr(op, left, right), _)) =>
      if lambda_parameters.length() == 1 {
        pkl_user_defined_int_constraint_from_comparison(
          function_decl.name,
          factory_parameter,
          threshold,
          lambda_parameters[0].name,
          op,
          left,
          right,
        )
      } else {
        None
      }
    _ => None
  }
}

///|
fn pkl_negate_user_defined_int_constraint(
  predicate : ConstraintIntPredicate,
) -> ConstraintIntPredicate? {
  match predicate {
    CustomGreaterThan(name, threshold) =>
      Some(NotCustomGreaterThan(name, threshold))
    CustomLessThan(name, threshold) => Some(NotCustomLessThan(name, threshold))
    CustomGreaterOrEqual(name, threshold) =>
      Some(NotCustomGreaterOrEqual(name, threshold))
    CustomLessOrEqual(name, threshold) =>
      Some(NotCustomLessOrEqual(name, threshold))
    _ => None
  }
}

///|
fn pkl_user_defined_int_constraint_predicate(
  text : String,
  declarations : Array[Declaration],
) -> ConstraintIntPredicate? {
  if text.has_prefix("!") && text.length() > 1 {
    let inner = String::unsafe_substring(text, start=1, end=text.length())
    match pkl_user_defined_int_constraint_predicate(inner, declarations) {
      Some(predicate) =>
        return pkl_negate_user_defined_int_constraint(predicate)
      None => return None
    }
  }
  match pkl_single_int_constraint_call(text) {
    Some(call) => {
      for declaration in declarations {
        match declaration {
          FunctionDeclaration(function_decl) =>
            if function_decl.name == call.name {
              return pkl_user_defined_int_constraint_from_function_decl(
                function_decl,
                call.argument,
              )
            }
          ClassDeclaration(_) | TypeAliasDeclaration(_) => ()
        }
      }
      None
    }
    None => None
  }
}

///|
fn pkl_constrained_int_predicates(
  type_name : String,
) -> Array[ConstraintIntPredicate] {
  let predicates : Array[ConstraintIntPredicate] = []
  // PKL-092: accept `Int(...)`, `Float(...)`, and `Number(...)` as the
  // numeric constraint host. The predicate-side encoding (Int thresholds)
  // is kept — Float values are widened from those thresholds when the
  // accepts-float helper runs the comparison.
  match pkl_constrained_type_base_name(type_name) {
    Some("Int") | Some("Float") | Some("Number") =>
      match pkl_constrained_type_constraint_text(type_name) {
        Some(text) => {
          let parts = pkl_split_constraint_arguments(text)
          for part in parts {
            match pkl_int_constraint_predicate(part) {
              Some(predicate) => predicates.push(predicate)
              None => ()
            }
          }
        }
        None => ()
      }
    _ => ()
  }
  predicates
}

///|
fn pkl_user_defined_constrained_int_predicates(
  type_name : String,
  declarations : Array[Declaration],
) -> Array[ConstraintIntPredicate] {
  let predicates : Array[ConstraintIntPredicate] = []
  match pkl_constrained_type_base_name(type_name) {
    Some("Int") =>
      match pkl_constrained_type_constraint_text(type_name) {
        Some(text) => {
          let parts = pkl_split_constraint_arguments(text)
          for part in parts {
            match
              pkl_user_defined_int_constraint_predicate(part, declarations) {
              Some(predicate) => predicates.push(predicate)
              None => ()
            }
          }
        }
        None => ()
      }
    _ => ()
  }
  predicates
}

///|
fn pkl_lookup_type_alias_target(
  declarations : Array[Declaration],
  name : String,
) -> String? {
  let mut found : String? = None
  for declaration in declarations {
    match declaration {
      TypeAliasDeclaration(type_alias) =>
        if type_alias.name == name {
          found = Some(type_alias.target)
        }
      ClassDeclaration(_) | FunctionDeclaration(_) => ()
    }
  }
  found
}

///|
fn pkl_user_defined_constrained_type_source_name_with_depth(
  name : String,
  declarations : Array[Declaration],
  depth : Int,
) -> String? {
  if depth > 8 {
    return None
  }
  if pkl_user_defined_constrained_int_predicates(name, declarations).length() >
    0 {
    return Some(name)
  }
  match pkl_lookup_type_alias_target(declarations, name) {
    Some(target) =>
      pkl_user_defined_constrained_type_source_name_with_depth(
        target,
        declarations,
        depth + 1,
      )
    None => None
  }
}

///|
fn pkl_user_defined_constrained_type_source_name(
  name : String,
  declarations : Array[Declaration],
) -> String? {
  pkl_user_defined_constrained_type_source_name_with_depth(
    name, declarations, 0,
  )
}

///|
fn pkl_constrained_type_annotation_has_supported_constraint(
  type_name : String,
) -> Bool {
  pkl_constrained_type_annotation_has_supported_constraint_with_depth(
    type_name, 0,
  )
}

///|
/// Recurse into collection wrappers so `Listing<Int(isPositive)>` and
/// `Mapping<String(length > 0), Int>` register as supported. Depth is
/// capped to keep mutually-recursive aliases from looping the cascade.
fn pkl_constrained_type_annotation_has_supported_constraint_with_depth(
  type_name : String,
  depth : Int,
) -> Bool {
  if depth > 8 {
    return false
  }
  if pkl_constrained_int_predicates(type_name).length() > 0 ||
    pkl_constrained_string_predicates(type_name).length() > 0 {
    return true
  }
  match generic_argument_text(type_name, "Listing") {
    Some(inner_text) =>
      return pkl_constrained_type_annotation_has_supported_constraint_with_depth(
        inner_text,
        depth + 1,
      )
    None => ()
  }
  match generic_argument_text(type_name, "Mapping") {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() == 2 {
        if pkl_constrained_type_annotation_has_supported_constraint_with_depth(
            parts[0],
            depth + 1,
          ) ||
          pkl_constrained_type_annotation_has_supported_constraint_with_depth(
            parts[1],
            depth + 1,
          ) {
          return true
        }
      }
      return false
    }
    None => ()
  }
  false
}

///|
fn pkl_constraint_name(predicate : ConstraintIntPredicate) -> String {
  // PKL-148: include the argument list verbatim so the diagnostic
  // wording matches Apple Pkl's exact format (e.g. `isBetween(10, 20)`
  // rather than the bare `isBetween`). The threshold values are
  // formatted through `format_constraint_arg` so Int-magnitude
  // doubles render without a trailing `.0`.
  match predicate {
    IsBetween(lo, hi) =>
      "isBetween(\{format_constraint_arg(lo)}, \{format_constraint_arg(hi)})"
    IsPositive => "isPositive"
    IsGreaterThan(t) => "isGreaterThan(\{format_constraint_arg(t)})"
    IsLessThan(t) => "isLessThan(\{format_constraint_arg(t)})"
    NotIsBetween(lo, hi) =>
      "!isBetween(\{format_constraint_arg(lo)}, \{format_constraint_arg(hi)})"
    NotIsPositive => "!isPositive"
    NotIsGreaterThan(t) => "!isGreaterThan(\{format_constraint_arg(t)})"
    NotIsLessThan(t) => "!isLessThan(\{format_constraint_arg(t)})"
    CustomGreaterThan(name, t) => "\{name}(\{format_constraint_arg(t)})"
    CustomLessThan(name, t) => "\{name}(\{format_constraint_arg(t)})"
    CustomGreaterOrEqual(name, t) => "\{name}(\{format_constraint_arg(t)})"
    CustomLessOrEqual(name, t) => "\{name}(\{format_constraint_arg(t)})"
    NotCustomGreaterThan(name, t) =>
      "!" + name + "(\{format_constraint_arg(t)})"
    NotCustomLessThan(name, t) => "!" + name + "(\{format_constraint_arg(t)})"
    NotCustomGreaterOrEqual(name, t) =>
      "!" + name + "(\{format_constraint_arg(t)})"
    NotCustomLessOrEqual(name, t) =>
      "!" + name + "(\{format_constraint_arg(t)})"
    ThisCompare(op, t, this_on_left) =>
      if this_on_left {
        "this \{constraint_compare_op_text(op)} \{format_constraint_arg(t)}"
      } else {
        "\{format_constraint_arg(t)} \{constraint_compare_op_text(op)} this"
      }
    NotThisCompare(op, t, this_on_left) =>
      if this_on_left {
        "!(this \{constraint_compare_op_text(op)} \{format_constraint_arg(t)})"
      } else {
        "!(\{format_constraint_arg(t)} \{constraint_compare_op_text(op)} this)"
      }
  }
}

///|
fn constraint_compare_op_text(op : ConstraintCompareOp) -> String {
  match op {
    CmpGreaterThan => ">"
    CmpGreaterOrEqual => ">="
    CmpLessThan => "<"
    CmpLessOrEqual => "<="
    CmpEqual => "=="
    CmpNotEqual => "!="
  }
}

///|
fn _pkl_binary_op_to_compare(op : BinaryOp) -> ConstraintCompareOp? {
  match op {
    GreaterThan => Some(CmpGreaterThan)
    GreaterOrEqual => Some(CmpGreaterOrEqual)
    LessThan => Some(CmpLessThan)
    LessOrEqual => Some(CmpLessOrEqual)
    Equal => Some(CmpEqual)
    NotEqual => Some(CmpNotEqual)
    _ => None
  }
}

///|
/// PKL-148b: parse a `this <op> N` or `N <op> this` bare comparison
/// from the constraint text into a `ThisCompare` predicate. Whitespace
/// is normalised; the supported ops are >, >=, <, <=, ==, !=.
fn pkl_parse_this_comparison(text : String) -> ConstraintIntPredicate? {
  let trimmed = pkl_constraint_trim(text)
  let ops : Array[(String, ConstraintCompareOp)] = [
    (">=", CmpGreaterOrEqual),
    ("<=", CmpLessOrEqual),
    ("==", CmpEqual),
    ("!=", CmpNotEqual),
    (">", CmpGreaterThan),
    ("<", CmpLessThan),
  ]
  for op_pair in ops {
    let op_text = op_pair.0
    let op = op_pair.1
    match pkl_split_on_op(trimmed, op_text) {
      Some((left, right)) => {
        let left_trim = pkl_constraint_trim(left)
        let right_trim = pkl_constraint_trim(right)
        if left_trim == "this" {
          match pkl_parse_constraint_double_text(right_trim) {
            Some(n) => return Some(ThisCompare(op, n, true))
            None => ()
          }
        } else if right_trim == "this" {
          match pkl_parse_constraint_double_text(left_trim) {
            Some(n) => return Some(ThisCompare(op, n, false))
            None => ()
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
fn pkl_split_on_op(text : String, op : String) -> (String, String)? {
  let n = text.length()
  let m = op.length()
  let mut i = 0
  while i + m <= n {
    let mut equal = true
    for j = 0; j < m; j = j + 1 {
      if text[i + j] != op[j] {
        equal = false
        break
      }
    }
    if equal {
      // Reject if the op text appears inside a longer operator (e.g.
      // matching `>` inside `>=`).
      let prev = if i > 0 {
        Some(text[i - 1].to_int().unsafe_to_char())
      } else {
        None
      }
      let next = if i + m < n {
        Some(text[i + m].to_int().unsafe_to_char())
      } else {
        None
      }
      let ambiguous = match (op, prev, next) {
        (">", _, Some('=')) | ("<", _, Some('=')) => true
        ("=", Some('='), _)
        | ("=", Some('!'), _)
        | ("=", Some('<'), _)
        | ("=", Some('>'), _) => true
        _ => false
      }
      if !ambiguous {
        return Some(
          (
            String::unsafe_substring(text, start=0, end=i),
            String::unsafe_substring(text, start=i + m, end=n),
          ),
        )
      }
    }
    i = i + 1
  }
  None
}

///|
/// PKL-148: format a constraint threshold for the diagnostic. Int-like
/// magnitudes (e.g. `10.0`) drop their trailing `.0` so the message
/// reads `isBetween(10, 20)` rather than `isBetween(10.0, 20.0)`.
fn format_constraint_arg(value : Double) -> String {
  if value.is_nan() || value.is_inf() {
    "\{value}"
  } else if value == value.floor() && value.abs() < 9.0e15 {
    "\{value.to_int()}"
  } else {
    "\{value}"
  }
}

///|
fn pkl_constraint_predicate_accepts(
  predicate : ConstraintIntPredicate,
  value : Int,
) -> Bool {
  // PKL-112: thresholds are stored as Double. Widen the Int side to
  // Double for the comparison so Int(isBetween(0, 10)) keeps working
  // alongside Float(isBetween(0.5, 1.5)).
  pkl_constraint_predicate_accepts_float(predicate, value.to_double())
}

///|
fn pkl_constrained_int_rejection_message_from_source(
  _display_name : String,
  source_name : String,
  value : Int,
) -> String? {
  for predicate in pkl_constrained_int_predicates(source_name) {
    if !pkl_constraint_predicate_accepts(predicate, value) {
      return Some(
        // PKL-148: align with Apple Pkl's exact diagnostic wording so
        // snippetTest fixtures that capture this string via
        // `test.catch(...)` match byte-for-byte.
        "Type constraint `\{pkl_constraint_name(predicate)}` violated. Value: \{value}",
      )
    }
  }
  None
}

///|
fn pkl_user_defined_constrained_int_rejection_message_from_source(
  _display_name : String,
  source_name : String,
  value : Int,
  declarations : Array[Declaration],
) -> String? {
  for
    predicate in pkl_user_defined_constrained_int_predicates(
      source_name, declarations,
    ) {
    if !pkl_constraint_predicate_accepts(predicate, value) {
      return Some(
        // PKL-148: align with Apple Pkl's exact diagnostic wording so
        // snippetTest fixtures that capture this string via
        // `test.catch(...)` match byte-for-byte.
        "Type constraint `\{pkl_constraint_name(predicate)}` violated. Value: \{value}",
      )
    }
  }
  None
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
fn pkl_constrained_type_annotation_expr_rejection_message_from_source(
  display_name : String,
  source_name : String,
  expr : Expr,
) -> String? {
  match pkl_int_literal_value(expr) {
    Some(value) =>
      return pkl_constrained_int_rejection_message_from_source(
        display_name, source_name, value,
      )
    None => ()
  }
  match pkl_string_literal_value(expr) {
    Some(value) =>
      pkl_constrained_string_rejection_message_from_source(
        display_name, source_name, value,
      )
    None => None
  }
}

///|
fn pkl_string_literal_value(expr : Expr) -> String? {
  match expr {
    StringLiteral(value) => Some(value)
    _ => None
  }
}

///|
fn pkl_user_defined_constrained_type_annotation_expr_rejection_message(
  type_name : String?,
  expr : Expr,
  declarations : Array[Declaration],
) -> String? {
  match type_name {
    Some(display_name) =>
      match
        pkl_user_defined_constrained_type_source_name(
          display_name, declarations,
        ) {
        Some(source_name) =>
          match pkl_int_literal_value(expr) {
            Some(value) =>
              pkl_user_defined_constrained_int_rejection_message_from_source(
                display_name, source_name, value, declarations,
              )
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn pkl_user_defined_constrained_type_annotation_expr_rejection_message_from_source(
  display_name : String,
  source_name : String,
  expr : Expr,
  declarations : Array[Declaration],
) -> String? {
  match
    pkl_user_defined_constrained_type_source_name(source_name, declarations) {
    Some(resolved_source_name) =>
      match pkl_int_literal_value(expr) {
        Some(value) =>
          pkl_user_defined_constrained_int_rejection_message_from_source(
            display_name, resolved_source_name, value, declarations,
          )
        None => None
      }
    None => None
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
fn pkl_constraint_predicate_accepts_float(
  predicate : ConstraintIntPredicate,
  value : Double,
) -> Bool {
  // PKL-112: thresholds are encoded as Double, so Float / Int values
  // can compare against them uniformly without precision loss.
  match predicate {
    IsBetween(lower, upper) => value >= lower && value <= upper
    IsPositive => value > 0.0
    IsGreaterThan(threshold) => value > threshold
    IsLessThan(threshold) => value < threshold
    NotIsBetween(lower, upper) => !(value >= lower && value <= upper)
    NotIsPositive => !(value > 0.0)
    NotIsGreaterThan(threshold) => !(value > threshold)
    NotIsLessThan(threshold) => !(value < threshold)
    CustomGreaterThan(_, threshold) => value > threshold
    CustomLessThan(_, threshold) => value < threshold
    CustomGreaterOrEqual(_, threshold) => value >= threshold
    CustomLessOrEqual(_, threshold) => value <= threshold
    NotCustomGreaterThan(_, threshold) => !(value > threshold)
    NotCustomLessThan(_, threshold) => !(value < threshold)
    NotCustomGreaterOrEqual(_, threshold) => !(value >= threshold)
    NotCustomLessOrEqual(_, threshold) => !(value <= threshold)
    ThisCompare(op, threshold, this_on_left) =>
      pkl_constraint_compare_eval(value, op, threshold, this_on_left)
    NotThisCompare(op, threshold, this_on_left) =>
      !pkl_constraint_compare_eval(value, op, threshold, this_on_left)
  }
}

///|
/// PKL-148b: run a `this <op> N` (or `N <op> this`) bare comparison
/// against a candidate value. Used by ThisCompare / NotThisCompare;
/// kept separate so the predicate evaluator stays branch-flat.
fn pkl_constraint_compare_eval(
  value : Double,
  op : ConstraintCompareOp,
  threshold : Double,
  this_on_left : Bool,
) -> Bool {
  let (left, right) = if this_on_left {
    (value, threshold)
  } else {
    (threshold, value)
  }
  match op {
    CmpGreaterThan => left > right
    CmpGreaterOrEqual => left >= right
    CmpLessThan => left < right
    CmpLessOrEqual => left <= right
    CmpEqual => left == right
    CmpNotEqual => left != right
  }
}

///|
fn pkl_constrained_float_rejection_message_from_source(
  _display_name : String,
  source_name : String,
  value : Double,
) -> String? {
  for predicate in pkl_constrained_int_predicates(source_name) {
    if !pkl_constraint_predicate_accepts_float(predicate, value) {
      return Some(
        // PKL-148: align with Apple Pkl's exact diagnostic wording so
        // snippetTest fixtures that capture this string via
        // `test.catch(...)` match byte-for-byte.
        "Type constraint `\{pkl_constraint_name(predicate)}` violated. Value: \{value}",
      )
    }
  }
  None
}

///|
fn pkl_user_defined_constrained_type_annotation_value_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match
    pkl_user_defined_constrained_type_source_name(source_name, declarations) {
    Some(resolved_source_name) =>
      match pkl_value_int(value) {
        Some(inner) =>
          pkl_user_defined_constrained_int_rejection_message_from_source(
            display_name, resolved_source_name, inner, declarations,
          )
        None => None
      }
    None => None
  }
}

///|
fn pkl_user_defined_constrained_type_annotation_value_rejection_message(
  type_name : String?,
  value : Value,
  declarations : Array[Declaration],
) -> String? {
  match type_name {
    Some(display_name) =>
      match
        pkl_user_defined_constrained_type_source_name(
          display_name, declarations,
        ) {
        Some(source_name) =>
          match pkl_value_int(value) {
            Some(inner) =>
              pkl_user_defined_constrained_int_rejection_message_from_source(
                display_name, source_name, inner, declarations,
              )
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn pkl_constrained_type_annotation_value_is_valid(
  type_name : String?,
  value : Value,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match
    pkl_constrained_type_annotation_value_rejection_message(type_name, value) {
    Some(message) => {
      diagnostics.push(diag(message))
      false
    }
    None => true
  }
}

///|
fn pkl_constrained_type_annotation_value_rejection_message(
  type_name : String?,
  value : Value,
) -> String? {
  match type_name {
    Some(name) =>
      pkl_constrained_type_annotation_value_rejection_message_from_source(
        name, name, value,
      )
    None => None
  }
}

///|
fn pkl_constrained_type_annotation_value_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : Value,
) -> String? {
  // PKL-148ae: `String(!isEmpty)?` / `Int(isPositive)?` etc. are
  // nullable-wrapped constrained types. NullValue trivially satisfies
  // the `?`; for non-null values, strip the trailing `?` and recurse
  // through the same cascade so the inner constraint cascade actually
  // runs. Without the unwrap, `pkl_constrained_type_base_name` returns
  // None (because the trailing `?` breaks the `has_suffix(")")` check
  // it needs) and the predicate dispatch silently returns None.
  if source_name.has_suffix("?") {
    match value {
      NullValue => return None
      _ => {
        let inner = String::unsafe_substring(
          source_name,
          start=0,
          end=source_name.length() - 1,
        )
        let inner_display = if display_name.has_suffix("?") {
          String::unsafe_substring(
            display_name,
            start=0,
            end=display_name.length() - 1,
          )
        } else {
          display_name
        }
        return pkl_constrained_type_annotation_value_rejection_message_from_source(
          inner_display, inner, value,
        )
      }
    }
  }
  match pkl_value_int(value) {
    Some(inner) =>
      return pkl_constrained_int_rejection_message_from_source(
        display_name, source_name, inner,
      )
    None => ()
  }
  // PKL-092: Float values dispatch through the same predicate set as
  // Int. The Float branch comes after the Int branch so an `IntValue`
  // stays in the Int-error format; only true `FloatValue`s reach here.
  match value {
    FloatValue(inner) =>
      return pkl_constrained_float_rejection_message_from_source(
        display_name, source_name, inner,
      )
    _ => ()
  }
  match pkl_value_string(value) {
    Some(inner) =>
      return pkl_constrained_string_rejection_message_from_source(
        display_name, source_name, inner,
      )
    None => ()
  }
  // PKL-148b: `Listing<T>(...)` host constraints fire against the
  // whole Listing (e.g. `Listing<String>(!isEmpty)`) before delegating
  // element-side cascade to the existing collection walker.
  match value {
    ListingValue(elements) | ListValue(elements) =>
      match
        pkl_constrained_listing_rejection_message_from_source(
          source_name, elements,
        ) {
        Some(message) => return Some(message)
        None => ()
      }
    _ => ()
  }
  pkl_collection_element_rejection_message_from_source(
    display_name, source_name, value,
  )
}

///|
/// PKL-148b: evaluate the `Listing<T>(<predicate>)` host constraint
/// against the actual Listing value. Today the supported predicates are
/// the bare `isEmpty` / `!isEmpty` zero-arg form; richer ones land as
/// follow-up.
fn pkl_constrained_listing_rejection_message_from_source(
  source_name : String,
  elements : Array[Value],
) -> String? {
  // Only fire when the host name is `Listing(<...>)` — the inner element
  // type doesn't affect the host predicate.
  match pkl_constrained_type_base_name(source_name) {
    Some(base) =>
      if !(base == "Listing" || base.has_prefix("Listing<")) {
        return None
      }
    None => return None
  }
  let text = match pkl_constrained_type_constraint_text(source_name) {
    Some(t) => pkl_constraint_trim(t)
    None => return None
  }
  let parts = pkl_split_constraint_arguments(text)
  for part in parts {
    let trimmed = pkl_constraint_trim(part)
    let negated = trimmed.has_prefix("!")
    let bare = if negated {
      pkl_constraint_trim(
        String::unsafe_substring(trimmed, start=1, end=trimmed.length()),
      )
    } else {
      trimmed
    }
    if bare == "isEmpty" {
      let is_empty = elements.length() == 0
      let violated = if negated { is_empty } else { !is_empty }
      if violated {
        // Render the rejected Listing using PCF inline form so the
        // user sees what was rejected.
        let buf = StringBuilder::new()
        render_listing_for_diag(elements, buf)
        return Some(
          "Type constraint `\{trimmed}` violated. Value: \{buf.to_string()}",
        )
      }
    }
  }
  None
}

///|
fn render_listing_for_diag(
  elements : Array[Value],
  buf : StringBuilder,
) -> Unit {
  if elements.length() == 0 {
    buf.write_string("new Listing {}")
  } else {
    buf.write_string("new Listing { ... }")
  }
}

///|
/// If `source_name` looks like `Listing<T>` / `Mapping<K, V>`, walk the
/// matching value variant and apply the same constrained-type cascade
/// to each element. Non-collection sources fall through to `None`,
/// preserving the existing dispatch behaviour for scalars.
fn pkl_collection_element_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : Value,
) -> String? {
  // PKL-148ae: strip the outer `(<constraint>)` from the source name
  // before extracting the generic argument. `List<String(!isEmpty)>(!isEmpty)`
  // has a top-level constraint that hides the `<...>` from `generic_argument_text`'s
  // `has_suffix(">")` check — `pkl_constrained_type_base_name` returns
  // `List<String(!isEmpty)>` which is then directly walkable.
  let base_source = match pkl_constrained_type_base_name(source_name) {
    Some(b) => b
    None => source_name
  }
  // PKL-148ae: `List<T>` joins `Listing<T>` for element-side cascade,
  // matching Apple Pkl's symmetric treatment — `(List<String(!isEmpty)>)`
  // arg / return constraints walk each element through the same
  // predicate set.
  let listing_or_list = match generic_argument_text(base_source, "Listing") {
    Some(t) => Some(t)
    None => generic_argument_text(base_source, "List")
  }
  match listing_or_list {
    Some(element_type) =>
      match value {
        ListingValue(elements) | ListValue(elements) | SetValue(elements) =>
          for element in elements {
            match
              pkl_constrained_type_annotation_value_rejection_message_from_source(
                element_type, element_type, element,
              ) {
              Some(message) => return Some(message)
              None => ()
            }
          } nobreak {
            return None
          }
        _ => return None
      }
    None => ()
  }
  // PKL-148ae: `Map<K, V>` joins `Mapping<K, V>` for entry-side cascade.
  let mapping_or_map = match generic_argument_text(base_source, "Mapping") {
    Some(t) => Some(t)
    None => generic_argument_text(base_source, "Map")
  }
  match mapping_or_map {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() != 2 {
        return None
      }
      let key_type = parts[0]
      let value_type = parts[1]
      let walk_entries = fn(entries : Array[ValueEntry]) -> String? {
        for entry in entries {
          match
            pkl_constrained_type_annotation_value_rejection_message_from_source(
              key_type,
              key_type,
              entry.key,
            ) {
            Some(message) => return Some(message)
            None => ()
          }
          match
            pkl_constrained_type_annotation_value_rejection_message_from_source(
              value_type,
              value_type,
              entry.value,
            ) {
            Some(message) => return Some(message)
            None => ()
          }
        } nobreak {
          None
        }
      }
      match value {
        MappingValue(entries) | MapValue(entries) =>
          match walk_entries(entries) {
            Some(message) => return Some(message)
            None => return None
          }
        _ => return None
      }
    }
    None => ()
  }
  let _ = display_name
  None
}

///|
priv enum ConstraintStringLengthOp {
  StringLengthGreaterThan
  StringLengthGreaterOrEqual
  StringLengthLessThan
  StringLengthLessOrEqual
  StringLengthEqual
  StringLengthNotEqual
}

///|
priv enum ConstraintStringPredicate {
  StringLengthIsBetween(Int, Int)
  StringLengthIsPositive
  StringLengthIsGreaterThan(Int)
  StringLengthIsLessThan(Int)
  StringLengthCompare(ConstraintStringLengthOp, Int)
  StringMatchesRegex(String)
  StringIsEmpty
  NotStringLengthIsBetween(Int, Int)
  NotStringLengthIsPositive
  NotStringLengthIsGreaterThan(Int)
  NotStringLengthIsLessThan(Int)
  NotStringLengthCompare(ConstraintStringLengthOp, Int)
  NotStringMatchesRegex(String)
  NotStringIsEmpty
}

///|
fn pkl_value_string(value : Value) -> String? {
  match value {
    StringValue(inner) => Some(inner)
    _ => None
  }
}

///|
fn pkl_constraint_trim(text : String) -> String {
  let mut start = 0
  let mut end = text.length()
  while start < end {
    let c = text[start].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      start += 1
    } else {
      break
    }
  }
  while end > start {
    let c = text[end - 1].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      end -= 1
    } else {
      break
    }
  }
  String::unsafe_substring(text, start~, end~)
}

///|
fn pkl_constraint_split_at_operator(
  text : String,
  op : String,
) -> (String, String)? {
  match text.find(op) {
    Some(index) =>
      Some(
        (
          String::unsafe_substring(text, start=0, end=index),
          String::unsafe_substring(
            text,
            start=index + op.length(),
            end=text.length(),
          ),
        ),
      )
    None => None
  }
}

///|
fn pkl_string_length_lhs_matches(text : String) -> Bool {
  let trimmed = pkl_constraint_trim(text)
  trimmed == "length" || trimmed == "this.length"
}

///|
/// Parse a `length OP N` comparison fragment. Operators are tried in
/// length-descending order so `>=` is recognized before `>`.
fn pkl_string_length_comparison_predicate(
  text : String,
) -> ConstraintStringPredicate? {
  let ops : Array[(String, ConstraintStringLengthOp)] = [
    (">=", StringLengthGreaterOrEqual),
    ("<=", StringLengthLessOrEqual),
    ("==", StringLengthEqual),
    ("!=", StringLengthNotEqual),
    (">", StringLengthGreaterThan),
    ("<", StringLengthLessThan),
  ]
  for entry in ops {
    let (op_text, op) = entry
    match pkl_constraint_split_at_operator(text, op_text) {
      Some((lhs, rhs)) =>
        if pkl_string_length_lhs_matches(lhs) {
          match pkl_parse_constraint_int_text(pkl_constraint_trim(rhs)) {
            Some(value) => return Some(StringLengthCompare(op, value))
            None => ()
          }
        }
      None => ()
    }
  }
  None
}

///|
fn pkl_string_length_dot_method_predicate(
  text : String,
) -> ConstraintStringPredicate? {
  let prefix = if text.has_prefix("length.") {
    Some("length.".length())
  } else if text.has_prefix("this.length.") {
    Some("this.length.".length())
  } else {
    None
  }
  match prefix {
    Some(start) => {
      let suffix = String::unsafe_substring(text, start~, end=text.length())
      // Reuse the existing Int predicate parser against the `.length`
      // suffix so length.isBetween / length.isGreaterThan / length.isLessThan
      // share the numeric grammar. PKL-112 lifted the threshold encoding
      // to Double — `length` is always Int so we truncate the threshold
      // back to Int here. Non-integer thresholds against `length` get
      // routed back through this branch only when the upstream parser
      // chose to accept them, which is the same behaviour Apple Pkl
      // exhibits (truncation toward zero).
      match pkl_int_constraint_predicate(suffix) {
        Some(IsBetween(lower, upper)) =>
          Some(StringLengthIsBetween(lower.to_int(), upper.to_int()))
        Some(IsPositive) => Some(StringLengthIsPositive)
        Some(IsGreaterThan(n)) => Some(StringLengthIsGreaterThan(n.to_int()))
        Some(IsLessThan(n)) => Some(StringLengthIsLessThan(n.to_int()))
        Some(NotIsBetween(lower, upper)) =>
          Some(NotStringLengthIsBetween(lower.to_int(), upper.to_int()))
        Some(NotIsPositive) => Some(NotStringLengthIsPositive)
        Some(NotIsGreaterThan(n)) =>
          Some(NotStringLengthIsGreaterThan(n.to_int()))
        Some(NotIsLessThan(n)) => Some(NotStringLengthIsLessThan(n.to_int()))
        _ => None
      }
    }
    None => None
  }
}

///|
fn pkl_string_matches_regex_inner(text : String) -> String? {
  let prefix = "matches(Regex(\""
  let suffix = "\"))"
  if text.has_prefix(prefix) &&
    text.has_suffix(suffix) &&
    text.length() >= prefix.length() + suffix.length() {
    Some(
      String::unsafe_substring(
        text,
        start=prefix.length(),
        end=text.length() - suffix.length(),
      ),
    )
  } else {
    None
  }
}

///|
fn pkl_string_constraint_predicate(text : String) -> ConstraintStringPredicate? {
  let trimmed = pkl_constraint_trim(text)
  if trimmed.has_prefix("!") && trimmed.length() > 1 {
    let inner = String::unsafe_substring(trimmed, start=1, end=trimmed.length())
    match pkl_string_constraint_predicate(inner) {
      Some(StringLengthIsBetween(lower, upper)) =>
        return Some(NotStringLengthIsBetween(lower, upper))
      Some(StringLengthIsPositive) => return Some(NotStringLengthIsPositive)
      Some(StringLengthIsGreaterThan(n)) =>
        return Some(NotStringLengthIsGreaterThan(n))
      Some(StringLengthIsLessThan(n)) =>
        return Some(NotStringLengthIsLessThan(n))
      Some(StringLengthCompare(op, n)) =>
        return Some(NotStringLengthCompare(op, n))
      Some(StringMatchesRegex(pattern)) =>
        return Some(NotStringMatchesRegex(pattern))
      Some(StringIsEmpty) => return Some(NotStringIsEmpty)
      _ => return None
    }
  }
  // PKL-148ae: bare `isEmpty` / `this.isEmpty` on a String constraint
  // (Apple Pkl exposes `String.isEmpty` directly; the predicate form
  // shows up without a `length.` prefix unlike `length.isPositive`).
  if trimmed == "isEmpty" || trimmed == "this.isEmpty" {
    return Some(StringIsEmpty)
  }
  match pkl_string_length_dot_method_predicate(trimmed) {
    Some(predicate) => return Some(predicate)
    None => ()
  }
  match pkl_string_length_comparison_predicate(trimmed) {
    Some(predicate) => return Some(predicate)
    None => ()
  }
  match pkl_string_matches_regex_inner(trimmed) {
    Some(pattern) => return Some(StringMatchesRegex(pattern))
    None => ()
  }
  None
}

///|
fn pkl_constrained_string_predicates(
  type_name : String,
) -> Array[ConstraintStringPredicate] {
  let predicates : Array[ConstraintStringPredicate] = []
  match pkl_constrained_type_base_name(type_name) {
    Some("String") =>
      match pkl_constrained_type_constraint_text(type_name) {
        Some(text) => {
          let parts = pkl_split_constraint_arguments(text)
          for part in parts {
            match pkl_string_constraint_predicate(part) {
              Some(predicate) => predicates.push(predicate)
              None => ()
            }
          }
        }
        None => ()
      }
    _ => ()
  }
  predicates
}

///|
fn pkl_string_length_op_text(op : ConstraintStringLengthOp) -> String {
  match op {
    StringLengthGreaterThan => ">"
    StringLengthGreaterOrEqual => ">="
    StringLengthLessThan => "<"
    StringLengthLessOrEqual => "<="
    StringLengthEqual => "=="
    StringLengthNotEqual => "!="
  }
}

///|
fn pkl_string_constraint_name(predicate : ConstraintStringPredicate) -> String {
  // PKL-148: include the argument list verbatim so the diagnostic
  // wording matches Apple Pkl exactly (e.g. `length.isBetween(10, 20)`
  // rather than the bare `length.isBetween`).
  match predicate {
    StringLengthIsBetween(lo, hi) => "length.isBetween(\{lo}, \{hi})"
    StringLengthIsPositive => "length.isPositive"
    StringLengthIsGreaterThan(t) => "length.isGreaterThan(\{t})"
    StringLengthIsLessThan(t) => "length.isLessThan(\{t})"
    StringLengthCompare(op, t) => "length \{pkl_string_length_op_text(op)} \{t}"
    StringMatchesRegex(pattern) => "matches(Regex(\"\{pattern}\"))"
    StringIsEmpty => "isEmpty"
    NotStringLengthIsBetween(lo, hi) => "!length.isBetween(\{lo}, \{hi})"
    NotStringLengthIsPositive => "!length.isPositive"
    NotStringLengthIsGreaterThan(t) => "!length.isGreaterThan(\{t})"
    NotStringLengthIsLessThan(t) => "!length.isLessThan(\{t})"
    NotStringLengthCompare(op, t) =>
      "!(length \{pkl_string_length_op_text(op)} \{t})"
    NotStringMatchesRegex(pattern) => "!matches(Regex(\"\{pattern}\"))"
    NotStringIsEmpty => "!isEmpty"
  }
}

///|
fn pkl_string_length_op_accepts(
  op : ConstraintStringLengthOp,
  length : Int,
  threshold : Int,
) -> Bool {
  match op {
    StringLengthGreaterThan => length > threshold
    StringLengthGreaterOrEqual => length >= threshold
    StringLengthLessThan => length < threshold
    StringLengthLessOrEqual => length <= threshold
    StringLengthEqual => length == threshold
    StringLengthNotEqual => length != threshold
  }
}

///|
fn pkl_string_predicate_accepts(
  predicate : ConstraintStringPredicate,
  value : String,
) -> Bool {
  let len = value.length()
  match predicate {
    StringLengthIsBetween(lower, upper) => len >= lower && len <= upper
    StringLengthIsPositive => len > 0
    StringLengthIsGreaterThan(threshold) => len > threshold
    StringLengthIsLessThan(threshold) => len < threshold
    StringLengthCompare(op, threshold) =>
      pkl_string_length_op_accepts(op, len, threshold)
    StringMatchesRegex(pattern) =>
      try {
        let re = @regexp.compile(pattern)
        let m = re.execute(value)
        m.matched() && m.before().length() == 0 && m.after().length() == 0
      } catch {
        // A malformed pattern means the predicate cannot accept anything;
        // surface this as a rejection via the diagnostic path so the user
        // sees the constraint name plus the bad pattern.
        _ => false
      }
    NotStringLengthIsBetween(lower, upper) => !(len >= lower && len <= upper)
    NotStringLengthIsPositive => !(len > 0)
    NotStringLengthIsGreaterThan(threshold) => !(len > threshold)
    NotStringLengthIsLessThan(threshold) => !(len < threshold)
    NotStringLengthCompare(op, threshold) =>
      !pkl_string_length_op_accepts(op, len, threshold)
    NotStringMatchesRegex(pattern) =>
      try {
        let re = @regexp.compile(pattern)
        let m = re.execute(value)
        !(m.matched() && m.before().length() == 0 && m.after().length() == 0)
      } catch {
        _ => true
      }
    StringIsEmpty => len == 0
    NotStringIsEmpty => len > 0
  }
}

///|
fn pkl_constrained_string_rejection_message_from_source(
  _display_name : String,
  source_name : String,
  value : String,
) -> String? {
  for predicate in pkl_constrained_string_predicates(source_name) {
    if !pkl_string_predicate_accepts(predicate, value) {
      return Some(
        "Type constraint `\{pkl_string_constraint_name(predicate)}` violated. Value: \"\{value}\"",
      )
    }
  }
  None
}
