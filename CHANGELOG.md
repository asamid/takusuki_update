# Changelog

## Unreleased

- 2026.10.0＋001/010/020/030のProduction適用後を読み取り専用で観測し、実ログ上の
  Note検索SQL縮小、API、timeout、CPU、parallel worker、連合block状態と残存課題を記録。
- 030のblocked-host解除・追加・再解除・再追加、subdomain、reply/renote、設定復元、
  任意のsystemd無再起動確認を将来更新でも再実行できる回帰スクリプトとして追加。
- v4.1.0の固定Web領域と通常4 URLを原子切替で公開し、Cloudflare purge後の再取得、
  SHA-256、ZIP/manifest、標準URL経路のStaging preflightを検証。

## 4.1.0 - 2026-10-25

- 公式stable tagへのmanaged patch互換性、migration差分、frozen build、対象テスト、
  API証拠をfail-closedで判定し、JSON/Markdownを生成する検証スクリプトを追加。
- `030-note-blocked-host-query-optimization.patch`をmanaged patch seriesへ追加
- 3,471 blocked hostsのNote SQLを約156KB/20,826 bindから約1.3KB/2 bindへ縮小
- 合成Stagingの中央値: 6,222.0msから32.2ms、結果集合差分0
- Misskey 2026.9.0および2026.10.0への001/010/020/030連続適用: PASS
- DB schema/migration変更なし
- bundleへ対象Misskey 2026.10.0と公式commitを固定
- 既知patch prefix、全適用済み、未知source差分を停止前に分類
- Ubuntu/systemd/source/Node/pnpm/PostgreSQL/PGroonga/Redis/migration/diskを自動検出・検証
- 4ファイルのRelease生成とWeb固定領域・原子切替scriptを追加
- Production: このrelease作業では未反映

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
