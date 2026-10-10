# Analytics Page

function Test-UGSMAnalyticsUIVerboseLogging {
    [CmdletBinding()]
    param()

    try {
        if ((Get-Variable -Name 'UGSM_EnableVerboseAnalyticsUILogging' -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseAnalyticsUILogging) { return $true }
        if ([string]::Equals($env:UGSM_VERBOSE_ANALYTICS_UI, '1', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    catch { }

    return $false
}

function Write-UGSMAnalyticsUILog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception') -and $Exception) {
            Write-UGSMLog -Level $Level -Category 'AnalyticsUI' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'AnalyticsUI' -Message $Message
        }
        return
    }

    if ($Level -in @('WARN','ERROR','FATAL')) {
        Write-Warning ('[AnalyticsUI] {0}' -f $Message)
    }
}


function New-UGSMAnalyticsPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Theme,

        [object]$AppState
    )

    $pageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMAnalyticsUILog -Level 'INFO' -Message 'Analytics page creation started.'

    $pageData = if (Get-Command Get-UGSMAnalyticsPageData -ErrorAction SilentlyContinue) {
        Get-UGSMAnalyticsPageData -AppState $AppState
    }
    else {
        [pscustomobject]@{
            Summary          = [pscustomobject]@{
                TotalInstances      = 0
                RunningCount        = 0
                StartingCount       = 0
                StoppedCount        = 0
                CpuPercent          = 0
                RamPercent          = 0
                DiskPercent         = 0
                CapacityState       = 'Healthy'
                CapacityMessage     = 'No analytics data available.'
                InstallDiskText     = 'Unknown'
                CanStartMoreServers = $true
                LastUpdated         = $null
            }
            CpuSeries        = @(0)
            RamSeries        = @(0)
            DiskSeries       = @(0)
            Instances        = @()
            SelectedInstance = $null
            Alerts           = @('No analytics data available.')
            Events           = @('Waiting for analytics service')
        }
    }

    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'
    $page.Margin = New-Object System.Windows.Forms.Padding(0)
    $page.Padding = New-Object System.Windows.Forms.Padding(14, 14, 14, 18)
    $page.BackColor = $global:UGSM_ColorPageBackground

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.Margin = New-Object System.Windows.Forms.Padding(0)
    $root.Padding = New-Object System.Windows.Forms.Padding(0)
    $root.BackColor = $global:UGSM_ColorPageBackground
    $root.ColumnCount = 1
    $root.RowCount = 4
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 108)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 170)))
    [void]$page.Controls.Add($root)

    $header = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 56 -BackColor $global:UGSM_ColorBackground -BorderColor $global:UGSM_ColorBorder
    $header.Dock = 'Fill'
    $header.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$root.Controls.Add($header, 0, 0)

    $lblHeaderTitle = New-UGSMLabel -Text 'Analytics' -X 14 -Y 8 -Width 240 -Height 24 -FontSize 14 -Style Bold -Color $global:UGSM_ColorText
    $lblHeaderSummary = New-UGSMLabel -Text 'Live overview and trend placeholders for machine and instances' -X 14 -Y 30 -Width 900 -Height 18 -FontSize 8.5 -Color $global:UGSM_ColorCPU
    [void]$header.Controls.Add($lblHeaderTitle)
    [void]$header.Controls.Add($lblHeaderSummary)

    $summaryRow = New-Object System.Windows.Forms.TableLayoutPanel
    $summaryRow.Dock = 'Fill'
    $summaryRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $summaryRow.Padding = New-Object System.Windows.Forms.Padding(0)
    $summaryRow.BackColor = $global:UGSM_ColorPageBackground
    $summaryRow.ColumnCount = 4
    $summaryRow.RowCount = 1
    1..4 | ForEach-Object { [void]$summaryRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) }
    [void]$summaryRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.Controls.Add($summaryRow, 0, 1)

    $summaryCards = @()
    foreach ($i in 0..3) {
        $card = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
        $card.Dock = 'Fill'
        $card.Margin = New-Object System.Windows.Forms.Padding($(if ($i -lt 3) { 0 } else { 0 }), 0, $(if ($i -lt 3) { 10 } else { 0 }), 0)
        [void]$summaryRow.Controls.Add($card, $i, 0)
        $summaryCards += $card
    }

    $workspace = New-Object System.Windows.Forms.TableLayoutPanel
    $workspace.Dock = 'Fill'
    $workspace.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $workspace.Padding = New-Object System.Windows.Forms.Padding(0)
    $workspace.BackColor = $global:UGSM_ColorPageBackground
    $workspace.ColumnCount = 2
    $workspace.RowCount = 1
    [void]$workspace.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 260)))
    [void]$workspace.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$workspace.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.Controls.Add($workspace, 0, 2)

    $leftColumn = New-Object System.Windows.Forms.TableLayoutPanel
    $leftColumn.Dock = 'Fill'
    $leftColumn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $leftColumn.ColumnCount = 1
    $leftColumn.RowCount = 1
    [void]$leftColumn.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$leftColumn.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$workspace.Controls.Add($leftColumn, 0, 0)

    $instanceCard = New-UGSMPanel -X 0 -Y 0 -Width 300 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $instanceCard.Dock = 'Fill'
    $instanceCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$leftColumn.Controls.Add($instanceCard, 0, 0)
    Add-CardHeader -Card $instanceCard -Title 'Host Activity' -Subtitle 'Live machine analytics'

    $instanceList = New-Object System.Windows.Forms.ListBox
    $instanceList.Location = New-Object System.Drawing.Point(14, 58)
    $instanceList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor `
        [System.Windows.Forms.AnchorStyles]::Bottom -bor `
        [System.Windows.Forms.AnchorStyles]::Left -bor `
        [System.Windows.Forms.AnchorStyles]::Right
    $instanceList.Size = New-Object System.Drawing.Size(($instanceCard.Width - 28), ($instanceCard.Height - 72))
    $instanceList.BackColor = $global:UGSM_ColorBack
    $instanceList.ForeColor = New-UGSMColor $Theme.Text
    $instanceList.BorderStyle = 'None'
    $instanceList.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $instanceList.IntegralHeight = $false
    [void]$instanceCard.Controls.Add($instanceList)

    $rightColumn = New-Object System.Windows.Forms.TableLayoutPanel
    $rightColumn.Dock = 'Fill'
    $rightColumn.Margin = New-Object System.Windows.Forms.Padding(0)
    $rightColumn.ColumnCount = 1
    $rightColumn.RowCount = 2
    [void]$rightColumn.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$rightColumn.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$rightColumn.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$workspace.Controls.Add($rightColumn, 1, 0)

    $cpuChartCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $cpuChartCard.Dock = 'Fill'
    $cpuChartCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$rightColumn.Controls.Add($cpuChartCard, 0, 0)
    Add-CardHeader -Card $cpuChartCard -Title 'CPU Trend' -Subtitle 'Recent machine usage'

    $cpuInner = New-Object System.Windows.Forms.TableLayoutPanel
    $cpuInner.Dock = 'Fill'
    $cpuInner.Margin = New-Object System.Windows.Forms.Padding(0)
    $cpuInner.Padding = New-Object System.Windows.Forms.Padding(16, 56, 16, 16)
    $cpuInner.ColumnCount = 1
    $cpuInner.RowCount = 2
    [void]$cpuInner.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$cpuInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 20)))
    [void]$cpuInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$cpuChartCard.Controls.Add($cpuInner)

    $cpuChartStats = New-UGSMLabel -Text 'Current: --%   Peak: --%   Samples: --' -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Muted
    $cpuChartStats.Dock = 'Fill'
    $cpuChartStats.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$cpuInner.Controls.Add($cpuChartStats, 0, 0)

    $cpuChart = New-Object System.Windows.Forms.Panel
    $cpuChart.Dock = 'Fill'
    $cpuChart.Margin = New-Object System.Windows.Forms.Padding(0)
    $cpuChart.BackColor = $global:UGSM_ColorBack
    [void]$cpuInner.Controls.Add($cpuChart, 0, 1)

    $ramChartCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 100 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $ramChartCard.Dock = 'Fill'
    $ramChartCard.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$rightColumn.Controls.Add($ramChartCard, 0, 1)
    Add-CardHeader -Card $ramChartCard -Title 'RAM Trend' -Subtitle 'Recent memory usage'

    $ramInner = New-Object System.Windows.Forms.TableLayoutPanel
    $ramInner.Dock = 'Fill'
    $ramInner.Margin = New-Object System.Windows.Forms.Padding(0)
    $ramInner.Padding = New-Object System.Windows.Forms.Padding(16, 56, 16, 16)
    $ramInner.ColumnCount = 1
    $ramInner.RowCount = 2
    [void]$ramInner.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$ramInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 20)))
    [void]$ramInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$ramChartCard.Controls.Add($ramInner)

    $ramChartStats = New-UGSMLabel -Text 'Current: --%   Peak: --%   Samples: --' -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Muted
    $ramChartStats.Dock = 'Fill'
    $ramChartStats.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$ramInner.Controls.Add($ramChartStats, 0, 0)

    $ramChart = New-Object System.Windows.Forms.Panel
    $ramChart.Dock = 'Fill'
    $ramChart.Margin = New-Object System.Windows.Forms.Padding(0)
    $ramChart.BackColor = $global:UGSM_ColorBack
    [void]$ramInner.Controls.Add($ramChart, 0, 1)

    $bottomRow = New-Object System.Windows.Forms.TableLayoutPanel
    $bottomRow.Dock = 'Fill'
    $bottomRow.Margin = New-Object System.Windows.Forms.Padding(0)
    $bottomRow.Padding = New-Object System.Windows.Forms.Padding(0)
    $bottomRow.BackColor = $global:UGSM_ColorPageBackground
    $bottomRow.ColumnCount = 3
    $bottomRow.RowCount = 1
    [void]$bottomRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)))
    [void]$bottomRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)))
    [void]$bottomRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 34)))
    [void]$bottomRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.Controls.Add($bottomRow, 0, 3)

    $alertsCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 170 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $alertsCard.Dock = 'Fill'
    $alertsCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    [void]$bottomRow.Controls.Add($alertsCard, 0, 0)
    Add-CardHeader -Card $alertsCard -Title 'Alerts' -Subtitle 'Current machine and instance flags'
    $lblAlerts = New-UGSMLabel -Text '-' -X 16 -Y 58 -Width 360 -Height 94 -FontSize 8.5 -Color $Theme.Muted
    $lblAlerts.AutoSize = $false
    [void]$alertsCard.Controls.Add($lblAlerts)

    $eventsCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 170 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $eventsCard.Dock = 'Fill'
    $eventsCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    [void]$bottomRow.Controls.Add($eventsCard, 1, 0)
    Add-CardHeader -Card $eventsCard -Title 'Recent Events' -Subtitle 'Analytics activity and server state'
    $lblEvents = New-UGSMLabel -Text '-' -X 16 -Y 58 -Width 360 -Height 94 -FontSize 8.5 -Color $Theme.Muted
    $lblEvents.AutoSize = $false
    [void]$eventsCard.Controls.Add($lblEvents)

    $storageCard = New-UGSMPanel -X 0 -Y 0 -Width 100 -Height 170 -BackColor $Theme.Surface -BorderColor $Theme.Border
    $storageCard.Dock = 'Fill'
    [void]$bottomRow.Controls.Add($storageCard, 2, 0)
    Add-CardHeader -Card $storageCard -Title 'Storage / Capacity' -Subtitle 'Lightweight host snapshot'
    $lblStorage = New-UGSMLabel -Text '-' -X 16 -Y 58 -Width 360 -Height 94 -FontSize 8.5 -Color $Theme.Muted
    $lblStorage.AutoSize = $false
    [void]$storageCard.Controls.Add($lblStorage)

    $summaryCardBindings = @()

    $summarySpecs = @(
        @{ Card = $summaryCards[0]; Title = 'CPU'; Color = $global:UGSM_ColorCPU }
        @{ Card = $summaryCards[1]; Title = 'RAM'; Color = $global:UGSM_ColorRAM }
        @{ Card = $summaryCards[2]; Title = 'Running'; Color = $global:UGSM_ColorRunning }
        @{ Card = $summaryCards[3]; Title = 'Capacity'; Color = $global:UGSM_ColorCapacity }
    )

    foreach ($spec in $summarySpecs) {
     # Add-CardHeader -Card $spec.Card -Title $spec.Title -Subtitle ''
        $titleLabel = New-UGSMLabel -Text $spec.Title -X 16 -Y 12 -Width 220 -Height 20 -FontSize 10 -Style Bold -Color $global:UGSM_ColorText
        $valueLabel = New-UGSMLabel -Text '-' -X 16 -Y 38 -Width 220 -Height 28 -FontSize 15 -Style Bold -Color $spec.Color
        $metaLabel = New-UGSMLabel -Text '-' -X 16 -Y 68 -Width 240 -Height 18 -FontSize 8.5 -Color $Theme.Muted

        [void]$spec.Card.Controls.Add($titleLabel)
        [void]$spec.Card.Controls.Add($valueLabel)
        [void]$spec.Card.Controls.Add($metaLabel)

        $summaryCardBindings += [pscustomobject]@{
            Title      = $spec.Title
            ValueLabel = $valueLabel
            MetaLabel  = $metaLabel
        }
    }

    $UpdateAnalyticsUI = {
        $refreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
        $pageData = if (Get-Command Get-UGSMAnalyticsPageData -ErrorAction SilentlyContinue) {
            Get-UGSMAnalyticsPageData -AppState $AppState
        }
        else {
            $null
        }

        if (-not $pageData) {
            return
        }

        foreach ($binding in $summaryCardBindings) {
            switch ($binding.Title) {
                'CPU' {
                    $binding.ValueLabel.Text = ('{0}%' -f $pageData.Summary.CpuPercent)
                    $binding.MetaLabel.Text = 'Current machine load'
                }
                'RAM' {
                    $binding.ValueLabel.Text = ('{0}%' -f $pageData.Summary.RamPercent)
                    $binding.MetaLabel.Text = 'Memory pressure'
                }
                'Running' {
                    $binding.ValueLabel.Text = ('{0} / {1}' -f $pageData.Summary.RunningCount, $pageData.Summary.TotalInstances)
                    $binding.MetaLabel.Text = 'Active instances'
                }
                'Capacity' {
                    $binding.ValueLabel.Text = [string]$pageData.Summary.CapacityState
                    $binding.MetaLabel.Text = [string]$pageData.Summary.CapacityMessage
                }
            }
        }

        $instanceList.BeginUpdate()
        $instanceList.Items.Clear()
        foreach ($item in @($pageData.Instances)) {
            [void]$instanceList.Items.Add(('{0}  •  {1}  •  {2}' -f $item.Name, $item.GameName, $item.Status))
        }
        $instanceList.EndUpdate()

        $lblAlerts.Text = (($pageData.Alerts | ForEach-Object { "• $_" }) -join [Environment]::NewLine)
        $lblEvents.Text = (($pageData.Events | ForEach-Object { "• $_" }) -join [Environment]::NewLine)
        $lblStorage.Text = @(
            ('Install Disk: {0}' -f $pageData.Summary.InstallDiskText)
            ('Disk Trend: {0}%' -f $pageData.Summary.DiskPercent)
            ('Stopped Instances: {0}' -f $pageData.Summary.StoppedCount)
            ('Starting Instances: {0}' -f $pageData.Summary.StartingCount)
        ) -join [Environment]::NewLine

        $cpuValues = @($pageData.CpuSeries)
        $ramValues = @($pageData.RamSeries)

        $cpuCurrent = if ($cpuValues.Count -gt 0) { $cpuValues[-1] } else { 0 }
        $cpuPeak = if ($cpuValues.Count -gt 0) { ($cpuValues | Measure-Object -Maximum).Maximum } else { 0 }

        $ramCurrent = if ($ramValues.Count -gt 0) { $ramValues[-1] } else { 0 }
        $ramPeak = if ($ramValues.Count -gt 0) { ($ramValues | Measure-Object -Maximum).Maximum } else { 0 }

        $cpuChartStats.Text = ('Current: {0}%   Peak: {1}%   Samples: {2}' -f $cpuCurrent, $cpuPeak, $cpuValues.Count)
        $ramChartStats.Text = ('Current: {0}%   Peak: {1}%   Samples: {2}' -f $ramCurrent, $ramPeak, $ramValues.Count)

        Set-UGSMAnalyticsChart -PageHost $cpuChart -Values $cpuValues -LineColor $global:UGSM_ColorStarting -ChartTitle 'CPU %'
        Set-UGSMAnalyticsChart -PageHost $ramChart -Values $ramValues -LineColor $global:UGSM_ColorErrorTextSoft -ChartTitle 'RAM %'

        $refreshStopwatch.Stop()
        $refreshDuration = [int]$refreshStopwatch.ElapsedMilliseconds
        if ($refreshDuration -ge 1000) {
            Write-UGSMAnalyticsUILog -Level 'WARN' -Message ("Analytics UI refresh was slow. DurationMs=$refreshDuration; Instances=$(@($pageData.Instances).Count)")
        }
        elseif (Test-UGSMAnalyticsUIVerboseLogging) {
            Write-UGSMAnalyticsUILog -Level 'DEBUG' -Message ("Analytics UI refresh completed. DurationMs=$refreshDuration; Instances=$(@($pageData.Instances).Count)")
        }
        }
        catch {
            $refreshStopwatch.Stop()
            Write-UGSMAnalyticsUILog -Level 'ERROR' -Message ('Analytics UI refresh failed. DurationMs={0}' -f [int]$refreshStopwatch.ElapsedMilliseconds) -Exception $_.Exception
        }
    }.GetNewClosure()

    $analyticsRefreshTimer = New-Object System.Windows.Forms.Timer
    $analyticsRefreshTimer.Interval = 5000
    $analyticsRefreshTimer.Add_Tick({ & $UpdateAnalyticsUI }.GetNewClosure())
    $analyticsRefreshTimer.Start()

    $page.Add_Disposed({
            try {
                if ($analyticsRefreshTimer) {
                    $analyticsRefreshTimer.Stop()
                    $analyticsRefreshTimer.Dispose()
                    Write-UGSMAnalyticsUILog -Level 'DEBUG' -Message 'Analytics page refresh timer disposed.'
                }
            }
            catch {
                Write-UGSMAnalyticsUILog -Level 'WARN' -Message 'Analytics page cleanup failed.' -Exception $_.Exception
            }
        }.GetNewClosure())

    & $UpdateAnalyticsUI

    $pageStopwatch.Stop()
    Write-UGSMAnalyticsUILog -Level 'INFO' -Message ('Analytics page creation finished. DurationMs={0}' -f [int]$pageStopwatch.ElapsedMilliseconds)

    return $page
}