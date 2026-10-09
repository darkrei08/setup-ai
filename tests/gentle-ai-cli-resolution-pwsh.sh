#!/usr/bin/env bash
# Exercises Resolve-GentleAiCli from setup-ai.ps1 against vendor go-install layouts.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: pwsh unavailable; PowerShell gentle-ai resolver not exercised\n'
    exit 0
fi

PS1="$(mktemp "${TMPDIR:-/tmp}/gai-resolver.XXXXXXXX.ps1")"
trap 'rm -f -- "${PS1}"' EXIT
cat > "${PS1}" <<'PS'
$ErrorActionPreference = 'Stop'
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $env:ROOT 'setup-ai.ps1'), [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-GentleAiCli' }, $true)
if ($null -eq $fn) { throw 'Resolve-GentleAiCli not found' }
$base = Join-Path ([IO.Path]::GetTempPath()) ('setup-ai-gai-' + [guid]::NewGuid().ToString('N'))
$script:Logs = 0
function Write-Log { $script:Logs++ }
function Test-Cmd { param([string]$Name) $false }
. ([scriptblock]::Create($fn.Extent.Text))
$origPath = $env:Path
function Case($name, $dir, $setup) {
    $env:Path = $origPath; $script:Logs = 0
    $env:GOBIN = $null; $env:GOPATH = $null; $env:LOCALAPPDATA = Join-Path $base 'none'; $env:USERPROFILE = Join-Path $base 'nohome'
    & $setup
    Resolve-GentleAiCli
    $expected = if ($dir) { $dir } else { $null }
    $hit = $expected -and $env:Path.StartsWith("$expected;")
    if ($expected -and -not $hit) { throw "FAIL: $name not resolved" }
    if (-not $expected -and ($env:Path -ne $origPath -or $script:Logs -ne 0)) { throw "FAIL: $name changed state" }
    Write-Output "PASS: $name"
}
function Mk($d) { New-Item -ItemType Directory -Force -Path $d | Out-Null; New-Item -ItemType File -Force -Path (Join-Path $d 'gentle-ai.exe') | Out-Null }
try {
    $g = Join-Path $base 'gobin';  Case 'GOBIN' $g { Mk $g; $env:GOBIN = $g }
    $p = Join-Path $base 'gp';     Case 'GOPATH\bin' (Join-Path $p 'bin') { Mk (Join-Path $p 'bin'); $env:GOPATH = $p }
    $u = Join-Path $base 'home';   Case 'USERPROFILE\go\bin' (Join-Path $u 'go\bin') { Mk (Join-Path $u 'go\bin'); $env:USERPROFILE = $u }
    $l = Join-Path $base 'lad';    Case 'legacy LOCALAPPDATA' (Join-Path $l 'gentle-ai\bin') { Mk (Join-Path $l 'gentle-ai\bin'); $env:LOCALAPPDATA = $l }
    Case 'absent' $null { }
} finally { Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue }
PS
ROOT="${ROOT}" pwsh -NoProfile -File "${PS1}"
