#!/usr/bin/env bash

# ==============================================================================
# AI Dev Suite - Engineering Excellence Edition
# Version: 3.3.1
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

SCRIPT_VERSION="3.3.1"

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

# Gentle AI ecosystem configurator installer (macOS/Linux). `gentle-ai install`
# is the interactive per-agent/per-IDE selector that also wires each agent's MCP
# servers, so the tools show up under /mcp.
GENTLE_AI_INSTALL="${GENTLE_AI_INSTALL:-https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh}"

ENGINEERING_EXCELLENCE_SLUG="${ENGINEERING_EXCELLENCE_SLUG:-darkrei08/Engineering-Excellence}"
ENGINEERING_EXCELLENCE_SKILL="engineering-excellence"

# Upstream agent-skill stack mirrored from vekexasia/dotenv setup_env.sh so the
# same skills land on every OS (dotenv itself is Linux-only). Each entry is
# "<source> <skill> [<skill>...]" installed via `npx skills add`.
UPSTREAM_SKILL_SOURCES=(
    "herdrdev/herdr herdr"
    "mattpocock/skills triage grill-me grilling wayfinder domain-modeling prototype research"
    "https://github.com/pedronauck/skills typescript-advanced"
    "humanlayer/skills show-me"
)
UPSTREAM_SKILL_NAMES=(herdr triage grill-me grilling wayfinder domain-modeling prototype research typescript-advanced show-me)

PI_AGENT_DIR="${HOME}/.pi/agent"
PI_EXTENSIONS_DIR="${PI_AGENT_DIR}/extensions"
PI_NPM_DIR="${PI_AGENT_DIR}/npm"

DOTENV_DIR="${HOME}/git/personale/dotenv"
DOTENV_EXT_DIR="${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows"

COCKPIT_REPO="jlcodes99/cockpit-tools"

# --- Pi packages: per-machine defaults, all overridable ------------------------
# Declarative manifest of extra Pi packages, one source per line
# (`npm:<pkg>[@<version>]`, `git:<host>/<owner>/<repo>[@<ref>]`, or a local path;
# `#` starts a comment). This is how a NEW machine gets every extension the
# toolchain needs without hand-editing ~/.pi/agent/settings.json.
#
# Where the manifest is read from follows the same split vekexasia uses: the Pi
# CONFIG (settings, package list) lives in the dotenv checkout that ~/.pi/agent
# points at, while the extensions themselves stay separate packages:
#   1. PI_PACKAGES_FILE, when set explicitly
#   2. <pi agent dir>/pi-packages.txt   (the dotenv/config repo)
#   3. <script dir>/pi-packages.txt     (a profile kept next to the installer)
# Nothing found is not an error: no extra packages are installed.
PI_PACKAGES_FILE="${PI_PACKAGES_FILE:-}"

# Local checkout that can carry a fix not yet published upstream. setup-ai only
# reads/builds from it: it never pushes, publishes, or switches the branch of an
# existing checkout. See `install_patched_pi_workflows`.
PI_WORKFLOWS_SOURCE_DIR="${PI_WORKFLOWS_SOURCE_DIR:-${HOME}/git/personale/pi-extensible-workflows}"
PI_WORKFLOWS_FIX_REF="${PI_WORKFLOWS_FIX_REF:-fix/windows-atomic-persistence}"
PI_WORKFLOWS_REMOTE="${PI_WORKFLOWS_REMOTE:-https://github.com/darkrei08/pi-extensible-workflows.git}"

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
    if ! capture_cmd "${output_var}" "report" "${command_name}" "$@"; then
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
# ==============================================================================

MODULE_ORDER=(base node bun pi pi-packages go dotenv ee skills pi-workflows herdr gentle-ai codex antigravity opencode cockpit rotator)

