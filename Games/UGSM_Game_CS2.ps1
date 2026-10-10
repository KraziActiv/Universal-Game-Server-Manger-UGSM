
# CS2 dedicated server module
# CS2 pass 4: grouped gameplay CFG tabs, corrected workshop-map launch args, and installed-map dropdown.
# Valve gamemode defaults are not edited; UGSM writes overrides into ugsm_<profile>.cfg.

function Write-UGSMGameCS2Log {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerboseCS2Logging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_CS2)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'CS2' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'CS2' -Message $Message }
        return
    }
    if ($Exception) { Write-Warning ("[CS2] $Message :: $($Exception.Message)") } else { Write-Host "[CS2][$Level] $Message" }
}

function Get-UGSMGameCS2Metadata {
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Id                       = 'CS2'
        Name                     = 'Counter-Strike 2'
        Category                 = 'FPS'
        Description              = 'Counter-Strike 2 Dedicated Server integration.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 110
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $true
        SupportsInstall          = $true
        SupportsUpdate           = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $true
        SupportsWorkshop         = $true
        SupportsRcon             = $true
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '730'
        SteamStoreAppId          = '730'
        ServerExecutable         = 'game\bin\win64\cs2.exe'
        ServerExecutableRelative = 'game\bin\win64\cs2.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'game\csgo\cfg'
        SaveRootRelative         = 'game\csgo'
        LogRootRelative          = 'Logs'
        RequiredFiles            = @('game\bin\win64\cs2.exe')
        InstallMarkers           = @('game\bin\win64\cs2.exe')
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 27015 },
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 },
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 27017 }
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
                'SteamCMD app id 730 installs CS2 dedicated server files using anonymous login.',
                'UGSM uses shared CS2 binaries and writes per-profile server cfg files into game\csgo\cfg as ugsm_<profile>.cfg.',
                'UGSM writes per-profile overrides into ugsm_<profile>.cfg and does not edit Valve gamemode_*.cfg files.',
                'Workshop maps use +host_workshop_map <WorkshopID>. UGSM keeps +map on an installed vanilla bootstrap map.',
                'RCON graceful shutdown is a later pass item. Current stop closes/kills the tracked process.'
            )
        }
    }
}

function Get-UGSMGameCS2InstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName','InstanceId')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return ''
}

function Get-UGSMGameCS2ProfileName {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    $name = Get-UGSMGameCS2InstanceId -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'CS21' }
    $safe = $name -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'CS21' }
    return $safe
}

function Get-UGSMGameCS2AppDataRoot {
    [CmdletBinding()]
    param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { return [string](Get-UGSMAppDataRoot) }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameCS2ProfileBaseRoot {
    [CmdletBinding()]
    param()
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'CS2' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) }
    }
    return (Join-Path (Get-UGSMGameCS2AppDataRoot) 'Profiles')
}

function Get-UGSMGameCS2ProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Join-Path (Get-UGSMGameCS2ProfileBaseRoot) 'CS2') $ProfileName)
}

function Get-UGSMGameCS2InstallPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$InstallPath)

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return $InstallPath }
    if ($Instance -and $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) { return [string]$Instance.InstallPath }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $roots = New-Object System.Collections.Generic.List[string]
    if ($settings) {
        foreach ($propName in @('SteamLibraryRoot','SteamRoot','SteamCmdRoot','InstallRoot')) {
            try {
                if ($settings.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propName)) {
                    $candidateRoot = [string]$settings.$propName
                    if (-not $roots.Contains($candidateRoot)) { [void]$roots.Add($candidateRoot) }
                }
            } catch {}
        }
    }

    $folderNames = @(
        'CS2',
        'Counter-Strike Global Offensive',
        'cs2-ds'
    )

    foreach ($base in $roots) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }

        $baseCandidates = New-Object System.Collections.Generic.List[string]
        foreach ($folderName in $folderNames) {
            try {
                $commonPath = Join-Path (Join-Path $base 'steamapps') 'common'
                [void]$baseCandidates.Add((Join-Path $commonPath $folderName))
            } catch {}
            try { [void]$baseCandidates.Add((Join-Path $base $folderName)) } catch {}
        }

        foreach ($candidate in $baseCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            try {
                if (Test-Path -LiteralPath (Join-Path $candidate 'game\bin\win64\cs2.exe') -PathType Leaf) { return $candidate }
            } catch {}
        }
    }

    # No hardcoded fallback path. If CS2 is not installed or the Steam root is not configured,
    # return empty so the Games page can show Install without probing source-machine drives.
    return ''
}

function Get-UGSMGameCS2InstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $root = Get-UGSMGameCS2InstallPath -Instance $Instance -InstallPath $InstallPath

    $serverExe = ''
    $cfgRoot = ''
    $gameRoot = ''
    if (-not [string]::IsNullOrWhiteSpace($root)) {
        $serverExe = Join-Path $root 'game\bin\win64\cs2.exe'
        $cfgRoot = Join-Path $root 'game\csgo\cfg'
        $gameRoot = Join-Path $root 'game\csgo'
    }

    return [pscustomobject]@{
        InstallPath          = $root
        ServerExecutablePath = $serverExe
        CfgRoot              = $cfgRoot
        GameRoot             = $gameRoot
    }
}

function Test-UGSMGameCS2Install {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
    $ok = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$definition.ServerExecutablePath)) {
        try { $ok = Test-Path -LiteralPath $definition.ServerExecutablePath -PathType Leaf } catch { $ok = $false }
    }
    return [pscustomobject]@{ Success=[bool]$ok; IsInstalled=[bool]$ok; InstallPath=$definition.InstallPath; ServerExecutablePath=$definition.ServerExecutablePath; Message=if ($ok) { 'CS2 Dedicated Server install detected.' } else { 'CS2 Dedicated Server was not detected.' } }
}
function Get-UGSMGameCS2AssignedPort {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][string]$Name, [int]$Default)
    foreach ($propName in @('Ports','AssignedPorts')) {
        if (-not ($Instance.PSObject.Properties[$propName])) { continue }
        $ports = $Instance.$propName
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) {
            $entry = $ports[$Name]
            if ($entry -is [int]) { return [int]$entry }
            if ($entry -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
        } elseif ($ports) {
            foreach ($entry in @($ports)) {
                if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
            }
        }
    }
    return $Default
}


