# ============================================================
# UGSM Main Form
# Shared UI helper functions and theme colors live in UGSM_UI_Helpers.ps1.
# This file should only build and wire the main shell.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Guard: UGSM_UI_Helpers.ps1 must load before this file.
$requiredUiHelpers = @(
    'New-UGSMLabel',
    'New-UGSMButton',
    'New-UGSMPanel',
    'Get-UGSMTheme',
    'Enable-UGSMDoubleBuffer',
    'New-UGSMDockPanel',
    'New-UGSMFlowPanel',
    'New-UGSMListBox',
    'New-UGSMMetricCard',
    'Add-CardHeader',
    'Test-UGSMTagCallback',
    'Write-UGSMTrace',
    'Format-UGSMTraceInstance'
)

foreach ($helperName in $requiredUiHelpers) {
    if (-not (Get-Command $helperName -ErrorAction SilentlyContinue)) {
        throw ("Required UI helper '{0}' was not loaded. Check UGSM_UI_Helpers.ps1 load order." -f $helperName)
    }
}


function Format-UGSMDialogMessage {
    param([AllowNull()][object]$Message)

    $text = [string]$Message
    if ([string]::IsNullOrEmpty($text)) { return '' }

    $nl = [Environment]::NewLine
    return ($text -replace '``r``n', $nl -replace '``n', $nl -replace '``r', $nl -replace '\r\n', $nl -replace '\n', $nl -replace '\r', $nl)
}

