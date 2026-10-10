# UGSM Game 7D2D
# Hidden golden 7D2D for future UGSM game modules.
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace 7D2D with the real game token
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

function Test-UGSMGame7D2DVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGame7D2DLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGame7D2DLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_7D2D)) { return $true }
    return $false
}

function ConvertTo-UGSMGame7D2DSafeLogText {
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
        # the 7D2D itself does not add portability-scan false positives.
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

function Write-UGSMGame7D2DLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGame7D2DVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGame7D2DSafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGame7D2DSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:7D2D' -Message $safeMessage
    }
}

function Write-UGSMGame7D2DPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older 7D2D notes. New modules should use Write-UGSMGame7D2DLog.
    Write-UGSMGame7D2DLog -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGame7D2DInstanceDiscordShape {
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

function Ensure-UGSMGame7D2D {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGame7D2DInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGame7D2DInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "7D2D install is not valid at '$InstallPath'."
    }

    return [pscustomobject]@{
        GameId               = '7D2D'
        InstallPath          = [string]$definition.InstallPath
        ServerExecutablePath = [string]$definition.ServerExecutablePath
        ConfigSourcePath     = Join-Path ([string]$definition.InstallPath) 'serverconfig.xml'
        BootstrapPerformed   = $false
    }
}

function Get-UGSMGame7D2DSupportedFeatures {
    [CmdletBinding()]
    param()

    # ============================================================
    # 7D2D SUPPORTED FEATURES
    # This is the first section to edit when copying the 7D2D.
    # Turn features on/off here, then edit the schema sections below.
    # Test builds show the 7D2D as a real game so optional UI can be previewed.
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
        # Show this game in the catalog. Release/test/dev exclusion is handled by build scripts.
        IsVisible     = $true
        Rcon          = $true
        GracefulStop  = $true

        # Set Mods=$true to preview the shared Mods tab in test builds.
        # Copied games can keep this on/off switch and only change ModTabMode/capabilities.
        Mods          = $true
        Workshop      = $false
        ModTabMode    = 'ArchiveImport' # SteamWorkshop, ArchiveImport, FrameworkPlugin, Mixed

        # Standard shared mod state storage. Game modules should keep mod references
        # in the instance JSON unless a game truly requires a different storage mode.
        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $false

        IniFiles        = $false
        JsonFiles       = $false
        XmlFiles        = $true
        CfgFiles        = $false
        PropertiesFiles = $false
        YamlFiles       = $false
        TomlFiles       = $false
        LuaFiles        = $false
        TextFiles       = $true
        PSSQLite        = $false

        ModCapabilities = [pscustomobject]@{
            # Standard Steam Workshop list/download/load-order tab.
            SteamWorkshop    = $false
            LoadOrder        = $false

            # ZIP/RAR/folder import tab pieces. Enable for games like 7 Days to Die.
            ArchiveImport    = $true
            FolderImport     = $false

            # Framework/plugin tab pieces. Enable for games like Rust Oxide/uMod.
            FrameworkInstall = $false
            PluginManager    = $false

            # Optional game-specific Steam Workshop utilities.
            KeyCopy          = $false
            ServerSideCopy   = $false
            RuntimeSync      = $false
            BuildIndexCache  = $false
            MapList          = $false
            ConfigMerge      = $false
            UrlDownload      = $false

            # Common safe utility buttons.
            OpenManifest     = $true
            RefreshSummary   = $true
        }
    }
}

function Get-UGSMGame7D2DModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGame7D2DSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId '7D2D' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
    }
    else {
        $mods = [pscustomobject]@{
            Supported = [bool]$features.Mods
            DisplayName = 'Mods'
            Version = 2
            ModStateStorage = 'InstanceJson'
            InstanceModsProperty = 'Mods'
            InstanceModStatesProperty = 'ModStates'
            ModTabMode = $(if ($features.PSObject.Properties['ModTabMode']) { [string]$features.ModTabMode } else { 'SteamWorkshop' })
            Capabilities = [pscustomobject]@{
                SteamWorkshop = $false; ArchiveImport = $false; FolderImport = $false; FrameworkInstall = $false; PluginManager = $false; MapList = $false; ConfigMerge = $false; LoadOrder = $false; UrlDownload = $false; KeyCopy = $false; ServerSideCopy = $false; RuntimeSync = $false; BuildIndexCache = $false; OpenManifest = $true; RefreshSummary = $true
            }
            Archive = [pscustomobject]@{ AllowedExtensions = @('.zip','.rar'); InstallFolderRelative = 'Mods'; RequireSafetyNotice = $true }
            Workshop = [pscustomobject]@{ IdField = 'WorkshopItemIds'; SupportsCollections = $true; ConfigStrategy = 'ManifestOnly'; AppId = '000000'; WorkshopAppId = '000000'; LoginMode = 'Anonymous' }
            Framework = [pscustomobject]@{ Id = 'ExampleFramework'; Label = 'Example Framework'; OfficialSourceOnly = $true; RequiresConfirmation = $true }
            Paths = [pscustomobject]@{ ModsFolderRelative = 'Mods'; ManifestFileName = $null }
            StoragePolicy = [pscustomobject]@{ Mode = 'InstanceJson'; KeepWorkshopModsShared = $true; CopyFullModsToProfile = $false; CopyOnlyRequiredFilesToProfile = $true; RuntimeMode = 'SharedWorkshopCache'; SummaryFileName = $null }
            UI = [pscustomobject]@{ InlineWorkshopInput = $true; ShowActiveLoadOrder = $true; ShowSafetyNotice = $true; ShowProfileLightNotice = $true }
            Safety = [pscustomobject]@{ ShowThirdPartyNotice = $true; RequireConfirmation = $true; NoticeKind = 'GenericMods' }
            Hooks = [pscustomobject]@{ Refresh = ''; Save = ''; Install = ''; Remove = ''; Validate = ''; BuildCustomTab = ''; AfterModsChanged = ''; AfterWorkshopDownload = '' }
            GameId = '7D2D'
        }
    }


    # 7D2D Workshop App ID placeholder. Copied games must replace 000000 with
    # the client Workshop App ID used by SteamCMD workshop_download_item.
    foreach ($propName in @('WorkshopAppId','SteamWorkshopAppId')) {
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = '000000' }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value '000000' -Force }
    }

    if ($mods.PSObject.Properties['Workshop'] -and $mods.Workshop) {
        foreach ($propName in @('AppId','WorkshopAppId','SteamWorkshopAppId')) {
            if ($mods.Workshop.PSObject.Properties[$propName]) { $mods.Workshop.$propName = '000000' }
            else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name $propName -Value '000000' -Force }
        }
        if ($mods.Workshop.PSObject.Properties['ConfigStrategy']) { $mods.Workshop.ConfigStrategy = 'ManifestOnly' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'ConfigStrategy' -Value 'ManifestOnly' -Force }
        if ($mods.Workshop.PSObject.Properties['LoginMode']) { $mods.Workshop.LoginMode = 'Anonymous' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'LoginMode' -Value 'Anonymous' -Force }
    }

    foreach ($propName in @('ModStateStorage','InstanceModsProperty','InstanceModStatesProperty')) {
        $value = switch ($propName) {
            'ModStateStorage' { 'InstanceJson' }
            'InstanceModsProperty' { 'Mods' }
            'InstanceModStatesProperty' { 'ModStates' }
        }
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = $value }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value $value -Force }
    }

    foreach ($name in @('SteamWorkshop','ArchiveImport','FolderImport','FrameworkInstall','PluginManager','MapList','ConfigMerge','LoadOrder','UrlDownload','KeyCopy','ServerSideCopy','RuntimeSync','BuildIndexCache','OpenManifest','RefreshSummary')) {
        if ($mods.Capabilities.PSObject.Properties[$name] -and $features.ModCapabilities.PSObject.Properties[$name]) {
            $mods.Capabilities.$name = [bool]$features.ModCapabilities.$name
        }
    }

    if ($features.PSObject.Properties['ModTabMode']) {
        if ($mods.PSObject.Properties['ModTabMode']) { $mods.ModTabMode = [string]$features.ModTabMode }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name ModTabMode -Value ([string]$features.ModTabMode) -Force }
    }


    # 7D2D uses third-party ZIP/RAR archive mods installed into the shared Steam install Mods folder.
    if ($mods.PSObject.Properties['ModTabMode']) { $mods.ModTabMode = 'ArchiveImport' } else { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'ModTabMode' -Value 'ArchiveImport' -Force }
    foreach ($pair in @(
        @{ Name = 'SteamWorkshop'; Value = $false },
        @{ Name = 'LoadOrder'; Value = $false },
        @{ Name = 'ArchiveImport'; Value = $true },
        @{ Name = 'FolderImport'; Value = $false },
        @{ Name = 'OpenManifest'; Value = $true },
        @{ Name = 'RefreshSummary'; Value = $true }
    )) {
        if ($mods.Capabilities.PSObject.Properties[$pair.Name]) { $mods.Capabilities.($pair.Name) = [bool]$pair.Value }
        else { Add-Member -InputObject $mods.Capabilities -MemberType NoteProperty -Name $pair.Name -Value ([bool]$pair.Value) -Force }
    }
    if (-not $mods.PSObject.Properties['Archive'] -or $null -eq $mods.Archive) { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Archive' -Value ([pscustomobject]@{}) -Force }
    foreach ($pair in @(
        @{ Name = 'AllowedExtensions'; Value = @('.zip','.rar') },
        @{ Name = 'InstallFolderRelative'; Value = 'Mods' },
        @{ Name = 'RequireSafetyNotice'; Value = $true }
    )) {
        if ($mods.Archive.PSObject.Properties[$pair.Name]) { $mods.Archive.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $mods.Archive -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }
    if (-not $mods.PSObject.Properties['Hooks'] -or $null -eq $mods.Hooks) { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Hooks' -Value ([pscustomobject]@{}) -Force }
    foreach ($hookName in @('Refresh','Save','Install','Remove','Validate','BuildCustomTab','AfterModsChanged','AfterWorkshopDownload','ImportArchive','RemoveArchive','SyncArchive')) {
        if (-not $mods.Hooks.PSObject.Properties[$hookName]) { Add-Member -InputObject $mods.Hooks -MemberType NoteProperty -Name $hookName -Value '' -Force }
    }
    $mods.Hooks.Install = 'Import-UGSMGame7D2DArchiveMod'
    $mods.Hooks.Remove  = 'Remove-UGSMGame7D2DArchiveMod'
    $mods.Hooks.Refresh = 'Sync-UGSMGame7D2DArchiveMods'
    $mods.Hooks.AfterModsChanged = 'Sync-UGSMGame7D2DArchiveMods'
    $mods.Hooks.ImportArchive = 'Import-UGSMGame7D2DArchiveMod'
    $mods.Hooks.RemoveArchive = 'Remove-UGSMGame7D2DArchiveMod'
    $mods.Hooks.SyncArchive = 'Sync-UGSMGame7D2DArchiveMods'

    if ($mods.PSObject.Properties['StoragePolicy'] -and $mods.StoragePolicy) {
        $mods.StoragePolicy.KeepWorkshopModsShared = $true
        $mods.StoragePolicy.CopyFullModsToProfile = $false
        $mods.StoragePolicy.CopyOnlyRequiredFilesToProfile = $true
        $mods.StoragePolicy.RuntimeMode = 'SharedArchiveMods'
    }

    if ($mods.PSObject.Properties['UI'] -and $mods.UI) {
        $mods.UI.InlineWorkshopInput = $false
        $mods.UI.ShowActiveLoadOrder = $true
        $mods.UI.ShowSafetyNotice = $true
        $mods.UI.ShowProfileLightNotice = $true
    }

    if ($mods.PSObject.Properties['Safety'] -and $mods.Safety) {
        $mods.Safety.ShowThirdPartyNotice = [bool]$features.Mods
        $mods.Safety.RequireConfirmation = $true
        if ($mods.Safety.PSObject.Properties['NoticeKind']) { $mods.Safety.NoticeKind = 'ArchiveMods' } else { Add-Member -InputObject $mods.Safety -MemberType NoteProperty -Name 'NoticeKind' -Value 'ArchiveMods' -Force }
    }

    return $mods
}

function Get-UGSMGame7D2DMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = '7DaysToDieServer.exe'
    $features = Get-UGSMGame7D2DSupportedFeatures
    $modsDefinition = Get-UGSMGame7D2DModsDefinition

    return [pscustomobject]@{
        Id                       = '7D2D'
        Name                     = '7 Days to Die'
        Category                 = 'Survival'
        Description              = 'Hidden runtime-only reference module for future UGSM game integrations.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 9999
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
        SteamAppId               = '294420'
        SteamStoreAppId          = '251570'
        ServerExecutable         = '7DaysToDieServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'Config'
        SaveRootRelative         = 'SaveData'
        LogRootRelative          = 'Logs'

        RequiredFiles            = @('7DaysToDieServer.exe')
        InstallMarkers           = @('7DaysToDieServer.exe')

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 26900 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 26901 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 8080 }
        )

        GameTraits = [pscustomobject]@{
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
                '7D2D module is shown only in test builds and excluded from release builds.',
                'Replace metadata, install validation, runtime layout, launch arguments, and schema values when creating a real game module.',
                'SteamCMD is the default install/update/verify pattern in the 7D2D.',
                'Steam login defaults to anonymous. Only add username/password handling when the target game truly requires it.',
                'Mods are driven by Get-UGSMGame7D2DModsDefinition and shared helper functions.',
                'Do not add profile sync or copy-back behavior to new game modules.'
            )
        }
    }
}

