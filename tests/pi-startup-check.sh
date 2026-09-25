#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="$(command -v node)"
export NODE_BIN
SETUP_AI_SH="${ROOT}/setup-ai.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-pi-check.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

failures=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }
check() {
    local name="$1"
    shift
    if "$@"; then pass "${name}"; else fail "${name}"; fi
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
    ' "${SETUP_AI_SH}"
}

PRODUCT_FUNCTIONS="${TEST_DIR}/product-functions.sh"
for function_name in terminate_pi_startup_process_group remove_line_from_file remove_stale_quiet_tools_switch remove_stale_rpiv_question_extension handle_quiet_tools_conflict verify_pi_startup; do
    extract_function "${function_name}" >> "${PRODUCT_FUNCTIONS}"
done

TMP_DIR="${TEST_DIR}/runtime"
HUMAN_LOG="${TEST_DIR}/human.log"
PI_AGENT_DIR="${TEST_DIR}/agent"
PI_CODING_AGENT_DIR="${PI_AGENT_DIR}"
export PI_CODING_AGENT_DIR
PI_STARTUP_PID=""
# The product functions read these process-wide globals; the harness owns them here
# because it sources the functions in isolation instead of the whole installer.
DRY_RUN=0
PI_STARTUP_WATCHDOG_PID=""
mkdir -p "${TMP_DIR}" "${PI_AGENT_DIR}" "${TEST_DIR}/home/.config/environment.d"
: > "${HUMAN_LOG}"
HOME="${TEST_DIR}/home"
export HOME
log_event() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${HUMAN_LOG}"
}
source "${PRODUCT_FUNCTIONS}"

file_mode() {
    local mode
    if mode="$(stat -c '%a' "$1" 2>/dev/null)"; then
        printf '%s' "${mode}"
    else
        stat -f '%Lp' "$1"
    fi
}

same_bytes() {
    node -e '
        const fs = require("node:fs");
        if (!fs.readFileSync(process.argv[1]).equals(fs.readFileSync(process.argv[2]))) process.exit(1);
    ' "$1" "$2"
}

write_settings() {
    cat > "${PI_AGENT_DIR}/settings.json"
}

broken_settings() {
    write_settings <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:pi-tool-display",
    "npm:neighbor"
  ]
}
JSON
}

repaired_settings() {
    write_settings <<'JSON'
{
  "packages": [
    {
      "source": "npm:gentle-pi",
      "extensions": [
        "-extensions/quiet-tools.ts",
        "-extensions/pi-pretty.ts"
      ]
    },
    "npm:pi-tool-display",
    "npm:neighbor"
  ]
}
JSON
}

check_bash_wiring() {
    local body="${TEST_DIR}/gentle-body.sh" handle_line verify_line
    extract_function mod_gentle_ai > "${body}"
    handle_line="$(grep -n '^[[:space:]]*handle_quiet_tools_conflict || return 1$' "${body}")" || return 1
    verify_line="$(grep -n '^[[:space:]]*verify_pi_startup || return 1$' "${body}")" || return 1
    [[ "${handle_line%%:*}" -lt "${verify_line%%:*}" ]]
}

# The declarations are only half the contract: a consumer that rebuilds the path from
# $HOME verifies a directory the installer never created, and the declaration grep
# alone cannot see it. Assert the two consumers too.
check_effective_agent_dir() {
    grep -Fq 'PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"' "${SETUP_AI_SH}" \
        && grep -Fq '$env:PI_CODING_AGENT_DIR' "${ROOT}/setup-ai.ps1" \
        && grep -Fq 'pi = Join-Path $PiAgentDir "skills"' "${ROOT}/setup-ai.ps1" \
        && grep -Fq '$piSettings = Join-Path $PiAgentDir "settings.json"' "${ROOT}/setup-ai.ps1"
}

