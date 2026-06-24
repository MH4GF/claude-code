---
name: md-reviewer
description: markdown 編集 PR の差分の文量バランスを、コンテキスト未継承の fresh subagent に判定させる。`SKILL.md` / `CLAUDE.md` / `commands/*.md` の散文肥大化を検出する。Symphony bg session が Human Review へ遷移する直前に必須実行する。「md レビュー」「文量バランス」で手動発動も可
---

# md-レビュアー

呼び出しセッションの「自分が書いた文脈を正当化するバイアス」を排除するため、別 subagent を `Agent` ツールで起動し、現 branch の markdown diff をフラットに review させる。

## 判定基準

subagent は次の 4 観点で diff を評価する (MH-89 由来)。厳格適用の対象は `SKILL.md` / `CLAUDE.md` / `commands/*.md`。`README.md` 等の一般 docs には緩く適用する。

1. 判定 / 分岐ロジックがコマンド節 (実行可能 snippet) に集約されているか — 散文で「こう判定する」「失敗時はこうなる」を別途解説していないか
2. description / 目的 / 手順が最小置換で済んでいるか — 既存節への小さな差替えで済む内容が、新規節として追加されていないか
3. 手順への補足が 1 行に圧縮されているか — サブステップとして展開せず `(snippet はコマンド節)` 形式で本文から参照しているか
4. 差分の経緯解説が skill 本文に残っていないか — 「今回追加した経緯」「過去の対応」等は `commit` メッセージや PR description にあるべき

## 手順

### 1. 対象 diff を抽出

```bash
git fetch origin main
git diff --name-only origin/main...HEAD -- '*.md' '**/*.md'
```

出力が空なら `PASS (no markdown changes)` を返して終了する。subagent は起動しない。

### 2. fresh subagent を起動

`Agent` ツールを `subagent_type: "general-purpose"` で呼ぶ。呼び出しセッションの作業文脈や設計意図を prompt に含めない。prompt は下記テンプレに対象ファイル list を埋めるだけ。

```
現 branch の markdown 編集を文量バランス観点で review してほしい。判定基準は 4 観点。`SKILL.md` / `CLAUDE.md` / `commands/*.md` は厳格、`README.md` 等は緩く適用する。

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

subagent の最終出力 (`PASS` / `FAIL` + 指摘) をそのまま呼び出し元へ返す。`FAIL` の時は対象 markdown を修正してから本 skill を再実行する。

## ガードレール

- 文法 / スペル / 表現の品質は判定対象外 — 文量バランスのみ
- markdown 以外のファイル (コード / 設定) は対象外
- 判定基準は固定 — 呼び出し元が prompt 内で観点を書き換えたり緩めたりしない
- subagent prompt に作業セッションの設計意図や正当化を入れない — diff そのものに語らせる
