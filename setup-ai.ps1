#Requires -Version 7.3
<#
==============================================================================
 AI Dev Suite - Engineering Excellence Edition (Windows)
 Version: 3.4.1

 Windows-native installer, sibling of setup-ai.sh. Uses each tool's official
 Windows method: winget for language runtimes, the vendor install.ps1 scripts
 for the AI CLIs, and npm for opencode, and
 `npx skills` / `pi install` for skills and pi packages.

 The Node launcher bin/setup-ai.mjs dispatches here on win32 and can pass a
 module selection via -Only (from its interactive menu).

 Usage:
   pwsh -File setup-ai.ps1                 # core module set
   pwsh -File setup-ai.ps1 -All            # every module (incl. GUI apps)
   pwsh -File setup-ai.ps1 -Only pi,codex,opencode
   pwsh -File setup-ai.ps1 -List
   pwsh -File setup-ai.ps1 -Help
==============================================================================
#>

[CmdletBinding()]
param(
    [string]$Only = "",
    [switch]$All,
    [switch]$List,
    [switch]$Yes,
    [switch]$Help
)

$OnlySpecified = $PSBoundParameters.ContainsKey('Only')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.3+ turns native nonzero exits into terminating errors, so a
# failed command cannot be hidden by a later successful command in the same step.
$PSNativeCommandUseErrorActionPreference = $true

# Render child-process UTF-8 output (npx skills box-drawing, banners) correctly
# instead of mojibake on the default Windows console codepage.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    if (Get-Command chcp -ErrorAction SilentlyContinue) { chcp 65001 | Out-Null }
} catch {
    # Non-fatal: child output may show mojibake, but the run can proceed.
    Write-Warning "Could not set UTF-8 console encoding: $($_.Exception.Message)"
}

$ScriptVersion = "3.4.1"
$ScriptPath = $PSCommandPath
$ScriptDir = Split-Path -Parent $ScriptPath
$LogDir = Join-Path $ScriptDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$RunId = (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$HumanLog = Join-Path $LogDir "setup_$RunId.log"
$JsonlLog = Join-Path $LogDir "setup_$RunId.jsonl"
$ReportFile = Join-Path $LogDir "engineering-report_$RunId.md"
$RunStartedAt = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
$RunStartTime = Get-Date

$EE_Slug  = "darkrei08/Engineering-Excellence"
$EE_Skill = "engineering-excellence"
$PiAgentDir = Join-Path $HOME ".pi\agent"
$PiExtDir   = Join-Path $PiAgentDir "extensions"
$PiNpmDir   = Join-Path $PiAgentDir "npm"

# --- Pi packages: per-machine defaults ---------------------------------------
# Declarative manifest of extra Pi packages, one source per line
# (`npm:<pkg>[@<version>]`, `git:<host>/<owner>/<repo>[@<ref>]`, or a local path;
# `#` starts a comment). Where the manifest is read from follows the same split
# the dotenv repo uses: the Pi CONFIG (settings, package list) lives in the dotenv
# checkout that ~/.pi/agent points at, while the extensions stay separate packages:
#   1. PI_PACKAGES_FILE, when set explicitly
#   2. <pi agent dir>/pi-packages.txt   (the dotenv/config repo)
#   3. <script dir>/pi-packages.txt     (a profile kept next to the installer)
# Nothing found is not an error: no extra packages are installed.
# Only the values setup-ai.sh lets the environment override are read from the
# environment here too; the pi roots and the retry marker stay fixed, as in Bash.
if (-not $env:PI_PACKAGES_FILE) { $PiPackagesFile = "" } else { $PiPackagesFile = $env:PI_PACKAGES_FILE }

# Local checkout that can carry a fix not yet published upstream. setup-ai only
# reads/builds from it: it never pushes, publishes, or switches the branch of an
# existing checkout. See Install-PatchedPiWorkflows.
if (-not $env:PI_WORKFLOWS_SOURCE_DIR) { $PiWorkflowsSourceDir = Join-Path $HOME "git\personale\pi-extensible-workflows" } else { $PiWorkflowsSourceDir = $env:PI_WORKFLOWS_SOURCE_DIR }
if (-not $env:PI_WORKFLOWS_FIX_REF) { $PiWorkflowsFixRef = 'fix/windows-atomic-persistence' } else { $PiWorkflowsFixRef = $env:PI_WORKFLOWS_FIX_REF }
if (-not $env:PI_WORKFLOWS_REMOTE) { $PiWorkflowsRemote = 'https://github.com/darkrei08/pi-extensible-workflows.git' } else { $PiWorkflowsRemote = $env:PI_WORKFLOWS_REMOTE }

# Marker of the transient-rename retry in pi-extensible-workflows. The published
# release writes state as a bare write(.tmp) + rename() without retry, so a
# transient lock on the target (Defender, indexing, sync client, or a concurrent pi
# process) fails the run with EPERM. The fix adds `renameWithRetry`; that symbol is
# the marker because the package version does NOT change when the fix is applied
# locally - only the artifact content proves which build is loaded.
$PiWorkflowsRetryMarker = 'renameWithRetry'
# Set when a rollback could not restore the published workflow package; the module turns
# that into a hard failure instead of a warning. Initialized here because StrictMode
# throws when a variable is read before it has been set.
$script:SetupAiRollbackFailed = $false
# Read by Restore-PublishedPiWorkflows before Mod-PiWorkflows ever assigns it.
$script:SetupAiWorkflowVersion = ''

# Upstream agent-skill stack mirrored from darkrei08/dotenv setup_env.sh so the
# same skills land on every OS (dotenv itself is Linux-only). Installed via
# `npx skills add`.
$UpstreamSkillSources = @(
    @{ Source = 'herdrdev/herdr';                       Skills = @('herdr') }
    @{ Source = 'mattpocock/skills';                    Skills = @('triage','grill-me','grilling','wayfinder','domain-modeling','prototype','research') }
    @{ Source = 'https://github.com/pedronauck/skills';  Skills = @('typescript-advanced') }
    @{ Source = 'humanlayer/skills';                    Skills = @('show-me') }
)
$UpstreamSkillNames = @('herdr','triage','grill-me','grilling','wayfinder','domain-modeling','prototype','research','typescript-advanced','show-me')
$SkillAgentNames = @('pi','claude-code','gemini-cli','cursor','antigravity','codex','opencode')
$SkillAgentConfigDirs = @{
    pi = Join-Path $HOME ".pi"
    'claude-code' = Join-Path $HOME ".claude"
    'gemini-cli' = Join-Path $HOME ".gemini"
    cursor = Join-Path $HOME ".cursor"
    antigravity = Join-Path $HOME ".antigravity"
    codex = Join-Path $HOME ".codex"
    opencode = Join-Path $HOME ".config\opencode"
}
$SkillAgentRoots = @{
    pi = Join-Path $HOME ".pi\agent\skills"
    'claude-code' = Join-Path $HOME ".claude\skills"
    'gemini-cli' = Join-Path $HOME ".gemini\skills"
    cursor = Join-Path $HOME ".cursor\skills"
    antigravity = Join-Path $HOME ".antigravity\skills"
    codex = Join-Path $HOME ".codex\skills"
    opencode = Join-Path $HOME ".config\opencode\skills"
}
# Candidate skill roots per agent: verification passes if SKILL.md exists in any
# of them. The agent's own config dir comes first, and the shared ~/.agents/skills
# root is accepted for every agent because upstream `skills add --global` installs
# there and names it as the install target in its own summary, copying into an
# agent's config dir only when it supports that agent. A shared root must never hide
# a skipped copy, so Assert-SkillInstalledForAgents warns per agent.
$SkillAgentCandidateRoots = @{}
foreach ($skillAgent in $SkillAgentNames) {
    $agentRoots = @()
    if ($SkillAgentRoots.ContainsKey($skillAgent)) { $agentRoots += $SkillAgentRoots[$skillAgent] }
    $agentRoots += (Join-Path $HOME ".agents\skills")
    $SkillAgentCandidateRoots[$skillAgent] = $agentRoots
}

# ------------------------------------------------------------------------------
# Logging (human + JSONL)
# ------------------------------------------------------------------------------

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$Level,
        [string]$Phase, [string]$Event, [string]$Message, [int]$ReturnCode = 0, [string]$Meta = "",
        [System.Collections.IDictionary]$Summary = $null
    )
    $ts = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
    $obj = [ordered]@{
        timestamp = $ts; level = $Level; phase = $Phase; event = $Event
        message = $Message; return_code = $ReturnCode; run_id = $RunId; pid = $PID
    }
    if ($Meta) { $obj.meta = $Meta }
    if ($Summary) { $obj.summary = $Summary }
    # -Depth 5 keeps the nested summary object (modules/steps) intact; the default of 2
    # would flatten it to type names.
    ($obj | ConvertTo-Json -Compress -Depth 5) | Add-Content -Path $JsonlLog

    # First failure wins: later wrapper events (`script_failed`, `module_failed`,
    # `completed_with_failures`) only announce the failure this one named, so they must not
    # replace the root cause the summary falls back to.
    if ($Level -eq 'ERROR' -and -not $script:LastErrorStep) {
        # Fallback diagnosis for the run summary when no step recorded the failure itself.
        $script:LastErrorStep = "$Event`: $Message"
        $script:LastErrorReturnCode = $ReturnCode
    }

    $line = "$ts [$Level] $Phase $Event`: $Message"
    $line | Add-Content -Path $HumanLog
    switch ($Level) {
        'INFO'  { Write-Host $line -ForegroundColor Blue }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'DEBUG' { if ($env:DEBUG -eq '1') { Write-Host $line -ForegroundColor DarkGray } }
        default { Write-Host $line }
    }
}

# ------------------------------------------------------------------------------
# Run summary state
#
# One `run_summary` record per run, built from the state below as the run progresses.
# Step counters are incremented by Write-StepResult from Invoke-Step; module outcomes
# come from the module loop, plus whatever was current when the failure happened.
# ------------------------------------------------------------------------------

$script:CurrentModule = ''
$script:SelectedModules = @()
$script:SucceededModules = @()
$script:FailedModules = @()
$script:RunActive = $false
$script:StepsInstalled = 0
$script:StepsVerified = 0
$script:StepsSkipped = 0
$script:StepsFailed = 0
$script:StepFailStep = ''
$script:StepFailReturnCode = 0
$script:LastErrorStep = ''
$script:LastErrorReturnCode = 0

# One machine-readable outcome per executed step, so the summary is counted from the
# run itself instead of by re-parsing the log.
# status: installed|verified|skipped|failed.
function Write-StepResult {
    param([string]$Phase, [string]$Status, [int]$ReturnCode, [string]$Step)
    switch ($Status) {
        'installed' { $script:StepsInstalled++ }
        'verified'  { $script:StepsVerified++ }
        'skipped'   { $script:StepsSkipped++ }
        'failed'    {
            $script:StepsFailed++
            $script:StepFailStep = $Step
            $script:StepFailReturnCode = $ReturnCode
        }
    }
    $level = switch ($Status) { 'failed' { 'ERROR' } 'skipped' { 'WARN' } default { 'INFO' } }
    Write-Log $level $Phase "step_result" "Step $Status" $ReturnCode "step=$Step;module=$script:CurrentModule;status=$Status"
}

# Terminal record for the run, written once from the report block, so a failed run
# still reports what failed and why.
function Write-RunSummary {
    param([string[]]$Selected, [string[]]$Succeeded, [string[]]$FailedModules, [int]$ExitCode)

    $outcome = if ($ExitCode -eq 0) { 'success' } else { 'failed' }
    $level = if ($ExitCode -eq 0) { 'INFO' } else { 'ERROR' }
    $endedAt = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
    $duration = [int]((Get-Date) - $RunStartTime).TotalSeconds
    if ($duration -lt 0) { $duration = 0 }

    # A failed step names itself; anything else falls back to the last ERROR record.
    $failedStep = $script:StepFailStep
    $failedReturnCode = $script:StepFailReturnCode
    if (-not $failedStep) {
        $failedStep = $script:LastErrorStep
        $failedReturnCode = $script:LastErrorReturnCode
    }
    # A negative code is a real Windows exit code (HRESULT style), so only 0 - "failed
    # without a code" - is replaced.
    if ($failedReturnCode -eq 0) { $failedReturnCode = 1 }

    $moduleNames = @($Selected)
    foreach ($f in @($FailedModules)) {
        # A gate can fail outside any selected module.
        if ($Selected -notcontains $f) { $moduleNames += $f }
    }

    $entries = @()
    $reportLines = @("", "## Run summary", "", "- Run ID: ``$RunId``", "- Outcome: $outcome")
    $reportLines += "- Started: $RunStartedAt"
    $reportLines += "- Ended: $endedAt ($($duration)s)"
    $mSuccess = 0; $mFailed = 0; $mSkipped = 0
    foreach ($m in $moduleNames) {
        if ($Succeeded -contains $m) { $status = 'success'; $mSuccess++ }
        elseif ($FailedModules -contains $m) { $status = 'failed'; $mFailed++ }
        else { $status = 'skipped'; $mSkipped++ }
        $entry = [ordered]@{ name = $m; status = $status }
        if ($status -eq 'failed') {
            $entry.failed_step = $failedStep
            $entry.return_code = $failedReturnCode
            $reportLines += "- Module ``$m``: failed at ``$failedStep`` (return code $failedReturnCode)"
        } else {
            $reportLines += "- Module ``$m``: $status"
        }
        $entries += $entry
    }
    $reportLines += "- Steps: $script:StepsInstalled installed, $script:StepsVerified verified, $script:StepsSkipped skipped, $script:StepsFailed failed"

    $message = "Run summary: outcome=$outcome;duration_seconds=$duration"
    $message += ";modules_success=$mSuccess;modules_failed=$mFailed;modules_skipped=$mSkipped"
    $message += ";steps_installed=$script:StepsInstalled;steps_verified=$script:StepsVerified"
    $message += ";steps_skipped=$script:StepsSkipped;steps_failed=$script:StepsFailed"
    if ($outcome -eq 'failed') {
        $message += ";failed_step=$failedStep;return_code=$failedReturnCode"
    }

    Add-Content -Path $ReportFile -Value $reportLines
    Write-Log $level "bootstrap" "run_summary" $message $ExitCode -Summary ([ordered]@{
        run_id = $RunId
        outcome = $outcome
        started_at = $RunStartedAt
        ended_at = $endedAt
        duration_seconds = $duration
        modules = $entries
        steps = [ordered]@{
            installed = $script:StepsInstalled
            verified = $script:StepsVerified
            skipped = $script:StepsSkipped
            failed = $script:StepsFailed
        }
    })
}

