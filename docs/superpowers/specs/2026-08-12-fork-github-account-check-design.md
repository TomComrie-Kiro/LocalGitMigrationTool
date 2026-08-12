# Fork GitHub account check — design

## Problem

GitRemoteSwitcher moves a repository's `origin` from GitLab to GitHub. It does not
touch Fork's own configuration. After a migration, Fork needs a GitHub account
configured (Preferences → Accounts) for a smooth experience with the new origin;
if it doesn't have one, the user may hit an unexpected credential prompt the first
time they use the migrated repository in Fork. The wizard should tell the user
this up front, in Step 1, alongside the existing GitHub CLI sign-in check.

## Constraints

Fork stores its account configuration in `%LOCALAPPDATA%\Fork\accounts.json`. This
file is credential-adjacent and has an undocumented, version-dependent schema. The
script must not attempt to decrypt or validate the stored credential's live
validity — only detect whether a GitHub-type account entry is present. Any parsing
must tolerate an unexpected file shape without crashing or falsely blocking the
user (a future Fork update could change the file's structure).

## Detection logic

New function `Test-ForkGitHubAccount`, returning one of four states:

- **NotInstalled** — `%LOCALAPPDATA%\Fork` does not exist. Fork isn't on this
  machine; the check does not apply. Never blocks.
- **NotFound** — the Fork folder exists, but `accounts.json` is missing, empty, or
  parses successfully with no GitHub reference found. Fork is installed but has no
  GitHub account configured. Blocks.
- **Found** — `accounts.json` parses successfully and a GitHub-type account entry
  is detected. Passes.
- **CouldNotVerify** — `accounts.json` exists but fails to parse, or its shape is
  unrecognized. The script cannot confirm either way. Does not block — a warning
  is shown instead, so an internal Fork format change degrades to "please check
  manually" rather than silently blocking every user.

Detection of a GitHub-type entry: parse `accounts.json` with `ConvertFrom-Json`,
then recursively walk the resulting object/array tree looking for any string
value that case-insensitively equals `GitHub` or contains `github.com`. This
avoids hard-coding exact property names from an undocumented schema.

## UI integration (Step 1 panel)

- New `TextBlock x:Name="ForkStatus"` added below the existing `AccessStatus` text
  block in `Step1Panel`.
- The check runs once at window startup (it doesn't depend on GitHub CLI sign-in)
  and again each time the user clicks "Sign in and verify access," so the user can
  fix Fork and retry without restarting the wizard.
- Status text:
  - NotInstalled → "Fork was not detected on this machine; skipping the Fork
    account check." (neutral, non-blocking)
  - Found → "Fork has a GitHub account configured." (success style)
  - NotFound → "Fork does not have a GitHub account configured. Open Fork →
    Preferences → Accounts and add your GitHub account, then click Sign in and
    verify access again." (warning style, blocks)
  - CouldNotVerify → "Could not verify Fork's GitHub account automatically. Check
    Fork → Preferences → Accounts manually." (warning style, does not block)
- `NextButton.IsEnabled` on Step 1 becomes:
  `$script:accessVerified -and ($script:forkStatus -ne 'NotFound')`

## Testing approach

`Test-ForkGitHubAccount` is tested in isolation (dot-sourced independent of the
GUI/`ShowDialog` call):

- Against the real `%LOCALAPPDATA%\Fork\accounts.json` on the test machine —
  asserting only the resulting state enum, never printing file content.
- Against synthetic fixtures for the other three branches: a nonexistent Fork
  folder (NotInstalled), a valid JSON fixture with no GitHub reference (NotFound),
  and a corrupt/malformed JSON fixture (CouldNotVerify).

Full UI behavior (status text rendering, Next button gating) requires a human to
click through Step 1 in the running wizard, since native WPF windows can't be
inspected by the assistant directly.

## Out of scope

- Validating that a configured GitHub credential is still valid/unexpired.
- Any change to Fork's own configuration or behavior.
