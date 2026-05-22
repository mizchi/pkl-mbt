///|
fn is_listing_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: PKL-base Listing properties — `isNotEmpty`, `isDistinct`,
    // `firstOrNull`, `lastOrNull`, `toList`, `toSet`. Apple Pkl projects
    // them as zero-arg property reads (no parens) since the underlying
    // method has no parameters.
    | "isNotEmpty"
    | "isDistinct"
    | "firstOrNull"
    | "lastOrNull"
    | "restOrNull"
    | "singleOrNull"
    | "toList"
    | "toSet"
    | "toListing"
    | "first"
    | "last"
    | "distinct"
    // PKL-151: pkl:base Listing/List extra property surface from
    // api/list.pkl. `single` raises unless length == 1; `rest` drops
    // the head; `lastIndex` is `length - 1`. `min` / `max` raise on
    // empty or non-comparable inputs.
    | "single"
    | "rest"
    | "lastIndex"
    | "min"
    | "max"
    | "minOrNull"
    | "maxOrNull"
    // PKL-151: read-only conversions Apple Pkl exposes as properties.
    | "flatten"
    | "filterNonNull" => true
    _ => false
  }
}

///|
fn is_listing_method_name(name : String) -> Bool {
  match name {
    "contains"
    | "fold"
    | "map"
    | "filter"
    | "take"
    | "drop"
    | "join"
    | "reverse"
    // PKL-148: pkl:base Listing surface — `getOrNull(idx)`,
    // `startsWith(other)`, `endsWith(other)`, `min` / `max` / `sum`.
    | "getOrNull"
    | "getOrDefault"
    | "startsWith"
    | "endsWith"
    // PKL-148b: Listing.isDistinctBy(keyFn) — checks whether elements
    // are unique under the key extractor.
    | "isDistinctBy"
    // PKL-134: read-only conversion methods used by pkf / pkspec's
    // shape inspection chains (`tests.toList().map(...)`).
    | "toList"
    | "toMap"
    // PKL-135: predicate / search / flatten methods used by pkspec's
    // `tagSteps`, `duplicateNames`, and rendered Mapping projections.
    | "flatMap"
    | "count"
    | "every"
    | "any"
    | "none"
    | "find"
    | "findOrNull"
    | "findLast"
    | "findLastOrNull"
    | "indexOfOrNull"
    | "lastIndexOfOrNull"
    | "findIndexOrNull"
    | "findLastIndexOrNull"
    // Apple Pkl exposes the no-arg surface (`toSet`, `toListing`,
    // `first`, `last`, `firstOrNull`, `lastOrNull`, `distinct`,
    // `isEmpty`, `isNotEmpty`, `isDistinct`) as both property reads
    // and method calls; accept the `()` form too so fixtures like
    // `list.toSet()` route through the method dispatcher.
    | "toSet"
    | "toListing"
    | "first"
    | "last"
    | "firstOrNull"
    | "lastOrNull"
    | "restOrNull"
    | "singleOrNull"
    | "distinct"
    | "isEmpty"
    | "isNotEmpty"
    | "isDistinct"
    // PKL-151: extended Listing method surface from api/list.pkl.
    | "single"
    | "rest"
    | "lastIndex"
    | "min"
    | "max"
    | "minOrNull"
    | "maxOrNull"
    | "flatten"
    | "filterNonNull"
    | "sort"
    | "sortBy"
    | "sortWith"
    | "minBy"
    | "maxBy"
    | "minByOrNull"
    | "maxByOrNull"
    | "minWith"
    | "maxWith"
    | "minWithOrNull"
    | "maxWithOrNull"
    | "distinctBy"
    | "indexOf"
    | "lastIndexOf"
    | "findIndex"
    | "findLastIndex"
    | "takeWhile"
    | "takeLast"
    | "takeLastWhile"
    | "dropWhile"
    | "dropLast"
    | "dropLastWhile"
    | "repeat"
    | "reduce"
    | "reduceOrNull"
    | "foldBack"
    | "groupBy"
    | "partition"
    | "split"
    | "splitOrNull"
    | "sublistOrNull"
    | "replace"
    | "replaceOrNull"
    | "replaceRange"
    | "replaceRangeOrNull"
    | "add"
    | "zip"
    | "filterIndexed"
    | "mapIndexed"
    | "foldIndexed"
    | "flatMapIndexed"
    | "mapNonNull"
    | "mapNonNullIndexed"
    | "filterIsInstance"
    | "toDynamic"
    | "toBytes" => true
    _ => false
  }
}