check_powershell_wiring() {
    local repair_line startup_line
    repair_line="$(grep -n '^[[:space:]]*Repair-QuietToolsConflict$' "${ROOT}/setup-ai.ps1")" || return 1
    startup_line="$(grep -n '^[[:space:]]*Test-PiStartup$' "${ROOT}/setup-ai.ps1")" || return 1
    [[ "${repair_line%%:*}" -lt "${startup_line%%:*}" ]] \
        && grep -Fq 'throw "pi startup verification failed' "${ROOT}/setup-ai.ps1" \
        && grep -Fq 'Get-Command -Name pi -CommandType Application' "${ROOT}/setup-ai.ps1" \
        && grep -Fq 'Start-Job -ArgumentList $piPath' "${ROOT}/setup-ai.ps1" \
        && grep -Fq 'ExitCode = 127' "${ROOT}/setup-ai.ps1" \
        && grep -Fq 'Remove-StaleRpivQuestionExtension' "${ROOT}/setup-ai.ps1"
}

check_repair_and_neighbor_bytes() {
    local rc
    broken_settings
    printf '%s\n' 'keep this neighbor' > "${HOME}/.bashrc"
    printf '%s\n' 'export GENTLE_PI_QUIET_TOOLS=0' >> "${HOME}/.bashrc"
    printf '%s\n' 'keep this other neighbor' >> "${HOME}/.bashrc"
    chmod 640 "${HOME}/.bashrc"
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] || return 1
    node -e '
        const fs = require("node:fs");
        const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const e = s.packages[0];
        if (!e || typeof e !== "object" || e.source !== "npm:gentle-pi" ||
            !e.extensions.includes("-extensions/quiet-tools.ts") ||
            !e.extensions.includes("-extensions/pi-pretty.ts")) process.exit(1);
        if (s.packages[1] !== "npm:pi-tool-display" || s.packages[2] !== "npm:neighbor") process.exit(1);
    ' "${PI_AGENT_DIR}/settings.json" || return 1
    grep -Fqx 'keep this neighbor' "${HOME}/.bashrc" || return 1
    grep -Fqx 'keep this other neighbor' "${HOME}/.bashrc" || return 1
    ! grep -Fqx 'export GENTLE_PI_QUIET_TOOLS=0' "${HOME}/.bashrc" || return 1
    [[ "$(file_mode "${HOME}/.bashrc")" == 640 ]]
}

check_repair_is_idempotent() {
    local before="${TEST_DIR}/settings.before" rc
    repaired_settings
    cp -- "${PI_AGENT_DIR}/settings.json" "${before}"
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] && same_bytes "${before}" "${PI_AGENT_DIR}/settings.json"
}

check_stale_rpiv_extension_is_removed() {
    local before="${TEST_DIR}/rpiv.before" rc
    write_settings <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:@juicesharp/rpiv-ask-user-question",
    "npm:neighbor"
  ]
}
JSON
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] || return 1
    node -e '
        const fs = require("node:fs");
        const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        if (s.packages.includes("npm:@juicesharp/rpiv-ask-user-question") ||
            !s.packages.includes("npm:gentle-pi") || !s.packages.includes("npm:neighbor")) process.exit(1);
    ' "${PI_AGENT_DIR}/settings.json" || return 1
    grep -Fq 'rpiv_question_extension_removed' "${HUMAN_LOG}" || return 1
    cp -- "${PI_AGENT_DIR}/settings.json" "${before}"
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] && same_bytes "${before}" "${PI_AGENT_DIR}/settings.json"
}

check_stale_rpiv_terminal_entry_is_removed() {
    local before="${TEST_DIR}/rpiv-terminal.before" rc
    write_settings <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:neighbor",
    "npm:@juicesharp/rpiv-ask-user-question"
  ]
}
JSON
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] || return 1
    node -e '
        const fs = require("node:fs");
        const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        if (s.packages.includes("npm:@juicesharp/rpiv-ask-user-question") ||
            !s.packages.includes("npm:gentle-pi") || !s.packages.includes("npm:neighbor")) process.exit(1);
    ' "${PI_AGENT_DIR}/settings.json" || return 1
    cp -- "${PI_AGENT_DIR}/settings.json" "${before}"
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] && same_bytes "${before}" "${PI_AGENT_DIR}/settings.json"
}

