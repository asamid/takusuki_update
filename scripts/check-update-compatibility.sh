#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 asami

set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
readonly ROOT
readonly PATCH_ROOT="$ROOT/bundle/takusuki-update3-bundle/misskey-patches"

SOURCE=''
TAG=''
EXPECTED_COMMIT=''
FROM_REF=''
OUTPUT_DIR=''
MODE='patch'
FETCH=1
API_EQUIVALENCE=''
API_PERFORMANCE=''
WORKTREE_ROOT=''
WORKTREE=''
STARTED_AT=$(date --iso-8601=seconds)

usage() {
	cat <<'EOF'
Usage:
  check-update-compatibility.sh --source MISSKEY_GIT --tag VERSION --output-dir DIR [options]

Options:
  --expected-commit SHA     Require the tag to resolve to this exact commit
  --from-ref REF           Base ref used to inventory migration changes (default: source HEAD)
  --full                   Frozen install, targeted tests, SPDX check, and full build
  --api-equivalence FILE   API equivalence JSON; required with --full
  --api-performance FILE   API performance JSON; required with --full
  --no-fetch               Use existing refs without changing source Git metadata
  --help                   Show this help

Run this on a validation host, never against the Production source worktree.
EOF
}

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 2
}

while (($# > 0)); do
	case "$1" in
		--source) SOURCE=${2:?}; shift 2 ;;
		--tag) TAG=${2:?}; shift 2 ;;
		--expected-commit) EXPECTED_COMMIT=${2:?}; shift 2 ;;
		--from-ref) FROM_REF=${2:?}; shift 2 ;;
		--output-dir) OUTPUT_DIR=${2:?}; shift 2 ;;
		--full) MODE='full'; shift ;;
		--api-equivalence) API_EQUIVALENCE=${2:?}; shift 2 ;;
		--api-performance) API_PERFORMANCE=${2:?}; shift 2 ;;
		--no-fetch) FETCH=0; shift ;;
		--help|-h) usage; exit 0 ;;
		*) fail "unknown option: $1" ;;
	esac
done

[[ -n "$SOURCE" && -n "$TAG" && -n "$OUTPUT_DIR" ]] || fail '--source, --tag, and --output-dir are required'
[[ "$TAG" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]] || fail 'tag must be a stable YYYY.N.N version'
[[ -z "$EXPECTED_COMMIT" || "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail 'expected commit must be a full SHA-1'
[[ -d "$SOURCE/.git" || -f "$SOURCE/.git" ]] || fail 'source is not a Git worktree'
[[ -f "$PATCH_ROOT/series" && -f "$PATCH_ROOT/patch-manifest.tsv" ]] || fail 'managed patch metadata is missing'
if [[ "$MODE" == 'full' ]]; then
	[[ -r "$API_EQUIVALENCE" && -r "$API_PERFORMANCE" ]] || fail '--full requires readable API equivalence and performance JSON'
fi

SOURCE=$(cd -- "$SOURCE" && pwd -P)
mkdir -p "$OUTPUT_DIR/logs"
OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P)
readonly SOURCE OUTPUT_DIR
readonly STEPS_FILE="$OUTPUT_DIR/steps.tsv"
readonly PATCHES_FILE="$OUTPUT_DIR/patches.tsv"
readonly MIGRATIONS_FILE="$OUTPUT_DIR/migrations.txt"
: > "$STEPS_FILE"
: > "$PATCHES_FILE"
: > "$MIGRATIONS_FILE"

record_step() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$STEPS_FILE"
}

# shellcheck disable=SC2317
cleanup() {
	if [[ -n "$WORKTREE" && -e "$WORKTREE" ]]; then
		git -C "$SOURCE" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
	fi
	if [[ -n "$WORKTREE_ROOT" && -d "$WORKTREE_ROOT" ]]; then
		rm -rf -- "$WORKTREE_ROOT"
	fi
}
trap cleanup EXIT

