# 卓すきーProduction 2026.10.0 — v4.1.0適用runbook

このrunbookは管理者がVM完全backupを完了した後に使います。今回のrelease作業では
`192.168.100.29`へupdaterを実行しません。

## 開始条件

- VM backup ID、取得時刻、restore手順、担当者を記録済み
- ProductionがMisskey `2026.10.0`
- 公式base commitが`de89118a225fbe0833e42ab94e8d5af1e5211208`
- DB migration変更を予定していない
- block listを変更しない
- maintenance windowと連絡先を確保済み

## 固定配布物の取得

```bash
release_dir=$(mktemp -d)
cd "$release_dir"
base=https://labo.takusuki.com/update3/releases/4.1.0
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update3.sh"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki_update3.sh.sha256"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update3-bundle.zip"
curl --proto '=https' --tlsv1.2 -fLO "$base/takusuki-update3-bundle.zip.sha256"
sha256sum -c takusuki_update3.sh.sha256
sha256sum -c takusuki-update3-bundle.zip.sha256
chmod 0755 takusuki_update3.sh
```

## 無停止の最終判定

```bash
sudo ./takusuki_update3.sh \
  --tag 2026.10.0 --advanced --check-patches \
  --bundle-file ./takusuki-update3-bundle.zip \
  --bundle-sha-file ./takusuki-update3-bundle.zip.sha256

sudo ./takusuki_update3.sh \
  --tag 2026.10.0 --advanced --check \
  --bundle-file ./takusuki-update3-bundle.zip \
  --bundle-sha-file ./takusuki-update3-bundle.zip.sha256
```

ここまでservice停止はありません。出力で次を確認します。

- target `2026.10.0`と固定commitが一致
- source stateが`001-010-020-applied`または`001-010-020-030-applied`
- PostgreSQL、PGroonga、Redis、migration、diskが正常
- unknown tracked modificationがない
- VM backup IDとrestore担当者を再確認

4本適用済みなら`ALREADY APPLIED`で終了し、実適用は不要です。これがservice停止前の最終中止点です。

## 実適用

```bash
sudo ./takusuki_update3.sh \
  --tag 2026.10.0 --advanced --yes \
  --bundle-file ./takusuki-update3-bundle.zip \
  --bundle-sha-file ./takusuki-update3-bundle.zip.sha256
```

`Final no-return checkpoint`の次にserviceが停止します。完了後、updaterのhealth PASSに加え、
管理者が公開API、Note検索/TL、block維持、Gallery 256、CPU、PostgreSQL session、slow SQL、
statement timeoutを確認します。block listの追加・削除は行いません。

## rollback判断

履歴IDを確認し、migration ledgerが同一の場合だけ次を使います。

```bash
sudo ./takusuki_update3.sh --rollback --rollback-id HISTORY_ID --yes
```

ledger差分、DB破損、VM全体の不整合がある場合はsource-only rollbackを行わず、maintenance状態を
維持してVM/DB backupのrestore手順へ移行します。