check_powershell_stale_rpiv_terminal_entry_is_removed() {
    if ! command -v pwsh >/dev/null 2>&1; then
        printf 'SKIP: PowerShell runtime unavailable for terminal-entry parity check\n'
        return 0
    fi
    ROOT="${ROOT}" pwsh -NoProfile -Command - <<'PS'
$ErrorActionPreference = 'Stop'
$root = $env:ROOT
$source = Join-Path $root 'setup-ai.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-StaleRpivQuestionExtension' }, $true)
if ($null -eq $fn) { throw 'Remove-StaleRpivQuestionExtension not found' }
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('setup-ai-rpiv-ps-' + [guid]::NewGuid().ToString('N'))
$PiAgentDir = $testDir
function Write-Log { param($Level, $Phase, $Code, $Message, $ExitCode, $Meta) }
try {
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    @'
{
  "packages": [
    "npm:gentle-pi",
    "npm:neighbor",
    "npm:@juicesharp/rpiv-ask-user-question"
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $testDir 'settings.json') -Encoding utf8
    . ([scriptblock]::Create($fn.Extent.Text))
    $settings = Join-Path $testDir 'settings.json'
    $json = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
    if (@($json.packages) -contains 'npm:@juicesharp/rpiv-ask-user-question') { throw 'rpiv entry survived PowerShell repair' }
    if (-not (@($json.packages) -contains 'npm:gentle-pi') -or -not (@($json.packages) -contains 'npm:neighbor')) { throw 'neighbor entry was lost' }
    $before = [IO.File]::ReadAllBytes($settings)
    Remove-StaleRpivQuestionExtension
    $after = [IO.File]::ReadAllBytes($settings)
    if (-not [Linq.Enumerable]::SequenceEqual($before, $after)) { throw 'second PowerShell repair changed settings' }
} finally {
    if (Test-Path -LiteralPath $testDir) { Remove-Item -LiteralPath $testDir -Recurse -Force }
}
PS
}

check_no_shadow_is_noop() {
    local before="${TEST_DIR}/settings.no-shadow.before" rc
    write_settings <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:neighbor"
  ]
}
JSON
    cp -- "${PI_AGENT_DIR}/settings.json" "${before}"
    handle_quiet_tools_conflict
    rc=$?
    [[ "${rc}" -eq 0 ]] && same_bytes "${before}" "${PI_AGENT_DIR}/settings.json"
}

check_symlink_is_untouched() {
    local target="${HOME}/rc-target" link="${HOME}/.zshrc"
    local target_before="${TEST_DIR}/rc-target.before" link_before="${TEST_DIR}/zshrc.before"
    local direct_rc remove_rc handle_rc
    printf '%s\n' 'keep target' > "${target}"
    printf '%s\n' 'export GENTLE_PI_QUIET_TOOLS=0' >> "${target}"
    chmod 600 "${target}"
    ln -s "${target}" "${link}"
    cp -- "${target}" "${target_before}"
    cp -- "${link}" "${link_before}"
    remove_line_from_file "${link}" 'export GENTLE_PI_QUIET_TOOLS=0'
    direct_rc=$?
    [[ "${direct_rc}" -eq 2 ]] || return 1
    remove_stale_quiet_tools_switch
    remove_rc=$?
    handle_quiet_tools_conflict
    handle_rc=$?
    [[ "${remove_rc}" -eq 1 && "${handle_rc}" -eq 1 ]] || return 1
    [[ -L "${link}" ]] || return 1
    same_bytes "${target_before}" "${target}" && same_bytes "${link_before}" "${link}" \
        && grep -Fqx 'export GENTLE_PI_QUIET_TOOLS=0' "${target}" \
        && [[ "$(file_mode "${target}")" == 600 ]] \
        && grep -Fq 'stale_quiet_tools_switch_unremoved' "${HUMAN_LOG}" \
        && grep -Fq "files=${link}" "${HUMAN_LOG}" \
        && grep -Fq 'remediation=' "${HUMAN_LOG}"
}

