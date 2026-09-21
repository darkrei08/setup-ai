#!/usr/bin/env bash

# ==============================================================================
# AI Dev Suite - Engineering Excellence Edition
# Version: 3.6.5
#
# Cross-platform (macOS + all major Linux distros) installer for an AI coding
# toolchain. Windows is handled by the sibling setup-ai.ps1; the Node launcher
# bin/setup-ai.mjs dispatches to the right script per OS and offers an
# interactive arrow-key module menu.
#
# Design:
#   - modular: every tool is its own mod_* function, driven by an ordered
#     registry; run a subset with --only, list them with --list.
#   - official, non-deprecated install method per OS for every tool.
#   - deterministic logging (human + JSONL), live command output, fail-fast with ERR diagnostics.
#
# Usage:
#   ./setup-ai.sh                 # install the core module set
#   ./setup-ai.sh --all           # every module (incl. optional GUI apps)
#   ./setup-ai.sh --only pi,codex,opencode
#   ./setup-ai.sh --yes           # never prompt: no interactive selectors
#   ./setup-ai.sh --dry-run       # report the plan without writing or installing
#   ./setup-ai.sh --list          # print modules and exit
#   ./setup-ai.sh --help
#   ./setup-ai.sh --verbose
#   ./setup-ai.sh --uninstall [--yes] [--purge] [--only <csv>]
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="3.6.5"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-dev-suite.XXXXXXXX")"
DRY_RUN="${DRY_RUN:-0}"
UNINSTALL=0
UNINSTALL_YES=0
UNINSTALL_PURGE=0
UNINSTALL_INCLUDE_SHELL=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=1 ;;
    esac
done
LOG_DIR="${SCRIPT_DIR}/logs"
if (( DRY_RUN == 1 )); then
    LOG_DIR="${TMP_DIR}/logs"
    export npm_config_cache="${TMP_DIR}/npm-cache"
fi
mkdir -p "${LOG_DIR}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
# RUN_ID is already a UTC timestamp: slice it instead of paying a second `date` call.
RUN_STARTED_AT="${RUN_ID:0:4}-${RUN_ID:4:2}-${RUN_ID:6:2}T${RUN_ID:9:2}:${RUN_ID:11:2}:${RUN_ID:13:2}Z"
RUN_STARTED_SECONDS="${SECONDS}"

HUMAN_LOG="${LOG_DIR}/setup_${RUN_ID}.log"
JSONL_LOG="${LOG_DIR}/setup_${RUN_ID}.jsonl"
REPORT_FILE="${LOG_DIR}/engineering-report_${RUN_ID}.md"

PI_STARTUP_PID=""
PI_STARTUP_WATCHDOG_PID=""

export RUN_ID

DEBUG="${DEBUG:-0}"
VERBOSE="${VERBOSE:-0}"
# --yes: never wait on a human. Vendor installers keep their own menus on a TTY,
# so the non-interactive value also changes which vendor path runs.
NONINTERACTIVE="${NONINTERACTIVE:-0}"
PI_WORKFLOW_VERSION="${PI_WORKFLOW_VERSION:-}"

DOTENV_REPO="${DOTENV_REPO:-https://github.com/darkrei08/dotenv.git}"

# Gentle AI ecosystem configurator installer (macOS/Linux). `gentle-ai install`
# is the interactive per-agent/per-IDE selector that also wires each agent's MCP
# servers, so the tools show up under /mcp.
GENTLE_AI_INSTALL="${GENTLE_AI_INSTALL:-https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh}"

ENGINEERING_EXCELLENCE_SLUG="${ENGINEERING_EXCELLENCE_SLUG:-darkrei08/Engineering-Excellence}"
ENGINEERING_EXCELLENCE_SKILL="engineering-excellence"

# Upstream agent-skill stack mirrored from darkrei08/dotenv setup_env.sh so the
# same skills land on every OS (dotenv itself is Linux-only). Each entry is
# "<source> <skill> [<skill>...]" installed via `npx skills add`.
UPSTREAM_SKILL_SOURCES=(
    "herdrdev/herdr herdr"
    "mattpocock/skills triage grill-me grilling wayfinder domain-modeling prototype research"
    "https://github.com/pedronauck/skills typescript-advanced"
    "humanlayer/skills show-me"
)
UPSTREAM_SKILL_NAMES=(herdr triage grill-me grilling wayfinder domain-modeling prototype research typescript-advanced show-me)

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_EXTENSIONS_DIR="${PI_AGENT_DIR}/extensions"
PI_NPM_DIR="${PI_AGENT_DIR}/npm"

# Where setup-ai clones/reads the dotenv checkout. Overridable so a machine that
# keeps its repos outside $HOME (e.g. on a data volume) can point at the existing
# checkout instead of cloning a duplicate. `git clone` is skipped when it exists.
DOTENV_DIR="${DOTENV_DIR:-${HOME}/git/personale/dotenv}"
DOTENV_EXT_DIR="${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows"

COCKPIT_REPO="jlcodes99/cockpit-tools"

# --- Pi packages: per-machine defaults, all overridable ------------------------
# Declarative manifest of extra Pi packages, one source per line
# (`npm:<pkg>[@<version>]`, `git:<host>/<owner>/<repo>[@<ref>]`, or a local path;
# `#` starts a comment). This is how a NEW machine gets every extension the
# toolchain needs without hand-editing ~/.pi/agent/settings.json.
#
# Where the manifest is read from follows the same split the dotenv repo uses: the Pi
# CONFIG (settings, package list) comes from the dotenv checkout, which setup_env.sh
# copies into the live ~/.pi/agent with a selective rsync (it is not a symlink), while
# the extensions themselves stay separate packages:
#   1. PI_PACKAGES_FILE, when set explicitly
#   2. <pi agent dir>/pi-packages.txt   (the dotenv/config repo)
#   3. <script dir>/pi-packages.txt     (a profile kept next to the installer)
# Nothing found is not an error: no extra packages are installed.
PI_PACKAGES_FILE="${PI_PACKAGES_FILE:-}"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

terminate_pi_startup_process_group() {
    local pid="${PI_STARTUP_PID:-}"
    [[ -n "${pid}" ]] || return 0
    if kill -TERM -- "-${pid}" 2>/dev/null; then :; else
        if kill -TERM "${pid}" 2>/dev/null; then :; fi
    fi
    sleep 1
    if kill -KILL -- "-${pid}" 2>/dev/null; then :; else
        if kill -KILL "${pid}" 2>/dev/null; then :; fi
    fi
}

cleanup() {
    if [[ -n "${PI_STARTUP_WATCHDOG_PID:-}" ]]; then
        if kill -TERM "${PI_STARTUP_WATCHDOG_PID}" 2>/dev/null; then :; fi
        if wait "${PI_STARTUP_WATCHDOG_PID}" 2>/dev/null; then :; fi
        PI_STARTUP_WATCHDOG_PID=""
    fi
    if [[ -n "${PI_STARTUP_PID:-}" ]]; then
        terminate_pi_startup_process_group
        if wait "${PI_STARTUP_PID}" 2>/dev/null; then :; fi
        PI_STARTUP_PID=""
    fi
    rm -rf -- "${TMP_DIR}"
}

# A run killed mid-module must not be written as a success: remember the signal so
# the exit trap can report `interrupted`, name the in-flight module as failed, and
# leave a non-zero exit code behind.
signal_exit_code() {
    case "$1" in
        HUP)  printf '1' ;;
        INT)  printf '2' ;;
        TERM) printf '15' ;;
        *)    printf '15' ;;
    esac
}

on_signal() {
    local signal="$1"
    RUN_INTERRUPTED=1
    INTERRUPT_SIGNAL="${signal}"
    INTERRUPT_RC=$(( 128 + $(signal_exit_code "${signal}") ))
    log_event "ERROR" "bootstrap" "run_interrupted" \
        "Run interrupted by ${signal}" "${INTERRUPT_RC}" \
        "signal=${signal};module=${CURRENT_MODULE:-none}"
    exit "${INTERRUPT_RC}"
}
trap 'on_signal HUP' HUP
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
# The run summary is written from the exit trap rather than from write_report: several
# failure paths end in a direct `exit` and never reach the ERR trap.
trap 'on_exit $?' EXIT

# ------------------------------------------------------------------------------
# JSON escaping without Python (works before Python is installed)
# ------------------------------------------------------------------------------

json_escape() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

json_log() {
    local timestamp="$1" level="$2" phase="$3" event="$4" message="$5"
    local return_code="${6:-0}" meta="${7:-}" extra="${8:-}"
    local optional="${9:-0}" behavior="${10:-}"

    local j_ts j_level j_phase j_event j_message j_meta j_behavior optional_json
    j_ts="$(json_escape "${timestamp}")"
    j_level="$(json_escape "${level}")"
    j_phase="$(json_escape "${phase}")"
    j_event="$(json_escape "${event}")"
    j_message="$(json_escape "${message}")"
    j_meta="$(json_escape "${meta}")"
    if [[ -z "${behavior}" ]]; then
        if (( optional == 1 )); then behavior="continue"; else behavior="abort"; fi
    fi
    j_behavior="$(json_escape "${behavior}")"
    optional_json="false"
    if (( optional == 1 )); then optional_json="true"; fi

    {
        printf '{"ts":"%s","lvl":"%s","ph":"%s","ev":"%s","msg":"%s","rc":%s,"rid":"%s","pid":%s' \
            "${j_ts}" "${j_level}" "${j_phase}" "${j_event}" "${j_message}" \
            "${return_code}" "${RUN_ID}" "$$"
        if [[ -n "${meta}" ]]; then
            printf ',"meta":"%s"' "${j_meta}"
        fi
        if [[ -n "${extra}" ]]; then
            # Pre-serialized object body, used by the terminal run summary record.
            printf ',"summary":%s' "${extra}"
        fi
        if (( return_code != 0 )); then
            printf ',"err":{"rc":%s,"optional":%s,"behavior":"%s"}' \
                "${return_code}" "${optional_json}" "${j_behavior}"
        fi
        printf '}\n'
    } >> "${JSONL_LOG}"
}

log_event() {
    local level="$1" phase="$2" event="$3" message="$4"
    local return_code="${5:-0}" meta="${6:-}" extra="${7:-}"
    local optional="${8:-0}" behavior="${9:-}"

    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    json_log "${timestamp}" "${level}" "${phase}" "${event}" "${message}" "${return_code}" "${meta}" "${extra}" "${optional}" "${behavior}"

    # First failure wins: later wrapper events (`script_failed`) only announce the failure
    # this one named, so they must not replace the root cause the summary falls back to.
    if [[ "${level}" == "ERROR" && -z "${LAST_ERROR_STEP}" ]]; then
        # Fallback diagnosis for the run summary when no step recorded the failure
        # itself (a module that exits directly, or a preflight check).
        LAST_ERROR_STEP="${event}: ${message}"
        LAST_ERROR_RC="${return_code}"
    fi

    local line="${timestamp} [${level}] ${phase} ${event}: ${message}"
    printf '%s\n' "${line}" >> "${HUMAN_LOG}"

    if (( VERBOSE == 1 )); then
        printf '\n[%s] %s / %s\n' "${level}" "${phase}" "${event}"
        printf '  %s\n' "${message}"
        if [[ -n "${meta}" ]]; then printf '  Details: %s\n' "${meta}"; fi
        if (( return_code != 0 )); then printf '  Return code: %s\n' "${return_code}"; fi
        return
    fi

    case "${level}" in
        INFO)  printf '\033[1;34m%s\033[0m\n' "${line}" ;;
        WARN)  printf '\033[1;33m%s\033[0m\n' "${line}" ;;
        ERROR) printf '\033[1;31m%s\033[0m\n' "${line}" ;;
        DEBUG) (( DEBUG == 1 )) && printf '\033[0;90m%s\033[0m\n' "${line}" ;;
        *)     printf '%s\n' "${line}" ;;
    esac
}

# ------------------------------------------------------------------------------
# Run summary state
#
# One `run_summary` record per run, built from the state below as the run progresses.
# Step counters are incremented by record_step from the command helpers; module
# outcomes come from run_module, plus the module (or phase) current at the failure.
# ------------------------------------------------------------------------------

SELECTED_MODULES=()
SELECTED_DISPLAY=""
CURRENT_MODULE=""
RUN_ACTIVE=0
MODULES_OK=""
DRY_RUN_PARTIAL=""
# Post-install steps a module cannot perform for the user (an interactive login, a
# token). They are printed with the closing summary so they are not buried in the log.
POST_INSTALL_ACTIONS=()
MODULE_INDEX=0
MODULE_TOTAL=0
STEP_INSTALLED=0
STEP_VERIFIED=0
STEP_SKIPPED=0
STEP_PLANNED=0
STEP_FAILED=0
STEP_FAIL_STEP=""
STEP_FAIL_RC=0
LAST_ERROR_STEP=""
LAST_ERROR_RC=0
RUN_INTERRUPTED=0
INTERRUPT_SIGNAL=""
INTERRUPT_RC=0
SUMMARY_WRITTEN=0

# Space-delimited on purpose: a plain string keeps the empty case safe under
# `set -u` on the bash 3.2 that macOS ships. Module names never contain spaces.
module_succeeded() {
    [[ " ${MODULES_OK} " == *" $1 "* ]]
}

# One machine-readable outcome per executed step, so the summary is counted from the
# run itself instead of by re-parsing the log. status: installed|verified|skipped|failed.
record_step() {
    local phase="$1" status="$2" return_code="$3" step="$4" level="INFO" optional=0 behavior="abort"
    if [[ "${status}" == "skipped" ]]; then
        optional=1
        behavior="continue"
    fi
    case "${status}" in
        installed) STEP_INSTALLED=$(( STEP_INSTALLED + 1 )) ;;
        verified)  STEP_VERIFIED=$(( STEP_VERIFIED + 1 )) ;;
        skipped)   STEP_SKIPPED=$(( STEP_SKIPPED + 1 )); level="WARN" ;;
        planned)
            # Counted from a file, not a variable: most planned steps are recorded inside
            # the per-module subshell of the dry-run walk, where a counter would be lost.
            if (( DRY_RUN == 1 )); then
                printf '1\n' >> "${TMP_DIR}/planned_steps"
            fi
            ;;
        failed)
            STEP_FAILED=$(( STEP_FAILED + 1 ))
            level="ERROR"
            STEP_FAIL_STEP="${step}"
            STEP_FAIL_RC="${return_code}"
            ;;
    esac
    log_event "${level}" "${phase}" "step_result" "Step ${status}" "${return_code}" \
        "step=${step};module=${CURRENT_MODULE};status=${status}" "" "${optional}" "${behavior}"
}

# Terminal record for the run, emitted once from the exit trap so a failed run
# reports why it failed regardless of the path it left through.
write_run_summary() {
    local rc="${1:-0}"
    if (( DRY_RUN == 1 )) && [[ -f "${TMP_DIR}/planned_steps" ]]; then
        local planned_steps=0 planned_entry
        while IFS= read -r planned_entry; do
            planned_steps=$(( planned_steps + 1 ))
        done < "${TMP_DIR}/planned_steps"
        STEP_PLANNED="${planned_steps}"
    fi
    # `--list` and `--help` exit inside parse_args: they are queries, not runs.
    (( RUN_ACTIVE == 1 )) || return 0
    (( SUMMARY_WRITTEN == 1 )) && return 0
    SUMMARY_WRITTEN=1

    local outcome="success" level="INFO"
    if (( rc != 0 )); then
        outcome="failed"
        level="ERROR"
    fi
    if (( RUN_INTERRUPTED == 1 )); then
        outcome="interrupted"
        level="ERROR"
    elif (( DRY_RUN == 1 && rc == 0 )); then
        outcome="dry-run"
    fi

    # A summary with a missing timestamp is worse than one that repeats the start time,
    # and the duration comes from the shell's own clock, so neither needs a helper.
    local ended_at duration
    ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || ended_at="${RUN_STARTED_AT}"
    duration=$(( SECONDS - RUN_STARTED_SECONDS ))
    (( duration < 0 )) && duration=0

    # A failed step names itself; anything else falls back to the last ERROR record.
    local failed_step="${STEP_FAIL_STEP}" failed_rc="${STEP_FAIL_RC}"
    if [[ -z "${failed_step}" ]]; then
        failed_step="${LAST_ERROR_STEP}"
        failed_rc="${LAST_ERROR_RC}"
    fi
    if (( RUN_INTERRUPTED == 1 )); then
        [[ -n "${failed_step}" ]] || failed_step="run_interrupted:${INTERRUPT_SIGNAL}"
        (( INTERRUPT_RC > 0 )) && failed_rc="${INTERRUPT_RC}"
    fi
    (( failed_rc > 0 )) || failed_rc=1

    local -a module_names=()
    if (( ${#SELECTED_MODULES[@]} > 0 )); then
        module_names=("${SELECTED_MODULES[@]}")
    fi
    if [[ ( "${outcome}" == "failed" || "${outcome}" == "interrupted" ) && -n "${CURRENT_MODULE}" ]] \
        && ! is_selected "${CURRENT_MODULE}"; then
        # A gate or the shell environment can fail outside any selected module.
        module_names+=("${CURRENT_MODULE}")
    fi

    local m status entry modules_json="" m_success=0 m_failed=0 m_skipped=0
    local -a report_lines=("## Run summary" "" "- Run ID: \`${RUN_ID}\`" "- Outcome: ${outcome}")
    report_lines+=("- Started: ${RUN_STARTED_AT}")
    report_lines+=("- Ended: ${ended_at} (${duration}s)")
    for m in "${module_names[@]}"; do
        if module_succeeded "${m}"; then
            status="success"; m_success=$(( m_success + 1 ))
        elif [[ "${outcome}" != "success" && "${m}" == "${CURRENT_MODULE}" ]]; then
            status="failed"; m_failed=$(( m_failed + 1 ))
        else
            status="skipped"; m_skipped=$(( m_skipped + 1 ))
        fi
        entry="{\"name\":\"$(json_escape "${m}")\",\"status\":\"${status}\""
        if [[ "${status}" == "failed" ]]; then
            entry="${entry},\"failed_step\":\"$(json_escape "${failed_step}")\",\"return_code\":${failed_rc}}"
            report_lines+=("- Module \`${m}\`: failed at \`${failed_step}\` (return code ${failed_rc})")
        else
            entry="${entry}}"
            report_lines+=("- Module \`${m}\`: ${status}")
        fi
        modules_json="${modules_json}${modules_json:+,}${entry}"
    done
    report_lines+=("- Steps: ${STEP_INSTALLED} installed, ${STEP_VERIFIED} verified, ${STEP_SKIPPED} skipped, ${STEP_PLANNED} planned, ${STEP_FAILED} failed")

    local message="Run summary: outcome=${outcome};duration_seconds=${duration}"
    message="${message};modules_success=${m_success};modules_failed=${m_failed};modules_skipped=${m_skipped}"
    message="${message};steps_installed=${STEP_INSTALLED};steps_verified=${STEP_VERIFIED}"
    message="${message};steps_skipped=${STEP_SKIPPED};steps_planned=${STEP_PLANNED};steps_failed=${STEP_FAILED}"
    if [[ "${outcome}" == "failed" ]]; then
        message="${message};failed_step=${failed_step};return_code=${failed_rc}"
    fi
    if (( RUN_INTERRUPTED == 1 )); then
        message="${message};interrupted=true;signal=${INTERRUPT_SIGNAL}"
        report_lines+=("- Interrupted by: ${INTERRUPT_SIGNAL}")
    fi

    # A run that failed before write_report still ends with a report, as it does in
    # setup-ai.ps1, and the summary is what it has to carry.
    if [[ ! -f "${REPORT_FILE}" ]]; then
        printf '# AI Dev Suite - Engineering Report\n' > "${REPORT_FILE}"
    fi
    printf '\n' >> "${REPORT_FILE}"
    printf '%s\n' "${report_lines[@]}" >> "${REPORT_FILE}"

    log_event "${level}" "bootstrap" "run_summary" "${message}" "${rc}" "" \
        "$(printf '{"run_id":"%s","outcome":"%s","started_at":"%s","ended_at":"%s","duration_seconds":%s,"modules":[%s],"steps":{"installed":%s,"verified":%s,"skipped":%s,"planned":%s,"failed":%s}}' \
            "$(json_escape "${RUN_ID}")" "${outcome}" "${RUN_STARTED_AT}" "${ended_at}" \
            "${duration}" "${modules_json}" "${STEP_INSTALLED}" "${STEP_VERIFIED}" \
            "${STEP_SKIPPED}" "${STEP_PLANNED}" "${STEP_FAILED}")"
}

on_exit() {
    local rc="${1:-0}"
    write_run_summary "${rc}"
    cleanup
}

# ------------------------------------------------------------------------------
# Failure diagnostics
# ------------------------------------------------------------------------------

on_error() {
    local rc=$?
    local line="${BASH_LINENO[0]:-unknown}"
    local source_file="${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-unknown}}"
    local function_name="${FUNCNAME[1]:-main}"
    local command="${BASH_COMMAND:-unknown}"

    log_event "ERROR" "bootstrap" "script_failed" "Setup failed" "${rc}" \
        "line=${line};file=${source_file};function=${function_name};command=${command}"

    write_report "FAILED" "${rc}" "${line}" "${source_file}" "${function_name}" "${command}"

    printf '\n\033[1;31mSETUP FALLITO\033[0m\n'
    printf 'Return code : %s\n' "${rc}"
    printf 'File        : %s\n' "${source_file}"
    printf 'Function    : %s\n' "${function_name}"
    printf 'Line        : %s\n' "${line}"
    printf 'Command     : %s\n' "${command}"
    printf 'Human log   : %s\n' "${HUMAN_LOG}"
    printf 'JSONL log   : %s\n' "${JSONL_LOG}"
    printf 'Report      : %s\n\n' "${REPORT_FILE}"

    exit "${rc}"
}
trap 'on_error' ERR

# ------------------------------------------------------------------------------
# Command helpers
# ------------------------------------------------------------------------------

section() {
    local title="$1"
    log_event "INFO" "section" "start" "${title}"
    printf '\n\033[1;36m======================================================================\033[0m\n'
    printf '\033[1;36m  %s\033[0m\n' "${title}"
    printf '\033[1;36m======================================================================\033[0m\n\n'
}

require_command() {
    local command="$1"
    if ! command -v "${command}" >/dev/null 2>&1; then
        # A dry run plans a run that has not happened yet, so a command an earlier
        # step would install is not a failure: report it and let the module reach the
        # commands that make up the plan. Nothing runs, so this cannot hide a break.
        if (( DRY_RUN == 1 )); then
            log_event "INFO" "preflight" "dry_run_command_missing" \
                "Command not installed yet; the plan assumes an earlier step provides it (dry run)" 0 \
                "command=${command}"
            return 0
        fi
        log_event "ERROR" "preflight" "missing_command" "Required command not found: ${command}" 127
        return 127
    fi
}

github_api_token() {
    local token="${GITHUB_TOKEN:-}"
    if [[ -z "${token}" ]] && command -v gh >/dev/null 2>&1; then
        token="$(gh auth token 2>/dev/null)" || token=""
    fi
    printf '%s' "${token}"
}

# Run a command. --verify marks a read-back whose success is counted as verification
# rather than as an install; --optional marks one whose failure the caller recovers from.
# Both keep the command's own events and its return code, and mirror -Verify / -Optional
# on Invoke-Step in setup-ai.ps1.
run_cmd() {
    local phase="$1"; shift
    local optional=0 verify=0
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --optional) optional=1 ;;
            --verify)   verify=1 ;;
            *)          break ;;
        esac
        shift
    done
    local display; printf -v display '%q ' "$@"
    local start_event="command_start" finish_event="command_success" fail_event="command_failed"
    local start_message="Executing command" finish_message="Command completed"
    local fail_message="Command returned non-zero status" level="ERROR" status="failed" ok_status="installed"
    local failure_behavior="abort"
    if (( DRY_RUN == 1 )); then
        log_event "INFO" "${phase}" "dry_run_command" "Command not run (dry run)" 0 "${display}"
        printf '  \033[1;35m[dry-run] would run: %s\033[0m\n' "${display}"
        record_step "${phase}" "planned" 0 "${display}"
        return 0
    fi
    if (( verify == 1 )); then
        ok_status="verified"
    fi
    if (( optional == 1 )); then
        start_event="optional_command_start"; finish_event="optional_command_success"
        fail_event="optional_command_failed"; start_message="Executing optional command"
        finish_message="Optional command completed"
        fail_message="Optional command failed; continuing"; level="WARN"; status="skipped"
        failure_behavior="continue"
    fi
    log_event "INFO" "${phase}" "${start_event}" "${start_message}" 0 "${display}"
    printf '  Command: %s\n' "${display}"
    printf '  \033[1;35mLive output follows. Prompts, including sudo, appear here.\033[0m\n\n'

    local stream="${TMP_DIR}/command_${RANDOM}.fifo" rc=0 tee_rc=0 tee_pid
    # Keep the command in the current shell so functions such as `nvm use` can
    # update PATH. A FIFO lets tee stream output without putting the command in
    # a pipeline subshell, and wait makes logging deterministic before returning.
    if ! mkfifo "${stream}"; then
        log_event "ERROR" "${phase}" "output_stream_failed" "Could not create the command output stream" 1 "path=${stream}" "" "${optional}" "${failure_behavior}"
        record_step "${phase}" "${status}" 1 "${display}"
        return 1
    fi
    tee -a "${HUMAN_LOG}" < "${stream}" &
    tee_pid=$!
    if "$@" >"${stream}" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    if wait "${tee_pid}"; then
        tee_rc=0
    else
        tee_rc=$?
    fi
    rm -f -- "${stream}" || log_event "WARN" "${phase}" "output_stream_cleanup_failed" "Could not remove the command output stream" 0 "path=${stream}"
    if (( rc == 0 && tee_rc != 0 )); then rc="${tee_rc}"; fi
    printf '\n'

    if (( rc == 0 )); then
        log_event "INFO" "${phase}" "${finish_event}" "${finish_message}" 0 "${display}"
        record_step "${phase}" "${ok_status}" 0 "${display}"
        return 0
    fi
    log_event "${level}" "${phase}" "${fail_event}" "${fail_message}" "${rc}" "${display}" "" "${optional}" "${failure_behavior}"
    record_step "${phase}" "${status}" "${rc}" "${display}"
    return "${rc}"
}

