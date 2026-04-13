---
description: ツール呼び出しログからハーネス (settings/CLAUDE.md/hooks/scripts) の改善候補を分類・対話適用
argument-hint: "[days, default 14]"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/aggregate-hook-logs.sh:*)"]
---

<task>
ツール呼び出しログを集計し、Claude Code ハーネスの改善候補を分類・提示・対話適用する。
集計スクリプトは事実収集のみ。分類と判断はここで Claude が行う。

ref: https://martinfowler.com/articles/harness-engineering.html
</task>

## Step 1: データ取得

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aggregate-hook-logs.sh" --since ${ARGUMENTS:-14} --format json
```

## Step 2: スキップ判定

以下は改善不要。件数のみカウントして先頭で報告:
- `ask_flow` が `user_allowed / user_denied` のみで、`current_settings.ask_bash_prefixes` にマッチ → 意図的 ask
- `permission_modes == ["plan"]` のみ → plan mode 仕様
- `count < 3` → ノイズ（ただし危険パターンや error は低頻度でも拾う）

## Step 3: 根本原因の分析

IMPORTANT: シグナルから直接アクションに飛ばない。まず「なぜこのパターンが発生しているか」を分析する。

各グループについて、以下を問う:
- **なぜ `user_allowed` が多いのか？** — 本当に allow すべきか、それともそもそも Claude がそのコマンドを使う必要がないのでは？代替ツール（Read, Grep 等）で済むなら CLAUDE.md でガイドする方が正しい
- **なぜ `denied` が繰り返されるのか？** — CLAUDE.md にルールがないのか、あるのに守れていないのか。後者なら表現を変える必要がある
- **なぜ複雑な one-liner が生まれるのか？** — 既存のツールやスキルで代替できないか。スクリプト抽出は最終手段
- **なぜ危険コマンドが通過しているのか？** — permission mode が bypassPermissions だったのか、prefix マッチの抜け穴か

各グループについて根本原因を1行で要約してから Step 4 の分類に進む。

## Step 4: 分類

各グループを以下のカテゴリに分類する（複数該当可 — 例: deny 追加 + CLAUDE.md ルール追加のように、センサーとガイドの二重防御が適切な場合がある）。

<where>
`cwds` の分布で対象ファイルを判定:
- **グローバル** (`~/.claude/settings.json`, `~/.claude/CLAUDE.md`): cwds のユニークなリポジトリルートが 3 以上 or 非リポジトリパス (/tmp 等)
- **プロジェクト** (`<repo>/.claude/settings.local.json`, `<repo>/CLAUDE.md`): cwds の count 合計の 80%+ が 1 リポジトリに集中

IMPORTANT: プロジェクト対応は案内のみ。Claude 自身は cd しない。
</where>

<categories>

### (1) フィードフォワード改善 — ガイドの追加・修正

Claude の行動を事前に操舵するガイドを改善する。

**CLAUDE.md ルール追加**:
- シグナル: 同一 cmd_prefix で `auto_denied` または `user_denied` が繰り返される → Claude が禁止行動を学習できていない
- 例: `git add -A` denied ×5 → 「ファイルを個別に add」/ `cat` 頻発 → 「Read ツールを使え」

### (2) フィードバック改善 — 権限・センサーの調整

権限ルールと hook バリデータを調整する。

**allow 追加** (摩擦削減):
- シグナル: `user_allowed` が多い + `current_settings.allow_bash_prefixes` に該当なし
- pattern が近い既存 allow があれば拡張を提案

**スクリプト抽出 → allow** (摩擦削減):
- シグナル: `example_commands` に 200+ char の one-liner や複合シェル構文 (`&&`, `|`, `for`, `$(...)`) で `user_allowed` が繰り返される
- → `.claude/scripts/<name>.sh` に抽出し `Bash(bash ~/.claude/scripts/<name>.sh*)` で allow

**deny / hook 追加** (センサーギャップ):
- シグナル: `example_commands` に破壊的操作が含まれるが `auto_allowed` で通過
- hook validator の regex 漏れ → 追加提案

**hook validator regex 調整**:
- `user_allowed` 多発 → regex が広すぎて safe な変種を誤検知 → 狭める提案

**unused allow 削除** (衛生):
- `current_settings.allow_bash_prefixes` と groups を突合し、期間内未使用の allow を検出

### (3) エラー hotspot — 決定論的センサーの問題示唆

- シグナル: `error_count >= 3`
- linter / test / build の設定問題の可能性
- 情報提示のみ。Claude は修正しない。

### (4) その他 — 上記に該当しないシグナル

上記3カテゴリに当てはまらないが注目すべきパターンがないか検討し、あれば提示する。
例: 特定の permission_mode に偏った異常な分布、想定外のツールの多用、セッション間で矛盾する挙動など。
新しいカテゴリの追加を示唆する発見があればユーザーに報告する。

</categories>

## Step 5: 提示・適用

提示順序: サマリ → フィードバック改善 → フィードフォワード改善 → プロジェクト案内 → hotspot

カテゴリ毎に `AskUserQuestion` で対話:
- **グローバルファイル** (`~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/scripts/*`): 承認後 Edit/Write
- **プロジェクトファイル**: 実行コマンドとして提示のみ
- **hotspot**: 情報提示のみ

settings.json を編集した場合は `jq empty ~/.claude/settings.json` で検証。変更 1 件以上で `/commit` を呼ぶ。

<constraints>
IMPORTANT: 以下を厳守

- `current_settings.ask_bash_prefixes` にマッチするコマンドを allow に昇格させない
- `Bash(bash -c:*)` のような過剰に広い allow を作らない
- 他リポジトリに cd して編集しない — 案内のみ
- 壊れた settings.json を自動巻き戻さない
- Lint/test config を自動修正しない（提示のみ）
- CLAUDE.md 追記は必ずユーザ承認を得る
</constraints>
