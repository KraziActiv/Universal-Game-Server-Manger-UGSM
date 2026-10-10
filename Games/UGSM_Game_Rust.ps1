# UGSM Game Rust
# Rust dedicated server module.
#
# This file is intentionally based on UGSM_Game_Template.ps1 so Rust stays on
# the same schema-driven editor/runtime-handler pattern as the completed games.
# Rust-specific code is limited to metadata, install detection, runtime launch,
# server.cfg generation, and future uMod/Oxide handling.
#
# Design rules
# ------------
# - Visible in the game catalog
# - Runtime-only working paths
# - No profile sync / no copy-back workflow
# - Generic reusable helpers first
# - Schema includes sample tabs and subtabs for multi-file games
# - Game-specific logic stays in the game module and must be labeled clearly
# - Default lifecycle for Steam games: Install, Update, Verify, Remove binaries only
# - Remove the sample reference tab once a real game module is built

function Test-UGSMGameRustVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameRustLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameRustLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_RUST)) { return $true }
    return $false
}

function ConvertTo-UGSMGameRustSafeLogText {
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
        # the rust itself does not add portability-scan false positives.
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

function Write-UGSMGameRustLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGameRustVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameRustSafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameRustSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:Rust' -Message $safeMessage
    }
}

function Write-UGSMGameRustPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older rust notes. New modules should use Write-UGSMGameRustLog.
    Write-UGSMGameRustLog -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGameRustInstanceDiscordShape {
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
            ShowInDashboard = $true
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
            Add-Member -InputObject $Instance.Discord -MemberType NoteProperty -Name 'ShowInDashboard' -Value $true -Force
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
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'DiscordVisible' -Value $true -Force
    }
    if (-not $Instance.PSObject.Properties['HasPrivateDiscordWebhook']) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'HasPrivateDiscordWebhook' -Value $false -Force
    }

    return $Instance
}


function Get-UGSMGameRustSupportedFeatures {
    [CmdletBinding()]
    param()

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
        Workshop      = $false
        ModTabMode    = 'FrameworkPlugin'

        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $false

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
            SteamWorkshop    = $false
            LoadOrder        = $false
            ArchiveImport    = $false
            FolderImport     = $false
            FrameworkInstall = $true
            PluginManager    = $true
            KeyCopy          = $false
            ServerSideCopy   = $false
            RuntimeSync      = $false
            BuildIndexCache  = $false
            MapList          = $false
            ConfigMerge      = $false
            UrlDownload      = $true
            OpenManifest     = $true
            RefreshSummary   = $true
        }
    }
}



function Get-UGSMGameRustModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameRustSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'Rust' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
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
            GameId = 'Rust'
        }
    }


    # Rust Workshop App ID placeholder. Copied games must replace 000000 with
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


    # Rust uses uMod/Oxide framework plugins, not Steam Workshop mods.
    if ($mods.PSObject.Properties['ModTabMode']) { $mods.ModTabMode = 'FrameworkPlugin' }
    else { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'ModTabMode' -Value 'FrameworkPlugin' -Force }

    if (-not ($mods.PSObject.Properties['Capabilities']) -or -not $mods.Capabilities) {
        Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Capabilities' -Value ([pscustomobject]@{}) -Force
    }
    foreach ($pair in @{
        SteamWorkshop    = $false
        ArchiveImport    = $false
        FolderImport     = $false
        FrameworkInstall = $true
        PluginManager    = $true
        LoadOrder        = $false
        OpenManifest     = $false
        RefreshSummary   = $true
    }.GetEnumerator()) {
        if ($mods.Capabilities.PSObject.Properties[$pair.Key]) { $mods.Capabilities.$($pair.Key) = $pair.Value }
        else { Add-Member -InputObject $mods.Capabilities -MemberType NoteProperty -Name $pair.Key -Value $pair.Value -Force }
    }

    $frameworkValue = [pscustomobject]@{
        Id = 'uModOxide'
        Label = 'uMod / Oxide'
        DownloadUrl = 'https://umod.org/games/rust/download'
        PluginFolderRelative = 'oxide\plugins'
        OfficialSourceOnly = $true
        RequiresConfirmation = $true
    }
    if ($mods.PSObject.Properties['Framework']) { $mods.Framework = $frameworkValue }
    else { Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Framework' -Value $frameworkValue -Force }

    if (-not ($mods.PSObject.Properties['Paths']) -or -not $mods.Paths) {
        Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Paths' -Value ([pscustomobject]@{}) -Force
    }
    if ($mods.Paths.PSObject.Properties['PluginFolderRelative']) { $mods.Paths.PluginFolderRelative = 'oxide\plugins' }
    else { Add-Member -InputObject $mods.Paths -MemberType NoteProperty -Name 'PluginFolderRelative' -Value 'oxide\plugins' -Force }

    if (-not ($mods.PSObject.Properties['Hooks']) -or -not $mods.Hooks) {
        Add-Member -InputObject $mods -MemberType NoteProperty -Name 'Hooks' -Value ([pscustomobject]@{}) -Force
    }
    foreach ($pair in @{
        FrameworkStatus      = 'Test-UGSMRustOxideFrameworkInstalled'
        FrameworkInstall     = 'Install-UGSMRustOxideFramework'
        FrameworkOpenPlugins = 'Open-UGSMRustOxidePluginsFolder'
        PluginAdd            = 'Add-UGSMRustOxidePlugin'
        PluginRemove         = 'Remove-UGSMRustOxidePlugin'
        AddPlugin            = 'Add-UGSMRustOxidePlugin'
        RemovePlugin         = 'Remove-UGSMRustOxidePlugin'
        OpenPlugins          = 'Open-UGSMRustOxidePluginsFolder'
    }.GetEnumerator()) {
        if ($mods.Hooks.PSObject.Properties[$pair.Key]) { $mods.Hooks.$($pair.Key) = $pair.Value }
        else { Add-Member -InputObject $mods.Hooks -MemberType NoteProperty -Name $pair.Key -Value $pair.Value -Force }
    }

    foreach ($pair in @{
        FrameworkStatus      = 'Test-UGSMRustOxideFrameworkInstalled'
        FrameworkInstall     = 'Install-UGSMRustOxideFramework'
        FrameworkOpenPlugins = 'Open-UGSMRustOxidePluginsFolder'
        PluginAdd            = 'Add-UGSMRustOxidePlugin'
        PluginRemove         = 'Remove-UGSMRustOxidePlugin'
        AddPlugin            = 'Add-UGSMRustOxidePlugin'
        RemovePlugin         = 'Remove-UGSMRustOxidePlugin'
        OpenPlugins          = 'Open-UGSMRustOxidePluginsFolder'
    }.GetEnumerator()) {
        if ($mods.PSObject.Properties[$pair.Key]) { $mods.$($pair.Key) = $pair.Value }
        else { Add-Member -InputObject $mods -MemberType NoteProperty -Name $pair.Key -Value $pair.Value -Force }
    }


    return $mods
}

