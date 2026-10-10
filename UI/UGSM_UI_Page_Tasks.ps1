# Tasks Page

function Write-UGSMTasksUILog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'TasksUI' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'TasksUI' -Message $Message
        }
    }
}

function Resolve-UGSMTasksUIColor {
    param(
        [object]$ColorValue,
        [System.Drawing.Color]$Fallback = [System.Drawing.Color]::White
    )

    if ($ColorValue -is [System.Drawing.Color]) {
        return $ColorValue
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$ColorValue)) {
        try {
            return [System.Drawing.ColorTranslator]::FromHtml([string]$ColorValue)
        }
        catch {
            return $Fallback
        }
    }

    return $Fallback
}

function New-UGSMTasksPage {
    [CmdletBinding()]
    param([hashtable]$Theme)

    $pageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMTasksUILog -Level 'INFO' -Message 'Tasks page creation started.'

    if (-not $Theme) {
        $Theme = @{
            WindowBg = $global:UGSM_ColorBackground
            Surface  = $global:UGSM_ColorPanelBackground
            Border   = $global:UGSM_ColorBorder
            Text     = $global:UGSM_ColorText
            Muted    = $global:UGSM_ColorMutedText
        }
    }

    if (Get-Command Start-UGSMTaskScheduler -ErrorAction SilentlyContinue) {
        Start-UGSMTaskScheduler | Out-Null
    }

    $getPageData = {
        $dataStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        if (Get-Command Get-UGSMTasksPageData -ErrorAction SilentlyContinue) {
            try {
                $result = $null
                if ($global:UGSM_AppState -and $global:UGSM_AppState.SelectedInstanceId) {
                    $result = Get-UGSMTasksPageData -InstanceId ([string]$global:UGSM_AppState.SelectedInstanceId)
                }
                else {
                    $result = Get-UGSMTasksPageData
                }
                $dataStopwatch.Stop()
                Write-UGSMTasksUILog -Level 'DEBUG' -Message ("Tasks page data loaded. InstanceId={0}; Tasks={1}; History={2}; DurationMs={3}" -f [string]$result.InstanceId, @($result.Tasks).Count, @($result.History).Count, $dataStopwatch.ElapsedMilliseconds)
                return $result
            }
            catch {
                $dataStopwatch.Stop()
                Write-UGSMTasksUILog -Level 'ERROR' -Message ("Tasks page data load failed. DurationMs={0}" -f $dataStopwatch.ElapsedMilliseconds) -Exception $_.Exception
            }
        }

        return [pscustomobject]@{
            Metrics      = @()
            Tasks        = @()
            SelectedTask = $null
            History      = @()
            Notes        = @()
            InstanceId   = ''
            InstanceName = 'No Instance'
            GameName     = 'Unknown'
            StatusText   = 'Ready'
        }
    }

    $pageData = & $getPageData

    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'
    $page.BackColor = $Theme.WindowBg
    $page.Padding = New-Object System.Windows.Forms.Padding(14)

    $metricValueLabels = @{}
    $metricTitleLabels = @{}
    $selectedTaskId = ''

    $makeButton = {
        param([string]$Text, [int]$W = 94)

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Width = $W
        $btn.Height = 28
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderColor = $Theme.Border
        $btn.BackColor = $Theme.Surface
        $btn.ForeColor = $Theme.Text
        return $btn
    }

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount = 5
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 84)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
    [void]$page.Controls.Add($root)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Fill'
    $header.BackColor = $global:UGSM_ColorTopBar
    [void]$root.Controls.Add($header, 0, 0)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = 'Tasks'
    $lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = $global:UGSM_ColorText
    $lblHeader.Location = New-Object System.Drawing.Point(14, 10)
    $lblHeader.Size = New-Object System.Drawing.Size(200, 28)
    [void]$header.Controls.Add($lblHeader)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Instance: $($pageData.InstanceName)  •  Game: $($pageData.GameName)"
    $lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblSub.ForeColor = $Theme.Muted
    $lblSub.Location = New-Object System.Drawing.Point(14, 42)
    $lblSub.Size = New-Object System.Drawing.Size(560, 18)
    [void]$header.Controls.Add($lblSub)

    $actions = New-Object System.Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'
    $actions.WrapContents = $false
    $actions.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $actions.BackColor = $Theme.WindowBg
    [void]$root.Controls.Add($actions, 0, 1)

    $btnNew = & $makeButton 'New Task' 92
    $btnEdit = & $makeButton 'Edit Task' 92
    $btnRemove = & $makeButton 'Remove' 82
    $btnRunNow = & $makeButton 'Run Now' 86
    $btnRefresh = & $makeButton 'Refresh' 88

    [void]$actions.Controls.Add($btnNew)
    [void]$actions.Controls.Add($btnEdit)
    [void]$actions.Controls.Add($btnRemove)
    [void]$actions.Controls.Add($btnRunNow)
    [void]$actions.Controls.Add($btnRefresh)

    $metrics = New-Object System.Windows.Forms.FlowLayoutPanel
    $metrics.Dock = 'Fill'
    $metrics.WrapContents = $false
    $metrics.BackColor = $Theme.WindowBg
    $metrics.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    [void]$root.Controls.Add($metrics, 0, 2)

    foreach ($m in $pageData.Metrics) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size(210, 66)
       $card.BackColor = $Theme.Surface
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)

        $title = New-Object System.Windows.Forms.Label
        $title.Text = $m.Label
        $title.ForeColor = $Theme.Muted
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $title.Location = New-Object System.Drawing.Point(12, 10)
        $title.Size = New-Object System.Drawing.Size(180, 18)
        [void]$card.Controls.Add($title)

        $value = New-Object System.Windows.Forms.Label
        $value.Text = [string]$m.Value
        $value.ForeColor = $global:UGSM_ColorText
        $value.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
        $value.Location = New-Object System.Drawing.Point(12, 30)
        $value.Size = New-Object System.Drawing.Size(180, 26)
        [void]$card.Controls.Add($value)

        $metricTitleLabels[[string]$m.Label] = $title
        $metricValueLabels[[string]$m.Label] = $value
        [void]$metrics.Controls.Add($card)
    }

    $main = New-Object System.Windows.Forms.SplitContainer
    $main.Panel1.Padding = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $main.Panel2.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $main.Dock = 'Fill'
    $main.SplitterDistance = 960
    [void]$root.Controls.Add($main, 0, 3)

    $leftLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $leftLayout.Dock = 'Fill'
    $leftLayout.ColumnCount = 1
    $leftLayout.RowCount = 2
    [void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 72)))
    [void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 28)))
    [void]$main.Panel1.Controls.Add($leftLayout)

    $tasksPanel = New-Object System.Windows.Forms.Panel
    $tasksPanel.Dock = 'Fill'
    $tasksPanel.BackColor = $Theme.Surface
    $tasksPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$leftLayout.Controls.Add($tasksPanel, 0, 0)

    $tasksTitle = New-Object System.Windows.Forms.Label
    $tasksTitle.Text = 'Scheduled Tasks'
    $tasksTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $tasksTitle.ForeColor = $global:UGSM_ColorText
    $tasksTitle.Location = New-Object System.Drawing.Point(4, 2)
    $tasksTitle.Size = New-Object System.Drawing.Size(200, 24)
    [void]$tasksPanel.Controls.Add($tasksTitle)

    $tasksSub = New-Object System.Windows.Forms.Label
    $tasksSub.Text = 'Automation jobs, schedules, and status'
    $tasksSub.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $tasksSub.ForeColor = $Theme.Muted
    $tasksSub.Location = New-Object System.Drawing.Point(4, 26)
    $tasksSub.Size = New-Object System.Drawing.Size(320, 16)
    [void]$tasksPanel.Controls.Add($tasksSub)

    $tasksInner = New-Object System.Windows.Forms.Panel
    $tasksInner.Dock = 'Fill'
    $tasksInner.Padding = New-Object System.Windows.Forms.Padding(4, 48, 4, 4)
    [void]$tasksPanel.Controls.Add($tasksInner)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.Margin = New-Object System.Windows.Forms.Padding(0)
    $grid.BackgroundColor = $global:UGSM_ColorInputBackground
    $grid.BorderStyle = 'FixedSingle'
    $grid.ForeColor = $Theme.Text
    $grid.AutoGenerateColumns = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.MultiSelect = $false
    $grid.ReadOnly = $true
    $grid.SelectionMode = 'FullRowSelect'
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $Theme.Surface
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.Text
    $grid.EnableHeadersVisualStyles = $false

    $grid.DefaultCellStyle.BackColor = $global:UGSM_ColorInputBackground
    $grid.DefaultCellStyle.ForeColor = $Theme.Text
    $grid.DefaultCellStyle.SelectionBackColor = $global:UGSM_ColorGridSelection
    $grid.DefaultCellStyle.SelectionForeColor = $global:UGSM_ColorText

    $grid.RowsDefaultCellStyle.BackColor = $global:UGSM_ColorInputBackground
    $grid.RowsDefaultCellStyle.ForeColor = $Theme.Text
    $grid.RowsDefaultCellStyle.SelectionBackColor = $global:UGSM_ColorGridSelection
    $grid.RowsDefaultCellStyle.SelectionForeColor = $global:UGSM_ColorText

    $grid.AlternatingRowsDefaultCellStyle.BackColor = $global:UGSM_ColorCanvas
    $grid.AlternatingRowsDefaultCellStyle.ForeColor = $Theme.Text
    $grid.AlternatingRowsDefaultCellStyle.SelectionBackColor = $global:UGSM_ColorGridSelection
    $grid.AlternatingRowsDefaultCellStyle.SelectionForeColor = $global:UGSM_ColorText

    $grid.GridColor = $Theme.Border

    foreach ($pair in @(
            @{ Name = 'Name'; Header = 'Task' },
            @{ Name = 'Type'; Header = 'Type' },
            @{ Name = 'Target'; Header = 'Target' },
            @{ Name = 'Schedule'; Header = 'Schedule' },
            @{ Name = 'Status'; Header = 'Status' },
            @{ Name = 'LastRun'; Header = 'Last Run' },
            @{ Name = 'NextRun'; Header = 'Next Run' },
            @{ Name = 'Active'; Header = 'Active' }
        )) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.DataPropertyName = $pair.Name
        $col.HeaderText = $pair.Header
        [void]$grid.Columns.Add($col)
    }

    [void]$tasksInner.Controls.Add($grid)

    $historyPanel = New-Object System.Windows.Forms.Panel
    $historyPanel.Dock = 'Fill'
    $historyPanel.BackColor = $Theme.Surface
    $historyPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$leftLayout.Controls.Add($historyPanel, 0, 1)

    $historyTitle = New-Object System.Windows.Forms.Label
    $historyTitle.Text = 'Recent Execution History'
    $historyTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $historyTitle.ForeColor = $global:UGSM_ColorText
    $historyTitle.Location = New-Object System.Drawing.Point(4, 2)
    $historyTitle.Size = New-Object System.Drawing.Size(260, 24)
    [void]$historyPanel.Controls.Add($historyTitle)

    $historyInner = New-Object System.Windows.Forms.Panel
    $historyInner.Dock = 'Fill'
    $historyInner.Padding = New-Object System.Windows.Forms.Padding(4, 34, 4, 4)
    [void]$historyPanel.Controls.Add($historyInner)

    $historyList = New-Object System.Windows.Forms.ListView
    $historyList.View = 'Details'
    $historyList.FullRowSelect = $true
    $historyList.HideSelection = $false
    $historyList.HeaderStyle = 'Nonclickable'
    $historyList.BackColor = $global:UGSM_ColorInputBackground
    $historyList.ForeColor = $Theme.Text
    $historyList.BorderStyle = 'FixedSingle'
    $historyList.Dock = 'Fill'
    [void]$historyList.Columns.Add('Time', 160)
    [void]$historyList.Columns.Add('Task', 280)
    [void]$historyList.Columns.Add('Result', 220)
    [void]$historyList.Columns.Add('Duration', 110)
    [void]$historyInner.Controls.Add($historyList)

    $rightLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $rightLayout.Dock = 'Fill'
    $rightLayout.ColumnCount = 1
    $rightLayout.RowCount = 2
    [void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 270)))
    [void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$main.Panel2.Controls.Add($rightLayout)

    $detailsPanel = New-Object System.Windows.Forms.Panel
    $detailsPanel.Dock = 'Fill'
    $detailsPanel.BackColor = $Theme.Surface
    $detailsPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$rightLayout.Controls.Add($detailsPanel, 0, 0)

    $detailTitle = New-Object System.Windows.Forms.Label
    $detailTitle.Text = 'Selected Task'
    $detailTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $detailTitle.ForeColor = $global:UGSM_ColorText
    $detailTitle.Location = New-Object System.Drawing.Point(4, 2)
    $detailTitle.Size = New-Object System.Drawing.Size(200, 24)
    [void]$detailsPanel.Controls.Add($detailTitle)

    $lblTaskName = New-Object System.Windows.Forms.Label
    $lblTaskName.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $lblTaskName.ForeColor = $global:UGSM_ColorText
    $lblTaskName.Location = New-Object System.Drawing.Point(4, 34)
    $lblTaskName.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblTaskName.Size = New-Object System.Drawing.Size(($detailsPanel.ClientSize.Width - 20), 28)
    [void]$detailsPanel.Controls.Add($lblTaskName)

    $lblTaskMeta = New-Object System.Windows.Forms.Label
    $lblTaskMeta.ForeColor = $Theme.Muted
    $lblTaskMeta.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblTaskMeta.Location = New-Object System.Drawing.Point(4, 68)
    $lblTaskMeta.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblTaskMeta.Size = New-Object System.Drawing.Size(($detailsPanel.ClientSize.Width - 20), 132)
    $lblTaskMeta.AutoSize = $false
    [void]$detailsPanel.Controls.Add($lblTaskMeta)

    $lblTaskNotes = New-Object System.Windows.Forms.Label
    $lblTaskNotes.ForeColor = $Theme.Text
    $lblTaskNotes.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblTaskNotes.Location = New-Object System.Drawing.Point(4, 206)
    $lblTaskNotes.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblTaskNotes.Size = New-Object System.Drawing.Size(($detailsPanel.ClientSize.Width - 20), 44)
    $lblTaskNotes.AutoSize = $false
    [void]$detailsPanel.Controls.Add($lblTaskNotes)

    $notesPanel = New-Object System.Windows.Forms.Panel
    $notesPanel.Dock = 'Fill'
    $notesPanel.BackColor = $Theme.Surface
    $notesPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$rightLayout.Controls.Add($notesPanel, 0, 1)

    $notesTitle = New-Object System.Windows.Forms.Label
    $notesTitle.Text = 'Task Workflow Notes'
    $notesTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $notesTitle.ForeColor = $global:UGSM_ColorText
    $notesTitle.Location = New-Object System.Drawing.Point(4, 2)
    $notesTitle.Size = New-Object System.Drawing.Size(220, 24)
    [void]$notesPanel.Controls.Add($notesTitle)

    $notesList = New-Object System.Windows.Forms.Label
    $notesList.ForeColor = $Theme.Muted
    $notesList.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $notesList.Location = New-Object System.Drawing.Point(4, 34)
    $notesList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $notesList.Size = New-Object System.Drawing.Size(($notesPanel.ClientSize.Width - 20), 180)
    $notesList.Text = (($pageData.Notes | ForEach-Object { "• $_" }) -join [Environment]::NewLine)
    $notesList.AutoSize = $false
    [void]$notesPanel.Controls.Add($notesList)

    $footer = New-Object System.Windows.Forms.Label
    $footer.Dock = 'Fill'
    $footer.ForeColor = $Theme.Muted
    $footer.TextAlign = 'MiddleLeft'
    $footer.Text = [string]$pageData.StatusText
    [void]$root.Controls.Add($footer, 0, 4)

    $updateTaskDetails = {
        param($task)

        if (-not $task) {
            $selectedTaskId = ''
            $lblTaskName.Text = 'No task selected'
            $lblTaskMeta.Text = 'Select a task to view details.'
            $lblTaskNotes.Text = ''
            return
        }

        $selectedTaskId = [string]$task.Id
        $lblTaskName.Text = [string]$task.Name
        $lblTaskMeta.Text = @(
            "Type: $($task.Type)"
            "Target: $($task.Target)"
            "Schedule: $($task.Schedule)"
            "Status: $($task.Status)"
            "Active: $($task.Active)"
            "Last Run: $($task.LastRun)"
            "Next Run: $($task.NextRun)"
            "Result: $($task.Result)"
        ) -join [Environment]::NewLine
        $lblTaskNotes.Text = [string]$task.Notes
    }.GetNewClosure()

    $showInfo = {
        param([string]$title, [string]$message)
        [void][System.Windows.Forms.MessageBox]::Show(
            $message,
            $title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }.GetNewClosure()

    $loadHistory = {
        param($history)

        $historyList.BeginUpdate()
        try {
            $historyList.Items.Clear()
            foreach ($entry in @($history)) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Time)
                [void]$item.SubItems.Add([string]$entry.Task)
                [void]$item.SubItems.Add([string]$entry.Result)
                [void]$item.SubItems.Add([string]$entry.Duration)
                [void]$historyList.Items.Add($item)
            }
        }
        finally {
            $historyList.EndUpdate()
        }
    }.GetNewClosure()

    $loadTasksGrid = {
        param($tasks)

        $grid.Rows.Clear()

        foreach ($task in @($tasks)) {
            $rowIndex = $grid.Rows.Add(
                [string]$task.Name,
                [string]$task.Type,
                [string]$task.Target,
                [string]$task.Schedule,
                [string]$task.Status,
                [string]$task.LastRun,
                [string]$task.NextRun,
                [string]$task.Active
            )

            $row = $grid.Rows[$rowIndex]
            $row.Tag = $task
        }
    }.GetNewClosure()

    $selectTaskRowById = {
        param([string]$taskId)

        if ([string]::IsNullOrWhiteSpace($taskId)) {
            return
        }

        foreach ($row in $grid.Rows) {
            if ($row.Tag -and [string]$row.Tag.Id -eq $taskId) {
                $row.Selected = $true
                if ($row.Cells.Count -gt 0) {
                    $grid.CurrentCell = $row.Cells[0]
                }
                return
            }
        }
    }.GetNewClosure()

    $getSelectedTask = {
        if ($grid.SelectedRows.Count -gt 0) {
            $row = $grid.SelectedRows[0]
            if ($row -and $row.Tag) {
                return $row.Tag
            }
        }

        if ($grid.CurrentRow -and $grid.CurrentRow.Tag) {
            return $grid.CurrentRow.Tag
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedTaskId)) {
            $fresh = & $getPageData
            return @($fresh.Tasks | Where-Object { [string]$_.Id -eq $selectedTaskId } | Select-Object -First 1)[0]
        }

        return $null
    }.GetNewClosure()

    $refreshPage = {
        param([string]$preferredTaskId = '')

        $refreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-UGSMTasksUILog -Level 'DEBUG' -Message ("Tasks page refresh started. PreferredTaskId={0}" -f [string]$preferredTaskId)
        $fresh = & $getPageData
        $lblSub.Text = "Instance: $($fresh.InstanceName)  •  Game: $($fresh.GameName)"
        $footer.Text = [string]$fresh.StatusText
        $notesList.Text = (($fresh.Notes | ForEach-Object { "• $_" }) -join [Environment]::NewLine)

        foreach ($m in @($fresh.Metrics)) {
            if ($metricValueLabels.ContainsKey([string]$m.Label)) {
                $metricValueLabels[[string]$m.Label].Text = [string]$m.Value
            }
        }

        #$binding.DataSource = @($fresh.Tasks)
        #$binding.ResetBindings($false)
        & $loadTasksGrid $fresh.Tasks
        & $loadHistory $fresh.History

        $taskToShow = $null
        if (-not [string]::IsNullOrWhiteSpace($preferredTaskId)) {
            $taskToShow = @($fresh.Tasks | Where-Object { [string]$_.Id -eq $preferredTaskId } | Select-Object -First 1)[0]
        }
        if (-not $taskToShow -and -not [string]::IsNullOrWhiteSpace($selectedTaskId)) {
            $taskToShow = @($fresh.Tasks | Where-Object { [string]$_.Id -eq $selectedTaskId } | Select-Object -First 1)[0]
        }
        if (-not $taskToShow -and $fresh.SelectedTask) {
            $taskToShow = $fresh.SelectedTask
        }

        if ($taskToShow) {
            & $updateTaskDetails $taskToShow
            & $selectTaskRowById ([string]$taskToShow.Id)
        }
        else {
            & $updateTaskDetails $null
        }

        $refreshStopwatch.Stop()
        Write-UGSMTasksUILog -Level 'DEBUG' -Message ("Tasks page refresh finished. Tasks={0}; History={1}; DurationMs={2}" -f @($fresh.Tasks).Count, @($fresh.History).Count, $refreshStopwatch.ElapsedMilliseconds)
    }.GetNewClosure()

    $getTargetInstances = {
        $instances = @()
        if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
            try {
                $instances = @(Get-UGSMInstances)
            }
            catch {
                Write-UGSMTasksUILog -Level 'ERROR' -Message 'Failed to load target instances for task editor.' -Exception $_.Exception
                $instances = @()
            }
        }

        if ($global:UGSM_AppState -and -not [string]::IsNullOrWhiteSpace([string]$global:UGSM_AppState.SelectedGameId)) {
            $instances = @($instances | Where-Object { [string]$_.GameId -eq [string]$global:UGSM_AppState.SelectedGameId })
        }

        return $instances
    }.GetNewClosure()

    $showTaskEditor = {
        param($task)

        $editorMode = if ($task) { 'Edit' } else { 'New' }
        Write-UGSMTasksUILog -Level 'INFO' -Message ("Task editor opened. Mode={0}" -f $editorMode)
        $instances = & $getTargetInstances
        if (@($instances).Count -eq 0) {
            Write-UGSMTasksUILog -Level 'WARN' -Message 'Task editor could not open because no target instances are available.'
            & $showInfo 'Tasks' 'Create a server profile first so a task has something to target.'
            return $null
        }

        $form = New-Object System.Windows.Forms.Form
        $form.Text = if ($task) { 'Edit Task' } else { 'New Task' }
        $form.StartPosition = 'CenterParent'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.ClientSize = New-Object System.Drawing.Size(460, 360)
        $form.BackColor = (Resolve-UGSMTasksUIColor $Theme.WindowBg $global:UGSM_ColorBackground)
        $form.ForeColor = (Resolve-UGSMTasksUIColor $Theme.Text $global:UGSM_ColorText)

        $makeLabel = {
            param([string]$text, [int]$x, [int]$y)
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $text
            $lbl.Location = New-Object System.Drawing.Point($x, $y)
            $lbl.Size = New-Object System.Drawing.Size(120, 20)
            $lbl.ForeColor = (Resolve-UGSMTasksUIColor $Theme.Text $global:UGSM_ColorText)
            return $lbl
        }

        $makeText = {
            param([int]$x, [int]$y, [int]$w = 290)
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Location = New-Object System.Drawing.Point($x, $y)
            $tb.Size = New-Object System.Drawing.Size($w, 24)
            return $tb
        }

        $form.Controls.Add((& $makeLabel 'Task Name' 20 20))
        $txtName = & $makeText 140 18
        $form.Controls.Add($txtName)

        $form.Controls.Add((& $makeLabel 'Target' 20 58))
        $cmbTarget = New-Object System.Windows.Forms.ComboBox
        $cmbTarget.Location = New-Object System.Drawing.Point(140, 56)
        $cmbTarget.Size = New-Object System.Drawing.Size(290, 24)
        $cmbTarget.DropDownStyle = 'DropDownList'
        foreach ($instance in $instances) {
            [void]$cmbTarget.Items.Add([pscustomobject]@{ Text = ('{0} ({1})' -f [string]$instance.Name, [string]$instance.GameId); Id = [string]$instance.Id; Name = [string]$instance.Name })
        }
        $cmbTarget.DisplayMember = 'Text'
        $cmbTarget.ValueMember = 'Id'
        $form.Controls.Add($cmbTarget)

        $form.Controls.Add((& $makeLabel 'Task Type' 20 96))
        $cmbType = New-Object System.Windows.Forms.ComboBox
        $cmbType.Location = New-Object System.Drawing.Point(140, 94)
        $cmbType.Size = New-Object System.Drawing.Size(180, 24)
        $cmbType.DropDownStyle = 'DropDownList'
        [void]$cmbType.Items.AddRange(@('Start', 'Stop', 'Restart'))
        $form.Controls.Add($cmbType)

        $form.Controls.Add((& $makeLabel 'Schedule' 20 134))
        $cmbSchedule = New-Object System.Windows.Forms.ComboBox
        $cmbSchedule.Location = New-Object System.Drawing.Point(140, 132)
        $cmbSchedule.Size = New-Object System.Drawing.Size(180, 24)
        $cmbSchedule.DropDownStyle = 'DropDownList'
        [void]$cmbSchedule.Items.AddRange(@('OneTime', 'Daily'))
        $form.Controls.Add($cmbSchedule)

        $form.Controls.Add((& $makeLabel 'Run At' 20 172))
        $dtRunAt = New-Object System.Windows.Forms.DateTimePicker
        $dtRunAt.Location = New-Object System.Drawing.Point(140, 170)
        $dtRunAt.Size = New-Object System.Drawing.Size(220, 24)
        $dtRunAt.Format = 'Custom'
        $dtRunAt.CustomFormat = 'MM/dd/yyyy hh:mm tt'
        $dtRunAt.Value = (Get-Date).AddMinutes(10)
        $form.Controls.Add($dtRunAt)

        $form.Controls.Add((& $makeLabel 'Daily Time' 20 210))
        $dtDaily = New-Object System.Windows.Forms.DateTimePicker
        $dtDaily.Location = New-Object System.Drawing.Point(140, 208)
        $dtDaily.Size = New-Object System.Drawing.Size(140, 24)
        $dtDaily.Format = 'Time'
        $dtDaily.ShowUpDown = $true
        $dtDaily.Value = Get-Date
        $form.Controls.Add($dtDaily)

        $chkEnabled = New-Object System.Windows.Forms.CheckBox
        $chkEnabled.Text = 'Task starts enabled'
        $chkEnabled.Location = New-Object System.Drawing.Point(140, 244)
        $chkEnabled.Size = New-Object System.Drawing.Size(180, 24)
        $chkEnabled.ForeColor = (Resolve-UGSMTasksUIColor $Theme.Text $global:UGSM_ColorText)
        $chkEnabled.Checked = $true
        $form.Controls.Add($chkEnabled)

        $form.Controls.Add((& $makeLabel 'Notes' 20 278))
        $txtNotes = New-Object System.Windows.Forms.TextBox
        $txtNotes.Location = New-Object System.Drawing.Point(140, 276)
        $txtNotes.Size = New-Object System.Drawing.Size(290, 44)
        $txtNotes.Multiline = $true
        $form.Controls.Add($txtNotes)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = 'Save'
        $btnOk.Location = New-Object System.Drawing.Point(274, 328)
        $btnOk.Size = New-Object System.Drawing.Size(74, 26)
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.Add($btnOk)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = 'Cancel'
        $btnCancel.Location = New-Object System.Drawing.Point(356, 328)
        $btnCancel.Size = New-Object System.Drawing.Size(74, 26)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($btnCancel)

        $toggleScheduleFields = {
            $isOneTime = ([string]$cmbSchedule.SelectedItem -eq 'OneTime')
            $dtRunAt.Enabled = $isOneTime
            $dtDaily.Enabled = -not $isOneTime
        }

        $cmbSchedule.Add_SelectedIndexChanged({ & $toggleScheduleFields })

        if ($task) {
            $txtName.Text = [string]$task.Name
            $cmbType.SelectedItem = [string]$task.Type
            $cmbSchedule.SelectedItem = [string]$task.ScheduleType
            $chkEnabled.Checked = [bool]$task.IsEnabled
            $txtNotes.Text = [string]$task.Notes

            foreach ($item in $cmbTarget.Items) {
                if ([string]$item.Id -eq [string]$task.TargetInstanceId) {
                    $cmbTarget.SelectedItem = $item
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$task.OneTimeAt)) {
                try { $dtRunAt.Value = [datetime]$task.OneTimeAt } catch {}
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$task.DailyTime)) {
                try {
                    $parsedDaily = [datetime]::ParseExact([string]$task.DailyTime, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
                    $dtDaily.Value = Get-Date -Hour $parsedDaily.Hour -Minute $parsedDaily.Minute -Second 0
                }
                catch {}
            }
        }
        else {
            $txtName.Text = if ($pageData.InstanceName -and $pageData.InstanceName -ne 'No Instance') { "Start $($pageData.InstanceName)" } else { '' }
            $cmbType.SelectedItem = 'Start'
            $cmbSchedule.SelectedItem = 'OneTime'

            foreach ($item in $cmbTarget.Items) {
                if ([string]$item.Id -eq [string]$pageData.InstanceId) {
                    $cmbTarget.SelectedItem = $item
                    break
                }
            }
            if (-not $cmbTarget.SelectedItem -and $cmbTarget.Items.Count -gt 0) {
                $cmbTarget.SelectedIndex = 0
            }
        }

        if (-not $cmbType.SelectedItem) { $cmbType.SelectedIndex = 0 }
        if (-not $cmbSchedule.SelectedItem) { $cmbSchedule.SelectedIndex = 0 }
        & $toggleScheduleFields

        $form.AcceptButton = $btnOk
        $form.CancelButton = $btnCancel

        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-UGSMTasksUILog -Level 'INFO' -Message 'Task editor cancelled.'
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
            Write-UGSMTasksUILog -Level 'WARN' -Message 'Task editor validation failed: task name is required.'
            & $showInfo 'Tasks' 'Task name is required.'
            return $null
        }
        if (-not $cmbTarget.SelectedItem) {
            Write-UGSMTasksUILog -Level 'WARN' -Message 'Task editor validation failed: target profile is required.'
            & $showInfo 'Tasks' 'Select a target profile.'
            return $null
        }

        $editorMode = if ($task) { 'Edit' } else { 'New' }
        Write-UGSMTasksUILog -Level 'INFO' -Message ("Task editor accepted. Mode={0}; Name={1}; Type={2}; TargetInstanceId={3}; ScheduleType={4}; Enabled={5}" -f $editorMode, [string]$txtName.Text.Trim(), [string]$cmbType.SelectedItem, [string]$cmbTarget.SelectedItem.Id, [string]$cmbSchedule.SelectedItem, [bool]$chkEnabled.Checked)

        return @{
            Id               = if ($task) { [string]$task.Id } else { '' }
            Name             = [string]$txtName.Text.Trim()
            Type             = [string]$cmbType.SelectedItem
            TargetInstanceId = [string]$cmbTarget.SelectedItem.Id
            ScheduleType     = [string]$cmbSchedule.SelectedItem
            OneTimeAt        = if ([string]$cmbSchedule.SelectedItem -eq 'OneTime') { $dtRunAt.Value.ToString('o') } else { '' }
            DailyTime        = if ([string]$cmbSchedule.SelectedItem -eq 'Daily') { $dtDaily.Value.ToString('HH:mm') } else { '' }
            IsEnabled        = [bool]$chkEnabled.Checked
            Notes            = [string]$txtNotes.Text.Trim()
        }
    }.GetNewClosure()

    $grid.Add_SelectionChanged({
            if ($grid.SelectedRows.Count -gt 0) {
                $row = $grid.SelectedRows[0]
                if ($row -and $row.Tag) {
                    & $updateTaskDetails $row.Tag
                }
            }
        }.GetNewClosure())

    $btnNew.Add_Click({
            Write-UGSMTasksUILog -Level 'INFO' -Message 'New Task clicked.'
            $taskInput = & $showTaskEditor $null
            if (-not $taskInput) { return }

            try {
                $saved = New-UGSMTaskDefinition @taskInput
                Write-UGSMTasksUILog -Level 'INFO' -Message ("New task saved from UI. Id={0}; Name={1}" -f [string]$saved.Id, [string]$saved.Name)
                & $refreshPage ([string]$saved.Id)
            }
            catch {
                Write-UGSMTasksUILog -Level 'ERROR' -Message 'New task save failed from UI.' -Exception $_.Exception
                & $showInfo 'New Task' ([string]$_.Exception.Message)
            }
        }.GetNewClosure())

    $btnEdit.Add_Click({
            Write-UGSMTasksUILog -Level 'INFO' -Message 'Edit Task clicked.'
            $current = & $getSelectedTask
            if (-not $current) {
                & $showInfo 'Edit Task' 'Select a task first.'
                return
            }

            $taskInput = & $showTaskEditor $current
            if (-not $taskInput) { return }

            try {
                $saved = New-UGSMTaskDefinition @taskInput
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Task edited from UI. Id={0}; Name={1}" -f [string]$saved.Id, [string]$saved.Name)
                & $refreshPage ([string]$saved.Id)
            }
            catch {
                Write-UGSMTasksUILog -Level 'ERROR' -Message 'Edit task failed from UI.' -Exception $_.Exception
                & $showInfo 'Edit Task' ([string]$_.Exception.Message)
            }
        }.GetNewClosure())

    $btnRemove.Add_Click({
            Write-UGSMTasksUILog -Level 'INFO' -Message 'Remove Task clicked.'
            $current = & $getSelectedTask
            if (-not $current) {
                & $showInfo 'Remove Task' 'Select a task first.'
                return
            }

            $confirm = [System.Windows.Forms.MessageBox]::Show(
                'Remove the selected task?',
                'Remove Task',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Remove task cancelled. Id={0}" -f [string]$current.Id)
                return
            }

            try {
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Remove task confirmed. Id={0}; Name={1}" -f [string]$current.Id, [string]$current.Name)
                $null = Remove-UGSMTaskDefinition -Id ([string]$current.Id)
                $selectedTaskId = ''
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Task removed from UI. Id={0}" -f [string]$current.Id)
                & $refreshPage
            }
            catch {
                Write-UGSMTasksUILog -Level 'ERROR' -Message 'Remove task failed from UI.' -Exception $_.Exception
                & $showInfo 'Remove Task' ([string]$_.Exception.Message)
            }
        }.GetNewClosure())

    $btnRunNow.Add_Click({
            Write-UGSMTasksUILog -Level 'INFO' -Message 'Run Task Now clicked.'
            $current = & $getSelectedTask
            if (-not $current) {
                & $showInfo 'Run Task Now' 'Select a task first.'
                return
            }

            try {
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Run task now requested from UI. Id={0}; Name={1}; Type={2}" -f [string]$current.Id, [string]$current.Name, [string]$current.Type)
                $result = Invoke-UGSMTaskNow -Id ([string]$current.Id)
                & $refreshPage ([string]$current.Id)
                Write-UGSMTasksUILog -Level 'INFO' -Message ("Run task now completed from UI. Id={0}; Success={1}; Result={2}; Duration={3}" -f [string]$current.Id, [bool]$result.Success, [string]$result.Result, [string]$result.Duration)
                & $showInfo 'Run Task Now' ("Task finished with result: {0}" -f [string]$result.Result)
            }
            catch {
                Write-UGSMTasksUILog -Level 'ERROR' -Message 'Run task now failed from UI.' -Exception $_.Exception
                & $showInfo 'Run Task Now' ([string]$_.Exception.Message)
            }
        }.GetNewClosure())

    $btnRefresh.Add_Click({ Write-UGSMTasksUILog -Level 'INFO' -Message ("Refresh Tasks clicked. SelectedTaskId={0}" -f [string]$selectedTaskId); & $refreshPage $selectedTaskId }.GetNewClosure())

    & $loadTasksGrid $pageData.Tasks
    & $loadHistory $pageData.History
    if ($pageData.SelectedTask) {
        & $updateTaskDetails $pageData.SelectedTask
        & $selectTaskRowById ([string]$pageData.SelectedTask.Id)
    }
    elseif ($pageData.Tasks.Count -gt 0) {
        & $updateTaskDetails $pageData.Tasks[0]
        & $selectTaskRowById ([string]$pageData.Tasks[0].Id)
    }
    else {
        & $updateTaskDetails $null
    }

    $pageStopwatch.Stop()
    Write-UGSMTasksUILog -Level 'INFO' -Message ("Tasks page creation finished. Tasks={0}; History={1}; DurationMs={2}" -f @($pageData.Tasks).Count, @($pageData.History).Count, $pageStopwatch.ElapsedMilliseconds)

    return $page
}
