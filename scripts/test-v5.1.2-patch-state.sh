#!/usr/bin/env bash
# shellcheck disable=SC2034  # Globals consumed by extracted updater functions.
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
MISSKEY_DIR=$(realpath -e "${1:?pass isolated 2026.11.0 checkout with all five patches applied}")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-040-state.XXXXXXXX")
trap 'git -C "$MISSKEY_DIR" worktree remove --force "$tmp/official" 2>/dev/null || true; rm -rf "$tmp"' EXIT
PATCH_DIR="$tmp/patches"
cp -r "$ROOT/bundle/takusuki-update3-bundle/misskey-patches" "$PATCH_DIR"
PATCH_ONLY=1 UPDATE_FLAVOR=patched TARGET_PATCH_COUNT=0
TEMPORARY_PATCH='040-avatar-decoration-category-sort.patch'
MISSKEY_USER=$(id -un) MISSKEY_GROUP=$(id -gn)
SERIES_FILE="$PATCH_DIR/series"
MANIFEST_FILE="$PATCH_DIR/patch-manifest.tsv"
UPDATER_VERSION=5.1.2 BUNDLE_RELEASE_ID=5.1.2
ASSET_ACTUAL=$(sha256sum "$ROOT/bundle/takusuki-update3-bundle/assets/unknown.png")
ASSET_ACTUAL=${ASSET_ACTUAL%% *}

# shellcheck disable=SC2329
as_misskey() { "$@"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
# shellcheck disable=SC2329
step() { :; }
{
	sed -n '/^safe_relative_path() {/,/^verify_zip_sidecar() {/p' "$ROOT/takusuki_update5.sh" | sed '$d'
	sed -n '/^declare -A PATCH_ID/,/^load_patch_metadata$/p' "$ROOT/takusuki_update5.sh"
	sed -n '/^collect_patch_managed_paths() {/,/^collect_patch_managed_paths$/p' "$ROOT/takusuki_update5.sh"
	sed -n '/^avatar_sort_snapshot() {/,/^check_patch_series$/p' "$ROOT/takusuki_update5.sh" | sed '$d'
	sed -n '/^write_patch_state_files() {/,/^run_rollback() {/p' "$ROOT/takusuki_update5.sh" | sed '$d'
} > "$tmp/functions"
# shellcheck disable=SC1091
source "$tmp/functions"

classify_current_source
[[ "$SOURCE_PATCH_COUNT" == 5 ]] || fail 'expected legacy full patch stack'
write_patch_state_files "$tmp" prior.tsv prior-series "$SOURCE_PATCH_COUNT"
cmp "$tmp/prior-series" "$SERIES_FILE"
git -C "$MISSKEY_DIR" diff --binary > "$tmp/prior.diff"

# Create an official-style baseline with the frontend change in HEAD, and verify
# that a reverse-applicable patch alone is not accepted. Never touch real refs.
git -C "$MISSKEY_DIR" worktree add --quiet --detach "$tmp/official" HEAD
git -C "$tmp/official" apply "$PATCH_DIR/$TEMPORARY_PATCH"
git -C "$tmp/official" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qam 'Simulate verified upstream categorization'
TARGET_COMMIT=$(git -C "$tmp/official" rev-parse HEAD)
if avatar_sort_is_upstream "$tmp/official" "$TARGET_COMMIT"; then fail 'unreviewed source recognized as upstream'; fi
# Exercise the gate, including an unreviewed reverse-applicable target.
export TMPDIR="$tmp"
set +e
( set -e; check_patch_series ) > "$tmp/conflict.log" 2>&1
rc=$?
set -e
if [[ "$rc" != 20 ]] || ! grep -Fq CONFLICT "$tmp/conflict.log"; then fail 'unreviewed target did not fail closed'; fi
# Cleanup the intentionally failed standalone gate (the runtime EXIT trap normally does this).
while IFS= read -r path; do
	case "$path" in "${TMPDIR:-/tmp}"/takusuki-update5.*/tree)
		[[ "$(git -C "$path" rev-parse HEAD)" == "$TARGET_COMMIT" ]] || continue
		git -C "$MISSKEY_DIR" worktree remove --force "$path"
		rmdir "${path%/tree}"
	;; esac
done < <(git -C "$MISSKEY_DIR" worktree list --porcelain | sed -n 's/^worktree //p')

avatar_sort_snapshot "$tmp/official" "$TARGET_COMMIT" | sha256sum | cut -d' ' -f1 >> "$PATCH_DIR/040-upstream-snapshots.txt"
PATCH_UPSTREAM["$TEMPORARY_PATCH"]=retired
check_patch_series
[[ "$TARGET_PATCH_COUNT" == 4 ]] || fail '040 was not skipped'
write_patch_state_files "$tmp" next.tsv next-series "$TARGET_PATCH_COUNT"
cmp "$tmp/next-series" <(head -n 4 "$SERIES_FILE")
# Retiring the patch must leave the old state and rollback diff recognizable.
classify_current_source
[[ "$SOURCE_PATCH_COUNT" == 5 ]] || fail 'retired patch was forgotten for source classification'
git -C "$MISSKEY_DIR" apply --reverse "$PATCH_DIR/$TEMPORARY_PATCH"
classify_current_source
[[ "$SOURCE_PATCH_COUNT" == 4 ]] || fail 'expected 001/010/020/030 only'
git -C "$MISSKEY_DIR" apply "$PATCH_DIR/$TEMPORARY_PATCH"
cmp "$tmp/prior.diff" <(git -C "$MISSKEY_DIR" diff --binary)
printf '040 SOURCE AND TARGET STATES: PASS\n'
