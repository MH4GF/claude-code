---
name: create-linear-issue
description: Linear issue を本セッション内で起票する。事前に superpowers:brainstorming で意図を固めてから、実行時に解決した Linear MCP で書き込む。「これも issue にして」「あとで Symphony に拾わせたい」「Linear に追加して」「フォローアップを issue 化」等で必ず発動する。会話中に複数の起票候補が浮上した時も発動する。
---

# create-linear-issue

ユーザーの一行の意図を、`superpowers:brainstorming` で固めてから Linear issue として起票する skill。issue body は brainstorming の議論結果から直接組み立てる。書き込み先の Linear MCP server は実行時に解決する (「使用する MCP server」節)。

Symphony 系の運用へ乗せる前提で、起票先は Linear workspace の project と 1 対 1 に対応する。Symphony が次の poll で拾うことを期待する。

## なぜ brainstorming を必須にするか

brainstorming skill の哲学に従う。「simple な issue こそ未検証の前提が無駄な実装を生む」。issue の Outcome / Why / 完了条件を曖昧なまま起票すると、Symphony が拾った後の実装ワーカーは推測で動く羽目になる。brainstorming で意図を固めれば、その議論結果が issue body の素材になる。

## 使用する MCP server

起票の前段として、利用可能な Linear MCP server を実行時に解決する。特定の server 名を本文へ直書きしない理由は「設計判断と理由」節に記す。

1. 利用可能なツールから `mcp__<server>__save_issue` を持つ server を数える。これが Linear MCP server の集合。
2. 該当が 1 つだけなら、その server を採用する。追加の質問はしない。
3. 2 つ以上あるなら、AskUserQuestion でどの server (= どの workspace) へ起票するかを確定する。別 workspace への誤送を防ぐため、ここは必ず聞く。

以降の手順ではツールを `list_projects` のような論理名として書く。実際の呼び出しには解決した server の prefix を付ける (例: server が `foo` なら `mcp__foo__list_projects`)。代表的に次を使う。

- `list_projects` — project 一覧と ID 解決
- `list_teams` — team 一覧と ID 解決
- `list_issue_labels` — team の実在 label 取得
- `list_issues` — 重複検知
- `save_issue` — 起票

## 手順

### 1. superpowers:brainstorming で意図を固める

Skill ツール経由で `superpowers:brainstorming` を起動し、ユーザー の一行の意図を渡す。brainstorming は次を実施する。

- project context の探索 (関連ファイル / 先行事例 / 既存 issue)
- clarifying questions (one at a time)
- 2-3 approaches の提示と user 選択
- design sections の提示と user 承認

注意点:

- brainstorming skill の標準フローには「Write design doc → spec self-review → User reviews spec → Invoke writing-plans skill」がある
- 本 skill 経由では design doc を別ファイルとして書かない。議論結果は直接 issue description へ統合する
- 別ファイル書き出しと writing-plans 起動が起きそうになったら、ユーザー へ確認してスキップする
- 確認文言: 「create-linear-issue 経由なので design doc 書き出しと writing-plans をスキップし、議論結果から直接 Linear 起票へ進む」

理由: bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた新規ファイルを bg session 側から読めない。issue body だけが情報源になる前提で組む。

### 2. project と team を解決する

`list_projects` で project 一覧を取得する。ユーザー が指定した project (または会話の文脈で自明な project) を name で絞り込んで ID を得る。複数該当した時は AskUserQuestion で確定する。

その project の team ID も取得する。project レスポンスに teams が含まれていればそれを使う。含まれない時は `list_teams` で解決する。

### 3. 重複を検索する

brainstorming で出てきたキーワード (1〜2 語) で既存 issue を検索する。

```
list_issues(query="<keyword>", project="<projectId>")
```

近い既存 issue が出た場合、新規作成せず該当の identifier と URL をユーザー へ報告して止まる。

### 4. description を組み立てる

brainstorming の議論結果から、次の節構成へ落とす。

- `## Outcome` — 最終状態と価値を箇条書きで 2〜4 点。手順は書かない
- `## Why` — 起票の動機・前例との関係・設計の理由。bg session が edge case で判断するための背景情報
- `## 参考` — 参照した関連ファイル、関連 issue (`XX-NN` 形式、実在のみ)、外部 URL。意図にある外部参照を必ず含める
- `## 完了条件` — 観測可能な状態 (コマンド出力、ファイル存在、Linear / GitHub の見え方) を箇条書き
- `## スコープ外` — 含めない範囲を箇条書き

書き出し先は `.claude/tmp/create-linear-issue-body-<slug>.md`。`<slug>` は intent から派生した短い英数字。

ワーカー判断の余地 (実装時の選択肢) は `## 実装の自由度` として最後に置いてもよい。spec で確定しきれない open question を明示する。

`## 参考` 節へ書いてよいのは、bg session の workspace で存在を保証できる path のみ。例として origin/main へコミット済みのファイル、関連 Linear issue (`XX-NN`)、公開 URL。scraps/open/ や .claude/tmp/ のような未コミットの path は書かない。

### 5. title と label を決める

title はプロジェクトの慣行に合わせ、80 文字以内、prefix なし、要点 1 文で書く。

