# UGSM Game Template
# Hidden golden template for future UGSM game modules.
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace TEMPLATE with the real game token
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

$script:UGSMGameTEMPLATEEditorSchemaCache = $null

function Test-UGSMGameTEMPLATEVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameTEMPLATELogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameTEMPLATELogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_TEMPLATE)) { return $true }
    return $false
}

function ConvertTo-UGSMGameTEMPLATESafeLogText {
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
        # the template itself does not add portability-scan false positives.
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

function Write-UGSMGameTEMPLATELog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGameTEMPLATEVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameTEMPLATESafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameTEMPLATESafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:TEMPLATE' -Message $safeMessage
    }
}

function Write-UGSMGameTEMPLATEPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older template notes. New modules should use Write-UGSMGameTEMPLATELog.
    Write-UGSMGameTEMPLATELog -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGameTEMPLATEInstanceDiscordShape {
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


function Get-UGSMGameTEMPLATESupportedFeatures {
    [CmdletBinding()]
    param()

    # ============================================================
    # TEMPLATE SUPPORTED FEATURES
    # This is the first section to edit when copying the template.
    # Turn features on/off here, then edit the schema sections below.
    # Test builds show the template as a real game so optional UI can be previewed.
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
        Workshop      = $true
        ModTabMode    = 'SteamWorkshop' # SteamWorkshop, ArchiveImport, FrameworkPlugin, Mixed

        # Standard shared mod state storage. Game modules should keep mod references
        # in the instance JSON unless a game truly requires a different storage mode.
        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $true

        IniFiles        = $true
        JsonFiles       = $true
        XmlFiles        = $false
        CfgFiles        = $true
        PropertiesFiles = $false
        YamlFiles       = $false
        TomlFiles       = $false
        LuaFiles        = $false
        TextFiles       = $true
        PSSQLite        = $false

        ModCapabilities = [pscustomobject]@{
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

function Get-UGSMGameTEMPLATEModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameTEMPLATESupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'TEMPLATE' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
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
            GameId = 'TEMPLATE'
        }
    }


    # Template Workshop App ID placeholder. Copied games must replace 000000 with
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

    return $mods
}

function Get-UGSMGameTEMPLATEMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = Join-Path 'Bin' 'TemplateServer.exe'
    $features = Get-UGSMGameTEMPLATESupportedFeatures
    $modsDefinition = Get-UGSMGameTEMPLATEModsDefinition

    return [pscustomobject]@{
        Id                       = 'TEMPLATE'
        Name                     = 'Template'
        Category                 = 'Template'
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
        SteamAppId               = '000000'
        SteamStoreAppId          = '000000'
        ServerExecutable         = 'TemplateServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'Config'
        SaveRootRelative         = 'SaveData'
        LogRootRelative          = 'Logs'

        RequiredFiles            = @('Bin\TemplateServer.exe','Config')
        InstallMarkers           = @('Bin','Config')

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 27017 }
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
                'Template module is shown only in test builds and excluded from release builds.',
                'Replace metadata, install validation, runtime layout, launch arguments, and schema values when creating a real game module.',
                'SteamCMD is the default install/update/verify pattern in the template.',
                'Steam login defaults to anonymous. Only add username/password handling when the target game truly requires it.',
                'Mods are driven by Get-UGSMGameTEMPLATEModsDefinition and shared helper functions.',
                'Do not add profile sync or copy-back behavior to new game modules.'
            )
        }
    }
}

function Get-UGSMGameTEMPLATEInstallDefinition {
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
            throw 'TEMPLATE install definition failed: InstallPath could not be resolved.'
        }

        $InstallPath = Join-Path $steamRoot 'steamapps\common\TEMPLATE'
    }

    $meta = Get-UGSMGameTEMPLATEMetadata

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
        LogRootPath          = Join-Path (Join-Path $InstallPath $meta.Id) 'Saved\Logs'
    }
}

function Get-UGSMGameTEMPLATEAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameTEMPLATEProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'TEMPLATE' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameTEMPLATEAppDataRoot) 'Profiles')
}

function Get-UGSMGameTEMPLATETemplateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameTEMPLATEAppDataRoot) 'Templates\TEMPLATE')
}

function Get-UGSMGameTEMPLATEProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameTEMPLATEProfileBaseRoot) 'TEMPLATE') $ProfileName)
}


