function Write-UGSMTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$LogName = 'UGSM_InstanceSelectionTrace.log'
    )

    # Compatibility wrapper only. Old instance trace calls are intentionally quiet
    # unless verbose tracing is explicitly enabled.
    $traceEnabled = $false
    try {
        if ([string]$env:UGSM_ENABLE_TRACE -eq '1') {
            $traceEnabled = $true
        }
        elseif ((Get-Variable -Name 'UGSM_EnableVerboseUILogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseUILogging) {
            $traceEnabled = $true
        }
    }
    catch {
        $traceEnabled = $false
    }

    if (-not $traceEnabled) {
        return
    }

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            Write-UGSMLog -Level 'DEBUG' -Category $Component -Message $Message
        }
        elseif (Get-Command Write-UGSMLogEntry -ErrorAction SilentlyContinue) {
            Write-UGSMLogEntry -Category $Component -Level 'Debug' -Message $Message
        }
    }
    catch {
    }
}

function Format-UGSMTraceInstance {
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

# Instances Service


function ConvertTo-UGSMInstancesSafeLogText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    $text = [string]$Value

    try {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($local)) {
            $escapedLocal = [regex]::Escape($local.TrimEnd('\'))
            $text = [regex]::Replace($text, $escapedLocal, '%LOCALAPPDATA%', 'IgnoreCase')
        }

        $profile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($profile)) {
            $escapedProfile = [regex]::Escape($profile.TrimEnd('\'))
            $text = [regex]::Replace($text, $escapedProfile, '%USERPROFILE%', 'IgnoreCase')
        }

        if (Get-Command Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            $settings = Get-UGSMGlobalSettings
            if ($settings) {
                foreach ($propName in @('SteamCmdPath','SteamPath','SteamRoot')) {
                    if ($settings.PSObject.Properties[$propName]) {
                        $steamRoot = [string]$settings.$propName
                        if (-not [string]::IsNullOrWhiteSpace($steamRoot)) {
                            $escapedSteam = [regex]::Escape($steamRoot.TrimEnd('\'))
                            $text = [regex]::Replace($text, $escapedSteam, '%UGSM_STEAM%', 'IgnoreCase')
                        }
                    }
                }

                foreach ($propName in @('ProfilesPath','ProfilePath','ProfilesRoot','ProfileRoot','ServerProfilesPath','ServerProfilesRoot')) {
                    if ($settings.PSObject.Properties[$propName]) {
                        $profileRoot = [string]$settings.$propName
                        if (-not [string]::IsNullOrWhiteSpace($profileRoot)) {
                            $escapedRoot = [regex]::Escape($profileRoot.TrimEnd('\'))
                            $text = [regex]::Replace($text, $escapedRoot, '%UGSM_PROFILES%', 'IgnoreCase')
                        }
                    }
                }
            }
        }

        # Generic fallback for the normal UGSM layout: <root>\Steam and <root>\Profiles.
        $text = [regex]::Replace($text, '(?i)([A-Z]:\\[^;\r\n]*?)\\Steam(?=\\|$)', '%UGSM_STEAM%')
        $text = [regex]::Replace($text, '(?i)([A-Z]:\\[^;\r\n]*?)\\Profiles(?=\\|$)', '%UGSM_PROFILES%')

        # Keep instance JSON paths useful without exposing the Windows user folder.
        $text = [regex]::Replace($text, '(?i)%LOCALAPPDATA%\\UGSM\\Instances', '%UGSM_INSTANCES%')

        # Secret redaction is intentionally broad for instance-service logs.
        $text = [regex]::Replace($text, '(?i)(https://discord(?:app)?\.com/api/webhooks/)[^\s''"`<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(\b(password|passwd|pwd|token|gslt|secret|apikey|api_key|login_token|webhook)\b\s*[:=]\s*)[^;\s,}]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+\s+\S+', '$1<redacted> <redacted>')
    }
    catch {
        # Redaction must never break instance actions.
    }

    return $text
}

function ConvertTo-UGSMInstancesSafeException {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Exception]$Exception
    )

    if (-not $Exception) { return $null }

    try {
        $safeMessage = ConvertTo-UGSMInstancesSafeLogText -Value $Exception.Message
        return [System.Exception]::new($safeMessage)
    }
    catch {
        return $Exception
    }
}

function Write-UGSMInstancesLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    try {
        $safeMessage = ConvertTo-UGSMInstancesSafeLogText -Value $Message
        $safeException = ConvertTo-UGSMInstancesSafeException -Exception $Exception

        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            if ($safeException) {
                Write-UGSMLog -Level $Level -Category 'Instances' -Message $safeMessage -Exception $safeException
            }
            else {
                Write-UGSMLog -Level $Level -Category 'Instances' -Message $safeMessage
            }
        }
        elseif (Get-Command Write-UGSMLogEntry -ErrorAction SilentlyContinue) {
            $entryLevel = if ($Level -eq 'WARN') { 'Warn' } elseif ($Level -eq 'ERROR') { 'Error' } elseif ($Level -eq 'FATAL') { 'Error' } else { $Level.Substring(0,1).ToUpperInvariant() + $Level.Substring(1).ToLowerInvariant() }
            if ($safeException) {
                Write-UGSMLogEntry -Category 'Instances' -Level $entryLevel -Message ($safeMessage + ' ' + [string]$safeException.Message)
            }
            else {
                Write-UGSMLogEntry -Category 'Instances' -Level $entryLevel -Message $safeMessage
            }
        }
    }
    catch {
    }
}

if (-not (Get-Variable -Scope Script -Name UGSM_InstanceCache -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstanceCache = @()
}
if (-not (Get-Variable -Scope Script -Name UGSM_InstanceCacheLastRefreshUtc -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstanceCacheLastRefreshUtc = [DateTime]::MinValue
}
if (-not (Get-Variable -Scope Script -Name UGSM_InstanceCacheTtlSeconds -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstanceCacheTtlSeconds = 15
}

if (-not (Get-Variable -Scope Script -Name UGSM_InstancesPageDataCache -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstancesPageDataCache = $null
}
if (-not (Get-Variable -Scope Script -Name UGSM_InstancesPageDataCacheLastRefreshUtc -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstancesPageDataCacheLastRefreshUtc = [DateTime]::MinValue
}
if (-not (Get-Variable -Scope Script -Name UGSM_InstancesPageDataCacheTtlSeconds -ErrorAction SilentlyContinue)) {
    $script:UGSM_InstancesPageDataCacheTtlSeconds = 10
}

function Clear-UGSMInstancesCache {
    $script:UGSM_InstanceCache = @()
    $script:UGSM_InstanceCacheLastRefreshUtc = [DateTime]::MinValue
    $script:UGSM_InstancesPageDataCache = $null
    $script:UGSM_InstancesPageDataCacheLastRefreshUtc = [DateTime]::MinValue
}

function Test-UGSMInstancesCacheIsValid {
    if ($null -eq $script:UGSM_InstanceCache) {
        return $false
    }

    $ttlSeconds = 5
    try {
        $ttlSeconds = [int]$script:UGSM_InstanceCacheTtlSeconds
    }
    catch {
        $ttlSeconds = 5
    }

    if ($ttlSeconds -lt 0) {
        $ttlSeconds = 0
    }

    if ($script:UGSM_InstanceCacheLastRefreshUtc -eq [DateTime]::MinValue) {
        return $false
    }

    $ageSeconds = ([DateTime]::UtcNow - $script:UGSM_InstanceCacheLastRefreshUtc).TotalSeconds
    return ($ageSeconds -lt $ttlSeconds)
}


function Get-UGSMInstancesRoot {
    $baseRoot = ''

    if (Get-Command Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        try {
            $baseRoot = [string](Get-UGSMAppDataRoot)
        }
        catch {
            $baseRoot = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($baseRoot)) {
        $baseRoot = Join-Path $env:LOCALAPPDATA 'UGSM'
    }

    $root = Join-Path $baseRoot 'Instances'

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $null = New-Item -Path $root -ItemType Directory -Force
    }

    return $root
}

function Get-UGSMInstancesGameRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    $root = Get-UGSMInstancesRoot
    $gameRoot = Join-Path $root $GameId

    if (-not (Test-Path -LiteralPath $gameRoot -PathType Container)) {
        New-Item -Path $gameRoot -ItemType Directory -Force | Out-Null
    }

    return $gameRoot
}

function Get-UGSMInstanceFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$GameId
    )

    $safeId = [regex]::Replace($Id, '[^\w\-]', '_')
    $gameRoot = Get-UGSMInstancesGameRoot -GameId $GameId
    return (Join-Path $gameRoot ($safeId + '.json'))
}


function ConvertTo-UGSMInstanceFolderName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Fallback = 'Instance'
    )

    $value = [string]$Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [string]$Fallback
    }

    $value = $value.Trim()
    $value = [regex]::Replace($value, '[\\/:*?"<>|]+', '_')
    $value = [regex]::Replace($value, '\s+', ' ')
    $value = $value.Trim('. ')

    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [string]$Fallback
    }

    return $value
}

