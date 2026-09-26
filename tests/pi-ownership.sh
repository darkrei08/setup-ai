#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DRY_RUN=1
source <(sed '/^# Main$/,$d' "${repo}/setup-ai.sh")
DRY_RUN=0
SCRIPT_DIR="${repo}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
declare -F install_pi_package_owned >/dev/null || fail 'install_pi_package_owned is not defined'
declare -F pi_package_identity >/dev/null || fail 'pi_package_identity is not defined'
declare -F pi_package_registration_count >/dev/null || fail 'pi_package_registration_count is not defined'
declare -F pi_package_receipt_path >/dev/null || fail 'pi_package_receipt_path is not defined'
declare -F uninstall_pi_package_state >/dev/null || fail 'uninstall_pi_package_state is not defined'

FAKE_PI_CALLS=0
FAKE_PI_REMOVES=0
FAKE_PI_LOG="${TMP_DIR}/pi-calls.log"
: >"${FAKE_PI_LOG}"

pi() {
    local operation="$1" spec="$2"
    FAKE_PI_CALLS=$((FAKE_PI_CALLS + 1))
    printf '%s\n' "$*" >>"${FAKE_PI_LOG}"
    if [[ "${operation}" == install ]]; then
        [[ "${PI_FAKE_FAIL_INSTALL:-0}" == 1 ]] && return 7
        [[ "${PI_FAKE_NOOP_INSTALL:-0}" == 1 ]] && return 0
        node -e '
            const fs = require("node:fs");
            const file = process.argv[1], source = process.argv[2], mode = process.argv[3];
            let settings = {};
            try { settings = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { if (e.code !== "ENOENT") throw e; }
            if (!Array.isArray(settings.packages)) settings.packages = [];
            settings.packages.push(mode === "mismatch" ? "npm:wrong-package" : source);
            if (mode === "duplicate") settings.packages.push(source);
            fs.writeFileSync(file, JSON.stringify(settings));
        ' "${PI_AGENT_DIR}/settings.json" "${spec}" "${PI_FAKE_INSTALL_MODE:-fresh}"
    elif [[ "${operation}" == remove ]]; then
        FAKE_PI_REMOVES=$((FAKE_PI_REMOVES + 1))
        [[ "${PI_FAKE_FAIL_REMOVE:-0}" == 1 ]] && return 7
        node -e '
            const fs = require("node:fs"), path = require("node:path"), os = require("node:os");
            const file = process.argv[1], wanted = process.argv[2];
            const identity = (source, base) => {
                let spec = String(source).trim();
                if (spec.startsWith("npm:")) { spec = spec.slice(4); const at = spec.lastIndexOf("@"); if (at > 0) spec = spec.slice(0, at); return "npm:" + spec.toLowerCase(); }
                if (spec.startsWith("git:")) { spec = spec.slice(4).split("#")[0]; const at = spec.lastIndexOf("@"); if (at > 0) spec = spec.slice(0, at); return "git:" + spec.replace(/\.git$/, "").toLowerCase(); }
                if (spec === "~" || spec.startsWith("~/") || spec.startsWith("~\\")) spec = path.join(os.homedir(), spec.slice(1).replace(/^[\\/]+/, ""));
                const resolved = path.resolve(base, spec); return "local:" + (process.platform === "win32" ? resolved.toLowerCase() : resolved);
            };
            const settings = JSON.parse(fs.readFileSync(file, "utf8"));
            const base = path.dirname(file), wantedId = identity(wanted, base);
            settings.packages = settings.packages.filter(entry => identity(typeof entry === "string" ? entry : entry.source, base) !== wantedId);
            fs.writeFileSync(file, JSON.stringify(settings));
        ' "${PI_AGENT_DIR}/settings.json" "${spec}"
        if [[ "${PI_FAKE_CHANGE_RECEIPT:-0}" == 1 ]]; then
            local receipt_path
            receipt_path="$(pi_package_receipt_path "${spec}")"
            printf 'changed during remove\n' >"${receipt_path}"
        fi
    else
        printf 'unexpected fake pi arguments: %s\n' "$*" >&2
        return 2
    fi
}

new_case() {
    local name="$1"
    PI_AGENT_DIR="${TMP_DIR}/pi-${name}/agent"
    XDG_STATE_HOME="${TMP_DIR}/pi-${name}/state"
    mkdir -p "${PI_AGENT_DIR}"
    export PI_AGENT_DIR XDG_STATE_HOME
}

write_settings() {
    printf '%s\n' "$1" >"${PI_AGENT_DIR}/settings.json"
}

spec='npm:@example/scoped-pkg@1.0.0'
new_case identity
[[ "$(pi_package_identity 'npm:@example/scoped-pkg@1.0.0')" == "$(pi_package_identity 'npm:@example/scoped-pkg@2.0.0')" ]] || fail 'npm scope/version normalization differs'
[[ "$(pi_package_identity 'git:github.com/owner/repo.git#v1')" == "$(pi_package_identity 'git:github.com/owner/repo@v2')" ]] || fail 'git ref normalization differs'
[[ "$(pi_package_identity 'extensions/local-package')" == "$(pi_package_identity "${PI_AGENT_DIR}/extensions/local-package")" ]] || fail 'relative package path was not resolved against the Pi agent directory'

new_case fresh
install_pi_package_owned test "${spec}" || fail 'fresh Pi registration install failed'
receipt="$(pi_package_receipt_path "${spec}")"
[[ -f "${receipt}" ]] || fail 'fresh registration did not publish its ownership receipt'
[[ "$(uninstall_pi_package_state "${spec}")" == receipt-backed* ]] || fail 'fresh registration was not inventoried as receipt-backed'

new_case existing
write_settings '{"packages":["npm:@example/scoped-pkg@1.0.0"]}'
PI_FAKE_NOOP_INSTALL=1 install_pi_package_owned test "${spec}" || fail 'pre-existing registration install did not verify'
unset PI_FAKE_NOOP_INSTALL
[[ ! -e "$(pi_package_receipt_path "${spec}")" ]] || fail 'pre-existing/upgraded registration was claimed'
[[ "$(uninstall_pi_package_state "${spec}")" == protected* ]] || fail 'pre-existing registration was not protected in inventory'

new_case mismatch
PI_FAKE_INSTALL_MODE=mismatch
if install_pi_package_owned test "${spec}"; then fail 'mismatched settings readback was accepted'; fi
unset PI_FAKE_INSTALL_MODE
[[ ! -e "$(pi_package_receipt_path "${spec}")" ]] || fail 'mismatched registration received a receipt'
[[ "$(uninstall_pi_package_state "${spec}")" == absent* ]] || fail 'mismatched registration was treated as the requested package'

new_case malformed
printf '{bad json\n' >"${PI_AGENT_DIR}/settings.json"
FAKE_PI_BEFORE=${FAKE_PI_CALLS}
if install_pi_package_owned test "${spec}"; then fail 'malformed settings were accepted for installation ownership'; fi
[[ "${FAKE_PI_CALLS}" -eq "${FAKE_PI_BEFORE}" ]] || fail 'pi ran despite malformed pre-install settings'

new_case unreadable
mkdir "${PI_AGENT_DIR}/settings.json"
FAKE_PI_BEFORE=${FAKE_PI_CALLS}
if install_pi_package_owned test "${spec}"; then fail 'unreadable settings were accepted for installation ownership'; fi
[[ "${FAKE_PI_CALLS}" -eq "${FAKE_PI_BEFORE}" ]] || fail 'pi ran despite unreadable pre-install settings'

new_case duplicate
write_settings '{"packages":["npm:@example/scoped-pkg@1.0.0","npm:@example/scoped-pkg@2.0.0"]}'
PI_FAKE_NOOP_INSTALL=1
if install_pi_package_owned test "${spec}"; then fail 'duplicate normalized registrations were accepted'; fi
unset PI_FAKE_NOOP_INSTALL
[[ ! -e "$(pi_package_receipt_path "${spec}")" ]] || fail 'duplicate registration received a receipt'
[[ "$(uninstall_pi_package_state "${spec}")" == protected* ]] || fail 'duplicate registration was not protected in inventory'

new_case duplicate-after
PI_FAKE_INSTALL_MODE=duplicate
if install_pi_package_owned test "${spec}"; then fail 'duplicate post-install readback was accepted'; fi
unset PI_FAKE_INSTALL_MODE
[[ ! -e "$(pi_package_receipt_path "${spec}")" ]] || fail 'duplicate post-install registration received a receipt'

new_case receipt-collision
receipt="$(pi_package_receipt_path "${spec}")"
mkdir -p "$(dirname "${receipt}")"
printf 'preserve existing receipt\n' >"${receipt}"
if install_pi_package_owned test "${spec}"; then fail 'pre-existing receipt collision was reported as owned'; fi
[[ "$(cat "${receipt}")" == 'preserve existing receipt' ]] || fail 'receipt collision overwrote the pre-existing receipt'
[[ "$(pi_package_registration_count "${spec}")" -eq 1 ]] || fail 'receipt failure deleted the registration'

new_case receipt-symlink
mkdir -p "${XDG_STATE_HOME}/setup-ai" "${TMP_DIR}/receipt-outside"
ln -s "${TMP_DIR}/receipt-outside" "${XDG_STATE_HOME}/setup-ai/ownership"
if install_pi_package_owned test "${spec}"; then fail 'symlinked receipt directory was accepted'; fi
[[ "$(pi_package_registration_count "${spec}")" -eq 1 && ! -e "${TMP_DIR}/receipt-outside/pi-packages" ]] || fail 'unsafe receipt path did not preserve registration or wrote outside the state root'

new_case inventory
install_pi_package_owned test "${spec}" || fail 'inventory fixture install failed'
settings_before="$(cat "${PI_AGENT_DIR}/settings.json")"
receipt="$(pi_package_receipt_path "${spec}")"
receipt_before="$(cat "${receipt}")"
FAKE_PI_BEFORE=${FAKE_PI_CALLS}
[[ "$(uninstall_pi_package_state "${spec}")" == receipt-backed* ]] || fail 'inventory lost receipt-backed state'
[[ "$(cat "${PI_AGENT_DIR}/settings.json")" == "${settings_before}" && "$(cat "${receipt}")" == "${receipt_before}" && "${FAKE_PI_CALLS}" -eq "${FAKE_PI_BEFORE}" ]] || fail 'inventory mutated state or invoked pi'
DRY_RUN=1
UNINSTALL_YES=1
uninstall_remove_pi_package "${spec}" >/dev/null || fail 'dry-run removal check failed'
DRY_RUN=0
[[ "$(cat "${PI_AGENT_DIR}/settings.json")" == "${settings_before}" && "$(cat "${receipt}")" == "${receipt_before}" && "${FAKE_PI_CALLS}" -eq "${FAKE_PI_BEFORE}" ]] || fail 'dry-run mutated settings, receipt, or invoked pi'

new_case changed
install_pi_package_owned test "${spec}" || fail 'changed-registration fixture install failed'
printf '{"packages":["npm:replacement-package"]}\n' >"${PI_AGENT_DIR}/settings.json"
[[ "$(uninstall_pi_package_state "${spec}")" == protected* ]] || fail 'changed identity with a stale receipt was not protected'
UNINSTALL_YES=1
if uninstall_remove_pi_package "${spec}"; then fail 'changed registration was removed or reported successful'; fi
[[ "${FAKE_PI_REMOVES}" -eq 0 && -f "$(pi_package_receipt_path "${spec}")" ]] || fail 'changed registration removal invoked pi or deleted its receipt'

new_case remove-failure
install_pi_package_owned test "${spec}" || fail 'failed-removal fixture install failed'
UNINSTALL_YES=1
PI_FAKE_FAIL_REMOVE=1
if uninstall_remove_pi_package "${spec}"; then fail 'failed pi remove was reported successful'; fi
unset PI_FAKE_FAIL_REMOVE
[[ "$(pi_package_registration_count "${spec}")" -eq 1 && -f "$(pi_package_receipt_path "${spec}")" ]] || fail 'failed pi remove did not preserve registration and receipt'

new_case receipt-change-during-remove
install_pi_package_owned test "${spec}" || fail 'receipt-race fixture install failed'
receipt="$(pi_package_receipt_path "${spec}")"
UNINSTALL_YES=1
PI_FAKE_CHANGE_RECEIPT=1
if uninstall_remove_pi_package "${spec}"; then fail 'receipt race was reported as successful removal'; fi
unset PI_FAKE_CHANGE_RECEIPT
[[ "$(pi_package_registration_count "${spec}")" -eq 1 && "$(cat "${receipt}")" == 'changed during remove' ]] || fail 'receipt verification failure did not restore the registration and preserve the raced receipt'

new_case removal
install_pi_package_owned test "${spec}" || fail 'removal fixture install failed'
node -e 'const fs=require("node:fs");fs.writeFileSync(process.argv[1],JSON.stringify({packages:["npm:@example/scoped-pkg@1.0.0","npm:unrelated-package"]}));' "${PI_AGENT_DIR}/settings.json"
# Use the actual Pi state after install while retaining an unrelated registration and protected data.
printf 'auth-sentinel\n' >"${PI_AGENT_DIR}/auth.json"
mkdir -p "${PI_AGENT_DIR}/sessions" "${PI_AGENT_DIR}/npm/node_modules/keep-me"
printf 'session-sentinel\n' >"${PI_AGENT_DIR}/sessions/keep"
printf 'package-sentinel\n' >"${PI_AGENT_DIR}/npm/node_modules/keep-me/data"
settings_before="$(cat "${PI_AGENT_DIR}/settings.json")"
UNINSTALL_YES=1
UNINSTALL_PURGE=1
uninstall_remove_pi_package "${spec}" || fail 'receipt-backed Pi registration removal failed'
unset UNINSTALL_PURGE
[[ "$(pi_package_registration_count "${spec}")" -eq 0 && "$(pi_package_registration_count 'npm:unrelated-package')" -eq 1 ]] || fail 'removal did not remove only the exact registration'
[[ ! -e "$(pi_package_receipt_path "${spec}")" ]] || fail 'successful removal left its registration receipt'
[[ -f "${PI_AGENT_DIR}/settings.json" && -f "${PI_AGENT_DIR}/auth.json" && -f "${PI_AGENT_DIR}/sessions/keep" && -f "${PI_AGENT_DIR}/npm/node_modules/keep-me/data" ]] || fail 'Pi root, settings, auth, sessions, or package data was deleted'
[[ "${FAKE_PI_REMOVES}" -gt 0 ]] || fail 'receipt-backed removal did not call fake pi remove'

printf 'Pi registration ownership checks passed.\n'
