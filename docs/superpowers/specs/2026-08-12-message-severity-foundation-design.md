# Message/error-handling foundation — design

## Problem

The user requested a larger batch of migration-smoothness features: `gh auth
setup-git` wiring, post-update `git ls-remote` verification, GitLab submodule
and `.gitlab-ci.yml` detection, review-grid ergonomics (bulk select, CSV
export, persisted selections), lazy UAC elevation, much more per-step
explanatory text, and proper error handling with user-facing messages for
warnings/errors/fatal conditions. That's too large for one spec and touches
too many independent subsystems to design or build as a single change.

This spec covers only the foundation: a consistent way to show the user
informational, warning, error, and fatal messages, and expanded explanatory
text for each wizard step. Every other requested feature (credential wiring,
coverage-gap detection, review ergonomics, lazy elevation) is a separate,
later spec that will build on this foundation rather than inventing its own
ad hoc messaging each time.

Today, user-facing status text (`AccessStatus`, `ForkStatus`, `ReviewStatus`,
`ProgressStatus`, `SummaryStatus`) is set directly as plain gray
(`#52606D`) text at each call site, with no severity distinction, and two
`MessageBox` popups exist only for GitHub CLI install failures inside
`Ensure-GitHubCli`. There is no consistent pattern a future feature could
reuse.

## Scope

**In scope:**
- A central message catalog (`$script:messages`) and a `Show-Message`
  function that formats, displays, color-codes by severity, and logs every
  message.
- Migrating the existing ~12 status-text call sites and the 2 failure
  `MessageBox` calls to this new mechanism.
- Expanding the 5 step-description paragraphs in the XAML with clearer
  explanations.

**Out of scope (explicitly, for later specs):**
- Color-coding the Step 3/5 `DataGrid` warning cells (`TargetStatus`,
  `Details` columns) — different mechanism (WPF `DataTrigger`/style, not
  `TextBlock`), deferred as its own follow-up.
- The two existing OK/Cancel confirmation dialogs (GitHub CLI install,
  restore remotes) — those are decisions, not status messages, and stay as
  direct `MessageBox.Show` calls.
- Any new error/warning scenarios introduced by not-yet-built features
  (credential wiring, submodule detection, etc.). Those features will add
  their own catalog entries when they're built, using the mechanism this
  spec establishes.

## Severity levels and display

Four levels, matching the existing single MessageBox precedent for the most
severe case:

| Severity | Display | Color | Also |
|---|---|---|---|
| Info | Inline `TextBlock` text | `#52606D` (existing neutral gray, unchanged) | — |
| Warning | Inline `TextBlock` text | `#9A6700` (amber) | — |
| Error | Inline `TextBlock` text | `#B42318` (red) | — |
| Fatal | Inline `TextBlock` text (same red) **+** blocking `MessageBox` | `#B42318` | `MessageBox` with the OS error icon, for explicit acknowledgment |

## Message catalog and `Show-Message`

A hashtable near the top of the script, one entry per message:

```powershell
$script:messages = @{
    'GitNotInstalled' = @{ Severity = 'Fatal'; Text = 'Git is not installed or is not available in PATH. Install Git for Windows, then restart this tool.' }
    'SignedIn'         = @{ Severity = 'Info';  Text = 'Signed in as {0}. Your {1} organisation access is confirmed.' }
    # ... one entry per migrated and new message
}
```

`Show-Message` looks up the entry by ID, formats it with `-f $FormatArgs` if
placeholders are present, sets the target control's `.Text` and
`.Foreground` per the severity table above, and always calls the existing
`Write-RunLog` function so support logs capture everything shown to the
user — including Info messages, for a complete audit trail of a run.

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

## Retrofit scope

Existing call sites migrated to `Show-Message` + catalog entries:

- `AccessStatus`: `Verify-Access`'s 4 messages (git missing → Fatal; sign-in
  not completed → Error; org membership unconfirmed → Error; not an active
  member → Error; success → Info) and the `LoginButton` handler's
  "Complete the GitHub sign-in in your browser..." (Info).
- `ForkStatus`: `Update-ForkStatusDisplay`'s 4 state messages
  (`NotInstalled`/`Found`/`CouldNotVerify` → Info; `NotFound` → Warning,
  since it blocks progress but isn't fatal to the tool itself).
- `ReviewStatus`: `Scan-Repositories`'s summary (Info).
- `ProgressStatus`: the "Updating X of Y" loop message (Info).
- `SummaryStatus`: `Update-SelectedRemotes`'s summary is Warning if
  `$failed -gt 0` (at least one repository's origin update failed),
  otherwise Info (repositories the user simply didn't select, or that were
  already flagged unavailable during the scan, aren't new failures).
  `Restore-OriginalRemotes`'s summary is Warning if `$restored -lt
  $script:lastUpdatedRepositories.Count` (at least one rollback failed),
  otherwise Info.
- `Ensure-GitHubCli`'s two failure `MessageBox` calls ("winget not found,"
  "GitHub CLI could not be installed") → Fatal.

Not migrated: the GitHub CLI install OK/Cancel confirmation and the restore
remotes OK/Cancel confirmation (decisions, not status messages), and the
Step 3/5 `DataGrid` warning cells (out of scope, see above).

## Expanded step explanations

Each of the 5 step-description `TextBlock`s in the XAML (`Step1Panel`
through `Step5Panel`) gets longer, clearer text: why the step matters, what
happens if something in it fails, and what the user should expect next. No
new controls — same `TextBlock`s, longer `Text` values. Exact copy is
written during implementation, reviewed for accuracy against what each step
actually does.

## Testing approach

`Show-Message`'s `Fatal` branch calls `[System.Windows.MessageBox]::Show`,
which blocks — separate from the main window's `ShowDialog()`, so the
existing `-NoGui` guard (added for the Fork check) doesn't cover it. Extend
that same seam: `Show-Message` checks `$NoGui` and skips the `MessageBox`
call when set, while still setting the target control's text/color, so the
formatting and severity-routing logic stays testable via dot-sourcing.

Automated tests (extending the existing `tests/` fixture style, no new
framework):
- Every catalog entry has a valid `Severity` (one of the 4) and non-empty
  `Text`.
- `Show-Message` formats placeholders correctly and sets `.Text` and
  `.Foreground` per severity, against a real `-NoGui`-constructed control
  (not a mock — same technique already proven in the Fork check's tests).
- `Show-Message` writes to the run log (assert the log file gains the
  expected line after a call).

The retrofit of ~12 call sites and the expanded step copy are verified
manually by clicking through the wizard, same as the Fork check's manual
verification task — they're wiring and copy, not logic, so they don't get
individual automated tests.

## Out of scope

- DataGrid cell coloring (deferred follow-up).
- Any new error/warning scenarios from not-yet-built features — those add
  their own catalog entries when built.
- Localization/i18n of the message catalog.
