#!/usr/bin/env bash
# Purpose: Interactive and non-interactive, reproducible, fail-closed Misskey operations.
# Author: asami / Takusuki operations (implementation prepared with Codex)
# Version: 4.0.0
# Changelog: v4 adds interactive UI, verified self-downloaded bundles, independent
# DB backups, migration-aware rollback history, and cwd-independent user switching.
# Safety design: preflight and patch checks run before downtime; required failures stop the update.
# Patch/asset source: verified bundle downloaded from labo.takusuki.com.
# Expected environment: systemd deployment, official misskey-dev/misskey Git remote, Node/Corepack/pnpm.

set -Eeuo pipefail
umask 077

readonly UPDATE3_VERSION='4.0.0'
readonly BUNDLE_FORMAT_VERSION='1'
readonly DEFAULT_BUNDLE_URL='https://labo.takusuki.com/update3/takusuki-update3-bundle.zip'
readonly DEFAULT_BUNDLE_SHA_URL='https://labo.takusuki.com/update3/takusuki-update3-bundle.zip.sha256'
readonly PRODUCTION_IPV4='192.168.100.29'
readonly PRODUCTION_IPV6='2400:4051:b900:7400:250:56ff:fe22:664c'

MODE=''
TARGET_VALUE=''
CHECK_ONLY=0
PATCH_ONLY=0
ADVANCED=0
ASSUME_YES=0
BACKUP_CONFIRMED=0
INTERACTIVE=0
ALLOW_DOWNGRADE=0
ROLLBACK_ID=''
BUNDLE_FILE_OVERRIDE=''
BUNDLE_SHA_FILE_OVERRIDE=''
DB_NAME_OVERRIDE=''
MIGRATION_STARTED=0
TMP_WORKTREE=''
TMP_BUNDLE=''
DB_PARTIAL=''
LOG_FILE=''
TARGET_COMMIT=''
TARGET_LABEL=''
CURRENT_STAGE='Initialization'
BACKUP_DIR=''
OLD_VERSION=''
OLD_COMMIT=''
UPDATE_STARTED_EPOCH=''
SERVICE_STOP_EPOCH=''
SERVICE_START_EPOCH=''

usage() {
	cat <<'USAGE'
Usage:
  takusuki_update3.sh                         Interactive menu (root)
  takusuki_update3.sh --stable [--check|--check-patches]
  takusuki_update3.sh --tag VERSION [--check|--check-patches]
  takusuki_update3.sh --master-reset [--check|--check-patches]
  takusuki_update3.sh --branch BRANCH --advanced [--check|--check-patches]
  takusuki_update3.sh --commit SHA1 --advanced [--check|--check-patches]
  takusuki_update3.sh --rollback [--rollback-id HISTORY_ID] [--yes]
  takusuki_update3.sh --db-backup [--yes]

Actual non-interactive operations require --yes and root. DB backup is optional
and independent; normal updates never start pg_dump.

Options:
  --stable             Latest stable YYYY.N.N release tag (default)
  --tag VERSION        Exact official stable release tag
  --master-reset       Exact fetched origin/master (development code warning)
  --branch BRANCH      Official remote branch (advanced mode only)
  --commit SHA1        Exact official commit reachable from a fetched official ref
  --advanced           Permit branch and commit modes
  --check              Full read-only/preflight check; no stop/apply/build/migrate
  --check-patches      Resolve target and test the complete patch series only
  --rollback           List/select a safe v4 update history and roll it back
  --rollback-id ID     Select one history directory basename
  --db-backup          Create and validate a PostgreSQL custom-format backup
  --db-name NAME       Advanced DB-backup-only database override (test/staging)
  --allow-downgrade    Permit CLI downgrade together with --yes
  --backup-confirmed   Deprecated compatibility no-op; backup is not required
  --bundle-file FILE   Verified local ZIP override (requires --advanced)
  --bundle-sha-file F  SHA-256 sidecar for --bundle-file (requires --advanced)
  --yes                Confirm the selected actual update
  --help               Show this help

Configuration environment:
  MISSKEY_USER, MISSKEY_DIR, SERVICE_NAME
  HEALTH_LOCAL_URL, HEALTH_LAN_URL, HEALTH_PUBLIC_URL, HEALTH_API_URL
  LOG_DIR, STATE_DIR, MIN_FREE_KB, POSTGRESQL_CONF, REQUIRE_ENV_FILE
  BUNDLE_URL, BUNDLE_SHA_URL, BUNDLE_CACHE_DIR, DB_BACKUP_DIR
USAGE
}

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

