# MisCreated Game
# Pre Template compitable.

function Test-UGSMGameMisCreatedVerboseLogging {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name 'UGSM_EnableVerboseMisCreatedLogging' -Scope Script -ErrorAction SilentlyContinue) {
        try { return [bool]$script:UGSM_EnableVerboseMisCreatedLogging } catch { }
    }

    $envValue = [string]$env:UGSM_VERBOSE_MISCREATED
    return ($envValue -in @('1', 'true', 'yes', 'on'))
}

function Write-UGSMGameMisCreatedLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception,

        [switch]$VerboseOnly
    )

    if ($VerboseOnly.IsPresent -and -not (Test-UGSMGameMisCreatedVerboseLogging)) { return }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'MisCreated' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'MisCreated' -Message $Message
        }
        return
    }

    if ($Exception) {
        Write-Host (('[{0}] [MisCreated] {1}: {2}' -f $Level, $Message, $Exception.Message))
    }
    else {
        Write-Host (('[{0}] [MisCreated] {1}' -f $Level, $Message))
    }
}

function Convert-UGSMGameMisCreatedSafeLaunchArguments {
    [CmdletBinding()]
    param([AllowNull()][string]$Arguments)

    if ([string]::IsNullOrWhiteSpace($Arguments)) { return '' }
    return ([string]$Arguments -replace '(?i)(\+http_password\s+")([^"]*)(")', '$1<redacted>$3' -replace '(?i)(\+http_password\s+)(\S+)', '$1<redacted>')
}

function Write-UGSMGameMisCreatedPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message $Message -VerboseOnly
}

function Get-UGSMGameMisCreatedPaths {
    [CmdletBinding()]
    param()

    $serverDirectoryName = 'Bin64_dedicated'
    $serverExecutableName = 'MisCreatedServer.exe'
    $serverExecutableRelativePath = Join-Path $serverDirectoryName $serverExecutableName

    return [pscustomobject]@{
        ServerDirectoryName         = $serverDirectoryName
        ServerExecutableName        = $serverExecutableName
        ServerExecutableRelativePath = $serverExecutableRelativePath
    }
}

function Get-UGSMGameMisCreatedMetadata {
    [CmdletBinding()]
    param()

    $paths = Get-UGSMGameMisCreatedPaths

    return [pscustomobject]@{
        Id                       = 'MisCreated'
        Name                     = 'MisCreated'
        Category                 = 'Survival'
        UseSteamArt              = $true
        RequiresSteamLogin       = $false
        SupportsMods             = $true
        SupportsWorkshop         = $true
        SupportsRcon             = $false
        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
        IsCustom                 = $false
        SortOrder                = 18

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 64090 }
            @{ Name = 'HttpPort'; Protocol = 'TCP'; PreferredStart = 64190 }
        )

        InstallProvider          = 'SteamCMD'
        SteamAppId               = 302200
        SteamStoreAppId          = 299740
        ServerExecutable         = $paths.ServerExecutableName
        ServerExecutableRelative = $paths.ServerExecutableRelativePath
        SupportsInstall          = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsRemove           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = '.'
        SaveRootRelative         = 'SaveGames'
        RequiredFiles            = @(
            $paths.ServerExecutableRelativePath
        )
        InstallMarkers           = @(
            $paths.ServerExecutableRelativePath
            $paths.ServerDirectoryName
        )
    }
}

function Get-UGSMGameMisCreatedInstallDefinition {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    if ([string]::IsNullOrWhiteSpace($InstallPath) -and $Instance) {
        if ($Instance.PSObject.Properties.Name -contains 'InstallPath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) {
            $InstallPath = [string]$Instance.InstallPath
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $settings = $null
        if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
        }

        $steamRoot = $null
        foreach ($propName in @('SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
            if ($settings -and $settings.PSObject.Properties.Name -contains $propName) {
                $value = [string]$settings.$propName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $steamRoot = $value
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($steamRoot)) {
            throw 'MisCreated install definition failed: InstallPath could not be resolved.'
        }

        $InstallPath = Join-Path $steamRoot 'servers\MisCreated'
    }

    $meta = Get-UGSMGameMisCreatedMetadata

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = Join-Path $InstallPath $meta.ServerExecutableRelative
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = $InstallPath
        SaveRootPath         = Join-Path $InstallPath $meta.SaveRootRelative
        LogRootPath          = Join-Path $InstallPath 'logs'
        HostingConfigPath    = Join-Path $InstallPath 'hosting.cfg'
        ModsRootPath         = Join-Path $InstallPath 'Mods'
    }
}

function Get-UGSMGameMisCreatedAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameMisCreatedProfileBaseRoot {
    [CmdletBinding()]
    param()

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    if ($settings -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) {
        return [string]$settings.ProfileBaseRoot
    }

    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'MisCreated' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameMisCreatedAppDataRoot) 'Profiles')
}

function Get-UGSMGameMisCreatedTemplateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameMisCreatedAppDataRoot) 'Templates\MisCreated')
}

function Get-UGSMGameMisCreatedProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameMisCreatedProfileBaseRoot) 'MisCreated') $ProfileName)
}

function Copy-UGSMGameMisCreatedDirectoryContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [switch]$ClearDestination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("Directory copy skipped because source does not exist. Source={0}" -f $Source) -VerboseOnly
        return
    }

    if ($ClearDestination -and (Test-Path -LiteralPath $Destination -PathType Container)) {
        Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $items = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Source.Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }

        $targetPath = Join-Path $Destination $relative

        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            continue
        }

        $parent = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

            Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
    }

    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("Directory content copied. Source={0}; Destination={1}; ItemCount={2}" -f $Source, $Destination, $items.Count) -VerboseOnly
}

function Get-UGSMGameMisCreatedDefaultSettings {
    [CmdletBinding()]
    param(
        [string]$ProfileName = 'MisCreated Server',
        [int]$GamePort = 64090,
        [int]$HttpPort = 64190
    )

    return [ordered]@{
        'sv_servername'          = ('UGSM MisCreated - {0}' -f $ProfileName)
        'sv_motd'                = 'Managed by UGSM'
        'sv_url'                 = ''
        'sv_maxuptime'           = '12'
        'http_password'          = 'ChangeMe'
        'sv_msg_conn'            = '1'
        'sv_msg_death'           = '1'
        'sv_maxplayers'          = '24'
        'map'                    = 'islands'
        'mis_gameserverid'       = '1337'
        'sv_bind'                = ''
        'sv_port'                = [string]$GamePort
        'http_port'              = [string]$HttpPort
        'wm_disable'             = '0'
        'wm_timeScale'           = '4'
        'wm_timeScaleNight'      = '4'
        'wm_forceTime'           = '-1'
        'steam_inventory_enable' = '1'
    }
}

function Read-UGSMGameMisCreatedHostingConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $settings = [ordered]@{}

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("hosting.cfg read skipped: file does not exist. Path={0}" -f $Path) -VerboseOnly
        return $settings
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.TrimStart().StartsWith('//')) { continue }
        if ($text -notmatch '^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$') { continue }

        $key = [string]$Matches[1]
        $value = [string]$Matches[2].Trim()

        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $settings[$key] = $value
    }

    return $settings
}

function Save-UGSMGameMisCreatedHostingConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $orderedKeys = @(
        'sv_servername',
        'sv_motd',
        'sv_url',
        'http_password',
        'sv_maxuptime',
        'sv_msg_conn',
        'sv_msg_death',
        'wm_disable',
        'wm_timeScale',
        'wm_timeScaleNight',
        'wm_forceTime',
        'steam_inventory_enable'
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('// UGSM MisCreated hosting.cfg')
    $lines.Add('// Saved from the instance profile editor')

    foreach ($key in $orderedKeys) {
        if (-not $Settings.Contains($key)) { continue }
        $value = [string]$Settings[$key]
        if ($key -in @('sv_servername', 'sv_motd', 'sv_url', 'http_password')) {
            $lines.Add(('{0}="{1}"' -f $key, $value.Replace('"', '\"')))
        }
        else {
            $lines.Add(('{0}={1}' -f $key, $value))
        }
    }

    $extraKeys = @($Settings.Keys | Where-Object { $orderedKeys -notcontains $_ } | Sort-Object)
    foreach ($key in $extraKeys) {
        $value = [string]$Settings[$key]
        if ($key -match '^(sv_|http_|wm_)') {
            $lines.Add(('{0}={1}' -f $key, $value))
        }
    }

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("hosting.cfg saved. Path={0}; SettingCount={1}" -f $Path, $Settings.Count) -VerboseOnly
}


function Get-UGSMGameMisCreatedStoredMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    $mods = @()

    if (Test-Path -LiteralPath $paths.ModsRoot -PathType Container) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $paths.ModsRoot -Force -ErrorAction SilentlyContinue)) {
            if ($entry.PSIsContainer) {
                $mods += [string]$entry.Name
            }
            elseif ($entry.Extension -ieq '.zip') {
                $mods += [string]$entry.Name
            }
        }
    }

    $uniqueMods = @($mods | Sort-Object -Unique)
    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("Stored MisCreated mods loaded. InstanceId={0}; Count={1}" -f ([string]$Instance.Id), $uniqueMods.Count) -VerboseOnly
    return $uniqueMods
}

