#Requires -Version 7.3
<#
==============================================================================
 AI Dev Suite — Engineering Excellence Edition (Windows)
 Version: 3.2.0

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

$ScriptVersion = "3.2.0"
$ScriptPath = $PSCommandPath
$ScriptDir = Split-Path -Parent $ScriptPath
$LogDir = Join-Path $ScriptDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$RunId = (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$HumanLog = Join-Path $LogDir "setup_$RunId.log"
$JsonlLog = Join-Path $LogDir "setup_$RunId.jsonl"
$ReportFile = Join-Path $LogDir "engineering-report_$RunId.md"

$EE_Slug  = "darkrei08/Engineering-Excellence"
$EE_Skill = "engineering-excellence"
$PiExtDir   = Join-Path $HOME ".pi\agent\extensions"

# Upstream agent-skill stack mirrored from vekexasia/dotenv setup_env.sh so the
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

# ------------------------------------------------------------------------------
# Logging (human + JSONL)
# ------------------------------------------------------------------------------

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$Level,
        [string]$Phase, [string]$Event, [string]$Message, [int]$ReturnCode = 0, [string]$Meta = ""
    )
    $ts = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
    $obj = [ordered]@{
        timestamp = $ts; level = $Level; phase = $Phase; event = $Event
        message = $Message; return_code = $ReturnCode; run_id = $RunId; pid = $PID
    }
    if ($Meta) { $obj.meta = $Meta }
    ($obj | ConvertTo-Json -Compress) | Add-Content -Path $JsonlLog

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

function Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# winget updates the registry PATH, not the live process. Re-read it so tools
# installed this run (node, git, ...) resolve without opening a new terminal.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Run a step; $Optional means failures are logged as WARN and swallowed.
function Invoke-Step {
    param([string]$Phase, [scriptblock]$Action, [switch]$Optional)
    Write-Log INFO $Phase "step_start" "Running step"
    try {
        $global:LASTEXITCODE = 0
        & $Action 2>&1 | Tee-Object -FilePath $HumanLog -Append | Out-Host
        $nativeExitCode = $global:LASTEXITCODE
        if ($nativeExitCode -ne 0) {
            throw "Native command exited with code $nativeExitCode"
        }
        Write-Log INFO $Phase "step_ok" "Step completed"
        return $true
    } catch {
        if ($Optional) {
            Write-Log WARN $Phase "step_failed_optional" "$($_.Exception.Message); continuing" 1
            return $false
        }
        Write-Log ERROR $Phase "step_failed" "$($_.Exception.Message)" 1
        throw
    }
}