remote_url=$(git -C "$SOURCE" remote get-url origin)
case "$remote_url" in
	https://github.com/misskey-dev/misskey.git|git@github.com:misskey-dev/misskey.git|ssh://git@github.com/misskey-dev/misskey.git)
		record_step official_remote PASS "$remote_url" ;;
	*) fail "unexpected Misskey origin: $remote_url" ;;
esac

if (( FETCH == 1 )); then
	if git -C "$SOURCE" fetch --prune origin '+refs/tags/*:refs/tags/*' '+refs/heads/*:refs/remotes/origin/*' >"$OUTPUT_DIR/logs/fetch.log" 2>&1; then
		record_step official_fetch PASS 'official refs fetched'
	else
		record_step official_fetch FAIL 'git fetch failed'
	fail 'official fetch failed'
	fi
else
	record_step official_fetch SKIP '--no-fetch selected'
fi

TARGET_COMMIT=$(git -C "$SOURCE" rev-parse --verify "refs/tags/$TAG^{commit}") || fail "tag not found: $TAG"
TAG_OBJECT=$(git -C "$SOURCE" cat-file -t "refs/tags/$TAG")
TARGET_VERSION=$(git -C "$SOURCE" show "$TARGET_COMMIT:package.json" | node -e "let s='';process.stdin.on('data',c=>s+=c).on('end',()=>process.stdout.write(JSON.parse(s).version ?? ''))")
[[ "$TARGET_VERSION" == "$TAG" ]] || fail "tag/package version mismatch: $TAG != $TARGET_VERSION"
if [[ -n "$EXPECTED_COMMIT" && "$TARGET_COMMIT" != "$EXPECTED_COMMIT" ]]; then
	fail "tag commit mismatch: expected $EXPECTED_COMMIT, got $TARGET_COMMIT"
fi
record_step official_target PASS "$TAG@$TARGET_COMMIT ($TAG_OBJECT tag object)"

FROM_REF=${FROM_REF:-HEAD}
FROM_COMMIT=$(git -C "$SOURCE" rev-parse --verify "$FROM_REF^{commit}") || fail "invalid --from-ref: $FROM_REF"
git -C "$SOURCE" diff --name-only "$FROM_COMMIT" "$TARGET_COMMIT" -- packages/backend/migration > "$MIGRATIONS_FILE"
MIGRATION_COUNT=$(wc -l < "$MIGRATIONS_FILE" | tr -d ' ')
record_step migration_inventory PASS "$MIGRATION_COUNT changed migration file(s) from $FROM_COMMIT"

WORKTREE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-compat.XXXXXXXX")
WORKTREE="$WORKTREE_ROOT/tree"
git -C "$SOURCE" worktree add --detach "$WORKTREE" "$TARGET_COMMIT" >"$OUTPUT_DIR/logs/worktree.log" 2>&1
record_step isolated_worktree PASS "$TARGET_COMMIT"

