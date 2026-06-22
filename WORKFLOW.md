---
tracker:
  kind: linear
  project_slug: "ai-native-workspace-202646c35423"
  api_key: $LINEAR_API_KEY
  active_states: ["Todo", "In Progress", "Merging", "Rework"]
  terminal_states: ["Human Review", "Done", "Canceled", "Duplicate"]
  required_labels: ["claude-code"]

workspace:
  root: /Users/hermes/.symphony/workspaces/claude-code

hooks:
  after_create: |
    set -eu
    git clone --depth 1 git@github.com:MH4GF/claude-code.git .

agent:
  max_concurrent_agents: 2
  max_turns: 20

codex:
  command: /Users/hermes/.local/bin/safe-claude
  claude_args: ["--permission-mode", "bypassPermissions"]
  stall_timeout_ms: 600000
  turn_timeout_ms: 1800000
---

MH4GF/claude-code (public な Claude Code 設定・plugin marketplace) の clone で作業する。repo 構造は root の `README.md` を起点に把握する。

## Issue

{{ issue.identifier }} - {{ issue.title }}

## Body

{{ issue.description }}

{% if attempt %}
## Continuation context

- これはリトライ attempt #{{ attempt }}。チケットが active state のため再ディスパッチされた。
- 最初からやり直さず、現在の workspace 状態から resume する。
- 完了済みの調査や validation を繰り返さない。新規コード変更で必要な場合は除く。
- issue が active state の間は turn を終わらせない。required permissions/secrets が missing で blocked の場合は除く。
{% endif %}

## Prerequisite

Linear MCP サーバー `linear-mh4gf` が利用可能である前提。設定されていなければ即座に止まり、blocker を明示する。

## Default posture

- 本セッションは unattended orchestration。人間に follow-up action を求めない
- session 起動直後に `workpad` skill を呼ぶ。`## Codex Workpad` comment を find/create し、新しい実装に入る前に最新化する
- まず Linear status を確認し、下の Status map に従って route する
- 実装より先に planning と verification 設計に十分な時間を割く
- 修正対象を明示するため、変更前に現状の挙動や issue の signal を再現させる
- チケットの metadata (state、checklist、acceptance criteria、links) を最新に保つ
- 進捗の唯一の source of truth は `## Codex Workpad` comment 1 つ。"done"/summary の別 comment は出さない
- チケットに `Validation` / `Test Plan` / `Testing` の節があれば必須受け入れ条件として workpad に転記し、完了前に実行する
- スコープ外の改善を実行中に発見したら、`mcp__linear-mh4gf__save_issue` で別 issue を起票する。本 issue のスコープは広げない
  - 別 issue は title / description / acceptance criteria を明記する
  - `Backlog` に置き、同一 project に紐付け、本 issue を `related` でリンクする
  - 依存があれば `blockedBy` を貼る
  - 例外: main 由来の既存違反が PR CI を block した場合、別 issue 化せず本 PR 内で inline 一括 fix する。本 issue の original 受け入れ条件は別途満たす
    - PR description に「スコープ外一括 fix の理由」を 1 段落書く。テンプレート: `本 PR は main 由来の既存違反が PR CI を block したため、本 issue 本来のスコープ外の一括 fix を含む。original の受け入れ条件は別途満たしている。`
- Linear status は対応する品質バーを満たした時だけ動かす
- missing requirements / secrets / permissions による blocker でなければ end-to-end で自律稼働する
- 阻害時の escape hatch は真の外部 blocker かつ fallback を尽くした時のみ使う
- 最終メッセージは完了した action と blocker のみ書く。"next steps for user" は書かない

## Related skills

- `workpad` — 単一の `## Codex Workpad` Linear comment を find/create し、plan / acceptance / validation / notes を 1 箇所に集約する
- `commit` — 実装中に意味のあるコミットを作る
- `push` — branch を remote と同期し、変更を publish する
- `pull` — `origin/main` の最新を branch へ取り込む
- `land` — Linear status が `Merging` になったら、`land` skill を loop で呼んで PR が merge されるまで進める。`gh pr merge` を直接叩かない

