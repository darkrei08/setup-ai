#!/usr/bin/env pwsh
# Behavioral checks for the PowerShell Compose module using an in-memory fake Docker.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Get-Content -LiteralPath (Join-Path $RepoRoot 'setup-ai.ps1') -Raw
$Start = $Source.IndexOf('function Mod-Cliproxyapi {')
$End = $Source.IndexOf("`n`$ModuleFn = @{", $Start)
if ($Start -lt 0 -or $End -lt 0) { throw 'Mod-Cliproxyapi was not found' }
Invoke-Expression $Source.Substring($Start, $End - $Start)

$script:FakeDockerAvailable = $true
$script:FakeComposeAvailable = $true
$script:Calls = @()
$script:Events = @()
$script:RunningServices = @()
$script:ProjectIds = @()
$script:WorkingDirs = @()
function Test-Cmd { param([string]$Name) return ($Name -ne 'docker' -or $script:FakeDockerAvailable) }
$script:Restricted = @()
function icacls { $script:Restricted += ,($args -join ' '); $global:LASTEXITCODE = 0 }
function docker {
    $call = $args -join ' '
    $script:Calls += ,$call
    if ($call -eq 'compose version' -and -not $script:FakeComposeAvailable) { throw 'Compose unavailable' }
    if ($call -like '*ps --status running --services') { return $script:RunningServices }
    if ($call -like '*ps -a -q') { return $script:ProjectIds }
    if ($call -like 'inspect *') { return $script:WorkingDirs }
}
function Write-Log { param($Level,$Phase,$Event,$Message,$Code=0,$Meta=''); $script:Events += "$Event|$Message" }
function Invoke-Step {
    param([string]$Phase,[switch]$Verify,[switch]$Optional,[scriptblock]$Action,[string]$CaptureOutput)
    try { $result = & $Action } catch {
        if ($Optional) { return $false }
        throw
    }
    if ($CaptureOutput) { $result | Set-Content -LiteralPath $CaptureOutput }
    return $true
}

$TestDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
$ScriptDir = $RepoRoot
$env:CLIPROXYAPI_DIR = Join-Path $TestDir 'cliproxyapi'
$script:PostInstallActions = @()
$script:HumanLog = Join-Path $TestDir 'human.log'
New-Item -ItemType Directory -Path $TestDir | Out-Null
try {
    # An absent directory is seeded with local example templates without invoking Docker;
    # a second run never overwrites what the user edited.
    Mod-Cliproxyapi
    if ($script:Calls.Count -ne 0 -or -not ($script:Events -match '^configuration_seeded\|')) { throw 'Missing configuration was not safely seeded' }
    foreach ($f in 'docker-compose.yml', 'config.yaml', 'keeper.env') {
        if (-not (Test-Path -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR $f))) { throw "$f was not seeded" }
    }
    if (-not (Select-String -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Pattern 'REPLACE_WITH' -Quiet)) { throw 'Seeded config lost its placeholders' }
    if (@($script:Restricted).Count -ne 2) { throw "Credential files were not restricted: $($script:Restricted -join '; ')" }
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Value 'edited'
    $script:Events = @()
    Mod-Cliproxyapi
    if ((Get-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml')) -ne 'edited') { throw 'Seeding overwrote a user file' }
    if ($script:Events -match '^configuration_seeded\|') { throw 'Nothing was missing but seeding ran' }
    Remove-Item -LiteralPath $env:CLIPROXYAPI_DIR -Recurse -Force

    # The Git-backed layout is selectable and seeds a single .env with placeholders.
    $env:CLIPROXYAPI_STORAGE = 'gitstore'
    Mod-Cliproxyapi
    if (-not (Select-String -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR '.env') -Pattern 'YOUR_USER' -Quiet)) { throw 'Gitstore .env was not seeded' }
    if (Test-Path -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml')) { throw 'Gitstore seeded local files' }
    Remove-Item Env:CLIPROXYAPI_STORAGE
    # A directory that only has .env is detected as gitstore without any variable.
    Mod-Cliproxyapi
    if (Test-Path -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml')) { throw '.env-only directory was treated as local' }
    Remove-Item -LiteralPath $env:CLIPROXYAPI_DIR -Recurse -Force
    $env:CLIPROXYAPI_STORAGE = 'bogus'
    try { Mod-Cliproxyapi; throw 'Invalid storage was accepted' } catch { if ($_.Exception.Message -eq 'Invalid storage was accepted') { throw } }
    Remove-Item Env:CLIPROXYAPI_STORAGE
    $script:Calls = @()
    $script:Events = @()

    # Placeholders in the other layout's files still block start: the compose file may mount them.
    New-Item -ItemType Directory -Path $env:CLIPROXYAPI_DIR | Out-Null
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'docker-compose.yml') -Value 'services: {}'
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR '.env') -Value 'GITSTORE_GIT_URL=private'
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Value 'api-keys: [REPLACE_WITH_A_LONG_RANDOM_CLIENT_KEY]'
    $env:CLIPROXYAPI_STORAGE = 'gitstore'
    Mod-Cliproxyapi
    Remove-Item Env:CLIPROXYAPI_STORAGE
    if ($script:Calls -like '*up -d') { throw 'Stack started with placeholders in the other layout' }
    Remove-Item -LiteralPath $env:CLIPROXYAPI_DIR -Recurse -Force
    $script:Calls = @()
    $script:Events = @()

    # A directory where a required regular file belongs blocks start before Compose runs.
    foreach ($case in @(@('local', 'config.yaml'), @('local', 'docker-compose.yml'), @('gitstore', '.env'))) {
        New-Item -ItemType Directory -Path $env:CLIPROXYAPI_DIR -Force | Out-Null
        foreach ($f in 'docker-compose.yml', 'config.yaml', 'keeper.env', '.env') { Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR $f) -Value 'private=1' }
        Remove-Item -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR $case[1]) -Force
        New-Item -ItemType Directory -Path (Join-Path $env:CLIPROXYAPI_DIR $case[1]) | Out-Null
        $script:Calls = @(); $script:Events = @()
        $env:CLIPROXYAPI_STORAGE = $case[0]
        $rejected = $false
        try { Mod-Cliproxyapi } catch { $rejected = $true }
        Remove-Item Env:CLIPROXYAPI_STORAGE
        if (-not $rejected) { throw "Directory at $($case[1]) was accepted" }
        if ($script:Calls -like '*up -d') { throw "Compose up ran with a directory at $($case[1])" }
        if (-not ($script:Events -match '^config_not_file\|')) { throw 'Non-file config was not logged' }
        Remove-Item -LiteralPath $env:CLIPROXYAPI_DIR -Recurse -Force
    }
    $script:Calls = @()
    $script:Events = @()

    New-Item -ItemType Directory -Path $env:CLIPROXYAPI_DIR | Out-Null
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'docker-compose.yml') -Value 'services: {}'
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Value 'api-keys: [private]'
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'keeper.env') -Value "CPA_MANAGEMENT_KEY=private`nLOGIN_PASSWORD=private"

    # Prerequisite ordering matches Bash even when configuration also has placeholders.
    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Value 'api-keys: [REPLACE_WITH_PRIVATE_KEY]'
    $script:FakeDockerAvailable = $false
    Mod-Cliproxyapi
    if ($script:Calls.Count -ne 0 -or -not ($script:Events -match '^docker_missing\|')) { throw 'Missing Docker was not safely skipped' }
    if ($script:Events -match '^configuration_placeholder\|') { throw 'PowerShell placeholder check ran before the Docker prerequisite check' }

    Set-Content -LiteralPath (Join-Path $env:CLIPROXYAPI_DIR 'config.yaml') -Value 'api-keys: [private]'
    $script:FakeDockerAvailable = $true
    $script:FakeComposeAvailable = $false
    $script:Events = @()
    Mod-Cliproxyapi
    if (-not ($script:Events -match '^compose_missing\|')) { throw 'Missing Compose was not safely skipped' }
    if ($script:Events -match '^stack_started\|') { throw 'Missing Compose was reported as started' }

    $script:FakeComposeAvailable = $true
    $script:Calls = @()
    $script:Events = @()
    $script:RunningServices = @('cli-proxy-api', 'cpa-usage-keeper')
    Mod-Cliproxyapi
    $dir = $env:CLIPROXYAPI_DIR
    $compose = Join-Path $dir 'docker-compose.yml'
    $expected = @(
        'compose version',
        "compose --project-directory $dir -f $compose config -q",
        "compose --project-directory $dir -f $compose ps -a -q",
        "compose --project-directory $dir -f $compose up -d",
        "compose --project-directory $dir -f $compose ps --status running --services"
    )
    if (($script:Calls -join "`n") -ne ($expected -join "`n")) { throw "Unexpected Docker Compose calls: $($script:Calls -join '; ')" }
    if (-not ($script:Events -match '^stack_started\|')) { throw 'Configured stack success was not logged' }

    # Containers of the same project name started from another directory are not ours.
    $script:ProjectIds = @('abc123')
    $script:WorkingDirs = @('/elsewhere/cliproxyapi')
    $script:Calls = @()
    $script:Events = @()
    try {
        Mod-Cliproxyapi
        throw 'Foreign Compose project was not refused'
    } catch {
        if ($_.Exception.Message -eq 'Foreign Compose project was not refused') { throw }
    }
    if (-not ($script:Events -match '^project_conflict\|')) { throw 'Project conflict was not logged' }
    if ($script:Calls -like '*up -d') { throw 'Compose up ran against a foreign project' }
    # Our own containers (same working dir) are updated normally.
    $script:WorkingDirs = @((Resolve-Path -LiteralPath $env:CLIPROXYAPI_DIR).Path)
    $script:RunningServices = @('cli-proxy-api', 'cpa-usage-keeper')
    Mod-Cliproxyapi
    $script:ProjectIds = @()
    $script:WorkingDirs = @()

    # Compose can exit successfully when one service is stopped.
    $script:Events = @()
    $script:RunningServices = @('cli-proxy-api')
    try {
        Mod-Cliproxyapi
        throw 'Stopped services were reported as running'
    } catch {
        if ($_.Exception.Message -eq 'Stopped services were reported as running') { throw }
    }
    if (-not ($script:Events -match '^stack_not_running\|')) { throw 'Stopped services were not reported' }
    if ($script:Events -match '^stack_started\|') { throw 'Stopped services were reported as started' }
    Write-Host 'PASS: PowerShell configured, missing-config, missing-Docker/Compose, and stopped-service behavior'
} finally {
    Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CLIPROXYAPI_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLIPROXYAPI_STORAGE -ErrorAction SilentlyContinue
}
