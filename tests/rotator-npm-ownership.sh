#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DRY_RUN=1
source <(sed '/^# Main$/,$d' "${repo}/setup-ai.sh")
SCRIPT_DIR="${repo}"
DRY_RUN=0
XDG_STATE_HOME="${TMP_DIR}/state"
export XDG_STATE_HOME

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
declare -F install_rotator_npm_package >/dev/null || fail 'install_rotator_npm_package is not defined'

FAKE_NPM_ROOT="${TMP_DIR}/npm-fresh"
FAKE_BIN="${TMP_DIR}/fake-bin"
FAKE_PACKAGE_NAME=tuxevil-rotator
FAKE_PACKAGE_VERSION=1.2.3
FAKE_NPM_CALLS=0
FAKE_NPM_UNINSTALL_CALLS=0
FAKE_NPM_LOG="${TMP_DIR}/npm-calls.log"
mkdir -p "${FAKE_NPM_ROOT}" "${FAKE_BIN}"
PATH="${FAKE_BIN}:${PATH}"
export FAKE_NPM_ROOT FAKE_PACKAGE_NAME FAKE_PACKAGE_VERSION FAKE_NPM_CALLS FAKE_NPM_UNINSTALL_CALLS FAKE_NPM_LOG PATH

npm() {
    FAKE_NPM_CALLS=$((FAKE_NPM_CALLS + 1))
    local arguments
    printf -v arguments '%s ' "$@"
    arguments="${arguments% }"
    printf '%s\n' "${arguments}" >>"${FAKE_NPM_LOG}"
    case "${arguments}" in
        'root -g')
            if [[ -n "${FAKE_NPM_ROOT_AFTER:-}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]]; then
                printf '%s\n' "${FAKE_NPM_ROOT_AFTER}"
            else
                printf '%s\n' "${FAKE_NPM_ROOT}"
            fi
            ;;
        'install --global tuxevil-rotator')
            if [[ "${FAKE_NPM_PACKAGE_SYMLINK:-0}" == 1 ]]; then
                ln -s -- "${FAKE_NPM_OUTSIDE_DIR}" "${FAKE_NPM_ROOT}/tuxevil-rotator"
            elif [[ "${FAKE_NPM_PACKAGE_JSON_SYMLINK:-0}" == 1 ]]; then
                mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator"
                ln -s -- "${FAKE_NPM_OUTSIDE_PACKAGE_JSON}" "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
            else
                mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator"
                printf '{"name":"%s","version":"%s"}\n' "${FAKE_PACKAGE_NAME}" "${FAKE_PACKAGE_VERSION}" >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
            fi
            if [[ "${FAKE_NPM_PREEXISTING_MARKER:-0}" == 1 ]]; then printf '%s' 'preserve-marker' >"${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership"; fi
            printf '#!/bin/sh\nexit 0\n' >"${FAKE_BIN}/tuxevil-rotator"
            chmod +x "${FAKE_BIN}/tuxevil-rotator"
            ;;
        'uninstall --global tuxevil-rotator')
            FAKE_NPM_UNINSTALL_CALLS=$((FAKE_NPM_UNINSTALL_CALLS + 1))
            [[ "${FAKE_NPM_FAIL_UNINSTALL:-0}" == 1 ]] && return 7
            [[ "${FAKE_NPM_KEEP_PACKAGE:-0}" == 1 ]] || mv "${FAKE_NPM_ROOT}/tuxevil-rotator" "${FAKE_NPM_ROOT}.removed"
            ;;
        *) printf 'unexpected fake npm arguments: %s\n' "$*" >&2; return 2 ;;
    esac
}

FAKE_SYSTEMCTL_MODE=absent
FAKE_SYSTEMCTL_CALLS=0
FAKE_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-calls.log"
systemctl() {
    local IFS=' '
    FAKE_SYSTEMCTL_CALLS=$((FAKE_SYSTEMCTL_CALLS + 1))
    printf '%s\n' "$*" >>"${FAKE_SYSTEMCTL_LOG}"
    case "$*" in
        '--user show-environment') [[ "${FAKE_SYSTEMCTL_MODE}" != unavailable ]] ;;
        '--user show tuxevil-rotator.service --property=LoadState --property=ActiveState --property=UnitFileState --value')
            case "${FAKE_SYSTEMCTL_MODE}" in
                absent) printf 'not-found\ninactive\nnot-found\n' ;;
                uncertain) printf 'loaded\ninactive\ndisabled\n' ;;
                *) return 1 ;;
            esac
            ;;
        *) printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2; return 2 ;;
    esac
}

