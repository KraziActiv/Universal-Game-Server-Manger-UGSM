# Tasks Service


function Write-UGSMTasksLog {
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
            Write-UGSMLog -Level $Level -Category 'Tasks' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'Tasks' -Message $Message
        }
        return
    }
}

# StrictMode-safe scheduler timer storage.
# Some pages only create the task scheduler after the Tasks page is opened.
# Referencing an unset script variable under StrictMode throws before the page can render.
if (-not (Get-Variable -Name 'UGSMTaskSchedulerTimer' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSMTaskSchedulerTimer = $null
}

function Get-UGSMTaskSchedulerTimer {
    [CmdletBinding()]
    param()

    $timerVar = Get-Variable -Name 'UGSMTaskSchedulerTimer' -Scope Script -ErrorAction SilentlyContinue
    if ($timerVar) {
        return $timerVar.Value
    }

    $script:UGSMTaskSchedulerTimer = $null
    return $null
}

function Set-UGSMTaskSchedulerTimer {
    [CmdletBinding()]
    param(
        $Timer
    )

    $script:UGSMTaskSchedulerTimer = $Timer
    return $script:UGSMTaskSchedulerTimer
}

function Get-UGSMTaskStoreRoot {
    [CmdletBinding()]
    param()

    $root = Join-Path $env:LOCALAPPDATA 'UGSM'
    if (Get-Command Ensure-UGSMDirectory -ErrorAction SilentlyContinue) {
        return (Ensure-UGSMDirectory -Path $root)
    }

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    return $root
}

function Get-UGSMTaskDefinitionsPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMTaskStoreRoot) 'tasks.json')
}

function Get-UGSMTaskHistoryPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMTaskStoreRoot) 'task_history.json')
}

function Get-UGSMTaskTargetInstance {
    [CmdletBinding()]
    param(
        [string]$InstanceId
    )

    $instance = $null

    if (-not [string]::IsNullOrWhiteSpace($InstanceId) -and (Get-Command Get-UGSMInstance -ErrorAction SilentlyContinue)) {
        try {
            $instance = Get-UGSMInstance -Id $InstanceId
        }
        catch {
            $instance = $null
        }
    }

    if (-not $instance -and $global:UGSM_AppState -and $global:UGSM_AppState.SelectedInstance) {
        $instance = $global:UGSM_AppState.SelectedInstance
    }

    if (-not $instance -and (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue)) {
        $instance = @(Get-UGSMInstances | Select-Object -First 1)[0]
    }

    return $instance
}

function ConvertFrom-UGSMJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) {
        return @()
    }

    if ($data -is [System.Array]) {
        return @($data)
    }

    return @($data)
}

function Save-UGSMJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowEmptyCollection()]
        [object[]]$Data = @()
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        if (Get-Command Ensure-UGSMDirectory -ErrorAction SilentlyContinue) {
            Ensure-UGSMDirectory -Path $parent | Out-Null
        }
        elseif (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }

    $json = @($Data) | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-UGSMTaskDefinitions {
    [CmdletBinding()]
    param()

    $tasks = @(ConvertFrom-UGSMJsonFile -Path (Get-UGSMTaskDefinitionsPath))

    $taskCount = @($tasks).Count
    $shouldLogLoad = $false
    $lastTaskCountVar = Get-Variable -Name 'UGSM_TaskDefinitionsLastLogCount' -Scope Script -ErrorAction SilentlyContinue
    if (-not $lastTaskCountVar -or [int]$lastTaskCountVar.Value -ne $taskCount) {
        $shouldLogLoad = $true
        $script:UGSM_TaskDefinitionsLastLogCount = $taskCount
    }
    if ((Get-Variable -Name 'UGSM_EnableVerboseTaskLogging' -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseTaskLogging) {
        $shouldLogLoad = $true
    }

    if ($shouldLogLoad) {
        Write-UGSMTasksLog -Level 'DEBUG' -Message ("Loaded task definitions. Count={0}" -f $taskCount)
    }

    return $tasks
}

function Save-UGSMTaskDefinitions {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Tasks = @()
    )

    Save-UGSMJsonFile -Path (Get-UGSMTaskDefinitionsPath) -Data @($Tasks)
    Write-UGSMTasksLog -Level 'INFO' -Message ("Saved task definitions. Count={0}" -f @($Tasks).Count)
}