# PowerShell has no exit trap; this is the equivalent of the one in setup-ai.sh. A
# terminating error that escapes the module loop still ends the run with a summary.
# Argument errors exit before $script:RunActive is set and stay summary-free, which is
# also what setup-ai.sh does for `--list`, `--help` and an invalid selection.
trap {
    Write-Log ERROR "bootstrap" "script_failed" "Setup failed: $($_.Exception.Message)" 1
    if ($script:RunActive) {
        # setup-ai.sh names the module (or phase) that was current when the run failed;
        # an unexpected failure has no entry in $script:FailedModules yet, so add it here.
        $failedModules = @($script:FailedModules)
        if ($script:CurrentModule) { $failedModules += $script:CurrentModule }
        Write-RunSummary -Selected $script:SelectedModules -Succeeded $script:SucceededModules -FailedModules $failedModules -ExitCode 1
    }
    exit 1
}

function Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# winget updates the registry PATH, not the live process. Re-read it so tools
# installed this run (node, git, ...) resolve without opening a new terminal.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Run a step; $Optional means failures are logged as WARN and swallowed. $Verify marks
# a readback step, whose successful outcome counts as verified instead of installed.
function Invoke-Step {
    param(
        [string]$Phase,
        [scriptblock]$Action,
        [switch]$Optional,
        [int[]]$ExpectedExitCodes = @(),
        [switch]$Verify,
        [string]$Step = ''
    )
    # Step identity for the step_result record: an explicit label when the helper has
    # one, otherwise the action source with whitespace collapsed.
    $step = if ($Step) { $Step } else { ($Action.ToString() -replace '\s+', ' ').Trim() }
    $kind = if ($Verify) { 'verified' } else { 'installed' }
    Write-Log INFO $Phase "step_start" "Running step"
    try {
        $global:LASTEXITCODE = 0
        & $Action 2>&1 | Tee-Object -FilePath $HumanLog -Append | Out-Host
        $nativeExitCode = $global:LASTEXITCODE
        if ($nativeExitCode -ne 0) {
            if ($ExpectedExitCodes -contains $nativeExitCode) {
                Write-Log INFO $Phase "step_expected" "Step returned expected exit code $nativeExitCode" $nativeExitCode
                Write-StepResult -Phase $Phase -Status $kind -ReturnCode 0 -Step $step
                return $null
            }
            throw "Native command exited with code $nativeExitCode"
        }
        Write-Log INFO $Phase "step_ok" "Step completed"
        Write-StepResult -Phase $Phase -Status $kind -ReturnCode 0 -Step $step
        return $true
    } catch {
        $nativeExitCode = $global:LASTEXITCODE
        if ($ExpectedExitCodes -contains $nativeExitCode) {
            Write-Log INFO $Phase "step_expected" "Step returned expected exit code $nativeExitCode" $nativeExitCode
            Write-StepResult -Phase $Phase -Status $kind -ReturnCode 0 -Step $step
            return $null
        }
        # Keep the real code, including a negative HRESULT-style one; only a missing code
        # (a wrapped exception rather than a native failure) falls back to 1.
        $rc = if ($null -ne $nativeExitCode) { [int]$nativeExitCode } else { 1 }
        if ($rc -eq 0) { $rc = 1 }
        if ($Optional) {
            Write-Log WARN $Phase "step_failed_optional" "$($_.Exception.Message); continuing" 1
            Write-StepResult -Phase $Phase -Status 'skipped' -ReturnCode $rc -Step $step
            return $false
        }
        Write-Log ERROR $Phase "step_failed" "$($_.Exception.Message)" 1
        Write-StepResult -Phase $Phase -Status 'failed' -ReturnCode $rc -Step $step
        throw
    }
}

function Test-WingetInstalled {
    param([string]$Id, [string]$Phase)
    $probe = Join-Path ([IO.Path]::GetTempPath()) ("setup-ai-winget-" + [guid]::NewGuid().ToString("N") + ".log")
    $wingetNoApplicationsFoundExitCode = -1978335212 # 0x8A150014: package is not installed.
    try {
        # Keep the query inside Invoke-Step so its exit status and output are
        # logged; a failed probe is treated as "not installed" and followed
        # by the mandatory install step.
        $listed = Invoke-Step -Phase $Phase -Optional -Verify -ExpectedExitCodes $wingetNoApplicationsFoundExitCode -Action {
            winget list --id $Id -e | Out-File -LiteralPath $probe -Encoding utf8
        }
        if ($null -eq $listed) {
            Write-Log INFO $Phase "not_installed" "$Id is not installed; will install"
            return $false
        }
        return ($listed -and [bool](Select-String -Path $probe -SimpleMatch $Id -Quiet))
    } finally {
        if (Test-Path $probe) {
            try {
                Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
            } catch {
                Write-Log WARN $Phase "cleanup_failed" "Could not remove temporary winget probe: $($_.Exception.Message)"
            }
        }
    }
}

function Install-Winget {
    param([string]$Id, [string]$Phase, [switch]$Upgrade)
    if (-not (Test-Cmd winget)) {
        throw "winget not available; cannot install '$Id'"
    }
    if (Test-WingetInstalled -Id $Id -Phase $Phase) {
        if (-not $Upgrade) {
            Write-Log INFO $Phase "already_present" "$Id already installed"
            return
        }
        Invoke-Step -Phase $Phase -Action {
            winget upgrade -e --id $Id --accept-package-agreements --accept-source-agreements --silent
        }
        return
    }
    Invoke-Step -Phase $Phase -Action {
        winget install -e --id $Id --accept-package-agreements --accept-source-agreements --silent
    }
}

function Invoke-RemoteScript {
    param([string]$Url, [string]$Phase)
    # Mirrors the vendor's documented `irm <url> | iex`, but logged.
    Invoke-Step -Phase $Phase -Action {
        $script = Invoke-RestMethod -Uri $Url -UseBasicParsing
        Invoke-Expression $script
    }
}

function Test-NodeMinimum {
    if (-not (Test-Cmd node)) { return $false }
    $versionText = ""
    $ok = Invoke-Step -Phase "node" -Optional -Verify -Action {
        $script:SetupAiNodeVersionProbe = (node --version).Trim()
    }
    if (-not $ok) { return $false }
    $versionText = $script:SetupAiNodeVersionProbe
    if ($versionText -notmatch '^v?(\d+)\.(\d+)') { return $false }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    return (($major -gt 22) -or (($major -eq 22) -and ($minor -ge 19)))
}

function Assert-NodeMinimum {
    if (-not (Test-Cmd node)) {
        throw "Node.js is required; pi-extensible-workflows and @earendil-works/pi-coding-agent need Node.js 22.19 or newer"
    }
    $versionText = ""
    Invoke-Step -Phase "node" -Verify -Action {
        $script:SetupAiNodeVersion = (node --version).Trim()
    }
    $versionText = $script:SetupAiNodeVersion
    if ($versionText -notmatch '^v?(\d+)\.(\d+)') {
        throw "Could not parse Node.js version '$versionText'"
    }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if (($major -lt 22) -or (($major -eq 22) -and ($minor -lt 19))) {
        throw "Node.js $versionText is too old; pi-extensible-workflows and @earendil-works/pi-coding-agent need >= 22.19"
    }
    Write-Log INFO "node" "runtime_validated" "Node.js version satisfies the pi and workflow requirements" 0 "version=$versionText;minimum=22.19"
}

function Get-ReportCommandValue {
    param([string]$Command, [string[]]$Arguments)
    $script:SetupAiReportValue = ""
    $ok = Invoke-Step -Phase "report" -Optional -Verify -Step "$Command $($Arguments -join ' ')" -Action {
        $script:SetupAiReportValue = (& $Command @Arguments).Trim()
    }
    if ($ok -and $script:SetupAiReportValue) { return $script:SetupAiReportValue }
    return "n/a"
}

function Get-TargetSkillAgents {
    $found = @()
    foreach ($agent in $SkillAgentNames) {
        if (Test-Path $SkillAgentConfigDirs[$agent]) { $found += $agent }
    }
    if ($found.Count -eq 0) { return @('pi') }
    return $found
}

function Assert-SkillInstalledForAgents {
    param([string]$Phase, [string]$Skill, [string[]]$Agents)
    foreach ($agent in $Agents) {
        $checked = @($SkillAgentCandidateRoots[$agent] | ForEach-Object { Join-Path (Join-Path $_ $Skill) "SKILL.md" })
        if (-not ($checked | Where-Object { Test-Path $_ })) {
            throw "$Skill SKILL.md missing for targeted agent '$agent' (checked: $($checked -join ', '))"
        }
        # A skill found only under the shared root means upstream skipped the copy into
        # this agent's own config dir: reported, never hidden, and never a failure.
        $ownRoot = if ($SkillAgentRoots.ContainsKey($agent)) { $SkillAgentRoots[$agent] } else { $null }
        if ($ownRoot -and -not (Test-Path -LiteralPath (Join-Path (Join-Path $ownRoot $Skill) "SKILL.md"))) {
            Write-Log WARN $Phase "skill_not_copied_to_agent_root" "Skill is installed under the shared skills root but was not copied into this agent's own config dir" 0 "agent=$agent;skill=$Skill;shared=$(Join-Path $HOME '.agents\skills')"
        }
    }
    Write-Log INFO $Phase "skill_verified" "$Skill verified for every targeted agent" 0 "agents=$($Agents -join ',')"
}

# ==============================================================================
# Pi install roots
#
# Concept: pi reads packages from TWO user-scope npm roots, and both must hold
# the same build or one silently shadows the other.
#
#   <agentDir>\npm         managed root: what `pi install` and
#                          `pi update --extensions` write and load
#   <agentDir>\extensions  shared resolution root: what setup-ai installs into so
#                          extension code can `import` these packages
#
# Every write into those roots goes through the helpers below, so npm behavior and
# artifact verification live in one place instead of being duplicated per module.
# ==============================================================================

# Append one line to a file only when that exact line is absent, so an existing
# .npmrc (user-owned, and it may hold other npm keys) is never rewritten or
# clobbered. Returns nothing: callers re-read the file to verify the result.
function Add-LineIfMissing {
    param([string]$Path, [string]$Line)
    $present = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $present = [bool](Select-String -LiteralPath $Path -CaseSensitive -Pattern ('^' + [regex]::Escape($Line) + '$') -Quiet)
    }
    if (-not $present) { Add-Content -LiteralPath $Path -Value $Line }
}

# npm 12 turns URL/tarball ("remote") sources off by default and aborts with
# EALLOWREMOTE. pi runs its managed installs as
# `npm install <spec> --prefix <agentDir>/npm --legacy-peer-deps`, and npm resolves
# its local .npmrc from the prefix it is given, so the opt-in belongs in the
# install root itself - never globally, never in the caller's cwd.
# npm < 12 does not know the key, so it is only written when npm >= 12.
function Enable-NpmRemoteSources {
    param([string]$Dir)
    $phase = "pi-npm"
    $npmrc = Join-Path $Dir ".npmrc"

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    # Mark the directory as an npm project root, so this helper can never make npm
    # walk up into an ancestor project.
    $dirPkgJson = Join-Path $Dir "package.json"
    if (-not (Test-Path -LiteralPath $dirPkgJson -PathType Leaf)) {
        Set-Content -LiteralPath $dirPkgJson -Value '{"name":"pi-extensions","private":true}'
    }

    if (-not (Test-Cmd npm)) {
        Write-Log WARN $phase "npm_missing" "npm is unavailable; remote-source opt-in was not written" 0 "dir=$Dir"
        return
    }

    $probeOk = Invoke-Step -Phase $phase -Optional -Verify -Action { $script:SetupAiNpmVersion = (npm --version).Trim() }
    if (-not $probeOk) {
        Write-Log WARN $phase "npm_version_unavailable" "Could not read the npm version; remote-source opt-in was not written" 0 "dir=$Dir"
        return
    }
    $npmVersion = $script:SetupAiNpmVersion
    $npmMajor = ($npmVersion -split '\.')[0]
    if ($npmMajor -notmatch '^[0-9]+$') {
        Write-Log WARN $phase "npm_version_unparsed" "Could not parse the npm version; remote-source opt-in was not written" 0 "version=$npmVersion"
        return
    }

    if ([int]$npmMajor -lt 12) {
        Write-Log INFO $phase "remote_sources_default" "npm $npmVersion fetches remote sources by default; no opt-in needed" 0 "npmrc=$npmrc"
        return
    }

    # Append-only: an existing .npmrc belongs to the user and may hold other keys.
    Add-LineIfMissing -Path $npmrc -Line 'allow-remote=all'
    Add-LineIfMissing -Path $npmrc -Line 'allow-git=all'

    # Verify the file npm will actually read, not the write we intended.
    $verified = $false
    if (Test-Path -LiteralPath $npmrc -PathType Leaf) {
        $verified = [bool](Select-String -LiteralPath $npmrc -CaseSensitive -Pattern '^allow-remote=all$' -Quiet) -and [bool](Select-String -LiteralPath $npmrc -CaseSensitive -Pattern '^allow-git=all$' -Quiet)
    }
    if (-not $verified) {
        Write-Log ERROR $phase "remote_sources_unverified" "Could not enable remote sources; pi install/update would fail with EALLOWREMOTE" 1 "npmrc=$npmrc"
        throw "Could not enable npm remote sources ($npmrc)"
    }
    Write-Log INFO $phase "remote_sources_enabled" "npm $npmVersion remote (URL/tarball) sources enabled for this install root" 0 "npmrc=$npmrc"
}

