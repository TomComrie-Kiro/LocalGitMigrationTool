# Fork GitHub Account Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a check to GitRemoteSwitcher's Step 1 that tells the user whether Fork has a GitHub account configured, so they aren't surprised by a Fork-side credential prompt after migrating a repo's origin to GitHub.

**Architecture:** A new pure function, `Test-ForkGitHubAccount`, inspects `%LOCALAPPDATA%\Fork\accounts.json` (existence + a schema-tolerant recursive scan for any "GitHub" reference) and returns one of four states: `NotInstalled`, `NotFound`, `Found`, `CouldNotVerify`. A thin display function, `Update-ForkStatusDisplay`, calls it and updates a new `ForkStatus` text block in the existing WPF Step 1 panel, and gates the `Next` button alongside the existing GitHub CLI sign-in check. A `-NoGui` script parameter guards the final `$window.ShowDialog()` call so the whole script can be dot-sourced for automated testing without launching the GUI.

**Tech Stack:** PowerShell 5.1, WPF (PresentationFramework) via inline XAML — matches the existing single-file script, no new dependencies.

## Global Constraints

- Do not parse or expose the actual credential/token values inside `accounts.json` — only detect presence of a GitHub-type reference (per spec, "Detection logic" section).
- Detection must tolerate an unrecognized/corrupt file shape without crashing or blocking the user (`CouldNotVerify`, non-blocking) — per spec, "Constraints" section.
- `NotInstalled` (Fork not on this machine) must never block `Next` — per spec, "Detection logic" section.
- `NotFound` (Fork installed, no GitHub account) blocks `Next` — per spec, user decision during brainstorming.
- No new external dependencies (no Pester, no NuGet packages) — matches the existing project's zero-dependency, single-file style.

---

### Task 1: Initialize git repo with a baseline commit

**Files:**
- Create: `.gitignore`
- (repo-wide) `git init`

**Interfaces:**
- Consumes: nothing.
- Produces: a git repository at `C:\Users\tom.comrie\git-remote-switcher` with an initial commit of the existing files, so later tasks can commit incrementally.

- [ ] **Step 1: Initialize the repository**

Run:
```bash
cd "C:\Users\tom.comrie\git-remote-switcher"
git init
```

- [ ] **Step 2: Add a .gitignore**

Create `.gitignore`:
```
e2e-test/
*.log
```

(`e2e-test/` excludes the disposable ~22GB test clone folder created during earlier manual testing; it should never be committed.)

- [ ] **Step 3: Baseline commit of existing files**

Run:
```bash
git add GitRemoteSwitcher.ps1 GitRemoteSwitcher.exe README.md .gitignore docs
git status
```

Confirm the status output shows only `GitRemoteSwitcher.ps1`, `GitRemoteSwitcher.exe`, `README.md`, `.gitignore`, and the `docs/` spec/plan files staged — nothing from `e2e-test/`.

```bash
git commit -m "Baseline commit of existing GitRemoteSwitcher project"
```

---

### Task 2: Add `-NoGui` testing seam

**Files:**
- Modify: `GitRemoteSwitcher.ps1:1-6` (param block)
- Modify: `GitRemoteSwitcher.ps1:343` (final `ShowDialog` line)

**Interfaces:**
- Consumes: nothing new.
- Produces: `. .\GitRemoteSwitcher.ps1 -NoGui` dot-sources every function and script-scoped variable in the file without displaying the window or blocking — this is what Task 3's test script relies on.

- [ ] **Step 1: Add the `-NoGui` switch parameter**

In `GitRemoteSwitcher.ps1`, change:
```powershell
#requires -Version 5.1
<#!
.SYNOPSIS
A guided utility for switching local GitLab remotes to Kiro-Race-Co on GitHub.
#>

Add-Type -AssemblyName PresentationFramework
```

to:
```powershell
#requires -Version 5.1
<#!
.SYNOPSIS
A guided utility for switching local GitLab remotes to Kiro-Race-Co on GitHub.
#>
param(
    [switch]$NoGui
)

Add-Type -AssemblyName PresentationFramework
```

- [ ] **Step 2: Guard the final `ShowDialog` call**

Change the last line of the file:
```powershell
Set-Step 1
$window.ShowDialog() | Out-Null
```

to:
```powershell
Set-Step 1
if (-not $NoGui) { $window.ShowDialog() | Out-Null }
```

- [ ] **Step 3: Verify dot-sourcing returns control instead of hanging**

