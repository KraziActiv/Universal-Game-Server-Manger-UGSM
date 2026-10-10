# UGSM Game Factorio
# Hidden golden Factorio for future UGSM game modules.
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace Factorio with the real game token
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

function Test-UGSMGameFactorioVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameFactorioLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameFactorioLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_Factorio)) { return $true }
    return $false
}

function ConvertTo-UGSMGameFactorioSafeLogText {
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
        # the Factorio itself does not add portability-scan false positives.
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

function Write-UGSMGameFactorioLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGameFactorioVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameFactorioSafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameFactorioSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:Factorio' -Message $safeMessage
    }
}

function Write-UGSMGameFactorioPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older Factorio notes. New modules should use Write-UGSMGameFactorioLog.
    Write-UGSMGameFactorioLog -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGameFactorioInstanceDiscordShape {
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


function Get-UGSMGameFactorioSupportedFeatures {
    [CmdletBinding()]
    param()

    # ============================================================
    # Factorio SUPPORTED FEATURES
    # This is the first section to edit when copying the Factorio.
    # Turn features on/off here, then edit the schema sections below.
    # Test builds show the Factorio as a real game so optional UI can be previewed.
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
        Rcon          = $false
        GracefulStop  = $false

        # Set Mods=$true to preview the shared Mods tab in test builds.
        # Copied games can keep this on/off switch and only change ModTabMode/capabilities.
        Mods          = $false
        Workshop      = $false
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
        LuaFiles        = $true
        TextFiles       = $true
        PSSQLite        = $false

        ModCapabilities = [pscustomobject]@{
            # Standard Steam Workshop list/download/load-order tab.
            SteamWorkshop    = $false
            LoadOrder        = $false

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

function Get-UGSMGameFactorioModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameFactorioSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'Factorio' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
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
            GameId = 'Factorio'
        }
    }


    # Factorio Workshop App ID placeholder. Copied games must replace 000000 with
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

function Get-UGSMGameFactorioMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = Join-Path (Join-Path 'bin' 'x64') 'factorio.exe'
    $features = Get-UGSMGameFactorioSupportedFeatures
    $modsDefinition = Get-UGSMGameFactorioModsDefinition

    return [pscustomobject]@{
        Id                       = 'Factorio'
        Name                     = 'Factorio'
        Category                 = 'Crafting'
        Description              = 'Automation factory dedicated server. Steam login is required to install the Windows binaries.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 250
        IsVisible                = [bool]$features.IsVisible

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
        UseSteamArt              = $true

        SupportsInstall          = [bool]$features.Install
        SupportsUpdate           = [bool]$features.Update
        SupportsVerify           = [bool]$features.Verify
        SupportsRepair           = [bool]$features.Repair
        SupportsStart            = [bool]$features.Start
        SupportsStop             = [bool]$features.Stop
        SupportsMods             = $false
        SupportsWorkshop         = $false
        SupportsRcon             = $false
        SupportsBootstrap        = $false
        SupportsProfiles         = [bool]$features.Profiles
        SupportsInstanceUi       = [bool]$features.InstanceUi
        SupportedFeatures        = $features
        Mods                     = $modsDefinition
        ModTraits                = $modsDefinition

        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $true
        SteamLoginMode           = 'AccountRequired'
        SteamAppId               = '427520'
        SteamStoreAppId          = '427520'
        ServerExecutable         = 'factorio.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'config'
        SaveRootRelative         = 'saves'
        LogRootRelative          = 'logs'
        ModsRootRelative         = 'mods'

        RequiredFiles            = @('bin\x64\factorio.exe','data')
        InstallMarkers           = @('bin','data')

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 34197 }
        )

        GameTraits = [pscustomobject]@{
            UsesIniFiles        = $false
            UsesJsonFiles       = $true
            UsesXmlFiles        = $false
            UsesCfgFiles        = $false
            UsesTextFiles       = $true
            UsesPSSQLite        = $false
            UsesSharedBinaries  = $true
            ConfigInProfile     = $true
            SaveInProfile       = $true
            LogsInProfile       = $true
            CreatesSaveOnStart  = $true
            SpaceAgeProfileMode = 'ModsLater'
        }
    }
}



function Get-UGSMGameFactorioInstallDefinition {
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
                if (-not [string]::IsNullOrWhiteSpace($value)) { $steamRoot = $value; break }
            }
        }

        if ([string]::IsNullOrWhiteSpace($steamRoot)) {
            throw 'Factorio install definition failed: InstallPath could not be resolved.'
        }

        # UGSM's SteamCMD installer stores Steam apps under steamapps\common\<AppName>.
        $InstallPath = Join-Path $steamRoot 'steamapps\common\Factorio'
    }

    $meta = Get-UGSMGameFactorioMetadata

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
        ModsRootPath         = Join-Path $InstallPath $meta.ModsRootRelative
    }
}



function Get-UGSMGameFactorioAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameFactorioProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'Factorio' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameFactorioAppDataRoot) 'Profiles')
}

function Get-UGSMGameFactorioFactorioRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameFactorioAppDataRoot) 'Factorios\Factorio')
}

function Get-UGSMGameFactorioProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameFactorioProfileBaseRoot) 'Factorio') $ProfileName)
}


function Get-UGSMGameFactorioRuntimeRoot {
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
            $profileRoot = Get-UGSMGameFactorioProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'Factorio runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameFactorioPath {
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

function New-UGSMGameFactorioDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "Factorio junction target was not found: $TargetPath"
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

        Remove-UGSMGameFactorioPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "Factorio junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameFactorioFilesToRuntime {
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

    Copy-UGSMGameFactorioDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameFactorioRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InstallDefinition
    )

    $profileRoot = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profileRoot = [string]$Instance.ProfilePath
    }
    elseif ($Instance.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $profileRoot = Get-UGSMGameFactorioProfileRoot -ProfileName ([string]$Instance.Name)
    }
    else {
        throw 'Factorio runtime definition failed: ProfilePath could not be resolved.'
    }

    $configRoot = Join-Path $profileRoot 'config'
    $saveRoot   = Join-Path $profileRoot 'saves'
    $logRoot    = Join-Path $profileRoot 'logs'
    $modsRoot   = Join-Path $profileRoot 'mods'

    $instanceName = 'Factorio'
    if ($Instance.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $instanceName = ([string]$Instance.Name -replace '[\\/:*?"<>|]', '_')
    }

    return [pscustomobject]@{
        RuntimeRoot                = $profileRoot
        RuntimeInstallRoot         = [string]$InstallDefinition.InstallPath
        RuntimeGameRoot            = $profileRoot
        RuntimeSavedRoot           = $profileRoot
        RuntimeConfigRootPath      = $configRoot
        RuntimeSaveRootPath        = $saveRoot
        RuntimeLogRootPath         = $logRoot
        RuntimeModsRootPath        = $modsRoot
        RuntimeServerExePath       = [string]$InstallDefinition.ServerExecutablePath
        SharedInstallPath          = [string]$InstallDefinition.InstallPath
        SharedGameRoot             = [string]$InstallDefinition.InstallPath

        ServerSettingsPath         = Join-Path $configRoot 'server-settings.json'
        MapGenSettingsPath         = Join-Path $configRoot 'map-gen-settings.json'
        MapSettingsPath            = Join-Path $configRoot 'map-settings.json'
        ServerAdminListPath        = Join-Path $configRoot 'server-adminlist.json'
        ServerWhitelistPath        = Join-Path $configRoot 'server-whitelist.json'
        ServerBanListPath          = Join-Path $configRoot 'server-banlist.json'
        ServerIdPath               = Join-Path $configRoot 'server-id.json'
        ModListPath                = Join-Path $modsRoot 'mod-list.json'
        ConfigIniPath              = Join-Path $configRoot 'config.ini'
        SavePath                   = Join-Path $saveRoot ($instanceName + '.zip')
        CreateSaveLogPath          = Join-Path $logRoot 'create-save.log'
        ServerConsoleLogPath       = Join-Path $logRoot 'server-console.log'
        RuntimeMarkerPath          = Join-Path $profileRoot 'UGSM.Runtime.json'
    }
}



function Resolve-UGSMGameFactorioDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance

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

function Ensure-UGSMGameFactorioRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InstallDefinition
    )

    $runtime = Get-UGSMGameFactorioRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition

    foreach ($path in @(
        $runtime.RuntimeRoot,
        $runtime.RuntimeConfigRootPath,
        $runtime.RuntimeSaveRootPath,
        $runtime.RuntimeLogRootPath,
        $runtime.RuntimeModsRootPath
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path) -and -not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath ([string]$runtime.RuntimeServerExePath) -PathType Leaf)) {
        throw 'Factorio runtime layout failed: shared factorio.exe was not found.'
    }

    return $runtime
}



function Initialize-UGSMGameFactorioRuntimeData {
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
        Copy-UGSMGameFactorioFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameFactorioFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameFactorioDirectoryContent {
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

function Get-UGSMGameFactorioRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'factorio.exe'" -ErrorAction Stop)
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

function Start-UGSMGameFactorioBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "Factorio server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'factorio' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM factorio.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'factorio' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'factorio' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameFactorioFactorio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameFactorioInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameFactorioInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "Factorio install is not valid at '$InstallPath'."
    }

    $FactorioRoot = Get-UGSMGameFactorioFactorioRoot
    $FactorioConfigRoot = Join-Path $FactorioRoot 'Config\WindowsServer'
    $FactorioSaveRoot = Join-Path $FactorioRoot 'SaveFiles'

    New-Item -ItemType Directory -Path $FactorioRoot -Force | Out-Null

    $hasFactorioConfig = (Test-Path -LiteralPath $FactorioConfigRoot -PathType Container) -and @(
        Get-ChildItem -LiteralPath $FactorioConfigRoot -File -Force -ErrorAction SilentlyContinue
    ).Count -gt 0

    $sourceConfigRoot = [string]$definition.ConfigRootPath
    $sourceSaveRoot = [string]$definition.SaveRootPath

    $needsBootstrap = $ForceRefresh.IsPresent -or -not $hasFactorioConfig
    if (-not $needsBootstrap) {
        $needsBootstrap = -not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)
    }

    $bootstrapResult = $null
    if ($needsBootstrap) {
        $bootstrapResult = Start-UGSMGameFactorioBootstrapProcess -ServerExecutablePath $definition.ServerExecutablePath -WorkingDirectory $InstallPath -BootstrapSeconds $BootstrapSeconds
        if (-not $bootstrapResult.Exited) {
            throw ('Factorio bootstrap server did not shut down cleanly. Remaining PIDs: {0}' -f (($bootstrapResult.RemainingPids -join ', ')))
        }
    }

    if (-not (Test-Path -LiteralPath $sourceConfigRoot -PathType Container)) {
        throw "Factorio bootstrap did not generate a config folder: $sourceConfigRoot"
    }

    $generatedConfigFiles = @(Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue)
    if ($generatedConfigFiles.Count -eq 0) {
        throw "Factorio bootstrap completed, but no generated config files were found in: $sourceConfigRoot"
    }

    Copy-UGSMGameFactorioDirectoryContent -Source $sourceConfigRoot -Destination $FactorioConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')

    New-Item -ItemType Directory -Path $FactorioSaveRoot -Force | Out-Null

    return [pscustomobject]@{
        GameId                       = 'Factorio'
        InstallPath          = $InstallPath
        FactorioRoot         = $FactorioRoot
        FactorioConfigRoot   = $FactorioConfigRoot
        FactorioSaveRoot     = $FactorioSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $needsBootstrap
        BootstrapResult      = $bootstrapResult
        GeneratedConfigFiles = @($generatedConfigFiles.Name)
    }
}

function Ensure-UGSMGameFactorioDefaultProfileFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Runtime,
        [switch]$Force
    )

    foreach ($path in @($Runtime.RuntimeConfigRootPath, $Runtime.RuntimeSaveRootPath, $Runtime.RuntimeLogRootPath, $Runtime.RuntimeModsRootPath)) {
        if (-not (Test-Path -LiteralPath ([string]$path) -PathType Container)) {
            New-Item -ItemType Directory -Path ([string]$path) -Force | Out-Null
        }
    }

    $serverName = 'My UGSM Server'
    if ($Instance.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $serverName = [string]$Instance.Name
    }

    if ($Force -or -not (Test-Path -LiteralPath ([string]$Runtime.ServerSettingsPath) -PathType Leaf)) {
        $serverSettings = [ordered]@{
            name = $serverName
            description = 'Factorio server managed by UGSM.'
            tags = @('game','tags')
            max_players = 0
            visibility = [ordered]@{
                public = $false
                lan = $true
            }
            username = ''
            password = ''
            token = ''
            game_password = ''
            require_user_verification = $true
            max_upload_in_kilobytes_per_second = 0
            max_upload_slots = 5
            minimum_latency_in_ticks = 0
            max_heartbeats_per_second = 60
            ignore_player_limit_for_returning_players = $false
            allow_commands = 'admins-only'
            autosave_interval = 10
            autosave_slots = 5
            afk_autokick_interval = 0
            auto_pause = $true
            auto_pause_when_players_connect = $false
            only_admins_can_pause_the_game = $true
            autosave_only_on_server = $true
            non_blocking_saving = $false
            minimum_segment_size = 25
            minimum_segment_size_peer_count = 20
            maximum_segment_size = 100
            maximum_segment_size_peer_count = 10
        }
        Write-UGSMGameFactorioJsonFile -Path ([string]$Runtime.ServerSettingsPath) -Value $serverSettings
    }

    foreach ($jsonPath in @($Runtime.ServerAdminListPath, $Runtime.ServerWhitelistPath, $Runtime.ServerBanListPath)) {
        if ($Force -or -not (Test-Path -LiteralPath ([string]$jsonPath) -PathType Leaf)) {
            Write-UGSMGameFactorioJsonFile -Path ([string]$jsonPath) -Value @()
        }
    }

    # Map generation/settings files are intentionally not seeded yet. Factorio will use defaults for initial save creation.

if ($Force -or -not (Test-Path -LiteralPath ([string]$Runtime.ModListPath) -PathType Leaf)) {
        $modList = [ordered]@{
            mods = @(
                [ordered]@{ name = 'base'; enabled = $true }
            )
        }
        Write-UGSMGameFactorioJsonFile -Path ([string]$Runtime.ModListPath) -Value $modList
    }

    return $Runtime
}

function Initialize-UGSMGameFactorioProfile {

    [CmdletBinding()]
    param(
        [object]$Instance,
        [string]$ProfileName,
        [string]$InstallPath,
        [switch]$Force,

        # Compatibility only. The shared create-profile caller may pass this
        # from older bootstrap-capable modules. Factorio does not run bootstrap
        # or create a save during profile creation.
        [int]$BootstrapSeconds = 30,

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$IgnoredArguments
    )

    $effectiveProfileName = ''
    $effectiveInstallPath = ''
    $instanceId = ''

    if ($Instance) {
        if ($Instance.PSObject.Properties.Name -contains 'Name') { $effectiveProfileName = [string]$Instance.Name }
        if ($Instance.PSObject.Properties.Name -contains 'InstallPath') { $effectiveInstallPath = [string]$Instance.InstallPath }
        if ($Instance.PSObject.Properties.Name -contains 'Id') { $instanceId = [string]$Instance.Id }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) { $effectiveProfileName = [string]$ProfileName }
    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) { $effectiveInstallPath = [string]$InstallPath }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) { throw 'ProfileName could not be resolved for Factorio profile initialization.' }
    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) { throw 'InstallPath is required to initialize a Factorio profile.' }

    $installDef = Get-UGSMGameFactorioInstallDefinition -InstallPath $effectiveInstallPath
    $validation = Test-UGSMGameFactorioInstall -InstallPath $effectiveInstallPath
    if (-not $validation.IsValid) {
        $missingText = ''
        if ($validation -and $validation.MissingItems) { $missingText = (' Missing: ' + ((@($validation.MissingItems) | ForEach-Object { [string]$_ }) -join ', ')) }
        throw ('Factorio profile initialization failed: install is not valid at {0}.{1}' -f $effectiveInstallPath, $missingText)
    }

    $profileRoot = Get-UGSMGameFactorioProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($Instance) {
        if ($Instance.PSObject.Properties.Name -contains 'ProfilePath') { $Instance.ProfilePath = $profileRoot }
    }

    $profileObject = [pscustomobject]@{ Name = $effectiveProfileName; ProfilePath = $profileRoot }
    $runtime = Get-UGSMGameFactorioRuntimeDefinition -Instance $profileObject -InstallDefinition $installDef
    Ensure-UGSMGameFactorioRuntimeLayout -Instance $profileObject -InstallDefinition $installDef | Out-Null
    Ensure-UGSMGameFactorioDefaultProfileFiles -Instance ([pscustomobject]@{ Name = $effectiveProfileName }) -Runtime $runtime -Force:$Force | Out-Null

    return [pscustomobject]@{
        GameId             = 'Factorio'
        InstanceId         = $instanceId
        ProfileName        = $effectiveProfileName
        InstallPath        = $effectiveInstallPath
        ProfileRoot        = $profileRoot
        RuntimeRoot        = [string]$runtime.RuntimeRoot
        ConfigRoot         = [string]$runtime.RuntimeConfigRootPath
        SaveRoot           = [string]$runtime.RuntimeSaveRootPath
        LogsRoot           = [string]$runtime.RuntimeLogRootPath
        ModsRoot           = [string]$runtime.RuntimeModsRootPath
        ServerSettingsPath = [string]$runtime.ServerSettingsPath
        Initialized        = $true
        SavePath           = $null
    }
}

function Test-UGSMGameFactorioInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameFactorioInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'Factorio validation failed: InstallPath could not be resolved.'
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
        GameId                       = 'Factorio'
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

function Ensure-UGSMGameFactorioInitialSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$ServerExecutablePath
    )

    $safeSaveName = 'UGSM_Factorio'
    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $safeSaveName = ([string]$Instance.Name) -replace '[^\w\-. ]','_'
    }

    $savePath = Join-Path ([string]$Paths.SaveRoot) ($safeSaveName + '.zip')
    if (Test-Path -LiteralPath $savePath -PathType Leaf) { return $savePath }

    foreach ($dirPath in @($Paths.SaveRoot, $Paths.LogRoot, $Paths.ModsRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath ([string]$dirPath) -PathType Container)) {
            New-Item -ItemType Directory -Path ([string]$dirPath) -Force | Out-Null
        }
    }

    $stdoutPath = Join-Path ([string]$Paths.LogRoot) 'create-save.stdout.log'
    $stderrPath = Join-Path ([string]$Paths.LogRoot) 'create-save.stderr.log'
    $combinedPath = Join-Path ([string]$Paths.LogRoot) 'create-save.log'

    Remove-Item -LiteralPath $stdoutPath,$stderrPath,$combinedPath -Force -ErrorAction SilentlyContinue

    $attempts = @()

    # First try: use the configurable map files so new worlds can honor the Map Gen / Map Settings tabs.
    if (
        -not [string]::IsNullOrWhiteSpace([string]$Paths.MapGenJsonPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$Paths.MapSettingsPath) -and
        (Test-Path -LiteralPath ([string]$Paths.MapGenJsonPath) -PathType Leaf) -and
        (Test-Path -LiteralPath ([string]$Paths.MapSettingsPath) -PathType Leaf)
    ) {
        $attempts += [pscustomobject]@{
            Name = 'custom-map-settings'
            Args = @(
                '--create', $savePath,
                '--map-gen-settings', ([string]$Paths.MapGenJsonPath),
                '--map-settings', ([string]$Paths.MapSettingsPath),
                '--mod-directory', ([string]$Paths.ModsRoot)
            )
        }
    }

    # Fallback: create a default save. This prevents a bad/unsupported custom map JSON value
    # from blocking the server from starting at all.
    $attempts += [pscustomobject]@{
        Name = 'default-map'
        Args = @(
            '--create', $savePath,
            '--mod-directory', ([string]$Paths.ModsRoot)
        )
    }

    $allLines = New-Object System.Collections.Generic.List[string]
    [void]$allLines.Add(('CreateSaveTarget={0}' -f $savePath))
    [void]$allLines.Add(('Executable={0}' -f $ServerExecutablePath))

    $lastExitCode = $null
    $lastErrorText = $null

    foreach ($attempt in $attempts) {
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

        [void]$allLines.Add('')
        [void]$allLines.Add(('=== Attempt: {0} ===' -f [string]$attempt.Name))
        $launchArgs = @()
        if ($Paths.PSObject.Properties['ConfigIniPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.ConfigIniPath)) {
            $launchArgs += @('--config', [string]$Paths.ConfigIniPath)
        }
        $launchArgs += @($attempt.Args)

        [void]$allLines.Add(('Arguments: {0}' -f (($launchArgs | ForEach-Object { '"{0}"' -f ([string]$_).Replace('"','\"') }) -join ' ')))

        try {
            $proc = Start-Process `
                -FilePath $ServerExecutablePath `
                -ArgumentList $launchArgs `
                -WorkingDirectory (Split-Path -Parent $ServerExecutablePath) `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath `
                -PassThru `
                -WindowStyle Hidden

            $proc.WaitForExit()
            $lastExitCode = $proc.ExitCode
            [void]$allLines.Add(('ExitCode: {0}' -f $proc.ExitCode))
        }
        catch {
            $lastErrorText = $_.Exception.Message
            [void]$allLines.Add(('StartProcessError: {0}' -f $lastErrorText))
        }

        if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
            [void]$allLines.Add('--- STDOUT ---')
            foreach ($line in @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)) { [void]$allLines.Add($line) }
        }
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            [void]$allLines.Add('--- STDERR ---')
            foreach ($line in @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)) { [void]$allLines.Add($line) }
        }

        if ((Test-Path -LiteralPath $savePath -PathType Leaf) -and ($null -eq $lastExitCode -or [int]$lastExitCode -eq 0)) {
            [void]$allLines.Add('')
            [void]$allLines.Add(('CreateSaveResult=Success via {0}' -f [string]$attempt.Name))
            Set-Content -LiteralPath $combinedPath -Value $allLines -Encoding UTF8
            return $savePath
        }

        if (Test-Path -LiteralPath $savePath -PathType Leaf) {
            # If Factorio wrote the save but returned a non-zero code, keep the save and continue.
            [void]$allLines.Add('')
            [void]$allLines.Add(('CreateSaveResult=Save file exists after {0}; using it despite exit code {1}.' -f [string]$attempt.Name, $lastExitCode))
            Set-Content -LiteralPath $combinedPath -Value $allLines -Encoding UTF8
            return $savePath
        }
    }

    [void]$allLines.Add('')
    [void]$allLines.Add(('CreateSaveResult=Failed. LastExitCode={0}; LastError={1}' -f $lastExitCode, $lastErrorText))
    Set-Content -LiteralPath $combinedPath -Value $allLines -Encoding UTF8

    throw ("Factorio save creation failed. LastExitCode={0}. Check create-save.log in the profile logs folder." -f $lastExitCode)
}

function Repair-UGSMGameFactorioServerSettingsForLocalStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Runtime
    )

    $settingsPath = [string]$Runtime.ServerSettingsPath
    if ([string]::IsNullOrWhiteSpace($settingsPath) -or -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        return
    }

    try {
        $settings = Read-UGSMGameFactorioJsonFile -Path $settingsPath
        if ($null -eq $settings) { return }

        if (-not $settings.PSObject.Properties['visibility'] -or $null -eq $settings.visibility) {
            Add-Member -InputObject $settings -MemberType NoteProperty -Name 'visibility' -Value ([pscustomobject]@{ public = $false; lan = $true }) -Force
        }

        if (-not $settings.visibility.PSObject.Properties['public']) {
            Add-Member -InputObject $settings.visibility -MemberType NoteProperty -Name 'public' -Value $false -Force
        }
        if (-not $settings.visibility.PSObject.Properties['lan']) {
            Add-Member -InputObject $settings.visibility -MemberType NoteProperty -Name 'lan' -Value $true -Force
        }

        $isPublic = $false
        try { $isPublic = [bool]$settings.visibility.public } catch { $isPublic = $false }

        $hasUser = $false
        $hasSecret = $false
        try { $hasUser = -not [string]::IsNullOrWhiteSpace([string]$settings.username) } catch {}
        try {
            $hasSecret = (
                -not [string]::IsNullOrWhiteSpace([string]$settings.password) -or
                -not [string]::IsNullOrWhiteSpace([string]$settings.token)
            )
        } catch {}

        if ($isPublic -and (-not $hasUser -or -not $hasSecret)) {
            # Factorio public matching requires factorio.com credentials/token. For first-run testing,
            # keep the server LAN-only instead of letting factorio.exe start and immediately exit.
            $settings.visibility.public = $false
            $settings.visibility.lan = $true
            Write-UGSMGameFactorioJsonFile -Path $settingsPath -Value $settings
            Write-UGSMGameFactorioLog -Level 'INFO' -Message 'Factorio public visibility was disabled for local start because no Factorio.com credentials/token were configured.'
        }
    }
    catch {
        Write-UGSMGameFactorioLog -Level 'WARN' -Message 'Factorio server-settings local-start repair failed.' -Exception $_.Exception
    }
}



function Set-UGSMGameFactorioInstanceField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ($Instance.PSObject.Properties[$Name]) {
        $Instance.($Name) = $Value
    }
    else {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Get-UGSMGameFactorioProfilePathsForRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profileRoot = $null
    if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profileRoot = [string]$Instance.ProfilePath
    }
    elseif ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $profileRoot = Get-UGSMGameFactorioProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profileRoot)) {
        throw 'Factorio profile path could not be resolved.'
    }

    $configRoot = Join-Path $profileRoot 'config'
    $saveRoot = Join-Path $profileRoot 'saves'
    $logRoot = Join-Path $profileRoot 'logs'
    $modRoot = Join-Path $profileRoot 'mods'

    foreach ($dir in @($profileRoot, $configRoot, $saveRoot, $logRoot, $modRoot)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    return [pscustomobject]@{
        ProfileRoot        = $profileRoot
        ConfigRoot         = $configRoot
        SaveRoot           = $saveRoot
        LogRoot            = $logRoot
        ModRoot            = $modRoot
        ServerSettingsPath   = Join-Path $configRoot 'server-settings.json'
        ServerAdminListPath = Join-Path $configRoot 'server-adminlist.json'
        ServerWhitelistPath = Join-Path $configRoot 'server-whitelist.json'
        ServerBanListPath   = Join-Path $configRoot 'server-banlist.json'
        ServerIdPath        = Join-Path $configRoot 'server-id.json'
        RuntimeMarkerPath   = Join-Path $profileRoot 'UGSM.Runtime.json'
        ServerConsoleLog    = Join-Path $logRoot 'server-console.log'
        ServerStdoutLog    = Join-Path $logRoot 'server-stdout.log'
        ServerStderrLog    = Join-Path $logRoot 'server-stderr.log'
        ServerLaunchLog    = Join-Path $logRoot 'server-launch.log'
        ModListPath        = Join-Path $modRoot 'mod-list.json'
        ConfigIniPath      = Join-Path $configRoot 'config.ini'
    }
}


function Ensure-UGSMGameFactorioConfigIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Paths,
        [Parameter(Mandatory)][string]$ServerExecutablePath
    )

    $configIniPath = $null
    if ($Paths.PSObject.Properties['ConfigIniPath']) { $configIniPath = [string]$Paths.ConfigIniPath }
    if ([string]::IsNullOrWhiteSpace($configIniPath)) { $configIniPath = Join-Path ([string]$Paths.ConfigRoot) 'config.ini' }

    $profileRoot = $null
    if ($Paths.PSObject.Properties['ProfileRoot']) { $profileRoot = [string]$Paths.ProfileRoot }
    if ([string]::IsNullOrWhiteSpace($profileRoot)) { $profileRoot = Split-Path -Parent ([string]$Paths.ConfigRoot) }

    $exeDir = Split-Path -Parent $ServerExecutablePath
    $readData = [System.IO.Path]::GetFullPath((Join-Path $exeDir '..\..\data'))
    $writeData = [System.IO.Path]::GetFullPath($profileRoot)

    $configParent = Split-Path -Parent $configIniPath
    if (-not (Test-Path -LiteralPath $configParent -PathType Container)) {
        New-Item -ItemType Directory -Path $configParent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath (Join-Path $writeData 'saves') -PathType Container)) {
        New-Item -ItemType Directory -Path (Join-Path $writeData 'saves') -Force | Out-Null
    }

    $content = @(
        '[path]',
        ('read-data={0}' -f $readData),
        ('write-data={0}' -f $writeData),
        '',
        '[general]',
        'locale=en'
    )

    Set-Content -LiteralPath $configIniPath -Value $content -Encoding UTF8
    return $configIniPath
}

function Resolve-UGSMGameFactorioStartSavePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Paths,
        [Parameter(Mandatory)][string]$PreferredSavePath
    )

    $saveRoot = [string]$Paths.SaveRoot
    if ([string]::IsNullOrWhiteSpace($saveRoot) -or -not (Test-Path -LiteralPath $saveRoot -PathType Container)) {
        return $PreferredSavePath
    }

    $latest = @(Get-ChildItem -LiteralPath $saveRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1)

    if ($latest.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$latest[0].FullName)) {
        return [string]$latest[0].FullName
    }

    return $PreferredSavePath
}

function Ensure-UGSMGameFactorioProfileRuntimeFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Instance)

    $serverName = 'UGSM Factorio Server'
    if ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $serverName = [string]$Instance.Name
    }

    if (-not (Test-Path -LiteralPath $Paths.ServerSettingsPath -PathType Leaf)) {
        $settings = [ordered]@{
            name = $serverName
            description = 'Factorio server managed by UGSM.'
            tags = @('game','tags')
            max_players = 0
            visibility = [ordered]@{ public = $false; lan = $true }
            username = ''
            password = ''
            token = ''
            game_password = ''
            require_user_verification = $true
            max_upload_in_kilobytes_per_second = 0
            max_upload_slots = 5
            minimum_latency_in_ticks = 0
            max_heartbeats_per_second = 60
            ignore_player_limit_for_returning_players = $false
            allow_commands = 'admins-only'
            autosave_interval = 10
            autosave_slots = 5
            afk_autokick_interval = 0
            auto_pause = $true
            auto_pause_when_players_connect = $false
            only_admins_can_pause_the_game = $true
            autosave_only_on_server = $true
            non_blocking_saving = $false
            minimum_segment_size = 25
            minimum_segment_size_peer_count = 20
            maximum_segment_size = 100
            maximum_segment_size_peer_count = 10
        }
        $settings | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Paths.ServerSettingsPath -Encoding UTF8
    }

    foreach ($fileName in @('server-adminlist.json','server-whitelist.json','server-banlist.json')) {
        $filePath = Join-Path $Paths.ConfigRoot $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            '[]' | Set-Content -LiteralPath $filePath -Encoding UTF8
        }
    }

    if (-not (Test-Path -LiteralPath $Paths.ModListPath -PathType Leaf)) {
        @{ mods = @(@{ name = 'base'; enabled = $true }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Paths.ModListPath -Encoding UTF8
    }
}

function Repair-UGSMGameFactorioServerSettingsForLocalStart {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerSettingsPath)

    if (-not (Test-Path -LiteralPath $ServerSettingsPath -PathType Leaf)) { return }

    try {
        $raw = Get-Content -LiteralPath $ServerSettingsPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $settings = $raw | ConvertFrom-Json

        if ($settings -and $settings.PSObject.Properties['visibility'] -and $settings.visibility) {
            $isPublic = $false
            if ($settings.visibility.PSObject.Properties['public']) { $isPublic = [bool]$settings.visibility.public }

            $hasUser = ($settings.PSObject.Properties['username'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.username))
            $hasPassword = ($settings.PSObject.Properties['password'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.password))
            $hasToken = ($settings.PSObject.Properties['token'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.token))

            if ($isPublic -and -not ($hasUser -and ($hasPassword -or $hasToken))) {
                $settings.visibility.public = $false
                $settings.visibility.lan = $true
                $settings | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ServerSettingsPath -Encoding UTF8
            }
        }
    }
    catch {}
}

function Get-UGSMGameFactorioMaxPlayersFromSettings {
    [CmdletBinding()]
    param([string]$ServerSettingsPath)

    if ([string]::IsNullOrWhiteSpace($ServerSettingsPath) -or -not (Test-Path -LiteralPath $ServerSettingsPath -PathType Leaf)) {
        return $null
    }

    try {
        $settings = Get-Content -LiteralPath $ServerSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($settings -and $settings.PSObject.Properties['max_players']) {
            return [int]$settings.max_players
        }
    }
    catch {}

    return $null
}

function Get-UGSMGameFactorioServerNameFromSettings {
    [CmdletBinding()]
    param([string]$ServerSettingsPath)

    if ([string]::IsNullOrWhiteSpace($ServerSettingsPath) -or -not (Test-Path -LiteralPath $ServerSettingsPath -PathType Leaf)) {
        return $null
    }

    try {
        $settings = Get-Content -LiteralPath $ServerSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($settings -and $settings.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.name)) {
            return [string]$settings.name
        }
    }
    catch {}

    return $null
}

function Update-UGSMGameFactorioInstanceServerDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][string]$ServerSettingsPath
    )

    if (-not $Instance) { return $Instance }

    $serverName = Get-UGSMGameFactorioServerNameFromSettings -ServerSettingsPath $ServerSettingsPath
    if ([string]::IsNullOrWhiteSpace([string]$serverName)) {
        if ($Instance.PSObject.Properties['ServerName'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ServerName)) {
            $serverName = [string]$Instance.ServerName
        }
        elseif ($Instance.PSObject.Properties['DisplayName'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.DisplayName)) {
            $serverName = [string]$Instance.DisplayName
        }
        elseif ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
            $serverName = [string]$Instance.Name
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$serverName)) {
        foreach ($propName in @('ServerName','PublicServerName','DisplayName','InstanceServerName')) {
            Set-UGSMGameFactorioInstanceField -Instance $Instance -Name $propName -Value ([string]$serverName)
        }
    }

    return $Instance
}

function Set-UGSMGameFactorioRuntimePlayerCountFields {
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
        @{ Name='CurrentPlayers'; Value=[int]$CurrentPlayers },
        @{ Name='PlayerCount'; Value=[int]$CurrentPlayers },
        @{ Name='OnlinePlayers'; Value=[int]$CurrentPlayers },
        @{ Name='PlayersOnline'; Value=[int]$CurrentPlayers },
        @{ Name='InstancePlayerCount'; Value=[int]$CurrentPlayers },
        @{ Name='PlayerCountSource'; Value=[string]$Source },
        @{ Name='InstancePlayerCountSource'; Value=[string]$Source },
        @{ Name='PlayerCountStatus'; Value=[string]$Status },
        @{ Name='InstancePlayerCountError'; Value=$(if ([string]::Equals([string]$Status,'OK',[System.StringComparison]::OrdinalIgnoreCase)) { '' } else { [string]$Status }) },
        @{ Name='PlayerCountUpdatedUtc'; Value=[DateTime]::UtcNow.ToString('o') },
        @{ Name='InstancePlayerCountUpdated'; Value=[DateTime]::UtcNow.ToString('o') }
    )

    if ($null -ne $MaxPlayers -and [int]$MaxPlayers -ge 0) {
        $pairs += @(
            @{ Name='MaxPlayers'; Value=[int]$MaxPlayers },
            @{ Name='ServerMaxPlayers'; Value=[int]$MaxPlayers },
            @{ Name='InstancePlayerMax'; Value=[int]$MaxPlayers }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Detail)) {
        $pairs += @{ Name='PlayerCountDetail'; Value=[string]$Detail }
    }

    foreach ($pair in $pairs) {
        Set-UGSMGameFactorioInstanceField -Instance $Instance -Name ([string]$pair.Name) -Value $pair.Value
    }
}

function Get-UGSMGameFactorioCurrentPlayerCountFromConsoleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$MaxLines = 2000
    )

    $paths = Get-UGSMGameFactorioProfilePathsForRuntime -Instance $Instance
    $logPath = [string]$paths.ServerConsoleLog
    $maxPlayers = Get-UGSMGameFactorioMaxPlayersFromSettings -ServerSettingsPath ([string]$paths.ServerSettingsPath)

    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'NoLog'
            CurrentPlayers = 0
            MaxPlayers     = $maxPlayers
            Source         = 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER'
            Detail         = 'server-console.log was not found.'
        }
    }

    try {
        $lines = Get-Content -LiteralPath $logPath -Tail $MaxLines -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'ReadFailed'
            CurrentPlayers = 0
            MaxPlayers     = $maxPlayers
            Source         = 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER'
            Detail         = 'server-console.log could not be read.'
        }
    }

    $active = @{}
    foreach ($lineObj in $lines) {
        $line = [string]$lineObj
        if ($line -match '\[JOIN\]\s+(?<name>.+?)\s+joined the game') {
            $name = [string]$Matches['name']
            if (-not [string]::IsNullOrWhiteSpace($name)) { $active[$name] = $true }
            continue
        }
        if ($line -match '\[LEAVE\]\s+(?<name>.+?)\s+left the game') {
            $name = [string]$Matches['name']
            if (-not [string]::IsNullOrWhiteSpace($name) -and $active.ContainsKey($name)) { $active.Remove($name) }
            continue
        }
    }

    return [pscustomobject]@{
        Success        = $true
        Status         = 'OK'
        CurrentPlayers = [int]$active.Count
        MaxPlayers     = $maxPlayers
        Source         = 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER'
        Detail         = (Split-Path -Leaf $logPath)
    }
}