# npm 12 blocks a dependency's install scripts until that package is explicitly
# approved, and `pi install` runs a plain `npm install` with no post-processing, so
# a blocked script never runs on a fresh machine. gentle-pi's postinstall is the
# load-bearing one: it installs the package-local gentle-ai review binary the `gga`
# gate uses; node-pty and pi-tool-display ship install scripts too.
#
# This is deliberately a post-install pass and NOT part of Enable-NpmRemoteSources:
# `npm install-scripts approve` only accepts an INSTALLED package (it exits ENOMATCH
# otherwise) and the npm-root helper runs before the first package exists, so on a
# fresh machine an approval there would be a silent no-op. The installer calls this
# once after the modules that install pi packages.
#
# Idempotent: every present target is approved and then rebuilt, and npm must report
# none of them pending afterwards, so the end state is the same on every run - and a
# build that failed on a previous run is retried. Approval is by NAME, not npm's
# default <pkg>@<version> pin: pi updates packages on its own (`pi update
# --extensions`), and a pinned entry stops covering the new version, re-blocking
# the script and silently removing what it installs (gentle-pi's review binary)
# until this pass runs again. An absent package and an npm without
# `install-scripts` are skips, never failures.

# Read npm's own install-script state and return the subset of $Names npm still
# reports as pending (unreviewed). Sets $script:SetupAiInstallScriptsStateOk so the
# caller can tell an empty list from an unreadable state; never throws.
function Get-PendingInstallScripts {
    param([string]$Dir, [string]$Phase, [string[]]$Names)
    $script:SetupAiInstallScriptsStateOk = $false
    $script:SetupAiInstallScriptsJson = ""
    $read = Invoke-Step -Phase $Phase -Optional -Verify -Action {
        $script:SetupAiInstallScriptsJson = (npm install-scripts ls --json --prefix $Dir | Out-String)
    }
    if (-not $read) { return @() }
    $pending = @()
    try {
        $state = $script:SetupAiInstallScriptsJson | ConvertFrom-Json
        if ($null -eq $state) { return @() }
        if ($null -ne $state.PSObject.Properties['allowScripts']) {
            foreach ($entry in @($state.allowScripts)) {
                if ($null -eq $entry) { continue }
                if (-not ($Names -contains $entry.name)) { continue }
                $changes = @()
                if ($null -ne $entry.PSObject.Properties['changes']) { $changes = @($entry.changes) }
                if (@($changes | Where-Object { $_.change -eq 'pending' }).Count -gt 0) { $pending += $entry.name }
            }
        }
        $script:SetupAiInstallScriptsStateOk = $true
        return $pending
    } catch {
        return @()
    }
}

function Approve-NpmInstallScripts {
    param([string]$Dir, [string]$Phase = "pi-npm")
    $pkgJson = Join-Path $Dir "package.json"
    # No project here means no pi package was ever installed into this root.
    if (-not (Test-Path -LiteralPath $pkgJson -PathType Leaf)) { return }
    if (-not (Test-Cmd npm)) {
        Write-Log WARN $Phase "npm_missing" "npm is unavailable; dependency install scripts cannot be approved" 0 "dir=$Dir"
        return
    }
    # Probe the subcommand instead of trusting a version number: npm < 12, and any
    # other package manager pi can be configured with, does not implement it.
    $probe = Invoke-Step -Phase $Phase -Optional -Verify -Action { npm install-scripts --help | Out-Null }
    if (-not $probe) {
        Write-Log INFO $Phase "install_scripts_unsupported" "This npm does not implement install-scripts; dependency install-script approval skipped" 0 "dir=$Dir"
        return
    }
    # The packages whose blocked install scripts the toolchain depends on; one that
    # is not installed in this root is a skip, never an error.
    $present = @()
    foreach ($pkg in @('gentle-pi','node-pty','pi-tool-display')) {
        if (Test-Path -LiteralPath (Join-Path $Dir "node_modules/$pkg/package.json") -PathType Leaf) { $present += $pkg }
    }
    if ($present.Count -eq 0) {
        Write-Log INFO $Phase "install_scripts_none_installed" "None of the install-script packages are installed; nothing to approve" 0 "dir=$Dir"
        return
    }
    # Approve every installed target and THEN run its script: approval alone does
    # not re-run a script that was blocked at install time (npm treats the package
    # as already installed), and skipping that would make a failed build permanent.
    # Re-running it is idempotent.
    foreach ($pkg in $present) {
        # Approval is a policy change and stays optional: a package that refuses it is
        # still covered by the rebuild check below.
        # --no-allow-scripts-pin approves the package by name, so the policy keeps
        # covering the versions pi installs later; npm collapses an existing pinned
        # entry for the same package into it.
        $null = Invoke-Step -Phase $Phase -Optional -Action { npm install-scripts approve --no-allow-scripts-pin $pkg --prefix $Dir }
        # The rebuild is load-bearing: a blocked postinstall can be the step that installs
        # a required artifact (gentle-pi ships its review binary this way), so a failure
        # here fails the run instead of degrading to a warning.
        # --foreground-scripts keeps build output and errors in the log.
        $null = Invoke-Step -Phase $Phase -Action { npm rebuild $pkg --foreground-scripts --prefix $Dir }
    }
    # An exit code is not proof that the artifact exists, so the load-bearing one is read
    # from disk: gentle-pi's postinstall is what installs the review binary.
    $gentlePiDir = Join-Path $Dir "node_modules/gentle-pi"
    if (Test-Path -LiteralPath $gentlePiDir -PathType Container) {
        $reviewBinary = @(Get-ChildItem -LiteralPath (Join-Path $gentlePiDir ".gentle-ai") -Recurse -File -Filter "gentle-ai*" -ErrorAction SilentlyContinue)
        if ($reviewBinary.Count -eq 0) {
            Write-Log ERROR $Phase "review_binary_missing" "gentle-pi review binary missing after its install scripts ran" 1 "dir=$Dir;expected=$gentlePiDir/.gentle-ai/*/gentle-ai*"
            throw "gentle-pi review binary missing after rebuild"
        }
        Write-Log INFO $Phase "review_binary_verified" "gentle-pi review binary present after the rebuild" 0 "binary=$($reviewBinary[0].FullName)"
    }
    # Verify by re-reading npm's own state: nothing we approved may still be pending.
    $pending = @(Get-PendingInstallScripts -Dir $Dir -Phase $Phase -Names $present)
    if (-not $script:SetupAiInstallScriptsStateOk) {
        # Fail closed: without npm's own state there is no proof the blocked scripts ran,
        # and reporting success would ship an unverified install.
        Write-Log ERROR $Phase "install_scripts_state_unreadable" "Could not re-read the npm install-script state to verify approval" 1 "dir=$Dir"
        throw "npm install-script state unreadable; approval could not be verified"
    }
    if ($pending.Count -gt 0) {
        Write-Log ERROR $Phase "install_scripts_unverified" "npm still reports install scripts as unapproved after approve" 1 "dir=$Dir;packages=$($pending -join ',')"
        throw "npm still reports install scripts as unapproved: $($pending -join ',')"
    }
    Write-Log INFO $Phase "install_scripts_approved" "Dependency install scripts approved and executed" 0 "dir=$Dir;packages=$($present -join ',')"
}

# Raw probe for the transient-rename marker: $true when the file exists and contains
# the marker. Never logs and never throws; callers decide what a miss means.
function Test-TransientRenameMarker {
    param([string]$IoJs)
    if (-not (Test-Path -LiteralPath $IoJs -PathType Leaf)) { return $false }
    try {
        return [bool](Select-String -LiteralPath $IoJs -SimpleMatch $PiWorkflowsRetryMarker -Quiet)
    } catch {
        # An unreadable artifact cannot be proven either; treat it as a miss.
        return $false
    }
}

# Prove a built/installed atomic-write module carries the transient-rename retry.
# Returns $false with a WARN when it cannot be proven, so callers decide the fallback.
function Assert-TransientRenameRetry {
    param([string]$IoJs, [string]$Phase, [string]$Context)

    if (-not (Test-Path -LiteralPath $IoJs -PathType Leaf)) {
        Write-Log WARN $Phase "retry_probe_missing" "Atomic-write module not found; cannot prove the transient-rename retry" 0 "path=$IoJs;context=$Context"
        return $false
    }
    if (-not (Test-TransientRenameMarker -IoJs $IoJs)) {
        Write-Log WARN $Phase "retry_missing" "Artifact has no transient-rename retry; EPERM-prone state writes stay unfixed" 0 "path=$IoJs;context=$Context"
        return $false
    }
    Write-Log INFO $Phase "retry_verified" "Transient-rename retry present in the loaded artifact" 0 "path=$IoJs;context=$Context"
    return $true
}