## Status map

- `Backlog` — 本 workflow のスコープ外。何も変更しない
- `Todo` — queued。active な作業に入る前に必ず `In Progress` へ動かす
  - 例外: 既存 PR が attach されていれば feedback / rework loop として扱う。PR feedback sweep を完走し、対応または明示的な pushback を返してから revalidate し、`Human Review` へ戻す
- `In Progress` — 実装稼働中
- `Human Review` — PR が attach 済みで validation 完了、人間の Approve 待ち。本 workflow の `terminal_states` に含まれる
- `Merging` — 人間が Approve 済み。`land` skill フローを実行する
- `Rework` — レビュアーが approach 全リセットを要求。planning と実装を再度ゼロから行う
- `Done` — terminal。何もしない

## Step 0: 現在のチケット状態を判定して route する

1. `mcp__linear-mh4gf__get_issue` を identifier で呼んで issue を取得する
2. 現在の Linear status を読む
3. 対応フローへ route する
   - `Backlog` — issue を変更しない。`Todo` へ人間が動かすのを待って止まる
   - `Todo` — 即 `mcp__linear-mh4gf__save_issue` で `In Progress` へ動かす。続けて `workpad` skill で bootstrap comment を find/create し、Step 1 へ進む
     - kick-off 時点で PR が既に attach されていれば、まず PR の open comment を全件読み、必須の変更点と明示 pushback の方針を立てる
   - `In Progress` — 現行 workpad comment を起点に execution flow を続ける
   - `Human Review` — terminal。何もせず shutdown する
   - `Merging` — `land` skill を起動し、PR が merge されるまで loop する。`gh pr merge` を直接叩かない
   - `Rework` — Step 4 へ進む
   - `Done` — 何もせず shutdown する
4. 現 branch の PR の状態を確認する
   - 既存 branch PR が `CLOSED` または `MERGED` なら、前回の branch 作業は再利用しない
   - `origin/main` から fresh branch を切って、新規 attempt として execution flow を再起動する
5. `Todo` チケットは次の順で startup する
   - `mcp__linear-mh4gf__save_issue(state: "In Progress")`
   - `workpad` skill で `## Codex Workpad` bootstrap comment を find/create する
   - その後で analysis / planning / 実装を始める
6. status と issue 内容が不整合なら、workpad に短い note を追記して、安全側のフローで進める

## Step 1: Start/continue execution (Todo または In Progress)

1. `workpad` skill で単一の永続 workpad comment を find/create する
   - 既存 comment から `## Codex Workpad` header を検索する
   - resolved comment は無視。active かつ unresolved のものだけ reuse 対象
   - 見つかればそれを reuse する。新規 workpad comment は作らない
   - 無ければ 1 つ作成し、以後の progress 更新は全てそこへ書く
   - workpad comment ID を保持し、progress 更新は必ず同じ ID へ向ける
2. `Todo` 起点で来た場合、追加の status 遷移で時間を使わない。本 Step 開始時には既に `In Progress` であるはず
3. 新規編集の前に workpad を reconcile する
   - 既に完了済みの項目を check off する
   - plan を現スコープに対して網羅的になるまで拡張・修正する
   - `Acceptance Criteria` と `Validation` がタスクと整合しているか確認する
4. 階層 plan を workpad comment へ書く・更新する
5. workpad 先頭に環境スタンプを 1 行の code fence で置く
   - 形式: `<host>:<abs-workdir>@<short-sha>`
   - 例: `mh4gfs-MacBook-Air:/Users/mh4gf/.symphony/workspaces/claude-code/MH-XX@7cf89d5`
   - Linear issue field から derive できる情報 (issue ID、status、branch、PR link) は重複させない
6. acceptance criteria と TODO を同じ comment 内に checklist として書く
   - 変更が user-facing なら、end-to-end の user 経路を辿る UI walkthrough acceptance criterion を含める
   - チケットに `Validation` / `Test Plan` / `Testing` の節があれば、workpad の `Acceptance Criteria` と `Validation` へ必須 checkbox として転記する。optional への格下げは禁止
