#requires -Version 5.1
<#!
.SYNOPSIS
Standalone assertions for Test-ForkGitHubAccount. Run with:
  powershell -File tests\Test-ForkGitHubAccount.tests.ps1
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'GitRemoteSwitcher.ps1') -NoGui

function Assert-Equal([string]$Expected, [string]$Actual, [string]$Because) {
    if ($Actual -ne $Expected) {
        throw "FAILED: $Because -- expected '$Expected' but got '$Actual'"
    }
    Write-Host "PASS: $Because"
}

$fixtureRoot = Join-Path $env:TEMP "grs-fork-check-tests-$(Get-Random)"
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$originalLocalAppData = $env:LOCALAPPDATA

try {
    # NotInstalled: LOCALAPPDATA path with no Fork subfolder at all
    $notInstalledRoot = Join-Path $fixtureRoot 'not-installed'
    New-Item -ItemType Directory -Path $notInstalledRoot -Force | Out-Null
    $env:LOCALAPPDATA = $notInstalledRoot
    Assert-Equal -Expected 'NotInstalled' -Actual (Test-ForkGitHubAccount) -Because 'Fork folder does not exist'

    # NotFound: Fork folder exists, accounts.json has no GitHub reference
    $notFoundRoot = Join-Path $fixtureRoot 'not-found'
    New-Item -ItemType Directory -Path (Join-Path $notFoundRoot 'Fork') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $notFoundRoot 'Fork\accounts.json') -Value '[{"Type":"GitLab","Username":"someone"}]' -Encoding UTF8
    $env:LOCALAPPDATA = $notFoundRoot
    Assert-Equal -Expected 'NotFound' -Actual (Test-ForkGitHubAccount) -Because 'accounts.json has no GitHub reference'

    # NotFound: Fork folder exists, accounts.json is empty
    $emptyRoot = Join-Path $fixtureRoot 'empty'
    New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'Fork') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $emptyRoot 'Fork\accounts.json') -Value '' -Encoding UTF8
    $env:LOCALAPPDATA = $emptyRoot
    Assert-Equal -Expected 'NotFound' -Actual (Test-ForkGitHubAccount) -Because 'accounts.json is empty'

    # Found: Fork folder exists, accounts.json has a GitHub reference
    $foundRoot = Join-Path $fixtureRoot 'found'
    New-Item -ItemType Directory -Path (Join-Path $foundRoot 'Fork') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $foundRoot 'Fork\accounts.json') -Value '[{"Type":"GitHub","Username":"someone"}]' -Encoding UTF8
    $env:LOCALAPPDATA = $foundRoot
    Assert-Equal -Expected 'Found' -Actual (Test-ForkGitHubAccount) -Because 'accounts.json has a GitHub type reference'

    # Found: reference is a github.com URL rather than a "Type" field
    $foundUrlRoot = Join-Path $fixtureRoot 'found-url'
    New-Item -ItemType Directory -Path (Join-Path $foundUrlRoot 'Fork') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $foundUrlRoot 'Fork\accounts.json') -Value '[{"Host":"https://github.com","Username":"someone"}]' -Encoding UTF8
    $env:LOCALAPPDATA = $foundUrlRoot
    Assert-Equal -Expected 'Found' -Actual (Test-ForkGitHubAccount) -Because 'accounts.json has a github.com URL reference'

    # CouldNotVerify: accounts.json is malformed JSON
    $corruptRoot = Join-Path $fixtureRoot 'corrupt'
    New-Item -ItemType Directory -Path (Join-Path $corruptRoot 'Fork') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $corruptRoot 'Fork\accounts.json') -Value '{not valid json!!' -Encoding UTF8
    $env:LOCALAPPDATA = $corruptRoot
    Assert-Equal -Expected 'CouldNotVerify' -Actual (Test-ForkGitHubAccount) -Because 'accounts.json is malformed'

    Write-Host "All Test-ForkGitHubAccount assertions passed."
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
