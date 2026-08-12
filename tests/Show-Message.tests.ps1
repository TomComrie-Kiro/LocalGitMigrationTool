#requires -Version 5.1
<#!
.SYNOPSIS
Standalone assertions for Show-Message and the message catalog. Run with:
  powershell -File tests\Show-Message.tests.ps1
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'GitRemoteSwitcher.ps1') -NoGui

function Assert-Equal([string]$Expected, [string]$Actual, [string]$Because) {
    if ($Actual -ne $Expected) {
        throw "FAILED: $Because -- expected '$Expected' but got '$Actual'"
    }
    Write-Host "PASS: $Because"
}

function Assert-True([bool]$Condition, [string]$Because) {
    if (-not $Condition) { throw "FAILED: $Because" }
    Write-Host "PASS: $Because"
}

# Catalog validation: every entry has a valid severity and non-empty text
$validSeverities = @('Info', 'Warning', 'Error', 'Fatal')
foreach ($id in $script:messages.Keys) {
    $entry = $script:messages[$id]
    Assert-True ($validSeverities -contains $entry.Severity) "catalog entry '$id' has a valid severity"
    Assert-True (-not [string]::IsNullOrWhiteSpace($entry.Text)) "catalog entry '$id' has non-empty text"
}

# Test-only catalog entries covering each severity, so this test doesn't depend on
# which real IDs currently use which severity.
$script:messages['__TestInfo']    = @{ Severity = 'Info';    Text = 'info {0}' }
$script:messages['__TestWarning'] = @{ Severity = 'Warning'; Text = 'warning {0}' }
$script:messages['__TestError']   = @{ Severity = 'Error';   Text = 'error {0}' }
$script:messages['__TestFatal']   = @{ Severity = 'Fatal';   Text = 'fatal {0}' }

Show-Message -Id '__TestInfo' -Control $controls.AccessStatus -FormatArgs @('one') | Out-Null
Assert-Equal -Expected 'info one' -Actual $controls.AccessStatus.Text -Because 'Show-Message formats placeholders for Info'
Assert-Equal -Expected '#FF52606D' -Actual $controls.AccessStatus.Foreground.ToString() -Because 'Info uses the neutral gray color'

Show-Message -Id '__TestWarning' -Control $controls.AccessStatus -FormatArgs @('two') | Out-Null
Assert-Equal -Expected 'warning two' -Actual $controls.AccessStatus.Text -Because 'Show-Message formats placeholders for Warning'
Assert-Equal -Expected '#FF9A6700' -Actual $controls.AccessStatus.Foreground.ToString() -Because 'Warning uses the amber color'

Show-Message -Id '__TestError' -Control $controls.AccessStatus -FormatArgs @('three') | Out-Null
Assert-Equal -Expected 'error three' -Actual $controls.AccessStatus.Text -Because 'Show-Message formats placeholders for Error'
Assert-Equal -Expected '#FFB42318' -Actual $controls.AccessStatus.Foreground.ToString() -Because 'Error uses the red color'

# Fatal: under -NoGui this must NOT show a blocking MessageBox, or this test process
# would hang forever with no one present to dismiss it.
Show-Message -Id '__TestFatal' -Control $controls.AccessStatus -FormatArgs @('four') | Out-Null
Assert-Equal -Expected 'fatal four' -Actual $controls.AccessStatus.Text -Because 'Show-Message formats placeholders for Fatal'
Assert-Equal -Expected '#FFB42318' -Actual $controls.AccessStatus.Foreground.ToString() -Because 'Fatal uses the red color'
Write-Host "PASS: Show-Message with Fatal severity did not hang under -NoGui (test reached this line)"

# Logging integration
$beforeLog = if (Test-Path -LiteralPath $script:logPath) { Get-Content -LiteralPath $script:logPath -Raw } else { '' }
Show-Message -Id '__TestInfo' -Control $controls.AccessStatus -FormatArgs @('logtest') | Out-Null
$afterLog = Get-Content -LiteralPath $script:logPath -Raw
Assert-True ($afterLog.Length -gt $beforeLog.Length -and $afterLog -match 'INFO \[__TestInfo\] info logtest') 'Show-Message writes a log line via Write-RunLog'

Write-Host "All Show-Message assertions passed."
