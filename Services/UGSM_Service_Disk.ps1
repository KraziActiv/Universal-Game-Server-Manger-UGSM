# Module for Services


function Write-UGSMDiskLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'DEBUG',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'Disk' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'Disk' -Message $Message
        }
        return
    }

    if ($Level -in @('WARN','ERROR','FATAL')) {
        Write-Warning "[Disk] $Message"
    }
}

function Get-UGSMDiskAccentColor {
    [CmdletBinding()]
    param(
        [ValidateSet('Good','Warning','Danger')]
        [string]$Health = 'Good'
    )

    switch ($Health) {
        'Danger'  { if ($global:UGSM_ColorDanger)  { return $global:UGSM_ColorDanger  }; return [System.Drawing.ColorTranslator]::FromHtml('#EF4444') }
        'Warning' { if ($global:UGSM_ColorCaution) { return $global:UGSM_ColorCaution }; return [System.Drawing.ColorTranslator]::FromHtml('#F59E0B') }
        default   { if ($global:UGSM_ColorSuccess) { return $global:UGSM_ColorSuccess }; return [System.Drawing.ColorTranslator]::FromHtml('#22C55E') }
    }
}

function Get-UGSMDiskPathRootInfo {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [pscustomobject]@{
            IsAvailable = $false
            Root        = ''
            Drive       = ''
            Reason      = 'EmptyPath'
        }
    }

    try {
        $trimmed = ([string]$Path).Trim()
        $root = [System.IO.Path]::GetPathRoot($trimmed)

        if ([string]::IsNullOrWhiteSpace($root)) {
            return [pscustomobject]@{
                IsAvailable = $false
                Root        = ''
                Drive       = ''
                Reason      = 'NoRoot'
            }
        }

        $drive = ''
        if ($root -match '^([A-Za-z]):\\?$') {
            $drive = ('{0}:' -f $matches[1].ToUpperInvariant())
        }

        $rootToCheck = $root
        if ($drive) {
            $rootToCheck = ($drive + '\')
        }

        if (-not [System.IO.Directory]::Exists($rootToCheck)) {
            return [pscustomobject]@{
                IsAvailable = $false
                Root        = $root
                Drive       = $drive
                Reason      = 'MissingRoot'
            }
        }

        return [pscustomobject]@{
            IsAvailable = $true
            Root        = $root
            Drive       = $drive
            Reason      = 'OK'
        }
    }
    catch {
        return [pscustomobject]@{
            IsAvailable = $false
            Root        = ''
            Drive       = ''
            Reason      = 'InvalidPath'
        }
    }
}


