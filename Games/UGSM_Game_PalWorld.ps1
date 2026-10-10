
# Palworld dedicated server module
# First functional pass: install/create/start/stop, server editor, Steam Workshop mod config, Discord tab.
# Privacy: passwords/tokens/webhooks are not written to UGSM logs by this module.

function Write-UGSMGamePalWorldLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerbosePalWorldLogging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_PALWORLD)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'PalWorld' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'PalWorld' -Message $Message }
        return
    }
    if ($Exception) { Write-Warning ("[PalWorld] $Message :: $($Exception.Message)") } else { Write-Host "[PalWorld][$Level] $Message" }
}

function Get-UGSMGamePalWorldMetadata {
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Id                       = 'PalWorld'
        Name                     = 'Palworld'
        Category                 = 'Survival'
        Description              = 'Palworld Dedicated Server integration.'
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
        SteamAppId               = '2394010'
        SteamStoreAppId          = '1623730'
        ServerExecutable         = 'PalServer.exe'
        ServerExecutableRelative = 'PalServer.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'Pal\Saved\Config\WindowsServer'
        SaveRootRelative         = 'Pal\Saved\SaveGames'
        LogRootRelative          = 'Pal\Saved\Logs'
        RequiredFiles            = @('PalServer.exe')
        InstallMarkers           = @('PalServer.exe')
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 8211 },
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27015 },
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 25575 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $true
            UsesJsonFiles         = $false
            UsesXmlFiles          = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $false
            UsesFolderCopyMods    = $true
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $true
        }
        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'SteamCMD app id 2394010 installs Palworld Dedicated Server using anonymous login.',
                'UGSM uses shared PalServer.exe binaries and per-profile Saved data via a junction.',
                'Palworld Steam Workshop server mods are configured through Mods/PalModSettings.ini with ActiveModList package names.',
                'Workshop items must contain server-compatible Palworld mod metadata. Only server-side compatible mods should be enabled.'
            )
        }
    }
}

function Get-UGSMGamePalWorldInstanceId { param([AllowNull()][object]$Instance) if (-not $Instance) { return '' }; foreach ($name in @('Id','Name','ProfileName','InstanceId')) { if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name } }; return '' }
function Get-UGSMGamePalWorldProfileName { param([AllowNull()][object]$Instance) $name=Get-UGSMGamePalWorldInstanceId -Instance $Instance; if ([string]::IsNullOrWhiteSpace($name)) { $name='PalWorld1' }; $safe=$name -replace '[^A-Za-z0-9_.-]','_'; if ([string]::IsNullOrWhiteSpace($safe)) { $safe='PalWorld1' }; return $safe }
function Get-UGSMGamePalWorldAppDataRoot { if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { return [string](Get-UGSMAppDataRoot) }; return (Join-Path $env:LOCALAPPDATA 'UGSM') }
function Get-UGSMGamePalWorldProfileBaseRoot { $settings=$null; if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings=Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings=$null } }; if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }; if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) { $probe=Get-UGSMDefaultInstanceProfilePath -GameId 'PalWorld' -Name '_probe_'; if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) } }; return (Join-Path (Get-UGSMGamePalWorldAppDataRoot) 'Profiles') }
function Get-UGSMGamePalWorldProfileRoot { param([Parameter(Mandatory)][string]$ProfileName) return (Join-Path (Join-Path (Get-UGSMGamePalWorldProfileBaseRoot) 'PalWorld') $ProfileName) }

function Get-UGSMGamePalWorldInstallPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$InstallPath)

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return $InstallPath }
    if ($Instance -and $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) { return [string]$Instance.InstallPath }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $names = @('PalServer','Palworld Dedicated Server','PalWorld Dedicated Server','Palworld')
    $candidateRoots = New-Object System.Collections.Generic.List[string]

    if ($settings) {
        foreach ($propName in @('SteamLibraryRoot','SteamRoot','SteamCmdRoot','InstallRoot')) {
            if ($settings.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propName)) {
                $base = ([string]$settings.$propName).TrimEnd('\','/')
                if (-not [string]::IsNullOrWhiteSpace($base)) {
                    foreach ($n in $names) {
                        [void]$candidateRoots.Add((Join-Path $base ("steamapps\common\$n")))
                    }
                }
            }
        }
    }

    foreach ($candidate in ($candidateRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        try {
            if (Test-Path -LiteralPath (Join-Path $candidate 'PalServer.exe') -PathType Leaf) { return $candidate }
        } catch {}
    }

    # Portable fallback: return a configured Steam root default only when the user has selected one.
    if ($settings -and $settings.PSObject.Properties['SteamLibraryRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.SteamLibraryRoot)) {
        return (Join-Path (([string]$settings.SteamLibraryRoot).TrimEnd('\','/')) 'steamapps\common\PalServer')
    }

    return ''
}

function Get-UGSMGamePalWorldInstallDefinition { param([string]$InstallPath,[AllowNull()][object]$Instance) $root=Get-UGSMGamePalWorldInstallPath -Instance $Instance -InstallPath $InstallPath; return [pscustomobject]@{ InstallPath=$root; ServerExecutablePath=Join-Path $root 'PalServer.exe'; SavedRoot=Join-Path $root 'Pal\Saved'; ConfigRoot=Join-Path $root 'Pal\Saved\Config\WindowsServer'; ModsRoot=Join-Path $root 'Mods'; WorkshopRoot=Join-Path $root 'Mods\Workshop'; PalModSettingsPath=Join-Path $root 'Mods\PalModSettings.ini' } }
function Test-UGSMGamePalWorldInstall { param([string]$InstallPath,[AllowNull()][object]$Instance) $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance; $ok=Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf; return [pscustomobject]@{ Success=[bool]$ok; IsInstalled=[bool]$ok; InstallPath=$d.InstallPath; ServerExecutablePath=$d.ServerExecutablePath; Message=if($ok){'Palworld Dedicated Server install detected.'}else{'Palworld Dedicated Server was not detected.'} } }

function Get-UGSMGamePalWorldAssignedPort { param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$Name,[int]$Default) foreach ($propName in @('Ports','AssignedPorts')) { if (-not ($Instance.PSObject.Properties[$propName])) { continue }; $ports=$Instance.$propName; if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) { $entry=$ports[$Name]; if ($entry -is [int]) { return [int]$entry }; if ($entry -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port } } elseif ($ports) { foreach ($entry in @($ports)) { if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port } } } }; return $Default }

function Get-UGSMGamePalWorldProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $profileName=Get-UGSMGamePalWorldProfileName -Instance $Instance
    $profileRoot=Get-UGSMGamePalWorldProfileRoot -ProfileName $profileName
    $savedRoot=Join-Path $profileRoot 'Saved'
    $logsRoot=Join-Path $profileRoot 'Logs'
    $centralLogRoot=Join-Path (Join-Path (Get-UGSMGamePalWorldAppDataRoot) 'Logs\PalWorld') $profileName
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance
    return [pscustomobject]@{
        ProfileName=$profileName
        ProfileRoot=$profileRoot
        SavedRoot=$savedRoot
        LogsRoot=$logsRoot
        CentralLogRoot=$centralLogRoot
        SettingsPath=Join-Path $profileRoot 'UGSM_PalWorldSettings.json'
        PalWorldSettingsPath=Join-Path $savedRoot 'Config\WindowsServer\PalWorldSettings.ini'
        LauncherPath=Join-Path $logsRoot 'UGSM_Start_PalWorld.cmd'
        LaunchLogPath=Join-Path $centralLogRoot 'server-launch.log'
        InstallSavedRoot=$d.SavedRoot
        InstallConfigRoot=$d.ConfigRoot
    }
}

