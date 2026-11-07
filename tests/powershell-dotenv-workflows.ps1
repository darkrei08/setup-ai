$ErrorActionPreference = 'Stop'
$setup = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-ai.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Raw -LiteralPath $setup), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "setup-ai.ps1 has parse errors: $($parseErrors -join '; ')" }

$functionNames = @(
    'Add-LineIfMissing', 'Enable-NpmRemoteSources',
    'Link-DotenvWorkflowExtensions', 'Mod-PiWorkflows'
)
$functions = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames
}, $true))
if ($functions.Count -ne $functionNames.Count) { throw 'Expected dotenv workflow functions in setup-ai.ps1.' }
foreach ($functionAst in $functions) { . ([scriptblock]::Create($functionAst.Extent.Text)) }

$script:FakeNpmMode = 'normal'
$script:FakeNpmCalls = @()
$script:FakePiCalls = @()
$script:RetryProbeCalls = @()
$script:LogEvents = @()

function Write-Log {
    param($Level, $Phase, $Event, $Message, $ReturnCode = 0, $Meta = '')
    $script:LogEvents += [pscustomobject]@{ Level = $Level; Phase = $Phase; Event = $Event; Message = $Message; Meta = $Meta }
}
function Test-Cmd {
    param([string]$Name)
    return $Name -in @('node', 'npm', 'pi')
}
function Assert-NodeMinimum { }
function Assert-TransientRenameRetry {
    param([string]$IoJs, [string]$Phase, [string]$Context)
    $script:RetryProbeCalls += $IoJs
    return $true
}
function Invoke-Step {
    param(
        [string]$Phase,
        [scriptblock]$Action,
        [switch]$Optional,
        [switch]$Verify
    )
    $global:LASTEXITCODE = 0
    & $Action | Out-Null
    if ($global:LASTEXITCODE -ne 0) { throw "fake step failed: $Phase" }
    return $true
}
function pi {
    $script:FakePiCalls += @($args | ForEach-Object { [string]$_ })
    $global:LASTEXITCODE = 0
}
function Install-PiPackageOwned {
    param([string]$Phase, [string]$Spec)
    pi install $Spec
}
function npm {
    $arguments = @($args | ForEach-Object { [string]$_ })
    $script:FakeNpmCalls += [pscustomobject]@{ Directory = (Get-Location).Path; Arguments = $arguments }
    $global:LASTEXITCODE = 0
    if ($arguments -contains '--version') {
        '12.4.0'
        return
    }
    if ($arguments -contains 'view') {
        '7.8.9'
        return
    }
    if ($arguments -contains 'install') {
        $packageSpec = $arguments[-1]
        $version = ($packageSpec -split '@')[-1]
        $currentDir = (Get-Location).Path
        $isDotenv = $currentDir -eq (Resolve-Path -LiteralPath $script:FakeDotenvExt).Path
        $packageDir = Join-Path $currentDir 'node_modules/pi-extensible-workflows'
        if ($isDotenv -and $script:FakeNpmMode -eq 'missing') {
            Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        if ($isDotenv -and $script:FakeNpmMode -eq 'mismatch') { $version = '0.0.1' }
        New-Item -ItemType Directory -Force -Path (Join-Path $packageDir 'dist/src') | Out-Null
        Set-Content -LiteralPath (Join-Path $packageDir 'package.json') -Value (@{ name = 'pi-extensible-workflows'; version = $version } | ConvertTo-Json)
        Set-Content -LiteralPath (Join-Path $packageDir 'dist/src/io.js') -Value 'renameWithRetry'
        return
    }
    throw "Unexpected fake npm invocation: $($arguments -join ' ')"
}

function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('setup-ai-dotenv-' + [Guid]::NewGuid().ToString('N'))
    $dotenv = Join-Path $root 'dotenv'
    $dotenvExt = Join-Path $dotenv 'pi/agent/extensions/pi-ext-workflows'
    $piAgent = Join-Path $root 'pi-agent'
    $piExt = Join-Path $piAgent 'extensions'
    $piNpm = Join-Path $piAgent 'npm'
    $sourceBarrel = Join-Path $dotenv 'pi/agent/extensions/piextworkflows.ts'
    New-Item -ItemType Directory -Force -Path $dotenvExt, $piExt, $piNpm | Out-Null
    Set-Content -LiteralPath (Join-Path $dotenvExt 'develop-issues.ts') -Value 'source'
    Set-Content -LiteralPath $sourceBarrel -Value 'source barrel'
    Set-Content -LiteralPath (Join-Path $piNpm 'package.json') -Value '{"name":"pi-npm","private":true}'
    $staleDir = Join-Path $root 'stale-workflows'
    New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
    Set-Content -LiteralPath (Join-Path $staleDir 'develop-issues.ts') -Value 'stale'
    New-Item -ItemType SymbolicLink -Path (Join-Path $piExt 'pi-ext-workflows') -Target $staleDir | Out-Null
    $staleBarrel = Join-Path $root 'stale-barrel.ts'
    Set-Content -LiteralPath $staleBarrel -Value 'stale barrel'
    New-Item -ItemType SymbolicLink -Path (Join-Path $piExt 'piextworkflows.ts') -Target $staleBarrel | Out-Null
    Set-Content -LiteralPath (Join-Path $piNpm 'node_modules-marker') -Value 'present'
    return [pscustomobject]@{
        Root = $root; DotenvDir = $dotenv; DotenvExt = $dotenvExt; SourceBarrel = $sourceBarrel
        PiAgentDir = $piAgent; PiExtDir = $piExt; PiNpmDir = $piNpm
    }
}

