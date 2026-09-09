#Requires -Version 7.0
<#
==============================================================================
 AI Dev Suite — Engineering Excellence Edition (Windows)
 Version: 3.0.0

 Windows-native installer, sibling of setup-ai.sh. Uses each tool's official
 Windows method: winget for language runtimes, the vendor install.ps1 scripts
 for the AI CLIs, `go install` for gentle-ai, npm for opencode, and
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

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptVersion = "3.0.2"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$RunId = (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$HumanLog = Join-Path $LogDir "setup_$RunId.log"
$JsonlLog = Join-Path $LogDir "setup_$RunId.jsonl"
$ReportFile = Join-Path $LogDir "engineering-report_$RunId.md"

$EE_Slug  = "micio86dev/Engineering-Excellence"
$EE_Skill = "engineering-excellence"
$PiSkillDir = Join-Path $HOME ".pi\agent\skills\$EE_Skill"
$PiExtDir   = Join-Path $HOME ".pi\agent\extensions"

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
        & $Action 2>&1 | Tee-Object -FilePath $HumanLog -Append | Out-Host
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

function Install-Winget {
    param([string]$Id, [string]$Phase)
    if (-not (Test-Cmd winget)) {
        Write-Log WARN $Phase "winget_missing" "winget not available; install '$Id' manually"
        return
    }
    # Skip if already installed.
    $installed = winget list --id $Id -e 2>$null | Select-String -SimpleMatch $Id
    if ($installed) {
        Write-Log INFO $Phase "already_present" "$Id already installed"
        return
    }
    Invoke-Step -Phase $Phase -Optional -Action {
        winget install -e --id $Id --accept-package-agreements --accept-source-agreements --silent
    }
}

function Invoke-RemoteScript {
    param([string]$Url, [string]$Phase)
    # Mirrors the vendor's documented `irm <url> | iex`, but logged.
    Invoke-Step -Phase $Phase -Optional -Action {
        $script = Invoke-RestMethod -Uri $Url -UseBasicParsing
        Invoke-Expression $script
    }
}

# ==============================================================================
# Module registry
# ==============================================================================

$ModuleOrder = @('base','node','bun','pi','go','ee','pi-workflows','herdr','gentle-ai','engram','codex','antigravity','opencode','cockpit')

$ModuleDesc = [ordered]@{
    'base'         = 'Core dev tools via winget (git, gh, python, neovim)'
    'node'         = 'Node.js LTS (winget OpenJS.NodeJS.LTS) + npm@latest'
    'bun'          = 'Bun runtime (bun.sh install.ps1)'
    'pi'           = 'pi.dev coding agent CLI (pi.dev install.ps1)'
    'go'           = 'Go toolchain (winget GoLang.Go)'
    'ee'           = 'Engineering Excellence skill (npx skills add, detected agents)'
    'pi-workflows' = 'pi-extensible-workflows (module resolution fix for pi extensions)'
    'herdr'        = 'herdr terminal multiplexer (herdr.dev install.ps1)'
    'gentle-ai'    = 'gentle-ai (go install) + gentle-pi package'
    'engram'       = 'Engram persistent memory for pi (gentle-engram: /remember /recall)'
    'codex'        = 'OpenAI Codex CLI (chatgpt.com install.ps1)'
    'antigravity'  = 'Google Antigravity CLI (antigravity.google install.ps1)'
    'opencode'     = 'opencode agent CLI (npm opencode-ai)'
    'cockpit'      = 'cockpit-tools desktop GUI (optional, .msi, CC BY-NC-SA)'
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
    Update-SessionPath
}

function Mod-Node {
    Write-Log INFO "node" "start" "Node.js"
    if (-not (Test-Cmd node)) {
        Install-Winget -Id "OpenJS.NodeJS.LTS" -Phase "node"
        Update-SessionPath
        # winget's PATH refresh can still lag; add the default install dir directly.
        $nodeDir = Join-Path $env:ProgramFiles "nodejs"
        if ((-not (Test-Cmd node)) -and (Test-Path (Join-Path $nodeDir "node.exe"))) {
            $env:Path = "$nodeDir;$env:Path"
        }
    }
    if (Test-Cmd npm) {
        Invoke-Step -Phase "node" -Optional -Action { npm install -g npm@latest }
    } else {
        Write-Log WARN "node" "unresolved" "node/npm not on PATH after install — open a NEW terminal and re-run (node-dependent modules will be skipped)"
    }
}

function Mod-Bun {
    Write-Log INFO "bun" "start" "Bun"
    if (Test-Cmd bun) { Write-Log INFO "bun" "already_present" "bun already installed"; return }
    Invoke-RemoteScript -Url "https://bun.sh/install.ps1" -Phase "bun"
}

function Mod-Pi {
    Write-Log INFO "pi" "start" "pi.dev CLI"
    if (Test-Cmd pi) { Write-Log INFO "pi" "already_present" "pi already installed"; return }
    Invoke-RemoteScript -Url "https://pi.dev/install.ps1" -Phase "pi"
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $HOME ".pi\agent\skills") | Out-Null
}

