# UGSM Game KillingFloor2
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace KillingFloor2 with the real game token
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

function Test-UGSMGameKillingFloor2VerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameKillingFloor2Logging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameKillingFloor2Logging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_KillingFloor2)) { return $true }
    return $false
}

function ConvertTo-UGSMGameKillingFloor2SafeLogText {
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
        # the KillingFloor2 itself does not add portability-scan false positives.
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
            @{ Names = @('UGSM_SteamRoot', 'UGSM_SteamCMDRoot', 'UGSM_SteamInstallRoot'); Token = '%UGSM_STEAM%' }
            @{ Names = @('UGSM_ProfileRoot', 'UGSM_ProfilesRoot', 'UGSM_ProfileStoreRoot'); Token = '%UGSM_PROFILES%' }
            @{ Names = @('UGSM_AppRoot', 'UGSM_Root', 'UGSM_SourceRoot'); Token = '%UGSM_ROOT%' }
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

function Write-UGSMGameKillingFloor2Log {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE', 'DEBUG')) -and -not (Test-UGSMGameKillingFloor2VerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameKillingFloor2SafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameKillingFloor2SafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:KillingFloor2' -Message $safeMessage
    }
}

function Write-UGSMGameKillingFloor2PathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older KillingFloor2 notes. New modules should use Write-UGSMGameKillingFloor2Log.
    Write-UGSMGameKillingFloor2Log -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGameKillingFloor2InstanceDiscordShape {
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


function Get-UGSMGameKillingFloor2SupportedFeatures {
    [CmdletBinding()]
    param()

    # ============================================================
    # KillingFloor2 SUPPORTED FEATURES
    # This is the first section to edit when copying the KillingFloor2.
    # Turn features on/off here, then edit the schema sections below.
    # Test builds show the KillingFloor2 as a real game so optional UI can be previewed.
    # ============================================================

    return [pscustomobject]@{
        Install                   = $true
        Update                    = $true
        Verify                    = $true
        Repair                    = $true
        Start                     = $true
        Stop                      = $true
        Profiles                  = $true
        InstanceUi                = $true
        Bootstrap                 = $true
        # Show this game in the catalog. Release/test/dev exclusion is handled by build scripts.
        IsVisible                 = $true
        Rcon                      = $false
        GracefulStop              = $false

        # Set Mods=$true to preview the shared Mods tab in test builds.
        # Copied games can keep this on/off switch and only change ModTabMode/capabilities.
        Mods                      = $false
        Workshop                  = $false
        ModTabMode                = 'SteamWorkshop' # SteamWorkshop, ArchiveImport, FrameworkPlugin, Mixed

        # Standard shared mod state storage. Game modules should keep mod references
        # in the instance JSON unless a game truly requires a different storage mode.
        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord                   = $true
        AdvancedFiles             = $true
        UserLists                 = $true

        IniFiles                  = $true
        JsonFiles                 = $false
        XmlFiles                  = $false
        CfgFiles                  = $false
        PropertiesFiles           = $false
        YamlFiles                 = $false
        TomlFiles                 = $false
        LuaFiles                  = $false
        TextFiles                 = $true
        PSSQLite                  = $false

        ModCapabilities           = [pscustomobject]@{
            # Standard Steam Workshop list/download/load-order tab.
            SteamWorkshop    = $true
            LoadOrder        = $true

            # ZIP/RAR/folder import tab pieces. Enable for games like 7 Days to Die.
            ArchiveImport    = $false
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

function Get-UGSMGameKillingFloor2ModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameKillingFloor2SupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'KillingFloor2' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
    }
    else {
        $mods = [pscustomobject]@{
            Supported                 = [bool]$features.Mods
            DisplayName               = 'Mods'
            Version                   = 2
            ModStateStorage           = 'InstanceJson'
            InstanceModsProperty      = 'Mods'
            InstanceModStatesProperty = 'ModStates'
            ModTabMode                = $(if ($features.PSObject.Properties['ModTabMode']) { [string]$features.ModTabMode } else { 'SteamWorkshop' })
            Capabilities              = [pscustomobject]@{
                SteamWorkshop = $false; ArchiveImport = $false; FolderImport = $false; FrameworkInstall = $false; PluginManager = $false; MapList = $false; ConfigMerge = $false; LoadOrder = $false; UrlDownload = $false; KeyCopy = $false; ServerSideCopy = $false; RuntimeSync = $false; BuildIndexCache = $false; OpenManifest = $true; RefreshSummary = $true
            }
            Archive                   = [pscustomobject]@{ AllowedExtensions = @('.zip', '.rar'); InstallFolderRelative = 'Mods'; RequireSafetyNotice = $true }
            Workshop                  = [pscustomobject]@{ IdField = 'WorkshopItemIds'; SupportsCollections = $true; ConfigStrategy = 'GameSpecific'; AppId = '232090'; WorkshopAppId = '232090'; LoginMode = 'Anonymous' }
            Framework                 = [pscustomobject]@{ Id = 'ExampleFramework'; Label = 'Example Framework'; OfficialSourceOnly = $true; RequiresConfirmation = $true }
            Paths                     = [pscustomobject]@{ ModsFolderRelative = 'Mods'; ManifestFileName = $null }
            StoragePolicy             = [pscustomobject]@{ Mode = 'InstanceJson'; KeepWorkshopModsShared = $true; CopyFullModsToProfile = $false; CopyOnlyRequiredFilesToProfile = $true; RuntimeMode = 'SharedWorkshopCache'; SummaryFileName = $null }
            UI                        = [pscustomobject]@{ InlineWorkshopInput = $true; ShowActiveLoadOrder = $true; ShowSafetyNotice = $true; ShowProfileLightNotice = $true }
            Safety                    = [pscustomobject]@{ ShowThirdPartyNotice = $true; RequireConfirmation = $true; NoticeKind = 'GenericMods' }
            Hooks                     = [pscustomobject]@{ Refresh = ''; Save = ''; Install = ''; Remove = ''; Validate = ''; BuildCustomTab = ''; AfterModsChanged = ''; AfterWorkshopDownload = '' }
            GameId                    = 'KillingFloor2'
        }
    }


    # Killing Floor 2 Workshop uses the client Workshop App ID. SteamCMD downloads
    # Workshop content into the normal shared Steam workshop cache for app 232090.
    foreach ($propName in @('WorkshopAppId', 'SteamWorkshopAppId')) {
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = '232090' }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value '232090' -Force }
    }

    if ($mods.PSObject.Properties['Workshop'] -and $mods.Workshop) {
        foreach ($propName in @('AppId', 'WorkshopAppId', 'SteamWorkshopAppId')) {
            if ($mods.Workshop.PSObject.Properties[$propName]) { $mods.Workshop.$propName = '232090' }
            else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name $propName -Value '232090' -Force }
        }
        if ($mods.Workshop.PSObject.Properties['ConfigStrategy']) { $mods.Workshop.ConfigStrategy = 'GameSpecific' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'ConfigStrategy' -Value 'GameSpecific' -Force }
        if ($mods.Workshop.PSObject.Properties['LoginMode']) { $mods.Workshop.LoginMode = 'Anonymous' }
        else { Add-Member -InputObject $mods.Workshop -MemberType NoteProperty -Name 'LoginMode' -Value 'Anonymous' -Force }
    }

    foreach ($propName in @('ModStateStorage', 'InstanceModsProperty', 'InstanceModStatesProperty')) {
        $value = switch ($propName) {
            'ModStateStorage' { 'InstanceJson' }
            'InstanceModsProperty' { 'Mods' }
            'InstanceModStatesProperty' { 'ModStates' }
        }
        if ($mods.PSObject.Properties[$propName]) { $mods.$propName = $value }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $propName -Value $value -Force }
    }

    foreach ($name in @('SteamWorkshop', 'ArchiveImport', 'FolderImport', 'FrameworkInstall', 'PluginManager', 'MapList', 'ConfigMerge', 'LoadOrder', 'UrlDownload', 'KeyCopy', 'ServerSideCopy', 'RuntimeSync', 'BuildIndexCache', 'OpenManifest', 'RefreshSummary')) {
        if ($mods.Capabilities.PSObject.Properties[$name] -and $features.ModCapabilities.PSObject.Properties[$name]) {
            $mods.Capabilities.$name = [bool]$features.ModCapabilities.$name
        }
    }

    if ($features.PSObject.Properties['ModTabMode']) {
        if ($mods.PSObject.Properties['ModTabMode']) { $mods.ModTabMode = [string]$features.ModTabMode }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name ModTabMode -Value ([string]$features.ModTabMode) -Force }
    }

    if ($mods.PSObject.Properties['StoragePolicy'] -and $mods.StoragePolicy) {
        $mods.StoragePolicy.KeepWorkshopModsShared = $true
        $mods.StoragePolicy.CopyFullModsToProfile = $false
        $mods.StoragePolicy.CopyOnlyRequiredFilesToProfile = $true
        $mods.StoragePolicy.RuntimeMode = 'SharedWorkshopCache'
    }

    if ($mods.PSObject.Properties['UI'] -and $mods.UI) {
        $mods.UI.InlineWorkshopInput = $true
        $mods.UI.ShowActiveLoadOrder = $true
        $mods.UI.ShowSafetyNotice = $true
        $mods.UI.ShowProfileLightNotice = $true
    }

    if ($mods.PSObject.Properties['Safety'] -and $mods.Safety) {
        $mods.Safety.ShowThirdPartyNotice = [bool]$features.Mods
        $mods.Safety.RequireConfirmation = [bool]($features.ModCapabilities.FrameworkInstall -or $features.ModCapabilities.UrlDownload)
    }


    if ($mods.PSObject.Properties['Hooks'] -and $mods.Hooks) {
        if ($mods.Hooks.PSObject.Properties['AfterModsChanged']) { $mods.Hooks.AfterModsChanged = 'Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni' }
        else { Add-Member -InputObject $mods.Hooks -MemberType NoteProperty -Name 'AfterModsChanged' -Value 'Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni' -Force }

        if ($mods.Hooks.PSObject.Properties['AfterWorkshopDownload']) { $mods.Hooks.AfterWorkshopDownload = 'Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni' }
        else { Add-Member -InputObject $mods.Hooks -MemberType NoteProperty -Name 'AfterWorkshopDownload' -Value 'Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni' -Force }
    }

    return $mods
}

function Get-UGSMGameKillingFloor2Metadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = Join-Path (Join-Path 'Binaries' 'Win64') 'KFServer.exe'
    $features = Get-UGSMGameKillingFloor2SupportedFeatures
    $modsDefinition = Get-UGSMGameKillingFloor2ModsDefinition

    return [pscustomobject]@{
        Id                       = 'KillingFloor2'
        Name                     = 'KillingFloor2'
        Category                 = 'Shooter'
        Description              = 'Killing Floor 2 dedicated server.'
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
        SteamAppId               = '232130'
        SteamStoreAppId          = '232090'
        ServerExecutable         = 'KFServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'KFGame\Config'
        SaveRootRelative         = 'KFGame\SaveData'
        LogRootRelative          = 'KFGame\Logs'

        #RequiredFiles            = @('Binaries\Win64\KFServer.exe', 'KFGame\Config')

        RequiredFiles            = @(
            $serverExeRelativePath
            'KFGame\Config'
        )

        #InstallMarkers           = @('Binaries\Win64', 'KFGame\Config')

        InstallMarkers           = @(
            $serverExeRelativePath
        )

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 7777 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'SteamPort'; Protocol = 'UDP'; PreferredStart = 20560 }
            @{ Name = 'WebAdminPort'; Protocol = 'TCP'; PreferredStart = 8080 }
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
                'KillingFloor2 module is shown only in test builds and excluded from release builds.',
                'Replace metadata, install validation, runtime layout, launch arguments, and schema values when creating a real game module.',
                'SteamCMD is the default install/update/verify pattern in the KillingFloor2.',
                'Steam login defaults to anonymous. Only add username/password handling when the target game truly requires it.',
                'Mods are driven by Get-UGSMGameKillingFloor2ModsDefinition and shared helper functions.',
                'Do not add profile sync or copy-back behavior to new game modules.'
            )
        }
    }
}

