---
name: go-review
description: Go の diff を「設計レベル」だけレビューする skill。狙うのは table-driven test への押し戻し、レイヤ越境疑い (adapter / controller / listener / repository の責務違反)、トランザクション境界 (`defer tx.Rollback()` 漏れ含む)、テストケース名 / コードコメントの言語整合。「go レビューして」「table-driven にして」「なぜ分けている」「listener の責務」「もっとシンプルに (Go)」等で必ず発動する。golangci-lint v2 / depguard / forbidigo / gofumpt / gci がカバーする領域 (import 順 / レイヤ違反 / 固有禁止 API / フォーマット / err 包み忘れ / 未使用変数) は対象外 — 重複指摘は明確に嫌われているので踏み込まない。常に report-only。
---

# go-review

Go の diff から「lint で止められない設計レベル」だけを抽出するレビュー skill。

## 対象範囲

`*.go` の追加・変更が対象。次のような Go プロジェクトを想定する
- `golangci-lint v2` 中心の厳格な lint 運用 (depguard / forbidigo を含む)
- `adapter/controller` / `adapter/listener` / `adapter/repository` のような onion 風レイヤ構成

## 対象外 (lint でカバーされる領域)

レビュー開始前に対象リポの lint / formatter 設定を確認する。これらが既に止める領域は指摘しない。重複指摘は読み手の認知負荷を増やすだけ。

確認すべき設定の例
- linter — `golangci-lint` を中心とした構成 (staticcheck / gosec / revive / govet / errorlint 系)
- フォーマッタ — `gofumpt` / `gci`
- アーキテクチャ制約 — `depguard` で表現されたパッケージ間 import 規約
- 固有禁止 API — `forbidigo` で deny された API 呼び出し
- 文言 — dupword / misspell

リポ次第で lint が止める一般的な領域
- import の並び順 / 未使用 import / 未使用変数
- フォーマット
- 型整合性
- err wrap / err 比較の作法
- レイヤ間 import 違反
- プロジェクト固有の禁止 API 呼び出し

報告前に再確認する。上の項目に該当する指摘は最終レポートから外す。

## 観点

### Table-driven test への押し戻し

次のパターンを挙げる
- sibling test — `TestXxx_A`, `TestXxx_B`, `TestXxx_C` のように同 subject の variation を別関数で書いている
- `t.Run` を 3-5 個ベタ書きで並べているケース — struct slice + ループに集約できないか確認する

折り畳み後の struct はドメインモデルへ揃えた命名にする (実モデル名と乖離する独自命名があれば別観点として挙げる)。

### レイヤ越境疑い

`depguard` は import の方向だけを止める。次は人 / AI 判断
- この型は本当に `adapter/controller` 配下に置くべきか、`domain/` や `usecase/` へ出すべきか
- この関数の置き場として `cmd/` と `dispatch/` のどちらが妥当か
- `repository` の中に business logic が紛れていないか

責務分離を直接問う形で指摘する。例えば「なぜ通常のハンドラと分けているのか」のように、分割の根拠を要求する。

### トランザクション境界

`db.WithTx` 等で囲うべき複数 query が個別になっていないか。`defer tx.Rollback()` の置き忘れ。並行更新が起きる場面のテスト有無 — reproducer の不在はレグレッションを誘う (deadlock / race)。

### テストケース名 / コードコメントの言語整合

テストケース名 (`t.Run("...", ...)` の第 1 引数) とコードコメント (`//` / `/* */`) は、チームの利用言語に揃える。プロジェクトが日本語運用なら日本語、英語運用なら英語にする。次のパターンを挙げる
- 日本語チームに英語のテスト名 / コメントが混入している
- 英語チームに日本語のテスト名 / コメントが混入している

## 報告フォーマット

次のテンプレで出力する。

```markdown
## go-review 指摘事項

対象: <files>

- `path/file.go:42` — 現状: <観察> / 問題: <なぜ良くないか> / 提案: <修正案>
- `path/file.go:80` — ...
```

優先度は付けない。挙げた指摘事項はすべて呼び出し元が対応する前提。該当なしの場合は「指摘事項なし」と書く。でっちあげ禁止。

## 自分の出力に対する自己チェック

報告前に次を確認する
- 対象外リストに該当する指摘を書いていないか (特に depguard / forbidigo の領域)
- 同じ file:line への重複指摘が無いか
- 「あった方が良い」だけの根拠の弱い指摘を挙げていないか
- 報告の語彙が日本語の用語規約 (`prh.yml` 等があれば) に違反していないか
