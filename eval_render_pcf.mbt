///|
pub fn render_value(value : Value) -> String {
  let buf = StringBuilder::new()
  match value {
    ObjectValue(members) => render_pcf_module(members, buf)
    _ => render_pcf_inline(value, 0, buf)
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
  match value {
    ObjectValue(_) | ListingValue(_) | MappingValue(_) => true
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
  // PKL-092: render a Float deterministically. Apple Pkl emits Doubles in
  // the shortest round-trip form (`1.5`, `12.3`, `1.0` — never `1`), so
  // we anchor on `Double::to_string()` and append `.0` when the result
  // has no fractional or exponent component (otherwise `42.0` would
  // round-trip as `42` and pun as an Int).
  let s = d.to_string()
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
fn render_pcf_scalar(value : Value, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => buf.write_string("\{n}")
    FloatValue(d) => buf.write_string(render_float_text(d))
    BoolValue(true) => buf.write_string("true")
    BoolValue(false) => buf.write_string("false")
    StringValue(s) => {
      buf.write_char('"')
      buf.write_string(escape_string(s))
      buf.write_char('"')
    }
    NullValue => buf.write_string("null")
    FunctionValue(_, _, _, _, _) => buf.write_string("<function>")
    DurationValue(n, unit) => buf.write_string("\{n}.\{unit}")
    DataSizeValue(n, unit) => buf.write_string("\{n}.\{unit}")
    RegexValue(pattern) => {
      buf.write_string("Regex(\"")
      buf.write_string(escape_string(pattern))
      buf.write_string("\")")
    }
    BytesValue(bytes) => {
      // PKL-083: PCF round-trips Bytes through the Listing constructor
      // so the parser can re-evaluate the literal verbatim. Each byte
      // is emitted as its 0..=255 decimal int.
      buf.write_string("Bytes(new Listing { ")
      for i = 0; i < bytes.length(); i = i + 1 {
        if i > 0 {
          buf.write_string("; ")
        }
        let n = bytes[i].to_int()
        buf.write_string("\{n}")
      }
      buf.write_string(" })")
    }
    // PKL-119a: PCF round-trips `Pair(a, b)` through Apple Pkl's
    // constructor form. Element values flow through `render_pcf_inline`
    // so nested composites stay valid PCF (`Pair(new { x = 1 }, 2)`).
    PairValue(first, second) => {
      buf.write_string("Pair(")
      render_pcf_inline(first, 0, buf)
      buf.write_string(", ")
      render_pcf_inline(second, 0, buf)
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
        render_pcf_inline(elements[i], 0, buf)
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
        render_pcf_inline(elements[i], 0, buf)
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
        render_pcf_inline(entries[i].key, 0, buf)
        buf.write_string(", ")
        render_pcf_inline(entries[i].value, 0, buf)
      }
      buf.write_char(')')
    }
    ObjectValue(_) | ListingValue(_) | MappingValue(_) =>
      // Defensive: callers should route block values through
      // render_pcf_inline / render_pcf_block_body. Falling back keeps
      // diagnostics non-empty if we ever miss a case.
      render_pcf_inline(value, 0, buf)
  }
}

///|
fn render_pcf_inline(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  if pcf_is_block_value(value) {
    buf.write_string("new ")
    render_pcf_block_body(value, indent, buf)
  } else if indent > 0 && value is StringValue(s) && s.contains("\n") {
    // PKL-148al: block-position StringValue with at least one newline
    // renders as a PCF triple-quoted heredoc. Apple Pkl emits the
    // opening `"""` on the current line, content lines at the same
    // indent as the opening for a bare element, and the closing
    // `"""` at the same indent. inline-position contexts (indent ==
    // 0, e.g. inside `List(...)` or `Pair(...)`) keep the
    // single-line escape form.
    render_pcf_string_heredoc(s, indent, buf)
  } else {
    render_pcf_scalar(value, buf)
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
  buf : StringBuilder,
) -> Unit {
  match value {
    ObjectValue([]) | ListingValue([]) | MappingValue([]) =>
      buf.write_string("{}")
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
      for field in visible {
        if field.name.has_prefix("@subscript$") {
          subscripts.push(field)
        } else if field.name.has_prefix("@element$") {
          elements.push(field)
        } else {
          named.push(field)
        }
      }
      let ordered : Array[ValueMember] = []
      for m in named {
        ordered.push(m)
      }
      for m in subscripts {
        ordered.push(m)
      }
      for m in elements {
        ordered.push(m)
      }
      buf.write_string("{\n")
      for i = 0; i < ordered.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_object_member(ordered[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    ListingValue(elements) => {
      buf.write_string("{\n")
      for i = 0; i < elements.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_inline(elements[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    MappingValue(entries) => {
      buf.write_string("{\n")
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_char('\n')
        }
        write_pcf_indent(buf, indent + 2)
        render_pcf_mapping_entry(entries[i], indent + 2, buf)
      }
      buf.write_char('\n')
      write_pcf_indent(buf, indent)
      buf.write_char('}')
    }
    _ => render_pcf_scalar(value, buf)
  }
}

///|
fn render_pcf_object_member(
  field : ValueMember,
  indent : Int,
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
    render_pcf_inline(field.value, indent, buf)
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
            render_pcf_inline(k, indent, buf)
            buf.write_char(']')
            if pcf_is_block_value(v) {
              buf.write_char(' ')
              render_pcf_block_body(v, indent, buf)
            } else {
              buf.write_string(" = ")
              render_pcf_scalar(v, buf)
            }
          }
          _ => ()
        }
      _ => ()
    }
    return
  }
  buf.write_string(field.name)
  if pcf_is_block_value(field.value) {
    buf.write_char(' ')
    render_pcf_block_body(field.value, indent, buf)
  } else if field.value is StringValue(s) && s.contains("\n") {
    // PKL-148al: property value with a multi-line string projects as
    // a triple-quoted heredoc; opening `"""` follows the `= ` on the
    // current line, content lines and closing live at `indent + 2`.
    buf.write_string(" = ")
    render_pcf_string_heredoc(s, indent + 2, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(field.value, buf)
  }
}

///|
fn render_pcf_mapping_entry(
  entry : ValueEntry,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  buf.write_char('[')
  render_pcf_inline(entry.key, indent, buf)
  buf.write_char(']')
  if pcf_is_block_value(entry.value) {
    buf.write_char(' ')
    render_pcf_block_body(entry.value, indent, buf)
  } else if entry.value is StringValue(s) && s.contains("\n") {
    buf.write_string(" = ")
    render_pcf_string_heredoc(s, indent + 2, buf)
  } else {
    buf.write_string(" = ")
    render_pcf_scalar(entry.value, buf)
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
    if !is_invisible_member_name(field.name) {
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
fn render_pcf_module(members : Array[ValueMember], buf : StringBuilder) -> Unit {
  let omit_null = pcf_omit_null_properties(members)
  let visible = visible_members(members)
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
    render_pcf_object_member(visible[i], 0, buf)
    emitted = emitted + 1
  }
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