function Get-UGSMDayZFolderInstanceFilePathFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$Create
    )

    $gameRoot = Get-UGSMInstancesGameRoot -GameId 'DayZ'

    $name = ''
    if ($Instance.PSObject.Properties.Name -contains 'Name') {
        $name = [string]$Instance.Name
    }

    $id = ''
    if ($Instance.PSObject.Properties.Name -contains 'Id') {
        $id = [string]$Instance.Id
    }

    $folderName = ConvertTo-UGSMInstanceFolderName -Name $name -Fallback $id
    $folder = Join-Path $gameRoot $folderName

    if ($Create -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        foreach ($child in @('cache', 'backups', 'generated', 'logs')) {
            $childPath = Join-Path $folder $child
            if (-not (Test-Path -LiteralPath $childPath -PathType Container)) {
                New-Item -ItemType Directory -Path $childPath -Force | Out-Null
            }
        }
    }

    return (Join-Path $folder 'instance.json')
}

function ConvertTo-UGSMInstanceId {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $id = $Name.ToLowerInvariant()
    $id = [regex]::Replace($id, '[^a-z0-9]+', '-')
    $id = $id.Trim('-')
    return $id
}

function Get-UGSMInstanceDefinitionFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,
        [switch]$Create
    )

    $gameId = ''
    if ($Instance.PSObject.Properties.Name -contains 'GameId') {
        $gameId = [string]$Instance.GameId
    }

    if ($gameId -eq 'DayZ') {
        if (Get-Command -Name Get-UGSMDayZInstanceDefinitionPath -ErrorAction SilentlyContinue) {
            try {
                $servicePath = [string](Get-UGSMDayZInstanceDefinitionPath -Instance $Instance -Create:$Create)
                if (-not [string]::IsNullOrWhiteSpace($servicePath)) {
                    return $servicePath
                }
            }
            catch {
                Write-UGSMTrace -Component 'Service.Instances' -Message ('DayZ instance path resolver failed; using built-in folder fallback. ' + [string]$_.Exception.Message)
            }
        }

        return (Get-UGSMDayZFolderInstanceFilePathFallback -Instance $Instance -Create:$Create)
    }

    return (Get-UGSMInstanceFilePath -Id ([string]$Instance.Id) -GameId ([string]$Instance.GameId))
}

