---
name: symphony-workflow
description: Symphony orchestrator からディスパッチされた bg セッションの共通実行手順。issue のステータス振り分け、workpad 運用、実装から Human Review 遷移、マージまでを定義する。Symphony の bg セッション起動直後に呼ぶ
---

# symphony-workflow

Symphony からディスパッチされた bg セッションが issue を処理する共通手順。リポジトリ固有の設定 (tracker / workspace / clone) と例外ルールはディスパッチプロンプト (各リポジトリの `WORKFLOW.md`) 側にあり、本スキルの共通手順を上書きする。

## Tracker の判定

本スキルは tracker を問わず同じ手順で動く。tracker 固有の操作だけを「Tracker 操作」の表から引く。

作業中の repo の `WORKFLOW.md` frontmatter `tracker.kind` を読んで判定する。works repo のみ `agents/ai-native/WORKFLOW.md`、それ以外は repo root の `WORKFLOW.md` に置かれている。読み取れない場合は `linear` として扱う。

## 前提条件

- `kind: linear` — Linear MCP サーバー `linear-mh4gf` が利用可能である前提
- `kind: github` — `gh` が認証済みである前提

設定されていなければ即座に止まり、ブロッカーを明示する。

## Tracker 操作

以降の手順が参照する操作の実体。`<repo>` に `WORKFLOW.md` の `tracker.repo` (`owner/name`) を、`<n>` に identifier `#123` の数値部分を入れる。

| 操作 | kind: linear | kind: github |
| --- | --- | --- |
| issue 取得 | `mcp__linear-mh4gf__get_issue` を identifier で呼ぶ | `gh issue view <n> --repo <repo> --json number,title,body,state,labels,url` |
| ステータス遷移 | `mcp__linear-mh4gf__save_issue` で state を更新する | 非終端は `gh issue edit <n> --repo <repo> --add-label "status:<slug>"`、終端は `gh issue close <n> --repo <repo> --reason completed` |
| issue 検索 | `mcp__linear-mh4gf__list_issues` | `gh issue list --repo <repo> --search "<query>" --state all` |
| issue 起票 | `mcp__linear-mh4gf__save_issue` | `gh issue create --repo <repo> --title <title> --body-file <path> --label "priority:<n>"` |
| コメント削除 | `mcp__linear-mh4gf__delete_comment` | `gh api --method DELETE repos/<repo>/issues/comments/<comment_id>` |
| PR リンク | Linear のアタッチメント (PR タイトル経由で自動付与) | PR 本文の `Closes <identifier>` |

`status:<slug>` はステータス名を小文字化し、英数字以外の連続を `-` に置換したもの。`In Progress` なら `status:in-progress`。`kind: github` では `status:*` を 1 つだけ持つ規約で、古いラベルは repo 側の正規化 Action が剥がす。手で剥がす操作は不要。

`kind: github` の終端遷移は `Canceled` のみ `--reason "not planned"` を使う。

## 基本姿勢

- 本セッションは無人実行のオーケストレーション。人間に追加対応を求めない
- セッション起動直後に `workpad` スキルを呼ぶ。`## Codex Workpad` コメントを検索または作成し、新しい実装に入る前に最新化する
- まずステータスを確認し、下のステータスマップに従って振り分ける
- 実装より先に計画と検証設計に十分な時間を割く
- 修正対象を明示するため、変更前に現状の挙動や issue のシグナルを再現させる
- チケットのメタデータ (state、チェックリスト、受け入れ条件、リンク) を最新に保つ
- 進捗の唯一の一次ソースは `## Codex Workpad` コメント 1 つ。"done" や要約の別コメントは出さない
- **turn は予告なく打ち切られる。** Symphony は turn timeout でセッションを強制終了し、次は新規セッションが workpad とブランチのコードだけを頼りに再開する。workpad に書かれていない調査結果 / 判断 / 検証結果は失われ、次セッションが同じ探索をやり直す。workpad の更新は「余裕があればやる作業」ではなく、進捗を確定させる唯一の手段として扱う。詳細は「workpad 更新の必須タイミング」を参照する
- チケットに `Validation` / `Test Plan` / `Testing` の節があれば必須受け入れ条件として workpad に転記し、完了前に実行する
- スコープ外の指摘を実行中に発見したら、次の 4 つの門をすべて通る場合に限り「Tracker 操作」の issue 起票で別 issue を立てる。本 issue のスコープは広げない
  - ユーザーに実害が出る指摘か。観測性・保守性・ドキュメント・テストの体裁だけを扱う指摘は起票しない
  - 既存 issue と重複していないか。起票前に「Tracker 操作」の issue 検索で同一症状を探す。検索は `Backlog` に限定せず、終端状態 (`Done` / `Canceled`) 以外をすべて対象にする。実装中や `Human Review` の issue と重なることがあり、状態を絞ると取りこぼす。見つかれば起票せずその issue へ関連リンクを貼る
  - 指摘の前提が `origin/main` に存在するか。本ブランチでしか成立しない指摘は起票せず、PR のレビューコメントとして残す
  - `priority` を決められるか。必ず設定する。決められないなら起票の材料が足りていない
  - 4 つを通った issue は title / description / 受け入れ条件を明記する。`Backlog` に置き、本 issue へのリンクを本文に書く。`kind: linear` は同一プロジェクトへ紐付け、依存があれば `blockedBy` を貼る。`kind: github` は同一 repo に立てる。依存は blocking の仕組みが無いため `Backlog` 据え置きで表現する