# Derive the stable id of a Pi package source (`npm:`/`git:`/local path) so a
# readback check can match pi's own record regardless of version or ref noise.
function Get-PiPackageId {
    param([string]$Spec)
    $spec = ([string]$Spec).Trim()
    # Windows counterpart of a POSIX path: a local source recorded by pi may use
    # backslashes on either side, so the id must not depend on the separator.
    $spec = $spec.Replace('\', '/')
    if ($spec.StartsWith('npm:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
    } elseif ($spec.StartsWith('git:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
    }
    $hash = $spec.IndexOf('#')
    if ($hash -ge 0) { $spec = $spec.Substring(0, $hash) }
    if ($spec.EndsWith('.git', [StringComparison]::Ordinal)) { $spec = $spec.Substring(0, $spec.Length - 4) }
    # Strip a trailing @ref/@version, but keep a leading @scope.
    $at = $spec.LastIndexOf('@')
    if ($at -gt 0 -and $spec[$at - 1] -ne '/') { $spec = $spec.Substring(0, $at) }
    $slash = $spec.LastIndexOf('/')
    if ($slash -ge 0) { $spec = $spec.Substring($slash + 1) }
    return $spec
}

# Prove pi recorded a package by reading back pi's own registry, not by trusting
# the install command we just ran. With -Expectation absent the check is inverted:
# it passes only when NO entry with that id is registered (used to prove that the
# published workflow package was really replaced by the patched local source).
function Get-PiPackageIdentity {
    param([string]$Spec, [string]$BaseDir)
    $spec = ([string]$Spec).Trim()
    # Identity keeps scope and owner: comparing basenames made `npm:@scope/pkg`
    # match `npm:pkg`, and two `git:host/owner/repo` sources with the same repo name
    # match each other.
    if ($spec.StartsWith('npm:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
        $at = $spec.LastIndexOf('@')
        if ($at -gt 0) { $spec = $spec.Substring(0, $at) }
        return "npm:$spec"
    }
    if ($spec.StartsWith('git:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
        $hash = $spec.IndexOf('#')
        if ($hash -ge 0) { $spec = $spec.Substring(0, $hash) }
        if ($spec.EndsWith('.git', [StringComparison]::Ordinal)) { $spec = $spec.Substring(0, $spec.Length - 4) }
        $at = $spec.LastIndexOf('@')
        if ($at -gt 0) { $spec = $spec.Substring(0, $at) }
        return "git:$spec"
    }
    # Local sources may be recorded relative to the agent directory.
    # A leading ~ is the user profile, not a directory named "~" under the agent dir.
    if ($spec -eq '~' -or $spec.StartsWith('~/') -or $spec.StartsWith('~\')) {
        $spec = Join-Path $HOME $spec.Substring(1).TrimStart([char]'\', [char]'/')
    }
    $full = if ([System.IO.Path]::IsPathRooted($spec)) { [System.IO.Path]::GetFullPath($spec) } else { [System.IO.Path]::GetFullPath((Join-Path $BaseDir $spec)) }
    return "local:" + $full.ToLowerInvariant()
}

function Assert-PiPackageRegistered {
    param([string]$Phase, [string]$Spec, [string]$Expectation = "present")
    $settings = Join-Path $PiAgentDir "settings.json"
    $want = Get-PiPackageIdentity -Spec $Spec -BaseDir $PiAgentDir
    $expectAbsent = ($Expectation -eq "absent")

    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        Write-Log ERROR $Phase "settings_missing" "pi settings.json not found; cannot verify installed packages" 1 "path=$settings"
        throw "pi settings.json not found ($settings)"
    }
    $entries = @()
    try {
        $parsed = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
        if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['packages']) { $entries = @($parsed.packages) }
    } catch {
        # An unparsable registry cannot prove anything, absence included: fail closed
            # instead of reporting the package as missing.
            Write-Log ERROR $Phase "settings_unreadable" "pi settings.json could not be parsed; cannot prove the package state" 1 "path=$settings"
            throw "pi settings.json could not be parsed ($settings)"
    }
    $found = $false
    foreach ($entry in $entries) {
        if ($null -eq $entry) { continue }
        $source = ""
        if ($entry -is [string]) {
            $source = $entry
        } else {
            $sourceProp = $entry.PSObject.Properties['source']
            if ($null -ne $sourceProp) { $source = [string]$sourceProp.Value }
        }
        if ($source -and ((Get-PiPackageIdentity -Spec $source -BaseDir $PiAgentDir) -ieq $want)) { $found = $true; break }
    }
    if ($found -eq (-not $expectAbsent)) {
        if ($expectAbsent) {
            Write-Log INFO $Phase "package_absent" "pi no longer registers the replaced package" 0 "spec=$Spec"
        } else {
            Write-Log INFO $Phase "package_registered" "pi registered the package" 0 "spec=$Spec"
        }
        return
    }
    if ($expectAbsent) {
        Write-Log ERROR $Phase "package_still_registered" "The replaced package is still registered in settings.json" 1 "spec=$Spec;settings=$settings"
        throw "The replaced package is still registered in settings.json ($Spec)"
    }
    Write-Log ERROR $Phase "package_not_registered" "pi did not register the package in settings.json" 1 "spec=$Spec;settings=$settings"
    throw "pi did not register the package in settings.json ($Spec)"
}

# Restore the published workflow package after a failed swap. Once the npm source is
# unregistered, a failure must not leave the workflow package missing from settings:
# the environment has to look exactly like it did before the patch attempt.
function Restore-PublishedPiWorkflows {
    $phase = "pi-workflows-patch"
    $pkgDir = Join-Path $PiWorkflowsSourceDir "packages\core"
    $ver = $script:SetupAiWorkflowVersion
    if (-not $ver) {
        # Route the lookup through Invoke-Step so the command and its diagnostics are
        # logged instead of being swallowed by a silent try/catch.
        $null = Invoke-Step -Phase $phase -Optional -Verify -Action { $script:SetupAiWorkflowVersion = (npm view pi-extensible-workflows version).Trim() }
        $ver = $script:SetupAiWorkflowVersion
    }

    Write-Log WARN $phase "patch_rollback_start" "Restoring the published workflow package after a failed swap" 0 "version=$ver"
    if (-not $ver) {
        $script:SetupAiRollbackFailed = $true
    Write-Log ERROR $phase "patch_rollback_failed" "Could not restore the published workflow package; run: pi install npm:pi-extensible-workflows" 1
        return $false
    }

    # Undo the swap in reverse order: drop the local source, register the published one
    # again, then put the published build back into every resolution root this module
    # overwrote. Ending as we started is the point - a rollback that restores only the
    # registration would leave a mix of local and published artifacts behind.
    $null = Invoke-Step -Phase $phase -Optional -Action { pi uninstall $pkgDir }
    $null = Invoke-Step -Phase $phase -Optional -Action { pi install "npm:pi-extensible-workflows@$ver" }
    foreach ($root in @($PiExtDir, $PiNpmDir)) {
        if (-not (Test-Path -LiteralPath (Join-Path $root "package.json") -PathType Leaf)) { continue }
        Push-Location $root
        try {
            $null = Invoke-Step -Phase $phase -Optional -Action { npm install --save-exact --no-audit --no-fund --legacy-peer-deps "pi-extensible-workflows@$ver" }
        } finally {
            Pop-Location
        }
    }

    # Prove the restore instead of trusting the commands: the registration AND the exact
    # artifact inside every root we touched must be back on the published build. A root
    # left on the patched build means the environment is mixed, which is what a rollback
    # must never leave behind.
    $restoreFailed = $false
    try {
        Assert-PiPackageRegistered -Phase $phase -Spec $pkgDir -Expectation "absent"
            Assert-PiPackageRegistered -Phase $phase -Spec "npm:pi-extensible-workflows"
    } catch {
        $restoreFailed = $true
    }
    foreach ($root in @($PiExtDir, $PiNpmDir)) {
        if (-not (Test-Path -LiteralPath (Join-Path $root "package.json") -PathType Leaf)) { continue }
        $rootPkg = Join-Path $root "node_modules\pi-extensible-workflows\package.json"
        if (-not (Test-Path -LiteralPath $rootPkg -PathType Leaf)) {
            Write-Log WARN $phase "rollback_artifact_missing" "Published workflow package did not come back in this root" 0 "root=$root"
            $restoreFailed = $true
            continue
        }
        $rootVersion = $null
        try {
            $rootVersion = (Get-Content -Raw -LiteralPath $rootPkg | ConvertFrom-Json).version
        } catch {
            # An unreadable artifact cannot prove the restore: fail closed here instead of
            # letting the exception escape past the rollback-failure latch below.
            Write-Log WARN $phase "rollback_artifact_unreadable" "Published workflow package metadata could not be read after rollback" 0 "root=$root;error=$($_.Exception.Message)"
            $restoreFailed = $true
            continue
        }
        if ($rootVersion -ne $ver) {
            Write-Log WARN $phase "rollback_artifact_version_mismatch" "Root holds a different workflow version after rollback" 0 "root=$root;expected=$ver;actual=$rootVersion"
            $restoreFailed = $true
            continue
        }
        $rootIo = Join-Path $root "node_modules\pi-extensible-workflows\dist\src\io.js"
        if (-not (Test-Path -LiteralPath $rootIo -PathType Leaf)) {
            Write-Log WARN $phase "rollback_entry_point_missing" "Published workflow package came back without its entry point; the restored build cannot be used" 0 "root=$root"
            $restoreFailed = $true
            continue
        }
        # A missing or unreadable entry point is not proof of a clean restore, so the marker
        # state is read explicitly and an unreadable file keeps the restore unproven.
        $markerState = "absent"
        try {
            if (Select-String -LiteralPath $rootIo -SimpleMatch $PiWorkflowsRetryMarker -Quiet) { $markerState = "present" }
        } catch {
            $markerState = "unreadable"
        }
        if ($markerState -eq "unreadable") {
            Write-Log WARN $phase "rollback_entry_point_unreadable" "Entry point could not be read after rollback; the restore is unproven" 0 "root=$root"
            $restoreFailed = $true
            continue
        }
        if ($markerState -eq "present") {
            Write-Log WARN $phase "rollback_artifact_still_patched" "Root still holds the patched build after rollback" 0 "root=$root"
            $restoreFailed = $true
        }
    }

    if (-not $restoreFailed) {
        Write-Log INFO $phase "patch_rolled_back" "Published workflow package and resolution roots verified after rollback" 0
        return $true
    }
    $script:SetupAiRollbackFailed = $true
    Write-Log ERROR $phase "patch_rollback_failed" "Could not fully restore the published workflow package; run: pi install npm:pi-extensible-workflows@$ver" 1
    return $false
}

# Resolve the Pi package manifest. Order: explicit override, then the Pi config
# repo (~/.pi/agent usually symlinks into a dotenv checkout), then a profile kept
# next to the installer. Returns the chosen path, or $null when none exists.
function Get-PiPackagesManifest {
    $candidates = @($PiPackagesFile, (Join-Path $PiAgentDir "pi-packages.txt"), (Join-Path $ScriptDir "pi-packages.txt"))
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

# Build the patched workflow package from the local checkout and install it into
# EVERY pi root. Nothing is guessed: the fix is proven in the source, then in the
# built artifact, then in each installed artifact. Any unproven step returns $false
# and the caller keeps the published release.
function Install-PatchedPiWorkflows {
    $phase = "pi-workflows-patch"
    # One attempt, one verdict: never inherit a previous run's rollback outcome.
    $script:SetupAiRollbackFailed = $false
    # Tracks any filesystem mutation this run made, not only the registration swap: once a
    # root holds the patched build, a later failure must restore before reporting the
    # fallback, or the caller would claim a published release that is not the one installed.
    $environmentMutated = $false
    $src = $PiWorkflowsSourceDir
    $ref = $PiWorkflowsFixRef
    $pkgDir = Join-Path $src "packages\core"
    $ioTs = Join-Path $pkgDir "src\io.ts"
    $ioJs = Join-Path $pkgDir "dist\src\io.js"

    try {
        if (-not (Test-Cmd git)) {
            Write-Log WARN $phase "git_missing" "git is unavailable; cannot build the patched workflow package" 0 "source=$src"
            return $false
        }

        # Accept a worktree too: `.git` is a file there, not a directory.
        if (-not (Test-Path -LiteralPath (Join-Path $src ".git"))) {
            if (Test-Path -LiteralPath $src) {
                Write-Log WARN $phase "source_not_git" "Configured workflow source is not a git checkout" 0 "source=$src"
                return $false
            }
            $null = Invoke-Step -Phase $phase -Action { git clone $PiWorkflowsRemote $src }
            # A checkout setup-ai created itself may freely move to the fix ref.
            $null = Invoke-Step -Phase $phase -Optional -Action { git -C $src checkout $ref }
        }

        # Prefer a ref that already resolves locally (a shared checkout can hold the fix
        # before it is pushed), then try the remote once. The fetched ref lands in
        # refs/remotes, so that is what the second probe has to resolve.
        $refOk = Invoke-Step -Phase $phase -Optional -Verify -ExpectedExitCodes @(1, 128) -Action {
            git -C $src rev-parse --verify --quiet "$ref^{commit}"
        }
        if (-not $refOk) {
            $null = Invoke-Step -Phase $phase -Optional -Action { git -C $src fetch origin "+refs/heads/$ref`:refs/remotes/origin/$ref" }
            $refOk = Invoke-Step -Phase $phase -Optional -Verify -ExpectedExitCodes @(1, 128) -Action {
                git -C $src rev-parse --verify --quiet "$ref^{commit}"
            }
            if (-not $refOk) {
                $refOk = Invoke-Step -Phase $phase -Optional -Verify -ExpectedExitCodes @(1, 128) -Action {
                    git -C $src rev-parse --verify --quiet "refs/remotes/origin/$ref^{commit}"
                }
            }
        }
        if (-not $refOk) {
            Write-Log WARN $phase "fix_ref_unavailable" "Workflow fix ref is unavailable; keeping the published release" 0 "ref=$ref;source=$src"
            return $false
        }

        # Trust the CONTENT, not the branch name: the checkout may sit on another branch,
        # and setup-ai must never switch a checkout the user owns.
        if (-not (Test-Path -LiteralPath $ioTs -PathType Leaf)) {
            Write-Log WARN $phase "source_missing" "Workflow source file not found; keeping the published release" 0 "path=$ioTs"
            return $false
        }
        $retryInSource = Test-TransientRenameMarker -IoJs $ioTs
        if (-not $retryInSource) {
            Write-Log WARN $phase "retry_missing_in_source" "Checked-out workflow source has no transient-rename retry" 0 "path=$ioTs;ref=$ref;hint=git -C $src checkout $ref"
            return $false
        }
        Write-Log INFO $phase "retry_found_in_source" "Workflow source carries the transient-rename retry" 0 "path=$ioTs"

        # The POSIX form is passed as an ARGUMENT, never interpolated into shell source: a path
        # containing a quote could otherwise inject shell syntax. packages/core's build script
        # is POSIX-only (rm -rf, cp -R), so on Windows the
        # patched build runs through a POSIX shell when one exists: plain PowerShell or
        # cmd fails with "'rm' is not recognized". Without a shell the published release
        # stays in place; this module never fails for that.
        $bashExe = ""
        if (Test-Cmd bash) { $bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source }
        if (-not $bashExe) {
            $gitBashCandidates = @()
            if ($env:ProgramFiles) { $gitBashCandidates += (Join-Path $env:ProgramFiles "Git\bin\bash.exe") }
            if (${env:ProgramFiles(x86)}) { $gitBashCandidates += (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe") }
            foreach ($candidate in $gitBashCandidates) {
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $bashExe = $candidate; break }
            }
        }
        if (-not $bashExe) {
            Write-Log WARN $phase "posix_shell_missing" "No POSIX shell found; the core build script (rm, cp) cannot run here; keeping the published release" 0 "source=$src"
            return $false
        }

        # The checkout must be an npm project root, or npm would walk up into an unrelated
        # ancestor project and rewrite its manifest.
        if (-not (Test-Path -LiteralPath (Join-Path $src "package.json") -PathType Leaf)) {
            Write-Log WARN $phase "source_not_npm_project" "Workflow checkout has no package.json; nothing is installed into it" 0 "source=$src"
            return $false
        }

        # packages/core builds through the workspace toolchain, so install the workspace
        # FIRST: typescript/esbuild come from its devDependencies and are hoisted by npm.
        # --no-save --package-lock=false: install only what the build needs without
        # writing to the checkout's tracked manifest or lockfile - this source tree
        # belongs to the user, and setup-ai must not leave edits behind in it.
        Push-Location $src
        try {
            $workspaceOk = Invoke-Step -Phase $phase -Optional -Action { npm install --no-save --package-lock=false --no-audit --no-fund }
            if (-not $workspaceOk) {
                Write-Log WARN $phase "workspace_install_failed" "Workspace dependencies could not be installed; keeping the published release" 0 "source=$src;hint=npm 12 blocks dependency install scripts by default"
                return $false
            }
            $buildOk = Invoke-Step -Phase $phase -Optional -Action {
                $srcPosix = $src.Replace([char]92, [char]47)   # backslash -> slash
                & $bashExe -c 'cd "$1" && npm run build --workspace=packages/core' setup-ai-build $srcPosix
            }
            if (-not $buildOk) {
                Write-Log WARN $phase "patch_build_failed" "Workflow package build failed; keeping the published release" 0 "source=$src;hint=the core build script needs a POSIX shell (rm, cp)"
                return $false
            }
        } finally {
            Pop-Location
        }

        if (-not (Assert-TransientRenameRetry -IoJs $ioJs -Phase $phase -Context "built")) { return $false }

        # Shared resolution roots FIRST: this only writes node_modules, so it can still
        # fail without any settings change - nothing is swapped while it can fail.
        # The dotenv extension root that setup-ai.sh patches is deliberately NOT here:
        # the dotenv flow is Linux-only, so on Windows that path is not an npm project
        # and nothing installs into it.
        $verifiedRoots = 0
        $skippedRoots = @()
        foreach ($root in @($PiExtDir, $PiNpmDir)) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
            # Never run npm in a directory that is not an npm project root: without a local
            # package.json npm walks UP the tree and installs into an ancestor project,
            # rewriting that project's manifest (observed once: it rewrote
            # <dotenv>\pi\agent\package.json and created ~169 MB of node_modules there).
            if (-not (Test-Path -LiteralPath (Join-Path $root "package.json") -PathType Leaf)) {
                Write-Log WARN $phase "root_not_npm_project" "Resolution root has no package.json; skipping it instead of installing into an ancestor" 0 "root=$root"
                $skippedRoots += $root
                continue
            }
            Push-Location $root
            try {
                $environmentMutated = $true
                $rootOk = Invoke-Step -Phase $phase -Optional -Action { npm install --save-exact --no-audit --no-fund --legacy-peer-deps $pkgDir }
            } finally {
                Pop-Location
            }
            $rootIo = Join-Path $root "node_modules\pi-extensible-workflows\dist\src\io.js"
            $markerOk = $rootOk -and (Assert-TransientRenameRetry -IoJs $rootIo -Phase $phase -Context "root=$root")
            if (-not $markerOk) {
                # The root may already carry the patched build: restore before leaving, so a
                # failure here never leaves a mixed patched/published installation behind.
                $null = Restore-PublishedPiWorkflows
                return $false
            }
            $verifiedRoots += 1
        }

        # Swap, do not add: `pi install <local path>` only ADDS an entry, so leaving the
        # npm source in place would keep the unpatched copy in the managed root and
        # register two copies of the same extension at once. From this point the published
        # package is unregistered, so every failure path restores it.
        # Past this point the published package is unregistered, so an unexpected exception
        # must still put the environment back before the fallback is reported.
        $environmentMutated = $true
        $null = Invoke-Step -Phase $phase -Optional -Action { pi uninstall npm:pi-extensible-workflows }
        try {
            # The local source may already be registered by a previous successful run: a
            # rerun must converge, so only the npm source is required to be gone. Bash does
            # the same, and requiring the local source to be absent made every rerun roll back.
            Assert-PiPackageRegistered -Phase $phase -Spec "npm:pi-extensible-workflows" -Expectation "absent"
            $null = Invoke-Step -Phase $phase -Action { pi install $pkgDir }
            Assert-PiPackageRegistered -Phase $phase -Spec $pkgDir
        } catch {
            $null = Restore-PublishedPiWorkflows
            return $false
        }

        # An unpatched copy left in the managed root would shadow the patched build at
        # import time. `pi uninstall` normally removes it; repair and verify when it
        # survived. Past the swap the whole operation is all-or-nothing, so a failure here
        # restores the published registration instead of leaving a half-patched install.
        $managedPkg = Join-Path $PiNpmDir "node_modules\pi-extensible-workflows"
        $managedIo = Join-Path $managedPkg "dist\src\io.js"
        # A root that still carries the package without its entry point is not a skipped
        # root, it is an unverifiable one, so fail closed instead of reporting success.
        if ((Test-Path -LiteralPath $managedPkg -PathType Container) -and -not (Test-Path -LiteralPath $managedIo -PathType Leaf)) {
            Write-Log ERROR $phase "managed_artifact_missing" "The managed root still carries the workflow package without its entry point; cannot prove the patched build is the one loaded" 1 "path=$managedPkg"
            $null = Restore-PublishedPiWorkflows
            return $false
        }
        if (Test-Path -LiteralPath $managedIo -PathType Leaf) {
            if (-not (Test-TransientRenameMarker -IoJs $managedIo)) {
                Write-Log WARN $phase "managed_copy_stale" "Unpatched copy survived in the managed root; replacing it with the patched build" 0 "path=$managedIo"
                Push-Location $PiNpmDir
                try {
                    $repairOk = Invoke-Step -Phase $phase -Optional -Action { npm install --save-exact --no-audit --no-fund --legacy-peer-deps $pkgDir }
                } finally {
                    Pop-Location
                }
                if (-not $repairOk) {
                    $null = Restore-PublishedPiWorkflows
                    return $false
                }
            }
            if (-not (Assert-TransientRenameRetry -IoJs $managedIo -Phase $phase -Context "managed-root")) {
                $null = Restore-PublishedPiWorkflows
                return $false
            }
        }

        # Report what was ACTUALLY verified: a skipped root is not a verified root, and the
        # message must never claim more than the checks proved.
        $skippedText = if ($skippedRoots.Count -gt 0) { $skippedRoots -join "," } else { "none" }
        Write-Log INFO $phase "patched_workflow_installed" "Patched pi-extensible-workflows installed and verified in $verifiedRoots resolution root(s)" 0 "source=$pkgDir;ref=$ref;verified_roots=$verifiedRoots;skipped_roots=$skippedText"
        return $true
    } catch {
        # Invoke-Step already logged the failing step; the caller falls back to the
        # published release instead of failing the module, but the cause is still reported.
        # Once any root or the registration has been touched, a throw may have left the
        # environment patched, so the restore runs here too and its own failure raises the
        # hard rollback-failure latch.
        if ($environmentMutated) {
            try { $null = Restore-PublishedPiWorkflows }
            catch { $script:SetupAiRollbackFailed = $true }
        }
        Write-Log WARN $phase "patch_unexpected_failure" "Unexpected failure while installing the patched build" 0 "error=$($_.Exception.Message)"
        return $false
    }
}

# ==============================================================================
# Module registry
# ==============================================================================

$ModuleOrder = @('base','node','bun','pi','dotenv','pi-packages','go','ee','skills','pi-workflows','herdr','gentle-ai','codex','antigravity','opencode','cockpit','rotator')

$ModuleDesc = [ordered]@{
    'base'         = 'System packages (build tools, git, gh, python, neovim, jq, imagemagick, go)'
    'node'         = 'Node.js v22 + npm@latest (nvm on Unix, winget on Windows)'
    'bun'          = 'Bun runtime'
    'pi'           = 'pi.dev coding agent CLI'
    'pi-packages'  = 'Extra Pi packages from a declarative manifest (pi-packages.txt)'
    'go'           = 'Go toolchain'
    'dotenv'       = 'darkrei08/dotenv dotfiles (Linux only: clones + runs setup_env.sh)'
    'ee'           = 'Engineering Excellence skill (npx skills add, all detected agents)'
    'skills'       = 'Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add'
    'pi-workflows' = 'pi-extensible-workflows (patched build + npm 12 remote sources for pi installs)'
    'herdr'        = 'herdr terminal multiplexer'
    'gentle-ai'    = 'gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi'
    'codex'        = 'OpenAI Codex CLI'
    'antigravity'  = 'Google Antigravity CLI (agy)'
    'opencode'     = 'opencode agent CLI (opencode-ai)'
    'cockpit'      = 'cockpit-tools desktop GUI app (optional, CC BY-NC-SA)'
    'rotator'      = 'tuxevil-rotator multi-account Gemini/Antigravity gateway (installed and started in the background; optional, opt-in)'
}
$ModuleOptional = @{ 'cockpit' = $true; 'rotator' = $true }

# ==============================================================================
# Modules
# ==============================================================================

function Mod-Base {
    Write-Log INFO "base" "start" "Core dev tools (winget)"
    Install-Winget -Id "Git.Git" -Phase "base"
    Install-Winget -Id "GitHub.cli" -Phase "base"
    Install-Winget -Id "Python.Python.3.12" -Phase "base"
    Install-Winget -Id "Neovim.Neovim" -Phase "base"
    # Parity with the advertised description and the Bash base module.
    Install-Winget -Id "jqlang.jq" -Phase "base"
    Install-Winget -Id "ImageMagick.ImageMagick" -Phase "base"
    Install-Winget -Id "GoLang.Go" -Phase "base"
    # Build tools (parity with build-essential): VS Build Tools + C++ workload.
    if (-not (Test-Cmd winget)) { throw "winget not available; cannot install build tools" }
    $vsId = "Microsoft.VisualStudio.2022.BuildTools"
    $vsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $workloadPresent = $false
    if (Test-Path $vsWhere) {
        $script:SetupAiVsInstallPath = ""
        $probeOk = Invoke-Step -Phase "base" -Optional -Verify -Action {
            $script:SetupAiVsInstallPath = (& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
        }
        $workloadPresent = $probeOk -and [bool]$script:SetupAiVsInstallPath
    }
    if (-not $workloadPresent) {
        Invoke-Step -Phase "base" -Action {
            winget install -e --id $vsId --force --accept-package-agreements --accept-source-agreements `
                --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        }
    } else {
        Write-Log INFO "base" "already_present" "Visual Studio C++ workload already installed"
    }
    if (-not (Test-Path $vsWhere)) {
        throw "Visual Studio Installer vswhere.exe not found; cannot verify C++ workload"
    }
    Invoke-Step -Phase "base" -Verify -Action {
        $script:SetupAiVsInstallPath = (& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    }
    if (-not $script:SetupAiVsInstallPath) {
        throw "Visual Studio C++ workload missing after Build Tools installation"
    }
    Update-SessionPath
}

function Mod-Node {
    Write-Log INFO "node" "start" "Node.js"
    # Upgrade only when the current runtime is below the workflow minimum; a
    # current WinGet package otherwise returns a non-zero "no update" status.
    if (Test-NodeMinimum) {
        Install-Winget -Id "OpenJS.NodeJS.22" -Phase "node"
    } else {
        Install-Winget -Id "OpenJS.NodeJS.22" -Phase "node" -Upgrade
    }
    Update-SessionPath
    # winget's PATH refresh can still lag; add the default install dir directly.
    $nodeDir = Join-Path $env:ProgramFiles "nodejs"
    if ((-not (Test-Cmd node)) -and (Test-Path (Join-Path $nodeDir "node.exe"))) {
        $env:Path = "$nodeDir;$env:Path"
    }
    if (-not (Test-Cmd node)) {
        throw "node not found on PATH after install"
    }
    if (-not (Test-Cmd npm)) {
        throw "npm not found on PATH after Node.js install"
    }
    Invoke-Step -Phase "node" -Action { npm install -g npm@latest }
    Assert-NodeMinimum
}

function Mod-Bun {
    Write-Log INFO "bun" "start" "Bun"
    if (Test-Cmd bun) {
        Invoke-Step -Phase "bun" -Verify -Action { bun --version }
        Write-Log INFO "bun" "already_present" "bun already installed"
        return
    }
    Invoke-RemoteScript -Url "https://bun.sh/install.ps1" -Phase "bun"
    if (Test-Cmd bun) {
        Invoke-Step -Phase "bun" -Verify -Action { bun --version }
        Write-Log INFO "bun" "installed" "bun available after remote installer"
    } else {
        Write-Log ERROR "bun" "install_missing" "bun not found on PATH after remote installer"
        throw "bun not found on PATH after remote installer"
    }
}

function Mod-Pi {
    Write-Log INFO "pi" "start" "pi.dev CLI"
    # Establish the same extension/skill roots as Bash even when pi is already installed.
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $HOME ".pi\agent\skills") | Out-Null
    New-Item -ItemType Directory -Force -Path $PiNpmDir | Out-Null
    # pi's managed npm root is where `pi install` and `pi update --extensions` land.
    # npm 12 refuses URL/tarball dependencies in that root unless it opts in, so
    # configure it as soon as the root exists - independent of any workflow module.
    Enable-NpmRemoteSources -Dir $PiNpmDir
    if (Test-Cmd pi) { Write-Log INFO "pi" "already_present" "pi already installed"; return }
    Invoke-RemoteScript -Url "https://pi.dev/install.ps1" -Phase "pi"
    if (Test-Cmd pi) {
        Write-Log INFO "pi" "installed" "pi available after remote installer"
    } else {
        Write-Log ERROR "pi" "install_missing" "pi not found on PATH after remote installer"
        throw "pi not found on PATH after remote installer"
    }
}

function Mod-Go {
    Write-Log INFO "go" "start" "Go toolchain"
    if (Test-Cmd go) {
        Invoke-Step -Phase "go" -Verify -Action { go version }
        Write-Log INFO "go" "already_present" "Go already installed"
        return
    }
    Install-Winget -Id "GoLang.Go" -Phase "go"
    Update-SessionPath
    if (Test-Cmd go) {
        Write-Log INFO "go" "installed" "Go available after PATH refresh"
    } else {
        throw "Go not on PATH after install"
    }
}

function Mod-Dotenv {
    Write-Log WARN "dotenv" "skipped_non_linux" "dotenv/setup_env.sh targets Linux package managers; skipped on Windows"
}

function Mod-Ee {
    Write-Log INFO "ee" "start" "Engineering Excellence"
    if (-not (Test-Cmd npx)) { throw "npx not found; ee cannot be installed (install the node module first)" }
    $agents = Get-TargetSkillAgents
    foreach ($a in $agents) {
        Invoke-Step -Phase "ee" -Action {
            npx --yes skills@latest add $EE_Slug --skill $EE_Skill --global --agent $a --copy --yes
        }
    }
    Assert-SkillInstalledForAgents -Phase "ee" -Skill $EE_Skill -Agents $agents
}

# Installs darkrei08/dotenv's skill stack on every OS via `npx skills add`.
# On Linux the dotenv module may already install these; skills add --copy is
# idempotent, so a re-run is safe.
function Mod-Skills {
    Write-Log INFO "skills" "start" "Agent skills (upstream stack)"
    if (-not (Test-Cmd npx)) { throw "npx not found; skills cannot be installed (install the node module first)" }
    $agents = Get-TargetSkillAgents
    foreach ($entry in $UpstreamSkillSources) {
        $src = $entry.Source
        $skills = $entry.Skills
        foreach ($a in $agents) {
            Invoke-Step -Phase "skills" -Action {
                npx --yes skills@latest add $src --skill $skills --global --agent $a --copy --yes
            }
        }
    }
    foreach ($skill in $UpstreamSkillNames) {
        Assert-SkillInstalledForAgents -Phase "skills" -Skill $skill -Agents $agents
    }
}

function Mod-PiWorkflows {
    Write-Log INFO "pi-workflows" "start" "pi-extensible-workflows"
    if (-not (Test-Cmd pi)) { throw "pi not found; pi-workflows cannot be installed" }
    if (-not (Test-Cmd npm)) { throw "npm not found; pi-workflows cannot be installed" }
    Assert-NodeMinimum
    # Configure npm before the first install: both roots are written below, and
    # `pi update --extensions` later reinstalls every configured package through the
    # managed root (parity with setup-ai.sh).
    Enable-NpmRemoteSources -Dir $PiNpmDir
    Enable-NpmRemoteSources -Dir $PiExtDir
    $ver = ""
    # Parity with setup-ai.sh: PI_WORKFLOW_VERSION wins when it is set, so a machine can
    # pin the published release without querying the registry.
    if ($env:PI_WORKFLOW_VERSION) {
        $ver = $env:PI_WORKFLOW_VERSION.Trim()
        $script:SetupAiWorkflowVersion = $ver
    }
    try {
        if (-not $ver) {
            Invoke-Step -Phase "pi-workflows" -Verify -Action {
                $script:SetupAiWorkflowVersion = (npm view pi-extensible-workflows version).Trim()
            }
            $ver = $script:SetupAiWorkflowVersion
        }
    } catch {
        throw "Could not resolve pi-extensible-workflows version: $($_.Exception.Message)"
    }
    if (-not $ver) { throw "Could not resolve pi-extensible-workflows version" }
    Write-Log INFO "pi-workflows" "version" "Version $ver"
    Invoke-Step -Phase "pi-workflows" -Action { pi install "npm:pi-extensible-workflows@$ver" }
    # Prove what Pi recorded instead of trusting the command: the quality gate below only
    # inspects the separate extensions-root copy.
    Assert-PiPackageRegistered -Phase "pi-workflows" -Spec "npm:pi-extensible-workflows"
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    # Append-only, so the npm 12 remote-source opt-in written above survives.
    Add-LineIfMissing -Path (Join-Path $PiExtDir ".npmrc") -Line "ignore-scripts=false"
    # Mark this dir as an npm project root so `npm install` lands HERE and cannot
    # walk up into an ancestor project (mirrors setup-ai.sh).
    $pkgJson = Join-Path $PiExtDir "package.json"
    if (-not (Test-Path $pkgJson)) {
        Set-Content -Path $pkgJson -Value '{"name":"pi-extensions","private":true}'
    }
    Push-Location $PiExtDir
    try {
        Invoke-Step -Phase "pi-workflows" -Action {
            npm install --save-exact --no-audit --no-fund --legacy-peer-deps "pi-extensible-workflows@$ver"
        }
    } finally { Pop-Location }

    # Verify the version that actually landed in THIS dir by reading its local
    # package.json directly. Do NOT use require.resolve: it ascends the tree and
    # can resolve a shadowing ancestor copy (false version_mismatch).
    $localPkg = Join-Path $PiExtDir "node_modules/pi-extensible-workflows/package.json"
    if (-not (Test-Path $localPkg)) {
        Write-Log ERROR "pi-workflows-node" "install_missing" "pi-extensible-workflows not installed in extensions dir ($localPkg)"
        throw "pi-extensible-workflows not installed in extensions dir ($localPkg)"
    } else {
        $installed = (Get-Content -Raw $localPkg | ConvertFrom-Json).version
        if ($installed -ne $ver) {
            Write-Log ERROR "pi-workflows-node" "version_mismatch" "Installed version mismatch (expected=$ver actual=$installed)"
            throw "Installed pi-extensible-workflows version mismatch (expected=$ver actual=$installed)"
        } else {
            Write-Log INFO "pi-workflows-node" "module_resolved" "Installed $installed in $localPkg"
        }
    }

    # Patched local build LAST, so it wins in both roots over the published release
    # installed above. A failure here is reported, never hidden: the environment
    # keeps working with the published release.
    $patchedActive = $false
    try { $patchedActive = [bool](Install-PatchedPiWorkflows) } catch {
        # A throw after a failed restore means the environment was not put back: surface it
        # instead of degrading to a published release we cannot prove is intact.
        if ($script:SetupAiRollbackFailed) { throw }
        $patchedActive = $false
    }
    if ($patchedActive) {
        $patchedVersion = "unknown"
        try { $patchedVersion = (Get-Content -Raw $localPkg | ConvertFrom-Json).version } catch { $patchedVersion = "unknown" }
        Write-Log INFO "pi-workflows-patch" "patched_version_active" "Effective workflow package is the patched local build" 0 "version=$patchedVersion;published=$ver"
    } else {
        if ($script:SetupAiRollbackFailed) { throw "Workflow patch rollback failed; the environment was not restored" }
        Write-Log WARN "pi-workflows-patch" "patched_build_unavailable" "Keeping the published pi-extensible-workflows; EPERM-prone state writes may still fail" 0 "source=$PiWorkflowsSourceDir;ref=$PiWorkflowsFixRef"
    }
}

# --- pi-packages ------------------------------------------------------------
# Declarative Pi packages: the manifest resolved by Get-PiPackagesManifest lists one
# source per line, so a NEW machine gets every extension the toolchain needs
# without hand-editing ~/.pi/agent/settings.json. Supported sources are whatever
# `pi install` accepts: `npm:<pkg>[@<version>]`,
# `git:<host>/<owner>/<repo>[@<ref>]`, or a local path. Blank lines and `#`
# comments are ignored, and every install is verified by reading pi's own
# settings.json back. pi-extensible-workflows is skipped here on purpose: the
# pi-workflows module owns that package (published + patched build).
function Mod-PiPackages {
    Write-Log INFO "pi-packages" "start" "pi-packages"
    if (-not (Test-Cmd pi)) { throw "pi not found; pi-packages cannot be installed" }
    if (-not (Test-Cmd node)) { throw "node not found; pi-packages needs node to verify pi settings" }

    # Manifest entries are arbitrary sources, so the managed root must already
    # tolerate remote (URL/tarball) dependencies before the first install.
    Enable-NpmRemoteSources -Dir $PiNpmDir

    $manifest = Get-PiPackagesManifest
    if (-not $manifest) {
        $override = if ($PiPackagesFile) { $PiPackagesFile } else { "<unset>" }
        $configManifest = Join-Path $PiAgentDir "pi-packages.txt"
        $profileManifest = Join-Path $ScriptDir "pi-packages.txt"
        Write-Log INFO "pi-packages" "manifest_absent" "No Pi package manifest; nothing extra to install" 0 "override=$override;config=$configManifest;profile=$profileManifest"
        return
    }
    Write-Log INFO "pi-packages" "manifest_loaded" "Pi package manifest found" 0 "manifest=$manifest"

    $installed = 0
    $skipped = 0
    $workflowId = Get-PiPackageId -Spec 'npm:pi-extensible-workflows'
    foreach ($rawLine in (Get-Content -LiteralPath $manifest)) {
        # Strip a trailing comment, then trim surrounding whitespace only; internal
        # whitespace stays invalid input.
        $line = ($rawLine -split '#', 2)[0].Trim()
        if (-not $line) { continue }

        if ((Get-PiPackageId -Spec $line) -eq $workflowId) {
            Write-Log WARN "pi-packages" "workflow_owned_elsewhere" "Skipping pi-extensible-workflows; the pi-workflows module owns that package" 0 "spec=$line"
            $skipped++
            continue
        }

        $null = Invoke-Step -Phase "pi-packages" -Action { pi install $line }
        Assert-PiPackageRegistered -Phase "pi-packages" -Spec $line
        $installed++
    }

    Write-Log INFO "pi-packages" "manifest_applied" "Pi package manifest applied" 0 "installed=$installed;skipped=$skipped;manifest=$manifest"
}

function Mod-Herdr {
    Write-Log INFO "herdr" "start" "herdr"
    if (Test-Cmd herdr) {
        Invoke-Step -Phase "herdr" -Verify -Action { herdr --version }
        Write-Log INFO "herdr" "already_present" "herdr already installed"
        return
    }
    Invoke-RemoteScript -Url "https://herdr.dev/install.ps1" -Phase "herdr"
    if (Test-Cmd herdr) {
        Write-Log INFO "herdr" "installed" "herdr available after remote installer"
    } else {
        Write-Log ERROR "herdr" "install_missing" "herdr not found on PATH after remote installer"
        throw "herdr not found on PATH after remote installer"
    }
}

# Reinstates the Gentle AI ecosystem configurator (sibling of mod_gentle_ai in
# setup-ai.sh). `gentle-ai install` is the per-agent/per-IDE selector that also
# wires each selected agent's MCP servers, so tools appear under /mcp. The
# configurator is a CORE step: it always runs (interactively with a console, or
# non-interactively over the detected agents in CI/pipes) and a failure fails
# the module. For pi we additionally guarantee + verify the first-class
# gentle-pi harness and pi-mcp-adapter. Idempotent: safe to re-run.
function Mod-GentleAi {
    Write-Log INFO "gentle-ai" "start" "gentle-ai"

    # The per-agent selector and the pi harness both require the gentle-ai CLI
    # itself; a legacy standalone gga is NOT enough, so install whenever the
    # gentle-ai CLI is missing even if an old gga is on PATH.
    if (-not (Test-Cmd gentle-ai)) {
        # Vendor's official Windows method (installs to %LOCALAPPDATA%\gentle-ai\bin).
        Invoke-RemoteScript -Url "https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.ps1" -Phase "gentle-ai"
        Update-SessionPath
    }

    if (-not (Test-Cmd gentle-ai)) {
        Write-Log ERROR "gentle-ai" "install_missing" "gentle-ai CLI not found on PATH after remote installer"
        throw "gentle-ai CLI not found on PATH after remote installer"
    }
    Invoke-Step -Phase "gentle-ai" -Verify -Action { & gentle-ai --version }

    # Detect the agents/IDEs present on this machine (same mapping as Mod-Ee).
    $detectedAgents = Get-TargetSkillAgents

    # Per-agent / per-IDE selection + MCP wiring, owned by gentle-ai. This is a
    # core step and must actually run: with a real console we launch the
    # interactive selector (run directly - Invoke-Step pipes output and would
    # hide the prompts); otherwise we run it non-interactively over the detected
    # agents so CI/pipes never hang. A failure fails the module.
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        Write-Log INFO "gentle-ai" "configurator_start" "Launching gentle-ai install (choose agents/IDEs + MCP)"
        & gentle-ai install --scope global
        if ($LASTEXITCODE -ne 0) {
            Write-Log ERROR "gentle-ai" "configurator_failed" "gentle-ai install exited with code $LASTEXITCODE"
            throw "gentle-ai install exited with code $LASTEXITCODE"
        }
    } else {
        $agentsCsv = ($detectedAgents -join ',')
        Write-Log INFO "gentle-ai" "configurator_noninteractive" "No console; installing gentle-ai for detected agents" 0 "agents=$agentsCsv"
        Invoke-Step -Phase "gentle-ai" -Action { & gentle-ai install --scope global --agents $agentsCsv }
    }
    Write-Log INFO "gentle-ai" "configurator_done" "gentle-ai install completed"

    # Guarantee pi reads gentle-ai in its MCP list (/mcp): install the first-class
    # gentle-pi harness + pi-mcp-adapter, then verify the exact target file.
    if (Test-Cmd pi) {
        Invoke-Step -Phase "gentle-ai" -Action { pi install npm:gentle-pi }
        Invoke-Step -Phase "gentle-ai" -Action { pi install npm:pi-mcp-adapter }
        $piSettings = Join-Path $HOME ".pi\agent\settings.json"
        $piSettingsRaw = if (Test-Path $piSettings) { Get-Content -Raw $piSettings } else { "" }
        if (($piSettingsRaw -match 'npm:gentle-pi') -and ($piSettingsRaw -match 'npm:pi-mcp-adapter')) {
            Write-Log INFO "gentle-ai" "pi_enabled" "gentle-pi + pi-mcp-adapter registered in pi (verify: /mcp, /gentle-ai:status)"
        } else {
            Write-Log ERROR "gentle-ai" "pi_enable_failed" "gentle-pi and/or pi-mcp-adapter not present in pi settings after install ($piSettings)"
            throw "gentle-pi and/or pi-mcp-adapter not present in pi settings after install"
        }
        # gentle-pi quiet-tools re-registers the built-in read/edit/grep tools; a
        # second extension that shadows one of them makes pi abort at startup.
        # Warn with the exact remediation instead of ending on a green install.
        if (($piSettingsRaw -match 'pi-hashline-edit-pro') -and ($env:GENTLE_PI_QUIET_TOOLS -ne '0')) {
            Write-Log WARN "gentle-ai" "quiet_tools_conflict" "pi-hashline-edit-pro registers read/edit, which gentle-pi quiet-tools also owns; pi aborts at startup. Set GENTLE_PI_QUIET_TOOLS=0 or remove the package." 0 "settings=$piSettings"
        }
    }

    @"
  gentle-ai next steps (run yourself, per project):
    1) Set your API keys
    2) Run your selected agent
    3) Try: /sdd-new my-feature   (in pi: /gentle-ai:status, /gentleman:models, /mcp)
  GGA (per project):  gga init  then  gga install
"@ | Tee-Object -FilePath $HumanLog -Append | Out-Host
}

function Mod-Codex {
    Write-Log INFO "codex" "start" "Codex CLI"
    if (Test-Cmd codex) { Write-Log INFO "codex" "already_present" "codex already installed"; return }
    Invoke-RemoteScript -Url "https://chatgpt.com/codex/install.ps1" -Phase "codex"
    if (Test-Cmd codex) {
        Write-Log INFO "codex" "installed" "codex available after remote installer"
    } else {
        Write-Log ERROR "codex" "install_missing" "codex not found on PATH after remote installer"
        throw "codex not found on PATH after remote installer"
    }
}

function Mod-Antigravity {
    Write-Log INFO "antigravity" "start" "Antigravity CLI"
    if (Test-Cmd agy) { Write-Log INFO "antigravity" "already_present" "agy already installed"; return }
    Invoke-RemoteScript -Url "https://antigravity.google/cli/install.ps1" -Phase "antigravity"
    if (Test-Cmd agy) {
        Write-Log INFO "antigravity" "installed" "agy available after remote installer"
    } else {
        Write-Log ERROR "antigravity" "install_missing" "agy not found on PATH after remote installer"
        throw "agy not found on PATH after remote installer"
    }
}

# opencode-pi spawns the CLI with child_process.spawn and no shell, so a Windows
# .cmd/.ps1 shim is not executable for it: Node reports `spawn opencode ENOENT`
# even though `opencode --version` works in a terminal. Resolve the native
# launcher behind the shim and hand it to the extension via OPENCODE_PI_BIN.
function Get-OpenCodeNativeBin {
    foreach ($cmd in @(Get-Command opencode -All -ErrorAction SilentlyContinue)) {
        $path = $cmd.Source
        if (-not $path) { continue }
        $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
        if (($ext -eq '.cmd') -or ($ext -eq '.bat')) {
            $native = Join-Path (Split-Path -Parent $path) 'node_modules\opencode-ai\bin\opencode.exe'
            if (Test-Path $native -PathType Leaf) { return $native }
            continue
        }
        if (($ext -eq '.exe') -and (Test-Path $path -PathType Leaf)) { return $path }
    }
    return $null
}

# Probe what opencode-pi will run: no shell, OPENCODE_PI_BIN first, then PATH.
# $null means node is missing, so the spawn path could not be proven either way.
function Test-OpenCodeSpawn {
    param([string]$Bin = "")
    if (-not (Test-Cmd node)) { return $null }
    $probe = 'const {spawnSync}=require("node:child_process");' +
        'const r=spawnSync(process.env.OPENCODE_PI_SPAWN_PROBE||"opencode",["--version"],{stdio:"ignore"});' +
        'process.exit(!r.error && r.status===0 ? 0 : 1)'
    $env:OPENCODE_PI_SPAWN_PROBE = $Bin
    $ok = $false
    # A nonzero exit may surface as a thrown NativeCommandExitException (the script
    # sets PSNativeCommandUseErrorActionPreference) or as $LASTEXITCODE; both fail.
    try {
        & node -e $probe | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
    } catch { $ok = $false }
    Remove-Item Env:OPENCODE_PI_SPAWN_PROBE -ErrorAction SilentlyContinue
    return $ok
}

function Set-OpenCodePiBin {
    # What a fresh pi session resolves: explicit override first, else bare PATH.
    $effective = $env:OPENCODE_PI_BIN
    if (-not $effective) { $effective = [Environment]::GetEnvironmentVariable('OPENCODE_PI_BIN', 'User') }
    if (-not $effective) { $effective = 'opencode' }
    $spawnable = Test-OpenCodeSpawn -Bin $effective
    if ($spawnable -eq $true) {
        Write-Log INFO "opencode" "spawn_ok" "opencode is spawnable without a shell (opencode-pi requirement)" 0 "bin=$effective"
        return
    }
    if ($null -eq $spawnable) {
        Write-Log WARN "opencode" "spawn_unverified" "node not found; cannot verify the opencode-pi spawn path" 0
        return
    }
    $native = Get-OpenCodeNativeBin
    if (-not $native) {
        Write-Log WARN "opencode" "spawn_unresolved" "opencode is not spawnable without a shell and no native launcher sits behind the shims" 0
        return
    }
    if ((Test-OpenCodeSpawn -Bin $native) -ne $true) {
        Write-Log WARN "opencode" "spawn_failed" "the resolved opencode launcher is not spawnable without a shell" 0 "bin=$native"
        return
    }
    [Environment]::SetEnvironmentVariable('OPENCODE_PI_BIN', $native, 'User')
    $env:OPENCODE_PI_BIN = $native
    Write-Log INFO "opencode" "pi_bin_set" "OPENCODE_PI_BIN points opencode-pi at the native launcher" 0 "bin=$native"
}

function Mod-Opencode {
    Write-Log INFO "opencode" "start" "opencode"
    if (Test-Cmd opencode) {
        Write-Log INFO "opencode" "already_present" "opencode already installed"
    } else {
        if (-not (Test-Cmd npm)) {
            throw "npm not found; opencode cannot be installed"
        }
        Invoke-Step -Phase "opencode" -Action { npm install -g opencode-ai }
        # npm writes the shim into the user PATH; refresh this session so the
        # verification below sees it without a new shell (parity with setup-ai.sh).
        Update-SessionPath
        if (-not (Test-Cmd opencode)) {
            Write-Log ERROR "opencode" "install_missing" "opencode not found on PATH after npm install"
            throw "opencode not found on PATH after npm install"
        }
    }
    Set-OpenCodePiBin
    @"
  OpenCode Go (paid) is hosted-model access; after install run: opencode auth login
  The SAME key works in pi.dev - add a custom provider (baseUrl https://opencode.ai/zen/v1,
  api openai-completions) or run /provider add. Docs: https://pi.dev/docs/latest/custom-provider
"@ | Tee-Object -FilePath $HumanLog -Append | Out-Host
}

function Mod-Cockpit {
    Write-Log INFO "cockpit" "start" "cockpit-tools (GUI)"
    Write-Log INFO "cockpit" "license_notice" "cockpit-tools is a desktop GUI app under CC BY-NC-SA 4.0"
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/jlcodes99/cockpit-tools/releases/latest" -Headers @{ 'User-Agent' = 'setup-ai' }
        $asset = $rel.assets | Where-Object { $_.name -match '\.msi$' } | Select-Object -First 1
        if (-not $asset) { Write-Log WARN "cockpit" "no_msi" "No .msi asset in latest release; download manually"; return }
        $msi = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi
        Invoke-Step -Phase "cockpit" -Optional -Action {
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qb" -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "msiexec exited with code $($process.ExitCode)" }
        }
    } catch {
        Write-Log WARN "cockpit" "failed" "$($_.Exception.Message)"
    }
}

# Resolve the executable a scheduled task must run. npm installs three shims on Windows
# and PowerShell resolves the .ps1 one, which a task cannot execute directly; the .cmd
# shim is what the task runs.
function Get-RotatorExecutable {
    $command = Get-Command tuxevil-rotator -ErrorAction SilentlyContinue
    $binPath = if ($command) { $command.Source } else { "tuxevil-rotator" }
    if ($binPath -like "*.ps1") {
        $cmdShim = [System.IO.Path]::ChangeExtension($binPath, ".cmd")
        if (Test-Path -LiteralPath $cmdShim -PathType Leaf) { return $cmdShim }
    }
    return $binPath
}

# Register the gateway with the machine's own autostart so it survives a reboot: a logon
# scheduled task, which runs hidden and needs no console. Registering only, not starting:
# the process is started by its own step and only when nothing answers its port, so an
# already-running gateway is never doubled.
#
# Windows has no counterpart to the Linux unit's Restart=on-failure, so the task also carries a
# repeating trigger as a watchdog: every tick starts the gateway only when nothing listens on
# 51200 yet. IgnoreNew skips the tick while the gateway it started is still running, and
# the tick's own probe skips it while a gateway started elsewhere holds the port.
function Register-RotatorTask {
    $binPath = Get-RotatorExecutable
    $watchdogMinutes = 5
    try {
        # The tick probes before it starts anything, because a manual or installer-detached
        # gateway owns the port without owning this task instance, and IgnoreNew alone cannot
        # keep that one single. A connect to the address the module's own probe uses is the
        # cheapest test that answers "is a gateway already answering?": it is milliseconds,
        # while Get-NetTCPConnection costs seconds and loads the NetTCPIP module.
        #NOTE: a gateway bound to a non-loopback address only would read as free here; the
        # gateway itself binds 0.0.0.0 (tuxevil-rotator's default) and 127.0.0.1 is what the
        # module and the Pi extension probe, so this asks the same question they do.
        # The path lands in a single-quoted string inside the task's command line, so a quote
        # in it would end that string early; doubling it is PowerShell's own escaping.
        $shim = $binPath.Replace("'", "''")
        $tick = "try { (New-Object Net.Sockets.TcpClient('127.0.0.1', 51200)).Close() } catch { & '$shim' start }"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -Command "' + $tick + '"')
        # Logon starts the gateway; the once-trigger's repetition is the watchdog. A
        # repetition attached to the logon trigger itself never fires: measured on Windows 11,
        # such a task reports no NextRunTime and only ever runs at logon.
        $atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $watchdogMinutes)
        # A zero execution time limit is what keeps a long-running gateway from being killed
        # at the scheduler's default three days.
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName "tuxevil-rotator" -Action $action -Trigger @($atLogon, $watchdog) -Settings $taskSettings `
            -Description "tuxevil-rotator multi-account Gemini/Antigravity gateway on http://localhost:51200" -Force | Out-Null
        # A registration can half-apply, and the promise is about the next logon rather than about
        # this run, so the task is read back and checked: what it runs, that it still starts at
        # logon for this user, and the two settings the supervision rests on. This also covers the
        # trap above, where a repetition attached to the wrong trigger reads back as no watchdog.
        $registered = Get-ScheduledTask -TaskName "tuxevil-rotator" -ErrorAction Stop
        $actions = @($registered.Actions)
        $actionOk = $actions.Count -eq 1 -and $actions[0].Execute -eq $action.Execute -and $actions[0].Arguments -eq $action.Arguments
        $logonOk = @($registered.Triggers | Where-Object {
            $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" -and $_.Enabled -and ($_.UserId -split '\\')[-1] -eq $env:USERNAME
        }).Count -gt 0
        # Both sides are read as ISO durations, because the scheduler hands the interval back as
        # the string "PT5M" while the trigger built here holds it as a TimeSpan.
        $interval = [System.Xml.XmlConvert]::ToTimeSpan($watchdog.Repetition.Interval)
        $watchdogOk = @($registered.Triggers | Where-Object {
            $_.Enabled -and $_.Repetition -and $_.Repetition.Interval -and [System.Xml.XmlConvert]::ToTimeSpan($_.Repetition.Interval) -eq $interval
        }).Count -gt 0
        # A disabled task or trigger is registered and inert, so both are part of the check.
        $enabledOk = [bool]$registered.Settings.Enabled
        $instancesOk = $registered.Settings.MultipleInstances -eq "IgnoreNew"
        $limitOk = [System.Xml.XmlConvert]::ToTimeSpan($registered.Settings.ExecutionTimeLimit) -eq [TimeSpan]::Zero
        if (-not ($actionOk -and $logonOk -and $watchdogOk -and $enabledOk -and $instancesOk -and $limitOk)) {
            $flags = "task=tuxevil-rotator;action=$actionOk;logon=$logonOk;watchdog=$watchdogOk;enabled=$enabledOk;ignoreNew=$instancesOk;noTimeLimit=$limitOk"
            Write-Log WARN "rotator" "task_unverified" "Scheduled task registered without the action, logon trigger, or watchdog settings this module relies on; the gateway may stay down until the next setup-ai run" 0 $flags
            return $false
        }
        Write-Log INFO "rotator" "task_registered" "tuxevil-rotator starts at logon and is watched every $watchdogMinutes minutes by a scheduled task" 0 "task=tuxevil-rotator;exe=$binPath;watchdog=${watchdogMinutes}m"
        return $true
    } catch {
        Write-Log WARN "rotator" "task_failed" "Scheduled task not registered; the gateway is started as a detached process only" 0 "error=$($_.Exception.Message)"
        return $false
    }
}

# Start the gateway in the background and leave the proof of that start to the caller's
# probe. The scheduled task is preferred because it also covers the next session;
# anywhere it cannot run, the process is detached from this installer instead.
function Start-RotatorGateway {
    param([string]$LogFile)
    if (Get-ScheduledTask -TaskName "tuxevil-rotator" -ErrorAction SilentlyContinue) {
        try {
            Start-ScheduledTask -TaskName "tuxevil-rotator"
            Write-Log INFO "rotator" "task_started" "tuxevil-rotator started through the logon scheduled task" 0 "task=tuxevil-rotator"
            return $true
        } catch {
            Write-Log WARN "rotator" "task_start_failed" "Scheduled task did not start; falling back to a detached process" 0 "error=$($_.Exception.Message)"
        }
    }
    $binPath = Get-RotatorExecutable
    try {
        Start-Process -FilePath $binPath -ArgumentList "start" -WindowStyle Hidden `
            -RedirectStandardOutput $LogFile -RedirectStandardError ([System.IO.Path]::ChangeExtension($LogFile, ".err.log"))
        Write-Log INFO "rotator" "gateway_spawned" "tuxevil-rotator started in the background" 0 "log=$LogFile"
        return $true
    } catch {
        Write-Log WARN "rotator" "gateway_spawn_failed" "tuxevil-rotator could not be started in the background" 0 "error=$($_.Exception.Message)"
        return $false
    }
}

function Mod-Rotator {
    Write-Log INFO "rotator" "start" "tuxevil-rotator gateway"
    # Detect a desktop cockpit-tools data dir by marker file only; never read tokens.
    $candidates = @(
        (Join-Path $HOME ".antigravity_cockpit")
        (Join-Path $HOME ".local\share\cockpit-tools")
        (Join-Path $HOME ".config\cockpit-tools")
        (Join-Path $HOME ".wizard-ai\cockpit-tools")
        (Join-Path $HOME "Library\Application Support\cockpit-tools")
    )
    if ($env:APPDATA) { $candidates += Join-Path $env:APPDATA "cockpit-tools" }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA "cockpit-tools" }

    $cockpitDir = ""
    foreach ($dir in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $dir "accounts.json") -PathType Leaf) -or
            (Test-Path -LiteralPath (Join-Path $dir "account-token.key") -PathType Leaf)) {
            $cockpitDir = $dir
            break
        }
    }
    if ($cockpitDir) {
        Write-Log INFO "rotator" "cockpit_detected" "cockpit-tools data directory detected" 0 "dir=$cockpitDir"
    } else {
        Write-Log INFO "rotator" "cockpit_absent" "No cockpit-tools data directory detected; the rotator can still use its own accounts" 0
    }

    # Non-fatal health probe. $gatewayUp drives the background start further below.
    $gw = "http://localhost:51200/v1/models"
    $gatewayUp = $false
    try {
        $response = Invoke-WebRequest -Uri $gw -Headers @{ Authorization = "Bearer tuxevil" } -TimeoutSec 5
        $body = $response.Content
        $count = if ($body) { ([regex]::Matches($body, '"id"')).Count } else { 0 }
        $gatewayUp = $true
        Write-Log INFO "rotator" "gateway_up" "tuxevil-rotator gateway is reachable" 0 "url=$gw;models=$count"
    } catch {
        Write-Log INFO "rotator" "gateway_down" "tuxevil-rotator gateway not reachable; starting it in the background" 0 "url=$gw"
    }

    # Install the CLI idempotently. Never runs login and never writes secrets; the
    # start below is best-effort and never fails the module.
    if (Test-Cmd tuxevil-rotator) {
        Write-Log INFO "rotator" "already_present" "tuxevil-rotator already installed"
    } else {
        if (-not (Test-Cmd npm)) { throw "npm not found; tuxevil-rotator cannot be installed" }
        Invoke-Step -Phase "rotator" -Action { npm install -g tuxevil-rotator }
        if (-not (Test-Cmd tuxevil-rotator)) {
            Write-Log ERROR "rotator" "install_missing" "tuxevil-rotator not found on PATH after npm install"
            throw "tuxevil-rotator not found on PATH after npm install"
        }
    }

    # Register boot persistence first: registering the task never starts a second
    # process, so this is safe whether or not the gateway is already up.
    [void](Register-RotatorTask)

    # Start the gateway only when nothing answers its port: the dotenv Gemini aliases are
    # unusable without it, so a gateway that only ever gets started by hand is the failure
    # this module exists to prevent. The start is proven by the probe below, because a
    # process that dies immediately must be reported, not assumed.
    if (-not $gatewayUp) {
        $gatewayLog = Join-Path $LogDir "rotator-gateway.log"
        [void](Start-RotatorGateway -LogFile $gatewayLog)
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            try {
                $probe = Invoke-WebRequest -Uri $gw -Headers @{ Authorization = "Bearer tuxevil" } -TimeoutSec 2
                $body = $probe.Content
                $count = if ($body) { ([regex]::Matches($body, '"id"')).Count } else { 0 }
                $gatewayUp = $true
                Write-Log INFO "rotator" "gateway_started" "tuxevil-rotator answered after the background start" 0 "url=$gw;models=$count"
                break
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $gatewayUp) {
            Write-Log WARN "rotator" "gateway_start_failed" "tuxevil-rotator did not answer within 10s; run 'tuxevil-rotator login', then check '$gatewayLog' or the 'tuxevil-rotator' scheduled task" 0 "url=$gw"
        }
    }
    if (Test-Cmd pi) {
        # `pi install` accepts only protocol URLs without the `git:` prefix, so the bare
        # `github:owner/repo` this module used to pass resolved as a local path and failed.
        # A leftover legacy entry from such a run is tolerated by pi (`pi list` skips it)
        # and cannot be removed with `pi remove`, which only matches installed packages.
        $extensionSource = "git:github.com/darkrei08/pi-cockpit-tools-sync"
        $piSettings = Join-Path $HOME ".pi\agent\settings.json"
        Invoke-Step -Phase "rotator" -Action { pi install $extensionSource }
        if (-not (Test-Path -LiteralPath $piSettings -PathType Leaf) -or
            -not (Select-String -LiteralPath $piSettings -SimpleMatch $extensionSource -Quiet)) {
            Write-Log ERROR "rotator" "pi_extension_missing" "Pi did not register cockpit sync extension" 1 "expected=$piSettings"
            throw "Pi did not register cockpit sync extension"
        }
        Write-Log INFO "rotator" "pi_extension_verified" "Cockpit sync extension registered in Pi" 0 "path=$piSettings"
    } else {
        Write-Log INFO "rotator" "pi_extension_skipped" "pi not found; cockpit sync extension was not installed"
    }
    @"
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
"@ | Tee-Object -FilePath $HumanLog -Append | Out-Host
}