function Sync-UGSMGameMisCreatedProfileModsToInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$ClearDestination
    )

    $syncSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Runtime mod sync requested. InstanceId={0}; ClearDestination={1}" -f ([string]$Instance.Id), $ClearDestination.IsPresent)

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    $installDef = Get-UGSMGameMisCreatedInstallDefinition -InstallPath ([string]$Instance.InstallPath) -Instance $Instance

    New-Item -ItemType Directory -Path $paths.ModsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $installDef.ModsRootPath -Force | Out-Null

    Copy-UGSMGameMisCreatedDirectoryContent -Source $paths.ModsRoot -Destination $installDef.ModsRootPath -ClearDestination:$ClearDestination.IsPresent

    $mods = @(Get-UGSMGameMisCreatedStoredMods -Instance $Instance)
    if ($Instance.PSObject.Properties.Name -contains 'Mods') {
        $Instance.Mods = @($mods)
    }

    $syncSw.Stop()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Runtime mod sync completed. InstanceId={0}; Count={1}; DurationMs={2}" -f ([string]$Instance.Id), @($mods).Count, [int]$syncSw.ElapsedMilliseconds)

    return [pscustomobject]@{
        GameId            = 'MisCreated'
        InstanceId        = [string]$Instance.Id
        ProfileModsRoot   = $paths.ModsRoot
        RuntimeModsRoot   = $installDef.ModsRootPath
        Mods              = @($mods)
        Synced            = $true
    }
}

function Get-UGSMGameMisCreatedProfilePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $profileRoot = if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        [string]$Instance.ProfilePath
    }
    else {
        if (Get-Command Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
            Get-UGSMDefaultInstanceProfilePath -GameId 'MisCreated' -Name ([string]$Instance.Name)
        }
        else {
            Get-UGSMGameMisCreatedProfileRoot -ProfileName ([string]$Instance.Name)
        }
    }

    [pscustomobject]@{
        ProfileRoot             = $profileRoot
        HostingConfigPath       = Join-Path $profileRoot 'hosting.cfg'
        LogsRoot                = Join-Path $profileRoot 'logs'
        ModsRoot                = Join-Path $profileRoot 'Mods'
        WorkshopManifestPath    = Join-Path $profileRoot 'WorkshopMods.txt'
    }
}

function Get-UGSMGameMisCreatedAssignedPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$PortName,
        [Parameter(Mandatory)][int]$DefaultValue
    )

    $candidateNames = @($PortName)
    if ($PortName -notmatch 'Port$') {
        $candidateNames += ($PortName + 'Port')
    }
    $candidateNames = @($candidateNames | Select-Object -Unique)

    foreach ($propName in $candidateNames) {
        if ($Instance.PSObject.Properties.Name -contains $propName) {
            $candidate = [string]$Instance.$propName
            if ($candidate -match '^\d+$') { return [int]$candidate }
        }
    }

    if ($Instance.PSObject.Properties.Name -contains 'Ports' -and $Instance.Ports) {
        $ports = $Instance.Ports

        if ($ports -is [hashtable]) {
            foreach ($key in $candidateNames) {
                if ($ports.Contains($key)) {
                    $candidate = [string]$ports[$key]
                    if ($candidate -match '^\d+$') { return [int]$candidate }
                }
            }
        }
        elseif ($ports -is [System.Collections.IDictionary]) {
            foreach ($key in $candidateNames) {
                if ($ports.Contains($key)) {
                    $candidate = [string]$ports[$key]
                    if ($candidate -match '^\d+$') { return [int]$candidate }
                }
            }
        }
        elseif ($ports.PSObject -and $ports.PSObject.Properties.Count -gt 0) {
            # ports.json and instance JSON commonly deserialize Ports as a PSCustomObject:
            # { "GamePort": 64093, "HttpPort": 64193 }
            foreach ($key in $candidateNames) {
                $prop = $ports.PSObject.Properties[$key]
                if ($prop) {
                    $candidate = [string]$prop.Value
                    if ($candidate -match '^\d+$') { return [int]$candidate }
                }
            }

            # Older shapes may be an array of objects with Name/Port-style properties.
            foreach ($entry in @($ports)) {
                $entryName = ''
                foreach ($n in @('Name', 'Id', 'Key')) {
                    if ($entry.PSObject.Properties.Name -contains $n) { $entryName = [string]$entry.$n; break }
                }
                if ($entryName -in $candidateNames) {
                    foreach ($p in @('Port', 'Value', 'Number')) {
                        if ($entry.PSObject.Properties.Name -contains $p) {
                            $candidate = [string]$entry.$p
                            if ($candidate -match '^\d+$') { return [int]$candidate }
                        }
                    }
                }
            }
        }
    }

    # Last-resort lookup: if the instance object does not carry Ports, consult the shared port registry.
    try {
        if ((Get-Command Get-UGSMPortRegistry -ErrorAction SilentlyContinue) -and
            ($Instance.PSObject.Properties.Name -contains 'Id') -and
            -not [string]::IsNullOrWhiteSpace([string]$Instance.Id)) {

            $registry = Get-UGSMPortRegistry -CreateIfMissing
            $assignment = @($registry.Assignments | Where-Object { [string]$_.InstanceId -eq [string]$Instance.Id } | Select-Object -First 1)
            if ($assignment -and $assignment.Ports) {
                foreach ($key in $candidateNames) {
                    if ($assignment.Ports -is [hashtable] -and $assignment.Ports.Contains($key)) {
                        $candidate = [string]$assignment.Ports[$key]
                        if ($candidate -match '^\d+$') { return [int]$candidate }
                    }
                    elseif ($assignment.Ports.PSObject.Properties[$key]) {
                        $candidate = [string]$assignment.Ports.PSObject.Properties[$key].Value
                        if ($candidate -match '^\d+$') { return [int]$candidate }
                    }
                }
            }
        }
    }
    catch {
        Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Failed to read MisCreated port assignment from registry. InstanceId={0}; PortName={1}" -f ([string]$Instance.Id), $PortName) -Exception $_.Exception
    }

    return $DefaultValue
}

function Ensure-UGSMGameMisCreatedTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 30
    )

    $templateSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Template ensure requested. InstallPath={0}; ForceRefresh={1}" -f $InstallPath, $ForceRefresh.IsPresent)

    $definition = Get-UGSMGameMisCreatedInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameMisCreatedInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "MisCreated install is not valid at '$InstallPath'."
    }

    $templateRoot = Get-UGSMGameMisCreatedTemplateRoot
    $templateHostingPath = Join-Path $templateRoot 'hosting.cfg'
    $templateModsRoot = Join-Path $templateRoot 'Mods'
    New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $templateModsRoot -Force | Out-Null

    $sourceHosting = [string]$definition.HostingConfigPath
    if ($ForceRefresh.IsPresent -or -not (Test-Path -LiteralPath $templateHostingPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $sourceHosting -PathType Leaf) {
            Copy-Item -LiteralPath $sourceHosting -Destination $templateHostingPath -Force
        }
        else {
            $defaults = Get-UGSMGameMisCreatedDefaultSettings
            Save-UGSMGameMisCreatedHostingConfig -Path $templateHostingPath -Settings $defaults
        }
    }

    $templateSw.Stop()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Template ensure completed. InstallPath={0}; DurationMs={1}" -f $InstallPath, [int]$templateSw.ElapsedMilliseconds)

    return [pscustomobject]@{
        GameId             = 'MisCreated'
        InstallPath        = $InstallPath
        TemplateRoot       = $templateRoot
        TemplateHostingCfg = $templateHostingPath
        TemplateModsRoot   = $templateModsRoot
    }
}


function Get-UGSMGameMisCreatedServerLogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $serverName = [string]$Instance.Name
    if ([string]::IsNullOrWhiteSpace($serverName)) { $serverName = [string]$Instance.Id }
    if ([string]::IsNullOrWhiteSpace($serverName)) { $serverName = 'Server' }

    if (Get-Command -Name New-UGSMServerLogDirectory -ErrorAction SilentlyContinue) {
        return [string](New-UGSMServerLogDirectory -GameId 'MisCreated' -ServerName $serverName)
    }

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
    }

    $safeServer = ($serverName -replace '[\\/:*?"<>|]', '_')
    $target = Join-Path (Join-Path (Join-Path $localAppData 'UGSM\Logs') 'MisCreated') $safeServer
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        New-Item -Path $target -ItemType Directory -Force | Out-Null
    }

    return [string]$target
}

function Sync-UGSMGameMisCreatedServerLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string[]]$SourceRoots = @()
    )

    $serverLogDir = Get-UGSMGameMisCreatedServerLogDirectory -Instance $Instance
    $copied = 0

    foreach ($sourceRoot in @($SourceRoots)) {
        if ([string]::IsNullOrWhiteSpace($sourceRoot)) { continue }
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { continue }

        $sourceItems = @(Get-ChildItem -LiteralPath $sourceRoot -File -ErrorAction SilentlyContinue)
        foreach ($item in $sourceItems) {
            try {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $serverLogDir $item.Name) -Force -ErrorAction Stop
                $copied++
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Failed to copy MisCreated server log. InstanceId={0}; Source={1}; Destination={2}" -f ([string]$Instance.Id), $item.FullName, $serverLogDir) -Exception $_.Exception
            }
        }
    }

    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("MisCreated server logs synced. InstanceId={0}; Destination={1}; Copied={2}" -f ([string]$Instance.Id), $serverLogDir, $copied) -VerboseOnly
    return [pscustomobject]@{
        LogDirectory = $serverLogDir
        Copied       = $copied
    }
}


