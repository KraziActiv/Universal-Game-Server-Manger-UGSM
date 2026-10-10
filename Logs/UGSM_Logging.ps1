# ============================================================
# UGSM Logging Helper
# App logs:
#   $env:LOCALAPPDATA\UGSM\Logs\UGSM
# Game logs:
#   $env:LOCALAPPDATA\UGSM\Logs\UGSM\Games\<GameId>
# Server logs:
#   $env:LOCALAPPDATA\UGSM\Logs\UGSM\Games\<GameId>\<ServerName>
#
# App logging creates one log file per UGSM run and keeps only
# the newest 5 normal app-run logs by default. Bootstrap/dev logs
# are cleaned separately and do not count against app-run logs.
# ============================================================

$script:UGSM_LogRoot = $null
$script:UGSM_LogFile = $null
$script:UGSM_LogInitialized = $false
$script:UGSM_LogRunId = $null
$script:UGSM_MaxAppRunLogs = 5

# Severity ranks. Higher = more important. Write-UGSMLog drops anything below the active threshold.
$script:UGSM_LogLevelMap = @{
    'TRACE' = 0
    'DEBUG' = 1
    'INFO'  = 2
    'WARN'  = 3
    'ERROR' = 4
    'FATAL' = 5
}

# Default thresholds per build mode. Dev logs everything, Test drops TRACE, Release only WARN+.
# Future: a Settings tab toggle will set $global:UGSM_LogLevelOverride at runtime.
$script:UGSM_LogModeThresholds = @{
    'Dev'     = 0
    'Test'    = 1
    'Release' = 3
}

function Get-UGSMLogLevelThreshold {
    [CmdletBinding()]
    param()

    $override = $null
    if (Get-Variable -Name 'UGSM_LogLevelOverride' -Scope Global -ErrorAction SilentlyContinue) {
        $override = $global:UGSM_LogLevelOverride
    }
    if ($null -ne $override -and -not ([string]::IsNullOrWhiteSpace([string]$override))) {
        if ($override -is [int]) { return [int]$override }
        $overrideName = ([string]$override).ToUpperInvariant()
        if ($script:UGSM_LogLevelMap.ContainsKey($overrideName)) {
            return [int]$script:UGSM_LogLevelMap[$overrideName]
        }
    }

    $mode = $null
    if (Get-Variable -Name 'UGSM_BuildMode' -Scope Script -ErrorAction SilentlyContinue) {
        $mode = [string]$script:UGSM_BuildMode
    }
    if ([string]::IsNullOrWhiteSpace($mode) -and (Get-Variable -Name 'UGSM_BuildMode' -Scope Global -ErrorAction SilentlyContinue)) {
        $mode = [string]$global:UGSM_BuildMode
    }

    if (-not [string]::IsNullOrWhiteSpace($mode) -and $script:UGSM_LogModeThresholds.ContainsKey($mode)) {
        return [int]$script:UGSM_LogModeThresholds[$mode]
    }

    # Unknown/unset mode behaves like Dev so loose .ps1 runs always log everything.
    return 0
}

function Get-UGSMResolvedBuildMode {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name 'UGSM_BuildMode' -Scope Script -ErrorAction SilentlyContinue) {
        $value = [string]$script:UGSM_BuildMode
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    if (Get-Variable -Name 'UGSM_BuildMode' -Scope Global -ErrorAction SilentlyContinue) {
        $value = [string]$global:UGSM_BuildMode
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return 'Dev'
}

function Get-UGSMDefaultLogRoot {
    [CmdletBinding()]
    param()

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
    }

    return (Join-Path $localAppData 'UGSM\Logs\UGSM')
}


function ConvertTo-UGSMDisplayPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    try {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $normalizedLocal = $localAppData.TrimEnd('\')
            if ($Path.StartsWith($normalizedLocal, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ('%LOCALAPPDATA%' + $Path.Substring($normalizedLocal.Length))
            }
        }

        $userProfile = $env:USERPROFILE
        if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
            $normalizedUser = $userProfile.TrimEnd('\')
            if ($Path.StartsWith($normalizedUser, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ('%USERPROFILE%' + $Path.Substring($normalizedUser.Length))
            }
        }
    }
    catch {
        # Display path cleanup must never stop logging.
    }

    return $Path
}

function New-UGSMSafePathName {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Fallback = 'Unknown'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = $Fallback
    }

    return ($Name -replace '[\\/:*?"<>|]', '_')
}


