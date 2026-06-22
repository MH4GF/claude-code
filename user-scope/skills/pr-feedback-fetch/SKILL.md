---
name: pr-feedback-fetch
context: fork
description: 指定 PR の 3 channel feedback (top-level / inline review / review summary) を 1 回で取得し structured markdown で返す。引数は PR 番号 / PR URL / なし (現 branch から解決) の 3 パターン。channel を取りこぼさない単一手順
---

# pr-feedback-fetch

指定された PR について、GitHub の 3 channel (top-level comment / inline review comment / review summary) を順序固定で取得する。出力は 1 つの structured markdown としてまとめる。

`gh pr view --comments` は top-level comment しか返さないため、inline review comment と review summary を独立に取得する必要がある。本 skill は 3 エンドポイントを不可分に呼び、`取得 channel: 3/3` を必ず明示する。

## 前提

- `gh` CLI が認証済み (`gh auth status` で `Logged in` になっている)
- 現 branch (引数なし時) または引数から PR 番号と repo (owner/repo) を解決できる
- 出力は structured markdown。呼び出し元が workpad / report / 判断材料に直接転記できる形

## スコープ外

- feedback への返信 / 対応コミット / push。本 skill は「取得して並べる」までで止める
- bot コメント (Actions / dependabot 等) のフィルタ判定。actionable かどうかの判断は呼び出し側に委ねる
- 過去の feedback 履歴の差分管理。常に最新 snapshot を全件取得する
- CI ステータス確認。`gh pr checks` は別経路で扱う

## 手順

### 1. 引数を解決する

呼び出し時の引数は 0 〜 1 個。次のいずれか。

- 引数なし — 現 branch をそのまま対象に `gh pr view --json number,url,headRefName,baseRepository` で PR 番号を解決する
- 数字 (例 `200`) — PR 番号として扱う。repo は `gh repo view --json nameWithOwner` で現 repo を採用する
- URL (例 `https://github.com/MH4GF/claude-code/pull/10`) — URL から `<owner>/<repo>` と PR 番号を分解する

引数を解決できない場合 (現 branch の PR が無い等) は即停止し、「PR 未解決」と書いた出力を返す。

### 2. 3 channel を順に取得する

解決した `<owner>/<repo>` と `<pr>` を使い、次の 3 コマンドを順に実行する。順序は固定。途中で止めない。

```bash
# 2-1. top-level の PR comment (issue comment と等価)
gh api repos/<owner>/<repo>/issues/<pr>/comments \
  --jq '.[] | {id, user: .user.login, type: .user.type, created_at, updated_at, body}'

# 2-2. inline review comment (diff 上の行コメント)
gh api repos/<owner>/<repo>/pulls/<pr>/comments \
  --jq '.[] | {id, user: .user.login, type: .user.type, path, line, original_line, side, created_at, updated_at, body, in_reply_to_id, pull_request_review_id}'

# 2-3. review summary (Approve / Request changes / Comment レビュー単位)
gh api repos/<owner>/<repo>/pulls/<pr>/reviews \
  --jq '.[] | {id, user: .user.login, type: .user.type, state, submitted_at, body}'
```

3 channel すべてが空でも 3 コマンドとも実行する。1 つでも省略すると本 skill の意味が失われる。

`gh api` が失敗した channel は、`> ERROR: <message>` として出力へ残し、呼び出し側に明示する。残り channel の取得は続行する。

### 3. 出力を整形する

次の構造の markdown を 1 通り返す。

