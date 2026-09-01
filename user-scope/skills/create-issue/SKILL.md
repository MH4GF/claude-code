---
name: create-issue
description: tracker の issue を本セッション内で起票する。事前に grilling で意図を固めてから、実行時に解決した起票先へ書き込む。「これも issue にして」「あとで Symphony に拾わせたい」「Linear に追加して」「GitHub issue 立てて」「フォローアップを issue 化」等で必ず発動する。会話中に複数の起票候補が浮上した時も発動する。
---

# create-issue

ユーザーの一行の意図を、`grilling` で固めてから issue として起票する skill。issue body は grilling で確定した内容から直接組み立てる。起票先と書き込み手段は実行時に解決する (「起票先を解決する」節)。

Symphony 系の運用へ乗せる前提で、起票先は Symphony の 1 系統と 1 対 1 に対応する。Symphony が次の poll で拾うことを期待する。

## なぜ grilling を必須にするか

simple に見える issue ほど、未検証の前提が無駄な実装を生む。issue の Outcome / Why / 完了条件を曖昧なまま起票すると、Symphony が拾った後の実装ワーカーは推測で動く羽目になる。

grilling は設計判断を design tree として展開し、frontier (前提が揃った決定) が空になるまで質問ラウンドを回す。全ての分岐を訪れて暗黙の仮定が残っていない状態が、そのまま issue body の素材になる。

## 手順

### 1. grilling で意図を固める

Skill ツール経由で `grilling` を起動し、ユーザー の一行の意図を渡す。grilling は次を実施する。

- 意図を design tree へ展開し、前提が揃った決定の集合 (frontier) を洗い出す
- frontier の質問を 1 ラウンドにまとめ、番号付き・推奨案付きで提示してユーザー の回答を待つ
- 回答で tree を組み直し、frontier が空になるまでラウンドを繰り返す
- 環境から取れる事実 (関連ファイル / 先行事例 / 既存 issue) は sub-agent で自分で調べる。ユーザー へ聞くのは決定だけ

注意点:

- frontier が空になり、shared understanding に達したとユーザー が確認するまでステップ 2 へ進まない。grilling は確認前に動くことを禁じている
- 議論結果を design doc として別ファイルへ書き出さない。直接 issue description へ統合する

理由: bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた新規ファイルを bg session 側から読めない。issue body だけが情報源になる前提で組む。

### 2. 起票先を解決する

起票先は Symphony の 1 系統 = 対象 repo。まず repo を決め、その repo の tracker を決める。

1. 会話の文脈から対象 repo が自明 (例: 「skills/X への変更」「daily note の cron が…」「unslop の rule 追加」) ならそれを採る。決められないなら AskUserQuestion で確定する
2. 対象 repo のローカル clone があれば `WORKFLOW.md` frontmatter の `tracker.kind` を読む。works repo のみ `agents/ai-native/WORKFLOW.md`、それ以外は repo root
3. clone が無い、または読み取れない場合は `linear` として扱う

以降、`kind` ごとに「Tracker 別操作」の手段を使う。

### 3. 重複を検索する

grilling で出てきたキーワード (1〜2 語) で既存 issue を検索する。検索は終端状態 (`Done` / `Canceled`) 以外をすべて対象にする。実装中や `Human Review` の issue と重なることがあり、状態を絞ると取りこぼす。

近い既存 issue が出た場合、新規作成せず該当の identifier と URL をユーザー へ報告して止まる。

### 4. description を組み立てる

grilling で確定した内容から、次の節構成へ落とす。

- `## Outcome` — 最終状態と価値を箇条書きで 2〜4 点。手順は書かない
- `## Why` — 起票の動機・前例との関係・設計の理由。bg session が edge case で判断するための背景情報
- `## 参考` — 参照した関連ファイル、関連 issue (実在のみ)、外部 URL。意図にある外部参照を必ず含める
- `## 完了条件` — 観測可能な状態 (コマンド出力、ファイル存在、tracker / GitHub の見え方) を箇条書き
- `## スコープ外` — 含めない範囲を箇条書き

