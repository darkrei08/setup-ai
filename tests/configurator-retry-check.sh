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
        $0 ~ "^" name "\\(\\) \\{" { capture = 1; print; next }
        capture && $0 ~ "^[[:alnum:]_]+\\(\\) \\{" { exit }
        capture { print }
    ' "${SETUP_AI_SH}"
}

FUNCTION_FILE="${TEST_DIR}/production-functions.sh"
export FUNCTION_FILE
for function_name in json_escape json_log log_event module_succeeded is_selected record_step write_run_summary run_cmd dry_run_note section mod_gentle_ai; do
    extract_function "${function_name}" >> "${FUNCTION_FILE}"
done
[[ -s "${FUNCTION_FILE}" ]] || fail "could not extract production functions"

bash_retry_sleep_fallback_rc="$(awk '/local configurator_retry_sleep_fallback_rc=/{value=$0; sub(/^.*fallback_rc=/, "", value); sub(/[^0-9].*$/, "", value); print value; exit}' "${SETUP_AI_SH}")"
ps_retry_sleep_fallback_rc="$(awk '/\$configuratorRetrySleepFallbackReturnCode =/{value=$0; sub(/^.*= /, "", value); sub(/[^0-9].*$/, "", value); print value; exit}' "${ROOT}/setup-ai.ps1")"
[[ -n "${bash_retry_sleep_fallback_rc}" && -n "${ps_retry_sleep_fallback_rc}" ]] \
    || fail "retry sleep fallback is not defined on both platforms"
[[ "${bash_retry_sleep_fallback_rc}" == "${ps_retry_sleep_fallback_rc}" ]] \
    || fail "retry sleep fallback differs between Bash (${bash_retry_sleep_fallback_rc}) and PowerShell (${ps_retry_sleep_fallback_rc})"

make_case() {
    local name="$1"
    local case_dir="${TEST_DIR}/${name}"
    mkdir -p "${case_dir}/bin" "${case_dir}/home" "${case_dir}/agent" "${case_dir}/tmp"
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
        rate-limit-sleep-fail)
            printf '%s\n' 'Error: download engram binary: fetch latest engram version: GitHub API returned HTTP 403'
            exit "${FAKE_RC}"
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
    cat > "${case_dir}/bin/later-module" <<'SCRIPT'
#!/usr/bin/env bash
exit 7
SCRIPT
    chmod +x "${case_dir}/bin/later-module"
    cat > "${case_dir}/bin/sleep" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${FAKE_SLEEP_RC}" != 0 ]]; then
    exit "${FAKE_SLEEP_RC}"
fi
printf '%s\n' "$*" >> "${FAKE_SLEEP_FILE}"
SCRIPT
    chmod +x "${case_dir}/bin/sleep"
    cat > "${case_dir}/harness.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
handle_quiet_tools_conflict() { return 0; }
github_api_token() { return 0; }
agent_config_dir() { printf '%s\n' "${CASE_DIR}/missing-agent"; }
verify_pi_startup() { return 0; }
source "${CASE_DIR%/*}/production-functions.sh"

STEP_INSTALLED=0 STEP_VERIFIED=0 STEP_SKIPPED=0 STEP_PLANNED=0 STEP_FAILED=0
STEP_FAIL_STEP="" STEP_FAIL_RC=0 LAST_ERROR_STEP="" LAST_ERROR_RC=0
RUN_INTERRUPTED=0 INTERRUPT_SIGNAL="" INTERRUPT_RC=0 SUMMARY_WRITTEN=0
RUN_ACTIVE=1 RUN_ID=test-run RUN_STARTED_AT=2026-09-21T00:00:00Z RUN_STARTED_SECONDS=0
CURRENT_MODULE=gentle-ai MODULES_OK="" SELECTED_MODULES=(gentle-ai) SELECTED_DISPLAY=gentle-ai
MODULE_INDEX=0 MODULE_TOTAL=1 VERBOSE=1 DEBUG=0 DRY_RUN="${DRY_RUN:-0}"
HUMAN_LOG="${HUMAN_LOG}" JSONL_LOG="${JSONL_LOG}" REPORT_FILE="${REPORT_FILE}"
TMP_DIR="${TMP_DIR}" HOME="${HOME}" PI_AGENT_DIR="${PI_AGENT_DIR}"
OS_FAMILY=linux NONINTERACTIVE=0

