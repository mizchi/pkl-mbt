///|
/// PKL-119b: method names dispatched off an `IntSeqValue` target.
/// `step` is overloaded — it's also a property name returning the
/// carrier slot — so the CallExpr dispatcher checks the call form
/// (zero args ⇒ method call returning a new IntSeq).
fn is_intseq_method_name(name : String) -> Bool {
  match name {
    "step" | "toList" | "toListing" | "map" | "fold" => true
    _ => false
  }
}

///|
/// PKL-119c: method names dispatched off a `SetValue` target. The
/// method-side surface mirrors Apple Pkl's `Set` class — the binary
/// `union` / `intersection` / `difference` operators come in a
/// follow-up; this slice covers `.contains` plus the read-only
/// projections and the higher-order helpers shared with `Listing`.
fn is_set_method_name(name : String) -> Bool {
  match name {
    "contains"
    | "startsWith"
    | "endsWith"
    // PKL-148: pkl:base Set surface — `add` / `every` / `any` /
    // `firstOrNull` / `getOrNull` / `count`.
    | "add"
    | "every"
    | "any"
    | "none"
    | "firstOrNull"
    | "lastOrNull"
    | "restOrNull"
    | "singleOrNull"
    | "count"
    | "toList"
    | "toListing"
    | "toSet"
    | "map"
    | "filter"
    | "fold"
    | "join"
    | "sortWith"
    | "flatMap"
    | "flatten"
    | "rest"
    | "last"
    | "first"
    | "single"
    | "find"
    | "findOrNull"
    | "findLast"
    | "findLastOrNull"
    | "take"
    | "takeWhile"
    | "takeLast"
    | "takeLastWhile"
    | "drop"
    | "dropWhile"
    | "dropLast"
    | "dropLastWhile"
    | "foldBack"
    | "reduce"
    | "reduceOrNull"
    | "groupBy"
    | "intersect"
    | "difference"
    | "toMap"
    | "minWith"
    | "minWithOrNull"
    | "maxWith"
    | "maxWithOrNull"
    | "zip"
    | "filterIndexed"
    | "mapIndexed"
    | "mapNonNullIndexed"
    | "flatMapIndexed"
    | "foldIndexed"
    | "toDynamic"
    | "filterNonNull"
    | "mapNonNull"
    | "filterIsInstance"
    | "split"
    | "splitOrNull"
    | "partition"
    | "min"
    | "minOrNull"
    | "max"
    | "maxOrNull"
    | "minBy"
    | "minByOrNull"
    | "maxBy"
    | "maxByOrNull"
    | "sort"
    | "sortBy"
    | "repeat"
    | "reverse" => true
    _ => false
  }
}

///|
/// PKL-119d: method names dispatched off a `MapValue` target. Apple
/// Pkl's `Map<K, V>` class is read-mostly; this slice covers the
/// lookup methods (`getOrNull` / `containsKey` / `getOrThrow`),
/// projection helpers (`toMap` / `toMapping` / `toList`), and the
/// higher-order surface (`map` / `filter` / `fold`). The mutation
/// mutating-style helpers (`put` / `remove`) return new Maps rather
/// than mutating the receiver.
fn is_map_method_name(name : String) -> Bool {
  match name {
    "containsKey"
    // PKL-148: pkl:base Map.containsValue(v) is the value-side parallel
    // of `containsKey` — Apple Pkl's fixture `api/map.pkl` exercises it.
    | "containsValue"
    | "getOrNull"
    | "getOrThrow"
    | "toMap"
    | "toMapping"
    | "toList"
    | "map"
    | "mapKeys"
    | "mapValues"
    | "flatMap"
    | "filter"
    | "fold"
    | "put"
    | "remove"
    | "toDynamic"
    | "toTyped"
    // PKL-148bb: Map shares the every / any / none predicate trio with
    // Mapping (`classes/mapConstraints1` exercises every on a Map).
    | "every"
    | "any"
    | "none" => true
    _ => false
  }
}

