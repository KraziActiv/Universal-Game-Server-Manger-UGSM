# Machine Monitor Service
# Optimized startup version:
# - Does not block UGSM startup with a full machine scan.
# - Seeds a lightweight snapshot immediately.
# - Refreshes metrics on a timer after the UI is allowed to open.
# - Throttles expensive disk checks separately from CPU/memory checks.
# - Disk refresh defaults to 30 minutes and can be forced after installs/mod sync.
# - Normal 5-second monitor ticks stay quiet unless a tick is slow or disk is included.
# - CPU/memory snapshots are throttled separately so the UI thread is not hit by expensive checks every tick.

$script:UGSM_MachineMonitorCommandCache = $null

function Write-UGSMMachineMonitorLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'DEBUG',

        [System.Exception]$Exception
    )

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            Write-UGSMLog -Level $Level -Category 'MachineMonitor' -Message $Message -Exception $Exception
        }
    }
    catch {
        # Monitoring/logging should never crash UGSM.
    }
}

function Get-UGSMCurrentAppState {
    [CmdletBinding()]
    param()

    if ($global:UGSM_AppState) {
        return $global:UGSM_AppState
    }

    return $null
}

function Get-UGSMMachineMonitorCommandCache {
    [CmdletBinding()]
    param([switch]$Refresh)

    if ($Refresh -or -not $script:UGSM_MachineMonitorCommandCache) {
        $script:UGSM_MachineMonitorCommandCache = [pscustomobject]@{
            CpuSnapshot      = [bool](Get-Command Get-UGSMCpuSnapshot -ErrorAction SilentlyContinue)
            CpuCounterInit   = [bool](Get-Command Initialize-UGSMCpuCounter -ErrorAction SilentlyContinue)
            MemorySnapshot   = [bool](Get-Command Get-UGSMMemorySnapshot -ErrorAction SilentlyContinue)
            DiskCardData     = [bool](Get-Command Get-UGSMDiskCardData -ErrorAction SilentlyContinue)
            ResolvedAt       = Get-Date
        }

        Write-UGSMMachineMonitorLog -Message ('Command cache resolved. CPU={0}; CpuInit={1}; Memory={2}; Disk={3}' -f `
            $script:UGSM_MachineMonitorCommandCache.CpuSnapshot, `
            $script:UGSM_MachineMonitorCommandCache.CpuCounterInit, `
            $script:UGSM_MachineMonitorCommandCache.MemorySnapshot, `
            $script:UGSM_MachineMonitorCommandCache.DiskCardData)
    }

    return $script:UGSM_MachineMonitorCommandCache
}

function New-UGSMMachineMetricsPlaceholder {
    [CmdletBinding()]
    param()

    $now = Get-Date
    return [pscustomobject]@{
        CpuPercent          = 0.0
        MemoryPercent       = 0.0
        DiskPercent         = 0.0
        HealthState         = 'Loading'
        HealthMessage       = 'Machine monitor is starting. Capacity checks will update shortly.'
        CanStartMoreServers = $false
        LastUpdated         = $now
        Cpu                 = $null
        Memory              = $null
        Disk                = $null
        IsPlaceholder       = $true
        IsDiskStale         = $true
    }
}