- 門を通らなかった指摘は起票しない。並列レビュースイープの `### Notes` に 1 行残して終える
- 1 セッションで起票する issue は 3 件までを目安とする。超える指摘が出たときは本 PR のスコープ設定が誤っている可能性が高い。その旨を workpad の `### Confusions` に書く
- ステータスは対応する品質バーを満たした時だけ動かす
- 必須要件 / 秘匿情報 / 権限の不足によるブロッカーでなければ、最後まで自律稼働する
- 阻害時のエスケープハッチは真の外部ブロッカーかつ代替手段を尽くした時のみ使う
- 最終メッセージは完了した対応とブロッカーのみ書く。「ユーザーへの次の手順」は書かない

## workpad 更新の必須タイミング

次の条件を満たしたら、**他の作業より先に** `workpad` スキルで既存の `## Codex Workpad` コメントを更新する。更新を後回しにして次の作業へ進んではならない。

- 計画を立て終えた時 (`Plan` / `Acceptance Criteria` / `Validation` を埋める)
- 再現シグナルを取り終えた時 (コマンドと出力を `Notes` に残す)
- 原因を特定した時、または当初の仮説を捨てて方針を変えた時 (何を捨て何を採ったかを `Notes` に残す)
- コード変更を一区切りコミットした時 (対象ファイルと短い SHA を `Notes` に残す)
- 検証 / テストを実行した時 (コマンドと合否を `Validation` に反映する)
- PR を作成・更新した時
- 並列レビュースイープ / PR フィードバックスイープの各周回を終えた時
- CI の失敗を確認した時、およびその対応を終えた時
- ブロッカーに突き当たった時 (何が / なぜ / 解除に必要な人間の対応)
- 上記に当てはまらなくても、**直前の更新から 30 分以上経過した時**

書く内容は次を満たす。判断基準は、次セッションが同じ調査をやり直さずに済むこと。

- 完了した項目にチェックを付ける。完了した作業を未チェックのまま放置しない
- `Notes` は結論を書く。試した経路と、その結果採らなかった選択肢も 1 行で残す
- 未着手で残っている作業を `Plan` に明示する。次に何をすべきかが読み取れる状態にする

## 関連スキル

- `workpad` — 単一の `## Codex Workpad` コメントを検索または作成し、計画 / 受け入れ条件 / 検証 / メモを 1 箇所に集約する
- `parallel-review` — `Human Review` 遷移前に bg セッション自身が行うセルフレビュー。AI 生成ノイズ、CLAUDE.md 違反、挙動の正しさに関わるバグの一次検出を行う。構成ツールと出力フォーマットはスキル本体を一次ソースとする。「並列レビュースイープ」の節で必須
- `pr-feedback-fetch` — PR の 3 チャンネルのフィードバック (トップレベル / インラインレビュー / レビューサマリー) を 1 回で取得する。「PR フィードバックスイープ」の節で必須。スキルが未配置の環境では同節の代替 3 コマンドを直接実行する
- `land` — ステータスが `Merging` になったら、`land` スキルを繰り返し呼んで PR がマージされるまで進める。`gh pr merge` を直接叩かない