module_desc() {
    case "$1" in
        base) printf '%s\n' "System packages (build tools, git, gh, python, neovim, jq, imagemagick, go)" ;;
        node) printf '%s\n' "Node.js v22 + npm@latest (nvm on Unix, winget on Windows)" ;;
        bun) printf '%s\n' "Bun runtime" ;;
        pi) printf '%s\n' "pi.dev coding agent CLI" ;;
        pi-packages) printf '%s\n' "Extra Pi packages from a declarative manifest (pi-packages.txt)" ;;
        go) printf '%s\n' "Go toolchain" ;;
        dotenv) printf '%s\n' "vekexasia/dotenv dotfiles (Linux only: clones + runs setup_env.sh)" ;;
        ee) printf '%s\n' "Engineering Excellence skill (npx skills add, all detected agents)" ;;
        skills) printf '%s\n' "Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add" ;;
        pi-workflows) printf '%s\n' "pi-extensible-workflows (patched build + npm 12 remote sources for pi installs)" ;;
        herdr) printf '%s\n' "herdr terminal multiplexer" ;;
        gentle-ai) printf '%s\n' "gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi" ;;
        codex) printf '%s\n' "OpenAI Codex CLI" ;;
        antigravity) printf '%s\n' "Google Antigravity CLI (agy)" ;;
        opencode) printf '%s\n' "opencode agent CLI (opencode-ai)" ;;
        cockpit) printf '%s\n' "cockpit-tools desktop GUI app (optional, CC BY-NC-SA)" ;;
        rotator) printf '%s\n' "tuxevil-rotator multi-account Gemini/Antigravity gateway (optional, opt-in)" ;;
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
    if ! capture_cmd npm_version "${phase}" npm --version; then
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
    local key
    for key in 'allow-remote=all' 'allow-git=all'; do
        if ! grep -qxF "${key}" "${npmrc}" 2>/dev/null; then
            printf '%s\n' "${key}" >> "${npmrc}"
        fi
    done

    # Verify the file npm will actually read, not the write we intended.
    for key in 'allow-remote=all' 'allow-git=all'; do
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

# Marker of the transient-rename retry in pi-extensible-workflows.
# The published release writes state as a bare write(.tmp) + rename() without
# retry, so a transient lock on the target (Defender, indexing, sync client, or a
# concurrent pi process) fails the run with EPERM. The fix adds `renameWithRetry`
# (EACCES/EBUSY/EPERM, bounded backoff); that symbol is the marker because the
# package version does NOT change when the fix is applied locally - only the
# artifact content proves which build is loaded.
PI_WORKFLOWS_RETRY_MARKER="renameWithRetry"

# Prove a built/installed atomic-write module carries the transient-rename retry.
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
            "path=${io_js};context=${context}"
        return 1
    fi
    log_event "INFO" "${phase}" "retry_verified" \
        "Transient-rename retry present in the loaded artifact" 0 \
        "path=${io_js};context=${context}"
}

# Derive the stable id of a Pi package source (`npm:`/`git:`/local path) so a
# readback check can match pi's own record regardless of version or ref noise.
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
# the install command we just ran. With `expect_absent` set, the check is inverted:
# it passes only when NO entry with that id is registered (used to prove that the
# published workflow package was really replaced by the patched local source).
assert_pi_package_registered() {
    local phase="$1" spec="$2" expectation="${3:-present}"
    local settings="${PI_AGENT_DIR}/settings.json" want
    want="$(pi_package_id "${spec}")"

    if [[ ! -f "${settings}" ]]; then
        log_event "ERROR" "${phase}" "settings_missing" \
            "pi settings.json not found; cannot verify installed packages" 1 "path=${settings}"
        return 1
    fi
    local rc=0
    node -e '
        const fs = require("node:fs");
        const id = (source) => {
            let spec = String(source).trim();
            spec = spec.replace(/^(npm|git):/, "").split("#")[0].replace(/\.git$/, "");
            const at = spec.lastIndexOf("@");
            if (at > 0) spec = spec.slice(0, at);
            const parts = spec.split("/");
            return parts[parts.length - 1];
        };
        let settings;
        try {
            settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        } catch {
            // An unreadable or malformed registry cannot prove absence: fail closed.
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
            const resolved = path.resolve(baseDir, spec);
            return "local:" + (process.platform === "win32" ? resolved.toLowerCase() : resolved);
        };
        const baseDir = path.dirname(process.argv[1]);
        const packages = settings.packages ?? [];
        const want = identity(process.argv[2], process.cwd());
        const found = packages.some((entry) => identity(typeof entry === "string" ? entry : entry?.source, baseDir) === want);
        process.exit(found === (process.argv[3] === "present") ? 0 : 1);
    ' "${settings}" "${want}" "${expectation}" || rc=$?
    if (( rc == 2 )); then
        log_event "ERROR" "${phase}" "settings_unreadable" \
            "pi settings.json could not be parsed; cannot prove the package state" 1 "path=${settings}"
        return 1
    fi
    if (( rc == 0 )); then
        if [[ "${expectation}" == "absent" ]]; then
            log_event "INFO" "${phase}" "package_absent" \
                "pi no longer registers the replaced package" 0 "spec=${spec}"
        else
            log_event "INFO" "${phase}" "package_registered" \
                "pi registered the package" 0 "spec=${spec}"
        fi
        return 0
    fi
    if [[ "${expectation}" == "absent" ]]; then
        log_event "ERROR" "${phase}" "package_still_registered" \
            "The replaced package is still registered in settings.json" 1 \
            "spec=${spec};settings=${settings}"
        return 1
    fi
    log_event "ERROR" "${phase}" "package_not_registered" \
        "pi did not register the package in settings.json" 1 \
        "spec=${spec};settings=${settings}"
    return 1
}

