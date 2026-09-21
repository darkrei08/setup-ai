#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-gentle-ai.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

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
    ' "${ROOT}/setup-ai.sh"
}

# Keep the product function intact while sandboxing its absolute vendor directory.
extract_function resolve_gentle_ai_cli \
    | sed "s#/usr/local/bin#${TEST_DIR}/vendor/bin#g" > "${TEST_DIR}/resolver.sh"
extract_function mod_gentle_ai > "${TEST_DIR}/module.sh"
source "${TEST_DIR}/resolver.sh"
source "${TEST_DIR}/module.sh"

# The extraction brings only the function, but mod_gentle_ai reads the run-summary
# state the installer initialises before any module runs (setup-ai.sh:306-311).
# Mirror it here, or the module dies on an unbound variable under set -u.
STEP_FAILED=0
STEP_FAIL_STEP=""
STEP_FAIL_RC=0
LAST_ERROR_STEP=""
LAST_ERROR_RC=0
RUN_INTERRUPTED=0

log_event() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${TEST_DIR}/events.log"
}

section() { :; }
handle_quiet_tools_conflict() { return 0; }
verify_pi_startup() { return 0; }
agent_config_dir() { printf '%s/missing-agent-config' "${TEST_DIR}"; }
github_api_token() { return 0; }
run_cmd() {
    local phase="$1"
    shift
    if [[ "${phase}" == "gentle-ai" && ( "${1:-}" == "curl" || "${1:-}" == "bash" ) ]]; then
        printf '%s\n' "$*" >> "${TEST_DIR}/installer.calls"
    fi
    return 0
}

DRY_RUN=0
NONINTERACTIVE=1
OS_FAMILY=linux
TMP_DIR="${TEST_DIR}/runtime"
HUMAN_LOG="${TEST_DIR}/human.log"
GENTLE_AI_INSTALL="${TEST_DIR}/installer.sh"
mkdir -p "${TMP_DIR}"
: > "${HUMAN_LOG}"

run_vendor_path_case() {
    local bin_dir="${TEST_DIR}/vendor/bin"
    mkdir -p "${bin_dir}"
    printf '#!/usr/bin/env bash\n' > "${bin_dir}/gentle-ai"
    chmod +x "${bin_dir}/gentle-ai"
    : > "${TEST_DIR}/events.log"
    export HOME="${TEST_DIR}/vendor-home" PATH="${TEST_DIR}/vendor-path:/usr/bin:/bin"

    resolve_gentle_ai_cli
    [[ "$(command -v gentle-ai)" == "${bin_dir}/gentle-ai" ]] || return 1
    [[ "${PATH}" == "${bin_dir}:${TEST_DIR}/vendor-path:/usr/bin:/bin" ]] || return 1
    [[ "$(awk -F'|' '$3 == "cli_resolved" { count++ } END { print count + 0 }' "${TEST_DIR}/events.log")" -eq 1 ]] || return 1
    grep -Fq "directory=${bin_dir}" "${TEST_DIR}/events.log"
}

run_outside_path_case() {
    local home="${TEST_DIR}/outside-home"
    rm -f "${TEST_DIR}/vendor/bin/gentle-ai"
    mkdir -p "${home}/.local/bin" "${TEST_DIR}/outside-path"
    printf '#!/usr/bin/env bash\n' > "${home}/.local/bin/gentle-ai"
    chmod +x "${home}/.local/bin/gentle-ai"
    : > "${TEST_DIR}/events.log"
    export HOME="${home}" PATH="${TEST_DIR}/outside-path:/usr/bin:/bin"

    resolve_gentle_ai_cli
    [[ "$(command -v gentle-ai)" == "${home}/.local/bin/gentle-ai" ]] || return 1
    [[ "${PATH}" == "${home}/.local/bin:${TEST_DIR}/outside-path:/usr/bin:/bin" ]] || return 1
    [[ "$(awk -F'|' '$3 == "cli_resolved" { count++ } END { print count + 0 }' "${TEST_DIR}/events.log")" -eq 1 ]] || return 1
    grep -Fq "directory=${home}/.local/bin" "${TEST_DIR}/events.log"
}

run_on_path_case() {
    local bin_dir="${TEST_DIR}/on-path"
    mkdir -p "${bin_dir}"
    printf '#!/usr/bin/env bash\n' > "${bin_dir}/gentle-ai"
    chmod +x "${bin_dir}/gentle-ai"
    : > "${TEST_DIR}/events.log"
    export HOME="${TEST_DIR}/on-path-home" PATH="${bin_dir}:/usr/bin:/bin"
    local before="${PATH}"

    resolve_gentle_ai_cli
    [[ "$(command -v gentle-ai)" == "${bin_dir}/gentle-ai" ]] || return 1
    [[ "${PATH}" == "${before}" ]] || return 1
    [[ ! -s "${TEST_DIR}/events.log" ]]
}

run_preinstall_guard_case() {
    local bin_dir="${TEST_DIR}/vendor/bin"
    mkdir -p "${bin_dir}"
    printf '#!/usr/bin/env bash\n' > "${bin_dir}/gentle-ai"
    chmod +x "${bin_dir}/gentle-ai"
    : > "${TEST_DIR}/events.log"
    : > "${TEST_DIR}/installer.calls"
    export HOME="${TEST_DIR}/guard-home" PATH="${TEST_DIR}/guard-path:/usr/bin:/bin"

    mod_gentle_ai > "${TEST_DIR}/module.out" 2>&1 || return 1
    mod_gentle_ai > "${TEST_DIR}/module.out" 2>&1 || return 1
    [[ ! -s "${TEST_DIR}/installer.calls" ]]
}

run_absent_case() {
    mkdir -p "${TEST_DIR}/absent-home" "${TEST_DIR}/absent-path"
    : > "${TEST_DIR}/events.log"
    export HOME="${TEST_DIR}/absent-home" PATH="${TEST_DIR}/absent-path:/usr/bin:/bin"

    resolve_gentle_ai_cli
    ! command -v gentle-ai >/dev/null 2>&1
}

run_vendor_path_case || fail "vendor directory binary was not resolved"
printf 'PASS: vendor directory binary is resolved and logged\n'
run_outside_path_case || fail "binary outside PATH was not resolved"
printf 'PASS: binary outside PATH is resolved and logged\n'
run_on_path_case || fail "binary already on PATH was changed or logged"
printf 'PASS: binary already on PATH is left unchanged\n'
run_absent_case || fail "absent binary was incorrectly resolved"
printf 'PASS: absent binary remains unavailable\n'
run_preinstall_guard_case || fail "pre-install guard invoked the vendor installer for an existing binary"
printf 'PASS: pre-install guard skips the vendor installer on repeated runs\n'
