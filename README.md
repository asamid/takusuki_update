# Takusuki Update

Takusuki Updateは、Ubuntu/systemdの通常インストール版Misskeyへ卓すきー管理patchを
fail-closedで適用するupdaterです。Docker/Kubernetes版は対象外です。

## 正式配布版 5.0.0

| 項目 | 値 |
| --- | --- |
| Updater / bundle release | `5.0.0` |
| 互換性参照Misskey | `2026.10.0` / `de89118a225fbe0833e42ab94e8d5af1e5211208` |
| 2026.10.1 patch適用検査 | `PASS` / `4840fa6d576128ba916ba69169258ca177d40faf` |
| 対応OS | Ubuntu amd64 / arm64、systemd、通常インストール |
| DB schema追加 | なし |

bundleの参照version/commitは、その組み合わせで得た検証証拠を示す参考情報です。v5は異なる
公式stable tagであることだけを理由に拒否せず、4 patchの厳密な順次適用を事前検査します。
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
format 2の対象情報は`compatibility_reference_*`です。v5は必要時にformat 1のv4 bundleも読み取れますが、
その`target_*`も互換性参照としてのみ扱います。

## 導入

Production作業ではmoving URLではなく固定Release URLを使ってください。

```bash
install_dir=$(mktemp -d)
cd "$install_dir"
base=https://github.com/asamid/takusuki_update/releases/download/v5.0.0
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update5.sh"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update5.sh.sha256"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update5-bundle.zip"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update5-bundle.zip.sha256"
sha256sum -c takusuki_update5.sh.sha256
sha256sum -c takusuki-update5-bundle.zip.sha256
chmod 0755 takusuki_update5.sh
```

Web固定領域は`https://labo.takusuki.com/update3/releases/5.0.0/`、通常領域は
`https://labo.takusuki.com/update3/`です。v4.1.0固定領域と旧ファイル名の通常URLはv4.1.0へ
固定したまま維持します。

## Patched更新

引数なしのメニュー1は最新stable、メニュー2はstable tag選択です。どちらも001/010/020/030を
順番に適用します。CLIの推奨順序:

```bash
sudo ./takusuki_update5.sh --tag 2026.10.1 --check-patches
sudo ./takusuki_update5.sh --tag 2026.10.1 --check
sudo ./takusuki_update5.sh --tag 2026.10.1 --yes
```

- `--check-patches`: 公式targetの隔離worktreeで4 patchを順次検査
- `--check`: source/runtime/DB/Redisを含むread-only preflight
- `--yes`: install、build、migration、service、HTTP/APIまで実適用（root必須）

参照version以外は`UNVERIFIED_TARGET_PATCH_PREFLIGHT_REQUIRED`と記録されます。patch conflict、部分状態、
build、migration、service、healthのいずれかが失敗すれば成功扱いにしません。

最新版を選ぶ場合:

```bash
sudo ./takusuki_update5.sh --stable --yes
```

## Vanilla更新

メニュー6または次のCLIは、正確な公式tagへ切り替え、独自patchと独自`unknown.png`を適用しません。

```bash
sudo ./takusuki_update5.sh --vanilla --tag 2026.10.1 --check
sudo ./takusuki_update5.sh --vanilla --tag 2026.10.1 --yes
```

更新前に既存の管理patch状態、binary diff、untracked archive、migration ledger、設定を履歴保存します。
trackedな管理変更は公式状態へ戻しますが、`git clean`は使いません。DB/Redisを初期化せず、uploads、
無関係なuntracked file、`.config/default.yml`を保護します。Vanilla完了後のpatch stateは0本です。

## source状態とFail-Closed

現在HEADが取得済み公式refから到達可能で、tracked差分が既知patch/assetだけであることを確認します。
現在versionと更新先versionが異なっても、現在HEADをbaseに0〜4本の連続patch prefixを分類できます。
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

rollbackは更新前後のmigration ledgerが同一の場合だけsource復元を許可します。v4の既存
`/var/lib/takusuki-update3`履歴を継承するため、v5も既定のstate/log/cache pathを維持します。

## 明示設定とoffline bundle

`MISSKEY_DIR`、`MISSKEY_USER`、`SERVICE_NAME`等を実行環境で指定した値は、legacy env fileより優先します。
起動が60秒を超える隔離環境では`READINESS_ATTEMPTS`（既定30）と
`READINESS_INTERVAL_SECONDS`（既定2）を明示できます。

```bash
sudo env MISSKEY_DIR=/srv/misskey MISSKEY_USER=misskey SERVICE_NAME=misskey.service \
  ./takusuki_update5.sh --tag 2026.10.1 --check

sudo ./takusuki_update5.sh --tag 2026.10.1 --advanced --yes \
  --bundle-file ./takusuki-update5-bundle.zip \
  --bundle-sha-file ./takusuki-update5-bundle.zip.sha256
```

branch/commit指定は`--advanced`が必要です。master resetは開発中コードのため強い確認を要求します。

## build・検証・公開

```bash
./scripts/build-bundle.sh
./scripts/verify-release.sh
./scripts/prepare-release-assets.sh ./dist/release
sudo ./scripts/publish-web-release.sh ./dist/release /var/www/trpger/labo/update3 5.0.0 4.1.0
```

bundle生成はbyte-identicalです。公開scriptはv4.1.0固定領域を保持し、v5固定領域を作成して、
Linux `renameat2(RENAME_EXCHANGE)`でdirectory tree全体を原子的に切り替えます。

対象versionごとの詳細検証は通常更新の必須条件ではありません。公式更新前の任意の深い確認には
`scripts/check-update-compatibility.sh`を使えます。この結果は通常updaterのpatch適用結果とは別の証拠です。

## 既知の制約

- Docker/Kubernetes、非Ubuntu、非systemdは対象外
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
