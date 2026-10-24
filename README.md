# Takusuki Update

Takusuki Updateは、Ubuntu上でsystemd運用される通常インストール版Misskeyへ、検証済みの
管理patchを再現可能かつfail-closedで適用するupdaterです。Docker版は対象外です。

## 正式配布版 4.1.0

| 項目 | 固定値 |
| --- | --- |
| Updater / bundle release | `4.1.0` |
| 対象Misskey | `2026.10.0` |
| 公式commit | `de89118a225fbe0833e42ab94e8d5af1e5211208` |
| 対応OS | Ubuntu amd64 / arm64、systemd、通常インストール |
| DB schema追加 | なし |

Misskeyのversionとupdater/bundleのrelease IDは別物です。互換性判定はversion文字列だけでなく、
公式commit、patch系列、bundle SHA-256で行います。卓すきーStagingでの成功は下記構成の検証結果で
あり、任意の独自改変環境を保証するものではありません。

## 管理patch

次の順序は固定です。実ファイルのhashは
[`patch-manifest.tsv`](bundle/takusuki-update3-bundle/misskey-patches/patch-manifest.tsv)を正本とします。

| 順 | ID | 目的 |
| ---: | --- | --- |
| 1 | `001-max-note-text-length.patch` | ノート文字数上限を5000へ変更 |
| 2 | `010-exp003-federation-chart-blocked-host.patch` | FederationChartのblocked-host照合を高速化 |
| 3 | `020-gallery-file-limit-256.patch` | Gallery添付上限を32から256へ拡張 |
| 4 | `030-note-blocked-host-query-optimization.patch` | Note検索/TLのblocked-host照合をDNS suffix等値照合へ最適化 |

030はliteral domainを等値照合し、wildcard規則だけILIKEを維持します。ユーザー、可視性、block、
連合制御の意味やDB schemaを変更しません。詳細は
[検証報告](reports/note-blocked-host-optimization.md)を参照してください。

## 配布物と静的asset

GitHub ReleaseとWeb Runtimeはいずれも次の4ファイルを配布します。

- `takusuki_update3.sh`
- `takusuki_update3.sh.sha256`
- `takusuki-update3-bundle.zip`
- `takusuki-update3-bundle.zip.sha256`

`unknown.png`はbundle内に同梱され、個別hashとbundle manifestで検証されます。4 patchとbuild参照を
静的監査した結果、`blank.png`を含む追加assetの外部配置は不要です。オフラインでは4ファイルを
同一ディレクトリへ取得し、`--bundle-file`と`--bundle-sha-file`を`--advanced`付きで指定できます。

## 導入

固定Releaseから4ファイルを取得します。`main`や通常URLはmoving targetなので、本番作業では
固定URLを使用してください。

```bash
install_dir=$(mktemp -d)
cd "$install_dir"
curl --proto '=https' --tlsv1.2 -fLO \
  https://github.com/asamid/takusuki_update/releases/download/v4.1.0/takusuki_update3.sh
curl --proto '=https' --tlsv1.2 -fLO \
  https://github.com/asamid/takusuki_update/releases/download/v4.1.0/takusuki_update3.sh.sha256
curl --proto '=https' --tlsv1.2 -fLO \
  https://github.com/asamid/takusuki_update/releases/download/v4.1.0/takusuki-update3-bundle.zip
curl --proto '=https' --tlsv1.2 -fLO \
  https://github.com/asamid/takusuki_update/releases/download/v4.1.0/takusuki-update3-bundle.zip.sha256
sha256sum -c takusuki_update3.sh.sha256
sha256sum -c takusuki-update3-bundle.zip.sha256
chmod 0755 takusuki_update3.sh
```

Web Runtimeの固定領域は
`https://labo.takusuki.com/update3/releases/4.1.0/`、通常領域は
`https://labo.takusuki.com/update3/`です。

## 自動検出と事前チェック

未指定時はsystemdのWorkingDirectoryと標準配置からMisskey sourceを、所有者から実行userを、
WorkingDirectoryからserviceを検出します。候補が複数ならTTYで選択し、非対話時は安全停止します。
必要ならroot所有の`/root/.misskey.env`または環境変数で指定します。

```bash
MISSKEY_DIR=/srv/misskey \
MISSKEY_USER=misskey \
SERVICE_NAME=misskey.service \
sudo --preserve-env=MISSKEY_DIR,MISSKEY_USER,SERVICE_NAME \
  ./takusuki_update3.sh --tag 2026.10.0 --check
```

停止前にUbuntu/architecture、systemd、公式origin/base commit、Git差分、Node/Corepack/pnpm、
PostgreSQL、PGroonga、Redis、migration ledger、空き容量、patch状態、設定ファイル、rollback保存先を
確認します。DB password等の値は表示しません。

推奨順序:

```bash
sudo ./takusuki_update3.sh --tag 2026.10.0 --check-patches
sudo ./takusuki_update3.sh --tag 2026.10.0 --check
sudo ./takusuki_update3.sh --tag 2026.10.0 --yes
```

- `--check-patches`: 公式targetへ4 patchを順番に適用できるかだけを確認
- `--check`: bundle・source状態・runtime・DB/Redisを含むread-only preflight
- `--yes`: 実適用。root必須

通常URLではなく手元の検証済みbundleを使う場合:

```bash
sudo ./takusuki_update3.sh \
  --tag 2026.10.0 --advanced --yes \
  --bundle-file ./takusuki-update3-bundle.zip \
  --bundle-sha-file ./takusuki-update3-bundle.zip.sha256
```

## source状態の扱い

