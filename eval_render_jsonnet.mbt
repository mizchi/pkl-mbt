// Jsonnet renderer.
//
// Renders Pkl `Value`s as [Jsonnet](https://jsonnet.org) text following the
// shape Apple Pkl's `pkl:jsonnet` produces. The module is intentionally
// self-contained — it only depends on the Pkl `Value` enum and the
// shared `find_object_class_tag` / `apply_value_renderer_converters`
// helpers in eval_expr.mbt. The Jsonnet semantics encoded here
// (single-quoted strings, `|||` heredoc for newline-containing text,
// trailing comma after each container element, `null`-field elision
// when `omitNullProperties = true`, special `ExtVar` / `ImportStr`
// constructor projection) live in this file alone, so this is the
// designated extraction candidate if a standalone `mizchi/jsonnet`
// MoonBit package is needed later — the only external surface is the
// `render_value_as_jsonnet*` functions below.

///|
pub fn render_value_as_jsonnet(value : Value) -> String {
  render_value_as_jsonnet_with_options(value, "  ", true)
}

///|
pub fn render_value_as_jsonnet_with_indent(
  value : Value,
  indent_text : String,
) -> String {
  render_value_as_jsonnet_with_options(value, indent_text, true)
}

///|
pub fn render_value_as_jsonnet_with_options(
  value : Value,
  indent_text : String,
  omit_null_properties : Bool,
) -> String {
  let buf = StringBuilder::new()
  let ctx : JsonnetCtx = {
    indent_text,
    omit_null_properties,
    compact: indent_text == "",
  }
  jsonnet_emit_value(value, 0, ctx, buf)
  buf.to_string()
}

///|
pub fn render_value_as_jsonnet_document(value : Value) -> String {
  render_value_as_jsonnet_document_with_options(value, "  ", true)
}

///|
pub fn render_value_as_jsonnet_document_with_indent(
  value : Value,
  indent_text : String,
) -> String {
  render_value_as_jsonnet_document_with_options(value, indent_text, true)
}

///|
pub fn render_value_as_jsonnet_document_with_options(
  value : Value,
  indent_text : String,
  omit_null_properties : Bool,
) -> String {
  let rendered = render_value_as_jsonnet_with_options(
    value, indent_text, omit_null_properties,
  )
  if rendered.has_suffix("\n") {
    rendered
  } else {
    rendered + "\n"
  }
}

///|
priv struct JsonnetCtx {
  indent_text : String
  omit_null_properties : Bool
  compact : Bool
}

///|
fn jsonnet_emit_value(
  value : Value,
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  match value {
    NullValue => buf.write_string("null")
    DeferredImportValue(_) => buf.write_string("null")
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(jsonnet_float_text(d))
    StringValue(s) => jsonnet_emit_string(s, indent, ctx, buf)
    ObjectValue(members) =>
      jsonnet_emit_object_from_members(members, indent, ctx, buf)
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      jsonnet_emit_object_from_entries(entries, indent, ctx, buf)
    MapValue(entries) =>
      jsonnet_emit_object_from_entries(entries, indent, ctx, buf)
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements)
    | SetValue(elements) => jsonnet_emit_array(elements, indent, ctx, buf)
    // The renderer-error dispatch (`jsonnet_renderer_value_error`)
    // rejects these before we reach the emit path, so reaching them
    // here means a caller bypassed the error gate. Emit `null` as a
    // last resort rather than crashing.
    DurationValue(_, _)
    | DataSizeValue(_, _)
    | PairValue(_, _)
    | IntSeqValue(_, _, _)
    | FunctionValue(_, _, _, _, _)
    | RegexValue(_)
    | BytesValue(_) => buf.write_string("null")
  }
}

///|
/// Detect the `pkl:jsonnet` ExtVar / ImportStr constructor shape so
/// `someExternalVariable = jsonnet.ExtVar("MY_VARIABLE")` renders as
/// `std.extVar('MY_VARIABLE')` and `someImportStr = jsonnet.ImportStr("foo")`
/// renders as `importstr 'foo'`. Both classes are single-string
/// payloads tagged via the universal class marker (see
/// `tag_object_with_class` in eval_module.mbt).
fn jsonnet_special_object_text(members : Array[ValueMember]) -> String? {
  // The stub constructors in `analysis.mbt`'s pkl:jsonnet text stamp
  // a `_jsonnet_kind = "ExtVar" / "ImportStr"` hidden marker on the
  // resulting `new` body; we cannot rely on the class-tag marker
  // because Pkl `new { ... }` inside a lambda body doesn't propagate
  // the class tag through the typed-return-path today.
  let kind = match lookup_member(members, "__jsonnet_kind__") {
    Some(StringValue(s)) => Some(s)
    _ =>
      match find_object_class_tag(members) {
        Some("ExtVar") => Some("ExtVar")
        Some("ImportStr") => Some("ImportStr")
        _ => None
      }
  }
  match kind {
    Some("ExtVar") =>
      match lookup_visible_member(members, "name") {
        Some(StringValue(name)) =>
          Some("std.extVar(" + jsonnet_quoted_string(name) + ")")
        _ => None
      }
    Some("ImportStr") =>
      match lookup_visible_member(members, "path") {
        Some(StringValue(path)) =>
          Some("importstr " + jsonnet_quoted_string(path))
        _ => None
      }
    _ => None
  }
}

