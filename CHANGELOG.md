# Changelog

## Runtime bundle update — 2026-09-03

- Gallery create/updateの1投稿あたりfile上限を32から256へ拡張
- `020-gallery-file-limit-256.patch`をmanaged patch seriesへ追加
- deterministic bundle SHA-256:
  `f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5`
- Misskey 2026.7.0 Productionへsame-version deployment
- install、build、migration、service、health: PASS
- DB migrationなし、pending migration 0

## 4.0.0 - 2026-08-16

- 日本語の対話UI
- latest stable release modeとstable tag selector
- official `origin/master`への強確認付きreset
- migration-aware rollbackと履歴保存
- 独立したPostgreSQL custom-format backup
- HTTPS patch/asset bundle distribution
- sidecar SHA-256、ZIP、manifest、個別file hash/size検証
- network failure時だけのverified cache fallback
- caller CWD非依存のMisskey user command実行
- isolated target worktreeでのpnpm/Corepack version検証
- service停止前preflightとfail-closed behavior
- bounded startup readinessとHTTP/API health check
- EXP-003 federation chart blocked-host query patch

## Legacy

旧`takusuki_update.sh`は`legacy/takusuki_update2.sh`へ移動しました。Git historyは保持しています。