function Update-UGSMGameFactorioDiscordRuntimeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (-not $Instance) { return $Instance }

    try {
        $paths = Get-UGSMGameFactorioProfilePathsForRuntime -Instance $Instance
        $maxPlayers = Get-UGSMGameFactorioMaxPlayersFromSettings -ServerSettingsPath ([string]$paths.ServerSettingsPath)
        $Instance = Update-UGSMGameFactorioInstanceServerDisplayName -Instance $Instance -ServerSettingsPath ([string]$paths.ServerSettingsPath)

        $statusText = ''
        if ($Instance.PSObject.Properties['Status']) { $statusText = [string]$Instance.Status }

        if ($statusText.Trim().ToLowerInvariant() -notin @('running','online','started')) {
            Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER' -Status 'Stopped' -Detail ''
            Save-UGSMGameFactorioInstanceDefinition -Instance $Instance | Out-Null
            return $Instance
        }

        $result = Get-UGSMGameFactorioCurrentPlayerCountFromConsoleLog -Instance $Instance
        if ($result -and [bool]$result.Success) {
            if ($null -ne $result.MaxPlayers -and [int]$result.MaxPlayers -ge 0) { $maxPlayers = [int]$result.MaxPlayers }
            Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers ([int]$result.CurrentPlayers) -MaxPlayers $maxPlayers -Source ([string]$result.Source) -Status ([string]$result.Status) -Detail ([string]$result.Detail)
        }
        else {
            $status = if ($result) { [string]$result.Status } else { 'NoResult' }
            $detail = if ($result) { [string]$result.Detail } else { 'Factorio player-count resolver returned no result.' }
            Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER' -Status $status -Detail $detail
        }

        Save-UGSMGameFactorioInstanceDefinition -Instance $Instance | Out-Null
    }
    catch {
        try {
            Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $null -Source 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER' -Status 'Error' -Detail $_.Exception.Message
            Save-UGSMGameFactorioInstanceDefinition -Instance $Instance | Out-Null
        } catch {}
    }

    return $Instance
}

function Start-UGSMGameFactorioLogConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][int]$ServerPid,
        [Parameter(Mandatory)][string]$InstanceName
    )

    $safeTitle = ('UGSM Factorio Console - {0}' -f $InstanceName)
    $consoleScript = @"
`$Host.UI.RawUI.WindowTitle = '$($safeTitle.Replace("'","''"))'
Write-Host 'Live Factorio log console. Close this window only if you do not need to watch the server output.'
Write-Host ''
`$logPath = '$($LogPath.Replace("'","''"))'
`$serverPid = $ServerPid
`$lastPosition = 0L
while (`$true) {
    `$running = `$true
    try { Get-Process -Id `$serverPid -ErrorAction Stop | Out-Null } catch { `$running = `$false }

    if (Test-Path -LiteralPath `$logPath -PathType Leaf) {
        try {
            `$fs = [System.IO.File]::Open(`$logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            if (`$lastPosition -gt `$fs.Length) { `$lastPosition = 0L }
            [void]`$fs.Seek(`$lastPosition, [System.IO.SeekOrigin]::Begin)
            `$reader = New-Object System.IO.StreamReader(`$fs)
            `$newText = `$reader.ReadToEnd()
            `$lastPosition = `$fs.Position
            `$reader.Close()
            `$fs.Close()
            if (-not [string]::IsNullOrEmpty(`$newText)) { Write-Host `$newText -NoNewline }
        } catch {}
    }
    else {
        Write-Host ('Waiting for log: ' + `$logPath)
    }

    if (-not `$running) {
        Write-Host ''
        Write-Host 'Factorio process stopped. Press Enter to close this console.'
        try { [void](Read-Host) } catch {}
        break
    }

    Start-Sleep -Seconds 2
}
"@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($consoleScript))
    try {
        return Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -WindowStyle Normal -PassThru
    }
    catch {
        return $null
    }
}

