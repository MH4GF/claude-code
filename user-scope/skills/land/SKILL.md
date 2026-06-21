---
name: land
description: PR のコンフリクト監視・レビュー応答・CI 復旧・マージまでを一括で面倒見るスキル。「land して」「PR をマージ」「Merging を流して」等で発動する。マージ完了までユーザーへ制御を返さずウォッチャーループを回し続ける
---

# land

## 目的

- PR が main とコンフリクト無しでマージできる状態を保証する
- CI を green に保ち、失敗時は原因を直す
- 全チェックが green になり次第マージする
- マージ完了までユーザーへ制御を返さない。ブロックされない限りウォッチャーループを回し続ける
- マージ後のリモートブランチ削除は不要 (リポジトリ側で head ブランチ自動削除を有効にしている前提)

## 前提条件

- `gh` CLI が認証済み
- 対象 PR のブランチをチェックアウト済みでワーキングツリーが clean

## 手順

1. 現在のブランチに対応する PR を特定する
2. push 前に手元のゲート (lint / test / type check) を全て green にする
3. ワーキングツリーに未コミット変更があれば `commit` スキルでコミットし、`push` スキルで push してから次へ進む
4. main に対するマージ可否とコンフリクトを確認する
5. コンフリクトがあれば `pull` スキルで `origin/main` を fetch+merge してコンフリクトを解消し、`push` スキルで更新したブランチを publish する
6. Codex のレビューコメント (あれば) を確認し、必要な修正をマージ前に処理する
7. 全チェックが完了するまでウォッチする
8. チェックが失敗したらログを取って原因を直し、`commit` スキルでコミット、`push` スキルで push、再度チェックを回す
9. 全チェックが green かつレビューフィードバックが解消したらマージする (リポジトリ許可 merge method を判定する snippet はコマンド節)
10. コンテキスト確認 — レビューフィードバックを実装する前に、ユーザーの意図やタスク文脈と矛盾しないか確認する。矛盾していたらインラインで根拠を返し、ユーザーに確認してからコードを変える
11. 反対応答テンプレ — 反対する時はインラインで「受領 + 根拠 + 代案」の順に返す
12. 曖昧時ゲート — 曖昧で進めない時は確認フローを回す (PR を現在の GitHub ユーザーへアサインしメンションして返答を待つ)。曖昧さが解けるまで実装しない
    - レビュアーより自分が正しいと確信できる時はユーザー確認なしで進めてよい。その場合もインラインで根拠を返す
13. コメント単位モード — 各レビューコメントを受諾 / 確認 / 反対のいずれかへ分類する。インライン (Codex レビューは issue スレッド) で意図を述べてからコードを変える
14. 変更前に返信 — 必ず意図を返してからコードを push する。インラインレビューコメントはインライン、Codex レビューは issue スレッド

## コマンド

```bash
# ブランチと PR 文脈を取得
branch=$(git branch --show-current)
pr_number=$(gh pr view --json number -q .number)
pr_title=$(gh pr view --json title -q .title)
pr_body=$(gh pr view --json body -q .body)

# 許可 merge method を判定 (優先順位 squash → マージコミット → rebase)
read -r allow_squash allow_merge allow_rebase <<<"$(gh api repos/{owner}/{repo} \
  --jq '[.allow_squash_merge, .allow_merge_commit, .allow_rebase_merge] | @tsv')"
if   [ "$allow_squash" = "true" ]; then merge_flag="--squash"
elif [ "$allow_merge"  = "true" ]; then merge_flag="--merge"
elif [ "$allow_rebase" = "true" ]; then merge_flag="--rebase"
else echo "no merge method allowed in this repo" >&2; exit 1
fi

# マージ可否とコンフリクトを確認
mergeable=$(gh pr view --json mergeable -q .mergeable)

if [ "$mergeable" = "CONFLICTING" ]; then
  # `pull` スキルで fetch + merge + コンフリクト解消
  # その後 `push` スキルで更新したブランチを publish
  exit 1
fi

# 非同期ウォッチ補助 (後述) を優先する。下の手動ループは Python が動かない時のフォールバック
# レビューフィードバックの到来を待つ。Codex レビューは `## Codex Review — <persona>` で始まる issue コメント
# として届く。レビュアーフィードバックと同じ扱いで `[codex]` issue コメントで受領を返す
while true; do
  gh api repos/{owner}/{repo}/issues/"$pr_number"/comments \
    --jq '.[] | select(.body | startswith("## Codex Review")) | .id' | rg -q '.' \
    && break
  sleep 10