function ConvertFrom-UGSMGamePalWorldMultilineList { param([AllowNull()][string]$Text) if ([string]::IsNullOrWhiteSpace($Text)) { return @() }; return @($Text -split "`r?`n|,|;" | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
function ConvertTo-UGSMGamePalWorldMultilineText { param([AllowNull()][object]$Values) if (-not $Values) { return '' }; return (@($Values) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine }

function Get-UGSMGamePalWorldDefaultSettings {
    param([Parameter(Mandatory)][object]$Instance)
    $profileName=Get-UGSMGamePalWorldProfileName -Instance $Instance
    return [pscustomobject]@{
        ServerName=$profileName
        ServerDescription='UGSM Palworld server'
        AdminPassword='changeme'
        ServerPassword=''
        GamePort=Get-UGSMGamePalWorldAssignedPort -Instance $Instance -Name 'GamePort' -Default 8211
        QueryPort=Get-UGSMGamePalWorldAssignedPort -Instance $Instance -Name 'QueryPort' -Default 27015
        RconEnabled=$true
        RconPort=Get-UGSMGamePalWorldAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575
        MaxPlayers=32
        PublicIP=''
        PublicPort=8211
        CommunityServer=$true
        Region=''
        UseMultithreadForDS=$true
        UsePerfThreads=$true
        NoAsyncLoadingThread=$true
        ExtraArgs=''
        WorkshopIds=@()
        ActiveModPackages=@()
        WorkshopRootDir=''
        EnableMods=$true
        Discord=[pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false }
    }
}

function Get-UGSMGamePalWorldSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $InstallPath
    $default=Get-UGSMGamePalWorldDefaultSettings -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)) { return $default }
    try {
        $loaded=Get-Content -LiteralPath $paths.SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $default.PSObject.Properties.Name) { if (-not $loaded.PSObject.Properties[$prop]) { Add-Member -InputObject $loaded -MemberType NoteProperty -Name $prop -Value $default.$prop -Force } }
        if (-not $loaded.Discord) { $loaded.Discord=$default.Discord }
        foreach ($prop in $default.Discord.PSObject.Properties.Name) { if (-not $loaded.Discord.PSObject.Properties[$prop]) { Add-Member -InputObject $loaded.Discord -MemberType NoteProperty -Name $prop -Value $default.Discord.$prop -Force } }
        foreach ($portName in @('GamePort','QueryPort','RconPort')) { $assigned=Get-UGSMGamePalWorldAssignedPort -Instance $Instance -Name $portName -Default ([int]$default.$portName); if (($loaded.$portName -as [int]) -le 0) { $loaded.$portName=$assigned } }
        if (($loaded.PublicPort -as [int]) -le 0) { $loaded.PublicPort=$loaded.GamePort }
        return $loaded
    } catch {
        Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Failed to read Palworld settings. Defaults will be used.' -Exception $_.Exception
        return $default
    }
}

function Save-UGSMGamePalWorldJsonFile { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value) $dir=Split-Path -Parent $Path; if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function ConvertTo-UGSMGamePalWorldIniValue { param([AllowNull()][object]$Value) if ($Value -is [bool]) { return ($(if($Value){'True'}else{'False'})) }; if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }; $s=[string]$Value; return ('"{0}"' -f ($s.Replace('"','"'))) }