make_fake_pi() {
    local mode="$1"
    cat > "${TEST_DIR}/bin/pi" <<EOF
#!/usr/bin/env bash
if ! "\${NODE_BIN}" -e '
const fs = require("node:fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const entry = (settings.packages || []).find((item) => item && typeof item === "object" && item.source === "npm:gentle-pi");
if (!entry || !entry.extensions.includes("-extensions/quiet-tools.ts") || !entry.extensions.includes("-extensions/pi-pretty.ts")) process.exit(1);
' "\${PI_CODING_AGENT_DIR}/settings.json"; then
    printf '%s\\n' 'Error: guarded gentle-pi entry is missing' >&2
    exit 7
fi
case '${mode}' in
    success) printf '%s\\n' 'pi startup output'; exit 0 ;;
    failure) printf '%s\\n' 'Error: Failed to load extension; Tool "read" conflicts' >&2; exit 7 ;;
    timeout)
        sleep 30 &
        child_pid=\$!
        cleanup_child() {
            kill -TERM "\$child_pid" 2>/dev/null || :
            wait "\$child_pid" 2>/dev/null || :
            exit 143
        }
        trap cleanup_child TERM INT
        printf '%s %s %s %s\\n' "\$child_pid" "\$\$" "\$(ps -o pgid= -p "\$\$" | tr -d ' ')" "\$(ps -o pgid= -p "\$child_pid" | tr -d ' ')" > "\${PI_CHILD_INFO}"
        wait "\$child_pid"
        ;;
esac
EOF
    chmod +x "${TEST_DIR}/bin/pi"
    PATH="${TEST_DIR}/bin:/usr/bin:/bin"
    export PATH
}

check_startup_success() {
    local rc
    mkdir -p "${TEST_DIR}/bin"
    repaired_settings
    make_fake_pi success
    PI_STARTUP_TIMEOUT=5
    export PI_STARTUP_TIMEOUT
    verify_pi_startup
    rc=$?
    [[ "${rc}" -eq 0 ]] && grep -Fq 'pi startup output' "${HUMAN_LOG}" && grep -Fq 'pi_startup_verified' "${HUMAN_LOG}"
}

check_startup_failure_diagnostic() {
    local rc
    repaired_settings
    make_fake_pi failure
    verify_pi_startup
    rc=$?
    [[ "${rc}" -eq 1 ]] \
        && grep -Fq 'pi_startup_failed' "${HUMAN_LOG}" \
        && grep -Fq 'Error: Failed to load extension; Tool "read" conflicts' "${HUMAN_LOG}" \
        && grep -Fq "log=${HUMAN_LOG}" "${HUMAN_LOG}" \
        && grep -Fq "settings=${PI_AGENT_DIR}/settings.json" "${HUMAN_LOG}"
}

