#!/usr/bin/env bash

# ==============================================================================
# AI Dev Suite — Engineering Excellence Edition
# Version: 3.0.4
#
# Cross-platform (macOS + all major Linux distros) installer for an AI coding
# toolchain. Windows is handled by the sibling setup-ai.ps1; the Node launcher
# bin/setup-ai.mjs dispatches to the right script per OS and offers an
# interactive, gentle-ai-style module menu.
#
# Design:
#   - modular: every tool is its own mod_* function, driven by an ordered
#     registry; run a subset with --only, list them with --list.
#   - official, non-deprecated install method per OS for every tool.
#   - deterministic logging (human + JSONL), fail-fast with ERR diagnostics.
#
# Usage:
#   ./setup-ai.sh                 # install the core module set
#   ./setup-ai.sh --all           # every module (incl. optional GUI apps)
#   ./setup-ai.sh --only pi,codex,opencode
#   ./setup-ai.sh --list          # print modules and exit
#   ./setup-ai.sh --help
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="3.0.4"

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

ENGINEERING_EXCELLENCE_SLUG="${ENGINEERING_EXCELLENCE_SLUG:-micio86dev/Engineering-Excellence}"
ENGINEERING_EXCELLENCE_SKILL="engineering-excellence"

PI_AGENT_DIR="${HOME}/.pi/agent"
PI_EXTENSIONS_DIR="${PI_AGENT_DIR}/extensions"
PI_NPM_DIR="${PI_AGENT_DIR}/npm"
ENGINEERING_EXCELLENCE_DIR="${PI_AGENT_DIR}/skills/${ENGINEERING_EXCELLENCE_SKILL}"

DOTENV_DIR="${HOME}/git/personale/dotenv"
DOTENV_EXT_DIR="${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows"

COCKPIT_REPO="jlcodes99/cockpit-tools"
GENTLE_AI_INSTALL="https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

cleanup() {
    rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

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
    local return_code="${6:-0}" meta="${7:-}"

    local j_ts j_level j_phase j_event j_message j_meta
    j_ts="$(json_escape "${timestamp}")"
    j_level="$(json_escape "${level}")"
    j_phase="$(json_escape "${phase}")"
    j_event="$(json_escape "${event}")"
    j_message="$(json_escape "${message}")"
    j_meta="$(json_escape "${meta}")"

    {
        printf '{"timestamp":"%s","level":"%s","phase":"%s","event":"%s","message":"%s","return_code":%s,"run_id":"%s","pid":%s' \
            "${j_ts}" "${j_level}" "${j_phase}" "${j_event}" "${j_message}" \
            "${return_code}" "${RUN_ID}" "$$"
        if [[ -n "${meta}" ]]; then
            printf ',"meta":"%s"' "${j_meta}"
        fi
        printf '}\n'
    } >> "${JSONL_LOG}"
}

log_event() {
    local level="$1" phase="$2" event="$3" message="$4"
    local return_code="${5:-0}" meta="${6:-}"

    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    json_log "${timestamp}" "${level}" "${phase}" "${event}" "${message}" "${return_code}" "${meta}"

    local line="${timestamp} [${level}] ${phase} ${event}: ${message}"
    printf '%s\n' "${line}" >> "${HUMAN_LOG}"

    case "${level}" in
        INFO)  printf '\033[1;34m%s\033[0m\n' "${line}" ;;
        WARN)  printf '\033[1;33m%s\033[0m\n' "${line}" ;;
        ERROR) printf '\033[1;31m%s\033[0m\n' "${line}" ;;
        DEBUG) (( DEBUG == 1 )) && printf '\033[0;90m%s\033[0m\n' "${line}" ;;
        *)     printf '%s\n' "${line}" ;;
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

section() { log_event "INFO" "section" "start" "$1"; }

require_command() {
    local command="$1"
    if ! command -v "${command}" >/dev/null 2>&1; then
        log_event "ERROR" "preflight" "missing_command" "Required command not found: ${command}" 127
        return 127
    fi
}