function Test-WingetInstalled {
    param([string]$Id, [string]$Phase)
    $probe = Join-Path ([IO.Path]::GetTempPath()) ("setup-ai-winget-" + [guid]::NewGuid().ToString("N") + ".log")
    try {
        # Keep the query inside Invoke-Step so its exit status and output are
        # logged; a failed probe is treated as "not installed" and followed
        # by the mandatory install step.
        $listed = Invoke-Step -Phase $Phase -Optional -Action {
            winget list --id $Id -e | Out-File -LiteralPath $probe -Encoding utf8
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
    $ok = Invoke-Step -Phase "node" -Optional -Action {
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
        throw "Node.js is required; install Node.js 22.19 or newer"
    }
    $versionText = ""
    Invoke-Step -Phase "node" -Action {
        $script:SetupAiNodeVersion = (node --version).Trim()
    }
    $versionText = $script:SetupAiNodeVersion
    if ($versionText -notmatch '^v?(\d+)\.(\d+)') {
        throw "Could not parse Node.js version '$versionText'"
    }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if (($major -lt 22) -or (($major -eq 22) -and ($minor -lt 19))) {
        throw "Node.js $versionText is too old; pi-extensible-workflows needs >= 22.19"
    }
    Write-Log INFO "node" "runtime_validated" "Node.js version satisfies workflow requirement" 0 "version=$versionText;minimum=22.19"
}

function Get-ReportCommandValue {
    param([string]$Command, [string[]]$Arguments)
    $script:SetupAiReportValue = ""
    $ok = Invoke-Step -Phase "report" -Optional -Action {
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
        $skillPath = Join-Path (Join-Path $SkillAgentRoots[$agent] $Skill) "SKILL.md"
        if (-not (Test-Path $skillPath)) {
            throw "$Skill SKILL.md missing for targeted agent '$agent' ($skillPath)"
        }
    }
    Write-Log INFO $Phase "skill_verified" "$Skill verified for every targeted agent" 0 "agents=$($Agents -join ',')"
}

# ==============================================================================
# Module registry
# ==============================================================================

$ModuleOrder = @('base','node','bun','pi','go','dotenv','ee','skills','pi-workflows','herdr','gentle-ai','codex','antigravity','opencode','cockpit')

$ModuleDesc = [ordered]@{
    'base'         = 'System packages (build tools, git, gh, python, neovim, jq, imagemagick, go)'
    'node'         = 'Node.js v22 + npm@latest (nvm on Unix, winget on Windows)'
    'bun'          = 'Bun runtime'
    'pi'           = 'pi.dev coding agent CLI'
    'go'           = 'Go toolchain'
    'dotenv'       = 'vekexasia/dotenv dotfiles (Linux only: clones + runs setup_env.sh)'
    'ee'           = 'Engineering Excellence skill (npx skills add, all detected agents)'
    'skills'       = 'Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add'
    'pi-workflows' = 'pi-extensible-workflows (fix module resolution for pi extensions)'
    'herdr'        = 'herdr terminal multiplexer'
    'gentle-ai'    = 'gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi'
    'codex'        = 'OpenAI Codex CLI'
    'antigravity'  = 'Google Antigravity CLI (agy)'
    'opencode'     = 'opencode agent CLI (opencode-ai)'
    'cockpit'      = 'cockpit-tools desktop GUI app (optional, CC BY-NC-SA)'
}
$ModuleOptional = @{ 'cockpit' = $true }

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
        $probeOk = Invoke-Step -Phase "base" -Optional -Action {
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
    Invoke-Step -Phase "base" -Action {
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
        Invoke-Step -Phase "bun" -Action { bun --version }
        Write-Log INFO "bun" "already_present" "bun already installed"
        return
    }
    Invoke-RemoteScript -Url "https://bun.sh/install.ps1" -Phase "bun"
    if (Test-Cmd bun) {
        Invoke-Step -Phase "bun" -Action { bun --version }
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
        Invoke-Step -Phase "go" -Action { go version }
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

# Installs vekexasia/dotenv's skill stack on every OS via `npx skills add`.
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
    $ver = ""
    try {
        Invoke-Step -Phase "pi-workflows" -Action {
            $script:SetupAiWorkflowVersion = (npm view pi-extensible-workflows version).Trim()
        }
        $ver = $script:SetupAiWorkflowVersion
    } catch {
        throw "Could not resolve pi-extensible-workflows version: $($_.Exception.Message)"
    }
    if (-not $ver) { throw "Could not resolve pi-extensible-workflows version" }
    Write-Log INFO "pi-workflows" "version" "Version $ver"
    Invoke-Step -Phase "pi-workflows" -Action { pi install "npm:pi-extensible-workflows@$ver" }
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    Set-Content -Path (Join-Path $PiExtDir ".npmrc") -Value "ignore-scripts=false"
    # Mark this dir as an npm project root so `npm install` lands HERE and cannot
    # walk up into an ancestor project (mirrors setup-ai.sh).
    $pkgJson = Join-Path $PiExtDir "package.json"
    if (-not (Test-Path $pkgJson)) {
        Set-Content -Path $pkgJson -Value '{"name":"pi-extensions","private":true}'
    }
    Push-Location $PiExtDir
    try {
        Invoke-Step -Phase "pi-workflows" -Action {
            npm install --save-exact --no-audit --no-fund "pi-extensible-workflows@$ver"
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
}

function Mod-Herdr {
    Write-Log INFO "herdr" "start" "herdr"
    if (Test-Cmd herdr) {
        Invoke-Step -Phase "herdr" -Action { herdr --version }
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
    Invoke-Step -Phase "gentle-ai" -Action { & gentle-ai --version }

    # Detect the agents/IDEs present on this machine (same mapping as Mod-Ee).
    $detectedAgents = Get-TargetSkillAgents

    # Per-agent / per-IDE selection + MCP wiring, owned by gentle-ai. This is a
    # core step and must actually run: with a real console we launch the
    # interactive selector (run directly — Invoke-Step pipes output and would
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

function Mod-Opencode {
    Write-Log INFO "opencode" "start" "opencode"
    if (Test-Cmd opencode) { Write-Log INFO "opencode" "already_present" "opencode already installed"; return }
    if (-not (Test-Cmd npm)) {
        throw "npm not found; opencode cannot be installed"
    }
    Invoke-Step -Phase "opencode" -Action { npm install -g opencode-ai }
    if (-not (Test-Cmd opencode)) {
        Write-Log ERROR "opencode" "install_missing" "opencode not found on PATH after npm install"
        throw "opencode not found on PATH after npm install"
    }
    @"
  OpenCode Go (paid) is hosted-model access; after install run: opencode auth login
  The SAME key works in pi.dev — add a custom provider (baseUrl https://opencode.ai/zen/v1,
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

$ModuleFn = @{
    'base' = ${function:Mod-Base}; 'node' = ${function:Mod-Node}; 'bun' = ${function:Mod-Bun}
    'pi' = ${function:Mod-Pi}; 'go' = ${function:Mod-Go}; 'dotenv' = ${function:Mod-Dotenv}; 'ee' = ${function:Mod-Ee}
    'skills' = ${function:Mod-Skills}
    'pi-workflows' = ${function:Mod-PiWorkflows}; 'herdr' = ${function:Mod-Herdr}
    'gentle-ai' = ${function:Mod-GentleAi}
    'codex' = ${function:Mod-Codex}; 'antigravity' = ${function:Mod-Antigravity}
    'opencode' = ${function:Mod-Opencode}; 'cockpit' = ${function:Mod-Cockpit}
}

# ==============================================================================
# CLI / selection
# ==============================================================================

function Show-List {
    Write-Host "AI Dev Suite $ScriptVersion — modules (core = installed by default):`n"
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
            if (-not $ModuleDesc.Contains($r)) { Write-Error "Unknown module: $r"; exit 2 }
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
    Write-Log INFO "quality" "start" "Running quality gates"

    if ($Selected -contains 'node' -or $Selected -contains 'pi-workflows') {
        Assert-NodeMinimum
    }
    if ($Selected -contains 'node') {
        Invoke-Step -Phase "quality" -Action { node --version }
        Invoke-Step -Phase "quality" -Action { npm --version }
    }
    if ($Selected -contains 'bun') {
        if (-not (Test-Cmd bun)) { throw "bun quality gate could not find bun" }
        Invoke-Step -Phase "quality" -Action { bun --version }
    }
    if ($Selected -contains 'pi') {
        if (-not (Test-Cmd pi)) { throw "pi quality gate could not find pi" }
        Invoke-Step -Phase "quality" -Action { pi --no-extensions --version }
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
Write-Log INFO "bootstrap" "modules_selected" "Modules queued" 0 ("modules=" + ($selected -join ' '))

$failed = @()
foreach ($m in $selected) {
    try { & $ModuleFn[$m] }
    catch {
        $failed += $m
        Write-Log ERROR "modules" "module_failed" "Module $m failed: $($_.Exception.Message)" 1
        # Fail-fast: mirror the Bash ERR trap so we never run modules whose
        # ordered prerequisites just failed.
        break
    }
}

# Skip quality gates when a module already failed (Bash aborts before them).
if (-not $failed) {
    try {
        Invoke-QualityGates -Selected $selected
    } catch {
        $failed += 'quality'
        Write-Log ERROR "quality" "gates_failed" $_.Exception.Message 1
    }
}

# Report
$reportNode = if (Test-Cmd node) { Get-ReportCommandValue -Command "node" -Arguments @("--version") } else { "n/a" }
$reportNpm = if (Test-Cmd npm) { Get-ReportCommandValue -Command "npm" -Arguments @("--version") } else { "n/a" }
$reportGo = if (Test-Cmd go) { Get-ReportCommandValue -Command "go" -Arguments @("version") } else { "n/a" }
@"
# AI Dev Suite — Engineering Report (Windows)

**Script version:** $ScriptVersion
**Run ID:** $RunId
**Selected modules:** $($selected -join ' ')
**Failed modules:** $(if ($failed) { $failed -join ' ' } else { 'none' })

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
if ($failed) {
    Write-Host "Failed  : $($failed -join ' ')" -ForegroundColor Yellow
    Write-Log ERROR "bootstrap" "completed_with_failures" "Setup finished with failed modules or quality gates" 1 "failed=$($failed -join ',')"
    Write-Host "Report  : $ReportFile"
    exit 1
}
Write-Log INFO "bootstrap" "completed" "Setup completed successfully" 0
Write-Host "Report  : $ReportFile"
Write-Host "`nNext: open a new terminal so PATH updates apply."
