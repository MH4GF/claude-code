---
name: workpad
description: Linear issue 上の `## Codex Workpad` ヘッダ付き コメント を 検索 / 作成 / 更新 する スキル。バックグラウンドセッション の進捗を 1 つの コメント に集約し、ターン 上限到達 や CI 失敗 を跨いだ永続記憶として使う。バックグラウンドセッション 起動直後と作業節目ごとに発動する
---

# workpad

バックグラウンドセッションが Linear issue へ集約する作業ノート用コメントを管理するスキル。
issue ごとに `## Codex Workpad` コメントを 1 つだけ維持する。再開時は同じコメントを読み直して作業を継続する。

## 前提

- 対象 Linear issue identifier (例 `MH-40`) が文脈から既知
- Linear MCP が利用可能

## スコープ外

- 別コメントへの分割書き込み。1 issue 1 ワークパッドで固定し、節ごとに別コメントを作らない
- resolved 状態のコメントへ加筆。resolved を見つけたら新規コメントを作る (人間が意図的に閉じた印として扱う)
- 他人のコメントへの上書き。`user.email` が自分と一致するコメントのみ再利用する

## 手順

### 1. issue ID を解決する

Linear MCP の issue 取得ツールを identifier で呼び、`id` (UUID) を取得する。

### 2. 既存ワークパッドを探す

Linear MCP のコメント一覧取得ツールを issue ID 指定で呼び、次の条件をすべて満たすコメントを探す。

- `body` が `## Codex Workpad` で始まる
- `resolvedAt` が `null`
- `user` が自身の Linear アカウント (Linear MCP の自身ユーザー取得ツールで確認)

複数該当した時は最新の 1 件を採用し、残りを後段で言及せず放置する (履歴として保つ)。

### 3a. 既存ワークパッドを更新する

該当コメントが見つかった場合、Linear MCP のコメント保存ツールを `id` 指定で呼び本文を上書きする。

更新内容は「直近の進捗」+「次に取る行動」を反映する。env stamp 行は再生成して上書きする (短い SHA や cwd が変わるため)。

### 3b. 新規ワークパッドを作成する

該当コメントが無い場合、Linear MCP のコメント保存ツールを issue 指定で呼び、下記テンプレに沿って本文を作る。

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

`<env-stamp>` を `host:abs-workdir@short-sha` 形式で書く。例: `mac-mini:/Users/mh4gf/ghq/github.com/MH4GF/claude-code@7cf89d5`。

- ホスト名を `hostname -s` から取得
- ワーキングディレクトリ絶対パスを `pwd` から取得
- 短い SHA を `git rev-parse --short HEAD` から取得

## 各セクションの責務

| セクション | 用途 |
| --- | --- |
| Plan | 完了条件を分解したチェックリスト。完了したら `[x]` に変える |
| Acceptance Criteria | issue 本文の完了条件を転記。判定基準を 1 箇所にまとめる |
| Validation | 実行した検証コマンドと結果。CI 履歴では追えないローカル検証を残す |
| Notes | 設計判断、なぜそのアプローチを選んだか、参照した既存コード等 |
| Confusions | 詰まり、未解決の判断点、ユーザー 確認待ち事項。次ターンの起点になる |

## エッジケース

- API 失敗でコメント一覧取得が落ちた時 — リトライせず止まり、ユーザー へ Linear MCP の認証状態を確認させる
- 別のセッションが同じ issue で並走している兆候 (env stamp が別 cwd を指す) が見えた時 — 新規作成を控え、`Confusions` へ「並走しているように見える」と書いて止まる。ユーザー へ状況確認を依頼する
