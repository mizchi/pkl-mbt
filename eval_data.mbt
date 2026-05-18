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
    | "fold" => true
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
      let truncated = d.to_int().to_double()
      if truncated == d && d >= -2147483648.0 && d <= 2147483647.0 {
        IntValue(d.to_int())
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
          members.push({ name: k, value: json_to_value(v, false), source: None })
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
    Integer(i) =>
      if i >= -2147483648L && i <= 2147483647L {
        IntValue(i.to_int())
      } else {
        FloatValue(i.to_double())
      }
    Real(d, ..) => {
      let truncated = d.to_int().to_double()
      if truncated == d && d >= -2147483648.0 && d <= 2147483647.0 {
        IntValue(d.to_int())
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
          members.push({ name: k, value: yaml_to_value(v, false), source: None })
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
fn intseq_materialize(start : Int, end_v : Int, step : Int) -> Array[Value] {
  // PKL-148am: iterate in Int64 so `start + step` cannot wrap.
  // Previously the loop var was Int (i32); with a fixture like
  // `IntSeq(math.maxInt, math.minInt).step(math.minInt)` the i32
  // `i + step` wrapped from -1 back to maxInt on the third step
  // and the while-condition (i >= end_v) stayed true forever, so
  // `result.push` grew the array past memory and the runtime
  // crashed with `invalid memory access`. Int64 has enough head /
  // tailroom (~64 bits vs. the i32 range each operand sits in) that
  // a single add never overflows, and the directional check (next
  // moved the wrong way) catches the boundary case where step is
  // 0 (caller already rejects) or somehow non-monotone.
  let result : Array[Value] = []
  let end64 = end_v.to_int64()
  let step64 = step.to_int64()
  if step > 0 {
    let mut i = start.to_int64()
    while i <= end64 {
      result.push(IntValue(i.to_int()))
      let next = i + step64
      if next <= i {
        break
      }
      i = next
    }
  } else if step < 0 {
    let mut i = start.to_int64()
    while i >= end64 {
      result.push(IntValue(i.to_int()))
      let next = i + step64
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
fn intseq_length(start : Int, end_v : Int, step : Int) -> Int64 {
  let s = start.to_int64()
  let e = end_v.to_int64()
  let st = step.to_int64()
  if st > 0L {
    if s > e {
      return 0L
    }
    return (e - s) / st + 1L
  }
  if st < 0L {
    if s < e {
      return 0L
    }
    return (s - e) / -st + 1L
  }
  0L
}

///|
/// Visible-member equality for ObjectValue operands. Compares only
/// rendered (non-hidden) properties and ignores order so
/// `{foo=1; bar=2} == {bar=2; foo=1}` agrees with Apple Pkl.
fn object_values_equal(
  xs : Array[ValueMember],
  ys : Array[ValueMember],
) -> Bool {
  let visible_xs = visible_members(xs)
  let visible_ys = visible_members(ys)
  if visible_xs.length() != visible_ys.length() {
    return false
  }
  for x in visible_xs {
    let mut matched = false
    for y in visible_ys {
      if y.name == x.name && y.value == x.value {
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
      if !consumed[j] && ys[j].key == x.key && ys[j].value == x.value {
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
      if !consumed[j] && ys[j] == x {
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
  start_a : Int,
  end_a : Int,
  step_a : Int,
  start_b : Int,
  end_b : Int,
  step_b : Int,
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
