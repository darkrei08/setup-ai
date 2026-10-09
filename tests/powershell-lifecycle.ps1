$ErrorActionPreference = 'Stop'
$setup = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-ai.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Raw -LiteralPath $setup), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "setup-ai.ps1 has parse errors: $($parseErrors -join '; ')" }

$functionNames = @(
    'Get-SetupAiUserEnvironmentValue', 'Set-SetupAiUserEnvironmentValue',
    'Get-SetupAiEnvironmentReceiptPath', 'Test-SetupAiEnvironmentReceiptLocation',
    'Get-SetupAiEnvironmentReceiptState', 'Write-SetupAiEnvironmentReceipt',
    'Get-SetupAiEnvironmentInventoryStatus', 'Remove-SetupAiEnvironment',
    'Get-OpenCodeUserEnvironmentValue', 'Set-OpenCodeUserEnvironmentValue',
    'Get-OpenCodeEnvReceiptState',
    'Write-OpenCodeEnvReceipt', 'Get-OpenCodeEnvInventoryStatus',
    'Remove-OpenCodeUserEnvironment', 'Set-OpenCodePiBin',
    'Report-StaleQuietToolsSwitch'
)
$functions = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames
}, $true))
if ($functions.Count -ne $functionNames.Count) { throw 'Expected environment ownership functions in setup-ai.ps1.' }
foreach ($functionAst in $functions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('setup-ai-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $testRoot 'localappdata'
$script:FakeUserEnvironment = @{}
function Get-SetupAiUserEnvironmentValue {
    param([string]$Name)
    if ($script:FakeUserEnvironment.ContainsKey($Name)) { return $script:FakeUserEnvironment[$Name] }
    return $null
}
$script:FakeSetMode = 'normal'
$script:FakeSetCalls = 0
$script:ErrorLogs = @()
function Set-SetupAiUserEnvironmentValue {
    param($Name, $Value)
    $script:FakeSetCalls++
    if ($null -ne $Value -and $script:FakeSetMode -in @('rollback-fails', 'clear-mutates-receipt-rollback-fails')) { throw 'fake rollback failure' }
    if ($null -eq $Value) {
        $script:FakeUserEnvironment.Remove($Name) | Out-Null
        if ($script:FakeSetMode -in @('clear-mutates-receipt', 'clear-mutates-receipt-rollback-fails')) {
            Add-Content -LiteralPath (Get-SetupAiEnvironmentReceiptPath -Name $Name) -Value '# changed during removal'
        }
    } else { $script:FakeUserEnvironment[$Name] = [string]$Value }
}
function Test-OpenCodeSpawn { param([string]$Bin = '') return ($Bin -eq 'C:\setup-ai\opencode.exe') }
function Get-OpenCodeNativeBin { return 'C:\setup-ai\opencode.exe' }
function Write-Log {
    param($Level, $Phase, $Event, $Message, $ReturnCode, $Meta)
    if ($Level -eq 'ERROR') { $script:ErrorLogs += $Message }
}

$previousProcessValue = $env:OPENCODE_PI_BIN
$previousQuietToolsValue = $env:GENTLE_PI_QUIET_TOOLS
try {
    $env:OPENCODE_PI_BIN = $null
    $script:FakeSetCalls = 0
    if (Remove-OpenCodeUserEnvironment -Confirmed) { throw 'Absent OPENCODE_PI_BIN was reported as removable.' }
    if ($script:SetupAiEnvironmentRemovalFailed -or $script:FakeSetCalls -ne 0) { throw 'Absent OPENCODE_PI_BIN marked failure or attempted mutation.' }

    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = 'C:\user\opencode.exe'
    if (Remove-OpenCodeUserEnvironment -Confirmed) { throw 'Unowned OPENCODE_PI_BIN was reported as removable.' }
    if ($script:SetupAiEnvironmentRemovalFailed -or $script:FakeSetCalls -ne 0) { throw 'Unowned OPENCODE_PI_BIN marked failure or attempted mutation.' }
    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = 'C:\user\opencode.exe'
    Set-OpenCodePiBin
    $env:OPENCODE_PI_BIN = $null
    if ($script:FakeUserEnvironment['OPENCODE_PI_BIN'] -cne 'C:\user\opencode.exe') { throw 'Pre-existing OPENCODE_PI_BIN was overwritten.' }
    if (Test-Path -LiteralPath (Get-SetupAiEnvironmentReceiptPath -Name 'OPENCODE_PI_BIN')) { throw 'Pre-existing OPENCODE_PI_BIN received an ownership receipt.' }
    $script:FakeUserEnvironment.Remove('OPENCODE_PI_BIN') | Out-Null
    Set-OpenCodePiBin
    $ownedOpenCode = 'C:\setup-ai\opencode.exe'
    if ($script:FakeUserEnvironment['OPENCODE_PI_BIN'] -cne $ownedOpenCode) { throw 'Fresh OPENCODE_PI_BIN was not written.' }
    if ((Get-OpenCodeEnvInventoryStatus).State -cne 'receipt-backed') { throw 'Fresh OPENCODE_PI_BIN was not receipt-backed.' }

    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = 'C:\user\replacement.exe'
    $script:FakeSetCalls = 0
    if ((Get-OpenCodeEnvInventoryStatus).State -cne 'protected' -or (Remove-OpenCodeUserEnvironment -Confirmed)) { throw 'Changed OPENCODE_PI_BIN was removable.' }
    if ($script:SetupAiEnvironmentRemovalFailed -or $script:FakeSetCalls -ne 0) { throw 'Changed OPENCODE_PI_BIN marked failure or attempted mutation.' }
    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = $ownedOpenCode
    if (-not (Remove-OpenCodeUserEnvironment -Confirmed)) { throw "Receipt-backed OPENCODE_PI_BIN removal failed: state=$((Get-OpenCodeEnvInventoryStatus).State);failed=$script:SetupAiEnvironmentRemovalFailed;path=$(Get-SetupAiEnvironmentReceiptPath -Name 'OPENCODE_PI_BIN')" }
    if ($script:FakeUserEnvironment.ContainsKey('OPENCODE_PI_BIN') -or (Test-Path -LiteralPath (Get-SetupAiEnvironmentReceiptPath -Name 'OPENCODE_PI_BIN'))) { throw 'OPENCODE_PI_BIN removal left state behind.' }

    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = $ownedOpenCode
    if (-not (Write-OpenCodeEnvReceipt -Value $ownedOpenCode)) { throw 'Could not prepare the rollback fixture.' }
    $script:FakeSetMode = 'clear-mutates-receipt-rollback-fails'
    $script:ErrorLogs = @()
    if (Remove-OpenCodeUserEnvironment -Confirmed) { throw 'Receipt mutation was reported as a successful removal.' }
    if (-not $script:SetupAiEnvironmentRemovalFailed -or $script:FakeUserEnvironment.ContainsKey('OPENCODE_PI_BIN') -or $script:ErrorLogs.Count -eq 0) {
        throw 'Failed rollback was not marked and logged.'
    }
    $script:FakeSetMode = 'normal'
    [IO.File]::Delete((Get-SetupAiEnvironmentReceiptPath -Name 'OPENCODE_PI_BIN'))

    if ((Get-SetupAiEnvironmentInventoryStatus -Name 'GENTLE_PI_QUIET_TOOLS').State -cne 'absent') { throw 'Absent legacy GENTLE_PI_QUIET_TOOLS was not reported as absent.' }
    $env:GENTLE_PI_QUIET_TOOLS = '0'
    $script:FakeUserEnvironment['GENTLE_PI_QUIET_TOOLS'] = '0'
    Report-StaleQuietToolsSwitch
    if ($script:FakeUserEnvironment['GENTLE_PI_QUIET_TOOLS'] -cne '0' -or $env:GENTLE_PI_QUIET_TOOLS -cne '0') { throw 'Pre-existing GENTLE_PI_QUIET_TOOLS was removed.' }

    if ((Get-SetupAiEnvironmentInventoryStatus -Name 'GENTLE_PI_QUIET_TOOLS').State -cne 'protected') { throw 'Legacy GENTLE_PI_QUIET_TOOLS was not protected.' }
    Report-StaleQuietToolsSwitch
    if ($script:FakeUserEnvironment['GENTLE_PI_QUIET_TOOLS'] -cne '0' -or $env:GENTLE_PI_QUIET_TOOLS -cne '0') { throw 'Legacy GENTLE_PI_QUIET_TOOLS was removed.' }
} finally {
    if ($null -eq $previousProcessValue) { Remove-Item Env:OPENCODE_PI_BIN -ErrorAction SilentlyContinue }
    else { $env:OPENCODE_PI_BIN = $previousProcessValue }
    if ($null -eq $previousQuietToolsValue) { Remove-Item Env:GENTLE_PI_QUIET_TOOLS -ErrorAction SilentlyContinue }
    else { $env:GENTLE_PI_QUIET_TOOLS = $previousQuietToolsValue }
    if ($null -eq $previousLocalAppData) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
    else { $env:LOCALAPPDATA = $previousLocalAppData }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$wingetFunctionNames = @('Invoke-Step', 'Test-WingetInstalled', 'Install-Winget')
$wingetFunctions = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $wingetFunctionNames
}, $true))
if ($wingetFunctions.Count -ne $wingetFunctionNames.Count) { throw 'Expected winget lifecycle functions in setup-ai.ps1.' }

$wingetTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('setup-ai-winget-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $wingetTestRoot | Out-Null
try {
    $HumanLog = Join-Path $wingetTestRoot 'human.log'
    $JsonlLog = Join-Path $wingetTestRoot 'events.jsonl'
    $RunId = 'winget-test-run'
    $script:VerboseOutput = $false
    $script:CurrentModule = 'base'
    $script:LastErrorStep = ''
    $script:LastErrorReturnCode = 0
    $script:WingetLogEvents = @()
    $script:WingetStepResults = @()
    $global:SetupAiFakeWingetCalls = @()
    $script:FakeWingetMode = 'list'
    $script:FakeWingetId = 'Git.Git'

    function Write-Log {
        param($Level, $Phase, $Event, $Message, $ReturnCode = 0, $Meta = '', [bool]$Optional = $false, [string]$Behavior = '')
        $script:WingetLogEvents += [pscustomobject]@{
            Level = $Level
            Phase = $Phase
            Event = $Event
            Message = $Message
            ReturnCode = $ReturnCode
            Optional = $Optional
            Behavior = $Behavior
        }
    }
    function Write-StepResult {
        param([string]$Phase, [string]$Status, [int]$ReturnCode, [string]$Step)
        $script:WingetStepResults += [pscustomobject]@{
            Phase = $Phase
            Status = $Status
            ReturnCode = $ReturnCode
            Step = $Step
        }
    }
    function Test-Cmd { param([string]$Name) return ($Name -eq 'winget') }
    function winget {
        $arguments = @($args | ForEach-Object { [string]$_ })
        $global:SetupAiFakeWingetCalls += [pscustomobject]@{ Arguments = $arguments }
        if ($arguments -contains 'list') {
            if ($arguments -notcontains '--accept-source-agreements') {
                'Source agreements not accepted'
                $global:LASTEXITCODE = -1978335166
            } else {
                "$script:FakeWingetId 1.0"
                $global:LASTEXITCODE = 0
            }
            return
        }
        if ($arguments -contains 'install') {
            if ($script:FakeWingetMode -eq 'unexpected-install-failure') {
                'unexpected install failure'
                $global:LASTEXITCODE = 17
            } else {
                'Package already installed'
                $global:LASTEXITCODE = -1978335189
            }
            return
        }
        throw "Unexpected winget invocation: $($arguments -join ' ')"
    }

    foreach ($functionName in $wingetFunctionNames) {
        $definition = @($wingetFunctions | Where-Object { $_.Name -eq $functionName })
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }

    $listed = Test-WingetInstalled -Id $script:FakeWingetId -Phase 'base'
    if (-not $listed) { throw 'winget list did not accept source agreements non-interactively.' }
    $listCall = @($global:SetupAiFakeWingetCalls | Where-Object { $_.Arguments -contains 'list' })[0]
    if ($null -eq $listCall -or $listCall.Arguments -notcontains '--accept-source-agreements') {
        throw 'winget list did not receive --accept-source-agreements.'
    }

    $script:WingetStepResults = @()
    $script:WingetLogEvents = @()
    function Test-WingetInstalled { param([string]$Id, [string]$Phase) return $false }
    Install-Winget -Id $script:FakeWingetId -Phase 'base'
    $installExpected = @($script:WingetLogEvents | Where-Object { $_.Event -eq 'step_expected' })
    if ($installExpected.Count -ne 1 -or $installExpected[0].Message -notmatch '-1978335189') {
        throw 'UPDATE_NOT_APPLICABLE was not logged as an expected winget result.'
    }
    if ($installExpected[0].ReturnCode -ne -1978335189) {
        throw 'step_expected did not log the observed native exit code in the structured rc field.'
    }
    $alreadyPresent = @($script:WingetLogEvents | Where-Object { $_.Event -eq 'already_present' })
    if ($alreadyPresent.Count -ne 1 -or $alreadyPresent[0].Message -notmatch 'UPDATE_NOT_APPLICABLE') {
        throw 'UPDATE_NOT_APPLICABLE did not produce truthful already-present logging.'
    }
    if ($script:WingetStepResults.Count -ne 1 -or $script:WingetStepResults[0].Status -ne 'installed' -or $script:WingetStepResults[0].ReturnCode -ne 0) {
        throw 'UPDATE_NOT_APPLICABLE did not retain successful install step accounting.'
    }

    $script:FakeWingetMode = 'unexpected-install-failure'
    $script:WingetStepResults = @()
    $script:WingetLogEvents = @()
    $failed = $false
    try { Install-Winget -Id $script:FakeWingetId -Phase 'base' } catch { $failed = $true }
    if (-not $failed -or $script:WingetStepResults.Count -ne 1 -or $script:WingetStepResults[0].Status -ne 'failed') {
        throw 'An unrelated winget install failure was swallowed.'
    }
} finally {
    Remove-Item -LiteralPath $wingetTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}


# Same-event parity with bash (#84): every ERROR record must carry a ReturnCode so it
# emits the `err` object. Write-Log defaults the code to 0, which silently drops `err`.
$errorCalls = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'Write-Log' -and
    $node.CommandElements.Count -gt 1 -and $node.CommandElements[1].Extent.Text -eq 'ERROR'
}, $true))
if ($errorCalls.Count -eq 0) { throw 'No Write-Log ERROR call sites found.' }
foreach ($call in $errorCalls) {
    $positional = 0
    foreach ($element in $call.CommandElements) {
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) { break }
        $positional++
    }
    # Write-Log, Level, Phase, Event, Message, ReturnCode
    if ($positional -lt 6) { throw "Write-Log ERROR without ReturnCode at line $($call.Extent.StartLineNumber)." }
}
Write-Host 'PowerShell lifecycle regression checks passed.'
