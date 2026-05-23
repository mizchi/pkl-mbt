#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"
GOLD="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/output"
PKG_CACHE="third_party/apple-pkl/pkl-commons-test/src/main/files/packages"
# IO-aware fixtures invoke the release binary directly so the
# controlled env / `-p` set isn't shadowed by `moon run`'s own
# environment plumbing. Build once up front; the other fixture lanes
# still go through `moon run` for the source-change detection.
MPKL="_build/native/release/build/cmd/mpkl/mpkl.exe"
moon build --release --target native >/dev/null 2>&1

# PKL-096: list of upstream fixtures whose `pkl eval` output already
# matches the gold `.pcf` byte-for-byte. Promote here only after a
# manual diff run; new failures must be either fixed or explicitly
# tracked outside this list (the script gates regressions).
GOLD_FIXTURES=(
  "annotation/annotation1"
  "api/anyConverter"
  "api/intseq"
  "api/jsonParser1"
  "api/jsonParser2"
  "api/jsonParser3"
  "api/jsonParser4"
  "api/jsonParser5"
  "api/jsonRenderer4"
  "api/jsonRenderer5"
  "api/jsonRenderer2b"
  "api/jsonRendererEmptyComposites"
  "api/jsonRenderer7"
  "api/jsonnetRenderer4"
  "api/jsonnetRenderer5"
  "api/module"
  "api/moduleOutput2"
  "api/pair"
  "api/pcfRenderer2"
  "api/pcfRenderer2b"
  "api/pcfRenderer3"
  "api/pcfRenderer4"
  "api/pcfRenderer5"
  "api/pcfRenderer6"
  "api/pcfRenderer7"
  "api/pListRenderer4"
  "api/pListRenderer5"
  "api/plistRenderer2b"
  "api/protobuf"
  "api/protobuf2"
  "api/propertiesRenderer2b"
  "api/propertiesRenderer4"
  "api/propertiesRenderer5"
  "api/semverModule"
  "api/xmlRenderer2b"
  "api/xmlRenderer4"
  "api/xmlRenderer5"
  "api/xmlRendererValidation10"
  "api/xmlRendererValidation11"
  "api/yamlRenderer2b"
  "api/reflect1"
  "api/yamlParser1Yaml12"
  "api/yamlParser2"
  "api/yamlParser3"
  "api/yamlParser4"
  "api/yamlParser5"
  "api/yamlParser6"
  "api/yamlRenderer4"
  "api/yamlRenderer5"
  "api/yamlRendererStream1"
  "api/yamlRendererStream2"
  "basic/amendsChains"
  "basic/baseModule"
  "basic/comments"
  "basic/constModifier"
  "basic/constModifier3"
  "basic/fixedProperty1"
  "basic/fixedProperty2"
  "basic/fixedProperty3"
  "basic/identifier"
  "basic/localMethodDynamicBinding"
  "basic/localMethodTyped3"
  "basic/localModuleMemberOverride1"
  "basic/localModuleMemberOverride2"
  "basic/localPropertyInAmendingModule"
  "basic/import1"
  "basic/import2"
  "basic/if"
  "basic/import3"
  "basic/imported"
  "basic/indexExpressions"
  "basic/intseq"
  "basic/list"
  "basic/localProperty1"
  "basic/localProperty2"
  "basic/localPropertyOverride1"
  "basic/localPropertyOverride2"
  "basic/localPropertyOverride3"
  "basic/propertyDefaults"
  "basic/minPklVersion"
  "basic/moduleRefLibrary"
  "basic/new"
  "basic/newType"
  "basic/nonNull"
  "basic/nullable"
  "basic/objectMember"
  "basic/parens"
  "basic/semicolon"
  "basic/set"
  "basic/typeResolution1"
  "basic/typeResolution2"
  "basic/typeResolution3"
  "basic/typeResolution4"
  "basic/underscore"
  "classes/class1"
  "classes/class4"
  "classes/constraints1"
  "classes/constraints2"
  "classes/constraints3"
  "classes/constraints4"
  "classes/constraints6"
  "classes/constraints7"
  "classes/constraints8"
  "classes/constraints13"
  "classes/constraintsLambdaThis"
  "classes/equality"
  "classes/supercalls"
  "classes/unionTypes"
  "classes/wrongType5"
  "errors/baseModule"
  "classes/functions1"
  "classes/functions2"
  "classes/functions3"
  "classes/functions4"
  "classes/inheritance1"
  "classes/inheritance2"
  "generators/propertyGenerators"
  "lambdas/amendLambdaDef"
  "lambdas/amendLambdaExpr"
  "lambdas/amendLambdaParameters"
  "lambdas/amendLambdaParametersTyped"
  "lambdas/amendLambdaThatReturnsAnotherLambda"
  "lambdas/equality"
  "lambdas/inequality"
  "lambdas/lambda1"
  "lambdas/lambda2"
  "lambdas/lambda5"
  "listings/cacheStealing"
  "listings/cacheStealingTypeCheck"
  "listings/listing1"
  "listings/listing5"
  "listings/typeCheck"
  "listings2/listing1"
  "listings2/typeCheck"
  "mappings/duplicateComputedKey"
  "mappings/mapping1"
  "mappings/typeCheck"
  "mappings2/duplicateComputedKey"
  "mappings2/mapping1"
  "mappings2/typeCheck"
  "methods/methodParameterTypes1"
  "methods/methodParameterTypes2"
  "modules/amendModule1"
  "modules/amendModule2"
  "modules/amendModule3"
  "modules/amendModule5"
  "modules/filename with spaces"
  "modules/filename with spaces 2"
  "modules/library"
  "modules/lists"
  "modules/objects"
  "modules/supercalls1"
  "modules/typedModuleProperties1"
  "objects/closure"
  "objects/configureObjectAssign"
  "objects/hashCode"
  "objects/implicitReceiver1"
  "objects/implicitReceiver2"
  "objects/implicitReceiver3"
  "objects/lateBinding4"
  "objects/outer"
  "objects/super1"
  "objects/super2"
  "objects/super3"
  "objects/super4"
  "objects/super5"
  "objects/this1"
  "parser/constraintsTrailingComma"
  "parser/lineCommentBetween"
  "parser/trailingCommas"
  "packages/packages1"
  "packages/packages2"
  "packages/redirects"
  "projects/badLocalProject/dog"
  "projects/evaluatorSettings/basic"
  "projects/notAProject/@child/theChild"
  "projects/notAProject/goodImport"
  "projects/packageWithSpaces/module with spaces"
  "projects/project1/basic"
  "projects/project1/globbing"
  "projects/project1/localProject"
  "projects/project1/localProjectRead"
  "projects/project2/penguin"
  "projects/project3/basic"
  "projects/project4/main"
  "projects/project5/main"
  "projects/project6/children"
  "projects/project6/children/a"
  "projects/project6/children/b"
  "projects/project6/children/c"
  "projects/project7/globWildcards"
  "types/ThisInTypeConstraint"
  "types/helpers/someModule"
  "types/moduleType2"
  "types/moduleType3"
  "types/moduleType4"
  "types/moduleType5"
  "types/nothingWithUnions"
  "types/typeAliasConstraint1"
  "types/typeAliasUnion"
  "implementation/equality"
  "implementation/inequality"
  "syntax/shebang"
  "api/annotationConverters"
  "api/any"
  "api/dataSize"
  "api/bytes"
  "api/duration"
  "api/dynamic"
  "api/float"
  "api/map"
  "api/mathModule"
  "api/moduleOutput"
  "api/benchmarkModule"
  "api/releaseModule"
  "api/Resource"
  "api/stringUnicode"
  "api/typeAliases"
  "api/typed"
  "api/dir1/dir2/relativePathTo"
  "classes/constraints14"
  "errors/const/constLocalAmendModule"
  "modules/amendModule6"
  "generators/spreadSyntaxNullable"
  "methods/methodParameterConstraints1"
  "types/typeAlias1"
  "modules/typedModuleMethods1"
  "types/typeAlias2"
  "listings/wrongIndex"
  "generators/spreadSyntaxTyped"
  "generators/forGeneratorNestedReference2"
  "generators/elementGenerators"
  "generators/entryGenerators"
  "generators/elementGeneratorsTyped"
  "generators/entryGeneratorsTyped"
  "generators/forGeneratorInFunctionBody"
  "generators/forGeneratorInMixins"
  "generators/forGeneratorLexicalScope"
  "listings2/wrongIndex"
  "classes/supercallsInLet"
  "basic/localMethodOverride1"
  "basic/localMethodOverride2"
  "basic/localMethodTyped4"
  "modules/supercalls2"
  "modules/supercalls3"
  "modules/amendModule4"
  "modules/extendModule1"
  "modules/日本語"
  "projects/project7/spacesInImport"
  "methods/methodParameterConstraints2"
  "basic/localTypedModuleMember"
  "basic/localMethodInAmendingModule"
  "basic/localMethodTyped"
  "basic/localMethodTyped2"
  "basic/localMethodTyped5"
  "basic/localMethodTyped6"
  "basic/localMethodUntyped"
  "basic/moduleRef1"
  "basic/moduleRef2"
  "basic/letTyped"
  "basic/constModifier4"
  "basic/localTypedClassMember"
  "basic/localTypedObjectMember"
  "api/pcfRenderer1"
  "basic/rawString"
  "basic/stringMultiline"
  "generators/predicateMembersThis"
  "classes/constraints10"
  "api/pcfRenderer9"
  "parser/newline"
  "listings/numberLiterals"
  "listings2/numberLiterals"
  "listings/default"
  "listings2/default"
  "listings/equality"
  "listings/inequality"
  "listings2/equality"
  "listings2/inequality"
  "listings/hashCode"
  "listings/listing2"
  "listings/listing3"
  "listings/listing4"
  "listings2/listing2"
  "listings2/listing3"
  "listings2/wrongParent"
  "mappings/default"
  "mappings2/default"
  "mappings/equality"
  "mappings/inequality"
  "mappings2/equality"
  "mappings2/inequality"
  "mappings/hashCode"
  "mappings/mapping2"
  "mappings2/mapping2"
  "mappings2/wrongParent"
  "basic/as"
  "basic/as2"
  "basic/as3"
)