function Get-UGSMDefaultLogsBaseRoot {
    [CmdletBinding()]
    param()

    $appLogRoot = Get-UGSMDefaultLogRoot
    $baseRoot = Split-Path -Parent $appLogRoot
    if ([string]::IsNullOrWhiteSpace($baseRoot)) {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
        }
        $baseRoot = Join-Path $localAppData 'UGSM\Logs'
    }

    if (-not (Test-Path -LiteralPath $baseRoot -PathType Container)) {
        New-Item -Path $baseRoot -ItemType Directory -Force | Out-Null
    }

    return $baseRoot
}

function New-UGSMServerLogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameId,
        [Parameter(Mandatory)][string]$ServerName,
        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = Get-UGSMDefaultLogsBaseRoot
    }

    $safeGameId = New-UGSMSafePathName -Name $GameId -Fallback 'Game'
    $safeServerName = New-UGSMSafePathName -Name $ServerName -Fallback 'Server'
    $targetPath = Join-Path (Join-Path $RootPath $safeGameId) $safeServerName

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
    }

    return $targetPath
}

function Get-UGSMLogRunId {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($global:UGSM_RunId)) {
        return [string]$global:UGSM_RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($script:UGSM_LogRunId)) {
        return [string]$script:UGSM_LogRunId
    }

    $script:UGSM_LogRunId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $global:UGSM_RunId = $script:UGSM_LogRunId
    return $script:UGSM_LogRunId
}

function New-UGSMLogDirectory {
    [CmdletBinding()]
    param(
        [string]$GameId,
        [string]$ServerName,
        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = Get-UGSMDefaultLogRoot
    }

    $targetPath = $RootPath

    if (-not [string]::IsNullOrWhiteSpace($GameId)) {
        $safeGameId = New-UGSMSafePathName -Name $GameId -Fallback 'Game'
        $targetPath = Join-Path (Join-Path $targetPath 'Games') $safeGameId
    }

    if (-not [string]::IsNullOrWhiteSpace($ServerName)) {
        $safeServerName = New-UGSMSafePathName -Name $ServerName -Fallback 'Server'
        $targetPath = Join-Path $targetPath $safeServerName
    }

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
    }

    return $targetPath
}

function Remove-UGSMOldRunLogFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogFolder,

        [string]$Pattern = '*.log',

        [int]$Keep = 5,

        [string[]]$ExcludeNames = @(),

        [string]$NameRegex
    )

    try {
        if ($Keep -lt 1) { $Keep = 1 }
        if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) { return }

        $excludeSet = @{}
        foreach ($excludeName in @($ExcludeNames)) {
            if (-not [string]::IsNullOrWhiteSpace($excludeName)) {
                $excludeSet[$excludeName.ToLowerInvariant()] = $true
            }
        }

        # Important: -Filter uses filesystem wildcards, not regex. Patterns like
        # UGSM_[0-9]*.log are unreliable here because [] can be treated literally
        # by the provider. So use a broad wildcard, then apply regex filtering in
        # PowerShell. This is what keeps app-run logs from piling up.
        $candidatePattern = $Pattern
        if ([string]::IsNullOrWhiteSpace($candidatePattern)) { $candidatePattern = '*.log' }

        $files = @(Get-ChildItem -LiteralPath $LogFolder -Filter $candidatePattern -File -ErrorAction SilentlyContinue |
            Where-Object {
                if ($excludeSet.ContainsKey($_.Name.ToLowerInvariant())) { return $false }
                if (-not [string]::IsNullOrWhiteSpace($NameRegex)) {
                    return ($_.Name -match $NameRegex)
                }
                return $true
            } |
            Sort-Object LastWriteTimeUtc -Descending)

        if ($files.Count -le $Keep) { return }

        $files | Select-Object -Skip $Keep | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            }
            catch {
                # Log cleanup should never stop UGSM startup.
            }
        }
    }
    catch {
        # Log cleanup should never stop UGSM startup.
    }
}