function Get-UGSMGame7D2DInstallDefinition {
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

    $meta = Get-UGSMGame7D2DMetadata
    $candidateRoots = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
        [void]$candidateRoots.Add([string]$InstallPath)
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($propName in @('SteamRoot', 'SteamCmdRoot', 'InstallRoot', 'SteamLibraryRoot')) {
        if ($settings -and $settings.PSObject.Properties.Name -contains $propName) {
            $value = [string]$settings.$propName
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $steamRoots.Contains($value)) {
                [void]$steamRoots.Add($value)
            }
        }
    }

    foreach ($root in @($steamRoots)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($candidate in @(
            (Join-Path $root 'steamapps\common\7D2D'),
            (Join-Path $root 'steamapps\common\7 Days to Die Dedicated Server'),
            (Join-Path $root 'servers\7D2D'),
            (Join-Path $root '7D2D')
        )) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidateRoots.Contains($candidate)) {
                [void]$candidateRoots.Add($candidate)
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        foreach ($candidate in @($candidateRoots)) {
            if ((Test-Path -LiteralPath $candidate -PathType Container) -and (Test-Path -LiteralPath (Join-Path $candidate '7DaysToDieServer.exe') -PathType Leaf)) {
                $InstallPath = [string]$candidate
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath) -and $candidateRoots.Count -gt 0) {
        $InstallPath = [string]$candidateRoots[0]
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw '7D2D install definition failed: InstallPath could not be resolved.'
    }

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = Join-Path $InstallPath '7DaysToDieServer.exe'
        RequiredFiles        = @('7DaysToDieServer.exe')
        InstallMarkers       = @('7DaysToDieServer.exe')
        ConfigRootPath       = $InstallPath
        SaveRootPath         = $InstallPath
        LogRootPath          = $InstallPath
    }
}

function Get-UGSMGame7D2DAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGame7D2DProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId '7D2D' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGame7D2DAppDataRoot) 'Profiles')
}

function Get-UGSMGame7D2D7D2DRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGame7D2DAppDataRoot) '7D2Ds\7D2D')
}

function Get-UGSMGame7D2DProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGame7D2DProfileBaseRoot) '7D2D') $ProfileName)
}


function Get-UGSMGame7D2DRuntimeRoot {
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
            $profileRoot = Get-UGSMGame7D2DProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw '7D2D runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGame7D2DPath {
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

function New-UGSMGame7D2DDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "7D2D junction target was not found: $TargetPath"
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

        Remove-UGSMGame7D2DPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "7D2D junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGame7D2DFilesToRuntime {
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

    Copy-UGSMGame7D2DDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGame7D2DRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGame7D2DRuntimeRoot -Instance $Instance
    $runtimeInstallRoot = Join-Path $runtimeRoot 'Install'
    $runtimeGameRoot = Join-Path $runtimeInstallRoot '7D2D'
    $runtimeSavedRoot = Join-Path $runtimeGameRoot 'Saved'

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeGameRoot       = $runtimeGameRoot
        RuntimeSavedRoot      = $runtimeSavedRoot
        RuntimeConfigRootPath = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
        RuntimeSaveRootPath   = Join-Path $runtimeSavedRoot 'SaveFiles'
        RuntimeLogRootPath    = Join-Path $runtimeSavedRoot 'Logs'
        RuntimeServerExePath  = Join-Path $runtimeInstallRoot '7DaysToDieServer.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = Join-Path ([string]$InstallDefinition.InstallPath) '7D2D'

    }
}

function Resolve-UGSMGame7D2DDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance

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

function Ensure-UGSMGame7D2DRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGame7D2DRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition
    $sharedInstallRoot = [string]$InstallDefinition.InstallPath
    $sharedGameRoot = Join-Path $sharedInstallRoot '7D2D'

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeInstallRoot, $runtime.RuntimeGameRoot, $runtime.RuntimeSavedRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $sharedInstallRoot -PathType Container) {
        foreach ($child in @(Get-ChildItem -LiteralPath $sharedInstallRoot -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtime.RuntimeInstallRoot $child.Name

            if ($child.PSIsContainer -and $child.Name -ieq '7D2D') {
                continue
            }

            if ($child.PSIsContainer) {
                New-UGSMGame7D2DDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
            }
            else {
                Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $sharedGameRoot -PathType Container)) {
        throw "7D2D runtime layout failed: Shared 7D2D root was not found: $sharedGameRoot"
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $sharedGameRoot -Force -ErrorAction SilentlyContinue)) {
        $targetPath = Join-Path $runtime.RuntimeGameRoot $child.Name

        if ($child.PSIsContainer -and $child.Name -ieq 'Saved') {
            continue
        }

        if ($child.PSIsContainer) {
            New-UGSMGame7D2DDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $runtime
}

function Initialize-UGSMGame7D2DRuntimeData {
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
        Copy-UGSMGame7D2DFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGame7D2DFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGame7D2DDirectoryContent {
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

function Get-UGSMGame7D2DRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = '7DaysToDieServer.exe'" -ErrorAction Stop)
    }
    catch {
        $matches = @()
    }

    $normalizedExe = [System.IO.Path]::GetFullPath($ServerExecutablePath)
    $results = @()
    foreach ($proc in $matches) {
        $exePath = [string]$proc.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($exePath)) {
            continue
        }

        try {
            $exePath = [System.IO.Path]::GetFullPath($exePath)
        }
        catch {
            continue
        }

        if (-not $exePath.Equals($normalizedExe, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

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

        $results += [pscustomobject]@{
            Pid         = [int]$proc.ProcessId
            Executable  = $exePath
            StartedAt   = $created
            CommandLine = [string]$proc.CommandLine
        }
    }

    return @($results | Sort-Object Pid -Unique)
}

function Start-UGSMGame7D2DBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "7D2D server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name '7DaysToDieServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM 7DaysToDieServer.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name '7DaysToDieServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name '7DaysToDieServer' -ErrorAction SilentlyContinue)

    if ($remainingFinal.Count -gt 0) {
    }
    else {
    }

    return [pscustomobject]@{
        PreferredPid  = [int]$proc.Id
        StartedAt     = $launchStartedAt
        BootstrapTime = $bootstrapTime
        StopResults   = $stopResults
        Exited        = ($remainingFinal.Count -eq 0)
        RemainingPids = @($remainingFinal.Id)
    }
}

function Ensure-UGSMGame7D2D {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGame7D2DInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGame7D2DInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "7D2D install is not valid at '$InstallPath'."
    }

    $sevenD2DRoot = Get-UGSMGame7D2D7D2DRoot
    $sevenD2DConfigRoot = Join-Path $sevenD2DRoot 'Config\WindowsServer'
    $sevenD2DSaveRoot = Join-Path $sevenD2DRoot 'SaveFiles'

    New-Item -ItemType Directory -Path $sevenD2DRoot -Force | Out-Null

    $has7D2DConfig = (Test-Path -LiteralPath $sevenD2DConfigRoot -PathType Container) -and @(
        Get-ChildItem -LiteralPath $sevenD2DConfigRoot -File -Force -ErrorAction SilentlyContinue
    ).Count -gt 0

    $sourceConfigRoot = [string]$definition.ConfigRootPath
    $sourceSaveRoot = [string]$definition.SaveRootPath

    $needsBootstrap = $ForceRefresh.IsPresent -or -not $has7D2DConfig
    if (-not $needsBootstrap) {
        $needsBootstrap = -not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)
    }

    $bootstrapResult = $null
    if ($needsBootstrap) {
        $bootstrapResult = Start-UGSMGame7D2DBootstrapProcess -ServerExecutablePath $definition.ServerExecutablePath -WorkingDirectory $InstallPath -BootstrapSeconds $BootstrapSeconds
        if (-not $bootstrapResult.Exited) {
            throw ('7D2D bootstrap server did not shut down cleanly. Remaining PIDs: {0}' -f (($bootstrapResult.RemainingPids -join ', ')))
        }
    }

    if (-not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)) {
        throw "7D2D bootstrap did not generate a config folder: $sourceConfigRoot"
    }

    $generatedConfigFiles = @(Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue)
    if ($generatedConfigFiles.Count -eq 0) {
        throw "7D2D bootstrap completed, but no generated config files were found in: $sourceConfigRoot"
    }

    Copy-UGSMGame7D2DDirectoryContent -Source $sourceConfigRoot -Destination $sevenD2DConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')

    New-Item -ItemType Directory -Path $sevenD2DSaveRoot -Force | Out-Null

    return [pscustomobject]@{
        GameId                       = '7D2D'
        InstallPath          = $InstallPath
        '7D2DRoot' = $sevenD2DRoot
        '7D2DConfigRoot' = $sevenD2DConfigRoot
        '7D2DSaveRoot' = $sevenD2DSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $needsBootstrap
        BootstrapResult      = $bootstrapResult
        GeneratedConfigFiles = @($generatedConfigFiles.Name)
    }
}


function Set-UGSMGame7D2DServerConfigProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
        $node = $xml.SelectSingleNode("//property[@name='$Name']")
        if ($null -eq $node) { return }
        $node.SetAttribute('value', [string]$Value)
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
        $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
        try { $xml.Save($writer) } finally { $writer.Close() }
    }
    catch { }
}


function Get-UGSMGame7D2DServerConfigProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$DefaultValue = $null
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $DefaultValue }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
        $node = $xml.SelectSingleNode("//property[@name='$Name']")
        if ($null -eq $node) { return $DefaultValue }
        $value = $node.GetAttribute('value')
        if ($null -eq $value) { return $DefaultValue }
        return $value
    }
    catch {
        return $DefaultValue
    }
}

function Test-UGSMGame7D2DProcessRunning {
    [CmdletBinding()]
    param([AllowNull()][object]$ProcessId)

    if (-not $ProcessId) { return $false }

    try {
        $proc = Get-Process -Id ([int]$ProcessId) -ErrorAction Stop
        return ($null -ne $proc -and -not $proc.HasExited)
    }
    catch {
        return $false
    }
}

function Invoke-UGSMGame7D2DTelnetCommand {
    [CmdletBinding()]
    param(
        [int]$Port = 8081,
        [AllowNull()][string]$Password,
        [Parameter(Mandatory)][string[]]$Commands,
        [int]$ConnectTimeoutMs = 5000,
        [int]$CommandDelayMs = 350,
        [int]$PostCommandHoldMs = 0
    )

    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            try { $client.Close() } catch {}
            return [pscustomobject]@{ Success = $false; Port = $Port; Error = 'Timed out connecting to 7D2D Telnet.' }
        }
        $client.EndConnect($async)

        $stream = $client.GetStream()
        $stream.ReadTimeout = 1000
        $stream.WriteTimeout = 5000
        $encoding = [System.Text.Encoding]::ASCII

        function Send-UGSM7D2DTelnetLine {
            param([string]$Line)
            $bytes = $encoding.GetBytes(($Line + "`r`n"))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            Start-Sleep -Milliseconds $CommandDelayMs
        }

        if (-not [string]::IsNullOrWhiteSpace($Password)) {
            Send-UGSM7D2DTelnetLine -Line $Password
        }

        foreach ($command in @($Commands)) {
            if ([string]::IsNullOrWhiteSpace($command)) { continue }
            Send-UGSM7D2DTelnetLine -Line $command
        }

        # For shutdown, keep the Telnet socket open briefly so 7D2D can
        # acknowledge the command and close the session during its own
        # shutdown path. Closing immediately can make the server log a noisy
        # "connection forcibly closed" IOException even though shutdown worked.
        if ($PostCommandHoldMs -gt 0) {
            Start-Sleep -Milliseconds $PostCommandHoldMs
        }

        return [pscustomobject]@{ Success = $true; Port = $Port; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Port = $Port; Error = $_.Exception.Message }
    }
    finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}



function Get-UGSMGame7D2DObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string[]]$Names,
        [AllowNull()][object]$DefaultValue = $null
    )

    if (-not $Object) { return $DefaultValue }

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        if ($Object -is [hashtable] -and $Object.ContainsKey($name)) { return $Object[$name] }
        if ($Object.PSObject -and $Object.PSObject.Properties[$name]) { return $Object.PSObject.Properties[$name].Value }
    }

    return $DefaultValue
}

function Set-UGSMGame7D2DObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if (-not $Object -or [string]::IsNullOrWhiteSpace($Name)) { return }

    if ($Object -is [hashtable]) {
        $Object[$Name] = $Value
        return
    }

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    }
    else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Update-UGSMGame7D2DInstanceNormalizedDiscordInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$Persist
    )

    if (-not $Instance) { return $Instance }

    $paths = $null
    try { $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance } catch { $paths = $null }

    $configPath = $null
    if ($paths -and $paths.PSObject.Properties['ServerConfigPath']) { $configPath = [string]$paths.ServerConfigPath }
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        $profilePath = Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('ProfilePath') -DefaultValue ''
        if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) { $configPath = Join-Path ([string]$profilePath) 'serverconfig.xml' }
    }

    $serverName = $null
    $maxPlayers = $null
    if (-not [string]::IsNullOrWhiteSpace($configPath) -and (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        $serverName = Get-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'ServerName' -DefaultValue $null
        $maxPlayers = Get-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'ServerMaxPlayerCount' -DefaultValue $null
    }

    if ($null -eq $serverName -or [string]::IsNullOrWhiteSpace([string]$serverName)) {
        $serverName = Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('ServerName','PublicServerName','DisplayName','Name') -DefaultValue ''
    }
    if ($null -eq $maxPlayers -or [string]::IsNullOrWhiteSpace([string]$maxPlayers)) {
        $maxPlayers = Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('MaxPlayers','ServerMaxPlayers') -DefaultValue $null
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$serverName)) {
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'ServerName' -Value ([string]$serverName)
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PublicServerName' -Value ([string]$serverName)
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'DisplayName' -Value ([string]$serverName)
    }

    if ($null -ne $maxPlayers -and -not [string]::IsNullOrWhiteSpace([string]$maxPlayers)) {
        $maxInt = 0
        if ([int]::TryParse(([string]$maxPlayers), [ref]$maxInt)) {
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'MaxPlayers' -Value $maxInt
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'ServerMaxPlayers' -Value $maxInt
        }
        else {
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'MaxPlayers' -Value ([string]$maxPlayers)
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'ServerMaxPlayers' -Value ([string]$maxPlayers)
        }
    }

    if ($Persist) { Save-UGSMGame7D2DInstanceDefinition -Instance $Instance | Out-Null }
    return $Instance
}

