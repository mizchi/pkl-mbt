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
