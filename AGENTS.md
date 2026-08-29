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
- pkspec: `pkspec exec -f specs/Test.pkl`, `pkspec check specs/Spec.pkl specs/Test.pkl`

## 環境

- GitHub: mizchi
- リポジトリ: ghq 管理 (`~/ghq/github.com/owner/repo`)

## 現在の開発状況

- 現在 version は `0.7.0` (`moon.mod`)。
- 上流の Apple Pkl 0.32.1 LanguageSnippetTests に対する gold-match: **416 / 416 (100.0%)**。確認は `pkf run coverage` で。
- カテゴリ別の内訳と最終更新は `README.md` / `TODO.md` が source of truth。
- 0.2.0 で追加された embedded-API: `configure_sandbox_resource_reader(scheme, fn)`、 `extends` chain の base-local 解決、 cross-module recursive function、 `Listing<T>` 返り値推論、 `mpkl test --junit-reports <dir>`。 詳細は `README.md` の "0.2.0 highlights"。

## 次に触るべきタスク

GitHub Issues に「user impact 順」で並んでいる。次セッションは **必ず最初に tracking issue を見る**:

- **[#32 Tracking: Apple Pkl 0.32.1 compatibility gaps](https://github.com/mizchi/pkl-mbt/issues/32)** — 追加・変更された 17 fixture はすべて gold-match へ復帰し、0.7.0 release gate と文書同期を確認済み。

個別 issue / release backlog (impact 大きい順):

- `TODO.md` Current DIFF Snapshot — with-gold fixture は全件一致。次は NOGOLD の診断契約または open issue を user impact 順に選ぶ。
- [#1 Evaluate Apple Pkl stdlib modules](https://github.com/mizchi/pkl-mbt/issues/1) — `analyze` / `benchmark` / `release` module surface と長期 stdlib parity。
- #17 YAML Parser complex mapping keys — `api/yamlParser6` の gold-match 後に close 済み。
- #6 XML / Protobuf renderer bodies — upstream XML / Protobuf text fixtures の通過後に close 済み。

## 次セッションを始めるときの定型手順

1. `gh issue list --state open` で生きてる issue を確認。新規ブロッカーが追加されていれば tracking issue に反映。
2. `pkf run coverage` で現在の gold-match を取り、`README.md` の数字とズレてないか確認。
3. 取り組む issue / TODO priority を 1 件 pick。AST に触る変更は破壊範囲が大きいので、別ブランチ + 段階的 commit を推奨。
4. 1 issue 1 PR が原則。 小さな PASS を狙う場合は `coverage-by-category.sh` の DIFF 出力から fixture 単位で当たる。
