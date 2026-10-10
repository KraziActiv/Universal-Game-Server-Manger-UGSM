# UGSM Game ProjectZomboid
# Project Zomboid dedicated server module.
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace ProjectZomboid with the real game token
# 3. Update metadata, install definition, runtime layout, schema, and any
#    game-specific workflows
# 4. Remove optional blocks that are marked as game-specific
#
# Design rules
# ------------
# - Hidden from the game catalog by default
# - Runtime-only working paths
# - No profile sync / no copy-back workflow
# - Generic reusable helpers first
# - Schema includes sample tabs and subtabs for multi-file games
# - Game-specific logic stays in the game module and must be labeled clearly
# - Default lifecycle for Steam games: Install, Update, Verify, Remove binaries only
# - Remove the sample reference tab once a real game module is built

function Test-UGSMGameProjectZomboidVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameProjectZomboidLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameProjectZomboidLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_ProjectZomboid)) { return $true }
    return $false
}

function ConvertTo-UGSMGameProjectZomboidSafeLogText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return '' }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    try {
        # Prefer the shared logger display-path helper when it is available.
        if (Get-Command -Name ConvertTo-UGSMDisplayPath -ErrorAction SilentlyContinue) {
            $text = ConvertTo-UGSMDisplayPath -Path $text
        }

        # Generic user/machine path cleanup. Build sensitive literals at runtime so
        # the ProjectZomboid itself does not add portability-scan false positives.
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $text = [regex]::Replace($text, [regex]::Escape($localAppData.TrimEnd('\')), '%LOCALAPPDATA%', 'IgnoreCase')
        }

        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $text = [regex]::Replace($text, [regex]::Escape($env:USERPROFILE.TrimEnd('\')), '%USERPROFILE%', 'IgnoreCase')
        }

        if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            $usersPrefix = [regex]::Escape(($env:SystemDrive.TrimEnd('\') + '\Users\'))
            $text = [regex]::Replace($text, "(?i)$usersPrefix[^\\;:""'<>\r\n]+", '%USERPROFILE%')
        }

        # Game/server roots. These variables may or may not exist in a copied module.
        $rootReplacements = @(
            @{ Names = @('UGSM_SteamRoot','UGSM_SteamCMDRoot','UGSM_SteamInstallRoot'); Token = '%UGSM_STEAM%' }
            @{ Names = @('UGSM_ProfileRoot','UGSM_ProfilesRoot','UGSM_ProfileStoreRoot'); Token = '%UGSM_PROFILES%' }
            @{ Names = @('UGSM_AppRoot','UGSM_Root','UGSM_SourceRoot'); Token = '%UGSM_ROOT%' }
        )

        foreach ($replacement in $rootReplacements) {
            foreach ($name in $replacement.Names) {
                $rootValue = $null

                $scriptVar = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
                if ($scriptVar -and $scriptVar.Value) { $rootValue = [string]$scriptVar.Value }

                if ([string]::IsNullOrWhiteSpace($rootValue)) {
                    $globalVar = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
                    if ($globalVar -and $globalVar.Value) { $rootValue = [string]$globalVar.Value }
                }

                if (-not [string]::IsNullOrWhiteSpace($rootValue)) {
                    $normalizedRoot = $rootValue.TrimEnd('\')
                    if (-not [string]::IsNullOrWhiteSpace($normalizedRoot)) {
                        $text = [regex]::Replace($text, [regex]::Escape($normalizedRoot), [string]$replacement.Token, 'IgnoreCase')
                    }
                }
            }
        }

        # Discord webhook URLs and Steam login credentials must never be logged.
        $text = [regex]::Replace($text, '(?i)https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s''"<>]+', '<redacted-discord-webhook>')
        $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+(\s+)\S+', '$1<redacted>$2<redacted>')

        # Generic key/value secret cleanup.
        $text = [regex]::Replace(
            $text,
            '(?i)\b(password|passwd|pass|token|api[_-]?key|apikey|secret|gslt|login[_-]?token|private[_-]?token|webhook(?:url)?)\b\s*[:=]\s*("[^"]*"|''[^'']*''|[^\s;,]+)',
            '$1=<redacted>'
        )
    }
    catch {
        # Log cleanup must never break the caller.
    }

    return $text
}

function Write-UGSMGameProjectZomboidLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGameProjectZomboidVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameProjectZomboidSafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameProjectZomboidSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:ProjectZomboid' -Message $safeMessage
    }
}

function Write-UGSMGameProjectZomboidPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older ProjectZomboid notes. New modules should use Write-UGSMGameProjectZomboidLog.
    Write-UGSMGameProjectZomboidLog -Level 'DEBUG' -Message $Message
}


function Ensure-UGSMGameProjectZomboidInstanceDiscordShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    # Strict-mode safe compatibility shape for the shared Discord settings service.
    # These are metadata flags only. Webhook secrets remain in UGSM secrets storage.
    if (-not $Instance.PSObject.Properties['Discord'] -or $null -eq $Instance.Discord) {
        $discordObject = [pscustomobject]@{
            WebhookUrl      = ''
            NotifyOnStart   = $false
            NotifyOnStop    = $false
            ShowInDashboard = $false
        }
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'Discord' -Value $discordObject -Force
    }
    else {
        if (-not $Instance.Discord.PSObject.Properties['WebhookUrl']) {
            Add-Member -InputObject $Instance.Discord -MemberType NoteProperty -Name 'WebhookUrl' -Value '' -Force
        }
        if (-not $Instance.Discord.PSObject.Properties['NotifyOnStart']) {
            Add-Member -InputObject $Instance.Discord -MemberType NoteProperty -Name 'NotifyOnStart' -Value $false -Force
        }
        if (-not $Instance.Discord.PSObject.Properties['NotifyOnStop']) {
            Add-Member -InputObject $Instance.Discord -MemberType NoteProperty -Name 'NotifyOnStop' -Value $false -Force
        }
        if (-not $Instance.Discord.PSObject.Properties['ShowInDashboard']) {
            Add-Member -InputObject $Instance.Discord -MemberType NoteProperty -Name 'ShowInDashboard' -Value $false -Force
        }
    }

    if (-not $Instance.PSObject.Properties['DiscordWebhookUrl']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'DiscordWebhookUrl' -Value '' -Force
    }
    if (-not $Instance.PSObject.Properties['DiscordNotifyStart']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'DiscordNotifyStart' -Value $false -Force
    }
    if (-not $Instance.PSObject.Properties['DiscordNotifyStop']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'DiscordNotifyStop' -Value $false -Force
    }
    if (-not $Instance.PSObject.Properties['DiscordVisible']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'DiscordVisible' -Value $false -Force
    }
    if (-not $Instance.PSObject.Properties['HasPrivateDiscordWebhook']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'HasPrivateDiscordWebhook' -Value $false -Force
    }

    return $Instance
}


function Get-UGSMGameProjectZomboidSupportedFeatures {
    [CmdletBinding()]
    param()

    # ============================================================
    # Project Zomboid SUPPORTED FEATURES
    # One switch block. Do not add duplicate visibility or storage paths.
    # ============================================================

    return [pscustomobject]@{
        Install       = $true
        Update        = $true
        Verify        = $true
        Repair        = $true
        Start         = $true
        Stop          = $true
        Profiles      = $true
        InstanceUi    = $true
        Bootstrap     = $false
        IsVisible     = $true

        Rcon          = $true
        GracefulStop  = $true

        Mods          = $true
        Workshop      = $true
        ModTabMode    = 'SteamWorkshop'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $true

        IniFiles         = $true
        JsonFiles        = $false
        XmlFiles         = $false
        CfgFiles         = $false
        PropertiesFiles  = $false
        YamlFiles        = $false
        TomlFiles        = $false
        LuaFiles         = $false
        TextFiles        = $true
        PSSQLite         = $false

        # Store mod state in the AppData instance.json, matching the DayZ pattern.
        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        # Project Zomboid uses Steam Workshop references. Keep full Workshop
        # content shared in Steam's workshop cache; the server INI gets only
        # WorkshopItems=, Mods=, and Map=.
        ModCapabilities = [pscustomobject]@{
            SteamWorkshop    = $true
            ArchiveImport    = $false
            FolderImport     = $false
            FrameworkInstall = $false
            PluginManager    = $false
            MapList          = $true
            ConfigMerge      = $false
            LoadOrder        = $true
            UrlDownload      = $false
            KeyCopy          = $false
            ServerSideCopy   = $false
            RuntimeSync      = $true
            BuildIndexCache  = $false
            OpenManifest     = $true
            RefreshSummary   = $true
        }
    }
}

function Get-UGSMGameProjectZomboidModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameProjectZomboidSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'ProjectZomboid' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
    }
    else {
        $mods = [pscustomobject]@{
            Supported = [bool]$features.Mods
            DisplayName = 'Mods'
            Version = 1
            Capabilities = [pscustomobject]@{
                SteamWorkshop = $false; ArchiveImport = $false; FolderImport = $false; FrameworkInstall = $false; PluginManager = $false; MapList = $false; ConfigMerge = $false; LoadOrder = $false; UrlDownload = $false; OpenManifest = $true; RefreshSummary = $true
            }
            Archive = [pscustomobject]@{ AllowedExtensions = @('.zip','.rar'); InstallFolderRelative = 'Mods'; RequireSafetyNotice = $true }
            Workshop = [pscustomobject]@{ IdField = 'WorkshopItemIds'; SupportsCollections = $true; ConfigStrategy = 'GameSpecific' }
            Framework = [pscustomobject]@{ Id = 'ExampleFramework'; Label = 'Example Framework'; OfficialSourceOnly = $true; RequiresConfirmation = $true }
            Paths = [pscustomobject]@{ ModsFolderRelative = 'Mods'; ManifestFileName = $null }
            Safety = [pscustomobject]@{ ShowThirdPartyNotice = $true; RequireConfirmation = $true; NoticeKind = 'GenericMods' }
            Hooks = [pscustomobject]@{ Refresh = ''; Save = ''; Install = ''; Remove = ''; Validate = ''; BuildCustomTab = '' }
            GameId = 'ProjectZomboid'
        }
    }

    foreach ($name in @('SteamWorkshop','ArchiveImport','FolderImport','FrameworkInstall','PluginManager','MapList','ConfigMerge','LoadOrder','UrlDownload','KeyCopy','ServerSideCopy','RuntimeSync','BuildIndexCache','OpenManifest','RefreshSummary')) {
        if ($mods.Capabilities.PSObject.Properties[$name] -and $features.ModCapabilities.PSObject.Properties[$name]) {
            $mods.Capabilities.$name = [bool]$features.ModCapabilities.$name
        }
    }

    # Project Zomboid Workshop/client App ID used by SteamCMD workshop_download_item.
    # Store it in more than one metadata location so shared helpers and future
    # copied modules can resolve it even if a helper version checks a different name.
    foreach ($propName in @('WorkshopAppId','SteamWorkshopAppId')) {
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = '108600' }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value '108600' -Force }
    }

    if ($mods.PSObject.Properties['Workshop'] -and $mods.Workshop) {
        if ($mods.Workshop.PSObject.Properties['AppId']) { $mods.Workshop.AppId = '108600' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'AppId' -Value '108600' -Force }

        if ($mods.Workshop.PSObject.Properties['WorkshopAppId']) { $mods.Workshop.WorkshopAppId = '108600' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'WorkshopAppId' -Value '108600' -Force }

        if ($mods.Workshop.PSObject.Properties['ConfigStrategy']) { $mods.Workshop.ConfigStrategy = 'ManifestOnly' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'ConfigStrategy' -Value 'ManifestOnly' -Force }

        if ($mods.Workshop.PSObject.Properties['LoginMode']) { $mods.Workshop.LoginMode = 'Anonymous' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'LoginMode' -Value 'Anonymous' -Force }

        foreach ($propName in @('PromptForModId','PromptForMapFolders')) {
            if ($mods.Workshop.PSObject.Properties[$propName]) { $mods.Workshop.$propName = $true }
            else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name $propName -Value $true -Force }
        }
    }

    foreach ($propName in @('LoginMode','SteamLoginMode','WorkshopLoginMode')) {
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = 'Anonymous' }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value 'Anonymous' -Force }
    }

    if ($mods.PSObject.Properties['StoragePolicy'] -and $mods.StoragePolicy) {
        $mods.StoragePolicy.KeepWorkshopModsShared = $true
        $mods.StoragePolicy.CopyFullModsToProfile = $false
        $mods.StoragePolicy.CopyOnlyRequiredFilesToProfile = $true
        $mods.StoragePolicy.RuntimeMode = 'SharedWorkshopCache'
        if ($mods.StoragePolicy.PSObject.Properties['SummaryFileName']) { $mods.StoragePolicy.SummaryFileName = $null }
    }

    if ($mods.PSObject.Properties['Safety'] -and $mods.Safety) {
        $mods.Safety.ShowThirdPartyNotice = [bool]$features.Mods
        $mods.Safety.RequireConfirmation = [bool]($features.ModCapabilities.FrameworkInstall -or $features.ModCapabilities.UrlDownload)
    }


    if ($mods.PSObject.Properties['Hooks'] -and $mods.Hooks) {
        foreach ($hookPair in @(
            @{ Name = 'AfterModsChanged'; Value = 'Update-UGSMGameProjectZomboidModIni' },
            @{ Name = 'AfterWorkshopDownload'; Value = 'Update-UGSMGameProjectZomboidModIni' }
        )) {
            $hookName = [string]$hookPair.Name
            if ($mods.Hooks.PSObject.Properties[$hookName]) { $mods.Hooks.$hookName = $hookPair.Value }
            else { Add-Member -InputObject $mods.Hooks -MemberType NoteProperty -Name $hookName -Value $hookPair.Value -Force }
        }
    }
    else {
        $hooks = [pscustomobject]@{
            AfterModsChanged      = 'Update-UGSMGameProjectZomboidModIni'
            AfterWorkshopDownload = 'Update-UGSMGameProjectZomboidModIni'
        }
        if ($mods.PSObject.Properties['Hooks']) { $mods.Hooks = $hooks }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Hooks' -Value $hooks -Force }
    }

    return $mods
}


function Get-UGSMGameProjectZomboidMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = 'jre64\bin\java.exe'
    $features = Get-UGSMGameProjectZomboidSupportedFeatures
    $modsDefinition = Get-UGSMGameProjectZomboidModsDefinition

    return [pscustomobject]@{
        Id                       = 'ProjectZomboid'
        Name                     = 'Project Zomboid'
        Category                 = 'Survival'
        Description              = 'Project Zomboid dedicated server module with SteamCMD install, profile-light settings, and Steam Workshop mod-line generation.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 9500
        IsVisible                = [bool]$features.IsVisible

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
        UseSteamArt              = $true

        SupportsInstall          = [bool]$features.Install
        SupportsUpdate           = [bool]$features.Update
        SupportsVerify           = [bool]$features.Verify
        SupportsRepair           = [bool]$features.Repair
        SupportsStart            = [bool]$features.Start
        SupportsStop             = [bool]$features.Stop
        SupportsMods             = [bool]($features.Mods -and $modsDefinition.Supported)
        SupportsWorkshop         = [bool]($features.Workshop -and $modsDefinition.Capabilities.SteamWorkshop)
        SupportsRcon             = [bool]$features.Rcon
        SupportsBootstrap        = [bool]$features.Bootstrap
        SupportsProfiles         = [bool]$features.Profiles
        SupportsInstanceUi       = [bool]$features.InstanceUi
        SupportedFeatures        = $features
        Mods                     = $modsDefinition
        ModTraits                = $modsDefinition

        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '380870'
        SteamStoreAppId          = '108600'
        ServerExecutable         = 'StartServer64.bat'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'Server'
        SaveRootRelative         = 'SaveFiles'
        LogRootRelative          = 'Logs'

        RequiredFiles            = @('StartServer64.bat', 'jre64\bin\java.exe')
        InstallMarkers           = @('StartServer64.bat', 'jre64')

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 16261 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 8766 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 27015 }
        )

        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = [bool]$features.IniFiles
            UsesJsonFiles         = [bool]$features.JsonFiles
            UsesXmlFiles          = [bool]$features.XmlFiles
            UsesCfgFiles          = [bool]$features.CfgFiles
            UsesPropertiesFiles   = [bool]$features.PropertiesFiles
            UsesYamlFiles         = [bool]$features.YamlFiles
            UsesTomlFiles         = [bool]$features.TomlFiles
            UsesLuaFiles          = [bool]$features.LuaFiles
            UsesTextFiles         = [bool]$features.TextFiles

            UsesPSSQLite          = [bool]$features.PSSQLite
            UsesSqliteDatabase    = [bool]$features.PSSQLite
            UsesSqlite            = [bool]$features.PSSQLite

            UsesProfileSync       = $false
            UsesPluginFramework   = [bool]$features.ModCapabilities.FrameworkInstall
            UsesZipMods           = [bool]$features.ModCapabilities.ArchiveImport
            UsesFolderCopyMods    = [bool]$features.ModCapabilities.FolderImport
            UsesFileMergeWorkflow = [bool]$features.ModCapabilities.ConfigMerge
            UsesMissionFiles      = $false
            UsesWorkshopItems     = [bool]$features.ModCapabilities.SteamWorkshop
        }

        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'Project Zomboid module is the real supported module converted from the template-driven test module.',
                'Replace metadata, install validation, runtime layout, launch arguments, and schema values when creating a real game module.',
                'SteamCMD is the default install/update/verify pattern in the ProjectZomboid.',
                'Steam login defaults to anonymous. Only add username/password handling when the target game truly requires it.',
                'Mods are driven by Get-UGSMGameProjectZomboidModsDefinition and shared helper functions.',
                'Do not add profile sync or copy-back behavior to new game modules.'
            )
        }
    }
}

function Get-UGSMGameProjectZomboidInstallDefinition {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    # The game-action service calls this handler to get the canonical install
    # path. Resolve that path from the same settings names used by the working
    # game modules instead of requiring the caller to pass InstallPath.
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $steamRoot = $null
    if ($settings) {
        foreach ($propName in @('SteamCmdPath', 'SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
            if ($settings.PSObject.Properties.Name -contains $propName) {
                $value = [string]$settings.$propName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $steamRoot = $value
                    break
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($steamRoot)) {
        throw 'Project Zomboid install definition failed: Steam root could not be resolved.'
    }

    $meta = Get-UGSMGameProjectZomboidMetadata
    $canonicalInstallPath = Join-Path (Join-Path $steamRoot 'steamapps\common') 'ProjectZomboid'

    if ([string]::IsNullOrWhiteSpace($InstallPath) -and $Instance) {
        if ($Instance.PSObject.Properties.Name -contains 'InstallPath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) {
            $InstallPath = [string]$Instance.InstallPath
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = $canonicalInstallPath
    }
    else {
        $leaf = Split-Path -Leaf $InstallPath
        if ($leaf -ne 'ProjectZomboid') {
            $InstallPath = $canonicalInstallPath
        }
    }

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = [string]$InstallPath
        ServerExecutablePath = Join-Path $InstallPath $meta.ServerExecutableRelative
        RequiredFiles            = @('StartServer64.bat', 'jre64\bin\java.exe')
        InstallMarkers           = @('StartServer64.bat', 'jre64')
        ConfigRootPath       = Join-Path $InstallPath $meta.ConfigRootRelative
        SaveRootPath         = Join-Path $InstallPath $meta.SaveRootRelative
        LogRootPath          = Join-Path $InstallPath $meta.LogRootRelative
    }
}

function Get-UGSMGameProjectZomboidAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameProjectZomboidProfileBaseRoot {
    [CmdletBinding()]
    param()

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
        }
        catch {
            $settings = $null
        }
    }

    if ($settings -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) {
        return [string]$settings.ProfileBaseRoot
    }

    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'ProjectZomboid' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameProjectZomboidAppDataRoot) 'Profiles')
}

function Get-UGSMGameProjectZomboidRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameProjectZomboidAppDataRoot) 'ProjectZomboid')
}

function Get-UGSMGameProjectZomboidProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameProjectZomboidProfileBaseRoot) 'ProjectZomboid') $ProfileName)
}


function Get-UGSMGameProjectZomboidRuntimeRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $profileRoot = $null

    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'ProfilePath') {
        $candidate = [string]$Instance.ProfilePath
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $profileRoot = $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot) -and $Instance -and $Instance.PSObject.Properties.Name -contains 'Name') {
        $candidate = [string]$Instance.Name
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $profileRoot = Get-UGSMGameProjectZomboidProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'ProjectZomboid runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameProjectZomboidPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        try {
            cmd.exe /c ('rmdir "{0}"' -f $Path) | Out-Null
        }
        catch {
            try {
                Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }
}

function New-UGSMGameProjectZomboidDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "ProjectZomboid junction target was not found: $TargetPath"
    }

    $parent = Split-Path -Path $LinkPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LinkPath) {
        $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $resolved = $null
            try { $resolved = [string]$existing.Target } catch { $resolved = $null }

            if ($resolved -is [System.Array]) {
                $resolved = [string]($resolved | Select-Object -First 1)
            }

            if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                try {
                    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
                    $resolvedFull = [System.IO.Path]::GetFullPath($resolved)
                    if ($targetFull.Equals($resolvedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return
                    }
                }
                catch {}
            }
        }

        Remove-UGSMGameProjectZomboidPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "ProjectZomboid junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameProjectZomboidFilesToRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [switch]$ClearDestination
    )

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        if ($ClearDestination) {
            Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        return
    }

    Copy-UGSMGameProjectZomboidDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameProjectZomboidRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameProjectZomboidRuntimeRoot -Instance $Instance
    $runtimeInstallRoot = [string]$InstallDefinition.InstallPath
    $runtimeGameRoot = [string]$InstallDefinition.InstallPath
    $runtimeSavedRoot = $runtimeRoot

    return [pscustomObject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeGameRoot       = $runtimeGameRoot
        RuntimeSavedRoot      = $runtimeSavedRoot
        RuntimeConfigRootPath = Join-Path $runtimeRoot 'Server'
        RuntimeSaveRootPath   = Join-Path $runtimeRoot 'SaveFiles'
        RuntimeLogRootPath    = Join-Path $runtimeRoot 'Logs'
        RuntimeServerExePath  = Join-Path ([string]$InstallDefinition.InstallPath) 'jre64\bin\java.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = [string]$InstallDefinition.InstallPath

    }
}

function Resolve-UGSMGameProjectZomboidDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($PreferRuntime) {
        if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeDatabasePath)) {
            [void]$candidates.Add([string]$paths.RuntimeDatabasePath)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$paths.ProfileDatabasePath)) {
            [void]$candidates.Add([string]$paths.ProfileDatabasePath)
        }
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace([string]$paths.ProfileDatabasePath)) {
            [void]$candidates.Add([string]$paths.ProfileDatabasePath)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeDatabasePath)) {
            [void]$candidates.Add([string]$paths.RuntimeDatabasePath)
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [string]$candidate
        }
    }

    foreach ($candidate in $candidates) {
        $parent = Split-Path -Parent $candidate
        if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent -PathType Container)) {
            return [string]$candidate
        }
    }

    return $null
}

function Ensure-UGSMGameProjectZomboidRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    # ProjectZomboid follows the shared-binaries/profile-light rule:
    # - server binaries remain in the Steam common install folder
    # - the profile keeps only config, saves/log roots, and UGSM manifests
    # - no full server binary copy/junction tree is created under the profile
    $runtime = Get-UGSMGameProjectZomboidRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeConfigRootPath)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path) -and -not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    return $runtime
}

function Initialize-UGSMGameProjectZomboidRuntimeData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileConfigRoot,

        [Parameter(Mandatory)]
        [string]$ProfileSaveRoot,

        [Parameter(Mandatory)]
        [string]$RuntimeConfigRoot,

        [Parameter(Mandatory)]
        [string]$RuntimeSaveRoot
    )

    if (-not (Test-Path -LiteralPath $RuntimeConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $RuntimeConfigRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $RuntimeSaveRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $RuntimeSaveRoot -Force | Out-Null
    }

    if ((Get-ChildItem -LiteralPath $RuntimeConfigRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameProjectZomboidFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameProjectZomboidFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameProjectZomboidDirectoryContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [switch]$ClearDestination,

        [string[]]$IncludeExtensions
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory was not found: $Source"
    }

    if ($ClearDestination -and (Test-Path -LiteralPath $Destination -PathType Container)) {
        Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $items = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Source.Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative)) {
            continue
        }

        $targetPath = Join-Path $Destination $relative

        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            continue
        }

        if ($IncludeExtensions -and $IncludeExtensions.Count -gt 0) {
            $ext = [System.IO.Path]::GetExtension($item.Name)
            if ($IncludeExtensions -notcontains $ext) {
                continue
            }
        }

        $parent = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
    }
}

function Get-UGSMGameProjectZomboidRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $serverRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ServerExecutablePath))
    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe' OR Name = 'cmd.exe'" -ErrorAction Stop)
    }
    catch {
        $matches = @()
    }

    $results = @()
    foreach ($proc in $matches) {
        $created = $null
        try {
            $created = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$proc.CreationDate)
        }
        catch {
            $created = $null
        }

        if ($created -and $created -lt $StartedAfter) {
            continue
        }

        $commandLine = [string]$proc.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            continue
        }

        $looksLikeProjectZomboid = ($commandLine -match 'ProjectZomboid|zombie\.network\.GameServer|StartServer64\.bat')
        $looksLikeThisInstall = (-not [string]::IsNullOrWhiteSpace($serverRoot) -and $commandLine.IndexOf($serverRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)

        if (-not ($looksLikeProjectZomboid -or $looksLikeThisInstall)) {
            continue
        }

        $results += [pscustomobject]@{
            Pid         = [int]$proc.ProcessId
            Executable  = [string]$proc.ExecutablePath
            StartedAt   = $created
            CommandLine = $commandLine
        }
    }

    return @($results | Sort-Object Pid -Unique)
}

function Start-UGSMGameProjectZomboidBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "ProjectZomboid server executable was not found: $ServerExecutablePath"
    }

    $bootstrapTime = [Math]::Max(10, $BootstrapSeconds)
    $launchStartedAt = Get-Date

    $proc = Start-Process `
        -FilePath $ServerExecutablePath `
        -ArgumentList @('-log', '-MaxPlayers=1', '-nobattleye') `
        -WorkingDirectory $WorkingDirectory `
        -PassThru

    Start-Sleep -Seconds $bootstrapTime

    $stopResults = @()

    if ($proc -and $proc.Id -gt 0) {
        $targetPid = [int]$proc.Id

        try {
            & taskkill.exe /PID $targetPid /T /F
            $taskkillExit = $LASTEXITCODE

            Start-Sleep -Seconds 2

            $stillRunning = $null -ne (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)

            if ($stillRunning) {

                try {
                    Stop-Process -Id $targetPid -Force -ErrorAction Stop
                }
                catch {
                }
            }

            try {
                $proc.Refresh()
                $waitExited = $proc.WaitForExit(5000)
            }
            catch {
            }

            $stillRunning = $null -ne (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)

            $stopResults += [pscustomobject]@{
                Pid      = $targetPid
                Stopped  = (-not $stillRunning)
                Method   = 'TaskKillTree'
                ExitCode = $taskkillExit
            }
        }
        catch {
        }
    }

    Start-Sleep -Seconds 2

    # Do not fall back to a hard-coded Project Zomboid process name here.
    # StartServer64.bat launches Java/cmd descendants, and the normal taskkill tree
    # path above is the owner for cleaning up this temporary bootstrap launch.

    return [pscustomobject]@{
        PreferredPid  = [int]$proc.Id
        StartedAt     = $launchStartedAt
        BootstrapTime = $bootstrapTime
        StopResults   = $stopResults
        Exited        = ($remainingFinal.Count -eq 0)
        RemainingPids = @($remainingFinal.Id)
    }
}

function Ensure-UGSMGameProjectZomboid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    # ProjectZomboid follows the shared-binaries/profile-light rule. For this template-copy
    # test module, the "ensure" step should only validate that SteamCMD installed
    # the shared binaries. It should not bootstrap/copy server files into AppData
    # or into every profile.
    $definition = Get-UGSMGameProjectZomboidInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameProjectZomboidInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "ProjectZomboid install is not valid at '$InstallPath'."
    }

    $sharedConfigRoot = Join-Path (Get-UGSMGameProjectZomboidProfileBaseRoot) 'ProjectZomboid\_Shared'
    New-Item -ItemType Directory -Path $sharedConfigRoot -Force | Out-Null

    return [pscustomobject]@{
        GameId             = 'ProjectZomboid'
        InstallPath        = [string]$definition.InstallPath
        SharedConfigRoot   = $sharedConfigRoot
        BootstrapPerformed = $false
        ProfileLight       = $true
        Validated          = $true
    }
}


function Get-UGSMGameProjectZomboidDefaultIniLines {
    [CmdletBinding()]
    param(
        [string]$ServerName = 'Project Zomboid Server'
    )

    $lines = @(
        '# Players can hurt and kill other players'
        'PVP=false'
        ''
        '# Game time stops when there are no players online'
        'PauseEmpty=true'
        ''
        '# Toggles global chat on or off.'
        'GlobalChat=true'
        ''
        'ChatStreams=s,r,a,w,y,sh,f,all'
        ''
        '# Clients may join without already having an account in the whitelist. If set to false, administrators must manually create username/password combos.'
        'Open=true'
        ''
        '# The first welcome message visible in the chat panel. This will be displayed immediately after player login. you can use RGB colours to chance the colour of the welcome message. You can also use <LINE> to create a separate lines within your text. Use: <RGB:1,0,0> This message will show up red!'
        'ServerWelcomeMessage=Welcome to Project Zomboid Multiplayer! <LINE> <LINE> To interact with the Chat panel: press Tab, T, or Enter. <LINE> <LINE> The Tab key will change the target stream of the message. <LINE> <LINE> Global Streams: /all <LINE> Local Streams: /say, /yell <LINE> Special Steams: /whisper, /safehouse, /faction. <LINE> <LINE> Press the Up arrow to cycle through your message history. Click the Gear icon to customize chat. <LINE> <LINE> Happy surviving!'
        ''
        '# Add unknown usernames to the whitelist when players join. Clients will supply their own username/password on joining. (This is for Open=true servers)'
        'AutoCreateUserInWhiteList=true'
        ''
        '# Display usernames above player''s heads in-game.'
        'DisplayUserName=true'
        ''
        '# Display first & last name above player''s heads.'
        'ShowFirstAndLastName=false'
        ''
        '# Force every new player to spawn at these set x,y,z world coordinates. Find desired coordinates at map.projectzomboid.com. (Ignored when 0,0,0)'
        'SpawnPoint=0,0,0'
        ''
        '# Players can enter and leave PVP on an individual basis. A player can only hurt another player when at least one of them is in PVP mode - as shown by the unobscured skull and crossbones on the left of the screen. When SafetySystem=false, players are free to hurt each other at any time if PVP is enabled.'
        'SafetySystem=true'
        ''
        '# Display a skull icon over the head of players who have entered PVP mode'
        'ShowSafety=true'
        ''
        '# The time it takes for a player to enter and leave PVP mode\nMinimum=0 Maximum=1000 Default=2'
        'SafetyToggleTimer=2'
        ''
        '# The delay before a player can enter or leave PVP mode again, having recently done so\nMinimum=0 Maximum=1000 Default=3'
        'SafetyCooldownTimer=3'
        ''
        '# Item types new players spawn with.\nSeparate multiple item types with commas.\nExample: Base.Axe,Base.Bag_BigHikingBag'
        'SpawnItems='
        ''
        '# Default starting port for player data. If UDP, this is this one of two ports used.\nMinimum=0 Maximum=65535 Default=16261'
        'DefaultPort=16261'
        ''
        '# Minimum=0 Maximum=65535 Default=16262'
        'UDPPort=16262'
        ''
        '# Reset ID determines if the server has undergone a soft-reset. If this number does match the client, the client must create a new character. Used in conjunction with PlayerServerID. It is strongly advised that you backup these IDs somewhere\nMinimum=0 Maximum=2147483647 Default=552764484'
        'ResetID=4775295'
        ''
        '# Enter the mod loading ID here. It can be found in \Steam\steamapps\workshop\modID\mods\modName\info.txt'
        'Mods='
        ''
        '# Enter the foldername of the mod found in \Steam\steamapps\workshop\modID\mods\modName\media\maps\'
        'Map=Muldraugh, KY'
        ''
        '# Kick clients whose game files don''t match the server''s.'
        'DoLuaChecksum=true'
        ''
        'DenyLoginOnOverloadedServer=true'
        ''
        '# Shows the server on the in-game browser. (Note: Steam-enabled servers are always visible in the Steam server browser)'
        'Public=true'
        ''
        '# Name of the server displayed in the in-game browser and, if applicable, the Steam browser'
        'PublicName=__UGSM_PUBLIC_NAME__'
        ''
        '# Description displayed in the in-game public server browser. Typing \n will create a new line in your description'
        'PublicDescription=UGSM Project Zomboid server'
        ''
        '# Maximum number of players that can be on the server at one time. This excludes admins.'
        '# WARNING: Server player counts above 32 will potentially result in poor map streaming and desync. Please advance with caution.\nMinimum=1 Maximum=100 Default=32'
        'MaxPlayers=5'
        ''
        '# Ping limit, in milliseconds, before a player is kicked from the server. (Set to 100 to disable)\nMinimum=100 Maximum=2147483647 Default=400'
        'PingLimit=400'
        ''
        '# After X hours, all containers in the world will respawn loot. To spawn loot a container must have been looted at least once. Loot respawn is not impacted by visibility or subsequent looting.\nMinimum=0 Maximum=2147483647 Default=0'
        'HoursForLootRespawn=1'
        ''
        '# Containers with a number of items greater, or equal to, this setting will not respawn\nMinimum=1 Maximum=2147483647 Default=4'
        'MaxItemsForLootRespawn=5'
        ''
        '# Items will not respawn in buildings that players have barricaded or built in'
        'ConstructionPreventsLootRespawn=false'
        ''
        '# Remove player accounts from the whitelist after death. This prevents players creating a new character after death on Open=false servers'
        'DropOffWhiteListAfterDeath=false'
        ''
        '# All forms of fire are disabled - except for campfires'
        'NoFire=false'
        ''
        '# If checked, every time a player dies a global message will be displayed in the chat'
        'AnnounceDeath=false'
        ''
        '# The number of in-game minutes it takes to read one page of a book\nMinimum=0.00 Maximum=60.00 Default=1.00'
        'MinutesPerPage=0.25'
        ''
        '# Loaded parts of the map are saved after this set number of real-world minutes have passed. (The map is usually saved only after clients leave a loaded area)\nMinimum=0 Maximum=2147483647 Default=0'
        'SaveWorldEveryMinutes=30'
        ''
        '# Both admins and players can claim safehouses'
        'PlayerSafehouse=false'
        ''
        '# Only admins can claim safehouses'
        'AdminSafehouse=false'
        ''
        '# Allow non-members to enter a safehouse without being invited'
        'SafehouseAllowTrepass=true'
        ''
        '# Allow fire to damage safehouses'
        'SafehouseAllowFire=true'
        ''
        '# Allow non-members to take items from safehouses'
        'SafehouseAllowLoot=true'
        ''
        '# Players will respawn in a safehouse that they were a member of before they died'
        'SafehouseAllowRespawn=true'
        ''
        '# Players must have survived this number of in-game days before they are allowed to claim a safehouse\nMinimum=0 Maximum=2147483647 Default=0'
        'SafehouseDaySurvivedToClaim=0'
        ''
        '# Players are automatically removed from a safehouse they have not visited for this many real-world hours\nMinimum=0 Maximum=2147483647 Default=144'
        'SafeHouseRemovalTime=144'
        ''
        '# Governs whether players can claim non-residential buildings.'
        'SafehouseAllowNonResidential=true'
        ''
        '# Allow players to destroy world objects with sledgehammers'
        'AllowDestructionBySledgehammer=true'
        ''
        '# Allow players to destroy world objects only in their safehouse (require AllowDestructionBySledgehammer to true).'
        'SledgehammerOnlyInSafehouse=false'
        ''
        '# Kick players that appear to be moving faster than is possible. May be buggy -- use with caution.'
        'KickFastPlayers=false'
        ''
        '# ServerPlayerID determines if a character is from another server, or single player. This value may be changed by soft resets. If this number does match the client, the client must create a new character. This is used in conjunction with ResetID. It is strongly advised that you backup these IDs somewhere'
        'ServerPlayerID=597032252'
        ''
        '# The port for the RCON (Remote Console)\nMinimum=0 Maximum=65535 Default=27015'
        'RCONPort=27015'
        ''
        '# RCON password (Pick a strong password)'
        'RCONPassword='
        ''
        '# Enables global text chat integration with a Discord channel'
        'DiscordEnable=false'
        ''
        '# Discord bot access token'
        'DiscordToken='
        ''
        '# The Discord channel name. (Try the separate channel ID option if having difficulties)'
        'DiscordChannel='
        ''
        '# The Discord channel ID. (Use if having difficulties with Discord channel name option)'
        'DiscordChannelID='
        ''
        '# Clients must know this password to join the server. (Ignored when hosting a server via the Host button)'
        'Password='
        ''
        '# Limits the number of different accounts a single Steam user may create on this server. Ignored when using the Hosts button.\nMinimum=0 Maximum=2147483647 Default=0'
        'MaxAccountsPerUser=5'
        ''
        '# Allow co-op/splitscreen players'
        'AllowCoop=true'
        ''
        '# Players are allowed to sleep when their survivor becomes tired, but they do not NEED to sleep'
        'SleepAllowed=false'
        ''
        '# Players get tired and need to sleep. (Ignored if SleepAllowed=false)'
        'SleepNeeded=false'
        ''
        'KnockedDownAllowed=true'
        ''
        'SneakModeHideFromOtherPlayers=true'
        ''
        '# List Workshop Mod IDs for the server to download. Each must be separated by a semicolon. Example: WorkshopItems=514427485;513111049'
        'WorkshopItems='
        ''
        '# Show Steam usernames and avatars in the Players list. Can be true (visible to everyone), false (visible to no one), or admin (visible to only admins)'
        'SteamScoreboard=true'
        ''
        '# Enable the Steam VAC system'
        'SteamVAC=true'
        ''
        '# Attempt to configure a UPnP-enabled internet gateway to automatically setup port forwarding rules. The server will fall back to default ports if this fails'
        'UPnP=true'
        ''
        '# VOIP is enabled when checked'
        'VoiceEnable=true'
        ''
        '# The minimum tile distance over which VOIP sounds can be heard.\nMinimum=0.00 Maximum=100000.00 Default=10.00'
        'VoiceMinDistance=10.0'
        ''
        '# The maximum tile distance over which VOIP sounds can be heard.\nMinimum=0.00 Maximum=100000.00 Default=100.00'
        'VoiceMaxDistance=100.0'
        ''
        '# Toggle directional audio for VOIP'
        'Voice3D=true'
        ''
        '# Minimum=10.00 Maximum=150.00 Default=70.00'
        'SpeedLimit=70.0'
        ''
        'LoginQueueEnabled=false'
        ''
        '# Minimum=20 Maximum=1200 Default=60'
        'LoginQueueConnectTimeout=60'
        ''
        '# Set the IP from which the server is broadcast. This is for network configurations with multiple IP addresses, such as server farms'
        'server_browser_announced_ip='
        ''
        '# Players can respawn in-game at the coordinates where they died'
        'PlayerRespawnWithSelf=true'
        ''
        '# Players can respawn in-game at a split screen / Remote Play player''s location'
        'PlayerRespawnWithOther=false'
        ''
        '# Governs how fast time passes while players sleep. Value multiplies the speed of the time that passes during sleeping.\nMinimum=1.00 Maximum=100.00 Default=40.00'
        'FastForwardMultiplier=40.0'
        ''
        '# Safehouse acts like a normal house if a member of the safehouse is connected (so secure when players are offline)'
        'DisableSafehouseWhenPlayerConnected=false'
        ''
        '# Players can create factions when true'
        'Faction=true'
        ''
        '# Players must survive this number of in-game days before being allowed to create a faction\nMinimum=0 Maximum=2147483647 Default=0'
        'FactionDaySurvivedToCreate=0'
        ''
        '# Number of players required as faction members before the faction owner can create a group tag\nMinimum=1 Maximum=2147483647 Default=1'
        'FactionPlayersRequiredForTag=1'
        ''
        '# Disables radio transmissions from players with an access level'
        'DisableRadioStaff=false'
        ''
        '# Disables radio transmissions from players with ''admin'' access level'
        'DisableRadioAdmin=true'
        ''
        '# Disables radio transmissions from players with ''gm'' access level'
        'DisableRadioGM=true'
        ''
        '# Disables radio transmissions from players with ''overseer'' access level'
        'DisableRadioOverseer=false'
        ''
        '# Disables radio transmissions from players with ''moderator'' access level'
        'DisableRadioModerator=false'
        ''
        '# Disables radio transmissions from invisible players'
        'DisableRadioInvisible=true'
        ''
        '# Semicolon-separated list of commands that will not be written to the cmd.txt server log. For example: \n-vehicle. Inputting * means do NOT write any vehicle command. Inputting: \n+vehicle.installPart means DO write that command'
        'ClientCommandFilter=-vehicle.*;+vehicle.damageWindow;+vehicle.fixPart;+vehicle.installPart;+vehicle.uninstallPart'
        ''
        '# Semicolon-separated list of actions that will be written to the ClientActionLogs.txt server log.'
        'ClientActionLogs=ISEnterVehicle;ISExitVehicle;ISTakeEngineParts;'
        ''
        '# Track changes in player perk levels in PerkLog.txt server log'
        'PerkLogs=true'
        ''
        '# Maximum number of items that can be placed in a container.  Zero means there is no limit. (PLEASE NOTE: This includes individual small items such as nails. A limit of 50 will mean only 50 nails can be stored.)\nMinimum=0 Maximum=9000 Default=0'
        'ItemNumbersLimitPerContainer=0'
        ''
        '# Number of days before old blood splats are removed.'
        '# Removal happens when map chunks are loaded.'
        '# Zero means they will never disappear\nMinimum=0 Maximum=365 Default=0'
        'BloodSplatLifespanDays=0'
        ''
        '# Allow use of non-ASCII (cyrillic etc) characters in usernames'
        'AllowNonAsciiUsername=false'
        ''
        'BanKickGlobalSound=true'
        ''
        '# If enabled, when HoursForCorpseRemoval triggers, it will also remove player s corpses from the ground.'
        'RemovePlayerCorpsesOnCorpseRemoval=false'
        ''
        '# If true, player can use the "delete all" button on bins.'
        'TrashDeleteAll=false'
        ''
        '# If true, player can hit again when struck by another player.'
        'PVPMeleeWhileHitReaction=false'
        ''
        '# If true, players will have to mouse over someone to see their display name.'
        'MouseOverToSeeDisplayName=true'
        ''
        '# If true, automatically hide the player you can''t see (like zombies).'
        'HidePlayersBehindYou=true'
        ''
        '# Damage multiplier for PVP melee attacks.\nMinimum=0.00 Maximum=500.00 Default=30.00'
        'PVPMeleeDamageModifier=30.0'
        ''
        '# Damage multiplier for PVP ranged attacks.\nMinimum=0.00 Maximum=500.00 Default=50.00'
        'PVPFirearmDamageModifier=50.0'
        ''
        '# Modify the range of zombie attraction to cars. (Lower values can help with lag.)\nMinimum=0.00 Maximum=10.00 Default=0.50'
        'CarEngineAttractionModifier=0.5'
        ''
        '# Governs whether players bump (and knock over) other players when running through them.'
        'PlayerBumpPlayer=false'
        ''
        '# Controls display of remote players on the in-game map.\n1=Hidden 2=Friends 3=Everyone\nMinimum=1 Maximum=3 Default=1'
        'MapRemotePlayerVisibility=1'
        ''
        '# Minimum=1 Maximum=300 Default=5'
        'BackupsCount=5'
        ''
        'BackupsOnStart=true'
        ''
        'BackupsOnVersionChange=true'
        ''
        '# Minimum=0 Maximum=1500 Default=0'
        'BackupsPeriod=0'
        ''
        '# Disables anti-cheat protection for type 1.'
        'AntiCheatProtectionType1=true'
        ''
        '# Disables anti-cheat protection for type 2.'
        'AntiCheatProtectionType2=true'
        ''
        '# Disables anti-cheat protection for type 3.'
        'AntiCheatProtectionType3=true'
        ''
        '# Disables anti-cheat protection for type 4.'
        'AntiCheatProtectionType4=true'
        ''
        '# Disables anti-cheat protection for type 5.'
        'AntiCheatProtectionType5=true'
        ''
        '# Disables anti-cheat protection for type 6.'
        'AntiCheatProtectionType6=true'
        ''
        '# Disables anti-cheat protection for type 7.'
        'AntiCheatProtectionType7=true'
        ''
        '# Disables anti-cheat protection for type 8.'
        'AntiCheatProtectionType8=true'
        ''
        '# Disables anti-cheat protection for type 9.'
        'AntiCheatProtectionType9=true'
        ''
        '# Disables anti-cheat protection for type 10.'
        'AntiCheatProtectionType10=true'
        ''
        '# Disables anti-cheat protection for type 11.'
        'AntiCheatProtectionType11=true'
        ''
        '# Disables anti-cheat protection for type 12.'
        'AntiCheatProtectionType12=true'
        ''
        '# Disables anti-cheat protection for type 13.'
        'AntiCheatProtectionType13=true'
        ''
        '# Disables anti-cheat protection for type 14.'
        'AntiCheatProtectionType14=true'
        ''
        '# Disables anti-cheat protection for type 15.'
        'AntiCheatProtectionType15=true'
        ''
        '# Disables anti-cheat protection for type 16.'
        'AntiCheatProtectionType16=true'
        ''
        '# Disables anti-cheat protection for type 17.'
        'AntiCheatProtectionType17=true'
        ''
        '# Disables anti-cheat protection for type 18.'
        'AntiCheatProtectionType18=true'
        ''
        '# Disables anti-cheat protection for type 19.'
        'AntiCheatProtectionType19=true'
        ''
        '# Disables anti-cheat protection for type 20.'
        'AntiCheatProtectionType20=true'
        ''
        'AntiCheatProtectionType21=true'
        ''
        'AntiCheatProtectionType22=true'
        ''
        'AntiCheatProtectionType23=true'
        ''
        'AntiCheatProtectionType24=true'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 2.\nMinimum=1.00 Maximum=10.00 Default=3.00'
        'AntiCheatProtectionType2ThresholdMultiplier=3.0'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 3.\nMinimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType3ThresholdMultiplier=1.0'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 4.\nMinimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType4ThresholdMultiplier=1.0'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 9.\nMinimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType9ThresholdMultiplier=1.0'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 15.\nMinimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType15ThresholdMultiplier=1.0'
        ''
        '# Threshold value multiplier for anti-cheat protection: type 20.\nMinimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType20ThresholdMultiplier=1.0'
        ''
        '# Minimum=1.00 Maximum=10.00 Default=1.00'
        'AntiCheatProtectionType22ThresholdMultiplier=1.0'
        ''
        '# Minimum=1.00 Maximum=10.00 Default=6.00'
        'AntiCheatProtectionType24ThresholdMultiplier=6.0'
    )

    $safeServerName = if ([string]::IsNullOrWhiteSpace($ServerName)) { 'Project Zomboid Server' } else { [string]$ServerName }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($lines)) {
        [void]$result.Add(([string]$line).Replace('__UGSM_PUBLIC_NAME__', $safeServerName))
    }
    return @($result.ToArray())
}

