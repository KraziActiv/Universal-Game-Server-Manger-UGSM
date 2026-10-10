# Test Helpers

# ============================================================
# UGSM Theme Colors Can add more if needed.
# ============================================================
$global:UGSM_ColorText = [System.Drawing.Color]::White
$global:UGSM_ColorBackground = [System.Drawing.ColorTranslator]::FromHtml('#071120')
$global:UGSM_ColorPanelBackground = [System.Drawing.ColorTranslator]::FromHtml('#0B1728')
$global:UGSM_ColorInputBackground = [System.Drawing.ColorTranslator]::FromHtml('#0A1320')
$global:UGSM_ColorMutedText = [System.Drawing.ColorTranslator]::FromHtml('#B8C7D9')
$global:UGSM_ColorPrimary = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$global:UGSM_ColorSuccess = [System.Drawing.ColorTranslator]::FromHtml('#22C55E')
$global:UGSM_ColorDanger = [System.Drawing.ColorTranslator]::FromHtml('#EF4444')
$global:UGSM_ColorNeutral = [System.Drawing.ColorTranslator]::FromHtml('#334155')
$global:UGSM_ColorCaution = [System.Drawing.ColorTranslator]::FromHtml('#F59E0B')
$global:UGSM_ColorSpecial = [System.Drawing.ColorTranslator]::FromHtml('#FF00FF')
$global:UGSM_ColorBack = [System.Drawing.ColorTranslator]::FromHtml('#475569')
$global:UGSM_ColorGrid = [System.Drawing.ColorTranslator]::FromHtml('#20344D')
$global:UGSM_ColorGridHeader = [System.Drawing.ColorTranslator]::FromHtml('#1C2430')
$global:UGSM_ColorGridSelection = [System.Drawing.ColorTranslator]::FromHtml('#2D5AA0')
$global:UGSM_ColorSurfaceAlt = [System.Drawing.ColorTranslator]::FromHtml('#1B2636')
$global:UGSM_ColorBorder = [System.Drawing.ColorTranslator]::FromHtml('#20344D')
$global:UGSM_ColorTopBar = [System.Drawing.ColorTranslator]::FromHtml('#0A101A')
$global:UGSM_ColorSidebar = [System.Drawing.ColorTranslator]::FromHtml('#0F1724')
$global:UGSM_ColorSecondaryPanel = [System.Drawing.ColorTranslator]::FromHtml('#0F1A2A')
$global:UGSM_ColorCanvas = [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
$global:UGSM_ColorHealthyBackground = [System.Drawing.ColorTranslator]::FromHtml('#0F2419')
$global:UGSM_ColorHealthyBorder = [System.Drawing.ColorTranslator]::FromHtml('#1F7A3D')
$global:UGSM_ColorStarting = [System.Drawing.ColorTranslator]::FromHtml('#60A5FA')
$global:UGSM_ColorSoftDanger = [System.Drawing.ColorTranslator]::FromHtml('#F87171')
$global:UGSM_ColorBannerBackground = [System.Drawing.ColorTranslator]::FromHtml('#132032')
$global:UGSM_ColorBannerText = [System.Drawing.ColorTranslator]::FromHtml('#D7E2EE')
$global:UGSM_ColorSurfaceDeep = [System.Drawing.ColorTranslator]::FromHtml('#101A2A')
$global:UGSM_ColorStatusBarBackground = [System.Drawing.ColorTranslator]::FromHtml('#0D1624')
$global:UGSM_ColorButtonStopMuted = [System.Drawing.ColorTranslator]::FromHtml('#7F1D1D')
$global:UGSM_ColorButtonRemoveMuted = [System.Drawing.ColorTranslator]::FromHtml('#991B1B')
$global:UGSM_ColorBrandTextDark = [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
$global:UGSM_ColorSuccessSurface = [System.Drawing.ColorTranslator]::FromHtml('#10271B')
$global:UGSM_ColorSuccessBorder = [System.Drawing.ColorTranslator]::FromHtml('#1F4F31')
$global:UGSM_ColorSuccessTextSoft = [System.Drawing.ColorTranslator]::FromHtml('#B7E4C7')
$global:UGSM_ColorSuccessTextBright = [System.Drawing.ColorTranslator]::FromHtml('#87E3A8')

$global:UGSM_ColorSurfaceMuted = [System.Drawing.ColorTranslator]::FromHtml('#2A313B')
$global:UGSM_ColorFooterBackground = [System.Drawing.ColorTranslator]::FromHtml('#10161D')
$global:UGSM_ColorFooterBorder = [System.Drawing.ColorTranslator]::FromHtml('#16232E')
$global:UGSM_ColorArtPlaceholder = [System.Drawing.ColorTranslator]::FromHtml('#111827')
$global:UGSM_ColorPageBackground = [System.Drawing.ColorTranslator]::FromHtml('#0C1218')
$global:UGSM_ColorArtBackground = [System.Drawing.ColorTranslator]::FromHtml('#0E1620')

$global:UGSM_ColorDangerSurface = [System.Drawing.ColorTranslator]::FromHtml('#A63A2D')
$global:UGSM_ColorDangerMutedBackground = [System.Drawing.ColorTranslator]::FromHtml('#3A1F24')

$global:UGSM_ColorErrorTextSoft = [System.Drawing.ColorTranslator]::FromHtml('#FCA5A5')
$global:UGSM_ColorHeaderBackground = [System.Drawing.ColorTranslator]::FromHtml('#112333')

$global:UGSM_ColorCPU = [System.Drawing.ColorTranslator]::FromHtml('#93C5FD')
$global:UGSM_ColorRAM = [System.Drawing.ColorTranslator]::FromHtml('#C4B5FD')
$global:UGSM_ColorRunning = [System.Drawing.ColorTranslator]::FromHtml('#86EFAC')
$global:UGSM_ColorCapacity = [System.Drawing.ColorTranslator]::FromHtml('#FCD34D')

# Canonical aliases used by game modules and shared helpers.
# Keep these aliases here so game files do not define their own colors.
$global:UGSM_ColorSurface = $global:UGSM_ColorPanelBackground
$global:UGSM_ColorAccent = $global:UGSM_ColorSuccess
$global:UGSM_ColorButton = $global:UGSM_ColorNeutral
$global:UGSM_ColorInput = $global:UGSM_ColorInputBackground





#Future removal of these redirectors so only the colors above are used.


$global:UGSM_ColorDangerSoft = $global:UGSM_ColorSoftDanger
$global:UGSM_ColorCanvasBackground = $global:UGSM_ColorCanvas
$global:UGSM_ColorCanvasBorder = $global:UGSM_ColorBorder
$global:UGSM_ColorHealthy = $global:UGSM_ColorSuccess
$global:UGSM_ColorBannerTextPrimary = $global:UGSM_ColorText
$global:UGSM_ColorBannerTextSecondary = $global:UGSM_ColorBannerText
$global:UGSM_ColorChartBackground = $global:UGSM_ColorBackground
$global:UGSM_ColorChartGrid = $global:UGSM_ColorGrid
$global:UGSM_ColorChartAxis = $global:UGSM_ColorBack
$global:UGSM_ColorChartLabel = $global:UGSM_ColorMutedText
$global:UGSM_ColorChartTitle = $global:UGSM_ColorText
$global:UGSM_ColorChartLine = $global:UGSM_ColorPrimary
$global:UGSM_ColorButtonNew = $global:UGSM_ColorPrimary
$global:UGSM_ColorButtonAdd = $global:UGSM_ColorPrimary
$global:UGSM_ColorButtonApply = $global:UGSM_ColorCaution
$global:UGSM_ColorButtonSave = $global:UGSM_ColorSuccess
$global:UGSM_ColorButtonRemove = $global:UGSM_ColorDanger
$global:UGSM_ColorButtonRefresh = $global:UGSM_ColorNeutral
$global:UGSM_ColorButtonLoad = $global:UGSM_ColorNeutral
$global:UGSM_ColorButtonOpenRaw = $global:UGSM_ColorNeutral
$global:UGSM_ColorButtonPrettyPrint = $global:UGSM_ColorSpecial
$global:UGSM_ColorButtonBack = $global:UGSM_ColorBack



function Get-UGSMDisplayPath {
    param([string]$Path, [int]$MaxLength = 24)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    if ($Path.Length -le $MaxLength) {
        return $Path
    }

    return ('...' + $Path.Substring($Path.Length - ($MaxLength - 3)))
}

# file Helper

Add-Type -AssemblyName System.Drawing

function global:New-UGSMColor {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Hex
    )

    if ($Hex -is [System.Drawing.Color]) {
        return [System.Drawing.Color]$Hex
    }

    $hexText = [string]$Hex
    if ([string]::IsNullOrWhiteSpace($hexText)) {
        return [System.Drawing.Color]::Transparent
    }

    try {
        return [System.Drawing.ColorTranslator]::FromHtml($hexText)
    }
    catch {
        return [System.Drawing.Color]::Transparent
    }
}



function global:ConvertTo-UGSMSafeColor {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Color,

        [System.Drawing.Color]$Fallback = [System.Drawing.Color]::Transparent
    )

    if ($Color -is [System.Drawing.Color]) {
        return [System.Drawing.Color]$Color
    }

    if ($null -eq $Color) {
        return $Fallback
    }

    $text = [string]$Color
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }

    try {
        return [System.Drawing.ColorTranslator]::FromHtml($text)
    }
    catch {
        return $Fallback
    }
}