Run (from the project root, with a timeout so a regression can't hang the terminal):
```bash
timeout 15 powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host 'DOT-SOURCE-OK'"
echo "EXIT: $?"
```
Expected: prints `DOT-SOURCE-OK` and exits 0 well before the 15s timeout. If it hangs until the timeout kills it, the `ShowDialog` guard is wrong — check Step 2.

- [ ] **Step 4: Commit**

```bash
git add GitRemoteSwitcher.ps1
git commit -m "Add -NoGui switch so the script can be dot-sourced for testing"
```

---

### Task 3: Implement and test `Test-ForkGitHubAccount`

**Files:**
- Modify: `GitRemoteSwitcher.ps1` (insert new functions after `Ensure-GitHubCli`, i.e. after the existing line `}` that closes that function, before `function Test-GitLabOrigin`)
- Create: `tests/Test-ForkGitHubAccount.tests.ps1`

**Interfaces:**
- Consumes: Task 2's `-NoGui` seam.
- Produces:
  - `Test-ForkGitHubAccount` — no parameters, returns `[string]` one of `'NotInstalled'`, `'NotFound'`, `'Found'`, `'CouldNotVerify'`.
  - `Find-GitHubReference($node)` — returns `[bool]`, `$true` if `$node` (or anything nested inside it) is a string equal to `'GitHub'` or matching `'github'` (case-insensitive, e.g. `github.com`).
  - Both are consumed by Task 4's `Update-ForkStatusDisplay`.

- [ ] **Step 1: Write the failing test**

Create `tests/Test-ForkGitHubAccount.tests.ps1`:
```powershell
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
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
```
Expected: fails with something like `The term 'Test-ForkGitHubAccount' is not recognized...` (the function doesn't exist yet).

- [ ] **Step 3: Implement `Test-ForkGitHubAccount` and `Find-GitHubReference`**

In `GitRemoteSwitcher.ps1`, insert immediately after the closing `}` of the existing `Ensure-GitHubCli` function and before `function Test-GitLabOrigin`:

```powershell
function Find-GitHubReference($node) {
    if ($null -eq $node) { return $false }
    if ($node -is [string]) { return $node -match 'github' }
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $node.PSObject.Properties) {
            if (Find-GitHubReference $property.Value) { return $true }
        }
        return $false
    }
    if ($node -is [System.Collections.IEnumerable]) {
        foreach ($item in $node) {
            if (Find-GitHubReference $item) { return $true }
        }
        return $false
    }
    return $false
}

function Test-ForkGitHubAccount {
    $forkDirectory = Join-Path $env:LOCALAPPDATA 'Fork'
    if (-not (Test-Path -LiteralPath $forkDirectory)) { return 'NotInstalled' }

    $accountsPath = Join-Path $forkDirectory 'accounts.json'
    if (-not (Test-Path -LiteralPath $accountsPath)) { return 'NotFound' }

    $raw = Get-Content -LiteralPath $accountsPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'NotFound' }

    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return 'CouldNotVerify'
    }

    if (Find-GitHubReference $data) { return 'Found' }
    return 'NotFound'
}
```

- [ ] **Step 4: Run the test again to verify it passes**

Run:
```bash
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
```
Expected: prints six `PASS:` lines followed by `All Test-ForkGitHubAccount assertions passed.`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add GitRemoteSwitcher.ps1 tests/Test-ForkGitHubAccount.tests.ps1
git commit -m "Add Test-ForkGitHubAccount detection function with fixture-based tests"
```

---

### Task 4: Wire the check into Step 1's UI

**Files:**
- Modify: `GitRemoteSwitcher.ps1` (XAML Step1Panel block, controls collection list, new `Update-ForkStatusDisplay` function, `LoginButton` click handler, startup sequence)

**Interfaces:**
- Consumes: `Test-ForkGitHubAccount` from Task 3.
- Produces: `Update-ForkStatusDisplay` — no parameters, returns `[string]` (the same state Task 3's function returns), and as a side effect sets `$controls.ForkStatus.Text` and `$script:forkStatus`.

- [ ] **Step 1: Add the `ForkStatus` text block to the XAML**

In the `$xaml` here-string, change:
```xml
            <Button x:Name="LoginButton" Content="Sign in and verify access" HorizontalAlignment="Left" Background="#24292F" Foreground="White" BorderBrush="#24292F"/>
            <TextBlock x:Name="AccessStatus" Margin="0,14,0,0" TextWrapping="Wrap" Foreground="#52606D" Text="GitHub access has not been checked."/>
          </StackPanel>
        </Border>
```
to:
```xml
            <Button x:Name="LoginButton" Content="Sign in and verify access" HorizontalAlignment="Left" Background="#24292F" Foreground="White" BorderBrush="#24292F"/>
            <TextBlock x:Name="AccessStatus" Margin="0,14,0,0" TextWrapping="Wrap" Foreground="#52606D" Text="GitHub access has not been checked."/>
            <TextBlock x:Name="ForkStatus" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#52606D" Text="Checking Fork's GitHub account..."/>
          </StackPanel>
        </Border>
```

- [ ] **Step 2: Register the new control**

Change:
```powershell
'Step1Panel','Step2Panel','Step3Panel','Step4Panel','Step5Panel','Step1Marker','Step2Marker','Step3Marker','Step4Marker','Step5Marker','LoginButton','AccessStatus','FoldersList','AddFolderButton','RemoveFolderButton','ReviewGrid','ReviewStatus','UpdateProgress','ProgressStatus','SummaryGrid','SummaryStatus','RollbackButton','LogPathText','BackButton','NextButton','FooterText' | ForEach-Object { $controls[$_] = $window.FindName($_) }
```
to:
```powershell
'Step1Panel','Step2Panel','Step3Panel','Step4Panel','Step5Panel','Step1Marker','Step2Marker','Step3Marker','Step4Marker','Step5Marker','LoginButton','AccessStatus','ForkStatus','FoldersList','AddFolderButton','RemoveFolderButton','ReviewGrid','ReviewStatus','UpdateProgress','ProgressStatus','SummaryGrid','SummaryStatus','RollbackButton','LogPathText','BackButton','NextButton','FooterText' | ForEach-Object { $controls[$_] = $window.FindName($_) }
```

- [ ] **Step 3: Initialize `$script:forkStatus`**

Change:
```powershell
$script:accessVerified = $false
$script:currentStep = 1
```
to:
```powershell
$script:accessVerified = $false
$script:forkStatus = 'NotInstalled'
$script:currentStep = 1
```

- [ ] **Step 4: Add `Update-ForkStatusDisplay`**

Insert directly after the `Test-ForkGitHubAccount` function (added in Task 3):
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

- [ ] **Step 5: Update the `LoginButton` click handler**

Change:
```powershell
$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    $controls.AccessStatus.Text = 'Complete the GitHub sign-in in your browser...'
    Start-Process -FilePath $script:ghCommand -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'read:org') -Wait | Out-Null
    $script:accessVerified = Verify-Access
    $controls.NextButton.IsEnabled = $script:accessVerified
})
```
to:
```powershell
$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    $controls.AccessStatus.Text = 'Complete the GitHub sign-in in your browser...'
    Start-Process -FilePath $script:ghCommand -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'read:org') -Wait | Out-Null
    $script:accessVerified = Verify-Access
    Update-ForkStatusDisplay | Out-Null
    $controls.NextButton.IsEnabled = $script:accessVerified -and ($script:forkStatus -ne 'NotFound')
})
```

- [ ] **Step 6: Run the check once at startup**

Change the final lines:
```powershell
Set-Step 1
if (-not $NoGui) { $window.ShowDialog() | Out-Null }
```
to:
```powershell
Update-ForkStatusDisplay | Out-Null
Set-Step 1
if (-not $NoGui) { $window.ShowDialog() | Out-Null }
```

- [ ] **Step 7: Re-run the automated test suite (regression check)**

Run:
```bash
powershell -NoProfile -File tests\Test-ForkGitHubAccount.tests.ps1
```
Expected: still all `PASS`, since Task 4's changes don't touch `Test-ForkGitHubAccount` or `Find-GitHubReference` themselves — this just confirms the file still dot-sources cleanly (no syntax errors from the XAML/control changes).

- [ ] **Step 8: Verify dot-sourcing still returns control (no new hang)**

Run:
```bash
timeout 15 powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host 'DOT-SOURCE-OK'"
echo "EXIT: $?"
```
Expected: `DOT-SOURCE-OK`, exit 0.

- [ ] **Step 9: Commit**

```bash
git add GitRemoteSwitcher.ps1
git commit -m "Show Fork GitHub account status in Step 1 and gate Next on it"
```

---

### Task 5: Manual verification

**Files:** none (verification only).

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: confirmation that the feature works against this machine's real Fork installation and in the actual running wizard.

- [ ] **Step 1: Check the real machine's state (result only, no file content)**

Run:
```bash
powershell -NoProfile -Command ". .\GitRemoteSwitcher.ps1 -NoGui; Write-Host \"Detected state: $(Test-ForkGitHubAccount)\""
```
This machine has Fork installed with a GitHub account already configured (confirmed earlier via a presence-only `grep` count on `accounts.json`, without reading its content), so the expected output is `Detected state: Found`. If it prints anything else, stop and investigate the recursive-search logic in `Find-GitHubReference` before proceeding — do not attempt to read `accounts.json` content directly to debug it.

- [ ] **Step 2: Launch the real wizard and confirm the UI**

Run:
```powershell
Start-Process -FilePath "C:\Users\tom.comrie\git-remote-switcher\GitRemoteSwitcher.ps1"
```
(Note: this runs the `.ps1` directly, not the compiled `.exe` — the `.exe` is a separately built artifact and is out of scope for this plan; rebuilding it is a follow-up if the user wants the compiled binary updated too.)

Ask the user to confirm, on Step 1 of the running wizard:
- The new status line appears below "GitHub access has not been checked." and reads "Fork has a GitHub account configured."
- After a successful "Sign in and verify access," the `Next` button becomes enabled as before (unaffected by this change, since Fork's status here is `Found`).

- [ ] **Step 3: Final commit**

If Steps 1-2 raised no issues, no further changes are needed. If they did, fix, re-run Task 3's test suite, and commit the fix:
```bash
git add -A
git status
git commit -m "Fix Fork account check issues found during manual verification"
```
(Only run this if there were actually changes to commit — check `git status` first.)