## ステータスマップ

- `Backlog` — 本ワークフローのスコープ外。何も変更しない
- `Todo` — キュー待ち。作業に入る前に必ず `In Progress` へ動かす
  - 例外: 既存 PR がアタッチされていればフィードバック / やり直しのループとして扱う。PR フィードバックスイープを完走し、対応または明示的なプッシュバックを返してから再検証し、`Human Review` へ戻す
- `In Progress` — 実装稼働中
- `Human Review` — PR がアタッチ済みで検証完了、人間の Approve 待ち。本ワークフローの `terminal_states` に含まれる
- `Merging` — 人間が Approve 済み。`land` スキルのフローを実行する
- `Rework` — レビュアーが方針の全リセットを要求。計画と実装を再度ゼロから行う
- `Done` — 終端。何もしない

## ステップ 0: 現在のチケット状態を判定して振り分ける

1. 「Tracker 操作」の issue 取得を identifier で呼んで issue を取得する
2. 現在のステータスを読む
3. 対応フローへ振り分ける
   - `Backlog` — issue を変更しない。`Todo` へ人間が動かすのを待って止まる
   - `Todo` — 即「Tracker 操作」のステータス遷移で `In Progress` へ動かす。続けて `workpad` スキルで初期コメントを検索または作成し、ステップ 1 へ進む
     - 開始時点で PR が既にアタッチされていれば、まず PR の未解決コメントを全件読み、必須の変更点と明示プッシュバックの方針を立てる
   - `In Progress` — 現行の workpad コメントを起点に実行フローを続ける
   - `Human Review` — 終端。何もせず終了する
   - `Merging` — `land` スキルを起動し、PR がマージされるまで繰り返す。`gh pr merge` を直接叩かない
   - `Rework` — ステップ 4 へ進む
   - `Done` — 何もせず終了する
4. 現ブランチの PR の状態を確認する
   - 既存ブランチの PR が `CLOSED` または `MERGED` なら、前回のブランチ作業は再利用しない
   - `origin/main` から新規ブランチを切って、新規の試行として実行フローを再起動する
5. `Todo` チケットは次の順で開始する
   - 「Tracker 操作」のステータス遷移で `In Progress` へ動かす
   - `workpad` スキルで `## Codex Workpad` の初期コメントを検索または作成する
   - その後で分析 / 計画 / 実装を始める
6. ステータスと issue 内容が不整合なら、workpad に短いメモを追記して、安全側のフローで進める

## ステップ 1: 実行の開始・継続 (Todo または In Progress)

1. `workpad` スキルで単一の永続 workpad コメントを検索または作成する
   - 既存コメントから `## Codex Workpad` 見出しを検索する
   - 解決済みコメントは無視する。有効かつ未解決のものだけ再利用の対象
   - 見つかればそれを再利用する。新規の workpad コメントは作らない
   - 無ければ 1 つ作成し、以後の進捗更新は全てそこへ書く
   - workpad コメント ID を保持し、進捗更新は必ず同じ ID へ向ける
2. `Todo` 起点で来た場合、追加のステータス遷移で時間を使わない。本ステップ開始時には既に `In Progress` であるはず
3. 新規編集の前に workpad を現状と整合させる
   - 既に完了済みの項目にチェックを付ける
   - 計画を現スコープに対して網羅的になるまで拡張・修正する
   - `Acceptance Criteria` と `Validation` がタスクと整合しているか確認する
4. 階層立てた計画を workpad コメントへ書く・更新する
5. workpad 先頭に環境スタンプを 1 行のコードフェンスで置く
   - 形式: `<host>:<abs-workdir>@<short-sha>`
   - 例: `mac-studio:/Users/hermes/.symphony/workspaces/<repo>/MH-XX@f3702a4`
   - issue のフィールドから導出できる情報 (issue ID、ステータス、ブランチ、PR リンク) は重複させない
6. 受け入れ条件と TODO を同じコメント内にチェックリストとして書く
   - 変更がユーザー向け機能なら、実際の利用経路を最初から最後まで辿る UI 確認の受け入れ条件を含める
   - チケットに `Validation` / `Test Plan` / `Testing` の節があれば、workpad の `Acceptance Criteria` と `Validation` へ必須チェックボックスとして転記する。任意項目への格下げは禁止