function New-UGSMMainForm {
    param(
        [Parameter(Mandatory)]
        [object]$AppState
    )
    $theme = Get-UGSMTheme

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'UGSM v2'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1600, 980)
    $form.MinimumSize = New-Object System.Drawing.Size(1400, 860)
    $form.BackColor = $theme.WindowBg
    $form.ForeColor = $theme.Text
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:MainForm = $form
    $form.KeyPreview = $true
    Enable-UGSMDoubleBuffer -Control $form

    # Root shell: top bar, content region, status bar
    $rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $rootLayout.Dock = 'Fill'
    $rootLayout.BackColor = $theme.WindowBg
    $rootLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $rootLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    $rootLayout.ColumnCount = 1
    $rootLayout.RowCount = 3
    [void]$rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
    [void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
    [void]$form.Controls.Add($rootLayout)

    # Top bar
    $topBar = New-Object System.Windows.Forms.Panel
    $topBar.Dock = 'Fill'
    $topBar.Margin = New-Object System.Windows.Forms.Padding(0)
    $topBar.BackColor = $theme.TopBar
    [void]$rootLayout.Controls.Add($topBar, 0, 0)

    $topLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $topLayout.Dock = 'Fill'
    $topLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $topLayout.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)
    $topLayout.ColumnCount = 2
    $topLayout.RowCount = 1
    [void]$topLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 300)))
    [void]$topLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$topLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$topBar.Controls.Add($topLayout)

    $titleHost = New-Object System.Windows.Forms.Panel
    $titleHost.Dock = 'Fill'
    $titleHost.Margin = New-Object System.Windows.Forms.Padding(0)
    $titleHost.BackColor = [System.Drawing.Color]::Transparent
    [void]$titleHost.Controls.Add((New-UGSMLabel -Text 'UGSM' -X 0 -Y 2 -Width 180 -Height 22 -FontSize 15 -Style Bold -Color $global:UGSM_ColorText))
    [void]$titleHost.Controls.Add((New-UGSMLabel -Text 'Universal Game Server Manager' -X 0 -Y 24 -Width 280 -Height 18 -FontSize 8.5 -Color $theme.Muted))
    [void]$topLayout.Controls.Add($titleHost, 0, 0)

    $toolbarHost = New-UGSMFlowPanel -Dock 'Fill' -BackColor ([System.Drawing.Color]::Transparent) -Padding (New-Object System.Windows.Forms.Padding(0, 4, 0, 0)) -FlowDirection ([System.Windows.Forms.FlowDirection]::LeftToRight) -WrapContents $false -AutoScroll $false
    [void]$topLayout.Controls.Add($toolbarHost, 1, 0)

    $toolbarButtons = @{}
    $quickStartButton = $null
    $quickStopButton = $null
    $quickRestartButton = $null


    foreach ($item in @('Install', 'Update', 'Verify', 'Start', 'Stop', 'Restart', 'Backup', 'Logs', 'App Update')) {
        $color = switch ($item) {
            'Start' { $theme.Accent }
            'Stop' { $global:UGSM_ColorButtonStopMuted }
            'Restart' { $theme.AccentBlue }
            default { $theme.SurfaceAlt }
        }

        $buttonWidth = if ($item -eq 'App Update') { 106 } else { 86 }
        $btn = New-UGSMButton -Text $item -X 0 -Y 0 -Width $buttonWidth -Height 34 -BackColor $color
        $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
        [void]$toolbarHost.Controls.Add($btn)

        $toolbarButtons[$item] = $btn
    }

    $statusChip = New-UGSMPanel -X 0 -Y 0 -Width 320 -Height 34 -BackColor $global:UGSM_ColorHealthyBackground -BorderColor $global:UGSM_ColorHealthyBorder
    $statusChip.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $statusChip.Padding = New-Object System.Windows.Forms.Padding(0)
    $statusChip.Cursor = 'Default'

    $machineStatusTitleLabel = New-UGSMLabel -Text 'Machine Status:' -X 10 -Y 4 -Width 100 -Height 12 -Color $global:UGSM_ColorHealthy -FontSize 7.5 -Style Bold
    $machineStatusValueLabel = New-UGSMLabel -Text 'Monitoring...' -X 10 -Y 16 -Width 300 -Height 14 -Color $global:UGSM_ColorHealthy -FontSize 7.5 -Style Bold

    [void]$statusChip.Controls.Add($machineStatusTitleLabel)
    [void]$statusChip.Controls.Add($machineStatusValueLabel)
    [void]$toolbarHost.Controls.Add($statusChip)

    $UpdateMachineStatusUI = {
        $pageData = $null
        $summary = $null

        if (Get-Command Get-UGSMAnalyticsPageData -ErrorAction SilentlyContinue) {
            try {
                $pageData = Get-UGSMAnalyticsPageData -AppState $AppState
                if ($pageData) {
                    $summary = $pageData.Summary
                }
            }
            catch {
                $summary = $null
            }
        }

        if (-not $summary) {
            if ($machineStatusValueLabel -and -not $machineStatusValueLabel.IsDisposed) {
                $machineStatusValueLabel.AutoEllipsis = $true
                $machineStatusValueLabel.Text = 'Monitoring unavailable'
                $machineStatusValueLabel.ForeColor = $global:UGSM_ColorCaution
            }

            if ($toolbarButtons['Start']) {
                $toolbarButtons['Start'].Enabled = $true
            }
            if ($quickStartButton) {
                $quickStartButton.Enabled = $true
            }
            return
        }

        $statusState = [string]$summary.CapacityState
        $statusMessage = [string]$summary.CapacityMessage

        if ([string]::IsNullOrWhiteSpace($statusState)) {
            $statusState = 'Healthy'
        }
        if ([string]::IsNullOrWhiteSpace($statusMessage)) {
            $statusMessage = 'System remains within a safe operating range'
        }

        $statusColor = switch ($statusState) {
            'Critical' { $global:UGSM_ColorDanger }
            'Warning' { $global:UGSM_ColorCaution }
            'Healthy' { $global:UGSM_ColorHealthy }
            default { $global:UGSM_ColorHealthy }
        }

        if ($machineStatusValueLabel -and -not $machineStatusValueLabel.IsDisposed) {
            $machineStatusValueLabel.AutoEllipsis = $true
            $machineStatusValueLabel.Text = $statusMessage
            $machineStatusValueLabel.ForeColor = New-UGSMColor $statusColor
        }

        if ($toolbarButtons['Start'] -and $summary.PSObject.Properties['CanStartMoreServers']) {
            $toolbarButtons['Start'].Enabled = [bool]$summary.CanStartMoreServers
        }
        if ($quickStartButton -and $summary.PSObject.Properties['CanStartMoreServers']) {
            $quickStartButton.Enabled = [bool]$summary.CanStartMoreServers
        }
    }.GetNewClosure()


    # Main content shell: left rail, navigation, and expandable center workspace
    $contentLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $contentLayout.Dock = 'Fill'
    $contentLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $contentLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    $contentLayout.BackColor = $theme.WindowBg
    $contentLayout.ColumnCount = 3
    $contentLayout.RowCount = 1
    [void]$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 104)))
    [void]$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 276)))
    [void]$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$rootLayout.Controls.Add($contentLayout, 0, 1)

    # Left nav rail
    $leftNav = New-Object System.Windows.Forms.Panel
    $leftNav.Dock = 'Fill'
    $leftNav.Margin = New-Object System.Windows.Forms.Padding(0)
    $leftNav.BackColor = $theme.Sidebar
    [void]$contentLayout.Controls.Add($leftNav, 0, 0)

    $brandButton = New-Object System.Windows.Forms.Panel
    $brandButton.Location = New-Object System.Drawing.Point(10, 16)
    $brandButton.Size = New-Object System.Drawing.Size(68, 52)
    $brandButton.BackColor = $theme.Accent
    $leftNav.Controls.Add($brandButton)
    $brandButton.Controls.Add((New-UGSMLabel -Text 'UG' -X 0 -Y 12 -Width 68 -Height 24 -Align MiddleCenter -FontSize 16 -Style Bold -Color $global:UGSM_ColorBrandTextDark))

    $navItems = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
    $navY = 90

    $settingsNavButton = $null
    $navButtons = @{}
    foreach ($nav in $navItems) {
        $navButton = New-UGSMButton -Text $nav -X 10 -Y $navY -Width 68 -Height 42 -BackColor $theme.Sidebar
        $navButton.FlatAppearance.BorderColor = $theme.Sidebar

        if ($nav -eq 'Settings') {
            $settingsNavButton = $navButton
        }

        $navButtons[$nav] = $navButton
        $leftNav.Controls.Add($navButton)
        $navY += 52
    }

    # Secondary nav panel
    $secondNav = New-Object System.Windows.Forms.Panel
    $secondNav.Dock = 'Fill'
    $secondNav.Margin = New-Object System.Windows.Forms.Padding(0)
    $secondNav.BackColor = $theme.SecondaryPanel
    [void]$contentLayout.Controls.Add($secondNav, 1, 0)

    $secondNav.Controls.Add((New-UGSMLabel -Text 'Navigation' -X 18 -Y 18 -Width 150 -Height 24 -FontSize 13 -Style Bold))
    $secondNav.Controls.Add((New-UGSMLabel -Text 'Pick a game and instance' -X 18 -Y 42 -Width 190 -Height 20 -FontSize 8.5 -Color $theme.Muted))

    $gameCard = New-UGSMPanel -X 16 -Y 78 -Width 228 -Height 220 -BackColor $global:UGSM_ColorSurfaceDeep -BorderColor $theme.Border
    $secondNav.Controls.Add($gameCard)
    Add-CardHeader -Card $gameCard -Title 'Games'

    $gameList = New-UGSMListBox -X 14 -Y 58 -Width 198 -Height 140 -BackColor $global:UGSM_ColorBackground -ForeColor $theme.Text
    $gameCard.Controls.Add($gameList)

    $instanceCard = New-UGSMPanel -X 16 -Y 312 -Width 228 -Height 306 -BackColor $global:UGSM_ColorSurfaceDeep -BorderColor $theme.Border
    $secondNav.Controls.Add($instanceCard)
    Add-CardHeader -Card $instanceCard -Title 'Instances'

    $instanceList = New-UGSMListBox -X 14 -Y 58 -Width 198 -Height 160 -BackColor $global:UGSM_ColorBackground -ForeColor $theme.Text
    $instanceCard.Controls.Add($instanceList)

    $btnInstanceAdd = New-UGSMButton -Text 'Add' -X 14 -Y 235 -Width 62 -Height 32 -BackColor $theme.Accent
    $btnInstanceEdit = New-UGSMButton -Text 'Edit' -X 82 -Y 235 -Width 62 -Height 32
    $btnInstanceRemove = New-UGSMButton -Text 'Remove' -X 150 -Y 235 -Width 62 -Height 32 -BackColor $global:UGSM_ColorButtonRemoveMuted
    $instanceCard.Controls.Add($btnInstanceAdd)
    $instanceCard.Controls.Add($btnInstanceEdit)
    $instanceCard.Controls.Add($btnInstanceRemove)

    # Center shell panel
    $dashboard = New-Object System.Windows.Forms.Panel
    $dashboard.Dock = 'Fill'
    $dashboard.Margin = New-Object System.Windows.Forms.Padding(0)
    $dashboard.BackColor = $theme.WindowBg
    [void]$contentLayout.Controls.Add($dashboard, 2, 0)

    $centerCanvas = New-Object System.Windows.Forms.Panel
    $centerCanvas.Dock = 'Fill'
    $centerCanvas.Margin = New-Object System.Windows.Forms.Padding(0)
    $centerCanvas.Padding = New-Object System.Windows.Forms.Padding(14, 14, 14, 18)
    $centerCanvas.BackColor = $global:UGSM_ColorCanvasBackground
    $dashboard.Controls.Add($centerCanvas)
    $centerCanvas.Add_Paint({
            param($sender, $e)
            $pen = New-Object System.Drawing.Pen(($global:UGSM_ColorCanvasBorder))
            $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
            $pen.Dispose()
        })

    $centerLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $centerLayout.Dock = 'Fill'
    $centerLayout.BackColor = $global:UGSM_ColorCanvasBackground
    $centerLayout.ColumnCount = 1
    $centerLayout.RowCount = 4
    $centerLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $centerLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$centerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$centerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 60)))
    [void]$centerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 128)))
    [void]$centerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
    [void]$centerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$centerCanvas.Controls.Add($centerLayout)

    $banner = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 52 -BackColor $global:UGSM_ColorBannerBackground -BorderColor $global:UGSM_ColorHealthyBorder
    $banner.Dock = 'Fill'
    $banner.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    [void]$centerLayout.Controls.Add($banner, 0, 0)
    [void]$banner.Controls.Add((New-UGSMLabel -Text 'Capacity Advisor: This machine can safely run 2 more SCUM instances or 1 more ARK server.' -X 16 -Y 10 -Width 1040 -Height 22 -Color $global:UGSM_ColorBannerTextPrimary -FontSize 10 -Style Bold))
    [void]$banner.Controls.Add((New-UGSMLabel -Text 'Current estimate uses CPU threads, free RAM, disk headroom, and active instance count. Numbers update from live service data when available.' -X 16 -Y 30 -Width 1040 -Height 18 -Color $global:UGSM_ColorBannerTextSecondary -FontSize 8.5))
    $banner.Add_Resize({
            param($sender, $eventArgs)
            foreach ($ctrl in $sender.Controls) {
                if ($ctrl -is [System.Windows.Forms.Label]) {
                    $ctrl.Width = [Math]::Max(180, $sender.ClientSize.Width - 32)
                }
            }
        })

    $topCardsRow = New-Object System.Windows.Forms.TableLayoutPanel
    $topCardsRow.Dock = 'Fill'
    $topCardsRow.BackColor = $theme.WindowBg
    $topCardsRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $topCardsRow.Padding = New-Object System.Windows.Forms.Padding(0)
    $topCardsRow.ColumnCount = 4
    $topCardsRow.RowCount = 1
    [void]$topCardsRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    1..4 | ForEach-Object { [void]$topCardsRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) }
    [void]$centerLayout.Controls.Add($topCardsRow, 0, 1)

    $topCardDefs = @(
        @{ Title = 'CPU Usage'; Sub = 'Host utilization'; Value = '42%'; Meta = '16 threads / 7 active'; Accent = $theme.AccentBlue },
        @{ Title = 'RAM Usage'; Sub = 'Memory pressure'; Value = '18.4 / 32 GB'; Meta = 'Safe headroom: 9.6 GB'; Accent = $theme.Accent },
        @{ Title = 'Disk Space'; Sub = 'Server storage'; Value = '1.24 TB Free'; Meta = 'Fast SSD healthy'; Accent = $theme.AccentYellow },
        @{ Title = 'Active Servers'; Sub = 'Running instances'; Value = '3'; Meta = '2 SCUM, 1 ARK SE'; Accent = $global:UGSM_ColorDanger }
    )

    $diskCardValueLabel = $null
    $diskCardMetaLabel = $null
    $diskCardAccentPanel = $null
    for ($i = 0; $i -lt $topCardDefs.Count; $i++) {
        $cardDef = $topCardDefs[$i]
        $metricCard = New-UGSMMetricCard -Definition $cardDef -Index $i -Count $topCardDefs.Count -Gap 12 -ValueY 64 -MetaY 92 -BackColor $theme.Surface -BorderColor $theme.Border -MetaColor $theme.Muted

        if ($cardDef.Title -eq 'Disk Space') {
            $diskCardValueLabel = $metricCard.ValueLabel
            $diskCardMetaLabel = $metricCard.MetaLabel
            $diskCardAccentPanel = $metricCard.Accent
        }

        [void]$topCardsRow.Controls.Add($metricCard.Slot, $i, 0)
    }

    $midCardsRow = New-Object System.Windows.Forms.TableLayoutPanel
    $midCardsRow.Dock = 'Fill'
    $midCardsRow.BackColor = $theme.WindowBg
    $midCardsRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $midCardsRow.Padding = New-Object System.Windows.Forms.Padding(0)
    $midCardsRow.ColumnCount = 3
    $midCardsRow.RowCount = 1
    [void]$midCardsRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$midCardsRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
    [void]$midCardsRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
    [void]$midCardsRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.34)))
    [void]$centerLayout.Controls.Add($midCardsRow, 0, 2)

    $midCardDefs = @(
        @{ Title = 'Machine Info'; Sub = 'Host diagnostics'; Value = 'Gaming Rig #1'; Meta = 'Ryzen 9 / 32 GB / 2 TB SSD'; Accent = $theme.Accent },
        @{ Title = 'Capacity Score'; Sub = 'Overall health'; Value = '77 / 100'; Meta = 'Good for more test servers'; Accent = $theme.AccentBlue },
        @{ Title = 'Network Status'; Sub = 'Ports and traffic'; Value = 'Stable'; Meta = '38 Mbps up / 22 Mbps down'; Accent = $theme.AccentYellow }
    )

    for ($i = 0; $i -lt $midCardDefs.Count; $i++) {
        $cardDef = $midCardDefs[$i]
        $metricCard = New-UGSMMetricCard -Definition $cardDef -Index $i -Count $midCardDefs.Count -Gap 14 -ValueY 66 -MetaY 98 -BackColor $theme.Surface -BorderColor $theme.Border -MetaColor $theme.Muted
        [void]$midCardsRow.Controls.Add($metricCard.Slot, $i, 0)
    }

    $analyticsCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $theme.Surface -BorderColor $theme.Border
    $analyticsCard.Dock = 'Fill'
    $analyticsCard.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$centerLayout.Controls.Add($analyticsCard, 0, 3)
    Add-CardHeader -Card $analyticsCard -Title 'Server Capacity Performance' -Subtitle 'Capacity and performance overview'

    $homePageControl = $null
    $gamesPageControl = $null
    $instancesPageControl = $null
    $analyticsPageControl = $null
    $tasksPageControl = $null
    $aboutPageControl = $null
    $GetLiveInstancesPageControl = {
        if ($instancesPageControl -and -not $instancesPageControl.IsDisposed) {
            return $instancesPageControl
        }

        if ($dashboard -and -not $dashboard.IsDisposed) {
            foreach ($ctrl in $dashboard.Controls) {
                if ($ctrl -and -not $ctrl.IsDisposed -and $ctrl.Tag) {
                    $hasSetSelected = Test-UGSMTagCallback -Tag $ctrl.Tag -Name 'SetSelectedInstance'
                    $hasRefreshAll = Test-UGSMTagCallback -Tag $ctrl.Tag -Name 'RefreshAll'
                    if ($hasSetSelected -or $hasRefreshAll) {
                        return $ctrl
                    }
                }
            }
        }

        return $null
    }.GetNewClosure()
    $script:UGSM_MainFormGetLiveInstancesPageControl = $GetLiveInstancesPageControl
    $ResolveLiveInstancesPageControl = {
        $resolver = $null

        try {
            $localVar = Get-Variable -Name 'GetLiveInstancesPageControl' -Scope 1 -ErrorAction SilentlyContinue
            if ($localVar -and $localVar.Value -is [scriptblock]) {
                $resolver = $localVar.Value
            }
        }
        catch { }

        if (-not $resolver) {
            try {
                $scriptVar = Get-Variable -Name 'UGSM_MainFormGetLiveInstancesPageControl' -Scope Script -ErrorAction SilentlyContinue
                if ($scriptVar -and $scriptVar.Value -is [scriptblock]) {
                    $resolver = $scriptVar.Value
                }
            }
            catch { }
        }

        if ($resolver -is [scriptblock]) {
            return (& $resolver)
        }

        return $null
    }.GetNewClosure()


    $RefreshGamesPageUI = {
    if ($gamesPageControl -and -not $gamesPageControl.IsDisposed) {
        $dashboard.Controls.Remove($gamesPageControl)
        $gamesPageControl.Dispose()
        $gamesPageControl = $null
    }

    if (Get-Command New-UGSMGamesPage -ErrorAction SilentlyContinue) {
        $gamesPageControl = New-UGSMGamesPage -Theme $theme
        $gamesPageControl.Dock = 'Fill'
        [void]$dashboard.Controls.Add($gamesPageControl)
        $gamesPageControl.BringToFront()

        if ($gamesPageControl.Tag) {
            $gamesPageControl.Tag | Add-Member -NotePropertyName RefreshShell -NotePropertyValue $null -Force
            $gamesPageControl.Tag.RefreshShell = $RefreshGamesPageUI
        }
    }

    if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
        $statusResultLabel.Text = 'Last Result: Games page refreshed'
    }
}.GetNewClosure()

    $DisposeActivePages = {
        foreach ($ctrl in @(
                $homePageControl,
                $gamesPageControl,
                $instancesPageControl,
                $analyticsPageControl,
                $tasksPageControl,
                $aboutPageControl
            )) {
            if ($ctrl -and -not $ctrl.IsDisposed) {
                $dashboard.Controls.Remove($ctrl)
                $ctrl.Dispose()
            }
        }

        $homePageControl = $null
        $gamesPageControl = $null
        $instancesPageControl = $null
        $analyticsPageControl = $null
        $tasksPageControl = $null
        $modsPageControl = $null
        $filesPageControl = $null
        $aboutPageControl = $null
    }.GetNewClosure()

    $showPage = {
        param([string]$pageName)

        foreach ($key in $navButtons.Keys) {
            $btn = $navButtons[$key]
            if (-not $btn -or $btn.IsDisposed) { continue }
            $btn.BackColor = $theme.Sidebar
            $btn.FlatAppearance.BorderColor = $theme.Sidebar
            if ($key -eq $pageName) {
                $btn.BackColor = $global:UGSM_ColorNeutral
                $btn.FlatAppearance.BorderColor = $theme.Accent
            }
        }

        switch ($pageName) {
            'Home' {
                $centerCanvas.Visible = $false
                if ($gamesPageControl -and -not $gamesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($gamesPageControl)
                    $gamesPageControl.Dispose()
                    $gamesPageControl = $null
                }
                if ($instancesPageControl -and -not $instancesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($instancesPageControl)
                    $instancesPageControl.Dispose()
                    $instancesPageControl = $null
                }
                if ($homePageControl -and -not $homePageControl.IsDisposed) {
                    $dashboard.Controls.Remove($homePageControl)
                    $homePageControl.Dispose()
                    $homePageControl = $null
                }
                if (Get-Command New-UGSMHomePage -ErrorAction SilentlyContinue) {
                    $homePageControl = New-UGSMHomePage -Theme $theme
                    $homePageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($homePageControl)
                    $homePageControl.BringToFront()
                }
                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: Home overview loaded'
                }
            }
            'Games' {
                $centerCanvas.Visible = $false
                if ($homePageControl -and -not $homePageControl.IsDisposed) {
                    $dashboard.Controls.Remove($homePageControl)
                    $homePageControl.Dispose()
                    $homePageControl = $null
                }
                if ($instancesPageControl -and -not $instancesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($instancesPageControl)
                    $instancesPageControl.Dispose()
                    $instancesPageControl = $null
                }
                if ($gamesPageControl -and -not $gamesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($gamesPageControl)
                    $gamesPageControl.Dispose()
                    $gamesPageControl = $null
                }
                if (Get-Command New-UGSMGamesPage -ErrorAction SilentlyContinue) {
                    $gamesPageControl = New-UGSMGamesPage -Theme $theme
                    $gamesPageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($gamesPageControl)
                    $gamesPageControl.BringToFront()
                }
                if ($gamesPageControl.Tag) {
    $gamesPageControl.Tag | Add-Member -NotePropertyName RefreshShell -NotePropertyValue $null -Force
    $gamesPageControl.Tag.RefreshShell = $RefreshGamesPageUI
}
                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: Games page loaded'
                }
            }
            'Instances' {
                $centerCanvas.Visible = $false
                if ($homePageControl -and -not $homePageControl.IsDisposed) {
                    $dashboard.Controls.Remove($homePageControl)
                    $homePageControl.Dispose()
                    $homePageControl = $null
                }
                if ($gamesPageControl -and -not $gamesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($gamesPageControl)
                    $gamesPageControl.Dispose()
                    $gamesPageControl = $null
                }
                if ($instancesPageControl -and -not $instancesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($instancesPageControl)
                    $instancesPageControl.Dispose()
                    $instancesPageControl = $null
                }
                if (Get-Command New-UGSMInstancesPage -ErrorAction SilentlyContinue) {
                    Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message ('Creating Instances page. AppState selected=' + (Format-UGSMTraceInstance $AppState.SelectedInstance))
                    $instancesPageControl = New-UGSMInstancesPage -Theme $theme -AppState $AppState
                    Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message ('Instances page created. ControlType=' + $(if ($instancesPageControl) { $instancesPageControl.GetType().FullName } else { '<null>' }) + '; IsDisposed=' + [string]$(if ($instancesPageControl) { $instancesPageControl.IsDisposed } else { $true }) + '; TagType=' + $(if ($instancesPageControl -and $instancesPageControl.Tag) { $instancesPageControl.Tag.GetType().FullName } else { '<null>' }))
                    if ($instancesPageControl -and $instancesPageControl.Tag) {
                        $tagHasRenderState = Test-UGSMTagCallback -Tag $instancesPageControl.Tag -Name 'RenderState'
                        $tagHasSetSelected = Test-UGSMTagCallback -Tag $instancesPageControl.Tag -Name 'SetSelectedInstance'
                        $tagHasRefreshAll = Test-UGSMTagCallback -Tag $instancesPageControl.Tag -Name 'RefreshAll'
                        $tagHasRefreshShell = Test-UGSMTagCallback -Tag $instancesPageControl.Tag -Name 'RefreshShell'
                        Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message ('Instances page tag inspection. HasRenderState=' + [string]$tagHasRenderState + '; HasSetSelectedInstance=' + [string]$tagHasSetSelected + '; HasRefreshAll=' + [string]$tagHasRefreshAll + '; HasRefreshShell=' + [string]$tagHasRefreshShell)
                    }
                    if ($instancesPageControl -and (Test-UGSMTagCallback -Tag $instancesPageControl.Tag -Name 'RefreshShell')) {
                        Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message 'Wiring instancesPageControl.Tag.RefreshShell callback'
                        $instancesPageControl.Tag.RefreshShell = {
                            Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message ('RefreshShell callback invoked. AppState selected=' + (Format-UGSMTraceInstance $AppState.SelectedInstance))
                            if ($UpdateSelectedInstanceContextUI -is [scriptblock]) {
                                & $UpdateSelectedInstanceContextUI $AppState.SelectedInstance
                            }
                            if ($UpdateStatusBarUI -is [scriptblock]) {
                                & $UpdateStatusBarUI
                            }
                        }
                    }
                    $instancesPageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($instancesPageControl)
                    $instancesPageControl.BringToFront()
                    Write-UGSMTrace -Component 'UI.MainForm.InstancesPageHost' -Message ('Instances page added to dashboard. Visible=' + [string]$instancesPageControl.Visible + '; Parent=' + $(if ($instancesPageControl.Parent) { $instancesPageControl.Parent.GetType().FullName } else { '<null>' }) + '; AppStateRefMatches=' + [string][object]::ReferenceEquals((& $GetLiveInstancesPageControl), $instancesPageControl))
                }
                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: Instances page loaded'
                }
            }
            'Analytics' {
                $centerCanvas.Visible = $false
                if ($homePageControl -and -not $homePageControl.IsDisposed) {
                    $dashboard.Controls.Remove($homePageControl)
                    $homePageControl.Dispose()
                    $homePageControl = $null
                }
                if ($gamesPageControl -and -not $gamesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($gamesPageControl)
                    $gamesPageControl.Dispose()
                    $gamesPageControl = $null
                }
                if ($instancesPageControl -and -not $instancesPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($instancesPageControl)
                    $instancesPageControl.Dispose()
                    $instancesPageControl = $null
                }
                if ($analyticsPageControl -and -not $analyticsPageControl.IsDisposed) {
                    $dashboard.Controls.Remove($analyticsPageControl)
                    $analyticsPageControl.Dispose()
                    $analyticsPageControl = $null
                }
                if (Get-Command New-UGSMAnalyticsPage -ErrorAction SilentlyContinue) {
                    $analyticsPageControl = New-UGSMAnalyticsPage -Theme $theme -AppState $AppState
                    $analyticsPageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($analyticsPageControl)
                    $analyticsPageControl.BringToFront()
                }
                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: Analytics page loaded'
                }
            }
            'Tasks' {
                $centerCanvas.Visible = $false
                & $DisposeActivePages

                if (Get-Command New-UGSMTasksPage -ErrorAction SilentlyContinue) {
                    $tasksPageControl = New-UGSMTasksPage -Theme $theme
                    $tasksPageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($tasksPageControl)
                    $tasksPageControl.BringToFront()
                }

                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: Tasks page loaded'
                }
            }
            'About' {
                $centerCanvas.Visible = $false
                & $DisposeActivePages

                if (Get-Command New-UGSMAboutPage -ErrorAction SilentlyContinue) {
                    $aboutPageControl = New-UGSMAboutPage -Theme $theme
                    $aboutPageControl.Dock = 'Fill'
                    [void]$dashboard.Controls.Add($aboutPageControl)
                    $aboutPageControl.BringToFront()
                }

                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = 'Last Result: About page loaded'
                }
            }
            default {
                if ($statusResultLabel -and -not $statusResultLabel.IsDisposed) {
                    $statusResultLabel.Text = ('Last Result: ' + $pageName + ' page not built yet')
                }
            }
        }
    }.GetNewClosure()

    # Right context rail removed. Page content now owns instance details, actions, and health messaging.
    # Keep this no-op hook so existing page-switch and selection calls remain safe during the refactor.
    $UpdateHealthWarningsUI = {
        return
    }.GetNewClosure()

    # Status bar
    $statusBar = New-Object System.Windows.Forms.Panel
    $statusBar.Dock = 'Fill'
    $statusBar.Margin = New-Object System.Windows.Forms.Padding(0)
    $statusBar.BackColor = $global:UGSM_ColorStatusBarBackground
    [void]$rootLayout.Controls.Add($statusBar, 0, 2)
    $statusGameLabel = New-UGSMLabel -Text 'Game: None' -X 12 -Y 4 -Width 110 -Height 18 -Color $theme.Muted -FontSize 8.5
    $statusInstanceLabel = New-UGSMLabel -Text 'Instance: None' -X 130 -Y 4 -Width 260 -Height 18 -Color $theme.Muted -FontSize 8.5
    $statusProcessLabel = New-UGSMLabel -Text 'Process: None' -X 410 -Y 4 -Width 120 -Height 18 -Color $theme.Muted -FontSize 8.5
    $statusResultLabel = New-UGSMLabel -Text 'Last Result: Ready' -X 550 -Y 4 -Width 1200 -Height 18 -Color $theme.Muted -FontSize 8.5
    [void]$statusBar.Controls.Add($statusGameLabel)
    [void]$statusBar.Controls.Add($statusInstanceLabel)
    [void]$statusBar.Controls.Add($statusProcessLabel)
    [void]$statusBar.Controls.Add($statusResultLabel)

    # =========================================================
    # UI Update Logic
    # =========================================================

    $instanceList.DisplayMember = 'Name'
    $AppState.GameDisplayMap = @{}

    $UpdateStatusBarUI = {
        if ($AppState.SelectedInstance) {
            $statusGameLabel.Text = "Game: $($AppState.SelectedInstance.GameId)"
            $statusInstanceLabel.Text = "Instance: $($AppState.SelectedInstance.Name)"

            $statusText = [string]$AppState.SelectedInstance.Status
            if ([string]::IsNullOrWhiteSpace($statusText)) {
                $statusText = 'Unknown'
            }

            $statusProcessLabel.Text = "Process: $statusText"

            switch ($statusText) {
                'Running' { $statusProcessLabel.ForeColor = $global:UGSM_ColorHealthy }
                'Starting' { $statusProcessLabel.ForeColor = $global:UGSM_ColorStarting }
                'Stopped' { $statusProcessLabel.ForeColor = $global:UGSM_ColorMutedText }
                default { $statusProcessLabel.ForeColor = $global:UGSM_ColorMutedText }
            }
        }
        else {
            $statusGameLabel.Text = 'Game: None'
            $statusInstanceLabel.Text = 'Instance: None'
            $statusProcessLabel.Text = 'Process: None'
            $statusProcessLabel.ForeColor = $theme.Muted
        }
    }.GetNewClosure()

    $SetStatusResult = {
        param(
            [string]$Text,
            [string]$ColorHex = $theme.Muted
        )

        if ([string]::IsNullOrWhiteSpace($Text)) {
            $Text = 'Ready'
        }

        $statusResultLabel.Text = "Last Result: $Text"
        $statusResultLabel.ForeColor = New-UGSMColor $ColorHex
    }.GetNewClosure()

    $UpdateSelectedInstanceContextUI = {
        param($Instance)

# Context rail was removed; selected instance details now live in the active page content.
# This hook is kept so existing selection flows do not need to be rewritten in the same pass.
        if ($Instance) {
            if ($statusInstanceLabel -and -not $statusInstanceLabel.IsDisposed) {
                $statusInstanceLabel.Text = 'Instance: ' + [string]$Instance.Name
            }
            if ($statusGameLabel -and -not $statusGameLabel.IsDisposed -and -not [string]::IsNullOrWhiteSpace([string]$Instance.GameId)) {
                $statusGameLabel.Text = 'Game: ' + [string]$Instance.GameId
            }
        }
        else {
            if ($statusInstanceLabel -and -not $statusInstanceLabel.IsDisposed) {
                $statusInstanceLabel.Text = 'Instance: None'
            }
        }
    }.GetNewClosure()


    $script:UGSM_MainFormMachineStatusBusy = $false

    $machineStatusTimer = New-Object System.Windows.Forms.Timer
    $machineStatusTimer.Interval = 10000
    $machineStatusTimer.Add_Tick({
            if ($script:UGSM_MainFormMachineStatusBusy) { return }
            $script:UGSM_MainFormMachineStatusBusy = $true
            try {
                & $UpdateMachineStatusUI
                & $UpdateHealthWarningsUI
            }
            finally {
                $script:UGSM_MainFormMachineStatusBusy = $false
            }
        }.GetNewClosure())
    $machineStatusTimer.Start()


    if ($script:UGSM_EnableDevReload -and (Get-Command Restart-UGSMApplication -ErrorAction SilentlyContinue)) {
        $form.Add_KeyDown({
                param($sender, $e)

                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F12) {
                    $e.SuppressKeyPress = $true
                    Restart-UGSMApplication
                }
            }.GetNewClosure())
    }

    $form.Add_Shown({
            & $UpdateMachineStatusUI
            & $UpdateHealthWarningsUI
        }.GetNewClosure())
    $form.Add_FormClosed({
            try {
                if ($machineStatusTimer) {
                    $machineStatusTimer.Stop()
                    $machineStatusTimer.Dispose()
                }
            }
            catch {
            }
        }.GetNewClosure())


    $UpdateInstanceListUI = {
        $instanceList.Items.Clear()

        if ([string]::IsNullOrWhiteSpace([string]$AppState.SelectedGameId)) {
            if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $null
            }
            else {
                $AppState.SelectedInstance = $null
                $AppState.SelectedInstanceId = $null
            }

            & $UpdateSelectedInstanceContextUI $null
            & $UpdateStatusBarUI
            return
        }

        $selectedInstanceId = [string]$AppState.SelectedInstanceId
        $instances = @()
        if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
            try {
                $instances = @(Get-UGSMInstances -GameId $AppState.SelectedGameId)
            }
            catch {
                & $SetStatusResult ([string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
                $instances = @()
            }
        }

        foreach ($instance in $instances) {
            [void]$instanceList.Items.Add($instance)
        }

        $match = $null
        if (-not [string]::IsNullOrWhiteSpace($selectedInstanceId)) {
            $match = $instances | Where-Object { [string]$_.Id -eq $selectedInstanceId } | Select-Object -First 1
        }

        if (-not $match -and $instanceList.Items.Count -gt 0) {
            $match = $instanceList.Items[0]
        }

        if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
            $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $match
        }
        elseif ($match) {
            $AppState.SelectedInstance = $match
            $AppState.SelectedInstanceId = [string]$match.Id
        }
        else {
            $AppState.SelectedInstance = $null
            $AppState.SelectedInstanceId = $null
        }

        if ($match) {
            $instanceList.SelectedItem = $match
        }
        else {
            & $UpdateSelectedInstanceContextUI $null
            & $UpdateStatusBarUI
        }
    }.GetNewClosure()

    $RefreshInstancesPageUI = {
        Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('RefreshInstancesPageUI start. Current AppState selected=' + (Format-UGSMTraceInstance $AppState.SelectedInstance) + '; SelectedInstanceId=' + [string]$AppState.SelectedInstanceId)
        $refreshState = $null
        if (Get-Command Get-UGSMRefreshedInstancesPageData -ErrorAction SilentlyContinue) {
            $refreshState = Get-UGSMRefreshedInstancesPageData -AppState $AppState
        }

        Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Refresh state present=' + [string]([bool]$refreshState) + '; selected=' + (Format-UGSMTraceInstance $(if ($refreshState) { $refreshState.SelectedInstance } else { $null })))

        if ($refreshState -and $refreshState.PSObject.Properties['SelectedInstance']) {
            if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $refreshState.SelectedInstance
            }
            else {
                $AppState.SelectedInstance = $refreshState.SelectedInstance
                $AppState.SelectedInstanceId = if ($refreshState.SelectedInstance) { [string]$refreshState.SelectedInstance.Id } else { $null }
            }
        }

        Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message (
            'GetLiveInstancesPageControl type before invoke: ' +
            $(try { $v = Get-Variable -Name 'GetLiveInstancesPageControl' -ErrorAction SilentlyContinue; if ($v -and $v.Value) { $v.Value.GetType().FullName } else { '<null>' } } catch { '<unset>' })
        )

        $liveInstancesPageControl = & $ResolveLiveInstancesPageControl
        $instancesPageAvailable = ($liveInstancesPageControl -and -not $liveInstancesPageControl.IsDisposed)
        $instancesPageTagAvailable = [bool]($instancesPageAvailable -and $liveInstancesPageControl.Tag)
        Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Instances page control inspection. Exists=' + [string][bool]$liveInstancesPageControl + '; Available=' + [string]$instancesPageAvailable + '; IsDisposed=' + [string]$(if ($liveInstancesPageControl) { $liveInstancesPageControl.IsDisposed } else { $true }) + '; Visible=' + [string]$(if ($liveInstancesPageControl) { $liveInstancesPageControl.Visible } else { $false }) + '; TagAvailable=' + [string]$instancesPageTagAvailable + '; TagType=' + $(if ($instancesPageTagAvailable) { $liveInstancesPageControl.Tag.GetType().FullName } else { '<null>' }))

        if ($instancesPageTagAvailable) {
            $tagHasRenderState = Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'RenderState'
            $tagHasSetSelected = Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'SetSelectedInstance'
            $tagHasRefreshAll = Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'RefreshAll'
            $tagRenderStateIsScript = [bool]($tagHasRenderState -and $liveInstancesPageControl.Tag.RenderState -is [scriptblock])
            $tagSetSelectedIsScript = [bool]($tagHasSetSelected -and $liveInstancesPageControl.Tag.SetSelectedInstance -is [scriptblock])
            $tagRefreshAllIsScript = [bool]($tagHasRefreshAll -and $liveInstancesPageControl.Tag.RefreshAll -is [scriptblock])
            Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Instances page tag callbacks. HasRenderState=' + [string]$tagHasRenderState + '; RenderStateIsScript=' + [string]$tagRenderStateIsScript + '; HasSetSelectedInstance=' + [string]$tagHasSetSelected + '; SetSelectedInstanceIsScript=' + [string]$tagSetSelectedIsScript + '; HasRefreshAll=' + [string]$tagHasRefreshAll + '; RefreshAllIsScript=' + [string]$tagRefreshAllIsScript)

            try {
                if ($refreshState -and $tagRenderStateIsScript) {
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Invoking instancesPageControl.Tag.RenderState with selected=' + (Format-UGSMTraceInstance $refreshState.SelectedInstance))
                    & $liveInstancesPageControl.Tag.RenderState $refreshState
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'instancesPageControl.Tag.RenderState completed'
                }
                elseif ($tagSetSelectedIsScript) {
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Invoking instancesPageControl.Tag.SetSelectedInstance with ' + (Format-UGSMTraceInstance $AppState.SelectedInstance))
                    & $liveInstancesPageControl.Tag.SetSelectedInstance $AppState.SelectedInstance
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'instancesPageControl.Tag.SetSelectedInstance completed'
                }
                elseif ($tagRefreshAllIsScript) {
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'Invoking instancesPageControl.Tag.RefreshAll'
                    & $liveInstancesPageControl.Tag.RefreshAll
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'instancesPageControl.Tag.RefreshAll completed'
                }
                else {
                    Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'Instances page tag exists, but no callable refresh callback was found'
                }
            }
            catch {
                Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Instances page callback failed: ' + $_.Exception.Message)
                throw
            }
        }
        else {
            Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'Instances page control unavailable or tag missing; skipping page callback'
        }

        if ($UpdateSelectedInstanceContextUI -is [scriptblock]) {
            Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('Refreshing shell context using ' + (Format-UGSMTraceInstance $AppState.SelectedInstance))
            & $UpdateSelectedInstanceContextUI $AppState.SelectedInstance
        }

        if ($UpdateStatusBarUI -is [scriptblock]) {
            Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'Refreshing status bar UI'
            & $UpdateStatusBarUI
        }

        Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message ('RefreshInstancesPageUI end. AppState selected=' + (Format-UGSMTraceInstance $AppState.SelectedInstance))
    }

    $InvokeInstanceAddUI = {
        $profileCreated = $false
        $createdProfileName = ''
        if ([string]::IsNullOrWhiteSpace([string]$AppState.SelectedGameId)) {
            & $SetStatusResult 'Select a game before creating a profile.' $global:UGSM_ColorDangerSoft
            return
        }

        Add-Type -AssemblyName Microsoft.VisualBasic
        $profileName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a profile name for the selected game.', 'Create Profile', '')
        if ([string]::IsNullOrWhiteSpace($profileName)) {
            & $SetStatusResult 'Create profile canceled.'
            return
        }

        try {
            $meta = $null
            if (Get-Command Resolve-UGSMGameModuleMetadata -ErrorAction SilentlyContinue) {
                $meta = Resolve-UGSMGameModuleMetadata -GameId $AppState.SelectedGameId
            }

            $instanceId = ConvertTo-UGSMInstanceId -Name $profileName
            $ports = @{}
            if ($meta -and $meta.PSObject.Properties['PortSchema'] -and @($meta.PortSchema).Count -gt 0 -and (Get-Command New-UGSMInstancePortAssignments -ErrorAction SilentlyContinue)) {
                $ports = New-UGSMInstancePortAssignments -InstanceId $instanceId -GameId $AppState.SelectedGameId -PortSchema @($meta.PortSchema)
            }

            $installPath = ''
            if (Get-Command Get-UGSMGameInstallRoot -ErrorAction SilentlyContinue) {
                try { $installPath = [string](Get-UGSMGameInstallRoot -GameId $AppState.SelectedGameId) } catch { $installPath = '' }
            }

            Write-UGSMTrace -Component 'UI.CreateProfile' -Message 'Before New-UGSMInstance'
            $instance = New-UGSMInstance -Name $profileName -GameId $AppState.SelectedGameId -InstallPath $installPath -Ports $ports
            $profileCreated = $true
            $createdProfileName = [string]$instance.Name
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('After New-UGSMInstance: ' + [string]$instance.Name)

            $selectedInstance = $instance
            if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                $selectedInstance = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $instance
            }
            else {
                $AppState.SelectedInstance = $instance
                $AppState.SelectedInstanceId = $instance.Id
            }

            if ((Get-Command Get-UGSMInstance -ErrorAction SilentlyContinue) -and $selectedInstance -and -not [string]::IsNullOrWhiteSpace([string]$selectedInstance.Id)) {
                $selectedInstance = Get-UGSMInstance -Id ([string]$selectedInstance.Id)
                if ($selectedInstance -and (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue)) {
                    $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $selectedInstance
                }
            }

            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Assigned AppState.SelectedInstanceId=' + [string]$AppState.SelectedInstanceId)

            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('UpdateInstanceListUI type=' + $(if ($UpdateInstanceListUI) { $UpdateInstanceListUI.GetType().FullName } else { '<null>' }))
            & $UpdateInstanceListUI
            if ($selectedInstance -and $instanceList) {
                $matchedListInstance = $null
                foreach ($item in $instanceList.Items) {
                    if ($item -and [string]$item.Id -eq [string]$selectedInstance.Id) {
                        $matchedListInstance = $item
                        break
                    }
                }
                if ($matchedListInstance) {
                    $instanceList.SelectedItem = $matchedListInstance
                    if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                        $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $matchedListInstance
                    }
                    else {
                        $AppState.SelectedInstance = $matchedListInstance
                        $AppState.SelectedInstanceId = [string]$matchedListInstance.Id
                    }
                    if ($UpdateSelectedInstanceContextUI -is [scriptblock]) {
                        & $UpdateSelectedInstanceContextUI $matchedListInstance
                    }
                    if ($UpdateStatusBarUI -is [scriptblock]) {
                        & $UpdateStatusBarUI
                    }
                }
            }
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message 'UpdateInstanceListUI completed'

            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('RefreshInstancesPageUI type=' + $(if ($RefreshInstancesPageUI) { $RefreshInstancesPageUI.GetType().FullName } else { '<null>' }))
            & $RefreshInstancesPageUI
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message 'RefreshInstancesPageUI completed'

            $liveInstancesPageControl = $null
            $liveInstancesPageControl = & $ResolveLiveInstancesPageControl

            if ($liveInstancesPageControl -and -not $liveInstancesPageControl.IsDisposed -and $liveInstancesPageControl.Tag) {
                if ($liveInstancesPageControl.Tag.PSObject.Properties['RefreshAll'] -and $liveInstancesPageControl.Tag.RefreshAll -is [scriptblock]) {
                    & $liveInstancesPageControl.Tag.RefreshAll
                }
                if ($selectedInstance -and (Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'SetSelectedInstance') -and $liveInstancesPageControl.Tag.SetSelectedInstance -is [scriptblock]) {
                    & $liveInstancesPageControl.Tag.SetSelectedInstance $selectedInstance
                }
            }

            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('SetStatusResult type=' + $(if ($SetStatusResult) { $SetStatusResult.GetType().FullName } else { '<null>' }))
            & $SetStatusResult ("Profile created: {0}" -f $instance.Name) $global:UGSM_ColorHealthy
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message 'SetStatusResult completed'
        }
        catch {
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Message: ' + $_.Exception.Message)
            Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Stack: ' + $_.ScriptStackTrace)

            if ($_.InvocationInfo) {
                Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Line: ' + [string]$_.InvocationInfo.Line)
                Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Position: ' + [string]$_.InvocationInfo.PositionMessage)
            }

            if ($profileCreated) {
                Write-UGSMTrace -Component 'UI.CreateProfile' -Message ('Profile was created, but post-create UI refresh failed. Suppressing failure popup. Profile=' + [string]$createdProfileName)
                if ($SetStatusResult -is [scriptblock]) {
                    & $SetStatusResult ("Profile created: {0}" -f $createdProfileName) $global:UGSM_ColorHealthy
                }
                return
            }

            if ($SetStatusResult -is [scriptblock]) {
                & $SetStatusResult ([string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
            }
            [System.Windows.Forms.MessageBox]::Show(
                [string]$_.Exception.Message,
                'Create Profile Failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure()

    $InvokeInstanceEditUI = {
        $instance = $AppState.SelectedInstance
        if (-not $instance) {
            & $SetStatusResult 'Select a profile to edit.' $global:UGSM_ColorDangerSoft
            return
        }

        Add-Type -AssemblyName Microsoft.VisualBasic
        $newName = [Microsoft.VisualBasic.Interaction]::InputBox('Rename the selected profile.', 'Edit Profile', [string]$instance.Name)
        if ([string]::IsNullOrWhiteSpace($newName)) {
            & $SetStatusResult 'Edit profile canceled.'
            return
        }

        try {
            $instance.Name = $newName
            $saved = Save-UGSMInstance -Instance $instance
            $AppState.SelectedInstance = $saved
            $AppState.SelectedInstanceId = $saved.Id
            & $UpdateInstanceListUI
            & $RefreshInstancesPageUI
            & $SetStatusResult ("Profile updated: {0}" -f $saved.Name) $global:UGSM_ColorHealthy
        }
        catch {
            & $SetStatusResult ([string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
            [System.Windows.Forms.MessageBox]::Show([string]$_.Exception.Message, 'Edit Profile Failed', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }.GetNewClosure()

    $InvokeInstanceRemoveUI = {
        $instance = $AppState.SelectedInstance
        if (-not $instance) {
            & $SetStatusResult 'Select a profile to remove.' $global:UGSM_ColorDangerSoft
            return
        }

        $answer = [System.Windows.Forms.MessageBox]::Show(
            ("Delete profile '{0}'? Shared game binaries will remain installed." -f [string]$instance.Name),
            'Remove Profile',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            & $SetStatusResult 'Remove profile canceled.'
            return
        }

        try {
            if (Get-Command Remove-UGSMProfileAndRefresh -ErrorAction SilentlyContinue) {
                $result = Remove-UGSMProfileAndRefresh -AppState $AppState -Id $instance.Id
            }
            else {
                throw 'Remove-UGSMProfileAndRefresh is not available.'
            }

            & $UpdateInstanceListUI
            & $RefreshInstancesPageUI
            & $SetStatusResult ("Profile removed: {0}" -f [string]$instance.Name) $global:UGSM_ColorHealthy
        }
        catch {
            & $SetStatusResult ([string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
            [System.Windows.Forms.MessageBox]::Show(
                [string]$_.Exception.Message,
                'Remove Profile Failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure()

    $InvokeSelectedGameToolbarAction = {
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Install', 'Update', 'Verify')]
            [string]$Action
        )

        if ([string]::IsNullOrWhiteSpace([string]$AppState.SelectedGameId)) {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                'Select a game first.',
                'UGSM',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        try {
            $result = $null
            if (Get-Command Invoke-UGSMGameBinaryAction -ErrorAction SilentlyContinue) {
                $result = Invoke-UGSMGameBinaryAction -Action $Action -GameId $AppState.SelectedGameId
            }
            else {
                switch ($Action) {
                    'Install' { $actionResult = Ensure-UGSMGameServerInstalled -GameId $AppState.SelectedGameId }
                    'Update'  { $actionResult = Update-UGSMGameServer -GameId $AppState.SelectedGameId }
                    'Verify'  { $actionResult = Verify-UGSMGameServer -GameId $AppState.SelectedGameId }
                }

                $result = [pscustomobject]@{
                    Action       = $Action
                    GameId       = $AppState.SelectedGameId
                    ActionResult = $actionResult
                    Message      = if ($actionResult -and $actionResult.PSObject.Properties['Message']) { [string]$actionResult.Message } else { '' }
                }
            }

            if ($RefreshGamesPageUI -is [scriptblock]) {
                & $RefreshGamesPageUI
            }

            $message = if ($result -and $result.PSObject.Properties['Message'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Message)) {
                [string]$result.Message
            }
            else {
                "{0} action completed for {1}." -f $Action, [string]$AppState.SelectedGameId
            }

            & $SetStatusResult $message $global:UGSM_ColorHealthy
        }
        catch {
            & $SetStatusResult ([string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                [string]$_.Exception.Message,
                ("{0} Failed" -f $Action),
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure()

    $InvokeAppUpdateCheckUI = {
        try {
            Write-UGSMLog -Level 'INFO' -Category 'Updater' -Message 'Manual app update check requested from main toolbar.'
            & $SetStatusResult 'Checking for UGSM updates...'

            if (-not (Get-Command Test-UGSMAppUpdate -ErrorAction SilentlyContinue)) {
                throw 'Test-UGSMAppUpdate is not available. Check UGSM_Service_Updater.ps1 load order.'
            }

            $result = Test-UGSMAppUpdate

            if (-not $result.Configured) {
                Write-UGSMLog -Level 'WARN' -Category 'Updater' -Message 'Manual update check skipped because no manifest URL is configured.'
                & $SetStatusResult 'Update check is not configured yet.' $global:UGSM_ColorCaution
                [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    (Format-UGSMDialogMessage ('The app update checker is installed, but no update manifest URL is configured yet.' + [Environment]::NewLine + [Environment]::NewLine + 'Set $script:UGSM_UpdateManifestUrl in the build/config once the release location is ready.')),
                    'UGSM Updates',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }

            if ($result.UpdateAvailable) {
                $notesText = ''
                if ($result.ReleaseNotes -and @($result.ReleaseNotes).Count -gt 0) {
                    $nl = [Environment]::NewLine
                    $notesText = ($nl + $nl + 'Release notes:' + $nl + '- ') + ((@($result.ReleaseNotes) | Select-Object -First 5) -join ($nl + '- '))
                }

                $nl = [Environment]::NewLine
                $message = 'A newer UGSM version is available.' + $nl + $nl + 'Current: ' + [string]$result.CurrentVersion + $nl + 'Latest:  ' + [string]$result.LatestVersion + $notesText + $nl + $nl + 'Download and install now?' + $nl + $nl + 'UGSM will close, replace the EXE, and restart.'
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    (Format-UGSMDialogMessage $message),
                    'UGSM Update Available',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )

                if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                    if (Get-Command Install-UGSMAppUpdate -ErrorAction SilentlyContinue) {
                        $installResult = Install-UGSMAppUpdate -UpdateResult $result
                        & $SetStatusResult ('Installing UGSM update v{0}. Closing app...' -f [string]$result.LatestVersion) $global:UGSM_ColorHealthy
                        [System.Windows.Forms.MessageBox]::Show(
                            $form,
                            (Format-UGSMDialogMessage ('The update was downloaded and verified.' + [Environment]::NewLine + [Environment]::NewLine + 'UGSM will close now, apply the update, and restart.')),
                            'UGSM Update Ready',
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        ) | Out-Null
                        $form.Close()
                    }
                    else {
                        Open-UGSMUpdateDownload -UpdateResult $result | Out-Null
                        & $SetStatusResult ('Opened update download for v{0}' -f [string]$result.LatestVersion) $global:UGSM_ColorHealthy
                    }
                }
                else {
                    & $SetStatusResult ('Update available: v{0}' -f [string]$result.LatestVersion) $global:UGSM_ColorCaution
                }
                return
            }

            & $SetStatusResult ('UGSM is up to date: v{0}' -f [string]$result.CurrentVersion) $global:UGSM_ColorHealthy
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                (Format-UGSMDialogMessage (('UGSM is up to date.' + [Environment]::NewLine + [Environment]::NewLine + 'Current version: v{0}') -f [string]$result.CurrentVersion)),
                'UGSM Updates',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            Write-UGSMLog -Level 'ERROR' -Category 'Updater' -Message 'Manual app update check failed.' -Exception $_.Exception
            & $SetStatusResult ('Update check failed: ' + [string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                (Format-UGSMDialogMessage $_.Exception.Message),
                'UGSM Update Check Failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure()

    $gameList.Add_SelectedIndexChanged({
            if ($null -eq $gameList.SelectedItem) {
                return
            }

            $selectedGameName = [string]$gameList.SelectedItem
            $AppState.SelectedGameId = $AppState.GameDisplayMap[$selectedGameName]

            & $SetStatusResult ("Selected game: {0}" -f [string]$AppState.SelectedGameId)
            & $UpdateInstanceListUI
            & $RefreshInstancesPageUI
        }.GetNewClosure())

    $instanceList.Add_SelectedIndexChanged({
            if ($null -eq $instanceList.SelectedItem) {
                if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                    $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $null
                }
                else {
                    $AppState.SelectedInstance = $null
                    $AppState.SelectedInstanceId = $null
                }

                $liveInstancesPageControl = $null

                Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message (
                    'GetLiveInstancesPageControl type before invoke: ' +
                    $(try { $v = Get-Variable -Name 'GetLiveInstancesPageControl' -ErrorAction SilentlyContinue; if ($v -and $v.Value) { $v.Value.GetType().FullName } else { '<null>' } } catch { '<unset>' })
                )

                $liveInstancesPageControl = & $ResolveLiveInstancesPageControl
                if ($liveInstancesPageControl -and -not $liveInstancesPageControl.IsDisposed -and (Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'SetSelectedInstance')) {
                    & $liveInstancesPageControl.Tag.SetSelectedInstance $null
                }
                else {
                    & $RefreshInstancesPageUI
                }

                if ($UpdateSelectedInstanceContextUI -is [scriptblock]) {
                    & $UpdateSelectedInstanceContextUI $null
                }

                if ($UpdateStatusBarUI -is [scriptblock]) {
                    & $UpdateStatusBarUI
                }
                return
            }

            $instance = $instanceList.SelectedItem
            Write-UGSMTrace -Component 'UI.MainForm.Events' -Message ('instanceList SelectedIndexChanged fired. SelectedItem=' + (Format-UGSMTraceInstance $instance) + '; Visible=' + [string]$instanceList.Visible + '; Focused=' + [string]$instanceList.Focused)

            if (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue) {
                $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $instance
            }
            elseif ($instance -and $instance.PSObject.Properties['Id']) {
                $AppState.SelectedInstance = $instance
                $AppState.SelectedInstanceId = [string]$instance.Id
            }
            else {
                $AppState.SelectedInstance = $null
                $AppState.SelectedInstanceId = $null
            }

            $liveInstancesPageControl = $null

            Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message (
                'GetLiveInstancesPageControl type before invoke: ' +
                $(try { $v = Get-Variable -Name 'GetLiveInstancesPageControl' -ErrorAction SilentlyContinue; if ($v -and $v.Value) { $v.Value.GetType().FullName } else { '<null>' } } catch { '<unset>' })
            )

            $liveInstancesPageControl = & $ResolveLiveInstancesPageControl
            if (-not $liveInstancesPageControl) {
                Write-UGSMTrace -Component 'UI.MainForm.RefreshInstancesPage' -Message 'Live Instances page control was not available during instance selection.'
            }
            if ($liveInstancesPageControl -and -not $liveInstancesPageControl.IsDisposed -and (Test-UGSMTagCallback -Tag $liveInstancesPageControl.Tag -Name 'SetSelectedInstance') -and $liveInstancesPageControl.Tag.SetSelectedInstance -is [scriptblock]) {
                & $liveInstancesPageControl.Tag.SetSelectedInstance $AppState.SelectedInstance
            }
            else {
                & $RefreshInstancesPageUI
            }

            if ($UpdateSelectedInstanceContextUI -is [scriptblock]) {
                & $UpdateSelectedInstanceContextUI $AppState.SelectedInstance
            }

            if ($UpdateStatusBarUI -is [scriptblock]) {
                & $UpdateStatusBarUI
            }

        }.GetNewClosure())

    $btnInstanceAdd.Add_Click({ & $InvokeInstanceAddUI }.GetNewClosure())
    $btnInstanceEdit.Add_Click({ & $InvokeInstanceEditUI }.GetNewClosure())
    $btnInstanceRemove.Add_Click({ & $InvokeInstanceRemoveUI }.GetNewClosure())


    $gameList.Items.Clear()
    $AppState.GameDisplayMap = @{}

    $availableGames = if (Get-Command Get-UGSMGameCatalog -ErrorAction SilentlyContinue) {
        @(Get-UGSMGameCatalog)
    }
    else {
        @()
    }

    foreach ($game in $availableGames) {
        if ([string]::IsNullOrWhiteSpace([string]$game.Name) -or [string]::IsNullOrWhiteSpace([string]$game.Id)) {
            continue
        }

        $AppState.GameDisplayMap[[string]$game.Name] = [string]$game.Id
        [void]$gameList.Items.Add([string]$game.Name)
    }

    if ($gameList.Items.Count -gt 0) {
        $gameList.SelectedIndex = 0
    }

    $ResolveCurrentInstanceSelection = {
        $resolved = $null

        if ($AppState.SelectedInstance) {
            $resolved = $AppState.SelectedInstance
        }
        elseif ($instanceList.SelectedItem) {
            $resolved = $instanceList.SelectedItem
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$AppState.SelectedInstanceId)) {
            if (Get-Command Get-UGSMInstance -ErrorAction SilentlyContinue) {
                try {
                    $resolved = Get-UGSMInstance -Id ([string]$AppState.SelectedInstanceId)
                }
                catch {
                    $resolved = $null
                }
            }

            if (-not $resolved -and (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue)) {
                try {
                    $resolved = @(Get-UGSMInstances -GameId $AppState.SelectedGameId | Where-Object { [string]$_.Id -eq [string]$AppState.SelectedInstanceId } | Select-Object -First 1)
                }
                catch {
                    $resolved = $null
                }
            }
        }

        if ($resolved -and (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue)) {
            $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $resolved
        }
        elseif ($resolved) {
            $AppState.SelectedInstance = $resolved
            $AppState.SelectedInstanceId = [string]$resolved.Id
        }

        return $resolved
    }.GetNewClosure()

    $HandleStartInstance = {
        $selectedInstance = & $ResolveCurrentInstanceSelection
        if (-not $selectedInstance) {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                'Select an instance first.',
                'UGSM',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        try {
            $result = if (Get-Command Invoke-UGSMInstanceAction -ErrorAction SilentlyContinue) {
                Invoke-UGSMInstanceAction -Action Start -AppState $AppState -Id $selectedInstance.Id
            }
            else {
                [pscustomobject]@{ UpdatedInstance = (Start-UGSMInstance -Id $selectedInstance.Id); SelectedInstance = $null }
            }

            if ($result -and $result.SelectedInstance -and (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue)) {
                $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $result.SelectedInstance
            }
            elseif ($result -and $result.UpdatedInstance) {
                $AppState.SelectedInstance = $result.UpdatedInstance
                $AppState.SelectedInstanceId = [string]$result.UpdatedInstance.Id
            }

            & $UpdateInstanceListUI
            & $RefreshInstancesPageUI
            & $SetStatusResult ("Started state for '{0}' saved" -f [string]$AppState.SelectedInstance.Name) $global:UGSM_ColorHealthy
        }
        catch {
            & $SetStatusResult ("Start failed - {0}" -f [string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
        }
    }.GetNewClosure()

    $HandleStopInstance = {
        $selectedInstance = & $ResolveCurrentInstanceSelection
        if (-not $selectedInstance) {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                'Select an instance first.',
                'UGSM',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        try {
            $result = if (Get-Command Invoke-UGSMInstanceAction -ErrorAction SilentlyContinue) {
                Invoke-UGSMInstanceAction -Action Stop -AppState $AppState -Id $selectedInstance.Id
            }
            else {
                [pscustomobject]@{ UpdatedInstance = (Stop-UGSMInstance -Id $selectedInstance.Id); SelectedInstance = $null }
            }

            if ($result -and $result.SelectedInstance -and (Get-Command Set-UGSMSelectedInstanceState -ErrorAction SilentlyContinue)) {
                $null = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $result.SelectedInstance
            }
            elseif ($result -and $result.UpdatedInstance) {
                $AppState.SelectedInstance = $result.UpdatedInstance
                $AppState.SelectedInstanceId = [string]$result.UpdatedInstance.Id
            }

            & $UpdateInstanceListUI
            & $RefreshInstancesPageUI
            & $SetStatusResult ("Stopped state for '{0}' saved" -f [string]$AppState.SelectedInstance.Name) $global:UGSM_ColorHealthy
        }
        catch {
            & $SetStatusResult ("Stop failed - {0}" -f [string]$_.Exception.Message) $global:UGSM_ColorDangerSoft
        }
    }.GetNewClosure()

    if ($toolbarButtons['Install']) {
        $toolbarButtons['Install'].Add_Click({
                & $InvokeSelectedGameToolbarAction 'Install'
            }.GetNewClosure())
    }

    if ($toolbarButtons['Update']) {
        $toolbarButtons['Update'].Add_Click({
                & $InvokeSelectedGameToolbarAction 'Update'
            }.GetNewClosure())
    }

    if ($toolbarButtons['Verify']) {
        $toolbarButtons['Verify'].Add_Click({
                & $InvokeSelectedGameToolbarAction 'Verify'
            }.GetNewClosure())
    }

    if ($toolbarButtons['App Update']) {
        $toolbarButtons['App Update'].Add_Click({
                & $InvokeAppUpdateCheckUI
            }.GetNewClosure())
    }

    if ($toolbarButtons['Start']) {
        $toolbarButtons['Start'].Add_Click({
                & $HandleStartInstance
            }.GetNewClosure())
    }

    if ($toolbarButtons['Stop']) {
        $toolbarButtons['Stop'].Add_Click({
                & $HandleStopInstance
            }.GetNewClosure())
    }

    if ($quickStartButton) {
        $quickStartButton.Add_Click({
                & $HandleStartInstance
            }.GetNewClosure())
    }

    if ($quickStopButton) {
        $quickStopButton.Add_Click({
                & $HandleStopInstance
            }.GetNewClosure())
    }


# =========================================================
# End UI Update Logic
# =========================================================

# Status bar
    

    if ($navButtons['Home']) {
        $navButtons['Home'].Add_Click({ & $showPage 'Home' }.GetNewClosure())
    }
    if ($navButtons['Games']) {
        $navButtons['Games'].Add_Click({ & $showPage 'Games' }.GetNewClosure())
    }
    if ($navButtons['Instances']) {
        $navButtons['Instances'].Add_Click({ & $showPage 'Instances' }.GetNewClosure())
    }
    if ($navButtons['Analytics']) {
        $navButtons['Analytics'].Add_Click({ & $showPage 'Analytics' }.GetNewClosure())
    }
    if ($navButtons['Tasks']) {
        $navButtons['Tasks'].Add_Click({ & $showPage 'Tasks' }.GetNewClosure())
    }
    if ($navButtons['About']) {
        $navButtons['About'].Add_Click({ & $showPage 'About' }.GetNewClosure())
    }

    if ($settingsNavButton) {
        $settingsNavButton.Add_Click({
                if (-not (Get-Command New-UGSMSettingsForm -ErrorAction SilentlyContinue)) {
                    [System.Windows.Forms.MessageBox]::Show(
                        $form,
                        'New-UGSMSettingsForm was not loaded.',
                        'UGSM Settings',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    ) | Out-Null
                    return
                }

                $settingsForm = New-UGSMSettingsForm -Owner $form
                try {
                    if ($settingsForm.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                        $savedSettings = $settingsForm.Tag
                        if ($savedSettings) {
                            $statusPathText = [string]$savedSettings.ProfileBaseRoot
                            if ([string]::IsNullOrWhiteSpace($statusPathText)) {
                                $statusPathText = 'Global settings saved'
                            }
                            $statusResultLabel.Text = 'Last Result: Settings saved'
                            $statusInstanceLabel.Text = "Instance Root: $statusPathText"
                            if ($null -ne $refreshDiskDashboard -and $refreshDiskDashboard -is [scriptblock]) {
                                & $refreshDiskDashboard
                            }
                            if (-not $centerCanvas.Visible) {
                                & $showPage 'Home'
                            }
                        }
                    }
                }
                finally {
                    if ($settingsForm) {
                        $settingsForm.Dispose()
                    }
                }
            }.GetNewClosure())
    }


    $form.Add_Shown({
            & $showPage 'Home'

            $startupUpdateCheckEnabled = $false
            $startupFlag = Get-Variable -Name 'UGSM_CheckUpdatesOnStartup' -Scope Script -ErrorAction SilentlyContinue
            if ($startupFlag) {
                $startupUpdateCheckEnabled = [bool]$startupFlag.Value
            }

            if ($startupUpdateCheckEnabled -and (Get-Command Test-UGSMAppUpdate -ErrorAction SilentlyContinue)) {
                $updateTimer = New-Object System.Windows.Forms.Timer
                $updateTimer.Interval = 4000
                $updateTimer.Add_Tick({
                        $updateTimer.Stop()
                        try {
                            Write-UGSMLog -Level 'INFO' -Category 'Updater' -Message 'Startup app update check started.'
                            $startupResult = Test-UGSMAppUpdate
                            if ($startupResult.UpdateAvailable) {
                                Write-UGSMLog -Level 'INFO' -Category 'Updater' -Message ('Startup update check found v{0}.' -f [string]$startupResult.LatestVersion)
                                & $SetStatusResult ('Update available: v{0}' -f [string]$startupResult.LatestVersion) $global:UGSM_ColorCaution
                            }
                            elseif ($startupResult.Configured) {
                                Write-UGSMLog -Level 'INFO' -Category 'Updater' -Message 'Startup update check found no update.'
                            }
                        }
                        catch {
                            Write-UGSMLog -Level 'WARN' -Category 'Updater' -Message 'Startup update check failed.' -Exception $_.Exception
                        }
                        finally {
                            $updateTimer.Dispose()
                        }
                    }.GetNewClosure())
                $updateTimer.Start()
            }

            if ($chartRegion -and -not $chartRegion.IsDisposed) {
                & $drawChartGrid $chartRegion
                & $drawChartBars $chartRegion
            }
        }.GetNewClosure())

    $form.WindowState = 'Maximized' 
    return $form
}
