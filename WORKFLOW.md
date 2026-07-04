---
tracker:
  kind: linear
  project_slug: "ai-native-workspace-202646c35423"
  api_key: $LINEAR_API_KEY
  active_states: ["Todo", "In Progress", "Merging", "Rework"]
  terminal_states: ["Human Review", "Done", "Canceled", "Duplicate"]
  required_labels: ["claude-code"]

workspace:
  root: /Users/hermes/.symphony/workspaces/claude-code

hooks:
  after_create: |
    set -eu
    git clone --depth 1 git@github.com:MH4GF/claude-code.git .

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

## Workflow protocol

- session 起動直後に `symphony-workflow` skill を呼ぶ。status routing / workpad 運用 / 実装 / sweep / `Human Review` 遷移 / land まで、進行は全て同 skill の手順に従う
- `symphony-workflow` skill が利用できない環境では実装に入らない。Linear issue に blocker comment (何が missing か / unblock に必要な人間の action) を 1 件書き、issue を `Human Review` へ動かして shutdown する
- 下の「本 repo 固有ルール」は skill の共通手順を上書きする

## 本 repo 固有ルール

- スコープ外改善の別 issue 化の例外: main 由来の既存違反が PR CI を block した場合、別 issue 化せず本 PR 内で inline 一括 fix する
  - 本 issue の original 受け入れ条件は別途満たす
  - PR description に「スコープ外一括 fix の理由」を 1 段落書く。テンプレート: `本 PR は main 由来の既存違反が PR CI を block したため、本 issue 本来のスコープ外の一括 fix を含む。original の受け入れ条件は別途満たしている。`
- Completion bar への追加要件が 1 つある
  - markdown / script / 設定の編集を含む PR (`*.md` / `*.sh` / `*.sb` / `*.json`) は `narrative-reviewer` skill が PASS している。FAIL なら本 turn 内で対象ファイルを修正して PASS まで再実行する

## スコープ外

issue が次のいずれかの作業を含むなら、止まってユーザーに label 修正を依頼する。

- vault 内容の編集 (`MH4GF/works`)
- Symphony orchestrator のコード (`MH4GF/symphony`)
- secrets / workspace 固有 identifier のコミット
