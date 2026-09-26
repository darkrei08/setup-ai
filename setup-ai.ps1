#Requires -Version 7.3
<#
==============================================================================
 AI Dev Suite - Engineering Excellence Edition (Windows)
 Version: 3.6.5

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
   pwsh -File setup-ai.ps1 -Yes            # never prompt: no interactive selectors
   pwsh -File setup-ai.ps1 -List
   pwsh -File setup-ai.ps1 -Help
   pwsh -File setup-ai.ps1 -Verbose
   pwsh -File setup-ai.ps1 -DryRun
   pwsh -File setup-ai.ps1 -Uninstall [-Yes] [-Purge] [-Only csv]
==============================================================================
#>

[CmdletBinding()]
param(
    [string]$Only = "",
    [switch]$All,
    [switch]$List,
    [switch]$Yes,
    [switch]$Help,
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Purge
)

$OnlySpecified = $PSBoundParameters.ContainsKey('Only')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptVersion = "3.6.5"
$ScriptPath = $PSCommandPath
$ScriptDir = Split-Path -Parent $ScriptPath
$LogDir = Join-Path $ScriptDir "logs"

$RunId = (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$HumanLog = Join-Path $LogDir "setup_$RunId.log"
$JsonlLog = Join-Path $LogDir "setup_$RunId.jsonl"
$ReportFile = Join-Path $LogDir "engineering-report_$RunId.md"
$RunStartedAt = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
$RunStartTime = Get-Date

$EE_Slug  = "darkrei08/Engineering-Excellence"
$EE_Skill = "engineering-excellence"
$PiAgentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME ".pi\agent" }
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

# Marker of the transient-rename retry in pi-extensible-workflows. State is written as
# a bare write(.tmp) + rename(), so a transient lock on the target (Defender, indexing,
# sync client, or a concurrent pi process) fails the write with EPERM unless the loaded
# artifact retries it. The retry ships in the published release; the version string
# cannot prove which build pi loads, so the symbol in the artifact is the proof.
$PiWorkflowsRetryMarker = 'renameWithRetry'
# Holds the resolved published workflow version for the module and its readbacks.
$script:SetupAiWorkflowVersion = ''
$script:LazyVimCloned = $false

# npm 12 blocks a dependency's install scripts until that package is explicitly
# approved; these are the ones the toolchain depends on. Declared once so the
# .npmrc policy and the post-install approve/rebuild pass cannot drift apart.
$Npm12InstallScriptPackages = @('gentle-pi','node-pty','pi-tool-display')

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
    pi = Join-Path $PiAgentDir "skills"
    'claude-code' = Join-Path $HOME ".claude\skills"
    'gemini-cli' = Join-Path $HOME ".gemini\skills"
    cursor = Join-Path $HOME ".cursor\skills"
    antigravity = Join-Path $HOME ".antigravity\skills"
    codex = Join-Path $HOME ".codex\skills"
    opencode = Join-Path $HOME ".config\opencode\skills"
}
# Agents the skills CLI classifies as universal (`agents[type].skillsDir ==
# ".agents/skills"`, skills 1.5.26): their --global install target IS the shared root
# and they read it at user scope, so no copy under their own config dir is expected.
$SkillSharedRootAgents = @('codex')
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
        [System.Collections.IDictionary]$Summary = $null, [bool]$Optional = $false, [string]$Behavior = ""
    )
    $ts = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
    $optionalSupplied = $PSBoundParameters.ContainsKey('Optional')
    $behaviorSupplied = $PSBoundParameters.ContainsKey('Behavior')
    $obj = [ordered]@{
        ts = $ts; lvl = $Level; ph = $Phase; ev = $Event
        msg = $Message; rc = $ReturnCode; rid = $RunId; pid = $PID
    }
    if ($Meta) { $obj.meta = $Meta }
    if ($Summary) { $obj.summary = $Summary }
    if ($ReturnCode -ne 0) {
        $err = [ordered]@{ rc = $ReturnCode }
        if ($optionalSupplied) { $err.optional = $Optional }
        if ($behaviorSupplied) { $err.behavior = $Behavior }
        $obj.err = $err
    }
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
    if ($script:VerboseOutput) {
        Write-Host ""
        Write-Host "[$Level] $Phase / $Event"
        Write-Host "  $Message"
        if ($Meta) { Write-Host "  Details: $Meta" }
        if ($ReturnCode -ne 0) { Write-Host "  Return code: $ReturnCode" }
    } else {
        switch ($Level) {
            'INFO'  { Write-Host $line -ForegroundColor Blue }
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            'DEBUG' { if ($env:DEBUG -eq '1') { Write-Host $line -ForegroundColor DarkGray } }
            default { Write-Host $line }
        }
    }
}

function Write-ModuleBanner {
    param([int]$Index, [int]$Total, [string]$Name)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ("  [{0}/{1}] {2}" -f $Index, $Total, $Name) -ForegroundColor White
    Write-Host ("  {0}" -f $ModuleDesc[$Name]) -ForegroundColor Gray
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
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
# Post-install steps a module cannot perform for the user (an interactive login, a
# token). They are printed with the closing summary so they are not buried in the log.
$script:PostInstallActions = @()
# Ctrl+C: Windows has no HUP/TERM, so the console event is cancelled and the run
# finishes with the same `interrupted` summary setup-ai.sh writes on a signal.
$script:Interrupted = $false
$script:InterruptSignal = ""
# The module that was running when the signal arrived, kept separate from
# $script:CurrentModule because the later phases overwrite that one.
$script:InterruptModule = ""
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
    if ($script:Interrupted) {
        # The same terminal outcome setup-ai.sh writes when a signal ends the run.
        $outcome = 'interrupted'
        $level = 'ERROR'
    }
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
    if ($script:Interrupted) {
        $message += ";interrupted=true;signal=$($script:InterruptSignal)"
        $reportLines += "- Interrupted by: $($script:InterruptSignal)"
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

# Ctrl+C is the Windows counterpart of the signals setup-ai.sh traps. .NET delivers
# it as SIGINT, and the handler must be pure .NET because a PowerShell scriptblock
# cannot run on the signal thread. Cancelling the default termination lets the run
# reach its `interrupted` summary instead of dying without one; the module loop and
# the gates stop at the next boundary. The handler is registered in the main flow,
# after the -List/-Help exits, so queries never pay for Add-Type.
function Test-Interrupted {
    if (-not $script:Interrupted -and [SetupAiInterrupt]::Interrupted) {
        $script:Interrupted = $true
        $script:InterruptSignal = 'INT'
        # Snapshot the first place that observed the signal; the later phase
        # reassignments overwrite $script:CurrentModule.
        if (-not $script:InterruptModule) { $script:InterruptModule = $script:CurrentModule }
    }
    return $script:Interrupted
}

function Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Resolve-GentleAiCli {
    if (Test-Cmd gentle-ai) { return }
    $directory = Join-Path $env:LOCALAPPDATA "gentle-ai\bin"
    $binary = Join-Path $directory "gentle-ai.exe"
    if (Test-Path -LiteralPath $binary -PathType Leaf) {
        $env:Path = "$directory;$env:Path"
        Write-Log INFO "gentle-ai" "cli_resolved" "Resolved gentle-ai CLI outside PATH" 0 "directory=$directory"
    }
}

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
        [string]$Step = '',
        [string]$CaptureOutput = ''
    )
    # Step identity for the step_result record: an explicit label when the helper has
    # one, otherwise the action source with whitespace collapsed.
    $step = if ($Step) { $Step } else { ($Action.ToString() -replace '\s+', ' ').Trim() }
    $kind = if ($Verify) { 'verified' } else { 'installed' }
    Write-Log INFO $Phase "step_start" "Running step" 0 "step=$step"
    Write-Host "  Step: $step" -ForegroundColor Gray
    Write-Host "  Live output follows. Prompts, including sudo, appear here." -ForegroundColor DarkMagenta
    Write-Host ""
    try {
        $global:LASTEXITCODE = 0
        if ($CaptureOutput) {
            [IO.File]::WriteAllText($CaptureOutput, [string]::Empty)
            & $Action 2>&1 | Tee-Object -FilePath $HumanLog -Append | Tee-Object -FilePath $CaptureOutput -Append | Out-Host
        } else {
            & $Action 2>&1 | Tee-Object -FilePath $HumanLog -Append | Out-Host
        }
        $nativeExitCode = $global:LASTEXITCODE
        if ($nativeExitCode -ne 0) {
            if ($ExpectedExitCodes -contains $nativeExitCode) {
                Write-Log INFO $Phase "step_expected" "Step returned expected exit code $nativeExitCode" 0
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
            Write-Log INFO $Phase "step_expected" "Step returned expected exit code $nativeExitCode" 0
            Write-StepResult -Phase $Phase -Status $kind -ReturnCode 0 -Step $step
            return $null
        }
        # Keep the real code, including a negative HRESULT-style one; only a missing code
        # (a wrapped exception rather than a native failure) falls back to 1.
        $rc = if ($null -ne $nativeExitCode) { [int]$nativeExitCode } else { 1 }
        if ($rc -eq 0) { $rc = 1 }
        if ($Optional) {
            Write-Log WARN $Phase "step_failed_optional" "$($_.Exception.Message); continuing" $rc -Optional:$Optional -Behavior continue
            Write-StepResult -Phase $Phase -Status 'skipped' -ReturnCode $rc -Step $step
            return $false
        }
        Write-Log ERROR $Phase "step_failed" "$($_.Exception.Message)" $rc -Optional:$false -Behavior abort
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

# Vendor installers decide interactivity from the console, not from flags, so a
# pi action menu would block an unattended run. An empty stdin pipe makes the
# child's console non-interactive, so the vendor script takes its documented
# default instead of waiting on a keypress.
function Invoke-RemoteScriptNoPrompt {
    param([string]$Url, [string]$Phase, [switch]$Optional)
    Invoke-Step -Phase $Phase -Optional:$Optional -Action {
        $script = Invoke-RestMethod -Uri $Url -UseBasicParsing
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("setup-ai-remote-" + [guid]::NewGuid().ToString("N") + ".ps1")
        Set-Content -LiteralPath $tmp -Value $script -Encoding utf8
        try {
            $pwshPath = (Get-Process -Id $PID).Path
            "" | & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $tmp
            if ($LASTEXITCODE -ne 0) { throw "remote installer exited with code $LASTEXITCODE" }
        } finally {
            if (Test-Path -LiteralPath $tmp) {
                try {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop
                } catch {
                    Write-Log WARN $Phase "cleanup_failed" "Could not remove temporary vendor installer: $($_.Exception.Message)"
                }
            }
        }
    }
}

function Test-NodeMinimum {
    param(
        [int]$MinimumMajor = 22,
        [int]$MinimumMinor = 19
    )
    $script:SetupAiNodeVersionProbe = ''
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
    return (($major -gt $MinimumMajor) -or (($major -eq $MinimumMajor) -and ($minor -ge $MinimumMinor)))
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
        # this agent's own config dir: reported, never hidden, and never a failure. An
        # agent whose own install target is that shared root is reported at INFO.
        $ownRoot = if ($SkillAgentRoots.ContainsKey($agent)) { $SkillAgentRoots[$agent] } else { $null }
        if ($ownRoot -and -not (Test-Path -LiteralPath (Join-Path (Join-Path $ownRoot $Skill) "SKILL.md"))) {
            if ($SkillSharedRootAgents -contains $agent) {
                Write-Log INFO $Phase "skill_shared_root_only" "Skill is installed under the shared skills root, which is this agent's own install target" 0 "agent=$agent;skill=$Skill;shared=$(Join-Path $HOME '.agents\skills')"
            } else {
                Write-Log WARN $Phase "skill_not_copied_to_agent_root" "Skill is installed under the shared skills root but was not copied into this agent's own config dir" 0 "agent=$agent;skill=$Skill;shared=$(Join-Path $HOME '.agents\skills')"
            }
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

# Prefer a caller-provided GitHub token, then the GitHub CLI's current login, so
# release metadata requests do not spend the unauthenticated API quota.
function Get-GitHubToken {
    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN.Trim() } else { '' }
    if (-not $token -and (Test-Cmd gh)) {
        try {
            $token = (@(gh auth token 2>$null) -join '').Trim()
        } catch {
            $token = ''
        }
    }
    return $token
}

function Get-GitHubApiHeaders {
    $token = Get-GitHubToken
    $headers = @{ 'User-Agent' = 'setup-ai' }
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return $headers
}

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
    #
    # allow-scripts is the policy that has to survive `pi update --extensions`: an
    # approval written into package.json's allowScripts field is lost the next time pi
    # rewrites that file, and the blocked scripts come back as "pending". npm reads the
    # policy from .npmrc as well, and pi does not own that file.
    $allowScriptsLine = 'allow-scripts=' + ($Npm12InstallScriptPackages -join ',')
    Add-LineIfMissing -Path $npmrc -Line 'allow-remote=all'
    Add-LineIfMissing -Path $npmrc -Line 'allow-git=all'
    Add-LineIfMissing -Path $npmrc -Line $allowScriptsLine

    # Verify the file npm will actually read, not the write we intended.
    $verified = $false
    if (Test-Path -LiteralPath $npmrc -PathType Leaf) {
        $verified = [bool](Select-String -LiteralPath $npmrc -CaseSensitive -Pattern '^allow-remote=all$' -Quiet) -and [bool](Select-String -LiteralPath $npmrc -CaseSensitive -Pattern '^allow-git=all$' -Quiet) -and [bool](Select-String -LiteralPath $npmrc -CaseSensitive -Pattern ('^' + [regex]::Escape($allowScriptsLine) + '$') -Quiet)
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

# True when this npm enforces the npm 12 install-script gate. Probes the subcommand
# instead of trusting a version number: npm < 12, and any other package manager pi can
# be configured with, does not implement it.
function Test-NpmInstallScriptsSupport {
    param([string]$Phase)
    return [bool](Invoke-Step -Phase $Phase -Optional -Verify -Action { npm install-scripts --help | Out-Null })
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
    if (-not (Test-NpmInstallScriptsSupport -Phase $Phase)) {
        Write-Log INFO $Phase "install_scripts_unsupported" "This npm does not implement install-scripts; dependency install-script approval skipped" 0 "dir=$Dir"
        return
    }
    # The packages whose blocked install scripts the toolchain depends on; one that
    # is not installed in this root is a skip, never an error.
    $present = @()
    foreach ($pkg in $Npm12InstallScriptPackages) {
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

# Prove an installed atomic-write module carries the transient-rename retry.
# Returns $false with a WARN when it cannot be proven, so callers decide the fallback.
function Assert-TransientRenameRetry {
    param([string]$IoJs, [string]$Phase, [string]$Context)

    if (-not (Test-Path -LiteralPath $IoJs -PathType Leaf)) {
        Write-Log WARN $Phase "retry_probe_missing" "Atomic-write module not found; cannot prove the transient-rename retry" 0 "path=$IoJs;context=$Context"
        return $false
    }
    if (-not (Test-TransientRenameMarker -IoJs $IoJs)) {
        Write-Log WARN $Phase "retry_missing" "Artifact has no transient-rename retry; EPERM-prone state writes stay unfixed" 0 "path=$IoJs;context=$Context;remedy=reinstall the latest pi-extensible-workflows release"
        return $false
    }
    Write-Log INFO $Phase "retry_verified" "Transient-rename retry present in the loaded artifact" 0 "path=$IoJs;context=$Context"
    return $true
}

# Pi identities retain npm scope and git owner, strip versions/refs, and resolve
# local sources against the agent directory. Both installers use this same shape.
function Get-PiPackageIdentity {
    param([string]$Spec, [string]$BaseDir)
    $spec = ([string]$Spec).Trim().Replace('\', '/')
    if ($spec.StartsWith('npm:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
        $at = $spec.LastIndexOf('@')
        if ($at -gt 0) { $spec = $spec.Substring(0, $at) }
        if (-not $spec) { throw 'Invalid npm package source.' }
        return "npm:$($spec.ToLowerInvariant())"
    }
    if ($spec.StartsWith('git:', [StringComparison]::Ordinal)) {
        $spec = $spec.Substring(4)
        $hash = $spec.IndexOf('#')
        if ($hash -ge 0) { $spec = $spec.Substring(0, $hash) }
        $at = $spec.LastIndexOf('@')
        if ($at -gt 0) { $spec = $spec.Substring(0, $at) }
        if ($spec.EndsWith('.git', [StringComparison]::Ordinal)) { $spec = $spec.Substring(0, $spec.Length - 4) }
        if (-not $spec) { throw 'Invalid git package source.' }
        return "git:$($spec.ToLowerInvariant())"
    }
    if ($spec -eq '~' -or $spec.StartsWith('~/') -or $spec.StartsWith('~\')) {
        $spec = Join-Path $HOME $spec.Substring(1).TrimStart([char]'\', [char]'/')
    }
    $pathSpec = $spec.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $full = if ([System.IO.Path]::IsPathRooted($pathSpec)) { [System.IO.Path]::GetFullPath($pathSpec) } else { [System.IO.Path]::GetFullPath((Join-Path $BaseDir $pathSpec)) }
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $full = $full.ToLowerInvariant() }
    return "local:$full"
}

function Get-PiPackageRegistrationState {
    param([string]$Spec)
    $settingsPath = Join-Path $PiAgentDir 'settings.json'
    $identity = Get-PiPackageIdentity -Spec $Spec -BaseDir $PiAgentDir
    if (-not (Test-Path -LiteralPath $settingsPath)) { return [pscustomobject]@{ Known = $true; Count = 0; Identity = $identity } }
    try {
        $parsed = Get-Content -Raw -LiteralPath $settingsPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed -or $parsed -is [array]) { throw 'Invalid Pi settings object.' }
        $packagesProperty = $parsed.PSObject.Properties['packages']
        if ($null -eq $packagesProperty) { $entries = @() }
        elseif ($null -eq $packagesProperty.Value -or $packagesProperty.Value -isnot [array]) { throw 'Invalid Pi packages list.' }
        else { $entries = @($packagesProperty.Value) }
        $count = 0
        foreach ($entry in $entries) {
            if ($entry -is [string]) { $source = $entry }
            elseif ($null -ne $entry -and $null -ne $entry.PSObject.Properties['source'] -and $entry.source -is [string]) { $source = $entry.source }
            else { throw 'Ambiguous Pi package entry.' }
            if ((Get-PiPackageIdentity -Spec $source -BaseDir $PiAgentDir) -ceq $identity) { $count++ }
        }
        return [pscustomobject]@{ Known = $true; Count = $count; Identity = $identity }
    } catch {
        return [pscustomobject]@{ Known = $false; Count = -1; Identity = $identity }
    }
}

function Get-PiPackageReceiptPath {
    param([string]$Spec)
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $null }
    $identity = Get-PiPackageIdentity -Spec $Spec -BaseDir $PiAgentDir
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($identity))).ToLowerInvariant() }
    finally { $sha.Dispose() }
    return Join-Path (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'setup-ai') 'ownership') 'pi-packages') "$digest.json"
}

function Test-PiPackageReceiptLocation {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or -not $Path) { return $false }
    $root = Join-Path $env:LOCALAPPDATA 'setup-ai'
    $ownership = Join-Path $root 'ownership'
    $directory = Join-Path $ownership 'pi-packages'
    $paths = @($env:LOCALAPPDATA, $root, $ownership, $directory, $Path)
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath((Join-Path $directory ([System.IO.Path]::GetFileName($Path)))), [StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path)) -cne [System.IO.Path]::GetFullPath($directory)) { return $false }
    try {
        foreach ($candidate in $paths) {
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            $attributes = [System.IO.File]::GetAttributes($candidate)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-PiPackageReceiptState {
    param([string]$Spec)
    $path = Get-PiPackageReceiptPath -Spec $Spec
    if (-not $path -or -not (Test-PiPackageReceiptLocation -Path $path)) { return [pscustomobject]@{ Safe = $false; Exists = $false; Valid = $false; Receipt = $null } }
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ Safe = $true; Exists = $false; Valid = $false; Receipt = $null } }
    try {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Receipt is not a file.' }
        $receipt = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $identity = Get-PiPackageIdentity -Spec $Spec -BaseDir $PiAgentDir
        $agentDir = [System.IO.Path]::GetFullPath($PiAgentDir)
        if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $agentDir = $agentDir.ToLowerInvariant() }
        $valid = $receipt -is [pscustomobject] -and $receipt.SchemaVersion -eq 1 -and
            $receipt.Identity -is [string] -and $receipt.Identity -ceq $identity -and
            $receipt.Spec -is [string] -and (Get-PiPackageIdentity -Spec $receipt.Spec -BaseDir $PiAgentDir) -ceq $identity -and
            $receipt.AgentDir -is [string] -and $receipt.AgentDir -ceq $agentDir
        return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = [bool]$valid; Receipt = $(if ($valid) { $receipt } else { $null }) }
    } catch { return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = $false; Receipt = $null } }
}