# PKL-097: list of upstream fixtures whose `eval -f json` output
# matches the upstream `<dir>/<name>.json` gold byte-for-byte after
# `extract_output_value` unwraps the `output { value }` envelope.
# Most upstream JSON-renderer fixtures additionally need converters,
# Float numerics, or stdlib types (List / Set / Map / Pair / IntSeq)
# we have not yet implemented; only fixtures that gold-match through
# the existing JSON renderer go on the list.
JSON_GOLD_FIXTURES=(
  "api/jsonRenderer1.json"
  "api/jsonRenderer2.json"
  "api/jsonRenderer3.json"
  "api/jsonRenderer6.json"
  "api/jsonRenderer9.json5"
)

# PKL-153b: YAML renderer-output fixtures whose `output { renderer =
# new YamlRenderer {} }` path matches the upstream `.yml` gold.
YAML_GOLD_FIXTURES=(
  "api/yamlRenderer1.yml"
  "api/yamlRenderer2.yml"
  "api/yamlRenderer3.yml"
  "api/yamlRenderer6.yml"
  "api/yamlRenderer8.yml"
  "api/yamlRenderer9.yml"
  "api/yamlRenderer10.yml"
  "api/yamlRendererBug66849708.yml"
  "api/yamlRendererEmpty.yml"
  "api/yamlRendererIndentationWidth2.yml"
  "api/yamlRendererIndentationWidth4.yml"
  "api/yamlRendererIndentationWidth5.yml"
  "api/yamlRendererKeys.yml"
  "api/yamlRendererStrings.yml"
)