function Get-UGSMGame7D2DCurrentPlayerCountFromTelnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$TimeoutMs = 3500
    )

    $paths = $null
    try { $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance } catch { $paths = $null }

    $configPath = $null
    if ($paths -and $paths.PSObject.Properties['ServerConfigPath']) { $configPath = [string]$paths.ServerConfigPath }
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        $profilePath = Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('ProfilePath') -DefaultValue ''
        if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) { $configPath = Join-Path ([string]$profilePath) 'serverconfig.xml' }
    }

    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_TELNET_LP'; Status = 'ConfigMissing'; Error = 'serverconfig.xml was not found.'; Raw = '' }
    }

    $telnetEnabled = [string](Get-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'TelnetEnabled' -DefaultValue 'true')
    if ($telnetEnabled.Trim().ToLowerInvariant() -in @('false','0','no','off')) {
        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_TELNET_LP'; Status = 'TelnetDisabled'; Error = 'Telnet is disabled.'; Raw = '' }
    }

    $portText = [string](Get-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'TelnetPort' -DefaultValue '8081')
    $port = 8081
    if (-not [int]::TryParse($portText, [ref]$port)) { $port = 8081 }
    $password = [string](Get-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'TelnetPassword' -DefaultValue '')

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            try { $client.Close() } catch {}
            return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_TELNET_LP'; Status = 'NoResponse'; Error = 'Timed out connecting to local Telnet.'; Raw = '' }
        }
        $client.EndConnect($async)

        $stream = $client.GetStream()
        $stream.ReadTimeout = 250
        $stream.WriteTimeout = 1000
        $encoding = [System.Text.Encoding]::ASCII

        function Send-UGSM7D2DPlayerCountTelnetLine {
            param([string]$Line)
            $bytes = $encoding.GetBytes(($Line + "`r`n"))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            Start-Sleep -Milliseconds 200
        }

        if (-not [string]::IsNullOrWhiteSpace($password)) {
            Send-UGSM7D2DPlayerCountTelnetLine -Line $password
        }
        Send-UGSM7D2DPlayerCountTelnetLine -Line 'lp'

        $buffer = New-Object byte[] 4096
        $builder = New-Object System.Text.StringBuilder
        $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)

        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                while ($stream.DataAvailable) {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -gt 0) { [void]$builder.Append($encoding.GetString($buffer, 0, $read)) }
                }
            }
            catch { }

            $rawNow = $builder.ToString()
            if ($rawNow -match '(?im)Total\s+of\s+(\d+)\s+(?:players?\s+)?in\s+the\s+game') { break }
            if ($rawNow -match '(?im)Players\s*:\s*(\d+)') { break }
            Start-Sleep -Milliseconds 150
        }

        $raw = $builder.ToString()
        $count = $null
        if ($raw -match '(?im)Total\s+of\s+(\d+)\s+(?:players?\s+)?in\s+the\s+game') {
            $count = [int]$matches[1]
        }
        elseif ($raw -match '(?im)Players\s*:\s*(\d+)') {
            $count = [int]$matches[1]
        }

        if ($null -ne $count) {
            return [pscustomobject]@{ Success = $true; CurrentPlayers = $count; Source = '7D2D_TELNET_LP'; Status = 'OK'; Error = $null; Raw = $raw }
        }

        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_TELNET_LP'; Status = 'ParseFailed'; Error = 'Telnet lp response did not contain a player total.'; Raw = $raw }
    }
    catch {
        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_TELNET_LP'; Status = 'Error'; Error = $_.Exception.Message; Raw = '' }
    }
    finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}


function Get-UGSMGame7D2DCurrentPlayerCountFromLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$TailLines = 800
    )

    $profilePath = Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('ProfilePath') -DefaultValue ''
    if ([string]::IsNullOrWhiteSpace([string]$profilePath)) {
        try {
            $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance
            if ($paths -and $paths.PSObject.Properties['ProfileRoot']) { $profilePath = [string]$paths.ProfileRoot }
        }
        catch { $profilePath = '' }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profilePath)) {
        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_LOG_TIME_PLY'; Status = 'ProfileMissing'; Error = 'ProfilePath was not available.'; Raw = '' }
    }

    $candidateLogs = @()
    $primaryLog = Join-Path ([string]$profilePath) 'output_log_dedi.txt'
    if (Test-Path -LiteralPath $primaryLog -PathType Leaf) { $candidateLogs += $primaryLog }

    try {
        $otherLogs = @(Get-ChildItem -LiteralPath ([string]$profilePath) -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(log|txt)$' -and $_.FullName -ne $primaryLog } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -ExpandProperty FullName -First 3)
        foreach ($logPath in $otherLogs) {
            if ($candidateLogs -notcontains $logPath) { $candidateLogs += $logPath }
        }
    }
    catch { }

    if (@($candidateLogs).Count -eq 0) {
        return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_LOG_TIME_PLY'; Status = 'LogMissing'; Error = 'No 7D2D runtime log was found.'; Raw = '' }
    }

    foreach ($logPath in @($candidateLogs)) {
        try {
            $lines = @(Get-Content -LiteralPath $logPath -Tail $TailLines -ErrorAction Stop)
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = [string]$lines[$i]
                if ($line -match '(?i)\bTime:\s+.*\bPly:\s*(\d+)\b') {
                    return [pscustomobject]@{
                        Success        = $true
                        CurrentPlayers = [int]$matches[1]
                        Source         = '7D2D_LOG_TIME_PLY'
                        Status         = 'OK'
                        Error          = $null
                        Raw            = $line
                        LogPath        = $logPath
                    }
                }
            }
        }
        catch {
            return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_LOG_TIME_PLY'; Status = 'Error'; Error = $_.Exception.Message; Raw = ''; LogPath = $logPath }
        }
    }

    return [pscustomobject]@{ Success = $false; CurrentPlayers = $null; Source = '7D2D_LOG_TIME_PLY'; Status = 'ParseFailed'; Error = 'No Time/Ply line was found in the recent runtime log.'; Raw = '' }
}


function Update-UGSMGame7D2DDiscordRuntimeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $Instance = Update-UGSMGame7D2DInstanceNormalizedDiscordInfo -Instance $Instance

    $statusText = [string](Get-UGSMGame7D2DObjectPropertyValue -Object $Instance -Names @('Status','State') -DefaultValue '')
    if ($statusText.Trim().ToLowerInvariant() -notin @('running','online','started')) {
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'CurrentPlayers' -Value 0
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCount' -Value 0
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'OnlinePlayers' -Value 0
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayersOnline' -Value 0
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountSource' -Value '7D2D_LOG_TIME_PLY'
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountStatus' -Value 'Stopped'
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Save-UGSMGame7D2DInstanceDefinition -Instance $Instance | Out-Null
        return $Instance
    }

    # 7D2D writes a lightweight status line about every 30 seconds:
    #   Time: ... Ply: 1 ...
    # Use that first because it is local, fast, and does not require Telnet secrets.
    $result = Get-UGSMGame7D2DCurrentPlayerCountFromLog -Instance $Instance

    # Keep Telnet as a fallback only. It is useful on servers where the log has
    # not emitted a recent Time/Ply line yet, but it requires Telnet to be enabled.
    if (-not ($result -and $result.Success)) {
        $telnetResult = Get-UGSMGame7D2DCurrentPlayerCountFromTelnet -Instance $Instance
        if ($telnetResult -and $telnetResult.Success) { $result = $telnetResult }
        elseif ($telnetResult) {
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountFallbackStatus' -Value ([string]$telnetResult.Status)
            Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountFallbackError' -Value ([string]$telnetResult.Error)
        }
    }

    if ($result -and $result.Success) {
        $count = [int]$result.CurrentPlayers
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'CurrentPlayers' -Value $count
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCount' -Value $count
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'OnlinePlayers' -Value $count
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayersOnline' -Value $count
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountSource' -Value ([string]$result.Source)
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountStatus' -Value 'OK'
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountLastError' -Value ''
    }
    else {
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountSource' -Value '7D2D_LOG_TIME_PLY'
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountStatus' -Value ([string]$result.Status)
        Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountLastError' -Value ([string]$result.Error)
    }

    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Save-UGSMGame7D2DInstanceDefinition -Instance $Instance | Out-Null
    return $Instance
}

function Stop-UGSMGame7D2DViaTelnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [AllowNull()][object]$ProcessId,
        [int]$TimeoutSeconds = 45
    )

    $telnetEnabled = [string](Get-UGSMGame7D2DServerConfigProperty -Path $ConfigPath -Name 'TelnetEnabled' -DefaultValue 'true')
    if ($telnetEnabled -notmatch '^(?i:true|1|yes)$') {
        return [pscustomobject]@{ Success = $false; Stopped = $false; Method = 'Telnet'; Error = 'Telnet is disabled in serverconfig.xml.' }
    }

    $portText = [string](Get-UGSMGame7D2DServerConfigProperty -Path $ConfigPath -Name 'TelnetPort' -DefaultValue '8081')
    $port = 8081
    [void][int]::TryParse($portText, [ref]$port)
    if ($port -le 0 -or $port -gt 65535) { $port = 8081 }

    $password = [string](Get-UGSMGame7D2DServerConfigProperty -Path $ConfigPath -Name 'TelnetPassword' -DefaultValue '')

    # 7D2D accepts the same shutdown command through Telnet as the visible
    # server console. Keep this minimal so graceful stop matches the manual
    # console behavior exactly.
    $commands = @(
        'shutdown'
    )

    $sendResult = Invoke-UGSMGame7D2DTelnetCommand -Port $port -Password $password -Commands $commands -PostCommandHoldMs 5000
    if (-not $sendResult.Success) {
        return [pscustomobject]@{ Success = $false; Stopped = $false; Method = 'Telnet'; Error = $sendResult.Error }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-UGSMGame7D2DProcessRunning -ProcessId $ProcessId)) {
            return [pscustomobject]@{ Success = $true; Stopped = $true; Method = 'Telnet'; Error = $null }
        }
        Start-Sleep -Seconds 1
    }

    return [pscustomobject]@{ Success = $true; Stopped = $false; Method = 'Telnet'; Error = 'Timed out waiting for 7D2D to exit after Telnet shutdown.' }
}

function New-UGSMGame7D2DProfileStartBat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$InstallPath,
        [Parameter(Mandatory)][string]$ProfilePath
    )

    $configPath = Join-Path $ProfilePath 'serverconfig.xml'
    $logPath = Join-Path $ProfilePath 'output_log_dedi.txt'
    $exePath = Join-Path $InstallPath '7DaysToDieServer.exe'

    # Keep this BAT only as a profile-local/manual launcher. UGSM starts the EXE
    # directly so the wrapper cmd window does not remain open as a blank console.
    $content = @(
        '@echo off',
        'setlocal',
        ('cd /d "{0}"' -f $InstallPath),
        'set SteamAppId=251570',
        'set SteamGameId=251570',
        ('start "" /D "{0}" "{1}" -logfile "{2}" -quit -batchmode -nographics -UserDataFolder="{3}" -configfile="{4}" -dedicated' -f $InstallPath, $exePath, $logPath, $ProfilePath, $configPath),
        'exit /b 0'
    )

    Set-Content -LiteralPath $Path -Value ($content -join [Environment]::NewLine) -Encoding ASCII
}

function Initialize-UGSMGame7D2DProfile {
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
        if (-not $Instance) { throw 'Instance is required.' }
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
        throw 'ProfileName could not be resolved for 7D2D profile initialization.'
    }

    $installDef = Get-UGSMGame7D2DInstallDefinition -InstallPath $effectiveInstallPath
    $effectiveInstallPath = [string]$installDef.InstallPath
    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a 7D2D profile.'
    }

    $sourceConfig = Join-Path $effectiveInstallPath 'serverconfig.xml'
    if (-not (Test-Path -LiteralPath $sourceConfig -PathType Leaf)) {
        throw "7D2D source serverconfig.xml was not found: $sourceConfig"
    }

    $profileRoot = Get-UGSMGame7D2DProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

    $profileConfig = Join-Path $profileRoot 'serverconfig.xml'
    $profileBat = Join-Path $profileRoot 'startdedicated.bat'

    if ($Force -or -not (Test-Path -LiteralPath $profileConfig -PathType Leaf)) {
        Copy-Item -LiteralPath $sourceConfig -Destination $profileConfig -Force
    }

    Set-UGSMGame7D2DServerConfigProperty -Path $profileConfig -Name 'ServerName' -Value $effectiveProfileName
    Set-UGSMGame7D2DServerConfigProperty -Path $profileConfig -Name 'GameName' -Value $effectiveProfileName
    Set-UGSMGame7D2DServerConfigProperty -Path $profileConfig -Name 'UserDataFolder' -Value $profileRoot
    Set-UGSMGame7D2DServerConfigProperty -Path $profileConfig -Name 'TerminalWindowEnabled' -Value 'true'

    New-UGSMGame7D2DProfileStartBat -Path $profileBat -InstallPath $effectiveInstallPath -ProfilePath $profileRoot

    return [pscustomobject]@{
        GameId          = '7D2D'
        InstanceId      = $instanceId
        ProfileName     = $effectiveProfileName
        InstallPath     = $effectiveInstallPath
        ProfileRoot     = $profileRoot
        ConfigPath      = $profileConfig
        StartScriptPath = $profileBat
        Initialized     = $true
        CreatedFiles    = @('serverconfig.xml', 'startdedicated.bat')
    }
}

function Test-UGSMGame7D2DInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGame7D2DInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw '7D2D validation failed: InstallPath could not be resolved.'
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
        GameId                       = '7D2D'
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

