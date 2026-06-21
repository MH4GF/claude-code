# Communication

- 媚びない — 同意するためだけに肯定しない。アプローチに欠陥があれば理由付きで率直に指摘する
- 悪い案には反対を出す — より良い代替が見えたら、ユーザーが聞いていなくても提案する。「動くが X の理由で Y のほうが良い」は常に歓迎される
- 「No」は証拠付きで — リクエストが技術負債やセキュリティ問題を生むなら、具体的理由で押し返す

# Japanese Writing Style

- 地の文に英単語を混ぜない — 日本語として定着した技術用語はカタカナで書く（動詞・形容詞含む）
  - 一部例: `tx` → トランザクション、`retry` → リトライ、`outer loop` → 外側のループ
  - 用語マッピングの正は `prh.yml` で、unslop が検出して block する
- 識別子は翻訳しない — コード・SQL・CLI・API・ライブラリ・DB オブジェクト・ファイルパス・ツール名・エラーコード・原文引用を原文のまま残す
  - 例: `goose.AddMigrationNoTxContext`、`ACCESS EXCLUSIVE`、`pgerrcode.DeadlockDetected`
  - 例: `gh pr view --json`、`mergeCommit`、`AskUserQuestion`
- 同一文書内で表記揺れを起こさない — 例えば `worker` / ワーカー、`trigger` / トリガー、`Approve` / 承認を混在させず、最初に選んだ表記で統一する
- bold-colon の箇条書きを使わない — `- **用語**: 説明` 形式は禁止。代わりに `- 用語 — 説明` 形式へ変えるか、段落として展開する
- 文の長さは ~100 字以内に収める — 日本語の文は 80〜100 字を目安に「。」で区切る。読点で繋ぎ続けず、複文は分割する
- リスト導入文末に「。」を打たない — 「次のとおり」「以下」で終え、その直後に箇条書きを置く。「〜となった。」の直後に箇条書きは続けない
- これら AI 文章クセは unslop-guard hook が PostToolUse で検出し、指摘されたら必ず修正する。情報通知ではなく block 扱いで、修正するまで write は通らない
- Claude 独自の略語を作らない — 簡潔さを優先するあまり、文を圧縮しすぎて Claude 以外に復号できない表現を生まない。例えば長い名詞を勝手に頭字語化して以降使う、主語と指示語だけの省略文にする等。簡潔さは説明の冗長を削って実現するもので、語そのものを切り詰めて達成しない

# Core Principles — Less is More

- 実装は小さく保つ — *最小で最も明白な解決策を書く*
- コードに語らせる — *複数段落のコメントが必要なら、意図が明白になるまで refactor する*
- シンプル > 巧妙 — *明快さは巧妙さに常に勝る*
- 容赦なく削る — *明確な価値を加えないものは取り除く*

# Git

- カレントワーキングディレクトリを使う — `<env>Working directory</env>` をベースパスにする。main branch のディレクトリにはフォールバックしない
- タスク単位で `commit` する — 論理的なタスクが完了するたびに `commit` する。文脈と理由を `commit` message に含める
- コードコメントに「なぜ」を書かない — 履歴は `commit` に住んでおり、コード本体には書かない
- 原因ではなく変更を述べる — `commit` message は何が変わったかを述べる。原因となったプロセスは書かない。例えば「レビュー指摘対応」は禁止で、実際の変更内容を述べる
- `git -C` を使わない — `git` コマンドは常に対象ディレクトリの中で実行する。`git -C <path> ...` ではなく `cd <path> && git ...` を使う
- `git add -A` / `git add .` を使わない — ファイルはパスで個別 stage する。secrets やビルド成果物や無関係な WIP の混入を避けるため。複数ファイル時も `git add <file1> <file2> ...` の形にする
- 複数行や `:` を含む `commit` message は `git commit -F` を使う — タイトルや本文に `:`・backtick・`$` が含まれると標準の heredoc パターンが壊れる。`git commit -m "$(cat <<'EOF' ... EOF)"` 形式は permission parser を混乱させる。message は `.claude/tmp/commit-msg-<slug>.md` に書いて `git commit -F <path>` で渡す。または `git commit -F - <<'EOF' ... EOF` をコマンド置換なしで使う

# Bash

