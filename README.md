# claude-code

MH4GF's Claude Code configuration and plugin marketplace.

This repository hosts both publicly distributed plugins (`.claude-plugins/`) and personal user scope settings (`user-scope/`) symlinked into `~/.claude/`.

## Plugins

- **[tool-use-steering](.claude-plugins/tool-use-steering/)** — Steering loop for Claude Code harness: log tool-use events, aggregate invocations, and AI-driven analysis to continuously improve settings.json, CLAUDE.md, hooks, and scripts.

## User scope config

`user-scope/` contains user scope Claude Code settings (`CLAUDE.md`, `settings.json`, `commands/`, `skills/`, `hooks/`). Run `./setup.sh` to symlink them into `~/.claude/`.

```bash
./setup.sh
```

## textlint AI 文章 lint を有効化する

`user-scope/hooks/textlint-guard.sh` は Write/Edit/MultiEdit 後の `*.md` / `*.mdx` を textlint で検査し、指摘があれば exit 2 で Claude にフィードバックする PostToolUse hook。`@textlint-ja/textlint-rule-preset-ai-writing` と `textlint-rule-preset-ja-technical-writing` を使う。

初回セットアップ:

```bash
cd /Users/mh4gf/ghq/github.com/MH4GF/claude-code
npm install
./node_modules/.bin/textlint -c .textlintrc.json tests/fixtures/textlint-bad.md   # 動作確認: 指摘が出れば OK
```

`node_modules` が無い間は hook が exit 0 でフェイルセーフし stderr にインストールヒントだけ出す。`TEXTLINT_GUARD=off` 環境変数で個別セッションを無効化できる。

ルール選び直し (plan B): ノイズが多いルールは `.textlintrc.json` で個別 disable する。

```json
{
  "rules": {
    "preset-ja-technical-writing": {
      "sentence-length": false,
      "no-doubled-conjunctive-particle-ga": false
    },
    "@textlint-ja/preset-ai-writing": true
  }
}
```

## Development

### Run Tests

```bash
bash tests/test-log-hook.sh      # Logger unit tests (9 cases)
bash tests/test-aggregate.sh     # Aggregation smoke tests (17 cases)
bash tests/test-comment-guard.sh # Comment-guard hook tests (25 cases)
bash tests/test-textlint-guard.sh # textlint-guard hook tests (7 cases, requires `npm install`)
```

## License

MIT