function Write-PiPackageReceipt {
    param([string]$Spec)
    $path = Get-PiPackageReceiptPath -Spec $Spec
    if (-not $path -or -not (Test-PiPackageReceiptLocation -Path $path)) { return $false }
    $state = Get-PiPackageReceiptState -Spec $Spec
    if (-not $state.Safe -or $state.Exists) { return $false }
    $directory = Split-Path -Parent $path
    try {
        New-Item -ItemType Directory -Force -Path $directory -ErrorAction Stop | Out-Null
        if (-not (Test-PiPackageReceiptLocation -Path $path)) { return $false }
        $identity = Get-PiPackageIdentity -Spec $Spec -BaseDir $PiAgentDir
        $agentDir = [System.IO.Path]::GetFullPath($PiAgentDir)
        if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $agentDir = $agentDir.ToLowerInvariant() }
        $json = [pscustomobject]@{ SchemaVersion = 1; Identity = $identity; Spec = $Spec; AgentDir = $agentDir } | ConvertTo-Json -Compress
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
        $tempPath = Join-Path $directory ('.pi-registration.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream = $null
            if (-not (Test-PiPackageReceiptLocation -Path $path) -or (Test-Path -LiteralPath $path)) { return $false }
            [System.IO.File]::Move($tempPath, $path)
        } finally {
            if ($null -ne $stream) { $stream.Dispose() }
            if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
        }
        return (Get-PiPackageReceiptState -Spec $Spec).Valid
    } catch { return $false }
}

function Get-PiPackageInventoryStatus {
    param([string]$Spec)
    $registration = Get-PiPackageRegistrationState -Spec $Spec
    if (-not $registration.Known) { return [pscustomobject]@{ State = 'unknown'; Message = 'protected; Pi settings could not be read unambiguously.' } }
    $receipt = Get-PiPackageReceiptState -Spec $Spec
    if (-not $receipt.Safe) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; Pi ownership receipt path is unsafe.' } }
    if ($registration.Count -gt 1) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; duplicate exact Pi registrations exist.' } }
    if ($registration.Count -eq 0) {
        if ($receipt.Exists) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; a stale or invalid Pi ownership receipt is preserved.' } }
        return [pscustomobject]@{ State = 'absent'; Message = 'absent.' }
    }
    if ($receipt.Valid) { return [pscustomobject]@{ State = 'receipt-backed'; Message = 'receipt-backed exact registration; removable with -Yes.' } }
    return [pscustomobject]@{ State = 'protected'; Message = 'protected; registration has no matching valid receipt.' }
}

function Assert-PiPackageRegistered {
    param([string]$Phase, [string]$Spec)
    $state = Get-PiPackageRegistrationState -Spec $Spec
    if (-not $state.Known) {
        Write-Log ERROR $Phase 'settings_unreadable' 'pi settings.json could not be read unambiguously' 1 "path=$(Join-Path $PiAgentDir 'settings.json')"
        throw 'Pi settings state is unknown.'
    }
    if ($state.Count -eq 1) {
        Write-Log INFO $Phase 'package_registered' 'Pi registered the exact package identity' 0 "spec=$Spec"
        return
    }
    $event = if ($state.Count -gt 1) { 'package_duplicate' } else { 'package_not_registered' }
    Write-Log ERROR $Phase $event 'Pi did not register exactly one matching package identity' 1 "spec=$Spec;count=$($state.Count)"
    throw "Pi did not register exactly one package identity ($Spec)."
}

function Install-PiPackageOwned {
    param([string]$Phase, [string]$Spec)
    $before = Get-PiPackageRegistrationState -Spec $Spec
    if (-not $before.Known) { throw "Cannot prove Pi package was absent before install ($Spec)." }
    $null = Invoke-Step -Phase $Phase -Action { pi install $Spec }
    Assert-PiPackageRegistered -Phase $Phase -Spec $Spec
    if ($before.Count -eq 0 -and -not (Write-PiPackageReceipt -Spec $Spec)) {
        Write-Log ERROR $Phase 'pi_receipt_publish_failed' 'Pi registration succeeded but its ownership receipt could not be safely published' 1 "spec=$Spec"
        throw "Pi ownership receipt could not be published ($Spec)."
    }
}

function Restore-PiPackageRegistration {
    param([string]$Phase, [string]$Spec)
    $state = Get-PiPackageRegistrationState -Spec $Spec
    if (-not $state.Known) { return $false }
    if ($state.Count -eq 1) { return $true }
    if ($state.Count -ne 0) { return $false }
    try { $null = Invoke-Step -Phase $Phase -Action { pi install $Spec } }
    catch {
        Write-Log ERROR $Phase 'pi_registration_restore_failed' 'Could not restore the Pi registration after a failed removal' 1 "spec=$Spec"
        return $false
    }
    $state = Get-PiPackageRegistrationState -Spec $Spec
    return $state.Known -and $state.Count -eq 1
}

function Restore-PiPackageReceipt {
    param([string]$Path, [string]$Contents)
    if (-not (Test-PiPackageReceiptLocation -Path $Path)) { return $false }
    if (Test-Path -LiteralPath $Path) {
        try { return [System.IO.File]::ReadAllText($Path) -ceq $Contents } catch { return $false }
    }
    $directory = Split-Path -Parent $Path
    $tempPath = Join-Path $directory ('.pi-registration-restore.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $stream = $null
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Contents)
        $stream = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream = $null
        if (-not (Test-PiPackageReceiptLocation -Path $Path) -or (Test-Path -LiteralPath $Path)) { return $false }
        [System.IO.File]::Move($tempPath, $Path)
        return [System.IO.File]::ReadAllText($Path) -ceq $Contents
    } catch { return $false }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
    }
}

function Remove-PiPackageRegistration {
    param([string]$Spec, [switch]$Confirmed, [switch]$DryRun)
    if (-not $Confirmed -or $DryRun) { return $false }
    $registration = Get-PiPackageRegistrationState -Spec $Spec
    $receiptState = Get-PiPackageReceiptState -Spec $Spec
    if (-not $registration.Known -or -not $receiptState.Safe) { $script:PiPackageRemovalFailed = $true; return $false }
    if ($registration.Count -gt 1 -or ($registration.Count -eq 0 -and $receiptState.Exists) -or ($receiptState.Exists -and -not $receiptState.Valid)) {
        $script:PiPackageRemovalFailed = $true
        return $false
    }
    if ($registration.Count -eq 0 -or -not $receiptState.Valid) { return $false }
    $path = Get-PiPackageReceiptPath -Spec $Spec
    try { $receiptBefore = [System.IO.File]::ReadAllText($path) } catch { $script:PiPackageRemovalFailed = $true; return $false }
    $current = Get-PiPackageRegistrationState -Spec $Spec
    $currentReceipt = Get-PiPackageReceiptState -Spec $Spec
    if (-not $current.Known -or $current.Count -ne 1 -or -not $currentReceipt.Valid) { $script:PiPackageRemovalFailed = $true; return $false }
    try { if ([System.IO.File]::ReadAllText($path) -cne $receiptBefore) { $script:PiPackageRemovalFailed = $true; return $false } }
    catch { $script:PiPackageRemovalFailed = $true; return $false }
    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) { $script:PiPackageRemovalFailed = $true; return $false }
    try { Invoke-Step -Phase 'uninstall' -Action { pi remove $currentReceipt.Receipt.Spec } | Out-Null }
    catch {
        $script:PiPackageRemovalFailed = $true
        $afterFailure = Get-PiPackageRegistrationState -Spec $Spec
        if ($afterFailure.Known -and $afterFailure.Count -eq 0 -and -not (Restore-PiPackageRegistration -Phase 'uninstall-rollback' -Spec $currentReceipt.Receipt.Spec)) {
            Write-Log ERROR 'uninstall' 'pi_registration_restore_failed' 'Could not restore the Pi registration after a failed remove command' 1 "spec=$Spec"
        }
        return $false
    }
    $after = Get-PiPackageRegistrationState -Spec $Spec
    if (-not $after.Known -or $after.Count -ne 0) { $script:PiPackageRemovalFailed = $true; return $false }
    $finalReceipt = Get-PiPackageReceiptState -Spec $Spec
    $receiptMatches = $false
    if ($finalReceipt.Valid) {
        try { $receiptMatches = [System.IO.File]::ReadAllText($path) -ceq $receiptBefore } catch { $receiptMatches = $false }
    }
    if (-not $receiptMatches) {
        if (-not (Restore-PiPackageReceipt -Path $path -Contents $receiptBefore)) { Write-Log ERROR 'uninstall' 'pi_receipt_restore_failed' 'Could not preserve the original Pi ownership receipt after post-remove verification failed' 1 "path=$path" }
        if (-not (Restore-PiPackageRegistration -Phase 'uninstall-rollback' -Spec $currentReceipt.Receipt.Spec)) { Write-Log ERROR 'uninstall' 'pi_registration_restore_failed' 'Could not restore the Pi registration after receipt verification failed' 1 "spec=$Spec" }
        $script:PiPackageRemovalFailed = $true
        return $false
    }
    try {
        [System.IO.File]::Delete($path)
        if (Test-Path -LiteralPath $path) { throw 'Receipt remains after deletion.' }
        return $true
    } catch {
        if (-not (Restore-PiPackageReceipt -Path $path -Contents $receiptBefore)) { Write-Log ERROR 'uninstall' 'pi_receipt_restore_failed' 'Could not restore the Pi ownership receipt after receipt deletion failed' 1 "path=$path" }
        if (-not (Restore-PiPackageRegistration -Phase 'uninstall-rollback' -Spec $currentReceipt.Receipt.Spec)) { Write-Log ERROR 'uninstall' 'pi_registration_restore_failed' 'Could not restore the Pi registration after receipt deletion failed' 1 "spec=$Spec" }
        $script:PiPackageRemovalFailed = $true
        return $false
    }
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

function Get-PiUninstallSpecs {
    param([string]$Module)
    $specs = switch ($Module) {
        'pi-workflows' { @('npm:pi-extensible-workflows') }
        'gentle-ai' { @('npm:gentle-pi', 'npm:pi-mcp-adapter') }
        'rotator' { @('git:github.com/darkrei08/pi-cockpit-tools-sync') }
        'pi-packages' {
            $manifest = Get-PiPackagesManifest
            if (-not $manifest) { @(); break }
            $workflowIdentity = Get-PiPackageIdentity -Spec 'npm:pi-extensible-workflows' -BaseDir $PiAgentDir
            $entries = @()
            foreach ($rawLine in (Get-Content -LiteralPath $manifest -ErrorAction Stop)) {
                $line = ($rawLine -split '#', 2)[0].Trim()
                if (-not $line) { continue }
                if ((Get-PiPackageIdentity -Spec $line -BaseDir $PiAgentDir) -ceq $workflowIdentity) { continue }
                $entries += $line
            }
            $entries
        }
        default { @() }
    }
    $result = @(); $identities = @()
    foreach ($spec in @($specs)) {
        $identity = Get-PiPackageIdentity -Spec $spec -BaseDir $PiAgentDir
        if ($identities -ccontains $identity) { continue }
        $identities += $identity; $result += $spec
    }
    return ,$result
}

# ==============================================================================
# Module registry
# ==============================================================================

$ModuleOrder = @('base','node','bun','pi','dotenv','lazyvim','pi-packages','go','ee','skills','pi-workflows','herdr','claude-code','codex','antigravity','opencode','gentle-ai','cockpit','rotator')