書き出し先は `.claude/tmp/create-issue-body-<slug>.md`。`<slug>` は intent から派生した短い英数字。

ワーカー判断の余地 (実装時の選択肢) は `## 実装の自由度` として最後に置いてもよい。spec で確定しきれない open question を明示する。

`## 参考` 節へ書いてよいのは、bg session の workspace で存在を保証できる path のみ。例として origin/main へコミット済みのファイル、関連 issue、公開 URL。scraps/open/ や .claude/tmp/ のような未コミットの path は書かない。

### 5. title と route キーを決める

title はプロジェクトの慣行に合わせ、80 文字以内、prefix なし、要点 1 文で書く。

route キーは tracker で異なる。

- `kind: linear` — label が route キー。固定の候補を持たず、実在 label を引いて選ぶ。label なしでは Symphony が拾わないため必須。対象 repo に対応する label が実在しない場合は起票せず、その旨をユーザー へ報告して止まる
- `kind: github` — issue が repo に属するため route キーは不要。ステップ 2 で決めた repo がそのまま宛先になる

### 6. repo 固有の issue 規約を反映する

その repo のローカル clone が見つかった場合のみ、issue 起票規約を読んで description をその節構成へ合わせる。clone の置き場は端末ごとの規約次第なので、path を本文へ直書きしない。

- 対象 repo のローカル clone を探す。無ければ本ステップを飛ばし、ステップ 4 の構成のまま進める
- clone が見つかった場合の探索先: repo root の `CLAUDE.md`、および agent ごとの `CLAUDE.md` (例: `agents/<project>/CLAUDE.md`)
- 規約が見つからない場合、ステップ 4 の構成のまま進める
- repo をローカルに持たないセッション (Claude Web など) でも本ステップを飛ばす

規約の最終的な充足は実装セッション側が担う。起票時の記載は入力の質を上げる手段として扱う。

### 7. 起票する

「Tracker 別操作」の起票手段を使う。Symphony の `active_states` と一致する開始状態 (`Todo` 相当) を必ず設定する。

戻り値から identifier と URL を取る。

### 8. ユーザー に報告する

ユーザーに 1〜2 行で次を伝える。

- 起票した issue の identifier (verbatim) と URL
- Symphony が次の poll (約 30 秒以内) で拾うはずである旨

その後は本セッションの元タスクに戻る。

## Tracker 別操作

### kind: linear

書き込み先の Linear MCP server は実行時に解決する。特定の server 名を本文へ直書きしない理由は「設計判断と理由」節に記す。

1. 利用可能なツールから `mcp__<server>__save_issue` を持つ server を数える。これが Linear MCP server の集合
2. 該当が 1 つだけなら、その server を採用する。追加の質問はしない
3. 2 つ以上あるなら、AskUserQuestion でどの server (= どの workspace) へ起票するかを確定する。別 workspace への誤送を防ぐため、ここは必ず聞く

ツールは `list_projects` のような論理名で書く。実際の呼び出しには解決した server の prefix を付ける (例: server が `foo` なら `mcp__foo__list_projects`)。

| 用途 | ツール |
| --- | --- |
| project 一覧と ID 解決 | `list_projects` |
| team 一覧と ID 解決 | `list_teams` |
| team の実在 label 取得 | `list_issue_labels(team="<teamId>")` |
| 重複検知 | `list_issues(query="<keyword>", project="<projectId>")` |
| 起票 | `save_issue` |

`save_issue` の引数は次のとおり。

- `team` / `project` — ステップ 2 で解決した ID
- `title` — ステップ 5 で決めた title
- `description` — ステップ 4 で書いたファイルを Read して渡す
- `state` — project の `Todo` 相当 state ID
- `labels` — 実在 label の配列

project レスポンスが teams を含むなら、その値を team ID として使う。含まない時は `list_teams` で解決する。

