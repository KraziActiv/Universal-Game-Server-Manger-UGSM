# Games Page

if (-not (Get-Variable -Name 'UGSM_GamesPageArtCache' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_GamesPageArtCache = @{}
}



function Get-UGSMGamesPageArtCache {
    [CmdletBinding()]
    param()

    try {
        $var = Get-Variable -Name 'UGSM_GamesPageArtCache' -Scope Script -ErrorAction SilentlyContinue
        if (-not $var -or $null -eq $var.Value) {
            $script:UGSM_GamesPageArtCache = @{}
        }
        elseif (-not ($var.Value -is [hashtable])) {
            $script:UGSM_GamesPageArtCache = @{}
        }
    }
    catch {
        $script:UGSM_GamesPageArtCache = @{}
    }

    return $script:UGSM_GamesPageArtCache
}

function New-UGSMGamesPage {
    [CmdletBinding()]
    param(
        [hashtable]$Theme
    )

    if (-not $Theme) {
    $Theme = @{
        WindowBg      = $global:UGSM_ColorBackground
        Surface       = $global:UGSM_ColorPanelBackground
        SurfaceAlt    = $global:UGSM_ColorSurfaceAlt
        Border        = $global:UGSM_ColorBorder
        Text          = $global:UGSM_ColorText
        Muted         = $global:UGSM_ColorMutedText
        Accent        = $global:UGSM_ColorSuccess
        AccentBlue    = $global:UGSM_ColorPrimary
        AccentWarning = $global:UGSM_ColorCaution
    }
}

    $writeGamesUILog = {
        param(
            [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
            [string]$Message,
            [object]$Exception = $null
        )

        if ([string]::IsNullOrWhiteSpace($Message)) { return }

        try {
            if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
                if ($Exception) {
                    Write-UGSMLog -Level $Level -Category 'GamesUI' -Message $Message -Exception $Exception
                }
                else {
                    Write-UGSMLog -Level $Level -Category 'GamesUI' -Message $Message
                }
            }
        }
        catch {
            # UI logging must never break the page.
        }
    }.GetNewClosure()

    & $writeGamesUILog -Level 'DEBUG' -Message 'Creating Games page.'

    $newEmptyPageData = {
        param([string]$StatusMessage = 'No games page data available.')

        [pscustomobject]@{
            TotalInstalled = 0
            Games          = @()
            StatusMessage  = $StatusMessage
            SteamCmd       = $null
        }
    }.GetNewClosure()

    $normalizePageData = {
        param([AllowNull()][object]$Data)

        if ($null -eq $Data) {
            return (& $newEmptyPageData)
        }

        return [pscustomobject]@{
            TotalInstalled = if ($Data.PSObject.Properties['TotalInstalled']) { [int]$Data.TotalInstalled } else { 0 }
            Games          = if ($Data.PSObject.Properties['Games']) { @($Data.Games) } else { @() }
            StatusMessage  = if ($Data.PSObject.Properties['StatusMessage']) { [string]$Data.StatusMessage } else { '' }
            SteamCmd       = if ($Data.PSObject.Properties['SteamCmd']) { $Data.SteamCmd } else { $null }
        }
    }.GetNewClosure()

    $getPageData = {
        if (-not (Get-Command Get-UGSMGamesPageData -ErrorAction SilentlyContinue)) {
            return (& $newEmptyPageData 'Games page loaded without service data.')
        }

        try {
            return (& $normalizePageData (Get-UGSMGamesPageData))
        }
        catch {
            & $writeGamesUILog -Level 'ERROR' -Message 'Failed to load Games page data.' -Exception $_.Exception
            return (& $newEmptyPageData $_.Exception.Message)
        }
    }.GetNewClosure()

    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'
    $page.BackColor = $Theme.WindowBg
    $page.Padding = New-Object System.Windows.Forms.Padding(0)

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.Margin = New-Object System.Windows.Forms.Padding(0)
    $root.Padding = New-Object System.Windows.Forms.Padding(12, 12, 12, 12)
    $root.BackColor = $Theme.WindowBg
    $root.ColumnCount = 1
    $root.RowCount = 3
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$page.Controls.Add($root)

    $header = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 64 -BackColor $global:UGSM_ColorSuccessSurface -BorderColor $global:UGSM_ColorSuccessBorder
    $header.Dock = 'Fill'
    $header.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$root.Controls.Add($header, 0, 0)

    [void]$header.Controls.Add((New-UGSMLabel -Text 'Games' -X 14 -Y 10 -Width 220 -Height 22 -FontSize 14 -Style Bold -Color $global:UGSM_ColorText))
    [void]$header.Controls.Add((New-UGSMLabel -Text 'Install SteamCMD once, then reuse it for all server downloads' -X 14 -Y 32 -Width 360 -Height 18 -FontSize 8.5 -Color $global:UGSM_ColorSuccessTextSoft))

    $lblHeaderSummary = New-UGSMLabel -Text '' -X 420 -Y 12 -Width 180 -Height 18 -FontSize 9 -Style Bold -Color $global:UGSM_ColorSuccessTextBright
    $lblSteamStatus = New-UGSMLabel -Text '' -X 420 -Y 32 -Width 260 -Height 18 -FontSize 8.5 -Color $global:UGSM_ColorSuccessTextBright
    [void]$header.Controls.Add($lblHeaderSummary)
    [void]$header.Controls.Add($lblSteamStatus)

    $btnInstallSteam = New-UGSMButton -Text 'Install SteamCMD' -X 700 -Y 12 -Width 122 -Height 24 -BackColor $Theme.AccentBlue
    $btnVerifySteam = New-UGSMButton -Text 'Verify' -X 830 -Y 12 -Width 56 -Height 24 -BackColor $global:UGSM_ColorSurfaceMuted
    $btnRemoveSteam = New-UGSMButton -Text 'Remove' -X 892 -Y 12 -Width 60 -Height 24 -BackColor $global:UGSM_ColorButtonStopMuted
    [void]$header.Controls.Add($btnInstallSteam)
    [void]$header.Controls.Add($btnVerifySteam)
    [void]$header.Controls.Add($btnRemoveSteam)

    $libraryCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $libraryCard.Dock = 'Fill'
    $libraryCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$root.Controls.Add($libraryCard, 0, 1)
    Add-CardHeader -Card $libraryCard -Title 'Installed Games' -Subtitle 'Binary library view'

    $contentHost = New-Object System.Windows.Forms.Panel
    $contentHost.Location = New-Object System.Drawing.Point(14, 58)
    $contentHost.Size = New-Object System.Drawing.Size(900, 200)
    $contentHost.Anchor = 'Top,Left,Right,Bottom'
    $contentHost.BackColor = $Theme.Surface
    $contentHost.Padding = New-Object System.Windows.Forms.Padding(0)
    $contentHost.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$libraryCard.Controls.Add($contentHost)

    $gamesHost = New-Object System.Windows.Forms.FlowLayoutPanel
    $gamesHost.Dock = 'Fill'
    $gamesHost.WrapContents = $true
    $gamesHost.AutoScroll = $true
    $gamesHost.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $gamesHost.BackColor = $Theme.Surface
    $gamesHost.Padding = New-Object System.Windows.Forms.Padding(0)
    $gamesHost.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$contentHost.Controls.Add($gamesHost)

    $footer = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 34 -BackColor $global:UGSM_ColorFooterBackground -BorderColor $global:UGSM_ColorFooterBorder
    $footer.Dock = 'Fill'
    $footer.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$root.Controls.Add($footer, 0, 2)

    $lblFooter = New-UGSMLabel -Text '' -X 12 -Y 8 -Width 1000 -Height 18 -FontSize 8.5 -Color $Theme.Muted
    [void]$footer.Controls.Add($lblFooter)

    if (-not $script:UGSM_GamesPageArtCache) {
        $script:UGSM_GamesPageArtCache = @{}
    }

    $callbackState = [ordered]@{
        PageData    = (& $getPageData)
        SetFooter   = $null
        RefreshData = $null
        RenderCards = $null
        LayoutPage  = $null
        RefreshAll  = $null
    }

    $setFooter = {
        param([string]$Message)
        if ($lblFooter -and -not $lblFooter.IsDisposed) {
            $lblFooter.Text = [string]$Message
        }
    }.GetNewClosure()
    $callbackState.SetFooter = $setFooter

    $getRenderableGames = {
        param([object[]]$Games)

        @(
            foreach ($item in @($Games)) {
                if ($null -eq $item) { continue }

                if ($item -is [System.Array] -or $item -is [System.Collections.IEnumerable] -and -not ($item -is [string]) -and -not ($item.PSObject.Properties['Id'])) {
                    foreach ($nested in @($item)) {
                        if ($null -ne $nested -and $nested.PSObject.Properties['Id']) { $nested }
                    }
                    continue
                }

                if ($item.PSObject.Properties['Id']) { $item }
            }
        )
    }.GetNewClosure()

    $applyPageData = {
        param([AllowNull()][object]$Data)

        $callbackState.PageData = & $normalizePageData $Data
        $games = @($callbackState.PageData.Games)
        & $writeGamesUILog -Level 'DEBUG' -Message ('Games page data applied. TotalInstalled={0}; Games={1}; Status={2}' -f [int]$callbackState.PageData.TotalInstalled, @($games).Count, [string]$callbackState.PageData.StatusMessage)
        $lblHeaderSummary.Text = ('Installed Games: {0}' -f [int]$callbackState.PageData.TotalInstalled)
        $lblSteamStatus.Text = [string]$callbackState.PageData.StatusMessage
        & $setFooter ([string]$callbackState.PageData.StatusMessage)
    }.GetNewClosure()

    $refreshData = {
        & $applyPageData (& $getPageData)
    }.GetNewClosure()
    $callbackState.RefreshData = $refreshData

    $disposeCardImages = {
        param([System.Windows.Forms.Control]$Control)

        if (-not $Control) { return }

        foreach ($child in @($Control.Controls)) {
            try {
                if ($child -is [System.Windows.Forms.PictureBox] -and $child.Image) {
                    $child.Image.Dispose()
                    $child.Image = $null
                }
            }
            catch {}

            try {
                if ($child.Controls.Count -gt 0) {
                    & $disposeCardImages $child
                }
            }
            catch {}
        }
    }.GetNewClosure()

    $clearCards = {
        foreach ($control in @($gamesHost.Controls)) {
            try { & $disposeCardImages $control } catch {}
            try { $control.Dispose() } catch {}
        }
        $gamesHost.Controls.Clear()
    }.GetNewClosure()

    $newArtControl = {
        param([psobject]$Game)

        $holder = New-UGSMPanel -X 12 -Y 12 -Width 180 -Height 96 -BackColor $global:UGSM_ColorArtPlaceholder -BorderColor $Theme.Border

        if (-not $script:UGSM_GamesPageArtCache) {
            $script:UGSM_GamesPageArtCache = @{}
        }

        $artPath = $null
        $gameId = if ($Game -and $Game.PSObject.Properties['Id']) { [string]$Game.Id } else { '' }

        if (-not [string]::IsNullOrWhiteSpace($gameId)) {
            $gameArtFolder = Join-Path (Join-Path $env:LOCALAPPDATA 'UGSM\Cache\GameArt') $gameId
            foreach ($candidateName in @('header.jpg', 'library_600x900.jpg', 'capsule_184x69.jpg', 'library_32x32.jpg')) {
                $candidatePath = Join-Path $gameArtFolder $candidateName
                if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                    $artPath = $candidatePath
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($artPath) -and $Game) {
            foreach ($pathPropertyName in @('HeaderArtPath', 'LibraryArtPath', 'CapsuleArtPath', 'IconArtPath')) {
                if (-not $Game.PSObject.Properties[$pathPropertyName]) { continue }

                $candidateArtPath = [string]$Game.$pathPropertyName
                if ([string]::IsNullOrWhiteSpace($candidateArtPath)) { continue }
                if (-not (Test-Path -LiteralPath $candidateArtPath -PathType Leaf)) { continue }

                $artPath = $candidateArtPath
                break
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($artPath)) {
            try {
                $cacheKey = [string]$artPath
                $cachedImage = $null
                if ((Get-UGSMGamesPageArtCache).ContainsKey($cacheKey)) {
                    $cachedImage = (Get-UGSMGamesPageArtCache)[$cacheKey]
                }
                elseif (Test-Path -LiteralPath $artPath -PathType Leaf) {
                    $bytes = [System.IO.File]::ReadAllBytes($artPath)
                    $ms = New-Object System.IO.MemoryStream(,$bytes)
                    try {
                        $loaded = [System.Drawing.Image]::FromStream($ms)
                        $cachedImage = [System.Drawing.Image]$loaded.Clone()
                        $loaded.Dispose()
                    }
                    finally {
                        $ms.Dispose()
                    }
                    (Get-UGSMGamesPageArtCache)[$cacheKey] = $cachedImage
                }

                if ($cachedImage) {
                    $picture = New-Object System.Windows.Forms.PictureBox
                    $picture.Dock = 'Fill'
                    $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
                    $picture.BackColor = $global:UGSM_ColorArtPlaceholder
                    $picture.Image = [System.Drawing.Image]$cachedImage.Clone()
                    [void]$holder.Controls.Add($picture)
                    return $holder
                }
            }
            catch {
                & $writeGamesUILog -Level 'DEBUG' -Message ('Game art load failed. GameId={0}; Path={1}' -f $gameId, $artPath) -Exception $_.Exception
            }
        }

        $fallbackText = if ($Game -and $Game.PSObject.Properties['Name']) { [string]$Game.Name } else { 'Unknown Game' }
        $fallback = New-UGSMLabel -Text $fallbackText -X 10 -Y 28 -Width 160 -Height 36 -FontSize 11 -Style Bold -Color $Theme.Text -Align 'MiddleCenter'
        [void]$holder.Controls.Add($fallback)
        return $holder
    }.GetNewClosure()

    $invokeGameAction = {
        param(
            [Parameter(Mandatory)][string]$GameId,
            [Parameter(Mandatory)][ValidateSet('Install', 'Repair', 'Remove', 'Update', 'Verify')][string]$Action,
            [Parameter(Mandatory)][string]$ProgressMessage
        )

        $finalMessage = $null

        try {
            if ($callbackState.SetFooter) {
                & $callbackState.SetFooter $ProgressMessage
            }

            & $writeGamesUILog -Level 'INFO' -Message ('Game action clicked. Action={0}; GameId={1}' -f $Action, $GameId)

            $swAction = [System.Diagnostics.Stopwatch]::StartNew()

            $result = $null
            if (Get-Command Invoke-UGSMGameBinaryAction -ErrorAction SilentlyContinue) {
                $result = Invoke-UGSMGameBinaryAction -Action $Action -GameId $GameId
            }
            else {
                switch ($Action) {
                    'Install' { $actionResult = Ensure-UGSMGameServerInstalled -GameId $GameId }
                    'Repair' { $actionResult = Install-UGSMGameServer -GameId $GameId -Validate }
                    'Remove' { $actionResult = Remove-UGSMGameServer -GameId $GameId }
                    'Update' { $actionResult = Update-UGSMGameServer -GameId $GameId }
                    'Verify' { $actionResult = Verify-UGSMGameServer -GameId $GameId }
                }

                $result = [pscustomobject]@{
                    Action       = $Action
                    ActionResult = $actionResult
                    PageData     = (& $getPageData)
                    Message      = if ($actionResult -and $actionResult.PSObject.Properties['Message']) { [string]$actionResult.Message } else { '' }
                }
            }

            $swAction.Stop()
            & $writeGamesUILog -Level 'INFO' -Message ('Game action service call completed. Action={0}; GameId={1}; DurationMs={2}' -f $Action, $GameId, $swAction.ElapsedMilliseconds)

            if ($result -and $result.PSObject.Properties['PageData']) {
                & $applyPageData $result.PageData
            }
            else {
                & $refreshData
            }

            if ($result -and $result.PSObject.Properties['Message']) {
                $finalMessage = [string]$result.Message
            }
        }
        catch {
            $finalMessage = [string]$_.Exception.Message
            & $writeGamesUILog -Level 'ERROR' -Message ('Game action failed. Action={0}; GameId={1}' -f $Action, $GameId) -Exception $_.Exception
            & $refreshData
        }

        $swRender = [System.Diagnostics.Stopwatch]::StartNew()
        if ($callbackState.RenderCards) { & $callbackState.RenderCards }
        if ($callbackState.LayoutPage) { & $callbackState.LayoutPage }
        $swRender.Stop()
        & $writeGamesUILog -Level 'DEBUG' -Message ('Game action render/layout completed. Action={0}; GameId={1}; DurationMs={2}' -f $Action, $GameId, $swRender.ElapsedMilliseconds)

        if ($finalMessage -and $callbackState.SetFooter) {
            & $callbackState.SetFooter $finalMessage
        }
    }.GetNewClosure()

    $newGameCard = {
        param([psobject]$Game)

        $card = New-UGSMPanel -X 0 -Y 0 -Width 340 -Height 170 -BackColor $Theme.SurfaceAlt -BorderColor $Theme.Border
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 14)

        $artControl = & $newArtControl $Game
        if ($artControl) {
            [void]$card.Controls.Add($artControl)
            $artControl.BringToFront()
        }

        $gameName = if ($Game.PSObject.Properties['Name']) { [string]$Game.Name } else { 'Unknown Game' }
        [void]$card.Controls.Add((New-UGSMLabel -Text $gameName -X 202 -Y 14 -Width 126 -Height 34 -FontSize 10 -Style Bold -Color $Theme.Text))

        $isValid = if ($Game.PSObject.Properties['IsValid']) { [bool]$Game.IsValid } else { $false }
        $needsRepair = if ($Game.PSObject.Properties['NeedsRepair']) { [bool]$Game.NeedsRepair } else { $false }
        $statusText = if ($Game.PSObject.Properties['StatusText']) { [string]$Game.StatusText } else { '' }
        $instanceCount = if ($Game.PSObject.Properties['InstanceCount']) { [int]$Game.InstanceCount } else { 0 }
        $installPath = if ($Game.PSObject.Properties['InstallPath']) { [string]$Game.InstallPath } else { '' }

        $statusColor = if ($isValid) { $Theme.Accent } elseif ($needsRepair) { $Theme.AccentWarning } else { $Theme.Muted }
        [void]$card.Controls.Add((New-UGSMLabel -Text $statusText -X 202 -Y 52 -Width 126 -Height 18 -FontSize 8.5 -Color $statusColor))
        [void]$card.Controls.Add((New-UGSMLabel -Text ('Profiles: {0}' -f $instanceCount) -X 202 -Y 72 -Width 126 -Height 18 -FontSize 8.0 -Color $Theme.Muted))

        $displayPath = if ([string]::IsNullOrWhiteSpace($installPath)) { 'Not installed yet' } else { Get-UGSMDisplayPath -Path $installPath -MaxLength 24 }
        [void]$card.Controls.Add((New-UGSMLabel -Text $displayPath -X 12 -Y 116 -Width 210 -Height 18 -FontSize 8.0 -Color $Theme.Muted))

        $isInstalled = if ($Game.PSObject.Properties['IsInstalled']) { [bool]$Game.IsInstalled } elseif ($Game.PSObject.Properties['Installed']) { [bool]$Game.Installed } else { $false }
        $supportsRemove = if ($Game.PSObject.Properties['SupportsRemove']) { [bool]$Game.SupportsRemove } else { $false }

        $actionHandler = $invokeGameAction
        $btnPrimary = $null
        $btnSecondary = $null

        if ($isInstalled -and $supportsRemove) {
            $btnSecondary = New-UGSMButton -Text 'Update' -X 238 -Y 96 -Width 88 -Height 26 -BackColor $global:UGSM_ColorSurfaceMuted
            $btnSecondary.Add_Click({
                    param($sender, $eventArgs)
                    & $actionHandler -GameId $Game.Id -Action 'Update' -ProgressMessage ('Checking for updates for {0}...' -f $Game.Id)
                }.GetNewClosure())

            $btnPrimary = New-UGSMButton -Text 'Remove' -X 238 -Y 128 -Width 88 -Height 26 -BackColor $global:UGSM_ColorButtonRemoveMuted
            $btnPrimary.Add_Click({
                    param($sender, $eventArgs)
                    & $actionHandler -GameId $Game.Id -Action 'Remove' -ProgressMessage ('Removing {0} binaries...' -f $Game.Id)
                }.GetNewClosure())
        }
        elseif ($needsRepair) {
            $btnSecondary = New-UGSMButton -Text 'Verify' -X 238 -Y 96 -Width 88 -Height 26 -BackColor $global:UGSM_ColorSurfaceMuted
            $btnSecondary.Add_Click({
                    param($sender, $eventArgs)
                    & $actionHandler -GameId $Game.Id -Action 'Verify' -ProgressMessage ('Verifying {0} files...' -f $Game.Id)
                }.GetNewClosure())

            $btnPrimary = New-UGSMButton -Text 'Repair' -X 238 -Y 128 -Width 88 -Height 26 -BackColor $global:UGSM_ColorCaution
            $btnPrimary.Add_Click({
                    param($sender, $eventArgs)
                    & $actionHandler -GameId $Game.Id -Action 'Repair' -ProgressMessage ('Repairing {0}...' -f $Game.Id)
                }.GetNewClosure())
        }
        else {
            $btnPrimary = New-UGSMButton -Text 'Install' -X 238 -Y 128 -Width 88 -Height 26 -BackColor $Theme.AccentBlue
            $btnPrimary.Add_Click({
                    param($sender, $eventArgs)
                    & $actionHandler -GameId $Game.Id -Action 'Install' -ProgressMessage ('Installing {0}...' -f $Game.Id)
                }.GetNewClosure())
        }

        if ($btnSecondary) {
            [void]$card.Controls.Add($btnSecondary)
        }

        if ($btnPrimary) {
            [void]$card.Controls.Add($btnPrimary)
        }

        return $card
    }.GetNewClosure()

    $renderCards = {
        $gamesHost.SuspendLayout()
        try {
            & $clearCards
            $gamesToRender = & $getRenderableGames @($callbackState.PageData.Games)

            foreach ($game in $gamesToRender) {
                $card = & $newGameCard $game
                [void]$gamesHost.Controls.Add($card)
            }

            if ($gamesHost.Controls.Count -eq 0) {
                $empty = New-UGSMLabel -Text 'No supported games were found.' -X 18 -Y 18 -Width 400 -Height 24 -FontSize 10 -Style Bold -Color $Theme.Muted
                [void]$gamesHost.Controls.Add($empty)
            }

            & $writeGamesUILog -Level 'DEBUG' -Message ('Games page cards rendered. Count={0}' -f $gamesHost.Controls.Count)
        }
        finally {
            $gamesHost.ResumeLayout($true)
            $gamesHost.PerformLayout()
            $gamesHost.Invalidate($true)
            $gamesHost.Refresh()
            if ($gamesHost.Parent) {
                $gamesHost.Parent.PerformLayout()
                $gamesHost.Parent.Invalidate($true)
                $gamesHost.Parent.Refresh()
            }
        }
    }.GetNewClosure()
    $callbackState.RenderCards = $renderCards

    $layoutPage = {
        $contentHost.Location = New-Object System.Drawing.Point(14, 58)
        $contentHost.Size = New-Object System.Drawing.Size(
            [Math]::Max(300, $libraryCard.ClientSize.Width - 28),
            [Math]::Max(200, $libraryCard.ClientSize.Height - 72)
        )
    }.GetNewClosure()
    $callbackState.LayoutPage = $layoutPage

    $refreshAll = {
        if ($callbackState.RefreshData) { & $callbackState.RefreshData }
        if ($callbackState.RenderCards) { & $callbackState.RenderCards }
        if ($callbackState.LayoutPage) { & $callbackState.LayoutPage }
    }.GetNewClosure()
    $callbackState.RefreshAll = $refreshAll

    $page.Tag = [pscustomobject]@{
        RefreshAll = $refreshAll
    }

    $btnInstallSteam.Add_Click({
            $finalMessage = $null
            try {
                & $writeGamesUILog -Level 'INFO' -Message 'SteamCMD install clicked.'
                $result = Ensure-UGSMSteamCMDInstalled
                if ($result -and $result.PSObject.Properties['Message']) {
                    $finalMessage = [string]$result.Message
                }
                & $writeGamesUILog -Level 'INFO' -Message ('SteamCMD install completed. Message={0}' -f $finalMessage)
            }
            catch {
                $finalMessage = [string]$_.Exception.Message
                & $writeGamesUILog -Level 'ERROR' -Message 'SteamCMD install failed.' -Exception $_.Exception
            }

            & $refreshAll
            if ($finalMessage -and $callbackState.SetFooter) { & $callbackState.SetFooter $finalMessage }
        }.GetNewClosure())

    $btnVerifySteam.Add_Click({
            $finalMessage = $null
            try {
                & $writeGamesUILog -Level 'INFO' -Message 'SteamCMD verify clicked.'
                $settings = Get-UGSMGlobalSettingsModel
                $result = Test-UGSMSteamCMDInstall -InstallPath ([string]$settings.SteamCmdPath)
                $finalMessage = $(if ($result.IsInstalled) { 'SteamCMD verified successfully.' } else { 'SteamCMD is not installed.' })
                & $writeGamesUILog -Level 'INFO' -Message ('SteamCMD verify completed. IsInstalled={0}' -f [bool]$result.IsInstalled)
            }
            catch {
                $finalMessage = [string]$_.Exception.Message
                & $writeGamesUILog -Level 'ERROR' -Message 'SteamCMD verify failed.' -Exception $_.Exception
            }

            & $refreshAll
            if ($finalMessage -and $callbackState.SetFooter) { & $callbackState.SetFooter $finalMessage }
        }.GetNewClosure())

    $btnRemoveSteam.Add_Click({
            $finalMessage = $null
            try {
                & $writeGamesUILog -Level 'INFO' -Message 'SteamCMD remove clicked.'
                $settings = Get-UGSMGlobalSettingsModel
                $result = Remove-UGSMSteamCMD -InstallPath ([string]$settings.SteamCmdPath)
                if ($result -and $result.PSObject.Properties['Message']) {
                    $finalMessage = [string]$result.Message
                }
                & $writeGamesUILog -Level 'INFO' -Message ('SteamCMD remove completed. Message={0}' -f $finalMessage)
            }
            catch {
                $finalMessage = [string]$_.Exception.Message
                & $writeGamesUILog -Level 'ERROR' -Message 'SteamCMD remove failed.' -Exception $_.Exception
            }

            & $refreshAll
            if ($finalMessage -and $callbackState.SetFooter) { & $callbackState.SetFooter $finalMessage }
        }.GetNewClosure())

    & $refreshAll
    & $writeGamesUILog -Level 'DEBUG' -Message 'Games page initial refresh completed.'

    $page.Add_Resize({ & $layoutPage }.GetNewClosure())
    $page.Add_Disposed({
            & $writeGamesUILog -Level 'DEBUG' -Message 'Games page disposed; cleaning card images.'
            foreach ($card in @($gamesHost.Controls)) {
                try { & $disposeCardImages $card } catch {}
            }
        }.GetNewClosure())

    return $page
}