function Get-UGSMGameRustMetadata {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameRustSupportedFeatures
    $modsDefinition = Get-UGSMGameRustModsDefinition

    return [pscustomobject]@{
        Id                       = 'Rust'
        Name                     = 'Rust'
        Category                 = 'Survival'
        Description              = 'Rust Dedicated Server integration.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 100
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
        SupportsWorkshop         = $false
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
        SteamAppId               = '258550'
        SteamStoreAppId          = '252490'
        ServerExecutable         = 'RustDedicated.exe'
        ServerExecutableRelative = 'RustDedicated.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'Config\WindowsServer'
        SaveRootRelative         = 'ServerData'
        LogRootRelative          = 'Logs'

        RequiredFiles            = @('RustDedicated.exe')
        InstallMarkers           = @('RustDedicated.exe')

        PortSchema               = @(
            @{ Name = 'GamePort';  Protocol = 'UDP'; PreferredStart = 28015 }
            @{ Name = 'RconPort';  Protocol = 'TCP'; PreferredStart = 28016 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 28017 }
        )

        GameTraits = [pscustomobject]@{
            UsesIniFiles          = $true
            UsesJsonFiles         = $true
            UsesXmlFiles          = $false
            UsesCfgFiles          = $true
            UsesTextFiles         = $true
            UsesPSSQLite          = $false
            UsesSqliteDatabase    = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $true
            UsesZipMods           = $false
            UsesFolderCopyMods    = $false
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $false
        }

        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'SteamCMD app id 258550 installs Rust Dedicated Server using anonymous login.',
                'UGSM uses shared RustDedicated.exe binaries and an isolated per-profile Rust identity/server data folder.',
                'uMod/Oxide support must show a confirmation warning before installing because it modifies server files and third-party plugins can affect stability/security/saves/gameplay.',
                'RCON password is masked in the UI and must never be logged.'
            )
        }
    }
}



function Get-UGSMGameRustInstallDefinition {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    if ([string]::IsNullOrWhiteSpace($InstallPath) -and $Instance -and $Instance.PSObject.Properties['InstallPath']) {
        $InstallPath = [string]$Instance.InstallPath
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $settings = $null
        if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
        }

        $roots = New-Object System.Collections.Generic.List[string]
        if ($settings) {
            foreach ($propName in @('SteamLibraryRoot','SteamRoot','SteamCmdRoot','InstallRoot','SteamInstallRoot')) {
                if ($settings.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propName)) {
                    [void]$roots.Add([string]$settings.$propName)
                }
            }
        }

        foreach ($root in @($roots.ToArray())) {
            foreach ($candidate in @(
                (Join-Path $root 'steamapps\common\Rust'),
                (Join-Path $root 'steamapps\common\rust_dedicated'),
                (Join-Path $root 'steamapps\common\Rust Dedicated Server'),
                (Join-Path $root 'steamapps\common\RustDedicated'),
                (Join-Path $root 'rust_dedicated'),
                (Join-Path $root 'Rust Dedicated Server')
            )) {
                if (Test-Path -LiteralPath (Join-Path $candidate 'RustDedicated.exe') -PathType Leaf) {
                    $InstallPath = $candidate
                    break
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { break }
        }

        if ([string]::IsNullOrWhiteSpace($InstallPath) -and $settings -and $settings.PSObject.Properties['SteamLibraryRoot']) {
            $InstallPath = Join-Path ([string]$settings.SteamLibraryRoot) 'steamapps\common\Rust'
        }
    }

    $serverExe = if ([string]::IsNullOrWhiteSpace($InstallPath)) { '' } else { Join-Path $InstallPath 'RustDedicated.exe' }
    $serverRoot = if ([string]::IsNullOrWhiteSpace($InstallPath)) { '' } else { Join-Path $InstallPath 'server' }

    return [pscustomobject]@{
        GameId               = 'Rust'
        InstallPath          = $InstallPath
        ServerRoot           = $serverRoot
        ServerExecutablePath = $serverExe
        RequiredFiles        = @('RustDedicated.exe')
        ConfigRootPath       = $serverRoot
        SaveRootPath         = $serverRoot
        LogRootPath          = Join-Path (Get-UGSMGameRustAppDataRoot) 'Logs\Rust'
    }
}



function Get-UGSMGameRustAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameRustProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'Rust' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameRustAppDataRoot) 'Profiles')
}

function Get-UGSMGameRustTemplateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameRustAppDataRoot) 'Rusts\Rust')
}

function Get-UGSMGameRustProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameRustProfileBaseRoot) 'Rust') $ProfileName)
}


function Get-UGSMGameRustRuntimeRoot {
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
            $profileRoot = Get-UGSMGameRustProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'Rust runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameRustPath {
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

function New-UGSMGameRustDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "Rust junction target was not found: $TargetPath"
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

        Remove-UGSMGameRustPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "Rust junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameRustFilesToRuntime {
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

    Copy-UGSMGameRustDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameRustRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InstallDefinition
    )

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    return [pscustomobject]@{
        RuntimeRoot           = [string]$paths.RuntimeRoot
        RuntimeInstallRoot    = [string]$InstallDefinition.InstallPath
        RuntimeGameRoot       = [string]$InstallDefinition.InstallPath
        RuntimeSavedRoot      = [string]$paths.ServerDataRoot
        RuntimeConfigRootPath = [string]$paths.ConfigRoot
        RuntimeSaveRootPath   = [string]$paths.ServerDataRoot
        RuntimeLogRootPath    = [string]$paths.LogRoot
        RuntimeServerExePath  = [string]$InstallDefinition.ServerExecutablePath
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = [string]$InstallDefinition.InstallPath
    }
}



function Resolve-UGSMGameRustDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance

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

function Ensure-UGSMGameRustRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InstallDefinition
    )

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    foreach ($dir in @($paths.ProfileRoot, $paths.ConfigRoot, $paths.ServerDataRoot, $paths.ServerCfgRoot, $paths.LogRoot, $paths.CentralLogRoot, [string]$InstallDefinition.ServerRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $identityLink = Join-Path ([string]$InstallDefinition.ServerRoot) ([string]$paths.Identity)
    if (Test-Path -LiteralPath $identityLink) {
        try {
            $item = Get-Item -LiteralPath $identityLink -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $paths }
            if ((Get-ChildItem -LiteralPath $identityLink -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) { return $paths }
            Remove-Item -LiteralPath $identityLink -Force -Recurse -ErrorAction SilentlyContinue
        } catch {}
    }

    if (-not (Test-Path -LiteralPath $identityLink)) {
        New-UGSMGameRustDirectoryJunction -LinkPath $identityLink -TargetPath ([string]$paths.ServerDataRoot) | Out-Null
    }

    return $paths
}



function Initialize-UGSMGameRustRuntimeData {
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
        Copy-UGSMGameRustFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameRustFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameRustDirectoryContent {
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

function Get-UGSMGameRustRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'RustDedicated.exe'" -ErrorAction Stop)
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


function Get-UGSMGameRustRunningServerProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Paths,
        [AllowNull()][string]$InstallPath
    )

    $identity = $null
    try {
        if ($Paths -and $Paths.PSObject.Properties['Identity']) { $identity = [string]$Paths.Identity }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($identity)) {
        try { $identity = [string](Get-UGSMGameRustProfilePaths -Instance $Instance).Identity } catch { $identity = $null }
    }

    $normalizedInstallPath = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$InstallPath)) {
        try { $normalizedInstallPath = [System.IO.Path]::GetFullPath([string]$InstallPath) } catch { $normalizedInstallPath = [string]$InstallPath }
    }

    $results = @()
    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "name = 'RustDedicated.exe' or name = 'cmd.exe' or name = 'powershell.exe' or name = 'powershell_ise.exe'" -ErrorAction SilentlyContinue)
        foreach ($proc in $processes) {
            $cmd = [string]$proc.CommandLine
            $exe = [string]$proc.ExecutablePath
            if ([string]::IsNullOrWhiteSpace($cmd) -and [string]::IsNullOrWhiteSpace($exe)) { continue }

            $isRustServer = ($cmd -match 'RustDedicated\.exe') -or ($exe -match 'RustDedicated\.exe')
            $isUgsmLauncher = ($cmd -match 'UGSM_Start_Rust')
            if (-not ($isRustServer -or $isUgsmLauncher)) { continue }

            if (-not [string]::IsNullOrWhiteSpace($identity)) {
                if ($cmd -notmatch [Regex]::Escape($identity)) { continue }
            }

            if (-not [string]::IsNullOrWhiteSpace($normalizedInstallPath)) {
                $pathMatch = $false
                foreach ($candidate in @($cmd, $exe)) {
                    if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
                    if ([string]$candidate -like ('*' + $normalizedInstallPath + '*')) { $pathMatch = $true; break }
                }
                if (-not $pathMatch -and -not $isUgsmLauncher) { continue }
            }

            $created = $null
            try { $created = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$proc.CreationDate) } catch { $created = $null }
            $results += [pscustomobject]@{
                Pid         = [int]$proc.ProcessId
                Name        = [string]$proc.Name
                Executable  = $exe
                StartedAt   = $created
                CommandLine = $cmd
            }
        }
    } catch {}

    return @($results | Sort-Object Pid -Unique)
}

