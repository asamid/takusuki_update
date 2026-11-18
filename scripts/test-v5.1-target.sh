#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly ROOT
SOURCE=${1:-}
TEMP_ROOT=''
cleanup() { [[ -z "$TEMP_ROOT" ]] || rm -rf -- "$TEMP_ROOT"; }
trap cleanup EXIT

if [[ -z "$SOURCE" ]]; then
	TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-v5.1-target.XXXXXXXX")
	SOURCE="$TEMP_ROOT/misskey"
	git clone --quiet --depth 1 --branch 2026.11.0 https://github.com/misskey-dev/misskey.git "$SOURCE"
	git -C "$SOURCE" fetch --quiet --depth 1 origin refs/tags/2026.10.1:refs/tags/2026.10.1
else
	SOURCE=$(realpath -e "$SOURCE")
fi

assert_eq() {
	[[ "$1" == "$2" ]] || { printf 'ASSERTION FAILED: expected <%s>, got <%s>\n' "$2" "$1" >&2; exit 1; }
}

assert_eq "$(git -C "$SOURCE" rev-parse HEAD)" 'dd7b4905d715d2587fa2f2cb6a88ecac8878ef0d'
assert_eq "$(node -p "require('$SOURCE/package.json').version")" '2026.11.0'
assert_eq "$(node -p "require('$SOURCE/packages/backend/package.json').engines.node")" '^24.22.3 || ^26.13.1'
[[ -f "$SOURCE/scripts/start.mjs" ]]

patch_count=0
while IFS= read -r patch; do
	[[ -n "$patch" ]] || continue
	git -C "$SOURCE" apply --check --whitespace=error-all \
		"$ROOT/bundle/takusuki-update3-bundle/misskey-patches/$patch"
	git -C "$SOURCE" apply --whitespace=error-all \
		"$ROOT/bundle/takusuki-update3-bundle/misskey-patches/$patch"
	((patch_count += 1))
done < "$ROOT/bundle/takusuki-update3-bundle/misskey-patches/series"
assert_eq "$patch_count" '5'
git -C "$SOURCE" diff --check
node --experimental-strip-types "$ROOT/scripts/test-avatar-decoration-sort.mjs" "$SOURCE"
"$ROOT/scripts/test-v5.1.2-patch-state.sh" "$SOURCE"
"$ROOT/scripts/test-v5.1.2-instances.sh" "$SOURCE"

mapfile -t migration_diff < <(git -C "$SOURCE" diff --name-status 2026.10.1..HEAD -- packages/backend/migration)
assert_eq "${#migration_diff[@]}" '3'
printf '%s\n' "${migration_diff[@]}" | grep -F $'A\tpackages/backend/migration/1794385801836-FixMetaMigratedConfigColumnDefaults.js' >/dev/null
printf '%s\n' "${migration_diff[@]}" | grep -F $'A\tpackages/backend/migration/js/migration-config.js' >/dev/null

printf '2026.11.0 TARGET: PASS (5 patches; migration diff recorded)\n'