function Initialize-UGSMGameMisCreatedProfile {
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByInstance')]
        [object]$Instance,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ProfileName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$InstallPath,

        [switch]$Force,

        [int]$BootstrapSeconds = 30
    )

    $profileSw = [System.Diagnostics.Stopwatch]::StartNew()
    $effectiveProfileName = ''
    $effectiveInstallPath = ''
    $instanceId = ''

    if ($PSCmdlet.ParameterSetName -eq 'ByInstance') {
        if (-not $Instance) { throw 'Instance is required.' }
        $effectiveProfileName = [string]$Instance.Name
        $effectiveInstallPath = [string]$Instance.InstallPath
        $instanceId = [string]$Instance.Id
    }
    else {
        $effectiveProfileName = [string]$ProfileName
        $effectiveInstallPath = [string]$InstallPath
    }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) {
        throw 'ProfileName could not be resolved for MisCreated profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a MisCreated profile.'
    }

    $gamePort = if ($Instance) { Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'GamePort' -DefaultValue 64090 } else { 64090 }
    $httpPort = if ($Instance) { Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'HttpPort' -DefaultValue 64190 } else { 64190 }

    $template = Ensure-UGSMGameMisCreatedTemplate -InstallPath $effectiveInstallPath
    $profileRoot = Get-UGSMGameMisCreatedProfileRoot -ProfileName $effectiveProfileName
    $hostingConfigPath = Join-Path $profileRoot 'hosting.cfg'
    $logsRoot = Join-Path $profileRoot 'logs'
    $modsRoot = Join-Path $profileRoot 'Mods'

    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
    $serverLogRoot = Get-UGSMGameMisCreatedServerLogDirectory -Instance $Instance
    New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null

    if (Test-Path -LiteralPath $template.TemplateHostingCfg -PathType Leaf) {
        Copy-Item -LiteralPath $template.TemplateHostingCfg -Destination $hostingConfigPath -Force
    }
    else {
        $defaults = Get-UGSMGameMisCreatedDefaultSettings -ProfileName $effectiveProfileName -GamePort $gamePort -HttpPort $httpPort
        Save-UGSMGameMisCreatedHostingConfig -Path $hostingConfigPath -Settings $defaults
    }

    $settings = Read-UGSMGameMisCreatedHostingConfig -Path $hostingConfigPath
    if ($settings.Count -eq 0) {
        $settings = Get-UGSMGameMisCreatedDefaultSettings -ProfileName $effectiveProfileName -GamePort $gamePort -HttpPort $httpPort
    }
    $settings['sv_servername'] = [string]$effectiveProfileName
    $settings['sv_port'] = [string]$gamePort
    $settings['http_port'] = [string]$httpPort
    if (-not $settings.Contains('mis_gameserverid') -or [string]::IsNullOrWhiteSpace([string]$settings['mis_gameserverid'])) {
        $settings['mis_gameserverid'] = ('{0}' -f (Get-Random -Minimum 1000 -Maximum 9999))
    }

    Save-UGSMGameMisCreatedHostingConfig -Path $hostingConfigPath -Settings $settings

    return [pscustomobject]@{
        GameId            = 'MisCreated'
        InstanceId        = $instanceId
        ProfileName       = $effectiveProfileName
        InstallPath       = $effectiveInstallPath
        ProfileRoot       = $profileRoot
        HostingConfigPath = $hostingConfigPath
        LogsRoot          = $logsRoot
        ServerLogRoot     = $serverLogRoot
        ModsRoot          = $modsRoot
        Initialized       = $true
    }
}

function Test-UGSMGameMisCreatedInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $definition = Get-UGSMGameMisCreatedInstallDefinition -InstallPath $InstallPath
        if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
            throw 'MisCreated validation failed: InstallPath could not be resolved.'
        }
        $InstallPath = [string]$definition.InstallPath
    }

    $metadata = Get-UGSMGameMisCreatedMetadata
    $serverExecutablePath = Join-Path $InstallPath $metadata.ServerExecutableRelative

    $installPathExists = Test-Path -LiteralPath $InstallPath -PathType Container
    $serverExecutableExists = Test-Path -LiteralPath $serverExecutablePath -PathType Leaf

    $missingItems = @()
    if (-not $installPathExists) { $missingItems += '.' }
    if (-not $serverExecutableExists) { $missingItems += [string]$metadata.ServerExecutableRelative }

    return [pscustomobject]@{
        GameId                 = 'MisCreated'
        InstallPath            = $InstallPath
        IsInstalled            = ($installPathExists -and $serverExecutableExists)
        IsValid                = ($installPathExists -and $serverExecutableExists)
        InstallPathExists      = $installPathExists
        ServerExecutablePath   = $serverExecutablePath
        ServerExecutableExists = $serverExecutableExists
        MissingItems           = @($missingItems)
    }
}

function Test-UGSMGameMisCreatedInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $install = Test-UGSMGameMisCreatedInstall -InstallPath ([string]$Instance.InstallPath)
    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance

    return [pscustomobject]@{
        GameId              = 'MisCreated'
        InstanceId          = [string]$Instance.Id
        InstanceName        = [string]$Instance.Name
        Install             = $install
        ProfileRoot         = $paths.ProfileRoot
        HostingConfigPath   = $paths.HostingConfigPath
        ProfileExists       = (Test-Path -LiteralPath $paths.ProfileRoot -PathType Container)
        HostingConfigExists = (Test-Path -LiteralPath $paths.HostingConfigPath -PathType Leaf)
        IsValid             = ($install.IsValid -and (Test-Path -LiteralPath $paths.HostingConfigPath -PathType Leaf))
    }
}

function Get-UGSMGameMisCreatedLaunchSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.HostingConfigPath -PathType Leaf)) {
        $null = Initialize-UGSMGameMisCreatedProfile -Instance $Instance
    }

    $settings = Read-UGSMGameMisCreatedHostingConfig -Path $paths.HostingConfigPath
    if ($settings.Count -eq 0) {
        $settings = Get-UGSMGameMisCreatedDefaultSettings -ProfileName ([string]$Instance.Name)
    }

    $gamePort = Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'GamePort' -DefaultValue 64090
    $httpPort = Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'HttpPort' -DefaultValue 64190
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Resolved MisCreated launch ports. InstanceId={0}; GamePort={1}; HttpPort={2}" -f ([string]$Instance.Id), $gamePort, $httpPort)

    $serverName = [string]$(if ($settings.Contains('sv_servername')) { $settings['sv_servername'] } else { $Instance.Name })
    $maxPlayers = [string]$(if ($settings.Contains('sv_maxplayers')) { $settings['sv_maxplayers'] } else { '24' })
    $map = [string]$(if ($settings.Contains('map')) { $settings['map'] } else { 'islands' })
    $gameServerId = [string]$(if ($settings.Contains('mis_gameserverid')) { $settings['mis_gameserverid'] } else { '1337' })
    $bindIp = [string]$(if ($settings.Contains('sv_bind')) { $settings['sv_bind'] } else { '' })
    $httpPassword = [string]$(if ($settings.Contains('http_password')) { $settings['http_password'] } else { '' })

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add(('+sv_maxplayers {0}' -f $maxPlayers))
    $args.Add(('+map {0}' -f $map))
    $args.Add(('-mis_gameserverid {0}' -f $gameServerId))
    if (-not [string]::IsNullOrWhiteSpace($bindIp)) {
        $args.Add(('-sv_bind {0}' -f $bindIp))
    }
    $args.Add(('-sv_port {0}' -f $gamePort))
    if (-not [string]::IsNullOrWhiteSpace($httpPassword)) {
        $args.Add(('+http_password "{0}"' -f $httpPassword.Replace('"', '\"')))
    }
    $args.Add(('+http_startserver port:{0}' -f $httpPort))
    $args.Add(('+sv_servername "{0}"' -f $serverName.Replace('"', '\"')))

    return [pscustomobject]@{
        Settings     = $settings
        Arguments    = ($args -join ' ')
        GamePort     = $gamePort
        HttpPort     = $httpPort
        HostingCfg   = $paths.HostingConfigPath
        ProfilePaths = $paths
    }
}

function Save-UGSMGameMisCreatedInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'Mods') {
        try {
            $Instance.Mods = @(Get-UGSMGameMisCreatedStoredMods -Instance $Instance)
        }
        catch {}
    }

    if (Get-Command Save-UGSMInstance -ErrorAction SilentlyContinue) {
        return (Save-UGSMInstance -Instance $Instance)
    }

    return $Instance
}

function Start-UGSMGameMisCreatedInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $startSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Start requested. InstanceId={0}; Name={1}" -f ([string]$Instance.Id), ([string]$Instance.Name))

    if (-not $Instance) {
        throw 'MisCreated start failed: Instance was null.'
    }

    $validation = Test-UGSMGameMisCreatedInstall -InstallPath ([string]$Instance.InstallPath)
    if (-not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'MisCreated start failed: the server executable is missing.'
    }

    $null = Initialize-UGSMGameMisCreatedProfile -Instance $Instance
    $installDef = Get-UGSMGameMisCreatedInstallDefinition -InstallPath ([string]$Instance.InstallPath) -Instance $Instance
    $serverLogRoot = Get-UGSMGameMisCreatedServerLogDirectory -Instance $Instance
    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("Server log directory ready. InstanceId={0}; Path={1}" -f ([string]$Instance.Id), $serverLogRoot) -VerboseOnly
    $launch = Get-UGSMGameMisCreatedLaunchSettings -Instance $Instance

    if (Test-Path -LiteralPath $launch.HostingCfg -PathType Leaf) {
        Copy-Item -LiteralPath $launch.HostingCfg -Destination $installDef.HostingConfigPath -Force
    }

    $null = Sync-UGSMGameMisCreatedProfileModsToInstall -Instance $Instance -ClearDestination

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $installDef.ServerExecutablePath
    $startInfo.WorkingDirectory = $installDef.InstallPath
    $startInfo.Arguments = [string]$launch.Arguments
    $startInfo.UseShellExecute = $false

    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Launching process. InstanceId={0}; Exe={1}; Args={2}" -f ([string]$Instance.Id), $installDef.ServerExecutablePath, (Convert-UGSMGameMisCreatedSafeLaunchArguments -Arguments ([string]$launch.Arguments)))
    $proc = [System.Diagnostics.Process]::Start($startInfo)
    Start-Sleep -Seconds 2

    if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = [int]$proc.Id }
    if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Running' }
    $saved = Save-UGSMGameMisCreatedInstance -Instance $Instance

    $startSw.Stop()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Start completed. InstanceId={0}; Pid={1}; DurationMs={2}" -f ([string]$Instance.Id), [int]$proc.Id, [int]$startSw.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance       = $saved
        Status         = 'Running'
        ProcessId      = [int]$proc.Id
        Arguments      = [string]$launch.Arguments
        HostingCfgPath = $installDef.HostingConfigPath
    }
}

function Stop-UGSMGameMisCreatedInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $stopSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Stop requested. InstanceId={0}; Name={1}" -f ([string]$Instance.Id), ([string]$Instance.Name))

    if (-not $Instance) {
        throw 'MisCreated stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameMisCreatedInstallDefinition -InstallPath ([string]$Instance.InstallPath) -Instance $Instance
    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    $stopped = $false

    # Stop-UGSMGameMisCreatedInstance
    $instancePid = $null
    if ($Instance.PSObject.Properties.Name -contains 'Pid') {
        try { $instancePid = [int]$Instance.Pid } catch { $instancePid = $null }
    }

    if ($instancePid) {
        try {
            Stop-Process -Id $instancePid -Force -ErrorAction Stop
            $stopped = $true
            Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Stopped process by saved PID. InstanceId={0}; Pid={1}" -f ([string]$Instance.Id), $instancePid)
        }
        catch {
            $stopped = $false
        }
    }

    if (-not $stopped) {
        $matches = @(Get-Process -Name 'MisCreatedServer' -ErrorAction SilentlyContinue)
        foreach ($proc in $matches) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                $stopped = $true
                Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Stopped MisCreated process by name fallback. InstanceId={0}; Pid={1}" -f ([string]$Instance.Id), [int]$proc.Id)
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Failed to stop fallback MisCreated process. InstanceId={0}; Pid={1}" -f ([string]$Instance.Id), [int]$proc.Id) -Exception $_.Exception
            }
        }
    }

    Start-Sleep -Seconds 2

    if (Test-Path -LiteralPath $installDef.HostingConfigPath -PathType Leaf) {
        Copy-Item -LiteralPath $installDef.HostingConfigPath -Destination $paths.HostingConfigPath -Force
    }

    if (Test-Path -LiteralPath $installDef.LogRootPath -PathType Container) {
        Copy-UGSMGameMisCreatedDirectoryContent -Source $installDef.LogRootPath -Destination $paths.LogsRoot
    }
    $null = Sync-UGSMGameMisCreatedServerLogs -Instance $Instance -SourceRoots @($installDef.LogRootPath, $paths.LogsRoot)

    if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $null }
    if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Stopped' }
    $saved = Save-UGSMGameMisCreatedInstance -Instance $Instance

    $stopSw.Stop()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Stop completed. InstanceId={0}; Stopped={1}; DurationMs={2}" -f ([string]$Instance.Id), $stopped, [int]$stopSw.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance = $saved
        Status   = 'Stopped'
        Stopped  = $stopped
    }
}


function Convert-UGSMGameMisCreatedWorkshopInputToId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputText
    )

    $value = [string]$InputText.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    if ($value -match '(?i)[?&]id=(\d{6,})') { return [string]$matches[1] }
    if ($value -match '(?i)/filedetails/?\?id=(\d{6,})') { return [string]$matches[1] }
    if ($value -match '^\d{6,}$') { return [string]$value }
    return ''
}

function Get-UGSMGameMisCreatedManagedWorkshopIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.WorkshopManifestPath -PathType Leaf)) {
        return @()
    }

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-Content -LiteralPath $paths.WorkshopManifestPath -ErrorAction SilentlyContinue)) {
        $id = Convert-UGSMGameMisCreatedWorkshopInputToId -InputText ([string]$line)
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $ids.Contains($id)) {
            $ids.Add($id)
        }
    }
    return @($ids)
}

function Save-UGSMGameMisCreatedManagedWorkshopIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowEmptyCollection()][AllowNull()][string[]]$WorkshopItemIds = @()
    )

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($rawId in @($WorkshopItemIds)) {
        $id = Convert-UGSMGameMisCreatedWorkshopInputToId -InputText ([string]$rawId)
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $normalized.Contains($id)) {
            $normalized.Add($id)
        }
    }

    $parent = Split-Path -Parent $paths.WorkshopManifestPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllLines($paths.WorkshopManifestPath, [string[]]@($normalized))
    return @($normalized)
}

function Get-UGSMGameMisCreatedSteamCmdExecutablePath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $candidates = @()
    if ($Instance) {
        foreach ($propertyName in @('SteamCMDPath', 'SteamCmdPath', 'SteamCmdExePath')) {
            if ($Instance.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$Instance.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates += $value }
            }
        }
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings) {
        foreach ($propertyName in @('SteamCMDPath', 'SteamCmdPath', 'SteamCmdExePath')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates += $value }
            }
        }
        foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $candidates += (Join-Path $value 'steamcmd.exe')
                    $candidates += (Join-Path $value 'SteamCMD\steamcmd.exe')
                    $candidates += (Join-Path $value 'tools\steamcmd\steamcmd.exe')
                }
            }
        }
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [string]$candidate }
    }

    throw 'MisCreated mod download failed: SteamCMD executable could not be resolved from the current settings.'
}

function Get-UGSMGameMisCreatedSteamLoginArguments {
    [CmdletBinding()]
    param()

    # MisCreated binaries and workshop content are handled through anonymous SteamCMD access.
    # Intentionally ignore any saved Steam credentials for this game module.
    return @('+login', 'anonymous')
}

function Get-UGSMGameMisCreatedWorkshopContentRoots {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $meta = Get-UGSMGameMisCreatedMetadata
    $roots = New-Object System.Collections.Generic.List[string]
    $appIds = @([string]$meta.SteamStoreAppId, [string]$meta.SteamAppId) | Select-Object -Unique

    $candidateBases = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace([string]$InstallPath)) {
        $cursor = $InstallPath
        for ($i = 0; $i -lt 5 -and -not [string]::IsNullOrWhiteSpace([string]$cursor); $i++) {
            if (-not $candidateBases.Contains($cursor)) { $candidateBases.Add($cursor) }
            $parent = Split-Path -Parent $cursor
            if ($parent -eq $cursor) { break }
            $cursor = $parent
        }
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings) {
        foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value) -and -not $candidateBases.Contains($value)) {
                    $candidateBases.Add($value)
                }
            }
        }
    }

    foreach ($base in @($candidateBases)) {
        foreach ($appId in @($appIds)) {
            foreach ($candidate in @(
                (Join-Path $base ("steamapps\workshop\content\{0}" -f $appId)),
                (Join-Path $base ("SteamCMD\steamapps\workshop\content\{0}" -f $appId)),
                (Join-Path $base ("tools\steamcmd\steamapps\workshop\content\{0}" -f $appId))
            )) {
                if ((Test-Path -LiteralPath $candidate -PathType Container) -and -not $roots.Contains($candidate)) {
                    $roots.Add($candidate)
                }
            }
        }
    }

    return @($roots)
}

