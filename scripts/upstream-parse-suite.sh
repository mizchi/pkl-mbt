#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM="third_party/apple-pkl/pkl-core/src/test/files/LanguageSnippetTests/input"

is_parser_comparison_exception() {
  local rel="$1"
  case "$rel" in
    stringError1.pkl | \
    annotationIsNotExpression2.pkl | \
    amendsRequiresParens.pkl | \
    errors/binopDifferentLine.pkl | \
    errors/parser18.pkl | \
    errors/nested1.pkl | \
    errors/invalidCharacterEscape.pkl | \
    errors/invalidCharacterEscape2.pkl | \
    errors/invalidUnicodeEscape.pkl | \
    errors/unterminatedUnicodeEscape.pkl | \
    errors/keywordNotAllowedHere1.pkl | \
    errors/keywordNotAllowedHere2.pkl | \
    errors/keywordNotAllowedHere3.pkl | \
    errors/keywordNotAllowedHere4.pkl | \
    errors/moduleWithHighMinPklVersionAndParseErrors.pkl | \
    errors/underscore.pkl | \
    errors/shebang.pkl | \
    errors/emptyParenthesizedTypeAnnotation.pkl | \
    notAUnionDefault.pkl | \
    multipleDefaults.pkl | \
    modules/invalidModule1.pkl | \
    singleBacktick.pkl | \
    errors/delimiters/* | \
    errors/parser*.pkl | \
    parser/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

files=()
while IFS= read -r file; do
  rel="${file#"$UPSTREAM"/}"
  if ! is_parser_comparison_exception "$rel"; then
    files+=("$file")
  fi
done < <(find "$UPSTREAM" -type f -name '*.pkl' | sort)

moon run cmd/main --target native -- parse-many "${files[@]}"
