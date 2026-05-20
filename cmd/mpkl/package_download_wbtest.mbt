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
  let uris = glob_visible_uris_from(
    "third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input/basic/importGlob.pkl",
    "package://localhost:0/packageContainingWildcardCharacters@1.0.0#/name%20*",
  )
  inspect(uris.length(), content="1")
  inspect(
    uris[0],
    content="package://localhost:0/packageContainingWildcardCharacters@1.0.0#/name%20with%20%5Bwildcard%5D!%20characters~~.pkl",
  )
  @pkl.configure_sandbox_package_caches([])
}