function Mod-Go {
    Write-Log INFO "go" "start" "Go toolchain"
    if (Test-Cmd go) { Write-Log INFO "go" "already_present" "Go already installed"; return }
    Install-Winget -Id "GoLang.Go" -Phase "go"
}

function Mod-Ee {
    Write-Log INFO "ee" "start" "Engineering Excellence"
    if (-not (Test-Cmd npx)) { Write-Log WARN "ee" "npx_missing" "npx not found; install node first"; return }
    # Keys are `skills` CLI agent names (claude-code, gemini-cli), not dir names.
    $agents = @{ pi = ".pi"; 'claude-code' = ".claude"; 'gemini-cli' = ".gemini"; cursor = ".cursor"; antigravity = ".antigravity"; codex = ".codex"; opencode = ".config\opencode" }
    $any = $false
    foreach ($a in @('pi','claude-code','gemini-cli','cursor','antigravity','codex','opencode')) {
        if (Test-Path (Join-Path $HOME $agents[$a])) {
            Invoke-Step -Phase "ee" -Optional -Action {
                npx --yes skills@latest add $EE_Slug --skill $EE_Skill --global --agent $a --copy --yes
            }
            $any = $true
        }
    }
    if (-not $any) {
        Invoke-Step -Phase "ee" -Optional -Action {
            npx --yes skills@latest add $EE_Slug --skill $EE_Skill --global --agent pi --copy --yes
        }
    }
    if (Test-Path (Join-Path $PiSkillDir "SKILL.md")) {
        Write-Log INFO "ee" "skill_installed" "EE skill present for pi"
    }
}

function Mod-PiWorkflows {
    Write-Log INFO "pi-workflows" "start" "pi-extensible-workflows"
    if (-not (Test-Cmd pi)) { Write-Log WARN "pi-workflows" "pi_missing" "pi not found; skipped"; return }
    $ver = ""
    try { $ver = (npm view pi-extensible-workflows version).Trim() } catch {}
    if (-not $ver) { Write-Log WARN "pi-workflows" "version_unresolved" "Could not resolve version; skipped"; return }
    Write-Log INFO "pi-workflows" "version" "Version $ver"
    Invoke-Step -Phase "pi-workflows" -Optional -Action { pi install "npm:pi-extensible-workflows@$ver" }
    New-Item -ItemType Directory -Force -Path $PiExtDir | Out-Null
    Set-Content -Path (Join-Path $PiExtDir ".npmrc") -Value "ignore-scripts=false"
    Push-Location $PiExtDir
    try {
        Invoke-Step -Phase "pi-workflows" -Optional -Action {
            npm install --save-exact --no-audit --no-fund "pi-extensible-workflows@$ver"
        }
        Invoke-Step -Phase "pi-workflows" -Optional -Action {
            node -e "console.log(require.resolve('pi-extensible-workflows',{paths:[process.cwd()]}))"
        }
    } finally { Pop-Location }
}

function Mod-Herdr {
    Write-Log INFO "herdr" "start" "herdr"
    if (Test-Cmd herdr) { Write-Log INFO "herdr" "already_present" "herdr already installed"; return }
    Invoke-RemoteScript -Url "https://herdr.dev/install.ps1" -Phase "herdr"
}

function Mod-GentleAi {
    Write-Log INFO "gentle-ai" "start" "gentle-ai"
    if (-not (Test-Cmd gentle-ai) -and -not (Test-Cmd gga)) {
        if (Test-Cmd go) {
            Invoke-Step -Phase "gentle-ai" -Optional -Action {
                go install github.com/gentleman-programming/gentle-ai/v2/cmd/gentle-ai@latest
            }
        } else {
            Write-Log WARN "gentle-ai" "go_missing" "Go not found; cannot 'go install' gentle-ai on Windows"
        }
    }
    if (Test-Cmd pi) {
        Invoke-Step -Phase "gentle-ai" -Optional -Action { pi install npm:gentle-pi }
        Invoke-Step -Phase "gentle-ai" -Optional -Action { pi install npm:pi-mcp-adapter }
        Write-Log INFO "gentle-ai" "pi_enabled" "gentle-pi registered in pi (verify: /gentle-ai:status)"
    }
    @"
  gentle-ai next steps (run yourself, per project):
    1) Set your API keys
    2) Run your selected agent
    3) Try: /sdd-new my-feature   (in pi: /gentle-ai:status, /gentleman:models)
  GGA (per project):  gga init  then  gga install
"@ | Tee-Object -FilePath $HumanLog -Append | Out-Host
}