run_cmd() {
    local phase="$1"; shift
    local display; printf -v display '%q ' "$@"
    log_event "INFO" "${phase}" "command_start" "Executing command" 0 "${display}"

    local output="${TMP_DIR}/command_${RANDOM}.log" rc=0
    "$@" >"${output}" 2>&1 || rc=$?
    cat "${output}" | tee -a "${HUMAN_LOG}"

    if (( rc == 0 )); then
        log_event "INFO" "${phase}" "command_success" "Command completed" 0 "${display}"
        return 0
    fi
    log_event "ERROR" "${phase}" "command_failed" "Command returned non-zero status" "${rc}" "${display}"
    return "${rc}"
}

run_optional() {
    local phase="$1"; shift
    local display; printf -v display '%q ' "$@"
    log_event "INFO" "${phase}" "optional_command_start" "Executing optional command" 0 "${display}"

    local output="${TMP_DIR}/optional_${RANDOM}.log" rc=0
    "$@" >"${output}" 2>&1 || rc=$?
    cat "${output}" | tee -a "${HUMAN_LOG}"

    if (( rc == 0 )); then
        log_event "INFO" "${phase}" "optional_command_success" "Optional command completed" 0 "${display}"
    else
        log_event "WARN" "${phase}" "optional_command_failed" "Optional command failed; continuing" "${rc}" "${display}"
    fi
    return 0
}

capture_cmd() {
    local output_var="$1" phase="$2"; shift 2
    local display; printf -v display '%q ' "$@"
    local output="${TMP_DIR}/capture_${RANDOM}.log" rc=0
    log_event "INFO" "${phase}" "capture_start" "Collecting command output" 0 "${display}"
    "$@" >"${output}" 2>&1 || rc=$?
    cat "${output}" | tee -a "${HUMAN_LOG}"
    if (( rc != 0 )); then
        log_event "ERROR" "${phase}" "capture_failed" "Command failed while collecting output" "${rc}" "${display}"
        return "${rc}"
    fi
    printf -v "${output_var}" '%s' "$(cat "${output}")"
    log_event "INFO" "${phase}" "capture_success" "Output captured" 0 "${display}"
}

