---
name: land
description: PR の conflict 監視・review 応答・CI 復旧・squash merge までを一括で面倒見る skill。「land して」「PR を merge」「Merging を流して」等で発動する。merge 完了までユーザー へ制御を返さず watcher ループを回し続ける
---

# land

## Goals

- PR が main と conflict free であることを保証する
- CI を green に保ち、失敗時は原因を直す
- 全 check が green になり次第 squash merge する
- merge 完了までユーザー へ制御を返さない。block されない限り watcher ループを回し続ける
- merge 後の remote branch 削除は不要 (repo 側で head branch 自動削除を有効にしている前提)

## Preconditions

- `gh` CLI が認証済み
- 対象 PR の branch を check out 済みでワーキングツリーが clean

## Steps

1. 現在の branch に対応する PR を特定する
2. push の前に手元の gauntlet (lint / test / type check) を全て green にする
3. ワーキングツリーに未 コミット 変更があれば `commit` skill で コミット し、`push` skill で push してから次へ進む
4. main に対する mergeability と conflict を確認する
5. conflict があれば `pull` skill で `origin/main` を fetch+merge して conflict を解消し、`push` skill で更新した branch を publish する
6. Codex review comment (あれば) を確認し、必要な修正を merge 前に処理する
7. 全 check が完了するまで watch する
8. check が失敗したら log を取って原因を直し、`commit` skill で コミット、`push` skill で push、再度 check を回す
9. 全 check が green かつ review feedback が解消したら squash merge し、PR title / body をそのまま merge subject / body へ流す
10. Context guard — review feedback を実装する前に、ユーザー の意図やタスク文脈と矛盾しないか確認する。矛盾していたら inline で根拠を返し、ユーザー に確認してからコードを変える
11. Pushback テンプレ — 反対する時は inline で「acknowledge + 根拠 + 代案」の順に返す
12. Ambiguity gate — 曖昧で進めない時は clarification flow を回す (PR を現在の GH user へ assign し mention して返答を待つ)。曖昧さが解けるまで実装しない
    - レビュアー より自分が正しいと確信できる時は ユーザー 確認なしで進めてよい。その場合も inline で根拠を返す
13. Per-comment モード — 各 review comment を accept / clarify / push back のいずれかへ分類する。inline (Codex review は issue thread) で意図を述べてからコードを変える
14. Reply before change — 必ず意図を返してから code を push する。inline review comment は inline、Codex review は issue thread

## Commands

```bash
# branch と PR 文脈を取得
branch=$(git branch --show-current)
pr_number=$(gh pr view --json number -q .number)
pr_title=$(gh pr view --json title -q .title)
pr_body=$(gh pr view --json body -q .body)

# mergeability と conflict を確認
mergeable=$(gh pr view --json mergeable -q .mergeable)

if [ "$mergeable" = "CONFLICTING" ]; then
  # `pull` skill で fetch + merge + conflict 解消
  # その後 `push` skill で更新した branch を publish
  exit 1
fi

# Async Watch Helper (後述) を優先する。下の手動ループは Python が動かない時の fallback
# review feedback の到来を待つ。Codex review は `## Codex Review — <persona>` で始まる issue comment
# として届く。reviewer feedback と同じ扱いで `[codex]` issue comment で受領を返す
while true; do
  gh api repos/{owner}/{repo}/issues/"$pr_number"/comments \
    --jq '.[] | select(.body | startswith("## Codex Review")) | .id' | rg -q '.' \
    && break
  sleep 10
done

# checks を watch
if ! gh pr checks --watch; then
  gh pr checks
  # 失敗した run を特定して log を見る
  # gh run list --branch "$branch"
  # gh run view <run-id> --log
  exit 1
fi

# squash merge (本 repo は head branch 自動削除を有効化済み)
gh pr merge --squash --subject "$pr_title" --body "$pr_body"
```

## Async Watch Helper

優先案 — asyncio watcher で review comment / CI / head 更新を並列で監視する。

```bash
python3 ~/.claude/skills/land/land_watch.py
```

exit code の意味

- `2` — review comment を検知した (feedback 対応へ)
- `3` — CI checks が失敗した
- `4` — PR head が更新された (autofix コミット を検知)
- `5` — merge conflict を検知した (`pull` skill で解消)

## Failure Handling

- check が失敗したら `gh pr checks` と `gh run view --log` で詳細を取り、修正して `commit` skill で コミット、`push` skill で push、再度 watcher を回す
- 自分の判断で flaky failure を見分ける。明らかに flake (片方の platform だけタイムアウト等) の時は直さず先へ進んでよい
- CI が auto-fix コミット (GitHub Actions 著者) を打った時、その コミット では新しい CI run がトリガー されない。PR head の更新を検知したら local へ pull し、必要なら `origin/main` を merge し、実 著者の コミット を 1 つ足して force-push で CI を再走させ、checks loop を再起動する
- 全 job が merge コミット 上で pnpm lockfile corrupted エラーを出した時の修復は、最新の `origin/main` を fetch → merge → force-push → CI 再走
- mergeability が `UNKNOWN` の時は待って再確認する
- review comment (人間・Codex 問わず) が未対応のうちは merge しない
- Codex review job は失敗時に リトライ され、blocking ではない。「review feedback が来た」の判定は job status ではなく、`## Codex Review — <persona>` issue comment の存在で行う
- auto-merge は有効化しない。本 repo は required check が無く、auto-merge では test を スキップ できてしまう
- 自分の過去の force-push や merge で remote PR branch が先行している時、無駄な merge を避ける。formatter を local で再実行し `git push --force-with-lease`