function Start-UGSMGame7D2DInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) { throw '7D2D start failed: Instance was null.' }

    $validation = Test-UGSMGame7D2DInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw '7D2D start failed: 7D2D is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGame7D2DInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGame7D2DProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "7D2D start failed: Profile path was not found: $profilePath"
    }

    $configPath = Join-Path $profilePath 'serverconfig.xml'
    $startScript = Join-Path $profilePath 'startdedicated.bat'

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "7D2D start failed: serverconfig.xml was not found: $configPath"
    }

    # Keep the real 7D2D terminal window enabled so users can see server output
    # and type server console commands. UGSM still tracks the real EXE PID.
    Set-UGSMGame7D2DServerConfigProperty -Path $configPath -Name 'TerminalWindowEnabled' -Value 'true'

    New-UGSMGame7D2DProfileStartBat -Path $startScript -InstallPath ([string]$installDef.InstallPath) -ProfilePath $profilePath

    $exePath = Join-Path ([string]$installDef.InstallPath) '7DaysToDieServer.exe'
    $logPath = Join-Path $profilePath 'output_log_dedi.txt'

    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "7D2D start failed: server executable was not found: $exePath"
    }

    # 7D2D V2 expects -configfile and -UserDataFolder in the equals form.
    # Passing them as separate Start-Process array entries makes the game ignore
    # the config path and fall back to AppData, which crashes before GamePrefs loads.
    $argumentString = @(
        ('-logfile "{0}"' -f $logPath),
        '-quit',
        '-batchmode',
        '-nographics',
        ('-UserDataFolder="{0}"' -f $profilePath),
        ('-configfile="{0}"' -f $configPath),
        '-dedicated'
    ) -join ' '

    $proc = Start-Process `
        -FilePath $exePath `
        -ArgumentList $argumentString `
        -WorkingDirectory ([string]$installDef.InstallPath) `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw '7D2D start failed: Start-Process did not return a valid process.'
    }

    $gamePid = [int]$proc.Id

    if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $gamePid }
    if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Running' }
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { $Instance.ProfilePath = $profilePath }

    $Instance = Update-UGSMGame7D2DInstanceNormalizedDiscordInfo -Instance $Instance
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'CurrentPlayers' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCount' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'OnlinePlayers' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayersOnline' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountSource' -Value '7D2D_LOG_TIME_PLY'
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountStatus' -Value 'Pending'
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Save-UGSMGame7D2DInstanceDefinition -Instance $Instance | Out-Null


    return [pscustomobject]@{
        Instance        = $Instance
        Pid             = $gamePid
        Status          = 'Running'
        ProfilePath     = $profilePath
        ConfigPath      = $configPath
        StartScriptPath = $startScript
    }
}

function Stop-UGSMGame7D2DInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw '7D2D stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGame7D2DInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw '7D2D stop failed: Install definition could not be resolved.'
    }

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGame7D2DProfileRoot -ProfileName ([string]$Instance.Name)
    }

    $configPath = Join-Path $profilePath 'serverconfig.xml'

    $targetProcessId = $null
    if ($Instance.PSObject.Properties.Name -contains 'Pid' -and $Instance.Pid) {
        $targetProcessId = [int]$Instance.Pid
    }

    # 7D2D should be stopped through Telnet first so it broadcasts, saves,
    # and exits cleanly. If that fails or times out, fall back to the existing
    # UGSM force-stop process tree behavior.
    $gracefulResult = $null
    if ((Test-Path -LiteralPath $configPath -PathType Leaf) -and $targetProcessId) {
        $gracefulResult = Stop-UGSMGame7D2DViaTelnet -ConfigPath $configPath -ProcessId $targetProcessId -TimeoutSeconds 180
    }

    $stopResult = $null
    if ($gracefulResult -and $gracefulResult.Stopped) {
        $stopResult = [pscustomobject]@{
            Pid      = $targetProcessId
            Stopped  = $true
            TimedOut = $false
            Method   = 'Telnet'
            Graceful = $true
            Detail   = $gracefulResult
        }
    }
    elseif ($targetProcessId -and (Get-Command -Name Stop-UGSMProcessTree -ErrorAction SilentlyContinue)) {
        $stopResult = Stop-UGSMProcessTree -ProcessId $targetProcessId -TimeoutSeconds 20
        try { Add-Member -InputObject $stopResult -MemberType NoteProperty -Name 'Graceful' -Value $false -Force } catch {}
        try { Add-Member -InputObject $stopResult -MemberType NoteProperty -Name 'GracefulAttempt' -Value $gracefulResult -Force } catch {}
    }
    elseif ($targetProcessId) {
        try {
            & taskkill.exe /PID $targetProcessId /T /F
        }
        catch {
            try { Stop-Process -Id $targetProcessId -Force -ErrorAction Stop } catch {}
        }

        Start-Sleep -Seconds 2

        $isStillRunning = Test-UGSMGame7D2DProcessRunning -ProcessId $targetProcessId
        $stopResult = [pscustomobject]@{
            Pid             = $targetProcessId
            Stopped         = (-not $isStillRunning)
            TimedOut        = $isStillRunning
            Method          = 'Force'
            Graceful        = $false
            GracefulAttempt = $gracefulResult
        }
    }

    if ($targetProcessId -and ($null -eq $stopResult -or -not $stopResult.Stopped)) {
        throw ("7D2D stop failed: Process {0} is still running." -f $targetProcessId)
    }

    Start-Sleep -Seconds 2

    if ($Instance.PSObject.Properties.Name -contains 'Pid') {
        $Instance.Pid = $null
    }
    if ($Instance.PSObject.Properties.Name -contains 'Status') {
        $Instance.Status = 'Stopped'
    }

    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'CurrentPlayers' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCount' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'OnlinePlayers' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayersOnline' -Value 0
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountSource' -Value '7D2D_LOG_TIME_PLY'
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountStatus' -Value 'Stopped'
    Set-UGSMGame7D2DObjectPropertyValue -Object $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    $Instance = Update-UGSMGame7D2DInstanceNormalizedDiscordInfo -Instance $Instance -Persist

    return [pscustomobject]@{
        Instance       = $Instance
        Status         = 'Stopped'
        ProfilePath    = $profilePath
        ConfigPath     = $configPath
        StopResult     = $stopResult
        GracefulResult = $gracefulResult
    }
}

function Register-UGSMGame7D2DModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGame7D2DMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGame7D2DMetadata'
            TestInstall       = 'Test-UGSMGame7D2DInstall'
            TestInstance      = 'Test-UGSMGame7D2DInstance'
            Ensure7D2D    = 'Ensure-UGSMGame7D2D'
            InitializeProfile = 'Initialize-UGSMGame7D2DProfile'
            Start             = 'Start-UGSMGame7D2DInstance'
            Stop              = 'Stop-UGSMGame7D2DInstance'

            BuildEditor       = 'New-UGSMGame7D2DInstanceEditor'
            SaveEditor        = 'Save-UGSMGame7D2DInstanceEditor'
        }
    }
}


function Get-UGSMGame7D2DBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','ArchiveModsManifest')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -eq 'Settings') {
        $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance
        if ($paths -and $paths.PSObject.Properties['ServerConfigPath']) {
            [void]$targets.Add([pscustomobject]@{
                SourcePath    = [string]$paths.ServerConfigPath
                RelativePath  = 'serverconfig.xml'
                Label         = '7D2D server config'
            })
        }
    }

    if ($Scope -eq 'ArchiveModsManifest') {
        $manifestPath = Get-UGSMGame7D2DSharedModsManifestPath -Instance $Instance
        [void]$targets.Add([pscustomobject]@{
            SourcePath    = [string]$manifestPath
            RelativePath  = 'Mods\UGSM_ManagedArchiveMods.json'
            Label         = '7D2D managed archive mods manifest'
        })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGame7D2DManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','ArchiveModsManifest')]
        [string]$Scope = 'Settings',
        [string]$Reason = '7D2D managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGame7D2DBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId '7D2D' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGame7D2DLog -Level 'WARN' -Message ('7D2D managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGame7D2DProfilePaths {
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
        $profileRoot = Get-UGSMGame7D2DProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId '7D2D' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw '7D2D profile paths could not be resolved for the selected instance.'
    }

    $serverConfigPath = Join-Path $profileRoot 'serverconfig.xml'
    $startScriptPath = Join-Path $profileRoot 'startdedicated.bat'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot
        ConfigRoot                  = $profileRoot
        SaveRoot                    = $profileRoot
        LogRoot                     = $profileRoot

        ProfileConfigRoot           = $profileRoot
        ProfileSaveRoot             = $profileRoot
        ProfileLogRoot              = $profileRoot

        RuntimeRoot                 = $profileRoot
        RuntimeConfigRoot           = $profileRoot
        RuntimeSaveRoot             = $profileRoot
        RuntimeLogRoot              = $profileRoot
        RuntimeMarkerPath           = Join-Path $profileRoot 'UGSM.Runtime.json'
        IsRuntimeActive             = $false

        PrimaryIniPath              = $null
        PrimaryJsonPath             = $null
        PrimaryXmlPath              = $serverConfigPath
        PrimaryCfgPath              = $null

        ServerConfigPath            = $serverConfigPath
        StartScriptPath             = $startScriptPath
        ServerSettingsPath          = $serverConfigPath
        GameplayJsonPath            = $null
        GameplayXmlPath             = $serverConfigPath
        ServerCfgPath               = $null

        AdminUsersPath              = $null
        ExclusiveUsersPath          = $null
        WhitelistedUsersPath        = $null
        BannedUsersPath             = $null
        SilencedUsersPath           = $null

        RuntimePrimaryIniPath       = $null
        RuntimePrimaryJsonPath      = $null
        RuntimePrimaryXmlPath       = $serverConfigPath
        RuntimePrimaryCfgPath       = $null

        RuntimeServerSettingsPath   = $serverConfigPath
        RuntimeGameplayJsonPath     = $null
        RuntimeGameplayXmlPath      = $serverConfigPath
        RuntimeServerCfgPath        = $null

        RuntimeAdminUsersPath       = $null
        RuntimeExclusiveUsersPath   = $null
        RuntimeWhitelistedUsersPath = $null
        RuntimeBannedUsersPath      = $null
        RuntimeSilencedUsersPath    = $null

        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $null
        DatabasePath                = $null
    }
}

