# V Rising dedicated server module
# First pass: logging, lightweight profiles, JSON settings, start/stop, Discord. Mods intentionally unsupported.

function Write-UGSMGameVRisingLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )

    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerboseVRisingLogging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_VRISING)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'VRising' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'VRising' -Message $Message }
        return
    }

    if ($Exception) { Write-Warning ("[VRising] $Message :: $($Exception.Message)") }
    else { Write-Host "[VRising][$Level] $Message" }
}

function Get-UGSMGameVRisingInstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return ''
}

function Get-UGSMGameVRisingMetadata {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Id                       = 'VRising'
        Name                     = 'V Rising'
        Category                 = 'Survival'
        Description              = 'V Rising dedicated server integration.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 90
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $true
        SupportsInstall          = $true
        SupportsUpdate           = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $false
        SupportsWorkshop         = $false
        SupportsRcon             = $true
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '1829350'
        SteamStoreAppId          = '1604030'
        ServerExecutable         = 'VRisingServer.exe'
        ServerExecutableRelative = 'VRisingServer.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'Settings'
        SaveRootRelative         = 'Saves'
        LogRootRelative          = 'Logs'
        RequiredFiles            = @('VRisingServer.exe')
        InstallMarkers           = @('VRisingServer.exe')
        PortSchema               = @(
            @{ Name = 'GamePort';  Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 }
            @{ Name = 'RconPort';  Protocol = 'TCP'; PreferredStart = 25575 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $false
            UsesJsonFiles         = $true
            UsesXmlFiles          = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $false
            UsesFolderCopyMods    = $false
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $false
        }
        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'V Rising uses ServerHostSettings.json and ServerGameSettings.json under the persistent Settings folder.',
                'UGSM uses -persistentDataPath so each profile has isolated settings and saves.',
                'Steam Workshop mod support is intentionally disabled in this pass.'
            )
        }
    }
}

function Get-UGSMGameVRisingAppDataRoot {
    [CmdletBinding()]
    param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { return [string](Get-UGSMAppDataRoot) }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameVRisingProfileBaseRoot {
    [CmdletBinding()]
    param()
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) {
        return [string]$settings.ProfileBaseRoot
    }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'VRising' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) }
    }
    return (Join-Path (Get-UGSMGameVRisingAppDataRoot) 'Profiles')
}

function Get-UGSMGameVRisingProfileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    foreach ($name in @('Name','Id','ProfileName')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return 'VRisingServer'
}

function Get-UGSMGameVRisingProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Join-Path (Get-UGSMGameVRisingProfileBaseRoot) 'VRising') $ProfileName)
}

function Get-UGSMGameVRisingInstallPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$InstallPath)

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    function Add-VRisingInstallCandidate {
        param([AllowNull()][string]$PathValue)
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return }

        $raw = [string]$PathValue
        $suffixes = @(
            '',
            'VRising',
            'VRisingDedicatedServer',
            'V Rising Dedicated Server',
            'steamapps\common\VRising',
            'steamapps\common\VRisingDedicatedServer',
            'steamapps\common\V Rising Dedicated Server',
            'common\VRising',
            'common\VRisingDedicatedServer',
            'common\V Rising Dedicated Server'
        )

        foreach ($suffix in $suffixes) {
            $candidate = if ([string]::IsNullOrWhiteSpace($suffix)) { $raw } else { Join-Path $raw $suffix }
            try { $full = [System.IO.Path]::GetFullPath($candidate) } catch { $full = $candidate }
            $key = $full.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$candidatePaths.Add($full)
            }
        }
    }

    Add-VRisingInstallCandidate $InstallPath

    if ($Instance -and $Instance.PSObject.Properties['InstallPath']) {
        Add-VRisingInstallCandidate ([string]$Instance.InstallPath)
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    if ($settings) {
        foreach ($propName in @('InstallPath','InstallRoot','SteamLibraryRoot','SteamRoot','SteamCmdRoot','SteamInstallRoot','SteamPath','SteamCmdPath')) {
            if ($settings.PSObject.Properties[$propName]) {
                Add-VRisingInstallCandidate ([string]$settings.$propName)
            }
        }
    }


    foreach ($candidate in @($candidatePaths.ToArray())) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        $directExe = Join-Path $candidate 'VRisingServer.exe'
        if (Test-Path -LiteralPath $directExe -PathType Leaf) { return [string]$candidate }

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            try {
                $exe = Get-ChildItem -LiteralPath $candidate -Filter 'VRisingServer.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) { return [string](Split-Path -Parent $exe.FullName) }
            } catch {
                Write-UGSMGameVRisingLog -Level 'DEBUG' -Message ("V Rising install path scan skipped a candidate. Candidate=$candidate") -Exception $_.Exception
            }
        }
    }

    # Portable build rule: never return a hardcoded machine path when the game is not installed.
    # The installer will use the configured SteamCMD/common folder. The Games page should simply
    # show Install until real binaries exist.
    return ''
}


function Resolve-UGSMGameVRisingServerExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallPath)

    if ([string]::IsNullOrWhiteSpace($InstallPath)) { return '' }

    foreach ($exeName in @('VRisingServer.exe','VRisingDedicatedServer.exe','VRising.exe')) {
        $direct = Join-Path $InstallPath $exeName
        if (Test-Path -LiteralPath $direct) { return [string]$direct }
    }

    try {
        foreach ($exeName in @('VRisingServer.exe','VRisingDedicatedServer.exe','VRising.exe')) {
            $match = Get-ChildItem -LiteralPath $InstallPath -Filter $exeName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { return [string]$match.FullName }
        }
    } catch {
        Write-UGSMGameVRisingLog -Level 'WARN' -Message ("Failed while searching for V Rising server executable. InstallPath=$InstallPath") -Exception $_.Exception
    }

    return (Join-Path $InstallPath 'VRisingServer.exe')
}


function Get-UGSMGameVRisingInstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath, [object]$Instance)

    $InstallPath = Get-UGSMGameVRisingInstallPath -Instance $Instance -InstallPath $InstallPath
    $meta = Get-UGSMGameVRisingMetadata

    $serverExe = ''
    $configRoot = ''
    $saveRoot = ''
    $logRoot = ''

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
        $serverExe = Resolve-UGSMGameVRisingServerExecutablePath -InstallPath $InstallPath
        $configRoot = Join-Path $InstallPath 'VRisingServer_Data\StreamingAssets\Settings'
        $saveRoot = Join-Path $InstallPath 'Saves'
        $logRoot = Join-Path $InstallPath 'Logs'
    }

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = $serverExe
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = $configRoot
        SaveRootPath         = $saveRoot
        LogRootPath          = $logRoot
    }
}

function Get-UGSMGameVRisingProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profileName = Get-UGSMGameVRisingProfileName -Instance $Instance
    $profileRoot = if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { [string]$Instance.ProfilePath } else { Get-UGSMGameVRisingProfileRoot -ProfileName $profileName }
    $settingsRoot = Join-Path $profileRoot 'Settings'
    $saveRoot = Join-Path $profileRoot 'Saves'
    $logRoot = Join-Path $profileRoot 'Logs'
    $hostSettingsPath = Join-Path $settingsRoot 'ServerHostSettings.json'
    $gameSettingsPath = Join-Path $settingsRoot 'ServerGameSettings.json'
    $centralLogRoot = ''

    return [pscustomobject]@{
        ProfileName      = $profileName
        ProfileRoot      = $profileRoot
        SettingsRoot     = $settingsRoot
        SaveRoot         = $saveRoot
        LogRoot          = $logRoot
        HostSettingsPath = $hostSettingsPath
        GameSettingsPath = $gameSettingsPath
        CentralLogRoot   = $centralLogRoot
    }
}

function Get-UGSMGameVRisingAssignedPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [int]$Default
    )

    if ($Instance.PSObject.Properties[$Name]) { $v = $Instance.$Name; if ($v -as [int]) { return [int]$v } }
    if ($Instance.PSObject.Properties['Ports'] -and $null -ne $Instance.Ports) {
        $ports = $Instance.Ports
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) { $v = $ports[$Name]; if ($v -as [int]) { return [int]$v } }
        if ($ports.PSObject.Properties[$Name]) { $v = $ports.$Name; if ($v -as [int]) { return [int]$v } }
        foreach ($entry in @($ports)) {
            if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) {
                $v = $entry.Port; if ($v -as [int]) { return [int]$v }
            }
        }
    }

    $instanceId = Get-UGSMGameVRisingInstanceId -Instance $Instance
    if (Get-Command -Name Get-UGSMPortAssignments -ErrorAction SilentlyContinue) {
        try {
            $assignments = @(Get-UGSMPortAssignments)
            foreach ($assignment in $assignments) {
                if ($assignment -and $assignment.PSObject.Properties['InstanceId'] -and [string]$assignment.InstanceId -eq $instanceId) {
                    if ($assignment.PSObject.Properties['Ports'] -and $assignment.Ports -and $assignment.Ports.PSObject.Properties[$Name]) {
                        $v = $assignment.Ports.$Name; if ($v -as [int]) { return [int]$v }
                    }
                }
            }
        } catch {}
    }
    return $Default
}

function ConvertTo-UGSMGameVRisingArgumentString {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Arguments)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) { continue }
        $text = [string]$arg
        if ($text.Length -eq 0) { continue }
        if ($text -match '[\s"`]') { [void]$parts.Add('"' + ($text -replace '"','\"') + '"') }
        else { [void]$parts.Add($text) }
    }
    return ($parts -join ' ')
}

function Read-UGSMGameVRisingJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Get-Command -Name Read-UGSMGameJsonFile -ErrorAction SilentlyContinue) {
            return (Read-UGSMGameJsonFile -Path $Path -DefaultValue $null)
        }
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-UGSMGameVRisingLog -Level 'WARN' -Message ("Failed to read JSON file. Path=$Path") -Exception $_.Exception
        return $null
    }
}

