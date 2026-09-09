#!/usr/bin/env bash

# ==============================================================================
# AI Dev Suite - Engineering Excellence Edition
# Version: 2.1.0
#
# Goals:
#   - deterministic installation
#   - explicit dependency resolution
#   - Pi-native package installation
#   - correct Node module resolution for ~/.pi/agent/extensions/*.ts
#   - Engineering Excellence skill
#   - secure structured logging (human + JSONL)
#   - useful failure diagnostics
#   - deterministic quality gates
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="2.1.0"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

HUMAN_LOG="${LOG_DIR}/setup_${RUN_ID}.log"
JSONL_LOG="${LOG_DIR}/setup_${RUN_ID}.jsonl"
REPORT_FILE="${LOG_DIR}/engineering-report_${RUN_ID}.md"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-dev-suite.XXXXXXXX")"

export RUN_ID

DEBUG="${DEBUG:-0}"
PI_WORKFLOW_VERSION="${PI_WORKFLOW_VERSION:-}"

DOTENV_REPO="${DOTENV_REPO:-https://github.com/vekexasia/dotenv.git}"

ENGINEERING_EXCELLENCE_REPO="${ENGINEERING_EXCELLENCE_REPO:-https://github.com/micio86dev/Engineering-Excellence.git}"
ENGINEERING_EXCELLENCE_DIR="${HOME}/.pi/agent/skills/engineering-excellence"

PI_AGENT_DIR="${HOME}/.pi/agent"
PI_EXTENSIONS_DIR="${PI_AGENT_DIR}/extensions"
PI_NPM_DIR="${PI_AGENT_DIR}/npm"

DOTENV_DIR="${HOME}/git/personale/dotenv"
DOTENV_EXT_DIR="${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

cleanup() {
    rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# JSON escaping without Python
#
# This is intentionally pure Bash so logging works BEFORE Python is installed.
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
    local timestamp="$1"
    local level="$2"
    local phase="$3"
    local event="$4"
    local message="$5"
    local return_code="${6:-0}"
    local meta="${7:-}"

    local j_ts
    local j_level
    local j_phase
    local j_event
    local j_message
    local j_meta

    j_ts="$(json_escape "${timestamp}")"
    j_level="$(json_escape "${level}")"
    j_phase="$(json_escape "${phase}")"
    j_event="$(json_escape "${event}")"
    j_message="$(json_escape "${message}")"
    j_meta="$(json_escape "${meta}")"

    {
        printf '{"timestamp":"%s","level":"%s","phase":"%s","event":"%s","message":"%s","return_code":%s,"run_id":"%s","pid":%s' \
            "${j_ts}" \
            "${j_level}" \
            "${j_phase}" \
            "${j_event}" \
            "${j_message}" \
            "${return_code}" \
            "${RUN_ID}" \
            "$$"

        if [[ -n "${meta}" ]]; then
            printf ',"meta":"%s"' "${j_meta}"
        fi

        printf '}\n'
    } >> "${JSONL_LOG}"
}

log_event() {
    local level="$1"
    local phase="$2"
    local event="$3"
    local message="$4"
    local return_code="${5:-0}"
    local meta="${6:-}"

    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    json_log \
        "${timestamp}" \
        "${level}" \
        "${phase}" \
        "${event}" \
        "${message}" \
        "${return_code}" \
        "${meta}"

    local line
    line="${timestamp} [${level}] ${phase} ${event}: ${message}"

    printf '%s\n' "${line}" >> "${HUMAN_LOG}"

    case "${level}" in
        INFO)
            printf '\033[1;34m%s\033[0m\n' "${line}"
            ;;
        WARN)
            printf '\033[1;33m%s\033[0m\n' "${line}"
            ;;
        ERROR)
            printf '\033[1;31m%s\033[0m\n' "${line}"
            ;;
        DEBUG)
            if (( DEBUG == 1 )); then
                printf '\033[0;90m%s\033[0m\n' "${line}"
            fi
            ;;
        *)
            printf '%s\n' "${line}"
            ;;
    esac
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

    log_event \
        "ERROR" \
        "bootstrap" \
        "script_failed" \
        "Setup failed" \
        "${rc}" \
        "line=${line};file=${source_file};function=${function_name};command=${command}"

    write_report \
        "FAILED" \
        "${rc}" \
        "${line}" \
        "${source_file}" \
        "${function_name}" \
        "${command}"

    printf '\n'
    printf '\033[1;31mSETUP FALLITO\033[0m\n'
    printf 'Return code : %s\n' "${rc}"
    printf 'File        : %s\n' "${source_file}"
    printf 'Function    : %s\n' "${function_name}"
    printf 'Line        : %s\n' "${line}"
    printf 'Command     : %s\n' "${command}"
    printf 'Human log   : %s\n' "${HUMAN_LOG}"
    printf 'JSONL log   : %s\n' "${JSONL_LOG}"
    printf 'Report      : %s\n' "${REPORT_FILE}"
    printf '\n'

    exit "${rc}"
}

trap 'on_error' ERR

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

section() {
    log_event "INFO" "section" "start" "$1"
}

require_command() {
    local command="$1"

    if ! command -v "${command}" >/dev/null 2>&1; then
        log_event \
            "ERROR" \
            "preflight" \
            "missing_command" \
            "Required command not found: ${command}" \
            127

        return 127
    fi
}