# ============================================================
# Shared WinForms UI Controls
# Main form and page files should use these instead of defining
# their own labels/buttons/panels. New shared colors should be
# added in the theme section above, not inside page files.
# ============================================================

if (-not (Get-Variable -Name 'UGSM_EnableVerboseUILogging' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_EnableVerboseUILogging = $false
}

function global:Write-UGSMTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$LogName = 'UGSM_InstanceSelectionTrace.log'
    )

    # Kept as a compatibility wrapper so old page calls do not create
    # their own trace files anymore. UI trace output now routes through
    # the normal UGSM logger only when verbose UI logging is enabled.
    $enabledByEnv = ([string]$env:UGSM_ENABLE_TRACE -eq '1')
    $enabledByScript = $false
    try { $enabledByScript = [bool]$script:UGSM_EnableVerboseUILogging } catch { $enabledByScript = $false }

    if (-not $enabledByEnv -and -not $enabledByScript) {
        return
    }

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level 'DEBUG' -Category $Component -Message $Message
        return
    }

    try { Write-Verbose ("[{0}] {1}" -f $Component, $Message) } catch {}
}

function global:Format-UGSMTraceInstance {
    param(
        [AllowNull()]
        [object]$Instance
    )

    if (-not $Instance) {
        return '<null>'
    }

    $id = if ($Instance.PSObject.Properties['Id']) { [string]$Instance.Id } else { '' }
    $name = if ($Instance.PSObject.Properties['Name']) { [string]$Instance.Name } else { '' }
    $gameId = if ($Instance.PSObject.Properties['GameId']) { [string]$Instance.GameId } else { '' }
    $status = if ($Instance.PSObject.Properties['Status']) { [string]$Instance.Status } else { '' }
    $instancePidText = if ($Instance.PSObject.Properties['Pid']) { [string]$Instance.Pid } else { '' }
    return ('Id={0}; Name={1}; GameId={2}; Status={3}; Pid={4}' -f $id, $name, $gameId, $status, $instancePidText)
}

