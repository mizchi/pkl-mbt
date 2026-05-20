///|
fn pkl_value_int(value : Value) -> Int64? {
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
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements) =>
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
        ListingValue(elements)
        | DefaultedListingValue(_, elements, _)
        | ListValue(elements)
        | SetValue(elements) =>
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
        MappingValue(entries)
        | DefaultedMappingValue(_, entries, _)
        | MapValue(entries) =>
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
  StringStartsWith(String)
  StringEndsWith(String)
  StringContains(String)
  NotStringLengthIsBetween(Int, Int)
  NotStringLengthIsPositive
  NotStringLengthIsGreaterThan(Int)
  NotStringLengthIsLessThan(Int)
  NotStringLengthCompare(ConstraintStringLengthOp, Int)
  NotStringMatchesRegex(String)
  NotStringIsEmpty
  NotStringStartsWith(String)
  NotStringEndsWith(String)
  NotStringContains(String)
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
fn pkl_strip_default_type_marker(text : String) -> String {
  let trimmed = pkl_constraint_trim(text)
  if trimmed.has_prefix("*") {
    pkl_constraint_trim(
      String::unsafe_substring(trimmed, start=1, end=trimmed.length()),
    )
  } else {
    trimmed
  }
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
      Some(StringStartsWith(arg)) => return Some(NotStringStartsWith(arg))
      Some(StringEndsWith(arg)) => return Some(NotStringEndsWith(arg))
      Some(StringContains(arg)) => return Some(NotStringContains(arg))
      _ => return None
    }
  }
  // PKL-148ae: bare `isEmpty` / `this.isEmpty` on a String constraint
  // (Apple Pkl exposes `String.isEmpty` directly; the predicate form
  // shows up without a `length.` prefix unlike `length.isPositive`).
  if trimmed == "isEmpty" || trimmed == "this.isEmpty" {
    return Some(StringIsEmpty)
  }
  // PKL-148ai: bare `endsWith("X")` / `startsWith("X")` / `contains("X")`
  // (also the `this.endsWith(...)` form). The constraint name renders the
  // argument verbatim including the quotes — gold diagnostic shape is
  // `Type constraint `endsWith("A")` violated. Value: "noegiP"`.
  for prefix_with_paren in ["endsWith(", "this.endsWith("] {
    if trimmed.has_prefix(prefix_with_paren) && trimmed.has_suffix(")") {
      let inner = String::unsafe_substring(
        trimmed,
        start=prefix_with_paren.length(),
        end=trimmed.length() - 1,
      )
      let arg = pkl_constraint_trim(inner)
      if arg.length() >= 2 && arg.has_prefix("\"") && arg.has_suffix("\"") {
        return Some(
          StringEndsWith(
            String::unsafe_substring(arg, start=1, end=arg.length() - 1),
          ),
        )
      }
    }
  }
  for prefix_with_paren in ["startsWith(", "this.startsWith("] {
    if trimmed.has_prefix(prefix_with_paren) && trimmed.has_suffix(")") {
      let inner = String::unsafe_substring(
        trimmed,
        start=prefix_with_paren.length(),
        end=trimmed.length() - 1,
      )
      let arg = pkl_constraint_trim(inner)
      if arg.length() >= 2 && arg.has_prefix("\"") && arg.has_suffix("\"") {
        return Some(
          StringStartsWith(
            String::unsafe_substring(arg, start=1, end=arg.length() - 1),
          ),
        )
      }
    }
  }
  for prefix_with_paren in ["contains(", "this.contains("] {
    if trimmed.has_prefix(prefix_with_paren) && trimmed.has_suffix(")") {
      let inner = String::unsafe_substring(
        trimmed,
        start=prefix_with_paren.length(),
        end=trimmed.length() - 1,
      )
      let arg = pkl_constraint_trim(inner)
      if arg.length() >= 2 && arg.has_prefix("\"") && arg.has_suffix("\"") {
        return Some(
          StringContains(
            String::unsafe_substring(arg, start=1, end=arg.length() - 1),
          ),
        )
      }
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
    StringStartsWith(arg) => "startsWith(\"\{arg}\")"
    StringEndsWith(arg) => "endsWith(\"\{arg}\")"
    StringContains(arg) => "contains(\"\{arg}\")"
    NotStringLengthIsBetween(lo, hi) => "!length.isBetween(\{lo}, \{hi})"
    NotStringLengthIsPositive => "!length.isPositive"
    NotStringLengthIsGreaterThan(t) => "!length.isGreaterThan(\{t})"
    NotStringLengthIsLessThan(t) => "!length.isLessThan(\{t})"
    NotStringLengthCompare(op, t) =>
      "!(length \{pkl_string_length_op_text(op)} \{t})"
    NotStringMatchesRegex(pattern) => "!matches(Regex(\"\{pattern}\"))"
    NotStringIsEmpty => "!isEmpty"
    NotStringStartsWith(arg) => "!startsWith(\"\{arg}\")"
    NotStringEndsWith(arg) => "!endsWith(\"\{arg}\")"
    NotStringContains(arg) => "!contains(\"\{arg}\")"
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
    StringStartsWith(arg) => value.has_prefix(arg)
    StringEndsWith(arg) => value.has_suffix(arg)
    StringContains(arg) =>
      match value.find(arg) {
        Some(_) => true
        None => false
      }
    NotStringStartsWith(arg) => !value.has_prefix(arg)
    NotStringEndsWith(arg) => !value.has_suffix(arg)
    NotStringContains(arg) =>
      match value.find(arg) {
        Some(_) => false
        None => true
      }
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