rc=0
mod_gentle_ai || rc=$?
case "${SCENARIO}" in
    dry-run)
        write_run_summary 0
        ;;
    recovered-summary)
        [[ "${rc}" == 0 ]] || exit 1
        MODULES_OK=" gentle-ai"
        SELECTED_MODULES=(gentle-ai later) CURRENT_MODULE=later
        log_event ERROR later later_failure "Later module failed directly" 7
        write_run_summary 7
        ;;
    interrupted-summary)
        [[ "${rc}" == 0 ]] || exit 1
        MODULES_OK=" gentle-ai"
        SELECTED_MODULES=(gentle-ai later) CURRENT_MODULE=later
        RUN_INTERRUPTED=1 INTERRUPT_SIGNAL=INT INTERRUPT_RC=130
        log_event ERROR bootstrap run_interrupted "Run interrupted by INT" 130 "signal=INT;module=later"
        write_run_summary 130
        ;;
    run-cmd-summary)
        [[ "${rc}" == 0 ]] || exit 1
        MODULES_OK=" gentle-ai"
        SELECTED_MODULES=(gentle-ai later) CURRENT_MODULE=later
        later_rc=0
        run_cmd later later-module || later_rc=$?
        write_run_summary "${later_rc}"
        ;;
esac
printf '%s\n' "${rc}" > "${RESULT_FILE}"
printf '%s\n' "${STEP_FAILED}" > "${CASE_DIR}/steps-failed"
SCRIPT
    chmod +x "${case_dir}/harness.sh"
    printf '%s\n' "${case_dir}"
}

run_case() {
    local name="$1" rc="$2" tty="$3" mode="$4" sleep_rc="${5:-0}" scenario="${6:-normal}"
    local case_dir
    case_dir="$(make_case "${name}")"
    export CASE_DIR="${case_dir}" FAKE_RC="${rc}" FAKE_MODE="${mode}" FAKE_SLEEP_RC="${sleep_rc}"
    export FAKE_COUNT_FILE="${case_dir}/count" FAKE_SLEEP_FILE="${case_dir}/sleep"
    export RESULT_FILE="${case_dir}/result" HUMAN_LOG="${case_dir}/human.log"
    export JSONL_LOG="${case_dir}/events.jsonl" REPORT_FILE="${case_dir}/report.md"
    export TMP_DIR="${case_dir}/tmp" HOME="${case_dir}/home" PI_AGENT_DIR="${case_dir}/agent"
    if [[ "${scenario}" == dry-run ]]; then
        export DRY_RUN=1
    else
        export DRY_RUN=0
    fi
    export OS_FAMILY=linux NONINTERACTIVE=0 SCENARIO="${scenario}" PATH="${case_dir}/bin:/usr/bin:/bin"
    mkdir -p "${TMP_DIR}"
    : > "${HUMAN_LOG}" "${JSONL_LOG}"

    if [[ "${tty}" == yes ]]; then
        script -qec "bash ${case_dir}/harness.sh" /dev/null > "${case_dir}/runner.out" 2>&1
    else
        bash "${case_dir}/harness.sh" </dev/null > "${case_dir}/runner.out" 2>&1
    fi
    printf '%s\n' "${case_dir}"
}

assert_steps_failed() {
    local case_dir="$1" expected="$2"
    grep -Eq '"steps":\{.*"failed":'"${expected}"'\}' "${case_dir}/events.jsonl" \
        || fail "run summary has the wrong steps_failed value"
}

TTY_CASE="$(run_case interactive-generic 7 yes generic)"
[[ "$(<"${TTY_CASE}/result")" == 1 ]] || fail "generic interactive failure did not fail the module"
grep -Fq 'interactive gentle-ai selector exited non-zero (rc=7)' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure did not report the observed selector failure"
! grep -Fq 'anonymous GitHub API quota exhausted' "${TTY_CASE}/human.log" \
    || fail "generic interactive failure produced the quota message"
! grep -Fq 'after rate-limit signature' "${TTY_CASE}/human.log" \
    || fail "generic interactive retry claimed a rate-limit signature"
grep -Fq 'reason=interactive selector failure (output not captured)' "${TTY_CASE}/events.jsonl" \
    || fail "interactive retry did not log its reason field"