# An effect the command choke points cannot see: a file a module creates or edits
# directly, or an action it takes on its own. In --dry-run it is reported, never
# performed: a dry run that writes is a lie, so every direct effect goes through
# this one guard.
dry_run_note() {
    log_event "INFO" "${1:-bootstrap}" "dry_run_note" "Not performed (dry run)" 0 "${2:-}"
    printf '  \033[1;35m[dry-run] would do: %s\033[0m\n' "${2:-}"
}

# Run a command whose failure the run ignores: the status is deliberately dropped (this
# helper has no fallback to choose), so run_cmd keeps the single implementation.
run_optional() {
    local phase="$1"; shift
    run_cmd "${phase}" --optional "$@" || :
    return 0
}

# Run a vendor installer that decides interactivity from the controlling
# terminal, not from flags (pi.dev writes state via raw keypress menus).
# setsid detaches /dev/tty, so the installer takes its documented no-TTY
# defaults instead of blocking an unattended run. macOS has no setsid; python3
# (installed by the base module) calls setsid before exec there.
run_vendor_installer() {
    local phase="$1" interpreter="$2" script="$3"
    if command -v setsid >/dev/null 2>&1; then
        run_cmd "${phase}" setsid --wait "${interpreter}" "${script}"
    elif command -v python3 >/dev/null 2>&1; then
        run_cmd "${phase}" python3 -c '
import os, sys
if hasattr(os, "setsid"):
    try:
        os.setsid()
    except OSError:
        pass
os.execvp(sys.argv[1], sys.argv[1:])
' "${interpreter}" "${script}"
    else
        run_cmd "${phase}" "${interpreter}" "${script}"
    fi
}

capture_cmd() {
    local output_var="$1" phase="$2"; shift 2
    # --optional marks a readback the caller tolerates: its failure is the `skipped`
    # outcome, matching what -Optional means for Invoke-Step in setup-ai.ps1.
    local optional=0
    if [[ "${1:-}" == "--optional" ]]; then
        optional=1
        shift
    fi
    local display; printf -v display '%q ' "$@"
    # Keep stdout as the captured scalar; stderr stays visible and logged but must
    # not contaminate the value (e.g. `npm view ... version` prints warnings on
    # stderr that would otherwise corrupt a version readback on Debian's npm 12).
    local capture_id="${RANDOM}"
    local out_file="${TMP_DIR}/capture_${capture_id}.out" err_file="${TMP_DIR}/capture_${capture_id}.err" rc=0 line
    local failure_behavior="abort"
    if (( optional == 1 )); then failure_behavior="continue"; fi
    log_event "INFO" "${phase}" "capture_start" "Collecting command output" 0 "${display}"
    "$@" >"${out_file}" 2>"${err_file}" || rc=$?
    cat "${out_file}" "${err_file}" >> "${HUMAN_LOG}"
    if (( VERBOSE == 1 )); then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            printf '    %s\n' "${line}"
        done < <(cat "${out_file}" "${err_file}")
    else
        cat "${out_file}" "${err_file}"
    fi
    if (( rc != 0 )); then
        if (( optional == 1 )); then
            # A tolerated readback is a warning, never an error the run did not take:
            # the caller falls back and the step is counted as skipped.
            log_event "WARN" "${phase}" "optional_capture_failed" \
                "Optional command failed while collecting output; continuing" "${rc}" "${display}" "" "${optional}" "${failure_behavior}"
            record_step "${phase}" "skipped" "${rc}" "${display}"
        else
            log_event "ERROR" "${phase}" "capture_failed" "Command failed while collecting output" "${rc}" "${display}" "" "${optional}" "${failure_behavior}"
            record_step "${phase}" "failed" "${rc}" "${display}"
        fi
        return "${rc}"
    fi
    printf -v "${output_var}" '%s' "$(cat "${out_file}")"
    log_event "INFO" "${phase}" "capture_success" "Output captured" 0 "${display}"
    record_step "${phase}" "verified" 0 "${display}"
}

# Run a `grep` probe that distinguishes "no match" from a real failure.
# Writes matching lines to ${out_file}. Returns 0 when matches were found,
# 1 when there were none (grep exit 1), and hard-fails on any operational
# error (grep exit >1, e.g. an unreadable file) instead of hiding it.
grep_probe() {
    local phase="$1" out_file="$2"; shift 2
    local rc=0
    grep "$@" >"${out_file}" 2>>"${HUMAN_LOG}" || rc=$?
    case "${rc}" in
        0) return 0 ;;
        1) return 1 ;;
        *)
            log_event "ERROR" "${phase}" "grep_probe_failed" \
                "grep probe failed with an operational error" "${rc}" "args=$*"
            exit "${rc}"
            ;;
    esac
}

report_version() {
    local output_var="$1" command_name="$2"; shift 2
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf -v "${output_var}" '%s' "n/a"
        return 0
    fi
    if ! capture_cmd "${output_var}" "report" --optional "${command_name}" "$@"; then
        printf -v "${output_var}" '%s' "n/a"
        log_event "WARN" "report" "version_unavailable" \
            "Could not read command version" 0 "command=${command_name}"
    fi
}

