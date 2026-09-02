# Gallery 256 release state

Status: **DEPLOYED TO PRODUCTION — STAGING ISOLATION RETEST WAIVED BY OPERATOR**

## Candidate

- Patch: `020-gallery-file-limit-256.patch`
- Patch SHA-256: `540962dc92bdd951e73be7ac4c8091c874d53c6e9150b19698837e35234f95e4`
- Candidate bundle: `candidate/takusuki-update3-bundle.zip`
- Accepted bundle SHA-256: `f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5`
- Updater SHA-256 (unchanged): `a121db5ab1ef3d834f8cf3f49909318b3a6736eb3e0dc608acca7a6c71a9aa5f`

## Release decision

The Gallery 256 functional validation passed all boundary, patch, build, migration, health and
rollback-readiness checks. Staging isolation failed because the Staging instance shared the
Production object-storage endpoint `083.takusuki.com` / bucket `house`, and traffic to it was
observed.

On 2026-09-03, the operator explicitly waived an additional Staging isolation rerun and approved
the existing deterministic candidate as the Git release source. This waiver does not reclassify
the Staging isolation test as PASS. The historical result remains **STAGING ISOLATION: FAIL**.

The accepted Git release source is identified by
`ACCEPTED_BUNDLE_SHA256=f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5`.

## Deployment timeline

1. The deterministic candidate was accepted as the Git release source under the operator waiver.
2. PR #2 merged the exact source into `main` at
   `d670118d4f5085fc189b59d6e36914d099b0b481`.
3. The accepted bundle was published to the runtime distribution endpoint.
4. The exact release was deployed to Misskey 2026.7.0 Production as a same-version update on
   2026-09-03.
5. Production install, build, migration, service and health validation passed with no pending
   migration, `NRestarts=0` and 22 seconds of service downtime.

## Current deployment state

| Component | State |
| --- | --- |
| Git release source | MERGED |
| Runtime distribution | DEPLOYED |
| Public runtime SHA-256 | `f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5` |
| Production | DEPLOYED |
| Production validation | PASS |

The Production success does not alter the historical **STAGING ISOLATION: FAIL** result.
