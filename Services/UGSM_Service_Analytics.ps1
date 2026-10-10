# Analytics Service

function Test-UGSMAnalyticsVerboseLogging {
    [CmdletBinding()]
    param()

    try {
        if ((Get-Variable -Name 'UGSM_EnableVerboseAnalyticsLogging' -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseAnalyticsLogging) { return $true }
        if ([string]::Equals($env:UGSM_VERBOSE_ANALYTICS, '1', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    catch { }

    return $false
}

function Write-UGSMAnalyticsLog {
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
            Write-UGSMLog -Level $Level -Category 'Analytics' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'Analytics' -Message $Message
        }
        return
    }

    if ($Level -in @('WARN','ERROR','FATAL')) {
        Write-Warning ('[Analytics] {0}' -f $Message)
    }
}



function Get-UGSMAnalyticsSafeCount {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return 0 }

    try {
        if ($Value -is [System.Array]) { return [int]$Value.Length }
        if ($Value -is [System.Collections.ICollection]) { return [int]$Value.Count }
        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            $count = 0
            foreach ($item in $Value) { $count++ }
            return [int]$count
        }
    }
    catch { }

    return 1
}


function Test-UGSMAnalyticsHasProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Object) { return $false }

    try {
        return ($Object.PSObject.Properties.Name -contains $Name)
    }
    catch {
        return $false
    }
}

function Get-UGSMAnalyticsPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }

    try {
        if ($Object.PSObject.Properties.Name -contains $Name) {
            $value = $Object.PSObject.Properties[$Name].Value
            if ($null -ne $value) { return $value }
        }
    }
    catch { }

    return $Default
}

function Get-UGSMAnalyticsFirstItem {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    try {
        $items = @($Value)
        if ($items.Count -gt 0) {
            return $items[0]
        }
    }
    catch { }

    return $null
}

function ConvertTo-UGSMAnalyticsPercent {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [double]$Default = 0.0
    )

    try {
        if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
            return [double]$Value
        }
    }
    catch { }

    return $Default
}

function ConvertTo-UGSMAnalyticsText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [string]$Default = ''
    )

    try {
        if ($null -ne $Value) {
            return [string]$Value
        }
    }
    catch { }

    return $Default
}


