///|
fn is_string_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: pkl:base.String surface — `isNotEmpty`, `isBlank`,
    // `isNotBlank`, `reverse`, `base64`, plus the surrogate-pair
    // accessors.
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars"
    // PKL-149: extra pkl:base.String property surface (api/string facts
    // batch). `isBase64`, `lastIndex`, `isRegex`, `base64Decoded`,
    // `base64DecodedBytes` are all bare property reads in Apple Pkl.
    | "isBase64"
    | "lastIndex"
    | "isRegex"
    | "base64Decoded"
    | "base64DecodedBytes" => true
    _ => false
  }
}

///|
fn is_string_method_name(name : String) -> Bool {
  match name {
    "toUpperCase"
    | "toLowerCase"
    | "contains"
    | "startsWith"
    | "endsWith"
    | "indexOf"
    | "replaceAll"
    | "replaceFirst"
    | "take"
    | "drop"
    | "split"
    | "padStart"
    | "padEnd"
    | "toBytes"
    | "codePointAt"
    // Apple Pkl exposes the no-arg surface (`reverse`, `isEmpty`,
    // `length`, etc.) as both property reads and method calls.
    | "length"
    | "isEmpty"
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars"
    // PKL-149: extended pkl:base.String method surface for the
    // api/string.pkl fact/example matrix. All five trim/case helpers,
    // numeric conversions (toInt / toFloat / toBoolean and their
    // `*OrNull` siblings), regex match (`matches`), `repeat`,
    // substring/get bounds-safe siblings, and three more replace
    // variants (`replaceLast`, `replaceAllMapped`,
    // `replaceFirstMapped`, `replaceLastMapped`, `replaceRange`).
    // `indexOfOrNull` / `lastIndexOf` / `lastIndexOfOrNull` /
    // `splitLimit` round out the search surface. Also covers the
    // bare-property names that Apple Pkl accepts as zero-arg method
    // calls (`isBase64()` / `lastIndex()` etc).
    | "matches"
    | "capitalize"
    | "decapitalize"
    | "repeat"
    | "trim"
    | "trimStart"
    | "trimEnd"
    | "toBoolean"
    | "toBooleanOrNull"
    | "toInt"
    | "toIntOrNull"
    | "toFloat"
    | "toFloatOrNull"
    | "substring"
    | "substringOrNull"
    | "getOrNull"
    | "replaceLast"
    | "replaceRange"
    | "replaceAllMapped"
    | "replaceFirstMapped"
    | "replaceLastMapped"
    | "indexOfOrNull"
    | "lastIndexOf"
    | "lastIndexOfOrNull"
    | "splitLimit"
    | "takeWhile"
    | "takeLast"
    | "takeLastWhile"
    | "dropWhile"
    | "dropLast"
    | "dropLastWhile"
    | "isBase64"
    | "lastIndex"
    | "isRegex"
    | "base64Decoded"
    | "base64DecodedBytes" => true
    _ => false
  }
}

///|
fn is_int_property_name(name : String) -> Bool {
  match name {
    "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv"
    // PKL-150: Int.ceil / .floor / .round / .truncate are no-ops on
    // an integer (they round to the nearest Int, which is `self`).
    // Apple Pkl projects them as both property reads and `()` calls.
    | "ceil"
    | "floor"
    | "round"
    | "truncate" => true
    _ => false
  }
}

///|
fn is_int_method_name(name : String) -> Bool {
  match name {
    // PKL-148b: pkl:base Int method surface adds `isBetween(a, b)`,
    // `toFloat()`, `shl` / `shr` / `ushr` / `or` / `and` / `xor`.
    "toString"
    | "toChar"
    | "toFloat"
    | "isBetween"
    // PKL-150: Int method surface — radix-string / fixed-decimal /
    // `toInt()` (no-op) / `toDuration(unit)` / `toDataSize(unit)` /
    // bitwise binary methods.
    | "toInt"
    | "toRadixString"
    | "toFixed"
    | "toDuration"
    | "toDataSize"
    | "shl"
    | "shr"
    | "ushr"
    | "and"
    | "or"
    | "xor"
    // No-arg property surface also accessible as `(N).method()`.
    | "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv"
    | "ceil"
    | "floor"
    | "round"
    | "truncate" => true
    _ => false
  }
}

///|
/// PKL-152: pkl:base.Typed method surface — `getProperty(name)`,
/// `getPropertyOrNull(name)`, `hasProperty(name)`, `toMap()`,
/// `toDynamic()`. These dispatch off any ObjectValue receiver via
/// the eval_callable_call intercept.
fn is_typed_method_name(name : String) -> Bool {
  match name {
    "getProperty"
    | "getPropertyOrNull"
    | "hasProperty"
    | "toMap"
    | "toDynamic"
    // PKL-152: Dynamic-specific introspection — `length` (number of
    // bare-element members), `toList` (project elements into a List),
    // `toTyped(<class>)` (cast a Dynamic into a Typed instance with
    // the supplied class).
    | "length"
    | "toList"
    | "toTyped" => true
    _ => false
  }
}

