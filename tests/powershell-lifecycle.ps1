$ErrorActionPreference = 'Stop'
$setup = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-ai.ps1'
$pwsh = (Get-Process -Id $PID).Path
$logs = Join-Path (Split-Path -Parent $PSScriptRoot) 'logs'
$testLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ('setup-ai-lifecycle-' + [Guid]::NewGuid().ToString('N'))

function Get-LogSnapshot {
    if (-not (Test-Path -LiteralPath $logs -PathType Container)) { return '<absent>' }
    $entries = @(Get-ChildItem -LiteralPath $logs -Force | Sort-Object Name | ForEach-Object {
        '{0}:{1}:{2}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc.Ticks
    })
    return ('{0}|{1}' -f (Get-Item -LiteralPath $logs).LastWriteTimeUtc.Ticks, ($entries -join ';'))
}

$initialLogs = Get-LogSnapshot
function Invoke-SetupAi {
    param([string[]]$Arguments)
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $testLocalAppData
        $output = & $pwsh -NoLogo -NoProfile -File $setup @Arguments 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    } finally {
        [System.Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
    }
}
function Assert-Contains {
    param([string]$Text, [string]$Expected)
    if (-not $Text.Contains($Expected)) { throw "Expected output to contain: $Expected`n$Text" }
}
function Assert-LogsUnchanged {
    if ((Get-LogSnapshot) -ne $initialLogs) { throw 'Lifecycle command created or changed persistent logs.' }
}
function Assert-InventorySelection {
    param($Result, [string[]]$Expected)
    $actual = @($Result.Output -split '\r?\n' | ForEach-Object {
        if ($_ -match "^\s+module '([^']+)':") { $Matches[1] }
        elseif ($_ -match '^\s+shell:') { 'shell' }
    })
    if (($actual -join ',') -ne ($Expected -join ',')) {
        throw "Expected inventory selection '$($Expected -join ',')', got '$($actual -join ',')'."
    }
}

$unownedInventory = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'rotator')
if ($unownedInventory.ExitCode -ne 0) { throw "Unowned rotator inventory exited $($unownedInventory.ExitCode):`n$($unownedInventory.Output)" }
Assert-Contains $unownedInventory.Output 'rotator npm package: not covered - missing or mismatched ownership receipt; legacy packages are protected.'
if ($unownedInventory.Output -notmatch 'rotator task: (state unknown; task query failed|not present \(task query succeeded\)|protected;|receipt-backed and removable)') { throw 'Uninstall inventory did not distinguish an unknown or proven task state.' }
Assert-LogsUnchanged

$tokens = $null; $parseErrors = $null
$sourceAst = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Raw -LiteralPath $setup), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "setup-ai.ps1 has parse errors: $($parseErrors -join '; ')" }
$piFunctionNames = @('Get-PiPackageIdentity','Get-PiPackageRegistrationState','Get-PiPackageReceiptPath','Test-PiPackageReceiptLocation','Get-PiPackageReceiptState','Write-PiPackageReceipt','Assert-PiPackageRegistered','Install-PiPackageOwned','Get-PiPackageInventoryStatus','Restore-PiPackageRegistration','Restore-PiPackageReceipt','Remove-PiPackageRegistration')
$piFunctions = @($sourceAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $piFunctionNames }, $true))
if ($piFunctions.Count -ne $piFunctionNames.Count) { throw 'Expected Pi registration identity, receipt, install, inventory, and removal functions in setup-ai.ps1.' }
foreach ($functionAst in $piFunctions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$openCodeFunctionNames = @('Get-OpenCodeUserEnvironmentValue','Set-OpenCodeUserEnvironmentValue','Get-OpenCodeEnvReceiptPath','Test-OpenCodeEnvReceiptLocation','Get-OpenCodeEnvReceiptState','Write-OpenCodeEnvReceipt','Get-OpenCodeEnvInventoryStatus','Remove-OpenCodeUserEnvironment')
$openCodeFunctions = @($sourceAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $openCodeFunctionNames }, $true))
if ($openCodeFunctions.Count -ne $openCodeFunctionNames.Count) { throw 'Expected receipt-backed OpenCode environment ownership functions in setup-ai.ps1.' }
foreach ($functionAst in $openCodeFunctions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$openCodeFakeUserValue = $null
function Get-OpenCodeUserEnvironmentValue { param([string]$Name) return $script:openCodeFakeUserValue }
function Set-OpenCodeUserEnvironmentValue { param([string]$Name, $Value) $script:openCodeFakeUserValue = $Value }
$localAppDataBeforeOpenCode = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $testLocalAppData 'opencode-state'
    $script:openCodeFakeUserValue = $null
    $openCodeValue = 'C:\\Users\\alice\\AppData\\Roaming\\npm\\node_modules\\opencode-ai\\bin\\opencode.exe'
    if (-not (Write-OpenCodeEnvReceipt -Value $openCodeValue)) { throw 'Fresh OpenCode environment ownership receipt was not written.' }
    $openCodeReceiptPath = Get-OpenCodeEnvReceiptPath
    if (-not (Test-Path -LiteralPath $openCodeReceiptPath -PathType Leaf)) { throw 'OpenCode environment receipt is missing.' }
    Set-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN' -Value $openCodeValue
    $inventoryBefore = [System.IO.File]::ReadAllText($openCodeReceiptPath)
    $openCodeStatus = Get-OpenCodeEnvInventoryStatus
    if ($openCodeStatus.State -cne 'receipt-backed') { throw "Matching OpenCode environment value was not inventoried as receipt-backed: state=$($openCodeStatus.State);message=$($openCodeStatus.Message);receipt=$([System.IO.File]::ReadAllText($openCodeReceiptPath))" }
    if ([System.IO.File]::ReadAllText($openCodeReceiptPath) -cne $inventoryBefore) { throw 'OpenCode inventory mutated its receipt.' }
    Set-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN' -Value 'C:\\Users\\alice\\other.exe'
    if ((Get-OpenCodeEnvInventoryStatus).State -cne 'protected' -or (Remove-OpenCodeUserEnvironment -Confirmed)) { throw 'Changed OpenCode environment value was removable.' }
    if (-not (Test-Path -LiteralPath $openCodeReceiptPath -PathType Leaf)) { throw 'Changed OpenCode environment value lost its receipt.' }
    Set-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN' -Value $openCodeValue
    if (-not (Remove-OpenCodeUserEnvironment -Confirmed)) { throw "Receipt-backed OpenCode environment removal failed: value=$script:openCodeFakeUserValue;state=$((Get-OpenCodeEnvInventoryStatus).State);receipt=$([bool](Test-Path -LiteralPath $openCodeReceiptPath));failure=$script:OpenCodeEnvRemovalFailed" }
    if ($null -ne (Get-OpenCodeUserEnvironmentValue -Name 'OPENCODE_PI_BIN') -or (Test-Path -LiteralPath $openCodeReceiptPath)) { throw 'OpenCode environment removal left state behind.' }
} finally {
    $script:openCodeFakeUserValue = $null
    $env:LOCALAPPDATA = $localAppDataBeforeOpenCode
}

