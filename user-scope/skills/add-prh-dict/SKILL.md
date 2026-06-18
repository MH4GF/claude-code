---
name: add-prh-dict
description: prh.yml に新しい英→日マッピングを追加したい時、本セッションを止めず Symphony 経由の bg session で追加 → コミット → PR まで自動実行させる。「prh に追加して」「辞書に追加」「prh.yml に entry 追加」「これも辞書化したい」「これも block するように」等で必ず発動する。本セッションを汚さず fire-and-forget で辞書更新したい場面の専用 skill。
---

# add-prh-dict

`prh.yml` への英→日マッピング追加を、Symphony 経由の bg session に丸投げする skill。本セッションが行うのは Linear issue 起票のみで、Symphony の claude-code workflow が次の poll で拾って bg session を ディスパッチ する。実際の Edit / コミット / push / PR 作成は dispatched session が担う。

## なぜ別セッションに投げるか

- 本セッションのコンテキストを乱さない。進行中タスクへ集中したい
- 辞書追加は機械作業なので、本セッションを止める価値がない
- 思いついた瞬間に投げて忘れられる。後でやろうとして忘れるリスクを避ける

## 起動条件

次のような要望が出た時に起動する。

- 「`X` を prh.yml に追加して」
- 「`X` も辞書化したい」
- 「これも prh で block するようにして」
- 会話中に複数の追加候補語が浮上した時 (まとめて 1 issue にする)

## 手順

### 1. 追加するエントリを確定する

次の 3 情報を文脈から抽出する。

- pattern — 英語の元の語。短い語は word boundary 付き regex を推奨 (例: `/\btx\b/i`)
- expected — 日本語の置換先 (例: `トランザクション`)
- カテゴリ — `prh.yml` 内の section 名 (`名詞` / `動詞` / `形容詞・副詞` / `比喩・造語`)

3 つすべてが文脈から確定できた場合、AskUserQuestion を呼ばずに次へ進む。

不足している情報がある場合のみ AskUserQuestion で確認する。複数不足する時は 1 回の AskUserQuestion 呼び出しに不足分の質問を束ねる (最大 3 つ)。揃った情報は質問しない。

質問の組み立て方は次のとおり。

- カテゴリ — 4 つの section 名 (`名詞` / `動詞` / `形容詞・副詞` / `比喩・造語`) を options に並べる
- pattern / expected — テキスト入力が必要なので、options を 2 つ程度添えた上で「Other」での自由入力を想定する。または通常のテキスト質問で聞いてもよい

確定情報なしに issue を起票しない。dispatched session は本セッションのコンテキストを引き継がないため、後から「やっぱりこう」が効かない。

### 2. Linear issue を起票する

下の `Linear issue body テンプレート` を `<pattern>` / `<expected>` / `<カテゴリ>` で変数置換し、`mcp__linear-mh4gf__save_issue` を次の引数で呼ぶ。

- `team` — `MH4GF`
- `project` — `ai-native-workspace-202646c35423` (project slug。WORKFLOW.md の `tracker.project_slug` と一致)
- `title` — `prh: <pattern> → <expected> を追加`
- `description` — 変数置換済みの body
- `state` — `Todo`
- `labels` — `["claude-code"]`

戻り値から `identifier` と `url` を取る。

### 3. ユーザーに報告する

ユーザーへ 1〜2 行で次を伝える。

- 起票した issue の identifier (verbatim) と URL
- Symphony の claude-code workflow が次の poll (約 30 秒以内) で拾って bg session を ディスパッチ する旨

その後は本セッションの元タスクに戻る。dispatched session の進行を本セッションで watch しない。

## Linear issue body テンプレート

dispatched session は issue description を唯一の情報源として動く。変数置換した結果が self-contained になるよう書く。

````markdown
## Outcome

- `prh.yml` の `<カテゴリ>` セクションに `<pattern>` → `<expected>` の entry を追加する
- `unslop -c .textlintrc.json --no-color prh.yml` が exit 0 で通る
- PR が `main` ベースで出ており、CI が green

