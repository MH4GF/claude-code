---
name: codex-review
context: fork
description: codex review CLIを使用したコードレビュー。セルフレビュー、PR作成前チェック、コミット確認に使用。「レビューして」「変更を確認して」で発動
---

# Codex Review

`codex review`でコードレビューを実行。

## 実行フロー

```
git status --porcelain
    │
    ├─ 出力あり → codex review --uncommitted
    │
    └─ 出力なし → codex review --base origin/main
                  （または origin/master）
```

ユーザーがコミット SHA を指定 → `codex review --commit <sha>`

## カスタムプロンプト

```bash
codex review --base origin/main "セキュリティ観点で確認"
```