function Test-UGSMInstanceJsonIsSupersededByFolderInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,
        [Parameter(Mandatory)]
        [object]$InstanceObject
    )

    $gameId = ''
    if ($InstanceObject.PSObject.Properties.Name -contains 'GameId') { $gameId = [string]$InstanceObject.GameId }
    if ($gameId -ne 'DayZ') { return $false }
    if (-not (Get-Command -Name Get-UGSMDayZInstanceDefinitionPath -ErrorAction SilentlyContinue)) { return $false }

    try {
        $expectedPath = [string](Get-UGSMDayZInstanceDefinitionPath -Instance $InstanceObject -Create:$false)
        if ([string]::IsNullOrWhiteSpace($expectedPath)) { return $false }
        $filePath = [System.IO.Path]::GetFullPath($File.FullName)
        $expectedFullPath = [System.IO.Path]::GetFullPath($expectedPath)
        if ($filePath -ieq $expectedFullPath) { return $false }
        if (Test-Path -LiteralPath $expectedFullPath -PathType Leaf) { return $true }
    } catch { }
    return $false
}

function Get-UGSMPreservedInstanceProperties {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Instance
    )

    $reserved = @(
        'Id','Name','GameId','InstallPath','ProfilePath','Map','Ports','Mods','Status','Pid','ModStates',
        'Discord','DiscordWebhookUrl','DiscordNotifyStart','DiscordNotifyStop','DiscordVisible',
        'PrivateDiscordWebhookUrl','InstanceDiscordWebhookUrl','WebhookUrl','PrivateWebhookUrl',
        'DiscordWebhookSecretId','PrivateDiscordWebhookSecretId','InstanceDiscordWebhookSecretId','HasPrivateDiscordWebhook'
    )

    $extra = [ordered]@{}
    if ($Instance) {
        foreach ($prop in $Instance.PSObject.Properties) {
            if ($reserved -contains [string]$prop.Name) {
                continue
            }
            $extra[[string]$prop.Name] = $prop.Value
        }
    }

    return $extra
}

function Get-UGSMDefaultInstanceProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $settings = $null
    if (Get-Command Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
        }
        catch {
            $settings = $null
        }
    }

    $baseRoot = ''
    if ($settings -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) {
        $baseRoot = [string]$settings.ProfileBaseRoot
    }

    if ([string]::IsNullOrWhiteSpace($baseRoot)) {
        if (Get-Command Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
            $baseRoot = Join-Path ([string](Get-UGSMAppDataRoot)) 'Profiles'
        }
        else {
            $baseRoot = Join-Path $env:LOCALAPPDATA 'UGSM\Profiles'
        }
    }

    return (Join-Path (Join-Path $baseRoot $GameId) $Name)
}

function Repair-UGSMInstanceRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        return $Instance
    }

    $status = [string]$Instance.Status
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'Stopped'
        $Instance.Status = 'Stopped'
    }

    $status = [string]$Instance.Status
    $processId = $null

    if ($Instance.PSObject.Properties.Name -contains 'Pid' -and
        $null -ne $Instance.Pid -and
        -not [string]::IsNullOrWhiteSpace([string]$Instance.Pid)) {
        try {
            $processId = [int]$Instance.Pid
        }
        catch {
            $processId = $null
        }
    }

    $isRunning = $false
    if ($null -ne $processId) {
        if (Get-Command Test-UGSMProcessIsRunning -ErrorAction SilentlyContinue) {
            $isRunning = [bool](Test-UGSMProcessIsRunning -ProcessId $processId)
        }
        else {
            try {
                $proc = Get-Process -Id $processId -ErrorAction Stop
                $isRunning = ($null -ne $proc -and -not $proc.HasExited)
            }
            catch {
                $isRunning = $false
            }
        }
    }

    if ($status -eq 'Running' -and -not $isRunning) {
        $Instance.Status = 'Stopped'
        $Instance.Pid = $null
    }
    elseif ($status -eq 'Starting' -and -not $isRunning) {
        $Instance.Status = 'Stopped'
        $Instance.Pid = $null
    }
    elseif ($status -eq 'Stopped') {
        $Instance.Pid = $null
    }

    return $Instance
}