FAKE_NPM_ROOT="${TMP_DIR}/npm-package-dir-symlink"
XDG_STATE_HOME="${TMP_DIR}/state-package-dir-symlink"
FAKE_NPM_OUTSIDE_DIR="${TMP_DIR}/npm-package-dir-outside"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
mkdir -p "${FAKE_NPM_ROOT}" "${FAKE_NPM_OUTSIDE_DIR}"
printf '{"name":"tuxevil-rotator","version":"1.2.3"}\n' >"${FAKE_NPM_OUTSIDE_DIR}/package.json"
printf 'outside-sentinel\n' >"${FAKE_NPM_OUTSIDE_DIR}/sentinel"
FAKE_NPM_PACKAGE_SYMLINK=1
export FAKE_NPM_ROOT FAKE_NPM_OUTSIDE_DIR FAKE_NPM_PACKAGE_SYMLINK XDG_STATE_HOME
install_rotator_npm_package
[[ ! -e "${receipt}" && ! -e "${FAKE_NPM_OUTSIDE_DIR}/.setup-ai-ownership" ]] || fail 'linked package directory received a marker or ownership receipt'
[[ "$(cat "${FAKE_NPM_OUTSIDE_DIR}/sentinel")" == outside-sentinel && "$(cat "${FAKE_NPM_OUTSIDE_DIR}/package.json")" == '{"name":"tuxevil-rotator","version":"1.2.3"}' ]] || fail 'linked package directory changed its external target'
unset FAKE_NPM_PACKAGE_SYMLINK

FAKE_NPM_ROOT="${TMP_DIR}/npm-package-json-symlink"
XDG_STATE_HOME="${TMP_DIR}/state-package-json-symlink"
FAKE_NPM_OUTSIDE_PACKAGE_JSON="${TMP_DIR}/npm-package-json-outside.json"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
printf '{"name":"tuxevil-rotator","version":"1.2.3"}\n' >"${FAKE_NPM_OUTSIDE_PACKAGE_JSON}"
FAKE_NPM_PACKAGE_JSON_SYMLINK=1
export FAKE_NPM_ROOT FAKE_NPM_OUTSIDE_PACKAGE_JSON FAKE_NPM_PACKAGE_JSON_SYMLINK XDG_STATE_HOME
install_rotator_npm_package
[[ ! -e "${receipt}" && ! -e "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership" ]] || fail 'non-regular package.json was accepted for marker installation'
unset FAKE_NPM_PACKAGE_JSON_SYMLINK

FAKE_NPM_ROOT="${TMP_DIR}/npm-receipt-parent-symlink"
XDG_STATE_HOME="${TMP_DIR}/state-receipt-parent-symlink"
FAKE_NPM_OUTSIDE_DIR="${TMP_DIR}/receipt-parent-outside"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
mkdir -p "${FAKE_NPM_ROOT}" "${FAKE_NPM_OUTSIDE_DIR}" "${XDG_STATE_HOME}/setup-ai"
ln -s -- "${FAKE_NPM_OUTSIDE_DIR}" "${XDG_STATE_HOME}/setup-ai/ownership"
export FAKE_NPM_ROOT XDG_STATE_HOME FAKE_NPM_OUTSIDE_DIR
install_rotator_npm_package
[[ ! -e "${receipt}" && ! -e "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership" && ! -e "${FAKE_NPM_OUTSIDE_DIR}/rotator-npm.json" ]] || fail 'symlinked receipt parent accepted an unsafe ownership path'

FAKE_NPM_ROOT="${TMP_DIR}/npm-receipt-collision"
XDG_STATE_HOME="${TMP_DIR}/state-receipt-collision"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
mkdir -p "${FAKE_NPM_ROOT}" "$(dirname -- "${receipt}")"
printf 'preserve receipt\n' >"${receipt}"
export FAKE_NPM_ROOT XDG_STATE_HOME
install_rotator_npm_package
[[ "$(cat "${receipt}")" == 'preserve receipt' && ! -e "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership" ]] || fail 'receipt publication failure left an orphaned marker or changed the receipt'