function Get-UGSMGameCS2ProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $profileName = Get-UGSMGameCS2ProfileName -Instance $Instance
    $profileRoot = Get-UGSMGameCS2ProfileRoot -ProfileName $profileName
    $serverData = Join-Path $profileRoot 'ServerData'
    $logsRoot = Join-Path $profileRoot 'Logs'
    $centralLogRoot = Join-Path (Join-Path (Get-UGSMGameCS2AppDataRoot) 'Logs\CS2') $profileName
    $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
    $safeCfgName = 'ugsm_' + ($profileName -replace '[^A-Za-z0-9_.-]', '_') + '.cfg'
    return [pscustomobject]@{
        ProfileName       = $profileName
        ProfileRoot       = $profileRoot
        ServerDataRoot    = $serverData
        LogsRoot          = $logsRoot
        CentralLogRoot    = $centralLogRoot
        SettingsPath      = Join-Path $profileRoot 'UGSM_CS2Settings.json'
        LocalServerCfgPath = Join-Path $serverData $safeCfgName
        ServerCfgName     = $safeCfgName
        ServerCfgPath     = Join-Path $definition.CfgRoot $safeCfgName
        LauncherPath      = Join-Path $logsRoot 'UGSM_Start_CS2.cmd'
        LaunchLogPath     = Join-Path $centralLogRoot 'server-launch.log'
        InstallCfgRoot    = $definition.CfgRoot
        InstallGameRoot   = $definition.GameRoot
    }
}

function ConvertFrom-UGSMGameCS2MultilineList {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split "`r?`n|,|;" | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-UGSMGameCS2InstalledMaps {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$InstallPath)
    $mapNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('de_dust2','de_mirage','de_inferno','de_nuke','de_train','de_vertigo','de_ancient','de_anubis','de_overpass','cs_office','cs_italy','ar_baggage','ar_pool_day','ar_shoots')) {
        if (-not $mapNames.Contains($name)) { [void]$mapNames.Add($name) }
    }
    try {
        $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
        $mapsRoot = Join-Path $definition.GameRoot 'maps'
        if (Test-Path -LiteralPath $mapsRoot -PathType Container) {
            Get-ChildItem -LiteralPath $mapsRoot -Filter '*.vpk' -File -ErrorAction SilentlyContinue | ForEach-Object {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if ([string]::IsNullOrWhiteSpace($name)) { return }
                if ($name -match '_vanity$') { return }
                if ($name -match '^workshop_preview_') { return }
                if ($name -in @('graphics_settings','lobby_mapveto','warehouse_vanity')) { return }
                if ($name -notmatch '^(de_|cs_|ar_|gd_)') { return }
                if (-not $mapNames.Contains($name)) { [void]$mapNames.Add($name) }
            }
        }
    } catch {
        Write-UGSMGameCS2Log -Level 'DEBUG' -Message 'Could not scan CS2 installed maps. Using built-in map defaults.' -Exception $_.Exception
    }
    return @($mapNames | Sort-Object)
}


function Get-UGSMGameCS2DefaultSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $profileName = Get-UGSMGameCS2ProfileName -Instance $Instance
    return [pscustomobject]@{
        ServerName    = $profileName
        Map           = 'de_dust2'
        GameType      = 0
        GameMode      = 1
        MaxPlayers    = 12
        GamePort      = Get-UGSMGameCS2AssignedPort -Instance $Instance -Name 'GamePort' -Default 27015
        QueryPort     = Get-UGSMGameCS2AssignedPort -Instance $Instance -Name 'QueryPort' -Default 27016
        RconPort      = Get-UGSMGameCS2AssignedPort -Instance $Instance -Name 'RconPort' -Default 27017
        RconPassword  = 'changeme'
        GSLT          = ''
        LanOnly       = $false
        TickRate      = 64
        ExtraArgs     = ''
        # Gameplay overrides written into ugsm_<profile>.cfg. Blank values are skipped.
        MpFriendlyFire = '0'
        MpTeammatesAreEnemies = '0'
        MpSolidTeammates = '1'
        SvDeadtalk = '0'
        SvFullAlltalk = '0'
        SvTalkEnemyDead = '0'
        SvTalkEnemyLiving = '0'
        SvCheats = '0'
        BotQuota = '0'
        BotQuotaMode = 'fill'
        BotDifficulty = '1'
        BotChatter = 'normal'
        BotDeferToHumanGoals = '0'
        BotDeferToHumanItems = '1'
        MpStartMoney = '800'
        MpMaxMoney = '16000'
        MpAfterroundmoney = '0'
        CashTeamTWinBomb = ''
        CashTeamEliminationHostageMap = ''
        CashTeamEliminationBombMap = ''
        CashTeamLoserBonus = ''
        CashTeamLoserBonusConsecutiveRounds = ''
        CashPlayerKilledTeammate = ''
        CashPlayerKilledEnemyDefault = ''
        CashPlayerBombPlanted = ''
        CashPlayerBombDefused = ''
        MpMaxRounds = '24'
        MpRoundTime = '1.92'
        MpRoundTimeDefuse = '1.92'
        MpRoundRestartDelay = '7'
        MpFreezeTime = '15'
        MpBuyTime = '20'
        MpC4Timer = '40'
        MpHalftime = '1'
        MpOvertimeEnable = '0'
        MpWarmupTime = '120'
        MpRespawnOnDeathCT = '0'
        MpRespawnOnDeathT = '0'
        MpRandomspawn = '0'
        MpDeathDropGun = '1'
        MpDeathDropGrenade = '2'
        MpDmBonusLengthMax = '30'
        WorkshopCollectionId = ''
        WorkshopStartMap = ''
        ExtraServerCfg = ''
        Discord       = [pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$true }
    }
}