///|
fn eval_listing_property(
  elements : Array[Value],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(elements.length().to_int64()))
    "isEmpty" => Some(BoolValue(elements.length() == 0))
    "isNotEmpty" => Some(BoolValue(elements.length() != 0))
    "isDistinct" => {
      let seen : Array[Value] = []
      let mut distinct = true
      for v in elements {
        if contains_value(seen, v) {
          distinct = false
          break
        }
        seen.push(v)
      }
      Some(BoolValue(distinct))
    }
    "firstOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        value_or_top_level_deferred_diagnostic(elements[0], diagnostics)
      }
    "lastOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        value_or_top_level_deferred_diagnostic(
          elements[elements.length() - 1],
          diagnostics,
        )
      }
    "restOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(ListingValue(list_slice(elements, 1, elements.length())))
      }
    "singleOrNull" =>
      if elements.length() == 1 {
        Some(elements[0])
      } else {
        Some(NullValue)
      }
    // PKL-148h: `.toList()` tags as `ListValue` (round-trips through
    // the `List(...)` constructor form); `.toListing()` keeps the
    // Listing block tag. `.toSet` deduplicates and tags as Set.
    "toList" => {
      match first_deferred_error_message(ListingValue(elements)) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      Some(ListValue(elements))
    }
    "toListing" => Some(ListingValue(elements))
    "toSet" => {
      let seen : Array[Value] = []
      for v in elements {
        if !contains_value(seen, v) {
          seen.push(v)
        }
      }
      Some(SetValue(seen))
    }
    "first" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Expected a non-empty Listing."))
        None
      } else {
        value_or_top_level_deferred_diagnostic(elements[0], diagnostics)
      }
    "last" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Expected a non-empty Listing."))
        None
      } else {
        value_or_top_level_deferred_diagnostic(
          elements[elements.length() - 1],
          diagnostics,
        )
      }
    "distinct" => {
      let seen : Array[Value] = []
      for v in elements {
        if !contains_value(seen, v) {
          seen.push(v)
        }
      }
      Some(ListingValue(seen))
    }
    // PKL-151: `single` returns the only element; raises on length != 1.
    "single" =>
      if elements.length() == 1 {
        Some(elements[0])
      } else {
        diagnostics.push(diag("Expected a single-element Listing."))
        None
      }
    // PKL-151: `rest` drops the head element. Empty input raises.
    "rest" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Cannot take the rest of an empty collection."))
        None
      } else {
        let out : Array[Value] = []
        for i = 1; i < elements.length(); i = i + 1 {
          out.push(elements[i])
        }
        Some(ListingValue(out))
      }
    // PKL-151: `lastIndex` mirrors Apple Pkl's `length - 1` semantics
    // (returns `-1` on empty input, the same convention `String` uses).
    "lastIndex" => Some(IntValue((elements.length() - 1).to_int64()))
    // PKL-151: `min` / `max` use Pkl ordering — Int/Float/String all
    // support `<` / `>` via the value model's compare operator. Empty
    // input raises.
    "min" =>
      if elements.length() == 0 {
        diagnostics.push(diag(collection_non_empty_message(elements)))
        None
      } else {
        let mut acc = elements[0]
        for i = 1; i < elements.length(); i = i + 1 {
          let cmp = compare_values(elements[i], acc)
          if cmp == incomparable_value_ordering_sentinel() {
            diagnostics.push(
              diag(
                undefined_operator_for_operand_types_message(
                  LessThan,
                  elements[i],
                  acc,
                ),
              ),
            )
            return None
          }
          if cmp < 0 {
            acc = elements[i]
          }
        }
        Some(acc)
      }
    "max" =>
      if elements.length() == 0 {
        diagnostics.push(diag(collection_non_empty_message(elements)))
        None
      } else {
        let mut acc = elements[0]
        for i = 1; i < elements.length(); i = i + 1 {
          let cmp = compare_values(elements[i], acc)
          if cmp == incomparable_value_ordering_sentinel() {
            diagnostics.push(
              diag(
                undefined_operator_for_operand_types_message(
                  GreaterThan,
                  elements[i],
                  acc,
                ),
              ),
            )
            return None
          }
          if cmp > 0 {
            acc = elements[i]
          }
        }
        Some(acc)
      }
    "minOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        eval_listing_property(elements, "min", diagnostics)
      }
    "maxOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        eval_listing_property(elements, "max", diagnostics)
      }
    // PKL-151: `flatten` concatenates the inner Listing/List elements
    // into a single Listing. Non-collection elements are an error.
    "flatten" => {
      let out : Array[Value] = []
      for v in elements {
        match v {
          ListingValue(xs) | ListValue(xs) | SetValue(xs) =>
            for x in xs {
              out.push(x)
            }
          _ => {
            diagnostics.push(
              diag(
                "Listing.flatten expects each element to be a Listing / List / Set.",
              ),
            )
            return None
          }
        }
      }
      Some(ListingValue(out))
    }
    // PKL-151: `filterNonNull` strips NullValue elements.
    "filterNonNull" => {
      let out : Array[Value] = []
      for v in elements {
        if !(v is NullValue) {
          out.push(v)
        }
      }
      Some(ListingValue(out))
    }
    _ => None
  }
}

///|
fn incomparable_value_ordering_sentinel() -> Int {
  -2
}