write_report() {
    local status="$1" rc="$2" line="${3:-n/a}" file="${4:-n/a}"
    local function_name="${5:-n/a}" command="${6:-n/a}"

    cat > "${REPORT_FILE}" <<EOF
# AI Dev Suite - Engineering Report

**Status:** ${status}
**Script version:** ${SCRIPT_VERSION}
**Run ID:** ${RUN_ID}
**Exit code:** ${rc}
**OS family:** ${OS_FAMILY:-unknown}
**Selected modules:** ${SELECTED_DISPLAY:-<default>}

## Failure diagnostics

- File: \`${file}\`
- Function: \`${function_name}\`
- Line: \`${line}\`
- Command: \`${command}\`

## Artifacts

- Human log: \`${HUMAN_LOG}\`
- JSONL log: \`${JSONL_LOG}\`
- Report: \`${REPORT_FILE}\`
EOF
}

# ==============================================================================
# Module registry
#
# ORDER matters (dependencies first). Each name maps to a mod_<name> function
# and a human description. DEFAULT_MODULES is the "core" set used when no
# --only/--all is given; OPTIONAL_MODULES (GUI apps etc.) are only installed
# via --all or an explicit --only.
# gentle-ai comes after the agent CLIs it configures: its installer fails with
# "install OpenCode Gentle Logo plugin: OpenCode runtime version unavailable or
# unsupported" when a runtime it targets is still absent.
# ==============================================================================

MODULE_ORDER=(base node bun pi dotenv pi-packages go ee skills pi-workflows herdr codex antigravity opencode gentle-ai cockpit rotator)

module_desc() {
    case "$1" in
        base) printf '%s\n' "System packages (build tools, git, gh, python, neovim, jq, imagemagick, go, clipboard)" ;;
        node) printf '%s\n' "Node.js v22 + npm@latest (nvm on Unix, winget on Windows)" ;;
        bun) printf '%s\n' "Bun runtime" ;;
        pi) printf '%s\n' "pi.dev coding agent CLI" ;;
        pi-packages) printf '%s\n' "Extra Pi packages from a declarative manifest (pi-packages.txt)" ;;
        go) printf '%s\n' "Go toolchain" ;;
        dotenv) printf '%s\n' "darkrei08/dotenv dotfiles (Linux only: clones + runs setup_env.sh)" ;;
        ee) printf '%s\n' "Engineering Excellence skill (npx skills add, all detected agents)" ;;
        skills) printf '%s\n' "Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add" ;;
        pi-workflows) printf '%s\n' "pi-extensible-workflows (published release + npm 12 remote sources for pi installs)" ;;
        herdr) printf '%s\n' "herdr terminal multiplexer" ;;
        gentle-ai) printf '%s\n' "gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi" ;;
        codex) printf '%s\n' "OpenAI Codex CLI" ;;
        antigravity) printf '%s\n' "Google Antigravity CLI (agy)" ;;
        opencode) printf '%s\n' "opencode agent CLI (opencode-ai)" ;;
        cockpit) printf '%s\n' "cockpit-tools desktop GUI app (optional, CC BY-NC-SA)" ;;
        rotator) printf '%s\n' "tuxevil-rotator multi-account Gemini/Antigravity gateway (installed and started in the background; optional, opt-in)" ;;
        *) return 1 ;;
    esac
}

module_is_optional() {
    [[ "$1" == "cockpit" || "$1" == "rotator" ]]
}

# ------------------------------------------------------------------------------
# OS / package-manager detection
# ------------------------------------------------------------------------------

OS_FAMILY=""
PM=""
DISTRO_ID=""
DISTRO_LIKE=""

# WSL2 appends the Windows PATH (/mnt/c/...) to the Linux one, so `node`, `npm` and
# `pi` can silently resolve to the Windows binaries and write to the Windows
# profile. setup-ai is a Linux-native run: drop every interop entry before a
# module resolves a command, so the two environments cannot overlap. Windows
# keeps its own installer (setup-ai.ps1); this guard never changes /etc/wsl.conf.
is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -r /proc/version ]] || return 1
    grep -qi microsoft /proc/version
}

strip_windows_interop_path() {
    local -a parts kept=()
    local entry
    IFS=':' read -r -a parts <<< "${PATH}"
    for entry in "${parts[@]}"; do
        [[ "${entry}" == /mnt/* ]] && continue
        kept+=("${entry}")
    done
    local IFS=':'
    PATH="${kept[*]}"
    export PATH

    # Verify the loaded value, not the write we intended: a survivor would mean the
    # Windows binaries are still reachable after the strip claimed otherwise.
    local remaining=""
    IFS=':' read -r -a parts <<< "${PATH}"
    for entry in "${parts[@]}"; do
        [[ "${entry}" == /mnt/* ]] && remaining="${remaining}${remaining:+,}${entry}"
    done
    if [[ -n "${remaining}" ]]; then
        log_event "ERROR" "preflight" "wsl_interop_path_unstripped" \
            "Windows interop entries survived the PATH rewrite" 1 "entries=${remaining}"
        return 1
    fi
    return 0
}

detect_os() {
    local uname_s
    uname_s="$(uname -s)"

    case "${uname_s}" in
        Darwin)
            OS_FAMILY="macos"
            if ! command -v brew >/dev/null 2>&1; then
                log_event "ERROR" "preflight" "brew_missing" \
                    "Homebrew is required on macOS. Install from https://brew.sh then re-run." 1
                exit 1
            fi
            PM="brew"
            ;;
        Linux)
            OS_FAMILY="linux"
            if [[ -f /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                DISTRO_ID="${ID:-unknown}"
                DISTRO_LIKE="${ID_LIKE:-}"
            else
                log_event "ERROR" "preflight" "os_detection_failed" "/etc/os-release not found" 1
                exit 1
            fi
            case "${DISTRO_ID}" in
                debian|ubuntu|linuxmint|pop)          PM="apt-get" ;;
                fedora|rhel|centos|rocky|almalinux)   PM="dnf" ;;
                arch|manjaro|endeavouros|omarchy)     PM="pacman" ;;
                opensuse*|sles)                       PM="zypper" ;;
                *)
                    if [[ "${DISTRO_LIKE}" == *debian* ]]; then PM="apt-get"
                    elif [[ "${DISTRO_LIKE}" == *fedora* || "${DISTRO_LIKE}" == *rhel* ]]; then PM="dnf"
                    elif [[ "${DISTRO_LIKE}" == *arch* ]]; then PM="pacman"
                    elif [[ "${DISTRO_LIKE}" == *suse* ]]; then PM="zypper"
                    else
                        log_event "ERROR" "preflight" "unsupported_distribution" \
                            "Unsupported Linux distribution: ${DISTRO_ID}" 1
                        exit 1
                    fi
                    ;;
            esac
            ;;
        *)
            log_event "ERROR" "preflight" "unsupported_os" \
                "Unsupported OS: ${uname_s}. On Windows use setup-ai.ps1." 1
            exit 1
            ;;
    esac

    log_event "INFO" "preflight" "os_detected" "OS detected" 0 \
        "family=${OS_FAMILY};pm=${PM};distro=${DISTRO_ID};like=${DISTRO_LIKE}"
}

# ==============================================================================
# Pi install roots
#
# Concept: pi reads packages from TWO user-scope npm roots, and both must hold
# the same build or one silently shadows the other.
#
#   <agentDir>/npm         managed root: what `pi install` and
#                          `pi update --extensions` write and load
#   <agentDir>/extensions  shared resolution root: what setup-ai installs into so
#                          extension code can `import` these packages
#
# Every write into those roots goes through the helpers below, so npm behavior and
# artifact verification live in one place instead of being duplicated per module.
# ==============================================================================

# npm 12 turns URL/tarball ("remote") sources off by default and aborts with
# EALLOWREMOTE. pi runs its managed installs as
# `npm install <spec> --prefix <agentDir>/npm --legacy-peer-deps`, and npm resolves
# its local .npmrc from the prefix it is given, so the opt-in belongs in the
# install root itself - never globally, never in the caller's cwd.
# npm < 12 does not know the key, so it is only written when npm >= 12.
ensure_npm_remote_sources() {
    local dir="$1" phase="pi-npm"
    local npmrc="${dir}/.npmrc"

    if (( DRY_RUN == 1 )); then
        dry_run_note "${phase}" "${dir}/.npmrc + ${dir}/package.json"
        return 0
    fi
    mkdir -p "${dir}"
    # Mark the directory as an npm project root, so this helper can never make npm
    # walk up into an ancestor project.
    if [[ ! -f "${dir}/package.json" ]]; then
        printf '%s\n' '{"name":"pi-extensions","private":true}' > "${dir}/package.json"
    fi

    if ! command -v npm >/dev/null 2>&1; then
        log_event "WARN" "${phase}" "npm_missing" \
            "npm is unavailable; remote-source opt-in was not written" 0 "dir=${dir}"
        return 0
    fi

    local npm_version npm_major
    if ! capture_cmd npm_version "${phase}" --optional npm --version; then
        log_event "WARN" "${phase}" "npm_version_unavailable" \
            "Could not read the npm version; remote-source opt-in was not written" 0 "dir=${dir}"
        return 0
    fi
    npm_major="${npm_version%%.*}"
    if [[ ! "${npm_major}" =~ ^[0-9]+$ ]]; then
        log_event "WARN" "${phase}" "npm_version_unparsed" \
            "Could not parse the npm version; remote-source opt-in was not written" 0 \
            "version=${npm_version}"
        return 0
    fi

    if (( npm_major < 12 )); then
        log_event "INFO" "${phase}" "remote_sources_default" \
            "npm ${npm_version} fetches remote sources by default; no opt-in needed" 0 \
            "npmrc=${npmrc}"
        return 0
    fi

    # Append-only: an existing .npmrc belongs to the user and may hold other keys.
    # npm 12 gates URL/tarball AND git sources separately (allow-remote, allow-git), and
    # pi's managed installs must be able to fetch a package that depends on either.
    #
    # allow-scripts is the policy that has to survive `pi update --extensions`: an
    # approval written into package.json's allowScripts field is lost the next time pi
    # rewrites that file, and the blocked scripts come back as "pending" (observed on
    # a host whose gentle-pi postinstall had already been approved once). npm reads the
    # policy from .npmrc as well, and pi does not own that file.
    local key
    for key in 'allow-remote=all' 'allow-git=all' \
        "allow-scripts=$(IFS=,; printf '%s' "${NPM12_INSTALL_SCRIPT_PACKAGES[*]}")"; do
        if ! grep -qxF "${key}" "${npmrc}" 2>/dev/null; then
            printf '%s\n' "${key}" >> "${npmrc}"
        fi
    done

    # Verify the file npm will actually read, not the write we intended.
    for key in 'allow-remote=all' 'allow-git=all' \
        "allow-scripts=$(IFS=,; printf '%s' "${NPM12_INSTALL_SCRIPT_PACKAGES[*]}")"; do
        if ! grep -qxF "${key}" "${npmrc}" 2>/dev/null; then
            log_event "ERROR" "${phase}" "remote_sources_unverified" \
                "Could not enable npm 12 sources; pi install/update would fail with EALLOWREMOTE" 1 \
                "npmrc=${npmrc};missing=${key}"
            return 1
        fi
    done
    log_event "INFO" "${phase}" "remote_sources_enabled" \
        "npm ${npm_version} remote (URL/tarball) sources enabled for this install root" 0 \
        "npmrc=${npmrc}"
}

# npm 12 blocks a dependency's install scripts until that package is explicitly
# approved, and `pi install` runs a plain `npm install` with no post-processing, so
# a blocked script never runs on a fresh machine. gentle-pi's postinstall is the
# load-bearing one: it installs the package-local gentle-ai review binary the `gga`
# gate uses; node-pty and pi-tool-display ship install scripts too.
#
# This is deliberately a post-install pass and NOT part of
# ensure_npm_remote_sources: `npm install-scripts approve` only accepts an
# INSTALLED package (it exits ENOMATCH otherwise) and the npm-root helper runs
# before the first package exists, so on a fresh machine an approval there would be
# a silent no-op. The installer calls this once after the modules that install pi
# packages.
#
# Idempotent: every present target is approved and then rebuilt, and npm must
# report none of them pending afterwards, so the end state is the same on every run
# - and a build that failed on a previous run is retried. Approval is by NAME, not
# npm's default <pkg>@<version> pin: pi updates packages on its own (`pi update
# --extensions`), and a pinned entry stops covering the new version, re-blocking the
# script and silently removing what it installs (gentle-pi's review binary) until
# this pass runs again. An absent package and an npm without `install-scripts` are
# skips, never failures.
NPM12_INSTALL_SCRIPT_PACKAGES=(gentle-pi node-pty pi-tool-display)

# Print the comma-separated subset of "$@" that npm still reports as pending
# (unreviewed) install scripts for the project at $1. Returns 1 when npm's state
# cannot be read, so the caller decides whether that is fatal.
npm_pending_install_scripts() {
    local dir="$1"; shift
    local state_file="${TMP_DIR}/install_scripts_${RANDOM}.json" rc=0
    # stderr goes to the human log, not into the JSON the parser reads.
    npm install-scripts ls --json --prefix "${dir}" >"${state_file}" 2>>"${HUMAN_LOG}" || rc=$?
    if (( rc != 0 )); then
        return 1
    fi
    if ! node -e '
        const fs = require("node:fs");
        const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const want = new Set(process.argv.slice(2));
        const pending = (data.allowScripts ?? [])
            .filter((entry) => (entry.changes ?? []).some((change) => change.change === "pending"))
            .map((entry) => entry.name)
            .filter((name) => want.has(name));
        process.stdout.write(pending.join(","));
    ' "${state_file}" "$@"; then
        return 1
    fi
}

approve_npm_install_scripts() {
    local dir="$1" phase="${2:-pi-npm}"
    local pkg_json="${dir}/package.json"

    if (( DRY_RUN == 1 )); then
        dry_run_note "${phase}" "${dir}/node_modules (npm install-scripts approval)"
        return 0
    fi
    # No project here means no pi package was ever installed into this root.
    if [[ ! -f "${pkg_json}" ]]; then
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        log_event "WARN" "${phase}" "npm_missing" \
            "npm is unavailable; dependency install scripts cannot be approved" 0 "dir=${dir}"
        return 0
    fi
    # Probe the subcommand instead of trusting a version number: npm < 12, and any
    # other package manager pi can be configured with, does not implement it.
    if ! npm install-scripts --help >/dev/null 2>&1; then
        log_event "INFO" "${phase}" "install_scripts_unsupported" \
            "This npm does not implement install-scripts; dependency install-script approval skipped" 0 \
            "dir=${dir}"
        return 0
    fi

    # The packages whose blocked install scripts the toolchain depends on; one that
    # is not installed in this root is a skip, never an error.
    local -a present=()
    local pkg
    for pkg in "${NPM12_INSTALL_SCRIPT_PACKAGES[@]}"; do
        [[ -f "${dir}/node_modules/${pkg}/package.json" ]] && present+=("${pkg}")
    done
    if (( ${#present[@]} == 0 )); then
        log_event "INFO" "${phase}" "install_scripts_none_installed" \
            "None of the install-script packages are installed; nothing to approve" 0 "dir=${dir}"
        return 0
    fi

    # Approve every installed target and THEN run its script: approval alone does
    # not re-run a script that was blocked at install time (npm treats the package
    # as already installed), and skipping that would make a failed build permanent.
    # Re-running it is idempotent.
    for pkg in "${present[@]}"; do
        # Approval is a policy change and stays optional: a package that refuses it is
        # still covered by the rebuild check below.
        # --no-allow-scripts-pin approves the package by name, so the policy keeps
        # covering the versions pi installs later; npm collapses an existing pinned
        # entry for the same package into it.
        run_optional "${phase}" npm install-scripts approve --no-allow-scripts-pin "${pkg}" --prefix "${dir}"
        # The rebuild is load-bearing: a blocked postinstall can be the step that
        # installs a required artifact (gentle-pi ships its review binary this way), so
        # a failure here fails the run instead of degrading to a warning.
        # --foreground-scripts keeps build output and errors in the log.
        run_cmd "${phase}" npm rebuild "${pkg}" --foreground-scripts --prefix "${dir}"
    done

    # An exit code is not proof that the artifact exists, so the load-bearing one is
    # read from disk: gentle-pi's postinstall is what installs the review binary.
    local review_binary=""
    if [[ -d "${dir}/node_modules/gentle-pi" ]]; then
        if ! review_binary="$(find "${dir}/node_modules/gentle-pi/.gentle-ai" -type f -name 'gentle-ai*' -print -quit 2>/dev/null)"; then
            review_binary=""
        fi
        if [[ -z "${review_binary}" ]]; then
            log_event "ERROR" "${phase}" "review_binary_missing" \
                "gentle-pi review binary missing after its install scripts ran" 1 \
                "dir=${dir};expected=${dir}/node_modules/gentle-pi/.gentle-ai/*/gentle-ai*"
            return 1
        fi
        log_event "INFO" "${phase}" "review_binary_verified" \
            "gentle-pi review binary present after the rebuild" 0 "binary=${review_binary}"
    fi

    # Verify by re-reading npm's own state: nothing we approved may still be
    # pending. A present package without install scripts never appears here.
    local pending_csv="" rc=0
    pending_csv="$(npm_pending_install_scripts "${dir}" "${present[@]}")" || rc=$?
    if (( rc != 0 )); then
        # Fail closed: without npm's own state there is no proof the blocked scripts
        # ran, and reporting success would ship an unverified install.
        log_event "ERROR" "${phase}" "install_scripts_state_unreadable" \
            "Could not re-read the npm install-script state to verify approval" "${rc}" \
            "dir=${dir}"
        return 1
    fi
    if [[ -n "${pending_csv}" ]]; then
        log_event "ERROR" "${phase}" "install_scripts_unverified" \
            "npm still reports install scripts as unapproved after approve" 1 \
            "dir=${dir};packages=${pending_csv}"
        return 1
    fi
    log_event "INFO" "${phase}" "install_scripts_approved" \
        "Dependency install scripts approved and executed" 0 \
        "dir=${dir};packages=$(IFS=,; printf '%s' "${present[*]}")"
}

# Marker of the transient-rename retry in pi-extensible-workflows. State is written as
# a bare write(.tmp) + rename(), so a transient lock on the target (Defender, indexing,
# sync client, or a concurrent pi process) fails the write with EPERM unless the loaded
# artifact retries it. The retry ships in the published release; the version string
# cannot prove which build pi loads, so the symbol in the artifact is the proof.
PI_WORKFLOWS_RETRY_MARKER="renameWithRetry"

# Prove an installed atomic-write module carries the transient-rename retry.
# Returns 1 with a WARN when it cannot be proven, so callers decide the fallback.
assert_transient_rename_retry() {
    local io_js="$1" phase="$2" context="$3"

    if [[ ! -f "${io_js}" ]]; then
        log_event "WARN" "${phase}" "retry_probe_missing" \
            "Atomic-write module not found; cannot prove the transient-rename retry" 0 \
            "path=${io_js};context=${context}"
        return 1
    fi
    if ! grep -q "${PI_WORKFLOWS_RETRY_MARKER}" "${io_js}"; then
        log_event "WARN" "${phase}" "retry_missing" \
            "Artifact has no transient-rename retry; EPERM-prone state writes stay unfixed" 0 \
            "path=${io_js};context=${context};remedy=reinstall the latest pi-extensible-workflows release"
        return 1
    fi
    log_event "INFO" "${phase}" "retry_verified" \
        "Transient-rename retry present in the loaded artifact" 0 \
        "path=${io_js};context=${context}"
}

# Derive the last path segment of a Pi package source, so a manifest line can be
# recognised as the workflow package the pi-workflows module owns. Identity
# comparisons for the readback check live in the Node/PowerShell helper.
pi_package_id() {
    local spec="$1"
    case "${spec}" in
        npm:*) spec="${spec#npm:}" ;;
        git:*) spec="${spec#git:}" ;;
    esac
    spec="${spec%%#*}"
    spec="${spec%.git}"
    # Strip a trailing @ref/@version, but keep a leading @scope.
    if [[ "${spec}" == *@* && "${spec%@*}" == *[!/] ]]; then
        spec="${spec%@*}"
    fi
    printf '%s' "${spec##*/}"
}

# Prove pi recorded a package by reading back pi's own registry, not by trusting
# the install command we just ran.
assert_pi_package_registered() {
    local phase="$1" spec="$2"
    local settings="${PI_AGENT_DIR}/settings.json"

    # A read-back that proves `pi install` recorded the package. In a dry run that
    # install never ran, so the check is reported instead of ending the module's plan.
    if (( DRY_RUN == 1 )); then
        log_event "INFO" "${phase}" "dry_run_skipped" \
            "pi package read-back needs an installed state; a dry run does not verify it" 0 \
            "spec=${spec}"
        return 0
    fi

    if [[ ! -f "${settings}" ]]; then
        log_event "ERROR" "${phase}" "settings_missing" \
            "pi settings.json not found; cannot verify installed packages" 1 "path=${settings}"
        return 1
    fi
    local rc=0
    node -e '
        const fs = require("node:fs");
        let settings;
        try {
            settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        } catch {
            // An unreadable or malformed registry cannot prove the registration: fail closed.
            process.exit(2);
        }
        const path = require("node:path");
        // Identity keeps scope and owner: comparing basenames made @scope/pkg match pkg,
        // and two repos with the same name match each other. Local paths resolve against
        // the base dir of the registry, because pi records them relative to the agent dir.
        const identity = (source, baseDir) => {
            let spec = String(source).trim();
            if (spec.startsWith("npm:")) {
                spec = spec.slice(4);
                const at = spec.lastIndexOf("@");
                if (at > 0) spec = spec.slice(0, at);
                return "npm:" + spec;
            }
            if (spec.startsWith("git:")) {
                spec = spec.split("#")[0].replace(/\.git$/, "");
                const at = spec.lastIndexOf("@");
                if (at > 0) spec = spec.slice(0, at);
                return "git:" + spec;
            }
            // A leading ~ means the user profile, not a directory named "~" under
            // the agent dir, and the shell cannot expand it inside a quoted argument.
            if (spec === "~" || spec.startsWith("~/") || spec.startsWith("~\\")) {
                spec = path.join(process.env.HOME || require("node:os").homedir(), spec.slice(1).replace(/^[\\/]+/, ""));
            }
            const resolved = path.resolve(baseDir, spec);
            return "local:" + (process.platform === "win32" ? resolved.toLowerCase() : resolved);
        };
        const baseDir = path.dirname(process.argv[1]);
        const packages = settings.packages ?? [];
        // Resolve a local want exactly as the recorded entries are resolved:
        // against the agent dir, where pi records them, never the caller cwd.
        const want = identity(process.argv[2], baseDir);
        const found = packages.some((entry) => identity(typeof entry === "string" ? entry : entry?.source, baseDir) === want);
        process.exit(found ? 0 : 1);
    ' "${settings}" "${spec}" || rc=$?
    if (( rc == 2 )); then
        log_event "ERROR" "${phase}" "settings_unreadable" \
            "pi settings.json could not be parsed; cannot prove the package state" 1 "path=${settings}"
        return 1
    fi
    if (( rc == 0 )); then
        log_event "INFO" "${phase}" "package_registered" \
            "pi registered the package" 0 "spec=${spec}"
        return 0
    fi
    log_event "ERROR" "${phase}" "package_not_registered" \
        "pi did not register the package in settings.json" 1 \
        "spec=${spec};settings=${settings}"
    return 1
}

# Resolve the Pi package manifest. Order: explicit override, then the Pi config
# repo (~/.pi/agent usually symlinks into a dotenv checkout), then a profile kept
# next to the installer. Prints the chosen path, or returns 1 when none exists.
pi_packages_manifest() {
    local candidate
    for candidate in "${PI_PACKAGES_FILE}" "${PI_AGENT_DIR}/pi-packages.txt" "${SCRIPT_DIR}/pi-packages.txt"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] && {
            printf '%s' "${candidate}"
            return 0
        }
    done
    return 1
}

# ==============================================================================
# Modules
# ==============================================================================

# --- base -------------------------------------------------------------------
mod_base() {
    section "Base system dependencies"

    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_cmd "base" brew install \
            git curl wget jq unzip gnupg python neovim gh go imagemagick
        return
    fi

    case "${PM}" in
        apt-get)
            local pkgs=(build-essential rsync sudo curl wget git unzip tar ca-certificates gnupg jq
                       python3 python3-venv python3-pip neovim gh golang-go imagemagick wl-clipboard xclip
                       x11-apps gedit pulseaudio-utils mesa-utils)
            # A debconf question or conffile prompt would stall the run mid-install, so
            # the upgrade runs non-interactive and keeps the installed conffiles.
            run_cmd "base" sudo env DEBIAN_FRONTEND=noninteractive apt-get update
            run_cmd "base" sudo env DEBIAN_FRONTEND=noninteractive apt-get \
                -y -o Dpkg::Options::=--force-confold upgrade
            # nala is the frontend for the bulk install below; apt-get bootstraps it so
            # a machine that does not have it still converges in this one pass.
            run_cmd "base" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nala
            run_cmd "base" sudo nala install -y "${pkgs[@]}"
            ;;
        dnf)
            local pkgs=(gcc gcc-c++ make curl wget git unzip tar ca-certificates gnupg2 jq
                       python3 python3-pip neovim gh golang ImageMagick wl-clipboard xclip)
            run_cmd "base" sudo dnf install -y "${pkgs[@]}"
            ;;
        pacman)
            local pkgs=(base-devel curl wget git unzip tar ca-certificates gnupg jq
                       python python-pip neovim go imagemagick wl-clipboard xclip)
            # github-cli conflicts with every other package that provides gh (github-cli-git
            # from the AUR, common on CachyOS). --noconfirm answers pacman's removal prompt
            # with "no", so the transaction aborts and takes the whole run with it. Request
            # it only when nothing provides gh yet: an existing provider is never removed.
            if command -v gh >/dev/null 2>&1 || pacman -Qq github-cli-git >/dev/null 2>&1; then
                log_event "INFO" "base" "gh_provider_present" \
                    "gh is already installed; skipping github-cli to avoid an unresolvable pacman conflict" 0 \
                    "package=github-cli"
            else
                pkgs+=(github-cli)
            fi
            run_cmd "base" sudo pacman -Sy --needed --noconfirm "${pkgs[@]}"
            ;;
        zypper)
            local pkgs=(gcc gcc-c++ make curl wget git unzip tar ca-certificates gpg2 jq
                       python3 python3-pip neovim gh go ImageMagick wl-clipboard xclip)
            run_cmd "base" sudo zypper --non-interactive refresh
            run_cmd "base" sudo zypper --non-interactive install --no-recommends "${pkgs[@]}"
            ;;
    esac

    require_command python3
}

# --- node -------------------------------------------------------------------
mod_node() {
    section "Node.js"

    local NVM_VERSION="${NVM_VERSION:-v0.40.3}"
    export NVM_DIR="${HOME}/.nvm"

    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
        local installer="${TMP_DIR}/install-nvm.sh"
        run_cmd "node" curl -fsSL \
            "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "${installer}"
        run_cmd "node" bash "${installer}"
    fi

    # nvm refuses to operate when npm_config_prefix is set (e.g. to /usr/local),
    # aborting with "nvm is not compatible with the npm_config_prefix ...".
    # It is only needed by nvm's own shims, so drop it for this process.
    unset npm_config_prefix NPM_CONFIG_PREFIX 2>/dev/null || log_event "WARN" "node" "unset_prefix_failed" "Could not unset npm prefix vars" 0

    # The one deliberate dry-run exception: sourcing nvm's bootstrap is not a mutation
    # and keeps the runtime on PATH for version probes; no nvm command runs because they
    # all go through guarded run_cmd.
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"

    run_cmd "node" nvm install 22
    run_cmd "node" nvm alias default 22
    run_cmd "node" nvm use 22

    assert_node_minimum

    # npm@latest (NOT npm@12 - that version does not exist).
    run_cmd "node" npm install -g npm@latest
    run_optional "node" npm cache verify

    # Make node/npm reachable under sudo (nvm's dir is not on sudo's secure_path),
    # so downstream "sudo npm ..." calls resolve. Optional: needs write to /usr/local/bin.
    local node_bin npm_bin
    node_bin="$(command -v node)"
    npm_bin="$(command -v npm)"
    run_optional "node" sudo ln -sf "${node_bin}" /usr/local/bin/node
    run_optional "node" sudo ln -sf "${npm_bin}" /usr/local/bin/npm
}

assert_node_minimum() {
    require_command node

    local node_version major minor
    capture_cmd node_version "node" node --version
    if [[ "${node_version}" =~ ^v([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
    else
        log_event "ERROR" "node" "version_invalid" "Could not parse Node.js version" 1 "version=${node_version}"
        return 1
    fi

    if (( major < 22 || (major == 22 && minor < 19) )); then
        log_event "ERROR" "node" "version_unsupported" \
            "Node.js ${node_version} is too old; pi-extensible-workflows and @earendil-works/pi-coding-agent need >= 22.19" 1
        return 1
    fi
    log_event "INFO" "node" "runtime_validated" "Node.js version satisfies the pi and workflow requirements" 0 \
        "version=${node_version};minimum=22.19"
}

# --- bun --------------------------------------------------------------------
mod_bun() {
    section "Bun"
    export BUN_INSTALL="${HOME}/.bun"
    if [[ ! -x "${BUN_INSTALL}/bin/bun" ]]; then
        local installer="${TMP_DIR}/install-bun.sh"
        run_cmd "bun" curl -fsSL https://bun.sh/install -o "${installer}"
        run_cmd "bun" bash "${installer}"
    fi
    export PATH="${BUN_INSTALL}/bin:${PATH}"
    require_command bun
    local bun_version
    if capture_cmd bun_version "bun" bun --version; then
        log_event "INFO" "bun" "runtime_ready" "Bun runtime validated" 0 "version=${bun_version}"
    else
        return 1
    fi
}

# --- pi ---------------------------------------------------------------------
mod_pi() {
    section "Pi"
    export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"
    if ! command -v pi >/dev/null 2>&1; then
        local installer="${TMP_DIR}/install-pi.sh"
        run_cmd "pi" curl -fsSL https://pi.dev/install.sh -o "${installer}"
        [[ -s "${installer}" ]] || {
            log_event "ERROR" "pi" "installer_missing" "pi installer is empty" 1 "path=${installer}"
            return 1
        }
        run_vendor_installer "pi" sh "${installer}"
    fi
    export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"
    require_command pi
    if ! PI_VERSION="$(pi --version 2>/dev/null)"; then
        PI_VERSION="unknown"
        log_event "WARN" "pi" "version_unavailable" "Could not read pi --version" 0
    fi
    log_event "INFO" "pi" "cli_ready" "Pi CLI detected" 0 "version=${PI_VERSION}"
    if (( DRY_RUN == 1 )); then
        dry_run_note "pi" "${PI_AGENT_DIR} + ${PI_EXTENSIONS_DIR} + ${PI_NPM_DIR} + ${PI_AGENT_DIR}/skills"
        return 0
    fi
    mkdir -p "${PI_AGENT_DIR}" "${PI_EXTENSIONS_DIR}" "${PI_NPM_DIR}" "${PI_AGENT_DIR}/skills"

    # pi's managed npm root is where `pi install` and `pi update --extensions` land.
    # npm 12 refuses URL/tarball dependencies in that root unless it opts in, so
    # configure it as soon as the root exists - independent of any workflow module.
    ensure_npm_remote_sources "${PI_NPM_DIR}"
}

# --- go ---------------------------------------------------------------------
mod_go() {
    section "Go toolchain"
    if command -v go >/dev/null 2>&1; then
        local go_version
        if capture_cmd go_version "go" go version; then
            log_event "INFO" "go" "already_present" "Go already installed" 0 "version=${go_version}"
            return
        fi
        return 1
    fi
    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_cmd "go" brew install go
    else
        # Installed by mod_base on Linux; if we got here it was skipped.
        case "${PM}" in
            apt-get) run_cmd "go" sudo apt-get install -y golang-go ;;
            dnf)     run_cmd "go" sudo dnf install -y golang ;;
            pacman)  run_cmd "go" sudo pacman -Sy --needed --noconfirm go ;;
            zypper)  run_cmd "go" sudo zypper --non-interactive install go ;;
        esac
    fi
    require_command go
}