function Read-UGSMGame7D2DIniFile {
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

function Get-UGSMGame7D2DIniValue {
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

function Set-UGSMGame7D2DIniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        [AllowNull()]
        [string]$Value
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($existingLine in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$existingLine)
        }
    }

    if ($lines.Count -eq 0) {
        $lines.Add('[' + $Section + ']')
        $lines.Add($Key + '=' + $Value)
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return
    }

    $sectionRegex = '^\s*\[' + [regex]::Escape($Section) + '\]\s*$'
    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*='
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
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return
    }

    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i] -match $keyRegex) {
            $lines[$i] = $Key + '=' + $Value
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    $insertIndex = $sectionEnd
    $lines.Insert($insertIndex, $Key + '=' + $Value)
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Read-UGSMGame7D2DStringListFile {
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

function Write-UGSMGame7D2DStringListFile {
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

    Set-Content -LiteralPath $Path -Value $cleanValues -Encoding UTF8
}


function Ensure-UGSMGame7D2DParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGame7D2DJsonFile {
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

function Write-UGSMGame7D2DJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGame7D2DParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGame7D2DXmlFile {
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

function Get-UGSMGame7D2DXmlPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$XmlData,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$DefaultValue = $null
    )

    if ($null -eq $XmlData -or [string]::IsNullOrWhiteSpace([string]$Name)) {
        return $DefaultValue
    }

    try {
        $safeName = $Name.Replace("'", "&apos;")
        $node = $XmlData.SelectSingleNode("//property[@name='$safeName']")
        if ($null -eq $node) { return $DefaultValue }

        $value = $node.GetAttribute('value')
        if ($null -eq $value) { return $DefaultValue }
        return [string]$value
    }
    catch {
        return $DefaultValue
    }
}

function Write-UGSMGame7D2DXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGame7D2DParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGame7D2DCfgFile {
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

function Set-UGSMGame7D2DCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGame7D2DParentDirectory -Path $Path

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
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    [void]$lines.Add(('{0} = "{1}"' -f $Key, $Value))
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# GAME-SPECIFIC OPTIONAL BLOCK
# Remove this whole PSSQLite section unless the target game really stores editable server/admin data in SQLite.
function Test-UGSMGame7D2DPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGame7D2DPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGame7D2DPSSQLiteInstalled)
}

function Get-UGSMGame7D2DElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGame7D2DPSSQLiteInstalled)) {
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

function Save-UGSMGame7D2DElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGame7D2DPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw '7D2D.db was not found.'
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


function Resolve-UGSMGame7D2DEditorFieldPath {
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

function ConvertTo-UGSMGame7D2DEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'Boolean' {
            return [string]$(if ($Control.Checked) { 'True' } else { 'False' })
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


function Set-UGSMGame7D2DXmlPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Value
    )

    $values = [ordered]@{}
    $values[$Name] = $Value
    Set-UGSMGame7D2DXmlPropertyValues -Path $Path -Values $values
}

function Set-UGSMGame7D2DXmlPropertyValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Values
    )

    Ensure-UGSMGame7D2DParentDirectory -Path $Path

    $text = ''
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = "<?xml version=`"1.0`"?>`r`n<ServerSettings>`r`n</ServerSettings>`r`n"
    }

    $keys = @()
    if ($Values -is [hashtable] -or $Values -is [System.Collections.Specialized.OrderedDictionary]) {
        $keys = @($Values.Keys)
    }
    else {
        $keys = @($Values.PSObject.Properties.Name)
    }

    foreach ($nameObject in $keys) {
        $name = [string]$nameObject
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $rawValue = $null
        if ($Values -is [hashtable] -or $Values -is [System.Collections.Specialized.OrderedDictionary]) { $rawValue = $Values[$name] }
        elseif ($Values.PSObject.Properties[$name]) { $rawValue = $Values.$name }
        $safeValue = [System.Security.SecurityElement]::Escape([string]$rawValue)
        if ($null -eq $safeValue) { $safeValue = '' }
        $namePattern = [regex]::Escape($name)
        $pattern = '(<property\s+name="' + $namePattern + '"\s+value=")([^"]*)(")'
        if ([regex]::IsMatch($text, $pattern)) {
            $text = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $safeValue + $m.Groups[3].Value }, 1)
        }
        else {
            $newLine = "`t<property name=`"$name`"`t`t`t`t`t`tvalue=`"$safeValue`"/>"
            $text = [regex]::Replace($text, '</ServerSettings>\s*$', $newLine + "`r`n</ServerSettings>`r`n")
        }
    }

    Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
}

function Get-UGSMGame7D2DInstanceDefinitionPath {
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

function Save-UGSMGame7D2DInstanceDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $saved = $false

    # Keep the central UGSM instance store updated, but do not return early.
    # The 7D2D runtime fields are normalized onto the instance object, so the
    # profile-side JSON should also be refreshed for Discord/dashboard readers.
    foreach ($commandName in @('Save-UGSMInstance', 'Update-UGSMInstance', 'Set-UGSMInstance')) {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            try {
                & $commandName -Instance $Instance | Out-Null
                $saved = $true
                break
            }
            catch { }
        }
    }

    foreach ($commandName in @('Save-UGSMInstances', 'Save-UGSMInstanceStore')) {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            try {
                & $commandName | Out-Null
                $saved = $true
                break
            }
            catch { }
        }
    }

    $definitionPath = Get-UGSMGame7D2DInstanceDefinitionPath -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace([string]$definitionPath)) {
        try {
            $parent = Split-Path -Parent $definitionPath
            if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $json = $Instance | ConvertTo-Json -Depth 16
            Set-Content -LiteralPath $definitionPath -Value $json -Encoding UTF8 -ErrorAction Stop
            $saved = $true
        }
        catch { }
    }

    return $saved
}

function Save-UGSMGame7D2DInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGame7D2DInstanceDiscordShape -Instance $Instance
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false
    $xmlUpdates = [ordered]@{}

    foreach ($dirPath in @($paths.ConfigRoot, $paths.SaveRoot, $paths.LogRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }

    $saveSummary = [ordered]@{ ConfigKeysWritten = 0; IniKeysWritten = 0; StringListsWritten = 0; RuntimeCopiesUpdated = 0; InstanceSettingsSaved = 0 }

    function Save-7D2DConfigFieldValue {
        param([Parameter(Mandatory)][hashtable]$Field, [AllowNull()][string]$Value)
        $fileName = if ($Field.ContainsKey('File')) { [string]$Field.File } else { '' }
        $keyName = if ($Field.ContainsKey('Key')) { [string]$Field.Key } else { [string]$Field.Id }
        if ($fileName -ieq 'serverconfig.xml') { $xmlUpdates[$keyName] = $Value; return }
        Set-UGSMGame7D2DIniValue -Path $paths.ServerSettingsPath -Section ([string]$Field.Section) -Key ([string]$Field.Key) -Value $Value
    }

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }
        $field = $item.Field; $control = $item.Control
        if (-not $field -or -not $control) { continue }
        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGame7D2DEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) { $targetPath = Resolve-UGSMGame7D2DEditorFieldPath -Field $field -Paths $paths }
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) { throw ("7D2D save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id) }
                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGame7D2DStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++; $saveSummary.RuntimeCopiesUpdated++
            }
            'Boolean' { $value = if ($control.Checked) { 'true' } else { 'false' }; Save-7D2DConfigFieldValue -Field $field -Value $value; $saveSummary.ConfigKeysWritten++; $saveSummary.RuntimeCopiesUpdated++ }
            'Number' { $value = ConvertTo-UGSMGame7D2DEditorFieldValue -Field $field -Control $control; Save-7D2DConfigFieldValue -Field $field -Value $value; $saveSummary.ConfigKeysWritten++; $saveSummary.RuntimeCopiesUpdated++ }
            'MultilineText' { $value = ConvertTo-UGSMGame7D2DEditorFieldValue -Field $field -Control $control; Save-7D2DConfigFieldValue -Field $field -Value $value; $saveSummary.ConfigKeysWritten++; $saveSummary.RuntimeCopiesUpdated++ }
            'Text' { $value = ConvertTo-UGSMGame7D2DEditorFieldValue -Field $field -Control $control; Save-7D2DConfigFieldValue -Field $field -Value $value; $saveSummary.ConfigKeysWritten++; $saveSummary.RuntimeCopiesUpdated++ }
            'Password' { $value = ConvertTo-UGSMGame7D2DEditorFieldValue -Field $field -Control $control; Save-7D2DConfigFieldValue -Field $field -Value $value; $saveSummary.ConfigKeysWritten++; $saveSummary.RuntimeCopiesUpdated++ }
            'InstanceText' { $value = [string](ConvertTo-UGSMGame7D2DEditorFieldValue -Field $field -Control $control); if ([string]$field.Model -eq 'Discord') { $discordInput[[string]$field.Property] = $value; $hasDiscordChanges = $true } }
            'InstanceBoolean' { $value = [bool]$control.Checked; if ([string]$field.Model -eq 'Discord') { $discordInput[[string]$field.Property] = $value; $hasDiscordChanges = $true } }
        }
    }

    if ($xmlUpdates.Count -gt 0) {
        Invoke-UGSMGame7D2DManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before 7D2D settings save' | Out-Null
        Set-UGSMGame7D2DXmlPropertyValues -Path $paths.ServerConfigPath -Values $xmlUpdates
    }

    $updatedInstance = Update-UGSMGame7D2DInstanceNormalizedDiscordInfo -Instance $updatedInstance -Persist

    if ($hasDiscordChanges) {
        $persistScript = { param($PersistedInstance) [void](Save-UGSMGame7D2DInstanceDefinition -Instance $PersistedInstance) }
        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) { $updatedInstance = $discordResult.Instance; $saveSummary.InstanceSettingsSaved++ }
    }

    return [pscustomobject]@{ Success = $true; Message = ("Saved 7D2D settings. Config keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.ConfigKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved); Summary = [pscustomobject]$saveSummary; Instance = $updatedInstance }
}

function New-UGSMGame7D2DInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Instance = Ensure-UGSMGame7D2DInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance
    $schema = Get-UGSMGame7D2DEditorSchema
    $iniData = Read-UGSMGame7D2DIniFile -Path $paths.ServerSettingsPath
    $xmlData = Read-UGSMGame7D2DXmlFile -Path $paths.ServerConfigPath
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

    function Get-7D2DSafeIniValue {
        param([hashtable]$Field)
        try {
            $fileName = if ($Field.ContainsKey('File')) { [string]$Field.File } else { '' }
            $keyName = if ($Field.ContainsKey('Key')) { [string]$Field.Key } else { [string]$Field.Id }
            if ($fileName -ieq 'serverconfig.xml') { return [string](Get-UGSMGame7D2DXmlPropertyValue -XmlData $xmlData -Name $keyName -DefaultValue $Field.DefaultValue) }
            return [string](Get-UGSMGame7D2DIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = '7D2D field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-7D2DSafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = '7D2D instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-7D2DTextBox {
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

    function New-7D2DStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-7D2DTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-7D2DNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-7D2DElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits 7D2D.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMGame7D2DPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in 7D2D.db.')
                return
            }

            $dbPath = Resolve-UGSMGame7D2DDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('7D2D.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('7D2D.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGame7D2DElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading 7D2D.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGame7D2DPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGame7D2DDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw '7D2D.db path could not be resolved for this instance.' }
                    Save-UGSMGame7D2DElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to 7D2D.db: ' + $dbPath }
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

    function Add-7D2DFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the 7D2D editor can render any supported schema shape.
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
            $modsHost.Height = 740
            $modsHost.Width = [Math]::Max(760, $Parent.ClientSize.Width - 16)
            $modsHost.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
            $modsDefinition = $null
            if ($Field.ContainsKey('ModsDefinition')) { $modsDefinition = $Field.ModsDefinition }
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGame7D2DModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the 7D2D Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-7D2DNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-7D2DSafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-7D2DNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-7D2DSafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-7D2DNarrowHost
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
                    $rawValue = Get-7D2DSafeIniValue -Field $Field
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
                    $control = New-7D2DStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-7D2DSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-7D2DStretchTextBox -MaskSecret
                    $control.Text = [string](Get-7D2DSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-7D2DStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-7D2DSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-7D2DTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGame7D2DEditorFieldPath -Field $Field -Paths $paths
                    $control.Tag = [string]$resolvedListPath
                    $control.ScrollBars = 'Vertical'
                    $control.AcceptsReturn = $true
                    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedListPath) -and (Test-Path -LiteralPath $resolvedListPath -PathType Leaf)) {
                        $control.Lines = @(Get-Content -LiteralPath $resolvedListPath -ErrorAction SilentlyContinue)
                    }
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control; Path = $resolvedListPath }
                }
                'ActionButton' {
                    $buttonHost = New-7D2DNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = '7D2D action failed: ' + $_.Exception.Message } }
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

                    New-7D2DElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-7D2DStretchTextBox
                    $control.Text = [string](Get-7D2DSafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('7D2D field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color '#FF7B72'
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-7D2DEditorContent {
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
            Add-7D2DFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('7D2D Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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

            # Mods tab is owned by UGSM_Game_Helper.ps1. The game module only creates
            # the TabPage host and passes the instance/mod definition into the shared renderer.
            if ([string]$tabDef.Title -eq 'Mods') {
                $modsTabFeatures = Get-UGSMGame7D2DSupportedFeatures
                if ([bool]$modsTabFeatures.Mods) {
                    try {
                        $modsDefinition = Get-UGSMGame7D2DModsDefinition
                        $sharedRenderer = Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue
                        if ($sharedRenderer) {
                            [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $tabPage -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
                        }
                        else {
                            $missing = New-UGSMLabel -Text 'Shared Steam Workshop Mods editor is not loaded. Load UGSM_Game_Helper.ps1 before opening this tab.' -X 12 -Y 12 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
                            [void]$tabPage.Controls.Add($missing)
                        }
                    }
                    catch {
                        $err = New-UGSMLabel -Text ('7D2D shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color '#FF7B72'
                        [void]$tabPage.Controls.Add($err)
                        if ($StatusLabel) { $StatusLabel.Text = '7D2D shared Mods tab failed: ' + $_.Exception.Message }
                    }
                    continue
                }
            }

            if ($tabDef.PSObject.Properties.Name -contains 'SubTabs' -and @($tabDef.SubTabs).Count -gt 0) {
                $subTabs = New-Object System.Windows.Forms.TabControl
                $subTabs.Dock = 'Fill'
                [void]$tabPage.Controls.Add($subTabs)

                foreach ($subDef in @($tabDef.SubTabs)) {
                    $subPage = New-Object System.Windows.Forms.TabPage
                    $subPage.Text = [string]$subDef.Title
                    $subPage.BackColor = New-UGSMColor '#0B121D'
                    [void]$subTabs.TabPages.Add($subPage)
                    New-7D2DEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-7D2DEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGame7D2DInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved 7D2D profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = '7D2D save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGame7D2DInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = '7D2D profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = '7D2D reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = '7D2D profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGame7D2DOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw '7D2D open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("7D2D open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw '7D2D open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("7D2D open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("7D2D open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}


function Resolve-UGSMGame7D2DInstance {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    if ($null -eq $Instance) { return $null }

    $resolved = $Instance
    $installPath = ''
    try {
        if ($resolved.PSObject.Properties['InstallPath']) { $installPath = [string]$resolved.InstallPath }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($installPath)) {
        try {
            $def = Get-UGSMGame7D2DInstallDefinition
            if ($def -and $def.PSObject.Properties['InstallPath']) { $installPath = [string]$def.InstallPath }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($installPath)) {
        try {
            if ($resolved.PSObject.Properties['InstallPath']) { $resolved.InstallPath = $installPath }
            else { Add-Member -InputObject $resolved -MemberType NoteProperty -Name 'InstallPath' -Value $installPath -Force }
        } catch {}
    }

    return $resolved
}

function Get-UGSMGame7D2DSharedModsRoot {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $installPath = ''
    try {
        $resolved = Resolve-UGSMGame7D2DInstance -Instance $Instance
        if ($resolved -and $resolved.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$resolved.InstallPath)) {
            $installPath = [string]$resolved.InstallPath
        }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($installPath)) {
        try {
            $def = Get-UGSMGame7D2DInstallDefinition
            if ($def -and $def.PSObject.Properties['InstallPath']) { $installPath = [string]$def.InstallPath }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($installPath)) { throw '7D2D install path could not be resolved for shared Mods folder.' }
    return (Join-Path $installPath 'Mods')
}

function Get-UGSMGame7D2DSharedModsManifestPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    return (Join-Path (Get-UGSMGame7D2DSharedModsRoot -Instance $Instance) 'UGSM_ManagedArchiveMods.json')
}

function Read-UGSMGame7D2DSharedModsManifest {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $path = Get-UGSMGame7D2DSharedModsManifestPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Version = 1; GameId = '7D2D'; Mods = @() } }
    try { return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch { return [pscustomobject]@{ Version = 1; GameId = '7D2D'; Mods = @() } }
}

function Save-UGSMGame7D2DSharedModsManifest {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][object]$Mods
    )

    $Mods = @($Mods)
    $modsRoot = Get-UGSMGame7D2DSharedModsRoot -Instance $Instance
    if (-not (Test-Path -LiteralPath $modsRoot -PathType Container)) { New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null }
    $path = Get-UGSMGame7D2DSharedModsManifestPath -Instance $Instance
    $payload = [pscustomobject]@{
        Version = 1
        GameId = '7D2D'
        Storage = 'SharedInstallModsFolder'
        ModsRoot = $modsRoot
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        Mods = @($Mods)
    }
    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-UGSMGame7D2DArchiveModEntriesFromFolder {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $modsRoot = Get-UGSMGame7D2DSharedModsRoot -Instance $Instance
    $existingManifest = Read-UGSMGame7D2DSharedModsManifest -Instance $Instance
    $known = @{}
    foreach ($m in @($existingManifest.Mods)) {
        try { if ($m -and $m.PSObject.Properties['Name']) { $known[[string]$m.Name] = $m } } catch {}
    }

    $entries = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $modsRoot -PathType Container)) { return @() }

    $order = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $name = [string]$dir.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $modInfo = Join-Path $dir.FullName 'ModInfo.xml'
        if (-not (Test-Path -LiteralPath $modInfo -PathType Leaf)) { continue }

        $old = $null
        if ($known.ContainsKey($name)) { $old = $known[$name] }
        $sourceArchive = if ($old -and $old.PSObject.Properties['SourceArchive']) { [string]$old.SourceArchive } else { '' }
        $installedUtc = if ($old -and $old.PSObject.Properties['InstalledUtc']) { [string]$old.InstalledUtc } else { '' }
        if ([string]::IsNullOrWhiteSpace($installedUtc)) { $installedUtc = (Get-Date).ToUniversalTime().ToString('o') }

        [void]$entries.Add([pscustomobject]@{
            Id = $name
            Name = $name
            FolderName = $name
            SourceType = 'Archive'
            Enabled = $true
            LoadOrder = $order
            RuntimeMode = 'SharedArchiveMods'
            SharedContentPath = $dir.FullName
            InstalledPath = $dir.FullName
            SourceArchive = $sourceArchive
            InstalledUtc = $installedUtc
            Notes = 'Shared 7D2D install Mods folder'
        })
        $order++
    }
    return @($entries.ToArray())
}

function Sync-UGSMGame7D2DArchiveMods {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][object]$Manifest,
        [AllowNull()][object]$ModsDefinition
    )

    $entries = @(Get-UGSMGame7D2DArchiveModEntriesFromFolder -Instance $Instance)
    Save-UGSMGame7D2DSharedModsManifest -Instance $Instance -Mods $entries | Out-Null

    if ($Manifest) {
        $Manifest.Mods = @($entries)
        $Manifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        return [pscustomobject]@{ Success = $true; Manifest = $Manifest; Mods = @($entries); Count = @($entries).Count }
    }

    return [pscustomobject]@{ Success = $true; Mods = @($entries); Count = @($entries).Count }
}

function Expand-UGSMGame7D2DArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container)) { New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null }
    $ext = [System.IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()

    if ($ext -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory([string]$ArchivePath, [string]$DestinationPath)
        return
    }

    if ($ext -eq '.rar') {
        $tar = Get-Command -Name tar.exe -ErrorAction SilentlyContinue
        if ($tar) {
            $p = Start-Process -FilePath $tar.Source -ArgumentList @('-xf', $ArchivePath, '-C', $DestinationPath) -Wait -PassThru -WindowStyle Hidden
            if ($p -and [int]$p.ExitCode -eq 0) { return }
        }

        try {
            $shell = New-Object -ComObject Shell.Application
            $src = $shell.NameSpace($ArchivePath)
            $dst = $shell.NameSpace($DestinationPath)
            if ($src -and $dst) {
                $dst.CopyHere($src.Items(), 0x14)
                Start-Sleep -Seconds 2
                return
            }
        } catch {}

        throw 'RAR extraction failed. This Windows build may need tar.exe or Explorer RAR support.'
    }

    throw ('Unsupported mod archive type: ' + $ext)
}

function Find-UGSMGame7D2DModFolders {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $folders = New-Object System.Collections.Generic.List[string]
    foreach ($mi in @(Get-ChildItem -LiteralPath $Root -Filter 'ModInfo.xml' -File -Recurse -ErrorAction SilentlyContinue)) {
        try { [void]$folders.Add([string]$mi.Directory.FullName) } catch {}
    }
    return @($folders.ToArray() | Select-Object -Unique)
}

function Import-UGSMGame7D2DArchiveMod {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][object]$Manifest,
        [AllowNull()][object]$ModsDefinition,
        [Parameter(Mandatory)][string]$ArchivePath
    )

    $stage = 'start'
    try {
        $stage = 'resolve instance'
        $Instance = Resolve-UGSMGame7D2DInstance -Instance $Instance
        if ($null -eq $Instance) { throw '7D2D mod import failed: instance was null.' }

        $stage = 'validate archive'
        $ArchivePath = [string]$ArchivePath
        if ([string]::IsNullOrWhiteSpace($ArchivePath) -or -not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
            throw 'Selected mod archive was not found.'
        }

        $stage = 'resolve mods root'
        $modsRoot = [string](Get-UGSMGame7D2DSharedModsRoot -Instance $Instance)
        if ([string]::IsNullOrWhiteSpace($modsRoot)) { throw '7D2D shared Mods folder could not be resolved.' }
        if (-not (Test-Path -LiteralPath $modsRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
        }

        $archiveLeaf = [string](Split-Path -Leaf $ArchivePath)
        Invoke-UGSMGame7D2DManagedBackup -Instance $Instance -Scope 'ArchiveModsManifest' -Reason 'Before 7D2D archive mod import' | Out-Null
        Write-UGSMGame7D2DLog -Level 'INFO' -Message ('7D2D archive mod import started. Archive=' + $archiveLeaf)

        $stage = 'create temp folder'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('UGSM_7D2D_ModImport_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        try {
            $stage = 'extract archive'
            Expand-UGSMGame7D2DArchive -ArchivePath $ArchivePath -DestinationPath $tempRoot

            $stage = 'find mod folders'
            $modFolders = @(Find-UGSMGame7D2DModFolders -Root $tempRoot | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if (@($modFolders).Count -eq 0) {
                throw 'No 7D2D mod folders with ModInfo.xml were found in the selected archive.'
            }

            $stage = 'read existing shared mods'
            $existing = @(Get-UGSMGame7D2DArchiveModEntriesFromFolder -Instance $Instance)
            $byName = @{}
            foreach ($e in @($existing)) {
                try {
                    if ($e -and $e.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$e.Name)) {
                        $byName[[string]$e.Name] = $e
                    }
                } catch {}
            }

            $stage = 'copy mod folders'
            $imported = @()
            foreach ($folder in @($modFolders)) {
                $folder = [string]$folder
                if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

                $name = [string](Split-Path -Leaf $folder)
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $dest = [string](Join-Path $modsRoot $name)
                if (Test-Path -LiteralPath $dest) {
                    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop
                }
                Copy-Item -LiteralPath $folder -Destination $dest -Recurse -Force -ErrorAction Stop

                $entry = [pscustomobject]@{
                    Id                = $name
                    Name              = $name
                    FolderName        = $name
                    SourceType        = 'Archive'
                    Enabled           = $true
                    LoadOrder         = 0
                    RuntimeMode       = 'SharedArchiveMods'
                    SharedContentPath = $dest
                    InstalledPath     = $dest
                    SourceArchive     = $archiveLeaf
                    InstalledUtc      = [DateTime]::UtcNow.ToString('o')
                    Notes             = 'Shared 7D2D install Mods folder'
                }
                $byName[$name] = $entry
                $imported += $entry
            }

            if (@($imported).Count -eq 0) { throw 'No mod folders were copied from the selected archive.' }

            $stage = 'build manifest'
            $all = @($byName.Values | Where-Object { $_ } | Sort-Object @{ Expression = { if ($_.PSObject.Properties['Name']) { [string]$_.Name } else { [string]$_.Id } } })
            $i = 0
            foreach ($m in @($all)) {
                try {
                    if ($m.PSObject.Properties['LoadOrder']) { $m.LoadOrder = [int]$i }
                    else { Add-Member -InputObject $m -MemberType NoteProperty -Name LoadOrder -Value ([int]$i) -Force }
                } catch {}
                $i++
            }

            $stage = 'save shared manifest'
            Save-UGSMGame7D2DSharedModsManifest -Instance $Instance -Mods @($all) | Out-Null

            $stage = 'return manifest'
            $outManifest = [pscustomobject]@{
                Version      = 1
                GameId       = '7D2D'
                Storage      = 'SharedInstallModsFolder'
                Mods         = @($all)
                UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
            }

            Write-UGSMGame7D2DLog -Level 'INFO' -Message ('7D2D archive mod import complete. Imported=' + @($imported).Count + '; Total=' + @($all).Count)
            return [pscustomobject]@{
                Success   = $true
                Imported  = @($imported)
                Manifest  = $outManifest
                ModsRoot  = $modsRoot
                TotalMods = @($all).Count
            }
        }
        finally {
            try {
                if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
    catch {
        $msg = '7D2D archive mod import failed at stage [' + $stage + ']: ' + $_.Exception.Message
        Write-UGSMGame7D2DLog -Level 'ERROR' -Message $msg
        throw $msg
    }
}

function Remove-UGSMGame7D2DArchiveMod {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][object]$Manifest,
        [AllowNull()][object]$ModsDefinition,
        [Parameter(Mandatory)][string]$ModName
    )

    $Instance = Resolve-UGSMGame7D2DInstance -Instance $Instance
    if ($null -eq $Instance) { throw '7D2D mod remove failed: instance was null.' }

    $modsRoot = Get-UGSMGame7D2DSharedModsRoot -Instance $Instance
    Invoke-UGSMGame7D2DManagedBackup -Instance $Instance -Scope 'ArchiveModsManifest' -Reason 'Before 7D2D archive mod remove' | Out-Null
    $target = Join-Path $modsRoot $ModName
    if (Test-Path -LiteralPath $target -PathType Container) { Remove-Item -LiteralPath $target -Recurse -Force }

    $remaining = @(Get-UGSMGame7D2DArchiveModEntriesFromFolder -Instance $Instance | Where-Object { [string]$_.Name -ne [string]$ModName })
    $i = 0
    foreach ($m in $remaining) { try { $m.LoadOrder = $i } catch {}; $i++ }
    Save-UGSMGame7D2DSharedModsManifest -Instance $Instance -Mods $remaining | Out-Null

    $outManifest = if ($Manifest) { $Manifest } else { [pscustomobject]@{ Version = 1; GameId = '7D2D'; Mods = @() } }
    $outManifest.Mods = @($remaining)
    $outManifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')

    Write-UGSMGame7D2DLog -Level 'INFO' -Message ('7D2D archive mod removed. Mod=' + $ModName + '; Remaining=' + @($remaining).Count)
    return [pscustomobject]@{ Success = $true; Removed = $ModName; Manifest = $outManifest; RemainingCount = @($remaining).Count }
}



function Resolve-UGSMGame7D2DEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw '7D2D action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGame7D2DProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("7D2D action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("7D2D action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGame7D2DEditorAction {
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

    $resolvedPath = Resolve-UGSMGame7D2DEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGame7D2DOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}


<#Adjust Schema to be game specific. these values were taken from Ark Survival Evolved. #>




function Get-UGSMGame7D2DEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenPrimaryIni     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGame7D2DEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryIni'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ServerSettings.ini.' }
        OpenPrimaryJson    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGame7D2DEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryJson'    -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened Gameplay.json.' }
        OpenPrimaryXml     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGame7D2DEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryXml'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened serverconfig.xml.' }
        OpenPrimaryCfg     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGame7D2DEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryCfg'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened server.cfg.' }
    }

    $features = Get-UGSMGame7D2DSupportedFeatures

    # ============================================================
    # 7D2D GAME SCHEMA
    # This is the main section to edit when copying this file.
    # Keep fields generic here. Add game-specific tabs/fields only after
    # copying the 7D2D into a real UGSM_Game_<Game>.ps1 module.
    # Privacy rule: every password/webhook/token/API key/GSLT/RCON secret must use Type='Password' or Secret=$true.
    # These render as masked/dot fields so secrets do not show on streams/screenshots.
    # Profile-light rule: profiles should hold server settings, manifests, saves/logs, and tiny required config files only.
    # Do not copy binaries or full Workshop/mod folders into profiles.
    # ============================================================

    $schema = [pscustomobject]@{
        Version = 2
        Tabs = @(
            [pscustomobject]@{
                Title       = 'General'
                Description = 'Server identity, browser text, password, region, and language.'
                Fields      = @(
                    @{ Id = 'ServerName'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'ServerName'; Label = 'Server Name'; DefaultValue = 'My Game Host'; Hint = 'Whatever you want the name of the server to be.' }
                    @{ Id = 'ServerDescription'; Type = 'MultilineText'; File = 'serverconfig.xml'; Key = 'ServerDescription'; Label = 'Server Description'; DefaultValue = 'A 7 Days to Die server'; Hint = 'Whatever you want the server description to be, will be shown in the server browser.' }
                    @{ Id = 'ServerWebsiteURL'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'ServerWebsiteURL'; Label = 'Server Website URL'; DefaultValue = ''; Hint = 'Website URL for the server, will be shown in the server browser as a clickable link' }
                    @{ Id = 'ServerPassword'; Type = 'Password'; File = 'serverconfig.xml'; Key = 'ServerPassword'; Label = 'Server Password'; DefaultValue = ''; Hint = 'Password to gain entry to the server' }
                    @{ Id = 'ServerLoginConfirmationText'; Type = 'MultilineText'; File = 'serverconfig.xml'; Key = 'ServerLoginConfirmationText'; Label = 'Server Login Confirmation Text'; DefaultValue = ''; Hint = 'If set the user will see the message during joining the server and has to confirm it before continuing. For more complex changes to this window you can change the "serverjoinrulesdialog" window in XUi' }
                    @{ Id = 'Region'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'Region'; Label = 'Region'; DefaultValue = 'NorthAmericaEast'; Hint = 'The region this server is in. Values: NorthAmericaEast, NorthAmericaWest, CentralAmerica, SouthAmerica, Europe, Russia, Asia, MiddleEast, Africa, Oceania' }
                    @{ Id = 'Language'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'Language'; Label = 'Language'; DefaultValue = 'English'; Hint = 'Primary language for players on this server. Values: Use any language name that you would users expect to search for. Should be the English name of the language, e.g. not "Deutsch" but "German"' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network / Slots'
                Description = 'Ports, visibility, networking protocol, world transfer speed, and player/admin slot limits.'
                Fields      = @(
                    @{ Id = 'ServerPort'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerPort'; Label = 'Server Port'; DefaultValue = '26900'; Min = 1; Max = 65535; Decimals = 0; Hint = 'Port you want the server to listen on. Keep it in the ranges 26900 to 26905 or 27015 to 27020 if you want PCs on the same LAN to find it as a LAN server.' }
                    @{ Id = 'ServerVisibility'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerVisibility'; Label = 'Server Visibility'; DefaultValue = '2'; Min = 0; Max = 2; Decimals = 0; Hint = 'Visibility of this server: 2 = public, 1 = only shown to friends, 0 = not listed. As you are never friend of a dedicated server setting this to "1" will only work when the first player connects manually by IP.' }
                    @{ Id = 'ServerDisabledNetworkProtocols'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'ServerDisabledNetworkProtocols'; Label = 'Server Disabled Network Protocols'; DefaultValue = 'SteamNetworking'; Hint = 'Networking protocols that should not be used. Separated by comma. Possible values: LiteNetLib, SteamNetworking. Dedicated servers should disable SteamNetworking if there is no NAT router in between your users and the server or when port-forwarding is set up correctly' }
                    @{ Id = 'ServerMaxWorldTransferSpeedKiBs'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerMaxWorldTransferSpeedKiBs'; Label = 'Server Max World Transfer Speed Ki Bs'; DefaultValue = '512'; Min = 1; Max = 5000; Decimals = 0; Hint = 'Maximum (!) speed in kiB/s the world is transferred at to a client on first connect if it does not have the world yet. Maximum is about 1300 kiB/s, even if you set a higher value.' }
                    @{ Id = 'ServerMaxPlayerCount'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerMaxPlayerCount'; Label = 'Server Max Player Count'; DefaultValue = '8'; Min = 1; Max = 64; Decimals = 0; Hint = 'Maximum Concurrent Players' }
                    @{ Id = 'ServerReservedSlots'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerReservedSlots'; Label = 'Server Reserved Slots'; DefaultValue = '0'; Min = 0; Max = 64; Decimals = 0; Hint = 'Out of the MaxPlayerCount this many slots can only be used by players with a specific permission level' }
                    @{ Id = 'ServerReservedSlotsPermission'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerReservedSlotsPermission'; Label = 'Server Reserved Slots Permission'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Required permission level to use reserved slots above' }
                    @{ Id = 'ServerAdminSlots'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerAdminSlots'; Label = 'Server Admin Slots'; DefaultValue = '0'; Min = 0; Max = 64; Decimals = 0; Hint = 'This many admins can still join even if the server has reached MaxPlayerCount' }
                    @{ Id = 'ServerAdminSlotsPermission'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerAdminSlotsPermission'; Label = 'Server Admin Slots Permission'; DefaultValue = '0'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Required permission level to use the admin slots above' }
                )
            }

            [pscustomobject]@{
                Title       = 'Admin / Security'
                Description = 'Web dashboard, Telnet, terminal window, admin file, EAC, sanctions, command logging, and save limits.'
                Fields      = @(
                    @{ Id = 'WebDashboardEnabled'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'WebDashboardEnabled'; Label = 'Web Dashboard Enabled'; DefaultValue = 'false'; Hint = 'Enable/disable the web dashboard' }
                    @{ Id = 'WebDashboardPort'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'WebDashboardPort'; Label = 'Web Dashboard Port'; DefaultValue = '8080'; Min = 1; Max = 65535; Decimals = 0; Hint = 'Port of the web dashboard' }
                    @{ Id = 'WebDashboardUrl'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'WebDashboardUrl'; Label = 'Web Dashboard Url'; DefaultValue = ''; Hint = 'External URL to the web dashboard if not just using the public IP of the server, e.g. if the web dashboard is behind a reverse proxy. Needs to be the full URL, like "https://domainOfReverseProxy.tld:1234/". Can be left empty if directly using the public IP and dashboard port' }
                    @{ Id = 'EnableMapRendering'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'EnableMapRendering'; Label = 'Enable Map Rendering'; DefaultValue = 'false'; Hint = 'Enable/disable rendering of the map to tile images while exploring it. This is used e.g. by the web dashboard to display a view of the map.' }
                    @{ Id = 'TelnetEnabled'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'TelnetEnabled'; Label = 'Telnet Enabled'; DefaultValue = 'true'; Hint = 'Enable/Disable the telnet' }
                    @{ Id = 'TelnetPort'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'TelnetPort'; Label = 'Telnet Port'; DefaultValue = '8081'; Min = 1; Max = 65535; Decimals = 0; Hint = 'Port of the telnet server' }
                    @{ Id = 'TelnetPassword'; Type = 'Password'; File = 'serverconfig.xml'; Key = 'TelnetPassword'; Label = 'Telnet Password'; DefaultValue = ''; Hint = 'Password to gain entry to telnet interface. If no password is set the server will only listen on the local loopback interface' }
                    @{ Id = 'TelnetFailedLoginLimit'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'TelnetFailedLoginLimit'; Label = 'Telnet Failed Login Limit'; DefaultValue = '10'; Min = 0; Max = 999; Decimals = 0; Hint = 'After this many wrong passwords from a single remote client the client will be blocked from connecting to the Telnet interface' }
                    @{ Id = 'TelnetFailedLoginsBlocktime'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'TelnetFailedLoginsBlocktime'; Label = 'Telnet Failed Logins Blocktime'; DefaultValue = '10'; Min = 0; Max = 999999; Decimals = 0; Hint = 'How long will the block persist (in seconds)' }
                    @{ Id = 'TerminalWindowEnabled'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'TerminalWindowEnabled'; Label = 'Terminal Window Enabled'; DefaultValue = 'true'; Hint = 'Show a terminal window for log output / command input (Windows only)' }
                    @{ Id = 'AdminFileName'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'AdminFileName'; Label = 'Admin File Name'; DefaultValue = 'serveradmin.xml'; Hint = 'Server admin file name. Path relative to UserDataFolder/Saves' }
                    @{ Id = 'ServerAllowCrossplay'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'ServerAllowCrossplay'; Label = 'Server Allow Crossplay'; DefaultValue = 'false'; Hint = 'Enables/Disables crossplay, crossplay servers will only be found in searches and joinable if sanctions are not ignored, and have a default or fewer player slot count' }
                    @{ Id = 'EACEnabled'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'EACEnabled'; Label = 'E A C Enabled'; DefaultValue = 'true'; Hint = 'Enables/Disables EasyAntiCheat' }
                    @{ Id = 'IgnoreEOSSanctions'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'IgnoreEOSSanctions'; Label = 'Ignore EOS Sanctions'; DefaultValue = 'false'; Hint = 'Ignore EOS sanctions when allowing players to join' }
                    @{ Id = 'HideCommandExecutionLog'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'HideCommandExecutionLog'; Label = 'Hide Command Execution Log'; DefaultValue = '0'; Min = 0; Max = 3; Decimals = 0; Hint = 'Hide logging of command execution. 0 = show everything, 1 = hide only from Telnet/ControlPanel, 2 = also hide from remote game clients, 3 = hide everything' }
                    @{ Id = 'MaxUncoveredMapChunksPerPlayer'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'MaxUncoveredMapChunksPerPlayer'; Label = 'Max Uncovered Map Chunks Per Player'; DefaultValue = '131072'; Min = 0; Max = 2147483647; Decimals = 0; Hint = 'Override how many chunks can be uncovered on the in-game map by each player. Resulting max map file size limit per player is (x * 512 Bytes), uncovered area is (x * 256 m²). Default 131072 means max 32 km² can be uncovered at any time' }
                    @{ Id = 'PersistentPlayerProfiles'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'PersistentPlayerProfiles'; Label = 'Persistent Player Profiles'; DefaultValue = 'false'; Hint = 'If disabled a player can join with any selected profile. If true they will join with the last profile they joined with' }
                    @{ Id = 'MaxChunkAge'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'MaxChunkAge'; Label = 'Max Chunk Age'; DefaultValue = '-1'; Min = -1; Max = 2147483647; Decimals = 0; Hint = 'The number of in-game days which must pass since visiting a chunk before it will reset to its original state if not revisited or protected (e.g. by a land claim or bedroll being in close proximity).' }
                    @{ Id = 'SaveDataLimit'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'SaveDataLimit'; Label = 'Save Data Limit'; DefaultValue = '-1'; Min = -1; Max = 2147483647; Decimals = 0; Hint = 'The maximum disk space allowance for each saved game in megabytes (MB). Saved chunks may be forcibly reset to their original states to free up space when this limit is reached. Negative values disable the limit.' }
                )
            }

            [pscustomobject]@{
                Title       = 'World / Time'
                Description = 'World selection/generation, save name, game mode, day length, weather, death/drop rules, and spawn rules.'
                Fields      = @(
                    @{ Id = 'GameWorld'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'GameWorld'; Label = 'Game World'; DefaultValue = 'Navezgane'; Hint = '"RWG" (see WorldGenSeed and WorldGenSize options below) or any already existing world name in the Worlds folder (currently shipping with e.g. "Navezgane", "Pregen06k01", "Pregen06k02", "Pregen08k01", "Pregen08k02", ...)' }
                    @{ Id = 'WorldGenSeed'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'WorldGenSeed'; Label = 'World Gen Seed'; DefaultValue = 'MyGame'; Hint = 'If RWG this is the seed for the generation of the new world. If a world with the resulting name already exists it will simply load it' }
                    @{ Id = 'WorldGenSize'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'WorldGenSize'; Label = 'World Gen Size'; DefaultValue = '6144'; Min = 1024; Max = 32768; Decimals = 0; Hint = '6144, 8192, 10240 If GameWorld = RWG, this controls the width and height of the created world. Officially supported sizes are between 6144 and 10240 and must be a multiple of 2048, e.g. 6144, 8192, 10240.' }
                    @{ Id = 'GameName'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'GameName'; Label = 'Game Name'; DefaultValue = 'MyGame'; Hint = 'Whatever you want the game name to be (allowed [A-Za-z0-9_-. ]). This affects the save game name as well as the seed used when placing decoration (trees etc.) in the world. It does not control the generic layout of the world if creating an RWG world' }
                    @{ Id = 'GameMode'; Type = 'Text'; File = 'serverconfig.xml'; Key = 'GameMode'; Label = 'Game Mode'; DefaultValue = 'GameModeSurvival'; Hint = 'GameModeSurvival' }
                    @{ Id = 'BuildCreate'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'BuildCreate'; Label = 'Build Create'; DefaultValue = 'false'; Hint = 'cheat mode on/off' }
                    @{ Id = 'DayNightLength'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DayNightLength'; Label = 'Day Night Length'; DefaultValue = '60'; Min = 1; Max = 10000; Decimals = 0; Hint = 'real time minutes per in game day: 60 minutes' }
                    @{ Id = 'DayLightLength'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DayLightLength'; Label = 'Day Light Length'; DefaultValue = '18'; Min = 1; Max = 24; Decimals = 0; Hint = 'in game hours the sun shines per day: 18 hours day light per in game day' }
                    @{ Id = 'BiomeProgression'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'BiomeProgression'; Label = 'Biome Progression'; DefaultValue = 'true'; Hint = 'Enables biome hazards. Weather and storms are not affected by this setting.' }
                    @{ Id = 'StormFreq'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'StormFreq'; Label = 'Storm Freq'; DefaultValue = '100'; Min = 0; Max = 500; Decimals = 0; Hint = 'Adjusts the frequency of storms. 0% turns them off. Vanilla values: 0, 50, 100, 150, 200, 300, 400, 500' }
                    @{ Id = 'DeathPenalty'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DeathPenalty'; Label = 'Death Penalty'; DefaultValue = '1'; Min = 0; Max = 3; Decimals = 0; Hint = 'Penalty after dying. 0 = Nothing. 1 = Default: Classic XP Penalty.  2 = Injured: You keep most of your de-buffs. Food and Water is set to 50% on respawn. 3 = Permanent Death: Your character is completely reset. You will respawn with a fresh start within the saved game.' }
                    @{ Id = 'DropOnDeath'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DropOnDeath'; Label = 'Drop On Death'; DefaultValue = '1'; Min = 0; Max = 4; Decimals = 0; Hint = '0 = nothing, 1 = everything, 2 = toolbelt only, 3 = backpack only, 4 = delete all' }
                    @{ Id = 'DropOnQuit'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DropOnQuit'; Label = 'Drop On Quit'; DefaultValue = '0'; Min = 0; Max = 3; Decimals = 0; Hint = '0 = nothing, 1 = everything, 2 = toolbelt only, 3 = backpack only' }
                    @{ Id = 'BedrollDeadZoneSize'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BedrollDeadZoneSize'; Label = 'Bedroll Dead Zone Size'; DefaultValue = '15'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Size (box "radius", so a box with 2 times the given value for each side''s length) of bedroll dead zone, no zombies will spawn inside this area, and any cleared sleeper volumes that touch a bedroll deadzone will not spawn after they''ve been cleared.' }
                    @{ Id = 'BedrollExpiryTime'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BedrollExpiryTime'; Label = 'Bedroll Expiry Time'; DefaultValue = '45'; Min = 0; Max = 10000; Decimals = 0; Hint = 'Number of real world days a bedroll stays active after owner was last online' }
                    @{ Id = 'AllowSpawnNearFriend'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'AllowSpawnNearFriend'; Label = 'Allow Spawn Near Friend'; DefaultValue = '2'; Min = 0; Max = 2; Decimals = 0; Hint = 'Can new players joining the server for the first time select to join near any friend playing at the same time? 0 = Disabled, 1 = Always, 2 = Only near friends in forest biome' }
                    @{ Id = 'CameraRestrictionMode'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'CameraRestrictionMode'; Label = 'Camera Restriction Mode'; DefaultValue = '0'; Min = 0; Max = 2; Decimals = 0; Hint = '0 = Players can freely swap between first and third person camera modes, 1 = Restricted to first person, 2 = Restricted to third person' }
                    @{ Id = 'JarRefund'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'JarRefund'; Label = 'Jar Refund'; DefaultValue = '60'; Min = 0; Max = 100; Decimals = 0; Hint = '0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100% The empty jar refund percentage after consuming an item.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Gameplay / Rules'
                Description = 'Difficulty, block damage, XP, safe zone, performance limits, PvP, and party XP settings.'
                Fields      = @(
                    @{ Id = 'GameDifficulty'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'GameDifficulty'; Label = 'Game Difficulty'; DefaultValue = '1'; Min = 0; Max = 5; Decimals = 0; Hint = '0 - 5, 0=easiest, 5=hardest' }
                    @{ Id = 'BlockDamagePlayer'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BlockDamagePlayer'; Label = 'Block Damage Player'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How much damage do players to blocks (percentage in whole numbers)' }
                    @{ Id = 'BlockDamageAI'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BlockDamageAI'; Label = 'Block Damage AI'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How much damage do AIs to blocks (percentage in whole numbers)' }
                    @{ Id = 'BlockDamageAIBM'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BlockDamageAIBM'; Label = 'Block Damage AI BM'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How much damage do AIs during blood moons to blocks (percentage in whole numbers)' }
                    @{ Id = 'XPMultiplier'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'XPMultiplier'; Label = 'X P Multiplier'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'XP gain multiplier (percentage in whole numbers)' }
                    @{ Id = 'PlayerSafeZoneLevel'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'PlayerSafeZoneLevel'; Label = 'Player Safe Zone Level'; DefaultValue = '5'; Min = 0; Max = 1000; Decimals = 0; Hint = 'If a player is less or equal this level he will create a safe zone (no enemies) when spawned' }
                    @{ Id = 'PlayerSafeZoneHours'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'PlayerSafeZoneHours'; Label = 'Player Safe Zone Hours'; DefaultValue = '5'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Hours in world time this safe zone exists' }
                    @{ Id = 'MaxSpawnedZombies'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'MaxSpawnedZombies'; Label = 'Max Spawned Zombies'; DefaultValue = '64'; Min = 0; Max = 10000; Decimals = 0; Hint = 'This setting covers the entire map. There can only be this many zombies on the entire map at one time. Changing this setting has a huge impact on performance.' }
                    @{ Id = 'MaxSpawnedAnimals'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'MaxSpawnedAnimals'; Label = 'Max Spawned Animals'; DefaultValue = '50'; Min = 0; Max = 10000; Decimals = 0; Hint = 'If your server has a large number of players you can increase this limit to add more wildlife. Animals don''t consume as much CPU as zombies. NOTE: That this doesn''t cause more animals to spawn arbitrarily: The biome spawning system only spawns a certain number of animals in a given area, but if you have lots of players that are all spread out then you may be hitting the limit and can increase it.' }
                    @{ Id = 'ServerMaxAllowedViewDistance'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ServerMaxAllowedViewDistance'; Label = 'Server Max Allowed View Distance'; DefaultValue = '12'; Min = 6; Max = 12; Decimals = 0; Hint = 'Max view distance a client may request (6 - 12). High impact on memory usage and performance.' }
                    @{ Id = 'MaxQueuedMeshLayers'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'MaxQueuedMeshLayers'; Label = 'Max Queued Mesh Layers'; DefaultValue = '1000'; Min = 0; Max = 100000; Decimals = 0; Hint = 'Maximum amount of Chunk mesh layers that can be enqueued during mesh generation. Reducing this will improve memory usage but may increase Chunk generation time' }
                    @{ Id = 'PartySharedKillRange'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'PartySharedKillRange'; Label = 'Party Shared Kill Range'; DefaultValue = '100'; Min = 0; Max = 10000; Decimals = 0; Hint = 'The distance you must be within to receive party shared kill XP and quest party kill objective credit.' }
                    @{ Id = 'PlayerKillingMode'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'PlayerKillingMode'; Label = 'Player Killing Mode'; DefaultValue = '3'; Min = 0; Max = 3; Decimals = 0; Hint = 'Player Killing Settings (0 = No Killing, 1 = Kill Allies Only, 2 = Kill Strangers Only, 3 = Kill Everyone)' }
                )
            }

            [pscustomobject]@{
                Title       = 'Zombies / Blood Moon'
                Description = 'Enemy spawning, zombie speeds, feral sense, blood moon timing, and horde size.'
                Fields      = @(
                    @{ Id = 'EnemySpawnMode'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'EnemySpawnMode'; Label = 'Enemy Spawn Mode'; DefaultValue = 'true'; Hint = 'Enable/Disable enemy spawning' }
                    @{ Id = 'EnemyDifficulty'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'EnemyDifficulty'; Label = 'Enemy Difficulty'; DefaultValue = '0'; Min = 0; Max = 1; Decimals = 0; Hint = '0 = Normal, 1 = Feral' }
                    @{ Id = 'ZombieFeralSense'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ZombieFeralSense'; Label = 'Zombie Feral Sense'; DefaultValue = '0'; Min = 0; Max = 3; Decimals = 0; Hint = '0-3 (Off, Day, Night, All)' }
                    @{ Id = 'ZombieMove'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ZombieMove'; Label = 'Zombie Move'; DefaultValue = '0'; Min = 0; Max = 4; Decimals = 0; Hint = '0-4 (walk, jog, run, sprint, nightmare)' }
                    @{ Id = 'ZombieMoveNight'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ZombieMoveNight'; Label = 'Zombie Move Night'; DefaultValue = '3'; Min = 0; Max = 4; Decimals = 0; Hint = '0-4 (walk, jog, run, sprint, nightmare)' }
                    @{ Id = 'ZombieFeralMove'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ZombieFeralMove'; Label = 'Zombie Feral Move'; DefaultValue = '3'; Min = 0; Max = 4; Decimals = 0; Hint = '0-4 (walk, jog, run, sprint, nightmare)' }
                    @{ Id = 'ZombieBMMove'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'ZombieBMMove'; Label = 'Zombie BM Move'; DefaultValue = '3'; Min = 0; Max = 4; Decimals = 0; Hint = '0-4 (walk, jog, run, sprint, nightmare)' }
                    @{ Id = 'AISmellMode'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'AISmellMode'; Label = 'A I Smell Mode'; DefaultValue = '3'; Min = 0; Max = 5; Decimals = 0; Hint = '0-5 (off, walk, jog, run, sprint, nightmare)' }
                    @{ Id = 'BloodMoonFrequency'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BloodMoonFrequency'; Label = 'Blood Moon Frequency'; DefaultValue = '7'; Min = 0; Max = 1000; Decimals = 0; Hint = 'What frequency (in days) should a blood moon take place. Set to "0" for no blood moons' }
                    @{ Id = 'BloodMoonRange'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BloodMoonRange'; Label = 'Blood Moon Range'; DefaultValue = '0'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How many days can the actual blood moon day randomly deviate from the above setting. Setting this to 0 makes blood moons happen exactly each Nth day as specified in BloodMoonFrequency' }
                    @{ Id = 'BloodMoonWarning'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BloodMoonWarning'; Label = 'Blood Moon Warning'; DefaultValue = '8'; Min = -1; Max = 23; Decimals = 0; Hint = 'The Hour number that the red day number begins on a blood moon day. Setting this to -1 makes the red never show.' }
                    @{ Id = 'BloodMoonEnemyCount'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'BloodMoonEnemyCount'; Label = 'Blood Moon Enemy Count'; DefaultValue = '8'; Min = 0; Max = 1000; Decimals = 0; Hint = 'This is the number of zombies that can be alive (spawned at the same time) at any time PER PLAYER during a blood moon horde, however, MaxSpawnedZombies overrides this number in multiplayer games. Also note that your game stage sets the max number of zombies PER PARTY. Low game stage values can result in lower number of zombies than the BloodMoonEnemyCount setting. Changing this setting has a huge impact on performance.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Loot / Airdrops'
                Description = 'Loot abundance, loot respawn, and airdrop behavior.'
                Fields      = @(
                    @{ Id = 'LootAbundance'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LootAbundance'; Label = 'Loot Abundance'; DefaultValue = '100'; Min = 0; Max = 1000; Decimals = 0; Hint = 'percentage in whole numbers' }
                    @{ Id = 'LootRespawnDays'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LootRespawnDays'; Label = 'Loot Respawn Days'; DefaultValue = '7'; Min = 0; Max = 1000; Decimals = 0; Hint = 'days in whole numbers' }
                    @{ Id = 'AirDropFrequency'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'AirDropFrequency'; Label = 'Air Drop Frequency'; DefaultValue = '72'; Min = 0; Max = 10000; Decimals = 0; Hint = 'How often airdrop occur in game-hours, 0 == never' }
                    @{ Id = 'AirDropMarker'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'AirDropMarker'; Label = 'Air Drop Marker'; DefaultValue = 'true'; Hint = 'Sets if a marker is added to map/compass for air drops.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Land Claim / Systems'
                Description = 'Land claim protection, dynamic mesh, Twitch permissions, and quest progression limits.'
                Fields      = @(
                    @{ Id = 'LandClaimCount'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimCount'; Label = 'Land Claim Count'; DefaultValue = '5'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Maximum allowed land claims per player.' }
                    @{ Id = 'LandClaimSize'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimSize'; Label = 'Land Claim Size'; DefaultValue = '41'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Size in blocks that is protected by a keystone' }
                    @{ Id = 'LandClaimDeadZone'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimDeadZone'; Label = 'Land Claim Dead Zone'; DefaultValue = '30'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Keystones must be this many blocks apart (unless you are friends with the other player)' }
                    @{ Id = 'LandClaimExpiryTime'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimExpiryTime'; Label = 'Land Claim Expiry Time'; DefaultValue = '7'; Min = 0; Max = 10000; Decimals = 0; Hint = 'The number of real world days a player can be offline before their claims expire and are no longer protected' }
                    @{ Id = 'LandClaimDecayMode'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimDecayMode'; Label = 'Land Claim Decay Mode'; DefaultValue = '0'; Min = 0; Max = 2; Decimals = 0; Hint = 'Controls how offline players land claims decay. 0=Slow (Linear) , 1=Fast (Exponential), 2=None (Full protection until claim is expired).' }
                    @{ Id = 'LandClaimOnlineDurabilityModifier'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimOnlineDurabilityModifier'; Label = 'Land Claim Online Durability Modifier'; DefaultValue = '4'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How much protected claim area block hardness is increased when a player is online. 0 means infinite (no damage will ever be taken). Default is 4x' }
                    @{ Id = 'LandClaimOfflineDurabilityModifier'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimOfflineDurabilityModifier'; Label = 'Land Claim Offline Durability Modifier'; DefaultValue = '4'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How much protected claim area block hardness is increased when a player is offline. 0 means infinite (no damage will ever be taken). Default is 4x' }
                    @{ Id = 'LandClaimOfflineDelay'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'LandClaimOfflineDelay'; Label = 'Land Claim Offline Delay'; DefaultValue = '0'; Min = 0; Max = 10000; Decimals = 0; Hint = 'The number of minutes after a player logs out that the land claim area hardness transitions from online to offline. Default is 0' }
                    @{ Id = 'DynamicMeshEnabled'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'DynamicMeshEnabled'; Label = 'Dynamic Mesh Enabled'; DefaultValue = 'true'; Hint = 'Is Dynamic Mesh system enabled' }
                    @{ Id = 'DynamicMeshLandClaimOnly'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'DynamicMeshLandClaimOnly'; Label = 'Dynamic Mesh Land Claim Only'; DefaultValue = 'true'; Hint = 'Is Dynamic Mesh system only active in player LCB areas' }
                    @{ Id = 'DynamicMeshLandClaimBuffer'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DynamicMeshLandClaimBuffer'; Label = 'Dynamic Mesh Land Claim Buffer'; DefaultValue = '3'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Dynamic Mesh LCB chunk radius' }
                    @{ Id = 'DynamicMeshMaxItemCache'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'DynamicMeshMaxItemCache'; Label = 'Dynamic Mesh Max Item Cache'; DefaultValue = '3'; Min = 0; Max = 1000; Decimals = 0; Hint = 'How many items can be processed concurrently, higher values use more RAM' }
                    @{ Id = 'TwitchServerPermission'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'TwitchServerPermission'; Label = 'Twitch Server Permission'; DefaultValue = '90'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Required permission level to use twitch integration on the server' }
                    @{ Id = 'TwitchBloodMoonAllowed'; Type = 'Boolean'; File = 'serverconfig.xml'; Key = 'TwitchBloodMoonAllowed'; Label = 'Twitch Blood Moon Allowed'; DefaultValue = 'false'; Hint = 'If the server allows twitch actions during a blood moon. This could cause server lag with extra zombies being spawned during blood moon.' }
                    @{ Id = 'QuestProgressionDailyLimit'; Type = 'Number'; File = 'serverconfig.xml'; Key = 'QuestProgressionDailyLimit'; Label = 'Quest Progression Daily Limit'; DefaultValue = '4'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Limits the number of quests that contribute to quest tier progression a player can complete each day. Quests after the limit can still be completed for rewards.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Advanced'
                Description = 'Manual access to the active 7 Days to Die profile config.'
                Fields      = @(
                    @{ Id = 'OpenServerConfigXml'; Type = 'ActionButton'; Label = 'serverconfig.xml'; ButtonText = 'Open serverconfig.xml'; Action = $actions.OpenPrimaryXml; Hint = 'Opens the profile serverconfig.xml for manual editing. UGSM preserves the XML comments/hints when saving setting values.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Discord'
                Description = 'UGSM per-server Discord override settings. Empty private webhook uses the global webhook; new private values are masked and stored in UGSM secrets, not in the instance JSON.'
                Fields      = @(
                    @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Secret = $true; Hint = 'Optional per-server webhook override. Leave blank to clear/use global. New values are hidden on screen and saved into the UGSM secrets store; instance JSON keeps safe metadata only.' }
                    @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                    @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                    @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $false; Hint = 'Marks this server as visible for Discord/dashboard status integrations.' }
                    @{ Id = 'DiscordTestWebhook'; Type = 'ActionButton'; Label = 'Test Discord Webhook'; ButtonText = 'Send Test Message'; Hint = 'Sends a test message using the saved per-server secret webhook if set, otherwise the global webhook.'; Action = {
                        param($Instance, $Paths, $StatusLabel)
                        try {
                            $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
                            if (-not $discordModel.HasWebhook) {
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook is configured for this server and no global webhook is available.' }
                                return
                            }
                            $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('7D2D ' + [string]$Instance.Name)
                            if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) {
                                $target = if ($discordModel.UsesGlobalWebhook) { 'global webhook' } else { 'server webhook' }
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully using the ' + $target + '.' }
                            }
                            else {
                                $errorText = if ($result -and $result.PSObject.Properties['Error']) { [string]$result.Error } else { 'Unknown Discord webhook error.' }
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $errorText }
                            }
                        }
                        catch {
                            if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message }
                        }
                    } }
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

        if ($title -eq 'Advanced') {
            $keptFields = @($tab.Fields | Where-Object {
                $fieldId = [string]$_.Id
                if ($fieldId -eq 'OpenPrimaryIni'  -and -not [bool]$features.IniFiles)  { return $false }
                if ($fieldId -eq 'OpenPrimaryJson' -and -not [bool]$features.JsonFiles) { return $false }
                if ($fieldId -eq 'OpenPrimaryXml'  -and -not [bool]$features.XmlFiles)  { return $false }
                if ($fieldId -eq 'OpenPrimaryCfg'  -and -not [bool]$features.CfgFiles)  { return $false }
                return $true
            })
            $tab = [pscustomobject]@{ Title = $tab.Title; Description = $tab.Description; Fields = $keptFields }
        }

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
        $modsDefinition = Get-UGSMGame7D2DModsDefinition
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
