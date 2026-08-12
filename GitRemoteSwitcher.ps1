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
$script:ghCommand = $null
$script:lastUpdatedRepositories = New-Object System.Collections.Generic.List[object]
$script:backupPath = $null
$script:logPath = Join-Path $env:LOCALAPPDATA "KiroRaceCo\GitRemoteSwitcher\logs\run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Git Remote Switcher" Height="670" Width="1060" MinHeight="560" MinWidth="820"
        WindowStartupLocation="CenterScreen" Background="#F7F8FA" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button"><Setter Property="Padding" Value="15,7"/><Setter Property="Margin" Value="0,0,8,0"/></Style>
    <Style TargetType="TextBox"><Setter Property="Padding" Value="8,5"/><Setter Property="BorderBrush" Value="#B8C1CC"/></Style>
  </Window.Resources>
  <Grid Margin="30">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="Git Remote Switcher" FontSize="27" FontWeight="SemiBold" Foreground="#17202A"/>
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
        <TextBlock Text="Sign in with the GitHub account registered to your @kiroraceco.com email address. You must first accept your Kiro-Race-Co invitation. This check confirms the correct account and organisation access; it does not change any repositories." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
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
        <TextBlock Text="Add every top-level folder where you keep local Git repositories, for example C:\Projects or C:\Users\your-name\source. You can add more than one folder. The next step searches every subfolder recursively; do not select an individual .git folder. No repository setting is changed during this scan." TextWrapping="Wrap" Margin="0,8,0,18" Foreground="#52606D"/>
        <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <ListBox x:Name="FoldersList" Height="280" Background="White" BorderBrush="#DEE3E9" BorderThickness="1"/>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,12,0,0"><Button x:Name="AddFolderButton" Content="Add folder" Background="#1F6FEB" Foreground="White" BorderBrush="#1F6FEB"/><Button x:Name="RemoveFolderButton" Content="Remove selected"/></StackPanel>
        </Grid>
      </StackPanel>

      <StackPanel x:Name="Step3Panel" Visibility="Collapsed">
        <TextBlock Text="Review remote changes" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Review every repository whose current origin points to GitLab. The new origin is always Kiro-Race-Co on GitHub. This scan changes nothing. A warning means the GitHub repository does not exist, this account cannot read it, or this account cannot push to it; leave it unchecked and contact Tom Comrie. Confirm that every expected repository is present before continuing." TextWrapping="Wrap" Margin="0,8,0,12" Foreground="#52606D"/>
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
        <TextBlock Text="The tool is changing only each selected repository's local origin URL. It does not edit files, commits, branches, tags, stashes, GitLab, or GitHub. Keep this window open until the summary appears." Margin="0,10,0,8" TextAlignment="Center" TextWrapping="Wrap" Foreground="#52606D"/>
        <TextBlock x:Name="ProgressStatus" Margin="0,0,0,16" TextAlignment="Center" Foreground="#52606D"/>
        <ProgressBar x:Name="UpdateProgress" Height="20" Minimum="0" Maximum="1" Value="0"/>
      </StackPanel>

      <StackPanel x:Name="Step5Panel" Visibility="Collapsed">
        <TextBlock Text="Migration summary" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/>
        <TextBlock Text="Successful repositories are ready to use in Fork after it is refreshed. Failed or not-updated repositories have been left unchanged and can be safely retried after the issue is resolved." TextWrapping="Wrap" Margin="0,8,0,8" Foreground="#52606D"/>
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
    $directory = Split-Path -Parent $script:logPath
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Add-Content -LiteralPath $script:logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
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
    & git ls-remote $Url 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return 'Warning: target unavailable or no read access' }
    $repository = $Url.Replace($gitHubPrefix, '').Replace('.git', '')
    $canPush = [string](& $script:ghCommand api "repos/$organisation/$repository" --jq '.permissions.push' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $canPush.Trim() -ne 'true') { return 'Warning: no GitHub write permission' }
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
    $controls.ForkStatus.Text = switch ($script:forkStatus) {
        'NotInstalled'   { "Fork was not detected on this machine; skipping the Fork account check." }
        'Found'          { "Fork has a GitHub account configured." }
        'NotFound'       { "Fork does not have a GitHub account configured. Open Fork -> Preferences -> Accounts and add your GitHub account, then click Sign in and verify access again." }
        'CouldNotVerify' { "Could not verify Fork's GitHub account automatically. Check Fork -> Preferences -> Accounts manually." }
    }
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
    $controls.ReviewStatus.Text = "$discovered local Git repository(s) checked; $($repositories.Count) with a GitLab origin found; $available target repository(s) are available on GitHub."
    Set-Step 3
}

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

function Update-SelectedRemotes {
    $selected = @($repositories | Where-Object Selected)
    $results.Clear()
    $script:lastUpdatedRepositories.Clear()
    $backupDirectory = Join-Path $env:LOCALAPPDATA 'KiroRaceCo\GitRemoteSwitcher\backups'
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
        $controls.ProgressStatus.Text = "Updating $($index + 1) of $($selected.Count): $($repository.Name)"
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        & git -C $repository.Path remote set-url origin $repository.New 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:lastUpdatedRepositories.Add($repository)
            $results.Add([pscustomobject]@{ Name = $repository.Name; Path = $repository.Path; Result = 'Succeeded'; Details = 'Origin updated to GitHub.' })
            Write-RunLog "UPDATED $($repository.Path) | $($repository.Current) -> $($repository.New)"
        } else {
            $results.Add([pscustomobject]@{ Name = $repository.Name; Path = $repository.Path; Result = 'Failed'; Details = 'Git could not update this origin.' })
            Write-RunLog "FAILED $($repository.Path) | could not update origin"
        }
        $controls.UpdateProgress.Value = $index + 1
    }
    $successful = @($results | Where-Object Result -eq 'Succeeded').Count
    $failed = @($results | Where-Object Result -eq 'Failed').Count
    $notUpdated = @($results | Where-Object Result -eq 'Not updated').Count
    $controls.SummaryStatus.Text = "$successful repository(s) updated successfully; $failed failed; $notUpdated not updated. Refresh Fork to use the new remotes."
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
    $controls.SummaryStatus.Text = "$restored of $($script:lastUpdatedRepositories.Count) original remote(s) restored. Refresh Fork to see the restored origins."
    $controls.RollbackButton.Visibility = 'Collapsed'
}

$controls.LoginButton.Add_Click({
    if (-not (Ensure-GitHubCli)) { return }
    $controls.AccessStatus.Text = 'Complete the GitHub sign-in in your browser...'
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
Update-ForkStatusDisplay | Out-Null
Set-Step 1
if (-not $NoGui) { $window.ShowDialog() | Out-Null }
