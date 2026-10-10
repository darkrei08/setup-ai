#!/usr/bin/env bash
# Behavioral checks for the optional CLIProxyAPI + Keeper Compose module.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-cliproxyapi.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

function_source="$(sed -n '/^mod_cliproxyapi() {/,/^}/p' "${ROOT}/setup-ai.sh")"
capture_source="$(sed -n '/^capture_cmd() {/,/^}/p' "${ROOT}/setup-ai.sh")"
[[ -n "${function_source}" && -n "${capture_source}" ]] || { echo 'FAIL: required setup-ai function is missing' >&2; exit 1; }
eval "${function_source}"
eval "${capture_source}"

DRY_RUN=0
SCRIPT_DIR="${ROOT}"
CLIPROXYAPI_DIR="${TEST_DIR}/stack"
POST_INSTALL_ACTIONS=()
HUMAN_LOG="${TEST_DIR}/human.log"
DOCKER_CALLS="${TEST_DIR}/docker.calls"
RUN_STEPS="${TEST_DIR}/run.steps"
TMP_DIR="${TEST_DIR}/tmp"
VERBOSE=0
RUNNING_SERVICES=""
FAIL_CONFIG_GREP=0
mkdir -p "${TEST_DIR}/bin" "${CLIPROXYAPI_DIR}" "${TMP_DIR}"
: > "${DOCKER_CALLS}"
cat > "${TEST_DIR}/bin/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_CALLS}"
if [[ "$*" == *"ps --status running --services" ]]; then
    printf '%s\n' "${RUNNING_SERVICES}"
elif [[ "$*" == *"ps -a -q" ]]; then
    printf '%s' "${PROJECT_IDS}"
elif [[ "$1" == inspect ]]; then
    printf '%s\n' "${WORKING_DIRS}"
fi
SH
chmod +x "${TEST_DIR}/bin/docker"
PATH="${TEST_DIR}/bin:${PATH}"
PROJECT_IDS=""
WORKING_DIRS=""
export PATH DOCKER_CALLS RUNNING_SERVICES PROJECT_IDS WORKING_DIRS

section() { :; }
grep() {
    if [[ "${FAIL_CONFIG_GREP}" == 1 && "${1:-}" == -Eq ]]; then return 2; fi
    command grep "$@"
}
log_event() { printf '%s|%s|%s\n' "$2" "$3" "$4" >> "${HUMAN_LOG}"; }
dry_run_note() { log_event INFO "$1" dry_run_note "$2"; }
record_step() { :; }
run_cmd() {
    local phase="$1" step=run; shift
    if [[ "${1:-}" == --verify ]]; then step=verify; shift; fi
    printf '%s|%s|%s\n' "${phase}" "${step}" "$*" >> "${RUN_STEPS}"
    "${@}"
}

# An empty directory is seeded with local example templates: placeholders, private modes,
# no Docker invocation, and a second run never overwrites what the user edited.
mod_cliproxyapi
[[ ! -s "${DOCKER_CALLS}" ]] || { echo 'FAIL: Docker ran without a configured stack' >&2; exit 1; }
grep -q 'configuration_seeded' "${HUMAN_LOG}" || { echo 'FAIL: seeding was not logged' >&2; exit 1; }
for f in docker-compose.yml config.yaml keeper.env; do
    [[ -f "${CLIPROXYAPI_DIR}/${f}" ]] || { echo "FAIL: ${f} was not seeded" >&2; exit 1; }