function Get-UGSMMachineMetricsSnapshot {
    [CmdletBinding()]
    param(
        [object]$PreviousSnapshot,
        [switch]$IncludeDisk
    )

    $commands = Get-UGSMMachineMonitorCommandCache

    $cpuSnapshot = $null
    $memorySnapshot = $null
    $diskSnapshot = $null

    $metricWatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($commands.CpuSnapshot) {
        try { $cpuSnapshot = Get-UGSMCpuSnapshot } catch { Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'CPU snapshot failed.' -Exception $_.Exception }
    }

    if ($commands.MemorySnapshot) {
        try { $memorySnapshot = Get-UGSMMemorySnapshot } catch { Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'Memory snapshot failed.' -Exception $_.Exception }
    }

    if ($IncludeDisk -and $commands.DiskCardData) {
        try { $diskSnapshot = Get-UGSMDiskCardData } catch { Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'Disk snapshot failed.' -Exception $_.Exception }
    }
    elseif ($PreviousSnapshot -and $PreviousSnapshot.PSObject.Properties['Disk']) {
        $diskSnapshot = $PreviousSnapshot.Disk
    }

    $metricWatch.Stop()
    if ($metricWatch.ElapsedMilliseconds -ge 750) {
        Write-UGSMMachineMonitorLog -Level 'WARN' -Message ('Metrics snapshot took {0} ms. IncludeDisk={1}' -f $metricWatch.ElapsedMilliseconds, [bool]$IncludeDisk)
    }
    elseif ($IncludeDisk) {
        Write-UGSMMachineMonitorLog -Level 'DEBUG' -Message ('Disk metrics snapshot took {0} ms.' -f $metricWatch.ElapsedMilliseconds)
    }

    $cpuPercent = if ($cpuSnapshot -and $cpuSnapshot.PSObject.Properties['Percent']) { [double]$cpuSnapshot.Percent } elseif ($PreviousSnapshot) { [double]$PreviousSnapshot.CpuPercent } else { 0.0 }
    $memoryPercent = if ($memorySnapshot -and $memorySnapshot.PSObject.Properties['Percent']) { [double]$memorySnapshot.Percent } elseif ($PreviousSnapshot) { [double]$PreviousSnapshot.MemoryPercent } else { 0.0 }

    $diskPercent = 0.0
    $diskFreePercent = 100.0
    $isDiskStale = -not $IncludeDisk

    if ($diskSnapshot -and $diskSnapshot.PSObject.Properties['PrimaryDisk'] -and $diskSnapshot.PrimaryDisk) {
        if ($diskSnapshot.PrimaryDisk.PSObject.Properties['PercentUsed']) { $diskPercent = [double]$diskSnapshot.PrimaryDisk.PercentUsed }
        if ($diskSnapshot.PrimaryDisk.PSObject.Properties['PercentFree']) { $diskFreePercent = [double]$diskSnapshot.PrimaryDisk.PercentFree }
    }
    elseif ($PreviousSnapshot -and $PreviousSnapshot.PSObject.Properties['DiskPercent']) {
        $diskPercent = [double]$PreviousSnapshot.DiskPercent
        if ($diskPercent -gt 0) { $diskFreePercent = 100.0 - $diskPercent }
        $isDiskStale = $true
    }

    $hasAnyRealMetric = ($cpuSnapshot -or $memorySnapshot -or $diskSnapshot)
    $hasDiskMetric = ($diskSnapshot -and $diskSnapshot.PSObject.Properties['PrimaryDisk'] -and $diskSnapshot.PrimaryDisk)

    $healthState = if (-not $hasAnyRealMetric) {
        'Loading'
    }
    elseif ($cpuPercent -ge 90 -or $memoryPercent -ge 90 -or ($hasDiskMetric -and $diskFreePercent -lt 10)) {
        'Critical'
    }
    elseif ($cpuPercent -ge 75 -or $memoryPercent -ge 80 -or ($hasDiskMetric -and $diskFreePercent -lt 15)) {
        'Warning'
    }
    else {
        'Healthy'
    }

    $healthMessage = switch ($healthState) {
        'Loading'  { 'Machine monitor is collecting system metrics.' }
        'Critical' { 'System pressure is high. New starts should be blocked until capacity recovers.' }
        'Warning'  { 'System is approaching recommended limits. Review load before starting more servers.' }
        default    { 'System remains within a safe operating range.' }
    }

    return [pscustomobject]@{
        CpuPercent          = [Math]::Round($cpuPercent, 1)
        MemoryPercent       = [Math]::Round($memoryPercent, 1)
        DiskPercent         = [Math]::Round($diskPercent, 1)
        HealthState         = $healthState
        HealthMessage       = $healthMessage
        CanStartMoreServers = ($healthState -eq 'Healthy' -or $healthState -eq 'Warning')
        LastUpdated         = Get-Date
        Cpu                 = $cpuSnapshot
        Memory              = $memorySnapshot
        Disk                = $diskSnapshot
        IsPlaceholder       = (-not $hasAnyRealMetric)
        IsDiskStale         = [bool]$isDiskStale
    }
}