function Start-UGSMGameRustBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "Rust server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'RustServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM RustServer.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'RustServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'RustServer' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameRustTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallPath,
        [switch]$ForceRefresh,
        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameRustInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameRustInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) { throw "Rust install is not valid at '$InstallPath'." }

    $templateRoot = Get-UGSMGameRustTemplateRoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    New-Item -ItemType Directory -Path $templateConfigRoot -Force | Out-Null

    $serverSettingsPath = Join-Path $templateConfigRoot 'ServerSettings.ini'
    if ($ForceRefresh -or -not (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf)) {
        $lines = @(
            '[General]',
            'ServerName=Rust Server',
            'ServerDescription=UGSM Rust server',
            'MaxPlayers=50',
            'Level=Procedural Map',
            'Seed=12345',
            'WorldSize=3500',
            'SaveInterval=300',
            'HeaderImage=',
            'WebsiteUrl=',
            'Tags=',
            '',
            '[Network]',
            'GamePort=28015',
            'QueryPort=28017',
            '',
            '[RCON]',
            'Enabled=True',
            'Port=28016',
            'Password=',
            'Web=True',
            '',
            '[Advanced]',
            'ExtraStartupArguments='
        )
        Set-Content -LiteralPath $serverSettingsPath -Value $lines -Encoding UTF8
    }

    return [pscustomobject]@{
        GameId             = 'Rust'
        InstallPath        = [string]$definition.InstallPath
        TemplateRoot       = $templateRoot
        TemplateConfigRoot = $templateConfigRoot
        BootstrapPerformed = $false
        GeneratedConfigFiles = @('ServerSettings.ini')
    }
}



function Initialize-UGSMGameRustProfile {
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

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $Instance = [pscustomobject]@{ Name = $ProfileName; InstallPath = $InstallPath; Id = ($ProfileName -replace '[^A-Za-z0-9_.-]', '-').ToLowerInvariant() }
    }

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    if ((Test-Path -LiteralPath $paths.ProfileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $paths.ProfileRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($dir in @($paths.ProfileRoot, $paths.ConfigRoot, $paths.ServerDataRoot, $paths.ServerCfgRoot, $paths.LogRoot, $paths.CentralLogRoot)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $gamePort = Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'GamePort' -Default 28015
    $queryPort = Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'QueryPort' -Default 28017
    $rconPort = Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'RconPort' -Default 28016

    if (-not (Test-Path -LiteralPath $paths.ServerSettingsPath -PathType Leaf)) {
        $serverName = if ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) { [string]$Instance.Name } else { 'Rust Server' }
        $lines = @(
            '[General]',
            ('ServerName={0}' -f $serverName),
            'ServerDescription=UGSM Rust server',
            'MaxPlayers=50',
            'Level=Procedural Map',
            'Seed=12345',
            'WorldSize=3500',
            'SaveInterval=300',
            'HeaderImage=',
            'WebsiteUrl=',
            'Tags=',
            '',
            '[Network]',
            ('GamePort={0}' -f $gamePort),
            ('QueryPort={0}' -f $queryPort),
            '',
            '[RCON]',
            'Enabled=True',
            ('Port={0}' -f $rconPort),
            'Password=',
            'Web=True',
            '',
            '[Advanced]',
            'ExtraStartupArguments='
        )
        Set-Content -LiteralPath $paths.ServerSettingsPath -Value $lines -Encoding UTF8
    }

    return [pscustomobject]@{
        GameId             = 'Rust'
        InstanceId         = [string]$Instance.Id
        ProfileName        = [string]$Instance.Name
        InstallPath        = [string]$Instance.InstallPath
        ProfileRoot        = [string]$paths.ProfileRoot
        RuntimeRoot        = [string]$paths.RuntimeRoot
        ConfigRoot         = [string]$paths.ConfigRoot
        SaveRoot           = [string]$paths.SaveRoot
        LogsRoot           = [string]$paths.LogRoot
        Initialized        = $true
        CopiedFiles        = @('Config\WindowsServer\ServerSettings.ini')
    }
}



function Test-UGSMGameRustInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    $definition = Get-UGSMGameRustInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $installPathExists = (-not [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) -and (Test-Path -LiteralPath ([string]$definition.InstallPath) -PathType Container)
    $exeExists = (-not [string]::IsNullOrWhiteSpace([string]$definition.ServerExecutablePath)) -and (Test-Path -LiteralPath ([string]$definition.ServerExecutablePath) -PathType Leaf)

    $missing = New-Object System.Collections.Generic.List[string]
    if (-not $installPathExists) { [void]$missing.Add([string]$definition.InstallPath) }
    if (-not $exeExists) { [void]$missing.Add('RustDedicated.exe') }

    return [pscustomobject]@{
        GameId                 = 'Rust'
        InstallPath            = [string]$definition.InstallPath
        InstallPathExists      = [bool]$installPathExists
        ServerExecutablePath   = [string]$definition.ServerExecutablePath
        ServerExecutableExists = [bool]$exeExists
        MissingItems           = @($missing)
        IsInstalled            = [bool]($installPathExists -and $exeExists)
        IsValid                = [bool]($installPathExists -and $exeExists -and $missing.Count -eq 0)
        NeedsRepair            = [bool]($installPathExists -and -not $exeExists)
        Success                = [bool]($installPathExists -and $exeExists)
        Message                = if ($installPathExists -and $exeExists) { 'Rust Dedicated Server install detected.' } else { 'Rust Dedicated Server was not detected.' }
    }
}



function Get-UGSMGameRustAssignedPort {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][string]$Name, [int]$Default)

    foreach ($propName in @('Ports','AssignedPorts')) {
        if (-not ($Instance.PSObject.Properties[$propName])) { continue }
        $ports = $Instance.$propName
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) {
            $entry = $ports[$Name]
            if ($entry -is [int]) { return [int]$entry }
            if ($entry -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
            if ($entry -as [int]) { return [int]$entry }
        }
        elseif ($ports -and $ports.PSObject.Properties[$Name] -and ($ports.$Name -as [int])) { return [int]$ports.$Name }
        elseif ($ports) {
            foreach ($entry in @($ports)) {
                if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
            }
        }
    }
    return $Default
}

function Get-UGSMGameRustLaunchSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    $ini = Read-UGSMGameRustIniFile -Path $paths.ServerSettingsPath
    $identity = [string]$paths.Identity

    $settings = [pscustomobject]@{
        ServerName   = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'ServerName' -DefaultValue ([string]$Instance.Name))
        Description  = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'ServerDescription' -DefaultValue 'UGSM Rust server')
        MaxPlayers   = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'MaxPlayers' -DefaultValue 50)
        Level        = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'Level' -DefaultValue 'Procedural Map')
        Seed         = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'Seed' -DefaultValue '12345')
        WorldSize    = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'WorldSize' -DefaultValue 3500)
        SaveInterval = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'SaveInterval' -DefaultValue 300)
        HeaderImage  = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'HeaderImage' -DefaultValue '')
        WebsiteUrl   = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'WebsiteUrl' -DefaultValue '')
        Tags         = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'General' -Key 'Tags' -DefaultValue '')
        GamePort     = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'Network' -Key 'GamePort' -DefaultValue (Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'GamePort' -Default 28015))
        QueryPort    = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'Network' -Key 'QueryPort' -DefaultValue (Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'QueryPort' -Default 28017))
        RconPort     = [int](Get-UGSMGameRustIniValue -IniData $ini -Section 'RCON' -Key 'Port' -DefaultValue (Get-UGSMGameRustAssignedPort -Instance $Instance -Name 'RconPort' -Default 28016))
        RconPassword = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'RCON' -Key 'Password' -DefaultValue '')
        RconWeb      = [bool]::Parse(([string](Get-UGSMGameRustIniValue -IniData $ini -Section 'RCON' -Key 'Web' -DefaultValue 'True')))
        Identity     = $identity
        ExtraArgs    = [string](Get-UGSMGameRustIniValue -IniData $ini -Section 'Advanced' -Key 'ExtraStartupArguments' -DefaultValue '')
    }

    return $settings
}

function Save-UGSMGameRustServerCfgFromSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Settings)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Paths.RuntimeServerCfgPath) | Out-Null
    $lines = @(
        ('server.hostname "{0}"' -f ([string]$Settings.ServerName).Replace('"','\"')),
        ('server.description "{0}"' -f ([string]$Settings.Description).Replace('"','\"')),
        ('server.level "{0}"' -f ([string]$Settings.Level).Replace('"','\"')),
        ('server.seed "{0}"' -f ([string]$Settings.Seed).Replace('"','\"')),
        ('server.worldsize {0}' -f ([int]$Settings.WorldSize)),
        ('server.maxplayers {0}' -f ([int]$Settings.MaxPlayers)),
        ('server.port {0}' -f ([int]$Settings.GamePort)),
        ('server.queryport {0}' -f ([int]$Settings.QueryPort)),
        ('rcon.port {0}' -f ([int]$Settings.RconPort)),
        ('rcon.web {0}' -f ($(if ([bool]$Settings.RconWeb) { '1' } else { '0' }))),
        ('server.saveinterval {0}' -f ([int]$Settings.SaveInterval))
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.RconPassword)) { $lines += ('rcon.password "{0}"' -f ([string]$Settings.RconPassword).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.HeaderImage)) { $lines += ('server.headerimage "{0}"' -f ([string]$Settings.HeaderImage).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.WebsiteUrl)) { $lines += ('server.url "{0}"' -f ([string]$Settings.WebsiteUrl).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Tags)) { $lines += ('server.tags "{0}"' -f ([string]$Settings.Tags).Replace('"','\"')) }
    Set-Content -LiteralPath $Paths.RuntimeServerCfgPath -Value $lines -Encoding UTF8
}

function ConvertTo-UGSMGameRustArgString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][object]$Paths)

    $args = @(
        '-batchmode',
        '-nographics',
        '-logfile "-"',
        ('+server.identity "{0}"' -f ([string]$Settings.Identity).Replace('"','\"')),
        ('+server.hostname "{0}"' -f ([string]$Settings.ServerName).Replace('"','\"')),
        ('+server.description "{0}"' -f ([string]$Settings.Description).Replace('"','\"')),
        ('+server.level "{0}"' -f ([string]$Settings.Level).Replace('"','\"')),
        ('+server.seed "{0}"' -f ([string]$Settings.Seed).Replace('"','\"')),
        ('+server.worldsize {0}' -f ([int]$Settings.WorldSize)),
        ('+server.maxplayers {0}' -f ([int]$Settings.MaxPlayers)),
        ('+server.port {0}' -f ([int]$Settings.GamePort)),
        ('+server.queryport {0}' -f ([int]$Settings.QueryPort)),
        ('+rcon.port {0}' -f ([int]$Settings.RconPort)),
        ('+rcon.web {0}' -f ($(if ([bool]$Settings.RconWeb) { '1' } else { '0' }))),
        ('+server.saveinterval {0}' -f ([int]$Settings.SaveInterval))
    )
    # Do not put rcon.password on the command line. Rust echoes its command line to the server output log.
    # The password is written to server/<identity>/cfg/server.cfg instead, so RCON works without exposing the secret in logs.
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.HeaderImage)) { $args += ('+server.headerimage "{0}"' -f ([string]$Settings.HeaderImage).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.WebsiteUrl)) { $args += ('+server.url "{0}"' -f ([string]$Settings.WebsiteUrl).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Tags)) { $args += ('+server.tags "{0}"' -f ([string]$Settings.Tags).Replace('"','\"')) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraArgs)) { $args += [string]$Settings.ExtraArgs }
    return ($args -join ' ')
}

function New-UGSMGameRustLaunchWrapper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallPath, [Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Settings)

    New-Item -ItemType Directory -Force -Path $Paths.LogRoot, $Paths.CentralLogRoot | Out-Null

    $argString = ConvertTo-UGSMGameRustArgString -Settings $Settings -Paths $Paths
    $rustExe = Join-Path $InstallPath 'RustDedicated.exe'
    $outputLogPath = [string]$Paths.OutputLogPath
    $teeScriptPath = [System.IO.Path]::ChangeExtension([string]$Paths.LauncherPath, '.ps1')

    $teeLines = @(
        '$ErrorActionPreference = ''Continue''',
        ('Set-Location -LiteralPath "{0}"' -f $InstallPath.Replace('"','`"')),
        ('New-Item -ItemType Directory -Force -Path "{0}" | Out-Null' -f ([string]$Paths.LogRoot).Replace('"','`"')),
        ('Remove-Item -LiteralPath "{0}" -Force -ErrorAction SilentlyContinue' -f $outputLogPath.Replace('"','`"')),
        ('Write-Output "[UGSM] Rust launcher started. Identity={0}"' -f ([string]$Settings.Identity).Replace('"','`"')),
        ('& "{0}" {1} 2>&1 | Tee-Object -FilePath "{2}" -Append' -f $rustExe.Replace('"','`"'), $argString, $outputLogPath.Replace('"','`"')),
        '$exitCode = if ($null -ne $global:LASTEXITCODE) { [int]$global:LASTEXITCODE } else { 0 }',
        'Write-Output "[UGSM] Rust launcher exited with code $exitCode."',
        'exit $exitCode'
    )
    Set-Content -LiteralPath $teeScriptPath -Value $teeLines -Encoding UTF8

    $lines = @(
        '@echo off',
        'setlocal enableextensions',
        ('cd /d "{0}"' -f $InstallPath),
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $teeScriptPath),
        'set EXITCODE=%ERRORLEVEL%',
        'exit /b %EXITCODE%'
    )
    Set-Content -LiteralPath $Paths.LauncherPath -Value $lines -Encoding ASCII
    return $Paths.LauncherPath
}

function Update-UGSMGameRustNormalizedInstanceFields {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][object]$Settings)

    foreach ($pair in @(
        @{ Name='ServerName'; Value=[string]$Settings.ServerName },
        @{ Name='PublicServerName'; Value=[string]$Settings.ServerName },
        @{ Name='DisplayName'; Value=[string]$Settings.ServerName },
        @{ Name='MaxPlayers'; Value=[int]$Settings.MaxPlayers },
        @{ Name='ServerMaxPlayers'; Value=[int]$Settings.MaxPlayers },
        @{ Name='GamePort'; Value=[int]$Settings.GamePort },
        @{ Name='QueryPort'; Value=[int]$Settings.QueryPort },
        @{ Name='RconPort'; Value=[int]$Settings.RconPort }
    )) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }
}


function Sync-UGSMGameRustDiscordMirrorFields {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Ensure-UGSMGameRustInstanceDiscordShape -Instance $Instance)

    $show = $false
    $notifyStart = $false
    $notifyStop = $false
    if ($Instance.PSObject.Properties['Discord'] -and $null -ne $Instance.Discord) {
        if ($Instance.Discord.PSObject.Properties['ShowInDashboard']) { $show = [bool]$Instance.Discord.ShowInDashboard }
        if ($Instance.Discord.PSObject.Properties['NotifyOnStart']) { $notifyStart = [bool]$Instance.Discord.NotifyOnStart }
        if ($Instance.Discord.PSObject.Properties['NotifyOnStop']) { $notifyStop = [bool]$Instance.Discord.NotifyOnStop }
    }

    foreach ($pair in @(
        @{ Name='DiscordVisible'; Value=$show },
        @{ Name='DiscordNotifyStart'; Value=$notifyStart },
        @{ Name='DiscordNotifyStop'; Value=$notifyStop }
    )) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }

    return $Instance
}

