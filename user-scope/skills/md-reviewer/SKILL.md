---
name: md-reviewer
context: fork
description: markdown 編集 PR の差分を観点別にレビューする。「md レビュー」「文量バランス」で発動。Symphony bg session が Human Review へ遷移する直前に必須実行する
---

# マークダウンテキストのレビュー

main ブランチとの diff の markdown を下記ルールで判定する。**ファイル編集は行わない**。修正判断は呼び出し元に委ねる。

## 対象

```bash
git diff --name-only origin/main...HEAD -- '*.md' '**/*.md'
```

出力が空なら `PASS (no markdown changes)` を返して終了する。

## ルール

### 文量バランス

`SKILL.md` / `CLAUDE.md` / `commands/*.md` の散文肥大化を 4 観点で検出する。`README.md` 等の一般 docs には緩く適用する。

1. 判定 / 分岐ロジックがコマンド節 (実行可能 snippet) に集約されているか
2. description / 目的 / 手順が最小置換で済んでいるか
3. 手順への補足が 1 行に圧縮されているか
4. 差分の経緯解説が本文に残っていないか (経緯は `commit` メッセージ / PR description 側にあるべき)

各ファイルにつき `git diff origin/main...HEAD -- <file>` と `Read <file>` を実行し、問題があれば行番号付きで列挙する。

## 出力

`PASS` か `FAIL` を 1 行出力する。`FAIL` なら箇条書きで指摘事項と推奨修正を添える。