function Save-UGSMGamePalWorldServerIni {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Paths,[Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Paths.PalWorldSettingsPath) | Out-Null
    $pairs=[ordered]@{
        Difficulty='None'
        DayTimeSpeedRate=1.000000
        NightTimeSpeedRate=1.000000
        ExpRate=1.000000
        PalCaptureRate=1.000000
        PalSpawnNumRate=1.000000
        PalDamageRateAttack=1.000000
        PalDamageRateDefense=1.000000
        PlayerDamageRateAttack=1.000000
        PlayerDamageRateDefense=1.000000
        PlayerStomachDecreaceRate=1.000000
        PlayerStaminaDecreaceRate=1.000000
        PlayerAutoHPRegeneRate=1.000000
        PlayerAutoHpRegeneRateInSleep=1.000000
        PalStomachDecreaceRate=1.000000
        PalStaminaDecreaceRate=1.000000
        PalAutoHPRegeneRate=1.000000
        PalAutoHpRegeneRateInSleep=1.000000
        BuildObjectDamageRate=1.000000
        BuildObjectDeteriorationDamageRate=1.000000
        CollectionDropRate=1.000000
        CollectionObjectHpRate=1.000000
        CollectionObjectRespawnSpeedRate=1.000000
        EnemyDropItemRate=1.000000
        DeathPenalty='All'
        bEnablePlayerToPlayerDamage=$false
        bEnableFriendlyFire=$false
        bEnableInvaderEnemy=$true
        bActiveUNKO=$false
        bEnableAimAssistPad=$true
        bEnableAimAssistKeyboard=$false
        DropItemMaxNum=3000
        DropItemMaxNum_UNKO=100
        BaseCampMaxNum=128
        BaseCampWorkerMaxNum=15
        DropItemAliveMaxHours=1.000000
        bAutoResetGuildNoOnlinePlayers=$false
        AutoResetGuildTimeNoOnlinePlayers=72.000000
        GuildPlayerMaxNum=20
        PalEggDefaultHatchingTime=72.000000
        WorkSpeedRate=1.000000
        bIsMultiplay=$false
        bIsPvP=$false
        bCanPickupOtherGuildDeathPenaltyDrop=$false
        bEnableNonLoginPenalty=$true
        bEnableFastTravel=$true
        bIsStartLocationSelectByMap=$true
        bExistPlayerAfterLogout=$false
        bEnableDefenseOtherGuildPlayer=$false
        CoopPlayerMaxNum=4
        ServerPlayerMaxNum=[int]$Settings.MaxPlayers
        ServerName=[string]$Settings.ServerName
        ServerDescription=[string]$Settings.ServerDescription
        AdminPassword=[string]$Settings.AdminPassword
        ServerPassword=[string]$Settings.ServerPassword
        PublicPort=[int]$Settings.PublicPort
        PublicIP=[string]$Settings.PublicIP
        RCONEnabled=[bool]$Settings.RconEnabled
        RCONPort=[int]$Settings.RconPort
        Region=[string]$Settings.Region
        bUseAuth=$true
        BanListURL='https://api.palworldgame.com/api/banlist.txt'
    }
    $items=@()
    foreach ($k in $pairs.Keys) { $items += ("{0}={1}" -f $k,(ConvertTo-UGSMGamePalWorldIniValue -Value $pairs[$k])) }
    $line='[/Script/Pal.PalGameWorldSettings]' + [Environment]::NewLine + 'OptionSettings=(' + ($items -join ',') + ')'
    Set-Content -LiteralPath $Paths.PalWorldSettingsPath -Value $line -Encoding UTF8
}

function Save-UGSMGamePalWorldModSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Definition,[Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path $Definition.ModsRoot,$Definition.WorkshopRoot | Out-Null
    $active=@($Settings.ActiveModPackages) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $workshopRoot=[string]$Settings.WorkshopRootDir
    if ([string]::IsNullOrWhiteSpace($workshopRoot)) { $workshopRoot=$Definition.WorkshopRoot }
    $lines=@('[PalModSettings]', ('bGlobalEnableMod={0}' -f ($(if([bool]$Settings.EnableMods){'true'}else{'false'}))))
    foreach ($pkg in $active) { $lines += ('ActiveModList={0}' -f $pkg.Trim()) }
    if (-not [string]::IsNullOrWhiteSpace($workshopRoot)) { $lines += ('WorkshopRootDir={0}' -f $workshopRoot) }
    Set-Content -LiteralPath $Definition.PalModSettingsPath -Value $lines -Encoding UTF8
    # Keep a simple UGSM record of Workshop IDs. The Palworld server uses PackageName entries from Info.json for activation.
    $ids=@($Settings.WorkshopIds) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    Set-Content -LiteralPath (Join-Path $Definition.ModsRoot 'UGSM_WorkshopIds.txt') -Value $ids -Encoding UTF8
}

function Save-UGSMGamePalWorldSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][object]$Settings,[string]$InstallPath)
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $d.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot,$paths.SavedRoot,(Split-Path -Parent $paths.PalWorldSettingsPath),$paths.LogsRoot,$paths.CentralLogRoot | Out-Null
    Save-UGSMGamePalWorldJsonFile -Path $paths.SettingsPath -Value $Settings
    Save-UGSMGamePalWorldServerIni -Paths $paths -Settings $Settings
    Save-UGSMGamePalWorldModSettings -Definition $d -Settings $Settings
    return [pscustomobject]@{ Success=$true; SettingsPath=$paths.SettingsPath; PalWorldSettingsPath=$paths.PalWorldSettingsPath; PalModSettingsPath=$d.PalModSettingsPath }
}

function Ensure-UGSMGamePalWorldSavedLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $d.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.SavedRoot,(Split-Path -Parent $paths.PalWorldSettingsPath) | Out-Null
    if (Test-Path -LiteralPath $d.SavedRoot) {
        $item=Get-Item -LiteralPath $d.SavedRoot -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $d.SavedRoot }
        $backup=Join-Path $d.InstallPath ('Pal\Saved_UGSM_Backup_' + (Get-Date -Format 'yyyyMMddHHmmss'))
        try { Rename-Item -LiteralPath $d.SavedRoot -NewName (Split-Path -Leaf $backup) -ErrorAction Stop } catch { Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Could not move existing Palworld Saved folder. Existing data may be used.' -Exception $_.Exception; return $d.SavedRoot }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d.SavedRoot) | Out-Null
    try { New-Item -ItemType Junction -Path $d.SavedRoot -Target $paths.SavedRoot -Force | Out-Null } catch { Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Failed to create Palworld Saved junction. Falling back to install Saved folder.' -Exception $_.Exception; New-Item -ItemType Directory -Force -Path $d.SavedRoot | Out-Null }
    return $d.SavedRoot
}

function Initialize-UGSMGamePalWorldProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath,[switch]$Force,[int]$BootstrapSeconds=0)
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $d.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot,$paths.SavedRoot,(Split-Path -Parent $paths.PalWorldSettingsPath),$paths.LogsRoot,$paths.CentralLogRoot | Out-Null
    Ensure-UGSMGamePalWorldSavedLink -Instance $Instance -InstallPath $d.InstallPath | Out-Null
    if ($Instance.PSObject.Properties['ProfilePath']) { $Instance.ProfilePath=$paths.ProfileRoot } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProfilePath -Value $paths.ProfileRoot -Force }
    if ($Instance.PSObject.Properties['InstallPath']) { $Instance.InstallPath=$d.InstallPath } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name InstallPath -Value $d.InstallPath -Force }
    $settings=Get-UGSMGamePalWorldSettings -Instance $Instance -InstallPath $d.InstallPath
    if ($Force -or -not (Test-Path -LiteralPath $paths.SettingsPath)) { $settings=Get-UGSMGamePalWorldDefaultSettings -Instance $Instance }
    if (($settings.PublicPort -as [int]) -le 0) { $settings.PublicPort=$settings.GamePort }
    Save-UGSMGamePalWorldSettings -Instance $Instance -Settings $settings -InstallPath $d.InstallPath | Out-Null
    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Profile initialized. InstanceId=$(Get-UGSMGamePalWorldInstanceId -Instance $Instance)")
    return [pscustomobject]@{ Success=$true; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.PalWorldSettingsPath }
}