# --- dotenv (Linux only) ----------------------------------------------------
mod_dotenv() {
    section "dotenv"
    if [[ "${OS_FAMILY}" != "linux" ]]; then
        log_event "WARN" "dotenv" "skipped_non_linux" \
            "dotenv/setup_env.sh targets Linux package managers; skipped on ${OS_FAMILY}"
        return
    fi

    if (( DRY_RUN == 1 )); then
        dry_run_note "dotenv" \
            "$(dirname -- "${DOTENV_DIR}") + git clone ${DOTENV_REPO} ${DOTENV_DIR} + bash ${DOTENV_DIR}/setup_env.sh (plus its in-place reference patches)"
        return 0
    fi
    mkdir -p "$(dirname -- "${DOTENV_DIR}")"
    if [[ ! -d "${DOTENV_DIR}/.git" ]]; then
        run_cmd "dotenv" git clone -- "${DOTENV_REPO}" "${DOTENV_DIR}"
    else
        log_event "INFO" "dotenv" "repository_exists" "Existing dotenv repository preserved"
    fi

    # Idempotent upstream-quirk patches (no-ops once upstream merges the fixes).
    if grep_probe "dotenv" "${TMP_DIR}/monokai_hits" \
        -rIl --exclude-dir=.git "gthelding/monokai-pro.nvim" "${DOTENV_DIR}"; then
        while IFS= read -r file; do
            run_cmd "dotenv" sed -i 's|gthelding/monokai-pro.nvim|loctvl842/monokai-pro.nvim|g' "${file}"
            log_event "INFO" "dotenv" "reference_patched" "Updated stale monokai-pro reference" 0 "file=${file}"
        done < "${TMP_DIR}/monokai_hits"
    fi

    if grep_probe "dotenv" "${TMP_DIR}/sudo_npm_hits" \
        -rIl --exclude-dir=.git 'sudo npm install -g --prefix /usr/local bun' "${DOTENV_DIR}"; then
        while IFS= read -r file; do
            run_cmd "dotenv" sed -i 's|sudo npm install -g --prefix /usr/local bun|sudo "$(command -v npm)" install -g --prefix /usr/local bun|g' "${file}"
            log_event "INFO" "dotenv" "reference_patched" "Patched sudo npm call to absolute path" 0 "file=${file}"
        done < "${TMP_DIR}/sudo_npm_hits"
    fi

    # ai-memory-kit v0.1.0 fetched tagged refs through refs/heads, which GitHub
    # rejects. Patch old dotenv checkouts before they stream that installer.
    if grep_probe "dotenv" "${TMP_DIR}/memory_installer_hits" \
        -rIl --exclude-dir=.git -F 'command -v aimem >/dev/null 2>&1 || AIMEM_REF="${AIMEM_REF}" curl -fsSL "https://raw.githubusercontent.com/darkrei08/ai-memory-kit/${AIMEM_REF}/install.sh" | AIMEM_REF="${AIMEM_REF}" bash -s -- --no-skill' "${DOTENV_DIR}"; then
        while IFS= read -r file; do
            run_cmd "dotenv" python3 - "${file}" <<'PYPATCH'
import sys
path = sys.argv[1]
with open(path, "r", newline="") as fh:
    text = fh.read()
old = 'command -v aimem >/dev/null 2>&1 || AIMEM_REF="${AIMEM_REF}" curl -fsSL "https://raw.githubusercontent.com/darkrei08/ai-memory-kit/${AIMEM_REF}/install.sh" | AIMEM_REF="${AIMEM_REF}" bash -s -- --no-skill\n'
new = (
    '# AI_DEV_MEMORY_PATCH: fix tagged ai-memory-kit codeload URL\n'
    'command -v aimem >/dev/null 2>&1 || AIMEM_REF="${AIMEM_REF}" curl -fsSL "https://raw.githubusercontent.com/darkrei08/ai-memory-kit/${AIMEM_REF}/install.sh" \\\n'
    '  | sed \'s|/tar.gz/refs/heads/\\$REF|/tar.gz/\\$REF|g\' \\\n'
    '  | AIMEM_REF="${AIMEM_REF}" bash -s -- --no-skill\n'
)
if old not in text:
    raise SystemExit("ai-memory-kit installer line changed unexpectedly")
with open(path, "w", newline="") as fh:
    fh.write(text.replace(old, new))
PYPATCH
            log_event "INFO" "dotenv" "reference_patched" "Patched ai-memory-kit tag download URL" 0 "file=${file}"
        done < "${TMP_DIR}/memory_installer_hits"
    fi

    if grep_probe "dotenv" "${TMP_DIR}/treesitter_hits" \
        -rIl --exclude-dir=.git -e 'npm install -g --prefix "\$HOME/.local" tree-sitter-cli' "${DOTENV_DIR}"; then
        while IFS= read -r file; do
            local marker_rc=0
            grep -q 'AI_DEV_TS_CLI_PATCH' "${file}" 2>>"${HUMAN_LOG}" || marker_rc=$?
            case "${marker_rc}" in
                0) continue ;;   # already patched
                1) ;;            # not patched yet; apply below
                *)
                    log_event "ERROR" "dotenv" "marker_probe_failed" \
                        "grep marker probe failed with an operational error" "${marker_rc}" "file=${file}"
                    exit "${marker_rc}"
                    ;;
            esac
            run_cmd "dotenv" python3 - "${file}" <<'PYPATCH'
import sys
path = sys.argv[1]
with open(path, "r", newline="") as fh:
    text = fh.read()
old = 'command -v tree-sitter >/dev/null 2>&1 || npm install -g --prefix "$HOME/.local" tree-sitter-cli\n'
new = (
    '# AI_DEV_TS_CLI_PATCH: force blocked postinstall and verify the real binary\n'
    'TS_CLI_BIN="$HOME/.local/lib/node_modules/tree-sitter-cli/tree-sitter"\n'
    'if [ ! -x "$TS_CLI_BIN" ]; then\n'
    '  npm install -g --prefix "$HOME/.local" --foreground-scripts --include=optional tree-sitter-cli\n'
    'fi\n'
    'if [ ! -x "$TS_CLI_BIN" ] && [ -f "$HOME/.local/lib/node_modules/tree-sitter-cli/install.js" ]; then\n'
    '  (cd "$HOME/.local/lib/node_modules/tree-sitter-cli" && node install.js)\n'
    'fi\n'
    '[ -x "$TS_CLI_BIN" ] || { printf \'tree-sitter binary missing after install: %s\\n\' "$TS_CLI_BIN" >&2; exit 1; }\n'
)
if old in text:
    text = text.replace(old, new)
    with open(path, "w", newline="") as fh:
        fh.write(text)
PYPATCH
            log_event "INFO" "dotenv" "reference_patched" "Patched tree-sitter-cli install" 0 "file=${file}"
        done < "${TMP_DIR}/treesitter_hits"
    fi

    if [[ -x "${DOTENV_DIR}/setup_env.sh" ]]; then
        # The upstream script also installs shared skills; both paths are
        # idempotent, so keep the upstream integration intact. It runs its own
        # copy only when no skill module replaces it in this pass, so `--only
        # dotenv` still gets the skills while a full run does not install the
        # same sources twice.
        local -a dotenv_prefix=()
        if is_selected ee || is_selected skills; then
            dotenv_prefix=(env SETUP_AI_SKIP_SKILLS=1)
        fi
        run_cmd "dotenv" "${dotenv_prefix[@]}" bash "${DOTENV_DIR}/setup_env.sh"
    else
        log_event "ERROR" "dotenv" "setup_script_missing" \
            "dotenv/setup_env.sh missing or not executable" 1 \
            "expected=${DOTENV_DIR}/setup_env.sh"
        return 1
    fi
}

# --- skill target helpers ----------------------------------------------------
agent_config_dir() {
    case "$1" in
        pi)          printf '%s\n' "${HOME}/.pi" ;;
        claude-code) printf '%s\n' "${HOME}/.claude" ;;
        gemini-cli)  printf '%s\n' "${HOME}/.gemini" ;;
        cursor)      printf '%s\n' "${HOME}/.cursor" ;;
        antigravity) printf '%s\n' "${HOME}/.antigravity" ;;
        codex)       printf '%s\n' "${HOME}/.codex" ;;
        opencode)    printf '%s\n' "${HOME}/.config/opencode" ;;
        *) return 1 ;;
    esac
}

agent_skill_root() {
    case "$1" in
        pi)          printf '%s\n' "${PI_AGENT_DIR}/skills" ;;
        claude-code) printf '%s\n' "${HOME}/.claude/skills" ;;
        gemini-cli)  printf '%s\n' "${HOME}/.gemini/skills" ;;
        cursor)      printf '%s\n' "${HOME}/.cursor/skills" ;;
        antigravity) printf '%s\n' "${HOME}/.antigravity/skills" ;;
        codex)       printf '%s\n' "${HOME}/.codex/skills" ;;
        opencode)    printf '%s\n' "${HOME}/.config/opencode/skills" ;;
        *) return 1 ;;
    esac
}

# Candidate skill roots per agent (one per line): verification passes if SKILL.md
# exists under any of them. The agent's own config dir comes first, and the shared
# ${HOME}/.agents/skills root is accepted for every agent: upstream `skills add
# --global` installs there and names it as the install target in its own summary,
# copying into an agent's config dir only when it supports that agent. A shared root
# must never hide a skipped copy, so verify_skill_for_agents reports per agent.
agent_skill_roots() {
    agent_skill_root "$1" || return 1
    printf '%s\n' "${HOME}/.agents/skills"
}

# Agents the skills CLI classifies as universal (`agents[type].skillsDir ==
# ".agents/skills"`, skills 1.5.26): their --global install target IS the shared root
# and they read it at user scope, so no copy under their own config dir is expected.
agent_uses_shared_skill_root() {
    [[ "$1" == "codex" ]]
}

# Prove a skill reached every targeted agent. Nothing under any candidate root fails;
# a skill found only under the shared root passes with a WARN naming the agent whose
# own config dir the CLI skipped, or with an INFO when that shared root is the agent's
# own install target.
verify_skill_for_agents() {
    local phase="$1" skill="$2"; shift 2
    # This proves an installed state, which a dry run does not have. Report it and let
    # the module reach the rest of its plan instead of claiming a verification it did
    # not perform.
    if (( DRY_RUN == 1 )); then
        log_event "INFO" "${phase}" "dry_run_skipped" \
            "Skill verification needs an installed state; a dry run does not verify it" 0 \
            "skill=${skill};agents=$*"
        return 0
    fi
    local agent root own_root found own checked
    for agent in "$@"; do
        found=0
        own=0
        checked=""
        if ! own_root="$(agent_skill_root "${agent}")"; then
            log_event "WARN" "${phase}" "agent_root_unknown" \
                "No skill root is known for this agent; only the shared root is checked" 0 \
                "agent=${agent}"
            own_root=""
        fi
        while IFS= read -r root; do
            checked="${checked:+${checked}, }${root}/${skill}/SKILL.md"
            if [[ -f "${root}/${skill}/SKILL.md" ]]; then
                found=1
                if [[ -n "${own_root}" && "${root}" == "${own_root}" ]]; then
                    own=1
                fi
                break
            fi
        done < <(agent_skill_roots "${agent}")
        if (( found == 0 )); then
            log_event "ERROR" "${phase}" "skill_missing" \
                "Skill SKILL.md missing for targeted agent" 1 \
                "agent=${agent};skill=${skill};checked=${checked}"
            return 1
        fi
        if (( own == 0 )); then
            if agent_uses_shared_skill_root "${agent}"; then
                log_event "INFO" "${phase}" "skill_shared_root_only" \
                    "Skill is installed under the shared skills root, which is this agent's own install target" 0 \
                    "agent=${agent};skill=${skill};shared=${HOME}/.agents/skills"
            else
                log_event "WARN" "${phase}" "skill_not_copied_to_agent_root" \
                    "Skill is installed under the shared skills root but was not copied into this agent's own config dir" 0 \
                    "agent=${agent};skill=${skill};shared=${HOME}/.agents/skills;expected=${own_root}/${skill}/SKILL.md"
            fi
        fi
    done
    return 0
}

# --- engineering-excellence -------------------------------------------------
mod_ee() {
    section "Engineering Excellence"
    require_command npx

    # Install the skill for every detected agent using the modern skills CLI
    # (replaces the old git-clone-and-move). Agents are detected by their config dir.
    # Keys are the `skills` CLI agent names (claude-code, gemini-cli, ...), which
    # differ from the config-dir basename; values are the dir we detect them by.
    local agent
    local installed_any=0
    local -a target_agents=()
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        [[ -d "$(agent_config_dir "${agent}")" ]] || continue
        run_cmd "engineering-excellence" \
            npx --yes skills@latest add "${ENGINEERING_EXCELLENCE_SLUG}" \
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent "${agent}" --copy --yes </dev/null
        target_agents+=("${agent}")
        installed_any=1
    done

    if (( installed_any == 0 )); then
        # No agent detected yet - install at least for pi (created by mod_pi).
        run_cmd "engineering-excellence" \
            npx --yes skills@latest add "${ENGINEERING_EXCELLENCE_SLUG}" \
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent pi --copy --yes </dev/null
        target_agents=(pi)
    fi

    verify_skill_for_agents "engineering-excellence" "${ENGINEERING_EXCELLENCE_SKILL}" "${target_agents[@]}"
    log_event "INFO" "engineering-excellence" "skills_verified" \
        "Engineering Excellence skill verified for every targeted agent" 0 \
        "agents=$(IFS=,; printf '%s' "${target_agents[*]}")"
}