function Get-UGSMTaskHistory {
    [CmdletBinding()]
    param(
        [int]$MaxEntries = 50,
        [string]$InstanceId
    )

    $items = @(ConvertFrom-UGSMJsonFile -Path (Get-UGSMTaskHistoryPath))
    if (-not [string]::IsNullOrWhiteSpace($InstanceId)) {
        $items = @($items | Where-Object { [string]$_.TargetInstanceId -eq $InstanceId })
    }

    $items = @($items | Sort-Object {
            try { [datetime]$_.SortTime } catch { [datetime]::MinValue }
        } -Descending)

    if ($MaxEntries -gt 0) {
        $items = @($items | Select-Object -First $MaxEntries)
    }

    return $items
}

function Add-UGSMTaskHistoryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Entry
    )

    $history = @(ConvertFrom-UGSMJsonFile -Path (Get-UGSMTaskHistoryPath))
    $history = @($Entry) + @($history)
    $history = @($history | Select-Object -First 200)
    Save-UGSMJsonFile -Path (Get-UGSMTaskHistoryPath) -Data $history
    Write-UGSMTasksLog -Level 'DEBUG' -Message ("Added task history entry. Task={0}; Result={1}; TargetInstanceId={2}" -f [string]$Entry.Task, [string]$Entry.Result, [string]$Entry.TargetInstanceId)
}

function Get-UGSMTaskScheduleText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Task
    )

    switch ([string]$Task.ScheduleType) {
        'OneTime' {
            if (-not [string]::IsNullOrWhiteSpace([string]$Task.OneTimeAt)) {
                try {
                    return ('One time at {0}' -f ([datetime]$Task.OneTimeAt).ToString('g'))
                }
                catch {
                    return 'One time'
                }
            }

            return 'One time'
        }
        'Daily' {
            if (-not [string]::IsNullOrWhiteSpace([string]$Task.DailyTime)) {
                return ('Daily at {0}' -f [string]$Task.DailyTime)
            }

            return 'Daily'
        }
        default {
            return 'Manual'
        }
    }
}

function Get-UGSMTaskNextRunValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Task,

        [datetime]$Now = (Get-Date)
    )

    if (-not [bool]$Task.IsEnabled) {
        return $null
    }

    switch ([string]$Task.ScheduleType) {
        'OneTime' {
            if ([string]::IsNullOrWhiteSpace([string]$Task.OneTimeAt)) {
                return $null
            }

            try {
                $dt = [datetime]$Task.OneTimeAt
            }
            catch {
                return $null
            }

            if ($Task.LastRun -and -not [string]::IsNullOrWhiteSpace([string]$Task.LastRun)) {
                return $null
            }

            return $dt
        }
        'Daily' {
            if ([string]::IsNullOrWhiteSpace([string]$Task.DailyTime)) {
                return $null
            }

            try {
                $time = [datetime]::ParseExact([string]$Task.DailyTime, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                try {
                    $time = [datetime]::Parse([string]$Task.DailyTime)
                }
                catch {
                    return $null
                }
            }

            $next = Get-Date -Year $Now.Year -Month $Now.Month -Day $Now.Day -Hour $time.Hour -Minute $time.Minute -Second 0
            if ($next -le $Now) {
                $next = $next.AddDays(1)
            }

            return $next
        }
        default {
            return $null
        }
    }
}

