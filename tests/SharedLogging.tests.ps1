#requires -Version 5.1
<#
.SYNOPSIS
Standalone assertions for shared diagnostic logging. Run with:
  powershell -File tests\SharedLogging.tests.ps1
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'LocalGitMigrationTool.ps1') -NoGui

function Assert-Equal([string]$Expected, [string]$Actual, [string]$Because) {
    if ($Actual -ne $Expected) { throw "FAILED: $Because -- expected '$Expected' but got '$Actual'" }
    Write-Host "PASS: $Because"
}

$fixtureRoot = Join-Path $env:TEMP "local-git-migration-log-tests-$(Get-Random)"
try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    Assert-Equal -Expected 'True' -Actual (Test-SharedLogDirectory $fixtureRoot) -Because 'shared log directory is writable'

    Set-SharedLogDirectory $fixtureRoot
    Write-RunLog 'test log entry'
    Rename-SharedLog 3

    Assert-Equal -Expected 'True' -Actual (Test-Path -LiteralPath $script:logPath) -Because 'renamed shared log exists'
    Assert-Equal -Expected 'True' -Actual ([System.IO.Path]::GetFileName($script:logPath) -match "^$([regex]::Escape($env:USERNAME))_\d{8}-\d{6}_3-repos\.log$") -Because 'log file name includes user, timestamp, and repository count'
    Assert-Equal -Expected 'True' -Actual ((Get-Content -LiteralPath $script:logPath -Raw) -match 'test log entry') -Because 'shared log contains diagnostic messages'
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