# PKL-126a: list of upstream fixtures whose `eval` output (the input
# already routes through `output { renderer = new PListRenderer {} }`,
# so no `-f plist` is needed) matches the upstream `<dir>/<name>.plist`
# gold byte-for-byte. Most other pListRenderer fixtures upstream lean
# on converter machinery (PKL-127) or on Set / Map / Pair / IntSeq
# value variants (PKL-119); they get promoted as those slices land.
PLIST_GOLD_FIXTURES=(
  "api/pListRenderer1.plist"
)

# PKL-126b: XML renderer fixtures whose `output { renderer = new
# xml.Renderer {} }` path now matches the upstream `.xml` gold.
XML_GOLD_FIXTURES=(
  "api/xmlRenderer1.xml"
  "api/xmlRenderer2.xml"
  "api/xmlRenderer3.xml"
  "api/xmlRenderer6.xml"
  "api/xmlRenderer9.xml"
  "api/xmlRendererCData.xml"
  "api/xmlRendererElement.xml"
  "api/xmlRendererInline.xml"
  "api/xmlRendererInline2.xml"
  "api/xmlRendererInline3.xml"
  "api/xmlRendererHtml.xml"
)

# PKL-126c: textproto renderer fixtures whose `output { renderer =
# new protobuf.Renderer {} }` path now matches the upstream `.txtpb`
# gold. Apple Pkl's current protobuf renderer emits text format only;
# binary protobuf / .proto schema loading is not part of this slice.
TEXTPROTO_GOLD_FIXTURES=(
  "api/protobuf3.txtpb"
)

