///|
fn is_mapping_property_name(name : String) -> Bool {
  match name {
    "length"
    | "isEmpty"
    // PKL-148: project the no-arg surface used by `.isNotEmpty` / `.entries`
    // / `.toMap` / `.toMapping` from pkl:base.
    | "isNotEmpty"
    | "entries"
    | "toMap"
    | "toMapping"
    | "keys"
    | "values" => true
    _ => false
  }
}

///|
fn is_mapping_method_name(name : String) -> Bool {
  match name {
    "containsKey"
    | "containsValue"
    | "getOrNull"
    | "getOrDefault"
    | "fold"
    // PKL-134: identity conversion methods used by pkf / pkspec.
    | "toMap"
    | "toList"
    // PKL-135: predicate methods. Upstream's Mapping.every/any/none take
    // `(Key, Value) -> Boolean`. count is upstream's `count((K, V) -> ...)`.
    | "every"
    | "any"
    | "none"
    | "count" => true
    _ => false
  }
}

///|
fn contains_entry_key(entries : Array[ValueEntry], key : Value) -> Bool {
  for entry in entries {
    if entry.key == key {
      return true
    }
  }
  false
}

///|
fn contains_value(xs : Array[Value], v : Value) -> Bool {
  for x in xs {
    if values_equal(x, v) {
      return true
    }
  }
  false
}

///|
fn set_collection_non_empty_message(elements : Array[Value]) -> String {
  "Expected a non-empty collection. Collection: \{render_pcf_value_inline(SetValue(elements))}"
}

///|
fn set_collection_index_range_message(
  index : Int64,
  lower : Int,
  upper : Int,
  elements : Array[Value],
) -> String {
  "Element index `\{index}` is out of range `\{lower}`..`\{upper}`. Collection: \{render_pcf_value_inline(SetValue(elements))}"
}

///|
fn first_top_level_pure_deferred_entry_message(
  entries : Array[ValueEntry],
) -> String? {
  for entry in entries {
    match entry.value {
      ObjectValue(members) if visible_members(members).length() == 0 =>
        match deferred_error_message(entry.value) {
          Some(message) => return Some(message)
          None => ()
        }
      _ => ()
    }
  } nobreak {
    None
  }
}

///|
fn value_to_string_for_join(v : Value) -> String {
  match v {
    IntValue(n) => "\{n}"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    StringValue(s) => s
    NullValue => "null"
    // PKL-148bh: container values render through the compact inline
    // form (one line, `;`-separated, leading `new <Class>`) so string
    // interpolation produces `new Listing { 1; 2; 3 }` rather than the
    // multi-line PCF block. `Dynamic` ObjectValues already carry the
    // `__class` tag for the Dynamic case; non-tagged Objects render
    // bare `new { ... }` for now (universal user-class tagging is
    // deferred — `basic/string` accepts the bare form for both
    // `Dynamic` and a user class in current gold).
    ObjectValue(members) =>
      match
        (lookup_member(members, "value"), lookup_member(members, "groups")) {
        (Some(StringValue(s)), Some(_)) => s
        _ => {
          let buf = StringBuilder::new()
          let class_name = match find_object_class_tag(members) {
            Some(name) => name
            None => ""
          }
          buf.write_string("new ")
          if class_name != "" {
            buf.write_string(class_name)
            buf.write_char(' ')
          }
          let visible = visible_members(members)
          if visible.length() == 0 {
            buf.write_string("{}")
          } else {
            buf.write_string("{ ")
            for i = 0; i < visible.length(); i = i + 1 {
              if i > 0 {
                buf.write_string("; ")
              }
              // PKL-148c: a property whose value is a Listing /
              // Mapping uses the implicit-body form (`names { ... }`)
              // rather than the explicit-assignment form (`names =
              // new Listing { ... }`). Matches Apple Pkl's
              // `reflect.Property.toString()` projection.
              match visible[i].value {
                ListingValue(elements)
                | DefaultedListingValue(_, elements, _)
                | ListValue(elements)
                | SetValue(elements) => {
                  buf.write_string(visible[i].name)
                  buf.write_string(" { ")
                  for j = 0; j < elements.length(); j = j + 1 {
                    if j > 0 {
                      buf.write_string("; ")
                    }
                    render_pcf_scalar(elements[j], buf)
                  }
                  buf.write_string(" }")
                }
                MappingValue(entries) | DefaultedMappingValue(_, entries, _)
                | MapValue(entries) => {
                  buf.write_string(visible[i].name)
                  buf.write_string(" { ")
                  for j = 0; j < entries.length(); j = j + 1 {
                    if j > 0 {
                      buf.write_string("; ")
                    }
                    buf.write_char('[')
                    render_pcf_scalar(entries[j].key, buf)
                    buf.write_string("] = ")
                    render_pcf_scalar(entries[j].value, buf)
                  }
                  buf.write_string(" }")
                }
                _ => {
                  buf.write_string(visible[i].name)
                  buf.write_string(" = ")
                  render_pcf_scalar(visible[i].value, buf)
                }
              }
            }
            buf.write_string(" }")
          }
          buf.to_string()
        }
      }
    ListingValue(elements) | DefaultedListingValue(_, elements, _) => {
      let buf = StringBuilder::new()
      buf.write_string("new Listing")
      if elements.length() == 0 {
        buf.write_string(" {}")
      } else {
        buf.write_string(" { ")
        for i = 0; i < elements.length(); i = i + 1 {
          if i > 0 {
            buf.write_string("; ")
          }
          render_pcf_scalar(elements[i], buf)
        }
        buf.write_string(" }")
      }
      buf.to_string()
    }
    MappingValue(entries) | DefaultedMappingValue(_, entries, _) => {
      let buf = StringBuilder::new()
      buf.write_string("new Mapping")
      if entries.length() == 0 {
        buf.write_string(" {}")
      } else {
        buf.write_string(" { ")
        for i = 0; i < entries.length(); i = i + 1 {
          if i > 0 {
            buf.write_string("; ")
          }
          buf.write_char('[')
          render_pcf_scalar(entries[i].key, buf)
          buf.write_string("] = ")
          render_pcf_scalar(entries[i].value, buf)
        }
        buf.write_string(" }")
      }
      buf.to_string()
    }
    // Apple Pkl renders function values as `new FunctionN {}` in
    // toString / interpolation contexts (N = arity).
    FunctionValue(parameters, _, _, _, _) =>
      "new Function\{parameters.length()} {}"
    _ => {
      let buf = StringBuilder::new()
      render_pcf_inline(v, 0, false, buf)
      buf.to_string()
    }
  }
}