function Get-UGSMInstances {
    [CmdletBinding()]
    param(
        [string]$GameId,
        [switch]$ForceRefresh
    )

    $refreshWatch = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not $ForceRefresh -and (Test-UGSMInstancesCacheIsValid)) {
        $cachedItems = @($script:UGSM_InstanceCache)
        if (-not [string]::IsNullOrWhiteSpace($GameId)) {
            return @($cachedItems | Where-Object { [string]$_.GameId -eq [string]$GameId })
        }
        return $cachedItems
    }

    $root = Get-UGSMInstancesRoot

    $files = @()

    if (Test-Path -LiteralPath $root -PathType Container) {
        $files += @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)
        $files += @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue)
    }

    $files = @($files | Sort-Object FullName -Unique)
    Write-Verbose ("UGSM Instance Files Found: " + $files.Count)

    $items = foreach ($file in $files) {
        try {
            if ($file.Name -match '\.bak(\.|$)') { continue }
            if ($file.FullName -match '(?i)[\\/]((cache)|(backups)|(generated)|(logs))[\\/]') { continue }

            $obj = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json

            if (Test-UGSMInstanceJsonIsSupersededByFolderInstance -File $file -InstanceObject $obj) {
                continue
            }

            $profilePath = if ($obj.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$obj.ProfilePath)) {
                [string]$obj.ProfilePath
            }
            else {
                Get-UGSMDefaultInstanceProfilePath -GameId ([string]$obj.GameId) -Name ([string]$obj.Name)
            }

            $discord = Merge-UGSMInstanceDiscordData -InstanceObject $obj
            $extraProperties = Get-UGSMPreservedInstanceProperties -Instance $obj

            $instance = [pscustomobject]@{
                Id                 = $obj.Id
                Name               = $obj.Name
                GameId             = $obj.GameId
                InstallPath        = $obj.InstallPath
                ProfilePath        = $profilePath
                Map                = $obj.Map
                Ports              = $obj.Ports
                ModStates          = @($obj.ModStates)
                Mods               = @($obj.Mods)
                Status             = if ([string]::IsNullOrWhiteSpace($obj.Status)) { 'Stopped' } else { [string]$obj.Status }
                Pid                = if ($null -ne $obj.Pid) { $obj.Pid } else { $null }
                Discord            = $discord
                DiscordWebhookUrl  = [string]$discord.WebhookUrl
                DiscordNotifyStart = [bool]$discord.NotifyOnStart
                DiscordNotifyStop  = [bool]$discord.NotifyOnStop
                DiscordVisible     = [bool]$discord.ShowInDashboard
            }

            foreach ($entry in $extraProperties.GetEnumerator()) {
                Add-Member -InputObject $instance -MemberType NoteProperty -Name ([string]$entry.Key) -Value $entry.Value -Force
            }

            $instance = Repair-UGSMInstanceRuntimeState -Instance $instance

            $instance
        }
        catch {
            Write-UGSMInstancesLog -Level 'WARN' -Message ("Failed to load instance file: " + $file.FullName) -Exception $_.Exception
        }
    }

    $result = @($items)
    $script:UGSM_InstanceCache = $result
    $script:UGSM_InstanceCacheLastRefreshUtc = [DateTime]::UtcNow

    $refreshWatch.Stop()

    $resultCount = @($result).Count
    $fileCount = @($files).Count
    $refreshMs = [int]$refreshWatch.ElapsedMilliseconds
    $cacheSignature = ('{0}|{1}|{2}' -f $resultCount, $fileCount, [string]$GameId)

    $shouldLogRefresh = $false
    $lastSignatureVar = Get-Variable -Name 'UGSM_InstanceCacheLastLogSignature' -Scope Script -ErrorAction SilentlyContinue
    if (-not $lastSignatureVar -or [string]$lastSignatureVar.Value -ne $cacheSignature) {
        $shouldLogRefresh = $true
        $script:UGSM_InstanceCacheLastLogSignature = $cacheSignature
    }
    if ($ForceRefresh.IsPresent -or $refreshMs -ge 1000) {
        $shouldLogRefresh = $true
    }
    if ((Get-Variable -Name 'UGSM_EnableVerboseInstanceLogging' -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseInstanceLogging) {
        $shouldLogRefresh = $true
    }

    if ($shouldLogRefresh) {
        $level = if ($refreshMs -ge 1000) { 'WARN' } else { 'DEBUG' }
        Write-UGSMInstancesLog -Level $level -Message ("Instances cache refreshed. Count={0}; Files={1}; DurationMs={2}; GameId={3}; ForceRefresh={4}" -f $resultCount, $fileCount, $refreshMs, [string]$GameId, [bool]$ForceRefresh.IsPresent)
    }

    if (-not [string]::IsNullOrWhiteSpace($GameId)) {
        return @($result | Where-Object { [string]$_.GameId -eq [string]$GameId })
    }

    return $result
}

function Invoke-UGSMInstanceDiscordEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [ValidateSet('Start','Stop')]
        [string]$Event
    )

    if (-not (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue)) {
        Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification unavailable: Send-UGSMInstanceDiscordNotification not found.")
        return
    }

    try {
        Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification begin for Id=" + [string]$Instance.Id + "; Name=" + [string]$Instance.Name)
        $result = Send-UGSMInstanceDiscordNotification -Instance $Instance -Event $Event

        if ($null -eq $result) {
            Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification returned no result for Id=" + [string]$Instance.Id)
            return
        }

        if ($result.PSObject.Properties['Success'] -and [bool]$result.Success) {
            Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification sent for Id=" + [string]$Instance.Id)
            return
        }

        if ($result.PSObject.Properties['Skipped'] -and [bool]$result.Skipped) {
            Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification skipped for Id=" + [string]$Instance.Id + "; " + [string]$result.Reason)
            return
        }

        $errorText = ''
        if ($result.PSObject.Properties['Error']) {
            $errorText = [string]$result.Error
        }

        Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification failed for Id=" + [string]$Instance.Id + "; " + $errorText)

        Write-UGSMInstancesLog -Level 'WARN' -Message ("Discord {0} notification failed for instance '{1}': {2}" -f [string]$Event, [string]$Instance.Name, [string]$errorText)
    }
    catch {
        Write-UGSMTrace -Component 'Service.Instances' -Message ("Discord $Event notification threw for Id=" + [string]$Instance.Id + "; " + [string]$_.Exception.Message)

        Write-UGSMInstancesLog -Level 'ERROR' -Message ("Discord {0} notification exception for instance '{1}'" -f [string]$Event, [string]$Instance.Name) -Exception $_.Exception
    }
}