function Ensure-UGSMMachineMonitorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [int]$RefreshSeconds = 5,
        [int]$DiskRefreshSeconds = 1800,
        [int]$InitialDiskDelaySeconds = 300,
        [int]$MetricsRefreshSeconds = 30
    )

    if (-not $AppState.MachineMonitor) {
        $AppState | Add-Member -NotePropertyName MachineMonitor -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $properties = @{
        RefreshSeconds          = $RefreshSeconds
        DiskRefreshSeconds      = $DiskRefreshSeconds
        InitialDiskDelaySeconds = $InitialDiskDelaySeconds
        MetricsRefreshSeconds     = $MetricsRefreshSeconds
        Timer                   = $null
        IsRunning               = $false
        IsUpdating              = $false
        LastRefreshStarted      = $null
        LastRefreshCompleted    = $null
        LastDiskRefresh         = $null
        LastMetricsRefresh      = $null
        StartedAt               = $null
    }

    foreach ($entry in $properties.GetEnumerator()) {
        if (-not $AppState.MachineMonitor.PSObject.Properties[$entry.Key]) {
            $AppState.MachineMonitor | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value -Force
        }
    }

    $AppState.MachineMonitor.RefreshSeconds = $RefreshSeconds
    $AppState.MachineMonitor.DiskRefreshSeconds = $DiskRefreshSeconds
    $AppState.MachineMonitor.InitialDiskDelaySeconds = $InitialDiskDelaySeconds
    $AppState.MachineMonitor.MetricsRefreshSeconds = $MetricsRefreshSeconds

    return $AppState.MachineMonitor
}

function Add-UGSMMachineHistoryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$History,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [int]$Value,
        [int]$MaxPoints = 24
    )

    if ($MaxPoints -lt 2) { $MaxPoints = 24 }

    $existing = @()
    if ($History.PSObject.Properties[$PropertyName] -and $History.$PropertyName) {
        $existing = @($History.$PropertyName)
    }

    $History.$PropertyName = @($existing + $Value | Select-Object -Last $MaxPoints)
}

function Update-UGSMMachineMonitor {
    [CmdletBinding()]
    param(
        [object]$AppState,
        [switch]$ForceDisk
    )

    if (-not $AppState) {
        $AppState = Get-UGSMCurrentAppState
    }

    if (-not $AppState) {
        return
    }

    $monitor = Ensure-UGSMMachineMonitorState -AppState $AppState
    if ($monitor.IsUpdating) {
        return $AppState.CachedSystemMetrics
    }

    $monitor.IsUpdating = $true
    $monitor.LastRefreshStarted = Get-Date
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $now = Get-Date
        $includeDisk = [bool]$ForceDisk

        if (-not $includeDisk) {
            $ageSinceStart = if ($monitor.StartedAt) { ($now - [datetime]$monitor.StartedAt).TotalSeconds } else { 999999 }
            $diskAge = if ($monitor.LastDiskRefresh) { ($now - [datetime]$monitor.LastDiskRefresh).TotalSeconds } else { 999999 }

            if ($ageSinceStart -ge [int]$monitor.InitialDiskDelaySeconds -and $diskAge -ge [int]$monitor.DiskRefreshSeconds) {
                $includeDisk = $true
            }
        }

        $previousSnapshot = $AppState.CachedSystemMetrics
        $metricsAge = if ($monitor.LastMetricsRefresh) { ($now - [datetime]$monitor.LastMetricsRefresh).TotalSeconds } else { 999999 }
        $metricsRefreshSeconds = if ($monitor.PSObject.Properties['MetricsRefreshSeconds']) { [int]$monitor.MetricsRefreshSeconds } else { 30 }
        if ($metricsRefreshSeconds -lt 5) { $metricsRefreshSeconds = 5 }

        $needsMetricsRefresh = [bool]$ForceDisk -or $includeDisk -or -not $previousSnapshot -or `
            ($previousSnapshot.PSObject.Properties['IsPlaceholder'] -and [bool]$previousSnapshot.IsPlaceholder) -or `
            ($metricsAge -ge $metricsRefreshSeconds)

        if (-not $needsMetricsRefresh) {
            return $previousSnapshot
        }

        $snapshot = Get-UGSMMachineMetricsSnapshot -PreviousSnapshot $previousSnapshot -IncludeDisk:$includeDisk

        if (-not $snapshot) {
            return $AppState.CachedSystemMetrics
        }

        if ($includeDisk -and -not $snapshot.IsDiskStale) {
            $monitor.LastDiskRefresh = $snapshot.LastUpdated
        }
        $monitor.LastMetricsRefresh = $snapshot.LastUpdated

        $AppState.CachedSystemMetrics = $snapshot
        $AppState.MachineStatus = $snapshot

        if (-not $AppState.AnalyticsHistory) {
            $AppState.AnalyticsHistory = [pscustomobject]@{
                Cpu         = @()
                Memory      = @()
                Disk        = @()
                MaxPoints   = 24
                LastUpdated = $null
            }
        }

        $history = $AppState.AnalyticsHistory
        $maxPoints = if ($history.PSObject.Properties['MaxPoints']) { [int]$history.MaxPoints } else { 24 }
        if ($maxPoints -lt 2) { $maxPoints = 24 }

        Add-UGSMMachineHistoryPoint -History $history -PropertyName 'Cpu' -Value ([int][Math]::Round($snapshot.CpuPercent)) -MaxPoints $maxPoints
        Add-UGSMMachineHistoryPoint -History $history -PropertyName 'Memory' -Value ([int][Math]::Round($snapshot.MemoryPercent)) -MaxPoints $maxPoints
        Add-UGSMMachineHistoryPoint -History $history -PropertyName 'Disk' -Value ([int][Math]::Round($snapshot.DiskPercent)) -MaxPoints $maxPoints
        $history.LastUpdated = $snapshot.LastUpdated

        return $snapshot
    }
    catch {
        Write-UGSMMachineMonitorLog -Level 'ERROR' -Message 'Machine monitor update failed.' -Exception $_.Exception
        return $AppState.CachedSystemMetrics
    }
    finally {
        $watch.Stop()
        $monitor.IsUpdating = $false
        $monitor.LastRefreshCompleted = Get-Date

        if ($watch.ElapsedMilliseconds -ge 750) {
            Write-UGSMMachineMonitorLog -Level 'WARN' -Message ('Machine monitor update finished in {0} ms.' -f $watch.ElapsedMilliseconds)
        }
        elseif ($ForceDisk) {
            Write-UGSMMachineMonitorLog -Level 'DEBUG' -Message ('Forced disk monitor update finished in {0} ms.' -f $watch.ElapsedMilliseconds)
        }
    }
}


