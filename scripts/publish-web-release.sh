#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

usage() {
	printf 'Usage: sudo %s ARTIFACT_DIR UPDATE3_WEB_ROOT RELEASE_ID [LEGACY_RELEASE_ID]\n' "$0" >&2
	exit 2
}

(($# == 3 || $# == 4)) || usage
ARTIFACT_DIR=$(realpath -e "$1")
readonly ARTIFACT_DIR
readonly WEB_ROOT=$2
readonly RELEASE_ID=$3
readonly LEGACY_RELEASE_ID=${4:-4.1.0}
readonly -a FILES=(
	takusuki_update5.sh
	takusuki_update5.sh.sha256
	takusuki-update5-bundle.zip
	takusuki-update5-bundle.zip.sha256
)

[[ "$RELEASE_ID" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid RELEASE_ID\n' >&2; exit 2; }
[[ "$LEGACY_RELEASE_ID" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid LEGACY_RELEASE_ID\n' >&2; exit 2; }
[[ "$WEB_ROOT" == /* && "$WEB_ROOT" != '/' ]] || { printf 'WEB_ROOT must be an absolute non-root path\n' >&2; exit 2; }
for file in "${FILES[@]}"; do [[ -f "$ARTIFACT_DIR/$file" && ! -L "$ARTIFACT_DIR/$file" ]] || { printf 'Missing artifact: %s\n' "$file" >&2; exit 1; }; done
(
	cd "$ARTIFACT_DIR"
	sha256sum -c takusuki_update5.sh.sha256
	sha256sum -c takusuki-update5-bundle.zip.sha256
	grep -Fxq "# Version: $RELEASE_ID" takusuki_update5.sh
	python3 - "$RELEASE_ID" <<'PYZIP'
import sys
import zipfile

with zipfile.ZipFile('takusuki-update5-bundle.zip') as archive:
    if archive.testzip() is not None:
        raise SystemExit('bundle ZIP CRC mismatch')
    meta = archive.read('takusuki-update3-bundle/bundle-manifest.tsv').decode().splitlines()
    ids = [row for row in meta if row.startswith('META\trelease_id\t')]
    if ids != [f'META\trelease_id\t{sys.argv[1]}']:
        raise SystemExit('bundle release ID mismatch')
PYZIP
)

parent=$(dirname -- "$WEB_ROOT")
name=$(basename -- "$WEB_ROOT")
mkdir -p "$parent"
exec 9>"$parent/.${name}.publish.lock"
flock -n 9 || { printf 'Another publication is in progress\n' >&2; exit 1; }
[[ ! -L "$WEB_ROOT" && ! -L "$WEB_ROOT/releases" ]] || { printf 'Web root and releases must not be symlinks\n' >&2; exit 1; }
[[ ! -e "$WEB_ROOT/releases/$RELEASE_ID" && ! -L "$WEB_ROOT/releases/$RELEASE_ID" ]] \
	|| { printf 'Immutable release already exists: %s\n' "$RELEASE_ID" >&2; exit 1; }
stage=$(mktemp -d "$parent/.${name}.publish.XXXXXXXX")
cleanup() { [[ -d "$stage" ]] && rm -rf -- "$stage"; }
trap cleanup EXIT

if [[ -d "$WEB_ROOT" ]]; then
	cp -a "$WEB_ROOT/." "$stage/"
else
	chmod 0755 "$stage"
fi
mkdir -p "$stage/releases/$RELEASE_ID"
for file in "${FILES[@]}"; do install -m 0644 "$ARTIFACT_DIR/$file" "$stage/releases/$RELEASE_ID/$file"; done

ln -sfnT "releases/$RELEASE_ID" "$stage/current"
for file in "${FILES[@]}"; do ln -sfnT "current/$file" "$stage/$file"; done

# Keep the v4 normal-name endpoints usable and pinned to their immutable
# release. V5 uses distinct filenames, so switching current never retargets a
# v4 client to incompatible assets.
readonly -a LEGACY_FILES=(
	takusuki_update3.sh
	takusuki_update3.sh.sha256
	takusuki-update3-bundle.zip
	takusuki-update3-bundle.zip.sha256
)
for file in "${LEGACY_FILES[@]}"; do
	[[ -f "$stage/releases/$LEGACY_RELEASE_ID/$file" ]] || { printf 'Missing immutable legacy artifact: %s\n' "$file" >&2; exit 1; }
	if [[ -e "$WEB_ROOT/$file" ]]; then
		cmp -s "$WEB_ROOT/$file" "$stage/releases/$LEGACY_RELEASE_ID/$file" \
			|| { printf 'Legacy URL differs from its pinned release: %s\n' "$file" >&2; exit 1; }
	fi
	ln -sfnT "releases/$LEGACY_RELEASE_ID/$file" "$stage/$file"
done

# Exchange the complete directory tree in one renameat2 syscall. Readers see
# either the old four-file set or the new internally consistent set.
if [[ -e "$WEB_ROOT" ]]; then
	python3 - "$stage" "$WEB_ROOT" <<'PY'
import ctypes
import os
import sys

source, target = map(os.fsencode, sys.argv[1:])
libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, source, -100, target, 2) != 0:  # AT_FDCWD, RENAME_EXCHANGE
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PY
	previous=$stage
	stage='' # After the exchange the old live tree must never be cleaned up.
	backup="$parent/.${name}.previous.${previous##*.}"
	if mv -T -- "$previous" "$backup"; then
		printf 'Previous tree: %s\n' "$backup"
	else
		printf 'Previous tree retained at: %s\n' "$previous" >&2
	fi
else
	mv -T -- "$stage" "$WEB_ROOT"
	stage=''
fi
trap - EXIT
printf 'WEB RELEASE PUBLISHED: %s -> %s/releases/%s\n' "$WEB_ROOT" "$WEB_ROOT" "$RELEASE_ID"
