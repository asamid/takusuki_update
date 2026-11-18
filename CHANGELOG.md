# Changelog

## 5.1.2 - 2026-11-18

- Misskey #18111の暫定パッチ040を追加。両画面でカテゴリを自然順に表示し、未分類を最後に配置
- レビュー済みの本家ソースで040を省略。廃止後も旧040を適用した状態を識別
- Ubuntu/systemdインスタンスの検出、ポート解決、インスタンス別の状態保存に対応
- 通常取得・キャッシュのbundleを同一release IDに限定
- Web公開ツールで既存固定版の上書きを拒否

## 5.1.1 - 2026-11-18

- legacy環境の`host=takusuki.com`を安全に`takusuki.com.service`へ正規化し、直接実行時のpreflight失敗を修正
- 既定bundle URLをupdaterと同じGitHub Releaseの固定assetへ変更し、古いWeb current bundleの混入を防止
- 不正なservice名のfail-closed拒否、v5の配布名、2026.11.0対応は維持

## 5.1.0 - 2026-11-18

- Misskey 2026.11.0以降の起動を公式`node ./scripts/start.mjs`へ切り替えるsystemd drop-in管理を追加
- 対象versionの数値比較、`start.mjs`存在確認、既知ExecStartだけの安全な変換を実装
- `NODE_OPTIONS`、Node CLIメモリoption、既存unitのType/User/WorkingDirectory/Environmentを維持
- 対象`packages/backend/package.json`のNode.js engineを読み、shell/systemd双方でfail-closed検査
- `--check`はsystemd変更予定と検証結果を表示するだけで、unit/service/DBを変更しない
- migration-aware rollbackでv5.1管理drop-inの更新前状態を復元
- 2026.11.0（`dd7b4905d715d2587fa2f2cb6a88ecac8878ef0d`）へ4 patchの連続適用を確認

## 5.0.0 - 2026-10-25

- bundleのMisskey version/commit固定拒否を廃止し、互換性参照情報へ変更
- 参照外の公式tagにも001/010/020/030を厳密な順序で事前検査・適用
- `--vanilla --tag VERSION`と対話メニュー6を追加
- Vanilla更新でmanaged patch/assetを公式状態へ戻し、設定・DB・Redis・untrackedを保護
- 現在HEAD基準のpatch prefix分類により、パッチ済み旧versionから新versionへの更新へ対応
- metadataへPATCHED/VANILLA、target commit、参照一致／未検証状態を記録
- format 1 bundle読取互換、format 2 manifest、v5配布名、v4固定URL維持を実装

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
