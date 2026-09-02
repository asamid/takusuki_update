#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly ROOT
readonly SOURCE="$ROOT/bundle/takusuki-update3-bundle"
readonly EXPECTED_SHA256='f1d69fcbdf292a42062f60d83917ad1c82504b28964d98c13711ebd4122372d5'
readonly OUTPUT_DIR="${1:-$ROOT/dist}"

[[ -d "$SOURCE" ]] || { printf 'Missing bundle source: %s\n' "$SOURCE" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"
TEMP_ZIP="$(mktemp "$OUTPUT_DIR/.takusuki-update3-bundle.XXXXXXXX.zip")"
readonly TEMP_ZIP
trap 'rm -f -- "$TEMP_ZIP"' EXIT

python3 - "$SOURCE" "$TEMP_ZIP" <<'PY'
import hashlib
import pathlib
import stat
import sys
import zipfile

source = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2])
manifest = source / 'bundle-manifest.tsv'
if not manifest.is_file():
    raise SystemExit('bundle-manifest.tsv is missing')

listed = set()
meta = {}
for line_no, line in enumerate(manifest.read_text(encoding='utf-8').splitlines(), 1):
    fields = line.split('\t')
    if fields[0] == 'META' and len(fields) == 3:
        meta[fields[1]] = fields[2]
        continue
    if fields[0] != 'FILE' or len(fields) != 4:
        raise SystemExit(f'invalid manifest row {line_no}')
    rel, expected_hash, expected_size = fields[1:]
    rel_path = pathlib.PurePosixPath(rel)
    if rel.startswith('/') or '..' in rel_path.parts or '\\' in rel or rel in listed:
        raise SystemExit(f'unsafe or duplicate manifest path: {rel}')
    path = source / rel
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f'missing or unsupported file: {rel}')
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_hash or len(data) != int(expected_size):
        raise SystemExit(f'manifest mismatch: {rel}')
    listed.add(rel)

if meta.get('bundle_version') != '1' or meta.get('minimum_updater_version') != '4.0.0':
    raise SystemExit('unsupported bundle metadata')
actual = {
    p.relative_to(source).as_posix()
    for p in source.rglob('*')
    if p.is_file() and p.name != 'bundle-manifest.tsv'
}
if actual != listed:
    raise SystemExit(f'manifest inventory mismatch: missing={sorted(listed-actual)} extra={sorted(actual-listed)}')
for path in source.rglob('*'):
    if path.is_symlink() or not (path.is_file() or path.is_dir()):
        raise SystemExit(f'unsupported source entry: {path}')

root = source.parent
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if path.is_dir():
            info = zipfile.ZipInfo(relative + '/', (1980, 1, 1, 0, 0, 0))
            info.external_attr = (stat.S_IFDIR | 0o755) << 16
            archive.writestr(info, b'')
        else:
            info = zipfile.ZipInfo(relative, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(
                info,
                path.read_bytes(),
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=9,
            )
PY

actual_sha256=$(sha256sum "$TEMP_ZIP" | awk '{print $1}')
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
	printf 'Bundle is not byte-identical to the Live Staging artifact.\nExpected: %s\nActual:   %s\n' \
		"$EXPECTED_SHA256" "$actual_sha256" >&2
	exit 1
fi

mv -f -- "$TEMP_ZIP" "$OUTPUT_DIR/takusuki-update3-bundle.zip"
trap - EXIT
printf 'BUNDLE BUILD: PASS\nSHA-256: %s\nOutput: %s\n' \
	"$actual_sha256" "$OUTPUT_DIR/takusuki-update3-bundle.zip"