///|
/// PKL-144: convert a `@json.Json` value into the corresponding Pkl
/// `Value`. `use_mapping` controls how JSON objects project — `true`
/// → `MappingValue` (key as `StringValue`, matching Apple Pkl's
/// `Parser { useMapping = true }` mode); `false` → `ObjectValue`
/// (one property per JSON entry, the Dynamic shape Apple Pkl uses
/// by default). Numbers convert to Int when integral, Float
/// otherwise — matches the upstream rule that JSON `42` evaluates
/// to a Pkl `Int` and `42.5` to a `Float`.
fn json_to_value(j : Json, use_mapping : Bool) -> Value {
  match j {
    Null => NullValue
    True => BoolValue(true)
    False => BoolValue(false)
    Number(d, ..) => {
      // PKL-150: Pkl's `Int` is i64. Widen the JSON Number → IntValue
      // round-trip to the full Int64 range; values outside fall back
      // to FloatValue. Previously clamped to i32.
      let truncated = d.to_int64().to_double()
      if truncated == d &&
        d >= -9223372036854775808.0 &&
        d <= 9223372036854775807.0 {
        IntValue(d.to_int64())
      } else {
        FloatValue(d)
      }
    }
    String(s) => StringValue(s)
    Array(items) => {
      let elements : Array[Value] = []
      for item in items {
        elements.push(json_to_value(item, use_mapping))
      }
      ListingValue(elements)
    }
    Object(map) =>
      if use_mapping {
        let entries : Array[ValueEntry] = []
        for k, v in map {
          entries.push({ key: StringValue(k), value: json_to_value(v, true) })
        }
        MappingValue(entries)
      } else {
        let members : Array[ValueMember] = []
        for k, v in map {
          members.push({
            name: k,
            value: json_to_value(v, false),
            source: None,
            annotations: [],
          })
        }
        ObjectValue(members)
      }
  }
}

///|
/// PKL-144 / PKL-145: read the `useMapping` slot from a pkl:json /
/// pkl:yaml Parser mirror. Each Parser is identified via the hidden
/// `__kind = "<JsonParser|YamlParser>"` marker stamped by the
/// synthetic class (`reflect_kind` walks the same `__kind` member);
/// this helper only reads the toggle once the marker has been
/// matched.
fn parser_use_mapping(members : Array[ValueMember]) -> Bool {
  match lookup_member(members, "useMapping") {
    Some(BoolValue(b)) => b
    _ => false
  }
}

///|
fn parser_max_collection_aliases(members : Array[ValueMember]) -> Int {
  match lookup_member(members, "maxCollectionAliases") {
    Some(IntValue(n)) if n >= 0L => n.to_int()
    _ => 50
  }
}

///|
fn normalize_yaml_folded_block_chomping(source : String) -> String {
  // moonbit-community/yaml erases folded-vs-literal style in Yaml::String.
  // Apple Pkl's parser fixtures expect plain `>` to behave like `>-`, so
  // normalize the source before loading instead of post-processing every string.
  let buf = StringBuilder::new()
  let mut first = true
  for line in source.split("\n") {
    if first {
      first = false
    } else {
      buf.write_char('\n')
    }
    buf.write_string(rewrite_yaml_folded_block_indicator_line(line.to_owned()))
  }
  buf.to_string()
}

///|
fn rewrite_yaml_folded_block_indicator_line(line : String) -> String {
  let chars : Array[Char] = []
  for c in line {
    chars.push(c)
  }
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '>' &&
      yaml_is_folded_block_indicator_position(chars, i) &&
      !yaml_block_indicator_has_chomping(chars, i) {
      let buf = StringBuilder::new()
      for j = 0; j < chars.length(); j = j + 1 {
        buf.write_char(chars[j])
        if j == i {
          buf.write_char('-')
        }
      }
      return buf.to_string()
    }
  }
  line
}

///|
fn yaml_is_folded_block_indicator_position(
  chars : Array[Char],
  index : Int,
) -> Bool {
  let mut prev = index - 1
  while prev >= 0 && (chars[prev] == ' ' || chars[prev] == '\t') {
    prev = prev - 1
  }
  prev < 0 || chars[prev] == ':' || chars[prev] == '-'
}

///|
fn yaml_block_indicator_has_chomping(chars : Array[Char], index : Int) -> Bool {
  let mut i = index + 1
  while i < chars.length() {
    let c = chars[i]
    if c == '+' || c == '-' {
      return true
    }
    if c >= '0' && c <= '9' {
      i = i + 1
      continue
    }
    if c == ' ' || c == '\t' || c == '#' {
      return false
    }
    return true
  }
  false
}

///|
/// PKL-146: convert a `moonbit-community/yaml` `Yaml` value into the
/// corresponding Pkl `Value`. `use_mapping` controls how YAML maps
/// project — `true` → `MappingValue` (key as `StringValue`); `false`
/// → `ObjectValue` (Dynamic shape, the default). Numbers: YAML
/// `Integer` becomes Pkl `Int`, while YAML `Real` remains Pkl
/// `Float` even when the numeric value is integral (`450.00`),
/// matching Apple Pkl parser converters. `BadValue` projects as
/// `NullValue` — the upstream `yaml` package emits it for parse
/// inputs the loader couldn't classify.
priv struct YamlAliasRefs {
  array_refs : Array[(Array[@yaml.Yaml], Int, Int64)]
  map_refs : Array[(Map[String, @yaml.Yaml], Int, Int64)]
  mut next_id : Int64
}

