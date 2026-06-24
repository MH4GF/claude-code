---
name: md-reviewer
description: markdown 編集 PR の差分の文量バランスを、コンテキスト未継承の fresh subagent に判定させる。`SKILL.md` / `CLAUDE.md` / `commands/*.md` の散文肥大化を検出する。Symphony bg session が Human Review へ遷移する直前に必須実行する。「md レビュー」「文量バランス」で手動発動も可
---

# md-レビュアー

## 手順

### 1. 対象 diff を抽出

```bash
git fetch origin main
git diff --name-only origin/main...HEAD -- '*.md' '**/*.md'
```

出力が空なら `PASS (no markdown changes)` を返して終了する。

### 2. fresh subagent を起動

`Agent` ツールを `subagent_type: "general-purpose"` で呼ぶ。prompt は下記テンプレに対象ファイル list を埋める。

```
現 branch の markdown 編集を文量バランス観点で review してほしい。判定基準は 4 観点。厳格適用の対象は `SKILL.md` / `CLAUDE.md` / `commands/*.md`。`README.md` 等の一般 docs には緩く適用する。

1. 判定 / 分岐ロジックがコマンド節 (実行可能 snippet) に集約されているか
2. description / 目的 / 手順が最小置換で済んでいるか
3. 手順への補足が 1 行に圧縮されているか
4. 差分の経緯解説が本文に残っていないか (経緯は `commit` メッセージ / PR description 側にあるべき)

対象ファイル:
<対象 file path 列挙>

各ファイルについて次を実行する。
- `git diff origin/main...HEAD -- <file>` で diff を見る
- `Read <file>` でファイル全体を読み diff 後の総量バランスを掴む
- 4 観点で評価し、問題があれば行番号付きで列挙する

最後に `PASS` か `FAIL` のいずれかを 1 行で出力する。`FAIL` の時は箇条書きで指摘事項と推奨修正を添える。`commit` メッセージ / PR description の記載は判定対象外、skill 本文の散文のみ対象。
```

### 3. 結果を呼び出し元へ返す

subagent の最終出力をそのまま呼び出し元へ返す。`FAIL` の時は対象 markdown を修正してから本 skill を再実行する。

## ガードレール

- 文量バランスのみ判定する — 文法 / スペル / 表現の品質は対象外
- markdown 以外 (コード / 設定) は対象外