# PKL-148bm: jsonnet renderer fixtures whose `output { renderer = new
# jsonnet.Renderer {} }` path matches the upstream `.jsonnet` gold.
# jsonnetRenderer7 (Mixin / Function1 rendering error message) and
# jsonnetRenderer8 (convertPropertyTransformers + LineComment
# annotation) are intentionally postponed; they live outside this
# slice's renderer surface.
JSONNET_GOLD_FIXTURES=(
  "api/jsonnetRenderer1.jsonnet"
  "api/jsonnetRenderer2.jsonnet"
  "api/jsonnetRenderer3.jsonnet"
  "api/jsonnetRenderer6.jsonnet"
)

# Files whose `pkl parse` should succeed even when we cannot evaluate
# them (e.g. they exercise stdlib gaps or runtime semantics outside
# the implemented slice). Keeping a parse-only check pins the parser
# surface.
PARSE_ONLY=(
  "basic/parens.pkl"
  "basic/import1.pkl"
  "basic/import2.pkl"
  "basic/import3.pkl"
  "basic/imported.pkl"
  "modules/filename with spaces.pkl"
  "modules/filename with spaces 2.pkl"
  "modules/objects.pkl"
)

parse_ok() {
  local label="$1"
  local file="$2"
  local output
  output="$(moon run cmd/mpkl --target native -- parse "$file")"
  if ! grep -Fxq "ok" <<<"$output"; then
    printf 'upstream parse failed: %s\n%s\n' "$label" "$output" >&2
    exit 1
  fi
  printf 'upstream parse ok: %s\n' "$label"
}

eval_matches_gold() {
  local label="$1"
  local input="$2"
  local gold="$3"
  # PKL-148q: capture mpkl stdout to a temp file and bytewise-diff,
  # instead of the previous `$(...)` capture + `printf '%s\n'` wrapping
  # which always appended a trailing newline. The wrapper masked any
  # disagreement on the final byte: `api/moduleOutput`'s gold ends
  # without `\n` (Apple Pkl writes `output.text` verbatim), so the
  # previous shape forced a 1-byte mismatch even after the CLI bypass
  # emitted the correct payload.
  local tmp
  tmp="$(mktemp)"
  moon run cmd/mpkl --target native -- eval --package-cache "$PKG_CACHE" "$input" > "$tmp"
  if ! diff -u "$gold" "$tmp" >/tmp/upstream-smoke-diff.$$; then
    printf 'upstream eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-diff.$$ >&2
    rm -f /tmp/upstream-smoke-diff.$$ "$tmp"
    exit 1
  fi
  rm -f /tmp/upstream-smoke-diff.$$ "$tmp"
  printf 'upstream eval ok: %s (gold match)\n' "$label"
}

eval_matches_gold_with_io() {
  # Same as `eval_matches_gold` but seeds the controlled env + `-p`
  # properties Apple Pkl's LanguageSnippetTests runner uses for
  # fixtures that exercise `read*("env:...")` / `read*("prop:...")` /
  # property paths containing spaces. Matches the values
  # `coverage-by-category.sh` already passes.
  local label="$1"
  local input="$2"
  local gold="$3"
  local tmp
  tmp="$(mktemp)"
  # The fixture's `read*("env:**")` glob walks the full environment,
  # so we wipe it with `env -i` and rebuild from scratch. `$MPKL` is
  # an absolute path so PATH lookup isn't needed for the binary call;
  # only the values below are visible to the snippet.
  env -i \
    NAME1=value1 \
    NAME2=value2 \
    'foo bar=foo bar' \
    '/foo/bar=foobar' \
    'file:///foo/bar=file:///foo/bar' \
    "$ROOT/$MPKL" eval \
      -p name1=value1 \
      -p name2=value2 \
      -p /foo/bar=foobar \
      --package-cache "$ROOT/$PKG_CACHE" \
      "$input" > "$tmp"
  if ! diff -u "$gold" "$tmp" >/tmp/upstream-smoke-io-diff.$$; then
    printf 'upstream eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-io-diff.$$ >&2
    rm -f /tmp/upstream-smoke-io-diff.$$ "$tmp"
    exit 1
  fi
  rm -f /tmp/upstream-smoke-io-diff.$$ "$tmp"
  printf 'upstream eval ok: %s (gold match, env+props)\n' "$label"
}

# Fixtures whose `read*` / `env:` / `prop:` calls require the
# controlled environment Apple Pkl's snippet runner sets up.
IO_GOLD_FIXTURES=(
  "basic/importGlob"
  "basic/read"
  "basic/readGlob"
)

