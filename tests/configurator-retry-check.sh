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
    case "${FAKE_MODE}" in
        rate-limit-once)
            if [[ "${count}" == 1 ]]; then
                printf '%s\n' 'Error: download engram binary: fetch latest engram version: GitHub API returned HTTP 403'
                exit 1
            fi
            exit 0
            ;;
        rate-limit-always)
            printf '%s\n' 'Error: download engram binary: fetch latest engram version: GitHub API returned HTTP 403'
            exit 1
            ;;
        rate-limit-then-neutral)
            if [[ "${count}" == 1 ]]; then
                printf '%s\n' 'Error: download engram binary: fetch latest engram version: GitHub API returned HTTP 403'
            else
                printf '%s\n' 'generic selector failure'
            fi
            exit 1
            ;;
        *)
            printf '%s\n' 'generic selector failure'
            exit "${FAKE_RC}"
            ;;
    esac
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
        "$@" 2>&1 | tee -a "${HUMAN_LOG}" "${capture_output}" >/dev/null
    else
        "$@" 2>&1 | tee -a "${HUMAN_LOG}" >/dev/null
    fi
    local rc="${PIPESTATUS[0]}"
    if (( rc != 0 )); then
        STEP_FAILED=$(( STEP_FAILED + 1 ))
        STEP_FAIL_STEP="gentle-ai test"
        STEP_FAIL_RC="${rc}"
    fi
    return "${rc}"
}
STEP_FAILED=0
STEP_FAIL_STEP=""
STEP_FAIL_RC=0
source "${FUNCTION_FILE}"
mod_gentle_ai
rc=$?
printf '%s\n' "${rc}" > "${RESULT_FILE}"
printf '%s\n' "${STEP_FAILED}" > "${CASE_DIR}/steps-failed"
SCRIPT
    chmod +x "${case_dir}/harness.sh"
    printf '%s\n' "${case_dir}"
}

run_case() {
    local name="$1" rc="$2" tty="$3" mode="$4"
    local case_dir
    case_dir="$(make_case "${name}")"
    export CASE_DIR="${case_dir}" FAKE_RC="${rc}" FAKE_MODE="${mode}"
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

TTY_CASE="$(run_case interactive-generic 7 yes generic)"
[[ "$(<"${TTY_CASE}/result")" == 1 ]] || fail "generic interactive failure did not fail the module"
grep -Fq 'interactive gentle-ai selector exited non-zero (rc=7)' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure did not report the observed selector failure"
! grep -Fq 'anonymous GitHub API quota exhausted' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure produced the quota message"
! grep -Fq 'after rate-limit signature' "${TTY_CASE}/human.log" \
    || fail "generic interactive retry claimed a rate-limit signature"
grep -Fq 'reason=interactive selector failure (output not captured)' "${TTY_CASE}/human.log" \
    || fail "interactive retry did not log its reason field"
! grep -Fq 'signature=interactive selector failure' "${TTY_CASE}/human.log" \
    || fail "interactive retry still logged its reason as a signature"
[[ "$(<"${TTY_CASE}/count")" == 3 ]] || fail "generic interactive failure did not use the bounded retry count"
[[ "$(wc -l < "${TTY_CASE}/sleep")" -eq 2 ]] || fail "generic interactive failure did not use both bounded backoffs"
printf 'PASS: generic interactive failure stays neutral\n'

INTERRUPT_CASE="$(run_case interrupted 130 no generic)"
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

RATE_LIMIT_SUCCESS_CASE="$(run_case rate-limit-recovered 1 no rate-limit-once)"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/result")" == 0 ]] || fail "rate-limit recovery did not complete the module"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/count")" == 2 ]] || fail "rate-limit recovery did not make exactly one retry"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/steps-failed")" == 0 ]] || fail "recovered rate-limit attempt remained in failed step accounting"
[[ "$(wc -l < "${RATE_LIMIT_SUCCESS_CASE}/sleep")" -eq 1 ]] || fail "rate-limit recovery did not use one backoff"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/sleep")" == 15 ]] || fail "rate-limit recovery did not back off for 15 seconds"
[[ "$(grep -Fc '|configurator_retry|' "${RATE_LIMIT_SUCCESS_CASE}/human.log")" -eq 1 ]] || fail "rate-limit recovery did not log exactly one retry"
grep -Fq 'backoff_seconds=15' "${RATE_LIMIT_SUCCESS_CASE}/human.log" \
    || fail "rate-limit recovery did not log the 15-second backoff"
