#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
source_repo=$(realpath -e "${1:?provide isolated official Misskey source}")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-instance.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export FIX_GIT FIX_NODE FIX_BIN="$tmp/bin"
FIX_GIT=$(command -v git)
FIX_NODE=$(command -v node)
export PATH="$FIX_BIN:$PATH"

cat > "$FIX_BIN/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "$*" in
	'list-unit-files --type=service --no-legend') printf '%s enabled\n' "$FIX_SERVICE"; exit ;;
	"cat $FIX_SERVICE") exit ;;
	"is-active $FIX_SERVICE") printf 'active\n'; exit ;;
	"show -p "*" --value $FIX_SERVICE") ;;
	*) printf 'unexpected or mutating systemctl: %s\n' "$*" >&2; exit 9 ;;
esac
case "$3" in
	WorkingDirectory) printf '%s\n' "$FIX_DIR" ;;
	User) printf '%s\n' "$FIX_USER" ;;
	Group) printf '%s\n' "$FIX_GROUP" ;;
	DynamicUser) printf 'no\n' ;;
	Type) printf 'simple\n' ;;
	RootDirectory|RootImage|EnvironmentFiles|Environment) ;;
	ExecStart) printf '{ path=%s/node ; argv[]=%s/node ./scripts/start.mjs ; ignore_errors=no ; }\n' "$FIX_BIN" "$FIX_BIN" ;;
	*) exit 10 ;;
esac
MOCK
cat > "$FIX_BIN/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == -C && "${3:-}" == fetch ]]; then exit 0; fi
exec "$FIX_GIT" "$@"
MOCK
cat > "$FIX_BIN/corepack" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == 'pnpm@12.17.0 --version' && -f scripts/start.mjs && "$PWD" != "$FIX_DIR" ]] || exit 11
printf '12.17.0\n'
MOCK
cat > "$FIX_BIN/node" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == '--version' ]]; then printf 'v26.13.1\n'; exit; fi
exec "$FIX_NODE" "$@"
MOCK
cat > "$FIX_BIN/id" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
	-un) printf '%s\n' "$FIX_USER" ;;
	"-gn $FIX_USER") printf '%s\n' "$FIX_GROUP" ;;
	*) exec /usr/bin/id "$@" ;;
esac
MOCK
cat > "$FIX_BIN/getent" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
	"passwd $FIX_USER") printf '%s:x:1001:1001::%s:/bin/bash\n' "$FIX_USER" "$FIX_HOME" ;;
	"group $FIX_GROUP") printf '%s:x:1001:\n' "$FIX_GROUP" ;;
	*) exit 2 ;;
esac
MOCK
cat > "$FIX_BIN/systemd-detect-virt" <<'MOCK'
#!/usr/bin/env bash
# Fixture represents a non-container Ubuntu systemd host.
exit 1
MOCK
cat > "$FIX_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
# Simulated outage only. The updater must validate the seeded cache itself.
exit 7
MOCK
chmod +x "$FIX_BIN/"*
"$ROOT/scripts/prepare-release-assets.sh" "$tmp/assets" >/dev/null
export FIX_DIR FIX_USER FIX_GROUP FIX_SERVICE FIX_HOME FIX_PORT
export BUNDLE_CACHE_DIR="$tmp/cache"
mkdir -p "$BUNDLE_CACHE_DIR"
cp "$tmp/assets/takusuki-update5-bundle.zip" "$BUNDLE_CACHE_DIR/bundle.zip"
cp "$tmp/assets/takusuki-update5-bundle.zip.sha256" "$BUNDLE_CACHE_DIR/bundle.zip.sha256"

for instance in one two; do
	case "$instance" in
		one) FIX_DIR="$tmp/opt/app-one"; FIX_SERVICE=fediverse-a.service; FIX_USER=fedi_a; FIX_GROUP=group_a; FIX_PORT=4101 ;;
		two) FIX_DIR="$tmp/srv/instance two"; FIX_SERVICE=community-b.service; FIX_USER=fedi_b; FIX_GROUP=group_b; FIX_PORT=8270 ;;
	esac
	FIX_HOME="$tmp/home/$FIX_USER"
	mkdir -p "$FIX_HOME"
	git clone --quiet --shared --no-tags "$source_repo" "$FIX_DIR"
	git -C "$FIX_DIR" remote set-url origin https://github.com/misskey-dev/misskey.git
	git -C "$FIX_DIR" tag 2026.11.0 HEAD
	mkdir -p "$FIX_DIR/.config" "$FIX_DIR/packages/backend/built" "$FIX_DIR/packages/backend/node_modules/"{pg,ioredis}
	printf '{"port":%s,"db":{"db":"%s"}}\n' "$FIX_PORT" "$instance" > "$FIX_DIR/.config/default.yml"
	cat > "$FIX_DIR/packages/backend/built/config.js" <<'NODE'
