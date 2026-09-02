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
        ├── patch-manifest.tsv
        └── series
```

## Managed patches

- `001-max-note-text-length.patch`: `MAX_NOTE_TEXT_LENGTH`を5000へ変更
- `010-exp003-federation-chart-blocked-host.patch`: FederationChart
  blocked-host matchingの性能を改善
- `020-gallery-file-limit-256.patch`: Gallery create/update APIの`fileIds`上限を
  32から256へ拡張

020は次の双方を変更します。

- `packages/backend/src/server/api/endpoints/gallery/posts/create.ts`
- `packages/backend/src/server/api/endpoints/gallery/posts/update.ts`

DB schema変更とmigrationはありません。2026-09-03にMisskey 2026.7.0のProductionへ
same-version deploymentとして適用済みです。

## Release identity

Accepted bundle SHA-256:

```text
f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5
```

## Build and validation

```bash
./scripts/build-bundle.sh
./scripts/verify-release.sh
```

canonical sourceを手動でZIP化しないでください。`bundle-manifest.tsv`を無視してfileを
追加したり、generated ZIPを直接編集したりすると、inventoryまたはdeterministic SHAが
変わります。source変更時はmanifestのhash/size/inventoryを更新し、buildとrelease検証を
必ず実行してください。
