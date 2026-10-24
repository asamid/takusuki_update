#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Creates a disposable, localhost-only Misskey validation instance on 192.168.100.62.
set -Eeuo pipefail
umask 077

readonly EXPECTED_STAGING_IP='192.168.100.62'
readonly LAB_ROOT='/srv/takusuki-v5-validation'
readonly SOURCE_DIR="$LAB_ROOT/misskey"
readonly ARTIFACT_DIR=${1:-}
readonly PG_UNIT='takusuki-v5-validation-pg.service'
readonly REDIS_UNIT='takusuki-v5-validation-redis.service'
readonly MISSKEY_UNIT='takusuki-v5-validation.service'
readonly PG_BIN='/usr/lib/postgresql/15/bin'
readonly PG_SOCKET="$LAB_ROOT/pgsocket"
readonly PG_PORT='55433'
readonly REDIS_PORT='6385'
readonly MISSKEY_PORT='3105'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'run as root on Staging'
[[ " ${STAGING_ACK:-} " == " $EXPECTED_STAGING_IP " ]] || fail "set STAGING_ACK=$EXPECTED_STAGING_IP"
hostname -I | tr ' ' '\n' | grep -Fxq "$EXPECTED_STAGING_IP" || fail 'this host is not the approved Staging address'
[[ -d "$ARTIFACT_DIR" ]] || fail 'release artifact directory is required'
[[ ! -e "$LAB_ROOT" ]] || fail "lab root already exists; refusing overwrite: $LAB_ROOT"
for unit in "$PG_UNIT" "$REDIS_UNIT" "$MISSKEY_UNIT"; do
	[[ ! -e "/etc/systemd/system/$unit" ]] || fail "unit already exists: $unit"
done
for file in takusuki_update5.sh takusuki_update5.sh.sha256 takusuki-update5-bundle.zip takusuki-update5-bundle.zip.sha256; do
	[[ -f "$ARTIFACT_DIR/$file" && ! -L "$ARTIFACT_DIR/$file" ]] || fail "artifact missing: $file"
done
(
	cd "$ARTIFACT_DIR"
	sha256sum -c takusuki_update5.sh.sha256
	sha256sum -c takusuki-update5-bundle.zip.sha256
)

install -d -o asami -g asami -m 0750 "$LAB_ROOT" "$LAB_ROOT/artifacts" "$LAB_ROOT/redis" "$PG_SOCKET"
install -d -o root -g root -m 0700 "$LAB_ROOT/state" "$LAB_ROOT/log" "$LAB_ROOT/cache"
install -o root -g root -m 0755 "$ARTIFACT_DIR/takusuki_update5.sh" "$LAB_ROOT/artifacts/takusuki_update5.sh"
install -o root -g root -m 0644 "$ARTIFACT_DIR/takusuki-update5-bundle.zip" "$LAB_ROOT/artifacts/takusuki-update5-bundle.zip"
install -o root -g root -m 0644 "$ARTIFACT_DIR/takusuki-update5-bundle.zip.sha256" "$LAB_ROOT/artifacts/takusuki-update5-bundle.zip.sha256"
python3 - "$LAB_ROOT/artifacts/takusuki-update5-bundle.zip" "$LAB_ROOT/artifacts" <<'PY'
import pathlib, stat, sys, zipfile
archive = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as source:
    for info in source.infolist():
        path = pathlib.PurePosixPath(info.filename)
        mode = (info.external_attr >> 16) & 0o170000
        if path.is_absolute() or '..' in path.parts or '\\' in info.filename:
            raise SystemExit(f'unsafe ZIP path: {info.filename}')
        if not path.parts or path.parts[0] not in {'takusuki-update3-bundle', 'takusuki-update5-bundle'}:
            raise SystemExit(f'unexpected ZIP root: {info.filename}')
        if mode not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise SystemExit(f'unsupported ZIP type: {info.filename}')
    source.extractall(destination)
