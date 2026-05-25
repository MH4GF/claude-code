## 機能の概要

ユーザー認証フローを OAuth 2.0 に切り替えた。

## 変更点

- `LoginForm` を削除した
- セッション管理を `iron-session` に置き換えた
- `AuthGuard` のテストを追加した