7. 計画をセルフレビューし、コメント内で磨き込む
8. 実装前に再現シグナルを取り、workpad の `Notes` に記録する。コマンドと出力か、決定的な挙動の説明
9. `origin/main` の最新をブランチへマージして同期し、結果を workpad の `Notes` に書く。マージ元 / `clean` か `conflicts resolved` か / 結果の HEAD short SHA を含める
10. 実行フェーズへ進む

## ステップ 2: 実行フェーズ (Todo → In Progress → Human Review)

1. 現在のリポジトリ状態 (`branch`, `git status`, `HEAD`) を確認し、開始時の `origin/main` 同期結果が workpad に書かれているかを再確認する。書かれていなければ書く
2. ステータスが `Todo` なら `In Progress` へ動かす。それ以外はそのまま
3. 既存の workpad コメントを実行中のチェックリストとして扱う。スコープ / リスク / 検証方針 / 新発見タスクなど、現実が変わったら躊躇なく書き換える
4. 階層 TODO に沿って実装し、コメントを最新に保つ
   - 完了項目にチェックを付ける
   - 新規発見項目を該当節へ追記する
   - 親子構造を保つ
   - 各マイルストーン (再現完了 / コード変更の反映 / 検証実行 / レビューフィードバック対応) の完了時に即 workpad を更新する
   - 完了した作業を未チェックのまま放置しない
   - `Todo` 起点で既に PR がアタッチされていたチケットは、新規の機能作業の前に PR フィードバックスイープを完走する
5. スコープに必要な検証 / テストを実行する
   - 必須ゲート: チケット由来の `Validation` / `Test Plan` / `Testing` を実行する。未達は未完了とみなす
   - 変更挙動を直接示す絞り込んだ証明を優先する
   - 確認用の一時的な編集 (ハードコードしたテスト入力 / モックの UI アカウント) は信頼度を上げる目的なら許可する
   - 一時的な編集はコミット / プッシュ前に必ず戻し、内容と結果を workpad の `Validation` / `Notes` に残す
6. 受け入れ条件を再点検し、欠落があれば塞ぐ
7. `git push` の前に必ずスコープの検証を走らせ、green を確認する。失敗なら原因を直してから再実行し、green を確認してからコミットしてプッシュする
8. PR URL を issue に紐付ける。「Tracker 操作」の PR リンクを優先し、無ければ workpad コメントにリンクを残す
9. `origin/main` の最新をブランチへマージし、コンフリクトを解消し、チェックを再実行する
10. workpad コメントを最終状態へ更新する
    - 計画 / 受け入れ条件 / 検証のチェックリスト完了項目を全てチェック済みにする
    - 最終の引き継ぎメモ (コミット + 検証結果) を同じ workpad に書く
    - PR URL は issue 側 (アタッチメント / リンク) に置き、workpad 本文には重複させない
    - 実行中に不明瞭な点があれば末尾に `### Confusions` 節を簡潔に追加する
    - 完了サマリーの追加コメントは出さない
11. `Human Review` へ動かす前に CI とフィードバックの締めのループを回す
    - 並列レビュースイープを完走し、対応が必要な指摘を残さない
    - `gh pr checks` を繰り返し確認し、全て green になるまで待つ。CI の失敗は本ターン内で直す。Stop hook は使わず、本スキルがそのループを担う
    - PR フィードバックスイープを完走し、対応が必要なコメントを残さない
    - チケット由来の検証 / テスト計画の項目が全て workpad でチェック済みであることを確認する
    - 状態遷移前に workpad を開き直し、`Plan` / `Acceptance Criteria` / `Validation` が完了した作業と過不足なく一致するよう更新する
    - `gh pr view --json isDraft` で Draft 状態を確認し、Draft なら `gh pr ready` で Ready 化する。これで GitHub 側の `ready_for_review` イベントが発火し、Slack のレビュー通知が飛ぶ。例外: 阻害時のエスケープハッチに該当する真の外部ブロッカーの場合のみ Draft 維持可
12. 上記を満たしたら「Tracker 操作」のステータス遷移で `Human Review` へ動かす
    - 例外: GitHub 以外の必須ツール / 認証が不足し、阻害時のエスケープハッチに該当する場合のみ動かす
    - その時はブロッカー概要と解除に必要な対応を workpad に書いた上で `Human Review` へ動かす