function ConvertTo-UGSMTaskViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Task,

        [datetime]$Now = (Get-Date)
    )

    $nextRun = Get-UGSMTaskNextRunValue -Task $Task -Now $Now
    $schedule = Get-UGSMTaskScheduleText -Task $Task
    $status = if ([bool]$Task.IsEnabled) { 'Enabled' } else { 'Disabled' }

    if ($Task.LastResult -and -not [string]::IsNullOrWhiteSpace([string]$Task.LastResult) -and $status -eq 'Enabled') {
        $status = [string]$Task.LastResult
    }

    [pscustomobject]@{
        Id               = [string]$Task.Id
        Name             = [string]$Task.Name
        Type             = [string]$Task.Type
        Target           = [string]$Task.TargetInstanceName
        TargetInstanceId = [string]$Task.TargetInstanceId
        Schedule         = $schedule
        Status           = $status
        LastRun          = if ([string]::IsNullOrWhiteSpace([string]$Task.LastRun)) { 'Never' } else { [string]$Task.LastRun }
        NextRun          = if ($nextRun) { $nextRun.ToString('g') } else { 'N/A' }
        Active           = if ([bool]$Task.IsEnabled) { 'Yes' } else { 'No' }
        Result           = if ([string]::IsNullOrWhiteSpace([string]$Task.LastResult)) { 'N/A' } else { [string]$Task.LastResult }
        Notes            = if ([string]::IsNullOrWhiteSpace([string]$Task.Notes)) { '' } else { [string]$Task.Notes }
        ScheduleType     = [string]$Task.ScheduleType
        OneTimeAt        = [string]$Task.OneTimeAt
        DailyTime        = [string]$Task.DailyTime
        IsEnabled        = [bool]$Task.IsEnabled
    }
}

function New-UGSMTaskDefinition {
    [CmdletBinding()]
    param(
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Restart')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$TargetInstanceId,
        [Parameter(Mandatory)]
        [ValidateSet('OneTime', 'Daily')]
        [string]$ScheduleType,
        [string]$OneTimeAt,
        [string]$DailyTime,
        [bool]$IsEnabled = $true,
        [string]$Notes = ''
    )

    Write-UGSMTasksLog -Level 'INFO' -Message ("Save task requested. Id={0}; Name={1}; Type={2}; TargetInstanceId={3}; ScheduleType={4}; Enabled={5}" -f [string]$Id, [string]$Name, [string]$Type, [string]$TargetInstanceId, [string]$ScheduleType, [bool]$IsEnabled)

    $instance = Get-UGSMTaskTargetInstance -InstanceId $TargetInstanceId
    if (-not $instance) {
        throw 'Target instance could not be resolved.'
    }

    $tasks = @(Get-UGSMTaskDefinitions)
    $existing = $null
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $existing = @($tasks | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1)[0]
    }

    if (-not $existing) {
        $Id = if ([string]::IsNullOrWhiteSpace($Id)) { [guid]::NewGuid().Guid } else { $Id }
        $task = [pscustomobject]@{
            Id                 = $Id
            Name               = $Name
            Type               = $Type
            TargetInstanceId   = [string]$instance.Id
            TargetInstanceName = [string]$instance.Name
            TargetGameId       = [string]$instance.GameId
            ScheduleType       = $ScheduleType
            OneTimeAt          = $OneTimeAt
            DailyTime          = $DailyTime
            IsEnabled          = $IsEnabled
            LastRun            = ''
            LastResult         = ''
            Notes              = $Notes
            CreatedOn          = (Get-Date).ToString('o')
            UpdatedOn          = (Get-Date).ToString('o')
        }
        $tasks += $task
    }
    else {
        $existing.Name = $Name
        $existing.Type = $Type
        $existing.TargetInstanceId = [string]$instance.Id
        $existing.TargetInstanceName = [string]$instance.Name
        $existing.TargetGameId = [string]$instance.GameId
        $existing.ScheduleType = $ScheduleType
        $existing.OneTimeAt = $OneTimeAt
        $existing.DailyTime = $DailyTime
        $existing.IsEnabled = $IsEnabled
        $existing.Notes = $Notes
        $existing.UpdatedOn = (Get-Date).ToString('o')
    }

    Save-UGSMTaskDefinitions -Tasks $tasks
    $savedTask = @($tasks | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1)[0]
    Write-UGSMTasksLog -Level 'INFO' -Message ("Task saved. Id={0}; Name={1}; Type={2}; TargetInstanceId={3}; Enabled={4}" -f [string]$savedTask.Id, [string]$savedTask.Name, [string]$savedTask.Type, [string]$savedTask.TargetInstanceId, [bool]$savedTask.IsEnabled)
    return $savedTask
}