declare -A MANIFEST_SHA MANIFEST_REQUIRED MANIFEST_UPSTREAM
while IFS=$'\t' read -r id filename _description required _introduced upstream sha _added extra; do
	[[ "$id" == 'ID' || -z "$id" ]] && continue
	[[ -z "$extra" && "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "invalid patch manifest row: $filename"
	MANIFEST_SHA["$filename"]=$sha
	MANIFEST_REQUIRED["$filename"]=$required
	MANIFEST_UPSTREAM["$filename"]=$upstream
done < "$PATCH_ROOT/patch-manifest.tsv"

OVERALL='PASS'
while IFS= read -r patch; do
	[[ -z "$patch" || "$patch" == \#* ]] && continue
	[[ -n "${MANIFEST_SHA[$patch]:-}" && -r "$PATCH_ROOT/$patch" ]] || fail "series/manifest mismatch: $patch"
	[[ "${MANIFEST_REQUIRED[$patch]}" == 'required' ]] || fail "series contains non-required patch: $patch"
	actual_sha=$(sha256sum "$PATCH_ROOT/$patch" | awk '{print $1}')
	[[ "$actual_sha" == "${MANIFEST_SHA[$patch]}" ]] || fail "patch hash mismatch: $patch"
	if git -C "$WORKTREE" apply --check --whitespace=error-all "$PATCH_ROOT/$patch"; then
		git -C "$WORKTREE" apply --whitespace=error-all "$PATCH_ROOT/$patch"
		printf '%s\t%s\t%s\t%s\n' "$patch" APPLIES "$actual_sha" "${MANIFEST_UPSTREAM[$patch]}" >> "$PATCHES_FILE"
	elif git -C "$WORKTREE" apply --reverse --check "$PATCH_ROOT/$patch"; then
		printf '%s\t%s\t%s\t%s\n' "$patch" UPSTREAM_EQUIVALENT "$actual_sha" "${MANIFEST_UPSTREAM[$patch]}" >> "$PATCHES_FILE"
		[[ "$OVERALL" == 'FAIL' ]] || OVERALL='BLOCKED'
	else
		printf '%s\t%s\t%s\t%s\n' "$patch" CONFLICT "$actual_sha" "${MANIFEST_UPSTREAM[$patch]}" >> "$PATCHES_FILE"
		OVERALL='FAIL'
	fi
done < "$PATCH_ROOT/series"

if [[ "$OVERALL" == 'PASS' ]] && git -C "$WORKTREE" diff --check >"$OUTPUT_DIR/logs/diff-check.log" 2>&1; then
	record_step patch_series PASS 'all managed patches apply in order'
elif [[ "$OVERALL" == 'BLOCKED' ]]; then
	record_step patch_series BLOCKED 'one or more patches may already be upstream; removal requires review and tests'
else
	record_step patch_series FAIL 'patch conflict or whitespace error'
	OVERALL='FAIL'
fi

if [[ "$MODE" == 'full' && "$OVERALL" == 'PASS' ]]; then
	EXPECTED_PNPM=$(node -e "const p=require('$WORKTREE/package.json').packageManager||'';process.stdout.write(p.startsWith('pnpm@')?p.slice(5):'')")
	if (cd "$WORKTREE" && corepack "pnpm@$EXPECTED_PNPM" install --frozen-lockfile) >"$OUTPUT_DIR/logs/install.log" 2>&1; then
		record_step frozen_install PASS "pnpm@$EXPECTED_PNPM"
	else
		record_step frozen_install FAIL 'frozen install failed'; OVERALL='FAIL'
	fi

	if [[ "$OVERALL" == 'PASS' ]] && (cd "$WORKTREE/packages/backend" && corepack "pnpm@$EXPECTED_PNPM" exec vitest run \
		src/core/chart/charts/federation-blocked-host-query.test.ts \
		src/core/chart/charts/federation-blocked-host-query.integration.test.ts \
		src/misc/note-blocked-host-query.test.ts) >"$OUTPUT_DIR/logs/targeted-tests.log" 2>&1; then
		record_step targeted_tests PASS '25 managed-patch tests'
	else
		record_step targeted_tests FAIL 'targeted tests failed'; OVERALL='FAIL'
	fi

	if [[ "$OVERALL" == 'PASS' ]] && (cd "$WORKTREE" && node scripts/check-spdx.mjs) >"$OUTPUT_DIR/logs/spdx.log" 2>&1; then
		record_step spdx PASS 'SPDX check passed'
	else
		record_step spdx FAIL 'SPDX check failed'; OVERALL='FAIL'
	fi

	if [[ "$OVERALL" == 'PASS' ]] && (cd "$WORKTREE" && corepack "pnpm@$EXPECTED_PNPM" build) >"$OUTPUT_DIR/logs/build.log" 2>&1; then
		record_step full_build PASS 'pnpm build passed'
	else
		record_step full_build FAIL 'full build failed'; OVERALL='FAIL'
	fi

	if python3 - "$API_EQUIVALENCE" "$API_PERFORMANCE" <<'PY'
import json, sys
eq = json.load(open(sys.argv[1], encoding='utf-8'))
perf = json.load(open(sys.argv[2], encoding='utf-8'))
if eq.get('caseCount', 0) < 28 or eq.get('mismatchCount') != 0:
    raise SystemExit(1)
if perf.get('resultIdentity', {}).get('baseline') != perf.get('resultIdentity', {}).get('candidate'):
    raise SystemExit(1)
for group in perf.get('summary', {}).values():
    for sample in group.values():
        if sample.get('timeoutsOrFailures') != 0:
            raise SystemExit(1)
PY
	then
		record_step runtime_evidence PASS 'API equivalence and result identity passed'
	else
		record_step runtime_evidence FAIL 'API evidence failed validation'; OVERALL='FAIL'
	fi
elif [[ "$MODE" == 'full' ]]; then
	record_step full_validation SKIP 'patch gate did not pass'
else
	record_step full_validation SKIP 'patch mode selected'
fi

FINISHED_AT=$(date --iso-8601=seconds)
export STARTED_AT FINISHED_AT MODE OVERALL TAG TARGET_COMMIT TARGET_VERSION TAG_OBJECT REMOTE_URL="$remote_url"
export FROM_COMMIT MIGRATION_COUNT API_EQUIVALENCE API_PERFORMANCE
python3 - "$STEPS_FILE" "$PATCHES_FILE" "$MIGRATIONS_FILE" "$OUTPUT_DIR/release-decision.json" "$OUTPUT_DIR/release-decision.md" <<'PY'
import hashlib, json, os, pathlib, sys

steps_path, patches_path, migrations_path, json_path, markdown_path = map(pathlib.Path, sys.argv[1:])
def rows(path, names):
    result = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line:
            result.append(dict(zip(names, line.split('\t'))))
    return result
def digest(path_text):
    if not path_text:
        return None
    path = pathlib.Path(path_text)
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

data = {
    'schemaVersion': 1,
    'decision': os.environ['OVERALL'],
    'mode': os.environ['MODE'],
    'startedAt': os.environ['STARTED_AT'],
    'finishedAt': os.environ['FINISHED_AT'],
    'official': {
        'remote': os.environ['REMOTE_URL'], 'tag': os.environ['TAG'],
        'commit': os.environ['TARGET_COMMIT'], 'version': os.environ['TARGET_VERSION'],
        'tagObjectType': os.environ['TAG_OBJECT'],
    },
    'fromCommit': os.environ['FROM_COMMIT'],
    'migrationCount': int(os.environ['MIGRATION_COUNT']),
    'migrations': migrations_path.read_text(encoding='utf-8').splitlines(),
    'steps': rows(steps_path, ['name', 'status', 'detail']),
    'patches': rows(patches_path, ['filename', 'status', 'sha256', 'declaredUpstreamStatus']),
    'runtimeEvidence': {
        'apiEquivalence': digest(os.environ.get('API_EQUIVALENCE', '')),
        'apiPerformance': digest(os.environ.get('API_PERFORMANCE', '')),
    },
}
pathlib.Path(json_path).write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
lines = [
    '# Update compatibility decision', '',
    f"Decision: **{data['decision']}**", '',
    f"- Official target: `{data['official']['tag']}` / `{data['official']['commit']}`",
    f"- Source remote: `{data['official']['remote']}`",
    f"- Mode: `{data['mode']}`",
    f"- Migration files changed from base: `{data['migrationCount']}`", '',
    '## Steps', '', '| Step | Status | Detail |', '|---|---|---|',
]
for step in data['steps']:
    lines.append(f"| {step['name']} | {step['status']} | {step['detail']} |")
lines += ['', '## Managed patches', '', '| Patch | Status | SHA-256 |', '|---|---|---|']
for patch in data['patches']:
    lines.append(f"| {patch['filename']} | {patch['status']} | `{patch['sha256']}` |")
pathlib.Path(markdown_path).write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

sha256sum "$OUTPUT_DIR/release-decision.json" "$OUTPUT_DIR/release-decision.md" > "$OUTPUT_DIR/checksums.sha256"
printf 'UPDATE COMPATIBILITY: %s\nJSON: %s\nMarkdown: %s\n' "$OVERALL" \
	"$OUTPUT_DIR/release-decision.json" "$OUTPUT_DIR/release-decision.md"
case "$OVERALL" in PASS) exit 0 ;; BLOCKED) exit 20 ;; *) exit 1 ;; esac