function Invoke-UGSMGameMisCreatedWorkshopDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string[]]$WorkshopItemIds
    )

    $itemIds = New-Object System.Collections.Generic.List[string]
    foreach ($rawId in @($WorkshopItemIds)) {
        $itemId = Convert-UGSMGameMisCreatedWorkshopInputToId -InputText ([string]$rawId)
        if (-not [string]::IsNullOrWhiteSpace($itemId) -and -not $itemIds.Contains($itemId)) {
            $itemIds.Add($itemId)
        }
    }
    if ($itemIds.Count -eq 0) { throw 'No valid MisCreated workshop ids were provided.' }

    $workshopSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Workshop download requested. InstanceId={0}; ItemCount={1}; Items={2}" -f ([string]$Instance.Id), $itemIds.Count, ([string](@($itemIds) -join ',')))

    $steamCmdPath = Get-UGSMGameMisCreatedSteamCmdExecutablePath -Instance $Instance
    $steamCmdRoot = Split-Path -Parent $steamCmdPath
    $meta = Get-UGSMGameMisCreatedMetadata

    $argumentParts = @()
    $argumentParts += @(Get-UGSMGameMisCreatedSteamLoginArguments)
    foreach ($itemId in @($itemIds)) {
        $argumentParts += @('+workshop_download_item', [string]$meta.SteamStoreAppId, [string]$itemId)
    }
    $argumentParts += '+quit'

    $argumentString = ($argumentParts | ForEach-Object {
        $part = [string]$_
        if ($part -match '\s') { '"{0}"' -f $part.Replace('"', '\"') } else { $part }
    }) -join ' '

    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Starting SteamCMD workshop download. InstanceId={0}; ItemCount={1}" -f ([string]$Instance.Id), $itemIds.Count)
    $process = Start-Process -FilePath $steamCmdPath -WorkingDirectory $steamCmdRoot -ArgumentList $argumentString -PassThru -Wait
    if ($null -eq $process) { throw 'MisCreated mod download failed: SteamCMD process did not start.' }
    if ([int]$process.ExitCode -ne 0) { throw ('MisCreated mod download failed: SteamCMD exited with code {0}.' -f [int]$process.ExitCode) }

    $contentRoots = @(Get-UGSMGameMisCreatedWorkshopContentRoots -InstallPath ([string]$Instance.InstallPath))
    $missingItems = New-Object System.Collections.Generic.List[string]
    foreach ($itemId in @($itemIds)) {
        $found = $false
        foreach ($root in @($contentRoots)) {
            $candidate = Join-Path $root $itemId
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $found = $true
                break
            }
        }
        if (-not $found) { $missingItems.Add($itemId) }
    }

    $workshopSw.Stop()
    if ($missingItems.Count -gt 0) {
        Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Workshop download completed with missing content. InstanceId={0}; Missing={1}; DurationMs={2}" -f ([string]$Instance.Id), ([string](@($missingItems) -join ',')), [int]$workshopSw.ElapsedMilliseconds)
    }
    else {
        Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Workshop download completed. InstanceId={0}; ItemCount={1}; DurationMs={2}" -f ([string]$Instance.Id), $itemIds.Count, [int]$workshopSw.ElapsedMilliseconds)
    }

    return [pscustomobject]@{
        SteamCmdPath = $steamCmdPath
        SteamCmdRoot = $steamCmdRoot
        ItemIds      = @($itemIds)
        ExitCode     = [int]$process.ExitCode
        MissingItems = @($missingItems)
        ContentRoots = @($contentRoots)
    }
}

function Install-UGSMGameMisCreatedWorkshopItemsToProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string[]]$WorkshopItemIds
    )

    $installWorkshopSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Install workshop items to profile requested. InstanceId={0}; RequestedCount={1}" -f ([string]$Instance.Id), @($WorkshopItemIds).Count)

    $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
    New-Item -ItemType Directory -Path $paths.ModsRoot -Force | Out-Null

    $downloadResult = Invoke-UGSMGameMisCreatedWorkshopDownload -Instance $Instance -WorkshopItemIds $WorkshopItemIds
    $installed = New-Object System.Collections.Generic.List[string]
    foreach ($itemId in @($downloadResult.ItemIds)) {
        $sourceRoot = $null
        foreach ($root in @($downloadResult.ContentRoots)) {
            $candidate = Join-Path $root $itemId
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $sourceRoot = $candidate
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$sourceRoot)) { continue }

        $destination = Join-Path $paths.ModsRoot ('ws_{0}' -f $itemId)
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-UGSMGameMisCreatedDirectoryContent -Source $sourceRoot -Destination $destination -ClearDestination
        $installed.Add(('ws_{0}' -f $itemId))
    }

    $existing = @(Get-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance)
    $combined = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($existing + @($downloadResult.ItemIds))) {
        $norm = Convert-UGSMGameMisCreatedWorkshopInputToId -InputText ([string]$id)
        if (-not [string]::IsNullOrWhiteSpace($norm) -and -not $combined.Contains($norm)) {
            $combined.Add($norm)
        }
    }
    $savedIds = Save-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance -WorkshopItemIds @($combined)

    if ($Instance.PSObject.Properties.Name -contains 'Mods') {
        try { $Instance.Mods = @(Get-UGSMGameMisCreatedStoredMods -Instance $Instance) } catch {}
    }
    try { $null = Save-UGSMGameMisCreatedInstance -Instance $Instance } catch {}

    $installWorkshopSw.Stop()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Install workshop items to profile completed. InstanceId={0}; InstalledCount={1}; ManagedCount={2}; DurationMs={3}" -f ([string]$Instance.Id), $installed.Count, @($savedIds).Count, [int]$installWorkshopSw.ElapsedMilliseconds)

    return [pscustomobject]@{
        DownloadResult = $downloadResult
        InstalledMods  = @($installed)
        ManagedIds     = @($savedIds)
        Mods           = @(Get-UGSMGameMisCreatedStoredMods -Instance $Instance)
    }
}


function Register-UGSMGameMisCreatedModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameMisCreatedMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameMisCreatedMetadata'
            TestInstall       = 'Test-UGSMGameMisCreatedInstall'
            TestInstance      = 'Test-UGSMGameMisCreatedInstance'
            EnsureTemplate    = 'Ensure-UGSMGameMisCreatedTemplate'
            InitializeProfile = 'Initialize-UGSMGameMisCreatedProfile'
            Start             = 'Start-UGSMGameMisCreatedInstance'
            Stop              = 'Stop-UGSMGameMisCreatedInstance'
        }
    }
}

function New-UGSMGameMisCreatedInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    $editorSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Instance editor creation started. InstanceId={0}; Name={1}" -f ([string]$Instance.Id), ([string]$Instance.Name))

    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = $Theme.WindowBg

        $paths = Get-UGSMGameMisCreatedProfilePaths -Instance $Instance
        if (-not (Test-Path -LiteralPath $paths.HostingConfigPath -PathType Leaf)) {
            try { $null = Initialize-UGSMGameMisCreatedProfile -Instance $Instance } catch {}
        }
        $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance

        $settings = Read-UGSMGameMisCreatedHostingConfig -Path $paths.HostingConfigPath
        if ($settings.Count -eq 0) {
            $settings = Get-UGSMGameMisCreatedDefaultSettings -ProfileName ([string]$Instance.Name)
        }

        $root = New-Object System.Windows.Forms.TableLayoutPanel
        $root.Dock = 'Fill'
        $root.Margin = New-Object System.Windows.Forms.Padding(0)
        $root.Padding = New-Object System.Windows.Forms.Padding(0)
        $root.ColumnCount = 1
        $root.RowCount = 2
        [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$HostPanel.Controls.Add($root)

        $toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
        $toolbar.Dock = 'Fill'
        $toolbar.WrapContents = $false
        $toolbar.AutoScroll = $true
        $toolbar.Margin = New-Object System.Windows.Forms.Padding(0)
        $toolbar.Padding = New-Object System.Windows.Forms.Padding(0)
        $toolbar.BackColor = $Theme.WindowBg
        [void]$root.Controls.Add($toolbar, 0, 0)

        function New-MisButton {
            param([string]$Text, [int]$Width = 120, [AllowNull()][object]$BackColor = $null)
            $btn = New-UGSMButton -Text $Text -X 0 -Y 0 -Width $Width -Height 30
            $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
            if ($null -ne $BackColor -and -not [string]::IsNullOrWhiteSpace([string]$BackColor)) {
                $btn.BackColor = New-UGSMColor $BackColor
            }
            return $btn
        }

        $toolbar.FlowDirection = 'RightToLeft'

        $btnReload = New-MisButton -Text 'Reload' -Width 86
        $btnSave = New-MisButton -Text 'Save All' -Width 112 -BackColor $Theme.Accent
        [void]$toolbar.Controls.AddRange(@($btnSave, $btnReload))

        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.Margin = New-Object System.Windows.Forms.Padding(0)
        $tabs.Padding = New-Object System.Drawing.Point(18, 6)
        $tabs.Appearance = 'Normal'
        [void]$root.Controls.Add($tabs, 0, 1)

        $tabGeneral = New-Object System.Windows.Forms.TabPage
        $tabGeneral.Text = 'General'
        $tabGeneral.BackColor = $Theme.WindowBg
        $tabGeneral.ForeColor = New-UGSMColor $Theme.Text
        [void]$tabs.TabPages.Add($tabGeneral)

        $tabMods = New-Object System.Windows.Forms.TabPage
        $tabMods.Text = 'Mods'
        $tabMods.BackColor = $Theme.WindowBg
        $tabMods.ForeColor = New-UGSMColor $Theme.Text
        [void]$tabs.TabPages.Add($tabMods)

        $tabDiscord = New-Object System.Windows.Forms.TabPage
        $tabDiscord.Text = 'Discord'
        $tabDiscord.BackColor = $Theme.WindowBg
        $tabDiscord.ForeColor = New-UGSMColor $Theme.Text
        [void]$tabs.TabPages.Add($tabDiscord)

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.Margin = New-Object System.Windows.Forms.Padding(0)
        $scroll.Padding = New-Object System.Windows.Forms.Padding(12)
        $scroll.BackColor = $Theme.WindowBg
        [void]$tabGeneral.Controls.Add($scroll)

        $layout = New-Object System.Windows.Forms.TableLayoutPanel
        $layout.Dock = 'Top'
        $layout.AutoSize = $true
        $layout.AutoSizeMode = 'GrowAndShrink'
        $layout.Margin = New-Object System.Windows.Forms.Padding(0)
        $layout.Padding = New-Object System.Windows.Forms.Padding(0)
        $layout.ColumnCount = 2
        [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
        [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$scroll.Controls.Add($layout)

        function Add-MisRow {
            param(
                [string]$Label,
                [System.Windows.Forms.Control]$Control,
                [string]$Hint = ''
            )

            $rowIndex = $layout.RowCount
            $layout.RowCount += 1
            [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

            $lbl = New-UGSMLabel -Text $Label -X 0 -Y 0 -Width 170 -Height 24 -FontSize 8.75 -Style Bold -Color $Theme.Text
            $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 8, 12, 0)
            $lbl.Dock = 'Top'
            [void]$layout.Controls.Add($lbl, 0, $rowIndex)

            $fieldHost = New-Object System.Windows.Forms.TableLayoutPanel
            $fieldHost.Dock = 'Top'
            $fieldHost.AutoSize = $true
            $fieldHost.AutoSizeMode = 'GrowAndShrink'
            $fieldHost.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
            $fieldHost.Padding = New-Object System.Windows.Forms.Padding(0)
            $fieldHost.ColumnCount = 1
            $fieldHost.RowCount = if ([string]::IsNullOrWhiteSpace($Hint)) { 1 } else { 2 }
            [void]$fieldHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
            [void]$fieldHost.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
            if ($fieldHost.RowCount -eq 2) {
                [void]$fieldHost.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
            }

            $Control.Margin = New-Object System.Windows.Forms.Padding(0)
            $Control.Anchor = 'Top, Left'
            if ($Control -is [System.Windows.Forms.TextBox]) {
                $Control.Width = [Math]::Min([int]$Control.Width, 420)
            } elseif ($Control -is [System.Windows.Forms.ComboBox]) {
                $Control.Width = [Math]::Min([int]$Control.Width, 220)
            } elseif ($Control -is [System.Windows.Forms.NumericUpDown]) {
                $Control.Width = [Math]::Min([int]$Control.Width, 180)
            }
            [void]$fieldHost.Controls.Add($Control, 0, 0)

            if (-not [string]::IsNullOrWhiteSpace($Hint)) {
                $hintLabel = New-UGSMLabel -Text $Hint -X 0 -Y 0 -Width 780 -Height 28 -FontSize 8.25 -Color $Theme.Muted
                $hintLabel.AutoSize = $false
                $hintLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
                $hintLabel.Dock = 'Top'
                [void]$fieldHost.Controls.Add($hintLabel, 0, 1)
            }

            [void]$layout.Controls.Add($fieldHost, 1, $rowIndex)
        }

        function New-MisTextBox {
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Height = 24
            $tb.Width = 420
            return $tb
        }

        function New-MisNumber {
            param([int]$Minimum = 0, [int]$Maximum = 65535)
            $num = New-Object System.Windows.Forms.NumericUpDown
            $num.Minimum = $Minimum
            $num.Maximum = $Maximum
            $num.Height = 24
            $num.Width = 160
            return $num
        }

        function New-MisCheckbox {
            $cb = New-Object System.Windows.Forms.CheckBox
            $cb.AutoSize = $true
            $cb.ForeColor = New-UGSMColor $Theme.Text
            return $cb
        }

        $txtServerName = New-MisTextBox
        $txtServerName.Text = [string]$(if ($settings.Contains('sv_servername')) { $settings['sv_servername'] } else { $Instance.Name })

        $txtMotd = New-MisTextBox
        $txtMotd.Text = [string]$(if ($settings.Contains('sv_motd')) { $settings['sv_motd'] } else { '' })

        $txtUrl = New-MisTextBox
        $txtUrl.Text = [string]$(if ($settings.Contains('sv_url')) { $settings['sv_url'] } else { '' })

        $cmbMap = New-Object System.Windows.Forms.ComboBox
        $cmbMap.DropDownStyle = 'DropDown'
        $cmbMap.Width = 180
        [void]$cmbMap.Items.AddRange(@('islands', 'main', 'canyonlands'))
        $cmbMap.Text = [string]$(if ($settings.Contains('map')) { $settings['map'] } else { 'islands' })

        $numMaxPlayers = New-MisNumber -Minimum 1 -Maximum 200
        $numMaxPlayers.Value = [decimal]([int]$(if ($settings.Contains('sv_maxplayers')) { $settings['sv_maxplayers'] } else { '24' }))

        $numGamePort = New-MisNumber -Minimum 1 -Maximum 65535
        $numGamePort.Value = [decimal]([int](Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'GamePort' -DefaultValue 64090))

        $numHttpPort = New-MisNumber -Minimum 1 -Maximum 65535
        $numHttpPort.Value = [decimal]([int](Get-UGSMGameMisCreatedAssignedPort -Instance $Instance -PortName 'HttpPort' -DefaultValue 64190))

        $txtBindIp = New-MisTextBox
        $txtBindIp.Text = [string]$(if ($settings.Contains('sv_bind')) { $settings['sv_bind'] } else { '' })

        $numServerId = New-MisNumber -Minimum 1000 -Maximum 999999
        $numServerId.Value = [decimal]([int]$(if ($settings.Contains('mis_gameserverid')) { $settings['mis_gameserverid'] } else { '1337' }))

        $txtHttpPassword = New-MisTextBox
        $txtHttpPassword.Text = [string]$(if ($settings.Contains('http_password')) { $settings['http_password'] } else { '' })

        $chkConn = New-MisCheckbox
        $chkConn.Text = 'Announce player connections'
        $chkConn.Checked = ([string]$(if ($settings.Contains('sv_msg_conn')) { $settings['sv_msg_conn'] } else { '1' }) -eq '1')

        $chkDeath = New-MisCheckbox
        $chkDeath.Text = 'Announce player deaths'
        $chkDeath.Checked = ([string]$(if ($settings.Contains('sv_msg_death')) { $settings['sv_msg_death'] } else { '1' }) -eq '1')

        Add-MisRow -Label 'Server Name'     -Control $txtServerName -Hint 'Public server name shown to players in the MisCreated server browser.'
        Add-MisRow -Label 'MOTD'            -Control $txtMotd       -Hint 'Short message shown to players when they join.'
        Add-MisRow -Label 'Website URL'     -Control $txtUrl        -Hint 'Optional website or community URL for the server.'
        Add-MisRow -Label 'Map'             -Control $cmbMap        -Hint 'Community setup guides commonly use the islands map for dedicated servers.'
        Add-MisRow -Label 'Max Players'     -Control $numMaxPlayers -Hint 'The launch command still passes this value to the dedicated server.'
        Add-MisRow -Label 'Game Port'       -Control $numGamePort   -Hint 'Default community examples use 64090.'
        Add-MisRow -Label 'HTTP Port'       -Control $numHttpPort   -Hint 'Used for the +http_startserver listener. Community examples commonly use 64190.'
        Add-MisRow -Label 'Bind IP'         -Control $txtBindIp     -Hint 'Optional. Leave blank unless you need the server to bind to a specific adapter.'
        Add-MisRow -Label 'Server ID'       -Control $numServerId   -Hint 'Unique numeric server ID passed through -mis_gameserverid.'
        Add-MisRow -Label 'HTTP Password'   -Control $txtHttpPassword -Hint 'Used by http_startserver. Leave blank until you need remote admin tooling.'
        Add-MisRow -Label 'Connection Feed' -Control $chkConn       -Hint 'Mirrors sv_msg_conn in hosting.cfg.'
        Add-MisRow -Label 'Death Feed'      -Control $chkDeath      -Hint 'Mirrors sv_msg_death in hosting.cfg.'

        # Discord Tab
        $discordScroll = New-Object System.Windows.Forms.Panel
        $discordScroll.Dock = 'Fill'
        $discordScroll.AutoScroll = $true
        $discordScroll.Padding = New-Object System.Windows.Forms.Padding(12)
        $discordScroll.BackColor = $Theme.WindowBg
        [void]$tabDiscord.Controls.Add($discordScroll)

        $discordLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $discordLayout.Dock = 'Top'
        $discordLayout.AutoSize = $true
        $discordLayout.AutoSizeMode = 'GrowAndShrink'
        $discordLayout.ColumnCount = 2
        [void]$discordLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
        [void]$discordLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$discordScroll.Controls.Add($discordLayout)

        function Add-DiscordRow {
            param([string]$Label, [System.Windows.Forms.Control]$Control, [string]$Hint = '')
            $rowIndex = $discordLayout.RowCount
            $discordLayout.RowCount += 1
            [void]$discordLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
            $lbl = New-UGSMLabel -Text $Label -X 0 -Y 0 -Width 170 -Height 24 -FontSize 8.75 -Style Bold -Color $Theme.Text
            $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 8, 12, 0)
            $lbl.Dock = 'Top'
            [void]$discordLayout.Controls.Add($lbl, 0, $rowIndex)
            $Control.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
            $Control.Anchor = 'Top, Left'
            if ($Control -is [System.Windows.Forms.TextBox]) {
                $Control.Width = [Math]::Min([int]$Control.Width, 520)
            } elseif ($Control -is [System.Windows.Forms.Button]) {
                $Control.Width = [Math]::Min([int]$Control.Width, 180)
            }
            [void]$discordLayout.Controls.Add($Control, 1, $rowIndex)
        }

        $txtDiscordWebhook = New-MisTextBox
        $txtDiscordWebhook.Text = [string]$discordModel.WebhookUrl
        $chkNotifyStart = New-MisCheckbox
        $chkNotifyStart.Text = 'Notify On Start'
        $chkNotifyStart.Checked = [bool]$discordModel.NotifyOnStart
        $chkNotifyStop = New-MisCheckbox
        $chkNotifyStop.Text = 'Notify On Stop'
        $chkNotifyStop.Checked = [bool]$discordModel.NotifyOnStop
        $chkShowInDashboard = New-MisCheckbox
        $chkShowInDashboard.Text = 'Show In Dashboard'
        $chkShowInDashboard.Checked = [bool]$discordModel.ShowInDashboard

        $btnTestDiscord = New-UGSMButton -Text 'Send Test Message' -X 0 -Y 0 -Width 180 -Height 30
        $btnTestDiscord.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)

        Add-DiscordRow -Label 'Webhook URL' -Control $txtDiscordWebhook -Hint 'Optional per-server webhook override. Blank uses the global webhook.'
        Add-DiscordRow -Label 'Notifications' -Control $chkNotifyStart
        $rowIndex = $discordLayout.RowCount
        $discordLayout.RowCount += 1
        [void]$discordLayout.Controls.Add($chkNotifyStop, 1, $rowIndex)
        Add-DiscordRow -Label 'Visibility' -Control $chkShowInDashboard
        $rowIndex = $discordLayout.RowCount
        $discordLayout.RowCount += 1
        [void]$discordLayout.Controls.Add($btnTestDiscord, 1, $rowIndex)

        $modsRoot = New-Object System.Windows.Forms.Panel
        $modsRoot.Dock = 'Fill'
        $modsRoot.BackColor = $Theme.WindowBg
        $modsRoot.Padding = New-Object System.Windows.Forms.Padding(10)
        [void]$tabMods.Controls.Add($modsRoot)

        $modsHeader = New-UGSMLabel -Text 'Manage MisCreated profile mods. Workshop downloads are stored in the profile Mods folder and synced to the shared runtime install when needed.' -X 10 -Y 8 -Width 1180 -Height 34 -FontSize 8.5 -Color $Theme.Muted
        $modsHeader.AutoSize = $false
        [void]$modsRoot.Controls.Add($modsHeader)

        $lstMods = New-Object System.Windows.Forms.ListBox
        $lstMods.Location = New-Object System.Drawing.Point(10, 50)
        $lstMods.Size = New-Object System.Drawing.Size(360, 420)
        $lstMods.BackColor = [System.Drawing.Color]::White
        $lstMods.ForeColor = [System.Drawing.Color]::Black
        [void]$modsRoot.Controls.Add($lstMods)

        $btnRemoveMod = New-UGSMButton -Text 'Remove Selected' -X 10 -Y 480 -Width 170 -Height 34 -BackColor $global:UGSM_ColorButtonRemove
        $btnSyncRuntime = New-UGSMButton -Text 'Sync Mods to Runtime' -X 190 -Y 480 -Width 180 -Height 34 -BackColor $global:UGSM_ColorPrimary
        [void]$modsRoot.Controls.AddRange(@($btnRemoveMod, $btnSyncRuntime))

        $rightPanel = New-Object System.Windows.Forms.Panel
        $rightPanel.Location = New-Object System.Drawing.Point(390, 50)
        $rightPanel.Size = New-Object System.Drawing.Size(500, 470)
        $rightPanel.BackColor = $Theme.Surface
        [void]$modsRoot.Controls.Add($rightPanel)

        $addTitle = New-UGSMLabel -Text 'Add / Download Workshop Mod' -X 14 -Y 14 -Width 240 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        $lblWorkshop = New-UGSMLabel -Text 'Workshop ID / URL:' -X 14 -Y 44 -Width 180 -Height 18 -FontSize 8.5 -Color $Theme.Text
        $txtWorkshop = New-Object System.Windows.Forms.TextBox
        $txtWorkshop.Location = New-Object System.Drawing.Point(14, 66)
        $txtWorkshop.Size = New-Object System.Drawing.Size(300, 24)
        $btnAddWorkshop = New-UGSMButton -Text 'Add + Download' -X 326 -Y 64 -Width 150 -Height 28 -BackColor $global:UGSM_ColorPrimary

        $utilityTitle = New-UGSMLabel -Text 'Utility Actions' -X 14 -Y 116 -Width 180 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        $btnDownloadAll = New-UGSMButton -Text 'Download / Update All Managed Mods' -X 14 -Y 146 -Width 462 -Height 34 -BackColor $global:UGSM_ColorCaution
        $btnRefreshMods = New-UGSMButton -Text 'Refresh Mod List' -X 14 -Y 188 -Width 220 -Height 34
        $btnOpenCfgMods = New-UGSMButton -Text 'Open hosting.cfg' -X 256 -Y 188 -Width 220 -Height 34

        $lblManaged = New-UGSMLabel -Text 'Managed Workshop IDs' -X 14 -Y 242 -Width 180 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        $txtManaged = New-Object System.Windows.Forms.TextBox
        $txtManaged.Location = New-Object System.Drawing.Point(14, 264)
        $txtManaged.Size = New-Object System.Drawing.Size(462, 150)
        $txtManaged.Multiline = $true
        $txtManaged.ReadOnly = $true
        $txtManaged.ScrollBars = 'Vertical'

        [void]$rightPanel.Controls.AddRange(@($addTitle, $lblWorkshop, $txtWorkshop, $btnAddWorkshop, $utilityTitle, $btnDownloadAll, $btnRefreshMods, $btnOpenCfgMods, $lblManaged, $txtManaged))

        $modsFooter = New-UGSMLabel -Text '' -X 10 -Y 525 -Width 980 -Height 20 -FontSize 8.25 -Color $Theme.Muted
        [void]$modsRoot.Controls.Add($modsFooter)

        $refreshModsUi = {
            $lstMods.BeginUpdate()
            try {
                $lstMods.Items.Clear()
                foreach ($mod in @(Get-UGSMGameMisCreatedStoredMods -Instance $Instance)) {
                    [void]$lstMods.Items.Add([string]$mod)
                }
            }
            finally {
                $lstMods.EndUpdate()
            }

            $managed = @(Get-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance)
            $txtManaged.Text = if ($managed.Count -gt 0) { [string]($managed -join [Environment]::NewLine) } else { 'No managed workshop mods yet.' }
            $modsFooter.Text = ('Profile Mods: {0} | Managed Workshop IDs: {1}' -f $lstMods.Items.Count, $managed.Count)
        }.GetNewClosure()

        $saveAction = {
            try {
                $saveSw = [System.Diagnostics.Stopwatch]::StartNew()
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Editor save requested. InstanceId={0}" -f ([string]$Instance.Id))
                $updated = Read-UGSMGameMisCreatedHostingConfig -Path $paths.HostingConfigPath
                if ($updated.Count -eq 0) {
                    $updated = [ordered]@{}
                }

                $discordInput = [pscustomobject]@{
                    WebhookUrl      = [string]$txtDiscordWebhook.Text.Trim()
                    NotifyOnStart   = [bool]$chkNotifyStart.Checked
                    NotifyOnStop    = [bool]$chkNotifyStop.Checked
                    ShowInDashboard = [bool]$chkShowInDashboard.Checked
                }

                $persistScript = {
                    param($PersistedInstance)
                    if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) {
                        [void](Save-UGSMInstance -Instance $PersistedInstance)
                    }
                }

                $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $Instance -InputObject $discordInput -PersistInstance $persistScript

                $defaults = Get-UGSMGameMisCreatedDefaultSettings -ProfileName ([string]$Instance.Name)
                foreach ($key in $defaults.Keys) {
                    if (-not $updated.Contains($key)) { $updated[$key] = [string]$defaults[$key] }
                }

                $updated['sv_servername'] = [string]$txtServerName.Text.Trim()
                $updated['sv_motd'] = [string]$txtMotd.Text.Trim()
                $updated['sv_url'] = [string]$txtUrl.Text.Trim()
                $updated['map'] = [string]$cmbMap.Text.Trim()
                $updated['sv_maxplayers'] = [string]([int]$numMaxPlayers.Value)
                $updated['sv_port'] = [string]([int]$numGamePort.Value)
                $updated['http_port'] = [string]([int]$numHttpPort.Value)
                $updated['sv_bind'] = [string]$txtBindIp.Text.Trim()
                $updated['mis_gameserverid'] = [string]([int]$numServerId.Value)
                $updated['http_password'] = [string]$txtHttpPassword.Text.Trim()
                $updated['sv_msg_conn'] = if ($chkConn.Checked) { '1' } else { '0' }
                $updated['sv_msg_death'] = if ($chkDeath.Checked) { '1' } else { '0' }

                Save-UGSMGameMisCreatedHostingConfig -Path $paths.HostingConfigPath -Settings $updated
                $null = Save-UGSMGameMisCreatedInstance -Instance $Instance

                $saveSw.Stop()
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Editor save completed. InstanceId={0}; DurationMs={1}" -f ([string]$Instance.Id), [int]$saveSw.ElapsedMilliseconds)
                if ($StatusLabel) { $StatusLabel.Text = 'Saved MisCreated profile settings.' }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'ERROR' -Message ("Editor save failed. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'MisCreated save failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $btnTestDiscord.Add_Click({
            try {
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Discord test clicked from editor. InstanceId={0}" -f ([string]$Instance.Id))
                $dm = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
                if (-not $dm.HasWebhook) {
                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook configured.' }
                    return
                }
                $res = Test-UGSMDiscordWebhook -WebhookUrl $dm.EffectiveWebhookUrl -Label ("MisCreated " + [string]$Instance.Name)
                if ($res -and $res.Success) {
                    $target = if ($dm.UsesGlobalWebhook) { 'global webhook' } else { 'server webhook' }
                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully using the ' + $target + '.' }
                }
                else {
                    $err = ''
                    if ($res -and $res.Error) { $err = [string]$res.Error }
                    if ([string]::IsNullOrWhiteSpace($err)) { $err = 'Unknown error.' }
                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $err }
                }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Discord test failed from editor. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure())

        $reloadAction = {
            if ($StatusLabel) { $StatusLabel.Text = 'Reloading MisCreated profile editor...' }
            New-UGSMGameMisCreatedInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel
        }.GetNewClosure()

        $openHosting = {
            if (Test-Path -LiteralPath $paths.HostingConfigPath -PathType Leaf) {
                Start-Process -FilePath $paths.HostingConfigPath | Out-Null
                if ($StatusLabel) { $StatusLabel.Text = 'Opened hosting.cfg.' }
            }
        }.GetNewClosure()

        $addWorkshop = {
            try {
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Add workshop clicked from editor. InstanceId={0}" -f ([string]$Instance.Id))
                $itemId = Convert-UGSMGameMisCreatedWorkshopInputToId -InputText ([string]$txtWorkshop.Text)
                if ([string]::IsNullOrWhiteSpace($itemId)) {
                    throw 'Enter a valid MisCreated workshop URL or numeric workshop id.'
                }

                if ($StatusLabel) { $StatusLabel.Text = ('Downloading MisCreated workshop item {0}...' -f $itemId) }
                $result = Install-UGSMGameMisCreatedWorkshopItemsToProfile -Instance $Instance -WorkshopItemIds @($itemId)
                & $refreshModsUi
                $txtWorkshop.Clear()
                $tabs.SelectedTab = $tabMods
                if ($StatusLabel) { $StatusLabel.Text = ('Downloaded and installed workshop mod {0}.' -f $itemId) }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'ERROR' -Message ("Workshop add failed from editor. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'MisCreated workshop add failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $downloadAllManaged = {
            try {
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Download all managed workshop mods clicked. InstanceId={0}" -f ([string]$Instance.Id))
                $ids = @(Get-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance)
                if ($ids.Count -eq 0) {
                    throw 'No managed MisCreated workshop IDs were saved yet.'
                }
                if ($StatusLabel) { $StatusLabel.Text = ('Downloading / updating {0} managed MisCreated workshop mod(s)...' -f $ids.Count) }
                $null = Install-UGSMGameMisCreatedWorkshopItemsToProfile -Instance $Instance -WorkshopItemIds $ids
                & $refreshModsUi
                if ($StatusLabel) { $StatusLabel.Text = ('Downloaded / updated {0} managed MisCreated workshop mod(s).' -f $ids.Count) }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'ERROR' -Message ("Managed workshop update failed from editor. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'MisCreated workshop update failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $removeSelected = {
            try {
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Remove mod clicked from editor. InstanceId={0}" -f ([string]$Instance.Id))
                if ($lstMods.SelectedItem -eq $null) {
                    throw 'Select a mod to remove first.'
                }

                $name = [string]$lstMods.SelectedItem
                $target = Join-Path $paths.ModsRoot $name
                if (Test-Path -LiteralPath $target -PathType Container) {
                    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                }
                elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                    Remove-Item -LiteralPath $target -Force -ErrorAction Stop
                }

                $managed = @(Get-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance)
                $idFromName = ''
                if ($name -match '^ws_(\d+)$') { $idFromName = [string]$matches[1] }
                elseif ($name -match '^(\d+)$') { $idFromName = [string]$matches[1] }

                if (-not [string]::IsNullOrWhiteSpace($idFromName)) {
                    $managed = @($managed | Where-Object { [string]$_ -ne $idFromName })
                    $savedManaged = @(Save-UGSMGameMisCreatedManagedWorkshopIds -Instance $Instance -WorkshopItemIds ([string[]]$managed))
                    Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Managed workshop manifest updated after remove. InstanceId={0}; RemovedWorkshopId={1}; RemainingCount={2}" -f ([string]$Instance.Id), $idFromName, $savedManaged.Count)
                }
                else {
                    Write-UGSMGameMisCreatedLog -Level 'DEBUG' -Message ("Removed MisCreated mod folder was not a managed workshop folder. InstanceId={0}; ModName={1}" -f ([string]$Instance.Id), $name)
                }

                $null = Save-UGSMGameMisCreatedInstance -Instance $Instance
                & $refreshModsUi
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Remove mod completed from editor. InstanceId={0}; ModName={1}" -f ([string]$Instance.Id), $name)
                if ($StatusLabel) { $StatusLabel.Text = ('Removed MisCreated mod {0}.' -f $name) }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'ERROR' -Message ("Remove mod failed from editor. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'MisCreated remove mod failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $syncMods = {
            try {
                Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Sync mods to runtime clicked from editor. InstanceId={0}" -f ([string]$Instance.Id))
                $result = Sync-UGSMGameMisCreatedProfileModsToInstall -Instance $Instance -ClearDestination
                & $refreshModsUi
                if ($StatusLabel) { $StatusLabel.Text = ('Synced {0} MisCreated mod item(s) to runtime.' -f @($result.Mods).Count) }
            }
            catch {
                Write-UGSMGameMisCreatedLog -Level 'ERROR' -Message ("Mod sync failed from editor. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
                if ($StatusLabel) { $StatusLabel.Text = 'MisCreated mod sync failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $refreshOnly = {
            & $refreshModsUi
            if ($StatusLabel) { $StatusLabel.Text = 'Refreshed MisCreated mod list.' }
        }.GetNewClosure()

        $btnSave.Add_Click($saveAction)
        $btnReload.Add_Click($reloadAction)
        if (Get-Variable -Name 'btnOpenCfg' -Scope Local -ErrorAction SilentlyContinue) {
            $btnOpenCfg.Add_Click($openHosting)
        }
        $btnAddWorkshop.Add_Click($addWorkshop)
        $btnDownloadAll.Add_Click($downloadAllManaged)
        $btnRemoveMod.Add_Click($removeSelected)
        $btnSyncRuntime.Add_Click($syncMods)
        $btnRefreshMods.Add_Click($refreshOnly)
        $btnOpenCfgMods.Add_Click($openHosting)

        & $refreshModsUi
        if ($StatusLabel) { $StatusLabel.Text = ('Loaded MisCreated profile editor. Detected {0} mod item(s).' -f $lstMods.Items.Count) }
        return $root
    }
    finally {
        $editorSw.Stop()
        if ($editorSw.ElapsedMilliseconds -ge 1000) {
            Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Instance editor creation was slow. InstanceId={0}; DurationMs={1}" -f ([string]$Instance.Id), [int]$editorSw.ElapsedMilliseconds)
        }
        else {
            Write-UGSMGameMisCreatedLog -Level 'INFO' -Message ("Instance editor creation finished. InstanceId={0}; DurationMs={1}" -f ([string]$Instance.Id), [int]$editorSw.ElapsedMilliseconds)
        }
        try {
            if ($HostPanel -and -not $HostPanel.IsDisposed) { $HostPanel.ResumeLayout() }
        }
        catch {
            Write-UGSMGameMisCreatedLog -Level 'WARN' -Message ("Instance editor ResumeLayout failed. InstanceId={0}" -f ([string]$Instance.Id)) -Exception $_.Exception
        }
    }
}
