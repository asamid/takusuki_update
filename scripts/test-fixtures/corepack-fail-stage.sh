#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Test-only Corepack proxy used by the isolated Staging validation.
set -Eeuo pipefail

case " ${TAKUSUKI_FAIL_STAGE:-} " in
	' build '|' migrate ') ;;
	*) exec /usr/bin/corepack "$@" ;;
esac

if [[ " $* " == *" run ${TAKUSUKI_FAIL_STAGE} "* ]]; then
	printf 'INTENTIONAL STAGING FAILURE: %s\n' "$TAKUSUKI_FAIL_STAGE" >&2
	exit 97
fi
exec /usr/bin/corepack "$@"