///|
/// PKL-152: dispatch a pkl:base.Typed method against a user-class
/// ObjectValue receiver. Each arm validates argument count locally;
/// missing properties surface the module-qualified diagnostic, in
/// keeping with `api/typed`'s gold wording.
fn eval_typed_method_dispatch(
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
  match method_name {
    "getProperty" | "getPropertyOrNull" | "hasProperty" => {
      if arguments.length() != 1 {
        diagnostics.push(
          diag("\{method_name} expects 1 argument, got \{arguments.length()}"),
        )
        return None
      }
      let name_value = eval_expr_with_bindings(
        arguments[0],
        bindings,
        env,
        class_env,
        cache,
        stack,
        declarations,
        diagnostics,
        resolve_import,
      )
      match name_value {
        Some(StringValue(name)) => {
          let mut found : Value? = None
          for m in receiver_members {
            if !is_invisible_member_name(m.name) && m.name == name {
              found = Some(m.value)
              break
            }
          }
          match (method_name, found) {
            ("getProperty", Some(v)) => Some(v)
            ("getProperty", None) => {
              let class_tag = match find_object_class_tag(receiver_members) {
                Some(s) => s
                None => "Dynamic"
              }
              let qualified = if is_stdlib_class_name(class_tag) {
                class_tag
              } else {
                let module_name = match lookup_value(cache, "@__module_name") {
                  Some(StringValue(s)) => s
                  _ => ""
                }
                if module_name.length() > 0 {
                  "\{module_name}#\{class_tag}"
                } else {
                  class_tag
                }
              }
              diagnostics.push(
                diag(
                  "Cannot find property `\{name}` in object of type `\{qualified}`.",
                ),
              )
              None
            }
            ("getPropertyOrNull", Some(v)) => Some(v)
            ("getPropertyOrNull", None) => Some(NullValue)
            ("hasProperty", Some(_)) => Some(BoolValue(true))
            ("hasProperty", None) => Some(BoolValue(false))
            _ => None
          }
        }
        Some(_) => {
          diagnostics.push(diag("\{method_name} expects String argument"))
          None
        }
        None => None
      }
    }
    "toMap" => {
      if arguments.length() != 0 {
        diagnostics.push(
          diag("toMap expects 0 arguments, got \{arguments.length()}"),
        )
        return None
      }
      let entries : Array[ValueEntry] = []
      for m in receiver_members {
        if !is_invisible_member_name(m.name) {
          entries.push({ key: StringValue(m.name), value: m.value })
        }
      }
      Some(MapValue(entries))
    }
    "toDynamic" => {
      if arguments.length() != 0 {
        diagnostics.push(
          diag("toDynamic expects 0 arguments, got \{arguments.length()}"),
        )
        return None
      }
      let next : Array[ValueMember] = []
      for m in receiver_members {
        if m.name == hidden_member_name("__class") {
          continue
        }
        next.push(m)
      }
      Some(ObjectValue(next))
    }
    "length" => {
      if arguments.length() != 0 {
        diagnostics.push(
          diag("length expects 0 arguments, got \{arguments.length()}"),
        )
        return None
      }
      // PKL-152: Dynamic.length counts only bare-element members
      // (`@element$<offset>`). Properties and bracket-entries don't
      // count, matching Apple Pkl's gold (`new Dynamic { name = ... }.length
      // == 0`).
      let mut count = 0
      for m in receiver_members {
        if m.name.has_prefix("@element$") {
          count = count + 1
        }
      }
      Some(IntValue(count.to_int64()))
    }
    "toList" => {
      if arguments.length() != 0 {
        diagnostics.push(
          diag("toList expects 0 arguments, got \{arguments.length()}"),
        )
        return None
      }
      let out : Array[Value] = []
      for m in receiver_members {
        if m.name.has_prefix("@element$") {
          out.push(m.value)
        }
      }
      Some(ListValue(out))
    }
    "toTyped" => {
      if arguments.length() != 1 {
        diagnostics.push(
          diag("toTyped expects 1 argument, got \{arguments.length()}"),
        )
        return None
      }
      // PKL-152: Dynamic.toTyped(<class>) stamps the receiver's
      // visible members with the supplied class's tag. Drops bare
      // element members (a Typed receiver can't hold them).
      match
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
        Some(ObjectValue(class_mirror)) =>
          match lookup_member(class_mirror, "simpleName") {
            Some(StringValue(class_name)) => {
              let stamped : Array[ValueMember] = [
                {
                  name: hidden_member_name("__class"),
                  value: StringValue(class_name),
                  source: None,
                  annotations: [],
                },
              ]
              for m in receiver_members {
                if m.name.has_prefix("@element$") {
                  continue
                }
                if m.name == hidden_member_name("__class") {
                  continue
                }
                stamped.push(m)
              }
              Some(ObjectValue(stamped))
            }
            _ => {
              diagnostics.push(diag("toTyped expects a Class mirror argument"))
              None
            }
          }
        _ => {
          diagnostics.push(diag("toTyped expects a Class mirror argument"))
          None
        }
      }
    }
    _ => None
  }
}

///|
/// PKL-148: pkl:base Boolean method names.
fn is_bool_method_name(name : String) -> Bool {
  match name {
    "xor" | "implies" | "and" | "or" | "toString" => true
    _ => false
  }
}

///|
/// PKL-148: pkl:base Float method names. Mirrors `is_int_method_name`
/// but routes through `eval_float_method`.
fn is_float_method_name(name : String) -> Bool {
  match name {
    "toString"
    | "toFloat"
    | "toInt"
    | "toFixed"
    | "toDuration"
    | "toDataSize"
    | "isBetween"
    | "abs"
    | "round"
    | "floor"
    | "ceil"
    | "truncate"
    // No-arg property surface — callable as `(x).isNaN()` etc.
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign" => true
    _ => false
  }
}

///|
fn is_duration_unit_name(name : String) -> Bool {
  match name {
    "ns" | "us" | "ms" | "s" | "min" | "h" | "d" => true
    _ => false
  }
}

///|
fn is_datasize_unit_name(name : String) -> Bool {
  match name {
    "b"
    | "kb"
    | "kib"
    | "mb"
    | "mib"
    | "gb"
    | "gib"
    | "tb"
    | "tib"
    | "pb"
    | "pib" => true
    _ => false
  }
}

///|
/// Position of a Duration unit on the ns..d ladder. Returned values are
/// only used for ordering and adjacent-step lookups — the absolute
/// factor between two units is reconstructed by walking the ladder a
/// step at a time so the intermediate magnitude never overflows Int32
/// (a flat `min`-to-ns factor would already need ≥ 6e10).
fn duration_unit_level(unit : String) -> Int {
  match unit {
    "ns" => 0
    "us" => 1
    "ms" => 2
    "s" => 3
    "min" => 4
    "h" => 5
    "d" => 6
    _ => -1
  }
}

///|
/// Integer factor that scales one unit at `level` to the next-finer unit
/// at `level - 1` (e.g. `min` → `s` is 60, `s` → `ms` is 1000).
fn duration_step_factor(level : Int) -> Int {
  match level {
    1 => 1000 // us -> ns
    2 => 1000 // ms -> us
    3 => 1000 // s  -> ms
    4 => 60 // min -> s
    5 => 60 // h   -> min
    6 => 24 // d   -> h
    _ => 1
  }
}

///|
/// Factor from a DataSize unit to bytes. Stored as Double so `tb` / `pb`
/// and their binary siblings can participate in `toUnit` and comparisons
/// without overflowing MoonBit's Int.
fn datasize_byte_factor(unit : String) -> Double {
  match unit {
    "b" => 1.0
    "kb" => 1000.0
    "kib" => 1024.0
    "mb" => 1_000_000.0
    "mib" => 1_048_576.0
    "gb" => 1_000_000_000.0
    "gib" => 1_073_741_824.0
    "tb" => 1_000_000_000_000.0
    "tib" => 1_099_511_627_776.0
    "pb" => 1_000_000_000_000_000.0
    "pib" => 1_125_899_906_842_624.0
    _ => -1.0
  }
}

///|
fn is_datasize_binary_unit(unit : String) -> Bool {
  match unit {
    "b" | "kib" | "mib" | "gib" | "tib" | "pib" => true
    _ => false
  }
}

///|
fn is_datasize_decimal_unit(unit : String) -> Bool {
  match unit {
    "b" | "kb" | "mb" | "gb" | "tb" | "pb" => true
    _ => false
  }
}

