#!/usr/bin/env bash
# Issue #103: setup-ai owns a Pi package registration only when its own install created
# it (absent before, install succeeded, exact settings readback), and uninstall removes
# only that exact registration while a valid, unchanged receipt vouches for it. Pi roots,
# settings, auth, sessions, package data, duplicates and pre-existing registrations are
# preserved. Everything runs against a fake `pi` inside a temporary HOME.
set -Eeuo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# DRY_RUN=1 while sourcing keeps the top-level log and npm cache inside the script's TMP_DIR.
export DRY_RUN=1
# shellcheck disable=SC1090
source <(sed '/^# Main$/,$d' "${repo}/setup-ai.sh")
DRY_RUN=0
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"

OUT="${TMP_DIR}/test-output.log"
FAKE_PI_LOG="${TMP_DIR}/fake-pi.log"
spec='npm:@example/scoped-pkg@1.0.0'
# The receipt name is the sha256 of the normalized identity; both installers must agree.
digest="$(node -e 'process.stdout.write(require("node:crypto").createHash("sha256").update("npm:@example/scoped-pkg").digest("hex"))')"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    if [[ -f "${OUT}" ]]; then tail -n 20 "${OUT}" >&2; fi
    exit 1
}

fake_pi_edit() {
    node -e '
        const fs = require("node:fs");
        const [file, action, source] = process.argv.slice(1);
        let settings = {};
        try { settings = JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) { if (error.code !== "ENOENT") throw error; }
        settings.packages = settings.packages || [];
        if (action === "add") settings.packages.push(source);
        if (action === "duplicate") settings.packages.push(source, source);
        if (action === "mismatch") settings.packages.push("npm:some-other-package");
        if (action === "remove") settings.packages = settings.packages.filter((entry) => (typeof entry === "string" ? entry : entry.source) !== source);
        fs.writeFileSync(file, JSON.stringify(settings));
    ' "${PI_AGENT_DIR}/settings.json" "$@"
}

pi() {
    # Not "$*": the sourced installer sets IFS to newline+tab.
    printf '%s %s\n' "$1" "${2-}" >>"${FAKE_PI_LOG}"
    case "$1:${FAKE_PI_INSTALL:-add}:${FAKE_PI_REMOVE:-ok}" in
        install:fail:*|remove:*:fail) return 7 ;;
        install:noop:*) return 0 ;;
        install:*) fake_pi_edit "${FAKE_PI_INSTALL:-add}" "$2" ;;
        remove:*) fake_pi_edit remove "$2" ;;
        *) return 2 ;;
    esac
}
# ensure_npm_remote_sources only reads the version: npm < 12 needs no opt-in.
npm() { printf '10.9.0\n'; }

new_case() {
    local name="$1"
    PI_AGENT_DIR="${TMP_DIR}/case-${name}/agent"
    PI_NPM_DIR="${PI_AGENT_DIR}/npm"
    XDG_STATE_HOME="${TMP_DIR}/case-${name}/state"
    PI_PACKAGES_FILE="${TMP_DIR}/case-${name}/pi-packages.txt"
    receipt="${XDG_STATE_HOME}/setup-ai/ownership/pi-packages/${digest}.json"
    export XDG_STATE_HOME
    mkdir -p "${PI_AGENT_DIR}"
    printf '%s\n' "${spec}" >"${PI_PACKAGES_FILE}"
    : >"${FAKE_PI_LOG}"
    unset FAKE_PI_INSTALL FAKE_PI_REMOVE
    printf '\n=== case %s\n' "${name}" >>"${OUT}"
}