function Get-UGSMGameCS2Settings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $InstallPath
    $default = Get-UGSMGameCS2DefaultSettings -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)) { return $default }
    try {
        $loaded = Get-Content -LiteralPath $paths.SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $default.PSObject.Properties.Name) {
            if (-not $loaded.PSObject.Properties[$prop]) { Add-Member -InputObject $loaded -MemberType NoteProperty -Name $prop -Value $default.$prop -Force }
        }
        foreach ($prop in $default.Discord.PSObject.Properties.Name) {
            if (-not $loaded.Discord) { $loaded.Discord = $default.Discord }
            if (-not $loaded.Discord.PSObject.Properties[$prop]) { Add-Member -InputObject $loaded.Discord -MemberType NoteProperty -Name $prop -Value $default.Discord.$prop -Force }
        }
        foreach ($portName in @('GamePort','QueryPort','RconPort')) {
            $assigned = Get-UGSMGameCS2AssignedPort -Instance $Instance -Name $portName -Default ([int]$default.$portName)
            if (($loaded.$portName -as [int]) -le 0) { $loaded.$portName = $assigned }
        }
        return $loaded
    } catch {
        Write-UGSMGameCS2Log -Level 'WARN' -Message "Failed to read CS2 settings. Defaults will be used. Path=$($paths.SettingsPath)" -Exception $_.Exception
        return $default
    }
}

function Save-UGSMGameCS2JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 16
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}


function Save-UGSMGameCS2ServerCfg {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Paths.LocalServerCfgPath), $Paths.InstallCfgRoot | Out-Null
    $lines = @(
        ('hostname "{0}"' -f ([string]$Settings.ServerName).Replace('"','\"')),
        ('rcon_password "{0}"' -f ([string]$Settings.RconPassword).Replace('"','\"')),
        ('sv_lan {0}' -f ($(if ([bool]$Settings.LanOnly) { '1' } else { '0' })))
    )
    if (($Settings.MaxPlayers -as [int]) -gt 0) { $lines += ('sv_visiblemaxplayers {0}' -f ([int]$Settings.MaxPlayers)) }
    if (($Settings.TickRate -as [int]) -gt 0) { $lines += ('sv_minupdaterate {0}' -f ([int]$Settings.TickRate)); $lines += ('sv_mincmdrate {0}' -f ([int]$Settings.TickRate)) }

    $lines += ''
    $lines += '// UGSM CS2 gameplay overrides. Blank UI values are skipped.'
    $cvarMap = @(
        @('MpFriendlyFire','mp_friendlyfire'), @('MpTeammatesAreEnemies','mp_teammates_are_enemies'), @('MpSolidTeammates','mp_solid_teammates'),
        @('SvDeadtalk','sv_deadtalk'), @('SvFullAlltalk','sv_full_alltalk'), @('SvTalkEnemyDead','sv_talk_enemy_dead'), @('SvTalkEnemyLiving','sv_talk_enemy_living'), @('SvCheats','sv_cheats'),
        @('BotQuota','bot_quota'), @('BotQuotaMode','bot_quota_mode'), @('BotDifficulty','bot_difficulty'), @('BotChatter','bot_chatter'), @('BotDeferToHumanGoals','bot_defer_to_human_goals'), @('BotDeferToHumanItems','bot_defer_to_human_items'),
        @('MpStartMoney','mp_startmoney'), @('MpMaxMoney','mp_maxmoney'), @('MpAfterroundmoney','mp_afterroundmoney'), @('CashTeamTWinBomb','cash_team_terrorist_win_bomb'), @('CashTeamEliminationHostageMap','cash_team_elimination_hostage_map'), @('CashTeamEliminationBombMap','cash_team_elimination_bomb_map'), @('CashTeamLoserBonus','cash_team_loser_bonus'), @('CashTeamLoserBonusConsecutiveRounds','cash_team_loser_bonus_consecutive_rounds'), @('CashPlayerKilledTeammate','cash_player_killed_teammate'), @('CashPlayerKilledEnemyDefault','cash_player_killed_enemy_default'), @('CashPlayerBombPlanted','cash_player_bomb_planted'), @('CashPlayerBombDefused','cash_player_bomb_defused'),
        @('MpMaxRounds','mp_maxrounds'), @('MpRoundTime','mp_roundtime'), @('MpRoundTimeDefuse','mp_roundtime_defuse'), @('MpRoundRestartDelay','mp_round_restart_delay'), @('MpFreezeTime','mp_freezetime'), @('MpBuyTime','mp_buytime'), @('MpC4Timer','mp_c4timer'), @('MpHalftime','mp_halftime'), @('MpOvertimeEnable','mp_overtime_enable'), @('MpWarmupTime','mp_warmuptime'),
        @('MpRespawnOnDeathCT','mp_respawn_on_death_ct'), @('MpRespawnOnDeathT','mp_respawn_on_death_t'), @('MpRandomspawn','mp_randomspawn'), @('MpDeathDropGun','mp_death_drop_gun'), @('MpDeathDropGrenade','mp_death_drop_grenade'), @('MpDmBonusLengthMax','mp_dm_bonus_length_max')
    )
    foreach ($pair in $cvarMap) {
        $prop = [string]$pair[0]; $cvar = [string]$pair[1]
        if ($Settings.PSObject.Properties[$prop]) {
            $value = [string]$Settings.$prop
            if (-not [string]::IsNullOrWhiteSpace($value)) { $lines += ('{0} {1}' -f $cvar, $value.Trim()) }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraServerCfg)) {
        $lines += ''
        $lines += '// UGSM extra server.cfg lines'
        $lines += ([string]$Settings.ExtraServerCfg -split "`r?`n")
    }
    Set-Content -LiteralPath $Paths.LocalServerCfgPath -Value $lines -Encoding UTF8
    Copy-Item -LiteralPath $Paths.LocalServerCfgPath -Destination $Paths.ServerCfgPath -Force
}

