#requires -Version 5.1
<#
.SYNOPSIS
Standalone assertions for Update-CompletionTracker. Run with:
  powershell -File tests\Update-CompletionTracker.tests.ps1
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'LocalGitMigrationTool.ps1') -NoGui

function Assert-Equal([string]$Expected, [string]$Actual, [string]$Because) {
    if ($Actual -ne $Expected) { throw "FAILED: $Because -- expected '$Expected' but got '$Actual'" }
    Write-Host "PASS: $Because"
}

$fixtureRoot = Join-Path $env:TEMP "local-git-migration-tracker-tests-$(Get-Random)"
$trackerPath = Join-Path $fixtureRoot 'Complete.json'
$originalPaths = $completionTrackerPaths
$originalDriveLetters = $completionTrackerDriveLetters

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $completionTrackerPaths = @($trackerPath)
    $completionTrackerDriveLetters = @()

    Update-CompletionTracker -GitHubUser 'test-user' -Repositories @('alpha', 'beta')
    Update-CompletionTracker -GitHubUser 'test-user' -Repositories @('beta', 'gamma')

    $entry = (Get-Content -LiteralPath $trackerPath -Raw | ConvertFrom-Json).'test-user'
    Assert-Equal -Expected 'alpha,beta,gamma' -Actual ($entry.Repositories -join ',') -Because 'tracker adds new repositories without duplicating previous ones'
    Assert-Equal -Expected $env:COMPUTERNAME -Actual $entry.Machine -Because 'tracker records the machine name'
} finally {
    $completionTrackerPaths = $originalPaths
    $completionTrackerDriveLetters = $originalDriveLetters
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