# --- upstream agent skills --------------------------------------------------
# Installs the shared skill stack via `npx skills add`; the upstream dotenv
# setup also installs its own copy, and both paths are idempotent.
mod_skills() {
    section "Agent skills (upstream stack)"
    require_command npx

    # Agent keys are the `skills` CLI names (claude-code, gemini-cli, ...),
    # detected by their config dir - same mapping as mod_ee.
    local agent
    local -a agents=()
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        [[ -d "$(agent_config_dir "${agent}")" ]] && agents+=("${agent}")
    done
    # pi is created by mod_pi; guarantee at least pi so the stack always lands.
    (( ${#agents[@]} == 0 )) && agents=(pi)

    local source_spec source skill_csv
    local -a skill_list
    for source_spec in "${UPSTREAM_SKILL_SOURCES[@]}"; do
        source="${source_spec%% *}"
        skill_csv="${source_spec#* }"
        # The script keeps global IFS at newline/tab for safe line reads;
        # explicitly restore spaces for this space-separated skill list.
        IFS=' ' read -r -a skill_list <<< "${skill_csv}"
        for agent in "${agents[@]}"; do
            run_cmd "skills" \
                npx --yes skills@latest add "${source}" \
                --skill "${skill_list[@]}" --global --agent "${agent}" --copy --yes </dev/null
        done
    done

    local sk
    for sk in "${UPSTREAM_SKILL_NAMES[@]}"; do
        verify_skill_for_agents "skills" "${sk}" "${agents[@]}"
    done
    log_event "INFO" "skills" "skills_verified" \
        "Upstream skills verified for every targeted agent" 0 \
        "agents=$(IFS=,; printf '%s' "${agents[*]}")"
}

# --- pi-extensible-workflows ------------------------------------------------
# Concept split for this module:
#   1. npm behavior of both pi roots (npm 12 EALLOWREMOTE on remote sources)
#   2. published pi-extensible-workflows, verified down to the loaded artifact
mod_pi_workflows() {
    section "pi-extensible-workflows"
    require_command pi
    require_command node
    assert_node_minimum

    # 1. Configure npm before the first install: both roots are written below, and
    #    `pi update --extensions` later reinstalls every configured package through
    #    the managed root.
    ensure_npm_remote_sources "${PI_NPM_DIR}"
    ensure_npm_remote_sources "${PI_EXTENSIONS_DIR}"

    if [[ -z "${PI_WORKFLOW_VERSION}" ]]; then
        capture_cmd PI_WORKFLOW_VERSION "pi-workflows" npm view pi-extensible-workflows version
    fi
    [[ -n "${PI_WORKFLOW_VERSION}" ]] || {
        log_event "ERROR" "pi-workflows" "version_unresolved" "Cannot determine published version" 1
        exit 1
    }
    log_event "INFO" "pi-workflows" "version_selected" "Workflow version selected" 0 "version=${PI_WORKFLOW_VERSION}"

    run_cmd "pi-workflows" pi install "npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
    # Prove what pi recorded instead of trusting the command's exit code: the parity rule
    # here is the same readback the PowerShell sibling performs right after its install.
    if ! assert_pi_package_registered "pi-workflows" "npm:pi-extensible-workflows"; then
        log_event "ERROR" "pi-workflows" "published_package_not_registered" \
            "pi did not register the published workflow package" 1 \
            "version=${PI_WORKFLOW_VERSION}"
        return 1
    fi

    if (( DRY_RUN == 1 )); then
        dry_run_note "pi-workflows" "${PI_EXTENSIONS_DIR}"
        dry_run_note "pi-workflows" "${PI_EXTENSIONS_DIR}/.npmrc: ignore-scripts=false"
    else
        mkdir -p "${PI_EXTENSIONS_DIR}"
        pushd "${PI_EXTENSIONS_DIR}" >/dev/null
        # Append-only, so the npm 12 remote-source opt-in written above survives.
        if [[ ! -f .npmrc ]] || ! grep -qxF 'ignore-scripts=false' .npmrc; then
            printf '%s\n' 'ignore-scripts=false' >> .npmrc
        fi
    fi
    run_cmd "pi-workflows-node" npm install --save-exact --no-audit --no-fund --legacy-peer-deps \
        "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
    (( DRY_RUN == 1 )) || popd >/dev/null

    # Verify the version that actually landed in THIS directory by reading its
    # local package.json directly. Do NOT use require.resolve here: it ascends
    # the directory tree and can resolve a shadowing copy in an ancestor
    # node_modules, producing a false version_mismatch.
    local local_pkg="${PI_EXTENSIONS_DIR}/node_modules/pi-extensible-workflows/package.json"
    if [[ ! -f "${local_pkg}" ]]; then
        log_event "ERROR" "pi-workflows-node" "install_missing" "pi-extensible-workflows not installed in extensions dir" 1 \
            "expected_path=${local_pkg}"
        exit 1
    fi
    log_event "INFO" "pi-workflows-node" "module_resolved" "Installed in pi extensions dir" 0 "resolved=${local_pkg}"

    local installed
    capture_cmd installed "pi-workflows-node" node -e \
        'console.log(require(process.argv[1]).version)' "${local_pkg}"
    if [[ "${installed}" != "${PI_WORKFLOW_VERSION}" ]]; then
        log_event "ERROR" "pi-workflows-node" "version_mismatch" "Installed version mismatch" 1 \
            "expected=${PI_WORKFLOW_VERSION};actual=${installed}"
        exit 1
    fi

    if [[ -d "${DOTENV_EXT_DIR}" ]]; then
        if (( DRY_RUN == 1 )); then
            dry_run_note "dotenv-workflows" "${DOTENV_EXT_DIR} + ${DOTENV_EXT_DIR}/.npmrc: ignore-scripts=false"
        else
            pushd "${DOTENV_EXT_DIR}" >/dev/null
            # Same npm 12 opt-in for this install root; this also creates the package marker.
            ensure_npm_remote_sources "${DOTENV_EXT_DIR}"
            if [[ ! -f .npmrc ]] || ! grep -qxF 'ignore-scripts=false' .npmrc; then
                printf '%s\n' 'ignore-scripts=false' >> .npmrc
            fi
        fi
        run_cmd "dotenv-workflows" npm install --save-exact --no-audit --no-fund --legacy-peer-deps \
            "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
        (( DRY_RUN == 1 )) || popd >/dev/null

        local dotenv_workflow_pkg="${DOTENV_EXT_DIR}/node_modules/pi-extensible-workflows/package.json"
        if [[ ! -f "${dotenv_workflow_pkg}" ]]; then
            log_event "ERROR" "dotenv-workflows" "install_missing" \
                "pi-extensible-workflows not installed in dotenv extensions dir" 1 \
                "expected_path=${dotenv_workflow_pkg}"
            exit 1
        fi
        local dotenv_installed
        capture_cmd dotenv_installed "dotenv-workflows" node -e \
            'console.log(require(process.argv[1]).version)' "${dotenv_workflow_pkg}"
        if [[ "${dotenv_installed}" != "${PI_WORKFLOW_VERSION}" ]]; then
            log_event "ERROR" "dotenv-workflows" "version_mismatch" \
                "Installed dotenv workflow version mismatch" 1 \
                "expected=${PI_WORKFLOW_VERSION};actual=${dotenv_installed}"
            exit 1
        fi
        log_event "INFO" "dotenv-workflows" "module_verified" \
            "Verified installed dotenv workflow package" 0 "path=${dotenv_workflow_pkg}"
    fi

    # 2. Prove the artifact pi will load carries the transient-rename retry the published
    #    release ships. Reading the installed file - not the install command - is the only
    #    proof of which build was loaded; an unproven root is reported, never hidden.
    local root root_io
    for root in "${PI_EXTENSIONS_DIR}" "${DOTENV_EXT_DIR}" "${PI_NPM_DIR}"; do
        [[ -d "${root}" ]] || continue
        root_io="${root}/node_modules/pi-extensible-workflows/dist/src/io.js"
        assert_transient_rename_retry "${root_io}" "pi-workflows" "root=${root}" || continue
    done
}

# --- pi-packages ------------------------------------------------------------
# Declarative Pi packages: the manifest resolved by `pi_packages_manifest` lists one
# source per line, so a NEW machine gets every extension the toolchain needs
# without hand-editing ~/.pi/agent/settings.json. Supported sources are whatever
# `pi install` accepts: `npm:<pkg>[@<version>]`,
# `git:<host>/<owner>/<repo>[@<ref>]`, or a local path. Blank lines and `#`
# comments are ignored, and every install is verified by reading pi's own
# settings.json back. pi-extensible-workflows is skipped here on purpose: the
# pi-workflows module owns that package (published release).
mod_pi_packages() {
    section "pi-packages"
    require_command pi
    require_command node

    # Manifest entries are arbitrary sources, so the managed root must already
    # tolerate remote (URL/tarball) dependencies before the first install.
    ensure_npm_remote_sources "${PI_NPM_DIR}"

    local manifest
    if ! manifest="$(pi_packages_manifest)"; then
        log_event "INFO" "pi-packages" "manifest_absent" \
            "No Pi package manifest; nothing extra to install" 0 \
            "override=${PI_PACKAGES_FILE:-<unset>};config=${PI_AGENT_DIR}/pi-packages.txt;profile=${SCRIPT_DIR}/pi-packages.txt"
        return 0
    fi
    log_event "INFO" "pi-packages" "manifest_loaded" "Pi package manifest found" 0 \
        "manifest=${manifest}"

    local line installed=0 skipped=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        # Trim surrounding whitespace only; internal whitespace stays invalid input.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue

        if [[ "$(pi_package_id "${line}")" == "$(pi_package_id 'npm:pi-extensible-workflows')" ]]; then
            log_event "WARN" "pi-packages" "workflow_owned_elsewhere" \
                "Skipping pi-extensible-workflows; the pi-workflows module owns that package" 0 \
                "spec=${line}"
            skipped=$(( skipped + 1 ))
            continue
        fi

        run_cmd "pi-packages" pi install "${line}" || return 1
        assert_pi_package_registered "pi-packages" "${line}" || return 1
        installed=$(( installed + 1 ))
    done < "${manifest}"

    log_event "INFO" "pi-packages" "manifest_applied" \
        "Pi package manifest applied" 0 \
        "installed=${installed};skipped=${skipped};manifest=${manifest}"
}

# --- herdr ------------------------------------------------------------------
mod_herdr() {
    section "herdr"
    if command -v herdr >/dev/null 2>&1; then
        local herdr_version
        if capture_cmd herdr_version "herdr" herdr --version; then
            log_event "INFO" "herdr" "already_present" "herdr already installed" 0 "version=${herdr_version}"
            return
        fi
        return 1
    fi
    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_cmd "herdr" brew install herdr
    else
        local installer="${TMP_DIR}/install-herdr.sh"
        run_cmd "herdr" curl -fsSL https://herdr.dev/install.sh -o "${installer}"
        [[ -s "${installer}" ]] || {
            log_event "ERROR" "herdr" "installer_missing" "herdr installer is empty" 1 "path=${installer}"
            return 1
        }
        run_cmd "herdr" sh "${installer}"
    fi
    require_command herdr
}

# --- gentle-ai --------------------------------------------------------------
# Delete one exact line from an existing file, keeping every other byte. No
# `sed -i` (BSD/macOS sed needs an -i '' argument); the rewrite goes through a
# temp file and only replaces the original after grep succeeded, so a failure
# leaves the file as it was. Return 0 when the line was removed, 1 when there was
# nothing to remove, and 2 when the line was present but the file could not be
# rewritten. Only LF lines are considered: every line this installer ever
# appended used LF.
remove_line_from_file() {
    local file="$1" line="$2" grep_rc
    [[ -f "${file}" ]] || return 1
    if grep -Fqx -- "${line}" "${file}" 2>/dev/null; then :; else
        grep_rc=$?
        if (( grep_rc == 1 )); then return 1; fi
        return 2
    fi
    if [[ -L "${file}" ]]; then
        log_event "ERROR" "gentle-ai" "remove_line_symlink" \
            "Refusing to replace symlink ${file}; its target was left unchanged" 1
        return 2
    fi
    local tmp="${file}.setup-ai.tmp" rc=0
    if ! cp -p -- "${file}" "${tmp}"; then
        rm -f -- "${tmp}"
        return 2
    fi
    grep -vxF -- "${line}" "${file}" > "${tmp}" || rc=$?
    if (( rc > 1 )); then
        rm -f -- "${tmp}"
        return 2
    fi
    if ! mv -- "${tmp}" "${file}"; then
        rm -f -- "${tmp}"
        return 2
    fi
    return 0
}

# An earlier setup-ai version persisted GENTLE_PI_QUIET_TOOLS=0 next to
# pi-hashline-edit-pro to keep pi startable. That value is exactly the one that
# makes gentle-pi's bundled pi-pretty register the built-in tool names itself, so
# it now causes the startup abort it was meant to avoid. Remove the exact lines
# this installer wrote, unconditionally: a machine can carry them with no
# shadowing package left. Anything else in those files belongs to the user.
remove_stale_quiet_tools_switch() {
    if (( DRY_RUN == 1 )); then
        dry_run_note "gentle-ai" "remove each stale GENTLE_PI_QUIET_TOOLS=0 line from ~/.bashrc, ~/.zshrc, ~/.profile and ~/.config/environment.d/50-gentle-pi.conf"
        return 0
    fi
    local changed=() failed=() candidate remove_rc
    for candidate in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if remove_line_from_file "${candidate}" 'export GENTLE_PI_QUIET_TOOLS=0'; then
            changed+=("${candidate}")
        else
            remove_rc=$?
            if (( remove_rc == 2 )); then failed+=("${candidate}"); fi
        fi
    done
    # systemd --user sessions and panes that never source an rc read this file.
    local envd="${HOME}/.config/environment.d/50-gentle-pi.conf"
    if remove_line_from_file "${envd}" 'GENTLE_PI_QUIET_TOOLS=0'; then
        changed+=("${envd}")
    else
        remove_rc=$?
        if (( remove_rc == 2 )); then failed+=("${envd}"); fi
    fi
    if (( ${#failed[@]} > 0 )); then
        local remediation="replace each listed symlink with a regular file or remove the stale line manually, then rerun setup-ai"
        log_event "ERROR" "gentle-ai" "stale_quiet_tools_switch_unremoved" \
            "Could not remove GENTLE_PI_QUIET_TOOLS=0 from files=$(IFS=,; printf '%s' "${failed[*]}"); ${remediation}" 1 \
            "files=$(IFS=,; printf '%s' "${failed[*]}");remediation=${remediation}"
        return 1
    fi
    (( ${#changed[@]} > 0 )) || return 0
    log_event "INFO" "gentle-ai" "stale_quiet_tools_switch_removed" \
        "Removed the GENTLE_PI_QUIET_TOOLS=0 switch an earlier setup-ai persisted: it disables gentle-pi quiet tools, which is what makes pi-pretty register the built-in tool names itself and abort startup" 0 \
        "files=$(IFS=,; printf '%s' "${changed[*]}")"
}

# gentle-pi's quiet-tools re-registers the built-in read/edit/grep/... tools, and
# pi aborts at startup ("Tool <name> conflicts") when a second installed extension
# registers one of the same names. pi-tool-display does exactly that, and so does
# the dropped pi-hashline-edit-pro still registered on machines upgraded from an
# older install. gentle-pi has no per-registrant switch, so the repair is its
# object entry in settings.json with both of its own registrants excluded. Loading
# extensions without a model call is impossible, so the collision is detected
# statically and the entry rewritten as raw text, which leaves the rest of the
# file's formatting untouched.
handle_quiet_tools_conflict() {
    remove_stale_quiet_tools_switch || return 1

    local settings="${PI_AGENT_DIR}/settings.json"
    [[ -f "${settings}" ]] || return 0

    local raw=""
    raw="$(<"${settings}")"
    # One alternation, both identities: pi-tool-display registers read/bash/find/
    # grep/ls, pi-hashline-edit-pro was that name's owner before it was dropped.
    local shadow=""
    if [[ "${raw}" =~ \"npm:(pi-tool-display|pi-hashline-edit-pro)(@[^\"]*)?\" ]]; then
        shadow="${BASH_REMATCH[1]}"
    fi
    [[ -n "${shadow}" ]] || return 0

    local remediation='{"source":"npm:gentle-pi","extensions":["-extensions/quiet-tools.ts","-extensions/pi-pretty.ts"]}'

    # Which edit is safe is a structural question, so parse the JSON for it; the
    # edit itself stays textual to preserve formatting.
    local state="invalid"
    if ! state="$(node -e '
        const fs = require("node:fs");
        let settings;
        try {
            settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        } catch {
            console.log("invalid");
            process.exit(0);
        }
        const entries = (Array.isArray(settings.packages) ? settings.packages : []).filter((entry) => {
            const source = typeof entry === "string" ? entry : (entry && entry.source) || "";
            return /^npm:gentle-pi(@.*)?$/.test(source);
        });
        const wanted = ["-extensions/quiet-tools.ts", "-extensions/pi-pretty.ts"];
        if (entries.length === 0) console.log("absent");
        else if (entries.length > 1) console.log("ambiguous");
        else if (typeof entries[0] === "string") console.log("string");
        else if (wanted.every((name) => (entries[0].extensions || []).includes(name))) console.log("guarded");
        else console.log("ambiguous");
    ' "${settings}" 2>/dev/null)"; then
        state="invalid"
    fi
    case "${state}" in
        absent|guarded) return 0 ;;
        string) ;;
        *)
            # Never claim a repair we did not make: an entry that cannot be
            # rewritten safely (duplicate, unparseable or compact JSON) is reported
            # with the exact JSON the user has to put in its place.
            log_event "WARN" "gentle-ai" "quiet_tools_conflict_unrepaired" \
                "${shadow} re-registers a built-in tool name, so pi aborts at startup until gentle-pi excludes its own registrants; replace the gentle-pi entry in ${settings} with the JSON below" 0 \
                "expected=${remediation};settings=${settings}"
            return 0
            ;;
    esac

    # Stage the replacement as a sibling of its target: same filesystem (so the
    # final mv is atomic) and `cp -p` carries the original mode over. Nothing is
    # staged on the already-repaired paths above.
    local tmp="${settings}.setup-ai.tmp" staged=0
    if cp -p -- "${settings}" "${tmp}" \
        && awk '
            # The entry can be the last element of the array, so its own trailing
            # comma has to survive, and the replacement follows its indentation.
            /^[ \t]*"npm:gentle-pi"[ \t]*,?[ \t]*$/ {
                hits++
                indent = $0
                sub(/[^ \t].*$/, "", indent)
                comma = ($0 ~ /,[ \t]*$/) ? "," : ""
                printf "%s{\n", indent
                printf "%s  \"source\": \"npm:gentle-pi\",\n", indent
                printf "%s  \"extensions\": [\n", indent
                printf "%s    \"-extensions/quiet-tools.ts\",\n", indent
                printf "%s    \"-extensions/pi-pretty.ts\"\n", indent
                printf "%s  ]\n", indent
                printf "%s}%s\n", indent, comma
                next
            }
            { print }
            END { exit (hits == 1 ? 0 : 1) }
        ' "${settings}" > "${tmp}" \
        && node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "${tmp}" 2>/dev/null; then
        staged=1
    fi
    if (( staged == 0 )); then
        rm -f -- "${tmp}"
        log_event "WARN" "gentle-ai" "quiet_tools_conflict_unrepaired" \
            "${shadow} re-registers a built-in tool name, so pi aborts at startup until gentle-pi excludes its own registrants; ${settings} is unchanged, replace the gentle-pi entry with the JSON below" 0 \
            "expected=${remediation};settings=${settings}"
        return 0
    fi
    if ! mv -- "${tmp}" "${settings}"; then
        rm -f -- "${tmp}"
        log_event "ERROR" "gentle-ai" "quiet_tools_conflict_unrepaired" \
            "Could not replace ${settings} with the repaired copy; pi keeps aborting at startup until gentle-pi excludes -extensions/quiet-tools.ts and -extensions/pi-pretty.ts" 1 \
            "settings=${settings}"
        return 1
    fi
    log_event "INFO" "gentle-ai" "quiet_tools_conflict_repaired" \
        "${shadow} re-registers one of the built-in tool names gentle-pi's quiet tools own; repair applied with -extensions/quiet-tools.ts and -extensions/pi-pretty.ts excluded" 0 \
        "settings=${settings}"
}

# Verify the real pi startup path after the quiet-tools repair. PI_OFFLINE=1 and
# stdin from /dev/null load extensions without a model call or network; measured
# on pi 0.85.1 with pi-tool-display 0.5.0 and gentle-pi 3.2.1, the conflicting
# settings exit 1 with a Tool "read" conflicts diagnostic and the repaired settings
# exit 0 in about 12 seconds.
verify_pi_startup() {
    if ! command -v pi >/dev/null 2>&1; then
        log_event "INFO" "gentle-ai" "pi_startup_skipped" \
            "pi is not on PATH; startup verification skipped" 0
        return 0
    fi

    local startup_timeout="${PI_STARTUP_TIMEOUT:-120}" output timeout_marker
    if [[ ! "${startup_timeout}" =~ ^[1-9][0-9]*$ ]]; then
        log_event "ERROR" "gentle-ai" "pi_startup_failed" \
            "PI_STARTUP_TIMEOUT must be a positive integer" 1 \
            "timeout=${startup_timeout};settings=${PI_AGENT_DIR}/settings.json"
        return 1
    fi
    output="${TMP_DIR}/pi-startup-${RANDOM}.log"
    timeout_marker="${output}.timeout"
    if ! : > "${output}"; then
        log_event "ERROR" "gentle-ai" "pi_startup_failed" \
            "Could not create the pi startup log" 1 \
            "log=${output};settings=${PI_AGENT_DIR}/settings.json"
        return 1
    fi

    # A watchdog makes the wait bounded without requiring GNU timeout. The pi job
    # gets its own process group, and the one-second grace period makes the measured
    # upper bound PI_STARTUP_TIMEOUT + 1 second apart from command scheduling.
    set -m
    PI_OFFLINE=1 pi </dev/null >"${output}" 2>&1 &
    PI_STARTUP_PID=$!
    set +m
    (
        watchdog_sleep_pid=""
        watchdog_cleanup() {
            if [[ -n "${watchdog_sleep_pid}" ]]; then
                if kill -TERM "${watchdog_sleep_pid}" 2>/dev/null; then :; fi
                if wait "${watchdog_sleep_pid}" 2>/dev/null; then :; fi
            fi
            exit 0
        }
        trap 'watchdog_cleanup' HUP INT TERM
        sleep "${startup_timeout}" &
        watchdog_sleep_pid=$!
        if wait "${watchdog_sleep_pid}"; then :; else exit 0; fi
        if kill -0 "${PI_STARTUP_PID}" 2>/dev/null; then
            if printf '%s\n' 'timed_out' > "${timeout_marker}"; then :; fi
            terminate_pi_startup_process_group
        fi
    ) &
    PI_STARTUP_WATCHDOG_PID=$!

    local rc=0 timed_out=0 first_error=""
    if wait "${PI_STARTUP_PID}"; then
        rc=0
    else
        rc=$?
    fi
    if [[ -f "${timeout_marker}" ]]; then timed_out=1; fi
    if (( timed_out == 1 )); then
        if wait "${PI_STARTUP_WATCHDOG_PID}" 2>/dev/null; then :; fi
    else
        if kill -TERM "${PI_STARTUP_WATCHDOG_PID}" 2>/dev/null; then :; fi
        if wait "${PI_STARTUP_WATCHDOG_PID}" 2>/dev/null; then :; fi
    fi
    PI_STARTUP_WATCHDOG_PID=""
    PI_STARTUP_PID=""

    if ! cat "${output}" >> "${HUMAN_LOG}"; then
        log_event "ERROR" "gentle-ai" "pi_startup_failed" \
            "Could not append the pi startup output to the human log" 1 \
            "log=${output};settings=${PI_AGENT_DIR}/settings.json"
        return 1
    fi
    if first_error="$(grep -m 1 -E 'Error:|conflicts' "${output}" 2>/dev/null)"; then :; else
        first_error="none"
    fi
    local result_rc="${rc}"
    if (( timed_out == 1 )); then result_rc=124; fi
    if (( result_rc == 0 )); then
        log_event "INFO" "gentle-ai" "pi_startup_verified" \
            "pi startup verified after the gentle-pi repair" 0 \
            "log=${output};settings=${PI_AGENT_DIR}/settings.json"
        return 0
    fi
    log_event "ERROR" "gentle-ai" "pi_startup_failed" \
        "pi startup verification failed" "${result_rc}" \
        "diagnostic=${first_error};log=${HUMAN_LOG};settings=${PI_AGENT_DIR}/settings.json"
    if (( result_rc == 124 )); then return 124; fi
    return 1
}

# Reinstates the Gentle AI ecosystem configurator. `gentle-ai install` is the
# per-agent/per-IDE selector (Pi, Claude Code, Cursor, Codex, ...) that also
# wires each selected agent's MCP servers, so tools appear under /mcp. The
# configurator is a CORE step: it always runs (interactively with a TTY, or
# non-interactively over the detected agents in CI/pipes) and a failure fails
# the module. For pi we additionally guarantee + verify the first-class
# gentle-pi harness and pi-mcp-adapter. Idempotent: safe to re-run.
mod_gentle_ai() {
    section "gentle-ai"

    # Installers drop the CLI into a PATH dir; make sure the usual ones resolve
    # in this live process so the post-install verification can find it.
    export PATH="${HOME}/.local/bin:${HOME}/go/bin:${PATH}"

    # Repair the harmful quiet-tools switch and the pi settings entry BEFORE anything
    # that can fail: the repair needs nothing from the installer (it only removes the
    # exact shell-profile lines this installer writes and edits settings.json), while a
    # failed `gentle-ai install` used to skip it and leave the switch behind, making a
    # failed run permanently worse than a run that never happened (issue #61).
    handle_quiet_tools_conflict || return 1

    # The per-agent selector and the pi harness both require the gentle-ai CLI
    # itself; a legacy standalone `gga` is NOT enough, so install whenever the
    # gentle-ai CLI is missing even if an old gga is on PATH.
    if ! command -v gentle-ai >/dev/null 2>&1; then
        if [[ "${OS_FAMILY}" == "macos" ]]; then
            run_cmd "gentle-ai" brew tap gentleman-programming/tap
            run_cmd "gentle-ai" brew install gentle-ai
        else
            local installer="${TMP_DIR}/install-gentle-ai.sh"
            run_cmd "gentle-ai" curl -fsSL "${GENTLE_AI_INSTALL}" -o "${installer}"
            [[ -s "${installer}" ]] || {
                log_event "ERROR" "gentle-ai" "installer_missing" "gentle-ai installer is empty" 1 "path=${installer}"
                return 1
            }
            run_cmd "gentle-ai" bash "${installer}"
        fi
    fi

    # Verify the CLI is present (a binary, not an npm tree - command -v + --version
    # is the correct check). Required for both the selector and the pi harness.
    if ! command -v gentle-ai >/dev/null 2>&1; then
        if (( DRY_RUN == 1 )); then
            dry_run_note "gentle-ai" "gentle-ai install (the CLI is not installed yet)"
            return 0
        fi
        log_event "ERROR" "gentle-ai" "binary_missing" "gentle-ai CLI not found on PATH after install" 1
        return 1
    fi
    run_cmd "gentle-ai" --verify gentle-ai --version

    # Detect the agents/IDEs present on this machine (same mapping as mod_ee).
    local agent
    local -a detected_agents=()
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        [[ -d "$(agent_config_dir "${agent}")" ]] && detected_agents+=("${agent}")
    done
    (( ${#detected_agents[@]} == 0 )) && detected_agents=(pi)

    # Per-agent / per-IDE selection + MCP wiring, owned by gentle-ai. This is a
    # core step and must actually run: with a real TTY we launch the interactive
    # selector (run directly - run_cmd would redirect stdout and hide prompts);
    # otherwise we run it non-interactively over the detected agents so CI/pipes
    # never hang. A failure fails the module (no silent downgrade).
    # The configurator downloads the engram binary through the GitHub API. Unauthenticated
    # that is the same 60-requests-per-hour-per-IP quota that already broke this ecosystem
    # twice (issue #60: "download engram binary: fetch latest engram version: GitHub API
    # returned HTTP 403"). The binary reads GITHUB_TOKEN/GH_TOKEN, so pass whichever token
    # this machine has; without one the call stays unauthenticated and the upstream error
    # is reported as before.
    #
    # The token is EXPORTED, never passed as an argument: `run_cmd` logs its argv verbatim
    # into the human log, the console, and the JSONL events, so an `env GITHUB_TOKEN=...`
    # prefix would copy a credential into every artifact this run produces. The previous
    # environment is restored right after the call.
    local gh_token configurator_rc=0
    local prev_github_token="${GITHUB_TOKEN:-}" prev_gh_token="${GH_TOKEN:-}"
    gh_token="$(github_api_token)"
    if [[ -n "${gh_token}" ]]; then
        export GITHUB_TOKEN="${gh_token}" GH_TOKEN="${gh_token}"
        log_event "INFO" "gentle-ai" "github_token_forwarded" \
            "Forwarding a GitHub token to the gentle-ai configurator for its API calls" 0
    else
        log_event "INFO" "gentle-ai" "github_token_absent" \
            "No GitHub token available; the configurator's GitHub API calls stay unauthenticated" 0
    fi

    if [[ -t 0 && -t 1 && "${NONINTERACTIVE}" -eq 0 ]]; then
        if (( DRY_RUN == 1 )); then
            dry_run_note "gentle-ai" "gentle-ai install --scope global"
        else
            log_event "INFO" "gentle-ai" "configurator_start" "Launching gentle-ai install (choose agents/IDEs + MCP)" 0
            gentle-ai install --scope global || configurator_rc=1
        fi
    else
        local agents_csv; agents_csv="$(IFS=,; printf '%s' "${detected_agents[*]}")"
        log_event "INFO" "gentle-ai" "configurator_noninteractive" \
            "No TTY; installing gentle-ai for detected agents" 0 "agents=${agents_csv}"
        run_cmd "gentle-ai" gentle-ai install --scope global --agents "${agents_csv}" || configurator_rc=1
    fi

    # The credential lives in this process's environment only for that call.
    if [[ -n "${gh_token}" ]]; then
        if [[ -n "${prev_github_token}" ]]; then export GITHUB_TOKEN="${prev_github_token}"; else unset GITHUB_TOKEN; fi
        if [[ -n "${prev_gh_token}" ]]; then export GH_TOKEN="${prev_gh_token}"; else unset GH_TOKEN; fi
    fi

    if (( configurator_rc != 0 )); then
        log_event "ERROR" "gentle-ai" "configurator_failed" "gentle-ai install failed" 1
        return 1
    fi
    log_event "INFO" "gentle-ai" "configurator_done" "gentle-ai install completed" 0

    # Guarantee pi reads gentle-ai in its MCP list (/mcp): install the first-class
    # gentle-pi harness and the pi-mcp-adapter bridge, then verify the exact
    # target (pi's own settings file), not a walked resolution.
    if command -v pi >/dev/null 2>&1; then
        run_cmd "gentle-ai" pi install npm:gentle-pi
        # Ensure the project marker exists even for --only gentle-ai before the
        # npm 12 approval/rebuild check (issue #49).
        ensure_npm_remote_sources "${PI_NPM_DIR}"
        # Approve/rebuild gentle-pi's blocked npm 12 install scripts now, in the
        # managed Pi root, so its package-local RDD review binary exists even if a
        # later module fails before the final convergence pass runs.
        approve_npm_install_scripts "${PI_NPM_DIR}" "gentle-ai"
        run_cmd "gentle-ai" pi install npm:pi-mcp-adapter
        local pi_settings="${PI_AGENT_DIR}/settings.json"
        if [[ -f "${pi_settings}" ]] \
            && grep -q '"npm:gentle-pi"' "${pi_settings}" \
            && grep -q '"npm:pi-mcp-adapter"' "${pi_settings}"; then
            log_event "INFO" "gentle-ai" "pi_enabled" \
                "gentle-pi + pi-mcp-adapter registered in pi (verify: /mcp, /gentle-ai:status)" 0
        else
            log_event "ERROR" "gentle-ai" "pi_enable_failed" \
                "gentle-pi and/or pi-mcp-adapter not present in pi settings after install" 1 "expected=${pi_settings}"
            return 1
        fi
    fi

    handle_quiet_tools_conflict || return 1
    verify_pi_startup || return 1

    log_event "INFO" "gentle-ai" "next_steps" "gentle-ai post-install hints" 0
    cat <<'HINT' | tee -a "${HUMAN_LOG}"
  gentle-ai next steps (run yourself, per project):
    1) Set your API keys
    2) Run your selected agent
    3) Try: /sdd-new my-feature   (in pi: /gentle-ai:status, /gentleman:models, /mcp)
  GGA (per project):
    gga init      # inside each repo
    gga install
HINT
}

# --- codex ------------------------------------------------------------------
mod_codex() {
    section "Codex CLI"
    if command -v codex >/dev/null 2>&1; then
        log_event "INFO" "codex" "already_present" "codex already installed" 0
        return
    fi
    if [[ "${OS_FAMILY}" == "macos" ]] && command -v brew >/dev/null 2>&1; then
        run_cmd "codex" brew install --cask codex
    fi
    if ! command -v codex >/dev/null 2>&1; then
        local installer="${TMP_DIR}/install-codex.sh"
        run_cmd "codex" curl -fsSL https://chatgpt.com/codex/install.sh -o "${installer}"
        [[ -s "${installer}" ]] || {
            log_event "ERROR" "codex" "installer_missing" "codex installer is empty" 1 "path=${installer}"
            return 1
        }
        # The vendor installer skips its "Start Codex now?" prompt when this is set.
        run_cmd "codex" env CODEX_NON_INTERACTIVE=1 sh "${installer}"
    fi
    require_command codex
}

# --- antigravity ------------------------------------------------------------
mod_antigravity() {
    section "Antigravity CLI"
    if command -v agy >/dev/null 2>&1; then
        log_event "INFO" "antigravity" "already_present" "agy already installed" 0
        return
    fi
    local installer="${TMP_DIR}/install-antigravity.sh"
    run_cmd "antigravity" curl -fsSL https://antigravity.google/cli/install.sh -o "${installer}"
    [[ -s "${installer}" ]] || {
        log_event "ERROR" "antigravity" "installer_missing" "Antigravity installer is empty" 1 "path=${installer}"
        return 1
    }
    run_cmd "antigravity" bash "${installer}"
    require_command agy
}

# --- opencode ---------------------------------------------------------------
# opencode-pi spawns the CLI with child_process.spawn and no shell. On POSIX the
# npm shim resolves through its shebang, so the PATH entry is enough; probe it
# instead of assuming, and name OPENCODE_PI_BIN when it does not resolve.
opencode_spawn_ok() {
    local bin="$1"
    if (( DRY_RUN == 1 )); then
        dry_run_note "opencode" "spawn ${bin} --version"
        return 0
    fi
    OPENCODE_PI_SPAWN_PROBE="${bin}" node -e \
        'const {spawnSync}=require("node:child_process");const r=spawnSync(process.env.OPENCODE_PI_SPAWN_PROBE||"opencode",["--version"],{stdio:"ignore"});process.exit(!r.error&&r.status===0?0:1)' \
        >/dev/null 2>&1
}

verify_opencode_spawn() {
    if (( DRY_RUN == 1 )); then
        dry_run_note "opencode" "node spawnSync ${OPENCODE_PI_BIN:-opencode} --version"
        return 0
    fi
    if ! command -v node >/dev/null 2>&1; then
        log_event "WARN" "opencode" "spawn_unverified" "node not found; cannot verify the opencode-pi spawn path" 0
        return 0
    fi
    local bin="${OPENCODE_PI_BIN:-opencode}"
    if opencode_spawn_ok "${bin}"; then
        log_event "INFO" "opencode" "spawn_ok" "opencode is spawnable without a shell (opencode-pi requirement)" 0 "bin=${bin}"
    else
        log_event "WARN" "opencode" "spawn_failed" "opencode is not spawnable without a shell; set OPENCODE_PI_BIN for the opencode-pi extension" 0 "bin=${bin}"
    fi
    return 0
}

# The opencode installer drops the binary in ${HOME}/.opencode/bin and appends
# that dir to the shell rc, so the current non-interactive process cannot see it.
# Resolve the directory the installer used and export it before verifying, or the
# require_command below fails with 127 on a fresh machine.
refresh_opencode_path() {
    local dir
    for dir in "${HOME}/.opencode/bin" "${XDG_BIN_HOME:-}" "${HOME}/.local/bin"; do
        [[ -n "${dir}" && -x "${dir}/opencode" ]] || continue
        case ":${PATH}:" in
            *":${dir}:"*) ;;
            *)
                export PATH="${dir}:${PATH}"
                log_event "INFO" "opencode" "path_refreshed" \
                    "Added the opencode install dir to PATH for this run" 0 "dir=${dir}"
                ;;
        esac
        return 0
    done
    return 1
}

mod_opencode() {
    section "opencode"
    if command -v opencode >/dev/null 2>&1; then
        log_event "INFO" "opencode" "already_present" "opencode already installed" 0
    else
        if [[ "${OS_FAMILY}" == "macos" ]]; then
            run_cmd "opencode" brew install anomalyco/tap/opencode
        else
            if (( DRY_RUN == 1 )); then
                dry_run_note "opencode" \
                    "curl https://opencode.ai/install + bash install-opencode.sh (with --version when a GitHub token is available), then npm install -g opencode-ai when it fails"
            else
                local installer="${TMP_DIR}/install-opencode.sh"
                local release_json="${TMP_DIR}/opencode-release.json"
                local token version="" vendor_installed=0
                token="$(github_api_token)"

                # The vendor installer resolves its release through the
                # unauthenticated GitHub API, which answers 403 under rate limiting
                # and then reports "Failed to fetch version information". A token
                # moves that lookup here and the installer skips its own; without a
                # token the plain install is still attempted, because the rate limit
                # is the only thing that made it fail.
                if [[ -n "${token}" ]]; then
                    local api_headers="${TMP_DIR}/opencode-github-headers"
                    # The token stays out of run_cmd's command display: curl reads the header file.
                    ( umask 077; printf '%s\n' \
                        "Authorization: Bearer ${token}" \
                        'Accept: application/vnd.github+json' > "${api_headers}" )
                    if run_cmd "opencode" --optional curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
                        --header "@${api_headers}" \
                        "https://api.github.com/repos/anomalyco/opencode/releases/latest" \
                        -o "${release_json}"; then
                        if [[ -s "${release_json}" ]]; then
                            capture_cmd version "opencode" --optional sed -n \
                                's/.*"tag_name": *"v\([^\"]*\)".*/\1/p' "${release_json}" || version=""
                        else
                            log_event "WARN" "opencode" "github_api_empty" \
                                "GitHub returned no opencode release metadata; leaving the lookup to the vendor installer" 0
                        fi
                    else
                        log_event "WARN" "opencode" "github_api_failed" \
                            "Could not fetch opencode release metadata; leaving the lookup to the vendor installer" 0
                    fi
                else
                    log_event "INFO" "opencode" "github_api_unauthenticated" \
                        "No GitHub API token available; the vendor installer does its own release lookup" 0
                fi

                local -a vendor_args=()
                [[ -n "${version}" ]] && vendor_args=(--version "${version}")
                if run_cmd "opencode" --optional curl -fsSL https://opencode.ai/install -o "${installer}" \
                    && [[ -s "${installer}" ]]; then
                    if run_cmd "opencode" --optional bash "${installer}" "${vendor_args[@]}"; then
                        if refresh_opencode_path && command -v opencode >/dev/null 2>&1; then
                            vendor_installed=1
                            log_event "INFO" "opencode" "vendor_install_succeeded" \
                                "Installed opencode with the vendor installer" 0 "version=${version:-latest}"
                        else
                            log_event "WARN" "opencode" "vendor_install_unresolved" \
                                "Vendor installer completed but opencode was not found; using the npm registry fallback" 0
                        fi
                    else
                        log_event "WARN" "opencode" "vendor_install_failed" \
                            "Vendor installer failed; using the npm registry fallback" 0
                    fi
                else
                    log_event "WARN" "opencode" "installer_unavailable" \
                        "Could not download the vendor installer; using the npm registry fallback" 0 \
                        "path=${installer}"
                fi

                if (( vendor_installed == 0 )); then
                    log_event "INFO" "opencode" "npm_fallback" "Installing opencode from the npm registry" 0
                    require_command npm
                    local npm_version npm_major
                    capture_cmd npm_version "opencode" npm --version
                    npm_major="${npm_version%%.*}"
                    if [[ "${npm_major}" =~ ^[0-9]+$ ]] && (( npm_major >= 12 )); then
                        run_cmd "opencode" npm install -g opencode-ai --allow-scripts=opencode-ai
                    else
                        run_cmd "opencode" npm install -g opencode-ai
                    fi
                    log_event "INFO" "opencode" "npm_install_succeeded" \
                        "Installed opencode from the npm registry" 0
                fi
            fi
        fi
        if (( DRY_RUN == 0 )) && ! refresh_opencode_path; then
            log_event "WARN" "opencode" "path_unresolved" \
                "opencode did not resolve on PATH after the installer; require_command will report it" 0
        fi
        require_command opencode
    fi
    verify_opencode_spawn

    log_event "INFO" "opencode" "zen_hint" "OpenCode Go / Zen provider hint" 0
    cat <<'HINT' | tee -a "${HUMAN_LOG}"
  OpenCode Go (paid) is hosted-model access; after install run: opencode auth login
  The SAME key works in pi.dev (no lock-in) - add a custom provider in pi:
    pi.registerProvider("opencode-go", {
      baseUrl: "https://opencode.ai/zen/v1",
      apiKey: "$OPENCODE_API_KEY",
      authHeader: true,
      api: "openai-completions",
      models: [ /* e.g. your Go plan model ids */ ]
    });
  or run  /provider add  inside pi. Docs: https://pi.dev/docs/latest/custom-provider
HINT
}

# --- cockpit-tools (GUI, optional) ------------------------------------------
mod_cockpit() {
    section "cockpit-tools (GUI)"
    log_event "INFO" "cockpit" "license_notice" \
        "cockpit-tools is a desktop GUI app under CC BY-NC-SA 4.0 (non-commercial)" 0

    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_optional "cockpit" brew tap "${COCKPIT_REPO}" "https://github.com/${COCKPIT_REPO}"
        run_optional "cockpit" brew install --cask cockpit-tools
        return
    fi

    # Linux: fetch the latest .deb (apt/dpkg) or .rpm (dnf) from GitHub Releases.
    local release_json="${TMP_DIR}/cockpit-release.json"
    local token api_headers
    token="$(github_api_token)"
    if [[ -n "${token}" ]]; then
        # Keep the token out of run_optional's command display; curl reads the headers from this file.
        # A dry run writes nothing, so the file is only created for a real request.
        api_headers="${TMP_DIR}/cockpit-github-headers"
        if (( DRY_RUN == 0 )); then
            ( umask 077; printf '%s\n' \
                "Authorization: Bearer ${token}" \
                'Accept: application/vnd.github+json' > "${api_headers}" )
        fi
        run_optional "cockpit" curl -fsSL --header "@${api_headers}" \
            "https://api.github.com/repos/${COCKPIT_REPO}/releases/latest" -o "${release_json}"
    else
        log_event "INFO" "cockpit" "github_api_unauthenticated" \
            "No GitHub API token available; trying the unauthenticated release lookup" 0
        run_optional "cockpit" curl -fsSL -H 'Accept: application/vnd.github+json' \
            "https://api.github.com/repos/${COCKPIT_REPO}/releases/latest" -o "${release_json}"
    fi
    if [[ ! -s "${release_json}" ]]; then
        if (( DRY_RUN == 1 )); then
            # Nothing was fetched, so the asset steps below have no input to plan.
            dry_run_note "cockpit" "the release metadata above decides which package is downloaded"
            return 0
        fi
        log_event "WARN" "cockpit" "release_unavailable" "Could not fetch cockpit-tools release metadata"
        return
    fi

    local asset_pat=""
    case "${PM}" in
        apt-get) asset_pat='amd64[^"]+\.deb|x86_64[^"]+\.deb|_amd64\.deb' ;;
        dnf|zypper) asset_pat='x86_64[^"]+\.rpm|\.rpm' ;;
        *) asset_pat='\.AppImage' ;;
    esac

    local asset_candidates url
    if ! asset_candidates="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' "${release_json}")"; then
        log_event "WARN" "cockpit" "asset_parse_failed" "Could not parse cockpit-tools release assets"
        return 0
    fi

    if ! url="$(printf '%s\n' "${asset_candidates}" \
        | cut -d '"' -f4 | grep -iE "${asset_pat}" | sed -n '1p')"; then
        log_event "WARN" "cockpit" "no_matching_asset" \
            "No matching cockpit-tools asset for ${PM}; download manually from GitHub Releases"
        return 0
    fi

    local installer="${TMP_DIR}/cockpit-asset"
    run_optional "cockpit" curl -fsSL "${url}" -o "${installer}"
    if [[ ! -s "${installer}" ]]; then
        log_event "WARN" "cockpit" "download_unavailable" "Could not download the selected cockpit-tools asset"
        return 0
    fi

    case "${PM}" in
        apt-get) run_optional "cockpit" sudo apt-get install -y "${installer}" ;;
        dnf)     run_optional "cockpit" sudo dnf install -y "${installer}" ;;
        zypper)  run_optional "cockpit" sudo zypper --non-interactive install "${installer}" ;;
        *)
            local dest="${HOME}/.local/bin/cockpit-tools.AppImage"
            if (( DRY_RUN == 1 )); then
                dry_run_note "cockpit" "${HOME}/.local/bin"
            else
                mkdir -p "${HOME}/.local/bin"
            fi
            run_optional "cockpit" install -Dm755 "${installer}" "${dest}"
            log_event "INFO" "cockpit" "appimage_installed" "AppImage placed" 0 "path=${dest}"
            ;;
    esac
}

