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
    | "_pkl_math_cbrt"
    | "_pkl_math_log"
    | "_pkl_math_log2"
    | "_pkl_math_log10"
    | "_pkl_math_exp"
    | "_pkl_math_floor"
    | "_pkl_math_ceil"
    | "_pkl_math_round"
    | "_pkl_math_sin"
    | "_pkl_math_cos"
    | "_pkl_math_tan"
    | "_pkl_math_asin"
    | "_pkl_math_acos"
    | "_pkl_math_is_power_of_two"
    | "_pkl_math_atan" => Some(1)
    "_pkl_math_pow"
    | "_pkl_math_atan2"
    | "_pkl_math_gcd"
    | "_pkl_math_lcm"
    | "_pkl_math_min"
    | "_pkl_math_max" => Some(2)
    _ => None
  }
}

///|
fn pkl_math_numeric_arg(value : Value) -> Double? {
  match value {
    FloatValue(d) => Some(d)
    IntValue(n) => Some(n.to_double())
    _ => None
  }
}

///|
fn pkl_math_int_arg(value : Value, diagnostics : Array[Diagnostic]) -> Int64? {
  match value {
    IntValue(n) =>
      if n < 0L {
        diagnostics.push(
          diag("Expected a positive number, but got `\{n.to_string()}`."),
        )
        None
      } else {
        Some(n)
      }
    _ => {
      diagnostics.push(
        diag(
          "Expected value of type `Int`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
        ),
      )
      None
    }
  }
}

///|
fn int64_gcd(a : Int64, b : Int64) -> Int64 {
  let mut x = a
  let mut y = b
  while y != 0L {
    let r = x % y
    x = y
    y = r
  }
  if x < 0L {
    0L - x
  } else {
    x
  }
}

///|
fn int64_is_power_of_two(n : Int64) -> Bool {
  n > 0L && (n & (n - 1L)) == 0L
}

///|
fn double_is_negative_zero(d : Double) -> Bool {
  d == 0.0 && (1.0 / d).is_neg_inf()
}

