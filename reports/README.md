# Takusuki Update reports

## Note blocked-host performance

- [Note blocked-host query optimization candidate](note-blocked-host-optimization.md): root cause,
  candidate 030 design, isolated benchmark, compatibility and remaining Production gate.

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