write_report() {
    local status="$1" rc="$2" line="${3:-n/a}" file="${4:-n/a}"
    local function_name="${5:-n/a}" command="${6:-n/a}"

    cat > "${REPORT_FILE}" <<EOF
# AI Dev Suite — Engineering Report

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

# ------------------------------------------------------------------------------
# resolve_workflow_version — find the package.json that really owns
# pi-extensible-workflows by walking up from where Node resolved its entry.
# ------------------------------------------------------------------------------

resolve_workflow_version() {
    local search_root="$1"
    node -e '
        const path = require("path");
        const fs = require("fs");
        const searchRoot = process.argv[1];
        let entry;
        try {
            entry = require.resolve("pi-extensible-workflows", { paths: [searchRoot] });
        } catch (err) {
            console.error(`pi-extensible-workflows is not resolvable from ${searchRoot}: ${err.message}`);
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
            if (parent === dir) break;
            dir = parent;
        }
        console.error(`Could not find pi-extensible-workflows package.json by walking up from ${entry}`);
        process.exit(1);
    ' "${search_root}"
}

# ==============================================================================
# Module registry
#
# ORDER matters (dependencies first). Each name maps to a mod_<name> function
# and a human description. DEFAULT_MODULES is the "core" set used when no
# --only/--all is given; OPTIONAL_MODULES (GUI apps etc.) are only installed
# via --all or an explicit --only.
# ==============================================================================

MODULE_ORDER=(base node bun pi go dotenv ee pi-workflows herdr gentle-ai engram codex antigravity opencode cockpit)

declare -A MODULE_DESC=(
    [base]="System packages (build tools, git, gh, python, neovim, jq, imagemagick)"
    [node]="Node.js via nvm (v22) + npm@latest + sudo-visible symlinks"
    [bun]="Bun runtime"
    [pi]="pi.dev coding agent CLI"
    [go]="Go toolchain"
    [dotenv]="vekexasia/dotenv dotfiles (Linux only: clones + runs setup_env.sh)"
    [ee]="Engineering Excellence skill (npx skills add, all detected agents)"
    [pi-workflows]="pi-extensible-workflows (fix module resolution for pi extensions)"
    [herdr]="herdr terminal multiplexer"
    [gentle-ai]="gentle-ai / gga (Gentleman's spec-driven agent runner) + gentle-pi package"
    [engram]="Engram persistent memory for pi (gentle-engram: /remember /recall /memory /forget)"
    [codex]="OpenAI Codex CLI"
    [antigravity]="Google Antigravity CLI (agy)"
    [opencode]="opencode agent CLI (opencode-ai)"
    [cockpit]="cockpit-tools desktop GUI app (optional, CC BY-NC-SA)"
)

# Optional modules: excluded from the default/core run.
declare -A MODULE_OPTIONAL=(
    [cockpit]=1
)

# ------------------------------------------------------------------------------
# OS / package-manager detection
# ------------------------------------------------------------------------------

OS_FAMILY=""
PM=""
DISTRO_ID=""
DISTRO_LIKE=""

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
            local pkgs=(build-essential curl wget git unzip tar ca-certificates gnupg jq
                       python3 python3-venv python3-pip neovim gh golang-go imagemagick)
            run_cmd "base" sudo apt-get update
            run_cmd "base" sudo apt-get install -y "${pkgs[@]}"
            ;;
        dnf)
            local pkgs=(gcc gcc-c++ make curl wget git unzip tar ca-certificates gnupg2 jq
                       python3 python3-pip neovim gh golang ImageMagick)
            run_cmd "base" sudo dnf install -y "${pkgs[@]}"
            ;;
        pacman)
            local pkgs=(base-devel curl wget git unzip tar ca-certificates gnupg jq
                       python python-pip neovim github-cli go imagemagick)
            run_cmd "base" sudo pacman -Sy --needed --noconfirm "${pkgs[@]}"
            ;;
        zypper)
            local pkgs=(gcc gcc-c++ make curl wget git unzip tar ca-certificates gpg2 jq
                       python3 python3-pip neovim gh go ImageMagick)
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
    unset npm_config_prefix NPM_CONFIG_PREFIX 2>/dev/null || true

    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"

    run_cmd "node" nvm install 22
    run_cmd "node" nvm alias default 22
    run_cmd "node" nvm use 22

    node - <<'NODE'
const [major, minor] = process.versions.node.split('.').map(Number);
if (major < 22 || (major === 22 && minor < 19)) {
    console.error(`Node.js ${process.versions.node} is too old; pi-extensible-workflows needs >= 22.19.`);
    process.exit(1);
}
NODE

    # npm@latest (NOT npm@12 — that version does not exist).
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
    log_event "INFO" "bun" "runtime_ready" "Bun runtime validated" 0 "version=$(bun --version)"
}

# --- pi ---------------------------------------------------------------------
mod_pi() {
    section "Pi"
    export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"
    if ! command -v pi >/dev/null 2>&1; then
        local installer="${TMP_DIR}/install-pi.sh"
        run_cmd "pi" curl -fsSL https://pi.dev/install.sh -o "${installer}"
        run_cmd "pi" sh "${installer}"
    fi
    export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"
    require_command pi
    PI_VERSION="$(pi --version 2>/dev/null || true)"
    log_event "INFO" "pi" "cli_ready" "Pi CLI detected" 0 "version=${PI_VERSION}"
    mkdir -p "${PI_AGENT_DIR}" "${PI_EXTENSIONS_DIR}" "${PI_NPM_DIR}" "${PI_AGENT_DIR}/skills"
}