function Save-UGSMGameVRisingJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)
    if (Get-Command -Name Write-UGSMGameJsonFile -ErrorAction SilentlyContinue) {
        Write-UGSMGameJsonFile -Path $Path -Value $Value -Depth 32
        return
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-UGSMGameVRisingDefaultHostSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profileName = Get-UGSMGameVRisingProfileName -Instance $Instance
    return [ordered]@{
        Name                = $profileName
        Description         = 'UGSM V Rising server'
        Port                = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'GamePort' -Default 27015
        QueryPort           = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'QueryPort' -Default 27016
        Address             = '0.0.0.0'
        HideIPAddress       = $false
        MaxConnectedUsers   = 40
        MaxConnectedAdmins  = 4
        ServerFps           = 30
        LowerFPSWhenEmpty   = $true
        LowerFPSWhenEmptyValue = 5
        Password            = ''
        Secure              = $true
        ListOnEOS           = $true
        ListOnSteam         = $true
        SaveName            = $profileName
        GameSettingsPreset  = 'StandardPvE'
        Rcon                = [ordered]@{
            Enabled = $false
            Password = ''
            Port = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575
            BindAddress = '127.0.0.1'
        }
    }
}

function Get-UGSMGameVRisingDefaultGameSettings {
    [CmdletBinding()]
    param()
    return [ordered]@{
        GameModeType = 'PvE'
        CastleDamageMode = 'Never'
        SiegeWeaponHealth = 'Normal'
        PlayerDamageMode = 'Always'
        PvPProtectionMode = 'Medium'
        DeathContainerPermission = 'Anyone'
        RelicSpawnType = 'Unique'
        CanLootEnemyContainers = $false
        BloodBoundEquipment = $true
        TeleportBoundItems = $true
        AllowGlobalChat = $true
        AllWaypointsUnlocked = $false
        FreeCastleRaid = $false
        FreeCastleClaim = $false
        FreeCastleDestroy = $false
        InactivityKillEnabled = $true
        InactivityKillTimeMin = 3600
        InactivityKillTimeMax = 604800
        ClanSize = 4
        BloodDrainModifier = 1.0
        DurabilityDrainModifier = 1.0
        GarlicAreaStrengthModifier = 1.0
        HolyAreaStrengthModifier = 1.0
        SilverStrengthModifier = 1.0
        SunDamageModifier = 1.0
        CastleDecayRateModifier = 1.0
        CastleBloodEssenceDrainModifier = 1.0
        CastleSiegeTimer = 420
        CastleUnderAttackTimer = 60
        AnnounceSiegeWeaponSpawn = $true
        ShowSiegeWeaponMapIcon = $true
        BuildCostModifier = 1.0
        RecipeCostModifier = 1.0
        CraftRateModifier = 1.0
        ResearchCostModifier = 1.0
        RefinementCostModifier = 1.0
        RefinementRateModifier = 1.0
        ResearchTimeModifier = 1.0
        DismantleResourceModifier = 0.75
        ServantConvertRateModifier = 1.0
        InventoryStacksModifier = 1.0
        DropTableModifier_General = 1.0
        DropTableModifier_Missions = 1.0
        MaterialYieldModifier_Global = 1.0
        BloodEssenceYieldModifier = 1.0
        JournalVBloodSourceUnitMaxDistance = 25.0
        PvPVampireRespawnModifier = 1.0
    }
}

function Merge-UGSMGameVRisingDefaults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Current, [Parameter(Mandatory)][hashtable]$Defaults)
    $obj = [ordered]@{}
    foreach ($k in $Defaults.Keys) { $obj[$k] = $Defaults[$k] }
    if ($Current) {
        foreach ($p in $Current.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    }
    return [pscustomobject]$obj
}

function Get-UGSMGameVRisingSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance
    $hostConfig = Read-UGSMGameVRisingJsonFile -Path $paths.HostSettingsPath
    $game = Read-UGSMGameVRisingJsonFile -Path $paths.GameSettingsPath
    if (-not $hostConfig) { $hostConfig = [pscustomobject](Get-UGSMGameVRisingDefaultHostSettings -Instance $Instance) }
    else { $hostConfig = Merge-UGSMGameVRisingDefaults -Current $hostConfig -Defaults (Get-UGSMGameVRisingDefaultHostSettings -Instance $Instance) }
    if (-not $game) { $game = [pscustomobject](Get-UGSMGameVRisingDefaultGameSettings) }
    else { $game = Merge-UGSMGameVRisingDefaults -Current $game -Defaults (Get-UGSMGameVRisingDefaultGameSettings) }

    $hostConfig.Port = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'GamePort' -Default ([int]$hostConfig.Port)
    $hostConfig.QueryPort = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'QueryPort' -Default ([int]$hostConfig.QueryPort)
    if (-not $hostConfig.PSObject.Properties['Rcon'] -or -not $hostConfig.Rcon) {
        $hostConfig | Add-Member -NotePropertyName Rcon -NotePropertyValue ([pscustomobject]@{ Enabled=$false; Password=''; Port=(Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575); BindAddress='127.0.0.1' }) -Force
    } else {
        try { $hostConfig.Rcon.Port = Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'RconPort' -Default ([int]$hostConfig.Rcon.Port) } catch {}
    }

    return [pscustomobject]@{ Host=$hostConfig; Game=$game; Paths=$paths }
}

function Save-UGSMGameVRisingSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$HostSettings,
        [Parameter(Mandatory)][object]$GameSettings
    )
    $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance
    foreach ($dir in @($paths.ProfileRoot,$paths.SettingsRoot,$paths.SaveRoot,$paths.LogRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    Save-UGSMGameVRisingJsonFile -Path $paths.HostSettingsPath -Value $HostSettings
    Save-UGSMGameVRisingJsonFile -Path $paths.GameSettingsPath -Value $GameSettings
}

function Test-UGSMGameVRisingInstall {
    [CmdletBinding()]
    param([string]$InstallPath, [object]$Instance)

    $definition = Get-UGSMGameVRisingInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $exePath = [string]$definition.ServerExecutablePath
    $isInstalled = (-not [string]::IsNullOrWhiteSpace($exePath) -and (Test-Path -LiteralPath $exePath))

    if (-not $isInstalled) {
        # Missing binaries are normal for an uninstalled game card.  Keep this quiet
        # unless verbose game logging is enabled.
        Write-UGSMGameVRisingLog -Level 'DEBUG' -Message ("V Rising is not installed. InstallPath=$($definition.InstallPath); ExpectedExe=$exePath")
        return [pscustomobject]@{
            GameId       = 'VRising'
            InstallPath  = [string]$definition.InstallPath
            ExePath      = $exePath
            IsInstalled  = $false
            IsValid      = $false
            NeedsRepair  = $false
            MissingItems = @('VRisingServer.exe')
        }
    }

    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("V Rising install validation succeeded. InstallPath=$($definition.InstallPath); Exe=$exePath")
    return [pscustomobject]@{
        GameId       = 'VRising'
        InstallPath  = [string]$definition.InstallPath
        ExePath      = $exePath
        IsInstalled  = $true
        IsValid      = $true
        NeedsRepair  = $false
        MissingItems = @()
    }
}


function Test-UGSMGameVRisingInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance
    return (Test-Path -LiteralPath $paths.HostSettingsPath)
}

function Ensure-UGSMGameVRisingTemplate {
    [CmdletBinding()]
    param([object]$Instance, [int]$BootstrapSeconds = 0, [switch]$Force, [switch]$ForceRefresh)
    if (-not $Instance) { return $null }
    return Initialize-UGSMGameVRisingProfile -Instance $Instance -BootstrapSeconds $BootstrapSeconds -Force:($Force -or $ForceRefresh)
}

function Initialize-UGSMGameVRisingProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [int]$BootstrapSeconds = 0, [switch]$Force)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = Get-UGSMGameVRisingInstanceId -Instance $Instance
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Profile initialization requested. InstanceId=$instanceId; Force=$Force")
    $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance
    foreach ($dir in @($paths.ProfileRoot,$paths.SettingsRoot,$paths.SaveRoot,$paths.LogRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $settings = Get-UGSMGameVRisingSettings -Instance $Instance
    if ($Force -or -not (Test-Path -LiteralPath $paths.HostSettingsPath)) {
        Save-UGSMGameVRisingJsonFile -Path $paths.HostSettingsPath -Value $settings.Host
    }
    if ($Force -or -not (Test-Path -LiteralPath $paths.GameSettingsPath)) {
        Save-UGSMGameVRisingJsonFile -Path $paths.GameSettingsPath -Value $settings.Game
    }

    $sw.Stop()
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Profile initialized. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds); SettingsRoot=$($paths.SettingsRoot)")
    return [pscustomobject]@{ Success=$true; ProfileRoot=$paths.ProfileRoot; SettingsRoot=$paths.SettingsRoot; SaveRoot=$paths.SaveRoot; LogRoot=$paths.LogRoot }
}

