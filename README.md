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

現在この hook は `user-scope/settings.json` の `env.UNSLOP_GUARD: "off"` で一時停止中。再開するにはその 1 行を削除する。

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

## 蓋を閉じてもスリープさせない (nosleep)

`user-scope/hooks/nosleep.sh` は、生きている Claude Code セッションがある間だけ蓋閉じスリープを抑止する hook。長時間の作業をラップトップで走らせたまま蓋を閉じたいとき用。

アイドルスリープの抑止は Claude Code 本体がセッションごとに `caffeinate -i` を張って行っている。しかし蓋閉じ (clamshell) スリープは caffeinate では止まらず、`pmset disablesleep` でしか止まらない。この hook が受け持つのはその 1 点だけ。

### セットアップ

`setup.sh` の symlink で hook 本体と settings.json は配られる。root 権限が要る部分だけ、マシンごとに 1 度実行する。

```bash
bash user-scope/hooks/nosleep-install.sh
```

置くものは 2 つ。`/usr/local/bin/claude-sleep-guard` は root 所有の固定スクリプトで、`pmset disablesleep` の 0/1 以外を実行できない。`/etc/sudoers.d/claude-nosleep` はこのヘルパーに限って NOPASSWD を許可する。

置き場が root 所有でなければ権限昇格の踏み台になる。そのためインストーラは `/usr/local` と `/usr/local/bin` の所有者・mode を検証してから進む。

ヘルパー未設置のマシンで hook は no-op になる。導入したくない端末では上記を実行しない。

### 挙動

SessionStart と Stop で `acquire`、SessionEnd で `release` を呼ぶ。登録されたセッションが 1 つ以上あり、かつ電源条件を満たすときだけ `disablesleep` を 1 にする。

Stop hook は毎ターン走る。電源が抜けたときは、次のターンで解除される。SessionEnd を落としたセッションの残骸も同様に掃除される。

判定には状態ファイルを使わない。`pmset` の実際の値をそのまま読む。再起動やクラッシュで状態が飛んでも復帰できる。

環境変数で調整する。

| 変数 | 既定 | 意味 |
| --- | --- | --- |
| `CLAUDE_NOSLEEP_AC_ONLY` | `1` | AC 電源接続時のみ有効化する。`disablesleep` は電源別に設定できないため、カバンの中でバッテリーを焼かないようスクリプト側で判定する |
| `CLAUDE_NOSLEEP_MIN_BATTERY` | `30` | `AC_ONLY=0` のとき、この残量を下回ったら解除する |
| `CLAUDE_NOSLEEP_STALE_AFTER` | `7200` | transcript がこの秒数更新されないセッションは死んだものとして掃除する |

### 確認と解除

```bash
bash user-scope/hooks/nosleep.sh status   # 登録状況と pmset の現状
bash user-scope/hooks/nosleep.sh off      # 強制解除 (次の Stop hook で再度有効になる)
bash user-scope/hooks/nosleep-install.sh uninstall
```

最後のセッションを SIGKILL やカーネルパニックで失うと `release` は飛ばず、抑止が残ったままになる。次にどれかのセッションが立ち上がった時点で掃除される。それまで待てない場合は `off` を叩く。

定期的な掃除が要る場合は LaunchAgent を足す。空 payload で `nosleep.sh acquire` を叩けばよい。

## Development

### Run Tests

```bash
bash tests/test-log-hook.sh      # Logger unit tests (9 cases)
bash tests/test-aggregate.sh     # Aggregation smoke tests (17 cases)
bash tests/test-comment-guard.sh # Comment-guard hook tests (30 cases)
bash tests/test-nosleep.sh       # nosleep hook tests (17 cases)
```

## License

MIT
