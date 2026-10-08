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
$script:DotenvDir = $TestDir
$env:CLIPROXYAPI_DIR = Join-Path $TestDir 'cliproxyapi'
$script:PostInstallActions = @()
$script:HumanLog = Join-Path $TestDir 'human.log'
New-Item -ItemType Directory -Path $TestDir | Out-Null
try {
    # Missing configuration is reported without invoking Docker.
    Mod-Cliproxyapi
    if ($script:Calls.Count -ne 0 -or -not ($script:Events -match '^configuration_missing\|')) { throw 'Missing configuration was not safely skipped' }

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
}
