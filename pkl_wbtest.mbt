// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "parse source root advertises module kind through the internal helper" {
  let parsed = parse_source("1 + 2 * 3")
  inspect(kind_name(parsed.root.kind()), content="module")
}

///|
test "analysis typecheck ignores unrelated source changes" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "value = 1")
  session.set_source(
    "main.pkl", "import \"base.pkl\" as base\nanswer = base.value + 1",
  )
  session.set_source("unused.pkl", "value = false")

  assert_true(
    session.typecheck_path("main.pkl") ==
    TypeOk(ObjectType([TypeMember::{ name: "answer", typ: IntType }])),
  )

  session.reset_stats()
  session.set_source("unused.pkl", "value = true")
  assert_true(
    session.typecheck_path("main.pkl") ==
    TypeOk(ObjectType([TypeMember::{ name: "answer", typ: IntType }])),
  )
  let stats = session.stats()
  inspect(stats.parse_count, content="0")
  inspect(stats.typecheck_count, content="0")
}

///|
test "analysis typecheck backdates unchanged dependency types" {
  let session = AnalysisSession::new()
  session.set_source("base.pkl", "value = 1")
  session.set_source(
    "main.pkl", "import \"base.pkl\" as base\nanswer = base.value + 1",
  )
  ignore(session.typecheck_path("main.pkl"))

  session.reset_stats()
  session.set_source("base.pkl", "value = 2")
  assert_true(
    session.typecheck_path("main.pkl") ==
    TypeOk(ObjectType([TypeMember::{ name: "answer", typ: IntType }])),
  )
  let stats_after_same_type = session.stats()
  inspect(stats_after_same_type.parse_count, content="1")
  inspect(stats_after_same_type.typecheck_count, content="1")

  session.reset_stats()
  session.set_source("base.pkl", "value = true")
  guard session.typecheck_path("main.pkl") is TypeError(diagnostics) else {
    panic()
  }
  inspect(diagnostics[0].message, content="operator + expects Int operands")
  let stats_after_changed_type = session.stats()
  inspect(stats_after_changed_type.parse_count, content="1")
  inspect(stats_after_changed_type.typecheck_count, content="2")
}

///|
test "typed mapping object literal rewrite keeps default function marker" {
  let parsed = parse_source(
    (
      #|res: Mapping<String, Person> = new {
      #|  default { key -> name = key }
      #|  ["x"] { age = 1 }
      #|}
    ),
  )
  guard parsed.program.bindings[0].value is ObjectLiteral(_) else { panic() }
  let rewritten = collection_literal_expr_for_type_annotation(
    parsed.program.bindings[0].value,
    Some("Mapping<String, Person>"),
  )
  guard rewritten is MappingLiteral(entries) else { panic() }
  inspect(entries.length(), content="2")
  guard entries[0].key is Identifier(marker_name) else { panic() }
  inspect(marker_name, content="@collectionDefault")
  guard entries[0].value is ObjectLiteral(default_members) else { panic() }
  inspect(default_members.length(), content="2")
  inspect(default_members[0].name, content="@functionAmend$params")
}

///|
test "typecheck accepts listing spreads in typed class members" {
  let source =
    #|local xs: Listing<String> = new { "a" }
    #|class Task {
    #|  inputs: Listing<String> = new {}
    #|}
    #|task = new Task {
    #|  inputs = new {
    #|    ...xs
    #|    "b"
    #|  }
    #|}
  guard typecheck_source(source) is TypeOk(_) else { panic() }
}

///|
test "typecheck tracks Listing higher-order methods and module builtins" {
  let source =
    #|class Task {
    #|  name: String
    #|  deps: Listing<Task> = new {}
    #|}
    #|tasks: Listing<Task> = new {}
    #|local taskNames: List<String> = tasks.toList().map((t) -> t.name)
    #|local duplicateNames: List<String> =
    #|  taskNames.filter((n) -> taskNames.count((m) -> m == n) > 1).distinct
    #|local rendered: Mapping<String, Task> = new Mapping {
    #|  for (task in tasks) {
    #|    [task.name] = task
    #|  }
    #|}
    #|defaults = new {}
    #|output {
    #|  value = new {
    #|    defaults = module.defaults
    #|    tasks =
    #|      if (duplicateNames.isEmpty)
    #|        rendered
    #|      else
    #|        throw("duplicate task names")
    #|  }
    #|}
  guard typecheck_source(source) is TypeOk(_) else { panic() }
}

