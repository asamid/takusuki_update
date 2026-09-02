# Gallery 256 investigation

Observed: 2026-09-03 JST

## Environment

- Controller: `ubuntu`, `192.168.100.138`.
- Repository baseline: `asamid/takusuki_update` main commit `522f203e6fb3ba22016a53658e29f4a54c5c0a0a`.
- Working branch: `feature/gallery-limit-256`.
- Public Production NodeInfo reports Misskey `2026.7.0`.
- At the time of this investigation, the exact Production Git commit, working tree, migration
  ledger, service state and configuration hashes were UNKNOWN because the configured Production
  READ-ONLY SSH authentication failed.
- Staging `192.168.100.62` became reachable on TCP/22 and accepted the configured
  `takusuki-staging` Ed25519 identity.
- Staging is a Production-data clone whose effective database `meta` settings enable object
  storage at `083.takusuki.com`, bucket `house`; this matches known Production journal evidence.

## Source finding

The official Misskey `2026.7.0` tag resolves to commit
`8ea4a0ecac058688f69706ab88de1fcd439e2621`. Both Gallery endpoints declare
`fileIds.maxItems: 32`:

- `packages/backend/src/server/api/endpoints/gallery/posts/create.ts`
- `packages/backend/src/server/api/endpoints/gallery/posts/update.ts`

The database entity stores `fileIds` as an array and this change introduces no schema or migration change.

## Candidate change

`020-gallery-file-limit-256.patch` changes only the two endpoint limits from 32 to 256.
It is registered as a required AGPL-3.0-only Misskey-derived patch after 001 and 010.

- Patch SHA-256: `540962dc92bdd951e73be7ac4c8091c874d53c6e9150b19698837e35234f95e4`
- Added paths: none
- Updater script changed: no

## Local evidence

- `git apply --check --whitespace=error-all`: PASS for 001, 010 and 020.
- `git diff --check`: PASS.
- Applied create limit: 256.
- Applied update limit: 256.
- Gallery endpoint `maxItems: 32` remaining after application: none.
- Updater `--check-patches` against official 2026.7.0: PASS and explicitly checked 001/010/020.

The exact candidate subsequently passed Staging build and create/update API boundary tests, but
the release gate failed because the Staging test accessed the shared Production object-storage
endpoint. See `reports/gallery-256-staging-validation.md`.

## Outcome

- Implemented as managed patch `020-gallery-file-limit-256.patch`.
- Merged through PR #2 at `d670118d4f5085fc189b59d6e36914d099b0b481`.
- Deployed to Misskey 2026.7.0 Production on 2026-09-03.
- Production validation: PASS.

These later outcomes do not revise the isolation failure recorded during the Staging investigation.