$ModuleFn = @{
    'base' = ${function:Mod-Base}; 'node' = ${function:Mod-Node}; 'bun' = ${function:Mod-Bun}
    'pi' = ${function:Mod-Pi}; 'pi-packages' = ${function:Mod-PiPackages}; 'go' = ${function:Mod-Go}; 'dotenv' = ${function:Mod-Dotenv}; 'ee' = ${function:Mod-Ee}
    'skills' = ${function:Mod-Skills}
    'pi-workflows' = ${function:Mod-PiWorkflows}; 'herdr' = ${function:Mod-Herdr}
    'gentle-ai' = ${function:Mod-GentleAi}
    'codex' = ${function:Mod-Codex}; 'antigravity' = ${function:Mod-Antigravity}
    'opencode' = ${function:Mod-Opencode}; 'cockpit' = ${function:Mod-Cockpit}; 'rotator' = ${function:Mod-Rotator}
}

# ==============================================================================
# CLI / selection
# ==============================================================================

function Show-List {
    Write-Host "AI Dev Suite $ScriptVersion - modules (core = installed by default):`n"
    foreach ($m in $ModuleOrder) {
        $tag = if ($ModuleOptional.ContainsKey($m)) { "optional" } else { "core    " }
        "{0,-10} {1,-14} {2}" -f "[$tag]", $m, $ModuleDesc[$m] | Write-Host
    }
    Write-Host "`nUse: -Only csv | -All | (default = core)"
}