function Save-UGSMGameCS2Settings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][object]$Settings, [string]$InstallPath)
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.ServerDataRoot, $paths.LogsRoot, $paths.CentralLogRoot, $paths.InstallCfgRoot | Out-Null
    Save-UGSMGameCS2JsonFile -Path $paths.SettingsPath -Value $Settings
    Save-UGSMGameCS2ServerCfg -Paths $paths -Settings $Settings
    return [pscustomobject]@{ Success=$true; SettingsPath=$paths.SettingsPath; ServerCfgPath=$paths.ServerCfgPath }
}


function Ensure-UGSMGameCS2InstallServerLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ServerDataRoot, $paths.InstallCfgRoot, $paths.LogsRoot, $paths.CentralLogRoot | Out-Null
    return $paths.InstallCfgRoot
}

function Initialize-UGSMGameCS2Profile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath, [switch]$Force, [int]$BootstrapSeconds = 0)
    $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.ServerDataRoot, $paths.LogsRoot, $paths.CentralLogRoot, $paths.InstallCfgRoot | Out-Null
    Ensure-UGSMGameCS2InstallServerLink -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    if ($Instance.PSObject.Properties['ProfilePath']) { $Instance.ProfilePath = $paths.ProfileRoot } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProfilePath -Value $paths.ProfileRoot -Force }
    if ($Instance.PSObject.Properties['InstallPath']) { $Instance.InstallPath = $definition.InstallPath } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name InstallPath -Value $definition.InstallPath -Force }
    $settings = Get-UGSMGameCS2Settings -Instance $Instance -InstallPath $definition.InstallPath
    if ($Force -or -not (Test-Path -LiteralPath $paths.SettingsPath)) { $settings = Get-UGSMGameCS2DefaultSettings -Instance $Instance }
    Save-UGSMGameCS2Settings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null
    Write-UGSMGameCS2Log -Level 'INFO' -Message ("Profile initialized. InstanceId=$(Get-UGSMGameCS2InstanceId -Instance $Instance); ProfilePath=$($paths.ProfileRoot)")
    return [pscustomobject]@{ Success=$true; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.ServerCfgPath }
}

function Test-UGSMGameCS2Instance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $InstallPath
    $ok = (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)
    return [pscustomobject]@{ Success=[bool]$ok; Exists=[bool]$ok; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.ServerCfgPath; Message=if ($ok) { 'CS2 profile exists.' } else { 'CS2 profile has not been initialized.' } }
}


function ConvertTo-UGSMGameCS2ArgString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][object]$Paths)

    $workshopMapId = [string]$Settings.WorkshopStartMap
    $launchMap = [string]$Settings.Map

    # CS2 still needs a normal map at boot. Workshop maps are loaded with +host_workshop_map <id>.
    # If a user typed a display name like Brownstone into Map while using a Workshop ID, use a safe vanilla bootstrap map.
    if (-not [string]::IsNullOrWhiteSpace($workshopMapId)) {
        if ([string]::IsNullOrWhiteSpace($launchMap) -or ($launchMap -notmatch '^(de_|cs_|ar_|gd_)')) { $launchMap = 'de_dust2' }
    }

    $args = @(
        '-dedicated',
        '-usercon',
        ('-port {0}' -f ([int]$Settings.GamePort)),
        ('-maxplayers {0}' -f ([int]$Settings.MaxPlayers)),
        ('+servercfgfile "{0}"' -f ([string]$Paths.ServerCfgName).Replace('"','\"')),
        ('+map "{0}"' -f $launchMap.Replace('"','\"')),
        ('+game_type {0}' -f ([int]$Settings.GameType)),
        ('+game_mode {0}' -f ([int]$Settings.GameMode))
    )
    if (($Settings.QueryPort -as [int]) -gt 0) { $args += ('+hostport {0}' -f ([int]$Settings.QueryPort)) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.GSLT)) { $args += ('+sv_setsteamaccount "{0}"' -f ([string]$Settings.GSLT).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.WorkshopCollectionId)) { $args += ('+host_workshop_collection "{0}"' -f ([string]$Settings.WorkshopCollectionId).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace($workshopMapId)) { $args += ('+host_workshop_map "{0}"' -f $workshopMapId.Replace('"','\"')) }
    if ([bool]$Settings.LanOnly) { $args += '+sv_lan 1' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraArgs)) { $args += [string]$Settings.ExtraArgs }
    return ($args -join ' ')
}

function New-UGSMGameCS2LaunchWrapper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallPath, [Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path $Paths.LogsRoot, $Paths.CentralLogRoot | Out-Null
    $argString = ConvertTo-UGSMGameCS2ArgString -Settings $Settings -Paths $Paths
    $lines = @(
        '@echo off',
        'setlocal enableextensions',
        ('cd /d "{0}"' -f $InstallPath),
        ('echo [%date% %time%] UGSM CS2 launcher started. Server={0}' -f ([string]$Settings.ServerName)),
        ('"{0}" {1}' -f (Join-Path $InstallPath 'game\bin\win64\cs2.exe'), $argString),
        'set EXITCODE=%ERRORLEVEL%',
        'echo [%date% %time%] UGSM CS2 launcher exited with code %EXITCODE%.',
        'exit /b %EXITCODE%'
    )
    Set-Content -LiteralPath $Paths.LauncherPath -Value $lines -Encoding ASCII
    return $Paths.LauncherPath
}

