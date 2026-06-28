---
description: 複数の観点で並列コードレビューを実行し、結果を統合レポートで出力して終了する
---

## Task

以下の 4 つのレビューを**並列**で実行し、結果を統合して報告する。

### 実行するレビュー

1. codex-review — `codex review` CLI によるコードレビュー
2. qa:claude-md-checker — CLAUDE.md 準拠チェック
3. /code-review — 現在 diff の正当性バグ (correctness) を effort level に応じて検出 (スラッシュコマンド)
4. deslop — AI 生成コード由来のノイズ（過剰コメント・防御的 try/catch・`any` キャスト等）を検出（Skill ツール経由）

### 実行方法

以下を**同時に**起動する：

```
Agent tool: subagent_type: "qa:claude-md-checker" → CLAUDE.md 準拠チェック
Skill tool: skill: "codex-review" → コードレビュー
SlashCommand: /code-review → 正当性バグ検出
Skill tool: skill: "deslop" → AI 生成ノイズ検出
```

### 出力形式

各レビューの結果を以下の形式でまとめる：

```markdown
## レビュー結果サマリー

### Codex Review
[結果]

### CLAUDE.md Checker
[結果]

### Code Review (Correctness)
[結果]

### Deslop
[結果]

## 対応が必要な項目
[優先度の高い指摘をリストアップ]
```

レポート出力をもって本コマンドは終了する。以降のアクションはレビュー結果を踏まえて呼び出し元が判断する。
