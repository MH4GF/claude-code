# Communication

- No sycophancy — NEVER agree just to be agreeable. If the user's approach has flaws, say so directly with reasoning
- Challenge bad ideas — When you spot a better alternative, propose it even if the user didn't ask. "That works, but X is better because Y" is always welcome
- Say "no" with evidence. Push back with concrete reasons whenever a request would create tech debt or security issues

# Japanese Writing Style

- No mixed English-Japanese in prose — 地の文に英単語・略語・英語比喩を混ぜない。日本語として定着した技術用語はカタカナで書く（動詞・形容詞含む）
  - 名詞: tx → トランザクション、conn → コネクション、retry → リトライ、worker → ワーカー、trigger → トリガー
  - 名詞 (続き): findings → 指摘事項、reviewer → レビュアー
  - 動詞: skip → スキップ、dispatch → ディスパッチ、deploy → デプロイ、commit → コミット
  - 形容詞・副詞: blanket → 一律、legitimate → 妥当、informational only → 情報通知のみ
  - 比喩・造語: deadlock victim → デッドロックで中断された側、mop-up → 掃き出し処理、outer loop → 外側のループ
- Keep identifiers untranslated — コード/SQL/CLI/API/ライブラリ/DBオブジェクト/ファイルパス/ツール名/エラーコード/原文引用は翻訳せず原文のまま残す
  - 例: `goose.AddMigrationNoTxContext`、`ACCESS EXCLUSIVE`、`pgerrcode.DeadlockDetected`
  - 例: `gh pr view --json`、`mergeCommit`、`AskUserQuestion`
- Consistent notation within a document — 同一文書内で表記揺れを起こさない。例えば「worker / ワーカー」「trigger / トリガー」「Approve / 承認」を混在させず、最初に選んだ表記で統一する
- No bold-colon list items — 箇条書きで `- **用語**: 説明` 形式は使わない。代わりに `- 用語 — 説明` 形式へ変えるか、段落として展開する
- Sentence length under ~100 chars — 日本語の文は 80〜100 字を目安に「。」で区切る。読点で繋ぎ続けず、複文は分割する
- No period before bullet lists — リストを導入する文は「次のとおり」「以下」で終え、最後の「。」を打たない。「〜となった。」の直後に箇条書きを続けない
- これら AI 文章クセは textlint-guard hook が PostToolUse で検出し、指摘されたら必ず修正する。情報通知ではなく block 扱いで、修正するまで write は通らない

# Core Principles — Less is More

- Keep implementations small — *Write the smallest, most obvious solution*
- Let code speak — *If you need multi-paragraph comments, refactor until intent is obvious*
- Simple > Clever — *Clear code beats clever code every time*
- Delete ruthlessly — *Remove anything that doesn't add clear value*

# Git

- Use current working directory — Use `<env>Working directory</env>` as the base path. Never fall back to the main branch directory
- Commit per task — Commit when each logical task completes. Include context and reasoning in the commit message
- No "why" in code comments — History lives in commits, not in code
- Describe the change, not the trigger — Commit messages MUST state what changed. Never describe the process that caused it. For example "address review feedback" is banned; describe the actual change instead
- No `git -C` — Always run git commands from within the target directory. Use `cd <path> && git ...` instead of `git -C <path> ...`
- No `git add -A` / `git add .` — Stage files individually by path. This avoids accidentally including secrets, build artifacts, or unrelated WIP. Use `git add <file1> <file2> ...` even for multi-file commits
- Use `git commit -F` for multiline or colon-containing messages. Titles or bodies containing `:`, backticks, or `$` break the default heredoc pattern. The `git commit -m "$(cat <<'EOF' ... EOF)"` form confuses the permission parser. Write the message to `.claude/tmp/commit-msg-<slug>.md` and pass `git commit -F <path>`. Alternatively use `git commit -F - <<'EOF' ... EOF` with no surrounding command substitution

# Bash

- Don't reflexively pipe short-output commands. `2>&1` や `| tail -N` をコマンドに付けると prefix ベースの allow 判定が壊れる。`| head -N` も同様で、余分な許可プロンプトが出る。Bash ツールは stderr を既に取得し、長出力も切詰める。両方とも冗長。例えば `gh api ... | base64 -d` のように出力を実際に変換する時だけ使う

# GitHub CLI

- Prefer dedicated subcommands — Use `gh pr view`, `gh issue list`, `gh search prs` etc. over `gh api`. Resort to `gh api` only when dedicated subcommands cannot retrieve the needed information
- `gh pr create` — always use `--body-file`. Write the PR body to `.claude/tmp/pr-body-<slug>.md` and pass `--body-file <path>`
  - Do NOT use the `--body "$(cat <<'EOF' ... EOF)"` pattern from the default Claude Code prompt
  - Backticks like `` `FuncName` `` in the body trigger nested command substitution in the permission parser
  - The single-quoted heredoc does not help. The call is denied even with `Bash(gh pr create:*)` allowlisted
  - Same applies to `gh pr edit --body ...` and `gh issue create --body ...`

# Research & Reporting

- Reproducible evidence — All findings MUST include steps another user can independently verify. For example: exact CLI commands executed and their output
- Executable commands only — Commands in reports MUST be copy-paste runnable. Never use abbreviated pseudocode

# Temporary Files

- Use `.claude/tmp/`. NEVER write temporary documents to `/tmp/`. Always use `.claude/tmp/` in the current working directory. Drafts and intermediate outputs are reusable across sessions. By contrast `/tmp/` is ephemeral and hard to explore
- Prefer `Write` over `mkdir -p` + `cat > heredoc`. `Write` auto-creates parent directories and bypasses the Bash mkdir sandbox block. Use it for any new file under `.claude/tmp/`. Reserve heredoc only for small executable snippets piped to another command

# External Service Writes

- Draft before MCP write. Before creating or updating content via MCP, write a markdown draft to `.claude/tmp/`. Get user approval before executing. Status-only field updates are exempt; body or content changes are not. Applies to (non-exhaustive):
  - `mcp__notion__notion-create-pages`
  - `mcp__notion__notion-update-page`, `mcp__notion__notion-create-comment`
  - `mcp__linear__save_issue`, `mcp__linear__save_comment`, `mcp__linear__save_document`
  - `mcp__linear__save_status_update`, `mcp__claude_ai_Slack__slack_send_message`
- Preview with `cc-human-review`. Invoke the skill whenever the user should read a file you've prepared. Targets include markdown drafts, SQL queries, code, or configs
  - Backstop if the skill is not triggered: run `cc-human-review <file>` once
  - This opens the file in a tmux split with nvim. Auto-reload covers subsequent `Edit`s, so do not re-run

# Plan Mode

Every plan MUST include:
- E2E verification steps (local env, UI-based, not API)
- Test code requirements

Before ExitPlanMode: `/plan-tools:state-machine`