done

# チェックをウォッチする
if ! gh pr checks --watch; then
  gh pr checks
  # 失敗した run を特定してログを見る
  # gh run list --branch "$branch"
  # gh run view <run-id> --log
  exit 1
fi

# 判定した method でマージ (squash の時のみ subject/body を渡す)
if [ "$merge_flag" = "--squash" ]; then
  gh pr merge --squash --subject "$pr_title" --body "$pr_body"
else
  gh pr merge "$merge_flag"
fi
```

## 非同期ウォッチ補助

優先案 — asyncio ベースのウォッチャーでレビューコメント / CI / head 更新を並列に監視する。

```bash
python3 ~/.claude/skills/land/land_watch.py
```

exit code の意味

- `2` — レビューコメントを検知した (フィードバック対応へ)
- `3` — CI チェックが失敗した
- `4` — PR head が更新された (自動修正コミットを検知)
- `5` — マージコンフリクトを検知した (`pull` スキルで解消)

## 失敗対応

- チェックが失敗したら `gh pr checks` と `gh run view --log` で詳細を取り、修正して `commit` スキルでコミット、`push` スキルで push、再度ウォッチャーを回す
- 自分の判断でフレーキー失敗を見分ける。明らかにフレーキー (片方のプラットフォームだけタイムアウト等) の時は直さず先へ進んでよい
- CI が自動修正コミット (GitHub Actions 著者) を打った時、そのコミットでは新しい CI run がトリガーされない。PR head の更新を検知したらローカルへ pull し、必要なら `origin/main` を merge し、実著者のコミットを 1 つ足して force-push で CI を再走させ、チェックループを再起動する
- 全ジョブがマージコミット上で pnpm lockfile 破損エラーを出した時の修復は、最新の `origin/main` を fetch → merge → force-push → CI 再走
- マージ可否が `UNKNOWN` の時は待って再確認する
- レビューコメント (人間・Codex 問わず) が未対応のうちはマージしない
- Codex レビュージョブは失敗時にリトライされ、ブロッキングではない。「レビューフィードバックが来た」の判定はジョブステータスではなく、`## Codex Review — <persona>` 形式の issue コメントの存在で行う
- auto-merge は有効化しない。本リポジトリは required check が無く、auto-merge ではテストをスキップできてしまう
- 自分の過去の force-push やマージでリモート PR ブランチが先行している時、無駄なマージを避ける。フォーマッターをローカルで再実行し `git push --force-with-lease`

## レビュー対応

- Codex レビューは GitHub Actions が投稿する issue コメントとして届く。`## Codex Review — <persona>` で始まり、レビュアーの方針 + 使ったガードレールを含む。マージ前に必ず受領する
- 人間レビューコメントはブロッキング。新規レビュー要求やマージの前に必ず対応 (返信 + resolve) する
- 同じスレッドに複数のレビュアーが並ぶ時は各コメントへ返信してからスレッドを閉じる (バッチ可)
- レビューコメントは `gh api` で取得し、プレフィックス付きコメントで返信する
- レビューコメント用エンドポイントと issue コメント用エンドポイントを取り違えない。インラインフィードバックはレビューコメント側
  - PR レビューコメントを一覧取得する
    ```bash
    gh api repos/{owner}/{repo}/pulls/<pr_number>/comments
    ```
  - PR issue コメント (top-level discussion) を一覧取得する
    ```bash
    gh api repos/{owner}/{repo}/issues/<pr_number>/comments
    ```
  - 特定のレビューコメントへ返信する。body は draft file 経由で `jq --rawfile` + `--input -` で渡す
    ```bash
    # body を draft file へ書く (Write ツールまたは heredoc)
    body_path=.claude/tmp/review-reply-<comment_id>.md

    # JSON ペイロードを組み立てて gh api へ stdin で渡す
    jq -n \
      --rawfile body "$body_path" \
      --argjson reply_to <comment_id> \
      '{body: $body, in_reply_to: $reply_to}' \
    | gh api -X POST /repos/{owner}/{repo}/pulls/<pr_number>/comments --input -
    ```
