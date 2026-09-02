# Takusuki Update

Takusuki Updateは、Takusuki（takusuki.com）でsystemd運用するMisskeyを安全かつ
再現可能に更新し、Takusuki固有patchを適用するためのupdaterです。fail-closed
preflight、patch compatibility test、検証済みruntime bundle、migration-aware
rollbackを提供します。

Ubuntu上の通常インストールを対象とし、Docker版Misskeyには対応していません。
通常updateではPostgreSQL backupを自動実行しません。

## Current Production Status

- Misskey: `2026.7.0`
- Updater: `Takusuki Update v4.0.0`
- Production deployment: `PASS`
- Last Gallery patch deployment: `2026-09-03`
- Gallery files per post: `256`
- Current managed patch series: `001 / 010 / 020`

Gallery 256はMisskeyのversionを変更しないsame-version deploymentとしてProductionへ
適用され、install、build、migration、service、healthの検証を通過しました。DB migrationは
なく、pending migrationは0でした。詳細は
[Production validation report](reports/gallery-256-production-validation.md)を参照してください。

## 主な機能

- 最新の正式stable releaseへのupdate
- 40件以上の正式tagからの選択
- official `origin/master`への強制reset
- migration-aware rollbackと履歴保存
- 独立したPostgreSQL custom-format backup
- HTTPS bundleとSHA-256 sidecarの検証
- ZIP path、symlink、special file、manifest、個別hash/sizeの検証
- network failure時だけのverified cache fallback
- official Misskey remote allowlistとexact commit解決
- isolated worktreeでのpatch compatibility test
- target pnpm/Corepack version isolationとCWD非依存実行
- service停止前preflight、bounded readiness、HTTP/API health check
- fail-closed動作とbroad `git clean`の禁止

## Managed patches

| ID | Patch | Purpose | Production |
| --- | --- | --- | --- |
| 001 | `001-max-note-text-length.patch` | ノート文字数上限を5000へ変更 | Applied |
| 010 | `010-exp003-federation-chart-blocked-host.patch` | FederationChart blocked-host照合を高速化 | Applied |
| 020 | `020-gallery-file-limit-256.patch` | Gallery添付上限を32から256へ拡張 | Applied |

適用順序と各patchのSHA-256は
[`series`](bundle/takusuki-update3-bundle/misskey-patches/series)および
[`patch-manifest.tsv`](bundle/takusuki-update3-bundle/misskey-patches/patch-manifest.tsv)
で管理します。

## Gallery 256

Gallery投稿1件あたりのfile attachment上限を、Misskey標準の32から256へ拡張しています。
変更対象はGallery create/update APIの双方で、DB schema変更やmigrationはありません。
Productionへは2026-09-03に適用済みです。

StagingのAPI boundary検証結果:

| File count | Create | Update |
| ---: | --- | --- |
| 1 | ACCEPT | ACCEPT |
| 32 | ACCEPT | ACCEPT |
| 33 | ACCEPT | ACCEPT |
| 256 | ACCEPT | ACCEPT |
| 257 | REJECT | REJECT |

Stagingの機能検証はPASSしましたが、Productionとobject storageを共有していたためisolationは
FAILでした。追加のisolation再試験は運用者がwaiveし、その後exact accepted artifactが
Production検証を通過しました。この経緯は
[Staging validation report](reports/gallery-256-staging-validation.md)と
[release report](reports/gallery-256-release.md)に保持しています。

## Quick Start

通常運用ではruntime配布元からupdater本体とsidecarを取得します。bundleは実行時に
`https://labo.takusuki.com/update3/`から自動取得され、SHA-256とmanifestが検証されます。

```bash
cd /home/asami
wget https://labo.takusuki.com/update3/takusuki_update3.sh
wget https://labo.takusuki.com/update3/takusuki_update3.sh.sha256
sha256sum -c takusuki_update3.sh.sha256
chmod 0755 takusuki_update3.sh
sudo ./takusuki_update3.sh
```

GitHubから取得する場合、HTMLの`blob/main` URLではなくraw URLを使用します。`main`は
moving targetです。

```bash
cd /home/asami
curl -fL \
  https://raw.githubusercontent.com/asamid/takusuki_update/main/takusuki_update3.sh \
  -o takusuki_update3.sh
chmod 0755 takusuki_update3.sh
```

Gallery 256で検証済みのsource commitへ厳密に固定する場合:

```bash
curl -fL \
  https://raw.githubusercontent.com/asamid/takusuki_update/d670118d4f5085fc189b59d6e36914d099b0b481/takusuki_update3.sh \
  -o takusuki_update3.sh
printf '%s  %s\n' \
  a121db5ab1ef3d834f8cf3f49909318b3a6736eb3e0dc608acca7a6c71a9aa5f \
  takusuki_update3.sh | sha256sum -c -
```

## 安全な事前確認

特定versionへのProduction更新では、patch-only check、full read-only preflight、actualの順に
実行します。

```bash
sudo ./takusuki_update3.sh --tag 2026.7.0 --check-patches
sudo ./takusuki_update3.sh --tag 2026.7.0 --check
sudo ./takusuki_update3.sh --tag 2026.7.0 --yes
```

- `--check-patches`: official targetに対するpatch compatibilityだけを確認
- `--check`: bundle、環境、service、healthを含むread-only preflight
- actual update: root権限と明示的な`--yes`が必要

意図しないversion upgradeを避ける場合は`--stable`ではなく`--tag`で対象を固定します。

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

その他の非対話CLI:

```bash
sudo ./takusuki_update3.sh --stable --yes
sudo ./takusuki_update3.sh --master-reset --yes
sudo ./takusuki_update3.sh --rollback
sudo ./takusuki_update3.sh --db-backup --yes
```

downgradeには追加で`--allow-downgrade`が必要です。

## Runtime distribution

GitHubはsource、history、review、CIの正本です。
`https://labo.takusuki.com/update3/`はupdaterが実行時に参照するruntime distributionの
正本です。

公開runtime artifact:

- `takusuki_update3.sh`
- `takusuki_update3.sh.sha256`
- `takusuki-update3-bundle.zip`
- `takusuki-update3-bundle.zip.sha256`

Gallery 256のaccepted bundle SHA-256は
`f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5`です。

## Bundle構成

canonical runtime bundle sourceは
[`bundle/takusuki-update3-bundle/`](bundle/takusuki-update3-bundle/)です。その外側にある
[bundle documentation](bundle/README.md)で構成、managed patches、build規則を説明しています。

sourceからreproducible ZIPを生成するには:

```bash
./scripts/build-bundle.sh
```

## Security model

updaterはofficial Misskey remoteのallowlist、fetch後のexact commit解決、HTTPS bundle、
SHA-256 sidecar、ZIP traversal防止、重複entry・symlink・special file拒否、bundle
manifestと個別hash/sizeを検証します。isolated official worktreeで全patchの互換性を確認し、
preflightが完了するまでserviceを停止しません。

download済みbundleのintegrity failureではcacheへfallbackせず停止します。cacheはnetwork
failure時だけ利用し、利用前に再検証します。install/build/migration failure後に壊れた
serviceを無条件起動せず、readinessは時間制限付きです。

## Rollback

rollback前に現在と更新前のmigration ledgerをbyte比較します。異なる場合はsource-only
rollbackを拒否します。DB restoreは自動実行しません。

「source rollback可能」と「DB backupからrestore可能」は別の判断です。migrationを含む
復旧は、DB互換性とbackupを人間が確認したうえで別途計画してください。

## DB backup

通常updateはDB backupを作成しません。対話メニュー5または`--db-backup`で明示した場合だけ、
custom-format `pg_dump`を実行します。完成後に`pg_restore --list`、file size、
SHA-256、entry count、PostgreSQL versionを検証・記録し、失敗したpartial dumpは有効backup
として扱いません。

## Release / Verification

```bash
./scripts/verify-release.sh
```

この検証はupdater SHA、deterministic bundle、ZIP、manifest、secret pattern、READMEの
local linksを検証し、Misskey hostへは接続しません。Gallery 256のrelease履歴は
[reports index](reports/README.md)を参照してください。

## License

repository全体がMIT-onlyではありません。

- Takusuki updaterとhelper scripts: [MIT](LICENSE)
- Misskey由来patch: [AGPL-3.0-only](LICENSES/AGPL-3.0-only.txt)
- Takusuki original `unknown.png`: MIT — Copyright (c) 2025-2026 asami

詳細は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)と
[license audit](docs/license-audit.md)を参照してください。

## Legacy

旧v2系updater、patch、assetは履歴を保つため[`legacy/`](legacy/)へ移動しました。新規運用
では使用しないでください。旧`.gitignore`は誤ってPython生成コードを含む非UTF-8 file
だったため、証跡として`legacy/gitignore-corrupted.txt`へ移動しました。