function New-UGSMInstance {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$GameId,

        [string]$InstallPath = '',
        [string]$Map = '',
        [hashtable]$Ports = @{},
        [object[]]$ModStates = @(),
        [string[]]$Mods = @()
    )

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Create instance requested. GameId={0}; Name={1}" -f [string]$GameId, [string]$Name)

    $id = ConvertTo-UGSMInstanceId -Name $Name

    $probeInstance = [pscustomobject]@{
        Id     = $id
        Name   = $Name
        GameId = $GameId
    }
    $path = Get-UGSMInstanceDefinitionFilePath -Instance $probeInstance -Create

    if (Test-Path -LiteralPath $path) {
        throw "An instance with id '$id' already exists."
    }

    $discord = [pscustomobject](Get-UGSMDefaultInstanceDiscordData)

    $instance = [pscustomobject]@{
        Id                 = $id
        Name               = $Name
        GameId             = $GameId
        InstallPath        = $InstallPath
        ProfilePath        = Get-UGSMDefaultInstanceProfilePath -GameId $GameId -Name $Name
        Map                = $Map
        Ports              = $Ports
        Mods               = @($Mods)
        ModStates          = @($ModStates)
        Status             = 'Stopped'
        Pid                = $null
        Discord            = $discord
        DiscordWebhookUrl  = [string]$discord.WebhookUrl
        DiscordNotifyStart = [bool]$discord.NotifyOnStart
        DiscordNotifyStop  = [bool]$discord.NotifyOnStop
        DiscordVisible     = [bool]$discord.ShowInDashboard
    }

    $instance = Save-UGSMInstance -Instance $instance
    Clear-UGSMInstancesCache

    if ((Get-Command Initialize-UGSMGameProfile -ErrorAction SilentlyContinue) -and (Get-Command Test-UGSMGameHandlerAvailable -ErrorAction SilentlyContinue) -and (Test-UGSMGameHandlerAvailable -GameId $GameId -HandlerName 'InitializeProfile')) {
        $profileResult = Initialize-UGSMGameProfile -Instance $instance
        if ($profileResult -and $profileResult.PSObject.Properties['ProfileRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$profileResult.ProfileRoot)) {
            $instance.ProfilePath = [string]$profileResult.ProfileRoot
            $instance = Save-UGSMInstance -Instance $instance
            Clear-UGSMInstancesCache
        }
    }

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Create instance completed. GameId={0}; InstanceId={1}; Name={2}" -f [string]$instance.GameId, [string]$instance.Id, [string]$instance.Name)

    return $instance
}

function Get-UGSMInstance {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name
    )

    $instances = @(Get-UGSMInstances)

    switch ($PSCmdlet.ParameterSetName) {
        'ById' {
            return ($instances | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
        }

        'ByName' {
            return ($instances | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
        }
    }
}

function Start-UGSMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Start instance requested. InstanceId={0}" -f [string]$Id)

    $instance = Get-UGSMInstance -Id $Id
    if (-not $instance) {
        throw "Instance '$Id' was not found."
    }

    $gameId = [string]$instance.GameId
    if ([string]::IsNullOrWhiteSpace($gameId)) {
        throw "Instance '$Id' does not have a valid GameId."
    }

    if (-not (Get-Command -Name Test-UGSMGameHandlerAvailable -ErrorAction SilentlyContinue)) {
        throw "Test-UGSMGameHandlerAvailable is not available."
    }

    if (-not (Get-Command -Name Invoke-UGSMGameHandler -ErrorAction SilentlyContinue)) {
        throw "Invoke-UGSMGameHandler is not available."
    }

    if (-not (Test-UGSMGameHandlerAvailable -GameId $gameId -HandlerName 'Start')) {
        throw "No Start handler is registered for game '$gameId'."
    }

    $instance.Status = 'Starting'
    $instance.Pid = $null
    $instance = Save-UGSMInstance -Instance $instance

    try {
        $result = Invoke-UGSMGameHandler -GameId $gameId -HandlerName 'Start' -Arguments @{
            Instance = $instance
        }

        if ($null -eq $result) {
            throw "Game start handler for '$gameId' returned no result."
        }

        $startedInstance = $instance
        $startedPid = $null
        $startedStatus = 'Running'

        if ($result -is [System.Management.Automation.PSCustomObject] -or $result -is [hashtable]) {
            if ($result.PSObject.Properties.Name -contains 'Instance' -and $null -ne $result.Instance) {
                $startedInstance = $result.Instance
            }

            if ($result.PSObject.Properties.Name -contains 'Pid' -and $null -ne $result.Pid) {
                $startedPid = [int]$result.Pid
            }

            if ($result.PSObject.Properties.Name -contains 'Status' -and -not [string]::IsNullOrWhiteSpace([string]$result.Status)) {
                $startedStatus = [string]$result.Status
            }
        }

        if ($null -eq $startedInstance) {
            $startedInstance = Get-UGSMInstance -Id $Id
            if (-not $startedInstance) {
                $startedInstance = $instance
            }
        }

        if ($null -eq $startedPid -and $null -ne $startedInstance.Pid) {
            $startedPid = [int]$startedInstance.Pid
        }

        $startedInstance.Status = $startedStatus
        $startedInstance.Pid = $startedPid
        $startedInstance = Save-UGSMInstance -Instance $startedInstance

        Invoke-UGSMInstanceDiscordEvent -Instance $startedInstance -Event 'Start'

        Write-UGSMInstancesLog -Level 'INFO' -Message ("Start instance completed. InstanceId={0}; GameId={1}; Status={2}; Pid={3}" -f [string]$startedInstance.Id, [string]$startedInstance.GameId, [string]$startedInstance.Status, [string]$startedInstance.Pid)
        
        # Trigger a dashboard update after a server starts
        try {
            if (Get-Command -Name Publish-UGSMDiscordDashboard -ErrorAction SilentlyContinue) {
                Write-UGSMTrace -Component 'Service.Instances' -Message ("Triggering Discord dashboard update for Start event: " + [string]$startedInstance.Name)
                Publish-UGSMDiscordDashboard -ForceUpdate
            }
        }
        catch {
            Write-UGSMTrace -Component 'Service.Instances' -Message ("Failed to trigger Discord dashboard update for Start event: " + [string]$_.Exception.Message)
        }

        return $startedInstance
    }
    catch {
        $instance = Get-UGSMInstance -Id $Id
        if ($instance) {
            $instance.Status = 'Stopped'
            $instance.Pid = $null
            Save-UGSMInstance -Instance $instance | Out-Null
        }

        Write-UGSMInstancesLog -Level 'ERROR' -Message ("Start instance failed. InstanceId={0}" -f [string]$Id) -Exception $_.Exception

        throw
    }
}

