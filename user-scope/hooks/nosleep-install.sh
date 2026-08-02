#!/bin/bash
# claude-nosleep の root ヘルパーを設置する。マシンごとに 1 度だけ実行する。
#
#   bash user-scope/hooks/nosleep-install.sh
#   bash user-scope/hooks/nosleep-install.sh uninstall
#
# 設置するもの:
#   /usr/local/bin/claude-sleep-guard   root 所有。pmset disablesleep の 0/1 だけを行う
#   /etc/sudoers.d/claude-nosleep       上記だけを NOPASSWD 許可する
#
# hook 側 (nosleep.sh と settings.json) は setup.sh の symlink で配られるので、
# このスクリプトで触るのは root 権限が要る部分だけ。
set -euo pipefail

GUARD=/usr/local/bin/claude-sleep-guard
SUDOERS=/etc/sudoers.d/claude-nosleep
GUARD_DIR="$(dirname "$GUARD")"
ME="$(id -un)"

# NOPASSWD 許可の前提は「ヘルパーを一般ユーザーが差し替えられない」こと。
# ディレクトリに書ければ root 所有ファイルでも unlink して置き換えられるので、
# 置き場とその親の両方が root 所有かつ group/other 書き込み不可であることを確認する。
assert_dir_safe() {
  local dir=$1 owner perms
  owner="$(stat -f %Su "$dir")"
  perms="$(stat -f %Lp "$dir")"
  if [ "$owner" != root ] || [ $((8#$perms & 8#022)) -ne 0 ]; then
    cat >&2 <<EOF
$dir が root 所有かつ group/other 書き込み不可ではありません ($owner $perms)。
このまま sudoers を置くと、一般ユーザー権限のプロセスがヘルパーを差し替えて
パスワード無しで root になれます。中止します。

Homebrew が /usr/local を chown している場合は、置き場を root 所有の別ディレクトリへ
変えてから再実行してください。
EOF
    exit 1
  fi
}

if [ "${1:-install}" = uninstall ]; then
  if [ -x "$GUARD" ]; then
    sudo "$GUARD" off || true
  else
    sudo /usr/bin/pmset -a disablesleep 0 || true
  fi
  sudo rm -f "$GUARD" "$SUDOERS"
  rm -rf "/tmp/claude-nosleep-$(id -u)"
  echo "uninstalled. settings.json の hooks は残るが、ヘルパーが無いので no-op になる。"
  exit 0
fi

assert_dir_safe /usr/local
assert_dir_safe "$GUARD_DIR"

echo "==> sudo が必要です (ヘルパーと sudoers の設置)"
sudo -v

# sudoers でワイルドカードを許すと任意コマンドの root 実行に化けるので、
# 引数を on/off に固定したヘルパーだけを許可対象にする。
sudo tee "$GUARD" >/dev/null <<'GUARD_EOF'
#!/bin/sh
case "$1" in
  on)  exec /usr/bin/pmset -a disablesleep 1 ;;
  off) exec /usr/bin/pmset -a disablesleep 0 ;;
  *)   echo "usage: claude-sleep-guard {on|off}" >&2; exit 64 ;;
esac
GUARD_EOF
sudo chown root:wheel "$GUARD"
sudo chmod 755 "$GUARD"

# 壊れた sudoers を置くと sudo 自体が使えなくなるので、visudo で検証してから配置する
tmp_sudoers="$(mktemp)"
trap 'rm -f "$tmp_sudoers"' EXIT
printf '%s ALL=(root) NOPASSWD: %s\n' "$ME" "$GUARD" > "$tmp_sudoers"
if ! sudo visudo -c -f "$tmp_sudoers" >/dev/null; then
  echo "sudoers の検証に失敗しました。中止します。" >&2
  exit 1
fi
sudo install -m 0440 -o root -g wheel "$tmp_sudoers" "$SUDOERS"

echo "==> 完了。確認: bash user-scope/hooks/nosleep.sh status"
