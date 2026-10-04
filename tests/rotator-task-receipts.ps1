#!/usr/bin/env pwsh
# Focused #104 task-receipt test; extracts production functions and uses fake Task Scheduler cmdlets.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $RepoRoot 'setup-ai.ps1'
$SourceLines = Get-Content -LiteralPath $SourcePath
function Get-FunctionSource {
    param([string[]]$Lines, [string]$Name)
    $capture = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($line -match "^function $Name\b") { $capture = $true }
        elseif ($capture -and $line -match '^function \w') { break }
        if ($capture) { $out.Add($line) }
    }
    return ($out -join "`n")
}
function Get-SingleLine {
    param([string[]]$Lines, [string]$Pattern)
    return ($Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1)
}
$failures = New-Object System.Collections.Generic.List[string]
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}
# ---- Fake Task Scheduler state and Write-Log capture ----
$script:FakeTasks = @{}
$script:FakeRegisterCalls = 0
$script:FakeUnregisterCalls = 0
$script:FakeRegisterCorruptsAction = $false
$script:FakeRegisterCorruptsPrincipal = $false
$script:FakeRegisterThrows = $false
$script:FakeRegisterThrowsAfterCreate = $false
$script:FakeUnregisterThrows = $false
$script:FakeNpmUninstallThrows = $false
$script:FakeNpmRootThrows = $false
$script:RemovalOrder = New-Object System.Collections.Generic.List[string]
$script:FakeGetThrows = $false
$script:FakeReadbackThrows = $false
$script:FakeStartTaskCalls = 0
$script:FakeProcessCalls = 0
function Write-Log {
    param([string]$Level, [string]$Phase, [string]$Event, [string]$Message, [int]$ReturnCode = 0, [string]$Meta = "")
}
function Invoke-Step {
    param([string]$Phase, [scriptblock]$Action, [switch]$Verify, [switch]$Optional, [string]$CaptureOutput = '')
    try { if ($CaptureOutput) { & $Action | Set-Content -LiteralPath $CaptureOutput } else { & $Action | Out-Null } }
    catch { if ($Optional) { return $false }; throw }
    return $true
}
function New-ScheduledTaskAction {
    param([string]$Execute, [string]$Argument)
    [pscustomobject]@{ Execute = $Execute; Arguments = $Argument; WorkingDirectory = $null }
}
function New-ScheduledTaskTrigger {
    param([switch]$AtLogOn, [string]$User, [switch]$Once, [datetime]$At, [TimeSpan]$RepetitionInterval)
    if ($AtLogOn) {
        return [pscustomobject]@{
            CimClass   = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' }
            Enabled    = $true
            UserId       = $User
            StartBoundary = $null
            EndBoundary   = $null
            Repetition    = $null
        }
    }
    # Like the real MSFT_TaskTimeTrigger, a time trigger has no UserId property at all.
    return [pscustomobject]@{
        CimClass   = [pscustomobject]@{ CimClassName = 'MSFT_TaskTimeTrigger' }
        Enabled    = $true
        StartBoundary = $At
        EndBoundary   = $null
        Repetition    = [pscustomobject]@{ Interval = $RepetitionInterval; Duration = $null; StopAtDurationEnd = $false }
    }
}
function New-ScheduledTaskPrincipal {
    param([string]$UserId, [string]$LogonType)
    [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = 'Limited' }
}
function New-ScheduledTaskSettingsSet {
    param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [TimeSpan]$ExecutionTimeLimit, [string]$MultipleInstances)
    [pscustomobject]@{
        Enabled                    = $true
        MultipleInstances          = $MultipleInstances
        ExecutionTimeLimit         = [System.Xml.XmlConvert]::ToString($ExecutionTimeLimit)
        AllowStartIfOnBatteries    = [bool]$AllowStartIfOnBatteries
        DontStopIfGoingOnBatteries = [bool]$DontStopIfGoingOnBatteries
        Hidden                     = $false
        Priority                   = 7
        WakeToRun                  = $false
        IdleSettings               = [pscustomobject]@{ IdleDuration = $null; RestartOnIdle = $false; StopOnIdleEnd = $false; WaitTimeout = $null }
    }
}
# Existing tasks must be guarded before registration.
function Register-ScheduledTask {
    param([string]$TaskName, $Action, $Trigger, $Settings, $Principal, [string]$Description)
    $script:FakeRegisterCalls++
    # Guard: mirrors the real cmdlet without -Force, so an accidental overwrite fails loudly.
    if ($script:FakeTasks.ContainsKey($TaskName)) { throw "fake: task '$TaskName' already exists" }
    if ($script:FakeRegisterThrows) { throw "fake: registration failed" }
    $actions = @($Action)
    if ($script:FakeRegisterCorruptsAction) {
        $actions = @([pscustomobject]@{ Execute = $Action.Execute; Arguments = "corrupted-on-registration" })
    }
    if ($script:FakeRegisterCorruptsPrincipal -and $Principal) {
        $Principal = [pscustomobject]@{ UserId = $Principal.UserId; LogonType = 'S4U'; RunLevel = $Principal.RunLevel }
    }
    $task = [pscustomobject]@{
        TaskName    = $TaskName
        TaskPath    = '\'
        Actions     = $actions
        Triggers    = @($Trigger)
        Settings    = $Settings
        Principal   = $Principal
        Description = $Description
    }
    $script:FakeTasks[$TaskName] = $task
    if ($script:FakeRegisterThrowsAfterCreate) { throw 'fake: registration reported failure after creating the task' }
    return $task
}
function Get-ScheduledTask {
    param([string]$TaskName, $ErrorAction)
    if ($script:FakeGetThrows -eq 'not-found') { $script:FakeGetThrows = $false; throw [System.Runtime.InteropServices.COMException]::new('fake: task not found', -2147024894) }
    if ($script:FakeGetThrows) { throw 'fake: task query failed' }
    if ($script:FakeReadbackThrows -and $script:FakeTasks.ContainsKey($TaskName)) { $script:FakeReadbackThrows = $false; throw 'fake: readback failed' }
    if ($script:FakeTasks.ContainsKey($TaskName)) { return $script:FakeTasks[$TaskName] }
    # The real cmdlet throws a CIM not-found error for a missing task under -ErrorAction Stop.
    $notFound = [System.Management.Automation.ErrorRecord]::new([Exception]::new("No MSFT_ScheduledTask objects found with property 'TaskName' equal to '$TaskName'."), 'CmdletizationQuery_NotFound_TaskName,Get-ScheduledTask', 'ObjectNotFound', $TaskName)
    throw $notFound
}
function Unregister-ScheduledTask {
    param([string]$TaskName, $Confirm, $ErrorAction)
    if (-not $script:FakeTasks.ContainsKey($TaskName)) { throw "fake: no such task '$TaskName'" }
    if ($script:FakeUnregisterThrows) { throw 'fake: unregister failed' }
    $script:FakeTasks.Remove($TaskName)
    $script:FakeUnregisterCalls++
    $script:RemovalOrder.Add('task')
}
function Start-ScheduledTask { param([string]$TaskName) $script:FakeStartTaskCalls++ }
function Start-Process { param($FilePath,$ArgumentList,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError) $script:FakeProcessCalls++ }
# ---- Wire up the real (extracted) functions under test ----
$env:USERNAME = 'test-user'
$markerLine = Get-SingleLine -Lines $SourceLines -Pattern '^\$RotatorTaskMarkerPrefix\s*='
Assert-True -Condition ([bool]$markerLine) -Message 'setup-ai.ps1 defines $RotatorTaskMarkerPrefix'
if ($markerLine) { Invoke-Expression $markerLine }
foreach ($name in @('Get-RotatorExecutable', 'Get-RotatorTask', 'Get-RotatorTaskFingerprint', 'Get-RotatorTaskReceipt', 'Test-RotatorTaskOwned', 'Remove-RotatorTaskRollback', 'Register-RotatorTask', 'Start-RotatorGateway', 'Test-Cmd', 'Test-ExtrasMarker', 'Test-ExtrasNpmPackage', 'Invoke-RotatorUninstall')) {
    $src = Get-FunctionSource -Lines $SourceLines -Name $name
    Assert-True -Condition ([bool]$src) -Message "setup-ai.ps1 defines $name"
    if ($src) { Invoke-Expression $src }
}
# ---- Fingerprint stability ----
$script:FakeGetThrows = 'not-found'
Assert-True -Condition ($null -eq (Get-RotatorTask)) -Message 'Get-RotatorTask treats the native missing-task HRESULT as absence'
$settingsA = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principalA = New-ScheduledTaskPrincipal -UserId 'test-user' -LogonType Interactive
$triggersA = @((New-ScheduledTaskTrigger -AtLogOn -User 'test-user'), (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)))
$taskA = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = @((New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "x"')); Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
$taskB = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = @((New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "x"')); Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
$taskCommandChanged = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = @((New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "y"')); Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
$env:USERDOMAIN = 'DOMAIN'
$fpA = Get-RotatorTaskFingerprint -Task $taskA
$fpB = Get-RotatorTaskFingerprint -Task $taskB
$fpCommandChanged = Get-RotatorTaskFingerprint -Task $taskCommandChanged
Assert-True -Condition ($fpA -eq $fpB) -Message 'fingerprint is stable for identical inputs'
Assert-True -Condition ($fpA -ne $fpCommandChanged) -Message 'fingerprint changes when the command line changes'
# ---- Fingerprint configuration ----
$principalChanged = [pscustomobject]@{ UserId = 'test-user'; LogonType = 'S4U'; RunLevel = 'Limited' }
$taskPrincipalChanged = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersA; Principal = $principalChanged; Settings = $settingsA }
Assert-True -Condition ($fpA -ne (Get-RotatorTaskFingerprint -Task $taskPrincipalChanged)) -Message 'fingerprint changes when the principal changes even though every action is identical'
Assert-True -Condition ($fpA -eq (Get-RotatorTaskFingerprint -Task ([pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersA; Principal = [pscustomobject]@{ UserId = 'DOMAIN\test-user'; LogonType = 'Interactive'; RunLevel = 'Limited' }; Settings = $settingsA }))) -Message 'fingerprint normalizes a domain-qualified principal returned by Task Scheduler'
Assert-True -Condition ($fpA -ne (Get-RotatorTaskFingerprint -Task ([pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersA; Principal = [pscustomobject]@{ UserId = 'OTHER\test-user'; LogonType = 'Interactive'; RunLevel = 'Limited' }; Settings = $settingsA }))) -Message 'fingerprint keeps different principal domains distinct'
$settingsBatteryChanged = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$taskSettingsChanged = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersA; Principal = $principalA; Settings = $settingsBatteryChanged }
Assert-True -Condition ($fpA -ne (Get-RotatorTaskFingerprint -Task $taskSettingsChanged)) -Message 'fingerprint changes when battery settings change even though every action is identical'
$triggersUserChanged = @((New-ScheduledTaskTrigger -AtLogOn -User 'other-user'), $triggersA[1])
$taskTriggerChanged = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersUserChanged; Principal = $principalA; Settings = $settingsA }
Assert-True -Condition ($fpA -ne (Get-RotatorTaskFingerprint -Task $taskTriggerChanged)) -Message 'fingerprint changes when a trigger''s user changes even though every action is identical'
$taskNamed = [pscustomobject]@{ TaskName = 'tuxevil-rotator'; TaskPath = '\'; Actions = $taskA.Actions; Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
Assert-True -Condition ($fpA -ne (Get-RotatorTaskFingerprint -Task $taskNamed)) `
    -Message 'fingerprint changes when the task name differs even though every other field is identical'
# ---- Delimiter collision: raw separators inside one argument never match two actions ----
$taskTwoActions = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = @((New-ScheduledTaskAction -Execute 'a' -Argument 'b'), (New-ScheduledTaskAction -Execute 'c' -Argument 'd')); Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
$taskCollision = [pscustomobject]@{ TaskName = 'task'; TaskPath = '\'; Actions = @((New-ScheduledTaskAction -Execute 'a' -Argument 'b;c|d')); Triggers = $triggersA; Principal = $principalA; Settings = $settingsA }
Assert-True -Condition ((Get-RotatorTaskFingerprint -Task $taskTwoActions) -ne (Get-RotatorTaskFingerprint -Task $taskCollision)) -Message 'fingerprint does not collide when an argument contains raw delimiter characters'
# ---- Receipt parsing ----
Assert-True -Condition ($null -eq (Get-RotatorTaskReceipt -Task $null)) -Message 'receipt is null for a null task'
$noDescTask = [pscustomobject]@{ Description = $null }
Assert-True -Condition ($null -eq (Get-RotatorTaskReceipt -Task $noDescTask)) -Message 'receipt is null when description is missing'
$malformedTask = [pscustomobject]@{ Description = 'a user task with no receipt' }
Assert-True -Condition ($null -eq (Get-RotatorTaskReceipt -Task $malformedTask)) -Message 'receipt is null when description has no marker'
$validTask = [pscustomobject]@{ Description = "x [$($RotatorTaskMarkerPrefix)-abc123456789:fp=abc0123456789def]" }
$parsed = Get-RotatorTaskReceipt -Task $validTask
Assert-True -Condition ($parsed -and $parsed.Marker -eq "$($RotatorTaskMarkerPrefix)-abc123456789" -and $parsed.Fingerprint -eq 'abc0123456789def') `
    -Message 'receipt parses a well-formed marker and fingerprint'
# ---- Fresh install ----
$script:FakeTasks = @{}
$script:FakeRegisterCalls = 0
$script:FakeUnregisterCalls = 0
$script:FakeRegisterCorruptsAction = $false
$result = Register-RotatorTask
Assert-True -Condition ($result -eq $true) -Message 'Register-RotatorTask returns true on a clean install'
Assert-True -Condition ($script:FakeTasks.ContainsKey('tuxevil-rotator')) -Message 'Register-RotatorTask leaves the task registered on success'
$receipt = Get-RotatorTaskReceipt -Task $script:FakeTasks['tuxevil-rotator']
Assert-True -Condition ($receipt -and $receipt.Marker -like "$($RotatorTaskMarkerPrefix)-*") -Message 'the created task carries this installer''s marker family'
$firstMarker = if ($receipt) { $receipt.Marker } else { $null }
# ---- Existing installer-owned task is preserved ----
$ownedTask = $script:FakeTasks['tuxevil-rotator']
$script:FakeRegisterCalls = 0
$result2 = Register-RotatorTask
Assert-True -Condition ($result2 -eq $false) -Message 'Register-RotatorTask fails closed when an installer-owned task already exists'
Assert-True -Condition ($script:FakeRegisterCalls -eq 0) -Message 'Register-RotatorTask does not replace an existing installer-owned task'
Assert-True -Condition ([object]::ReferenceEquals($script:FakeTasks['tuxevil-rotator'], $ownedTask)) -Message 'an existing installer-owned task is left byte-for-byte untouched'
Assert-True -Condition ((Get-RotatorTaskReceipt -Task $script:FakeTasks['tuxevil-rotator']).Marker -eq $firstMarker) -Message 'preserving an installer-owned task keeps its existing marker'
# ---- Pre-existing task ----
$preexisting = [pscustomobject]@{ TaskName = 'tuxevil-rotator'; Description = 'a user-made task'; Actions = @(); Triggers = @(); Settings = $null }
$script:FakeTasks = @{ 'tuxevil-rotator' = $preexisting }
$script:FakeRegisterCalls = 0
$result = Register-RotatorTask
Assert-True -Condition ($result -eq $false) -Message 'Register-RotatorTask returns false when a task already exists'
Assert-True -Condition ($script:FakeRegisterCalls -eq 0) -Message 'Register-RotatorTask never calls Register-ScheduledTask when a task already exists'
Assert-True -Condition ([object]::ReferenceEquals($script:FakeTasks['tuxevil-rotator'], $preexisting)) -Message 'a pre-existing task is left byte-for-byte untouched'
# ---- Verification rollback ----
$script:FakeTasks = @{}
$script:FakeUnregisterCalls = 0
$script:FakeRegisterCorruptsAction = $true
$result = Register-RotatorTask
Assert-True -Condition ($result -eq $false) -Message 'Register-RotatorTask returns false when receipt/settings verification fails'
Assert-True -Condition (-not $script:FakeTasks.ContainsKey('tuxevil-rotator')) -Message 'Register-RotatorTask rolls back a task it created when verification fails'
Assert-True -Condition ($script:FakeUnregisterCalls -eq 1) -Message 'rollback calls Unregister-ScheduledTask exactly once'
$script:FakeRegisterCorruptsAction = $false
# ---- Fingerprint drift rollback ----
$script:FakeTasks = @{}
$script:FakeUnregisterCalls = 0
$script:FakeRegisterCorruptsPrincipal = $true
$result = Register-RotatorTask
Assert-True -Condition ($result -eq $false) -Message 'Register-RotatorTask returns false when the readback fingerprint does not match the embedded receipt'
Assert-True -Condition (-not $script:FakeTasks.ContainsKey('tuxevil-rotator')) -Message 'a fingerprint mismatch on a non-action field rolls back the task this run just created'
Assert-True -Condition ($script:FakeUnregisterCalls -eq 1) -Message 'rollback fires exactly once on a fingerprint mismatch'
$script:FakeRegisterCorruptsPrincipal = $false
$script:FakeTasks = @{}; $script:FakeUnregisterCalls = 0; $script:FakeReadbackThrows = $true
$result = Register-RotatorTask
Assert-True -Condition ($result -eq $false -and -not $script:FakeTasks.ContainsKey('tuxevil-rotator') -and $script:FakeUnregisterCalls -eq 1) -Message 'a readback exception rolls back the task this run created'
# ---- Registration fails before creating anything ----
$script:FakeTasks = @{}; $script:FakeUnregisterCalls = 0; $script:FakeRegisterThrows = $true
$result = Register-RotatorTask; $script:FakeRegisterThrows = $false
Assert-True -Condition ($result -eq $false -and -not $script:FakeTasks.ContainsKey('tuxevil-rotator') -and $script:FakeUnregisterCalls -eq 0) -Message 'a registration that creates nothing has nothing to roll back'
# ---- Registration creates the task, then reports failure ----
$script:FakeTasks = @{}; $script:FakeUnregisterCalls = 0; $script:FakeRegisterThrowsAfterCreate = $true
$result = Register-RotatorTask; $script:FakeRegisterThrowsAfterCreate = $false
Assert-True -Condition ($result -eq $false -and -not $script:FakeTasks.ContainsKey('tuxevil-rotator') -and $script:FakeUnregisterCalls -eq 1) -Message 'a task left by a registration error is rolled back by its marker and fingerprint'
# ---- Mismatching marker is preserved ----
$script:FakeTasks = @{ 'tuxevil-rotator' = [pscustomobject]@{ TaskName = 'tuxevil-rotator'; Description = "x [$($RotatorTaskMarkerPrefix)-deadbeefcafe:fp=abc0123456789def]" } }
$script:FakeUnregisterCalls = 0
Remove-RotatorTaskRollback -ExpectedMarker "$($RotatorTaskMarkerPrefix)-000000000000" -ExpectedFingerprint 'abc0123456789def'
Assert-True -Condition ($script:FakeTasks.ContainsKey('tuxevil-rotator')) -Message 'rollback never removes a task carrying a different ownership marker'
Assert-True -Condition ($script:FakeUnregisterCalls -eq 0) -Message 'rollback does not call Unregister-ScheduledTask for a mismatched marker'
$script:FakeTasks = @{ 'tuxevil-rotator' = [pscustomobject]@{ TaskName = 'tuxevil-rotator'; Description = "x [$($RotatorTaskMarkerPrefix)-000000000000:fp=badbadbadbadbadb]" } }
Remove-RotatorTaskRollback -ExpectedMarker "$($RotatorTaskMarkerPrefix)-000000000000" -ExpectedFingerprint 'abc0123456789def'
Assert-True -Condition ($script:FakeTasks.ContainsKey('tuxevil-rotator')) -Message 'rollback never removes a task with a mismatched expected fingerprint'
$script:FakeTasks = @{}; [void](Register-RotatorTask); $script:FakeTasks['tuxevil-rotator'].Description = $script:FakeTasks['tuxevil-rotator'].Description -replace 'fp=[0-9a-f]{16}', 'fp=0000000000000000'
$script:FakeStartTaskCalls = 0; $script:FakeProcessCalls = 0; [void](Start-RotatorGateway -LogFile 'ignored')
Assert-True -Condition ($script:FakeStartTaskCalls -eq 0 -and $script:FakeProcessCalls -eq 1) -Message 'an unowned task is not started by the gateway helper'
# ---- Uninstall: task before package, and only receipt-owned state ----
$script:NpmRoot = Join-Path ([IO.Path]::GetTempPath()) ('setup-ai-rotator-npm-' + [guid]::NewGuid().ToString('N'))
$pkgDir = Join-Path $script:NpmRoot 'tuxevil-rotator'
function npm {
    if ($args[0] -eq 'root') { if ($script:FakeNpmRootThrows) { throw 'fake: npm root failed' }; return $script:NpmRoot }
    if ($args[0] -eq 'uninstall') {
        $script:RemovalOrder.Add('npm')
        if ($script:FakeNpmUninstallThrows) { throw 'fake: npm uninstall failed' }
        Remove-Item -Recurse -Force -LiteralPath $pkgDir
    }
}
function Reset-RotatorState { param([string]$Marker, [switch]$OwnedTask, $Task)
    $script:FakeTasks = @{}; $script:RemovalOrder.Clear(); $script:FakeUnregisterThrows = $false; $script:FakeNpmUninstallThrows = $false; $script:FakeNpmRootThrows = $false; $script:FakeGetThrows = $false
    if ($OwnedTask) { [void](Register-RotatorTask) } elseif ($Task) { $script:FakeTasks['tuxevil-rotator'] = $Task }
    Remove-Item -Recurse -Force -LiteralPath $pkgDir -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
    Set-Content -LiteralPath (Join-Path $pkgDir 'package.json') -Value '{"name":"tuxevil-rotator"}'
    if ($Marker) { [IO.File]::WriteAllText((Join-Path $pkgDir '.setup-ai-owned'), "$Marker`n") } }
$owned = 'setup-ai rotator npm-global tuxevil-rotator'
try {
    Reset-RotatorState -Marker $owned -OwnedTask; $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition ($r -and ($script:RemovalOrder -join ',') -eq 'task,npm' -and -not (Test-Path $pkgDir)) -Message 'uninstall removes the owned task before the marked npm package'
    Reset-RotatorState -Marker $owned -OwnedTask; $r = Invoke-RotatorUninstall 6>$null
    Assert-True -Condition ($r -and $script:RemovalOrder.Count -eq 0 -and (Test-Path $pkgDir)) -Message 'uninstall without -Yes only reports'
    Reset-RotatorState -Marker $owned -Task ([pscustomobject]@{ TaskName = 'tuxevil-rotator'; Description = 'a user-made task' }); $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition ($r -and $script:RemovalOrder.Count -eq 0 -and (Test-Path $pkgDir)) -Message 'an unowned task keeps itself and the npm package'
    Reset-RotatorState -Marker $owned -OwnedTask; $script:FakeGetThrows = 'query-failed'; $r = Invoke-RotatorUninstall -Confirmed 6>$null; $script:FakeGetThrows = $false
    Assert-True -Condition (-not $r -and $script:RemovalOrder.Count -eq 0 -and (Test-Path $pkgDir)) -Message 'unknown task state fails without removing anything'
    Reset-RotatorState -Marker $owned -OwnedTask; $script:FakeUnregisterThrows = $true; $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition (-not $r -and (Test-Path $pkgDir)) -Message 'a failed task removal keeps the npm package'
    Reset-RotatorState -Marker 'setup-ai extras npm-global tuxevil-rotator'; $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition ($r -and $script:RemovalOrder.Count -eq 0 -and (Test-Path $pkgDir)) -Message 'a package without the rotator marker is preserved'
    Reset-RotatorState -Marker $owned -OwnedTask; $script:FakeNpmUninstallThrows = $true; $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition (-not $r -and (Test-Path $pkgDir) -and (Test-Path (Join-Path $pkgDir '.setup-ai-owned'))) -Message 'a failed npm removal preserves the package and receipt'
    Reset-RotatorState -Marker $owned -OwnedTask; $script:FakeNpmRootThrows = $true; $r = Invoke-RotatorUninstall -Confirmed 6>$null
    Assert-True -Condition ($r -and ($script:RemovalOrder -join ',') -eq 'task' -and (Test-Path $pkgDir)) -Message 'an unavailable npm root skips the package like Bash and still removes the owned task'
} finally { Remove-Item -Recurse -Force -LiteralPath $script:NpmRoot -ErrorAction SilentlyContinue }
if ($failures.Count -gt 0) {
    Write-Host "FAIL ($($failures.Count)):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
Write-Host 'PASS: all assertions passed' -ForegroundColor Green
exit 0