function Stop-UGSMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Stop instance requested. InstanceId={0}" -f [string]$Id)

    $instance = Get-UGSMInstance -Id $Id
    if (-not $instance) {
        throw "Instance '$Id' was not found."
    }

    $gameId = [string]$instance.GameId
    if ([string]::IsNullOrWhiteSpace($gameId)) {
        throw "Instance '$Id' does not have a valid GameId."
    }

    if (-not (Get-Command -Name Test-UGSMGameHandlerAvailable -ErrorAction SilentlyContinue)) {
        throw "Test-UGSMGameHandlerAvailable is not available."
    }

    if (-not (Get-Command -Name Invoke-UGSMGameHandler -ErrorAction SilentlyContinue)) {
        throw "Invoke-UGSMGameHandler is not available."
    }

    $instance.Status = 'Stopping'
    $instance = Save-UGSMInstance -Instance $instance

    try {
        if (Test-UGSMGameHandlerAvailable -GameId $gameId -HandlerName 'Stop') {
            $result = Invoke-UGSMGameHandler -GameId $gameId -HandlerName 'Stop' -Arguments @{
                Instance = $instance
            }

            $stoppedInstance = $instance

            if ($null -ne $result -and ($result -is [System.Management.Automation.PSCustomObject] -or $result -is [hashtable])) {
                if ($result.PSObject.Properties.Name -contains 'Instance' -and $null -ne $result.Instance) {
                    $stoppedInstance = $result.Instance
                }
            }

            if ($null -eq $stoppedInstance) {
                $stoppedInstance = Get-UGSMInstance -Id $Id
                if (-not $stoppedInstance) {
                    $stoppedInstance = $instance
                }
            }

            $stoppedInstance.Status = 'Stopped'
            $stoppedInstance.Pid = $null
            $stoppedInstance = Save-UGSMInstance -Instance $stoppedInstance

            Invoke-UGSMInstanceDiscordEvent -Instance $stoppedInstance -Event 'Stop'

            Write-UGSMInstancesLog -Level 'INFO' -Message ("Stop instance completed. InstanceId={0}; GameId={1}; Status={2}" -f [string]$stoppedInstance.Id, [string]$stoppedInstance.GameId, [string]$stoppedInstance.Status)
            
            # Trigger a dashboard update after a server stops
            try {
                if (Get-Command -Name Publish-UGSMDiscordDashboard -ErrorAction SilentlyContinue) {
                    Write-UGSMTrace -Component 'Service.Instances' -Message ("Triggering Discord dashboard update for Stop event: " + [string]$stoppedInstance.Name)
                    Publish-UGSMDiscordDashboard -ForceUpdate
                }
            }
            catch {
                Write-UGSMTrace -Component 'Service.Instances' -Message ("Failed to trigger Discord dashboard update for Stop event: " + [string]$_.Exception.Message)
            }

            return $stoppedInstance
        }

        if ($null -ne $instance.Pid -and (Get-Command -Name Stop-UGSMProcessTree -ErrorAction SilentlyContinue)) {
            $null = Stop-UGSMProcessTree -ProcessId ([int]$instance.Pid) -TimeoutSeconds 20
        }

        $instance.Status = 'Stopped'
        $instance.Pid = $null
        $instance = Save-UGSMInstance -Instance $instance

        Invoke-UGSMInstanceDiscordEvent -Instance $instance -Event 'Stop'

        Write-UGSMInstancesLog -Level 'INFO' -Message ("Stop instance completed. InstanceId={0}; GameId={1}; Status={2}" -f [string]$instance.Id, [string]$instance.GameId, [string]$instance.Status)
        
        # Trigger a dashboard update after a server stops
        try {
            if (Get-Command -Name Publish-UGSMDiscordDashboard -ErrorAction SilentlyContinue) {
                Write-UGSMTrace -Component 'Service.Instances' -Message ("Triggering Discord dashboard update for Stop event: " + [string]$instance.Name)
                Publish-UGSMDiscordDashboard -ForceUpdate
            }
        }
        catch {
            Write-UGSMTrace -Component 'Service.Instances' -Message ("Failed to trigger Discord dashboard update for Stop event: " + [string]$_.Exception.Message)
        }

        return $instance
    }
    catch {
        $instance = Get-UGSMInstance -Id $Id
        if ($instance) {
            $instance.Status = 'Running'
            $instance = Save-UGSMInstance -Instance $instance
        }

        Write-UGSMInstancesLog -Level 'ERROR' -Message ("Stop instance failed. InstanceId={0}" -f [string]$Id) -Exception $_.Exception

        throw
    }
}