function Set-UGSMGameRustRuntimePlayerCountFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][int]$CurrentPlayers,
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
        @{ Name='PlayerCountSource'; Value=[string]$Source },
        @{ Name='PlayerCountStatus'; Value=[string]$Status },
        @{ Name='PlayerCountUpdatedUtc'; Value=[DateTime]::UtcNow.ToString('o') }
    )

    if ($null -ne $MaxPlayers -and [int]$MaxPlayers -gt 0) {
        $pairs += @(
            @{ Name='MaxPlayers'; Value=[int]$MaxPlayers },
            @{ Name='ServerMaxPlayers'; Value=[int]$MaxPlayers }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Detail)) {
        $pairs += @{ Name='PlayerCountDetail'; Value=[string]$Detail }
    }

    foreach ($pair in $pairs) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }
}


function Get-UGSMGameRustCurrentPlayerCountFromOutputLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [int]$MaxLines = 1200
    )

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    $logPath = [string]$paths.OutputLogPath

    if ([string]::IsNullOrWhiteSpace($logPath) -or -not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        return [pscustomobject]@{
            Success        = $false
            Status         = 'NoLog'
            CurrentPlayers = 0
            MaxPlayers     = $null
            Source         = 'RUST_OUTPUT_LOG_JOIN_TRACKER'
            Detail         = 'Rust output log was not found.'
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
            MaxPlayers     = $null
            Source         = 'RUST_OUTPUT_LOG_JOIN_TRACKER'
            Detail         = 'Rust output log could not be read.'
        }
    }

    # The console status line is ideal, but Rust does not always write it to -logfile.
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = [string]$lines[$i]
        if ($line -match '\[\s*(?<players>\d+)\s*/\s*(?<max>\d+)\s*\]\s+Rust\s+\[') {
            return [pscustomobject]@{
                Success        = $true
                Status         = 'OK'
                CurrentPlayers = [int]$Matches['players']
                MaxPlayers     = [int]$Matches['max']
                Source         = 'RUST_OUTPUT_LOG_STATUS_LINE'
                Detail         = (Split-Path -Leaf $logPath)
            }
        }
    }

    # Fallback: count currently active players from join/spawn/disconnect lines.
    # Steam IDs are only used in memory to de-duplicate active sessions; they are not saved to the instance JSON.
    $active = @{}
    foreach ($rawLine in $lines) {
        $line = [string]$rawLine
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Rust writes player joins like:
        #   100.0.153.105:63132/7656119.../PlayerName joined [windows/7656119...]
        # The old parser only matched "steamid ... joined", so these real Rust join lines were ignored.
        if ($line -match '/(?<steamid>[0-9]{10,})/[^/\r\n]+?\s+joined\b') {
            $active[[string]$Matches['steamid']] = $true
            continue
        }

        if ($line -match '\bsteamid\s+(?<steamid>[0-9]{10,})\b.*\bjoined\b') {
            $active[[string]$Matches['steamid']] = $true
            continue
        }

        # Keep the player active once the spawn line appears, even if the join line was outside the tail window.
        if ($line -match '\[(?<steamid>[0-9]{10,})\]\s+has\s+spawned\b') {
            $active[[string]$Matches['steamid']] = $true
            continue
        }

        if ($line -match '/(?<steamid>[0-9]{10,})/[^/\r\n]+?\s+disconnecting\b') {
            $steamId = [string]$Matches['steamid']
            if ($active.ContainsKey($steamId)) { $active.Remove($steamId) }
            continue
        }

        if ($line -match '\b(?<steamid>[0-9]{10,})\b.*\b(disconnected|disconnecting|left)\b') {
            $steamId = [string]$Matches['steamid']
            if ($active.ContainsKey($steamId)) { $active.Remove($steamId) }
            continue
        }
    }

    return [pscustomobject]@{
        Success        = $true
        Status         = 'OK'
        CurrentPlayers = [int]$active.Count
        MaxPlayers     = $null
        Source         = 'RUST_OUTPUT_LOG_JOIN_TRACKER'
        Detail         = (Split-Path -Leaf $logPath)
    }
}


function Update-UGSMGameRustDiscordRuntimeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (-not $Instance) { return $Instance }

    try {
        $settings = Get-UGSMGameRustLaunchSettings -Instance $Instance
        Update-UGSMGameRustNormalizedInstanceFields -Instance $Instance -Settings $settings

        $maxPlayers = $null
        if ($settings -and $settings.PSObject.Properties['MaxPlayers']) { $maxPlayers = [int]$settings.MaxPlayers }

        $statusText = ''
        if ($Instance.PSObject.Properties['Status']) { $statusText = [string]$Instance.Status }
        if ($statusText.Trim().ToLowerInvariant() -notin @('running','online','started')) {
            Set-UGSMGameRustRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'RUST_OUTPUT_LOG_JOIN_TRACKER' -Status 'Stopped' -Detail ''
            Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null
            return $Instance
        }

        $result = Get-UGSMGameRustCurrentPlayerCountFromOutputLog -Instance $Instance
        if ($result -and [bool]$result.Success) {
            if ($null -ne $result.MaxPlayers -and [int]$result.MaxPlayers -gt 0) { $maxPlayers = [int]$result.MaxPlayers }
            Set-UGSMGameRustRuntimePlayerCountFields -Instance $Instance -CurrentPlayers ([int]$result.CurrentPlayers) -MaxPlayers $maxPlayers -Source ([string]$result.Source) -Status ([string]$result.Status) -Detail ([string]$result.Detail)
        }
        else {
            $status = if ($result) { [string]$result.Status } else { 'NoResult' }
            $detail = if ($result) { [string]$result.Detail } else { 'Rust player-count resolver returned no result.' }
            Set-UGSMGameRustRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $maxPlayers -Source 'RUST_OUTPUT_LOG_JOIN_TRACKER' -Status $status -Detail $detail
        }

        Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null
    }
    catch {
        try {
            Set-UGSMGameRustRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers $null -Source 'RUST_OUTPUT_LOG_JOIN_TRACKER' -Status 'Error' -Detail $_.Exception.Message
            Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null
        } catch {}
    }

    return $Instance
}