# --- rotator (opt-in: tuxevil-rotator multi-account gateway) -----------------

# Register the gateway with the machine's own autostart so it survives a reboot: a
# systemd --user unit where the machine has one, and nothing anywhere else (macOS and
# containers fall back to the detached start below). Enabling without --now is
# deliberate: the process is started by its own step, and only when nothing answers the
# port, so an already-running gateway is never doubled.
#
# Returns 0 for every expected outcome: a machine without a user manager, or one that
# refuses the enable, is logged and the caller still starts the gateway by other means.
# A failed mkdir or unit write is NOT swallowed, because this module is opt-in and
# installing a unit nobody can start is worse than failing loudly.
# The unit bounds its own restart loop: while no account is logged in the gateway
# exits at once, and Restart=on-failure would respawn it every 5s forever.
ensure_rotator_unit() {
    # XDG_CONFIG_HOME is not set on every distro or session, so the standard default
    # stays the fallback; the user manager reads the same path.
    local unit_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
    local unit="${unit_dir}/tuxevil-rotator.service"
    local bin_path

    if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
        log_event "INFO" "rotator" "service_skipped" \
            "No working systemctl --user session; the gateway is only started as a detached process" 0
        return 0
    fi
    bin_path="$(command -v tuxevil-rotator)"
    if (( DRY_RUN == 1 )); then
        dry_run_note "rotator" "${unit_dir} + ${unit}"
        return 0
    fi
    mkdir -p "${unit_dir}"
    # Rewritten on every run so a moved binary or a stale unit converges here.
    cat >"${unit}" <<UNIT
[Unit]
Description=tuxevil-rotator multi-account Gemini/Antigravity gateway
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
ExecStart="${bin_path}" start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
    if run_cmd "rotator" systemctl --user enable tuxevil-rotator.service; then
        log_event "INFO" "rotator" "service_enabled" \
            "tuxevil-rotator is enabled as a systemd user service and starts at boot" 0 "unit=${unit}"
        return 0
    fi
    log_event "WARN" "rotator" "service_enable_failed" \
        "systemd user unit could not be enabled; the gateway is started as a detached process only" 0 "unit=${unit}"
    return 0
}

