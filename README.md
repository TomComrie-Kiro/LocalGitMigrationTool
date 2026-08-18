# Local Git Migration Tool

A small Windows wizard for changing GitLab `origin` remotes in existing local repositories to the fixed `Kiro-Race-Co` GitHub organisation. Fork reads the same Git configuration, so no Fork-specific migration is needed beyond making sure Fork itself already has a GitHub account configured — the wizard checks this on the first screen and will not let you continue past it until it is.

## Use

1. Run `LocalGitMigrationTool.exe` and approve the Windows UAC prompt. The executable requests administrator permission at startup so it can install GitHub CLI when required.
2. Click **Sign in and verify access**. If GitHub CLI is missing, approve the elevated Winget installation. Then complete browser sign-in with the company GitHub account. Confirm the account name shown by the wizard is the account that accepted the `Kiro-Race-Co` invitation. The wizard also checks whether Fork itself has a GitHub account configured; if it does not, open Fork → Preferences → Accounts, add your GitHub account, then click **Re-check Fork** before continuing.
3. Add every folder where the developer stores repositories.
4. Review the current and new origins. The tool verifies that each target GitHub repository is accessible and warns when it is not.
5. Update the selected remotes and review the success/failure summary.

The tool only runs `git remote set-url origin ...` on selected repositories. It never changes working files, commits, branches, tags, stashes, or GitLab/GitHub server data.

The recursive scan lists every repository whose `origin` points to a GitLab host, whether it currently uses HTTPS, SSH, or a Git worktree. It maps each selected repository to `https://github.com/Kiro-Race-Co/<repository-name>.git`.

Each run saves the selected repositories' original remote URLs under `%LOCALAPPDATA%\KiroRaceCo\LocalGitMigrationTool\backups` and provides a **Restore original remotes** button in the final summary. Full diagnostic logs are saved to `\\uk-files-01\dropbox\08_IT\_Software\LocalGitMigrationTool\Log` as `<Windows-username>_<timestamp>_<successful-repository-count>-repos.log`. At startup, if the tool cannot reach this shared folder, it offers to browse for the Silverstone drive's `08_IT` folder, or to fall back to a local log folder at `%LOCALAPPDATA%\KiroRaceCo\LocalGitMigrationTool\Log` (useful when running outside the corporate network, e.g. a build distributed via a GitHub release).
