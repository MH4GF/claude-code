---
name: create-linear-issue
description: Linear issue を本セッション内で起票する。事前に superpowers:brainstorming で意図を固めてから、Linear MCP (`linear-mh4gf`) で書き込む。「これも issue にして」「あとで Symphony に拾わせたい」「Linear に追加して」「フォローアップを issue 化」等で必ず発動する。会話中に複数の起票候補が浮上した時も発動する。
---

# create-linear-issue

ユーザーの一行の意図を、`superpowers:brainstorming` で固めてから Linear issue として起票する skill。issue body は brainstorming の議論結果から直接組み立てる。Linear MCP server `linear-mh4gf` 経由で書き込む。

Symphony 系の運用へ乗せる前提で、起票先は Linear workspace の project と1対1に対応する。Symphony が次の poll で拾うことを期待する。

## なぜ brainstorming を必須にするか

brainstorming skill の哲学に従う。「simple な issue こそ未検証の前提が無駄な実装を生む」。issue の Outcome / Why / 完了条件 を曖昧なまま起票すると、Symphony が拾った後の実装ワーカーは推測で動く羽目になる。brainstorming で意図を固めれば、その議論結果が issue body の素材になる。

## 使用する MCP server

`linear-mh4gf` という名前で登録された Linear MCP server を使う。ツール命名は `mcp__linear-mh4gf__*` の prefix。代表的に次を使う。

- `mcp__linear-mh4gf__list_projects` — project 一覧と ID 解決
- `mcp__linear-mh4gf__list_teams` — team 一覧と ID 解決
- `mcp__linear-mh4gf__list_issues` — 重複検知
- `mcp__linear-mh4gf__save_issue` — 起票

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
- 別ファイル書き出しと writing-plans 起動が起きそうになったら、ユーザー へ確認して スキップ する
- 確認文言: 「create-linear-issue 経由なので design doc 書き出しと writing-plans を スキップ し、議論結果から直接 Linear 起票へ進む」

理由: bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた新規ファイルを bg session 側から読めない。issue body だけが情報源になる前提で組む。

### 2. project と team を解決する

`mcp__linear-mh4gf__list_projects` で project 一覧を取得する。ユーザー が指定した project (または会話の文脈で自明な project) を name で絞り込んで ID を得る。複数該当した時は AskUserQuestion で確定する。

その project の team ID も取得する。project レスポンスに teams が含まれていればそれを使う。含まれない時は `mcp__linear-mh4gf__list_teams` で解決する。

### 3. 重複を検索する

brainstorming で出てきたキーワード (1〜2語) で既存 issue を検索する。

```
mcp__linear-mh4gf__list_issues(query="<keyword>", project="<projectId>")
```

近い既存 issue が出た場合、新規作成せず該当の identifier と URL を ユーザー へ報告して止まる。

### 4. description を組み立てる

brainstorming の議論結果から、次の節構成へ落とす。

- `## Outcome` — 最終状態と価値を箇条書きで 2〜4 点。手順は書かない
- `## Why` — 起票の動機・前例との関係・設計の理由。bg session が edge case で判断するための背景情報
- `## 参考` — 参照した関連ファイル、関連 issue (`XX-NN` 形式、実在のみ)、外部 URL。意図にある外部参照を必ず含める
- `## 完了条件` — 観測可能な状態 (コマンド出力、ファイル存在、Linear / GitHub の見え方) を箇条書き
- `## スコープ外` — 含めない範囲を箇条書き

書き出し先は `.claude/tmp/create-linear-issue-body-<slug>.md`。`<slug>` は intent から派生した短い英数字。

ワーカー判断の余地 (実装時の選択肢) は `## 実装の自由度` として最後に置いてもよい。spec で確定しきれない open question を明示する。

`## 参考` 節へ書いてよいのは、bg session の workspace で存在を保証できる path のみ。例として origin/main へ コミット 済みのファイル、関連 Linear issue (`XX-NN`)、公開 URL。scraps/open/ や .claude/tmp/ のような未 コミット の path は書かない。

### 5. title と label を決める

title はプロジェクトの慣行に合わせ、80 文字以内、prefix なし、要点 1 文で書く。

label は次のいずれかから選ぶ。Symphony が WORKFLOW を route するキー。

- `works` — MH4GF/works repo の vault / agents / scripts / Mac mini hermes 等が対象
- `claude-code` — MH4GF/claude-code repo の user-スコープ skill / hook / plugin / textlint config 等が対象

文脈から自明 (例: 「skills/X に追加して」「daily note の cron が…」) なら自分で決めて宣言する。曖昧なら AskUserQuestion で確定する。label なしでは Symphony が拾わないため必須。

### 6. MCP で起票する

`mcp__linear-mh4gf__save_issue` を呼ぶ。引数:

- `team`: ステップ 2 で解決した team ID
- `project`: ステップ 2 で解決した project ID
- `title`: ステップ 5 で決めた title
- `description`: ステップ 4 で書いたファイルの中身 (`.claude/tmp/create-linear-issue-body-<slug>.md` を Read して渡す)
- `state`: project の Todo 相当 state ID (Symphony の `active_states` と一致させる)
- `labels`: ステップ 5 で選んだ label の配列 (例: `["works"]` または `["claude-code"]`)

戻り値から `identifier` と `url` を取る。

### 7. ユーザー に報告する

ユーザーに 1〜2 行で次を伝える。

- 起票した issue の identifier (verbatim) と URL
- Symphony が次の poll (約30秒以内) で拾うはずである旨

その後は本セッションの元タスクに戻る。

## 設計判断と理由

### 親セッション内で同期実行する

brainstorming と Linear 起票を本セッションで完結させる。別 bg セッションを spawn する価値は薄い。座って起票する場面が大半。bg を挟むと permission prompt 待ちで止まるリスクが増える。

### Linear MCP `linear-mh4gf` に限定する

Linear MCP は claude のグローバル設定で workspace ごとに別 server として登録される。`mcp__linear__*` や `mcp__linear-<other>__*` が別 workspace の key で起動していると、ai-native の起票指示が誤って別 workspace へ届く。本 skill は `mcp__linear-mh4gf__*` の prefix だけ呼び、別 server を混在させない。

### label で workflow を route する

Symphony は同じ Linear project の中で複数の WORKFLOW.md を並列駆動する。route キーは label。`works` 付き issue を works repo の WORKFLOW が拾う。`claude-code` 付き issue を claude-code repo の WORKFLOW が担当する。label なしの issue はどちらの WORKFLOW からも拾われず宙吊り化する。起票時の label 指定を必須化する。

### description を単一ソースにする

bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた別ファイルを参照できない。description には設計の理由と完了条件をまとめて記載する。ワーカーは issue body だけで全体像を取れる。edge case の判断に要る背景情報も description の `## Why` 節へ含める。

## エッジケース

- 意図が複数 issue にまたがる時: brainstorming 内で「1 issue に統合か個別に分けるか」を AskUserQuestion で確認する。分けるときは brainstorming も issue ごとに分けて回す
- 該当 project が `list_projects` に無い時: ユーザー へ「project 名が違うか、`linear-mh4gf` MCP の権限スコープに無い」と報告して止まる
- MCP 呼び出しが認証エラーで失敗した時: `claude mcp` の再認証を ユーザー へ依頼してから止まる。リトライしない
- brainstorming を スキップ したい正当な理由がある時 (= ユーザー が「brainstorming は不要、直接起票して」と明示した時): 例外的に brainstorming を踏まず、ステップ 2 以降のみ実行する。スキップ した事実を 報告に明記する