13. `Todo` 起点で既に PR がアタッチされていたチケットは次を満たす
    - 既存 PR のフィードバック (インラインレビューコメント含む) を全件レビューし、コード変更または明示プッシュバックで解決済み
    - 必要な更新をブランチにプッシュ済み
    - その上で `Human Review` へ動かす

## ステップ 3: Human Review とマージ

1. `Human Review` は本ワークフローの終端。bg セッションは終了し、Symphony は人間の操作まで再ディスパッチを止める
2. 人間が PR をレビューする。少量の追加変更が必要なら、ステータスを `In Progress` へ動かす。`kind: linear` は PR を Draft に戻す (`gh pr ready --undo`) と `gitAutomationStates.draft` 経由でも遷移する。Symphony が再ディスパッチし、bg セッションが既存 workpad から再開する
3. 方針の全リセットが必要なら、人間が `Rework` へ動かす。Symphony が再ディスパッチし、bg セッションがステップ 4 を実行する
4. Approve され、人間が `Merging` へ動かしたら、Symphony が再ディスパッチし、bg セッションが `land` スキルを起動する
5. `Merging` 状態では `land` スキルを繰り返し呼んで PR がマージされるまで進める
   - `land` スキルは CI green / `mergeable` / Approve / ステータス `Merging` を事前検証する
   - 通れば `gh pr merge --squash --delete-branch` を実行する
   - マージ後にステータスは `Done` へ動く。`kind: linear` は `gitAutomationStates.merge` イベント経由、`kind: github` は PR 本文の `Closes <identifier>` により issue が close される
   - `gh pr merge` を直接叩かない

## ステップ 4: Rework の処理

1. `Rework` は方針の全リセット。少量の修正は通常の `In Progress` → `Human Review` のループで扱う。`Rework` は明示的な「やり直し」信号
2. issue 本文と人間の全コメントを読み直し、今回の試行で何を変えるかを明示する。新 workpad の `Notes` に差分を書く
3. 既存 PR を `gh pr close` で閉じる
4. 既存の `## Codex Workpad` コメントを「Tracker 操作」のコメント削除で削除する。新規ブランチ + 新規 workpad の規約
5. `origin/main` から新規ブランチを切る
6. 通常の開始フローへ戻る
   - ステータスが `Todo` なら `In Progress` へ動かす。それ以外はそのまま
   - 新規の `## Codex Workpad` 初期コメントを作る
   - 新規の計画 / チェックリストを立て、最後まで実行する

## 並列レビュースイープ (必須)

`Human Review` へ動かす前に bg セッション自身が行うセルフレビュー。AI 生成ノイズ、CLAUDE.md 違反、挙動の正しさに関わるバグを人間レビュアーの前段で塞ぐ。3 つのスイープの役割分担は次のとおり

- 並列レビュースイープ — bg セッション自身のローカルスイープ。本節が担う
- CI — プッシュ後の自動チェック。締めのループの `gh pr checks` 確認で担保する
- PR フィードバックスイープ — プッシュ後の人間 + bot レビュー。「PR フィードバックスイープ」の節が担う

手順は次のとおり

1. `/parallel-review` を実行する。構成ツールと出力フォーマットはスキル本体を一次ソースとして扱う
2. 結果サマリー (各ツールの合否 / 指摘の有無) と、対応が必要な指摘の対応状況を workpad の `### Notes` に時系列で追記する
3. 対応が必要な指摘は全ツールいずれの出力でも遷移を止めるものと扱う。「PR フィードバックスイープ」と同じ基準で、次のいずれかが満たされるまで完了にしない
   - コード / テスト / ドキュメントを更新して対応した
   - 明示的かつ理由付きのプッシュバックを workpad の `### Notes` に記録した。プッシュバックで完了にした指摘は次回スイープで再出現しても対応対象から除外する
   - スコープ外と判断し、「基本姿勢」の 4 つの門で起票要否を決め、その結果を workpad の `### Notes` に記録した。門を通らなかった指摘はここで終わりにする