FAKE_NPM_ROOT="${TMP_DIR}/npm-fresh"
XDG_STATE_HOME="${TMP_DIR}/state"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
install_rotator_npm_package
[[ -f "${receipt}" ]] || fail 'fresh global install did not write an ownership receipt'
node -e 'const fs=require("node:fs"); const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const marker=`${process.argv[2]}/tuxevil-rotator/.setup-ai-ownership`; if (r.schemaVersion !== 2 || r.package !== "tuxevil-rotator" || r.version !== "1.2.3" || r.npmRoot !== process.argv[2] || !/^[0-9a-f]{32}$/.test(r.marker) || fs.readFileSync(marker,"utf8") !== r.marker) process.exit(1)' "${receipt}" "${FAKE_NPM_ROOT}" \
    || fail 'fresh install receipt did not record a verified package marker and metadata'

FAKE_NPM_ROOT="${TMP_DIR}/npm-marker-collision"
XDG_STATE_HOME="${TMP_DIR}/state-marker-collision"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
FAKE_NPM_PREEXISTING_MARKER=1
export FAKE_NPM_ROOT XDG_STATE_HOME FAKE_NPM_PREEXISTING_MARKER
mkdir -p "${FAKE_NPM_ROOT}"
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'pre-existing package marker was incorrectly claimed'
[[ "$(cat "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership")" == preserve-marker ]] || fail 'pre-existing package marker was overwritten'
unset FAKE_NPM_PREEXISTING_MARKER

FAKE_NPM_ROOT="${TMP_DIR}/npm-preexisting"
XDG_STATE_HOME="${TMP_DIR}/state-preexisting"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
export FAKE_NPM_ROOT XDG_STATE_HOME
mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator"
printf '{"name":"tuxevil-rotator","version":"0.9.0"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
export FAKE_NPM_ROOT
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'pre-existing package was incorrectly claimed as setup-ai-owned'

FAKE_NPM_ROOT="${TMP_DIR}/npm-invalid-metadata"
XDG_STATE_HOME="${TMP_DIR}/state-invalid-metadata"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
FAKE_PACKAGE_NAME=another-package
export FAKE_NPM_ROOT FAKE_PACKAGE_NAME XDG_STATE_HOME
mkdir -p "${FAKE_NPM_ROOT}"
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'package with mismatched metadata was incorrectly claimed as setup-ai-owned'

FAKE_NPM_ROOT="${TMP_DIR}/npm-whitespace-version"
XDG_STATE_HOME="${TMP_DIR}/state-whitespace-version"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
FAKE_PACKAGE_NAME=tuxevil-rotator
FAKE_PACKAGE_VERSION='   '
export FAKE_NPM_ROOT FAKE_PACKAGE_NAME FAKE_PACKAGE_VERSION XDG_STATE_HOME
mkdir -p "${FAKE_NPM_ROOT}"
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'package with whitespace-only version was incorrectly claimed as setup-ai-owned'
FAKE_PACKAGE_VERSION=1.2.3
export FAKE_PACKAGE_VERSION

FAKE_NPM_ROOT="${TMP_DIR}/npm-root-changed"
FAKE_NPM_ROOT_AFTER="${TMP_DIR}/npm-root-changed-after"
XDG_STATE_HOME="${TMP_DIR}/state-root-changed"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
FAKE_PACKAGE_NAME=tuxevil-rotator
export FAKE_NPM_ROOT FAKE_NPM_ROOT_AFTER FAKE_PACKAGE_NAME XDG_STATE_HOME
mkdir -p "${FAKE_NPM_ROOT}"
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'changed npm root was incorrectly claimed as setup-ai-owned'
unset FAKE_NPM_ROOT_AFTER

FAKE_NPM_ROOT="${TMP_DIR}/npm-root-unavailable"
XDG_STATE_HOME="${TMP_DIR}/state-root-unavailable"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
export FAKE_NPM_ROOT XDG_STATE_HOME
install_rotator_npm_package
[[ ! -e "${receipt}" ]] || fail 'unreadable pre-install npm root was incorrectly claimed as setup-ai-owned'

