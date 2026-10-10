#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-dotenv-wf.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# Fake minimal logging and run_cmd to isolate link_dotenv_workflow_extensions
DRY_RUN=0
dry_run_note() { :; }
run_cmd() { shift; "$@"; }
log_event() { :; }

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

eval "$(extract_function link_dotenv_workflow_extensions)"

# 1. Setup mock source
SRC_EXT="${TEST_DIR}/source/pi-ext-workflows"
SRC_BARREL="${TEST_DIR}/source/piextworkflows.ts"
mkdir -p "${SRC_EXT}"
touch "${SRC_EXT}/develop-issues.ts"
touch "${SRC_BARREL}"

TARGET_DIR="${TEST_DIR}/live/extensions/pi-ext-workflows"
TARGET_BARREL="${TEST_DIR}/live/extensions/piextworkflows.ts"

# 2. Test initial link creation
link_dotenv_workflow_extensions "${SRC_EXT}" "${TARGET_DIR}" "${SRC_BARREL}" "${TARGET_BARREL}" || fail "Initial link failed"
[[ -L "${TARGET_DIR}" ]] || fail "Target extension dir is not a symlink"
[[ -f "${TARGET_DIR}/develop-issues.ts" ]] || fail "develop-issues.ts not visible via symlink"
[[ -L "${TARGET_BARREL}" ]] || fail "Target barrel is not a symlink"

# 3. Test idempotency (re-running does not fail or nest)
link_dotenv_workflow_extensions "${SRC_EXT}" "${TARGET_DIR}" "${SRC_BARREL}" "${TARGET_BARREL}" || fail "Idempotent re-run failed"
[[ -L "${TARGET_DIR}" ]] || fail "Target extension dir is still a symlink"
[[ ! -e "${TARGET_DIR}/pi-ext-workflows" ]] || fail "Symlink was incorrectly nested on re-run"

# 4. Test protection of existing real directory (must not be deleted)
REAL_TARGET_DIR="${TEST_DIR}/live-real/extensions/pi-ext-workflows"
REAL_BARREL="${TEST_DIR}/live-real/extensions/piextworkflows.ts"
mkdir -p "${REAL_TARGET_DIR}"
touch "${REAL_TARGET_DIR}/develop-issues.ts"
touch "${REAL_TARGET_DIR}/user-custom-file.txt"

link_dotenv_workflow_extensions "${SRC_EXT}" "${REAL_TARGET_DIR}" "${SRC_BARREL}" "${REAL_BARREL}" || fail "Real dir link call failed"
[[ ! -L "${REAL_TARGET_DIR}" ]] || fail "Real directory was converted to symlink"
[[ -f "${REAL_TARGET_DIR}/user-custom-file.txt" ]] || fail "User file in real directory was deleted"

printf 'PASS: dotenv-workflows-link passed all checks\n'
