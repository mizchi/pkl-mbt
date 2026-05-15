///|
priv struct ConstraintIntRange {
  lower : Int
  upper : Int
}

///|
priv struct ConstraintIntCall {
  name : String
  argument : Int
}

///|
priv enum ConstraintIntPredicate {
  IsBetween(Int, Int)
  IsPositive
  IsGreaterThan(Int)
  IsLessThan(Int)
  NotIsBetween(Int, Int)
  NotIsPositive
  NotIsGreaterThan(Int)
  NotIsLessThan(Int)
  CustomGreaterThan(String, Int)
  CustomLessThan(String, Int)
  CustomGreaterOrEqual(String, Int)
  CustomLessOrEqual(String, Int)
  NotCustomGreaterThan(String, Int)
  NotCustomLessThan(String, Int)
  NotCustomGreaterOrEqual(String, Int)
  NotCustomLessOrEqual(String, Int)
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
fn pkl_constraint_property_matches(text : String, name : String) -> Bool {
  text == name || text == "this." + name
}

///|
fn pkl_single_int_constraint_argument(text : String, name : String) -> Int? {
  match pkl_constraint_call_inner(text, name + "(") {
    Some(inner) => pkl_parse_constraint_int_text(inner)
    None =>
      match pkl_constraint_call_inner(text, "this." + name + "(") {
        Some(inner) => pkl_parse_constraint_int_text(inner)
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
        match pkl_parse_constraint_int_text(inner) {
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
  None
}

///|
fn pkl_user_defined_int_constraint_from_order(
  function_name : String,
  threshold : Int,
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
  threshold : Int,
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
  threshold : Int,
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
  match predicate {
    IsBetween(_, _) => "isBetween"
    IsPositive => "isPositive"
    IsGreaterThan(_) => "isGreaterThan"
    IsLessThan(_) => "isLessThan"
    NotIsBetween(_, _) => "!isBetween"
    NotIsPositive => "!isPositive"
    NotIsGreaterThan(_) => "!isGreaterThan"
    NotIsLessThan(_) => "!isLessThan"
    CustomGreaterThan(name, _) => name
    CustomLessThan(name, _) => name
    CustomGreaterOrEqual(name, _) => name
    CustomLessOrEqual(name, _) => name
    NotCustomGreaterThan(name, _) => "!" + name
    NotCustomLessThan(name, _) => "!" + name
    NotCustomGreaterOrEqual(name, _) => "!" + name
    NotCustomLessOrEqual(name, _) => "!" + name
  }
}

///|
fn pkl_constraint_predicate_accepts(
  predicate : ConstraintIntPredicate,
  value : Int,
) -> Bool {
  match predicate {
    IsBetween(lower, upper) => value >= lower && value <= upper
    IsPositive => value > 0
    IsGreaterThan(threshold) => value > threshold
    IsLessThan(threshold) => value < threshold
    NotIsBetween(lower, upper) => !(value >= lower && value <= upper)
    NotIsPositive => !(value > 0)
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
  }
}

///|
fn pkl_constrained_int_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : Int,
) -> String? {
  for predicate in pkl_constrained_int_predicates(source_name) {
    if !pkl_constraint_predicate_accepts(predicate, value) {
      return Some(
        "type annotation \{display_name} constraint \{pkl_constraint_name(predicate)} rejects \{value}",
      )
    }
  }
  None
}

///|
fn pkl_user_defined_constrained_int_rejection_message_from_source(
  display_name : String,
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
        "type annotation \{display_name} constraint \{pkl_constraint_name(predicate)} rejects \{value}",
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
  // PKL-092: Int-side thresholds widen to Double for the comparison.
  // Custom predicate factories that accept an Int threshold (today's
  // user-defined surface) flow through this path uniformly.
  match predicate {
    IsBetween(lower, upper) =>
      value >= lower.to_double() && value <= upper.to_double()
    IsPositive => value > 0.0
    IsGreaterThan(threshold) => value > threshold.to_double()
    IsLessThan(threshold) => value < threshold.to_double()
    NotIsBetween(lower, upper) =>
      !(value >= lower.to_double() && value <= upper.to_double())
    NotIsPositive => !(value > 0.0)
    NotIsGreaterThan(threshold) => !(value > threshold.to_double())
    NotIsLessThan(threshold) => !(value < threshold.to_double())
    CustomGreaterThan(_, threshold) => value > threshold.to_double()
    CustomLessThan(_, threshold) => value < threshold.to_double()
    CustomGreaterOrEqual(_, threshold) => value >= threshold.to_double()
    CustomLessOrEqual(_, threshold) => value <= threshold.to_double()
    NotCustomGreaterThan(_, threshold) => !(value > threshold.to_double())
    NotCustomLessThan(_, threshold) => !(value < threshold.to_double())
    NotCustomGreaterOrEqual(_, threshold) => !(value >= threshold.to_double())
    NotCustomLessOrEqual(_, threshold) => !(value <= threshold.to_double())
  }
}

///|
fn pkl_constrained_float_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : Double,
) -> String? {
  for predicate in pkl_constrained_int_predicates(source_name) {
    if !pkl_constraint_predicate_accepts_float(predicate, value) {
      return Some(
        "type annotation \{display_name} constraint \{pkl_constraint_name(predicate)} rejects \{value}",
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
      diagnostics.push(Diagnostic::{ message, })
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
  pkl_collection_element_rejection_message_from_source(
    display_name, source_name, value,
  )
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
  match generic_argument_text(source_name, "Listing") {
    Some(element_type) =>
      match value {
        ListingValue(elements) =>
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
  match generic_argument_text(source_name, "Mapping") {
    Some(inner_text) => {
      let parts = split_top_level_generic_arguments(inner_text)
      if parts.length() != 2 {
        return None
      }
      let key_type = parts[0]
      let value_type = parts[1]
      match value {
        MappingValue(entries) =>
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
            return None
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
  NotStringLengthIsBetween(Int, Int)
  NotStringLengthIsPositive
  NotStringLengthIsGreaterThan(Int)
  NotStringLengthIsLessThan(Int)
  NotStringLengthCompare(ConstraintStringLengthOp, Int)
  NotStringMatchesRegex(String)
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
      // share the numeric grammar.
      match pkl_int_constraint_predicate(suffix) {
        Some(IsBetween(lower, upper)) =>
          Some(StringLengthIsBetween(lower, upper))
        Some(IsPositive) => Some(StringLengthIsPositive)
        Some(IsGreaterThan(n)) => Some(StringLengthIsGreaterThan(n))
        Some(IsLessThan(n)) => Some(StringLengthIsLessThan(n))
        Some(NotIsBetween(lower, upper)) =>
          Some(NotStringLengthIsBetween(lower, upper))
        Some(NotIsPositive) => Some(NotStringLengthIsPositive)
        Some(NotIsGreaterThan(n)) => Some(NotStringLengthIsGreaterThan(n))
        Some(NotIsLessThan(n)) => Some(NotStringLengthIsLessThan(n))
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
      _ => return None
    }
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
  match predicate {
    StringLengthIsBetween(_, _) => "length.isBetween"
    StringLengthIsPositive => "length.isPositive"
    StringLengthIsGreaterThan(_) => "length.isGreaterThan"
    StringLengthIsLessThan(_) => "length.isLessThan"
    StringLengthCompare(op, _) => "length \{pkl_string_length_op_text(op)}"
    StringMatchesRegex(_) => "matches"
    NotStringLengthIsBetween(_, _) => "!length.isBetween"
    NotStringLengthIsPositive => "!length.isPositive"
    NotStringLengthIsGreaterThan(_) => "!length.isGreaterThan"
    NotStringLengthIsLessThan(_) => "!length.isLessThan"
    NotStringLengthCompare(op, _) =>
      "!(length \{pkl_string_length_op_text(op)})"
    NotStringMatchesRegex(_) => "!matches"
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
  }
}

///|
fn pkl_constrained_string_rejection_message_from_source(
  display_name : String,
  source_name : String,
  value : String,
) -> String? {
  for predicate in pkl_constrained_string_predicates(source_name) {
    if !pkl_string_predicate_accepts(predicate, value) {
      return Some(
        "type annotation \{display_name} constraint \{pkl_string_constraint_name(predicate)} rejects \"\{value}\"",
      )
    }
  }
  None
}
