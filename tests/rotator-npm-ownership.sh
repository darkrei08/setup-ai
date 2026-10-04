#!/usr/bin/env bash
# #104: the rotator npm package is removed only when it carries setup-ai's marker and no
# systemd user unit still runs it. Fake npm and systemctl only; nothing real is touched.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK}"' EXIT

# Run a copy so the uninstall logs land in the scratch directory, never in the repository.
cp "${ROOT}/setup-ai.sh" "${WORK}/setup-ai.sh"
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/npm" <<'NPM'
#!/usr/bin/env bash
case "$1 $2" in
    "root -g") printf '%s\n' "${FAKE_NPM_ROOT}" ;;
    "uninstall -g") printf '%s\n' "$3" >> "${FAKE_NPM_LOG}"; rm -rf -- "${FAKE_NPM_ROOT:?}/$3" ;;
    *) exit 1 ;;
esac
NPM
cat > "${WORK}/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "$*" in
    *is-active*)
        if [[ -n "${FAKE_UNIT_ACTIVE:-}" ]]; then exit 0; fi
        if [[ -n "${FAKE_UNIT_UNKNOWN:-}" ]]; then exit 1; fi
        exit 3
        ;;
    *) exit 0 ;;
esac
SYSTEMCTL
chmod +x "${WORK}/bin/npm" "${WORK}/bin/systemctl"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

pkg="${WORK}/npm-root/tuxevil-rotator"
unit="${WORK}/home/.config/systemd/user/tuxevil-rotator.service"

setup_state() { # marker text ('' for none)
    rm -rf -- "${WORK}/home" "${WORK}/npm-root"
    mkdir -p "${pkg}" "${WORK}/home"
    printf '{"name":"tuxevil-rotator"}\n' > "${pkg}/package.json"
    [[ -z "$1" ]] || printf '%s\n' "$1" > "${pkg}/.setup-ai-owned"
    : > "${WORK}/npm.log"
}

run_uninstall() {
    HOME="${WORK}/home" XDG_CONFIG_HOME="${WORK}/home/.config" PATH="${WORK}/bin:${PATH}" \
        FAKE_NPM_ROOT="${WORK}/npm-root" FAKE_NPM_LOG="${WORK}/npm.log" \
        bash "${WORK}/setup-ai.sh" --uninstall --only rotator --yes 2>&1
}

owned='setup-ai rotator npm-global tuxevil-rotator'

setup_state "${owned}"
out="$(run_uninstall)" || fail "owned package uninstall exited non-zero: ${out}"
[[ "$(cat "${WORK}/npm.log")" == "tuxevil-rotator" && ! -e "${pkg}" ]] || fail "marked package was not removed: ${out}"

setup_state ''
out="$(run_uninstall)" || fail "unmarked package uninstall exited non-zero: ${out}"
[[ -d "${pkg}" && ! -s "${WORK}/npm.log" ]] || fail "unmarked package was removed: ${out}"

setup_state 'setup-ai extras npm-global tuxevil-rotator'
out="$(run_uninstall)" || fail "foreign-marker uninstall exited non-zero: ${out}"
[[ -d "${pkg}" && ! -s "${WORK}/npm.log" ]] || fail "package with another module's marker was removed: ${out}"

# A canonical unit is a read-only dependency, so setup-ai leaves both it and the package.
setup_state "${owned}"
mkdir -p "$(dirname -- "${unit}")"
: > "${unit}"
out="$(run_uninstall)" || fail "present-unit uninstall exited non-zero: ${out}"
[[ -d "${pkg}" && ! -s "${WORK}/npm.log" && -f "${unit}" ]] || fail "package or unit changed while the systemd unit remains: ${out}"

setup_state "${owned}"
out="$(FAKE_UNIT_ACTIVE=1 run_uninstall)" || fail "active-unit uninstall exited non-zero: ${out}"
[[ -d "${pkg}" && ! -s "${WORK}/npm.log" ]] || fail "package removed while the user manager still runs its unit: ${out}"

setup_state "${owned}"
out="$(FAKE_UNIT_UNKNOWN=1 run_uninstall)" || fail "unknown-manager uninstall exited non-zero: ${out}"
[[ -d "${pkg}" && ! -s "${WORK}/npm.log" ]] || fail "package removed while systemd state is unknown: ${out}"

printf '%s\n' 'PASS: rotator npm package is removed only when marked and no systemd unit still uses it'