function Remove-UGSMTaskDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-UGSMTasksLog -Level 'INFO' -Message ("Remove task requested. Id={0}" -f [string]$Id)
    $tasks = @(Get-UGSMTaskDefinitions)
    $existing = @($tasks | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1)[0]
    $remaining = @($tasks | Where-Object { [string]$_.Id -ne $Id })
    Save-UGSMTaskDefinitions -Tasks $remaining
    Write-UGSMTasksLog -Level 'INFO' -Message ("Task removed. Id={0}; Found={1}; Remaining={2}" -f [string]$Id, [bool]$existing, @($remaining).Count)
    return $true
}

function Invoke-UGSMTaskInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Task,

        [switch]$TriggeredByScheduler
    )

    $started = Get-Date
    Write-UGSMTasksLog -Level 'INFO' -Message ("Task execution started. Id={0}; Name={1}; Type={2}; TargetInstanceId={3}; Scheduler={4}" -f [string]$Task.Id, [string]$Task.Name, [string]$Task.Type, [string]$Task.TargetInstanceId, [bool]$TriggeredByScheduler)
    $resultText = 'Success'
    $durationText = '0s'

    try {
        $instanceId = [string]$Task.TargetInstanceId
        if ([string]::IsNullOrWhiteSpace($instanceId)) {
            throw 'Task target instance is missing.'
        }

        if (-not $global:UGSM_AppState) {
            throw 'UGSM AppState is not available.'
        }

        if (Get-Command Invoke-UGSMInstanceAction -ErrorAction SilentlyContinue) {
            $null = Invoke-UGSMInstanceAction -Action ([string]$Task.Type) -AppState $global:UGSM_AppState -InstanceId $instanceId
        }
        else {
            switch ([string]$Task.Type) {
                'Start' {
                    if (-not (Get-Command Start-UGSMInstance -ErrorAction SilentlyContinue)) { throw 'Start-UGSMInstance is not available.' }
                    $null = Start-UGSMInstance -Id $instanceId
                }
                'Stop' {
                    if (-not (Get-Command Stop-UGSMInstance -ErrorAction SilentlyContinue)) { throw 'Stop-UGSMInstance is not available.' }
                    $null = Stop-UGSMInstance -Id $instanceId
                }
                'Restart' {
                    if (-not (Get-Command Stop-UGSMInstance -ErrorAction SilentlyContinue)) { throw 'Stop-UGSMInstance is not available.' }
                    if (-not (Get-Command Start-UGSMInstance -ErrorAction SilentlyContinue)) { throw 'Start-UGSMInstance is not available.' }
                    $null = Stop-UGSMInstance -Id $instanceId
                    Start-Sleep -Seconds 2
                    $null = Start-UGSMInstance -Id $instanceId
                }
            }
        }
    }
    catch {
        $resultText = ('Failed: {0}' -f [string]$_.Exception.Message)
        Write-UGSMTasksLog -Level 'ERROR' -Message ("Task execution failed. Id={0}; Name={1}; Type={2}; TargetInstanceId={3}" -f [string]$Task.Id, [string]$Task.Name, [string]$Task.Type, [string]$Task.TargetInstanceId) -Exception $_.Exception
    }
    finally {
        $ended = Get-Date
        $durationText = ('{0:n1}s' -f ($ended - $started).TotalSeconds)
    }

    $tasks = @(Get-UGSMTaskDefinitions)
    $storedTask = @($tasks | Where-Object { [string]$_.Id -eq [string]$Task.Id } | Select-Object -First 1)[0]
    if ($storedTask) {
        $storedTask.LastRun = $started.ToString('g')
        $storedTask.LastResult = $resultText
        $storedTask.UpdatedOn = (Get-Date).ToString('o')

        if ([string]$storedTask.ScheduleType -eq 'OneTime' -and $resultText -eq 'Success') {
            $storedTask.IsEnabled = $false
        }

        Save-UGSMTaskDefinitions -Tasks $tasks
    }

    Add-UGSMTaskHistoryEntry -Entry ([pscustomobject]@{
            Time             = $started.ToString('g')
            SortTime         = $started.ToString('o')
            Task             = [string]$Task.Name
            Result           = $resultText
            Duration         = $durationText
            TargetInstanceId = [string]$Task.TargetInstanceId
        })

    $finishLevel = if ($resultText -eq 'Success') { 'INFO' } else { 'WARN' }
    Write-UGSMTasksLog -Level $finishLevel -Message ("Task execution finished. Id={0}; Name={1}; Result={2}; Duration={3}" -f [string]$Task.Id, [string]$Task.Name, [string]$resultText, [string]$durationText)

    return [pscustomobject]@{
        Success  = ($resultText -eq 'Success')
        Result   = $resultText
        Duration = $durationText
    }
}

