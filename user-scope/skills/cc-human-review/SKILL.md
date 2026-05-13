---
name: cc-human-review
description: MUST use whenever Claude wants the user to read or review a file it has prepared or modified — markdown reports / plan files / design docs / summaries, drafts before MCP writes (Notion / Slack / Linear / Gmail drafts / Obsidian), SQL queries, code files, config files, or any text file that needs human eyes before the next step. Opens the file(s) in a tmux split pane with nvim so the user reviews while Claude continues editing.
allowed-tools:
  - Bash(cc-human-review:*)
---

# cc-human-review

Claude が用意したファイルを tmux 分割ペインの nvim でユーザーにプレビューさせる汎用レビューツール。nvim で開けるテキストファイルなら何でも対象になる。

## 発動局面

ユーザーに読ませたいファイルが手元にできた時に呼ぶ。代表例:

- markdown: 調査レポート / plan file / design doc / summary / MCP 書き込み前のドラフト (Notion / Slack / Linear / Gmail / Obsidian)
- SQL: クエリレビュー、マイグレーション確認
- コードファイル: 生成・修正したコードのレビュー依頼
- 設定ファイル (YAML / TOML / JSON 等)
- その他、ユーザーに見せて承認・確認を取りたい任意のテキストファイル

「ファイルを書いたから読んで」と言葉で渡すだけで済ませず、必ずこの skill 経由で nvim プレビューを立ち上げる。

## 実行フロー

1. **ファイル準備**: 対象ファイルを `.claude/tmp/<slug>.<ext>` 等に Write/Edit ツールで書く (`/tmp/` は禁止、parent dir は Write が自動作成)。既存ファイルをレビューさせる場合はこのステップ不要。
2. **プレビュー起動**: `cc-human-review <path>` を Bash で **1 回だけ** 実行する。tmux split pane が右側に出て nvim が開く。複数ファイルを並べる場合は `cc-human-review a.md b.sql` のように渡すと nvim タブで開く。
3. **編集ループ**: ユーザーのフィードバックに応じて Edit ツールでファイルを更新する。nvim は autoread で外部変更を検知して自動再読み込みするので、`cc-human-review` の再実行は不要。
4. **承認後**: 用途に応じた次アクション (MCP 書き込み実行 / plan 承認 / レポート受領で完了 / コード適用 等) はユーザー判断に従う。skill 本体はプレビュー起動までが責務。

## 前提

- tmux セッション内で動作する (script は `$TMUX` を要求し、無ければ exit 1)。
- nvim の `autoread` が有効である必要がある (ユーザー環境前提)。