///|
fn pkl_math_minmax(name : String, left : Value, right : Value) -> Value? {
  match (left, right) {
    (IntValue(a), IntValue(b)) =>
      if name == "_pkl_math_min" {
        Some(IntValue(if a < b { a } else { b }))
      } else {
        Some(IntValue(if a > b { a } else { b }))
      }
    _ => {
      let a = match pkl_math_numeric_arg(left) {
        Some(v) => v
        None => return None
      }
      let b = match pkl_math_numeric_arg(right) {
        Some(v) => v
        None => return None
      }
      if a.is_nan() || b.is_nan() {
        return Some(FloatValue(0.0 / 0.0))
      }
      if name == "_pkl_math_min" {
        if a == 0.0 &&
          b == 0.0 &&
          (double_is_negative_zero(a) || double_is_negative_zero(b)) {
          Some(FloatValue(-0.0))
        } else {
          Some(FloatValue(if a < b { a } else { b }))
        }
      } else if a == 0.0 && b == 0.0 {
        Some(FloatValue(0.0))
      } else {
        Some(FloatValue(if a > b { a } else { b }))
      }
    }
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
  let raw_values : Array[Value] = []
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(value) => raw_values.push(value)
      None => return None
    }
  }
  let arg_values : Array[Double] = []
  if name != "_pkl_math_gcd" &&
    name != "_pkl_math_lcm" &&
    name != "_pkl_math_is_power_of_two" &&
    name != "_pkl_math_min" &&
    name != "_pkl_math_max" {
    for value in raw_values {
      match pkl_math_numeric_arg(value) {
        Some(d) => arg_values.push(d)
        None => {
          diagnostics.push(diag("\{name} expects numeric arguments"))
          return None
        }
      }
    }
  }
  match name {
    "_pkl_math_sqrt" => Some(FloatValue(arg_values[0].sqrt()))
    "_pkl_math_cbrt" => Some(FloatValue(@math.cbrt(arg_values[0])))
    "_pkl_math_pow" => Some(FloatValue(@math.pow(arg_values[0], arg_values[1])))
    "_pkl_math_log" => Some(FloatValue(@math.ln(arg_values[0])))
    // PKL-148bo: `@math.log2(x)` computes `ln(f)/LN2 + e` after
    // `frexp(x) = (f, e)`. The intermediate `1/LN2` multiplication
    // loses a couple of ulps on inputs whose `f` is not a clean
    // power of two — `log2(2.34)` for example comes out
    // `1.2265085298086795` versus Apple Pkl / fdlibm's correctly-
    // rounded `1.2265085298086797`. `ln(x) / ln(2.0)` keeps the
    // computation in a single division and round-trips through the
    // same `ln`, matching the upstream gold for `api/mathModule`.
    "_pkl_math_log2" =>
      Some(FloatValue(@math.ln(arg_values[0]) / @math.ln(2.0)))
    "_pkl_math_log10" => Some(FloatValue(@math.log10(arg_values[0])))
    "_pkl_math_exp" => Some(FloatValue(@math.exp(arg_values[0])))
    "_pkl_math_floor" => Some(FloatValue(arg_values[0].floor()))
    "_pkl_math_ceil" => Some(FloatValue(arg_values[0].ceil()))
    "_pkl_math_round" => Some(FloatValue(arg_values[0].round()))
    // PKL-148bp: macOS `libm`'s `sin` / `cos` (the path
    // `@math.sin` / `@math.cos` take on native) disagree with
    // Apple Pkl by 1–2 ulps for inputs like 2.34 because
    // Apple's GraalVM native-image binary routes through
    // `StrictMath`, itself a port of Sun's fdlibm. Route through
    // the small fdlibm kernel + Cody-Waite reduction in
    // `eval_math_fdlibm.mbt` so the upstream `api/mathModule`
    // gold (`sin(2.34) == 0.7184647930691261`) matches byte for
    // byte.
    "_pkl_math_sin" => Some(FloatValue(fdlibm_sin(arg_values[0])))
    "_pkl_math_cos" => Some(FloatValue(fdlibm_cos(arg_values[0])))
    "_pkl_math_tan" => Some(FloatValue(fdlibm_tan(arg_values[0])))
    "_pkl_math_asin" => Some(FloatValue(@math.asin(arg_values[0])))
    "_pkl_math_acos" => Some(FloatValue(@math.acos(arg_values[0])))
    "_pkl_math_atan" => Some(FloatValue(@math.atan(arg_values[0])))
    "_pkl_math_atan2" =>
      Some(FloatValue(@math.atan2(arg_values[0], arg_values[1])))
    "_pkl_math_gcd" => {
      let a = match pkl_math_int_arg(raw_values[0], diagnostics) {
        Some(n) => n
        None => return None
      }
      let b = match pkl_math_int_arg(raw_values[1], diagnostics) {
        Some(n) => n
        None => return None
      }
      Some(IntValue(int64_gcd(a, b)))
    }
    "_pkl_math_lcm" => {
      let a = match pkl_math_int_arg(raw_values[0], diagnostics) {
        Some(n) => n
        None => return None
      }
      let b = match pkl_math_int_arg(raw_values[1], diagnostics) {
        Some(n) => n
        None => return None
      }
      let g = int64_gcd(a, b)
      if a == 0L || b == 0L {
        Some(IntValue(0L))
      } else {
        match checked_int64_mul(a / g, b) {
          Some(n) => Some(IntValue(n))
          None => {
            diagnostics.push(diag("Integer overflow."))
            None
          }
        }
      }
    }
    "_pkl_math_is_power_of_two" =>
      match raw_values[0] {
        IntValue(n) => Some(BoolValue(int64_is_power_of_two(n)))
        FloatValue(d) =>
          if d.is_nan() || d.is_inf() || d <= 0.0 {
            Some(BoolValue(false))
          } else {
            let rounded = d.round()
            Some(
              BoolValue(
                rounded == d && @math.pow(2.0, @math.log2(d).round()) == d,
              ),
            )
          }
        _ => {
          diagnostics.push(diag("\{name} expects numeric arguments"))
          None
        }
      }
    "_pkl_math_min" | "_pkl_math_max" =>
      match pkl_math_minmax(name, raw_values[0], raw_values[1]) {
        Some(value) => Some(value)
        None => {
          diagnostics.push(diag("\{name} expects numeric arguments"))
          None
        }
      }
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
fn is_pkl_reflect_intrinsic_call(
  callee : Expr,
  bindings : Array[Binding],
  stack : Array[String],
) -> Bool {
  match callee {
    Identifier(name) =>
      pkl_reflect_intrinsic_arity(name) is Some(_) &&
      !stack_contains_binding(stack, name) &&
      find_binding(bindings, name) is None
    _ => false
  }
}

///|
fn pkl_reflect_intrinsic_arity(name : String) -> Int? {
  match name {
    "_pkl_reflect_type"
    | "_pkl_reflect_class"
    | "_pkl_reflect_type_alias"
    | "_pkl_reflect_module"
    | "_pkl_reflect_declared_type"
    | "_pkl_reflect_union_type"
    | "_pkl_reflect_string_literal_type"
    | "_pkl_reflect_type_variable" => Some(1)
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
  if s.length() > 1 && s[0].to_int().unsafe_to_char() == '0' {
    fail("leading zero in numeric segment")
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
  let members : Array[ValueMember] = [
    {
      name: "major",
      value: IntValue(major.to_int64()),
      source: None,
      annotations: [],
    },
    {
      name: "minor",
      value: IntValue(minor.to_int64()),
      source: None,
      annotations: [],
    },
    {
      name: "patch",
      value: IntValue(patch.to_int64()),
      source: None,
      annotations: [],
    },
    {
      name: hidden_member_name("__semver_version"),
      value: BoolValue(true),
      source: None,
      annotations: [],
    },
  ]
  match pre {
    Some(p) =>
      members.push({
        name: "preRelease",
        value: StringValue(p),
        source: None,
        annotations: [],
      })
    None => ()
  }
  match build {
    Some(b) =>
      members.push({
        name: "build",
        value: StringValue(b),
        source: None,
        annotations: [],
      })
    None => ()
  }
  ObjectValue(members)
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
  } else {
    a.lexical_compare(b)
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
fn is_semver_value_members(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "__semver_version") {
    Some(BoolValue(true)) => true
    _ => false
  }
}

///|
fn semver_build_from_members(members : Array[ValueMember]) -> String? {
  match find_member(members, "build") {
    Some(StringValue(s)) => Some(s)
    _ => None
  }
}

///|
fn semver_to_string(members : Array[ValueMember]) -> String? {
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
  let mut out = "\{major}.\{minor}.\{patch}"
  match find_member(members, "preRelease") {
    Some(StringValue(s)) => out = out + "-" + s
    _ => ()
  }
  match semver_build_from_members(members) {
    Some(s) => out = out + "+" + s
    None => ()
  }
  Some(out)
}

///|
fn is_semver_version_method_name(name : String) -> Bool {
  name == "toString" ||
  name == "equals" ||
  name == "isLessThan" ||
  name == "isLessThanOrEquals" ||
  name == "isGreaterThan" ||
  name == "isGreaterThanOrEquals" ||
  name == "isNormal" ||
  name == "isStable"
}

///|
fn eval_semver_version_method(
  receiver_members : Array[ValueMember],
  method_name : String,
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
  if !is_semver_value_members(receiver_members) {
    return None
  }
  if method_name == "toString" {
    if arguments.length() != 0 {
      diagnostics.push(diag("Version.toString takes no arguments"))
      return None
    }
    match semver_to_string(receiver_members) {
      Some(text) => return Some(StringValue(text))
      None => return None
    }
  }
  if method_name == "isNormal" || method_name == "isStable" {
    if arguments.length() != 0 {
      diagnostics.push(diag("Version.\{method_name} takes no arguments"))
      return None
    }
    let pre = match find_member(receiver_members, "preRelease") {
      Some(StringValue(_)) => true
      _ => false
    }
    let build = match find_member(receiver_members, "build") {
      Some(StringValue(_)) => true
      _ => false
    }
    if method_name == "isNormal" {
      return Some(BoolValue(!pre && !build))
    }
    let major = match find_int_member(receiver_members, "major") {
      Some(n) => n
      None => return Some(BoolValue(false))
    }
    return Some(BoolValue(major > 0 && !pre))
  }
  if arguments.length() != 1 {
    diagnostics.push(diag("Version.\{method_name} expects 1 argument"))
    return None
  }
  let other = match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(value) => value
    None => return None
  }
  let cmp = match compare_semver_values(ObjectValue(receiver_members), other) {
    Some(n) => n
    None => {
      diagnostics.push(
        diag("Version.\{method_name} expects a Version argument"),
      )
      return None
    }
  }
  match method_name {
    "equals" => Some(BoolValue(cmp == 0))
    "isLessThan" => Some(BoolValue(cmp < 0))
    "isLessThanOrEquals" => Some(BoolValue(cmp <= 0))
    "isGreaterThan" => Some(BoolValue(cmp > 0))
    "isGreaterThanOrEquals" => Some(BoolValue(cmp >= 0))
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
    Some(IntValue(n)) => Some(n.to_int())
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
            diag("`\{s}` is not a valid semantic version number."),
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
        Some(n) => Some(IntValue(n.to_int64()))
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

///|
fn eval_pkl_reflect_intrinsic(
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
  let arity = match pkl_reflect_intrinsic_arity(name) {
    Some(n) => n
    None => return None
  }
  if arguments.length() != arity {
    diagnostics.push(
      diag("\{name} expects \{arity} arguments, got \{arguments.length()}"),
    )
    return None
  }
  let arg = match
    eval_expr_with_bindings(
      arguments[0],
      bindings,
      env,
      class_env,
      cache,
      stack,
      declarations,
      diagnostics,
      resolve_import,
    ) {
    Some(v) => v
    None => return None
  }
  match name {
    "_pkl_reflect_type" =>
      match arg {
        StringValue(type_name) => Some(reflect_type_value(type_name, []))
        _ => {
          diagnostics.push(diag("reflect type constructor expects a String"))
          None
        }
      }
    "_pkl_reflect_class" => Some(reflect_class_factory_value(arg))
    "_pkl_reflect_type_alias" => Some(reflect_type_alias_factory_value(arg))
    "_pkl_reflect_module" => Some(reflect_module_factory_value(arg))
    "_pkl_reflect_declared_type" => Some(reflect_declared_type_value(arg, []))
    "_pkl_reflect_union_type" =>
      match arg {
        ListingValue(types) | ListValue(types) =>
          Some(reflect_union_type_value(types))
        _ => {
          diagnostics.push(diag("reflect.UnionType expects a List argument"))
          None
        }
      }
    "_pkl_reflect_string_literal_type" =>
      match arg {
        StringValue(s) => Some(reflect_string_literal_type_value(s))
        _ => {
          diagnostics.push(
            diag("reflect.StringLiteralType expects a String argument"),
          )
          None
        }
      }
    "_pkl_reflect_type_variable" =>
      match arg {
        ObjectValue(members) =>
          match lookup_member(members, "name") {
            Some(StringValue(name)) => Some(reflect_type_variable_value(name))
            _ => {
              diagnostics.push(
                diag("reflect.TypeVariable expects a type parameter"),
              )
              None
            }
          }
        StringValue(name) => Some(reflect_type_variable_value(name))
        _ => {
          diagnostics.push(
            diag("reflect.TypeVariable expects a type parameter"),
          )
          None
        }
      }
    _ => None
  }
}