///|
fn datasize_binary_unit_for(unit : String) -> String {
  match unit {
    "kb" | "kib" => "kib"
    "mb" | "mib" => "mib"
    "gb" | "gib" => "gib"
    "tb" | "tib" => "tib"
    "pb" | "pib" => "pib"
    _ => "b"
  }
}

///|
fn datasize_decimal_unit_for(unit : String) -> String {
  match unit {
    "kb" | "kib" => "kb"
    "mb" | "mib" => "mb"
    "gb" | "gib" => "gb"
    "tb" | "tib" => "tb"
    "pb" | "pib" => "pb"
    _ => "b"
  }
}

///|
/// Pick the unit with the smaller magnitude-per-unit so the resulting
/// arithmetic always rounds toward the finer side and stays expressible
/// in Int. For Duration this collapses to the ladder ordering (ns < us <
/// ms < s < min < h < d). For DataSize the comparison is by direct
/// byte factor (with the `tb`+ overflow ceiling caveat).
fn smaller_duration_unit(a : String, b : String) -> String {
  if duration_unit_level(a) <= duration_unit_level(b) {
    a
  } else {
    b
  }
}

///|
fn smaller_datasize_unit(a : String, b : String) -> String {
  let fa = datasize_byte_factor(a)
  let fb = datasize_byte_factor(b)
  if fa <= fb {
    a
  } else {
    b
  }
}

///|
/// Convert `magnitude` from `from_unit` to `to_unit` by walking one step
/// along the unit ladder at a time. Coarser→finer multiplies by each
/// step factor; finer→coarser divides (truncating). Stepping avoids the
/// overflow that a flat `factor_to_ns / factor_to_target` would hit on
/// `min`, `h`, or `d`.
fn duration_in_unit(
  magnitude : Double,
  from_unit : String,
  to_unit : String,
) -> Double {
  let from = duration_unit_level(from_unit)
  let to = duration_unit_level(to_unit)
  let mut m = magnitude
  let mut level = from
  while level > to {
    m = m * duration_step_factor(level).to_double()
    level = level - 1
  }
  while level < to {
    m = m / duration_step_factor(level + 1).to_double()
    level = level + 1
  }
  m
}

///|
fn duration_literal_text(magnitude : Double, unit : String) -> String {
  "\{magnitude}.\{unit}"
}

///|
fn left_pad_9_digits(value : Int64) -> String {
  let raw = value.to_string()
  let buf = StringBuilder::new()
  let mut i = raw.length()
  while i < 9 {
    buf.write_char('0')
    i = i + 1
  }
  buf.write_string(raw)
  buf.to_string()
}

///|
fn trim_trailing_zeroes(text : String) -> String {
  let mut end = text.length()
  while end > 0 && text[end - 1].to_int().unsafe_to_char() == '0' {
    end = end - 1
  }
  String::unsafe_substring(text, start=0, end~)
}

///|
fn duration_second_component_text(seconds_ns : Int64) -> String {
  let ns_per_second = 1_000_000_000L
  let seconds = seconds_ns / ns_per_second
  let fractional = seconds_ns % ns_per_second
  if fractional == 0L {
    seconds.to_string()
  } else {
    seconds.to_string() +
    "." +
    trim_trailing_zeroes(left_pad_9_digits(fractional))
  }
}

///|
fn duration_iso_string(
  magnitude : Double,
  unit : String,
  diagnostics : Array[Diagnostic],
) -> String? {
  if magnitude.is_nan() || magnitude.is_inf() {
    diagnostics.push(
      diag(
        "Cannot convert duration `\{duration_literal_text(magnitude, unit)}` to ISO 8601 duration.",
      ),
    )
    return None
  }
  let seconds = duration_in_unit(magnitude, unit, "s")
  let negative = seconds < 0.0
  let abs_seconds = if negative { 0.0 - seconds } else { seconds }
  if abs_seconds > 9_000_000_000_000_000_000.0 {
    if negative {
      return Some("-PT9223372036854775807H7M8S")
    }
    return Some("PT9223372036854775807H7M8S")
  }
  let total_ns = (duration_in_unit(abs_seconds, "s", "ns") + 0.5).to_int64()
  let ns_per_second = 1_000_000_000L
  let ns_per_minute = 60L * ns_per_second
  let ns_per_hour = 60L * ns_per_minute
  let hours = total_ns / ns_per_hour
  let after_hours = total_ns % ns_per_hour
  let minutes = after_hours / ns_per_minute
  let seconds_ns = after_hours % ns_per_minute
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  buf.write_string("PT")
  if hours > 0L {
    buf.write_string(hours.to_string())
    buf.write_char('H')
  }
  if minutes > 0L {
    buf.write_string(minutes.to_string())
    buf.write_char('M')
  }
  if seconds_ns > 0L || (hours == 0L && minutes == 0L) {
    buf.write_string(duration_second_component_text(seconds_ns))
    buf.write_char('S')
  }
  Some(buf.to_string())
}

///|
/// Convert `magnitude` from `from_unit` to `to_unit` for DataSize.
fn datasize_in_unit(
  magnitude : Double,
  from_unit : String,
  to_unit : String,
) -> Double {
  let from_f = datasize_byte_factor(from_unit)
  let to_f = datasize_byte_factor(to_unit)
  if from_f < 0.0 || to_f < 0.0 {
    return magnitude
  }
  if from_f == to_f {
    magnitude
  } else {
    magnitude * from_f / to_f
  }
}

///|
fn is_regex_method_name(name : String) -> Bool {
  match name {
    "matches" | "find" | "findAll" | "replace" | "replaceAll" => true
    _ => false
  }
}

///|
fn is_bytes_method_name(name : String) -> Bool {
  match name {
    "getOrNull" | "toList" => true
    _ => false
  }
}

///|
/// Build a `BytesValue` from a Listing of Int byte values. Each entry
/// must be in the 0..=255 range; an out-of-range or non-Int element
/// records a diagnostic and bails. The resulting `Bytes` is owned by
/// the new `BytesValue` and shared by reference for the lifetime of
/// the value (MoonBit `Bytes` is immutable).
fn build_bytes_from_int_listing(
  elements : Array[Value],
  diagnostics : Array[Diagnostic],
) -> Value? {
  let buf : Array[Byte] = []
  for element in elements {
    match element {
      IntValue(n) =>
        if n < 0 || n > 255 {
          diagnostics.push(diag("Bytes element \{n} is out of range 0..255"))
          return None
        } else {
          buf.push(n.to_byte())
        }
      _ => {
        diagnostics.push(
          diag(
            "Bytes element must be Int, got \{eval_value_type_name(element)}",
          ),
        )
        return None
      }
    }
  }
  Some(BytesValue(Bytes::from_array(buf)))
}