function Start-UGSMGameVRisingInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)

    $instanceId = Get-UGSMGameVRisingInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")
    try {
        $definition = Get-UGSMGameVRisingInstallDefinition -InstallPath $InstallPath -Instance $Instance
        if (-not (Test-Path -LiteralPath $definition.ServerExecutablePath)) { throw "VRisingServer.exe not found at '$($definition.ServerExecutablePath)'." }
        $init = Initialize-UGSMGameVRisingProfile -Instance $Instance
        $settings = Get-UGSMGameVRisingSettings -Instance $Instance
        $paths = $settings.Paths
        $hostConfig = $settings.Host

        $args = @(
            '-persistentDataPath', $paths.ProfileRoot,
            '-serverName', [string]$hostConfig.Name,
            '-saveName', [string]$hostConfig.SaveName,
            '-gamePort', [string]$hostConfig.Port,
            '-queryPort', [string]$hostConfig.QueryPort
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$hostConfig.Password)) { $args += @('-password', [string]$hostConfig.Password) }
        if ($hostConfig.PSObject.Properties['Description'] -and -not [string]::IsNullOrWhiteSpace([string]$hostConfig.Description)) { $args += @('-description', [string]$hostConfig.Description) }
        if ($hostConfig.PSObject.Properties['Secure']) { $args += @('-secure', ([string]$hostConfig.Secure).ToLowerInvariant()) }
        if ($hostConfig.PSObject.Properties['ListOnSteam']) { $args += @('-listOnSteam', ([string]$hostConfig.ListOnSteam).ToLowerInvariant()) }
        if ($hostConfig.PSObject.Properties['ListOnEOS']) { $args += @('-listOnEOS', ([string]$hostConfig.ListOnEOS).ToLowerInvariant()) }

        $argText = ConvertTo-UGSMGameVRisingArgumentString -Arguments $args
        $logArgText = $argText
        if (-not [string]::IsNullOrWhiteSpace([string]$hostConfig.Password)) { $logArgText = $logArgText -replace [regex]::Escape([string]$hostConfig.Password), '<redacted>' }
        Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Launching process. InstanceId=$instanceId; Exe=$($definition.ServerExecutablePath); Args=$logArgText")

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $definition.ServerExecutablePath
        $psi.WorkingDirectory = Split-Path -Parent $definition.ServerExecutablePath
        $psi.Arguments = $argText
        $psi.UseShellExecute = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) { throw 'Process did not start.' }
        Start-Sleep -Milliseconds 1200
        try { if ($proc.HasExited) { throw "V Rising server exited immediately with code $($proc.ExitCode)." } } catch { throw }

        $sw.Stop()
        Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$($proc.Id); DurationMs=$($sw.ElapsedMilliseconds)")
        if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
            try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameVRisingLog -Level 'WARN' -Message ("Discord start notification failed. InstanceId=$instanceId") -Exception $_.Exception }
        }
        return [pscustomobject]@{ Success=$true; Pid=$proc.Id; ProcessId=$proc.Id; Status='Running'; Message='V Rising server started.' }
    } catch {
        $sw.Stop()
        Write-UGSMGameVRisingLog -Level 'ERROR' -Message ("Start failed. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)") -Exception $_.Exception
        return [pscustomobject]@{ Success=$false; Status='Stopped'; Message=$_.Exception.Message }
    }
}


function Read-UGSMGameVRisingRconBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][byte[]]$Buffer,
        [int]$Offset = 0,
        [Parameter(Mandatory)][int]$Count
    )
    $readTotal = 0
    while ($readTotal -lt $Count) {
        $read = $Stream.Read($Buffer, ($Offset + $readTotal), ($Count - $readTotal))
        if ($read -le 0) { throw 'RCON connection closed while reading.' }
        $readTotal += $read
    }
}

function Send-UGSMGameVRisingRconPacket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [int]$RequestId,
        [int]$Type,
        [AllowNull()][string]$Body
    )
    if ($null -eq $Body) { $Body = '' }
    $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $size = 4 + 4 + $bodyBytes.Length + 2
    $bytes = New-Object byte[] (4 + $size)
    [BitConverter]::GetBytes([int]$size).CopyTo($bytes,0)
    [BitConverter]::GetBytes([int]$RequestId).CopyTo($bytes,4)
    [BitConverter]::GetBytes([int]$Type).CopyTo($bytes,8)
    [Array]::Copy($bodyBytes,0,$bytes,12,$bodyBytes.Length)
    $bytes[$bytes.Length - 2] = 0
    $bytes[$bytes.Length - 1] = 0
    $Stream.Write($bytes,0,$bytes.Length)
    $Stream.Flush()
}

function Receive-UGSMGameVRisingRconPacket {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)
    $lenBytes = New-Object byte[] 4
    Read-UGSMGameVRisingRconBytes -Stream $Stream -Buffer $lenBytes -Count 4
    $size = [BitConverter]::ToInt32($lenBytes,0)
    if ($size -lt 10 -or $size -gt 1048576) { throw "Invalid RCON packet size: $size" }
    $payload = New-Object byte[] $size
    Read-UGSMGameVRisingRconBytes -Stream $Stream -Buffer $payload -Count $size
    $requestId = [BitConverter]::ToInt32($payload,0)
    $type = [BitConverter]::ToInt32($payload,4)
    $bodyLen = [Math]::Max(0, $size - 10)
    $body = if ($bodyLen -gt 0) { [System.Text.Encoding]::ASCII.GetString($payload,8,$bodyLen) } else { '' }
    return [pscustomobject]@{ RequestId=$requestId; Type=$type; Body=$body }
}

function Invoke-UGSMGameVRisingRconCommand {
    [CmdletBinding()]
    param(
        [string]$HostName = '127.0.0.1',
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutMilliseconds = 5000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { throw 'RCON connection timed out.' }
        $client.EndConnect($iar)
        $client.ReceiveTimeout = $TimeoutMilliseconds
        $client.SendTimeout = $TimeoutMilliseconds
        $stream = $client.GetStream()
        Send-UGSMGameVRisingRconPacket -Stream $stream -RequestId 1001 -Type 3 -Body $Password
        $authPacket = Receive-UGSMGameVRisingRconPacket -Stream $stream
        if ($authPacket.RequestId -eq -1) { throw 'RCON authentication failed.' }
        Send-UGSMGameVRisingRconPacket -Stream $stream -RequestId 1002 -Type 2 -Body $Command
        $response = Receive-UGSMGameVRisingRconPacket -Stream $stream
        return [pscustomobject]@{ Success=$true; Response=$response.Body }
    }
    finally {
        try { $client.Close() } catch { }
    }
}

function Invoke-UGSMGameVRisingGracefulShutdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [int]$DelaySeconds = 10)

    $settings = Get-UGSMGameVRisingSettings -Instance $Instance
    $hostConfig = $settings.Host
    if (-not $hostConfig -or -not $hostConfig.PSObject.Properties['Rcon'] -or -not $hostConfig.Rcon) { return [pscustomobject]@{ Success=$false; Reason='RCON settings missing.' } }
    if (-not [bool]$hostConfig.Rcon.Enabled) { return [pscustomobject]@{ Success=$false; Reason='RCON disabled.' } }
    if ([string]::IsNullOrWhiteSpace([string]$hostConfig.Rcon.Password)) { return [pscustomobject]@{ Success=$false; Reason='RCON password blank.' } }

    $bindAddress = [string]$hostConfig.Rcon.BindAddress
    if ([string]::IsNullOrWhiteSpace($bindAddress) -or $bindAddress -eq '*') { $bindAddress = '127.0.0.1' }
    $port = [int]$hostConfig.Rcon.Port
    $safeDelay = [Math]::Max(1, [Math]::Min(120, $DelaySeconds))
    $command = ('shutdown {0} UGSM server shutdown requested.' -f $safeDelay)
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Graceful shutdown requested through RCON. InstanceId=$(Get-UGSMGameVRisingInstanceId -Instance $Instance); RconPort=$port; DelaySeconds=$safeDelay")
    return (Invoke-UGSMGameVRisingRconCommand -HostName $bindAddress -Port $port -Password ([string]$hostConfig.Rcon.Password) -Command $command)
}

function Stop-UGSMGameVRisingInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [int]$ProcessId)

    $instanceId = Get-UGSMGameVRisingInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId; Pid=$ProcessId")
    $stopped = $false
    try {
        $gracefulSent = $false
        try {
            $graceful = Invoke-UGSMGameVRisingGracefulShutdown -Instance $Instance -DelaySeconds 10
            if ($graceful -and $graceful.Success) {
                $gracefulSent = $true
                for ($i = 0; $i -lt 20; $i++) {
                    Start-Sleep -Milliseconds 750
                    if ($ProcessId -gt 0) {
                        $procCheck = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                        if (-not $procCheck) { $stopped = $true; break }
                    }
                    else {
                        $running = @(Get-Process -Name 'VRisingServer' -ErrorAction SilentlyContinue)
                        if ($running.Count -eq 0) { $stopped = $true; break }
                    }
                }
            }
            elseif ($graceful -and $graceful.PSObject.Properties['Reason']) {
                Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Graceful shutdown skipped. InstanceId=$instanceId; Reason=$($graceful.Reason)")
            }
        }
        catch {
            Write-UGSMGameVRisingLog -Level 'WARN' -Message ("Graceful shutdown failed; falling back to process stop. InstanceId=$instanceId") -Exception $_.Exception
        }

        if (-not $stopped) {
            if ($ProcessId -gt 0) {
                $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($proc) {
                    if (-not $gracefulSent) { try { $null = $proc.CloseMainWindow(); Start-Sleep -Seconds 5 } catch {} }
                    $proc.Refresh()
                    if (-not $proc.HasExited) { Stop-Process -Id $ProcessId -Force -ErrorAction Stop }
                    $stopped = $true
                }
            }
        }
        if (-not $stopped) {
            $procs = @(Get-Process -Name 'VRisingServer' -ErrorAction SilentlyContinue)
            foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped = $true } catch {} }
        }
        $sw.Stop()
        Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Stop completed. InstanceId=$instanceId; Stopped=$stopped; GracefulSent=$gracefulSent; DurationMs=$($sw.ElapsedMilliseconds)")
        if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
            try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameVRisingLog -Level 'WARN' -Message ("Discord stop notification failed. InstanceId=$instanceId") -Exception $_.Exception }
        }
        return [pscustomobject]@{ Success=$true; Stopped=$stopped; Status='Stopped'; Message='V Rising server stopped.' }
    } catch {
        $sw.Stop()
        Write-UGSMGameVRisingLog -Level 'ERROR' -Message ("Stop failed. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)") -Exception $_.Exception
        return [pscustomobject]@{ Success=$false; Stopped=$false; Status='Unknown'; Message=$_.Exception.Message }
    }
}