step() {
	CURRENT_STAGE=$*
	printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

cleanup() {
	local rc=$?
	local service_state='UNKNOWN' migration_state='NOT STARTED'
	if [[ -n "$TMP_WORKTREE" && -d "$TMP_WORKTREE/tree" ]]; then
		as_misskey git -C "$MISSKEY_DIR" worktree remove --force "$TMP_WORKTREE/tree" >/dev/null 2>&1 || true
	fi
	if [[ -n "$TMP_WORKTREE" && -d "$TMP_WORKTREE" ]]; then
		rm -rf -- "$TMP_WORKTREE"
	fi
	if [[ -n "$TMP_BUNDLE" && -d "$TMP_BUNDLE" ]]; then
		rm -rf -- "$TMP_BUNDLE"
	fi
	if [[ -n "$DB_PARTIAL" ]]; then
		rm -f -- "$DB_PARTIAL" "$DB_PARTIAL.list" "$DB_PARTIAL.metadata"
	fi
	if (( rc != 0 )); then
		if [[ -n "${SERVICE_NAME:-}" ]] && command -v systemctl >/dev/null 2>&1; then
			service_state=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
			[[ -n "$service_state" ]] || service_state='UNKNOWN'
		fi
		if (( MIGRATION_STARTED == 1 )); then migration_state='STARTED'; fi
		printf '\n============================================================\n' >&2
		printf ' Operation failed / 処理に失敗しました\n' >&2
		printf '============================================================\n' >&2
		printf '失敗工程 / Stage : %s\nExit               : %d\nMisskey service    : %s\nMigration          : %s\n' \
			"$CURRENT_STAGE" "$rc" "$service_state" "$migration_state" >&2
		printf 'Fail-closed: no service start is attempted after an install/build/migration failure.\n' >&2
		if [[ -n "$BACKUP_DIR" ]]; then printf 'Rollback candidate: %s\n' "$BACKUP_DIR" >&2; fi
		if [[ -n "$LOG_FILE" ]]; then
			printf 'Log: %s\n' "$LOG_FILE" >&2
		fi
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if (($# == 0)); then
	INTERACTIVE=1
	MODE='interactive'
fi

while (($# > 0)); do
	case "$1" in
		--stable)
			MODE='stable'
			TARGET_VALUE=''
			shift
			;;
		--tag)
			(($# >= 2)) || fail '--tag requires a value'
			MODE='tag'
			TARGET_VALUE=$2
			shift 2
			;;
		--master-reset)
			MODE='master'
			TARGET_VALUE='master'
			shift
			;;
		--branch)
			(($# >= 2)) || fail '--branch requires a value'
			MODE='branch'
			TARGET_VALUE=$2
			shift 2
			;;
		--commit)
			(($# >= 2)) || fail '--commit requires a value'
			MODE='commit'
			TARGET_VALUE=$2
			shift 2
			;;
		--advanced)
			ADVANCED=1
			shift
			;;
		--check)
			CHECK_ONLY=1
			shift
			;;
		--check-patches)
			CHECK_ONLY=1
			PATCH_ONLY=1
			shift
			;;
		--backup-confirmed)
			BACKUP_CONFIRMED=1
			shift
			;;
		--rollback)
			MODE='rollback'
			shift
			;;
		--rollback-id)
			(($# >= 2)) || fail '--rollback-id requires a value'
			ROLLBACK_ID=$2
			shift 2
			;;
		--db-backup)
			MODE='db-backup'
			shift
			;;
		--db-name)
			(($# >= 2)) || fail '--db-name requires a value'
			DB_NAME_OVERRIDE=$2
			shift 2
			;;
		--allow-downgrade)
			ALLOW_DOWNGRADE=1
			shift
			;;
		--bundle-file)
			(($# >= 2)) || fail '--bundle-file requires a value'
			BUNDLE_FILE_OVERRIDE=$2
			shift 2
			;;
		--bundle-sha-file)
			(($# >= 2)) || fail '--bundle-sha-file requires a value'
			BUNDLE_SHA_FILE_OVERRIDE=$2
			shift 2
			;;
		--yes)
			ASSUME_YES=1
			shift
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			fail "unknown option: $1"
			;;
	esac
done

[[ -n "$MODE" ]] || fail 'one operation mode is required; use --help'

[[ "$MODE" != 'branch' || "$ADVANCED" == 1 ]] || fail '--branch requires --advanced'
[[ "$MODE" != 'commit' || "$ADVANCED" == 1 ]] || fail '--commit requires --advanced'
if [[ -n "$BUNDLE_FILE_OVERRIDE" || -n "$BUNDLE_SHA_FILE_OVERRIDE" ]]; then
	(( ADVANCED == 1 )) || fail 'local bundle override requires --advanced'
	[[ -n "$BUNDLE_FILE_OVERRIDE" && -n "$BUNDLE_SHA_FILE_OVERRIDE" ]] || fail 'both local bundle files are required'
fi
if [[ "$MODE" == 'tag' ]]; then
	[[ "$TARGET_VALUE" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]] || fail 'tag must be a stable YYYY.N.N version'
fi
if [[ "$MODE" == 'commit' ]]; then
	[[ "$TARGET_VALUE" =~ ^[0-9a-f]{40}$ ]] || fail 'commit must be a full lowercase 40-character SHA-1'
fi
if [[ "$MODE" == 'rollback' || "$MODE" == 'db-backup' ]]; then
	(( CHECK_ONLY == 0 && PATCH_ONLY == 0 )) || fail '--check/--check-patches apply only to update modes'
	[[ -z "$BUNDLE_FILE_OVERRIDE" ]] || fail 'bundle override does not apply to rollback/DB backup'
fi
[[ -z "$ROLLBACK_ID" || "$MODE" == 'rollback' ]] || fail '--rollback-id requires --rollback'
if [[ -n "$DB_NAME_OVERRIDE" ]]; then
	[[ "$MODE" == 'db-backup' && "$ADVANCED" == 1 ]] || fail '--db-name requires --db-backup --advanced'
	[[ "$DB_NAME_OVERRIDE" =~ ^[A-Za-z0-9_.-]+$ ]] || fail 'invalid --db-name value'
fi

if [[ -r /root/.misskey.env ]]; then
	# Trusted administrator-owned deployment environment; values are never printed.
	# shellcheck disable=SC1091
	source /root/.misskey.env
fi

MISSKEY_USER=${MISSKEY_USER:-${misskey_user:-misskey}}
[[ "$MISSKEY_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail 'invalid MISSKEY_USER'
MISSKEY_HOME=$(getent passwd "$MISSKEY_USER" | cut -d: -f6)
[[ -n "$MISSKEY_HOME" ]] || fail "user does not exist: $MISSKEY_USER"

USER_ENV_FILE="$MISSKEY_HOME/.misskey.env"
if [[ -r "$USER_ENV_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$USER_ENV_FILE"
fi

MISSKEY_DIR=${MISSKEY_DIR:-"$MISSKEY_HOME/${misskey_directory:-misskey}"}
SERVICE_NAME=${SERVICE_NAME:-${host:-takusuki.com}}
LOG_DIR=${LOG_DIR:-/var/log/takusuki-update3}
STATE_DIR=${STATE_DIR:-/var/lib/takusuki-update3}
BUNDLE_CACHE_DIR=${BUNDLE_CACHE_DIR:-/var/cache/takusuki-update3}
DB_BACKUP_DIR=${DB_BACKUP_DIR:-/var/backups/takusuki}
BUNDLE_URL=${BUNDLE_URL:-$DEFAULT_BUNDLE_URL}
BUNDLE_SHA_URL=${BUNDLE_SHA_URL:-$DEFAULT_BUNDLE_SHA_URL}
MIN_FREE_KB=${MIN_FREE_KB:-10485760}
REQUIRE_ENV_FILE=${REQUIRE_ENV_FILE:-1}
HEALTH_LOCAL_URL=${HEALTH_LOCAL_URL:-http://127.0.0.1:3000/}
HEALTH_API_URL=${HEALTH_API_URL:-http://127.0.0.1:3000/api/meta}
HEALTH_LAN_URL=${HEALTH_LAN_URL:-}
HEALTH_PUBLIC_URL=${HEALTH_PUBLIC_URL:-}

if (( CHECK_ONLY == 0 && EUID != 0 )); then
	fail 'actual update requires root; use --check for an unprivileged preflight'
fi

as_misskey() {
	if (( EUID == 0 )); then
		# Expansion is intentionally done by child Bash.
		# shellcheck disable=SC2016
		runuser --preserve-environment -u "$MISSKEY_USER" -- \
			env HOME="$MISSKEY_HOME" USER="$MISSKEY_USER" LOGNAME="$MISSKEY_USER" \
			bash -c 'cd -- "$1"; shift; exec "$@"' bash "$MISSKEY_DIR" "$@"
	elif [[ "$(id -un)" == "$MISSKEY_USER" ]]; then
		( cd -- "$MISSKEY_DIR" && "$@" )
	else
		fail "cannot run as $MISSKEY_USER without root"
	fi
}

init_colors() {
	C_RESET='' C_RED='' C_BLUE='' C_CYAN='' C_YELLOW=''
	if [[ -t 1 && -n "${TERM:-}" ]] && command -v tput >/dev/null 2>&1; then
		C_RESET=$(tput sgr0 2>/dev/null || true)
		C_RED=$(tput setaf 1 2>/dev/null || true)
		C_YELLOW=$(tput setaf 3 2>/dev/null || true)
		C_BLUE=$(tput setaf 4 2>/dev/null || true)
		C_CYAN=$(tput setaf 6 2>/dev/null || true)
	fi
}

ui_header() {
	printf '%s============================================================%s\n' "$C_BLUE" "$C_RESET"
	printf '%s Takusuki Misskey Updater v%s%s\n' "$C_CYAN" "$UPDATE3_VERSION" "$C_RESET"
	printf '%s============================================================%s\n' "$C_BLUE" "$C_RESET"
}

current_version() {
	node -e 'try { process.stdout.write(require(process.argv[1]).version ?? "UNKNOWN"); } catch { process.stdout.write("UNKNOWN"); }' "$MISSKEY_DIR/package.json" 2>/dev/null || printf 'UNKNOWN'
}

interactive_menu() {
	[[ -t 0 ]] || fail 'argument-free interactive mode requires a TTY'
	local version commit service choice
	version=$(current_version)
	commit=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --short=12 HEAD 2>/dev/null || printf 'UNKNOWN')
	service=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
	while true; do
		ui_header
		printf '\n現在のMisskey:\n  Version : %s\n  Commit  : %s\n  Service : %s\n\n' "$version" "$commit" "$service"
		printf '1. 最新版へアップデート\n2. タグから選んでアップデート\n3. master へ強制リセット\n4. ロールバック\n5. DBをバックアップ\n0. 終了\n\n'
		read -r -p '番号で選んでください [0-5]: ' choice
		case "$choice" in
			0) printf '終了します。\n'; exit 0 ;;
			1) MODE='stable'; return ;;
			2) MODE='tag-select'; return ;;
			3) MODE='master'; return ;;
			4) MODE='rollback'; return ;;
			5) MODE='db-backup'; return ;;
			*) printf '%s無効な選択です。%s\n\n' "$C_RED" "$C_RESET" ;;
		esac
	done
}

safe_relative_path() {
	local value=$1
	[[ -n "$value" && "$value" != /* && "$value" != *'..'* && "$value" != *$'\n'* ]]
}

verify_zip_sidecar() {
	local zip_file=$1 sidecar=$2 expected actual extra
	read -r expected extra < "$sidecar" || fail 'bundle SHA-256 sidecar is empty'
	[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || fail 'bundle SHA-256 sidecar is invalid'
	actual=$(sha256sum "$zip_file" | awk '{ print $1 }')
	[[ "${actual,,}" == "${expected,,}" ]] || fail 'bundle ZIP SHA-256 mismatch'
	printf '[OK] Bundle ZIP SHA-256 %s\n' "$actual"
}

extract_zip_safely() {
	local zip_file=$1 destination=$2
	python3 - "$zip_file" "$destination" <<'PY'
import os
import pathlib
import shutil
import stat
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(mode=0o700, parents=True)
seen = set()
with zipfile.ZipFile(archive) as source:
    infos = source.infolist()
    if not infos:
        raise SystemExit('empty ZIP')
    for info in infos:
        name = info.filename
        pure = pathlib.PurePosixPath(name)
        if '\\' in name or not name or pure.is_absolute() or '..' in pure.parts or '\x00' in name:
            raise SystemExit(f'unsafe ZIP path: {name!r}')
        if not pure.parts or pure.parts[0] != 'takusuki-update3-bundle':
            raise SystemExit(f'unexpected ZIP root: {name!r}')
        if name in seen:
            raise SystemExit(f'duplicate ZIP path: {name!r}')
        seen.add(name)
        mode = (info.external_attr >> 16) & 0xFFFF
        kind = stat.S_IFMT(mode)
        is_dir = info.is_dir()
        if kind == stat.S_IFLNK or (kind not in (0, stat.S_IFREG, stat.S_IFDIR)):
            raise SystemExit(f'unsupported ZIP entry type: {name!r}')
        target = destination.joinpath(*pure.parts)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if is_dir:
            target.mkdir(mode=0o700, exist_ok=True)
        else:
            with source.open(info) as incoming, open(target, 'xb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            target.chmod(0o600)
PY
}

verify_bundle_manifest() {
	local root=$1 manifest="$1/bundle-manifest.tsv"
	[[ -f "$manifest" && ! -L "$manifest" ]] || fail 'bundle-manifest.tsv missing or unsafe'
	local kind key value size extra bundle_version='' minimum_version=''
	declare -A expected_sha expected_size
	while IFS=$'\t' read -r kind key value size extra; do
		[[ -n "$kind" ]] || continue
		[[ -z "$extra" ]] || fail "bundle manifest has extra fields: $key"
		case "$kind" in
			META)
				[[ -n "$key" && -n "$value" && -z "$size" ]] || fail 'invalid bundle META row'
				case "$key" in
					bundle_version) bundle_version=$value ;;
					minimum_updater_version) minimum_version=$value ;;
					generated_at) : ;;
					*) fail "unknown bundle META key: $key" ;;
				esac
				;;
			FILE)
				safe_relative_path "$key" || fail "unsafe bundle manifest path: $key"
				[[ "$key" != 'bundle-manifest.tsv' ]] || fail 'manifest cannot hash itself'
				[[ "$value" =~ ^[0-9a-f]{64}$ && "$size" =~ ^[0-9]+$ ]] || fail "invalid bundle FILE row: $key"
				[[ -z "${expected_sha[$key]:-}" ]] || fail "duplicate bundle manifest path: $key"
				expected_sha[$key]=$value
				expected_size[$key]=$size
				;;
			*) fail "unknown bundle manifest row: $kind" ;;
		esac
	done < "$manifest"
	[[ "$bundle_version" == "$BUNDLE_FORMAT_VERSION" ]] || fail "unsupported bundle version: $bundle_version"
	[[ -n "$minimum_version" ]] || fail 'bundle minimum updater version missing'
	[[ "$(printf '%s\n%s\n' "$minimum_version" "$UPDATE3_VERSION" | sort -V | head -n 1)" == "$minimum_version" ]] || fail "bundle requires updater $minimum_version"
	((${#expected_sha[@]} > 0)) || fail 'bundle manifest contains no files'
	local path relative actual_sha actual_size
	while IFS= read -r -d '' path; do
		relative=${path#"$root/"}
		[[ "$relative" == 'bundle-manifest.tsv' ]] && continue
		[[ -n "${expected_sha[$relative]:-}" ]] || fail "unlisted bundle file: $relative"
	done < <(find "$root" -mindepth 1 -type f -print0)
	if find "$root" -mindepth 1 -type l -print -quit | grep -q .; then fail 'bundle contains a symlink'; fi
	for relative in "${!expected_sha[@]}"; do
		path="$root/$relative"
		[[ -f "$path" && ! -L "$path" ]] || fail "bundle file missing: $relative"
		actual_sha=$(sha256sum "$path" | awk '{ print $1 }')
		actual_size=$(stat -c %s "$path")
		[[ "$actual_sha" == "${expected_sha[$relative]}" ]] || fail "bundle file SHA-256 mismatch: $relative"
		[[ "$actual_size" == "${expected_size[$relative]}" ]] || fail "bundle file size mismatch: $relative"
	done
	printf '[OK] Bundle manifest: version=%s files=%d\n' "$bundle_version" "${#expected_sha[@]}"
}

grant_bundle_read_access() {
	(( EUID == 0 )) || return 0
	local misskey_group
	misskey_group=$(id -gn "$MISSKEY_USER")
	# The root-created temporary tree remains non-public. The Misskey account
	# receives read/traverse access only after every ZIP and manifest check passed.
	chown root:"$misskey_group" "$TMP_BUNDLE"
	chmod 0710 "$TMP_BUNDLE"
	chown -R root:"$misskey_group" "$TMP_BUNDLE/extract"
	find "$TMP_BUNDLE/extract" -type d -exec chmod 0750 {} +
	find "$TMP_BUNDLE/extract" -type f -exec chmod 0640 {} +
}

validate_bundle_zip() {
	local zip_file=$1 sidecar=$2
	verify_zip_sidecar "$zip_file" "$sidecar"
	extract_zip_safely "$zip_file" "$TMP_BUNDLE/extract"
	BUNDLE_ROOT="$TMP_BUNDLE/extract/takusuki-update3-bundle"
	verify_bundle_manifest "$BUNDLE_ROOT"
	PATCH_DIR="$BUNDLE_ROOT/misskey-patches"
	SERIES_FILE="$PATCH_DIR/series"
	MANIFEST_FILE="$PATCH_DIR/patch-manifest.tsv"
	ASSET_FILE="$BUNDLE_ROOT/assets/unknown.png"
	ASSET_HASH_FILE="$BUNDLE_ROOT/assets/unknown.png.sha256"
	grant_bundle_read_access
}

acquire_bundle() {
	step 'Download and verify Takusuki patch bundle'
	command -v curl >/dev/null || fail 'curl missing'
	command -v python3 >/dev/null || fail 'python3 missing'
	TMP_BUNDLE=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-update3-bundle.XXXXXXXX")
	local zip_file="$TMP_BUNDLE/bundle.zip" sidecar="$TMP_BUNDLE/bundle.zip.sha256" remote_ok=0
	if [[ -n "$BUNDLE_FILE_OVERRIDE" ]]; then
		[[ -f "$BUNDLE_FILE_OVERRIDE" && -f "$BUNDLE_SHA_FILE_OVERRIDE" ]] || fail 'local bundle override file missing'
		install -m 0600 "$BUNDLE_FILE_OVERRIDE" "$zip_file"
		install -m 0600 "$BUNDLE_SHA_FILE_OVERRIDE" "$sidecar"
		validate_bundle_zip "$zip_file" "$sidecar"
		printf 'Bundle source: verified local advanced override\n'
		return
	fi
	[[ "$BUNDLE_URL" == https://* && "$BUNDLE_SHA_URL" == https://* ]] || fail 'bundle URLs must use HTTPS'
	if curl --proto '=https' --tlsv1.2 --location --fail --silent --show-error --max-time 120 --output "$zip_file" "$BUNDLE_URL" \
		&& curl --proto '=https' --tlsv1.2 --location --fail --silent --show-error --max-time 30 --output "$sidecar" "$BUNDLE_SHA_URL"; then
		# A downloaded-but-invalid bundle is a security failure, not an outage:
		# never hide an integrity error behind a cache fallback.
		validate_bundle_zip "$zip_file" "$sidecar"
		remote_ok=1
	fi
	if (( remote_ok == 0 )); then
		printf '%sCACHE FALLBACK: remote bundle unavailable.%s\n' "$C_YELLOW" "$C_RESET" >&2
		[[ -f "$BUNDLE_CACHE_DIR/bundle.zip" && -f "$BUNDLE_CACHE_DIR/bundle.zip.sha256" ]] || fail 'Takusuki patch bundle could not be verified; Misskey was NOT stopped'
		install -m 0600 "$BUNDLE_CACHE_DIR/bundle.zip" "$zip_file"
		install -m 0600 "$BUNDLE_CACHE_DIR/bundle.zip.sha256" "$sidecar"
		validate_bundle_zip "$zip_file" "$sidecar"
		printf 'Bundle source: verified cache fallback\n'
	elif (( EUID == 0 )); then
		install -d -o root -g root -m 0700 "$BUNDLE_CACHE_DIR"
		install -o root -g root -m 0600 "$zip_file" "$BUNDLE_CACHE_DIR/bundle.zip.new"
		install -o root -g root -m 0600 "$sidecar" "$BUNDLE_CACHE_DIR/bundle.zip.sha256.new"
		mv -f -- "$BUNDLE_CACHE_DIR/bundle.zip.new" "$BUNDLE_CACHE_DIR/bundle.zip"
		mv -f -- "$BUNDLE_CACHE_DIR/bundle.zip.sha256.new" "$BUNDLE_CACHE_DIR/bundle.zip.sha256"
		printf 'Bundle source: verified HTTPS download; cache updated atomically\n'
	else
		printf 'Bundle source: verified HTTPS download; unprivileged check left cache unchanged\n'
	fi
}

db_node() {
	local action=$1
	shift
	MISSKEY_DIR="$MISSKEY_DIR" DB_NAME_OVERRIDE="$DB_NAME_OVERRIDE" node --input-type=module - "$action" "$@" <<'NODE'
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const misskeyDir = process.env.MISSKEY_DIR;
const action = process.argv[2];
const args = process.argv.slice(3);
process.chdir(misskeyDir);
const { loadConfig } = await import(pathToFileURL(`${misskeyDir}/packages/backend/built/config.js`).href);
const require = createRequire(`${misskeyDir}/packages/backend/package.json`);
const pgModule = require('pg');
const pg = pgModule.default ?? pgModule;
const config = loadConfig();
const db = config.db;
const database = process.env.DB_NAME_OVERRIDE || db.db;
const connection = {
  host: db.host,
  port: db.port,
  user: db.user,
  password: db.pass,
  database,
  connectionTimeoutMillis: 10000,
  application_name: 'takusuki-update3-v4',
};

if (action === 'dump') {
  const output = args[0];
  if (!output) throw new Error('dump output path is required');
  const dumpArgs = ['--format=custom', '--compress=6', '--no-owner', '--no-privileges', '--file', output];
  if (db.host) dumpArgs.push('--host', String(db.host));
  if (db.port) dumpArgs.push('--port', String(db.port));
  if (db.user) dumpArgs.push('--username', String(db.user));
  dumpArgs.push('--dbname', String(database));
  const child = spawn('pg_dump', dumpArgs, {
    stdio: ['ignore', 'inherit', 'inherit'],
    env: { ...process.env, PGPASSWORD: db.pass ?? '' },
  });
  const [code, signal] = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (exitCode, exitSignal) => resolve([exitCode, exitSignal]));
  });
  if (code !== 0) throw new Error(`pg_dump failed (exit=${code}, signal=${signal ?? 'none'})`);
  process.exit(0);
}

const client = new pg.Client(connection);
await client.connect();
try {
  if (action === 'info') {
    const result = await client.query(`SELECT current_database() AS database, pg_database_size(current_database())::text AS bytes, current_setting('server_version') AS version`);
    const row = result.rows[0];
    process.stdout.write(`${row.database}\n${row.bytes}\n${row.version}\n`);
  } else if (action === 'ledger') {
    const result = await client.query('SELECT id, timestamp, name FROM migrations ORDER BY id');
    for (const row of result.rows) process.stdout.write(`${row.id}\t${row.timestamp}\t${row.name}\n`);
  } else {
    throw new Error(`unknown DB action: ${action}`);
  }
} finally {
  await client.end();
}
NODE
}

confirm_yes() {
	local prompt=$1 answer
	if (( INTERACTIVE == 1 )); then
		read -r -p "$prompt [y/N]: " answer
		[[ "$answer" == 'y' || "$answer" == 'Y' ]]
	else
		(( ASSUME_YES == 1 ))
	fi
}

wait_for_readiness() {
	local attempt
	for attempt in $(seq 1 30); do
		if ! systemctl is-active --quiet "$SERVICE_NAME"; then
			fail "systemd service stopped during startup wait (attempt $attempt)"
		fi
		if ss -ltnH | awk '$4 ~ /:3000$/ { found=1 } END { exit !found }' \
			&& curl --fail --silent --max-time 5 --output /dev/null "$HEALTH_LOCAL_URL" \
			&& curl --fail --silent --max-time 5 --output /dev/null -H 'Content-Type: application/json' -d '{}' "$HEALTH_API_URL"; then
			printf '[OK] Local readiness after attempt %d/30\n' "$attempt"
			return 0
		fi
		sleep 2
	done
	fail 'local Misskey readiness did not pass within 60 seconds'
}

run_health_checks() {
	wait_for_readiness
	curl --fail --silent --show-error --max-time 10 --output /dev/null "$HEALTH_LOCAL_URL"
	curl --fail --silent --show-error --max-time 10 --output /dev/null -H 'Content-Type: application/json' -d '{}' "$HEALTH_API_URL"
	if [[ -n "$HEALTH_LAN_URL" ]]; then curl --fail --silent --show-error --max-time 10 --output /dev/null "$HEALTH_LAN_URL"; fi
	if [[ -n "$HEALTH_PUBLIC_URL" ]]; then curl --fail --silent --show-error --max-time 15 --output /dev/null "$HEALTH_PUBLIC_URL"; fi
	printf '[OK] HTTP/API health checks\n'
}

run_db_backup() {
	step 'PostgreSQL Backup'
	(( EUID == 0 )) || fail 'DB backup requires root'
	command -v pg_dump >/dev/null || fail 'pg_dump missing'
	command -v pg_restore >/dev/null || fail 'pg_restore missing'
	local -a info
	mapfile -t info < <(db_node info)
	((${#info[@]} == 3)) || fail 'could not read safe PostgreSQL metadata'
	local database=${info[0]} bytes=${info[1]} pg_version=${info[2]}
	[[ "$database" =~ ^[A-Za-z0-9_.-]+$ && "$bytes" =~ ^[0-9]+$ ]] || fail 'unsafe database metadata'
	install -d -o root -g root -m 0700 "$DB_BACKUP_DIR"
	local stamp final partial list metadata metadata_partial
	stamp=$(date -u +%Y%m%dT%H%M%SZ)
	final="$DB_BACKUP_DIR/$database-$stamp-$$.dump"
	partial="$final.partial"
	list="$partial.list"
	metadata="$final.metadata.tsv"
	metadata_partial="$partial.metadata"
	DB_PARTIAL=$partial
	printf 'Database : %s\nSize     : %s bytes\nFormat   : PostgreSQL custom\nOutput   : %s\n' "$database" "$bytes" "$final"
	confirm_yes 'バックアップを開始しますか？' || { printf 'Cancelled.\n'; return 0; }
	rm -f -- "$partial" "$list"
	if ! db_node dump "$partial"; then
		rm -f -- "$partial" "$list" "$metadata_partial"
		fail 'pg_dump failed; incomplete dump removed'
	fi
	if ! pg_restore --list "$partial" > "$list"; then
		rm -f -- "$partial" "$list" "$metadata_partial"
		fail 'pg_restore --list failed; invalid dump removed'
	fi
	local sha file_size entries
	sha=$(sha256sum "$partial" | awk '{ print $1 }')
	file_size=$(stat -c %s "$partial")
	entries=$(awk '!/^;/ && NF { count++ } END { print count + 0 }' "$list")
	(( entries > 0 )) || { rm -f -- "$partial" "$list" "$metadata_partial"; fail 'restore list has no entries'; }
	{
		printf 'status\tPASS\ncreated_at\t%s\ndatabase\t%s\nsource_database_bytes\t%s\npostgresql_version\t%s\nformat\tcustom\nfile\t%s\nfile_bytes\t%s\nsha256\t%s\nrestore_list_entries\t%s\n' \
			"$(date --iso-8601=seconds)" "$database" "$bytes" "$pg_version" "$final" "$file_size" "$sha" "$entries"
	} > "$metadata_partial"
	chmod 0600 "$partial" "$metadata_partial"
	mv -- "$partial" "$final"
	mv -- "$metadata_partial" "$metadata"
	DB_PARTIAL=''
	rm -f -- "$list"
	printf '\nBACKUP VALIDATION: PASS\nFile: %s\nBytes: %s\nSHA-256: %s\nRestore-list entries: %s\n' "$final" "$file_size" "$sha" "$entries"
}

history_is_rollback_capable() {
	local directory=$1
	[[ -f "$directory/metadata.tsv" && -f "$directory/result.tsv" \
		&& -f "$directory/pre-update-working-tree.patch" \
		&& -f "$directory/pre-update-untracked.list0" \
		&& -f "$directory/pre-update-untracked.tar.gz" \
		&& -f "$directory/pre-update-patch-manifest.tsv" \
		&& -f "$directory/pre-update-patch-series" \
		&& -f "$directory/pre-update-migrations.tsv" ]]
}

select_rollback_history() {
	local -a choices=()
	local directory index=1 selection old new status stamp
	while IFS= read -r directory; do
		history_is_rollback_capable "$directory" || continue
		choices+=("$directory")
		old=$(awk -F '\t' '$1 == "old_version" { print $2 }' "$directory/metadata.tsv")
		new=$(awk -F '\t' '$1 == "new_target" { print $2 }' "$directory/metadata.tsv")
		stamp=$(awk -F '\t' '$1 == "timestamp" { print $2 }' "$directory/metadata.tsv")
		status=$(awk -F '\t' '$1 == "health" { print $2 }' "$directory/result.tsv")
		printf ' [%d] %s\n     %s -> %s  %s\n' "$index" "$stamp" "$old" "$new" "${status:-UNKNOWN}"
		((index++))
	done < <(find "$STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -print | sort -r)
	((${#choices[@]} > 0)) || fail 'no migration-aware v4 rollback history is available'
	if [[ -n "$ROLLBACK_ID" ]]; then
		[[ "$ROLLBACK_ID" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'unsafe rollback ID'
		BACKUP_DIR="$STATE_DIR/backups/$ROLLBACK_ID"
		history_is_rollback_capable "$BACKUP_DIR" || fail 'selected rollback history is incomplete'
		return
	fi
	[[ -t 0 ]] || fail '--rollback-id is required for non-interactive rollback'
	while true; do
		read -r -p "戻したい番号を選択してください [1-${#choices[@]}]: " selection
		if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#choices[@]} )); then
			BACKUP_DIR=${choices[selection - 1]}
			return
		fi
		printf '無効な選択です。\n'
	done
}

remove_manifest_managed_paths() {
	local manifest=$1 id filename description required introduced upstream sha added extra path
	[[ -f "$manifest" ]] || return 0
	while IFS=$'\t' read -r id filename description required introduced upstream sha added extra; do
		[[ "$id" == 'ID' || -z "$id" ]] && continue
		IFS=';' read -r -a paths <<< "$added"
		for path in "${paths[@]}"; do
			[[ -z "$path" ]] && continue
			safe_relative_path "$path" || fail "unsafe managed rollback path: $path"
			rm -f -- "$MISSKEY_DIR/$path"
		done
	done < "$manifest"
}

run_rollback() {
	step 'Migration-aware rollback selection'
	(( EUID == 0 )) || fail 'rollback requires root'
	select_rollback_history
	local expected_ledger="$BACKUP_DIR/pre-update-migrations.tsv" current_ledger="$BACKUP_DIR/rollback-current-migrations-$$.tsv"
	db_node ledger > "$current_ledger"
	chmod 0600 "$current_ledger"
	if ! cmp -s "$expected_ledger" "$current_ledger"; then
		printf 'DB migration差分を検出しました。sourceだけのrollbackは拒否します。\n' >&2
		fail 'migration-aware rollback refused (ledger differs)'
	fi
	local old_commit old_version expected_pnpm answer rollback_state
	old_commit=$(awk -F '\t' '$1 == "old_commit" { print $2 }' "$BACKUP_DIR/metadata.tsv")
	old_version=$(awk -F '\t' '$1 == "old_version" { print $2 }' "$BACKUP_DIR/metadata.tsv")
	[[ "$old_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'rollback metadata has invalid old commit'
	printf 'Rollback target: %s (%s)\nMigration ledger: IDENTICAL\n' "$old_version" "$old_commit"
	confirm_yes 'この履歴へrollbackしますか？' || { printf 'Cancelled.\n'; return 0; }
	step 'Stop service for rollback'
	systemctl stop "$SERVICE_NAME"
	step 'Restore pre-update source and user changes'
	as_misskey git -C "$MISSKEY_DIR" reset --hard HEAD
	remove_manifest_managed_paths "$STATE_DIR/current-patch-manifest.tsv"
	as_misskey git -C "$MISSKEY_DIR" checkout --detach "$old_commit"
	as_misskey git -C "$MISSKEY_DIR" reset --hard "$old_commit"
	if [[ -s "$BACKUP_DIR/pre-update-working-tree.patch" ]]; then
		as_misskey git -C "$MISSKEY_DIR" apply --binary < "$BACKUP_DIR/pre-update-working-tree.patch"
	fi
	tar -C "$MISSKEY_DIR" -xzf "$BACKUP_DIR/pre-update-untracked.tar.gz"
	expected_pnpm=$(node -e "const p=require(process.argv[1]).packageManager || ''; process.stdout.write(p.startsWith('pnpm@') ? p.slice(5) : '')" "$MISSKEY_DIR/package.json")
	[[ -n "$expected_pnpm" ]] || fail 'rollback packageManager missing'
	step 'Install and build rollback target'
	as_misskey env CI=true NODE_ENV=production corepack "pnpm@$expected_pnpm" --dir "$MISSKEY_DIR" install --frozen-lockfile --prefer-offline
	as_misskey env CI=true NODE_ENV=production corepack "pnpm@$expected_pnpm" --dir "$MISSKEY_DIR" run build
	db_node ledger > "$current_ledger"
	cmp -s "$expected_ledger" "$current_ledger" || fail 'migration ledger changed during rollback build'
	step 'Start and validate rollback target'
	systemctl start "$SERVICE_NAME"
	run_health_checks
	cp "$BACKUP_DIR/pre-update-patch-manifest.tsv" "$STATE_DIR/current-patch-manifest.tsv"
	cp "$BACKUP_DIR/pre-update-patch-series" "$STATE_DIR/current-patch-series"
	rollback_state="$STATE_DIR/rollbacks/$(date -u +%Y%m%dT%H%M%SZ)-$$-${BACKUP_DIR##*/}"
	install -d -o root -g root -m 0700 "$rollback_state"
	printf 'timestamp\t%s\nsource_history\t%s\nold_version\t%s\nold_commit\t%s\nmigration_ledger\tIDENTICAL\ninstall\tPASS\nbuild\tPASS\nservice\tPASS\nhealth\tPASS\n' \
		"$(date --iso-8601=seconds)" "$BACKUP_DIR" "$old_version" "$old_commit" > "$rollback_state/result.tsv"
	printf '\nROLLBACK COMPLETE: %s (%s)\nResult: %s\n' "$old_version" "$old_commit" "$rollback_state"
}

validate_health_target() {
	local value=$1
	[[ -z "$value" ]] && return 0
	case "$value" in
		*"$PRODUCTION_IPV4"*|*"$PRODUCTION_IPV6"*|http://takusuki.com|http://takusuki.com/*|https://takusuki.com|https://takusuki.com/*)
			fail "Production health target is forbidden: $value"
			;;
	esac
}

validate_health_target "$HEALTH_LOCAL_URL"
validate_health_target "$HEALTH_API_URL"
validate_health_target "$HEALTH_LAN_URL"
validate_health_target "$HEALTH_PUBLIC_URL"
validate_health_target "$BUNDLE_URL"
validate_health_target "$BUNDLE_SHA_URL"

init_colors
if (( INTERACTIVE == 1 )); then interactive_menu; fi

if (( EUID == 0 )); then
	install -d -m 0700 "$LOG_DIR" "$STATE_DIR/backups" "$STATE_DIR/rollbacks"
else
	mkdir -p "$LOG_DIR" "$STATE_DIR/backups"
fi
LOG_FILE="$LOG_DIR/update-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee -a "$LOG_FILE") 2>&1

printf 'Takusuki update3 v%s\n' "$UPDATE3_VERSION"
printf 'Mode=%s check=%d patch_only=%d\n' "$MODE" "$CHECK_ONLY" "$PATCH_ONLY"

case "$MODE" in
	db-backup)
		run_db_backup
		exit 0
		;;
	rollback)
		run_rollback
		exit 0
		;;
