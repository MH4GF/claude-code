---
name: create-linear-issue
description: Linear issue を本セッション内で起票する。事前に superpowers:brainstorming で意図を固めてから、同梱の shell wrapper で書き込む。「これも issue にして」「あとで Symphony に拾わせたい」「Linear に追加して」「フォローアップを issue 化」等で必ず発動する。同梱 wrapper 経由のみで Linear MCP は使わない。
required_environment_variables:
  - LINEAR_API_KEY
---

# create-linear-issue

ユーザーの一行の意図を、`superpowers:brainstorming` で固めてから Linear issue として起票する skill。issue body は brainstorming の議論結果から直接組み立てる。`scripts/linear-issue.sh` (同梱) が Linear GraphQL を叩く。Linear MCP は使わない (workspace 越境事故の手当て、および スコープ を明示する目的)。

Symphony 系の運用へ乗せる前提で、起票先は Linear workspace の project と1対1に対応する。Symphony が次の poll で拾うことを期待する。

## 起動条件

次のような要望が出た時に起動する。

- 「`X` を issue にして」「Linear に `X` 追加して」
- 「これも Symphony に拾わせたい」
- 「フォローアップ issue を立てて」
- 会話中に複数の起票候補が浮上した時 (まとめて作るか個別に作るかは brainstorming 内の AskUserQuestion で確認)

## なぜ brainstorming を必須にするか

brainstorming skill の哲学に従う。「simple な issue こそ未検証の前提が無駄な実装を生む」。issue の Outcome / Why / 完了条件 を曖昧なまま起票すると、Symphony が拾った後の実装ワーカーは推測で動く羽目になる。brainstorming で意図を固めれば、その議論結果が issue body の素材になる。

実体験として、brainstorming を踏むと次の収穫がある。

- 「全部やる」か「初期スコープを絞る」かを意識的に選ばせられる
- 似た先行事例 (zenigame / 過去 issue 等) との対比で前提を引き出せる
- 完了条件を具体的なコマンドや観測可能な状態の形へ落とせる

## 同梱の shell wrapper

このスキルディレクトリの `scripts/linear-issue.sh` を呼ぶ。

機能:

- `list-projects` — 設定された project key 一覧 + default
- `default-project` — default project key を返す
- `search --project <key> --query <text> [--limit N]` — 重複検知
- `create --project <key> --title <text> --description-file <path>` — 起票

Linear API key を env `LINEAR_API_KEY` から読む。key は **発行された Linear workspace でしか有効でない**。wrapper は config 上の project_id を信じて投げてよい。別 workspace へ届く可能性は無い。

## config (workspace 固有値)

`~/.config/create-linear-issue/config.json` に置く。public なこの skill repo には置かない。

schema:

```json
{
  "default_project": "<key>",
  "projects": {
    "<key>": {
      "team_id": "<uuid>",
      "project_id": "<uuid>",
      "default_state_id": "<uuid>"
    }
  }
}
```

参考 example: `templates/config.example.json` (UUID は dummy)。

config が無い時は初期化を ユーザー に促してから skill を実行する。Linear UI で project/state を作成し、各 ID を Linear GraphQL の `teams` / `projects` / `workflowStates` query で取得して config に書く。

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

### 2. project を解決する

`!bash <skill_dir>/scripts/linear-issue.sh list-projects` で project 一覧を表示できる。

ユーザー が project を指定しなければ `!bash <skill_dir>/scripts/linear-issue.sh default-project` の値を採用する。指定があれば list に存在することを確認する。存在しない場合は AskUserQuestion で再確認する。

### 3. 重複を検索する

brainstorming で出てきたキーワード (1〜2語) で既存 issue を検索する。

```bash
<skill_dir>/scripts/linear-issue.sh search --project <key> --query "<keyword>"
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

### 5. description の lint を通す

書いた description を unslop で当てて、違反が無くなるまで自動修正する。textlintrc は claude-code repo の `.textlintrc.json` を使う。違反が残ったまま wrapper を呼ばない。

### 6. title を決める

プロジェクトの慣行に合わせ、80 文字以内、prefix なし、要点 1 文で書く。

### 7. wrapper で起票する

```bash
<skill_dir>/scripts/linear-issue.sh create \
  --project <key> \
  --title "<title>" \
  --description-file .claude/tmp/create-linear-issue-body-<slug>.md
```

戻り値 JSON から `issue.identifier` と `issue.url` を取る。

### 8. ユーザー に報告する

ユーザーに 1〜2 行で次を伝える。

- 起票した issue の identifier (verbatim) と URL
- Symphony が次の poll (約30秒以内) で拾うはずである旨

その後は本セッションの元タスクに戻る。

## 設計判断と理由

### brainstorming を必須にする

過去、意図を曖昧に放置したまま起票した issue で、後から「もう少し スコープ を絞っておくべき」「先行事例を引いておくべき」と振り返る事故を起こした。brainstorming の小さなオーバーヘッドを払えば、Symphony に拾われた後の実装ワーカーは手戻りなく動ける。

### 親セッション内で同期実行する

brainstorming と Linear 起票を本セッションで完結させる。別 bg セッションを spawn する価値は薄い。座って起票する場面が大半。bg を挟むと permission prompt 待ちで止まるリスクが増える。

### Linear MCP を使わない

Linear MCP は claude のグローバル設定で workspace ごとに別 server として接続される。`mcp__linear__*` が別 workspace (例えば immedio) の key で起動していると、ai-native の起票指示が誤って immedio へ届く。Wrapper は LINEAR_API_KEY だけを使う。key を workspace に閉じる仕組みなので、スコープ を渡すバグが起きない。

### config を skill repo に置かない

claude-code repo は public。team_id / project_id / workspace url 自体は機密でないものの、漏らす理由も無い。`~/.config/create-linear-issue/config.json` で local に閉じる。

### 識別子は wrapper の戻り値しか信じない

過去、identifier を URL slug や workspace 名から推論して `MH4-XX` のような誤った形を生成した事故が起きた。wrapper の `issueCreate` が返す `issue.identifier` を verbatim で出す方法だけ正しい。

### description を単一ソースにする

bg session の作業 workspace は origin/main の depth=1 clone なので、scraps/open/ 等へ書いた別ファイルを参照できない。description には設計の理由と完了条件をまとめて記載する。ワーカーは issue body だけで全体像を取れる。edge case の判断に要る背景情報も description の `## Why` 節へ含める。

過去は design doc を別ファイルとして scraps/open/ に書き永続化する設計だった。bg session 側で読めない問題と、二重持ちの保守コストを理由に、現在は description 単一ソースへ統合している。

## エッジケース

- 意図が複数 issue にまたがる時: brainstorming 内で「1 issue に統合か個別に分けるか」を AskUserQuestion で確認する。分けるときは brainstorming も issue ごとに分けて回す
- 起票先 project が config に無い時: ユーザー に `~/.config/create-linear-issue/config.json` への追加を依頼してから起票する
- wrapper が exit 4 (Linear API error) を返した時: stderr の GraphQL エラー本文を ユーザー へ報告して止まる。リトライしない
- description の unslop 違反が残る時: 修正できなければ起票せず、現状の違反内容を ユーザー へ報告して止まる
- brainstorming を スキップ したい正当な理由がある時 (= ユーザー が「brainstorming は不要、直接起票して」と明示した時): 例外的に brainstorming を踏まず、ステップ 2 以降のみ実行する。スキップ した事実を 報告に明記する