4. コード変更を伴う対応をした場合はコミット + プッシュし、CI 確認をやり直してから `/parallel-review` を再実行する。プッシュバックだけの対応なら再実行不要。対応が必要な指摘が残らなくなった時点で本スイープを完了とする
5. スキル構成ツールの一部だけが失敗した場合 (例: 依存 CLI 未インストール、subagent 未配置) は、出た指摘だけ上記基準で処理する。部分失敗の事実を workpad の `### Notes` に記録し、スイープを完了扱いとする。スキル全体が実行不能な時のみエスケープハッチ (下記の阻害時の節) を適用する

## PR フィードバックスイープ (必須)

PR がアタッチされたチケットは、本スイープを完走させてから `Human Review` へ動かす。

1. `pr-feedback-fetch` スキルを呼んで PR の 3 チャンネルのフィードバックを 1 回で取得する。引数は次のいずれか
   - 引数なし — 現ブランチの PR を自動解決
   - PR 番号 (例 `200`) — 番号指定
   - PR URL — URL 指定
   - スキルはトップレベル / インラインレビュー / レビューサマリーを順に取得し、`取得 channel: 3/3` の集計まで揃えて返す。チャンネルを個別に叩き分けない
   - スキルが未配置の環境では、次の 3 コマンドを順に実行して同じ 3 チャンネルを取得する。順序は固定で、1 つでも省略すると本スイープが破綻する
     - トップレベル — `gh api repos/<owner>/<repo>/issues/<pr>/comments`
     - インラインレビュー — `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
     - レビューサマリー — `gh api repos/<owner>/<repo>/pulls/<pr>/reviews`
2. 対応が必要なレビュアーコメント (人間 / bot 問わず) は、インラインレビューコメント含めて全て遷移を止めるものと扱う。次のいずれかが満たされるまで完了にしない
   - コード / テスト / ドキュメントを更新して対応した
   - 明示的かつ理由付きのプッシュバックをスレッドに返信した
3. workpad の計画 / チェックリストに各フィードバック項目と解決状況を追記する
4. フィードバック反映の変更後は検証を再実行し、プッシュする
5. `pr-feedback-fetch` スキルを再度呼び、対応が必要なコメントが残らなくなるまで本スイープを繰り返す

インラインレビューコメントへの返信を投稿する時、`gh api -f body='...'` は使わない。本文中のバッククォート (`` ` ``) や `$` が zsh のコマンド置換や変数展開として解釈され、囲まれた部分が黙って消える。下書きを `.claude/tmp/` 配下のファイルに書き、`jq -n --rawfile body <path> ... | gh api ... --input -` で標準入力から渡す。詳細は `land` スキル SKILL.md のレビュー対応節を参照する。同じ問題は `gh issue comment` やトップレベルの `gh pr comment` でも起きるので、それぞれ `--body-file <path>` を使う

## 阻害時のエスケープハッチ (必須挙動)

完了を阻害する必須ツールや認証 / 権限の不足がセッション内で解消できない時のみ本ハッチを使う。

- GitHub は基本ブロッカーにならない。別リモートや別の認証方式などの代替手段を必ず先に試す
- GitHub のアクセス / 認証をブロッカーと判断する前に、代替手段を全部試して workpad に記録する
- GitHub 以外の必須ツール / 認証が不足しているなら、`Human Review` へ動かし、workpad にブロッカー概要を書く
  - 何が不足しているか
  - なぜ受け入れ条件 / 検証を阻むか
  - 解除に必要な人間の具体的な対応
- 概要は簡潔に、対応を促す形で書く。workpad 外に追加のトップレベルコメントを作らない
- エスケープハッチ経由で `Human Review` へ動かす時は PR を Ready 化せず Draft のまま遷移してよい。完了バーの「PR が Ready 状態」要件はこの経路に限り免除される。ブロッカー概要から人間が状況を把握する
- 並列レビュースイープ全体が外部依存 (スキル本体未配置、必須 CLI 未認証など) で実行不能な時も本ハッチを適用する。workpad のブロッカー概要に未実施の旨と原因を明記した上で `Human Review` へ動かす。完了バーの「並列レビュースイープ完走」要件はこの経路に限り免除される。部分失敗 (一部ツールのみ失敗) は本ハッチの対象外で、並列レビュースイープの手順 5 に従う

## Human Review 前の完了バー

次の全項目を満たした時のみ `Human Review` へ動かす。