function Initialize-UGSMGameProjectZomboidProfile {
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

    $effectiveProfileName = ''
    $effectiveInstallPath = ''
    $instanceId = ''

    if ($PSCmdlet.ParameterSetName -eq 'ByInstance') {
        if (-not $Instance) {
            throw 'Instance is required.'
        }

        $effectiveProfileName = [string]$Instance.Name
        $effectiveInstallPath = [string]$Instance.InstallPath
        $instanceId = [string]$Instance.Id
    }
    else {
        $effectiveProfileName = [string]$ProfileName
        $effectiveInstallPath = [string]$InstallPath
        $instanceId = ''
    }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) {
        throw 'ProfileName could not be resolved for ProjectZomboid profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        $definition = Get-UGSMGameProjectZomboidInstallDefinition
        $effectiveInstallPath = [string]$definition.InstallPath
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a ProjectZomboid profile.'
    }

    $validation = Test-UGSMGameProjectZomboidInstall -InstallPath $effectiveInstallPath
    if (-not $validation -or -not $validation.IsValid) {
        throw 'ProjectZomboid profile initialization failed: shared server binaries are not installed or failed validation.'
    }

    $profileRoot = Get-UGSMGameProjectZomboidProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Profile-light layout:
    # - binaries stay in Steam common\ProjectZomboid
    # - profile stores only instance config/save/log folders and UGSM manifests
    # - no Runtime folder and no copied server binaries
    $runtimeRoot = $profileRoot
    $runtimeSavedRoot = $profileRoot
    $runtimeConfigRoot = Join-Path $profileRoot 'Server'
    $runtimeSaveRoot = Join-Path $profileRoot 'Saves'
    $runtimeLogsRoot = Join-Path $profileRoot 'Logs'
    $pzServerName = Get-UGSMGameProjectZomboidSafeServerName -Name $effectiveProfileName

    foreach ($dir in @($profileRoot, $runtimeConfigRoot)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $serverSettingsPath = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')
    if (-not (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf)) {
        $ini = Get-UGSMGameProjectZomboidDefaultIniLines -ServerName $effectiveProfileName
        Set-Content -LiteralPath $serverSettingsPath -Value $ini -Encoding UTF8
    }

    Update-UGSMGameProjectZomboidModIni -Instance ([pscustomobject]@{ Name = $effectiveProfileName; ProfilePath = $profileRoot }) -IniPath $serverSettingsPath -SkipBackup


    foreach ($listFile in @('AdminUsers.txt','ExclusiveUsers.txt','WhitelistedUsers.txt','BannedUsers.txt','SilencedUsers.txt')) {
        $listPath = Join-Path $runtimeConfigRoot $listFile
        if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
            Set-Content -LiteralPath $listPath -Value @() -Encoding UTF8
        }
    }

    return [pscustomobject]@{
        GameId          = 'ProjectZomboid'
        InstanceId      = $instanceId
        ProfileName     = $effectiveProfileName
        InstallPath     = $effectiveInstallPath
        ProfileRoot     = $profileRoot
        RuntimeRoot     = $runtimeRoot
        ConfigRoot      = $runtimeConfigRoot
        SaveRoot        = $runtimeSaveRoot
        LogsRoot        = $runtimeLogsRoot
        Initialized     = $true
        ProfileLight    = $true
        CopiedFiles     = @(
            Get-ChildItem -LiteralPath $runtimeConfigRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName.Substring($profileRoot.Length).TrimStart('\') }
        )
    }
}

function Test-UGSMGameProjectZomboidInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameProjectZomboidInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'ProjectZomboid validation failed: InstallPath could not be resolved.'
    }

    $installPath = [string]$definition.InstallPath
    $missing = New-Object System.Collections.Generic.List[string]

    $installPathExists = Test-Path -LiteralPath $installPath -PathType Container
    if (-not $installPathExists) {
        [void]$missing.Add($installPath)
    }

    foreach ($relativePath in @($definition.RequiredFiles)) {
        $fullPath = Join-Path $installPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            [void]$missing.Add($relativePath)
        }
    }

    $serverExecutablePath = [string]$definition.ServerExecutablePath
    $exeExists = Test-Path -LiteralPath $serverExecutablePath -PathType Leaf

    return [pscustomobject]@{
        GameId                       = 'ProjectZomboid'
        InstallPath            = $installPath
        InstallPathExists      = $installPathExists
        ServerExecutablePath   = $serverExecutablePath
        ServerExecutableExists = $exeExists
        MissingItems           = @($missing)
        IsInstalled            = ($installPathExists -and $exeExists)
        IsValid                = ($installPathExists -and $exeExists -and $missing.Count -eq 0)
        NeedsRepair            = ($installPathExists -and ($missing.Count -gt 0))
    }
}


function Split-UGSMGameProjectZomboidCommandLine {
    [CmdletBinding()]
    param([AllowNull()][string]$CommandLine)

    $tokens = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }

    $current = New-Object System.Text.StringBuilder
    $inQuote = $false
    for ($i = 0; $i -lt $CommandLine.Length; $i++) {
        $ch = $CommandLine[$i]
        if ($ch -eq '"') {
            $inQuote = -not $inQuote
            continue
        }

        if ([char]::IsWhiteSpace($ch) -and -not $inQuote) {
            if ($current.Length -gt 0) {
                [void]$tokens.Add($current.ToString())
                [void]$current.Clear()
            }
            continue
        }

        [void]$current.Append($ch)
    }

    if ($current.Length -gt 0) { [void]$tokens.Add($current.ToString()) }
    return @($tokens.ToArray())
}

function Get-UGSMGameProjectZomboidJavaLaunchSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InstallDefinition,
        [Parameter(Mandatory)][string]$Cachedir,
        [Parameter(Mandatory)][string]$ServerName
    )

    $installPath = [string]$InstallDefinition.InstallPath
    if ([string]::IsNullOrWhiteSpace($installPath) -or -not (Test-Path -LiteralPath $installPath -PathType Container)) {
        throw 'ProjectZomboid Java launch failed: install path is missing.'
    }

    $javaExe = Join-Path $installPath 'jre64\bin\java.exe'
    if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf)) {
        throw "ProjectZomboid Java launch failed: java.exe was not found: $javaExe"
    }

    $startBat = Join-Path $installPath 'StartServer64.bat'
    if (-not (Test-Path -LiteralPath $startBat -PathType Leaf)) {
        throw "ProjectZomboid Java launch failed: StartServer64.bat was not found: $startBat"
    }

    $raw = Get-Content -LiteralPath $startBat -Raw -ErrorAction Stop
    $lines = @($raw -split "`r?`n")
    $javaLine = ''
    foreach ($line in $lines) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match 'zombie\.network\.GameServer') {
            $javaLine = $trimmed
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($javaLine)) {
        throw 'ProjectZomboid Java launch failed: could not find the zombie.network.GameServer command in StartServer64.bat.'
    }

    $mainIndex = $javaLine.IndexOf('zombie.network.GameServer')
    if ($mainIndex -lt 0) {
        throw 'ProjectZomboid Java launch failed: invalid StartServer64.bat command line.'
    }

    $beforeMain = $javaLine.Substring(0, $mainIndex).Trim()
    if ($beforeMain.StartsWith('@')) { $beforeMain = $beforeMain.TrimStart('@').Trim() }

    $tokens = @(Split-UGSMGameProjectZomboidCommandLine -CommandLine $beforeMain)
    $jvmArgs = New-Object System.Collections.Generic.List[string]

    $skippedJavaToken = $false
    foreach ($token in $tokens) {
        $text = [string]$token
        if (-not $skippedJavaToken) {
            $skippedJavaToken = $true
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$jvmArgs.Add($text) }
    }

    if ($jvmArgs.Count -eq 0) {
        throw 'ProjectZomboid Java launch failed: no JVM/classpath arguments could be parsed from StartServer64.bat.'
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $jvmArgs) {
        if ([string]$arg -in @('-statistic','0','-log','-nobattleye','%1','%2')) { continue }
        [void]$arguments.Add([string]$arg)
    }

    [void]$arguments.Add('zombie.network.GameServer')
    [void]$arguments.Add(('-cachedir=' + $Cachedir))
    [void]$arguments.Add('-servername')
    [void]$arguments.Add($ServerName)

    return [pscustomobject]@{
        JavaExe          = $javaExe
        WorkingDirectory = $installPath
        Arguments        = @($arguments.ToArray())
        Cachedir         = $Cachedir
        ServerName       = $ServerName
    }
}

function Start-UGSMGameProjectZomboidInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'ProjectZomboid start failed: Instance was null.'
    }

    $validation = Test-UGSMGameProjectZomboidInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'ProjectZomboid start failed: ProjectZomboid is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGameProjectZomboidInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'ProjectZomboid start failed: Install definition could not be resolved.'
    }

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGameProjectZomboidProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "ProjectZomboid start failed: Profile path was not found: $profilePath"
    }

    $runtime = Ensure-UGSMGameProjectZomboidRuntimeLayout -Instance $Instance -InstallDefinition $installDef

    $runtimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
    $runtimeSaveRoot = [string]$runtime.RuntimeSaveRootPath
    $pzServerName = Get-UGSMGameProjectZomboidSafeServerName -Name ([string]$Instance.Name)
    $serverSettingsPath = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')

    if (-not (Test-Path -LiteralPath $runtimeConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeConfigRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf)) {
        throw "ProjectZomboid start failed: Runtime Project Zomboid server INI was not found: $serverSettingsPath"
    }

    $installPath = [string]$installDef.InstallPath
    $stockBat = Join-Path $installPath 'StartServer64.bat'
    if (-not (Test-Path -LiteralPath $stockBat -PathType Leaf)) {
        throw "ProjectZomboid start failed: Stock StartServer64.bat was not found: $stockBat"
    }

    $wrapperRoot = Join-Path $profilePath 'Runtime'
    if (-not (Test-Path -LiteralPath $wrapperRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $wrapperRoot -Force | Out-Null
    }

    $wrapperPath = Join-Path $wrapperRoot 'UGSM_StartServer64.bat'

    $batText = [System.IO.File]::ReadAllText($stockBat)
    $installPathEscaped = $installPath.Replace('"', '""')
    $profilePathEscaped = $profilePath.Replace('"', '""')
    $serverNameEscaped = $pzServerName.Replace('"', '""')

    # The wrapper lives in the profile Runtime folder, but Project Zomboid's stock
    # Java, native, and classpath entries are relative to the install folder.
    # Keep the stock Java/classpath setup and only force the working directory
    # plus the final GameServer arguments.
    $batText = [regex]::Replace(
        $batText,
        '(?im)^\s*@?cd\s+/d\s+"%~dp0"\s*$',
        ('@cd /d "' + $installPathEscaped + '"')
    )

    if ($batText -notmatch '(?im)^\s*@?cd\s+/d\s+"') {
        $batText = ('@cd /d "' + $installPathEscaped + '"' + [Environment]::NewLine + $batText)
    }

    $serverTail = 'zombie.network.GameServer -cachedir="' + $profilePathEscaped + '" -servername "' + $serverNameEscaped + '"'
    $batText = [regex]::Replace(
        $batText,
        'zombie\.network\.GameServer(?:\s+[^\r\n]*)?',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $serverTail }
    )

    # Do not leave the server console waiting for a keypress when UGSM owns lifecycle.
    $batText = [regex]::Replace($batText, '(?im)^\s*pause\s*$', 'rem pause disabled by UGSM')

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($wrapperPath, $batText, $utf8NoBom)

    if (Get-Command -Name Write-UGSMGameProjectZomboidLog -ErrorAction SilentlyContinue) {
        Write-UGSMGameProjectZomboidLog -Level 'INFO' -Message ("Starting Project Zomboid via UGSM wrapper. CacheDir=$profilePath ServerName=$pzServerName Ini=$serverSettingsPath Wrapper=$wrapperPath")
    }

    $proc = Start-Process `
        -FilePath $wrapperPath `
        -WorkingDirectory $installPath `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'ProjectZomboid start failed: Start-Process did not return a valid process.'
    }

    $gamePid = [int]$proc.Id

    if ($Instance.PSObject.Properties.Name -contains 'Pid') {
        $Instance.Pid = $gamePid
    }
    if ($Instance.PSObject.Properties.Name -contains 'Status') {
        $Instance.Status = 'Running'
    }
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $Instance.ProfilePath = $profilePath
    }

    [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $Instance -CurrentPlayers 0 -PlayerCountSource 'PROJECTZOMBOID_STARTING' -PlayerCountStatus 'Pending')
    [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $Instance)

    try {
        $runtimeMarker = Join-Path $runtime.RuntimeSaveRootPath 'UGSM.Runtime.json'
        $runtimeData = [pscustomobject]@{
            InstanceId        = [string]$Instance.Id
            GameId            = 'ProjectZomboid'
            ProfilePath       = $profilePath
            RuntimeRoot       = [string]$runtime.RuntimeRoot
            RuntimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
            RuntimeSaveRoot   = [string]$runtime.RuntimeSaveRootPath
            RuntimeLogRoot    = [string]$runtime.RuntimeLogRootPath
            Pid               = $gamePid
            StartedAtUtc      = [DateTime]::UtcNow.ToString('o')
            WrapperPath       = $wrapperPath
        }
        $runtimeData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runtimeMarker -Encoding UTF8
    }
    catch {}

    return [pscustomobject]@{
        Instance = $Instance
        Pid      = $gamePid
        Status   = 'Running'
        Runtime  = $runtime
    }
}

function Stop-UGSMGameProjectZomboidInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'ProjectZomboid stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameProjectZomboidInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'ProjectZomboid stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameProjectZomboidRuntimeDefinition -Instance $Instance -InstallDefinition $installDef

    $targetProcessId = $null
    if ($Instance.PSObject.Properties.Name -contains 'Pid' -and $Instance.Pid) {
        $targetProcessId = [int]$Instance.Pid
    }

    $stopResult = $null

    if ($targetProcessId -and (Get-Command -Name Stop-UGSMProcessTree -ErrorAction SilentlyContinue)) {
        $stopResult = Stop-UGSMProcessTree -ProcessId $targetProcessId -TimeoutSeconds 20
    }
    elseif ($targetProcessId) {
        try {
            & taskkill.exe /PID $targetProcessId /T /F
        }
        catch {
            try { Stop-Process -Id $targetProcessId -Force -ErrorAction Stop } catch {}
        }

        Start-Sleep -Seconds 2

        $isStillRunning = $false
        if (Get-Command -Name Test-UGSMProcessIsRunning -ErrorAction SilentlyContinue) {
            $isStillRunning = [bool](Test-UGSMProcessIsRunning -ProcessId $targetProcessId)
        }
        else {
            try {
                $proc = Get-Process -Id $targetProcessId -ErrorAction Stop
                $isStillRunning = ($null -ne $proc -and -not $proc.HasExited)
            }
            catch {
                $isStillRunning = $false
            }
        }

        $stopResult = [pscustomobject]@{
            Pid      = $targetProcessId
            Stopped  = (-not $isStillRunning)
            TimedOut = $isStillRunning
        }
    }

    if ($targetProcessId -and ($null -eq $stopResult -or -not $stopResult.Stopped)) {
        throw ("ProjectZomboid stop failed: Process {0} is still running." -f $targetProcessId)
    }

    Start-Sleep -Seconds 2

    try {
        $runtimeMarker = Join-Path $runtime.RuntimeRoot 'UGSM.Runtime.json'
        if (Test-Path -LiteralPath $runtimeMarker -PathType Leaf) {
            Remove-Item -LiteralPath $runtimeMarker -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}

    if ($Instance.PSObject.Properties.Name -contains 'Pid') {
        $Instance.Pid = $null
    }
    if ($Instance.PSObject.Properties.Name -contains 'Status') {
        $Instance.Status = 'Stopped'
    }

    [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $Instance -CurrentPlayers 0 -PlayerCountSource 'PROJECTZOMBOID_STOPPED' -PlayerCountStatus 'Stopped' -Stopped)
    [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $Instance)

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Runtime  = $runtime
    }
}

function Register-UGSMGameProjectZomboidModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameProjectZomboidMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata          = 'Get-UGSMGameProjectZomboidMetadata'
            GetInstallDefinition = 'Get-UGSMGameProjectZomboidInstallDefinition'
            TestInstall          = 'Test-UGSMGameProjectZomboidInstall'
            TestInstance         = 'Test-UGSMGameProjectZomboidInstance'
            EnsureTemplate       = 'Ensure-UGSMGameProjectZomboid'
            EnsureProjectZomboid         = 'Ensure-UGSMGameProjectZomboid'
            InitializeProfile    = 'Initialize-UGSMGameProjectZomboidProfile'
            Start                = 'Start-UGSMGameProjectZomboidInstance'
            Stop                 = 'Stop-UGSMGameProjectZomboidInstance'
            BuildEditor          = 'New-UGSMGameProjectZomboidInstanceEditor'
            SaveEditor           = 'Save-UGSMGameProjectZomboidInstanceEditor'
        }
    }
}


function Get-UGSMGameProjectZomboidBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','ModIni')]
        [string]$Scope = 'Settings',
        [AllowNull()][string]$IniPath
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $path = [string]$IniPath

    if ([string]::IsNullOrWhiteSpace($path)) {
        $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
        if ($paths -and $paths.PSObject.Properties['ServerSettingsPath']) { $path = [string]$paths.ServerSettingsPath }
    }

    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $leaf = Split-Path -Leaf $path
        if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = 'server.ini' }
        [void]$targets.Add([pscustomobject]@{
            SourcePath    = $path
            RelativePath  = ('Server\' + $leaf)
            Label         = 'Project Zomboid server INI'
        })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameProjectZomboidManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','ModIni')]
        [string]$Scope = 'Settings',
        [AllowNull()][string]$IniPath,
        [string]$Reason = 'Project Zomboid managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameProjectZomboidBackupTargets -Instance $Instance -Scope $Scope -IniPath $IniPath)
        return Invoke-UGSMManagedFileBackup -GameId 'ProjectZomboid' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameProjectZomboidLog -Level 'WARN' -Message ('ProjectZomboid managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameProjectZomboidProfilePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $profileRoot = $null

    if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profileRoot = [string]$Instance.ProfilePath
    }
    elseif ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $profileRoot = Get-UGSMGameProjectZomboidProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'ProjectZomboid' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'ProjectZomboid profile paths could not be resolved for the selected instance.'
    }

    $runtimeRoot = Get-UGSMGameProjectZomboidRuntimeRoot -Instance $Instance
    $runtimeConfigRoot = Join-Path $runtimeRoot 'Server'
    $runtimeSaveRoot = Join-Path $runtimeRoot 'SaveFiles'
    $runtimeLogRoot = Join-Path $runtimeRoot 'Logs'
    $pzServerName = Get-UGSMGameProjectZomboidSafeServerName -Name ([string]$Instance.Name)

    $runtimeMarkerPath = Join-Path $runtimeRoot 'UGSM.Runtime.json'
    $runtimeDatabasePath = Join-Path $runtimeSaveRoot 'ProjectZomboid.db'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot

        ProfileConfigRoot           = $null
        ProfileSaveRoot             = $null
        ProfileLogRoot              = $null

        RuntimeRoot                 = $runtimeRoot
        RuntimeConfigRoot           = $runtimeConfigRoot
        RuntimeSaveRoot             = $runtimeSaveRoot
        RuntimeLogRoot              = $runtimeLogRoot
        RuntimeMarkerPath           = $runtimeMarkerPath
        IsRuntimeActive             = (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf)

        ConfigRoot                  = $runtimeConfigRoot
        SaveRoot                    = $runtimeSaveRoot
        LogRoot                     = $runtimeLogRoot

        PrimaryIniPath              = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')
        PrimaryJsonPath             = Join-Path $runtimeConfigRoot 'Gameplay.json'
        PrimaryXmlPath              = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        PrimaryCfgPath              = Join-Path $runtimeConfigRoot 'Server.cfg'

        ServerSettingsPath          = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')
        GameplayJsonPath            = Join-Path $runtimeConfigRoot 'Gameplay.json'
        GameplayXmlPath             = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        ServerCfgPath               = Join-Path $runtimeConfigRoot 'Server.cfg'

        AdminUsersPath              = Join-Path $runtimeConfigRoot 'AdminUsers.txt'
        ExclusiveUsersPath          = Join-Path $runtimeConfigRoot 'ExclusiveUsers.txt'
        WhitelistedUsersPath        = Join-Path $runtimeConfigRoot 'WhitelistedUsers.txt'
        BannedUsersPath             = Join-Path $runtimeConfigRoot 'BannedUsers.txt'
        SilencedUsersPath           = Join-Path $runtimeConfigRoot 'SilencedUsers.txt'

        RuntimePrimaryIniPath       = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')
        RuntimePrimaryJsonPath      = Join-Path $runtimeConfigRoot 'Gameplay.json'
        RuntimePrimaryXmlPath       = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        RuntimePrimaryCfgPath       = Join-Path $runtimeConfigRoot 'Server.cfg'

        RuntimeServerSettingsPath   = Join-Path $runtimeConfigRoot ($pzServerName + '.ini')
        RuntimeGameplayJsonPath     = Join-Path $runtimeConfigRoot 'Gameplay.json'
        RuntimeGameplayXmlPath      = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        RuntimeServerCfgPath        = Join-Path $runtimeConfigRoot 'Server.cfg'

        RuntimeAdminUsersPath       = Join-Path $runtimeConfigRoot 'AdminUsers.txt'
        RuntimeExclusiveUsersPath   = Join-Path $runtimeConfigRoot 'ExclusiveUsers.txt'
        RuntimeWhitelistedUsersPath = Join-Path $runtimeConfigRoot 'WhitelistedUsers.txt'
        RuntimeBannedUsersPath      = Join-Path $runtimeConfigRoot 'BannedUsers.txt'
        RuntimeSilencedUsersPath    = Join-Path $runtimeConfigRoot 'SilencedUsers.txt'

        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $runtimeDatabasePath
        DatabasePath                = $runtimeDatabasePath
    }
}

function Read-UGSMGameProjectZomboidIniFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    $section = 'General'
    $result[$section] = [ordered]@{}
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*\[(.+?)\]\s*$') {
            $section = [string]$matches[1]
            if (-not $result.Contains($section)) {
                $result[$section] = [ordered]@{}
            }
            continue
        }

        if ($line -match '^\s*([^=;#]+?)\s*=\s*(.*)$') {
            $key = [string]$matches[1].Trim()
            $value = [string]$matches[2]
            if (-not $result.Contains($section)) {
                $result[$section] = [ordered]@{}
            }
            $result[$section][$key] = $value
        }
    }

    return $result
}

function Get-UGSMGameProjectZomboidIniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$IniData,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        $DefaultValue = $null
    )

    if ($IniData -and $IniData.Contains($Section) -and $IniData[$Section].Contains($Key)) {
        return $IniData[$Section][$Key]
    }

    return $DefaultValue
}


function Write-UGSMGameProjectZomboidTextFileNoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Lines
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $cleanLines = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Lines) {
        # keep empty
    }
    elseif ($Lines -is [string]) {
        $raw = [string]$Lines
        $raw = $raw.TrimStart([char]0xFEFF)
        foreach ($line in @($raw -split "`r?`n", -1)) {
            [void]$cleanLines.Add(([string]$line).TrimStart([char]0xFEFF))
        }
    }
    elseif ($Lines -is [System.Collections.IEnumerable]) {
        foreach ($line in $Lines) {
            [void]$cleanLines.Add(([string]$line).TrimStart([char]0xFEFF))
        }
    }
    else {
        [void]$cleanLines.Add(([string]$Lines).TrimStart([char]0xFEFF))
    }

    $content = [string]::Join("`r`n", @($cleanLines.ToArray()))
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Set-UGSMGameProjectZomboidIniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        [AllowNull()]
        [string]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($existingLine in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$existingLine)
        }
    }

    $flatMode = ([string]::IsNullOrWhiteSpace($Section) -or [string]$Section -in @('General','PZ','ProjectZomboid','Root'))
    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*='

    if ($flatMode) {
        # Project Zomboid server INI files are flat key=value files, not [section]-based INI files.
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $keyRegex) {
                $lines[$i] = $Key + '=' + $Value
                Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
                return
            }
        }

        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            [void]$lines.Add('')
        }
        [void]$lines.Add($Key + '=' + $Value)
        Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
        return
    }

    $isFlatProjectZomboidIni = ([string]::IsNullOrWhiteSpace($Section) -or [string]::Equals([string]$Section, 'General', [System.StringComparison]::OrdinalIgnoreCase))
    if ($isFlatProjectZomboidIni) {
        $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*='
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $keyRegex) {
                $lines[$i] = $Key + '=' + $Value
                Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
                return
            }
        }

        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add($Key + '=' + $Value)
        Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
        return
    }

    if ($lines.Count -eq 0) {
        $lines.Add('[' + $Section + ']')
        $lines.Add($Key + '=' + $Value)
        Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
        return
    }

    $sectionRegex = '^\s*\[' + [regex]::Escape($Section) + '\]\s*$'
    $sectionStart = -1
    $sectionEnd = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $sectionRegex) {
            $sectionStart = $i
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^\s*\[.+\]\s*$') {
                    $sectionEnd = $j
                    break
                }
            }
            break
        }
    }

    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add('[' + $Section + ']')
        $lines.Add($Key + '=' + $Value)
        Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
        return
    }

    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i] -match $keyRegex) {
            $lines[$i] = $Key + '=' + $Value
            Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
            return
        }
    }

    $insertIndex = $sectionEnd
    $lines.Insert($insertIndex, $Key + '=' + $Value)
    Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
}

function Read-UGSMGameProjectZomboidStringListFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Write-UGSMGameProjectZomboidStringListFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Values
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $cleanValues = @(
        $Values |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $cleanValues
}


function Ensure-UGSMGameProjectZomboidParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameProjectZomboidJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ($raw | ConvertFrom-Json -Depth 100)
}

function Write-UGSMGameProjectZomboidJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameProjectZomboidParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGameProjectZomboidXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ([xml]$raw)
}

function Write-UGSMGameProjectZomboidXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameProjectZomboidParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameProjectZomboidCfgFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*[= ]\s*"?(.+?)"?\s*;?\s*$') {
            $result[[string]$matches[1]] = [string]$matches[2]
        }
    }

    return $result
}

function Set-UGSMGameProjectZomboidCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameProjectZomboidParentDirectory -Path $Path

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($existingLine in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$existingLine)
        }
    }

    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*[= ]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $keyRegex) {
            $lines[$i] = ('{0} = "{1}"' -f $Key, $Value)
            Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
            return
        }
    }

    [void]$lines.Add(('{0} = "{1}"' -f $Key, $Value))
    Write-UGSMGameProjectZomboidTextFileNoBom -Path $Path -Lines $lines
}

# GAME-SPECIFIC OPTIONAL BLOCK
# Remove this whole PSSQLite section unless the target game really stores editable server/admin data in SQLite.
function Test-UGSMGameProjectZomboidPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameProjectZomboidPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameProjectZomboidPSSQLiteInstalled)
}

function Get-UGSMGameProjectZomboidElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameProjectZomboidPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        return @()
    }

    Import-Module PSSQLite -ErrorAction Stop | Out-Null

    $tableExists = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='elevated_users';" -ErrorAction Stop
    if (-not $tableExists) {
        return @()
    }

    $rows = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT user_id FROM elevated_users ORDER BY user_id;' -ErrorAction Stop)
    return @(
        $rows |
        ForEach-Object { [string]$_.user_id } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Save-UGSMGameProjectZomboidElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameProjectZomboidPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'ProjectZomboid.db was not found.'
    }

    Import-Module PSSQLite -ErrorAction Stop | Out-Null

    $escapedIds = @(
        $UserIds |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -match '^\d{17}$' } |
        Select-Object -Unique
    )

    $queries = [System.Collections.Generic.List[string]]::new()
    $queries.Add('CREATE TABLE IF NOT EXISTS elevated_users (user_id TEXT NOT NULL PRIMARY KEY);')
    $queries.Add('DELETE FROM elevated_users;')
    foreach ($id in $escapedIds) {
        $queries.Add(("INSERT INTO elevated_users (user_id) VALUES ('{0}');" -f $id.Replace("'", "''")))
    }

    $queryText = 'BEGIN TRANSACTION; ' + ($queries -join ' ') + ' COMMIT;'
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $queryText -ErrorAction Stop | Out-Null
}


function Resolve-UGSMGameProjectZomboidEditorFieldPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Paths,
        [ValidateSet('Active', 'Profile', 'Runtime')]
        [string]$TargetSet = 'Active'
    )

    $configRoot = [string]$Paths.RuntimeConfigRoot
    if ([string]::IsNullOrWhiteSpace($configRoot)) {
        $configRoot = [string]$Paths.ConfigRoot
    }

    if ($Field.ContainsKey('Path') -and -not [string]::IsNullOrWhiteSpace([string]$Field.Path)) {
        $rawPath = [string]$Field.Path
        if ([System.IO.Path]::IsPathRooted($rawPath)) {
            return $rawPath
        }
    }

    switch ([string]$Field.Id) {
        'AdminUsers' { return [string]$Paths.RuntimeAdminUsersPath }
        'ExclusiveUsers' { return [string]$Paths.RuntimeExclusiveUsersPath }
        'WhitelistedUsers' { return [string]$Paths.RuntimeWhitelistedUsersPath }
        'BannedUsers' { return [string]$Paths.RuntimeBannedUsersPath }
        'SilencedUsers' { return [string]$Paths.RuntimeSilencedUsersPath }
        default {
            if ($Field.ContainsKey('Path') -and -not [string]::IsNullOrWhiteSpace([string]$Field.Path) -and -not [string]::IsNullOrWhiteSpace($configRoot)) {
                return [string](Join-Path $configRoot ([string]$Field.Path))
            }

            return $null
        }
    }
}

function ConvertTo-UGSMGameProjectZomboidEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'Boolean' {
            return [string]$(if ($Control.Checked) { 'True' } else { 'False' })
        }
        'InstanceBoolean' {
            if ($Control -and $Control.PSObject.Properties['Checked']) {
                return [bool]$Control.Checked
            }
            return $false
        }
        'Number' {
            $raw = [decimal]$Control.Value
            $decimals = if ($Field.ContainsKey('Decimals')) { [int]$Field.Decimals } else { 0 }
            return [string]$raw.ToString(('F' + $decimals), [System.Globalization.CultureInfo]::InvariantCulture)
        }
        'MultilineText' {
            return [string](($Control.Lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        }
        default {
            return [string]$Control.Text
        }
    }
}


function Get-UGSMGameProjectZomboidInstanceDefinitionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'DefinitionPath') {
        $value = [string]$Instance.DefinitionPath
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'ProfilePath') {
        $profilePath = [string]$Instance.ProfilePath
        if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
            return (Join-Path $profilePath 'instance.json')
        }
    }

    return $null
}

function Save-UGSMGameProjectZomboidInstanceDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    foreach ($commandName in @('Save-UGSMInstance', 'Update-UGSMInstance', 'Set-UGSMInstance')) {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            try {
                & $commandName -Instance $Instance | Out-Null
                return $true
            }
            catch { }
        }
    }

    foreach ($commandName in @('Save-UGSMInstances', 'Save-UGSMInstanceStore')) {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            try {
                & $commandName | Out-Null
                return $true
            }
            catch { }
        }
    }

    $definitionPath = Get-UGSMGameProjectZomboidInstanceDefinitionPath -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace([string]$definitionPath)) {
        try {
            $parent = Split-Path -Parent $definitionPath
            if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $json = $Instance | ConvertTo-Json -Depth 16
            Set-Content -LiteralPath $definitionPath -Value $json -Encoding UTF8 -ErrorAction Stop
            return $true
        }
        catch { }
    }

    return $false
}


function Get-UGSMGameProjectZomboidSafeServerName {
    [CmdletBinding()]
    param([AllowNull()][string]$Name)

    $value = [string]$Name
    if ([string]::IsNullOrWhiteSpace($value)) { $value = 'PZServer' }
    $value = [regex]::Replace($value.Trim(), '[^A-Za-z0-9_.-]+', '')
    if ([string]::IsNullOrWhiteSpace($value)) { $value = 'PZServer' }
    return $value
}


function Set-UGSMGameProjectZomboidInstanceProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if (-not $Instance.PSObject.Properties[$Name]) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
    else {
        $Instance.$Name = $Value
    }

    return $Instance
}

function Get-UGSMGameProjectZomboidServerRuntimeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $serverName = ''
    if ($Instance.PSObject.Properties['Name']) {
        $serverName = [string]$Instance.Name
    }

    $publicName = $serverName
    $maxPlayers = 0
    $iniPath = $null

    try {
        $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
        $iniPath = [string]$paths.ServerSettingsPath

        if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
            $safeName = Get-UGSMGameProjectZomboidSafeServerName -Name $serverName
            $fallbackPath = Join-Path (Join-Path ([string]$paths.ProfileRoot) 'Server') ($safeName + '.ini')
            if (Test-Path -LiteralPath $fallbackPath -PathType Leaf) {
                $iniPath = $fallbackPath
            }
        }

        if (Test-Path -LiteralPath $iniPath -PathType Leaf) {
            $iniData = Read-UGSMGameProjectZomboidIniFile -Path $iniPath

            $publicNameValue = Get-UGSMGameProjectZomboidIniValue -IniData $iniData -Section 'General' -Key 'PublicName' -DefaultValue $null
            if (-not [string]::IsNullOrWhiteSpace([string]$publicNameValue)) {
                $publicName = [string]$publicNameValue
            }

            $maxValue = Get-UGSMGameProjectZomboidIniValue -IniData $iniData -Section 'General' -Key 'MaxPlayers' -DefaultValue $null
            $parsedMax = 0
            if ([int]::TryParse([string]$maxValue, [ref]$parsedMax)) {
                $maxPlayers = [Math]::Max(0, $parsedMax)
            }
        }
    }
    catch { }

    if ($maxPlayers -le 0 -and $Instance.PSObject.Properties['MaxPlayers']) {
        $parsedInstanceMax = 0
        if ([int]::TryParse([string]$Instance.MaxPlayers, [ref]$parsedInstanceMax)) {
            $maxPlayers = [Math]::Max(0, $parsedInstanceMax)
        }
    }

    return [pscustomobject]@{
        ServerName       = $serverName
        PublicServerName = $publicName
        DisplayName      = $publicName
        MaxPlayers       = $maxPlayers
        IniPath          = $iniPath
    }
}

function Set-UGSMGameProjectZomboidNormalizedRuntimeFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Nullable[int]]$CurrentPlayers,
        [string]$PlayerCountSource = '',
        [string]$PlayerCountStatus = '',
        [string]$PlayerCountDetail = '',
        [switch]$Stopped
    )

    $settings = Get-UGSMGameProjectZomboidServerRuntimeSettings -Instance $Instance

    if ($Stopped) {
        $CurrentPlayers = 0
        if ([string]::IsNullOrWhiteSpace($PlayerCountSource)) { $PlayerCountSource = 'PROJECTZOMBOID_STOPPED' }
        if ([string]::IsNullOrWhiteSpace($PlayerCountStatus)) { $PlayerCountStatus = 'Stopped' }
    }
    elseif ($null -eq $CurrentPlayers) {
        $CurrentPlayers = 0
        if ([string]::IsNullOrWhiteSpace($PlayerCountStatus)) { $PlayerCountStatus = 'Pending' }
    }

    $safeCurrent = [Math]::Max(0, [int]$CurrentPlayers)
    $safeMax = [Math]::Max(0, [int]$settings.MaxPlayers)

    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'ServerName' -Value ([string]$settings.ServerName))
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PublicServerName' -Value ([string]$settings.PublicServerName))
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'DisplayName' -Value ([string]$settings.DisplayName))
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'MaxPlayers' -Value $safeMax)
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'ServerMaxPlayers' -Value $safeMax)

    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'CurrentPlayers' -Value $safeCurrent)
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayerCount' -Value $safeCurrent)
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'OnlinePlayers' -Value $safeCurrent)
    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayersOnline' -Value $safeCurrent)

    if (-not [string]::IsNullOrWhiteSpace($PlayerCountSource)) {
        [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayerCountSource' -Value $PlayerCountSource)
    }
    if (-not [string]::IsNullOrWhiteSpace($PlayerCountStatus)) {
        [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayerCountStatus' -Value $PlayerCountStatus)
    }
    if (-not [string]::IsNullOrWhiteSpace($PlayerCountDetail)) {
        [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayerCountDetail' -Value $PlayerCountDetail)
    }

    [void](Set-UGSMGameProjectZomboidInstanceProperty -Instance $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o')))

    return $Instance
}

function Get-UGSMGameProjectZomboidRecentLogLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Tail = 2000
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    try {
        return @(Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction Stop)
    }
    catch {
        try {
            return @([System.IO.File]::ReadAllLines($Path))
        }
        catch {
            return @()
        }
    }
}

function Get-UGSMGameProjectZomboidCurrentPlayerCountFromUserLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = $null
    try { $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance } catch { return $null }

    $logRootCandidates = @()
    foreach ($candidate in @($paths.LogRoot, (Join-Path ([string]$paths.ProfileRoot) 'Logs'))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath ([string]$candidate) -PathType Container)) {
            $logRootCandidates += [string]$candidate
        }
    }

    $userLog = $null
    foreach ($root in ($logRootCandidates | Select-Object -Unique)) {
        $candidate = Get-ChildItem -LiteralPath $root -Filter '*_user.txt' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($candidate) {
            $userLog = $candidate
            break
        }
    }

    if (-not $userLog) {
        return [pscustomobject]@{
            Success = $false
            Count   = 0
            Source  = 'PROJECTZOMBOID_USER_LOG'
            Status  = 'NoLog'
            Detail  = 'No *_user.txt log was found.'
        }
    }

    $activePlayers = @{}
    $lines = Get-UGSMGameProjectZomboidRecentLogLines -Path $userLog.FullName -Tail 4000

    foreach ($line in $lines) {
        $text = [string]$line

        if ($text -match '^\[[^\]]+\]\s+(?<SteamId>\d+)\s+"[^"]+"\s+fully connected\b') {
            $activePlayers[$Matches.SteamId] = $true
            continue
        }

        if ($text -match '^\[[^\]]+\]\s+(?<SteamId>\d+)\s+"[^"]+"\s+(?:removed connection index=\d+|disconnected player\b)') {
            if ($activePlayers.ContainsKey($Matches.SteamId)) {
                $activePlayers.Remove($Matches.SteamId)
            }
            continue
        }
    }

    return [pscustomobject]@{
        Success = $true
        Count   = [int]$activePlayers.Count
        Source  = 'PROJECTZOMBOID_USER_LOG'
        Status  = 'OK'
        Detail  = ('Log={0}' -f $userLog.Name)
    }
}

function Get-UGSMGameProjectZomboidCurrentPlayerCountFromChatLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = $null
    try { $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance } catch { return $null }

    $logRoot = Join-Path ([string]$paths.ProfileRoot) 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
        return $null
    }

    $chatLog = Get-ChildItem -LiteralPath $logRoot -Filter '*_chat.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $chatLog) {
        return $null
    }

    $activePlayers = @{}
    $lines = Get-UGSMGameProjectZomboidRecentLogLines -Path $chatLog.FullName -Tail 2000

    foreach ($line in $lines) {
        $text = [string]$line

        if ($text -match "Player\s+.+\((?<Id>\d+)\)\s+joined to chat server successfully") {
            $activePlayers[$Matches.Id] = $true
            continue
        }

        if ($text -match "Player\s+(?<Id>\d+)\s+disconnecting") {
            if ($activePlayers.ContainsKey($Matches.Id)) {
                $activePlayers.Remove($Matches.Id)
            }
            continue
        }
    }

    return [pscustomobject]@{
        Success = $true
        Count   = [int]$activePlayers.Count
        Source  = 'PROJECTZOMBOID_CHAT_LOG'
        Status  = 'OK'
        Detail  = ('Log={0}' -f $chatLog.Name)
    }
}

function Get-UGSMGameProjectZomboidCurrentPlayerCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $userResult = Get-UGSMGameProjectZomboidCurrentPlayerCountFromUserLog -Instance $Instance
    if ($userResult -and $userResult.Success) {
        return $userResult
    }

    $chatResult = Get-UGSMGameProjectZomboidCurrentPlayerCountFromChatLog -Instance $Instance
    if ($chatResult -and $chatResult.Success) {
        return $chatResult
    }

    if ($userResult) { return $userResult }

    return [pscustomobject]@{
        Success = $false
        Count   = 0
        Source  = 'PROJECTZOMBOID_LOG'
        Status  = 'NoLog'
        Detail  = 'No usable Project Zomboid player log was found.'
    }
}

function Update-UGSMGameProjectZomboidDiscordRuntimeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if (-not $Instance) { return $null }

    $isRunning = $false
    if ($Instance.PSObject.Properties['Status']) {
        $isRunning = ([string]$Instance.Status -eq 'Running')
    }

    if (-not $isRunning) {
        [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $Instance -CurrentPlayers 0 -PlayerCountSource 'PROJECTZOMBOID_STOPPED' -PlayerCountStatus 'Stopped' -Stopped)
        [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $Instance)
        return $Instance
    }

    $countResult = Get-UGSMGameProjectZomboidCurrentPlayerCount -Instance $Instance
    if ($countResult -and $countResult.Success) {
        [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $Instance -CurrentPlayers ([int]$countResult.Count) -PlayerCountSource ([string]$countResult.Source) -PlayerCountStatus ([string]$countResult.Status) -PlayerCountDetail ([string]$countResult.Detail))
    }
    else {
        $source = 'PROJECTZOMBOID_LOG'
        $status = 'Pending'
        $detail = ''
        if ($countResult) {
            $source = [string]$countResult.Source
            $status = [string]$countResult.Status
            $detail = [string]$countResult.Detail
        }
        [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $Instance -CurrentPlayers 0 -PlayerCountSource $source -PlayerCountStatus $status -PlayerCountDetail $detail)
    }

    [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $Instance)
    return $Instance
}


function Get-UGSMGameProjectZomboidModConfigFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    $workshopIds = [System.Collections.Generic.List[string]]::new()
    $modIds = [System.Collections.Generic.List[string]]::new()
    $mapFolders = [System.Collections.Generic.List[string]]::new()

    try {
        if (-not $ModsDefinition) { $ModsDefinition = Get-UGSMGameProjectZomboidModsDefinition }
        if (Get-Command -Name Read-UGSMModsManifest -ErrorAction SilentlyContinue) {
            $manifest = Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition
            if ($manifest -and $manifest.PSObject.Properties['Mods']) {
                foreach ($mod in @($manifest.Mods)) {
                    if (-not $mod) { continue }
                    $enabled = $true
                    if ($mod.PSObject.Properties['Enabled']) { $enabled = [bool]$mod.Enabled }
                    if (-not $enabled) { continue }

                    $wid = ''
                    foreach ($propName in @('WorkshopId','Id')) {
                        if ($mod.PSObject.Properties[$propName] -and [string]$mod.$propName -match '^\d+$') { $wid = [string]$mod.$propName; break }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($wid) -and -not $workshopIds.Contains($wid)) { [void]$workshopIds.Add($wid) }

                    foreach ($propName in @('ModId','ModID','PZModId','Name')) {
                        if ($mod.PSObject.Properties[$propName]) {
                            $mid = [string]$mod.$propName
                            if (-not [string]::IsNullOrWhiteSpace($mid) -and $mid -notmatch '^Workshop\s+\d+$' -and -not $modIds.Contains($mid)) { [void]$modIds.Add($mid) }
                            break
                        }
                    }

                    foreach ($propName in @('MapFolders','MapFolder','Map')) {
                        if ($mod.PSObject.Properties[$propName]) {
                            foreach ($map in @($mod.$propName)) {
                                $mapText = [string]$map
                                if (-not [string]::IsNullOrWhiteSpace($mapText) -and -not $mapFolders.Contains($mapText)) { [void]$mapFolders.Add($mapText) }
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-UGSMGameProjectZomboidLog -Level 'WARN' -Message ('Failed to build PZ mod config from manifest: ' + $_.Exception.Message)
    }

    if ($mapFolders.Count -gt 0 -and -not $mapFolders.Contains('Muldraugh, KY')) { [void]$mapFolders.Add('Muldraugh, KY') }

    return [pscustomobject]@{
        WorkshopItems = ($workshopIds.ToArray() -join ';')
        Mods          = ($modIds.ToArray() -join ';')
        Map           = ($mapFolders.ToArray() -join ';')
    }
}

function Update-UGSMGameProjectZomboidModIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$IniPath,
        [switch]$SkipBackup
    )

    $modConfig = Get-UGSMGameProjectZomboidModConfigFromManifest -Instance $Instance -ModsDefinition (Get-UGSMGameProjectZomboidModsDefinition)
    if (-not $SkipBackup) {
        Invoke-UGSMGameProjectZomboidManagedBackup -Instance $Instance -Scope 'ModIni' -IniPath $IniPath -Reason 'Before Project Zomboid mod INI sync' | Out-Null
    }
    Set-UGSMGameProjectZomboidIniValue -Path $IniPath -Section 'General' -Key 'WorkshopItems' -Value ([string]$modConfig.WorkshopItems)
    Set-UGSMGameProjectZomboidIniValue -Path $IniPath -Section 'General' -Key 'Mods' -Value ([string]$modConfig.Mods)
    Set-UGSMGameProjectZomboidIniValue -Path $IniPath -Section 'General' -Key 'Map' -Value ([string]$modConfig.Map)
}

function Save-UGSMGameProjectZomboidInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameProjectZomboidInstanceDiscordShape -Instance $Instance
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false

    foreach ($dirPath in @($paths.ConfigRoot, $paths.SaveRoot, $paths.LogRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }

    $saveSummary = [ordered]@{
        IniKeysWritten        = 0
        StringListsWritten    = 0
        RuntimeCopiesUpdated  = 0
        InstanceSettingsSaved = 0
    }

    Invoke-UGSMGameProjectZomboidManagedBackup -Instance $updatedInstance -Scope 'Settings' -IniPath $paths.ServerSettingsPath -Reason 'Before Project Zomboid settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameProjectZomboidEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameProjectZomboidEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("ProjectZomboid save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameProjectZomboidStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control
                Set-UGSMGameProjectZomboidIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control
                Set-UGSMGameProjectZomboidIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control
                Set-UGSMGameProjectZomboidIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control
                Set-UGSMGameProjectZomboidIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = ConvertTo-UGSMGameProjectZomboidEditorFieldValue -Field $field -Control $control
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = [bool]$value
                    $hasDiscordChanges = $true
                }
            }
        }
    }

    if ($hasDiscordChanges) {
        $persistScript = {
            param($PersistedInstance)
            [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    Update-UGSMGameProjectZomboidModIni -Instance $updatedInstance -IniPath $paths.ServerSettingsPath -SkipBackup

    $existingCurrentPlayers = 0
    $existingStatus = 'Pending'
    $existingSource = 'PROJECTZOMBOID_SETTINGS_SAVE'
    if ($updatedInstance.PSObject.Properties['CurrentPlayers']) {
        [void][int]::TryParse([string]$updatedInstance.CurrentPlayers, [ref]$existingCurrentPlayers)
    }
    if ($updatedInstance.PSObject.Properties['PlayerCountStatus'] -and -not [string]::IsNullOrWhiteSpace([string]$updatedInstance.PlayerCountStatus)) {
        $existingStatus = [string]$updatedInstance.PlayerCountStatus
    }
    if ($updatedInstance.PSObject.Properties['PlayerCountSource'] -and -not [string]::IsNullOrWhiteSpace([string]$updatedInstance.PlayerCountSource)) {
        $existingSource = [string]$updatedInstance.PlayerCountSource
    }

    [void](Set-UGSMGameProjectZomboidNormalizedRuntimeFields -Instance $updatedInstance -CurrentPlayers $existingCurrentPlayers -PlayerCountSource $existingSource -PlayerCountStatus $existingStatus)
    [void](Save-UGSMGameProjectZomboidInstanceDefinition -Instance $updatedInstance)

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved ProjectZomboid settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameProjectZomboidInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Instance = Ensure-UGSMGameProjectZomboidInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
    $schema = Get-UGSMGameProjectZomboidEditorSchema
    $iniData = Read-UGSMGameProjectZomboidIniFile -Path $paths.ServerSettingsPath
    $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
    $controlMap = @{}
    $layout = [ordered]@{
        HeaderHeight             = 52
        ToolbarHeight            = 40
        ContentPadding           = 12
        RowGap                   = 6
        LabelWidth               = 170
        ControlWidth             = 340
        WideControlWidth         = 620
        NarrowControlWidth       = 110
        SectionDescriptionHeight = 22
        MultilineHeight          = 52
        StringListHeight         = 92
    }

    function Get-ProjectZomboidSafeIniValue {
        param([hashtable]$Field)
        try {
            return [string](Get-UGSMGameProjectZomboidIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-ProjectZomboidSafeInstanceValue {
        param([hashtable]$Field)

        try {
            if ([string]$Field.Model -eq 'Discord') {
                $propertyName = [string]$Field.Property
                if (-not [string]::IsNullOrWhiteSpace($propertyName) -and $discordModel.PSObject.Properties[$propertyName]) {
                    return $discordModel.$propertyName
                }
            }
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-ProjectZomboidTextBox {
        param(
            [int]$Width = 340,
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-Object System.Windows.Forms.TextBox
        $null = $tb.SuspendLayout()
        try {
            $tb.Width = $Width
            $tb.Margin = New-Object System.Windows.Forms.Padding(0)
            $tb.BorderStyle = 'FixedSingle'
            $tb.BackColor = [System.Drawing.Color]::White
            $tb.ForeColor = [System.Drawing.Color]::Black
            $tb.Multiline = [bool]$Multiline
            $tb.AutoSize = $false

            if ($Multiline) {
                $tb.AcceptsReturn = $true
                $tb.AcceptsTab = $true
                $tb.ScrollBars = 'Vertical'
                $tb.WordWrap = $true
                $tb.Height = $Height
            }
            else {
                $tb.ScrollBars = 'None'
                $tb.Height = 24
                if ($MaskSecret) {
                    $tb.UseSystemPasswordChar = $true
                    $tb.PasswordChar = '*'
                }
            }
        }
        finally {
            $tb.ResumeLayout($false)
        }

        return $tb
    }

    function New-ProjectZomboidStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-ProjectZomboidTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-ProjectZomboidNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-ProjectZomboidElevatedUsersControl {
        param(
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Panel]$Parent,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        $wrapper = New-Object System.Windows.Forms.TableLayoutPanel
        $wrapper.Dock = 'Top'
        $wrapper.AutoSize = $true
        $wrapper.AutoSizeMode = 'GrowAndShrink'
        $wrapper.Margin = New-Object System.Windows.Forms.Padding(0)
        $wrapper.Padding = New-Object System.Windows.Forms.Padding(0)
        $wrapper.ColumnCount = 2
        $wrapper.RowCount = 7
        [void]$wrapper.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 52)))
        [void]$wrapper.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 48)))
        for ($i = 0; $i -lt 7; $i++) {
            [void]$wrapper.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
        }

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits ProjectZomboid.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
        $status.AutoSize = $false
        [void]$wrapper.Controls.Add($status, 0, 0)
        $wrapper.SetColumnSpan($status, 2)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Dock = 'Fill'
        $list.Height = 170
        $list.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
        $list.BackColor = New-UGSMColor '#0E1620'
        $list.ForeColor = New-UGSMColor $Theme.Text
        [void]$wrapper.Controls.Add($list, 0, 1)
        $wrapper.SetRowSpan($list, 6)

        $txtUser = New-Object System.Windows.Forms.TextBox
        $txtUser.Dock = 'Top'
        $txtUser.Margin = New-Object System.Windows.Forms.Padding(0)
        $txtUser.Height = 24
        [void]$wrapper.Controls.Add($txtUser, 1, 1)

        $hintId = New-UGSMLabel -Text 'Steam64 ID' -X 0 -Y 0 -Width 220 -Height 18 -FontSize 8.5 -Color $Theme.Muted
        [void]$wrapper.Controls.Add($hintId, 1, 2)

        $btnInstallSql = New-UGSMButton -Text 'Install PSSQLite' -Width 150 -Height 28 -BackColor '#7C3AED'
        $btnInstallSql.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnInstallSql, 1, 3)

        $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttonRow.Dock = 'Top'
        $buttonRow.AutoSize = $true
        $buttonRow.WrapContents = $false
        $buttonRow.FlowDirection = 'LeftToRight'
        $buttonRow.Margin = New-Object System.Windows.Forms.Padding(0)
        $btnLoadDb = New-UGSMButton -Text 'Load DB' -Width 78 -Height 28
        $btnAddDb = New-UGSMButton -Text 'Add User' -Width 90 -Height 28 -BackColor $Theme.AccentBlue
        [void]$buttonRow.Controls.Add($btnLoadDb)
        [void]$buttonRow.Controls.Add($btnAddDb)
        [void]$wrapper.Controls.Add($buttonRow, 1, 4)

        $btnRemoveDb = New-UGSMButton -Text 'Remove Selected' -Width 150 -Height 28 -BackColor '#A63A2D'
        $btnRemoveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnRemoveDb, 1, 5)

        $btnSaveDb = New-UGSMButton -Text 'Save DB' -Width 150 -Height 28 -BackColor $Theme.Accent
        $btnSaveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnSaveDb, 1, 6)

        $loadDbState = {
            $list.Items.Clear()
            $moduleInstalled = Test-UGSMGameProjectZomboidPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in ProjectZomboid.db.')
                return
            }

            $dbPath = Resolve-UGSMGameProjectZomboidDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('ProjectZomboid.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('ProjectZomboid.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameProjectZomboidElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading ProjectZomboid.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameProjectZomboidPSSQLite | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'Installed PSSQLite for the current user.' }
                    & $loadDbState
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'PSSQLite install failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())
        $btnLoadDb.Add_Click({ & $loadDbState }.GetNewClosure())
        $btnAddDb.Add_Click({
                $id = [string]$txtUser.Text.Trim()
                if ($id -notmatch '^\d{17}$') {
                    if ($StatusLabel) { $StatusLabel.Text = 'Enter a valid 17-digit Steam64 ID.' }
                    return
                }
                if (-not $list.Items.Contains($id)) { [void]$list.Items.Add($id) }
                $txtUser.Clear()
            }.GetNewClosure())
        $btnRemoveDb.Add_Click({ if ($list.SelectedIndex -ge 0) { $list.Items.RemoveAt($list.SelectedIndex) } }.GetNewClosure())
        $btnSaveDb.Add_Click({
                try {
                    $userIds = @()
                    foreach ($item in $list.Items) {
                        $text = [string]$item
                        if ($text -match '^\d{17}$') { $userIds += $text }
                    }
                    $dbPath = Resolve-UGSMGameProjectZomboidDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'ProjectZomboid.db path could not be resolved for this instance.' }
                    Save-UGSMGameProjectZomboidElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to ProjectZomboid.db: ' + $dbPath }
                    & $loadDbState
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'Saving elevated users failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())
        $txtUser.Add_KeyDown({
                param($sender, $e)
                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                    $e.SuppressKeyPress = $true
                    $btnAddDb.PerformClick()
                }
            }.GetNewClosure())

        & $loadDbState

        if ($Parent) {
            [void]$Parent.Controls.Add($wrapper)
        }

        return $wrapper
    }

    function Add-ProjectZomboidFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the ProjectZomboid editor can render any supported schema shape.
        if ($null -eq $Field) { return }
        if ($Field -isnot [hashtable]) {
            $normalizedField = @{}
            if ($Field -is [System.Collections.IDictionary]) {
                foreach ($key in $Field.Keys) { $normalizedField[[string]$key] = $Field[$key] }
            }
            else {
                foreach ($prop in @($Field.PSObject.Properties)) {
                    if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Name)) {
                        $normalizedField[[string]$prop.Name] = $prop.Value
                    }
                }
            }
            $Field = $normalizedField
        }


        if ([string]$Field.Type -eq 'ModsProviderPanel') {
            $modsHost = New-Object System.Windows.Forms.Panel
            $modsHost.Dock = 'Top'
            $modsHost.AutoSize = $false
            $modsHost.AutoScroll = $true
            $modsHost.Height = 720
            $modsHost.Width = [Math]::Max(760, $Parent.ClientSize.Width - 16)
            $modsHost.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

            $modsDefinition = $null
            if ($Field.ContainsKey('ModsDefinition')) { $modsDefinition = $Field.ModsDefinition }
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameProjectZomboidModsDefinition }

            $sharedRenderer = Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue
            if ($sharedRenderer) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared Steam Workshop Mods editor is not loaded. Load UGSM_Game_Helper.ps1 before opening this tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
                [void]$modsHost.Controls.Add($missing)
            }

            [void]$Parent.Controls.Add($modsHost)
            return
        }

        $row = New-Object System.Windows.Forms.TableLayoutPanel
        $row.Dock = 'Top'
        $row.AutoSize = $true
        $row.AutoSizeMode = 'GrowAndShrink'
        $row.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $layout.RowGap)
        $row.ColumnCount = 2
        $row.RowCount = if ([string]::IsNullOrWhiteSpace([string]$Field.Hint)) { 1 } else { 2 }
        [void]$row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $layout.LabelWidth)))
        [void]$row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 700)))
        [void]$row.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
        if ($row.RowCount -gt 1) {
            [void]$row.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
        }

        $label = New-UGSMLabel -Text ([string]$Field.Label) -X 0 -Y 0 -Width ($layout.LabelWidth - 12) -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        $label.Dock = 'Fill'
        $label.TextAlign = 'MiddleLeft'
        $label.Margin = New-Object System.Windows.Forms.Padding(0)
        [void]$row.Controls.Add($label, 0, 0)

        try {
            $control = $null
            switch ([string]$Field.Type) {
                'Boolean' {
                    $fieldHost = New-ProjectZomboidNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-ProjectZomboidSafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-ProjectZomboidNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-ProjectZomboidSafeInstanceValue -Field $Field
                    if ($instanceValue -is [bool]) {
                        $control.Checked = [bool]$instanceValue
                    }
                    else {
                        $control.Checked = ([string]$instanceValue -match '^(?i:true|1|yes)$')
                    }
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-ProjectZomboidNarrowHost
                    $control = New-Object System.Windows.Forms.NumericUpDown
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.Width = $layout.NarrowControlWidth
                    $control.Anchor = 'Left'
                    $min = if ($Field.ContainsKey('Min')) { [decimal]$Field.Min } else { [decimal]0 }
                    $max = if ($Field.ContainsKey('Max')) { [decimal]$Field.Max } else { [decimal]2147483647 }
                    $decimals = if ($Field.ContainsKey('Decimals')) { [int]$Field.Decimals } else { 0 }
                    $control.Minimum = $min
                    $control.Maximum = $max
                    $control.DecimalPlaces = $decimals
                    $control.Increment = if ($Field.ContainsKey('Increment')) { [decimal]::Parse([string]$Field.Increment, [System.Globalization.CultureInfo]::InvariantCulture) } elseif ($decimals -gt 0) { [decimal]0.1 } else { [decimal]1 }
                    $rawValue = Get-ProjectZomboidSafeIniValue -Field $Field
                    $numericValue = [decimal]0
                    if (-not [decimal]::TryParse([string]$rawValue, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numericValue)) {
                        $fallbackValue = if ($Field.ContainsKey('DefaultValue')) { [string]$Field.DefaultValue } else { '0' }
                        [void][decimal]::TryParse([string]$fallbackValue, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numericValue)
                    }
                    if ($numericValue -lt $control.Minimum) { $numericValue = $control.Minimum }
                    if ($numericValue -gt $control.Maximum) { $numericValue = $control.Maximum }
                    $control.Value = $numericValue
                    [void]$numberHost.Controls.Add($control)
                    [void]$row.Controls.Add($numberHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'MultilineText' {
                    $control = New-ProjectZomboidStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-ProjectZomboidSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-ProjectZomboidStretchTextBox -MaskSecret
                    $control.Text = [string](Get-ProjectZomboidSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-ProjectZomboidStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-ProjectZomboidSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-ProjectZomboidTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameProjectZomboidEditorFieldPath -Field $Field -Paths $paths
                    $control.Tag = [string]$resolvedListPath
                    $control.ScrollBars = 'Vertical'
                    $control.AcceptsReturn = $true
                    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedListPath) -and (Test-Path -LiteralPath $resolvedListPath -PathType Leaf)) {
                        $control.Lines = @(Get-Content -LiteralPath $resolvedListPath -ErrorAction SilentlyContinue)
                    }
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control; Path = $resolvedListPath }
                }
                'ActiveModsList' {
                    $control = New-ProjectZomboidTextBox -Width $layout.WideControlWidth -Multiline -Height 160
                    $control.ScrollBars = 'Vertical'
                    $control.ReadOnly = $true
                    $control.AcceptsReturn = $true

                    $summaryText = ''
                    try {
                        $modsDefForList = Get-UGSMGameProjectZomboidModsDefinition
                        if (Get-Command -Name Resolve-UGSMModsSummaryPath -ErrorAction SilentlyContinue) {
                            $summaryPath = Resolve-UGSMModsSummaryPath -Instance $Instance -ModsDefinition $modsDefForList
                            if (-not [string]::IsNullOrWhiteSpace([string]$summaryPath) -and (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
                                $summaryText = [string]::Join([Environment]::NewLine, @(Get-Content -LiteralPath $summaryPath -ErrorAction SilentlyContinue))
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($summaryText) -and (Get-Command -Name Read-UGSMModsManifest -ErrorAction SilentlyContinue)) {
                            $manifest = Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefForList
                            if (Get-Command -Name Get-UGSMModsSummaryLines -ErrorAction SilentlyContinue) {
                                $summaryText = [string]::Join([Environment]::NewLine, @(Get-UGSMModsSummaryLines -Manifest $manifest))
                            }
                        }
                    }
                    catch {
                        $summaryText = 'Unable to load active mods summary: ' + $_.Exception.Message
                    }

                    if ([string]::IsNullOrWhiteSpace($summaryText)) {
                        $summaryText = 'No active mods are configured for this profile yet.'
                    }

                    $control.Text = $summaryText
                    [void]$row.Controls.Add($control, 1, 0)
                }

                'ActionButton' {
                    $buttonHost = New-ProjectZomboidNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid action failed: ' + $_.Exception.Message } }
                        }.GetNewClosure())
                    [void]$buttonHost.Controls.Add($control)
                    [void]$row.Controls.Add($buttonHost, 1, 0)
                }
                'ElevatedUsers' {
                    $elevatedHost = New-Object System.Windows.Forms.Panel
                    $elevatedHost.Dock = 'Top'
                    $elevatedHost.AutoSize = $true
                    $elevatedHost.AutoSizeMode = 'GrowAndShrink'
                    $elevatedHost.Margin = New-Object System.Windows.Forms.Padding(0)
                    $elevatedHost.Padding = New-Object System.Windows.Forms.Padding(0)

                    New-ProjectZomboidElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-ProjectZomboidStretchTextBox
                    $control.Text = [string](Get-ProjectZomboidSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
            }

            if ($Field.Type -ne 'ElevatedUsers' -and -not [string]::IsNullOrWhiteSpace([string]$Field.Hint)) {
                $hint = New-UGSMLabel -Text ([string]$Field.Hint) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Muted
                $hint.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
                [void]$row.Controls.Add($hint, 1, 1)
            }
        }
        catch {
            $errorLabel = New-UGSMLabel -Text ('ProjectZomboid field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color '#FF7B72'
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-ProjectZomboidEditorContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
            [string]$Description,
            [object[]]$Fields
        )

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.BackColor = New-UGSMColor '#0B121D'
        [void]$Parent.Controls.Add($scroll)

        $content = New-Object System.Windows.Forms.FlowLayoutPanel
        $content.Dock = 'Top'
        $content.AutoSize = $true
        $content.AutoSizeMode = 'GrowAndShrink'
        $content.FlowDirection = 'TopDown'
        $content.WrapContents = $false
        $content.Margin = New-Object System.Windows.Forms.Padding(0)
        $content.Padding = New-Object System.Windows.Forms.Padding($layout.ContentPadding, 10, $layout.ContentPadding, 10)
        $content.BackColor = New-UGSMColor '#0B121D'
        $content.Width = [Math]::Max(760, $scroll.ClientSize.Width - 24)
        $content.MaximumSize = New-Object System.Drawing.Size([Math]::Max(760, $scroll.ClientSize.Width - 24), 0)
        [void]$scroll.Controls.Add($content)

        $refreshScrollLayout = {
            $targetWidth = [Math]::Max(760, $scroll.ClientSize.Width - 24)
            $content.Width = $targetWidth
            $content.MaximumSize = New-Object System.Drawing.Size($targetWidth, 0)
            $preferred = $content.GetPreferredSize((New-Object System.Drawing.Size($targetWidth, 0)))
            $scroll.AutoScrollMinSize = New-Object System.Drawing.Size(0, [Math]::Max($preferred.Height + 20, $scroll.ClientSize.Height + 1))
        }.GetNewClosure()

        $scroll.Add_Resize({ & $refreshScrollLayout }.GetNewClosure())

        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $descRow = New-Object System.Windows.Forms.TableLayoutPanel
            $descRow.Dock = 'Top'
            $descRow.AutoSize = $true
            $descRow.AutoSizeMode = 'GrowAndShrink'
            $descRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
            $descRow.ColumnCount = 1
            [void]$descRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
            $desc = New-UGSMLabel -Text ([string]$Description) -X 0 -Y 0 -Width 760 -Height $layout.SectionDescriptionHeight -FontSize 8.5 -Color $Theme.Muted
            $desc.AutoSize = $false
            $desc.Margin = New-Object System.Windows.Forms.Padding(0)
            [void]$descRow.Controls.Add($desc, 0, 0)
            [void]$content.Controls.Add($descRow)
        }

        foreach ($field in @($Fields)) {
            Add-ProjectZomboidFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
        }

        & $refreshScrollLayout
    }

    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = New-UGSMColor '#11161C'

        $root = New-Object System.Windows.Forms.TableLayoutPanel
        $root.Dock = 'Fill'
        $root.Margin = New-Object System.Windows.Forms.Padding(0)
        $root.Padding = New-Object System.Windows.Forms.Padding(0)
        $root.BackColor = New-UGSMColor '#11161C'
        $root.ColumnCount = 1
        $root.RowCount = 3
        [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.HeaderHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.ToolbarHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$HostPanel.Controls.Add($root)

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Fill'
        $header.BackColor = New-UGSMColor '#09111B'
        [void]$root.Controls.Add($header, 0, 0)

        $title = New-UGSMLabel -Text ('ProjectZomboid Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
        $pathLabel = New-UGSMLabel -Text ([string]$paths.ProfileRoot) -X 12 -Y 28 -Width 760 -Height 16 -FontSize 8 -Color $Theme.Muted
        [void]$header.Controls.Add($title)
        [void]$header.Controls.Add($pathLabel)

        $toolbar = New-Object System.Windows.Forms.Panel
        $toolbar.Dock = 'Fill'
        $toolbar.BackColor = New-UGSMColor '#09111B'
        [void]$root.Controls.Add($toolbar, 0, 1)

        $toolbarButtons = New-Object System.Windows.Forms.FlowLayoutPanel
        $toolbarButtons.Dock = 'Right'
        $toolbarButtons.AutoSize = $true
        $toolbarButtons.AutoSizeMode = 'GrowAndShrink'
        $toolbarButtons.FlowDirection = 'LeftToRight'
        $toolbarButtons.WrapContents = $false
        $toolbarButtons.Padding = New-Object System.Windows.Forms.Padding(0, 6, 10, 0)
        $toolbarButtons.BackColor = [System.Drawing.Color]::Transparent
        [void]$toolbar.Controls.Add($toolbarButtons)

        $btnReload = New-UGSMButton -Text 'Reload' -X 0 -Y 0 -Width 84 -Height 28 -BackColor '#253341'
        $btnSave = New-UGSMButton -Text 'Save All' -X 0 -Y 0 -Width 96 -Height 28 -BackColor $Theme.Accent
        $btnReload.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
        $btnSave.Margin = New-Object System.Windows.Forms.Padding(0)
        [void]$toolbarButtons.Controls.Add($btnReload)
        [void]$toolbarButtons.Controls.Add($btnSave)

        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.Margin = New-Object System.Windows.Forms.Padding(0)
        [void]$root.Controls.Add($tabs, 0, 2)

        foreach ($tabDef in @($schema.Tabs)) {
            $tabPage = New-Object System.Windows.Forms.TabPage
            $tabPage.Text = [string]$tabDef.Title
            $tabPage.BackColor = New-UGSMColor '#0B121D'
            [void]$tabs.TabPages.Add($tabPage)

            $usesSharedModsEditor = [bool](
                ($tabDef.PSObject.Properties.Name -contains 'UsesSharedModsEditor' -and [bool]$tabDef.UsesSharedModsEditor) -or
                ([string]$tabDef.Title -eq 'Mods' -and [bool]$features.Mods -and (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -ErrorAction SilentlyContinue))
            )

            if ($usesSharedModsEditor) {
                try {
                    $modsDefinition = Get-UGSMGameProjectZomboidModsDefinition
                    New-UGSMSharedSteamWorkshopModsEditor -Parent $tabPage -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel | Out-Null
                }
                catch {
                    $errorPanel = New-Object System.Windows.Forms.Panel
                    $errorPanel.Dock = 'Fill'
                    $errorPanel.BackColor = New-UGSMColor '#0B121D'
                    [void]$tabPage.Controls.Add($errorPanel)
                    $errorLabel = New-UGSMLabel -Text ('Shared Mods tab failed to load: ' + $_.Exception.Message) -X 12 -Y 12 -Width 900 -Height 24 -FontSize 9 -Color '#FF7B72'
                    [void]$errorPanel.Controls.Add($errorLabel)
                    if ($StatusLabel) { $StatusLabel.Text = 'Shared Mods tab failed to load: ' + $_.Exception.Message }
                }
            }
            elseif ($tabDef.PSObject.Properties.Name -contains 'SubTabs' -and @($tabDef.SubTabs).Count -gt 0) {
                $subTabs = New-Object System.Windows.Forms.TabControl
                $subTabs.Dock = 'Fill'
                [void]$tabPage.Controls.Add($subTabs)

                foreach ($subDef in @($tabDef.SubTabs)) {
                    $subPage = New-Object System.Windows.Forms.TabPage
                    $subPage.Text = [string]$subDef.Title
                    $subPage.BackColor = New-UGSMColor '#0B121D'
                    [void]$subTabs.TabPages.Add($subPage)
                    New-ProjectZomboidEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-ProjectZomboidEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameProjectZomboidInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved ProjectZomboid profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameProjectZomboidInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'ProjectZomboid profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameProjectZomboidOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'ProjectZomboid open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("ProjectZomboid open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'ProjectZomboid open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("ProjectZomboid open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("ProjectZomboid open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameProjectZomboidEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'ProjectZomboid action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("ProjectZomboid action failed: could not resolve paths for '{0}'." -f $Target)
    }

    $candidate = switch ($Target) {
        'ServerSettings' { [string]$Paths.ServerSettingsPath }
        'PrimaryIni' { [string]$Paths.PrimaryIniPath }
        'PrimaryJson' { [string]$Paths.PrimaryJsonPath }
        'PrimaryXml' { [string]$Paths.PrimaryXmlPath }
        'PrimaryCfg' { [string]$Paths.PrimaryCfgPath }
        'AdminUsers' { [string]$Paths.AdminUsersPath }
        'ExclusiveUsers' { [string]$Paths.ExclusiveUsersPath }
        'WhitelistedUsers' { [string]$Paths.WhitelistedUsersPath }
        'BannedUsers' { [string]$Paths.BannedUsersPath }
        'SilencedUsers' { [string]$Paths.SilencedUsersPath }
        'ConfigFolder' { [string]$Paths.ConfigRoot }
        'ProfileFolder' { [string]$Paths.ProfileRoot }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        throw ("ProjectZomboid action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameProjectZomboidEditorAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    $resolvedPath = Resolve-UGSMGameProjectZomboidEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameProjectZomboidOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Resolve-UGSMGameProjectZomboidEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'ProjectZomboid action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("ProjectZomboid action failed: could not resolve paths for '{0}'." -f $Target)
    }

    $candidate = switch ($Target) {
        'ServerSettings' { [string]$Paths.ServerSettingsPath }
        'PrimaryIni' { [string]$Paths.PrimaryIniPath }
        'PrimaryJson' { [string]$Paths.PrimaryJsonPath }
        'PrimaryXml' { [string]$Paths.PrimaryXmlPath }
        'PrimaryCfg' { [string]$Paths.PrimaryCfgPath }
        'AdminUsers' { [string]$Paths.AdminUsersPath }
        'ExclusiveUsers' { [string]$Paths.ExclusiveUsersPath }
        'WhitelistedUsers' { [string]$Paths.WhitelistedUsersPath }
        'BannedUsers' { [string]$Paths.BannedUsersPath }
        'SilencedUsers' { [string]$Paths.SilencedUsersPath }
        'ConfigFolder' { [string]$Paths.ConfigRoot }
        'ProfileFolder' { [string]$Paths.ProfileRoot }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        throw ("ProjectZomboid action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameProjectZomboidEditorAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    $resolvedPath = Resolve-UGSMGameProjectZomboidEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameProjectZomboidOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}


<#Adjust Schema to be game specific. these values were taken from Ark Survival Evolved. #>




function Get-UGSMGameProjectZomboidEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenPrimaryIni     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameProjectZomboidEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryIni'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened Project Zomboid server INI.' }
    }

    $features = Get-UGSMGameProjectZomboidSupportedFeatures

    # ============================================================
    # ProjectZomboid GAME SCHEMA
    # This is the main section to edit when copying this file.
    # Keep fields generic here. Add game-specific tabs/fields only after
    # copying the ProjectZomboid into a real UGSM_Game_<Game>.ps1 module.
    # Password/secret fields should use Type='Password' or Secret=$true.
    # ============================================================

    $schema = [pscustomobject]@{
        Version = 3
        Tabs = @(
            [pscustomobject]@{
                Title       = 'General'
                Description = 'Basic public identity, access, and server browser settings.'
                Fields      = @(
                    @{ Id = 'PublicName'; Type = 'Text'; File = 'PZServer.ini'; Section = 'General'; Key = 'PublicName'; Label = 'Server Name'; DefaultValue = 'My PZ Server'; Hint = 'Project Zomboid PublicName setting.' }
                    @{ Id = 'PublicDescription'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'PublicDescription'; Label = 'Server Description'; DefaultValue = 'UGSM Project Zomboid server'; Hint = 'Project Zomboid PublicDescription setting.' }
                    @{ Id = 'ServerWelcomeMessage'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'ServerWelcomeMessage'; Label = 'Welcome Message'; DefaultValue = 'Welcome to Project Zomboid Multiplayer! <LINE> <LINE> To interact with the Chat panel: press Tab, T, or Enter. <LINE> <LINE> The Tab key will change the target stream of the message. <LINE> <LINE> Global Streams: /all <LINE> Local Streams: /say, /yell <LINE> Special Steams: /whisper, /safehouse, /faction. <LINE> <LINE> Press the Up arrow to cycle through your message history. Click the Gear icon to customize chat. <LINE> <LINE> Happy surviving!'; Hint = 'Supports Project Zomboid <LINE> and RGB tags such as <RGB:1,0,0>.' }
                    @{ Id = 'Password'; Type = 'Password'; File = 'PZServer.ini'; Section = 'General'; Key = 'Password'; Label = 'Server Password'; DefaultValue = ''; Hint = 'Masked on screen for privacy/streaming.'; Secret = $true }
                    @{ Id = 'MaxPlayers'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'MaxPlayers'; Label = 'Max Players'; DefaultValue = 5; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid MaxPlayers setting.' }
                    @{ Id = 'Public'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'Public'; Label = 'Public Server'; DefaultValue = $true; Hint = 'Project Zomboid Public setting.' }
                    @{ Id = 'Open'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'Open'; Label = 'Open Server'; DefaultValue = $true; Hint = 'Project Zomboid Open setting.' }
                    @{ Id = 'AutoCreateUserInWhiteList'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AutoCreateUserInWhiteList'; Label = 'Auto Create User In White List'; DefaultValue = $true; Hint = 'Project Zomboid AutoCreateUserInWhiteList setting.' }
                    @{ Id = 'ResetID'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'ResetID'; Label = 'Reset ID'; DefaultValue = 4775295; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid ResetID setting.' }
                    @{ Id = 'ServerPlayerID'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'ServerPlayerID'; Label = 'Server Player ID'; DefaultValue = 597032252; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid ServerPlayerID setting.' }
                    @{ Id = 'server_browser_announced_ip'; Type = 'Text'; File = 'PZServer.ini'; Section = 'General'; Key = 'server_browser_announced_ip'; Label = 'Server Browser Announced IP'; DefaultValue = ''; Hint = 'Project Zomboid server_browser_announced_ip setting.' }
                    @{ Id = 'MaxAccountsPerUser'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'MaxAccountsPerUser'; Label = 'Max Accounts Per User'; DefaultValue = 5; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid MaxAccountsPerUser setting.' }
                    @{ Id = 'AllowCoop'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AllowCoop'; Label = 'Allow Coop'; DefaultValue = $true; Hint = 'Project Zomboid AllowCoop setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network / Ports'
                Description = 'Network, Steam, login queue, and RCON settings. Change ports with caution because conflicting ports can prevent servers from starting.'
                Fields      = @(
                    @{ Id = 'DefaultPort'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'DefaultPort'; Label = 'Default Port'; DefaultValue = 16261; Min = 0; Max = 65535; Decimals = 0; Hint = 'Port setting. Change with caution; conflicts with another server can prevent startup.' }
                    @{ Id = 'UDPPort'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'UDPPort'; Label = 'UDP Port'; DefaultValue = 16262; Min = 0; Max = 65535; Decimals = 0; Hint = 'Port setting. Change with caution; conflicts with another server can prevent startup.' }
                    @{ Id = 'RCONPort'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'RCONPort'; Label = 'RCON Port'; DefaultValue = 27015; Min = 0; Max = 65535; Decimals = 0; Hint = 'Port setting. Change with caution; conflicts with another server can prevent startup.' }
                    @{ Id = 'RCONPassword'; Type = 'Password'; File = 'PZServer.ini'; Section = 'General'; Key = 'RCONPassword'; Label = 'RCON Password'; DefaultValue = ''; Hint = 'Masked on screen for privacy/streaming.'; Secret = $true }
                    @{ Id = 'UPnP'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'UPnP'; Label = 'UPnP'; DefaultValue = $true; Hint = 'Project Zomboid UPnP setting.' }
                    @{ Id = 'SteamScoreboard'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SteamScoreboard'; Label = 'Steam Scoreboard'; DefaultValue = $true; Hint = 'Project Zomboid SteamScoreboard setting.' }
                    @{ Id = 'SteamVAC'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SteamVAC'; Label = 'Steam VAC'; DefaultValue = $true; Hint = 'Project Zomboid SteamVAC setting.' }
                    @{ Id = 'PingLimit'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'PingLimit'; Label = 'Ping Limit'; DefaultValue = 400; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid PingLimit setting.' }
                    @{ Id = 'DenyLoginOnOverloadedServer'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DenyLoginOnOverloadedServer'; Label = 'Deny Login On Overloaded Server'; DefaultValue = $true; Hint = 'Project Zomboid DenyLoginOnOverloadedServer setting.' }
                    @{ Id = 'LoginQueueEnabled'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'LoginQueueEnabled'; Label = 'Login Queue Enabled'; DefaultValue = $false; Hint = 'Project Zomboid LoginQueueEnabled setting.' }
                    @{ Id = 'LoginQueueConnectTimeout'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'LoginQueueConnectTimeout'; Label = 'Login Queue Connect Timeout'; DefaultValue = 60; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid LoginQueueConnectTimeout setting.' }
                    @{ Id = 'SpeedLimit'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SpeedLimit'; Label = 'Speed Limit'; DefaultValue = 70.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid SpeedLimit setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Player Rules'
                Description = 'PvP, names, safety, chat, sleep, and respawn behavior.'
                Fields      = @(
                    @{ Id = 'PVP'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PVP'; Label = 'Allow PvP'; DefaultValue = $false; Hint = 'Project Zomboid PVP setting.' }
                    @{ Id = 'PauseEmpty'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PauseEmpty'; Label = 'Pause When Empty'; DefaultValue = $true; Hint = 'Project Zomboid PauseEmpty setting.' }
                    @{ Id = 'GlobalChat'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'GlobalChat'; Label = 'Global Chat'; DefaultValue = $true; Hint = 'Project Zomboid GlobalChat setting.' }
                    @{ Id = 'ChatStreams'; Type = 'Text'; File = 'PZServer.ini'; Section = 'General'; Key = 'ChatStreams'; Label = 'Chat Streams'; DefaultValue = 's,r,a,w,y,sh,f,all'; Hint = 'Project Zomboid ChatStreams setting.' }
                    @{ Id = 'DisplayUserName'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisplayUserName'; Label = 'Display Usernames'; DefaultValue = $true; Hint = 'Project Zomboid DisplayUserName setting.' }
                    @{ Id = 'ShowFirstAndLastName'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'ShowFirstAndLastName'; Label = 'Show First And Last Name'; DefaultValue = $false; Hint = 'Project Zomboid ShowFirstAndLastName setting.' }
                    @{ Id = 'SafetySystem'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafetySystem'; Label = 'Safety System'; DefaultValue = $true; Hint = 'Project Zomboid SafetySystem setting.' }
                    @{ Id = 'ShowSafety'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'ShowSafety'; Label = 'Show Safety'; DefaultValue = $true; Hint = 'Project Zomboid ShowSafety setting.' }
                    @{ Id = 'SafetyToggleTimer'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafetyToggleTimer'; Label = 'Safety Toggle Timer'; DefaultValue = 2; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid SafetyToggleTimer setting.' }
                    @{ Id = 'SafetyCooldownTimer'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafetyCooldownTimer'; Label = 'Safety Cooldown Timer'; DefaultValue = 3; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid SafetyCooldownTimer setting.' }
                    @{ Id = 'SleepAllowed'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SleepAllowed'; Label = 'Sleep Allowed'; DefaultValue = $false; Hint = 'Project Zomboid SleepAllowed setting.' }
                    @{ Id = 'SleepNeeded'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SleepNeeded'; Label = 'Sleep Needed'; DefaultValue = $false; Hint = 'Project Zomboid SleepNeeded setting.' }
                    @{ Id = 'KnockedDownAllowed'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'KnockedDownAllowed'; Label = 'Knocked Down Allowed'; DefaultValue = $true; Hint = 'Project Zomboid KnockedDownAllowed setting.' }
                    @{ Id = 'SneakModeHideFromOtherPlayers'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SneakModeHideFromOtherPlayers'; Label = 'Sneak Mode Hide From Other Players'; DefaultValue = $true; Hint = 'Project Zomboid SneakModeHideFromOtherPlayers setting.' }
                    @{ Id = 'PlayerRespawnWithSelf'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PlayerRespawnWithSelf'; Label = 'Player Respawn With Self'; DefaultValue = $true; Hint = 'Project Zomboid PlayerRespawnWithSelf setting.' }
                    @{ Id = 'PlayerRespawnWithOther'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PlayerRespawnWithOther'; Label = 'Player Respawn With Other'; DefaultValue = $false; Hint = 'Project Zomboid PlayerRespawnWithOther setting.' }
                    @{ Id = 'DropOffWhiteListAfterDeath'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DropOffWhiteListAfterDeath'; Label = 'Drop Off White List After Death'; DefaultValue = $false; Hint = 'Project Zomboid DropOffWhiteListAfterDeath setting.' }
                    @{ Id = 'KickFastPlayers'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'KickFastPlayers'; Label = 'Kick Fast Players'; DefaultValue = $false; Hint = 'Project Zomboid KickFastPlayers setting.' }
                    @{ Id = 'AnnounceDeath'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AnnounceDeath'; Label = 'Announce Death'; DefaultValue = $false; Hint = 'Project Zomboid AnnounceDeath setting.' }
                    @{ Id = 'AllowNonAsciiUsername'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AllowNonAsciiUsername'; Label = 'Allow Non Ascii Username'; DefaultValue = $false; Hint = 'Project Zomboid AllowNonAsciiUsername setting.' }
                    @{ Id = 'BanKickGlobalSound'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'BanKickGlobalSound'; Label = 'Ban Kick Global Sound'; DefaultValue = $true; Hint = 'Project Zomboid BanKickGlobalSound setting.' }
                    @{ Id = 'MouseOverToSeeDisplayName'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'MouseOverToSeeDisplayName'; Label = 'Mouse Over To See Display Name'; DefaultValue = $true; Hint = 'Project Zomboid MouseOverToSeeDisplayName setting.' }
                    @{ Id = 'HidePlayersBehindYou'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'HidePlayersBehindYou'; Label = 'Hide Players Behind You'; DefaultValue = $true; Hint = 'Project Zomboid HidePlayersBehindYou setting.' }
                    @{ Id = 'PlayerBumpPlayer'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PlayerBumpPlayer'; Label = 'Player Bump Player'; DefaultValue = $false; Hint = 'Project Zomboid PlayerBumpPlayer setting.' }
                    @{ Id = 'PVPMeleeWhileHitReaction'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PVPMeleeWhileHitReaction'; Label = 'PvPMelee While Hit Reaction'; DefaultValue = $false; Hint = 'Project Zomboid PVPMeleeWhileHitReaction setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Voice / Radio'
                Description = 'Voice distance and staff/admin radio visibility.'
                Fields      = @(
                    @{ Id = 'VoiceEnable'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'VoiceEnable'; Label = 'Voice Chat'; DefaultValue = $true; Hint = 'Project Zomboid VoiceEnable setting.' }
                    @{ Id = 'VoiceMinDistance'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'VoiceMinDistance'; Label = 'Voice Min Distance'; DefaultValue = 10.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid VoiceMinDistance setting.' }
                    @{ Id = 'VoiceMaxDistance'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'VoiceMaxDistance'; Label = 'Voice Max Distance'; DefaultValue = 100.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid VoiceMaxDistance setting.' }
                    @{ Id = 'Voice3D'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'Voice3D'; Label = '3D Voice'; DefaultValue = $true; Hint = 'Project Zomboid Voice3D setting.' }
                    @{ Id = 'DisableRadioStaff'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioStaff'; Label = 'Disable Radio Staff'; DefaultValue = $false; Hint = 'Project Zomboid DisableRadioStaff setting.' }
                    @{ Id = 'DisableRadioAdmin'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioAdmin'; Label = 'Disable Radio Admin'; DefaultValue = $true; Hint = 'Project Zomboid DisableRadioAdmin setting.' }
                    @{ Id = 'DisableRadioGM'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioGM'; Label = 'Disable Radio GM'; DefaultValue = $true; Hint = 'Project Zomboid DisableRadioGM setting.' }
                    @{ Id = 'DisableRadioOverseer'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioOverseer'; Label = 'Disable Radio Overseer'; DefaultValue = $false; Hint = 'Project Zomboid DisableRadioOverseer setting.' }
                    @{ Id = 'DisableRadioModerator'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioModerator'; Label = 'Disable Radio Moderator'; DefaultValue = $false; Hint = 'Project Zomboid DisableRadioModerator setting.' }
                    @{ Id = 'DisableRadioInvisible'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableRadioInvisible'; Label = 'Disable Radio Invisible'; DefaultValue = $true; Hint = 'Project Zomboid DisableRadioInvisible setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Gameplay / World'
                Description = 'Gameplay, loot, corpses, fire, speed, and general world rules.'
                Fields      = @(
                    @{ Id = 'SpawnPoint'; Type = 'Text'; File = 'PZServer.ini'; Section = 'General'; Key = 'SpawnPoint'; Label = 'Spawn Point'; DefaultValue = '0,0,0'; Hint = 'Project Zomboid SpawnPoint setting.' }
                    @{ Id = 'SpawnItems'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'SpawnItems'; Label = 'Spawn Items'; DefaultValue = ''; Hint = 'Project Zomboid SpawnItems setting.' }
                    @{ Id = 'NoFire'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'NoFire'; Label = 'No Fire'; DefaultValue = $false; Hint = 'Project Zomboid NoFire setting.' }
                    @{ Id = 'MinutesPerPage'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'MinutesPerPage'; Label = 'Minutes Per Page'; DefaultValue = 0.25; Min = 0; Max = 2147483647; Decimals = 2; Increment = '0.1'; Hint = 'Project Zomboid MinutesPerPage setting.' }
                    @{ Id = 'SaveWorldEveryMinutes'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SaveWorldEveryMinutes'; Label = 'Save World Every Minutes'; DefaultValue = 30; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid SaveWorldEveryMinutes setting.' }
                    @{ Id = 'HoursForLootRespawn'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'HoursForLootRespawn'; Label = 'Hours For Loot Respawn'; DefaultValue = 1; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid HoursForLootRespawn setting.' }
                    @{ Id = 'MaxItemsForLootRespawn'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'MaxItemsForLootRespawn'; Label = 'Max Items For Loot Respawn'; DefaultValue = 5; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid MaxItemsForLootRespawn setting.' }
                    @{ Id = 'ConstructionPreventsLootRespawn'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'ConstructionPreventsLootRespawn'; Label = 'Construction Prevents Loot Respawn'; DefaultValue = $false; Hint = 'Project Zomboid ConstructionPreventsLootRespawn setting.' }
                    @{ Id = 'FastForwardMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'FastForwardMultiplier'; Label = 'Fast Forward Multiplier'; DefaultValue = 40.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid FastForwardMultiplier setting.' }
                    @{ Id = 'ItemNumbersLimitPerContainer'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'ItemNumbersLimitPerContainer'; Label = 'Item Numbers Limit Per Container'; DefaultValue = 0; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid ItemNumbersLimitPerContainer setting.' }
                    @{ Id = 'BloodSplatLifespanDays'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'BloodSplatLifespanDays'; Label = 'Blood Splat Lifespan Days'; DefaultValue = 0; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid BloodSplatLifespanDays setting.' }
                    @{ Id = 'RemovePlayerCorpsesOnCorpseRemoval'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'RemovePlayerCorpsesOnCorpseRemoval'; Label = 'Remove Player Corpses On Corpse Removal'; DefaultValue = $false; Hint = 'Project Zomboid RemovePlayerCorpsesOnCorpseRemoval setting.' }
                    @{ Id = 'TrashDeleteAll'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'TrashDeleteAll'; Label = 'Trash Delete All'; DefaultValue = $false; Hint = 'Project Zomboid TrashDeleteAll setting.' }
                    @{ Id = 'PVPMeleeDamageModifier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'PVPMeleeDamageModifier'; Label = 'PvPMelee Damage Modifier'; DefaultValue = 30.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid PVPMeleeDamageModifier setting.' }
                    @{ Id = 'PVPFirearmDamageModifier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'PVPFirearmDamageModifier'; Label = 'PvPFirearm Damage Modifier'; DefaultValue = 50.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid PVPFirearmDamageModifier setting.' }
                    @{ Id = 'CarEngineAttractionModifier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'CarEngineAttractionModifier'; Label = 'Car Engine Attraction Modifier'; DefaultValue = 0.5; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid CarEngineAttractionModifier setting.' }
                    @{ Id = 'MapRemotePlayerVisibility'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'MapRemotePlayerVisibility'; Label = 'Map Remote Player Visibility'; DefaultValue = 1; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid MapRemotePlayerVisibility setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Safehouse / Factions'
                Description = 'Safehouse, faction, and base protection settings.'
                Fields      = @(
                    @{ Id = 'PlayerSafehouse'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'PlayerSafehouse'; Label = 'Player Safehouse'; DefaultValue = $false; Hint = 'Project Zomboid PlayerSafehouse setting.' }
                    @{ Id = 'AdminSafehouse'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AdminSafehouse'; Label = 'Admin Safehouse'; DefaultValue = $false; Hint = 'Project Zomboid AdminSafehouse setting.' }
                    @{ Id = 'SafehouseAllowTrepass'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseAllowTrepass'; Label = 'Safehouse Allow Trespass'; DefaultValue = $true; Hint = 'Project Zomboid SafehouseAllowTrepass setting.' }
                    @{ Id = 'SafehouseAllowFire'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseAllowFire'; Label = 'Safehouse Allow Fire'; DefaultValue = $true; Hint = 'Project Zomboid SafehouseAllowFire setting.' }
                    @{ Id = 'SafehouseAllowLoot'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseAllowLoot'; Label = 'Safehouse Allow Loot'; DefaultValue = $true; Hint = 'Project Zomboid SafehouseAllowLoot setting.' }
                    @{ Id = 'SafehouseAllowRespawn'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseAllowRespawn'; Label = 'Safehouse Allow Respawn'; DefaultValue = $true; Hint = 'Project Zomboid SafehouseAllowRespawn setting.' }
                    @{ Id = 'SafehouseDaySurvivedToClaim'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseDaySurvivedToClaim'; Label = 'Safehouse Day Survived To Claim'; DefaultValue = 0; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid SafehouseDaySurvivedToClaim setting.' }
                    @{ Id = 'SafeHouseRemovalTime'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafeHouseRemovalTime'; Label = 'Safehouse Removal Time'; DefaultValue = 144; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid SafeHouseRemovalTime setting.' }
                    @{ Id = 'SafehouseAllowNonResidential'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SafehouseAllowNonResidential'; Label = 'Safehouse Allow Non Residential'; DefaultValue = $true; Hint = 'Project Zomboid SafehouseAllowNonResidential setting.' }
                    @{ Id = 'AllowDestructionBySledgehammer'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AllowDestructionBySledgehammer'; Label = 'Allow Destruction By Sledgehammer'; DefaultValue = $true; Hint = 'Project Zomboid AllowDestructionBySledgehammer setting.' }
                    @{ Id = 'SledgehammerOnlyInSafehouse'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'SledgehammerOnlyInSafehouse'; Label = 'Sledgehammer Only In Safehouse'; DefaultValue = $false; Hint = 'Project Zomboid SledgehammerOnlyInSafehouse setting.' }
                    @{ Id = 'DisableSafehouseWhenPlayerConnected'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DisableSafehouseWhenPlayerConnected'; Label = 'Disable Safehouse When Player Connected'; DefaultValue = $false; Hint = 'Project Zomboid DisableSafehouseWhenPlayerConnected setting.' }
                    @{ Id = 'Faction'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'Faction'; Label = 'Faction'; DefaultValue = $true; Hint = 'Project Zomboid Faction setting.' }
                    @{ Id = 'FactionDaySurvivedToCreate'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'FactionDaySurvivedToCreate'; Label = 'Faction Day Survived To Create'; DefaultValue = 0; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid FactionDaySurvivedToCreate setting.' }
                    @{ Id = 'FactionPlayersRequiredForTag'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'FactionPlayersRequiredForTag'; Label = 'Faction Players Required For Tag'; DefaultValue = 1; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid FactionPlayersRequiredForTag setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Mods / Map'
                Description = 'Project Zomboid Workshop, mod IDs, map folders, and Lua checksum settings.'
                Fields      = @(
                    @{ Id = 'WorkshopItems'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'WorkshopItems'; Label = 'Workshop Items'; DefaultValue = ''; Hint = 'Semicolon-separated Steam Workshop IDs. UGSM mod helper should update this from active instance mods.' }
                    @{ Id = 'Mods'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'Mods'; Label = 'Mod IDs'; DefaultValue = ''; Hint = 'Semicolon-separated Project Zomboid mod IDs from each Workshop mod info.txt.' }
                    @{ Id = 'Map'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'Map'; Label = 'Map Folders'; DefaultValue = 'Muldraugh, KY'; Hint = 'Semicolon-separated map folders. Keep Muldraugh, KY at the end unless intentionally changing the base map order.' }
                    @{ Id = 'DoLuaChecksum'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'DoLuaChecksum'; Label = 'Lua Checksum'; DefaultValue = $true; Hint = 'Project Zomboid DoLuaChecksum setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Logging / Filters'
                Description = 'Client command filters and gameplay/event logging.'
                Fields      = @(
                    @{ Id = 'ClientCommandFilter'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'ClientCommandFilter'; Label = 'Client Command Filter'; DefaultValue = '-vehicle.*;+vehicle.damageWindow;+vehicle.fixPart;+vehicle.installPart;+vehicle.uninstallPart'; Hint = 'Project Zomboid ClientCommandFilter setting.' }
                    @{ Id = 'ClientActionLogs'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'ClientActionLogs'; Label = 'Client Action Logs'; DefaultValue = 'ISEnterVehicle;ISExitVehicle;ISTakeEngineParts;'; Hint = 'Project Zomboid ClientActionLogs setting.' }
                    @{ Id = 'PerkLogs'; Type = 'MultilineText'; File = 'PZServer.ini'; Section = 'General'; Key = 'PerkLogs'; Label = 'Perk Logs'; DefaultValue = 'true'; Hint = 'Project Zomboid PerkLogs setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Backups'
                Description = 'Project Zomboid native backup controls.'
                Fields      = @(
                    @{ Id = 'BackupsCount'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'BackupsCount'; Label = 'Backups Count'; DefaultValue = 5; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid BackupsCount setting.' }
                    @{ Id = 'BackupsOnStart'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'BackupsOnStart'; Label = 'Backups On Start'; DefaultValue = $true; Hint = 'Project Zomboid BackupsOnStart setting.' }
                    @{ Id = 'BackupsOnVersionChange'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'BackupsOnVersionChange'; Label = 'Backups On Version Change'; DefaultValue = $true; Hint = 'Project Zomboid BackupsOnVersionChange setting.' }
                    @{ Id = 'BackupsPeriod'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'BackupsPeriod'; Label = 'Backups Period'; DefaultValue = 0; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Project Zomboid BackupsPeriod setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Anti-Cheat'
                Description = 'Project Zomboid anti-cheat protection toggles and threshold multipliers.'
                Fields      = @(
                    @{ Id = 'AntiCheatProtectionType1'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType1'; Label = 'Anti Cheat Protection Type1'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType1 setting.' }
                    @{ Id = 'AntiCheatProtectionType2'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType2'; Label = 'Anti Cheat Protection Type2'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType2 setting.' }
                    @{ Id = 'AntiCheatProtectionType3'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType3'; Label = 'Anti Cheat Protection Type3'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType3 setting.' }
                    @{ Id = 'AntiCheatProtectionType4'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType4'; Label = 'Anti Cheat Protection Type4'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType4 setting.' }
                    @{ Id = 'AntiCheatProtectionType5'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType5'; Label = 'Anti Cheat Protection Type5'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType5 setting.' }
                    @{ Id = 'AntiCheatProtectionType6'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType6'; Label = 'Anti Cheat Protection Type6'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType6 setting.' }
                    @{ Id = 'AntiCheatProtectionType7'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType7'; Label = 'Anti Cheat Protection Type7'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType7 setting.' }
                    @{ Id = 'AntiCheatProtectionType8'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType8'; Label = 'Anti Cheat Protection Type8'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType8 setting.' }
                    @{ Id = 'AntiCheatProtectionType9'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType9'; Label = 'Anti Cheat Protection Type9'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType9 setting.' }
                    @{ Id = 'AntiCheatProtectionType10'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType10'; Label = 'Anti Cheat Protection Type10'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType10 setting.' }
                    @{ Id = 'AntiCheatProtectionType11'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType11'; Label = 'Anti Cheat Protection Type11'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType11 setting.' }
                    @{ Id = 'AntiCheatProtectionType12'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType12'; Label = 'Anti Cheat Protection Type12'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType12 setting.' }
                    @{ Id = 'AntiCheatProtectionType13'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType13'; Label = 'Anti Cheat Protection Type13'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType13 setting.' }
                    @{ Id = 'AntiCheatProtectionType14'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType14'; Label = 'Anti Cheat Protection Type14'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType14 setting.' }
                    @{ Id = 'AntiCheatProtectionType15'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType15'; Label = 'Anti Cheat Protection Type15'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType15 setting.' }
                    @{ Id = 'AntiCheatProtectionType16'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType16'; Label = 'Anti Cheat Protection Type16'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType16 setting.' }
                    @{ Id = 'AntiCheatProtectionType17'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType17'; Label = 'Anti Cheat Protection Type17'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType17 setting.' }
                    @{ Id = 'AntiCheatProtectionType18'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType18'; Label = 'Anti Cheat Protection Type18'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType18 setting.' }
                    @{ Id = 'AntiCheatProtectionType19'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType19'; Label = 'Anti Cheat Protection Type19'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType19 setting.' }
                    @{ Id = 'AntiCheatProtectionType20'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType20'; Label = 'Anti Cheat Protection Type20'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType20 setting.' }
                    @{ Id = 'AntiCheatProtectionType21'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType21'; Label = 'Anti Cheat Protection Type21'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType21 setting.' }
                    @{ Id = 'AntiCheatProtectionType22'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType22'; Label = 'Anti Cheat Protection Type22'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType22 setting.' }
                    @{ Id = 'AntiCheatProtectionType23'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType23'; Label = 'Anti Cheat Protection Type23'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType23 setting.' }
                    @{ Id = 'AntiCheatProtectionType24'; Type = 'Boolean'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType24'; Label = 'Anti Cheat Protection Type24'; DefaultValue = $true; Hint = 'Project Zomboid AntiCheatProtectionType24 setting.' }
                    @{ Id = 'AntiCheatProtectionType2ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType2ThresholdMultiplier'; Label = 'Anti Cheat Protection Type2 Threshold Multiplier'; DefaultValue = 3.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType2ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType3ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType3ThresholdMultiplier'; Label = 'Anti Cheat Protection Type3 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType3ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType4ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType4ThresholdMultiplier'; Label = 'Anti Cheat Protection Type4 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType4ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType9ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType9ThresholdMultiplier'; Label = 'Anti Cheat Protection Type9 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType9ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType15ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType15ThresholdMultiplier'; Label = 'Anti Cheat Protection Type15 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType15ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType20ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType20ThresholdMultiplier'; Label = 'Anti Cheat Protection Type20 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType20ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType22ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType22ThresholdMultiplier'; Label = 'Anti Cheat Protection Type22 Threshold Multiplier'; DefaultValue = 1.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType22ThresholdMultiplier setting.' }
                    @{ Id = 'AntiCheatProtectionType24ThresholdMultiplier'; Type = 'Number'; File = 'PZServer.ini'; Section = 'General'; Key = 'AntiCheatProtectionType24ThresholdMultiplier'; Label = 'Anti Cheat Protection Type24 Threshold Multiplier'; DefaultValue = 6.0; Min = 0; Max = 2147483647; Decimals = 1; Increment = '0.1'; Hint = 'Project Zomboid AntiCheatProtectionType24ThresholdMultiplier setting.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Files / Lists'
                Description = 'Project-local user list files stored in the selected profile Config folder.'
                Fields      = @(
                    @{ Id = 'AdminUsers'; Type = 'StringList'; Path = 'AdminUsers.txt'; Label = 'Admin Users'; Hint = 'One user/SteamID/account ID per line.' }
                    @{ Id = 'WhitelistedUsers'; Type = 'StringList'; Path = 'Whitelist.txt'; Label = 'Whitelist'; Hint = 'One user/SteamID/account ID per line.' }
                    @{ Id = 'BannedUsers'; Type = 'StringList'; Path = 'Bans.txt'; Label = 'Banned Users'; Hint = 'One user/SteamID/account ID per line.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Advanced'
                Description = 'Manual access to the profile-local Project Zomboid server files.'
                Fields      = @(
                    @{ Id = 'OpenPrimaryIni'; Type = 'ActionButton'; Label = 'Project Zomboid INI'; ButtonText = 'Open PZ Server INI'; Action = $actions.OpenPrimaryIni; Hint = 'Opens the profile-local Project Zomboid server INI for manual editing.' }
)
            }

            [pscustomobject]@{
                Title       = 'Discord'
                Description = 'UGSM per-server Discord override settings. Private webhooks are stored in UGSM secrets, not in the instance JSON.'
                Fields      = @(
                    @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Secret = $true; Hint = 'Optional per-server webhook override. Hidden on screen and saved into the UGSM secrets store; instance JSON keeps safe metadata only.' }
                    @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                    @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                    @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $false; Hint = 'Marks this server as visible for Discord/dashboard status integrations.' }
                   @{
    Id         = 'DiscordTestWebhook'
    Type       = 'ActionButton'
    Label      = 'Test Discord Webhook'
    ButtonText = 'Send Test Message'
    Hint       = 'Sends a test message using the saved per-server secret webhook if set, otherwise the global webhook.'
    Action     = {
        param($Instance, $Paths, $StatusLabel)

        try {
            $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance

            if (-not $discordModel.HasWebhook) {
                if ($StatusLabel) {
                    $StatusLabel.Text = 'Discord test skipped: no webhook is configured for this server and no global webhook is available.'
                }
                return
            }

            $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('Project Zomboid ' + [string]$Instance.Name)

            if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) {
                $target = if ($discordModel.UsesGlobalWebhook) { 'global webhook' } else { 'server webhook' }

                if ($StatusLabel) {
                    $StatusLabel.Text = 'Discord test sent successfully using the ' + $target + '.'
                }
            }
            else {
                $errorText = ''

                if ($result -and $result.PSObject.Properties['Error']) {
                    $errorText = [string]$result.Error
                }

                if ([string]::IsNullOrWhiteSpace($errorText)) {
                    $errorText = 'Unknown Discord webhook error.'
                }

                if ($StatusLabel) {
                    $StatusLabel.Text = 'Discord test failed: ' + $errorText
                }
            }
        }
        catch {
            if ($StatusLabel) {
                $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message
            }
        }
    }
}
                )
            }
        )
    }

    $filteredTabs = New-Object System.Collections.Generic.List[object]
    foreach ($tab in @($schema.Tabs)) {
        $title = [string]$tab.Title
        if ($title -eq 'Discord' -and -not [bool]$features.Discord) { continue }
        if ($title -eq 'Files / Lists' -and -not [bool]$features.UserLists) { continue }
        if ($title -eq 'Advanced' -and -not [bool]$features.AdvancedFiles) { continue }
        # Project Zomboid uses the shared Steam Workshop Mods tab. Hide the old
        # INI-only Mods / Map tab when shared mod management is enabled.
        if ($title -eq 'Mods / Map' -and [bool]$features.Mods) { continue }

        if ($title -eq 'Network / Ports' -and -not [bool]$features.Rcon) {
            $keptFields = @($tab.Fields | Where-Object {
                $fieldId = [string]$_.Id
                $fieldId -notin @('RconEnabled','RconPort','RconPassword')
            })
            $tab = [pscustomobject]@{ Title = $tab.Title; Description = $tab.Description; Fields = $keptFields }
        }

        [void]$filteredTabs.Add($tab)
    }

    $resultSchema = [pscustomobject]@{
        Version = $schema.Version
        Tabs = @($filteredTabs.ToArray())
    }


    if ([bool]$features.Mods) {
        $modsDefinition = Get-UGSMGameProjectZomboidModsDefinition
        $hasModsTab = $false
        foreach ($existingTab in @($resultSchema.Tabs)) {
            if ([string]$existingTab.Title -eq 'Mods') { $hasModsTab = $true; break }
        }

        if (-not $hasModsTab) {
            $modsTab = [pscustomobject]@{
                Title       = 'Mods'
                Description = ''
                UsesSharedModsEditor = $true
                Fields      = @()
            }

            $tabsWithMods = New-Object System.Collections.Generic.List[object]
            foreach ($existingTab in @($resultSchema.Tabs)) { [void]$tabsWithMods.Add($existingTab) }
            [void]$tabsWithMods.Add($modsTab)
            $resultSchema = [pscustomobject]@{ Version = $resultSchema.Version; Tabs = @($tabsWithMods.ToArray()) }
        }
    }

    return $resultSchema
}
