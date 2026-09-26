#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export HOME="${TMPDIR:-/tmp}/setup-ai-systemd-home-${BASHPID}"
export DRY_RUN=1
source <(sed '/^# Main$/,$d' "${repo}/setup-ai.sh")
SCRIPT_DIR="${repo}"
DRY_RUN=0
TEST_ROOT="${TMP_DIR}/rotator-systemd"
HOME="${TEST_ROOT}/home"
PI_AGENT_DIR="${HOME}/.pi/agent"
PI_EXTENSIONS_DIR="${PI_AGENT_DIR}/extensions"
PI_NPM_DIR="${PI_AGENT_DIR}/npm"
DOTENV_DIR="${HOME}/git/personale/dotenv"
DOTENV_EXT_DIR="${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows"
mkdir -p "${HOME}"
FAKE_SYSTEMCTL_LOG="${TEST_ROOT}/systemctl.log"
FAKE_NPM_LOG="${TEST_ROOT}/npm.log"
FAKE_SYSTEMCTL_FAIL=""
FAKE_SYSTEMCTL_STATE="loaded"
FAKE_SYSTEMCTL_SHOW_CALLS=0
FAKE_SYSTEMCTL_RELOAD_CALLS=0
FAKE_RM_FAIL_UNIT=0
FAKE_RM_KEEP_UNIT=0
FAKE_RM_FAIL_RECEIPT=0
FAKE_RM_KEEP_RECEIPT=0
FAKE_RECEIPT_RM_CHECK=0
FAKE_NPM_UNINSTALL_CALLS=0
mkdir -p "${TEST_ROOT}"
export FAKE_SYSTEMCTL_LOG FAKE_NPM_LOG

tuxevil-rotator() { :; }

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

systemctl() {
    local IFS=' '
    printf '%s\n' "$*" >>"${FAKE_SYSTEMCTL_LOG}"
    case "$*" in
        '--user show-environment') [[ "${FAKE_SYSTEMCTL_FAIL}" != show-environment ]] ;;
        '--user enable tuxevil-rotator.service') [[ "${FAKE_SYSTEMCTL_FAIL}" != enable ]] ;;
        '--user stop tuxevil-rotator.service') [[ "${FAKE_SYSTEMCTL_FAIL}" != stop ]] ;;
        '--user disable tuxevil-rotator.service') [[ "${FAKE_SYSTEMCTL_FAIL}" != disable ]] ;;
        '--user daemon-reload')
            FAKE_SYSTEMCTL_RELOAD_CALLS=$((FAKE_SYSTEMCTL_RELOAD_CALLS + 1))
            [[ "${FAKE_SYSTEMCTL_FAIL}" != daemon-reload && ! ( "${FAKE_SYSTEMCTL_FAIL}" == daemon-reload-after-remove && "${FAKE_SYSTEMCTL_RELOAD_CALLS}" -eq 2 ) ]] ;;
        '--user show tuxevil-rotator.service --property=LoadState --property=ActiveState --property=UnitFileState --value')
            FAKE_SYSTEMCTL_SHOW_CALLS=$((FAKE_SYSTEMCTL_SHOW_CALLS + 1))
            [[ "${FAKE_SYSTEMCTL_FAIL}" != show-state && ! ( "${FAKE_SYSTEMCTL_FAIL}" == show-state-after-remove && ! -e "${FAKE_UNIT_PATH}" && ! -L "${FAKE_UNIT_PATH}" ) ]] || return 1
            if [[ ! -e "${FAKE_UNIT_PATH}" && ! -L "${FAKE_UNIT_PATH}" ]]; then
                printf 'not-found\ninactive\nnot-found\n'
            elif [[ "${FAKE_SYSTEMCTL_STATE}" == loaded ]]; then
                printf 'loaded\ninactive\ndisabled\n'
            else
                printf 'not-found\ninactive\nnot-found\n'
            fi
            ;;
        *) printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2; return 2 ;;
    esac
}

npm() {
    local IFS=' '
    printf '%s\n' "$*" >>"${FAKE_NPM_LOG}"
    case "$*" in
        'root -g') printf '%s\n' "${FAKE_NPM_ROOT}" ;;
        'uninstall --global tuxevil-rotator')
            FAKE_NPM_UNINSTALL_CALLS=$((FAKE_NPM_UNINSTALL_CALLS + 1))
            if [[ -e "${FAKE_UNIT_PATH}" || -L "${FAKE_UNIT_PATH}" || -e "${FAKE_SYSTEMD_RECEIPT}" || -L "${FAKE_SYSTEMD_RECEIPT}" ]]; then
                printf 'npm uninstall reached before systemd ownership was cleared\n' >&2
                return 9
            fi
            command rm -rf -- "${FAKE_NPM_ROOT}/tuxevil-rotator"
            ;;
        *) printf 'unexpected fake npm arguments: %s\n' "$*" >&2; return 2 ;;
    esac
}