PY
chown -R root:asami "$LAB_ROOT/artifacts/takusuki-update3-bundle" 2>/dev/null || true
chown -R root:asami "$LAB_ROOT/artifacts/takusuki-update5-bundle" 2>/dev/null || true
find "$LAB_ROOT/artifacts" -type d -exec chmod 0750 {} +
find "$LAB_ROOT/artifacts" -type f -exec chmod 0640 {} +
chmod 0755 "$LAB_ROOT/artifacts/takusuki_update5.sh"

runuser -u asami -- git clone --filter=blob:none --no-checkout https://github.com/misskey-dev/misskey.git "$SOURCE_DIR"
runuser -u asami -- git -C "$SOURCE_DIR" fetch --no-tags origin refs/tags/2026.10.0:refs/tags/2026.10.0 refs/tags/2026.10.1:refs/tags/2026.10.1
runuser -u asami -- git -C "$SOURCE_DIR" checkout --detach 2026.10.0

BUNDLE_ROOT="$LAB_ROOT/artifacts/takusuki-update5-bundle"
[[ -d "$BUNDLE_ROOT" ]] || BUNDLE_ROOT="$LAB_ROOT/artifacts/takusuki-update3-bundle"
while IFS= read -r patch; do
	[[ -n "$patch" ]] || continue
	runuser -u asami -- git -C "$SOURCE_DIR" apply --check --whitespace=error-all "$BUNDLE_ROOT/misskey-patches/$patch"
	runuser -u asami -- git -C "$SOURCE_DIR" apply --whitespace=error-all "$BUNDLE_ROOT/misskey-patches/$patch"
done < "$BUNDLE_ROOT/misskey-patches/series"
install -o asami -g asami -m 0644 "$BUNDLE_ROOT/assets/unknown.png" "$SOURCE_DIR/packages/frontend/assets/unknown.png"

install -d -o asami -g asami -m 0750 "$SOURCE_DIR/.config" "$SOURCE_DIR/files"
install -o asami -g asami -m 0600 /dev/null "$SOURCE_DIR/.config/default.yml"
printf '%s\n' \
	"url: 'http://127.0.0.1:$MISSKEY_PORT'" \
	"port: $MISSKEY_PORT" \
	"db:" \
	"  host: '$PG_SOCKET'" \
	"  port: $PG_PORT" \
	"  db: takusuki_v5_patched" \
	"  user: asami" \
	"  pass: ''" \
	"redis:" \
	"  host: 127.0.0.1" \
	"  port: $REDIS_PORT" \
	"  db: 0" \
	"id: aidx" > "$SOURCE_DIR/.config/default.yml"
chown asami:asami "$SOURCE_DIR/.config/default.yml"
printf 'preserve-untracked-v5\n' > "$SOURCE_DIR/operator-note.txt"
printf 'preserve-upload-v5\n' > "$SOURCE_DIR/files/upload-marker.txt"
chown asami:asami "$SOURCE_DIR/operator-note.txt" "$SOURCE_DIR/files/upload-marker.txt"

install -d -o asami -g asami -m 0700 "$LAB_ROOT/pgdata"
runuser -u asami -- "$PG_BIN/initdb" -D "$LAB_ROOT/pgdata" --auth-local=trust --auth-host=reject --no-instructions

install -m 0644 /dev/null "/etc/systemd/system/$PG_UNIT"
printf '%s\n' \
	'[Unit]' 'Description=Takusuki v5 isolated PostgreSQL' \
	'[Service]' 'Type=notify' 'User=asami' 'Group=asami' \
	"ExecStart=$PG_BIN/postgres -D $LAB_ROOT/pgdata -k $PG_SOCKET -p $PG_PORT -c listen_addresses=" \
	'KillSignal=SIGINT' 'TimeoutStopSec=120' 'NoNewPrivileges=yes' \
	'IPAddressDeny=any' 'IPAddressAllow=localhost' \
	'[Install]' 'WantedBy=multi-user.target' > "/etc/systemd/system/$PG_UNIT"