settings() { printf '%s\n' "$1" >"${PI_AGENT_DIR}/settings.json"; }
registered() {
    node -e '
        const settings = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write((settings.packages || []).map((entry) => typeof entry === "string" ? entry : entry.source).join(","));
    ' "${PI_AGENT_DIR}/settings.json"
}
install_ok() { mod_pi_packages >>"${OUT}" 2>&1; }
remove_target() { uninstall_remove_pi_package "${spec}" >>"${OUT}" 2>&1; }
pi_called() { grep -q "^$1 " "${FAKE_PI_LOG}"; }
inventory_state() {
    SELECTED_MODULES=(pi-packages)
    UNINSTALL_INCLUDE_SHELL=0
    uninstall_print_inventory | grep -F -- "${spec}"
}

# --- capture -------------------------------------------------------------------
new_case fresh
install_ok || fail 'fresh install failed'
[[ -f "${receipt}" ]] || fail "fresh registration did not publish its receipt at ${receipt}"
node -e '
    const receipt = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
    if (receipt.schemaVersion !== 1 || receipt.identity !== "npm:@example/scoped-pkg" || receipt.source !== process.argv[2]) process.exit(1);
' "${receipt}" "${spec}" || fail 'receipt does not record schemaVersion 1, the normalized identity and the exact source'
inventory_state | grep -qw owned || fail 'inventory did not report the receipt-backed registration as owned'

new_case preexisting
settings "{\"packages\":[\"${spec}\"]}"
FAKE_PI_INSTALL=noop install_ok || fail 'install over a pre-existing registration failed'
[[ ! -e "${receipt}" ]] || fail 'a pre-existing registration was claimed'
inventory_state | grep -qw unowned || fail 'inventory did not report the pre-existing registration as unowned'

new_case install-failure
if FAKE_PI_INSTALL=fail install_ok; then fail 'a failed pi install was reported as success'; fi
[[ ! -e "${receipt}" ]] || fail 'a failed install received a receipt'

new_case mismatch
if FAKE_PI_INSTALL=mismatch install_ok; then fail 'a readback without the requested identity was accepted'; fi
[[ ! -e "${receipt}" ]] || fail 'a mismatched readback received a receipt'

new_case malformed
settings '{bad json'
if install_ok; then fail 'malformed settings were accepted'; fi
if pi_called install; then fail 'pi install ran although prior absence could not be proven'; fi
[[ "$(cat "${PI_AGENT_DIR}/settings.json")" == '{bad json' ]] || fail 'malformed settings were rewritten'

new_case duplicate-after
if FAKE_PI_INSTALL=duplicate install_ok; then fail 'a duplicated readback was accepted as owned'; fi
[[ ! -e "${receipt}" ]] || fail 'a duplicated registration received a receipt'
[[ "$(registered)" == "${spec},${spec}" ]] || fail 'duplicate registrations were not preserved'

new_case receipt-collision
mkdir -p "$(dirname -- "${receipt}")"
printf 'foreign\n' >"${receipt}"
if install_ok; then fail 'a foreign receipt was accepted as ownership proof'; fi
[[ "$(cat "${receipt}")" == foreign ]] || fail 'a pre-existing receipt was overwritten'
[[ "$(registered)" == "${spec}" ]] || fail 'the registration was not preserved after the receipt failure'

new_case receipt-symlink
mkdir -p "${XDG_STATE_HOME}/setup-ai" "${TMP_DIR}/outside"
ln -s "${TMP_DIR}/outside" "${XDG_STATE_HOME}/setup-ai/ownership"
if install_ok; then fail 'a symlinked receipt directory was accepted'; fi
[[ -z "$(ls -A "${TMP_DIR}/outside")" ]] || fail 'a receipt was written outside the state root'
[[ "$(registered)" == "${spec}" ]] || fail 'the registration was not preserved after the unsafe receipt path'

new_case dry-run-install
DRY_RUN=1
install_ok || fail 'dry-run install plan failed'
DRY_RUN=0
[[ ! -e "${PI_AGENT_DIR}/settings.json" && ! -e "${XDG_STATE_HOME}" ]] || fail 'dry-run install wrote settings or a receipt'
if pi_called install; then fail 'dry-run install ran pi'; fi