esac

acquire_bundle

step 'Validate source directory and official remote'
[[ -d "$MISSKEY_DIR" ]] || fail "source directory missing: $MISSKEY_DIR"
[[ -e "$MISSKEY_DIR/.git" ]] || fail 'source directory is not a Git worktree'
[[ -f "$MISSKEY_DIR/package.json" ]] || fail 'package.json missing'
[[ -d "$MISSKEY_DIR/packages/backend" ]] || fail 'packages/backend missing'
REMOTE_URL=$(as_misskey git -C "$MISSKEY_DIR" remote get-url origin)
case "$REMOTE_URL" in
	https://github.com/misskey-dev/misskey.git|git@github.com:misskey-dev/misskey.git|ssh://git@github.com/misskey-dev/misskey.git)
		;;
	*)
		fail "unexpected origin; refusing reset: $REMOTE_URL"
		;;
esac

declare -A PATCH_ID PATCH_DESCRIPTION PATCH_REQUIRED PATCH_INTRODUCED PATCH_UPSTREAM PATCH_SHA PATCH_ADDED
declare -a SERIES

load_patch_metadata() {
	[[ -r "$SERIES_FILE" ]] || fail "series missing: $SERIES_FILE"
	[[ -r "$MANIFEST_FILE" ]] || fail "manifest missing: $MANIFEST_FILE"
	mapfile -t SERIES < <(sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$SERIES_FILE")
	((${#SERIES[@]} > 0)) || fail 'patch series is empty'

	local id filename description required introduced upstream sha added extra
	while IFS=$'\t' read -r id filename description required introduced upstream sha added extra; do
		[[ "$id" == 'ID' ]] && continue
		[[ -z "$id" ]] && continue
		[[ -z "$extra" ]] || fail "manifest has unexpected extra field for $filename"
		safe_relative_path "$filename" || fail "unsafe patch filename: $filename"
		[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA256 for $filename"
		PATCH_ID["$filename"]=$id
		PATCH_DESCRIPTION["$filename"]=$description
		PATCH_REQUIRED["$filename"]=$required
		PATCH_INTRODUCED["$filename"]=$introduced
		PATCH_UPSTREAM["$filename"]=$upstream
		PATCH_SHA["$filename"]=$sha
		PATCH_ADDED["$filename"]=$added
	done < "$MANIFEST_FILE"

	local patch actual
	for patch in "${SERIES[@]}"; do
		safe_relative_path "$patch" || fail "unsafe series entry: $patch"
		[[ -n "${PATCH_SHA[$patch]:-}" ]] || fail "series entry absent from manifest: $patch"
		[[ -r "$PATCH_DIR/$patch" ]] || fail "patch missing: $PATCH_DIR/$patch"
		actual=$(sha256sum "$PATCH_DIR/$patch" | awk '{print $1}')
		[[ "$actual" == "${PATCH_SHA[$patch]}" ]] || fail "patch SHA256 mismatch: $patch"
	done
}

load_patch_metadata

step 'Validate canonical asset'
[[ -s "$ASSET_FILE" ]] || fail "asset missing or empty: $ASSET_FILE"
[[ -r "$ASSET_HASH_FILE" ]] || fail "asset checksum file missing: $ASSET_HASH_FILE"
ASSET_EXPECTED=$(awk 'NR == 1 { print $1 }' "$ASSET_HASH_FILE")
[[ "$ASSET_EXPECTED" =~ ^[0-9a-f]{64}$ ]] || fail 'invalid asset SHA256 file'
ASSET_ACTUAL=$(sha256sum "$ASSET_FILE" | awk '{print $1}')
[[ "$ASSET_ACTUAL" == "$ASSET_EXPECTED" ]] || fail 'asset SHA256 mismatch'
[[ "$(file --brief --mime-type "$ASSET_FILE")" == 'image/png' ]] || fail 'canonical asset is not PNG'
printf 'Asset SHA256: %s (%s bytes)\n' "$ASSET_ACTUAL" "$(stat -c %s "$ASSET_FILE")"

step 'Fetch official refs and resolve target'
as_misskey git -C "$MISSKEY_DIR" fetch --prune origin '+refs/tags/*:refs/tags/*' '+refs/heads/*:refs/remotes/origin/*'
if [[ "$MODE" == 'tag-select' ]]; then
	mapfile -t STABLE_TAGS < <(as_misskey git -C "$MISSKEY_DIR" tag --list | awk '/^[0-9]{4}\.[0-9]+\.[0-9]+$/ { print }' | sort -Vr | head -n 40)
	((${#STABLE_TAGS[@]} > 0)) || fail 'no stable release tags found'
	printf '\n正式release tag（新しい順）:\n'
	for index in "${!STABLE_TAGS[@]}"; do printf ' [%2d] %s\n' "$((index + 1))" "${STABLE_TAGS[index]}"; done
	while true; do
		read -r -p "タグ番号を選んでください [1-${#STABLE_TAGS[@]}]: " selection
		if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#STABLE_TAGS[@]} )); then
			TARGET_VALUE=${STABLE_TAGS[selection - 1]}
			MODE='tag'
			break
		fi
		printf '無効な選択です。\n'
	done
fi
case "$MODE" in
	stable)
		TARGET_LABEL=$(as_misskey git -C "$MISSKEY_DIR" tag --list | awk '/^[0-9]{4}\.[0-9]+\.[0-9]+$/ { print }' | sort -V | tail -n 1)
		[[ -n "$TARGET_LABEL" ]] || fail 'no stable release tag found'
		TARGET_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --verify "refs/tags/$TARGET_LABEL^{commit}")
		;;
	tag)
		TARGET_LABEL=$TARGET_VALUE
		TARGET_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --verify "refs/tags/$TARGET_LABEL^{commit}") || fail "official tag not found: $TARGET_LABEL"
		;;
	master)
		TARGET_LABEL='origin/master'
		TARGET_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --verify 'refs/remotes/origin/master^{commit}') || fail 'official origin/master not found'
		;;
	branch)
		as_misskey git check-ref-format --branch "$TARGET_VALUE" >/dev/null || fail 'invalid branch name'
		TARGET_LABEL="origin/$TARGET_VALUE"
		TARGET_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --verify "refs/remotes/origin/$TARGET_VALUE^{commit}") || fail "official branch not found: $TARGET_VALUE"
		;;
	commit)
		TARGET_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse --verify "$TARGET_VALUE^{commit}") || fail "commit not found after official fetch: $TARGET_VALUE"
		[[ "$TARGET_COMMIT" == "$TARGET_VALUE" ]] || fail 'resolved commit differs from requested commit'
		OFFICIAL_CONTAINING_REF=$(as_misskey git -C "$MISSKEY_DIR" for-each-ref --format='%(refname)' --contains "$TARGET_COMMIT" refs/remotes/origin refs/tags | sed -n '1p')
		[[ -n "$OFFICIAL_CONTAINING_REF" ]] || fail 'commit is not reachable from any fetched official branch or tag'
		TARGET_LABEL="commit/$TARGET_COMMIT"
		printf 'Official reachability: %s\n' "$OFFICIAL_CONTAINING_REF"
		;;
