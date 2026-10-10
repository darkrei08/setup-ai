#!/usr/bin/env bash
# Legacy rotator cleanup must require an exact, home-scoped ownership proof.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-legacy-rotator.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

sed -n '/^uninstall_path_in_home() {/,/^}/p; /^uninstall_remove_legacy_rotator_unit() {/,/^}/p' \
    "${ROOT}/setup-ai.sh" > "${TEST_DIR}/functions.sh"
source "${TEST_DIR}/functions.sh"
HOME="${TEST_DIR}/home"
XDG_CONFIG_HOME="${HOME}/.config"
TMP_DIR="${TEST_DIR}/tmp"
DRY_RUN=0
mkdir -p "${XDG_CONFIG_HOME}/systemd/user" "${TMP_DIR}"
run_optional() { :; }
unit="${XDG_CONFIG_HOME}/systemd/user/tuxevil-rotator.service"
bin="${HOME}/.nvm/bin/tuxevil-rotator"

cat > "${unit}" <<'UNIT'
[Unit]
Description=unrelated user service
UNIT
uninstall_remove_legacy_rotator_unit tuxevil-rotator.service >/dev/null
[[ -f "${unit}" ]] || { echo 'FAIL: unowned systemd unit was removed' >&2; exit 1; }

cat > "${unit}" <<UNIT
[Unit]
Description=tuxevil-rotator multi-account Gemini/Antigravity gateway
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
ExecStart="${bin}" start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
printf '# user edit\n' >> "${unit}"
uninstall_remove_legacy_rotator_unit tuxevil-rotator.service >/dev/null
[[ -f "${unit}" ]] || { echo 'FAIL: modified unit was removed' >&2; exit 1; }

cat > "${unit}" <<UNIT
[Unit]
Description=tuxevil-rotator multi-account Gemini/Antigravity gateway
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
ExecStart="${bin}" start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
uninstall_remove_legacy_rotator_unit tuxevil-rotator.service >/dev/null
[[ ! -e "${unit}" ]] || { echo 'FAIL: exact setup-ai unit was not removed' >&2; exit 1; }

if grep -Fq 'npm-global|legacy-rotator|tuxevil-rotator' "${ROOT}/setup-ai.sh" ||
    grep -Fq 'path|legacy-rotator|' "${ROOT}/setup-ai.sh"; then
    echo 'FAIL: legacy uninstall claims ownership of unreceipted npm or account data' >&2
    exit 1
fi
grep -Fq 'pi-package|legacy-rotator|git:github.com/darkrei08/pi-cockpit-tools-sync' "${ROOT}/setup-ai.sh" || {
    echo 'FAIL: receipted legacy Pi package uninstall path is missing' >&2; exit 1;
}
printf 'PASS: legacy rotator cleanup removes only exact owned resources\n'