# --- go ---------------------------------------------------------------------
mod_go() {
    section "Go toolchain"
    if command -v go >/dev/null 2>&1; then
        log_event "INFO" "go" "already_present" "Go already installed" 0 "version=$(go version)"
        return
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

    mkdir -p "${HOME}/git/personale"
    if [[ ! -d "${DOTENV_DIR}/.git" ]]; then
        run_cmd "dotenv" git clone -- "${DOTENV_REPO}" "${DOTENV_DIR}"
    else
        log_event "INFO" "dotenv" "repository_exists" "Existing dotenv repository preserved"
    fi

    # Idempotent upstream-quirk patches (no-ops once upstream merges the fixes).
    if grep -RIl --exclude-dir=.git "gthelding/monokai-pro.nvim" "${DOTENV_DIR}" \
        >"${TMP_DIR}/monokai_hits" 2>/dev/null; then
        while IFS= read -r file; do
            sed -i 's|gthelding/monokai-pro.nvim|loctvl842/monokai-pro.nvim|g' "${file}"
            log_event "INFO" "dotenv" "reference_patched" "Updated stale monokai-pro reference" 0 "file=${file}"
        done < "${TMP_DIR}/monokai_hits"
    fi

    if grep -RIl --exclude-dir=.git 'sudo npm install -g --prefix /usr/local bun' "${DOTENV_DIR}" \
        >"${TMP_DIR}/sudo_npm_hits" 2>/dev/null; then
        while IFS= read -r file; do
            sed -i 's|sudo npm install -g --prefix /usr/local bun|sudo "$(command -v npm)" install -g --prefix /usr/local bun|g' "${file}"
            log_event "INFO" "dotenv" "reference_patched" "Patched sudo npm call to absolute path" 0 "file=${file}"
        done < "${TMP_DIR}/sudo_npm_hits"
    fi

    if grep -RIl --exclude-dir=.git -e 'npm install -g --prefix "\$HOME/.local" tree-sitter-cli' "${DOTENV_DIR}" \
        >"${TMP_DIR}/treesitter_hits" 2>/dev/null; then
        while IFS= read -r file; do
            grep -q 'AI_DEV_TS_CLI_PATCH' "${file}" && continue
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
            log_event "INFO" "dotenv" "reference_patched" "Patched tree-sitter-cli install" 0 "file=${file}"
        done < "${TMP_DIR}/treesitter_hits"
    fi

    if [[ -x "${DOTENV_DIR}/setup_env.sh" ]]; then
        run_cmd "dotenv" bash "${DOTENV_DIR}/setup_env.sh"
    else
        log_event "WARN" "dotenv" "setup_script_missing" "dotenv/setup_env.sh missing or not executable"
    fi
}

# --- engineering-excellence -------------------------------------------------
mod_ee() {
    section "Engineering Excellence"
    require_command npx

    # Install the skill for every detected agent using the modern skills CLI
    # (replaces the old git-clone-and-move). Agents are detected by their config dir.
    # Keys are the `skills` CLI agent names (claude-code, gemini-cli, ...), which
    # differ from the config-dir basename; values are the dir we detect them by.
    local agent dir
    local -A agent_dir=(
        [pi]="${HOME}/.pi"
        [claude-code]="${HOME}/.claude"
        [gemini-cli]="${HOME}/.gemini"
        [cursor]="${HOME}/.cursor"
        [antigravity]="${HOME}/.antigravity"
        [codex]="${HOME}/.codex"
        [opencode]="${HOME}/.config/opencode"
    )
    local installed_any=0
    for agent in pi claude-code gemini-cli cursor antigravity codex opencode; do
        dir="${agent_dir[$agent]}"
        [[ -d "${dir}" ]] || continue
        run_optional "engineering-excellence" \
            npx --yes skills@latest add "${ENGINEERING_EXCELLENCE_SLUG}" \
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent "${agent}" --copy --yes
        installed_any=1
    done

    if (( installed_any == 0 )); then
        # No agent detected yet — install at least for pi (created by mod_pi).
        run_optional "engineering-excellence" \
            npx --yes skills@latest add "${ENGINEERING_EXCELLENCE_SLUG}" \
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent pi --copy --yes
    fi

    if [[ -f "${ENGINEERING_EXCELLENCE_DIR}/SKILL.md" ]]; then
        log_event "INFO" "engineering-excellence" "skill_installed" "EE skill present for pi" 0 \
            "path=${ENGINEERING_EXCELLENCE_DIR}"
    else
        log_event "WARN" "engineering-excellence" "skill_path_unverified" \
            "EE SKILL.md not found at pi path; check other agents' skill dirs" 0 \
            "expected=${ENGINEERING_EXCELLENCE_DIR}"
    fi
}