function Start-UGSMGameFactorioInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'Factorio start failed: Instance was null.'
    }

    $installDef = Get-UGSMGameFactorioInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'Factorio start failed: Install definition could not be resolved.'
    }

    $serverExe = [string]$installDef.ServerExecutablePath
    if ([string]::IsNullOrWhiteSpace($serverExe) -or -not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        $installRoot = [string]$installDef.InstallPath
        if (-not [string]::IsNullOrWhiteSpace($installRoot)) {
            $serverExe = Join-Path $installRoot 'bin\x64\factorio.exe'
        }
    }

    if ([string]::IsNullOrWhiteSpace($serverExe) -or -not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "Factorio start failed: factorio.exe was not found. Expected under: $($installDef.InstallPath)\bin\x64"
    }

    $paths = Get-UGSMGameFactorioProfilePathsForRuntime -Instance $Instance
    Ensure-UGSMGameFactorioProfileRuntimeFiles -Paths $paths -Instance $Instance
    Repair-UGSMGameFactorioServerSettingsForLocalStart -ServerSettingsPath ([string]$paths.ServerSettingsPath)

    $savePaths = [pscustomobject]@{
        ProfileRoot     = [string]$paths.ProfileRoot
        ConfigRoot      = [string]$paths.ConfigRoot
        SaveRoot        = [string]$paths.SaveRoot
        LogRoot         = [string]$paths.LogRoot
        ModsRoot        = [string]$paths.ModRoot
        ConfigIniPath   = [string]$paths.ConfigIniPath
        MapGenJsonPath  = Join-Path ([string]$paths.ConfigRoot) 'map-gen-settings.json'
        MapSettingsPath = Join-Path ([string]$paths.ConfigRoot) 'map-settings.json'
    }
    Ensure-UGSMGameFactorioConfigIni -Paths $paths -ServerExecutablePath $serverExe | Out-Null
    $savePath = Ensure-UGSMGameFactorioInitialSave -Instance $Instance -Paths $savePaths -ServerExecutablePath $serverExe
    $savePath = Resolve-UGSMGameFactorioStartSavePath -Paths $paths -PreferredSavePath ([string]$savePath)
    if ([string]::IsNullOrWhiteSpace([string]$savePath) -or -not (Test-Path -LiteralPath ([string]$savePath) -PathType Leaf)) {
        throw 'Factorio start failed: initial save could not be resolved.'
    }

    $gamePort = 34197
    try {
        if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports -and $Instance.Ports.PSObject.Properties['GamePort']) {
            $gamePort = [int]$Instance.Ports.GamePort
        }
    }
    catch { $gamePort = 34197 }

    foreach ($logPath in @($paths.ServerStdoutLog, $paths.ServerStderrLog, $paths.ServerLaunchLog, $paths.ServerConsoleLog)) {
        try {
            $parent = Split-Path -Parent $logPath
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        } catch {}
    }

    $args = @(
        '--config', [string]$paths.ConfigIniPath,
        '--start-server', [string]$savePath,
        '--server-settings', [string]$paths.ServerSettingsPath,
        '--server-adminlist', [string]$paths.ServerAdminListPath
    )

    $useServerWhitelist = $false
    try {
        $whitelistPath = [string]$paths.ServerWhitelistPath
        if (-not [string]::IsNullOrWhiteSpace($whitelistPath) -and (Test-Path -LiteralPath $whitelistPath -PathType Leaf)) {
            $whitelistRaw = Get-Content -LiteralPath $whitelistPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($whitelistRaw)) {
                $whitelistData = ConvertFrom-Json -InputObject $whitelistRaw -ErrorAction Stop
                if ($whitelistData -is [System.Array]) {
                    $useServerWhitelist = ($whitelistData.Count -gt 0)
                }
                elseif ($null -ne $whitelistData) {
                    $useServerWhitelist = $true
                }
            }
        }
    }
    catch {
        $useServerWhitelist = $false
    }

    if ($useServerWhitelist) {
        $args += @('--use-server-whitelist', '--server-whitelist', [string]$paths.ServerWhitelistPath)
    }

    $args += @(
        '--server-banlist', [string]$paths.ServerBanListPath,
        '--server-id', [string]$paths.ServerIdPath,
        '--port', [string]$gamePort,
        '--mod-directory', [string]$paths.ModRoot,
        '--console-log', [string]$paths.ServerConsoleLog
    )

    $args = @($args | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    try {
        ('[{0}] UGSM launching Factorio: {1}' -f ([DateTime]::Now.ToString('s')), $serverExe) | Set-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
        ('SelectedSave: {0}' -f ([string]$savePath)) | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
        ('ProfileConfig: {0}' -f ([string]$paths.ConfigIniPath)) | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
        ('Args: {0}' -f ($args -join ' ')) | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
    }
    catch {}

    $proc = Start-Process `
        -FilePath $serverExe `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $serverExe) `
        -RedirectStandardOutput ([string]$paths.ServerStdoutLog) `
        -RedirectStandardError ([string]$paths.ServerStderrLog) `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'Factorio start failed: Start-Process did not return a valid process.'
    }

    Start-Sleep -Seconds 5

    $exitedEarly = $false
    try {
        $checkProc = Get-Process -Id ([int]$proc.Id) -ErrorAction Stop
        if ($checkProc.HasExited) { $exitedEarly = $true }
    }
    catch {
        $exitedEarly = $true
    }

    if ($exitedEarly) {
        try {
            ('[{0}] Factorio exited during start verification.' -f ([DateTime]::Now.ToString('s'))) | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
            if (Test-Path -LiteralPath $paths.ServerStdoutLog -PathType Leaf) {
                '--- STDOUT ---' | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
                Get-Content -LiteralPath $paths.ServerStdoutLog -ErrorAction SilentlyContinue | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
            }
            if (Test-Path -LiteralPath $paths.ServerStderrLog -PathType Leaf) {
                '--- STDERR ---' | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
                Get-Content -LiteralPath $paths.ServerStderrLog -ErrorAction SilentlyContinue | Add-Content -LiteralPath $paths.ServerLaunchLog -Encoding UTF8
            }
        } catch {}
        throw 'Factorio start failed: factorio.exe exited right after launch. Check server-launch.log in the profile logs folder.'
    }

    $gamePid = [int]$proc.Id
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'Pid' -Value $gamePid
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'ProcessId' -Value $gamePid
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'Status' -Value 'Running'
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'ProfilePath' -Value ([string]$paths.ProfileRoot)
    $Instance = Update-UGSMGameFactorioInstanceServerDisplayName -Instance $Instance -ServerSettingsPath ([string]$paths.ServerSettingsPath)

    $consoleProc = Start-UGSMGameFactorioLogConsole -LogPath ([string]$paths.ServerConsoleLog) -ServerPid $gamePid -InstanceName ([string]$Instance.Name)
    $consolePid = $null
    if ($consoleProc -and $consoleProc.Id) { $consolePid = [int]$consoleProc.Id }

    try {
        Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers (Get-UGSMGameFactorioMaxPlayersFromSettings -ServerSettingsPath ([string]$paths.ServerSettingsPath)) -Source 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER' -Status 'Pending' -Detail 'Waiting for Factorio join/leave log lines.'
    } catch {}

    try {
        $runtimeData = [pscustomobject]@{
            InstanceId        = [string]$Instance.Id
            GameId            = 'Factorio'
            ProfilePath       = [string]$paths.ProfileRoot
            ConfigRoot        = [string]$paths.ConfigRoot
            SaveRoot          = [string]$paths.SaveRoot
            LogRoot           = [string]$paths.LogRoot
            ModRoot           = [string]$paths.ModRoot
            ServerConsoleLog  = [string]$paths.ServerConsoleLog
            Pid               = $gamePid
            ConsolePid        = $consolePid
            StartedAtUtc      = [DateTime]::UtcNow.ToString('o')
        }
        $runtimeData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $paths.RuntimeMarkerPath -Encoding UTF8
    }
    catch {}

    Save-UGSMGameFactorioInstanceDefinition -Instance $Instance | Out-Null

    return [pscustomobject]@{
        Instance   = $Instance
        Pid        = $gamePid
        ProcessId  = $gamePid
        ConsolePid = $consolePid
        Status     = 'Running'
        Runtime    = $paths
    }
}



function Stop-UGSMGameFactorioInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'Factorio stop failed: Instance was null.'
    }

    $paths = Get-UGSMGameFactorioProfilePathsForRuntime -Instance $Instance

    $targetProcessId = $null
    foreach ($propName in @('Pid','ProcessId')) {
        if ($Instance.PSObject.Properties[$propName] -and ($Instance.$propName -as [int])) {
            $targetProcessId = [int]$Instance.$propName
            break
        }
    }

    $consolePid = $null
    try {
        if (Test-Path -LiteralPath $paths.RuntimeMarkerPath -PathType Leaf) {
            $runtimeData = Get-Content -LiteralPath $paths.RuntimeMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($runtimeData -and $runtimeData.PSObject.Properties['ConsolePid'] -and ($runtimeData.ConsolePid -as [int])) {
                $consolePid = [int]$runtimeData.ConsolePid
            }
        }
    }
    catch {}

    if ($targetProcessId) {
        try {
            $proc = Get-Process -Id $targetProcessId -ErrorAction Stop
            try { if ($proc.CloseMainWindow()) { [void]$proc.WaitForExit(15000) } } catch {}
            try {
                $proc = Get-Process -Id $targetProcessId -ErrorAction Stop
                Stop-Process -Id $targetProcessId -Force -ErrorAction Stop
            }
            catch [System.ArgumentException] {}
            catch {}
        }
        catch [System.ArgumentException] {}
        catch {
            try { & taskkill.exe /PID $targetProcessId /T /F | Out-Null } catch {}
        }
    }

    if ($consolePid) {
        try { Stop-Process -Id $consolePid -Force -ErrorAction SilentlyContinue } catch {}
    }

    try {
        if (Test-Path -LiteralPath $paths.RuntimeMarkerPath -PathType Leaf) {
            Remove-Item -LiteralPath $paths.RuntimeMarkerPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}

    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'Pid' -Value $null
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'ProcessId' -Value $null
    Set-UGSMGameFactorioInstanceField -Instance $Instance -Name 'Status' -Value 'Stopped'

    try {
        Set-UGSMGameFactorioRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers (Get-UGSMGameFactorioMaxPlayersFromSettings -ServerSettingsPath ([string]$paths.ServerSettingsPath)) -Source 'FACTORIO_CONSOLE_LOG_JOIN_TRACKER' -Status 'Stopped' -Detail ''
    } catch {}

    Save-UGSMGameFactorioInstanceDefinition -Instance $Instance | Out-Null

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Runtime  = $paths
    }
}

function Register-UGSMGameFactorioModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameFactorioMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameFactorioMetadata'
            TestInstall       = 'Test-UGSMGameFactorioInstall'
            TestInstance      = 'Test-UGSMGameFactorioInstance'
            EnsureFactorio    = 'Ensure-UGSMGameFactorioFactorio'
            InitializeProfile = 'Initialize-UGSMGameFactorioProfile'
            Start             = 'Start-UGSMGameFactorioInstance'
            Stop              = 'Stop-UGSMGameFactorioInstance'

            BuildEditor       = 'New-UGSMGameFactorioInstanceEditor'
            SaveEditor        = 'Save-UGSMGameFactorioInstanceEditor'
        }
    }
}


function Get-UGSMGameFactorioBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance

        $settingsTargets = @(
            @{ Path = $paths.ServerSettingsPath;          Relative = 'Config\WindowsServer\ServerSettings.ini'; Label = 'Factorio server settings INI' },
            @{ Path = $paths.GameplayJsonPath;            Relative = 'Config\WindowsServer\Gameplay.json';      Label = 'Factorio gameplay JSON' },
            @{ Path = $paths.GameplayXmlPath;             Relative = 'Config\WindowsServer\Gameplay.xml';       Label = 'Factorio gameplay XML' },
            @{ Path = $paths.ServerCfgPath;               Relative = 'Config\WindowsServer\Server.cfg';          Label = 'Factorio server CFG' },
            @{ Path = $paths.AdminUsersPath;              Relative = 'Config\WindowsServer\AdminUsers.txt';     Label = 'Factorio admin users list' },
            @{ Path = $paths.ExclusiveUsersPath;          Relative = 'Config\WindowsServer\ExclusiveUsers.txt'; Label = 'Factorio exclusive users list' },
            @{ Path = $paths.WhitelistedUsersPath;        Relative = 'Config\WindowsServer\WhitelistedUsers.txt'; Label = 'Factorio whitelist users list' },
            @{ Path = $paths.BannedUsersPath;             Relative = 'Config\WindowsServer\BannedUsers.txt';    Label = 'Factorio banned users list' },
            @{ Path = $paths.SilencedUsersPath;           Relative = 'Config\WindowsServer\SilencedUsers.txt';  Label = 'Factorio silenced users list' }
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
        #     Label        = 'Factorio managed mods manifest'
        # })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameFactorioManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'Factorio managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameFactorioBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'Factorio' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameFactorioLog -Level 'WARN' -Message ('Factorio managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameFactorioProfilePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $profileRoot = $null
    if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profileRoot = [string]$Instance.ProfilePath
    }
    elseif ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
        $profileRoot = Get-UGSMGameFactorioProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'Factorio profile paths could not be resolved for the selected instance.'
    }

    $configRoot = Join-Path $profileRoot 'config'
    $saveRoot = Join-Path $profileRoot 'saves'
    $logRoot = Join-Path $profileRoot 'logs'
    $modsRoot = Join-Path $profileRoot 'mods'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot
        ProfileConfigRoot           = $configRoot
        ProfileSaveRoot             = $saveRoot
        ProfileLogRoot              = $logRoot
        ProfileModsRoot             = $modsRoot

        RuntimeRoot                 = $profileRoot
        RuntimeConfigRoot           = $configRoot
        RuntimeSaveRoot             = $saveRoot
        RuntimeLogRoot              = $logRoot
        RuntimeModsRoot             = $modsRoot
        RuntimeMarkerPath           = Join-Path $profileRoot 'UGSM.Runtime.json'
        IsRuntimeActive             = (Test-Path -LiteralPath (Join-Path $profileRoot 'UGSM.Runtime.json') -PathType Leaf)

        ConfigRoot                  = $configRoot
        SaveRoot                    = $saveRoot
        LogRoot                     = $logRoot
        ModsRoot                    = $modsRoot

        PrimaryJsonPath             = Join-Path $configRoot 'server-settings.json'
        ServerSettingsPath          = Join-Path $configRoot 'server-settings.json'
        MapGenSettingsPath          = Join-Path $configRoot 'map-gen-settings.json'
        MapSettingsPath             = Join-Path $configRoot 'map-settings.json'
        ServerAdminListPath         = Join-Path $configRoot 'server-adminlist.json'
        ServerWhitelistPath         = Join-Path $configRoot 'server-whitelist.json'
        ServerBanListPath           = Join-Path $configRoot 'server-banlist.json'
        ServerIdPath                = Join-Path $configRoot 'server-id.json'
        ModListPath                 = Join-Path $modsRoot 'mod-list.json'

        AdminUsersPath              = Join-Path $configRoot 'server-adminlist.json'
        WhitelistedUsersPath        = Join-Path $configRoot 'server-whitelist.json'
        BannedUsersPath             = Join-Path $configRoot 'server-banlist.json'
        ExclusiveUsersPath          = Join-Path $configRoot 'server-whitelist.json'
        SilencedUsersPath           = Join-Path $configRoot 'server-banlist.json'

        RuntimePrimaryJsonPath      = Join-Path $configRoot 'server-settings.json'
        RuntimeServerSettingsPath   = Join-Path $configRoot 'server-settings.json'
        RuntimeAdminUsersPath       = Join-Path $configRoot 'server-adminlist.json'
        RuntimeWhitelistedUsersPath = Join-Path $configRoot 'server-whitelist.json'
        RuntimeBannedUsersPath      = Join-Path $configRoot 'server-banlist.json'
        RuntimeExclusiveUsersPath   = Join-Path $configRoot 'server-whitelist.json'
        RuntimeSilencedUsersPath    = Join-Path $configRoot 'server-banlist.json'

        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $null
        DatabasePath                = $null
    }
}



function Read-UGSMGameFactorioIniFile {
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

function Get-UGSMGameFactorioIniValue {
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

function Set-UGSMGameFactorioIniValue {
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

function Read-UGSMGameFactorioStringListFile {
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

function Write-UGSMGameFactorioStringListFile {
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


function Ensure-UGSMGameFactorioParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameFactorioJsonFile {
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

    $value = ConvertFrom-Json -InputObject $raw
    return ,$value
}

function Write-UGSMGameFactorioJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameFactorioParentDirectory -Path $Path

    if ($null -ne $Value -and [System.IO.Path]::GetFileName([string]$Path).Equals('map-gen-settings.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        $startingPointsProp = $Value.PSObject.Properties['starting_points']
        if ($startingPointsProp) {
            $pointsValue = $startingPointsProp.Value
            if ($null -eq $pointsValue) {
                $pointsList = New-Object System.Collections.ArrayList
                $Value.starting_points = $pointsList
            }
            elseif ($pointsValue -isnot [System.Collections.IList] -and $pointsValue -isnot [System.Array]) {
                $pointsList = New-Object System.Collections.ArrayList
                [void]$pointsList.Add($pointsValue)
                $Value.starting_points = $pointsList
            }
        }
    }

    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = (ConvertTo-Json -InputObject $Value -Depth 100)
    }

    if (-not [string]::IsNullOrWhiteSpace($json) -and [System.IO.Path]::GetFileName([string]$Path).Equals('map-gen-settings.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        # PowerShell 5.1 can unwrap a single starting_points item while serializing.
        # Factorio requires this value to remain a JSON array, even when it contains one point.
        $json = [System.Text.RegularExpressions.Regex]::Replace(
            $json,
            '(?s)("starting_points"\s*:\s*)(\{[^{}]*\})',
            '$1[$2]',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-UGSMGameFactorioModListPathFromPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Paths)

    if ($Paths.PSObject.Properties['ModListPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.ModListPath)) {
        return [string]$Paths.ModListPath
    }

    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
    if (-not [string]::IsNullOrWhiteSpace([string]$modsRoot)) {
        return (Join-Path ([string]$modsRoot) 'mod-list.json')
    }

    return $null
}

function Get-UGSMGameFactorioSpaceAgeEnabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModListPath)

    try {
        $modList = Read-UGSMGameFactorioJsonFile -Path $ModListPath
        if ($null -eq $modList -or -not $modList.PSObject.Properties['mods']) { return $false }

        foreach ($mod in @($modList.mods)) {
            if ($mod -and [string]$mod.name -eq 'space-age') {
                return [bool]$mod.enabled
            }
        }
    }
    catch { }

    return $false
}

function Set-UGSMGameFactorioSpaceAgeEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModListPath,
        [Parameter(Mandatory)][bool]$Enabled
    )

    $modList = $null
    try { $modList = Read-UGSMGameFactorioJsonFile -Path $ModListPath } catch { $modList = $null }
    if ($null -eq $modList) { $modList = [pscustomobject]@{} }

    $existingByName = [ordered]@{}
    if ($modList.PSObject.Properties['mods']) {
        foreach ($mod in @($modList.mods)) {
            if ($mod -and $mod.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.name)) {
                $existingByName[[string]$mod.name] = $mod
            }
        }
    }

    function New-FactorioModEntry {
        param([string]$Name, [bool]$IsEnabled)
        if ($existingByName.Contains($Name)) {
            $entry = $existingByName[$Name]
            if ($entry.PSObject.Properties['enabled']) { $entry.enabled = $IsEnabled }
            else { Add-Member -InputObject $entry -MemberType NoteProperty -Name 'enabled' -Value $IsEnabled -Force }
            return $entry
        }

        return [pscustomobject]@{ name = $Name; enabled = $IsEnabled }
    }

    $orderedMods = New-Object System.Collections.Generic.List[object]
    foreach ($builtIn in @('base','elevated-rails','quality','space-age')) {
        $isEnabled = if ($builtIn -eq 'base') { $true } else { $Enabled }
        [void]$orderedMods.Add((New-FactorioModEntry -Name $builtIn -IsEnabled $isEnabled))
        if ($existingByName.Contains($builtIn)) { [void]$existingByName.Remove($builtIn) }
    }

    foreach ($name in @($existingByName.Keys)) {
        [void]$orderedMods.Add($existingByName[$name])
    }

    if ($modList.PSObject.Properties['mods']) { $modList.mods = @($orderedMods.ToArray()) }
    else { Add-Member -InputObject $modList -MemberType NoteProperty -Name 'mods' -Value @($orderedMods.ToArray()) -Force }

    Write-UGSMGameFactorioJsonFile -Path $ModListPath -Value $modList
}


function Get-UGSMGameFactorioBuiltInModNames {
    [CmdletBinding()]
    param()

    return @('base','elevated-rails','quality','space-age')
}

function Get-UGSMGameFactorioModNameFromZipPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([string]::IsNullOrWhiteSpace($baseName)) { return $null }

    # Factorio mod archives normally use name_version.zip.
    # Strip a trailing _1.2.3 style version while preserving underscores in the mod name.
    if ($baseName -match '^(?<name>.+)_(?<version>\d+(?:\.\d+){1,4})$') {
        return [string]$Matches['name']
    }

    return [string]$baseName
}

function Get-UGSMGameFactorioModZipEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModsRoot)

    $entries = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($ModsRoot) -or -not (Test-Path -LiteralPath $ModsRoot -PathType Container)) {
        return @()
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $ModsRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $modName = Get-UGSMGameFactorioModNameFromZipPath -Path $file.FullName
        if ([string]::IsNullOrWhiteSpace($modName)) { continue }

        [void]$entries.Add([pscustomobject]@{
                Name = [string]$modName
                File = [string]$file.Name
                Path = [string]$file.FullName
            })
    }

    return @($entries.ToArray())
}

function Read-UGSMGameFactorioModListObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModListPath)

    $modList = $null
    try { $modList = Read-UGSMGameFactorioJsonFile -Path $ModListPath } catch { $modList = $null }
    if ($null -eq $modList) { $modList = [pscustomobject]@{} }
    if (-not $modList.PSObject.Properties['mods']) {
        Add-Member -InputObject $modList -MemberType NoteProperty -Name 'mods' -Value @([pscustomobject]@{ name='base'; enabled=$true }) -Force
    }

    return $modList
}

function Get-UGSMGameFactorioModsRootFromPaths {
    [CmdletBinding()]
    param([AllowNull()]$Paths)

    if ($Paths) {
        foreach ($propName in @('ModsRoot','ProfileModsRoot','RuntimeModsRoot','RuntimeModsRootPath','ModRoot')) {
            if ($Paths.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.$propName)) {
                return [string]$Paths.$propName
            }
        }

        if ($Paths.PSObject.Properties['ModListPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.ModListPath)) {
            $parent = Split-Path -Parent ([string]$Paths.ModListPath)
            if (-not [string]::IsNullOrWhiteSpace([string]$parent)) { return [string]$parent }
        }

        foreach ($rootProp in @('ProfileRoot','RuntimeRoot')) {
            if ($Paths.PSObject.Properties[$rootProp] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.$rootProp)) {
                return (Join-Path ([string]$Paths.$rootProp) 'mods')
            }
        }
    }

    return $null
}

function Get-UGSMGameFactorioLocalModRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModListPath,
        [Parameter(Mandatory)][string]$ModsRoot
    )

    $builtIns = @{}
    foreach ($name in (Get-UGSMGameFactorioBuiltInModNames)) { $builtIns[[string]$name] = $true }

    $modList = Read-UGSMGameFactorioModListObject -ModListPath $ModListPath
    $byName = [ordered]@{}
    foreach ($mod in @($modList.mods)) {
        if (-not $mod -or -not $mod.PSObject.Properties['name']) { continue }
        $name = [string]$mod.name
        if ([string]::IsNullOrWhiteSpace($name) -or $builtIns.ContainsKey($name)) { continue }
        $enabled = $false
        if ($mod.PSObject.Properties['enabled']) { $enabled = [bool]$mod.enabled }
        $byName[$name] = [pscustomobject]@{ Name=$name; Enabled=$enabled; File='' }
    }

    foreach ($zip in @(Get-UGSMGameFactorioModZipEntries -ModsRoot $ModsRoot)) {
        if (-not $byName.Contains($zip.Name)) {
            $byName[$zip.Name] = [pscustomobject]@{ Name=$zip.Name; Enabled=$true; File=$zip.File }
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$byName[$zip.Name].File)) {
            $byName[$zip.Name].File = $zip.File
        }
    }

    return @($byName.Values | Sort-Object Name)
}

function Set-UGSMGameFactorioLocalModsEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModListPath,
        [Parameter(Mandatory)][string]$ModsRoot,
        [string[]]$EnabledNames
    )

    $enabledLookup = @{}
    foreach ($name in @($EnabledNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $enabledLookup[[string]$name] = $true }
    }

    $builtIns = @{}
    foreach ($name in (Get-UGSMGameFactorioBuiltInModNames)) { $builtIns[[string]$name] = $true }

    $modList = Read-UGSMGameFactorioModListObject -ModListPath $ModListPath

    $existingByName = [ordered]@{}
    foreach ($mod in @($modList.mods)) {
        if ($mod -and $mod.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.name)) {
            $existingByName[[string]$mod.name] = $mod
        }
    }

    $localNames = New-Object System.Collections.Generic.List[string]
    foreach ($zip in @(Get-UGSMGameFactorioModZipEntries -ModsRoot $ModsRoot)) {
        if (-not $builtIns.ContainsKey($zip.Name) -and -not $localNames.Contains($zip.Name)) {
            [void]$localNames.Add($zip.Name)
        }
    }
    foreach ($name in @($existingByName.Keys)) {
        if (-not $builtIns.ContainsKey($name) -and -not $localNames.Contains($name)) {
            [void]$localNames.Add($name)
        }
    }

    $orderedMods = New-Object System.Collections.Generic.List[object]

    foreach ($name in (Get-UGSMGameFactorioBuiltInModNames)) {
        $entry = $null
        if ($existingByName.Contains($name)) { $entry = $existingByName[$name] }
        else { $entry = [pscustomobject]@{ name=$name; enabled=($name -eq 'base') } }

        if ($name -eq 'base') { $entry.enabled = $true }
        [void]$orderedMods.Add($entry)
    }

    foreach ($name in @($localNames | Sort-Object)) {
        $entry = $null
        if ($existingByName.Contains($name)) { $entry = $existingByName[$name] }
        else { $entry = [pscustomobject]@{ name=$name; enabled=$true } }

        if ($entry.PSObject.Properties['enabled']) { $entry.enabled = [bool]$enabledLookup.ContainsKey($name) }
        else { Add-Member -InputObject $entry -MemberType NoteProperty -Name 'enabled' -Value ([bool]$enabledLookup.ContainsKey($name)) -Force }

        [void]$orderedMods.Add($entry)
    }

    $modList.mods = @($orderedMods.ToArray())
    Write-UGSMGameFactorioJsonFile -Path $ModListPath -Value $modList
}

function Import-UGSMGameFactorioLocalModZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms

    if ($null -eq $Paths) { $Paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance }
    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modsRoot)) {
        throw 'Factorio mod import failed: mods folder path could not be resolved.'
    }

    if (-not (Test-Path -LiteralPath $modsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Import Factorio Mod ZIP'
    $dialog.Filter = 'Factorio mod archives (*.zip)|*.zip|All files (*.*)|*.*'
    $dialog.Multiselect = $true

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        if ($StatusLabel) { $StatusLabel.Text = 'Factorio mod import cancelled.' }
        return
    }

    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modListPath)) {
        $modListPath = Join-Path $modsRoot 'mod-list.json'
    }

    $enabledNames = New-Object System.Collections.Generic.List[string]
    foreach ($row in @(Get-UGSMGameFactorioLocalModRows -ModListPath $modListPath -ModsRoot $modsRoot)) {
        if ([bool]$row.Enabled -and -not $enabledNames.Contains([string]$row.Name)) { [void]$enabledNames.Add([string]$row.Name) }
    }

    $imported = 0
    foreach ($sourcePath in @($dialog.FileNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
        $fileName = [System.IO.Path]::GetFileName($sourcePath)
        if ([string]::IsNullOrWhiteSpace($fileName) -or -not $fileName.ToLowerInvariant().EndsWith('.zip')) { continue }

        $targetPath = Join-Path $modsRoot $fileName
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop

        $modName = Get-UGSMGameFactorioModNameFromZipPath -Path $targetPath
        if (-not [string]::IsNullOrWhiteSpace($modName) -and -not $enabledNames.Contains($modName)) {
            [void]$enabledNames.Add($modName)
        }

        $imported++
    }

    Set-UGSMGameFactorioLocalModsEnabled -ModListPath $modListPath -ModsRoot $modsRoot -EnabledNames @($enabledNames.ToArray())

    if ($StatusLabel) { $StatusLabel.Text = ("Imported {0} Factorio mod ZIP(s). Reload the editor to refresh the mod list." -f $imported) }
}

function Sync-UGSMGameFactorioLocalModListFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    if ($null -eq $Paths) { $Paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance }
    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modsRoot)) {
        throw 'Factorio mod sync failed: mods folder path could not be resolved.'
    }

    if (-not (Test-Path -LiteralPath $modsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
    }

    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modListPath)) {
        $modListPath = Join-Path $modsRoot 'mod-list.json'
    }

    $enabledNames = New-Object System.Collections.Generic.List[string]
    foreach ($row in @(Get-UGSMGameFactorioLocalModRows -ModListPath $modListPath -ModsRoot $modsRoot)) {
        if ([bool]$row.Enabled -and -not $enabledNames.Contains([string]$row.Name)) { [void]$enabledNames.Add([string]$row.Name) }
    }

    foreach ($zip in @(Get-UGSMGameFactorioModZipEntries -ModsRoot $modsRoot)) {
        if (-not $enabledNames.Contains($zip.Name)) { [void]$enabledNames.Add($zip.Name) }
    }

    Set-UGSMGameFactorioLocalModsEnabled -ModListPath $modListPath -ModsRoot $modsRoot -EnabledNames @($enabledNames.ToArray())

    if ($StatusLabel) { $StatusLabel.Text = 'Synced Factorio mod-list.json from the local mods folder. Reload the editor to refresh the mod list.' }
}


function Select-UGSMGameFactorioLocalModForRemove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    if ($null -eq $Paths) { $Paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance }
    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modsRoot) -or -not (Test-Path -LiteralPath $modsRoot -PathType Container)) {
        if ($StatusLabel) { $StatusLabel.Text = 'No Factorio profile mods folder was found.' }
        return ''
    }

    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modListPath)) { $modListPath = Join-Path $modsRoot 'mod-list.json' }

    $builtIns = @{}
    foreach ($builtIn in (Get-UGSMGameFactorioBuiltInModNames)) { $builtIns[[string]$builtIn] = $true }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($zip in @(Get-UGSMGameFactorioModZipEntries -ModsRoot $modsRoot)) {
        $name = [string]$zip.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($builtIns.ContainsKey($name)) { continue }
        if (-not $names.Contains($name)) { [void]$names.Add($name) }
    }

    if ($names.Count -eq 0) {
        foreach ($row in @(Get-UGSMGameFactorioLocalModRows -ModListPath $modListPath -ModsRoot $modsRoot)) {
            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($builtIns.ContainsKey($name)) { continue }
            if ($name.StartsWith('(')) { continue }
            if (-not $names.Contains($name)) { [void]$names.Add($name) }
        }
    }

    if ($names.Count -eq 0) {
        if ($StatusLabel) { $StatusLabel.Text = 'No removable local Factorio mod ZIPs were found.' }
        return ''
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Remove Factorio Mod'
    $form.StartPosition = 'CenterParent'
    $form.Width = 420
    $form.Height = 360
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.FormBorderStyle = 'FixedDialog'
    $form.ShowInTaskbar = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Select the local Factorio mod ZIP to remove from this profile:'
    $label.Left = 12
    $label.Top = 12
    $label.Width = 380
    $label.Height = 22
    [void]$form.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Left = 12
    $list.Top = 40
    $list.Width = 380
    $list.Height = 230
    $list.SelectionMode = 'One'
    foreach ($name in @($names.ToArray() | Sort-Object)) { [void]$list.Items.Add([string]$name) }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    [void]$form.Controls.Add($list)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Remove Selected'
    $ok.Left = 192
    $ok.Top = 285
    $ok.Width = 105
    $ok.Height = 28
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Left = 305
    $cancel.Top = 285
    $cancel.Width = 87
    $cancel.Height = 28
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $list.Add_DoubleClick({ if ($list.SelectedIndex -ge 0) { $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() } }.GetNewClosure())

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedIndex -ge 0 -and $null -ne $list.SelectedItem) {
        return [string]$list.SelectedItem
    }

    if ($StatusLabel) { $StatusLabel.Text = 'Factorio mod remove cancelled.' }
    return ''
}

function Remove-UGSMGameFactorioLocalMod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$ModName,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    if ([string]::IsNullOrWhiteSpace($ModName)) {
        throw 'Factorio mod remove failed: no local mod was selected.'
    }

    $builtIns = @{}
    foreach ($builtIn in (Get-UGSMGameFactorioBuiltInModNames)) { $builtIns[[string]$builtIn] = $true }
    if ($builtIns.ContainsKey($ModName)) {
        throw ("Factorio mod remove failed: '{0}' is a built-in mod and cannot be removed here." -f $ModName)
    }

    if ($null -eq $Paths) { $Paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance }
    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modsRoot)) {
        throw 'Factorio mod remove failed: mods folder path could not be resolved.'
    }

    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $Paths
    if ([string]::IsNullOrWhiteSpace($modListPath)) {
        $modListPath = Join-Path $modsRoot 'mod-list.json'
    }

    $removedFiles = 0
    foreach ($zip in @(Get-UGSMGameFactorioModZipEntries -ModsRoot $modsRoot)) {
        if ([string]$zip.Name -eq [string]$ModName -and -not [string]::IsNullOrWhiteSpace([string]$zip.Path) -and (Test-Path -LiteralPath ([string]$zip.Path) -PathType Leaf)) {
            Remove-Item -LiteralPath ([string]$zip.Path) -Force -ErrorAction Stop
            $removedFiles++
        }
    }

    $modList = Read-UGSMGameFactorioModListObject -ModListPath $modListPath
    $remainingMods = New-Object System.Collections.Generic.List[object]
    foreach ($mod in @($modList.mods)) {
        if ($mod -and $mod.PSObject.Properties['name'] -and [string]$mod.name -eq [string]$ModName) { continue }
        [void]$remainingMods.Add($mod)
    }

    $modList.mods = @($remainingMods.ToArray())
    Write-UGSMGameFactorioJsonFile -Path $modListPath -Value $modList

    if ($StatusLabel) {
        $StatusLabel.Text = ("Removed Factorio mod '{0}'. ZIP files removed: {1}." -f $ModName, $removedFiles)
    }
}


function Get-UGSMGameFactorioJsonPathValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$JsonObject,
        [Parameter(Mandatory)][string]$JsonPath,
        [AllowNull()]$DefaultValue
    )

    if ($null -eq $JsonObject -or [string]::IsNullOrWhiteSpace($JsonPath)) { return $DefaultValue }

    $current = $JsonObject
    foreach ($part in @($JsonPath -split '\.')) {
        if ($null -eq $current -or [string]::IsNullOrWhiteSpace($part)) { return $DefaultValue }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($part)) { return $DefaultValue }
            $current = $current[$part]
        }
        else {
            $prop = $current.PSObject.Properties[$part]
            if (-not $prop) { return $DefaultValue }
            $current = $prop.Value
        }
    }

    if ($null -eq $current) { return $DefaultValue }
    return $current
}

function Set-UGSMGameFactorioJsonPathValue {

    [CmdletBinding()]
    param(
        [AllowNull()]$JsonObject,
        [Parameter(Mandatory)][string]$JsonPath,
        [AllowNull()]$Value
    )

    if ($null -eq $JsonObject) { $JsonObject = [pscustomobject]@{} }

    $parts = @($JsonPath -split '\.' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($parts.Count -eq 0) { return $JsonObject }

    $current = $JsonObject
    for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
        $part = [string]$parts[$i]
        $prop = $current.PSObject.Properties[$part]
        if (-not $prop -or $null -eq $prop.Value) {
            $child = [pscustomobject]@{}
            Add-Member -InputObject $current -MemberType NoteProperty -Name $part -Value $child -Force
            $current = $child
        }
        else {
            $current = $prop.Value
        }
    }

    $leaf = [string]$parts[$parts.Count - 1]
    if ($current.PSObject.Properties[$leaf]) { $current.$leaf = $Value }
    else { Add-Member -InputObject $current -MemberType NoteProperty -Name $leaf -Value $Value -Force }

    return $JsonObject
}

function ConvertTo-UGSMGameFactorioJsonEditorValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [AllowNull()]$Value
    )

    $kind = ''
    if ($Field.ContainsKey('ValueKind')) { $kind = [string]$Field.ValueKind }

    switch ($kind) {
        'Boolean' { return [bool]$Value }
        'Integer' {
            $n = 0
            [void][int]::TryParse([string]$Value, [ref]$n)
            return $n
        }
        'Number' {
            $d = [decimal]0
            [void][decimal]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)
            return $d
        }
        'StringArray' {
            if ($null -eq $Value) { return @() }
            if ($Value -is [array]) { return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
            return @(([string]$Value -split "(`r`n|`n|,)") | ForEach-Object { [string]$_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        'RawJson' {
            $raw = [string]$Value
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
            try {
                $parsed = ConvertFrom-Json -InputObject $raw
                $trimmed = $raw.TrimStart()
                if ($trimmed.StartsWith('[')) {
                    $list = New-Object System.Collections.ArrayList
                    if ($null -ne $parsed) {
                        if ($parsed -is [System.Array]) {
                            foreach ($item in $parsed) { [void]$list.Add($item) }
                        }
                        else {
                            [void]$list.Add($parsed)
                        }
                    }
                    return ,$list
                }
                return $parsed
            }
            catch {
                throw ("Factorio save failed: field '{0}' must contain valid JSON. {1}" -f [string]$Field.Id, $_.Exception.Message)
            }
        }
        default { return [string]$Value }
    }
}