function Mod-Engram {
    Write-Log INFO "engram" "start" "Engram memory (pi)"
    # The gentle-engram pi extension auto-starts `engram serve`; the Engram Go
    # binary must be on PATH first, or the extension loads but silently fails.
    if (-not (Test-Cmd engram)) {
        if (Test-Cmd go) {
            Invoke-Step -Phase "engram" -Optional -Action {
                go install github.com/Gentleman-Programming/engram/cmd/engram@latest
            }
            $goBin = Join-Path $HOME "go\bin"
            if ((Test-Path (Join-Path $goBin "engram.exe")) -and ($env:Path -notlike "*$goBin*")) {
                $env:Path = "$goBin;$env:Path"
            }
        } else {
            Write-Log WARN "engram" "go_missing" "Go not found; cannot install engram binary (needed on PATH)"
        }
    }
    if (-not (Test-Cmd pi)) { Write-Log WARN "engram" "pi_missing" "pi not found; skipped"; return }
    Invoke-Step -Phase "engram" -Optional -Action { pi install npm:gentle-engram }
    Invoke-Step -Phase "engram" -Optional -Action { pi install npm:pi-mcp-adapter }
    Invoke-Step -Phase "engram" -Optional -Action { npm exec --yes --package gentle-engram@latest -- pi-engram init }
    Write-Log INFO "engram" "enabled" "Engram enabled — RESTART pi, verify: mem_current_project / mem_doctor / 'engram tui'"
}

function Mod-Codex {
    Write-Log INFO "codex" "start" "Codex CLI"
    if (Test-Cmd codex) { Write-Log INFO "codex" "already_present" "codex already installed"; return }
    Invoke-RemoteScript -Url "https://chatgpt.com/codex/install.ps1" -Phase "codex"
}

function Mod-Antigravity {
    Write-Log INFO "antigravity" "start" "Antigravity CLI"
    if (Test-Cmd agy) { Write-Log INFO "antigravity" "already_present" "agy already installed"; return }
    Invoke-RemoteScript -Url "https://antigravity.google/cli/install.ps1" -Phase "antigravity"
}

function Mod-Opencode {
    Write-Log INFO "opencode" "start" "opencode"
    if (Test-Cmd opencode) { Write-Log INFO "opencode" "already_present" "opencode already installed"; return }
    if (Test-Cmd npm) {
        Invoke-Step -Phase "opencode" -Optional -Action { npm install -g opencode-ai }
    } else {
        Write-Log WARN "opencode" "npm_missing" "npm not found; install node first"
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
        Invoke-Step -Phase "cockpit" -Optional -Action { Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qb" -Wait }
    } catch {
        Write-Log WARN "cockpit" "failed" "$($_.Exception.Message)"
    }
}

$ModuleFn = @{
    'base' = ${function:Mod-Base}; 'node' = ${function:Mod-Node}; 'bun' = ${function:Mod-Bun}
    'pi' = ${function:Mod-Pi}; 'go' = ${function:Mod-Go}; 'ee' = ${function:Mod-Ee}
    'pi-workflows' = ${function:Mod-PiWorkflows}; 'herdr' = ${function:Mod-Herdr}
    'gentle-ai' = ${function:Mod-GentleAi}; 'engram' = ${function:Mod-Engram}
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
    Write-Host "`nUse: -Only <csv> | -All | (default = core)"
}

function Show-Help {
    Get-Content $MyInvocation.MyCommand.Path | Select-Object -First 30 | ForEach-Object { $_ }
    Show-List
}

function Resolve-Selection {
    $requested = @()
    if ($All) {
        $requested = $ModuleOrder
    } elseif ($Only) {
        foreach ($r in ($Only -split ',')) {
            $r = $r.Trim()
            if (-not $r) { continue }
            if (-not $ModuleDesc.Contains($r)) { Write-Error "Unknown module: $r"; exit 2 }
            $requested += $r
        }
    } else {
        $requested = $ModuleOrder | Where-Object { -not $ModuleOptional.ContainsKey($_) }
    }
    # Order by ModuleOrder so dependencies run first.
    return $ModuleOrder | Where-Object { $requested -contains $_ }
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
    catch { $failed += $m; Write-Log ERROR "modules" "module_failed" "Module $m failed: $($_.Exception.Message)" 1 }
}

# Report
@"
# AI Dev Suite — Engineering Report (Windows)

**Script version:** $ScriptVersion
**Run ID:** $RunId
**Selected modules:** $($selected -join ' ')
**Failed modules:** $(if ($failed) { $failed -join ' ' } else { 'none' })

## Versions
- Node: $(if (Test-Cmd node) { node --version } else { 'n/a' })
- npm:  $(if (Test-Cmd npm) { npm --version } else { 'n/a' })
- Go:   $(if (Test-Cmd go) { (go version) } else { 'n/a' })
- pi:   $(if (Test-Cmd pi) { 'installed' } else { 'n/a' })

Logs: $HumanLog ; $JsonlLog
"@ | Set-Content -Path $ReportFile

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " AI Dev Suite (Windows) setup finished" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Modules : $($selected -join ' ')"
if ($failed) { Write-Host "Failed  : $($failed -join ' ')" -ForegroundColor Yellow }
Write-Host "Report  : $ReportFile"
Write-Host "`nNext: open a new terminal so PATH updates apply."