## Review Handling

- Codex review は GitHub Actions が投稿する issue comment として届く。`## Codex Review — <persona>` で始まり、レビュアー の methodology + 使った guardrails を含む。merge 前に必ず受領する
- 人間 review comment は blocking。新規 review 要求や merge の前に必ず対応 (返信 + resolve) する
- 同じ thread に複数の レビュアー が並ぶ時は各 comment へ返信してから thread を閉じる (batch 可)
- review comment は `gh api` で取得し、prefix 付き comment で返信する
- review comment endpoint と issue comment endpoint を取り違えない。inline feedback は review comment 側
  - PR review comment を list する
    ```bash
    gh api repos/{owner}/{repo}/pulls/<pr_number>/comments
    ```
  - PR issue comment (top-level discussion) を list する
    ```bash
    gh api repos/{owner}/{repo}/issues/<pr_number>/comments
    ```
  - 特定の review comment へ返信する
    ```bash
    gh api -X POST /repos/{owner}/{repo}/pulls/<pr_number>/comments \
      -f body='[codex] <response>' -F in_reply_to=<comment_id>
    ```
- `in_reply_to` は review comment の数値 ID (例 `2710521800`) を渡す。GraphQL node ID (例 `PRRC_...`) は通らない。endpoint には PR 番号 (`/pulls/<pr_number>/comments`) を含める
- GraphQL の review reply mutation が forbidden になったら REST へ切り替える
- 返信で 404 が出たら、endpoint が間違っている (PR 番号抜け) か スコープ 不足のいずれか。先に list を取って確認する
- 本 エージェント が出す GitHub comment は全て `[codex]` prefix で始める
- Codex review issue comment への返信は issue thread (review thread ではなく) で行う。`[codex]` を付け、対応 / 先送り の別と根拠を書く
- feedback が変更を要する時
  - inline review comment (人間) へは、修正方針 (`[codex] ...`) を **元の review comment への inline reply** として返す。review comment endpoint と `in_reply_to` を使う。issue comment は使わない
  - 修正して コミット して push する
  - 修正詳細と コミット SHA (`[codex] ...`) を、受領した時と同じ場所 (Codex review は issue comment、review comment は inline reply) に返す
  - land watcher は Codex review issue comment を「未解消」として扱う。後続で `[codex]` issue comment が新しく付けば「acknowledged」と判定する
- 新しい Codex review を要求するのは「再実行」が必要な時 (例 新しい コミット 後) に限る。前回 review 以降に変更が無いのに要求しない
  - 新しい Codex review を要求する前に land watcher を再走し、未対応の review comment が 0 件 (全て `[codex]` inline reply 済み) であることを確認する
  - 新しい コミット を push すると Codex review workflow が PR synchronization で再走する (手動 rerun も可能)。root-level の summary comment を短く付けて、レビュアー に最新差分を見せる
    ```
    [codex] Changes since last review:
    - <short bullets of deltas>
    Commits: <sha>, <sha>
    Tests: <commands run>
    ```
  - 前回 review からの新しい コミット が 1 つ以上あるときだけ再要求する
  - 次の Codex review comment が来るまで待ってから merge する

## スコープ と PR Metadata

- PR の title と description は変更の最終形を反映する。直近 fix 分だけを書かない
- review feedback で スコープ が広がった時、今この PR に含めるか別 issue へ送るかを決める。accept / defer / decline のいずれか
- defer / decline する時は root-level の `[codex]` update に短い理由 (`out-of-scope` / 意図と相反 / 不要 等) を書く
- correctness 系の review comment は対応する。defer / decline したい時は先に validate し、なぜ該当しないかを述べる
- 各 review comment を `correctness` / `design` / `style` / `clarification` / `scope` に分類する
- correctness feedback には具体的な validation (test / log / 根拠) を添えてから close する
- accept する時は root-level update に 1 行で理由を残す
- decline する時は短い代案または follow-up の トリガー を示す
- 小刻みな update を散らさない。修正を 1 バッチした後に "review addressed" の root-level comment を 1 つだけ出す
- doc 系 feedback は behavior と一致しているかを確認する (review 受けで doc だけ変える対応は避ける)

## Linear 連携

本 skill は GitHub 側の land 作業を扱う。Linear status との関係は次のとおり。

- 起動条件 — Linear status が `Merging` であること (`mcp__linear-mh4gf__get_issue` の `state.name` で確認)
- merge 完了後 — GitHub webhook 経由で Linear gitAutomationStates の `merge` event が発火し `Done` へ自動遷移する。10 秒待っても遷移しない時のみ `mcp__linear-mh4gf__save_issue` で手動遷移する (state ID は `mcp__linear-mh4gf__list_issue_statuses` 経由)
- `Merging` 以外の状態の時は本 skill を起動しない。直接 `gh pr merge` を叩かない