done
command grep -q 'REPLACE_WITH' "${CLIPROXYAPI_DIR}/config.yaml" "${CLIPROXYAPI_DIR}/keeper.env" || { echo 'FAIL: seeded files lost their placeholders' >&2; exit 1; }
[[ "$(stat -c %a "${CLIPROXYAPI_DIR}/config.yaml" 2>/dev/null || stat -f %Lp "${CLIPROXYAPI_DIR}/config.yaml")" == 600 ]] || { echo 'FAIL: seeded config is not private' >&2; exit 1; }
printf 'edited\n' > "${CLIPROXYAPI_DIR}/config.yaml"
: > "${HUMAN_LOG}"
mod_cliproxyapi
[[ "$(cat "${CLIPROXYAPI_DIR}/config.yaml")" == edited ]] || { echo 'FAIL: seeding overwrote a user file' >&2; exit 1; }
if grep -q 'configuration_seeded' "${HUMAN_LOG}"; then echo 'FAIL: nothing was missing but seeding ran' >&2; exit 1; fi
rm -f "${CLIPROXYAPI_DIR}"/*
: > "${DOCKER_CALLS}"

# The Git-backed layout is selectable and seeds a single .env with placeholders.
CLIPROXYAPI_STORAGE=gitstore mod_cliproxyapi
command grep -q 'YOUR_USER' "${CLIPROXYAPI_DIR}/.env" || { echo 'FAIL: gitstore .env was not seeded' >&2; exit 1; }
[[ ! -e "${CLIPROXYAPI_DIR}/config.yaml" ]] || { echo 'FAIL: gitstore seeded local files' >&2; exit 1; }
[[ ! -s "${DOCKER_CALLS}" ]] || { echo 'FAIL: Docker ran for a seeded gitstore layout' >&2; exit 1; }
# A directory that only has .env is detected as gitstore without any variable.
: > "${HUMAN_LOG}"
mod_cliproxyapi
[[ ! -e "${CLIPROXYAPI_DIR}/config.yaml" ]] || { echo 'FAIL: .env-only directory was treated as local' >&2; exit 1; }
# Placeholders in the other layout's files still block start: the compose file may mount them.
printf 'GITSTORE_GIT_URL=private\n' > "${CLIPROXYAPI_DIR}/.env"
printf 'api-keys: [REPLACE_WITH_A_LONG_RANDOM_CLIENT_KEY]\n' > "${CLIPROXYAPI_DIR}/config.yaml"
: > "${DOCKER_CALLS}"
CLIPROXYAPI_STORAGE=gitstore mod_cliproxyapi
if grep -q 'up -d' "${DOCKER_CALLS}"; then echo 'FAIL: stack started with placeholders in the other layout' >&2; exit 1; fi
rm -f "${CLIPROXYAPI_DIR}/config.yaml"
rm -f "${CLIPROXYAPI_DIR}/.env" "${CLIPROXYAPI_DIR}/docker-compose.yml"
if CLIPROXYAPI_STORAGE=bogus mod_cliproxyapi; then echo 'FAIL: invalid storage was accepted' >&2; exit 1; fi
grep -q 'storage_invalid' "${HUMAN_LOG}" || { echo 'FAIL: invalid storage was not logged' >&2; exit 1; }
: > "${DOCKER_CALLS}"

# A directory where a required regular file belongs blocks start before Compose runs.
for layout_case in local:config.yaml local:docker-compose.yml gitstore:.env; do
    rm -rf "${CLIPROXYAPI_DIR}"; mkdir -p "${CLIPROXYAPI_DIR}"
    for f in docker-compose.yml config.yaml keeper.env .env; do printf 'private=1\n' > "${CLIPROXYAPI_DIR}/${f}"; done
    rm -f "${CLIPROXYAPI_DIR}/${layout_case#*:}"; mkdir "${CLIPROXYAPI_DIR}/${layout_case#*:}"
    : > "${DOCKER_CALLS}"; : > "${HUMAN_LOG}"
    if CLIPROXYAPI_STORAGE="${layout_case%%:*}" mod_cliproxyapi; then echo "FAIL: directory at ${layout_case#*:} was accepted" >&2; exit 1; fi
    if grep -q 'up -d' "${DOCKER_CALLS}"; then echo "FAIL: Compose up ran with a directory at ${layout_case#*:}" >&2; exit 1; fi
    grep -q 'config_not_file' "${HUMAN_LOG}" || { echo 'FAIL: non-file config was not logged' >&2; exit 1; }
done
rm -rf "${CLIPROXYAPI_DIR}"; mkdir -p "${CLIPROXYAPI_DIR}"
: > "${DOCKER_CALLS}"

# Dry-run must not invoke Docker, even when configuration files are present.
cat > "${CLIPROXYAPI_DIR}/docker-compose.yml" <<'EOF'
services: {}
EOF
printf 'api-keys: [private]\nremote-management: {secret-key: private}\n' > "${CLIPROXYAPI_DIR}/config.yaml"
printf 'CPA_MANAGEMENT_KEY=private\nLOGIN_PASSWORD=private\n' > "${CLIPROXYAPI_DIR}/keeper.env"
DRY_RUN=1
mod_cliproxyapi
[[ ! -s "${DOCKER_CALLS}" ]] || { echo 'FAIL: dry-run invoked Docker' >&2; exit 1; }

# A configured normal run validates, starts, and reads back the exact Compose project.
DRY_RUN=0
: > "${RUN_STEPS}"
RUNNING_SERVICES=$'cli-proxy-api\ncpa-usage-keeper'
mod_cliproxyapi
expected="${TEST_DIR}/expected.calls"
printf 'compose version\ncompose --project-directory %s -f %s config -q\ncompose --project-directory %s -f %s ps -a -q\ncompose --project-directory %s -f %s up -d\ncompose --project-directory %s -f %s ps --status running --services\n' \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" > "${expected}"
[[ "$(<"${expected}")" == "$(<"${DOCKER_CALLS}")" ]] || { echo 'FAIL: Docker Compose call sequence differs' >&2; exit 1; }
printf 'cliproxyapi|run|docker compose --project-directory %s -f %s config -q\ncliproxyapi|run|docker compose --project-directory %s -f %s up -d\n' \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" \
    "${CLIPROXYAPI_DIR}" "${CLIPROXYAPI_DIR}/docker-compose.yml" > "${TEST_DIR}/expected.steps"
[[ "$(<"${TEST_DIR}/expected.steps")" == "$(<"${RUN_STEPS}")" ]] || { echo 'FAIL: setup-ai run steps differ' >&2; exit 1; }

# Containers of the same project name started from another directory are not ours.
PROJECT_IDS="abc123"
WORKING_DIRS="/elsewhere/cliproxyapi"
: > "${DOCKER_CALLS}"
: > "${HUMAN_LOG}"
if mod_cliproxyapi; then
    echo 'FAIL: foreign Compose project was not refused' >&2
    exit 1
fi
grep -q 'project_conflict' "${HUMAN_LOG}" || { echo 'FAIL: project conflict was not logged' >&2; exit 1; }
if grep -q 'up -d' "${DOCKER_CALLS}"; then
    echo 'FAIL: Compose up ran against a foreign project' >&2
    exit 1
fi
# Our own containers (same working dir) are updated normally.
WORKING_DIRS="${CLIPROXYAPI_DIR}"
RUNNING_SERVICES=$'cli-proxy-api\ncpa-usage-keeper'
: > "${HUMAN_LOG}"
mod_cliproxyapi || { echo 'FAIL: own Compose project was refused' >&2; exit 1; }
PROJECT_IDS=""
WORKING_DIRS=""

# Compose can exit successfully when one service is stopped.
: > "${HUMAN_LOG}"
RUNNING_SERVICES="cli-proxy-api"
if mod_cliproxyapi; then
    echo 'FAIL: stopped services were reported as running' >&2
    exit 1
fi
grep -q 'stack_not_running' "${HUMAN_LOG}" || { echo 'FAIL: stopped services were not reported' >&2; exit 1; }
if grep -q 'stack_started' "${HUMAN_LOG}"; then
    echo 'FAIL: stopped services were reported as started' >&2
    exit 1
fi

# Operational config-read failures abort before Compose starts.
FAIL_CONFIG_GREP=1
: > "${DOCKER_CALLS}"
: > "${HUMAN_LOG}"
if mod_cliproxyapi; then
    echo 'FAIL: configuration read failure was ignored' >&2
    exit 1
fi
grep -q 'configuration_check_failed' "${HUMAN_LOG}" || { echo 'FAIL: configuration read failure was not logged' >&2; exit 1; }
if grep -Eq 'config -q|up -d' "${DOCKER_CALLS}"; then
    echo 'FAIL: Compose started after a configuration read failure' >&2
    exit 1
fi
FAIL_CONFIG_GREP=0

# Docker availability is reported before credential placeholders, matching PowerShell.
printf 'api-keys: [REPLACE_WITH_PRIVATE_KEY]\n' > "${CLIPROXYAPI_DIR}/config.yaml"
mv "${TEST_DIR}/bin/docker" "${TEST_DIR}/bin/docker.disabled"
: > "${DOCKER_CALLS}"
: > "${HUMAN_LOG}"
SAFE_PATH="${PATH}"
PATH="${TEST_DIR}/empty-path"
mod_cliproxyapi
PATH="${SAFE_PATH}"
[[ ! -s "${DOCKER_CALLS}" ]] || { echo 'FAIL: Docker was invoked when unavailable' >&2; exit 1; }
grep -q 'docker_missing' "${HUMAN_LOG}" || { echo 'FAIL: missing Docker was not logged' >&2; exit 1; }
if grep -q 'configuration_placeholder' "${HUMAN_LOG}"; then
    echo 'FAIL: Bash placeholder check ran before the Docker prerequisite check' >&2
    exit 1
fi
if grep -q 'stack_started' "${HUMAN_LOG}"; then
    echo 'FAIL: missing Docker was reported as a started stack' >&2
    exit 1
fi
printf 'PASS: configured, missing-config, and dry-run Compose behavior\n'