check_startup_timeout() {
    local rc started elapsed child_pid pi_pid pi_pgid child_pgid child_state
    repaired_settings
    make_fake_pi timeout
    rm -f -- "${TEST_DIR}/child-info"
    PI_CHILD_INFO="${TEST_DIR}/child-info"
    export PI_CHILD_INFO
    PI_STARTUP_TIMEOUT=1
    export PI_STARTUP_TIMEOUT
    started="${SECONDS}"
    verify_pi_startup
    rc=$?
    elapsed=$((SECONDS - started))
    [[ "${rc}" -eq 124 ]] && (( elapsed <= 4 )) && grep -Fq '|124|' "${HUMAN_LOG}" || return 1
    if ! command -v ps >/dev/null 2>&1 || ! read -r child_pid pi_pid pi_pgid child_pgid < "${TEST_DIR}/child-info"; then
        printf 'SKIP: process-group survivor assertion unavailable on this runner\n'
        return 0
    fi
    if [[ "${pi_pid}" != "${pi_pgid}" || "${pi_pgid}" != "${child_pgid}" ]]; then
        printf 'SKIP: pi process-group control unavailable on this runner\n'
        if kill -0 "${child_pid}" 2>/dev/null; then kill -TERM "${child_pid}" 2>/dev/null || :; fi
        return 0
    fi
    local attempts=0
    while kill -0 "${child_pid}" 2>/dev/null && (( attempts < 10 )); do
        sleep 0.1
        attempts=$((attempts + 1))
    done
    if kill -0 "${child_pid}" 2>/dev/null; then
        child_state="$(ps -o stat= -p "${child_pid}" 2>/dev/null | tr -d ' ')"
        printf 'FAIL: timed-out pi child survived (state=%s)\n' "${child_state}" >&2
        return 1
    fi
}

check_startup_skip() {
    local rc
    PATH="/usr/bin:/bin"
    export PATH
    verify_pi_startup
    rc=$?
    [[ "${rc}" -eq 0 ]] && grep -Fq 'pi_startup_skipped' "${HUMAN_LOG}"
}

check_ai_memory_uninstall_owned_paths() {
    local uninstall_home="${TEST_DIR}/ai-memory-home"
    local aimem_prefix="${uninstall_home}/.local"
    local aimem_bin="${aimem_prefix}/bin/aimem"
    local aimem_share="${aimem_prefix}/share/ai-memory-kit"
    local neighbor="${aimem_prefix}/share/keep-me.txt"
    local log_file="${TEST_DIR}/ai-memory-uninstall.log"
    local rc=0

    mkdir -p "${aimem_prefix}/bin" "${aimem_share}"
    : > "${aimem_bin}"
    printf '%s\n' 'keep this unrelated neighbor' > "${neighbor}"
    HOME="${uninstall_home}" AIMEM_PREFIX="${aimem_prefix}" \
        bash "${SETUP_AI_SH}" --uninstall --yes --only ai-memory > "${log_file}" 2>&1 || rc=$?

    [[ "${rc}" -eq 0 ]] \
        && [[ ! -e "${aimem_bin}" && ! -L "${aimem_bin}" ]] \
        && [[ ! -e "${aimem_share}" && ! -L "${aimem_share}" ]] \
        && grep -Fqx 'keep this unrelated neighbor' "${neighbor}"
}

check "Bash module calls startup verification after repair and propagates failure" check_bash_wiring
check "Both installers resolve PI_CODING_AGENT_DIR" check_effective_agent_dir
check "PowerShell calls startup verification after repair and throws on failure" check_powershell_wiring
check "Repair changes only the gentle-pi entry and stale switch, preserving mode and neighbors" check_repair_and_neighbor_bytes
check "Already repaired settings are byte-level no-op" check_repair_is_idempotent
check "Stale rpiv question extension is removed while neighbors survive" check_stale_rpiv_extension_is_removed
check "Terminal stale rpiv entry is removed without invalid JSON" check_stale_rpiv_terminal_entry_is_removed
check "PowerShell terminal stale rpiv entry is removed without invalid JSON" check_powershell_stale_rpiv_terminal_entry_is_removed
check "Settings without a shadow package are byte-level no-op" check_no_shadow_is_noop
check "Symlink rc files remain links and targets remain unchanged" check_symlink_is_untouched
check "Successful pi startup is logged and output reaches HUMAN_LOG" check_startup_success
check "Failed pi startup logs the first diagnostic, log path, and settings path" check_startup_failure_diagnostic
check "Startup timeout returns 124 within the bounded window" check_startup_timeout
check "Missing pi is skipped with INFO" check_startup_skip
check "ai-memory uninstall removes only its owned paths" check_ai_memory_uninstall_owned_paths

if (( failures > 0 )); then
    printf '%d acceptance check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'All pi startup acceptance checks passed\n'
