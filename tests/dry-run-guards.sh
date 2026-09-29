#!/usr/bin/env bash
# --dry-run promises no writes: the Pi settings repairs and the pi startup check must
# only report through dry_run_note. The product functions are sourced in isolation
# with stubs; no real installer runs.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_AI_SH="${ROOT}/setup-ai.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-dry-run.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

failures=0
check() {
    local name="$1"
    shift
    if "$@"; then printf 'PASS: %s\n' "${name}"; else printf 'FAIL: %s\n' "${name}"; failures=$((failures + 1)); fi
}

extract_function() {
    awk -v name="$1" '
        $0 ~ "^" name "\\(\\) \\{" { capture = 1 }
        capture {
            line = $0
            depth += gsub(/\{/, "", line) - gsub(/\}/, "", line)
            print
            if (depth == 0) exit
        }
    ' "${SETUP_AI_SH}"
}

PRODUCT_FUNCTIONS="${TEST_DIR}/product-functions.sh"
for function_name in dry_run_note remove_line_from_file remove_stale_quiet_tools_switch \
    remove_stale_rpiv_question_extension handle_quiet_tools_conflict verify_pi_startup mod_claude_code; do
    extract_function "${function_name}" >> "${PRODUCT_FUNCTIONS}"
done

TMP_DIR="${TEST_DIR}/runtime"
HUMAN_LOG="${TEST_DIR}/human.log"
PI_AGENT_DIR="${TEST_DIR}/agent"
HOME="${TEST_DIR}/home"
export HOME
DRY_RUN=1
mkdir -p "${TMP_DIR}" "${PI_AGENT_DIR}" "${HOME}" "${TEST_DIR}/bin"
: > "${HUMAN_LOG}"
log_event() { printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${HUMAN_LOG}"; }
source "${PRODUCT_FUNCTIONS}"

SETTINGS="${PI_AGENT_DIR}/settings.json"
# Both repairs apply to this file: the stale rpiv entry and the pi-tool-display shadow.
cat > "${SETTINGS}" <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:@juicesharp/rpiv-ask-user-question",
    "npm:pi-tool-display"
  ]
}
JSON
cp -p -- "${SETTINGS}" "${TEST_DIR}/settings.before"

PI_MARKER="${TEST_DIR}/pi-was-executed"
cat > "${TEST_DIR}/bin/pi" <<SH
#!/usr/bin/env bash
: > "${PI_MARKER}"
SH
chmod +x "${TEST_DIR}/bin/pi"
PATH="${TEST_DIR}/bin:${PATH}"

check_repairs_leave_settings_untouched() {
    handle_quiet_tools_conflict >/dev/null || return 1
    cmp -s -- "${TEST_DIR}/settings.before" "${SETTINGS}" \
        && [[ ! -e "${SETTINGS}.setup-ai.tmp" ]] \
        && [[ "$(grep -c "|dry_run_note|.*${SETTINGS}" "${HUMAN_LOG}")" == 2 ]]
}

# Control: the same fixture is rewritten outside a dry run, so the check above is not vacuous.
check_fixture_is_repaired_without_dry_run() {
    local control="${TEST_DIR}/control"
    mkdir -p "${control}" && cp -p -- "${TEST_DIR}/settings.before" "${control}/settings.json" || return 1
    ( DRY_RUN=0; PI_AGENT_DIR="${control}"; handle_quiet_tools_conflict ) >/dev/null || return 1
    ! cmp -s -- "${TEST_DIR}/settings.before" "${control}/settings.json"
}

check_startup_check_does_not_launch_pi() {
    [[ "$(command -v pi)" == "${TEST_DIR}/bin/pi" ]] || return 1
    : > "${HUMAN_LOG}"
    verify_pi_startup >/dev/null || return 1
    [[ ! -e "${PI_MARKER}" ]] && grep -q '|dry_run_note|' "${HUMAN_LOG}"
}

# capture_cmd assigns through printf -v, so an undeclared target becomes a global.
check_claude_version_stays_local() {
    (
        section() { :; }
        require_command() { :; }
        run_cmd() { :; }
        capture_cmd() { printf -v "$1" '%s' "9.9.9"; }
        DRY_RUN=0 OS_FAMILY=linux PATH="${TEST_DIR}/empty-path"
        mod_claude_code >/dev/null || exit 1
        [[ -z "${claude_version+set}" ]]
    )
}

check "Dry-run settings repairs leave a provisioned settings.json byte-identical" check_repairs_leave_settings_untouched
check "The dry-run fixture is repaired outside a dry run" check_fixture_is_repaired_without_dry_run
check "Dry-run startup verification never executes pi" check_startup_check_does_not_launch_pi
check "mod_claude_code keeps claude_version local on a fresh install" check_claude_version_stays_local

if (( failures > 0 )); then
    printf '%d dry-run guard check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'All dry-run guard checks passed\n'