# --- pi-extensible-workflows ------------------------------------------------
mod_pi_workflows() {
    section "pi-extensible-workflows"
    require_command pi
    require_command node

    if [[ -z "${PI_WORKFLOW_VERSION}" ]]; then
        capture_cmd PI_WORKFLOW_VERSION "pi-workflows" npm view pi-extensible-workflows version
    fi
    [[ -n "${PI_WORKFLOW_VERSION}" ]] || {
        log_event "ERROR" "pi-workflows" "version_unresolved" "Cannot determine published version" 1
        exit 1
    }
    log_event "INFO" "pi-workflows" "version_selected" "Workflow version selected" 0 "version=${PI_WORKFLOW_VERSION}"

    run_cmd "pi-workflows" pi install "npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}"

    mkdir -p "${PI_EXTENSIONS_DIR}"
    pushd "${PI_EXTENSIONS_DIR}" >/dev/null
    printf '%s\n' 'ignore-scripts=false' > .npmrc
    run_cmd "pi-workflows-node" npm install --save-exact --no-audit --no-fund \
        "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
    popd >/dev/null

    local resolved
    resolved="$(node -e 'console.log(require.resolve("pi-extensible-workflows",{paths:[process.argv[1]]}))' "${PI_EXTENSIONS_DIR}")"
    log_event "INFO" "pi-workflows-node" "module_resolved" "Resolvable from pi extensions dir" 0 "resolved=${resolved}"

    local installed
    installed="$(resolve_workflow_version "${PI_EXTENSIONS_DIR}")"
    if [[ "${installed}" != "${PI_WORKFLOW_VERSION}" ]]; then
        log_event "ERROR" "pi-workflows-node" "version_mismatch" "Installed version mismatch" 1 \
            "expected=${PI_WORKFLOW_VERSION};actual=${installed}"
        exit 1
    fi

    if [[ -d "${DOTENV_EXT_DIR}" ]]; then
        pushd "${DOTENV_EXT_DIR}" >/dev/null
        printf '%s\n' 'ignore-scripts=false' > .npmrc
        run_cmd "dotenv-workflows" npm install --save-exact --no-audit --no-fund \
            "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
        popd >/dev/null
    fi
}

# --- herdr ------------------------------------------------------------------
mod_herdr() {
    section "herdr"
    if command -v herdr >/dev/null 2>&1; then
        log_event "INFO" "herdr" "already_present" "herdr already installed" 0 "version=$(herdr --version 2>/dev/null || true)"
        return
    fi
    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_optional "herdr" brew install herdr
    else
        local installer="${TMP_DIR}/install-herdr.sh"
        run_optional "herdr" curl -fsSL https://herdr.dev/install.sh -o "${installer}"
        [[ -s "${installer}" ]] && run_optional "herdr" sh "${installer}"
    fi
}

# --- gentle-ai --------------------------------------------------------------
mod_gentle_ai() {
    section "gentle-ai"
    if ! command -v gentle-ai >/dev/null 2>&1 && ! command -v gga >/dev/null 2>&1; then
        if [[ "${OS_FAMILY}" == "macos" ]]; then
            run_optional "gentle-ai" brew tap gentleman-programming/tap
            run_optional "gentle-ai" brew install gentle-ai
        else
            local installer="${TMP_DIR}/install-gentle-ai.sh"
            run_optional "gentle-ai" curl -fsSL "${GENTLE_AI_INSTALL}" -o "${installer}"
            [[ -s "${installer}" ]] && run_optional "gentle-ai" bash "${installer}"
        fi
    fi

    # Enable gentle-ai INSIDE pi as packages (the standalone gga binary alone
    # does not register anything in pi — this is why it wasn't visible there).
    if command -v pi >/dev/null 2>&1; then
        run_optional "gentle-ai" pi install npm:gentle-pi
        run_optional "gentle-ai" pi install npm:pi-mcp-adapter
        log_event "INFO" "gentle-ai" "pi_enabled" "gentle-pi registered in pi (verify: /gentle-ai:status)" 0
    fi

    # Surface gentle-ai's own next-steps (do NOT run — they are per-repo).
    log_event "INFO" "gentle-ai" "next_steps" "gentle-ai post-install hints" 0
    cat <<'HINT' | tee -a "${HUMAN_LOG}"
  gentle-ai next steps (run yourself, per project):
    1) Set your API keys
    2) Run your selected agent
    3) Try: /sdd-new my-feature   (in pi: /gentle-ai:status, /gentleman:models)
  GGA (per project):
    gga init      # inside each repo
    gga install