run_cmd() {
    local phase="$1"
    shift

    local display
    printf -v display '%q ' "$@"

    log_event \
        "INFO" \
        "${phase}" \
        "command_start" \
        "Executing command" \
        0 \
        "${display}"

    local output="${TMP_DIR}/command_${RANDOM}.log"
    local rc=0

    "$@" >"${output}" 2>&1 || rc=$?

    cat "${output}" | tee -a "${HUMAN_LOG}"

    if (( rc == 0 )); then
        log_event \
            "INFO" \
            "${phase}" \
            "command_success" \
            "Command completed" \
            0 \
            "${display}"

        return 0
    fi

    log_event \
        "ERROR" \
        "${phase}" \
        "command_failed" \
        "Command returned non-zero status" \
        "${rc}" \
        "${display}"

    return "${rc}"
}

run_optional() {
    local phase="$1"
    shift

    local display
    printf -v display '%q ' "$@"

    log_event \
        "INFO" \
        "${phase}" \
        "optional_command_start" \
        "Executing optional command" \
        0 \
        "${display}"

    local output="${TMP_DIR}/optional_${RANDOM}.log"
    local rc=0

    "$@" >"${output}" 2>&1 || rc=$?

    cat "${output}" | tee -a "${HUMAN_LOG}"

    if (( rc == 0 )); then
        log_event \
            "INFO" \
            "${phase}" \
            "optional_command_success" \
            "Optional command completed" \
            0 \
            "${display}"
    else
        log_event \
            "WARN" \
            "${phase}" \
            "optional_command_failed" \
            "Optional command failed; continuing" \
            "${rc}" \
            "${display}"
    fi

    return 0
}

capture_cmd() {
    local output_var="$1"
    local phase="$2"
    shift 2

    local display
    printf -v display '%q ' "$@"

    local output="${TMP_DIR}/capture_${RANDOM}.log"
    local rc=0

    log_event \
        "INFO" \
        "${phase}" \
        "capture_start" \
        "Collecting command output" \
        0 \
        "${display}"

    "$@" >"${output}" 2>&1 || rc=$?

    cat "${output}" | tee -a "${HUMAN_LOG}"

    if (( rc != 0 )); then
        log_event \
            "ERROR" \
            "${phase}" \
            "capture_failed" \
            "Command failed while collecting output" \
            "${rc}" \
            "${display}"

        return "${rc}"
    fi

    printf -v "${output_var}" '%s' "$(cat "${output}")"

    log_event \
        "INFO" \
        "${phase}" \
        "capture_success" \
        "Output captured" \
        0 \
        "${display}"
}

