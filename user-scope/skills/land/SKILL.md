---
name: land
description: PR の コンフリクト 監視・レビュー 応答・CI 復旧・squash マージ までを一括で面倒見る スキル。「land して」「PR を マージ」「Merging を流して」等で発動する。マージ 完了まで ユーザー へ制御を返さず ウォッチャー ループ を回し続ける
---

# land

## 目的

- PR が main と コンフリクト 無しで マージ できる状態を保証する
- CI を green に保ち、失敗時は原因を直す
- 全 チェック が green になり次第 squash マージ する
- マージ 完了まで ユーザー へ制御を返さない。ブロック されない限り ウォッチャー ループ を回し続ける
- マージ 後の リモート ブランチ 削除は不要 (リポジトリ 側で head ブランチ 自動削除を有効にしている前提)

## 前提条件

- `gh` CLI が認証済み
- 対象 PR の ブランチ を チェックアウト 済みで ワーキングツリー が clean

## 手順

1. 現在の ブランチ に対応する PR を特定する
2. push 前に手元の ゲート (lint / test / type check) を全て green にする
3. ワーキングツリー に未 コミット 変更があれば `commit` スキル で コミット し、`push` スキル で push してから次へ進む
4. main に対する マージ可否 と コンフリクト を確認する
5. コンフリクト があれば `pull` スキル で `origin/main` を fetch+merge して コンフリクト を解消し、`push` スキル で更新した ブランチ を publish する
6. Codex の レビューコメント (あれば) を確認し、必要な修正を マージ 前に処理する
7. 全 チェック が完了するまで ウォッチ する
8. チェック が失敗したら ログ を取って原因を直し、`commit` スキル で コミット、`push` スキル で push、再度 チェック を回す
9. 全 チェック が green かつ レビュー フィードバック が解消したら squash マージ し、PR タイトル / 本文 をそのまま マージ コミット の subject / body へ流す
10. コンテキスト 確認 — レビュー フィードバック を実装する前に、ユーザー の意図やタスク文脈と矛盾しないか確認する。矛盾していたら インライン で根拠を返し、ユーザー に確認してからコードを変える
11. 反対応答 テンプレ — 反対する時は インライン で「受領 + 根拠 + 代案」の順に返す
12. 曖昧時 ゲート — 曖昧で進めない時は 確認 フロー を回す (PR を現在の GitHub ユーザー へ アサイン し メンション して返答を待つ)。曖昧さが解けるまで実装しない
    - レビュアー より自分が正しいと確信できる時は ユーザー 確認なしで進めてよい。その場合も インライン で根拠を返す
13. コメント 単位 モード — 各 レビュー コメント を 受諾 / 確認 / 反対 のいずれかへ分類する。インライン (Codex レビュー は issue スレッド) で意図を述べてからコードを変える
14. 変更前に返信 — 必ず意図を返してから コード を push する。インライン レビュー コメント は インライン、Codex レビュー は issue スレッド

## コマンド

```bash
# ブランチ と PR 文脈を取得
branch=$(git branch --show-current)
pr_number=$(gh pr view --json number -q .number)
pr_title=$(gh pr view --json title -q .title)
pr_body=$(gh pr view --json body -q .body)

# マージ可否 と コンフリクト を確認
mergeable=$(gh pr view --json mergeable -q .mergeable)

if [ "$mergeable" = "CONFLICTING" ]; then
  # `pull` スキル で fetch + merge + コンフリクト 解消
  # その後 `push` スキル で更新した ブランチ を publish
  exit 1
fi

# 非同期 ウォッチ補助 (後述) を優先する。下の手動 ループ は Python が動かない時の フォールバック
# レビュー フィードバック の到来を待つ。Codex レビュー は `## Codex Review — <persona>` で始まる issue コメント
# として届く。レビュアー フィードバック と同じ扱いで `[codex]` issue コメント で受領を返す
while true; do
  gh api repos/{owner}/{repo}/issues/"$pr_number"/comments \
    --jq '.[] | select(.body | startswith("## Codex Review")) | .id' | rg -q '.' \
    && break
  sleep 10