7. plan を self-review し、comment 内で refine する
8. 実装前に reproduction signal を取り、workpad `Notes` に記録する。コマンドと出力か、deterministic な挙動の説明
9. `pull` skill を呼んで `origin/main` の最新と同期し、結果を workpad `Notes` に書く。merge 源 / `clean` か `conflicts resolved` か / 結果 HEAD short SHA を含める
10. execution へ進む

## Step 2: Execution phase (Todo → In Progress → Human Review)

1. 現在の repo state (`branch`, `git status`, `HEAD`) を確認し、kickoff の `pull` 同期結果が workpad に書かれているかを再確認する。書かれていなければ書く
2. Linear status が `Todo` なら `In Progress` へ動かす。それ以外はそのまま
3. 既存 workpad comment を active execution checklist として扱う。スコープ / リスク / validation 方針 / 新発見タスクなど、現実が変わったら liberal に書き換える
4. 階層 TODO に沿って実装し、comment を最新に保つ
   - 完了項目を check off する
   - 新規発見項目を該当節へ追記する
   - parent/child 構造を保つ
   - 各 milestone (reproduction 完了 / コード変更 land / validation 実行 / review feedback 対応) 完了時に即 workpad を更新する
   - 完了した作業を unchecked のまま放置しない
   - `Todo` 起点で既に PR が attach されていたチケットは、新規 feature 作業の前に PR feedback sweep protocol を完走する
5. スコープに必要な validation / test を実行する
   - 必須ゲート: チケット由来の `Validation` / `Test Plan` / `Testing` を実行する。未達は未完了とみなす
   - 変更挙動を直接示す targeted proof を優先する
   - 仮の local proof 編集 (hardcoded test input / mock UI account) は信頼度を上げる目的なら許可する
   - 仮 proof 編集はコミット / push 前に必ず revert し、内容と結果を workpad の `Validation` / `Notes` に残す
6. acceptance criteria を再点検し、欠落があれば塞ぐ
7. `git push` の前に必ずスコープの validation を走らせ、green を確認する。fail なら原因を直してから再実行し、green を確認してから `commit` と `push`
8. PR URL を issue に紐付ける。Linear attachment を優先し、無ければ workpad comment にリンクを残す
9. `pull` skill で `origin/main` の最新を branch へ merge し、conflict を解消し、check を再実行する
10. workpad comment を最終状態へ更新する
    - plan / acceptance / validation の checklist 完了項目を全て check 済みにする
    - 最終ハンドオフノート (コミット + validation 結果) を同じ workpad に書く
    - PR URL は issue 側 (attachment / link) に置き、workpad 本文には重複させない
    - 実行中に不明瞭な点があれば末尾に `### Confusions` 節を簡潔に追加する
    - 完了 summary の追加 comment は出さない
11. `Human Review` へ動かす前に CI と feedback の close-out loop を回す
    - `gh pr checks` を poll し、全て green になるまで待つ。CI fail は本 turn 内で fix する。Stop hook は使わず、本 WORKFLOW prompt がその loop を担う
    - PR feedback sweep protocol を完走し、actionable comment を残さない
    - チケット由来の validation / test-plan 項目が全て workpad で check 済みであることを確認する
    - 状態遷移前に workpad を reopen し、`Plan` / `Acceptance Criteria` / `Validation` が完了した作業と過不足なく一致するよう refresh する
    - `gh pr view --json isDraft` で Draft 状態を確認し、Draft なら `gh pr ready` で Ready 化する。これで GitHub 側 `ready_for_review` event が発火し Slack の review 通知が飛ぶ。例外: 阻害時の escape hatch に該当する真の外部 blocker の場合のみ Draft 維持可
12. 上記を満たしたら `mcp__linear-mh4gf__save_issue` で `Human Review` へ動かす
    - 例外: GitHub 以外の必須ツール / 認証が missing で阻害時の escape hatch に該当する場合のみ動かす
    - その時は blocker brief と unblock action を workpad に書いた上で `Human Review` へ動かす
