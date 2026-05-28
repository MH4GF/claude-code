---
name: add-prh-dict
description: prh.yml に新しい英→日マッピングを追加したい時、本セッションを止めず別 Claude bg session で追加 → commit → push まで自動実行させる。「prh に追加して」「辞書に追加」「prh.yml に entry 追加」「これも辞書化したい」「これも block するように」等で必ず発動する。本セッションを汚さず fire-and-forget で辞書更新したい場面の専用 skill。
---

# add-prh-dict

`prh.yml` への英→日マッピング追加を、別の Claude bg session に丸投げする skill。本セッションでは tq action を作って即時 ディスパッチ するだけで、実際の Edit / コミット / push は dispatched session が担う。

## なぜ別セッションに投げるか

- 本セッションのコンテキストを乱さない。進行中タスクへ集中したい
- 辞書追加は機械作業なので、本セッションを止める価値がない
- 思いついた瞬間に投げて忘れられる。後でやろうとして忘れるリスクを避ける

## 起動条件

次のような要望が出た時に起動する。

- 「`X` を prh.yml に追加して」
- 「`X` も辞書化したい」
- 「これも prh で block するようにして」
- 会話中に複数の追加候補語が浮上した時 (まとめて 1 action にする)

## 手順

### 1. 追加するエントリを確定する

次の情報を抽出する。

- pattern: 英語の元の語。短い語は word boundary 付き regex を推奨 (例: `/\btx\b/i`)
- expected: 日本語の置換先 (例: `トランザクション`)
- カテゴリ: `prh.yml` 内の section 名 (名詞 / 動詞 / 形容詞・副詞 / 比喩・造語)

情報が不足する場合は AskUserQuestion で確認する。確定情報なしに ディスパッチ しない。dispatched session は本セッションのコンテキストを引き継がないため、後から「やっぱりこう」が効かない。

### 2. tq task と action を作って即時 ディスパッチ する

`tq task create` で新規 task を作り、`tq action create` でその task に紐付ける action を作る。`--after` を付けないと即時 ディスパッチ される。

```bash
TASK_ID=$(tq task create 'prh.yml に <pattern> を追加' --format json | jq -r '.id')

tq action create '<instruction>' \
  --task "$TASK_ID" \
  --title 'prh: <pattern> 追加' \
  --meta '{"mode":"experimental_bg","claude_args":["--permission-mode","auto"]}'
```

mode は `experimental_bg` (bg session として ディスパッチ される)。permission-mode は `auto` で全工程を無人実行させる。

### 3. instruction テンプレート

dispatched session に渡す instruction は self-contained に書く。次のテンプレートを採用する。

````markdown
## Goal

`/Users/mh4gf/ghq/github.com/MH4GF/claude-code/prh.yml` に prh ルールを追加し、textlint で構文確認した上で commit して push する。完了したら tq action done を呼ぶ。

## 追加するエントリ

カテゴリ: <カテゴリ>

- expected: <Japanese>
  pattern: <英語 pattern>

(複数ある場合はリストで列挙)

## 手順

1. `cd /Users/mh4gf/ghq/github.com/MH4GF/claude-code`
2. `git status` で main ブランチかつ clean な状態を確認する。dirty なら他作業を巻き込まないため action を failed にする
3. `prh.yml` を Read して、既存エントリと pattern が重複していないか確認する。重複なら no-op で action done (artifact に "already present")
4. 該当カテゴリ section の末尾に新エントリを追加する
5. `./node_modules/.bin/textlint -c .textlintrc.json --no-color prh.yml` で構文確認する (exit 0)
6. `git add prh.yml`
7. commit message を `.claude/tmp/commit-msg-prh-<slug>.md` に Write する
8. `git commit -F .claude/tmp/commit-msg-prh-<slug>.md`
9. `git pull --rebase origin main` で remote 進行を取り込む
10. `git push origin main`。push 失敗時は rebase 再試行、それでもダメなら failed
11. `tq action done <action_id>` で artifact に commit hash を残す

## commit message template

```
prh: <pattern> → <expected> を追加

<カテゴリ> として <pattern> の混入を block 対象にする。
```
````

### 4. 本セッションのユーザーに報告する

action 作成後、ユーザーに 1〜2 行で次を伝える。

- 作成した action ID
- fire-and-forget で進める旨と、完了確認は `tq action list --task <id>` で見られる旨

その後は本セッションの元タスクに戻る。dispatched session の進行を本セッションで watch しない。

## 設計判断と理由

### task を action ごとに新規作成する

action 1 つに task 1 つで対応関係が明快になる。task list は一時的に膨らむが、`tq:triage` skill で整理できる。共通 task に集約すると複数 action の責任範囲がぼやけて triage しにくい。

### permission-mode を auto にする

辞書追加から push までを無人で完走させるため auto モードを採用する。手順は self-contained で機械的なため、追加で人の判断を挟む余地はない。push 先が個人 repo の main で blast radius は限定的なので、auto モードのリスクは許容できる。

### 本セッションでは prh.yml を一切触らない

dispatched session が単一情報源。本セッションが並行して prh.yml を編集すると、後発の push で衝突する。本セッションは action 作成までで止める。

## エッジケース

- pattern と expected が同一語の言い換え (例: `commit` → `commit`): スキップしてユーザーに「prh で扱う必要がない」と伝える
- 同じ pattern が既存にある場合: dispatched session が手順 3 で検出し、no-op done する
- prh.yml が存在しない: instruction の手順 1〜2 で検出され failed になる
- 本セッションが worktree 内: cwd は instruction 内で main repo を絶対パスで指定済みなので問題なし