///|
/// `member_name_matches_any_visibility` replaced three string equalities
/// against `name`, `@hidden$name` and `@local$name` on the scope-walk hot
/// paths. It has to accept and reject exactly what those comparisons did,
/// including for a `name` that is already prefixed.
test "member name matching accepts every visibility form without allocating" {
  assert_true(member_name_matches_any_visibility("x", "x"))
  assert_true(member_name_matches_any_visibility("@hidden$x", "x"))
  assert_true(member_name_matches_any_visibility("@local$x", "x"))
  // A different member, a prefix of one, and an extension of one.
  assert_false(member_name_matches_any_visibility("y", "x"))
  assert_false(member_name_matches_any_visibility("@hidden$xy", "x"))
  assert_false(member_name_matches_any_visibility("@hidden$", "x"))
  assert_false(member_name_matches_any_visibility("x", "@hidden$x"))
  // `@error$` is a separate namespace: the old comparison never matched it.
  assert_false(member_name_matches_any_visibility("@error$x", "x"))
  // Doubly-prefixed storage names answer to their prefixed bare form.
  assert_true(member_name_matches_any_visibility("@hidden$@hidden$x", "@hidden$x"))
  assert_true(member_name_matches_any_visibility("@hidden$x", "@hidden$x"))
  // Empty and single-character edges.
  assert_false(member_name_matches_any_visibility("", "x"))
  assert_true(member_name_matches_any_visibility("", ""))
  assert_true(member_name_matches_any_visibility("@hidden$", ""))
}

///|
test "module snapshot member name prefers inherited hidden storage" {
  let bindings : Array[Binding] = [
    {
      name: "@hidden$secret",
      type_name: None,
      value: NullLiteral,
      exported: true,
      is_const: false,
      annotations: [],
      abstract_slot: false,
      sibling_slot: false,
    },
    {
      name: "plain",
      type_name: None,
      value: NullLiteral,
      exported: true,
      is_const: false,
      annotations: [],
      abstract_slot: false,
      sibling_slot: false,
    },
  ]
  let parent_members : Array[ValueMember] = [
    { name: "@hidden$inherited", value: NullValue, source: None, annotations: [] },
    { name: "@local$scoped", value: NullValue, source: None, annotations: [] },
    { name: "visible", value: NullValue, source: None, annotations: [] },
  ]
  let index = build_module_binding_index(bindings, Some(parent_members))
  // Declared `hidden` in this module.
  assert_eq(module_snapshot_member_name("secret", index), "@hidden$secret")
  // `hidden` / `local` inherited from the amended parent.
  assert_eq(module_snapshot_member_name("inherited", index), "@hidden$inherited")
  assert_eq(module_snapshot_member_name("scoped", index), "@local$scoped")
  // Ordinary properties keep their bare name.
  assert_eq(module_snapshot_member_name("plain", index), "plain")
  assert_eq(module_snapshot_member_name("visible", index), "visible")
  assert_eq(module_snapshot_member_name("absent", index), "absent")
  // Already-invisible names pass through untouched.
  assert_eq(module_snapshot_member_name("@hidden$secret", index), "@hidden$secret")
}

///|
/// `repeat` counted in 32 bits, so a count past that range wrapped and the
/// call answered with an empty list instead of building one. The upstream
/// fixture uses 118,866,785 -- inside the range, and named for the
/// overflow it triggered in the original implementation -- so nothing in
/// the gold suite covered the wrap.
test "repeat does not truncate its count to 32 bits" {
  // 2^32 + 1 copies of an empty list is still an empty list, and gets
  // there without building anything. Under the truncating loop the count
  // wrapped to 1; under a correct one the answer is the same, so assert
  // on the arithmetic that decides it rather than on a huge allocation.
  guard eval_source("n = List().repeat(4294967297).length") is EvalOk(value) else {
    panic()
  }
  guard value is ObjectValue(members) else { panic() }
  assert_eq(lookup_member(members, "n"), Some(IntValue(0L)))
  // And the ordinary case still repeats, in order.
  guard eval_source("xs = List(1, 2).repeat(3)") is EvalOk(list_value) else {
    panic()
  }
  guard list_value is ObjectValue(list_members) else { panic() }
  guard lookup_member(list_members, "xs") is Some(ListValue(elements)) else {
    panic()
  }
  assert_eq(elements.length(), 6)
  assert_eq(elements[0], IntValue(1L))
  assert_eq(elements[1], IntValue(2L))
  assert_eq(elements[5], IntValue(2L))
  // Zero copies is empty, and a negative count is refused.
  guard eval_source("xs = List(1).repeat(0)") is EvalOk(zero_value) else {
    panic()
  }
  guard zero_value is ObjectValue(zero_members) else { panic() }
  guard lookup_member(zero_members, "xs") is Some(ListValue(zero_elements)) else {
    panic()
  }
  assert_eq(zero_elements.length(), 0)
  assert_true(eval_source("xs = List(1).repeat(-1)") is EvalError(_))
}
