#requires -Version 5.1
<#!
.SYNOPSIS
A guided utility for switching local GitLab remotes to Kiro-Race-Co on GitHub.
#>
param(
    [switch]$NoGui
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$organisation = 'Kiro-Race-Co'
$gitHubPrefix = "https://github.com/$organisation/"
$script:accessVerified = $false
$script:forkStatus = 'NotInstalled'
$script:currentStep = 1
$script:githubUser = $null
$sharedLogRelativePath = '_Software\LocalGitMigrationTool\Log'
$sharedLogDirectories = @('\\uk-files-01\dropbox\08_IT\_Software\LocalGitMigrationTool\Log')
$sharedLogDriveLetters = @('S', 'R', 'Z')
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
$script:ghCommand = $null
$script:lastUpdatedRepositories = New-Object System.Collections.Generic.List[object]
$script:backupPath = $null
$script:logDirectory = $null
$script:logStartedAt = Get-Date
$script:logPath = $null
if ($NoGui) { $script:logPath = Join-Path $env:TEMP "LocalGitMigrationTool-test-$PID.log" }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
         Title="Local Git Migration Tool" Height="850" Width="1060" MinHeight="720" MinWidth="820"
        WindowStartupLocation="CenterScreen" Background="#F7F8FA" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button"><Setter Property="Padding" Value="15,7"/><Setter Property="Margin" Value="0,0,8,0"/></Style>
    <Style TargetType="TextBox"><Setter Property="Padding" Value="8,5"/><Setter Property="BorderBrush" Value="#B8C1CC"/></Style>
  </Window.Resources>
  <Grid Margin="30">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="Local Git Migration Tool" FontSize="27" FontWeight="SemiBold" Foreground="#17202A"/>
      <TextBlock Text="Move existing local repositories from GitLab to GitHub without changing their contents." Margin="0,5,0,0" Foreground="#52606D" FontSize="14"/>
    </StackPanel>
    <Grid Grid.Row="1" Margin="0,0,0,16">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border x:Name="Step1Marker" Grid.Column="0" Background="#1F6FEB" CornerRadius="4" Padding="8"><TextBlock Text="1. Verify access" HorizontalAlignment="Center" Foreground="White"/></Border>
      <Border x:Name="Step2Marker" Grid.Column="1" Background="#DDE3EA" CornerRadius="4" Padding="8" Margin="6,0,0,0"><TextBlock Text="2. Folders" HorizontalAlignment="Center" Foreground="#52606D"/></Border>
      <Border x:Name="Step3Marker" Grid.Column="2" Background="#DDE3EA" CornerRadius="4" Padding="8" Margin="6,0,0,0"><TextBlock Text="3. Review" HorizontalAlignment="Center" Foreground="#52606D"/></Border>
      <Border x:Name="Step4Marker" Grid.Column="3" Background="#DDE3EA" CornerRadius="4" Padding="8" Margin="6,0,0,0"><TextBlock Text="4. Update" HorizontalAlignment="Center" Foreground="#52606D"/></Border>
      <Border x:Name="Step5Marker" Grid.Column="4" Background="#DDE3EA" CornerRadius="4" Padding="8" Margin="6,0,0,0"><TextBlock Text="5. Summary" HorizontalAlignment="Center" Foreground="#52606D"/></Border>
    </Grid>

    <Grid Grid.Row="2">
      <StackPanel x:Name="Step1Panel">
        <TextBlock Text="Sign in to GitHub" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Sign in with the GitHub account registered to your @kiroraceco.com email address. You must first accept your Kiro-Race-Co invitation before signing in here. This check only confirms the correct account and organisation access -- it does not change any repositories, and nothing is migrated until you reach step 4. The tool also checks whether Fork has a GitHub account configured, since Fork needs its own sign-in separate from this one; if it does not, you will not be able to continue until you add one in Fork and click Re-check Fork." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
        <Border Background="White" BorderBrush="#DEE3E9" BorderThickness="1" CornerRadius="6" Padding="20">
          <StackPanel>
            <TextBlock Text="Target organisation" FontWeight="SemiBold"/>
            <TextBlock Text="Kiro-Race-Co" FontSize="18" Margin="0,4,0,18" Foreground="#17202A"/>
            <Button x:Name="LoginButton" Content="Sign in and verify access" HorizontalAlignment="Left" Background="#24292F" Foreground="White" BorderBrush="#24292F"/>
            <TextBlock x:Name="AccessStatus" Margin="0,14,0,0" TextWrapping="Wrap" Foreground="#52606D" Text="GitHub access has not been checked."/>
            <TextBlock x:Name="ForkStatus" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#52606D" Text="Checking Fork's GitHub account..."/>
            <Button x:Name="RecheckForkButton" Content="Re-check Fork" HorizontalAlignment="Left" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>
      </StackPanel>

      <StackPanel x:Name="Step2Panel" Visibility="Collapsed">
        <TextBlock Text="Add repository folders" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Add every top-level folder where you keep local Git repositories, for example C:\Projects or C:\Users\your-name\source. You can add more than one folder. The next step searches every subfolder recursively, including nested repositories and Git worktrees; do not select an individual .git folder itself. Only repositories whose current origin points to GitLab are shown in the next step -- everything else is silently skipped. No repository setting is changed during this scan, so it is safe to point this at your entire workspace. Scanning can take a few minutes for large workspaces, since each GitLab repository found is checked against GitHub." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
        <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <ListBox x:Name="FoldersList" Height="280" Background="White" BorderBrush="#DEE3E9" BorderThickness="1"/>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,12,0,0"><Button x:Name="AddFolderButton" Content="Add folder" Background="#1F6FEB" Foreground="White" BorderBrush="#1F6FEB"/><Button x:Name="RemoveFolderButton" Content="Remove selected"/></StackPanel>
        </Grid>
      </StackPanel>

      <StackPanel x:Name="Step3Panel" Visibility="Collapsed">
        <TextBlock Text="Review remote changes" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Review every repository whose current origin points to GitLab. The new origin is always the matching repository name under Kiro-Race-Co on GitHub. This scan changes nothing -- only the next step (Update selected remotes) actually modifies anything. A warning in the Target check column means the GitHub repository does not exist yet, this account cannot read it, this account cannot push to it, or another local repository already claims the same target name; leave warned rows unchecked and contact Tom Comrie before retrying. Repositories using Git LFS are noted in the same Target check column -- confirm the LFS objects were migrated to GitHub before relying on that repository there. Confirm that every repository you expect to see is present in this list before continuing." TextWrapping="Wrap" Margin="0,8,0,12" Foreground="#52606D"/>
        <DataGrid x:Name="ReviewGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False" GridLinesVisibility="Horizontal" BorderBrush="#DEE3E9" Background="White" Height="360">
          <DataGrid.Columns>
            <DataGridCheckBoxColumn Header="Update" Binding="{Binding Selected, Mode=TwoWay}" Width="65"/>
            <DataGridTextColumn Header="Repository" Binding="{Binding Name}" Width="150" IsReadOnly="True"/>
            <DataGridTextColumn Header="Location" Binding="{Binding Path}" Width="*" IsReadOnly="True"/>
            <DataGridTextColumn Header="Current origin" Binding="{Binding Current}" Width="220" IsReadOnly="True"/>
            <DataGridTextColumn Header="New origin" Binding="{Binding New}" Width="220" IsReadOnly="True"/>
            <DataGridTextColumn Header="Target check" Binding="{Binding TargetStatus}" Width="190" IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
        <TextBlock x:Name="ReviewStatus" Margin="0,10,0,0" Foreground="#52606D"/>
      </StackPanel>

      <StackPanel x:Name="Step4Panel" Visibility="Collapsed" VerticalAlignment="Center">
        <TextBlock Text="Updating remotes" FontSize="20" FontWeight="SemiBold" Foreground="#17202A" HorizontalAlignment="Center"/>
        <TextBlock Text="The tool is changing only each selected repository's local origin URL, one at a time. It does not edit files, commits, branches, tags, stashes, or anything on GitLab or GitHub itself -- this only affects how your local copy connects to its remote. A backup of every original origin is saved automatically before any change is made, so this step can be undone from the summary screen if needed. Keep this window open until the summary appears; closing it early may leave some repositories updated and others not." Margin="0,10,0,8" TextAlignment="Center" TextWrapping="Wrap" Foreground="#52606D"/>
        <TextBlock x:Name="ProgressStatus" Margin="0,0,0,16" TextAlignment="Center" Foreground="#52606D"/>
        <ProgressBar x:Name="UpdateProgress" Height="20" Minimum="0" Maximum="1" Value="0"/>
      </StackPanel>

      <StackPanel x:Name="Step5Panel" Visibility="Collapsed">
        <TextBlock Text="Migration summary" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Successful repositories are ready to use in Fork after it is refreshed -- Fork reads the same Git configuration this tool just changed, so no separate Fork-side migration step is needed for those repositories. Failed or not-updated repositories have been left completely unchanged and can be safely retried by running this tool again after the underlying issue (shown in the Details column) is resolved. If something went wrong, Restore original remotes reverts every repository this run changed back to its original GitLab origin (a backup of the originals is also saved to disk); support logs for this run are saved at the path shown below." TextWrapping="Wrap" Margin="0,8,0,8" Foreground="#52606D"/>
        <TextBlock x:Name="SummaryStatus" Margin="0,0,0,12" Foreground="#52606D"/>
        <DataGrid x:Name="SummaryGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False" IsReadOnly="True" GridLinesVisibility="Horizontal" BorderBrush="#DEE3E9" Background="White" Height="360">
          <DataGrid.Columns><DataGridTextColumn Header="Repository" Binding="{Binding Name}" Width="180"/><DataGridTextColumn Header="Location" Binding="{Binding Path}" Width="*"/><DataGridTextColumn Header="Result" Binding="{Binding Result}" Width="180"/><DataGridTextColumn Header="Details" Binding="{Binding Details}" Width="260"/></DataGrid.Columns>
        </DataGrid>
        <StackPanel Orientation="Horizontal" Margin="0,12,0,0"><Button x:Name="RollbackButton" Content="Restore original remotes" Visibility="Collapsed" Background="#A23B00" Foreground="White" BorderBrush="#A23B00"/><TextBlock x:Name="LogPathText" VerticalAlignment="Center" Foreground="#52606D" TextWrapping="Wrap"/></StackPanel>
      </StackPanel>
    </Grid>

    <DockPanel Grid.Row="3" Margin="0,18,0,0">
      <TextBlock x:Name="FooterText" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="#52606D" Text="Step 1 of 5"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button x:Name="BackButton" Content="Back" IsEnabled="False"/><Button x:Name="NextButton" Content="Next" Background="#1F6FEB" Foreground="White" BorderBrush="#1F6FEB" IsEnabled="False"/></StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
$controls = @{}
'Step1Panel','Step2Panel','Step3Panel','Step4Panel','Step5Panel','Step1Marker','Step2Marker','Step3Marker','Step4Marker','Step5Marker','LoginButton','AccessStatus','ForkStatus','RecheckForkButton','FoldersList','AddFolderButton','RemoveFolderButton','ReviewGrid','ReviewStatus','UpdateProgress','ProgressStatus','SummaryGrid','SummaryStatus','RollbackButton','LogPathText','BackButton','NextButton','FooterText' | ForEach-Object { $controls[$_] = $window.FindName($_) }

$folders = New-Object System.Collections.ObjectModel.ObservableCollection[string]
$repositories = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$results = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$controls.FoldersList.ItemsSource = $folders
$controls.ReviewGrid.ItemsSource = $repositories
$controls.SummaryGrid.ItemsSource = $results

function Write-RunLog([string]$Message) {
    Add-Content -LiteralPath $script:logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

function Test-SharedLogDirectory([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $false }
    $probePath = Join-Path $Directory ".local-git-migration-tool-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($probePath, '')
        Remove-Item -LiteralPath $probePath -Force
        return $true
    } catch {
        return $false
    }
}

function Find-SharedLogDirectory {
    foreach ($candidate in $sharedLogDirectories) {
        if (Test-SharedLogDirectory $candidate) { return $candidate }
    }
    foreach ($drive in $sharedLogDriveLetters) {
        $candidate = "${drive}:\08_IT\$sharedLogRelativePath"
        if (Test-SharedLogDirectory $candidate) { return $candidate }
    }
    return $null
}

function Set-SharedLogDirectory([string]$Directory) {
    $script:logDirectory = $Directory
    $userName = ($env:USERNAME -replace '[^A-Za-z0-9._-]', '_')
    $timestamp = $script:logStartedAt.ToString('yyyyMMdd-HHmmss')
    $script:logPath = Join-Path $script:logDirectory "${userName}_${timestamp}_0-repos.log"
    Write-RunLog "RUN START User=$env:USERNAME; Machine=$env:COMPUTERNAME; Log=$script:logPath"
}

function Rename-SharedLog([int]$RepositoryCount) {
    $userName = ($env:USERNAME -replace '[^A-Za-z0-9._-]', '_')
    $timestamp = $script:logStartedAt.ToString('yyyyMMdd-HHmmss')
    $newPath = Join-Path $script:logDirectory "${userName}_${timestamp}_${RepositoryCount}-repos.log"
    if ($newPath -eq $script:logPath) { return }
    try {
        Move-Item -LiteralPath $script:logPath -Destination $newPath -Force
        $script:logPath = $newPath
    } catch {
        Write-RunLog "LOG RENAME FAILED: $($_.Exception.Message)"
    }
}

function Initialize-SharedLogging {
    $directory = Find-SharedLogDirectory
    while ($null -eq $directory) {
        [System.Windows.MessageBox]::Show('The shared Local Git Migration Tool log folder is unavailable. Select the 08_IT folder on your Silverstone drive so the tool can save diagnostic logs.', 'Local Git Migration Tool', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the 08_IT folder on your Silverstone drive'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }
        if ((Split-Path -Leaf $dialog.SelectedPath) -ne '08_IT') {
            [System.Windows.MessageBox]::Show('Select the folder named 08_IT, not one of its subfolders.', 'Local Git Migration Tool', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            continue
        }
        $candidate = Join-Path $dialog.SelectedPath $sharedLogRelativePath
        if (Test-SharedLogDirectory $candidate) { $directory = $candidate }
        else {
            [System.Windows.MessageBox]::Show("Could not write to $candidate. Check the Silverstone drive connection and permissions, then try again.", 'Local Git Migration Tool', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
    }
    Set-SharedLogDirectory $directory
    return $true
}

function Set-Step([int]$Step) {
    $script:currentStep = $Step
    1..5 | ForEach-Object {
        $controls["Step$($_)Panel"].Visibility = if ($_ -eq $Step) { 'Visible' } else { 'Collapsed' }
        $marker = $controls["Step$($_)Marker"]
        $marker.Background = if ($_ -le $Step) { '#1F6FEB' } else { '#DDE3EA' }
        $marker.Child.Foreground = if ($_ -le $Step) { 'White' } else { '#52606D' }
    }
    $controls.FooterText.Text = "Step $Step of 5"
    $controls.BackButton.IsEnabled = $Step -gt 1 -and $Step -lt 5
    $controls.NextButton.Visibility = if ($Step -eq 5) { 'Collapsed' } else { 'Visible' }
    $controls.NextButton.Content = if ($Step -eq 3) { 'Update selected remotes' } else { 'Next' }
    $controls.NextButton.IsEnabled = ($Step -eq 2 -and $folders.Count -gt 0) -or ($Step -eq 3 -and @($repositories | Where-Object Selected).Count -gt 0)
}

function Get-Origin([string]$Path) {
    $originOutput = @(& git -C $Path remote get-url origin 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or $originOutput.Count -eq 0) { return $null }
    return ([string]$originOutput[0]).Trim()
}

function Find-Repositories([string]$Root) {
    $found = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) { $found.Add($Root) }
    # A standard clone has a .git directory; a Git worktree has a .git file.
    Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' } |
        ForEach-Object { $found.Add($_.Parent.FullName) }
    $found
}

function Target-Exists([string]$Url) {
    $output = @(& git ls-remote $Url 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-RunLog "TARGET CHECK FAILED $Url | $($output -join ' ')"
        return 'Warning: target unavailable or no read access'
    }
    $repository = $Url.Replace($gitHubPrefix, '').Replace('.git', '')
    $canPushOutput = @(& $script:ghCommand api "repos/$organisation/$repository" --jq '.permissions.push' 2>&1)
    $canPush = [string]$canPushOutput[0]
    if ($LASTEXITCODE -ne 0 -or $canPush.Trim() -ne 'true') {
        Write-RunLog "TARGET WRITE CHECK FAILED $Url | $($canPushOutput -join ' ')"
        return 'Warning: no GitHub write permission'
    }
    return 'Available'
}

function Find-GitHubCli {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $locations = @(
        (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
    )
    foreach ($location in $locations) {
        if (Test-Path -LiteralPath $location) { return $location }
    }
    return $null
}

function Ensure-GitHubCli {
    $script:ghCommand = Find-GitHubCli
    if ($null -ne $script:ghCommand) { return $true }

    $install = [System.Windows.MessageBox]::Show(
        'GitHub CLI is required to sign in and verify organisation access. Install it now?',
        'Install GitHub CLI',
        [System.Windows.MessageBoxButton]::OKCancel,
        [System.Windows.MessageBoxImage]::Information
    )
    if ($install -ne [System.Windows.MessageBoxResult]::OK) { return $false }

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

function Show-Message([string]$Id, $Control, [object[]]$FormatArgs) {
    $entry = $script:messages[$Id]
    if ($null -eq $entry) { throw "Show-Message: unknown message id '$Id'" }
    $text = if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) { $entry.Text -f $FormatArgs } else { $entry.Text }
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
        [System.Windows.MessageBox]::Show($text, 'Local Git Migration Tool', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
    return $entry.Severity
}

function Find-GitHubReference($node) {
    if ($null -eq $node) { return $false }
    if ($node -is [string]) { return $node -match 'github' }
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $node.PSObject.Properties) {
            if (Find-GitHubReference $property.Value) { return $true }
        }
        return $false
    }
    if ($node -is [System.Collections.IDictionary]) {
        foreach ($key in $node.Keys) {
            if ($key -match 'github') { return $true }
            if (Find-GitHubReference $node[$key]) { return $true }
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

    try {
        $raw = Get-Content -LiteralPath $accountsPath -Raw -ErrorAction Stop
    } catch {
        $Error.RemoveAt(0)
        return 'CouldNotVerify'
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'NotFound' }

    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $Error.RemoveAt(0)
        return 'CouldNotVerify'
    }

    if (Find-GitHubReference $data) { return 'Found' }
    return 'NotFound'
}

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

function Test-GitLabOrigin([string]$Origin) {
    return $Origin -match '(?i)gitlab'
}

function Get-RepositoryName([string]$Origin) {
    return (Split-Path -Leaf $Origin.TrimEnd('/')) -replace '\.git$',''
}

function Test-UsesLfs([string]$Path) {
    $attributes = @(& git -C $Path show 'HEAD:.gitattributes' 2>$null)
    return $LASTEXITCODE -eq 0 -and ($attributes -match 'filter=lfs').Count -gt 0
}

function Scan-Repositories {
    $repositories.Clear()
    $seen = @{}
    $targetOwners = @{}
    $discovered = 0
    foreach ($folder in $folders) {
        foreach ($path in Find-Repositories $folder) {
            if ($seen.ContainsKey($path)) { continue }; $seen[$path] = $true
            $discovered++
            $origin = Get-Origin $path
            if ($null -eq $origin -or -not (Test-GitLabOrigin $origin)) { continue }
            $name = Get-RepositoryName $origin
            $target = "$gitHubPrefix$name.git"
            $targetStatus = Target-Exists $target
            $usesLfs = Test-UsesLfs $path
            if ($usesLfs) { $targetStatus += '; LFS detected: confirm LFS objects were migrated' }
            $available = $targetStatus.StartsWith('Available')
            $item = [pscustomobject]@{ Selected = $available; TargetAvailable = $available; Name = $name; Path = $path; Current = $origin; New = $target; TargetStatus = $targetStatus }
            if ($targetOwners.ContainsKey($target)) {
                $other = $targetOwners[$target]
                $other.Selected = $false; $other.TargetAvailable = $false; $other.TargetStatus = "Warning: name collision with $path"
                $item.Selected = $false; $item.TargetAvailable = $false; $item.TargetStatus = "Warning: name collision with $($other.Path)"
            } else { $targetOwners[$target] = $item }
            $repositories.Add($item)
            Write-RunLog "SCAN $path | $origin | $target | $($item.TargetStatus)"
        }
    }
    $available = @($repositories | Where-Object TargetAvailable).Count
    Show-Message -Id 'ScanComplete' -Control $controls.ReviewStatus -FormatArgs @($discovered, $repositories.Count, $available) | Out-Null
    Set-Step 3
}

function Verify-Access {
    $gitVersion = [string](& git --version 2>&1)
    if ($LASTEXITCODE -ne 0) { Show-Message -Id 'GitNotInstalled' -Control $controls.AccessStatus | Out-Null; return $false }
    $userOutput = @(& $script:ghCommand api user --jq '.login' 2>&1)
    $user = [string]$userOutput[0]
    $userExitCode = $LASTEXITCODE
    if ($userExitCode -ne 0) { Write-RunLog "GITHUB USER CHECK FAILED | $($userOutput -join ' ')"; Show-Message -Id 'SignInNotCompleted' -Control $controls.AccessStatus | Out-Null; return $false }
    $stateOutput = @(& $script:ghCommand api "user/memberships/orgs/$organisation" --jq '.state' 2>&1)
    $state = [string]$stateOutput[0]
    $stateExitCode = $LASTEXITCODE
    if ($stateExitCode -ne 0) {
        Write-RunLog "GITHUB ORGANISATION CHECK FAILED | $($stateOutput -join ' ')"
        Show-Message -Id 'OrgMembershipUnconfirmed' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
        return $false
    }
    if ($state.Trim() -ne 'active') {
        Show-Message -Id 'OrgMembershipInactive' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
        return $false
    }
    Show-Message -Id 'SignedIn' -Control $controls.AccessStatus -FormatArgs @($user.Trim(), $organisation) | Out-Null
    $script:githubUser = $user.Trim()
    Write-RunLog "PREFLIGHT Git=$($gitVersion.Trim()); GitHubUser=$($user.Trim()); Organisation=$organisation"
    return $true
}

function Update-SelectedRemotes {
    $selected = @($repositories | Where-Object Selected)
    $results.Clear()
    $script:lastUpdatedRepositories.Clear()
    $backupDirectory = Join-Path $env:LOCALAPPDATA 'KiroRaceCo\LocalGitMigrationTool\backups'
    if (-not (Test-Path -LiteralPath $backupDirectory)) { New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null }
    $script:backupPath = Join-Path $backupDirectory "remote-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    @($selected | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.Path; OriginalOrigin = $_.Current; NewOrigin = $_.New } }) |
        ConvertTo-Json | Set-Content -LiteralPath $script:backupPath -Encoding UTF8
    Write-RunLog "BACKUP $script:backupPath"
    foreach ($repository in @($repositories | Where-Object { -not $_.Selected })) {
        $details = if ($repository.TargetStatus -eq 'Available') { 'Not selected by the user.' } else { $repository.TargetStatus }
        $results.Add([pscustomobject]@{ Name = $repository.Name; Path = $repository.Path; Result = 'Not updated'; Details = $details })
    }
    Set-Step 4
    $controls.UpdateProgress.Maximum = $selected.Count; $controls.UpdateProgress.Value = 0
    for ($index = 0; $index -lt $selected.Count; $index++) {
        $repository = $selected[$index]
        Show-Message -Id 'UpdateProgressMsg' -Control $controls.ProgressStatus -FormatArgs @(($index + 1), $selected.Count, $repository.Name) | Out-Null
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        $gitOutput = @(& git -C $repository.Path remote set-url origin $repository.New 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $script:lastUpdatedRepositories.Add($repository)
            $results.Add([pscustomobject]@{ Name = $repository.Name; Path = $repository.Path; Result = 'Succeeded'; Details = 'Origin updated to GitHub.' })
            Write-RunLog "UPDATED $($repository.Path) | $($repository.Current) -> $($repository.New)"
        } else {
            $details = "Git could not update this origin: $($gitOutput -join ' ')"
            $results.Add([pscustomobject]@{ Name = $repository.Name; Path = $repository.Path; Result = 'Failed'; Details = $details })
            Write-RunLog "FAILED $($repository.Path) | $($gitOutput -join ' ')"
        }
        $controls.UpdateProgress.Value = $index + 1
    }
    $successful = @($results | Where-Object Result -eq 'Succeeded').Count
    $failed = @($results | Where-Object Result -eq 'Failed').Count
    $notUpdated = @($results | Where-Object Result -eq 'Not updated').Count
    $updateSummaryId = if ($failed -gt 0) { 'UpdateSummaryWithFailures' } else { 'UpdateSummarySuccess' }
    Show-Message -Id $updateSummaryId -Control $controls.SummaryStatus -FormatArgs @($successful, $failed, $notUpdated) | Out-Null
    Rename-SharedLog $successful
    $controls.RollbackButton.Visibility = if ($script:lastUpdatedRepositories.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $controls.LogPathText.Text = "Support log: $script:logPath"
    Set-Step 5
}

function Restore-OriginalRemotes {
    if ($script:lastUpdatedRepositories.Count -eq 0) { return }
    $confirmation = [System.Windows.MessageBox]::Show('Restore the original GitLab origin for every repository updated in this run?', 'Restore original remotes', [System.Windows.MessageBoxButton]::OKCancel, [System.Windows.MessageBoxImage]::Warning)
    if ($confirmation -ne [System.Windows.MessageBoxResult]::OK) { return }
    $restored = 0
    foreach ($repository in $script:lastUpdatedRepositories) {
        & git -C $repository.Path remote set-url origin $repository.Current 2>$null
        if ($LASTEXITCODE -eq 0) { $restored++; Write-RunLog "RESTORED $($repository.Path) | $($repository.Current)" }
        else { Write-RunLog "RESTORE FAILED $($repository.Path)" }
    }
    $restoreSummaryId = if ($restored -lt $script:lastUpdatedRepositories.Count) { 'RestoreSummaryWithFailures' } else { 'RestoreSummarySuccess' }
    Show-Message -Id $restoreSummaryId -Control $controls.SummaryStatus -FormatArgs @($restored, $script:lastUpdatedRepositories.Count) | Out-Null
    $controls.RollbackButton.Visibility = 'Collapsed'
}

$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    Show-Message -Id 'SigningIn' -Control $controls.AccessStatus | Out-Null
    Start-Process -FilePath $script:ghCommand -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'read:org') -Wait | Out-Null
    $script:accessVerified = Verify-Access
    Update-ForkStatusDisplay | Out-Null
    $controls.NextButton.IsEnabled = $script:accessVerified -and ($script:forkStatus -ne 'NotFound')
})
$controls.RecheckForkButton.Add_Click({
    Update-ForkStatusDisplay | Out-Null
    $controls.NextButton.IsEnabled = $script:accessVerified -and ($script:forkStatus -ne 'NotFound')
})
$controls.AddFolderButton.Add_Click({ $dialog = New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'Choose a folder containing Git repositories'; if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and -not $folders.Contains($dialog.SelectedPath)) { $folders.Add($dialog.SelectedPath); $controls.NextButton.IsEnabled = $true } })
$controls.RemoveFolderButton.Add_Click({ if ($null -ne $controls.FoldersList.SelectedItem) { $folders.Remove([string]$controls.FoldersList.SelectedItem); $controls.NextButton.IsEnabled = $folders.Count -gt 0 } })
$controls.RollbackButton.Add_Click({ Restore-OriginalRemotes })
$controls.NextButton.Add_Click({
    if ($script:currentStep -eq 1 -and $script:accessVerified) { Set-Step 2 }
    elseif ($script:currentStep -eq 2) { Scan-Repositories }
    elseif ($script:currentStep -eq 3) { Update-SelectedRemotes }
})
$controls.BackButton.Add_Click({ if ($script:currentStep -eq 2) { Set-Step 1 }; if ($script:currentStep -eq 3) { Set-Step 2 } })
if (-not $NoGui -and (Initialize-SharedLogging)) {
    Update-ForkStatusDisplay | Out-Null
    Set-Step 1
    $window.ShowDialog() | Out-Null
} elseif ($NoGui) {
    Update-ForkStatusDisplay | Out-Null
    Set-Step 1
}