///|
fn eval_bytes_property(
  bytes : Bytes,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(bytes.length().to_int64()))
    "base64" => Some(StringValue(@base64.encode(bytes[:])))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Bytes`."),
      )
      None
    }
  }
}

///|
fn eval_bytes_method(
  bytes : Bytes,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "getOrNull" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          IntValue(index64) => {
            let index = index64.to_int()
            if index64 < 0L || index >= bytes.length() {
              Some(NullValue)
            } else {
              Some(IntValue(bytes[index].to_int().to_int64()))
            }
          }
          _ => {
            diagnostics.push(diag("Bytes.getOrNull expects an Int argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Bytes.getOrNull expects exactly one argument"))
        None
      }
    "toList" =>
      if arg_values.length() == 0 {
        let elements : Array[Value] = []
        for i = 0; i < bytes.length(); i = i + 1 {
          elements.push(IntValue(bytes[i].to_int().to_int64()))
        }
        Some(ListValue(elements))
      } else {
        diagnostics.push(diag("Bytes.toList takes no arguments"))
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Bytes`."),
      )
      None
    }
  }
}

///|
/// Compile `pattern` via `moonbitlang/regexp`. Returns `None` and pushes
/// a diagnostic on syntax errors so callers can bail out without
/// propagating a raise. Each call recompiles — the value model only
/// caches the source string so equality stays decidable on the surface.
fn compile_regex_pattern(
  pattern : String,
  diagnostics : Array[Diagnostic],
) -> @regexp.Regexp? {
  Some(@regexp.compile(pattern)) catch {
    err => {
      diagnostics.push(diag("invalid Regex pattern: \{err}"))
      None
    }
  }
}

///|
fn regex_matches_full(re : @regexp.Regexp, input : String) -> Bool {
  let m = re.execute(input)
  if !m.matched() {
    return false
  }
  // Full-input match: the captured slice must cover the entire input
  // with nothing before or after. `before` / `after` come back as views
  // so an empty view means the match anchored at both ends.
  m.before().length() == 0 && m.after().length() == 0
}

///|
fn regex_find_first(re : @regexp.Regexp, input : String) -> String? {
  match re.match_(input) {
    Some(m) =>
      match m.get(0) {
        Some(view) => Some(view.to_owned())
        None => None
      }
    None => None
  }
}

///|
/// Repeatedly execute the regex on the remaining suffix, collecting each
/// match's text. Advances by at least one character on zero-width
/// matches so the walk always terminates.
fn regex_find_all(re : @regexp.Regexp, input : String) -> Array[String] {
  let out : Array[String] = []
  let mut rest = input
  while rest.length() > 0 {
    match re.match_(rest) {
      Some(m) =>
        match m.get(0) {
          Some(view) => {
            let matched_text = view.to_owned()
            out.push(matched_text)
            let after = m.after().to_owned()
            if matched_text.length() == 0 && after.length() == rest.length() {
              // Zero-width match at the head of `rest`: skip one char to
              // avoid an infinite loop.
              if rest.length() <= 1 {
                rest = ""
              } else {
                rest = String::unsafe_substring(
                  rest,
                  start=1,
                  end=rest.length(),
                )
              }
            } else {
              rest = after
            }
          }
          None => break
        }
      None => break
    }
  }
  out
}

///|
fn regex_replace_first(
  re : @regexp.Regexp,
  input : String,
  replacement : String,
) -> String {
  match re.match_(input) {
    Some(m) => {
      let buf = StringBuilder::new()
      buf.write_string(m.before().to_owned())
      buf.write_string(replacement)
      buf.write_string(m.after().to_owned())
      buf.to_string()
    }
    None => input
  }
}

///|
fn regex_replace_all(
  re : @regexp.Regexp,
  input : String,
  replacement : String,
) -> String {
  let buf = StringBuilder::new()
  let mut rest = input
  while rest.length() > 0 {
    match re.match_(rest) {
      Some(m) =>
        match m.get(0) {
          Some(view) => {
            let matched_text = view.to_owned()
            buf.write_string(m.before().to_owned())
            buf.write_string(replacement)
            let after = m.after().to_owned()
            if matched_text.length() == 0 && after.length() == rest.length() {
              // Zero-width match: emit the first char verbatim then
              // continue, so substitution never spins.
              if rest.length() >= 1 {
                buf.write_string(String::unsafe_substring(rest, start=0, end=1))
              }
              if rest.length() <= 1 {
                rest = ""
              } else {
                rest = String::unsafe_substring(
                  rest,
                  start=1,
                  end=rest.length(),
                )
              }
            } else {
              rest = after
            }
          }
          None => {
            buf.write_string(rest)
            rest = ""
          }
        }
      None => {
        buf.write_string(rest)
        rest = ""
      }
    }
  }
  buf.to_string()
}

///|
fn eval_int_property(
  n : Int64,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "abs" => if n < 0L { Some(IntValue(0L - n)) } else { Some(IntValue(n)) }
    "isEven" => Some(BoolValue(n % 2L == 0L))
    "isOdd" => Some(BoolValue(n % 2L != 0L))
    // PKL-148: pkl:base Int zero-arg accessors.
    "isPositive" => Some(BoolValue(n >= 0L))
    "isNonZero" => Some(BoolValue(n != 0L))
    "isFinite" => Some(BoolValue(true))
    "isNaN" => Some(BoolValue(false))
    "isInfinite" => Some(BoolValue(false))
    "sign" =>
      if n > 0L {
        Some(IntValue(1L))
      } else if n < 0L {
        Some(IntValue(-1L))
      } else {
        Some(IntValue(0L))
      }
    "inv" => Some(IntValue(n.lnot()))
    // PKL-150: rounding / truncation are no-ops on Int.
    "ceil" | "floor" | "round" | "truncate" => Some(IntValue(n))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Int`."),
      )
      None
    }
  }
}

///|
/// Float counterpart of `eval_int_property`. Apple Pkl exposes the
/// same no-arg surface (`abs`, `isPositive`, `isNaN`, …) on Float.
fn eval_float_property(
  d : Double,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "abs" => Some(FloatValue(if d < 0.0 { 0.0 - d } else { d.abs() }))
    "ceil" => Some(FloatValue(d.ceil()))
    "floor" => Some(FloatValue(d.floor()))
    "isPositive" => Some(BoolValue(d >= 0.0))
    "isNonZero" => Some(BoolValue(d != 0.0))
    "isFinite" => Some(BoolValue(!d.is_nan() && !d.is_inf()))
    "isNaN" => Some(BoolValue(d.is_nan()))
    "isInfinite" => Some(BoolValue(d.is_inf()))
    "sign" =>
      if d.is_nan() {
        Some(FloatValue(d))
      } else if is_negative_zero(d) {
        Some(FloatValue(d))
      } else if d > 0.0 {
        Some(FloatValue(1.0))
      } else if d < 0.0 {
        Some(FloatValue(-1.0))
      } else {
        Some(FloatValue(0.0))
      }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Float`."),
      )
      None
    }
  }
}