///|
/// PKL-151: compare two scalar values for ordering. Returns -1 / 0 / +1.
/// Mismatched types raise via -2 sentinel; callers should diagnostic +
/// bail. Only the comparable scalars Apple Pkl supports for min / max
/// (Int / Float / String / Duration / DataSize) are handled; anything
/// else is treated as "incomparable" and bails.
fn compare_values(a : Value, b : Value) -> Int {
  match (a, b) {
    (IntValue(x), IntValue(y)) => if x < y { -1 } else if x > y { 1 } else { 0 }
    (FloatValue(x), FloatValue(y)) =>
      if x < y {
        -1
      } else if x > y {
        1
      } else {
        0
      }
    (IntValue(x), FloatValue(y)) => {
      let xf = x.to_double()
      if xf < y {
        -1
      } else if xf > y {
        1
      } else {
        0
      }
    }
    (FloatValue(x), IntValue(y)) => {
      let yf = y.to_double()
      if x < yf {
        -1
      } else if x > yf {
        1
      } else {
        0
      }
    }
    (StringValue(x), StringValue(y)) => x.lexical_compare(y)
    (DurationValue(xv, xu), DurationValue(yv, yu)) => {
      // Normalize to nanoseconds via the existing helper for ordering.
      let xn = duration_to_ns(xv, xu)
      let yn = duration_to_ns(yv, yu)
      if xn < yn {
        -1
      } else if xn > yn {
        1
      } else {
        0
      }
    }
    (DataSizeValue(xv, xu), DataSizeValue(yv, yu)) => {
      let xn = datasize_to_bytes(xv, xu)
      let yn = datasize_to_bytes(yv, yu)
      if xn < yn {
        -1
      } else if xn > yn {
        1
      } else {
        0
      }
    }
    _ => incomparable_value_ordering_sentinel()
  }
}

///|
fn pkl_bool_return_type_message(value : Value) -> String {
  "Expected value of type `Boolean`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}"
}

///|
fn pkl_collection_return_type_message(value : Value) -> String {
  "Expected value of type `Collection`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}"
}

///|
fn list_slice(elements : Array[Value], start : Int, end : Int) -> Array[Value] {
  let out : Array[Value] = []
  for i = start; i < end; i = i + 1 {
    out.push(elements[i])
  }
  out
}

///|
fn collection_index_range_message(
  index : Int64,
  lower : Int,
  upper : Int,
  elements : Array[Value],
) -> String {
  "Element index `\{index}` is out of range `\{lower}`..`\{upper}`. Collection: \{render_pcf_value_inline(ListValue(elements))}"
}

///|
fn collection_non_empty_message(elements : Array[Value]) -> String {
  "Expected a non-empty collection. Collection: \{render_pcf_value_inline(ListValue(elements))}"
}

///|
fn unique_values(values : Array[Value]) -> Array[Value] {
  let out : Array[Value] = []
  for value in values {
    if !contains_value(out, value) {
      out.push(value)
    }
  }
  out
}

///|
fn dynamic_from_elements(elements : Array[Value]) -> Value {
  let members : Array[ValueMember] = []
  for i = 0; i < elements.length(); i = i + 1 {
    members.push({
      name: "@element$\{i}",
      value: elements[i],
      source: None,
      annotations: [],
    })
  }
  ObjectValue(tag_object_with_class(members, "Dynamic"))
}

