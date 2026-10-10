# Core Machine Helpers
# Consolidates machine-level raw metrics and disk inventory helpers.

$script:UGSMCpuCounter = $null
$script:UGSMCpuCounterReady = $false

function Initialize-UGSMCpuCounter {
    [CmdletBinding()]
    param()

    if ($script:UGSMCpuCounterReady) {
        return $true
    }

    try {
        $counter = New-Object System.Diagnostics.PerformanceCounter
        $counter.CategoryName = 'Processor'
        $counter.CounterName  = '% Processor Time'
        $counter.InstanceName = '_Total'

        # First read enumerates the Processor category (scales with logical core count)
        # and primes the counter so subsequent NextValue() calls return real samples.
        $null = $counter.NextValue()

        $script:UGSMCpuCounter = $counter
        $script:UGSMCpuCounterReady = $true
        return $true
    }
    catch {
        $script:UGSMCpuCounter = $null
        $script:UGSMCpuCounterReady = $false
        return $false
    }
}

function Get-UGSMCpuSnapshot {
    [CmdletBinding()]
    param()

    if (-not $script:UGSMCpuCounterReady -or -not $script:UGSMCpuCounter) {
        return [pscustomobject]@{
            Percent = 0
        }
    }

    try {
        $value = [double]$script:UGSMCpuCounter.NextValue()

        if ($value -lt 0) { $value = 0 }
        if ($value -gt 100) { $value = 100 }

        return [pscustomobject]@{
            Percent = [Math]::Round($value, 2)
        }
    }
    catch {
        return [pscustomobject]@{
            Percent = 0
        }
    }
}

function Get-UGSMMemorySnapshot {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem

        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $freeBytes  = [double]$os.FreePhysicalMemory * 1KB
        $usedBytes  = $totalBytes - $freeBytes

        $percent = 0
        if ($totalBytes -gt 0) {
            $percent = ($usedBytes / $totalBytes) * 100
        }

        return [pscustomobject]@{
            TotalBytes = [Math]::Round($totalBytes, 0)
            UsedBytes  = [Math]::Round($usedBytes, 0)
            FreeBytes  = [Math]::Round($freeBytes, 0)
            Percent    = [Math]::Round($percent, 2)
            TotalGB    = [Math]::Round($totalBytes / 1GB, 2)
            UsedGB     = [Math]::Round($usedBytes / 1GB, 2)
            FreeGB     = [Math]::Round($freeBytes / 1GB, 2)
        }
    }
    catch {
        return [pscustomobject]@{
            TotalBytes = 0
            UsedBytes  = 0
            FreeBytes  = 0
            Percent    = 0
            TotalGB    = 0
            UsedGB     = 0
            FreeGB     = 0
        }
    }
}

function Convert-UGSMBytesToReadable {
    [CmdletBinding()]
    param(
        [Nullable[double]]$Bytes,
        [int]$Decimals = 2
    )

    if ($null -eq $Bytes) {
        return '0 B'
    }

    $value = [double]$Bytes
    if ($value -lt 0) {
        $value = 0
    }

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $unitIndex = 0

    while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $value = $value / 1024
        $unitIndex++
    }

    return ([string]::Format("{0:N$Decimals} {1}", $value, $units[$unitIndex]))
}

function Resolve-UGSMDriveLetterFromPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $trimmedPath = $Path.Trim()

    try {
        $resolvedPath = $trimmedPath
        if (Test-Path -LiteralPath $trimmedPath) {
            $resolvedPath = (Resolve-Path -LiteralPath $trimmedPath -ErrorAction Stop).Path
        }

        $root = [System.IO.Path]::GetPathRoot($resolvedPath)
        if ([string]::IsNullOrWhiteSpace($root)) {
            return $null
        }

        return $root.TrimEnd('\\')
    }
    catch {
        $fallbackRoot = [System.IO.Path]::GetPathRoot($trimmedPath)
        if ([string]::IsNullOrWhiteSpace($fallbackRoot)) {
            return $null
        }

        return $fallbackRoot.TrimEnd('\\')
    }
}

function Get-UGSMDiskInventory {
    [CmdletBinding()]
    param()

    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 })

    $inventory = foreach ($disk in $disks) {
        $sizeBytes = [int64]$disk.Size
        $freeBytes = [int64]$disk.FreeSpace
        $usedBytes = [Math]::Max([int64]0, ([int64]$sizeBytes - [int64]$freeBytes))

        $percentFree = 0.0
        if ($sizeBytes -gt 0) {
            $percentFree = [Math]::Round((([double]$freeBytes / [double]$sizeBytes) * 100), 2)
        }

        $percentUsed = [Math]::Round((100 - $percentFree), 2)

        [pscustomobject]@{
            DriveLetter = [string]$disk.DeviceID
            RootPath    = ([string]$disk.DeviceID + '\\')
            VolumeName  = [string]$disk.VolumeName
            FileSystem  = [string]$disk.FileSystem
            TotalBytes  = [int64]$sizeBytes
            FreeBytes   = [int64]$freeBytes
            UsedBytes   = [int64]$usedBytes
            PercentFree = $percentFree
            PercentUsed = $percentUsed
            SizeText    = Convert-UGSMBytesToReadable -Bytes $sizeBytes
            FreeText    = Convert-UGSMBytesToReadable -Bytes $freeBytes
            UsedText    = Convert-UGSMBytesToReadable -Bytes $usedBytes
        }
    }

    return @($inventory | Sort-Object DriveLetter)
}

function Get-UGSMDiskForPath {
    [CmdletBinding()]
    param(
        [string]$Path,
        [object[]]$Inventory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $driveLetter = Resolve-UGSMDriveLetterFromPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($driveLetter)) {
        return $null
    }

    if ($null -eq $Inventory -or $Inventory.Count -eq 0) {
        $Inventory = Get-UGSMDiskInventory
    }

    return ($Inventory | Where-Object { $_.DriveLetter -eq $driveLetter } | Select-Object -First 1)
}

function Get-UGSMDiskCardData {
    [CmdletBinding()]
    param(
        [string]$PrimaryPath,
        [object[]]$Inventory
    )

    if ($null -eq $Inventory -or $Inventory.Count -eq 0) {
        $Inventory = Get-UGSMDiskInventory
    }

    $primaryDisk = $null
    if (-not [string]::IsNullOrWhiteSpace($PrimaryPath)) {
        $primaryDisk = Get-UGSMDiskForPath -Path $PrimaryPath -Inventory $Inventory
    }

    if (-not $primaryDisk -and $Inventory.Count -gt 0) {
        $primaryDisk = $Inventory | Sort-Object DriveLetter | Select-Object -First 1
    }

    return [pscustomobject]@{
        PrimaryDisk = $primaryDisk
        Inventory   = @($Inventory)
        Count       = @($Inventory).Count
    }
}
