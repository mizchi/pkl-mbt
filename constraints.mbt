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
  match pkl_constrained_type_base_name(type_name) {
    Some("Int") =>
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
  pkl_constrained_int_predicates(type_name).length() > 0
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
      pkl_constrained_int_rejection_message_from_source(
        display_name, source_name, value,
      )
    None => None
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
fn pkl_value_int(value : Value) -> Int? {
  match value {
    IntValue(inner) => Some(inner)
    _ => None
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
      pkl_constrained_int_rejection_message_from_source(
        display_name, source_name, inner,
      )
    None => None
  }
}