done

# チェック を ウォッチ する
if ! gh pr checks --watch; then
  gh pr checks
  # 失敗した run を特定して ログ を見る
  # gh run list --branch "$branch"
  # gh run view <run-id> --log
  exit 1
fi

# squash マージ (本 リポジトリ は head ブランチ 自動削除を有効化済み)
gh pr merge --squash --subject "$pr_title" --body "$pr_body"
```

## 非同期 ウォッチ補助

優先案 — asyncio ベース の ウォッチャー で レビュー コメント / CI / head 更新を並列に監視する。

```bash
python3 ~/.claude/skills/land/land_watch.py
```

exit code の意味

- `2` — レビュー コメント を検知した (フィードバック 対応へ)
- `3` — CI チェック が失敗した
- `4` — PR head が更新された (自動修正 コミット を検知)
- `5` — マージ コンフリクト を検知した (`pull` スキル で解消)

## 失敗対応

- チェック が失敗したら `gh pr checks` と `gh run view --log` で詳細を取り、修正して `commit` スキル で コミット、`push` スキル で push、再度 ウォッチャー を回す
- 自分の判断で フレーキー 失敗を見分ける。明らかに フレーキー (片方の プラットフォーム だけ タイムアウト 等) の時は直さず先へ進んでよい
- CI が 自動修正 コミット (GitHub Actions 著者) を打った時、その コミット では新しい CI run が トリガー されない。PR head の更新を検知したら ローカル へ pull し、必要なら `origin/main` を merge し、実 著者の コミット を 1 つ足して force-push で CI を再走させ、チェック ループ を再起動する
- 全 ジョブ が マージ コミット 上で pnpm lockfile 破損 エラーを出した時の修復は、最新の `origin/main` を fetch → merge → force-push → CI 再走
- マージ可否 が `UNKNOWN` の時は待って再確認する
- レビュー コメント (人間・Codex 問わず) が未対応のうちは マージ しない
- Codex レビュー ジョブ は失敗時に リトライ され、ブロッキング ではない。「レビュー フィードバック が来た」の判定は ジョブ ステータス ではなく、`## Codex Review — <persona>` 形式の issue コメント の存在で行う
- auto-merge は有効化しない。本 リポジトリ は required check が無く、auto-merge では テスト を スキップ できてしまう
- 自分の過去の force-push や マージ で リモート PR ブランチ が先行している時、無駄な マージ を避ける。フォーマッター を ローカル で再実行し `git push --force-with-lease`

## レビュー対応

- Codex レビュー は GitHub Actions が投稿する issue コメント として届く。`## Codex Review — <persona>` で始まり、レビュアー の方針 + 使った ガードレール を含む。マージ 前に必ず受領する
- 人間 レビュー コメント は ブロッキング。新規 レビュー 要求や マージ の前に必ず対応 (返信 + resolve) する
- 同じ スレッド に複数の レビュアー が並ぶ時は各 コメント へ返信してから スレッド を閉じる (バッチ 可)
- レビュー コメント は `gh api` で取得し、プレフィックス 付き コメント で返信する
- レビュー コメント 用 エンドポイント と issue コメント 用 エンドポイント を取り違えない。インライン フィードバック は レビュー コメント 側
  - PR レビュー コメント を 一覧 取得する
    ```bash
    gh api repos/{owner}/{repo}/pulls/<pr_number>/comments
    ```
  - PR issue コメント (top-level discussion) を 一覧 取得する
    ```bash
    gh api repos/{owner}/{repo}/issues/<pr_number>/comments
    ```
  - 特定の レビュー コメント へ返信する
    ```bash
    gh api -X POST /repos/{owner}/{repo}/pulls/<pr_number>/comments \
      -f body='[codex] <response>' -F in_reply_to=<comment_id>
    ```
