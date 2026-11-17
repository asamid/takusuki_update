#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are consumed by functions sourced below.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly ROOT
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/takusuki-v5.1-tests.XXXXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

awk '
	/^release_version_ge\(\) \{/ { capture=1 }
	/^interactive_menu\(\) \{/ { capture=0 }
	capture { print }
' "$ROOT/takusuki_update5.sh" > "$TEST_ROOT/runtime-functions.sh"

awk '
	/^normalize_service_name\(\) \{/ { capture=1 }
	capture { print }
	capture && /^}/ { exit }
' "$ROOT/takusuki_update5.sh" > "$TEST_ROOT/service-name-function.sh"

fail() { printf 'EXPECTED_FAIL: %s\n' "$*" >&2; exit 91; }
# shellcheck disable=SC1091
source "$TEST_ROOT/runtime-functions.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/service-name-function.sh"

assert_eq() {
	[[ "$1" == "$2" ]] || { printf 'ASSERTION FAILED: expected <%s>, got <%s>\n' "$2" "$1" >&2; exit 1; }
}

assert_eq "$(normalize_service_name 'takusuki.com')" 'takusuki.com.service'
assert_eq "$(normalize_service_name 'takusuki.com.service')" 'takusuki.com.service'
assert_eq "$(normalize_service_name '../unsafe')" '../unsafe'
if [[ "$(normalize_service_name '../unsafe')" =~ ^[A-Za-z0-9_.@-]+\.service$ ]]; then
	fail 'unsafe service name was accepted'
fi
grep -Fq "releases/download/v\${UPDATER_VERSION}/takusuki-update5-bundle.zip" \
	"$ROOT/takusuki_update5.sh" || fail 'default bundle URL is not release-pinned'

release_version_ge 2026.11.0 2026.11.0
release_version_ge 2027.1.0 2026.11.0
if release_version_ge 2026.10.99 2026.11.0; then fail 'numeric version comparison regressed'; fi

fake_node="$TEST_ROOT/node"
printf '#!/usr/bin/env bash\nprintf "v26.13.1\\n"\n' > "$fake_node"
chmod 0755 "$fake_node"
node_satisfies_engine "$fake_node" '^24.22.3 || ^26.13.1'
printf '#!/usr/bin/env bash\nprintf "v26.12.1\\n"\n' > "$fake_node"
if node_satisfies_engine "$fake_node" '^24.22.3 || ^26.13.1'; then fail 'insufficient Node.js was accepted'; fi
printf '#!/usr/bin/env bash\nprintf "v22.22.0\\n"\n' > "$fake_node"
if node_satisfies_engine "$fake_node" '^24.22.3 || ^26.13.1'; then fail 'unsupported Node.js major was accepted'; fi

SERVICE_NAME='fixture.service'
MISSKEY_DIR="$TEST_ROOT/misskey"
TARGET_COMMIT='0123456789012345678901234567890123456789'
START_MJS_VERSION='2026.11.0'
mkdir -p "$MISSKEY_DIR"

systemctl() {
	case "$*" in
		'show -p ExecStart --value fixture.service') printf '%s\n' "$FIXTURE_EXECSTART" ;;
		'show -p Type --value fixture.service') printf 'simple\n' ;;
		*) printf 'unexpected mock systemctl call: %s\n' "$*" >&2; return 1 ;;
	esac
}
as_misskey() {
	case "$*" in
		*'cat-file -e'*':scripts/start.mjs') [[ "$START_MJS_PRESENT" == 1 ]] ;;
		*) printf 'unexpected mock as_misskey call: %s\n' "$*" >&2; return 1 ;;
	esac
}

node_path=$(readlink -f "$(command -v node)")
mkdir -p "$TEST_ROOT/runtime/bin"
ln -s "$node_path" "$TEST_ROOT/runtime/bin/node"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/runtime/bin/npm"
chmod 0755 "$TEST_ROOT/runtime/bin/npm"
npm_path="$TEST_ROOT/runtime/bin/npm"
START_MJS_PRESENT=1

TARGET_VERSION='2026.10.9'
FIXTURE_EXECSTART="{ path=$npm_path ; argv[]=$npm_path start ; ignore_errors=no ; }"
build_systemd_start_plan
assert_eq "$SYSTEMD_PLAN_ACTION" 'none'
assert_eq "$TARGET_START_STYLE" 'legacy'

TARGET_VERSION='2026.11.0'
FIXTURE_EXECSTART="{ path=/usr/bin/env ; argv[]=/usr/bin/env NODE_OPTIONS=--max-old-space-size=4096 $npm_path start ; ignore_errors=no ; }"
build_systemd_start_plan
assert_eq "$SYSTEMD_PLAN_ACTION" 'write'
assert_eq "$TARGET_START_STYLE" 'start.mjs'
[[ "$SYSTEMD_DROPIN_CONTENT" == *'NODE_OPTIONS=--max-old-space-size=4096'* ]]
[[ "$SYSTEMD_DROPIN_CONTENT" == *'./scripts/start.mjs'* ]]
[[ "$SYSTEMD_DROPIN_CONTENT" != *'--migrate'* ]]

FIXTURE_EXECSTART="{ path=$node_path ; argv[]=$node_path --max-old-space-size=6144 ./packages/backend/built/entry.js ; ignore_errors=no ; }"
build_systemd_start_plan
assert_eq "$SYSTEMD_PLAN_ACTION" 'write'
[[ "$SYSTEMD_DROPIN_CONTENT" == *'--max-old-space-size=6144'* ]]

FIXTURE_EXECSTART="{ path=$node_path ; argv[]=$node_path ./scripts/start.mjs ; ignore_errors=no ; }"
build_systemd_start_plan
assert_eq "$SYSTEMD_PLAN_ACTION" 'none'
assert_eq "$SERVICE_START_STYLE" 'start.mjs'

if (
	FIXTURE_EXECSTART='{ path=/opt/custom/launcher ; argv[]=/opt/custom/launcher serve ; ignore_errors=no ; }'
	build_systemd_start_plan
); then
	fail 'unknown custom ExecStart was overwritten'
fi

if (
	START_MJS_PRESENT=0
	FIXTURE_EXECSTART="{ path=$npm_path ; argv[]=$npm_path start ; ignore_errors=no ; }"
	build_systemd_start_plan
); then
	fail 'missing target start.mjs was accepted'
fi

python3 - "$ROOT/takusuki_update5.sh" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
dry_run = text.index("if (( CHECK_ONLY == 1 )); then")
dry_run_exit = text.index('exit 0', dry_run)
metadata = text.index("step 'Write pre-update metadata", dry_run_exit)
unit_apply = text.index('apply_systemd_start_plan', metadata)
if not dry_run < dry_run_exit < metadata < unit_apply:
    raise SystemExit('--check can reach a service/unit mutation')
migrate = text.index("run migrate")
apply_plan = text.index("apply_systemd_start_plan", migrate)
start = text.index('systemctl start "$SERVICE_NAME"', apply_plan)
if not migrate < apply_plan < start:
    raise SystemExit('systemd mutation/start ordering is not fail-closed')
rollback_restore = text.index('restore_systemd_managed_state')
rollback_start = text.index('systemctl start "$SERVICE_NAME"', rollback_restore)
if not rollback_restore < rollback_start:
    raise SystemExit('rollback does not restore systemd state before start')
print('FAIL-CLOSED ORDERING: PASS')
PY

printf 'V5.1 RUNTIME TESTS: PASS\n'