function Start-UGSMGameCS2Instance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $instanceId = Get-UGSMGameCS2InstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameCS2Log -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")
    $definition = Get-UGSMGameCS2InstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $definition.ServerExecutablePath -PathType Leaf)) { throw "game\bin\win64\cs2.exe was not found: $($definition.ServerExecutablePath)" }
    Initialize-UGSMGameCS2Profile -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    $paths = Get-UGSMGameCS2ProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    $settings = Get-UGSMGameCS2Settings -Instance $Instance -InstallPath $definition.InstallPath
    Save-UGSMGameCS2Settings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null
    $launcherPath = New-UGSMGameCS2LaunchWrapper -InstallPath $definition.InstallPath -Paths $paths -Settings $settings
    try {
        $header = @(
            ('[{0}] UGSM starting CS2.' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
            ('InstallPath: {0}' -f $definition.InstallPath),
            ('Launcher: {0}' -f $launcherPath),
            ('ServerName: {0}' -f $settings.ServerName),
            ('GamePort: {0}' -f $settings.GamePort),
            ('QueryPort: {0}' -f $settings.QueryPort),
            ('RconPort: {0}' -f $settings.RconPort),
            ''
        )
        Set-Content -LiteralPath $paths.LaunchLogPath -Value $header -Encoding UTF8
    } catch {}
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.WorkingDirectory = $definition.InstallPath
    $psi.Arguments = '/d /k "' + $launcherPath + '"'
    $psi.UseShellExecute = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'CS2 process failed to start.' }
    Start-Sleep -Seconds 5
    try { $process.Refresh() } catch {}
    if ($process.HasExited) { throw "CS2 process exited immediately with code $($process.ExitCode). Check $($paths.LaunchLogPath)." }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = [int]$process.Id } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value ([int]$process.Id) -Force }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Running' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Running' -Force }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameCS2Log -Level 'WARN' -Message ("Discord start notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    $sw.Stop()
    Write-UGSMGameCS2Log -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$($process.Id); DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=[int]$process.Id; Pid=[int]$process.Id }
}

function Stop-UGSMGameCS2Instance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $instanceId = Get-UGSMGameCS2InstanceId -Instance $Instance
    $profileName = Get-UGSMGameCS2ProfileName -Instance $Instance
    $processId = 0
    if ($Instance.PSObject.Properties['ProcessId'] -and ($Instance.ProcessId -as [int])) { $processId = [int]$Instance.ProcessId }
    Write-UGSMGameCS2Log -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId; Pid=$processId")
    $stopped = $false
    if ($processId -gt 0) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            try { if ($proc.CloseMainWindow()) { $stopped = $proc.WaitForExit(15000) } } catch {}
            if (-not $stopped) { Stop-Process -Id $processId -Force -ErrorAction Stop; $stopped = $true }
        } catch [System.ArgumentException] { $stopped = $true } catch { Write-UGSMGameCS2Log -Level 'ERROR' -Message ("Stop failed. InstanceId=$instanceId; Pid=$processId") -Exception $_.Exception }
    }
    try {
        Get-CimInstance Win32_Process -Filter "name = 'cs2.exe' or name = 'cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [Regex]::Escape($profileName) -and $_.CommandLine -match 'cs2.exe|UGSM_Start_CS2' } |
            ForEach-Object { Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue; $stopped = $true }
    } catch {}
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Stopped' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Stopped' -Force }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = $null }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameCS2Log -Level 'WARN' -Message ("Discord stop notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    return [pscustomobject]@{ Success=$true; Status='Stopped'; Stopped=[bool]$stopped }
}

function Get-UGSMGameCS2Color {
    [CmdletBinding()]
    param([AllowNull()][object]$Theme, [Parameter(Mandatory)][string]$Name, [System.Drawing.Color]$Fallback)
    if ($Theme) {
        $prop = $Theme.PSObject.Properties[$Name]
        if ($prop -and $prop.Value -is [System.Drawing.Color]) { return $prop.Value }
    }
    $globalName = switch ($Name) {
        'Background' { 'UGSM_ColorBackground' }
        'Surface' { 'UGSM_ColorSurface' }
        'Input' { 'UGSM_ColorInputBackground' }
        'Text' { 'UGSM_ColorText' }
        'Muted' { 'UGSM_ColorMutedText' }
        'Accent' { 'UGSM_ColorAccent' }
        default { '' }
    }
    if ($globalName -and (Get-Variable -Name $globalName -Scope Global -ErrorAction SilentlyContinue)) {
        $value = (Get-Variable -Name $globalName -Scope Global).Value
        if ($value -is [System.Drawing.Color]) { return $value }
    }
    return $Fallback
}

function Add-UGSMGameCS2Field {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [string]$Value, [int]$Row, [object]$Theme, [switch]$Multiline, [int]$Height = 24)
    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.AutoSize = $false
    $labelControl.Left = 24
    $labelControl.Top = 18 + ($Row * 42)
    $labelControl.Width = 170
    $labelControl.Height = 24
    $labelControl.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($labelControl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Left = 220
    $txt.Top = 14 + ($Row * 42)
    $txt.Width = 520
    $txt.Height = $Height
    $txt.Text = $Value
    $txt.Multiline = [bool]$Multiline
    if ($Multiline) { $txt.ScrollBars = 'Vertical'; $txt.AcceptsReturn = $true }
    $txt.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $txt.BackColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24))
    $Parent.Controls.Add($txt)
    $Controls[$Key] = $txt
    return $txt
}

