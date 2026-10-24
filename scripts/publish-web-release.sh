#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

usage() {
	printf 'Usage: sudo %s ARTIFACT_DIR UPDATE3_WEB_ROOT RELEASE_ID [OLD_RELEASE_ID]\n' "$0" >&2
	exit 2
}

(($# == 3 || $# == 4)) || usage
ARTIFACT_DIR=$(realpath -e "$1")
readonly ARTIFACT_DIR
readonly WEB_ROOT=$2
readonly RELEASE_ID=$3
readonly OLD_RELEASE_ID=${4:-}
readonly -a FILES=(
	takusuki_update3.sh
	takusuki_update3.sh.sha256
	takusuki-update3-bundle.zip
	takusuki-update3-bundle.zip.sha256
)

[[ "$RELEASE_ID" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid RELEASE_ID\n' >&2; exit 2; }
[[ -z "$OLD_RELEASE_ID" || "$OLD_RELEASE_ID" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid OLD_RELEASE_ID\n' >&2; exit 2; }
[[ "$WEB_ROOT" == /* && "$WEB_ROOT" != '/' ]] || { printf 'WEB_ROOT must be an absolute non-root path\n' >&2; exit 2; }
for file in "${FILES[@]}"; do [[ -f "$ARTIFACT_DIR/$file" && ! -L "$ARTIFACT_DIR/$file" ]] || { printf 'Missing artifact: %s\n' "$file" >&2; exit 1; }; done
(
	cd "$ARTIFACT_DIR"
	sha256sum -c takusuki_update3.sh.sha256
	sha256sum -c takusuki-update3-bundle.zip.sha256
)

parent=$(dirname -- "$WEB_ROOT")
name=$(basename -- "$WEB_ROOT")
mkdir -p "$parent"
stage=$(mktemp -d "$parent/.${name}.publish.XXXXXXXX")
cleanup() { [[ -d "$stage" ]] && rm -rf -- "$stage"; }
trap cleanup EXIT

if [[ -d "$WEB_ROOT" ]]; then cp -a "$WEB_ROOT/." "$stage/"; fi
mkdir -p "$stage/releases/$RELEASE_ID"
for file in "${FILES[@]}"; do install -m 0644 "$ARTIFACT_DIR/$file" "$stage/releases/$RELEASE_ID/$file"; done

if [[ -n "$OLD_RELEASE_ID" && -d "$WEB_ROOT" && ! -e "$stage/releases/$OLD_RELEASE_ID" ]]; then
	mkdir -p "$stage/releases/$OLD_RELEASE_ID"
	for file in "${FILES[@]}"; do
		[[ -f "$WEB_ROOT/$file" ]] || { printf 'Cannot archive old public file: %s\n' "$file" >&2; exit 1; }
		install -m 0644 "$WEB_ROOT/$file" "$stage/releases/$OLD_RELEASE_ID/$file"
	done
fi

ln -sfn "releases/$RELEASE_ID" "$stage/current"
for file in "${FILES[@]}"; do ln -sfn "current/$file" "$stage/$file"; done

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
	backup="$parent/.${name}.previous.$(date -u +%Y%m%dT%H%M%SZ)"
	mv -- "$stage" "$backup"
	stage=''
	printf 'Previous tree: %s\n' "$backup"
else
	mv -- "$stage" "$WEB_ROOT"
	stage=''
fi
trap - EXIT
printf 'WEB RELEASE PUBLISHED: %s -> %s/releases/%s\n' "$WEB_ROOT" "$WEB_ROOT" "$RELEASE_ID"