function Start-UGSMGameRustInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$InstallPath
    )

    if (-not $Instance) { throw 'Rust start failed: Instance was null.' }

    $installDef = Get-UGSMGameRustInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $installDef.ServerExecutablePath -PathType Leaf)) {
        throw 'Rust start failed: RustDedicated.exe was not found.'
    }

    Initialize-UGSMGameRustProfile -Instance $Instance | Out-Null
    $paths = Ensure-UGSMGameRustRuntimeLayout -Instance $Instance -InstallDefinition $installDef
    $settings = Get-UGSMGameRustLaunchSettings -Instance $Instance
    Save-UGSMGameRustServerCfgFromSettings -Paths $paths -Settings $settings

    $existingProcesses = @(Get-UGSMGameRustRunningServerProcesses -Instance $Instance -Paths $paths -InstallPath ([string]$installDef.InstallPath))
    if ($existingProcesses.Count -gt 0) {
        $serverProcess = @($existingProcesses | Where-Object { $_.Name -eq 'RustDedicated.exe' } | Select-Object -First 1)
        if (-not $serverProcess) { $serverProcess = @($existingProcesses | Select-Object -First 1) }

        foreach ($pair in @(
            @{ Name='Pid'; Value=[int]$serverProcess.Pid },
            @{ Name='ProcessId'; Value=[int]$serverProcess.Pid },
            @{ Name='Status'; Value='Running' },
            @{ Name='ProfilePath'; Value=[string]$paths.ProfileRoot }
        )) {
            if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
            else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
        }

        Update-UGSMGameRustNormalizedInstanceFields -Instance $Instance -Settings $settings
        [void](Sync-UGSMGameRustDiscordMirrorFields -Instance $Instance)
        Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null
        return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=[int]$serverProcess.Pid; Pid=[int]$serverProcess.Pid; AlreadyRunning=$true }
    }

    Update-UGSMGameRustNormalizedInstanceFields -Instance $Instance -Settings $settings
    [void](Sync-UGSMGameRustDiscordMirrorFields -Instance $Instance)

    $launcherPath = New-UGSMGameRustLaunchWrapper -InstallPath ([string]$installDef.InstallPath) -Paths $paths -Settings $settings

    try {
        $safeHeader = @(
            ('[{0}] UGSM starting Rust.' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
            ('Identity: {0}' -f ([string]$settings.Identity)),
            ('GamePort: {0}' -f ([int]$settings.GamePort)),
            ('QueryPort: {0}' -f ([int]$settings.QueryPort)),
            ('RconPort: {0}' -f ([int]$settings.RconPort)),
            ''
        )
        Set-Content -LiteralPath $paths.LaunchLogPath -Value $safeHeader -Encoding UTF8
    } catch {}

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.WorkingDirectory = [string]$installDef.InstallPath
    $psi.Arguments = '/d /k "' + $launcherPath + '"'
    $psi.UseShellExecute = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'Rust start failed: process failed to start.' }

    Start-Sleep -Seconds 5
    try { $process.Refresh() } catch {}
    if ($process.HasExited) { throw ('Rust start failed: process exited immediately. Check {0}.' -f $paths.LaunchLogPath) }

    foreach ($pair in @(
        @{ Name='Pid'; Value=[int]$process.Id },
        @{ Name='ProcessId'; Value=[int]$process.Id },
        @{ Name='Status'; Value='Running' },
        @{ Name='ProfilePath'; Value=[string]$paths.ProfileRoot }
    )) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }

    try {
        Set-UGSMGameRustRuntimePlayerCountFields -Instance $Instance -CurrentPlayers 0 -MaxPlayers ([int]$settings.MaxPlayers) -Source 'RUST_OUTPUT_LOG_JOIN_TRACKER' -Status 'Pending' -Detail 'Waiting for Rust output log.'
    } catch {}

    try {
        $runtimeData = [pscustomobject]@{
            InstanceId   = [string]$Instance.Id
            GameId       = 'Rust'
            ProfilePath  = [string]$paths.ProfileRoot
            Identity     = [string]$settings.Identity
            Pid          = [int]$process.Id
            StartedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $runtimeData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $paths.RuntimeMarkerPath -Encoding UTF8
    } catch {}

    Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch {}
    }

    return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=[int]$process.Id; Pid=[int]$process.Id }
}



function Stop-UGSMGameRustInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (-not $Instance) { throw 'Rust stop failed: Instance was null.' }
    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    $identity = [string]$paths.Identity
    $targetProcessId = 0
    foreach ($propName in @('Pid','ProcessId')) {
        if ($Instance.PSObject.Properties[$propName] -and ($Instance.$propName -as [int])) { $targetProcessId = [int]$Instance.$propName; break }
    }

    $stopped = $false
    if ($targetProcessId -gt 0) {
        try {
            $proc = Get-Process -Id $targetProcessId -ErrorAction Stop
            try { if ($proc.CloseMainWindow()) { $stopped = $proc.WaitForExit(15000) } } catch {}
            if (-not $stopped) { Stop-Process -Id $targetProcessId -Force -ErrorAction Stop; $stopped = $true }
        } catch [System.ArgumentException] { $stopped = $true } catch { Write-UGSMGameRustLog -Level 'WARN' -Message 'Rust tracked process stop failed.' -Exception $_.Exception }
    }

    try {
        Get-CimInstance Win32_Process -Filter "name = 'RustDedicated.exe' or name = 'cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [Regex]::Escape($identity) -and $_.CommandLine -match 'RustDedicated|UGSM_Start_Rust' } |
            ForEach-Object { Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue; $stopped = $true }
    } catch {}

    foreach ($pair in @(
        @{ Name='Status'; Value='Stopped' },
        @{ Name='Pid'; Value=$null },
        @{ Name='ProcessId'; Value=$null },
        @{ Name='CurrentPlayers'; Value=0 },
        @{ Name='PlayerCount'; Value=0 },
        @{ Name='OnlinePlayers'; Value=0 },
        @{ Name='PlayersOnline'; Value=0 },
        @{ Name='PlayerCountStatus'; Value='Stopped' },
        @{ Name='PlayerCountUpdatedUtc'; Value=[DateTime]::UtcNow.ToString('o') }
    )) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }

    try { if (Test-Path -LiteralPath $paths.RuntimeMarkerPath -PathType Leaf) { Remove-Item -LiteralPath $paths.RuntimeMarkerPath -Force -ErrorAction SilentlyContinue } } catch {}
    [void](Sync-UGSMGameRustDiscordMirrorFields -Instance $Instance)
    Save-UGSMGameRustInstanceDefinition -Instance $Instance | Out-Null

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch {}
    }

    return [pscustomobject]@{ Success=$true; Status='Stopped'; Stopped=[bool]$stopped }
}



function Register-UGSMGameRustModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameRustMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameRustMetadata'
            TestInstall       = 'Test-UGSMGameRustInstall'
            TestInstance      = 'Test-UGSMGameRustInstance'
            EnsureTemplate    = 'Ensure-UGSMGameRustTemplate'
            InitializeProfile = 'Initialize-UGSMGameRustProfile'
            Start             = 'Start-UGSMGameRustInstance'
            Stop              = 'Stop-UGSMGameRustInstance'

            BuildEditor       = 'New-UGSMGameRustInstanceEditor'
            SaveEditor        = 'Save-UGSMGameRustInstanceEditor'
        }
    }
}