HINT
}

# --- engram (pi persistent memory) ------------------------------------------
# The gentle-engram pi extension auto-starts `engram serve`, so the Engram Go
# binary MUST be on PATH first — otherwise the extension loads but silently
# fails (the "engram doesn't work in pi" symptom). Install binary, then the pi
# packages, then init, then the user restarts pi.
mod_engram() {
    section "Engram memory (pi)"

    # 1. Engram binary (Go).
    if ! command -v engram >/dev/null 2>&1; then
        if [[ "${OS_FAMILY}" == "macos" ]]; then
            run_optional "engram" brew install gentleman-programming/tap/engram
        fi
        if ! command -v engram >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
            run_optional "engram" go install github.com/Gentleman-Programming/engram/cmd/engram@latest
        fi
    fi
    # go installs into $GOPATH/bin (default ~/go/bin), which may not be on PATH yet.
    [[ -x "${HOME}/go/bin/engram" ]] && export PATH="${HOME}/go/bin:${PATH}"

    if ! command -v engram >/dev/null 2>&1; then
        log_event "WARN" "engram" "binary_missing" \
            "engram binary not found after install; the pi extension needs it on PATH" 1
    fi

    # 2. pi integration (in-process extension is the primary path; MCP adapter optional).
    if command -v pi >/dev/null 2>&1; then
        run_optional "engram" pi install npm:gentle-engram
        run_optional "engram" pi install npm:pi-mcp-adapter
        run_optional "engram" npm exec --yes --package gentle-engram@latest -- pi-engram init
        log_event "INFO" "engram" "enabled" \
            "Engram enabled — RESTART pi, then verify with mem_current_project / mem_doctor / 'engram tui'" 0
    else
        log_event "WARN" "engram" "pi_missing" "pi not found; Engram pi integration skipped"
    fi
}

# --- codex ------------------------------------------------------------------
mod_codex() {
    section "Codex CLI"
    if command -v codex >/dev/null 2>&1; then
        log_event "INFO" "codex" "already_present" "codex already installed" 0
        return
    fi
    if [[ "${OS_FAMILY}" == "macos" ]] && command -v brew >/dev/null 2>&1; then
        run_optional "codex" brew install --cask codex
    fi
    if ! command -v codex >/dev/null 2>&1; then
        local installer="${TMP_DIR}/install-codex.sh"
        run_optional "codex" curl -fsSL https://chatgpt.com/codex/install.sh -o "${installer}"
        [[ -s "${installer}" ]] && run_optional "codex" sh "${installer}"
    fi
}

# --- antigravity ------------------------------------------------------------
mod_antigravity() {
    section "Antigravity CLI"
    if command -v agy >/dev/null 2>&1; then
        log_event "INFO" "antigravity" "already_present" "agy already installed" 0
        return
    fi
    local installer="${TMP_DIR}/install-antigravity.sh"
    run_optional "antigravity" curl -fsSL https://antigravity.google/cli/install.sh -o "${installer}"
    [[ -s "${installer}" ]] && run_optional "antigravity" bash "${installer}"
}

