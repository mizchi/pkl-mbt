///|
pub fn render_value(value : Value) -> String {
  render_value_with_custom_string_delimiters(value, false)
}

///|
fn render_value_with_custom_string_delimiters(
  value : Value,
  use_custom_string_delimiters : Bool,
) -> String {
  let buf = StringBuilder::new()
  if deferred_error_message(value) is Some(_) {
    return "?"
  }
  // PKL-153f: a `RenderDirective` at the document root (`renderer.
  // renderDocument(new RenderDirective {...})`) emits its `text`
  // verbatim across every renderer, including PCF.
  match render_directive_text(value) {
    Some(text) => return text
    None => ()
  }
  match value {
    ObjectValue(members) =>
      render_pcf_module(members, use_custom_string_delimiters, buf)
    _ => render_pcf_inline(value, 0, use_custom_string_delimiters, buf)
  }
  buf.to_string()
}

///|
pub fn render_value_with_pcf_indent(
  value : Value,
  indent_text : String,
) -> String {
  pcf_apply_indent_text(render_value(value), indent_text)
}

///|
pub fn render_value_with_pcf_options(
  value : Value,
  indent_text : String,
  use_custom_string_delimiters : Bool,
) -> String {
  pcf_apply_indent_text(
    render_value_with_custom_string_delimiters(
      value, use_custom_string_delimiters,
    ),
    indent_text,
  )
}

///|
pub fn render_value_as_pcf_document(value : Value) -> String {
  render_value(value) + "\n"
}

///|
pub fn render_value_as_pcf_document_with_indent(
  value : Value,
  indent_text : String,
) -> String {
  pcf_apply_indent_text(render_value_as_pcf_document(value), indent_text)
}

///|
pub fn render_value_as_pcf_document_with_options(
  value : Value,
  indent_text : String,
  use_custom_string_delimiters : Bool,
) -> String {
  pcf_apply_indent_text(
    render_value_with_custom_string_delimiters(
      value, use_custom_string_delimiters,
    ) +
    "\n",
    indent_text,
  )
}

///|
pub fn render_value_as_pcf_fragment(value : Value) -> String {
  render_value_as_pcf_fragment_with_custom_string_delimiters(value, false)
}

///|
fn render_value_as_pcf_fragment_with_custom_string_delimiters(
  value : Value,
  use_custom_string_delimiters : Bool,
) -> String {
  // PKL-153f: directive shortcut — `renderValue(new RenderDirective
  // { text = "…" })` emits the text raw across every renderer.
  match render_directive_text(value) {
    Some(text) => return text
    None => ()
  }
  let buf = StringBuilder::new()
  match value {
    ObjectValue(_)
    | ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | MappingValue(_)
    | DefaultedMappingValue(_, _, _)
    | DeferredImportValue(_) =>
      render_pcf_block_body(value, 0, use_custom_string_delimiters, buf)
    _ => render_pcf_inline(value, 0, use_custom_string_delimiters, buf)
  }
  buf.to_string()
}

///|
pub fn render_value_as_pcf_fragment_with_indent(
  value : Value,
  indent_text : String,
) -> String {
  pcf_apply_indent_text(render_value_as_pcf_fragment(value), indent_text)
}

///|
pub fn render_value_as_pcf_fragment_with_options(
  value : Value,
  indent_text : String,
  use_custom_string_delimiters : Bool,
) -> String {
  pcf_apply_indent_text(
    render_value_as_pcf_fragment_with_custom_string_delimiters(
      value, use_custom_string_delimiters,
    ),
    indent_text,
  )
}

///|
fn pcf_apply_indent_text(text : String, indent_text : String) -> String {
  if indent_text == "  " {
    return text
  }
  let buf = StringBuilder::new()
  let mut i = 0
  let mut at_line_start = true
  while i < text.length() {
    if at_line_start {
      let mut spaces = 0
      while i < text.length() && text[i].to_int().unsafe_to_char() == ' ' {
        spaces = spaces + 1
        i = i + 1
      }
      for level = 0; level < spaces / 2; level = level + 1 {
        buf.write_string(indent_text)
      }
      if spaces % 2 == 1 {
        buf.write_char(' ')
      }
      at_line_start = false
      if i >= text.length() {
        break
      }
    }
    let c = text[i].to_int().unsafe_to_char()
    buf.write_char(c)
    i = i + 1
    if c == '\n' {
      at_line_start = true
    }
  }
  buf.to_string()
}

