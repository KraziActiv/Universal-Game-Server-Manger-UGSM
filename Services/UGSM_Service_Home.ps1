# Home Service

function Write-UGSMHomeLog {
    [CmdletBinding()]
    param(
        [string]$Level = 'INFO',
        [string]$Message,
        [System.Exception]$Exception
    )

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            if ($Exception) {
                Write-UGSMLog -Level $Level -Category 'Home' -Message $Message -Exception $Exception
            }
            else {
                Write-UGSMLog -Level $Level -Category 'Home' -Message $Message
            }
        }
    }
    catch { }
}


function Get-UGSMHomeSafeCount {
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
        return 1
    }
    catch {
        return 0
    }
}

$script:UGSM_HomePageDataCache = $null
$script:UGSM_HomePageDataCacheLoadedAt = [datetime]::MinValue
$script:UGSM_HomePageDataCacheTtlSeconds = 5

function Clear-UGSMHomePageDataCache {
    [CmdletBinding()]
    param()

    
function Get-UGSMHomeSafeCount {
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
        return 1
    }
    catch {
        return 0
    }
}

$script:UGSM_HomePageDataCache = $null
    $script:UGSM_HomePageDataCacheLoadedAt = [datetime]::MinValue
    Write-UGSMHomeLog -Level 'DEBUG' -Message 'Home page data cache cleared.'
}

