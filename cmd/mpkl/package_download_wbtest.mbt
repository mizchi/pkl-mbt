///|
fn test_push_u16_le(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xff).to_byte())
  out.push(((value >> 8) & 0xff).to_byte())
}

///|
fn test_push_u32_le(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xff).to_byte())
  out.push(((value >> 8) & 0xff).to_byte())
  out.push(((value >> 16) & 0xff).to_byte())
  out.push(((value >> 24) & 0xff).to_byte())
}

///|
fn test_push_bytes(out : Array[Byte], bytes : Bytes) -> Unit {
  for i = 0; i < bytes.length(); i = i + 1 {
    out.push(bytes[i])
  }
}

///|
fn test_bytes(out : Array[Byte]) -> Bytes {
  Bytes::from_array(FixedArray::makei(out.length(), fn(i) { out[i] }))
}

///|
fn test_zip_one_file(
  path : String,
  content : Bytes,
  compression : Int,
) -> Bytes {
  let compressed = if compression == 8 {
    @zlib.deflate_compress(content)
  } else {
    content
  }
  let name = @utf8.encode(path[:])
  let out : Array[Byte] = []
  let local_offset = 0
  test_push_u32_le(out, 0x04034b50)
  test_push_u16_le(out, 20)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, compression)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u32_le(out, 0)
  test_push_u32_le(out, compressed.length())
  test_push_u32_le(out, content.length())
  test_push_u16_le(out, name.length())
  test_push_u16_le(out, 0)
  test_push_bytes(out, name)
  test_push_bytes(out, compressed)
  let central_offset = out.length()
  test_push_u32_le(out, 0x02014b50)
  test_push_u16_le(out, 20)
  test_push_u16_le(out, 20)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, compression)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u32_le(out, 0)
  test_push_u32_le(out, compressed.length())
  test_push_u32_le(out, content.length())
  test_push_u16_le(out, name.length())
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u32_le(out, 0)
  test_push_u32_le(out, local_offset)
  test_push_bytes(out, name)
  let central_size = out.length() - central_offset
  test_push_u32_le(out, 0x06054b50)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 0)
  test_push_u16_le(out, 1)
  test_push_u16_le(out, 1)
  test_push_u32_le(out, central_size)
  test_push_u32_le(out, central_offset)
  test_push_u16_le(out, 0)
  test_bytes(out)
}

///|
test "package cache path uses URI fragment as package file path" {
  let relative = package_cache_relative(
    "package://pkg.pkl-lang.org/github.com/mizchi/pkfire/pkfire@0.6.0#/Taskfile.pkl",
    "",
  )
  inspect(
    relative,
    content="github.com/mizchi/pkfire/pkfire@0.6.0/package/Taskfile.pkl",
  )
}

///|
test "zip reader inflates deflated entries" {
  let zip = test_zip_one_file("dir/hello.pkl", b"x = 1\n", 8)
  let entries = read_zip_entries(zip)
  inspect(entries.length(), content="1")
  inspect(entries[0].path, content="dir/hello.pkl")
  inspect(@utf8.decode(entries[0].content[:]), content="x = 1\n")
}

///|
test "read glob scanner supports recursive globstar" {
  let resources = glob_resources_from(
    "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/readGlob.pkl",
    "../../input-helper/globtest/**.pkl",
  )
  inspect(resources.length(), content="4")
  inspect(
    resources[0].uri,
    content="../../input-helper/globtest/module with [weird] ~!characters.pkl",
  )
  inspect(
    resources[3].uri,
    content="../../input-helper/globtest/child/moduleC.pkl",
  )
  inspect(
    resources[0].resource_uri,
    content="file:///$snippetsDir/input-helper/globtest/module%20with%20%5Bweird%5D%20~!characters.pkl",
  )
}

///|
test "read glob scanner preserves globstar parent visible prefix" {
  let resources = glob_resources_from(
    "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/importGlob.pkl",
    "../../input-helper/globtest/**/../*.pkl",
  )
  inspect(resources.length(), content="3")
  inspect(
    resources[0].uri,
    content="../../input-helper/globtest/child/../module with [weird] ~!characters.pkl",
  )
  inspect(
    resources[2].uri,
    content="../../input-helper/globtest/child/../moduleB.pkl",
  )
}