function Get-UGSMGameTEMPLATERuntimeRoot {
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
            $profileRoot = Get-UGSMGameTEMPLATEProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'TEMPLATE runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameTEMPLATEPath {
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

function New-UGSMGameTEMPLATEDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "TEMPLATE junction target was not found: $TargetPath"
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

        Remove-UGSMGameTEMPLATEPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "TEMPLATE junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameTEMPLATEFilesToRuntime {
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

    Copy-UGSMGameTEMPLATEDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameTEMPLATERuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameTEMPLATERuntimeRoot -Instance $Instance
    $runtimeInstallRoot = Join-Path $runtimeRoot 'Install'
    $runtimeGameRoot = Join-Path $runtimeInstallRoot 'TEMPLATE'
    $runtimeSavedRoot = Join-Path $runtimeGameRoot 'Saved'

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeGameRoot       = $runtimeGameRoot
        RuntimeSavedRoot      = $runtimeSavedRoot
        RuntimeConfigRootPath = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
        RuntimeSaveRootPath   = Join-Path $runtimeSavedRoot 'SaveFiles'
        RuntimeLogRootPath    = Join-Path $runtimeSavedRoot 'Logs'
        RuntimeServerExePath  = Join-Path $runtimeInstallRoot 'TEMPLATE\Binaries\Win64\TEMPLATEServer.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = Join-Path ([string]$InstallDefinition.InstallPath) 'TEMPLATE'

    }
}

function Resolve-UGSMGameTEMPLATEDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameTEMPLATEProfilePaths -Instance $Instance

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

function Ensure-UGSMGameTEMPLATERuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameTEMPLATERuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition
    $sharedInstallRoot = [string]$InstallDefinition.InstallPath
    $sharedGameRoot = Join-Path $sharedInstallRoot 'TEMPLATE'

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeInstallRoot, $runtime.RuntimeGameRoot, $runtime.RuntimeSavedRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $sharedInstallRoot -PathType Container) {
        foreach ($child in @(Get-ChildItem -LiteralPath $sharedInstallRoot -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtime.RuntimeInstallRoot $child.Name

            if ($child.PSIsContainer -and $child.Name -ieq 'TEMPLATE') {
                continue
            }

            if ($child.PSIsContainer) {
                New-UGSMGameTEMPLATEDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
            }
            else {
                Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $sharedGameRoot -PathType Container)) {
        throw "TEMPLATE runtime layout failed: Shared TEMPLATE root was not found: $sharedGameRoot"
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $sharedGameRoot -Force -ErrorAction SilentlyContinue)) {
        $targetPath = Join-Path $runtime.RuntimeGameRoot $child.Name

        if ($child.PSIsContainer -and $child.Name -ieq 'Saved') {
            continue
        }

        if ($child.PSIsContainer) {
            New-UGSMGameTEMPLATEDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $runtime
}

function Initialize-UGSMGameTEMPLATERuntimeData {
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
        Copy-UGSMGameTEMPLATEFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameTEMPLATEFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameTEMPLATEDirectoryContent {
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

function Get-UGSMGameTEMPLATERunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'TEMPLATEServer.exe'" -ErrorAction Stop)
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

function Start-UGSMGameTEMPLATEBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "TEMPLATE server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'TEMPLATEServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM TEMPLATEServer.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'TEMPLATEServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'TEMPLATEServer' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameTEMPLATETemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameTEMPLATEInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameTEMPLATEInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "TEMPLATE install is not valid at '$InstallPath'."
    }

    $templateRoot = Get-UGSMGameTEMPLATETemplateRoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    $templateSaveRoot = Join-Path $templateRoot 'SaveFiles'

    New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null

    $hasTemplateConfig = (Test-Path -LiteralPath $templateConfigRoot -PathType Container) -and @(
        Get-ChildItem -LiteralPath $templateConfigRoot -File -Force -ErrorAction SilentlyContinue
    ).Count -gt 0

    $sourceConfigRoot = [string]$definition.ConfigRootPath
    $sourceSaveRoot = [string]$definition.SaveRootPath

    $needsBootstrap = $ForceRefresh.IsPresent -or -not $hasTemplateConfig
    if (-not $needsBootstrap) {
        $needsBootstrap = -not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)
    }

    $bootstrapResult = $null
    if ($needsBootstrap) {
        $bootstrapResult = Start-UGSMGameTEMPLATEBootstrapProcess -ServerExecutablePath $definition.ServerExecutablePath -WorkingDirectory $InstallPath -BootstrapSeconds $BootstrapSeconds
        if (-not $bootstrapResult.Exited) {
            throw ('TEMPLATE bootstrap server did not shut down cleanly. Remaining PIDs: {0}' -f (($bootstrapResult.RemainingPids -join ', ')))
        }
    }

    if (-not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)) {
        throw "TEMPLATE bootstrap did not generate a config folder: $sourceConfigRoot"
    }

    $generatedConfigFiles = @(Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue)
    if ($generatedConfigFiles.Count -eq 0) {
        throw "TEMPLATE bootstrap completed, but no generated config files were found in: $sourceConfigRoot"
    }

    Copy-UGSMGameTEMPLATEDirectoryContent -Source $sourceConfigRoot -Destination $templateConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')

    New-Item -ItemType Directory -Path $templateSaveRoot -Force | Out-Null

    return [pscustomobject]@{
        GameId                       = 'TEMPLATE'
        InstallPath          = $InstallPath
        TemplateRoot         = $templateRoot
        TemplateConfigRoot   = $templateConfigRoot
        TemplateSaveRoot     = $templateSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $needsBootstrap
        BootstrapResult      = $bootstrapResult
        GeneratedConfigFiles = @($generatedConfigFiles.Name)
    }
}