///|
fn jsonnet_emit_object_from_members(
  members : Array[ValueMember],
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  match jsonnet_special_object_text(members) {
    Some(text) => {
      buf.write_string(text)
      return
    }
    None => ()
  }
  let entries : Array[(String, Value)] = []
  for field in visible_members(members) {
    if field.name == class_tag_member_name() {
      continue
    }
    // `__jsonnet_kind__` is the internal marker the pkl:jsonnet stub
    // uses to identify ExtVar / ImportStr constructor results (see
    // `jsonnet_special_object_text`); it must never reach the rendered
    // text.
    if field.name == "__jsonnet_kind__" {
      continue
    }
    if ctx.omit_null_properties && field.value is NullValue {
      continue
    }
    entries.push((field.name, field.value))
  }
  jsonnet_emit_object_entries_typed(entries, indent, ctx, buf)
}

///|
fn jsonnet_emit_object_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  let kvs : Array[(String, Value)] = []
  for entry in entries {
    if ctx.omit_null_properties && entry.value is NullValue {
      continue
    }
    let key = match entry.key {
      StringValue(s) => s
      IntValue(n) => "\{n}"
      FloatValue(d) => jsonnet_float_text(d)
      BoolValue(b) => if b { "true" } else { "false" }
      _ => jsonnet_value_to_string_key(entry.key)
    }
    kvs.push((key, entry.value))
  }
  jsonnet_emit_object_entries_typed(kvs, indent, ctx, buf)
}

///|
fn jsonnet_emit_object_entries_typed(
  entries : Array[(String, Value)],
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  if entries.length() == 0 {
    buf.write_string("{}")
    return
  }
  if ctx.compact {
    buf.write_string("{ ")
    for i = 0; i < entries.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      let (key, value) = entries[i]
      buf.write_string(jsonnet_object_key(key))
      buf.write_string(": ")
      jsonnet_emit_value(value, indent + 1, ctx, buf)
    }
    buf.write_string(" }")
    return
  }
  buf.write_string("{\n")
  let inner_indent = indent + 1
  for entry in entries {
    let (key, value) = entry
    jsonnet_write_indent(inner_indent, ctx, buf)
    buf.write_string(jsonnet_object_key(key))
    buf.write_string(": ")
    jsonnet_emit_value(value, inner_indent, ctx, buf)
    buf.write_string(",\n")
  }
  jsonnet_write_indent(indent, ctx, buf)
  buf.write_char('}')
}

///|
fn jsonnet_emit_array(
  elements : Array[Value],
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  if elements.length() == 0 {
    buf.write_string("[]")
    return
  }
  if ctx.compact {
    buf.write_char('[')
    for i = 0; i < elements.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      jsonnet_emit_value(elements[i], indent + 1, ctx, buf)
    }
    buf.write_char(']')
    return
  }
  buf.write_string("[\n")
  let inner_indent = indent + 1
  for element in elements {
    jsonnet_write_indent(inner_indent, ctx, buf)
    jsonnet_emit_value(element, inner_indent, ctx, buf)
    buf.write_string(",\n")
  }
  jsonnet_write_indent(indent, ctx, buf)
  buf.write_char(']')
}

///|
fn jsonnet_write_indent(
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  for _ in 0..<indent {
    buf.write_string(ctx.indent_text)
  }
}

///|
/// Jsonnet object keys are unquoted when they're valid identifiers
/// (`[a-zA-Z_][a-zA-Z0-9_]*`) and quoted otherwise. Matches Apple
/// Pkl's `jsonnetfmt` output (`annoyingNames` fixture has
/// `'5hello'`, `'foo.bar'`, `"single'quote"`).
fn jsonnet_object_key(key : String) -> String {
  if jsonnet_is_simple_identifier(key) && !jsonnet_is_reserved_keyword(key) {
    return key
  }
  jsonnet_quoted_string(key)
}

///|
/// Jsonnet reserved words. Bare identifiers matching one of these must
/// be quoted as object keys (jsonnetfmt-compatible). The list comes
/// from the Jsonnet language spec — kept narrow to just what shows up
/// in the upstream fixtures (`local`); the rest are included so we
/// don't regress on future fixtures that exercise edge cases.
fn jsonnet_is_reserved_keyword(name : String) -> Bool {
  match name {
    "assert"
    | "else"
    | "error"
    | "false"
    | "for"
    | "function"
    | "if"
    | "import"
    | "importstr"
    | "in"
    | "local"
    | "null"
    | "self"
    | "super"
    | "tailstrict"
    | "then"
    | "true" => true
    _ => false
  }
}