function Test-UGSMGamePalWorldInstance { param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath) $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $InstallPath; $ok=Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf; return [pscustomobject]@{ Success=[bool]$ok; Exists=[bool]$ok; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.PalWorldSettingsPath; Message=if($ok){'Palworld profile exists.'}else{'Palworld profile has not been initialized.'} } }

function ConvertTo-UGSMGamePalWorldArgString {
    param([Parameter(Mandatory)][object]$Settings)
    $args=@('-log')
    if ([bool]$Settings.UsePerfThreads) { $args += '-useperfthreads' }
    if ([bool]$Settings.NoAsyncLoadingThread) { $args += '-NoAsyncLoadingThread' }
    if ([bool]$Settings.UseMultithreadForDS) { $args += '-UseMultithreadForDS' }
    if ([bool]$Settings.CommunityServer) { $args += '-publiclobby' }
    if (([int]$Settings.GamePort) -gt 0) { $args += ('-port={0}' -f ([int]$Settings.GamePort)) }
    if (([int]$Settings.QueryPort) -gt 0) { $args += ('-queryport={0}' -f ([int]$Settings.QueryPort)) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraArgs)) { $args += [string]$Settings.ExtraArgs }
    return ($args -join ' ')
}

function New-UGSMGamePalWorldLaunchWrapper {
    param([Parameter(Mandatory)][string]$InstallPath,[Parameter(Mandatory)][object]$Paths,[Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path $Paths.LogsRoot,$Paths.CentralLogRoot | Out-Null
    $argString=ConvertTo-UGSMGamePalWorldArgString -Settings $Settings
    $lines=@('@echo off','setlocal enableextensions',('cd /d "{0}"' -f $InstallPath),('echo [%date% %time%] UGSM Palworld launcher started. Profile={0}' -f $Paths.ProfileName),('"{0}" {1}' -f (Join-Path $InstallPath 'PalServer.exe'),$argString),'set EXITCODE=%ERRORLEVEL%','echo [%date% %time%] UGSM Palworld launcher exited with code %EXITCODE%.','exit /b %EXITCODE%')
    Set-Content -LiteralPath $Paths.LauncherPath -Value $lines -Encoding ASCII
    return $Paths.LauncherPath
}

function Find-UGSMGamePalWorldServerProcess {
    [CmdletBinding()]
    param([int]$GamePort=0,[string]$InstallPath)
    $names=@('PalServer-Win64-Shipping-Cmd.exe','PalServer-Win64-Test-Cmd.exe','PalServer-Win64-Shipping.exe','PalServer.exe','BootstrapPackagedGame.exe')
    try {
        $items=Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.Name }
        if ($GamePort -gt 0) {
            $matched=@($items | Where-Object { $_.CommandLine -match ('-port=' + [Regex]::Escape([string]$GamePort)) })
            if ($matched.Count -gt 0) { return $matched[0] }
        }
        if (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
            $safe=[Regex]::Escape($InstallPath)
            $matched=@($items | Where-Object { $_.ExecutablePath -match $safe -or $_.CommandLine -match $safe })
            if ($matched.Count -gt 0) { return $matched[0] }
        }
    } catch {}
    return $null
}

function Start-UGSMGamePalWorldInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $instanceId=Get-UGSMGamePalWorldInstanceId -Instance $Instance
    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf)) { throw "PalServer.exe was not found: $($d.ServerExecutablePath)" }
    Initialize-UGSMGamePalWorldProfile -Instance $Instance -InstallPath $d.InstallPath | Out-Null
    $paths=Get-UGSMGamePalWorldProfilePaths -Instance $Instance -InstallPath $d.InstallPath
    $settings=Get-UGSMGamePalWorldSettings -Instance $Instance -InstallPath $d.InstallPath
    Save-UGSMGamePalWorldSettings -Instance $Instance -Settings $settings -InstallPath $d.InstallPath | Out-Null
    $argString=ConvertTo-UGSMGamePalWorldArgString -Settings $settings
    try {
        Set-Content -LiteralPath $paths.LaunchLogPath -Value @(
            ("[{0}] UGSM starting Palworld." -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
            'Launcher: direct PalServer.exe',
            ('Profile: {0}' -f $paths.ProfileName),
            ('GamePort: {0}' -f $settings.GamePort),
            ('QueryPort: {0}' -f $settings.QueryPort),
            ('RconPort: {0}' -f $settings.RconPort),
            ''
        ) -Encoding UTF8
    } catch {}
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$d.ServerExecutablePath
    $psi.WorkingDirectory=$d.InstallPath
    $psi.Arguments=$argString
    $psi.UseShellExecute=$true
    $process=[System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'Palworld process failed to start.' }
    Start-Sleep -Seconds 8
    $serverProc=Find-UGSMGamePalWorldServerProcess -GamePort ([int]$settings.GamePort) -InstallPath $d.InstallPath
    $trackedPid=[int]$process.Id
    if ($serverProc -and $serverProc.ProcessId) { $trackedPid=[int]$serverProc.ProcessId }
    else {
        try { $process.Refresh(); if ($process.HasExited) { throw "Palworld launcher exited and no Palworld server process was found. Check $($paths.LaunchLogPath)." } } catch { throw }
    }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId=$trackedPid } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value $trackedPid -Force }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status='Running' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Running' -Force }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Discord start notification failed.' -Exception $_.Exception } }
    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$trackedPid")
    return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=$trackedPid }
}