///|
fn is_float_property_name(name : String) -> Bool {
  match name {
    "abs"
    | "ceil"
    | "floor"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign" => true
    _ => false
  }
}

///|
fn eval_duration_property(
  magnitude : Double,
  unit : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "value" => Some(magnitude_as_value(magnitude))
    "isoString" =>
      match duration_iso_string(magnitude, unit, diagnostics) {
        Some(text) => Some(StringValue(text))
        None => None
      }
    "unit" => Some(StringValue(unit))
    "isPositive" => Some(BoolValue(magnitude >= 0.0))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Duration`."),
      )
      None
    }
  }
}

///|
fn eval_datasize_property(
  magnitude : Double,
  unit : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "value" => Some(magnitude_as_value(magnitude))
    "unit" => Some(StringValue(unit))
    "isPositive" => Some(BoolValue(magnitude >= 0.0))
    "isBinaryUnit" => Some(BoolValue(is_datasize_binary_unit(unit)))
    "isDecimalUnit" => Some(BoolValue(is_datasize_decimal_unit(unit)))
    "toBinaryUnit" => {
      let target = datasize_binary_unit_for(unit)
      Some(DataSizeValue(datasize_in_unit(magnitude, unit, target), target))
    }
    "toDecimalUnit" => {
      let target = datasize_decimal_unit_for(unit)
      Some(DataSizeValue(datasize_in_unit(magnitude, unit, target), target))
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `DataSize`."),
      )
      None
    }
  }
}

///|
/// PKL-121: project a magnitude back to an `IntValue` when it has no
/// fractional component and fits in `Int`, otherwise expose it as
/// `FloatValue`. Keeps the common Int-magnitude path observationally
/// identical to the pre-PKL-121 behaviour (`.value` on `5.min` is
/// still `5`, not `5.0`).
fn magnitude_as_value(magnitude : Double) -> Value {
  let rounded = magnitude.to_int64()
  if rounded.to_double() == magnitude {
    IntValue(rounded)
  } else {
    FloatValue(magnitude)
  }
}

///|
fn int_to_string_radix(n : Int64, radix : Int) -> String {
  if n == 0L {
    return "0"
  }
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let negative = n < 0L
  let mut value = if negative { 0L - n } else { n }
  let radix64 = radix.to_int64()
  let chars : Array[Char] = []
  while value > 0L {
    let d = (value % radix64).to_int()
    chars.push(digits.unsafe_get(d).to_int().unsafe_to_char())
    value = value / radix64
  }
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  let mut i = chars.length() - 1
  while i >= 0 {
    buf.write_char(chars[i])
    i = i - 1
  }
  buf.to_string()
}

///|
fn eval_int_method(
  n : Int64,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        Some(StringValue("\{n}"))
      } else if arg_values.length() == 1 {
        match arg_values[0] {
          IntValue(radix) =>
            if radix < 2L || radix > 36L {
              diagnostics.push(
                diag(
                  "Int.toString radix must be between 2 and 36, got \{radix}",
                ),
              )
              None
            } else {
              Some(StringValue(int_to_string_radix(n, radix.to_int())))
            }
          _ => {
            diagnostics.push(diag("Int.toString radix must be Int"))
            None
          }
        }
      } else {
        diagnostics.push(
          diag(
            "Int.toString expects 0 or 1 arguments, got \{arg_values.length()}",
          ),
        )
        None
      }
    "toChar" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Int.toChar expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      if n < 0L || n > 0x10FFFFL {
        // PKL-150: match Apple Pkl's wording — "Decimal `N` is not a
        // valid Unicode code point." with a comma-grouped magnitude.
        diagnostics.push(
          diag(
            "Decimal `\{format_int_with_commas(n)}` is not a valid Unicode code point.",
          ),
        )
        return None
      }
      let buf = StringBuilder::new()
      buf.write_char(n.to_int().unsafe_to_char())
      Some(StringValue(buf.to_string()))
    }
    // PKL-148b: Int.isBetween(lower, upper) — inclusive range check.
    "isBetween" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Int.isBetween expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let lower = match arg_values[0] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Int.isBetween expects Number arguments"))
          return None
        }
      }
      let upper = match arg_values[1] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Int.isBetween expects Number arguments"))
          return None
        }
      }
      let v = n.to_double()
      Some(BoolValue(v >= lower && v <= upper))
    }
    // PKL-148b: Int.toFloat() — widens to Float (no precision loss).
    "toFloat" =>
      if arg_values.length() == 0 {
        Some(FloatValue(n.to_double()))
      } else {
        diagnostics.push(diag("Int.toFloat takes no arguments"))
        None
      }
    // PKL-150: Int.toInt() — Apple Pkl projects it for symmetry with
    // Float.toInt(); on Int it's the identity.
    "toInt" =>
      if arg_values.length() == 0 {
        Some(IntValue(n))
      } else {
        diagnostics.push(diag("Int.toInt takes no arguments"))
        None
      }
    // PKL-150: Int.toRadixString(radix) — base 2-36, raises out of
    // range. Negative inputs render with a leading "-".
    "toRadixString" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Int.toRadixString expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(radix) =>
          if radix < 2L || radix > 36L {
            // PKL-150: match Apple Pkl's wording — the parameter is
            // declared `Int(this.isBetween(2, 36))` so the violation
            // surfaces through the constraint message verbatim.
            diagnostics.push(
              diag(
                "Type constraint `this.isBetween(2, 36)` violated. Value: \{radix}",
              ),
            )
            None
          } else {
            Some(StringValue(int_to_string_radix(n, radix.to_int())))
          }
        _ => {
          diagnostics.push(diag("Int.toRadixString expects Int argument"))
          None
        }
      }
    }
    // PKL-150: Int.toFixed(decimals) — fixed-point string with the
    // exact requested number of trailing zeros. 0..20 is the Apple Pkl
    // accepted range; outside raises.
    "toFixed" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Int.toFixed expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(decimals) =>
          if decimals < 0L || decimals > 20L {
            // PKL-150: Apple Pkl's `toFixed(decimals: Int(this.isBetween(0, 20)))`
            // surfaces a constraint-violation message verbatim.
            diagnostics.push(
              diag(
                "Type constraint `this.isBetween(0, 20)` violated. Value: \{decimals}",
              ),
            )
            None
          } else {
            Some(StringValue(format_fixed_decimal(n, decimals.to_int())))
          }
        _ => {
          diagnostics.push(diag("Int.toFixed expects Int argument"))
          None
        }
      }
    }
    // PKL-150: Int.toDuration(unit) / .toDataSize(unit) — wraps the
    // magnitude as a Duration / DataSize with the supplied unit.
    "toDuration" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Int.toDuration expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_duration_unit_name(unit) {
            Some(DurationValue(n.to_double(), unit))
          } else {
            diagnostics.push(diag("Invalid Duration unit: \"\{unit}\"."))
            None
          }
        _ => {
          diagnostics.push(diag("Int.toDuration expects String argument"))
          None
        }
      }
    }
    "toDataSize" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Int.toDataSize expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_datasize_unit_name(unit) {
            Some(DataSizeValue(n.to_double(), unit))
          } else {
            diagnostics.push(diag("Invalid DataSize unit: \"\{unit}\"."))
            None
          }
        _ => {
          diagnostics.push(diag("Int.toDataSize expects String argument"))
          None
        }
      }
    }
    // PKL-150: bitwise binary Int methods (Apple Pkl spells `shl` /
    // `shr` / `ushr` / `and` / `or` / `xor` as methods, not operators).
    "shl" | "shr" | "ushr" | "and" | "or" | "xor" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Int.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(m) => {
          // PKL-150: shift count is Int (i32). Bitwise ops are Int64
          // and / or / xor.
          let m_int = m.to_int()
          match method_name {
            "shl" => Some(IntValue(n << m_int))
            "shr" => Some(IntValue(n >> m_int))
            "ushr" =>
              Some(
                IntValue(
                  (n.reinterpret_as_uint64() >> m_int).reinterpret_as_int64(),
                ),
              )
            "and" => Some(IntValue(n.land(m)))
            "or" => Some(IntValue(n.lor(m)))
            "xor" => Some(IntValue(n.lxor(m)))
            _ => None
          }
        }
        _ => {
          diagnostics.push(diag("Int.\{method_name} expects Int argument"))
          None
        }
      }
    }
    // No-arg property surface accessible as `(N).abs()` / `.isEven()`
    // / `.sign()` / etc.
    "abs"
    | "isEven"
    | "isOdd"
    | "isPositive"
    | "isNonZero"
    | "isFinite"
    | "isNaN"
    | "isInfinite"
    | "sign"
    | "inv"
    | "ceil"
    | "floor"
    | "round"
    | "truncate" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Int.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_int_property(n, method_name, diagnostics)
      }
    _ => None
  }
}

///|
/// PKL-150: format `n` as a fixed-point string with exactly
/// `decimals` digits after the dot. `decimals == 0` omits the dot
/// entirely. Negative inputs get a leading "-".
fn format_fixed_decimal(n : Int64, decimals : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("\{n}")
  if decimals > 0 {
    buf.write_char('.')
    for _ in 0..<decimals {
      buf.write_char('0')
    }
  }
  buf.to_string()
}

///|
fn pow10_int64(decimals : Int) -> Int64 {
  let mut result = 1L
  for _ in 0..<decimals {
    result = result * 10L
  }
  result
}

///|
fn write_left_padded_int64(
  buf : StringBuilder,
  value : Int64,
  width : Int,
) -> Unit {
  let raw = value.to_string()
  let mut i = raw.length()
  while i < width {
    buf.write_char('0')
    i = i + 1
  }
  buf.write_string(raw)
}

///|
fn is_negative_zero(d : Double) -> Bool {
  d.reinterpret_as_uint64() == 0x8000000000000000UL
}

///|
fn negate_float(d : Double) -> Double {
  if d == 0.0 {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    0.0 - d
  }
}

///|
fn decimal_digit_at(text : String, index : Int) -> Int {
  text.unsafe_get(index).to_int() - '0'.to_int()
}

///|
fn increment_decimal_string(text : String) -> String {
  if text.length() == 0 {
    return "1"
  }
  let digits : Array[Int] = []
  for i in 0..<text.length() {
    digits.push(decimal_digit_at(text, i))
  }
  let mut carry = 1
  let mut i = digits.length() - 1
  while i >= 0 && carry > 0 {
    let next = digits[i] + carry
    if next >= 10 {
      digits[i] = 0
      carry = 1
    } else {
      digits[i] = next
      carry = 0
    }
    i = i - 1
  }
  let buf = StringBuilder::new()
  if carry > 0 {
    buf.write_char('1')
  }
  for digit in digits {
    buf.write_char("0123456789".unsafe_get(digit).to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
fn split_decimal_text(text : String) -> (String, String) {
  match text.find(".") {
    Some(index) =>
      (
        String::unsafe_substring(text, start=0, end=index),
        String::unsafe_substring(text, start=index + 1, end=text.length()),
      )
    None => (text, "")
  }
}

///|
fn format_fixed_decimal_text(
  whole_text : String,
  fraction_text : String,
  decimals : Int,
) -> String {
  let digits : Array[Int] = []
  for i in 0..<decimals {
    if i < fraction_text.length() {
      digits.push(decimal_digit_at(fraction_text, i))
    } else {
      digits.push(0)
    }
  }
  let next_digit = if decimals < fraction_text.length() {
    decimal_digit_at(fraction_text, decimals)
  } else {
    0
  }
  let mut whole = whole_text
  if next_digit >= 5 {
    let mut carry = 1
    let mut i = digits.length() - 1
    while i >= 0 && carry > 0 {
      let next = digits[i] + carry
      if next >= 10 {
        digits[i] = 0
        carry = 1
      } else {
        digits[i] = next
        carry = 0
      }
      i = i - 1
    }
    if carry > 0 {
      whole = increment_decimal_string(whole)
    }
  }
  let buf = StringBuilder::new()
  buf.write_string(whole)
  if decimals > 0 {
    buf.write_char('.')
    for digit in digits {
      buf.write_char("0123456789".unsafe_get(digit).to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
fn format_fixed_float_slow(
  d : Double,
  decimals : Int,
  negative : Bool,
) -> String {
  let scale = @math.pow(10.0, decimals.to_double())
  let abs_value = if negative { 0.0 - d } else { d }
  let rounded = (abs_value * scale + 0.5).floor() / scale
  let whole = rounded.floor()
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  buf.write_string(whole.to_int64().to_string())
  if decimals > 0 {
    buf.write_char('.')
    let mut fraction = rounded - whole
    for _ in 0..<decimals {
      fraction = fraction * 10.0
      let digit = fraction.floor().to_int()
      buf.write_char("0123456789".unsafe_get(digit).to_int().unsafe_to_char())
      fraction = fraction - digit.to_double()
    }
  }
  buf.to_string()
}

///|
fn format_fixed_float(d : Double, decimals : Int) -> String {
  if d.is_nan() || d.is_inf() {
    return render_float_text(d)
  }
  let negative = d < 0.0 || is_negative_zero(d)
  let abs_value = if negative { 0.0 - d } else { d }
  let text = render_float_text(abs_value)
  if text.find("e") is None && text.find("E") is None {
    let (whole, fraction) = split_decimal_text(text)
    let fixed = format_fixed_decimal_text(whole, fraction, decimals)
    return if negative { "-\{fixed}" } else { fixed }
  }
  if decimals > 18 {
    return format_fixed_float_slow(d, decimals, negative)
  }
  let scale = pow10_int64(decimals)
  if abs_value > 9_000_000_000_000_000_000.0 / scale.to_double() {
    return format_fixed_float_slow(d, decimals, negative)
  }
  let scaled = (abs_value * scale.to_double() + 0.5).floor().to_int64()
  let whole = scaled / scale
  let fraction = scaled % scale
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  buf.write_string(whole.to_string())
  if decimals > 0 {
    buf.write_char('.')
    write_left_padded_int64(buf, fraction, decimals)
  }
  buf.to_string()
}

///|
fn render_float_to_int_error_text(d : Double) -> String {
  let text = render_float_text(d)
  match text {
    "9223372036854778000.0" => "9.223372036854776E18"
    "-9223372036854778000.0" => "-9.223372036854776E18"
    _ => text
  }
}

///|
/// PKL-150: format an Int with Apple Pkl-style "," thousand-grouping
/// (e.g. `1,114,112`). Negative sign is preserved.
fn format_int_with_commas(n : Int64) -> String {
  let raw_signed = "\{n}"
  let negative = raw_signed.has_prefix("-")
  let raw = if negative {
    String::unsafe_substring(raw_signed, start=1, end=raw_signed.length())
  } else {
    raw_signed
  }
  if raw.length() <= 3 {
    return if negative { "-\{raw}" } else { raw }
  }
  let buf = StringBuilder::new()
  let len = raw.length()
  let first_group = len % 3
  let mut i = 0
  if first_group > 0 {
    buf.write_string(String::unsafe_substring(raw, start=0, end=first_group))
    i = first_group
  }
  while i < len {
    if buf.to_string().length() > 0 {
      buf.write_char(',')
    }
    buf.write_string(String::unsafe_substring(raw, start=i, end=i + 3))
    i = i + 3
  }
  if negative {
    "-" + buf.to_string()
  } else {
    buf.to_string()
  }
}

///|
/// PKL-148: pkl:base Bool method surface. Apple Pkl projects logical
/// operators (`xor` / `implies`) and the keyword-named pair (`and` /
/// `or`) as instance methods; `toString` is universal. The methods
/// take a single Boolean argument except `toString` (arity 0) and the
/// unary `not` (arity 0).
fn eval_bool_method(
  b : Bool,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        if b {
          Some(StringValue("true"))
        } else {
          Some(StringValue("false"))
        }
      } else {
        diagnostics.push(diag("Bool.toString takes no arguments"))
        None
      }
    "xor" | "implies" | "and" | "or" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          BoolValue(other) =>
            match method_name {
              "xor" => Some(BoolValue(b != other))
              "implies" => Some(BoolValue(!b || other))
              "and" => Some(BoolValue(b && other))
              "or" => Some(BoolValue(b || other))
              _ => None
            }
          other => {
            diagnostics.push(
              diag(
                "Expected value of type `Boolean`, but got type `\{eval_value_type_name(other)}`. Value: \{render_pcf_value_inline(other)}",
              ),
            )
            None
          }
        }
      } else {
        diagnostics.push(
          diag("Bool.\{method_name} expects exactly one argument"),
        )
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Boolean`."),
      )
      None
    }
  }
}

