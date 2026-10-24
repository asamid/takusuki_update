# Takusuki Update Bundle

このdirectoryは、`takusuki_update3.sh`が利用するTakusuki固有のruntime bundle sourceを
管理します。

canonical source:

```text
bundle/takusuki-update3-bundle/
```

```text
bundle/
├── README.md
└── takusuki-update3-bundle/
    ├── assets/
    │   ├── unknown.png
    │   └── unknown.png.sha256
    ├── bundle-manifest.tsv
    └── misskey-patches/
        ├── 001-max-note-text-length.patch
        ├── 010-exp003-federation-chart-blocked-host.patch
        ├── 020-gallery-file-limit-256.patch
        ├── 030-note-blocked-host-query-optimization.patch
        ├── patch-manifest.tsv
        └── series
```

## Managed patches

- `001-max-note-text-length.patch`: `MAX_NOTE_TEXT_LENGTH`を5000へ変更
- `010-exp003-federation-chart-blocked-host.patch`: FederationChart
  blocked-host matchingの性能を改善
- `020-gallery-file-limit-256.patch`: Gallery create/update APIの`fileIds`上限を
  32から256へ拡張
- `030-note-blocked-host-query-optimization.patch`: Note検索/TLでblocked hostを
  DNS suffix等値照合し、巨大なspread parameter SQLを回避

020は次の双方を変更します。

- `packages/backend/src/server/api/endpoints/gallery/posts/create.ts`
- `packages/backend/src/server/api/endpoints/gallery/posts/update.ts`

DB schema変更とmigrationはありません。2026-09-03にMisskey 2026.7.0のProductionへ
same-version deploymentとして適用済みです。

## Release identity

Release IDとMisskey versionは分離しています。4.1.0 bundleは次をmanifestに固定します。

```text
release_id: 4.1.0
target_misskey_version: 2026.10.0
target_official_commit: de89118a225fbe0833e42ab94e8d5af1e5211208
bundle_sha256: 7b68d319e1b98938de80f56348839937809bfd9f4acc66fe2cb33eec99c11742
```
Productionへの適用有無はbundle identityとは別に記録します。4.1.0 release作業ではProductionへ
適用しません。

## Build and validation

```bash
./scripts/build-bundle.sh
./scripts/verify-release.sh
```

canonical sourceを手動でZIP化しないでください。`bundle-manifest.tsv`を無視してfileを
追加したり、generated ZIPを直接編集したりすると、inventoryまたはdeterministic SHAが
変わります。source変更時はmanifestのhash/size/inventoryを更新し、buildとrelease検証を
必ず実行してください。