# --- inventory, dry run and removal -----------------------------------------------
new_case read-only
install_ok || fail 'read-only fixture install failed'
before="$(cat "${PI_AGENT_DIR}/settings.json" "${receipt}")"
: >"${FAKE_PI_LOG}"
inventory_state >/dev/null
DRY_RUN=1
out="$(uninstall_remove_pi_package "${spec}")" || fail 'dry-run removal failed'
DRY_RUN=0
[[ "${out}" == *'would remove'* ]] || fail 'dry-run removal did not report the plan'
[[ "$(cat "${PI_AGENT_DIR}/settings.json" "${receipt}")" == "${before}" ]] || fail 'inventory or dry run changed settings or the receipt'
[[ ! -s "${FAKE_PI_LOG}" ]] || fail 'inventory or dry run invoked pi'

new_case removal
install_ok || fail 'removal fixture install failed'
fake_pi_edit add 'npm:unrelated-package'
printf 'auth\n' >"${PI_AGENT_DIR}/auth.json"
mkdir -p "${PI_AGENT_DIR}/sessions" "${PI_NPM_DIR}/node_modules/keep-me" "${PI_AGENT_DIR}/extensions/node_modules/keep-me"
printf 'session\n' >"${PI_AGENT_DIR}/sessions/keep"
printf 'data\n' >"${PI_NPM_DIR}/node_modules/keep-me/data"
printf 'data\n' >"${PI_AGENT_DIR}/extensions/node_modules/keep-me/data"
UNINSTALL_PURGE=1
remove_target || fail 'receipt-backed removal failed'
UNINSTALL_PURGE=0
grep -qx "remove ${spec}" "${FAKE_PI_LOG}" || fail 'removal did not call pi remove with the exact recorded source'
[[ "$(registered)" == 'npm:unrelated-package' ]] || fail 'removal did not remove only the exact registration'
[[ ! -e "${receipt}" ]] || fail 'successful removal left its receipt'
for kept in settings.json auth.json sessions/keep npm/node_modules/keep-me/data extensions/node_modules/keep-me/data; do
    [[ -f "${PI_AGENT_DIR}/${kept}" ]] || fail "removal deleted ${kept}"
done

new_case keep-preexisting
settings "{\"packages\":[\"${spec}\"]}"
remove_target || fail 'skipping an unowned registration failed'
if pi_called remove; then fail 'an unowned registration was removed'; fi
[[ "$(registered)" == "${spec}" ]] || fail 'an unowned registration was not preserved'

new_case keep-duplicates
settings "{\"packages\":[\"${spec}\",\"npm:@example/scoped-pkg@2.0.0\"]}"
FAKE_PI_INSTALL=noop install_ok || fail 'install over pre-existing duplicates failed'
[[ ! -e "${receipt}" ]] || fail 'pre-existing duplicates were claimed'
remove_target || fail 'skipping unowned duplicates failed'
if pi_called remove; then fail 'unowned duplicates were removed'; fi

new_case changed
install_ok || fail 'changed-registration fixture install failed'
settings '{"packages":["npm:@example/scoped-pkg@2.0.0"]}'
if remove_target; then fail 'a registration that changed since install was removed'; fi
if pi_called remove; then fail 'pi remove ran for a changed registration'; fi
[[ -f "${receipt}" && "$(registered)" == 'npm:@example/scoped-pkg@2.0.0' ]] || fail 'changed registration or its receipt was not preserved'

new_case invalid-receipt
install_ok || fail 'invalid-receipt fixture install failed'
printf '{"schemaVersion":1,"identity":"npm:other","source":"npm:other","agentDir":"/"}' >"${receipt}"
if remove_target; then fail 'a receipt for another identity authorized removal'; fi
if pi_called remove; then fail 'pi remove ran with an invalid receipt'; fi

new_case remove-failure
install_ok || fail 'remove-failure fixture install failed'
if FAKE_PI_REMOVE=fail remove_target; then fail 'a failed pi remove was reported as success'; fi
[[ -f "${receipt}" && "$(registered)" == "${spec}" ]] || fail 'a failed pi remove did not preserve the registration and receipt'