function global:New-UGSMLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 120,
        [int]$Height = 22,
        [AllowNull()][object]$Color = $global:UGSM_ColorText,
        [float]$FontSize = 10,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [string]$Align = 'MiddleLeft'
    )

    $resolvedColor = ConvertTo-UGSMSafeColor -Color $Color -Fallback $global:UGSM_ColorText

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = $resolvedColor
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize, $Style)
    $label.TextAlign = [System.Drawing.ContentAlignment]::$Align
    return $label
}
function global:New-UGSMButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 95,
        [int]$Height = 34,
        [AllowNull()][object]$BackColor = $global:UGSM_ColorNeutral,
        [AllowNull()][object]$ForeColor = $global:UGSM_ColorText,
        [bool]$Flat = $true
    )

    $resolvedBackColor = ConvertTo-UGSMSafeColor -Color $BackColor -Fallback $global:UGSM_ColorNeutral
    $resolvedForeColor = ConvertTo-UGSMSafeColor -Color $ForeColor -Fallback $global:UGSM_ColorText

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.BackColor = $resolvedBackColor
    $button.ForeColor = $resolvedForeColor
    $button.FlatStyle = if ($Flat) { 'Flat' } else { 'Standard' }
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    $button.TabStop = $false
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    if ($Flat) {
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.MouseOverBackColor = $button.BackColor
        $button.FlatAppearance.MouseDownBackColor = $button.BackColor
    }

    return $button
}
function global:New-UGSMPanel {
    param(
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 100,
        [int]$Height = 100,
        [AllowNull()][object]$BackColor = $global:UGSM_ColorPanelBackground,
        [AllowNull()][object]$BorderColor = [System.Drawing.Color]::Transparent
    )

    $resolvedBackColor = ConvertTo-UGSMSafeColor -Color $BackColor -Fallback $global:UGSM_ColorPanelBackground
    $resolvedBorderColor = ConvertTo-UGSMSafeColor -Color $BorderColor -Fallback ([System.Drawing.Color]::Transparent)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $resolvedBackColor

    if ($resolvedBorderColor -ne [System.Drawing.Color]::Transparent) {
        $panel.Add_Paint({
                param($sender, $e)

                if (-not $sender -or $sender.IsDisposed) { return }
                if ($sender.Width -le 1 -or $sender.Height -le 1) { return }

                $pen = $null
                try {
                    $pen = New-Object System.Drawing.Pen($resolvedBorderColor)
                    $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
                }
                finally {
                    if ($pen) { $pen.Dispose() }
                }
            }.GetNewClosure())
    }

    return $panel
}
function global:Add-CardHeader {
    param(
        [System.Windows.Forms.Control]$Card,
        [string]$Title,
        [string]$Subtitle = ''
    )

    $titleLabel = New-UGSMLabel -Text $Title -X 16 -Y 10 -Width ($Card.Width - 32) -Height 22 -Color $global:UGSM_ColorText -FontSize 11 -Style Bold
    $titleLabel.AutoSize = $false

    [void]$Card.Controls.Add($titleLabel)

    if ($Subtitle) {
        $subtitleLabel = New-UGSMLabel -Text $Subtitle -X 16 -Y 31 -Width ($Card.Width - 20) -Height 16 -Color $global:UGSM_ColorMutedText -FontSize 8.5
        $subtitleLabel.AutoSize = $false
        [void]$Card.Controls.Add($subtitleLabel)
    }
}

