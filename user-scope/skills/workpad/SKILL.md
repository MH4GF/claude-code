---
name: workpad
description: issue 上の `## Codex Workpad` ヘッダ付き コメント を 検索 / 作成 / 更新 する スキル。バックグラウンドセッション の進捗を 1 つの コメント に集約し、ターン 上限到達 や CI 失敗 を跨いだ永続記憶として使う。バックグラウンドセッション 起動直後と作業節目ごとに発動する
---

# workpad

バックグラウンドセッションが issue へ集約する作業ノート用コメントを管理するスキル。
issue ごとに `## Codex Workpad` コメントを 1 つだけ維持する。再開時は同じコメントを読み直して作業を継続する。

## Tracker の判定

操作先は tracker ごとに違う。作業中の repo の `WORKFLOW.md` frontmatter `tracker.kind` を読んで分岐する。works repo のみ `agents/ai-native/WORKFLOW.md`、それ以外は repo root の `WORKFLOW.md` に置かれている。読み取れない場合は `linear` として扱う。

以降の手順は tracker 共通の骨格で、具体的な操作だけを Tracker 別操作から引く。

## 前提

- 対象 issue identifier (`kind: linear` なら `MH-40`、`kind: github` なら `#123`) が文脈から既知
- `kind: linear` は Linear MCP、`kind: github` は `gh` が利用可能

## スコープ外

- 別コメントへの分割書き込み。1 issue 1 ワークパッドで固定し、節ごとに別コメントを作らない
- 他人のコメントへの上書き。自分が作成したコメントのみ再利用する

## 手順

### 1. 既存ワークパッドを探す

対象 issue のコメント一覧を取得し、次の条件をすべて満たすコメントを探す。

- `body` が `## Codex Workpad` で始まる
- 作成者が自分自身
- (`kind: linear` のみ) 未 resolve である。resolved は人間が意図的に閉じた印として扱い、再利用せず新規作成する

複数該当した時は最新の 1 件を採用し、残りを後段で言及せず放置する (履歴として保つ)。

### 2a. 既存ワークパッドを更新する

該当コメントが見つかった場合、そのコメント ID を指定して本文を上書きする。

更新内容は「直近の進捗」+「次に取る行動」を反映する。env stamp 行は再生成して上書きする (短い SHA や cwd が変わるため)。

### 2b. 新規ワークパッドを作成する

該当コメントが無い場合、下記テンプレに沿って本文を作り、issue へコメントを投稿する。

```markdown
## Codex Workpad

<env-stamp>

### Plan

- [ ] step 1
- [ ] step 2

### Acceptance Criteria

- ...

### Validation

- 実行コマンドと結果

### Notes

- 設計判断のメモ

### Confusions

- 詰まったポイント、確認したい点
```

`<env-stamp>` を `host:abs-workdir@short-sha` 形式で書く。例: `mac-studio:/Users/hermes/ghq/github.com/MH4GF/claude-code@7cf89d5`。

- ホスト名を `hostname -s` から取得
- ワーキングディレクトリ絶対パスを `pwd` から取得
- 短い SHA を `git rev-parse --short HEAD` から取得

## Tracker 別操作

### kind: linear

| 操作 | 手段 |
| --- | --- |
| issue ID 解決 | Linear MCP の issue 取得ツールを identifier で呼び `id` (UUID) を得る。以降の呼び出しはこの UUID を使う |
| 自分の識別 | Linear MCP の自身ユーザー取得ツールで得たアカウントと、コメントの `user` を突き合わせる |
| コメント一覧 | Linear MCP のコメント一覧取得ツールを issue ID 指定で呼ぶ。`resolvedAt` が `null` のものだけ再利用対象 |
| 更新 | Linear MCP のコメント保存ツールを `id` 指定で呼び本文を上書きする |
| 新規作成 | Linear MCP のコメント保存ツールを issue 指定で呼ぶ |

### kind: github

identifier `#123` の `123` が issue number。`<repo>` は `WORKFLOW.md` の `tracker.repo` (`owner/name`)。

| 操作 | 手段 |
| --- | --- |
| 自分の識別 | `gh api user --jq .login` |
| コメント一覧 | `gh api repos/<repo>/issues/123/comments --paginate` で `id` / `user.login` / `body` を読む |
| 更新 | `gh api --method PATCH repos/<repo>/issues/comments/<comment_id> -F body=@<file>` |
| 新規作成 | `gh api repos/<repo>/issues/123/comments -F body=@<file>` |

本文は複数行になるのでファイルへ書き出して `-F body=@<file>` で渡す。コマンドライン引数へ直接埋めない。

GitHub の issue コメントに resolve 状態は無いため、resolved の判定は行わない。

## 各セクションの責務

| セクション | 用途 |
| --- | --- |
| Plan | 完了条件を分解したチェックリスト。完了したら `[x]` に変える |
| Acceptance Criteria | issue 本文の完了条件を転記。判定基準を 1 箇所にまとめる |
| Validation | 実行した検証コマンドと結果。CI 履歴では追えないローカル検証を残す |
| Notes | 設計判断、なぜそのアプローチを選んだか、参照した既存コード等 |
| Confusions | 詰まり、未解決の判断点、ユーザー 確認待ち事項。次ターンの起点になる |

## エッジケース

- コメント一覧取得が API 失敗で落ちた時。リトライせず止まり、ユーザー へ認証状態 (`kind: linear` なら Linear MCP、`kind: github` なら `gh auth status`) を確認させる
- 別のセッションが同じ issue で並走している兆候 (env stamp が別 cwd を指す) が見えた時。新規作成を控え、`Confusions` へ「並走しているように見える」と書いて止まる。ユーザー へ状況確認を依頼する