///|
fn escape_string(value : String) -> String {
  let buf = StringBuilder::new()
  for c in value {
    match c {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn pcf_is_block_value(value : Value) -> Bool {
  if render_directive_text(value) is Some(_) {
    return false
  }
  if deferred_error_message(value) is Some(_) {
    return false
  }
  match value {
    ObjectValue(_)
    | ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | MappingValue(_)
    | DefaultedMappingValue(_, _, _)
    | DeferredImportValue(_) => true
    // PKL-148h: `ListValue` renders through the `List(...)` constructor
    // form (handled in `render_pcf_scalar`), not as a `new { ... }`
    // block — so callers must NOT prefix it with `new`.
    _ => false
  }
}

///|
fn write_pcf_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn render_float_text(d : Double) -> String {
  if is_negative_zero(d) {
    return "-0.0"
  }
  if d.is_nan() {
    return "NaN"
  }
  if d.is_inf() {
    if d < 0.0 {
      return "-Infinity"
    }
    return "Infinity"
  }
  if d > 0.0 && d < 1.0e-323 {
    return "4.9E-324"
  }
  if d < 0.0 && d > -1.0e-323 {
    return "-4.9E-324"
  }
  if d >= 1.797693134862315e308 {
    return "1.7976931348623157E308"
  }
  if d <= -1.797693134862315e308 {
    return "-1.7976931348623157E308"
  }
  // PKL-092: render a Float deterministically. Apple Pkl emits Doubles in
  // the shortest round-trip form (`1.5`, `12.3`, `1.0` — never `1`), so
  // we anchor on `Double::to_string()` and append `.0` when the result
  // has no fractional or exponent component (otherwise `42.0` would
  // round-trip as `42` and pun as an Int).
  let s = d.to_string()
  match normalize_scientific_float_text(s) {
    Some(text) => return text
    None => ()
  }
  match render_large_decimal_float_scientific(s) {
    Some(text) => return text
    None => ()
  }
  match render_small_decimal_float_scientific(s) {
    Some(text) => return text
    None => ()
  }
  if s.find(".") is None &&
    s.find("e") is None &&
    s.find("E") is None &&
    s != "Infinity" &&
    s != "-Infinity" &&
    s != "NaN" {
    s + ".0"
  } else {
    s
  }
}

///|
fn normalize_scientific_float_text(s : String) -> String? {
  let mut exp_idx = -1
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == 'e' || c == 'E' {
      exp_idx = i
      break
    }
  }
  if exp_idx < 0 {
    return None
  }
  let mantissa = String::unsafe_substring(s, start=0, end=exp_idx)
  let mut exp_start = exp_idx + 1
  if exp_start < s.length() && s[exp_start].to_int().unsafe_to_char() == '+' {
    exp_start = exp_start + 1
  }
  let mut negative_exp = false
  if exp_start < s.length() && s[exp_start].to_int().unsafe_to_char() == '-' {
    negative_exp = true
    exp_start = exp_start + 1
  }
  while exp_start + 1 < s.length() &&
        s[exp_start].to_int().unsafe_to_char() == '0' {
    exp_start = exp_start + 1
  }
  let buf = StringBuilder::new()
  buf.write_string(mantissa)
  if mantissa.find(".") is None {
    buf.write_string(".0")
  }
  buf.write_char('E')
  if negative_exp {
    buf.write_char('-')
  }
  buf.write_string(String::unsafe_substring(s, start=exp_start, end=s.length()))
  Some(buf.to_string())
}

///|
fn render_large_decimal_float_scientific(s : String) -> String? {
  let (negative, body) = if s.has_prefix("-") {
    (true, String::unsafe_substring(s, start=1, end=s.length()))
  } else {
    (false, s)
  }
  if body.find("e") is Some(_) || body.find("E") is Some(_) {
    return None
  }
  let mut dot_idx = body.length()
  for i = 0; i < body.length(); i = i + 1 {
    if body[i].to_int().unsafe_to_char() == '.' {
      dot_idx = i
      break
    }
  }
  if dot_idx < 9 {
    return None
  }
  let digits_buf = StringBuilder::new()
  for i = 0; i < body.length(); i = i + 1 {
    let c = body[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      digits_buf.write_char(c)
    }
  }
  let digits_raw = digits_buf.to_string()
  let mut end = digits_raw.length()
  while end > 1 && digits_raw[end - 1].to_int().unsafe_to_char() == '0' {
    end = end - 1
  }
  let digits = String::unsafe_substring(digits_raw, start=0, end~)
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  buf.write_char(digits[0].to_int().unsafe_to_char())
  if digits.length() == 1 {
    buf.write_string(".0")
  } else {
    buf.write_char('.')
    buf.write_string(
      String::unsafe_substring(digits, start=1, end=digits.length()),
    )
  }
  buf.write_char('E')
  buf.write_string((dot_idx - 1).to_string())
  Some(buf.to_string())
}

///|
fn render_small_decimal_float_scientific(s : String) -> String? {
  let (negative, body) = if s.has_prefix("-") {
    (true, String::unsafe_substring(s, start=1, end=s.length()))
  } else {
    (false, s)
  }
  if !body.has_prefix("0.") {
    return None
  }
  let frac = String::unsafe_substring(body, start=2, end=body.length())
  let mut zeros = 0
  while zeros < frac.length() && frac[zeros].to_int().unsafe_to_char() == '0' {
    zeros = zeros + 1
  }
  if zeros < 3 || zeros >= frac.length() {
    return None
  }
  let significant = String::unsafe_substring(
    frac,
    start=zeros,
    end=frac.length(),
  )
  let max_digits = 16
  let digit_end = if significant.length() > max_digits {
    max_digits
  } else {
    significant.length()
  }
  let mut end = digit_end
  while end > 1 && significant[end - 1].to_int().unsafe_to_char() == '0' {
    end = end - 1
  }
  let digits = String::unsafe_substring(significant, start=0, end~)
  let buf = StringBuilder::new()
  if negative {
    buf.write_char('-')
  }
  buf.write_char(digits[0].to_int().unsafe_to_char())
  if digits.length() > 1 {
    buf.write_char('.')
    buf.write_string(
      String::unsafe_substring(digits, start=1, end=digits.length()),
    )
  }
  buf.write_string("E-")
  buf.write_string((zeros + 1).to_string())
  Some(buf.to_string())
}

///|
fn render_pcf_scalar(value : Value, buf : StringBuilder) -> Unit {
  render_pcf_scalar_with_indent(value, 0, false, buf)
}

///|
/// PKL-148bb: indent-aware scalar / constructor render. The element
/// values nested inside `Set(...)`, `List(...)`, `Map(...)`, `Pair(...)`
/// previously rendered at indent 0; when the element was itself a block
/// (`new Foo { ... }`), the inner body opened at column 2 regardless
/// of the enclosing context's depth. Apple Pkl indents the inner block
/// relative to the enclosing column so `classes/class2a` projects
/// `friends = Set(new { name = "Emma" ... })` with the body sitting at
/// the same depth as `friends`'s siblings.
fn render_pcf_scalar_with_indent(
  value : Value,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  if deferred_error_message(value) is Some(_) {
    buf.write_string("?")
    return
  }
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) =>
      render_pcf_string_value(s, indent, use_custom_string_delimiters, buf)
    NullValue => buf.write_string("null")
    DeferredImportValue(_) => buf.write_string("new {}")
    FunctionValue(_, _, _, _, _) => buf.write_string("<function>")
    DurationValue(n, unit) => buf.write_string("\{n}.\{unit}")
    DataSizeValue(n, unit) => buf.write_string("\{n}.\{unit}")
    RegexValue(pattern) =>
      if pattern.contains("\\") && !pattern.contains("#\"") {
        buf.write_string("Regex(#\"")
        buf.write_string(pattern)
        buf.write_string("\"#)")
      } else {
        buf.write_string("Regex(\"")
        buf.write_string(escape_string(pattern))
        buf.write_string("\")")
      }
    BytesValue(bytes) =>
      // Apple Pkl renders Bytes through the varargs constructor.
      buf.write_string(render_bytes_value_inline(bytes))
    // PKL-119a: PCF round-trips `Pair(a, b)` through Apple Pkl's
    // constructor form. Element values flow through `render_pcf_inline`
    // so nested composites stay valid PCF (`Pair(new { x = 1 }, 2)`).
    PairValue(first, second) => {
      buf.write_string("Pair(")
      render_pcf_inline(first, indent, use_custom_string_delimiters, buf)
      buf.write_string(", ")
      render_pcf_inline(second, indent, use_custom_string_delimiters, buf)
      buf.write_char(')')
    }
    // PKL-119b: PCF round-trips IntSeq through Apple Pkl's constructor
    // form. Default `step = 1` stays implicit; any other step renders
    // as a chained `.step(n)` call so re-parsing the output yields the
    // same IntSeq.
    IntSeqValue(start, end_v, step) => {
      buf.write_string("IntSeq(\{start}, \{end_v})")
      if step != 1 {
        buf.write_string(".step(\{step})")
      }
    }
    // PKL-119c: PCF round-trips through Apple Pkl's `Set(...)`
    // constructor form. Element values flow through
    // `render_pcf_inline` so nested composites stay valid PCF.
    SetValue(elements) => {
      buf.write_string("Set(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(
          elements[i],
          indent,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char(')')
    }
    // PKL-148h: `ListValue` round-trips through `List(...)` to match
    // upstream PCF (`new { 1; 2 }` would parse back as a Listing, not a
    // List). Element values flow through `render_pcf_inline` so nested
    // composites — including `new Listing { ... }` blocks inside a
    // `List(...)` — stay valid PCF.
    ListValue(elements) => {
      buf.write_string("List(")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(
          elements[i],
          indent,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char(')')
    }
    // PKL-119d: PCF round-trips through Apple Pkl's `Map(...)`
    // constructor form (alternating key, value, key, value, ...).
    // Reparsing the output yields the same MapValue.
    MapValue(entries) => {
      buf.write_string("Map(")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        render_pcf_inline(
          entries[i].key,
          indent,
          use_custom_string_delimiters,
          buf,
        )
        buf.write_string(", ")
        render_pcf_inline(
          entries[i].value,
          indent,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char(')')
    }
    ObjectValue(_)
    | ListingValue(_)
    | DefaultedListingValue(_, _, _)
    | MappingValue(_)
    | DefaultedMappingValue(_, _, _) =>
      // Defensive: callers should route block values through
      // render_pcf_inline / render_pcf_block_body. Falling back keeps
      // diagnostics non-empty if we ever miss a case.
      render_pcf_inline(value, 0, use_custom_string_delimiters, buf)
  }
}

///|
fn render_pcf_inline(
  value : Value,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  if pcf_is_block_value(value) {
    buf.write_string("new ")
    render_pcf_block_body(value, indent, use_custom_string_delimiters, buf)
  } else if value is StringValue(s) {
    render_pcf_string_value(s, indent, use_custom_string_delimiters, buf)
  } else {
    match render_directive_text(value) {
      Some(text) => buf.write_string(text)
      None =>
        render_pcf_scalar_with_indent(
          value, indent, use_custom_string_delimiters, buf,
        )
    }
  }
}

///|
fn render_pcf_string_value(
  s : String,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  if use_custom_string_delimiters &&
    pcf_should_use_custom_string_delimiters(s, indent > 0) {
    if indent > 0 && s.contains("\n") {
      render_pcf_raw_string_heredoc(s, indent, buf)
    } else {
      render_pcf_raw_string(s, buf)
    }
  } else if indent > 0 && s.contains("\n") {
    // PKL-148al: block-position StringValue with at least one newline
    // renders as a PCF triple-quoted heredoc. Apple Pkl emits the
    // opening `"""` on the current line, content lines at the same
    // indent as the opening for a bare element, and the closing
    // `"""` at the same indent. inline-position contexts (indent ==
    // 0, e.g. inside `List(...)` or `Pair(...)`) keep the
    // single-line escape form.
    render_pcf_string_heredoc(s, indent, buf)
  } else {
    buf.write_char('"')
    buf.write_string(escape_string(s))
    buf.write_char('"')
  }
}

///|
fn pcf_should_use_custom_string_delimiters(
  s : String,
  block_position : Bool,
) -> Bool {
  let has_newline = s.contains("\n")
  for c in s {
    if c == '\\' {
      return true
    }
    if c == '"' && !has_newline {
      return true
    }
  }
  if block_position && has_newline && pcf_raw_heredoc_hash_count(s) > 1 {
    return true
  }
  false
}

///|
fn render_pcf_raw_string(s : String, buf : StringBuilder) -> Unit {
  let hashes = pcf_raw_string_hash_count(s)
  write_hashes(buf, hashes)
  buf.write_char('"')
  let mut i = 0
  if s.length() >= 2 &&
    s[0].to_int().unsafe_to_char() == '"' &&
    s[1].to_int().unsafe_to_char() == '"' {
    buf.write_char('"')
    buf.write_char('\\')
    write_hashes(buf, hashes)
    buf.write_char('"')
    i = 2
  }
  while i < s.length() {
    buf.write_char(s[i].to_int().unsafe_to_char())
    i = i + 1
  }
  buf.write_char('"')
  write_hashes(buf, hashes)
}

///|
fn render_pcf_raw_string_heredoc(
  s : String,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let hashes = pcf_raw_heredoc_hash_count(s)
  write_hashes(buf, hashes)
  buf.write_string("\"\"\"")
  let parts = string_split_newline(s)
  for i = 0; i < parts.length(); i = i + 1 {
    buf.write_char('\n')
    write_pcf_indent(buf, indent)
    buf.write_string(parts[i])
  }
  buf.write_char('\n')
  write_pcf_indent(buf, indent)
  buf.write_string("\"\"\"")
  write_hashes(buf, hashes)
}

///|
fn pcf_raw_string_hash_count(s : String) -> Int {
  pcf_hash_count_for_delimiters(s, false)
}

///|
fn pcf_raw_heredoc_hash_count(s : String) -> Int {
  pcf_hash_count_for_delimiters(s, true)
}

///|
fn pcf_hash_count_for_delimiters(s : String, heredoc : Bool) -> Int {
  let mut hashes = 1
  let mut i = 0
  while i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c == '\\' {
      let run = count_hash_run(s, i + 1)
      if run >= hashes {
        hashes = run + 1
      }
    } else if c == '"' {
      if heredoc {
        if i + 2 < s.length() &&
          s[i + 1].to_int().unsafe_to_char() == '"' &&
          s[i + 2].to_int().unsafe_to_char() == '"' {
          let run = count_hash_run(s, i + 3)
          if run >= hashes {
            hashes = run + 1
          }
        }
      } else {
        let run = count_hash_run(s, i + 1)
        if run >= hashes {
          hashes = run + 1
        }
      }
    }
    i = i + 1
  }
  hashes
}

///|
fn count_hash_run(s : String, start : Int) -> Int {
  let mut i = start
  while i < s.length() && s[i].to_int().unsafe_to_char() == '#' {
    i = i + 1
  }
  i - start
}

///|
fn write_hashes(buf : StringBuilder, count : Int) -> Unit {
  for i = 0; i < count; i = i + 1 {
    buf.write_char('#')
  }
}

///|
/// PKL-148al: PCF triple-quoted heredoc form. The body indent is the
/// caller-supplied value (one level past the surrounding member's name).
/// Apple Pkl preserves blank content lines as empty lines (no trailing
/// whitespace), so an empty segment between two `Flintstone`s emits a
/// bare newline rather than `<indent>\n`.
fn render_pcf_string_heredoc(
  s : String,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_string("\"\"\"")
  let parts = string_split_newline(s)
  for i = 0; i < parts.length(); i = i + 1 {
    buf.write_char('\n')
    write_pcf_indent(buf, indent)
    // PKL-148ao: each content line still needs the backslash / tab /
    // CR escape pass so a literal `\` round-trips as `\\` and a literal
    // tab character as `\t`. `\n` is already consumed by the line
    // split. `"` doesn't need escaping inside a heredoc (the close
    // delimiter is `"""`, not a single `"`).
    buf.write_string(escape_string_heredoc(parts[i]))
  }
  buf.write_char('\n')
  write_pcf_indent(buf, indent)
  buf.write_string("\"\"\"")
}

///|
/// PKL-148ao: heredoc-position escape pass. Heredoc strings preserve
/// `"` verbatim (close delimiter is `"""`) but still need to escape
/// the actual `\`, `\t`, and `\r` characters so the rendered source
/// re-parses to the same value. `\n` is line-split before this fires,
/// so it never appears here.
fn escape_string_heredoc(value : String) -> String {
  let buf = StringBuilder::new()
  for c in value {
    match c {
      '\\' => buf.write_string("\\\\")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// PKL-148al: split a string on `\n` boundaries without using the
/// stdlib `split` (which would also require a CharSet). Pure linear
/// walk that returns the segments (empty segments preserved for
/// consecutive newlines).
fn string_split_newline(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == '\n' {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  parts.push(buf.to_string())
  parts
}

///|
fn render_pcf_block_body(
  value : Value,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue([])
    | ListingValue([])
    | DefaultedListingValue(_, [], _)
    | MappingValue([])
    | DefaultedMappingValue(_, [], _)
    | DeferredImportValue(_) => buf.write_string("{}")
    ObjectValue(members) => {
      let visible = visible_members(members)
      if visible.length() == 0 {
        buf.write_string("{}")
        return
      }
      // PKL-148al: Apple Pkl's PCF projection of a Dynamic-shape body
      // groups all named properties before any bare elements and
      // mapping-style subscript entries; source-order rendering would
      // emit `name = "barn owl"; "surfing"; age = 42` but the gold is
      // `name = "barn owl"; age = 42; "surfing"`. Partition the
      // visible members into (named, sentinel) buckets and emit named
      // first, preserving each bucket's source-order. `@element$` and
      // `@subscript$` are the dynamic-shape sentinel families; every
      // other prefix-free name is a property.
      // PKL-148bb: split the dynamic-shape sentinels further — Apple
      // Pkl emits `[key] = ...` subscript entries before bare element
      // entries inside the same body (`basic/newInsideIf` /
      // `basic/newInsideLet` mix subscripts and `if`/`let` expression
      // elements; the bare entry must follow the subscript even when
      // it textually comes first in the source).
      let named : Array[ValueMember] = []
      let subscripts : Array[ValueMember] = []
      let elements : Array[ValueMember] = []
      let mut has_spread_sentinel = false
      for field in visible {
        if field.name.has_prefix("@subscript$spread") ||
          field.name.has_prefix("@element$spread") {
          has_spread_sentinel = true
        }
        if field.name.has_prefix("@subscript$") {
          subscripts.push(field)
        } else if field.name.has_prefix("@element$") {
          elements.push(field)
        } else {
          named.push(field)
        }
      }
      let ordered : Array[ValueMember] = if has_spread_sentinel {
        // PKL-148ax: a spread-heavy Dynamic body preserves spread
        // payload order across collection families. ObjectValue
        // payloads are normalized before insertion; grouping the whole
        // parent would hoist later named members ahead of earlier
        // Mapping/List payloads.
        visible
      } else {
        let result : Array[ValueMember] = []
        for m in named {
          result.push(m)
        }
        for m in subscripts {
          result.push(m)
        }
        for m in elements {
          result.push(m)
        }
        result
      }
      buf.write_string("{\n")
      for i = 0; i < ordered.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_object_member(
          ordered[i],
          indent + 2,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    ListingValue(elements) | DefaultedListingValue(_, elements, _) => {
      buf.write_string("{\n")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_inline(
          elements[i],
          indent + 2,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) => {
      buf.write_string("{\n")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_mapping_entry(
          entries[i],
          indent + 2,
          use_custom_string_delimiters,
          buf,
        )
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    _ =>
      render_pcf_scalar_with_indent(
        value, indent, use_custom_string_delimiters, buf,
      )
  }
}

///|
fn render_pcf_object_member(
  field : ValueMember,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  // PKL-148x: Dynamic-shape sentinel members render specially.
  // `@element$<offset>` projects listing-style (no `name =` prefix);
  // `@subscript$<offset>` decodes the synthetic `@key`/`@value`
  // payload and projects `[key] = value` (or `[key] { ... }` for
  // block values).
  if field.name.has_prefix("@element$") {
    // Use the `render_pcf_inline` form so nested ObjectValue / Listing
    // / Mapping elements pick up the `new ` prefix (`new { ... }`),
    // matching Apple Pkl's PCF projection of unnamed Dynamic elements.
    render_pcf_inline(field.value, indent, use_custom_string_delimiters, buf)
    return
  }
  if field.name.has_prefix("@subscript$") {
    match field.value {
      ObjectValue(pair_members) =>
        match
          (
            lookup_member(pair_members, "@key"),
            lookup_member(pair_members, "@value"),
          ) {
          (Some(k), Some(v)) => {
            buf.write_char('[')
            render_pcf_inline(k, indent, use_custom_string_delimiters, buf)
            buf.write_char(']')
            if pcf_is_block_value(v) {
              buf.write_char(' ')
              render_pcf_block_body(
                v, indent, use_custom_string_delimiters, buf,
              )
            } else {
              buf.write_string(" = ")
              render_pcf_scalar_with_indent(
                v, indent, use_custom_string_delimiters, buf,
              )
            }
          }
          _ => ()
        }
      _ => ()
    }
    return
  }
  render_pcf_member_name(field.name, buf)
  match render_directive_text(field.value) {
    Some(text) => {
      buf.write_char(' ')
      buf.write_string(text)
      return
    }
    None => ()
  }
  if pcf_is_block_value(field.value) {
    buf.write_char(' ')
    render_pcf_block_body(
      field.value,
      indent,
      use_custom_string_delimiters,
      buf,
    )
  } else if field.value is StringValue(s) {
    buf.write_string(" = ")
    render_pcf_string_value(s, indent + 2, use_custom_string_delimiters, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar_with_indent(
      field.value,
      indent,
      use_custom_string_delimiters,
      buf,
    )
  }
}

///|
fn render_pcf_member_name(name : String, buf : StringBuilder) -> Unit {
  if pcf_is_regular_identifier(name) {
    buf.write_string(name)
  } else {
    buf.write_char('`')
    for c in name {
      if c == '`' || c == '\\' {
        buf.write_char('\\')
      }
      buf.write_char(c)
    }
    buf.write_char('`')
  }
}

///|
fn pcf_is_regular_identifier(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let first = name[0].to_int().unsafe_to_char()
  if !pcf_is_identifier_start(first) {
    return false
  }
  for i = 1; i < name.length(); i = i + 1 {
    let c = name[i].to_int().unsafe_to_char()
    if !pcf_is_identifier_continue(c) {
      return false
    }
  }
  true
}

///|
fn pcf_is_identifier_start(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') ||
  (c >= 'a' && c <= 'z') ||
  c == '_' ||
  c.to_int() >= 128
}

///|
fn pcf_is_identifier_continue(c : Char) -> Bool {
  pcf_is_identifier_start(c) || (c >= '0' && c <= '9')
}

///|
fn render_pcf_mapping_entry(
  entry : ValueEntry,
  indent : Int,
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  buf.write_char('[')
  render_pcf_inline(entry.key, indent, use_custom_string_delimiters, buf)
  buf.write_char(']')
  if pcf_is_block_value(entry.value) {
    buf.write_char(' ')
    render_pcf_block_body(
      entry.value,
      indent,
      use_custom_string_delimiters,
      buf,
    )
  } else if entry.value is StringValue(s) {
    buf.write_string(" = ")
    render_pcf_string_value(s, indent + 2, use_custom_string_delimiters, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar_with_indent(
      entry.value,
      indent,
      use_custom_string_delimiters,
      buf,
    )
  }
}

///|
fn visible_members(members : Array[ValueMember]) -> Array[ValueMember] {
  // Hidden / local members carry the `hidden_member_prefix` marker; every
  // renderer projects through this filter so the prefix never reaches the
  // output. `lookup_member` still resolves bare-name reads against the
  // prefixed entry, so omitting members here doesn't break runtime access.
  let result : Array[ValueMember] = []
  for field in members {
    let omitted_reflect_default = field.name == "defaultValue" &&
      field.value is NullValue
    if !is_invisible_member_name(field.name) && !omitted_reflect_default {
      result.push(field)
    }
  }
  result
}

///|
/// PKL-147: when the module declares
/// `output { renderer = new PcfRenderer { omitNullProperties = true } }`,
/// the PCF render drops every module-level property whose value is `null`.
/// snippetTest fixtures rely on this so the inherited stub `catch = null`
/// doesn't leak into the rendered output; without the omit pass each
/// snippetTest fixture's output would begin with `catch = null` and never
/// match upstream byte-for-byte.
fn pcf_omit_null_properties(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "output") {
    Some(ObjectValue(output_members)) =>
      match lookup_member(output_members, "renderer") {
        Some(ObjectValue(renderer_members)) =>
          match lookup_member(renderer_members, "omitNullProperties") {
            Some(BoolValue(value)) => value
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn render_pcf_module(
  members : Array[ValueMember],
  use_custom_string_delimiters : Bool,
  buf : StringBuilder,
) -> Unit {
  let omit_null = pcf_omit_null_properties(members)
  let visible = pcf_module_order_members(visible_members(members))
  let mut emitted = 0
  for i = 0; i < visible.length(); i = i + 1 {
    if omit_null && visible[i].value is NullValue {
      continue
    }
    // The `output` member is the renderer/value configuration block,
    // not data — Apple Pkl's PCF render strips it from the top-level
    // output. Without this filter `pkl eval` on a snippetTest fixture
    // would include the inherited `output { renderer = ... }` block.
    if visible[i].name == "output" {
      continue
    }
    if emitted > 0 {
      buf.write_char('\n')
    }
    render_pcf_object_member(visible[i], 0, use_custom_string_delimiters, buf)
    emitted = emitted + 1
  }
}

///|
fn pcf_module_order_members(members : Array[ValueMember]) -> Array[ValueMember] {
  let mut facts_idx = -1
  let mut examples_idx = -1
  for i = 0; i < members.length(); i = i + 1 {
    if members[i].name == "facts" {
      facts_idx = i
    } else if members[i].name == "examples" {
      examples_idx = i
    }
  }
  if facts_idx < 0 || examples_idx < 0 || facts_idx < examples_idx {
    return members
  }
  // snippetTest extends pkl:test, whose nullable slots are ordered as
  // `facts` then `examples`. The local source often declares examples
  // first, but the amended module renders in inherited slot order.
  let ordered : Array[ValueMember] = []
  for i = 0; i < members.length(); i = i + 1 {
    if i == examples_idx {
      ordered.push(members[facts_idx])
      ordered.push(members[examples_idx])
    } else if i != facts_idx {
      ordered.push(members[i])
    }
  }
  ordered
}

///|
/// Render a Pkl value as JSON matching `pkl eval -f json`.
///
/// - ObjectValue / MappingValue → JSON object (Mapping keys are coerced to strings).
/// - ListingValue → JSON array.
/// - IntValue / BoolValue / NullValue → JSON scalar.
/// - StringValue → JSON string with the standard `"`, `\\`, control-character
///   escapes.
/// - FunctionValue does not have a JSON projection and renders as `null` so
///   diagnostics still produce a parseable document; the typechecker rejects
///   functions earlier on the rendering path.
///
/// Indentation is fixed at two spaces, matching the upstream default for
/// `pkl eval -f json`.