esac
printf 'Resolved target: %s (%s)\n' "$TARGET_LABEL" "$TARGET_COMMIT"
CURRENT_VERSION=$(current_version)
TARGET_VERSION=$(as_misskey git -C "$MISSKEY_DIR" show "$TARGET_COMMIT:package.json" | node -e "let s=''; process.stdin.on('data', c => s += c).on('end', () => process.stdout.write(JSON.parse(s).version ?? 'UNKNOWN'))")
CHANGE_DIRECTION='non-release'
if [[ "$CURRENT_VERSION" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ && "$TARGET_VERSION" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]]; then
	if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
		CHANGE_DIRECTION='same-version'
	elif [[ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$TARGET_VERSION" | sort -V | head -n 1)" == "$TARGET_VERSION" ]]; then
		CHANGE_DIRECTION='downgrade'
	else
		CHANGE_DIRECTION='upgrade'
	fi
fi
printf 'Current version: %s\nTarget version : %s\nDirection      : %s\n' "$CURRENT_VERSION" "$TARGET_VERSION" "$CHANGE_DIRECTION"
EXPECTED_PNPM=$(as_misskey git -C "$MISSKEY_DIR" show "$TARGET_COMMIT:package.json" | node -e "let s=''; process.stdin.on('data', c => s += c).on('end', () => { const p=JSON.parse(s).packageManager || ''; process.stdout.write(p.startsWith('pnpm@') ? p.slice(5) : ''); });")
[[ -n "$EXPECTED_PNPM" ]] || fail 'package.json has no pnpm packageManager'