function Invoke-UGSMMachineDiskRefresh {
    [CmdletBinding()]
    param(
        [object]$AppState,
        [string]$Reason = 'Manual disk refresh requested.'
    )

    if (-not $AppState) {
        $AppState = Get-UGSMCurrentAppState
    }

    if (-not $AppState) {
        Write-UGSMMachineMonitorLog -Level 'WARN' -Message ('Disk refresh skipped because app state was unavailable. Reason={0}' -f $Reason)
        return $null
    }

    Write-UGSMMachineMonitorLog -Level 'INFO' -Message ('Forcing disk refresh. Reason={0}' -f $Reason)
    return (Update-UGSMMachineMonitor -AppState $AppState -ForceDisk)
}

function Request-UGSMMachineDiskRefresh {
    [CmdletBinding()]
    param(
        [object]$AppState,
        [string]$Reason = 'Disk refresh requested.'
    )

    # Friendly alias-style wrapper for install/mod/service code.
    return (Invoke-UGSMMachineDiskRefresh -AppState $AppState -Reason $Reason)
}

function Get-UGSMLatestMachineMetrics {
    [CmdletBinding()]
    param(
        [switch]$RefreshIfMissing,
        [switch]$ForceRefresh
    )

    $appState = Get-UGSMCurrentAppState
    if (-not $appState) {
        return $null
    }

    if ($ForceRefresh) {
        return (Update-UGSMMachineMonitor -AppState $appState -ForceDisk)
    }

    if ($RefreshIfMissing -and -not $appState.CachedSystemMetrics) {
        $appState.CachedSystemMetrics = New-UGSMMachineMetricsPlaceholder
        $appState.MachineStatus = $appState.CachedSystemMetrics
    }

    return $appState.CachedSystemMetrics
}