function Show-Help {
    Get-Content $ScriptPath | Select-Object -First 30 | ForEach-Object { $_ }
    Show-List
}

function Resolve-Selection {
    $requested = @()
    if ($All) {
        $requested = $ModuleOrder
    } elseif ($OnlySpecified) {
        if ([string]::IsNullOrWhiteSpace($Only)) {
            Write-Log ERROR "selection" "invalid_only" "-Only requires a non-empty comma-separated module list." 2
            exit 2
        }
        foreach ($r in ($Only -split ',')) {
            $r = $r.Trim()
            if (-not $r) { continue }
            if (-not $ModuleDesc.Contains($r)) { Write-Log ERROR "selection" "invalid_only" "Unknown module: $r" 2; exit 2 }
            $requested += $r
        }
        if ($requested.Count -eq 0) {
            Write-Log ERROR "selection" "invalid_only" "-Only requires a non-empty comma-separated module list." 2
            exit 2
        }
    } else {
        $requested = $ModuleOrder | Where-Object { -not $ModuleOptional.ContainsKey($_) }
    }
    # Order by ModuleOrder so dependencies run first.
    return $ModuleOrder | Where-Object { $requested -contains $_ }
}

function Invoke-QualityGates {
    param([string[]]$Selected)
    $script:CurrentModule = 'quality'
    Write-Log INFO "quality" "start" "Running quality gates"

    if ($Selected -contains 'node' -or $Selected -contains 'pi-workflows') {
        Assert-NodeMinimum
    }
    if ($Selected -contains 'node') {
        Invoke-Step -Phase "quality" -Verify -Action { node --version }
        Invoke-Step -Phase "quality" -Verify -Action { npm --version }
    }
    if ($Selected -contains 'bun') {
        if (-not (Test-Cmd bun)) { throw "bun quality gate could not find bun" }
        Invoke-Step -Phase "quality" -Verify -Action { bun --version }
    }
    if ($Selected -contains 'pi') {
        if (-not (Test-Cmd pi)) { throw "pi quality gate could not find pi" }
        Invoke-Step -Phase "quality" -Verify -Action { pi --no-extensions --version }
    }
    if ($Selected -contains 'pi-workflows') {
        $workflowPkg = Join-Path $PiExtDir "node_modules/pi-extensible-workflows/package.json"
        if (-not (Test-Path $workflowPkg)) {
            throw "pi-extensible-workflows package.json missing from extensions dir ($workflowPkg)"
        }
        $workflowVersion = (Get-Content -Raw $workflowPkg | ConvertFrom-Json).version
        Write-Log INFO "quality" "workflow_package_verified" "Verified pi-extensible-workflows package" 0 "path=$workflowPkg;version=$workflowVersion"
    }
    $targetAgents = Get-TargetSkillAgents
    if ($Selected -contains 'ee') {
        Assert-SkillInstalledForAgents -Phase "quality" -Skill $EE_Skill -Agents $targetAgents
        Write-Log INFO "quality" "ee_gate_passed" "Engineering Excellence verified for every targeted agent"
    }
    if ($Selected -contains 'skills') {
        foreach ($sk in $UpstreamSkillNames) {
            Assert-SkillInstalledForAgents -Phase "quality" -Skill $sk -Agents $targetAgents
        }
        Write-Log INFO "quality" "skills_gate_passed" "All upstream skills verified for every targeted agent"
    }
    if ($Selected -contains 'gentle-ai') {
        # The module requires the gentle-ai CLI specifically; a legacy standalone
        # gga cannot prove the per-agent/MCP configuration ran.
        if (-not (Test-Cmd gentle-ai)) {
            throw "gentle-ai quality gate could not find the gentle-ai CLI on PATH"
        }
        if (Test-Cmd pi) {
            $piSettings = Join-Path $HOME ".pi\agent\settings.json"
            $piSettingsRaw = if (Test-Path $piSettings) { Get-Content -Raw $piSettings } else { "" }
            if (-not ($piSettingsRaw -match 'npm:gentle-pi') -or -not ($piSettingsRaw -match 'npm:pi-mcp-adapter')) {
                throw "gentle-pi and/or pi-mcp-adapter not registered in pi settings ($piSettings)"
            }
            Write-Log INFO "quality" "gentle_ai_gate_passed" "gentle-ai verified (CLI present; gentle-pi + pi-mcp-adapter registered in pi)"
        } else {
            # No pi on PATH: pi MCP wiring is genuinely not applicable, so do not
            # claim it was registered.
            Write-Log INFO "quality" "gentle_ai_gate_passed" "gentle-ai CLI verified; pi not present, so pi MCP wiring was not required"
        }
    }
    Write-Log INFO "quality" "gates_done" "Quality gates completed for selected modules"
}