check_patch_series() {
	step 'Check patch compatibility in an isolated official worktree'
	TMP_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-update3.XXXXXXXX")
	if (( EUID == 0 )); then
		chown "$MISSKEY_USER":"$(id -gn "$MISSKEY_USER")" "$TMP_WORKTREE"
	fi
	as_misskey git -C "$MISSKEY_DIR" worktree add --detach "$TMP_WORKTREE/tree" "$TARGET_COMMIT"

	local patch
	for patch in "${SERIES[@]}"; do
		[[ "${PATCH_REQUIRED[$patch]}" == 'required' ]] || fail "series contains a non-required patch: $patch"
		printf 'Checking %s %s [%s; %s; %s]\n' \
			"${PATCH_ID[$patch]}" "$patch" "${PATCH_DESCRIPTION[$patch]}" \
			"${PATCH_INTRODUCED[$patch]}" "${PATCH_UPSTREAM[$patch]}"
		if ! as_misskey git -C "$TMP_WORKTREE/tree" apply --check --whitespace=error-all "$PATCH_DIR/$patch"; then
			printf 'PATCH COMPATIBILITY FAILURE: %s\n' "$patch" >&2
			printf 'The change may already be upstream or the patch needs a reviewed refresh.\n' >&2
			exit 20
		fi
		as_misskey git -C "$TMP_WORKTREE/tree" apply --whitespace=error-all "$PATCH_DIR/$patch"
	done
	as_misskey git -C "$TMP_WORKTREE/tree" diff --check
	[[ -f "$TMP_WORKTREE/tree/packages/frontend/assets/unknown.png" ]] || fail 'frontend asset target path missing'
	if (( PATCH_ONLY == 0 )); then
		command -v corepack >/dev/null || fail 'corepack missing'
		# Verify the target-declared pnpm from the target worktree. Running this
		# against the live source would make cross-version updates fail when the
		# current and target packageManager/devEngines versions differ.
		# Expansion is intentionally done by the child Bash.
		# shellcheck disable=SC2016
		ACTUAL_PNPM=$(as_misskey bash -c 'cd -- "$1"; shift; exec corepack "$@"' \
			bash "$TMP_WORKTREE/tree" "pnpm@$EXPECTED_PNPM" --version)
		[[ "$ACTUAL_PNPM" == "$EXPECTED_PNPM" ]] || fail "pnpm mismatch: expected $EXPECTED_PNPM, got $ACTUAL_PNPM"
	fi
	printf 'PATCH PIPELINE CHECK PASS\n'
	as_misskey git -C "$MISSKEY_DIR" worktree remove --force "$TMP_WORKTREE/tree"
	rm -rf -- "$TMP_WORKTREE"
	TMP_WORKTREE=''
}