///|
fn sort_with_comparator(
  elements : Array[Value],
  comparator : Value,
  context : String,
  bindings : Array[Binding],
  env : Array[ValueBinding],
  class_env : Array[ClassBinding],
  cache : Array[ValueBinding],
  stack : Array[String],
  declarations : Array[Declaration],
  diagnostics : Array[Diagnostic],
  resolve_import : (String) -> EvalResult?,
) -> Array[Value]? {
  let out = elements[:].to_owned()
  for i = 1; i < out.length(); i = i + 1 {
    let cur = out[i]
    let mut j = i - 1
    while j >= 0 {
      let before = match
        apply_function_value(
          "\{context} comparator",
          comparator,
          [cur, out[j]],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(BoolValue(b)) => b
        Some(IntValue(n)) => n < 0L
        Some(_) => {
          diagnostics.push(
            diag("\{context} comparator must return Boolean or Int"),
          )
          return None
        }
        None => return None
      }
      if !before {
        break
      }
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = cur
  }
  Some(out)
}

///|
/// PKL-151: nanosecond projection of a Duration magnitude+unit pair.
/// Walks the unit ladder so intermediate products stay in Double.
fn duration_to_ns(magnitude : Double, unit : String) -> Double {
  let level = duration_unit_level(unit)
  let mut acc = magnitude
  let mut i = level
  while i > 0 {
    acc = acc * duration_step_factor(i).to_double()
    i = i - 1
  }
  acc
}

///|
/// PKL-151: byte projection of a DataSize magnitude+unit pair.
fn datasize_to_bytes(magnitude : Double, unit : String) -> Double {
  let factor = datasize_byte_factor(unit)
  if factor < 0.0 {
    magnitude
  } else {
    magnitude * factor
  }
}

///|
/// PKL-148bb: a List receiver should keep its `List(...)` constructor
/// shape across method calls that preserve the collection shape
/// (`.map`, `.filter`, `.reverse`, etc.). The shared dispatcher
/// (`eval_listing_method`) emits `ListingValue` uniformly; wrap the
/// returned value to lift it back to `ListValue` for List receivers.
fn eval_list_or_listing_method(
  receiver_is_list : Bool,
  elements : Array[Value],
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
  let result = eval_listing_method(
    elements, method_name, arguments, bindings, env, class_env, cache, stack, declarations,
    diagnostics, resolve_import,
  )
  if receiver_is_list {
    match result {
      Some(ListingValue(xs)) if method_name == "toListing" =>
        Some(ListingValue(xs))
      Some(ListingValue(xs)) => Some(ListValue(xs))
      other => other
    }
  } else {
    result
  }
}

///|
fn eval_listing_method(
  elements : Array[Value],
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
    "contains" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.contains expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(BoolValue(contains_value(elements, arg_values[0])))
    }
    "isDistinctBy" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.isDistinctBy expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let keys : Array[Value] = []
      let mut distinct = true
      for element in elements {
        match
          apply_function_value(
            "Listing.isDistinctBy keyFn",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(key) =>
            if contains_value(keys, key) {
              distinct = false
              break
            } else {
              keys.push(key)
            }
          None => return None
        }
      }
      Some(BoolValue(distinct))
    }
    // PKL-148: pkl:base Listing.getOrNull(index) — returns the element
    // at `index` or null when out of bounds. Apple Pkl's signature is
    // `(Int) -> T?`.
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.getOrNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx64) => {
          let idx = idx64.to_int()
          if idx64 >= 0L && idx < elements.length() {
            Some(elements[idx])
          } else {
            Some(NullValue)
          }
        }
        _ => {
          diagnostics.push(diag("Listing.getOrNull expects an Int index"))
          None
        }
      }
    }
    "getOrDefault" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.getOrDefault expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(idx64) => {
          let idx = idx64.to_int()
          if idx64 >= 0L && idx < elements.length() {
            Some(elements[idx])
          } else {
            Some(NullValue)
          }
        }
        _ => {
          diagnostics.push(diag("Listing.getOrDefault expects an Int index"))
          None
        }
      }
    }
    // PKL-148: pkl:base Listing.startsWith(other) / endsWith(other) —
    // structural prefix / suffix match against another Listing.
    "startsWith" | "endsWith" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        ListingValue(other)
        | DefaultedListingValue(_, other, _)
        | ListValue(other)
        | SetValue(other) =>
          if other.length() > elements.length() {
            Some(BoolValue(false))
          } else {
            let offset = if method_name == "startsWith" {
              0
            } else {
              elements.length() - other.length()
            }
            let mut equal = true
            for i = 0; i < other.length(); i = i + 1 {
              if elements[i + offset] != other[i] {
                equal = false
                break
              }
            }
            Some(BoolValue(equal))
          }
        _ => {
          diagnostics.push(
            diag("Listing.\{method_name} expects a Listing argument"),
          )
          None
        }
      }
    }
    "reverse" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.reverse expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let reversed : Array[Value] = []
      let mut i = elements.length() - 1
      while i >= 0 {
        reversed.push(elements[i])
        i = i - 1
      }
      Some(ListingValue(reversed))
    }
    "take" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.take expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > elements.length() {
            elements.length()
          } else {
            raw_i
          }
          let result : Array[Value] = []
          for i = 0; i < n; i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(diag("Listing.take expects Int argument"))
          None
        }
      }
    }
    "drop" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.drop expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > elements.length() {
            elements.length()
          } else {
            raw_i
          }
          let result : Array[Value] = []
          for i = n; i < elements.length(); i = i + 1 {
            result.push(elements[i])
          }
          Some(ListingValue(result))
        }
        _ => {
          diagnostics.push(diag("Listing.drop expects Int argument"))
          None
        }
      }
    }
    "join" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.join expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(sep) => {
          let buf = StringBuilder::new()
          for i = 0; i < elements.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(sep)
            }
            buf.write_string(value_to_string_for_join(elements[i]))
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(diag("Listing.join expects String separator"))
          None
        }
      }
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.map callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => result.push(v)
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.filter predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(element)
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Listing.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for element in elements {
        match
          apply_function_value(
            "Listing.fold combine",
            callback,
            [acc, element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    // PKL-148h: `.toList()` on a Listing returns a `ListValue` so the
    // renderer projects through the `List(...)` constructor form. The
    // arity guard is preserved from the PKL-134 implementation. `.toMap`
    // on a Listing without Pair entries is the empty map — matches
    // Apple Pkl's behaviour when the Listing is not a Listing-of-Pair.
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Listing.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match first_deferred_error_message(ListingValue(elements)) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      Some(ListValue(elements))
    }
    "toBytes" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.toBytes expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      build_bytes_from_int_listing(elements, diagnostics)
    }
    "toMap" =>
      if arg_values.length() == 0 {
        Some(MappingValue([]))
      } else if arg_values.length() == 2 {
        let entries : Array[ValueEntry] = []
        for element in elements {
          let key = match
            apply_function_value(
              "Listing.toMap keyFn",
              arg_values[0],
              [element],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(v) => v
            None => return None
          }
          let value = match
            apply_function_value(
              "Listing.toMap valueFn",
              arg_values[1],
              [element],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(v) => v
            None => return None
          }
          entries.push({ key, value })
        }
        Some(MapValue(entries))
      } else {
        diagnostics.push(
          diag(
            "Listing.toMap expects 0 or 2 arguments, got \{arg_values.length()}",
          ),
        )
        None
      }
    // PKL-135: flatMap concatenates the listing results of each element's
    // transform call. Upstream allows Collection<Result> (List | Listing | Set);
    // pkl-mbt collapses those into ListingValue, so the shape stays consistent.
    "flatMap" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.flatMap expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.flatMap callback",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(ListingValue(inner))
          | Some(DefaultedListingValue(_, inner, _))
          | Some(ListValue(inner))
          | Some(SetValue(inner)) =>
            for v in inner {
              result.push(v)
            }
          Some(value) => {
            diagnostics.push(diag(pkl_collection_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(result))
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for element in elements {
        match
          apply_function_value(
            "Listing.count predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => n = n + 1
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n.to_int64()))
    }
    "every" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.every expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.every predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => ()
          Some(BoolValue(false)) => return Some(BoolValue(false))
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "any" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.any expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.any predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(true))
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(false))
    }
    "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.none expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.none predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(BoolValue(false))
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "find" | "findOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      for element in elements {
        match
          apply_function_value(
            "Listing.\{method_name} predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(element)
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      // Apple Pkl: `find` throws when no match, `findOrNull` returns null.
      if method_name == "findOrNull" {
        Some(NullValue)
      } else {
        diagnostics.push(diag("Listing.find did not match any element"))
        None
      }
    }
    "findLast" | "findLastOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut i = elements.length() - 1
      while i >= 0 {
        let element = elements[i]
        match
          apply_function_value(
            "Listing.\{method_name} predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => return Some(element)
          Some(BoolValue(false)) => ()
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
        i = i - 1
      }
      if method_name == "findLastOrNull" {
        Some(NullValue)
      } else {
        diagnostics.push(diag("Listing.findLast did not match any element"))
        None
      }
    }
    // PKL-151: indexOf(elem) / lastIndexOf(elem) — return position of
    // a structurally-equal element; raise on miss.
    "indexOf" | "lastIndexOf" | "indexOfOrNull" | "lastIndexOfOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let needle = arg_values[0]
      let mut found = -1
      if method_name == "indexOf" || method_name == "indexOfOrNull" {
        for i = 0; i < elements.length(); i = i + 1 {
          if elements[i] == needle {
            found = i
            break
          }
        }
      } else {
        let mut i = elements.length() - 1
        while i >= 0 {
          if elements[i] == needle {
            found = i
            break
          }
          i = i - 1
        }
      }
      if found < 0 {
        if method_name == "indexOfOrNull" || method_name == "lastIndexOfOrNull" {
          return Some(NullValue)
        }
        diagnostics.push(diag("Element not found in Listing."))
        None
      } else {
        Some(IntValue(found.to_int64()))
      }
    }
    // PKL-151: findIndex(pred) / findLastIndex(pred) — predicate
    // sibling of indexOf; raises on no match.
    "findIndex" | "findLastIndex" | "findIndexOrNull" | "findLastIndexOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let pred = arg_values[0]
      let walk_forward = method_name == "findIndex" ||
        method_name == "findIndexOrNull"
      let mut found = -1
      let range = if walk_forward {
        let r : Array[Int] = []
        for i = 0; i < elements.length(); i = i + 1 {
          r.push(i)
        }
        r
      } else {
        let r : Array[Int] = []
        let mut i = elements.length() - 1
        while i >= 0 {
          r.push(i)
          i = i - 1
        }
        r
      }
      for i in range {
        match
          apply_function_value(
            "Listing.\{method_name} pred",
            pred,
            [elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => {
            found = i
            break
          }
          Some(BoolValue(false)) => continue
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      if found < 0 {
        if method_name == "findIndexOrNull" ||
          method_name == "findLastIndexOrNull" {
          return Some(NullValue)
        }
        diagnostics.push(
          diag("Listing.\{method_name} did not match any element"),
        )
        None
      } else {
        Some(IntValue(found.to_int64()))
      }
    }
    // PKL-151: sortBy / minBy / maxBy / distinctBy — extract a key,
    // then compare on the key (Pkl ordering for Int / Float / String /
    // Duration / DataSize).
    "sortBy" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.sortBy expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key_fn = arg_values[0]
      let keys : Array[Value] = []
      for e in elements {
        match
          apply_function_value(
            "Listing.sortBy keyFn",
            key_fn,
            [e],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => keys.push(v)
          None => return None
        }
      }
      let indexed : Array[(Int, Value)] = []
      for i = 0; i < elements.length(); i = i + 1 {
        indexed.push((i, keys[i]))
      }
      // Simple insertion sort — Listings in practice stay small.
      for i = 1; i < indexed.length(); i = i + 1 {
        let cur = indexed[i]
        let mut j = i - 1
        while j >= 0 {
          let cmp = compare_values(indexed[j].1, cur.1)
          if cmp == incomparable_value_ordering_sentinel() {
            diagnostics.push(
              diag(
                undefined_operator_for_operand_types_message(
                  GreaterThan,
                  indexed[j].1,
                  cur.1,
                ),
              ),
            )
            return None
          }
          if cmp <= 0 {
            break
          }
          indexed[j + 1] = indexed[j]
          j = j - 1
        }
        indexed[j + 1] = cur
      }
      let out : Array[Value] = []
      for pair in indexed {
        out.push(elements[pair.0])
      }
      Some(ListingValue(out))
    }
    "sortWith" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.sortWith expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match
        sort_with_comparator(
          elements,
          arg_values[0],
          "Listing.sortWith",
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(out) => Some(ListingValue(out))
        None => None
      }
    }
    "minWith" | "maxWith" | "minWithOrNull" | "maxWithOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      if elements.length() == 0 {
        if method_name == "minWithOrNull" || method_name == "maxWithOrNull" {
          return Some(NullValue)
        }
        diagnostics.push(diag(collection_non_empty_message(elements)))
        return None
      }
      match
        sort_with_comparator(
          elements,
          arg_values[0],
          "Listing.\{method_name}",
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(out) =>
          if method_name == "maxWith" || method_name == "maxWithOrNull" {
            Some(out[out.length() - 1])
          } else {
            Some(out[0])
          }
        None => None
      }
    }
    "minBy" | "maxBy" | "minByOrNull" | "maxByOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      if elements.length() == 0 {
        if method_name == "minByOrNull" || method_name == "maxByOrNull" {
          return Some(NullValue)
        }
        diagnostics.push(diag(collection_non_empty_message(elements)))
        return None
      }
      let key_fn = arg_values[0]
      let pick_max = method_name == "maxBy" || method_name == "maxByOrNull"
      let mut best_idx = 0
      let mut best_key = match
        apply_function_value(
          "Listing.\{method_name} keyFn",
          key_fn,
          [elements[0]],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(v) => v
        None => return None
      }
      for i = 1; i < elements.length(); i = i + 1 {
        let k = match
          apply_function_value(
            "Listing.\{method_name} keyFn",
            key_fn,
            [elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => v
          None => return None
        }
        let cmp = compare_values(k, best_key)
        if cmp == incomparable_value_ordering_sentinel() {
          let op = if pick_max { GreaterThan } else { LessThan }
          diagnostics.push(
            diag(undefined_operator_for_operand_types_message(op, k, best_key)),
          )
          return None
        }
        if pick_max {
          if cmp > 0 {
            best_idx = i
            best_key = k
          }
        } else if cmp < 0 {
          best_idx = i
          best_key = k
        }
      }
      Some(elements[best_idx])
    }
    "distinctBy" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.distinctBy expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let key_fn = arg_values[0]
      let keys : Array[Value] = []
      let out : Array[Value] = []
      for e in elements {
        let k = match
          apply_function_value(
            "Listing.distinctBy keyFn",
            key_fn,
            [e],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => v
          None => return None
        }
        if !contains_value(keys, k) {
          keys.push(k)
          out.push(e)
        }
      }
      Some(ListingValue(out))
    }
    // PKL-151: sort() — zero-arg ascending sort using `compare_values`.
    "sort" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Listing.sort expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let out = elements[:].to_owned()
      for i = 1; i < out.length(); i = i + 1 {
        let cur = out[i]
        let mut j = i - 1
        while j >= 0 {
          let cmp = compare_values(out[j], cur)
          if cmp == incomparable_value_ordering_sentinel() {
            diagnostics.push(
              diag(
                undefined_operator_for_operand_types_message(
                  LessThan,
                  cur,
                  out[j],
                ),
              ),
            )
            return None
          }
          if cmp <= 0 {
            break
          }
          out[j + 1] = out[j]
          j = j - 1
        }
        out[j + 1] = cur
      }
      Some(ListingValue(out))
    }
    // PKL-151: takeWhile / dropWhile and their `*Last*` variants —
    // walk from the start (or end) while the predicate holds.
    "takeWhile" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.takeWhile expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let pred = arg_values[0]
      let out : Array[Value] = []
      for e in elements {
        match
          apply_function_value(
            "Listing.takeWhile pred",
            pred,
            [e],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => out.push(e)
          Some(BoolValue(false)) => break
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(ListingValue(out))
    }
    "dropWhile" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.dropWhile expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let pred = arg_values[0]
      let out : Array[Value] = []
      let mut dropping = true
      for e in elements {
        if dropping {
          match
            apply_function_value(
              "Listing.dropWhile pred",
              pred,
              [e],
              bindings,
              env,
              class_env,
              cache,
              stack,
              declarations,
              diagnostics,
              resolve_import,
            ) {
            Some(BoolValue(true)) => continue
            Some(BoolValue(false)) => {
              dropping = false
              out.push(e)
            }
            Some(value) => {
              diagnostics.push(diag(pkl_bool_return_type_message(value)))
              return None
            }
            None => return None
          }
        } else {
          out.push(e)
        }
      }
      Some(ListingValue(out))
    }
    "takeLast" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.takeLast expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > elements.length() {
            elements.length()
          } else {
            raw_i
          }
          let out : Array[Value] = []
          for i = elements.length() - n; i < elements.length(); i = i + 1 {
            out.push(elements[i])
          }
          Some(ListingValue(out))
        }
        _ => {
          diagnostics.push(diag("Listing.takeLast expects Int argument"))
          None
        }
      }
    }
    "dropLast" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.dropLast expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(raw) => {
          let raw_i = raw.to_int()
          let n = if raw < 0L {
            0
          } else if raw_i > elements.length() {
            elements.length()
          } else {
            raw_i
          }
          let out : Array[Value] = []
          for i = 0; i < elements.length() - n; i = i + 1 {
            out.push(elements[i])
          }
          Some(ListingValue(out))
        }
        _ => {
          diagnostics.push(diag("Listing.dropLast expects Int argument"))
          None
        }
      }
    }
    // PKL-151: repeat(n) — concat self `n` times. Negative `n` raises.
    "repeat" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.repeat expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(n) =>
          if n < 0L {
            diagnostics.push(
              diag("Expected a positive number, but got `\{n}`."),
            )
            None
          } else {
            let out : Array[Value] = []
            for _ in 0..<n.to_int() {
              for e in elements {
                out.push(e)
              }
            }
            Some(ListingValue(out))
          }
        _ => {
          diagnostics.push(diag("Listing.repeat expects Int argument"))
          None
        }
      }
    }
    // PKL-151: add(elem) / replace(idx, elem) — non-mutating returns.
    "add" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.add expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let out = elements[:].to_owned()
      out.push(arg_values[0])
      Some(ListingValue(out))
    }
    "replace" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Listing.replace expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(i64) => {
          let i = i64.to_int()
          if i64 < 0L || i >= elements.length() {
            diagnostics.push(
              diag(
                collection_index_range_message(
                  i64,
                  0,
                  elements.length() - 1,
                  elements,
                ),
              ),
            )
            None
          } else {
            let out = elements[:].to_owned()
            out[i] = arg_values[1]
            Some(ListingValue(out))
          }
        }
        _ => {
          diagnostics.push(diag("Listing.replace expects (Int, T) arguments"))
          None
        }
      }
    }
    // PKL-151: mapNonNull(fn) — map then strip nulls.
    "mapNonNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.mapNonNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let fn_v = arg_values[0]
      let out : Array[Value] = []
      for e in elements {
        match
          apply_function_value(
            "Listing.mapNonNull fn",
            fn_v,
            [e],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(NullValue) => continue
          Some(v) => out.push(v)
          None => return None
        }
      }
      Some(ListingValue(out))
    }
    "takeLastWhile" | "dropLastWhile" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let pred = arg_values[0]
      let mut cut = elements.length()
      let mut i = elements.length() - 1
      while i >= 0 {
        match
          apply_function_value(
            "Listing.\{method_name} pred",
            pred,
            [elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => {
            cut = i
            i = i - 1
          }
          Some(BoolValue(false)) => break
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      if method_name == "takeLastWhile" {
        Some(ListingValue(list_slice(elements, cut, elements.length())))
      } else {
        Some(ListingValue(list_slice(elements, 0, cut)))
      }
    }
    "foldBack" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Listing.foldBack expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let callback = arg_values[1]
      let mut acc = arg_values[0]
      let mut i = elements.length() - 1
      while i >= 0 {
        match
          apply_function_value(
            "Listing.foldBack combine",
            callback,
            [elements[i], acc],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
        i = i - 1
      }
      Some(acc)
    }
    "reduce" | "reduceOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      if elements.length() == 0 {
        if method_name == "reduceOrNull" {
          return Some(NullValue)
        }
        diagnostics.push(diag(collection_non_empty_message(elements)))
        return None
      }
      let callback = arg_values[0]
      let mut acc = elements[0]
      for i = 1; i < elements.length(); i = i + 1 {
        match
          apply_function_value(
            "Listing.\{method_name} combine",
            callback,
            [acc, elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    "groupBy" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.groupBy expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let entries : Array[ValueEntry] = []
      for element in elements {
        let key = match
          apply_function_value(
            "Listing.groupBy keyFn",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => v
          None => return None
        }
        let mut found = false
        for i = 0; i < entries.length(); i = i + 1 {
          if values_equal(entries[i].key, key) {
            match entries[i].value {
              ListValue(xs) => {
                let grouped : Array[Value] = xs[:].to_owned()
                grouped.push(element)
                entries[i] = { key: entries[i].key, value: ListValue(grouped) }
              }
              _ => ()
            }
            found = true
            break
          }
        }
        if !found {
          entries.push({ key, value: ListValue([element]) })
        }
      }
      Some(MapValue(entries))
    }
    "replaceRange" | "replaceRangeOrNull" => {
      if arg_values.length() != 3 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 3 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1], arg_values[2]) {
        (IntValue(start64), IntValue(end64), ListValue(replacement))
        | (IntValue(start64), IntValue(end64), ListingValue(replacement))
        | (IntValue(start64), IntValue(end64), SetValue(replacement)) => {
          let start = start64.to_int()
          let end = end64.to_int()
          if start64 < 0L {
            if method_name == "replaceRangeOrNull" {
              return Some(NullValue)
            }
            diagnostics.push(
              diag(
                collection_index_range_message(
                  start64,
                  0,
                  elements.length(),
                  elements,
                ),
              ),
            )
            return None
          }
          if end64 > elements.length().to_int64() || start > end {
            if method_name == "replaceRangeOrNull" {
              return Some(NullValue)
            }
            diagnostics.push(
              diag(
                collection_index_range_message(
                  end64,
                  start,
                  elements.length(),
                  elements,
                ),
              ),
            )
            return None
          }
          let out : Array[Value] = []
          for i = 0; i < start; i = i + 1 {
            out.push(elements[i])
          }
          for v in replacement {
            out.push(v)
          }
          for i = end; i < elements.length(); i = i + 1 {
            out.push(elements[i])
          }
          Some(ListingValue(out))
        }
        _ => {
          diagnostics.push(
            diag(
              "Listing.\{method_name} expects (Int, Int, Collection) arguments",
            ),
          )
          None
        }
      }
    }
    "replaceOrNull" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Listing.replaceOrNull expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(i64) => {
          let i = i64.to_int()
          if i64 < 0L || i >= elements.length() {
            Some(NullValue)
          } else {
            let out = elements[:].to_owned()
            out[i] = arg_values[1]
            Some(ListingValue(out))
          }
        }
        _ => {
          diagnostics.push(
            diag("Listing.replaceOrNull expects (Int, T) arguments"),
          )
          None
        }
      }
    }
    "sublistOrNull" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Listing.sublistOrNull expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match (arg_values[0], arg_values[1]) {
        (IntValue(start64), IntValue(end64)) => {
          let start = start64.to_int()
          let end = end64.to_int()
          if start64 < 0L || end64 > elements.length().to_int64() || start > end {
            Some(NullValue)
          } else {
            Some(ListingValue(list_slice(elements, start, end)))
          }
        }
        _ => {
          diagnostics.push(
            diag("Listing.sublistOrNull expects (Int, Int) arguments"),
          )
          None
        }
      }
    }
    "split" | "splitOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match arg_values[0] {
        IntValue(index64) => {
          let index = index64.to_int()
          if index64 < 0L || index > elements.length() {
            if method_name == "splitOrNull" {
              return Some(NullValue)
            }
            diagnostics.push(
              diag(
                collection_index_range_message(
                  index64,
                  0,
                  elements.length(),
                  elements,
                ),
              ),
            )
            return None
          }
          Some(
            PairValue(
              ListValue(list_slice(elements, 0, index)),
              ListValue(list_slice(elements, index, elements.length())),
            ),
          )
        }
        _ => {
          diagnostics.push(diag("Listing.\{method_name} expects Int argument"))
          None
        }
      }
    }
    "partition" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.partition expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let yes : Array[Value] = []
      let no : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Listing.partition predicate",
            arg_values[0],
            [element],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => yes.push(element)
          Some(BoolValue(false)) => no.push(element)
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      Some(PairValue(ListValue(yes), ListValue(no)))
    }
    "zip" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Listing.zip expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let other = match arg_values[0] {
        ListValue(xs) | ListingValue(xs) | SetValue(xs) => xs
        _ => {
          diagnostics.push(diag("Listing.zip expects a Collection argument"))
          return None
        }
      }
      let out : Array[Value] = []
      let n = if elements.length() < other.length() {
        elements.length()
      } else {
        other.length()
      }
      for i = 0; i < n; i = i + 1 {
        out.push(PairValue(elements[i], other[i]))
      }
      Some(ListingValue(out))
    }
    "filterIndexed" | "mapIndexed" | "flatMapIndexed" | "mapNonNullIndexed" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let out : Array[Value] = []
      for i = 0; i < elements.length(); i = i + 1 {
        match
          apply_function_value(
            "Listing.\{method_name} callback",
            arg_values[0],
            [IntValue(i.to_int64()), elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(value) =>
            if method_name == "filterIndexed" {
              match value {
                BoolValue(true) => out.push(elements[i])
                BoolValue(false) => ()
                _ => {
                  diagnostics.push(diag(pkl_bool_return_type_message(value)))
                  return None
                }
              }
            } else if method_name == "flatMapIndexed" {
              match value {
                ListValue(xs) | ListingValue(xs) | SetValue(xs) =>
                  for v in xs {
                    out.push(v)
                  }
                _ => {
                  diagnostics.push(
                    diag(pkl_collection_return_type_message(value)),
                  )
                  return None
                }
              }
            } else if method_name == "mapNonNullIndexed" {
              if value != NullValue {
                out.push(value)
              }
            } else {
              out.push(value)
            }
          None => return None
        }
      }
      Some(ListingValue(out))
    }
    "foldIndexed" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag(
            "Listing.foldIndexed expects 2 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for i = 0; i < elements.length(); i = i + 1 {
        match
          apply_function_value(
            "Listing.foldIndexed combine",
            callback,
            [IntValue(i.to_int64()), acc, elements[i]],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(v) => acc = v
          None => return None
        }
      }
      Some(acc)
    }
    "filterIsInstance" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Listing.filterIsInstance expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let target = class_mirror_simple_name(arg_values[0])
      let out : Array[Value] = []
      for element in elements {
        let keep = match target {
          Some("Any") => true
          Some("Number") => element is IntValue(_) || element is FloatValue(_)
          Some("Int") => element is IntValue(_)
          Some("Float") => element is FloatValue(_)
          Some("String") => element is StringValue(_)
          Some("Boolean") => element is BoolValue(_)
          Some("List") => element is ListValue(_)
          Some("Listing") =>
            element is ListingValue(_) ||
            element is DefaultedListingValue(_, _, _)
          Some("Set") => element is SetValue(_)
          _ => false
        }
        if keep {
          out.push(element)
        }
      }
      Some(ListingValue(out))
    }
    "toDynamic" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.toDynamic expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(dynamic_from_elements(elements))
    }
    // Apple Pkl allows zero-arg property reads (e.g. `list.toSet`) to be
    // written as method calls (`list.toSet()`). Delegate the no-arg
    // surface back to the property evaluator so both forms agree.
    "toSet"
    | "toListing"
    | "first"
    | "last"
    | "firstOrNull"
    | "lastOrNull"
    | "distinct"
    | "isEmpty"
    | "isNotEmpty"
    | "isDistinct"
    | "single"
    | "rest"
    | "lastIndex"
    | "min"
    | "max"
    | "flatten"
    | "filterNonNull" =>
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Listing.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        None
      } else {
        eval_listing_property(elements, method_name, diagnostics)
      }
    _ => None
  }
}