## Why

`<pattern>` を日本語の地の文に混ぜないよう block 対象へ加える。`<カテゴリ>` として `<expected>` への置換を一律に強制する。

## 参考

- `prh.yml` (編集対象)
- `.textlintrc.json` (unslop の構文確認に使う config)
- `user-scope/CLAUDE.md` の `Japanese Writing Style` 節 (表記の根拠)

## 完了条件

- `prh.yml` の `<カテゴリ>` セクション末尾に `- expected: <expected>` / `  pattern: <pattern>` の entry が追加されている
- `unslop -c .textlintrc.json --no-color prh.yml` が exit 0 で通る
- PR が出ており、CI が green
- 既に同じ pattern が存在した場合は no-op として完了し、PR を出さず workpad に `already present` と記録した上で `Human Review` へ動かす

## 実装メモ

- 重複チェック — `prh.yml` を Read し、追加予定 pattern が既存 entry に含まれていれば no-op で終了する
- 編集箇所 — 該当 `<カテゴリ>` section コメント (`# 名詞` 等) 直下のリスト末尾に追加する
- 構文確認 — 編集後に `unslop -c .textlintrc.json --no-color prh.yml` を必ず実行し、exit 0 を確認する
- commit message — 1 行目を `prh: <pattern> → <expected> を追加`、本文を `<カテゴリ> として <pattern> の混入を block 対象にする。` にする
- pull --rebase — push 前に `pull` skill で `origin/main` を取り込む

## スコープ外

- 他の entry の編集 / 並び替え / 削除
- `prh.yml` 内 section 構造の変更
- `.textlintrc.json` や CI ファイルの変更
````

## 設計判断と理由

### brainstorming を呼ばない

本 skill が扱う入力は pattern / expected / カテゴリ の 3 つに固定される。Outcome / Why / 完了条件 もテンプレで決まりきった形へ落ちる。brainstorming は曖昧な意図を分解するためにある。本 skill の入力は最初から構造化されている。フリクションだけが残るので呼ばない。

### create-linear-issue を経由しない

`create-linear-issue` skill は `superpowers:brainstorming` を必須化している。本 skill で扱う情報は最初から 3 つに分解済みなので、design doc 議論のロジックを通すと最短経路がぼやける。3 情報が揃った時点で `mcp__linear-mh4gf__save_issue` を直接叩く。

### label を `claude-code` に固定する

`prh.yml` は `MH4GF/claude-code` repo root のファイル。Symphony の claude-code workflow はこの label の issue だけを拾う。他 label を付けると claude-code workflow から拾われない。誤って別 label を付与した場合、対応する別 repo 用の workflow から bg session が起動される。session 側に edit 先を持たないため、failed する。

### dispatched session の手順は issue body に書く

WORKFLOW.md は汎用 prompt で、prh 固有の重複チェック / unslop 構文確認 / コミット message format を含まない。これらを issue body の `実装メモ` 節に置くことで、dispatched session は issue description だけで完結できる。

### 本セッションでは prh.yml を一切触らない

dispatched session が単一情報源。本セッションが並行して `prh.yml` を編集すると、後発の push で衝突する。本セッションは issue 起票までで止める。

## エッジケース

- pattern と expected が同じ語で翻訳不要な場合 — 起票せず、ユーザーへ「prh で扱う必要がない」と伝える
- 同じ pattern が既存にある場合 — そのまま起票する。dispatched session が `prh.yml` Read 時に検出し、no-op で `Human Review` へ動かす
- 本セッションが worktree 内 — dispatched session は別 workspace で動く。本セッションの cwd は無関係
- Linear MCP `linear-mh4gf` が利用できない時 — issue 起票が落ちるため止まり、ユーザーへ「`claude mcp` で `linear-mh4gf` の認証を確認してほしい」と伝える。リトライしない
