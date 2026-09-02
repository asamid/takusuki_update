# Takusuki Update

Takusuki Update v4.0.0は、systemdで運用するMisskeyを安全に更新するための
対話式・非対話式updaterです。Ubuntu上の通常インストールを対象とし、Docker
環境には対応していません。

Live Stagingで検証したexact updaterと、Misskey patch・assetを収録した検証可能な
HTTPS bundleを組み合わせます。通常updateではPostgreSQL backupを自動実行しません。

## 主な機能

- 最新の正式stable releaseへのupdate
- 40件以上の正式tagからの選択
- official `origin/master`への強制reset
- migration-aware rollback
- 独立したPostgreSQL custom-format backup
- HTTPS bundleとSHA-256 sidecarの検証
- ZIP path、symlink、special file、manifest、個別hash/sizeの検証
- network failure時だけのverified cache fallback
- official Misskey remote allowlistとexact commit解決
- isolated worktreeでのpatch compatibility test
- Gallery投稿1件あたりの添付上限を256ファイルへ拡張するTakusuki patch
- target pnpm/Corepack version isolationとCWD非依存実行
- service停止前preflight、bounded readiness、HTTP/API health check
- fail-closed動作とbroad `git clean`の禁止

## 対話UI

引数なしで起動すると次のメニューを表示します。

```text
1. 最新版へアップデート
2. タグから選んでアップデート
3. master へ強制リセット
4. ロールバック
5. DBをバックアップ
0. 終了
```

## インストールと実行

runtime配布の正本は `https://labo.takusuki.com/update3/` です。

```bash
wget https://labo.takusuki.com/update3/takusuki_update3.sh
wget https://labo.takusuki.com/update3/takusuki_update3.sh.sha256
sha256sum -c takusuki_update3.sh.sha256
chmod 0755 takusuki_update3.sh
sudo ./takusuki_update3.sh
```

非対話CLIの例:

```bash
sudo ./takusuki_update3.sh --stable --yes
sudo ./takusuki_update3.sh --tag 2026.7.0 --yes
sudo ./takusuki_update3.sh --master-reset --yes
sudo ./takusuki_update3.sh --rollback
sudo ./takusuki_update3.sh --db-backup --yes
./takusuki_update3.sh --stable --check
./takusuki_update3.sh --tag 2026.7.0 --check-patches
```

actual非対話updateにはrootと`--yes`が必要です。downgradeには追加で
`--allow-downgrade`が必要です。

## Security model

updaterは、official Misskey remoteのallowlist、fetch後のexact commit解決、HTTPS
bundle、SHA-256 sidecar、ZIP traversal防止、重複entry・symlink・special file拒否、
bundle manifestと個別hash/sizeを検証します。isolated official worktreeで全patchの
互換性を確認し、preflightが完了するまでserviceを停止しません。

download済みbundleのintegrity failureではcacheへfallbackせず停止します。cacheは
network failure時だけ利用し、利用前に再検証します。install/build/migration failure後に
壊れたserviceを無条件起動せず、readinessは時間制限付きです。

## Rollbackの制約

rollback前に現在と更新前のmigration ledgerをbyte比較します。異なる場合は
source-only rollbackを拒否します。DB restoreは自動実行しません。

「source rollback可能」と「DB backupからrestore可能」は別の判断です。migrationを
含む復旧は、DB互換性とbackupを人間が確認したうえで別途計画してください。

## PostgreSQL backup

通常updateはDB backupを作成しません。メニュー5または`--db-backup`で明示した場合だけ、
custom-format `pg_dump`を実行します。完成後に`pg_restore --list`、file size、SHA-256、
entry count、PostgreSQL versionを検証・記録し、失敗したpartial dumpは有効backupとして
扱いません。

## Bundle sourceと配布

repositoryの[bundle source](bundle/takusuki-update3-bundle/)から
`scripts/build-bundle.sh`でreproducible ZIPを生成できます。`scripts/verify-release.sh`は
updater、bundle、manifest、secret patternを検証します。

公開runtime artifactは次の4ファイルです。

- `takusuki_update3.sh`
- `takusuki_update3.sh.sha256`
- `takusuki-update3-bundle.zip`
- `takusuki-update3-bundle.zip.sha256`

GitHubはsource、history、review、CIの正本、labo.takusuki.comはupdaterが実行時に参照する
runtime distribution endpointです。PR merge後にGitHub Releaseを作成する場合も、Live
Stagingで検証したexact SHAの4 artifactだけをrelease assetにします。

bundleのTakusuki custom patchには、Galleryのcreate/update API双方で投稿1件あたりの
file上限を32から256へ拡張するpatchが含まれます。DB schema変更はありません。

## Legacy

旧v2系updater、patch、assetは履歴を保つため[legacy](legacy/)へ移動しました。新規運用では
使用しないでください。旧 `.gitignore` は誤ってPython生成コードを含む非UTF-8 fileだったため、
証跡として`legacy/gitignore-corrupted.txt`へ移動し、rootには有効なignore規則を配置しました。

## ライセンス

repository全体がMIT-onlyではありません。

- Takusuki updaterとhelper scripts: [MIT](LICENSE)
- Misskey由来patch: [AGPL-3.0-only](LICENSES/AGPL-3.0-only.txt)
- Takusuki original `unknown.png`: MIT — Copyright (c) 2025-2026 asami

詳細は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)と
[license audit](docs/license-audit.md)を参照してください。

## 検証

```bash
./scripts/verify-release.sh
```

この検証はlocal repository内だけで完結し、Misskey hostへ接続しません。
