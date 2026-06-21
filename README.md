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

### per-user overlay

公式 Claude Code は user-level の `settings.local.json` を持たない。`permissions.ask` のような環境別に効かせたい設定を user-スコープだけで分岐させるため、`setup.sh` で per-user overlay を merge する仕組みを持つ。

`setup.sh` は `$(id -un)` から実行ユーザー を判定する。`user-scope/settings.<user>.overlay.json` があれば base 設定と deep merge する。merge 結果は `~/.claude/settings.json` へ materialized file として書き出す。merge は `jq -s '.[0] * .[1]'` を使う。overlay が無ければ従来通り symlink する。

現在の overlay 一覧は次のとおり。

- `user-scope/settings.mh4gf.overlay.json` — MacBook interactive 用。`permissions.ask` に `gh pr create` / Linear write / Notion write 等の承認 prompt 対象を入れる
- hermes (Mac mini bg session) は overlay 無し。base の `ask: []` がそのまま使われ、`bypassPermissions` mode の bg session を停滞させない

別ユーザー で利用する場合は `user-scope/settings.<user>.overlay.json` を新規追加して `./setup.sh` を再実行する。

overlay 経路では symlink を貼らず materialized file になる。`user-scope/settings.json` を編集した後は `./setup.sh` を再実行して反映する。

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
bash tests/test-log-hook.sh      # Logger unit tests (9 cases)
bash tests/test-aggregate.sh     # Aggregation smoke tests (17 cases)
bash tests/test-comment-guard.sh # Comment-guard hook tests (30 cases)
```

## License

MIT