function Get-UGSMGameVRisingColor {
    [CmdletBinding()]
    param([AllowNull()][object]$Theme, [Parameter(Mandatory)][string]$Name, [System.Drawing.Color]$Fallback)
    try {
        if ($Theme -and $Theme.PSObject.Properties[$Name] -and $Theme.$Name -is [System.Drawing.Color]) { return $Theme.$Name }
        if ($Theme -and $Theme.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string]$Theme.$Name)) { return [System.Drawing.ColorTranslator]::FromHtml([string]$Theme.$Name) }
    } catch {}
    $globalName = switch ($Name) {
        'Background' { 'UGSM_ColorBackground' }
        'Surface' { 'UGSM_ColorSurface' }
        'Input' { 'UGSM_ColorInputBackground' }
        'Text' { 'UGSM_ColorText' }
        'Muted' { 'UGSM_ColorMutedText' }
        'Accent' { 'UGSM_ColorAccent' }
        'Button' { 'UGSM_ColorNeutral' }
        default { $null }
    }
    if ($globalName) {
        try {
            $value = Get-Variable -Name $globalName -Scope Global -ErrorAction SilentlyContinue
            if ($value -and $value.Value -is [System.Drawing.Color]) { return $value.Value }
            if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value.Value)) { return [System.Drawing.ColorTranslator]::FromHtml([string]$value.Value) }
        } catch {}
    }
    return $Fallback
}


function Update-UGSMGameVRisingPanelScrollSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$Panel,
        [int]$Bottom
    )
    try { $Panel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ([Math]::Max(($Bottom + 90), 400))) } catch {}
}

function Get-UGSMGameVRisingPrettyLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $label = $Name -replace '_',' '
    $label = $label -replace '([a-z0-9])([A-Z])','$1 $2'
    $label = $label -replace '\bPv P\b','PvP'
    $label = $label -replace '\bP V P\b','PvP'
    $label = $label -replace '\bV Blood\b','VBlood'
    $label = $label -replace '\bRcon\b','RCON'
    $label = $label -replace '\bApi\b','API'
    $label = $label -replace '\bEos\b','EOS'
    return $label.Trim()
}

function Get-UGSMGameVRisingKnownClamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][object]$CurrentValue)

    $clamps = @{
        'ClanSize' = @{ Min = 1; Max = 50; Decimals = 0 }
        'InventoryStacksModifier' = @{ Min = 0.0001; Max = 3; Decimals = 4 }
        'CastleUnderAttackTimer' = @{ Min = 0; Max = 65504; Decimals = 0 }
        'CastleBloodEssenceDrainModifier' = @{ Min = 0.01; Max = 100; Decimals = 2 }
        'RefinementRateModifier' = @{ Min = 0.01; Max = 100; Decimals = 2 }
        'CraftRateModifier' = @{ Min = 0.01; Max = 100; Decimals = 2 }
        'ServantConvertRateModifier' = @{ Min = 0.01; Max = 100; Decimals = 2 }
        'DropTableModifier_General' = @{ Min = 0; Max = 100; Decimals = 2 }
        'DropTableModifier_Missions' = @{ Min = 0; Max = 100; Decimals = 2 }
        'MaterialYieldModifier_Global' = @{ Min = 0; Max = 100; Decimals = 2 }
        'BloodEssenceYieldModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'BloodDrainModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'DurabilityDrainModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'GarlicAreaStrengthModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'HolyAreaStrengthModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'SilverStrengthModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'SunDamageModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'JournalVBloodSourceUnitMaxDistance' = @{ Min = 0; Max = 100; Decimals = 2 }
        'PvPVampireRespawnModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'CastleDecayRateModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'BuildCostModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'RecipeCostModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'ResearchCostModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'RefinementCostModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
        'ResearchTimeModifier' = @{ Min = 0; Max = 100; Decimals = 2 }
    }

    if ($clamps.ContainsKey($Name)) { return $clamps[$Name] }

    if ($Name -in @('Port','QueryPort') -or $Name -match 'Port$') { return @{ Min = 1; Max = 65535; Decimals = 0 } }
    if ($Name -match 'Hour$') { return @{ Min = 0; Max = 23; Decimals = 0 } }
    if ($Name -match 'Minute$') { return @{ Min = 0; Max = 59; Decimals = 0 } }
    if ($Name -match 'Fps$' -or $Name -eq 'ServerFps') { return @{ Min = 1; Max = 240; Decimals = 0 } }
    if ($Name -match 'MaxConnected') { return @{ Min = 1; Max = 200; Decimals = 0 } }
    if ($Name -match 'Count$|Limit$|Level$|Slots$|Workers$|Tries$|Connections$') { return @{ Min = 0; Max = 1000000; Decimals = 0 } }

    if ($CurrentValue -is [int] -or $CurrentValue -is [long]) { return @{ Min = 0; Max = 1000000000; Decimals = 0 } }
    return @{ Min = -1000000000; Max = 1000000000; Decimals = 2 }
}

function Get-UGSMGameVRisingPresetOptions {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $options = New-Object System.Collections.Generic.List[string]
    [void]$options.Add('')

    $installPath = ''
    try { if ($Instance -and $Instance.PSObject.Properties['InstallPath']) { $installPath = [string]$Instance.InstallPath } } catch {}
    $installPath = Get-UGSMGameVRisingInstallPath -Instance $Instance -InstallPath $installPath

    $presetRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($installPath)) {
        $presetRoots += (Join-Path $installPath 'VRisingServer_Data\StreamingAssets\Settings\GameSettingPresets')
        $presetRoots += (Join-Path $installPath 'VRisingServer_Data\StreamingAssets\GameSettingPresets')
    }

    foreach ($root in $presetRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not $options.Contains($name)) { [void]$options.Add($name) }
            }
        }
    }

    foreach ($fallback in @('StandardPvE','StandardPvP','Level30PvE','Level30PvP','Level50PvE','Level50PvP','Level70PvE','Level70PvP')) {
        if (-not $options.Contains($fallback)) { [void]$options.Add($fallback) }
    }

    return @($options.ToArray())
}

function Get-UGSMGameVRisingOptionsForField {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$FullPath, [AllowNull()][object]$Instance)

    switch ($Name) {
        'GameSettingsPreset' { return (Get-UGSMGameVRisingPresetOptions -Instance $Instance) }
        'GameDifficultyPreset' { return @('', 'Relaxed', 'Normal', 'Hard', 'Brutal') }
        'GameModeType' { return @('PvE', 'PvP') }
        'GameDifficulty' { return @('Relaxed', 'Normal', 'Hard', 'Brutal') }
        'CastleDamageMode' { return @('Never', 'Always', 'TimeRestricted') }
        'PlayerDamageMode' { return @('Always', 'TimeRestricted') }
        'SiegeWeaponHealth' { return @('VeryLow', 'Low', 'Normal', 'High', 'VeryHigh') }
        'CastleHeartDamageMode' { return @('CanBeDestroyedOnlyWhenDecaying', 'CanBeDestroyedByPlayers', 'CanBeSeizedOrDestroyedByPlayers') }
        'PvPProtectionMode' { return @('Disabled', 'VeryShort', 'Short', 'Medium', 'Long') }
        'DeathContainerPermission' { return @('Anyone', 'ClanMembersOnly', 'OnlySelf') }
        'RelicSpawnType' { return @('Unique', 'Plentiful') }
        'CastleHeartLimitType' { return @('User', 'Clan') }
        'TimeZone' { return @('Local', 'UTC', 'PST', 'EST', 'CET') }
        default { return @() }
    }
}

function Get-UGSMGameVRisingObjectProperties {
    [CmdletBinding()]
    param([AllowNull()][object]$Object)

    if ($null -eq $Object) { return @() }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $Object[$_] } })
    }
    return @($Object.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty','Property') })
}

function Get-UGSMGameVRisingJsonEditorEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][object]$RootObject,
        [string[]]$Path = @()
    )

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($prop in @(Get-UGSMGameVRisingObjectProperties -Object $RootObject)) {
        $name = [string]$prop.Name
        $value = $prop.Value
        $nextPath = @($Path + $name)
        $fullPath = ($nextPath -join '.')

        if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or $value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [single] -or $value -is [decimal]) {
            [void]$entries.Add([pscustomobject]@{ File = $File; Path = $nextPath; Name = $name; FullPath = $fullPath; Value = $value; Kind = 'Scalar' })
            continue
        }

        if ($value -is [System.Array] -or $value -is [System.Collections.IEnumerable] -and -not ($value -is [string]) -and -not ($value.PSObject.Properties.Count -gt 0 -and $value -isnot [System.Array])) {
            [void]$entries.Add([pscustomobject]@{ File = $File; Path = $nextPath; Name = $name; FullPath = $fullPath; Value = $value; Kind = 'Json' })
            continue
        }

        $childProps = @(Get-UGSMGameVRisingObjectProperties -Object $value)
        if ($childProps.Count -gt 0) {
            $childEntries = @(Get-UGSMGameVRisingJsonEditorEntries -File $File -RootObject $value -Path $nextPath)
            foreach ($entry in $childEntries) { [void]$entries.Add($entry) }
        }
        else {
            [void]$entries.Add([pscustomobject]@{ File = $File; Path = $nextPath; Name = $name; FullPath = $fullPath; Value = $value; Kind = 'Json' })
        }
    }

    return @($entries.ToArray())
}

function Set-UGSMGameVRisingJsonPathValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Root,
        [Parameter(Mandatory)][string[]]$Path,
        [AllowNull()][object]$Value
    )

    $current = $Root
    for ($i = 0; $i -lt ($Path.Count - 1); $i++) {
        $segment = [string]$Path[$i]
        if (-not $current.PSObject.Properties[$segment] -or $null -eq $current.$segment) {
            $current | Add-Member -NotePropertyName $segment -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $current = $current.$segment
    }

    $leaf = [string]$Path[-1]
    if ($current.PSObject.Properties[$leaf]) { $current.$leaf = $Value }
    else { $current | Add-Member -NotePropertyName $leaf -NotePropertyValue $Value -Force }
}


