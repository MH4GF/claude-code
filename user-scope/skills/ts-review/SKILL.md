---
name: ts-review
description: TypeScript / TSX の diff を「設計レベル」だけレビューする skill。狙うのは any / 強制キャストの排除、try/catch の構造見直し (スコープ過大 / 握り潰し)、React Hook の state shape、AI 生成コメント混入、テストケース名 / コードコメントの言語整合。「ts レビューして」「TS の any 消して」「state の持ち方おかしい」「try/catch 広すぎる」等で必ず発動する。lint / formatter / tsc が止める領域 (import 順 / kebab-case / Hook 依存配列 / 未使用変数 / 型エラー) は対象外 — 重複指摘は明確に嫌われているので踏み込まない。常に report-only。
---

# ts-review

TypeScript / TSX の diff から「lint で止められない設計レベル」だけを抽出するレビュー skill。

## 対象範囲

主な種類は次のとおり
- フロントエンド — Next.js / React / Vite / Tailwind / Vitest / Storybook 系
- バックエンド — Hono / Next.js API / Prisma 系

両方の変更が混在する diff は順に両方を見る。共通観点 → フロントエンド固有 → バックエンド固有の順で出力する。

## 対象外 (lint でカバーされる領域)

レビュー開始前に対象リポの lint / formatter / 型チェッカ設定を確認する。これらが既に止める領域は指摘しない。重複指摘は読み手の認知負荷を増やすだけ。

確認すべき設定の例
- linter — biome / eslint (`flat config` 含む)、有効化された rule
- formatter — prettier / biome formatter
- 型チェック — `tsc --noEmit` の CI 連携、`noUncheckedIndexedAccess` 等の strict オプション
- `pre-commit` hook — lefthook / husky / lint-staged の対象

リポ次第で lint が止める一般的な領域
- import の並び順 / 未使用 import / 未使用変数
- フォーマット (空白 / 改行 / quote)
- React Hook の依存配列の漏れ
- ファイル名規約 (kebab-case 強制等)
- 型エラー
- console.log / debugger の混入
- パッケージ境界 (`import-access` / `useImportRestrictions` 系)
- 一般的な a11y (`eslint-plugin-jsx-a11y` の領域)

報告前に再確認する。上の項目に該当する指摘は最終レポートから外す。

## 共通観点

### `any` / 強制キャストの排除

`any` / `as any` / `as unknown as X` / `// @ts-ignore` / `// @ts-expect-error` は原則禁止。95% のケースは型で表現可能。本当に解消手段が尽きた時の最後の手段としてのみ許される。

レビュアーとして、diff に現れた強制キャストを 1 件も見逃さず列挙する。「なぜキャストが必要だったのか」を呼び出し元へ問い直す。型で解消する道が残っていないか再検討させる。「対応が難しい」という理由で指摘を見送らない。

型で解消する典型パターン (呼び出し元への参考)
- 外部 API レスポンスの型が無いケース — Zod schema で受ければ unknown を排除できる
- ジェネリクスの推論が効かないケース — 型引数を明示すればキャストは不要になる

### try/catch の構造見直し

try/catch の構造は必ず疑う。次の 2 パターンを挙げる。

- スコープ過大 — 関数全体や複数文を 1 つの try/catch で囲っている。どの行でどんなエラーが出るのか読み取れない構造はそれ自体が問題。発生行に絞った狭いスコープで囲う形へ見直すべき
- 握り潰し — catch ブロックが空 / 無関係処理 / ログ出力だけ。信頼できる内部呼び出しに対する防御的 try/catch も同類

ライブラリ呼び出し / HTTP 境界 / DB / ファイル I/O など try/catch が本当に必要な場面でも、対象はエラー発生行のみに絞る。「とりあえず広く囲んでおく」を見過ごさない。

### Hook の state shape

React の `useState` / `useReducer` で次のパターンを見る
- 同期取れない複数 state — A の更新後に B を更新しないと矛盾する設計
- 派生値を state にしている — `useMemo` で済む値を `useState` で持っている
- 過剰な Optional Chaining `a?.b?.c?.d` を要求する state 設計

「データの持ち方が変だ」と感じる場面に直接対応する観点。state の置き場所そのものを問い直す。

### コメント混入

既存 PR に AI 生成コメントが残っている場合、`// This function does X` 系の説明コメント、経緯コメント、TODO / FIXME / issue ID コメントを挙げる。

### テストケース名 / コードコメントの言語整合

テストケース名 (`describe` / `it` の文字列) とコードコメント (`//` / `/* */`) は、チームの利用言語に揃える。プロジェクトが日本語運用なら日本語、英語運用なら英語にする。次のパターンを挙げる
- 日本語チームに英語のテスト名 / コメントが混入している
- 英語チームに日本語のテスト名 / コメントが混入している

## 報告フォーマット

次のテンプレで出力する。

```markdown
## ts-review 指摘事項

対象: <files>

- `path/file.ts:42` — 現状: <観察> / 問題: <なぜ良くないか> / 提案: <修正案>
- `path/file.ts:80` — ...
```

優先度は付けない。挙げた指摘事項はすべて呼び出し元が対応する前提。該当なしの場合は「指摘事項なし」と書く。でっちあげ禁止。

## 自分の出力に対する自己チェック

報告前に次を確認する
- 対象外リストに該当する指摘を書いていないか
- 同じ file:line への重複指摘が無いか
- 「あった方が良い」だけの根拠の弱い指摘を挙げていないか
- 報告の語彙が日本語の用語規約 (`prh.yml` 等があれば) に違反していないか
