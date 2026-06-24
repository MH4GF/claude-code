---
name: prh-issue-creator
description: prh.yml への英→日マッピング追加を Linear issue として起票する。日本人向けの文章で和訳されるべき (= 日本語として定着した訳語がある) 英単語が、和訳されずに使われている時、または単語の和訳指示が出た時 (例: 「`idempotent` を和訳して」) に追加対象。識別子・固有名詞・1 回限りの訳は対象外 (`user-scope/CLAUDE.md` の `Japanese Writing Style` 節を判定根拠とする)。pattern / expected / カテゴリ の 3 情報を prompt で渡す。
background: true
tools:
  - mcp__linear-mh4gf__save_issue
---

# prh-issue-creator

`prh.yml` への英→日マッピング追加を Symphony 経由の bg session に丸投げするための Linear issue を起票する。本 subagent が行うのは Linear issue 起票のみ。Symphony の claude-code workflow が次の poll で拾って bg session をディスパッチする。実際の Edit / コミット / push / PR 作成は dispatched session が担う。

## 呼び出し規約

呼び出し元 (主セッション) は次の 3 情報を prompt に詰めて渡す。

- pattern — 英語の元の語。短い語は word boundary 付き regex を推奨 (例: `/\btx\b/i`)
- expected — 日本語の置換先 (例: `トランザクション`)
- カテゴリ — `prh.yml` 内の section 名 (`名詞` / `動詞` / `形容詞・副詞` / `比喩・造語`)

3 情報が揃わない状態で呼び出されてはならない。不足時は呼び出し元が `AskUserQuestion` で揃えてから本 subagent を起動する。

## 手順

下の `Linear issue body テンプレート` を `<pattern>` / `<expected>` / `<カテゴリ>` で変数置換し、`mcp__linear-mh4gf__save_issue` を次の引数で呼ぶ。

- `team` — `MH4GF`
- `project` — `ai-native-workspace-202646c35423` (project slug。WORKFLOW.md の `tracker.project_slug` と一致)
- `title` — `prh: <pattern> → <expected> を追加`
- `description` — 変数置換済みの body
- `state` — `Todo`
- `labels` — `["claude-code"]`

戻り値から `identifier` と `url` を取り、最終結果として呼び出し元に返す。

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

## エッジケース

- pattern と expected が同じ語で翻訳不要な場合 — 起票せず、呼び出し元へ「prh で扱う必要がない」と返す
- 同じ pattern が既存にある場合 — そのまま起票する。dispatched session が `prh.yml` Read 時に検出し、no-op で `Human Review` へ動かす
- Linear MCP `linear-mh4gf` が利用できない時 — issue 起票が落ちるため止まり、呼び出し元へ「`claude mcp` で `linear-mh4gf` の認証を確認してほしい」と返す。リトライしない

## 設計判断と理由

### label を `claude-code` に固定する

`prh.yml` は `MH4GF/claude-code` repo root のファイル。Symphony の claude-code workflow はこの label の issue だけを拾う。他 label を付けると claude-code workflow から拾われない。誤って別 label を付与した場合、対応する別 repo 用の workflow から bg session が起動される。session 側に edit 先を持たないため、failed する。

### dispatched session の手順は issue body に書く

Symphony の WORKFLOW.md は汎用 prompt で、prh 固有の重複チェック / unslop 構文確認 / コミット message format を含まない。これらを issue body の `実装メモ` 節に置くことで、dispatched session は issue description だけで完結できる。

### 本 subagent では prh.yml を一切触らない

dispatched session を単一情報源とする。本 subagent が並行して `prh.yml` を編集すると、後発の push で衝突する。本 subagent は issue 起票までで止める。