function Invoke-UGSMLogRetentionCleanup {
    [CmdletBinding()]
    param(
        [string]$LogFolder,
        [string]$LogName = 'UGSM',
        [int]$KeepRunLogs = 5,
        [int]$KeepBootstrapLogs = 1
    )

    try {
        if ([string]::IsNullOrWhiteSpace($LogFolder)) { return }
        if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) { return }

        $safeLogName = New-UGSMSafePathName -Name $LogName -Fallback 'UGSM'
        if ($KeepRunLogs -lt 1) { $KeepRunLogs = 1 }
        if ($KeepBootstrapLogs -lt 0) { $KeepBootstrapLogs = 0 }

        # Normal app-run logs only, e.g. UGSM_20260520_144507_060.log.
        # This intentionally excludes UGSM_Bootstrap_*.log and any game/server logs.
        $escapedName = [regex]::Escape($safeLogName)
        $runRegex = '^' + $escapedName + '_\d{8}_\d{6}_\d{3}\.log$'
        Remove-UGSMOldRunLogFiles -LogFolder $LogFolder -Pattern ($safeLogName + '_*.log') -Keep $KeepRunLogs -NameRegex $runRegex

        if ($KeepBootstrapLogs -gt 0) {
            $bootstrapRegex = '^' + $escapedName + '_Bootstrap_\d{8}_\d{6}_\d{3}\.log$'
            Remove-UGSMOldRunLogFiles -LogFolder $LogFolder -Pattern ($safeLogName + '_Bootstrap_*.log') -Keep $KeepBootstrapLogs -NameRegex $bootstrapRegex
        }
    }
    catch {
        # Log retention must never stop UGSM.
    }
}

function Initialize-UGSMLogging {
    [CmdletBinding()]
    param(
        [string]$RootPath,
        [string]$LogName = 'UGSM',
        [int]$KeepRunLogs = 5,
        [switch]$Reset
    )

    if ($script:UGSM_LogInitialized -and -not $Reset) {
        return $script:UGSM_LogFile
    }

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = Get-UGSMDefaultLogRoot
    }

    if ($KeepRunLogs -lt 1) {
        $KeepRunLogs = 1
    }

    $logDirectory = New-UGSMLogDirectory -RootPath $RootPath
    $safeLogName = New-UGSMSafePathName -Name $LogName -Fallback 'UGSM'
    $runId = Get-UGSMLogRunId
    $logFile = Join-Path $logDirectory ("{0}_{1}.log" -f $safeLogName, $runId)

    $script:UGSM_LogRoot = $logDirectory
    $script:UGSM_LogFile = $logFile
    $script:UGSM_LogInitialized = $true
    $script:UGSM_LogRunId = $runId
    $script:UGSM_MaxAppRunLogs = $KeepRunLogs

    $global:UGSM_LogRoot = $logDirectory
    $global:UGSM_LogFile = $logFile
    $global:UGSM_LogRunId = $runId

    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        New-Item -Path $logFile -ItemType File -Force | Out-Null
    }

    # Keep only the last few normal app-run logs. Bootstrap/dev logs are cleaned separately.
    Invoke-UGSMLogRetentionCleanup -LogFolder $logDirectory -LogName $safeLogName -KeepRunLogs $KeepRunLogs -KeepBootstrapLogs 1

    $displayLogFile = ConvertTo-UGSMDisplayPath -Path $logFile
    $resolvedMode = Get-UGSMResolvedBuildMode
    $resolvedThreshold = Get-UGSMLogLevelThreshold
    $thresholdName = 'TRACE'
    foreach ($entry in $script:UGSM_LogLevelMap.GetEnumerator()) {
        if ([int]$entry.Value -eq [int]$resolvedThreshold) { $thresholdName = [string]$entry.Key; break }
    }
    Write-UGSMLog -Level 'INFO' -Category 'Logging' -Message "Logging initialized: $displayLogFile"
    Write-UGSMLog -Level 'INFO' -Category 'Logging' -Message "RunId: $runId; keeping newest $KeepRunLogs normal app run logs. Bootstrap/dev logs are separate."
    Write-UGSMLog -Level 'INFO' -Category 'Logging' -Message "Build mode: $resolvedMode; minimum log level: $thresholdName."
    return $logFile
}