function Start-UGSMCpuCounterPrime {
    [CmdletBinding()]
    param(
        [int]$DelayMilliseconds = 3000
    )

    if (-not (Get-Command Initialize-UGSMCpuCounter -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        $primeTimer = New-Object System.Windows.Forms.Timer
        $primeTimer.Interval = [Math]::Max(250, $DelayMilliseconds)

        $primeAction = {
            $timerInstance = $this
            try {
                $timerInstance.Stop()
            }
            catch {
                # Stopping a timer should not crash the prime.
            }

            $primeWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $primeOk = $false
            try {
                $primeOk = [bool](Initialize-UGSMCpuCounter)
            }
            catch {
                Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'CPU counter prime threw.' -Exception $_.Exception
            }
            $primeWatch.Stop()

            if ($primeOk) {
                Write-UGSMMachineMonitorLog -Level 'INFO' -Message ('CPU counter primed in {0} ms.' -f $primeWatch.ElapsedMilliseconds)
            }
            else {
                Write-UGSMMachineMonitorLog -Level 'WARN' -Message ('CPU counter prime failed after {0} ms.' -f $primeWatch.ElapsedMilliseconds)
            }

            try {
                $timerInstance.Dispose()
            }
            catch {
                # Disposing a timer should not crash the prime.
            }
        }.GetNewClosure()

        $primeTimer.Add_Tick($primeAction)
        $primeTimer.Start()
    }
    catch {
        Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'Failed to schedule CPU counter prime.' -Exception $_.Exception
    }
}

function Start-UGSMMachineMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [int]$RefreshSeconds = 5,
        [int]$DiskRefreshSeconds = 1800,
        [int]$InitialDiskDelaySeconds = 300,
        [int]$MetricsRefreshSeconds = 30,
        [switch]$RunInitialFullRefresh
    )

    $monitor = Ensure-UGSMMachineMonitorState `
        -AppState $AppState `
        -RefreshSeconds $RefreshSeconds `
        -DiskRefreshSeconds $DiskRefreshSeconds `
        -InitialDiskDelaySeconds $InitialDiskDelaySeconds `
        -MetricsRefreshSeconds $MetricsRefreshSeconds

    if ($monitor.Timer -and $monitor.IsRunning) {
        return $monitor.Timer
    }

    $monitor.StartedAt = Get-Date

    if (-not $AppState.CachedSystemMetrics) {
        $AppState.CachedSystemMetrics = New-UGSMMachineMetricsPlaceholder
        $AppState.MachineStatus = $AppState.CachedSystemMetrics
    }

    $commands = Get-UGSMMachineMonitorCommandCache

    if ($commands.CpuCounterInit) {
        Start-UGSMCpuCounterPrime
    }

    if ($RunInitialFullRefresh) {
        [void](Update-UGSMMachineMonitor -AppState $AppState -ForceDisk)
    }
    else {
        Write-UGSMMachineMonitorLog -Level 'INFO' -Message ('Machine monitor started with deferred refresh. Timer={0}s; MetricsRefresh={1}s; DiskRefresh={2}s; InitialDiskDelay={3}s.' -f $RefreshSeconds, $MetricsRefreshSeconds, $DiskRefreshSeconds, $InitialDiskDelaySeconds)
    }

    $tickAction = {
        try {
            [void](Update-UGSMMachineMonitor -AppState $AppState)
        }
        catch {
            Write-UGSMMachineMonitorLog -Level 'ERROR' -Message 'Machine monitor timer tick failed.' -Exception $_.Exception
        }
    }.GetNewClosure()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1000, ($RefreshSeconds * 1000))
    $timer.Add_Tick($tickAction)
    $timer.Start()

    $monitor.RefreshSeconds = $RefreshSeconds
    $monitor.DiskRefreshSeconds = $DiskRefreshSeconds
    $monitor.InitialDiskDelaySeconds = $InitialDiskDelaySeconds
    $monitor.MetricsRefreshSeconds = $MetricsRefreshSeconds
    $monitor.Timer = $timer
    $monitor.IsRunning = $true

    return $timer
}

function Stop-UGSMMachineMonitor {
    [CmdletBinding()]
    param(
        [object]$AppState
    )

    if (-not $AppState) {
        $AppState = Get-UGSMCurrentAppState
    }

    if (-not $AppState -or -not $AppState.MachineMonitor -or -not $AppState.MachineMonitor.Timer) {
        return
    }

    try {
        $AppState.MachineMonitor.Timer.Stop()
        $AppState.MachineMonitor.Timer.Dispose()
        Write-UGSMMachineMonitorLog -Level 'INFO' -Message 'Machine monitor stopped.'
    }
    catch {
        Write-UGSMMachineMonitorLog -Level 'WARN' -Message 'Machine monitor stop failed.' -Exception $_.Exception
    }

    $AppState.MachineMonitor.Timer = $null
    $AppState.MachineMonitor.IsRunning = $false
    $AppState.MachineMonitor.IsUpdating = $false
}
