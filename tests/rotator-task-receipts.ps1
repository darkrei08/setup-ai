#!/usr/bin/env pwsh
# Legacy Windows rotator cleanup is uninstall-only and requires an unchanged receipt.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Get-Content -LiteralPath (Join-Path $RepoRoot 'setup-ai.ps1') -Raw
if ($Source -match "(?m)^\s*'rotator'\s*=") { throw 'rotator must not remain in the install registry or module map' }
if ($Source -notmatch "'cliproxyapi'\s*=" -or $Source -notmatch 'function Mod-Cliproxyapi') { throw 'CLIProxyAPI module dispatch is missing' }
if ($Source -notmatch 'function Remove-LegacyRotatorTask') { throw 'legacy task cleanup is missing' }

function Get-FunctionSource {
    param([string]$Name)
    $start = $Source.IndexOf("function $Name {")
    if ($start -lt 0) { throw "Missing function $Name" }
    $next = $Source.IndexOf("`nfunction ", $start + 1)
    if ($next -lt 0) { $next = $Source.Length }
    return $Source.Substring($start, $next - $start)
}
$RotatorTaskMarkerPrefix = 'setup-ai-rotator-task-v1'
foreach ($name in @('Get-RotatorTaskFingerprint', 'Get-RotatorTask', 'Get-RotatorTaskReceipt', 'Test-RotatorTaskOwned', 'Remove-LegacyRotatorTask')) {
    Invoke-Expression (Get-FunctionSource -Name $name)
}

$script:Task = $null
$script:UnregisterCalls = 0
function Get-ScheduledTask { param($TaskName, $ErrorAction) return $script:Task }
function Unregister-ScheduledTask { param($TaskName, $Confirm, $ErrorAction) $script:UnregisterCalls++; $script:Task = $null }

function New-FakeTask {
    $task = [pscustomobject]@{
        TaskName = 'tuxevil-rotator'; TaskPath = '\'
        Actions = @([pscustomobject]@{ Execute = 'powershell.exe'; Arguments = '-NoProfile -Command start'; WorkingDirectory = '' })
        Triggers = @([pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' }; Enabled = $true; UserId = 'test-user'; StartBoundary = ''; EndBoundary = ''; Repetition = $null })
        Principal = [pscustomobject]@{ UserId = 'test-user'; LogonType = 'Interactive'; RunLevel = 'Limited' }
        Settings = [pscustomobject]@{ Enabled = $true; MultipleInstances = 'IgnoreNew'; ExecutionTimeLimit = 'PT0S'; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true; Hidden = $true; Priority = 7; WakeToRun = $false; IdleSettings = [pscustomobject]@{ IdleDuration = ''; RestartOnIdle = $false; StopOnIdleEnd = $false; WaitTimeout = '' } }
        Description = ''
    }
    $task.Description = "legacy task [$($RotatorTaskMarkerPrefix)-abc123456789:fp=$(Get-RotatorTaskFingerprint -Task $task)]"
    return $task
}
$script:Task = New-FakeTask
if (-not (Test-RotatorTaskOwned -Task $script:Task)) { throw 'Valid legacy task receipt was not recognized' }
if (-not (Remove-LegacyRotatorTask) -or $script:UnregisterCalls -ne 1 -or $script:Task) { throw 'Exact receipted task was not removed' }

$script:Task = New-FakeTask
$script:Task.Description = 'user-owned task without an ownership receipt'
if (Remove-LegacyRotatorTask -or $script:UnregisterCalls -ne 1 -or -not $script:Task) { throw 'Task without receipt was removed' }

$script:Task = New-FakeTask
$script:Task.Description = "legacy task [$($RotatorTaskMarkerPrefix)-abc123456789:fp=0000000000000000]"
if (Remove-LegacyRotatorTask -or $script:UnregisterCalls -ne 1 -or -not $script:Task) { throw 'Task with a changed fingerprint was removed' }
Write-Host 'PASS: legacy scheduled-task cleanup requires a matching ownership receipt'