eval_contains() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local output
  output="$(moon run cmd/mpkl --target native -- eval "$file")"
  if ! grep -Fq "$expected" <<<"$output"; then
    printf 'upstream eval failed: %s\nexpected: %s\n%s\n' "$label" "$expected" "$output" >&2
    exit 1
  fi
  printf 'upstream eval ok: %s\n' "$label"
}

# PKL-097: byte-diff `eval -f json` output against the upstream JSON
# gold file. Same gating shape as `eval_matches_gold` but runs the
# JSON renderer; the CLI's `extract_output_value` strips the
# `output {}` envelope so `output.value` matches Apple Pkl's
# JsonRenderer-on-output.value behavior.
eval_json_matches_gold() {
  local label="$1"
  local input="$2"
  local gold="$3"
  local actual
  actual="$(moon run cmd/mpkl --target native -- eval -f json "$input")"
  if ! diff -u "$gold" <(printf '%s\n' "$actual") >/tmp/upstream-smoke-json-diff.$$; then
    printf 'upstream json eval mismatch: %s\n' "$label" >&2
    cat /tmp/upstream-smoke-json-diff.$$ >&2
    rm -f /tmp/upstream-smoke-json-diff.$$
    exit 1
  fi
  rm -f /tmp/upstream-smoke-json-diff.$$
  printf 'upstream json eval ok: %s (gold match)\n' "$label"
}

# Parse-only sanity for files that exercise the parser even when
# evaluation depends on unimplemented features.
for entry in "${PARSE_ONLY[@]}"; do
  parse_ok "$entry" "$UPSTREAM/$entry"
done

# Gold-match each fixture in the curated list.
ok_count=0
for label in "${GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label.pcf"
  ok_count=$((ok_count + 1))
done

# JSON gold-match for fixtures that route their output through
# `output.value`. The CLI's `extract_output_value` strips the
# `output { value }` envelope before the JSON renderer sees the
# value, so the diff lines up with Apple Pkl's upstream JSON output.
# Each label already carries its `.json` suffix because upstream
# names the input as `<name>.json.pkl` and the gold as `<name>.json`.
json_ok_count=0
for label in "${JSON_GOLD_FIXTURES[@]}"; do
  eval_json_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  json_ok_count=$((json_ok_count + 1))
done

yaml_ok_count=0
for label in "${YAML_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  yaml_ok_count=$((yaml_ok_count + 1))
done

# PKL-126a: gold-match each fixture whose `output { renderer = new
# PListRenderer {} }` block routes through the plist renderer. The
# rendered envelope is exactly the upstream `.plist` gold file, so
# `eval_matches_gold` (no `-f` override needed because the driver
# path detects the renderer from the AST) lines up byte-for-byte.
plist_ok_count=0
for label in "${PLIST_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  plist_ok_count=$((plist_ok_count + 1))
done

xml_ok_count=0
for label in "${XML_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  xml_ok_count=$((xml_ok_count + 1))
done

textproto_ok_count=0
for label in "${TEXTPROTO_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  textproto_ok_count=$((textproto_ok_count + 1))
done

jsonnet_ok_count=0
for label in "${JSONNET_GOLD_FIXTURES[@]}"; do
  eval_matches_gold "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label"
  jsonnet_ok_count=$((jsonnet_ok_count + 1))
done

io_ok_count=0
for label in "${IO_GOLD_FIXTURES[@]}"; do
  eval_matches_gold_with_io "$label" "$UPSTREAM/$label.pkl" "$GOLD/$label.pcf"
  io_ok_count=$((io_ok_count + 1))
done

printf 'upstream-smoke: %d gold-match fixtures passed\n' "$ok_count"
printf 'upstream-smoke: %d json gold-match fixtures passed\n' "$json_ok_count"
printf 'upstream-smoke: %d yaml gold-match fixtures passed\n' "$yaml_ok_count"
printf 'upstream-smoke: %d plist gold-match fixtures passed\n' "$plist_ok_count"
printf 'upstream-smoke: %d xml gold-match fixtures passed\n' "$xml_ok_count"
printf 'upstream-smoke: %d textproto gold-match fixtures passed\n' "$textproto_ok_count"
printf 'upstream-smoke: %d jsonnet gold-match fixtures passed\n' "$jsonnet_ok_count"
printf 'upstream-smoke: %d io gold-match fixtures passed (env + props)\n' "$io_ok_count"