$script:PiAgentDir = Join-Path $testLocalAppData 'pi-agent-test'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'pi-state-test'
$script:PiTestSpec = 'npm:@example/scoped-pkg@1.0.0'
$script:PiFakeCalls = 0
$script:PiFakeRemoves = 0
$script:PiFakeInstallMode = 'fresh'
$script:PiFakeNoopInstall = $false
$script:PiFakeFailRemove = $false
$script:PiFakeChangeReceipt = $false
function Write-Log { param($Level, $Phase, $Event, $Message, $ReturnCode, $Detail) }
function Invoke-Step {
    param([string]$Phase, [scriptblock]$Action, [switch]$Verify, [switch]$Optional)
    & $Action
    if ($global:LASTEXITCODE -ne 0) { throw "Fake command exited $global:LASTEXITCODE" }
    return $true
}
function Set-PiTestCase {
    param([string]$Name)
    $script:PiAgentDir = Join-Path $testLocalAppData "pi-$Name-agent"
    $env:LOCALAPPDATA = Join-Path $testLocalAppData "pi-$Name-state"
    [void][System.IO.Directory]::CreateDirectory($script:PiAgentDir)
    $script:PiFakeInstallMode = 'fresh'
    $script:PiFakeNoopInstall = $false
    $script:PiFakeFailRemove = $false
    $script:PiFakeChangeReceipt = $false
    $script:PiFakeRemoves = 0
}
function Write-PiTestSettings($Settings) {
    [System.IO.File]::WriteAllText((Join-Path $script:PiAgentDir 'settings.json'), ($Settings | ConvertTo-Json -Compress -Depth 10))
}
function pi {
    $script:PiFakeCalls++
    $operation = [string]$args[0]
    $spec = [string]$args[1]
    $settingsPath = Join-Path $script:PiAgentDir 'settings.json'
    if ($operation -ceq 'install') {
        if ($script:PiFakeNoopInstall) { $global:LASTEXITCODE = 0; return }
        $settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) { Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json } else { [pscustomobject]@{ packages = @() } }
        $source = if ($script:PiFakeInstallMode -ceq 'mismatch') { 'npm:wrong-package' } else { $spec }
        $settings.packages = @($settings.packages) + $source
        if ($script:PiFakeInstallMode -ceq 'duplicate') { $settings.packages = @($settings.packages) + $source }
        Write-PiTestSettings $settings
        $global:LASTEXITCODE = 0
        return
    }
    if ($operation -ceq 'remove') {
        $script:PiFakeRemoves++
        if ($script:PiFakeFailRemove) { $global:LASTEXITCODE = 7; return }
        $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
        $wanted = Get-PiPackageIdentity -Spec $spec -BaseDir $script:PiAgentDir
        $settings.packages = @($settings.packages | Where-Object {
            $source = if ($_ -is [string]) { [string]$_ } elseif ($null -ne $_.PSObject.Properties['source']) { [string]$_.source } else { '' }
            -not $source -or (Get-PiPackageIdentity -Spec $source -BaseDir $script:PiAgentDir) -cne $wanted
        })
        Write-PiTestSettings $settings
        if ($script:PiFakeChangeReceipt) { [System.IO.File]::WriteAllText((Get-PiPackageReceiptPath -Spec $spec), 'changed during remove') }
        $global:LASTEXITCODE = 0
        return
    }
    throw "Unexpected fake pi command: $($args -join ' ')"
}

$piIdentityAgent = Join-Path $testLocalAppData 'pi-identity-agent'
if ((Get-PiPackageIdentity -Spec 'npm:@example/scoped-pkg@1.0.0' -BaseDir $piIdentityAgent) -cne (Get-PiPackageIdentity -Spec 'npm:@example/scoped-pkg@2.0.0' -BaseDir $piIdentityAgent)) { throw 'Pi npm scope/version normalization differs.' }
if ((Get-PiPackageIdentity -Spec 'git:github.com/owner/repo.git#v1' -BaseDir $piIdentityAgent) -cne (Get-PiPackageIdentity -Spec 'git:github.com/owner/repo@v2' -BaseDir $piIdentityAgent)) { throw 'Pi git ref normalization differs.' }
if ((Get-PiPackageIdentity -Spec 'extensions/local-package' -BaseDir $piIdentityAgent) -cne (Get-PiPackageIdentity -Spec (Join-Path $piIdentityAgent 'extensions/local-package') -BaseDir $piIdentityAgent)) { throw 'Pi relative package path was not resolved against the agent directory.' }

Set-PiTestCase fresh
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
$piReceiptPath = Get-PiPackageReceiptPath -Spec $script:PiTestSpec
if (-not (Test-Path -LiteralPath $piReceiptPath -PathType Leaf)) { throw 'Fresh Pi registration did not publish its receipt.' }
if ((Get-PiPackageInventoryStatus -Spec $script:PiTestSpec).State -cne 'receipt-backed') { throw 'Fresh Pi registration was not inventoried as receipt-backed.' }

Set-PiTestCase existing
Write-PiTestSettings ([pscustomobject]@{ packages = @('npm:@example/scoped-pkg@0.9.0') })
$script:PiFakeNoopInstall = $true
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
if (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec)) { throw 'Pre-existing or upgraded Pi registration was claimed.' }
if ((Get-PiPackageInventoryStatus -Spec $script:PiTestSpec).State -cne 'protected') { throw 'Pre-existing Pi registration was not protected.' }

Set-PiTestCase mismatch
$script:PiFakeInstallMode = 'mismatch'
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Mismatched Pi readback was accepted.' } catch { if ($_.Exception.Message -eq 'Mismatched Pi readback was accepted.') { throw } }
if (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec)) { throw 'Mismatched Pi registration received a receipt.' }

Set-PiTestCase malformed
[System.IO.File]::WriteAllText((Join-Path $script:PiAgentDir 'settings.json'), '{bad json')
$piCallsBefore = $script:PiFakeCalls
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Malformed Pi settings were accepted.' } catch { if ($_.Exception.Message -eq 'Malformed Pi settings were accepted.') { throw } }
if ($script:PiFakeCalls -ne $piCallsBefore) { throw 'pi ran despite malformed pre-install settings.' }

Set-PiTestCase unreadable
[void][System.IO.Directory]::CreateDirectory((Join-Path $script:PiAgentDir 'settings.json'))
$piCallsBefore = $script:PiFakeCalls
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Unreadable Pi settings were accepted.' } catch { if ($_.Exception.Message -eq 'Unreadable Pi settings were accepted.') { throw } }
if ($script:PiFakeCalls -ne $piCallsBefore) { throw 'pi ran despite unreadable pre-install settings.' }

Set-PiTestCase duplicate
Write-PiTestSettings ([pscustomobject]@{ packages = @('npm:@example/scoped-pkg@0.9.0','npm:@example/scoped-pkg@2.0.0') })
$script:PiFakeNoopInstall = $true
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Duplicate normalized Pi registrations were accepted.' } catch { if ($_.Exception.Message -eq 'Duplicate normalized Pi registrations were accepted.') { throw } }
if (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec)) { throw 'Duplicate Pi registration received a receipt.' }
if ((Get-PiPackageInventoryStatus -Spec $script:PiTestSpec).State -cne 'protected') { throw 'Duplicate Pi registration was not protected.' }

Set-PiTestCase duplicate-after
$script:PiFakeInstallMode = 'duplicate'
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Duplicate post-install Pi readback was accepted.' } catch { if ($_.Exception.Message -eq 'Duplicate post-install Pi readback was accepted.') { throw } }
if (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec)) { throw 'Duplicate post-install registration received a receipt.' }

Set-PiTestCase receipt-collision
$piReceiptPath = Get-PiPackageReceiptPath -Spec $script:PiTestSpec
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $piReceiptPath))
[System.IO.File]::WriteAllText($piReceiptPath, 'preserve existing receipt')
try { Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec; throw 'Pi receipt collision was reported as owned.' } catch { if ($_.Exception.Message -eq 'Pi receipt collision was reported as owned.') { throw } }
if ([System.IO.File]::ReadAllText($piReceiptPath) -cne 'preserve existing receipt' -or (Get-PiPackageRegistrationState -Spec $script:PiTestSpec).Count -ne 1) { throw 'Receipt collision changed the receipt or registration.' }

Set-PiTestCase inventory
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
$piReceiptPath = Get-PiPackageReceiptPath -Spec $script:PiTestSpec
$settingsBefore = [System.IO.File]::ReadAllText((Join-Path $script:PiAgentDir 'settings.json'))
$receiptBefore = [System.IO.File]::ReadAllText($piReceiptPath)
$piCallsBefore = $script:PiFakeCalls
if ((Get-PiPackageInventoryStatus -Spec $script:PiTestSpec).State -cne 'receipt-backed' -or (Get-PiPackageReceiptState -Spec $script:PiTestSpec).Valid -ne $true) { throw 'Pi inventory lost a valid receipt-backed registration.' }
if ([System.IO.File]::ReadAllText((Join-Path $script:PiAgentDir 'settings.json')) -cne $settingsBefore -or [System.IO.File]::ReadAllText($piReceiptPath) -cne $receiptBefore -or $script:PiFakeCalls -ne $piCallsBefore) { throw 'Pi inventory mutated settings/receipt or invoked pi.' }
if (Remove-PiPackageRegistration -Spec $script:PiTestSpec -Confirmed -DryRun) { throw 'Pi dry-run reported removal.' }
if ([System.IO.File]::ReadAllText((Join-Path $script:PiAgentDir 'settings.json')) -cne $settingsBefore -or [System.IO.File]::ReadAllText($piReceiptPath) -cne $receiptBefore -or $script:PiFakeCalls -ne $piCallsBefore) { throw 'Pi dry-run mutated state or invoked pi.' }

