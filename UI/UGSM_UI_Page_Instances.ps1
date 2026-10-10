# Instances Page

function Write-UGSMInstancesUILog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'InstancesUI' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'InstancesUI' -Message $Message
        }
        return
    }

    if (Get-Command Write-UGSMTrace -ErrorAction SilentlyContinue) {
        Write-UGSMTrace -Component 'UI.InstancesPage' -Message $Message
    }
}

function Get-UGSMInstancesUIInstanceText {
    [CmdletBinding()]
    param([object]$Instance)

    if (Get-Command Format-UGSMTraceInstance -ErrorAction SilentlyContinue) {
        return (Format-UGSMTraceInstance $Instance)
    }

    if (-not $Instance) { return '<null>' }

    $id = ''
    $name = ''
    $gameId = ''
    if ($Instance.PSObject.Properties['Id']) { $id = [string]$Instance.Id }
    if ($Instance.PSObject.Properties['Name']) { $name = [string]$Instance.Name }
    if ($Instance.PSObject.Properties['GameId']) { $gameId = [string]$Instance.GameId }
    return ('Id={0}; Name={1}; GameId={2}' -f $id, $name, $gameId)
}

function New-UGSMInstancesPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Theme,

        [Parameter()]
        [object]$AppState
    )

    $pageCreateWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMInstancesUILog -Level 'INFO' -Message 'Instances page creation started.'

    # Compatibility guard for shared selection helpers loaded outside this page.
    # Some builds call Set-UGSMSelectedInstanceState from ListBox selection events,
    # and that helper expects this resolver variable to exist in the caller scope.
    # Keep it as a no-op resolver here so selection refreshes do not throw when
    # the shell has not provided its own resolver.
    if (-not (Get-Variable -Name 'ResolveLiveInstancesPageControl' -Scope Local -ErrorAction SilentlyContinue)) {
        $ResolveLiveInstancesPageControl = { param([object]$Control) return $Control }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'ResolveLiveInstancesPageControl' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ResolveLiveInstancesPageControl = $ResolveLiveInstancesPageControl
    }
    if (-not (Get-Variable -Name 'ResolveLiveInstancesPageControl' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:ResolveLiveInstancesPageControl = $ResolveLiveInstancesPageControl
    }

    if (-not (Get-Variable -Name 'UpdateSelectedInstanceContextUI' -Scope Local -ErrorAction SilentlyContinue)) {
        $UpdateSelectedInstanceContextUI = { param([AllowNull()][object]$Instance) }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'UpdateSelectedInstanceContextUI' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:UpdateSelectedInstanceContextUI = $UpdateSelectedInstanceContextUI
    }
    if (-not (Get-Variable -Name 'UpdateSelectedInstanceContextUI' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:UpdateSelectedInstanceContextUI = $UpdateSelectedInstanceContextUI
    }

    if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Local -ErrorAction SilentlyContinue)) {
        $UpdateStatusBarUI = {
            param([string]$Message)
            try {
                if ($lblFooter -and -not [string]::IsNullOrWhiteSpace($Message)) {
                    $lblFooter.Text = $Message
                }
            }
            catch { }
        }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:UpdateStatusBarUI = $UpdateStatusBarUI
    }
    if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:UpdateStatusBarUI = $UpdateStatusBarUI
    }


    # Local-only selected-instance setter. Do not call the shared/global
    # Set-UGSMSelectedInstanceState helper from this page; older loaded builds of
    # that helper reference $ResolveLiveInstancesPageControl from the wrong scope
    # and throw during ListBox selection refresh.
    $SetInstancesPageSelectedState = {
        param([AllowNull()][object]$Instance)

        if (-not $AppState) { return }

        if ($AppState -is [hashtable]) {
            if ($Instance) {
                $AppState['SelectedInstance'] = $Instance
                $AppState['SelectedInstanceId'] = [string]$Instance.Id
            }
            else {
                $AppState['SelectedInstance'] = $null
                $AppState['SelectedInstanceId'] = $null
            }
            return
        }

        try {
            if ($Instance) {
                $AppState.SelectedInstance = $Instance
                $AppState.SelectedInstanceId = [string]$Instance.Id
            }
            else {
                $AppState.SelectedInstance = $null
                $AppState.SelectedInstanceId = $null
            }
        }
        catch {
            Write-UGSMInstancesUILog -Level 'WARN' -Message 'Failed to update selected instance state from Instances page.' -Exception $_.Exception
        }
    }.GetNewClosure()

    if (-not $Theme -and (Get-Command Get-UGSMTheme -ErrorAction SilentlyContinue)) {
        $Theme = Get-UGSMTheme
    }

    $pageDataWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $pageData = if (Get-Command Get-UGSMInstancesPageData -ErrorAction SilentlyContinue) {
            Get-UGSMInstancesPageData
        }
        else {
            [pscustomobject]@{
                TotalCount    = @((Get-UGSMInstances)).Count
                RunningCount  = 0
                StartingCount = 0
                StoppedCount  = 0
                Instances     = @(Get-UGSMInstances)
            }
        }
        $pageDataWatch.Stop()
        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('Initial instances page data loaded. Count={0}; DurationMs={1}' -f @($pageData.Instances).Count, $pageDataWatch.ElapsedMilliseconds)
    }
    catch {
        $pageDataWatch.Stop()
        Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Failed to load initial instances page data. DurationMs={0}' -f $pageDataWatch.ElapsedMilliseconds) -Exception $_.Exception
        throw
    }

    $page = New-UGSMDockPanel -Dock 'Fill' -BackColor $global:UGSM_ColorPageBackground -Padding (New-Object System.Windows.Forms.Padding(14, 14, 14, 18)) -DoubleBuffered

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.Margin = New-Object System.Windows.Forms.Padding(0)
    $root.Padding = New-Object System.Windows.Forms.Padding(0)
    $root.BackColor = $global:UGSM_ColorPageBackground
    $root.ColumnCount = 1
    $root.RowCount = 3
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$page.Controls.Add($root)

    # Header
    $header = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 56 -BackColor $global:UGSM_ColorSuccessSurface -BorderColor $global:UGSM_ColorSuccessBorder
    $header.Dock = 'Fill'
    $header.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$root.Controls.Add($header, 0, 0)

    $lblHeaderTitle = New-UGSMLabel -Text 'Instances' -X 14 -Y 4 -Width 260 -Height 24 -FontSize 14 -Style Bold -Color $global:UGSM_ColorText
    $lblHeaderSummary = New-UGSMLabel -Text 'Loading instances...' -X 14 -Y 28 -Width 900 -Height 16 -FontSize 8.5 -Color $global:UGSM_ColorSuccessTextSoft
    $lblHeaderSummary.Anchor = 'Left,Top,Right'
    [void]$header.Controls.Add($lblHeaderTitle)
    [void]$header.Controls.Add($lblHeaderSummary)

    # Workspace
    $workspace = New-Object System.Windows.Forms.TableLayoutPanel
    $workspace.Dock = 'Fill'
    $workspace.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $workspace.Padding = New-Object System.Windows.Forms.Padding(0)
    $workspace.BackColor = $global:UGSM_ColorPageBackground
    $workspace.ColumnCount = 1
    $workspace.RowCount = 2
    [void]$workspace.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$workspace.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 178)))
    [void]$workspace.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.Controls.Add($workspace, 0, 1)

    # Selected instance summary. This stays on the page now that the old right-side context panel is removed.
    $detailsCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 168 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $detailsCard.Dock = 'Fill'
    $detailsCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$workspace.Controls.Add($detailsCard, 0, 0)
    Add-CardHeader -Card $detailsCard -Title 'Selected Instance' -Subtitle 'Choose an instance to manage'

    $detailsLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $detailsLayout.Dock = 'Fill'
    $detailsLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $detailsLayout.Padding = New-Object System.Windows.Forms.Padding(16, 56, 16, 12)
    $detailsLayout.BackColor = [System.Drawing.Color]::Transparent
    $detailsLayout.ColumnCount = 3
    $detailsLayout.RowCount = 1
    [void]$detailsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 252)))
    [void]$detailsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$detailsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 500)))
    [void]$detailsLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$detailsCard.Controls.Add($detailsLayout)
    $detailsLayout.SendToBack()

    $artBox = New-Object System.Windows.Forms.PictureBox
    $artBox.Dock = 'Fill'
    $artBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    $artBox.SizeMode = 'Zoom'
    $artBox.BackColor = $global:UGSM_ColorArtBackground
    [void]$detailsLayout.Controls.Add($artBox, 0, 0)

    $detailsTextPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $detailsTextPanel.Dock = 'Fill'
    $detailsTextPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    $detailsTextPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $detailsTextPanel.BackColor = [System.Drawing.Color]::Transparent
    $detailsTextPanel.ColumnCount = 1
    $detailsTextPanel.RowCount = 2
    [void]$detailsTextPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$detailsTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
    [void]$detailsTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$detailsLayout.Controls.Add($detailsTextPanel, 1, 0)

    $lblDetailsTitle = New-UGSMLabel -Text 'No instance selected' -X 0 -Y 0 -Width 100 -Height 26 -FontSize 12 -Style Bold -Color $Theme.Text
    $lblDetailsTitle.Dock = 'Fill'
    $lblDetailsTitle.AutoEllipsis = $true
    [void]$detailsTextPanel.Controls.Add($lblDetailsTitle, 0, 0)

    $lblDetailsBody = New-UGSMLabel -Text 'Select an instance from the list to view details.' -X 0 -Y 0 -Width 100 -Height 90 -FontSize 8.75 -Color $Theme.Muted
    $lblDetailsBody.Dock = 'Fill'
    $lblDetailsBody.AutoSize = $false
    $lblDetailsBody.AutoEllipsis = $true
    [void]$detailsTextPanel.Controls.Add($lblDetailsBody, 0, 1)

    $actionsPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $actionsPanel.Dock = 'Fill'
    $actionsPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $actionsPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $actionsPanel.BackColor = [System.Drawing.Color]::Transparent
    $actionsPanel.ColumnCount = 1
    $actionsPanel.RowCount = 2
    [void]$actionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$actionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 78)))
    [void]$actionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$detailsLayout.Controls.Add($actionsPanel, 2, 0)

    $buttonFlow = New-UGSMFlowPanel -Dock 'Fill' -BackColor ([System.Drawing.Color]::Transparent) -WrapContents $true
    [void]$actionsPanel.Controls.Add($buttonFlow, 0, 0)

    $btnStart  = New-UGSMButton -Text 'Start'          -X 0 -Y 0 -Width 88  -Height 32 -BackColor $Theme.Accent
    $btnStop   = New-UGSMButton -Text 'Stop'           -X 0 -Y 0 -Width 88  -Height 32 -BackColor $global:UGSM_ColorDangerSurface
    $btnEdit   = New-UGSMButton -Text 'Edit'           -X 0 -Y 0 -Width 88  -Height 32
    $btnOpen   = New-UGSMButton -Text 'Open Folder'    -X 0 -Y 0 -Width 110 -Height 32
    $btnRemove = New-UGSMButton -Text 'Remove Profile' -X 0 -Y 0 -Width 122 -Height 32 -BackColor $global:UGSM_ColorDangerMutedBackground

    $btnStart.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
    $btnStop.Margin   = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
    $btnEdit.Margin   = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnOpen.Margin   = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnRemove.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)

    [void]$buttonFlow.Controls.Add($btnStart)
    [void]$buttonFlow.Controls.Add($btnStop)
    [void]$buttonFlow.Controls.Add($btnEdit)
    [void]$buttonFlow.Controls.Add($btnOpen)
    [void]$buttonFlow.Controls.Add($btnRemove)

    $lblActionInfo = New-UGSMLabel -Text 'Remove Profile deletes only the selected profile. Shared game binaries stay in place.' -X 0 -Y 0 -Width 100 -Height 34 -FontSize 8.5 -Color $Theme.Muted
    $lblActionInfo.Dock = 'Fill'
    $lblActionInfo.AutoSize = $false
    [void]$actionsPanel.Controls.Add($lblActionInfo, 0, 1)

    $editorHostCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $editorHostCard.Dock = 'Fill'
    $editorHostCard.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$workspace.Controls.Add($editorHostCard, 0, 1)
    Add-CardHeader -Card $editorHostCard -Title 'Game-Specific Editor' -Subtitle ''
    $editorHostCard.Padding = New-Object System.Windows.Forms.Padding(10, 58, 12, 12)

    $editorHostPanel = New-UGSMDockPanel -Dock 'Fill' -BackColor $global:UGSM_ColorCanvas -DoubleBuffered
    [void]$editorHostCard.Controls.Add($editorHostPanel)

    $applyResponsiveDetailsLayout = {
        if (-not $detailsCard -or $detailsCard.IsDisposed) { return }
        if (-not $detailsLayout -or $detailsLayout.IsDisposed) { return }

        $width = [int]$detailsCard.ClientSize.Width
        if ($width -lt 980) {
            $detailsLayout.ColumnStyles[0].Width = 0
            $detailsLayout.ColumnStyles[2].Width = 360
            $artBox.Visible = $false
            $lblActionInfo.Visible = $false
        }
        elseif ($width -lt 1250) {
            $detailsLayout.ColumnStyles[0].Width = 220
            $detailsLayout.ColumnStyles[2].Width = 400
            $artBox.Visible = $true
            $lblActionInfo.Visible = $false
        }
        else {
            $detailsLayout.ColumnStyles[0].Width = 252
            $detailsLayout.ColumnStyles[2].Width = 500
            $artBox.Visible = $true
            $lblActionInfo.Visible = $true
        }
    }.GetNewClosure()

    $detailsCard.Add_SizeChanged({ & $applyResponsiveDetailsLayout }.GetNewClosure())
    & $applyResponsiveDetailsLayout

    # Footer
    $footer = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 34 -BackColor $global:UGSM_ColorFooterBackground -BorderColor $global:UGSM_ColorFooterBorder
    $footer.Dock = 'Fill'
    $footer.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$root.Controls.Add($footer, 0, 2)

    $lblFooter = New-UGSMLabel -Text 'Instances page ready' -X 12 -Y 8 -Width 900 -Height 18 -FontSize 8.5 -Color $Theme.Muted
    $lblFooter.Anchor = 'Left,Top,Right'
    [void]$footer.Controls.Add($lblFooter)

    # Helpers
    $uiRenderState = [pscustomobject]@{
        ArtKey    = $null
        EditorKey = $null
    }

    $getInstanceEditorKey = {
        param($instance)

        if (-not $instance) { return '<none>' }

        $gameId = if ($instance.PSObject.Properties['GameId']) { [string]$instance.GameId } else { '' }
        $instanceId = if ($instance.PSObject.Properties['Id']) { [string]$instance.Id } else { '' }
        if ([string]::IsNullOrWhiteSpace($instanceId) -and $instance.PSObject.Properties['Name']) {
            $instanceId = [string]$instance.Name
        }

        return ('{0}|{1}' -f $gameId, $instanceId)
    }.GetNewClosure()

    $setArtForGame = {
        param($game)

        $gameKey = '<none>'
        if ($game) {
            if ($game.PSObject.Properties['Id']) { $gameKey = [string]$game.Id }
            elseif ($game.PSObject.Properties['Name']) { $gameKey = [string]$game.Name }
        }

        if ($uiRenderState.ArtKey -eq $gameKey) {
            return
        }

        $uiRenderState.ArtKey = $gameKey

        if ($artBox.Image) {
            $artBox.Image.Dispose()
            $artBox.Image = $null
        }

        if (-not $game) { return }
        if (-not (Get-Command Get-UGSMGameHeaderArt -ErrorAction SilentlyContinue)) { return }

        $artPath = Get-UGSMGameHeaderArt -Game $game
        if ([string]::IsNullOrWhiteSpace($artPath) -or -not (Test-Path -LiteralPath $artPath)) { return }

        try {
            $imageBytes = [System.IO.File]::ReadAllBytes($artPath)
            $memoryStream = New-Object System.IO.MemoryStream(, $imageBytes)
            try {
                $artBox.Image = [System.Drawing.Image]::FromStream($memoryStream)
            }
            finally {
                $memoryStream.Dispose()
            }
        }
        catch {
            $artBox.Image = $null
            Write-UGSMInstancesUILog -Level 'WARN' -Message ('Failed to load instance page artwork: ' + [string]$artPath) -Exception $_.Exception
        }
    }.GetNewClosure()

    $GetRefreshedState = {
        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('GetRefreshedState start. AppState SelectedInstanceId=' + [string]$AppState.SelectedInstanceId + '; SelectedGameId=' + [string]$AppState.SelectedGameId)

        # Keep this page self-contained for selected-instance refreshes.
        # Some shared refresh helpers still reference $ResolveLiveInstancesPageControl
        # from their own scope and can throw after a profile is removed.
        $fallbackPageData = if (Get-Command Get-UGSMInstancesPageData -ErrorAction SilentlyContinue) {
            Get-UGSMInstancesPageData
        }
        else {
            [pscustomobject]@{
                TotalCount    = @((Get-UGSMInstances)).Count
                RunningCount  = 0
                StartingCount = 0
                StoppedCount  = 0
                Instances     = @(Get-UGSMInstances)
            }
        }

        $selected = $null
        $selectedId = if ($AppState -is [hashtable]) { [string]$AppState['SelectedInstanceId'] } else { [string]$AppState.SelectedInstanceId }
        if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
            $selected = @($fallbackPageData.Instances | Where-Object { [string]$_.Id -eq $selectedId -or [string]$_.Name -eq $selectedId } | Select-Object -First 1)
        }

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('GetRefreshedState resolved selected=' + (Get-UGSMInstancesUIInstanceText $selected) + '; Instances=' + [string]@($fallbackPageData.Instances).Count)

        return [pscustomobject]@{
            PageData         = $fallbackPageData
            SelectedInstance = $selected
        }
    }.GetNewClosure()

    $refreshHeader = {
        $currentData = if ($script:UGSMInstancesCurrentPageData) { $script:UGSMInstancesCurrentPageData } else { $pageData }
        $lblHeaderSummary.Text = ('Total: {0}   Running: {1}   Starting: {2}   Stopped: {3}' -f $currentData.TotalCount, $currentData.RunningCount, $currentData.StartingCount, $currentData.StoppedCount)
    }.GetNewClosure()

    $renderGameSpecificEditor = {
        param(
            $instance,
            [bool]$ForceEditorRefresh = $false
        )

        if (-not $editorHostPanel -or $editorHostPanel.IsDisposed) {
            return
        }

        $editorKey = & $getInstanceEditorKey $instance
        if (-not $ForceEditorRefresh -and $uiRenderState.EditorKey -eq $editorKey) {
            Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('Skipped game-specific editor rebuild. EditorKey={0}' -f $editorKey)
            return
        }

        $uiRenderState.EditorKey = $editorKey
        $editorWatch = [System.Diagnostics.Stopwatch]::StartNew()

        $editorHostPanel.SuspendLayout()
        try {
            $editorHostPanel.Controls.Clear()

            if (-not $instance) {
                $emptyLabel = New-UGSMLabel -Text 'Select an instance to load a game-specific profile editor.' -X 16 -Y 16 -Width 720 -Height 24 -FontSize 10 -Color $Theme.Muted
                [void]$editorHostPanel.Controls.Add($emptyLabel)
                return
            }

            $builderName = ('New-UGSMGame{0}InstanceEditor' -f ([string]$instance.GameId -replace '[^A-Za-z0-9]', ''))
            if (Get-Command -Name $builderName -ErrorAction SilentlyContinue) {
                try {
                    & $builderName -Instance $instance -Theme $Theme -HostPanel $editorHostPanel -StatusLabel $lblFooter
                    return
                }
                catch {
                    $errorLabel = New-UGSMLabel -Text ('Failed to load editor: ' + $_.Exception.Message) -X 16 -Y 16 -Width 820 -Height 48 -FontSize 9 -Color $global:UGSM_ColorErrorTextSoft
                    $errorLabel.AutoSize = $false
                    [void]$editorHostPanel.Controls.Add($errorLabel)
                    Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Game-specific editor failed to render. Builder={0}; EditorKey={1}' -f $builderName, $editorKey) -Exception $_.Exception
                    return
                }
            }

            $fallbackLabel = New-UGSMLabel -Text ('No game-specific editor is registered for ' + [string]$instance.GameId + '.') -X 16 -Y 16 -Width 720 -Height 24 -FontSize 10 -Color $Theme.Muted
            [void]$editorHostPanel.Controls.Add($fallbackLabel)
        }
        finally {
            $editorHostPanel.ResumeLayout()
            $editorWatch.Stop()
            if ($editorWatch.ElapsedMilliseconds -gt 250) {
                Write-UGSMInstancesUILog -Level 'WARN' -Message ('Game-specific editor render was slow. EditorKey={0}; DurationMs={1}' -f $editorKey, $editorWatch.ElapsedMilliseconds)
            }
            else {
                Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('Game-specific editor render finished. EditorKey={0}; DurationMs={1}' -f $editorKey, $editorWatch.ElapsedMilliseconds)
            }
        }
    }.GetNewClosure()

    $getSelectedInstance = {
        $currentData = if ($script:UGSMInstancesCurrentPageData) { $script:UGSMInstancesCurrentPageData } else { $pageData }
        $resolved = $null

        $selectedId = $null
        if ($AppState -is [hashtable]) {
            $selectedId = $AppState['SelectedInstanceId']
        }
        else {
            $selectedId = $AppState.SelectedInstanceId
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$selectedId)) {
            foreach ($instance in @($currentData.Instances)) {
                if ([string]$instance.Id -eq [string]$selectedId -or [string]$instance.Name -eq [string]$selectedId) {
                    $resolved = $instance
                    break
                }
            }
        }

        if ($resolved) {
            return $resolved
        }

        if ($AppState -and $AppState.PSObject.Properties['SelectedInstance'] -and $AppState.SelectedInstance) {
            return $AppState.SelectedInstance
        }

        $selectedId = if ($AppState -is [hashtable]) { [string]$AppState['SelectedInstanceId'] } else { [string]$AppState.SelectedInstanceId }
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedId) -and (Get-Command Get-UGSMInstance -ErrorAction SilentlyContinue)) {
            try {
                $liveInstance = Get-UGSMInstance -Id ([string]$selectedId)
                if ($liveInstance) {
                    & $SetInstancesPageSelectedState $liveInstance

                    return $liveInstance
                }
            }
            catch {
            }
        }

        return $null
    }.GetNewClosure()

    $refreshSelected = {
        param(
            $instance,
            [bool]$ForceEditorRefresh = $false
        )

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('refreshSelected called with ' + (Get-UGSMInstancesUIInstanceText $instance) + '; ForceEditorRefresh=' + [string]$ForceEditorRefresh)

        if (-not $instance) {
            $lblDetailsTitle.Text = 'No instance selected'
            $lblDetailsBody.Text = 'Select an instance from the list to view details.'
            & $renderGameSpecificEditor $null $ForceEditorRefresh
            return
        }

        $game = if (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue) {
            Get-UGSMGameById -Id $instance.GameId
        }
        else { $null }

        $gameName = if ($game) { [string]$game.Name } else { [string]$instance.GameId }
        $portsText = '-'
        if ($instance.Ports) {
            $parts = @()
            foreach ($prop in $instance.Ports.PSObject.Properties) {
                $parts += ('{0}={1}' -f $prop.Name, $prop.Value)
            }
            if ($parts.Count -gt 0) {
                $portsText = ($parts -join ', ')
            }
        }

        $modsText = if ($instance.Mods -and @($instance.Mods).Count -gt 0) {
            (@($instance.Mods) -join ', ')
        }
        else {
            'None'
        }

        $lblDetailsTitle.Text = [string]$instance.Name
        $lblDetailsBody.Text = @(
            ('Game: ' + $gameName)
            ('Status: ' + [string]$instance.Status)
            ('Map: ' + [string]$instance.Map)
            ('Install Path: ' + [string]$instance.InstallPath)
            ('Ports: ' + $portsText)
            ('Mods: ' + $modsText)
            ('PID: ' + $(if ($null -ne $instance.Pid) { [string]$instance.Pid } else { 'Not running' }))
        ) -join [Environment]::NewLine

        & $setArtForGame $game
        & $renderGameSpecificEditor $instance $ForceEditorRefresh
    }.GetNewClosure()

    $applyPageState = {
        param(
            [object]$state
        )

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('applyPageState start. State selected=' + (Get-UGSMInstancesUIInstanceText $(if ($state) { $state.SelectedInstance } else { $null })))

        $currentPageData = if ($state -and $state.PSObject.Properties['PageData'] -and $state.PageData) {
            $state.PageData
        }
        else {
            if (Get-Command Get-UGSMInstancesPageData -ErrorAction SilentlyContinue) {
                Get-UGSMInstancesPageData
            }
            else {
                $pageData
            }
        }

        $script:UGSMInstancesCurrentPageData = $currentPageData

        $currentSelected = if ($state -and $state.PSObject.Properties['SelectedInstance']) {
            $state.SelectedInstance
        }
        else {
            $null
        }

        & $SetInstancesPageSelectedState $currentSelected

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('applyPageState currentSelected=' + (Get-UGSMInstancesUIInstanceText $currentSelected) + '; Current page instances=' + [string]@($currentPageData.Instances).Count)

        & $refreshHeader
        & $refreshSelected $currentSelected

        if ($page.Tag -and ((($page.Tag -is [hashtable]) -and $page.Tag.ContainsKey('RefreshShell')) -or $page.Tag.PSObject.Properties['RefreshShell']) -and $page.Tag.RefreshShell -is [scriptblock]) {
            Write-UGSMInstancesUILog -Level 'DEBUG' -Message 'applyPageState invoking RefreshShell'
            & $page.Tag.RefreshShell
        }

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('applyPageState end. AppState selected=' + (Get-UGSMInstancesUIInstanceText $AppState.SelectedInstance))
    }.GetNewClosure()

    $refreshList = {
        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('refreshList start. AppState selected=' + (Get-UGSMInstancesUIInstanceText $AppState.SelectedInstance) + '; SelectedInstanceId=' + [string]$AppState.SelectedInstanceId)
        $currentData = if ($script:UGSMInstancesCurrentPageData) { $script:UGSMInstancesCurrentPageData } else { $pageData }
        $selectedInstance = $null

        if ($AppState.SelectedInstanceId) {
            $selectedInstance = @($currentData.Instances | Where-Object { [string]$_.Id -eq [string]$AppState.SelectedInstanceId } | Select-Object -First 1)
        }
        if (-not $selectedInstance -and $AppState.SelectedInstance) {
            $selectedInstance = @($currentData.Instances | Where-Object { [string]$_.Name -eq [string]$AppState.SelectedInstance.Name } | Select-Object -First 1)
        }

        if ($null -ne $selectedInstance) {
            & $refreshSelected $selectedInstance
        }
        else {
            $lblDetailsTitle.Text = 'No instance selected'
            $lblDetailsBody.Text = 'Select an instance from the left sidebar to view details.'
            & $renderGameSpecificEditor $null
        }
    }.GetNewClosure()

    $setSelectedInstance = {
        param(
            [object]$instance
        )

        $newEditorKey = & $getInstanceEditorKey $instance
        $isSameEditorSelection = ($uiRenderState.EditorKey -eq $newEditorKey)

        Write-UGSMInstancesUILog -Level 'INFO' -Message ('Selected instance changed from Instances page. Instance=' + (Get-UGSMInstancesUIInstanceText $instance))

        & $SetInstancesPageSelectedState $instance

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('setSelectedInstance AppState now ' + (Get-UGSMInstancesUIInstanceText $AppState.SelectedInstance))

        if ($isSameEditorSelection) {
            Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('Selected instance already has current editor. Skipping forced editor rebuild. EditorKey={0}' -f $newEditorKey)
            & $refreshSelected $AppState.SelectedInstance $false
        }
        else {
            & $refreshSelected $AppState.SelectedInstance $true
        }

        if ($page.Tag -and ((($page.Tag -is [hashtable]) -and $page.Tag.ContainsKey('RefreshShell')) -or $page.Tag.PSObject.Properties['RefreshShell']) -and $page.Tag.RefreshShell -is [scriptblock]) {
            Write-UGSMInstancesUILog -Level 'DEBUG' -Message 'applyPageState invoking RefreshShell'
            & $page.Tag.RefreshShell
        }

        Write-UGSMInstancesUILog -Level 'DEBUG' -Message ('applyPageState end. AppState selected=' + (Get-UGSMInstancesUIInstanceText $AppState.SelectedInstance))
    }.GetNewClosure()

    $refreshAll = {
        Write-UGSMInstancesUILog -Level 'DEBUG' -Message 'refreshAll invoked'
        $refreshResult = & $GetRefreshedState
        & $applyPageState $refreshResult

        $lblFooter.Text = 'Instances page loaded'
    }.GetNewClosure()

    $PromptForText = {
        param(
            [string]$Title,
            [string]$Prompt,
            [string]$DefaultValue = ''
        )

        Add-Type -AssemblyName Microsoft.VisualBasic
        return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $DefaultValue)
    }.GetNewClosure()

    $invokeStart = {
        $selectedInstance = & $getSelectedInstance
        if ($null -eq $selectedInstance) {
            $lblFooter.Text = 'Select an instance first.'
            return
        }

        $actionWatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-UGSMInstancesUILog -Level 'INFO' -Message ('Start requested from Instances page. InstanceId={0}; Name={1}; GameId={2}' -f [string]$selectedInstance.Id, [string]$selectedInstance.Name, [string]$selectedInstance.GameId)
        try {
            $result = if (Get-Command Start-UGSMInstance -ErrorAction SilentlyContinue) {
                [pscustomobject]@{ UpdatedInstance = (Start-UGSMInstance -Id $selectedInstance.Id); SelectedInstance = $null }
            }
            elseif (Get-Command Invoke-UGSMInstanceAction -ErrorAction SilentlyContinue) {
                Invoke-UGSMInstanceAction -Action Start -AppState $AppState -Id $selectedInstance.Id
            }
            else {
                throw 'Start service is not available.'
            }

            if ($result -and $result.SelectedInstance) {
                & $SetInstancesPageSelectedState $result.SelectedInstance
            }
            elseif ($result -and $result.UpdatedInstance) {
                & $SetInstancesPageSelectedState $result.UpdatedInstance
            }

            & $refreshAll
            $actionWatch.Stop()
            Write-UGSMInstancesUILog -Level 'INFO' -Message ('Start completed from Instances page. InstanceId={0}; DurationMs={1}' -f [string]$selectedInstance.Id, $actionWatch.ElapsedMilliseconds)
            $lblFooter.Text = ('Started: ' + [string]$AppState.SelectedInstance.Name)
        }
        catch {
            $actionWatch.Stop()
            Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Start failed from Instances page. InstanceId={0}; DurationMs={1}' -f [string]$selectedInstance.Id, $actionWatch.ElapsedMilliseconds) -Exception $_.Exception
            $lblFooter.Text = ('Start failed: ' + $_.Exception.Message)
        }
    }.GetNewClosure()

    $invokeStop = {
        $selectedInstance = & $getSelectedInstance
        if ($null -eq $selectedInstance) {
            $lblFooter.Text = 'Select an instance first.'
            return
        }

        $actionWatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-UGSMInstancesUILog -Level 'INFO' -Message ('Stop requested from Instances page. InstanceId={0}; Name={1}; GameId={2}' -f [string]$selectedInstance.Id, [string]$selectedInstance.Name, [string]$selectedInstance.GameId)
        try {
            $result = if (Get-Command Stop-UGSMInstance -ErrorAction SilentlyContinue) {
                [pscustomobject]@{ UpdatedInstance = (Stop-UGSMInstance -Id $selectedInstance.Id); SelectedInstance = $null }
            }
            elseif (Get-Command Invoke-UGSMInstanceAction -ErrorAction SilentlyContinue) {
                Invoke-UGSMInstanceAction -Action Stop -AppState $AppState -Id $selectedInstance.Id
            }
            else {
                throw 'Stop service is not available.'
            }

            if ($result -and $result.SelectedInstance) {
                & $SetInstancesPageSelectedState $result.SelectedInstance
            }
            elseif ($result -and $result.UpdatedInstance) {
                & $SetInstancesPageSelectedState $result.UpdatedInstance
            }

            & $refreshAll
            $actionWatch.Stop()
            Write-UGSMInstancesUILog -Level 'INFO' -Message ('Stop completed from Instances page. InstanceId={0}; DurationMs={1}' -f [string]$selectedInstance.Id, $actionWatch.ElapsedMilliseconds)
            $lblFooter.Text = ('Stopped: ' + [string]$AppState.SelectedInstance.Name)
        }
        catch {
            $actionWatch.Stop()
            Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Stop failed from Instances page. InstanceId={0}; DurationMs={1}' -f [string]$selectedInstance.Id, $actionWatch.ElapsedMilliseconds) -Exception $_.Exception
            $lblFooter.Text = ('Stop failed: ' + $_.Exception.Message)
        }
    }.GetNewClosure()

    # Events

    $btnStart.Add_Click({ Write-UGSMInstancesUILog -Level 'INFO' -Message 'Profile Start button clicked.'; & $invokeStart }.GetNewClosure())
    $btnStop.Add_Click({ Write-UGSMInstancesUILog -Level 'INFO' -Message 'Profile Stop button clicked.'; & $invokeStop }.GetNewClosure())
    $btnEdit.Add_Click({
            $selectedInstance = & $getSelectedInstance
            Write-UGSMInstancesUILog -Level 'INFO' -Message ('Profile Edit button clicked. Instance=' + (Get-UGSMInstancesUIInstanceText $selectedInstance))
            if ($null -eq $selectedInstance) {
                $lblFooter.Text = 'Select an instance first.'
                return
            }

            $newName = (& $PromptForText 'Edit Profile' 'Update the profile name.' ([string]$selectedInstance.Name))
            if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq [string]$selectedInstance.Name) {
                return
            }

            try {
                $updatedInstance = [pscustomobject]@{
                    Id          = [string]$selectedInstance.Id
                    Name        = [string]$newName
                    GameId      = [string]$selectedInstance.GameId
                    InstallPath = [string]$selectedInstance.InstallPath
                    Map         = [string]$selectedInstance.Map
                    Ports       = $selectedInstance.Ports
                    Mods        = @($selectedInstance.Mods)
                    Status      = [string]$selectedInstance.Status
                    Pid         = $selectedInstance.Pid
                }

                Write-UGSMInstancesUILog -Level 'INFO' -Message ('Profile rename save requested. InstanceId={0}; OldName={1}; NewName={2}' -f [string]$selectedInstance.Id, [string]$selectedInstance.Name, [string]$newName)
                $updatedInstance = Save-UGSMInstance -Instance $updatedInstance
                Write-UGSMInstancesUILog -Level 'INFO' -Message ('Profile rename saved. InstanceId={0}; NewName={1}' -f [string]$updatedInstance.Id, [string]$updatedInstance.Name)
                & $refreshAll

                $items = @($script:UGSMInstancesCurrentPageData.Instances)

                $lblFooter.Text = ('Renamed profile to: ' + [string]$updatedInstance.Name)
            }
            catch {
                Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Profile edit failed. Instance=' + (Get-UGSMInstancesUIInstanceText $selectedInstance)) -Exception $_.Exception
                $lblFooter.Text = ('Edit failed: ' + $_.Exception.Message)
            }
        }.GetNewClosure())
    $btnOpen.Add_Click({
            $selectedInstance = & $getSelectedInstance
            Write-UGSMInstancesUILog -Level 'INFO' -Message ('Open profile folder clicked. Instance=' + (Get-UGSMInstancesUIInstanceText $selectedInstance))
            if ($null -eq $selectedInstance) {
                $lblFooter.Text = 'Select a profile first.'
                return
            }

            $targetPath = [string]$selectedInstance.ProfilePath
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                $lblFooter.Text = 'This profile does not have a profile path yet.'
                return
            }

            if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
                $lblFooter.Text = 'Profile folder does not exist yet.'
                return
            }

            try {
                Start-Process -FilePath $targetPath | Out-Null
                Write-UGSMInstancesUILog -Level 'INFO' -Message ('Opened profile folder. InstanceId={0}' -f [string]$selectedInstance.Id)
                $lblFooter.Text = ('Opened profile folder: ' + $targetPath)
            }
            catch {
                Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Open profile folder failed. InstanceId={0}' -f [string]$selectedInstance.Id) -Exception $_.Exception
                $lblFooter.Text = ('Open Folder failed: ' + $_.Exception.Message)
            }
        }.GetNewClosure())
    $btnRemove.Add_Click({
            $selectedInstance = & $getSelectedInstance
            Write-UGSMInstancesUILog -Level 'INFO' -Message ('Remove Profile button clicked. Instance=' + (Get-UGSMInstancesUIInstanceText $selectedInstance))
            if ($null -eq $selectedInstance) {
                $lblFooter.Text = 'Select a profile first.'
                return
            }

            try {
                if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Local -ErrorAction SilentlyContinue)) {
                    $UpdateStatusBarUI = { param([string]$Message) }.GetNewClosure()
                }

                $removeWatch = [System.Diagnostics.Stopwatch]::StartNew()
                $removed = Remove-UGSMInstance -Id $selectedInstance.Id
                $removeWatch.Stop()
                Write-UGSMInstancesUILog -Level 'INFO' -Message ('Remove profile completed from Instances page. InstanceId={0}; Removed={1}; DurationMs={2}' -f [string]$selectedInstance.Id, [bool]($removed -and $removed.Removed), $removeWatch.ElapsedMilliseconds)

                if ($removed -and $removed.Removed) {
                    & $SetInstancesPageSelectedState $null
                }

                & $refreshAll

                if ($removed -and $removed.Removed) {
                    $lblFooter.Text = ('Removed profile: ' + [string]$selectedInstance.Name)
                }
                else {
                    $lblFooter.Text = 'No profile data was removed.'
                }
            }
            catch {
                Write-UGSMInstancesUILog -Level 'ERROR' -Message ('Remove profile failed from Instances page. Instance=' + (Get-UGSMInstancesUIInstanceText $selectedInstance)) -Exception $_.Exception
                $lblFooter.Text = ('Remove failed: ' + $_.Exception.Message)
            }
        }.GetNewClosure())

    $page.Tag = [pscustomobject]@{
        RefreshAll             = $refreshAll
        RefreshSelected        = $refreshList
        GetSelected            = $getSelectedInstance
        SetSelectedInstance    = $setSelectedInstance
        RenderSelectedInstance = $setSelectedInstance
        RenderState            = $applyPageState
        RefreshShell           = $null
    }

    # Initial render
    Write-UGSMInstancesUILog -Level 'DEBUG' -Message 'Initial render starting.'
    $null = & $refreshAll
    $pageCreateWatch.Stop()
    Write-UGSMInstancesUILog -Level 'INFO' -Message ('Instances page creation finished. DurationMs={0}' -f $pageCreateWatch.ElapsedMilliseconds)

    if (-not ($page -is [System.Windows.Forms.Control])) {
        throw 'New-UGSMInstancesPage did not produce a WinForms control.'
    }

    return $page
}
