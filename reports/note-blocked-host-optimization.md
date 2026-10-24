# Note blocked-host query optimization candidate

Date: 2026-10-24 JST

Status: Misskey 2026.10.0 isolated Staging validation PASS. Production is unchanged and requires
an explicit approval gate.

## Root cause

Misskey 2026.10.0 `QueryService.generateBlockedHostQueryForNote()` expands every blocked host to
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

## Historical isolated benchmark

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
These are historical PostgreSQL 16 design values and are not the current acceptance measurement.

## Misskey 2026.10.0 Staging validation

The live Staging service was found unsafe for mutation because it still identified as Production
and allowed federation/email traffic. A separate localhost-only test area was therefore created on
the same `.62` host with independent PostgreSQL databases, independent Redis processes and
`IPAddressDeny=any`/`IPAddressAllow=localhost` on every test unit. No Production data was copied.

Baseline was official 2026.10.0 + 001/010/020. Candidate added only 030. Both used PostgreSQL
15.17, PGroonga 4.0.6, 2,001 synthetic notes and 3,471 block rules.

| Actual API/SQL metric | Baseline | Candidate |
| --- | ---: | ---: |
| normalized SQL bytes | 170,826 | 16,422 |
| highest bind position | 20,838 | 29 |
| planning mean (3 calls) | 107.457 ms | 46.969 ms |
| execution mean (3 calls) | 10,077.888 ms | 2,307.277 ms |
| API p50 (7 low-load calls) | 10,509.2 ms | 2,501.7 ms |
| API p95 (7 low-load calls) | 10,792.6 ms | 2,864.0 ms |
| default 10 s timeout failures | 3/3 | 0/3 |

Twenty-eight functional API comparisons covering host suffixes, case, Unicode/Punycode,
`%`/`_`, reply/renote, visibility, login state, mute and ordinary block had zero ID/order/count
mismatches. Removing and re-adding a blocked host produced the same state transitions in both
trees. The full build passed in both trees; the combined 010/030 targeted suite passed 25/25.

The reusable regression runner is `scripts/test-blocked-host-transition.mjs`. It exercises
unblocked -> blocked -> unblocked -> blocked transitions through `admin/update-meta`, compares
baseline and candidate Note Search results for exact/subdomain/deep-subdomain/reply/renote cases,
restores the original block list in a `finally` path, and can assert unchanged systemd start and
restart counters without printing the administrator token.

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

## Production gate

The candidate is technically validated, but deployment remains blocked until Production's exact
Git HEAD, migration ledger and current managed patch state are captured. The available Production
account can confirm version 2026.10.0 and runtime health but cannot read the source tree. Run the
updater patch check/full preflight only after explicit approval. Do not combine this performance
patch with a Misskey version upgrade in the same change window.