///|
/// PKL-148: pkl:base Float method surface. Most Float operations
/// share the Int name surface; the runtime intercepts a small set
/// of float-specific names (`isNaN`, `isFinite`, `isInfinite`).
fn eval_float_method(
  d : Double,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "toString" =>
      if arg_values.length() == 0 {
        Some(StringValue(render_float_text(d)))
      } else {
        diagnostics.push(diag("Float.toString takes no arguments"))
        None
      }
    "toFloat" =>
      if arg_values.length() == 0 {
        Some(FloatValue(d))
      } else {
        diagnostics.push(diag("Float.toFloat takes no arguments"))
        None
      }
    "toInt" =>
      if arg_values.length() == 0 {
        if d.is_nan() || d.is_inf() {
          diagnostics.push(
            diag(
              "Cannot convert non-finite Float `\{render_float_text(d)}` to Int.",
            ),
          )
          None
        } else if d >= 9_223_372_036_854_776_000.0 ||
          d < -9_223_372_036_854_776_000.0 {
          diagnostics.push(
            diag(
              "Cannot convert Float `\{render_float_to_int_error_text(d)}` to Int because it is too large.",
            ),
          )
          None
        } else {
          Some(IntValue(d.to_int64()))
        }
      } else {
        diagnostics.push(diag("Float.toInt takes no arguments"))
        None
      }
    "toFixed" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Float.toFixed expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(decimals) =>
          if decimals < 0L || decimals > 20L {
            diagnostics.push(
              diag(
                "Type constraint `this.isBetween(0, 20)` violated. Value: \{decimals}",
              ),
            )
            None
          } else {
            Some(StringValue(format_fixed_float(d, decimals.to_int())))
          }
        _ => {
          diagnostics.push(diag("Float.toFixed expects Int argument"))
          None
        }
      }
    }
    "isBetween" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Float.isBetween expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let lower = match arg_values[0] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Float.isBetween expects Number arguments"))
          return None
        }
      }
      let upper = match arg_values[1] {
        IntValue(v) => v.to_double()
        FloatValue(v) => v
        _ => {
          diagnostics.push(diag("Float.isBetween expects Number arguments"))
          return None
        }
      }
      Some(BoolValue(d >= lower && d <= upper))
    }
    "toDuration" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Float.toDuration expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_duration_unit_name(unit) {
            Some(DurationValue(d, unit))
          } else {
            diagnostics.push(diag("Invalid Duration unit: \"\{unit}\"."))
            None
          }
        _ => {
          diagnostics.push(diag("Float.toDuration expects String argument"))
          None
        }
      }
    }
    "toDataSize" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Float.toDataSize expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_datasize_unit_name(unit) {
            Some(DataSizeValue(d, unit))
          } else {
            diagnostics.push(diag("Invalid DataSize unit: \"\{unit}\"."))
            None
          }
        _ => {
          diagnostics.push(diag("Float.toDataSize expects String argument"))
          None
        }
      }
    }
    "abs" =>
      if arg_values.length() == 0 {
        Some(FloatValue(if d < 0.0 { -d } else { d }))
      } else {
        diagnostics.push(diag("Float.abs takes no arguments"))
        None
      }
    "round" =>
      if arg_values.length() == 0 {
        // Apple Pkl keeps Float identity for Float.round().
        if is_negative_zero(d) {
          Some(FloatValue(d))
        } else {
          Some(FloatValue(d.round()))
        }
      } else {
        diagnostics.push(diag("Float.round takes no arguments"))
        None
      }
    "floor" =>
      if arg_values.length() == 0 {
        Some(FloatValue(d.floor()))
      } else {
        diagnostics.push(diag("Float.floor takes no arguments"))
        None
      }
    "ceil" =>
      if arg_values.length() == 0 {
        Some(FloatValue(d.ceil()))
      } else {
        diagnostics.push(diag("Float.ceil takes no arguments"))
        None
      }
    "truncate" =>
      if arg_values.length() == 0 {
        if d.is_nan() || d.is_inf() {
          Some(FloatValue(d))
        } else if d < 0.0 {
          Some(FloatValue(d.ceil()))
        } else if is_negative_zero(d) {
          Some(FloatValue(d))
        } else {
          Some(FloatValue(d.floor()))
        }
      } else {
        diagnostics.push(diag("Float.truncate takes no arguments"))
        None
      }
    "isPositive" | "isNonZero" | "isFinite" | "isNaN" | "isInfinite" | "sign" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Float.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_float_property(d, method_name, diagnostics)
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Float`."),
      )
      None
    }
  }
}

///|
fn eval_duration_method(
  magnitude : Double,
  unit : String,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "isBetween" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Duration.isBetween expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (DurationValue(lower, lower_unit), DurationValue(upper, upper_unit)) => {
          let value_in_ns = duration_in_unit(magnitude, unit, "ns")
          let lower_in_ns = duration_in_unit(lower, lower_unit, "ns")
          let upper_in_ns = duration_in_unit(upper, upper_unit, "ns")
          Some(
            BoolValue(value_in_ns >= lower_in_ns && value_in_ns <= upper_in_ns),
          )
        }
        _ => {
          diagnostics.push(
            diag("Duration.isBetween expects Duration arguments"),
          )
          None
        }
      }
    }
    "toUnit" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(target) =>
            if is_duration_unit_name(target) {
              Some(
                DurationValue(duration_in_unit(magnitude, unit, target), target),
              )
            } else {
              diagnostics.push(
                diag(
                  "Expected value of type `\"ns\"|\"us\"|\"ms\"|\"s\"|\"min\"|\"h\"|\"d\"`, but got `\"\{target}\"`.",
                ),
              )
              None
            }
          _ => {
            diagnostics.push(diag("Duration.toUnit expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Duration.toUnit expects exactly one argument"))
        None
      }
    _ => {
      diagnostics.push(
        diag(
          "Cannot find method `\{method_name}` in object of type `Duration`.",
        ),
      )
      None
    }
  }
}