function Add-UGSMGameCS2ComboField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [string]$Value, [string[]]$Items, [int]$Row, [object]$Theme)
    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.AutoSize = $false
    $labelControl.Left = 24
    $labelControl.Top = 18 + ($Row * 42)
    $labelControl.Width = 170
    $labelControl.Height = 24
    $labelControl.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($labelControl)
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Left = 220
    $combo.Top = 14 + ($Row * 42)
    $combo.Width = 520
    $combo.Height = 24
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($item in @($Items)) { if (-not [string]::IsNullOrWhiteSpace([string]$item)) { [void]$combo.Items.Add([string]$item) } }
    $combo.Text = $Value
    $combo.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $combo.BackColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24))
    $Parent.Controls.Add($combo)
    $Controls[$Key] = $combo
    return $combo
}

function Add-UGSMGameCS2CheckField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [bool]$Value, [int]$Row, [object]$Theme)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Left = 220
    $chk.Top = 16 + ($Row * 42)
    $chk.Width = 400
    $chk.Height = 24
    $chk.Text = $Label
    $chk.Checked = [bool]$Value
    $chk.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $chk.BackColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
    $Parent.Controls.Add($chk)
    $Controls[$Key] = $chk
    return $chk
}

function Save-UGSMGameCS2InstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$EditorState)
    $instance = $EditorState.Instance
    $controls = $EditorState.Controls
    $settings = Get-UGSMGameCS2Settings -Instance $instance
    foreach ($name in @('ServerName','Map','RconPassword','GSLT','ExtraArgs','ExtraServerCfg','MpFriendlyFire','MpTeammatesAreEnemies','MpSolidTeammates','SvDeadtalk','SvFullAlltalk','SvTalkEnemyDead','SvTalkEnemyLiving','SvCheats','BotQuota','BotQuotaMode','BotDifficulty','BotChatter','BotDeferToHumanGoals','BotDeferToHumanItems','MpStartMoney','MpMaxMoney','MpAfterroundmoney','CashTeamTWinBomb','CashTeamEliminationHostageMap','CashTeamEliminationBombMap','CashTeamLoserBonus','CashTeamLoserBonusConsecutiveRounds','CashPlayerKilledTeammate','CashPlayerKilledEnemyDefault','CashPlayerBombPlanted','CashPlayerBombDefused','MpMaxRounds','MpRoundTime','MpRoundTimeDefuse','MpRoundRestartDelay','MpFreezeTime','MpBuyTime','MpC4Timer','MpHalftime','MpOvertimeEnable','MpWarmupTime','MpRespawnOnDeathCT','MpRespawnOnDeathT','MpRandomspawn','MpDeathDropGun','MpDeathDropGrenade','MpDmBonusLengthMax','WorkshopCollectionId','WorkshopStartMap')) {
        if ($controls.ContainsKey($name)) { $settings.$name = [string]$controls[$name].Text }
    }
    foreach ($name in @('GameType','GameMode','MaxPlayers','GamePort','QueryPort','RconPort','TickRate')) {
        if ($controls.ContainsKey($name)) { $n = 0; if ([int]::TryParse([string]$controls[$name].Text, [ref]$n)) { $settings.$name = $n } }
    }
    foreach ($name in @('LanOnly')) { if ($controls.ContainsKey($name)) { $settings.$name = [bool]$controls[$name].Checked } }
    if ($controls.ContainsKey('DiscordWebhookUrl')) { $settings.Discord.WebhookUrl = [string]$controls['DiscordWebhookUrl'].Text }
    if ($controls.ContainsKey('NotifyOnStart')) { $settings.Discord.NotifyOnStart = [bool]$controls['NotifyOnStart'].Checked }
    if ($controls.ContainsKey('NotifyOnStop')) { $settings.Discord.NotifyOnStop = [bool]$controls['NotifyOnStop'].Checked }
    if ($controls.ContainsKey('ShowInDashboard')) { $settings.Discord.ShowInDashboard = [bool]$controls['ShowInDashboard'].Checked }
    return Save-UGSMGameCS2Settings -Instance $instance -Settings $settings
}

