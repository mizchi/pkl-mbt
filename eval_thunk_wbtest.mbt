///|
fn eval_thunk_force_count_for_test(cell : EvalThunkCell) -> Int {
  cell.force_count.val
}

///|
fn eval_thunk_state_name_for_test(cell : EvalThunkCell) -> String {
  match cell.state.val {
    PendingThunk => "Pending"
    EvaluatingThunk => "Evaluating"
    ResolvedThunk(_) => "Resolved"
    RejectedThunk(_) => "Rejected"
  }
}

///|
fn eval_thunk_has_computation_for_test(cell : EvalThunkCell) -> Bool {
  cell.computation.val is Some(_)
}

///|
fn object_property_thunk_for_test(
  module_value : Value,
  object_name : String,
  property_name : String,
) -> EvalThunkCell {
  guard module_value is ObjectValue(module_members) else { panic() }
  guard lookup_value_member(module_members, object_name) is Some(object_member) else {
    panic()
  }
  guard object_member.value is ObjectValue(object_members) else { panic() }
  guard lookup_value_member(object_members, property_name)
    is Some(property_member) else {
    panic()
  }
  guard property_member.value is ThunkValue(cell) else { panic() }
  cell
}

///|
test "PKL-161: rejected thunk memoizes its failure" {
  let computation_count : Ref[Int] = { val: 0 }
  let cell = reserve_eval_thunk("pkl161Rejected")
  initialize_eval_thunk(cell, fn() {
    computation_count.val = computation_count.val + 1
    ThunkError("rejected once")
  })
  let first = force_eval_thunk(ThunkValue(cell))
  let second = force_eval_thunk(ThunkValue(cell))
  inspect(
    deferred_error_message(first) == Some("rejected once"),
    content="true",
  )
  inspect(
    deferred_error_message(second) == Some("rejected once"),
    content="true",
  )
  inspect(computation_count.val, content="1")
}

///|
test "PKL-161: unused object property RHS stays pending" {
  let source =
    #|local result = new {
    #|  pkl161Unused = "value".missing
    #|  pkl161Used = true
    #|}
    #|answer = result.pkl161Used
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value), content="answer = true")
}

///|
test "PKL-161: object property RHS is memoized after first force" {
  let source =
    #|result = new {
    #|  pkl161Memoized = 40 + 2
    #|}
    #|sum = result.pkl161Memoized + result.pkl161Memoized
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let cell = object_property_thunk_for_test(value, "result", "pkl161Memoized")
  inspect(eval_thunk_force_count_for_test(cell), content="1")
}

///|
test "PKL-163: same-name property RHS resolves the enclosing binding" {
  let source =
    #|local pkl163Shadowed = 42
    #|result = new {
    #|  pkl163Shadowed = pkl163Shadowed
    #|}
    #|answer = result.pkl163Shadowed
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let cell = object_property_thunk_for_test(value, "result", "pkl163Shadowed")
  inspect(
    render_value(strip_invisible_recursive(value)).contains("answer = 42"),
    content="true",
  )
  inspect(eval_thunk_force_count_for_test(cell), content="1")
}

///|
test "PKL-163: lexical binding shadows a sibling thunk in later RHS" {
  let source =
    #|function build() =
    #|  let (cases = new Listing { 1; 2; 3 })
    #|    new {
    #|      cases = cases.length
    #|      summary = cases.length
    #|    }
    #|answer = build().summary
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value).contains("answer = 3"), content="true")
}

///|
test "PKL-162: local object identity is shared across module bindings" {
  let source =
    #|result = new {
    #|  pkl162Shared = 40 + 2
    #|}
    #|first = result.pkl162Shared
    #|second = result.pkl162Shared
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let cell = object_property_thunk_for_test(value, "result", "pkl162Shared")
  inspect(eval_thunk_force_count_for_test(cell), content="1")
}

///|
test "PKL-163: output.value only forces the selected exported property" {
  let source =
    #|result = new {
    #|  pkl163ExportUnused = 40 + 2
    #|  pkl163ExportUsed = true
    #|}
    #|output {
    #|  value = result.pkl163ExportUsed
    #|}
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let unused = object_property_thunk_for_test(
    value, "result", "pkl163ExportUnused",
  )
  let used = object_property_thunk_for_test(value, "result", "pkl163ExportUsed")
  // Module evaluation preserves the lazy output contract. Rendering the
  // selected output is the consumer boundary that must force only `value`.
  ignore(render_value(extract_output_value(value)))
  inspect(eval_thunk_force_count_for_test(unused), content="0")
  inspect(eval_thunk_force_count_for_test(used), content="1")
}

///|
test "PKL-162: local typed properties stay pending until accessed" {
  let source =
    #|class Result {
    #|  pkl162TypedUnused: Int
    #|  pkl162TypedUsed: Boolean
    #|}
    #|local result = new Result {
    #|  pkl162TypedUnused = "bad"
    #|  pkl162TypedUsed = true
    #|}
    #|answer = result.pkl162TypedUsed
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value), content="answer = true")
}

///|
test "PKL-162: unused typed constraint stays pending" {
  let source =
    #|class Result {
    #|  pkl162PositiveUnused: Int(this > 0)
    #|  safe: Boolean
    #|}
    #|local result = new Result {
    #|  pkl162PositiveUnused = -1
    #|  safe = true
    #|}
    #|answer = result.safe
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value), content="answer = true")
}

///|
test "PKL-162: typed constraint is checked and memoized when forced" {
  let source =
    #|class Result {
    #|  pkl162PositiveForced: Int(this > 0)
    #|}
    #|result = new Result {
    #|  pkl162PositiveForced = -1
    #|}
    #|message = module.catch(() -> result.pkl162PositiveForced)
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let cell = object_property_thunk_for_test(
    value, "result", "pkl162PositiveForced",
  )
  inspect(
    render_value(strip_invisible_recursive(value)).contains("Type constraint"),
    content="true",
  )
  inspect(eval_thunk_force_count_for_test(cell), content="1")
}