///|
/// moonbit-community/yaml resolves aliases by reusing the same collection
/// object but drops the anchor id itself. Pre-scan collection refs so only
/// repeated maps receive an internal alias tag; independent equal maps stay
/// structurally equal and untagged.
fn yaml_alias_refs_for_documents(docs : Array[@yaml.Yaml]) -> YamlAliasRefs {
  let refs = YamlAliasRefs::{ array_refs: [], map_refs: [], next_id: 1L }
  for doc in docs {
    collect_yaml_alias_refs(doc, refs)
  }
  refs
}

///|
fn collect_yaml_alias_refs(y : @yaml.Yaml, refs : YamlAliasRefs) -> Unit {
  match y {
    Array(items) => {
      note_yaml_array_ref(refs, items)
      for item in items {
        collect_yaml_alias_refs(item, refs)
      }
    }
    Map(map) => {
      note_yaml_map_ref(refs, map)
      for _, value in map {
        collect_yaml_alias_refs(value, refs)
      }
    }
    _ => ()
  }
}

///|
fn note_yaml_array_ref(refs : YamlAliasRefs, items : Array[@yaml.Yaml]) -> Unit {
  for i = 0; i < refs.array_refs.length(); i = i + 1 {
    let entry = refs.array_refs[i]
    if physical_equal(entry.0, items) {
      refs.array_refs[i] = (entry.0, entry.1 + 1, entry.2)
      return
    }
  }
  let id = refs.next_id
  refs.next_id = refs.next_id + 1L
  refs.array_refs.push((items, 1, id))
}

///|
fn note_yaml_map_ref(
  refs : YamlAliasRefs,
  map : Map[String, @yaml.Yaml],
) -> Unit {
  for i = 0; i < refs.map_refs.length(); i = i + 1 {
    let entry = refs.map_refs[i]
    if physical_equal(entry.0, map) {
      refs.map_refs[i] = (entry.0, entry.1 + 1, entry.2)
      return
    }
  }
  let id = refs.next_id
  refs.next_id = refs.next_id + 1L
  refs.map_refs.push((map, 1, id))
}

///|
fn yaml_map_alias_id(
  refs : YamlAliasRefs,
  map : Map[String, @yaml.Yaml],
) -> Int64? {
  for entry in refs.map_refs {
    if entry.1 > 1 && physical_equal(entry.0, map) {
      return Some(entry.2)
    }
  }
  None
}

///|
fn yaml_collection_alias_count(refs : YamlAliasRefs) -> Int {
  let mut count = 0
  for entry in refs.array_refs {
    if entry.1 > 1 {
      count = count + entry.1 - 1
    }
  }
  for entry in refs.map_refs {
    if entry.1 > 1 {
      count = count + entry.1 - 1
    }
  }
  count
}

///|
fn yaml_alias_member_name() -> String {
  local_member_name("__yamlAnchorId")
}

///|
fn attach_yaml_alias_member(
  members : Array[ValueMember],
  id : Int64?,
) -> Array[ValueMember] {
  match id {
    Some(anchor_id) => {
      let out : Array[ValueMember] = [
        {
          name: yaml_alias_member_name(),
          value: IntValue(anchor_id),
          source: None,
          annotations: [],
        },
      ]
      for field in members {
        out.push(field)
      }
      out
    }
    None => members
  }
}

///|
fn yaml_to_value_with_aliases(
  y : @yaml.Yaml,
  use_mapping : Bool,
  refs : YamlAliasRefs,
) -> Value {
  match y {
    Null => NullValue
    Boolean(b) => BoolValue(b)
    Integer(i) => IntValue(i)
    Real(d, ..) => FloatValue(d)
    String(s) =>
      match yaml_v12_try_decode_binary_string(s) {
        Some(v) => v
        None => StringValue(s)
      }
    Array(items) => {
      let elements : Array[Value] = []
      for item in items {
        elements.push(yaml_to_value_with_aliases(item, use_mapping, refs))
      }
      ListingValue(elements)
    }
    Map(map) =>
      if yaml_v12_map_is_set(map) {
        // PKL-153c: `!!set` rewritten into a sentinel-marked map by
        // `yaml_v12_rewrite_set`. Project to a Listing of the (string)
        // keys to mirror Apple Pkl's `!!set` → Listing-of-keys rendering.
        let elements : Array[Value] = []
        for k, _ in map {
          if k == yaml_v12_set_marker_member {
            continue
          }
          elements.push(StringValue(k))
        }
        ListingValue(elements)
      } else if use_mapping {
        let entries : Array[ValueEntry] = []
        for k, v in map {
          entries.push({
            key: StringValue(k),
            value: yaml_to_value_with_aliases(v, true, refs),
          })
        }
        MappingValue(entries)
      } else {
        let members : Array[ValueMember] = []
        for k, v in map {
          members.push({
            name: k,
            value: yaml_to_value_with_aliases(v, false, refs),
            source: None,
            annotations: [],
          })
        }
        ObjectValue(
          attach_yaml_alias_member(members, yaml_map_alias_id(refs, map)),
        )
      }
    BadValue => NullValue
  }
}

