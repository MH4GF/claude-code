---
name: land
description: Linear status が `Merging` の PR を安全に squash merge する skill。CI / mergeable / Draft / Linear status を事前検証し、`gh pr merge --squash --delete-branch` を実行する。「land して」「PR を merge」「Merging を流して」等で発動する。Symphony bg session が `Merging` 遷移後に呼ぶ前提
---

# land

Linear status `Merging` の PR を squash merge へ運ぶ skill。事前検証で安全性を担保し、`gh pr merge` を一度だけ実行する。

## 前提

呼び出し時点で次を満たしておく。

- 作業ワーキングディレクトリが対象 PR の branch を check out 済み (Symphony bg session の通例)
- `gh` CLI が認証済み
- Linear issue が `Merging` 状態へ遷移済み (人間操作で動かす想定。PR open や `## Codex Review` 自動 approve では到達しない)
- 対応する Linear issue identifier (例 `MH-40`) が文脈から既知

## スコープ外

- `gh pr merge` の直接呼び出し。本 skill の手順を介さず merge コマンドを叩かない
- `Merging` 以外の状態からの強行 merge。状態不一致は止まる
- branch protection / required check の回避。green でない時に強行しない

## 手順

### 1. PR 番号を解決する

`mcp__linear-mh4gf__get_issue` で Linear issue を取得し、`attachments` から対象 repo の PR URL を 1 件選ぶ。URL 末尾の数字が PR 番号。

複数 PR が attach されている時は、現在 check out 中の branch (`git branch --show-current`) と一致するものを選ぶ。一致するものがなければ止まり、ユーザー へ報告する。

### 2. 状態を取得する

```bash
pr_number=$(gh pr view --json number -q .number)
gh pr view "$pr_number" --json mergeable,statusCheckRollup,reviews,isDraft,headRefName
```

### 3. 前提を検証する

次の全てを満たす時のみ次へ進む。1 つでも欠ければ止まる。報告は具体的な失敗箇所を述べる。

- `isDraft` が `false`
- `mergeable` が `MERGEABLE` (`UNKNOWN` の時は 10 秒待って再取得を 1 回だけ試す。それでも `UNKNOWN` なら止まる)
- `statusCheckRollup` の全 check が `SUCCESS` (`PENDING` / `IN_PROGRESS` は green 待ち、`FAILURE` は止まる)
- Linear issue status が `Merging` (`mcp__linear-mh4gf__get_issue` の `state.name` で確認)

### 4. squash merge を実行する

```bash
gh pr merge "$pr_number" --squash --delete-branch
```

`--auto` は使わない。本 repo は branch protection なしで即時 merge できる。`--subject` / `--body` は省略し、PR title / body から自動生成させる (個人 repo の慣行)。

### 5. Linear status の遷移を確認する

merge 直後は GitHub webhook → Linear gitAutomationStates の `merge` event 経由で `Done` へ自動遷移する。10 秒待ってから `mcp__linear-mh4gf__get_issue` で status を確認する。

`Done` になっていれば完了を報告する。

未遷移の時は `mcp__linear-mh4gf__save_issue` を呼び `Done` へ手動で動かす。state ID を `mcp__linear-mh4gf__list_issue_statuses` から取得する。

### 6. 報告する

ユーザー へ 1〜2 行で報告する。

- merge した PR 番号と URL
- Linear status が `Done` へ動いたか (自動 / 手動の別)

## エッジケース

- `mergeable` が `CONFLICTING` の時は止まり、conflict resolution は本 skill の責務外と報告する (Symphony bg session 側で `pull` skill から再着手する想定)
- CI が `FAILURE` の時は止まり、失敗 check 名を報告する。本 skill 内では fix へ進まない
- Linear status が `Merging` 以外 (例 `In Progress`、`Human Review`) の時は止まる。人間ゲートを跨いだ merge は本 skill 経由では実行しない
- `gh pr merge` 自体が失敗した時はリトライしない。エラー出力をそのまま報告する
