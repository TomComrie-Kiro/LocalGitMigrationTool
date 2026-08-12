# Message/Error-Handling Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give GitRemoteSwitcher a consistent way to show info/warning/error/fatal messages to the user (color-coded, logged, with fatal conditions also raising a blocking popup), retrofit every existing status message onto it, and expand each wizard step's explanatory text.

**Architecture:** A central `$script:messages` hashtable maps short IDs to `{ Severity, Text }` entries (`Text` may contain `{0}`/`{1}`-style placeholders). A new `Show-Message` function looks up an ID, formats it, sets a target `TextBlock`'s `.Text` and `.Foreground` by severity, always logs via the existing `Write-RunLog`, and for `Fatal` severity also raises a blocking `MessageBox` (skipped under `-NoGui` for testability). Every existing status-text call site and the two existing failure `MessageBox` calls are migrated to this mechanism.

**Tech Stack:** PowerShell 5.1, WPF (PresentationFramework) — matches the existing single-file script, no new dependencies.

## Global Constraints

- Four severities only: Info, Warning, Error, Fatal — per spec's "Severity levels and display" section.
- Colors: Info `#52606D`, Warning `#9A6700`, Error `#B42318`, Fatal `#B42318` (same as Error) plus a blocking `MessageBox` — exact values from the spec.
- `Show-Message`'s `Fatal` branch must check `$NoGui` and skip the `MessageBox.Show` call when set, so automated tests never block — per spec's "Testing approach" section.
- Out of scope for this plan: `DataGrid` cell coloring (Step 3/5 warning text stays plain), the two existing OK/Cancel confirmation dialogs (GitHub CLI install, restore remotes) stay as direct `MessageBox.Show` calls, no new error/warning scenarios beyond what already exists in the script today.
- No new external dependencies.

---

### Task 1: Add the message catalog and `Show-Message` function

**Files:**
- Modify: `GitRemoteSwitcher.ps1` (add `$script:messages` catalog near the other script-scoped variables; add `Show-Message` function after `Ensure-GitHubCli` and before `Find-GitHubReference`)
- Create: `tests/Show-Message.tests.ps1`

**Interfaces:**
- Consumes: the existing `-NoGui` seam, `$controls`, `Write-RunLog`.
- Produces: `Show-Message([string]$Id, $Control, [object[]]$FormatArgs)` — looks up `$Id` in `$script:messages`, formats `Text` with `-f $FormatArgs` if provided, sets `$Control.Text` and `$Control.Foreground`, calls `Write-RunLog`, shows a blocking `MessageBox` for `Fatal` severity unless `$NoGui` is set, and returns the severity string. Consumed by every call site migrated in Task 2.

- [ ] **Step 1: Write the failing tests**

Create `tests/Show-Message.tests.ps1`:
```powershell
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
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
powershell -NoProfile -File tests\Show-Message.tests.ps1
```
Expected: fails, either because `$script:messages` doesn't exist yet or `Show-Message` is not recognized.

- [ ] **Step 3: Add the message catalog**

