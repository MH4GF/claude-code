---
description: 複数の観点で並列コードレビューを実行し、結果を統合後すべて修正する
---

## Task

以下の 3 つのレビューを**並列**で実行し、結果を統合して報告する。

### 実行するレビュー

1. codex-review — `codex review` CLI によるコードレビュー
2. claude-md-checker — CLAUDE.md 準拠チェック (ユーザースコープ agent)
3. deslop — AI 生成コード由来のノイズ（過剰コメント・防御的 try/catch・`any` キャスト等）を検出（Skill ツール経由）

### 実行方法

以下を**同時に**起動する：

```
Agent tool: subagent_type: "claude-md-checker" → CLAUDE.md 準拠チェック
Skill tool: skill: "codex-review" → コードレビュー
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

### Deslop
[結果]

## 対応が必要な項目
[優先度の高い指摘をリストアップ]
```

### レビュー後の修正

レポート出力後、「対応が必要な項目」に挙げた指摘を**すべて修正する**。修正が完了するまで停止しないこと。

- 各指摘について該当ファイルを編集し、問題を解消する
- 修正完了後、最終的な変更サマリーを報告する