label は Symphony が WORKFLOW を route するキー。固定の候補を持たず、`list_issue_labels` で team の実在 label を引く。workspace ごとに存在する label が違うため、実在しない候補を提示しない。

```
list_issue_labels(team="<teamId>")
```

- 会話の文脈から対象 repo が自明 (例: 「skills/X への変更」「daily note の cron が…」「unslop の rule 追加」) なら、返ってきた実在 label の中から対応するものを選んで宣言する
- 決められないときは、`list_issue_labels` が返した実在 label だけを選択肢にして AskUserQuestion で確定する
- label なしでは Symphony が拾わないため必須。対象 repo に対応する label が実在しない場合は起票せず、その旨をユーザー へ報告して止まる

### 6. repo 固有の issue 規約を反映する

label は repo 名と一対一に対応する。その repo のローカル clone が見つかった場合のみ、issue 起票規約を読んで description をその節構成へ合わせる。clone の置き場は端末ごとの規約次第なので、path を本文へ直書きしない。

- 対象 repo のローカル clone を探す。無ければ本ステップを飛ばし、ステップ 4 の構成のまま進める
- clone が見つかった場合の探索先: repo root の `CLAUDE.md`、および agent ごとの `CLAUDE.md` (例: `agents/<project>/CLAUDE.md`)
- 規約が見つからない場合、ステップ 4 の構成のまま進める
- repo をローカルに持たないセッション (Claude Web など) でも本ステップを飛ばす

規約の最終的な充足は実装セッション側が担う。起票時の記載は入力の質を上げる手段として扱う。

### 7. MCP で起票する

`save_issue` を呼ぶ。引数:

- `team`: ステップ 2 で解決した team ID
- `project`: ステップ 2 で解決した project ID
- `title`: ステップ 5 で決めた title
- `description`: ステップ 4 で書いたファイルの中身 (`.claude/tmp/create-linear-issue-body-<slug>.md` を Read して渡す)
- `state`: project の Todo 相当 state ID (Symphony の `active_states` と一致させる)
- `labels`: ステップ 5 で選んだ実在 label の配列 (例: `["claude-code"]`)

戻り値から `identifier` と `url` を取る。

### 8. ユーザー に報告する

ユーザーに 1〜2 行で次を伝える。

- 起票した issue の identifier (verbatim) と URL
- Symphony が次の poll (約 30 秒以内) で拾うはずである旨

その後は本セッションの元タスクに戻る。

## 設計判断と理由

### 親セッション内で同期実行する

brainstorming と Linear 起票を本セッションで完結させる。別 bg セッションを spawn する価値は薄い。座って起票する場面が大半。bg を挟むと permission prompt 待ちで止まるリスクが増える。

### Linear MCP server を実行時に解決する

Linear MCP は claude のグローバル設定で workspace ごとに別 server として登録される。登録名は端末ごとに違い、個人端末と業務用端末で異なる。特定の server 名を本文へ書くと、その名前を持たない端末で毎回「MCP が無い」と報告する羽目になる。だから名前を直書きせず、`save_issue` を持つ server を実行時に列挙して解決する。

ただし誤送防止の意図は残す。別 workspace の Linear MCP が同時に起動していると、ai-native 向けの起票指示を誤って別 workspace へ届けてしまう。複数あるときだけ起票先を確認する手順にしているのは、この誤送を防ぐため。1 セッションの起票は解決した 1 つの server の prefix へ向け、別 server を混在させない。

### label で workflow を route する

Symphony は同じ Linear project の中で複数の WORKFLOW.md を並列駆動する。route キーは label。label 1 つが repo 1 つの WORKFLOW へ対応する。例えば `claude-code` 付き issue は claude-code repo の WORKFLOW が担当する。どの label が実在するかは workspace ごとに違うため、候補を本文へ固定せずステップ 5 で `list_issue_labels` から引く。label なしの issue はどの WORKFLOW からも拾われず宙吊り化するので、起票時の label 指定を必須化する。

### description を単一ソースにする

bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた別ファイルを参照できない。description には設計の理由と完了条件をまとめて記載する。ワーカーは issue body だけで全体像を取れる。edge case の判断に要る背景情報も description の `## Why` 節へ含める。

## エッジケース

- 意図が複数 issue にまたがる時: brainstorming 内で「1 issue に統合か個別に分けるか」を AskUserQuestion で確認する。分けるときは brainstorming も issue ごとに分けて回す
- 該当 project が `list_projects` に無い時: ユーザー へ「project 名が違うか、解決した Linear MCP server の権限スコープに無い」と報告して止まる
- 利用可能な Linear MCP server が 1 つも無い時: 起票先を解決できない。ユーザー へ Linear MCP の登録状況を確認するよう報告して止まる
- MCP 呼び出しが認証エラーで失敗した時: `claude mcp` の再認証をユーザー へ依頼してから止まる。リトライしない
- brainstorming をスキップしたい正当な理由がある時 (= ユーザー が「brainstorming は不要、直接起票して」と明示した時): 例外的に brainstorming を踏まず、ステップ 2 以降のみ実行する。スキップした事実を報告に明記する
