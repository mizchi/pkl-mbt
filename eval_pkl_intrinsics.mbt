///|
fn is_pkl_math_intrinsic_call(
  callee : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> Bool {
  match callee {
    Identifier(name) =>
      pkl_math_intrinsic_arity(name) is Some(_) &&
      !stack_contains_binding(stack, name) &&
      find_binding(bindings, name) is None
    _ => false
  }
}

///|
fn pkl_math_intrinsic_arity(name : String) -> Int? {
  match name {
    "_pkl_math_sqrt"
    | "_pkl_math_log"
    | "_pkl_math_exp"
    | "_pkl_math_floor"
    | "_pkl_math_ceil"
    | "_pkl_math_round"
    | "_pkl_math_sin"
    | "_pkl_math_cos"
    | "_pkl_math_tan"
    | "_pkl_math_atan" => Some(1)
    "_pkl_math_pow" | "_pkl_math_atan2" => Some(2)
    _ => None
  }
}

///|
fn eval_pkl_math_intrinsic(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let name = match callee {
    Identifier(n) => n
    _ => return None
  }
  let arity = match pkl_math_intrinsic_arity(name) {
    Some(n) => n
    None => return None
  }
  if arguments.length() != arity {
    diagnostics.push(
      diag("\{name} expects \{arity} arguments, got \{arguments.length()}"),
    )
    return None
  }
  let arg_values : Array[Double] = []
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(FloatValue(d)) => arg_values.push(d)
      Some(IntValue(n)) => arg_values.push(n.to_double())
      Some(_) => {
        diagnostics.push(diag("\{name} expects numeric arguments"))
        return None
      }
      None => return None
    }
  }
  match name {
    "_pkl_math_sqrt" => Some(FloatValue(arg_values[0].sqrt()))
    "_pkl_math_pow" => Some(FloatValue(@math.pow(arg_values[0], arg_values[1])))
    "_pkl_math_log" => Some(FloatValue(@math.ln(arg_values[0])))
    "_pkl_math_exp" => Some(FloatValue(@math.exp(arg_values[0])))
    "_pkl_math_floor" => Some(FloatValue(arg_values[0].floor()))
    "_pkl_math_ceil" => Some(FloatValue(arg_values[0].ceil()))
    "_pkl_math_round" => Some(FloatValue(arg_values[0].round()))
    "_pkl_math_sin" => Some(FloatValue(@math.sin(arg_values[0])))
    "_pkl_math_cos" => Some(FloatValue(@math.cos(arg_values[0])))
    "_pkl_math_tan" => Some(FloatValue(@math.tan(arg_values[0])))
    "_pkl_math_atan" => Some(FloatValue(@math.atan(arg_values[0])))
    "_pkl_math_atan2" =>
      Some(FloatValue(@math.atan2(arg_values[0], arg_values[1])))
    _ => None
  }
}

///|
/// PKL-123: detect `_pkl_semver_<op>` intrinsic calls and report
/// their declared arity. Same routing pattern as `pkl:math`.
fn is_pkl_semver_intrinsic_call(
  callee : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> Bool {
  match callee {
    Identifier(name) =>
      pkl_semver_intrinsic_arity(name) is Some(_) &&
      !stack_contains_binding(stack, name) &&
      find_binding(bindings, name) is None
    _ => false
  }
}

///|
fn pkl_semver_intrinsic_arity(name : String) -> Int? {
  match name {
    "_pkl_semver_parse" | "_pkl_semver_parse_or_null" => Some(1)
    "_pkl_semver_compare" => Some(2)
    _ => None
  }
}

///|
/// Parse a SemVer 2.0 string `MAJOR.MINOR.PATCH[-PRE][+BUILD]` into
/// its five components. Numeric core fields must be ASCII digits and
/// non-negative; pre-release / build segments may contain ASCII
/// alphanumerics, dots, and hyphens. Returns None on bad input.
fn pkl_semver_decompose(s : String) -> (Int, Int, Int, String?, String?)? {
  let (head, build) = match s.find("+") {
    None => (s, None)
    Some(idx) =>
      (
        String::unsafe_substring(s, start=0, end=idx),
        Some(String::unsafe_substring(s, start=idx + 1, end=s.length())),
      )
  }
  let (core, pre) = match head.find("-") {
    None => (head, None)
    Some(idx) =>
      (
        String::unsafe_substring(head, start=0, end=idx),
        Some(String::unsafe_substring(head, start=idx + 1, end=head.length())),
      )
  }
  let parts = core.split(".").collect()
  if parts.length() != 3 {
    return None
  }
  let major = parse_semver_int(parts[0].to_owned()) catch { _ => return None }
  let minor = parse_semver_int(parts[1].to_owned()) catch { _ => return None }
  let patch = parse_semver_int(parts[2].to_owned()) catch { _ => return None }
  match pre {
    Some(p) => if !is_valid_semver_identifier_list(p) { return None }
    None => ()
  }
  match build {
    Some(b) => if !is_valid_semver_identifier_list(b) { return None }
    None => ()
  }
  Some((major, minor, patch, pre, build))
}

///|
fn parse_semver_int(s : String) -> Int raise {
  if s.length() == 0 {
    fail("empty numeric segment")
  }
  let mut acc = 0
  for i in 0..<s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c < '0' || c > '9' {
      fail("non-digit in numeric segment")
    }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
  }
  acc
}

///|
fn is_valid_semver_identifier_list(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for part in s.split(".") {
    if part.length() == 0 {
      return false
    }
    for c in part.iter() {
      let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      let digit = c >= '0' && c <= '9'
      if !alpha && !digit && c != '-' {
        return false
      }
    }
  }
  true
}