grep -Fq 'reason=HTTP 403 + GitHub API download path' "${RATE_LIMIT_SUCCESS_CASE}/human.log" \
    || fail "rate-limit retry did not log its reason field"
printf 'PASS: transient HTTP 403 retries once and recovers\n'

RATE_LIMIT_THEN_NEUTRAL_CASE="$(run_case rate-limit-then-neutral 1 no rate-limit-then-neutral)"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/result")" == 1 ]] || fail "stale rate-limit output made the neutral failure recover"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/count")" == 2 ]] || fail "neutral failure after rate-limit was retried more than once"
[[ "$(wc -l < "${RATE_LIMIT_THEN_NEUTRAL_CASE}/sleep")" -eq 1 ]] || fail "neutral failure after rate-limit used the wrong retry count"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/sleep")" == 15 ]] || fail "neutral failure after rate-limit used the wrong backoff"
[[ "$(grep -Fc '|configurator_retry|' "${RATE_LIMIT_THEN_NEUTRAL_CASE}/human.log")" -eq 1 ]] || fail "neutral failure after rate-limit logged the wrong retry count"
grep -Fq 'no HTTP 403 + GitHub API signature was observed in captured output' "${RATE_LIMIT_THEN_NEUTRAL_CASE}/human.log" \
    || fail "stale rate-limit output produced the quota diagnosis"
! grep -Fq 'anonymous GitHub API quota exhausted' "${RATE_LIMIT_THEN_NEUTRAL_CASE}/human.log" \
    || fail "neutral failure after rate-limit made a quota claim"
printf 'PASS: per-attempt capture truncation prevents stale quota diagnosis\n'

RATE_LIMIT_EXHAUSTED_CASE="$(run_case rate-limit-exhausted 1 no rate-limit-always)"
[[ "$(<"${RATE_LIMIT_EXHAUSTED_CASE}/result")" == 1 ]] || fail "exhausted rate-limit did not fail the module"
[[ "$(<"${RATE_LIMIT_EXHAUSTED_CASE}/count")" == 3 ]] || fail "exhausted rate-limit did not make exactly 3 attempts"
[[ "$(wc -l < "${RATE_LIMIT_EXHAUSTED_CASE}/sleep")" -eq 2 ]] || fail "exhausted rate-limit did not use both backoffs"
[[ "$(<"${RATE_LIMIT_EXHAUSTED_CASE}/sleep")" == $'15\n45' ]] || fail "exhausted rate-limit did not use 15 and 45 second backoffs"
[[ "$(grep -Fc '|configurator_retry|' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log")" -eq 2 ]] || fail "exhausted rate-limit did not log both retries"
grep -Fq 'anonymous GitHub API quota exhausted' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the anonymous GitHub API quota"
grep -Fq "gh auth login" "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the gh auth login remedy"
grep -Fq 'GITHUB_TOKEN/GH_TOKEN' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the token remedy"
printf 'PASS: repeated HTTP 403 exhausts retries with quota remedies\n'

NEUTRAL_CASE="$(run_case nonmatching 7 no generic)"
[[ "$(<"${NEUTRAL_CASE}/result")" == 1 ]] || fail "nonmatching configurator failure did not fail the module"
[[ "$(<"${NEUTRAL_CASE}/count")" == 1 ]] || fail "nonmatching configurator failure was retried"
[[ ! -e "${NEUTRAL_CASE}/sleep" ]] || fail "nonmatching configurator failure slept before retry"
grep -Fq 'no HTTP 403 + GitHub API signature was observed in captured output' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure did not use the neutral message"
! grep -Fq 'anonymous GitHub API quota exhausted' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure made a quota claim"
! grep -Fq 'gh auth login' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure named a quota remedy"
! grep -Fq 'GITHUB_TOKEN/GH_TOKEN' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure named a token remedy"
printf 'PASS: nonmatching configurator failure stays neutral\n'