rm() {
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == "${FAKE_UNIT_PATH:-}" && "${FAKE_RM_FAIL_UNIT}" == 1 ]]; then return 1; fi
        if [[ "${arg}" == "${FAKE_UNIT_PATH:-}" && "${FAKE_RM_KEEP_UNIT}" == 1 ]]; then return 0; fi
        if [[ "${arg}" == "${FAKE_SYSTEMD_RECEIPT:-}" && "${FAKE_RM_FAIL_RECEIPT}" == 1 ]]; then return 1; fi
        if [[ "${arg}" == "${FAKE_SYSTEMD_RECEIPT:-}" && "${FAKE_RM_KEEP_RECEIPT}" == 1 ]]; then return 0; fi
        if [[ "${arg}" == "${FAKE_SYSTEMD_RECEIPT:-}" && "${FAKE_RECEIPT_RM_CHECK}" == 1 ]]; then
            [[ ! -e "${FAKE_UNIT_PATH}" && ! -L "${FAKE_UNIT_PATH}" ]] || fail 'systemd receipt was removed before verified unit absence'
        fi
    done
    command rm "$@"
}

reset_case() {
    local name="$1"
    XDG_CONFIG_HOME="${TEST_ROOT}/${name}/config"
    XDG_STATE_HOME="${TEST_ROOT}/${name}/state"
    FAKE_UNIT_PATH="${XDG_CONFIG_HOME}/systemd/user/tuxevil-rotator.service"
    FAKE_SYSTEMD_RECEIPT="${XDG_STATE_HOME}/setup-ai/ownership/rotator-systemd.json"
    FAKE_NPM_ROOT="${TEST_ROOT}/${name}/npm"
    FAKE_SYSTEMCTL_FAIL=""
    FAKE_SYSTEMCTL_STATE=loaded
    FAKE_SYSTEMCTL_SHOW_CALLS=0
    FAKE_SYSTEMCTL_RELOAD_CALLS=0
    FAKE_RM_FAIL_UNIT=0
    FAKE_RM_KEEP_UNIT=0
    FAKE_RM_FAIL_RECEIPT=0
    FAKE_RM_KEEP_RECEIPT=0
    FAKE_RECEIPT_RM_CHECK=0
    FAKE_NPM_UNINSTALL_CALLS=0
    ROTATOR_SYSTEMD_UNINSTALL_BLOCKED=0
    ROTATOR_SYSTEMD_UNINSTALL_CHECKED=0
    mkdir -p "${TEST_ROOT}/${name}" "${FAKE_NPM_ROOT}"
    : >"${FAKE_SYSTEMCTL_LOG}"
    : >"${FAKE_NPM_LOG}"
    export XDG_CONFIG_HOME XDG_STATE_HOME FAKE_UNIT_PATH FAKE_SYSTEMD_RECEIPT FAKE_NPM_ROOT
}

create_npm_receipt() {
    local marker=0123456789abcdef0123456789abcdef receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
    mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator" "$(dirname -- "${receipt}")"
    printf '{"name":"tuxevil-rotator","version":"1.2.3"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
    printf '%s' "${marker}" >"${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership"
    node -e 'const fs=require("node:fs"),root=process.argv[1],path=process.argv[2],marker=process.argv[3];fs.writeFileSync(path,JSON.stringify({schemaVersion:2,package:"tuxevil-rotator",npmRoot:root,packagePath:`${root}/tuxevil-rotator/package.json`,version:"1.2.3",marker}));' \
        "${FAKE_NPM_ROOT}" "${receipt}" "${marker}"
}