function Save-UGSMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    Write-UGSMInstancesLog -Level 'DEBUG' -Message ('Save instance requested. ' + (Format-UGSMTraceInstance $Instance))

    if (-not $Instance.Id) {
        throw 'Cannot save instance because Id is missing.'
    }

    $resolvedProfilePath = if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        [string]$Instance.ProfilePath
    }
    else {
        Get-UGSMDefaultInstanceProfilePath -GameId ([string]$Instance.GameId) -Name ([string]$Instance.Name)
    }

    $discord = Merge-UGSMInstanceDiscordData -InstanceObject $Instance
    $hasPrivateDiscordWebhook = $false
    $discordWebhookSecretId = ''
    $explicitNoPrivateDiscordWebhook = $false
    if ($Instance.PSObject.Properties['HasPrivateDiscordWebhook']) {
        $explicitNoPrivateDiscordWebhook = -not [bool]$Instance.HasPrivateDiscordWebhook
    }

    # Privacy guard: instance JSON must never store raw Discord webhook URLs.
    # When a private instance webhook reaches the generic instance save path,
    # move it into the Discord secret store if that service is loaded; otherwise
    # drop it from the saved JSON rather than leaking it.
    if (-not [string]::IsNullOrWhiteSpace([string]$discord.WebhookUrl)) {
        if (Get-Command -Name Save-UGSMDiscordInstanceWebhookSecret -ErrorAction SilentlyContinue) {
            try {
                $secretResult = Save-UGSMDiscordInstanceWebhookSecret -Instance $Instance -WebhookUrl ([string]$discord.WebhookUrl)
                $hasPrivateDiscordWebhook = [bool]$secretResult.HasPrivateWebhook
                if ($hasPrivateDiscordWebhook -and $secretResult.PSObject.Properties['SecretId']) {
                    $discordWebhookSecretId = [string]$secretResult.SecretId
                }
            }
            catch { }
        }
        $discord.WebhookUrl = ''
    }
    elseif ((-not $explicitNoPrivateDiscordWebhook) -and (Get-Command -Name Get-UGSMDiscordInstanceWebhookSecret -ErrorAction SilentlyContinue)) {
        try {
            $existingPrivateWebhook = Get-UGSMDiscordInstanceWebhookSecret -Instance $Instance
            if (-not [string]::IsNullOrWhiteSpace([string]$existingPrivateWebhook)) {
                $hasPrivateDiscordWebhook = $true
                if (Get-Command -Name Get-UGSMDiscordInstanceSecretId -ErrorAction SilentlyContinue) {
                    $discordWebhookSecretId = [string](Get-UGSMDiscordInstanceSecretId -Instance $Instance)
                }
            }
        }
        catch { }
    }

    $extraProperties = Get-UGSMPreservedInstanceProperties -Instance $Instance

    $instanceToSave = [pscustomobject]@{
        Id                 = [string]$Instance.Id
        Name               = [string]$Instance.Name
        GameId             = [string]$Instance.GameId
        InstallPath        = [string]$Instance.InstallPath
        ProfilePath        = $resolvedProfilePath
        Map                = [string]$Instance.Map
        Ports              = $Instance.Ports
        Mods               = @($Instance.Mods)
        Status             = [string]$Instance.Status
        Pid                = $Instance.Pid
        ModStates          = @($Instance.ModStates)
        Discord            = [pscustomobject]@{
            WebhookUrl      = [string]$discord.WebhookUrl
            NotifyOnStart   = [bool]$discord.NotifyOnStart
            NotifyOnStop    = [bool]$discord.NotifyOnStop
            ShowInDashboard = [bool]$discord.ShowInDashboard
        }
        DiscordWebhookUrl  = ''
        DiscordNotifyStart = [bool]$discord.NotifyOnStart
        DiscordNotifyStop  = [bool]$discord.NotifyOnStop
        DiscordVisible     = [bool]$discord.ShowInDashboard
        DiscordWebhookSecretId = $discordWebhookSecretId
        HasPrivateDiscordWebhook = [bool]$hasPrivateDiscordWebhook
    }

    foreach ($entry in $extraProperties.GetEnumerator()) {
        Add-Member -InputObject $instanceToSave -MemberType NoteProperty -Name ([string]$entry.Key) -Value $entry.Value -Force
    }

    $filePath = Get-UGSMInstanceDefinitionFilePath -Instance $instanceToSave -Create

    $parent = Split-Path -Parent $filePath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $instanceToSave |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $filePath -Encoding UTF8

    $safeFilePath = ConvertTo-UGSMInstancesSafeLogText -Value $filePath
    Write-UGSMInstancesLog -Level 'DEBUG' -Message ("Save instance completed. InstanceId={0}; GameId={1}; File={2}" -f [string]$instanceToSave.Id, [string]$instanceToSave.GameId, [string]$safeFilePath)

    # DayZ uses folder-style storage: Instances\DayZ\<InstanceName>\instance.json.
    # If a legacy flat file was created by an older save path, move it aside so it
    # does not show as a duplicate instance.
    if ([string]$instanceToSave.GameId -eq 'DayZ') {
        try {
            $legacyFilePath = Get-UGSMInstanceFilePath -Id ([string]$instanceToSave.Id) -GameId ([string]$instanceToSave.GameId)
            if (-not [string]::IsNullOrWhiteSpace($legacyFilePath) -and
                -not [string]::IsNullOrWhiteSpace($filePath) -and
                ($legacyFilePath.ToLowerInvariant() -ne $filePath.ToLowerInvariant()) -and
                (Test-Path -LiteralPath $legacyFilePath -PathType Leaf)) {
                Move-Item -LiteralPath $legacyFilePath -Destination ($legacyFilePath + '.migrated.bak') -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }

    Clear-UGSMInstancesCache

    return $instanceToSave
}

function Remove-UGSMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Remove instance requested. InstanceId={0}" -f [string]$Id)

    $instance = Get-UGSMInstance -Id $Id
    if (-not $instance) {
        Write-UGSMInstancesLog -Level 'WARN' -Message ("Remove instance skipped because it was not found. InstanceId={0}" -f [string]$Id)

        return [pscustomobject]@{
            Id                    = $Id
            Name                  = $null
            Removed               = $false
            InstanceFileRemoved   = $false
            InstanceFolderRemoved = $false
            ProfileRemoved        = $false
            PortsReleased         = $false
            FilePath              = $null
            InstanceFolderPath    = $null
            ProfilePath           = $null
            Reason                = 'Instance not found.'
        }
    }

    # Important: use the same resolver that Save-UGSMInstance uses.
    # DayZ instances now live at Instances\DayZ\<InstanceName>\instance.json,
    # while older/non-DayZ instances still use Instances\<GameId>\<id>.json.
    $filePath = Get-UGSMInstanceDefinitionFilePath -Instance $instance -Create:$false
    $legacyFilePath = Get-UGSMInstanceFilePath -Id ([string]$instance.Id) -GameId ([string]$instance.GameId)

    $instanceFolderPath = $null
    if (-not [string]::IsNullOrWhiteSpace($filePath)) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        if ($fileName -ieq 'instance.json') {
            $instanceFolderPath = Split-Path -Parent $filePath
        }
    }

    $profilePath = [string]$instance.ProfilePath

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = Get-UGSMDefaultInstanceProfilePath -GameId ([string]$instance.GameId) -Name ([string]$instance.Name)
    }

    if ([string]$instance.Status -ne 'Stopped' -and (Get-Command Stop-UGSMInstance -ErrorAction SilentlyContinue)) {
        try {
            $null = Stop-UGSMInstance -Id $instance.Id
        }
        catch {
        }
    }

    $profileRemoved = $false
    if (-not [string]::IsNullOrWhiteSpace($profilePath) -and (Test-Path -LiteralPath $profilePath -PathType Container)) {
        Remove-Item -LiteralPath $profilePath -Recurse -Force
        $profileRemoved = $true
    }

    $instanceFileRemoved = $false
    if (-not [string]::IsNullOrWhiteSpace($filePath) -and (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Remove-Item -LiteralPath $filePath -Force
        $instanceFileRemoved = $true
    }

    # Clean up a stale legacy flat file too if one exists, but do not use it as
    # the primary path for folder-based DayZ instances.
    if (-not [string]::IsNullOrWhiteSpace($legacyFilePath) -and
        $legacyFilePath -ine $filePath -and
        (Test-Path -LiteralPath $legacyFilePath -PathType Leaf)) {
        Remove-Item -LiteralPath $legacyFilePath -Force
    }

    $instanceFolderRemoved = $false
    if (-not [string]::IsNullOrWhiteSpace($instanceFolderPath) -and
        (Test-Path -LiteralPath $instanceFolderPath -PathType Container)) {

        # Only remove folder-style instance storage folders. This folder is under
        # AppData\Local\UGSM\Instances and contains cache/backups/generated/logs.
        Remove-Item -LiteralPath $instanceFolderPath -Recurse -Force
        $instanceFolderRemoved = $true
    }

    $portsReleased = $false
    if (Get-Command Remove-UGSMInstancePortAssignments -ErrorAction SilentlyContinue) {
        $portResult = Remove-UGSMInstancePortAssignments -InstanceId $instance.Id
        if ($portResult -and $portResult.PSObject.Properties['Removed']) {
            $portsReleased = [bool]$portResult.Removed
        }
    }

    Clear-UGSMInstancesCache

    Write-UGSMInstancesLog -Level 'INFO' -Message ("Remove instance completed. InstanceId={0}; GameId={1}; ProfileRemoved={2}; InstanceFileRemoved={3}; InstanceFolderRemoved={4}; PortsReleased={5}" -f [string]$instance.Id, [string]$instance.GameId, [bool]$profileRemoved, [bool]$instanceFileRemoved, [bool]$instanceFolderRemoved, [bool]$portsReleased)

    return [pscustomobject]@{
        Id                    = [string]$instance.Id
        Name                  = [string]$instance.Name
        Removed               = ($instanceFileRemoved -or $instanceFolderRemoved -or $profileRemoved -or $portsReleased)
        InstanceFileRemoved   = $instanceFileRemoved
        InstanceFolderRemoved = $instanceFolderRemoved
        ProfileRemoved        = $profileRemoved
        PortsReleased         = $portsReleased
        FilePath              = $filePath
        InstanceFolderPath    = $instanceFolderPath
        ProfilePath           = $profilePath
    }
}