write_report() {
    local status="$1"
    local rc="$2"
    local line="${3:-n/a}"
    local file="${4:-n/a}"
    local function_name="${5:-n/a}"
    local command="${6:-n/a}"

    cat > "${REPORT_FILE}" <<EOF
# AI Dev Suite — Engineering Report

**Status:** ${status}  
**Script version:** ${SCRIPT_VERSION}  
**Run ID:** ${RUN_ID}  
**Exit code:** ${rc}

## Failure diagnostics

- File: \`${file}\`
- Function: \`${function_name}\`
- Line: \`${line}\`
- Command: \`${command}\`

## Artifacts

- Human log: \`${HUMAN_LOG}\`
- JSONL log: \`${JSONL_LOG}\`
- Report: \`${REPORT_FILE}\`

## Engineering controls

EOF

    printf -- '- **Fail-fast:** enabled with centralized ERR diagnostics\n' >> "${REPORT_FILE}"
    printf -- '- **Structured logging:** JSONL\n' >> "${REPORT_FILE}"
    printf -- '- **Human logging:** timestamped text\n' >> "${REPORT_FILE}"
    printf -- '- **Secret safety:** no global `set -x`\n' >> "${REPORT_FILE}"
    printf -- '- **Pi package registration:** native `pi install`\n' >> "${REPORT_FILE}"
    printf -- '- **Node resolution:** local module verification under `~/.pi/agent/extensions`\n' >> "${REPORT_FILE}"
    printf -- '- **Engineering Excellence:** installed as Pi skill\n' >> "${REPORT_FILE}"
    printf -- '- **Quality gates:** shell, Node, npm, Bun, Pi and dependency resolution\n' >> "${REPORT_FILE}"
}

# ------------------------------------------------------------------------------
# resolve_workflow_version
#
# The naive check "${dir}/node_modules/pi-extensible-workflows/package.json"
# assumes Node resolved the module locally inside ${dir}/node_modules. It
# does not: require.resolve({paths:[dir]}) still walks UP through ancestor
# node_modules directories per Node's normal CommonJS algorithm, so it can
# report the module "resolvable" even when it was actually found one or more
# levels above ${dir} (e.g. installed there separately by `pi install`,
# while a local `npm install` pruned/never created the nested copy).
#
# This walks up from wherever the module's entry file ACTUALLY resolved to,
# looking for the package.json that really owns it, instead of guessing a
# fixed path. It also reports that real location on stderr, so a mismatch
# between "where we expected it" and "where it really is" is visible in the
# logs instead of crashing on a bare MODULE_NOT_FOUND.
# ------------------------------------------------------------------------------

resolve_workflow_version() {
    local search_root="$1"

    node -e '
        const path = require("path");
        const fs = require("fs");

        const searchRoot = process.argv[1];
        let entry;

        try {
            entry = require.resolve(
                "pi-extensible-workflows",
                { paths: [searchRoot] }
            );
        } catch (err) {
            console.error(
                `pi-extensible-workflows is not resolvable from ${searchRoot}: ${err.message}`
            );
            process.exit(1);
        }

        let dir = path.dirname(entry);

        for (;;) {
            const candidate = path.join(dir, "package.json");

            if (fs.existsSync(candidate)) {
                const pkg = JSON.parse(fs.readFileSync(candidate, "utf8"));

                if (pkg.name === "pi-extensible-workflows") {
                    process.stderr.write(`resolved_package_json=${candidate}\n`);
                    console.log(pkg.version);
                    process.exit(0);
                }
            }

            const parent = path.dirname(dir);

            if (parent === dir) {
                break;
            }

            dir = parent;
        }

        console.error(
            `Could not find pi-extensible-workflows package.json by walking up from ${entry}`
        );
        process.exit(1);
    ' "${search_root}"
}

# ------------------------------------------------------------------------------
# Initialize logs BEFORE checking optional runtime dependencies.
# ------------------------------------------------------------------------------

: > "${HUMAN_LOG}"
: > "${JSONL_LOG}"

log_event \
    "INFO" \
    "bootstrap" \
    "start" \
    "AI Dev Suite setup started" \
    0 \
    "script_version=${SCRIPT_VERSION}"

log_event \
    "INFO" \
    "bootstrap" \
    "paths" \
    "Runtime directories initialized" \
    0 \
    "pi_agent=${PI_AGENT_DIR};pi_extensions=${PI_EXTENSIONS_DIR};pi_npm=${PI_NPM_DIR}"

# ------------------------------------------------------------------------------
# 1. Preflight
# ------------------------------------------------------------------------------

section "Preflight"

require_command bash
require_command curl
require_command git
require_command sudo

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release

    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
else
    log_event \
        "ERROR" \
        "preflight" \
        "os_detection_failed" \
        "/etc/os-release not found" \
        1

    exit 1
fi

log_event \
    "INFO" \
    "preflight" \
    "os_detected" \
    "Linux distribution detected" \
    0 \
    "id=${DISTRO_ID};id_like=${DISTRO_LIKE}"

# ------------------------------------------------------------------------------
# 2. Python is installed before any JSON tooling is needed elsewhere.
# ------------------------------------------------------------------------------

section "Base system dependencies"

PM=""

case "${DISTRO_ID}" in
    debian|ubuntu|linuxmint|pop)
        PM="apt-get"
        ;;

    fedora|rhel|centos|rocky|almalinux)
        PM="dnf"
        ;;

    arch|manjaro)
        PM="pacman"
        ;;

    opensuse*|sles)
        PM="zypper"
        ;;

    *)
        if [[ "${DISTRO_LIKE}" == *debian* ]]; then
            PM="apt-get"
        elif [[ "${DISTRO_LIKE}" == *fedora* || "${DISTRO_LIKE}" == *rhel* ]]; then
            PM="dnf"
        else
            log_event \
                "ERROR" \
                "system" \
                "unsupported_distribution" \
                "Unsupported Linux distribution: ${DISTRO_ID}" \
                1

            exit 1
        fi
        ;;
esac

log_event \
    "INFO" \
    "system" \
    "package_manager_selected" \
    "Package manager selected" \
    0 \
    "package_manager=${PM}"

case "${PM}" in

    apt-get)
        SYSTEM_PKGS=(
            build-essential
            curl
            wget
            git
            unzip
            tar
            ca-certificates
            gnupg
            python3
            python3-venv
            python3-pip
            neovim
            gh
            golang-go
            imagemagick
        )

        run_cmd "system" sudo apt-get update
        run_cmd "system" sudo apt-get install -y "${SYSTEM_PKGS[@]}"
        ;;

    dnf)
        SYSTEM_PKGS=(
            gcc
            gcc-c++
            make
            curl
            wget
            git
            unzip
            tar
            ca-certificates
            gnupg2
            python3
            python3-pip
            neovim
            gh
            golang
            ImageMagick
        )

        run_cmd "system" sudo dnf install -y "${SYSTEM_PKGS[@]}"
        ;;

    pacman)
        SYSTEM_PKGS=(
            base-devel
            curl
            wget
            git
            unzip
            tar
            ca-certificates
            gnupg
            python
            python-pip
            neovim
            github-cli
            go
            imagemagick
        )

        run_cmd \
            "system" \
            sudo pacman -Sy --needed --noconfirm "${SYSTEM_PKGS[@]}"
        ;;

    zypper)
        SYSTEM_PKGS=(
            gcc
            gcc-c++
            make
            curl
            wget
            git
            unzip
            tar
            ca-certificates
            gpg2
            python3
            python3-pip
            neovim
            gh
            go
            ImageMagick
        )

        run_cmd \
            "system" \
            sudo zypper --non-interactive refresh

        run_cmd \
            "system" \
            sudo zypper \
            --non-interactive \
            install \
            --no-recommends \
            "${SYSTEM_PKGS[@]}"
        ;;

esac

require_command python3

# ------------------------------------------------------------------------------
# 3. Node / NVM
# ------------------------------------------------------------------------------

section "Node.js"

NVM_VERSION="${NVM_VERSION:-v0.40.3}"
export NVM_DIR="${HOME}/.nvm"

if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then

    NVM_INSTALLER="${TMP_DIR}/install-nvm.sh"

    run_cmd \
        "node" \
        curl \
        -fsSL \
        "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
        -o \
        "${NVM_INSTALLER}"

    run_cmd \
        "node" \
        bash \
        "${NVM_INSTALLER}"
fi

# shellcheck disable=SC1090
source "${NVM_DIR}/nvm.sh"

run_cmd "node" nvm install 22
run_cmd "node" nvm alias default 22
run_cmd "node" nvm use 22

NODE_VERSION="$(node --version)"

node - <<'NODE'
const [major, minor] = process.versions.node
  .split('.')
  .map(Number);

if (major < 22 || (major === 22 && minor < 19)) {
    console.error(
        `Node.js ${process.versions.node} is too old. ` +
        `pi-extensible-workflows requires Node.js >= 22.19.`
    );

    process.exit(1);
}
NODE

log_event \
    "INFO" \
    "node" \
    "runtime_ready" \
    "Node.js runtime validated" \
    0 \
    "version=${NODE_VERSION}"

run_cmd "node" npm install -g npm@12
run_cmd "node" npm cache verify

# ------------------------------------------------------------------------------
# 3b. Make node/npm reachable under sudo
#
# nvm installs node/npm under ~/.nvm, which is only on PATH after nvm.sh is
# sourced in an interactive shell. sudo ignores that PATH and uses its own
# secure_path (typically /usr/bin:/bin:/usr/sbin:/sbin, occasionally also
# /usr/local/bin), so any downstream "sudo npm ..." call -- whether written
# directly in a script (e.g. dotenv/setup_env.sh) or issued internally by a
# binary such as the Pi CLI during "pi update --extensions" -- fails with
# "sudo: npm: command not found". Symlinking the resolved binaries into
# /usr/local/bin fixes this once, for every caller, instead of patching each
# occurrence individually.
# ------------------------------------------------------------------------------

NODE_BIN="$(command -v node)"
NPM_BIN="$(command -v npm)"

run_cmd "node" sudo ln -sf "${NODE_BIN}" /usr/local/bin/node
run_cmd "node" sudo ln -sf "${NPM_BIN}" /usr/local/bin/npm

log_event \
    "INFO" \
    "node" \
    "sudo_path_fixed" \
    "node/npm symlinked into /usr/local/bin for sudo visibility" \
    0 \
    "node=${NODE_BIN};npm=${NPM_BIN}"

# ------------------------------------------------------------------------------
# 4. Bun
# ------------------------------------------------------------------------------

section "Bun"

export BUN_INSTALL="${HOME}/.bun"

if [[ ! -x "${BUN_INSTALL}/bin/bun" ]]; then

    BUN_INSTALLER="${TMP_DIR}/install-bun.sh"

    run_cmd \
        "bun" \
        curl \
        -fsSL \
        https://bun.sh/install \
        -o \
        "${BUN_INSTALLER}"

    run_cmd \
        "bun" \
        bash \
        "${BUN_INSTALLER}"
fi

export PATH="${BUN_INSTALL}/bin:${PATH}"

require_command bun

log_event \
    "INFO" \
    "bun" \
    "runtime_ready" \
    "Bun runtime validated" \
    0 \
    "version=$(bun --version)"

# ------------------------------------------------------------------------------
# 5. Pi
# ------------------------------------------------------------------------------

section "Pi"

export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"

if ! command -v pi >/dev/null 2>&1; then

    PI_INSTALLER="${TMP_DIR}/install-pi.sh"

    run_cmd \
        "pi" \
        curl \
        -fsSL \
        https://pi.dev/install.sh \
        -o \
        "${PI_INSTALLER}"

    run_cmd \
        "pi" \
        sh \
        "${PI_INSTALLER}"
fi

export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"

require_command pi

PI_VERSION="$(pi --version 2>/dev/null || true)"

log_event \
    "INFO" \
    "pi" \
    "cli_ready" \
    "Pi CLI detected" \
    0 \
    "version=${PI_VERSION}"

# Ensure Pi runtime directories exist.
mkdir -p \
    "${PI_AGENT_DIR}" \
    "${PI_EXTENSIONS_DIR}" \
    "${PI_NPM_DIR}" \
    "${PI_AGENT_DIR}/skills"

# ------------------------------------------------------------------------------
# 6. Dotenv
# ------------------------------------------------------------------------------

section "dotenv"

mkdir -p "${HOME}/git/personale"

if [[ ! -d "${DOTENV_DIR}/.git" ]]; then

    run_cmd \
        "dotenv" \
        git clone \
        -- \
        "${DOTENV_REPO}" \
        "${DOTENV_DIR}"

else

    log_event \
        "INFO" \
        "dotenv" \
        "repository_exists" \
        "Existing dotenv repository preserved"
fi

# Exact stale reference replacement only.
if grep \
    -RIl \
    --exclude-dir=.git \
    "gthelding/monokai-pro.nvim" \
    "${DOTENV_DIR}" \
    >"${TMP_DIR}/monokai_hits" \
    2>/dev/null; then

    while IFS= read -r file; do

        sed -i \
            's|gthelding/monokai-pro.nvim|loctvl842/monokai-pro.nvim|g' \
            "${file}"

        log_event \
            "INFO" \
            "dotenv" \
            "reference_patched" \
            "Updated stale monokai-pro repository reference" \
            0 \
            "file=${file}"

    done < "${TMP_DIR}/monokai_hits"
fi

# sudo does not inherit PATH, so a bare "sudo npm" cannot find an
# nvm-installed npm. Pin it to the resolved absolute path instead.
if grep \
    -RIl \
    --exclude-dir=.git \
    'sudo npm install -g --prefix /usr/local bun' \
    "${DOTENV_DIR}" \
    >"${TMP_DIR}/sudo_npm_hits" \
    2>/dev/null; then

    while IFS= read -r file; do

        sed -i \
            's|sudo npm install -g --prefix /usr/local bun|sudo "$(command -v npm)" install -g --prefix /usr/local bun|g' \
            "${file}"

        log_event \
            "INFO" \
            "dotenv" \
            "reference_patched" \
            "Patched sudo npm call to use resolved absolute path" \
            0 \
            "file=${file}"

    done < "${TMP_DIR}/sudo_npm_hits"
fi

# tree-sitter-cli downloads its real binary in a postinstall step that pi's
# npm policy blocks, and the "command -v tree-sitter" guard doesn't check the
# absolute path Neovim actually spawns -- so parser compilation dies with
# ENOENT. Replace that single install line with a version that forces the
# postinstall and verifies/repairs the exact binary. Idempotent: the marker
# on the replacement line means a second run finds nothing to patch.
if grep \
    -RIl \
    --exclude-dir=.git \
    -e 'npm install -g --prefix "\$HOME/.local" tree-sitter-cli' \
    "${DOTENV_DIR}" \
    >"${TMP_DIR}/treesitter_hits" \
    2>/dev/null; then

    while IFS= read -r file; do

        if grep -q 'AI_DEV_TS_CLI_PATCH' "${file}"; then
            continue
        fi

        python3 - "${file}" <<'PYPATCH'
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

        log_event \
            "INFO" \
            "dotenv" \
            "reference_patched" \
            "Patched tree-sitter-cli install to force postinstall and verify binary" \
            0 \
            "file=${file}"

    done < "${TMP_DIR}/treesitter_hits"
fi

if [[ -x "${DOTENV_DIR}/setup_env.sh" ]]; then

    run_cmd \
        "dotenv" \
        bash \
        "${DOTENV_DIR}/setup_env.sh"

else

    log_event \
        "WARN" \
        "dotenv" \
        "setup_script_missing" \
        "dotenv/setup_env.sh is missing or not executable"
fi

# ------------------------------------------------------------------------------
# 7. Engineering Excellence
# ------------------------------------------------------------------------------

section "Engineering Excellence"

PI_SKILLS_DIR="${PI_AGENT_DIR}/skills"
EE_STAGE="${TMP_DIR}/engineering-excellence"

run_cmd \
    "engineering-excellence" \
    git clone \
    --depth 1 \
    --branch main \
    -- \
    "${ENGINEERING_EXCELLENCE_REPO}" \
    "${EE_STAGE}"

[[ -f "${EE_STAGE}/skills/engineering-excellence/SKILL.md" ]] || {
    log_event \
        "ERROR" \
        "engineering-excellence" \
        "skill_not_found" \
        "SKILL.md was not found at expected repository path" \
        1 \
        "expected=${EE_STAGE}/skills/engineering-excellence/SKILL.md"

    exit 1
}

if [[ -e "${ENGINEERING_EXCELLENCE_DIR}" ]]; then

    BACKUP_DIR="${ENGINEERING_EXCELLENCE_DIR}.backup.${RUN_ID}"

    mv \
        -- \
        "${ENGINEERING_EXCELLENCE_DIR}" \
        "${BACKUP_DIR}"

    log_event \
        "WARN" \
        "engineering-excellence" \
        "existing_skill_backed_up" \
        "Existing skill backed up" \
        0 \
        "backup=${BACKUP_DIR}"
fi

mv \
    -- \
    "${EE_STAGE}/skills/engineering-excellence" \
    "${ENGINEERING_EXCELLENCE_DIR}"

EE_COMMIT="$(
    git \
        -C \
        "${TMP_DIR}/engineering-excellence" \
        rev-parse HEAD
)"

log_event \
    "INFO" \
    "engineering-excellence" \
    "skill_installed" \
    "Engineering Excellence installed as Pi skill" \
    0 \
    "path=${ENGINEERING_EXCELLENCE_DIR};commit=${EE_COMMIT}"

# ------------------------------------------------------------------------------
# 8. pi-extensible-workflows
#
# THIS IS THE IMPORTANT FIX.
#
# The failing file:
#
#   ~/.pi/agent/extensions/piextworkflows.ts
#
# performs:
#
#   import/require("pi-extensible-workflows")
#
# Node resolves that package starting from:
#
#   ~/.pi/agent/extensions/
#
# Therefore installing only inside:
#
#   ~/git/personale/dotenv/pi/agent/extensions/...
#
# is insufficient.
#
# We install it in both:
#
#   A) Pi's official package manager
#   B) ~/.pi/agent/extensions/node_modules
#
# and explicitly test require.resolve() from the failing directory.
# ------------------------------------------------------------------------------

section "pi-extensible-workflows"

if [[ -z "${PI_WORKFLOW_VERSION}" ]]; then

    capture_cmd \
        PI_WORKFLOW_VERSION \
        "pi-workflows" \
        npm view pi-extensible-workflows version
fi

[[ -n "${PI_WORKFLOW_VERSION}" ]] || {
    log_event \
        "ERROR" \
        "pi-workflows" \
        "version_unresolved" \
        "Unable to determine published pi-extensible-workflows version" \
        1

    exit 1
}

log_event \
    "INFO" \
    "pi-workflows" \
    "version_selected" \
    "Workflow package version selected" \
    0 \
    "version=${PI_WORKFLOW_VERSION}"

# A. Official Pi package installation.
run_cmd \
    "pi-workflows" \
    pi install \
    "npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}"

# B. Install as a normal Node dependency exactly where the failing extension
#    expects Node resolution to begin.
mkdir -p "${PI_EXTENSIONS_DIR}"

pushd "${PI_EXTENSIONS_DIR}" >/dev/null

printf '%s\n' \
    'ignore-scripts=false' \
    > .npmrc

run_cmd \
    "pi-workflows-node" \
    npm install \
    --save-exact \
    --no-audit \
    --no-fund \
    "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"

popd >/dev/null

#
# The critical regression test.
#
# Do not trust "npm install" blindly; prove Node can resolve the exact module
# from ~/.pi/agent/extensions, which is the path named by the original error.
#

RESOLVED_MODULE="$(
    node \
        -e \
        'console.log(require.resolve("pi-extensible-workflows",{paths:[process.argv[1]]}))' \
        "${PI_EXTENSIONS_DIR}"
)"

log_event \
    "INFO" \
    "pi-workflows-node" \
    "module_resolved" \
    "pi-extensible-workflows is resolvable from Pi extensions directory" \
    0 \
    "resolved=${RESOLVED_MODULE}"

#
# Verify package version.
#
# Resolve the version from wherever pi-extensible-workflows was ACTUALLY
# found (see resolve_workflow_version), not from an assumed local path --
# RESOLVED_MODULE above already proved resolution can land outside
# ${PI_EXTENSIONS_DIR}/node_modules.
#

INSTALLED_WORKFLOW_VERSION="$(resolve_workflow_version "${PI_EXTENSIONS_DIR}")"

if [[ "${INSTALLED_WORKFLOW_VERSION}" != "${PI_WORKFLOW_VERSION}" ]]; then

    log_event \
        "ERROR" \
        "pi-workflows-node" \
        "version_mismatch" \
        "Installed workflow version does not match requested version" \
        1 \
        "expected=${PI_WORKFLOW_VERSION};actual=${INSTALLED_WORKFLOW_VERSION}"

    exit 1
fi

#
# Also fix the local dotenv extension dependency if that source tree exists.
#

if [[ -d "${DOTENV_EXT_DIR}" ]]; then

    pushd "${DOTENV_EXT_DIR}" >/dev/null

    printf '%s\n' \
        'ignore-scripts=false' \
        > .npmrc

    run_cmd \
        "dotenv-workflows" \
        npm install \
        --save-exact \
        --no-audit \
        --no-fund \
        "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"

    popd >/dev/null

    DOTENV_RESOLVED="$(
        node \
            -e \
            'console.log(require.resolve("pi-extensible-workflows",{paths:[process.argv[1]]}))' \
            "${DOTENV_EXT_DIR}"
    )"

    log_event \
        "INFO" \
        "dotenv-workflows" \
        "module_resolved" \
        "Workflow dependency is also resolvable from dotenv extension" \
        0 \
        "resolved=${DOTENV_RESOLVED}"
fi

# ------------------------------------------------------------------------------
# 9. Optional Pi companion packages
# ------------------------------------------------------------------------------

section "Pi companion packages"

run_optional \
    "pi-companion" \
    pi install \
    npm:@piewf/herdr

run_optional \
    "pi-companion" \
    pi install \
    npm:@piewf/cli

# ------------------------------------------------------------------------------
# 10. tuxevil-rotator
# ------------------------------------------------------------------------------

section "tuxevil-rotator"

TUXEVIL_DIR="${PI_EXTENSIONS_DIR}/tuxevil-rotator"

if [[ ! -d "${TUXEVIL_DIR}" ]]; then

    run_optional \
        "tuxevil-rotator" \
        git clone \
        https://github.com/tuxevil/tuxevil-rotator.git \
        "${TUXEVIL_DIR}"
fi

if [[ -d "${TUXEVIL_DIR}" ]]; then

    pushd "${TUXEVIL_DIR}" >/dev/null

    printf '%s\n' \
        'ignore-scripts=false' \
        > .npmrc

    run_optional \
        "tuxevil-rotator" \
        npm install \
        --no-audit \
        --no-fund

    popd >/dev/null
fi

# ------------------------------------------------------------------------------
# 11. External AI CLIs
# ------------------------------------------------------------------------------

section "External AI CLIs"

#
# We download installers first rather than using curl | bash.
# These components remain optional.
#

AG_INSTALLER="${TMP_DIR}/install-antigravity.sh"

run_optional \
    "external-ai" \
    curl \
    -fsSL \
    https://antigravity.google/cli/install.sh \
    -o \
    "${AG_INSTALLER}"

if [[ -s "${AG_INSTALLER}" ]]; then
    run_optional \
        "external-ai" \
        bash \
        "${AG_INSTALLER}"
fi

CODEX_INSTALLER="${TMP_DIR}/install-codex.sh"

run_optional \
    "external-ai" \
    curl \
    -fsSL \
    https://chatgpt.com/codex/install.sh \
    -o \
    "${CODEX_INSTALLER}"

if [[ -s "${CODEX_INSTALLER}" ]]; then
    run_optional \
        "external-ai" \
        sh \
        "${CODEX_INSTALLER}"
fi

CLAUDE_INSTALLER="${TMP_DIR}/install-claude.sh"

run_optional \
    "external-ai" \
    curl \
    -fsSL \
    https://claude.ai/install.sh \
    -o \
    "${CLAUDE_INSTALLER}"

if [[ -s "${CLAUDE_INSTALLER}" ]]; then
    run_optional \
        "external-ai" \
        bash \
        "${CLAUDE_INSTALLER}"
fi

OPENCODE_INSTALLER="${TMP_DIR}/install-opencode.sh"

run_optional \
    "external-ai" \
    curl \
    -fsSL \
    https://opencode.ai/install \
    -o \
    "${OPENCODE_INSTALLER}"

if [[ -s "${OPENCODE_INSTALLER}" ]]; then
    run_optional \
        "external-ai" \
        bash \
        "${OPENCODE_INSTALLER}"
fi

# ------------------------------------------------------------------------------
# 12. Go tools
# ------------------------------------------------------------------------------

section "Go tools"

export GOPATH="${HOME}/go"
export PATH="${GOPATH}/bin:${HOME}/.cargo/bin:${PATH}"

if command -v go >/dev/null 2>&1; then

    run_optional \
        "go-tools" \
        go install \
        github.com/gentleman-programming/gentle-ai/v2/cmd/gentle-ai@latest

    run_optional \
        "go-tools" \
        go install \
        github.com/vekexasia/wslens@latest

else

    log_event \
        "WARN" \
        "go-tools" \
        "go_missing" \
        "Go not found; optional Go tools skipped"
fi

# ------------------------------------------------------------------------------
# 13. Cockpit Tools
# ------------------------------------------------------------------------------

section "Cockpit Tools"

COCKPIT_INSTALLED=0

RELEASE_JSON="${TMP_DIR}/cockpit-release.json"

run_optional \
    "cockpit" \
    curl \
    -fsSL \
    https://api.github.com/repos/jlcodes99/cockpit-tools/releases/latest \
    -o \
    "${RELEASE_JSON}"

if [[ -s "${RELEASE_JSON}" && "${PM}" == "apt-get" ]]; then

    DEB_URL="$(
        grep \
            -oE \
            '"browser_download_url":[[:space:]]*"[^"]+amd64[^"]+\.deb"' \
            "${RELEASE_JSON}" \
        | head -n1 \
        | cut -d '"' -f4 \
        || true
    )"

    if [[ -n "${DEB_URL}" ]]; then

        COCKPIT_DEB="${TMP_DIR}/cockpit.deb"

        run_optional \
            "cockpit" \
            curl \
            -fsSL \
            "${DEB_URL}" \
            -o \
            "${COCKPIT_DEB}"

        if [[ -s "${COCKPIT_DEB}" ]]; then

            run_optional \
                "cockpit" \
                sudo \
                apt-get \
                install \
                -y \
                "${COCKPIT_DEB}"

            COCKPIT_INSTALLED=1
        fi
    fi
fi

if (( COCKPIT_INSTALLED == 0 )); then

    if command -v cargo >/dev/null 2>&1; then

        run_optional \
            "cockpit" \
            cargo \
            install \
            --git \
            https://github.com/jlcodes99/cockpit-tools

    else

        log_event \
            "WARN" \
            "cockpit" \
            "cargo_missing" \
            "Cargo not available; source build skipped"
    fi
fi

# ------------------------------------------------------------------------------
# 14. Shell environment
# ------------------------------------------------------------------------------

section "Shell environment"

SHELL_CONFIG="${HOME}/.bashrc"

if [[ -n "${ZSH_VERSION:-}" ]]; then
    SHELL_CONFIG="${HOME}/.zshrc"
fi

ENV_MARKER="# AI Dev Toolsuite Environment"

if ! grep -Fq "${ENV_MARKER}" "${SHELL_CONFIG}" 2>/dev/null; then

    cat >> "${SHELL_CONFIG}" <<'EOF'

# ==========================================
# AI Dev Toolsuite Environment
# ==========================================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

export BUN_INSTALL="$HOME/.bun"
export GOPATH="$HOME/go"

export PATH="$BUN_INSTALL/bin:$HOME/.pi/bin:$HOME/.local/bin:$GOPATH/bin:$HOME/.cargo/bin:$PATH"
EOF

    log_event \
        "INFO" \
        "shell" \
        "environment_added" \
        "AI Dev environment added to shell startup file" \
        0 \
        "file=${SHELL_CONFIG}"

else

    log_event \
        "INFO" \
        "shell" \
        "environment_exists" \
        "AI Dev environment already exists" \
        0 \
        "file=${SHELL_CONFIG}"
fi

# ------------------------------------------------------------------------------
# 15. Quality gates
# ------------------------------------------------------------------------------

section "Quality gates"

#
# Gate 1: Shell parser
#

run_cmd \
    "quality" \
    bash \
    -n \
    "${BASH_SOURCE[0]}"

#
# Gate 2: Node >= 22.19
#

run_cmd "quality" node --version
run_cmd "quality" npm --version
run_cmd "quality" bun --version

#
# Gate 3: Pi binary
#

run_cmd \
    "quality" \
    pi \
    --no-extensions \
    --version

#
# Gate 4: Pi package registry
#

run_cmd \
    "quality" \
    pi \
    list

#
# Gate 5: Exact regression test from the failing extension root
#

run_cmd \
    "quality" \
    node \
    -e \
    'const root=process.argv[1]; const resolved=require.resolve("pi-extensible-workflows",{paths:[root]}); console.log(`RESOLVED=${resolved}`)' \
    "${PI_EXTENSIONS_DIR}"

#
# Gate 6: The specific file from the user's original failure must exist if
# dotenv/setup_env.sh generated it.
#

PI_WORKFLOW_EXTENSION="${PI_EXTENSIONS_DIR}/piextworkflows.ts"

if [[ -f "${PI_WORKFLOW_EXTENSION}" ]]; then

    log_event \
        "INFO" \
        "quality" \
        "failing_extension_detected" \
        "Original failing piextworkflows.ts exists" \
        0 \
        "file=${PI_WORKFLOW_EXTENSION}"

    #
    # Check that the dependency can be resolved exactly from the extension's
    # directory.
    #

    run_cmd \
        "quality" \
        node \
        -e \
        'const root=require("path").dirname(process.argv[1]); console.log(require.resolve("pi-extensible-workflows",{paths:[root]}))' \
        "${PI_WORKFLOW_EXTENSION}"

else

    log_event \
        "INFO" \
        "quality" \
        "failing_extension_not_present" \
        "piextworkflows.ts is not currently present; base module resolution gate passed"
fi

#
# Gate 7: Package version
#

FINAL_WORKFLOW_VERSION="$(resolve_workflow_version "${PI_EXTENSIONS_DIR}")"

if [[ "${FINAL_WORKFLOW_VERSION}" != "${PI_WORKFLOW_VERSION}" ]]; then

    log_event \
        "ERROR" \
        "quality" \
        "workflow_version_gate_failed" \
        "Workflow dependency version mismatch" \
        1 \
        "expected=${PI_WORKFLOW_VERSION};actual=${FINAL_WORKFLOW_VERSION}"

    exit 1
fi

#
# Gate 8: Engineering Excellence
#

[[ -f "${ENGINEERING_EXCELLENCE_DIR}/SKILL.md" ]] || {
    log_event \
        "ERROR" \
        "quality" \
        "engineering_excellence_gate_failed" \
        "Engineering Excellence SKILL.md missing" \
        1

    exit 1
}

log_event \
    "INFO" \
    "quality" \
    "all_gates_passed" \
    "All deterministic quality gates passed"

# ------------------------------------------------------------------------------
# 16. Final engineering report
# ------------------------------------------------------------------------------

write_report \
    "SUCCESS" \
    0 \
    "n/a" \
    "n/a" \
    "n/a" \
    "n/a"

cat >> "${REPORT_FILE}" <<EOF

## Installed versions

- Node.js: \`$(node --version)\`
- npm: \`$(npm --version)\`
- Bun: \`$(bun --version)\`
- Pi: \`${PI_VERSION}\`
- pi-extensible-workflows: \`${PI_WORKFLOW_VERSION}\`
- Engineering Excellence commit: \`${EE_COMMIT}\`

## Root cause addressed

The original error was:

\`Cannot find module 'pi-extensible-workflows'\`

from:

\`${PI_EXTENSIONS_DIR}/piextworkflows.ts\`

The package is now installed in:

\`${PI_EXTENSIONS_DIR}/node_modules/pi-extensible-workflows\`

and verified through:

\`require.resolve("pi-extensible-workflows")\`

using the exact extension root.

Pi's own package manager installation is also retained:

\`pi install npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}\`

## Logging

### Human-readable

\`${HUMAN_LOG}\`

### AI / machine-readable

\`${JSONL_LOG}\`

The JSONL format is one structured event per line, suitable for:

\`\`\`bash
jq .
\`\`\`

or:

\`\`\`bash
tail -f "${JSONL_LOG}" | jq .
\`\`\`

## Final verification

After the script finishes successfully:

\`\`\`bash
source "${SHELL_CONFIG}"
pi
\`\`\`

The previous \`Cannot find module 'pi-extensible-workflows'\` error should no longer occur.

EOF

log_event \
    "INFO" \
    "bootstrap" \
    "completed" \
    "AI Dev Suite setup completed successfully" \
    0 \
    "human_log=${HUMAN_LOG};jsonl_log=${JSONL_LOG};report=${REPORT_FILE}"

printf '\n'
printf '\033[1;32m============================================================\033[0m\n'
printf '\033[1;32m AI Dev Suite setup completed successfully\033[0m\n'
printf '\033[1;32m============================================================\033[0m\n'
printf 'Human log : %s\n' "${HUMAN_LOG}"
printf 'JSONL log : %s\n' "${JSONL_LOG}"
printf 'Report    : %s\n' "${REPORT_FILE}"
printf 'Pi        : %s\n' "${PI_VERSION}"
printf 'Workflows : %s\n' "${PI_WORKFLOW_VERSION}"
printf 'EE Skill  : %s\n' "${ENGINEERING_EXCELLENCE_DIR}"
printf '\n'
printf 'Next:\n'
printf '  source "%s"\n' "${SHELL_CONFIG}"
printf '  pi\n'