function Set-FixtureVariables {
    param($Fixture)
    $script:FakeDotenvExt = $Fixture.DotenvExt
    $script:SetupAiWorkflowVersion = ''
    $script:DotenvDir = $Fixture.DotenvDir
    $script:PiAgentDir = $Fixture.PiAgentDir
    $script:PiExtDir = $Fixture.PiExtDir
    $script:PiNpmDir = $Fixture.PiNpmDir
    $script:DryRun = $false
    $env:PI_WORKFLOW_VERSION = '7.8.9'
}

function Invoke-WorkflowModule {
    $script:FakeNpmCalls = @()
    $script:FakePiCalls = @()
    $script:RetryProbeCalls = @()
    Mod-PiWorkflows | Out-Null
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected=$Expected actual=$Actual)" }
}

$fixture = New-Fixture
try {
    Set-FixtureVariables -Fixture $fixture
    Invoke-WorkflowModule

    $dotenvInstall = @($script:FakeNpmCalls | Where-Object {
        $_.Directory -eq (Resolve-Path -LiteralPath $fixture.DotenvExt).Path -and $_.Arguments -contains 'install'
    })
    Assert-Equal $dotenvInstall.Count 1 'dotenv extensions did not receive its own npm install'
    Assert-True ($dotenvInstall[0].Arguments -contains 'pi-extensible-workflows@7.8.9') 'dotenv install did not use the resolved workflow version'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.DotenvExt '.npmrc')) 'dotenv .npmrc was not created'
    $dotenvNpmrc = Get-Content -Raw -LiteralPath (Join-Path $fixture.DotenvExt '.npmrc')
    Assert-True ($dotenvNpmrc -match '(?m)^allow-remote=all$') 'dotenv npm 12 remote-source opt-in is missing'
    Assert-True ($dotenvNpmrc -match '(?m)^ignore-scripts=false$') 'dotenv ignore-scripts=false is missing'
    $dotenvPackage = Join-Path $fixture.DotenvExt 'node_modules/pi-extensible-workflows/package.json'
    Assert-Equal ((Get-Content -Raw -LiteralPath $dotenvPackage | ConvertFrom-Json).version) '7.8.9' 'dotenv package version was not verified'

    Assert-Equal $script:RetryProbeCalls.Count 3 'transient-rename probe did not cover all three roots'
    Assert-True (@($script:RetryProbeCalls | Where-Object { $_ -like "*$($fixture.DotenvExt)*" }).Count -gt 0) 'dotenv root was not probed for transient rename retry'

    $targetDir = Join-Path $fixture.PiExtDir 'pi-ext-workflows'
    $targetBarrel = Join-Path $fixture.PiExtDir 'piextworkflows.ts'
    Assert-Equal (Get-Item -Force -LiteralPath $targetDir).Target (Resolve-Path -LiteralPath $fixture.DotenvExt).Path 'stale extension symlink was not repointed'
    Assert-Equal (Get-Item -Force -LiteralPath $targetBarrel).Target (Resolve-Path -LiteralPath $fixture.SourceBarrel).Path 'stale barrel symlink was not repointed'
    Link-DotenvWorkflowExtensions -SourceDir $fixture.DotenvExt -TargetDir $targetDir -SourceBarrel $fixture.SourceBarrel -TargetBarrel $targetBarrel | Out-Null
    Assert-Equal (Get-Item -Force -LiteralPath $targetDir).Target (Resolve-Path -LiteralPath $fixture.DotenvExt).Path 'correct extension symlink was not left valid'
    Assert-Equal (Get-Item -Force -LiteralPath $targetBarrel).Target (Resolve-Path -LiteralPath $fixture.SourceBarrel).Path 'correct barrel symlink was not left valid'

    $script:FakeNpmMode = 'missing'
    $failedMissing = $false
    try { Invoke-WorkflowModule } catch { $failedMissing = $true }
    Assert-True $failedMissing 'missing dotenv artifact did not fail the module'

    $script:FakeNpmMode = 'mismatch'
    $failedMismatch = $false
    try { Invoke-WorkflowModule } catch { $failedMismatch = $true }
    Assert-True $failedMismatch 'dotenv version mismatch did not fail the module'

    Write-Host 'PASS: powershell dotenv workflow parity tests passed successfully.'
} finally {
    Remove-Item Env:PI_WORKFLOW_VERSION -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
}