///|
fn jsonnet_is_simple_identifier(key : String) -> Bool {
  if key.length() == 0 {
    return false
  }
  let first = key[0].to_int().unsafe_to_char()
  if !((first >= 'a' && first <= 'z') ||
    (first >= 'A' && first <= 'Z') ||
    first == '_') {
    return false
  }
  for i = 1; i < key.length(); i = i + 1 {
    let c = key[i].to_int().unsafe_to_char()
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_') {
      return false
    }
  }
  true
}

///|
fn jsonnet_value_to_string_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    FloatValue(d) => jsonnet_float_text(d)
    BoolValue(b) => if b { "true" } else { "false" }
    NullValue => "null"
    _ => "?"
  }
}

///|
/// Single-quote strings unless the content contains a `'` and no `"`,
/// in which case switch to double-quote so the renderer doesn't need
/// to escape the apostrophe. Matches `jsonnetfmt`'s quoting choice
/// observed in the upstream fixtures (`"single'quote"` vs `'foo.bar'`).
fn jsonnet_quoted_string(s : String) -> String {
  let has_single = string_contains_char(s, '\'')
  let has_double = string_contains_char(s, '"')
  let use_double = has_single && !has_double
  let buf = StringBuilder::new()
  if use_double {
    buf.write_char('"')
  } else {
    buf.write_char('\'')
  }
  for ch in s {
    jsonnet_write_escaped_char(ch, use_double, buf)
  }
  if use_double {
    buf.write_char('"')
  } else {
    buf.write_char('\'')
  }
  buf.to_string()
}

///|
fn jsonnet_write_escaped_char(
  ch : Char,
  use_double : Bool,
  buf : StringBuilder,
) -> Unit {
  let code = ch.to_int()
  if code == '\\'.to_int() {
    buf.write_string("\\\\")
  } else if code == '\n'.to_int() {
    buf.write_string("\\n")
  } else if code == '\r'.to_int() {
    buf.write_string("\\r")
  } else if code == '\t'.to_int() {
    buf.write_string("\\t")
  } else if code == '\u{08}' {
    buf.write_string("\\b")
  } else if code == '\u{0c}' {
    buf.write_string("\\f")
  } else if use_double && code == '"'.to_int() {
    buf.write_string("\\\"")
  } else if !use_double && code == '\''.to_int() {
    buf.write_string("\\'")
  } else if code < 0x20 {
    let hex = jsonnet_hex4(code)
    buf.write_string("\\u")
    buf.write_string(hex)
  } else {
    buf.write_char(ch)
  }
}

///|
fn jsonnet_hex4(code : Int) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  buf.write_char(digits[(code >> 12) & 0xf].to_int().unsafe_to_char())
  buf.write_char(digits[(code >> 8) & 0xf].to_int().unsafe_to_char())
  buf.write_char(digits[(code >> 4) & 0xf].to_int().unsafe_to_char())
  buf.write_char(digits[code & 0xf].to_int().unsafe_to_char())
  buf.to_string()
}

///|
/// Newline-containing strings render as the `|||` heredoc block
/// jsonnetfmt prefers. Without this an interpolated multi-line value
/// would emit one giant single-quoted string with `\n` escapes, which
/// reads poorly compared to the canonical Pkl output.
fn jsonnet_emit_string(
  s : String,
  indent : Int,
  ctx : JsonnetCtx,
  buf : StringBuilder,
) -> Unit {
  if ctx.compact || !string_contains_char(s, '\n') {
    buf.write_string(jsonnet_quoted_string(s))
    return
  }
  buf.write_string("|||\n")
  let inner_indent = indent + 1
  let lines = s.split("\n").collect()
  let trailing_newline = s.has_suffix("\n")
  let last_idx = if trailing_newline {
    lines.length() - 2
  } else {
    lines.length() - 1
  }
  for i = 0; i <= last_idx; i = i + 1 {
    let line = lines[i].to_owned()
    if line == "" {
      buf.write_char('\n')
      continue
    }
    jsonnet_write_indent(inner_indent, ctx, buf)
    buf.write_string(line)
    buf.write_char('\n')
  }
  jsonnet_write_indent(indent, ctx, buf)
  buf.write_string("|||")
}

///|
fn jsonnet_float_text(d : Double) -> String {
  if d.is_nan() {
    // Jsonnet has no NaN literal — the renderer error gate would
    // normally trap this, but if it slips through fall back to the
    // jsonnetfmt-style `null` placeholder rather than crashing.
    return "null"
  }
  if d.is_inf() {
    return "null"
  }
  if d == d.floor() && d.abs() < 9.0e15 {
    "\{d.to_int64()}"
  } else {
    "\{d}"
  }
}