# --- opencode ---------------------------------------------------------------
mod_opencode() {
    section "opencode"
    if command -v opencode >/dev/null 2>&1; then
        log_event "INFO" "opencode" "already_present" "opencode already installed" 0
        return
    fi
    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_optional "opencode" brew install anomalyco/tap/opencode
    else
        local installer="${TMP_DIR}/install-opencode.sh"
        run_optional "opencode" curl -fsSL https://opencode.ai/install -o "${installer}"
        [[ -s "${installer}" ]] && run_optional "opencode" bash "${installer}"
    fi

    log_event "INFO" "opencode" "zen_hint" "OpenCode Go / Zen provider hint" 0
    cat <<'HINT' | tee -a "${HUMAN_LOG}"
  OpenCode Go (paid) is hosted-model access; after install run: opencode auth login
  The SAME key works in pi.dev (no lock-in) — add a custom provider in pi:
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
    run_optional "cockpit" curl -fsSL \
        "https://api.github.com/repos/${COCKPIT_REPO}/releases/latest" -o "${release_json}"
    [[ -s "${release_json}" ]] || {
        log_event "WARN" "cockpit" "release_unavailable" "Could not fetch cockpit-tools release metadata"
        return
    }

    local asset_pat=""
    case "${PM}" in
        apt-get) asset_pat='amd64[^"]+\.deb|x86_64[^"]+\.deb|_amd64\.deb' ;;
        dnf|zypper) asset_pat='x86_64[^"]+\.rpm|\.rpm' ;;
        *) asset_pat='\.AppImage' ;;
    esac

    local url
    url="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' "${release_json}" \
        | cut -d '"' -f4 | grep -iE "${asset_pat}" | head -n1 || true)"

    if [[ -z "${url}" ]]; then
        log_event "WARN" "cockpit" "no_matching_asset" \
            "No matching cockpit-tools asset for ${PM}; download manually from GitHub Releases"
        return
    fi

    local installer="${TMP_DIR}/cockpit-asset"
    run_optional "cockpit" curl -fsSL "${url}" -o "${installer}"
    [[ -s "${installer}" ]] || return

    case "${PM}" in
        apt-get) run_optional "cockpit" sudo apt-get install -y "${installer}" ;;
        dnf)     run_optional "cockpit" sudo dnf install -y "${installer}" ;;
        zypper)  run_optional "cockpit" sudo zypper --non-interactive install "${installer}" ;;
        *)
            local dest="${HOME}/.local/bin/cockpit-tools.AppImage"
            mkdir -p "${HOME}/.local/bin"
            run_optional "cockpit" install -Dm755 "${installer}" "${dest}"
            log_event "INFO" "cockpit" "appimage_installed" "AppImage placed" 0 "path=${dest}"
            ;;
    esac
}

# ==============================================================================
# Shell environment
# ==============================================================================

configure_shell_env() {
    section "Shell environment"
    local shell_config="${HOME}/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && shell_config="${HOME}/.zshrc"
    [[ "${OS_FAMILY}" == "macos" && -f "${HOME}/.zshrc" ]] && shell_config="${HOME}/.zshrc"

    local marker="# AI Dev Toolsuite Environment"
    if ! grep -Fq "${marker}" "${shell_config}" 2>/dev/null; then
        cat >> "${shell_config}" <<'EOF'

# ==========================================
# AI Dev Toolsuite Environment
# ==========================================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

export BUN_INSTALL="$HOME/.bun"
export GOPATH="$HOME/go"

export PATH="$BUN_INSTALL/bin:$HOME/.pi/bin:$HOME/.local/bin:$GOPATH/bin:$HOME/.cargo/bin:$PATH"
EOF
        log_event "INFO" "shell" "environment_added" "Shell env added" 0 "file=${shell_config}"
    else
        log_event "INFO" "shell" "environment_exists" "Shell env already present" 0 "file=${shell_config}"
    fi
}

# ==============================================================================
# Quality gates (run only for modules that were selected)
# ==============================================================================

quality_gates() {
    section "Quality gates"
    run_cmd "quality" bash -n "${BASH_SOURCE[0]}"

    is_selected node && { run_cmd "quality" node --version; run_cmd "quality" npm --version; }
    is_selected bun && run_optional "quality" bun --version
    is_selected pi && run_optional "quality" pi --no-extensions --version

    if is_selected pi-workflows; then
        run_cmd "quality" node -e \
            'const root=process.argv[1]; console.log("RESOLVED="+require.resolve("pi-extensible-workflows",{paths:[root]}))' \
            "${PI_EXTENSIONS_DIR}"
    fi

    if is_selected ee && [[ -f "${ENGINEERING_EXCELLENCE_DIR}/SKILL.md" ]]; then
        log_event "INFO" "quality" "ee_gate_passed" "Engineering Excellence SKILL.md present"
    fi

    log_event "INFO" "quality" "gates_done" "Quality gates completed for selected modules"
}

