# Takusuki Update

Takusuki Updateは、Ubuntu/systemdの通常インストール版Misskeyへ卓すきー管理patchを
fail-closedで適用するupdaterです。Docker/Kubernetes版は対象外です。

## 正式配布版 5.1.2

| 項目 | 値 |
| --- | --- |
| Updater / bundle release | `5.1.2` |
| 互換性参照Misskey | `2026.11.0` / `dd7b4905d715d2587fa2f2cb6a88ecac8878ef0d` |
| 2026.11.0 patch適用検査 | `PASS`（001/010/020/030/040） |
| 対応OS | Ubuntu amd64 / arm64、systemd、通常インストール |
| DB schema追加 | なし |

bundleの参照version/commitは、その組み合わせで得た検証証拠を示す参考情報です。v5は異なる
公式stable tagであることだけを理由に拒否せず、5 patchの厳密な順次適用を事前検査します。
適用成功やbuild成功を、機能互換性の事前検証済みとは表示しません。

## 管理patch

順序とSHA-256は
[`patch-manifest.tsv`](bundle/takusuki-update3-bundle/misskey-patches/patch-manifest.tsv)が正本です。

| 順 | ID | 目的 |
| ---: | --- | --- |
| 1 | `001` | ノート文字数上限を5000へ変更 |
| 2 | `010` | FederationChartのblocked-host照合を高速化 |
| 3 | `020` | Gallery添付上限を32から256へ拡張 |
| 4 | `030` | Note検索/TLのblocked-host照合をDNS suffix等値照合へ最適化 |
| 5 | `040` | [Misskey #18111](https://github.com/misskey-dev/misskey/issues/18111)：管理画面とユーザー設定でアバターデコレーションをカテゴリ名順に表示 |

030はliteral domainを等値照合し、wildcard規則だけ`ILIKE`を維持します。010は
FederationChart専用、030はNote検索/TL経路用で、別のquery pathを改善します。030はDB schema、
可視性、block、連合制御の意味を変更しません。詳細は
[検証報告](reports/note-blocked-host-optimization.md)を参照してください。

## 配布物

- `takusuki_update5.sh`
- `takusuki_update5.sh.sha256`
- `takusuki-update5-bundle.zip`
- `takusuki-update5-bundle.zip.sha256`

bundleはsidecar SHA-256、ZIP path/type、manifest inventory、各patch/assetのSHA-256とsizeを検証します。
通常のHTTPS取得とキャッシュでは、updaterと同じ `release_id` のみ受け付けます。
旧版bundleが必要な場合は `--advanced --bundle-file` と `--bundle-sha-file` をセットで指定してください。
旧版でもSHA-256とmanifestの検証は必須です。

## 導入

Production作業ではmoving URLではなく固定Release URLを使ってください。

```bash
install_dir=$(mktemp -d)
cd "$install_dir"
base=https://github.com/asamid/takusuki_update/releases/download/v5.1.2
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update5.sh"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update5.sh.sha256"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update5-bundle.zip"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update5-bundle.zip.sha256"
sha256sum -c takusuki_update5.sh.sha256
sha256sum -c takusuki-update5-bundle.zip.sha256
chmod 0755 takusuki_update5.sh
```

既定の取得元はGitHubの固定assetです。Webで同じ版を取得する場合は
`https://labo.takusuki.com/update3/releases/5.1.2/` の公開状況とSHA-256を確認してください。

初回導入では、公式Git checkout、非rootのUbuntu/systemdサービス、`.config/default.yml`、
対象Misskeyが要求するNode.jsとCorepackを用意してください。既存パッチがなくても導入できます。
サービスの `User`、`Group`、`WorkingDirectory`、`ExecStart` を照合します。候補が複数あるときは
サービス名かパスを明示してください。PostgreSQLとRedisの接続情報はMisskeyの設定から読み取り、
書き換えません。

## Patched更新

引数なしのメニュー1は最新stable、メニュー2はstable tag選択です。どちらも001/010/020/030と、必要な場合は040を
順番に適用します。CLIの推奨順序:

```bash
sudo ./takusuki_update5.sh --tag 2026.11.0 --check-patches
sudo ./takusuki_update5.sh --tag 2026.11.0 --check
sudo ./takusuki_update5.sh --tag 2026.11.0 --yes
```

- `--check-patches`: 公式targetの隔離worktreeで5 patchを順次検査
- `--check`: source/runtime/DB/Redisを含むread-only preflight
- `--yes`: install、build、migration、service、HTTP/APIまで実適用（root必須）

2026.11.0以降は対象`package.json`のversionを数値比較し、公式`node ./scripts/start.mjs`へ
systemdの起動方式を切り替えます。それより前は従来方式を維持します。updaterが管理するdrop-inは
変更前に履歴へ保存し、rollback可能な場合は元の状態へ戻します。独自ExecStartは推測で上書きしません。
`pnpm migrate`は独立工程のままで、起動時に`--migrate`を渡しません。

2026.11.0のNode.js要件は`^24.22.3 || ^26.13.1`です。updaterは対象の
`packages/backend/package.json`にある`engines.node`を読み、シェルとsystemd双方のNode.jsが
満たさなければservice停止前に拒否します。

参照version以外は`UNVERIFIED_TARGET_PATCH_PREFLIGHT_REQUIRED`と記録されます。patch conflict、部分状態、
build、migration、service、healthのいずれかが失敗すれば成功扱いにしません。

最新版を選ぶ場合:

```bash
sudo ./takusuki_update5.sh --stable --yes
```

## Vanilla更新

メニュー6または次のCLIは、正確な公式tagへ切り替え、独自patchと独自`unknown.png`を適用しません。

```bash
sudo ./takusuki_update5.sh --vanilla --tag 2026.11.0 --check
sudo ./takusuki_update5.sh --vanilla --tag 2026.11.0 --yes
```

更新前に既存の管理patch状態、binary diff、untracked archive、migration ledger、設定を履歴保存します。
trackedな管理変更は公式状態へ戻しますが、`git clean`は使いません。DB/Redisを初期化せず、uploads、
無関係なuntracked file、`.config/default.yml`を保護します。Vanilla完了後のpatch stateは0本です。

## source状態とFail-Closed

現在HEADが取得済み公式refから到達可能で、tracked差分が既知patch/assetだけであることを確認します。
現在versionと更新先versionが異なっても、現在HEADをbaseに0〜5本の連続patch prefixを分類できます。
未知のtracked差分・非公式commit・不連続patch状態はservice停止前に拒否します。

install/build/migrateはservice停止後です。失敗時は壊れたserviceを無条件に起動せず、失敗工程、
migration開始有無、log、rollback候補を表示します。migration開始後はDB互換性を推測してsourceだけを
自動rollbackしません。通常更新はDB backupを自動取得しないため、先にVM snapshotまたは検証済み
DB backupを用意してください。

## rollbackとDB backup

```bash
sudo ./takusuki_update5.sh --rollback
sudo ./takusuki_update5.sh --rollback --rollback-id HISTORY_ID --yes
sudo ./takusuki_update5.sh --db-backup --yes
```

rollbackは更新前と現在のmigration ledgerが同一の場合だけsource復元を許可します。
既定のstate/log/cache/DBバックアップは `/var/{lib,log,cache,backups}/takusuki-update5/` 配下で、
サービス名・実パス・ユーザーから作った識別子ごとに分離します。旧版の履歴を使う場合は、
同じインスタンスの履歴であることを確認して `STATE_DIR=/var/lib/takusuki-update3` を明示してください。
同じ状態ディレクトリへの並行実行や別インスタンスへの再利用は拒否します。

## 明示設定とoffline bundle

`MISSKEY_DIR`、`MISSKEY_USER`、`SERVICE_NAME`のいずれかを明示した場合は、
`/root/.misskey.env` の旧インスタンス設定を読み込みません。ユーザーホーム内のenvファイルは実行しません。
HTTP待受ポートは `.config/default.yml` の `port` から読み取り、ループバックの `/` と `/api/meta`
を使います。Unix socketやプロキシ経由の確認では `HEALTH_LOCAL_URL` と `HEALTH_API_URL` の両方を指定してください。
安全なservice省略名（例: `takusuki.com`）には`.service`を補完し、それ以外の不正な名前は拒否します。
起動が60秒を超える隔離環境では`READINESS_ATTEMPTS`（既定30）と
`READINESS_INTERVAL_SECONDS`（既定2）を明示できます。

```bash
sudo env MISSKEY_DIR=/srv/misskey MISSKEY_USER=misskey SERVICE_NAME=misskey.service \
  HEALTH_LOCAL_URL=http://127.0.0.1:8270/ HEALTH_API_URL=http://127.0.0.1:8270/api/meta \
  ./takusuki_update5.sh --tag 2026.11.0 --check

sudo ./takusuki_update5.sh --tag 2026.11.0 --advanced --yes \
  --bundle-file ./takusuki-update5-bundle.zip \
  --bundle-sha-file ./takusuki-update5-bundle.zip.sha256
```

branch/commit指定は`--advanced`が必要です。master resetは開発中コードのため強い確認を要求します。

## 040の省略と廃止

040はフロントエンドのみの暫定パッチです。API、ロール制限、装着・取り外し・編集、DB migrationは変更しません。
同等修正が本家に入ったら公式コミット上で両画面の動作をレビューし、
`scripts/avatar-sort-snapshot.sh MISSKEY_GIT OFFICIAL_COMMIT` の出力を
`040-upstream-snapshots.txt` に追加してください。同じ3ファイルの内容を持つ公式ソースでは040を省略します。
逆適用できるだけでは省略しません。本家修正を確認できず、パッチも適用できない場合は停止します。

未修正版を対応対象から外すときは `patch-manifest.tsv` の040を `retired` に変更してbundleを再生成します。
廃止後はレビュー済みの本家実装が必須です。040の行とパッチファイルを残すことで、旧チェックアウトの
識別と履歴からの復元を保ちます。001/010/020/030は引き続き適用します。

## build・検証・公開

```bash
./scripts/build-bundle.sh
./scripts/verify-release.sh
./scripts/prepare-release-assets.sh ./dist/release
sudo ./scripts/publish-web-release.sh ./dist/release /var/www/trpger/labo/update3 5.1.2 4.1.0
```

bundle生成はbyte-identicalです。公開scriptはv4.1.0固定領域を保持し、v5固定領域を作成して、
Linux `renameat2(RENAME_EXCHANGE)`でdirectory tree全体を原子的に切り替えます。

対象versionごとの詳細検証は通常更新の必須条件ではありません。公式更新前の任意の深い確認には
`scripts/check-update-compatibility.sh`を使えます。この結果は通常updaterのpatch適用結果とは別の証拠です。

## 既知の制約

- Docker/Kubernetes、非Ubuntu、非systemd、rootで動くサービスは対象外
- 独自ランチャー、相対パスのExecStart、systemdの `EnvironmentFile`、既定ファイル以外の設定は自動検証の対象外
- functional compatibilityはversion横断で自動保証されない
- PostgreSQL/Redisの認証情報や既存設定は上書きしない
- DB backup/VM snapshot、外部storage、連合配送、メールの復旧は管理者責任
- `master`/advanced commitはstable tagよりリスクが高い

## Security / License

official remote allowlist、official ref reachability、HTTPS、sidecar、ZIP traversal/symlink/special-file、
manifest、個別hash、verified cache fallbackを検証します。integrity failureではcacheへfallbackしません。

- updater/helper: [MIT](LICENSE)
- Misskey由来patch: [AGPL-3.0-only](LICENSES/AGPL-3.0-only.txt)
- `unknown.png`: MIT — Copyright (c) 2025-2026 asami

詳細は[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)と
[license audit](docs/license-audit.md)を参照してください。