! grep -Fq 'signature=interactive selector failure' "${TTY_CASE}/events.jsonl" \
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
! grep -Fq 'configurator_retry:' "${INTERRUPT_CASE}/human.log" \
    || fail "interrupted configurator emitted a retry event"
printf 'PASS: rc 130 skips sleep and retry\n'

RATE_LIMIT_SUCCESS_CASE="$(run_case rate-limit-recovered 1 no rate-limit-once)"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/result")" == 0 ]] || fail "rate-limit recovery did not complete the module"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/count")" == 2 ]] || fail "rate-limit recovery did not make exactly one retry"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/steps-failed")" == 0 ]] || fail "recovered rate-limit attempt remained in failed step accounting"
grep -Fq '"ev":"command_failed"' "${RATE_LIMIT_SUCCESS_CASE}/events.jsonl" \
    || fail "recovered rate-limit attempt lost its command_failed event"
grep -Fq '"msg":"Step failed"' "${RATE_LIMIT_SUCCESS_CASE}/events.jsonl" \
    || fail "recovered rate-limit attempt lost its failed step_result event"
[[ "$(wc -l < "${RATE_LIMIT_SUCCESS_CASE}/sleep")" -eq 1 ]] || fail "rate-limit recovery did not use one backoff"
[[ "$(<"${RATE_LIMIT_SUCCESS_CASE}/sleep")" == 15 ]] || fail "rate-limit recovery did not back off for 15 seconds"
[[ "$(grep -Fc 'gentle-ai configurator_retry:' "${RATE_LIMIT_SUCCESS_CASE}/human.log")" -eq 1 ]] || fail "rate-limit recovery did not log exactly one retry"
[[ "$(grep -Fc 'gentle-ai configurator_recovered:' "${RATE_LIMIT_SUCCESS_CASE}/human.log")" -eq 1 ]] || fail "rate-limit recovery did not log recovery"
grep -Fq 'backoff_seconds=15' "${RATE_LIMIT_SUCCESS_CASE}/events.jsonl" \
    || fail "rate-limit recovery did not log the 15-second backoff"
grep -Fq 'reason=HTTP 403 + GitHub API download path' "${RATE_LIMIT_SUCCESS_CASE}/events.jsonl" \
    || fail "rate-limit retry did not log its reason field"
printf 'PASS: transient HTTP 403 retries once and recovers\n'