```markdown
## PR feedback snapshot — <owner>/<repo>#<pr>

- 取得時刻 (UTC): <ISO-8601>
- PR URL: <URL>

### Top-level comments (channel 1/3) — N 件

- [@<user> · <created_at>] <body 1 行要約>
  - id: <id>
  - body:
    > <body 全文を引用ブロックに保持>

### Inline review comments (channel 2/3) — N 件

- [@<user> · <created_at>] `<path>:<line>` <side=RIGHT|LEFT>
  - id: <id> (review: <pull_request_review_id>, reply: <in_reply_to_id or n/a>)
  - body:
    > <body 全文を引用ブロックに保持>

### Review summaries (channel 3/3) — N 件

- [@<user> · <submitted_at>] state=<APPROVED|CHANGES_REQUESTED|COMMENTED|DISMISSED>
  - id: <id>
  - body:
    > <body 全文を引用ブロックに保持>

### 集計

- 取得 channel: 3/3 (top-level / inline review / review summary)
- 取得件数: top-level=N1, inline=N2, review=N3, 合計=N1+N2+N3
- エラー channel: <なし or 該当 channel 名と error 抜粋>
```

整形時の規約:

- 各 comment の `body` 全文を改変せず引用ブロックに貼る。要約だけでは inline review の文脈 (file path, line, side) が消えるため
- `user.type == "Bot"` の comment は除外せずそのまま出す。actionable 判定は呼び出し側
- `body` が空の comment (Approve / Reject の空 body 等) もエントリを出す。`body:` 行に `> (empty)` と書く
- `created_at` / `submitted_at` は API 返却値 (UTC ISO-8601) をそのまま貼る

## 設計判断と理由

### なぜ 3 channel を skill 1 つに固める

GitHub の PR feedback は 3 つの異なる API エンドポイントに分かれている。`gh pr view --comments` が返すのは top-level のみ。これだけで判断すると inline review comment と review summary を取りこぼす。本 skill は 3 エンドポイントを順序固定で不可分に呼ぶことで、呼び出し側に「channel を覚える / 個別判断する」余地を残さない。

### なぜ `gh pr view --comments` ではなく `gh api .../issues/<pr>/comments` を使う

`gh pr view --comments` は top-level の issue comment だけを人間向け整形で返す。本 skill は 3 channel すべてを同じ JSON 構造で並列に扱いたいので、`gh api` の生 endpoint を直接叩く。

### なぜ inline review comment の `path` / `line` / `side` を必ず出す

inline review comment は diff 上の特定行に紐付く。body 単独だと「何に対する指摘か」が判別できない。`path:line` と `side` (RIGHT=new, LEFT=old) を残すことで、呼び出し側が file を開いて即座に文脈を再現できる。

### なぜ bot コメントをフィルタしない

`Coderabbit` / `Devin` / `Renovate` 等の bot コメントは actionable なものとそうでないものが混ざる。本 skill 側で一律にフィルタすると、actionable な bot コメントを取りこぼす。`user.type == "Bot"` フィールドだけ出力へ残す。actionable 判定は呼び出し側に委ねる。

### なぜ取得時刻を出力に入れる

PR feedback は時間と共に増える。skill 出力を保存した時点での snapshot 時刻を明示することで、その後に来た feedback を「sweep 後」と判定できる。actionable comment の残存有無を判断したい時、snapshot 時刻以降の増分有無を確認する手がかりになる。

## エッジケース

### 現 branch に PR が無い

`gh pr view --json number` が exit code 非ゼロ。本 skill は即停止し、出力に「PR 未解決」と書いて返す。

### PR が draft

draft でも feedback は付く。channel 取得は通常どおり行う。draft 判定は本 skill の責務外。

### `gh api` が rate-limit に当たる

`gh api` 自体が指数バックオフでリトライする。本 skill 内では追加リトライを入れない。3 channel のいずれかが最終的に失敗した場合は、出力の「エラー channel」節にその旨を書く。

### bot が同じ inline 行に大量コメントする

`Coderabbit` 等は 1 PR に 10〜50 件以上の inline review comment を出すことがある。本 skill は全件出力し、件数を「集計」節に明示する。

### inline review comment の `in_reply_to_id` がある

reply chain は出力にそのまま貼る。`in_reply_to_id` を残すことで、呼び出し側がスレッドの親子関係を再現できる。

### review summary が空 (state=COMMENTED, body 空)

inline review comment を投稿した時に発生する「親 review record」。entry は出すが `body:` に `> (empty)` と書く。呼び出し側は inline review comment 本体を見ればよい。