function Get-UGSMAnalyticsPageData {
    [CmdletBinding()]
    param(
        [object]$AppState
    )

    $analyticsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not $AppState -and (Get-Command Get-UGSMCurrentAppState -ErrorAction SilentlyContinue)) {
            $AppState = Get-UGSMCurrentAppState
        }

        $instances = if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
            @(Get-UGSMInstances)
        }
        else {
            @()
        }

        $runningCount = @($instances | Where-Object { (ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $_ -Name 'Status' -Default '') -Default '') -eq 'Running' }).Count
        $startingCount = @($instances | Where-Object { (ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $_ -Name 'Status' -Default '') -Default '') -eq 'Starting' }).Count
        $stoppedCount = @($instances | Where-Object { (ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $_ -Name 'Status' -Default '') -Default '') -eq 'Stopped' }).Count
        $totalCount = Get-UGSMAnalyticsSafeCount -Value $instances

        $selectedInstance = $null
        $appSelectedInstance = Get-UGSMAnalyticsPropertyValue -Object $AppState -Name 'SelectedInstance' -Default $null
        $appSelectedInstanceId = Get-UGSMAnalyticsPropertyValue -Object $AppState -Name 'SelectedInstanceId' -Default $null

        if ($appSelectedInstance) {
            $selectedInstance = $appSelectedInstance
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$appSelectedInstanceId)) {
            $selectedInstance = Get-UGSMAnalyticsFirstItem -Value @(
                $instances |
                Where-Object { (ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $_ -Name 'Id' -Default '') -Default '') -eq [string]$appSelectedInstanceId }
            )
        }

        if (-not $selectedInstance) {
            $selectedInstance = Get-UGSMAnalyticsFirstItem -Value @(
                $instances |
                Where-Object { (ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $_ -Name 'Status' -Default '') -Default '') -eq 'Running' }
            )
        }

        if (-not $selectedInstance) {
            $selectedInstance = Get-UGSMAnalyticsFirstItem -Value $instances
        }

        $selectedGame = $null
        $selectedGameId = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'GameId' -Default '') -Default ''
        if (-not [string]::IsNullOrWhiteSpace($selectedGameId) -and (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue)) {
            $selectedGame = Get-UGSMGameById -Id $selectedGameId
        }

        $selectedArtPath = ''
        if ($selectedGame -and (Get-Command Get-UGSMGameHeaderArt -ErrorAction SilentlyContinue)) {
            $selectedArtPath = Get-UGSMGameHeaderArt -Game $selectedGame
        }

        $machineMetrics = $null
        $cachedMetrics = Get-UGSMAnalyticsPropertyValue -Object $AppState -Name 'CachedSystemMetrics' -Default $null
        if ($cachedMetrics) {
            $machineMetrics = $cachedMetrics
        }
        elseif (Get-Command Get-UGSMLatestMachineMetrics -ErrorAction SilentlyContinue) {
            $machineMetrics = Get-UGSMLatestMachineMetrics -RefreshIfMissing
        }

        $cpuSnapshot = Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'Cpu' -Default $null
        $memorySnapshot = Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'Memory' -Default $null
        $diskCard = Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'Disk' -Default $null

        $cpuCurrent = ConvertTo-UGSMAnalyticsPercent -Value (Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'CpuPercent' -Default 0.0) -Default 0.0
        $ramCurrent = ConvertTo-UGSMAnalyticsPercent -Value (Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'MemoryPercent' -Default 0.0) -Default 0.0
        $diskCurrent = ConvertTo-UGSMAnalyticsPercent -Value (Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'DiskPercent' -Default 0.0) -Default 0.0

        $primaryDisk = Get-UGSMAnalyticsPropertyValue -Object $diskCard -Name 'PrimaryDisk' -Default $null
        $primaryDiskPercentFree = ConvertTo-UGSMAnalyticsPercent -Value (Get-UGSMAnalyticsPropertyValue -Object $primaryDisk -Name 'PercentFree' -Default 100.0) -Default 100.0

        $machineHealthState = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'HealthState' -Default '') -Default ''
        if (-not [string]::IsNullOrWhiteSpace($machineHealthState)) {
            $capacityState = $machineHealthState
        }
        elseif ($cpuCurrent -ge 90 -or $ramCurrent -ge 90 -or $primaryDiskPercentFree -lt 10) {
            $capacityState = 'Critical'
        }
        elseif ($cpuCurrent -ge 75 -or $ramCurrent -ge 80 -or $primaryDiskPercentFree -lt 15) {
            $capacityState = 'Warning'
        }
        else {
            $capacityState = 'Healthy'
        }

        $machineHealthMessage = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'HealthMessage' -Default '') -Default ''
        if (-not [string]::IsNullOrWhiteSpace($machineHealthMessage)) {
            $capacityMessage = $machineHealthMessage
        }
        else {
            switch ($capacityState) {
                'Critical' { $capacityMessage = 'System pressure is high. New starts should be blocked until capacity recovers.' }
                'Warning' { $capacityMessage = 'System is approaching recommended limits. Review load before starting more servers.' }
                default { $capacityMessage = 'System remains within a safe operating range.' }
            }
        }

        $history = Get-UGSMAnalyticsPropertyValue -Object $AppState -Name 'AnalyticsHistory' -Default $null
        $historyCpu = Get-UGSMAnalyticsPropertyValue -Object $history -Name 'Cpu' -Default $null
        $historyMemory = Get-UGSMAnalyticsPropertyValue -Object $history -Name 'Memory' -Default $null
        $historyDisk = Get-UGSMAnalyticsPropertyValue -Object $history -Name 'Disk' -Default $null

        $cpuSeries = if ((Get-UGSMAnalyticsSafeCount -Value $historyCpu) -gt 0) {
            @($historyCpu)
        }
        else {
            @([Math]::Max(0, [int][Math]::Round($cpuCurrent)))
        }

        $ramSeries = if ((Get-UGSMAnalyticsSafeCount -Value $historyMemory) -gt 0) {
            @($historyMemory)
        }
        else {
            @([Math]::Max(0, [int][Math]::Round($ramCurrent)))
        }

        $diskSeries = if ((Get-UGSMAnalyticsSafeCount -Value $historyDisk) -gt 0) {
            @($historyDisk)
        }
        else {
            @([Math]::Max(0, [int][Math]::Round($diskCurrent)))
        }

        $monitoredInstances = @(foreach ($instance in $instances) {
            $ports = @()
            $instancePorts = Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Ports' -Default $null
            if ($instancePorts) {
                foreach ($name in @($instancePorts.PSObject.Properties.Name)) {
                    $ports += ('{0}:{1}' -f $name, $instancePorts.PSObject.Properties[$name].Value)
                }
            }

            $mods = @(Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Mods' -Default @())
            $status = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Status' -Default 'Stopped') -Default 'Stopped'

            $health = switch ($status) {
                'Running' { 'Healthy' }
                'Starting' { 'Watch' }
                default { 'Idle' }
            }

            $gameId = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'GameId' -Default '') -Default ''
            $gameName = $gameId
            if (-not [string]::IsNullOrWhiteSpace($gameId) -and (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue)) {
                $g = Get-UGSMGameById -Id $gameId
                $gName = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $g -Name 'Name' -Default '') -Default ''
                if (-not [string]::IsNullOrWhiteSpace($gName)) {
                    $gameName = $gName
                }
            }

            $instanceMap = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Map' -Default '') -Default ''
            $installPath = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'InstallPath' -Default '') -Default ''

            [pscustomobject]@{
                Id          = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Id' -Default '') -Default ''
                Name        = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $instance -Name 'Name' -Default '') -Default ''
                GameId      = $gameId
                GameName    = $gameName
                Status      = $status
                Map         = if ([string]::IsNullOrWhiteSpace($instanceMap)) { 'Not set' } else { $instanceMap }
                InstallPath = if ([string]::IsNullOrWhiteSpace($installPath)) { 'Not configured' } else { $installPath }
                PortsText   = if ((Get-UGSMAnalyticsSafeCount -Value $ports) -gt 0) { ($ports -join '  ') } else { 'Ports not assigned' }
                ModsText    = if ((Get-UGSMAnalyticsSafeCount -Value $mods) -gt 0) { ($mods -join ', ') } else { 'No mods loaded' }
                ModCount    = (Get-UGSMAnalyticsSafeCount -Value $mods)
                Health      = $health
            }
        })

        $alerts = New-Object System.Collections.Generic.List[string]

        if ($capacityState -eq 'Critical') {
            [void]$alerts.Add('Machine capacity is critical. Start actions should be blocked.')
        }
        elseif ($capacityState -eq 'Warning') {
            [void]$alerts.Add('Machine capacity is approaching warning thresholds.')
        }

        if ($primaryDisk -and $primaryDiskPercentFree -lt 15) {
            $driveLetter = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $primaryDisk -Name 'DriveLetter' -Default 'install disk') -Default 'install disk'
            [void]$alerts.Add(('Install disk free space is low on {0}.' -f $driveLetter))
        }

        if ((Get-UGSMAnalyticsSafeCount -Value $alerts) -eq 0) {
            [void]$alerts.Add('No active analytics alerts.')
        }

        $events = New-Object System.Collections.Generic.List[string]
        $lastUpdatedValue = Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'LastUpdated' -Default $null
        $lastUpdatedText = if ($lastUpdatedValue) {
            try { ([datetime]$lastUpdatedValue).ToString('HH:mm:ss') } catch { (Get-Date).ToString('HH:mm:ss') }
        }
        else {
            (Get-Date).ToString('HH:mm:ss')
        }

        [void]$events.Add(('Analytics snapshot refreshed at {0}' -f $lastUpdatedText))
        [void]$events.Add(('CPU: {0:N1}%  RAM: {1:N1}%  Disk: {2:N1}%' -f $cpuCurrent, $ramCurrent, $diskCurrent))

        $diskText = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $diskCard -Name 'ValueText' -Default 'Unknown') -Default 'Unknown'
        $canStartMoreServers = Get-UGSMAnalyticsPropertyValue -Object $machineMetrics -Name 'CanStartMoreServers' -Default $null
        if ($null -eq $canStartMoreServers) {
            $canStartMoreServers = ($capacityState -ne 'Critical')
        }
        else {
            $canStartMoreServers = [bool]$canStartMoreServers
        }

        $selectedInstanceData = $null
        if ($selectedInstance) {
            $selectedPorts = Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Ports' -Default $null
            $selectedPortsText = 'Ports not assigned'
            if ($selectedPorts) {
                $selectedPortsList = @($selectedPorts.PSObject.Properties | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Value })
                if ($selectedPortsList.Count -gt 0) {
                    $selectedPortsText = ($selectedPortsList -join '  ')
                }
            }

            $selectedMods = @(Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Mods' -Default @())
            $selectedMap = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Map' -Default '') -Default ''
            $selectedInstallPath = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'InstallPath' -Default '') -Default ''
            $selectedGameName = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedGame -Name 'Name' -Default $selectedGameId) -Default $selectedGameId

            $selectedInstanceData = [pscustomobject]@{
                Id          = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Id' -Default '') -Default ''
                Name        = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Name' -Default '') -Default ''
                GameId      = $selectedGameId
                GameName    = $selectedGameName
                Status      = ConvertTo-UGSMAnalyticsText -Value (Get-UGSMAnalyticsPropertyValue -Object $selectedInstance -Name 'Status' -Default '') -Default ''
                Map         = if ([string]::IsNullOrWhiteSpace($selectedMap)) { 'Not set' } else { $selectedMap }
                InstallPath = if ([string]::IsNullOrWhiteSpace($selectedInstallPath)) { 'Not configured' } else { $selectedInstallPath }
                PortsText   = $selectedPortsText
                ModsText    = if ((Get-UGSMAnalyticsSafeCount -Value $selectedMods) -gt 0) { ($selectedMods -join ', ') } else { 'No mods loaded' }
                ArtPath     = [string]$selectedArtPath
            }
        }

        $result = [pscustomobject]@{
            Summary          = [pscustomobject]@{
                TotalInstances      = $totalCount
                RunningCount        = $runningCount
                StartingCount       = $startingCount
                StoppedCount        = $stoppedCount
                CpuPercent          = [Math]::Round($cpuCurrent, 1)
                RamPercent          = [Math]::Round($ramCurrent, 1)
                DiskPercent         = [Math]::Round($diskCurrent, 1)
                CapacityState       = $capacityState
                CapacityMessage     = $capacityMessage
                CanStartMoreServers = [bool]$canStartMoreServers
                InstallDiskText     = $diskText
                LastUpdated         = $lastUpdatedValue
            }
            CpuSeries        = @($cpuSeries)
            RamSeries        = @($ramSeries)
            DiskSeries       = @($diskSeries)
            Instances        = @($monitoredInstances)
            SelectedInstance = $selectedInstanceData
            Alerts           = @($alerts)
            Events           = @($events)
            MachineSnapshot  = [pscustomobject]@{
                Cpu    = $cpuSnapshot
                Memory = $memorySnapshot
                Disk   = $diskCard
            }
        }

        $analyticsStopwatch.Stop()
        $durationMs = [int]$analyticsStopwatch.ElapsedMilliseconds
        $instanceCount = if ($result -and (Test-UGSMAnalyticsHasProperty -Object $result -Name 'Instances')) { @($result.Instances).Count } else { 0 }
        $resultCapacityState = if ($result -and (Test-UGSMAnalyticsHasProperty -Object $result -Name 'Summary')) { [string]$result.Summary.CapacityState } else { 'Unknown' }

        if ($durationMs -ge 1000) {
            Write-UGSMAnalyticsLog -Level 'WARN' -Message ("Analytics page data build was slow. DurationMs=$durationMs; Instances=$instanceCount; Capacity=$resultCapacityState")
        }
        elseif (Test-UGSMAnalyticsVerboseLogging) {
            Write-UGSMAnalyticsLog -Level 'DEBUG' -Message ("Analytics page data built. DurationMs=$durationMs; Instances=$instanceCount; Capacity=$resultCapacityState")
        }

        return $result
    }
    catch {
        $analyticsStopwatch.Stop()
        Write-UGSMAnalyticsLog -Level 'ERROR' -Message ('Failed to build analytics page data. DurationMs={0}' -f [int]$analyticsStopwatch.ElapsedMilliseconds) -Exception $_.Exception

        return [pscustomobject]@{
            Summary          = [pscustomobject]@{
                TotalInstances      = 0
                RunningCount        = 0
                StartingCount       = 0
                StoppedCount        = 0
                CpuPercent          = 0
                RamPercent          = 0
                DiskPercent         = 0
                CapacityState       = 'Unknown'
                CapacityMessage     = 'Analytics data failed to load. Check the log for details.'
                CanStartMoreServers = $false
                InstallDiskText     = 'Unknown'
                LastUpdated         = $null
            }
            CpuSeries        = @(0)
            RamSeries        = @(0)
            DiskSeries       = @(0)
            Instances        = @()
            SelectedInstance = $null
            Alerts           = @('Analytics data failed to load.')
            Events           = @('Analytics error logged.')
            MachineSnapshot  = $null
        }
    }
}

