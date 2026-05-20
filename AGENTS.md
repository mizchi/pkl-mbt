# AGENTS.md

ユーザーには日本語で答えて。

## 開発スタイル

- TDD で開発する。探索、Red、Green、Refactoring の順に進める。
- KPI やカバレッジ目標が与えられたら、達成するまで試行する。
- 不明瞭な指示は質問して明確にする。

## コード設計

- 関心の分離を保つ。
- 状態とロジックを分離する。
- 可読性と保守性を重視する。
- コントラクト層は API、型、pkspec で厳密に定義し、実装層は再生成可能に保つ。

## このプロジェクト

- Apple Pkl の parser、interpreter、typechecker を pure MoonBit で実装する。
- parser の CST は `mizchi/cst` を使う。
- incremental analysis と typecheck cache は `mizchi/ripple` を使う。
- pkspec の仕様は `specs/` に置き、ローカルスキーマは `pkspec/` に vendoring する。
- タスク定義は pkfire の `Taskfile.pkl` に集約する。

## ツール

- タスク: `pkf run ci`, `pkf run release-check`
- Node.js: pnpm, v24+
- E2E: playwright
- MoonBit: `moon fmt`, `moon check --deny-warn`, `moon test`, `moon info`
- pkspec: `pkspec exec -f specs/Test.pkl`, `pkspec spec --check specs/Spec.pkl specs/Test.pkl`

## 環境

- GitHub: mizchi
- リポジトリ: ghq 管理 (`~/ghq/github.com/owner/repo`)

## 現在の開発状況

- 上流の Apple Pkl LanguageSnippetTests に対する gold-match: **281 / 391 (71.9%)**。確認は `pkf run coverage` で。
- カテゴリ別の内訳と最終更新は `README.md` の「Per-category PCF gold-match」表が source of truth。

## 次に触るべきタスク

GitHub Issues に「user impact 順」で並んでいる。次セッションは **必ず最初に umbrella issue を見る**:

- **[#8 Tracking: practical blockers](https://github.com/mizchi/pkl-mbt/issues/8)** — Tier1/Tier2/Tier3 で並べた採用ブロッカーの全体マップ。チェック済み行で進捗を追える。

個別 issue / release backlog (impact 大きい順):

- [#6 XML / Protobuf renderer bodies](https://github.com/mizchi/pkl-mbt/issues/6) — XML 3 fixtures / textproto 1 fixture は通過済み。残りの Tier 1 renderer parity。
- [#1 Evaluate Apple Pkl stdlib modules](https://github.com/mizchi/pkl-mbt/issues/1) — `external` / `abstract` / variance / `pkl:` stdlib resolution の長期ブロッカー。
- `TODO.md` Priority 5 — Generic `as` / `is` / typed collection retention。次に触る候補。
- `TODO.md` Priority 1 — Numeric / Bytes parity。
- `TODO.md` Priority 2 — Resource / glob host surface。
- `TODO.md` Priority 3 — Shape-aware object body evaluation for remaining generator DIFFs。

## 次セッションを始めるときの定型手順

1. `gh issue list --state open` で生きてる issue を確認。新規ブロッカーが追加されてれば umbrella (#8) に反映。
2. `pkf run coverage` で現在の gold-match を取り、`README.md` の数字とズレてないか確認。
3. 取り組む issue / TODO priority を 1 件 pick。AST に触る変更は破壊範囲が大きいので、別ブランチ + 段階的 commit を推奨。
4. 1 issue 1 PR が原則。 小さな PASS を狙う場合は `coverage-by-category.sh` の DIFF 出力から fixture 単位で当たる。