function Initialize-UGSMGameTEMPLATEProfile {
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
        throw 'ProfileName could not be resolved for TEMPLATE profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a TEMPLATE profile.'
    }

    $templateRoot = Get-UGSMGameTEMPLATETemplateRoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    if (-not (Test-Path -LiteralPath $templateConfigRoot -PathType Container)) {
        throw 'TEMPLATE template does not exist yet. Install or repair TEMPLATE first so the template can be built.'
    }

    $profileRoot = Get-UGSMGameTEMPLATEProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

    $runtimeRoot = $profileRoot
    $runtimeInstallRoot = $runtimeRoot
    $runtimeGameRoot = Join-Path $runtimeInstallRoot 'TEMPLATE'
    $runtimeSavedRoot = Join-Path $runtimeGameRoot 'Saved'
    $runtimeConfigRoot = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
    $runtimeSaveRoot = Join-Path $runtimeSavedRoot 'SaveFiles'
    $runtimeLogsRoot = Join-Path $runtimeSavedRoot 'Logs'

    # create runtime folders first
    New-Item -ItemType Directory -Path $runtimeConfigRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $runtimeSaveRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $runtimeLogsRoot -Force | Out-Null

    # seed template config only for missing files
    $templateFiles = @(Get-ChildItem -LiteralPath $templateConfigRoot -File -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($file in $templateFiles) {
        $relative = $file.FullName.Substring($templateConfigRoot.Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }

        $targetPath = Join-Path $runtimeConfigRoot $relative
        $targetParent = Split-Path -Parent $targetPath

        if (-not [string]::IsNullOrWhiteSpace($targetParent) -and -not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }

        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
        }
    }

    Copy-UGSMGameTEMPLATEDirectoryContent -Source $templateConfigRoot -Destination $runtimeConfigRoot -ClearDestination

    $serverSettingsPath = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
    if (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf) {
        try {
            $content = Get-Content -LiteralPath $serverSettingsPath -Raw

            foreach ($candidateKey in @('server_name', 'ServerName')) {
                if ($content -match ('(?im)^\s*' + [regex]::Escape($candidateKey) + '\s*=')) {
                    $content = [Regex]::Replace($content, ('(?im)^\s*' + [regex]::Escape($candidateKey) + '\s*=.*$'), ('{0}={1}' -f $candidateKey, $effectiveProfileName))
                }
            }

            foreach ($candidateKey in @('server_description', 'ServerDescription')) {
                if ($content -match ('(?im)^\s*' + [regex]::Escape($candidateKey) + '\s*=')) {
                    $content = [Regex]::Replace($content, ('(?im)^\s*' + [regex]::Escape($candidateKey) + '\s*=.*$'), ('{0}=UGSM TEMPLATE Profile - {1}' -f $candidateKey, $effectiveProfileName))
                }
            }

            Set-Content -LiteralPath $serverSettingsPath -Value $content -Encoding UTF8
        }
        catch {
        }
    }

    return [pscustomobject]@{
        GameId                       = 'TEMPLATE'
        InstanceId         = $instanceId
        ProfileName        = $effectiveProfileName
        InstallPath        = $effectiveInstallPath
        ProfileRoot        = $profileRoot
        RuntimeRoot        = $runtimeRoot
        ConfigRoot         = $runtimeConfigRoot
        SaveRoot           = $runtimeSaveRoot
        LogsRoot           = $runtimeLogsRoot
        TemplateRoot       = $templateRoot
        TemplateConfigRoot = $templateConfigRoot
        Initialized        = $true
        CopiedFiles        = @(
            Get-ChildItem -LiteralPath $runtimeConfigRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName.Substring($profileRoot.Length).TrimStart('\') }
        )
    }
}

function Test-UGSMGameTEMPLATEInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameTEMPLATEInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'TEMPLATE validation failed: InstallPath could not be resolved.'
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
        GameId                       = 'TEMPLATE'
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

function Start-UGSMGameTEMPLATEInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'TEMPLATE start failed: Instance was null.'
    }

    $validation = Test-UGSMGameTEMPLATEInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'TEMPLATE start failed: TEMPLATE is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGameTEMPLATEInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'TEMPLATE start failed: Install definition could not be resolved.'
    }

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGameTEMPLATEProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "TEMPLATE start failed: Profile path was not found: $profilePath"
    }

    $runtime = Ensure-UGSMGameTEMPLATERuntimeLayout -Instance $Instance -InstallDefinition $installDef

    $runtimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
    $runtimeSaveRoot = [string]$runtime.RuntimeSaveRootPath
    $serverSettingsPath = Join-Path $runtimeConfigRoot 'ServerSettings.ini'

    if (-not (Test-Path -LiteralPath $runtimeConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeConfigRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $runtimeSaveRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeSaveRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf)) {
        throw "TEMPLATE start failed: Runtime ServerSettings.ini was not found: $serverSettingsPath"
    }

    $serverExe = [string]$runtime.RuntimeServerExePath
    $workingDirectory = Split-Path -Parent $serverExe
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "TEMPLATE start failed: Runtime server executable was not found: $serverExe"
    }

    $proc = Start-Process `
        -FilePath $serverExe `
        -ArgumentList @('-log', '-nobattleye') `
        -WorkingDirectory $workingDirectory `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'TEMPLATE start failed: Start-Process did not return a valid process.'
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

    try {
        $runtimeMarker = Join-Path $runtime.RuntimeSaveRootPath 'UGSM.Runtime.json'
        $runtimeData = [pscustomobject]@{
            InstanceId        = [string]$Instance.Id
            GameId                       = 'TEMPLATE'
            ProfilePath       = $profilePath
            RuntimeRoot       = [string]$runtime.RuntimeRoot
            RuntimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
            RuntimeSaveRoot   = [string]$runtime.RuntimeSaveRootPath
            RuntimeLogRoot    = [string]$runtime.RuntimeLogRootPath
            Pid               = $gamePid
            StartedAtUtc      = [DateTime]::UtcNow.ToString('o')
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

function Stop-UGSMGameTEMPLATEInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'TEMPLATE stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameTEMPLATEInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'TEMPLATE stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameTEMPLATERuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
        throw ("TEMPLATE stop failed: Process {0} is still running." -f $targetProcessId)
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

function Register-UGSMGameTEMPLATEModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameTEMPLATEMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameTEMPLATEMetadata'
            TestInstall       = 'Test-UGSMGameTEMPLATEInstall'
            TestInstance      = 'Test-UGSMGameTEMPLATEInstance'
            EnsureTemplate    = 'Ensure-UGSMGameTEMPLATETemplate'
            InitializeProfile = 'Initialize-UGSMGameTEMPLATEProfile'
            Start             = 'Start-UGSMGameTEMPLATEInstance'
            Stop              = 'Stop-UGSMGameTEMPLATEInstance'

            BuildEditor       = 'New-UGSMGameTEMPLATEInstanceEditor'
            SaveEditor        = 'Save-UGSMGameTEMPLATEInstanceEditor'
        }
    }
}


function Get-UGSMGameTEMPLATEBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameTEMPLATEProfilePaths -Instance $Instance

        $settingsTargets = @(
            @{ Path = $paths.ServerSettingsPath;          Relative = 'Config\WindowsServer\ServerSettings.ini'; Label = 'Template server settings INI' },
            @{ Path = $paths.GameplayJsonPath;            Relative = 'Config\WindowsServer\Gameplay.json';      Label = 'Template gameplay JSON' },
            @{ Path = $paths.GameplayXmlPath;             Relative = 'Config\WindowsServer\Gameplay.xml';       Label = 'Template gameplay XML' },
            @{ Path = $paths.ServerCfgPath;               Relative = 'Config\WindowsServer\Server.cfg';          Label = 'Template server CFG' },
            @{ Path = $paths.AdminUsersPath;              Relative = 'Config\WindowsServer\AdminUsers.txt';     Label = 'Template admin users list' },
            @{ Path = $paths.ExclusiveUsersPath;          Relative = 'Config\WindowsServer\ExclusiveUsers.txt'; Label = 'Template exclusive users list' },
            @{ Path = $paths.WhitelistedUsersPath;        Relative = 'Config\WindowsServer\WhitelistedUsers.txt'; Label = 'Template whitelist users list' },
            @{ Path = $paths.BannedUsersPath;             Relative = 'Config\WindowsServer\BannedUsers.txt';    Label = 'Template banned users list' },
            @{ Path = $paths.SilencedUsersPath;           Relative = 'Config\WindowsServer\SilencedUsers.txt';  Label = 'Template silenced users list' }
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
    if ($Scope -in @('Mods','All')) {
        # Example:
        # [void]$targets.Add([pscustomobject]@{
        #     SourcePath   = Join-Path $paths.ConfigRoot 'UGSM_ManagedMods.json'
        #     RelativePath = 'Mods\UGSM_ManagedMods.json'
        #     Label        = 'Template managed mods manifest'
        # })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameTEMPLATEManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'Template managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameTEMPLATEBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'TEMPLATE' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameTEMPLATELog -Level 'WARN' -Message ('Template managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameTEMPLATEProfilePaths {
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
        $profileRoot = Get-UGSMGameTEMPLATEProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'TEMPLATE' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'TEMPLATE profile paths could not be resolved for the selected instance.'
    }

    $runtimeRoot = Get-UGSMGameTEMPLATERuntimeRoot -Instance $Instance
    $runtimeConfigRoot = Join-Path $runtimeRoot 'TEMPLATE\Saved\Config\WindowsServer'
    $runtimeSaveRoot = Join-Path $runtimeRoot '\TEMPLATE\Saved\SaveFiles'
    $runtimeLogRoot = Join-Path $runtimeRoot '\TEMPLATE\Saved\Logs'

    $runtimeMarkerPath = Join-Path $runtimeSaveRoot 'UGSM.Runtime.json'
    $runtimeDatabasePath = Join-Path $runtimeSaveRoot 'TEMPLATE.db'

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

        PrimaryIniPath              = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
        PrimaryJsonPath             = Join-Path $runtimeConfigRoot 'Gameplay.json'
        PrimaryXmlPath              = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        PrimaryCfgPath              = Join-Path $runtimeConfigRoot 'Server.cfg'

        ServerSettingsPath          = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
        GameplayJsonPath            = Join-Path $runtimeConfigRoot 'Gameplay.json'
        GameplayXmlPath             = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        ServerCfgPath               = Join-Path $runtimeConfigRoot 'Server.cfg'

        AdminUsersPath              = Join-Path $runtimeConfigRoot 'AdminUsers.txt'
        ExclusiveUsersPath          = Join-Path $runtimeConfigRoot 'ExclusiveUsers.txt'
        WhitelistedUsersPath        = Join-Path $runtimeConfigRoot 'WhitelistedUsers.txt'
        BannedUsersPath             = Join-Path $runtimeConfigRoot 'BannedUsers.txt'
        SilencedUsersPath           = Join-Path $runtimeConfigRoot 'SilencedUsers.txt'

        RuntimePrimaryIniPath       = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
        RuntimePrimaryJsonPath      = Join-Path $runtimeConfigRoot 'Gameplay.json'
        RuntimePrimaryXmlPath       = Join-Path $runtimeConfigRoot 'Gameplay.xml'
        RuntimePrimaryCfgPath       = Join-Path $runtimeConfigRoot 'Server.cfg'

        RuntimeServerSettingsPath   = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
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

function Read-UGSMGameTEMPLATEIniFile {
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

function Get-UGSMGameTEMPLATEIniValue {
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

function Set-UGSMGameTEMPLATEIniValue {
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

function Read-UGSMGameTEMPLATEStringListFile {
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

function Write-UGSMGameTEMPLATEStringListFile {
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


function Ensure-UGSMGameTEMPLATEParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameTEMPLATEJsonFile {
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

function Write-UGSMGameTEMPLATEJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameTEMPLATEParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGameTEMPLATEXmlFile {
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

function Write-UGSMGameTEMPLATEXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameTEMPLATEParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameTEMPLATECfgFile {
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

function Set-UGSMGameTEMPLATECfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameTEMPLATEParentDirectory -Path $Path

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
function Test-UGSMGameTEMPLATEPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameTEMPLATEPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameTEMPLATEPSSQLiteInstalled)
}

function Get-UGSMGameTEMPLATEElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameTEMPLATEPSSQLiteInstalled)) {
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

function Save-UGSMGameTEMPLATEElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameTEMPLATEPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'TEMPLATE.db was not found.'
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


function Resolve-UGSMGameTEMPLATEEditorFieldPath {
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

function ConvertTo-UGSMGameTEMPLATEEditorFieldValue {
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
        default {
            return [string]$Control.Text
        }
    }
}


function Get-UGSMGameTEMPLATEInstanceDefinitionPath {
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

function Save-UGSMGameTEMPLATEInstanceDefinition {
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

    $definitionPath = Get-UGSMGameTEMPLATEInstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameTEMPLATEInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameTEMPLATEProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameTEMPLATEInstanceDiscordShape -Instance $Instance
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

    Invoke-UGSMGameTEMPLATEManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before Template settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameTEMPLATEEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameTEMPLATEEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("TEMPLATE save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameTEMPLATEStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control
                Set-UGSMGameTEMPLATEIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control
                Set-UGSMGameTEMPLATEIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control
                Set-UGSMGameTEMPLATEIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control
                Set-UGSMGameTEMPLATEIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameTEMPLATEEditorFieldValue -Field $field -Control $control)
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
            [void](Save-UGSMGameTEMPLATEInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved Template settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameTEMPLATEInstanceEditor {
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
    foreach ($themeName in @('Background','Surface','Input','Text','Muted','Accent','AccentBlue','Button','Danger','Success')) {
        if (-not $Theme.ContainsKey($themeName) -or $null -eq $Theme[$themeName]) {
            if ($baseTheme -and $baseTheme.ContainsKey($themeName)) { $Theme[$themeName] = $baseTheme[$themeName] }
        }
    }

    $Instance = Ensure-UGSMGameTEMPLATEInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameTEMPLATEProfilePaths -Instance $Instance
    $schema = Get-UGSMGameTEMPLATEEditorSchema
    $iniData = Read-UGSMGameTEMPLATEIniFile -Path $paths.ServerSettingsPath
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

    function Get-TEMPLATESafeIniValue {
        param([hashtable]$Field)
        try {
            return [string](Get-UGSMGameTEMPLATEIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-TEMPLATESafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-TEMPLATETextBox {
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

    function New-TEMPLATEStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-TEMPLATETextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-TEMPLATENarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-TEMPLATEElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits TEMPLATE.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMGameTEMPLATEPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in TEMPLATE.db.')
                return
            }

            $dbPath = Resolve-UGSMGameTEMPLATEDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('TEMPLATE.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('TEMPLATE.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameTEMPLATEElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading TEMPLATE.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameTEMPLATEPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameTEMPLATEDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'TEMPLATE.db path could not be resolved for this instance.' }
                    Save-UGSMGameTEMPLATEElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to TEMPLATE.db: ' + $dbPath }
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

    function Add-TEMPLATEFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the template editor can render any supported schema shape.
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
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameTEMPLATEModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the template Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-TEMPLATENarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-TEMPLATESafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-TEMPLATENarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-TEMPLATESafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-TEMPLATENarrowHost
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
                    $rawValue = Get-TEMPLATESafeIniValue -Field $Field
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
                    $control = New-TEMPLATEStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-TEMPLATESafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-TEMPLATEStretchTextBox -MaskSecret
                    $control.Text = [string](Get-TEMPLATESafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-TEMPLATEStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-TEMPLATESafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-TEMPLATETextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameTEMPLATEEditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-TEMPLATENarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor $Theme.Button
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE action failed: ' + $_.Exception.Message } }
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

                    New-TEMPLATEElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-TEMPLATEStretchTextBox
                    $control.Text = [string](Get-TEMPLATESafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('TEMPLATE field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Danger
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-TEMPLATEEditorContent {
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
            Add-TEMPLATEFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('Template Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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
        $tabs.SuspendLayout()
        [void]$root.Controls.Add($tabs, 0, 2)

        foreach ($tabDef in @($schema.Tabs)) {
            $tabPage = New-Object System.Windows.Forms.TabPage
            $tabPage.SuspendLayout()
            try {
                $tabPage.Text = [string]$tabDef.Title
                $tabPage.BackColor = $Theme.Background
                [void]$tabs.TabPages.Add($tabPage)

                # Mods tab is owned by UGSM_Game_Helper.ps1. The game module only creates
                # the TabPage host and passes the instance/mod definition into the shared renderer.
                if ([string]$tabDef.Title -eq 'Mods') {
                    $modsTabFeatures = Get-UGSMGameTEMPLATESupportedFeatures
                    if ([bool]$modsTabFeatures.Mods) {
                        try {
                            $modsDefinition = Get-UGSMGameTEMPLATEModsDefinition
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
                            $err = New-UGSMLabel -Text ('Template shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color $Theme.Danger
                            [void]$tabPage.Controls.Add($err)
                            if ($StatusLabel) { $StatusLabel.Text = 'Template shared Mods tab failed: ' + $_.Exception.Message }
                        }
                        continue
                    }
                }

                if ($tabDef.PSObject.Properties.Name -contains 'SubTabs' -and @($tabDef.SubTabs).Count -gt 0) {
                    $subTabs = New-Object System.Windows.Forms.TabControl
                    $subTabs.Dock = 'Fill'
                    $subTabs.SuspendLayout()
                    [void]$tabPage.Controls.Add($subTabs)

                    foreach ($subDef in @($tabDef.SubTabs)) {
                        $subPage = New-Object System.Windows.Forms.TabPage
                        $subPage.SuspendLayout()
                        $subPage.Text = [string]$subDef.Title
                        $subPage.BackColor = $Theme.Background
                        [void]$subTabs.TabPages.Add($subPage)
                        New-TEMPLATEEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                        $subPage.ResumeLayout($false)
                    }

                    $subTabs.ResumeLayout($false)
                }
                else {
                    New-TEMPLATEEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
                }
            }
            finally {
                $tabPage.ResumeLayout($false)
            }
        }

        $tabs.ResumeLayout($true)

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameTEMPLATEInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved TEMPLATE profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameTEMPLATEInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'TEMPLATE profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameTEMPLATEOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'TEMPLATE open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("TEMPLATE open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'TEMPLATE open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("TEMPLATE open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("TEMPLATE open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameTEMPLATEEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'TEMPLATE action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameTEMPLATEProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("TEMPLATE action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("TEMPLATE action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameTEMPLATEEditorAction {
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

    $resolvedPath = Resolve-UGSMGameTEMPLATEEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameTEMPLATEOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameTEMPLATEEditorSchema {
    [CmdletBinding()]
    param()

    if ($script:UGSMGameTEMPLATEEditorSchemaCache) {
        return $script:UGSMGameTEMPLATEEditorSchemaCache
    }

    $actions = @{
        OpenPrimaryIni     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameTEMPLATEEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryIni'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ServerSettings.ini.' }
        OpenPrimaryJson    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameTEMPLATEEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryJson'    -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened Gameplay.json.' }
        OpenPrimaryXml     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameTEMPLATEEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryXml'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened Gameplay.xml.' }
        OpenPrimaryCfg     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameTEMPLATEEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryCfg'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened server.cfg.' }
    }

    $features = Get-UGSMGameTEMPLATESupportedFeatures

    # ============================================================
    # TEMPLATE GAME SCHEMA
    # This is the main section to edit when copying this file.
    # Keep fields generic here. Add game-specific tabs/fields only after
    # copying the template into a real UGSM_Game_<Game>.ps1 module.
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
                Description = 'Basic identity and access settings used by most dedicated servers.'
                Fields      = @(
                    @{ Id = 'ServerName'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'ServerName'; Label = 'Server Name'; DefaultValue = 'My UGSM Server'; Hint = 'Public server name shown in server browsers or connection lists.' }
                    @{ Id = 'ServerDescription'; Type = 'MultilineText'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'ServerDescription'; Label = 'Server Description'; DefaultValue = ''; Hint = 'Optional description or message of the day.' }
                    @{ Id = 'ServerPassword'; Type = 'Password'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'ServerPassword'; Label = 'Server Password'; DefaultValue = ''; Hint = 'Optional. Leave blank for no password. Masked on screen.' }
                    @{ Id = 'AdminPassword'; Type = 'Password'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'AdminPassword'; Label = 'Admin Password'; DefaultValue = ''; Hint = 'Admin password if the game supports one. Masked on screen.' }
                    @{ Id = 'MaxPlayers'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'MaxPlayers'; Label = 'Max Players'; DefaultValue = 16; Min = 1; Max = 512; Decimals = 0; Hint = 'Maximum player slots.' }
                    @{ Id = 'PublicServer'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Server'; Key = 'PublicServer'; Label = 'Public Server'; DefaultValue = $true; Hint = 'Show server publicly if the game supports a browser.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network / Ports'
                Description = 'Common network and RCON fields. Remove or rename these for games that use different port names.'
                Fields      = @(
                    @{ Id = 'BindIp'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'Network'; Key = 'BindIp'; Label = 'Bind IP'; DefaultValue = '0.0.0.0'; Hint = 'Use 0.0.0.0 unless the game needs a specific network adapter.' }
                    @{ Id = 'GamePort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Network'; Key = 'GamePort'; Label = 'Game Port'; DefaultValue = 27015; Min = 1; Max = 65535; Decimals = 0; Hint = 'Primary gameplay port.' }
                    @{ Id = 'QueryPort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Network'; Key = 'QueryPort'; Label = 'Query Port'; DefaultValue = 27016; Min = 1; Max = 65535; Decimals = 0; Hint = 'Steam/server-browser query port if used.' }
                    @{ Id = 'RconEnabled'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Enabled'; Label = 'Enable RCON'; DefaultValue = $true; Hint = 'Enable remote console if supported.' }
                    @{ Id = 'RconPort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Port'; Label = 'RCON Port'; DefaultValue = 27017; Min = 1; Max = 65535; Decimals = 0; Hint = 'RCON/Telnet/admin port if supported.' }
                    @{ Id = 'RconPassword'; Type = 'Password'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Password'; Label = 'RCON Password'; DefaultValue = ''; Hint = 'Remote console password. Masked on screen.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Player Rules'
                Description = 'Common rules used by many dedicated servers.'
                Fields      = @(
                    @{ Id = 'AllowPvp'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Rules'; Key = 'AllowPvp'; Label = 'Allow PvP'; DefaultValue = $true; Hint = 'Whether player-vs-player damage is enabled.' }
                    @{ Id = 'AllowFriendlyFire'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Rules'; Key = 'AllowFriendlyFire'; Label = 'Allow Friendly Fire'; DefaultValue = $false; Hint = 'Whether allied/team damage is enabled.' }
                    @{ Id = 'AllowVoiceChat'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Rules'; Key = 'AllowVoiceChat'; Label = 'Allow Voice Chat'; DefaultValue = $true; Hint = 'Enable in-game voice chat if supported.' }
                    @{ Id = 'AllowTextChat'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Rules'; Key = 'AllowTextChat'; Label = 'Allow Text Chat'; DefaultValue = $true; Hint = 'Enable in-game text chat if supported.' }
                    @{ Id = 'WhitelistEnabled'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'Rules'; Key = 'WhitelistEnabled'; Label = 'Enable Whitelist'; DefaultValue = $false; Hint = 'Enable whitelist enforcement if supported.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Gameplay'
                Description = 'Generic gameplay multipliers that are common across survival/server games.'
                Fields      = @(
                    @{ Id = 'Difficulty'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'Difficulty'; Label = 'Difficulty'; DefaultValue = 1; Min = 0; Max = 100; Decimals = 0; Hint = 'Generic difficulty value. Replace with a dropdown or real game values when known.' }
                    @{ Id = 'ExperienceMultiplier'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'ExperienceMultiplier'; Label = 'Experience Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 3; Increment = '0.1'; Hint = 'XP gain multiplier.' }
                    @{ Id = 'HarvestMultiplier'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'HarvestMultiplier'; Label = 'Harvest/Gather Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 3; Increment = '0.1'; Hint = 'Resource gathering multiplier.' }
                    @{ Id = 'LootMultiplier'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'LootMultiplier'; Label = 'Loot Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 3; Increment = '0.1'; Hint = 'Loot amount/quality multiplier if supported.' }
                    @{ Id = 'DayLengthMultiplier'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'DayLengthMultiplier'; Label = 'Day Length Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 3; Increment = '0.1'; Hint = 'Day/night speed or duration multiplier.' }
                    @{ Id = 'SaveIntervalMinutes'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Gameplay'; Key = 'SaveIntervalMinutes'; Label = 'Auto Save Interval (Minutes)'; DefaultValue = 15; Min = 1; Max = 1440; Decimals = 0; Hint = 'How often the game should save, if configurable.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Files / Lists'
                Description = 'Common text-file lists used by many games. Remove any lists the real game does not use.'
                Fields      = @(
                    @{ Id = 'AdminUsers'; Type = 'StringList'; Path = 'AdminUsers.txt'; Label = 'Admin Users'; Hint = 'One user/SteamID/account ID per line.' }
                    @{ Id = 'WhitelistedUsers'; Type = 'StringList'; Path = 'Whitelist.txt'; Label = 'Whitelist'; Hint = 'One allowed user/SteamID/account ID per line.' }
                    @{ Id = 'BannedUsers'; Type = 'StringList'; Path = 'Bans.txt'; Label = 'Banned Users'; Hint = 'One banned user/SteamID/account ID per line.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Advanced'
                Description = 'Manual overrides and quick access for anything not surfaced in the form yet.'
                Fields      = @(
                    @{ Id = 'ExtraStartupArguments'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'Advanced'; Key = 'ExtraStartupArguments'; Label = 'Extra Startup Arguments'; DefaultValue = ''; Hint = 'Optional extra command-line arguments. Do not put passwords or tokens here unless the game requires it.' }
                    @{ Id = 'RawConfigOverrides'; Type = 'MultilineText'; File = 'ServerSettings.ini'; Section = 'Advanced'; Key = 'RawConfigOverrides'; Label = 'Raw Config Overrides'; DefaultValue = ''; Hint = 'Optional manual notes/overrides. Replace with real config handling in a copied game module.' }
                    @{ Id = 'OpenPrimaryIni'; Type = 'ActionButton'; Label = 'ServerSettings.ini'; ButtonText = 'Open ServerSettings.ini'; Action = $actions.OpenPrimaryIni; Hint = 'Opens the main generic INI file for manual editing.' }
                    @{ Id = 'OpenPrimaryJson'; Type = 'ActionButton'; Label = 'Gameplay.json'; ButtonText = 'Open Gameplay.json'; Action = $actions.OpenPrimaryJson; Hint = 'Opens a generic JSON file if this game uses JSON settings.' }
                    @{ Id = 'OpenPrimaryXml'; Type = 'ActionButton'; Label = 'Gameplay.xml'; ButtonText = 'Open Gameplay.xml'; Action = $actions.OpenPrimaryXml; Hint = 'Opens a generic XML file if this game uses XML settings.' }
                    @{ Id = 'OpenPrimaryCfg'; Type = 'ActionButton'; Label = 'server.cfg'; ButtonText = 'Open server.cfg'; Action = $actions.OpenPrimaryCfg; Hint = 'Opens a generic CFG file if this game uses CFG settings.' }
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
                            $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('Template ' + [string]$Instance.Name)
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
        $modsDefinition = Get-UGSMGameTEMPLATEModsDefinition
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

    $script:UGSMGameTEMPLATEEditorSchemaCache = $resultSchema
    return $resultSchema
}