///|
/// PKL-119b: materialize an IntSeq into an Array[Value] of Int
/// elements. Empty when `step > 0 && start > end` or
/// `step < 0 && start < end`; `step == 0` would be rejected by the
/// caller before reaching here (and is treated as empty here too as
/// a defensive guard).
fn intseq_materialize(
  start : Int64,
  end_v : Int64,
  step : Int64,
) -> Array[Value] {
  // PKL-148am / PKL-150: iterate in Int64 so `start + step` cannot wrap
  // even at the full Int range. Directional check (next moved the wrong
  // way) catches the boundary case where step is 0 (caller rejects
  // upstream) or somehow non-monotone.
  let result : Array[Value] = []
  if step > 0L {
    let mut i = start
    while i <= end_v {
      result.push(IntValue(i))
      let next = i + step
      if next <= i {
        break
      }
      i = next
    }
  } else if step < 0L {
    let mut i = start
    while i >= end_v {
      result.push(IntValue(i))
      let next = i + step
      if next >= i {
        break
      }
      i = next
    }
  }
  result
}

///|
fn bytes_materialize(bytes : Bytes) -> Array[Value] {
  let result : Array[Value] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    result.push(IntValue(bytes[i].to_int().to_int64()))
  }
  result
}

///|
/// Number of elements an IntSeq with the given start/end/step would
/// produce. Computed in Int64 so that ranges that span the full Int32
/// width (`IntSeq(math.minInt, math.maxInt)`) don't overflow.
fn intseq_length(start : Int64, end_v : Int64, step : Int64) -> Int64 {
  let int64_max = 9223372036854775807L
  let int64_min = 0L - int64_max - 1L
  let saturating_distance = fn(lo : Int64, hi : Int64) -> Int64 {
    if lo < 0L && hi > 0L {
      if lo == int64_min {
        return int64_max
      }
      let left = 0L - lo
      if int64_max - left < hi {
        int64_max
      } else {
        left + hi
      }
    } else {
      hi - lo
    }
  }
  let saturating_len = fn(distance : Int64, positive_step : Int64) -> Int64 {
    let q = distance / positive_step
    if q >= int64_max {
      int64_max
    } else {
      q + 1L
    }
  }
  if step > 0L {
    if start > end_v {
      return 0L
    }
    return saturating_len(saturating_distance(start, end_v), step)
  }
  if step < 0L {
    if start < end_v {
      return 0L
    }
    return saturating_len(saturating_distance(end_v, start), 0L - step)
  }
  0L
}

///|
/// Pkl value equality for collection membership and unordered content
/// comparisons. MoonBit's derived equality is fine for scalars, but
/// containers need Apple Pkl's visible-member / order-insensitive rules.
fn values_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (ObjectValue(xs), ObjectValue(ys)) => object_values_equal(xs, ys)
    (MapValue(xs), MapValue(ys)) => map_entries_equal(xs, ys)
    (MappingValue(xs), MappingValue(ys)) => map_entries_equal(xs, ys)
    (DefaultedMappingValue(_, xs, _), MappingValue(ys))
    | (MappingValue(xs), DefaultedMappingValue(_, ys, _))
    | (DefaultedMappingValue(_, xs, _), DefaultedMappingValue(_, ys, _)) =>
      map_entries_equal(xs, ys)
    (SetValue(xs), SetValue(ys)) => set_values_equal(xs, ys)
    (ListingValue(xs), ListingValue(ys)) => value_arrays_equal(xs, ys)
    (DefaultedListingValue(_, xs, _), ListingValue(ys))
    | (ListingValue(xs), DefaultedListingValue(_, ys, _))
    | (DefaultedListingValue(_, xs, _), DefaultedListingValue(_, ys, _)) =>
      value_arrays_equal(xs, ys)
    (ListValue(xs), ListValue(ys)) => value_arrays_equal(xs, ys)
    (IntSeqValue(s1, e1, st1), IntSeqValue(s2, e2, st2)) =>
      intseq_value_equal(s1, e1, st1, s2, e2, st2)
    _ => a == b
  }
}

