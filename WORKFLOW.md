---
tracker:
  kind: github
  provider:
    repo: MH4GF/claude-code
  active_states: ["Todo", "In Progress", "Merging", "Rework"]
  terminal_states: ["Done", "Canceled"]

review_watch:
  enabled: true
  states: ["Human Review"]
  on_conflict_state: "In Progress"

workspace:
  root: /Users/hermes/.symphony/workspaces/claude-code

hooks:
  after_create: |
    set -eu
    git clone --depth 1 https://github.com/MH4GF/claude-code.git .

agent:
  max_concurrent_agents: 2
  max_turns: 20

codex:
  command: /Users/hermes/.local/bin/safe-claude
  claude_args: ["--permission-mode", "bypassPermissions"]
  stall_timeout_ms: 600000
  turn_timeout_ms: 1800000
---

MH4GF/claude-code (public な Claude Code 設定・plugin marketplace) の clone で作業する。repo 構造は root の `README.md` を起点に把握する。

## Issue

{{ issue.identifier }} - {{ issue.title }}

## Body

{{ issue.description }}

{% if attempt %}
## Continuation context

- これはリトライ attempt #{{ attempt }}。チケットが active state のため再ディスパッチされた。
- 最初からやり直さず、現在の workspace 状態から resume する。
- 完了済みの調査や validation を繰り返さない。新規コード変更で必要な場合は除く。
- issue が active state の間は turn を終わらせない。required permissions/secrets が missing で blocked の場合は除く。
{% endif %}

## ワークフロー手順

- セッション起動直後に `symphony-workflow` スキルを呼ぶ。ステータスの振り分け / workpad 運用 / 実装 / レビュースイープ / `Human Review` 遷移 / マージまで、進行は全て同スキルの手順に従う
- `symphony-workflow` スキルが利用できない環境では実装に入らない。issue にブロッカーコメント (何が不足しているか / 解除に必要な人間の対応) を 1 件書き、issue を `Human Review` へ動かして終了する
- 下の「本リポジトリ固有ルール」はスキルの共通手順を上書きする

## 本リポジトリ固有ルール

- スコープ外改善の別 issue 化の例外: main 由来の既存違反が PR CI を阻んだ場合、別 issue 化せず本 PR 内でインライン一括修正する
  - 本 issue の本来の受け入れ条件は別途満たす
  - PR 本文に「スコープ外一括 fix の理由」を 1 段落書く。テンプレート: `本 PR は main 由来の既存違反が PR CI を block したため、本 issue 本来のスコープ外の一括 fix を含む。original の受け入れ条件は別途満たしている。`
- 完了バーへの追加要件が 1 つある
  - markdown / スクリプト / 設定の編集を含む PR (`*.md` / `*.sh` / `*.sb` / `*.json`) は `narrative-reviewer` スキルが PASS している。FAIL なら本ターン内で対象ファイルを修正して PASS まで再実行する

## スコープ外

issue が次のいずれかの作業を含むなら、止まってユーザーに label 修正を依頼する。

- vault 内容の編集 (`MH4GF/works`)
- Symphony orchestrator のコード (`MH4GF/symphony`)
- secrets / workspace 固有 identifier のコミット