check_patch_series

if (( PATCH_ONLY == 1 )); then
	printf 'PATCH-ONLY CHECK COMPLETE: %s\n' "$TARGET_LABEL"
	exit 0
fi

step 'Runtime preflight'
command -v node >/dev/null || fail 'node missing'
command -v corepack >/dev/null || fail 'corepack missing'
command -v git >/dev/null || fail 'git missing'
command -v curl >/dev/null || fail 'curl missing'
command -v file >/dev/null || fail 'file missing'
AVAILABLE_KB=$(df -Pk "$MISSKEY_DIR" | awk 'NR == 2 { print $4 }')
(( AVAILABLE_KB >= MIN_FREE_KB )) || fail "insufficient disk: ${AVAILABLE_KB}KiB available, ${MIN_FREE_KB}KiB required"
printf 'Node=%s pnpm=%s free_kib=%s\n' "$(node --version)" "$ACTUAL_PNPM" "$AVAILABLE_KB"
if (( REQUIRE_ENV_FILE == 1 )); then
	[[ -r /root/.misskey.env || -r "$USER_ENV_FILE" ]] || fail 'required .misskey.env missing'
fi
systemctl cat "$SERVICE_NAME" >/dev/null || fail "systemd service missing: $SERVICE_NAME"
[[ -r "$MISSKEY_DIR/.config/default.yml" ]] || fail '.config/default.yml missing'