13. `Todo` 起点で既に PR が attach されていたチケットは次を満たす
    - 既存 PR feedback (inline review comment 含む) を全件レビューし、コード変更または明示 pushback で解決済み
    - 必要な更新を branch に push 済み
    - その上で `Human Review` へ動かす

## Step 3: Human Review と merge

1. `Human Review` は本 workflow の terminal。bg session は exit し、Symphony は人間 action まで再ディスパッチを止める
2. 人間が PR をレビューする。incremental 変更が必要なら、PR を Draft に戻す (`gh pr ready --undo`) か、`gitAutomationStates.draft` event 経由で `In Progress` へ動かす。Symphony が再ディスパッチし、bg session が既存 workpad から resume する
3. approach 全リセットが必要なら、人間が `Rework` へ動かす。Symphony が再ディスパッチし、bg session が Step 4 を実行する
4. Approve され、人間が `Merging` へ動かしたら、Symphony が再ディスパッチし、bg session が `land` skill を起動する
5. `Merging` 状態では `land` skill を loop で呼んで PR が merge されるまで進める
   - `land` skill は CI green / `mergeable` / Approve / Linear status `Merging` を pre-validation する
   - 通れば `gh pr merge --squash --delete-branch` を実行する
   - `gitAutomationStates.merge` event 経由で Linear status は `Done` へ動く
   - `gh pr merge` を直接叩かない

## Step 4: Rework handling

1. `Rework` は approach 全リセット。incremental 修正は通常の `In Progress` → `Human Review` loop で扱う。`Rework` は明示的な "やり直し" 信号
2. issue 本文と全 human comment を読み直し、今回の attempt で何を変えるかを明示する。新 workpad の `Notes` に diff を書く
3. 既存 PR を `gh pr close` で閉じる
4. 既存 `## Codex Workpad` comment を `mcp__linear-mh4gf__delete_comment` で削除する。fresh branch + fresh workpad の規約
5. `origin/main` から fresh branch を切る
6. 通常の kick-off フローへ戻る
   - Linear status が `Todo` なら `In Progress` へ動かす。それ以外はそのまま
   - 新規 bootstrap `## Codex Workpad` comment を作る
   - 新規 plan / checklist を立て、end-to-end で実行する

## PR feedback sweep protocol (required)

PR が attach されたチケットは、本 protocol を完走させてから `Human Review` へ動かす。

1. issue の link / attachment から PR 番号を取得する
2. 全 channel から feedback を集める
   - 最上位の PR comment — `gh pr view --comments`
   - inline review comment — `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
   - review summary / state — `gh pr view --json reviews`
3. actionable なレビュアー comment (人間 / bot 問わず) は inline review comment 含めて全て blocking と扱う。次のいずれかが満たされるまで close しない
   - コード / test / docs を更新して対応した
   - 明示的かつ理由付きの pushback を thread に返信した
4. workpad の plan / checklist に各 feedback 項目と解決 status を追記する
5. feedback 反映の変更後は validation を再実行し、push する
6. actionable comment が残らなくなるまで本 sweep を繰り返す

inline review comment への返信を POST する時、`gh api -f body='...'` は使わない。body 中の backtick (`` ` ``) や `$` が zsh のコマンド置換や変数展開として解釈され、囲まれた部分が黙って消える。draft を `.claude/tmp/` 配下の file に書き、`jq -n --rawfile body <path> ... | gh api ... --input -` で stdin から渡す。詳細は `land` skill SKILL.md のレビュー対応節を参照する。同じ問題は `gh issue comment` や top-level `gh pr comment` でも起きるので、それぞれ `--body-file <path>` を使う

## 阻害時の escape hatch (必須挙動)

完了を阻害する必須ツールや認証 / permissions の不足が session 内で解消できない時のみ本 hatch を使う。

- GitHub は基本 blocker にならない。alternate remote / auth mode 等の fallback を必ず先に試す
- GitHub アクセス / 認証を blocker と判断する前に、fallback を全部試して workpad に記録する
- GitHub 以外の必須ツール / 認証が missing なら、`Human Review` へ動かし、workpad に blocker brief を書く
  - 何が missing か
  - なぜ受け入れ条件 / validation を block するか
  - unblock に必要な人間の具体 action
