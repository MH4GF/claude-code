---
name: review
description: ブランチ diff (vs main) を file:line で構造化レポートする非妥協レビュー skill。「細かいレビューする」「コードレビューして」「これじゃダメ」「もっとシンプルに」「この PR をレビュー」「コミット前にレビュー」「diff を見て」「PR を出す前に見て」「全部見て」「どこから直すべきか」等のように、ユーザーが diff 全体を見直したい状況で必ず発動する。変更ファイル拡張子から ts-review / go-review / narrative-review に振り分け、表層 AI ノイズは deslop、設計再フレーミング機会は thermo-nuclear に委譲するメタレイヤとして働く。ただし thermo-nuclear / deslop / ts-review / go-review / narrative-review がユーザーから明示的に呼ばれた場面は対象外 — それらは review を経由せず直接起動するべき。常に report-only。ユーザーが自分のレビューを通すまで外部へ書き込まない HOTL 原則を死守する。
---

# review

ブランチ diff の構造化レビューを担うメタレイヤ skill。観点を自前で抱え込まない方針を取る。次のとおり委譲する
- 表層ノイズ → deslop
- 設計レベル → thermo-nuclear
- 言語固有 (TS / Go) → ts-review / go-review
- ナラティブ (markdown / script / 設定) → narrative-review

review 自身は呼び出しと振り分け、最終レポートのまとめだけを行う。

## 守ること

振る舞いはレポート-only に限定する。コードへの edit は一切しない。HOTL 原則の徹底で、ユーザーが「自分のレビューを通すまで外へは何も出したくない」と明言している。

観点を網羅できる気がしても重複指摘を作らない。同じ箇所へ複数の角度から書くと明確に嫌われる。

該当なしの場合は「指摘事項なし」と明記する。でっちあげは禁止。

文体は日本語、箇条書き、簡潔。長文ナラティブは書かない。

## フロー

### 1. 対象 diff の特定

PR URL / branch / コミット範囲の指定をユーザーへ確認する。未指定なら `git diff origin/main...HEAD` を既定とする。main の無いリポでは master、ユーザーの明示があるならそれに従う。

### 2. 変更ファイルの言語振り分け

```bash
git diff --name-only origin/main...HEAD | sort -u
```

拡張子で振り分ける
- `*.ts` / `*.tsx` → ts-review skill を呼ぶ
- `*.go` → go-review skill を呼ぶ
- `*.md` / `*.sh` / `*.sb` / `*.json` → narrative-review skill を呼ぶ
- それ以外 (`*.sql` / `*.rs` 等) はこの skill で直接見る

混在時は該当する子 skill を順に呼び、それぞれの指摘事項をまとめる。

### 3. 表層ノイズの委譲判定

deslop が表層ノイズ (過剰コメント / 防御的 try/catch / 不要 any / 深ネスト / 周辺と不整合な書き方) を担当している。表層ノイズが多そうなら自分で同じ観点を書かず、`/deslop` の先行実行をユーザーへ提案する。流さない判断なら表層は軽く言及して終わる。

### 4. 設計再フレーミング機会の委譲判定

設計レベル (1000 行越え / レイヤ越境 / スパゲッティ成長 / 薄いラッパー) を見て「構造ごと消せそう」と感じたら、自身では深追いせず、候補だけ列挙して `/thermo-nuclear-code-quality-review` を呼ぶか確認する。thermo-nuclear は重く尖ったレビューなので、明示要求が無い限り起動しない。

### 5. 残った領域を直接レビュー

言語別 skill / deslop / thermo-nuclear のいずれにも当てはまらない領域を自分で見る。代表的には次のとおり
- 命名 — 関数 / 変数 / ファイルの命名が周辺と揃っているか
- 凝集 — 1 関数が複数の責務を抱えていないか
- API 設計 — 公開関数の signature が呼び出し側で扱いづらくないか
- 規約遵守 — 周辺コードと書き方が乖離していないか (フォーマッタが見ない範囲)

## 報告フォーマット

次のテンプレで出力する。

```markdown
## レビュー結果

対象: `<base>...<head>` (変更 <N> ファイル)

### 指摘事項
- `path/to/file.ts:42` — 現状: <観察> / 問題: <なぜ良くないか> / 提案: <修正案>
- `path/to/file.ts:80` — ...

### 委譲提案
- 表層ノイズが <件数> あり。`/deslop` で一括検出を推奨
- 設計再フレーミング候補が <件数> あり。`/thermo-nuclear-code-quality-review` で深掘り推奨

(該当なしの場合は「指摘事項なし」と書く)
```

優先度は付けない。挙げた指摘事項はすべて呼び出し元が対応する前提。

## 子 skill を呼ぶときの注意

ts-review / go-review / narrative-review を呼ぶときは、対象ファイルパスを引数で渡す。

```
/ts-review <file1>.ts <file2>.tsx
/go-review <file1>.go <file2>.go
/narrative-review <file1>.md <file2>.sh
```

子 skill の指摘をそのまま自分の報告に混ぜず、子 skill の出力を「ts-review より」「go-review より」「narrative-review より」と見出しで区切って残す。これで「どの skill が言ったか」を後から追える。

## 自分の出力に対する自己チェック

レポートを返す前に次を確認する
- 同じ file:line への重複指摘が無いか
- lint / hook がカバー済の領域を書いていないか (linter / フォーマッタ / 文体チェッカ等のスコープ)
- 「あった方が良い」だけの根拠の弱い指摘を挙げていないか
- 報告の語彙が日本語の用語規約 (`prh.yml` 等があれば) に違反していないか
