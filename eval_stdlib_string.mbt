///|
fn eval_string_property(
  s : String,
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(s.length()))
    "isEmpty" => Some(BoolValue(s.length() == 0))
    // PKL-148: pkl:base String zero-arg accessors. `isBlank` checks
    // for whitespace-only; `reverse` reverses code-points (not UTF-16
    // units) so surrogate pairs survive.
    "isNotEmpty" => Some(BoolValue(s.length() != 0))
    "isBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(blank))
    }
    "isNotBlank" => {
      let mut blank = true
      for c in s.iter() {
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          blank = false
          break
        }
      }
      Some(BoolValue(!blank))
    }
    "base64" =>
      // PKL-148: encode the string's UTF-8 bytes as standard base64.
      // Apple Pkl projects this as a property, not a method.
      Some(StringValue(@base64.encode(@utf8.encode(s))))
    "reverse" => {
      let chars : Array[Char] = []
      for c in s.iter() {
        chars.push(c)
      }
      let buf = StringBuilder::new()
      let mut i = chars.length() - 1
      while i >= 0 {
        buf.write_char(chars[i])
        i = i - 1
      }
      Some(StringValue(buf.to_string()))
    }
    // PKL-122: surrogate-pair aware properties. `length` stays
    // UTF-16 code units for compat with the existing fixture
    // baseline; `codePointCount` / `codePoints` / `chars` are the
    // new Unicode-correct view. MoonBit's `String::iter` already
    // yields full code-point `Char` values, so a single pass walks
    // surrogates correctly.
    "codePointCount" => Some(IntValue(s.char_length()))
    "codePoints" => {
      let points : Array[Value] = []
      for c in s.iter() {
        points.push(IntValue(c.to_int()))
      }
      Some(ListingValue(points))
    }
    "chars" => {
      let chars : Array[Value] = []
      for c in s.iter() {
        chars.push(StringValue(String::from_array([c][:])))
      }
      Some(ListingValue(chars))
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `String`."),
      )
      None
    }
  }
}

///|
fn pad_string(s : String, width : Int, pad : String, at_start : Bool) -> String {
  let current = s.length()
  if current >= width || pad.length() == 0 {
    return s
  }
  let buf = StringBuilder::new()
  if at_start {
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
    buf.write_string(s)
  } else {
    buf.write_string(s)
    let mut remaining = width - current
    while remaining > 0 {
      let chunk = if remaining >= pad.length() {
        pad
      } else {
        String::unsafe_substring(pad, start=0, end=remaining)
      }
      buf.write_string(chunk)
      remaining = remaining - chunk.length()
    }
  }
  buf.to_string()
}

///|
fn eval_string_method(
  s : String,
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
    "toUpperCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toUpperCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_upper()))
    }
    "toBytes" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("String.toBytes expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(BytesValue(@utf8.encode(s[:])))
    }
    // PKL-122: code-point index lookup. `i` indexes the Unicode
    // code-point stream (surrogate-pair aware), not the UTF-16 code
    // units indexed by `String[i]` / `String.take`. Returns IntValue
    // of the code point or pushes a diagnostic if out of range.
    "codePointAt" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "String.codePointAt expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx) => {
          let mut count = 0
          let mut found : Int? = None
          for c in s.iter() {
            if count == idx {
              found = Some(c.to_int())
              break
            }
            count = count + 1
          }
          match found {
            Some(cp) => Some(IntValue(cp))
            None => {
              diagnostics.push(
                diag("String.codePointAt index \{idx} out of range"),
              )
              None
            }
          }
        }
        _ => {
          diagnostics.push(diag("String.codePointAt expects Int argument"))
          None
        }
      }
    }
    "toLowerCase" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.toLowerCase expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(StringValue(s.to_lower()))
    }
    "contains" =>
      one_string_arg(arg_values, "String.contains", diagnostics, fn(needle) {
        Some(BoolValue(s.contains(needle)))
      })
    "startsWith" =>
      one_string_arg(arg_values, "String.startsWith", diagnostics, fn(prefix) {
        Some(BoolValue(s.has_prefix(prefix)))
      })
    "endsWith" =>
      one_string_arg(arg_values, "String.endsWith", diagnostics, fn(suffix) {
        Some(BoolValue(s.has_suffix(suffix)))
      })
    "indexOf" =>
      one_string_arg(arg_values, "String.indexOf", diagnostics, fn(needle) {
        match s.find(needle) {
          Some(i) => Some(IntValue(i))
          None => Some(IntValue(-1))
        }
      })
    "replaceAll" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceAll expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace_all(old~, new=new_value)))
        _ => {
          diagnostics.push(diag("String.replaceAll expects String arguments"))
          None
        }
      }
    }
    "replaceFirst" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.replaceFirst expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (StringValue(old), StringValue(new_value)) =>
          Some(StringValue(s.replace(old~, new=new_value)))
        _ => {
          diagnostics.push(diag("String.replaceFirst expects String arguments"))
          None
        }
      }
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.take expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(StringValue(String::unsafe_substring(s, start=0, end=n)))
        }
        _ => {
          diagnostics.push(diag("String.take expects Int argument"))
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("String.drop expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let n = if raw < 0 {
            0
          } else if raw > s.length() {
            s.length()
          } else {
            raw
          }
          Some(
            StringValue(String::unsafe_substring(s, start=n, end=s.length())),
          )
        }
        _ => {
          diagnostics.push(diag("String.drop expects Int argument"))
          None
        }
      }
    }
    "split" =>
      one_string_arg(arg_values, "String.split", diagnostics, fn(sep) {
        let parts : Array[Value] = []
        for piece in s.split(sep) {
          parts.push(StringValue(piece.to_owned()))
        }
        Some(ListingValue(parts))
      })
    "padStart" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "String.padStart expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, true)))
        _ => {
          diagnostics.push(
            diag("String.padStart expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    "padEnd" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("String.padEnd expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(width), StringValue(pad)) =>
          Some(StringValue(pad_string(s, width, pad, false)))
        _ => {
          diagnostics.push(
            diag("String.padEnd expects (Int, String) arguments"),
          )
          None
        }
      }
    }
    // No-arg property surface accessible as `string.length()` etc.
    "length"
    | "isEmpty"
    | "isNotEmpty"
    | "isBlank"
    | "isNotBlank"
    | "reverse"
    | "base64"
    | "codePointCount"
    | "codePoints"
    | "chars" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "String.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_string_property(s, method_name, diagnostics)
      }
    _ => None
  }
}

///|
fn one_string_arg(
  arg_values : Array[Value],
  label : String,
  diagnostics : Array[Diagnostic],
  body : (String) -> Value?,
) -> Value? {
  if arg_values.length() != 1 {
    diagnostics.push(
      diag("\{label} expects 1 argument, got \{arg_values.length()}"),
    )
    return None
  }
  match arg_values[0] {
    StringValue(s) => body(s)
    _ => {
      diagnostics.push(diag("\{label} expects String argument"))
      None
    }
  }
}