function Read-UGSMGamePalWorldRconBytes {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$Count
    )
    $readTotal = 0
    while ($readTotal -lt $Count) {
        $read = $Stream.Read($Buffer, $Offset + $readTotal, $Count - $readTotal)
        if ($read -le 0) { throw 'RCON connection closed unexpectedly.' }
        $readTotal += $read
    }
}

function Send-UGSMGamePalWorldRconPacket {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][int]$RequestId,
        [Parameter(Mandatory)][int]$Type,
        [AllowNull()][string]$Body
    )
    if ($null -eq $Body) { $Body = '' }
    $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $size = 4 + 4 + $bodyBytes.Length + 2
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int]$size)
    $bw.Write([int]$RequestId)
    $bw.Write([int]$Type)
    $bw.Write($bodyBytes)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Flush()
    $bytes = $ms.ToArray()
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
}

function Receive-UGSMGamePalWorldRconPacket {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)
    $lenBytes = New-Object byte[] 4
    Read-UGSMGamePalWorldRconBytes -Stream $Stream -Buffer $lenBytes -Offset 0 -Count 4
    $size = [BitConverter]::ToInt32($lenBytes, 0)
    if ($size -lt 10 -or $size -gt 1048576) { throw "Invalid RCON packet size: $size" }
    $payload = New-Object byte[] $size
    Read-UGSMGamePalWorldRconBytes -Stream $Stream -Buffer $payload -Offset 0 -Count $size
    $id = [BitConverter]::ToInt32($payload, 0)
    $type = [BitConverter]::ToInt32($payload, 4)
    $bodyLen = [Math]::Max(0, $size - 10)
    $body = ''
    if ($bodyLen -gt 0) { $body = [System.Text.Encoding]::ASCII.GetString($payload, 8, $bodyLen) }
    return [pscustomobject]@{ Id=$id; Type=$type; Body=$body }
}

function Invoke-UGSMGamePalWorldRconCommand {
    [CmdletBinding()]
    param(
        [string]$HostName = '127.0.0.1',
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutMs = 2500
    )
    if ([string]::IsNullOrWhiteSpace($Password)) { throw 'RCON password is blank.' }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { throw "RCON connection timed out on port $Port." }
        $client.EndConnect($iar)
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs
        $stream = $client.GetStream()

        # Source RCON: SERVERDATA_AUTH = 3, SERVERDATA_EXECCOMMAND = 2.
        Send-UGSMGamePalWorldRconPacket -Stream $stream -RequestId 1001 -Type 3 -Body $Password
        $auth1 = Receive-UGSMGamePalWorldRconPacket -Stream $stream
        $auth2 = Receive-UGSMGamePalWorldRconPacket -Stream $stream
        if ($auth1.Id -eq -1 -or $auth2.Id -eq -1) { throw 'RCON authentication failed.' }

        Send-UGSMGamePalWorldRconPacket -Stream $stream -RequestId 1002 -Type 2 -Body $Command
        $response = Receive-UGSMGamePalWorldRconPacket -Stream $stream
        return [pscustomobject]@{ Success=$true; Response=$response.Body }
    } finally {
        try { $client.Close() } catch {}
    }
}