///|
test "PKL-161: mutually recursive object property thunks reject once" {
  let source =
    #|result = new {
    #|  pkl161Left = pkl161Right
    #|  pkl161Right = pkl161Left
    #|}
    #|message = module.catch(() -> result.pkl161Left)
  guard eval_source_with_imports(source, fn(_) { None }) is EvalOk(value) else {
    panic()
  }
  let left = object_property_thunk_for_test(value, "result", "pkl161Left")
  let right = object_property_thunk_for_test(value, "result", "pkl161Right")
  let rendered = render_value(strip_invisible_recursive(value))
  inspect(rendered.contains("cyclic property reference"), content="true")
  inspect(eval_thunk_force_count_for_test(left), content="1")
  inspect(eval_thunk_force_count_for_test(right), content="1")
}

///|
test "PKL-161: thunk-backed Dynamic values remain valid Map keys" {
  let source =
    #|local keyed = Map(new Dynamic { name = "Pigeon" }, 30)
    #|value = keyed[new Dynamic { name = "Pigeon" }]
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value).contains("value = 30"), content="true")
}

///|
test "PKL-164: module self-reference sees a prior thunk-backed property" {
  let source =
    #|local foo = new {
    #|  b = 43
    #|  answer = module.foo.b
    #|}
    #|message = foo.answer
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(render_value(value), content="message = 43")
}

///|
test "PKL-165: XML root thunk is forced before structural dispatch" {
  let id = reserve_eval_thunk("pkl165XmlRoot")
  initialize_eval_thunk(id, fn() {
    ThunkOk(
      ObjectValue([
        {
          name: "body",
          value: StringValue("hello"),
          source: None,
          annotations: [],
        },
      ]),
    )
  })
  inspect(
    render_value_as_xml_with_options(ThunkValue(id), "html", "  ", "1.0"),
    content=(
      #|<?xml version="1.0" encoding="UTF-8"?>
      #|<html>
      #|  <body>hello</body>
      #|</html>
      #|
    ),
  )
}

///|
test "PKL-166: thunk handle owns state and releases its computation" {
  let computation_count : Ref[Int] = { val: 0 }
  let thunk = reserve_eval_thunk("pkl166Owned")
  initialize_eval_thunk(thunk, fn() {
    computation_count.val = computation_count.val + 1
    ThunkOk(IntValue(42L))
  })
  inspect(eval_thunk_state_name_for_test(thunk), content="Pending")
  inspect(eval_thunk_has_computation_for_test(thunk), content="true")
  inspect(force_eval_thunk(ThunkValue(thunk)) == IntValue(42L), content="true")
  inspect(force_eval_thunk(ThunkValue(thunk)) == IntValue(42L), content="true")
  inspect(eval_thunk_state_name_for_test(thunk), content="Resolved")
  inspect(eval_thunk_has_computation_for_test(thunk), content="false")
  inspect(computation_count.val, content="1")
}

///|
test "PKL-166: AnalysisSession instances own independent thunk cells" {
  let source =
    #|result = new {
    #|  unused = "value".missing
    #|  used = true
    #|}
    #|output { value = result.used }
  let first_session = AnalysisSession::new()
  first_session.set_source("main.pkl", source)
  let second_session = AnalysisSession::new()
  second_session.set_source("main.pkl", source)
  guard first_session.eval_path_with_runtime_metadata("main.pkl")
    is EvalOk(first) else {
    panic()
  }
  guard second_session.eval_path_with_runtime_metadata("main.pkl")
    is EvalOk(second) else {
    panic()
  }
  let first_cell = object_property_thunk_for_test(first, "result", "unused")
  let second_cell = object_property_thunk_for_test(second, "result", "unused")
  inspect(first_cell != second_cell, content="true")
  inspect(eval_thunk_state_name_for_test(first_cell), content="Pending")
  inspect(eval_thunk_state_name_for_test(second_cell), content="Pending")
  ignore(force_eval_thunk(ThunkValue(first_cell)))
  inspect(eval_thunk_state_name_for_test(first_cell), content="Rejected")
  inspect(eval_thunk_state_name_for_test(second_cell), content="Pending")
}

///|
test "PKL-167: typed nested amendments initialize every property thunk" {
  let source =
    #|class Person {
    #|  name: String = "X"
    #|  friends: List<Person>
    #|  address: Address
    #|}
    #|class Address {
    #|  street: String = "Howdy St"
    #|}
    #|pigeon = new Person {
    #|  name = "Pigeon Who"
    #|  friends = List(new Person { name = "Emma" })
    #|  address { street = "Pigeon St." }
    #|}
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value(value),
    content=(
      #|pigeon {
      #|  name = "Pigeon Who"
      #|  friends = List(new {
      #|    name = "Emma"
      #|    friends = List()
      #|    address {
      #|      street = "Howdy St"
      #|    }
      #|  })
      #|  address {
      #|    street = "Pigeon St."
      #|  }
      #|}
    ),
  )
}

///|
test "PKL-161: function equality does not traverse a cyclic thunk environment" {
  let captured : Array[ValueBinding] = []
  let function = FunctionValue([], NullLiteral, None, captured, 161)
  let cell = reserve_eval_thunk("pkl161FunctionCycle")
  initialize_eval_thunk(cell, fn() { ThunkOk(function) })
  captured.push({ name: "self", value: ThunkValue(cell) })
  inspect(values_equal(function, function), content="true")
  inspect(
    values_equal(function, FunctionValue([], NullLiteral, None, captured, 162)),
    content="false",
  )
}
