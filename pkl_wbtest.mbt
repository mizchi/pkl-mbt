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