Set-PiTestCase changed
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
Write-PiTestSettings ([pscustomobject]@{ packages = @('npm:replacement-package') })
if ((Get-PiPackageInventoryStatus -Spec $script:PiTestSpec).State -cne 'protected') { throw 'Changed Pi registration with a stale receipt was not protected.' }
$script:PiFakeCalls = 0
if (Remove-PiPackageRegistration -Spec $script:PiTestSpec -Confirmed) { throw 'Changed Pi registration was removed or reported successful.' }
if ($script:PiFakeCalls -ne 0 -or -not (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec))) { throw 'Changed Pi registration invoked pi or deleted its receipt.' }

Set-PiTestCase remove-failure
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
$script:PiFakeFailRemove = $true
if (Remove-PiPackageRegistration -Spec $script:PiTestSpec -Confirmed) { throw 'Failed Pi remove was reported successful.' }
if ((Get-PiPackageRegistrationState -Spec $script:PiTestSpec).Count -ne 1 -or -not (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec))) { throw 'Failed Pi remove did not preserve registration and receipt.' }

Set-PiTestCase receipt-change-during-remove
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
$piReceiptPath = Get-PiPackageReceiptPath -Spec $script:PiTestSpec
$script:PiFakeChangeReceipt = $true
if (Remove-PiPackageRegistration -Spec $script:PiTestSpec -Confirmed) { throw 'Pi receipt change during removal was reported as successful.' }
$script:PiFakeChangeReceipt = $false
if ((Get-PiPackageRegistrationState -Spec $script:PiTestSpec).Count -ne 1 -or [System.IO.File]::ReadAllText($piReceiptPath) -cne 'changed during remove') { throw 'Pi receipt verification failure did not restore the registration and preserve the raced receipt.' }

Set-PiTestCase removal
Install-PiPackageOwned -Phase test -Spec $script:PiTestSpec
$piSettingsPath = Join-Path $script:PiAgentDir 'settings.json'
Write-PiTestSettings ([pscustomobject]@{ packages = @('npm:@example/scoped-pkg@1.0.0','npm:unrelated-package') })
[System.IO.File]::WriteAllText((Join-Path $script:PiAgentDir 'auth.json'), 'auth-sentinel')
[void][System.IO.Directory]::CreateDirectory((Join-Path $script:PiAgentDir 'sessions'))
[void][System.IO.Directory]::CreateDirectory((Join-Path $script:PiAgentDir 'npm/node_modules/keep-me'))
[System.IO.File]::WriteAllText((Join-Path (Join-Path $script:PiAgentDir 'sessions') 'keep'), 'session-sentinel')
[System.IO.File]::WriteAllText((Join-Path (Join-Path $script:PiAgentDir 'npm/node_modules/keep-me') 'data'), 'package-sentinel')
if (-not (Remove-PiPackageRegistration -Spec $script:PiTestSpec -Confirmed)) { throw 'Receipt-backed Pi registration removal failed.' }
if ($script:PiFakeRemoves -lt 1) { throw 'Receipt-backed Pi removal did not call fake pi remove.' }
if ((Get-PiPackageRegistrationState -Spec $script:PiTestSpec).Count -ne 0 -or (Get-PiPackageRegistrationState -Spec 'npm:unrelated-package').Count -ne 1) { throw 'Pi removal changed more than its exact registration.' }
if (Test-Path -LiteralPath (Get-PiPackageReceiptPath -Spec $script:PiTestSpec)) { throw 'Successful Pi removal left its receipt.' }
if (-not (Test-Path -LiteralPath $piSettingsPath) -or -not (Test-Path -LiteralPath (Join-Path $script:PiAgentDir 'auth.json')) -or -not (Test-Path -LiteralPath (Join-Path (Join-Path $script:PiAgentDir 'sessions') 'keep')) -or -not (Test-Path -LiteralPath (Join-Path (Join-Path $script:PiAgentDir 'npm/node_modules/keep-me') 'data'))) { throw 'Pi root, settings, auth, sessions, or package data was deleted.' }

