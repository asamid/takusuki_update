#!/usr/bin/env bash
set -Eeuo pipefail
(($# == 2)) || { printf 'Usage: %s MISSKEY_GIT REVIEWED_OFFICIAL_COMMIT\n' "$0" >&2; exit 2; }
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
source_dir=$(realpath -e -- "$1")
commit=$(git -C "$source_dir" rev-parse --verify "$2^{commit}")
# shellcheck disable=SC2317,SC2329  # Used by the updater function loaded below.
as_misskey() { "$@"; }
# shellcheck disable=SC1090,SC1091
source <(sed -n '/^avatar_sort_snapshot() {/,/^avatar_sort_is_upstream() {/p' "$ROOT/takusuki_update5.sh" | sed '$d')
avatar_sort_snapshot "$source_dir" "$commit" | sha256sum | cut -d' ' -f1