function Get-UGSMGameRustBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameRustProfilePaths -Instance $Instance

        $settingsTargets = @(
            @{ Path = $paths.ServerSettingsPath;          Relative = 'Config\WindowsServer\ServerSettings.ini'; Label = 'Rust server settings INI' },
            @{ Path = $paths.GameplayJsonPath;            Relative = 'Config\WindowsServer\Gameplay.json';      Label = 'Rust gameplay JSON' },
            @{ Path = $paths.GameplayXmlPath;             Relative = 'Config\WindowsServer\Gameplay.xml';       Label = 'Rust gameplay XML' },
            @{ Path = $paths.ServerCfgPath;               Relative = 'Config\WindowsServer\Server.cfg';          Label = 'Rust server CFG' },
            @{ Path = $paths.AdminUsersPath;              Relative = 'Config\WindowsServer\AdminUsers.txt';     Label = 'Rust admin users list' },
            @{ Path = $paths.ExclusiveUsersPath;          Relative = 'Config\WindowsServer\ExclusiveUsers.txt'; Label = 'Rust exclusive users list' },
            @{ Path = $paths.WhitelistedUsersPath;        Relative = 'Config\WindowsServer\WhitelistedUsers.txt'; Label = 'Rust whitelist users list' },
            @{ Path = $paths.BannedUsersPath;             Relative = 'Config\WindowsServer\BannedUsers.txt';    Label = 'Rust banned users list' },
            @{ Path = $paths.SilencedUsersPath;           Relative = 'Config\WindowsServer\SilencedUsers.txt';  Label = 'Rust silenced users list' }
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
        #     Label        = 'Rust managed mods manifest'
        # })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameRustManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'Rust managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameRustBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'Rust' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameRustLog -Level 'WARN' -Message ('Rust managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameRustProfilePaths {
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
        $profileRoot = Get-UGSMGameRustProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'Rust' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'Rust profile paths could not be resolved for the selected instance.'
    }

    $profileName = if ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) { [string]$Instance.Name } else { Split-Path -Leaf $profileRoot }
    $identity = ($profileName -replace '[^A-Za-z0-9_.-]', '_')
    if ([string]::IsNullOrWhiteSpace($identity)) { $identity = 'Rust1' }

    $configRoot = Join-Path $profileRoot 'Config\WindowsServer'
    $serverDataRoot = Join-Path $profileRoot 'ServerData'
    $serverCfgRoot = Join-Path $serverDataRoot 'cfg'
    $logsRoot = Join-Path $profileRoot 'Logs'
    # Keep Rust runtime/server logs with the profile so removing a profile cleans its server logs too.
    # CentralLogRoot is kept as a compatibility alias for older helper paths.
    $centralLogRoot = $logsRoot

    [pscustomobject]@{
        ProfileName                 = $profileName
        Identity                    = $identity
        ProfileRoot                 = $profileRoot
        ProfileConfigRoot           = $configRoot
        ProfileSaveRoot             = $serverDataRoot
        ProfileLogRoot              = $logsRoot
        RuntimeRoot                 = $profileRoot
        RuntimeConfigRoot           = $configRoot
        RuntimeSaveRoot             = $serverDataRoot
        RuntimeLogRoot              = $logsRoot
        RuntimeMarkerPath           = Join-Path $serverDataRoot 'UGSM.Runtime.json'
        IsRuntimeActive             = (Test-Path -LiteralPath (Join-Path $serverDataRoot 'UGSM.Runtime.json') -PathType Leaf)
        ConfigRoot                  = $configRoot
        SaveRoot                    = $serverDataRoot
        LogRoot                     = $logsRoot
        ServerDataRoot              = $serverDataRoot
        ServerCfgRoot               = $serverCfgRoot
        CentralLogRoot              = $centralLogRoot
        PrimaryIniPath              = Join-Path $configRoot 'ServerSettings.ini'
        PrimaryCfgPath              = Join-Path $configRoot 'server.cfg'
        ServerSettingsPath          = Join-Path $configRoot 'ServerSettings.ini'
        ServerCfgPath               = Join-Path $configRoot 'server.cfg'
        RuntimeServerCfgPath        = Join-Path $serverCfgRoot 'server.cfg'
        LauncherPath                = Join-Path $logsRoot 'UGSM_Start_Rust.cmd'
        LaunchLogPath               = Join-Path $logsRoot 'server-launch.log'
        OutputLogPath               = Join-Path $logsRoot 'rust-server-output.log'
        AdminUsersPath              = Join-Path $configRoot 'AdminUsers.txt'
        WhitelistedUsersPath        = Join-Path $configRoot 'Whitelist.txt'
        BannedUsersPath             = Join-Path $configRoot 'Bans.txt'
        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $null
        DatabasePath                = $null
    }
}



