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