function ConvertTo-UGSMGameFactorioEditorDisplayValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [AllowNull()][hashtable]$Field
    )

    if ($null -eq $Value) {
        if ($Field -and $Field.ContainsKey('ValueKind') -and [string]$Field.ValueKind -eq 'RawJson') { return 'null' }
        return ''
    }

    if ($Field -and $Field.ContainsKey('ValueKind') -and [string]$Field.ValueKind -eq 'RawJson') {
        if ($Value -is [string]) { return [string]$Value }

        $jsonValue = $Value
        if ($Field.ContainsKey('Id') -and [string]$Field.Id -eq 'StartingPoints') {
            if ($null -eq $jsonValue) {
                $jsonValue = @()
            }
            elseif ($jsonValue -is [System.Collections.IList] -or $jsonValue -is [System.Array]) {
                $pointsList = New-Object System.Collections.ArrayList
                foreach ($point in @($jsonValue)) { [void]$pointsList.Add($point) }
                $jsonValue = $pointsList
            }
            else {
                $pointsList = New-Object System.Collections.ArrayList
                [void]$pointsList.Add($jsonValue)
                $jsonValue = $pointsList
            }
        }

        return [string](ConvertTo-Json -InputObject $jsonValue -Depth 100)
    }

    if ($Value -is [array]) { return (@($Value) -join [Environment]::NewLine) }
    return [string]$Value
}


function Read-UGSMGameFactorioXmlFile {
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

function Write-UGSMGameFactorioXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameFactorioParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameFactorioCfgFile {
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

function Set-UGSMGameFactorioCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameFactorioParentDirectory -Path $Path

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
function Test-UGSMGameFactorioPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameFactorioPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameFactorioPSSQLiteInstalled)
}

function Get-UGSMGameFactorioElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameFactorioPSSQLiteInstalled)) {
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

function Save-UGSMGameFactorioElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameFactorioPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'Factorio.db was not found.'
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


function Resolve-UGSMGameFactorioEditorFieldPath {
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

            if ($Field.ContainsKey('File') -and -not [string]::IsNullOrWhiteSpace([string]$Field.File) -and -not [string]::IsNullOrWhiteSpace($configRoot)) {
                return [string](Join-Path $configRoot ([string]$Field.File))
            }

            return $null
        }
    }
}