function Get-UGSMGameKillingFloor2InstallDefinition {
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
            try {
                $settings = Get-UGSMGlobalSettings -CreateIfMissing
            }
            catch {
                $settings = $null
            }
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
            throw 'KillingFloor2 install definition failed: InstallPath could not be resolved.'
        }

        $InstallPath = Join-Path $steamRoot 'steamapps\common\KillingFloor2'
    }

    $meta = Get-UGSMGameKillingFloor2Metadata

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = Join-Path $InstallPath $meta.ServerExecutableRelative
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = Join-Path $InstallPath $meta.ConfigRootRelative
        SaveRootPath         = Join-Path $InstallPath $meta.SaveRootRelative
        LogRootPath          = Join-Path $InstallPath $meta.LogRootRelative
    }
}

function Get-UGSMGameKillingFloor2AppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameKillingFloor2ProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'KillingFloor2' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameKillingFloor2AppDataRoot) 'Profiles')
}

function Get-UGSMGameKillingFloor2KillingFloor2Root {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameKillingFloor2AppDataRoot) 'KillingFloor2s\KillingFloor2')
}

function Get-UGSMGameKillingFloor2ProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameKillingFloor2ProfileBaseRoot) 'KillingFloor2') $ProfileName)
}


function Get-UGSMGameKillingFloor2RuntimeRoot {
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
            $profileRoot = Get-UGSMGameKillingFloor2ProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'KillingFloor2 runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameKillingFloor2Path {
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

function New-UGSMGameKillingFloor2DirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "KillingFloor2 junction target was not found: $TargetPath"
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

        Remove-UGSMGameKillingFloor2Path -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "KillingFloor2 junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameKillingFloor2FilesToRuntime {
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

    Copy-UGSMGameKillingFloor2DirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameKillingFloor2RuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameKillingFloor2RuntimeRoot -Instance $Instance
    $runtimeInstallRoot = $runtimeRoot
    $runtimeGameRoot = Join-Path $runtimeRoot 'KFGame' # Make sure this matches KFGame structure
    $runtimeSavedRoot = Join-Path $runtimeRoot 'KFGame\SaveData' # Or appropriate saved path

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeGameRoot       = $runtimeGameRoot
        RuntimeSavedRoot      = $runtimeSavedRoot
        RuntimeConfigRootPath = Join-Path $InstallPath 'KFGame\Config'
        RuntimeSaveRootPath   = Join-Path $runtimeRoot 'KFGame\SaveData'
        RuntimeLogRootPath    = Join-Path $runtimeRoot 'KFGame\Logs'
        RuntimeServerExePath  = Join-Path $InstallPath 'Binaries\Win64\KFServer.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = Join-Path ([string]$InstallDefinition.InstallPath) 'KFGame'
    }
}

function Resolve-UGSMGameKillingFloor2DatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance

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