///|
fn value_arrays_equal(xs : Array[Value], ys : Array[Value]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  for i = 0; i < xs.length(); i = i + 1 {
    if !values_equal(xs[i], ys[i]) {
      return false
    }
  }
  true
}

///|
/// Visible-member equality for ObjectValue operands. Compares only
/// rendered (non-hidden) properties and ignores order so
/// `{foo=1; bar=2} == {bar=2; foo=1}` agrees with Apple Pkl.
fn object_values_equal(
  xs : Array[ValueMember],
  ys : Array[ValueMember],
) -> Bool {
  if reflect_kind(xs) is Some("Module") && reflect_kind(ys) is Some("Module") {
    match (lookup_member(xs, "uri"), lookup_member(ys, "uri")) {
      (Some(StringValue(x_uri)), Some(StringValue(y_uri))) =>
        return x_uri == y_uri
      _ => ()
    }
  }
  match
    (
      hidden_string_member(xs, "__module_path"),
      hidden_string_member(ys, "__module_path"),
    ) {
    (Some(x_path), Some(y_path)) if x_path != y_path => return false
    _ => ()
  }
  // PKL-148bh: class identity is part of equality — `new Person {}`
  // and `new Person2 {}` carry distinct `@hidden$__class` tags so
  // they don't compare equal even though the visible-member arrays
  // are both empty. An untagged ObjectValue (bare object-literal
  // body like `(obj1) {}`) compares as `Dynamic` so `(obj1) {} ==
  // new Dynamic { foo = 1 }` still returns true when the visible
  // members align.
  let class_xs = match find_object_class_tag(xs) {
    Some(s) => s
    None => "Dynamic"
  }
  let class_ys = match find_object_class_tag(ys) {
    Some(s) => s
    None => "Dynamic"
  }
  if class_xs != class_ys {
    return false
  }
  let visible_xs = visible_members(xs)
  let visible_ys = visible_members(ys)
  if visible_xs.length() != visible_ys.length() {
    return false
  }
  for x in visible_xs {
    let mut matched = false
    for y in visible_ys {
      if y.name == x.name && values_equal(y.value, x.value) {
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
fn hidden_string_member(members : Array[ValueMember], name : String) -> String? {
  let hidden = hidden_member_name(name)
  for value_member in members {
    if value_member.name == hidden {
      match value_member.value {
        StringValue(value) => return Some(value)
        _ => return None
      }
    }
  }
  None
}

///|
/// Map / Mapping content equality — key/value order is immaterial; two
/// entries with the same key/value pair regardless of position match.
fn map_entries_equal(xs : Array[ValueEntry], ys : Array[ValueEntry]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let consumed : Array[Bool] = Array::make(ys.length(), false)
  for x in xs {
    let mut matched = false
    for j = 0; j < ys.length(); j = j + 1 {
      if !consumed[j] &&
        values_equal(ys[j].key, x.key) &&
        values_equal(ys[j].value, x.value) {
        consumed[j] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// Multiset equality for SetValue operands — Apple Pkl treats two Sets
/// as equal when they hold the same elements regardless of insertion
/// order. Quadratic, but Sets in practice are small.
fn set_values_equal(xs : Array[Value], ys : Array[Value]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let consumed : Array[Bool] = Array::make(ys.length(), false)
  for x in xs {
    let mut matched = false
    for j = 0; j < ys.length(); j = j + 1 {
      if !consumed[j] && values_equal(ys[j], x) {
        consumed[j] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// PKL-119be (IntSeq equality follow-up): two IntSeqs are equal when
/// they produce the same Int sequence. Compute lengths without
/// materializing — for arithmetic progressions equality reduces to
/// matching length, start, and step (step doesn't matter when len <= 1).
fn intseq_value_equal(
  start_a : Int64,
  end_a : Int64,
  step_a : Int64,
  start_b : Int64,
  end_b : Int64,
  step_b : Int64,
) -> Bool {
  if start_a == start_b && end_a == end_b && step_a == step_b {
    return true
  }
  let len_a = intseq_length(start_a, end_a, step_a)
  let len_b = intseq_length(start_b, end_b, step_b)
  if len_a != len_b {
    return false
  }
  if len_a == 0 {
    return true
  }
  if start_a != start_b {
    return false
  }
  if len_a == 1 {
    return true
  }
  step_a == step_b
}