- 短い出力のコマンドに反射的に pipe を付けない — `2>&1` や `| tail -N` をコマンドに付けると prefix ベースの allow 判定が壊れる。`| head -N` も同様で、余分な許可プロンプトが出る。Bash ツールは stderr を既に取得し、長出力も切詰める。両方とも冗長。例えば `gh api ... | base64 -d` のように出力を実際に変換する時だけ使う
- ファイルの一部を読むのに `sed -n 'N,Mp'`・`head -N`・`tail -N` を使わない — Read ツールの `offset`/`limit` を使う。行番号付きで返り、permission の摩擦もない。実際にテキストを変換するパイプ処理の時だけ sed を使う
- 検査コマンドを装飾 echo セパレータで連結しない — `echo "=== X ===" && <cmd>; echo "=== Y ===" && <cmd>` のように複数の検査を 1 つの Bash 呼び出しへ束ねない。head トークンが `echo` になり `&&`/`;` 複合のため後続コマンドが prefix-match できず毎回 ask に落ちる。各コマンドを個別のツールコールとして発行する。並列実行でき、各々が auto-allow され、出力も読みやすい

# GitHub CLI

- 専用サブコマンドを優先する — `gh pr view`・`gh issue list`・`gh search prs` 等を `gh api` より先に検討する。`gh api` は専用サブコマンドで取得できない情報に限って使う
- `gh pr create` は `--body-file` を必ず使う。PR body を `.claude/tmp/pr-body-<slug>.md` に書き `--body-file <path>` で渡す
  - 標準 Claude Code prompt の `--body "$(cat <<'EOF' ... EOF)"` 形式は使わない
  - body に `` `FuncName` `` のような backtick が含まれると permission parser がネストしたコマンド置換とみなす
  - single-quoted heredoc でも回避できず、`Bash(gh pr create:*)` を allowlist しても deny される
  - `gh pr edit --body ...` や `gh issue create --body ...` でも同じ問題が起きる

# Research & Reporting

- 再現可能な証拠 — すべての指摘事項に、他のユーザーが独立に検証できる手順を含める。例えば実行した CLI コマンドそのものと出力
- 実行可能なコマンドのみ — レポート内のコマンドはコピーペーストでそのまま動く形にする。省略された擬似コードは使わない
- 外部に出す文は self-contained にする — PR description、Linear issue、Slack、コミット message など他人が読む文が対象。ローカルの plan ファイルや `.claude/tmp/` 配下の draft を「詳細はそちら参照」で済ませない。読み手は手元にそのファイルを持たない前提で、必要な情報を本文に展開する

# Temporary Files

- `.claude/tmp/` を使う — 一時文書を `/tmp/` に書かない。常に作業ディレクトリの `.claude/tmp/` を使う。draft や中間出力はセッション間で再利用できる。対して `/tmp/` は ephemeral で探索しにくい
- `mkdir -p` + `cat > heredoc` より `Write` を優先 — `Write` は親ディレクトリを自動作成し、Bash mkdir の sandbox block を避ける。`.claude/tmp/` 配下の新規ファイルは `Write` で作る。heredoc は別コマンドへ pipe する小さな実行スニペットに限る

# External Service Writes

- MCP 書き込み前に draft を作る — MCP でコンテンツを作成や更新する前に、`.claude/tmp/` に markdown draft を書きユーザー承認を得てから実行する。status だけのフィールド更新は対象外、body やコンテンツ変更は対象。対象 (非網羅):
  - `mcp__notion__notion-create-pages`
  - `mcp__notion__notion-update-page`、`mcp__notion__notion-create-comment`
  - `mcp__linear__save_issue`、`mcp__linear__save_comment`、`mcp__linear__save_document`
  - `mcp__linear__save_status_update`、`mcp__claude_ai_Slack__slack_send_message`
- `cc-human-review` でプレビュー — 用意したファイルをユーザーに読ませたい時は `cc-human-review` skill を必ず使う。対象は markdown draft・SQL クエリ・コード・設定ファイル等
  - skill が起動されなかった場合のバックストップとして `cc-human-review <file>` を 1 回実行する
  - tmux split で nvim が開く。以降の `Edit` は autoread で反映されるので再実行はしない

# Skill 編集

SKILL.md / CLAUDE.md / カスタムコマンドへの増分編集で、本文の散文を肥大化させない指針は以下

- 判定 / 分岐ロジックはコマンド節 (実行可能 snippet) に集約する — 散文で「こう判定する」「失敗時はこうなる」を別途解説しない
- description / 目的 / 手順は最小置換に留める — `squash マージ` を `マージ` に差し替える形で済ませ、新規節を増やさない
- 手順への補足は 1 行に圧縮する — サブステップを増やさず `(snippet はコマンド節)` 形式で本文から参照する
- 差分の経緯解説は `commit` message と PR description に書く — skill 本文には書かない

# Plan Mode

Plan には次の項目が必要

- E2E 検証手順 (local env、UI ベース、API ではなく)
- テストコード要件

ExitPlanMode の前に `/plan-tools:state-machine` を呼ぶ
