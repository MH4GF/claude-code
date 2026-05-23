---
description: 複数の観点で並列コードレビューを実行
---

## Task

以下の5つのレビューを**並列**で実行し、結果を統合して報告する。

### 実行するレビュー

1. **codex-review** - `codex review` CLI によるコードレビュー
2. **qa:claude-md-checker** - CLAUDE.md 準拠チェック
3. **simplify** - コードの簡潔性・保守性・再利用性・品質・効率性チェックと修正（Skill tool 経由）
4. **deslop** - AI 生成コード由来のノイズ（過剰コメント・防御的 try/catch・`any` キャスト等）を検出（Skill tool 経由）
5. **thermo-nuclear-code-quality-review** - 構造的負債・設計再フレーミング機会の厳格レビュー（Skill tool 経由）

### 実行方法

以下を**同時に**起動する：

```
Agent tool: subagent_type: "qa:claude-md-checker" → CLAUDE.md 準拠チェック
Skill tool: skill: "codex-review" → コードレビュー
Skill tool: skill: "simplify" → 簡潔性・品質チェック
Skill tool: skill: "deslop" → AI 生成ノイズ検出
Skill tool: skill: "thermo-nuclear-code-quality-review" → 厳格な構造品質レビュー
```

### 出力形式

各レビューの結果を以下の形式でまとめる：

```markdown
## レビュー結果サマリー

### Codex Review
[結果]

### CLAUDE.md Checker
[結果]

### Simplify
[結果]

### Deslop
[結果]

### Thermo-Nuclear
[結果]

## 対応が必要な項目
[優先度の高い指摘をリストアップ]
```

### ネクストアクション

結果出力後、**AskUserQuestion** ツールでネクストアクションを確認する。