function Get-UGSMDiskCardData {
    [CmdletBinding()]
    param(
        [psobject]$Settings
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($null -eq $Settings) {
        if (Get-Command Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            $Settings = Get-UGSMGlobalSettings -CreateIfMissing
        }
    }

    $inventory = @()
    try {
        $inventory = @(Get-UGSMDiskInventory)
    }
    catch {
        Write-UGSMDiskLog -Level 'ERROR' -Message 'Failed to build disk inventory for disk card data.' -Exception $_.Exception
        $inventory = @()
    }

    if ($inventory.Count -eq 0) {
        Write-UGSMDiskLog -Level 'WARN' -Message 'No local fixed disks were detected while building disk card data.'

        return [pscustomobject]@{
            IsAvailable        = $false
            ValueText          = 'No drives found'
            MetaText           = 'No local fixed disks were detected'
            AccentColor        = (Get-UGSMDiskAccentColor -Health 'Danger')
            ChartBars          = @(12, 18, 10, 14)
            ChartLabels        = @()
            Health             = 'Danger'
            PathMappings       = @()
            PrimaryDriveLetter = $null
            PrimarySource      = $null
            SummaryText        = 'No local fixed disks were detected.'
        }
    }

    $pathRequests = @(
        @{ Key = 'SteamCmdPath';    Label = 'Install';  Priority = 1; Path = if ($Settings) { [string]$Settings.SteamCmdPath } else { '' } },
        @{ Key = 'ProfileBaseRoot'; Label = 'Profiles'; Priority = 2; Path = if ($Settings) { [string]$Settings.ProfileBaseRoot } else { '' } },
        @{ Key = 'BackupRoot';      Label = 'Backups';  Priority = 3; Path = if ($Settings) { [string]$Settings.BackupRoot } else { '' } }
    )

    $pathMappings = @()
    foreach ($request in $pathRequests) {
        if ([string]::IsNullOrWhiteSpace($request.Path)) { continue }

        $rootInfo = Get-UGSMDiskPathRootInfo -Path ([string]$request.Path)
        if (-not $rootInfo.IsAvailable) {
            Write-UGSMDiskLog -Level 'DEBUG' -Message ('Skipping disk mapping because configured root is unavailable. Key={0}; Drive={1}; Reason={2}' -f $request.Key, $rootInfo.Drive, $rootInfo.Reason)
            continue
        }

        $disk = $null
        try {
            $disk = Get-UGSMDiskForPath -Path ([string]$request.Path) -Inventory $inventory
        }
        catch {
            Write-UGSMDiskLog -Level 'DEBUG' -Message ('Skipping disk mapping because path-to-disk resolution failed. Key={0}; Drive={1}' -f $request.Key, $rootInfo.Drive)
            continue
        }

        if ($null -eq $disk) { continue }
        $pathMappings += [pscustomobject]@{
            Key         = $request.Key
            Label       = $request.Label
            Priority    = [int]$request.Priority
            Path        = $request.Path
            DriveLetter = $disk.DriveLetter
            Disk        = $disk
        }
    }

    $installMapping = $pathMappings | Where-Object { $_.Key -eq 'SteamCmdPath' } | Select-Object -First 1
    $profileMapping = $pathMappings | Where-Object { $_.Key -eq 'ProfileBaseRoot' } | Select-Object -First 1
    $backupMapping = $pathMappings | Where-Object { $_.Key -eq 'BackupRoot' } | Select-Object -First 1

    $primaryMapping = $installMapping
    if ($null -eq $primaryMapping) { $primaryMapping = $profileMapping }

    $primaryDisk = $null
    $primarySource = 'Fallback'
    if ($primaryMapping) {
        $primaryDisk = $primaryMapping.Disk
        $primarySource = $primaryMapping.Label
    }
    else {
        $primaryDisk = $inventory | Sort-Object FreeBytes -Descending | Select-Object -First 1
    }

    $health = 'Good'
    $accentColor = Get-UGSMDiskAccentColor -Health 'Good'
    if ($primaryDisk.PercentFree -lt 15) {
        $health = 'Danger'
        $accentColor = Get-UGSMDiskAccentColor -Health 'Danger'
    }
    elseif ($primaryDisk.PercentFree -lt 25) {
        $health = 'Warning'
        $accentColor = Get-UGSMDiskAccentColor -Health 'Warning'
    }

    $primaryMeta = '{0} free on {1} ({2} free)' -f $primaryDisk.FreeText, $primaryDisk.DriveLetter, ([string]::Format('{0:N1}', $primaryDisk.PercentFree) + '%')
    if ($primarySource -eq 'Install') {
        $primaryMeta = '{0} • SteamCMD and server binaries' -f $primaryMeta
    }
    elseif ($primarySource -eq 'Profiles') {
        $primaryMeta = '{0} • Profile storage drive' -f $primaryMeta
    }
    else {
        $primaryMeta = '{0} • Best available local drive' -f $primaryMeta
    }

    $chartValues = New-Object System.Collections.Generic.List[object]
    foreach ($mapping in @($installMapping, $profileMapping, $backupMapping)) {
        if ($null -eq $mapping) { continue }
        [void]$chartValues.Add([pscustomobject]@{ Label = $mapping.Label; Value = [Math]::Max(4, [int][Math]::Round($mapping.Disk.PercentUsed)) })
    }
    foreach ($disk in ($inventory | Sort-Object DriveLetter)) {
        if (@($chartValues | Where-Object { $_.Label -eq $disk.DriveLetter }).Count -gt 0) { continue }
        [void]$chartValues.Add([pscustomobject]@{ Label = $disk.DriveLetter; Value = [Math]::Max(4, [int][Math]::Round($disk.PercentUsed)) })
    }
    $chartValues = @($chartValues | Select-Object -First 10)

    $summaryText = 'Install disk is driving dashboard capacity.'
    if ($null -eq $installMapping -and $profileMapping) {
        $summaryText = 'Profiles disk is being used until SteamCMD path is configured.'
    }
    elseif ($null -eq $installMapping -and $null -eq $profileMapping) {
        $summaryText = 'No storage paths configured yet. Using the best local drive as a fallback.'
    }

    $sw.Stop()
    if ($sw.ElapsedMilliseconds -ge 1000) {
        Write-UGSMDiskLog -Level 'WARN' -Message ("Disk card data build was slow. DurationMs={0}; InventoryCount={1}; PrimaryDrive={2}; Health={3}" -f $sw.ElapsedMilliseconds, $inventory.Count, $primaryDisk.DriveLetter, $health)
    }
    elseif ((Get-Variable -Name 'UGSM_EnableVerboseDiskLogging' -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseDiskLogging) {
        Write-UGSMDiskLog -Level 'DEBUG' -Message ("Disk card data built. DurationMs={0}; InventoryCount={1}; PrimaryDrive={2}; Health={3}" -f $sw.ElapsedMilliseconds, $inventory.Count, $primaryDisk.DriveLetter, $health)
    }

    return [pscustomobject]@{
        IsAvailable        = $true
        ValueText          = ($primaryDisk.FreeText + ' Free')
        MetaText           = $primaryMeta
        AccentColor        = $accentColor
        Health             = $health
        PrimaryDriveLetter = $primaryDisk.DriveLetter
        PrimarySource      = $primarySource
        PrimaryDisk        = $primaryDisk
        InstallDisk        = if ($installMapping) { $installMapping.Disk } else { $null }
        ProfileDisk        = if ($profileMapping) { $profileMapping.Disk } else { $null }
        BackupDisk         = if ($backupMapping) { $backupMapping.Disk } else { $null }
        PathMappings       = @($pathMappings)
        ChartBars          = @($chartValues | ForEach-Object { $_.Value })
        ChartLabels        = @($chartValues | ForEach-Object { $_.Label })
        SummaryText        = $summaryText
    }
}