import { readFileSync } from 'node:fs';
export const loadConfig = () => JSON.parse(readFileSync('.config/default.yml'));
NODE
	cat > "$FIX_DIR/packages/backend/node_modules/pg/index.js" <<'NODE'
exports.Client = class {
	constructor(config) {
		if (!['one', 'two'].includes(config.database)) throw Error('wrong database');
	}
	async connect() {}
	async end() {}
	async query() {
		return { rows: [{ postgres_version: 16, pgroonga_version: null, migration_count: '1', latest_migration: 'fixture' }] };
	}
};
NODE
	cat > "$FIX_DIR/packages/backend/node_modules/ioredis/index.js" <<'NODE'
module.exports = class {
	async connect() {}
	async ping() { return 'PONG'; }
	disconnect() {}
};
NODE
	args=(--tag 2026.11.0 --check --advanced --bundle-file "$tmp/assets/takusuki-update5-bundle.zip" --bundle-sha-file "$tmp/assets/takusuki-update5-bundle.zip.sha256")
	# Exercise explicit service => directory and explicit directory => service.
	if [[ "$instance" == one ]]; then select=(SERVICE_NAME="${FIX_SERVICE%.service}"); else select=(MISSKEY_DIR="$FIX_DIR"); fi
	run_check() {
		env -u MISSKEY_DIR -u MISSKEY_USER -u SERVICE_NAME -u HEALTH_LOCAL_URL -u HEALTH_API_URL \
			"${select[@]}" MIN_FREE_KB=0 XDG_STATE_HOME="$tmp/state" "$ROOT/takusuki_update5.sh" "$@"
	}
	run_check "${args[@]}" > "$tmp/$instance.log" 2>&1 || { cat "$tmp/$instance.log"; exit 1; }
	grep -Fq 'official-unpatched (0/5 patches' "$tmp/$instance.log"
	grep -Fq "Local health: http://127.0.0.1:$FIX_PORT/ ; http://127.0.0.1:$FIX_PORT/api/meta" "$tmp/$instance.log"
	grep -Fq 'DRY RUN COMPLETE' "$tmp/$instance.log"
	git -C "$FIX_DIR" diff --quiet HEAD
	if [[ "$instance" == one ]]; then
		# Extra unknown tracked changes must be refused before runtime probes.
		printf '\ncustom\n' >> "$FIX_DIR/package.json"
		if run_check "${args[@]}" > "$tmp/conflict.log" 2>&1; then exit 1; fi
		grep -Fq 'unknown tracked source modification' "$tmp/conflict.log"
		git -C "$FIX_DIR" restore package.json
	fi
done
[[ $(find "$tmp/state" -name .instance | sort -u | wc -l) == 2 ]]
# Exercise the ordinary download path (offline with an authentic local cache).
run_check --tag 2026.11.0 --check > "$tmp/cache.log" 2>&1 || { cat "$tmp/cache.log"; exit 1; }
grep -Fq 'verified cache fallback' "$tmp/cache.log"
# A ZIP with internally valid file hashes and its correct sidecar can still
# describe the wrong release. Test that through the real fallback path.
python3 - "$BUNDLE_CACHE_DIR/bundle.zip" <<'PY'
import pathlib, sys, zipfile
out = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(out) as z:
    files = {f: z.read(f) for f in z.namelist()}
meta = 'takusuki-update3-bundle/bundle-manifest.tsv'
files[meta] = files[meta].replace(b'release_id\t5.1.2', b'release_id\t5.1.1')
with zipfile.ZipFile(out, 'w') as z:
    for name, data in files.items():
        z.writestr(name, data)
PY
(cd "$BUNDLE_CACHE_DIR" && sha256sum bundle.zip > bundle.zip.sha256)
if run_check --check --tag 2026.11.0 > "$tmp/stale.log" 2>&1; then exit 1; fi
grep -Fq 'bundle release ID mismatch' "$tmp/stale.log"
printf 'TWO INSTANCE PREFLIGHTS, CUSTOM SOURCE REJECTION AND CACHE RELEASE PIN: PASS\n'