new_case removed-outside-setup-ai
install_ok || fail 'external-removal fixture install failed'
fake_pi_edit remove "${spec}"
remove_target || fail 'uninstall failed although the registration is already gone'
[[ -f "${receipt}" ]] || fail 'uninstall deleted a receipt without removing its registration'
install_ok || fail 'reinstall over a leftover matching receipt failed'
inventory_state | grep -qw owned || fail 'a leftover matching receipt did not vouch for the fresh reinstall'

new_case catalog
catalog="$(uninstall_catalog)"
[[ "${catalog}" != *'path|pi|'* ]] || fail 'the uninstall catalog still deletes Pi roots, package data or the pi binary'

printf 'PASS: Bash Pi registration ownership\n'

# --- PowerShell parity -------------------------------------------------------------
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: pwsh unavailable; PowerShell Pi ownership not exercised\n'
    exit 0
fi

ps_script="${TMP_DIR}/pi-ownership.ps1"
cat >"${ps_script}" <<'PS1'
param([string]$Repo, [string]$Root, [string]$Digest, [string]$Spec)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'setup-ai.ps1'), [ref]$null, [ref]$null)
foreach ($name in 'Write-Log','Write-StepResult','Invoke-Step','Get-PiPackageIdentity','Assert-PiPackageRegistered',
        'Get-PiPackageMatches','Get-PiPackageReceiptPath','Test-PiPackageReceiptLocation',
        'Get-PiPackageOwnershipState','Write-PiPackageReceipt','Install-PiPackageOwned') {
    $fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $fn) { throw "FAIL: $name is not defined in setup-ai.ps1" }
    . ([ScriptBlock]::Create($fn.Extent.Text))
}
$RunId = 'test'; $JsonlLog = Join-Path $Root 'ps.jsonl'; $HumanLog = Join-Path $Root 'ps.log'
$script:VerboseOutput = $false; $script:CurrentModule = 'pi-packages'; $script:LastErrorStep = ''; $script:LastErrorReturnCode = 0
$script:StepsInstalled = 0; $script:StepsVerified = 0; $script:StepsSkipped = 0; $script:StepsFailed = 0
$script:StepFailStep = ''; $script:StepFailReturnCode = 0
$global:FakePiInstall = 'add'; $global:FakePiCalls = 0

function global:pi {
    $global:FakePiCalls++
    if ($global:FakePiInstall -eq 'fail') { $global:LASTEXITCODE = 7; return }
    if ($global:FakePiInstall -eq 'noop') { return }
    $file = Join-Path $script:PiAgentDir 'settings.json'
    $data = if (Test-Path -LiteralPath $file) { Get-Content -Raw -LiteralPath $file | ConvertFrom-Json -AsHashtable } else { @{} }
    $packages = @(if ($data.ContainsKey('packages')) { $data['packages'] })
    $packages += $args[1]
    if ($global:FakePiInstall -eq 'duplicate') { $packages += $args[1] }
    $data['packages'] = $packages
    $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file
}
function Fail([string]$Message) { throw "FAIL: $Message" }
function New-Case([string]$Name) {
    $script:PiAgentDir = Join-Path $Root "ps-$Name/agent"
    $env:LOCALAPPDATA = Join-Path $Root "ps-$Name/local"
    New-Item -ItemType Directory -Force -Path $script:PiAgentDir | Out-Null
    $script:Receipt = Join-Path $env:LOCALAPPDATA "setup-ai/ownership/pi-packages/$Digest.json"
    $global:FakePiInstall = 'add'; $global:FakePiCalls = 0
}
function Test-Refused { try { Install-PiPackageOwned -Phase 'pi-packages' -Spec $Spec *>$null; return $false } catch { return $true } }