| 状態 | 動作 |
| --- | --- |
| 公式2026.10.0、patchなし | 4 patchを順番に適用 |
| 公式2026.10.0、001/010/020済み | 既知の3 patchと判定し、公式baseから4本を再現して030を追加 |
| 公式2026.10.0、4本済み | `ALREADY APPLIED`を返し、stop/build/migrateを行わない |
| 異なる公式version、clean | 対象commit、patch、DB接続を確認後にのみ更新可能 |
| 未知のtracked差分・非公式commit | 差分を消さず、service停止前に拒否 |

untrackedファイルは一覧とarchiveをrollback履歴へ保存し、broad `git clean`は実行しません。
`.config/default.yml`、利用中のenv file、systemd unitもrootのみ読める権限で履歴へ保存します。

## 停止影響と失敗時

install/build/migrateはservice停止後に実行されます。停止時間は環境のCPU、disk、pnpm cache、
migrationに依存します。`Final no-return checkpoint`が、service停止前の最終中止点です。

preflightやpatch検証の失敗ではserviceを停止しません。停止後のinstall/build/migration失敗では、
壊れたserviceを無条件に起動せず、失敗工程、service状態、migration開始有無、log、rollback候補を
表示します。通常updateはDB backupを自動取得しません。VM snapshotまたは検証済みDB backupを
先に用意してください。

## rollbackとDB backup

rollbackは更新前後のmigration ledgerが同一の場合だけsource復元を許可します。

```bash
sudo ./takusuki_update3.sh --rollback
sudo ./takusuki_update3.sh --rollback --rollback-id HISTORY_ID --yes
sudo ./takusuki_update3.sh --db-backup --yes
```

DB migrationが変化した場合、sourceだけのrollbackは拒否されます。VM/DB restoreは自動実行せず、
管理者が整合性を確認して実施します。

## 対話UIとその他のCLI

引数なしではstable update、tag選択、master reset、rollback、DB backupを選べます。`--stable`は
将来tagを選ぶ可能性がありますが、bundleに固定された対象version/commitと一致しなければ拒否されます。

```bash
sudo ./takusuki_update3.sh --stable --yes
sudo ./takusuki_update3.sh --master-reset --yes
sudo ./takusuki_update3.sh --db-backup --yes
```

branch/commit指定は`--advanced`が必要です。ただし4.1.0 bundleは2026.10.0の固定commit以外へは
適用されません。

## build・検証・公開

```bash
./scripts/build-bundle.sh
./scripts/verify-release.sh
./scripts/prepare-release-assets.sh ./dist/release
```

同一sourceからのbundle生成はbyte-identicalです。公開originでの原子切替には
[`publish-web-release.sh`](scripts/publish-web-release.sh)を使います。このスクリプトは固定release領域を
作り、旧通常配布物を保存し、Linux `renameat2(RENAME_EXCHANGE)`でdirectory tree全体を切り替えます。

## 将来の公式Misskey更新

新しい公式tagへ無条件に適用しません。Production外の隔離cloneで次を実行し、公式tag/commit、
migration差分、全patch、frozen install、対象test、SPDX、full build、API等価性・性能証拠がPASSした後、
bundle metadataとhashを新releaseとして更新します。

030の動的追従は、外部通信を遮断したbaseline/candidate APIと専用管理者tokenを用意して次を実行します。
対象hostの解除、追加、再解除、再追加をAPI経由で行い、exact/subdomain/deep subdomain、reply、renoteの
検索結果、設定復元、指定時はsystemdの無再起動をfail-closedで確認します。token値は結果へ出力しません。

```bash
BASELINE_URL=http://127.0.0.1:3101 \
CANDIDATE_URL=http://127.0.0.1:3102 \
BASELINE_SERVICE=misskey-baseline.service \
CANDIDATE_SERVICE=misskey-candidate.service \
node scripts/test-blocked-host-transition.mjs ./private-test-tokens.json ./block-transition.json
```

```bash
EXP003_DATABASE_URL="$ISOLATED_DATABASE_URL" \
./scripts/check-update-compatibility.sh \
  --source /path/to/official-misskey-clone \
  --tag 2026.10.0 \
  --expected-commit de89118a225fbe0833e42ab94e8d5af1e5211208 \
  --from-ref HEAD --full \
  --api-equivalence /path/to/api-equivalence.json \
  --api-performance /path/to/api-performance.json \
  --output-dir /path/to/result
```

上流取込候補、patch conflict、未知のmigrationは自動解決せずFAIL/BLOCKEDにします。

## 既知の制約

- Docker/Kubernetes、非Ubuntu、非systemdは対象外
- custom commitや未知のtracked差分は自動統合しない
- PostgreSQL/Redisの認証情報や既存設定を上書きしない
- DB backup/VM snapshot、外部storage、連合配送、メールの復旧は管理者責任
- 卓すきーでのPGroonga 4.1.0検証はPASSしたが、全versionの性能を保証しない

卓すきーProduction固有の作業は
[Production runbook](docs/takusuki-production-2026.10.0-runbook.md)に分離しています。

## Security / License

official remote allowlist、exact commit、HTTPS、sidecar、ZIP traversal/symlink/special-file、manifest、
個別hash、verified cache fallbackを検証します。integrity failureではcacheへfallbackしません。

- updater/helper: [MIT](LICENSE)
- Misskey由来patch: [AGPL-3.0-only](LICENSES/AGPL-3.0-only.txt)
- `unknown.png`: MIT — Copyright (c) 2025-2026 asami

詳細は[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)と
[license audit](docs/license-audit.md)を参照してください。旧v2成果物は`legacy/`に保持しています。