In `GitRemoteSwitcher.ps1`, change:
```powershell
$script:accessVerified = $false
$script:forkStatus = 'NotInstalled'
$script:currentStep = 1
```
to:
```powershell
$script:accessVerified = $false
$script:forkStatus = 'NotInstalled'
$script:currentStep = 1
$script:messages = @{
    'GitNotInstalled'           = @{ Severity = 'Fatal';   Text = 'Git is not installed or is not available in PATH. Install Git for Windows, then restart this tool.' }
    'SignInNotCompleted'        = @{ Severity = 'Error';   Text = 'GitHub sign-in was not completed.' }
    'OrgMembershipUnconfirmed'  = @{ Severity = 'Error';   Text = 'Signed in as {0}, but GitHub could not confirm {1} membership. Sign in again and approve organisation access, or contact Tom Comrie.' }
    'OrgMembershipInactive'     = @{ Severity = 'Error';   Text = 'Signed in as {0}, but this account is not an active member of {1}. Accept the organisation invitation for this exact account, or contact Tom Comrie.' }
    'SignedIn'                  = @{ Severity = 'Info';    Text = 'Signed in as {0}. Your {1} organisation access is confirmed.' }
    'SigningIn'                 = @{ Severity = 'Info';    Text = 'Complete the GitHub sign-in in your browser...' }
    'InstallingGitHubCli'       = @{ Severity = 'Info';    Text = 'Installing GitHub CLI. Approve the Windows elevation prompt if shown...' }
    'WingetNotFound'            = @{ Severity = 'Fatal';   Text = 'Windows Package Manager (winget) was not found. Install GitHub CLI manually, then restart this tool.' }
    'GitHubCliInstallFailed'    = @{ Severity = 'Fatal';   Text = 'GitHub CLI could not be installed. Contact Tom Comrie for assistance.' }
    'ForkNotInstalled'          = @{ Severity = 'Info';    Text = 'Fork was not detected on this machine; skipping the Fork account check.' }
    'ForkFound'                 = @{ Severity = 'Info';    Text = 'Fork has a GitHub account configured.' }
    'ForkNotFound'              = @{ Severity = 'Warning'; Text = 'Fork does not have a GitHub account configured. Open Fork -> Preferences -> Accounts, add your GitHub account, then click Re-check Fork.' }
    'ForkCouldNotVerify'        = @{ Severity = 'Info';    Text = "Could not verify Fork's GitHub account automatically. Check Fork -> Preferences -> Accounts manually." }
    'ScanComplete'              = @{ Severity = 'Info';    Text = '{0} local Git repository(s) checked; {1} with a GitLab origin found; {2} target repository(s) are available on GitHub.' }
    'UpdateProgressMsg'         = @{ Severity = 'Info';    Text = 'Updating {0} of {1}: {2}' }
    'UpdateSummarySuccess'      = @{ Severity = 'Info';    Text = '{0} repository(s) updated successfully; {1} failed; {2} not updated. Refresh Fork to use the new remotes.' }
    'UpdateSummaryWithFailures' = @{ Severity = 'Warning'; Text = '{0} repository(s) updated successfully; {1} failed; {2} not updated. Refresh Fork to use the new remotes.' }
    'RestoreSummarySuccess'     = @{ Severity = 'Info';    Text = '{0} of {1} original remote(s) restored. Refresh Fork to see the restored origins.' }
    'RestoreSummaryWithFailures' = @{ Severity = 'Warning'; Text = '{0} of {1} original remote(s) restored. Refresh Fork to see the restored origins.' }
}
```

- [ ] **Step 4: Add the `Show-Message` function**

In `GitRemoteSwitcher.ps1`, insert immediately after the closing `}` of `Ensure-GitHubCli` and before `function Find-GitHubReference`:

```powershell
function Show-Message([string]$Id, $Control, [object[]]$FormatArgs) {
    $entry = $script:messages[$Id]
    $text = if ($FormatArgs) { $entry.Text -f $FormatArgs } else { $entry.Text }
    $color = switch ($entry.Severity) {
        'Info'    { '#52606D' }
        'Warning' { '#9A6700' }
        'Error'   { '#B42318' }
        'Fatal'   { '#B42318' }
    }
    $Control.Text = $text
    $Control.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    Write-RunLog "$($entry.Severity.ToUpper()) [$Id] $text"
    if ($entry.Severity -eq 'Fatal' -and -not $NoGui) {
        [System.Windows.MessageBox]::Show($text, 'Git Remote Switcher', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    return $entry.Severity
}
```

- [ ] **Step 5: Run the tests again to verify they pass**

Run:
```bash
powershell -NoProfile -File tests\Show-Message.tests.ps1
```
Expected: all assertions print `PASS:`, ending with `All Show-Message assertions passed.`, exit code 0, and the process does **not** hang (confirming the Fatal/`-NoGui` guard works).

- [ ] **Step 6: Verify dot-sourcing still works and existing tests still pass**

Run:
```bash
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
timeout 15 powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host 'DOT-SOURCE-OK'"
echo "EXIT: $?"
```
Expected: existing 8 assertions still pass; `DOT-SOURCE-OK` printed, exit 0.

- [ ] **Step 7: Commit**

```bash
git add GitRemoteSwitcher.ps1 tests/Show-Message.tests.ps1
git commit -m "Add message catalog and Show-Message function"
```

---

### Task 2: Retrofit existing call sites onto `Show-Message`

**Files:**
- Modify: `GitRemoteSwitcher.ps1` (`Verify-Access`, `Ensure-GitHubCli`, `Update-ForkStatusDisplay`, `Scan-Repositories`, `Update-SelectedRemotes`, `Restore-OriginalRemotes`, `LoginButton` click handler)

