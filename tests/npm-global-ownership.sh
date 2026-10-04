#!/usr/bin/env bash
# #105: install/uninstall ownership matrix for both npm-global fallbacks, using fake `npm` only.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# DRY_RUN=1 while sourcing keeps the top-level log and npm cache inside the script's TMP_DIR.
export DRY_RUN=1
# shellcheck disable=SC1090
source <(sed '/^# Main$/,$d' "${ROOT}/setup-ai.sh")
DRY_RUN=0
FAKE_NPM_ROOT="${TMP_DIR}/npm-root"
FAKE_NPM_LOG="${TMP_DIR}/npm.log"
FAKE_NPM_UNAVAILABLE=0
FAKE_NPM_ROOT_FAIL=0
FAKE_NPM_INSTALL_FAIL=0
FAKE_NPM_UNINSTALL_FAIL=0
FAKE_NPM_UNINSTALL_NOREMOVE=0
npm() {
    (( FAKE_NPM_UNAVAILABLE == 0 )) || return 127
    case "$1 $2" in
        "root -g")
            (( FAKE_NPM_ROOT_FAIL == 0 )) || return 1
            printf '%s\n' "${FAKE_NPM_ROOT}" ;;
        "install -g")
            shift 2
            ( IFS=' '; printf 'install %s\n' "$*" >> "${FAKE_NPM_LOG}" )
            (( FAKE_NPM_INSTALL_FAIL == 0 )) || return 1
            mkdir -p "${FAKE_NPM_ROOT}/$1"
            printf '{"name":"%s"}\n' "$1" > "${FAKE_NPM_ROOT}/$1/package.json" ;;
        "uninstall -g")
            shift 2
            printf 'uninstall %s\n' "$*" >> "${FAKE_NPM_LOG}"
            (( FAKE_NPM_UNINSTALL_FAIL == 0 )) || return 1
            (( FAKE_NPM_UNINSTALL_NOREMOVE == 1 )) || rm -rf -- "${FAKE_NPM_ROOT:?}/$1" ;;
        *) return 1 ;;
    esac
}
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
reset_state() {
    rm -rf -- "${FAKE_NPM_ROOT}"
    mkdir -p "${FAKE_NPM_ROOT}"
    : > "${FAKE_NPM_LOG}"
    FAKE_NPM_UNAVAILABLE=0; FAKE_NPM_ROOT_FAIL=0; FAKE_NPM_INSTALL_FAIL=0; FAKE_NPM_UNINSTALL_FAIL=0; FAKE_NPM_UNINSTALL_NOREMOVE=0
}
test_package() {
    local pkg="$1" module="$2"
    local dir="${FAKE_NPM_ROOT}/${pkg}"
    local expected="setup-ai ${module} npm-global ${pkg}"
    local marker="${dir}/.setup-ai-owned"
    reset_state
    install_extras_global_package "${pkg}" "${module}" || fail "${pkg}: fresh install failed"
    extras_marker_matches "${marker}" "${expected}" || fail "${pkg}: fresh install did not leave a readable marker"
    grep -qx "install ${pkg}" "${FAKE_NPM_LOG}" || fail "${pkg}: npm install did not run with the exact package name"
    reset_state
    install_extras_global_package "${pkg}" "${module}" "--allow-scripts=${pkg}" || fail "${pkg}: install with extra npm args failed"
    grep -qx "install ${pkg} --allow-scripts=${pkg}" "${FAKE_NPM_LOG}" || fail "${pkg}: extra npm install args were not passed through"
    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"
    install_extras_global_package "${pkg}" "${module}" || fail "${pkg}: preserving an existing unmarked package failed"
    [[ ! -s "${FAKE_NPM_LOG}" && ! -e "${marker}" ]] || fail "${pkg}: an existing unmarked package was reinstalled or claimed"
    reset_state
    mkdir -p "${dir}"; printf '{"name":"something-else"}\n' > "${dir}/package.json"
    if install_extras_global_package "${pkg}" "${module}"; then fail "${pkg}: an unverifiable existing package was accepted"; fi
    [[ ! -s "${FAKE_NPM_LOG}" ]] || fail "${pkg}: an unverifiable existing package was reinstalled"
    reset_state
    FAKE_NPM_UNAVAILABLE=1
    if install_extras_global_package "${pkg}" "${module}" 2>/dev/null; then fail "${pkg}: install succeeded without npm"; fi
    [[ ! -e "${dir}" ]] || fail "${pkg}: a package appeared although npm was unavailable"
    reset_state; FAKE_NPM_INSTALL_FAIL=1; if install_extras_global_package "${pkg}" "${module}"; then fail "${pkg}: install failure was swallowed"; fi; grep -Fqx "install ${pkg}" "${FAKE_NPM_LOG}" || fail "${pkg}: failed install did not reach fake npm"; [[ ! -e "${dir}" && ! -e "${marker}" ]] || fail "${pkg}: failed install changed package state"
    # --- uninstall_remove_npm_global (unchanged, reused for the two new catalog rows) ---
    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: owned-package uninstall exited non-zero"
    if [[ -e "${dir}" ]] || ! grep -Fqx "uninstall ${pkg}" "${FAKE_NPM_LOG}"; then fail "${pkg}: owned package was not removed"; fi
    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: unmarked-package uninstall exited non-zero"
    [[ -d "${dir}" && ! -s "${FAKE_NPM_LOG}" ]] || fail "${pkg}: an unmarked package was removed (simulated external reinstall must be preserved)"
    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf 'setup-ai extras npm-global %s\n' "${pkg}" > "${marker}"
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: foreign-marker uninstall exited non-zero"
    [[ -d "${dir}" && ! -s "${FAKE_NPM_LOG}" ]] || fail "${pkg}: a package owned by another module was removed"
    reset_state
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: absent-package uninstall exited non-zero"
    [[ ! -s "${FAKE_NPM_LOG}" ]] || fail "${pkg}: npm uninstall ran for an absent package"

    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"
    FAKE_NPM_UNAVAILABLE=1
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: fake npm-unavailable uninstall exited non-zero"
    [[ -d "${dir}" ]] || fail "${pkg}: package removed although fake npm was unavailable"

    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"
    (empty_path="$(mktemp -d "${TMP_DIR}/empty-path.XXXXXX")"; ln -s "$(command -v date)" "${empty_path}/date"; PATH="${empty_path}"; export PATH; unset -f npm; uninstall_remove_npm_global "${pkg}" "${expected}") || fail "${pkg}: missing npm uninstall exited non-zero"
    [[ -d "${dir}" && ! -s "${FAKE_NPM_LOG}" ]] || fail "${pkg}: package changed although npm was missing"

    reset_state; mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"; FAKE_NPM_UNINSTALL_FAIL=1; if uninstall_remove_npm_global "${pkg}" "${expected}"; then fail "${pkg}: uninstall failure was swallowed"; fi; grep -Fqx "uninstall ${pkg}" "${FAKE_NPM_LOG}" || fail "${pkg}: failed uninstall did not reach fake npm"; [[ -d "${dir}" && -f "${marker}" ]] || fail "${pkg}: failed uninstall changed package state"

    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"
    FAKE_NPM_ROOT_FAIL=1
    uninstall_remove_npm_global "${pkg}" "${expected}" || fail "${pkg}: npm-root-unavailable uninstall exited non-zero"
    [[ -d "${dir}" ]] || fail "${pkg}: package removed although npm root -g failed"

    reset_state
    mkdir -p "${dir}"; printf '{"name":"%s"}\n' "${pkg}" > "${dir}/package.json"; printf '%s\n' "${expected}" > "${marker}"
    FAKE_NPM_UNINSTALL_NOREMOVE=1
    if uninstall_remove_npm_global "${pkg}" "${expected}" 2>/dev/null; then fail "${pkg}: uninstall was accepted although the package survived"; fi
    [[ -d "${dir}" && -f "${marker}" ]] || fail "${pkg}: an unverified removal still disturbed the package or its marker"

    printf 'PASS: %s npm-global ownership (install and uninstall)\n' "${pkg}"
}

test_package '@anthropic-ai/claude-code' claude-code
test_package 'opencode-ai' opencode

printf '%s\n' 'PASS: npm-global ownership is generalized across every npm-global call site'