create_owned_unit() {
    ensure_rotator_unit || fail 'could not create fake receipt-owned systemd unit'
    [[ -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'unit creation did not publish its receipt'
}

# Fresh install is the regression case: the unit and receipt must be created together.
reset_case fresh
create_owned_unit
unit_before="$(cat "${FAKE_UNIT_PATH}")"
node -e 'const fs=require("node:fs"),r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(r.schemaVersion!==1||r.unitPath!==process.argv[2]||!/^[0-9a-f]{64}$/.test(r.fingerprint))process.exit(1)' \
    "${FAKE_SYSTEMD_RECEIPT}" "${FAKE_UNIT_PATH}" || fail 'fresh unit receipt did not contain the stable path and fingerprint'
expected_unit="$(printf '[Unit]\nDescription=tuxevil-rotator multi-account Gemini/Antigravity gateway\nStartLimitIntervalSec=300\nStartLimitBurst=5\n\n[Service]\nExecStart="tuxevil-rotator" start\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target')"
[[ "${unit_before}" == "${expected_unit}" ]] || fail 'fresh unit content did not match the canonical unit text'

# Existing regular units, symlinks, and units changed since receipt creation are never rewritten or claimed.
reset_case existing
mkdir -p "$(dirname -- "${FAKE_UNIT_PATH}")"
printf 'user-owned unit\n' >"${FAKE_UNIT_PATH}"
ensure_rotator_unit || fail 'existing unit check failed'
[[ "$(cat "${FAKE_UNIT_PATH}")" == 'user-owned unit' && ! -e "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'existing unit was overwritten or claimed'

reset_case symlink
mkdir -p "$(dirname -- "${FAKE_UNIT_PATH}")"
outside="${TEST_ROOT}/symlink-sentinel"
printf 'outside unit\n' >"${outside}"
ln -s -- "${outside}" "${FAKE_UNIT_PATH}"
ensure_rotator_unit || fail 'symlink unit check failed'
[[ -L "${FAKE_UNIT_PATH}" && "$(cat "${outside}")" == 'outside unit' && ! -e "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'symlinked unit or its target changed'

reset_case modified
create_owned_unit
receipt_before="$(cat "${FAKE_SYSTEMD_RECEIPT}")"
printf 'externally modified\n' >"${FAKE_UNIT_PATH}"
ensure_rotator_unit || fail 'modified unit check failed'
[[ "$(cat "${FAKE_UNIT_PATH}")" == 'externally modified' && "$(cat "${FAKE_SYSTEMD_RECEIPT}")" == "${receipt_before}" ]] || fail 'modified unit or stale receipt was changed'

# Receipt collisions fail before unit creation; a publication failure rolls back only this call's unit.
reset_case receipt-collision
mkdir -p "$(dirname -- "${FAKE_SYSTEMD_RECEIPT}")"
printf 'preserve receipt\n' >"${FAKE_SYSTEMD_RECEIPT}"
ensure_rotator_unit || fail 'receipt collision should be a safe skip'
[[ ! -e "${FAKE_UNIT_PATH}" && "$(cat "${FAKE_SYSTEMD_RECEIPT}")" == 'preserve receipt' ]] || fail 'receipt collision claimed a unit or overwrote the receipt'

reset_case unsafe-receipt-path
outside_state="${TEST_ROOT}/outside-state"
mkdir -p "${outside_state}"
ln -s -- "${outside_state}" "${XDG_STATE_HOME}"
if ensure_rotator_unit; then fail 'symlinked receipt directory was accepted'; fi
[[ ! -e "${FAKE_UNIT_PATH}" && ! -e "${outside_state}/setup-ai/ownership/rotator-systemd.json" ]] || fail 'unsafe receipt path created an unowned unit or receipt'

reset_case exclusive-race
eval "$(declare -f rotator_systemd_create_unit | sed '1s/rotator_systemd_create_unit/real_rotator_systemd_create_unit/')"
rotator_systemd_create_unit() {
    printf 'racing unit\n' >"$1"
    real_rotator_systemd_create_unit "$@"
}
if ensure_rotator_unit; then fail 'exclusive creation accepted a unit that appeared after preflight'; fi
[[ "$(cat "${FAKE_UNIT_PATH}")" == 'racing unit' && ! -e "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'exclusive-create collision overwrote or claimed a racing unit'
unset -f rotator_systemd_create_unit
eval "$(declare -f real_rotator_systemd_create_unit | sed '1s/real_rotator_systemd_create_unit/rotator_systemd_create_unit/')"
unset -f real_rotator_systemd_create_unit

reset_case receipt-publication-failure
eval "$(declare -f rotator_systemd_publish_receipt | sed '1s/rotator_systemd_publish_receipt/real_rotator_systemd_publish_receipt/')"
rotator_systemd_publish_receipt() {
    printf 'racing receipt\n' >"$1"
    real_rotator_systemd_publish_receipt "$@"
}
if ensure_rotator_unit; then fail 'receipt publication collision was reported as success'; fi
[[ ! -e "${FAKE_UNIT_PATH}" && ! -L "${FAKE_UNIT_PATH}" && "$(cat "${FAKE_SYSTEMD_RECEIPT}")" == 'racing receipt' ]] || fail 'receipt publication collision left an unowned unit or overwrote the colliding receipt'
unset -f rotator_systemd_publish_receipt
eval "$(declare -f real_rotator_systemd_publish_receipt | sed '1s/real_rotator_systemd_publish_receipt/rotator_systemd_publish_receipt/')"
unset -f real_rotator_systemd_publish_receipt

# A transient enable failure leaves a receipt-owned unit that a later run retries.
reset_case enable-retry
FAKE_SYSTEMCTL_FAIL=enable
ensure_rotator_unit || fail 'transient enable failure was not safely preserved'
[[ -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'enable failure did not preserve the owned unit and receipt'
FAKE_SYSTEMCTL_FAIL=""
ensure_rotator_unit || fail 'enable retry failed'
[[ "$(grep -c '^--user enable tuxevil-rotator.service$' "${FAKE_SYSTEMCTL_LOG}")" -ge 2 ]] || fail 'owned unit enable was not retried'

# Inventory and dry-run classify without changing either file or invoking mutating systemctl operations.
reset_case inventory
create_owned_unit
unit_before="$(cat "${FAKE_UNIT_PATH}")"
receipt_before="$(cat "${FAKE_SYSTEMD_RECEIPT}")"
SELECTED_MODULES=(rotator)
inventory="$(uninstall_print_inventory)"
[[ "${inventory}" == *'tuxevil-rotator.service (receipt-backed; removable)'* ]] || fail 'inventory did not identify the matching unit receipt'
DRY_RUN=1
uninstall_remove_systemd_unit tuxevil-rotator.service || fail 'owned-unit dry-run failed'
DRY_RUN=0
[[ "$(cat "${FAKE_UNIT_PATH}")" == "${unit_before}" && "$(cat "${FAKE_SYSTEMD_RECEIPT}")" == "${receipt_before}" ]] || fail 'inventory or dry-run mutated unit ownership state'
if grep -Eq '^--user (stop|disable|daemon-reload) ' "${FAKE_SYSTEMCTL_LOG}"; then fail 'inventory or dry-run invoked mutating systemctl'; fi

reset_case protected-inventory
mkdir -p "$(dirname -- "${FAKE_UNIT_PATH}")"
printf 'unowned\n' >"${FAKE_UNIT_PATH}"
SELECTED_MODULES=(rotator)
inventory="$(uninstall_print_inventory)"
[[ "${inventory}" == *'tuxevil-rotator.service (protected: unowned or mismatched)'* ]] || fail 'inventory did not label the unowned unit as protected'
unit_before="$(cat "${FAKE_UNIT_PATH}")"
DRY_RUN=1
if uninstall_remove_systemd_unit tuxevil-rotator.service 2>"${TEST_ROOT}/dry-run-protected.err"; then fail 'dry-run did not block an unowned systemd unit'; fi
DRY_RUN=0
[[ "$(cat "${FAKE_UNIT_PATH}")" == "${unit_before}" && "$(cat "${TEST_ROOT}/dry-run-protected.err")" == *'blocked (systemd ownership not verified)'* ]] || fail 'protected dry-run changed the unit or failed to label it'

# Successful uninstall removes the unit and its receipt before fake npm is reached.
reset_case ordered-removal
create_owned_unit
create_npm_receipt
FAKE_RECEIPT_RM_CHECK=1
SELECTED_MODULES=(rotator)
UNINSTALL_YES=1
UNINSTALL_PURGE=0
run_uninstall || fail 'receipt-owned unit and npm package removal failed'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 1 && ! -e "${FAKE_UNIT_PATH}" && ! -e "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'systemd-owned unit was not cleared before npm removal'

# Stop/disable/daemon uncertainty, unit unlink failure, a surviving unit, and unsafe ownership all block npm.
for failure in show-environment stop disable daemon-reload show-state; do
    reset_case "systemctl-${failure}"
    create_owned_unit
    create_npm_receipt
    FAKE_SYSTEMCTL_FAIL="${failure}"
    if uninstall_remove_rotator_npm; then fail "${failure} failure did not block npm removal"; fi
    [[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail "${failure} failure did not preserve unit, receipt, and package"
done

for failure in daemon-reload-after-remove show-state-after-remove; do
    reset_case "systemctl-${failure}"
    create_owned_unit
    create_npm_receipt
    FAKE_SYSTEMCTL_FAIL="${failure}"
    if uninstall_remove_rotator_npm; then fail "${failure} failure did not block npm removal"; fi
    [[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail "${failure} failure did not restore the unit and preserve the package"
done

reset_case removal-failure
create_owned_unit
create_npm_receipt
FAKE_RM_FAIL_UNIT=1
if uninstall_remove_rotator_npm; then fail 'unit removal failure did not block npm removal'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'unit removal failure did not preserve unit and receipt'

reset_case surviving-unit
create_owned_unit
create_npm_receipt
FAKE_RM_KEEP_UNIT=1
if uninstall_remove_rotator_npm; then fail 'surviving unit did not block npm removal'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'surviving unit did not preserve ownership and package state'

reset_case receipt-removal-failure
create_owned_unit
create_npm_receipt
FAKE_RM_FAIL_RECEIPT=1
if uninstall_remove_rotator_npm; then fail 'receipt removal failure did not block npm removal'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_SYSTEMD_RECEIPT}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'receipt removal failure did not restore the unit and preserve receipts and package'

for state in unowned mismatched malformed modified; do
    reset_case "protected-${state}"
    if [[ "${state}" == modified ]]; then
        create_owned_unit
        printf 'modified unit\n' >"${FAKE_UNIT_PATH}"
    else
        mkdir -p "$(dirname -- "${FAKE_UNIT_PATH}")"
        printf 'protected unit\n' >"${FAKE_UNIT_PATH}"
    fi
    if [[ "${state}" == mismatched || "${state}" == malformed ]]; then
        mkdir -p "$(dirname -- "${FAKE_SYSTEMD_RECEIPT}")"
        if [[ "${state}" == mismatched ]]; then
            printf '{"schemaVersion":1,"unitPath":"%s","fingerprint":"%064d"}\n' "${FAKE_UNIT_PATH}" 1 >"${FAKE_SYSTEMD_RECEIPT}"
        else
            printf '{malformed\n' >"${FAKE_SYSTEMD_RECEIPT}"
        fi
    fi
    create_npm_receipt
    if uninstall_remove_rotator_npm; then fail "${state} unit did not block npm removal"; fi
    [[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_UNIT_PATH}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail "${state} unit or package was changed"
    if [[ "${state}" != unowned ]]; then [[ -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail "${state} receipt was removed"; fi
done

# A stale but well-formed receipt with no unit is cleared only after manager-confirmed absence.
reset_case stale-receipt
create_owned_unit
command rm -- "${FAKE_UNIT_PATH}"
FAKE_SYSTEMCTL_STATE=absent
create_npm_receipt
FAKE_RECEIPT_RM_CHECK=1
if uninstall_remove_rotator_npm; then fail 'stale receipt unexpectedly permitted npm removal'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_SYSTEMD_RECEIPT}" ]] || fail 'stale receipt was removed without a unit-state proof'

# --purge does not authorize touching an unowned unit, wants link, unrelated unit, or user data.
reset_case purge
mkdir -p "$(dirname -- "${FAKE_UNIT_PATH}")" "${XDG_CONFIG_HOME}/systemd/user/default.target.wants"
printf 'unowned unit\n' >"${FAKE_UNIT_PATH}"
unrelated="${XDG_CONFIG_HOME}/systemd/user/other.service"
printf 'other unit\n' >"${unrelated}"
link_target="${TEST_ROOT}/purge-link-target"
printf 'link target\n' >"${link_target}"
ln -s -- "${link_target}" "${XDG_CONFIG_HOME}/systemd/user/default.target.wants/other.service"
user_data="${HOME}/.tuxevil-rotator-user-data"
printf 'user data\n' >"${user_data}"
UNINSTALL_PURGE=1
if uninstall_remove_systemd_unit tuxevil-rotator.service; then fail '--purge widened unowned unit removal'; fi
[[ -f "${FAKE_UNIT_PATH}" && -f "${unrelated}" && -L "${XDG_CONFIG_HOME}/systemd/user/default.target.wants/other.service" && -f "${link_target}" && -f "${user_data}" ]] || fail '--purge removed an unrelated unit, symlink, or user data'

printf 'Rotator systemd ownership checks passed.\n'