FAKE_NPM_ROOT="${TMP_DIR}/npm-dry-run"
XDG_STATE_HOME="${TMP_DIR}/state-dry-run"
receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
FAKE_NPM_CALLS=0
export FAKE_NPM_ROOT FAKE_NPM_CALLS XDG_STATE_HOME
DRY_RUN=1
install_rotator_npm_package
[[ "${FAKE_NPM_CALLS}" -eq 0 ]] || fail 'dry-run queried or invoked npm'
[[ ! -e "${receipt}" ]] || fail 'dry-run wrote an ownership receipt'

prepare_rotator_state() {
    local name="$1" with_receipt="${2:-1}"
    FAKE_NPM_ROOT="${TMP_DIR}/npm-${name}"
    XDG_STATE_HOME="${TMP_DIR}/state-${name}"
    XDG_CONFIG_HOME="${TMP_DIR}/config-${name}"
    receipt="${XDG_STATE_HOME}/setup-ai/ownership/rotator-npm.json"
    FAKE_NPM_UNINSTALL_CALLS=0
    FAKE_NPM_FAIL_UNINSTALL=0
    FAKE_NPM_KEEP_PACKAGE=0
    FAKE_SYSTEMCTL_MODE=absent
    FAKE_SYSTEMCTL_CALLS=0
    : >"${FAKE_SYSTEMCTL_LOG}"
    mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator" "$(dirname "${receipt}")"
    printf '{"name":"tuxevil-rotator","version":"1.2.3"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
    FAKE_OWNER_MARKER=0123456789abcdef0123456789abcdef
    printf '%s' "${FAKE_OWNER_MARKER}" >"${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership"
    if [[ "${with_receipt}" == 1 ]]; then
        node -e 'const fs=require("node:fs");const root=process.argv[1],path=process.argv[2],marker=process.argv[3];fs.writeFileSync(path,JSON.stringify({schemaVersion:2,package:"tuxevil-rotator",npmRoot:root,packagePath:`${root}/tuxevil-rotator/package.json`,version:"1.2.3",marker}));' "${FAKE_NPM_ROOT}" "${receipt}" "${FAKE_OWNER_MARKER}"
    fi
    export FAKE_NPM_ROOT XDG_STATE_HOME XDG_CONFIG_HOME
}

prepare_rotator_state v1-receipt
node -e 'const fs=require("node:fs"),p=process.argv[1],r=JSON.parse(fs.readFileSync(p,"utf8"));r.schemaVersion=1;fs.writeFileSync(p,JSON.stringify(r));' "${receipt}"
receipt_before="$(cat "${receipt}")"
SELECTED_MODULES=(rotator)
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'v1 npm receipt was upgraded or accepted as removable'; fi
UNINSTALL_YES=1
uninstall_remove_npm_global tuxevil-rotator || fail 'v1 receipt rejection returned an error'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && "$(cat "${receipt}")" == "${receipt_before}" ]] || fail 'v1 receipt was changed or used to uninstall the package'

prepare_rotator_state receipt-parent-link
mv -- "${XDG_STATE_HOME}/setup-ai/ownership" "${TMP_DIR}/receipt-parent-link-outside"
ln -s -- "${TMP_DIR}/receipt-parent-link-outside" "${XDG_STATE_HOME}/setup-ai/ownership"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'receipt behind a symlinked parent was accepted'; fi
UNINSTALL_YES=1
uninstall_remove_npm_global tuxevil-rotator || fail 'linked receipt parent rejection returned an error'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${TMP_DIR}/receipt-parent-link-outside/rotator-npm.json" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'linked receipt parent authorized removal or lost the receipt'

prepare_rotator_state no-receipt 0
SELECTED_MODULES=(rotator)
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'package without a receipt was listed as removable'; fi
[[ "$(uninstall_print_inventory)" == *'tuxevil-rotator (protected: no matching receipt/fingerprint)'* ]] || fail 'inventory did not label the unowned package as protected'
UNINSTALL_YES=1
uninstall_remove_npm_global tuxevil-rotator || fail 'unowned package removal returned an error'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'unowned package was removed'

