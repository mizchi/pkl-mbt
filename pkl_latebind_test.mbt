// Late-binding / most-derived-receiver field resolution tests.
//
// Pkl semantics: a property's value expression is late-bound. When an
// object O is evaluated, each inherited default body is re-evaluated with
// `this` = O (the most-derived object), so references to sibling
// properties resolve to O's (possibly-overridden) values, not the
// declaring class's own defaults.

///|
// Shape 1: a parent-class default iterates a field the subclass overrides.
// `Base.argv` defaults to `new { "run"; for (p in include) { p } }`.
// `Derived extends Base` overrides `include`. Apple Pkl re-evaluates
// `argv`'s inherited default against Derived's `include`, so the loop
// emits Derived's elements; mpkl previously evaluated `argv` against
// Base's empty `include`.
test "late binding: inherited default re-evaluated against subclass override" {
  let source =
    #|open class Base {
    #|  include: Listing<String> = new {}
    #|  argv: Listing<String> = new {
    #|    "run"
    #|    for (p in include) {
    #|      p
    #|    }
    #|  }
    #|}
    #|class Derived extends Base {
    #|  include = new { "a"; "b" }
    #|}
    #|result = new Derived {}
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "result": {
      #|    "include": [
      #|      "a",
      #|      "b"
      #|    ],
      #|    "argv": [
      #|      "run",
      #|      "a",
      #|      "b"
      #|    ]
      #|  }
      #|}
    ),
  )
}

///|
// Shape 1b: inherited default references a scalar field the subclass
// overrides (`configPath`). Mirrors the pkspec Vitest adapter shape where
// `discover.command.argv` embeds `configPath`.
test "late binding: inherited default reads subclass scalar override" {
  let source =
    #|open class Base {
    #|  configPath: String = "default.config"
    #|  argv: Listing<String> = new {
    #|    "--config"
    #|    configPath
    #|  }
    #|}
    #|class Derived extends Base {
    #|  configPath = "custom.config"
    #|}
    #|result = new Derived {}
  guard eval_source(source) is EvalOk(value) else { panic() }
  inspect(
    render_value_as_json(value),
    content=(
      #|{
      #|  "result": {
      #|    "configPath": "custom.config",
      #|    "argv": [
      #|      "--config",
      #|      "custom.config"
      #|    ]
      #|  }
      #|}
    ),
  )
}

///|
// Shape 2: nested typed-Listing element defaults. `tests: Listing<Test>`
// elements carry a `background: Listing<Background>` field whose element
// type `Background` declares `shell = "bash"`. Apple Pkl applies the
// element type's defaults to every nested element; mpkl previously
// accepted a cast `Test` object as-is and never backfilled the inner
// `Background` element's `shell`, so `b.shell` surfaced as
// `Cannot find property 'shell' in Dynamic`. The cast path now
// re-applies declared user-class collection-field annotations.
test "late binding: nested typed-Listing element defaults backfilled" {
  let source =
    #|class Background {
    #|  name: String
    #|  shell: String = "bash"
    #|}
    #|class Test {
    #|  name: String
    #|  background: Listing<Background> = new {}
    #|}
    #|local function renderBg(b: Background): String = b.shell
    #|tests: Listing<Test> = new {
    #|  new {
    #|    name = "t1"
    #|    background { new { name = "bg1" } }
    #|  }
    #|}
    #|rendered = new Mapping {
    #|  for (t in tests) {
    #|    [t.name] = new Listing { for (b in t.background) { renderBg(b) } }
    #|  }
    #|}
  guard eval_source(source) is EvalOk(value) else { panic() }
  let json = render_value_as_json(value)
  // The nested Background element must carry its `shell = "bash"`
  // default (rendered both on `tests` and read back via `renderBg`).
  assert_true(json.contains("\"shell\": \"bash\""))
  assert_true(json.contains("\"bash\""))
}