- `gh api -f body='...'` / `gh api -F body=@file` は使わない。zsh が body 中の backtick (`` ` ``) や `$` をコマンド置換 / 変数展開として解釈し、囲まれた部分が黙って消える
- レビュー返信はコード断片や `$variable` を含むことが多い。`--rawfile` + `--input -` を必ず経由させる
- 同じ問題は `gh issue comment` や top-level `gh pr comment` にもある。これらは `--body-file <path>` を使う
- `in_reply_to` はレビューコメントの数値 ID (例 `2710521800`) を渡す。GraphQL の node ID (例 `PRRC_...`) は通らない。エンドポイントには PR 番号 (`/pulls/<pr_number>/comments`) を含める
- GraphQL のレビュー返信 mutation が forbidden になったら REST へ切り替える
- 返信で 404 が出たら、エンドポイントが間違っている (PR 番号抜け) かスコープ不足のいずれか。先に一覧を取って確認する
- 本エージェントが出す GitHub コメントは全て `[codex]` プレフィックスで始める
- Codex レビューの issue コメントへの返信は issue スレッド (レビュースレッドではなく) で行う。`[codex]` を付け、対応 / 先送りの別と根拠を書く
- フィードバックが変更を要する時
  - インラインレビューコメント (人間) へは、修正方針 (`[codex] ...`) を **元のレビューコメントへのインライン返信** として返す。レビューコメント用エンドポイントと `in_reply_to` を使う。issue コメントは使わない
  - 修正してコミットして push する
  - 修正詳細とコミット SHA (`[codex] ...`) を、受領した時と同じ場所 (Codex レビューは issue コメント、レビューコメントはインライン返信) に返す
  - land ウォッチャーは Codex レビューの issue コメントを「未解消」として扱う。後続で `[codex]` issue コメントが新しく付けば「受領済み」と判定する
- 新しい Codex レビューを要求するのは「再実行」が必要な時 (例新しいコミット後) に限る。前回レビュー以降に変更が無いのに要求しない
  - 新しい Codex レビューを要求する前に land ウォッチャーを再走し、未対応のレビューコメントが 0 件 (全て `[codex]` インライン返信済み) であることを確認する
  - 新しいコミットを push すると Codex レビューのワークフローが PR 同期で再走する (手動再実行も可能)。トップレベルのサマリーコメントを短く付けて、レビュアーに最新差分を見せる
    ```
    [codex] Changes since last review:
    - <short bullets of deltas>
    Commits: <sha>, <sha>
    Tests: <commands run>
    ```
  - 前回レビューからの新しいコミットが 1 つ以上あるときだけ再要求する
  - 次の Codex レビューコメントが来るまで待ってからマージする

## スコープと PR メタデータ

- PR のタイトルと本文は変更の最終形を反映する。直近 fix 分だけを書かない
- レビューフィードバックでスコープが広がった時、今この PR に含めるか別 issue へ送るかを決める。受諾 / 先送り / 拒否のいずれか
- 先送り / 拒否する時はトップレベルの `[codex]` 更新に短い理由 (`out-of-scope` / 意図と相反 / 不要等) を書く
- correctness 系のレビューコメントは対応する。先送り / 拒否したい時は先に検証し、なぜ該当しないかを述べる
- 各レビューコメントを `correctness` / `design` / `style` / `clarification` / `scope` に分類する
- correctness フィードバックには具体的な検証 (テスト / ログ / 根拠) を添えてから close する
- 受諾する時はトップレベル更新に 1 行で理由を残す
- 拒否する時は短い代案またはフォローアップのトリガーを示す
- 小刻みな更新を散らさない。修正を 1 バッチした後に "レビュー反映済み" のトップレベルコメントを 1 つだけ出す
- ドキュメント系フィードバックは挙動と一致しているかを確認する (レビュー受けでドキュメントだけ変える対応は避ける)

## Linear 連携

本スキルは GitHub 側の land 作業を扱う。Linear status との関係は次のとおり

- 起動条件 — Linear status が `Merging` であること (`mcp__linear-mh4gf__get_issue` の `state.name` で確認)
- マージ完了後 — GitHub webhook 経由で Linear gitAutomationStates の `merge` event が発火し `Done` へ自動遷移する。10 秒待っても遷移しない時のみ `mcp__linear-mh4gf__save_issue` で手動遷移する (state ID は `mcp__linear-mh4gf__list_issue_statuses` 経由)
- `Merging` 以外の状態の時は本スキルを起動しない。直接 `gh pr merge` を叩かない