- ステップ 1 / ステップ 2 のチェックリストが完了し、workpad コメントにその通り反映されている
- 受け入れ条件とチケット由来の検証項目が全て完了している
- ローカルの検証 / テストが最新コミットで green
- 並列レビュースイープが完了し、対応が必要な指摘が残っていない
- PR の CI チェックが最新コミットで green
- PR フィードバックスイープが完了し、対応が必要なコメントが残っていない
- ブランチがプッシュ済みで、PR が issue にリンクされている (アタッチメントまたは workpad リンク)
- PR が Ready 状態 (Draft でない)。`gh pr view --json isDraft` で確認する。GitHub の `ready_for_review` イベントを発火させ、Slack 通知で人間が Approve のタイミングを拾えるようにするため。例外: 阻害時のエスケープハッチに該当する場合のみ Draft のまま遷移する

## ガードレール

- ブランチの PR が既にクローズ済みまたはマージ済みなら、そのブランチや前回の実装状態を継続に使わない
- クローズ済み / マージ済みの PR を持つチケットは、`origin/main` から新規ブランチを切り、再現 / 計画からやり直す
- ステータスが `Backlog` なら何も変更しない。人間が `Todo` へ動かすのを待つ
- 計画や進捗の追跡のために issue 本文を編集しない
- workpad コメントは 1 issue につき 1 つだけ (`## Codex Workpad`)
- workpad を更新しないまま作業を続けない。「workpad 更新の必須タイミング」の条件を満たしたら、次の作業より先に更新する
- 確認用の一時的な編集はローカル検証の目的のみ許可し、コミット前に必ず戻す
- スコープ外の指摘は「基本姿勢」の 4 つの門を通る場合のみ別の `Backlog` issue を作って受ける。門を通らないものは起票しない。本 issue のスコープは広げない
- 完了バーを満たさないまま `Human Review` へ動かさない
- `Human Review` は本ワークフローの終端。動かした時点でセッションは終了する
- 終端状態 (`Done`) なら何もせず終了する
- issue の文は簡潔に、レビュアー向けに書く
- workpad が無い段階で行き詰まったら、ブロッカーと影響と次の解除対応を書いたブロッカーコメントを 1 件作る

## Workpad テンプレート

永続 workpad コメントは次の構造を使い、実行中ずっとその場で更新する。

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

identifier はディスパッチプロンプトの `## Issue` 節の値をそのまま使う。URL スラッグやタイトルから推論した別形 (例: 余計な桁を足す等) を書かない。

### kind: linear

PR タイトル末尾に `(<issue identifier>)` を付ける (例: `docs(workflow): ... (MH-67)`)。Linear がこの記載を読んで PR を自動アタッチする。

参照: <https://linear.app/docs/github#linking-linear-issues-to-github-prs>

ブランチ名や PR 本文には identifier の記載を要求しない。リンクは PR タイトル 1 箇所だけで成立する。

アタッチ検証は PR 作成直後の必須ステップとして次を行う

- PR 作成から 30〜60 秒後に「Tracker 操作」の issue 取得を再実行する
- `attachments` 配列に対象 PR の URL が含まれていることを確認する
- 含まれていない場合は PR タイトルの identifier 記載を見直し、`gh pr edit --title` で修正して再検証する
- 2 分待ってもアタッチされない場合は Linear と GitHub の連携側の不整合の可能性。workpad に「アタッチ未付与」を明記し、`Human Review` で人間判断に委ねる

### kind: github

PR 本文に `Closes <identifier>` を verbatim で書く (例: `Closes #123`)。マージ時に issue が close され、終端状態へ移る。

`Refs:` や `Related to` では close が発火しないため使わない。リンクは PR 本文のこの 1 行だけで成立し、アタッチ検証のステップを踏まない。

## PR ルール

- `main` への直接プッシュ禁止。必ず `gh pr create` で PR を出す
- identifier の記載は「Identifier ルール」の tracker 別の規約に従う
- PR 本文の末尾に issue の URL を併記する (ステップ 0 の issue 取得結果から取る)。人間のレビュアーが issue へ遷移できるようにするため
- PR 本文は `--body-file` で渡す。`.claude/tmp/pr-body-<slug>.md` に書いて `gh pr create --body-file <path>` で渡す
- issue が曖昧 (受け入れ条件が不明) なら、PR 本文に計画と質問を書いた Draft PR を開いて止まる