function global:Test-UGSMTagCallback {
    param(
        $Tag,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Tag) { return $false }

    if ($Tag -is [hashtable]) {
        return ($Tag.ContainsKey($Name) -and $Tag[$Name] -is [scriptblock])
    }

    $prop = $null
    try {
        $prop = $Tag.PSObject.Properties[$Name]
    }
    catch {
        $prop = $null
    }

    return ($null -ne $prop -and $Tag.$Name -is [scriptblock])
}



# ============================================================
# Shared Shell / Layout Helpers
# These keep the main form and page files from rebuilding the same
# WinForms boilerplate over and over. Keep new shared colors in the
# theme block above and use Get-UGSMTheme inside UI files.
# ============================================================

function global:Get-UGSMTheme {
    [CmdletBinding()]
    param()

    return @{
        # Short canonical names used by template/game editors
        Background     = $global:UGSM_ColorBackground
        Surface        = $global:UGSM_ColorSurface
        Input          = $global:UGSM_ColorInputBackground
        Text           = $global:UGSM_ColorText
        Muted          = $global:UGSM_ColorMutedText
        Accent         = $global:UGSM_ColorAccent
        AccentBlue     = $global:UGSM_ColorPrimary
        AccentYellow   = $global:UGSM_ColorCaution
        AccentRed      = $global:UGSM_ColorDanger
        Button         = $global:UGSM_ColorNeutral
        Danger         = $global:UGSM_ColorDanger
        Success        = $global:UGSM_ColorSuccess
        Border         = $global:UGSM_ColorBorder

        # Shell/page names kept for existing pages
        WindowBg       = $global:UGSM_ColorBackground
        TopBar         = $global:UGSM_ColorTopBar
        Sidebar        = $global:UGSM_ColorSidebar
        SecondaryPanel = $global:UGSM_ColorSecondaryPanel
        SurfaceAlt     = $global:UGSM_ColorSurfaceAlt
    }
}

function global:Enable-UGSMDoubleBuffer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.Control]$Control
    )

    if (-not $Control -or $Control.IsDisposed) { return }

    try {
        $prop = $Control.GetType().GetProperty(
            'DoubleBuffered',
            [System.Reflection.BindingFlags]'Instance,NonPublic'
        )
        if ($prop) {
            $prop.SetValue($Control, $true, $null)
        }
    }
    catch {
        # Double buffering is a UI polish optimization only. Never fail startup for it.
    }
}