function Stop-UGSMGamePalWorldInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)

    $instanceId=Get-UGSMGamePalWorldInstanceId -Instance $Instance
    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId")

    $settings=Get-UGSMGamePalWorldSettings -Instance $Instance -InstallPath $InstallPath
    $d=Get-UGSMGamePalWorldInstallDefinition -InstallPath $InstallPath -Instance $Instance

    $palNames=@(
        'PalServer-Win64-Shipping-Cmd.exe',
        'PalServer-Win64-Test-Cmd.exe',
        'PalServer-Win64-Shipping.exe',
        'PalServer.exe',
        'BootstrapPackagedGame.exe'
    )

    $targetIds = New-Object System.Collections.Generic.List[int]

    function Add-UGSMPalworldStopTarget {
        param([object]$ProcessInfo,[string]$SafeInstall,[System.Collections.Generic.List[int]]$List,[string[]]$Names)
        if (-not $ProcessInfo) { return }
        $procId = [int]$ProcessInfo.ProcessId
        if ($procId -le 0) { return }
        if ($procId -eq [int]$PID) { return }
        $procName = [string]$ProcessInfo.Name
        $exe = [string]$ProcessInfo.ExecutablePath
        $cmd = [string]$ProcessInfo.CommandLine
        $isPalName = $Names -contains $procName
        $isFromInstall = $false
        if (-not [string]::IsNullOrWhiteSpace($SafeInstall)) {
            $isFromInstall = (($exe -match $SafeInstall) -or ($cmd -match $SafeInstall))
        }
        if (($isPalName -or $isFromInstall) -and -not $List.Contains($procId)) {
            $List.Add($procId) | Out-Null
        }
    }

    function Get-UGSMPalworldStopTargets {
        param([object]$Instance,[object]$Settings,[object]$Definition,[string[]]$Names)
        $list = New-Object System.Collections.Generic.List[int]
        try {
            $safeInstall = ''
            if (-not [string]::IsNullOrWhiteSpace($Definition.InstallPath)) { $safeInstall=[Regex]::Escape($Definition.InstallPath) }

            $seedIds=@()
            if ($Instance.PSObject.Properties['ProcessId'] -and $Instance.ProcessId) { $seedIds += [int]$Instance.ProcessId }

            $found=Find-UGSMGamePalWorldServerProcess -GamePort ([int]$Settings.GamePort) -InstallPath $Definition.InstallPath
            if ($found -and $found.ProcessId) { $seedIds += [int]$found.ProcessId }

            foreach ($seedId in @($seedIds | Sort-Object -Unique)) {
                $info = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [string]$seedId) -ErrorAction SilentlyContinue
                Add-UGSMPalworldStopTarget -ProcessInfo $info -SafeInstall $safeInstall -List $list -Names $Names

                if ($info) {
                    $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + [string]$info.ProcessId) -ErrorAction SilentlyContinue)
                    foreach ($child in $children) { Add-UGSMPalworldStopTarget -ProcessInfo $child -SafeInstall $safeInstall -List $list -Names $Names }

                    if ($info.ParentProcessId -gt 0) {
                        $parent = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [string]$info.ParentProcessId) -ErrorAction SilentlyContinue
                        Add-UGSMPalworldStopTarget -ProcessInfo $parent -SafeInstall $safeInstall -List $list -Names $Names
                    }
                }
            }

            foreach ($name in $Names) {
                $matches=@(Get-CimInstance Win32_Process -Filter ("Name='" + $name.Replace("'","''") + "'") -ErrorAction SilentlyContinue)
                foreach ($match in $matches) { Add-UGSMPalworldStopTarget -ProcessInfo $match -SafeInstall $safeInstall -List $list -Names $Names }
            }
        } catch {
            Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Could not safely build Palworld stop target list.' -Exception $_.Exception
        }
        return @($list.ToArray() | Sort-Object -Unique)
    }

    $ids = @(Get-UGSMPalworldStopTargets -Instance $Instance -Settings $settings -Definition $d -Names $palNames)
    Write-UGSMGamePalWorldLog -Level 'DEBUG' -Message ("Stop targets resolved. InstanceId=$instanceId; Count=$($ids.Count)")

    $gracefulSent = $false
    $stopped = $false

    if ([bool]$settings.RconEnabled -and -not [string]::IsNullOrWhiteSpace([string]$settings.AdminPassword) -and ([int]$settings.RconPort -gt 0)) {
        try {
            Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Attempting graceful RCON shutdown. InstanceId=$instanceId; RconPort=$($settings.RconPort)")
            Invoke-UGSMGamePalWorldRconCommand -Port ([int]$settings.RconPort) -Password ([string]$settings.AdminPassword) -Command 'Broadcast Server_shutdown_in_10_seconds' | Out-Null
            Invoke-UGSMGamePalWorldRconCommand -Port ([int]$settings.RconPort) -Password ([string]$settings.AdminPassword) -Command 'Save' | Out-Null
            Invoke-UGSMGamePalWorldRconCommand -Port ([int]$settings.RconPort) -Password ([string]$settings.AdminPassword) -Command 'Shutdown 10 UGSM_shutdown' | Out-Null
            $gracefulSent = $true
        } catch {
            Write-UGSMGamePalWorldLog -Level 'WARN' -Message ("Graceful RCON shutdown failed. InstanceId=$instanceId; falling back to process stop after wait.") -Exception $_.Exception
        }
    } else {
        Write-UGSMGamePalWorldLog -Level 'WARN' -Message ("Graceful RCON shutdown skipped. InstanceId=$instanceId; RCON disabled, blank admin password, or missing RCON port.")
    }

    if ($gracefulSent) {
        $deadline = (Get-Date).AddSeconds(18)
        do {
            Start-Sleep -Milliseconds 750
            $remaining = @(Get-UGSMPalworldStopTargets -Instance $Instance -Settings $settings -Definition $d -Names $palNames)
            if ($remaining.Count -eq 0) { $stopped = $true; break }
        } while ((Get-Date) -lt $deadline)
        $ids = @(Get-UGSMPalworldStopTargets -Instance $Instance -Settings $settings -Definition $d -Names $palNames)
    }

    if ($ids.Count -gt 0) {
        Write-UGSMGamePalWorldLog -Level 'WARN' -Message ("Palworld still running after graceful stop window; forcing remaining processes. InstanceId=$instanceId; Count=$($ids.Count)")
        foreach ($targetProcessId in $ids) {
            try {
                Stop-Process -Id $targetProcessId -Force -ErrorAction Stop
                $stopped=$true
                Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Stopped Palworld process. InstanceId=$instanceId; ProcessId=$targetProcessId")
            } catch [System.ArgumentException] {
                $stopped=$true
            } catch {
                Write-UGSMGamePalWorldLog -Level 'ERROR' -Message ("Stop failed. InstanceId=$instanceId; ProcessId=$targetProcessId") -Exception $_.Exception
            }
        }
    } elseif (-not $stopped) {
        $stopped = $true
    }

    if ($Instance.PSObject.Properties['Status']) { $Instance.Status='Stopped' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Stopped' -Force }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId=$null }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGamePalWorldLog -Level 'WARN' -Message 'Discord stop notification failed.' -Exception $_.Exception }
    }

    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Stop completed. InstanceId=$instanceId; Stopped=$stopped; GracefulRcon=$gracefulSent")
    return [pscustomobject]@{ Success=$true; Status='Stopped'; Stopped=[bool]$stopped; GracefulRcon=[bool]$gracefulSent }
}



