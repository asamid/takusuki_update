#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly ROOT
readonly OUTPUT_DIR="${1:-$ROOT/dist/release}"

mkdir -p "$OUTPUT_DIR"
"$ROOT/scripts/build-bundle.sh" "$OUTPUT_DIR"
install -m 0755 "$ROOT/takusuki_update5.sh" "$OUTPUT_DIR/takusuki_update5.sh"
(
	cd "$OUTPUT_DIR"
	sha256sum takusuki_update5.sh > takusuki_update5.sh.sha256
	sha256sum takusuki-update5-bundle.zip > takusuki-update5-bundle.zip.sha256
)

printf 'RELEASE ASSETS: PASS\nOutput: %s\n' "$OUTPUT_DIR"
sha256sum "$OUTPUT_DIR/takusuki_update5.sh" "$OUTPUT_DIR/takusuki-update5-bundle.zip"