prepare_rotator_state malformed
printf '{bad json' >"${receipt}"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'malformed receipt package was listed as removable'; fi

prepare_rotator_state root-mismatch
FAKE_NPM_ROOT_AFTER="${TMP_DIR}/npm-other-root"
export FAKE_NPM_ROOT_AFTER
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'changed global root package was listed as removable'; fi
unset FAKE_NPM_ROOT_AFTER

prepare_rotator_state fingerprint-mismatch
printf '{"name":"tuxevil-rotator","version":"9.9.9"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'changed package fingerprint was listed as removable'; fi
prepare_rotator_state name-mismatch
printf '{"name":"other-package","version":"1.2.3"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'changed package name was listed as removable'; fi

prepare_rotator_state stale-reinstall
mv "${FAKE_NPM_ROOT}/tuxevil-rotator" "${FAKE_NPM_ROOT}/tuxevil-rotator.old"
mkdir -p "${FAKE_NPM_ROOT}/tuxevil-rotator"
printf '{"name":"tuxevil-rotator","version":"1.2.3"}\n' >"${FAKE_NPM_ROOT}/tuxevil-rotator/package.json"
printf '%s' 'fedcba9876543210fedcba9876543210' >"${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'stale receipt authorized a same-version replacement package'; fi
UNINSTALL_YES=1
uninstall_remove_npm_global tuxevil-rotator || fail 'stale receipt rejection returned an error'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${receipt}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'same-version replacement package or stale receipt was changed'

prepare_rotator_state marker-missing
node -e 'require("node:fs").unlinkSync(process.argv[1])' "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership"
if uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'receipt with a missing package marker was listed as removable'; fi

prepare_rotator_state inventory
UNINSTALL_YES=0
if ! uninstall_entry_present npm-global tuxevil-rotator ''; then fail 'matching receipt package was not inventoried'; fi
[[ "$(uninstall_print_inventory)" == *'tuxevil-rotator (receipt-backed; removable with --yes)'* ]] || fail 'matching receipt package was not listed as removable'
if grep -Fqx 'uninstall --global tuxevil-rotator' "${FAKE_NPM_LOG}"; then fail 'captured inventory invoked npm uninstall'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${receipt}" ]] || fail 'inventory invoked npm uninstall or changed the receipt'

prepare_rotator_state dry-run
UNINSTALL_YES=1
DRY_RUN=1
uninstall_remove_npm_global tuxevil-rotator || fail 'dry-run removal check failed'
if grep -Fqx 'uninstall --global tuxevil-rotator' "${FAKE_NPM_LOG}"; then fail 'dry-run inventory invoked npm uninstall'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${receipt}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'dry-run changed the package or receipt'

prepare_rotator_state needs-confirmation
DRY_RUN=0
UNINSTALL_YES=0
uninstall_remove_npm_global tuxevil-rotator || fail 'unconfirmed removal check failed'
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${receipt}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'removal without --yes changed the package or receipt'

prepare_rotator_state uninstall-failure
UNINSTALL_YES=1
FAKE_NPM_FAIL_UNINSTALL=1
export FAKE_NPM_FAIL_UNINSTALL
if uninstall_remove_npm_global tuxevil-rotator; then fail 'failed npm uninstall was reported as successful'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 1 && -f "${receipt}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'uninstall failure did not preserve the package and receipt'

prepare_rotator_state package-remains
UNINSTALL_YES=1
FAKE_NPM_KEEP_PACKAGE=1
if uninstall_remove_npm_global tuxevil-rotator; then fail 'npm success with a remaining package was reported as complete'; fi
[[ -f "${receipt}" && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" ]] || fail 'remaining package did not preserve its receipt'

prepare_rotator_state confirmed
UNINSTALL_YES=1
if ! uninstall_remove_npm_global tuxevil-rotator; then fail 'confirmed receipt-backed removal failed'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 1 && ! -e "${FAKE_NPM_ROOT}/tuxevil-rotator" && ! -e "${FAKE_NPM_ROOT}/tuxevil-rotator/.setup-ai-ownership" && ! -e "${receipt}" ]] || fail 'confirmed removal did not uninstall the exact package and then its receipt'
grep -Fqx 'uninstall --global tuxevil-rotator' "${FAKE_NPM_LOG}" || fail 'npm uninstall did not receive the exact package argument'