New-Case fresh
Install-PiPackageOwned -Phase 'pi-packages' -Spec $Spec *>$null
if (-not (Test-Path -LiteralPath $Receipt)) { Fail "PowerShell did not publish the receipt at $Receipt" }
$r = Get-Content -Raw -LiteralPath $Receipt | ConvertFrom-Json
if ($r.schemaVersion -ne 1 -or $r.identity -cne 'npm:@example/scoped-pkg' -or $r.source -cne $Spec) { Fail 'PowerShell receipt fields differ from the Bash schema' }
if ((Get-PiPackageOwnershipState -Spec $Spec).State -ne 'owned') { Fail 'PowerShell did not report the fresh registration as owned' }

New-Case preexisting
Set-Content -LiteralPath (Join-Path $PiAgentDir 'settings.json') -Value "{`"packages`":[`"$Spec`"]}"
$global:FakePiInstall = 'noop'
Install-PiPackageOwned -Phase 'pi-packages' -Spec $Spec *>$null
if (Test-Path -LiteralPath $Receipt) { Fail 'PowerShell claimed a pre-existing registration' }

New-Case failure
$global:FakePiInstall = 'fail'
if (-not (Test-Refused)) { Fail 'PowerShell reported a failed pi install as success' }
if (Test-Path -LiteralPath $Receipt) { Fail 'PowerShell gave a failed install a receipt' }

New-Case malformed
Set-Content -LiteralPath (Join-Path $PiAgentDir 'settings.json') -Value '{bad json'
if (-not (Test-Refused)) { Fail 'PowerShell accepted malformed settings' }
if ($global:FakePiCalls -ne 0) { Fail 'PowerShell ran pi install although prior absence could not be proven' }

New-Case duplicate
$global:FakePiInstall = 'duplicate'
if (-not (Test-Refused)) { Fail 'PowerShell accepted a duplicated readback' }
if (Test-Path -LiteralPath $Receipt) { Fail 'PowerShell gave a duplicated registration a receipt' }

New-Case collision
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Receipt) | Out-Null
Set-Content -LiteralPath $Receipt -Value 'foreign'
if (-not (Test-Refused)) { Fail 'PowerShell accepted a foreign receipt' }
if ((Get-Content -Raw -LiteralPath $Receipt).Trim() -ne 'foreign') { Fail 'PowerShell overwrote a pre-existing receipt' }

New-Case symlink
$outside = Join-Path $Root 'ps-outside'
New-Item -ItemType Directory -Force -Path $outside, (Join-Path $env:LOCALAPPDATA 'setup-ai') | Out-Null
New-Item -ItemType SymbolicLink -Path (Join-Path $env:LOCALAPPDATA 'setup-ai/ownership') -Target $outside | Out-Null
if (-not (Test-Refused)) { Fail 'PowerShell accepted a symlinked receipt directory' }
if (@(Get-ChildItem -Force -LiteralPath $outside).Count -ne 0) { Fail 'PowerShell wrote a receipt outside the state root' }

# A receipt PowerShell writes must be one Bash accepts: the shared state is the contract.
New-Case shared
$env:LOCALAPPDATA = Join-Path $Root 'shared/state'
$script:PiAgentDir = Join-Path $Root 'shared/agent'
New-Item -ItemType Directory -Force -Path $PiAgentDir | Out-Null
Install-PiPackageOwned -Phase 'pi-packages' -Spec $Spec *>$null
Write-Output 'PASS: PowerShell Pi registration ownership'
PS1

pwsh -NoProfile -File "${ps_script}" -Repo "${repo}" -Root "${TMP_DIR}" -Digest "${digest}" -Spec "${spec}" \
    || fail 'PowerShell Pi ownership checks failed'

new_case shared
PI_AGENT_DIR="${TMP_DIR}/shared/agent"
XDG_STATE_HOME="${TMP_DIR}/shared/state"
inventory_state | grep -qw owned || fail 'Bash did not accept the receipt PowerShell published'
printf 'PASS: Bash accepts the PowerShell receipt\n'