///|
fn eval_datasize_method(
  magnitude : Double,
  unit : String,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  match method_name {
    "isBetween" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "DataSize.isBetween expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (DataSizeValue(lower, lower_unit), DataSizeValue(upper, upper_unit)) => {
          let value_in_bytes = datasize_in_unit(magnitude, unit, "b")
          let lower_in_bytes = datasize_in_unit(lower, lower_unit, "b")
          let upper_in_bytes = datasize_in_unit(upper, upper_unit, "b")
          Some(
            BoolValue(
              value_in_bytes >= lower_in_bytes &&
              value_in_bytes <= upper_in_bytes,
            ),
          )
        }
        _ => {
          diagnostics.push(
            diag("DataSize.isBetween expects DataSize arguments"),
          )
          None
        }
      }
    }
    "toUnit" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(target) =>
            if is_datasize_unit_name(target) {
              Some(
                DataSizeValue(datasize_in_unit(magnitude, unit, target), target),
              )
            } else {
              diagnostics.push(
                diag(
                  "Expected value of type `\"b\"|\"kb\"|\"kib\"|\"mb\"|\"mib\"|\"gb\"|\"gib\"|\"tb\"|\"tib\"|\"pb\"|\"pib\"`, but got `\"\{target}\"`.",
                ),
              )
              None
            }
          _ => {
            diagnostics.push(diag("DataSize.toUnit expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("DataSize.toUnit expects exactly one argument"))
        None
      }
    "toBinaryUnit" | "toDecimalUnit" =>
      if arg_values.length() == 0 {
        let target = if method_name == "toBinaryUnit" {
          datasize_binary_unit_for(unit)
        } else {
          datasize_decimal_unit_for(unit)
        }
        Some(DataSizeValue(datasize_in_unit(magnitude, unit, target), target))
      } else {
        diagnostics.push(diag("DataSize.\{method_name} takes no arguments"))
        None
      }
    _ => {
      diagnostics.push(
        diag(
          "Cannot find method `\{method_name}` in object of type `DataSize`.",
        ),
      )
      None
    }
  }
}

