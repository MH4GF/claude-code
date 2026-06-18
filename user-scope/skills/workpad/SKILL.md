---
name: workpad
description: Linear issue 上の `## Codex Workpad` ヘッダ付き コメント を 検索 / 作成 / 更新 する スキル。Symphony の バックグラウンドセッション の進捗を 1 つの コメント に集約し、ターン 上限到達 や CI 失敗 を跨いだ永続記憶として使う。バックグラウンドセッション 起動直後と作業節目ごとに発動する
---

# workpad

Symphony の バックグラウンドセッション が Linear issue へ集約する作業ノート用 コメント を管理する スキル。
issue ごとに `## Codex Workpad` コメント を 1 つだけ維持し、再 ディスパッチ 時に同じ コメント を読み直して作業を継続する。

## 前提

- 対象 Linear issue identifier (例 `MH-40`) が文脈から既知
- Linear MCP サーバー `linear-mh4gf` が利用可能

## スコープ 外

- 別 コメント への分割書き込み。1 issue 1 ワークパッド で固定し、節ごとに別 コメント を作らない
- resolved 状態の コメント へ加筆。resolved を見つけたら新規 コメント を作る (人間が意図的に閉じた印として扱う)
- 他人の コメント への上書き。`user.email` が自分と一致する コメント のみ 再利用 する

## 手順

### 1. issue ID を解決する

`mcp__linear-mh4gf__get_issue` を identifier で呼び、`id` (UUID) を取得する。

### 2. 既存 ワークパッド を探す

`mcp__linear-mh4gf__list_comments` を issue ID 指定で呼び、次の条件をすべて満たす コメント を探す。

- `body` が `## Codex Workpad` で始まる
- `resolvedAt` が `null`
- `user` が自身の Linear アカウント (`mcp__linear-mh4gf__get_user(self=true)` で確認)

複数該当した時は最新の 1 件を採用し、残りを後段で言及せず放置する (履歴として保つ)。

### 3a. 既存 ワークパッド を更新する

該当 コメント が見つかった場合、`mcp__linear-mh4gf__save_comment` を `id` 指定で呼び 本文 を上書きする。

更新内容は「直近の進捗」+「次に取る行動」を反映する。env stamp 行は再生成して上書きする (短い SHA や cwd が変わるため)。

### 3b. 新規 ワークパッド を作成する

該当 コメント が無い場合、`mcp__linear-mh4gf__save_comment` を issue 指定で呼び、下記テンプレに沿って 本文 を作る。

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

`<env-stamp>` を `host:abs-workdir@short-sha` 形式で書く。例: `mac-mini:/Users/mh4gf/.symphony/workspaces/claude-code/MH-40@7cf89d5`。

- ホスト名 を `hostname -s` から取得
- ワーキングディレクトリ 絶対パス を `pwd` から取得
- 短い SHA を `git rev-parse --short HEAD` から取得

### 4. 報告する

ユーザー へ 1 行で報告する。

- 作成 / 更新の別
- コメント URL (Linear MCP 戻り値の `url`)

## 各セクションの責務

| セクション | 用途 |
| --- | --- |
| Plan | 完了条件を分解した チェックリスト。完了したら `[x]` に変える |
| Acceptance Criteria | issue 本文の完了条件を転記。判定基準を 1 箇所にまとめる |
| Validation | 実行した検証コマンドと結果。CI 履歴では追えない ローカル 検証を残す |
| Notes | 設計判断、なぜその アプローチ を選んだか、参照した既存コード等 |
| Confusions | 詰まり、未解決の判断点、ユーザー 確認待ち事項。次 ターン の起点になる |

## エッジケース

- Rework 遷移時 (人間が `Rework` 状態へ動かした時) — 既存 ワークパッド を `delete_comment` で削除してから新規作成する。fresh ブランチ + fresh ワークパッド で再着手する規約
- API 失敗で list_comments が落ちた時 — リトライ せず止まり、ユーザー へ Linear MCP の 認証状態 を確認させる
- 別の バックグラウンドセッション が同じ issue で並走している兆候 (env stamp が別 cwd を指す) が見えた時 — 新規作成を控え、`Confusions` へ「並走しているように見える」と書いて止まる。オーケストレーター 側の ディスパッチ 状況確認を ユーザー へ依頼する