function Get-UGSMGamePalWorldColor { param([AllowNull()][object]$Theme,[Parameter(Mandatory)][string]$Name,[System.Drawing.Color]$Fallback) if ($Theme) { $prop=$Theme.PSObject.Properties[$Name]; if ($prop -and $prop.Value -is [System.Drawing.Color]) { return $prop.Value } }; $globalName=switch($Name){ 'Background'{'UGSM_ColorBackground'} 'Surface'{'UGSM_ColorSurface'} 'Input'{'UGSM_ColorInputBackground'} 'Text'{'UGSM_ColorText'} 'Muted'{'UGSM_ColorMutedText'} 'Accent'{'UGSM_ColorAccent'} default{''} }; if ($globalName -and (Get-Variable -Name $globalName -Scope Global -ErrorAction SilentlyContinue)) { $value=(Get-Variable -Name $globalName -Scope Global).Value; if ($value -is [System.Drawing.Color]) { return $value } }; return $Fallback }
function Add-UGSMGamePalWorldField { param([System.Windows.Forms.Panel]$Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[string]$Value,[int]$Row,[object]$Theme,[switch]$Multiline,[int]$Height=24) $lbl=New-Object System.Windows.Forms.Label; $lbl.Text=$Label; $lbl.AutoSize=$false; $lbl.Left=24; $lbl.Top=18+($Row*42); $lbl.Width=210; $lbl.Height=24; $lbl.ForeColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White); $Parent.Controls.Add($lbl); $txt=New-Object System.Windows.Forms.TextBox; $txt.Left=250; $txt.Top=14+($Row*42); $txt.Width=560; $txt.Height=$Height; $txt.Text=$Value; $txt.Multiline=[bool]$Multiline; if($Multiline){$txt.ScrollBars='Vertical';$txt.AcceptsReturn=$true}; $txt.ForeColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White); $txt.BackColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24)); $Parent.Controls.Add($txt); $Controls[$Key]=$txt; return $txt }
function Add-UGSMGamePalWorldCheckField { param([System.Windows.Forms.Panel]$Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[bool]$Value,[int]$Row,[object]$Theme) $chk=New-Object System.Windows.Forms.CheckBox; $chk.Left=250; $chk.Top=16+($Row*42); $chk.Width=500; $chk.Height=24; $chk.Text=$Label; $chk.Checked=[bool]$Value; $chk.ForeColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White); $chk.BackColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31)); $Parent.Controls.Add($chk); $Controls[$Key]=$chk; return $chk }

function Save-UGSMGamePalWorldInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$EditorState)
    $instance=$EditorState.Instance; $controls=$EditorState.Controls; $settings=Get-UGSMGamePalWorldSettings -Instance $instance
    foreach ($name in @('ServerName','ServerDescription','AdminPassword','ServerPassword','PublicIP','Region','ExtraArgs','WorkshopRootDir')) { if ($controls.ContainsKey($name)) { $settings.$name=[string]$controls[$name].Text } }
    foreach ($name in @('GamePort','QueryPort','RconPort','MaxPlayers','PublicPort')) { if ($controls.ContainsKey($name)) { $n=0; if ([int]::TryParse([string]$controls[$name].Text,[ref]$n)) { $settings.$name=$n } } }
    foreach ($name in @('RconEnabled','CommunityServer','UseMultithreadForDS','UsePerfThreads','NoAsyncLoadingThread','EnableMods')) { if ($controls.ContainsKey($name)) { $settings.$name=[bool]$controls[$name].Checked } }
    if ($controls.ContainsKey('WorkshopIds')) { $settings.WorkshopIds=ConvertFrom-UGSMGamePalWorldMultilineList -Text $controls['WorkshopIds'].Text }
    if ($controls.ContainsKey('ActiveModPackages')) { $settings.ActiveModPackages=ConvertFrom-UGSMGamePalWorldMultilineList -Text $controls['ActiveModPackages'].Text }
    if ($controls.ContainsKey('DiscordWebhookUrl')) { $settings.Discord.WebhookUrl=[string]$controls['DiscordWebhookUrl'].Text }
    if ($controls.ContainsKey('NotifyOnStart')) { $settings.Discord.NotifyOnStart=[bool]$controls['NotifyOnStart'].Checked }
    if ($controls.ContainsKey('NotifyOnStop')) { $settings.Discord.NotifyOnStop=[bool]$controls['NotifyOnStop'].Checked }
    if ($controls.ContainsKey('ShowInDashboard')) { $settings.Discord.ShowInDashboard=[bool]$controls['ShowInDashboard'].Checked }
    return Save-UGSMGamePalWorldSettings -Instance $instance -Settings $settings
}