function Get-UGSMGameVRisingEditorSchema {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $actions = @{
        OpenHostSettings = {
            param($Instance, $Paths, $StatusLabel)
            try {
                if (-not (Test-Path -LiteralPath $Paths.HostSettingsPath -PathType Leaf)) { New-Item -ItemType File -Path $Paths.HostSettingsPath -Force | Out-Null }
                Invoke-Item -LiteralPath $Paths.HostSettingsPath
                if ($StatusLabel) { $StatusLabel.Text = 'Opened ServerHostSettings.json.' }
            } catch { if ($StatusLabel) { $StatusLabel.Text = 'Open failed: ' + $_.Exception.Message } }
        }
        OpenGameSettings = {
            param($Instance, $Paths, $StatusLabel)
            try {
                if (-not (Test-Path -LiteralPath $Paths.GameSettingsPath -PathType Leaf)) { New-Item -ItemType File -Path $Paths.GameSettingsPath -Force | Out-Null }
                Invoke-Item -LiteralPath $Paths.GameSettingsPath
                if ($StatusLabel) { $StatusLabel.Text = 'Opened ServerGameSettings.json.' }
            } catch { if ($StatusLabel) { $StatusLabel.Text = 'Open failed: ' + $_.Exception.Message } }
        }
    }

    return [pscustomobject]@{
        Version = 2
        Tabs = @(
            [pscustomobject]@{
                Title = 'Server'
                Description = 'V Rising host settings stored in ServerHostSettings.json.'
                Fields = @(
                    @{ Id='ServerName'; Type='Text'; File='ServerHostSettings.json'; JsonPath='Name'; Label='Server Name'; DefaultValue=(Get-UGSMGameVRisingProfileName -Instance $Instance); Hint='Name shown in the server browser.' }
                    @{ Id='Description'; Type='MultilineText'; File='ServerHostSettings.json'; JsonPath='Description'; Label='Description'; DefaultValue='UGSM V Rising server'; Hint='Short description shown in the server browser.' }
                    @{ Id='SaveName'; Type='Text'; File='ServerHostSettings.json'; JsonPath='SaveName'; Label='Save Name'; DefaultValue=(Get-UGSMGameVRisingProfileName -Instance $Instance); Hint='Save folder name below the V Rising Saves folder.' }
                    @{ Id='Address'; Type='Text'; File='ServerHostSettings.json'; JsonPath='Address'; Label='Bind Address'; DefaultValue='0.0.0.0'; Hint='Usually 0.0.0.0. Use a specific local IP only when needed.' }
                    @{ Id='HideIPAddress'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='HideIPAddress'; Label='Hide IP Address'; DefaultValue=$false; Hint='Hides the IP address in server listing metadata if supported.' }
                    @{ Id='Password'; Type='Password'; File='ServerHostSettings.json'; JsonPath='Password'; Label='Server Password'; DefaultValue=''; Secret=$true; Hint='Optional join password. Masked in the UI.' }
                    @{ Id='Secure'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='Secure'; Label='Secure'; DefaultValue=$true; Hint='Enable secure server mode.' }
                    @{ Id='ListOnEOS'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='ListOnEOS'; Label='List On EOS'; DefaultValue=$true; Hint='Show server through EOS listing.' }
                    @{ Id='ListOnSteam'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='ListOnSteam'; Label='List On Steam'; DefaultValue=$true; Hint='Show server through Steam listing.' }
                    @{ Id='MaxConnectedUsers'; Type='Number'; File='ServerHostSettings.json'; JsonPath='MaxConnectedUsers'; Label='Max Connected Users'; DefaultValue=40; Min=1; Max=200; Decimals=0; Hint='Maximum connected players.' }
                    @{ Id='MaxConnectedAdmins'; Type='Number'; File='ServerHostSettings.json'; JsonPath='MaxConnectedAdmins'; Label='Max Connected Admins'; DefaultValue=4; Min=0; Max=200; Decimals=0; Hint='Maximum connected admins.' }
                    @{ Id='ServerFps'; Type='Number'; File='ServerHostSettings.json'; JsonPath='ServerFps'; Label='Server FPS'; DefaultValue=30; Min=1; Max=240; Decimals=0; Hint='Server tick/FPS target.' }
                    @{ Id='LowerFPSWhenEmpty'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='LowerFPSWhenEmpty'; Label='Lower FPS When Empty'; DefaultValue=$true; Hint='Reduce server FPS when empty.' }
                    @{ Id='LowerFPSWhenEmptyValue'; Type='Number'; File='ServerHostSettings.json'; JsonPath='LowerFPSWhenEmptyValue'; Label='Empty Server FPS'; DefaultValue=5; Min=1; Max=240; Decimals=0; Hint='FPS target when no players are connected.' }
                )
            }
            [pscustomobject]@{
                Title = 'Network / RCON'
                Description = 'Ports and RCON settings. Ports should be unique across every UGSM instance.'
                Fields = @(
                    @{ Id='Port'; Type='Number'; File='ServerHostSettings.json'; JsonPath='Port'; Label='Game Port'; DefaultValue=(Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'GamePort' -Default 27015); Min=1; Max=65535; Decimals=0; Hint='Main UDP game port.' }
                    @{ Id='QueryPort'; Type='Number'; File='ServerHostSettings.json'; JsonPath='QueryPort'; Label='Query Port'; DefaultValue=(Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'QueryPort' -Default 27016); Min=1; Max=65535; Decimals=0; Hint='UDP query/listing port.' }
                    @{ Id='RconEnabled'; Type='Boolean'; File='ServerHostSettings.json'; JsonPath='Rcon.Enabled'; Label='RCON Enabled'; DefaultValue=$false; Hint='Enable RCON. Needed later for graceful stop commands.' }
                    @{ Id='RconPort'; Type='Number'; File='ServerHostSettings.json'; JsonPath='Rcon.Port'; Label='RCON Port'; DefaultValue=(Get-UGSMGameVRisingAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575); Min=1; Max=65535; Decimals=0; Hint='TCP RCON port.' }
                    @{ Id='RconPassword'; Type='Password'; File='ServerHostSettings.json'; JsonPath='Rcon.Password'; Label='RCON Password'; DefaultValue=''; Secret=$true; Hint='RCON password. Masked in the UI.' }
                    @{ Id='RconBindAddress'; Type='Text'; File='ServerHostSettings.json'; JsonPath='Rcon.BindAddress'; Label='RCON Bind Address'; DefaultValue='127.0.0.1'; Hint='Usually 127.0.0.1 for local-only RCON.' }
                )
            }
            [pscustomobject]@{
                Title = 'Game Settings'
                Description = 'Game mode and major gameplay settings stored in ServerGameSettings.json. Leave Game Settings Preset blank to use custom gameplay values.'
                Fields = @(
                    @{ Id='GameSettingsPreset'; Type='Dropdown'; File='ServerHostSettings.json'; JsonPath='GameSettingsPreset'; Label='Game Settings Preset'; DefaultValue=''; Options=(Get-UGSMGameVRisingPresetOptions -Instance $Instance); Hint='Blank/custom uses ServerGameSettings.json. Presets can override custom gameplay values.' }
                    @{ Id='GameDifficultyPreset'; Type='Dropdown'; File='ServerHostSettings.json'; JsonPath='GameDifficultyPreset'; Label='Game Difficulty Preset'; DefaultValue=''; Options=@('', 'Relaxed', 'Normal', 'Hard', 'Brutal'); Hint='Optional difficulty preset. Blank keeps custom values.' }
                    @{ Id='GameModeType'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='GameModeType'; Label='Game Mode Type'; DefaultValue='PvE'; Options=@('PvE','PvP'); Hint='PvE or PvP ruleset.' }
                    @{ Id='GameDifficulty'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='GameDifficulty'; Label='Game Difficulty'; DefaultValue='Normal'; Options=@('Relaxed','Normal','Hard','Brutal'); Hint='Gameplay difficulty when supported by the current version.' }
                    @{ Id='CastleDamageMode'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='CastleDamageMode'; Label='Castle Damage Mode'; DefaultValue='Never'; Options=@('Never','Always','TimeRestricted'); Hint='Castle damage rules.' }
                    @{ Id='PlayerDamageMode'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='PlayerDamageMode'; Label='Player Damage Mode'; DefaultValue='Always'; Options=@('Always','TimeRestricted'); Hint='Player damage rules.' }
                    @{ Id='PvPProtectionMode'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='PvPProtectionMode'; Label='PvP Protection Mode'; DefaultValue='Medium'; Options=@('Disabled','VeryShort','Short','Medium','Long'); Hint='New player PvP protection duration.' }
                    @{ Id='DeathContainerPermission'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='DeathContainerPermission'; Label='Death Container Permission'; DefaultValue='Anyone'; Options=@('Anyone','ClanMembersOnly','OnlySelf'); Hint='Who can loot death containers.' }
                    @{ Id='RelicSpawnType'; Type='Dropdown'; File='ServerGameSettings.json'; JsonPath='RelicSpawnType'; Label='Relic Spawn Type'; DefaultValue='Unique'; Options=@('Unique','Plentiful'); Hint='Relic spawn behavior.' }
                    @{ Id='ClanSize'; Type='Number'; File='ServerGameSettings.json'; JsonPath='ClanSize'; Label='Clan Size'; DefaultValue=4; Min=1; Max=50; Decimals=0; Hint='Server clamps this between 1 and 50.' }
                    @{ Id='AllowGlobalChat'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='AllowGlobalChat'; Label='Allow Global Chat'; DefaultValue=$true; Hint='Enable global chat.' }
                    @{ Id='BloodBoundEquipment'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='BloodBoundEquipment'; Label='Blood Bound Equipment'; DefaultValue=$true; Hint='Keep equipment after death when enabled.' }
                    @{ Id='TeleportBoundItems'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='TeleportBoundItems'; Label='Teleport Bound Items'; DefaultValue=$true; Hint='Controls teleport restrictions for bound items.' }
                    @{ Id='CanLootEnemyContainers'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='CanLootEnemyContainers'; Label='Can Loot Enemy Containers'; DefaultValue=$false; Hint='Allow looting enemy containers.' }
                    @{ Id='AllWaypointsUnlocked'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='AllWaypointsUnlocked'; Label='All Waypoints Unlocked'; DefaultValue=$false; Hint='Unlock all waypoints.' }
                    @{ Id='FreeCastleRaid'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='FreeCastleRaid'; Label='Free Castle Raid'; DefaultValue=$false; Hint='Raid/castle cost behavior if supported.' }
                    @{ Id='FreeCastleClaim'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='FreeCastleClaim'; Label='Free Castle Claim'; DefaultValue=$false; Hint='Allow free castle claiming if supported.' }
                    @{ Id='FreeCastleDestroy'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='FreeCastleDestroy'; Label='Free Castle Destroy'; DefaultValue=$false; Hint='Allow free castle destroy if supported.' }
                )
            }
            [pscustomobject]@{
                Title = 'Modifiers'
                Description = 'Rates, yields, drain and cost modifiers. Values use known V Rising clamps from startup warnings where available.'
                Fields = @(
                    @{ Id='BloodDrainModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='BloodDrainModifier'; Label='Blood Drain Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='DurabilityDrainModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='DurabilityDrainModifier'; Label='Durability Drain Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='GarlicAreaStrengthModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='GarlicAreaStrengthModifier'; Label='Garlic Area Strength Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='HolyAreaStrengthModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='HolyAreaStrengthModifier'; Label='Holy Area Strength Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='SilverStrengthModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='SilverStrengthModifier'; Label='Silver Strength Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='SunDamageModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='SunDamageModifier'; Label='Sun Damage Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='BuildCostModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='BuildCostModifier'; Label='Build Cost Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='RecipeCostModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='RecipeCostModifier'; Label='Recipe Cost Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='ResearchCostModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='ResearchCostModifier'; Label='Research Cost Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='RefinementCostModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='RefinementCostModifier'; Label='Refinement Cost Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='ResearchTimeModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='ResearchTimeModifier'; Label='Research Time Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='RefinementRateModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='RefinementRateModifier'; Label='Refinement Rate Modifier'; DefaultValue=1.0; Min=0.01; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0.01 to 100.' }
                    @{ Id='CraftRateModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='CraftRateModifier'; Label='Craft Rate Modifier'; DefaultValue=1.0; Min=0.01; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0.01 to 100.' }
                    @{ Id='ServantConvertRateModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='ServantConvertRateModifier'; Label='Servant Convert Rate Modifier'; DefaultValue=1.0; Min=0.01; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0.01 to 100.' }
                    @{ Id='InventoryStacksModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='InventoryStacksModifier'; Label='Inventory Stacks Modifier'; DefaultValue=1.0; Min=0.0001; Max=3; Decimals=4; Increment='0.1'; Hint='Known clamp: 0.0001 to 3.' }
                    @{ Id='DropTableModifier_General'; Type='Number'; File='ServerGameSettings.json'; JsonPath='DropTableModifier_General'; Label='Drop Table Modifier - General'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='DropTableModifier_Missions'; Type='Number'; File='ServerGameSettings.json'; JsonPath='DropTableModifier_Missions'; Label='Drop Table Modifier - Missions'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='MaterialYieldModifier_Global'; Type='Number'; File='ServerGameSettings.json'; JsonPath='MaterialYieldModifier_Global'; Label='Material Yield Modifier - Global'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='BloodEssenceYieldModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='BloodEssenceYieldModifier'; Label='Blood Essence Yield Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='JournalVBloodSourceUnitMaxDistance'; Type='Number'; File='ServerGameSettings.json'; JsonPath='JournalVBloodSourceUnitMaxDistance'; Label='Journal VBlood Source Max Distance'; DefaultValue=25.0; Min=0; Max=100; Decimals=2; Increment='1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='PvPVampireRespawnModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='PvPVampireRespawnModifier'; Label='PvP Vampire Respawn Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                )
            }
            [pscustomobject]@{
                Title = 'Castle / Time'
                Description = 'Castle, inactivity, timers and siege options.'
                Fields = @(
                    @{ Id='CastleDecayRateModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='CastleDecayRateModifier'; Label='Castle Decay Rate Modifier'; DefaultValue=1.0; Min=0; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0 to 100.' }
                    @{ Id='CastleBloodEssenceDrainModifier'; Type='Number'; File='ServerGameSettings.json'; JsonPath='CastleBloodEssenceDrainModifier'; Label='Castle Blood Essence Drain Modifier'; DefaultValue=1.0; Min=0.01; Max=100; Decimals=2; Increment='0.1'; Hint='Known clamp: 0.01 to 100.' }
                    @{ Id='CastleSiegeTimer'; Type='Number'; File='ServerGameSettings.json'; JsonPath='CastleSiegeTimer'; Label='Castle Siege Timer'; DefaultValue=420; Min=0; Max=65504; Decimals=0; Hint='Siege timer in seconds if supported.' }
                    @{ Id='CastleUnderAttackTimer'; Type='Number'; File='ServerGameSettings.json'; JsonPath='CastleUnderAttackTimer'; Label='Castle Under Attack Timer'; DefaultValue=60; Min=0; Max=65504; Decimals=0; Hint='Known clamp: 0 to 65504.' }
                    @{ Id='AnnounceSiegeWeaponSpawn'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='AnnounceSiegeWeaponSpawn'; Label='Announce Siege Weapon Spawn'; DefaultValue=$true; Hint='Announce siege weapon spawns.' }
                    @{ Id='ShowSiegeWeaponMapIcon'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='ShowSiegeWeaponMapIcon'; Label='Show Siege Weapon Map Icon'; DefaultValue=$true; Hint='Show siege weapon map icons.' }
                    @{ Id='InactivityKillEnabled'; Type='Boolean'; File='ServerGameSettings.json'; JsonPath='InactivityKillEnabled'; Label='Inactivity Kill Enabled'; DefaultValue=$true; Hint='Kill inactive players when enabled.' }
                    @{ Id='InactivityKillTimeMin'; Type='Number'; File='ServerGameSettings.json'; JsonPath='InactivityKillTimeMin'; Label='Inactivity Kill Time Min'; DefaultValue=3600; Min=0; Max=2147483647; Decimals=0; Hint='Minimum inactivity time.' }
                    @{ Id='InactivityKillTimeMax'; Type='Number'; File='ServerGameSettings.json'; JsonPath='InactivityKillTimeMax'; Label='Inactivity Kill Time Max'; DefaultValue=604800; Min=0; Max=2147483647; Decimals=0; Hint='Maximum inactivity time.' }
                )
            }
            [pscustomobject]@{
                Title = 'Advanced'
                Description = 'Manual file access for values not surfaced in the form yet.'
                Fields = @(
                    @{ Id='OpenHostSettings'; Type='ActionButton'; Label='ServerHostSettings.json'; ButtonText='Open Host Settings'; Action=$actions.OpenHostSettings; Hint='Open the host settings JSON file.' }
                    @{ Id='OpenGameSettings'; Type='ActionButton'; Label='ServerGameSettings.json'; ButtonText='Open Game Settings'; Action=$actions.OpenGameSettings; Hint='Open the game settings JSON file.' }
                )
            }
            [pscustomobject]@{
                Title = 'Discord'
                Description = 'UGSM per-server Discord override settings. Empty private webhook uses the global webhook; new private values are masked and stored in UGSM secrets, not in the instance JSON.'
                Fields = @(
                    @{ Id='DiscordWebhookUrl'; Type='InstanceText'; Model='Discord'; Property='WebhookUrl'; Label='Discord Webhook URL'; DefaultValue=''; Secret=$true; Hint='Optional per-server webhook override. Leave blank to clear/use global. Stored through UGSM secret handling.' }
                    @{ Id='DiscordNotifyStart'; Type='InstanceBoolean'; Model='Discord'; Property='NotifyOnStart'; Label='Notify On Start'; DefaultValue=$false; Hint='Send a Discord notification when this server starts.' }
                    @{ Id='DiscordNotifyStop'; Type='InstanceBoolean'; Model='Discord'; Property='NotifyOnStop'; Label='Notify On Stop'; DefaultValue=$false; Hint='Send a Discord notification when this server stops.' }
                    @{ Id='DiscordVisible'; Type='InstanceBoolean'; Model='Discord'; Property='ShowInDashboard'; Label='Show In Dashboard'; DefaultValue=$false; Hint='Marks this server as visible for Discord/dashboard status integrations.' }
                    @{ Id='DiscordTestWebhook'; Type='ActionButton'; Label='Test Discord Webhook'; ButtonText='Send Test Message'; Hint='Sends a test message using the saved per-server secret webhook if set, otherwise the global webhook.'; Action={
                        param($Instance,$Paths,$StatusLabel)
                        try {
                            $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
                            if (-not $discordModel.HasWebhook) { if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook is configured.' }; return }
                            $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('V Rising ' + [string]$Instance.Name)
                            if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) { if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully.' } }
                            else { if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed.' } }
                        } catch { if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message } }
                    } }
                )
            }
        )
    }
}

function Resolve-UGSMGameVRisingEditorFieldPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Field, [Parameter(Mandatory)][object]$Paths)

    switch ([string]$Field.File) {
        'ServerHostSettings.json' { return [string]$Paths.HostSettingsPath }
        'ServerGameSettings.json' { return [string]$Paths.GameSettingsPath }
        default { return '' }
    }
}

function Get-UGSMGameVRisingEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)][object]$HostSettings,
        [Parameter(Mandatory)][object]$GameSettings,
        [AllowNull()][object]$DiscordModel
    )

    if ([string]$Field.Type -in @('InstanceText','InstanceBoolean')) {
        if ([string]$Field.Model -eq 'Discord' -and $DiscordModel) {
            $prop = [string]$Field.Property
            if (-not [string]::IsNullOrWhiteSpace($prop) -and $DiscordModel.PSObject.Properties[$prop]) { return $DiscordModel.$prop }
        }
        if ($Field.ContainsKey('DefaultValue')) { return $Field.DefaultValue }
        return $null
    }

    if (-not $Field.ContainsKey('JsonPath')) {
        if ($Field.ContainsKey('DefaultValue')) { return $Field.DefaultValue }
        return $null
    }

    $root = if ([string]$Field.File -eq 'ServerHostSettings.json') { $HostSettings } else { $GameSettings }
    $default = $null
    if ($Field.ContainsKey('DefaultValue')) { $default = $Field.DefaultValue }
    if (Get-Command -Name Get-UGSMGameJsonPathValue -ErrorAction SilentlyContinue) {
        return Get-UGSMGameJsonPathValue -Root $root -JsonPath ([string]$Field.JsonPath) -DefaultValue $default
    }

    # Fallback if the shared helper is not loaded for a dev-source run.
    $current = $root
    foreach ($segment in @(([string]$Field.JsonPath) -split '\.')) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) { return $default }
        $current = $current.$segment
    }
    if ($null -eq $current) { return $default }
    return $current
}