### kind: github

`<repo>` はステップ 2 で決めた `owner/name`。

| 用途 | コマンド |
| --- | --- |
| 重複検知 | `gh issue list --repo <repo> --search "<keyword>" --state all` |
| 起票 | `gh issue create --repo <repo> --title "<title>" --body-file .claude/tmp/create-issue-body-<slug>.md --label "status:todo"` |

`--label "status:todo"` が Symphony の `active_states` に対応する開始状態。設計議論を先に挟みたい issue は `--label "status:backlog"` を付けて起票する。Symphony の pick up 対象から外れ、Backlog の一覧に並ぶ。

`status:*` を必ず 1 つ付ける。無しでも dispatch されないが、それは「Symphony 管理外」を意味する状態で、bot が立てる恒久 issue と同じ扱いになり Backlog の一覧から漏れる。

優先度を付けるなら `--label "priority:<1-4>"` を併記する。

## 設計判断と理由

### 親セッション内で同期実行する

grilling と起票を本セッションで完結させる。別 bg セッションを spawn する価値は薄い。座って起票する場面が大半。bg を挟むと permission prompt 待ちで止まるリスクが増える。

例外は grilling が事実確認へ飛ばす sub-agent だけ。決定はすべて本セッションでユーザー へ問う。

### Linear MCP server を実行時に解決する

Linear MCP は claude のグローバル設定で workspace ごとに別 server として登録される。登録名は端末ごとに違い、個人端末と業務用端末で異なる。特定の server 名を本文へ書くと、その名前を持たない端末で毎回「MCP が無い」と報告する羽目になる。だから名前を直書きせず、`save_issue` を持つ server を実行時に列挙して解決する。

ただし誤送防止の意図は残す。別 workspace の Linear MCP が同時に起動していると、ある系統向けの起票指示を誤って別 workspace へ届けてしまう。複数あるときだけ起票先を確認する手順にしているのは、この誤送を防ぐため。1 セッションの起票は解決した 1 つの server の prefix へ向け、別 server を混在させない。

`kind: github` ではこの誤送が構造的に起きない。`gh` が `--repo` で宛先を明示するため、workspace の概念そのものが無い。

### route キーが tracker で違う

`kind: linear` では Symphony が同じ project の中で複数の WORKFLOW.md を並列駆動するため、route キーとして label が要る。label 1 つが repo 1 つの WORKFLOW へ対応する。どの label が実在するかは workspace ごとに違う。候補を本文へ固定せず、実行時に引く。label なしの issue はどの WORKFLOW からも拾われず宙吊り化する。

`kind: github` では issue が repo へ属するため route キーが要らない。起票先の repo を決めた時点で route が確定する。

### description を単一ソースにする

bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた別ファイルを参照できない。description には設計の理由と完了条件をまとめて記載する。ワーカーは issue body だけで全体像を取れる。edge case の判断に要る背景情報も description の `## Why` 節へ含める。

## エッジケース

- 意図が複数 issue にまたがる時: 「1 issue に統合か個別に分けるか」を grilling の最初のラウンドの質問として出す。分けるときは grilling も issue ごとに分けて回す
- 該当 project が `list_projects` に無い時 (`kind: linear`): ユーザー へ「project 名が違うか、解決した Linear MCP server の権限スコープに無い」と報告して止まる
- 利用可能な Linear MCP server が 1 つも無い時 (`kind: linear`): 起票先を解決できない。ユーザー へ Linear MCP の登録状況を確認するよう報告して止まる
- `gh` が未認証の時 (`kind: github`): ユーザー へ `gh auth status` の確認を依頼して止まる
- 書き込みが認証エラーで失敗した時: 再認証をユーザー へ依頼してから止まる。リトライしない
- grilling をスキップしたい正当な理由がある時 (= ユーザー が「grilling は不要、直接起票して」と明示した時): 例外的に grilling を踏まず、ステップ 2 以降のみ実行する。スキップした事実を報告に明記する