# Start the gateway in the background and leave the proof of that start to the caller's
# probe. The systemd unit is preferred because it also restarts the gateway when it
# dies; anywhere else (macOS, WSL without systemd, containers) the process is detached
# from this installer instead.
start_rotator_gateway() {
    local log_file="$1"
    if (( DRY_RUN == 1 )); then
        dry_run_note "rotator" "start tuxevil-rotator gateway"
        return 0
    fi

    # A unit that exhausted its start limit stays failed and refuses every later start
    # until that rate-limit state is cleared, so clear it before asking again. A machine
    # without systemctl never wrote a unit, so it has no start limit to clear.
    if command -v systemctl >/dev/null 2>&1; then
        run_optional "rotator" systemctl --user reset-failed tuxevil-rotator.service
    fi
    if systemctl --user start tuxevil-rotator.service >/dev/null 2>&1; then
        log_event "INFO" "rotator" "service_started" "tuxevil-rotator started through the systemd user unit" 0 "unit=tuxevil-rotator.service"
        return 0
    fi
    # macOS has no setsid and a shell without job control refuses disown; setsid or nohup
    # has already detached the process, so a refused disown is informational.
    if command -v setsid >/dev/null 2>&1; then
        setsid nohup tuxevil-rotator start >>"${log_file}" 2>&1 &
    else
        nohup tuxevil-rotator start >>"${log_file}" 2>&1 &
    fi
    if ! disown 2>/dev/null; then
        log_event "INFO" "rotator" "disown_unavailable" \
            "This shell cannot disown jobs; setsid or nohup already detached the gateway" 0
    fi
    log_event "INFO" "rotator" "gateway_spawned" "tuxevil-rotator started in the background" 0 "log=${log_file}"
    return 0
}
mod_rotator() {
    section "tuxevil-rotator gateway"
    # Detect a desktop cockpit-tools data dir by marker file only; never read tokens.
    local -a candidates=(
        "${HOME}/.antigravity_cockpit"
        "${HOME}/.local/share/cockpit-tools"
        "${HOME}/.config/cockpit-tools"
        "${HOME}/.wizard-ai/cockpit-tools"
        "${HOME}/Library/Application Support/cockpit-tools"
    )
    # Windows-only locations, appended only when set (mirrors the ps1 behavior).
    [[ -n "${APPDATA:-}" ]] && candidates+=("${APPDATA}/cockpit-tools")
    [[ -n "${LOCALAPPDATA:-}" ]] && candidates+=("${LOCALAPPDATA}/cockpit-tools")
    local dir cockpit_dir=""
    for dir in "${candidates[@]}"; do
        if [[ -f "${dir}/accounts.json" || -f "${dir}/account-token.key" ]]; then
            cockpit_dir="${dir}"; break
        fi
    done
    if [[ -n "${cockpit_dir}" ]]; then
        log_event "INFO" "rotator" "cockpit_detected" "cockpit-tools data directory detected" 0 "dir=${cockpit_dir}"
    else
        log_event "INFO" "rotator" "cockpit_absent" "No cockpit-tools data directory detected; the rotator can still use its own accounts" 0
    fi
    # Non-fatal health probe. gw_up drives the background start further below.
    local gw="http://localhost:51200/v1/models" body count gw_up=0
    if body="$(curl -fsS -m 5 -H 'Authorization: Bearer tuxevil' "${gw}" 2>/dev/null)"; then
        # curl -fsS already proved reachability; the count is informational only
        # (awk always exits 0, so no operational failure is masked here).
        count="$(printf '%s' "${body}" | awk '{c+=gsub(/"id"/,"&")} END{print c+0}')"
        gw_up=1
        log_event "INFO" "rotator" "gateway_up" "tuxevil-rotator gateway is reachable" 0 "url=${gw};models=${count}"
    else
        log_event "INFO" "rotator" "gateway_down" "tuxevil-rotator gateway not reachable; starting it in the background" 0 "url=${gw}"
    fi
    # The CLI's undici dependency needs the global File (Node >= 20): on an older runtime
    # it dies with "ReferenceError: File is not defined", so installing it there only
    # produces a gateway that cannot start plus a login hint that cannot work. Check the
    # runtime first and leave the machine untouched instead.
    local node_version="" node_major=""
    if command -v node >/dev/null 2>&1; then
        if capture_cmd node_version "rotator" --optional node --version \
            && [[ "${node_version}" =~ ^v([0-9]+) ]]; then
            node_major="${BASH_REMATCH[1]}"
        fi
    fi
    if [[ -z "${node_major}" ]] || (( node_major < 20 )); then
        log_event "WARN" "rotator" "node_too_old" \
            "tuxevil-rotator not installed: it needs Node.js >= 20 and crashes on older runtimes; install Node.js 20+ (the node module ships 22) and re-run the rotator module" 0 \
            "node=${node_version:-none};minimum=20"
        return 0
    fi
    # Install the CLI idempotently. Never runs login and never writes secrets; the
    # start below is best-effort and never fails the module.
    if command -v tuxevil-rotator >/dev/null 2>&1; then
        log_event "INFO" "rotator" "already_present" "tuxevil-rotator already installed" 0
    else
        run_cmd "rotator" npm install --global tuxevil-rotator
        require_command tuxevil-rotator
    fi
    # Register boot persistence first: enabling the unit or the task never starts a
    # second process, so this is safe whether or not the gateway is already up. The
    # helper logs its own INFO (`service_skipped`) when the machine has neither.
    ensure_rotator_unit
    # Start the gateway only when nothing answers its port: the dotenv Gemini aliases are
    # unusable without it, so a gateway that only ever gets started by hand is the failure
    # this module exists to prevent. The start is proven by the probe below, because a
    # process that dies immediately must be reported, not assumed.
    if (( gw_up == 0 )); then
        local gw_log="${LOG_DIR}/rotator-gateway.log" attempt
        start_rotator_gateway "${gw_log}"
        if (( DRY_RUN == 1 )); then
            log_event "INFO" "rotator" "dry_run_skipped" "Skipped gateway wait; the gateway was not started" 0
        else
            for (( attempt = 1; attempt <= 20; attempt++ )); do
                if body="$(curl -fsS -m 2 -H 'Authorization: Bearer tuxevil' "${gw}" 2>/dev/null)"; then
                    count="$(printf '%s' "${body}" | awk '{c+=gsub(/"id"/,"&")} END{print c+0}')"
                    gw_up=1
                    log_event "INFO" "rotator" "gateway_started" \
                        "tuxevil-rotator answered after the background start" 0 "url=${gw};models=${count}"
                    break
                fi
                sleep 0.5
            done
            if (( gw_up == 0 )); then
                # A gateway with no account exits immediately, so the port never opens and
                # the only place that says so is the CLI's own log (the same file the Pi
                # extension points at); the run-side log only holds the start attempt.
                # Without this the run reports the rotator as installed while the
                # gemini-* aliases stay broken.
                local cli_log="${HOME}/.tuxevil-rotator/gateway.log"
                if grep -qs 'No accounts configured' "${cli_log}" "${gw_log}" 2>/dev/null; then
                    log_event "WARN" "rotator" "accounts_missing" \
                        "tuxevil-rotator has no account configured, so the gateway cannot start; run 'tuxevil-rotator login' in an interactive terminal, then 'tuxevil-rotator start'" 0 \
                        "url=${gw};log=${gw_log}"
                    POST_INSTALL_ACTIONS+=(
                        "rotator: run 'tuxevil-rotator login' in an interactive terminal (it prints a Google OAuth URL and waits for the browser callback on localhost:51121), then 'tuxevil-rotator status' and 'tuxevil-rotator start'"
                    )
                else
                    log_event "WARN" "rotator" "gateway_start_failed" \
                        "tuxevil-rotator did not answer within 10s; check 'systemctl --user status tuxevil-rotator' or ${gw_log}" 0 "url=${gw}"
                fi
            fi
        fi
    fi
    if command -v pi >/dev/null 2>&1; then
        # `pi install` accepts only protocol URLs without the `git:` prefix, so the bare
        # `github:owner/repo` this module used to pass resolved as a local path and failed.
        # A leftover legacy entry from such a run is tolerated by pi (`pi list` skips it)
        # and cannot be removed with `pi remove`, which only matches installed packages.
        local extension_source="git:github.com/darkrei08/pi-cockpit-tools-sync"
        local pi_settings="${PI_AGENT_DIR}/settings.json"
        run_cmd "rotator" pi install "${extension_source}"
        if [[ ! -f "${pi_settings}" ]] || ! grep -Fq "${extension_source}" "${pi_settings}"; then
            log_event "ERROR" "rotator" "pi_extension_missing" "Pi did not register cockpit sync extension" 1 "expected=${pi_settings}"
            return 1
        fi
        log_event "INFO" "rotator" "pi_extension_verified" "Cockpit sync extension registered in Pi" 0 "path=${pi_settings}"
    else
        log_event "INFO" "rotator" "pi_extension_skipped" "pi not found; cockpit sync extension was not installed" 0
    fi
    cat <<'HINT' | tee -a "${HUMAN_LOG}"
      tuxevil-rotator installed. To use the multi-account Gemini/Antigravity gateway:
        tuxevil-rotator login     # add a Google Antigravity account (repeat to add more)
        tuxevil-rotator import    # or bulk-import accounts from a cockpit-tools JSON
        tuxevil-rotator status    # accounts, quotas, and routing state
      setup-ai starts the gateway on http://localhost:51200 in the background, but only
      when nothing is already listening: a systemd user unit on Linux, a logon scheduled
      task on Windows, a detached process otherwise. The Pi extension does the same when
      a session opens and the port is dead.
      Pi reaches it through the 'tuxevil-rotator' provider configured in your dotenv.
      The cockpit sync extension provides /cockpit-sync, /cockpit-provision, and /cockpit-proxy.
      Login is never run by setup-ai and no tokens are read or stored.
HINT
}

# ==============================================================================
# Shell environment
# ==============================================================================

SHELL_ENV_BLOCK='# ==========================================
# AI Dev Toolsuite Environment
# ==========================================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

export BUN_INSTALL="$HOME/.bun"
export GOPATH="$HOME/go"

export PATH="$BUN_INSTALL/bin:$HOME/.pi/bin:$HOME/.local/bin:$GOPATH/bin:$HOME/.cargo/bin:$PATH"'

configure_shell_env() {
    CURRENT_MODULE="shell"
    section "Shell environment"
    local shell_config="${HOME}/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && shell_config="${HOME}/.zshrc"
    [[ "${OS_FAMILY}" == "macos" && -f "${HOME}/.zshrc" ]] && shell_config="${HOME}/.zshrc"

    local marker="# AI Dev Toolsuite Environment"
    if ! grep -Fq "${marker}" "${shell_config}" 2>/dev/null; then
        if (( DRY_RUN == 1 )); then
            dry_run_note "shell" "${shell_config}"
        else
            printf '\n%s\n' "${SHELL_ENV_BLOCK}" >> "${shell_config}"
        fi
        log_event "INFO" "shell" "environment_added" "Shell env added" 0 "file=${shell_config}"
    else
        log_event "INFO" "shell" "environment_exists" "Shell env already present" 0 "file=${shell_config}"
    fi
}

# ==============================================================================
# Quality gates (run only for modules that were selected)
# ==============================================================================

