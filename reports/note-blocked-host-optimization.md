# Note blocked-host query optimization candidate

Date: 2026-10-24 JST

Status: Staging candidate. Production is unchanged and requires an explicit approval gate.

## Root cause

Misskey 2026.9.0 `QueryService.generateBlockedHostQueryForNote()` expands every blocked host to
an exact and subdomain `ILIKE` pattern, then repeats that spread array for the note author, reply
author and renote author. With 3,471 configured rules this generates approximately 156 KB of SQL
and 20,826 positional bind values for affected Note Search and database timeline queries.

The existing 010 patch optimizes the separate hourly `FederationChart.tickMinor()` path. It does
not change `QueryService`, so it cannot fix this Note Search path.

## Candidate change

`030-note-blocked-host-query-optimization.patch` keeps the existing visible behavior while
changing the SQL shape:

- literal domain rules use case-folded DNS suffix equality;
- rules containing PostgreSQL `%` or `_` metacharacters remain on the original `ILIKE` path;
- author, reply author and renote author filtering remains in place;
- `NULL`/local hosts remain allowed by the existing outer conditions;
- the two arrays are reused as TypeORM named parameters;
- no schema, migration, block-list data or federation-delivery behavior changes.

## Isolated benchmark

Environment: local user-owned PostgreSQL 16.15, Unix socket only, TCP disabled, JIT disabled.
Fixture: 2,004 synthetic note rows, 3,471 blocked hosts, 3 host columns, three sequential runs.
The fixture covers literal exact/subdomain, case-insensitive, wildcard exact/subdomain, allowed and
`NULL` cases. It contains no Production data or credentials.

| Shape | SQL bytes | Bind values | Client median | Planning median | Execution median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current spread parameters | 155,758 | 20,826 | 6,222.0 ms | 773.6 ms | 5,406.3 ms |
| Single array only (rejected) | 271 | 1 | 6,338.2 ms | 633.7 ms | 5,418.7 ms |
| DNS suffix lookup candidate | 1,320 | 2 | 32.2 ms | 3.9 ms | 21.6 ms |

All three forms returned the same 2,001 allowed rows. The single-array-only variant was rejected
because it retained the expensive `ILIKE ALL` comparisons and did not materially improve execution.
These are synthetic Staging values and are not claimed as Production latency.

## Compatibility and release validation

- 001 -> 010 -> 020 -> 030 applies cleanly to official Misskey 2026.9.0: PASS.
- 001 -> 010 -> 020 -> 030 applies cleanly to official Misskey 2026.10.0: PASS.
- helper TypeScript strict compile: PASS.
- helper unit tests: 4/4 PASS.
- TypeORM 1.0.0 repeated named-array parameter test: 2 bind values, PASS.
- deterministic bundle build: PASS.
- bundle manifest, ZIP, secret and README link verification: PASS.
- candidate bundle SHA-256:
  `63915baca799a8f87cffd4819d0c848b49822d36c0d38c8f7e6adcec0927c3b5`.

## Remaining gate

The previously used Staging VM at `192.168.100.62` was unreachable during this investigation.
Therefore a full Misskey build and endpoint-level replay against a PGroonga dataset was not run.
Before Production deployment, run the updater patch check/full preflight and an isolated
PGroonga-backed `notes/search` result/latency comparison. Do not combine this performance patch
with a Misskey version upgrade in the same change window.
