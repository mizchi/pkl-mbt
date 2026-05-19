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
        arguments[0], bindings, env, class_env, cache, stack, declarations,
        diagnostics, resolve_import,
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
          arguments[0], bindings, env, class_env, cache, stack, declarations,
          diagnostics, resolve_import,
        ) {
        Some(ObjectValue(class_mirror)) =>
          match lookup_member(class_mirror, "simpleName") {
            Some(StringValue(class_name)) => {
              let stamped : Array[ValueMember] = [
                {
                  name: hidden_member_name("__class"),
                  value: StringValue(class_name),
                  source: None,
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
              diagnostics.push(
                diag("toTyped expects a Class mirror argument"),
              )
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
    | "abs"
    | "round"
    | "floor"
    | "ceil"
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
/// Factor from a DataSize unit to bytes. Values up to `gib` (≈ 1.07e9)
/// fit in Int32; `tb` and beyond overflow and return -1 so callers can
/// detect the gap and skip mixed-unit arithmetic. This is the
/// documented PKL-082 ceiling — promoting larger units to lossless
/// arithmetic needs Int64 in the value model.
fn datasize_byte_factor(unit : String) -> Int {
  match unit {
    "b" => 1
    "kb" => 1000
    "kib" => 1024
    "mb" => 1_000_000
    "mib" => 1_048_576
    "gb" => 1_000_000_000
    "gib" => 1_073_741_824
    "tb" | "tib" | "pb" | "pib" => -1
    _ => -1
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
  if fa < 0 || fb < 0 {
    // tb / tib / pb / pib do not participate in mixed-unit arithmetic in
    // this slice; pick `a` deterministically so callers see a stable
    // result without a panic. Mixed-unit ops involving these will hit
    // the overflow-guarded path below.
    a
  } else if fa <= fb {
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
/// Convert `magnitude` from `from_unit` to `to_unit` for DataSize. Both
/// units must fit in the Int32 byte-factor range (`b`..`gib`); callers
/// that mix `tb`+ units guard against the -1 sentinel from
/// `datasize_byte_factor` first.
fn datasize_in_unit(
  magnitude : Double,
  from_unit : String,
  to_unit : String,
) -> Double {
  let from_f = datasize_byte_factor(from_unit)
  let to_f = datasize_byte_factor(to_unit)
  if from_f < 0 || to_f < 0 {
    return magnitude
  }
  if from_f == to_f {
    magnitude
  } else if from_f > to_f {
    magnitude * (from_f / to_f).to_double()
  } else {
    magnitude / (to_f / from_f).to_double()
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
    "abs" => Some(FloatValue(if d < 0.0 { -d } else { d }))
    "isPositive" => Some(BoolValue(d >= 0.0))
    "isNonZero" => Some(BoolValue(d != 0.0))
    "isFinite" => Some(BoolValue(!d.is_nan() && !d.is_inf()))
    "isNaN" => Some(BoolValue(d.is_nan()))
    "isInfinite" => Some(BoolValue(d.is_inf()))
    "sign" =>
      if d > 0.0 {
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
          diag(
            "Int.toFixed expects 1 argument, got \{arg_values.length()}",
          ),
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
          diag(
            "Int.toDuration expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_duration_unit_name(unit) {
            Some(DurationValue(n.to_double(), unit))
          } else {
            diagnostics.push(
              diag("Invalid Duration unit: \"\{unit}\"."),
            )
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
          diag(
            "Int.toDataSize expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        StringValue(unit) =>
          if is_datasize_unit_name(unit) {
            Some(DataSizeValue(n.to_double(), unit))
          } else {
            diagnostics.push(
              diag("Invalid DataSize unit: \"\{unit}\"."),
            )
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
/// PKL-150: format an Int with Apple Pkl-style "," thousand-grouping
/// (e.g. `1,114,112`). Negative sign is preserved.
fn format_int_with_commas(n : Int64) -> String {
  let negative = n < 0L
  let magnitude = if negative { 0L - n } else { n }
  let raw = "\{magnitude}"
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
    "abs" =>
      if arg_values.length() == 0 {
        Some(FloatValue(if d < 0.0 { -d } else { d }))
      } else {
        diagnostics.push(diag("Float.abs takes no arguments"))
        None
      }
    "round" =>
      if arg_values.length() == 0 {
        // Round half to even (Apple Pkl's default per IEEE 754 round-to-nearest).
        let r = d.round()
        Some(IntValue(r.to_int64()))
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
                  "Duration.toUnit expects one of ns/us/ms/s/min/h/d, got \{target}",
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
                  "DataSize.toUnit expects one of b/kb/kib/mb/mib/gb/gib/tb/tib/pb/pib, got \{target}",
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