function New-UGSMGameCS2InstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][System.Windows.Forms.Control]$HostPanel, [AllowNull()][object]$Theme, [AllowNull()][System.Windows.Forms.Label]$StatusLabel)
    $instanceId = Get-UGSMGameCS2InstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameCS2Log -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.Multiline = $false
        $HostPanel.Controls.Add($tabs)
        $settings = Get-UGSMGameCS2Settings -Instance $Instance
        $controls = @{}
        $installedMaps = @(Get-UGSMGameCS2InstalledMaps -Instance $Instance)

        function New-CS2TabPanel {
            param([string]$Title)
            $tab = New-Object System.Windows.Forms.TabPage
            $tab.Text = $Title
            $panel = New-Object System.Windows.Forms.Panel
            $panel.Dock = 'Fill'
            $panel.AutoScroll = $true
            $panel.BackColor = $HostPanel.BackColor
            $tab.Controls.Add($panel)
            [void]$tabs.TabPages.Add($tab)
            return $panel
        }
        function Add-CS2Note {
            param([System.Windows.Forms.Panel]$Parent, [string]$Text, [int]$Top)
            $note = New-Object System.Windows.Forms.Label
            $note.Left = 24; $note.Top = $Top; $note.Width = 820; $note.Height = 42
            $note.Text = $Text
            $note.ForeColor = Get-UGSMGameCS2Color -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::LightGray)
            $note.BackColor = $Parent.BackColor
            $Parent.Controls.Add($note)
            return $note
        }

        $serverPanel = New-CS2TabPanel -Title 'Server'
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'ServerName' -Label 'Server name' -Value $settings.ServerName -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameCS2ComboField -Parent $serverPanel -Controls $controls -Key 'Map' -Label 'Bootstrap map' -Value $settings.Map -Items $installedMaps -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'GameType' -Label 'Game type' -Value ([string]$settings.GameType) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'GameMode' -Label 'Game mode' -Value ([string]$settings.GameMode) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'MaxPlayers' -Label 'Max players' -Value ([string]$settings.MaxPlayers) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'GamePort' -Label 'Game port' -Value ([string]$settings.GamePort) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'QueryPort' -Label 'Query port' -Value ([string]$settings.QueryPort) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'RconPort' -Label 'RCON port / reference' -Value ([string]$settings.RconPort) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'RconPassword' -Label 'RCON password' -Value $settings.RconPassword -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'GSLT' -Label 'Login token / GSLT' -Value $settings.GSLT -Row 9 -Theme $Theme | Out-Null
        Add-CS2Note -Parent $serverPanel -Text 'Public CS2 servers require a Steam Game Server Login Token. Create one with App ID 730. Tokens/passwords are not logged.' -Top 438 | Out-Null
        Add-UGSMGameCS2CheckField -Parent $serverPanel -Controls $controls -Key 'LanOnly' -Label 'LAN only' -Value ([bool]$settings.LanOnly) -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'TickRate' -Label 'Tick/update rate' -Value ([string]$settings.TickRate) -Row 12 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $serverPanel -Controls $controls -Key 'ExtraArgs' -Label 'Extra startup args' -Value $settings.ExtraArgs -Row 13 -Theme $Theme -Multiline -Height 70 | Out-Null

        $gameplayPanel = New-CS2TabPanel -Title 'Gameplay'
        Add-CS2Note -Parent $gameplayPanel -Text 'These values are saved as overrides in ugsm_<server>.cfg. Valve gamemode_*.cfg files are left untouched.' -Top 8 | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'MpFriendlyFire' -Label 'Friendly fire' -Value ([string]$settings.MpFriendlyFire) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'MpTeammatesAreEnemies' -Label 'Teammates are enemies' -Value ([string]$settings.MpTeammatesAreEnemies) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'MpSolidTeammates' -Label 'Solid teammates' -Value ([string]$settings.MpSolidTeammates) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'SvDeadtalk' -Label 'Dead talk' -Value ([string]$settings.SvDeadtalk) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'SvFullAlltalk' -Label 'Full alltalk' -Value ([string]$settings.SvFullAlltalk) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'SvTalkEnemyDead' -Label 'Enemy dead talk' -Value ([string]$settings.SvTalkEnemyDead) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'SvTalkEnemyLiving' -Label 'Enemy living talk' -Value ([string]$settings.SvTalkEnemyLiving) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $gameplayPanel -Controls $controls -Key 'SvCheats' -Label 'Cheats' -Value ([string]$settings.SvCheats) -Row 8 -Theme $Theme | Out-Null

        $botsPanel = New-CS2TabPanel -Title 'Bots'
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotQuota' -Label 'Bot quota' -Value ([string]$settings.BotQuota) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotQuotaMode' -Label 'Bot quota mode' -Value ([string]$settings.BotQuotaMode) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotDifficulty' -Label 'Bot difficulty' -Value ([string]$settings.BotDifficulty) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotChatter' -Label 'Bot chatter' -Value ([string]$settings.BotChatter) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotDeferToHumanGoals' -Label 'Defer goals' -Value ([string]$settings.BotDeferToHumanGoals) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $botsPanel -Controls $controls -Key 'BotDeferToHumanItems' -Label 'Defer items' -Value ([string]$settings.BotDeferToHumanItems) -Row 5 -Theme $Theme | Out-Null

        $economyPanel = New-CS2TabPanel -Title 'Economy'
        Add-CS2Note -Parent $economyPanel -Text 'Leave cash override boxes blank to let the selected CS2 game mode use Valve defaults.' -Top 8 | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'MpStartMoney' -Label 'Start money' -Value ([string]$settings.MpStartMoney) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'MpMaxMoney' -Label 'Max money' -Value ([string]$settings.MpMaxMoney) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'MpAfterroundmoney' -Label 'After-round money' -Value ([string]$settings.MpAfterroundmoney) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashTeamTWinBomb' -Label 'T win bomb cash' -Value ([string]$settings.CashTeamTWinBomb) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashTeamEliminationHostageMap' -Label 'Team elim hostage' -Value ([string]$settings.CashTeamEliminationHostageMap) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashTeamEliminationBombMap' -Label 'Team elim bomb' -Value ([string]$settings.CashTeamEliminationBombMap) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashTeamLoserBonus' -Label 'Loser bonus' -Value ([string]$settings.CashTeamLoserBonus) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashTeamLoserBonusConsecutiveRounds' -Label 'Loser bonus streak' -Value ([string]$settings.CashTeamLoserBonusConsecutiveRounds) -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashPlayerKilledTeammate' -Label 'Kill teammate cash' -Value ([string]$settings.CashPlayerKilledTeammate) -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashPlayerKilledEnemyDefault' -Label 'Kill enemy cash' -Value ([string]$settings.CashPlayerKilledEnemyDefault) -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashPlayerBombPlanted' -Label 'Bomb planted cash' -Value ([string]$settings.CashPlayerBombPlanted) -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $economyPanel -Controls $controls -Key 'CashPlayerBombDefused' -Label 'Bomb defused cash' -Value ([string]$settings.CashPlayerBombDefused) -Row 12 -Theme $Theme | Out-Null

        $matchPanel = New-CS2TabPanel -Title 'Match / Rounds'
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpMaxRounds' -Label 'Max rounds' -Value ([string]$settings.MpMaxRounds) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpRoundTime' -Label 'Round time' -Value ([string]$settings.MpRoundTime) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpRoundTimeDefuse' -Label 'Round time defuse' -Value ([string]$settings.MpRoundTimeDefuse) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpRoundRestartDelay' -Label 'Round restart delay' -Value ([string]$settings.MpRoundRestartDelay) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpFreezeTime' -Label 'Freeze time' -Value ([string]$settings.MpFreezeTime) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpBuyTime' -Label 'Buy time' -Value ([string]$settings.MpBuyTime) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpC4Timer' -Label 'C4 timer' -Value ([string]$settings.MpC4Timer) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpHalftime' -Label 'Halftime' -Value ([string]$settings.MpHalftime) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpOvertimeEnable' -Label 'Overtime enabled' -Value ([string]$settings.MpOvertimeEnable) -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $matchPanel -Controls $controls -Key 'MpWarmupTime' -Label 'Warmup time' -Value ([string]$settings.MpWarmupTime) -Row 9 -Theme $Theme | Out-Null

        $dmPanel = New-CS2TabPanel -Title 'Deathmatch / Respawn'
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpRespawnOnDeathCT' -Label 'Respawn CT' -Value ([string]$settings.MpRespawnOnDeathCT) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpRespawnOnDeathT' -Label 'Respawn T' -Value ([string]$settings.MpRespawnOnDeathT) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpRandomspawn' -Label 'Random spawn' -Value ([string]$settings.MpRandomspawn) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpDeathDropGun' -Label 'Death drop gun' -Value ([string]$settings.MpDeathDropGun) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpDeathDropGrenade' -Label 'Death drop grenade' -Value ([string]$settings.MpDeathDropGrenade) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $dmPanel -Controls $controls -Key 'MpDmBonusLengthMax' -Label 'DM bonus length max' -Value ([string]$settings.MpDmBonusLengthMax) -Row 5 -Theme $Theme | Out-Null

        $mapsPanel = New-CS2TabPanel -Title 'Mods / Workshop'
        Add-CS2Note -Parent $mapsPanel -Text 'For a single Workshop map, paste the Steam Workshop item ID into Workshop map ID. Server > Bootstrap map can stay on a vanilla installed map such as de_dust2; UGSM launches the Workshop map with +host_workshop_map.' -Top 8 | Out-Null
        Add-UGSMGameCS2Field -Parent $mapsPanel -Controls $controls -Key 'WorkshopCollectionId' -Label 'Workshop collection ID' -Value ([string]$settings.WorkshopCollectionId) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2Field -Parent $mapsPanel -Controls $controls -Key 'WorkshopStartMap' -Label 'Workshop map ID' -Value ([string]$settings.WorkshopStartMap) -Row 2 -Theme $Theme | Out-Null

        $cfgPanel = New-CS2TabPanel -Title 'Advanced CFG'
        Add-CS2Note -Parent $cfgPanel -Text 'Extra lines are appended to ugsm_<server>.cfg. Use this for settings not exposed in the tabs yet.' -Top 8 | Out-Null
        Add-UGSMGameCS2Field -Parent $cfgPanel -Controls $controls -Key 'ExtraServerCfg' -Label 'Extra server.cfg lines' -Value $settings.ExtraServerCfg -Row 1 -Theme $Theme -Multiline -Height 300 | Out-Null
        $discordTab = New-Object System.Windows.Forms.TabPage
        $discordTab.Text = 'Discord'
        $discordPanel = New-Object System.Windows.Forms.Panel
        $discordPanel.Dock = 'Fill'
        $discordPanel.AutoScroll = $true
        $discordPanel.BackColor = $HostPanel.BackColor
        $discordTab.Controls.Add($discordPanel)
        [void]$tabs.TabPages.Add($discordTab)
        Add-UGSMGameCS2Field -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value $settings.Discord.WebhookUrl -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameCS2CheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$settings.Discord.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameCS2CheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$settings.Discord.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameCS2CheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$settings.Discord.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $btnTestDiscord = New-Object System.Windows.Forms.Button
        $btnTestDiscord.Text = 'Test Discord'
        $btnTestDiscord.Left = 220; $btnTestDiscord.Top = 190; $btnTestDiscord.Width = 160; $btnTestDiscord.Height = 30
        $btnTestDiscord.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTestDiscord.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameCS2InstanceEditor -EditorState $st | Out-Null; if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null }; if ($st.StatusLabel) { $st.StatusLabel.Text = 'CS2 Discord test sent.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text = 'CS2 Discord test failed: ' + $_.Exception.Message }; Write-UGSMGameCS2Log -Level 'ERROR' -Message 'Discord test failed.' -Exception $_.Exception } })
        $discordPanel.Controls.Add($btnTestDiscord)

        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save Settings'
        $btnSave.Dock = 'Bottom'
        $btnSave.Height = 32
        $btnSave.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameCS2InstanceEditor -EditorState $st | Out-Null; if ($st.StatusLabel) { $st.StatusLabel.Text = 'CS2 settings saved.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text = 'CS2 save failed: ' + $_.Exception.Message }; Write-UGSMGameCS2Log -Level 'ERROR' -Message 'CS2 editor save failed.' -Exception $_.Exception } })
        $HostPanel.Controls.Add($btnSave)
        $btnSave.BringToFront()
        $sw.Stop()
        Write-UGSMGameCS2Log -Level 'INFO' -Message ("Editor creation completed. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)")
        return [pscustomobject]@{ Success=$true; Controls=$controls }
    } catch {
        Write-UGSMGameCS2Log -Level 'ERROR' -Message ("Editor creation failed. InstanceId=$instanceId") -Exception $_.Exception
        throw
    } finally {
        $HostPanel.ResumeLayout($true)
    }
}

function Register-UGSMGameCS2Module {
    [CmdletBinding()]
    param()
    $metadata = Get-UGSMGameCS2Metadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameCS2Metadata'
            TestInstall       = 'Test-UGSMGameCS2Install'
            TestInstance      = 'Test-UGSMGameCS2Instance'
            InitializeProfile = 'Initialize-UGSMGameCS2Profile'
            Start             = 'Start-UGSMGameCS2Instance'
            Stop              = 'Stop-UGSMGameCS2Instance'
            BuildEditor       = 'New-UGSMGameCS2InstanceEditor'
            SaveEditor        = 'Save-UGSMGameCS2InstanceEditor'
        }
    }
}