///|
fn eval_mapping_property(
  entries : Array[ValueEntry],
  name : String,
  diagnostics : Array[Diagnostic],
) -> Value? {
  match name {
    "length" => Some(IntValue(entries.length().to_int64()))
    "isEmpty" => Some(BoolValue(entries.length() == 0))
    "isNotEmpty" => Some(BoolValue(entries.length() != 0))
    "keys" => {
      let keys : Array[Value] = []
      for entry in entries {
        keys.push(entry.key)
      }
      Some(SetValue(keys))
    }
    "values" => {
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(ListingValue(values))
    }
    "entries" => {
      // PKL-148: `Mapping.entries` projects to a Listing of
      // Pair<Key, Value> mirroring `Map.entries`.
      let pairs : Array[Value] = []
      for entry in entries {
        pairs.push(PairValue(entry.key, entry.value))
      }
      Some(ListingValue(pairs))
    }
    "toMap" => {
      // PKL-148: lift the Mapping into a Map value preserving order.
      let kvs : Array[ValueEntry] = []
      for entry in entries {
        kvs.push({ key: entry.key, value: entry.value })
      }
      Some(MapValue(kvs))
    }
    "toMapping" => Some(MappingValue(entries))
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{name}` in object of type `Mapping`."),
      )
      None
    }
  }
}

///|
/// PKL-119b: dispatch methods on an IntSeqValue. `step(newValue)`
/// returns a new IntSeq with the carrier step replaced; `toList`
/// materializes a `ListValue`, `toListing` materializes a
/// `ListingValue`; `map(f)` materializes then applies the lambda to
/// each element; `fold(initial, op)` reduces left-to-right.
fn eval_intseq_method(
  start : Int64,
  end_v : Int64,
  step : Int64,
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
    "step" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("IntSeq.step expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        IntValue(new_step) =>
          if new_step == 0L {
            diagnostics.push(
              diag("Type constraint `isNonZero` violated. Value: 0"),
            )
            None
          } else {
            Some(IntSeqValue(start, end_v, new_step))
          }
        _ => {
          diagnostics.push(diag("IntSeq.step expects Int"))
          None
        }
      }
    }
    "toList" | "toListing" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "IntSeq.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let elements = intseq_materialize(start, end_v, step)
      if method_name == "toList" {
        Some(ListValue(elements))
      } else {
        Some(ListingValue(elements))
      }
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("IntSeq.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let elements = intseq_materialize(start, end_v, step)
      let mapped : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "IntSeq.map callback",
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
          Some(v) => mapped.push(v)
          None => return None
        }
      }
      // Apple Pkl's IntSeq.map returns `List<T>` — the gold fixture
      // `basic/let`'s `res11 = IntSeq(1, 5).map(...)` renders through
      // the `List(3, 4, 5, 6, 7)` constructor form rather than a
      // Listing block.
      Some(ListValue(mapped))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("IntSeq.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let elements = intseq_materialize(start, end_v, step)
      for element in elements {
        match
          apply_function_value(
            "IntSeq.fold operator",
            arg_values[1],
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
    _ => {
      diagnostics.push(
        diag(
          "Cannot find property `\{method_name}` in object of type `IntSeq`.",
        ),
      )
      None
    }
  }
}

///|
/// PKL-119c: dispatch methods on a `SetValue`. `.contains(x)` reuses
/// the same value-equality helper as Listing; `.toList()` /
/// `.toListing()` materialise into a `ListingValue` (the two are
/// aliased until PKL-119d splits List / Map out); `.toSet()` is
/// identity since the receiver is already a Set; `.map` / `.filter`
/// / `.fold` / `.join` mirror the Listing surface but return into a
/// `ListingValue` (mapped Sets keep insertion order but the upstream
/// signature for `Set.map` is `Listing<Out>`, not `Set<Out>`).
fn eval_set_method(
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
  if method_name == "reduce" && elements.length() == 0 {
    diagnostics.push(diag(set_collection_non_empty_message(elements)))
    return None
  }
  if (method_name == "minBy" || method_name == "maxBy") &&
    elements.length() == 0 {
    diagnostics.push(diag(set_collection_non_empty_message(elements)))
    return None
  }
  if method_name == "split" {
    if arg_values.length() != 1 {
      diagnostics.push(
        diag("Set.split expects 1 argument, got \{arg_values.length()}"),
      )
      return None
    }
    match arg_values[0] {
      IntValue(index64) => {
        let index = index64.to_int()
        if index64 < 0L || index > elements.length() {
          diagnostics.push(
            diag(
              set_collection_index_range_message(
                index64,
                0,
                elements.length(),
                elements,
              ),
            ),
          )
          return None
        }
      }
      _ => ()
    }
  }
  match method_name {
    "contains" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.contains expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      Some(BoolValue(contains_value(elements, arg_values[0])))
    }
    // PKL-148: `Set.add(x)` returns a new Set with `x` appended (no-op
    // when the element already belongs). Apple Pkl's signature is
    // `add(Value) -> Set` — non-mutating.
    "add" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.add expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let next : Array[Value] = []
      for v in elements {
        next.push(v)
      }
      if !contains_value(next, arg_values[0]) {
        next.push(arg_values[0])
      }
      Some(SetValue(next))
    }
    "firstOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        value_or_deferred_diagnostic(elements[0], diagnostics)
      }
    "lastOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        value_or_deferred_diagnostic(
          elements[elements.length() - 1],
          diagnostics,
        )
      }
    "every" | "any" | "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Set.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut hit = false
      for element in elements {
        match
          apply_function_value(
            "Set.\{method_name} predicate",
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
          Some(BoolValue(true)) => {
            hit = true
            if method_name == "any" || method_name == "none" {
              break
            }
          }
          Some(BoolValue(false)) =>
            if method_name == "every" {
              return Some(BoolValue(false))
            }
          Some(value) => {
            diagnostics.push(diag(pkl_bool_return_type_message(value)))
            return None
          }
          None => return None
        }
      }
      match method_name {
        "every" => Some(BoolValue(true))
        "any" => Some(BoolValue(hit))
        "none" => Some(BoolValue(!hit))
        _ => None
      }
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for element in elements {
        match
          apply_function_value(
            "Set.count predicate",
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
    "toList" | "toListing" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag(
            "Set.\{method_name} expects 0 arguments, got \{arg_values.length()}",
          ),
        )
        return None
      }
      // PKL-148h: `Set.toList` → `ListValue`, `Set.toListing` →
      // `ListingValue`. Element order is preserved (Set walks in
      // insertion order, matching the Apple Pkl PCF projection).
      if method_name == "toList" {
        Some(ListValue(elements))
      } else {
        Some(ListingValue(elements))
      }
    }
    "toSet" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Set.toSet expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(SetValue(elements))
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Set.map callback",
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
      Some(SetValue(unique_values(result)))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[Value] = []
      for element in elements {
        match
          apply_function_value(
            "Set.filter predicate",
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
      Some(SetValue(result))
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Set.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      for element in elements {
        match
          apply_function_value(
            "Set.fold operator",
            arg_values[1],
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
    "join" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.join expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match arg_values[0] {
        StringValue(separator) => {
          let buf = StringBuilder::new()
          for i = 0; i < elements.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(separator)
            }
            match elements[i] {
              StringValue(s) => buf.write_string(s)
              other => render_pcf_inline(other, 0, false, buf)
            }
          }
          Some(StringValue(buf.to_string()))
        }
        _ => {
          diagnostics.push(diag("Set.join expects String separator"))
          None
        }
      }
    }
    "sortWith" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Set.sortWith expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      match
        sort_with_comparator(
          elements,
          arg_values[0],
          "Set.sortWith",
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(out) => Some(ListValue(out))
        None => None
      }
    }
    "maxWith" | "maxWithOrNull" => {
      let delegated_name = if method_name == "maxWithOrNull" {
        "maxWithOrNull"
      } else {
        "minWith"
      }
      eval_list_or_listing_method(
        false, elements, delegated_name, arguments, bindings, env, class_env, cache,
        stack, declarations, diagnostics, resolve_import,
      )
    }
    "intersect" | "difference" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Set.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let other = match arg_values[0] {
        SetValue(xs) | ListValue(xs) | ListingValue(xs) => xs
        _ => {
          diagnostics.push(
            diag("Set.\{method_name} expects a Collection argument"),
          )
          return None
        }
      }
      let out : Array[Value] = []
      if method_name == "intersect" {
        for element in elements {
          if contains_value(other, element) {
            out.push(element)
          }
        }
      } else {
        for element in elements {
          if !contains_value(other, element) {
            out.push(element)
          }
        }
      }
      Some(SetValue(out))
    }
    "toMap" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Set.toMap expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let entries : Array[ValueEntry] = []
      for element in elements {
        let key = match
          apply_function_value(
            "Set.toMap keyFn",
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
            "Set.toMap valueFn",
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
    }
    _ =>
      if is_listing_method_name(method_name) {
        match
          eval_list_or_listing_method(
            false, elements, method_name, arguments, bindings, env, class_env, cache,
            stack, declarations, diagnostics, resolve_import,
          ) {
          Some(ListingValue(xs)) =>
            match method_name {
              "sort" | "sortBy" | "sortWith" | "repeat" | "reverse" =>
                Some(ListValue(xs))
              "toListing" => Some(ListingValue(xs))
              _ => Some(SetValue(unique_values(xs)))
            }
          Some(ListValue(xs)) =>
            match method_name {
              "foldBack" => Some(ListValue(xs))
              "toList"
              | "sort"
              | "sortBy"
              | "sortWith"
              | "repeat"
              | "reverse" => Some(ListValue(xs))
              _ => Some(SetValue(unique_values(xs)))
            }
          Some(PairValue(ListValue(a), ListValue(b))) =>
            if method_name == "split" ||
              method_name == "splitOrNull" ||
              method_name == "partition" {
              Some(
                PairValue(
                  SetValue(unique_values(a)),
                  SetValue(unique_values(b)),
                ),
              )
            } else {
              Some(PairValue(ListValue(a), ListValue(b)))
            }
          Some(MapValue(entries)) if method_name == "groupBy" => {
            let converted : Array[ValueEntry] = []
            for entry in entries {
              match entry.value {
                ListValue(xs) =>
                  converted.push({
                    key: entry.key,
                    value: SetValue(unique_values(xs)),
                  })
                _ => converted.push(entry)
              }
            }
            Some(MapValue(converted))
          }
          other => other
        }
      } else {
        diagnostics.push(
          diag("Cannot find property `\{method_name}` in object of type `Set`."),
        )
        None
      }
  }
}

///|
/// PKL-119d: dispatch methods on a `MapValue`. The lookup methods
/// (`getOrNull` / `containsKey` / `getOrThrow`) use the same value-
/// equality helper as `contains_value` so any key type that derives
/// Eq works (Pkl supports arbitrary key types). Projection helpers
/// materialize into the matching variant — `.toMap` is identity,
/// `.toMapping` re-projects into the object-style `MappingValue`,
/// `.toList` walks the entries as `Listing<Pair<K, V>>`. `.map(f)`
/// expects a `(key, value) -> Pair<NewKey, NewValue>` lambda; for
/// the MVP we accept the upstream convention. `.filter` and `.fold`
/// mirror the same pattern as Listing / Set.
fn eval_map_method(
  entries : Array[ValueEntry],
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
    "containsKey" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.containsKey expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(BoolValue(true))
        }
      }
      Some(BoolValue(false))
    }
    "containsValue" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Map.containsValue expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let v = arg_values[0]
      for entry in entries {
        if entry.value == v {
          return Some(BoolValue(true))
        }
      }
      Some(BoolValue(false))
    }
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.getOrNull expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(entry.value)
        }
      }
      Some(NullValue)
    }
    "getOrThrow" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.getOrThrow expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let key = arg_values[0]
      for entry in entries {
        if entry.key == key {
          return Some(entry.value)
        }
      }
      diagnostics.push(diag("Map.getOrThrow: key not found"))
      None
    }
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MapValue(entries))
    }
    "toMapping" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toMapping expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MappingValue(entries))
    }
    "toDynamic" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toDynamic expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let members : Array[ValueMember] = []
      for entry in entries {
        match entry.key {
          StringValue(name) =>
            members.push({
              name,
              value: entry.value,
              source: None,
              annotations: [],
            })
          _ => ()
        }
      }
      Some(ObjectValue(tag_object_with_class(members, "Dynamic")))
    }
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Map.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let pairs : Array[Value] = []
      for entry in entries {
        pairs.push(PairValue(entry.key, entry.value))
      }
      Some(ListingValue(pairs))
    }
    "map" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.map expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.map callback",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(PairValue(new_key, new_value)) =>
            result.push({ key: new_key, value: new_value })
          Some(value) => {
            diagnostics.push(
              diag(
                "Expected value of type `Pair`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
              ),
            )
            return None
          }
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "mapKeys" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.mapKeys expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.mapKeys callback",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(new_key) => result.push({ key: new_key, value: entry.value })
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "mapValues" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.mapValues expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.mapValues callback",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(new_value) => result.push({ key: entry.key, value: new_value })
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "flatMap" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.flatMap expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.flatMap callback",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(MapValue(next_entries)) =>
            for next in next_entries {
              result.push(next)
            }
          Some(value) => {
            diagnostics.push(
              diag(
                "Expected value of type `Map`, but got type `\{eval_value_type_name(value)}`. Value: \{render_pcf_value_inline(value)}",
              ),
            )
            return None
          }
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "filter" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.filter expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        match
          apply_function_value(
            "Map.filter predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => result.push(entry)
          Some(BoolValue(false)) => ()
          Some(_) => {
            diagnostics.push(diag("Map.filter predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(MapValue(result))
    }
    "remove" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Map.remove expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      for entry in entries {
        if !values_equal(entry.key, arg_values[0]) {
          result.push(entry)
        }
      }
      Some(MapValue(result))
    }
    "put" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Map.put expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let result : Array[ValueEntry] = []
      let mut replaced = false
      for entry in entries {
        if values_equal(entry.key, arg_values[0]) {
          result.push({ key: arg_values[0], value: arg_values[1] })
          replaced = true
        } else {
          result.push(entry)
        }
      }
      if !replaced {
        result.push({ key: arg_values[0], value: arg_values[1] })
      }
      Some(MapValue(result))
    }
    "toTyped" => {
      if arguments.length() != 1 {
        diagnostics.push(
          diag("Map.toTyped expects 1 argument, got \{arguments.length()}"),
        )
        return None
      }
      match
        eval_expr_with_bindings(
          arguments[0],
          bindings,
          env,
          class_env,
          cache,
          stack,
          declarations,
          diagnostics,
          resolve_import,
        ) {
        Some(class_value) =>
          match
            (
              class_mirror_simple_name(class_value),
              class_mirror_display_name(class_value),
            ) {
            (Some(class_name), Some(display_name)) =>
              dynamic_members_to_typed_value(
                map_entries_to_dynamic_members(entries),
                class_name,
                display_name,
                bindings,
                env,
                class_env,
                cache,
                stack,
                declarations,
                diagnostics,
                resolve_import,
              )
            _ => {
              diagnostics.push(
                diag("Map.toTyped expects a Class mirror argument"),
              )
              None
            }
          }
        None => None
      }
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Map.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      for entry in entries {
        match
          apply_function_value(
            "Map.fold operator",
            arg_values[1],
            [acc, entry.key, entry.value],
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
    // PKL-148bb: Map mirrors Mapping's predicate trio. Each takes a
    // 2-arg lambda `(key, value) -> Boolean`. Used by class-property
    // constraints whose Map slot fires the `every(...)` cascade
    // (`classes/mapConstraints1`).
    "every" | "any" | "none" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Map.\{method_name} expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let mut hit = false
      let mut all = true
      for entry in entries {
        match
          apply_function_value(
            "Map.\{method_name} predicate",
            arg_values[0],
            [entry.key, entry.value],
            bindings,
            env,
            class_env,
            cache,
            stack,
            declarations,
            diagnostics,
            resolve_import,
          ) {
          Some(BoolValue(true)) => hit = true
          Some(BoolValue(false)) => all = false
          Some(_) => {
            diagnostics.push(
              diag("Map.\{method_name} predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
        if method_name == "any" && hit {
          return Some(BoolValue(true))
        }
        if method_name == "every" && !all {
          return Some(BoolValue(false))
        }
      }
      match method_name {
        "every" => Some(BoolValue(all))
        "any" => Some(BoolValue(hit))
        "none" => Some(BoolValue(!hit))
        _ => None
      }
    }
    "getOrDefault" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.getOrDefault expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match lookup_entry(entries, arg_values[0]) {
        Some(v) => Some(v)
        None => Some(NullValue)
      }
    }
    _ => {
      diagnostics.push(
        diag("Cannot find property `\{method_name}` in object of type `Map`."),
      )
      None
    }
  }
}

///|
fn eval_mapping_method(
  entries : Array[ValueEntry],
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
    "containsKey" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.containsKey expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      Some(BoolValue(contains_entry_key(entries, arg_values[0])))
    }
    "containsValue" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.containsValue expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(BoolValue(contains_value(values, arg_values[0])))
    }
    "getOrNull" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag(
            "Mapping.getOrNull expects 1 argument, got \{arg_values.length()}",
          ),
        )
        return None
      }
      match lookup_entry(entries, arg_values[0]) {
        Some(v) => Some(v)
        None => Some(NullValue)
      }
    }
    "fold" => {
      if arg_values.length() != 2 {
        diagnostics.push(
          diag("Mapping.fold expects 2 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let mut acc = arg_values[0]
      let callback = arg_values[1]
      for entry in entries {
        match
          apply_function_value(
            "Mapping.fold combine",
            callback,
            [acc, entry.key, entry.value],
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
    // PKL-134: identity conversion. toMap on a Mapping is self;
    // toList projects the entries' values (matching Apple Pkl's
    // `Map.values.toList()` shape closely enough for shape-only chains).
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Mapping.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      match first_top_level_pure_deferred_entry_message(entries) {
        Some(message) => {
          diagnostics.push(diag(message))
          return None
        }
        None => ()
      }
      let kvs : Array[ValueEntry] = []
      for entry in entries {
        kvs.push({ key: entry.key, value: entry.value })
      }
      Some(MapValue(kvs))
    }
    "toList" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Mapping.toList expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      let values : Array[Value] = []
      for entry in entries {
        values.push(entry.value)
      }
      Some(ListingValue(values))
    }
    // PKL-135: predicate methods. Upstream's signature is
    // `(Key, Value) -> Boolean` for every / any; pkl-mbt mirrors that.
    "every" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.every expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.every predicate",
            arg_values[0],
            [entry.key, entry.value],
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
          Some(_) => {
            diagnostics.push(
              diag("Mapping.every predicate must return Boolean"),
            )
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
          diag("Mapping.any expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.any predicate",
            arg_values[0],
            [entry.key, entry.value],
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
          Some(_) => {
            diagnostics.push(diag("Mapping.any predicate must return Boolean"))
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
          diag("Mapping.none expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      for entry in entries {
        match
          apply_function_value(
            "Mapping.none predicate",
            arg_values[0],
            [entry.key, entry.value],
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
          Some(_) => {
            diagnostics.push(diag("Mapping.none predicate must return Boolean"))
            return None
          }
          None => return None
        }
      }
      Some(BoolValue(true))
    }
    "count" => {
      if arg_values.length() != 1 {
        diagnostics.push(
          diag("Mapping.count expects 1 argument, got \{arg_values.length()}"),
        )
        return None
      }
      let mut n = 0
      for entry in entries {
        match
          apply_function_value(
            "Mapping.count predicate",
            arg_values[0],
            [entry.key, entry.value],
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
          Some(_) => {
            diagnostics.push(
              diag("Mapping.count predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n.to_int64()))
    }
    _ => None
  }
}
