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
    | "toList"
    | "toSet"
    | "toListing"
    | "first"
    | "last"
    | "distinct" => true
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
    | "distinct"
    | "isEmpty"
    | "isNotEmpty"
    | "isDistinct" => true
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
    "length" => Some(IntValue(elements.length()))
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
        Some(elements[0])
      }
    "lastOrNull" =>
      if elements.length() == 0 {
        Some(NullValue)
      } else {
        Some(elements[elements.length() - 1])
      }
    // PKL-148h: `.toList()` tags as `ListValue` (round-trips through
    // the `List(...)` constructor form); `.toListing()` keeps the
    // Listing block tag. `.toSet` deduplicates and tags as Set.
    "toList" => Some(ListValue(elements))
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
        diagnostics.push(diag("Listing.first on empty Listing"))
        None
      } else {
        Some(elements[0])
      }
    "last" =>
      if elements.length() == 0 {
        diagnostics.push(diag("Listing.last on empty Listing"))
        None
      } else {
        Some(elements[elements.length() - 1])
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
    _ => None
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
        IntValue(idx) =>
          if idx >= 0 && idx < elements.length() {
            Some(elements[idx])
          } else {
            Some(NullValue)
          }
        _ => {
          diagnostics.push(diag("Listing.getOrNull expects an Int index"))
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
        ListingValue(other) | ListValue(other) | SetValue(other) =>
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
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
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
          let n = if raw < 0 {
            0
          } else if raw > elements.length() {
            elements.length()
          } else {
            raw
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
          Some(_) => {
            diagnostics.push(
              diag("Listing.filter predicate must return Boolean"),
            )
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
      Some(ListValue(elements))
    }
    "toMap" => {
      if arg_values.length() != 0 {
        diagnostics.push(
          diag("Listing.toMap expects 0 arguments, got \{arg_values.length()}"),
        )
        return None
      }
      Some(MappingValue([]))
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
          Some(ListingValue(inner)) | Some(ListValue(inner)) =>
            for v in inner {
              result.push(v)
            }
          Some(_) => {
            diagnostics.push(
              diag("Listing.flatMap callback must return Listing"),
            )
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
          Some(_) => {
            diagnostics.push(
              diag("Listing.count predicate must return Boolean"),
            )
            return None
          }
          None => return None
        }
      }
      Some(IntValue(n))
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
          Some(_) => {
            diagnostics.push(
              diag("Listing.every predicate must return Boolean"),
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
          Some(_) => {
            diagnostics.push(diag("Listing.any predicate must return Boolean"))
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
          Some(_) => {
            diagnostics.push(diag("Listing.none predicate must return Boolean"))
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
          Some(_) => {
            diagnostics.push(
              diag("Listing.\{method_name} predicate must return Boolean"),
            )
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
          Some(_) => {
            diagnostics.push(
              diag("Listing.\{method_name} predicate must return Boolean"),
            )
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
    | "isDistinct" =>
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