if (( CHECK_ONLY == 1 )); then
	printf 'DRY RUN COMPLETE: no service stop, patch application, build, migration, or restart occurred.\n'
	exit 0
fi

printf '\n%sDBバックアップは自動取得しません。必要な場合はメニュー5 / --db-backupを先に実行してください。%s\n' "$C_YELLOW" "$C_RESET"
if (( BACKUP_CONFIRMED == 1 )); then printf 'NOTICE: --backup-confirmed is accepted only for v3 CLI compatibility and is not required.\n'; fi
if (( INTERACTIVE == 1 )); then
	case "$MODE:$CHANGE_DIRECTION" in
		master:*)
			printf '%sWARNING: masterはstable releaseではなく、開発中コードを含む可能性があります。%s\n' "$C_RED" "$C_RESET"
			read -r -p 'masterへ強制リセットするには「master」と入力してください: ' answer
			[[ "$answer" == 'master' ]] || fail 'master reset confirmation did not match'
			;;
		*:downgrade)
			printf '%sこれはダウングレードです。新versionで適用済みのDB migrationと古いsourceは非互換になる可能性があります。%s\n' "$C_RED" "$C_RESET"
			read -r -p '続行するには「DOWNGRADE」と入力してください: ' answer
			[[ "$answer" == 'DOWNGRADE' ]] || fail 'downgrade confirmation did not match'
			;;
		*) confirm_yes "$CURRENT_VERSION → $TARGET_VERSION にアップデートしますか？" || { printf 'Cancelled.\n'; exit 0; } ;;
	esac
	ASSUME_YES=1
else
	(( ASSUME_YES == 1 )) || fail 'actual non-interactive update requires --yes'
	if [[ "$CHANGE_DIRECTION" == 'downgrade' ]]; then
		(( ALLOW_DOWNGRADE == 1 )) || fail 'CLI downgrade requires --allow-downgrade together with --yes'
	fi
fi

step 'Write pre-update metadata (no secret values)'
BACKUP_DIR="$STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$-${TARGET_LABEL//\//_}"
install -d -o root -g "$(id -gn "$MISSKEY_USER")" -m 0750 "$BACKUP_DIR"
OLD_COMMIT=$(as_misskey git -C "$MISSKEY_DIR" rev-parse HEAD)
OLD_VERSION=$(node -e "process.stdout.write(require(process.argv[1]).version)" "$MISSKEY_DIR/package.json")
{
	printf 'update3_version\t%s\n' "$UPDATE3_VERSION"
	printf 'timestamp\t%s\n' "$(date --iso-8601=seconds)"
	printf 'old_version\t%s\n' "$OLD_VERSION"
	printf 'old_commit\t%s\n' "$OLD_COMMIT"
	printf 'new_target\t%s\n' "$TARGET_LABEL"
	printf 'new_official_commit\t%s\n' "$TARGET_COMMIT"
	printf 'target_version\t%s\n' "$TARGET_VERSION"
	printf 'change_direction\t%s\n' "$CHANGE_DIRECTION"
	printf 'service_state\t%s\n' "$(systemctl is-active "$SERVICE_NAME" || true)"
	printf 'node\t%s\n' "$(node --version)"
	printf 'pnpm\t%s\n' "$ACTUAL_PNPM"
	printf 'asset_sha256\t%s\n' "$ASSET_ACTUAL"
	printf 'default_yml_sha256\t%s\n' "$(sha256sum "$MISSKEY_DIR/.config/default.yml" | awk '{print $1}')"
	printf 'systemd_unit_sha256\t%s\n' "$(systemctl cat "$SERVICE_NAME" --no-pager | sha256sum | awk '{print $1}')"
	if [[ -n "${POSTGRESQL_CONF:-}" && -r "$POSTGRESQL_CONF" ]]; then
		printf 'postgresql_conf_sha256\t%s\n' "$(sha256sum "$POSTGRESQL_CONF" | awk '{print $1}')"
	else
		printf 'postgresql_conf_sha256\tUNAVAILABLE\n'
	fi
} > "$BACKUP_DIR/metadata.tsv"
cp "$SERIES_FILE" "$MANIFEST_FILE" "$BACKUP_DIR/"
if [[ -f "$STATE_DIR/current-patch-manifest.tsv" && -f "$STATE_DIR/current-patch-series" ]]; then
	cp "$STATE_DIR/current-patch-manifest.tsv" "$BACKUP_DIR/pre-update-patch-manifest.tsv"
	cp "$STATE_DIR/current-patch-series" "$BACKUP_DIR/pre-update-patch-series"