RATE_LIMIT_THEN_NEUTRAL_CASE="$(run_case rate-limit-then-neutral 1 no rate-limit-then-neutral)"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/result")" == 1 ]] || fail "stale rate-limit output made the neutral failure recover"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/count")" == 2 ]] || fail "neutral failure after rate-limit was retried more than once"
[[ "$(wc -l < "${RATE_LIMIT_THEN_NEUTRAL_CASE}/sleep")" -eq 1 ]] || fail "neutral failure after rate-limit used the wrong retry count"
[[ "$(<"${RATE_LIMIT_THEN_NEUTRAL_CASE}/sleep")" == 15 ]] || fail "neutral failure after rate-limit used the wrong backoff"
[[ "$(grep -Fc 'gentle-ai configurator_retry:' "${RATE_LIMIT_THEN_NEUTRAL_CASE}/human.log")" -eq 1 ]] || fail "neutral failure after rate-limit logged the wrong retry count"
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
[[ "$(grep -Fc 'gentle-ai configurator_retry:' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log")" -eq 2 ]] || fail "exhausted rate-limit did not log both retries"
grep -Fq 'anonymous GitHub API quota exhausted' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the anonymous GitHub API quota"
grep -Fq "gh auth login" "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the gh auth login remedy"
grep -Fq 'GITHUB_TOKEN/GH_TOKEN' "${RATE_LIMIT_EXHAUSTED_CASE}/human.log" \
    || fail "exhausted rate-limit did not name the token remedy"
printf 'PASS: repeated HTTP 403 exhausts retries with quota remedies\n'

SLEEP_FAILURE_CASE="$(run_case retry-sleep-failed 7 no rate-limit-sleep-fail 9)"
[[ "$(<"${SLEEP_FAILURE_CASE}/result")" == 1 ]] || fail "sleep failure did not fail the module"
[[ "$(<"${SLEEP_FAILURE_CASE}/count")" == 1 ]] || fail "sleep failure retried the selector"
grep -Fq 'configurator_retry_sleep_failed:' "${SLEEP_FAILURE_CASE}/human.log" \
    || fail "sleep failure did not emit its event"
grep -Fq 'sleep_return_code=9' "${SLEEP_FAILURE_CASE}/events.jsonl" \
    || fail "Bash sleep failure did not preserve the observed sleep return code"
grep -Fq "retry backoff sleep failed (fallback return code=${bash_retry_sleep_fallback_rc}); configurator selector return code=7" "${SLEEP_FAILURE_CASE}/human.log" \
    || fail "sleep failure did not use the documented cross-OS fallback"
! grep -Fq 'no HTTP 403 + GitHub API signature was observed' "${SLEEP_FAILURE_CASE}/human.log" \
    || fail "sleep failure reported a false missing-signature diagnosis"
printf 'PASS: retry sleep failure names its cause and preserves selector rc\n'

NEUTRAL_CASE="$(run_case nonmatching 7 no generic)"
[[ "$(<"${NEUTRAL_CASE}/result")" == 1 ]] || fail "nonmatching configurator failure did not fail the module"
[[ "$(<"${NEUTRAL_CASE}/count")" == 1 ]] || fail "nonmatching configurator failure was retried"
[[ ! -e "${NEUTRAL_CASE}/sleep" ]] || fail "nonmatching configurator failure slept before retry"
grep -Fq 'no HTTP 403 + GitHub API signature was observed in captured output' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure did not use the neutral message"
! grep -Fq 'anonymous GitHub API quota exhausted' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure made a quota claim"
! grep -Fq "gh auth login" "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure named a quota remedy"
! grep -Fq 'GITHUB_TOKEN/GH_TOKEN' "${NEUTRAL_CASE}/human.log" \
    || fail "nonmatching configurator failure named a token remedy"
printf 'PASS: nonmatching configurator failure stays neutral\n'

DRY_RUN_CASE="$(run_case dry-run 0 yes generic 0 dry-run)"
! grep -Fq 'gentle-ai configurator_start:' "${DRY_RUN_CASE}/human.log" \
    || fail "dry run logged a configurator launch"
grep -Fq 'gentle-ai dry_run_note:' "${DRY_RUN_CASE}/human.log" \
    || fail "dry run did not log its note"
[[ "$(<"${DRY_RUN_CASE}/count")" == 0 ]] || fail "dry run invoked the configurator"
printf 'PASS: dry run does not claim to launch the configurator\n'

RECOVERED_SUMMARY_CASE="$(run_case recovered-summary 1 no rate-limit-once 0 recovered-summary)"
assert_steps_failed "${RECOVERED_SUMMARY_CASE}" 0
grep -Fq '"failed_step":"later_failure: Later module failed directly","return_code":7' "${RECOVERED_SUMMARY_CASE}/events.jsonl" \
    || fail "recovered summary kept the superseded configurator failure identity"
grep -Fq 'gentle-ai configurator_recovered:' "${RECOVERED_SUMMARY_CASE}/human.log" \
    || fail "recovered summary did not explain the retry recovery"
printf 'PASS: recovered retry leaves later direct failure in the run summary\n'

INTERRUPTED_SUMMARY_CASE="$(run_case interrupted-summary 1 no rate-limit-once 0 interrupted-summary)"
assert_steps_failed "${INTERRUPTED_SUMMARY_CASE}" 0
grep -Fq '"failed_step":"run_interrupted: Run interrupted by INT","return_code":130' "${INTERRUPTED_SUMMARY_CASE}/events.jsonl" \
    || fail "interrupted summary kept the superseded configurator failure identity"
printf 'PASS: recovered retry leaves interruption identity in the run summary\n'

RUN_CMD_SUMMARY_CASE="$(run_case later-run-cmd-failure 1 no rate-limit-once 0 run-cmd-summary)"
assert_steps_failed "${RUN_CMD_SUMMARY_CASE}" 1
grep -Fq '"name":"gentle-ai","status":"success"' "${RUN_CMD_SUMMARY_CASE}/events.jsonl" \
    || fail "run_cmd summary did not retain the recovered module"
grep -Fq '"name":"later","status":"failed","failed_step":"later-module ","return_code":7' "${RUN_CMD_SUMMARY_CASE}/events.jsonl" \
    || fail "run_cmd summary did not identify the later module failure"
printf 'PASS: recovered retry leaves later run_cmd failure in the run summary\n'