# Linux npm removal is blocked by a present unit without inspecting its ownership receipt.
prepare_rotator_state systemd-unit-present
FAKE_SYSTEMD_UNIT="${XDG_CONFIG_HOME}/systemd/user/tuxevil-rotator.service"
mkdir -p "$(dirname -- "${FAKE_SYSTEMD_UNIT}")"
printf 'unowned unit\n' >"${FAKE_SYSTEMD_UNIT}"
FAKE_SYSTEMCTL_MODE=unavailable
UNINSTALL_YES=1
if uninstall_remove_npm_global tuxevil-rotator; then fail 'npm removal ignored a present systemd unit'; fi
[[ "${FAKE_SYSTEMCTL_CALLS}" -eq 0 && "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" && -f "${receipt}" ]] || fail 'present systemd unit did not preserve npm ownership state'

# Missing or uncertain systemd manager state also preserves the package.
prepare_rotator_state systemd-manager-unavailable
FAKE_SYSTEMCTL_MODE=unavailable
UNINSTALL_YES=1
if uninstall_remove_npm_global tuxevil-rotator; then fail 'npm removal ignored unavailable systemd manager state'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" && -f "${receipt}" ]] || fail 'unavailable systemd manager state did not preserve npm ownership state'

prepare_rotator_state systemd-manager-uncertain
FAKE_SYSTEMCTL_MODE=uncertain
UNINSTALL_YES=1
if uninstall_remove_npm_global tuxevil-rotator; then fail 'npm removal ignored uncertain systemd manager state'; fi
[[ "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" && -f "${receipt}" ]] || fail 'uncertain systemd manager state did not preserve npm ownership state'

# A unit appearing after the first guard must block npm removal at the final check.
prepare_rotator_state systemd-toctou
FAKE_SYSTEMD_UNIT="${XDG_CONFIG_HOME}/systemd/user/tuxevil-rotator.service"
mkdir -p "$(dirname -- "${FAKE_SYSTEMD_UNIT}")"
FAKE_SYSTEMCTL_MODE=absent
ROTATOR_NPM_RECEIPT_MATCH_CALLS=0
receipt_before="$(cat "${receipt}")"
eval "$(declare -f uninstall_rotator_npm_receipt_matches | sed '1s/uninstall_rotator_npm_receipt_matches/real_uninstall_rotator_npm_receipt_matches/')"
uninstall_rotator_npm_receipt_matches() {
    ROTATOR_NPM_RECEIPT_MATCH_CALLS=$((ROTATOR_NPM_RECEIPT_MATCH_CALLS + 1))
    if [[ "${ROTATOR_NPM_RECEIPT_MATCH_CALLS}" -eq 2 ]]; then
        printf 'appeared unit\n' >"${FAKE_SYSTEMD_UNIT}"
    fi
    real_uninstall_rotator_npm_receipt_matches "$@"
}
UNINSTALL_YES=1
if uninstall_remove_npm_global tuxevil-rotator; then fail 'npm removal ignored a unit appearing after the first systemd guard'; fi
[[ "${ROTATOR_NPM_RECEIPT_MATCH_CALLS}" -eq 2 &&
    "${FAKE_NPM_UNINSTALL_CALLS}" -eq 0 && -f "${FAKE_NPM_ROOT}/tuxevil-rotator/package.json" &&
    "$(cat "${receipt}")" == "${receipt_before}" && -f "${FAKE_SYSTEMD_UNIT}" ]] ||
    fail 'TOCTOU systemd appearance did not preserve npm, receipt, and unit state'
if grep -Eq '^--user (stop|disable|daemon-reload)' "${FAKE_SYSTEMCTL_LOG}"; then
    fail 'TOCTOU systemd appearance invoked a mutating systemctl operation'
fi
unset -f uninstall_rotator_npm_receipt_matches
eval "$(declare -f real_uninstall_rotator_npm_receipt_matches | sed '1s/real_uninstall_rotator_npm_receipt_matches/uninstall_rotator_npm_receipt_matches/')"
unset -f real_uninstall_rotator_npm_receipt_matches

printf 'Rotator npm ownership checks passed.\n'