$ModuleDesc = [ordered]@{
    'base'         = 'System packages (build tools, git, gh, python, neovim, jq, imagemagick, go, clipboard)'
    'node'         = 'Node.js v22 + npm@latest (nvm on Unix, winget on Windows)'
    'bun'          = 'Bun runtime'
    'pi'           = 'pi.dev coding agent CLI'
    'lazyvim'      = 'Neovim and LazyVim starter (headless sync)'
    'pi-packages'  = 'Extra Pi packages from a declarative manifest (pi-packages.txt)'
    'go'           = 'Go toolchain'
    'dotenv'       = 'darkrei08/dotenv dotfiles (Linux only: clones + runs setup_env.sh)'
    'ee'           = 'Engineering Excellence skill (npx skills add, all detected agents)'
    'skills'       = 'Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add'
    'pi-workflows' = 'pi-extensible-workflows (published release + npm 12 remote sources for pi installs)'
    'herdr'        = 'herdr terminal multiplexer'
    'claude-code'  = 'Anthropic Claude Code CLI'
    'gentle-ai'    = 'gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi'
    'codex'        = 'OpenAI Codex CLI'
    'antigravity'  = 'Google Antigravity CLI (agy)'
    'opencode'     = 'opencode agent CLI (opencode-ai)'
    'cockpit'      = 'cockpit-tools desktop GUI app (optional, CC BY-NC-SA)'
    'rotator'      = 'tuxevil-rotator multi-account Gemini/Antigravity gateway (installed and started in the background; optional, opt-in)'
}
$ModuleOptional = @{ 'cockpit' = $true; 'rotator' = $true }
# ponytail: static plans can drift from module bodies; move operations into shared metadata if drift becomes costly.
$ModuleDryRunPlan = [ordered]@{
    'base' = @(
        'Use winget to ensure Git, GitHub CLI, Python 3.12, Neovim, jq, ImageMagick, and Go are installed.'
        'Probe with vswhere for Microsoft.VisualStudio.Component.VC.Tools.x86.x64; if the workload is absent or unverified, run winget install --force for Visual Studio 2022 Build Tools with the VC Tools workload, then verify it and refresh PATH.'
    )
    'node' = @(
        'Use winget to ensure Node.js 22; upgrade only when installed Node.js is below 22.19.'
        'Refresh PATH, globally install npm@latest, and verify Node.js is at least 22.19.'
    )
    'bun' = @('If bun is available, verify bun --version; otherwise run https://bun.sh/install.ps1 and verify bun.')
    'pi' = @(
        'Create the Pi extensions, skills, and npm roots plus the npm project marker; write remote-source and allow-scripts policy only when npm 12+ is available.'
        'If pi is missing, run https://pi.dev/install.ps1, refresh PATH, and verify pi; otherwise keep the installed CLI.'
    )
    'dotenv' = @('Skip dotenv/setup_env.sh because it targets Linux package managers; no Windows action is defined.')
    'lazyvim' = @(
        'Install Neovim with winget only if nvim is missing; require git.'
        'If the Neovim config is absent, clone LazyVim starter, remove its .git metadata, run nvim --headless "+Lazy! sync" +qa, and move it into place; preserve an existing config.'
    )
    'pi-packages' = @(
        'Require pi and node on PATH before enabling npm remote sources and resolving the manifest.'
        'Resolve pi-packages.txt from PI_PACKAGES_FILE, the Pi agent directory, or the installer directory, in that order.'
        'If a manifest exists, run pi install and verify each listed package; skip pi-extensible-workflows because pi-workflows owns it. If absent, install no extra packages.'
    )
    'go' = @('If go is available, verify go version; otherwise install GoLang.Go with winget, refresh PATH, and verify Go.')
    'ee' = @(
        'Detect configured agents (fall back to pi) and run npx --yes skills@latest add darkrei08/Engineering-Excellence --skill engineering-excellence --global --agent <agent> --copy --yes for each.'
        'Verify the Engineering Excellence skill for every targeted agent.'
    )
    'skills' = @(
        'Run npx --yes skills@latest add for herdrdev/herdr (herdr), mattpocock/skills (triage, grill-me, grilling, wayfinder, domain-modeling, prototype, research), pedronauck/skills (typescript-advanced), and humanlayer/skills (show-me), for each detected agent.'
        'Verify every configured upstream skill for every targeted agent.'
    )
    'pi-workflows' = @(
        'Require pi, npm, and Node.js 22.19+; enable npm remote sources in the managed and extensions roots.'
        'Use PI_WORKFLOW_VERSION or resolve the release with npm view; install pi-extensible-workflows with pi and npm, then verify its version and retry marker.'
    )
    'herdr' = @('If herdr is available, verify herdr --version; otherwise run https://herdr.dev/install.ps1 and verify herdr.')
    'claude-code' = @(
        'If claude is missing, try https://claude.ai/install.ps1; if it fails or claude remains missing, use npm install -g @anthropic-ai/claude-code (with --allow-scripts when supported).'
        'Refresh PATH when installing and verify claude --version; otherwise verify the existing CLI.'
    )
    'codex' = @(
        'If codex is missing, run https://chatgpt.com/codex/install.ps1 with CODEX_NON_INTERACTIVE=1; otherwise keep the existing codex.'
        'Verify codex is available on PATH after the installer.'
    )
    'antigravity' = @('If agy is missing, run https://antigravity.google/cli/install.ps1 and verify agy; otherwise keep the existing CLI.')
    'opencode' = @(
        'If opencode is missing, install opencode-ai globally with npm and allow its install script when supported; if npm is available, also run the optional global rebuild.'
        'Verify opencode --version; if its no-shell launch probe fails, resolve and verify the native launcher before setting user/process OPENCODE_PI_BIN.'
    )
    'gentle-ai' = @(
        'Remove stale GENTLE_PI_QUIET_TOOLS=0; repair Pi settings only when an unambiguous safe edit is available, otherwise warn and leave ambiguous or unmodifiable conflicts unchanged.'
        'Install gentle-ai from its official script only if missing, then run gentle-ai install --scope global interactively with a TTY or non-interactively for detected agents; forward a GitHub token when available.'
        'With a TTY, retry nonzero selector failures unless interrupted; without a TTY, retry only when captured output matches the GitHub API HTTP 403 signature (up to two backoffs).'
        'If pi is available, install gentle-pi and pi-mcp-adapter; when gentle-pi is installed and npm supports approval, approve and rebuild its install script, then verify the review binary and Pi registrations. Repair settings safely again and verify pi startup.'
    )
    'cockpit' = @('Query the latest cockpit-tools GitHub release; if an MSI exists, download it and run msiexec /i /qb. If no MSI exists or the optional install fails, report/skip it.')
    'rotator' = @(
        'Probe localhost:51200/v1/models; if Node.js is missing or below 20, stop without installing the CLI, registering persistence, or starting the gateway.'
        'If Node.js is at least 20, install tuxevil-rotator with npm only if missing and verify it is available on PATH.'
        'Attempt best-effort registration and readback of the logon task with a 5-minute watchdog.'
        'Only if the initial gateway probe was down, start via the scheduled task when available or fall back to a detached process and poll readiness; if already reachable, skip starting it.'
        'Install/verify the Pi cockpit-sync extension only when pi is available.'
    )
}

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
    $vsWhere = if (${env:ProgramFiles(x86)}) {
        Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    } else {
        $null
    }
    $workloadPresent = $false
    if ($vsWhere -and (Test-Path $vsWhere)) {
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
    if (-not $vsWhere -or -not (Test-Path $vsWhere)) {
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
    New-Item -ItemType Directory -Force -Path (Join-Path $PiAgentDir "skills") | Out-Null
    New-Item -ItemType Directory -Force -Path $PiNpmDir | Out-Null
    # pi's managed npm root is where `pi install` and `pi update --extensions` land.
    # npm 12 refuses URL/tarball dependencies in that root unless it opts in, so
    # configure it as soon as the root exists - independent of any workflow module.
    Enable-NpmRemoteSources -Dir $PiNpmDir
    if (Test-Cmd pi) { Write-Log INFO "pi" "already_present" "pi already installed"; return }
    Invoke-RemoteScriptNoPrompt -Url "https://pi.dev/install.ps1" -Phase "pi"
    Update-SessionPath
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

function Mod-LazyVim {
    Write-Log INFO "lazyvim" "start" "Neovim + LazyVim"
    if (-not (Test-Cmd nvim)) {
        Install-Winget -Id "Neovim.Neovim" -Phase "lazyvim"
        Update-SessionPath
    }
    if (-not (Test-Cmd nvim)) { throw "nvim not found after winget install; lazyvim cannot be installed" }
    if (-not (Test-Cmd git)) { throw "git not found; lazyvim cannot be installed" }
    $configRoot = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { Join-Path $env:LOCALAPPDATA "nvim" }
    if (Test-Path -LiteralPath $configRoot -PathType Container) {
        Write-Log INFO "lazyvim" "config_present" "Preserving the existing Neovim configuration" 0 "path=$configRoot"
        return
    }
    $stagedConfig = Join-Path ([IO.Path]::GetTempPath()) ("setup-ai-nvim-" + [guid]::NewGuid().ToString("N"))
    try {
        Invoke-Step -Phase "lazyvim" -Action { git clone --depth=1 https://github.com/LazyVim/starter $stagedConfig }
        Invoke-Step -Phase "lazyvim" -Action { Remove-Item -LiteralPath (Join-Path $stagedConfig ".git") -Recurse -Force }
        Invoke-Step -Phase "lazyvim" -Action {
            $previousAppName = $env:NVIM_APPNAME
            $previousConfigHome = $env:XDG_CONFIG_HOME
            $env:NVIM_APPNAME = Split-Path -Leaf $stagedConfig
            $env:XDG_CONFIG_HOME = Split-Path -Parent $stagedConfig
            try { nvim --headless "+Lazy! sync" +qa } finally {
                $env:NVIM_APPNAME = $previousAppName
                $env:XDG_CONFIG_HOME = $previousConfigHome
            }
        }
        Invoke-Step -Phase "lazyvim" -Action { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configRoot) | Out-Null }
        Invoke-Step -Phase "lazyvim" -Action { Move-Item -LiteralPath $stagedConfig -Destination $configRoot }
    } finally {
        if (Test-Path -LiteralPath $stagedConfig) {
            try {
                Remove-Item -LiteralPath $stagedConfig -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Log WARN "lazyvim" "cleanup_failed" "Could not remove temporary LazyVim staging directory: $($_.Exception.Message)"
            }
        }
    }
    $script:LazyVimCloned = $true
    if (-not (Test-Path -LiteralPath $configRoot -PathType Container)) {
        throw "LazyVim configuration was not created at $configRoot"
    }
    Write-Log INFO "lazyvim" "config_verified" "LazyVim starter cloned and synchronized headlessly" 0 "path=$configRoot"
}

function Mod-Ee {
    Write-Log INFO "engineering-excellence" "start" "Engineering Excellence"
    if (-not (Test-Cmd npx)) { throw "npx not found; engineering-excellence cannot be installed (install the node module first)" }
    $agents = Get-TargetSkillAgents
    foreach ($a in $agents) {
        Invoke-Step -Phase "engineering-excellence" -Action {
            npx --yes skills@latest add $EE_Slug --skill $EE_Skill --global --agent $a --copy --yes
        }
    }
    Assert-SkillInstalledForAgents -Phase "engineering-excellence" -Skill $EE_Skill -Agents $agents
}

# Installs the shared skill stack via `npx skills add`; the upstream dotenv
# setup also installs its own copy on Linux, and both paths are idempotent.
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
    Install-PiPackageOwned -Phase "pi-workflows" -Spec "npm:pi-extensible-workflows@$ver"
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    # Append-only, so the npm 12 remote-source opt-in written above survives.
    Add-LineIfMissing -Path (Join-Path $PiExtDir ".npmrc") -Line "ignore-scripts=false"
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

    # Prove the artifact pi will load carries the transient-rename retry the published
    # release ships. Reading the installed file - not the install command - is the only
    # proof of which build was loaded; an unproven root is reported, never hidden.
    foreach ($root in @($PiExtDir, $PiNpmDir)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $rootIo = Join-Path $root "node_modules\pi-extensible-workflows\dist\src\io.js"
        $null = Assert-TransientRenameRetry -IoJs $rootIo -Phase "pi-workflows" -Context "root=$root"
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
# pi-workflows module owns that package (published release).
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
    $workflowId = Get-PiPackageIdentity -Spec 'npm:pi-extensible-workflows' -BaseDir $PiAgentDir
    foreach ($rawLine in (Get-Content -LiteralPath $manifest)) {
        # Strip a trailing comment, then trim surrounding whitespace only; internal
        # whitespace stays invalid input.
        $line = ($rawLine -split '#', 2)[0].Trim()
        if (-not $line) { continue }

        if ((Get-PiPackageIdentity -Spec $line -BaseDir $PiAgentDir) -ceq $workflowId) {
            Write-Log WARN "pi-packages" "workflow_owned_elsewhere" "Skipping pi-extensible-workflows; the pi-workflows module owns that package" 0 "spec=$line"
            $skipped++
            continue
        }

        Install-PiPackageOwned -Phase "pi-packages" -Spec $line
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

function Mod-ClaudeCode {
    Write-Log INFO "claude-code" "start" "Claude Code CLI"
    if (-not (Test-Cmd claude)) {
        $vendorInstalled = $false
        try {
            $vendorStepOk = Invoke-RemoteScriptNoPrompt -Url "https://claude.ai/install.ps1" -Phase "claude-code" -Optional
            Update-SessionPath
            $vendorInstalled = $vendorStepOk -and (Test-Cmd claude)
        } catch {
            Write-Log WARN "claude-code" "vendor_installer_failed" "Claude Code vendor installer failed; trying npm fallback" 0 "error=$($_.Exception.Message)"
        }
        if (-not $vendorInstalled) {
            if (-not (Test-Cmd npm)) { throw "claude not found after vendor installer and npm is unavailable" }
            $allowScripts = @()
            if (Test-NpmInstallScriptsSupport -Phase "claude-code") {
                $allowScripts = @('--allow-scripts=@anthropic-ai/claude-code')
            }
            Invoke-Step -Phase "claude-code" -Action { npm install -g @anthropic-ai/claude-code @allowScripts }
            Update-SessionPath
        }
        if (-not (Test-Cmd claude)) {
            Write-Log ERROR "claude-code" "install_missing" "claude not found on PATH after vendor installer and npm fallback"
            throw "claude not found on PATH after vendor installer and npm fallback"
        }
    } else {
        Write-Log INFO "claude-code" "already_present" "Claude Code already installed"
    }
    Invoke-Step -Phase "claude-code" -Verify -Action { claude --version }
}

# An earlier setup-ai version persisted GENTLE_PI_QUIET_TOOLS=0 next to
# pi-hashline-edit-pro to keep pi startable. That value is exactly the one that
# makes gentle-pi's bundled pi-pretty register the built-in tool names itself, so it
# now causes the startup abort it was meant to avoid. Remove the User-scope value
# this installer wrote, unconditionally: a machine can carry it with no shadowing
# package left. Any other value belongs to the user and is left alone.
function Remove-StaleQuietToolsSwitch {
    $changed = @()
    if ([Environment]::GetEnvironmentVariable('GENTLE_PI_QUIET_TOOLS', 'User') -eq '0') {
        [Environment]::SetEnvironmentVariable('GENTLE_PI_QUIET_TOOLS', $null, 'User')
        $changed += 'User:GENTLE_PI_QUIET_TOOLS'
    }
    if ($env:GENTLE_PI_QUIET_TOOLS -eq '0') {
        # The current session inherited the value when it started; clear it there too.
        $env:GENTLE_PI_QUIET_TOOLS = $null
        if ($changed.Count -eq 0) { $changed += 'Process:GENTLE_PI_QUIET_TOOLS' }
    }
    if ($changed.Count -eq 0) { return }
    Write-Log INFO "gentle-ai" "stale_quiet_tools_switch_removed" "Removed the GENTLE_PI_QUIET_TOOLS=0 switch an earlier setup-ai persisted: it disables gentle-pi quiet tools, which is what makes pi-pretty register the built-in tool names itself and abort startup" 0 ("removed=" + ($changed -join ','))
}

function Remove-StaleRpivQuestionExtension {
    $settings = Join-Path $PiAgentDir "settings.json"
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($settings)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $utf8 = New-Object System.Text.UTF8Encoding($hasBom)
    $offset = if ($hasBom) { 3 } else { 0 }
    $raw = $utf8.GetString($bytes, $offset, $bytes.Length - $offset)

    $hasGentle = $false
    $rpivEntries = @()
    try {
        $parsed = ConvertFrom-Json -InputObject $raw
        foreach ($entry in @($parsed.packages)) {
            if ($null -eq $entry) { continue }
            $isString = $entry -is [string]
            $source = if ($isString) { $entry } elseif ($null -ne $entry.PSObject.Properties['source']) { [string]$entry.source } else { '' }
            if ($source -cmatch '^npm:gentle-pi(@.*)?$') { $hasGentle = $true }
            if ($source -cmatch '^npm:@juicesharp/rpiv-ask-user-question(@.*)?$') { $rpivEntries += @{ Value = $entry; IsString = $isString } }
        }
    } catch {
        Write-Log WARN "gentle-ai" "rpiv_question_conflict_unrepaired" "Could not parse $settings while checking for the stale rpiv ask_user_question extension" 0 "settings=$settings"
        return
    }
    if (-not $hasGentle -or $rpivEntries.Count -eq 0) { return }
    if ($rpivEntries.Count -ne 1 -or -not $rpivEntries[0].IsString) {
        Write-Log WARN "gentle-ai" "rpiv_question_conflict_unrepaired" "The stale rpiv ask_user_question extension conflicts with gentle-pi; settings.json was not changed because its package entry is ambiguous" 0 "settings=$settings;package=npm:@juicesharp/rpiv-ask-user-question"
        return
    }

    $entryMatch = [regex]::Matches($raw, '(?m)^([ \t]*)"npm:@juicesharp/rpiv-ask-user-question(?:@[^\"]*)?"([ \t]*)(,?)[ \t]*(\r?)$')
    if ($entryMatch.Count -ne 1) {
        Write-Log WARN "gentle-ai" "rpiv_question_conflict_unrepaired" "The stale rpiv ask_user_question extension conflicts with gentle-pi; settings.json was unchanged because its entry could not be removed safely" 0 "settings=$settings;package=npm:@juicesharp/rpiv-ask-user-question"
        return
    }
    $updated = $raw.Remove($entryMatch[0].Index, $entryMatch[0].Length)
    if ([string]::IsNullOrEmpty($entryMatch[0].Groups[3].Value)) {
        $prefix = $updated.Substring(0, $entryMatch[0].Index)
        $prefix = [regex]::Replace($prefix, '(?m),([ \t]*\r?\n[ \t]*)$', '$1')
        $updated = $prefix + $updated.Substring($entryMatch[0].Index)
    }
    $tmp = "$settings.setup-ai.tmp"
    $backup = "$settings.setup-ai.bak"
    try {
        [System.IO.File]::WriteAllText($tmp, $updated, $utf8)
        $null = [System.IO.File]::ReadAllText($tmp, $utf8) | ConvertFrom-Json
        [System.IO.File]::Replace($tmp, $settings, $backup)
    } catch {
        Write-Log ERROR "gentle-ai" "rpiv_question_conflict_unrepaired" "Could not remove the stale rpiv ask_user_question extension from ${settings}: $($_.Exception.Message)" 1 "settings=$settings;package=npm:@juicesharp/rpiv-ask-user-question"
        throw "Could not repair the stale rpiv ask_user_question extension in $settings"
    } finally {
        foreach ($stale in @($tmp, $backup)) {
            if (Test-Path -LiteralPath $stale) {
                try { Remove-Item -LiteralPath $stale -Force -ErrorAction Stop }
                catch { Write-Log WARN "gentle-ai" "quiet_tools_temp_left" "Could not remove a temporary file next to settings.json" 0 "path=$stale" }
            }
        }
    }
    Write-Log INFO "gentle-ai" "rpiv_question_extension_removed" "Removed the obsolete rpiv ask_user_question extension because gentle-pi now provides the same tool" 0 "settings=$settings;package=npm:@juicesharp/rpiv-ask-user-question"
}

# gentle-pi's quiet-tools re-registers the built-in read/edit/grep/... tools, and pi
# aborts at startup ("Tool <name> conflicts") when a second installed extension
# registers one of the same names. pi-tool-display does exactly that, and so does the
# dropped pi-hashline-edit-pro still registered on machines upgraded from an older
# install. Newer gentle-pi releases also own ask_user_question, so remove the
# obsolete standalone rpiv extension when it is still registered beside it.
# gentle-pi has no per-registrant switch, so the repair is its object entry
# in settings.json with both of its own registrants excluded. Loading extensions
# without a model call is impossible, so the collision is detected statically and the
# entry rewritten as raw text, which leaves the rest of the file's formatting
# untouched.
function Repair-QuietToolsConflict {
    Remove-StaleQuietToolsSwitch

    $settings = Join-Path $PiAgentDir "settings.json"
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) { return }
    Remove-StaleRpivQuestionExtension

    # Read the bytes explicitly, so the text can be written back with the same
    # encoding: UTF-8, with a byte-order mark only when the file already has one.
    $bytes = [System.IO.File]::ReadAllBytes($settings)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $utf8 = New-Object System.Text.UTF8Encoding($hasBom)
    $offset = 0
    if ($hasBom) { $offset = 3 }
    $raw = $utf8.GetString($bytes, $offset, $bytes.Length - $offset)

    # One alternation, both identities: pi-tool-display registers read/bash/find/
    # grep/ls, pi-hashline-edit-pro was that name's owner before it was dropped.
    $shadow = ''
    if ($raw -cmatch '"npm:(pi-tool-display|pi-hashline-edit-pro)(@[^"]*)?"') { $shadow = $Matches[1] }
    if (-not $shadow) { return }

    $remediation = '{"source":"npm:gentle-pi","extensions":["-extensions/quiet-tools.ts","-extensions/pi-pretty.ts"]}'

    # Which edit is safe is a structural question, so parse the JSON for it; the edit
    # itself stays textual to preserve formatting.
    $state = 'invalid'
    try {
        $parsed = ConvertFrom-Json -InputObject $raw
        $gentle = @()
        if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['packages']) {
            foreach ($entry in @($parsed.packages)) {
                if ($null -eq $entry) { continue }
                $isString = $entry -is [string]
                $source = if ($isString) { $entry } elseif ($null -ne $entry.PSObject.Properties['source']) { [string]$entry.source } else { '' }
                if (-not $source) { continue }
                if ((Get-PiPackageIdentity -Spec $source -BaseDir $PiAgentDir) -ine 'npm:gentle-pi') { continue }
                $extensions = if (-not $isString -and $null -ne $entry.PSObject.Properties['extensions']) { @($entry.extensions) } else { @() }
                $gentle += @{ Kind = $(if ($isString) { 'string' } else { 'object' }); Extensions = $extensions }
            }
        }
        $exclusions = @('-extensions/quiet-tools.ts', '-extensions/pi-pretty.ts')
        if ($gentle.Count -eq 0) { $state = 'absent' }
        elseif ($gentle.Count -gt 1) { $state = 'ambiguous' }
        elseif ($gentle[0].Kind -eq 'string') { $state = 'string' }
        elseif (@($exclusions | Where-Object { $gentle[0].Extensions -notcontains $_ }).Count -eq 0) { $state = 'guarded' }
        else { $state = 'ambiguous' }
    } catch {
        $state = 'invalid'
    }
    if ($state -eq 'absent' -or $state -eq 'guarded') { return }
    if ($state -ne 'string') {
        # Never claim a repair we did not make: an entry that cannot be rewritten
        # safely (duplicate, unparseable or compact JSON) is reported with the exact
        # JSON the user has to put in its place.
        Write-Log WARN "gentle-ai" "quiet_tools_conflict_unrepaired" "$shadow re-registers a built-in tool name, so pi aborts at startup until gentle-pi excludes its own registrants; replace the gentle-pi entry in $settings with the JSON below" 0 "expected=$remediation;settings=$settings"
        return
    }

    # The single plain entry is the only text that changes; indentation, trailing
    # comma and line ending follow the original line. The replacement is staged as a
    # sibling of its target, so the final Replace is atomic and a failed write can
    # never leave an unusable settings.json behind.
    $entryMatch = [regex]::Matches($raw, '(?m)^([ \t]*)"npm:gentle-pi"([ \t]*)(,?)[ \t]*(\r?)$')
    if ($entryMatch.Count -ne 1) {
        Write-Log WARN "gentle-ai" "quiet_tools_conflict_unrepaired" "$shadow re-registers a built-in tool name, so pi aborts at startup until gentle-pi excludes its own registrants; $settings is unchanged, replace the gentle-pi entry with the JSON below" 0 "expected=$remediation;settings=$settings"
        return
    }
    $indent = $entryMatch[0].Groups[1].Value
    $comma = $entryMatch[0].Groups[3].Value
    $lineEnding = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = @(
        "$indent{"
        "$indent  `"source`": `"npm:gentle-pi`","
        "$indent  `"extensions`": ["
        "$indent    `"-extensions/quiet-tools.ts`","
        "$indent    `"-extensions/pi-pretty.ts`""
        "$indent  ]"
        "$indent}$comma"
    ) -join $lineEnding
    $block += $entryMatch[0].Groups[4].Value
    $updated = $raw.Remove($entryMatch[0].Index, $entryMatch[0].Length).Insert($entryMatch[0].Index, $block)

    $tmp = "$settings.setup-ai.tmp"
    $backup = "$settings.setup-ai.bak"
    try {
        [System.IO.File]::WriteAllText($tmp, $updated, $utf8)
        # Verify the staged file before it replaces anything.
        $null = [System.IO.File]::ReadAllText($tmp, $utf8) | ConvertFrom-Json
        # The atomic swap on Windows, which also keeps the destination's attributes;
        # the backup it writes is removed below.
        [System.IO.File]::Replace($tmp, $settings, $backup)
    } catch {
        Write-Log ERROR "gentle-ai" "quiet_tools_conflict_unrepaired" "Could not replace $settings with the repaired copy: $($_.Exception.Message); pi keeps aborting at startup until gentle-pi excludes -extensions/quiet-tools.ts and -extensions/pi-pretty.ts" 1 "settings=$settings"
        throw "Could not repair the gentle-pi entry in $settings"
    } finally {
        foreach ($stale in @($tmp, $backup)) {
            if (Test-Path -LiteralPath $stale) {
                try {
                    Remove-Item -LiteralPath $stale -Force -ErrorAction Stop
                } catch {
                    Write-Log WARN "gentle-ai" "quiet_tools_temp_left" "Could not remove a temporary file next to settings.json" 0 "path=$stale"
                }
            }
        }
    }
    Write-Log INFO "gentle-ai" "quiet_tools_conflict_repaired" "$shadow re-registers one of the built-in tool names gentle-pi's quiet tools own; repair applied with -extensions/quiet-tools.ts and -extensions/pi-pretty.ts excluded" 0 "settings=$settings"
}

# Verify the real pi startup path after the quiet-tools repair. PI_OFFLINE=1 and
# the job's non-interactive stdin load extensions without a model call or network;
# measured on pi 0.85.1 with pi-tool-display 0.5.0 and gentle-pi 3.2.1, the
# conflicting settings exit 1 and the repaired settings exit 0 in about 12 seconds.
function Test-PiStartup {
    $piCommand = @(Get-Command -Name pi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($piCommand.Count -eq 0) {
        Write-Log INFO "gentle-ai" "pi_startup_skipped" "pi is not on PATH; startup verification skipped"
        return
    }
    $piPath = [string]$piCommand[0].Path

    $timeoutText = if ($env:PI_STARTUP_TIMEOUT) { $env:PI_STARTUP_TIMEOUT } else { '120' }
    [int]$timeoutSeconds = 0
    if (-not [int]::TryParse($timeoutText, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$timeoutSeconds) -or $timeoutSeconds -le 0) {
        Write-Log ERROR "gentle-ai" "pi_startup_failed" "PI_STARTUP_TIMEOUT must be a positive integer" 1 "timeout=$timeoutText;settings=$(Join-Path $PiAgentDir 'settings.json')"
        throw "PI_STARTUP_TIMEOUT must be a positive integer"
    }

    $settings = Join-Path $PiAgentDir "settings.json"
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) "setup-ai-pi-startup-$PID-$([guid]::NewGuid().ToString('N')).log"
    $job = $null
    $lines = @()
    $returnCode = 1
    try {
        # Start-Job gives pi a non-interactive worker, but Windows cannot guarantee
        # that Stop-Job kills native children pi spawned after the timeout.
        $job = Start-Job -ArgumentList $piPath -ScriptBlock {
            param([string]$PiPath)
            $ErrorActionPreference = 'Continue'
            $PSNativeCommandUseErrorActionPreference = $false
            $env:PI_OFFLINE = '1'
            try {
                $captured = @(& $PiPath 2>&1 | ForEach-Object { [string]$_ })
            } catch {
                return [pscustomobject]@{
                    Kind = 'pi-startup-result'
                    ExitCode = 127
                    Lines = @("pi startup launch failed: $($_.Exception.Message)")
                }
            }
            $nativeExitCode = $LASTEXITCODE
            if ($null -eq $nativeExitCode -or $nativeExitCode -isnot [int]) {
                $captured += 'pi startup returned no known exit status'
                $code = 127
            } else {
                $code = [int]$nativeExitCode
            }
            [pscustomobject]@{ Kind = 'pi-startup-result'; ExitCode = $code; Lines = $captured }
        }
        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds
        if ($null -eq $completed) {
            $null = Stop-Job -Job $job -ErrorAction SilentlyContinue
            $returnCode = 124
            $lines = @("pi startup verification timed out after $timeoutSeconds seconds")
        } else {
            $received = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            $result = @($received | Where-Object { $_.Kind -eq 'pi-startup-result' } | Select-Object -First 1)
            if ($result.Count -eq 0) {
                $lines = @('pi startup job returned no result')
                $returnCode = 1
            } else {
                $lines = @($result[0].Lines | ForEach-Object { [string]$_ })
                $returnCode = [int]$result[0].ExitCode
            }
        }
    } finally {
        if ($null -ne $job) {
            if ($job.State -eq 'Running') { $null = Stop-Job -Job $job -ErrorAction SilentlyContinue }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    [System.IO.File]::WriteAllLines($logPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    $firstError = @($lines | Where-Object { $_ -match 'Error:|conflicts' } | Select-Object -First 1)
    $diagnostic = if ($firstError.Count -gt 0) { [string]$firstError[0] } else { 'none' }
    if ($returnCode -eq 0) {
        Write-Log INFO "gentle-ai" "pi_startup_verified" "pi startup verified after the gentle-pi repair" 0 "log=$logPath;settings=$settings"
        return
    }
    Write-Log ERROR "gentle-ai" "pi_startup_failed" "pi startup verification failed" $returnCode "diagnostic=$diagnostic;log=$logPath;settings=$settings"
    throw "pi startup verification failed (return code $returnCode; first error line: $diagnostic; log: $logPath)"
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

    # Repair the harmful quiet-tools switch and the pi settings entry BEFORE anything
    # that can fail: the repair needs nothing from the installer (it only removes the
    # exact shell-profile lines this installer writes and edits settings.json), while a
    # failed `gentle-ai install` used to skip it and leave the switch behind, making a
    # failed run permanently worse than a run that never happened (issue #61).
    Repair-QuietToolsConflict

    # The per-agent selector and the pi harness both require the gentle-ai CLI
    # itself; a legacy standalone gga is NOT enough, so install whenever the
    # gentle-ai CLI is missing even if an old gga is on PATH.
    Resolve-GentleAiCli
    if (-not (Test-Cmd gentle-ai)) {
        # Vendor's official Windows method (installs to %LOCALAPPDATA%\gentle-ai\bin).
        Invoke-RemoteScript -Url "https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.ps1" -Phase "gentle-ai"
        Update-SessionPath
    }

    Resolve-GentleAiCli
    if (-not (Test-Cmd gentle-ai)) {
        Write-Log ERROR "gentle-ai" "install_missing" "gentle-ai CLI not found on PATH after remote installer"
        throw "gentle-ai CLI not found on PATH after remote installer"
    }
    Invoke-Step -Phase "gentle-ai" -Verify -Action { & gentle-ai --version }

    # The configurator downloads the engram binary through the GitHub API. Unauthenticated
    # that is the same 60-requests-per-hour-per-IP quota that already broke this ecosystem
    # twice (issue #60: "download engram binary: fetch latest engram version: GitHub API
    # returned HTTP 403"). The binary reads GITHUB_TOKEN/GH_TOKEN, so pass whichever token
    # this machine has; without one the call stays unauthenticated and the upstream error
    # is reported as before.
    $ghToken = Get-GitHubToken
    if ($ghToken) {
        $env:GITHUB_TOKEN = $ghToken
        $env:GH_TOKEN = $ghToken
        Write-Log INFO "gentle-ai" "github_token_forwarded" "Forwarding a GitHub token to the gentle-ai configurator for its API calls"
    } else {
        Write-Log INFO "gentle-ai" "github_token_absent" "No GitHub token available; the configurator's GitHub API calls stay unauthenticated"
    }

    # Detect the agents/IDEs present on this machine (same mapping as Mod-Ee).
    $detectedAgents = Get-TargetSkillAgents

    # Per-agent / per-IDE selection + MCP wiring, owned by gentle-ai. This is a
    # core step and must actually run: with a real console we launch the
    # interactive selector (run directly - Invoke-Step pipes output and would
    # hide the prompts); otherwise we run it non-interactively over the detected
    # agents so CI/pipes never hang. A failure fails the module.
    $configuratorInteractive = (-not $Yes -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
    $agentsCsv = ($detectedAgents -join ',')
    $configuratorOutput = Join-Path ([IO.Path]::GetTempPath()) ("setup-ai-gentle-ai-" + [guid]::NewGuid().ToString('N') + ".log")
    $configuratorRetryDelays = @(15, 45)
    $configuratorRetryAttempt = 0
    $configuratorRateLimitExhausted = $false
    $configuratorQuotaConfirmed = $false
    $configuratorInterrupted = $false
    $configuratorRc = 0
    $configuratorStepsFailed = $script:StepsFailed
    $configuratorStepFailStep = $script:StepFailStep
    $configuratorStepFailReturnCode = $script:StepFailReturnCode
    $configuratorLastErrorStep = $script:LastErrorStep
    $configuratorLastErrorReturnCode = $script:LastErrorReturnCode
    $configuratorRetrySleepFailed = $false
    # Start-Sleep throws without exposing a native exit code; keep this fallback in sync with setup-ai.sh.
    $configuratorRetrySleepFallbackReturnCode = 1
    $configuratorRetrySleepReturnCode = 0
    if ($configuratorInteractive) {
        Write-Log INFO "gentle-ai" "configurator_start" "Launching gentle-ai install (choose agents/IDEs + MCP)"
    } else {
        Write-Log INFO "gentle-ai" "configurator_noninteractive" "No console; installing gentle-ai for detected agents" 0 "agents=$agentsCsv"
    }
    try {
        while ($true) {
            $configuratorRc = 0
            $configuratorSignature = ''
            if ($configuratorInteractive) {
                # The selector must see the real console; capturing it would hide or buffer its prompts.
                try {
                    & gentle-ai install --scope global
                    $configuratorRc = $LASTEXITCODE
                } catch {
                    $configuratorRc = if ($LASTEXITCODE) { [int]$LASTEXITCODE } else { 1 }
                }
                $configuratorSignature = 'interactive selector failure (output not captured)'
            } else {
                try {
                    Invoke-Step -Phase "gentle-ai" -CaptureOutput $configuratorOutput -Action { & gentle-ai install --scope global --agents $agentsCsv }
                } catch {
                    $nativeExitCode = $global:LASTEXITCODE
                    $configuratorRc = if ($null -ne $nativeExitCode -and [int]$nativeExitCode -ne 0) { [int]$nativeExitCode } else { 1 }
                }
                if ($configuratorRc -ne 0 -and (Test-Path -LiteralPath $configuratorOutput)) {
                    $configuratorOutputText = Get-Content -Raw -LiteralPath $configuratorOutput
                    if ($configuratorOutputText -match '(?i)(HTTP 403.*GitHub API|GitHub API.*HTTP 403)') {
                        $configuratorSignature = 'HTTP 403 + GitHub API download path'
                        $configuratorQuotaConfirmed = $true
                    }
                }
            }

            if ($configuratorRc -eq 0) {
                if ($configuratorRetryAttempt -gt 0) {
                    $script:StepsFailed = $configuratorStepsFailed
                    $script:StepFailStep = $configuratorStepFailStep
                    $script:StepFailReturnCode = $configuratorStepFailReturnCode
                    $script:LastErrorStep = $configuratorLastErrorStep
                    $script:LastErrorReturnCode = $configuratorLastErrorReturnCode
                    Write-Log INFO "gentle-ai" "configurator_recovered" "gentle-ai configurator recovered after retry" 0 "attempts=$configuratorRetryAttempt"
                }
                break
            }
            if ($configuratorRc -eq 130 -or $configuratorRc -eq 143) {
                $configuratorInterrupted = $true
                Write-Log INFO "gentle-ai" "configurator_retry_skipped" "No retry attempted because the gentle-ai configurator run was interrupted" $configuratorRc "return_code=$configuratorRc;reason=$configuratorSignature"
                break
            }
            if (-not $configuratorSignature) { break }
            if ($configuratorRetryAttempt -ge $configuratorRetryDelays.Count) {
                $configuratorRateLimitExhausted = $true
                break
            }
            $configuratorRetryAttempt++
            $configuratorBackoff = $configuratorRetryDelays[$configuratorRetryAttempt - 1]
            $configuratorRetryMessage = if ($configuratorQuotaConfirmed) {
                "Retrying gentle-ai configurator after confirmed rate-limit signature"
            } else {
                "Retrying gentle-ai configurator after observed selector failure"
            }
            Write-Log INFO "gentle-ai" "configurator_retry" "$configuratorRetryMessage (attempt $configuratorRetryAttempt/2; waiting ${configuratorBackoff}s)" 0 "attempt=$configuratorRetryAttempt;reason=$configuratorSignature;backoff_seconds=$configuratorBackoff"
            try {
                Start-Sleep -Seconds $configuratorBackoff
            } catch {
                $configuratorRetrySleepFailed = $true
                $configuratorRetrySleepReturnCode = $configuratorRetrySleepFallbackReturnCode
                Write-Log ERROR "gentle-ai" "configurator_retry_sleep_failed" "Could not wait before retrying the gentle-ai configurator" $configuratorRetrySleepReturnCode "attempt=$configuratorRetryAttempt;backoff_seconds=$configuratorBackoff;observed_return_code=$configuratorRc"
                break
            }
        }
    } finally {
        if (Test-Path -LiteralPath $configuratorOutput) {
            try {
                Remove-Item -LiteralPath $configuratorOutput -Force -ErrorAction Stop
            } catch {
                Write-Log WARN "gentle-ai" "configurator_output_cleanup_failed" "Could not remove the configurator output capture" 0 "path=$configuratorOutput;error=$($_.Exception.Message)"
            }
        }
    }
    if ($configuratorRc -ne 0) {
        if ($configuratorRetrySleepFailed) {
            $configuratorFailure = "gentle-ai install failed: retry backoff sleep failed (fallback return code=$configuratorRetrySleepReturnCode); configurator selector return code=$configuratorRc"
        } elseif ($configuratorInterrupted) {
            $configuratorFailure = "gentle-ai install interrupted (rc=$configuratorRc); no retry was attempted because the run was interrupted"
        } elseif ($configuratorRateLimitExhausted -and $configuratorQuotaConfirmed) {
            $configuratorFailure = "gentle-ai install failed: anonymous GitHub API quota exhausted; remedies: run 'gh auth login', or export GITHUB_TOKEN/GH_TOKEN"
        } elseif ($configuratorInteractive) {
            $configuratorFailure = "gentle-ai install failed: the interactive gentle-ai selector exited non-zero (rc=$configuratorRc) and its output was not captured because the selector owns the TTY"
        } else {
            $configuratorFailure = "gentle-ai install failed: the non-interactive gentle-ai configurator exited non-zero (rc=$configuratorRc); no HTTP 403 + GitHub API signature was observed in captured output"
        }
        Write-Log ERROR "gentle-ai" "configurator_failed" $configuratorFailure $configuratorRc
        throw $configuratorFailure
    }
    Write-Log INFO "gentle-ai" "configurator_done" "gentle-ai install completed"

    # Guarantee pi reads gentle-ai in its MCP list (/mcp): install the first-class
    # gentle-pi harness + pi-mcp-adapter, then verify the exact target file.
    if (Test-Cmd pi) {
        Install-PiPackageOwned -Phase "gentle-ai" -Spec 'npm:gentle-pi'
        # Ensure the project marker exists even for -Only gentle-ai before the
        # npm 12 approval/rebuild check (issue #49).
        Enable-NpmRemoteSources -Dir $PiNpmDir
        # Approve/rebuild gentle-pi's blocked npm 12 install scripts now, in the
        # managed Pi root, so its package-local RDD review binary exists even if a
        # later module fails before the final convergence pass runs.
        Approve-NpmInstallScripts -Dir $PiNpmDir -Phase "gentle-ai"
        Install-PiPackageOwned -Phase "gentle-ai" -Spec 'npm:pi-mcp-adapter'
        $piSettings = Join-Path $PiAgentDir "settings.json"
        try {
            Assert-PiPackageRegistered -Phase 'gentle-ai' -Spec 'npm:gentle-pi'
            Assert-PiPackageRegistered -Phase 'gentle-ai' -Spec 'npm:pi-mcp-adapter'
            Write-Log INFO "gentle-ai" "pi_enabled" "gentle-pi + pi-mcp-adapter registered in pi (verify: /mcp, /gentle-ai:status)"
        } catch {
            Write-Log ERROR "gentle-ai" "pi_enable_failed" "gentle-pi and/or pi-mcp-adapter not present exactly once in pi settings after install ($piSettings)"
            throw
        }
    }

    Repair-QuietToolsConflict
    Test-PiStartup

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
    # The vendor installer reads CODEX_NON_INTERACTIVE and skips its "Start Codex
    # now?" prompt; without it an unattended run waits on stdin.
    $previousCodexNonInteractive = $env:CODEX_NON_INTERACTIVE
    $env:CODEX_NON_INTERACTIVE = "1"
    try {
        Invoke-RemoteScript -Url "https://chatgpt.com/codex/install.ps1" -Phase "codex"
    } finally {
        $env:CODEX_NON_INTERACTIVE = $previousCodexNonInteractive
    }
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

function Get-OpenCodeUserEnvironmentValue {
    param([string]$Name)
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-OpenCodeUserEnvironmentValue {
    param([string]$Name, [AllowNull()][string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Get-OpenCodeEnvReceiptPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $null }
    return Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'setup-ai') 'ownership') 'opencode-pi-bin.json'
}

function Test-OpenCodeEnvReceiptLocation {
    $root = $env:LOCALAPPDATA; $path = Get-OpenCodeEnvReceiptPath
    if (-not $root -or -not $path) { return $false }
    $expected = Join-Path (Join-Path (Join-Path $root 'setup-ai') 'ownership') 'opencode-pi-bin.json'
    try {
        if (-not [string]::Equals([System.IO.Path]::GetFullPath($path), [System.IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $paths = @($root, (Join-Path $root 'setup-ai'), (Join-Path (Join-Path $root 'setup-ai') 'ownership'), $path)
        for ($i = 0; $i -lt $paths.Count; $i++) {
            if (-not (Test-Path -LiteralPath $paths[$i])) { continue }
            $item = Get-Item -LiteralPath $paths[$i] -Force -ErrorAction Stop
            if (($i -lt 3) -ne [bool]$item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-OpenCodeEnvReceiptState {
    $path = Get-OpenCodeEnvReceiptPath
    if (-not $path -or -not (Test-OpenCodeEnvReceiptLocation)) { return [pscustomobject]@{ Safe = $false; Exists = $false; Valid = $false; Receipt = $null } }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Safe = $true; Exists = $false; Valid = $false; Receipt = $null } }
    try {
        $receipt = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $valid = $receipt -is [pscustomobject] -and $receipt.SchemaVersion -eq 1 -and
            $receipt.Scope -ceq 'User' -and $receipt.Name -ceq 'OPENCODE_PI_BIN' -and
            $receipt.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($receipt.Value)
        return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = [bool]$valid; Receipt = $(if ($valid) { $receipt } else { $null }) }
    } catch { return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = $false; Receipt = $null } }
}

function Write-OpenCodeEnvReceipt {
    param([string]$Value)
    $path = Get-OpenCodeEnvReceiptPath
    if (-not $path -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
    $state = Get-OpenCodeEnvReceiptState
    if (-not $state.Safe -or $state.Exists) { return $false }
    $stream = $null
    try {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        if (-not (Test-OpenCodeEnvReceiptLocation)) { return $false }
        $json = [pscustomobject]@{ SchemaVersion = 1; Scope = 'User'; Name = 'OPENCODE_PI_BIN'; Value = $Value } | ConvertTo-Json -Compress
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true)
        $stream.Dispose(); $stream = $null
        $state = Get-OpenCodeEnvReceiptState
        return $state.Valid -and $state.Receipt.Value -ceq $Value
    } catch { return $false } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-OpenCodeEnvInventoryStatus {
    $state = Get-OpenCodeEnvReceiptState
    if (-not $state.Safe) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; OpenCode environment receipt path is unsafe.' } }
    if (-not $state.Exists) { return [pscustomobject]@{ State = 'absent'; Message = 'absent.' } }
    if (-not $state.Valid) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; OpenCode environment receipt is missing or invalid.' } }
    $current = Get-OpenCodeUserEnvironmentValue -Name $state.Receipt.Name
    if ($current -ceq $state.Receipt.Value) { return [pscustomobject]@{ State = 'receipt-backed'; Message = 'receipt-backed User environment value; removable with -Yes.' } }
    if ($null -eq $current) { return [pscustomobject]@{ State = 'protected'; Message = 'protected; receipt-backed User environment value is already absent.' } }
    return [pscustomobject]@{ State = 'protected'; Message = 'protected; User environment value changed after setup-ai recorded it.' }
}

function Remove-OpenCodeUserEnvironment {
    param([switch]$Confirmed, [switch]$DryRun)
    if (-not $Confirmed -or $DryRun) { return $false }
    $path = Get-OpenCodeEnvReceiptPath
    if (-not $path) { $script:OpenCodeEnvRemovalFailed = $true; return $false }
    try { $receiptBefore = [System.IO.File]::ReadAllText($path) } catch { $script:OpenCodeEnvRemovalFailed = $true; return $false }
    $state = Get-OpenCodeEnvReceiptState
    if (-not $state.Safe -or -not $state.Valid) { $script:OpenCodeEnvRemovalFailed = $true; return $false }
    $value = $state.Receipt.Value
    if ((Get-OpenCodeUserEnvironmentValue -Name $state.Receipt.Name) -cne $value) { return $false }
    try {
        if ([System.IO.File]::ReadAllText($path) -cne $receiptBefore) { return $false }
        Set-OpenCodeUserEnvironmentValue -Name $state.Receipt.Name -Value $null
        if ($null -ne (Get-OpenCodeUserEnvironmentValue -Name $state.Receipt.Name)) { throw 'User environment readback still contains OPENCODE_PI_BIN.' }
        if ([System.IO.File]::ReadAllText($path) -cne $receiptBefore) { throw 'receipt changed' }
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $path) { throw 'receipt still exists' }
        return $true
    } catch {
        $script:OpenCodeEnvRemovalFailed = $true
        try { Set-OpenCodeUserEnvironmentValue -Name $state.Receipt.Name -Value $value }
        catch { Write-Host "  ERROR: Could not restore User OPENCODE_PI_BIN after a failed removal: $($_.Exception.Message)" }
        return $false
    }
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
    $userValueBefore = Get-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN'
    Set-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN' -Value $native
    if ((Get-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN') -cne $native) {
        throw 'OPENCODE_PI_BIN User environment readback did not match the native launcher.'
    }
    $env:OPENCODE_PI_BIN = $native
    if ($null -eq $userValueBefore) {
        $receiptState = Get-OpenCodeEnvReceiptState
        if ($receiptState.Valid -and $receiptState.Receipt.Value -ceq $native) {
            Write-Log INFO "opencode" "ownership_receipt_preserved" "Preserved the existing setup-ai OpenCode environment ownership receipt" 0 "bin=$native"
        } elseif (Write-OpenCodeEnvReceipt -Value $native) {
            Write-Log INFO "opencode" "ownership_receipt_written" "Recorded fresh ownership of the User OPENCODE_PI_BIN value" 0 "bin=$native"
        } else {
            Write-Log WARN "opencode" "ownership_receipt_skipped" "Could not record ownership of OPENCODE_PI_BIN; the User environment value remains protected" 0 "bin=$native"
        }
    }
    Write-Log INFO "opencode" "pi_bin_set" "OPENCODE_PI_BIN points opencode-pi at the native launcher" 0 "bin=$native"
}

function Mod-Opencode {
    Write-Log INFO "opencode" "start" "opencode"
    # opencode-ai ships a 479-byte stub at bin/opencode.exe and its postinstall is what
    # installs the real launcher. npm 12 blocks that script, and the stub then prints
    # "opencode-ai's postinstall script was not run" and exits 1, so installing without
    # the approval would report success for a CLI that never works. `npm
    # install-scripts approve` cannot be used here: it refuses global installs (the
    # policy lives in a project package.json), while --allow-scripts is the form npm
    # itself documents for `npm install -g`.
    # npm stays required for the install and the repair only: an opencode that another
    # package manager already installed needs neither, and the check below is what proves it.
    $npmAvailable = Test-Cmd npm
    $allowScripts = @()
    if ($npmAvailable -and (Test-NpmInstallScriptsSupport -Phase "opencode")) { $allowScripts = @('--allow-scripts=opencode-ai') }
    if (Test-Cmd opencode) {
        Write-Log INFO "opencode" "already_present" "opencode already installed"
    } else {
        if (-not $npmAvailable) {
            throw "npm not found; opencode cannot be installed"
        }
        Invoke-Step -Phase "opencode" -Action { npm install -g opencode-ai @allowScripts }
        # npm writes the shim into the user PATH; refresh this session so the
        # verification below sees it without a new shell (parity with setup-ai.sh).
        Update-SessionPath
        if (-not (Test-Cmd opencode)) {
            Write-Log ERROR "opencode" "install_missing" "opencode not found on PATH after npm install"
            throw "opencode not found on PATH after npm install"
        }
    }
    # Repair an install the blocked postinstall left on the stub: reinstalling does not
    # re-run it (npm treats the package as already installed), which is why an earlier
    # run's broken opencode would otherwise stay broken. Optional because an opencode
    # that comes from another package manager has nothing to rebuild; the CLI check below
    # is the gate that decides.
    if ($npmAvailable) {
        $null = Invoke-Step -Phase "opencode" -Optional -Action { npm rebuild -g opencode-ai @allowScripts --foreground-scripts }
    }
    # The stub exits 1 with its own message, so the exit code of the CLI - not the
    # existence of the shim - is what proves the real launcher is installed.
    $null = Invoke-Step -Phase "opencode" -Verify -Action { opencode --version }
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
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/jlcodes99/cockpit-tools/releases/latest" -Headers (Get-GitHubApiHeaders)
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

function Get-RotatorTaskFingerprint {
    param($Task)
    try {
        $get = { param($Object, $Name) if ($null -eq $Object) { return $null }; $property = $Object.PSObject.Properties[$Name]; if ($property) { $property.Value } }
        $taskName = [string](& $get $Task 'TaskName')
        $taskPath = [string](& $get $Task 'TaskPath')
        $description = [string](& $get $Task 'Description')
        $markerMatch = [regex]::Match($description, '\[setup-ai-rotator-owner:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\]$')
        $markerCount = [regex]::Matches($description, '\[setup-ai-rotator-owner:[^\]]+\]').Count
        $markerGuid = [Guid]::Empty
        if ($taskName -cne 'tuxevil-rotator' -or $taskPath -cne '\' -or
            -not $description.StartsWith('tuxevil-rotator multi-account Gemini/Antigravity gateway on http://localhost:51200 [setup-ai-rotator-owner:', [StringComparison]::Ordinal) -or
            -not $markerMatch.Success -or $markerCount -ne 1 -or
            -not [Guid]::TryParseExact($markerMatch.Groups[1].Value, 'D', [ref]$markerGuid)) { return '' }

        $actions = @(& $get $Task 'Actions')
        $rawTriggers = @(& $get $Task 'Triggers')
        $settings = & $get $Task 'Settings'
        $principal = & $get $Task 'Principal'
        $actionFingerprint = @($actions | ForEach-Object {
            [ordered]@{ Execute = & $get $_ 'Execute'; Arguments = & $get $_ 'Arguments'; WorkingDirectory = & $get $_ 'WorkingDirectory' }
        })
        $triggerFingerprint = @($rawTriggers | ForEach-Object {
            $repetition = & $get $_ 'Repetition'
            $cimClass = & $get $_ 'CimClass'
            [ordered]@{
                Type = & $get $cimClass 'CimClassName'; Enabled = & $get $_ 'Enabled'; UserId = & $get $_ 'UserId'
                StartBoundary = & $get $_ 'StartBoundary'; EndBoundary = & $get $_ 'EndBoundary'
                RepetitionInterval = & $get $repetition 'Interval'; RepetitionDuration = & $get $repetition 'Duration'
                RepetitionStopAtDurationEnd = & $get $repetition 'StopAtDurationEnd'
            }
        })
        $settingsFingerprint = [ordered]@{}
        foreach ($name in @('Enabled', 'MultipleInstances', 'ExecutionTimeLimit', 'AllowStartIfOnBatteries', 'DontStopIfGoingOnBatteries', 'StartWhenAvailable', 'WakeToRun', 'DisallowStartIfOnBatteries', 'RunOnlyIfIdle', 'RunOnlyIfNetworkAvailable', 'AllowDemandStart', 'AllowHardTerminate', 'StopIfGoingOnBatteries', 'Priority', 'Hidden', 'RestartCount', 'RestartInterval', 'DeleteExpiredTaskAfter', 'UseUnifiedSchedulingEngine', 'Compatibility', 'Volatile', 'DisallowStartOnRemoteAppSession')) {
            $settingsFingerprint[$name] = & $get $settings $name
        }
        $principalFingerprint = [ordered]@{
            UserId = & $get $principal 'UserId'; GroupId = & $get $principal 'GroupId'
            LogonType = & $get $principal 'LogonType'; RunLevel = & $get $principal 'RunLevel'
            ProcessTokenSidType = & $get $principal 'ProcessTokenSidType'; RequiredPrivileges = & $get $principal 'RequiredPrivileges'
        }
        $fingerprint = [ordered]@{
            TaskName = $taskName; TaskPath = $taskPath; Marker = $markerMatch.Groups[1].Value
            Description = $description; Actions = $actionFingerprint; Triggers = $triggerFingerprint
            Principal = $principalFingerprint; Settings = $settingsFingerprint
        }
        return ConvertTo-Json -InputObject $fingerprint -Compress -Depth 10
    } catch { return '' }
}

function Test-RotatorTaskOwnership {
    param($Task, $Receipt)
    try {
        if ($null -eq $Receipt -or $Receipt.SchemaVersion -ne 1 -or
            $Receipt.TaskName -cne 'tuxevil-rotator' -or $Receipt.TaskPath -cne '\' -or
            [string]::IsNullOrWhiteSpace([string]$Receipt.Fingerprint)) { return $false }
        $markerGuid = [Guid]::Empty
        if (-not [Guid]::TryParseExact([string]$Receipt.Marker, 'D', [ref]$markerGuid)) { return $false }
        $description = [string]$Task.Description
        if (-not $description.EndsWith("[setup-ai-rotator-owner:$($Receipt.Marker)]", [StringComparison]::Ordinal)) { return $false }
        $fingerprint = Get-RotatorTaskFingerprint -Task $Task
        return [bool]$fingerprint -and $fingerprint -ceq [string]$Receipt.Fingerprint
    } catch { return $false }
}

function Test-RotatorReceiptPathSafe {
    param([string]$LocalAppData, [string]$ReceiptPath, [object[]]$Attributes)
    try {
        if ([string]::IsNullOrWhiteSpace($LocalAppData) -or [string]::IsNullOrWhiteSpace($ReceiptPath) -or $Attributes.Count -ne 4) { return $false }
        $expected = Join-Path (Join-Path (Join-Path $LocalAppData 'setup-ai') 'ownership') 'rotator-task.json'
        if (-not [string]::Equals([System.IO.Path]::GetFullPath($expected), [System.IO.Path]::GetFullPath($ReceiptPath), [StringComparison]::OrdinalIgnoreCase)) { return $false }
        foreach ($attribute in $Attributes) { if ($null -ne $attribute -and $attribute -ne -1 -and ([System.IO.FileAttributes]$attribute -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false } }
        return $true
    } catch { return $false }
}

function Get-RotatorTaskReceiptPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $null }
    return Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'setup-ai') 'ownership') 'rotator-task.json'
}

function Test-RotatorReceiptLocation {
    $root = $env:LOCALAPPDATA; $path = Get-RotatorTaskReceiptPath
    if (-not $path) { return $false }
    $paths = @($root, (Join-Path $root 'setup-ai'), (Join-Path (Join-Path $root 'setup-ai') 'ownership'), $path); $attributes = @(-1, -1, -1, -1)
    try {
        for ($i = 0; $i -lt 4; $i++) {
            if (-not (Test-Path -LiteralPath $paths[$i])) { continue }
            $item = Get-Item -LiteralPath $paths[$i] -Force -ErrorAction Stop
            if (($i -lt 3) -ne [bool]$item.PSIsContainer) { return $false }; $attributes[$i] = $item.Attributes
        }
        return Test-RotatorReceiptPathSafe -LocalAppData $root -ReceiptPath $path -Attributes $attributes
    } catch { return $false }
}

function Get-RotatorTaskReceiptState {
    $path = Get-RotatorTaskReceiptPath
    if (-not $path -or -not (Test-RotatorReceiptLocation)) { return [pscustomobject]@{ Safe = $false; Exists = $false; Valid = $false; Receipt = $null } }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Safe = $true; Exists = $false; Valid = $false; Receipt = $null } }
    try {
        $receipt = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop; $guid = [Guid]::Empty
        $valid = $receipt -is [pscustomobject] -and $receipt.SchemaVersion -eq 1 -and $receipt.TaskName -ceq 'tuxevil-rotator' -and $receipt.TaskPath -ceq '\' -and [Guid]::TryParseExact([string]$receipt.Marker, 'D', [ref]$guid) -and -not [string]::IsNullOrWhiteSpace([string]$receipt.Fingerprint)
        return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = [bool]$valid; Receipt = $(if ($valid) { $receipt } else { $null }) }
    } catch { return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = $false; Receipt = $null } }
}

