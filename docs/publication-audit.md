# Publication audit — Takusuki Update3 v4.1.0

Audit date: 2026-10-25 (JST)

## Release identity

- Updater: `4.1.0`
- Misskey: `2026.10.0`
- Official commit: `de89118a225fbe0833e42ab94e8d5af1e5211208`
- Updater SHA-256: `4fc9af956091e5f5dbf4c156fabde6b56826aa12f6f8f969760a9110e18a2e39`
- Bundle SHA-256: `7b68d319e1b98938de80f56348839937809bfd9f4acc66fe2cb33eec99c11742`

`scripts/build-bundle.sh`による独立した2回の生成はbyte-identicalでした。ZIP CRC、path/type、
bundle/patch manifest、個別SHA-256/size、README local link、ShellCheck、秘密情報patternはPASSです。

## Compatibility gate

隔離worktreeと専用一時PostgreSQL DBで次を再実行しました。

- official remote/tag/exact commit: PASS
- migration inventory: 変更0
- 001/010/020/030の順次適用: PASS
- frozen pnpm 11.25.0 install: PASS
- unit/integration test: 25/25 PASS、skip 0
- SPDX: PASS
- Misskey full build: PASS
- PGroonga 4.1.0 API evidence: 28/28、mismatch 0

## Secret and operational metadata audit

private key、GitHub/AWS token、Bearer value、database URL実値、`.env`、DB dump、runtime log、
SSH credential、SMTP/Cloudflare credentialは含みません。旧updaterにあったProduction固定IPと
固定local username前提は削除しました。`/root/.misskey.env`は任意のtrusted config探索pathとして
のみ記載し、内容は含みません。

## Asset and license audit

4 patchが参照するsourceとbuild assetを静的監査し、外部追加配置が必要なのはありません。
`unknown.png`はbundle内に同梱し、`blank.png`は不要です。updater/helperとoriginal assetはMIT、
Misskey-derived 4 patchはAGPL-3.0-onlyです。