function Read-UGSMGameRustIniFile {
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

function Get-UGSMGameRustIniValue {
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

function Set-UGSMGameRustIniValue {
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

function Read-UGSMGameRustStringListFile {
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

function Write-UGSMGameRustStringListFile {
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


function Ensure-UGSMGameRustParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameRustJsonFile {
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

function Write-UGSMGameRustJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameRustParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGameRustXmlFile {
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

function Write-UGSMGameRustXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameRustParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameRustCfgFile {
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

function Set-UGSMGameRustCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameRustParentDirectory -Path $Path

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
function Test-UGSMGameRustPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameRustPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameRustPSSQLiteInstalled)
}

function Get-UGSMGameRustElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameRustPSSQLiteInstalled)) {
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

function Save-UGSMGameRustElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameRustPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'Rust.db was not found.'
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


function Resolve-UGSMGameRustEditorFieldPath {
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

function ConvertTo-UGSMGameRustEditorFieldValue {
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
            return [bool]$Control.Checked
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


function Get-UGSMGameRustInstanceDefinitionPath {
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

function Save-UGSMGameRustInstanceDefinition {
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

    $definitionPath = Get-UGSMGameRustInstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameRustInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameRustInstanceDiscordShape -Instance $Instance
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

    Invoke-UGSMGameRustManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before Rust settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameRustEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameRustEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("Rust save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameRustStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control
                Set-UGSMGameRustIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control
                Set-UGSMGameRustIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control
                Set-UGSMGameRustIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control
                Set-UGSMGameRustIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Password' {
                $value = ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control
                Set-UGSMGameRustIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameRustEditorFieldValue -Field $field -Control $control)
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
            [void](Save-UGSMGameRustInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    try {
        $settingsAfterSave = Get-UGSMGameRustLaunchSettings -Instance $updatedInstance
        Update-UGSMGameRustNormalizedInstanceFields -Instance $updatedInstance -Settings $settingsAfterSave
        [void](Sync-UGSMGameRustDiscordMirrorFields -Instance $updatedInstance)
        [void](Save-UGSMGameRustInstanceDefinition -Instance $updatedInstance)
    } catch {}

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved Rust settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameRustInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Instance = Ensure-UGSMGameRustInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    $schema = Get-UGSMGameRustEditorSchema
    $iniData = Read-UGSMGameRustIniFile -Path $paths.ServerSettingsPath
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

    function Get-RustSafeIniValue {
        param([hashtable]$Field)
        try {
            return [string](Get-UGSMGameRustIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'Rust field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-RustSafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'Rust instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-RustTextBox {
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

    function New-RustStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-RustTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-RustNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-RustElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits Rust.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMGameRustPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in Rust.db.')
                return
            }

            $dbPath = Resolve-UGSMGameRustDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('Rust.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('Rust.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameRustElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading Rust.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameRustPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameRustDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'Rust.db path could not be resolved for this instance.' }
                    Save-UGSMGameRustElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to Rust.db: ' + $dbPath }
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

    function Add-RustFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the rust editor can render any supported schema shape.
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
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameRustModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the rust Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-RustNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-RustSafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-RustNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-RustSafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-RustNarrowHost
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
                    $rawValue = Get-RustSafeIniValue -Field $Field
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
                    $control = New-RustStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-RustSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-RustStretchTextBox -MaskSecret
                    $control.Text = [string](Get-RustSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-RustStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-RustSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-RustTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameRustEditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-RustNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'Rust action failed: ' + $_.Exception.Message } }
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

                    New-RustElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-RustStretchTextBox
                    $control.Text = [string](Get-RustSafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('Rust field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Danger
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-RustEditorContent {
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
            Add-RustFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('Rust Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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
            $tabPage.BackColor = $Theme.Background
            [void]$tabs.TabPages.Add($tabPage)

            # Mods tab is owned by UGSM_Game_Helper.ps1. The game module only creates
            # the TabPage host and passes the instance/mod definition into the shared renderer.
            if ([string]$tabDef.Title -eq 'Mods') {
                $modsTabFeatures = Get-UGSMGameRustSupportedFeatures
                if ([bool]$modsTabFeatures.Mods) {
                    try {
                        $modsDefinition = Get-UGSMGameRustModsDefinition
                        $modTabMode = ''
                        try {
                            if ($modsDefinition -and $modsDefinition.PSObject.Properties['ModTabMode']) { $modTabMode = [string]$modsDefinition.ModTabMode }
                        } catch { $modTabMode = '' }

                        if ($modTabMode -eq 'FrameworkPlugin') {
                            $frameworkRenderer = Get-Command -Name New-UGSMSharedFrameworkPluginModsEditor -CommandType Function -ErrorAction SilentlyContinue
                            if ($frameworkRenderer) {
                                [void](New-UGSMSharedFrameworkPluginModsEditor -Parent $tabPage -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
                            }
                            else {
                                $missing = New-UGSMLabel -Text 'Shared framework/plugin Mods editor is not loaded. Load UGSM_Game_Helper.ps1 before opening this tab.' -X 12 -Y 12 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
                                [void]$tabPage.Controls.Add($missing)
                            }
                        }
                        else {
                            $sharedRenderer = Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue
                            if ($sharedRenderer) {
                                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $tabPage -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
                            }
                            else {
                                $missing = New-UGSMLabel -Text 'Shared Mods editor is not loaded. Load UGSM_Game_Helper.ps1 before opening this tab.' -X 12 -Y 12 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
                                [void]$tabPage.Controls.Add($missing)
                            }
                        }
                    }
                    catch {
                        $err = New-UGSMLabel -Text ('Rust shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color $Theme.Danger
                        [void]$tabPage.Controls.Add($err)
                        if ($StatusLabel) { $StatusLabel.Text = 'Rust shared Mods tab failed: ' + $_.Exception.Message }
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
                    New-RustEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-RustEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameRustInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved Rust profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'Rust save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameRustInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'Rust profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'Rust reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'Rust profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameRustOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'Rust open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("Rust open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'Rust open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("Rust open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("Rust open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameRustEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'Rust action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameRustProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("Rust action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("Rust action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameRustEditorAction {
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

    $resolvedPath = Resolve-UGSMGameRustEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameRustOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameRustEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenServerSettings = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameRustEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryIni' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened ServerSettings.ini.' }
        OpenServerCfg      = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameRustEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryCfg' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened server.cfg.' }
    }

    $tabs = @(
        [pscustomobject]@{
            Title = 'General'
            Description = 'Rust server identity and browser settings.'
            Fields = @(
                @{ Id = 'ServerName'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'ServerName'; Label = 'Server Name'; DefaultValue = 'Rust Server'; Hint = 'Public server name shown in the Rust browser and Discord.' }
                @{ Id = 'ServerDescription'; Type = 'MultilineText'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'ServerDescription'; Label = 'Description'; DefaultValue = 'UGSM Rust server'; Hint = 'Server description shown in the browser.' }
                @{ Id = 'MaxPlayers'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'MaxPlayers'; Label = 'Max Players'; DefaultValue = 50; Min = 1; Max = 1000; Decimals = 0; Hint = 'Maximum player slots.' }
                @{ Id = 'HeaderImage'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'HeaderImage'; Label = 'Header Image URL'; DefaultValue = ''; Hint = 'Optional Rust server header image URL.' }
                @{ Id = 'WebsiteUrl'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'WebsiteUrl'; Label = 'Website URL'; DefaultValue = ''; Hint = 'Optional server website URL.' }
                @{ Id = 'Tags'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'Tags'; Label = 'Server Tags'; DefaultValue = ''; Hint = 'Optional comma-separated Rust tags.' }
            )
        }
        [pscustomobject]@{
            Title = 'World'
            Description = 'Rust world generation and save settings.'
            Fields = @(
                @{ Id = 'Level'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'Level'; Label = 'Level'; DefaultValue = 'Procedural Map'; Hint = 'Example: Procedural Map.' }
                @{ Id = 'Seed'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'Seed'; Label = 'Seed'; DefaultValue = '12345'; Hint = 'Rust world seed.' }
                @{ Id = 'WorldSize'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'WorldSize'; Label = 'World Size'; DefaultValue = 3500; Min = 1000; Max = 6000; Decimals = 0; Hint = 'Rust map size.' }
                @{ Id = 'SaveInterval'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'General'; Key = 'SaveInterval'; Label = 'Save Interval Seconds'; DefaultValue = 300; Min = 30; Max = 3600; Decimals = 0; Hint = 'Rust server.saveinterval value.' }
            )
        }
        [pscustomobject]@{
            Title = 'Network / RCON'
            Description = 'Rust ports and RCON settings.'
            Fields = @(
                @{ Id = 'GamePort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Network'; Key = 'GamePort'; Label = 'Game Port'; DefaultValue = 28015; Min = 1; Max = 65535; Decimals = 0; Hint = 'Rust server.port UDP.' }
                @{ Id = 'QueryPort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'Network'; Key = 'QueryPort'; Label = 'Query Port'; DefaultValue = 28017; Min = 1; Max = 65535; Decimals = 0; Hint = 'Rust server.queryport UDP.' }
                @{ Id = 'RconEnabled'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Enabled'; Label = 'Enable RCON'; DefaultValue = $true; Hint = 'Enable RCON settings for Rust.' }
                @{ Id = 'RconPort'; Type = 'Number'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Port'; Label = 'RCON Port'; DefaultValue = 28016; Min = 1; Max = 65535; Decimals = 0; Hint = 'Rust RCON TCP/WebSocket port.' }
                @{ Id = 'RconPassword'; Type = 'Password'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Password'; Label = 'RCON Password'; DefaultValue = ''; Hint = 'Rust RCON password. Masked on screen and never logged.' }
                @{ Id = 'RconWeb'; Type = 'Boolean'; File = 'ServerSettings.ini'; Section = 'RCON'; Key = 'Web'; Label = 'RCON Web'; DefaultValue = $true; Hint = 'Rust normally uses WebSocket RCON.' }
            )
        }
        [pscustomobject]@{
            Title = 'Advanced'
            Description = 'Manual Rust launch/config access.'
            Fields = @(
                @{ Id = 'ExtraStartupArguments'; Type = 'Text'; File = 'ServerSettings.ini'; Section = 'Advanced'; Key = 'ExtraStartupArguments'; Label = 'Extra Startup Arguments'; DefaultValue = ''; Hint = 'Optional extra Rust command-line arguments. Do not put secrets here unless required.' }
                @{ Id = 'OpenServerSettings'; Type = 'ActionButton'; Label = 'ServerSettings.ini'; ButtonText = 'Open ServerSettings.ini'; Action = $actions.OpenServerSettings; Hint = 'Opens the UGSM-managed Rust settings INI.' }
                @{ Id = 'OpenServerCfg'; Type = 'ActionButton'; Label = 'server.cfg'; ButtonText = 'Open generated server.cfg'; Action = $actions.OpenServerCfg; Hint = 'Opens the generated Rust server.cfg.' }
            )
        }
        [pscustomobject]@{
            Title = 'Mods'
            Description = 'Rust uMod/Oxide framework and plugin handling. Framework install will require a confirmation warning before it modifies server files.'
            UsesSharedModsEditor = $true
            Fields = @()
        }
        [pscustomobject]@{
            Title = 'Discord'
            Description = 'UGSM per-server Discord override settings. Empty private webhook uses the global webhook; new private values are masked and stored in UGSM secrets, not in the instance JSON.'
            Fields = @(
                @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Secret = $true; Hint = 'Optional per-server webhook override. Leave blank to clear/use global. New values are hidden on screen and saved into the UGSM secrets store; instance JSON keeps safe metadata only.' }
                @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $true; Hint = 'Show this server in the Discord dashboard.' }
                @{ Id = 'DiscordTestWebhook'; Type = 'ActionButton'; Label = 'Test Discord Webhook'; ButtonText = 'Send Test Message'; Hint = 'Sends a test message using the saved per-server secret webhook if set, otherwise the global webhook.'; Action = {
                    param($Instance, $Paths, $StatusLabel)
                    try {
                        $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
                        if (-not $discordModel.HasWebhook) { if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook configured.' }; return }
                        $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('Rust ' + [string]$Instance.Name)
                        if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) { if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully.' } }
                        else { if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed.' } }
                    } catch { if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message } }
                } }
            )
        }
    )

    return [pscustomobject]@{ Version = 2; Tabs = $tabs }
}