function Ensure-UGSMGameKillingFloor2RuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameKillingFloor2RuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition
    $sharedInstallRoot = [string]$InstallDefinition.InstallPath
    $sharedGameRoot = Join-Path $sharedInstallRoot 'KillingFloor2'

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeInstallRoot, $runtime.RuntimeGameRoot, $runtime.RuntimeSavedRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $sharedInstallRoot -PathType Container) {
        foreach ($child in @(Get-ChildItem -LiteralPath $sharedInstallRoot -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtime.RuntimeInstallRoot $child.Name

            if ($child.PSIsContainer -and $child.Name -ieq 'KillingFloor2') {
                continue
            }

            if ($child.PSIsContainer) {
                New-UGSMGameKillingFloor2DirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
            }
            else {
                Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $sharedGameRoot -PathType Container)) {
        throw "KillingFloor2 runtime layout failed: Shared KillingFloor2 root was not found: $sharedGameRoot"
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $sharedGameRoot -Force -ErrorAction SilentlyContinue)) {
        $targetPath = Join-Path $runtime.RuntimeGameRoot $child.Name

        if ($child.PSIsContainer -and $child.Name -ieq 'Saved') {
            continue
        }

        if ($child.PSIsContainer) {
            New-UGSMGameKillingFloor2DirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $runtime
}

function Initialize-UGSMGameKillingFloor2RuntimeData {
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
        Copy-UGSMGameKillingFloor2FilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameKillingFloor2FilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameKillingFloor2DirectoryContent {
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

function Get-UGSMGameKillingFloor2RunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'KFServer.exe'" -ErrorAction Stop)
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

function Start-UGSMGameKillingFloor2BootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "KillingFloor2 server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'KillingFloor2DedicatedServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM KillingFloor2Server.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'KillingFloor2DedicatedServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'KillingFloor2DedicatedServer' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameKillingFloor2Template {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameKillingFloor2Install -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "Killing Floor 2 install is not valid at '$InstallPath'."
    }

    $sourceConfigRoot = [string]$definition.ConfigRootPath
    $missingConfigs = @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini') | Where-Object { 
        -not (Test-Path -LiteralPath (Join-Path $sourceConfigRoot $_) -PathType Leaf) 
    }

    $bootstrapResult = $null

    if ($missingConfigs.Count -gt 0 -or $ForceRefresh) {
    $workingDir = $definition.InstallPath

    Start-Sleep -Seconds 5

    $bootstrapResult = Start-UGSMGameKillingFloor2BootstrapProcess `
        -ServerExecutablePath $definition.ServerExecutablePath `
        -WorkingDirectory $workingDir `
        -BootstrapSeconds $BootstrapSeconds | Out-Null

    if ($bootstrapResult -and $bootstrapResult.PSObject.Properties['Exited'] -and -not [bool]$bootstrapResult.Exited) {
        throw ('Killing Floor 2 bootstrap server did not shut down cleanly. Remaining PIDs: {0}' -f (($bootstrapResult.RemainingPids -join ', ')))
    }
}

    foreach ($fileName in @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini')) {
        $path = Join-Path $sourceConfigRoot $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Killing Floor 2 config file was not found. Missing: $path"
        }
    }

    return [pscustomobject]@{
        GameId               = 'KillingFloor2'
        InstallPath          = $InstallPath
        SourceConfigRoot     = $sourceConfigRoot
        GeneratedConfigFiles = @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini')
    }
}


function Initialize-UGSMGameKillingFloor2Profile {
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByInstance')]
        [object]$Instance,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ProfileName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$InstallPath,

        [switch]$Force,

        [int]$BootstrapSeconds = 15
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
        throw 'ProfileName could not be resolved for Killing Floor 2 profile initialization.'
    }
    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        $installDefinition = Get-UGSMGameKillingFloor2InstallDefinition
        $effectiveInstallPath = [string]$installDefinition.InstallPath
    }

    $definition = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $effectiveInstallPath
    $sourceConfigRoot = [string]$definition.ConfigRootPath




    
    # Check if source configs exist; if not, invoke the template builder (bootstrap) like SCUM does
    $missingConfigs = @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini') | Where-Object { 
        -not (Test-Path -LiteralPath (Join-Path $sourceConfigRoot $_) -PathType Leaf) 
    }

    if ($missingConfigs.Count -gt 0) {
        Write-Host "Killing Floor 2 base configs missing. Running initial bootstrap to generate INI files..."
        Ensure-UGSMGameKillingFloor2Template -InstallPath $effectiveInstallPath -BootstrapSeconds $BootstrapSeconds | Out-Null
    }

    # Proceed with profile root creation and file copying...
    $profileRoot = Get-UGSMGameKillingFloor2ProfileRoot -ProfileName $effectiveProfileName





    foreach ($fileName in @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini')) {
        $sourcePath = Join-Path $sourceConfigRoot $fileName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Killing Floor 2 profile initialization failed. Missing source config: $sourcePath"
        }
    }

    $profileRoot = Get-UGSMGameKillingFloor2ProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    $profileConfigRoot = Join-Path $profileRoot 'Config'
    New-Item -ItemType Directory -Path $profileConfigRoot -Force | Out-Null

    $copied = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini')) {
        $sourcePath = Join-Path $sourceConfigRoot $fileName
        $targetPath = Join-Path $profileConfigRoot $fileName
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
            [void]$copied.Add((Join-Path 'Config' $fileName))
        }
    }

    $gameIni = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
    if (Test-Path -LiteralPath $gameIni -PathType Leaf) {
        try {
            Set-UGSMGameKillingFloor2IniValue -Path $gameIni -Section 'Engine.GameReplicationInfo' -Key 'ServerName' -Value $effectiveProfileName
        }
        catch { }
    }

    return [pscustomobject]@{
        GameId      = 'KillingFloor2'
        InstanceId  = $instanceId
        ProfileName = $effectiveProfileName
        InstallPath = $effectiveInstallPath
        ProfileRoot = $profileRoot
        ConfigRoot  = $profileConfigRoot
        Initialized = $true
        CopiedFiles = @($copied.ToArray())
    }
}

function Test-UGSMGameKillingFloor2Install {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'KillingFloor2 validation failed: InstallPath could not be resolved.'
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
        GameId                 = 'KillingFloor2'
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


function Set-UGSMGameKillingFloor2InstanceField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ($Instance.PSObject.Properties[$Name]) {
        $Instance.$Name = $Value
    }
    else {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Get-UGSMGameKillingFloor2ServerNameFromConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    try {
        $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
        $iniData = Read-UGSMGameKillingFloor2IniFile -Path ([string]$paths.PCServerKFGamePath)
        $serverName = [string](Get-UGSMGameKillingFloor2IniValue -IniData $iniData -Section 'Engine.GameReplicationInfo' -Key 'ServerName' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($serverName)) {
            $serverName = [string](Get-UGSMGameKillingFloor2IniValue -IniData $iniData -Section 'Engine.GameReplicationInfo' -Key 'ShortName' -DefaultValue '')
        }
        if (-not [string]::IsNullOrWhiteSpace($serverName)) { return $serverName.Trim() }
    }
    catch { }

    if ($Instance.PSObject.Properties['Name']) { return [string]$Instance.Name }
    return 'Killing Floor 2 Server'
}

function Sync-UGSMGameKillingFloor2InstanceDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $serverName = Get-UGSMGameKillingFloor2ServerNameFromConfig -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($serverName)) { return $Instance }

    foreach ($fieldName in @('ServerName', 'PublicServerName', 'DisplayName', 'InstanceServerName', 'ServerDisplayName')) {
        Set-UGSMGameKillingFloor2InstanceField -Instance $Instance -Name $fieldName -Value ([string]$serverName)
    }

    return $Instance
}

function Get-UGSMGameKillingFloor2MaxPlayersFromConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    try {
        $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
        $iniData = Read-UGSMGameKillingFloor2IniFile -Path ([string]$paths.PCServerKFGamePath)
        $gameMode = [string](Get-UGSMGameKillingFloor2IniValue -IniData $iniData -Section 'Engine.GameInfo' -Key 'DefaultGame' -DefaultValue 'KFGameContent.KFGameInfo_Survival')

        $modeSection = switch -Regex ($gameMode) {
            'WeeklySurvival' { 'KFGameContent.KFGameInfo_WeeklySurvival'; break }
            'VersusSurvival' { 'KFGameContent.KFGameInfo_VersusSurvival'; break }
            'Endless' { 'KFGameContent.KFGameInfo_Endless'; break }
            'Objective' { 'KFGameContent.KFGameInfo_Objective'; break }
            default { 'KFGameContent.KFGameInfo_Survival' }
        }

        $maxText = [string](Get-UGSMGameKillingFloor2IniValue -IniData $iniData -Section $modeSection -Key 'MaxPlayers' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($maxText)) {
            $maxText = [string](Get-UGSMGameKillingFloor2IniValue -IniData $iniData -Section 'Engine.GameInfo' -Key 'MaxPlayers' -DefaultValue '')
        }

        $maxPlayers = 0
        if (-not [string]::IsNullOrWhiteSpace($maxText) -and [int]::TryParse($maxText, [ref]$maxPlayers) -and $maxPlayers -gt 0) {
            return [int]$maxPlayers
        }
    }
    catch { }

    return $null
}

function Set-UGSMGameKillingFloor2RuntimePlayerCountFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$CurrentPlayers,
        [AllowNull()][Nullable[int]]$MaxPlayers,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Status,
        [AllowNull()][string]$Detail
    )

    if ($CurrentPlayers -lt 0) { $CurrentPlayers = 0 }

    $pairs = @(
        @{ Name = 'CurrentPlayers'; Value = [int]$CurrentPlayers },
        @{ Name = 'PlayerCount'; Value = [int]$CurrentPlayers },
        @{ Name = 'OnlinePlayers'; Value = [int]$CurrentPlayers },
        @{ Name = 'PlayersOnline'; Value = [int]$CurrentPlayers },
        @{ Name = 'InstancePlayerCount'; Value = [int]$CurrentPlayers },
        @{ Name = 'PlayerCountSource'; Value = [string]$Source },
        @{ Name = 'InstancePlayerCountSource'; Value = [string]$Source },
        @{ Name = 'PlayerCountStatus'; Value = [string]$Status },
        @{ Name = 'InstancePlayerCountError'; Value = $(if ([string]::Equals([string]$Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) { '' } else { [string]$Status }) },
        @{ Name = 'PlayerCountUpdatedUtc'; Value = [DateTime]::UtcNow.ToString('o') },
        @{ Name = 'InstancePlayerCountUpdated'; Value = [DateTime]::UtcNow.ToString('o') }
    )

    if ($null -ne $MaxPlayers -and [int]$MaxPlayers -ge 0) {
        $pairs += @(
            @{ Name = 'MaxPlayers'; Value = [int]$MaxPlayers },
            @{ Name = 'ServerMaxPlayers'; Value = [int]$MaxPlayers },
            @{ Name = 'InstancePlayerMax'; Value = [int]$MaxPlayers }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Detail)) {
        $pairs += @{ Name = 'PlayerCountDetail'; Value = [string]$Detail }
    }

    foreach ($pair in $pairs) {
        Set-UGSMGameKillingFloor2InstanceField -Instance $Instance -Name ([string]$pair.Name) -Value $pair.Value
    }
}

function Get-UGSMGameKillingFloor2LogCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($paths.PSObject.Properties['ServerConsoleLogPath'] -and -not [string]::IsNullOrWhiteSpace([string]$paths.ServerConsoleLogPath)) {
        [void]$candidates.Add([string]$paths.ServerConsoleLogPath)
    }

    try {
        $installDef = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
        if ($installDef -and -not [string]::IsNullOrWhiteSpace([string]$installDef.LogRootPath)) {
            foreach ($name in @('Launch.log', 'KFGame.log', 'KillingFloor2.log')) {
                [void]$candidates.Add((Join-Path ([string]$installDef.LogRootPath) $name))
            }
            if (Test-Path -LiteralPath ([string]$installDef.LogRootPath) -PathType Container) {
                foreach ($logFile in @(Get-ChildItem -LiteralPath ([string]$installDef.LogRootPath) -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)) {
                    [void]$candidates.Add([string]$logFile.FullName)
                }
            }
        }
    }
    catch { }

    return @($candidates.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
}

function Get-UGSMGameKillingFloor2CurrentPlayerCountFromLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$MaxLines = 4000
    )

    $maxPlayers = Get-UGSMGameKillingFloor2MaxPlayersFromConfig -Instance $Instance
    $logPath = $null

    foreach ($candidate in @(Get-UGSMGameKillingFloor2LogCandidates -Instance $Instance)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $logPath = [string]$candidate
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'NoLog'
            CurrentPlayers = 0
            MaxPlayers     = $maxPlayers
            Source         = 'KF2_LOG_SERVER_DATA'
            Detail         = 'No KF2 server log was found yet.'
        }
    }

    try {
        $lines = @(Get-Content -LiteralPath $logPath -Tail $MaxLines -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'ReadFailed'
            CurrentPlayers = 0
            MaxPlayers     = $maxPlayers
            Source         = 'KF2_LOG_SERVER_DATA'
            Detail         = 'KF2 server log could not be read.'
        }
    }

    $currentPlayers = $null
    $foundMax = $null
    $lastMatch = ''

    foreach ($lineObj in $lines) {
        $line = [string]$lineObj

        if ($line -match 'Server data:.*?Slots:\s*(?<slots>\d+).*?Players:\s*(?<players>\d+)') {
            $foundMax = [int]$Matches['slots']
            $currentPlayers = [int]$Matches['players']
            $lastMatch = 'Server data'
            continue
        }

        if ($line -match 'Advertising:\s+NumPublicConnections=(?<slots>\d+)') {
            $foundMax = [int]$Matches['slots']
            $lastMatch = 'NumPublicConnections'
            continue
        }

        if ($line -match 'Advertising:\s+NumOpenPublicConnections=(?<open>\d+)') {
            $openSlots = [int]$Matches['open']
            if ($null -ne $foundMax -and $foundMax -ge $openSlots) {
                $currentPlayers = [int]($foundMax - $openSlots)
                $lastMatch = 'NumOpenPublicConnections'
            }
            continue
        }
    }

    if ($null -eq $currentPlayers) {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'NoPlayerLine'
            CurrentPlayers = 0
            MaxPlayers     = $(if ($null -ne $foundMax) { [int]$foundMax } else { $maxPlayers })
            Source         = 'KF2_LOG_SERVER_DATA'
            Detail         = (Split-Path -Leaf $logPath)
        }
    }

    if ($null -ne $foundMax) { $maxPlayers = [int]$foundMax }

    return [pscustomobject]@{
        Success        = $true
        Status         = 'OK'
        CurrentPlayers = [int]$currentPlayers
        MaxPlayers     = $maxPlayers
        Source         = 'KF2_LOG_SERVER_DATA'
        Detail         = ((Split-Path -Leaf $logPath) + ' / ' + $lastMatch)
    }
}

function Update-UGSMGameKillingFloor2DiscordRuntimeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (-not $Instance) { return $Instance }

    try {
        $Instance = Sync-UGSMGameKillingFloor2InstanceDisplayName -Instance $Instance
        $maxPlayers = Get-UGSMGameKillingFloor2MaxPlayersFromConfig -Instance $Instance

        $statusText = ''
        if ($Instance.PSObject.Properties['Status']) { $statusText = [string]$Instance.Status }

        if ($statusText.Trim().ToLowerInvariant() -notin @('running', 'online', 'started')) {
            Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'KF2_LOG_SERVER_DATA' -Status 'Stopped' -Detail ''
            Save-UGSMGameKillingFloor2InstanceDefinition -Instance $Instance | Out-Null
            return $Instance
        }

        $result = Get-UGSMGameKillingFloor2CurrentPlayerCountFromLog -Instance $Instance
        if ($result -and [bool]$result.Success) {
            if ($null -ne $result.MaxPlayers -and [int]$result.MaxPlayers -ge 0) { $maxPlayers = [int]$result.MaxPlayers }
            Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $Instance -CurrentPlayers ([int]$result.CurrentPlayers) -MaxPlayers $maxPlayers -Source ([string]$result.Source) -Status ([string]$result.Status) -Detail ([string]$result.Detail)
        }
        else {
            $status = if ($result) { [string]$result.Status } else { 'NoResult' }
            $detail = if ($result) { [string]$result.Detail } else { 'KF2 player-count resolver returned no result.' }
            Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'KF2_LOG_SERVER_DATA' -Status $status -Detail $detail
        }

        Save-UGSMGameKillingFloor2InstanceDefinition -Instance $Instance | Out-Null
    }
    catch {
        try {
            Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $null -Source 'KF2_LOG_SERVER_DATA' -Status 'Error' -Detail $_.Exception.Message
            Save-UGSMGameKillingFloor2InstanceDefinition -Instance $Instance | Out-Null
        }
        catch { }
    }

    return $Instance
}

function Start-UGSMGameKillingFloor2Instance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) { throw 'Killing Floor 2 start failed: Instance was null.' }

    $validation = Test-UGSMGameKillingFloor2Install -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'Killing Floor 2 start failed: Killing Floor 2 is not installed or KFServer.exe is missing.'
    }

    $installDef = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance

    if (-not (Test-Path -LiteralPath $paths.ProfileConfigRoot -PathType Container)) {
        throw "Killing Floor 2 start failed: profile config folder was not found: $($paths.ProfileConfigRoot)"
    }

    if ($paths.PSObject.Properties['ProfileLogRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$paths.ProfileLogRoot) -and -not (Test-Path -LiteralPath ([string]$paths.ProfileLogRoot) -PathType Container)) {
        New-Item -ItemType Directory -Path ([string]$paths.ProfileLogRoot) -Force | Out-Null
    }

    try {
        $modsDefinitionForStart = Get-UGSMGameKillingFloor2ModsDefinition
        $modsManifestForStart = $null
        if (Get-Command -Name Read-UGSMModsManifest -ErrorAction SilentlyContinue) {
            $modsManifestForStart = Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefinitionForStart
        }
        Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni -Instance $Instance -Manifest $modsManifestForStart -ModsDefinition $modsDefinitionForStart | Out-Null
    }
    catch {
        Write-UGSMLog -Level 'WARN' -Category 'KillingFloor2' -Message ('Failed to sync Killing Floor 2 Workshop list before start: ' + $_.Exception.Message)
    }

    $installConfigRoot = [string]$installDef.ConfigRootPath
    foreach ($fileName in @('PCServer-KFGame.ini', 'PCServer-KFEngine.ini', 'KFWeb.ini')) {
        $sourcePath = Join-Path $paths.ProfileConfigRoot $fileName
        $targetPath = Join-Path $installConfigRoot $fileName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Killing Floor 2 start failed: profile config file was not found: $sourcePath"
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }

    $serverExe = [string]$installDef.ServerExecutablePath
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "Killing Floor 2 start failed: KFServer.exe was not found: $serverExe"
    }

    $gameIniData = Read-UGSMGameKillingFloor2IniFile -Path $paths.PCServerKFGamePath
    $engineIniData = Read-UGSMGameKillingFloor2IniFile -Path $paths.PCServerKFEnginePath

    $mapName = [string](Get-UGSMGameKillingFloor2IniValue -IniData $engineIniData -Section 'URL' -Key 'ServerLocalMap' -DefaultValue 'KF-BioticsLab')
    if ([string]::IsNullOrWhiteSpace($mapName)) { $mapName = 'KF-BioticsLab' }
    if ($Instance.PSObject.Properties['StartMap'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.StartMap)) {
        $mapName = [string]$Instance.StartMap
    }

    $gameMode = [string](Get-UGSMGameKillingFloor2IniValue -IniData $gameIniData -Section 'Engine.GameInfo' -Key 'DefaultGame' -DefaultValue 'KFGameContent.KFGameInfo_Survival')
    if ([string]::IsNullOrWhiteSpace($gameMode)) { $gameMode = 'KFGameContent.KFGameInfo_Survival' }
    if ($Instance.PSObject.Properties['GameModeClass'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.GameModeClass)) {
        $gameMode = [string]$Instance.GameModeClass
    }

    $gamePort = 7777
    $queryPort = 27015
    $steamPort = 20560
    $peerPort = 7778

    try {
        $iniGamePort = [string](Get-UGSMGameKillingFloor2IniValue -IniData $engineIniData -Section 'URL' -Key 'Port' -DefaultValue '7777')
        $parsedGamePort = 0
        if (-not [string]::IsNullOrWhiteSpace($iniGamePort) -and [int]::TryParse($iniGamePort, [ref]$parsedGamePort)) { $gamePort = $parsedGamePort }
    }
    catch { $gamePort = 7777 }

    try {
        $iniPeerPort = [string](Get-UGSMGameKillingFloor2IniValue -IniData $engineIniData -Section 'URL' -Key 'PeerPort' -DefaultValue '7778')
        $parsedPeerPort = 0
        if (-not [string]::IsNullOrWhiteSpace($iniPeerPort) -and [int]::TryParse($iniPeerPort, [ref]$parsedPeerPort)) { $peerPort = $parsedPeerPort }
    }
    catch { $peerPort = 7778 }

    try {
        $iniQueryPort = [string](Get-UGSMGameKillingFloor2IniValue -IniData $engineIniData -Section 'URL' -Key 'QueryPort' -DefaultValue '27015')
        $parsedQueryPort = 0
        if (-not [string]::IsNullOrWhiteSpace($iniQueryPort) -and [int]::TryParse($iniQueryPort, [ref]$parsedQueryPort)) { $queryPort = $parsedQueryPort }
    }
    catch { $queryPort = 27015 }

    try {
        $iniSteamPort = [string](Get-UGSMGameKillingFloor2IniValue -IniData $engineIniData -Section 'URL' -Key 'SteamPort' -DefaultValue '20560')
        $parsedSteamPort = 0
        if (-not [string]::IsNullOrWhiteSpace($iniSteamPort) -and [int]::TryParse($iniSteamPort, [ref]$parsedSteamPort)) { $steamPort = $parsedSteamPort }
    }
    catch { $steamPort = 20560 }

    try {
        if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports) {
            if ($Instance.Ports.PSObject.Properties['GamePort']) { $gamePort = [int]$Instance.Ports.GamePort }
            if ($Instance.Ports.PSObject.Properties['QueryPort']) { $queryPort = [int]$Instance.Ports.QueryPort }
            if ($Instance.Ports.PSObject.Properties['SteamPort']) { $steamPort = [int]$Instance.Ports.SteamPort }
        }
    }
    catch { }

    if ($gamePort -lt 1 -or $gamePort -gt 65535) { $gamePort = 7777 }
    if ($queryPort -lt 1 -or $queryPort -gt 65535) { $queryPort = 27015 }
    if ($steamPort -lt 1 -or $steamPort -gt 65535) { $steamPort = 20560 }
    if ($peerPort -lt 1 -or $peerPort -gt 65535) { $peerPort = ($gamePort + 1) }
    if ($peerPort -gt 65535) { $peerPort = 7778 }

    $launchOptions = @(
        ('game={0}' -f $gameMode),
        ('Port={0}' -f $gamePort),
        ('PeerPort={0}' -f $peerPort),
        ('QueryPort={0}' -f $queryPort),
        ('SteamPort={0}' -f $steamPort)
    )
    $launchUrl = ('{0}?{1}' -f $mapName, ($launchOptions -join '?'))
    $logArgument = $null
    if ($paths.PSObject.Properties['ServerConsoleLogPath'] -and -not [string]::IsNullOrWhiteSpace([string]$paths.ServerConsoleLogPath)) {
        try { if (Test-Path -LiteralPath ([string]$paths.ServerConsoleLogPath) -PathType Leaf) { Remove-Item -LiteralPath ([string]$paths.ServerConsoleLogPath) -Force -ErrorAction SilentlyContinue } } catch { }
        $logArgument = ('-abslog={0}' -f [string]$paths.ServerConsoleLogPath)
    }

    $arguments = @($launchUrl, '-log')
    if (-not [string]::IsNullOrWhiteSpace($logArgument)) { $arguments += $logArgument }

    $workingDirectory = Split-Path -Parent $serverExe
    $proc = Start-Process -FilePath $serverExe -ArgumentList $arguments -WorkingDirectory $workingDirectory -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'Killing Floor 2 start failed: Start-Process did not return a valid process.'
    }

    $gamePid = [int]$proc.Id
    $Instance = Sync-UGSMGameKillingFloor2InstanceDisplayName -Instance $Instance
    Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers (Get-UGSMGameKillingFloor2MaxPlayersFromConfig -Instance $Instance) -Source 'KF2_LOG_SERVER_DATA' -Status 'Starting' -Detail ''
    if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $gamePid }
    if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Running' }
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $Instance.ProfilePath = [string]$paths.ProfileRoot
    }

    try { [void](Save-UGSMGameKillingFloor2InstanceDefinition -Instance $Instance) } catch { }

    return [pscustomobject]@{
        Success           = $true
        ProcessId         = $gamePid
        ExecutablePath    = $serverExe
        WorkingDirectory  = $workingDirectory
        Arguments         = $arguments
        ProfileConfigRoot = [string]$paths.ProfileConfigRoot
        InstallConfigRoot = $installConfigRoot
    }
}

function Stop-UGSMGameKillingFloor2Instance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'KillingFloor2 stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameKillingFloor2InstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'KillingFloor2 stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameKillingFloor2RuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
        throw ("KillingFloor2 stop failed: Process {0} is still running." -f $targetProcessId)
    }

    Start-Sleep -Seconds 2

    try {
        $runtimeMarker = Join-Path $runtime.RuntimeSaveRootPath 'UGSM.Runtime.json'
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

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Runtime  = $runtime
    }
}

function Register-UGSMGameKillingFloor2Module {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameKillingFloor2Metadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata         = 'Get-UGSMGameKillingFloor2Metadata'
            TestInstall         = 'Test-UGSMGameKillingFloor2Install'
            TestInstance        = 'Test-UGSMGameKillingFloor2Instance'
            EnsureKillingFloor2 = 'Ensure-UGSMGameKillingFloor2Template'
            InitializeProfile   = 'Initialize-UGSMGameKillingFloor2Profile'
            Start               = 'Start-UGSMGameKillingFloor2Instance'
            Stop                = 'Stop-UGSMGameKillingFloor2Instance'

            BuildEditor         = 'New-UGSMGameKillingFloor2InstanceEditor'
            SaveEditor          = 'Save-UGSMGameKillingFloor2InstanceEditor'
        }
    }
}


function Get-UGSMGameKillingFloor2BackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings', 'Mods', 'All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings', 'All')) {
        $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance

        $settingsTargets = @(
            @{ Path = $paths.ServerSettingsPath; Relative = 'Config\WindowsServer\ServerSettings.ini'; Label = 'KillingFloor2 server settings INI' },
            @{ Path = $paths.GameplayJsonPath; Relative = 'Config\WindowsServer\Gameplay.json'; Label = 'KillingFloor2 gameplay JSON' },
            @{ Path = $paths.GameplayXmlPath; Relative = 'Config\WindowsServer\Gameplay.xml'; Label = 'KillingFloor2 gameplay XML' },
            @{ Path = $paths.ServerCfgPath; Relative = 'Config\WindowsServer\Server.cfg'; Label = 'KillingFloor2 server CFG' },
            @{ Path = $paths.AdminUsersPath; Relative = 'Config\WindowsServer\AdminUsers.txt'; Label = 'KillingFloor2 admin users list' },
            @{ Path = $paths.ExclusiveUsersPath; Relative = 'Config\WindowsServer\ExclusiveUsers.txt'; Label = 'KillingFloor2 exclusive users list' },
            @{ Path = $paths.WhitelistedUsersPath; Relative = 'Config\WindowsServer\WhitelistedUsers.txt'; Label = 'KillingFloor2 whitelist users list' },
            @{ Path = $paths.BannedUsersPath; Relative = 'Config\WindowsServer\BannedUsers.txt'; Label = 'KillingFloor2 banned users list' },
            @{ Path = $paths.SilencedUsersPath; Relative = 'Config\WindowsServer\SilencedUsers.txt'; Label = 'KillingFloor2 silenced users list' }
        )

        foreach ($target in $settingsTargets) {
            if ([string]::IsNullOrWhiteSpace([string]$target.Path)) { continue }
            [void]$targets.Add([pscustomobject]@{
                    SourcePath   = [string]$target.Path
                    RelativePath = [string]$target.Relative
                    Label        = [string]$target.Label
                })
        }
    }

    # Future copied game modules can add mod/map manifests here, but do not include runtime/world/save folders by default.
    if ($Scope -in @('Mods', 'All')) {
        # Example:
        # [void]$targets.Add([pscustomobject]@{
        #     SourcePath   = Join-Path $paths.ConfigRoot 'UGSM_ManagedMods.json'
        #     RelativePath = 'Mods\UGSM_ManagedMods.json'
        #     Label        = 'KillingFloor2 managed mods manifest'
        # })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameKillingFloor2ManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings', 'Mods', 'All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'KillingFloor2 managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameKillingFloor2BackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'KillingFloor2' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameKillingFloor2Log -Level 'WARN' -Message ('KillingFloor2 managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameKillingFloor2ProfilePaths {
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
        $profileRoot = Get-UGSMGameKillingFloor2ProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'Killing Floor 2 profile paths could not be resolved for the selected instance.'
    }

    $profileConfigRoot = Join-Path $profileRoot 'Config'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot
        ProfileConfigRoot           = $profileConfigRoot
        ProfileSaveRoot             = $null
        ProfileLogRoot              = Join-Path $profileRoot 'Logs'

        RuntimeRoot                 = $profileRoot
        RuntimeConfigRoot           = $profileConfigRoot
        RuntimeSaveRoot             = $null
        RuntimeLogRoot              = Join-Path $profileRoot 'Logs'
        IsRuntimeActive             = $false

        ConfigRoot                  = $profileConfigRoot
        SaveRoot                    = $null
        LogRoot                     = Join-Path $profileRoot 'Logs'

        PCServerKFGamePath          = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
        PCServerKFEnginePath        = Join-Path $profileConfigRoot 'PCServer-KFEngine.ini'
        KFWebPath                   = Join-Path $profileConfigRoot 'KFWeb.ini'
        ServerConsoleLogPath        = Join-Path (Join-Path $profileRoot 'Logs') 'server-console.log'

        PrimaryIniPath              = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
        ServerSettingsPath          = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
        PrimaryJsonPath             = $null
        PrimaryXmlPath              = $null
        PrimaryCfgPath              = $null
        GameplayJsonPath            = $null
        GameplayXmlPath             = $null
        ServerCfgPath               = $null

        AdminUsersPath              = $null
        ExclusiveUsersPath          = $null
        WhitelistedUsersPath        = $null
        BannedUsersPath             = $null
        SilencedUsersPath           = $null

        RuntimePrimaryIniPath       = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
        RuntimeServerSettingsPath   = Join-Path $profileConfigRoot 'PCServer-KFGame.ini'
        RuntimeAdminUsersPath       = $null
        RuntimeExclusiveUsersPath   = $null
        RuntimeWhitelistedUsersPath = $null
        RuntimeBannedUsersPath      = $null
        RuntimeSilencedUsersPath    = $null
    }
}

function Read-UGSMGameKillingFloor2IniFile {
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

function Get-UGSMGameKillingFloor2IniValue {
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

function Set-UGSMGameKillingFloor2IniValue {
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

function Read-UGSMGameKillingFloor2StringListFile {
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

function Write-UGSMGameKillingFloor2StringListFile {
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


function Set-UGSMGameKillingFloor2RepeatedIniValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [string[]]$Values
    )

    Ensure-UGSMGameKillingFloor2ParentDirectory -Path $Path

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$line)
        }
    }

    $sectionHeader = '[' + $Section + ']'
    $sectionRegex = '^\s*\[' + [regex]::Escape($Section) + '\]\s*$'
    $anySectionRegex = '^\s*\[.+\]\s*$'
    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*='

    $sectionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $sectionRegex) { $sectionStart = $i; break }
    }

    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$lines[$lines.Count - 1])) {
            [void]$lines.Add('')
        }
        [void]$lines.Add($sectionHeader)
        $sectionStart = $lines.Count - 1
    }

    $sectionEnd = $lines.Count
    for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $anySectionRegex) { $sectionEnd = $i; break }
    }

    for ($i = $sectionEnd - 1; $i -gt $sectionStart; $i--) {
        if ($lines[$i] -match $keyRegex) {
            $lines.RemoveAt($i)
        }
    }

    $insertIndex = $sectionStart + 1
    $cleanValues = @(
        $Values |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -match '^\d+$' } |
        Select-Object -Unique
    )

    foreach ($value in @($cleanValues)) {
        $lines.Insert($insertIndex, ($Key + '=' + [string]$value))
        $insertIndex++
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-UGSMGameKillingFloor2EnabledWorkshopIds {
    [CmdletBinding()]
    param([AllowNull()][object]$Manifest)

    $ids = New-Object System.Collections.Generic.List[string]
    if (-not $Manifest -or -not $Manifest.PSObject.Properties['Mods']) { return @() }

    foreach ($mod in @($Manifest.Mods)) {
        if (-not $mod) { continue }

        $enabled = $true
        if ($mod.PSObject.Properties['Enabled']) { $enabled = [bool]$mod.Enabled }
        if (-not $enabled) { continue }

        $workshopId = ''
        foreach ($propName in @('WorkshopId', 'WorkshopID', 'Id')) {
            if ($mod.PSObject.Properties[$propName]) {
                $candidate = [string]$mod.$propName
                if ($candidate -match '^\d+$') { $workshopId = $candidate; break }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($workshopId) -and -not $ids.Contains($workshopId)) {
            [void]$ids.Add($workshopId)
        }
    }

    return @($ids.ToArray())
}

function Sync-UGSMGameKillingFloor2WorkshopManifestToEngineIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Manifest,
        [AllowNull()][object]$ModsDefinition,
        [string]$WorkshopId = '',
        [string]$SharedContentPath = ''
    )

    if (-not $ModsDefinition) {
        try { $ModsDefinition = Get-UGSMGameKillingFloor2ModsDefinition } catch { $ModsDefinition = $null }
    }

    if (-not $Manifest) {
        if (Get-Command -Name Read-UGSMModsManifest -ErrorAction SilentlyContinue) {
            try { $Manifest = Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition } catch { $Manifest = $null }
        }
    }

    if (-not $Manifest) { return $null }

    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
    $enginePath = [string]$paths.PCServerKFEnginePath
    if ([string]::IsNullOrWhiteSpace($enginePath)) { return $null }

    $workshopIds = @(Get-UGSMGameKillingFloor2EnabledWorkshopIds -Manifest $Manifest)

    Set-UGSMGameKillingFloor2RepeatedIniValues -Path $enginePath -Section 'OnlineSubsystemSteamworks.KFWorkshopSteamworks' -Key 'ServerSubscribedWorkshopItems' -Values $workshopIds
    Set-UGSMGameKillingFloor2IniValue -Path $enginePath -Section 'IpDrv.HTTPDownload' -Key 'RedirectToURL' -Value 'http://kf2.tripwirecdn.com/'

    return [pscustomobject]@{
        Success     = $true
        Path        = $enginePath
        WorkshopIds = @($workshopIds)
        Count       = [int]$workshopIds.Count
    }
}


function Ensure-UGSMGameKillingFloor2ParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameKillingFloor2JsonFile {
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

function Write-UGSMGameKillingFloor2JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameKillingFloor2ParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGameKillingFloor2XmlFile {
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

function Write-UGSMGameKillingFloor2XmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameKillingFloor2ParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameKillingFloor2CfgFile {
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

function Set-UGSMGameKillingFloor2CfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameKillingFloor2ParentDirectory -Path $Path

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
function Test-UGSMGameKillingFloor2PSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameKillingFloor2PSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameKillingFloor2PSSQLiteInstalled)
}

function Get-UGSMGameKillingFloor2ElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameKillingFloor2PSSQLiteInstalled)) {
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

function Save-UGSMGameKillingFloor2ElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameKillingFloor2PSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'KillingFloor2.db was not found.'
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


function Resolve-UGSMGameKillingFloor2EditorFieldPath {
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

function ConvertTo-UGSMGameKillingFloor2EditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'InstanceBoolean' {
            return [bool]$Control.Checked
        }
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
        'Select' {
            try {
                $selectedText = [string]$Control.Text
                if ($Control.SelectedItem) { $selectedText = [string]$Control.SelectedItem }
                if ($Control.Tag -is [System.Collections.IDictionary] -and $Control.Tag.Contains('Values')) {
                    $valueLookup = $Control.Tag['Values']
                    if ($valueLookup -is [System.Collections.IDictionary] -and $valueLookup.Contains($selectedText)) {
                        return [string]$valueLookup[$selectedText]
                    }
                }
                if ($Control.SelectedValue -and -not [string]::IsNullOrWhiteSpace([string]$Control.SelectedValue)) {
                    return [string]$Control.SelectedValue
                }
            }
            catch {}
            return [string]$Control.Text
        }
        default {
            return [string]$Control.Text
        }
    }
}


function Get-UGSMGameKillingFloor2InstanceDefinitionPath {
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

function Save-UGSMGameKillingFloor2InstanceDefinition {
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

    $definitionPath = Get-UGSMGameKillingFloor2InstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameKillingFloor2InstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameKillingFloor2InstanceDiscordShape -Instance $Instance
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false

    foreach ($dirPath in @($paths.ConfigRoot)) {
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

    Invoke-UGSMGameKillingFloor2ManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before KillingFloor2 settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("KillingFloor2 save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameKillingFloor2StringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control
                $targetIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$targetIniPath)) { $targetIniPath = $paths.ServerSettingsPath }
                Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control
                $targetIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$targetIniPath)) { $targetIniPath = $paths.ServerSettingsPath }
                Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control
                $targetIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$targetIniPath)) { $targetIniPath = $paths.ServerSettingsPath }
                Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control
                $targetIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$targetIniPath)) { $targetIniPath = $paths.ServerSettingsPath }
                Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Select' {
                $value = ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control
                $targetIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $field -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$targetIniPath)) { $targetIniPath = $paths.ServerSettingsPath }
                Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++

                if ([string]$field.Id -eq 'GameModeClass') {
                    Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section 'Engine.GameInfo' -Key 'DefaultServerGame' -Value $value
                    Set-UGSMGameKillingFloor2IniValue -Path $targetIniPath -Section 'Engine.GameInfo' -Key 'DefaultGameType' -Value $value
                    $saveSummary.IniKeysWritten += 2
                }
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameKillingFloor2EditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }
        }
    }

    if ($hasDiscordChanges) {
        $persistScript = {
            param($PersistedInstance)
            [void](Save-UGSMGameKillingFloor2InstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    try {
        $updatedInstance = Sync-UGSMGameKillingFloor2InstanceDisplayName -Instance $updatedInstance
        Set-UGSMGameKillingFloor2RuntimePlayerCountFields -Instance $updatedInstance -CurrentPlayers 0 -MaxPlayers (Get-UGSMGameKillingFloor2MaxPlayersFromConfig -Instance $updatedInstance) -Source 'KF2_LOG_SERVER_DATA' -Status 'Saved' -Detail ''
        Save-UGSMGameKillingFloor2InstanceDefinition -Instance $updatedInstance | Out-Null
    }
    catch { }

    return [pscustomobject]@{
        Success  = $true
        Message  = ("Saved KillingFloor2 settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary  = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameKillingFloor2InstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if (-not $Theme) { $Theme = @{} }
    $baseTheme = $null
    if (Get-Command -Name Get-UGSMTheme -ErrorAction SilentlyContinue) {
        try { $baseTheme = Get-UGSMTheme } catch { $baseTheme = $null }
    }
    foreach ($themeName in @('Background', 'Surface', 'Input', 'Text', 'Muted', 'Accent', 'AccentBlue', 'Button', 'Danger', 'Success')) {
        if (-not $Theme.ContainsKey($themeName) -or $null -eq $Theme[$themeName]) {
            if ($baseTheme -and $baseTheme.ContainsKey($themeName)) { $Theme[$themeName] = $baseTheme[$themeName] }
        }
    }

    $Instance = Ensure-UGSMGameKillingFloor2InstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
    $schema = Get-UGSMGameKillingFloor2EditorSchema
    $iniData = Read-UGSMGameKillingFloor2IniFile -Path $paths.ServerSettingsPath
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

    function Get-KillingFloor2SafeIniValue {
        param([hashtable]$Field)
        try {
            $fieldIniPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $Field -Paths $paths
            $fieldIniData = $iniData
            if (-not [string]::IsNullOrWhiteSpace([string]$fieldIniPath) -and [string]$fieldIniPath -ne [string]$paths.ServerSettingsPath) {
                $fieldIniData = Read-UGSMGameKillingFloor2IniFile -Path $fieldIniPath
            }
            return [string](Get-UGSMGameKillingFloor2IniValue -IniData $fieldIniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-KillingFloor2SafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-KillingFloor2TextBox {
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
            $tb.BackColor = $Theme.Input
            $tb.ForeColor = $Theme.Text
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

    function New-KillingFloor2StretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-KillingFloor2TextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-KillingFloor2NarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-KillingFloor2ElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits KillingFloor2.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
        $status.AutoSize = $false
        [void]$wrapper.Controls.Add($status, 0, 0)
        $wrapper.SetColumnSpan($status, 2)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Dock = 'Fill'
        $list.Height = 170
        $list.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
        $list.BackColor = $Theme.Input
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

        $btnInstallSql = New-UGSMButton -Text 'Install PSSQLite' -Width 150 -Height 28 -BackColor $Theme.AccentBlue
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

        $btnRemoveDb = New-UGSMButton -Text 'Remove Selected' -Width 150 -Height 28 -BackColor $Theme.Danger
        $btnRemoveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnRemoveDb, 1, 5)

        $btnSaveDb = New-UGSMButton -Text 'Save DB' -Width 150 -Height 28 -BackColor $Theme.Accent
        $btnSaveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnSaveDb, 1, 6)

        $loadDbState = {
            $list.Items.Clear()
            $moduleInstalled = Test-UGSMGameKillingFloor2PSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in KillingFloor2.db.')
                return
            }

            $dbPath = Resolve-UGSMGameKillingFloor2DatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('KillingFloor2.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('KillingFloor2.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameKillingFloor2ElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading KillingFloor2.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameKillingFloor2PSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameKillingFloor2DatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'KillingFloor2.db path could not be resolved for this instance.' }
                    Save-UGSMGameKillingFloor2ElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to KillingFloor2.db: ' + $dbPath }
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

    function Add-KillingFloor2FieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the KillingFloor2 editor can render any supported schema shape.
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
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameKillingFloor2ModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the KillingFloor2 Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-KillingFloor2NarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-KillingFloor2SafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-KillingFloor2NarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-KillingFloor2SafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-KillingFloor2NarrowHost
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
                    $rawValue = Get-KillingFloor2SafeIniValue -Field $Field
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
                'Select' {
                    $selectHost = New-KillingFloor2NarrowHost
                    $control = New-Object System.Windows.Forms.ComboBox
                    $control.DropDownStyle = 'DropDownList'
                    $control.Width = [Math]::Max($layout.ControlWidth, 340)
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = $Theme.Input
                    $control.ForeColor = New-UGSMColor $Theme.Text

                    $valueLookup = @{}
                    $valueList = New-Object System.Collections.ArrayList
                    foreach ($option in @($Field.Options)) {
                        $labelText = ''
                        $valueText = ''
                        if ($option -is [System.Collections.IDictionary]) {
                            $labelText = [string]$option['Label']
                            $valueText = [string]$option['Value']
                        }
                        else {
                            if ($option.PSObject.Properties['Label']) { $labelText = [string]$option.Label }
                            if ($option.PSObject.Properties['Value']) { $valueText = [string]$option.Value }
                        }
                        if ([string]::IsNullOrWhiteSpace($labelText)) { $labelText = $valueText }
                        if ([string]::IsNullOrWhiteSpace($valueText)) { $valueText = $labelText }
                        if (-not [string]::IsNullOrWhiteSpace($labelText)) {
                            [void]$control.Items.Add($labelText)
                            $valueLookup[$labelText] = $valueText
                            [void]$valueList.Add([pscustomobject]@{ Label = $labelText; Value = $valueText })
                        }
                    }
                    $control.Tag = @{ Values = $valueLookup; Items = $valueList }

                    $currentValue = [string](Get-KillingFloor2SafeIniValue -Field $Field)
                    $matchedIndex = -1
                    for ($i = 0; $i -lt $valueList.Count; $i++) {
                        if ([string]$valueList[$i].Value -eq $currentValue -or [string]$valueList[$i].Label -eq $currentValue) {
                            $matchedIndex = $i
                            break
                        }
                    }
                    if ($matchedIndex -ge 0 -and $matchedIndex -lt $control.Items.Count) {
                        $control.SelectedIndex = $matchedIndex
                    }
                    elseif ($control.Items.Count -gt 0) {
                        $control.SelectedIndex = 0
                    }
                    [void]$selectHost.Controls.Add($control)
                    [void]$row.Controls.Add($selectHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'MultilineText' {
                    $control = New-KillingFloor2StretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-KillingFloor2SafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-KillingFloor2StretchTextBox -MaskSecret
                    $control.Text = [string](Get-KillingFloor2SafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-KillingFloor2StretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-KillingFloor2SafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-KillingFloor2TextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameKillingFloor2EditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-KillingFloor2NarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor $Theme.Button
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 action failed: ' + $_.Exception.Message } }
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

                    New-KillingFloor2ElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-KillingFloor2StretchTextBox
                    $control.Text = [string](Get-KillingFloor2SafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('KillingFloor2 field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Danger
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-KillingFloor2EditorContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
            [string]$Description,
            [object[]]$Fields
        )

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.BackColor = $Theme.Background
        [void]$Parent.Controls.Add($scroll)

        $content = New-Object System.Windows.Forms.FlowLayoutPanel
        $content.Dock = 'Top'
        $content.AutoSize = $true
        $content.AutoSizeMode = 'GrowAndShrink'
        $content.FlowDirection = 'TopDown'
        $content.WrapContents = $false
        $content.Margin = New-Object System.Windows.Forms.Padding(0)
        $content.Padding = New-Object System.Windows.Forms.Padding($layout.ContentPadding, 10, $layout.ContentPadding, 10)
        $content.BackColor = $Theme.Background
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
            Add-KillingFloor2FieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
        }

        & $refreshScrollLayout
    }

    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = $Theme.Surface

        $root = New-Object System.Windows.Forms.TableLayoutPanel
        $root.Dock = 'Fill'
        $root.Margin = New-Object System.Windows.Forms.Padding(0)
        $root.Padding = New-Object System.Windows.Forms.Padding(0)
        $root.BackColor = $Theme.Surface
        $root.ColumnCount = 1
        $root.RowCount = 3
        [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.HeaderHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.ToolbarHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$HostPanel.Controls.Add($root)

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Fill'
        $header.BackColor = $Theme.Surface
        [void]$root.Controls.Add($header, 0, 0)

        $title = New-UGSMLabel -Text ('KillingFloor2 Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
        $pathLabel = New-UGSMLabel -Text ([string]$paths.ProfileRoot) -X 12 -Y 28 -Width 760 -Height 16 -FontSize 8 -Color $Theme.Muted
        [void]$header.Controls.Add($title)
        [void]$header.Controls.Add($pathLabel)

        $toolbar = New-Object System.Windows.Forms.Panel
        $toolbar.Dock = 'Fill'
        $toolbar.BackColor = $Theme.Surface
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

        $btnReload = New-UGSMButton -Text 'Reload' -X 0 -Y 0 -Width 84 -Height 28 -BackColor $Theme.Button
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
            $tabPage.BackColor = $Theme.Background
            [void]$tabs.TabPages.Add($tabPage)

            # Mods tab is owned by UGSM_Game_Helper.ps1. The game module only creates
            # the TabPage host and passes the instance/mod definition into the shared renderer.
            if ([string]$tabDef.Title -eq 'Mods') {
                $modsTabFeatures = Get-UGSMGameKillingFloor2SupportedFeatures
                if ([bool]$modsTabFeatures.Mods) {
                    try {
                        $modsDefinition = Get-UGSMGameKillingFloor2ModsDefinition
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
                        $err = New-UGSMLabel -Text ('KillingFloor2 shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color $Theme.Danger
                        [void]$tabPage.Controls.Add($err)
                        if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 shared Mods tab failed: ' + $_.Exception.Message }
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
                    $subPage.BackColor = $Theme.Background
                    [void]$subTabs.TabPages.Add($subPage)
                    New-KillingFloor2EditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-KillingFloor2EditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameKillingFloor2InstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved KillingFloor2 profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameKillingFloor2InstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'KillingFloor2 profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameKillingFloor2OpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'KillingFloor2 open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("KillingFloor2 open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'KillingFloor2 open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("KillingFloor2 open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("KillingFloor2 open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameKillingFloor2EditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'KillingFloor2 action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameKillingFloor2ProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("KillingFloor2 action failed: could not resolve paths for '{0}'." -f $Target)
    }

    $candidate = switch ($Target) {
        'ServerSettings' { [string]$Paths.ServerSettingsPath }
        'PrimaryIni' { [string]$Paths.PrimaryIniPath }
        'PrimaryJson' { [string]$Paths.PrimaryJsonPath }
        'PrimaryXml' { [string]$Paths.PrimaryXmlPath }
        'PrimaryCfg' { [string]$Paths.PrimaryCfgPath }
        'PCServerKFGame' { [string]$Paths.PCServerKFGamePath }
        'PCServerKFEngine' { [string]$Paths.PCServerKFEnginePath }
        'KFWeb' { [string]$Paths.KFWebPath }
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
        throw ("KillingFloor2 action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameKillingFloor2EditorAction {
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

    $resolvedPath = Resolve-UGSMGameKillingFloor2EditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameKillingFloor2OpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameKillingFloor2EditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenGameIni      = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameKillingFloor2EditorAction -Instance $Instance -Paths $Paths -Target 'PCServerKFGame' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened PCServer-KFGame.ini.' }
        OpenEngineIni    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameKillingFloor2EditorAction -Instance $Instance -Paths $Paths -Target 'PCServerKFEngine' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened PCServer-KFEngine.ini.' }
        OpenWebIni       = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameKillingFloor2EditorAction -Instance $Instance -Paths $Paths -Target 'KFWeb' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened KFWeb.ini.' }
        OpenConfigFolder = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameKillingFloor2OpenPath -Path $Paths.ConfigRoot -StatusLabel $StatusLabel -OpenedMessage 'Opened KF2 profile config folder.' }
    }

    $features = Get-UGSMGameKillingFloor2SupportedFeatures

    $mapOptions = @(
        @{ Label = 'Airship'; Value = 'KF-Airship' }
        @{ Label = 'Ashwood Asylum'; Value = 'KF-AshwoodAsylum' }
        @{ Label = 'Barmwich Town'; Value = 'KF-BarmwichTown' }
        @{ Label = 'Biolapse'; Value = 'KF-Biolapse' }
        @{ Label = 'Biotics Lab'; Value = 'KF-BioticsLab' }
        @{ Label = 'Black Forest'; Value = 'KF-BlackForest' }
        @{ Label = 'Burning Paris'; Value = 'KF-BurningParis' }
        @{ Label = 'Carillon Hamlet'; Value = 'KF-CarillonHamlet' }
        @{ Label = 'Castle Volter'; Value = 'KF-CastleVolter' }
        @{ Label = 'Catacombs'; Value = 'KF-Catacombs' }
        @{ Label = 'Containment Station'; Value = 'KF-ContainmentStation' }
        @{ Label = 'Crash'; Value = 'KF-Crash' }
        @{ Label = 'Desolation'; Value = 'KF-Desolation' }
        @{ Label = 'DieSector'; Value = 'KF-DieSector' }
        @{ Label = 'Dystopia 2029'; Value = 'KF-Dystopia2029' }
        @{ Label = 'Elysium'; Value = 'KF-Elysium' }
        @{ Label = 'Evacuation Point'; Value = 'KF-EvacuationPoint' }
        @{ Label = 'Farmhouse'; Value = 'KF-Farmhouse' }
        @{ Label = 'Hellmark Station'; Value = 'KF-HellmarkStation' }
        @{ Label = 'Hostile Grounds'; Value = 'KF-HostileGrounds' }
        @{ Label = 'Infernal Realm'; Value = 'KF-InfernalRealm' }
        @{ Label = 'Krampus Lair'; Value = 'KF-KrampusLair' }
        @{ Label = 'Lockdown'; Value = 'KF-Lockdown' }
        @{ Label = 'Monster Ball'; Value = 'KF-MonsterBall' }
        @{ Label = 'Moonbase'; Value = 'KF-Moonbase' }
        @{ Label = 'Netherhold'; Value = 'KF-Netherhold' }
        @{ Label = 'Nightmare'; Value = 'KF-Nightmare' }
        @{ Label = 'Nuked'; Value = 'KF-Nuked' }
        @{ Label = 'Outpost'; Value = 'KF-Outpost' }
        @{ Label = 'Power Core Holdout'; Value = 'KF-PowerCore_Holdout' }
        @{ Label = 'Prison'; Value = 'KF-Prison' }
        @{ Label = 'Rig'; Value = 'KF-Rig' }
        @{ Label = 'Sanitarium'; Value = 'KF-Sanitarium' }
        @{ Label = 'Santas Workshop'; Value = 'KF-SantasWorkshop' }
        @{ Label = 'Shopping Spree'; Value = 'KF-ShoppingSpree' }
        @{ Label = 'Spillway'; Value = 'KF-Spillway' }
        @{ Label = 'Steam Fortress'; Value = 'KF-SteamFortress' }
        @{ Label = 'Subduction'; Value = 'KF-Subduction' }
        @{ Label = 'The Descent'; Value = 'KF-TheDescent' }
        @{ Label = 'Tragic Kingdom'; Value = 'KF-TragicKingdom' }
        @{ Label = 'Volter Manor'; Value = 'KF-VolterManor' }
        @{ Label = 'Zed Landing'; Value = 'KF-ZedLanding' }
    )

    $gameModeOptions = @(
        @{ Label = 'Survival'; Value = 'KFGameContent.KFGameInfo_Survival' }
        @{ Label = 'Weekly Survival'; Value = 'KFGameContent.KFGameInfo_WeeklySurvival' }
        @{ Label = 'Versus Survival'; Value = 'KFGameContent.KFGameInfo_VersusSurvival' }
        @{ Label = 'Endless'; Value = 'KFGameContent.KFGameInfo_Endless' }
        @{ Label = 'Objective'; Value = 'KFGameContent.KFGameInfo_Objective' }
    )

    $difficultyOptions = @(
        @{ Label = 'Normal'; Value = '0.000000' }
        @{ Label = 'Hard'; Value = '1.000000' }
        @{ Label = 'Suicidal'; Value = '2.000000' }
        @{ Label = 'Hell on Earth'; Value = '3.000000' }
    )

    $lengthOptions = @(
        @{ Label = 'Short'; Value = '0' }
        @{ Label = 'Medium'; Value = '1' }
        @{ Label = 'Long'; Value = '2' }
    )

    $schema = [pscustomobject]@{
        Version = 2
        Tabs    = @(
            [pscustomobject]@{
                Title       = 'Server'
                Description = 'Killing Floor 2 server identity, access, launch map, and selected game mode.'
                Fields      = @(
                    @{ Id = 'ServerName'; Type = 'Text'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.GameReplicationInfo'; Key = 'ServerName'; Label = 'Server Name'; DefaultValue = 'UGSM KF2 Server'; Hint = 'Public name shown in the KF2 server browser.' }
                    @{ Id = 'ShortName'; Type = 'Text'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.GameReplicationInfo'; Key = 'ShortName'; Label = 'Short Name'; DefaultValue = 'UGSMKF2'; Hint = 'Short server name.' }
                    @{ Id = 'StartMap'; Type = 'Select'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'URL'; Key = 'ServerLocalMap'; Label = 'Start Map'; DefaultValue = 'KF-BioticsLab'; Options = $mapOptions; Hint = 'Default official map to launch. Using a dropdown helps avoid spelling errors.' }
                    @{ Id = 'GameModeClass'; Type = 'Select'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.GameInfo'; Key = 'DefaultGame'; Label = 'Game Mode'; DefaultValue = 'KFGameContent.KFGameInfo_Survival'; Options = $gameModeOptions; Hint = 'Game class used in the launch URL. Save also syncs DefaultServerGame and DefaultGameType.' }
                    @{ Id = 'AllowTakeover'; Type = 'Boolean'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'Engine.GameEngine'; Key = 'bUsedForTakeover'; Label = 'Allow Takeover'; DefaultValue = $true; Hint = 'Allow KF2 takeover/matchmaking behavior for this server. Disable for a more locked-down dedicated test server.' }
                    @{ Id = 'AdminPassword'; Type = 'Password'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.AccessControl'; Key = 'AdminPassword'; Label = 'Admin Password'; DefaultValue = ''; Hint = 'WebAdmin/admin password. Masked on screen.' }
                    @{ Id = 'GamePassword'; Type = 'Password'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.AccessControl'; Key = 'GamePassword'; Label = 'Server Password'; DefaultValue = ''; Hint = 'Optional join password. Leave blank for public access. Masked on screen.' }
                    @{ Id = 'Spectators'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.GameInfo'; Key = 'MaxSpectators'; Label = 'Max Spectators'; DefaultValue = 2; Min = 0; Max = 32; Decimals = 0; Hint = 'Spectator slots.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Survival'
                Description = 'Survival mode settings from PCServer-KFGame.ini.'
                Fields      = @(
                    @{ Id = 'SurvivalMaxPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Survival'; Key = 'MaxPlayers'; Label = 'Survival Max Players'; DefaultValue = 6; Min = 1; Max = 32; Decimals = 0; Hint = 'Max player slots for Survival.' }
                    @{ Id = 'SurvivalMinPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Survival'; Key = 'MinNetPlayers'; Label = 'Survival Min Players'; DefaultValue = 1; Min = 1; Max = 32; Decimals = 0; Hint = 'Minimum players before Survival starts when wait-for-players is enabled.' }
                    @{ Id = 'SurvivalWaitPlayers'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Survival'; Key = 'bWaitForNetPlayers'; Label = 'Wait For Players'; DefaultValue = $true; Hint = 'Wait for minimum players before starting Survival.' }
                    @{ Id = 'SurvivalEndDelay'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Survival'; Key = 'EndOfGameDelay'; Label = 'End Of Game Delay'; DefaultValue = 15; Min = 0; Max = 300; Decimals = 0; Hint = 'Delay after the match ends.' }
                    @{ Id = 'SurvivalKillWhenEmpty'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Survival'; Key = 'ServerExpirationForKillWhenEmpty'; Label = 'Kill When Empty Delay'; DefaultValue = 120; Min = 0; Max = 3600; Decimals = 0; Hint = 'Seconds before the server expires/kills an empty match.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Weekly / Endless'
                Description = 'Weekly Survival and Endless mode player settings.'
                Fields      = @(
                    @{ Id = 'WeeklyMaxPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_WeeklySurvival'; Key = 'MaxPlayers'; Label = 'Weekly Max Players'; DefaultValue = 6; Min = 1; Max = 32; Decimals = 0; Hint = 'Max player slots for Weekly Survival.' }
                    @{ Id = 'EndlessMaxPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_Endless'; Key = 'MaxPlayers'; Label = 'Endless Max Players'; DefaultValue = 6; Min = 1; Max = 32; Decimals = 0; Hint = 'Max player slots for Endless.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Versus / Objective'
                Description = 'Versus Survival and Objective mode settings.'
                Fields      = @(
                    @{ Id = 'VersusMaxPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_VersusSurvival'; Key = 'MaxPlayers'; Label = 'Versus Max Players'; DefaultValue = 12; Min = 1; Max = 32; Decimals = 0; Hint = 'Max player slots for Versus Survival.' }
                    @{ Id = 'VersusMinPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_VersusSurvival'; Key = 'MinNetPlayers'; Label = 'Versus Min Players'; DefaultValue = 2; Min = 1; Max = 32; Decimals = 0; Hint = 'Minimum players for Versus Survival.' }
                    @{ Id = 'TeamBalance'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_VersusSurvival'; Key = 'bTeamBalanceEnabled'; Label = 'Team Balance'; DefaultValue = $true; Hint = 'Enable team balancing in Versus Survival.' }
                    @{ Id = 'VersusRoundDelay'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGameContent.KFGameInfo_VersusSurvival'; Key = 'TimeUntilNextRound'; Label = 'Next Round Delay'; DefaultValue = 30; Min = 0; Max = 300; Decimals = 0; Hint = 'Seconds until the next Versus round.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Gameplay'
                Description = 'Game-wide KF2 gameplay values.'
                Fields      = @(
                    @{ Id = 'GameDifficulty'; Type = 'Select'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'Engine.GameInfo'; Key = 'GameDifficulty'; Label = 'Difficulty'; DefaultValue = '0.000000'; Options = $difficultyOptions; Hint = 'Normal, Hard, Suicidal, or Hell on Earth.' }
                    @{ Id = 'GameLength'; Type = 'Select'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'GameLength'; Label = 'Game Length'; DefaultValue = '1'; Options = $lengthOptions; Hint = 'Short, Medium, or Long. Weekly/Endless may ignore this.' }
                    @{ Id = 'MinNetPlayers'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'MinNetPlayers'; Label = 'Global Min Players'; DefaultValue = 1; Min = 1; Max = 32; Decimals = 0; Hint = 'Global minimum players value.' }
                    @{ Id = 'GameStartDelay'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'GameStartDelay'; Label = 'Game Start Delay'; DefaultValue = 4; Min = 0; Max = 300; Decimals = 0; Hint = 'Delay before the match starts.' }
                    @{ Id = 'ReadyUpDelay'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'ReadyUpDelay'; Label = 'Ready Up Delay'; DefaultValue = 90; Min = 0; Max = 600; Decimals = 0; Hint = 'Ready-up lobby delay.' }
                    @{ Id = 'WaitForNetPlayers'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bWaitForNetPlayers'; Label = 'Wait For Net Players'; DefaultValue = $true; Hint = 'Wait for the minimum player count before starting.' }
                    @{ Id = 'FriendlyFireScale'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'FriendlyFireScale'; Label = 'Friendly Fire Scale'; DefaultValue = 0; Min = 0; Max = 1; Decimals = 2; Increment = '0.05'; Hint = '0 disables friendly fire. 1 is full friendly fire damage.' }
                    @{ Id = 'EnableMapObjectives'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bEnableMapObjectives'; Label = 'Enable Map Objectives'; DefaultValue = $true; Hint = 'Enable objective events where maps support them.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Voting / Chat'
                Description = 'Common KF2 voting and communication options.'
                Fields      = @(
                    @{ Id = 'DisableKickVote'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bDisableKickVote'; Label = 'Disable Kick Vote'; DefaultValue = $false; Hint = 'Turns off player kick voting.' }
                    @{ Id = 'KickVotePercentage'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'KickVotePercentage'; Label = 'Kick Vote Percentage'; DefaultValue = 0.66; Min = 0; Max = 1; Decimals = 2; Increment = '0.01'; Hint = 'Vote percentage required for kick votes.' }
                    @{ Id = 'VoteTime'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'VoteTime'; Label = 'Vote Time'; DefaultValue = 60; Min = 0; Max = 300; Decimals = 0; Hint = 'Seconds a vote remains open.' }
                    @{ Id = 'TimeBetweenFailedVotes'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'TimeBetweenFailedVotes'; Label = 'Failed Vote Cooldown'; DefaultValue = 10; Min = 0; Max = 600; Decimals = 0; Hint = 'Cooldown after a failed vote.' }
                    @{ Id = 'DisableMapVote'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bDisableMapVote'; Label = 'Disable Map Vote'; DefaultValue = $false; Hint = 'Turns off map voting.' }
                    @{ Id = 'MapVoteDuration'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'MapVoteDuration'; Label = 'Map Vote Duration'; DefaultValue = 60; Min = 0; Max = 300; Decimals = 0; Hint = 'Map vote time in seconds.' }
                    @{ Id = 'MapVotePercentage'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'MapVotePercentage'; Label = 'Map Vote Percentage'; DefaultValue = 0; Min = 0; Max = 1; Decimals = 2; Increment = '0.01'; Hint = 'Map vote percentage threshold.' }
                    @{ Id = 'DisablePublicTextChat'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bDisablePublicTextChat'; Label = 'Disable Public Text Chat'; DefaultValue = $false; Hint = 'Turns off public text chat.' }
                    @{ Id = 'DisableVOIP'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bDisableVOIP'; Label = 'Disable VOIP'; DefaultValue = $false; Hint = 'Turns off voice chat.' }
                    @{ Id = 'EnableDeadToVOIP'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bEnableDeadToVOIP'; Label = 'Dead Players To VOIP'; DefaultValue = $true; Hint = 'Allow dead players to use VOIP.' }
                    @{ Id = 'DisableTeamCollision'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'bDisableTeamCollision'; Label = 'Disable Team Collision'; DefaultValue = $false; Hint = 'Disables team collision.' }
                )
            }

            [pscustomobject]@{
                Title       = 'MOTD / Links'
                Description = 'Server MOTD, community links, and banner fields.'
                Fields      = @(
                    @{ Id = 'ServerMOTD'; Type = 'MultilineText'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'ServerMOTD'; Label = 'Server MOTD'; DefaultValue = ''; Hint = 'Message shown to players. KF2 uses \n in the raw file for line breaks.' }
                    @{ Id = 'WebsiteLink'; Type = 'Text'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'WebsiteLink'; Label = 'Website Link'; DefaultValue = ''; Hint = 'Optional community/server website link.' }
                    @{ Id = 'BannerLink'; Type = 'Text'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'BannerLink'; Label = 'Banner Image Link'; DefaultValue = ''; Hint = 'Optional MOTD/banner image URL.' }
                    @{ Id = 'ClanMotto'; Type = 'Text'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGameInfo'; Key = 'ClanMotto'; Label = 'Clan Motto'; DefaultValue = ''; Hint = 'Optional motto text.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network'
                Description = 'KF2 network ports and connection limits.'
                Fields      = @(
                    @{ Id = 'GamePort'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'URL'; Key = 'Port'; Label = 'Game Port'; DefaultValue = 7777; Min = 1; Max = 65535; Decimals = 0; Hint = 'KF2 game port.' }
                    @{ Id = 'PeerPort'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'URL'; Key = 'PeerPort'; Label = 'Peer Port'; DefaultValue = 7778; Min = 1; Max = 65535; Decimals = 0; Hint = 'KF2 peer port.' }
                    @{ Id = 'QueryPort'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'URL'; Key = 'QueryPort'; Label = 'Query Port'; DefaultValue = 27015; Min = 1; Max = 65535; Decimals = 0; Hint = 'Steam/master server query port. This is also passed in the KF2 launch URL so the server does not advertise as port 0.' }
                    @{ Id = 'SteamPort'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'URL'; Key = 'SteamPort'; Label = 'Steam Port'; DefaultValue = 20560; Min = 1; Max = 65535; Decimals = 0; Hint = 'Steam server port. This is also passed in the KF2 launch URL.' }
                    @{ Id = 'ConnectionTimeout'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'ConnectionTimeout'; Label = 'Connection Timeout'; DefaultValue = 30; Min = 1; Max = 600; Decimals = 0; Hint = 'Connection timeout in seconds.' }
                    @{ Id = 'InitialConnectTimeout'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'InitialConnectTimeout'; Label = 'Initial Connect Timeout'; DefaultValue = 200; Min = 1; Max = 600; Decimals = 0; Hint = 'Initial connection timeout in seconds.' }
                    @{ Id = 'MaxClientRate'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'MaxClientRate'; Label = 'Max Client Rate'; DefaultValue = 15000; Min = 1000; Max = 200000; Decimals = 0; Hint = 'Max client network rate.' }
                    @{ Id = 'MaxInternetClientRate'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'MaxInternetClientRate'; Label = 'Max Internet Client Rate'; DefaultValue = 10000; Min = 1000; Max = 200000; Decimals = 0; Hint = 'Max internet client network rate.' }
                    @{ Id = 'NetServerMaxTickRate'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'NetServerMaxTickRate'; Label = 'Server Tick Rate'; DefaultValue = 30; Min = 1; Max = 120; Decimals = 0; Hint = 'Server network tick rate.' }
                    @{ Id = 'LanServerMaxTickRate'; Type = 'Number'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'LanServerMaxTickRate'; Label = 'LAN Tick Rate'; DefaultValue = 35; Min = 1; Max = 120; Decimals = 0; Hint = 'LAN server tick rate.' }
                    @{ Id = 'AllowDownloads'; Type = 'Boolean'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'AllowDownloads'; Label = 'Allow Downloads'; DefaultValue = $true; Hint = 'Allow downloads from the server.' }
                    @{ Id = 'EnableDDOSProtection'; Type = 'Boolean'; File = 'PCServer-KFEngine.ini'; Path = 'PCServer-KFEngine.ini'; Section = 'IpDrv.TcpNetDriver'; Key = 'EnableDDOSProtection'; Label = 'Enable DDOS Protection'; DefaultValue = $true; Hint = 'Enable Unreal network DDOS protection.' }
                )
            }

            [pscustomobject]@{
                Title       = 'WebAdmin'
                Description = 'KF2 WebAdmin settings from KFWeb.ini.'
                Fields      = @(
                    @{ Id = 'WebAdminEnabled'; Type = 'Boolean'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebServer'; Key = 'bEnabled'; Label = 'Enable WebAdmin'; DefaultValue = $false; Hint = 'Enables the KF2 web admin interface.' }
                    @{ Id = 'WebAdminPort'; Type = 'Number'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebServer'; Key = 'ListenPort'; Label = 'WebAdmin Port'; DefaultValue = 8080; Min = 1; Max = 65535; Decimals = 0; Hint = 'KF2 WebAdmin TCP port.' }
                    @{ Id = 'WebAdminMaxConnections'; Type = 'Number'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebServer'; Key = 'MaxConnections'; Label = 'Max Connections'; DefaultValue = 18; Min = 1; Max = 512; Decimals = 0; Hint = 'Maximum WebAdmin connections.' }
                    @{ Id = 'WebAdminExpiration'; Type = 'Number'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebServer'; Key = 'ExpirationSeconds'; Label = 'Session Expiration'; DefaultValue = 86400; Min = 60; Max = 604800; Decimals = 0; Hint = 'WebAdmin session expiration in seconds.' }
                    @{ Id = 'WebConnectionMaxValueLength'; Type = 'Number'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebConnection'; Key = 'MaxValueLength'; Label = 'Max Value Length'; DefaultValue = 4096; Min = 1024; Max = 65535; Decimals = 0; Hint = 'Web connection max value length.' }
                    @{ Id = 'WebConnectionMaxLineLength'; Type = 'Number'; File = 'KFWeb.ini'; Path = 'KFWeb.ini'; Section = 'IpDrv.WebConnection'; Key = 'MaxLineLength'; Label = 'Max Line Length'; DefaultValue = 4096; Min = 1024; Max = 65535; Decimals = 0; Hint = 'Web connection max line length.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Performance / Gore'
                Description = 'Server-visible gore and decal limits. These are gameplay/performance-facing, not debug/render settings.'
                Fields      = @(
                    @{ Id = 'MaxDeadBodies'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxDeadBodies'; Label = 'Max Dead Bodies'; DefaultValue = 12; Min = 0; Max = 200; Decimals = 0; Hint = 'Maximum dead bodies kept around.' }
                    @{ Id = 'MaxBloodEffects'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxBloodEffects'; Label = 'Max Blood Effects'; DefaultValue = 25; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum blood effects.' }
                    @{ Id = 'MaxGoreEffects'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxGoreEffects'; Label = 'Max Gore Effects'; DefaultValue = 10; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum gore effects.' }
                    @{ Id = 'MaxBodyWoundDecals'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxBodyWoundDecals'; Label = 'Max Wound Decals'; DefaultValue = 5; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum body wound decals.' }
                    @{ Id = 'MaxBloodSplatterDecals'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxBloodSplatterDecals'; Label = 'Max Blood Splatter Decals'; DefaultValue = 20; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum blood splatter decals.' }
                    @{ Id = 'MaxBloodPoolDecals'; Type = 'Number'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'MaxBloodPoolDecals'; Label = 'Max Blood Pool Decals'; DefaultValue = 20; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum blood pool decals.' }
                    @{ Id = 'AllowBloodSplatterDecals'; Type = 'Boolean'; File = 'PCServer-KFGame.ini'; Path = 'PCServer-KFGame.ini'; Section = 'KFGame.KFGoreManager'; Key = 'AllowBloodSplatterDecals'; Label = 'Allow Blood Splatter Decals'; DefaultValue = $true; Hint = 'Allow blood splatter decals.' }
                )
            }

            if ([bool]$features.Mods) {
                [pscustomobject]@{
                    Title       = 'Mods'
                    Description = 'Steam Workshop mod support for Killing Floor 2.'
                    Fields      = @(
                        @{ Id = 'ModsProvider'; Type = 'ModsProviderPanel'; ModsDefinition = $modsDefinition }
                    )
                }
            }

            [pscustomobject]@{
                Title       = 'Files'
                Description = 'Open the KF2 profile files copied from the Steam install.'
                Fields      = @(
                    @{ Id = 'OpenGameIni'; Type = 'ActionButton'; Label = 'PCServer-KFGame.ini'; ButtonText = 'Open Game INI'; Action = $actions.OpenGameIni; Hint = 'Open the main KF2 server settings file.' }
                    @{ Id = 'OpenEngineIni'; Type = 'ActionButton'; Label = 'PCServer-KFEngine.ini'; ButtonText = 'Open Engine INI'; Action = $actions.OpenEngineIni; Hint = 'Open the KF2 engine/network settings file.' }
                    @{ Id = 'OpenWebIni'; Type = 'ActionButton'; Label = 'KFWeb.ini'; ButtonText = 'Open Web INI'; Action = $actions.OpenWebIni; Hint = 'Open the KF2 WebAdmin settings file.' }
                    @{ Id = 'OpenConfigFolder'; Type = 'ActionButton'; Label = 'Config Folder'; ButtonText = 'Open Config'; Action = $actions.OpenConfigFolder; Hint = 'Open the profile config folder.' }
                )
            }
        )
    }

    if ([bool]$features.Discord) {
        $discordFields = $null
        try { $discordFields = New-UGSMDiscordSettingsFields -GameId 'KillingFloor2' } catch { $discordFields = $null }

        if ($discordFields) {
            $schema.Tabs += [pscustomobject]@{
                Title       = 'Discord'
                Description = 'Per-instance Discord notifications and dashboard visibility.'
                Fields      = @($discordFields)
            }
        }
        else {
            $schema.Tabs += [pscustomobject]@{
                Title       = 'Discord'
                Description = 'UGSM per-server Discord override settings. Empty private webhook uses the global webhook.'
                Fields      = @(
                    @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Secret = $true; Hint = 'Optional per-server webhook override. Masked and stored using UGSM secrets.' }
                    @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                    @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                    @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $false; Hint = 'Show this server in dashboard/status integrations.' }
                )
            }
        }
    }

    return $schema
}