function New-UGSMGamePalWorldInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][System.Windows.Forms.Control]$HostPanel,[AllowNull()][object]$Theme,[AllowNull()][System.Windows.Forms.Label]$StatusLabel)
    $instanceId=Get-UGSMGamePalWorldInstanceId -Instance $Instance
    Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear(); $HostPanel.BackColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
        $tabs=New-Object System.Windows.Forms.TabControl; $tabs.Dock='Fill'; $tabs.Multiline=$false; $HostPanel.Controls.Add($tabs)
        $settings=Get-UGSMGamePalWorldSettings -Instance $Instance; $controls=@{}
        $serverTab=New-Object System.Windows.Forms.TabPage; $serverTab.Text='Server'; $serverPanel=New-Object System.Windows.Forms.Panel; $serverPanel.Dock='Fill'; $serverPanel.AutoScroll=$true; $serverPanel.BackColor=$HostPanel.BackColor; $serverTab.Controls.Add($serverPanel); [void]$tabs.TabPages.Add($serverTab)
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'ServerName' -Label 'Server name' -Value $settings.ServerName -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'ServerDescription' -Label 'Description' -Value $settings.ServerDescription -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'AdminPassword' -Label 'Admin password' -Value $settings.AdminPassword -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'ServerPassword' -Label 'Server password' -Value $settings.ServerPassword -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'MaxPlayers' -Label 'Max players' -Value ([string]$settings.MaxPlayers) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'GamePort' -Label 'Game port' -Value ([string]$settings.GamePort) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'QueryPort' -Label 'Query port' -Value ([string]$settings.QueryPort) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'RconPort' -Label 'RCON port' -Value ([string]$settings.RconPort) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $serverPanel -Controls $controls -Key 'RconEnabled' -Label 'Enable RCON' -Value ([bool]$settings.RconEnabled) -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'PublicIP' -Label 'Public IP optional' -Value $settings.PublicIP -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'PublicPort' -Label 'Public port' -Value ([string]$settings.PublicPort) -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'Region' -Label 'Region optional' -Value $settings.Region -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $serverPanel -Controls $controls -Key 'CommunityServer' -Label 'List as community/public server' -Value ([bool]$settings.CommunityServer) -Row 12 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $serverPanel -Controls $controls -Key 'UsePerfThreads' -Label 'Use performance threads' -Value ([bool]$settings.UsePerfThreads) -Row 13 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $serverPanel -Controls $controls -Key 'NoAsyncLoadingThread' -Label 'No async loading thread' -Value ([bool]$settings.NoAsyncLoadingThread) -Row 14 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $serverPanel -Controls $controls -Key 'UseMultithreadForDS' -Label 'Use multithread for dedicated server' -Value ([bool]$settings.UseMultithreadForDS) -Row 15 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $serverPanel -Controls $controls -Key 'ExtraArgs' -Label 'Extra startup args' -Value $settings.ExtraArgs -Row 16 -Theme $Theme -Multiline -Height 70 | Out-Null

        $modsTab=New-Object System.Windows.Forms.TabPage; $modsTab.Text='Mods'; $modsPanel=New-Object System.Windows.Forms.Panel; $modsPanel.Dock='Fill'; $modsPanel.AutoScroll=$true; $modsPanel.BackColor=$HostPanel.BackColor; $modsTab.Controls.Add($modsPanel); [void]$tabs.TabPages.Add($modsTab)
        $note=New-Object System.Windows.Forms.Label; $note.Text='Palworld server mods need Workshop item files plus ActiveModList package names from each mod Info.json. Only server-compatible mods should be enabled.'; $note.Left=24; $note.Top=18; $note.Width=900; $note.Height=42; $note.ForeColor=Get-UGSMGamePalWorldColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White); $modsPanel.Controls.Add($note)
        Add-UGSMGamePalWorldCheckField -Parent $modsPanel -Controls $controls -Key 'EnableMods' -Label 'Enable Palworld mods' -Value ([bool]$settings.EnableMods) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldField -Parent $modsPanel -Controls $controls -Key 'WorkshopIds' -Label 'Workshop IDs' -Value (ConvertTo-UGSMGamePalWorldMultilineText -Values $settings.WorkshopIds) -Row 3 -Theme $Theme -Multiline -Height 120 | Out-Null
        Add-UGSMGamePalWorldField -Parent $modsPanel -Controls $controls -Key 'ActiveModPackages' -Label 'Active package names' -Value (ConvertTo-UGSMGamePalWorldMultilineText -Values $settings.ActiveModPackages) -Row 7 -Theme $Theme -Multiline -Height 120 | Out-Null
        Add-UGSMGamePalWorldField -Parent $modsPanel -Controls $controls -Key 'WorkshopRootDir' -Label 'Workshop root optional' -Value $settings.WorkshopRootDir -Row 11 -Theme $Theme | Out-Null

        $discordTab=New-Object System.Windows.Forms.TabPage; $discordTab.Text='Discord'; $discordPanel=New-Object System.Windows.Forms.Panel; $discordPanel.Dock='Fill'; $discordPanel.AutoScroll=$true; $discordPanel.BackColor=$HostPanel.BackColor; $discordTab.Controls.Add($discordPanel); [void]$tabs.TabPages.Add($discordTab)
        Add-UGSMGamePalWorldField -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value $settings.Discord.WebhookUrl -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$settings.Discord.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$settings.Discord.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGamePalWorldCheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$settings.Discord.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $btnTestDiscord=New-Object System.Windows.Forms.Button; $btnTestDiscord.Text='Test Discord'; $btnTestDiscord.Left=250; $btnTestDiscord.Top=190; $btnTestDiscord.Width=160; $btnTestDiscord.Height=30; $btnTestDiscord.Tag=[pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTestDiscord.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGamePalWorldInstanceEditor -EditorState $st | Out-Null; if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null }; if ($st.StatusLabel) { $st.StatusLabel.Text='Palworld Discord test sent.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text='Palworld Discord test failed: ' + $_.Exception.Message }; Write-UGSMGamePalWorldLog -Level 'ERROR' -Message 'Discord test failed.' -Exception $_.Exception } })
        $discordPanel.Controls.Add($btnTestDiscord)
        $btnSave=New-Object System.Windows.Forms.Button; $btnSave.Text='Save Settings'; $btnSave.Dock='Bottom'; $btnSave.Height=32; $btnSave.Tag=[pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGamePalWorldInstanceEditor -EditorState $st | Out-Null; if ($st.StatusLabel) { $st.StatusLabel.Text='Palworld settings saved.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text='Palworld save failed: ' + $_.Exception.Message }; Write-UGSMGamePalWorldLog -Level 'ERROR' -Message 'Palworld editor save failed.' -Exception $_.Exception } })
        $HostPanel.Controls.Add($btnSave); $btnSave.BringToFront()
        Write-UGSMGamePalWorldLog -Level 'INFO' -Message ("Editor creation completed. InstanceId=$instanceId")
        return [pscustomobject]@{ Success=$true; Controls=$controls }
    } catch { Write-UGSMGamePalWorldLog -Level 'ERROR' -Message ("Editor creation failed. InstanceId=$instanceId") -Exception $_.Exception; throw } finally { $HostPanel.ResumeLayout($true) }
}

function Register-UGSMGamePalWorldModule {
    [CmdletBinding()]
    param()
    $metadata=Get-UGSMGamePalWorldMetadata
    return [pscustomobject]@{
        Id=[string]$metadata.Id
        Metadata=$metadata
        Handlers=[pscustomobject]@{
            GetMetadata='Get-UGSMGamePalWorldMetadata'
            TestInstall='Test-UGSMGamePalWorldInstall'
            TestInstance='Test-UGSMGamePalWorldInstance'
            InitializeProfile='Initialize-UGSMGamePalWorldProfile'
            Start='Start-UGSMGamePalWorldInstance'
            Stop='Stop-UGSMGamePalWorldInstance'
            BuildEditor='New-UGSMGamePalWorldInstanceEditor'
            SaveEditor='Save-UGSMGamePalWorldInstanceEditor'
        }
    }
}