# ==============================================================================
# Main
# ==============================================================================

New-Item -ItemType File -Force -Path $HumanLog | Out-Null
New-Item -ItemType File -Force -Path $JsonlLog | Out-Null

if ($Help) { Show-Help; exit 0 }
if ($List) { Show-List; exit 0 }

Write-Log INFO "bootstrap" "start" "AI Dev Suite (Windows) started" 0 "script_version=$ScriptVersion"

$selected = Resolve-Selection
$script:SelectedModules = @($selected)
$script:RunActive = $true
Write-Log INFO "bootstrap" "modules_selected" "Modules queued" 0 ("modules=" + ($selected -join ' '))

$script:FailedModules = @()
$script:SucceededModules = @()
foreach ($m in $selected) {
    $script:CurrentModule = $m
    try { & $ModuleFn[$m]; $script:SucceededModules += $m }
    catch {
        $script:FailedModules += $m
        Write-Log ERROR "modules" "module_failed" "Module $m failed: $($_.Exception.Message)" 1
        # Fail-fast: mirror the Bash ERR trap so we never run modules whose
        # ordered prerequisites just failed.
        break
    }
}

# npm 12 install-script approval can only name an installed package, so converge
# after the modules that install pi packages and before the gates that use them.
$script:CurrentModule = 'pi-npm'
if (-not $script:FailedModules -and ($selected -contains 'pi' -or $selected -contains 'pi-packages' -or $selected -contains 'gentle-ai' -or $selected -contains 'pi-workflows')) {
    try {
        Approve-NpmInstallScripts -Dir $PiNpmDir
    } catch {
        $script:FailedModules += 'pi-npm'
        Write-Log ERROR "pi-npm" "install_scripts_unverified" $_.Exception.Message 1
    }
}

