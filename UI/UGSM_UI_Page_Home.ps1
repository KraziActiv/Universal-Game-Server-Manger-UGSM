# Home Page

function Write-UGSMHomeUILog {
    [CmdletBinding()]
    param(
        [string]$Level = 'INFO',
        [string]$Message,
        [System.Exception]$Exception
    )

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            if ($Exception) {
                Write-UGSMLog -Level $Level -Category 'HomeUI' -Message $Message -Exception $Exception
            }
            else {
                Write-UGSMLog -Level $Level -Category 'HomeUI' -Message $Message
            }
        }
    }
    catch { }
}


function New-UGSMHomePage {
    [CmdletBinding()]
    param(
        [hashtable]$Theme,
        [object]$AppState
    )

    $pageCreateWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMHomeUILog -Level 'INFO' -Message 'Home page creation started.'

    if (-not $Theme) {
        $Theme = @{}
    }

    $Theme = @{
        MainBg       = if ($Theme.ContainsKey('MainBg') -and $null -ne $Theme.MainBg) { $Theme.MainBg } elseif ($Theme.ContainsKey('WindowBg') -and $null -ne $Theme.WindowBg) { $Theme.WindowBg } else { $global:UGSM_ColorBackground }
        CardBg       = if ($Theme.ContainsKey('CardBg') -and $null -ne $Theme.CardBg) { $Theme.CardBg } elseif ($Theme.ContainsKey('Surface') -and $null -ne $Theme.Surface) { $Theme.Surface } else { $global:UGSM_ColorPanelBackground }
        CardAltBg    = if ($Theme.ContainsKey('CardAltBg') -and $null -ne $Theme.CardAltBg) { $Theme.CardAltBg } elseif ($Theme.ContainsKey('SurfaceAlt') -and $null -ne $Theme.SurfaceAlt) { $Theme.SurfaceAlt } else { $global:UGSM_ColorSurfaceAlt }
        Border       = if ($Theme.ContainsKey('Border') -and $null -ne $Theme.Border) { $Theme.Border } else { $global:UGSM_ColorBorder }
        Text         = if ($Theme.ContainsKey('Text') -and $null -ne $Theme.Text) { $Theme.Text } else { $global:UGSM_ColorText }
        Muted        = if ($Theme.ContainsKey('Muted') -and $null -ne $Theme.Muted) { $Theme.Muted } else { $global:UGSM_ColorMutedText }
        Accent       = if ($Theme.ContainsKey('Accent') -and $null -ne $Theme.Accent) { $Theme.Accent } else { $global:UGSM_ColorSuccess }
        AccentBlue   = if ($Theme.ContainsKey('AccentBlue') -and $null -ne $Theme.AccentBlue) { $Theme.AccentBlue } else { $global:UGSM_ColorPrimary }
        AccentYellow = if ($Theme.ContainsKey('AccentYellow') -and $null -ne $Theme.AccentYellow) { $Theme.AccentYellow } else { $global:UGSM_ColorCaution }
    }

    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'
    $page.BackColor = $Theme.MainBg
    $page.AutoScroll = $true

    $titleLabel = New-UGSMLabel -Text 'Home' -X 24 -Y 20 -Width 260 -Height 28 -Color $Theme.Text -FontSize 18 -Bold
    $subLabel = New-UGSMLabel -Text 'System overview and running servers' -X 24 -Y 50 -Width 420 -Height 20 -Color $Theme.Muted -FontSize 9
    [void]$page.Controls.Add($titleLabel)
    [void]$page.Controls.Add($subLabel)

    $topCardPanels = @()
    $topCardTitleLabels = @()
    $topCardValueLabels = @()
    $topCardMetaLabels = @()

    for ($i = 0; $i -lt 4; $i++) {
        $panel = New-UGSMPanel -X 0 -Y 0 -Width 250 -Height 96 -BackColor $Theme.CardBg
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

        $labelTitle = New-UGSMLabel -Text '' -X 14 -Y 12 -Width 200 -Height 18 -Color $Theme.Muted -FontSize 8.5
        $labelValue = New-UGSMLabel -Text '' -X 14 -Y 34 -Width 220 -Height 28 -Color $Theme.Text -FontSize 15 -Bold
        $labelMeta = New-UGSMLabel -Text '' -X 14 -Y 66 -Width 220 -Height 18 -Color $Theme.Muted -FontSize 8

        [void]$panel.Controls.Add($labelTitle)
        [void]$panel.Controls.Add($labelValue)
        [void]$panel.Controls.Add($labelMeta)
        [void]$page.Controls.Add($panel)

        $topCardPanels += $panel
        $topCardTitleLabels += $labelTitle
        $topCardValueLabels += $labelValue
        $topCardMetaLabels += $labelMeta
    }

    $serversHeader = New-UGSMLabel -Text 'Running Servers' -X 24 -Y 205 -Width 220 -Height 24 -Color $Theme.Text -FontSize 13 -Bold
    $serversSub = New-UGSMLabel -Text '' -X 24 -Y 228 -Width 460 -Height 18 -Color $Theme.Muted -FontSize 8.5
    [void]$page.Controls.Add($serversHeader)
    [void]$page.Controls.Add($serversSub)

    $serversHost = New-Object System.Windows.Forms.FlowLayoutPanel
    $serversHost.Location = New-Object System.Drawing.Point(24, 256)
    $serversHost.Size = New-Object System.Drawing.Size(900, 10)
    $serversHost.AutoSize = $true
    $serversHost.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $serversHost.WrapContents = $true
    $serversHost.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $serversHost.Margin = New-Object System.Windows.Forms.Padding(0)
    $serversHost.Padding = New-Object System.Windows.Forms.Padding(0)
    $serversHost.BackColor = $Theme.MainBg
    $serversHost.AutoScroll = $false
    [void]$page.Controls.Add($serversHost)

    $storagePanel = New-UGSMPanel -X 24 -Y 0 -Width 420 -Height 140 -BackColor $Theme.CardBg
    $storagePanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $storageTitleLabel = New-UGSMLabel -Text 'Storage Summary' -X 14 -Y 12 -Width 160 -Height 22 -Color $Theme.Text -FontSize 12 -Bold
    $storageSteamLabel = New-UGSMLabel -Text '' -X 14 -Y 42 -Width 380 -Height 18 -Color $Theme.Muted -FontSize 8.5
    $storageProfilesLabel = New-UGSMLabel -Text '' -X 14 -Y 68 -Width 380 -Height 18 -Color $Theme.Muted -FontSize 8.5
    $storageBackupsLabel = New-UGSMLabel -Text '' -X 14 -Y 94 -Width 380 -Height 18 -Color $Theme.Muted -FontSize 8.5
    [void]$storagePanel.Controls.Add($storageTitleLabel)
    [void]$storagePanel.Controls.Add($storageSteamLabel)
    [void]$storagePanel.Controls.Add($storageProfilesLabel)
    [void]$storagePanel.Controls.Add($storageBackupsLabel)
    [void]$page.Controls.Add($storagePanel)

    $activityPanel = New-UGSMPanel -X 24 -Y 0 -Width 320 -Height 140 -BackColor $Theme.CardBg
    $activityPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $activityTitleLabel = New-UGSMLabel -Text 'Recent Activity' -X 14 -Y 12 -Width 140 -Height 22 -Color $Theme.Text -FontSize 12 -Bold
    [void]$activityPanel.Controls.Add($activityTitleLabel)
    [void]$page.Controls.Add($activityPanel)

    $warningPanel = New-UGSMPanel -X 24 -Y 0 -Width 300 -Height 140 -BackColor $Theme.CardBg
    $warningPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $warningTitleLabel = New-UGSMLabel -Text 'Warnings' -X 14 -Y 12 -Width 120 -Height 22 -Color $Theme.Text -FontSize 12 -Bold
    [void]$warningPanel.Controls.Add($warningTitleLabel)
    [void]$page.Controls.Add($warningPanel)

    $clearPanelBody = {
        param([System.Windows.Forms.Control]$Panel)
        while ($Panel.Controls.Count -gt 1) {
            $control = $Panel.Controls[$Panel.Controls.Count - 1]
            $Panel.Controls.RemoveAt($Panel.Controls.Count - 1)
            try { $control.Dispose() } catch {}
        }
    }.GetNewClosure()

    $clearServersHost = {
        foreach ($control in @($serversHost.Controls)) {
            try {
                if ($control -is [System.Windows.Forms.PictureBox] -and $control.Image) {
                    $control.Image.Dispose()
                    $control.Image = $null
                }
            }
            catch {}
            try {
                $serversHost.Controls.Remove($control)
                $control.Dispose()
            }
            catch {}
        }
    }.GetNewClosure()

    $getDefaultHomePageData = {
        [pscustomobject]@{
            Cards = @(
                [pscustomobject]@{ Title = 'CPU'; Value = 'N/A'; Meta = 'CPU monitor unavailable' }
                [pscustomobject]@{ Title = 'RAM'; Value = 'N/A'; Meta = 'Memory monitor unavailable' }
                [pscustomobject]@{ Title = 'Install Disk'; Value = 'Not configured'; Meta = 'SteamCMD / binaries' }
                [pscustomobject]@{ Title = 'Profile Store'; Value = 'Not configured'; Meta = 'Profiles location' }
            )
            RunningInstances = @()
            HomeSummary = [pscustomobject]@{ RunningCount = 0; StartingCount = 0; TotalCount = 0 }
            StorageSummary = [pscustomobject]@{ SteamCmdPath = 'Not configured'; ProfileBaseRoot = 'Not configured'; BackupRoot = 'Not configured' }
            RecentActivity = @('No recent activity')
            WarningItems   = @('No active warnings.')
        }
    }.GetNewClosure()

    $layoutHomePage = {
        $leftMargin = 24
        $rightMargin = 24
        $topCardsY = 88
        $sectionGap = 18
        $cardGap = 14
        $usableWidth = [Math]::Max(700, ($page.ClientSize.Width - $leftMargin - $rightMargin))

        $cardCount = $topCardPanels.Count
        if ($cardCount -gt 0) {
            $cardWidth = [Math]::Floor(($usableWidth - (($cardCount - 1) * $cardGap)) / $cardCount)
            if ($cardWidth -lt 180) { $cardWidth = 180 }
            if ($cardWidth -gt 320) { $cardWidth = 320 }

            $x = $leftMargin
            for ($i = 0; $i -lt $cardCount; $i++) {
                $panel = $topCardPanels[$i]
                $panel.Location = New-Object System.Drawing.Point($x, $topCardsY)
                $panel.Size = New-Object System.Drawing.Size($cardWidth, 96)
                $topCardTitleLabels[$i].Width = ($cardWidth - 28)
                $topCardValueLabels[$i].Width = ($cardWidth - 28)
                $topCardMetaLabels[$i].Width = ($cardWidth - 28)
                $x += ($cardWidth + $cardGap)
            }
        }

        $serversHeader.Location = New-Object System.Drawing.Point($leftMargin, 205)
        $serversSub.Location = New-Object System.Drawing.Point($leftMargin, 228)

        $serversHost.Location = New-Object System.Drawing.Point($leftMargin, 256)
        $serversHost.MaximumSize = New-Object System.Drawing.Size($usableWidth, 0)
        $serversHost.MinimumSize = New-Object System.Drawing.Size($usableWidth, 0)
        $serversHost.Width = $usableWidth

        $summaryY = $serversHost.Bottom + $sectionGap
        $bottomGap = 16

        if ($usableWidth -ge 950) {
            $storageWidth = 420
            $activityWidth = 260
            $warningWidth = 260
            $totalBottomWidth = $storageWidth + $activityWidth + $warningWidth + ($bottomGap * 2)

            if ($totalBottomWidth -le $usableWidth) {
                $storagePanel.Location = New-Object System.Drawing.Point($leftMargin, $summaryY)
                $storagePanel.Size = New-Object System.Drawing.Size($storageWidth, 140)

                $activityPanel.Location = New-Object System.Drawing.Point(($storagePanel.Right + $bottomGap), $summaryY)
                $activityPanel.Size = New-Object System.Drawing.Size($activityWidth, 140)

                $warningPanel.Location = New-Object System.Drawing.Point(($activityPanel.Right + $bottomGap), $summaryY)
                $warningPanel.Size = New-Object System.Drawing.Size($warningWidth, 140)
            }
            else {
                $storagePanel.Location = New-Object System.Drawing.Point($leftMargin, $summaryY)
                $storagePanel.Size = New-Object System.Drawing.Size($usableWidth, 140)

                $activityPanel.Location = New-Object System.Drawing.Point($leftMargin, ($storagePanel.Bottom + $bottomGap))
                $activityPanel.Size = New-Object System.Drawing.Size($usableWidth, 140)

                $warningPanel.Location = New-Object System.Drawing.Point($leftMargin, ($activityPanel.Bottom + $bottomGap))
                $warningPanel.Size = New-Object System.Drawing.Size($usableWidth, 140)
            }
        }
        else {
            $storagePanel.Location = New-Object System.Drawing.Point($leftMargin, $summaryY)
            $storagePanel.Size = New-Object System.Drawing.Size($usableWidth, 140)

            $activityPanel.Location = New-Object System.Drawing.Point($leftMargin, ($storagePanel.Bottom + $bottomGap))
            $activityPanel.Size = New-Object System.Drawing.Size($usableWidth, 140)

            $warningPanel.Location = New-Object System.Drawing.Point($leftMargin, ($activityPanel.Bottom + $bottomGap))
            $warningPanel.Size = New-Object System.Drawing.Size($usableWidth, 140)
        }
    }.GetNewClosure()

    $renderHomePageData = {
        param([object]$Data)

        if (-not $Data) {
            $Data = & $getDefaultHomePageData
        }

        $cards = @($Data.Cards)
        for ($i = 0; $i -lt $topCardPanels.Count; $i++) {
            $card = if ($i -lt $cards.Count) { $cards[$i] } else { [pscustomobject]@{ Title=''; Value=''; Meta='' } }
            $topCardTitleLabels[$i].Text = [string]$card.Title
            $topCardValueLabels[$i].Text = [string]$card.Value
            $topCardMetaLabels[$i].Text = [string]$card.Meta
        }

        $serversSub.Text = 'Running: {0}  •  Starting: {1}  •  Total Profiles: {2}' -f $Data.HomeSummary.RunningCount, $Data.HomeSummary.StartingCount, $Data.HomeSummary.TotalCount

        & $clearServersHost
        $runningInstances = @($Data.RunningInstances)
        if ($runningInstances.Count -eq 0) {
            $emptyPanel = New-UGSMPanel -X 0 -Y 0 -Width 560 -Height 150 -BackColor $Theme.CardAltBg
            $emptyPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $emptyPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 14)
            [void]$emptyPanel.Controls.Add((New-UGSMLabel -Text 'No servers are currently running' -X 18 -Y 22 -Width 300 -Height 24 -Color $Theme.Text -FontSize 13 -Bold))
            [void]$emptyPanel.Controls.Add((New-UGSMLabel -Text 'Use the Instances page to start a server profile.' -X 18 -Y 54 -Width 320 -Height 20 -Color $Theme.Muted -FontSize 9))
            [void]$emptyPanel.Controls.Add((New-UGSMLabel -Text 'This dashboard will list active servers here with game art and quick status.' -X 18 -Y 84 -Width 420 -Height 20 -Color $Theme.Muted -FontSize 8.5))
            [void]$serversHost.Controls.Add($emptyPanel)
        }
        else {
            foreach ($instance in $runningInstances) {
                $tile = New-UGSMPanel -X 0 -Y 0 -Width 250 -Height 168 -BackColor $Theme.CardAltBg
                $tile.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
                $tile.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 14)

                $imageAdded = $false
                if (-not [string]::IsNullOrWhiteSpace([string]$instance.ArtworkPath) -and (Test-Path -LiteralPath $instance.ArtworkPath)) {
                    try {
                        $imageBox = New-Object System.Windows.Forms.PictureBox
                        $imageBox.Location = New-Object System.Drawing.Point(12, 12)
                        $imageBox.Size = New-Object System.Drawing.Size(150, 80)
                        $imageBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
                        $imageBox.BackColor = $global:UGSM_ColorInputBackground
                        $imageBox.Image = [System.Drawing.Image]::FromFile($instance.ArtworkPath)
                        [void]$tile.Controls.Add($imageBox)
                        $imageAdded = $true
                    }
                    catch {
                        Write-UGSMHomeUILog -Level 'DEBUG' -Message ('Failed to load Home page artwork. Path={0}' -f $instance.ArtworkPath) -Exception $_.Exception
                        $imageAdded = $false
                    }
                }

                if (-not $imageAdded) {
                    $fallbackPanel = New-UGSMPanel -X 12 -Y 12 -Width 150 -Height 80 -BackColor $global:UGSM_ColorInputBackground
                    $fallbackLabel = New-UGSMLabel -Text ([string]$instance.GameName) -X 10 -Y 28 -Width 130 -Height 24 -Color $Theme.Text -FontSize 13 -Bold
                    [void]$fallbackPanel.Controls.Add($fallbackLabel)
                    [void]$tile.Controls.Add($fallbackPanel)
                }

                $nameLabel = New-UGSMLabel -Text ([string]$instance.Name) -X 170 -Y 12 -Width 70 -Height 40 -Color $Theme.Text -FontSize 9.5 -Bold
                $statusColor = if ([string]$instance.Status -eq 'Starting') { $Theme.AccentYellow } else { $Theme.Accent }
                $statusLabel = New-UGSMLabel -Text ([string]$instance.StatusText) -X 170 -Y 54 -Width 68 -Height 18 -Color $statusColor -FontSize 8.5
                $detailLabel = New-UGSMLabel -Text ([string]$instance.DetailText) -X 12 -Y 102 -Width 226 -Height 18 -Color $Theme.Text -FontSize 8.5
                $portsLabel = New-UGSMLabel -Text ([string]$instance.PortsText) -X 12 -Y 122 -Width 226 -Height 18 -Color $Theme.Muted -FontSize 7.5
                $viewButton = New-UGSMButton -Text 'View Later' -X 150 -Y 138 -Width 88 -Height 24 -BackColor $Theme.AccentBlue
                $viewButton.Left = $tile.Width - $viewButton.Width - 10
                $viewButton.Enabled = $false
                [void]$tile.Controls.Add($nameLabel)
                [void]$tile.Controls.Add($statusLabel)
                [void]$tile.Controls.Add($detailLabel)
                [void]$tile.Controls.Add($portsLabel)
                [void]$tile.Controls.Add($viewButton)
                [void]$serversHost.Controls.Add($tile)
            }
        }

        $storageSteamLabel.Text = 'SteamCMD: {0}' -f [string]$Data.StorageSummary.SteamCmdPath
        $storageProfilesLabel.Text = 'Profiles: {0}' -f [string]$Data.StorageSummary.ProfileBaseRoot
        $storageBackupsLabel.Text = 'Backups: {0}' -f [string]$Data.StorageSummary.BackupRoot

        & $clearPanelBody $activityPanel
        $activityY = 42
        foreach ($item in @($Data.RecentActivity)) {
            [void]$activityPanel.Controls.Add((New-UGSMLabel -Text ('• {0}' -f $item) -X 14 -Y $activityY -Width ([Math]::Max(220, $activityPanel.Width - 28)) -Height 18 -Color $Theme.Muted -FontSize 8.5))
            $activityY += 24
        }

        & $clearPanelBody $warningPanel
        $warningY = 42
        foreach ($item in @($Data.WarningItems)) {
            [void]$warningPanel.Controls.Add((New-UGSMLabel -Text ('• {0}' -f $item) -X 14 -Y $warningY -Width ([Math]::Max(220, $warningPanel.Width - 28)) -Height 18 -Color $Theme.Muted -FontSize 8.5))
            $warningY += 24
        }

        & $layoutHomePage
    }.GetNewClosure()

    $homeRefreshInProgress = $false
    $refreshHomePageData = {
        param([switch]$ForceRefresh)

        if ($homeRefreshInProgress) {
            return
        }

        if (-not $page.Visible -or -not $page.IsHandleCreated) {
            return
        }

        $homeRefreshInProgress = $true
        $refreshWatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $latestData = $null
            if (Get-Command Get-UGSMHomePageData -ErrorAction SilentlyContinue) {
                try {
                    $latestData = Get-UGSMHomePageData -AppState $AppState -ForceRefresh:$ForceRefresh
                }
                catch {
                    Write-UGSMHomeUILog -Level 'ERROR' -Message 'Failed to get Home page data.' -Exception $_.Exception
                    $latestData = $null
                }
            }
            & $renderHomePageData $latestData

            $refreshWatch.Stop()
            if ($refreshWatch.ElapsedMilliseconds -ge 750) {
                Write-UGSMHomeUILog -Level 'WARN' -Message ('Home page refresh was slow. DurationMs={0}; ForceRefresh={1}' -f $refreshWatch.ElapsedMilliseconds, [bool]$ForceRefresh)
            }
            elseif ($ForceRefresh) {
                Write-UGSMHomeUILog -Level 'DEBUG' -Message ('Home page initial refresh completed. DurationMs={0}' -f $refreshWatch.ElapsedMilliseconds)
            }
        }
        finally {
            $homeRefreshInProgress = $false
        }
    }.GetNewClosure()

    $page.Tag = [pscustomobject]@{
        RenderData  = $renderHomePageData
        RefreshData = $refreshHomePageData
        AppState    = $AppState
    }

    & $refreshHomePageData -ForceRefresh

    $homeRefreshTimer = New-Object System.Windows.Forms.Timer
    $homeRefreshTimer.Interval = 10000
    $homeRefreshTimer.Add_Tick({ if ($page.Visible -and $page.IsHandleCreated) { & $refreshHomePageData } }.GetNewClosure())
    $homeRefreshTimer.Start()

    $page.Add_Resize({
        & $layoutHomePage
    }.GetNewClosure())

    $page.Add_Disposed({
        try {
            if ($homeRefreshTimer) {
                $homeRefreshTimer.Stop()
                $homeRefreshTimer.Dispose()
            }
        }
        catch {
            Write-UGSMHomeUILog -Level 'WARN' -Message 'Home page disposal cleanup failed.' -Exception $_.Exception
        }
    }.GetNewClosure())

    $pageCreateWatch.Stop()
    if ($pageCreateWatch.ElapsedMilliseconds -ge 750) {
        Write-UGSMHomeUILog -Level 'WARN' -Message ('Home page creation was slow. DurationMs={0}' -f $pageCreateWatch.ElapsedMilliseconds)
    }
    else {
        Write-UGSMHomeUILog -Level 'INFO' -Message ('Home page creation finished. DurationMs={0}' -f $pageCreateWatch.ElapsedMilliseconds)
    }

    return $page
}
