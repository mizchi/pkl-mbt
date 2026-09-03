///|
test "PKL-154: output.bytes is projected without text conversion" {
  let value = @pkl.ObjectValue([
    {
      name: "output",
      value: @pkl.ObjectValue([
        {
          name: "bytes",
          value: @pkl.BytesValue(b"\x00\x7f\x80\xff"),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  guard extract_output_bytes(value) is Some(bytes) else { panic() }
  inspect(bytes.length(), content="4")
  inspect(bytes[0].to_int(), content="0")
  inspect(bytes[1].to_int(), content="127")
  inspect(bytes[2].to_int(), content="128")
  inspect(bytes[3].to_int(), content="255")
}

///|
test "PKL-154: inherited pklbinary output renderer is detected at runtime" {
  let value = @pkl.ObjectValue([
    {
      name: "output",
      value: @pkl.ObjectValue([
        {
          name: "renderer",
          value: @pkl.ObjectValue([
            {
              name: "@hidden$__class",
              value: @pkl.StringValue("pklbinary.Renderer"),
              source: None,
              annotations: [],
            },
          ]),
          source: None,
          annotations: [],
        },
      ]),
      source: None,
      annotations: [],
    },
  ])
  guard extract_output_renderer_format(value) is Some(format) else { panic() }
  inspect(format, content="pklbinary")
}

///|
test "PKL-154: upstream inherited pklbinary renderer survives evaluation" {
  let parent_path = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/pklbinaryTest.pkl"
  let child_path = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/pklbinary/classes.msgpack.yaml.pkl"
  let session = @pkl.AnalysisSession::new()
  session.set_source(
    parent_path,
    @fs.read_file_to_string(parent_path) catch {
      _ => panic()
    },
  )
  session.set_source(
    ".../pklbinaryTest.pkl",
    @fs.read_file_to_string(parent_path) catch {
      _ => panic()
    },
  )
  session.set_source(
    child_path,
    @fs.read_file_to_string(child_path) catch {
      _ => panic()
    },
  )
  let child_parsed = @pkl.parse_source(
    @fs.read_file_to_string(child_path) catch {
      _ => panic()
    },
  )
  let mut barn_owl_annotation = "missing"
  for binding in child_parsed.program.bindings {
    if binding.name == "barnOwl" {
      match binding.type_name {
        Some(annotation) => barn_owl_annotation = annotation
        None => ()
      }
    }
  }
  inspect(barn_owl_annotation, content="Person")
  guard session.eval_path_with_runtime_metadata(child_path)
    is @pkl.EvalOk(value) else {
    panic()
  }
  guard extract_output_renderer_format(value) is Some(format) else { panic() }
  inspect(format, content="pklbinary")
  inspect(output_value_is_module_projection(value), content="true")
  guard value is @pkl.ObjectValue(module_members) else { panic() }
  let mut barn_owl_tag = "missing"
  let mut person_class_kind = "missing"
  for entry in module_members {
    if entry.name == "barnOwl" {
      match entry.value {
        @pkl.ObjectValue(members) =>
          for nested in members {
            if nested.name == "@hidden$__class" {
              match nested.value {
                @pkl.StringValue(name) => barn_owl_tag = name
                _ => ()
              }
            }
          }
        _ => ()
      }
    }
    if entry.name == "personClass" {
      match entry.value {
        @pkl.ObjectValue(members) =>
          for nested in members {
            if nested.name == "@hidden$__kind" {
              match nested.value {
                @pkl.StringValue(kind) => person_class_kind = kind
                _ => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  inspect(barn_owl_tag, content="Person")
  inspect(person_class_kind, content="Class")
}

///|
test "PKL-154: upstream explicit output.bytes survives evaluation" {
  let path = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/api/pklbinary1.msgpack.yaml.pkl"
  let session = @pkl.AnalysisSession::new()
  session.set_source(path, @fs.read_file_to_string(path) catch { _ => panic() })
  guard session.eval_path_with_runtime_metadata(path) is @pkl.EvalOk(value) else {
    panic()
  }
  guard extract_output_bytes(value) is Some(bytes) else { panic() }
  inspect(bytes.length() > 0, content="true")
}

///|
/// The search order is what stops reflection from depending on the
/// working directory, so pin its shape: an explicit request leads, the
/// executable's own tree comes next (walking up), and the historical
/// cwd-relative paths stay last.
test "the stdlib search looks beside the executable before the working directory" {
  let previous = @env.get_env_var("PKL_MBT_STDLIB")
  @env.set_env_var("PKL_MBT_STDLIB", "/explicit/base.pkl")
  let candidates = stdlib_base_candidates()
  match previous {
    Some(v) => @env.set_env_var("PKL_MBT_STDLIB", v)
    None => @env.set_env_var("PKL_MBT_STDLIB", "")
  }
  // An explicit request is tried first.
  assert_eq(candidates[0], "/explicit/base.pkl")
  // The cwd-relative fallbacks are last, in their historical order.
  let n = candidates.length()
  assert_eq(candidates[n - 3], "third_party/apple-pkl/stdlib/base.pkl")
  assert_eq(candidates[n - 2], "stdlib/base.pkl")
  assert_eq(candidates[n - 1], "/usr/local/share/pkl/stdlib/base.pkl")
  // Everything between is anchored at the executable, so it resolves the
  // same way whatever directory the process was started from. The test
  // binary lives inside the repo, so at least one such candidate exists.
  let mut absolute_between = 0
  for i = 1; i < n - 3; i = i + 1 {
    if candidates[i].has_prefix("/") {
      absolute_between = absolute_between + 1
    }
  }
  assert_true(absolute_between > 0)
  assert_eq(absolute_between, n - 4)
}

///|
/// An empty `PKL_MBT_STDLIB` must not become a candidate: an empty path
/// reads as the current directory on some filesystems, and a silent
/// wrong answer is the thing this search order exists to prevent.
test "an empty PKL_MBT_STDLIB contributes no candidate" {
  let previous = @env.get_env_var("PKL_MBT_STDLIB")
  @env.set_env_var("PKL_MBT_STDLIB", "")
  let candidates = stdlib_base_candidates()
  match previous {
    Some(v) => @env.set_env_var("PKL_MBT_STDLIB", v)
    None => ()
  }
  for candidate in candidates {
    assert_true(candidate != "")
  }
  assert_eq(candidates[0].has_prefix("/") || candidates[0] == "third_party/apple-pkl/stdlib/base.pkl", true)
}