function ConvertTo-UGSMGameVRisingEditorFieldValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Field, [Parameter(Mandatory)][System.Windows.Forms.Control]$Control)

    switch ([string]$Field.Type) {
        'Boolean' { return [bool]([System.Windows.Forms.CheckBox]$Control).Checked }
        'InstanceBoolean' { return [bool]([System.Windows.Forms.CheckBox]$Control).Checked }
        'Number' {
            $decimals = 0
            if ($Field.ContainsKey('Decimals')) { $decimals = [int]$Field.Decimals }
            if ($decimals -le 0) { return [int]([System.Windows.Forms.NumericUpDown]$Control).Value }
            return [double]([System.Windows.Forms.NumericUpDown]$Control).Value
        }
        'Dropdown' { return [string]([System.Windows.Forms.ComboBox]$Control).Text }
        default { return [string]([System.Windows.Forms.TextBox]$Control).Text }
    }
}


function Get-UGSMGameVRisingBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance

        [void]$targets.Add([pscustomobject]@{
            SourcePath   = [string]$paths.HostSettingsPath
            RelativePath = 'Settings\ServerHostSettings.json'
            Label        = 'V Rising server host settings'
        })

        [void]$targets.Add([pscustomobject]@{
            SourcePath   = [string]$paths.GameSettingsPath
            RelativePath = 'Settings\ServerGameSettings.json'
            Label        = 'V Rising server game settings'
        })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameVRisingManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'V Rising managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameVRisingBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'VRising' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameVRisingLog -Level 'WARN' -Message ('V Rising managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Save-UGSMGameVRisingInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameVRisingProfilePaths -Instance $Instance
    $settings = Get-UGSMGameVRisingSettings -Instance $Instance
    $hostConfig = $settings.Host
    $gameConfig = $settings.Game
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false
    $jsonFieldsWritten = 0

    foreach ($dirPath in @($paths.ProfileRoot,$paths.SettingsRoot,$paths.SaveRoot,$paths.LogRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) { New-Item -ItemType Directory -Path $dirPath -Force | Out-Null }
    }

    Invoke-UGSMGameVRisingManagedBackup -Instance $Instance -Scope 'Settings' -Reason 'Before V Rising settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }
        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'ActionButton' { continue }
            'InstanceText' {
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = [string](ConvertTo-UGSMGameVRisingEditorFieldValue -Field $field -Control $control)
                    $hasDiscordChanges = $true
                }
                continue
            }
            'InstanceBoolean' {
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = [bool](ConvertTo-UGSMGameVRisingEditorFieldValue -Field $field -Control $control)
                    $hasDiscordChanges = $true
                }
                continue
            }
        }

        if (-not $field.ContainsKey('JsonPath')) { continue }
        $value = ConvertTo-UGSMGameVRisingEditorFieldValue -Field $field -Control $control
        $target = if ([string]$field.File -eq 'ServerHostSettings.json') { $hostConfig } else { $gameConfig }
        if (Get-Command -Name Set-UGSMGameJsonPathValue -ErrorAction SilentlyContinue) {
            $null = Set-UGSMGameJsonPathValue -Root $target -JsonPath ([string]$field.JsonPath) -Value $value
        }
        else {
            # Fallback if the helper is not loaded.
            $segments = @(([string]$field.JsonPath) -split '\.')
            $current = $target
            for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
                $seg = [string]$segments[$i]
                if (-not $current.PSObject.Properties[$seg] -or $null -eq $current.$seg) { Add-Member -InputObject $current -MemberType NoteProperty -Name $seg -Value ([pscustomobject]@{}) -Force }
                $current = $current.$seg
            }
            $leaf = [string]$segments[-1]
            if ($current.PSObject.Properties[$leaf]) { $current.$leaf = $value } else { Add-Member -InputObject $current -MemberType NoteProperty -Name $leaf -Value $value -Force }
        }
        $jsonFieldsWritten++
    }

    if ($hasDiscordChanges -and (Get-Command -Name Save-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue)) {
        # Keep the shared Discord service happy by passing the full expected Discord shape.
        # Some older instance objects do not have these compatibility fields yet.
        foreach ($compatName in @('WebhookUrl','NotifyOnStart','NotifyOnStop','ShowInDashboard','HasPrivateDiscordWebhook','DiscordWebhookSecretId')) {
            if (-not $discordInput.Contains($compatName)) {
                $compatValue = $null
                if ($Instance -and $Instance.PSObject.Properties['Discord'] -and $Instance.Discord -and $Instance.Discord.PSObject.Properties[$compatName]) {
                    $compatValue = $Instance.Discord.$compatName
                }
                elseif ($Instance -and $Instance.PSObject.Properties[$compatName]) {
                    $compatValue = $Instance.$compatName
                }
                elseif ($compatName -in @('NotifyOnStart','NotifyOnStop','ShowInDashboard','HasPrivateDiscordWebhook')) {
                    $compatValue = $false
                }
                else {
                    $compatValue = ''
                }
                $discordInput[$compatName] = $compatValue
            }
        }

        $persistScript = { param($updated) if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) { Save-UGSMInstance -Instance $updated | Out-Null } }
        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $Instance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) { $Instance = $discordResult.Instance }
    }

    Save-UGSMGameVRisingSettings -Instance $Instance -HostSettings $hostConfig -GameSettings $gameConfig
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Editor settings saved. InstanceId=$(Get-UGSMGameVRisingInstanceId -Instance $Instance); JsonFields=$jsonFieldsWritten; DiscordUpdated=$hasDiscordChanges")
    return [pscustomobject]@{ Success=$true; Message=("Saved V Rising settings. JSON fields: {0}." -f $jsonFieldsWritten); Instance=$Instance }
}

function Add-UGSMGameVRisingEditorRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$Parent,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [string]$Hint = '',
        [AllowNull()][object]$Theme,
        [int]$Top = 0
    )

    $fore = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $muted = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
    $back = $Parent.BackColor

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Left = 16
    $lbl.Top = $Top + 3
    $lbl.Width = 180
    $lbl.Height = 24
    $lbl.ForeColor = $fore
    $lbl.BackColor = $back
    $lbl.Font = New-Object System.Drawing.Font($lbl.Font, [System.Drawing.FontStyle]::Bold)
    $Parent.Controls.Add($lbl)

    $Control.Left = 210
    $Control.Top = $Top
    $Control.Width = if ($Control.Width -gt 20) { $Control.Width } else { 520 }
    $Parent.Controls.Add($Control)

    $rowHeight = [Math]::Max(34, $Control.Height + 2)
    if (-not [string]::IsNullOrWhiteSpace($Hint)) {
        $hintLabel = New-Object System.Windows.Forms.Label
        $hintLabel.Text = $Hint
        $hintLabel.Left = 210
        $hintLabel.Top = $Top + $Control.Height + 2
        $hintLabel.Width = 760
        $hintLabel.Height = 18
        $hintLabel.ForeColor = $muted
        $hintLabel.BackColor = $back
        $Parent.Controls.Add($hintLabel)
        $rowHeight += 20
    }
    return ($Top + $rowHeight + 18)
}

