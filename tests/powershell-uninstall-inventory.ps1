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
    'Get-OpenCodeEnvReceiptState', 'Write-OpenCodeEnvReceipt',
    'Get-OpenCodeEnvInventoryStatus', 'Remove-OpenCodeUserEnvironment',
    'Get-RotatorTask', 'Get-RotatorTaskReceipt', 'Test-RotatorTaskOwned', 'Remove-LegacyRotatorTask',
    'Get-WindowsModuleInventory', 'Invoke-WindowsEnvironmentUninstall'
)
$functions = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames
}, $true))
foreach ($functionAst in $functions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('setup-ai-uninst-inv-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $testRoot 'localappdata'

$script:FakeUserEnvironment = @{}
function Get-SetupAiUserEnvironmentValue {
    param([string]$Name)
    if ($script:FakeUserEnvironment.ContainsKey($Name)) { return $script:FakeUserEnvironment[$Name] }
    return $null
}
function Set-SetupAiUserEnvironmentValue {
    param($Name, $Value)
    if ($null -eq $Value) { $script:FakeUserEnvironment.Remove($Name) | Out-Null }
    else { $script:FakeUserEnvironment[$Name] = [string]$Value }
}
function Get-RotatorTask { return $null }
function Write-Log { param($Level, $Phase, $Event, $Message, $ReturnCode, $Meta) }

$ModuleOrder = @('base','node','bun','pi','dotenv','ai-memory','lazyvim','pi-packages','go','ee','skills','pi-workflows','herdr','claude-code','codex','antigravity','opencode','gentle-ai','cockpit','cliproxyapi','extras')
$ModuleDesc = @{}
foreach ($m in $ModuleOrder) { $ModuleDesc[$m] = $m }

try {
    # 1. Test inventory enumeration without mutations
    $inv = Get-WindowsModuleInventory -ModuleName 'base'
    if (-not $inv -or $inv[0].Classification -ne 'protected') {
        throw "Base WinGet packages must be classified as protected"
    }

    $invPi = Get-WindowsModuleInventory -ModuleName 'pi'
    if (-not $invPi -or $invPi[0].Classification -ne 'protected') {
        throw "Pi shared root must be classified as protected"
    }

    $invDotenv = Get-WindowsModuleInventory -ModuleName 'dotenv'
    if (-not $invDotenv -or $invDotenv[0].Classification -ne 'absent') {
        throw "Linux dotenv on Windows must be classified as absent"
    }

    # 2. Test corrupt/stale receipt on opencode reports protected
    $receiptPath = Get-SetupAiEnvironmentReceiptPath -Name 'OPENCODE_PI_BIN'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $receiptPath) | Out-Null
    Set-Content -LiteralPath $receiptPath -Value 'corrupt json receipt'
    $script:FakeUserEnvironment['OPENCODE_PI_BIN'] = 'C:\fake\pi.exe'

    $invOpencode = Get-WindowsModuleInventory -ModuleName 'opencode'
    $envItem = $invOpencode | Where-Object { $_.Resource -eq 'User OPENCODE_PI_BIN' }
    if ($envItem.Classification -ne 'protected') {
        throw "Corrupt receipt must classify resource as protected, got: $($envItem.Classification)"
    }

    # 3. Test valid receipt reports receipt-backed
    Remove-Item -LiteralPath $receiptPath -Force
    Write-OpenCodeEnvReceipt -Value 'C:\fake\pi.exe' | Out-Null
    $invOpencodeValid = Get-WindowsModuleInventory -ModuleName 'opencode'
    $validItem = $invOpencodeValid | Where-Object { $_.Resource -eq 'User OPENCODE_PI_BIN' }
    if ($validItem.Classification -ne 'receipt-backed') {
        throw "Valid receipt must classify resource as receipt-backed, got: $($validItem.Classification)"
    }

    # 4. Test dry-run does not mutate state even with -Yes
    $All = $true
    $OnlySpecified = $false
    $Only = ''
    $Yes = $true
    $DryRun = $true
    $res = Invoke-WindowsEnvironmentUninstall
    if ($script:FakeUserEnvironment['OPENCODE_PI_BIN'] -ne 'C:\fake\pi.exe') {
        throw "-DryRun -Yes must not mutate environment values"
    }
    if ($res -ne 0) { throw "Invoke-WindowsEnvironmentUninstall failed with exit code $res" }

    # 5. Test -Yes without -DryRun removes receipt-backed resource
    $DryRun = $false
    $res2 = Invoke-WindowsEnvironmentUninstall
    if ($script:FakeUserEnvironment.ContainsKey('OPENCODE_PI_BIN')) {
        throw "-Yes without -DryRun should have removed receipt-backed OPENCODE_PI_BIN"
    }
    if ($res2 -ne 0) { throw "Removal failed with exit code $res2" }

    Write-Host 'PASS: powershell-uninstall-inventory tests passed successfully.'
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
