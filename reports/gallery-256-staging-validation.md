# Gallery 256 Staging validation

Status: **FAILED AT PRODUCTION ISOLATION GATE; RELEASE BLOCKED**

Observed on 2026-09-03 JST against Staging `192.168.100.62` (`trpgeus`). The exact
candidate ZIP was not rebuilt or modified.

## Candidate identity

- Controller SHA-256: `f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5`.
- Staging SHA-256 after transfer: identical.
- Updater: v4.0.0, SHA-256 `a121db5ab1ef3d834f8cf3f49909318b3a6736eb3e0dc608acca7a6c71a9aa5f`.
- Official target: Misskey `2026.7.0`, commit `8ea4a0ecac058688f69706ab88de1fcd439e2621`.

## Identity and pre-state

- Node: `v22.22.2`; target package manager: `pnpm@11.11.0`.
- Service: `takusuki.com.service`, active, `NRestarts=0`.
- PostgreSQL: 15.17, active; Redis: 8.6.2, active/PONG.
- Free filesystem space before apply: 622,219,956 KiB.
- `.config/default.yml` SHA-256: `e6863af5aafdd3270a65f0761b8ba9c7d06011f9299a9c06b4064e3777b90702`.
- PostgreSQL config SHA-256: `005dd787264a267077a11d8414f22314c09b14441fa30c46a3f80072c0a257eb`.
- Migration ledger SHA-256: `82968ea7d6e37e1c69c4a73ffc9c55d9dd4f9a7645712aaa329f3ee77d61ec18`.

## Pipeline and runtime results

- Patch-only check for 001/010/020: PASS.
- Full `--check`: PASS; no service stop or live source change.
- Same-version actual apply: PASS.
- Install/build: PASS.
- Migration: PASS / no pending migration.
- Service start and local HTTP/API health: PASS.
- Recorded service downtime: 200 seconds.
- Source `create.ts` and `update.ts`: `maxItems: 256`.
- Running backend bundle: two exact Gallery validator occurrences at 256 and zero at 32.
- Pre/post migration ledgers: byte-identical.
- systemd restart delta: 0.
- Service remained active; no warning-or-higher systemd journal entries were recorded after start.

## Boundary API results

All calls used a dedicated temporary Staging account and local API endpoint.

| Endpoint | 1 | 32 | 33 | 256 | 257 |
| --- | --- | --- | --- | --- | --- |
| `gallery/posts/create` | ACCEPT | ACCEPT | ACCEPT | ACCEPT | REJECT (`INVALID_PARAM`) |
| `gallery/posts/update` | ACCEPT | ACCEPT | ACCEPT | ACCEPT | REJECT (`INVALID_PARAM`) |

After the rejected 257-file update, the existing post retained its 256-file state. The five
temporary Gallery posts and all 256 temporary DriveFile database rows were deleted. The
temporary account was marked deleted, its test-specific Redis keys were removed, and all
temporary credential/artifact files were destroyed.

## Isolation failure

Initial static inspection found local PostgreSQL and Redis and local-only updater health targets.
However, the effective object-storage settings live in the database `meta` row rather than
`.config/default.yml`:

- `useObjectStorage=true`
- base URL: `https://083.takusuki.com/house`
- endpoint: `083.takusuki.com`
- bucket: `house`

This endpoint and `/house/shell02/...` object paths also appear in the known Production journal
evidence. Packet capture during the test recorded 4,002 packets matching the broad Production
and public-storage filter. TLS inspection identified 66 handshakes with SNI
`083.takusuki.com`. The one packet matching the direct Production IPv4 was a gateway ARP query,
not Staging-originated application traffic; nevertheless, the Drive uploads and their cleanup
accessed the shared Production object-storage endpoint.

Object deletion ran through the `objectStorage` queue. The six failed job IDs were old
`235741`-`237284` jobs; the new cleanup jobs completed in the `277990`-`278019` range with no
new failure observed.

Therefore `STAGING ISOLATION` and `PRODUCTION ACCESS DELTA` are FAIL. The candidate must not be
declared `VALIDATED_BUNDLE_SHA256`, and expected SHA, GitHub, runtime distribution and Production
steps remain forbidden. A new Staging run requires a dedicated non-Production object-storage
endpoint/bucket (or verified local internal storage) and an enforceable Production network guard.

## Rollback readiness

The updater created complete history at
`/var/lib/takusuki-update3/backups/20260902T182623Z-10379-2026.7.0`. The pre-update series is
001/010, the current series is 001/010/020, and pre/post migration ledgers are identical.
Source rollback is therefore eligible. No rollback rehearsal was performed after the isolation
failure; Staging currently remains on 001/010/020 for investigation.