function global:New-UGSMDockPanel {
    [CmdletBinding()]
    param(
        [string]$Dock = 'Fill',
        [System.Drawing.Color]$BackColor = $global:UGSM_ColorPanelBackground,
        [System.Windows.Forms.Padding]$Margin = (New-Object System.Windows.Forms.Padding(0)),
        [System.Windows.Forms.Padding]$Padding = (New-Object System.Windows.Forms.Padding(0)),
        [switch]$DoubleBuffered
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = $Dock
    $panel.Margin = $Margin
    $panel.Padding = $Padding
    $panel.BackColor = $BackColor

    if ($DoubleBuffered) {
        Enable-UGSMDoubleBuffer -Control $panel
    }

    return $panel
}

function global:New-UGSMFlowPanel {
    [CmdletBinding()]
    param(
        [string]$Dock = 'Fill',
        [System.Drawing.Color]$BackColor = ([System.Drawing.Color]::Transparent),
        [System.Windows.Forms.Padding]$Margin = (New-Object System.Windows.Forms.Padding(0)),
        [System.Windows.Forms.Padding]$Padding = (New-Object System.Windows.Forms.Padding(0)),
        [System.Windows.Forms.FlowDirection]$FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight,
        [bool]$WrapContents = $false,
        [bool]$AutoScroll = $false
    )

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = $Dock
    $panel.Margin = $Margin
    $panel.Padding = $Padding
    $panel.WrapContents = $WrapContents
    $panel.AutoScroll = $AutoScroll
    $panel.FlowDirection = $FlowDirection
    $panel.BackColor = $BackColor
    return $panel
}

function global:New-UGSMListBox {
    [CmdletBinding()]
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Color]$BackColor = $global:UGSM_ColorBackground,
        [System.Drawing.Color]$ForeColor = $global:UGSM_ColorText,
        [float]$FontSize = 10
    )

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point($X, $Y)
    $list.Size = New-Object System.Drawing.Size($Width, $Height)
    $list.BackColor = $BackColor
    $list.ForeColor = $ForeColor
    $list.BorderStyle = 'None'
    $list.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize)
    $list.IntegralHeight = $false
    return $list
}

function global:New-UGSMMetricCard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Definition,

        [int]$Index = 0,
        [int]$Count = 1,
        [int]$Gap = 12,
        [int]$ValueY = 64,
        [int]$MetaY = 92,
        [System.Drawing.Color]$BackColor = $global:UGSM_ColorPanelBackground,
        [System.Drawing.Color]$BorderColor = $global:UGSM_ColorBorder,
        [System.Drawing.Color]$ValueColor = $global:UGSM_ColorText,
        [System.Drawing.Color]$MetaColor = $global:UGSM_ColorMutedText
    )

    $slot = New-UGSMDockPanel -Dock 'Fill' -BackColor ([System.Drawing.Color]::Transparent)
    $slot.Margin = if ($Index -eq ($Count - 1)) {
        New-Object System.Windows.Forms.Padding(0)
    }
    else {
        New-Object System.Windows.Forms.Padding(0, 0, $Gap, 0)
    }

    $card = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $BackColor -BorderColor $BorderColor
    $card.Dock = 'Fill'
    [void]$slot.Controls.Add($card)

    Add-CardHeader -Card $card -Title ([string]$Definition.Title) -Subtitle ([string]$Definition.Sub)

    $valueLabel = New-UGSMLabel -Text ([string]$Definition.Value) -X 16 -Y $ValueY -Width 300 -Height 28 -FontSize 17 -Style Bold -Color $ValueColor
    $metaLabel = New-UGSMLabel -Text ([string]$Definition.Meta) -X 16 -Y $MetaY -Width 300 -Height 18 -FontSize 8.5 -Color $MetaColor
    [void]$card.Controls.Add($valueLabel)
    [void]$card.Controls.Add($metaLabel)

    $accent = New-Object System.Windows.Forms.Panel
    $accent.Dock = 'Left'
    $accent.Width = 4
    $accent.BackColor = New-UGSMColor $Definition.Accent
    [void]$card.Controls.Add($accent)
    $accent.BringToFront()

    return [pscustomobject]@{
        Slot       = $slot
        Card       = $card
        ValueLabel = $valueLabel
        MetaLabel  = $metaLabel
        Accent     = $accent
    }
}

