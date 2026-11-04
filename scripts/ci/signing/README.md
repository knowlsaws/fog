# 署名証明書の保存場所

`distribution.p12.enc` は CI（`.github/workflows/testflight.yml`）が App Store Connect API で作った
Apple Distribution 証明書と秘密鍵を、`ASC_PRIVATE_KEY`（.p8）の SHA-256 をパスフレーズに AES-256-CBC で暗号化したもの。
CI が自動でコミットする。手で触る必要はない。

- 証明書を作り直したいとき：このディレクトリの `distribution.p12.enc` と `distribution.json` を削除して main に push する
- `ASC_PRIVATE_KEY` を作り直したとき：復号できなくなるので CI が自動で作り直す（古い証明書は `signing-admin` ワークフローで失効させる）
- 証明書の上限（Distribution は 3 枚）で止まったとき：`signing-admin` の `list` で一覧を見て `revoke`