function Get-UGSMLogFile {
    [CmdletBinding()]
    param()

    if (-not $script:UGSM_LogInitialized) {
        [void](Initialize-UGSMLogging)
    }

    return $script:UGSM_LogFile
}

function Write-UGSMLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [string]$Category = 'General',

        [System.Exception]$Exception,

        [object]$Data
    )

    try {
        $levelKey = $Level.ToUpperInvariant()
        $levelRank = if ($script:UGSM_LogLevelMap.ContainsKey($levelKey)) { [int]$script:UGSM_LogLevelMap[$levelKey] } else { 2 }
        if ($levelRank -lt (Get-UGSMLogLevelThreshold)) { return }

        if (-not $script:UGSM_LogInitialized -or [string]::IsNullOrWhiteSpace($script:UGSM_LogFile)) {
            [void](Initialize-UGSMLogging)
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = '[{0}] [{1}] [{2}] {3}' -f $timestamp, $Level.ToUpperInvariant(), $Category, $Message

        Add-Content -LiteralPath $script:UGSM_LogFile -Value $line -Encoding UTF8

        if ($Exception) {
            Add-Content -LiteralPath $script:UGSM_LogFile -Value ('    Exception: {0}' -f $Exception.Message) -Encoding UTF8
            if ($Exception.StackTrace) {
                Add-Content -LiteralPath $script:UGSM_LogFile -Value ('    StackTrace: {0}' -f $Exception.StackTrace) -Encoding UTF8
            }
        }

        if ($null -ne $Data) {
            try {
                $json = $Data | ConvertTo-Json -Depth 8 -Compress
                Add-Content -LiteralPath $script:UGSM_LogFile -Value ('    Data: {0}' -f $json) -Encoding UTF8
            }
            catch {
                Add-Content -LiteralPath $script:UGSM_LogFile -Value ('    Data: {0}' -f [string]$Data) -Encoding UTF8
            }
        }
    }
    catch {
        # Logging must never crash UGSM.
        try {
            Write-Host "UGSM logging failed: $($_.Exception.Message)"
        }
        catch {
        }
    }
}

function Invoke-UGSMTimedBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$Category = 'Performance'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMLog -Level 'DEBUG' -Category $Category -Message "Starting: $Name"

    try {
        return & $ScriptBlock
    }
    catch {
        Write-UGSMLog -Level 'ERROR' -Category $Category -Message "Failed: $Name after $($stopwatch.ElapsedMilliseconds) ms" -Exception $_.Exception
        throw
    }
    finally {
        $stopwatch.Stop()
        Write-UGSMLog -Level 'DEBUG' -Category $Category -Message "Finished: $Name ($($stopwatch.ElapsedMilliseconds) ms)"
    }
}

function Register-UGSMUnhandledExceptionLogging {
    [CmdletBinding()]
    param()

    try {
        [AppDomain]::CurrentDomain.add_UnhandledException({
                param($sender, $eventArgs)
                $exception = $eventArgs.ExceptionObject -as [System.Exception]
                if ($exception) {
                    Write-UGSMLog -Level 'FATAL' -Category 'UnhandledException' -Message 'Unhandled AppDomain exception.' -Exception $exception
                }
                else {
                    Write-UGSMLog -Level 'FATAL' -Category 'UnhandledException' -Message "Unhandled AppDomain exception: $($eventArgs.ExceptionObject)"
                }
            })
    }
    catch {
        Write-UGSMLog -Level 'WARN' -Category 'Logging' -Message 'Could not register AppDomain exception logger.' -Exception $_.Exception
    }

    try {
        if ('System.Windows.Forms.Application' -as [type]) {
            [System.Windows.Forms.Application]::add_ThreadException({
                    param($sender, $eventArgs)
                    Write-UGSMLog -Level 'ERROR' -Category 'UIThreadException' -Message 'Unhandled WinForms thread exception.' -Exception $eventArgs.Exception
                })
        }
    }
    catch {
        Write-UGSMLog -Level 'WARN' -Category 'Logging' -Message 'Could not register WinForms thread exception logger.' -Exception $_.Exception
    }
}
