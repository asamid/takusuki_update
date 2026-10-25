# Takusuki Update reports

## Updater v5

- [v5.0.0 Staging release validation](v5.0.0-staging-release-validation.md): isolated patched and
  Vanilla upgrades, injected failures, rollback, preservation, and deterministic release checks.
- [v5.0.0 GitHub and Web publication](v5.0.0-web-publication.md): Release assets, immutable/current
  HTTPS publication, v4 URL preservation, public menu fetch-back, and temporary-key cleanup.

## Note blocked-host performance

- [Note blocked-host query optimization candidate](note-blocked-host-optimization.md): root cause,
  candidate 030 design, Misskey 2026.10.0 PGroonga API validation, compatibility and remaining
  Production gate.
- [v4.1.0 Staging release validation](v4.1.0-staging-release-validation.md): distributed artifact
  application, same-version rerun, rollback/reapply, invariants and observed PGroonga 4.0.1 timeout.
- [v4.1.0 Production performance validation](v4.1.0-production-performance.md): read-only
  post-deployment SQL shape, API, timeout, CPU, worker, federation and future-update assessment.

## Gallery 256

These reports preserve the Gallery 256 investigation and release history in chronological order.

1. [Investigation](gallery-256-investigation.md): upstream limit, patch design and initial
   compatibility evidence.
2. [Staging validation](gallery-256-staging-validation.md): functional boundary validation and
   the historical Staging isolation failure.
3. [Release decision](gallery-256-release.md): operator waiver, accepted bundle identity, Git
   merge, runtime publication and deployment timeline.
4. [Production validation](gallery-256-production-validation.md): same-version Production
   deployment and health result.

The Staging functional validation passed. Staging isolation failed because the clone accessed the
shared Production object-storage endpoint, and the operator waived an additional isolation rerun.
The exact accepted artifact was subsequently deployed to Production and passed Production
validation. Production success does not reclassify the historical isolation result as PASS.