///|
fn eval_regex_property(
  pattern : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "pattern" => Some(StringValue(pattern))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Regex`."),
      )
      None
    }
  }
}

///|
fn eval_regex_method(
  pattern : String,
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
  let arg_values : Array[Value] = []
  let mut ok = true
  for argument in arguments {
    match
      eval_expr_with_bindings(
        argument, bindings, env, class_env, cache, stack, declarations, diagnostics,
        resolve_import,
      ) {
      Some(v) => arg_values.push(v)
      None => ok = false
    }
  }
  if !ok {
    return None
  }
  let re = match compile_regex_pattern(pattern, diagnostics) {
    Some(r) => r
    None => return None
  }
  match method_name {
    "matches" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) => Some(BoolValue(regex_matches_full(re, input)))
          _ => {
            diagnostics.push(diag("Regex.matches expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.matches expects exactly one argument"))
        None
      }
    "find" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) =>
            match regex_find_first(re, input) {
              Some(found) => Some(StringValue(found))
              None => Some(NullValue)
            }
          _ => {
            diagnostics.push(diag("Regex.find expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.find expects exactly one argument"))
        None
      }
    "findAll" =>
      if arg_values.length() == 1 {
        match arg_values[0] {
          StringValue(input) => {
            let matches = regex_find_all(re, input)
            let elements : Array[Value] = []
            for s in matches {
              elements.push(StringValue(s))
            }
            Some(ListingValue(elements))
          }
          _ => {
            diagnostics.push(diag("Regex.findAll expects a String argument"))
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.findAll expects exactly one argument"))
        None
      }
    "replace" =>
      if arg_values.length() == 2 {
        match (arg_values[0], arg_values[1]) {
          (StringValue(input), StringValue(repl)) =>
            Some(StringValue(regex_replace_first(re, input, repl)))
          _ => {
            diagnostics.push(
              diag("Regex.replace expects (String, String) arguments"),
            )
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.replace expects exactly two arguments"))
        None
      }
    "replaceAll" =>
      if arg_values.length() == 2 {
        match (arg_values[0], arg_values[1]) {
          (StringValue(input), StringValue(repl)) =>
            Some(StringValue(regex_replace_all(re, input, repl)))
          _ => {
            diagnostics.push(
              diag("Regex.replaceAll expects (String, String) arguments"),
            )
            None
          }
        }
      } else {
        diagnostics.push(diag("Regex.replaceAll expects exactly two arguments"))
        None
      }
    _ => {
      diagnostics.push(
        diag("Cannot find method `\{method_name}` in object of type `Regex`."),
      )
      None
    }
  }
}
