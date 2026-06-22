# claude-code

MH4GF's Claude Code configuration and plugin marketplace.

公開 plugin (`.claude-plugins/`) と個人設定 (`user-scope/`) を併置するリポジトリ。

## Plugins

- `.claude-plugins/tool-use-steering/` — Claude Code harness 向けの steering loop。invocation を集計し AI 分析で `settings.json` / `CLAUDE.md` / hook / script を継続改善する

## ユーザー設定 (`user-scope/`)

`user-scope/` 配下に `CLAUDE.md` / `settings.json` / `commands/` / `skills/` / `hooks/` がある。`./setup.sh` で `~/.claude/` へ symlink する。

```bash
./setup.sh
```

## unslop AI 文章 lint を有効化する

`user-scope/hooks/unslop-guard.sh` は PostToolUse hook。Write/Edit/MultiEdit 後の Markdown を unslop で検査し、違反があれば exit 2 を返す。

[unslop](https://github.com/MH4GF/unslop) は textlintrc 互換の Rust 製 lint binary。`.textlintrc.json` と `prh.yml` をそのまま読む。

初回セットアップ:

```bash
cd ~/ghq/github.com/MH4GF/unslop && cargo build --release
```

binary path は `~/ghq/github.com/MH4GF/unslop/target/release/unslop` を hardcode している。`UNSLOP_BIN` 環境変数で上書きできる。`UNSLOP_GUARD=off` で個別セッションを無効化する。

ノイズが多いルールは `.textlintrc.json` で個別 disable する。

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
bash tests/test-log-hook.sh           # Logger unit tests (9 cases)
bash tests/test-aggregate.sh          # Aggregation smoke tests (17 cases)
bash tests/test-comment-guard.sh      # Comment-guard hook tests (30 cases)
bash tests/test-skill-prose-guard.sh  # Skill-prose-guard hook tests (23 cases)
```

## License

MIT
