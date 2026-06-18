# pr-completion-guard

Stop hook が「PR が Ready 状態に到達するまでセッションを終わらせない」状態を作る plugin。「コミット → PR Draft → CI green → Ready」までセッションを継続させ、人手の介入対象を merge 判断のみに絞る。merge そのものは plugin の責務外で、人手ゲートとして残す。

## 動作

Stop イベント発火時に次の順で状態判定する。未完了の作業が残っていたら `{decision:"block", reason:"..."}` を stdout へ書き、セッションを継続させる。

| 検知 key | 条件 | reason 内容 |
|---|---|---|
| `uncommitted` | `git status --porcelain` が非空 | 変更をファイル単位でコミットして PR を作る |
| `pr-missing` | PR 0 件 + ahead > 0 | `gh pr create --draft` で draft PR を作成 |
| `ci-fail` | `statusCheckRollup` に FAILURE 等 | `gh pr checks` で失敗内容を確認し修正 |
| `ci-pending` | `statusCheckRollup` に PENDING 等 | `gh pr checks --watch` で完了待ち |
| `mergeable-draft` | `mergeable=MERGEABLE` かつ `isDraft=true` | `gh pr ready` で ready 化 |
| `conflict` | `mergeable=CONFLICTING` | `origin/main` を rebase して解消 |
| `mergeable-unknown` | `mergeable=UNKNOWN` | 再評価を待つ |

次のケースは exit 0 で素通しする

- 現在ブランチが `main` / `master` / `HEAD` / 空文字列
- PR が CLOSED または MERGED 状態
- PR が `mergeable=MERGEABLE` かつ Ready (=人手 merge ゲートへ引き渡す)
- `git rev-parse --git-dir` が失敗 (git repo の外)
- `gh` が無いか 5 秒以内に応答しない

## ループ抑制

同じ理由で連続 push back されないように `(session_id, reason_key)` を `.git/info/pr-completion-guard-last-reason` に書く。次回 Stop で同じ key だったら素通しする。理由が変わったら再 fire する。

## Installation

各 repo の project スコープ (`.claude/settings.json`) で有効化する。Stop hook が PR 操作を扱うため、PR を持つ repo にのみ enable する。ユーザー スコープ (`~/.claude/settings.json`) で一律に有効化すると、PR を作らない探索的セッションでも hook が走るので避ける。

`<repo>/.claude/settings.json` に次を追加する。

```json
{
  "enabledPlugins": {
    "pr-completion-guard@claude-code": true
  }
}
```

marketplace 登録 (`extraKnownMarketplaces.claude-code`) はユーザー スコープ (`~/.claude/settings.json`) 側に置く。各 repo の project スコープ では `enabledPlugins` のみ宣言する。

## 環境変数

| 変数 | 既定 | 説明 |
|---|---|---|
| `PR_GUARD_SKIP` | unset | `1` で hook を全 disable する operator 用 escape hatch |

## 失敗時の挙動

`gh` や `jq` のエラーと timeout はすべて exit 0 で素通しする。Stop hook 経由でセッションを詰まらせない fail-open 設計。
