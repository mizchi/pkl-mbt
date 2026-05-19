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
    // PKL-148: pkl:base Set surface — `add` / `every` / `any` /
    // `firstOrNull` / `getOrNull` / `count`.
    | "add"
    | "every"
    | "any"
    | "none"
    | "firstOrNull"
    | "lastOrNull"
    | "count"
    | "toList"
    | "toListing"
    | "toSet"
    | "map"
    | "filter"
    | "fold"
    | "join" => true
    _ => false
  }
}

///|
/// PKL-119d: method names dispatched off a `MapValue` target. Apple
/// Pkl's `Map<K, V>` class is read-mostly; this slice covers the
/// lookup methods (`getOrNull` / `containsKey` / `getOrThrow`),
/// projection helpers (`toMap` / `toMapping` / `toList`), and the
/// higher-order surface (`map` / `filter` / `fold`). The mutation
/// methods (`put` / `remove`) are intentionally elided — Apple Pkl's
/// signatures return new Maps rather than mutating, but their
/// implementations involve key-equality semantics we already cover
/// via the entry-walker so the slice can pick them up later without
/// further model changes.
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
    | "filter"
    | "fold"
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
/// PKL-146: convert a `moonbit-community/yaml` `Yaml` value into the
/// corresponding Pkl `Value`. `use_mapping` controls how YAML maps
/// project — `true` → `MappingValue` (key as `StringValue`); `false`
/// → `ObjectValue` (Dynamic shape, the default). Numbers: YAML
/// `Real(d)` becomes Pkl `IntValue` when integral + Int32-bounded
/// else `FloatValue` (same rule as the JSON path); YAML `Integer`
/// clamps Int64 → Int32 and falls back to FloatValue when out of
/// range so no value silently truncates. `BadValue` projects as
/// `NullValue` — the upstream `yaml` package emits it for parse
/// inputs the loader couldn't classify.
fn yaml_to_value(y : @yaml.Yaml, use_mapping : Bool) -> Value {
  match y {
    Null => NullValue
    Boolean(b) => BoolValue(b)
    Integer(i) => IntValue(i)
    Real(d, ..) => {
      // PKL-150: Pkl `Int` is i64. Widen to full Int64 range; falls
      // back to FloatValue only when truly out of range or non-integral.
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
        elements.push(yaml_to_value(item, use_mapping))
      }
      ListingValue(elements)
    }
    Map(map) =>
      if use_mapping {
        let entries : Array[ValueEntry] = []
        for k, v in map {
          entries.push({ key: StringValue(k), value: yaml_to_value(v, true) })
        }
        MappingValue(entries)
      } else {
        let members : Array[ValueMember] = []
        for k, v in map {
          members.push({
            name: k,
            value: yaml_to_value(v, false),
            source: None,
            annotations: [],
          })
        }
        ObjectValue(members)
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
/// Number of elements an IntSeq with the given start/end/step would
/// produce. Computed in Int64 so that ranges that span the full Int32
/// width (`IntSeq(math.minInt, math.maxInt)`) don't overflow.
fn intseq_length(start : Int64, end_v : Int64, step : Int64) -> Int64 {
  if step > 0L {
    if start > end_v {
      return 0L
    }
    return (end_v - start) / step + 1L
  }
  if step < 0L {
    if start < end_v {
      return 0L
    }
    return (start - end_v) / -step + 1L
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
    (SetValue(xs), SetValue(ys)) => set_values_equal(xs, ys)
    (ListingValue(xs), ListingValue(ys)) => value_arrays_equal(xs, ys)
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