**Interfaces:**
- Consumes: `Show-Message` from Task 1, and every catalog ID defined in Task 1's Step 3.
- Produces: nothing new — same function signatures as before, only their internals change.

- [ ] **Step 1: Retrofit `Verify-Access`**

Change:
```powershell
function Verify-Access {
    $gitVersion = [string](& git --version 2>$null)
    if ($LASTEXITCODE -ne 0) { $controls.AccessStatus.Text = 'Git is not installed or is not available in PATH. Install Git for Windows, then restart this tool.'; return $false }
    $user = [string](& $script:ghCommand api user --jq '.login' 2>$null)
    $userExitCode = $LASTEXITCODE
    if ($userExitCode -ne 0) { $controls.AccessStatus.Text = 'GitHub sign-in was not completed.'; return $false }
    $state = [string](& $script:ghCommand api "user/memberships/orgs/$organisation" --jq '.state' 2>$null)
    $stateExitCode = $LASTEXITCODE
    if ($stateExitCode -ne 0) {
        $controls.AccessStatus.Text = "Signed in as $($user.Trim()), but GitHub could not confirm $organisation membership. Sign in again and approve organisation access, or contact Tom Comrie."
        return $false
    }
    if ($state.Trim() -ne 'active') {
        $controls.AccessStatus.Text = "Signed in as $($user.Trim()), but this account is not an active member of $organisation. Accept the organisation invitation for this exact account, or contact Tom Comrie."
        return $false
    }
    $controls.AccessStatus.Text = "Signed in as $($user.Trim()). Your $organisation organisation access is confirmed."
    Write-RunLog "PREFLIGHT Git=$($gitVersion.Trim()); GitHubUser=$($user.Trim()); Organisation=$organisation"
    return $true
}
```
to:
```powershell
function Verify-Access {
    $gitVersion = [string](& git --version 2>$null)
    if ($LASTEXITCODE -ne 0) { Show-Message -Id 'GitNotInstalled' -Control $controls.AccessStatus | Out-Null; return $false }
    $user = [string](& $script:ghCommand api user --jq '.login' 2>$null)
    $userExitCode = $LASTEXITCODE
    if ($userExitCode -ne 0) { Show-Message -Id 'SignInNotCompleted' -Control $controls.AccessStatus | Out-Null; return $false }
    $state = [string](& $script:ghCommand api "user/memberships/orgs/$organisation" --jq '.state' 2>$null)
    $stateExitCode = $LASTEXITCODE
    if ($stateExitCode -ne 0) {
        Show-Message -Id 'OrgMembershipUnconfirmed' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
        return $false
    }
    if ($state.Trim() -ne 'active') {
        Show-Message -Id 'OrgMembershipInactive' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
        return $false
    }
    Show-Message -Id 'SignedIn' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
    Write-RunLog "PREFLIGHT Git=$($gitVersion.Trim()); GitHubUser=$($user.Trim()); Organisation=$organisation"
    return $true
}
```
(The `PREFLIGHT` log line is a separate structured audit record, not a user-facing message — leave it as-is alongside `Show-Message`'s own logging.)

- [ ] **Step 2: Retrofit `Ensure-GitHubCli`**

Change:
```powershell
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        [System.Windows.MessageBox]::Show('Windows Package Manager (winget) was not found. Install GitHub CLI manually, then restart this tool.', 'Git Remote Switcher')
        return $false
    }
    $controls.AccessStatus.Text = 'Installing GitHub CLI. Approve the Windows elevation prompt if shown...'
    $process = Start-Process -FilePath $winget.Source -ArgumentList @('install', '--id', 'GitHub.cli', '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements') -Verb RunAs -Wait -PassThru
    $script:ghCommand = Find-GitHubCli
    if ($process.ExitCode -ne 0 -or $null -eq $script:ghCommand) {
        [System.Windows.MessageBox]::Show('GitHub CLI could not be installed. Contact Tom Comrie for assistance.', 'Git Remote Switcher')
        return $false
    }
    return $true
}
```
to:
```powershell
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        Show-Message -Id 'WingetNotFound' -Control $controls.AccessStatus | Out-Null
        return $false
    }
    Show-Message -Id 'InstallingGitHubCli' -Control $controls.AccessStatus | Out-Null
    $process = Start-Process -FilePath $winget.Source -ArgumentList @('install', '--id', 'GitHub.cli', '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements') -Verb RunAs -Wait -PassThru
    $script:ghCommand = Find-GitHubCli
    if ($process.ExitCode -ne 0 -or $null -eq $script:ghCommand) {
        Show-Message -Id 'GitHubCliInstallFailed' -Control $controls.AccessStatus | Out-Null
        return $false
    }
    return $true
}
```
(Leave the earlier `[System.Windows.MessageBox]::Show(... 'Install GitHub CLI' ... OKCancel ...)` confirmation dialog in this same function untouched — it's a decision prompt, not a status message.)

- [ ] **Step 3: Retrofit `Update-ForkStatusDisplay`**

Change:
```powershell
function Update-ForkStatusDisplay {
    $script:forkStatus = Test-ForkGitHubAccount
    $controls.ForkStatus.Text = switch ($script:forkStatus) {
        'NotInstalled'   { "Fork was not detected on this machine; skipping the Fork account check." }
        'Found'          { "Fork has a GitHub account configured." }
        'NotFound'       { "Fork does not have a GitHub account configured. Open Fork -> Preferences -> Accounts and add your GitHub account, then click Sign in and verify access again." }
        'CouldNotVerify' { "Could not verify Fork's GitHub account automatically. Check Fork -> Preferences -> Accounts manually." }
    }
    return $script:forkStatus
}
```
to:
```powershell
function Update-ForkStatusDisplay {
    $script:forkStatus = Test-ForkGitHubAccount
    $messageId = switch ($script:forkStatus) {
        'NotInstalled'   { 'ForkNotInstalled' }
        'Found'          { 'ForkFound' }
        'NotFound'       { 'ForkNotFound' }
        'CouldNotVerify' { 'ForkCouldNotVerify' }
    }
    Show-Message -Id $messageId -Control $controls.ForkStatus | Out-Null
    return $script:forkStatus
}
```
(Note: `ForkNotFound`'s text now says "click Re-check Fork" instead of the old "click Sign in and verify access again" — the old wording predates the Re-check Fork button and was already stale; this corrects it as part of the retrofit.)

- [ ] **Step 4: Retrofit `Scan-Repositories`**

Change:
```powershell
    $available = @($repositories | Where-Object TargetAvailable).Count
    $controls.ReviewStatus.Text = "$discovered local Git repository(s) checked; $($repositories.Count) with a GitLab origin found; $available target repository(s) are available on GitHub."
    Set-Step 3
```
to:
```powershell
    $available = @($repositories | Where-Object TargetAvailable).Count
    Show-Message -Id 'ScanComplete' -Control $controls.ReviewStatus -FormatArgs @($discovered, $repositories.Count, $available) | Out-Null
    Set-Step 3
```

- [ ] **Step 5: Retrofit `Update-SelectedRemotes`'s progress line**

Change:
```powershell
        $controls.ProgressStatus.Text = "Updating $($index + 1) of $($selected.Count): $($repository.Name)"
```
to:
```powershell
        Show-Message -Id 'UpdateProgressMsg' -Control $controls.ProgressStatus -FormatArgs @($index + 1, $selected.Count, $repository.Name) | Out-Null
```

- [ ] **Step 6: Retrofit `Update-SelectedRemotes`'s summary line**

Change:
```powershell
    $controls.SummaryStatus.Text = "$successful repository(s) updated successfully; $failed failed; $notUpdated not updated. Refresh Fork to use the new remotes."
    $controls.RollbackButton.Visibility = if ($script:lastUpdatedRepositories.Count -gt 0) { 'Visible' } else { 'Collapsed' }
```
to:
```powershell
    $updateSummaryId = if ($failed -gt 0) { 'UpdateSummaryWithFailures' } else { 'UpdateSummarySuccess' }
    Show-Message -Id $updateSummaryId -Control $controls.SummaryStatus -FormatArgs @($successful, $failed, $notUpdated) | Out-Null
    $controls.RollbackButton.Visibility = if ($script:lastUpdatedRepositories.Count -gt 0) { 'Visible' } else { 'Collapsed' }
```

- [ ] **Step 7: Retrofit `Restore-OriginalRemotes`**

Change:
```powershell
    $controls.SummaryStatus.Text = "$restored of $($script:lastUpdatedRepositories.Count) original remote(s) restored. Refresh Fork to see the restored origins."
    $controls.RollbackButton.Visibility = 'Collapsed'
```
to:
```powershell
    $restoreSummaryId = if ($restored -lt $script:lastUpdatedRepositories.Count) { 'RestoreSummaryWithFailures' } else { 'RestoreSummarySuccess' }
    Show-Message -Id $restoreSummaryId -Control $controls.SummaryStatus -FormatArgs @($restored, $script:lastUpdatedRepositories.Count) | Out-Null
    $controls.RollbackButton.Visibility = 'Collapsed'
```

- [ ] **Step 8: Retrofit the `LoginButton` click handler**

Change:
```powershell
$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    $controls.AccessStatus.Text = 'Complete the GitHub sign-in in your browser...'
    Start-Process -FilePath $script:ghCommand -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'read:org') -Wait | Out-Null
```
to:
```powershell
$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    Show-Message -Id 'SigningIn' -Control $controls.AccessStatus | Out-Null
    Start-Process -FilePath $script:ghCommand -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'read:org') -Wait | Out-Null
```

- [ ] **Step 9: Regression check**

Run:
```bash
powershell -NoProfile -File tests\Show-Message.tests.ps1
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
timeout 15 powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host 'DOT-SOURCE-OK'"
echo "EXIT: $?"
```
Expected: all existing assertions still pass (this task doesn't add new automated tests — it's wiring, verified by the regression suite plus Task 4's manual pass), `DOT-SOURCE-OK`, exit 0.

- [ ] **Step 10: Commit**

```bash
git add GitRemoteSwitcher.ps1
git commit -m "Retrofit existing status messages onto Show-Message"
```

---

### Task 3: Expand step-by-step explanatory text

**Files:**
- Modify: `GitRemoteSwitcher.ps1` (the 5 step-description `TextBlock`s inside the `$xaml` string)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — copy-only change, no new controls or logic.

- [ ] **Step 1: Expand Step 1's description**

Change:
```xml
        <TextBlock Text="Sign in with the GitHub account registered to your @kiroraceco.com email address. You must first accept your Kiro-Race-Co invitation. This check confirms the correct account and organisation access; it does not change any repositories." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
```
to:
```xml
        <TextBlock Text="Sign in with the GitHub account registered to your @kiroraceco.com email address. You must first accept your Kiro-Race-Co invitation before signing in here. This check only confirms the correct account and organisation access -- it does not change any repositories, and nothing is migrated until you reach step 4. The tool also checks whether Fork has a GitHub account configured, since Fork needs its own sign-in separate from this one; if it does not, you will not be able to continue until you add one in Fork and click Re-check Fork." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
```

- [ ] **Step 2: Expand Step 2's description**

Change:
```xml
        <TextBlock Text="Add every top-level folder where you keep local Git repositories, for example C:\Projects or C:\Users\your-name\source. You can add more than one folder. The next step searches every subfolder recursively; do not select an individual .git folder. No repository setting is changed during this scan." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
```
to:
```xml
        <TextBlock Text="Add every top-level folder where you keep local Git repositories, for example C:\Projects or C:\Users\your-name\source. You can add more than one folder. The next step searches every subfolder recursively, including nested repositories and Git worktrees; do not select an individual .git folder itself. Only repositories whose current origin points to GitLab are shown in the next step -- everything else is silently skipped. No repository setting is changed during this scan, so it is safe to point this at your entire workspace." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
```

- [ ] **Step 3: Expand Step 3's description**

Change:
```xml
        <TextBlock Text="Review every repository whose current origin points to GitLab. The new origin is always Kiro-Race-Co on GitHub. This scan changes nothing. A warning means the GitHub repository does not exist, this account cannot read it, or this account cannot push to it; leave it unchecked and contact Tom Comrie. Confirm that every expected repository is present before continuing." TextWrapping="Wrap" Margin="0,8,0,12" Foreground="#52606D"/>
```
to:
```xml
        <TextBlock Text="Review every repository whose current origin points to GitLab. The new origin is always the matching repository name under Kiro-Race-Co on GitHub. This scan changes nothing -- only the next step (Update selected remotes) actually modifies anything. A warning in the Target check column means the GitHub repository does not exist yet, this account cannot read it, this account cannot push to it, or another local repository already claims the same target name; leave warned rows unchecked and contact Tom Comrie before retrying. Repositories using Git LFS are flagged separately -- confirm the LFS objects were migrated to GitHub before relying on that repository there. Confirm that every repository you expect to see is present in this list before continuing." TextWrapping="Wrap" Margin="0,8,0,12" Foreground="#52606D"/>
```

- [ ] **Step 4: Expand Step 4's description**

Change:
```xml
        <TextBlock Text="The tool is changing only each selected repository's local origin URL. It does not edit files, commits, branches, tags, stashes, GitLab, or GitHub. Keep this window open until the summary appears." Margin="0,10,0,8" TextAlignment="Center" TextWrapping="Wrap" Foreground="#52606D"/>
```
to:
```xml
        <TextBlock Text="The tool is changing only each selected repository's local origin URL, one at a time. It does not edit files, commits, branches, tags, stashes, or anything on GitLab or GitHub itself -- this only affects how your local copy connects to its remote. A backup of every original origin is saved automatically before any change is made, so this step can be undone from the summary screen if needed. Keep this window open until the summary appears; closing it early may leave some repositories updated and others not." Margin="0,10,0,8" TextAlignment="Center" TextWrapping="Wrap" Foreground="#52606D"/>
```

- [ ] **Step 5: Expand Step 5's description**

Change:
```xml
        <TextBlock Text="Successful repositories are ready to use in Fork after it is refreshed. Failed or not-updated repositories have been left unchanged and can be safely retried after the issue is resolved." TextWrapping="Wrap" Margin="0,8,0,8" Foreground="#52606D"/>
```
to:
```xml
        <TextBlock Text="Successful repositories are ready to use in Fork after it is refreshed -- Fork reads the same Git configuration this tool just changed, so no separate Fork-side migration step is needed for those repositories. Failed or not-updated repositories have been left completely unchanged and can be safely retried by running this tool again after the underlying issue (shown in the Details column) is resolved. If something went wrong, Restore original remotes reverts every repository this run changed back to its original GitLab origin using the backup saved at the start of this step; support logs for this run are saved at the path shown below." TextWrapping="Wrap" Margin="0,8,0,8" Foreground="#52606D"/>
```

- [ ] **Step 6: Regression check**

Run:
```bash
powershell -NoProfile -File tests\Show-Message.tests.ps1
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
timeout 15 powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host 'DOT-SOURCE-OK'"
echo "EXIT: $?"
```
Expected: all pass, confirming the XAML is still well-formed (malformed XAML fails at `[Windows.Markup.XamlReader]::Load` during dot-source, which the `DOT-SOURCE-OK` check would catch).

- [ ] **Step 7: Commit**

```bash
git add GitRemoteSwitcher.ps1
git commit -m "Expand step-by-step explanatory text in the wizard"
```

---

### Task 4: Manual verification

**Files:** none (verification only).

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: confirmation that the retrofit and new copy work correctly in the actual running wizard.

- [ ] **Step 1: Launch the real wizard**

Run:
```powershell
Start-Process -FilePath "C:\Users\tom.comrie\git-remote-switcher\GitRemoteSwitcher.ps1"
```

- [ ] **Step 2: Confirm severity coloring end-to-end**

Ask the user to confirm, while clicking through the wizard:
- Step 1's description text is now longer and explains the Fork check.
- After clicking "Sign in and verify access," `AccessStatus` shows in gray (Info, e.g. "Signed in as...") on success, or red (Error) text for a failure scenario if one can be triggered.
- `ForkStatus` shows gray (Info) if Fork has a GitHub account, or amber (Warning) if not, and the exact wording says "click Re-check Fork" (not the old "click Sign in and verify access again").
- Step 2 through Step 5's description text reads as expanded, accurate, and doesn't overflow its panel oddly.
- Step 3's `ReviewStatus` line and Step 4's progress line and Step 5's summary line all still populate correctly (gray unless there's a failure, in which case Step 5's summary should be amber).

- [ ] **Step 3: Final commit**

If Steps 1-2 raised no issues, no further changes are needed. If they did, fix, re-run Task 1's and prior tests' regression suite, and commit the fix:
```bash
git add -A
git status
git commit -m "Fix issues found during manual verification"
```
(Only run this if there were actually changes to commit — check `git status` first.)