# Restore the published workflow package after a failed swap. Once the npm source is
# unregistered, a failure must not leave the workflow package missing from settings:
# the environment has to look exactly like it did before the patch attempt.
rollback_published_pi_workflows() {
    local phase="pi-workflows-patch"
    local pkg_dir="${PI_WORKFLOWS_SOURCE_DIR}/packages/core"
    local root root_pkg root_version root_io restore_failed=0

    log_event "WARN" "${phase}" "patch_rollback_start" \
        "Restoring the published workflow package after a failed swap" 0 \
        "version=${PI_WORKFLOW_VERSION}"

    # Undo the swap in reverse order: drop the local source, register the published one
    # again, then put the published build back into every npm root this module overwrote
    # (the managed root included). Ending as we started is the point.
    run_optional "${phase}" pi uninstall "${pkg_dir}"
    run_optional "${phase}" pi install "npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}"

    for root in "${PI_EXTENSIONS_DIR}" "${DOTENV_EXT_DIR}" "${PI_NPM_DIR}"; do
        [[ -f "${root}/package.json" ]] || continue
        pushd "${root}" >/dev/null
        run_optional "${phase}" npm install --save-exact --no-audit --no-fund --legacy-peer-deps \
            "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
        popd >/dev/null
    done

    # Prove the restore instead of trusting the commands: registration must be the
    # published one, the local source must be gone, and every root must hold the published
    # version without the patched marker.
    if ! assert_pi_package_registered "${phase}" "npm:pi-extensible-workflows"; then
        restore_failed=1
    fi
    if ! assert_pi_package_registered "${phase}" "${pkg_dir}" absent; then
        restore_failed=1
    fi
    for root in "${PI_EXTENSIONS_DIR}" "${DOTENV_EXT_DIR}" "${PI_NPM_DIR}"; do
        [[ -f "${root}/package.json" ]] || continue
        root_pkg="${root}/node_modules/pi-extensible-workflows/package.json"
        if [[ ! -f "${root_pkg}" ]]; then
            log_event "WARN" "${phase}" "rollback_artifact_missing" \
                "Published workflow package did not come back in this root" 0 "root=${root}"
            restore_failed=1
            continue
        fi
        root_version="$(grep -m1 '"version"' "${root_pkg}" | cut -d'"' -f4)"
        if [[ "${root_version}" != "${PI_WORKFLOW_VERSION}" ]]; then
            log_event "WARN" "${phase}" "rollback_artifact_version_mismatch" \
                "Root holds a different workflow version after rollback" 0 \
                "root=${root};expected=${PI_WORKFLOW_VERSION};actual=${root_version}"
            restore_failed=1
            continue
        fi
        root_io="${root}/node_modules/pi-extensible-workflows/dist/src/io.js"
        if [[ -f "${root_io}" ]] && grep -q "${PI_WORKFLOWS_RETRY_MARKER}" "${root_io}"; then
            log_event "WARN" "${phase}" "rollback_artifact_still_patched" \
                "Root still holds the patched build after rollback" 0 "root=${root}"
            restore_failed=1
        fi
    done

    if (( restore_failed == 0 )); then
        log_event "INFO" "${phase}" "patch_rolled_back" \
            "Published workflow package and npm roots verified after rollback" 0
        return 0
    fi
    # An unrestored environment is a hard failure, not a warning: continuing would let the
    # module report a healthy install while the roots hold a mix of both builds.
    log_event "ERROR" "${phase}" "patch_rollback_failed" \
        "Could not fully restore the published workflow package; run: pi install npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}" 1
    exit 1
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

# Build the patched workflow package from the local checkout and install it into
# BOTH pi roots. Nothing is guessed: the fix is proven in the source, then in the
# built artifact, then in the installed artifact. Any unproven step returns 1 and
# the caller keeps the published release.
install_patched_pi_workflows() {
    local phase="pi-workflows-patch"
    local src="${PI_WORKFLOWS_SOURCE_DIR}"
    local ref="${PI_WORKFLOWS_FIX_REF}"
    local pkg_dir="${src}/packages/core"
    local io_ts="${pkg_dir}/src/io.ts"
    local io_js="${pkg_dir}/dist/src/io.js"

    command -v git >/dev/null 2>&1 || {
        log_event "WARN" "${phase}" "git_missing" \
            "git is unavailable; cannot build the patched workflow package" 0 "source=${src}"
        return 1
    }

    # Accept a worktree too: `.git` is a file there, not a directory.
    if [[ ! -e "${src}/.git" ]]; then
        if [[ -e "${src}" ]]; then
            log_event "WARN" "${phase}" "source_not_git" \
                "Configured workflow source is not a git checkout" 0 "source=${src}"
            return 1
        fi
        run_cmd "${phase}" git clone "${PI_WORKFLOWS_REMOTE}" "${src}" || return 1
        # A checkout setup-ai created itself may freely move to the fix ref.
        run_optional "${phase}" git -C "${src}" checkout "${ref}"
    fi

    # Prefer a ref that already resolves locally (a shared checkout can hold the fix
    # before it is pushed), then try the remote once. The fetched ref lands in
    # refs/remotes, so that is what the second probe has to resolve.
    if ! git -C "${src}" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null; then
        run_optional "${phase}" git -C "${src}" fetch origin \
            "+refs/heads/${ref}:refs/remotes/origin/${ref}"
    fi
    if ! git -C "${src}" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null \
        && ! git -C "${src}" rev-parse --verify --quiet "refs/remotes/origin/${ref}^{commit}" >/dev/null; then
        log_event "WARN" "${phase}" "fix_ref_unavailable" \
            "Workflow fix ref is unavailable; keeping the published release" 0 \
            "ref=${ref};source=${src}"
        return 1
    fi

    # Trust the CONTENT, not the branch name: the checkout may sit on another branch,
    # and setup-ai must never switch a checkout the user owns.
    if [[ ! -f "${io_ts}" ]]; then
        log_event "WARN" "${phase}" "source_missing" \
            "Workflow source file not found; keeping the published release" 0 "path=${io_ts}"
        return 1
    fi
    if ! grep -q "${PI_WORKFLOWS_RETRY_MARKER}" "${io_ts}"; then
        log_event "WARN" "${phase}" "retry_missing_in_source" \
            "Checked-out workflow source has no transient-rename retry" 0 \
            "path=${io_ts};ref=${ref};hint=git -C ${src} checkout ${ref}"
        return 1
    fi
    log_event "INFO" "${phase}" "retry_found_in_source" \
        "Workflow source carries the transient-rename retry" 0 "path=${io_ts}"

    # packages/core builds through the workspace toolchain, so install the workspace
    # first. packages/core's own build script is POSIX-only (rm -rf, cp -R), which is
    # why the patched build is a Unix/WSL path: Windows keeps the published release
    # unless a POSIX shell is available to run that script.
    # The checkout must be an npm project root, or npm would walk up into an unrelated
    # ancestor project and rewrite its manifest.
    if [[ ! -f "${src}/package.json" ]]; then
        log_event "WARN" "${phase}" "source_not_npm_project" \
            "Workflow checkout has no package.json; nothing is installed into it" 0 \
            "source=${src}"
        return 1
    fi
    pushd "${src}" >/dev/null
    # --no-save --package-lock=false: install only what the build needs without
    # writing to the checkout's tracked manifest or lockfile - this source tree
    # belongs to the user, and setup-ai must not leave edits behind in it.
    if ! run_cmd "${phase}" npm install --no-save --package-lock=false --no-audit --no-fund; then
        popd >/dev/null
        log_event "WARN" "${phase}" "workspace_install_failed" \
            "Workspace dependencies could not be installed; keeping the published release" 0 \
            "source=${src};hint=npm 12 blocks dependency install scripts by default"
        return 1
    fi
    if ! run_cmd "${phase}" npm run build --workspace=packages/core; then
        popd >/dev/null
        log_event "WARN" "${phase}" "patch_build_failed" \
            "Workflow package build failed; keeping the published release" 0 \
            "source=${src};hint=the core build script needs a POSIX shell (rm, cp)"
        return 1
    fi
    popd >/dev/null

    assert_transient_rename_retry "${io_js}" "${phase}" "built" || return 1

    # Shared resolution roots FIRST: this only writes node_modules, so it can still
    # fail without any settings change - nothing is swapped while it can fail.
    local root verified_roots=0 skipped_roots=""
    for root in "${PI_EXTENSIONS_DIR}" "${DOTENV_EXT_DIR}"; do
        [[ -d "${root}" ]] || continue
        # Never run npm in a directory that is not an npm project root: without a local
        # package.json npm walks UP the tree and installs into an ancestor project,
        # rewriting that project's manifest.
        if [[ ! -f "${root}/package.json" ]]; then
            log_event "WARN" "${phase}" "root_not_npm_project" \
                "Resolution root has no package.json; skipping it instead of installing into an ancestor" 0 \
                "root=${root}"
            skipped_roots="${skipped_roots}${skipped_roots:+,}${root}"
            continue
        fi
        pushd "${root}" >/dev/null
        if ! run_cmd "${phase}" npm install --save-exact --no-audit --no-fund --legacy-peer-deps "${pkg_dir}"; then
            popd >/dev/null
            # The root may already carry the patched build: restore before leaving, so a
            # failure here never leaves a mixed patched/published installation behind.
            rollback_published_pi_workflows
            return 1
        fi
        popd >/dev/null
        if ! assert_transient_rename_retry \
            "${root}/node_modules/pi-extensible-workflows/dist/src/io.js" \
            "${phase}" "root=${root}"; then
            rollback_published_pi_workflows
            return 1
        fi
        verified_roots=$(( verified_roots + 1 ))
    done

    # Swap, do not add: `pi install <local path>` only ADDS an entry, so leaving the
    # npm source in place would keep the unpatched copy in the managed root and
    # register two copies of the same extension at once. From this point the published
    # package is unregistered, so every failure path restores it.
    run_optional "${phase}" pi uninstall npm:pi-extensible-workflows
    if ! assert_pi_package_registered "${phase}" "npm:pi-extensible-workflows" absent; then
        rollback_published_pi_workflows
        return 1
    fi
    if ! run_cmd "${phase}" pi install "${pkg_dir}"; then
        rollback_published_pi_workflows
        return 1
    fi
    if ! assert_pi_package_registered "${phase}" "${pkg_dir}"; then
        rollback_published_pi_workflows
        return 1
    fi

    # An unpatched copy left in the managed root would shadow the patched build at
    # import time. `pi uninstall` normally removes it; repair and verify when it
    # survived. Past the swap the whole operation is all-or-nothing, so a failure here
    # restores the published registration instead of leaving a half-patched install.
    local managed_io="${PI_NPM_DIR}/node_modules/pi-extensible-workflows/dist/src/io.js"
    if [[ -f "${managed_io}" ]]; then
        if ! grep -q "${PI_WORKFLOWS_RETRY_MARKER}" "${managed_io}"; then
            log_event "WARN" "${phase}" "managed_copy_stale" \
                "Unpatched copy survived in the managed root; replacing it with the patched build" 0 \
                "path=${managed_io}"
            pushd "${PI_NPM_DIR}" >/dev/null
            if ! run_cmd "${phase}" npm install --save-exact --no-audit --no-fund --legacy-peer-deps "${pkg_dir}"; then
                popd >/dev/null
                rollback_published_pi_workflows
                return 1
            fi
            popd >/dev/null
        fi
        if ! assert_transient_rename_retry "${managed_io}" "${phase}" "managed-root"; then
            rollback_published_pi_workflows
            return 1
        fi
    fi

    # Report what was ACTUALLY verified: a skipped root is not a verified root, and the
    # message must never claim more than the checks proved.
    log_event "INFO" "${phase}" "patched_workflow_installed" \
        "Patched pi-extensible-workflows installed and verified in ${verified_roots} resolution root(s)" 0 \
        "source=${pkg_dir};ref=${ref};verified_roots=${verified_roots};skipped_roots=${skipped_roots:-none}"
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
    unset npm_config_prefix NPM_CONFIG_PREFIX 2>/dev/null || log_event "WARN" "node" "unset_prefix_failed" "Could not unset npm prefix vars" 0

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
            "Node.js ${node_version} is too old; pi-extensible-workflows needs >= 22.19" 1
        return 1
    fi
    log_event "INFO" "node" "runtime_validated" "Node.js version satisfies workflow requirement" 0 \
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
        run_cmd "pi" sh "${installer}"
    fi
    export PATH="${HOME}/.pi/bin:${HOME}/.local/bin:${PATH}"
    require_command pi
    if ! PI_VERSION="$(pi --version 2>/dev/null)"; then
        PI_VERSION="unknown"
        log_event "WARN" "pi" "version_unavailable" "Could not read pi --version" 0
    fi
    log_event "INFO" "pi" "cli_ready" "Pi CLI detected" 0 "version=${PI_VERSION}"
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

    mkdir -p "${HOME}/git/personale"
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
        run_cmd "dotenv" bash "${DOTENV_DIR}/setup_env.sh"
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

# Candidate skill roots per agent (one per line): verification passes if
# SKILL.md exists under any of them. Every agent keeps its single existing root;
# Codex also accepts ${HOME}/.agents/skills because upstream `skills add
# --global` writes Codex skills there instead of ${HOME}/.codex/skills.
agent_skill_roots() {
    agent_skill_root "$1" || return 1
    if [[ "$1" == codex ]]; then
        printf '%s\n' "${HOME}/.agents/skills"
    fi
}

verify_skill_for_agents() {
    local phase="$1" skill="$2"; shift 2
    local agent root found checked
    for agent in "$@"; do
        found=0
        checked=""
        while IFS= read -r root; do
            checked="${checked:+${checked}, }${root}/${skill}/SKILL.md"
            if [[ -f "${root}/${skill}/SKILL.md" ]]; then
                found=1
                break
            fi
        done < <(agent_skill_roots "${agent}")
        if (( found == 0 )); then
            log_event "ERROR" "${phase}" "skill_missing" \
                "Skill SKILL.md missing for targeted agent" 1 \
                "agent=${agent};skill=${skill};checked=${checked}"
            return 1
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
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent "${agent}" --copy --yes
        target_agents+=("${agent}")
        installed_any=1
    done

    if (( installed_any == 0 )); then
        # No agent detected yet - install at least for pi (created by mod_pi).
        run_cmd "engineering-excellence" \
            npx --yes skills@latest add "${ENGINEERING_EXCELLENCE_SLUG}" \
            --skill "${ENGINEERING_EXCELLENCE_SKILL}" --global --agent pi --copy --yes
        target_agents=(pi)
    fi

    verify_skill_for_agents "engineering-excellence" "${ENGINEERING_EXCELLENCE_SKILL}" "${target_agents[@]}"
    log_event "INFO" "engineering-excellence" "skills_verified" \
        "Engineering Excellence skill verified for every targeted agent" 0 \
        "agents=$(IFS=,; printf '%s' "${target_agents[*]}")"
}

# --- upstream agent skills --------------------------------------------------
# Installs vekexasia/dotenv's skill stack on every OS via `npx skills add`.
# On Linux the dotenv module may already install these; skills add --copy is
# idempotent, so a re-run is safe.
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
                --skill "${skill_list[@]}" --global --agent "${agent}" --copy --yes
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
#   2. published pi-extensible-workflows (baseline that always stays usable)
#   3. patched local build (transient-rename retry for EPERM-prone state writes)
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

    mkdir -p "${PI_EXTENSIONS_DIR}"
    pushd "${PI_EXTENSIONS_DIR}" >/dev/null
    # Append-only, so the npm 12 remote-source opt-in written above survives.
    if [[ ! -f .npmrc ]] || ! grep -qxF 'ignore-scripts=false' .npmrc; then
        printf '%s\n' 'ignore-scripts=false' >> .npmrc
    fi
    # Mark this directory as an npm project root so `npm install` lands HERE and
    # cannot walk up the tree into an ancestor project. This matters when
    # ~/.pi/agent is symlinked into another repo (e.g. the dotenv dotfiles):
    # without a local package.json, npm would install into that repo's
    # node_modules and verification would then pick up a stale, shadowing copy.
    if [[ ! -f package.json ]]; then
        printf '%s\n' '{"name":"pi-extensions","private":true}' > package.json
    fi
    run_cmd "pi-workflows-node" npm install --save-exact --no-audit --no-fund --legacy-peer-deps \
        "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
    popd >/dev/null

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
        pushd "${DOTENV_EXT_DIR}" >/dev/null
        if [[ ! -f package.json ]]; then
            printf '%s\n' '{"name":"pi-ext-workflows","private":true}' > package.json
        fi
        # Same npm 12 opt-in for this install root.
        ensure_npm_remote_sources "${DOTENV_EXT_DIR}"
        if [[ ! -f .npmrc ]] || ! grep -qxF 'ignore-scripts=false' .npmrc; then
            printf '%s\n' 'ignore-scripts=false' >> .npmrc
        fi
        run_cmd "dotenv-workflows" npm install --save-exact --no-audit --no-fund --legacy-peer-deps \
            "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
        popd >/dev/null

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

    # 3. Patched local build LAST, so it wins in both roots over the published
    #    release installed above. A failure here is reported, never hidden: the
    #    environment keeps working with the published release.
    if install_patched_pi_workflows; then
        local patched_version="unknown"
        if ! capture_cmd patched_version "pi-workflows-patch" node -e \
            'console.log(require(process.argv[1]).version)' \
            "${PI_EXTENSIONS_DIR}/node_modules/pi-extensible-workflows/package.json"; then
            patched_version="unknown"
        fi
        log_event "INFO" "pi-workflows-patch" "patched_version_active" \
            "Effective workflow package is the patched local build" 0 \
            "version=${patched_version};published=${PI_WORKFLOW_VERSION}"
    else
        log_event "WARN" "pi-workflows-patch" "patched_build_unavailable" \
            "Keeping the published pi-extensible-workflows; EPERM-prone state writes may still fail" 0 \
            "source=${PI_WORKFLOWS_SOURCE_DIR};ref=${PI_WORKFLOWS_FIX_REF}"
    fi
}

# --- pi-packages ------------------------------------------------------------
# Declarative Pi packages: the manifest resolved by `pi_packages_manifest` lists one
# source per line, so a NEW machine gets every extension the toolchain needs
# without hand-editing ~/.pi/agent/settings.json. Supported sources are whatever
# `pi install` accepts: `npm:<pkg>[@<version>]`,
# `git:<host>/<owner>/<repo>[@<ref>]`, or a local path. Blank lines and `#`
# comments are ignored, and every install is verified by reading pi's own
# settings.json back. pi-extensible-workflows is skipped here on purpose: the
# pi-workflows module owns that package (published + patched build).
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
    command -v gentle-ai >/dev/null 2>&1 || {
        log_event "ERROR" "gentle-ai" "binary_missing" "gentle-ai CLI not found on PATH after install" 1
        return 1
    }
    run_cmd "gentle-ai" gentle-ai --version

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
    if [[ -t 0 && -t 1 ]]; then
        log_event "INFO" "gentle-ai" "configurator_start" "Launching gentle-ai install (choose agents/IDEs + MCP)" 0
        if ! gentle-ai install --scope global; then
            log_event "ERROR" "gentle-ai" "configurator_failed" "gentle-ai install failed" 1
            return 1
        fi
    else
        local agents_csv; agents_csv="$(IFS=,; printf '%s' "${detected_agents[*]}")"
        log_event "INFO" "gentle-ai" "configurator_noninteractive" \
            "No TTY; installing gentle-ai for detected agents" 0 "agents=${agents_csv}"
        run_cmd "gentle-ai" gentle-ai install --scope global --agents "${agents_csv}"
    fi
    log_event "INFO" "gentle-ai" "configurator_done" "gentle-ai install completed" 0

    # Guarantee pi reads gentle-ai in its MCP list (/mcp): install the first-class
    # gentle-pi harness and the pi-mcp-adapter bridge, then verify the exact
    # target (pi's own settings file), not a walked resolution.
    if command -v pi >/dev/null 2>&1; then
        run_cmd "gentle-ai" pi install npm:gentle-pi
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
        run_cmd "codex" sh "${installer}"
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
mod_opencode() {
    section "opencode"
    if command -v opencode >/dev/null 2>&1; then
        log_event "INFO" "opencode" "already_present" "opencode already installed" 0
        return
    fi
    if [[ "${OS_FAMILY}" == "macos" ]]; then
        run_cmd "opencode" brew install anomalyco/tap/opencode
    else
        local installer="${TMP_DIR}/install-opencode.sh"
        run_cmd "opencode" curl -fsSL https://opencode.ai/install -o "${installer}"
        [[ -s "${installer}" ]] || {
            log_event "ERROR" "opencode" "installer_missing" "opencode installer is empty" 1 "path=${installer}"
            return 1
        }
        run_cmd "opencode" bash "${installer}"
    fi
    require_command opencode

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
    if ! url="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' "${release_json}" \
        | cut -d '"' -f4 | grep -iE "${asset_pat}" | sed -n '1p')"; then
        log_event "WARN" "cockpit" "asset_parse_failed" "Could not parse cockpit-tools release assets"
        return 0
    fi

    if [[ -z "${url}" ]]; then
        log_event "WARN" "cockpit" "no_matching_asset" \
            "No matching cockpit-tools asset for ${PM}; download manually from GitHub Releases"
        return
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
            mkdir -p "${HOME}/.local/bin"
            run_optional "cockpit" install -Dm755 "${installer}" "${dest}"
            log_event "INFO" "cockpit" "appimage_installed" "AppImage placed" 0 "path=${dest}"
            ;;
    esac
}

# --- rotator (opt-in: tuxevil-rotator multi-account gateway) -----------------
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
    # Non-fatal health probe.
    local gw="http://localhost:51200/v1/models" body count
    if body="$(curl -fsS -m 5 -H 'Authorization: Bearer tuxevil' "${gw}" 2>/dev/null)"; then
        # curl -fsS already proved reachability; the count is informational only
        # (awk always exits 0, so no operational failure is masked here).
        count="$(printf '%s' "${body}" | awk '{c+=gsub(/"id"/,"&")} END{print c+0}')"
        log_event "INFO" "rotator" "gateway_up" "tuxevil-rotator gateway is reachable" 0 "url=${gw};models=${count}"
    else
        log_event "INFO" "rotator" "gateway_down" "tuxevil-rotator gateway not reachable; start it with 'tuxevil-rotator start'" 0 "url=${gw}"
    fi
    # Install the CLI idempotently. Never runs login/start or writes secrets.
    if command -v tuxevil-rotator >/dev/null 2>&1; then
        log_event "INFO" "rotator" "already_present" "tuxevil-rotator already installed" 0
    else
        run_cmd "rotator" npm install --global tuxevil-rotator
        require_command tuxevil-rotator
    fi
    if command -v pi >/dev/null 2>&1; then
        run_cmd "rotator" pi install "github:darkrei08/pi-cockpit-tools-sync"
        local pi_settings="${PI_AGENT_DIR}/settings.json"
        if [[ ! -f "${pi_settings}" ]] || ! grep -Fq 'github:darkrei08/pi-cockpit-tools-sync' "${pi_settings}"; then
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
        tuxevil-rotator start     # start the rotating proxy on http://localhost:51200
      Pi reaches it through the 'tuxevil-rotator' provider configured in your dotenv.
      The cockpit sync extension provides /cockpit-sync, /cockpit-provision, and /cockpit-proxy.
      Login/start are never run by setup-ai and no tokens are read or stored.
HINT
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
    is_selected bun && run_cmd "quality" bun --version
    if is_selected pi; then
        require_command pi
        run_cmd "quality" pi --no-extensions --version
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
        run_cmd "quality" node -e \
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
    printf 'AI Dev Suite %s - modules (core = installed by default):\n\n' "${SCRIPT_VERSION}"
    local m tag
    for m in "${MODULE_ORDER[@]}"; do
        if module_is_optional "${m}"; then tag="optional"; else tag="core    "; fi
        printf '  [%s] %-14s %s\n' "${tag}" "${m}" "$(module_desc "${m}")"
    done
    printf '\nUse: --only <csv> | --all | (default = core)\n'
}