function Invoke-UGSMTaskNow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-UGSMTasksLog -Level 'INFO' -Message ("Run task now requested. Id={0}" -f [string]$Id)
    $task = @(Get-UGSMTaskDefinitions | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1)[0]
    if (-not $task) {
        throw 'Task not found.'
    }

    return (Invoke-UGSMTaskInternal -Task $task)
}

function Process-UGSMDueTasks {
    [CmdletBinding()]
    param()

    $now = Get-Date
    $tasks = @(Get-UGSMTaskDefinitions)
    foreach ($task in $tasks) {
        if (-not [bool]$task.IsEnabled) {
            continue
        }

        $next = Get-UGSMTaskNextRunValue -Task $task -Now $now
        if ($next -and $next -le $now) {
            Write-UGSMTasksLog -Level 'INFO' -Message ("Due task detected. Id={0}; Name={1}; Type={2}; NextRun={3}" -f [string]$task.Id, [string]$task.Name, [string]$task.Type, $next.ToString('o'))
            $null = Invoke-UGSMTaskInternal -Task $task -TriggeredByScheduler
        }
    }
}

function Start-UGSMTaskScheduler {
    [CmdletBinding()]
    param(
        [int]$IntervalSeconds = 15
    )

    $existingTimer = Get-UGSMTaskSchedulerTimer
    if ($existingTimer -and -not $existingTimer.IsDisposed) {
        $existingTimer.Interval = [Math]::Max(5000, ($IntervalSeconds * 1000))
        if (-not $existingTimer.Enabled) {
            $existingTimer.Start()
        }
        Write-UGSMTasksLog -Level 'DEBUG' -Message ("Task scheduler already exists. IntervalMs={0}; Enabled={1}" -f $existingTimer.Interval, $existingTimer.Enabled)
        return $existingTimer
    }

    $newTimer = New-Object System.Windows.Forms.Timer
    $newTimer.Interval = [Math]::Max(5000, ($IntervalSeconds * 1000))
    $newTimer.Add_Tick({
            try {
                Process-UGSMDueTasks
            }
            catch {
                Write-UGSMTasksLog -Level 'ERROR' -Message 'Task scheduler tick failed.' -Exception $_.Exception
            }
        })
    $newTimer.Start()
    $null = Set-UGSMTaskSchedulerTimer -Timer $newTimer
    Write-UGSMTasksLog -Level 'INFO' -Message ("Task scheduler started. IntervalMs={0}" -f $newTimer.Interval)
    return $newTimer
}

function Stop-UGSMTaskScheduler {
    [CmdletBinding()]
    param()

    $timer = Get-UGSMTaskSchedulerTimer
    if ($timer) {
        try { $timer.Stop() } catch {}
        try { $timer.Dispose() } catch {}
        Write-UGSMTasksLog -Level 'INFO' -Message 'Task scheduler stopped.'
        $null = Set-UGSMTaskSchedulerTimer -Timer $null
    }
}

