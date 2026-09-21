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
source "${TEST_DIR}/resolver.sh"

log_event() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${TEST_DIR}/events.log"
}

run_outside_path_case() {
    local home="${TEST_DIR}/outside-home"
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

run_absent_case() {
    mkdir -p "${TEST_DIR}/absent-home" "${TEST_DIR}/absent-path"
    : > "${TEST_DIR}/events.log"
    export HOME="${TEST_DIR}/absent-home" PATH="${TEST_DIR}/absent-path:/usr/bin:/bin"

    resolve_gentle_ai_cli
    ! command -v gentle-ai >/dev/null 2>&1
}

run_outside_path_case || fail "binary outside PATH was not resolved"
printf 'PASS: binary outside PATH is resolved and logged\n'
run_on_path_case || fail "binary already on PATH was changed or logged"
printf 'PASS: binary already on PATH is left unchanged\n'
run_absent_case || fail "absent binary was incorrectly resolved"
printf 'PASS: absent binary remains unavailable\n'