# Skip quality gates when a module already failed (Bash aborts before them).
if (-not $script:FailedModules) {
    try {
        Invoke-QualityGates -Selected $selected
    } catch {
        $script:FailedModules += 'quality'
        Write-Log ERROR "quality" "gates_failed" $_.Exception.Message 1
    }
}

# Report
$script:CurrentModule = 'report'
$reportNode = if (Test-Cmd node) { Get-ReportCommandValue -Command "node" -Arguments @("--version") } else { "n/a" }
$reportNpm = if (Test-Cmd npm) { Get-ReportCommandValue -Command "npm" -Arguments @("--version") } else { "n/a" }
$reportGo = if (Test-Cmd go) { Get-ReportCommandValue -Command "go" -Arguments @("version") } else { "n/a" }
@"
# AI Dev Suite - Engineering Report (Windows)

**Script version:** $ScriptVersion
**Run ID:** $RunId
**Selected modules:** $($selected -join ' ')
**Failed modules:** $(if ($script:FailedModules) { $script:FailedModules -join ' ' } else { 'none' })

## Versions
- Node: $reportNode
- npm:  $reportNpm
- Go:   $reportGo
- pi:   $(if (Test-Cmd pi) { 'installed' } else { 'n/a' })

Logs: $HumanLog ; $JsonlLog
"@ | Set-Content -Path $ReportFile

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " AI Dev Suite (Windows) setup finished" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Modules : $($selected -join ' ')"
$exitCode = 0
if ($script:FailedModules) {
    Write-Host "Failed  : $($script:FailedModules -join ' ')" -ForegroundColor Yellow
    Write-Log ERROR "bootstrap" "completed_with_failures" "Setup finished with failed modules or quality gates" 1 "failed=$($script:FailedModules -join ',')"
    $exitCode = 1
} else {
    Write-Log INFO "bootstrap" "completed" "Setup completed successfully" 0
}
# The summary is the terminal record of the run, as it is in setup-ai.sh.
Write-RunSummary -Selected $script:SelectedModules -Succeeded $script:SucceededModules -FailedModules $script:FailedModules -ExitCode $exitCode
Write-Host "Report  : $ReportFile"
if ($exitCode -eq 0) {
    Write-Host "`nNext: open a new terminal so PATH updates apply."
}
exit $exitCode
