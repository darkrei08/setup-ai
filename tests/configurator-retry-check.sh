#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_AI_SH="${ROOT}/setup-ai.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-configurator-check.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v awk >/dev/null 2>&1 || fail "awk is required"
command -v script >/dev/null 2>&1 || fail "script is required for the TTY-path check"

extract_function() {
    local name="$1"
    awk -v name="${name}" '
        $0 ~ "^" name "\\(\\) \\{" { capture = 1 }
        capture {
            line = $0
            opens = gsub(/\{/, "", line)
            closes = gsub(/\}/, "", line)
            depth += opens - closes
            print
            if (depth == 0) exit
        }
    ' "${SETUP_AI_SH}"
}

FUNCTION_FILE="${TEST_DIR}/mod-gentle-ai.sh"
export FUNCTION_FILE
extract_function mod_gentle_ai > "${FUNCTION_FILE}"
[[ -s "${FUNCTION_FILE}" ]] || fail "could not extract mod_gentle_ai"

make_case() {
    local name="$1"
    local case_dir="${TEST_DIR}/${name}"
    mkdir -p "${case_dir}/bin" "${case_dir}/home" "${case_dir}/agent"
    printf '0\n' > "${case_dir}/count"
    cat > "${case_dir}/bin/gentle-ai" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' 'gentle-ai test'
    exit 0
fi
if [[ "${1:-}" == "install" ]]; then
    count=$(( $(<"${FAKE_COUNT_FILE}") + 1 ))
    printf '%s\n' "${count}" > "${FAKE_COUNT_FILE}"
    printf '%s\n' 'generic selector failure'
    exit "${FAKE_RC}"
fi
exit 2
SCRIPT
    chmod +x "${case_dir}/bin/gentle-ai"
    cat > "${case_dir}/bin/sleep" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_SLEEP_FILE}"
SCRIPT
    chmod +x "${case_dir}/bin/sleep"
    cat > "${case_dir}/harness.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
section() { :; }
handle_quiet_tools_conflict() { return 0; }
github_api_token() { return 0; }
agent_config_dir() { printf '%s\n' "${CASE_DIR}/missing-agent"; }
dry_run_note() { :; }
verify_pi_startup() { return 0; }
log_event() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${HUMAN_LOG}"
}
run_cmd() {
    local capture_output=""
    shift
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --capture-output) capture_output="$2"; shift ;;
            --verify) ;;
            *) printf 'unsupported run_cmd option: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    if [[ -n "${capture_output}" ]]; then
        "$@" >"${capture_output}" 2>&1
    else
        "$@"
    fi
    return $?
}
source "${FUNCTION_FILE}"
mod_gentle_ai
printf '%s\n' "$?" > "${RESULT_FILE}"
SCRIPT
    chmod +x "${case_dir}/harness.sh"
    printf '%s\n' "${case_dir}"
}

run_case() {
    local name="$1" rc="$2" tty="$3"
    local case_dir
    case_dir="$(make_case "${name}")"
    export CASE_DIR="${case_dir}" FAKE_RC="${rc}"
    export FAKE_COUNT_FILE="${case_dir}/count" FAKE_SLEEP_FILE="${case_dir}/sleep"
    export RESULT_FILE="${case_dir}/result" HUMAN_LOG="${case_dir}/human.log"
    export TMP_DIR="${case_dir}/tmp" HOME="${case_dir}/home" PI_AGENT_DIR="${case_dir}/agent"
    export OS_FAMILY=linux NONINTERACTIVE=0 DRY_RUN=0
    mkdir -p "${TMP_DIR}"
    : > "${HUMAN_LOG}"
    export PATH="${case_dir}/bin:/usr/bin:/bin"

    if [[ "${tty}" == yes ]]; then
        script -qec "bash ${case_dir}/harness.sh" /dev/null > "${case_dir}/runner.out" 2>&1
    else
        bash "${case_dir}/harness.sh" </dev/null > "${case_dir}/runner.out" 2>&1
    fi
    printf '%s\n' "${case_dir}"
}

TTY_CASE="$(run_case interactive-generic 7 yes)"
[[ "$(<"${TTY_CASE}/result")" == 1 ]] || fail "generic interactive failure did not fail the module"
grep -Fq 'interactive gentle-ai selector exited non-zero (rc=7)' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure did not report the observed selector failure"
! grep -Fq 'anonymous GitHub API quota exhausted' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure produced the quota message"
! grep -Fq 'after rate-limit signature' "${TTY_CASE}/human.log" \
    || fail "generic interactive retry claimed a rate-limit signature"
[[ "$(<"${TTY_CASE}/count")" == 3 ]] || fail "generic interactive failure did not use the bounded retry count"
[[ "$(wc -l < "${TTY_CASE}/sleep")" -eq 2 ]] || fail "generic interactive failure did not use both bounded backoffs"
printf 'PASS: generic interactive failure stays neutral\n'

INTERRUPT_CASE="$(run_case interrupted 130 no)"
[[ "$(<"${INTERRUPT_CASE}/result")" == 1 ]] || fail "interrupted configurator did not fail the module"
[[ "$(<"${INTERRUPT_CASE}/count")" == 1 ]] || fail "interrupted configurator was retried"
[[ ! -e "${INTERRUPT_CASE}/sleep" ]] || fail "interrupted configurator slept before retry"
grep -Fq 'configurator_retry_skipped' "${INTERRUPT_CASE}/human.log" \
    || fail "interrupted configurator did not log the skipped retry"
grep -Fq 'No retry attempted because the gentle-ai configurator run was interrupted' "${INTERRUPT_CASE}/human.log" \
    || fail "interrupted configurator did not explain the skipped retry"
! grep -Fq '|configurator_retry|' "${INTERRUPT_CASE}/human.log" \
    || fail "interrupted configurator emitted a retry event"
printf 'PASS: rc 130 skips sleep and retry\n'
