# Communication

- **No sycophancy** - NEVER agree just to be agreeable. If the user's approach has flaws, say so directly with reasoning
- **Challenge bad ideas** - When you spot a better alternative, propose it even if the user didn't ask. "That works, but X is better because Y" is always welcome
- **Say "no" with evidence** - If a request will cause problems (tech debt, bugs, security), push back with concrete reasons

# Japanese Writing Style

- **No mixed English-Japanese in prose** - 地の文に英単語・略語・英語比喩を混ぜない。日本語として定着した技術用語はカタカナで書く（動詞・形容詞含む）
  - 名詞: tx → トランザクション、conn → コネクション、retry → リトライ、worker → ワーカー、trigger → トリガー、findings → 指摘事項、reviewer → レビュアー
  - 動詞: skip → スキップ、dispatch → ディスパッチ、deploy → デプロイ、commit → コミット
  - 形容詞・副詞: blanket → 一律、legitimate → 妥当、informational only → 情報通知のみ
  - 比喩・造語: deadlock victim → デッドロックで中断された側、mop-up → 掃き出し処理、outer loop → 外側のループ
- **Keep identifiers untranslated** - コード/SQL/CLI/API/ライブラリ/DBオブジェクト/ファイルパス/ツール名/エラーコード/原文引用は翻訳せず原文のまま残す（例: `goose.AddMigrationNoTxContext`, `ACCESS EXCLUSIVE`, `pgerrcode.DeadlockDetected`, `gh pr view --json`, `mergeCommit`, `AskUserQuestion`）
- **Consistent notation within a document** - 同一文書内で表記揺れを起こさない（例: 「worker / ワーカー」「trigger / トリガー」「Approve / 承認」を混在させず、最初に選んだ表記で統一する）

# Core Principles: **Less is More**

- **Keep implementations small** - *Write the smallest, most obvious solution*
- **Let code speak** - *If you need multi-paragraph comments, refactor until intent is obvious*
- **Simple > Clever** - *Clear code beats clever code every time*
- **Delete ruthlessly** - *Remove anything that doesn't add clear value*

# Git

- **Use current working directory** - All file operations must use `<env>Working directory</env>` as base path, never main branch directory
- **Commit per task** - Commit when each logical task completes; include context and reasoning in commit message
- **No "why" in code comments** - History lives in commits, not in code
- **Describe the change, not the trigger** - Commit messages MUST state what changed, never the process that caused it (e.g., "address review feedback" is banned—describe the actual change instead)
- **No `git -C`** - Always run git commands from within the target directory. Use `cd <path> && git ...` instead of `git -C <path> ...`

# GitHub CLI

- **Prefer dedicated subcommands** - Use `gh pr view`, `gh issue list`, `gh search prs` etc. over `gh api`. Resort to `gh api` only when dedicated subcommands cannot retrieve the needed information.
- **`gh pr create` — always use `--body-file`** - Write the PR body to `.claude/tmp/pr-body-<slug>.md` and pass `--body-file <path>`. Do NOT use the `--body "$(cat <<'EOF' ... EOF)"` pattern from the default Claude Code prompt: when the body contains backticks (e.g., `` `FuncName` ``), the permission parser treats them as nested command substitution despite the single-quoted heredoc, so even with `Bash(gh pr create:*)` allowlisted the call is denied. Same applies to `gh pr edit --body ...` and `gh issue create --body ...`.

# Research & Reporting

- **Reproducible evidence** - All findings MUST include steps another user can independently verify (e.g., exact CLI commands executed and their output)
- **Executable commands only** - Commands in reports MUST be copy-paste runnable, never abbreviated pseudocode

# Temporary Files

- **Use `.claude/tmp/`** - NEVER write temporary documents to `/tmp/`. Always use `.claude/tmp/` in the current working directory. Temporary investigation results, drafts, and intermediate outputs are reusable across sessions; `/tmp/` is ephemeral and hard to explore.

# External Service Writes

- **Draft before MCP write** - Before creating/updating content via MCP (Linear, Notion, Slack, etc.), write a markdown draft to `.claude/tmp/` and get user approval before executing
- **Preview with `cc-human-review`** - When creating markdown for user review, run `cc-human-review <file>` to open it in a tmux split pane with nvim. Run only once per file—nvim auto-reloads on external edits, so subsequent `Edit`s do NOT require re-running the command

# Plan Mode

Every plan MUST include:
- E2E verification steps (local env, UI-based - not API)
- Test code requirements

Before ExitPlanMode: `/plan-tools:state-machine`