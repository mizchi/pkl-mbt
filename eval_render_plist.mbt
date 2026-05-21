///|
pub fn render_value_as_plist(value : Value) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  buf.write_string(
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n",
  )
  buf.write_string("<plist version=\"1.0\">\n")
  render_plist_value(value, 0, buf)
  buf.write_char('\n')
  buf.write_string("</plist>\n")
  buf.to_string()
}

///|
fn render_plist_value(value : Value, indent : Int, buf : StringBuilder) -> Unit {
  match value {
    IntValue(n) => {
      write_plist_indent(buf, indent)
      buf.write_string("<integer>\{n}</integer>")
    }
    FloatValue(d) => {
      write_plist_indent(buf, indent)
      buf.write_string("<real>\{render_float_text(d)}</real>")
    }
    BoolValue(true) => {
      write_plist_indent(buf, indent)
      buf.write_string("<true/>")
    }
    BoolValue(false) => {
      write_plist_indent(buf, indent)
      buf.write_string("<false/>")
    }
    NullValue => {
      // Top-level Null lands here too — emit an empty `<string/>`
      // shape so the output stays valid plist XML. Object / array
      // contexts intercept Null earlier and elide / error per the
      // upstream rule.
      write_plist_indent(buf, indent)
      buf.write_string("<string></string>")
    }
    DeferredImportValue(_) => {
      write_plist_indent(buf, indent)
      buf.write_string("<dict/>")
    }
    StringValue(s) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>")
      write_plist_escaped(s, buf)
      buf.write_string("</string>")
    }
    ObjectValue(members) => render_plist_dict_from_members(members, indent, buf)
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) =>
      render_plist_dict_from_entries(entries, indent, buf)
    ListingValue(elements)
    | DefaultedListingValue(_, elements, _)
    | ListValue(elements) => render_plist_array(elements, indent, buf)
    FunctionValue(_, _, _, _, _) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string></string>")
    }
    DurationValue(n, unit) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{n} \{unit}</string>")
    }
    DataSizeValue(n, unit) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{n} \{unit}</string>")
    }
    RegexValue(pattern) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>")
      write_plist_escaped(pattern, buf)
      buf.write_string("</string>")
    }
    BytesValue(bytes) => {
      write_plist_indent(buf, indent)
      buf.write_string("<string>\{@base64.encode(bytes[:])}</string>")
    }
    // PKL-119a: Pair renders as a 2-element `<array>`; reuse the
    // listing path so element indent / null handling stay consistent
    // with sibling collections.
    PairValue(first, second) => render_plist_array([first, second], indent, buf)
    // PKL-119b: IntSeq materializes and reuses the plist `<array>`
    // path so the rendered shape matches a hand-written Listing of
    // the same elements.
    IntSeqValue(start, end_v, step) =>
      render_plist_array(intseq_materialize(start, end_v, step), indent, buf)
    // PKL-119c: Set reuses the same `<array>` path.
    SetValue(elements) => render_plist_array(elements, indent, buf)
    // PKL-119d: Map reuses the mapping-entries `<dict>` path.
    MapValue(entries) => render_plist_dict_from_entries(entries, indent, buf)
  }
}

///|
fn render_plist_dict_from_members(
  members : Array[ValueMember],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let visible = visible_members(members)
  // Apple's `omitNullProperties` default is `true`; skip Null entries
  // before the dict envelope so an all-Null object renders as an
  // empty `<dict/>`.
  let kept : Array[ValueMember] = []
  for field in visible {
    if !(field.value is NullValue) {
      kept.push(field)
    }
  }
  write_plist_indent(buf, indent)
  if kept.length() == 0 {
    buf.write_string("<dict/>")
    return
  }
  buf.write_string("<dict>")
  for field in kept {
    buf.write_char('\n')
    write_plist_indent(buf, indent + 2)
    buf.write_string("<key>")
    write_plist_escaped(field.name, buf)
    buf.write_string("</key>")
    buf.write_char('\n')
    render_plist_value(field.value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</dict>")
}

///|
fn render_plist_dict_from_entries(
  entries : Array[ValueEntry],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let kept : Array[ValueEntry] = []
  for entry in entries {
    if !(entry.value is NullValue) {
      kept.push(entry)
    }
  }
  write_plist_indent(buf, indent)
  if kept.length() == 0 {
    buf.write_string("<dict/>")
    return
  }
  buf.write_string("<dict>")
  for entry in kept {
    buf.write_char('\n')
    write_plist_indent(buf, indent + 2)
    buf.write_string("<key>")
    write_plist_escaped(plist_coerce_key(entry.key), buf)
    buf.write_string("</key>")
    buf.write_char('\n')
    render_plist_value(entry.value, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</dict>")
}

///|
fn render_plist_array(
  elements : Array[Value],
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  write_plist_indent(buf, indent)
  if elements.length() == 0 {
    buf.write_string("<array/>")
    return
  }
  buf.write_string("<array>")
  for element in elements {
    if element is NullValue {
      continue
    }
    buf.write_char('\n')
    render_plist_value(element, indent + 2, buf)
  }
  buf.write_char('\n')
  write_plist_indent(buf, indent)
  buf.write_string("</array>")
}

///|
fn write_plist_indent(buf : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write_char(' ')
  }
}

///|
fn write_plist_escaped(value : String, buf : StringBuilder) -> Unit {
  for c in value {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(c)
    }
  }
}

///|
fn plist_coerce_key(value : Value) -> String {
  match value {
    StringValue(s) => s
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NullValue => "null"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(value, 0, buf)
      buf.to_string()
    }
  }
}

///|
/// Render a Value as a Java Properties document, mirroring the shape of
/// `pkl eval -f properties`.
///
/// Top-level Object / Mapping members flatten into dotted keys. Scalars emit
/// as `key = value` lines (unquoted, with property-style escaping for `\`,
/// `\n`, `\t`, `\r`, `\f`, leading space, `:`, `=`, `!`, `#`). Null leaves
/// are omitted (Apple Pkl's `omitNullProperties` default is `true`). Listings
/// render as a compact JSON-style single-line value (`[1,2,3]`), and the
/// JSON form's own `:` separators are then property-escaped to `\:`. Empty
/// Object / Mapping leaves are dropped entirely; empty Listings still emit
/// `key = []`. Top-level non-mapping values produce an empty document.
///
/// Apple Pkl's `restrictCharset = true` mode (emit `\uXXXX` for non-ASCII)
/// remains a follow-up — the default is `false` here, so unicode passes
/// through verbatim.