else
	# First v4 run: the binary diff remains authoritative. These files describe
	# the Takusuki-managed paths restored by that diff.
	cp "$MANIFEST_FILE" "$BACKUP_DIR/pre-update-patch-manifest.tsv"
	cp "$SERIES_FILE" "$BACKUP_DIR/pre-update-patch-series"
fi
# The updater is root, while Git intentionally runs as the Misskey account. Let
# the root shell own the redirection so Git never needs directory write access.
as_misskey git -C "$MISSKEY_DIR" diff --binary > "$BACKUP_DIR/pre-update-working-tree.patch"
as_misskey git -C "$MISSKEY_DIR" diff > "$BACKUP_DIR/pre-update-tracked.patch"
as_misskey git -C "$MISSKEY_DIR" diff --name-only > "$BACKUP_DIR/pre-update-tracked-paths.txt"
as_misskey git -C "$MISSKEY_DIR" ls-files --others --exclude-standard -z > "$BACKUP_DIR/pre-update-untracked.list0"
tar -C "$MISSKEY_DIR" --null --verbatim-files-from --files-from="$BACKUP_DIR/pre-update-untracked.list0" -czf "$BACKUP_DIR/pre-update-untracked.tar.gz"
db_node ledger > "$BACKUP_DIR/pre-update-migrations.tsv"
sha256sum "$BACKUP_DIR/pre-update-migrations.tsv" | awk '{ print $1 }' > "$BACKUP_DIR/pre-update-migrations.sha256"
chmod 0600 "$BACKUP_DIR"/*

step 'Stop service after all compatibility checks pass'
UPDATE_STARTED_EPOCH=$(date +%s)
SERVICE_STOP_EPOCH=$UPDATE_STARTED_EPOCH
systemctl stop "$SERVICE_NAME"
[[ "$(systemctl is-active "$SERVICE_NAME" || true)" != 'active' ]] || fail 'service did not stop'

step 'Restore exact official source without broad git clean'
as_misskey git -C "$MISSKEY_DIR" reset --hard HEAD
remove_manifest_managed_paths "$STATE_DIR/current-patch-manifest.tsv"
for patch in "${SERIES[@]}"; do
	IFS=';' read -r -a managed_paths <<< "${PATCH_ADDED[$patch]:-}"
	for managed_path in "${managed_paths[@]}"; do
		[[ -z "$managed_path" ]] && continue
		safe_relative_path "$managed_path" || fail "unsafe managed path: $managed_path"
		rm -f -- "$MISSKEY_DIR/$managed_path"
	done
done
as_misskey git -C "$MISSKEY_DIR" checkout --detach "$TARGET_COMMIT"
as_misskey git -C "$MISSKEY_DIR" reset --hard "$TARGET_COMMIT"
as_misskey git -C "$MISSKEY_DIR" submodule update --init --recursive

step 'Apply required patch series'
for patch in "${SERIES[@]}"; do
	as_misskey git -C "$MISSKEY_DIR" apply --check --whitespace=error-all "$PATCH_DIR/$patch" || {
		printf 'PATCH COMPATIBILITY FAILURE: %s\n' "$patch" >&2
		exit 20
	}
	as_misskey git -C "$MISSKEY_DIR" apply --whitespace=error-all "$PATCH_DIR/$patch"
	printf '%s\t%s\t%s\n' "${PATCH_ID[$patch]}" "$patch" "${PATCH_SHA[$patch]}" | tee -a "$BACKUP_DIR/applied-patches.tsv"
done
as_misskey git -C "$MISSKEY_DIR" diff --check
as_misskey git -C "$MISSKEY_DIR" status --short
as_misskey git -C "$MISSKEY_DIR" diff --stat

step 'Install canonical asset'
install -o "$MISSKEY_USER" -g "$(id -gn "$MISSKEY_USER")" -m 0644 "$ASSET_FILE" "$MISSKEY_DIR/packages/frontend/assets/unknown.png"
[[ "$(sha256sum "$MISSKEY_DIR/packages/frontend/assets/unknown.png" | awk '{print $1}')" == "$ASSET_ACTUAL" ]] || fail 'installed asset checksum mismatch'

step 'Install dependencies and build'
as_misskey env CI=true NODE_ENV=production corepack "pnpm@$EXPECTED_PNPM" --dir "$MISSKEY_DIR" install --frozen-lockfile --prefer-offline
as_misskey env CI=true NODE_ENV=production corepack "pnpm@$EXPECTED_PNPM" --dir "$MISSKEY_DIR" run build
[[ -f "$MISSKEY_DIR/packages/backend/built/config.js" ]] || fail 'packages/backend/built/config.js missing after build'

step 'Run migration (fail-closed; DB backup is an independent operation)'
MIGRATION_STARTED=1
as_misskey env CI=true NODE_ENV=production corepack "pnpm@$EXPECTED_PNPM" --dir "$MISSKEY_DIR" run migrate

step 'Start service and perform bounded health checks'
systemctl start "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME" || fail 'systemd service is not active'
run_health_checks
SERVICE_START_EPOCH=$(date +%s)
DOWNTIME_SECONDS=$((SERVICE_START_EPOCH - SERVICE_STOP_EPOCH))

cp "$MANIFEST_FILE" "$STATE_DIR/current-patch-manifest.tsv"
cp "$SERIES_FILE" "$STATE_DIR/current-patch-series"
db_node ledger > "$BACKUP_DIR/post-update-migrations.tsv"
sha256sum "$BACKUP_DIR/post-update-migrations.tsv" | awk '{ print $1 }' > "$BACKUP_DIR/post-update-migrations.sha256"
{
	printf 'timestamp\t%s\n' "$(date --iso-8601=seconds)"
	printf 'old_version\t%s\n' "$OLD_VERSION"
	printf 'new_version\t%s\n' "$(node -e "process.stdout.write(require(process.argv[1]).version)" "$MISSKEY_DIR/package.json")"
	printf 'old_commit\t%s\n' "$OLD_COMMIT"
	printf 'new_official_commit\t%s\n' "$TARGET_COMMIT"
	printf 'asset_sha256\t%s\n' "$ASSET_ACTUAL"
	printf 'install\tPASS\n'
	printf 'build\tPASS\n'
	printf 'migration\tPASS\n'
	printf 'service\tPASS\n'
	printf 'health\tPASS\n'
	printf 'service_downtime_seconds\t%s\n' "$DOWNTIME_SECONDS"
} > "$BACKUP_DIR/result.tsv"

printf '\n============================================================\n 更新完了\n============================================================\n'
printf '旧Version : %s\n新Version : %s\n\n' "$OLD_VERSION" "$(current_version)"
for patch in "${SERIES[@]}"; do printf 'Patch [OK] %s %s\n' "${PATCH_ID[$patch]}" "${PATCH_DESCRIPTION[$patch]}"; done
printf '\nInstall   : PASS\nBuild     : PASS\nMigration : PASS\nService   : PASS\nHealth    : PASS\n停止時間 : %s秒\nMetadata : %s\nLog      : %s\n' "$DOWNTIME_SECONDS" "$BACKUP_DIR" "$LOG_FILE"