install -m 0644 /dev/null "/etc/systemd/system/$REDIS_UNIT"
printf '%s\n' \
	'[Unit]' 'Description=Takusuki v5 isolated Redis' \
	'[Service]' 'Type=notify' 'User=asami' 'Group=asami' \
	"ExecStart=/usr/bin/redis-server --supervised systemd --bind 127.0.0.1 --port $REDIS_PORT --save '' --appendonly no --dir $LAB_ROOT/redis" \
	'NoNewPrivileges=yes' 'IPAddressDeny=any' 'IPAddressAllow=localhost' \
	'[Install]' 'WantedBy=multi-user.target' > "/etc/systemd/system/$REDIS_UNIT"

install -m 0644 /dev/null "/etc/systemd/system/$MISSKEY_UNIT"
printf '%s\n' \
	'[Unit]' 'Description=Takusuki v5 isolated Misskey validation' \
	"After=$PG_UNIT $REDIS_UNIT" "Requires=$PG_UNIT $REDIS_UNIT" \
	'[Service]' 'Type=simple' 'User=asami' 'Group=asami' "WorkingDirectory=$SOURCE_DIR" \
	'Environment=NODE_ENV=production' \
	'ExecStart=/usr/bin/corepack pnpm run start' \
	'Restart=no' 'NoNewPrivileges=yes' 'PrivateTmp=yes' \
	'IPAddressDeny=any' 'IPAddressAllow=localhost' \
	'[Install]' 'WantedBy=multi-user.target' > "/etc/systemd/system/$MISSKEY_UNIT"

systemctl daemon-reload
systemctl start "$PG_UNIT" "$REDIS_UNIT"
runuser -u asami -- "$PG_BIN/createdb" -h "$PG_SOCKET" -p "$PG_PORT" takusuki_v5_patched
runuser -u asami -- "$PG_BIN/psql" -h "$PG_SOCKET" -p "$PG_PORT" -d takusuki_v5_patched -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS pgroonga'

runuser -u asami -- env CI=true NODE_ENV=production /usr/bin/corepack pnpm@11.25.0 --dir "$SOURCE_DIR" install --frozen-lockfile --prefer-offline
runuser -u asami -- env CI=true NODE_ENV=production /usr/bin/corepack pnpm@11.25.0 --dir "$SOURCE_DIR" run build
runuser -u asami -- env CI=true NODE_ENV=production /usr/bin/corepack pnpm@11.25.0 --dir "$SOURCE_DIR" run migrate
runuser -u asami -- "$PG_BIN/createdb" -h "$PG_SOCKET" -p "$PG_PORT" -T takusuki_v5_patched takusuki_v5_vanilla

systemctl start "$MISSKEY_UNIT"
for _attempt in $(seq 1 90); do
	curl --fail --silent --max-time 5 --output /dev/null "http://127.0.0.1:$MISSKEY_PORT/api/meta" \
		-H 'Content-Type: application/json' -d '{}' && break
	((_attempt == 90)) && fail 'isolated Misskey did not become ready'
	sleep 2
done

sha256sum "$SOURCE_DIR/.config/default.yml" "$SOURCE_DIR/operator-note.txt" "$SOURCE_DIR/files/upload-marker.txt" > "$LAB_ROOT/preservation-before.sha256"
systemctl show "$MISSKEY_UNIT" -p User -p WorkingDirectory -p IPAddressDeny -p IPAddressAllow -p ActiveState -p SubState > "$LAB_ROOT/isolation.tsv"
printf 'STAGING V5 LAB READY\nroot=%s\nsource=%s\nservice=%s\npostgres=%s:%s\nredis=127.0.0.1:%s\nhttp=127.0.0.1:%s\n' \
	"$LAB_ROOT" "$SOURCE_DIR" "$MISSKEY_UNIT" "$PG_SOCKET" "$PG_PORT" "$REDIS_PORT" "$MISSKEY_PORT"