function Get-UGSMTasksPageData {
    [CmdletBinding()]
    param(
        [string]$InstanceId
    )

    $instance = Get-UGSMTaskTargetInstance -InstanceId $InstanceId

    $targetInstanceName = if ($instance) { [string]$instance.Name } else { 'No Instance Selected' }
    $targetGameId = if ($instance -and $instance.GameId) { [string]$instance.GameId } else { '' }

    $gameName = if ([string]::IsNullOrWhiteSpace($targetGameId)) { 'Unknown' } else { $targetGameId }
    if ($targetGameId -and (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue)) {
        $game = Get-UGSMGameById -Id $targetGameId
        if ($game -and $game.Name) {
            $gameName = [string]$game.Name
        }
    }

    $allTasks = @(Get-UGSMTaskDefinitions)
    $tasksForInstance = if ($instance) {
        @($allTasks | Where-Object { [string]$_.TargetInstanceId -eq [string]$instance.Id })
    }
    else {
        @($allTasks)
    }

    $viewTasks = @($tasksForInstance | ForEach-Object { ConvertTo-UGSMTaskViewModel -Task $_ })
    $history = @(
        Get-UGSMTaskHistory -InstanceId $(if ($instance) { [string]$instance.Id } else { '' }) -MaxEntries 25 |
        ForEach-Object {
            [pscustomobject]@{
                Time     = [string]$_.Time
                Task     = [string]$_.Task
                Result   = [string]$_.Result
                Duration = [string]$_.Duration
            }
        }
    )

    $enabledCount = @($viewTasks | Where-Object { $_.IsEnabled }).Count
    $disabledCount = @($viewTasks | Where-Object { -not $_.IsEnabled }).Count

    $nextRunCandidate = @(
        $viewTasks |
            Where-Object {
                $value = ''
                if ($_.PSObject.Properties.Name -contains 'NextRun') { $value = [string]$_.NextRun }
                ($_.PSObject.Properties.Name -contains 'IsEnabled') -and [bool]$_.IsEnabled -and -not [string]::IsNullOrWhiteSpace($value) -and $value -ne 'N/A'
            } |
            Sort-Object NextRun |
            Select-Object -First 1
    )
    $nextRunValue = 'N/A'
    if ($nextRunCandidate.Count -gt 0 -and ($nextRunCandidate[0].PSObject.Properties.Name -contains 'NextRun')) {
        $candidateNextRun = [string]$nextRunCandidate[0].NextRun
        if (-not [string]::IsNullOrWhiteSpace($candidateNextRun)) {
            $nextRunValue = $candidateNextRun
        }
    }

    $lastResultCandidate = @(
        $viewTasks |
            Where-Object {
                $value = ''
                if ($_.PSObject.Properties.Name -contains 'Result') { $value = [string]$_.Result }
                -not [string]::IsNullOrWhiteSpace($value) -and $value -ne 'N/A'
            } |
            Select-Object -First 1
    )
    $lastResultValue = 'N/A'
    if ($lastResultCandidate.Count -gt 0 -and ($lastResultCandidate[0].PSObject.Properties.Name -contains 'Result')) {
        $candidateResult = [string]$lastResultCandidate[0].Result
        if (-not [string]::IsNullOrWhiteSpace($candidateResult)) {
            $lastResultValue = $candidateResult
        }
    }

    $selectedTask = if (@($viewTasks).Count -gt 0) { @($viewTasks)[0] } else { $null }

    $pageInstanceId = if ($instance) { [string]$instance.Id } else { '' }
    Write-UGSMTasksLog -Level 'DEBUG' -Message ("Tasks page data built. InstanceId={0}; Tasks={1}; History={2}; Enabled={3}; Disabled={4}" -f $pageInstanceId, @($viewTasks).Count, @($history).Count, $enabledCount, $disabledCount)

    return [pscustomobject]@{
        InstanceId   = if ($instance) { [string]$instance.Id } else { '' }
        InstanceName = $targetInstanceName
        GameName     = $gameName
        Metrics      = @(
            [pscustomobject]@{ Label = 'Active Tasks'; Value = $enabledCount }
            [pscustomobject]@{ Label = 'Disabled'; Value = $disabledCount }
            [pscustomobject]@{ Label = 'Next Run'; Value = $nextRunValue }
            [pscustomobject]@{ Label = 'Last Result'; Value = $lastResultValue }
        )
        Tasks        = $viewTasks
        SelectedTask = $selectedTask
        History      = $history
        Notes        = @(
            'Start tasks can bring a server online before peak hours or after maintenance.'
            'Restart tasks are best for daily upkeep once graceful warnings are added later.'
            'One-time tasks disable themselves after a successful run so they do not repeat.'
            'Daily schedules run only while UGSM is open in this build. Background scheduling can come later.'
        )
        StatusText   = if ($instance) { "Showing task data for $targetInstanceName" } else { 'Select an instance to view task data.' }
    }
}
