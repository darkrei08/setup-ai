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

& (Get-Process -Id $PID).Path -NoLogo -NoProfile -File (Join-Path $PSScriptRoot 'rotator-task-receipts.ps1'); if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host 'PowerShell lifecycle regression checks passed.'