# ==============================================================================
# CLI parsing / module selection
# ==============================================================================

SELECTED_MODULES=()
SELECTED_DISPLAY=""

is_selected() {
    local needle="$1" m
    for m in "${SELECTED_MODULES[@]}"; do
        [[ "${m}" == "${needle}" ]] && return 0
    done
    return 1
}

print_list() {
    printf 'AI Dev Suite %s — modules (core = installed by default):\n\n' "${SCRIPT_VERSION}"
    local m tag
    for m in "${MODULE_ORDER[@]}"; do
        if [[ -n "${MODULE_OPTIONAL[$m]:-}" ]]; then tag="optional"; else tag="core    "; fi
        printf '  [%s] %-14s %s\n' "${tag}" "${m}" "${MODULE_DESC[$m]}"
    done
    printf '\nUse: --only <csv> | --all | (default = core)\n'
}

print_help() {
    sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    printf '\n'
    print_list
}

parse_args() {
    local mode="default" only_csv=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)        mode="all"; shift ;;
            --only)       mode="only"; only_csv="${2:-}"; shift 2 ;;
            --only=*)     mode="only"; only_csv="${1#*=}"; shift ;;
            --yes|-y)     shift ;;                 # accepted for launcher parity
            --list)       print_list; exit 0 ;;
            -h|--help)    print_help; exit 0 ;;
            *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    local requested=()
    case "${mode}" in
        all)  requested=("${MODULE_ORDER[@]}") ;;
        only)
            local IFS_SAVE="${IFS}"; IFS=','
            # shellcheck disable=SC2206
            local raw=(${only_csv})
            IFS="${IFS_SAVE}"
            local r
            for r in "${raw[@]}"; do
                r="$(printf '%s' "${r}" | tr -d '[:space:]')"
                [[ -z "${r}" ]] && continue
                [[ -n "${MODULE_DESC[$r]:-}" ]] || { printf 'Unknown module: %s\n' "${r}" >&2; exit 2; }
                requested+=("${r}")
            done
            ;;
        default)
            local m
            for m in "${MODULE_ORDER[@]}"; do
                [[ -n "${MODULE_OPTIONAL[$m]:-}" ]] && continue
                requested+=("${m}")
            done
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

    SELECTED_DISPLAY="$(printf '%s ' "${SELECTED_MODULES[@]}")"
}

run_module() {
    local name="$1"
    local fn="mod_${name//-/_}"
    if ! declare -F "${fn}" >/dev/null; then
        log_event "WARN" "modules" "unknown_module" "No function for module ${name}"
        return 0
    fi
    "${fn}"
}

# ==============================================================================
# Main
# ==============================================================================

: > "${HUMAN_LOG}"
: > "${JSONL_LOG}"

log_event "INFO" "bootstrap" "start" "AI Dev Suite setup started" 0 "script_version=${SCRIPT_VERSION}"

parse_args "$@"

section "Preflight"
require_command bash
require_command curl
require_command git
detect_os

if [[ "${OS_FAMILY}" == "linux" ]]; then
    require_command sudo
fi

log_event "INFO" "bootstrap" "modules_selected" "Modules queued" 0 "modules=${SELECTED_DISPLAY}"

PI_VERSION=""
for _mod in "${SELECTED_MODULES[@]}"; do
    run_module "${_mod}"
done

configure_shell_env
quality_gates

write_report "SUCCESS" 0 "n/a" "n/a" "n/a" "n/a"

cat >> "${REPORT_FILE}" <<EOF

## Installed (selected modules)

${SELECTED_DISPLAY}

## Versions

- Node.js: \`$(command -v node >/dev/null 2>&1 && node --version || echo n/a)\`
- npm: \`$(command -v npm >/dev/null 2>&1 && npm --version || echo n/a)\`
- Bun: \`$(command -v bun >/dev/null 2>&1 && bun --version || echo n/a)\`
- Pi: \`${PI_VERSION:-n/a}\`
- Go: \`$(command -v go >/dev/null 2>&1 && go version || echo n/a)\`
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