///|
fn semver_value(
  major : Int,
  minor : Int,
  patch : Int,
  pre : String?,
  build : String?,
) -> Value {
  let pre_value = match pre {
    Some(p) => StringValue(p)
    None => NullValue
  }
  let build_value = match build {
    Some(b) => StringValue(b)
    None => NullValue
  }
  ObjectValue([
    { name: "major", value: IntValue(major) },
    { name: "minor", value: IntValue(minor) },
    { name: "patch", value: IntValue(patch) },
    { name: "preRelease", value: pre_value },
    { name: "build", value: build_value },
  ])
}

///|
/// SemVer pre-release ordering: dot-separated identifiers compared
/// pairwise. Numeric identifiers compare numerically; alphanumeric
/// identifiers compare lexicographically; numeric < alphanumeric;
/// fewer identifiers < more identifiers (left-aligned).
fn compare_semver_prerelease(a : String?, b : String?) -> Int {
  match (a, b) {
    (None, None) => 0
    // Version with pre-release ranks below version without pre-release.
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (Some(left), Some(right)) => {
      let left_parts = left.split(".").collect()
      let right_parts = right.split(".").collect()
      let len = if left_parts.length() < right_parts.length() {
        left_parts.length()
      } else {
        right_parts.length()
      }
      for i in 0..<len {
        let lp = left_parts[i].to_owned()
        let rp = right_parts[i].to_owned()
        let cmp = compare_semver_identifier(lp, rp)
        if cmp != 0 {
          return cmp
        }
      }
      if left_parts.length() < right_parts.length() {
        -1
      } else if left_parts.length() > right_parts.length() {
        1
      } else {
        0
      }
    }
  }
}

///|
fn is_numeric_identifier(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for c in s.iter() {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn compare_semver_identifier(a : String, b : String) -> Int {
  let a_num = is_numeric_identifier(a)
  let b_num = is_numeric_identifier(b)
  if a_num && b_num {
    let ai = parse_semver_int(a) catch { _ => return 0 }
    let bi = parse_semver_int(b) catch { _ => return 0 }
    if ai < bi {
      -1
    } else if ai > bi {
      1
    } else {
      0
    }
  } else if a_num && !b_num {
    -1
  } else if !a_num && b_num {
    1
  } else if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn compare_semver_values(a : Value, b : Value) -> Int? {
  let (a_major, a_minor, a_patch, a_pre) = match extract_semver_core(a) {
    Some(t) => t
    None => return None
  }
  let (b_major, b_minor, b_patch, b_pre) = match extract_semver_core(b) {
    Some(t) => t
    None => return None
  }
  if a_major != b_major {
    return Some(if a_major < b_major { -1 } else { 1 })
  }
  if a_minor != b_minor {
    return Some(if a_minor < b_minor { -1 } else { 1 })
  }
  if a_patch != b_patch {
    return Some(if a_patch < b_patch { -1 } else { 1 })
  }
  Some(compare_semver_prerelease(a_pre, b_pre))
}

///|
fn extract_semver_core(v : Value) -> (Int, Int, Int, String?)? {
  match v {
    ObjectValue(members) => {
      let major = match find_int_member(members, "major") {
        Some(n) => n
        None => return None
      }
      let minor = match find_int_member(members, "minor") {
        Some(n) => n
        None => return None
      }
      let patch = match find_int_member(members, "patch") {
        Some(n) => n
        None => return None
      }
      let pre = match find_member(members, "preRelease") {
        Some(StringValue(s)) => Some(s)
        Some(NullValue) | None => None
        Some(_) => return None
      }
      Some((major, minor, patch, pre))
    }
    _ => None
  }
}

///|
fn find_member(members : Array[ValueMember], name : String) -> Value? {
  for m in members {
    if m.name == name {
      return Some(m.value)
    }
  }
  None
}

///|
fn find_int_member(members : Array[ValueMember], name : String) -> Int? {
  match find_member(members, name) {
    Some(IntValue(n)) => Some(n)
    _ => None
  }
}

///|
fn eval_pkl_semver_intrinsic(
  callee : Expr,
  arguments : Array[Expr],
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Value? {
  let name = match callee {
    Identifier(n) => n
    _ => return None
  }
  let arity = match pkl_semver_intrinsic_arity(name) {
    Some(n) => n
    None => return None
  }
  if arguments.length() != arity {
    diagnostics.push(
      diag("\{name} expects \{arity} arguments, got \{arguments.length()}"),
    )
    return None
  }
  let arg_values : Array[Value] = []
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => return None
    }
  }
  match name {
    "_pkl_semver_parse" => {
      let s = match arg_values[0] {
        StringValue(s) => s
        _ => {
          diagnostics.push(diag("semver.parse expects a String argument"))
          return None
        }
      }
      match pkl_semver_decompose(s) {
        Some((major, minor, patch, pre, build)) =>
          Some(semver_value(major, minor, patch, pre, build))
        None => {
          diagnostics.push(
            diag("semver.parse: invalid version string \"\{s}\""),
          )
          None
        }
      }
    }
    "_pkl_semver_parse_or_null" => {
      let s = match arg_values[0] {
        StringValue(s) => s
        _ => {
          diagnostics.push(diag("semver.parseOrNull expects a String argument"))
          return None
        }
      }
      match pkl_semver_decompose(s) {
        Some((major, minor, patch, pre, build)) =>
          Some(semver_value(major, minor, patch, pre, build))
        None => Some(NullValue)
      }
    }
    "_pkl_semver_compare" =>
      match compare_semver_values(arg_values[0], arg_values[1]) {
        Some(n) => Some(IntValue(n))
        None => {
          diagnostics.push(
            diag("semver.compare expects two parsed Version objects"),
          )
          None
        }
      }
    _ => None
  }
}
