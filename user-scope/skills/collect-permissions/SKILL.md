---
description: 全リポジトリの settings.local.json から許可設定を収集し、グローバル設定への追加候補を判定する。追加自体は別 action にディスパッチする
context: fork
allowed-tools: Bash(bash *collect_permissions.sh*), Read(~/.claude/settings.json)
---

候補抽出と分類のみを行う noninteractive スキル。`~/.claude/settings.json` への実追加は `/tq:create-action` で別 action にディスパッチし、人間の承認下で実行する。

## 手順

### 1. 候補抽出

```bash
bash ~/.claude/skills/collect-permissions/scripts/collect_permissions.sh
```

スクリプト出力はフィルタ適用済みの候補リスト。

### 2. 分類

各候補を以下の順で判定:

1. auto memory の除外ルール (`feedback_collect_permissions.md`) に該当 → 除外
2. <review_guidelines> に該当 → 除外
3. 残りは「追加候補」

<review_guidelines>
- `gog`: query 系（`gog auth status` 等）は許可、操作系（`gog gmail thread modify` 等）は除外
- プロジェクト固有 Skill: グローバル追加すべきか判定（基本除外、明らかに汎用な場合のみ追加）
- 引数境界が曖昧で過去収集で「保留」が繰り返される候補（例: `cc-open *`）: 除外し auto memory に追記
</review_guidelines>

### 3. 分岐

**追加候補 0 件** — そのまま終了。`/tq:done` で `outcome: 追加候補なし` を記録するだけ。`/tq:create-action` は呼ばない。

**追加候補 1 件以上** — `/tq:create-action` で settings.json 追加 action をディスパッチ。複数候補は 1 つの action にまとめる。

instruction の形式:

````
~/.claude/settings.json (claude-code リポジトリの user-scope/settings.json) の permissions.allow に以下を追加してください。アルファベット順を維持し、追加後 /commit で claude-code リポジトリにコミット:

- "<entry1>" — <理由>
- "<entry2>" — <理由>
````

### 4. auto memory 更新

既存除外ルールでカバーできない新カテゴリを判断した、もしくは `<review_guidelines>` の「引数境界が曖昧」枠で新たに除外した候補がある場合のみ、`feedback_collect_permissions.md` に追記。判断不要なら更新しない。