quality_gates() {
    if (( DRY_RUN == 1 )); then
        log_event "INFO" "quality" "dry_run_skipped" "Quality gates verify an installed state; a dry run installs nothing" 0
        return 0
    fi
    CURRENT_MODULE="quality"
    section "Quality gates"
    run_cmd "quality" --verify bash -n "${BASH_SOURCE[0]}"

    is_selected node && { run_cmd "quality" --verify node --version; run_cmd "quality" --verify npm --version; }
    is_selected bun && run_cmd "quality" --verify bun --version
    if is_selected pi; then
        require_command pi
        run_cmd "quality" --verify pi --no-extensions --version
    fi

    if is_selected node || is_selected pi-workflows; then
        assert_node_minimum
    fi

    if is_selected pi-workflows; then
        local workflow_pkg="${PI_EXTENSIONS_DIR}/node_modules/pi-extensible-workflows/package.json"
        if [[ ! -f "${workflow_pkg}" ]]; then
            log_event "ERROR" "quality" "workflow_package_missing" \
                "pi-extensible-workflows package.json missing from extensions dir" 1 \
                "expected_path=${workflow_pkg}"
            exit 1
        fi
        run_cmd "quality" --verify node -e \
            'const fs=require("fs"); const path=process.argv[1]; const pkg=JSON.parse(fs.readFileSync(path,"utf8")); console.log("VERSION="+pkg.version)' \
            "${workflow_pkg}"
    fi

    local -a target_agents=()
    local agent sk
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        [[ -d "$(agent_config_dir "${agent}")" ]] && target_agents+=("${agent}")
    done
    (( ${#target_agents[@]} == 0 )) && target_agents=(pi)

    if is_selected ee; then
        verify_skill_for_agents "quality" "${ENGINEERING_EXCELLENCE_SKILL}" "${target_agents[@]}"
        log_event "INFO" "quality" "ee_gate_passed" \
            "Engineering Excellence skill verified for every targeted agent" 0
    fi

    if is_selected skills; then
        for sk in "${UPSTREAM_SKILL_NAMES[@]}"; do
            verify_skill_for_agents "quality" "${sk}" "${target_agents[@]}"
        done
        log_event "INFO" "quality" "skills_gate_passed" \
            "All upstream skills verified for every targeted agent" 0
    fi

    if is_selected gentle-ai; then
        # The module requires the gentle-ai CLI specifically; a legacy standalone
        # gga cannot prove the per-agent/MCP configuration ran.
        if ! command -v gentle-ai >/dev/null 2>&1; then
            log_event "ERROR" "quality" "gentle_ai_missing" \
                "gentle-ai CLI not found on PATH after install" 1
            exit 1
        fi
        if command -v pi >/dev/null 2>&1; then
            local gentle_settings="${PI_AGENT_DIR}/settings.json"
            if [[ ! -f "${gentle_settings}" ]] \
                || ! grep -q '"npm:gentle-pi"' "${gentle_settings}" \
                || ! grep -q '"npm:pi-mcp-adapter"' "${gentle_settings}"; then
                log_event "ERROR" "quality" "gentle_pi_missing" \
                    "gentle-pi and/or pi-mcp-adapter not registered in pi settings" 1 "expected=${gentle_settings}"
                exit 1
            fi
            log_event "INFO" "quality" "gentle_ai_gate_passed" \
                "gentle-ai verified (CLI present; gentle-pi + pi-mcp-adapter registered in pi)" 0
        else
            # No pi on PATH: pi MCP wiring is genuinely not applicable, so do not
            # claim it was registered.
            log_event "INFO" "quality" "gentle_ai_gate_passed" \
                "gentle-ai CLI verified; pi not present, so pi MCP wiring was not required" 0
        fi
    fi

    log_event "INFO" "quality" "gates_done" "Quality gates completed for selected modules"
}

# ==============================================================================
# Uninstall catalog and removers
# ==============================================================================

uninstall_path_in_home() {
    local path="$1"
    if [[ "${HOME}" == "/" ]]; then
        [[ "${path}" == /* ]]
    else
        [[ "${path}" == "${HOME}" || "${path}" == "${HOME}/"* ]]
    fi
}

uninstall_protected() {
    local target="$1" candidate dir resolved
    # Both the literal and the resolved form on both sides: ~/.pi/agent can itself be a
    # symlink (an older dotenv made it one), and a comparison that only resolves would
    # miss the literal target this guard exists to refuse, while one that only compares
    # literally would miss a catalog entry that reaches the same directory through a link.
    local -a targets=("${target}")
    local -a dirs=("${PI_AGENT_DIR}")
    if resolved="$(uninstall_resolve_link "${target}" 2>/dev/null)"; then
        targets+=("${resolved}")
    fi
    if resolved="$(uninstall_resolve_link "${PI_AGENT_DIR}" 2>/dev/null)"; then
        dirs+=("${resolved}")
    fi
    for dir in "${dirs[@]}"; do
        for candidate in "${dir}" "${dir}/auth.json" "${dir}/sessions"; do
            for target in "${targets[@]}"; do
                if [[ "${target}" == "${candidate}" || "${candidate}" == "${target}/"* ]]; then
                    log_event "ERROR" "uninstall" "protected_target" \
                        "Refusing to remove a protected pi path" 1 "target=${target};protected=${candidate}"
                    printf 'ERROR: refusing protected uninstall target: %s\n' "${target}" >&2
                    return 1
                fi
            done
        done
    done
}

uninstall_resolve_link() {
    local target="$1" resolved
    if resolved="$(readlink -f -- "${target}" 2>/dev/null)"; then
        printf '%s\n' "${resolved}"
        return 0
    fi
    if resolved="$(realpath "${target}" 2>/dev/null)"; then
        printf '%s\n' "${resolved}"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1 \
        && resolved="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${target}" 2>/dev/null)"; then
        printf '%s\n' "${resolved}"
        return 0
    fi
    return 1
}

# The uninstall's generic removers reuse remove_line_from_file above: one
# implementation, one contract (0 removed, 1 nothing to remove, 2 could not
# rewrite), and its symlink guard and same-filesystem swap apply here too.

# One catalog only: every line has kind|module|target|flags|detail.
uninstall_catalog() {
    printf 'path|node|%s|d|\n' "${HOME}/.nvm"
    printf 'path|node|/usr/local/bin/node|-|\n'
    printf 'path|node|/usr/local/bin/npm|-|\n'
    printf 'path|bun|%s|d|\n' "${HOME}/.bun"
    printf 'path|pi|%s|-|\n' "${HOME}/.pi/bin/pi"
    printf 'path|pi|%s|-|\n' "${HOME}/.pi/agent/npm"
    printf 'path|pi|%s|-|\n' "${HOME}/.pi/agent/extensions/node_modules"
    printf 'path|pi|%s|-|\n' "${HOME}/.pi/agent/extensions/package.json"
    printf 'path|pi|%s|-|\n' "${HOME}/.pi/agent/extensions/.npmrc"
    printf 'pi-package|pi-workflows|npm:pi-extensible-workflows|-|\n'
    printf 'pi-package|gentle-ai|npm:gentle-pi|-|\n'
    printf 'pi-package|gentle-ai|npm:pi-mcp-adapter|-|\n'
    printf 'shell-rc-line|gentle-ai|export GENTLE_PI_QUIET_TOOLS=0|-|\n'
    printf 'env-file-line|gentle-ai|%s|-|GENTLE_PI_QUIET_TOOLS=0\n' \
        "${HOME}/.config/environment.d/50-gentle-pi.conf"
    printf 'pi-package|rotator|git:github.com/darkrei08/pi-cockpit-tools-sync|-|\n'
    printf 'npm-global|rotator|tuxevil-rotator|-|\n'
    printf 'systemd-unit|rotator|tuxevil-rotator.service|-|\n'
    printf 'path|rotator|%s|d|\n' "${HOME}/.tuxevil-rotator"
    printf 'appimage|cockpit|%s|-|\n' "${HOME}/.local/bin/cockpit-tools.AppImage"
    printf 'path|dotenv|%s|d|\n' "${DOTENV_DIR}"

    local agent root skill
    for skill in "${UPSTREAM_SKILL_NAMES[@]}"; do
        for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
            root="$(agent_skill_root "${agent}")"
            printf 'path|skills|%s/%s|-|\n' "${root}" "${skill}"
        done
        printf 'path|skills|%s/%s|-|\n' "${HOME}/.agents/skills" "${skill}"
    done
    skill="${ENGINEERING_EXCELLENCE_SKILL}"
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        root="$(agent_skill_root "${agent}")"
        printf 'path|ee|%s/%s|-|\n' "${root}" "${skill}"
    done
    printf 'path|ee|%s/%s|-|\n' "${HOME}/.agents/skills" "${skill}"

    local manifest line
    if manifest="$(pi_packages_manifest)"; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "${line}" ]] && continue
            [[ "$(pi_package_id "${line}")" == "$(pi_package_id 'npm:pi-extensible-workflows')" ]] && continue
            printf 'pi-package|pi-packages|%s|-|\n' "${line}"
        done < "${manifest}"
    fi

    local shell_line
    while IFS= read -r shell_line || [[ -n "${shell_line}" ]]; do
        [[ -n "${shell_line}" ]] || continue
        printf 'shell-rc-line|shell|%s|-|\n' "${shell_line}"
    done <<< "${SHELL_ENV_BLOCK}"
}

uninstall_remove_path() {
    local target="$1" flags="$2" resolved
    uninstall_protected "${target}" || return 1
    if [[ ! -e "${target}" && ! -L "${target}" ]]; then
        printf 'skipped (not present): %s\n' "${target}"
        return 0
    fi
    if [[ "${flags}" == "d" && "${UNINSTALL_PURGE}" != 1 ]]; then
        printf 'skipped (destructive, needs --purge): %s\n' "${target}"
        return 0
    fi
    if ! uninstall_path_in_home "${target}"; then
        if [[ ! -L "${target}" ]] \
            || ! resolved="$(uninstall_resolve_link "${target}")" \
            || ! uninstall_path_in_home "${resolved}"; then
            printf 'skipped (not owned by this suite): %s\n' "${target}"
            return 0
        fi
    fi
    if (( DRY_RUN == 1 )); then
        printf 'would remove: %s\n' "${target}"
        return 0
    fi
    if rm -rf -- "${target}"; then
        printf 'removed: %s\n' "${target}"
    else
        log_event "ERROR" "uninstall" "path_remove_failed" \
            "Could not remove catalogued path" 1 "target=${target}"
        return 1
    fi
}

uninstall_remove_appimage() {
    local target="$1"
    uninstall_protected "${target}" || return 1
    if [[ ! -e "${target}" && ! -L "${target}" ]]; then
        printf 'skipped (not present): %s\n' "${target}"
        return 0
    fi
    if (( DRY_RUN == 1 )); then
        printf 'would remove: %s\n' "${target}"
        return 0
    fi
    if rm -f -- "${target}"; then
        printf 'removed: %s\n' "${target}"
    else
        log_event "ERROR" "uninstall" "appimage_remove_failed" \
            "Could not remove catalogued AppImage" 1 "target=${target}"
        return 1
    fi
}

uninstall_remove_npm_global() {
    local target="$1" npm_root
    if ! command -v npm >/dev/null 2>&1; then
        log_event "WARN" "uninstall" "npm_missing" \
            "npm is unavailable; global package left behind" 0 "package=${target}"
        printf 'skipped (npm unavailable): %s\n' "${target}"
        return 0
    fi
    if ! npm_root="$(npm root -g 2>/dev/null)"; then
        log_event "WARN" "uninstall" "npm_root_unavailable" \
            "Could not locate the global npm root; package left behind" 0 "package=${target}"
        printf 'skipped (npm root unavailable): %s\n' "${target}"
        return 0
    fi
    if [[ ! -e "${npm_root}/${target}" && ! -L "${npm_root}/${target}" ]]; then
        printf 'skipped (not present): %s\n' "${target}"
        return 0
    fi
    if (( DRY_RUN == 1 )); then
        printf 'would remove: %s\n' "${target}"
        return 0
    fi
    run_cmd "uninstall" npm uninstall -g "${target}" || return 1
    printf 'removed: %s\n' "${target}"
}

uninstall_remove_pi_package() {
    local target="$1" settings="${PI_AGENT_DIR}/settings.json"
    if ! command -v pi >/dev/null 2>&1; then
        log_event "WARN" "uninstall" "pi_missing" \
            "pi is unavailable; settings.json package entry left behind" 0 "package=${target};settings=${settings}"
        printf 'skipped (pi unavailable): %s\n' "${target}"
        return 0
    fi
    # One presence check for the whole catalog: never re-implement the settings.json
    # lookup here, or the two answers drift.
    if ! uninstall_entry_present "pi-package" "${target}" ""; then
        printf 'skipped (not present): %s\n' "${target}"
        return 0
    fi
    if (( DRY_RUN == 1 )); then
        printf 'would remove: %s\n' "${target}"
        return 0
    fi
    run_cmd "uninstall" pi remove "${target}" || return 1
    printf 'removed: %s\n' "${target}"
}

uninstall_remove_systemd_unit() {
    local target="$1" unit="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user/$1"
    if [[ ! -e "${unit}" && ! -L "${unit}" ]]; then
        printf 'skipped (not present): %s\n' "${target}"
        return 0
    fi
    if (( DRY_RUN == 1 )); then
        printf 'would remove: %s\n' "${target}"
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        run_optional "uninstall" systemctl --user disable --now "${target}"
    fi
    if rm -f -- "${unit}"; then
        printf 'removed: %s\n' "${target}"
    else
        log_event "ERROR" "uninstall" "systemd_unit_remove_failed" \
            "Could not remove catalogued systemd user unit" 1 "unit=${unit}"
        return 1
    fi
}

uninstall_remove_shell_rc_line() {
    local target="$1" file rc removed=0 present=0
    for file in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        [[ -f "${file}" ]] || continue
        if (( DRY_RUN == 1 )); then
            grep -Fqx -- "${target}" "${file}" 2>/dev/null && present=1
            continue
        fi
        rc=0
        remove_line_from_file "${file}" "${target}" || rc=$?
        if (( rc == 0 )); then
            removed=1
        elif (( rc > 1 )); then
            log_event "ERROR" "uninstall" "shell_line_remove_failed" \
                "Could not remove an exact shell rc line" "${rc}" "file=${file};line=${target}"
            return "${rc}"
        fi
    done
    if (( DRY_RUN == 1 )); then
        if (( present == 1 )); then
            printf 'would remove: %s\n' "${target}"
        else
            printf 'skipped (not present): %s\n' "${target}"
        fi
        return 0
    fi
    if (( removed == 1 )); then
        printf 'removed: %s\n' "${target}"
    else
        printf 'skipped (not present): %s\n' "${target}"
    fi
}

uninstall_remove_env_file_line() {
    local file="$1" line="$2" rc=0 removed=0
    if [[ ! -f "${file}" ]]; then
        printf 'skipped (not present): %s\n' "${file}"
        return 0
    fi
    if (( DRY_RUN == 1 )); then
        if grep -Fqx -- "${line}" "${file}" 2>/dev/null; then
            printf 'would remove: %s\n' "${file}"
        else
            printf 'skipped (not present): %s\n' "${file}"
        fi
        return 0
    fi
    remove_line_from_file "${file}" "${line}" || rc=$?
    if (( rc == 0 )); then
        removed=1
    elif (( rc > 1 )); then
        log_event "ERROR" "uninstall" "env_line_remove_failed" \
            "Could not remove an exact environment file line" "${rc}" "file=${file};line=${line}"
        return "${rc}"
    fi
    if [[ ! -s "${file}" ]]; then
        if ! rm -f -- "${file}"; then
            log_event "ERROR" "uninstall" "env_file_remove_failed" \
                "Could not remove the empty environment file" 1 "file=${file}"
            return 1
        fi
        removed=1
    fi
    if (( removed == 1 )); then
        printf 'removed: %s\n' "${file}"
    else
        printf 'skipped (not present): %s\n' "${file}"
    fi
}

uninstall_entry_selected() {
    local module="$1"
    if [[ "${module}" == "shell" ]]; then
        (( UNINSTALL_INCLUDE_SHELL == 1 ))
    else
        is_selected "${module}"
    fi
}

uninstall_entry_present() {
    local kind="$1" target="$2" detail="$3" file npm_root
    case "${kind}" in
        path|appimage|systemd-unit)
            [[ -e "${target}" || -L "${target}" ]] ;;
        npm-global)
            if ! command -v npm >/dev/null 2>&1; then
                return 0
            fi
            npm_root="$(npm root -g 2>/dev/null)" || return 0
            [[ -e "${npm_root}/${target}" || -L "${npm_root}/${target}" ]] ;;
        pi-package)
            if ! command -v pi >/dev/null 2>&1; then
                return 0
            fi
            [[ -f "${PI_AGENT_DIR}/settings.json" ]] \
                && grep -Fq "\"${target}\"" "${PI_AGENT_DIR}/settings.json" 2>/dev/null ;;
        shell-rc-line)
            for file in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
                grep -Fqx -- "${target}" "${file}" 2>/dev/null && return 0
            done
            return 1
            ;;
        env-file-line)
            [[ -f "${target}" ]] ;;
        *)
            return 1
            ;;
    esac
}

uninstall_print_inventory() {
    local kind module target flags detail destructive
    printf '\nUninstall inventory:\n'
    printf '%-18s %-18s %-48s %s\n' 'module' 'kind' 'item' 'destructive'
    while IFS='|' read -r kind module target flags detail; do
        uninstall_entry_selected "${module}" || continue
        destructive="no"
        [[ "${flags}" == "d" ]] && destructive="yes"
        printf '%-18s %-18s %-48s %s\n' "${module}" "${kind}" "${target}" "${destructive}"
    done < <(uninstall_catalog)
}

uninstall_print_not_covered() {
    printf '\nDeclared NOT covered (left in place):\n'
    printf '  - base installs distro packages through apt/dnf/pacman/zypper; the package manager owns them.\n'
    printf '  - dotenv runs upstream setup_env.sh, which rsyncs configuration into %s and installs files elsewhere; that payload belongs to the dotenv repository. The catalog only removes the %s checkout, and only with --purge.\n' \
        "${PI_AGENT_DIR}" "${DOTENV_DIR}"
    printf '  - cockpit .deb/.rpm installs and macOS brew --cask installs belong to their package manager; only the AppImage is catalogued.\n'
    printf '  - the opencode vendor installer shell-rc line belongs to the vendor, not this catalog.\n'
    printf '  - %s/settings.json, %s/skills, %s/auth.json and %s/sessions are never removed.\n' \
        "${PI_AGENT_DIR}" "${PI_AGENT_DIR}" "${PI_AGENT_DIR}" "${PI_AGENT_DIR}"
}

run_uninstall() {
    if (( UNINSTALL_YES == 0 && DRY_RUN == 0 )); then
        uninstall_print_inventory
        uninstall_print_not_covered
        printf '\nRemoval needs --yes. Destructive entries additionally need --purge.\n'
        return 2
    fi

    local kind module target flags detail any_present=0 validation_failed=0 rc=0
    while IFS='|' read -r kind module target flags detail; do
        uninstall_entry_selected "${module}" || continue
        if [[ "${kind}" == "path" || "${kind}" == "appimage" ]]; then
            uninstall_protected "${target}" || validation_failed=1
        fi
        if uninstall_entry_present "${kind}" "${target}" "${detail}"; then
            any_present=1
        fi
    done < <(uninstall_catalog)
    if (( validation_failed != 0 )); then
        uninstall_print_not_covered
        return 1
    fi
    if (( any_present == 0 )); then
        printf 'Nothing left to remove.\n'
        uninstall_print_not_covered
        return 0
    fi

    while IFS='|' read -r kind module target flags detail; do
        uninstall_entry_selected "${module}" || continue
        case "${kind}" in
            path)          uninstall_remove_path "${target}" "${flags}" || rc=1 ;;
            appimage)      uninstall_remove_appimage "${target}" || rc=1 ;;
            npm-global)    uninstall_remove_npm_global "${target}" || rc=1 ;;
            pi-package)    uninstall_remove_pi_package "${target}" || rc=1 ;;
            systemd-unit)  uninstall_remove_systemd_unit "${target}" || rc=1 ;;
            shell-rc-line) uninstall_remove_shell_rc_line "${target}" || rc=1 ;;
            env-file-line) uninstall_remove_env_file_line "${target}" "${detail}" || rc=1 ;;
            *)
                log_event "ERROR" "uninstall" "catalog_kind_unknown" \
                    "Unknown uninstall catalog kind" 1 "kind=${kind};target=${target}"
                rc=1
                ;;
        esac
    done < <(uninstall_catalog)
    uninstall_print_not_covered
    (( rc == 0 ))
}

# ==============================================================================
# CLI parsing / module selection
# ==============================================================================

# SELECTED_MODULES / SELECTED_DISPLAY are initialized with the run summary state.

is_selected() {
    local needle="$1" m
    for m in "${SELECTED_MODULES[@]}"; do
        [[ "${m}" == "${needle}" ]] && return 0
    done
    return 1
}

print_list() {
    printf 'AI Dev Suite %s - modules (core = installed by default):\n\n' "${SCRIPT_VERSION}"
    local m tag
    for m in "${MODULE_ORDER[@]}"; do
        if module_is_optional "${m}"; then tag="optional"; else tag="core    "; fi
        printf '  [%s] %-14s %s\n' "${tag}" "${m}" "$(module_desc "${m}")"
    done
    printf '\nUse: --only <csv> | --all | --dry-run | --verbose | (default = core)\n'
    printf 'Lifecycle: --dry-run (plan only) | --uninstall [--yes] [--purge] [--only <csv>]\n'
}

print_help() {
    # Print the header comment (lines 3-27) without external commands: a missing or
    # failing `sed` would be an unchecked external call inside `--help`, and the
    # ERR trap would then abort the script with a confusing error.
    # A read loop instead of `mapfile`: macOS ships bash 3.2, which has no mapfile,
    # and `--help` must work on every platform this installer claims.
    local line lineno=0
    while IFS= read -r line; do
        lineno=$(( lineno + 1 ))
        if (( lineno < 3 )); then continue; fi
        if (( lineno > 27 )); then break; fi
        line="${line#'# '}"
        line="${line#\#}"
        printf '%s\n' "${line}"
    done < "${BASH_SOURCE[0]}"
    printf '\n'
    print_list
}

parse_args() {
    local mode="default" only_csv="" all_requested=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)        mode="all"; all_requested=1; shift ;;
            --only)
                [[ $# -ge 2 ]] || { printf '%s\n' '--only requires a non-empty comma-separated module list.' >&2; exit 2; }
                mode="only"; only_csv="$2"; shift 2
                ;;
            --only=*)     mode="only"; only_csv="${1#*=}"; shift ;;
            --yes|-y)     NONINTERACTIVE=1; UNINSTALL_YES=1; shift ;;
            --dry-run)    DRY_RUN=1; shift ;;
            --uninstall)  UNINSTALL=1; shift ;;
            --purge)      UNINSTALL_PURGE=1; shift ;;
            --verbose|-v)  VERBOSE=1; DEBUG=1; shift ;;
            --list)       print_list; exit 0 ;;
            -h|--help)    print_help; exit 0 ;;
            *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    # Match PowerShell: -All wins whenever it is present, regardless of
    # where it appears relative to --only.
    (( all_requested == 1 )) && mode="all"
    if (( UNINSTALL_PURGE == 1 && UNINSTALL == 0 )); then
        printf '%s\n' '--purge is only valid with --uninstall.' >&2
        exit 2
    fi

    local requested=()
    case "${mode}" in
        all)
            requested=("${MODULE_ORDER[@]}")
            (( UNINSTALL == 1 )) && UNINSTALL_INCLUDE_SHELL=1
            ;;
        only)
            # Split on commas without word-splitting or glob expansion.
            local raw=()
            IFS=',' read -r -a raw <<< "${only_csv}"
            local r
            for r in "${raw[@]}"; do
                # Trim only surrounding whitespace (match PowerShell .Trim());
                # internal whitespace makes the token invalid instead of being
                # silently collapsed (e.g. "co dex" must not become "codex").
                r="${r#"${r%%[![:space:]]*}"}"
                r="${r%"${r##*[![:space:]]}"}"
                [[ -z "${r}" ]] && continue
                if (( UNINSTALL == 1 )) && [[ "${r}" == "shell" ]]; then
                    UNINSTALL_INCLUDE_SHELL=1
                    continue
                fi
                module_desc "${r}" >/dev/null || { printf 'Unknown module: %s\n' "${r}" >&2; exit 2; }
                requested+=("${r}")
            done
            (( ${#requested[@]} > 0 || UNINSTALL_INCLUDE_SHELL == 1 )) || {
                printf '%s\n' '--only requires a non-empty comma-separated module list.' >&2
                exit 2
            }
            ;;
        default)
            local m
            if (( UNINSTALL == 1 )); then
                requested=("${MODULE_ORDER[@]}")
                UNINSTALL_INCLUDE_SHELL=1
            else
                for m in "${MODULE_ORDER[@]}"; do
                    module_is_optional "${m}" && continue
                    requested+=("${m}")
                done
            fi
            ;;
    esac

    # Order the selection by MODULE_ORDER so dependencies run first.
    local m r
    for m in "${MODULE_ORDER[@]}"; do
        for r in "${requested[@]}"; do
            if [[ "${m}" == "${r}" ]]; then
                SELECTED_MODULES+=("${m}")
                break
            fi
        done
    done

    SELECTED_DISPLAY=""
    if (( ${#SELECTED_MODULES[@]} > 0 )); then
        SELECTED_DISPLAY="$(printf '%s ' "${SELECTED_MODULES[@]}")"
    fi
    if (( UNINSTALL == 1 && UNINSTALL_INCLUDE_SHELL == 1 )); then
        SELECTED_DISPLAY="${SELECTED_DISPLAY}shell "
    fi
}

run_module() {
    local name="$1"
    local fn="mod_${name//-/_}"
    if ! declare -F "${fn}" >/dev/null; then
        log_event "WARN" "modules" "unknown_module" "No function for module ${name}"
        return 0
    fi
    CURRENT_MODULE="${name}"
    MODULE_INDEX=$(( MODULE_INDEX + 1 ))
    printf '\n\033[1;37m[%d/%d] %s\033[0m\n' "${MODULE_INDEX}" "${MODULE_TOTAL}" "${name}"
    printf '  %s\n\n' "$(module_desc "${name}")"
    if (( DRY_RUN == 1 )); then
        # A plan must survive a module whose read-backs need a machine that is not
        # provisioned yet, but it must not let a module run past a failed check and
        # then claim a success it did not achieve. So the module keeps errexit inside
        # a subshell, while the ERR trap is dropped on both sides of it: a `||` or
        # `if` context would silently disable errexit inside the subshell, and the
        # parent's trap would abort the whole plan on the subshell's exit status.
        local dry_rc=0
        trap - ERR
        set +e
        ( trap - ERR; set -e; "${fn}" )
        dry_rc=$?
        set -e
        trap 'on_error' ERR
        if (( dry_rc != 0 )); then
            DRY_RUN_PARTIAL="${DRY_RUN_PARTIAL} ${name}"
            log_event "WARN" "modules" "dry_run_module_partial" \
                "Dry run: this module stopped planning early (nothing was run)" "${dry_rc}" "module=${name}"
        fi
        MODULES_OK="${MODULES_OK} ${name}"
        printf '\033[1;35m  PLAN\033[0m  %s planned\n\n' "${name}"
        return 0
    fi
    "${fn}"
    MODULES_OK="${MODULES_OK} ${name}"
    printf '\033[1;32m  OK\033[0m  %s completed\n\n' "${name}"
}

# ==============================================================================
# Main
# ==============================================================================

: > "${HUMAN_LOG}"
: > "${JSONL_LOG}"

# Pre-scan only the display flag so the very first event uses verbose formatting.
for arg in "$@"; do
    case "${arg}" in
        --verbose|-v) VERBOSE=1; DEBUG=1 ;;
    esac
done

log_event "INFO" "bootstrap" "start" "AI Dev Suite setup started" 0 "script_version=${SCRIPT_VERSION}"

parse_args "$@"

# Uninstall is self-contained: it must not require curl, git, sudo, or OS preflight.
if (( UNINSTALL == 1 )); then
    uninstall_rc=0
    run_uninstall || uninstall_rc=$?
    exit "${uninstall_rc}"
fi

# --list / --help exit inside parse_args: only a real run gets a summary.
RUN_ACTIVE=1

CURRENT_MODULE="preflight"
section "Preflight"
require_command bash
detect_os

# WSL: the Windows PATH is removed before anything is resolved, and a HOME on the
# Windows filesystem is refused - running from /mnt would write the Linux config
# into the Windows profile, which is exactly the overlap this guard prevents.
if [[ "${OS_FAMILY}" == "linux" ]] && is_wsl; then
    if [[ "${HOME}" == /mnt/* ]]; then
        log_event "ERROR" "preflight" "wsl_home_on_windows_fs" \
            "HOME points into the Windows filesystem; run setup-ai from a Linux home so the two environments stay separate" 1 \
            "home=${HOME}"
        exit 1
    fi
    strip_windows_interop_path || exit 1
    log_event "INFO" "preflight" "wsl_interop_path_stripped" \
        "Windows interop entries removed from PATH (Linux-native run)" 0 \
        "distro=${WSL_DISTRO_NAME:-unknown}"
fi

# The base module owns bootstrap tools on a clean machine. For explicit
# selections that skip base, fail early because later installers need them.
if ! is_selected base; then
    require_command curl
    require_command git
fi

if [[ "${OS_FAMILY}" == "linux" ]]; then
    require_command sudo
fi

log_event "INFO" "bootstrap" "modules_selected" "Modules queued" 0 "modules=${SELECTED_DISPLAY}"
MODULE_TOTAL="${#SELECTED_MODULES[@]}"
printf '\n\033[1;37mInstallation plan: %d module(s)\033[0m\n' "${MODULE_TOTAL}"
printf '  %s\n\n' "${SELECTED_DISPLAY}"

PI_VERSION=""
for _mod in "${SELECTED_MODULES[@]}"; do
    run_module "${_mod}"
done

# npm 12 install-script approval can only name an installed package, so converge
# after the modules that install pi packages and before the gates that use them.
CURRENT_MODULE="pi-npm"
if is_selected pi || is_selected pi-packages || is_selected gentle-ai || is_selected pi-workflows; then
    if (( DRY_RUN == 1 )); then
        log_event "INFO" "pi-npm" "dry_run_skipped" "Skipped npm install-script approval; nothing was installed" 0
    else
        approve_npm_install_scripts "${PI_NPM_DIR}"
    fi
fi

configure_shell_env
quality_gates

CURRENT_MODULE="report"
if (( DRY_RUN == 1 )); then
    write_report "DRY RUN - nothing installed" 0 "n/a" "n/a" "n/a" "n/a"
    log_event "INFO" "bootstrap" "dry_run_completed" "Dry run completed; nothing was installed or written" 0
    printf '\n\033[1;35m============================================================\033[0m\n'
    printf '\033[1;35m AI Dev Suite dry run completed\033[0m\n'
    printf '\033[1;35m============================================================\033[0m\n'
    printf 'OS family : %s\n' "${OS_FAMILY}"
    printf 'Modules   : %s\n' "${SELECTED_DISPLAY}"
    if [[ -n "${DRY_RUN_PARTIAL}" ]]; then
        printf 'Partial plans :%s (each stopped at its first read-back because the machine is not provisioned yet)\n' "${DRY_RUN_PARTIAL}"
    fi
    printf 'Probes        : version and state reads still run; no command that writes is executed\n'
    printf 'DRY RUN: nothing was installed, nothing was written; re-run without --dry-run to apply\n'
    exit 0
fi
write_report "SUCCESS" 0 "n/a" "n/a" "n/a" "n/a"
report_version REPORT_NODE_VERSION node --version
report_version REPORT_NPM_VERSION npm --version
report_version REPORT_BUN_VERSION bun --version
report_version REPORT_GO_VERSION go version

cat >> "${REPORT_FILE}" <<EOF

## Installed (selected modules)

${SELECTED_DISPLAY}

## Versions

- Node.js: \`${REPORT_NODE_VERSION}\`
- npm: \`${REPORT_NPM_VERSION}\`
- Bun: \`${REPORT_BUN_VERSION}\`
- Pi: \`${PI_VERSION:-n/a}\`
- Go: \`${REPORT_GO_VERSION}\`
EOF

log_event "INFO" "bootstrap" "completed" "AI Dev Suite setup completed successfully" 0 \
    "human_log=${HUMAN_LOG};jsonl_log=${JSONL_LOG};report=${REPORT_FILE}"

printf '\n\033[1;32m============================================================\033[0m\n'
printf '\033[1;32m AI Dev Suite setup completed successfully\033[0m\n'
printf '\033[1;32m============================================================\033[0m\n'
printf 'OS family : %s\n' "${OS_FAMILY}"
printf 'Modules   : %s\n' "${SELECTED_DISPLAY}"
printf 'Human log : %s\n' "${HUMAN_LOG}"
printf 'JSONL log : %s\n' "${JSONL_LOG}"
printf 'Report    : %s\n' "${REPORT_FILE}"
printf '\nNext: restart your shell (or source your rc file) so PATH updates apply.\n'
if (( ${#POST_INSTALL_ACTIONS[@]} > 0 )); then
    for action in "${POST_INSTALL_ACTIONS[@]}"; do
        printf 'Then : %s\n' "${action}"
    done
fi