- brief は簡潔に、action-oriented に書く。workpad 外に追加 top-level comment を作らない
- 本 escape hatch に該当する時のみ PR を Draft のまま `Human Review` へ遷移してよい。通常経路では Step 2 の Ready 化手順を必ず実行する

## Completion bar before Human Review

次の全項目を満たした時のみ `Human Review` へ動かす。

- Step 1 / Step 2 の checklist が完了し、workpad comment にその通り反映されている
- acceptance criteria とチケット由来の validation 項目が全て完了している
- local validation / test が最新コミットで green
- PR CI check が最新コミットで green
- PR feedback sweep が完了し、actionable comment が残っていない
- branch が push 済みで、PR が issue に link されている (attachment または workpad link)
- PR が Ready 状態 (Draft でない)。`gh pr view --json isDraft` で確認する。例外: 阻害時の escape hatch に該当する真の外部 blocker の場合のみ Draft 許容

## Guardrails

- branch PR が既に closed / merged なら、その branch や前回の実装状態を継続に使わない
- closed / merged branch PR のチケットは、`origin/main` から fresh branch を切り、reproduction / planning からやり直す
- Linear status が `Backlog` なら何も変更しない。人間が `Todo` へ動かすのを待つ
- planning / progress 追跡のために issue body / description を編集しない
- workpad comment は 1 issue につき 1 つだけ (`## Codex Workpad`)
- 仮 proof 編集は local 検証目的のみ許可し、コミット前に必ず revert する
- スコープ外の改善は別 `Backlog` issue を作って受ける。本 issue のスコープは広げない
  - 別 issue は title / description / acceptance criteria を明記し、same-project に置き、本 issue を `related` でリンクし、依存があれば `blockedBy` を貼る
  - 例外: main 由来の既存違反が CI を block した場合、本 PR 内で一括 fix する
- Completion bar を満たさないまま `Human Review` へ動かさない
- `Human Review` は本 workflow の terminal。動かした時点で session は exit する
- terminal state (`Done`) なら何もせず shutdown する
- issue の文は簡潔に、レビュアー向けに書く
- workpad が無い段階で blocked になったら、blocker と影響と次の unblock action を書いた blocker comment を 1 件作る

## Workpad template

永続 workpad comment は次の構造を使い、実行中ずっと in-place で更新する。

````md
## Codex Workpad

```text
<hostname>:<abs-path>@<short-sha>
```

### Plan

- [ ] 1\. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task
- [ ] 2\. Parent task

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

### Validation

- [ ] targeted tests: `<command>`

### Notes

- <short progress note with timestamp>

### Confusions

- <only include when something was confusing during execution>
````

## Identifier ルール

`{{ issue.identifier }}` を branch 名と PR タイトル先頭にそのまま埋め込む。Linear の GitHub linking は identifier 完全一致で動く。URL slug や title から推論した別形 (例: 余計な桁を足す等) を書かない。

## PR ルール

- `main` 直接 push 禁止。必ず `gh pr create` で PR を出す
- PR タイトル先頭に `{{ issue.identifier }}: ` を必ず入れる。例 `{{ issue.identifier }}: <descriptor>`。Linear ↔ GitHub auto-link はタイトル中の identifier 完全一致で発火する (https://linear.app/docs/github#linking-linear-issues-to-github-prs)
- PR body 末尾に {{ issue.url }} を併記
- PR body は `--body-file` で渡す。`.claude/tmp/pr-body-<slug>.md` に書いて `gh pr create --body-file <path>` で渡す
- issue が曖昧 (acceptance criteria が不明) なら、PR body に plan と質問を書いた draft PR を開いて止まる

## スコープ外

issue が次のいずれかの作業を含むなら、止まってユーザーに label 修正を依頼する。

- vault 内容の編集 (`MH4GF/works`)
- Symphony orchestrator のコード (`MH4GF/symphony`)
- secrets / workspace 固有 identifier のコミット