- `in_reply_to` は レビュー コメント の数値 ID (例 `2710521800`) を渡す。GraphQL の node ID (例 `PRRC_...`) は通らない。エンドポイント には PR 番号 (`/pulls/<pr_number>/comments`) を含める
- GraphQL の レビュー 返信 mutation が forbidden になったら REST へ切り替える
- 返信で 404 が出たら、エンドポイント が間違っている (PR 番号抜け) か スコープ 不足のいずれか。先に一覧を取って確認する
- 本 エージェント が出す GitHub コメント は全て `[codex]` プレフィックス で始める
- Codex レビュー の issue コメント への返信は issue スレッド (レビュー スレッド ではなく) で行う。`[codex]` を付け、対応 / 先送り の別と根拠を書く
- フィードバック が変更を要する時
  - インライン レビュー コメント (人間) へは、修正方針 (`[codex] ...`) を **元の レビュー コメント への インライン 返信** として返す。レビュー コメント 用 エンドポイント と `in_reply_to` を使う。issue コメント は使わない
  - 修正して コミット して push する
  - 修正詳細と コミット SHA (`[codex] ...`) を、受領した時と同じ場所 (Codex レビュー は issue コメント、レビュー コメント は インライン 返信) に返す
  - land ウォッチャー は Codex レビュー の issue コメント を「未解消」として扱う。後続で `[codex]` issue コメント が新しく付けば「受領済み」と判定する
- 新しい Codex レビュー を要求するのは「再実行」が必要な時 (例 新しい コミット 後) に限る。前回 レビュー 以降に変更が無いのに要求しない
  - 新しい Codex レビュー を要求する前に land ウォッチャー を再走し、未対応の レビュー コメント が 0 件 (全て `[codex]` インライン 返信済み) であることを確認する
  - 新しい コミット を push すると Codex レビュー の ワークフロー が PR 同期 で再走する (手動再実行も可能)。トップレベル の サマリー コメント を短く付けて、レビュアー に最新差分を見せる
    ```
    [codex] Changes since last review:
    - <short bullets of deltas>
    Commits: <sha>, <sha>
    Tests: <commands run>
    ```
  - 前回 レビュー からの新しい コミット が 1 つ以上あるときだけ再要求する
  - 次の Codex レビュー コメント が来るまで待ってから マージ する

## スコープ と PR メタデータ

- PR の タイトル と 本文 は変更の最終形を反映する。直近 fix 分だけを書かない
- レビュー フィードバック で スコープ が広がった時、今この PR に含めるか別 issue へ送るかを決める。受諾 / 先送り / 拒否 のいずれか
- 先送り / 拒否 する時は トップレベル の `[codex]` 更新 に短い理由 (`out-of-scope` / 意図と相反 / 不要 等) を書く
- correctness 系の レビュー コメント は対応する。先送り / 拒否 したい時は先に検証し、なぜ該当しないかを述べる
- 各 レビュー コメント を `correctness` / `design` / `style` / `clarification` / `scope` に分類する
- correctness フィードバック には具体的な検証 (テスト / ログ / 根拠) を添えてから close する
- 受諾 する時は トップレベル 更新に 1 行で理由を残す
- 拒否 する時は短い代案または フォローアップ の トリガー を示す
- 小刻みな更新を散らさない。修正を 1 バッチ した後に "レビュー 反映済み" の トップレベル コメント を 1 つだけ出す
- ドキュメント 系 フィードバック は挙動と一致しているかを確認する (レビュー 受けで ドキュメント だけ変える対応は避ける)

## Linear 連携

本 スキル は GitHub 側の land 作業を扱う。Linear status との関係は次のとおり

- 起動条件 — Linear status が `Merging` であること (`mcp__linear-mh4gf__get_issue` の `state.name` で確認)
- マージ 完了後 — GitHub webhook 経由で Linear gitAutomationStates の `merge` event が発火し `Done` へ自動遷移する。10 秒待っても遷移しない時のみ `mcp__linear-mh4gf__save_issue` で手動遷移する (state ID は `mcp__linear-mh4gf__list_issue_statuses` 経由)
- `Merging` 以外の状態の時は本 スキル を起動しない。直接 `gh pr merge` を叩かない