function global:Set-UGSMAnalyticsChart {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.Panel]$PageHost,

        [Parameter(Mandatory)]
        [int[]]$Values,

        [System.Drawing.Color]$LineColor = $global:UGSM_ColorChartLine,

        [string]$ChartTitle = 'Usage'
    )

    $PageHost.Tag = @{
        Values     = @($Values)
        LineColor  = $LineColor
        ChartTitle = $ChartTitle
    }

    $PageHost.Add_Paint({
            param($sender, $e)

            $chartData = $sender.Tag
            $values = @($chartData.Values)
            $lineColor = [System.Drawing.Color]$chartData.LineColor
            $chartTitle = [string]$chartData.ChartTitle

            $e.Graphics.Clear($global:UGSM_ColorChartBackground)
            $e.Graphics.SmoothingMode = 'AntiAlias'

            $gridPen = New-Object System.Drawing.Pen($global:UGSM_ColorChartGrid)
            $axisPen = New-Object System.Drawing.Pen($global:UGSM_ColorChartAxis)
            $labelBrush = New-Object System.Drawing.SolidBrush($global:UGSM_ColorChartLabel)
            $titleBrush = New-Object System.Drawing.SolidBrush($global:UGSM_ColorChartTitle)
            $font = New-Object System.Drawing.Font('Segoe UI', 8.0)
            $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)

            try {
                $leftPad = 34
                $rightPad = 34
                $topPad = 20
                $bottomPad = 30

                $plotLeft = $leftPad
                $plotTop = $topPad
                $plotWidth = [Math]::Max(20, $sender.Width - $leftPad - $rightPad)
                $plotHeight = [Math]::Max(20, $sender.Height - $topPad - $bottomPad)
                $plotRight = $plotLeft + $plotWidth
                $plotBottom = $plotTop + $plotHeight

                $levels = @(100, 75, 50, 25, 0)
                for ($i = 0; $i -lt $levels.Count; $i++) {
                    $value = $levels[$i]
                    $y = $plotTop + (($plotHeight / ($levels.Count - 1)) * $i)
                    $e.Graphics.DrawLine($gridPen, $plotLeft, $y, $plotRight, $y)
                    $e.Graphics.DrawString(($value.ToString() + '%'), $font, $labelBrush, 4, ($y - 7))
                }

                $e.Graphics.DrawLine($axisPen, $plotLeft, $plotTop, $plotLeft, $plotBottom)
                $e.Graphics.DrawLine($axisPen, $plotLeft, $plotBottom, $plotRight, $plotBottom)

                $e.Graphics.DrawString($chartTitle, $titleFont, $titleBrush, $plotLeft, 2)

                if ($values.Count -gt 0) {
                    $pen = New-Object System.Drawing.Pen($lineColor, 2)
                    $brush = New-Object System.Drawing.SolidBrush($lineColor)

                    try {
                        $max = [Math]::Max(100, ($values | Measure-Object -Maximum).Maximum)
                        $stepX = if ($values.Count -gt 1) { $plotWidth / ($values.Count - 1) } else { 0 }

                        $points = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'

                        for ($i = 0; $i -lt $values.Count; $i++) {
                            $x = $plotLeft + ($stepX * $i)
                            $y = $plotBottom - (([double]$values[$i] / $max) * $plotHeight)
                            $points.Add((New-Object System.Drawing.PointF([single]$x, [single]$y)))
                        }

                        if ($points.Count -gt 1) {
                            $e.Graphics.DrawLines($pen, $points.ToArray())
                        }

                        foreach ($pt in $points) {
                            $e.Graphics.FillEllipse($brush, $pt.X - 2.5, $pt.Y - 2.5, 5, 5)
                        }
                    }
                    finally {
                        $pen.Dispose()
                        $brush.Dispose()
                    }
                }
            }
            finally {
                $gridPen.Dispose()
                $axisPen.Dispose()
                $labelBrush.Dispose()
                $titleBrush.Dispose()
                $font.Dispose()
                $titleFont.Dispose()
            }
        })

    $PageHost.Invalidate()
}