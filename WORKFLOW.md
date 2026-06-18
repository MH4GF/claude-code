---
tracker:
  kind: linear
  project_slug: "ai-native-workspace-202646c35423"
  api_key: $LINEAR_API_KEY
  active_states: ["Todo"]
  terminal_states: ["In Review", "Done", "Canceled", "Duplicate", "Human Review Needed"]
  required_labels: ["claude-code"]

workspace:
  root: /Users/mh4gf/.symphony/workspaces/claude-code

hooks:
  after_create: |
    set -eu
    git clone --depth 1 git@github.com:MH4GF/claude-code.git .

agent:
  max_concurrent_agents: 2
  max_turns: 6

codex:
  command: claude
  claude_args: ["--permission-mode", "auto"]
  stall_timeout_ms: 600000
  turn_timeout_ms: 1800000
---

MH4GF/claude-code (public な Claude Code 設定・plugin marketplace) の clone で作業する。repo 構造の把握は root の `README.md` を起点とする。

## Issue

{{ issue.identifier }} - {{ issue.title }}

## Body

{{ issue.description }}

## Identifier ルール

`{{ issue.identifier }}` を branch 名と PR body にそのまま埋め込む。Linear の GitHub linking は identifier 完全一致で動くため、URL slug や title から推論した別形 (例: 余計な桁を足す等) を書かない。

## PR ルール

- `main` 直接 push 禁止。必ず `gh pr create` で PR を出す
- PR body 冒頭に `Closes {{ issue.identifier }}` を独立行で必須記載。末尾に {{ issue.url }} を併記
- issue が曖昧 (acceptance criteria が不明) なら、PR body に plan と質問を書いた draft PR を開いて止まる

## スコープ外

issue が次のいずれかの作業を含むなら、止まって ユーザー に label 修正を依頼する。

- vault 内容の編集 (`MH4GF/works`)
- Symphony orchestrator のコード (`MH4GF/symphony`)
- secrets / workspace 固有 identifier の コミット