///|
test "import glob scanner includes directory matches for deferred loading" {
  let from = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/importGlob.pkl"
  let empty = import_glob_scan_from(from, "").uris
  inspect(empty.length(), content="1")
  inspect(empty[0], content="")
  let direct_scan = import_glob_scan_from(from, "../../input-helper/globtest")
  let direct = direct_scan.uris
  inspect(direct.length(), content="1")
  inspect(direct[0], content="../../input-helper/globtest")
  inspect(
    direct_scan.errors["../../input-helper/globtest"],
    content="I/O error loading module `file:///$snippetsDir/input-helper/globtest`. IOException: Is a directory",
  )
}

///|
test "import glob scanner treats escaped wildcard chars as literals" {
  let from = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/importGlob.pkl"
  let uris = import_glob_scan_from(
      from, "../../input-helper/globtest/module with \\[weird] ~!characters.pkl",
    ).uris
  inspect(uris.length(), content="1")
  inspect(
    uris[0],
    content="../../input-helper/globtest/module with [weird] ~!characters.pkl",
  )
}

///|
test "register expr io preloads string literal resource arguments for dynamic read" {
  @pkl.reset_sandbox_io_cache()
  let from = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/read.pkl"
  let source =
    #|local function doRead(uri) = read(uri)
    #|result = doRead("globtest/file2.txt").text
  let parsed = @pkl.parse_source(source)
  for binding in parsed.program.bindings {
    register_expr_io(from, binding.value)
  }
  let session = @pkl.AnalysisSession::new()
  session.set_source(from, source)
  guard session.eval_path(from) is @pkl.EvalOk(@pkl.ObjectValue(members)) else {
    panic()
  }
  guard members[0].value is @pkl.StringValue(text) else { panic() }
  inspect(text, content="file2\n")
  @pkl.reset_sandbox_io_cache()
}

///|
test "register expr io preloads string literal glob arguments for dynamic read star" {
  @pkl.reset_sandbox_io_cache()
  let from = "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/readGlob.pkl"
  let source =
    #|local function doRead(pattern) = read*(pattern)
    #|result = doRead("globtest/file*.txt")
  let parsed = @pkl.parse_source(source)
  for binding in parsed.program.bindings {
    register_expr_io(from, binding.value)
  }
  let session = @pkl.AnalysisSession::new()
  session.set_source(from, source)
  guard session.eval_path(from) is @pkl.EvalOk(value) else { panic() }
  inspect(
    @pkl.render_value(value),
    content=(
      #|result {
      #|  ["globtest/file1.txt"] {
      #|    uri = "file:///$snippetsDir/input/basic/globtest/file1.txt"
      #|    text = """
      #|      file1
      #|      
      #|      """
      #|    base64 = "ZmlsZTEK"
      #|  }
      #|  ["globtest/file2.txt"] {
      #|    uri = "file:///$snippetsDir/input/basic/globtest/file2.txt"
      #|    text = """
      #|      file2
      #|      
      #|      """
      #|    base64 = "ZmlsZTIK"
      #|  }
      #|}
    ),
  )
  @pkl.reset_sandbox_io_cache()
}

///|
test "read glob scanner supports package globstar" {
  @pkl.configure_sandbox_package_caches([
    "third_party/apple-pkl/pkl-commons-test/src/main/files/packages",
  ])
  let resources = glob_resources_from(
    "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/readGlob.pkl",
    "package://localhost:0/birds@0.5.0#/**.pkl",
  )
  inspect(resources.length(), content="6")
  inspect(
    resources[0].uri,
    content="package://localhost:0/birds@0.5.0#/Bird.pkl",
  )
  inspect(
    resources[3].uri,
    content="package://localhost:0/birds@0.5.0#/catalog/Ostrich.pkl",
  )
  inspect(resources[0].resource_uri, content=resources[0].uri)
  @pkl.configure_sandbox_package_caches([])
}

///|
test "package glob scanner keeps absolute URI escaping" {
  @pkl.configure_sandbox_package_caches([
    "third_party/apple-pkl/pkl-commons-test/src/main/files/packages",
  ])
  let uris = import_glob_scan_from(
      "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/importGlob.pkl",
      "package://localhost:0/packageContainingWildcardCharacters@1.0.0#/name%20*",
    ).uris
  inspect(uris.length(), content="1")
  inspect(
    uris[0],
    content="package://localhost:0/packageContainingWildcardCharacters@1.0.0#/name%20with%20%5Bwildcard%5D!%20characters~~.pkl",
  )
  @pkl.configure_sandbox_package_caches([])
}
