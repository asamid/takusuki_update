#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly ROOT
readonly EXPECTED_UPDATER_SHA256='e12584d4d7457760574174ee22c0a5cd19bc7eea80a416e9b646b79a8a3fad44'
readonly EXPECTED_BUNDLE_SHA256='827da22c6d4e9e1a3f05334df4f1de7bd988d4138973c73961e514b8c1bd067b'
BUILD_DIR=$(mktemp -d /tmp/takusuki-update5-verify.XXXXXXXX)
trap 'rm -rf -- "$BUILD_DIR"' EXIT

command -v bash >/dev/null
command -v python3 >/dev/null
command -v node >/dev/null
command -v sha256sum >/dev/null
command -v shellcheck >/dev/null || {
	printf 'ShellCheck is required.\n' >&2
	exit 1
}

bash -n "$ROOT/takusuki_update5.sh"
node --check "$ROOT/scripts/test-blocked-host-transition.mjs"
shellcheck "$ROOT/takusuki_update5.sh" "$ROOT/scripts/build-bundle.sh" \
	"$ROOT/scripts/check-update-compatibility.sh" "$ROOT/scripts/prepare-release-assets.sh" \
	"$ROOT/scripts/publish-web-release.sh" "$ROOT/scripts/staging-v5-validation-lab.sh" \
	"$ROOT/scripts/test-fixtures/corepack-fail-stage.sh" "$0"

updater_sha256=$(sha256sum "$ROOT/takusuki_update5.sh" | awk '{print $1}')
[[ "$EXPECTED_UPDATER_SHA256" == 'TO_BE_FILLED_AFTER_IMPLEMENTATION' || "$updater_sha256" == "$EXPECTED_UPDATER_SHA256" ]] || {
	printf 'Updater SHA mismatch: %s\n' "$updater_sha256" >&2
	exit 1
}

"$ROOT/scripts/build-bundle.sh" "$BUILD_DIR"
bundle="$BUILD_DIR/takusuki-update5-bundle.zip"
bundle_sha256=$(sha256sum "$bundle" | awk '{print $1}')
[[ "$EXPECTED_BUNDLE_SHA256" == 'TO_BE_FILLED_AFTER_REPRODUCIBLE_BUILD' || "$bundle_sha256" == "$EXPECTED_BUNDLE_SHA256" ]] || {
	printf 'Bundle SHA mismatch: %s\n' "$bundle_sha256" >&2
	exit 1
}

python3 - "$bundle" <<'PY'
import pathlib
import stat
import sys
import zipfile

path = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    if archive.testzip() is not None:
        raise SystemExit('ZIP CRC validation failed')
    seen = set()
    for info in archive.infolist():
        name = info.filename
        parts = pathlib.PurePosixPath(name).parts
        mode = (info.external_attr >> 16) & 0o170000
        if name in seen or name.startswith('/') or '\\' in name or '..' in parts:
            raise SystemExit(f'unsafe ZIP entry: {name}')
        if not name.startswith('takusuki-update3-bundle/'):
            raise SystemExit(f'unexpected ZIP root: {name}')
        if mode not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise SystemExit(f'unsupported ZIP type: {name}')
        seen.add(name)
PY

python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
excluded_parts = {'.git', 'dist'}
patterns = {
    'private key': re.compile(rb'-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----'),
    'GitHub token': re.compile(rb'\b(?:gh[opsu]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'),
    'AWS access key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'database URL value': re.compile(rb'(?i)DATABASE_URL\s*=\s*["\x27]?[a-z][a-z0-9+.-]*://'),
    'authorization value': re.compile(rb'(?i)Authorization\s*[:=]\s*["\x27]?Bearer\s+[A-Za-z0-9._~+/=-]{12,}'),
}
for path in root.rglob('*'):
    if not path.is_file() or any(part in excluded_parts for part in path.parts):
        continue
    data = path.read_bytes()
    for label, pattern in patterns.items():
        if pattern.search(data):
            raise SystemExit(f'secret audit failed ({label}): {path.relative_to(root)}')
print('SECRET AUDIT: PASS')
PY

python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys
from urllib.parse import unquote

root = pathlib.Path(sys.argv[1])
readme = root / 'README.md'
for target in re.findall(r'\[[^]]+\]\(([^)]+)\)', readme.read_text(encoding='utf-8')):
    if re.match(r'^(?:https?://|mailto:|#)', target):
        continue
    path_text = unquote(target.split('#', 1)[0])
    if not (root / path_text).exists():
        raise SystemExit(f'broken local README link: {target}')
print('README LOCAL LINKS: PASS')
PY

printf 'UPDATER SHA-256: %s\nBUNDLE SHA-256: %s\nRELEASE VERIFICATION: PASS\n' \
	"$updater_sha256" "$bundle_sha256"