$functionNames = @('Get-RotatorTaskFingerprint','Test-RotatorTaskOwnership','Test-RotatorReceiptPathSafe','Write-RotatorTaskReceipt','Test-RotatorTaskCleanupGuard','Get-RotatorActionArguments','Test-RotatorTaskActionCurrent')
$ownershipFunctions = @($sourceAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames }, $true))
if ($ownershipFunctions.Count -ne $functionNames.Count) { throw 'Expected rotator ownership, receipt, path, cleanup, and action functions in setup-ai.ps1.' }
foreach ($functionAst in $ownershipFunctions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$marker = '9a59dfd0-ffcf-4a29-b04d-a74ea2709852'
$testExecutable = 'C:\Tools\tuxevil-rotator.cmd'
$testActionArguments = Get-RotatorActionArguments -Executable $testExecutable
function New-TestRotatorTask {
    param([string]$OwnerMarker = $marker)
    [pscustomobject]@{
        TaskName = 'tuxevil-rotator'; TaskPath = '\';
        Description = "tuxevil-rotator multi-account Gemini/Antigravity gateway on http://localhost:51200 [setup-ai-rotator-owner:$OwnerMarker]"
        Actions = @([pscustomobject]@{ Execute = 'powershell.exe'; Arguments = $testActionArguments; WorkingDirectory = '' })
        Principal = [pscustomobject]@{ UserId = 'DOMAIN\alice'; GroupId = ''; LogonType = 'Interactive'; RunLevel = 'Limited'; ProcessTokenSidType = 'Default'; RequiredPrivileges = @() }
        Triggers = @(
            [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' }; Enabled = $true; UserId = 'DOMAIN\alice'; StartBoundary = ''; EndBoundary = ''; Repetition = [pscustomobject]@{ Interval = ''; Duration = ''; StopAtDurationEnd = $false } }
            [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskTimeTrigger' }; Enabled = $true; UserId = ''; StartBoundary = '2025-01-01T00:00:00'; EndBoundary = ''; Repetition = [pscustomobject]@{ Interval = 'PT5M'; Duration = ''; StopAtDurationEnd = $false } }
        )
        Settings = [pscustomobject]@{ Enabled = $true; MultipleInstances = 'IgnoreNew'; ExecutionTimeLimit = 'PT0S'; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true; StartWhenAvailable = $false; WakeToRun = $false; Hidden = $false; RunOnlyIfIdle = $false; RunOnlyIfNetworkAvailable = $false; AllowDemandStart = $true; AllowHardTerminate = $true; StopIfGoingOnBatteries = $false; Priority = 7; Compatibility = 5; Volatile = $false; DisallowStartOnRemoteAppSession = $false }
    }
}
function New-TestRotatorReceipt($Task) { [pscustomobject]@{ SchemaVersion = 1; TaskName = 'tuxevil-rotator'; TaskPath = '\'; Marker = $marker; Fingerprint = (Get-RotatorTaskFingerprint -Task $Task) } }
function Copy-TestObject($Value) { $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json }
function Assert-Unowned($Task, $Receipt, [string]$Case) { if (Test-RotatorTaskOwnership -Task $Task -Receipt $Receipt) { throw "Rotator ownership predicate accepted $Case." } }
function Assert-RotatorMutationRejected($Mutation, [string]$Case) { $task = Copy-TestObject $ownedTask; & $Mutation $task; Assert-Unowned $task $ownedReceipt $Case }

$ownedTask = New-TestRotatorTask; $ownedReceipt = New-TestRotatorReceipt $ownedTask
if (-not (Test-RotatorTaskOwnership -Task $ownedTask -Receipt $ownedReceipt)) { throw 'Rotator ownership predicate rejected a matching task and receipt.' }
Assert-RotatorMutationRejected { param($t) $t.Description = $t.Description.Replace($marker, '5a59dfd0-ffcf-4a29-b04d-a74ea2709852') } 'a changed marker'
Assert-RotatorMutationRejected { param($t) $t.TaskName = 'other-task' } 'a changed task name'
Assert-RotatorMutationRejected { param($t) $t.TaskPath = '\Other\' } 'a changed task path'
Assert-RotatorMutationRejected { param($t) $t.Actions[0].Arguments = 'changed' } 'a changed action'
Assert-RotatorMutationRejected { param($t) $t.Triggers[1].Repetition.Interval = 'PT10M' } 'a changed trigger'
Assert-RotatorMutationRejected { param($t) $t.Settings.MultipleInstances = 'Parallel' } 'changed settings'
Assert-RotatorMutationRejected { param($t) $t.Settings.Hidden = $true } 'changed relevant settings'
Assert-RotatorMutationRejected { param($t) $t.Principal.UserId = 'DOMAIN\bob' } 'changed principal identity'
Assert-RotatorMutationRejected { param($t) $t.Principal.LogonType = 'Password' } 'changed principal logon type'
Assert-RotatorMutationRejected { param($t) $t.Principal.RunLevel = 'Highest' } 'changed principal run level'
Assert-RotatorMutationRejected { param($t) $t.Principal.GroupId = 'BUILTIN\Users' } 'changed principal group identity'
Assert-RotatorMutationRejected { param($t) $t.Principal.ProcessTokenSidType = 'Unrestricted' } 'changed principal token SID type'
Assert-RotatorMutationRejected { param($t) $t.Principal.RequiredPrivileges = @('SeBackupPrivilege') } 'changed principal required privileges'
Assert-RotatorMutationRejected { param($t) $t.Settings.Compatibility = 4 } 'changed task compatibility'
Assert-Unowned $ownedTask $null 'a missing receipt'
Assert-Unowned $ownedTask ([pscustomobject]@{ SchemaVersion = 99; TaskName = 'tuxevil-rotator'; TaskPath = '\'; Marker = $marker; Fingerprint = 'invalid' }) 'a malformed receipt'

if (-not (Test-RotatorTaskActionCurrent -Task $ownedTask -Executable $testExecutable)) { throw 'Current executable rejected.' }; if (Test-RotatorTaskActionCurrent -Task $ownedTask -Executable 'C:\New\tuxevil-rotator.cmd') { throw 'Stale executable accepted.' }
$caseVariantTask = Copy-TestObject $ownedTask; $caseVariantTask.Actions[0].Arguments = Get-RotatorActionArguments -Executable 'c:\TOOLS\TUXEVIL-ROTATOR.cmd'
if (-not (Test-RotatorTaskActionCurrent -Task $caseVariantTask -Executable $testExecutable)) { throw 'Casing-only executable path change was treated as stale.' }
if (-not (Test-RotatorTaskCleanupGuard -Task $ownedTask -Receipt $ownedReceipt -CreatedByCurrentCall $true)) { throw 'Fresh task rejected by cleanup guard.' }; if (Test-RotatorTaskCleanupGuard -Task $ownedTask -Receipt $ownedReceipt -CreatedByCurrentCall $false) { throw 'Uncreated task accepted by cleanup guard.' }
$changedTask = Copy-TestObject $ownedTask; $changedTask.Description = $changedTask.Description.Replace($marker, '5a59dfd0-ffcf-4a29-b04d-a74ea2709852'); if (Test-RotatorTaskCleanupGuard -Task $changedTask -Receipt $ownedReceipt -CreatedByCurrentCall $true) { throw 'Changed task identity accepted by cleanup guard.' }
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'setup-ai-ownership-predicate'; $testReceiptPath = Join-Path (Join-Path (Join-Path $testRoot 'setup-ai') 'ownership') 'rotator-task.json'; $ordinaryAttributes = @([System.IO.FileAttributes]::Directory, $null, $null, $null)
if (-not (Test-RotatorReceiptPathSafe -LocalAppData $testRoot -ReceiptPath $testReceiptPath -Attributes $ordinaryAttributes)) { throw 'Safe synthetic receipt path rejected.' }
foreach ($index in 0..3) { $bad = @($ordinaryAttributes); $bad[$index] = [System.IO.FileAttributes]::ReparsePoint; if (Test-RotatorReceiptPathSafe -LocalAppData $testRoot -ReceiptPath $testReceiptPath -Attributes $bad) { throw "Reparse point accepted at slot $index." } }
if (Test-RotatorReceiptPathSafe -LocalAppData $testRoot -ReceiptPath (Join-Path $testRoot 'other.json') -Attributes $ordinaryAttributes) { throw 'Receipt outside ownership path accepted.' }; if (Test-RotatorReceiptPathSafe -LocalAppData $testRoot -ReceiptPath $testReceiptPath -Attributes @($ordinaryAttributes[0])) { throw 'Incomplete path attributes accepted.' }

$receiptTestDir = Join-Path (Join-Path $testLocalAppData 'setup-ai') 'ownership'
New-Item -ItemType Directory -Force -Path $receiptTestDir | Out-Null
$script:receiptTestPath = Join-Path $receiptTestDir 'rotator-task.json'
$script:receiptLocationChecks = 0
$script:receiptRaceValue = 'pre-existing receipt must survive'
$script:npmFakeTaskReceipt = $null
function Get-RotatorTaskReceiptState {
    if ($script:npmFakeTaskReceipt) { return [pscustomobject]@{ Safe = $true; Exists = $true; Valid = $true; Receipt = $script:npmFakeTaskReceipt } }
    return [pscustomobject]@{ Safe = $true; Exists = $false; Valid = $false; Receipt = $null }
}
function Get-RotatorTaskReceiptPath { return $script:receiptTestPath }
function Test-RotatorReceiptLocation {
    $script:receiptLocationChecks++
    if ($script:receiptLocationChecks -eq 2) { [System.IO.File]::WriteAllText($script:receiptTestPath, $script:receiptRaceValue) }
    return $true
}
if (Write-RotatorTaskReceipt -Receipt $ownedReceipt) { throw 'Receipt writer accepted a destination created before atomic publication.' }
if ([System.IO.File]::ReadAllText($script:receiptTestPath) -cne $script:receiptRaceValue) { throw 'Receipt publication changed a receipt that appeared during the write.' }
if (@(Get-ChildItem -LiteralPath $receiptTestDir -Filter 'rotator-task.json.*.tmp' -File).Count -ne 0) { throw 'Failed receipt publication left a temporary file behind.' }

$npmFunctionNames = @('Get-RotatorNpmReceiptPath','Test-RotatorNpmReceiptLocation','Write-RotatorNpmReceipt','Get-RotatorNpmPathAttributes','Get-RotatorNpmReceiptState','Get-RotatorTaskQueryState','Get-OwnedRotatorTask','Install-RotatorNpmPackage','Test-RotatorNpmTaskDependency','Get-RotatorTaskInventoryStatus','Remove-RotatorNpmPackage')
$npmFunctions = @($sourceAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $npmFunctionNames }, $true))
if ($npmFunctions.Count -ne $npmFunctionNames.Count) { throw 'Expected rotator npm receipt and install ownership functions in setup-ai.ps1.' }
foreach ($functionAst in $npmFunctions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$script:npmFakeRoot = ''
$script:npmFakeRootAfter = ''
$script:npmFakePackageName = 'tuxevil-rotator'
$script:npmFakeVersion = '1.2.3'
$script:npmFakeInstallCount = 0
$script:npmFakeRootCount = 0
$script:npmFakeCalls = 0
$script:npmFakeUninstallCount = 0
$script:npmFakeUninstallArgs = ''
$script:npmFakeFailUninstall = $false
$script:npmFakeKeepPackage = $false
$script:npmFakeCreateMetadata = $true
$script:npmFakePreexistingMarker = ''
$script:npmFakeInstallLink = ''
$script:npmFakeOutsideDir = ''
$script:npmFakeOutsidePackageJson = ''
function npm {
    $script:npmFakeCalls++
    $arguments = $args -join ' '
    if ($arguments -ceq 'root -g') {
        $script:npmFakeRootCount++
        if ($script:npmFakeTaskAppearOnRootCount -gt 0 -and $script:npmFakeRootCount -ge $script:npmFakeTaskAppearOnRootCount -and $null -eq $script:npmFakeTask) { $script:npmFakeTask = New-TestRotatorTask -OwnerMarker 'fedcba9876543210fedcba9876543210' }
        $root = $script:npmFakeRoot
        if ($script:npmFakeRootAfter -and (Test-Path -LiteralPath (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'))) { $root = $script:npmFakeRootAfter }
        $global:LASTEXITCODE = 0
        return $root
    }
    if ($arguments -ceq 'install -g tuxevil-rotator') {
        $script:npmFakeInstallCount++
        $packageDir = Join-Path $script:npmFakeRoot 'tuxevil-rotator'
        if ($script:npmFakeInstallLink -eq 'directory') {
            if ($IsWindows) {
                & $env:ComSpec /c mklink /J $packageDir $script:npmFakeOutsideDir | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not create fake package-directory junction.' }
            } else {
                [void][System.IO.Directory]::CreateSymbolicLink($packageDir, $script:npmFakeOutsideDir)
            }
            $global:LASTEXITCODE = 0
            return
        }
        [void][System.IO.Directory]::CreateDirectory($packageDir)
        if ($script:npmFakeInstallLink -eq 'package-json-symlink') {
            [void][System.IO.File]::CreateSymbolicLink((Join-Path $packageDir 'package.json'), $script:npmFakeOutsidePackageJson)
        } elseif ($script:npmFakeInstallLink -eq 'package-json-directory') {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $packageDir 'package.json'))
        } elseif ($script:npmFakeCreateMetadata -or -not (Test-Path -LiteralPath (Join-Path $packageDir 'package.json'))) {
            [System.IO.File]::WriteAllText((Join-Path $packageDir 'package.json'), (@{ name = $script:npmFakePackageName; version = $script:npmFakeVersion } | ConvertTo-Json -Compress))
        }
        if ($script:npmFakePreexistingMarker) { [System.IO.File]::WriteAllText((Join-Path $packageDir '.setup-ai-ownership'), $script:npmFakePreexistingMarker) }
        $global:LASTEXITCODE = 0
        return
    }
    if ($arguments -ceq 'uninstall --global tuxevil-rotator') {
        $script:npmFakeUninstallArgs = $arguments
        $script:npmFakeUninstallCount++
        if ($script:npmFakeFailUninstall) { $global:LASTEXITCODE = 7; return }
        if (-not $script:npmFakeKeepPackage) {
            [System.IO.Directory]::Move((Join-Path $script:npmFakeRoot 'tuxevil-rotator'), "$script:npmFakeRoot.removed")
        }
        $global:LASTEXITCODE = 0
        return
    }
    throw "Unexpected fake npm arguments: $arguments"
}
function Invoke-Step { param([string]$Phase, [scriptblock]$Action, [switch]$Verify) & $Action; if ($global:LASTEXITCODE -ne 0) { throw "Fake npm exited $global:LASTEXITCODE" }; return $true }
function Test-Cmd { param([string]$Name) return ($Name -eq 'npm' -or $Name -eq 'tuxevil-rotator') }
function Write-Log { param([string]$Level, [string]$Phase, [string]$Event, [string]$Message, [int]$ReturnCode, [string]$Detail) }
$script:npmFakeTask = $null
$script:npmFakeTaskUnreadable = $false
$script:npmFakeTaskAppearOnRootCount = 0
$script:npmFakeTaskRemovalCount = 0
function Get-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath)
    if ($script:npmFakeTaskUnreadable) { throw 'fake task query denied' }
    $tasks = @($script:npmFakeTask | Where-Object { $null -ne $_ })
    if ($PSBoundParameters.ContainsKey('TaskName')) {
        $tasks = @($tasks | Where-Object { $_.TaskName -ceq $TaskName })
        if ($tasks.Count -eq 0) { throw 'fake filtered task query returned no objects' }
    }
    if ($PSBoundParameters.ContainsKey('TaskPath')) {
        $tasks = @($tasks | Where-Object { $_.TaskPath -ceq $TaskPath })
        if ($tasks.Count -eq 0) { throw 'fake filtered task query returned no objects' }
    }
    return $tasks
}
function Remove-RotatorOwnedTask { $script:npmFakeTaskRemovalCount++; return $false }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-package-dir-symlink-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-package-dir-symlink-appdata'
$script:npmFakeOutsideDir = Join-Path $testLocalAppData 'npm-package-dir-outside'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
[void][System.IO.Directory]::CreateDirectory($script:npmFakeOutsideDir)
$outsidePackageJson = Join-Path $script:npmFakeOutsideDir 'package.json'
[System.IO.File]::WriteAllText($outsidePackageJson, '{"name":"tuxevil-rotator","version":"1.2.3"}')
[System.IO.File]::WriteAllText((Join-Path $script:npmFakeOutsideDir 'sentinel'), 'outside-sentinel')
$script:npmFakeInstallLink = 'directory'
Install-RotatorNpmPackage
if ((Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) -or (Test-Path -LiteralPath (Join-Path $script:npmFakeOutsideDir '.setup-ai-ownership'))) { throw 'Linked package directory received a marker or ownership receipt.' }
if ([System.IO.File]::ReadAllText((Join-Path $script:npmFakeOutsideDir 'sentinel')) -cne 'outside-sentinel' -or [System.IO.File]::ReadAllText($outsidePackageJson) -cne '{"name":"tuxevil-rotator","version":"1.2.3"}') { throw 'Linked package directory changed its external target.' }
$script:npmFakeInstallLink = ''

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-package-json-directory-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-package-json-directory-appdata'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
$script:npmFakeInstallLink = 'package-json-directory'
Install-RotatorNpmPackage
if ((Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) -or (Test-Path -LiteralPath (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'))) { throw 'Non-regular package.json was accepted for marker installation.' }
$script:npmFakeInstallLink = ''

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-package-json-symlink-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-package-json-symlink-appdata'
$script:npmFakeOutsidePackageJson = Join-Path $testLocalAppData 'npm-package-json-symlink-outside.json'
$outsidePackageJsonContent = '{"name":"tuxevil-rotator","version":"1.2.3"}'
[System.IO.File]::WriteAllText($script:npmFakeOutsidePackageJson, $outsidePackageJsonContent)
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
$script:npmFakeInstallLink = 'package-json-symlink'
Install-RotatorNpmPackage
$symlinkPackageJson = Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'
if ((Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) -or (Test-Path -LiteralPath (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'))) { throw 'Symlinked package.json received an ownership marker or receipt.' }
if ([System.IO.File]::ReadAllText($script:npmFakeOutsidePackageJson) -cne $outsidePackageJsonContent -or -not [System.IO.File]::Exists($symlinkPackageJson)) { throw 'Symlinked package.json target was changed or link was not created.' }
$script:npmFakeInstallLink = ''
$script:npmFakeOutsidePackageJson = ''

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-receipt-parent-symlink-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-receipt-parent-symlink-appdata'
$receiptParent = Join-Path (Join-Path $env:LOCALAPPDATA 'setup-ai') 'ownership'
$receiptOutside = Join-Path $testLocalAppData 'npm-receipt-parent-outside'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $receiptParent))
[void][System.IO.Directory]::CreateDirectory($receiptOutside)
if ($IsWindows) {
    & $env:ComSpec /c mklink /J $receiptParent $receiptOutside | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create fake receipt-parent junction.' }
} else {
    [void][System.IO.Directory]::CreateSymbolicLink($receiptParent, $receiptOutside)
}
Install-RotatorNpmPackage
if ((Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) -or
    (Test-Path -LiteralPath (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership')) -or
    (Test-Path -LiteralPath (Join-Path $receiptOutside 'rotator-npm.json'))) { throw 'Symlinked npm receipt parent accepted an unsafe ownership path.' }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-receipt-collision-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-receipt-collision-appdata'
$npmCollisionReceipt = Get-RotatorNpmReceiptPath
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $npmCollisionReceipt))
[System.IO.File]::WriteAllText($npmCollisionReceipt, 'preserve receipt')
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
if ([System.IO.File]::ReadAllText($npmCollisionReceipt) -cne 'preserve receipt' -or
    (Test-Path -LiteralPath (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'))) { throw 'Receipt publication failure left an orphaned marker or changed the receipt.' }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-fresh-root'
$script:npmFakeInstallCount = 0
$script:npmFakeRootCount = 0
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-fresh-appdata'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
$npmReceiptPath = Get-RotatorNpmReceiptPath
if (-not (Test-Path -LiteralPath $npmReceiptPath -PathType Leaf)) { throw 'Fresh global install did not write an npm ownership receipt.' }
$npmReceipt = Get-Content -Raw -LiteralPath $npmReceiptPath | ConvertFrom-Json
$npmMarkerPath = Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'
if ($npmReceipt.SchemaVersion -ne 2 -or $npmReceipt.Package -cne 'tuxevil-rotator' -or $npmReceipt.Version -cne '1.2.3' -or $npmReceipt.NpmRoot -cne $script:npmFakeRoot -or $npmReceipt.Marker -cnotmatch '^[0-9a-f]{32}$' -or (Get-Content -Raw -LiteralPath $npmMarkerPath) -cne $npmReceipt.Marker) { throw 'Fresh npm receipt did not record a verified package marker and metadata.' }
if ($npmReceiptPath -eq (Get-RotatorTaskReceiptPath)) { throw 'Npm ownership receipt reused the independent scheduled-task receipt path.' }
if ($script:npmFakeInstallCount -ne 1 -or $script:npmFakeRootCount -lt 2) { throw "Fresh npm ownership did not install and re-read the global npm root (installs=$script:npmFakeInstallCount; roots=$script:npmFakeRootCount)." }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-marker-collision-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-marker-collision-appdata'
$script:npmFakePreexistingMarker = 'preserve-marker'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
$collisionMarkerPath = Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'
if ((Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) -or (Get-Content -Raw -LiteralPath $collisionMarkerPath) -cne 'preserve-marker') { throw 'Pre-existing package marker was overwritten or claimed.' }
$script:npmFakePreexistingMarker = ''

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-preexisting-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-preexisting-appdata'
$packageDir = Join-Path $script:npmFakeRoot 'tuxevil-rotator'
[void][System.IO.Directory]::CreateDirectory($packageDir)
[System.IO.File]::WriteAllText((Join-Path $packageDir 'package.json'), '{"name":"tuxevil-rotator","version":"0.9.0"}')
Install-RotatorNpmPackage
if (Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) { throw 'Pre-existing global package was incorrectly claimed as setup-ai-owned.' }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-invalid-metadata-root'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-invalid-metadata-appdata'
$script:npmFakePackageName = 'another-package'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
if (Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) { throw 'Mismatched package metadata was incorrectly claimed as setup-ai-owned.' }

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-whitespace-version'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-whitespace-version-appdata'
$script:npmFakePackageName = 'tuxevil-rotator'
$script:npmFakeVersion = '   '
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
if (Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) { throw 'Whitespace-only package version was incorrectly claimed as setup-ai-owned.' }
$script:npmFakeVersion = '1.2.3'

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-changed-root'
$script:npmFakeRootAfter = Join-Path $testLocalAppData 'npm-changed-root-after'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-changed-root-appdata'
$script:npmFakePackageName = 'tuxevil-rotator'
[void][System.IO.Directory]::CreateDirectory($script:npmFakeRoot)
Install-RotatorNpmPackage
if (Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) { throw 'Changed global npm root was incorrectly claimed as setup-ai-owned.' }
$script:npmFakeRootAfter = ''

$script:npmFakeRoot = Join-Path $testLocalAppData 'npm-root-unavailable'
$env:LOCALAPPDATA = Join-Path $testLocalAppData 'npm-root-unavailable-appdata'
Install-RotatorNpmPackage
if (Test-Path -LiteralPath (Get-RotatorNpmReceiptPath)) { throw 'Unavailable pre-install npm root was incorrectly claimed as setup-ai-owned.' }

function Prepare-TestRotatorNpm {
    param([string]$Name, [bool]$WithReceipt = $true)
    $script:npmFakeRoot = Join-Path $testLocalAppData "npm-$Name"
    $script:npmFakeRootAfter = ''
    $script:npmFakeVersion = '1.2.3'
    $script:npmFakeRootCount = 0
    $script:npmFakeTask = $null
    $script:npmFakeTaskUnreadable = $false
    $script:npmFakeTaskAppearOnRootCount = 0
    $script:npmFakeTaskRemovalCount = 0
    $script:npmFakeTaskReceipt = $null
    $script:npmFakeUninstallCount = 0
    $script:npmFakeFailUninstall = $false
    $script:npmFakeKeepPackage = $false
    $script:npmFakeUninstallArgs = ''
    $env:LOCALAPPDATA = Join-Path $testLocalAppData "appdata-$Name"
    $packageDir = Join-Path $script:npmFakeRoot 'tuxevil-rotator'
    [void][System.IO.Directory]::CreateDirectory($packageDir)
    [System.IO.File]::WriteAllText((Join-Path $packageDir 'package.json'), '{"name":"tuxevil-rotator","version":"1.2.3"}')
    $marker = '0123456789abcdef0123456789abcdef'
    [System.IO.File]::WriteAllText((Join-Path $packageDir '.setup-ai-ownership'), $marker)
    if ($WithReceipt) {
        $packageJson = Join-Path $packageDir 'package.json'
        $receipt = [pscustomobject]@{ SchemaVersion = 2; Package = 'tuxevil-rotator'; NpmRoot = $script:npmFakeRoot; PackagePath = $packageJson; Version = '1.2.3'; Marker = $marker }
        if (-not (Write-RotatorNpmReceipt -Receipt $receipt)) { throw 'Could not create fake npm receipt.' }
    }
}

Prepare-TestRotatorNpm 'no-receipt' $false
$beforeNpmCalls = $script:npmFakeCalls
if (Remove-RotatorNpmPackage -Confirmed) { throw 'Removed a package without an ownership receipt.' }
if ($script:npmFakeCalls -ne $beforeNpmCalls -or $script:npmFakeUninstallCount -ne 0) { throw 'No-receipt check invoked npm.' }

Prepare-TestRotatorNpm 'v1-receipt'
$legacyReceipt = Get-Content -Raw -LiteralPath (Get-RotatorNpmReceiptPath) | ConvertFrom-Json
$legacyReceipt.SchemaVersion = 1
[System.IO.File]::WriteAllText((Get-RotatorNpmReceiptPath), ($legacyReceipt | ConvertTo-Json -Compress))
$legacyReceiptBefore = [System.IO.File]::ReadAllText((Get-RotatorNpmReceiptPath))
if ((Get-RotatorNpmReceiptState).Valid) { throw 'v1 npm receipt was upgraded or inventoried as owned.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or [System.IO.File]::ReadAllText((Get-RotatorNpmReceiptPath)) -cne $legacyReceiptBefore) { throw 'v1 npm receipt was changed or used to uninstall the package.' }

Prepare-TestRotatorNpm 'malformed'
[System.IO.File]::WriteAllText((Get-RotatorNpmReceiptPath), '{bad json')
if ((Get-RotatorNpmReceiptState).Valid) { throw 'Malformed npm receipt was inventoried as owned.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0) { throw 'Malformed receipt package was removable.' }

Prepare-TestRotatorNpm 'root-mismatch'
$script:npmFakeRootAfter = Join-Path $testLocalAppData 'npm-wrong-root'
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0) { throw 'Changed global root package was removable.' }

Prepare-TestRotatorNpm 'fingerprint-mismatch'
[System.IO.File]::WriteAllText((Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'), '{"name":"tuxevil-rotator","version":"9.9.9"}')
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0) { throw 'Changed package fingerprint was removable.' }

Prepare-TestRotatorNpm 'name-mismatch'
[System.IO.File]::WriteAllText((Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'), '{"name":"other-package","version":"1.2.3"}')
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0) { throw 'Changed package name was removable.' }

Prepare-TestRotatorNpm 'stale-reinstall'
$packageDir = Join-Path $script:npmFakeRoot 'tuxevil-rotator'
$replacedPackageDir = "$packageDir.old"
[System.IO.Directory]::Move($packageDir, $replacedPackageDir)
[void][System.IO.Directory]::CreateDirectory($packageDir)
[System.IO.File]::WriteAllText((Join-Path $packageDir 'package.json'), '{"name":"tuxevil-rotator","version":"1.2.3"}')
[System.IO.File]::WriteAllText((Join-Path $packageDir '.setup-ai-ownership'), 'fedcba9876543210fedcba9876543210')
if ((Get-RotatorNpmReceiptState).Valid) { throw 'Stale receipt inventoried a same-version replacement package as owned.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Stale receipt authorized a same-version replacement package.' }

Prepare-TestRotatorNpm 'marker-missing'
[System.IO.File]::Delete((Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'))
if ((Get-RotatorNpmReceiptState).Valid) { throw 'Receipt with a missing marker was inventoried as owned.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Receipt with a missing marker authorized package removal.' }

Prepare-TestRotatorNpm 'marker-mismatch'
[System.IO.File]::WriteAllText((Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') '.setup-ai-ownership'), 'fedcba9876543210fedcba9876543210')
if ((Get-RotatorNpmReceiptState).Valid) { throw 'Receipt with a mismatched marker was inventoried as owned.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Receipt with a mismatched marker authorized package removal.' }

Prepare-TestRotatorNpm 'unowned-task'
$script:npmFakeTask = New-TestRotatorTask -OwnerMarker 'fedcba9876543210fedcba9876543210'
if (Test-RotatorNpmTaskDependency -ReadOnly -or -not $script:RotatorNpmTaskBlocked -or $script:npmFakeTaskRemovalCount -ne 0) { throw 'Inventory accepted or changed an unowned scheduled-task dependency.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not (Test-Path (Get-RotatorNpmReceiptPath)) -or -not (Test-Path (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'))) { throw 'Valid npm receipt removed a package still required by an unowned task.' }
$script:npmFakeTask = $null

Prepare-TestRotatorNpm 'absent-task'
if (-not (Test-RotatorNpmTaskDependency -ReadOnly) -or $script:RotatorNpmTaskBlocked) { throw 'A successful empty task listing did not prove the task absent.' }
$taskStatus = Get-RotatorTaskInventoryStatus
if ($taskStatus.Message -cne 'not present (task query succeeded).') { throw 'Inventory did not report a successfully queried absent task.' }

Prepare-TestRotatorNpm 'unreadable-task'
$script:npmFakeTaskUnreadable = $true
$taskStatus = Get-RotatorTaskInventoryStatus
if ($taskStatus.Message -cnotmatch '^state unknown;') { throw 'Inventory reported an unreadable task query as absent or unowned.' }
if (Test-RotatorNpmTaskDependency -ReadOnly -or -not $script:RotatorNpmTaskBlocked -or $script:npmFakeTaskRemovalCount -ne 0) { throw 'Inventory accepted or changed an unreadable scheduled-task dependency.' }
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Unreadable task state did not protect the npm package receipt.' }
$script:npmFakeTaskUnreadable = $false

Prepare-TestRotatorNpm 'duplicate-nested-task'
$nestedTask = Copy-TestObject $ownedTask
$nestedTask.TaskPath = '\Nested\'
$script:npmFakeTask = @($ownedTask, $nestedTask)
if (Test-RotatorNpmTaskDependency -ReadOnly -or -not $script:RotatorNpmTaskBlocked) { throw 'A duplicate or nested same-name task did not block npm removal.' }
$taskStatus = Get-RotatorTaskInventoryStatus
if ($taskStatus.Message -notmatch '^protected; duplicate or nested same-name task exists\.') { throw 'Inventory did not report duplicate or nested same-name tasks as protected.' }

Prepare-TestRotatorNpm 'task-removal-failure'
$script:npmFakeTask = $ownedTask
$script:npmFakeTaskReceipt = New-TestRotatorReceipt $ownedTask
$taskStatus = Get-RotatorTaskInventoryStatus -Confirmed
if ($taskStatus.Removed -or $taskStatus.Message -cnotmatch '^not removed; ownership could not be verified or removal failed\.') { throw 'Failed task removal was reported as absent or merely unowned.' }

Prepare-TestRotatorNpm 'owned-task-inventory'
$script:npmFakeTask = $ownedTask
$script:npmFakeTaskReceipt = New-TestRotatorReceipt $ownedTask
if (-not (Test-RotatorNpmTaskDependency -ReadOnly) -or $script:RotatorNpmTaskBlocked -or $script:npmFakeTaskRemovalCount -ne 0) { throw 'Inventory did not recognize a matching task as removable without deleting it.' }

Prepare-TestRotatorNpm 'surviving-task'
$script:npmFakeTask = $ownedTask
$script:npmFakeTaskReceipt = New-TestRotatorReceipt $ownedTask
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or $script:npmFakeTaskRemovalCount -ne 1 -or $null -eq $script:npmFakeTask -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Surviving scheduled task did not block package removal.' }

Prepare-TestRotatorNpm 'inventory'
$inventoryState = Get-RotatorNpmReceiptState
if (-not $inventoryState.Valid -or -not $inventoryState.PackagePresent) { throw 'Matching receipt package was not inventoried.' }
$beforeNpmCalls = $script:npmFakeUninstallCount
if (Remove-RotatorNpmPackage -DryRun -Confirmed) { throw 'Inventory/dry-run reported an npm package removed.' }
if ($script:npmFakeUninstallCount -ne $beforeNpmCalls -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Inventory changed the package or receipt.' }
if (Remove-RotatorNpmPackage) { throw 'Removal without -Yes was accepted.' }
if ($script:npmFakeUninstallCount -ne 0) { throw 'Removal without -Yes invoked npm uninstall.' }

Prepare-TestRotatorNpm 'late-task'
$script:npmFakeTaskAppearOnRootCount = 2
$removed = Remove-RotatorNpmPackage -Confirmed
if ($removed -or $script:npmFakeUninstallCount -ne 0 -or -not $script:npmFakeTask -or -not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Task appearing during final receipt validation did not block npm uninstall.' }

Prepare-TestRotatorNpm 'uninstall-failure'
$script:npmFakeFailUninstall = $true
if (Remove-RotatorNpmPackage -Confirmed) { throw 'npm uninstall failure was reported as success.' }
if ($script:npmFakeUninstallCount -ne 1 -or -not (Test-Path (Get-RotatorNpmReceiptPath)) -or -not (Test-Path (Join-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator') 'package.json'))) { throw 'npm uninstall failure did not preserve package and receipt.' }

Prepare-TestRotatorNpm 'package-remains'
$script:npmFakeKeepPackage = $true
if (Remove-RotatorNpmPackage -Confirmed) { throw 'npm uninstall success with a remaining package was accepted.' }
if (-not (Test-Path (Get-RotatorNpmReceiptPath))) { throw 'Receipt was removed while the package remained.' }

Prepare-TestRotatorNpm 'confirmed'
if (-not (Remove-RotatorNpmPackage -Confirmed)) { throw 'Confirmed receipt-backed removal failed.' }
if ($script:npmFakeUninstallCount -ne 1 -or $script:npmFakeUninstallArgs -cne 'uninstall --global tuxevil-rotator' -or (Test-Path (Get-RotatorNpmReceiptPath)) -or (Test-Path (Join-Path $script:npmFakeRoot 'tuxevil-rotator'))) { throw 'Confirmed removal was not exact or left its package/receipt behind.' }

$dryRun = Invoke-SetupAi -Arguments @('-DryRun', '-Only', 'pi,codex')
if ($dryRun.ExitCode -ne 0) { throw "-DryRun exited $($dryRun.ExitCode):`n$($dryRun.Output)" }
Assert-Contains $dryRun.Output 'Installation plan (dry run)'
Assert-Contains $dryRun.Output '  pi:'
Assert-Contains $dryRun.Output 'Create the Pi extensions, skills, and npm roots plus the npm project marker; write remote-source and allow-scripts policy only when npm 12+ is available.'
Assert-Contains $dryRun.Output 'If pi is missing, run https://pi.dev/install.ps1, refresh PATH, and verify pi; otherwise keep the installed CLI.'
Assert-Contains $dryRun.Output '  codex:'
Assert-Contains $dryRun.Output 'If codex is missing, run https://chatgpt.com/codex/install.ps1 with CODEX_NON_INTERACTIVE=1; otherwise keep the existing codex.'
Assert-Contains $dryRun.Output 'Verify codex is available on PATH after the installer.'
Assert-Contains $dryRun.Output 'Plan only; no installer, network, package-manager, environment, task, or child-process action was run.'
if ($dryRun.Output.Contains('  base:')) { throw '-Only was not honored by the dry-run plan.' }
Assert-LogsUnchanged

$conditionPlan = Invoke-SetupAi -Arguments @('-DryRun', '-Only', 'base,pi-packages,gentle-ai,rotator')
if ($conditionPlan.ExitCode -ne 0) { throw "Conditional -DryRun exited $($conditionPlan.ExitCode):`n$($conditionPlan.Output)" }
Assert-Contains $conditionPlan.Output 'Probe with vswhere for Microsoft.VisualStudio.Component.VC.Tools.x86.x64; if the workload is absent or unverified, run winget install --force for Visual Studio 2022 Build Tools with the VC Tools workload, then verify it and refresh PATH.'
Assert-Contains $conditionPlan.Output 'Require pi and node on PATH before enabling npm remote sources and resolving the manifest.'
Assert-Contains $conditionPlan.Output 'repair Pi settings only when an unambiguous safe edit is available, otherwise warn and leave ambiguous or unmodifiable conflicts unchanged.'
Assert-Contains $conditionPlan.Output 'when gentle-pi is installed and npm supports approval, approve and rebuild its install script, then verify the review binary'
Assert-Contains $conditionPlan.Output 'With a TTY, retry nonzero selector failures unless interrupted; without a TTY, retry only when captured output matches the GitHub API HTTP 403 signature'
$rotatorPlanSteps = @(
    'Probe localhost:51200/v1/models;'
    'If Node.js is at least 20, install tuxevil-rotator with npm only if missing and verify it is available on PATH.'
    'Attempt best-effort registration and readback of the logon task with a 5-minute watchdog.'
    'Only if the initial gateway probe was down, start via the scheduled task when available or fall back to a detached process and poll readiness;'
    'Install/verify the Pi cockpit-sync extension only when pi is available.'
)
$previousRotatorStepIndex = -1
foreach ($step in $rotatorPlanSteps) {
    $stepIndex = $conditionPlan.Output.IndexOf($step)
    if ($stepIndex -le $previousRotatorStepIndex) { throw "Rotator plan step missing or out of order: $step" }
    $previousRotatorStepIndex = $stepIndex
}
Assert-LogsUnchanged

$modules = @('base','node','bun','pi','dotenv','lazyvim','pi-packages','go','ee','skills','pi-workflows','herdr','claude-code','codex','antigravity','opencode','gentle-ai','cockpit','rotator')
$allSelection = @($modules + 'shell')
$defaultInventory = Invoke-SetupAi -Arguments @('-Uninstall')
if ($defaultInventory.ExitCode -ne 0) { throw "Default -Uninstall exited $($defaultInventory.ExitCode):`n$($defaultInventory.Output)" }
Assert-InventorySelection $defaultInventory $allSelection
Assert-Contains $defaultInventory.Output 'Inventory only; pass -Yes to request removal.'
Assert-Contains $defaultInventory.Output "module 'opencode': only the receipt-backed User OPENCODE_PI_BIN value can be removed; the CLI, npm package, credentials, and other environment values remain protected."
Assert-Contains $defaultInventory.Output 'User OPENCODE_PI_BIN: absent.'
Assert-LogsUnchanged

$inventory = Invoke-SetupAi -Arguments @('-Uninstall', '-All')
if ($inventory.ExitCode -ne 0) { throw "-Uninstall -All exited $($inventory.ExitCode):`n$($inventory.Output)" }
Assert-InventorySelection $inventory $allSelection
Assert-Contains $inventory.Output "module 'rotator': only its receipt-owned task and matching global npm package can be removed; other package/data remain protected."
Assert-Contains $inventory.Output 'rotator npm package: not covered - missing or mismatched ownership receipt; legacy packages are protected.'
if ($inventory.Output -notmatch 'rotator task: (state unknown; task query failed|not present \(task query succeeded\)|protected;|receipt-backed and removable)') { throw 'Inventory did not distinguish an unknown or proven task state.' }
Assert-Contains $inventory.Output 'Inventory only; pass -Yes to request removal.'
if ($inventory.Output.Contains('ai-memory')) { throw 'Inventory included a module outside this slice.' }
Assert-LogsUnchanged

$shellOnly = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'shell')
if ($shellOnly.ExitCode -ne 0) { throw "-Uninstall -Only shell exited $($shellOnly.ExitCode):`n$($shellOnly.Output)" }
Assert-InventorySelection $shellOnly @('shell')
Assert-LogsUnchanged

$shellAndPi = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'shell,pi')
if ($shellAndPi.ExitCode -ne 0) { throw "-Uninstall -Only shell,pi exited $($shellAndPi.ExitCode):`n$($shellAndPi.Output)" }
Assert-InventorySelection $shellAndPi @('pi','shell')
Assert-LogsUnchanged

$uppercaseShell = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'SHELL')
if ($uppercaseShell.ExitCode -ne 2) { throw "-Uninstall -Only SHELL exited $($uppercaseShell.ExitCode), expected 2:`n$($uppercaseShell.Output)" }
Assert-Contains $uppercaseShell.Output 'Unknown module: SHELL'
Assert-LogsUnchanged

$uppercaseModule = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'PI')
if ($uppercaseModule.ExitCode -ne 2) { throw "-Uninstall -Only PI exited $($uppercaseModule.ExitCode), expected 2:`n$($uppercaseModule.Output)" }
Assert-Contains $uppercaseModule.Output 'Unknown module: PI'
Assert-LogsUnchanged

$allWins = Invoke-SetupAi -Arguments @('-Uninstall', '-All', '-Only', 'shell')
if ($allWins.ExitCode -ne 0) { throw "-Uninstall -All -Only shell exited $($allWins.ExitCode):`n$($allWins.Output)" }
Assert-InventorySelection $allWins $allSelection
Assert-LogsUnchanged

$confirmed = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'rotator', '-Yes', '-Purge')
if ($confirmed.ExitCode -ne 0) { throw "Confirmed -Uninstall exited $($confirmed.ExitCode):`n$($confirmed.Output)" }
Assert-InventorySelection $confirmed @('rotator')
Assert-Contains $confirmed.Output 'module ''rotator'': only its receipt-owned task and matching global npm package can be removed; other package/data remain protected.'
Assert-Contains $confirmed.Output 'rotator task: not removed; ownership could not be verified or removal failed.'
Assert-Contains $confirmed.Output 'rotator npm package: preserved - missing or mismatched receipt/fingerprint.'
Assert-Contains $confirmed.Output 'Removal requested (-Yes), but no items were removed.'
Assert-Contains $confirmed.Output '-Purge does not expand scope; Pi roots/data, rotator data, OpenCode/npm/vendor resources, and all other modules remain protected.'
if ($confirmed.Output -match '(?m)^\s+removed:') { throw 'Inventory-only uninstall removed an item.' }
Assert-LogsUnchanged

$dryUninstall = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'rotator', '-DryRun', '-Yes')
if ($dryUninstall.ExitCode -ne 0) { throw "Dry-run uninstall exited $($dryUninstall.ExitCode):`n$($dryUninstall.Output)" }
Assert-Contains $dryUninstall.Output 'Dry run; no items were removed.'
if ($dryUninstall.Output -match '(?m)^\s+removed:') { throw 'Dry-run uninstall removed an item.' }
Assert-LogsUnchanged

# Real child process: confirmed Pi removal must run without an initialized log run.
$e2eAgent = Join-Path $testLocalAppData 'pi-e2e-agent'
$e2eBin = Join-Path $testLocalAppData 'pi-e2e-bin'
$e2eSpec = 'npm:pi-extensible-workflows'
[void][System.IO.Directory]::CreateDirectory($e2eAgent)
[void][System.IO.Directory]::CreateDirectory($e2eBin)
$e2eSettings = Join-Path $e2eAgent 'settings.json'
[System.IO.File]::WriteAllText($e2eSettings, '{"packages":["npm:pi-extensible-workflows","npm:unrelated-package"]}')
[System.IO.File]::WriteAllText((Join-Path $e2eBin 'pi.ps1'), @'
param([string]$Operation, [string]$Spec)
if ($Operation -cne 'remove') { exit 2 }
$file = Join-Path $env:PI_CODING_AGENT_DIR 'settings.json'
$settings = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
$settings.packages = @($settings.packages | Where-Object { $_ -cne $Spec })
[System.IO.File]::WriteAllText($file, ($settings | ConvertTo-Json -Compress))
exit 0
'@)
$script:PiAgentDir = $e2eAgent
$env:LOCALAPPDATA = $testLocalAppData
if (-not (Write-PiPackageReceipt -Spec $e2eSpec)) { throw 'Could not prepare the end-to-end Pi ownership receipt.' }
$e2eReceipt = Get-PiPackageReceiptPath -Spec $e2eSpec
$previousPath = $env:PATH
$previousAgentDir = $env:PI_CODING_AGENT_DIR
try {
    $env:PATH = $e2eBin + [System.IO.Path]::PathSeparator + $env:PATH
    $env:PI_CODING_AGENT_DIR = $e2eAgent
    $piRemoval = Invoke-SetupAi -Arguments @('-Uninstall', '-Only', 'pi-workflows', '-Yes')
} finally {
    $env:PATH = $previousPath
    [System.Environment]::SetEnvironmentVariable('PI_CODING_AGENT_DIR', $previousAgentDir, 'Process')
}
if ($piRemoval.ExitCode -ne 0) { throw "Confirmed Pi uninstall exited $($piRemoval.ExitCode):`n$($piRemoval.Output)" }
Assert-Contains $piRemoval.Output "removed: Pi package $e2eSpec"
if ((Get-Content -Raw -LiteralPath $e2eSettings) -cne '{"packages":["npm:unrelated-package"]}') { throw "Confirmed Pi uninstall changed more than its exact registration:`n$(Get-Content -Raw -LiteralPath $e2eSettings)" }
if (Test-Path -LiteralPath $e2eReceipt) { throw 'Confirmed Pi uninstall left its ownership receipt.' }
Assert-LogsUnchanged

Write-Host 'PowerShell lifecycle regression checks passed.'
