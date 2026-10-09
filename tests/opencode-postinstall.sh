#!/usr/bin/env bash
# npm 12 blocks opencode-ai's postinstall, leaving a stub launcher that exits 1.
# mod_opencode must approve the script, rebuild, and gate on `opencode --version`.
# Fake tools only; no real install runs.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-opencode.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

awk '$0 ~ /^mod_opencode\(\) \{/ { c = 1 } c { l = $0; d += gsub(/\{/, "", l) - gsub(/\}/, "", l); print; if (d == 0) exit }' \
    "${ROOT}/setup-ai.sh" > "${TEST_DIR}/module.sh"
source "${TEST_DIR}/module.sh"

mkdir -p "${TEST_DIR}/bin"
# Fake npm: `install-scripts` exists (npm >= 12) only while the "supported" flag file exists.
printf '#!/bin/sh\necho "npm $*" >> "%s/calls"\n[ "$1" = install-scripts ] && [ ! -e "%s/supported" ] && exit 1\nexit 0\n' \
    "${TEST_DIR}" "${TEST_DIR}" > "${TEST_DIR}/bin/npm"
touch "${TEST_DIR}/supported"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/bin/opencode"   # the stub launcher
chmod +x "${TEST_DIR}/bin/"*
PATH="${TEST_DIR}/bin:${PATH}"

DRY_RUN=0
HUMAN_LOG="${TEST_DIR}/human.log"
section() { :; }
log_event() { :; }
verify_opencode_spawn() { :; }
run_cmd() {
    local phase="$1" optional=0; shift
    while [[ "${1:-}" == --* ]]; do [[ "$1" == --optional ]] && optional=1; shift; done
    "$@" || { (( optional == 1 )) && return 1; exit 1; }   # the real run_cmd aborts on failure
}
run_optional() { local phase="$1"; shift; run_cmd "${phase}" --optional "$@" || :; }

failures=0
check() { if "$@"; then printf 'PASS: %s\n' "$1"; else printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); fi; }

rc=0
( mod_opencode ) >/dev/null 2>&1 || rc=$?
rebuild_approved() { grep -q 'npm rebuild -g opencode-ai --allow-scripts=opencode-ai --foreground-scripts' "${TEST_DIR}/calls"; }
stub_fails_module() { (( rc != 0 )); }
check rebuild_approved
check stub_fails_module

printf '#!/bin/sh\nexit 0\n' > "${TEST_DIR}/bin/opencode"
rc=0
( mod_opencode ) >/dev/null 2>&1 || rc=$?
real_launcher_passes() { (( rc == 0 )); }
check real_launcher_passes

rm "${TEST_DIR}/supported"
: > "${TEST_DIR}/calls"
( mod_opencode ) >/dev/null 2>&1
rebuild_ungated() { grep -q 'npm rebuild -g opencode-ai' "${TEST_DIR}/calls" && ! grep -q -- '--allow-scripts' "${TEST_DIR}/calls"; }
check rebuild_ungated

exit $(( failures > 0 ))