function Get-UGSMHomePageData {
    [CmdletBinding()]
    param(
        [object]$AppState,
        [switch]$ForceRefresh
    )

    $startedAt = [datetime]::UtcNow
    $now = $startedAt
    if (-not $ForceRefresh -and $script:UGSM_HomePageDataCache -and $script:UGSM_HomePageDataCacheLoadedAt -ne [datetime]::MinValue) {
        $cacheAgeSeconds = ($now - $script:UGSM_HomePageDataCacheLoadedAt).TotalSeconds
        if ($cacheAgeSeconds -ge 0 -and $cacheAgeSeconds -lt $script:UGSM_HomePageDataCacheTtlSeconds) {
            return $script:UGSM_HomePageDataCache
        }
    }

    $settings = $null
    if (Get-Command Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings
        }
        catch {
            Write-UGSMHomeLog -Level 'WARN' -Message 'Failed to load global settings for Home page data.' -Exception $_.Exception
            $settings = $null
        }
    }

    $diskCard = $null
    if (Get-Command Get-UGSMDiskCardData -ErrorAction SilentlyContinue) {
        try {
            $diskCard = Get-UGSMDiskCardData
        }
        catch {
            Write-UGSMHomeLog -Level 'WARN' -Message 'Failed to load disk card data for Home page data.' -Exception $_.Exception
            $diskCard = $null
        }
    }

    $allInstances = @()

    if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
        try {
            $allInstances = @(Get-UGSMInstances)
        }
        catch {
            Write-UGSMHomeLog -Level 'WARN' -Message 'Failed to load instances for Home page data.' -Exception $_.Exception
            $allInstances = @()
        }
    }

    $runningStates = @('Running', 'Starting')
    $runningInstances = @($allInstances | Where-Object { $runningStates -contains [string]$_.Status })

    $runningCards = @(foreach ($instance in $runningInstances) {
        $game = $null
        if (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue) {
            try {
                $game = Get-UGSMGameById -Id $instance.GameId
            }
            catch {
                Write-UGSMHomeLog -Level 'DEBUG' -Message ('Failed to resolve game metadata for Home card. GameId={0}' -f $instance.GameId) -Exception $_.Exception
                $game = $null
            }
        }

        $artPath = $null
        if ($game -and (Get-Command Get-UGSMGameHeaderArt -ErrorAction SilentlyContinue)) {
            try {
                $artPath = Get-UGSMGameHeaderArt -Game $game
            }
            catch {
                Write-UGSMHomeLog -Level 'DEBUG' -Message ('Failed to resolve game artwork for Home card. GameId={0}' -f $instance.GameId) -Exception $_.Exception
                $artPath = $null
            }
        }

        $ports = @()
        if ($instance.Ports) {
            foreach ($name in @('Game', 'Query', 'Rcon')) {
                if ($instance.Ports.PSObject.Properties[$name]) {
                    $ports += ('{0}:{1}' -f $name, $instance.Ports.$name)
                }
            }
        }

        [pscustomobject]@{
            Id             = [string]$instance.Id
            Name           = [string]$instance.Name
            GameId         = [string]$instance.GameId
            GameName       = if ($game) { [string]$game.Name } else { [string]$instance.GameId }
            Status         = [string]$instance.Status
            StatusText     = if ([string]$instance.Status -eq 'Starting') { 'Starting' } else { 'Running' }
            ArtworkPath    = $artPath
            Map            = [string]$instance.Map
            InstallPath    = [string]$instance.InstallPath
            PortsText      = if ($ports.Count -gt 0) { ($ports -join '  ') } else { 'Ports not assigned' }
            DetailText     = if (-not [string]::IsNullOrWhiteSpace($instance.Map)) { [string]$instance.Map } else { 'Map not set' }
            MetaText       = if (-not [string]::IsNullOrWhiteSpace($instance.InstallPath)) { [string]$instance.InstallPath } else { 'Install path not set' }
        }
    })

    $machineMetrics = if (Get-Command Get-UGSMLatestMachineMetrics -ErrorAction SilentlyContinue) {
        Get-UGSMLatestMachineMetrics -RefreshIfMissing
    }
    else {
        $null
    }

    if ($machineMetrics -and $machineMetrics.Cpu) {
        $cpuValue = ('{0:N1}%' -f $machineMetrics.CpuPercent)
        $cpuMeta = 'Total machine CPU load'
    }
    else {
        $cpuValue = 'N/A'
        $cpuMeta = 'CPU monitor unavailable'
    }

    if ($machineMetrics -and $machineMetrics.Memory) {
        $usedGb = [double]$machineMetrics.Memory.UsedGB
        $totalGb = [double]$machineMetrics.Memory.TotalGB
        $ramValue = ('{0:N1} / {1:N1} GB' -f $usedGb, $totalGb)
        $ramMeta = ('{0:N1}% used' -f [double]$machineMetrics.MemoryPercent)
    }
    else {
        $ramValue = 'N/A'
        $ramMeta = 'Memory monitor unavailable'
    }

    $installDiskText = 'Not configured'
    if ($diskCard -and $diskCard.ValueText) {
        $installDiskText = [string]$diskCard.ValueText
    }

    $profileStoreText = 'Not configured'
    if ($settings -and -not [string]::IsNullOrWhiteSpace($settings.ProfileBaseRoot)) {
        $profileStoreText = [string]$settings.ProfileBaseRoot
    }

    $warningItems = New-Object System.Collections.Generic.List[string]
    if ((Get-UGSMHomeSafeCount -Value $runningCards) -eq 0) {
        $warningItems.Add('No servers are currently running.') | Out-Null
    }

    foreach ($instance in @($allInstances | Where-Object { [string]$_.Status -eq 'Starting' })) {
        $warningItems.Add(("{0} is still starting." -f $instance.Name)) | Out-Null
    }

    if ($diskCard -and $diskCard.Health -and [string]$diskCard.Health -ne 'Good') {
        $warningItems.Add(("Install disk health: {0}" -f $diskCard.Health)) | Out-Null
    }

    if ($warningItems.Count -eq 0) {
        $warningItems.Add('No active warnings.') | Out-Null
    }

    $recentActivity = New-Object System.Collections.Generic.List[string]
    if ((Get-UGSMHomeSafeCount -Value $runningCards) -gt 0) {
        foreach ($card in ($runningCards | Select-Object -First 3)) {
            $recentActivity.Add(("{0} is {1}" -f $card.Name, $card.StatusText.ToLowerInvariant())) | Out-Null
        }
    }
    else {
        $recentActivity.Add('No running servers detected') | Out-Null
        $recentActivity.Add('Open Instances to start a server') | Out-Null
    }

    if ($settings) {
        $recentActivity.Add('Settings loaded') | Out-Null
    }

    $result = [pscustomobject]@{
        Cards = @(
            [pscustomobject]@{ Title = 'CPU'; Value = $cpuValue; Meta = $cpuMeta }
            [pscustomobject]@{ Title = 'RAM'; Value = $ramValue; Meta = $ramMeta }
            [pscustomobject]@{ Title = 'Install Disk'; Value = $installDiskText; Meta = 'SteamCMD / binaries' }
            [pscustomobject]@{ Title = 'Profile Store'; Value = $profileStoreText; Meta = 'Profiles location' }
        )
        RunningInstances = @($runningCards)
        HomeSummary = [pscustomobject]@{
            RunningCount  = @($runningCards | Where-Object { $_.Status -eq 'Running' }).Count
            StartingCount = @($runningCards | Where-Object { $_.Status -eq 'Starting' }).Count
            TotalCount    = (Get-UGSMHomeSafeCount -Value $allInstances)
        }
        StorageSummary = [pscustomobject]@{
            SteamCmdPath    = if ($settings) { [string]$settings.SteamCmdPath } else { '' }
            ProfileBaseRoot = if ($settings) { [string]$settings.ProfileBaseRoot } else { '' }
            BackupRoot      = if ($settings) { [string]$settings.BackupRoot } else { '' }
        }
        RecentActivity = @($recentActivity)
        WarningItems   = @($warningItems)
    }

    $script:UGSM_HomePageDataCache = $result
    $script:UGSM_HomePageDataCacheLoadedAt = $now

    $durationMs = [int](([datetime]::UtcNow - $startedAt).TotalMilliseconds)
    if ($durationMs -ge 750) {
        Write-UGSMHomeLog -Level 'WARN' -Message ('Home page data build was slow. DurationMs={0}; Instances={1}; Running={2}' -f $durationMs, (Get-UGSMHomeSafeCount -Value $allInstances), (Get-UGSMHomeSafeCount -Value $runningCards))
    }
    elseif ($ForceRefresh) {
        Write-UGSMHomeLog -Level 'DEBUG' -Message ('Home page data built. DurationMs={0}; Instances={1}; Running={2}' -f $durationMs, (Get-UGSMHomeSafeCount -Value $allInstances), (Get-UGSMHomeSafeCount -Value $runningCards))
    }

    return $result
}