print_help() {
    # Print the header comment (lines 3-25) without external commands: a missing or
    # failing `sed` would be an unchecked external call inside `--help`, and the
    # ERR trap would then abort the script with a confusing error.
    local line
    local -a header=()
    mapfile -t -s 2 -n 23 header < "${BASH_SOURCE[0]}"
    for line in "${header[@]}"; do
        line="${line#'# '}"
        line="${line#\#}"
        printf '%s\n' "${line}"
    done
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
            --yes|-y)     shift ;;                 # accepted for launcher parity
            --list)       print_list; exit 0 ;;
            -h|--help)    print_help; exit 0 ;;
            *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    # Match PowerShell: -All wins whenever it is present, regardless of
    # where it appears relative to --only.
    (( all_requested == 1 )) && mode="all"

    local requested=()
    case "${mode}" in
        all)  requested=("${MODULE_ORDER[@]}") ;;
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
                module_desc "${r}" >/dev/null || { printf 'Unknown module: %s\n' "${r}" >&2; exit 2; }
                requested+=("${r}")
            done
            (( ${#requested[@]} > 0 )) || {
                printf '%s\n' '--only requires a non-empty comma-separated module list.' >&2
                exit 2
            }
            ;;
        default)
            local m
            for m in "${MODULE_ORDER[@]}"; do
                module_is_optional "${m}" && continue
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
detect_os

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

PI_VERSION=""
for _mod in "${SELECTED_MODULES[@]}"; do
    run_module "${_mod}"
done

configure_shell_env
quality_gates

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