function ConvertTo-UGSMGameFactorioEditorFieldValue {
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


function Get-UGSMGameFactorioInstanceDefinitionPath {
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

function Save-UGSMGameFactorioInstanceDefinition {
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

    $definitionPath = Get-UGSMGameFactorioInstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameFactorioInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameFactorioInstanceDiscordShape -Instance $Instance
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false

    foreach ($dirPath in @($paths.ConfigRoot, $paths.SaveRoot, $paths.LogRoot, $paths.ModsRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }

    $saveSummary = [ordered]@{
        JsonKeysWritten      = 0
        IniKeysWritten       = 0
        StringListsWritten   = 0
        InstanceSettingsSaved = 0
    }

    Invoke-UGSMGameFactorioManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before Factorio settings save' | Out-Null

    $jsonCache = @{}

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        if ($field -isnot [hashtable]) {
            $normalizedField = @{}
            foreach ($prop in @($field.PSObject.Properties)) { $normalizedField[[string]$prop.Name] = $prop.Value }
            $field = $normalizedField
        }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $field -Paths $paths
                }
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("Factorio save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                if ($field.ContainsKey('File') -and ([string]$field.File).ToLowerInvariant().EndsWith('.json')) {
                    Write-UGSMGameFactorioJsonFile -Path $targetPath -Value @($values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    $saveSummary.JsonKeysWritten++
                }
                else {
                    Write-UGSMGameFactorioStringListFile -Path $targetPath -Values $values
                    $saveSummary.StringListsWritten++
                }
            }

            'Boolean' { 
                $rawValue = ConvertTo-UGSMGameFactorioEditorFieldValue -Field $field -Control $control
                if ($field.ContainsKey('File') -and ([string]$field.File).ToLowerInvariant().EndsWith('.json')) {
                    $targetPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $field -Paths $paths
                    if (-not $jsonCache.ContainsKey($targetPath)) { $jsonCache[$targetPath] = Read-UGSMGameFactorioJsonFile -Path $targetPath }
                    $jsonPath = $(if ($field.ContainsKey('JsonPath')) { [string]$field.JsonPath } else { [string]$field.Key })
                    if ($jsonPath -eq '__instance_port_only') { continue }
                    $jsonValue = ConvertTo-UGSMGameFactorioJsonEditorValue -Field $field -Value $rawValue
                    $jsonCache[$targetPath] = Set-UGSMGameFactorioJsonPathValue -JsonObject $jsonCache[$targetPath] -JsonPath $jsonPath -Value $jsonValue
                    $saveSummary.JsonKeysWritten++
                }
                else {
                    Set-UGSMGameFactorioIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $rawValue
                    $saveSummary.IniKeysWritten++
                }
            }

            { $_ -in @('Number','MultilineText','Text','Password') } {
                $rawValue = ConvertTo-UGSMGameFactorioEditorFieldValue -Field $field -Control $control
                if ($field.ContainsKey('File') -and ([string]$field.File).ToLowerInvariant().EndsWith('.json')) {
                    $targetPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $field -Paths $paths
                    if (-not $jsonCache.ContainsKey($targetPath)) { $jsonCache[$targetPath] = Read-UGSMGameFactorioJsonFile -Path $targetPath }
                    $jsonPath = $(if ($field.ContainsKey('JsonPath')) { [string]$field.JsonPath } else { [string]$field.Key })
                    if ($jsonPath -eq '__instance_port_only') { continue }
                    $jsonValue = ConvertTo-UGSMGameFactorioJsonEditorValue -Field $field -Value $rawValue
                    $jsonCache[$targetPath] = Set-UGSMGameFactorioJsonPathValue -JsonObject $jsonCache[$targetPath] -JsonPath $jsonPath -Value $jsonValue
                    $saveSummary.JsonKeysWritten++
                }
                else {
                    Set-UGSMGameFactorioIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $rawValue
                    $saveSummary.IniKeysWritten++
                }
            }

            'FactorioSpaceAgeToggle' {
                $enabled = [bool]$control.Checked
                $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$modListPath)) {
                    throw "Factorio save failed: mod-list.json path could not be resolved for Space Age toggle."
                }

                Set-UGSMGameFactorioSpaceAgeEnabled -ModListPath $modListPath -Enabled $enabled
                $saveSummary.JsonKeysWritten++
            }

            'FactorioLocalModList' {
                $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $paths
                if ([string]::IsNullOrWhiteSpace([string]$modListPath)) {
                    throw "Factorio save failed: mod-list.json path could not be resolved for local mods."
                }

                $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $paths
                if ([string]::IsNullOrWhiteSpace($modsRoot)) {
                    throw "Factorio save failed: mods folder path could not be resolved for local mods."
                }

                $enabledNames = New-Object System.Collections.Generic.List[string]
                if ($control.Enabled) {
                    foreach ($checkedItem in @($control.CheckedItems)) {
                        $name = [string]$checkedItem
                        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $enabledNames.Contains($name)) {
                            [void]$enabledNames.Add($name)
                        }
                    }
                }

                Set-UGSMGameFactorioLocalModsEnabled -ModListPath $modListPath -ModsRoot $modsRoot -EnabledNames @($enabledNames.ToArray())
                $saveSummary.JsonKeysWritten++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameFactorioEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameFactorioEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }
        }
    }

    foreach ($jsonPath in @($jsonCache.Keys)) {
        if ($null -eq $jsonCache[$jsonPath]) { $jsonCache[$jsonPath] = [pscustomobject]@{} }
        Write-UGSMGameFactorioJsonFile -Path $jsonPath -Value $jsonCache[$jsonPath]
    }

    $updatedInstance = Update-UGSMGameFactorioInstanceServerDisplayName -Instance $updatedInstance -ServerSettingsPath ([string]$paths.ServerSettingsPath)
    Save-UGSMGameFactorioInstanceDefinition -Instance $updatedInstance | Out-Null

    if ($hasDiscordChanges) {
        $persistScript = {
            param($PersistedInstance)
            [void](Save-UGSMGameFactorioInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved Factorio settings. JSON keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.JsonKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}



function New-UGSMGameFactorioInstanceEditor {
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

    $Instance = Ensure-UGSMGameFactorioInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance
    $schema = Get-UGSMGameFactorioEditorSchema
    $iniData = Read-UGSMGameFactorioIniFile -Path $paths.ServerSettingsPath
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

    function Get-FactorioSafeIniValue {
        param([hashtable]$Field)
        try {
            $defaultValue = $(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })

            if ($Field.ContainsKey('File') -and ([string]$Field.File).ToLowerInvariant().EndsWith('.json')) {
                $jsonPath = $null
                if ($Field.ContainsKey('JsonPath')) { $jsonPath = [string]$Field.JsonPath }
                elseif ($Field.ContainsKey('Key')) { $jsonPath = [string]$Field.Key }

                $targetPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $Field -Paths $paths
                $jsonObject = Read-UGSMGameFactorioJsonFile -Path $targetPath
                $rawValue = Get-UGSMGameFactorioJsonPathValue -JsonObject $jsonObject -JsonPath $jsonPath -DefaultValue $defaultValue
                return [string](ConvertTo-UGSMGameFactorioEditorDisplayValue -Value $rawValue -Field $Field)
            }

            return [string](Get-UGSMGameFactorioIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $defaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'Factorio field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-FactorioSafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'Factorio instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-FactorioTextBox {
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

    function New-FactorioStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-FactorioTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-FactorioNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-FactorioElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits Factorio.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMGameFactorioPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in Factorio.db.')
                return
            }

            $dbPath = Resolve-UGSMGameFactorioDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('Factorio.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('Factorio.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameFactorioElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading Factorio.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameFactorioPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameFactorioDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'Factorio.db path could not be resolved for this instance.' }
                    Save-UGSMGameFactorioElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to Factorio.db: ' + $dbPath }
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

    function Add-FactorioFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the Factorio editor can render any supported schema shape.
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
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameFactorioModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the Factorio Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-FactorioNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-FactorioSafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'FactorioSpaceAgeToggle' {
                    $fieldHost = New-FactorioNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $paths
                    $control.Checked = if ([string]::IsNullOrWhiteSpace([string]$modListPath)) { $false } else { Get-UGSMGameFactorioSpaceAgeEnabled -ModListPath $modListPath }
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'FactorioLocalModList' {
                    $modsHost = New-Object System.Windows.Forms.Panel
                    $modsHost.Dock = 'Top'
                    $modsHost.Height = 180
                    $modsHost.Margin = New-Object System.Windows.Forms.Padding(0)
                    $modsHost.Padding = New-Object System.Windows.Forms.Padding(0)

                    $control = New-Object System.Windows.Forms.CheckedListBox
                    $control.Dock = 'Fill'
                    $control.CheckOnClick = $true
                    $control.BackColor = New-UGSMColor $Theme.Input
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.BorderStyle = 'FixedSingle'
                    $control.HorizontalScrollbar = $true

                    $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $paths
                    $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $paths

                    if (-not [string]::IsNullOrWhiteSpace([string]$modListPath) -and -not [string]::IsNullOrWhiteSpace([string]$modsRoot)) {
                        foreach ($rowItem in @(Get-UGSMGameFactorioLocalModRows -ModListPath $modListPath -ModsRoot $modsRoot)) {
                            $index = $control.Items.Add([string]$rowItem.Name)
                            $control.SetItemChecked($index, [bool]$rowItem.Enabled)
                        }
                    }

                    if ($control.Items.Count -eq 0) {
                        [void]$control.Items.Add('(No local mod ZIPs found. Use Import Mod ZIPs, then reload this editor.)')
                        $control.Enabled = $false
                    }
                    else {
                        $control.Add_SelectedIndexChanged({
                                try {
                                    if ($this.SelectedIndex -ge 0 -and $null -ne $this.SelectedItem) {
                                        $script:UGSMGameFactorioLastSelectedLocalMod = [string]$this.SelectedItem
                                    }
                                } catch { }
                            })
                        $control.Add_MouseDown({
                                param($sender, $eventArgs)
                                try {
                                    $hitIndex = $sender.IndexFromPoint($eventArgs.Location)
                                    if ($hitIndex -ge 0 -and $hitIndex -lt $sender.Items.Count) {
                                        $script:UGSMGameFactorioLastSelectedLocalMod = [string]$sender.Items[$hitIndex]
                                    }
                                } catch { }
                            })
                    }

                    [void]$modsHost.Controls.Add($control)
                    [void]$row.Controls.Add($modsHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                    $script:UGSMGameFactorioLastLocalModListControl = $control
                }
                'InstanceBoolean' {
                    $fieldHost = New-FactorioNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-FactorioSafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-FactorioNarrowHost
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
                    $rawValue = Get-FactorioSafeIniValue -Field $Field
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
                    $control = New-FactorioStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-FactorioSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-FactorioStretchTextBox -MaskSecret
                    $control.Text = [string](Get-FactorioSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-FactorioStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-FactorioSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-FactorioTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameFactorioEditorFieldPath -Field $Field -Paths $paths
                    $control.Tag = [string]$resolvedListPath
                    $control.ScrollBars = 'Vertical'
                    $control.AcceptsReturn = $true
                    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedListPath) -and (Test-Path -LiteralPath $resolvedListPath -PathType Leaf)) {
                        if ($Field.ContainsKey('File') -and ([string]$Field.File).ToLowerInvariant().EndsWith('.json')) {
                            $jsonList = Read-UGSMGameFactorioJsonFile -Path $resolvedListPath
                            if ($jsonList -is [array]) {
                                $control.Lines = @($jsonList | ForEach-Object { [string]$_ })
                            }
                            elseif ($null -ne $jsonList) {
                                $control.Lines = @([string]$jsonList)
                            }
                        }
                        else {
                            $control.Lines = @(Get-Content -LiteralPath $resolvedListPath -ErrorAction SilentlyContinue)
                        }
                    }
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control; Path = $resolvedListPath }
                }
                'FactorioRemoveSelectedModButton' {
                    $buttonHost = New-FactorioNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor $Theme.Button
                    $control.Add_Click({
                            try {
                                $modsList = $null

                                if ($null -ne $controlMap -and $controlMap.ContainsKey('LocalMods')) {
                                    $modsEntry = $controlMap['LocalMods']
                                    if ($modsEntry -and $modsEntry.Control) { $modsList = $modsEntry.Control }
                                }

                                if ($null -eq $modsList -and $script:UGSMGameFactorioLastLocalModListControl) {
                                    $modsList = $script:UGSMGameFactorioLastLocalModListControl
                                }

                                $selectedMod = ''
                                if ($null -ne $modsList) {
                                    try {
                                        if ($modsList.SelectedIndex -ge 0 -and $null -ne $modsList.SelectedItem) {
                                            $selectedMod = [string]$modsList.SelectedItem
                                        }
                                    } catch { $selectedMod = '' }

                                    if ([string]::IsNullOrWhiteSpace($selectedMod)) {
                                        try {
                                            if ($modsList.CheckedItems -and $modsList.CheckedItems.Count -eq 1) {
                                                $selectedMod = [string]$modsList.CheckedItems[0]
                                            }
                                        } catch { $selectedMod = '' }
                                    }
                                }

                                if ([string]::IsNullOrWhiteSpace($selectedMod) -and -not [string]::IsNullOrWhiteSpace([string]$script:UGSMGameFactorioLastSelectedLocalMod)) {
                                    $selectedMod = [string]$script:UGSMGameFactorioLastSelectedLocalMod
                                }

                                if ([string]::IsNullOrWhiteSpace($selectedMod)) {
                                    try {
                                        $modListPathForFallback = Get-UGSMGameFactorioModListPathFromPaths -Paths $paths
                                        $modsRootForFallback = Get-UGSMGameFactorioModsRootFromPaths -Paths $paths
                                        if (-not [string]::IsNullOrWhiteSpace([string]$modListPathForFallback) -and -not [string]::IsNullOrWhiteSpace([string]$modsRootForFallback)) {
                                            $fallbackRows = @(Get-UGSMGameFactorioLocalModRows -ModListPath $modListPathForFallback -ModsRoot $modsRootForFallback)
                                            if ($fallbackRows.Count -eq 1) {
                                                $selectedMod = [string]$fallbackRows[0].Name
                                            }
                                        }
                                    } catch { $selectedMod = '' }
                                }

                                if ([string]::IsNullOrWhiteSpace($selectedMod) -or $selectedMod.StartsWith('(')) {
                                    $selectedMod = Select-UGSMGameFactorioLocalModForRemove -Instance $Instance -Paths $paths -StatusLabel $StatusLabel
                                }

                                if ([string]::IsNullOrWhiteSpace($selectedMod) -or $selectedMod.StartsWith('(')) {
                                    return
                                }

                                Add-Type -AssemblyName System.Windows.Forms
                                $confirm = [System.Windows.Forms.MessageBox]::Show(
                                    ("Remove local Factorio mod '{0}' from this profile?`r`n`r`nThis deletes the matching ZIP file(s) from the profile mods folder and removes the mod from mod-list.json." -f $selectedMod),
                                    'Remove Factorio Mod',
                                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                                    [System.Windows.Forms.MessageBoxIcon]::Warning
                                )
                                if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                                    if ($StatusLabel) { $StatusLabel.Text = 'Factorio mod remove cancelled.' }
                                    return
                                }

                                Remove-UGSMGameFactorioLocalMod -Instance $Instance -Paths $paths -ModName $selectedMod -StatusLabel $StatusLabel

                                # Keep this button action surgical and avoid WinForms refresh/null edge cases here.
                                # Reloading the editor rebuilds the local mod list from the profile mods folder and mod-list.json.
                                if ($StatusLabel) {
                                    $StatusLabel.Text = ("Removed Factorio mod '{0}'. Reload the editor to refresh the local mod list." -f $selectedMod)
                                }
                            }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'Factorio action failed: ' + $_.Exception.Message } }
                        }.GetNewClosure())
                    [void]$buttonHost.Controls.Add($control)
                    [void]$row.Controls.Add($buttonHost, 1, 0)
                }
                'ActionButton' {
                    $buttonHost = New-FactorioNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor $Theme.Button
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'Factorio action failed: ' + $_.Exception.Message } }
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

                    New-FactorioElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-FactorioStretchTextBox
                    $control.Text = [string](Get-FactorioSafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('Factorio field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Danger
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-FactorioEditorContent {
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
            Add-FactorioFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('Factorio Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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
                $modsTabFeatures = Get-UGSMGameFactorioSupportedFeatures
                if ([bool]$modsTabFeatures.Mods) {
                    try {
                        $modsDefinition = Get-UGSMGameFactorioModsDefinition
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
                        $err = New-UGSMLabel -Text ('Factorio shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color $Theme.Danger
                        [void]$tabPage.Controls.Add($err)
                        if ($StatusLabel) { $StatusLabel.Text = 'Factorio shared Mods tab failed: ' + $_.Exception.Message }
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
                    New-FactorioEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-FactorioEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameFactorioInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved Factorio profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'Factorio save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameFactorioInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'Factorio profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'Factorio reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'Factorio profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameFactorioOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'Factorio open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("Factorio open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'Factorio open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("Factorio open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("Factorio open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameFactorioEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'Factorio action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameFactorioProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("Factorio action failed: could not resolve paths for '{0}'." -f $Target)
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
        'ModsFolder' {
            $modsRoot = Get-UGSMGameFactorioModsRootFromPaths -Paths $Paths
            if (-not [string]::IsNullOrWhiteSpace([string]$modsRoot)) { [string]$modsRoot } else { $null }
        }
        'ModList' {
            $modListPath = Get-UGSMGameFactorioModListPathFromPaths -Paths $Paths
            if (-not [string]::IsNullOrWhiteSpace([string]$modListPath)) { [string]$modListPath } else { $null }
        }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        throw ("Factorio action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameFactorioEditorAction {
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

    $resolvedPath = Resolve-UGSMGameFactorioEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameFactorioOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}


<#Adjust Schema to be game specific. these values were taken from Ark Survival Evolved. #>




function Get-UGSMGameFactorioEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenServerSettings = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryJson' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened server-settings.json.' }
        OpenMapGenSettings = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioOpenPath -Path (Join-Path $Paths.ConfigRoot 'map-gen-settings.json') -StatusLabel $StatusLabel }
        OpenMapSettings    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioOpenPath -Path (Join-Path $Paths.ConfigRoot 'map-settings.json') -StatusLabel $StatusLabel }
        OpenConfigFolder   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioOpenPath -Path $Paths.ConfigRoot -StatusLabel $StatusLabel }
        OpenSavesFolder    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioOpenPath -Path $Paths.SaveRoot -StatusLabel $StatusLabel }
        OpenLogsFolder     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioOpenPath -Path $Paths.LogRoot -StatusLabel $StatusLabel }
        OpenModsFolder     = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioEditorAction -Instance $Instance -Paths $Paths -Target 'ModsFolder' -EnsureFolder -StatusLabel $StatusLabel -OpenedMessage 'Opened the profile mods folder.' }
        OpenModList        = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameFactorioEditorAction -Instance $Instance -Paths $Paths -Target 'ModList' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened mod-list.json.' }
        ImportModZip       = { param($Instance, $Paths, $StatusLabel) Import-UGSMGameFactorioLocalModZip -Instance $Instance -Paths $Paths -StatusLabel $StatusLabel }
        SyncLocalMods      = { param($Instance, $Paths, $StatusLabel) Sync-UGSMGameFactorioLocalModListFromFolder -Instance $Instance -Paths $Paths -StatusLabel $StatusLabel }
    }

    $ss = 'server-settings.json'
    $mg = 'map-gen-settings.json'
    $ms = 'map-settings.json'

    $schema = [pscustomobject]@{
        Version = 3
        Tabs = @(
            [pscustomobject]@{
                Title       = 'Server'
                Description = 'Factorio server identity and player access settings from server-settings.json.'
                Fields      = @(
                    @{ Id='Name'; Type='Text'; File=$ss; JsonPath='name'; Key='name'; Label='Server Name'; DefaultValue='My UGSM Server'; ValueKind='String'; Hint='Name shown in the Factorio multiplayer browser.' }
                    @{ Id='Description'; Type='MultilineText'; File=$ss; JsonPath='description'; Key='description'; Label='Description'; DefaultValue='Factorio server managed by UGSM.'; ValueKind='String'; Hint='Public server description.' }
                    @{ Id='Tags'; Type='MultilineText'; File=$ss; JsonPath='tags'; Key='tags'; Label='Tags'; DefaultValue='game'; ValueKind='StringArray'; Hint='One tag per line. Saved as the JSON tags array.' }
                    @{ Id='MaxPlayers'; Type='Number'; File=$ss; JsonPath='max_players'; Key='max_players'; Label='Max Players'; DefaultValue=0; Min=0; Max=65535; Decimals=0; ValueKind='Integer'; Hint='0 means unlimited. Admins can join a full server.' }
                    @{ Id='GamePassword'; Type='Password'; File=$ss; JsonPath='game_password'; Key='game_password'; Label='Game Password'; DefaultValue=''; ValueKind='String'; Hint='Optional password required to join. Masked on screen.' }
                    @{ Id='RequireUserVerification'; Type='Boolean'; File=$ss; JsonPath='require_user_verification'; Key='require_user_verification'; Label='Require Factorio Account'; DefaultValue=$true; ValueKind='Boolean'; Hint='Only allow clients with a valid Factorio.com account.' }
                    @{ Id='EnableSpaceAge'; Type='FactorioSpaceAgeToggle'; Label='Enable Space Age DLC'; DefaultValue=$false; Hint='Writes Space Age to mods\mod-list.json. Also enables the built-in Quality and Elevated Rails dependencies.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Visibility / Login'
                Description = 'Public listing settings. Public visibility requires Factorio.com credentials or token.'
                Fields      = @(
                    @{ Id='VisibilityPublic'; Type='Boolean'; File=$ss; JsonPath='visibility.public'; Key='visibility.public'; Label='Public Server Browser'; DefaultValue=$false; ValueKind='Boolean'; Hint='Publish on the official Factorio matching server.' }
                    @{ Id='VisibilityLan'; Type='Boolean'; File=$ss; JsonPath='visibility.lan'; Key='visibility.lan'; Label='LAN Broadcast'; DefaultValue=$true; ValueKind='Boolean'; Hint='Broadcast on LAN.' }
                    @{ Id='Username'; Type='Text'; File=$ss; JsonPath='username'; Key='username'; Label='Factorio.com Username'; DefaultValue=''; ValueKind='String'; Hint='Required for public games unless using token.' }
                    @{ Id='Password'; Type='Password'; File=$ss; JsonPath='password'; Key='password'; Label='Factorio.com Password'; DefaultValue=''; ValueKind='String'; Hint='Masked. Use token instead when possible.' }
                    @{ Id='Token'; Type='Password'; File=$ss; JsonPath='token'; Key='token'; Label='Factorio.com Token'; DefaultValue=''; ValueKind='String'; Hint='Masked. May be used instead of password.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network'
                Description = 'Gameplay port and upload/network limits.'
                Fields      = @(
                    @{ Id='GamePort'; Type='Number'; File=$ss; JsonPath='__instance_port_only'; Key='__instance_port_only'; Label='Game Port'; DefaultValue=34197; Min=1; Max=65535; Decimals=0; ValueKind='Integer'; Hint='Factorio default is 34197 UDP. Start currently reads the instance port when available.' }
                    @{ Id='MaxUploadKbps'; Type='Number'; File=$ss; JsonPath='max_upload_in_kilobytes_per_second'; Key='max_upload_in_kilobytes_per_second'; Label='Max Upload KB/s'; DefaultValue=0; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='0 means unlimited.' }
                    @{ Id='MaxUploadSlots'; Type='Number'; File=$ss; JsonPath='max_upload_slots'; Key='max_upload_slots'; Label='Max Upload Slots'; DefaultValue=5; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='0 means unlimited.' }
                    @{ Id='MinimumLatencyTicks'; Type='Number'; File=$ss; JsonPath='minimum_latency_in_ticks'; Key='minimum_latency_in_ticks'; Label='Minimum Latency Ticks'; DefaultValue=0; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='One tick is 16ms at default speed. 0 means no minimum.' }
                    @{ Id='MaxHeartbeats'; Type='Number'; File=$ss; JsonPath='max_heartbeats_per_second'; Key='max_heartbeats_per_second'; Label='Max Heartbeats / Sec'; DefaultValue=60; Min=6; Max=240; Decimals=0; ValueKind='Integer'; Hint='Network update packet rate before bundling.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Gameplay'
                Description = 'Pause, command, autosave, and AFK behavior.'
                Fields      = @(
                    @{ Id='AllowCommands'; Type='Text'; File=$ss; JsonPath='allow_commands'; Key='allow_commands'; Label='Allow Commands'; DefaultValue='admins-only'; ValueKind='String'; Hint='Allowed values: true, false, admins-only.' }
                    @{ Id='IgnorePlayerLimitReturning'; Type='Boolean'; File=$ss; JsonPath='ignore_player_limit_for_returning_players'; Key='ignore_player_limit_for_returning_players'; Label='Returning Players Ignore Limit'; DefaultValue=$false; ValueKind='Boolean'; Hint='Players who already played on the map can join when full.' }
                    @{ Id='AutosaveInterval'; Type='Number'; File=$ss; JsonPath='autosave_interval'; Key='autosave_interval'; Label='Autosave Interval Minutes'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Autosave interval in minutes.' }
                    @{ Id='AutosaveSlots'; Type='Number'; File=$ss; JsonPath='autosave_slots'; Key='autosave_slots'; Label='Autosave Slots'; DefaultValue=5; Min=1; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Server autosave slot count.' }
                    @{ Id='AfkAutokick'; Type='Number'; File=$ss; JsonPath='afk_autokick_interval'; Key='afk_autokick_interval'; Label='AFK Autokick Minutes'; DefaultValue=0; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='0 means never kick.' }
                    @{ Id='AutoPause'; Type='Boolean'; File=$ss; JsonPath='auto_pause'; Key='auto_pause'; Label='Pause When Empty'; DefaultValue=$true; ValueKind='Boolean'; Hint='Pause the server when no players are present.' }
                    @{ Id='AutoPauseConnect'; Type='Boolean'; File=$ss; JsonPath='auto_pause_when_players_connect'; Key='auto_pause_when_players_connect'; Label='Pause While Players Connect'; DefaultValue=$false; ValueKind='Boolean'; Hint='Pause while someone is connecting.' }
                    @{ Id='OnlyAdminsPause'; Type='Boolean'; File=$ss; JsonPath='only_admins_can_pause_the_game'; Key='only_admins_can_pause_the_game'; Label='Only Admins Can Pause'; DefaultValue=$true; ValueKind='Boolean'; Hint='Only admins may pause the game.' }
                    @{ Id='AutosaveOnlyServer'; Type='Boolean'; File=$ss; JsonPath='autosave_only_on_server'; Key='autosave_only_on_server'; Label='Autosave Only On Server'; DefaultValue=$true; ValueKind='Boolean'; Hint='Autosaves saved only on server.' }
                    @{ Id='NonBlockingSaving'; Type='Boolean'; File=$ss; JsonPath='non_blocking_saving'; Key='non_blocking_saving'; Label='Non-blocking Saving'; DefaultValue=$false; ValueKind='Boolean'; Hint='Experimental. Use carefully.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Segments'
                Description = 'Advanced network segment tuning. Changing these can affect connection stability.'
                Fields      = @(
                    @{ Id='MinimumSegmentSize'; Type='Number'; File=$ss; JsonPath='minimum_segment_size'; Key='minimum_segment_size'; Label='Minimum Segment Size'; DefaultValue=25; Min=1; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Lower segment size for low peer counts.' }
                    @{ Id='MinimumSegmentPeerCount'; Type='Number'; File=$ss; JsonPath='minimum_segment_size_peer_count'; Key='minimum_segment_size_peer_count'; Label='Minimum Segment Peer Count'; DefaultValue=20; Min=1; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Peer count for minimum segment size.' }
                    @{ Id='MaximumSegmentSize'; Type='Number'; File=$ss; JsonPath='maximum_segment_size'; Key='maximum_segment_size'; Label='Maximum Segment Size'; DefaultValue=100; Min=1; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Higher segment size for lower peer counts.' }
                    @{ Id='MaximumSegmentPeerCount'; Type='Number'; File=$ss; JsonPath='maximum_segment_size_peer_count'; Key='maximum_segment_size_peer_count'; Label='Maximum Segment Peer Count'; DefaultValue=10; Min=1; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Peer count for maximum segment size.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Map Gen'
                Description = 'New-world map generation settings from map-gen-settings.json. Existing saves are not regenerated by changing these.'
                Fields      = @(
                    @{ Id='MapWidth'; Type='Number'; File=$mg; JsonPath='width'; Key='width'; Label='Map Width'; DefaultValue=0; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Width in tiles. 0 means infinite.' }
                    @{ Id='MapHeight'; Type='Number'; File=$mg; JsonPath='height'; Key='height'; Label='Map Height'; DefaultValue=0; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Height in tiles. 0 means infinite.' }
                    @{ Id='StartingArea'; Type='Number'; File=$mg; JsonPath='starting_area'; Key='starting_area'; Label='Starting Area'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Multiplier for the biter-free starting area.' }
                    @{ Id='PeacefulMode'; Type='Boolean'; File=$mg; JsonPath='peaceful_mode'; Key='peaceful_mode'; Label='Peaceful Mode'; DefaultValue=$false; ValueKind='Boolean'; Hint='Enemies do not attack first when enabled.' }
                    @{ Id='MapSeed'; Type='Text'; File=$mg; JsonPath='seed'; Key='seed'; Label='Seed JSON'; DefaultValue='null'; ValueKind='RawJson'; Hint='Use null for random seed, or a JSON number for a fixed seed.' }
                    @{ Id='StartingPoints'; Type='MultilineText'; File=$mg; JsonPath='starting_points'; Key='starting_points'; Label='Starting Points JSON'; DefaultValue='[{"x":0,"y":0}]'; ValueKind='RawJson'; Hint='JSON array of starting points, for example [{"x":0,"y":0}].' }
                )
            }

            [pscustomobject]@{
                Title       = 'Resources'
                Description = 'Autoplace resource, terrain, tree, water, and enemy-base generation from map-gen-settings.json.'
                Fields      = @(
                    @{ Id='CoalFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.coal.frequency'; Key='autoplace_controls.coal.frequency'; Label='Coal Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Coal patch frequency.' }
                    @{ Id='CoalSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.coal.size'; Key='autoplace_controls.coal.size'; Label='Coal Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Coal patch size.' }
                    @{ Id='CoalRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.coal.richness'; Key='autoplace_controls.coal.richness'; Label='Coal Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Coal patch richness.' }
                    @{ Id='StoneFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.stone.frequency'; Key='autoplace_controls.stone.frequency'; Label='Stone Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Stone patch frequency.' }
                    @{ Id='StoneSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.stone.size'; Key='autoplace_controls.stone.size'; Label='Stone Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Stone patch size.' }
                    @{ Id='StoneRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.stone.richness'; Key='autoplace_controls.stone.richness'; Label='Stone Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Stone patch richness.' }
                    @{ Id='CopperFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.copper-ore.frequency'; Key='autoplace_controls.copper-ore.frequency'; Label='Copper Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Copper ore patch frequency.' }
                    @{ Id='CopperSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.copper-ore.size'; Key='autoplace_controls.copper-ore.size'; Label='Copper Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Copper ore patch size.' }
                    @{ Id='CopperRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.copper-ore.richness'; Key='autoplace_controls.copper-ore.richness'; Label='Copper Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Copper ore patch richness.' }
                    @{ Id='IronFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.iron-ore.frequency'; Key='autoplace_controls.iron-ore.frequency'; Label='Iron Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Iron ore patch frequency.' }
                    @{ Id='IronSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.iron-ore.size'; Key='autoplace_controls.iron-ore.size'; Label='Iron Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Iron ore patch size.' }
                    @{ Id='IronRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.iron-ore.richness'; Key='autoplace_controls.iron-ore.richness'; Label='Iron Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Iron ore patch richness.' }
                    @{ Id='UraniumFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.uranium-ore.frequency'; Key='autoplace_controls.uranium-ore.frequency'; Label='Uranium Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Uranium ore patch frequency.' }
                    @{ Id='UraniumSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.uranium-ore.size'; Key='autoplace_controls.uranium-ore.size'; Label='Uranium Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Uranium ore patch size.' }
                    @{ Id='UraniumRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.uranium-ore.richness'; Key='autoplace_controls.uranium-ore.richness'; Label='Uranium Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Uranium ore patch richness.' }
                    @{ Id='OilFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.crude-oil.frequency'; Key='autoplace_controls.crude-oil.frequency'; Label='Crude Oil Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Crude oil frequency.' }
                    @{ Id='OilSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.crude-oil.size'; Key='autoplace_controls.crude-oil.size'; Label='Crude Oil Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Crude oil size.' }
                    @{ Id='OilRichness'; Type='Number'; File=$mg; JsonPath='autoplace_controls.crude-oil.richness'; Key='autoplace_controls.crude-oil.richness'; Label='Crude Oil Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Crude oil richness.' }
                    @{ Id='WaterFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.water.frequency'; Key='autoplace_controls.water.frequency'; Label='Water Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Water frequency.' }
                    @{ Id='WaterSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.water.size'; Key='autoplace_controls.water.size'; Label='Water Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Water size.' }
                    @{ Id='TreesFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.trees.frequency'; Key='autoplace_controls.trees.frequency'; Label='Trees Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Tree frequency.' }
                    @{ Id='TreesSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.trees.size'; Key='autoplace_controls.trees.size'; Label='Trees Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Tree size.' }
                    @{ Id='EnemyBaseFrequency'; Type='Number'; File=$mg; JsonPath='autoplace_controls.enemy-base.frequency'; Key='autoplace_controls.enemy-base.frequency'; Label='Enemy Base Frequency'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Enemy base frequency.' }
                    @{ Id='EnemyBaseSize'; Type='Number'; File=$mg; JsonPath='autoplace_controls.enemy-base.size'; Key='autoplace_controls.enemy-base.size'; Label='Enemy Base Size'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='Enemy base size.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Cliffs / Terrain'
                Description = 'Cliff and terrain expression settings from map-gen-settings.json.'
                Fields      = @(
                    @{ Id='CliffName'; Type='Text'; File=$mg; JsonPath='cliff_settings.name'; Key='cliff_settings.name'; Label='Cliff Prototype Name'; DefaultValue='cliff'; ValueKind='String'; Hint='Name of the cliff prototype.' }
                    @{ Id='CliffElevation0'; Type='Number'; File=$mg; JsonPath='cliff_settings.cliff_elevation_0'; Key='cliff_settings.cliff_elevation_0'; Label='Cliff Elevation 0'; DefaultValue=10; Min=-2147483648; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Elevation of the first row of cliffs.' }
                    @{ Id='CliffElevationInterval'; Type='Number'; File=$mg; JsonPath='cliff_settings.cliff_elevation_interval'; Key='cliff_settings.cliff_elevation_interval'; Label='Cliff Elevation Interval'; DefaultValue=40; Min=-2147483648; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Elevation difference between cliff rows.' }
                    @{ Id='CliffRichness'; Type='Number'; File=$mg; JsonPath='cliff_settings.richness'; Key='cliff_settings.richness'; Label='Cliff Continuity / Richness'; DefaultValue=1; Min=0; Max=1000; Decimals=3; ValueKind='Number'; Hint='0 means no cliffs, higher values make cliff rows more solid.' }
                    @{ Id='MoistureFrequency'; Type='Text'; File=$mg; JsonPath='property_expression_names.control:moisture:frequency'; Key='property_expression_names.control:moisture:frequency'; Label='Moisture Frequency Expression'; DefaultValue='1'; ValueKind='String'; Hint='Inverse of moisture scale in the map generator.' }
                    @{ Id='MoistureBias'; Type='Text'; File=$mg; JsonPath='property_expression_names.control:moisture:bias'; Key='property_expression_names.control:moisture:bias'; Label='Moisture Bias Expression'; DefaultValue='0'; ValueKind='String'; Hint='Moisture bias expression.' }
                    @{ Id='AuxFrequency'; Type='Text'; File=$mg; JsonPath='property_expression_names.control:aux:frequency'; Key='property_expression_names.control:aux:frequency'; Label='Terrain Type Frequency Expression'; DefaultValue='1'; ValueKind='String'; Hint='Inverse of terrain type scale.' }
                    @{ Id='AuxBias'; Type='Text'; File=$mg; JsonPath='property_expression_names.control:aux:bias'; Key='property_expression_names.control:aux:bias'; Label='Terrain Type Bias Expression'; DefaultValue='0'; ValueKind='String'; Hint='Terrain type bias expression.' }
                    @{ Id='ElevationExpression'; Type='Text'; File=$mg; JsonPath='property_expression_names.elevation'; Key='property_expression_names.elevation'; Label='Elevation Expression'; DefaultValue=''; ValueKind='String'; Hint='Leave blank for normal terrain, or use elevation_island for island maps.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Difficulty / Pollution'
                Description = 'Difficulty and pollution settings from map-settings.json.'
                Fields      = @(
                    @{ Id='TechPriceMultiplier'; Type='Number'; File=$ms; JsonPath='difficulty_settings.technology_price_multiplier'; Key='difficulty_settings.technology_price_multiplier'; Label='Technology Price Multiplier'; DefaultValue=1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Research cost multiplier.' }
                    @{ Id='SpoilTimeModifier'; Type='Number'; File=$ms; JsonPath='difficulty_settings.spoil_time_modifier'; Key='difficulty_settings.spoil_time_modifier'; Label='Spoil Time Modifier'; DefaultValue=1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Space Age spoil time modifier.' }
                    @{ Id='PollutionEnabled'; Type='Boolean'; File=$ms; JsonPath='pollution.enabled'; Key='pollution.enabled'; Label='Pollution Enabled'; DefaultValue=$true; ValueKind='Boolean'; Hint='Enable pollution simulation.' }
                    @{ Id='PollutionDiffusionRatio'; Type='Number'; File=$ms; JsonPath='pollution.diffusion_ratio'; Key='pollution.diffusion_ratio'; Label='Pollution Diffusion Ratio'; DefaultValue=0.02; Min=0; Max=1000000; Decimals=8; ValueKind='Number'; Hint='Amount diffused to neighboring chunks.' }
                    @{ Id='PollutionMinToDiffuse'; Type='Number'; File=$ms; JsonPath='pollution.min_to_diffuse'; Key='pollution.min_to_diffuse'; Label='Pollution Min To Diffuse'; DefaultValue=15; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum pollution before diffusion.' }
                    @{ Id='PollutionAgeing'; Type='Number'; File=$ms; JsonPath='pollution.ageing'; Key='pollution.ageing'; Label='Pollution Ageing'; DefaultValue=1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Pollution ageing factor.' }
                    @{ Id='PollutionExpectedMaxPerChunk'; Type='Number'; File=$ms; JsonPath='pollution.expected_max_per_chunk'; Key='pollution.expected_max_per_chunk'; Label='Expected Max Per Chunk'; DefaultValue=150; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Expected max pollution per chunk.' }
                    @{ Id='PollutionMinToShowPerChunk'; Type='Number'; File=$ms; JsonPath='pollution.min_to_show_per_chunk'; Key='pollution.min_to_show_per_chunk'; Label='Min To Show Per Chunk'; DefaultValue=50; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum pollution shown per chunk.' }
                    @{ Id='PollutionMinDamageTrees'; Type='Number'; File=$ms; JsonPath='pollution.min_pollution_to_damage_trees'; Key='pollution.min_pollution_to_damage_trees'; Label='Min Pollution To Damage Trees'; DefaultValue=60; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum pollution needed to damage trees.' }
                    @{ Id='PollutionMaxForestDamage'; Type='Number'; File=$ms; JsonPath='pollution.pollution_with_max_forest_damage'; Key='pollution.pollution_with_max_forest_damage'; Label='Pollution With Max Forest Damage'; DefaultValue=150; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Pollution amount for max forest damage.' }
                    @{ Id='PollutionPerTreeDamage'; Type='Number'; File=$ms; JsonPath='pollution.pollution_per_tree_damage'; Key='pollution.pollution_per_tree_damage'; Label='Pollution Per Tree Damage'; DefaultValue=50; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Pollution consumed per tree damage.' }
                    @{ Id='PollutionRestoredPerTreeDamage'; Type='Number'; File=$ms; JsonPath='pollution.pollution_restored_per_tree_damage'; Key='pollution.pollution_restored_per_tree_damage'; Label='Pollution Restored Per Tree Damage'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Pollution restored per tree damage.' }
                    @{ Id='PollutionMaxToRestoreTrees'; Type='Number'; File=$ms; JsonPath='pollution.max_pollution_to_restore_trees'; Key='pollution.max_pollution_to_restore_trees'; Label='Max Pollution To Restore Trees'; DefaultValue=20; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum pollution where trees can restore.' }
                    @{ Id='EnemyAttackPollutionConsumptionModifier'; Type='Number'; File=$ms; JsonPath='pollution.enemy_attack_pollution_consumption_modifier'; Key='pollution.enemy_attack_pollution_consumption_modifier'; Label='Enemy Attack Pollution Consumption Modifier'; DefaultValue=1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Enemy attack pollution consumption multiplier.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Enemies'
                Description = 'Enemy evolution and expansion settings from map-settings.json.'
                Fields      = @(
                    @{ Id='EnemyEvolutionEnabled'; Type='Boolean'; File=$ms; JsonPath='enemy_evolution.enabled'; Key='enemy_evolution.enabled'; Label='Evolution Enabled'; DefaultValue=$true; ValueKind='Boolean'; Hint='Enable enemy evolution.' }
                    @{ Id='EnemyEvolutionTimeFactor'; Type='Number'; File=$ms; JsonPath='enemy_evolution.time_factor'; Key='enemy_evolution.time_factor'; Label='Evolution Time Factor'; DefaultValue=0.000004; Min=0; Max=1000000; Decimals=10; ValueKind='Number'; Hint='Evolution added over time.' }
                    @{ Id='EnemyEvolutionDestroyFactor'; Type='Number'; File=$ms; JsonPath='enemy_evolution.destroy_factor'; Key='enemy_evolution.destroy_factor'; Label='Evolution Destroy Factor'; DefaultValue=0.002; Min=0; Max=1000000; Decimals=10; ValueKind='Number'; Hint='Evolution from destroying spawners.' }
                    @{ Id='EnemyEvolutionPollutionFactor'; Type='Number'; File=$ms; JsonPath='enemy_evolution.pollution_factor'; Key='enemy_evolution.pollution_factor'; Label='Evolution Pollution Factor'; DefaultValue=0.0000009; Min=0; Max=1000000; Decimals=10; ValueKind='Number'; Hint='Evolution from pollution.' }
                    @{ Id='EnemyExpansionEnabled'; Type='Boolean'; File=$ms; JsonPath='enemy_expansion.enabled'; Key='enemy_expansion.enabled'; Label='Expansion Enabled'; DefaultValue=$true; ValueKind='Boolean'; Hint='Enable enemy expansion.' }
                    @{ Id='MaxExpansionDistance'; Type='Number'; File=$ms; JsonPath='enemy_expansion.max_expansion_distance'; Key='enemy_expansion.max_expansion_distance'; Label='Max Expansion Distance'; DefaultValue=7; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum expansion distance.' }
                    @{ Id='FriendlyBaseInfluenceRadius'; Type='Number'; File=$ms; JsonPath='enemy_expansion.friendly_base_influence_radius'; Key='enemy_expansion.friendly_base_influence_radius'; Label='Friendly Base Influence Radius'; DefaultValue=2; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Friendly base influence radius.' }
                    @{ Id='EnemyBuildingInfluenceRadius'; Type='Number'; File=$ms; JsonPath='enemy_expansion.enemy_building_influence_radius'; Key='enemy_expansion.enemy_building_influence_radius'; Label='Enemy Building Influence Radius'; DefaultValue=2; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Enemy building influence radius.' }
                    @{ Id='ExpansionBuildingCoefficient'; Type='Number'; File=$ms; JsonPath='enemy_expansion.building_coefficient'; Key='enemy_expansion.building_coefficient'; Label='Building Coefficient'; DefaultValue=0.1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Expansion building coefficient.' }
                    @{ Id='ExpansionOtherBaseCoefficient'; Type='Number'; File=$ms; JsonPath='enemy_expansion.other_base_coefficient'; Key='enemy_expansion.other_base_coefficient'; Label='Other Base Coefficient'; DefaultValue=2.0; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Other base coefficient.' }
                    @{ Id='ExpansionNeighbouringChunkCoefficient'; Type='Number'; File=$ms; JsonPath='enemy_expansion.neighbouring_chunk_coefficient'; Key='enemy_expansion.neighbouring_chunk_coefficient'; Label='Neighbouring Chunk Coefficient'; DefaultValue=0.5; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Neighbouring chunk coefficient.' }
                    @{ Id='ExpansionNeighbouringBaseChunkCoefficient'; Type='Number'; File=$ms; JsonPath='enemy_expansion.neighbouring_base_chunk_coefficient'; Key='enemy_expansion.neighbouring_base_chunk_coefficient'; Label='Neighbouring Base Chunk Coefficient'; DefaultValue=0.4; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Neighbouring base chunk coefficient.' }
                    @{ Id='ExpansionMaxCollidingTilesCoefficient'; Type='Number'; File=$ms; JsonPath='enemy_expansion.max_colliding_tiles_coefficient'; Key='enemy_expansion.max_colliding_tiles_coefficient'; Label='Max Colliding Tiles Coefficient'; DefaultValue=0.9; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Max colliding tiles coefficient.' }
                    @{ Id='SettlerGroupMinSize'; Type='Number'; File=$ms; JsonPath='enemy_expansion.settler_group_min_size'; Key='enemy_expansion.settler_group_min_size'; Label='Settler Group Min Size'; DefaultValue=5; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum settler group size.' }
                    @{ Id='SettlerGroupMaxSize'; Type='Number'; File=$ms; JsonPath='enemy_expansion.settler_group_max_size'; Key='enemy_expansion.settler_group_max_size'; Label='Settler Group Max Size'; DefaultValue=20; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum settler group size.' }
                    @{ Id='MinExpansionCooldown'; Type='Number'; File=$ms; JsonPath='enemy_expansion.min_expansion_cooldown'; Key='enemy_expansion.min_expansion_cooldown'; Label='Min Expansion Cooldown'; DefaultValue=14400; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum expansion cooldown in ticks.' }
                    @{ Id='MaxExpansionCooldown'; Type='Number'; File=$ms; JsonPath='enemy_expansion.max_expansion_cooldown'; Key='enemy_expansion.max_expansion_cooldown'; Label='Max Expansion Cooldown'; DefaultValue=216000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum expansion cooldown in ticks.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Unit Groups'
                Description = 'Enemy unit group behavior settings from map-settings.json.'
                Fields      = @(
                    @{ Id='MinGroupGatheringTime'; Type='Number'; File=$ms; JsonPath='unit_group.min_group_gathering_time'; Key='unit_group.min_group_gathering_time'; Label='Min Group Gathering Time'; DefaultValue=3600; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum group gathering time in ticks.' }
                    @{ Id='MaxGroupGatheringTime'; Type='Number'; File=$ms; JsonPath='unit_group.max_group_gathering_time'; Key='unit_group.max_group_gathering_time'; Label='Max Group Gathering Time'; DefaultValue=36000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum group gathering time in ticks.' }
                    @{ Id='MaxWaitTimeForLateMembers'; Type='Number'; File=$ms; JsonPath='unit_group.max_wait_time_for_late_members'; Key='unit_group.max_wait_time_for_late_members'; Label='Max Wait Time For Late Members'; DefaultValue=7200; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max wait time for late group members.' }
                    @{ Id='MaxGroupRadius'; Type='Number'; File=$ms; JsonPath='unit_group.max_group_radius'; Key='unit_group.max_group_radius'; Label='Max Group Radius'; DefaultValue=30.0; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Maximum group radius.' }
                    @{ Id='MinGroupRadius'; Type='Number'; File=$ms; JsonPath='unit_group.min_group_radius'; Key='unit_group.min_group_radius'; Label='Min Group Radius'; DefaultValue=5.0; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Minimum group radius.' }
                    @{ Id='MaxMemberSpeedupBehind'; Type='Number'; File=$ms; JsonPath='unit_group.max_member_speedup_when_behind'; Key='unit_group.max_member_speedup_when_behind'; Label='Max Member Speedup When Behind'; DefaultValue=1.4; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Speedup for units behind group.' }
                    @{ Id='MaxMemberSlowdownAhead'; Type='Number'; File=$ms; JsonPath='unit_group.max_member_slowdown_when_ahead'; Key='unit_group.max_member_slowdown_when_ahead'; Label='Max Member Slowdown When Ahead'; DefaultValue=0.6; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Slowdown for units ahead of group.' }
                    @{ Id='MaxGroupSlowdownFactor'; Type='Number'; File=$ms; JsonPath='unit_group.max_group_slowdown_factor'; Key='unit_group.max_group_slowdown_factor'; Label='Max Group Slowdown Factor'; DefaultValue=0.3; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Maximum group slowdown factor.' }
                    @{ Id='MaxGroupMemberFallbackFactor'; Type='Number'; File=$ms; JsonPath='unit_group.max_group_member_fallback_factor'; Key='unit_group.max_group_member_fallback_factor'; Label='Max Group Member Fallback Factor'; DefaultValue=3; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max group member fallback factor.' }
                    @{ Id='MemberDisownDistance'; Type='Number'; File=$ms; JsonPath='unit_group.member_disown_distance'; Key='unit_group.member_disown_distance'; Label='Member Disown Distance'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Distance where members may be disowned.' }
                    @{ Id='TickToleranceWhenMemberArrives'; Type='Number'; File=$ms; JsonPath='unit_group.tick_tolerance_when_member_arrives'; Key='unit_group.tick_tolerance_when_member_arrives'; Label='Tick Tolerance When Member Arrives'; DefaultValue=60; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Arrival tick tolerance.' }
                    @{ Id='MaxGatheringUnitGroups'; Type='Number'; File=$ms; JsonPath='unit_group.max_gathering_unit_groups'; Key='unit_group.max_gathering_unit_groups'; Label='Max Gathering Unit Groups'; DefaultValue=30; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum gathering unit groups.' }
                    @{ Id='MaxUnitGroupSize'; Type='Number'; File=$ms; JsonPath='unit_group.max_unit_group_size'; Key='unit_group.max_unit_group_size'; Label='Max Unit Group Size'; DefaultValue=200; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum unit group size.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Steering'
                Description = 'Enemy steering defaults and moving steering from map-settings.json.'
                Fields      = @(
                    @{ Id='SteeringDefaultRadius'; Type='Number'; File=$ms; JsonPath='steering.default.radius'; Key='steering.default.radius'; Label='Default Steering Radius'; DefaultValue=1.2; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Default steering radius.' }
                    @{ Id='SteeringDefaultSeparationForce'; Type='Number'; File=$ms; JsonPath='steering.default.separation_force'; Key='steering.default.separation_force'; Label='Default Separation Force'; DefaultValue=0.005; Min=0; Max=1000000; Decimals=8; ValueKind='Number'; Hint='Default separation force.' }
                    @{ Id='SteeringDefaultSeparationFactor'; Type='Number'; File=$ms; JsonPath='steering.default.separation_factor'; Key='steering.default.separation_factor'; Label='Default Separation Factor'; DefaultValue=1.2; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Default separation factor.' }
                    @{ Id='SteeringDefaultForceFuzzyGoto'; Type='Boolean'; File=$ms; JsonPath='steering.default.force_unit_fuzzy_goto_behavior'; Key='steering.default.force_unit_fuzzy_goto_behavior'; Label='Default Force Fuzzy Goto'; DefaultValue=$false; ValueKind='Boolean'; Hint='Force fuzzy goto behavior for default steering.' }
                    @{ Id='SteeringMovingRadius'; Type='Number'; File=$ms; JsonPath='steering.moving.radius'; Key='steering.moving.radius'; Label='Moving Steering Radius'; DefaultValue=3; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Moving steering radius.' }
                    @{ Id='SteeringMovingSeparationForce'; Type='Number'; File=$ms; JsonPath='steering.moving.separation_force'; Key='steering.moving.separation_force'; Label='Moving Separation Force'; DefaultValue=0.01; Min=0; Max=1000000; Decimals=8; ValueKind='Number'; Hint='Moving separation force.' }
                    @{ Id='SteeringMovingSeparationFactor'; Type='Number'; File=$ms; JsonPath='steering.moving.separation_factor'; Key='steering.moving.separation_factor'; Label='Moving Separation Factor'; DefaultValue=3; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Moving separation factor.' }
                    @{ Id='SteeringMovingForceFuzzyGoto'; Type='Boolean'; File=$ms; JsonPath='steering.moving.force_unit_fuzzy_goto_behavior'; Key='steering.moving.force_unit_fuzzy_goto_behavior'; Label='Moving Force Fuzzy Goto'; DefaultValue=$false; ValueKind='Boolean'; Hint='Force fuzzy goto behavior for moving steering.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Path Finder'
                Description = 'Advanced path finder and cache settings from map-settings.json.'
                Fields      = @(
                    @{ Id='PathFwd2BwdRatio'; Type='Number'; File=$ms; JsonPath='path_finder.fwd2bwd_ratio'; Key='path_finder.fwd2bwd_ratio'; Label='Fwd/Bwd Ratio'; DefaultValue=5; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Forward-to-backward path finder ratio.' }
                    @{ Id='PathGoalPressureRatio'; Type='Number'; File=$ms; JsonPath='path_finder.goal_pressure_ratio'; Key='path_finder.goal_pressure_ratio'; Label='Goal Pressure Ratio'; DefaultValue=2; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Goal pressure ratio.' }
                    @{ Id='PathMaxStepsWorkedPerTick'; Type='Number'; File=$ms; JsonPath='path_finder.max_steps_worked_per_tick'; Key='path_finder.max_steps_worked_per_tick'; Label='Max Steps Worked Per Tick'; DefaultValue=1000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max path finder steps worked per tick.' }
                    @{ Id='PathMaxWorkDonePerTick'; Type='Number'; File=$ms; JsonPath='path_finder.max_work_done_per_tick'; Key='path_finder.max_work_done_per_tick'; Label='Max Work Done Per Tick'; DefaultValue=8000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max path finder work done per tick.' }
                    @{ Id='PathUseCache'; Type='Boolean'; File=$ms; JsonPath='path_finder.use_path_cache'; Key='path_finder.use_path_cache'; Label='Use Path Cache'; DefaultValue=$true; ValueKind='Boolean'; Hint='Enable path cache.' }
                    @{ Id='PathShortCacheSize'; Type='Number'; File=$ms; JsonPath='path_finder.short_cache_size'; Key='path_finder.short_cache_size'; Label='Short Cache Size'; DefaultValue=5; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Short path cache size.' }
                    @{ Id='PathLongCacheSize'; Type='Number'; File=$ms; JsonPath='path_finder.long_cache_size'; Key='path_finder.long_cache_size'; Label='Long Cache Size'; DefaultValue=25; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Long path cache size.' }
                    @{ Id='PathShortCacheMinDistance'; Type='Number'; File=$ms; JsonPath='path_finder.short_cache_min_cacheable_distance'; Key='path_finder.short_cache_min_cacheable_distance'; Label='Short Cache Min Distance'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum distance for short cache.' }
                    @{ Id='PathShortCacheMinSteps'; Type='Number'; File=$ms; JsonPath='path_finder.short_cache_min_algo_steps_to_cache'; Key='path_finder.short_cache_min_algo_steps_to_cache'; Label='Short Cache Min Algo Steps'; DefaultValue=50; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum algorithm steps for short cache.' }
                    @{ Id='PathLongCacheMinDistance'; Type='Number'; File=$ms; JsonPath='path_finder.long_cache_min_cacheable_distance'; Key='path_finder.long_cache_min_cacheable_distance'; Label='Long Cache Min Distance'; DefaultValue=30; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum distance for long cache.' }
                    @{ Id='PathCacheMaxConnectMultiplier'; Type='Number'; File=$ms; JsonPath='path_finder.cache_max_connect_to_cache_steps_multiplier'; Key='path_finder.cache_max_connect_to_cache_steps_multiplier'; Label='Cache Max Connect Steps Multiplier'; DefaultValue=100; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Cache connect step multiplier.' }
                    @{ Id='PathCacheAcceptStartRatio'; Type='Number'; File=$ms; JsonPath='path_finder.cache_accept_path_start_distance_ratio'; Key='path_finder.cache_accept_path_start_distance_ratio'; Label='Cache Accept Start Distance Ratio'; DefaultValue=0.2; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Cache accept path start distance ratio.' }
                    @{ Id='PathCacheAcceptEndRatio'; Type='Number'; File=$ms; JsonPath='path_finder.cache_accept_path_end_distance_ratio'; Key='path_finder.cache_accept_path_end_distance_ratio'; Label='Cache Accept End Distance Ratio'; DefaultValue=0.15; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Cache accept path end distance ratio.' }
                    @{ Id='PathNegativeCacheAcceptStartRatio'; Type='Number'; File=$ms; JsonPath='path_finder.negative_cache_accept_path_start_distance_ratio'; Key='path_finder.negative_cache_accept_path_start_distance_ratio'; Label='Negative Cache Accept Start Ratio'; DefaultValue=0.3; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Negative cache accept path start distance ratio.' }
                    @{ Id='PathNegativeCacheAcceptEndRatio'; Type='Number'; File=$ms; JsonPath='path_finder.negative_cache_accept_path_end_distance_ratio'; Key='path_finder.negative_cache_accept_path_end_distance_ratio'; Label='Negative Cache Accept End Ratio'; DefaultValue=0.3; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Negative cache accept path end distance ratio.' }
                    @{ Id='PathCacheStartDistanceRatingMultiplier'; Type='Number'; File=$ms; JsonPath='path_finder.cache_path_start_distance_rating_multiplier'; Key='path_finder.cache_path_start_distance_rating_multiplier'; Label='Cache Path Start Rating Multiplier'; DefaultValue=10; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Cache path start distance rating multiplier.' }
                    @{ Id='PathCacheEndDistanceRatingMultiplier'; Type='Number'; File=$ms; JsonPath='path_finder.cache_path_end_distance_rating_multiplier'; Key='path_finder.cache_path_end_distance_rating_multiplier'; Label='Cache Path End Rating Multiplier'; DefaultValue=20; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Cache path end distance rating multiplier.' }
                    @{ Id='PathStaleSameDestinationPenalty'; Type='Number'; File=$ms; JsonPath='path_finder.stale_enemy_with_same_destination_collision_penalty'; Key='path_finder.stale_enemy_with_same_destination_collision_penalty'; Label='Stale Same Destination Collision Penalty'; DefaultValue=30; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Penalty for stale enemies with same destination.' }
                    @{ Id='PathIgnoreMovingEnemyDistance'; Type='Number'; File=$ms; JsonPath='path_finder.ignore_moving_enemy_collision_distance'; Key='path_finder.ignore_moving_enemy_collision_distance'; Label='Ignore Moving Enemy Collision Distance'; DefaultValue=5; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Distance to ignore moving enemy collision.' }
                    @{ Id='PathDifferentDestinationPenalty'; Type='Number'; File=$ms; JsonPath='path_finder.enemy_with_different_destination_collision_penalty'; Key='path_finder.enemy_with_different_destination_collision_penalty'; Label='Different Destination Collision Penalty'; DefaultValue=30; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Penalty for enemies with different destination.' }
                    @{ Id='PathGeneralCollisionPenalty'; Type='Number'; File=$ms; JsonPath='path_finder.general_entity_collision_penalty'; Key='path_finder.general_entity_collision_penalty'; Label='General Entity Collision Penalty'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='General entity collision penalty.' }
                    @{ Id='PathGeneralSubsequentCollisionPenalty'; Type='Number'; File=$ms; JsonPath='path_finder.general_entity_subsequent_collision_penalty'; Key='path_finder.general_entity_subsequent_collision_penalty'; Label='General Subsequent Collision Penalty'; DefaultValue=3; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Subsequent general collision penalty.' }
                    @{ Id='PathExtendedCollisionPenalty'; Type='Number'; File=$ms; JsonPath='path_finder.extended_collision_penalty'; Key='path_finder.extended_collision_penalty'; Label='Extended Collision Penalty'; DefaultValue=3; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Extended collision penalty.' }
                    @{ Id='PathMaxClientsAnyRequest'; Type='Number'; File=$ms; JsonPath='path_finder.max_clients_to_accept_any_new_request'; Key='path_finder.max_clients_to_accept_any_new_request'; Label='Max Clients Any New Request'; DefaultValue=10; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max clients to accept any new request.' }
                    @{ Id='PathMaxClientsShortRequest'; Type='Number'; File=$ms; JsonPath='path_finder.max_clients_to_accept_short_new_request'; Key='path_finder.max_clients_to_accept_short_new_request'; Label='Max Clients Short New Request'; DefaultValue=100; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max clients to accept short new request.' }
                    @{ Id='PathDirectDistanceShortRequest'; Type='Number'; File=$ms; JsonPath='path_finder.direct_distance_to_consider_short_request'; Key='path_finder.direct_distance_to_consider_short_request'; Label='Direct Distance For Short Request'; DefaultValue=100; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Direct distance to consider short request.' }
                    @{ Id='PathShortRequestMaxSteps'; Type='Number'; File=$ms; JsonPath='path_finder.short_request_max_steps'; Key='path_finder.short_request_max_steps'; Label='Short Request Max Steps'; DefaultValue=1000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Short request max steps.' }
                    @{ Id='PathShortRequestRatio'; Type='Number'; File=$ms; JsonPath='path_finder.short_request_ratio'; Key='path_finder.short_request_ratio'; Label='Short Request Ratio'; DefaultValue=0.5; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Short request ratio.' }
                    @{ Id='PathMinStepsTermination'; Type='Number'; File=$ms; JsonPath='path_finder.min_steps_to_check_path_find_termination'; Key='path_finder.min_steps_to_check_path_find_termination'; Label='Min Steps To Check Termination'; DefaultValue=2000; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Minimum steps to check path find termination.' }
                    @{ Id='PathStartGoalCostTermination'; Type='Number'; File=$ms; JsonPath='path_finder.start_to_goal_cost_multiplier_to_terminate_path_find'; Key='path_finder.start_to_goal_cost_multiplier_to_terminate_path_find'; Label='Start/Goal Cost Termination Multiplier'; DefaultValue=2000.0; Min=0; Max=1000000000; Decimals=6; ValueKind='Number'; Hint='Start to goal cost multiplier to terminate path find.' }
                    @{ Id='PathOverloadLevels'; Type='MultilineText'; File=$ms; JsonPath='path_finder.overload_levels'; Key='path_finder.overload_levels'; Label='Overload Levels JSON'; DefaultValue='[0,100,500]'; ValueKind='RawJson'; Hint='JSON array of overload levels.' }
                    @{ Id='PathOverloadMultipliers'; Type='MultilineText'; File=$ms; JsonPath='path_finder.overload_multipliers'; Key='path_finder.overload_multipliers'; Label='Overload Multipliers JSON'; DefaultValue='[2,3,4]'; ValueKind='RawJson'; Hint='JSON array of overload multipliers.' }
                    @{ Id='PathNegativeCacheDelayInterval'; Type='Number'; File=$ms; JsonPath='path_finder.negative_path_cache_delay_interval'; Key='path_finder.negative_path_cache_delay_interval'; Label='Negative Path Cache Delay Interval'; DefaultValue=20; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Negative path cache delay interval.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Asteroids'
                Description = 'Space Age asteroid and remaining map settings from map-settings.json.'
                Fields      = @(
                    @{ Id='AsteroidSpawningRate'; Type='Number'; File=$ms; JsonPath='asteroids.spawning_rate'; Key='asteroids.spawning_rate'; Label='Asteroid Spawning Rate'; DefaultValue=1; Min=0; Max=1000000; Decimals=6; ValueKind='Number'; Hint='Asteroid spawning rate.' }
                    @{ Id='AsteroidMaxRayPortals'; Type='Number'; File=$ms; JsonPath='asteroids.max_ray_portals_expanded_per_tick'; Key='asteroids.max_ray_portals_expanded_per_tick'; Label='Max Ray Portals Expanded Per Tick'; DefaultValue=100; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Max ray portals expanded per tick.' }
                    @{ Id='MaxFailedBehaviorCount'; Type='Number'; File=$ms; JsonPath='max_failed_behavior_count'; Key='max_failed_behavior_count'; Label='Max Failed Behavior Count'; DefaultValue=3; Min=0; Max=2147483647; Decimals=0; ValueKind='Integer'; Hint='Maximum failed behavior count.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Mods'
                Description = 'Local Factorio mod ZIP handling. Import ZIP files into the profile mods folder and enable or disable local mods in mod-list.json.'
                Fields      = @(
                    @{ Id='LocalMods'; Type='FactorioLocalModList'; Label='Local Mod ZIPs'; DefaultValue=''; Hint='Checked local mods are enabled in mods\mod-list.json. Built-in DLC mods are controlled by the Space Age checkbox.' }
                    @{ Id='ImportLocalModZip'; Type='ActionButton'; Label='Import Mod ZIPs'; ButtonText='Import Mod ZIPs'; Action=$actions.ImportModZip; Hint='Copy one or more Factorio mod ZIPs into the profile mods folder and enable them.' }
                    @{ Id='SyncLocalMods'; Type='ActionButton'; Label='Sync Mod List From Folder'; ButtonText='Sync Mods Folder'; Action=$actions.SyncLocalMods; Hint='Adds local ZIPs from the mods folder to mod-list.json without touching built-in DLC toggles.' }
                    @{ Id='RemoveSelectedLocalMod'; Type='FactorioRemoveSelectedModButton'; Label='Remove Selected Mod'; ButtonText='Remove Selected Mod'; Hint='Deletes the selected local mod ZIP from this profile and removes it from mod-list.json.' }
                    @{ Id='OpenModsFolder'; Type='ActionButton'; Label='Open Mods Folder'; ButtonText='Open Mods Folder'; Action=$actions.OpenModsFolder; Hint='Open the profile mods folder.' }
                    @{ Id='OpenModList'; Type='ActionButton'; Label='Open mod-list.json'; ButtonText='Open Mod List'; Action=$actions.OpenModList; Hint='Open the raw Factorio mod-list.json file.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Lists / Files'
                Description = 'User lists and direct file access for Factorio profile files.'
                Fields      = @(
                    @{ Id='AdminUsers'; Type='StringList'; File='server-adminlist.json'; Path='server-adminlist.json'; Label='Admin Player Names'; DefaultValue=''; Hint='Enter Factorio player names, one per line. Factorio uses player/account names here, not Steam64 IDs.' }
                    @{ Id='WhitelistedUsers'; Type='StringList'; File='server-whitelist.json'; Path='server-whitelist.json'; Label='Whitelist Player Names'; DefaultValue=''; Hint='Enter Factorio player names, one per line. Factorio uses player/account names here, not Steam64 IDs.' }
                    @{ Id='BannedUsers'; Type='StringList'; File='server-banlist.json'; Path='server-banlist.json'; Label='Banned Player Names'; DefaultValue=''; Hint='Enter Factorio player names, one per line. Factorio uses player/account names here, not Steam64 IDs.' }
                    @{ Id='OpenServerSettings'; Type='ActionButton'; Label='Open server-settings.json'; ButtonText='Open Server Settings'; Action=$actions.OpenServerSettings; Hint='Open the raw Factorio settings file.' }
                    @{ Id='OpenMapGenSettings'; Type='ActionButton'; Label='Open map-gen-settings.json'; ButtonText='Open Map Gen Settings'; Action=$actions.OpenMapGenSettings; Hint='Open the raw map generation settings file.' }
                    @{ Id='OpenMapSettings'; Type='ActionButton'; Label='Open map-settings.json'; ButtonText='Open Map Settings'; Action=$actions.OpenMapSettings; Hint='Open the raw map behavior settings file.' }
                    @{ Id='OpenConfigFolder'; Type='ActionButton'; Label='Open Config Folder'; ButtonText='Open Config'; Action=$actions.OpenConfigFolder; Hint='Open the profile config folder.' }
                    @{ Id='OpenSavesFolder'; Type='ActionButton'; Label='Open Saves Folder'; ButtonText='Open Saves'; Action=$actions.OpenSavesFolder; Hint='Open the profile saves folder.' }
                    @{ Id='OpenLogsFolder'; Type='ActionButton'; Label='Open Logs Folder'; ButtonText='Open Logs'; Action=$actions.OpenLogsFolder; Hint='Open the profile logs folder.' }
                )
            }
        )
    }

    $discordFields = $null
    try { $discordFields = New-UGSMDiscordSettingsFields -GameId 'Factorio' } catch { $discordFields = $null }

    if ($discordFields) {
        $schema.Tabs += [pscustomobject]@{
            Title       = 'Discord'
            Description = 'Per-instance Discord notifications.'
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

    return $schema
}