function New-UGSMGameVRisingEditorControlForField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [AllowNull()][object]$Value,
        [AllowNull()][object]$Theme
    )

    $inputBack = [System.Drawing.Color]::White
    $inputFore = [System.Drawing.Color]::Black

    switch ([string]$Field.Type) {
        'Boolean' { $cb = New-Object System.Windows.Forms.CheckBox; $cb.Checked = [bool]$Value; $cb.Width = 24; $cb.Height = 24; $cb.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(18,22,28)); return $cb }
        'InstanceBoolean' { $cb = New-Object System.Windows.Forms.CheckBox; $cb.Checked = [bool]$Value; $cb.Width = 24; $cb.Height = 24; $cb.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(18,22,28)); return $cb }
        'Number' {
            $nud = New-Object System.Windows.Forms.NumericUpDown
            $nud.Width = 130
            $nud.Height = 24
            $nud.DecimalPlaces = if ($Field.ContainsKey('Decimals')) { [int]$Field.Decimals } else { 0 }
            $nud.Minimum = if ($Field.ContainsKey('Min')) { [decimal]$Field.Min } else { [decimal]0 }
            $nud.Maximum = if ($Field.ContainsKey('Max')) { [decimal]$Field.Max } else { [decimal]1000000 }
            if ($Field.ContainsKey('Increment')) { try { $nud.Increment = [decimal]([string]$Field.Increment) } catch {} }
            $candidate = [decimal]0
            try { $candidate = [decimal]$Value } catch { if ($Field.ContainsKey('DefaultValue')) { $candidate = [decimal]$Field.DefaultValue } }
            if ($candidate -lt $nud.Minimum) { $candidate = $nud.Minimum }
            if ($candidate -gt $nud.Maximum) { $candidate = $nud.Maximum }
            $nud.Value = $candidate
            return $nud
        }
        'Dropdown' {
            $combo = New-Object System.Windows.Forms.ComboBox
            $combo.Width = 340
            $combo.Height = 24
            $combo.DropDownStyle = 'DropDownList'
            foreach ($opt in @($Field.Options)) { [void]$combo.Items.Add([string]$opt) }
            $text = [string]$Value
            if ($combo.Items.Contains($text)) { $combo.SelectedItem = $text }
            elseif ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }
            $combo.BackColor = $inputBack
            $combo.ForeColor = $inputFore
            return $combo
        }
        'MultilineText' {
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Multiline = $true
            $tb.AcceptsReturn = $true
            $tb.ScrollBars = 'Vertical'
            $tb.Width = 620
            $tb.Height = 58
            $tb.Text = [string]$Value
            $tb.BackColor = $inputBack
            $tb.ForeColor = $inputFore
            return $tb
        }
        'ActionButton' {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = if ($Field.ContainsKey('ButtonText')) { [string]$Field.ButtonText } else { [string]$Field.Label }
            $btn.Width = 190
            $btn.Height = 28
            return $btn
        }
        default {
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Width = 520
            $tb.Height = 24
            $tb.Text = [string]$Value
            if ($Field.ContainsKey('Secret') -and [bool]$Field.Secret) { $tb.UseSystemPasswordChar = $true }
            $tb.BackColor = $inputBack
            $tb.ForeColor = $inputFore
            return $tb
        }
    }
}

function New-UGSMGameVRisingInstanceEditor {
    [CmdletBinding()]
    param([object]$Instance,[object]$AppState,[object]$Theme,[object]$HostPanel,[object]$StatusLabel)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = Get-UGSMGameVRisingInstanceId -Instance $Instance
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")

    if (-not $HostPanel) { $HostPanel = New-Object System.Windows.Forms.Panel }
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(18,22,28))

        $settings = Get-UGSMGameVRisingSettings -Instance $Instance
        $paths = $settings.Paths
        $hostConfig = $settings.Host
        $gameConfig = $settings.Game
        $schema = Get-UGSMGameVRisingEditorSchema -Instance $Instance
        $discordModel = $null
        if (Get-Command -Name Get-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) { try { $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance } catch { $discordModel = $null } }
        if (-not $discordModel) { $discordModel = [pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false } }

        $status = New-Object System.Windows.Forms.Label
        $status.Dock = 'Bottom'
        $status.Height = 24
        $status.Text = 'V Rising editor loaded.'
        $status.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
        $status.BackColor = $HostPanel.BackColor
        $HostPanel.Controls.Add($status)

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Top'
        $header.Height = 52
        $header.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Surface' -Fallback ([System.Drawing.Color]::FromArgb(25,31,40))
        $HostPanel.Controls.Add($header)

        $title = New-Object System.Windows.Forms.Label
        $title.Text = ('V Rising Profile Editor - {0}' -f (Get-UGSMGameVRisingProfileName -Instance $Instance))
        $title.Left = 16; $title.Top = 8; $title.Width = 520; $title.Height = 22
        $title.Font = New-Object System.Drawing.Font($title.Font, [System.Drawing.FontStyle]::Bold)
        $title.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $title.BackColor = $header.BackColor
        $header.Controls.Add($title)

        $pathLabel = New-Object System.Windows.Forms.Label
        $pathLabel.Text = [string]$paths.ProfileRoot
        $pathLabel.Left = 16; $pathLabel.Top = 30; $pathLabel.Width = 780; $pathLabel.Height = 18
        $pathLabel.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
        $pathLabel.BackColor = $header.BackColor
        $header.Controls.Add($pathLabel)

        $toolbar = New-Object System.Windows.Forms.Panel
        $toolbar.Dock = 'Top'; $toolbar.Height = 40; $toolbar.BackColor = $HostPanel.BackColor
        $HostPanel.Controls.Add($toolbar)

        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save All'; $btnSave.Width = 92; $btnSave.Height = 28; $btnSave.Top = 6
        $btnSave.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Accent' -Fallback ([System.Drawing.Color]::FromArgb(46,160,67))
        $btnSave.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $toolbar.Controls.Add($btnSave)

        $btnReload = New-Object System.Windows.Forms.Button
        $btnReload.Text = 'Reload'; $btnReload.Width = 72; $btnReload.Height = 28; $btnReload.Top = 6
        $btnReload.BackColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Button' -Fallback ([System.Drawing.Color]::FromArgb(52,58,70))
        $btnReload.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $toolbar.Controls.Add($btnReload)
        $toolbar.Add_Resize({ param($s,$e) $s.Controls[0].Left = [Math]::Max(0, $s.Width - 104); $s.Controls[1].Left = [Math]::Max(0, $s.Width - 182) })

        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $HostPanel.Controls.Add($tabs)
        $tabs.BringToFront()

        $controlMap = @{}
        foreach ($tab in @($schema.Tabs)) {
            $page = New-Object System.Windows.Forms.TabPage
            $page.Text = [string]$tab.Title
            $page.BackColor = $HostPanel.BackColor
            [void]$tabs.TabPages.Add($page)

            $scroll = New-Object System.Windows.Forms.Panel
            $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true; $scroll.BackColor = $page.BackColor
            $page.Controls.Add($scroll)

            $top = 14
            if (-not [string]::IsNullOrWhiteSpace([string]$tab.Description)) {
                $desc = New-Object System.Windows.Forms.Label
                $desc.Text = [string]$tab.Description
                $desc.Left = 16; $desc.Top = $top; $desc.Width = 950; $desc.Height = 28
                $desc.ForeColor = Get-UGSMGameVRisingColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
                $desc.BackColor = $scroll.BackColor
                $scroll.Controls.Add($desc)
                $top += 38
            }

            foreach ($field in @($tab.Fields)) {
                $value = Get-UGSMGameVRisingEditorFieldValue -Field $field -HostSettings $hostConfig -GameSettings $gameConfig -DiscordModel $discordModel
                $control = New-UGSMGameVRisingEditorControlForField -Field $field -Value $value -Theme $Theme
                if ([string]$field.Type -eq 'ActionButton') {
                    $control.Tag = [pscustomobject]@{ Field=$field; Instance=$Instance; Paths=$paths; Status=$status }
                    $control.Add_Click({ param($sender,$eventArgs) $state=$sender.Tag; try { & $state.Field['Action'] $state.Instance $state.Paths $state.Status } catch { if ($state.Status) { $state.Status.Text = 'Action failed: ' + $_.Exception.Message } } })
                }
                else {
                    $controlMap[[string]$field.Id] = [pscustomobject]@{ Field=$field; Control=$control }
                }
                $top = Add-UGSMGameVRisingEditorRow -Parent $scroll -Label ([string]$field.Label) -Control $control -Hint ([string]$field.Hint) -Theme $Theme -Top $top
            }
            try { $scroll.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($top + 60)) } catch {}
        }

        $editorState = [pscustomobject]@{ Instance=$Instance; Controls=$controlMap; StatusLabel=$status; HostPanel=$HostPanel; Theme=$Theme }
        $btnSave.Tag = $editorState
        $btnReload.Tag = $editorState

        $btnSave.Add_Click({
            param($sender,$eventArgs)
            $state = $sender.Tag
            try {
                $result = Save-UGSMGameVRisingInstanceEditor -Instance $state.Instance -EditorState $state.Controls
                if ($state.StatusLabel) { $state.StatusLabel.Text = $result.Message }
            } catch { try { if ($state.StatusLabel) { $state.StatusLabel.Text = 'V Rising save failed: ' + $_.Exception.Message } } catch {}; Write-UGSMGameVRisingLog -Level 'ERROR' -Message 'Editor save failed.' -Exception $_.Exception }
        })

        $btnReload.Add_Click({
            param($sender,$eventArgs)
            $state = $sender.Tag
            try { New-UGSMGameVRisingInstanceEditor -Instance $state.Instance -Theme $state.Theme -HostPanel $state.HostPanel -StatusLabel $state.StatusLabel }
            catch { try { if ($state.StatusLabel) { $state.StatusLabel.Text = 'V Rising reload failed: ' + $_.Exception.Message } } catch {}; Write-UGSMGameVRisingLog -Level 'ERROR' -Message 'Editor reload failed.' -Exception $_.Exception }
        })
    }
    finally { $HostPanel.ResumeLayout($true) }

    $sw.Stop()
    Write-UGSMGameVRisingLog -Level 'INFO' -Message ("Editor creation finished. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)")
}

function Register-UGSMGameVRisingModule {
    [CmdletBinding()]
    param()
    $metadata = Get-UGSMGameVRisingMetadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameVRisingMetadata'
            TestInstall       = 'Test-UGSMGameVRisingInstall'
            TestInstance      = 'Test-UGSMGameVRisingInstance'
            EnsureTemplate    = 'Ensure-UGSMGameVRisingTemplate'
            InitializeProfile = 'Initialize-UGSMGameVRisingProfile'
            Start             = 'Start-UGSMGameVRisingInstance'
            Stop              = 'Stop-UGSMGameVRisingInstance'
            BuildEditor       = 'New-UGSMGameVRisingInstanceEditor'
            SaveEditor        = 'Save-UGSMGameVRisingInstanceEditor'
        }
    }
}