function Write-RotatorTaskReceipt {
    param($Receipt)
    $state = Get-RotatorTaskReceiptState; if (-not $state.Safe -or $state.Exists) { return $false }
    $path = Get-RotatorTaskReceiptPath; $tempPath = "$path.$([Guid]::NewGuid().ToString('N')).tmp"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($Receipt | ConvertTo-Json -Compress -Depth 10)); $stream = $null; $createdTemp = $false
    try {
        if (-not (Test-RotatorReceiptLocation)) { return $false }
        $stream = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $createdTemp = $true
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream = $null
        if (-not (Test-RotatorReceiptLocation)) { return $false }
        [System.IO.File]::Move($tempPath, $path)
        $createdTemp = $false
        return $true
    } catch { return $false } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($createdTemp) { [System.IO.File]::Delete($tempPath) }
    }
}

function Test-RotatorTaskCleanupGuard { param($Task, $Receipt, [bool]$CreatedByCurrentCall) return $CreatedByCurrentCall -and (Test-RotatorTaskOwnership -Task $Task -Receipt $Receipt) }

function Get-RotatorActionArguments {
    param([string]$Executable)
    $shim = $Executable.Replace("'", "''"); $tick = "try { (New-Object Net.Sockets.TcpClient('127.0.0.1', 51200)).Close() } catch { & '$shim' start }"
    return '-NoProfile -WindowStyle Hidden -Command "' + $tick + '"'
}