function Test-UGSMInstancesPageDataCacheIsValid {
    if ($null -eq $script:UGSM_InstancesPageDataCache) {
        return $false
    }

    if ($script:UGSM_InstancesPageDataCacheLastRefreshUtc -eq [DateTime]::MinValue) {
        return $false
    }

    $ttlSeconds = 10
    try {
        $ttlSeconds = [int]$script:UGSM_InstancesPageDataCacheTtlSeconds
    }
    catch {
        $ttlSeconds = 10
    }

    if ($ttlSeconds -le 0) {
        return $false
    }

    $ageSeconds = ([DateTime]::UtcNow - $script:UGSM_InstancesPageDataCacheLastRefreshUtc).TotalSeconds
    return ($ageSeconds -lt $ttlSeconds)
}

function Get-UGSMInstancesPageData {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh -and (Test-UGSMInstancesPageDataCacheIsValid)) {
        return $script:UGSM_InstancesPageDataCache
    }

    $pageWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $instances = @(Get-UGSMInstances -ForceRefresh:$ForceRefresh)

    $runningCount = @($instances | Where-Object { $_.Status -eq 'Running' }).Count
    $startingCount = @($instances | Where-Object { $_.Status -eq 'Starting' }).Count
    $stoppedCount = @($instances | Where-Object { $_.Status -eq 'Stopped' }).Count

    $pageData = [pscustomobject]@{
        TotalCount    = $instances.Count
        RunningCount  = $runningCount
        StartingCount = $startingCount
        StoppedCount  = $stoppedCount
        Instances     = $instances
    }

    $script:UGSM_InstancesPageDataCache = $pageData
    $script:UGSM_InstancesPageDataCacheLastRefreshUtc = [DateTime]::UtcNow

    $pageWatch.Stop()
    Write-UGSMInstancesLog -Level 'DEBUG' -Message ("Instances page data rebuilt. Total={0}; Running={1}; Starting={2}; Stopped={3}; DurationMs={4}; ForceRefresh={5}" -f [int]$pageData.TotalCount, [int]$pageData.RunningCount, [int]$pageData.StartingCount, [int]$pageData.StoppedCount, [int]$pageWatch.ElapsedMilliseconds, [bool]$ForceRefresh.IsPresent)

    return $pageData
}