function Test-RotatorTaskActionCurrent {
    param($Task, [string]$Executable)
    try {
        $actions = @($Task.Actions)
        return $actions.Count -eq 1 -and
            [string]::Equals([string]$actions[0].Execute, 'powershell.exe', [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$actions[0].Arguments, (Get-RotatorActionArguments -Executable $Executable), [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-RotatorTaskQueryState {
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $null -ne $_ -and $_.TaskName -ceq 'tuxevil-rotator' })
        return [pscustomobject]@{ Known = $true; Tasks = $tasks }
    } catch {
        return [pscustomobject]@{ Known = $false; Tasks = @() }
    }
}

function Get-OwnedRotatorTask {
    $receiptState = Get-RotatorTaskReceiptState
    if (-not $receiptState.Safe -or -not $receiptState.Valid) { return $null }
    $taskState = Get-RotatorTaskQueryState
    if (-not $taskState.Known -or $taskState.Tasks.Count -ne 1 -or $taskState.Tasks[0].TaskPath -cne '\') { return $null }
    $task = $taskState.Tasks[0]
    if (Test-RotatorTaskOwnership -Task $task -Receipt $receiptState.Receipt) { return $task }
    return $null
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
    $state = Get-RotatorTaskReceiptState
    if (-not $state.Safe -or ($state.Exists -and -not $state.Valid)) { Write-Log WARN 'rotator' 'receipt_invalid' 'Unsafe or malformed rotator receipt path; preserving the task'; return $false }
    $createdByCall = $false
    $newReceipt = $null
    try {
        $existing = Get-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -ErrorAction SilentlyContinue
        if ($existing) {
            if (-not $state.Valid -or -not (Test-RotatorTaskOwnership -Task $existing -Receipt $state.Receipt)) {
                Write-Log WARN 'rotator' 'task_unowned' 'An existing rotator task is not receipt-owned; preserving it and using a detached process' 0 'task=tuxevil-rotator'
                return $false
            }
            if (Test-RotatorTaskActionCurrent -Task $existing -Executable $binPath) {
                Write-Log INFO 'rotator' 'task_owned' 'Existing setup-ai rotator task is receipt-owned and uses the current executable' 0 'task=tuxevil-rotator'
                return $true
            }
            if (-not (Remove-RotatorOwnedTask)) { return $false }
            $state = Get-RotatorTaskReceiptState
            if (-not $state.Safe -or $state.Exists) { return $false }
        } elseif ($state.Exists) {
            Write-Log WARN 'rotator' 'receipt_stale' 'A receipt exists without its task; preserving the receipt and refusing registration' 0 'task=tuxevil-rotator'
            return $false
        }

        $receiptPath = Get-RotatorTaskReceiptPath
        if (-not (Test-RotatorReceiptLocation)) { return $false }
        New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force | Out-Null
        if (-not (Test-RotatorReceiptLocation)) { return $false }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-RotatorActionArguments -Executable $binPath)
        $atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $watchdogMinutes = 5
        $watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $watchdogMinutes)
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        $principalUser = "$env:USERDOMAIN\$env:USERNAME"
        $principal = New-ScheduledTaskPrincipal -UserId $principalUser -LogonType Interactive -RunLevel Limited
        $marker = [Guid]::NewGuid().ToString('D')
        $description = "tuxevil-rotator multi-account Gemini/Antigravity gateway on http://localhost:51200 [setup-ai-rotator-owner:$marker]"
        # Without -Force, a concurrent task makes fresh registration fail rather than overwrite it.
        $registered = Register-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -Action $action -Trigger @($atLogon, $watchdog) `
            -Settings $taskSettings -Principal $principal -Description $description -PassThru
        $createdByCall = $true
        $newReceipt = [pscustomobject]@{
            SchemaVersion = 1; TaskName = 'tuxevil-rotator'; TaskPath = '\'; Marker = $marker
            Fingerprint = Get-RotatorTaskFingerprint -Task $registered
        }
        if (-not $newReceipt.Fingerprint) { throw 'Could not fingerprint the newly registered task.' }
        $registered = Get-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -ErrorAction Stop
        if (-not (Test-RotatorTaskOwnership -Task $registered -Receipt $newReceipt)) { throw 'Task identity changed before readback validation.' }
        $actions = @($registered.Actions)
        $triggers = @($registered.Triggers)
        $actionOk = $actions.Count -eq 1 -and $actions[0].Execute -eq $action.Execute -and $actions[0].Arguments -eq $action.Arguments
        $logonOk = @($triggers | Where-Object {
            $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $_.Enabled -and ($_.UserId -split '\\')[-1] -eq $env:USERNAME
        }).Count -eq 1
        $toDuration = { param($value) if ($value -is [TimeSpan]) { return [TimeSpan]$value }; $text = ([string]$value).Trim(); if ($text -like 'P*') { return [System.Xml.XmlConvert]::ToTimeSpan($text) }; return [TimeSpan]::Parse($text, [Globalization.CultureInfo]::InvariantCulture) }
        $interval = & $toDuration $watchdog.Repetition.Interval
        $watchdogOk = @($triggers | Where-Object {
            $_.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger' -and $_.Enabled -and $_.Repetition -and $_.Repetition.Interval -and (& $toDuration $_.Repetition.Interval) -eq $interval
        }).Count -eq 1
        $settingsOk = [bool]$registered.Settings.Enabled -and $registered.Settings.AllowStartIfOnBatteries -and
            $registered.Settings.DontStopIfGoingOnBatteries -and $registered.Settings.MultipleInstances -eq 'IgnoreNew' -and
            [System.Xml.XmlConvert]::ToTimeSpan($registered.Settings.ExecutionTimeLimit) -eq [TimeSpan]::Zero
        $principalOk = $registered.Principal.UserId -and ($registered.Principal.UserId -split '\\')[-1] -eq $env:USERNAME -and
            $registered.Principal.LogonType -eq 'Interactive' -and $registered.Principal.RunLevel -eq 'Limited'
        $identityOk = $registered.TaskName -ceq 'tuxevil-rotator' -and $registered.TaskPath -ceq '\' -and $registered.Description -ceq $description
        if (-not ($identityOk -and $actionOk -and $logonOk -and $watchdogOk -and $settingsOk -and $principalOk)) { throw 'Scheduled task readback did not match the expected identity, action, triggers, principal, or settings.' }
        if (-not (Write-RotatorTaskReceipt -Receipt $newReceipt)) { throw 'Could not create the ownership receipt.' }
        $createdByCall = $false
        $writtenState = Get-RotatorTaskReceiptState
        if (-not $writtenState.Safe -or -not $writtenState.Valid -or -not (Test-RotatorTaskOwnership -Task $registered -Receipt $writtenState.Receipt)) { throw 'Ownership receipt readback did not match the registered task.' }
        Write-Log INFO 'rotator' 'task_registered' "tuxevil-rotator starts at logon and is watched every $watchdogMinutes minutes" 0 "task=tuxevil-rotator;exe=$binPath;watchdog=${watchdogMinutes}m"
        return $true
    } catch {
        if ($createdByCall -and $newReceipt) { [void](Remove-RotatorCreatedTask -Receipt $newReceipt -CreatedByCurrentCall $true) }
        Write-Log WARN 'rotator' 'task_failed' 'Scheduled task registration or ownership verification failed; the gateway is started as a detached process only' 0 "error=$($_.Exception.Message)"
        return $false
    }
}

# Start the gateway in the background and leave the proof of that start to the caller's
# probe. The scheduled task is preferred because it also covers the next session;
# anywhere it cannot run, the process is detached from this installer instead.
function Start-RotatorGateway {
    param([string]$LogFile)
    $binPath = Get-RotatorExecutable
    $ownedTask = Get-OwnedRotatorTask
    if ($ownedTask -and (Test-RotatorTaskActionCurrent -Task $ownedTask -Executable $binPath)) {
        try {
            Start-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\'
            Write-Log INFO 'rotator' 'task_started' 'Receipt-owned tuxevil-rotator started through its logon task' 0 'task=tuxevil-rotator'
            return $true
        } catch {
            Write-Log WARN 'rotator' 'task_start_failed' 'Scheduled task did not start; falling back to a detached process' 0 "error=$($_.Exception.Message)"
        }
    }
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

function Remove-RotatorTaskReceipt {
    param($ExpectedReceipt)
    $state = Get-RotatorTaskReceiptState
    if (-not $state.Safe -or -not $state.Valid) { return $false }
    $receipt = $state.Receipt
    if ($receipt.SchemaVersion -ne $ExpectedReceipt.SchemaVersion -or $receipt.TaskName -cne $ExpectedReceipt.TaskName -or
        $receipt.TaskPath -cne $ExpectedReceipt.TaskPath -or $receipt.Marker -cne $ExpectedReceipt.Marker -or
        $receipt.Fingerprint -cne $ExpectedReceipt.Fingerprint -or -not (Test-RotatorReceiptLocation)) { return $false }
    Remove-Item -LiteralPath (Get-RotatorTaskReceiptPath) -Force -ErrorAction Stop
    return $true
}

function Remove-RotatorOwnedTask {
    $state = Get-RotatorTaskReceiptState
    if (-not $state.Safe -or -not $state.Valid) { return $false }
    try {
        $taskState = Get-RotatorTaskQueryState
        if (-not $taskState.Known -or $taskState.Tasks.Count -ne 1 -or $taskState.Tasks[0].TaskPath -cne '\' -or
            -not (Test-RotatorTaskOwnership -Task $taskState.Tasks[0] -Receipt $state.Receipt)) { return $false }
        # ponytail: Task Scheduler has no compare-and-delete; the TOCTOU window remains until an atomic condition is available.
        $state = Get-RotatorTaskReceiptState
        $taskState = Get-RotatorTaskQueryState
        if (-not $state.Safe -or -not $state.Valid -or -not $taskState.Known -or $taskState.Tasks.Count -ne 1 -or
            $taskState.Tasks[0].TaskPath -cne '\' -or -not (Test-RotatorTaskOwnership -Task $taskState.Tasks[0] -Receipt $state.Receipt)) { return $false }
        Unregister-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -Confirm:$false -ErrorAction Stop
        $taskState = Get-RotatorTaskQueryState
        if (-not $taskState.Known -or $taskState.Tasks.Count -ne 0) { return $false }
        return Remove-RotatorTaskReceipt -ExpectedReceipt $state.Receipt
    } catch {
        Write-Log WARN 'rotator' 'task_remove_failed' 'Receipt-owned rotator task could not be safely removed' 0 "error=$($_.Exception.Message)"
        return $false
    }
}

function Remove-RotatorCreatedTask {
    param($Receipt, [bool]$CreatedByCurrentCall)
    if (-not $CreatedByCurrentCall -or -not $Receipt) { return $false }
    try {
        $task = Get-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -ErrorAction Stop
        if (-not (Test-RotatorTaskCleanupGuard -Task $task -Receipt $Receipt -CreatedByCurrentCall $CreatedByCurrentCall)) { return $false }
        # Revalidate this call's fresh marker and fingerprint immediately before cleanup.
        $task = Get-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -ErrorAction Stop
        if (-not (Test-RotatorTaskCleanupGuard -Task $task -Receipt $Receipt -CreatedByCurrentCall $CreatedByCurrentCall)) { return $false }
        Unregister-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -Confirm:$false -ErrorAction Stop
        if (Get-ScheduledTask -TaskName 'tuxevil-rotator' -TaskPath '\' -ErrorAction SilentlyContinue) { return $false }
        return $true
    } catch { return $false }
}

function Get-RotatorNpmReceiptPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $null }
    return Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'setup-ai') 'ownership') 'rotator-npm.json'
}

function Test-RotatorNpmReceiptLocation {
    $root = $env:LOCALAPPDATA; $path = Get-RotatorNpmReceiptPath
    if (-not $path) { return $false }
    $paths = @($root, (Join-Path $root 'setup-ai'), (Join-Path (Join-Path $root 'setup-ai') 'ownership'), $path)
    try {
        for ($i = 0; $i -lt 4; $i++) {
            if (-not (Test-Path -LiteralPath $paths[$i])) { continue }
            $item = Get-Item -LiteralPath $paths[$i] -Force -ErrorAction Stop
            if (($i -lt 3) -ne [bool]$item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        $expected = Join-Path (Join-Path (Join-Path $root 'setup-ai') 'ownership') 'rotator-npm.json'
        return [string]::Equals([System.IO.Path]::GetFullPath($expected), [System.IO.Path]::GetFullPath($path), [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Write-RotatorNpmReceipt {
    param($Receipt)
    $path = Get-RotatorNpmReceiptPath
    if (-not $path -or -not (Test-RotatorNpmReceiptLocation)) { return $false }
    $stream = $null
    try {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        if (-not (Test-RotatorNpmReceiptLocation)) { return $false }
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($Receipt | ConvertTo-Json -Compress -Depth 4))
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        return $true
    } catch { return $false } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-RotatorNpmPathAttributes {
    param([string]$Path)
    try { return [System.IO.File]::GetAttributes($Path) }
    catch [System.IO.FileNotFoundException] { return $null }
    catch [System.IO.DirectoryNotFoundException] { return $null }
}

function Get-RotatorNpmReceiptState {
    param([switch]$AllowMissingPackage)
    $path = Get-RotatorNpmReceiptPath
    if (-not $path -or -not (Test-RotatorNpmReceiptLocation) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
    try {
        $receipt = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($receipt -isnot [pscustomobject] -or $receipt.SchemaVersion -ne 2 -or $receipt.Package -cne 'tuxevil-rotator' -or
            [string]::IsNullOrWhiteSpace($receipt.NpmRoot) -or [string]::IsNullOrWhiteSpace($receipt.PackagePath) -or
            $receipt.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($receipt.Version) -or
            $receipt.Marker -isnot [string] -or $receipt.Marker -cnotmatch '^[0-9a-f]{32}$') { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
        if (-not (Test-Cmd npm)) { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
        $global:LASTEXITCODE = 0
        $root = (& npm root -g 2>$null | Out-String).Trim()
        if ($global:LASTEXITCODE -ne 0 -or $root -cne $receipt.NpmRoot) { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
        $packageDir = Join-Path $root 'tuxevil-rotator'
        $packageJson = Join-Path $packageDir 'package.json'
        $markerPath = Join-Path $packageDir '.setup-ai-ownership'
        if ($packageJson -cne $receipt.PackagePath) { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
        $directoryAttributes = Get-RotatorNpmPathAttributes $packageDir
        $markerAttributes = Get-RotatorNpmPathAttributes $markerPath
        if ($null -eq $directoryAttributes) {
            if ($AllowMissingPackage -and $null -eq $markerAttributes) { return [pscustomobject]@{ Valid = $true; PackagePresent = $false; Receipt = $receipt } }
            return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null }
        }
        if (($directoryAttributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
            ($directoryAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $null -eq $markerAttributes -or
            ($markerAttributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
            ($markerAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return [pscustomobject]@{ Valid = $false; PackagePresent = $true; Receipt = $null } }
        $packageAttributes = Get-RotatorNpmPathAttributes $packageJson
        if ($null -eq $packageAttributes -or ($packageAttributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
            ($packageAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return [pscustomobject]@{ Valid = $false; PackagePresent = $true; Receipt = $null } }
        if ([System.IO.File]::ReadAllText($markerPath) -cne $receipt.Marker) { return [pscustomobject]@{ Valid = $false; PackagePresent = $true; Receipt = $null } }
        $metadata = Get-Content -Raw -LiteralPath $packageJson -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($metadata.Name -cne $receipt.Package -or $metadata.Version -isnot [string] -or $metadata.Version -cne $receipt.Version) { return [pscustomobject]@{ Valid = $false; PackagePresent = $true; Receipt = $null } }
        return [pscustomobject]@{ Valid = $true; PackagePresent = $true; Receipt = $receipt }
    } catch { return [pscustomobject]@{ Valid = $false; PackagePresent = $false; Receipt = $null } }
}

function Test-RotatorNpmTaskDependency {
    param([switch]$ReadOnly)
    $script:RotatorNpmTaskBlocked = $false
    $taskState = Get-RotatorTaskQueryState
    if (-not $taskState.Known) { $script:RotatorNpmTaskBlocked = $true; return $false }
    if ($taskState.Tasks.Count -eq 0) { return $true }
    if ($taskState.Tasks.Count -ne 1 -or $taskState.Tasks[0].TaskPath -cne '\') { $script:RotatorNpmTaskBlocked = $true; return $false }
    $receiptState = Get-RotatorTaskReceiptState
    if (-not $receiptState.Safe -or -not $receiptState.Valid -or
        -not (Test-RotatorTaskOwnership -Task $taskState.Tasks[0] -Receipt $receiptState.Receipt)) { $script:RotatorNpmTaskBlocked = $true; return $false }
    if ($ReadOnly) { return $true }
    if (-not (Remove-RotatorOwnedTask)) { $script:RotatorNpmTaskBlocked = $true; return $false }
    return $true
}

function Get-RotatorTaskInventoryStatus {
    param([switch]$Confirmed, [switch]$DryRun)
    if ($Confirmed -and -not $DryRun) {
        if (Remove-RotatorOwnedTask) { return [pscustomobject]@{ Removed = $true; Message = 'removed receipt-backed task.' } }
        return [pscustomobject]@{ Removed = $false; Message = 'not removed; ownership could not be verified or removal failed.' }
    }
    $taskState = Get-RotatorTaskQueryState
    if (-not $taskState.Known) { return [pscustomobject]@{ Removed = $false; Message = 'state unknown; task query failed and the task is protected.' } }
    if ($taskState.Tasks.Count -eq 0) { return [pscustomobject]@{ Removed = $false; Message = 'not present (task query succeeded).' } }
    if ($taskState.Tasks.Count -ne 1 -or $taskState.Tasks[0].TaskPath -cne '\') {
        return [pscustomobject]@{ Removed = $false; Message = 'protected; duplicate or nested same-name task exists.' }
    }
    $receiptState = Get-RotatorTaskReceiptState
    if ($receiptState.Safe -and $receiptState.Valid -and (Test-RotatorTaskOwnership -Task $taskState.Tasks[0] -Receipt $receiptState.Receipt)) {
        $message = if ($Confirmed -and $DryRun) { 'would remove receipt-backed task in dry-run.' } else { 'receipt-backed and removable with -Yes.' }
        return [pscustomobject]@{ Removed = $false; Message = $message }
    }
    return [pscustomobject]@{ Removed = $false; Message = 'protected; present task has no matching ownership receipt and fingerprint.' }
}

function Remove-RotatorNpmPackage {
    param([switch]$Confirmed, [switch]$DryRun)
    if (-not $Confirmed -or $DryRun) { return $false }
    $receiptPath = Get-RotatorNpmReceiptPath
    if (-not $receiptPath) { return $false }
    try { $receiptBefore = [System.IO.File]::ReadAllText($receiptPath) } catch { return $false }
    $state = Get-RotatorNpmReceiptState
    if (-not $state.Valid -or -not $state.PackagePresent) { return $false }
    if (-not (Test-RotatorNpmTaskDependency)) { return $false }
    $receipt = $state.Receipt
    $current = Get-RotatorNpmReceiptState
    if (-not $current.Valid -or -not $current.PackagePresent -or $current.Receipt.NpmRoot -cne $receipt.NpmRoot -or
        $current.Receipt.PackagePath -cne $receipt.PackagePath -or $current.Receipt.Package -cne $receipt.Package -or
        $current.Receipt.Version -cne $receipt.Version -or $current.Receipt.Marker -cne $receipt.Marker) { return $false }
    try {
        if ([System.IO.File]::ReadAllText($receiptPath) -cne $receiptBefore) { return $false }
    } catch { return $false }
    if (-not (Test-RotatorNpmTaskDependency)) { return $false }
    try {
        $global:LASTEXITCODE = 0
        npm uninstall --global tuxevil-rotator | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "npm exited with code $global:LASTEXITCODE" }
    } catch {
        $script:RotatorNpmRemovalFailed = $true
        Write-Host "ERROR: Receipt-owned tuxevil-rotator npm uninstall failed; package and receipt were preserved. $($_.Exception.Message)"
        return $false
    }
    $after = Get-RotatorNpmReceiptState -AllowMissingPackage
    if (-not $after.Valid -or $after.PackagePresent -or $after.Receipt.NpmRoot -cne $receipt.NpmRoot -or
        $after.Receipt.PackagePath -cne $receipt.PackagePath -or $after.Receipt.Package -cne $receipt.Package -or
        $after.Receipt.Version -cne $receipt.Version -or $after.Receipt.Marker -cne $receipt.Marker) {
        $script:RotatorNpmRemovalFailed = $true
        Write-Host 'ERROR: npm uninstall did not leave the receipt-owned package directory and marker absent from the same global root; receipt preserved.'
        return $false
    }
    try {
        if ([System.IO.File]::ReadAllText($receiptPath) -cne $receiptBefore) { throw 'receipt changed' }
        Remove-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
        if ($null -ne (Get-RotatorNpmPathAttributes $receiptPath)) { throw 'receipt still exists' }
        return $true
    } catch {
        $script:RotatorNpmRemovalFailed = $true
        Write-Host "ERROR: Package is absent but its ownership receipt could not be removed. $($_.Exception.Message)"
        return $false
    }
}

function Install-RotatorNpmPackage {
    if (-not (Test-Cmd npm)) { throw "npm not found; tuxevil-rotator cannot be installed" }

    $npmRootBefore = ''
    try {
        $npmRootBefore = (& npm root -g 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { $npmRootBefore = '' }
    } catch { $npmRootBefore = '' }
    $preExisting = $true
    if ($npmRootBefore) {
        try { $preExisting = [System.IO.Directory]::GetFileSystemEntries($npmRootBefore, 'tuxevil-rotator').Length -gt 0 } catch { $preExisting = $true }
    }

    $installed = Invoke-Step -Phase 'rotator' -Action { npm install -g tuxevil-rotator }
    if (-not $installed) { throw 'tuxevil-rotator npm install failed' }
    if (-not (Test-Cmd tuxevil-rotator)) {
        Write-Log ERROR 'rotator' 'install_missing' 'tuxevil-rotator not found on PATH after npm install'
        throw 'tuxevil-rotator not found on PATH after npm install'
    }
    if (-not $npmRootBefore -or $preExisting) {
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Could not prove this run installed a previously absent global package' 0
        return
    }

    $npmRootAfter = ''
    try {
        $npmRootAfter = (& npm root -g 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $npmRootAfter -cne $npmRootBefore) { $npmRootAfter = '' }
    } catch { $npmRootAfter = '' }
    if (-not $npmRootAfter) {
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Global npm root changed or could not be verified after installation' 0
        return
    }

    $packageDir = Join-Path $npmRootAfter 'tuxevil-rotator'
    $packageJson = Join-Path $packageDir 'package.json'
    $directoryAttributes = Get-RotatorNpmPathAttributes $packageDir
    $packageAttributes = Get-RotatorNpmPathAttributes $packageJson
    if ($null -eq $directoryAttributes -or ($directoryAttributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($directoryAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $null -eq $packageAttributes -or
        ($packageAttributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
        ($packageAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Package directory or package.json is not a regular owned path' 0 "package=$packageJson"
        return
    }
    try {
        $metadata = Get-Content -Raw -LiteralPath $packageJson | ConvertFrom-Json -ErrorAction Stop
        if ($metadata.Name -cne 'tuxevil-rotator' -or $metadata.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($metadata.Version)) { throw 'package metadata mismatch' }
    } catch {
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Installed package metadata could not be verified at the exact global npm root' 0 "package=$packageJson"
        return
    }

    $directoryAttributes = Get-RotatorNpmPathAttributes $packageDir
    $packageAttributes = Get-RotatorNpmPathAttributes $packageJson
    if ($null -eq $directoryAttributes -or ($directoryAttributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($directoryAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $null -eq $packageAttributes -or
        ($packageAttributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
        ($packageAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Package directory or package.json changed to an unsafe path' 0 "package=$packageJson"
        return
    }
    $markerPath = Join-Path $packageDir '.setup-ai-ownership'
    $marker = [Guid]::NewGuid().ToString('N')
    $markerStream = $null
    try {
        $markerStream = [System.IO.File]::Open($markerPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $markerBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($marker)
        $markerStream.Write($markerBytes, 0, $markerBytes.Length)
        $markerStream.Flush($true)
        $markerStream.Dispose(); $markerStream = $null
        if ([System.IO.File]::ReadAllText($markerPath) -cne $marker) { throw 'marker readback mismatch' }
    } catch {
        if ($null -ne $markerStream) { $markerStream.Dispose() }
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Could not create and verify a unique package ownership marker' 0 "path=$markerPath"
        return
    }

    $receipt = [pscustomobject]@{
        SchemaVersion = 2; Package = $metadata.Name; NpmRoot = $npmRootAfter
        PackagePath = $packageJson; Version = $metadata.Version; Marker = $marker
    }
    if (Write-RotatorNpmReceipt -Receipt $receipt) {
        Write-Log INFO 'rotator' 'ownership_receipt_written' 'Verified fresh global package ownership recorded' 0 "package=$packageJson"
    } else {
        try {
            $markerAttributes = Get-RotatorNpmPathAttributes $markerPath
            if ($null -ne $markerAttributes -and ($markerAttributes -band [System.IO.FileAttributes]::Directory) -eq 0 -and
                ($markerAttributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
                [System.IO.File]::ReadAllText($markerPath) -ceq $marker) {
                Remove-Item -LiteralPath $markerPath -Force -ErrorAction Stop
            }
        } catch { Write-Log ERROR 'rotator' 'ownership_marker_cleanup_failed' 'Could not remove the marker after receipt publication failed' 1 "path=$markerPath" }
        Write-Log WARN 'rotator' 'ownership_receipt_skipped' 'Could not publish the package ownership receipt; the package remains unowned' 0
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

    if (-not (Test-NodeMinimum -MinimumMajor 20 -MinimumMinor 0)) {
        $nodeProbe = if ($script:SetupAiNodeVersionProbe) { $script:SetupAiNodeVersionProbe } else { 'none' }
        Write-Log WARN "rotator" "node_too_old" "tuxevil-rotator not installed: it needs Node.js >= 20 and crashes on older runtimes; install Node.js 20+ (the node module ships 22) and re-run the rotator module" 0 "node=$nodeProbe;minimum=20"
        return
    }

    # Install the CLI idempotently. Never runs login and never writes secrets; the
    # start below is best-effort and never fails the module.
    if (Test-Cmd tuxevil-rotator) {
        Write-Log INFO "rotator" "already_present" "tuxevil-rotator already installed"
    } else {
        Install-RotatorNpmPackage
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
            # A gateway with no account exits immediately, so the port never opens and the
            # only place that says so is the CLI's own log (the same file the Pi extension
            # points at); the run-side log only holds the start attempt. Without this the
            # run reports the rotator as installed while the gemini-* aliases stay broken.
            $cliLog = Join-Path $HOME ".tuxevil-rotator\gateway.log"
            $noAccounts = @($cliLog, $gatewayLog) |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Where-Object { Select-String -LiteralPath $_ -SimpleMatch 'No accounts configured' -Quiet } |
                Select-Object -First 1
            $noAccounts = [bool]$noAccounts
            if ($noAccounts) {
                Write-Log WARN "rotator" "accounts_missing" "tuxevil-rotator has no account configured, so the gateway cannot start; run 'tuxevil-rotator login' in an interactive terminal, then 'tuxevil-rotator start'" 0 "url=$gw;log=$gatewayLog"
                $script:PostInstallActions += "rotator: run 'tuxevil-rotator login' in an interactive terminal (it prints a Google OAuth URL and waits for the browser callback on localhost:51121), then 'tuxevil-rotator status' and 'tuxevil-rotator start'"
            } else {
                Write-Log WARN "rotator" "gateway_start_failed" "tuxevil-rotator did not answer within 10s; check '$gatewayLog' or the 'tuxevil-rotator' scheduled task" 0 "url=$gw"
            }
        }
    }
    if (Test-Cmd pi) {
        # `pi install` accepts only protocol URLs without the `git:` prefix, so the bare
        # `github:owner/repo` this module used to pass resolved as a local path and failed.
        # A leftover legacy entry from such a run is tolerated by pi (`pi list` skips it)
        # and cannot be removed with `pi remove`, which only matches installed packages.
        $extensionSource = "git:github.com/darkrei08/pi-cockpit-tools-sync"
        $piSettings = Join-Path $PiAgentDir "settings.json"
        Install-PiPackageOwned -Phase 'rotator' -Spec $extensionSource
        Assert-PiPackageRegistered -Phase 'rotator' -Spec $extensionSource
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
    'pi' = ${function:Mod-Pi}; 'pi-packages' = ${function:Mod-PiPackages}; 'go' = ${function:Mod-Go}; 'dotenv' = ${function:Mod-Dotenv}; 'lazyvim' = ${function:Mod-LazyVim}; 'ee' = ${function:Mod-Ee}
    'skills' = ${function:Mod-Skills}
    'pi-workflows' = ${function:Mod-PiWorkflows}; 'herdr' = ${function:Mod-Herdr}; 'claude-code' = ${function:Mod-ClaudeCode}
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
    Write-Host "`nUse: -Only csv | -All | -DryRun | -Uninstall [-Yes] [-Purge] | -Verbose (default = core)"
}

function Show-Help {
    # Print the comment header between <# and #>, not a fixed line count: a growing
    # usage block must never leak the param() block into -Help.
    $lines = @(Get-Content -LiteralPath $ScriptPath)
    $first = [array]::IndexOf($lines, '<#')
    $last = [array]::IndexOf($lines, '#>')
    if ($first -ge 0 -and $last -gt $first) {
        $lines[($first + 1)..($last - 1)] | ForEach-Object { $_ }
    }
    Show-List
}

function Write-SelectionError {
    param([string]$Message)
    if ($DryRun -or $Uninstall) { Write-Host "ERROR: $Message" -ForegroundColor Red }
    else { Write-Log ERROR "selection" "invalid_only" $Message 2 }
    exit 2
}

function Resolve-Selection {
    $requested = @()
    if ($All) {
        $requested = $ModuleOrder
    } elseif ($OnlySpecified) {
        if ([string]::IsNullOrWhiteSpace($Only)) { Write-SelectionError "-Only requires a non-empty comma-separated module list." }
        foreach ($r in ($Only -split ',')) {
            $r = $r.Trim()
            if (-not $r) { continue }
            if (-not $ModuleDesc.Contains($r)) { Write-SelectionError "Unknown module: $r" }
            $requested += $r
        }
        if ($requested.Count -eq 0) { Write-SelectionError "-Only requires a non-empty comma-separated module list." }
    } else {
        $requested = $ModuleOrder | Where-Object { -not $ModuleOptional.ContainsKey($_) }
    }
    # Order by ModuleOrder so dependencies run first.
    return $ModuleOrder | Where-Object { $requested -contains $_ }
}

function Resolve-UninstallSelection {
    $requested = @()
    if ($All) {
        $requested = @($ModuleOrder) + 'shell'
    } elseif ($OnlySpecified) {
        if ([string]::IsNullOrWhiteSpace($Only)) { Write-SelectionError "-Only requires a non-empty comma-separated module list." }
        foreach ($r in ($Only -split ',')) {
            $r = $r.Trim()
            if (-not $r) { continue }
            if ($r -cne 'shell' -and -not ($ModuleOrder -ccontains $r)) { Write-SelectionError "Unknown module: $r" }
            $requested += $r
        }
        if ($requested.Count -eq 0) { Write-SelectionError "-Only requires a non-empty comma-separated module list." }
    } else {
        $requested = @($ModuleOrder) + 'shell'
    }
    $selected = @($ModuleOrder | Where-Object { $requested -contains $_ })
    if ($requested -contains 'shell') { $selected += 'shell' }
    return $selected
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
    if ($Selected -contains 'claude-code') {
        if (-not (Test-Cmd claude)) { throw "claude-code quality gate could not find claude" }
        Invoke-Step -Phase "quality" -Verify -Action { claude --version }
    }
    if ($Selected -contains 'lazyvim') {
        if (-not (Test-Cmd nvim)) { throw "lazyvim quality gate could not find nvim" }
        if ($script:LazyVimCloned) {
            Invoke-Step -Phase "quality" -Verify -Action { nvim --headless "+Lazy! sync" +qa }
        } else {
            Invoke-Step -Phase "quality" -Verify -Action { nvim --version }
        }
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
            $piSettings = Join-Path $PiAgentDir "settings.json"
            $piSettingsRaw = if (Test-Path $piSettings) { Get-Content -Raw $piSettings } else { "" }
            if (-not ($piSettingsRaw -match '"npm:gentle-pi"') -or -not ($piSettingsRaw -match '"npm:pi-mcp-adapter"')) {
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

if ($Purge -and -not $Uninstall) {
    Write-Host "ERROR: -Purge requires -Uninstall." -ForegroundColor Red
    exit 2
}
if ($DryRun -or $Uninstall) {
    # Lifecycle mode writes no run logs, so the ownership removers get console-only
    # replacements for the run-log helpers, which need an initialized log run.
    function Write-Log {
        param([string]$Level, [string]$Phase, [string]$Event, [string]$Message, [int]$ReturnCode = 0, [string]$Meta = '')
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR') { Write-Host "  ${Level}: $Message $Meta" }
    }
    function Invoke-Step {
        param([string]$Phase, [scriptblock]$Action)
        $global:LASTEXITCODE = 0
        & $Action 2>&1 | Out-Host
        if ($global:LASTEXITCODE -ne 0) { throw "Native command exited with code $global:LASTEXITCODE" }
        return $true
    }
    $selected = if ($Uninstall) { Resolve-UninstallSelection } else { Resolve-Selection }
    if ($Uninstall) {
        Write-Host "Uninstall inventory (Windows):"
        $removed = 0
        $script:RotatorNpmRemovalFailed = $false
        $script:RotatorNpmTaskBlocked = $false
        $script:OpenCodeEnvRemovalFailed = $false
        $script:PiPackageRemovalFailed = $false
        $piRemovalFailureObserved = $false
        foreach ($m in $selected) {
            if ($m -eq 'shell') { Write-Host "  shell: not covered - Windows setup does not edit shell startup files."; continue }
            $piSpecs = @(Get-PiUninstallSpecs -Module $m)
            if ($piSpecs.Count -gt 0) {
                if ($m -ne 'rotator' -and $m -ne 'opencode') { Write-Host "  module '$m': only matching receipt-backed Pi registrations are removable; Pi settings, roots, auth, sessions, package data, and unrelated registrations remain protected." }
                foreach ($piSpec in $piSpecs) {
                    $piStatus = Get-PiPackageInventoryStatus -Spec $piSpec
                    if ($Yes -and -not $DryRun) {
                        $script:PiPackageRemovalFailed = $false
                        if (Remove-PiPackageRegistration -Spec $piSpec -Confirmed:$Yes -DryRun:$DryRun) {
                            Write-Host "  removed: Pi package $piSpec"; $removed++
                        } elseif ($script:PiPackageRemovalFailed) {
                            Write-Host "  ERROR: Pi package $piSpec removal blocked; registration and receipt are preserved."
                            $script:PiPackageRemovalFailed = $true
                            $piRemovalFailureObserved = $true
                        } else { Write-Host "  Pi package '$piSpec': $($piStatus.Message)" }
                    } elseif ($DryRun -and $piStatus.State -eq 'receipt-backed') {
                        Write-Host "  Pi package '$piSpec': would remove receipt-backed exact registration."
                    } else { Write-Host "  Pi package '$piSpec': $($piStatus.Message)" }
                }
            }
            if ($m -eq 'opencode') {
                Write-Host "  module 'opencode': only the receipt-backed User OPENCODE_PI_BIN value can be removed; the CLI, npm package, credentials, and other environment values remain protected."
                $openCodeStatus = Get-OpenCodeEnvInventoryStatus
                if ($Yes -and -not $DryRun) {
                    if (Remove-OpenCodeUserEnvironment -Confirmed:$Yes -DryRun:$DryRun) { Write-Host '  removed: User OPENCODE_PI_BIN environment value'; $removed++ }
                    elseif ($script:OpenCodeEnvRemovalFailed) { Write-Host '  ERROR: User OPENCODE_PI_BIN removal failed; ownership receipt preserved.' }
                    else { Write-Host "  User OPENCODE_PI_BIN: $($openCodeStatus.Message)" }
                } elseif ($DryRun -and $openCodeStatus.State -eq 'receipt-backed') {
                    Write-Host '  User OPENCODE_PI_BIN: would remove receipt-backed value.'
                } else { Write-Host "  User OPENCODE_PI_BIN: $($openCodeStatus.Message)" }
                continue
            }
            if ($m -ne 'rotator') {
                if ($piSpecs.Count -eq 0) { Write-Host "  module '$m': not covered - setup-ai does not record ownership; the installation may predate this run." }
                continue
            }
            Write-Host "  module 'rotator': only its receipt-owned task and matching global npm package can be removed; other package/data remain protected."
            $taskStatus = Get-RotatorTaskInventoryStatus -Confirmed:$Yes -DryRun:$DryRun
            if ($taskStatus.Removed) { Write-Host '  removed: rotator scheduled task'; $removed++ }
            else { Write-Host "  rotator task: $($taskStatus.Message)" }
            if ($Yes -and -not $DryRun) {
                if (Remove-RotatorNpmPackage -Confirmed:$Yes -DryRun:$DryRun) { Write-Host '  removed: rotator global npm package'; $removed++ }
                elseif ($script:RotatorNpmTaskBlocked) { Write-Host '  rotator npm package: preserved - task dependency is not proven absent; package and receipt remain protected.' }
                elseif ($script:RotatorNpmRemovalFailed) { Write-Host '  rotator npm package: removal failed; ownership receipt preserved.' }
                else { Write-Host '  rotator npm package: preserved - missing or mismatched receipt/fingerprint.' }
            } else {
                $npmState = Get-RotatorNpmReceiptState
                if ($npmState.Valid -and $npmState.PackagePresent) { [void](Test-RotatorNpmTaskDependency -ReadOnly) }
                if ($npmState.Valid -and $npmState.PackagePresent -and $script:RotatorNpmTaskBlocked) { Write-Host '  rotator npm package: protected - task dependency is not proven removable; package and receipt remain protected.' }
                elseif ($DryRun -and $npmState.Valid -and $npmState.PackagePresent) { Write-Host '  rotator npm package: would remove receipt-backed tuxevil-rotator.' }
                elseif ($npmState.Valid -and $npmState.PackagePresent) { Write-Host '  rotator npm package: receipt-backed and removable with -Yes.' }
                else { Write-Host '  rotator npm package: not covered - missing or mismatched ownership receipt; legacy packages are protected.' }
            }
        }
        if ($Yes -and $removed -gt 0) { Write-Host "Removal requested (-Yes); removed $removed receipt-owned rotator item(s)." }
        elseif ($Yes -and $DryRun) { Write-Host 'Dry run; no items were removed.' }
        elseif ($Yes) { Write-Host "Removal requested (-Yes), but no items were removed." }
        else { Write-Host "Inventory only; pass -Yes to request removal." }
        if ($Purge) { Write-Host "-Purge does not expand scope; Pi roots/data, rotator data, OpenCode/npm/vendor resources, and all other modules remain protected." }
        if ($script:RotatorNpmRemovalFailed -or $script:OpenCodeEnvRemovalFailed -or $piRemovalFailureObserved) { exit 1 }
    } else {
        Write-Host "Installation plan (dry run):"
        foreach ($m in $selected) {
            Write-Host "  ${m}:"
            foreach ($operation in $ModuleDryRunPlan[$m]) { Write-Host "    - $operation" }
        }
        Write-Host "Plan only; no installer, network, package-manager, environment, task, or child-process action was run."
    }
    exit 0
}

$script:VerboseOutput = ($VerbosePreference -eq 'Continue' -or $env:VERBOSE -eq '1')
if ($script:VerboseOutput) { $env:DEBUG = '1' }
$PSNativeCommandUseErrorActionPreference = $true

# Render child-process UTF-8 output correctly instead of mojibake on the default codepage.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    if (Get-Command chcp -ErrorAction SilentlyContinue) { chcp 65001 | Out-Null }
} catch {
    Write-Warning "Could not set UTF-8 console encoding: $($_.Exception.Message)"
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
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
$moduleTotal = @($selected).Count
$moduleIndex = 0
Write-Host ""
Write-Host ("Installation plan: {0} module(s)" -f $moduleTotal) -ForegroundColor White
Write-Host ("  {0}" -f ($selected -join '  ')) -ForegroundColor Gray

if (-not ('SetupAiInterrupt' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class SetupAiInterrupt {
    public static volatile bool Interrupted;
    public static void OnSignal(PosixSignalContext ctx) { ctx.Cancel = true; Interrupted = true; }
}
'@
}
try {
    [System.Runtime.InteropServices.PosixSignalRegistration]::Create(
        [System.Runtime.InteropServices.PosixSignal]::SIGINT,
        [System.Delegate]::CreateDelegate([System.Action[System.Runtime.InteropServices.PosixSignalContext]], [SetupAiInterrupt].GetMethod('OnSignal'))) | Out-Null
} catch {
    # A host without a console cannot deliver the signal; record the degraded
    # interruption handling instead of swallowing the registration failure.
    Write-Log WARN "bootstrap" "interrupt_handler_unavailable" `
        "Ctrl+C cannot be intercepted on this host; the run will end without an interrupted summary" 0 `
        "error=$($_.Exception.Message)"
}
foreach ($m in $selected) {
    if (Test-Interrupted) { break }
    $moduleIndex++
    $script:CurrentModule = $m
    Write-ModuleBanner -Index $moduleIndex -Total $moduleTotal -Name $m
    try { & $ModuleFn[$m]; $script:SucceededModules += $m; Write-Host ("  OK  {0} completed" -f $m) -ForegroundColor Green }
    catch {
        $script:FailedModules += $m
        Write-Log ERROR "modules" "module_failed" "Module $m failed: $($_.Exception.Message)" 1
        # Fail-fast: mirror the Bash ERR trap so we never run modules whose
        # ordered prerequisites just failed.
        break
    }
}

# The in-flight module is the one that was running when the signal arrived; the
# phase reassignments below must not rewrite it in the summary.
if (Test-Interrupted -and -not $script:InterruptModule) { $script:InterruptModule = $script:CurrentModule }

# npm 12 install-script approval can only name an installed package, so converge
# after the modules that install pi packages and before the gates that use them.
$script:CurrentModule = 'pi-npm'
if (-not (Test-Interrupted) -and -not $script:FailedModules -and ($selected -contains 'pi' -or $selected -contains 'pi-packages' -or $selected -contains 'gentle-ai' -or $selected -contains 'pi-workflows')) {
    try {
        Approve-NpmInstallScripts -Dir $PiNpmDir
    } catch {
        $script:FailedModules += 'pi-npm'
        Write-Log ERROR "pi-npm" "install_scripts_unverified" $_.Exception.Message 1
    }
}

# Skip quality gates when a module already failed (Bash aborts before them).
if (-not (Test-Interrupted) -and -not $script:FailedModules) {
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
$reportBun = if (Test-Cmd bun) { Get-ReportCommandValue -Command "bun" -Arguments @("--version") } else { "n/a" }
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
- Bun:  $reportBun
- pi:   $(if (Test-Cmd pi) { 'installed' } else { 'n/a' })

Logs: $HumanLog ; $JsonlLog
"@ | Set-Content -Path $ReportFile

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " AI Dev Suite (Windows) setup finished" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Modules : $($selected -join ' ')"
$interruptedTarget = if ($script:InterruptModule) { $script:InterruptModule } else { $script:CurrentModule }
$exitCode = 0
if (Test-Interrupted) {
    Write-Host "Interrupted: $($script:InterruptSignal)" -ForegroundColor Yellow
    Write-Log ERROR "bootstrap" "run_interrupted" "Run interrupted by Ctrl+C" 130 "signal=$($script:InterruptSignal);module=$($interruptedTarget)"
    $exitCode = 130
} elseif ($script:FailedModules) {
    Write-Host "Failed  : $($script:FailedModules -join ' ')" -ForegroundColor Yellow
    Write-Log ERROR "bootstrap" "completed_with_failures" "Setup finished with failed modules or quality gates" 1 "failed=$($script:FailedModules -join ',')"
    $exitCode = 1
} else {
    Write-Log INFO "bootstrap" "completed" "Setup completed successfully" 0
}
# The summary is the terminal record of the run, as it is in setup-ai.sh.
$failedForSummary = @($script:FailedModules)
if ($script:Interrupted -and $interruptedTarget -and ($failedForSummary -notcontains $interruptedTarget)) {
    $failedForSummary += $interruptedTarget
}
Write-RunSummary -Selected $script:SelectedModules -Succeeded $script:SucceededModules -FailedModules $failedForSummary -ExitCode $exitCode
Write-Host "Report  : $ReportFile"
if ($exitCode -eq 0) {
    Write-Host "`nNext: open a new terminal so PATH updates apply."
    foreach ($action in $script:PostInstallActions) {
        Write-Host "Then : $action"
    }
}
exit $exitCode
